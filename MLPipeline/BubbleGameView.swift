// BubbleGameView.swift
// VisionStudio – Team 5
//
// Example RealityView that connects the EEG prediction bridge to avatar arm
// animations and bubble-popping logic.
//
// To use in your project:
//   1. Add EEGPredictionBridge.swift to your target
//   2. Start the Python pipeline:
//        python eeg_classifier.py --mode offline --xdf bci-mi-n-100.xdf --train
//        python lsl_to_tcp_bridge.py
//   3. Run this view — arms animate on EEG prediction, bubbles pop on contact

import SwiftUI
import RealityKit

struct BubbleGameView: View {

    // ── EEG bridge (shared across the app) ───────────────────────────────────
    @State private var bridge     = EEGPredictionBridge()
    @State private var armCtrl    = ArmMovementController()

    // ── Game state ────────────────────────────────────────────────────────────
    @State private var score: Int = 0
    @State private var bubbles: [BubbleEntity] = []

    // ── RealityKit entity handles ─────────────────────────────────────────────
    @State private var leftArmAnchor:  AnchorEntity?
    @State private var rightArmAnchor: AnchorEntity?

    var body: some View {
        ZStack(alignment: .top) {
            RealityView { content in
                setupScene(content: content)
            } update: { content in
                // Called every SwiftUI render pass — sync state to RealityKit
                checkBubbleCollisions()
            }
            .task { startEEG() }

            // ── HUD ───────────────────────────────────────────────────────────
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    PredictionBadge(prediction: bridge.latestPrediction)
                    Spacer()
                    Text("Score: \(score)")
                        .font(.title2.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                }
                .padding()
            }
        }
        .onDisappear { bridge.stop() }
    }

    // MARK: - Scene setup

    private func setupScene(content: RealityViewContent) {
        // ── Ground plane ──────────────────────────────────────────────────────
        let ground = AnchorEntity(world: .zero)
        content.add(ground)

        // ── Left arm ─────────────────────────────────────────────────────────
        let leftArm  = makeArm(color: .blue)
        let leftAnchor = AnchorEntity(world: [-0.4, -0.2, -0.8])
        leftAnchor.addChild(leftArm)
        content.add(leftAnchor)
        leftArmAnchor = leftAnchor
        armCtrl.leftArmEntity = leftArm

        // ── Right arm ─────────────────────────────────────────────────────────
        let rightArm = makeArm(color: .orange)
        let rightAnchor = AnchorEntity(world: [0.4, -0.2, -0.8])
        rightAnchor.addChild(rightArm)
        content.add(rightAnchor)
        rightArmAnchor = rightAnchor
        armCtrl.rightArmEntity = rightArm

        // ── Spawn initial bubbles ─────────────────────────────────────────────
        for _ in 0..<8 { spawnBubble(in: content) }
    }

    private func makeArm(color: UIColor) -> Entity {
        // Simple capsule representing the forearm
        let mesh      = MeshResource.generateCapsule(height: 0.35, radius: 0.05)
        let material  = SimpleMaterial(color: color.withAlphaComponent(0.85), isMetallic: false)
        let entity    = ModelEntity(mesh: mesh, materials: [material])
        // Pivot at shoulder – offset so rotation looks natural
        entity.position = [0, 0.18, 0]
        return entity
    }

    // MARK: - EEG connection

    private func startEEG() {
        // Uncomment for production (live TCP server):
        // bridge.host = "127.0.0.1"
        // bridge.port = 12345

        bridge.demoMode = false   // set true when running without the Python pipeline
        bridge.start()
        armCtrl.observe(bridge)
    }

    // MARK: - Bubble management

    private func spawnBubble(in content: RealityViewContent) {
        let x = Float.random(in: -0.8...0.8)
        let y = Float.random(in:  0.1...0.9)
        let z = Float.random(in: -1.2...(-0.5))
        let r = Float.random(in:  0.06...0.12)

        let mesh     = MeshResource.generateSphere(radius: r)
        var mat      = UnlitMaterial()
        mat.color    = .init(tint: bubbleColor().withAlphaComponent(0.6))
        let entity   = ModelEntity(mesh: mesh, materials: [mat])
        entity.position = [x, y, z]

        // Add collision so we can detect arm contact
        entity.collision = CollisionComponent(
            shapes: [.generateSphere(radius: r)],
            mode: .trigger,
            filter: .default
        )

        let anchor = AnchorEntity(world: entity.position)
        anchor.addChild(entity)
        content.add(anchor)
        bubbles.append(BubbleEntity(entity: entity, anchor: anchor, radius: r))
    }

    private func bubbleColor() -> UIColor {
        [UIColor.systemPink, .systemTeal, .systemPurple, .systemYellow].randomElement()!
    }

    private func checkBubbleCollisions() {
        // Check if the active arm entity is close to any bubble
        let activeArm: Entity? = switch bridge.latestPrediction.movement {
        case .left:  armCtrl.leftArmEntity
        case .right: armCtrl.rightArmEntity
        case .idle:  nil
        }
        guard let arm = activeArm else { return }

        let armPos = arm.position(relativeTo: nil)
        bubbles.removeAll { bubble in
            let dist = distance(armPos, bubble.entity.position(relativeTo: nil))
            if dist < bubble.radius + 0.12 {
                popBubble(bubble)
                return true
            }
            return false
        }
    }

    private func popBubble(_ bubble: BubbleEntity) {
        // Scale-out pop animation
        bubble.entity.move(
            to: Transform(scale: .init(repeating: 2.5), translation: bubble.entity.position),
            relativeTo: bubble.entity.parent,
            duration: 0.15,
            timingFunction: .easeOut
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            bubble.anchor.removeFromParent()
        }
        score += 10
    }

    // MARK: - Helpers

    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(a - b)
    }
}

// MARK: - Supporting types

private struct BubbleEntity {
    let entity: Entity
    let anchor: AnchorEntity
    let radius: Float
}

// MARK: - Prediction badge HUD element

private struct PredictionBadge: View {
    let prediction: EEGPrediction

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(prediction.movement.label)
                .font(.subheadline.bold())
            Text(String(format: "%.0f%%", prediction.confidence * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: prediction.movement)
    }

    private var color: Color {
        switch prediction.movement {
        case .idle:  return .gray
        case .left:  return .blue
        case .right: return .orange
        }
    }
}

// MARK: - App entry point (keep in your existing App file)

/*
@main
struct VisionStudioApp: App {
    var body: some Scene {
        WindowGroup {
            BubbleGameView()
        }
        .windowStyle(.volumetric)
    }
}
*/
