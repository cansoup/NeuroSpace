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
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RealityView { content, attachments in

            // Game objects — world-fixed, 1.2m in front at eye level (y=0 in visionOS)
            let sceneAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, -1.2))
            sceneAnchor.name = "SceneAnchor"

            let root = Entity()
            root.name = "Root"

            var armMaterial = PhysicallyBasedMaterial()
            armMaterial.baseColor = .init(tint: .white.withAlphaComponent(0.6))
            armMaterial.roughness = .init(floatLiteral: 0.4)
            let arm = ModelEntity(
                mesh: .generateCylinder(height: 0.24, radius: 0.025),
                materials: [armMaterial]
            )
            arm.name = "Arm"
            arm.position = appModel.gameController.armState.armBasePosition

            var tipMaterial = PhysicallyBasedMaterial()
            tipMaterial.baseColor = .init(tint: .cyan.withAlphaComponent(0.9))
            tipMaterial.roughness = .init(floatLiteral: 0.2)
            let tip = ModelEntity(
                mesh: .generateSphere(radius: 0.025),
                materials: [tipMaterial]
            )
            tip.name = "PointerTip"
            tip.position = appModel.gameController.armState.pointerPosition

            root.addChild(arm)
            root.addChild(tip)
            for bubble in appModel.gameController.bubbles where !bubble.isPopped {
                root.addChild(makeBubbleEntity(for: bubble))
            }
            sceneAnchor.addChild(root)
            content.add(sceneAnchor)

            // Control panel — world-fixed, top-right of bubble field
            if let panel = attachments.entity(for: "controlPanel") {
                panel.name = "ControlPanel"
                let panelAnchor = AnchorEntity(world: SIMD3<Float>(0.5, 0.2, -1.2))
                panelAnchor.addChild(panel)
                content.add(panelAnchor)
            }

            // Stop alert — world-fixed, centered, hidden by default
            if let alert = attachments.entity(for: "stopAlert") {
                alert.name = "StopAlert"
                alert.isEnabled = false
                let alertAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, -1.0))
                alertAnchor.name = "StopAlertAnchor"
                alertAnchor.addChild(alert)
                content.add(alertAnchor)
            }

        } update: { content, _ in

            guard
                let sceneAnchor = content.entities.first(where: { $0.name == "SceneAnchor" }),
                let root = sceneAnchor.findEntity(named: "Root"),
                let arm = root.findEntity(named: "Arm"),
                let tip = root.findEntity(named: "PointerTip")
            else { return }

            let controller = appModel.gameController
            controller.update(deltaTime: 1.0 / 60.0)

            arm.position = controller.armState.armBasePosition
            tip.position = controller.armState.pointerPosition
            syncBubbles(in: root, with: controller.bubbles)

            // Toggle stop alert
            if let alertAnchor = content.entities.first(where: { $0.name == "StopAlertAnchor" }),
               let alert = alertAnchor.findEntity(named: "StopAlert") {
                alert.isEnabled = appModel.showStopAlert
            }

        } attachments: {
            Attachment(id: "controlPanel") {
                GameControlPanel()
                    .environment(appModel)
            }
            Attachment(id: "stopAlert") {
                StopAlertPanel()
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

    private func makeBubbleEntity(for bubble: Bubble) -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .purple.withAlphaComponent(0.55))
        material.roughness = .init(floatLiteral: 0.1)
        let entity = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [material])
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

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
