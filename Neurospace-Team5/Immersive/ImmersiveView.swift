//
//  ImmersiveView.swift
//  Neurospace-Team5
//

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

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var startHoverBeganAt: Date? = nil
    @State private var startTargetHighlighted = false
    @State private var clickCount: Int = 0       // increments on every tap while playing

    /// Class wrapper so mutations don't trigger SwiftUI re-renders or
    /// "Modifying state during view update" warnings.
    private final class BubbleEntityStore {
        var entities: [UUID: ModelEntity] = [:]
        var lastSeenClickCount: Int = 0
        weak var worldAnchor: AnchorEntity?
        weak var armsAnchor: AnchorEntity?
        weak var backgroundPlane: Entity?
        let arSession = ARKitSession()
        let worldTracking = WorldTrackingProvider()
        var arSessionStarted = false
    }

    private let worldAnchorOffset = SIMD3<Float>(0, 1.45, -1.0)
    @State private var bubbleStore = BubbleEntityStore()

    private let startOrbPosition = SIMD3<Float>(0.0, -0.06, 0.02)
    private let startPanelPosition = SIMD3<Float>(0.0, 0.20, 0.02)

    var body: some View {
        RealityView { content, attachments in
            let worldAnchor = AnchorEntity(world: worldAnchorOffset)
            worldAnchor.name = "WorldAnchor"

            let root = Entity()
            root.name = "Root"
            root.position = .zero

            // Bubbles are managed via bubbleStore in syncBubbles; none are needed here.

            // Large invisible background entity that catches taps in empty space.
            // Placed behind the bubble interaction zone so bubble entities take
            // priority when directly targeted; misses fall through to this plane.
            let bgEntity = Entity()
            bgEntity.name = "BackgroundPlane"
            bgEntity.position = SIMD3<Float>(0, 0.10, -0.60)   // behind bubble z range
            bgEntity.components.set(CollisionComponent(
                shapes: [.generateBox(width: 6.0, height: 4.0, depth: 0.05)]
            ))
            bgEntity.components.set(InputTargetComponent())
            bgEntity.isEnabled = false   // enabled only while session is playing
            root.addChild(bgEntity)
            bubbleStore.backgroundPlane = bgEntity

            let startOrb = makeStartOrbEntity(
                name: "StartOrb",
                position: startOrbPosition,
                highlighted: false
            )
            root.addChild(startOrb)

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
                playAnimationIfAvailable(on: idlePose)
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
            // isReadyStage: controls StartOrb UI — only shown in .ready state
            let isReadyStage = controller.sessionState == .ready
            // useIdleArm: controls arm pose — idle in .ready and .finished to avoid
            // the arm pointing at the last-popped bubble during stage transitions
            let useIdleArm = controller.sessionState == .ready || controller.sessionState == .finished

            let activeState = controller.activeArm == .left
                ? controller.leftArmState
                : controller.rightArmState

            let zoneToShow: BubbleZone
            let variantToShow: PoseVariant

            // Arm always points center (middleMiddle) — direction is handled by gaze targeting
            zoneToShow = .middleMiddle
            variantToShow = useIdleArm ? .right : (controller.activeArm == .left ? .left : .right)

            updateArmPoseDisplay(
                in: armsRoot,
                zone: zoneToShow,
                variant: variantToShow
            )

            // Re-trigger arm animation on every tap while playing.
            // Mutation goes through bubbleStore (class), not @State, to avoid
            // "Modifying state during view update" warnings.
            // playAnimationIfAvailable is deferred via Task to avoid calling
            // playAnimation during RealityKit's update cycle (bind point warning).
            if clickCount != bubbleStore.lastSeenClickCount {
                bubbleStore.lastSeenClickCount = clickCount
                let tapPoseName = poseName(for: zoneToShow, variant: variantToShow)
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

            // Gaze-based targeting using coordinate-space conversion.
            // bubble.position is in worldAnchor-local space.
            // armsAnchor.convert(position:from:) maps it to head-local space without
            // needing scene entity lookups (which are unreliable in the update closure).
            // In head-local space, screen center = (0, 0, -depth); smallest lateral
            // angle = most centered bubble.
            // Compute gaze targeting, then apply result via Task to avoid mutating
            // @Observable state during the view update cycle.
            // Gaze targeting runs from the .task loop via updateGazeAndFOV(),
            // because the update closure does not re-run on head motion alone.

            if isReadyStage {
                removeAllBubbleEntities(from: root)
            } else {
                syncBubbles(in: root, with: controller.bubbles,
                            targetedID: controller.targetedBubbleID)
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

                    // Ready state: only StartOrb starts the session
                    if name == "StartOrb", appModel.gameController.sessionState == .ready {
                        triggerSessionStart()
                        return
                    }

                    guard appModel.gameController.sessionState == .playing else { return }

                    // Empty-space tap: background entity caught the hit → arm animation only
                    if name == "BackgroundPlane" {
                        clickCount += 1
                        return
                    }

                    guard name.hasPrefix("Bubble_") else { return }

                    // Any bubble tap triggers arm animation
                    clickCount += 1

                    // Only pop if the tapped bubble is the currently targeted one.
                    // Tapping a non-targeted bubble triggers arm animation but no pop.
                    let uuidString = String(name.dropFirst("Bubble_".count))
                    guard let tappedID = UUID(uuidString: uuidString),
                          tappedID == appModel.gameController.targetedBubbleID else { return }

                    appModel.gameController.popTargetedBubble()
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
                updateGazeAndFOV()

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
                clickCount = 0
                bubbleStore.lastSeenClickCount = 0

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

    private func configurePoseEntity(
        _ entity: Entity,
        for zone: BubbleZone,
        variant: PoseVariant
    ) {
        let transform = transformForZone(zone, variant: variant)
        entity.position = transform.position
        entity.scale = transform.scale
        entity.orientation = transform.orientation
    }

    private func transformForZone(
        _ zone: BubbleZone,
        variant: PoseVariant
    ) -> ArmVisualTransform {
        let baseScale = SIMD3<Float>(repeating: 0.90)

        let rotateX = simd_quatf(angle: .pi * 0.5, axis: SIMD3<Float>(1, 0, 0))
        let rotateY = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        let baseOrientation = rotateX * rotateY

        let rightTransform: ArmVisualTransform

        switch zone {
        case .upperLeft:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(-0.02, -0.26, -0.30),
                scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: -.pi / 10, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: -.pi / 20, axis: SIMD3<Float>(0, 0, 1))
            )

        case .upperMiddle:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.0, -0.24, -0.30),
                scale: baseScale,
                orientation: baseOrientation
            )

        case .upperRight:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.02, -0.25, -0.30),
                scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: .pi / 18, axis: SIMD3<Float>(0, 1, 0))
            )

        case .middleLeft:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(-0.04, -0.31, -0.30),
                scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: -.pi / 8, axis: SIMD3<Float>(0, 1, 0))
            )

        case .middleMiddle:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.0, -0.30, -0.30),
                scale: baseScale,
                orientation: baseOrientation
            )

        case .middleRight:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.06, -0.35, -0.28),
                scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: .pi / 10, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: -.pi / 16, axis: SIMD3<Float>(1, 0, 0))
            )

        case .lowerLeft:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(-0.03, -0.37, -0.28),
                scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: -.pi / 9, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: .pi / 14, axis: SIMD3<Float>(0, 0, 1))
            )

        case .lowerMiddle:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.0, -0.39, -0.28),
                scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: .pi / 18, axis: SIMD3<Float>(1, 0, 0))
            )

        case .lowerRight:
            rightTransform = ArmVisualTransform(
                position: SIMD3<Float>(0.04, -0.37, -0.28),
                scale: baseScale,
                orientation: baseOrientation
                    * simd_quatf(angle: .pi / 9, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: -.pi / 14, axis: SIMD3<Float>(0, 0, 1))
            )
        }

        guard variant == .left else { return rightTransform }

        let mirroredPosition = SIMD3<Float>(
            -rightTransform.position.x,
            rightTransform.position.y,
            rightTransform.position.z
        )

        var mirroredScale = rightTransform.scale
        mirroredScale.x *= -1

        let mirroredOrientation =
            simd_quatf(angle: -.pi / 6, axis: SIMD3<Float>(0, 1, 0)) *
            rightTransform.orientation

        return ArmVisualTransform(
            position: mirroredPosition,
            scale: mirroredScale,
            orientation: mirroredOrientation
        )
    }

    private func currentVisibleZone(in armsRoot: Entity, variant: PoseVariant) -> BubbleZone? {
        let prefix = "Pose_\(variant.rawValue)_"

        for child in armsRoot.children where child.isEnabled {
            guard child.name.hasPrefix(prefix) else { continue }
            let suffix = String(child.name.dropFirst(prefix.count))
            return BubbleZone(rawValue: suffix)
        }

        return nil
    }

    private func stableVisualZone(
        for state: ArmState,
        currentZone: BubbleZone?
    ) -> BubbleZone {
        let delta = state.tipPosition - state.basePosition

        let verticalThresholdHigh: Float = 0.15
        let verticalThresholdLow: Float = 0.09
        let horizontalThresholdHigh: Float = 0.11
        let horizontalThresholdLow: Float = 0.06

        let vertical: Int
        switch currentZone {
        case .some(.upperLeft), .some(.upperMiddle), .some(.upperRight):
            vertical = delta.y < verticalThresholdLow ? 0 : 1
        case .some(.lowerLeft), .some(.lowerMiddle), .some(.lowerRight):
            vertical = delta.y > -verticalThresholdLow ? 0 : -1
        default:
            if delta.y > verticalThresholdHigh {
                vertical = 1
            } else if delta.y < -verticalThresholdHigh {
                vertical = -1
            } else {
                vertical = 0
            }
        }

        let horizontal: Int
        switch currentZone {
        case .some(.upperLeft), .some(.middleLeft), .some(.lowerLeft):
            horizontal = delta.x > -horizontalThresholdLow ? 0 : -1
        case .some(.upperRight), .some(.middleRight), .some(.lowerRight):
            horizontal = delta.x < horizontalThresholdLow ? 0 : 1
        default:
            if delta.x < -horizontalThresholdHigh {
                horizontal = -1
            } else if delta.x > horizontalThresholdHigh {
                horizontal = 1
            } else {
                horizontal = 0
            }
        }

        switch (vertical, horizontal) {
        case (1, -1): return .upperLeft
        case (1, 0): return .upperMiddle
        case (1, 1): return .upperRight
        case (0, -1): return .middleLeft
        case (0, 0): return .middleMiddle
        case (0, 1): return .middleRight
        case (-1, -1): return .lowerLeft
        case (-1, 0): return .lowerMiddle
        case (-1, 1): return .lowerRight
        default: return .middleMiddle
        }
    }

    private func updateArmPoseDisplay(
        in armsRoot: Entity,
        zone: BubbleZone,
        variant: PoseVariant
    ) {
        let targetName = poseName(for: zone, variant: variant)
        let currentlyVisibleName = armsRoot.children.first(where: { $0.isEnabled })?.name

        for child in armsRoot.children {
            child.isEnabled = child.name == targetName
        }

        // Play (or restart looping) animation whenever the active pose changes.
        // Also plays on first call when currentlyVisibleName is nil (fresh scene).
        if currentlyVisibleName != targetName,
           let pose = armsRoot.findEntity(named: targetName) {
            playAnimationIfAvailable(on: pose)
        }
    }

    private func updateArmsRootTransform(
        _ armsRoot: Entity,
        activeState: ArmState,
        activeArm: ActiveArm,
        isReadyStage: Bool
    ) {
        let targetTransform: Transform

        if isReadyStage {
            targetTransform = Transform(
                scale: SIMD3<Float>(repeating: 1.0),
                rotation: simd_quatf(angle: 0.0, axis: SIMD3<Float>(0, 1, 0)),
                translation: SIMD3<Float>(0.0, -0.16, -0.16)
            )
        } else {
            // Fix armsRoot at a constant position — arm direction is expressed
            // entirely through USDZ pose selection (stableVisualZone).
            // Delta-based translation caused the center to shift when tipPosition
            // jumped (e.g. clicking a left-side bubble with the right arm).
            targetTransform = Transform(
                scale: SIMD3<Float>(repeating: 1.0),
                rotation: simd_quatf(angle: 0.0, axis: SIMD3<Float>(0, 1, 0)),
                translation: SIMD3<Float>(0.0, -0.30, -0.30)
            )
        }

        let duration: TimeInterval = isReadyStage ? 0.20 : 0.10

        armsRoot.move(
            to: targetTransform,
            relativeTo: armsRoot.parent,
            duration: duration,
            timingFunction: .easeInOut
        )
    }

    private func playAnimationIfAvailable(on entity: Entity) {
        if let animatedEntity = findAnimatedEntity(in: entity),
           let animation = animatedEntity.availableAnimations.last {
            animatedEntity.playAnimation(
                animation,
                transitionDuration: 0.22,
                startsPaused: false
            )
        }
    }

    private func findAnimatedEntity(in entity: Entity) -> Entity? {
        for child in entity.children {
            if let animatedChild = findAnimatedEntity(in: child) {
                return animatedChild
            }
        }

        if !entity.availableAnimations.isEmpty {
            return entity
        }

        return nil
    }

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
    private func updateGazeAndFOV() {
        let controller = appModel.gameController
        let playingNow = controller.sessionState == .playing

        // Background plane catches empty-space taps for arm animation, but
        // must be disabled outside of .playing so SwiftUI windows (Congrats /
        // MissionFailed) are not occluded and can receive taps.
        if let plane = bubbleStore.backgroundPlane, plane.isEnabled != playingNow {
            plane.isEnabled = playingNow
        }

        guard bubbleStore.worldTracking.state == .running,
              let deviceAnchor = bubbleStore.worldTracking.queryDeviceAnchor(
                atTimestamp: CACurrentMediaTime()
              )
        else { return }

        let headFromWorld = simd_inverse(deviceAnchor.originFromAnchorTransform)
        let centerConeRadians: Float = 15.0 * .pi / 180.0

        var bestAngle: Float = .greatestFiniteMagnitude
        var bestID: UUID? = nil

        for bubble in controller.bubbles where !bubble.isGone {
            let bubbleWorld = bubble.position + worldAnchorOffset
            let bubbleWorld4 = SIMD4<Float>(bubbleWorld.x, bubbleWorld.y, bubbleWorld.z, 1)
            let headLocal4 = headFromWorld * bubbleWorld4
            let p = SIMD3<Float>(headLocal4.x, headLocal4.y, headLocal4.z)

            // Forward is -z in head-local space.
            guard p.z < 0 else { continue }

            let lateral = (p.x * p.x + p.y * p.y).squareRoot()
            let angle = atan2(lateral, abs(p.z))

            if playingNow && angle < bestAngle && angle <= centerConeRadians {
                bestAngle = angle
                bestID = bubble.id
            }
        }

        if controller.targetedBubbleID != bestID {
            controller.targetedBubbleID = bestID
        }
    }

    @MainActor
    private func triggerSessionStart() {
        guard appModel.gameController.sessionState == .ready else { return }
        startHoverBeganAt = nil
        startTargetHighlighted = false
        appModel.gameController.startSession()
    }

    private func makeBubbleEntity(for bubble: Bubble, isTargeted: Bool = false) -> ModelEntity {
        let radius = appModel.gameController.stageConfig.bubbleRadius

        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [makeBubbleMaterial(color: bubble.type.uiColor, isTargeted: isTargeted)]
        )

        entity.name = "Bubble_\(bubble.id.uuidString)"
        entity.position = bubble.position
        entity.scale = isTargeted ? SIMD3<Float>(repeating: 1.3) : SIMD3<Float>(repeating: 1.0)
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
        entity.components.set(InputTargetComponent())

        return entity
    }

    private func makeBubbleMaterial(color: UIColor, isTargeted: Bool = false) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()

        if isTargeted {
            // Targeted: solid bright white-tinted version of the bubble color + strong glow
            material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: UIColor.white)
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.0)
            material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.92))
            material.clearcoat = PhysicallyBasedMaterial.Clearcoat(floatLiteral: 1.0)
            material.clearcoatRoughness = PhysicallyBasedMaterial.ClearcoatRoughness(floatLiteral: 0.0)
            material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: color)
            material.emissiveIntensity = 3.0
        } else {
            // Normal: translucent with bubble's own color
            material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color.withAlphaComponent(0.25))
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.0)
            material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.25))
            material.clearcoat = PhysicallyBasedMaterial.Clearcoat(floatLiteral: 1.0)
            material.clearcoatRoughness = PhysicallyBasedMaterial.ClearcoatRoughness(floatLiteral: 0.0)
        }

        return material
    }

    private func syncBubbles(in root: Entity, with bubbles: [Bubble], targetedID: UUID?) {
        let activeIDs = Set(bubbles.filter { !$0.isGone }.map { $0.id })

        // Remove entities whose bubbles are gone (popped / expired)
        let goneIDs = bubbleStore.entities.keys.filter { !activeIDs.contains($0) }
        for id in goneIDs {
            bubbleStore.entities[id]?.removeFromParent()
            bubbleStore.entities.removeValue(forKey: id)
        }

        // Add or update active bubbles using stored references — bypasses the
        // RealityView content API limitation where root.children only reflects
        // entities from the make closure, not those added in prior update calls.
        for bubble in bubbles where !bubble.isGone {
            let isTargeted = bubble.id == targetedID

            if let entity = bubbleStore.entities[bubble.id] {
                entity.position = bubble.position
                entity.model?.materials = [makeBubbleMaterial(color: bubble.type.uiColor, isTargeted: isTargeted)]
                entity.scale = isTargeted ? SIMD3<Float>(repeating: 1.3) : SIMD3<Float>(repeating: 1.0)
            } else {
                let entity = makeBubbleEntity(for: bubble, isTargeted: isTargeted)
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
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: (highlighted ? UIColor.systemGreen : UIColor.systemPurple).withAlphaComponent(0.95))
        material.emissiveColor = .init(color: highlighted ? .white : .systemPink)

        let entity = ModelEntity(
            mesh: .generateSphere(radius: highlighted ? 0.055 : 0.045),
            materials: [material]
        )
        entity.name = name
        entity.position = position
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.06)]))
        entity.components.set(InputTargetComponent())

        return entity
    }

    private func updateStartOrbAppearance(_ entity: ModelEntity, highlighted: Bool, visible: Bool) {
        entity.scale = visible
            ? (highlighted ? SIMD3<Float>(repeating: 1.18) : SIMD3<Float>(repeating: 1.0))
            : SIMD3<Float>(repeating: 0.001)

        if var material = entity.model?.materials.first as? PhysicallyBasedMaterial {
            material.baseColor = .init(tint: (highlighted ? UIColor.systemGreen : UIColor.systemPurple).withAlphaComponent(0.95))
            material.emissiveColor = .init(color: highlighted ? .white : .systemPink)
            entity.model?.materials = [material]
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
