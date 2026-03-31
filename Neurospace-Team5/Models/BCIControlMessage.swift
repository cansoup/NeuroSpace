//
//  BCIControlMessage.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 31/3/2026.
//

import Foundation

struct BCIControlMessage: Codable {
    let activeArm: ActiveArm
    let moveX: Float
    let moveY: Float
    let moveZ: Float
    let confidence: Float
    let timestamp: Double
}
