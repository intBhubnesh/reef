import Foundation

/// Line-delimited JSON server on a Unix domain socket. `fire` connections close after parsing;
/// `wait` connections stay open until replied to, closed, or the peer hangs up.
public final class UnixSocketServer {
    public final class Connection {
        public let id = UUID()
        fileprivate let fd: Int32
        fileprivate let queue: DispatchQueue
        fileprivate var source: DispatchSourceRead?
        fileprivate let framer = LineFramer()
        fileprivate var isOpen = true
        public var onClosed: (() -> Void)?

        init(fd: Int32, queue: DispatchQueue) { self.fd = fd; self.queue = queue }

        public func reply(_ response: BridgeResponse) {
            guard let data = try? response.encodedLine() else { close(); return }
            queue.async { [self] in
                guard isOpen else { return }
                data.withUnsafeBytes { raw in
                    var offset = 0
                    while offset < raw.count {
                        let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                        if n <= 0 { break }
                        offset += n
                    }
                }
                closeLocked()
            }
        }

        public func close() { queue.async { [self] in closeLocked() } }

        fileprivate func closeLocked() {
            guard isOpen else { return }
            isOpen = false
            source?.cancel()
            source = nil
            Darwin.close(fd)
            let handler = onClosed
            onClosed = nil
            DispatchQueue.main.async { handler?() }
        }
    }

    public let path: String
    private let queue: DispatchQueue
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [UUID: Connection] = [:]
    /// Called on the server's queue; hop to the main thread before touching UI state. `Connection.onClosed` runs on main.
    public var onRequest: ((BridgeRequest, Connection) -> Void)?

    public init(path: String, queue: DispatchQueue) {
        self.path = path
        self.queue = queue
    }

    public func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketClient.Error.unavailable }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(fd); throw UnixSocketClient.Error.unavailable }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in raw.copyBytes(from: bytes); raw[bytes.count] = 0 }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard bound == 0, listen(fd, 16) == 0 else { Darwin.close(fd); throw UnixSocketClient.Error.unavailable }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.resume()
        acceptSource = source
    }

    public func stop() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if listenFD >= 0 { Darwin.close(listenFD); listenFD = -1 }
            for connection in connections.values { connection.closeLocked() }
            connections.removeAll()
        }
        unlink(path)
    }

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            let flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            let connection = Connection(fd: fd, queue: queue)
            connections[connection.id] = connection
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.read(connection)
            }
            connection.source = source
            source.resume()
        }
    }

    private func read(_ connection: Connection) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let n = Darwin.read(connection.fd, &buffer, buffer.count)
        if n <= 0 {
            if n < 0, errno == EAGAIN { return }
            connections[connection.id] = nil
            connection.closeLocked()
            return
        }
        for line in connection.framer.append(Data(buffer[0..<n])) {
            guard let request = try? BridgeRequest.decode(line: line) else { continue }
            onRequest?(request, connection)
            if request.mode == .fire {
                connections[connection.id] = nil
                connection.closeLocked()
                return
            }
        }
    }
}
