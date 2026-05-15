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

    // Stage-end dwell tracking — mirrors gazeHoverBubbleID / gazeHoverBeganAt
    @State private var stageEndDwellTarget: StageEndChoice? = nil
    @State private var stageEndDwellBeganAt: Date? = nil
    @State private var stageEndDwellFired: Bool = false
    @State private var stageEndDwellProgress: Double = 0.0

    private final class BubbleEntityStore {
        var entities: [UUID: ModelEntity] = [:]
        var lastSeenClickCount: Int = 0
        var lastSeenPopCount: Int = 0
        weak var worldAnchor: AnchorEntity?
        weak var armsAnchor: AnchorEntity?
        weak var backgroundPlane: Entity?
        weak var gazeCursor: ModelEntity?
        weak var holdMarker: ModelEntity?
        // Stage-end option spheres
        weak var stageEndRoot: Entity?
        var stageEndSpheres: [String: ModelEntity] = [:]
        let arSession = ARKitSession()
        let worldTracking = WorldTrackingProvider()
        var arSessionStarted = false
        // Smoothed cursor position for exponential interpolation
        var smoothedCursorPosition: SIMD3<Float>? = nil
    }

    /// Root content offset relative to the head anchor at session start.
    /// Y = -0.11 m compensates for the bubble Y-range bias (-0.08 ... 0.30,
    /// midpoint ≈ +0.11) so spawned bubbles average at the user's actual
    /// eye level instead of above it. Z = -1.0 m places the play space one
    /// metre in front of the user.
    private let worldAnchorOffset = SIMD3<Float>(0, -0.11, -1.0)
    @State private var bubbleStore = BubbleEntityStore()

    // How close (metres) the head ray must pass to a bubble to select it
    private let gazeSelectRadius: Float = 0.11
    private let gazeDwellDuration: TimeInterval = 0.65
    /// Longer dwell for stage-end option bubbles — gives the user time to decide.
    private let stageEndDwellDuration: TimeInterval = 5.0

    var body: some View {
        RealityView { content, attachments in
            // Anchor the play space to the user's head position at session
            // start (.once), so the world adapts to actual eye height instead
            // of a hardcoded 1.45 m. After the initial lock the anchor stays
            // put — content does not follow head movement.
            let worldAnchor = AnchorEntity(.head, trackingMode: .once)
            worldAnchor.name = "WorldAnchor"

            let root = Entity()
            root.name = "Root"
            root.position = worldAnchorOffset

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

            // Result card: world-anchored, sits just above the option bubbles
            // seRoot is at (-0.03, -0.05, 0.0), spheres radius 0.09 → top ~y=0.04
            // Place card at y=0.20 so it clears the bubbles with a small gap
            if let result = attachments.entity(for: "resultPanel") {
                result.name = "ResultPanel"
                result.position = SIMD3<Float>(-0.03, 0.22, 0.0)
                root.addChild(result)
            }

            // ── Stage-end option spheres ─────────────────────────────────────────
            // Three real RealityKit spheres (same material as game bubbles) that
            // float in the space after a stage ends.  Labels are SwiftUI attachments.
            let seRoot = Entity()
            seRoot.name = "StageEndRoot"
            seRoot.isEnabled = false

            // Sphere configs: (name, colour, x-offset)
            // Shifted left so "next" doesn't overlap the HUD panel (x=0.34)
            let seConfigs: [(String, UIColor, Float)] = [
                (StageEndChoice.lobby.rawValue, UIColor(DS.textSecondary).withAlphaComponent(0.9), -0.38),
                (StageEndChoice.retry.rawValue, UIColor(DS.warning),                               -0.06),
                (StageEndChoice.next.rawValue,  UIColor(DS.teal),                                   0.26)
            ]

            for (name, color, xOffset) in seConfigs {
                let sphere = makeStageEndSphere(color: color)
                sphere.name = name
                sphere.position = SIMD3<Float>(xOffset, 0.0, 0.0)
                seRoot.addChild(sphere)
                bubbleStore.stageEndSpheres[name] = sphere

                // Label attachment sits 0.14 m below the sphere centre
                if let label = attachments.entity(for: name) {
                    label.name = "Label_\(name)"
                    label.position = SIMD3<Float>(0.0, -0.18, 0.0)
                    sphere.addChild(label)
                }
            }

            // Below eye level so bubbles sit under the HUD panel
            seRoot.position = SIMD3<Float>(-0.03, -0.05, 0.0)
            root.addChild(seRoot)
            bubbleStore.stageEndRoot = seRoot

            armsAnchor.addChild(armsRoot)
            content.add(armsAnchor)

        } update: { content, _ in
            guard
                let worldAnchor = content.entities.first(where: { $0.name == "WorldAnchor" }),
                let root = worldAnchor.findEntity(named: "Root"),
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

            let isCalibrationStage = controller.sessionState == .calibrating
            handleArmAnimationTrigger(in: armsRoot, controller: controller)
            updateArmsRootTransform(armsRoot)

            if isCalibrationStage || controller.sessionState == .finished {
                // Calibrating: not started yet. Finished: stage over.
                // Either way, clear all game bubbles from the scene.
                controller.targetedBubbleID = nil
                gazeHoverBubbleID = nil
                gazeHoverBeganAt = nil
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

            if let calibrationPanel = root.findEntity(named: "CalibrationPanel") {
                calibrationPanel.isEnabled = isCalibrationStage
                calibrationPanel.position = SIMD3<Float>(0.0, 0.18, 0.02)
            }

            if let panel = root.findEntity(named: "ControlPanel") {
                panel.position = SIMD3<Float>(0.34, 0.18, 0.02)
                panel.scale = SIMD3<Float>(repeating: 0.92)
            }

            // Show/hide stage-end spheres and sync which options are available
            if let seRoot = root.findEntity(named: "StageEndRoot") {
                let show = appModel.showStageEndBubbles
                seRoot.isEnabled = show

                if show {
                    let passed = controller.finishReason == .allPopped && controller.meetsUnlockCriteria
                    // Hide "Next" sphere when stage was failed
                    if let nextSphere = seRoot.findEntity(named: StageEndChoice.next.rawValue) {
                        nextSphere.isEnabled = passed
                    }
                    // Brighten whichever sphere is currently being dwelled on
                    for choice in [StageEndChoice.lobby, .retry, .next] {
                        if let sphere = seRoot.findEntity(named: choice.rawValue) as? ModelEntity {
                            let isTarget = stageEndDwellTarget == choice
                            let color: UIColor
                            switch choice {
                            case .lobby: color = UIColor(DS.textSecondary).withAlphaComponent(0.9)
                            case .retry: color = UIColor(DS.warning)
                            case .next:  color = UIColor(DS.teal)
                            }
                            sphere.model?.materials = [makeStageEndMaterial(color: color, highlighted: isTarget)]
                        }
                    }
                }
            }

        } attachments: {
            Attachment(id: "controlPanel") {
                GameControlPanel()
                    .environment(appModel)
            }

            Attachment(id: "calibrationPanel") {
                ImmersiveCalibrationPanel(cue: calibrationCue)
            }

            Attachment(id: "progressBar") {
                BubbleProgressBar()
                    .environment(appModel)
            }

            // Result card — head-tracked attachment above the bubbles
            Attachment(id: "resultPanel") {
                switch appModel.stageEndResult {
                case .passed:
                    CongratsView()
                        .environment(appModel)
                case .failed:
                    MissionFailedView()
                        .environment(appModel)
                case .none:
                    EmptyView()
                }
            }

            // Stage-end pill labels — one per sphere, with live dwell countdown
            Attachment(id: StageEndChoice.lobby.rawValue) {
                StageEndLabel(
                    text: "Lobby",
                    color: DS.textSecondary,
                    isActive: stageEndDwellTarget == .lobby,
                    dwellProgress: stageEndDwellTarget == .lobby ? stageEndDwellProgress : 0,
                    dwellDuration: stageEndDwellDuration
                )
            }
            Attachment(id: StageEndChoice.retry.rawValue) {
                StageEndLabel(
                    text: "Retry",
                    color: DS.warning,
                    isActive: stageEndDwellTarget == .retry,
                    dwellProgress: stageEndDwellTarget == .retry ? stageEndDwellProgress : 0,
                    dwellDuration: stageEndDwellDuration
                )
            }
            Attachment(id: StageEndChoice.next.rawValue) {
                let isFinal = appModel.gameController.isOnFinalStage
                StageEndLabel(
                    text: isFinal ? "Finish" : "Next Stage",
                    color: DS.teal,
                    isActive: stageEndDwellTarget == .next,
                    dwellProgress: stageEndDwellTarget == .next ? stageEndDwellProgress : 0,
                    dwellDuration: stageEndDwellDuration
                )
            }


        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let name = value.entity.name

                    guard appModel.gameController.sessionState == .playing else { return }

                    if name == "BackgroundPlane" {
                        clickCount += 1
                        return
                    }

                    // Stage-end option tapped (fallback for direct pinch/tap)
                    if name.hasPrefix("StageEnd_"),
                       appModel.showStageEndBubbles,
                       let choice = StageEndChoice(rawValue: name) {
                        handleStageEndChoice(choice)
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
            if newState != .calibrating {
                calibrationStartedAt = nil
                calibrationCueIndex = -1
            }

            guard newState == .finished else { return }

            Task { @MainActor in
                dismissWindow(id: appModel.congratsWindowID)
                dismissWindow(id: appModel.missionFailedWindowID)

                // Show the in-world bubble menu — it replaces the flat windows
                // when the player is inside the immersive space.
                if appModel.immersiveSpaceState == .open {
                    stageEndDwellTarget = nil
                    stageEndDwellBeganAt = nil
                    stageEndDwellFired = false
                    stageEndDwellProgress = 0.0
                    appModel.showStageEndBubbles = true

                    // Show result as a head-tracked attachment — no floating window
                    switch appModel.gameController.finishReason {
                    case .allPopped: appModel.stageEndResult = .passed
                    default:         appModel.stageEndResult = .failed
                    }
                } else {
                    // Fallback: open the flat window if not in immersive
                    switch appModel.gameController.finishReason {
                    case .allPopped:
                        openWindow(id: appModel.congratsWindowID)
                    default:
                        openWindow(id: appModel.missionFailedWindowID)
                    }
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
                appModel.showStageEndBubbles = false
                appModel.stageEndResult = .none
                stageEndDwellTarget = nil
                stageEndDwellBeganAt = nil
                stageEndDwellFired = false
                stageEndDwellProgress = 0.0
                appModel.gameController.resetGame()
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

        // ── Stage-end dwell mode ──────────────────────────────────────────────
        if appModel.showStageEndBubbles && !stageEndDwellFired {
            updateStageEndDwell()
            // Hide gameplay cursor while stage-end is showing
            bubbleStore.gazeCursor?.isEnabled = false
            bubbleStore.holdMarker?.isEnabled = false
            return
        }

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

    // MARK: - Stage-end dwell

    @MainActor
    private func updateStageEndDwell() {
        guard let ray = currentHeadRayInRootSpace() else { return }

        // Find which stage-end sphere (if any) the head ray is pointing at
        let passed = appModel.gameController.finishReason == .allPopped
                  && appModel.gameController.meetsUnlockCriteria
        var closestChoice: StageEndChoice? = nil
        var closestPerp: Float = .greatestFiniteMagnitude

        let candidates: [StageEndChoice] = passed
            ? [.lobby, .retry, .next]
            : [.lobby, .retry]

        for choice in candidates {
            guard let sphere = bubbleStore.stageEndSpheres[choice.rawValue],
                  sphere.isEnabled else { continue }

            // Get sphere position in root-local space (same space as the head ray)
            let rootPos = sphere.position(relativeTo: bubbleStore.worldAnchor)
            let toBubble = rootPos - ray.origin
            let depth = simd_dot(toBubble, ray.direction)
            guard depth > 0 else { continue }
            let closest = ray.origin + ray.direction * depth
            let perp = simd_distance(rootPos, closest)
            if perp < closestPerp {
                closestPerp = perp
                closestChoice = choice
            }
        }

        let stageEndSelectRadius: Float = 0.22   // generous radius so head-turning is comfortable

        if closestPerp <= stageEndSelectRadius, let choice = closestChoice {
            if stageEndDwellTarget != choice {
                // Switched to a new sphere — reset timer
                stageEndDwellTarget = choice
                stageEndDwellBeganAt = Date()
                stageEndDwellProgress = 0.0
            } else if let began = stageEndDwellBeganAt {
                let elapsed = Date().timeIntervalSince(began)
                stageEndDwellProgress = min(elapsed / stageEndDwellDuration, 1.0)
                if elapsed >= stageEndDwellDuration {
                    stageEndDwellFired = true
                    handleStageEndChoice(choice)
                }
            }
        } else {
            // Not looking at any sphere — reset
            stageEndDwellTarget = nil
            stageEndDwellBeganAt = nil
            stageEndDwellProgress = 0.0
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

// MARK: - Stage-end sphere helpers

extension ImmersiveView {

    /// Creates a RealityKit sphere entity styled like a game bubble.
    func makeStageEndSphere(color: UIColor) -> ModelEntity {
        let radius: Float = 0.09
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [makeStageEndMaterial(color: color, highlighted: false)]
        )
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent(
            .highlight(HoverEffectComponent.HighlightHoverEffectStyle(
                color: .init(color),
                strength: 2.0
            ))
        ))
        return entity
    }

    /// Physically-based material identical to game bubbles.
    func makeStageEndMaterial(color: UIColor, highlighted: Bool) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor       = .init(tint: color.withAlphaComponent(highlighted ? 0.55 : 0.30))
        m.roughness       = .init(floatLiteral: 0.05)
        m.metallic        = .init(floatLiteral: 0.0)
        m.blending        = .transparent(opacity: .init(floatLiteral: 0.45))
        m.clearcoat       = .init(floatLiteral: 1.0)
        m.clearcoatRoughness = .init(floatLiteral: 0.0)
        m.emissiveColor   = .init(color: color)
        m.emissiveIntensity = highlighted ? 5.0 : 1.8
        return m
    }

    /// Routes a confirmed stage-end choice (from dwell or direct tap) to the
    /// appropriate navigation action, mirroring CongratsView / MissionFailedView.
    @MainActor
    func handleStageEndChoice(_ choice: StageEndChoice) {
        // Reset dwell state immediately so the handler only fires once
        stageEndDwellTarget = nil
        stageEndDwellBeganAt = nil

        Task { @MainActor in
            appModel.showStageEndBubbles = false
            appModel.stageEndResult = .none
            stageEndDwellFired = false
            dismissWindow(id: appModel.congratsWindowID)
            dismissWindow(id: appModel.missionFailedWindowID)

            let controller = appModel.gameController

            switch choice {

            case .lobby:
                appModel.saveSessionRecord()
                controller.resetGame()
                if appModel.immersiveSpaceState == .open {
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                    appModel.immersiveSpaceState = .closed
                }
                openWindow(id: appModel.mainWindowID)

            case .retry:
                controller.resetGame(keepStage: true)
                if appModel.immersiveSpaceState == .open {
                    controller.startSession()
                    dismissWindow(id: appModel.mainWindowID)
                }

            case .next:
                guard controller.canAdvanceStage else { return }
                controller.advanceStage()
                if appModel.immersiveSpaceState == .open {
                    controller.startSession()
                    dismissWindow(id: appModel.mainWindowID)
                }
            }
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
