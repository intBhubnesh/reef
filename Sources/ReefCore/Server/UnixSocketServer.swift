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
        private let closedLock = NSLock()
        private var closedHandler: (() -> Void)?

        /// Set from any thread; delivered once on the main thread when the connection closes.
        public var onClosed: (() -> Void)? {
            get { closedLock.lock(); defer { closedLock.unlock() }; return closedHandler }
            set { closedLock.lock(); closedHandler = newValue; closedLock.unlock() }
        }

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
            closedLock.lock()
            let handler = closedHandler
            closedHandler = nil
            closedLock.unlock()
            DispatchQueue.main.async { handler?() }
        }
    }

    public let path: String
    private let queue: DispatchQueue
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [UUID: Connection] = [:]
    /// Identity of the pathname created by this server. A previous Reef process can finish
    /// shutting down after its replacement has already bound the same path; only the process
    /// that still owns the pathname may unlink it.
    private var socketPathIdentity: (device: dev_t, inode: ino_t)?
    /// Called on the server's queue; hop to the main thread before touching UI state. `Connection.onClosed` runs on main.
    public var onRequest: ((BridgeRequest, Connection) -> Void)?

    public init(path: String, queue: DispatchQueue) {
        self.path = path
        self.queue = queue
    }

    public func start() throws {
        guard listenFD < 0 else { return }
        try removeStaleSocketIfNeeded()
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
        socketPathIdentity = identity(at: path)
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
        // Never let an old process remove a replacement process's live socket during a restart.
        if let owned = socketPathIdentity, let current = identity(at: path),
           owned.device == current.device, owned.inode == current.inode {
            unlink(path)
        }
        socketPathIdentity = nil
    }

    /// Leaves a live listener alone. A pathname left behind by a crashed process is safe to
    /// remove, but unlinking a live socket makes that server unreachable while it still appears
    /// healthy—exactly the restart race this check prevents.
    private func removeStaleSocketIfNeeded() throws {
        guard lstatExists(path) else { return }
        let client = UnixSocketClient(path: path)
        defer { client.close() }
        if (try? client.connect()) != nil { throw UnixSocketClient.Error.unavailable }
        guard unlink(path) == 0 || errno == ENOENT else { throw UnixSocketClient.Error.unavailable }
    }

    private func lstatExists(_ path: String) -> Bool {
        var value = stat()
        return lstat(path, &value) == 0
    }

    private func identity(at path: String) -> (device: dev_t, inode: ino_t)? {
        var value = stat()
        guard lstat(path, &value) == 0 else { return nil }
        return (value.st_dev, value.st_ino)
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
