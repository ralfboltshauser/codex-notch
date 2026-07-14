import CodexNotchCore
import Foundation
import Network

final class TailscaleListener {
    static let defaultPort: NWEndpoint.Port = 47391
    static let maximumFrameSize = 4096

    private let pairings: PairingStore
    private let delivery: (CompletionEvent) -> CompletionAcceptance
    private let queue = DispatchQueue(label: "com.ralfbuilds.codex-notch.tailscale")
    private var listener: NWListener?

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
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: port)
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                FileHandle.standardError.write(Data("Codex Notch listener failed: \(error)\n".utf8))
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
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
