//
//  AppModel.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    let mainWindowID = "main"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var gameController = BubbleGameController()
    var showStopAlert: Bool = false
}
