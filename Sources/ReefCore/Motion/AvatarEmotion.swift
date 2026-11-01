import Foundation

public struct AvatarHeadGaze: Equatable {
    public let yaw: Double
    public let pitch: Double
    public let roll: Double

    public init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }
}

public struct AvatarEyeConfig: Equatable {
    /// Width and height in units of the circle radius, matching Bloub's source model.
    public let width: Double
    public let height: Double
    public let tilt: Double
    public let open: Double

    public init(width: Double, height: Double, tilt: Double = 0, open: Double = 1) {
        self.width = width
        self.height = height
        self.tilt = tilt
        self.open = open
    }
}

public struct AvatarExpression: Equatable {
    public let gaze: AvatarHeadGaze
    public let split: Double
    public let eyes: [AvatarEyeConfig]

    public init(gaze: AvatarHeadGaze, split: Double, eyes: [AvatarEyeConfig]) {
        precondition(eyes.count == 2)
        self.gaze = gaze
        self.split = split
        self.eyes = eyes
    }
}

/// The 16 measured Bloub expressions. Constants are a direct native port of
/// `src/bot/expressions.ts` at the attributed upstream revision.
public enum AvatarEmotion: String, CaseIterable, Codable, Identifiable {
    case neutral, attentive, surprised, excited
    case happy, laughing, angry, sad
    case scared, suspicious, confused, curious
    case proud, shy, unimpressed, sleepy

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    public var expression: AvatarExpression {
        func eye(_ width: Double, _ height: Double, _ tilt: Double = 0,
                 _ open: Double = 1) -> AvatarEyeConfig {
            AvatarEyeConfig(width: width, height: height, tilt: tilt, open: open)
        }
        func pair(_ width: Double, _ height: Double, _ tilt: Double = 0,
                  _ open: Double = 1) -> [AvatarEyeConfig] {
            [eye(width, height, tilt, open), eye(width, height, -tilt, open)]
        }

        switch self {
        case .neutral:
            return AvatarExpression(gaze: .init(yaw: 28.49, pitch: 28.62, roll: -13),
                                    split: 15.46,
                                    eyes: [eye(0.186, 0.412), eye(0.186, 0.412)])
        case .attentive:
            return AvatarExpression(gaze: .init(yaw: 4, pitch: 5, roll: -4),
                                    split: 16, eyes: pair(0.21, 0.44))
        case .surprised:
            return AvatarExpression(gaze: .init(yaw: 3, pitch: -3, roll: 0),
                                    split: 19, eyes: pair(0.45, 0.47))
        case .excited:
            return AvatarExpression(gaze: .init(yaw: 6, pitch: -14, roll: 0),
                                    split: 19.5, eyes: pair(0.4, 0.56, -10))
        case .happy:
            return AvatarExpression(gaze: .init(yaw: 5, pitch: 9, roll: 0),
                                    split: 17, eyes: pair(0.27, 0.17, 14))
        case .laughing:
            return AvatarExpression(gaze: .init(yaw: 4, pitch: 14, roll: 0),
                                    split: 18, eyes: pair(0.34, 0.13, 20))
        case .angry:
            return AvatarExpression(gaze: .init(yaw: 3, pitch: 7, roll: 0),
                                    split: 17, eyes: pair(0.34, 0.15, 30))
        case .sad:
            return AvatarExpression(gaze: .init(yaw: 3, pitch: -13, roll: 0),
                                    split: 16, eyes: pair(0.22, 0.4, -28))
        case .scared:
            return AvatarExpression(gaze: .init(yaw: 2, pitch: -20, roll: 0),
                                    split: 20.5, eyes: pair(0.4, 0.6))
        case .suspicious:
            return AvatarExpression(gaze: .init(yaw: 12, pitch: 6, roll: -6), split: 16,
                                    eyes: [eye(0.21, 0.4), eye(0.22, 0.15)])
        case .confused:
            return AvatarExpression(gaze: .init(yaw: -14, pitch: 3, roll: 8), split: 16.5,
                                    eyes: [eye(0.2, 0.44, -18), eye(0.28, 0.17, 14)])
        case .curious:
            return AvatarExpression(gaze: .init(yaw: 16, pitch: -9, roll: -15), split: 16.5,
                                    eyes: [eye(0.24, 0.46, -8), eye(0.2, 0.38, -8)])
        case .proud:
            return AvatarExpression(gaze: .init(yaw: 5, pitch: 17, roll: 0),
                                    split: 17, eyes: pair(0.3, 0.15, 18))
        case .shy:
            return AvatarExpression(gaze: .init(yaw: -19, pitch: -14, roll: -7),
                                    split: 14, eyes: pair(0.17, 0.3))
        case .unimpressed:
            return AvatarExpression(gaze: .init(yaw: -22, pitch: 2, roll: 0),
                                    split: 16, eyes: pair(0.3, 0.12))
        case .sleepy:
            return AvatarExpression(gaze: .init(yaw: 6, pitch: -9, roll: -3),
                                    split: 16, eyes: pair(0.2, 0.42, 0, 0.42))
        }
    }
}

/// Stable settings keys for every session status family shown in Display.
public enum AvatarStatusSlot: String, CaseIterable, Codable, Identifiable {
    case idea, working, runningTool, compacting
    case approval, question, plan, done, failed

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .idea: return "Idea / idle"
        case .working: return "Working"
        case .runningTool: return "Running tool"
        case .compacting: return "Compacting"
        case .approval: return "Needs approval"
        case .question: return "Has a question"
        case .plan: return "Plan review"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }

    public var defaultEmotion: AvatarEmotion {
        switch self {
        case .idea: return .neutral
        case .working: return .attentive
        case .runningTool: return .excited
        case .compacting: return .sleepy
        case .approval: return .suspicious
        case .question: return .curious
        case .plan: return .proud
        case .done: return .happy
        case .failed: return .sad
        }
    }

    public var sampleStatus: SessionStatus {
        switch self {
        case .idea: return .idle
        case .working: return .working
        case .runningTool: return .runningTool("Tool")
        case .compacting: return .compacting
        case .approval: return .waitingForApproval
        case .question: return .waitingForQuestion
        case .plan: return .waitingForPlan
        case .done: return .done
        case .failed: return .failed
        }
    }

    public static var defaultMapping: [String: String] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0.defaultEmotion.rawValue) })
    }

    public static func slot(for status: SessionStatus) -> AvatarStatusSlot {
        switch status {
        case .idle: return .idea
        case .working: return .working
        case .runningTool: return .runningTool
        case .compacting: return .compacting
        case .waitingForApproval: return .approval
        case .waitingForQuestion: return .question
        case .waitingForPlan: return .plan
        case .done: return .done
        case .failed: return .failed
        }
    }

    public static func emotion(for status: SessionStatus,
                               mapping: [String: String] = defaultMapping) -> AvatarEmotion {
        let slot = slot(for: status)
        return mapping[slot.rawValue].flatMap(AvatarEmotion.init(rawValue:)) ?? slot.defaultEmotion
    }
}
