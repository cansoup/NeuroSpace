import SwiftUI
import RealityKit

struct LobbySkyboxView: View {
    var body: some View {
        RealityView { content in
            let starField = Entity()
            starField.name = "StarField"

            let starCount = 400
            let radius: Float = 30.0

            for _ in 0..<starCount {
                let theta = Float.random(in: 0...(2 * .pi))
                let phi = acos(Float.random(in: -1...1))
                let r = radius * Float.random(in: 0.85...1.0)

                let x = r * sin(phi) * cos(theta)
                let y = r * sin(phi) * sin(theta)
                let z = r * cos(phi)

                let size = Float.random(in: 0.01...0.04)

                var material = UnlitMaterial()
                let brightness = Float.random(in: 0.5...1.0)
                let tint: UIColor
                let roll = Int.random(in: 0...100)
                if roll < 5 {
                    tint = UIColor(red: 0.7, green: 0.85, blue: 1.0, alpha: CGFloat(brightness))
                } else if roll < 8 {
                    tint = UIColor(red: 1.0, green: 0.9, blue: 0.7, alpha: CGFloat(brightness))
                } else {
                    tint = UIColor(white: CGFloat(brightness), alpha: 1.0)
                }
                material.color = .init(tint: tint)

                let star = ModelEntity(
                    mesh: .generateSphere(radius: size),
                    materials: [material]
                )
                star.position = SIMD3<Float>(x, y, z)
                starField.addChild(star)
            }

            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(starField)
            content.add(anchor)
        }
    }
}
