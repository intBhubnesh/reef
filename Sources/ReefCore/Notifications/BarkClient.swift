import Foundation

public enum BarkNotificationLevel: String, Codable, CaseIterable, Sendable {
    case active
    case timeSensitive
    case passive
}

public struct BarkConfiguration: Equatable, Sendable {
    public var serverURL: String
    public var deviceKey: String

    public init(serverURL: String, deviceKey: String) {
        self.serverURL = serverURL
        self.deviceKey = deviceKey
    }
}

public struct BarkMessage: Equatable, Sendable {
    public var title: String
    public var body: String
    public var group: String
    public var level: BarkNotificationLevel
    public var sound: String?

    public init(title: String, body: String, group: String = "Reef",
                level: BarkNotificationLevel = .active, sound: String? = nil) {
        self.title = title
        self.body = body
        self.group = group
        self.level = level
        self.sound = sound
    }
}

public enum BarkClientError: Error, LocalizedError, Equatable {
    case invalidServerURL
    case missingDeviceKey
    case invalidResponse
    case server(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "Enter a valid HTTP or HTTPS Bark server URL."
        case .missingDeviceKey: return "Enter the device key shown in the Bark app."
        case .invalidResponse: return "Bark returned an invalid response."
        case let .server(status, message): return message.isEmpty ? "Bark returned HTTP \(status)." : message
        }
    }
}

public final class BarkClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Bark API V2: POST JSON to `/push`, with the key in the body. This works with both the
    /// public service and self-hosted bark-server installations without putting the key in logs.
    public static func request(configuration: BarkConfiguration, message: BarkMessage) throws -> URLRequest {
        var rawServer = configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var key = configuration.deviceKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Bark's primary onboarding action copies a complete test URL. Accept that directly:
        // the first path component is the device key and the origin becomes the server. The
        // complete input remains protected in Keychain and the actual request still uses /push.
        if var copied = URLComponents(string: key),
           let scheme = copied.scheme?.lowercased(),
           scheme == "https" || scheme == "http",
           copied.host != nil,
           let copiedKey = copied.path.split(separator: "/").first.map(String.init),
           !copiedKey.isEmpty {
            key = copiedKey
            copied.path = ""
            copied.query = nil
            copied.fragment = nil
            if let origin = copied.url?.absoluteString { rawServer = origin }
        }
        guard !key.isEmpty else { throw BarkClientError.missingDeviceKey }

        guard var components = URLComponents(string: rawServer),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else { throw BarkClientError.invalidServerURL }
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else { throw BarkClientError.invalidServerURL }
        let endpoint = baseURL.path.hasSuffix("/push") ? baseURL : baseURL.appendingPathComponent("push")

        var payload: [String: Any] = [
            "device_key": key,
            "title": message.title,
            "body": message.body,
            "group": message.group,
            "level": message.level.rawValue,
        ]
        if let sound = message.sound?.trimmingCharacters(in: .whitespacesAndNewlines), !sound.isEmpty {
            payload["sound"] = sound
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Reef/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return request
    }

    public func send(configuration: BarkConfiguration, message: BarkMessage) async throws {
        let request = try Self.request(configuration: configuration, message: message)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BarkClientError.invalidResponse }

        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let serviceCode = (object?["code"] as? NSNumber)?.intValue
        let serviceMessage = object?["message"] as? String ?? ""
        guard (200..<300).contains(http.statusCode), serviceCode == nil || serviceCode == 200 else {
            throw BarkClientError.server(status: serviceCode ?? http.statusCode, message: serviceMessage)
        }
    }
}
