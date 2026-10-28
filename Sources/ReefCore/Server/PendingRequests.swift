import Foundation

/// Open `wait` connections awaiting a decision, keyed by request id. Not thread-safe: use from the main thread.
public final class PendingRequests {
    private struct Entry {
        let key: SessionKey
        let connection: UnixSocketServer.Connection
        let deadline: Date
    }

    private var entries: [String: Entry] = [:]
    private let now: () -> Date
    /// Fires when the peer hung up before any decision (answered in the terminal, or the agent died).
    public var onDropped: ((String) -> Void)?

    public init(now: @escaping () -> Date = Date.init) { self.now = now }

    public var count: Int { entries.count }

    public func add(requestID: String, key: SessionKey, connection: UnixSocketServer.Connection, deadline: Date) {
        entries[requestID] = Entry(key: key, connection: connection, deadline: deadline)
        connection.onClosed = { [weak self] in
            guard let self, self.entries.removeValue(forKey: requestID) != nil else { return }
            self.onDropped?(requestID)
        }
    }

    public func requestIDs(for key: SessionKey) -> [String] {
        entries.filter { $0.value.key == key }.sorted { $0.value.deadline < $1.value.deadline }.map(\.key)
    }

    /// Sends the decision and closes. Returns false when the request is no longer pending.
    @discardableResult
    public func resolve(requestID: String, decision: Decision, source: AgentSource) -> Bool {
        guard let entry = entries.removeValue(forKey: requestID) else { return false }
        let data = DecisionEncoder.encode(decision, for: source)
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        entry.connection.onClosed = nil
        entry.connection.reply(BridgeResponse(id: requestID, reply: reply))
        return true
    }

    /// Hands the request back to the terminal with no decision.
    public func release(requestID: String) {
        guard let entry = entries.removeValue(forKey: requestID) else { return }
        entry.connection.onClosed = nil
        entry.connection.reply(BridgeResponse(id: requestID, reply: [:]))
    }

    public func releaseAll(for key: SessionKey) {
        for id in requestIDs(for: key) { release(requestID: id) }
    }

    public func releaseAll() {
        for id in Array(entries.keys) { release(requestID: id) }
    }

    /// Releases every request past its deadline; returns their ids.
    @discardableResult
    public func expire(now: Date) -> [String] {
        let expired = entries.filter { $0.value.deadline <= now }.map(\.key).sorted()
        for id in expired { release(requestID: id) }
        return expired
    }
}
