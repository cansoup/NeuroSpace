//
//  BCIControlMessage.swift
//  NeuroSpace
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

struct BCIPredictionMessage: Codable {
    let type: String
    let timestamp: Double
    let sessionId: String
    let predictedClass: PredictedClass
    let predictedIndex: Int
    let confidence: Double
    let probabilities: BCIProbabilities
    let processingTimeMs: Double
    let aboveThreshold: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case sessionId = "session_id"
        case predictedClass = "predicted_class"
        case predictedIndex = "predicted_index"
        case confidence
        case probabilities
        case processingTimeMs = "processing_time_ms"
        case aboveThreshold = "above_threshold"
    }
}

struct BCIProbabilities: Codable {
    let left: Double
    let right: Double
    let both: Double
}

enum PredictedClass: String, Codable {
    case left
    case right
    case both
}
