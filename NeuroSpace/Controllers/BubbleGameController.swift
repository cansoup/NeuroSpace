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

    // Set each frame by ImmersiveView using cursor / eye target
    var targetedBubbleID: UUID? = nil

    private(set) var popCount: Int = 0

    var currentStage: Int = 1
    var targetBubbleColor: String = "Pink"
    var accuracy: Double = 0.0

    enum FinishReason { case allPopped, timeUp }
    private(set) var finishReason: FinishReason? = nil

    var remainingSeconds: Int = 0
    private var timerTask: Task<Void, Never>? = nil

    private var targetDirection: SIMD3<Float> = .zero
    private var filteredDirection: SIMD3<Float> = .zero

    private let maxSpeed: Float = 0.55
    private let acceleration: Float = 3.0
    private let deceleration: Float = 4.0

    private let xLimit: ClosedRange<Float> = -0.38 ... 0.38
    private let yLimit: ClosedRange<Float> = -0.10 ... 0.24
    private let zLimit: ClosedRange<Float> = -0.22 ... 0.22

    private let assistRadius: Float = 0.18
    private let maxAssistStrength: Float = 0.28
    private let popThreshold: Float = 0.06
    private let directionBiasWeight: Float = 0.60
    private let neutralIntentThreshold: Float = 0.08
    private let inputDeadzone: Float = 0.12
    private let inputSmoothing: Float = 0.22
    private let idleDecay: Float = 0.18

    private var hitCount: Int = 0
    private var attemptCount: Int = 0

    var stageConfig: StageConfig {
        StageConfig.config(for: currentStage)
    }

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
        targetedBubbleID = nil
        popCount = 0

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

    var poppedCount: Int {
        bubbles.filter(\.isPopped).count
    }

    var totalBubbleCount: Int {
        stageConfig.bubbleCount
    }

    var stageProgress: Float {
        totalBubbleCount > 0 ? Float(poppedCount) / Float(totalBubbleCount) : 0
    }

    var canAdvanceStage: Bool {
        currentStage < StageConfig.totalStages
    }

    var isOnFinalStage: Bool {
        currentStage >= StageConfig.totalStages
    }

    var meetsUnlockCriteria: Bool {
        let criteria = stageConfig.unlockCriteria
        return popCount >= criteria.requiredPops && accuracy >= criteria.minimumAccuracy
    }

    var unlockProgressText: String {
        let c = stageConfig.unlockCriteria
        let acc = Int((accuracy * 100).rounded())
        let req = Int((c.minimumAccuracy * 100).rounded())
        return "Accuracy \(acc)% / \(req)%   ·   Pops \(popCount)/\(c.requiredPops)"
    }

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
        targetedBubbleID = nil

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

    // MARK: - BCI prediction mapping

    func applyPredictionClass(_ prediction: PredictedClass) {
        switch prediction {
        case .left:
            setActiveArm(.left)
            moveActiveArmTowardEyeTarget()

        case .right:
            setActiveArm(.right)
            moveActiveArmTowardEyeTarget()

        case .both:
            attemptPopEyeTargetedBubble()
        }
    }

    private func moveActiveArmTowardEyeTarget() {
        guard let target = eyeTargetedBubble() ?? nearestBubble() else {
            stopMotion()
            return
        }

        moveActiveArmToward(target)
    }

    private func attemptPopEyeTargetedBubble() {
        guard let target = eyeTargetedBubble() else {
            stopMotion()
            return
        }

        if !target.canBePopped(by: activeArm) {
            stopMotion()
            return
        }

        let tip = currentArmState.tipPosition
        let popRadius = max(stageConfig.bubbleRadius + 0.055, popThreshold + 0.03)

        if simd_distance(target.position, tip) <= popRadius {
            popBubble(withID: target.id)
        } else {
            moveActiveArmToward(target)
        }
    }

    private func moveActiveArmToward(_ target: Bubble) {
        let toBubble = target.position - currentArmState.tipPosition

        guard simd_length(toBubble) > 0.001 else {
            autoPopIfTouching()
            return
        }

        let direction = simd_normalize(toBubble)

        applyControlVector(
            x: direction.x,
            y: direction.y,
            z: direction.z,
            respectStageAxes: false
        )
    }

    private func eyeTargetedBubble() -> Bubble? {
        guard let targetedBubbleID else { return nil }
        return bubbles.first { $0.id == targetedBubbleID && !$0.isGone }
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

    func applyControlVector(
        x: Float,
        y: Float,
        z: Float,
        respectStageAxes: Bool = true
    ) {
        currentIntent = .idle

        var raw = SIMD3<Float>(
            clampUnit(x),
            clampUnit(y),
            clampUnit(z)
        )

        if respectStageAxes {
            if !stageConfig.allowedAxes.contains(.x) { raw.x = 0 }
            if !stageConfig.allowedAxes.contains(.y) { raw.y = 0 }
            if !stageConfig.allowedAxes.contains(.z) { raw.z = 0 }
        }

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
            updateBubbleLifecycle(deltaTime: deltaTime)
        }
    }

    // MARK: - Pop control

    func popTargetedBubble() {
        guard sessionState == .playing, let id = targetedBubbleID else { return }
        popBubble(withID: id)
    }

    func popBubble(withID id: UUID) {
        guard sessionState == .playing else { return }
        guard let idx = bubbles.firstIndex(where: { $0.id == id }),
              !bubbles[idx].isGone else { return }

        if !bubbles[idx].canBePopped(by: activeArm) {
            return
        }

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

    var eyeTargetText: String {
        guard let bubble = eyeTargetedBubble() else {
            return "None"
        }

        let armName = bubble.assignedArm?.rawValue.capitalized ?? "Any"
        return "\(armName) \(format(bubble.position))"
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

    private func nearestBubbleDistance(for arm: ActiveArm) -> Float {
        let tip = arm == .left ? leftArmState.tipPosition : rightArmState.tipPosition
        var minDist: Float = .greatestFiniteMagnitude

        for bubble in bubbles where !bubble.isGone {
            guard bubble.canBePopped(by: arm) else { continue }
            minDist = min(minDist, simd_distance(bubble.position, tip))
        }

        return minDist
    }

    private func nearestBubble() -> Bubble? {
        var closest: Bubble?
        var minDist: Float = .greatestFiniteMagnitude

        for bubble in bubbles where !bubble.isGone {
            guard bubble.canBePopped(by: activeArm) else { continue }

            let d = simd_distance(bubble.position, currentArmState.tipPosition)
            if d < minDist {
                minDist = d
                closest = bubble
            }
        }

        return closest
    }

    private func bestBubbleForCurrentIntent(from tip: SIMD3<Float>) -> Bubble? {
        if let target = eyeTargetedBubble() {
            return target
        }

        let intentMagnitude = simd_length(targetDirection)

        guard intentMagnitude > neutralIntentThreshold else {
            return nearestBubble()
        }

        let intentDirection = simd_normalize(targetDirection)

        var bestBubble: Bubble?
        var bestScore: Float = -.greatestFiniteMagnitude

        for bubble in bubbles where !bubble.isGone {
            guard bubble.canBePopped(by: activeArm) else { continue }

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
        // Intentionally no longer auto-pops during BCI testing.
        // Pop is now confirmed using the "both" prediction.
    }

    private func registerBubblePop(at index: Int) {
        guard bubbles.indices.contains(index), !bubbles[index].isGone else { return }

        bubbles[index].isPopped = true
        score += bubbles[index].type.points
        hitCount += 1
        attemptCount += 1
        accuracy = Double(hitCount) / Double(attemptCount)
        popCount += 1
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
        let xRange: ClosedRange<Float> = config.allowedAxes.contains(.x) ? -0.55 ... 0.55 : -0.04 ... 0.04
        let yRange: ClosedRange<Float> = config.allowedAxes.contains(.y) ? -0.08 ... 0.30 : 0.08 ... 0.12
        let zRange: ClosedRange<Float> = config.allowedAxes.contains(.z) ? -0.26 ... 0.14 : -0.06 ... 0.06

        let minDistance = config.bubbleRadius * 2.0

        let rightTipStart = SIMD3<Float>(0.16, 0.02, 0.00)
        let leftTipStart  = SIMD3<Float>(-0.16, 0.02, 0.00)
        let safeRadius = config.bubbleRadius + 0.025

        let centerExclusionX: Float = max(0.06, config.bubbleRadius * 0.6)
        let centerExclusionZ: Float = max(0.05, config.bubbleRadius * 0.5)

        // Stage info / control panel keep-out box. Mirrors the panel's runtime
        // position in ImmersiveView (panel.position = (0.34, 0.18, 0.02))
        // with a half-extent generous enough to cover the panel even when its
        // debug section is expanded.
        let panelCenter = SIMD3<Float>(0.34, 0.18, 0.02)
        let panelHalfExtent = SIMD3<Float>(0.18, 0.13, 0.06)

        // Multi-pass placement: try strictest constraints first, then relax
        // progressively if we can't place all the configured bubbles. This
        // guarantees stage 1 always renders its full bubbleCount, even when
        // the panel keep-out and tight axis ranges leave very little room.
        var positions: [SIMD3<Float>] = []

        func attempt(maxTries: Int, applyPanelKeepOut: Bool, applyMinDistance: Bool) {
            var tries = 0
            while positions.count < config.bubbleCount && tries < maxTries {
                tries += 1

                let candidate = SIMD3<Float>(
                    Float.random(in: xRange),
                    Float.random(in: yRange),
                    Float.random(in: zRange)
                )

                // Center / face keep-out (only fires for upper y values)
                let tooCloseToCenter =
                    abs(candidate.x) < centerExclusionX &&
                    candidate.y > 0.18 &&
                    abs(candidate.z) < centerExclusionZ
                if tooCloseToCenter { continue }

                // Panel keep-out (best-effort)
                if applyPanelKeepOut {
                    let dx = abs(candidate.x - panelCenter.x)
                    let dy = abs(candidate.y - panelCenter.y)
                    let dz = abs(candidate.z - panelCenter.z)
                    if dx < panelHalfExtent.x + config.bubbleRadius &&
                       dy < panelHalfExtent.y + config.bubbleRadius &&
                       dz < panelHalfExtent.z + config.bubbleRadius {
                        continue
                    }
                }

                // Tip safety (always enforced — bubbles must not spawn on the
                // player's resting hand position)
                if simd_distance(candidate, rightTipStart) < safeRadius ||
                   simd_distance(candidate, leftTipStart) < safeRadius {
                    continue
                }

                // Inter-bubble minimum distance (best-effort)
                if applyMinDistance,
                   positions.contains(where: { simd_distance($0, candidate) < minDistance }) {
                    continue
                }

                positions.append(candidate)
            }
        }

        // Pass 1 — full constraints
        attempt(maxTries: 1200, applyPanelKeepOut: true, applyMinDistance: true)

        // Pass 2 — drop panel keep-out so a tightly-constrained stage can still
        // satisfy bubbleCount even if a few bubbles end up over the panel area
        if positions.count < config.bubbleCount {
            attempt(maxTries: 600, applyPanelKeepOut: false, applyMinDistance: true)
        }

        // Pass 3 — last-resort fallback: also drop minimum-distance check.
        // This may produce visually overlapping spheres, but only triggers in
        // pathologically tight stages we'd otherwise undershoot on.
        if positions.count < config.bubbleCount {
            attempt(maxTries: 300, applyPanelKeepOut: false, applyMinDistance: false)
        }

        return positions.map { position in
            let assignedArm: ActiveArm?
            let type: BubbleType

            switch config.armMode {
            case .bilateral:
                let arm: ActiveArm = position.x < 0 ? .left : .right
                assignedArm = arm
                type = arm == .left ? .blue : .red
            case .singleActive:
                assignedArm = nil
                type = BubbleType.randomWeighted()
            }

            let speed = Float.random(in: config.bubbleSpeed)

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
                type: type,
                assignedArm: assignedArm,
                velocity: velocity,
                lifetime: config.bubbleLifetime
            )
        }
    }
}
