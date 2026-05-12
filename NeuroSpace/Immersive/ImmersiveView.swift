//
//  ImmersiveView.swift
//  NeuroSpace


import SwiftUI
import RealityKit
import RealityKitContent
import ARKit
import simd
import QuartzCore

private struct ArmVisualTransform {
    let position: SIMD3<Float>
    let scale: SIMD3<Float>
    let orientation: simd_quatf
}

private struct GazeTargetResult {
    let bubble: Bubble?
    let cursorPosition: SIMD3<Float>
    let holdProgress: Float
}

private enum CalibrationCue: CaseIterable {
    case right
    case left
    case both

    var title: String {
        switch self {
        case .right: "Right hand"
        case .left: "Left hand"
        case .both: "Both hands"
        }
    }

    var prompt: String {
        switch self {
        case .right: "Imagine reaching and pointing with your right hand."
        case .left: "Imagine reaching and pointing with your left hand."
        case .both: "Now imagine using both hands together."
        }
    }
}

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var startHoverBeganAt: Date? = nil
    @State private var startTargetHighlighted = false
    @State private var clickCount: Int = 0

    @State private var gazeHoverBubbleID: UUID? = nil
    @State private var gazeHoverBeganAt: Date? = nil
    @State private var lastSeenArmAnimationTriggerCount: Int = 0
    @State private var handVisibilityToken: Int = 0
    @State private var calibrationStartedAt: Date? = nil
    @State private var calibrationCue: CalibrationCue = .right
    @State private var calibrationCueIndex: Int = -1
    @State private var lastSkyboxEnv: EnvironmentChoice? = nil
    @State private var popSoundResource: AudioFileResource? = nil
    private final class BubbleEntityStore {
        var entities: [UUID: ModelEntity] = [:]
        var lastSeenClickCount: Int = 0
        var lastSeenPopCount: Int = 0
        weak var worldAnchor: AnchorEntity?
        weak var armsAnchor: AnchorEntity?
        weak var backgroundPlane: Entity?
        weak var gazeCursor: ModelEntity?
        weak var holdMarker: ModelEntity?
        let arSession = ARKitSession()
        let worldTracking = WorldTrackingProvider()
        var arSessionStarted = false
        // Smoothed cursor position for exponential interpolation
        var smoothedCursorPosition: SIMD3<Float>? = nil
    }

    private let worldAnchorOffset = SIMD3<Float>(0, 1.45, -1.0)
    @State private var bubbleStore = BubbleEntityStore()

    private let startOrbPosition = SIMD3<Float>(0.0, -0.06, 0.02)
    private let startPanelPosition = SIMD3<Float>(0.0, 0.20, 0.02)

    // How close (metres) the head ray must pass to a bubble to select it
    private let gazeSelectRadius: Float = 0.11
    private let gazeDwellDuration: TimeInterval = 0.65

    var body: some View {
        RealityView { content, attachments in
            let worldAnchor = AnchorEntity(world: worldAnchorOffset)
            worldAnchor.name = "WorldAnchor"

            let root = Entity()
            root.name = "Root"
            root.position = .zero

            let bgEntity = Entity()
            bgEntity.name = "BackgroundPlane"
            bgEntity.position = SIMD3<Float>(0, 0.10, -0.60)
            bgEntity.components.set(CollisionComponent(
                shapes: [.generateBox(width: 6.0, height: 4.0, depth: 0.05)]
            ))
            bgEntity.components.set(InputTargetComponent())
            bgEntity.isEnabled = false
            root.addChild(bgEntity)
            bubbleStore.backgroundPlane = bgEntity

            let startOrb = makeStartOrbEntity(
                name: "StartOrb",
                position: startOrbPosition,
                highlighted: false
            )
            root.addChild(startOrb)

            let gazeCursor = makeGazeCursorEntity()
            gazeCursor.name = "GazeCursor"
            gazeCursor.isEnabled = false
            root.addChild(gazeCursor)
            bubbleStore.gazeCursor = gazeCursor

            let holdMarker = makeHoldMarkerEntity()
            holdMarker.name = "HoldMarker"
            holdMarker.isEnabled = false
            root.addChild(holdMarker)
            bubbleStore.holdMarker = holdMarker

            if let panel = attachments.entity(for: "controlPanel") {
                panel.name = "ControlPanel"
                panel.position = SIMD3<Float>(0.34, 0.18, 0.02)
                panel.scale = SIMD3<Float>(repeating: 0.92)
                root.addChild(panel)
            }

            if let startPanel = attachments.entity(for: "startPanel") {
                startPanel.name = "StartPanel"
                startPanel.position = startPanelPosition
                root.addChild(startPanel)
            }

            if let calibrationPanel = attachments.entity(for: "calibrationPanel") {
                calibrationPanel.name = "CalibrationPanel"
                calibrationPanel.position = SIMD3<Float>(0.0, 0.18, 0.02)
                root.addChild(calibrationPanel)
            }

            worldAnchor.addChild(root)
            content.add(worldAnchor)
            bubbleStore.worldAnchor = worldAnchor

            let skyboxAnchor = AnchorEntity(world: .zero)
            skyboxAnchor.name = "SkyboxAnchor"
            content.add(skyboxAnchor)
            let initialEnv = appModel.selectedEnvironment
            lastSkyboxEnv = initialEnv
            await SkyboxBuilder.rebuild(anchor: skyboxAnchor, for: initialEnv)

            do {
                popSoundResource = try await AudioFileResource(named: "pop")
            } catch {
                print("[Audio] pop sound resource not found: \(error.localizedDescription)")
            }
            bubbleStore.lastSeenPopCount = appModel.gameController.popCount

            let armsAnchor = AnchorEntity(.head, trackingMode: .continuous)
            armsAnchor.name = "ArmsAnchor"
            bubbleStore.armsAnchor = armsAnchor

            let armsRoot = Entity()
            armsRoot.name = "ArmsRoot"
            armsRoot.isEnabled = false

            if let rightSource = await loadArmEntity(named: "handpoint") {
                let rightHand = rightSource.clone(recursive: true)
                configureHandEntity(rightHand, for: .right)
                rightHand.name = handPoseName(for: .right)
                rightHand.isEnabled = false
                armsRoot.addChild(rightHand)
                print("Loaded right hand asset: handpoint")
            } else {
                print("Failed to load right hand asset: handpoint")
            }

            if let leftSource = await loadArmEntity(named: "lefthandpoint") {
                let leftHand = leftSource.clone(recursive: true)
                configureHandEntity(leftHand, for: .left)
                leftHand.name = handPoseName(for: .left)
                leftHand.isEnabled = false
                armsRoot.addChild(leftHand)
                print("Loaded left hand asset: lefthandpoint")
            } else {
                print("Failed to load left hand asset: lefthandpoint")
            }

            if let progressBar = attachments.entity(for: "progressBar") {
                progressBar.name = "ProgressBar"
                progressBar.position = SIMD3<Float>(0.0, -0.16, -0.50)
                progressBar.scale = SIMD3<Float>(repeating: 0.85)
                armsAnchor.addChild(progressBar)
            }

            armsAnchor.addChild(armsRoot)
            content.add(armsAnchor)

        } update: { content, _ in
            guard
                let worldAnchor = content.entities.first(where: { $0.name == "WorldAnchor" }),
                let root = worldAnchor.findEntity(named: "Root"),
                let startOrb = root.findEntity(named: "StartOrb") as? ModelEntity,
                let armsAnchor = content.entities.first(where: { $0.name == "ArmsAnchor" }),
                let armsRoot = armsAnchor.findEntity(named: "ArmsRoot")
            else { return }

            let currentEnv = appModel.selectedEnvironment
            if lastSkyboxEnv != currentEnv,
               let skyboxAnchor = content.entities.first(where: { $0.name == "SkyboxAnchor" }) {
                lastSkyboxEnv = currentEnv
                Task { @MainActor in
                    await SkyboxBuilder.rebuild(anchor: skyboxAnchor, for: currentEnv)
                }
            }

            let controller = appModel.gameController

            if controller.popCount > bubbleStore.lastSeenPopCount {
                let prev = bubbleStore.lastSeenPopCount
                bubbleStore.lastSeenPopCount = controller.popCount
                print("[PopSound] popCount diff \(prev) → \(controller.popCount), state=\(controller.sessionState.rawValue)")
                if controller.sessionState == .playing,
                   let resource = popSoundResource,
                   let position = controller.lastPoppedBubblePosition {
                    playPopSound(at: position, parent: root, resource: resource)
                }
            } else if controller.popCount < bubbleStore.lastSeenPopCount {
                // popCount reset (resetGame) — re-sync without playing a sound
                print("[PopSound] popCount reset \(bubbleStore.lastSeenPopCount) → \(controller.popCount), resyncing")
                bubbleStore.lastSeenPopCount = controller.popCount
            }

            let isReadyStage = controller.sessionState == .ready
            let isCalibrationStage = controller.sessionState == .calibrating
            handleArmAnimationTrigger(in: armsRoot, controller: controller)
            updateArmsRootTransform(armsRoot)

            if isReadyStage || isCalibrationStage {
                controller.targetedBubbleID = nil
                gazeHoverBubbleID = nil
                gazeHoverBeganAt = nil
                if isReadyStage {
                    hideAllHandPoses(in: armsRoot)
                }
                updateGazeCursorAndMarker(
                    result: nil,
                    isVisible: false
                )
                removeAllBubbleEntities(from: root)
            } else {
                // Cursor position and controller.targetedBubbleID are updated
                // every frame in updateCursorEveryFrame() via the .task loop,
                // so they stay live regardless of whether BCI data is active.
                // syncBubbles needs root (from content) so it stays here.
                syncBubbles(
                    in: root,
                    with: controller.bubbles,
                    highlightedID: controller.targetedBubbleID
                )
            }

            let showStartTarget = isReadyStage

            startOrb.isEnabled = showStartTarget
            startOrb.position = startOrbPosition

            updateStartOrbAppearance(
                startOrb,
                highlighted: startTargetHighlighted,
                visible: showStartTarget
            )

            if let startPanel = root.findEntity(named: "StartPanel") {
                startPanel.isEnabled = showStartTarget
                startPanel.position = startPanelPosition
            }

            if let calibrationPanel = root.findEntity(named: "CalibrationPanel") {
                calibrationPanel.isEnabled = isCalibrationStage
                calibrationPanel.position = SIMD3<Float>(0.0, 0.18, 0.02)
            }

            if let panel = root.findEntity(named: "ControlPanel") {
                panel.position = SIMD3<Float>(0.34, 0.18, 0.02)
                panel.scale = SIMD3<Float>(repeating: 0.92)
            }

        } attachments: {
            Attachment(id: "controlPanel") {
                GameControlPanel()
                    .environment(appModel)
            }

            Attachment(id: "startPanel") {
                ImmersiveStartPanel(isHighlighted: startTargetHighlighted)
            }

            Attachment(id: "calibrationPanel") {
                ImmersiveCalibrationPanel(cue: calibrationCue)
            }

            Attachment(id: "progressBar") {
                BubbleProgressBar()
                    .environment(appModel)
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let name = value.entity.name

                    if name == "StartOrb",
                       appModel.gameController.sessionState == .ready {
                        triggerSessionStart()
                        return
                    }

                    guard appModel.gameController.sessionState == .playing else { return }

                    if name == "BackgroundPlane" {
                        clickCount += 1
                        return
                    }

                    guard name.hasPrefix("Bubble_") else { return }

                    clickCount += 1

                    let uuidString = String(name.dropFirst("Bubble_".count))
                    guard let tappedID = UUID(uuidString: uuidString) else { return }

                    appModel.gameController.targetedBubbleID = tappedID
                    appModel.gameController.popBubble(withID: tappedID)
                }
        )
        .onChange(of: appModel.gameController.sessionState) { _, newState in
            if newState != .ready {
                startHoverBeganAt = nil
                startTargetHighlighted = false
            }

            if newState != .calibrating {
                calibrationStartedAt = nil
                calibrationCueIndex = -1
            }

            guard newState == .finished else { return }

            Task { @MainActor in
                dismissWindow(id: appModel.congratsWindowID)
                dismissWindow(id: appModel.missionFailedWindowID)

                switch appModel.gameController.finishReason {
                case .allPopped:
                    openWindow(id: appModel.congratsWindowID)

                default:
                    openWindow(id: appModel.missionFailedWindowID)
                }
            }
        }
        .task { @MainActor in
            if !bubbleStore.arSessionStarted {
                bubbleStore.arSessionStarted = true

                do {
                    try await bubbleStore.arSession.run([bubbleStore.worldTracking])
                } catch {
                    print("ARKit session failed: \(error)")
                }
            }

            while !Task.isCancelled {
                appModel.gameController.update(deltaTime: 1.0 / 60.0)
                updatePreSessionStartInteraction()
                updateCalibrationCue()
                updateBackgroundPlane()
                updateCursorEveryFrame()

                do {
                    try await Task.sleep(for: .seconds(1.0 / 60.0))
                } catch {
                    break
                }
            }
        }
        .onChange(of: appModel.shouldEndSession) { _, shouldEnd in
            guard shouldEnd else { return }

            appModel.shouldEndSession = false

            Task { @MainActor in
                appModel.gameController.resetGame()
                startHoverBeganAt = nil
                startTargetHighlighted = false
                gazeHoverBubbleID = nil
                gazeHoverBeganAt = nil
                clickCount = 0
                bubbleStore.lastSeenClickCount = 0
                bubbleStore.smoothedCursorPosition = nil

                dismissWindow(id: appModel.congratsWindowID)
                dismissWindow(id: appModel.missionFailedWindowID)

                if appModel.immersiveSpaceState == .open {
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                    appModel.immersiveSpaceState = .closed
                }

                openWindow(id: appModel.mainWindowID)
            }
        }
    }

    // MARK: - Head-Ray Targeting
    //
    // This is the programmatic targeting system. It fires a ray from the head
    // pose and selects the nearest bubble within gazeSelectRadius.
    //
    // Visual targeting (what the user *sees* highlighted) is handled separately
    // by HoverEffectComponent on each bubble — the system uses real eye tracking
    // for that rendering without telling us which entity is lit.
    //
    // The two systems work together:
    //   HoverEffectComponent → shows the user which bubble is "aimed at" (eye-accurate)
    //   Head ray             → tells the game which bubble is targeted for BCI logic

    private func currentHeadRayTargetResult(from bubbles: [Bubble]) -> GazeTargetResult {
        guard let ray = currentHeadRayInRootSpace() else {
            // No device anchor — fall back to the most central bubble
            let fallback = bestCentralBubble(from: bubbles)
            let pos = fallback?.position ?? SIMD3<Float>(0, 0.08, 0.02)
            return updateHoverState(bubble: fallback, cursorPosition: smoothCursor(pos))
        }

        var bestBubble: Bubble?
        var bestPerp: Float = .greatestFiniteMagnitude
        var bestDepth: Float = 0.9

        for bubble in bubbles where !bubble.isGone {
            let toBubble = bubble.position - ray.origin
            let depth = simd_dot(toBubble, ray.direction)
            guard depth > 0 else { continue }

            let closestPoint = ray.origin + ray.direction * depth
            let perp = simd_distance(bubble.position, closestPoint)

            if perp < bestPerp {
                bestPerp = perp
                bestDepth = depth
                bestBubble = bubble
            }
        }

        let cursorDepth = max(0.55, min(bestDepth, 1.35))
        let rawCursorPos = ray.origin + ray.direction * cursorDepth

        if bestPerp <= gazeSelectRadius, let bubble = bestBubble {
            // Snap cursor to the bubble centre when the ray is close enough
            return updateHoverState(
                bubble: bubble,
                cursorPosition: smoothCursor(bubble.position)
            )
        } else {
            return updateHoverState(
                bubble: nil,
                cursorPosition: smoothCursor(rawCursorPos)
            )
        }
    }

    /// Returns a ray from the head centre in the head-forward direction.
    /// The cursor follows this ray; HoverEffectComponent uses real eye tracking.
    private func currentHeadRayInRootSpace() -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        guard let deviceAnchor = bubbleStore.worldTracking.queryDeviceAnchor(
            atTimestamp: CACurrentMediaTime()
        ) else { return nil }

        let t = deviceAnchor.originFromAnchorTransform

        let worldOrigin = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let worldForward = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)

        return (worldOrigin - worldAnchorOffset, simd_normalize(worldForward))
    }

    /// Exponential moving average — smooths cursor movement so it doesn't snap.
    private let cursorSmoothAlpha: Float = 0.20

    private func smoothCursor(_ newPos: SIMD3<Float>) -> SIMD3<Float> {
        guard let existing = bubbleStore.smoothedCursorPosition else {
            bubbleStore.smoothedCursorPosition = newPos
            return newPos
        }
        let s = existing * (1 - cursorSmoothAlpha) + newPos * cursorSmoothAlpha
        bubbleStore.smoothedCursorPosition = s
        return s
    }

    // MARK: - Hover / Dwell state

    private func updateHoverState(
        bubble: Bubble?,
        cursorPosition: SIMD3<Float>
    ) -> GazeTargetResult {
        if gazeHoverBubbleID != bubble?.id {
            gazeHoverBubbleID = bubble?.id
            gazeHoverBeganAt = bubble == nil ? nil : Date()
        }

        let progress: Float
        if let began = gazeHoverBeganAt, bubble != nil {
            progress = Float(min(1.0, Date().timeIntervalSince(began) / gazeDwellDuration))
        } else {
            progress = 0
        }

        return GazeTargetResult(bubble: bubble, cursorPosition: cursorPosition, holdProgress: progress)
    }

    // MARK: - Background plane toggle

    @MainActor
    private func updateBackgroundPlane() {
        let playing = appModel.gameController.sessionState == .playing
        if let plane = bubbleStore.backgroundPlane, plane.isEnabled != playing {
            plane.isEnabled = playing
        }
    }

    // MARK: - Per-frame cursor update
    //
    // The RealityView update: block only fires when SwiftUI detects a state change.
    // When BCI demo data is off and nothing else is changing, update: never runs,
    // so the cursor freezes. This function is called every frame from the .task
    // loop and directly mutates the cursor/marker entity positions, bypassing
    // SwiftUI's change-detection entirely.

    @MainActor
    private func updateCursorEveryFrame() {
        let controller = appModel.gameController
        guard controller.sessionState == .playing else {
            // Hide cursor outside of gameplay
            bubbleStore.gazeCursor?.isEnabled = false
            bubbleStore.holdMarker?.isEnabled = false
            return
        }

        let gazeResult = currentHeadRayTargetResult(from: controller.bubbles)

        // BCI targeting always runs — bubbles still respond to EEG signals
        // and HoverEffectComponent highlighting still works regardless of cursor visibility.
        controller.targetedBubbleID = gazeResult.bubble?.id

        // Cursor and hold marker only render when showCursor is enabled
        updateGazeCursorAndMarker(result: gazeResult, isVisible: appModel.showCursor)
    }

    // MARK: - Pre-session start interaction

    @MainActor
    private func updatePreSessionStartInteraction() {
        let controller = appModel.gameController

        guard controller.sessionState == .ready else {
            startHoverBeganAt = nil
            startTargetHighlighted = false
            return
        }

        let activeTip = controller.activeArm == .left
            ? controller.leftArmState.tipPosition
            : controller.rightArmState.tipPosition

        let distance = simd_distance(activeTip, startOrbPosition)
        let hoverRadius: Float = 0.10
        let dwellDuration: TimeInterval = 0.45

        if distance <= hoverRadius {
            startTargetHighlighted = true
            if startHoverBeganAt == nil {
                startHoverBeganAt = Date()
            } else if let began = startHoverBeganAt,
                      Date().timeIntervalSince(began) >= dwellDuration {
                triggerSessionStart()
            }
        } else {
            startHoverBeganAt = nil
            startTargetHighlighted = false
        }
    }

    @MainActor
    private func updateCalibrationCue() {
        let controller = appModel.gameController

        guard controller.sessionState == .calibrating,
              let armsRoot = bubbleStore.armsAnchor?.findEntity(named: "ArmsRoot") else {
            return
        }

        let now = Date()
        if calibrationStartedAt == nil {
            calibrationStartedAt = now
            calibrationCueIndex = -1
        }

        guard let startedAt = calibrationStartedAt else { return }

        let thinkDelay: TimeInterval = 3.0
        let animationPlaybackWindow: TimeInterval = 2.0
        let cueDuration = thinkDelay + animationPlaybackWindow
        let elapsed = now.timeIntervalSince(startedAt)
        let nextIndex = Int(elapsed / cueDuration)
        let cues = CalibrationCue.allCases

        guard nextIndex < cues.count else {
            hideAllHandPoses(in: armsRoot)
            controller.completeCalibration()
            return
        }

        guard nextIndex != calibrationCueIndex else { return }

        calibrationCueIndex = nextIndex
        calibrationCue = cues[nextIndex]
        handVisibilityToken += 1
        let token = handVisibilityToken
        hideAllHandPoses(in: armsRoot)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(thinkDelay))
            guard handVisibilityToken == token,
                  controller.sessionState == .calibrating else { return }

            switch calibrationCue {
            case .right:
                showHands([.right], in: armsRoot)

            case .left:
                showHands([.left], in: armsRoot)

            case .both:
                showHands([.left, .right], in: armsRoot)
            }
        }
    }

    @MainActor
    private func triggerSessionStart() {
        guard appModel.gameController.sessionState == .ready else { return }
        startHoverBeganAt = nil
        startTargetHighlighted = false
        appModel.gameController.startSession()
    }

    // MARK: - Hand animation helpers

    private func handPoseName(for arm: ActiveArm) -> String {
        arm == .left ? "LeftHandPoint" : "RightHandPoint"
    }

    private func loadArmEntity(named name: String) async -> Entity? {
        do {
            return try await Entity(named: name, in: realityKitContentBundle)
        } catch {
            print("Failed to load arm asset \(name): \(error)")
            return nil
        }
    }

    private func configureHandEntity(_ entity: Entity, for arm: ActiveArm) {
        let transform = transformForHand(arm)
        entity.position = transform.position
        entity.scale = transform.scale
        entity.orientation = transform.orientation
    }

    private func transformForHand(_ arm: ActiveArm) -> ArmVisualTransform {
        let baseScale = SIMD3<Float>(repeating: 0.90)
        let rotateX = simd_quatf(angle: .pi * 0.5, axis: SIMD3<Float>(1, 0, 0))
        let rotateY = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        let baseOrientation = rotateX * rotateY

        let xOffset: Float = arm == .left ? -0.06 : 0.06
        let yaw: Float = arm == .left ? -.pi / 14 : .pi / 14

        return ArmVisualTransform(
            position: SIMD3<Float>(xOffset, -0.34, -0.30),
            scale: baseScale,
            orientation: baseOrientation * simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        )
    }

    @MainActor
    private func handleArmAnimationTrigger(in armsRoot: Entity, controller: BubbleGameController) {
        guard lastSeenArmAnimationTriggerCount != controller.armAnimationTriggerCount else { return }
        lastSeenArmAnimationTriggerCount = controller.armAnimationTriggerCount

        guard controller.sessionState == .playing,
              let prediction = controller.armAnimationPrediction else {
            hideAllHandPoses(in: armsRoot)
            return
        }

        switch prediction {
        case .left:
            showHand(.left, in: armsRoot, hideAfter: 0.90)

        case .right:
            showHand(.right, in: armsRoot, hideAfter: 0.90)

        case .both:
            let hand = visibleHand(in: armsRoot) ?? controller.activeArm
            let token = showHand(hand, in: armsRoot, hideAfter: 1.05)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.46))
                guard handVisibilityToken == token else { return }
                controller.completeArmAnimationPop()
            }
        }
    }

    @MainActor
    @discardableResult
    private func showHand(_ arm: ActiveArm, in armsRoot: Entity, hideAfter delay: TimeInterval) -> Int {
        handVisibilityToken += 1
        let token = handVisibilityToken

        showHands([arm], in: armsRoot)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard handVisibilityToken == token else { return }
            hideAllHandPoses(in: armsRoot)
        }

        return token
    }

    @MainActor
    private func showHands(_ arms: [ActiveArm], in armsRoot: Entity) {
        let targetNames = Set(arms.map(handPoseName(for:)))
        armsRoot.isEnabled = true

        for child in armsRoot.children {
            child.isEnabled = targetNames.contains(child.name)
        }

        for name in targetNames {
            guard let pose = armsRoot.findEntity(named: name) else { continue }
            pose.stopAllAnimations(recursive: true)
            playAnimationIfAvailable(on: pose)
        }
    }

    private func visibleHand(in armsRoot: Entity) -> ActiveArm? {
        if armsRoot.findEntity(named: handPoseName(for: .left))?.isEnabled == true {
            return .left
        }

        if armsRoot.findEntity(named: handPoseName(for: .right))?.isEnabled == true {
            return .right
        }

        return nil
    }

    private func hideAllHandPoses(in armsRoot: Entity) {
        for child in armsRoot.children {
            child.isEnabled = false
        }
        armsRoot.isEnabled = false
    }

    private func updateArmsRootTransform(_ armsRoot: Entity) {
        let targetTransform = Transform(
            scale: SIMD3<Float>(repeating: 1.0),
            rotation: simd_quatf(angle: 0.0, axis: SIMD3<Float>(0, 1, 0)),
            translation: .zero
        )
        armsRoot.move(to: targetTransform, relativeTo: armsRoot.parent,
                      duration: 0.10, timingFunction: .easeInOut)
    }

    private func playAnimationIfAvailable(on entity: Entity) {
        if let animated = findAnimatedEntity(in: entity),
           let animation = animated.availableAnimations.last {
            animated.playAnimation(animation, transitionDuration: 0.22, startsPaused: false)
        }
    }

    private func findAnimatedEntity(in entity: Entity) -> Entity? {
        for child in entity.children {
            if let found = findAnimatedEntity(in: child) { return found }
        }
        return entity.availableAnimations.isEmpty ? nil : entity
    }

    // MARK: - Bubble helpers

    private func bestCentralBubble(from bubbles: [Bubble]) -> Bubble? {
        var best: Bubble?
        var bestScore: Float = .greatestFiniteMagnitude
        for bubble in bubbles where !bubble.isGone {
            let score = sqrt(bubble.position.x * bubble.position.x
                           + bubble.position.y * bubble.position.y * 1.35)
                      + abs(bubble.position.z) * 0.20
            if score < bestScore { bestScore = score; best = bubble }
        }
        return best
    }

    private func makeBubbleEntity(for bubble: Bubble, highlighted: Bool = false) -> ModelEntity {
        let radius = appModel.gameController.stageConfig.bubbleRadius

        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [makeBubbleMaterial(color: bubble.type.uiColor, highlighted: highlighted)]
        )
        entity.name = "Bubble_\(bubble.id.uuidString)"
        entity.position = bubble.position
        entity.scale = SIMD3<Float>(repeating: highlighted ? 1.18 : 1.0)
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
        entity.components.set(InputTargetComponent())
        // HoverEffectComponent: the system uses real eye tracking to render a glow
        // when the user looks at this bubble. No callback is available — Apple
        // intentionally keeps gaze private — but the visual feedback is eye-accurate.
        entity.components.set(HoverEffectComponent(
            .highlight(HoverEffectComponent.HighlightHoverEffectStyle(
                color: .init(bubble.type.uiColor),
                strength: 1.8
            ))
        ))
        return entity
    }

    private func makeBubbleMaterial(color: UIColor, highlighted: Bool = false) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color.withAlphaComponent(highlighted ? 0.52 : 0.30))
        m.roughness = .init(floatLiteral: 0.05)
        m.metallic = .init(floatLiteral: 0.0)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        m.clearcoat = .init(floatLiteral: 1.0)
        m.clearcoatRoughness = .init(floatLiteral: 0.0)
        m.emissiveColor = .init(color: color)
        m.emissiveIntensity = highlighted ? 4.5 : 1.5
        return m
    }

    private func makeGazeCursorEntity() -> ModelEntity {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.95))
        return ModelEntity(mesh: .generateSphere(radius: 0.018), materials: [material])
    }

    private func makeHoldMarkerEntity() -> ModelEntity {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.65))
        let entity = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [material])
        entity.scale = SIMD3<Float>(1.25, 0.10, 1.25)
        return entity
    }

    private func makeCursorMaterial(for bubble: Bubble) -> UnlitMaterial {
        var m = UnlitMaterial()
        m.color = .init(tint: bubble.type.uiColor.withAlphaComponent(0.95))
        return m
    }

    private func makeMarkerMaterial(for bubble: Bubble) -> UnlitMaterial {
        var m = UnlitMaterial()
        m.color = .init(tint: bubble.type.uiColor.withAlphaComponent(0.62))
        return m
    }

    private func updateGazeCursorAndMarker(
        result: GazeTargetResult?,
        isVisible: Bool
    ) {
        guard let cursor = bubbleStore.gazeCursor,
              let marker = bubbleStore.holdMarker else { return }

        guard isVisible, let result else {
            cursor.isEnabled = false
            marker.isEnabled = false
            return
        }

        cursor.position = result.cursorPosition
        cursor.isEnabled = true

        if let target = result.bubble {
            marker.position = SIMD3<Float>(
                target.position.x,
                target.position.y - appModel.gameController.stageConfig.bubbleRadius - 0.026,
                target.position.z
            )
            let progressScale: Float = 1.25 + result.holdProgress * 0.75
            marker.scale = SIMD3<Float>(progressScale, 0.10, progressScale)
            marker.isEnabled = true
            cursor.model?.materials = [makeCursorMaterial(for: target)]
            marker.model?.materials = [makeMarkerMaterial(for: target)]
        } else {
            marker.isEnabled = false
            var m = UnlitMaterial()
            m.color = .init(tint: UIColor.white.withAlphaComponent(0.85))
            cursor.model?.materials = [m]
        }
    }

    private func syncBubbles(in root: Entity, with bubbles: [Bubble], highlightedID: UUID?) {
        let activeIDs = Set(bubbles.filter { !$0.isGone }.map { $0.id })

        for id in bubbleStore.entities.keys where !activeIDs.contains(id) {
            bubbleStore.entities[id]?.removeFromParent()
            bubbleStore.entities.removeValue(forKey: id)
        }

        for bubble in bubbles where !bubble.isGone {
            let isHighlighted = bubble.id == highlightedID

            if let entity = bubbleStore.entities[bubble.id] {
                entity.position = bubble.position
                entity.scale = SIMD3<Float>(repeating: isHighlighted ? 1.18 : 1.0)
                entity.model?.materials = [makeBubbleMaterial(color: bubble.type.uiColor, highlighted: isHighlighted)]
            } else {
                let entity = makeBubbleEntity(for: bubble, highlighted: isHighlighted)
                root.addChild(entity)
                bubbleStore.entities[bubble.id] = entity
            }
        }
    }

    private func removeAllBubbleEntities(from root: Entity) {
        bubbleStore.entities.values.forEach { $0.removeFromParent() }
        bubbleStore.entities.removeAll()
    }

    private func makeStartOrbEntity(name: String, position: SIMD3<Float>, highlighted: Bool) -> ModelEntity {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: (highlighted ? UIColor.systemGreen : UIColor.systemPurple).withAlphaComponent(0.95))
        m.emissiveColor = .init(color: highlighted ? .white : .systemPink)
        let entity = ModelEntity(mesh: .generateSphere(radius: highlighted ? 0.055 : 0.045), materials: [m])
        entity.name = name
        entity.position = position
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.06)]))
        entity.components.set(InputTargetComponent())
        return entity
    }

    private func updateStartOrbAppearance(_ entity: ModelEntity, highlighted: Bool, visible: Bool) {
        entity.scale = visible
            ? SIMD3<Float>(repeating: highlighted ? 1.18 : 1.0)
            : SIMD3<Float>(repeating: 0.001)

        if var m = entity.model?.materials.first as? PhysicallyBasedMaterial {
            m.baseColor = .init(tint: (highlighted ? UIColor.systemGreen : UIColor.systemPurple).withAlphaComponent(0.95))
            m.emissiveColor = .init(color: highlighted ? .white : .systemPink)
            entity.model?.materials = [m]
        }
    }

    /// Spawn a transient spatial-audio entity at the popped-bubble position,
    /// play the pop sound, and clean up shortly after.
    @MainActor
    private func playPopSound(at position: SIMD3<Float>, parent: Entity, resource: AudioFileResource) {
        let id = UUID().uuidString.prefix(8)
        let t = CACurrentMediaTime()
        let activeBefore = parent.children.filter { $0.name == "PopSound" }.count
        print("[PopSound] play id=\(id) pos=(\(position.x),\(position.y),\(position.z)) t=\(String(format: "%.3f", t)) activeBefore=\(activeBefore)")

        let audioEntity = Entity()
        audioEntity.name = "PopSound"
        audioEntity.position = position
        audioEntity.spatialAudio = SpatialAudioComponent()
        parent.addChild(audioEntity)
        audioEntity.playAudio(resource)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            audioEntity.removeFromParent()
            print("[PopSound] cleanup id=\(id) t=\(String(format: "%.3f", CACurrentMediaTime()))")
        }
    }
}

// MARK: - Immersive Calibration Panel

private struct ImmersiveCalibrationPanel: View {
    let cue: CalibrationCue

    private var cueIndex: Int {
        CalibrationCue.allCases.firstIndex(of: cue) ?? 0
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Calibration")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text(cue.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(cue.prompt)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(CalibrationCue.allCases.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == cueIndex ? Color.green : Color.secondary.opacity(0.30))
                        .frame(width: index == cueIndex ? 28 : 9, height: 9)
                }
            }
            .frame(height: 12)

            Text("Keep your body still and focus only on the imagined movement.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(width: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
    }
}

// MARK: - Immersive Start Panel

struct ImmersiveStartPanel: View {
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text("Ready to Begin?")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text("Move the active arm onto the glowing orb to start.")
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text(isHighlighted ? "Hold steady..." : "Awaiting arm input")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHighlighted ? .green : .purple)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}
