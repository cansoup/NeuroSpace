import Foundation

/// Immersive environment options selectable from Settings → Immersive.
enum EnvironmentChoice: String, CaseIterable, Identifiable, Codable {
    case deepSpace
    case forest
    case clearNight
    case aurora
    case garden
    case passthrough

    var id: String { rawValue }

    /// Display label shown in the picker.
    var label: String {
        switch self {
        case .deepSpace:   return "Deep Space"
        case .forest:      return "Forest"
        case .clearNight:  return "Clear Night"
        case .aurora:      return "Aurora"
        case .garden:      return "Garden"
        case .passthrough: return "Passthrough"
        }
    }

    /// Decorative icon for the picker swatch.
    var icon: String {
        switch self {
        case .deepSpace:   return "✦"
        case .forest:      return "⬡"
        case .clearNight:  return "◎"
        case .aurora:      return "◈"
        case .garden:      return "◇"
        case .passthrough: return "⊹"
        }
    }

    /// Two-stop gradient hex pair shown in the picker swatch.
    var swatchHex: (UInt, UInt) {
        switch self {
        case .deepSpace:   return (0x060a12, 0x0d1a2e)
        case .forest:      return (0x0a1a0a, 0x0d2010)
        case .clearNight:  return (0x060e1a, 0x0a1428)
        case .aurora:      return (0x0a0820, 0x1a0a2e)
        case .garden:      return (0x1a0e06, 0x2a1a08)
        case .passthrough: return (0x1a1a1a, 0x2a2a2a)
        }
    }

    /// Asset name (HDR / image) bundled in the project. `nil` for procedural
    /// or non-skybox environments (Deep Space, Aurora, Passthrough).
    var hdrAssetName: String? {
        switch self {
        case .forest:      return "rainforest_trail_4k"
        case .clearNight:  return "rogland_clear_night_4k"
        case .garden:      return "suburban_garden_4k"
        case .deepSpace, .aurora, .passthrough:
            return nil
        }
    }
}
