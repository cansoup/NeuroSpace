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
    let congratsWindowID = "congrats"
    let missionFailedWindowID = "missionFailed"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var gameController: BubbleGameController
    var shouldEndSession: Bool = false

    let armMapper: BCIArmMapper
    let fakeBCIInput: FakeBCIInputService

    init() {
        let controller = BubbleGameController()
        self.gameController = controller
        self.armMapper = BCIArmMapper(controller: controller)
        self.fakeBCIInput = FakeBCIInputService(mapper: self.armMapper)
    }
}
