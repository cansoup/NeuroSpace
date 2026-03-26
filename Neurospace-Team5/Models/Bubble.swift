//
//  Bubble.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 26/3/2026.
//

import Foundation
import simd

struct Bubble: Identifiable, Equatable {
    let id: UUID
    var position: SIMD3<Float>
    var isPopped: Bool
    
    init(id: UUID = UUID(), position: SIMD3<Float>, isPopped: Bool = false) {
        self.id = id
        self.position = position
        self.isPopped = isPopped
    }
}
