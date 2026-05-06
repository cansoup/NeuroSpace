//
//  EEGCommandMessage.swift
//  NeuroSpace
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//

import Foundation

struct EEGCommandMessage: Codable {
    let intent: BCIIntent
    let confidence: Double?
    let timestamp: TimeInterval?
}
