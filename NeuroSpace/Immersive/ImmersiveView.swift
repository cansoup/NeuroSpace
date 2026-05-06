//
//  ImmersiveView.swift
//  NeuroSpace


import SwiftUI
import RealityKit
import RealityKitContent
import ARKit
import simd
import QuartzCore

private enum BubbleZone: String, CaseIterable {
    case upperLeft
    case upperMiddle
    case upperRight
    case middleLeft
    case middleMiddle
    case middleRight
    case lowerLeft
    case lowerMiddle
    case lowerRight

    var assetName: String {
        switch self {
        case .upperLeft: return "upperleft"
        case .upperMiddle: return "uppermiddle"
        case .upperRight: return "upperright"
        case .middleLeft: return "middleleft"
        case .middleMiddle: return "middlemiddleanim"
        case .middleRight: return "middleright"
        case .lowerLeft: return "lowleft"
        case .lowerMiddle: return "lowmiddle"
        case .lowerRight: return "lowright"
        }
    }
}

private enum PoseVariant: String {
    case left = "L"
    case right = "R"
}

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

    private final class BubbleEntityStore {
        var entities: [UUID: ModelEntity] = [:]
        var lastSeenClickCount: Int = 0
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

            worldAnchor.addChild(root)
            content.add(worldAnchor)
            bubbleStore.worldAnchor = worldAnchor

            let starField = makeStarField(count: 300, radius: 20.0)
            starField.name = "StarField"
            content.add(starField)

            let armsAnchor = AnchorEntity(.head, trackingMode: .continuous)
            armsAnchor.name = "ArmsAnchor"
            bubbleStore.armsAnchor = armsAnchor

            let armsRoot = Entity()
            armsRoot.name = "ArmsRoot"

            for zone in BubbleZone.allCases {
                if let sourcePose = await loadArmEntity(named: zone.assetName) {
                    let rightPose = sourcePose.clone(recursive: true)
                    configurePoseEntity(rightPose, for: zone, variant: .right)
                    rightPose.name = poseName(for: zone, variant: .right)
                    rightPose.isEnabled = false
                    armsRoot.addChild(rightPose)

                    let leftPose = sourcePose.clone(recursive: true)
                    configurePoseEntity(leftPose, for: zone, variant: .left)
                    leftPose.name = poseName(for: zone, variant: .left)
                    leftPose.isEnabled = false
                    armsRoot.addChild(leftPose)

                    print("Loaded arm pose variants: \(zone.assetName)")
                } else {
                    print("Failed to load arm pose: \(zone.assetName)")
                }
            }

            if let idlePose = armsRoot.findEntity(
                named: poseName(for: .middleMiddle, variant: .right)
            ) {
                idlePose.isEnabled = true
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

            let controller = appModel.gameController

            let isReadyStage = controller.sessionState == .ready

            let useIdleArm =
                controller.sessionState == .ready ||
                controller.sessionState == .finished

            let activeState = controller.activeArm == .left
                ? controller.leftArmState
                : controller.rightArmState

            let variantToShow: PoseVariant = useIdleArm
                ? .right
                : (controller.activeArm == .left ? .left : .right)

            let currentZone = currentVisibleZone(
                in: armsRoot,
                variant: variantToShow
            )

            let zoneToShow: BubbleZone = useIdleArm
                ? .middleMiddle
                : stableVisualZone(
                    for: activeState,
                    currentZone: currentZone
                )

            updateArmPoseDisplay(
                in: armsRoot,
                zone: zoneToShow,
                variant: variantToShow,
                animateOnChange: controller.sessionState == .playing
            )

            let feedbackCount = clickCount + controller.popCount

            if feedbackCount != bubbleStore.lastSeenClickCount {
                bubbleStore.lastSeenClickCount = feedbackCount

                let tapPoseName = poseName(
                    for: zoneToShow,
                    variant: variantToShow
                )

                if let pose = armsRoot.findEntity(named: tapPoseName) {
                    Task { @MainActor in
                        playAnimationIfAvailable(on: pose)
                    }
                }
            }

            updateArmsRootTransform(
                armsRoot,
                activeState: activeState,
                activeArm: controller.activeArm,
                isReadyStage: useIdleArm
            )

            if isReadyStage {
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

        // Keep controller target fresh every frame regardless of BCI activity
        controller.targetedBubbleID = gazeResult.bubble?.id

        // Directly update entity positions — no SwiftUI state change needed
        updateGazeCursorAndMarker(result: gazeResult, isVisible: true)
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
    private func triggerSessionStart() {
        guard appModel.gameController.sessionState == .ready else { return }
        startHoverBeganAt = nil
        startTargetHighlighted = false
        appModel.gameController.startSession()
    }

    // MARK: - Arm pose helpers

    private func poseName(for zone: BubbleZone, variant: PoseVariant) -> String {
        "Pose_\(variant.rawValue)_\(zone.rawValue)"
    }

    private func loadArmEntity(named name: String) async -> Entity? {
        do {
            return try await Entity(named: name, in: realityKitContentBundle)
        } catch {
            print("Failed to load arm asset \(name): \(error)")
            return nil
        }
    }

    private func configurePoseEntity(_ entity: Entity, for zone: BubbleZone, variant: PoseVariant) {
        let transform = transformForZone(zone, variant: variant)
        entity.position = transform.position
        entity.scale = transform.scale
        entity.orientation = transform.orientation
    }

    private func transformForZone(_ zone: BubbleZone, variant: PoseVariant) -> ArmVisualTransform {
        let baseScale = SIMD3<Float>(repeating: 0.90)
        let rotateX = simd_quatf(angle: .pi * 0.5, axis: SIMD3<Float>(1, 0, 0))
        let rotateY = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        let baseOrientation = rotateX * rotateY

        let rightTransform: ArmVisualTransform

        switch zone {
        case .upperLeft:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(-0.02, -0.26, -0.30), scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: -.pi / 10, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: -.pi / 20, axis: SIMD3<Float>(0, 0, 1)))
        case .upperMiddle:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.0, -0.24, -0.30), scale: baseScale,
                orientation: baseOrientation)
        case .upperRight:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.02, -0.25, -0.30), scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: .pi / 18, axis: SIMD3<Float>(0, 1, 0)))
        case .middleLeft:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(-0.04, -0.31, -0.30), scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: -.pi / 8, axis: SIMD3<Float>(0, 1, 0)))
        case .middleMiddle:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.0, -0.30, -0.30), scale: baseScale,
                orientation: baseOrientation)
        case .middleRight:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.06, -0.35, -0.28), scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: .pi / 10, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: -.pi / 16, axis: SIMD3<Float>(1, 0, 0)))
        case .lowerLeft:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(-0.03, -0.37, -0.28), scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: -.pi / 9, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: .pi / 14, axis: SIMD3<Float>(0, 0, 1)))
        case .lowerMiddle:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.0, -0.39, -0.28), scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: .pi / 18, axis: SIMD3<Float>(1, 0, 0)))
        case .lowerRight:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.04, -0.37, -0.28), scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: .pi / 9, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: -.pi / 14, axis: SIMD3<Float>(0, 0, 1)))
        }

        guard variant == .left else { return rightTransform }

        let mirroredPosition = SIMD3<Float>(-rightTransform.position.x, rightTransform.position.y, rightTransform.position.z)
        var mirroredScale = rightTransform.scale
        mirroredScale.x *= -1
        let mirroredOrientation = simd_quatf(angle: -.pi / 6, axis: SIMD3<Float>(0, 1, 0)) * rightTransform.orientation

        return ArmVisualTransform(position: mirroredPosition, scale: mirroredScale, orientation: mirroredOrientation)
    }

    private func currentVisibleZone(in armsRoot: Entity, variant: PoseVariant) -> BubbleZone? {
        let prefix = "Pose_\(variant.rawValue)_"
        for child in armsRoot.children where child.isEnabled {
            guard child.name.hasPrefix(prefix) else { continue }
            return BubbleZone(rawValue: String(child.name.dropFirst(prefix.count)))
        }
        return nil
    }

    private func stableVisualZone(for state: ArmState, currentZone: BubbleZone?) -> BubbleZone {
        let delta = state.tipPosition - state.basePosition
        let vHigh: Float = 0.15, vLow: Float = 0.09
        let hHigh: Float = 0.11, hLow: Float = 0.06

        let vertical: Int
        switch currentZone {
        case .some(.upperLeft), .some(.upperMiddle), .some(.upperRight):
            vertical = delta.y < vLow ? 0 : 1
        case .some(.lowerLeft), .some(.lowerMiddle), .some(.lowerRight):
            vertical = delta.y > -vLow ? 0 : -1
        default:
            vertical = delta.y > vHigh ? 1 : delta.y < -vHigh ? -1 : 0
        }

        let horizontal: Int
        switch currentZone {
        case .some(.upperLeft), .some(.middleLeft), .some(.lowerLeft):
            horizontal = delta.x > -hLow ? 0 : -1
        case .some(.upperRight), .some(.middleRight), .some(.lowerRight):
            horizontal = delta.x < hLow ? 0 : 1
        default:
            horizontal = delta.x < -hHigh ? -1 : delta.x > hHigh ? 1 : 0
        }

        switch (vertical, horizontal) {
        case (1, -1): return .upperLeft
        case (1,  0): return .upperMiddle
        case (1,  1): return .upperRight
        case (0, -1): return .middleLeft
        case (0,  0): return .middleMiddle
        case (0,  1): return .middleRight
        case (-1,-1): return .lowerLeft
        case (-1, 0): return .lowerMiddle
        case (-1, 1): return .lowerRight
        default:      return .middleMiddle
        }
    }

    private func updateArmPoseDisplay(
        in armsRoot: Entity,
        zone: BubbleZone,
        variant: PoseVariant,
        animateOnChange: Bool
    ) {
        let targetName = poseName(for: zone, variant: variant)
        guard armsRoot.children.first(where: { $0.isEnabled })?.name != targetName else { return }

        for child in armsRoot.children {
            child.isEnabled = child.name == targetName
        }

        if animateOnChange, let pose = armsRoot.findEntity(named: targetName) {
            playAnimationIfAvailable(on: pose)
        }
    }

    private func updateArmsRootTransform(
        _ armsRoot: Entity,
        activeState: ArmState,
        activeArm: ActiveArm,
        isReadyStage: Bool
    ) {
        _ = activeState; _ = activeArm
        let targetTransform = Transform(
            scale: SIMD3<Float>(repeating: 1.0),
            rotation: simd_quatf(angle: 0.0, axis: SIMD3<Float>(0, 1, 0)),
            translation: .zero
        )
        armsRoot.move(to: targetTransform, relativeTo: armsRoot.parent,
                      duration: isReadyStage ? 0.20 : 0.10, timingFunction: .easeInOut)
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

    private func makeStarField(count: Int, radius: Float) -> Entity {
        let root = Entity()
        for _ in 0..<count {
            let theta = Float.random(in: 0...(2 * .pi))
            let phi = acos(Float.random(in: -1...1))
            let r = radius * Float.random(in: 0.85...1.0)
            let size = Float.random(in: 0.01...0.04)
            let brightness = Float.random(in: 0.5...1.0)

            var m = UnlitMaterial()
            let roll = Int.random(in: 0...100)
            if roll < 5 {
                m.color = .init(tint: UIColor(red: 0.7, green: 0.85, blue: 1.0, alpha: CGFloat(brightness)))
            } else if roll < 8 {
                m.color = .init(tint: UIColor(red: 1.0, green: 0.9, blue: 0.7, alpha: CGFloat(brightness)))
            } else {
                m.color = .init(tint: UIColor(white: CGFloat(brightness), alpha: 1.0))
            }

            let star = ModelEntity(mesh: .generateSphere(radius: size), materials: [m])
            star.position = SIMD3<Float>(
                r * sin(phi) * cos(theta),
                r * sin(phi) * sin(theta),
                r * cos(phi)
            )
            root.addChild(star)
        }
        return root
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
