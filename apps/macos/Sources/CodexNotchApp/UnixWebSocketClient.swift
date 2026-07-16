import CryptoKit
import Darwin
import Foundation
import Security

protocol AppServerSocketClient: AnyObject {
    var onText: ((Data) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }

    func start() throws
    func send(json: [String: Any]) throws
    func close()
}

/// Minimal RFC 6455 client for Codex App Server's local Unix-domain socket.
/// It deliberately supports text, ping/pong and close only; App Server JSON-RPC
/// never needs extensions, compression or binary messages here.
final class UnixWebSocketClient: AppServerSocketClient {
    enum ClientError: Error { case socket, pathTooLong, handshake, closed, invalidFrame }

    private let path: String
    private let callbackQueue: DispatchQueue
    private let readQueue = DispatchQueue(label: "com.ralfbuilds.codex-notch.websocket-read")
    private let writeLock = NSLock()
    private var descriptor: Int32 = -1
    private var stopped = false

    var onText: ((Data) -> Void)?
    var onClose: (() -> Void)?

    init(path: String, queue: DispatchQueue) {
        self.path = path
        callbackQueue = queue
    }

    func start() throws {
        descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ClientError.socket }
        var noSigPipe: Int32 = 1
        _ = Darwin.setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else { close(); throw ClientError.pathTooLong }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for index in bytes.indices { destination[index] = bytes[index] }
            }
        }
        let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else { close(); throw ClientError.socket }
        try handshake()
        readQueue.async { [weak self] in self?.readLoop() }
    }

    func send(json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try sendFrame(opcode: 0x1, payload: data)
    }

    func close() {
        writeLock.lock()
        let socket = descriptor
        descriptor = -1
        stopped = true
        writeLock.unlock()
        if socket >= 0 {
            Darwin.shutdown(socket, SHUT_RDWR)
            Darwin.close(socket)
        }
    }

    private func handshake() throws {
        var random = [UInt8](repeating: 0, count: 16)
        let randomStatus = random.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw ClientError.handshake
        }
        let key = Data(random).base64EncodedString()
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        try writeAll(Data(request.utf8))
        var response = Data()
        while !response.ends(with: Data("\r\n\r\n".utf8)), response.count < 16_384 {
            response.append(try readExact(1))
        }
        guard let header = String(data: response, encoding: .utf8),
              header.hasPrefix("HTTP/1.1 101") || header.hasPrefix("HTTP/1.0 101") else {
            throw ClientError.handshake
        }
        let expected = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        guard header.lowercased().contains("sec-websocket-accept: \(expected.lowercased())") else {
            throw ClientError.handshake
        }
    }

    private func readLoop() {
        defer {
            close()
            callbackQueue.async { [weak self] in self?.onClose?() }
        }
        do {
            while !stopped {
                let first = try readExact(2)
                let opcode = first[0] & 0x0f
                var length = UInt64(first[1] & 0x7f)
                if length == 126 {
                    let value = try readExact(2)
                    length = UInt64(value[0]) << 8 | UInt64(value[1])
                } else if length == 127 {
                    length = try readExact(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                }
                guard length <= 1_048_576 else { throw ClientError.invalidFrame }
                let masked = first[1] & 0x80 != 0
                let mask = masked ? try readExact(4) : Data()
                var payload = try readExact(Int(length))
                if masked {
                    for index in payload.indices { payload[index] ^= mask[index % 4] }
                }
                switch opcode {
                case 0x1: callbackQueue.async { [weak self] in self?.onText?(payload) }
                case 0x8: return
                case 0x9: try sendFrame(opcode: 0xA, payload: payload)
                case 0xA: break
                default: throw ClientError.invalidFrame
                }
            }
        } catch { }
    }

    private func sendFrame(opcode: UInt8, payload: Data) throws {
        guard payload.count <= 1_048_576 else { throw ClientError.invalidFrame }
        var frame = Data([0x80 | opcode])
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        } else if payload.count <= 65_535 {
            frame.append(0x80 | 126)
            frame.append(UInt8(payload.count >> 8))
            frame.append(UInt8(payload.count & 0xff))
        } else {
            frame.append(0x80 | 127)
            var length = UInt64(payload.count).bigEndian
            frame.append(withUnsafeBytes(of: &length) { Data($0) })
        }
        var mask = [UInt8](repeating: 0, count: 4)
        let maskStatus = mask.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard maskStatus == errSecSuccess else {
            throw ClientError.socket
        }
        frame.append(contentsOf: mask)
        frame.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        try writeAll(frame)
    }

    private func readExact(_ count: Int) throws -> Data {
        var result = Data(count: count)
        var offset = 0
        while offset < count {
            let readCount = result.withUnsafeMutableBytes { buffer in
                Darwin.recv(descriptor, buffer.baseAddress!.advanced(by: offset), count - offset, 0)
            }
            guard readCount > 0 else { throw ClientError.closed }
            offset += readCount
        }
        return result
    }

    private func writeAll(_ data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard descriptor >= 0 else { throw ClientError.closed }
        var offset = 0
        while offset < data.count {
            let sent = data.withUnsafeBytes { buffer in
                Darwin.send(descriptor, buffer.baseAddress!.advanced(by: offset), data.count - offset, 0)
            }
            guard sent > 0 else { throw ClientError.closed }
            offset += sent
        }
    }
}

private extension Data {
    func ends(with suffix: Data) -> Bool {
        count >= suffix.count && self[(count - suffix.count)..<count].elementsEqual(suffix)
    }
}
