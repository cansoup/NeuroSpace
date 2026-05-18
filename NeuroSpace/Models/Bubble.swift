//
//  Bubble.swift
//  NeuroSpace
//

//
//  Bubble.swift
//  NeuroSpace
//

import Foundation
import simd
import UIKit

enum BubbleType: String, CaseIterable, Codable {
    case red
    case blue

    var points: Int {
        switch self {
        case .red:   return 10
        case .blue:  return 20
        }
    }

    var displayName: String {
        switch self {
        case .red:   return "Red"
        case .blue:  return "Blue"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .red:   return UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0)
        case .blue:  return UIColor(red: 0.36, green: 0.61, blue: 1.0, alpha: 1.0)
        }
    }

    static func randomWeighted() -> BubbleType {
        Bool.random() ? .red : .blue
    }
}

struct Bubble: Identifiable, Equatable {
    let id: UUID
    var position: SIMD3<Float>
    var isPopped: Bool

    // Gameplay identity
    var type: BubbleType

    // Stage-aware fields
    var velocity: SIMD3<Float>     // non-zero in dynamic stages (5)
    var spawnTime: Date            // used for lifetime tracking
    var lifetime: Double?          // nil = lives until explicitly popped

    init(
        id: UUID = UUID(),
        position: SIMD3<Float>,
        isPopped: Bool = false,
        type: BubbleType = .red,
        velocity: SIMD3<Float> = .zero,
        spawnTime: Date = Date(),
        lifetime: Double? = nil
    ) {
        self.id = id
        self.position = position
        self.isPopped = isPopped
        self.type = type
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
        lhs.velocity == rhs.velocity
    }
}
