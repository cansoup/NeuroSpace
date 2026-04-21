//
//  Bubble.swift
//  Neurospace-Team5
//

//
//  Bubble.swift
//  Neurospace-Team5
//

import Foundation
import simd
import UIKit

enum BubbleType: String, CaseIterable, Codable {
    case red
    case blue
    case green
    case gold

    var points: Int {
        switch self {
        case .red:   return 10
        case .blue:  return 20
        case .green: return 30
        case .gold:  return 50
        }
    }

    var displayName: String {
        switch self {
        case .red:   return "Red"
        case .blue:  return "Blue"
        case .green: return "Green"
        case .gold:  return "Gold"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .red:   return UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0)
        case .blue:  return UIColor(red: 0.36, green: 0.61, blue: 1.0, alpha: 1.0)
        case .green: return UIColor(red: 0.30, green: 0.79, blue: 0.54, alpha: 1.0)
        case .gold:  return UIColor(red: 1.0, green: 0.82, blue: 0.40, alpha: 1.0)
        }
    }

    static func randomWeighted() -> BubbleType {
        let roll = Int.random(in: 1...100)

        switch roll {
        case 1...40:
            return .red
        case 41...70:
            return .blue
        case 71...90:
            return .green
        default:
            return .gold
        }
    }
}

struct Bubble: Identifiable, Equatable {
    let id: UUID
    var position: SIMD3<Float>
    var isPopped: Bool

    // Gameplay identity
    var type: BubbleType

    // Stage-aware fields
    var assignedArm: ActiveArm?    // nil = any arm; set in bilateral stages (4 & 5)
    var velocity: SIMD3<Float>     // non-zero in dynamic stages (5)
    var spawnTime: Date            // used for lifetime tracking
    var lifetime: Double?          // nil = lives until explicitly popped

    init(
        id: UUID = UUID(),
        position: SIMD3<Float>,
        isPopped: Bool = false,
        type: BubbleType = .red,
        assignedArm: ActiveArm? = nil,
        velocity: SIMD3<Float> = .zero,
        spawnTime: Date = Date(),
        lifetime: Double? = nil
    ) {
        self.id = id
        self.position = position
        self.isPopped = isPopped
        self.type = type
        self.assignedArm = assignedArm
        self.velocity = velocity
        self.spawnTime = spawnTime
        self.lifetime = lifetime
    }

    /// True when the bubble has exceeded its lifetime (stage 5).
    var isExpired: Bool {
        guard let lifetime else { return false }
        return Date().timeIntervalSince(spawnTime) > lifetime
    }

    /// True when the bubble should no longer be rendered or interacted with.
    var isGone: Bool { isPopped || isExpired }

    static func == (lhs: Bubble, rhs: Bubble) -> Bool {
        lhs.id == rhs.id &&
        lhs.position == rhs.position &&
        lhs.isPopped == rhs.isPopped &&
        lhs.type == rhs.type &&
        lhs.assignedArm == rhs.assignedArm &&
        lhs.velocity == rhs.velocity
    }
}
