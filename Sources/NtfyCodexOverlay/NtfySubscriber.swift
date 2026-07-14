import Foundation

final class NtfySubscriber: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private static let cursorKey = "ntfyCursor.v1"
    private static let seenKey = "seenEventIDs.v1"
    private static let maximumSeen = 1_000

    private let configuration: AppConfiguration
    private let defaults: UserDefaults
    private let delivery: (CompletedTask) -> Void
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.ralfbuilds.ntfy-codex-overlay.stream"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private lazy var session = URLSession(
        configuration: .ephemeral,
        delegate: self,
        delegateQueue: delegateQueue
    )
    private var streamTask: URLSessionDataTask?
    private var lineBuffer = Data()
    private var cursor: String?
    private var seenOrder: [String]
    private var seen: Set<String>
    private var retryDelay: TimeInterval = 1
    private var stopped = false

    init(
        topicURL: URL,
        defaults: UserDefaults = .standard,
        delivery: @escaping (CompletedTask) -> Void
    ) {
        self.configuration = AppConfiguration(topicURL: topicURL)
        self.defaults = defaults
        self.delivery = delivery
        self.cursor = defaults.string(forKey: Self.cursorKey)
        let stored = defaults.stringArray(forKey: Self.seenKey) ?? []
        self.seenOrder = stored
        self.seen = Set(stored)
        super.init()
    }

    func start() {
        delegateQueue.addOperation { [weak self] in
            guard let self, !self.stopped else { return }
            if let cursor = self.cursor {
                self.openStream(since: cursor)
            } else {
                self.fetchBaseline()
            }
        }
    }

    func stop() {
        delegateQueue.addOperation { [weak self] in
            self?.stopped = true
            self?.streamTask?.cancel()
            self?.streamTask = nil
        }
    }

    private func fetchBaseline() {
        guard let url = configuration.subscriptionURL(parameters: ["poll": "1", "since": "latest"]) else {
            scheduleReconnect()
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue("ntfy-codex-overlay/1", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            self.delegateQueue.addOperation {
                guard !self.stopped else { return }
                if let data, error == nil {
                    let ids = self.lines(in: data).compactMap(NtfyEventParser.messageID)
                    if let baseline = ids.last {
                        self.remember(baseline)
                        self.updateCursor(baseline)
                        self.openStream(since: baseline)
                    } else {
                        self.openStream(since: String(Int(Date().timeIntervalSince1970)))
                    }
                } else {
                    self.scheduleReconnect()
                }
            }
        }.resume()
    }

    private func openStream(since cursor: String) {
        guard !stopped,
              let url = configuration.subscriptionURL(parameters: ["since": cursor]) else { return }
        lineBuffer.removeAll(keepingCapacity: true)
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue("ntfy-codex-overlay/1", forHTTPHeaderField: "User-Agent")
        streamTask = session.dataTask(with: request)
        streamTask?.resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) {
            retryDelay = 1
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[..<newline]
            lineBuffer.removeSubrange(...newline)
            process(Data(line))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard task === streamTask else { return }
        streamTask = nil
        if !stopped { scheduleReconnect() }
    }

    private func process(_ data: Data) {
        guard let eventID = NtfyEventParser.messageID(from: data) else { return }
        updateCursor(eventID)
        guard !seen.contains(eventID) else { return }
        remember(eventID)
        guard let task = NtfyEventParser.task(from: data) else { return }
        DispatchQueue.main.async { [delivery] in delivery(task) }
    }

    private func updateCursor(_ eventID: String) {
        cursor = eventID
        defaults.set(eventID, forKey: Self.cursorKey)
    }

    private func remember(_ eventID: String) {
        guard seen.insert(eventID).inserted else { return }
        seenOrder.append(eventID)
        if seenOrder.count > Self.maximumSeen {
            let count = seenOrder.count - Self.maximumSeen
            let removed = Array(seenOrder.prefix(count))
            seenOrder.removeFirst(count)
            seen.subtract(removed)
        }
        defaults.set(seenOrder, forKey: Self.seenKey)
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 60)
        delegateQueue.addOperation { [weak self] in
            Thread.sleep(forTimeInterval: delay)
            guard let self, !self.stopped else { return }
            if let cursor = self.cursor {
                self.openStream(since: cursor)
            } else {
                self.fetchBaseline()
            }
        }
    }

    private func lines(in data: Data) -> [Data] {
        Array(data).split(separator: UInt8(0x0A)).map { Data($0) }
    }
}
