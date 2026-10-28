import Foundation

public enum BridgeMode: String, Codable {
    case fire
    case wait

    /// Blocking events hold the socket open for a decision; everything else is fire-and-forget.
    public static func forEvent(name: String) -> BridgeMode {
        name == "PermissionRequest" ? .wait : .fire
    }
}

public enum BridgeProtocolError: Error, Equatable {
    case notAnObject
    case unsupportedVersion(Int)
    case missingField(String)
}

public let bridgeProtocolVersion = 1

public struct BridgeRequest {
    public let v: Int
    public let id: String
    public let mode: BridgeMode
    public let event: [String: Any]

    public init(id: String = UUID().uuidString, mode: BridgeMode, event: [String: Any]) {
        v = bridgeProtocolVersion
        self.id = id
        self.mode = mode
        self.event = event
    }

    private init(v: Int, id: String, mode: BridgeMode, event: [String: Any]) {
        self.v = v; self.id = id; self.mode = mode; self.event = event
    }

    public func encodedLine() throws -> Data {
        try JSONLine.encode(["v": v, "id": id, "mode": mode.rawValue, "event": event])
    }

    public static func decode(line: Data) throws -> BridgeRequest {
        let json = try JSONLine.decode(line)
        let v = try JSONLine.version(of: json)
        guard let id = json["id"] as? String else { throw BridgeProtocolError.missingField("id") }
        guard let modeRaw = json["mode"] as? String, let mode = BridgeMode(rawValue: modeRaw) else {
            throw BridgeProtocolError.missingField("mode")
        }
        guard let event = json["event"] as? [String: Any] else { throw BridgeProtocolError.missingField("event") }
        return BridgeRequest(v: v, id: id, mode: mode, event: event)
    }
}

public struct BridgeResponse {
    public let v: Int
    public let id: String
    public let reply: [String: Any]

    public init(id: String, reply: [String: Any]) {
        v = bridgeProtocolVersion
        self.id = id
        self.reply = reply
    }

    private init(v: Int, id: String, reply: [String: Any]) {
        self.v = v; self.id = id; self.reply = reply
    }

    public func encodedLine() throws -> Data {
        try JSONLine.encode(["v": v, "id": id, "reply": reply])
    }

    public static func decode(line: Data) throws -> BridgeResponse {
        let json = try JSONLine.decode(line)
        let v = try JSONLine.version(of: json)
        guard let id = json["id"] as? String else { throw BridgeProtocolError.missingField("id") }
        guard let reply = json["reply"] as? [String: Any] else { throw BridgeProtocolError.missingField("reply") }
        return BridgeResponse(v: v, id: id, reply: reply)
    }
}

enum JSONLine {
    static func encode(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(UInt8(ascii: "\n"))
        return data
    }

    static func decode(_ line: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: line), let json = object as? [String: Any] else {
            throw BridgeProtocolError.notAnObject
        }
        return json
    }

    static func version(of json: [String: Any]) throws -> Int {
        let v = json["v"] as? Int ?? 0
        guard v == bridgeProtocolVersion else { throw BridgeProtocolError.unsupportedVersion(v) }
        return v
    }
}
