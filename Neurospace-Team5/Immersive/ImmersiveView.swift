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

import SwiftUI
import RealityKit
import simd

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RealityView { content, attachments in
            let headAnchor = AnchorEntity(.head)
            headAnchor.name = "HeadAnchor"

            let root = Entity()
            root.name = "Root"
            root.position = SIMD3<Float>(0, 0, -1.2)

            // Left arm
            let leftArm = makeArmBodyEntity(
                name: "LeftArmBody",
                color: appModel.gameController.activeArm == .left ? .cyan : .gray
            )
            let leftTip = makeTipEntity(
                name: "LeftArmTip",
                color: appModel.gameController.activeArm == .left ? .red : .gray
            )

            // Right arm
            let rightArm = makeArmBodyEntity(
                name: "RightArmBody",
                color: appModel.gameController.activeArm == .right ? .cyan : .gray
            )
            let rightTip = makeTipEntity(
                name: "RightArmTip",
                color: appModel.gameController.activeArm == .right ? .red : .gray
            )

            root.addChild(leftArm)
            root.addChild(leftTip)
            root.addChild(rightArm)
            root.addChild(rightTip)

            for bubble in appModel.gameController.bubbles where !bubble.isPopped {
                root.addChild(makeBubbleEntity(for: bubble))
            }

            headAnchor.addChild(root)

            if let panel = attachments.entity(for: "controlPanel") {
                panel.name = "ControlPanel"
                panel.position = SIMD3<Float>(0.45, 0.15, -1.2)
                headAnchor.addChild(panel)
            }

            content.add(headAnchor)

        } update: { content, _ in
            guard
                let headAnchor = content.entities.first(where: { $0.name == "HeadAnchor" }),
                let root = headAnchor.findEntity(named: "Root"),
                let leftArmBody = root.findEntity(named: "LeftArmBody") as? ModelEntity,
                let leftTip = root.findEntity(named: "LeftArmTip") as? ModelEntity,
                let rightArmBody = root.findEntity(named: "RightArmBody") as? ModelEntity,
                let rightTip = root.findEntity(named: "RightArmTip") as? ModelEntity
            else { return }

            let controller = appModel.gameController
            controller.update(deltaTime: 1.0 / 60.0)

            updateArm(
                body: leftArmBody,
                tip: leftTip,
                state: controller.leftArmState,
                isActive: controller.activeArm == .left
            )

            updateArm(
                body: rightArmBody,
                tip: rightTip,
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
        material.baseColor = .init(tint: color.withAlphaComponent(0.8))
        material.roughness = .init(floatLiteral: 0.35)

        let entity = ModelEntity(
            mesh: .generateCylinder(height: 1.0, radius: 0.018),
            materials: [material]
        )
        entity.name = name
        return entity
    }

    private func makeTipEntity(name: String, color: UIColor) -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.withAlphaComponent(0.95))
        material.roughness = .init(floatLiteral: 0.15)

        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.028),
            materials: [material]
        )
        entity.name = name
        return entity
    }

    private func updateArm(body: ModelEntity, tip: ModelEntity, state: ArmState, isActive: Bool) {
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

        if var bodyMaterial = body.model?.materials.first as? PhysicallyBasedMaterial {
            bodyMaterial.baseColor = .init(tint: (isActive ? UIColor.cyan : UIColor.gray).withAlphaComponent(0.8))
            body.model?.materials = [bodyMaterial]
        }

        if var tipMaterial = tip.model?.materials.first as? PhysicallyBasedMaterial {
            tipMaterial.baseColor = .init(tint: (isActive ? UIColor.red : UIColor.gray).withAlphaComponent(0.95))
            tip.model?.materials = [tipMaterial]
        }
    }

    private func makeBubbleEntity(for bubble: Bubble) -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor.systemPurple.withAlphaComponent(0.55))
        material.roughness = .init(floatLiteral: 0.1)

        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.06),
            materials: [material]
        )
        entity.name = "Bubble_\(bubble.id.uuidString)"
        entity.position = bubble.position
        return entity
    }

    private func syncBubbles(in root: Entity, with bubbles: [Bubble]) {
        for bubble in bubbles {
            let name = "Bubble_\(bubble.id.uuidString)"

            if bubble.isPopped {
                root.findEntity(named: name)?.removeFromParent()
            } else if root.findEntity(named: name) == nil {
                root.addChild(makeBubbleEntity(for: bubble))
            }
        }
    }
}
