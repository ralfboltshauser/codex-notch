import CodexNotchCore
import Foundation
import Network

private final class ListenerStartupState {
    enum Outcome {
        case ready
        case failed(Error)
    }

    private let lock = NSLock()
    private var storedOutcome: Outcome?

    func resolve(_ outcome: Outcome) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedOutcome == nil else { return false }
        storedOutcome = outcome
        return true
    }

    var outcome: Outcome? {
        lock.lock()
        defer { lock.unlock() }
        return storedOutcome
    }
}

private final class ListenerShutdownState {
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var resolved = false

    init() { group.enter() }

    func resolve() {
        lock.lock()
        guard !resolved else { lock.unlock(); return }
        resolved = true
        lock.unlock()
        group.leave()
    }

    func wait(timeout: TimeInterval) {
        _ = group.wait(timeout: .now() + max(0.1, timeout))
    }
}

final class TailscaleListener {
    static let defaultPort: NWEndpoint.Port = 47391
    static let maximumFrameSize = 4096

    private let pairings: PairingStore
    private let delivery: (CompletionEvent) -> CompletionAcceptance
    private let queue = DispatchQueue(label: "com.ralfbuilds.codex-notch.tailscale")
    private var listener: NWListener?
    private var startup: ListenerStartupState?
    private var startupGroup: DispatchGroup?
    private var shutdown: ListenerShutdownState?

    init(
        pairings: PairingStore,
        delivery: @escaping (CompletionEvent) -> CompletionAcceptance
    ) {
        self.pairings = pairings
        self.delivery = delivery
    }

    func start(host: String, port: NWEndpoint.Port = defaultPort) throws {
        stop()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: .any)
        let listener = try NWListener(using: parameters, on: port)
        let startup = ListenerStartupState()
        let startupGroup = DispatchGroup()
        let shutdown = ListenerShutdownState()
        startupGroup.enter()
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if startup.resolve(.ready) { startupGroup.leave() }
            case .failed(let error):
                FileHandle.standardError.write(Data("Codex Notch listener failed: \(error)\n".utf8))
                if startup.resolve(.failed(error)) { startupGroup.leave() }
                shutdown.resolve()
            case .cancelled:
                let error = NSError(
                    domain: "CodexNotch",
                    code: 31,
                    userInfo: [NSLocalizedDescriptionKey: "The Tailscale receiver was cancelled before it became ready"]
                )
                if startup.resolve(.failed(error)) { startupGroup.leave() }
                shutdown.resolve()
            default:
                break
            }
        }
        self.listener = listener
        self.startup = startup
        self.startupGroup = startupGroup
        self.shutdown = shutdown
        listener.start(queue: queue)
    }

    func waitUntilReady(timeout: TimeInterval = 3) throws {
        guard let startup, let startupGroup else {
            throw NSError(
                domain: "CodexNotch",
                code: 34,
                userInfo: [NSLocalizedDescriptionKey: "The Tailscale receiver has not been started"]
            )
        }
        guard startupGroup.wait(timeout: .now() + max(0.1, timeout)) == .success else {
            stop()
            throw NSError(
                domain: "CodexNotch",
                code: 30,
                userInfo: [NSLocalizedDescriptionKey: "The Tailscale receiver did not become ready in time"]
            )
        }
        guard let outcome = startup.outcome else {
            stop()
            throw NSError(
                domain: "CodexNotch",
                code: 35,
                userInfo: [NSLocalizedDescriptionKey: "The Tailscale receiver returned no startup state"]
            )
        }
        if case .failed(let error) = outcome {
            throw NSError(
                domain: "CodexNotch",
                code: 32,
                userInfo: [NSLocalizedDescriptionKey: "Could not start the Tailscale receiver: \(error.localizedDescription)"]
            )
        }
    }

    func stop() {
        let listener = self.listener
        let shutdown = self.shutdown
        self.listener = nil
        startup = nil
        startupGroup = nil
        self.shutdown = nil
        listener?.cancel()
        shutdown?.wait(timeout: 1)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        receiveExact(4, from: connection) { [weak self] header in
            guard let self, let header else { connection.cancel(); return }
            let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= Self.maximumFrameSize else {
                self.send(.rejected("invalid frame length"), over: connection)
                return
            }
            self.receiveExact(Int(length), from: connection) { payload in
                guard let payload else { connection.cancel(); return }
                self.process(payload, over: connection)
            }
        }
    }

    private func process(_ payload: Data, over connection: NWConnection) {
        guard let envelope = try? JSONDecoder.codexNotch.decode(RemoteEnvelope.self, from: payload),
              envelope.protocolVersion == 1 else {
            send(.rejected("invalid protocol envelope"), over: connection)
            return
        }
        guard let host = pairings.host(authenticating: envelope.token) else {
            send(.rejected("authentication failed"), over: connection)
            return
        }
        if envelope.kind == "ping" {
            send(.pong, over: connection)
            return
        }
        guard envelope.kind == "completion", let received = envelope.event else {
            send(.rejected("unsupported message kind"), over: connection)
            return
        }

        let event = CompletionEvent(
            schemaVersion: received.schemaVersion,
            eventID: received.eventID,
            threadID: received.threadID,
            turnID: received.turnID,
            title: CompletionEvent.cleanTitle(received.title),
            sourceID: host.id,
            sourceLabel: host.label,
            completedAt: received.completedAt
        )
        guard event.isValid else {
            send(.rejected("invalid completion event", eventID: received.eventID), over: connection)
            return
        }
        switch DispatchQueue.main.sync(execute: { delivery(event) }) {
        case .accepted:
            send(.accepted(eventID: event.eventID, duplicate: false), over: connection)
        case .duplicate:
            send(.accepted(eventID: event.eventID, duplicate: true), over: connection)
        case .rejected:
            send(.rejected("event could not be persisted", eventID: event.eventID), over: connection)
        }
    }

    private func send(_ acknowledgement: RemoteAcknowledgement, over connection: NWConnection) {
        guard let payload = try? JSONEncoder.codexNotch.encode(acknowledgement),
              payload.count <= Self.maximumFrameSize else {
            connection.cancel()
            return
        }
        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func receiveExact(
        _ count: Int,
        from connection: NWConnection,
        accumulated: Data = Data(),
        completion: @escaping (Data?) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: count - accumulated.count
        ) { [weak self] data, _, isComplete, error in
            guard self != nil, error == nil else { completion(nil); return }
            var result = accumulated
            if let data { result.append(data) }
            if result.count == count {
                completion(result)
            } else if isComplete || result.count > count {
                completion(nil)
            } else {
                self?.receiveExact(count, from: connection, accumulated: result, completion: completion)
            }
        }
    }
}
