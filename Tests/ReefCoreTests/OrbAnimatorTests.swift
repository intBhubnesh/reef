import XCTest
@testable import ReefCore

final class OrbAnimatorTests: XCTestCase {
    func testCatalogueContainsAllSixteenBloubExpressionsInDisplayOrder() {
        XCTAssertEqual(AvatarEmotion.allCases.map(\.rawValue), [
            "neutral", "attentive", "surprised", "excited",
            "happy", "laughing", "angry", "sad",
            "scared", "suspicious", "confused", "curious",
            "proud", "shy", "unimpressed", "sleepy"
        ])
    }

    func testMeasuredUpstreamConstantsArePreserved() {
        let neutral = AvatarEmotion.neutral.expression
        XCTAssertEqual(neutral.gaze, AvatarHeadGaze(yaw: 28.49, pitch: 28.62, roll: -13))
        XCTAssertEqual(neutral.split, 15.46)
        XCTAssertEqual(neutral.eyes[0], AvatarEyeConfig(width: 0.186, height: 0.412))

        let angry = AvatarEmotion.angry.expression
        XCTAssertEqual(angry.eyes[0].tilt, 30)
        XCTAssertEqual(angry.eyes[1].tilt, -30)

        let sleepy = AvatarEmotion.sleepy.expression
        XCTAssertEqual(sleepy.eyes[0].open, 0.42)
        XCTAssertEqual(sleepy.eyes[1].open, 0.42)
    }

    func testEveryExpressionRendersTwoProjectedEyes() {
        for emotion in AvatarEmotion.allCases {
            let frame = OrbAnimator.frame(status: .idle, elapsed: 1, seed: 0,
                                          emotion: emotion, reduceMotion: true)
            XCTAssertEqual(frame.emotion, emotion)
            XCTAssertEqual(frame.eyes.count, 2, "\(emotion.rawValue) lost an eye")
            XCTAssertTrue(frame.eyes.allSatisfy { $0.width > 0 && $0.height > 0 && $0.alpha > 0 })
        }
    }

    func testAllSixteenExpressionsProduceDistinctEyeGeometry() {
        let signatures = AvatarEmotion.allCases.map { emotion -> String in
            let frame = OrbAnimator.frame(status: .idle, elapsed: 1, seed: 0,
                                          emotion: emotion, reduceMotion: true)
            return frame.eyes.map {
                [$0.x, $0.y, $0.width, $0.height, $0.a, $0.b, $0.c, $0.d]
                    .map { String(format: "%.6f", Double($0)) }.joined(separator: ",")
            }.joined(separator: "|")
        }
        XCTAssertEqual(Set(signatures).count, 16)
    }

    func testDefaultStatusToEmotionMapping() {
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .idle), .neutral)
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .working), .attentive)
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .runningTool("Bash")), .excited)
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .compacting), .sleepy)
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .waitingForApproval), .suspicious)
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .waitingForQuestion), .curious)
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .waitingForPlan), .proud)
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .done), .happy)
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .failed), .sad)
    }

    func testCustomMappingAndExplicitOverrideDriveFrame() {
        var mapping = AvatarStatusSlot.defaultMapping
        mapping[AvatarStatusSlot.working.rawValue] = AvatarEmotion.angry.rawValue
        XCTAssertEqual(AvatarStatusSlot.emotion(for: .working, mapping: mapping), .angry)

        let frame = OrbAnimator.frame(status: .working, elapsed: 0, seed: 2,
                                      emotion: .laughing)
        XCTAssertEqual(frame.emotion, .laughing)
    }

    func testEyesWanderAndBlinkUsingDeterministicBloubSchedule() {
        let a = OrbAnimator.frame(status: .idle, elapsed: 0, seed: 41, emotion: .neutral)
        let b = OrbAnimator.frame(status: .idle, elapsed: 1, seed: 41, emotion: .neutral)
        XCTAssertNotEqual(a.eyes, b.eyes)

        let frames = stride(from: 0.0, through: 5.0, by: 0.02).map {
            OrbAnimator.frame(status: .idle, elapsed: $0, seed: 0, emotion: .attentive)
        }
        let verticalScales = frames.compactMap { $0.eyes.first?.d }.map(abs)
        XCTAssertLessThan(verticalScales.min()!, verticalScales.max()! * 0.4)
    }

    func testStatusDecorationStillAnimatesWithoutChangingFace() {
        let workingA = OrbAnimator.frame(status: .working, elapsed: 0, seed: 2,
                                         emotion: .attentive)
        let workingB = OrbAnimator.frame(status: .working, elapsed: 0.5, seed: 2,
                                         emotion: .attentive)
        XCTAssertTrue(workingA.showsOrbit)
        XCTAssertNotEqual(workingA.orbitAngle, workingB.orbitAngle)

        let waiting = OrbAnimator.frame(status: .waitingForApproval, elapsed: 0, seed: 2,
                                        emotion: .suspicious)
        XCTAssertGreaterThan(waiting.badgeScale, 0)
    }

    func testReduceMotionFreezesTheExactPose() {
        let a = OrbAnimator.frame(status: .working, elapsed: 0, seed: 9,
                                  emotion: .attentive, reduceMotion: true)
        let b = OrbAnimator.frame(status: .working, elapsed: 100, seed: 9,
                                  emotion: .attentive, reduceMotion: true)
        XCTAssertEqual(a, b)

        let waiting = OrbAnimator.frame(status: .waitingForApproval, elapsed: 20, seed: 9,
                                        emotion: .suspicious, reduceMotion: true)
        XCTAssertEqual(waiting.badgeScale, 1)
    }
}
