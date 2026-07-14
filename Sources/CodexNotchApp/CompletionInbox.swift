import CodexNotchCore
import Darwin
import Foundation

final class CompletionInbox {
    private let directory: URL
    private let delivery: (CompletionEvent) -> Bool
    private let queue = DispatchQueue(label: "com.ralfbuilds.codex-notch.inbox")
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1

    init(
        directory: URL = AppPaths.inbox,
        delivery: @escaping (CompletionEvent) -> Bool
    ) {
        self.directory = directory
        self.delivery = delivery
    }

    func start() throws {
        try AppPaths.prepareDirectory(directory)
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        self.source = source
        source.resume()
        queue.async { [weak self] in self?.drain() }
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func drain() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let event = try? JSONDecoder.codexNotch.decode(CompletionEvent.self, from: data),
                  event.isValid else {
                quarantine(file)
                continue
            }
            let accepted = DispatchQueue.main.sync { delivery(event) }
            if accepted { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func quarantine(_ file: URL) {
        let invalid = directory.appendingPathComponent("invalid", isDirectory: true)
        try? AppPaths.prepareDirectory(invalid)
        let destination = invalid.appendingPathComponent(file.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: file, to: destination)
    }
}
