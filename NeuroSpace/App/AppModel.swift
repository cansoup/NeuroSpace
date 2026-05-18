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
    var debugMode: Bool = false
    var selectedEnvironment: EnvironmentChoice = .deepSpace
    /// When false the cursor dot and hold marker are hidden during gameplay.
    /// BCI targeting and HoverEffectComponent highlighting still work normally.
    var showCursor: Bool = true
    var hasCompletedOnboarding: Bool = false
    /// True while the lobby skybox immersive space is open as an environment
    /// preview from Settings → Immersive. Used by ImmersivePanel to gate
    /// open/dismiss so the preview doesn't fight with normal game flow.
    var isPreviewingEnvironment: Bool = false

    /// Accessibility: when true, SwiftUI buttons that opt-in via `.dwellable`
    /// auto-fire after the user's gaze hovers on them for `dwellDuration`
    /// seconds. Designed for users who cannot use hand gestures.
    var dwellModeEnabled: Bool = false
    var dwellDuration: Double = 1.5

    /// True once the user has completed the left/right/both calibration
    /// sequence at least once. Persisted across launches so returning users
    /// skip straight to gameplay. Reset from Settings → Recalibrate.
    var hasCalibrated: Bool = UserDefaults.standard.bool(forKey: "hasCalibrated") {
        didSet { UserDefaults.standard.set(hasCalibrated, forKey: "hasCalibrated") }
    }

    /// WebSocket bridge address. Persisted so the user can edit it from
    /// Settings and the value survives relaunch.
    var bciHost: String = (
        UserDefaults.standard.string(forKey: "bciHost")
        ?? (Bundle.main.object(forInfoDictionaryKey: "BCI_DEFAULT_HOST") as? String)
        ?? "192.168.1.10"
    ) {
        didSet { UserDefaults.standard.set(bciHost, forKey: "bciHost") }
    }

    var bciPort: Int = {
        let saved = UserDefaults.standard.integer(forKey: "bciPort")
        if saved > 0 { return saved }
        if let s = Bundle.main.object(forInfoDictionaryKey: "BCI_DEFAULT_PORT") as? String,
           let p = Int(s) { return p }
        return 8765
    }() {
        didSet { UserDefaults.standard.set(bciPort, forKey: "bciPort") }
    }

    /// True while the in-world stage-end bubble menu is visible inside the immersive space.
    var showStageEndBubbles: Bool = false

    /// Drives which result card is shown as a head-tracked attachment.
    enum StageEndResult { case none, passed, failed }
    var stageEndResult: StageEndResult = .none

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
