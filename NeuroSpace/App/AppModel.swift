//
//  AppModel.swift
//  NeuroSpace
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
    var debugMode: Bool = true
    var selectedEnvironment: EnvironmentChoice = .deepSpace

    var gameController = BubbleGameController()
    var jsonPlayback: JSONPlaybackManager!
    var sessionStore = SessionStore()

    init() {
        jsonPlayback = JSONPlaybackManager(controller: gameController)
    }

    func saveSessionRecord() {
        let controller = gameController
        let totalStages = StageConfig.totalStages
        let elapsed = controller.stageConfig.duration - controller.remainingSeconds
        let record = SessionRecord(
            stageReached: controller.currentStage,
            totalStages: totalStages,
            score: controller.score,
            durationSeconds: elapsed
        )
        sessionStore.save(record)
    }
}
