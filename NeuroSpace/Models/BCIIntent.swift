//
//  BCIIntent.swift
//  NeuroSpace
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//This will translate the intended EEG signals coming into the app for the action that users want to take

import Foundation

enum BCIIntent: String, Codable, CaseIterable {
    case idle
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case moveForward
    case moveBackward
    case pop
}
