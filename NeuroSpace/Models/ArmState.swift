//
//  ArmState.swift
//  NeuroSpace
//
//  Created by Shaiyan Haseen Khan on 26/3/2026.
//


//
//  ArmState.swift
//  NeuroSpace
//

import Foundation
import simd

enum ActiveArm: String, Codable, CaseIterable {
    case left
    case right
}

struct ArmState: Equatable {
    var basePosition: SIMD3<Float>
    var tipPosition: SIMD3<Float>
    var velocity: SIMD3<Float>
    var isPopTriggered: Bool = false

    init(
        basePosition: SIMD3<Float> = .zero,
        tipPosition: SIMD3<Float> = .zero,
        velocity: SIMD3<Float> = .zero,
        isPopTriggered: Bool = false
    ) {
        self.basePosition = basePosition
        self.tipPosition = tipPosition
        self.velocity = velocity
        self.isPopTriggered = isPopTriggered
    }
}
