//
//  SessionState.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//This will tell the app what phase the user is in i.e. whether the user is in the painting phase or doign something else

import Foundation

enum SessionState: String, Codable {
    case idle
    case calibrating
    case ready
    case playing
    case paused
    case finished
}
