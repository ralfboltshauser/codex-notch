import CodexNotchCore
import Darwin
import Network
import XCTest
@testable import CodexNotchApp

class CodexNotchTestCase: XCTestCase {
    let threadID = "019f5d4f-3a8d-76c0-8c2d-19451190e028"

    func makeEvent() -> CompletionEvent {
        CompletionEvent(
            eventID: CompletionEvent.eventID(threadID: threadID, turnID: "turn-1"),
            threadID: threadID,
            turnID: "turn-1",
            title: "Build the overlay",
            sourceID: "local",
            sourceLabel: "This Mac",
            completedAt: Date(timeIntervalSince1970: 1_784_035_200)
        )
    }

    func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-notch-\(UUID())")
        try! FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    func waitForMainQueue(seconds: TimeInterval) {
        let finished = expectation(description: "Main queue advanced")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: seconds + 1)
    }

    func hooksRoot(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    func unusedLoopbackPort() throws -> NWEndpoint.Port {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        XCTAssertEqual(inet_pton(AF_INET, "127.0.0.1", &address.sin_addr), 1)
        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindStatus == 0 else { throw POSIXError(.EADDRINUSE) }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameStatus = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameStatus == 0,
              let port = NWEndpoint.Port(
                rawValue: UInt16(bigEndian: boundAddress.sin_port)
              )
        else { throw POSIXError(.EIO) }
        return port
    }

    func socketRoundTrip(
        _ payload: Data,
        port: UInt16
    ) throws -> RemoteAcknowledgement {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        XCTAssertEqual(inet_pton(AF_INET, "127.0.0.1", &address.sin_addr), 1)
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard status == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        try sendAll(frame, descriptor: descriptor)
        let header = try receiveExact(4, descriptor: descriptor)
        let responseLength = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let response = try receiveExact(Int(responseLength), descriptor: descriptor)
        return try JSONDecoder.codexNotch.decode(
            RemoteAcknowledgement.self,
            from: response
        )
    }

    private func sendAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let amount = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset,
                    0
                )
                guard amount > 0 else { throw POSIXError(.EIO) }
                offset += amount
            }
        }
    }

    private func receiveExact(_ count: Int, descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        let received = data.withUnsafeMutableBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            var offset = 0
            while offset < count {
                let amount = Darwin.recv(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    count - offset,
                    0
                )
                if amount <= 0 { return -1 }
                offset += amount
            }
            return offset
        }
        guard received == count else { throw POSIXError(.EIO) }
        return data
    }
}
