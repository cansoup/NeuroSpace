//
//  ArmState.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 26/3/2026.
//


import Foundation
import simd

struct ArmState: Equatable {
    var pointerPosition: SIMD3<Float> = [0.0, 0.0, 0.0]
    var armBasePosition: SIMD3<Float> = [0.0, -0.08, 0.0]
    var isPopTriggered: Bool = false
}
