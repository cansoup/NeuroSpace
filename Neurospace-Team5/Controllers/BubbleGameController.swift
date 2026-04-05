import Foundation
import Observation
import simd

@MainActor
@Observable
final class BubbleGameController {

    // MARK: - Public state

    var currentIntent:   BCIIntent       = .idle
    var connectionState: ConnectionState = .disconnected
    var sessionState:    SessionState    = .idle

    var activeArm:    ActiveArm = .right
    var leftArmState:  ArmState = ArmState()
    var rightArmState: ArmState = ArmState()

    var bubbles: [Bubble] = []
    var score:   Int      = 0

    // Stage
    var currentStage:      Int    = 1
    var targetBubbleColor: String = "Pink"
    var accuracy:          Double = 0.0

    // Finish reason — used to distinguish Congrats from Mission Failed
    enum FinishReason { case allPopped, timeUp }
    private(set) var finishReason: FinishReason? = nil

    // Timer
    var remainingSeconds: Int = 0
    private var timerTask: Task<Void, Never>? = nil

    // Movement
    private var targetDirection: SIMD3<Float> = .zero
    private let maxSpeed:     Float = 0.55
    private let acceleration: Float = 3.0
    private let deceleration: Float = 4.0

    // Interaction bounds
    private let xLimit: ClosedRange<Float> = -0.38 ... 0.38
    private let yLimit: ClosedRange<Float> = -0.10 ... 0.24
    private let zLimit: ClosedRange<Float> = -0.22 ... 0.22

    // Bubble assist tuning
    private let assistRadius: Float = 0.18
    private let assistStrength: Float = 0.25
    private let popThreshold: Float = 0.06
    private let directionBiasWeight: Float = 0.55
    private let neutralIntentThreshold: Float = 0.08

    // Per-session hit counters (reset each stage)
    private var hitCount:     Int = 0
    private var attemptCount: Int = 0

    // MARK: - Stage config

    var stageConfig: StageConfig { StageConfig.config(for: currentStage) }

    // MARK: - Init

    init() { resetGame() }

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

    /// Full reset. Pass keepStage: true to retry the current stage (e.g. "Try Again").
    func resetGame(keepStage: Bool = false) {
        timerTask?.cancel()
        timerTask = nil

        if !keepStage { currentStage = 1 }

        currentIntent    = .idle
        sessionState     = .ready
        activeArm        = .right
        score            = 0
        hitCount         = 0
        attemptCount     = 0
        accuracy         = 0.0
        finishReason     = nil
        targetDirection  = .zero
        remainingSeconds = stageConfig.duration

        leftArmState = ArmState(
            basePosition: [-0.22, -0.14, 0.08],
            tipPosition:  [-0.16,  0.02, 0.00],
            velocity:     .zero,
            isPopTriggered: false
        )
        rightArmState = ArmState(
            basePosition: [ 0.22, -0.14, 0.08],
            tipPosition:  [ 0.16,  0.02, 0.00],
            velocity:     .zero,
            isPopTriggered: false
        )

        bubbles = Self.generateBubbles(for: stageConfig)
    }

    // MARK: - Stage progression

    var canAdvanceStage: Bool { currentStage < StageConfig.totalStages }

    var isOnFinalStage: Bool { currentStage >= StageConfig.totalStages }

    /// Advances to the next stage. No-op if already at final stage.
    func advanceStage() {
        guard canAdvanceStage else { return }
        currentStage    += 1
        hitCount         = 0
        attemptCount     = 0
        accuracy         = 0.0
        finishReason     = nil
        targetDirection  = .zero
        sessionState     = .ready
        remainingSeconds = stageConfig.duration

        leftArmState = ArmState(
            basePosition: [-0.22, -0.14, 0.08],
            tipPosition:  [-0.16,  0.02, 0.00],
            velocity:     .zero,
            isPopTriggered: false
        )
        rightArmState = ArmState(
            basePosition: [ 0.22, -0.14, 0.08],
            tipPosition:  [ 0.16,  0.02, 0.00],
            velocity:     .zero,
            isPopTriggered: false
        )

        bubbles = Self.generateBubbles(for: stageConfig)
    }

    // MARK: - Connection / arm helpers

    func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    func setActiveArm(_ arm: ActiveArm) {
        activeArm       = arm
        targetDirection = .zero
        currentIntent   = .idle
    }

    // MARK: - Intent / control

    func applyIntent(_ intent: BCIIntent) {
        guard stageConfig.isIntentAllowed(intent) else {
            currentIntent   = .idle
            targetDirection = .zero
            return
        }

        currentIntent = intent
        currentArmState.isPopTriggered = false

        switch intent {
        case .moveLeft:     targetDirection = [-1,  0,  0]
        case .moveRight:    targetDirection = [ 1,  0,  0]
        case .moveUp:       targetDirection = [ 0,  1,  0]
        case .moveDown:     targetDirection = [ 0, -1,  0]
        case .moveForward:  targetDirection = [ 0,  0, -1]
        case .moveBackward: targetDirection = [ 0,  0,  1]
        case .idle:         targetDirection = .zero
        case .pop:          currentArmState.isPopTriggered = true
        }
    }

    func applyControlVector(x: Float, y: Float, z: Float) {
        currentIntent   = .idle
        targetDirection = SIMD3<Float>(
            max(-1, min(1, x)),
            max(-1, min(1, y)),
            max(-1, min(1, z))
        )
    }

    func stopMotion() {
        currentIntent   = .idle
        targetDirection = .zero
    }

    // MARK: - Per-frame update

    func update(deltaTime: Float) {
        guard sessionState == .playing || sessionState == .ready else { return }

        let speedFactor    = simd_length(targetDirection) > 0 ? acceleration : deceleration
        let targetVelocity = targetDirection * maxSpeed

        currentArmState.velocity +=
            (targetVelocity - currentArmState.velocity) * min(speedFactor * deltaTime, 1.0)

        if simd_length(currentArmState.velocity) < 0.001 {
            currentArmState.velocity = .zero
        }

        var newTip = currentArmState.tipPosition + currentArmState.velocity * deltaTime

        // Assist toward best bubble for the active arm, based on intent + distance
        if let targetBubble = bestBubbleForCurrentIntent(from: newTip) {
            let toBubble = targetBubble.position - newTip
            let distance = simd_length(toBubble)

            if distance < assistRadius && distance > 0.001 {
                let direction = simd_normalize(toBubble)
                let strength = (1.0 - (distance / assistRadius)) * assistStrength
                newTip += direction * strength * deltaTime * 10.0
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

    // MARK: - Tap-to-pop (from SpatialTapGesture)

    func popBubble(withID id: UUID) {
        guard sessionState == .playing else { return }
        guard let idx = bubbles.firstIndex(where: { $0.id == id }),
              !bubbles[idx].isGone else { return }

        // Bilateral: only the assigned arm may pop
        if stageConfig.isBilateral,
           let assigned = bubbles[idx].assignedArm,
           assigned != activeArm { return }

        bubbles[idx].isPopped = true
        score        += 100
        hitCount     += 1
        attemptCount += 1
        accuracy = Double(hitCount) / Double(attemptCount)

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
        guard let bubble = bestBubbleForCurrentIntent(from: currentArmState.tipPosition) else { return "None" }
        return format(bubble.position)
    }

    private func format(_ v: SIMD3<Float>) -> String {
        String(format: "(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
    }

    // MARK: - Private helpers

    private var currentArmState: ArmState {
        get { activeArm == .left ? leftArmState : rightArmState }
        set {
            if activeArm == .left { leftArmState = newValue }
            else                  { rightArmState = newValue }
        }
    }

    private func nearestBubble() -> Bubble? {
        var closest: Bubble?
        var minDist: Float = .greatestFiniteMagnitude

        for bubble in bubbles where !bubble.isGone {
            if stageConfig.isBilateral,
               let assigned = bubble.assignedArm,
               assigned != activeArm { continue }

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

        // If the input is nearly neutral, fall back to the closest valid bubble.
        guard intentMagnitude > neutralIntentThreshold else {
            return nearestBubble()
        }

        let intentDirection = simd_normalize(targetDirection)

        var bestBubble: Bubble?
        var bestScore: Float = -.greatestFiniteMagnitude

        for bubble in bubbles where !bubble.isGone {
            if stageConfig.isBilateral,
               let assigned = bubble.assignedArm,
               assigned != activeArm { continue }

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
        for i in bubbles.indices {
            guard !bubbles[i].isGone else { continue }

            if stageConfig.isBilateral,
               let assigned = bubbles[i].assignedArm,
               assigned != activeArm { continue }

            let popRadius = max(stageConfig.bubbleRadius + 0.028, popThreshold)

            if simd_distance(bubbles[i].position, currentArmState.tipPosition) < popRadius {
                currentArmState.tipPosition = simd_mix(
                    currentArmState.tipPosition,
                    bubbles[i].position,
                    SIMD3<Float>(repeating: 0.4)
                )

                bubbles[i].isPopped = true
                score        += 100
                hitCount     += 1
                attemptCount += 1
            }
        }

        if attemptCount > 0 {
            accuracy = Double(hitCount) / Double(attemptCount)
        }
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

    // MARK: - Bubble generation

    private static func generateBubbles(for config: StageConfig) -> [Bubble] {
        let xRange: ClosedRange<Float> = config.allowedAxes.contains(.x) ? -0.32 ... 0.32 : -0.02 ... 0.02
        let yRange: ClosedRange<Float> = config.allowedAxes.contains(.y) ? -0.02 ... 0.18 :  0.08 ... 0.10
        let zRange: ClosedRange<Float> = config.allowedAxes.contains(.z) ? -0.14 ... 0.12 :  0.00 ... 0.00
        let minDistance = config.bubbleRadius * 2.5

        var positions: [SIMD3<Float>] = []
        var tries = 0

        while positions.count < config.bubbleCount && tries < 300 {
            tries += 1
            let candidate = SIMD3<Float>(
                Float.random(in: xRange),
                Float.random(in: yRange),
                Float.random(in: zRange)
            )
            if !positions.contains(where: { simd_distance($0, candidate) < minDistance }) {
                positions.append(candidate)
            }
        }

        return positions.map { position in
            let arm: ActiveArm? = config.isBilateral ? (position.x < 0 ? .left : .right) : nil

            let speed  = Float.random(in: config.bubbleSpeed)
            let rawDir = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), 0)
            let velocity: SIMD3<Float> = (speed > 0.001 && simd_length(rawDir) > 0.001)
                ? simd_normalize(rawDir) * speed
                : .zero

            return Bubble(
                position:    position,
                assignedArm: arm,
                velocity:    velocity,
                lifetime:    config.bubbleLifetime
            )
        }
    }
}
