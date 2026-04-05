//
//  BCIControlMessage.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 5/4/2026.
//


import Foundation


struct BCIControlMessage: Codable {
    let timestamp: Double
    let activeArm: ActiveArm
    let moveX: Float
    let moveY: Float
    let moveZ: Float
    let confidence: Float
}
