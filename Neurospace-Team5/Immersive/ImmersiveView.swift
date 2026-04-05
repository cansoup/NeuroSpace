//
//  ImmersiveView.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//
//
//  ImmersiveView.swift
//  Neurospace-Team5
//

//
//  ImmersiveView.swift
//  Neurospace-Team5
//

import SwiftUI
import RealityKit
import simd

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RealityView { content, attachments in
            // World anchor: fixed in real-world space at eye level, 1.2 m in front of origin
            let worldAnchor = AnchorEntity(world: SIMD3<Float>(0, 1.5, -1.2))
            worldAnchor.name = "WorldAnchor"

            let root = Entity()
            root.name = "Root"
            root.position = .zero

            let leftArm = makeArmBodyEntity(
                name: "LeftArmBody",
                color: appModel.gameController.activeArm == .left ? .cyan : .gray
            )
            let leftTip = makeTipEntity(
                name: "LeftArmTip",
                color: appModel.gameController.activeArm == .left ? .systemPink : .gray,
                radius: appModel.gameController.activeArm == .left ? 0.032 : 0.026
            )

            let rightArm = makeArmBodyEntity(
                name: "RightArmBody",
                color: appModel.gameController.activeArm == .right ? .cyan : .gray
            )
            let rightTip = makeTipEntity(
                name: "RightArmTip",
                color: appModel.gameController.activeArm == .right ? .systemPink : .gray,
                radius: appModel.gameController.activeArm == .right ? 0.032 : 0.026
            )

            let leftGlow = makeHighlightRing(name: "LeftArmGlow")
            let rightGlow = makeHighlightRing(name: "RightArmGlow")

            root.addChild(leftArm)
            root.addChild(leftTip)
            root.addChild(rightArm)
            root.addChild(rightTip)
            root.addChild(leftGlow)
            root.addChild(rightGlow)

            for bubble in appModel.gameController.bubbles where !bubble.isGone {
                root.addChild(makeBubbleEntity(for: bubble))
            }

            worldAnchor.addChild(root)

            if let panel = attachments.entity(for: "controlPanel") {
                panel.name = "ControlPanel"
                panel.position = SIMD3<Float>(0.55, 0.25, 0)
                worldAnchor.addChild(panel)
            }

            content.add(worldAnchor)

        } update: { content, _ in
            guard
                let worldAnchor = content.entities.first(where: { $0.name == "WorldAnchor" }),
                let root = worldAnchor.findEntity(named: "Root"),
                let leftArmBody = root.findEntity(named: "LeftArmBody") as? ModelEntity,
                let leftTip = root.findEntity(named: "LeftArmTip") as? ModelEntity,
                let rightArmBody = root.findEntity(named: "RightArmBody") as? ModelEntity,
                let rightTip = root.findEntity(named: "RightArmTip") as? ModelEntity,
                let leftGlow = root.findEntity(named: "LeftArmGlow") as? ModelEntity,
                let rightGlow = root.findEntity(named: "RightArmGlow") as? ModelEntity
            else { return }

            // Physics is driven by the .task below — this closure only syncs entities to model state.
            let controller = appModel.gameController

            updateArm(
                body: leftArmBody,
                tip: leftTip,
                glow: leftGlow,
                state: controller.leftArmState,
                isActive: controller.activeArm == .left
            )

            updateArm(
                body: rightArmBody,
                tip: rightTip,
                glow: rightGlow,
                state: controller.rightArmState,
                isActive: controller.activeArm == .right
            )

            syncBubbles(in: root, with: controller.bubbles)

        } attachments: {
            Attachment(id: "controlPanel") {
                GameControlPanel()
                    .environment(appModel)
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    let name = value.entity.name
                    guard name.hasPrefix("Bubble_") else { return }
                    let uuidString = String(name.dropFirst("Bubble_".count))
                    guard let id = UUID(uuidString: uuidString) else { return }
                    appModel.gameController.popBubble(withID: id)
                }
        )
        .onChange(of: appModel.gameController.sessionState) { _, newState in
            guard newState == .finished else { return }
            switch appModel.gameController.finishReason {
            case .allPopped: openWindow(id: appModel.congratsWindowID)
            default:         openWindow(id: appModel.missionFailedWindowID)
            }
        }
        .task { @MainActor in
            // Physics loop runs independently of the render loop.
            // Decoupled from the update closure to prevent a feedback cycle where
            // controller.update() triggers @Observable → update closure → controller.update() again.
            while !Task.isCancelled {
                appModel.gameController.update(deltaTime: 1.0 / 60.0)
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

                if appModel.immersiveSpaceState == .open {
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                }

                openWindow(id: appModel.mainWindowID)
            }
        }
    }

    private func makeArmBodyEntity(name: String, color: UIColor) -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.withAlphaComponent(0.85))
        material.roughness = .init(floatLiteral: 0.28)

        let entity = ModelEntity(
            mesh: .generateCylinder(height: 1.0, radius: 0.018),
            materials: [material]
        )
        entity.name = name
        return entity
    }

    private func makeTipEntity(name: String, color: UIColor, radius: Float) -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.withAlphaComponent(0.98))
        material.roughness = .init(floatLiteral: 0.12)

        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material]
        )
        entity.name = name
        return entity
    }

    private func makeHighlightRing(name: String) -> ModelEntity {
        let material = UnlitMaterial(color: .systemPink.withAlphaComponent(0.55))
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.040),
            materials: [material]
        )
        entity.name = name
        entity.isEnabled = false
        return entity
    }

    private func updateArm(
        body: ModelEntity,
        tip: ModelEntity,
        glow: ModelEntity,
        state: ArmState,
        isActive: Bool
    ) {
        tip.position = state.tipPosition

        let direction = state.tipPosition - state.basePosition
        let length = max(simd_length(direction), 0.001)
        let midpoint = (state.basePosition + state.tipPosition) / 2

        let normalizedDirection = simd_normalize(direction)
        let up = SIMD3<Float>(0, 1, 0)
        let rotation = simd_quatf(from: up, to: normalizedDirection)

        body.transform = Transform(
            scale: [1.0, length, 1.0],
            rotation: rotation,
            translation: midpoint
        )

        glow.position = state.tipPosition
        glow.isEnabled = isActive
        glow.scale = isActive ? [1.0, 1.0, 1.0] : [0.001, 0.001, 0.001]

        if var bodyMaterial = body.model?.materials.first as? PhysicallyBasedMaterial {
            bodyMaterial.baseColor = .init(tint: (isActive ? UIColor.cyan : UIColor.gray).withAlphaComponent(0.85))
            body.model?.materials = [bodyMaterial]
        }

        if var tipMaterial = tip.model?.materials.first as? PhysicallyBasedMaterial {
            tipMaterial.baseColor = .init(tint: (isActive ? UIColor.systemPink : UIColor.gray).withAlphaComponent(0.98))
            tip.model?.materials = [tipMaterial]
        }
    }

    private func makeBubbleEntity(for bubble: Bubble) -> ModelEntity {
        // Colour indicates arm assignment: cyan = left, orange = right, purple = unassigned
        let tint: UIColor
        switch bubble.assignedArm {
        case .left:  tint = UIColor.systemCyan.withAlphaComponent(0.65)
        case .right: tint = UIColor.systemOrange.withAlphaComponent(0.65)
        case nil:    tint = UIColor.systemPurple.withAlphaComponent(0.55)
        }

        let radius = appModel.gameController.stageConfig.bubbleRadius

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.roughness = .init(floatLiteral: 0.1)

        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material]
        )
        entity.name = "Bubble_\(bubble.id.uuidString)"
        entity.position = bubble.position
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
        entity.components.set(InputTargetComponent())
        return entity
    }

    private func syncBubbles(in root: Entity, with bubbles: [Bubble]) {
        let validNames = Set(bubbles.filter { !$0.isGone }.map { "Bubble_\($0.id.uuidString)" })

        // Snapshot before removing to avoid mutating root.children during iteration
        let toRemove = root.children.filter {
            $0.name.hasPrefix("Bubble_") && !validNames.contains($0.name)
        }
        toRemove.forEach { $0.removeFromParent() }

        // Add new entities or update positions of existing ones (for moving bubbles)
        for bubble in bubbles where !bubble.isGone {
            let name = "Bubble_\(bubble.id.uuidString)"
            if let existing = root.findEntity(named: name) {
                existing.position = bubble.position
            } else {
                root.addChild(makeBubbleEntity(for: bubble))
            }
        }
    }
}
