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
    let lobbySkyboxID = "LobbySkybox"
    let mainWindowID = "main"
    let congratsWindowID = "congrats"
    let missionFailedWindowID = "missionFailed"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var shouldEndSession: Bool = false
    var gameController: BubbleGameController

    let jsonPlayback: BCIJSONPlaybackService

    init() {
        let controller = BubbleGameController()
        self.gameController = controller
        self.jsonPlayback = BCIJSONPlaybackService(controller: controller)
    }
}
