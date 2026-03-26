//
//  ImmersiveView.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//
import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.name = "Root"

            // Place bubble field at eye level, 1.2m in front in world space
            let anchor = AnchorEntity(world: SIMD3<Float>(0, 1.5, -1.2))

            let armMesh = MeshResource.generateCylinder(height: 0.24, radius: 0.025)
            var armMaterial = PhysicallyBasedMaterial()
            armMaterial.baseColor = .init(tint: .white.withAlphaComponent(0.6))
            armMaterial.roughness = .init(floatLiteral: 0.4)
            let arm = ModelEntity(mesh: armMesh, materials: [armMaterial])
            arm.name = "Arm"
            arm.position = appModel.gameController.armState.armBasePosition

            let tipMesh = MeshResource.generateSphere(radius: 0.025)
            var tipMaterial = PhysicallyBasedMaterial()
            tipMaterial.baseColor = .init(tint: .cyan.withAlphaComponent(0.9))
            tipMaterial.roughness = .init(floatLiteral: 0.2)
            let tip = ModelEntity(mesh: tipMesh, materials: [tipMaterial])
            tip.name = "PointerTip"
            tip.position = appModel.gameController.armState.pointerPosition

            root.addChild(arm)
            root.addChild(tip)

            for bubble in appModel.gameController.bubbles where !bubble.isPopped {
                let bubbleEntity = makeBubbleEntity(for: bubble)
                root.addChild(bubbleEntity)
            }

            anchor.addChild(root)
            content.add(anchor)

            // Attach control panel — top-right of the bubble field
            if let panel = attachments.entity(for: "controlPanel") {
                panel.position = SIMD3<Float>(0.55, 0.45, -1.0)
                content.add(panel)
            }

        } update: { content, attachments in

            let deltaTime: Float = 1.0 / 60.0
            appModel.gameController.update(deltaTime: deltaTime)

            guard
                let anchor = content.entities.first,
                let root = anchor.findEntity(named: "Root"),
                let arm = root.findEntity(named: "Arm"),
                let tip = root.findEntity(named: "PointerTip")
            else {
                return
            }

            let controller = appModel.gameController

            arm.position = controller.armState.armBasePosition
            tip.position = controller.armState.pointerPosition

            syncBubbles(in: root, with: controller.bubbles)

        } attachments: {
            Attachment(id: "controlPanel") {
                GameControlPanel()
                    .environment(appModel)
            }
        }
    }

    private func makeBubbleEntity(for bubble: Bubble) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.06)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .purple.withAlphaComponent(0.55))
        material.roughness = .init(floatLiteral: 0.1)
        material.metallic = .init(floatLiteral: 0.0)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = bubbleEntityName(for: bubble.id)
        entity.position = bubble.position
        return entity
    }

    private func bubbleEntityName(for id: UUID) -> String {
        "Bubble_\(id.uuidString)"
    }

    private func syncBubbles(in root: Entity, with bubbles: [Bubble]) {
        for bubble in bubbles {
            let name = bubbleEntityName(for: bubble.id)

            if bubble.isPopped {
                root.findEntity(named: name)?.removeFromParent()
            } else if root.findEntity(named: name) == nil {
                let entity = makeBubbleEntity(for: bubble)
                root.addChild(entity)
            }
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
