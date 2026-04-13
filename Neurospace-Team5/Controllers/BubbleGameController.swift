import Foundation
import Observation
import simd

@MainActor
@Observable
final class BubbleGameController {

    // MARK: - Public state

    var currentIntent: BCIIntent = .idle
    var connectionState: ConnectionState = .disconnected
    var sessionState: SessionState = .idle

    var activeArm: ActiveArm = .right
    var leftArmState: ArmState = ArmState()
    var rightArmState: ArmState = ArmState()

    var bubbles: [Bubble] = []
    var score: Int = 0

    // Stage
    var currentStage: Int = 1
    var targetBubbleColor: String = "Pink"
    var accuracy: Double = 0.0

    // Finish reason — used to distinguish Congrats from Mission Failed
    enum FinishReason { case allPopped, timeUp }
    private(set) var finishReason: FinishReason? = nil

    // Timer
    var remainingSeconds: Int = 0
    private var timerTask: Task<Void, Never>? = nil

    // Movement
    private var targetDirection: SIMD3<Float> = .zero
    private var filteredDirection: SIMD3<Float> = .zero

    private let maxSpeed: Float = 0.55
    private let acceleration: Float = 3.0
    private let deceleration: Float = 4.0

    // Interaction bounds
    private let xLimit: ClosedRange<Float> = -0.38 ... 0.38
    private let yLimit: ClosedRange<Float> = -0.10 ... 0.24
    private let zLimit: ClosedRange<Float> = -0.22 ... 0.22

    // Adaptive mapping tuning
    private let assistRadius: Float = 0.18
    private let maxAssistStrength: Float = 0.28
    private let popThreshold: Float = 0.06
    private let directionBiasWeight: Float = 0.60
    private let neutralIntentThreshold: Float = 0.08
    private let inputDeadzone: Float = 0.12
    private let inputSmoothing: Float = 0.22
    private let idleDecay: Float = 0.18

    // Per-session hit counters (reset each stage)
    private var hitCount: Int = 0
    private var attemptCount: Int = 0

    // MARK: - Stage config

    var stageConfig: StageConfig { StageConfig.config(for: currentStage) }

    // MARK: - Init

    init() {
        resetGame()
    }

    // MARK: - Session control

    func startSession() {
        finishReason = nil
        sessionState = .playing

        let duration = stageConfig.duration
        remainingSeconds = duration
        timerTask?.cancel()

        let start = Date()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.sessionState == .playing else { break }

                let elapsed = Int(Date().timeIntervalSince(start))
                self.remainingSeconds = max(0, duration - elapsed)

                if self.remainingSeconds == 0 {
                    self.finishReason = .timeUp
                    self.sessionState = .finished
                    break
                }
            }
        }
    }

    /// Full reset. Pass keepStage: true to retry the current stage.
    func resetGame(keepStage: Bool = false) {
        timerTask?.cancel()
        timerTask = nil

        if !keepStage {
            currentStage = 1
        }

        currentIntent = .idle
        sessionState = .ready
        activeArm = .right
        score = 0
        hitCount = 0
        attemptCount = 0
        accuracy = 0.0
        finishReason = nil
        targetDirection = .zero
        filteredDirection = .zero
        remainingSeconds = stageConfig.duration

        leftArmState = ArmState(
            basePosition: [-0.22, -0.14, 0.08],
            tipPosition: [-0.16, 0.02, 0.00],
            velocity: .zero,
            isPopTriggered: false
        )

        rightArmState = ArmState(
            basePosition: [0.22, -0.14, 0.08],
            tipPosition: [0.16, 0.02, 0.00],
            velocity: .zero,
            isPopTriggered: false
        )

        bubbles = Self.generateBubbles(for: stageConfig)
    }

    // MARK: - Stage progression

    var canAdvanceStage: Bool { currentStage < StageConfig.totalStages }
    var isOnFinalStage: Bool { currentStage >= StageConfig.totalStages }

    func advanceStage() {
        guard canAdvanceStage else { return }

        currentStage += 1
        hitCount = 0
        attemptCount = 0
        accuracy = 0.0
        finishReason = nil
        targetDirection = .zero
        filteredDirection = .zero
        sessionState = .ready
        remainingSeconds = stageConfig.duration

        leftArmState = ArmState(
            basePosition: [-0.22, -0.14, 0.08],
            tipPosition: [-0.16, 0.02, 0.00],
            velocity: .zero,
            isPopTriggered: false
        )

        rightArmState = ArmState(
            basePosition: [0.22, -0.14, 0.08],
            tipPosition: [0.16, 0.02, 0.00],
            velocity: .zero,
            isPopTriggered: false
        )

        bubbles = Self.generateBubbles(for: stageConfig)
    }

    // MARK: - Connection / arm helpers

    func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    func setActiveArm(_ arm: ActiveArm) {
        activeArm = arm
        targetDirection = .zero
        filteredDirection = .zero
        currentIntent = .idle
    }

    // MARK: - Intent / control

    func applyIntent(_ intent: BCIIntent) {
        guard stageConfig.isIntentAllowed(intent) else {
            currentIntent = .idle
            targetDirection = .zero
            filteredDirection = .zero
            return
        }

        currentIntent = intent
        currentArmState.isPopTriggered = false

        switch intent {
        case .moveLeft:     targetDirection = [-1, 0, 0]
        case .moveRight:    targetDirection = [1, 0, 0]
        case .moveUp:       targetDirection = [0, 1, 0]
        case .moveDown:     targetDirection = [0, -1, 0]
        case .moveForward:  targetDirection = [0, 0, -1]
        case .moveBackward: targetDirection = [0, 0, 1]
        case .idle:         targetDirection = .zero
        case .pop:          currentArmState.isPopTriggered = true
        }

        filteredDirection = targetDirection
    }

    func applyControlVector(x: Float, y: Float, z: Float) {
        currentIntent = .idle

        var raw = SIMD3<Float>(
            clampUnit(x),
            clampUnit(y),
            clampUnit(z)
        )

        if !stageConfig.allowedAxes.contains(.x) { raw.x = 0 }
        if !stageConfig.allowedAxes.contains(.y) { raw.y = 0 }
        if !stageConfig.allowedAxes.contains(.z) { raw.z = 0 }

        raw.x = abs(raw.x) < inputDeadzone ? 0 : raw.x
        raw.y = abs(raw.y) < inputDeadzone ? 0 : raw.y
        raw.z = abs(raw.z) < inputDeadzone ? 0 : raw.z

        filteredDirection = simd_mix(
            filteredDirection,
            raw,
            SIMD3<Float>(repeating: inputSmoothing)
        )

        if simd_length(raw) < 0.001 {
            filteredDirection = simd_mix(
                filteredDirection,
                .zero,
                SIMD3<Float>(repeating: idleDecay)
            )
        }

        targetDirection = filteredDirection
    }

    func stopMotion() {
        currentIntent = .idle
        targetDirection = .zero
        filteredDirection = .zero
    }

    // MARK: - Per-frame update

    func update(deltaTime: Float) {
        guard sessionState == .playing || sessionState == .ready else { return }

        let speedFactor = simd_length(targetDirection) > 0 ? acceleration : deceleration
        let targetVelocity = targetDirection * maxSpeed

        currentArmState.velocity +=
            (targetVelocity - currentArmState.velocity) * min(speedFactor * deltaTime, 1.0)

        if simd_length(currentArmState.velocity) < 0.001 {
            currentArmState.velocity = .zero
        }

        var newTip = currentArmState.tipPosition + currentArmState.velocity * deltaTime

        if let targetBubble = bestBubbleForCurrentIntent(from: newTip) {
            let toBubble = targetBubble.position - newTip
            let distance = simd_length(toBubble)

            if distance < assistRadius && distance > 0.001 {
                let direction = simd_normalize(toBubble)
                let closeness = 1.0 - (distance / assistRadius)
                let adaptiveStrength = closeness * maxAssistStrength
                newTip += direction * adaptiveStrength * deltaTime * 10.0
            }
        }

        newTip.x = min(max(newTip.x, xLimit.lowerBound), xLimit.upperBound)
        newTip.y = min(max(newTip.y, yLimit.lowerBound), yLimit.upperBound)
        newTip.z = min(max(newTip.z, zLimit.lowerBound), zLimit.upperBound)
        currentArmState.tipPosition = newTip

        if sessionState == .playing {
            autoPopIfTouching()
            updateBubbleLifecycle(deltaTime: deltaTime)
        }
    }

    // MARK: - Tap-to-pop

    func popBubble(withID id: UUID) {
        guard sessionState == .playing else { return }
        guard let idx = bubbles.firstIndex(where: { $0.id == id }),
              !bubbles[idx].isGone else { return }

        if stageConfig.isBilateral,
           let assigned = bubbles[idx].assignedArm,
           assigned != activeArm {
            return
        }

        // Move arm tip to bubble position so the visual pose updates to point at it
        let bubblePos = bubbles[idx].position
        currentArmState.tipPosition = SIMD3<Float>(
            min(max(bubblePos.x, xLimit.lowerBound), xLimit.upperBound),
            min(max(bubblePos.y, yLimit.lowerBound), yLimit.upperBound),
            min(max(bubblePos.z, zLimit.lowerBound), zLimit.upperBound)
        )

        registerBubblePop(at: idx)
        checkSessionFinished()
    }

    // MARK: - Debug Helpers

    var leftTipText: String {
        format(leftArmState.tipPosition)
    }

    var rightTipText: String {
        format(rightArmState.tipPosition)
    }

    var motionVectorText: String {
        format(targetDirection)
    }

    var activeBubbleText: String {
        guard let bubble = bestBubbleForCurrentIntent(from: currentArmState.tipPosition) else {
            return "None"
        }
        return "\(bubble.type.displayName) \(format(bubble.position))"
    }

    private func format(_ v: SIMD3<Float>) -> String {
        String(format: "(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
    }

    // MARK: - Private helpers

    private var currentArmState: ArmState {
        get { activeArm == .left ? leftArmState : rightArmState }
        set {
            if activeArm == .left {
                leftArmState = newValue
            } else {
                rightArmState = newValue
            }
        }
    }

    private func nearestBubble() -> Bubble? {
        var closest: Bubble?
        var minDist: Float = .greatestFiniteMagnitude

        for bubble in bubbles where !bubble.isGone {
            if stageConfig.isBilateral,
               let assigned = bubble.assignedArm,
               assigned != activeArm {
                continue
            }

            let d = simd_distance(bubble.position, currentArmState.tipPosition)
            if d < minDist {
                minDist = d
                closest = bubble
            }
        }

        return closest
    }

    private func bestBubbleForCurrentIntent(from tip: SIMD3<Float>) -> Bubble? {
        let intentMagnitude = simd_length(targetDirection)

        guard intentMagnitude > neutralIntentThreshold else {
            return nearestBubble()
        }

        let intentDirection = simd_normalize(targetDirection)

        var bestBubble: Bubble?
        var bestScore: Float = -.greatestFiniteMagnitude

        for bubble in bubbles where !bubble.isGone {
            if stageConfig.isBilateral,
               let assigned = bubble.assignedArm,
               assigned != activeArm {
                continue
            }

            let toBubble = bubble.position - tip
            let distance = simd_length(toBubble)

            if distance < 0.001 {
                return bubble
            }

            let bubbleDirection = simd_normalize(toBubble)
            let alignment = simd_dot(intentDirection, bubbleDirection)
            let distanceScore = -distance

            let score = distanceScore + (alignment * directionBiasWeight)

            if score > bestScore {
                bestScore = score
                bestBubble = bubble
            }
        }

        return bestBubble
    }

    private func autoPopIfTouching() {
        var poppedAnyBubble = false

        for i in bubbles.indices {
            guard !bubbles[i].isGone else { continue }

            if stageConfig.isBilateral,
               let assigned = bubbles[i].assignedArm,
               assigned != activeArm {
                continue
            }

            let popRadius = max(stageConfig.bubbleRadius + 0.028, popThreshold)

            if simd_distance(bubbles[i].position, currentArmState.tipPosition) < popRadius {
                currentArmState.tipPosition = simd_mix(
                    currentArmState.tipPosition,
                    bubbles[i].position,
                    SIMD3<Float>(repeating: 0.4)
                )

                registerBubblePop(at: i)
                poppedAnyBubble = true
            }
        }

        if poppedAnyBubble && attemptCount > 0 {
            accuracy = Double(hitCount) / Double(attemptCount)
            checkSessionFinished()
        }
    }

    private func registerBubblePop(at index: Int) {
        guard bubbles.indices.contains(index), !bubbles[index].isGone else { return }

        bubbles[index].isPopped = true
        score += bubbles[index].type.points
        hitCount += 1
        attemptCount += 1
        accuracy = Double(hitCount) / Double(attemptCount)
    }

    private func updateBubbleLifecycle(deltaTime: Float) {
        if stageConfig.respawnsEnabled {
            var updated = bubbles

            for i in updated.indices where !updated[i].isPopped {
                if simd_length(updated[i].velocity) > 0.001 {
                    updated[i].position += updated[i].velocity * deltaTime
                }
            }

            if updated.allSatisfy(\.isGone) {
                bubbles = Self.generateBubbles(for: stageConfig)
            } else {
                bubbles = updated
            }
            return
        }

        checkSessionFinished()
    }

    private func checkSessionFinished() {
        guard bubbles.allSatisfy(\.isGone) else { return }
        finishReason = .allPopped
        sessionState = .finished
    }

    private func clampUnit(_ value: Float) -> Float {
        max(-1, min(1, value))
    }

    // MARK: - Bubble generation

    private static func generateBubbles(for config: StageConfig) -> [Bubble] {
        // Wider, deeper, and taller 3D space for a more immersive feel
        let xRange: ClosedRange<Float> = config.allowedAxes.contains(.x) ? -0.55 ... 0.55 : -0.04 ... 0.04
        let yRange: ClosedRange<Float> = config.allowedAxes.contains(.y) ? -0.08 ... 0.30 : 0.08 ... 0.12
        let zRange: ClosedRange<Float> = config.allowedAxes.contains(.z) ? -0.26 ... 0.14 : -0.06 ... 0.06

        // Keep them naturally separated
        let minDistance = config.bubbleRadius * 3.2

        // Arm tip starting positions — bubbles must not spawn within autoPopIfTouching range
        let rightTipStart = SIMD3<Float>(0.16, 0.02, 0.00)
        let leftTipStart  = SIMD3<Float>(-0.16, 0.02, 0.00)
        let safeRadius = max(config.bubbleRadius + 0.028, 0.06) + 0.10

        var positions: [SIMD3<Float>] = []
        var tries = 0

        while positions.count < config.bubbleCount && tries < 500 {
            tries += 1

            let candidate = SIMD3<Float>(
                Float.random(in: xRange),
                Float.random(in: yRange),
                Float.random(in: zRange)
            )

            // Prevent crowding around the main center interaction space
            let tooCloseToCenter =
                abs(candidate.x) < 0.10 &&
                candidate.y > -0.02 && candidate.y < 0.18 &&
                abs(candidate.z) < 0.08

            if tooCloseToCenter {
                continue
            }

            // Ensure bubble doesn't spawn within immediate pop range of arm starting position
            if simd_distance(candidate, rightTipStart) < safeRadius ||
               simd_distance(candidate, leftTipStart) < safeRadius {
                continue
            }

            if positions.contains(where: { simd_distance($0, candidate) < minDistance }) {
                continue
            }

            positions.append(candidate)
        }

        return positions.map { position in
            let arm: ActiveArm? = config.isBilateral ? (position.x < 0 ? .left : .right) : nil

            let speed = Float.random(in: config.bubbleSpeed)

            // Give dynamic stages a more natural 3D drift
            let rawDir = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -0.6...0.6),
                Float.random(in: -0.8...0.8)
            )

            let velocity: SIMD3<Float> = (speed > 0.001 && simd_length(rawDir) > 0.001)
                ? simd_normalize(rawDir) * speed
                : .zero

            return Bubble(
                position: position,
                type: BubbleType.randomWeighted(),
                assignedArm: arm,
                velocity: velocity,
                lifetime: config.bubbleLifetime
            )
        }
    }
}
