import SwiftUI
import RealityKit
import RealityKitContent

struct LobbySkyboxView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        // The make closure creates a single named anchor and runs the initial
        // build. The update closure finds that anchor by name and kicks off a
        // Task to rebuild its children. We capture the Entity reference (a
        // class) inside the Task — never the `inout content` — which avoids
        // the "Escaping closure captures 'inout' parameter" error and ensures
        // env switches actually re-render the skybox.
        RealityView { content in
            let anchor = AnchorEntity(world: .zero)
            anchor.name = "SkyboxAnchor"
            content.add(anchor)
            await rebuild(anchor: anchor, for: appModel.selectedEnvironment)
        } update: { content in
            guard let anchor = content.entities.first(where: { $0.name == "SkyboxAnchor" })
            else { return }

            let env = appModel.selectedEnvironment
            Task { @MainActor in
                await rebuild(anchor: anchor, for: env)
            }
        }
    }

    @MainActor
    private func rebuild(anchor: Entity, for env: EnvironmentChoice) async {
        // Tear down previous skybox children
        for child in anchor.children {
            child.removeFromParent()
        }

        switch env {
        case .deepSpace:
            anchor.addChild(makeStarField())

        case .aurora:
            anchor.addChild(makeAuroraSky())

        case .forest, .clearNight, .garden:
            if let sphere = await makeHDRSkybox(named: env.hdrAssetName ?? "") {
                anchor.addChild(sphere)
            } else {
                // Fallback when the HDR asset isn't bundled yet — show a
                // gradient sphere using the swatch colors so the picker still
                // visibly switches.
                anchor.addChild(makeFallbackSky(for: env))
            }

        case .passthrough:
            // Render no skybox content. Note: true passthrough requires
            // .mixed immersion style, set on the ImmersiveSpace in the App.
            break
        }
    }

    // MARK: - Procedural: Deep Space starfield

    private func makeStarField() -> Entity {
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

        return starField
    }

    // MARK: - Procedural: Aurora gradient + soft glow

    private func makeAuroraSky() -> Entity {
        let root = Entity()
        root.name = "AuroraSky"

        // Inverted sphere with a vertical gradient tint
        let mesh = MeshResource.generateSphere(radius: 50)
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.06, green: 0.04, blue: 0.18, alpha: 1.0))
        let sky = ModelEntity(mesh: mesh, materials: [material])
        sky.scale = SIMD3<Float>(-1, 1, 1)
        root.addChild(sky)

        // A few translucent emerald/violet ribbons rendered as oriented planes
        let ribbonColors: [UIColor] = [
            UIColor(red: 0.15, green: 0.85, blue: 0.55, alpha: 0.35),
            UIColor(red: 0.45, green: 0.40, blue: 0.95, alpha: 0.30),
            UIColor(red: 0.20, green: 0.95, blue: 0.85, alpha: 0.25)
        ]

        for (i, color) in ribbonColors.enumerated() {
            var ribbonMaterial = UnlitMaterial()
            ribbonMaterial.color = .init(tint: color)
            ribbonMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.7))

            let ribbon = ModelEntity(
                mesh: .generatePlane(width: 30, height: 6),
                materials: [ribbonMaterial]
            )
            ribbon.position = SIMD3<Float>(0, Float(2 + i), -8 - Float(i) * 2)
            ribbon.transform.rotation = simd_quatf(angle: Float(i) * 0.2, axis: [0, 1, 0])
            root.addChild(ribbon)
        }

        return root
    }

    // MARK: - HDR / 360° image skybox

    private func makeHDRSkybox(named name: String) async -> Entity? {
        guard !name.isEmpty else { return nil }

        let texture = await loadTexture(named: name)
        guard let texture else {
            print("[Skybox] Texture '\(name)' not found in any bundle.")
            return nil
        }

        let mesh = MeshResource.generateSphere(radius: 50)
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        let model = ModelEntity(mesh: mesh, materials: [material])
        // Flip so the texture is visible from inside the sphere.
        model.scale = SIMD3<Float>(-1, 1, 1)
        model.name = "HDRSkybox_\(name)"
        return model
    }

    /// Tries the Reality Composer Pro package bundle first (where rkassets
    /// live), then the main app bundle as a fallback.
    private func loadTexture(named name: String) async -> TextureResource? {
        // 1) RealityKitContent package bundle
        do {
            let texture = try await TextureResource(named: name, in: realityKitContentBundle)
            print("[Skybox] Loaded '\(name)' from realityKitContentBundle")
            return texture
        } catch {
            print("[Skybox] realityKitContentBundle miss for '\(name)': \(error.localizedDescription)")
        }

        // 2) Main app bundle
        do {
            let texture = try await TextureResource(named: name)
            print("[Skybox] Loaded '\(name)' from main bundle")
            return texture
        } catch {
            print("[Skybox] main bundle miss for '\(name)': \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Fallback: solid gradient sphere

    private func makeFallbackSky(for env: EnvironmentChoice) -> Entity {
        let (c1, _) = env.swatchHex
        let mesh = MeshResource.generateSphere(radius: 50)
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(
            red: CGFloat((c1 >> 16) & 0xFF) / 255,
            green: CGFloat((c1 >> 8) & 0xFF) / 255,
            blue: CGFloat(c1 & 0xFF) / 255,
            alpha: 1.0
        ))
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.scale = SIMD3<Float>(-1, 1, 1)
        model.name = "FallbackSky"
        return model
    }
}
