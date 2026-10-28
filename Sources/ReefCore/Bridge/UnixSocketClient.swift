import Foundation

/// Minimal blocking Unix-domain-socket client used by the bridge (and by tests of the server).
public final class UnixSocketClient {
    public enum Error: Swift.Error, Equatable { case unavailable, timeout, closed }

    public let path: String
    private var fd: Int32 = -1

    public init(path: String) { self.path = path }
    deinit { close() }

    /// Sends one line; when `awaitReply`, waits up to `timeout` for one reply line (without the newline).
    public func send(_ line: Data, awaitReply: Bool, timeout: TimeInterval) throws -> Data? {
        try connect()
        defer { if !awaitReply { close() } }
        try writeAll(line)
        guard awaitReply else { return nil }
        return try readLine(timeout: timeout)
    }

    public func connect() throws {
        guard fd < 0 else { return }
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { throw Error.unavailable }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(sock); throw Error.unavailable }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes); raw[bytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(sock, $0, len) } }
        guard rc == 0 else { Darwin.close(sock); throw Error.unavailable }
        fd = sock
    }

    /// Writes a line on an already-open connection without closing it.
    public func sendRaw(_ line: Data) throws {
        try connect()
        try writeAll(line)
    }

    public func close() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }

    private func writeAll(_ data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { throw Error.closed }
                offset += n
            }
        }
    }

    /// Reads until a newline; returns the line without it.
    public func readLine(timeout: TimeInterval) throws -> Data {
        let framer = LineFramer()
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw Error.timeout }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(min(remaining * 1000, Double(Int32.max))))
            if ready == 0 { throw Error.timeout }
            if ready < 0 { if errno == EINTR { continue }; throw Error.closed }
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n <= 0 { throw Error.closed }
            if let line = framer.append(Data(buffer[0..<n])).first { return line }
        }
    }
}
