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
    /// When false the cursor dot and hold marker are hidden during gameplay.
    /// BCI targeting and HoverEffectComponent highlighting still work normally.
    var showCursor: Bool = true
    var hasCompletedOnboarding: Bool = false
    /// True while the lobby skybox immersive space is open as an environment
    /// preview from Settings → Immersive. Used by ImmersivePanel to gate
    /// open/dismiss so the preview doesn't fight with normal game flow.
    var isPreviewingEnvironment: Bool = false

    var gameController = BubbleGameController()
    var bciClient = BCIWebSocketClient()
    var jsonPlayback: JSONPlaybackManager!
    var sessionStore = SessionStore()

    init() {
        jsonPlayback = JSONPlaybackManager(controller: gameController)
        // Wire predictions arriving over WebSocket into arm movement.
        bciClient.armMapper = BCIArmMapper(controller: gameController)
    }

    var isEEGConnected: Bool {
        if case .connected = bciClient.state { return true }
        return false
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
