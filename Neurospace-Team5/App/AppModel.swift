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

    let mainWindowID = "MainWindow"
    let congratsWindowID = "CongratsWindow"
    let missionFailedWindowID = "MissionFailedWindow"

    let immersiveSpaceID = "ImmersiveSpace"
    let lobbySkyboxID = "LobbySkybox"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var shouldEndSession = false

    var gameController = BubbleGameController()
    var jsonPlayback: JSONPlaybackManager!

    init() {
        jsonPlayback = JSONPlaybackManager(controller: gameController)
    }
}
