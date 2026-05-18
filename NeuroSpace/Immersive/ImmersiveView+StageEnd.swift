import SwiftUI
import RealityKit
import UIKit

extension ImmersiveView {

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

    @MainActor
    func handleStageEndChoice(_ choice: StageEndChoice) {
        // Reset immediately so the handler fires once per dwell completion.
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
