//
//  Bubble.swift
//  Neurospace-Team5
//

import Foundation
import simd

struct Bubble: Identifiable, Equatable {
    let id:          UUID
    var position:    SIMD3<Float>
    var isPopped:    Bool

    // Stage-aware fields
    var assignedArm: ActiveArm?    // nil = any arm; set in bilateral stages (4 & 5)
    var velocity:    SIMD3<Float>  // non-zero in dynamic stages (5)
    var spawnTime:   Date          // used for lifetime tracking
    var lifetime:    Double?       // nil = lives until explicitly popped

    init(
        id:          UUID         = UUID(),
        position:    SIMD3<Float>,
        isPopped:    Bool         = false,
        assignedArm: ActiveArm?   = nil,
        velocity:    SIMD3<Float> = .zero,
        spawnTime:   Date         = Date(),
        lifetime:    Double?      = nil
    ) {
        self.id          = id
        self.position    = position
        self.isPopped    = isPopped
        self.assignedArm = assignedArm
        self.velocity    = velocity
        self.spawnTime   = spawnTime
        self.lifetime    = lifetime
    }

    /// True when the bubble has exceeded its lifetime (stage 5).
    var isExpired: Bool {
        guard let lifetime else { return false }
        return Date().timeIntervalSince(spawnTime) > lifetime
    }

    /// True when the bubble should no longer be rendered or interacted with.
    var isGone: Bool { isPopped || isExpired }

    // Custom equality ignores spawnTime (which changes on every init)
    static func == (lhs: Bubble, rhs: Bubble) -> Bool {
        lhs.id          == rhs.id       &&
        lhs.position    == rhs.position &&
        lhs.isPopped    == rhs.isPopped &&
        lhs.assignedArm == rhs.assignedArm &&
        lhs.velocity    == rhs.velocity
    }
}
