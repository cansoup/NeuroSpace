//
//  NeuroSpaceApp.swift
//  NeuroSpace
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//

import SwiftUI

@main
struct NeuroSpaceApp: App {

    @State private var appModel = AppModel()

    /// `.mixed` (real-world passthrough) for None/Passthrough envs,
    /// `.full` otherwise. Reading `selectedEnvironment` makes the App body
    /// re-render when the user changes env, swapping the immersion style.
    private var immersionStyle: any ImmersionStyle {
        switch appModel.selectedEnvironment {
        case .none, .passthrough: return .mixed
        default:                  return .full
        }
    }

    var body: some Scene {
        WindowGroup(id: appModel.mainWindowID) {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.plain)

        WindowGroup(id: appModel.congratsWindowID) {
            CongratsView()
                .environment(appModel)
        }
        .defaultSize(width: 460, height: 560)
        .windowResizability(.contentSize)

        WindowGroup(id: appModel.missionFailedWindowID) {
            MissionFailedView()
                .environment(appModel)
        }
        .defaultSize(width: 460, height: 560)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: appModel.lobbySkyboxID) {
            LobbySkyboxView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(immersionStyle), in: .full, .mixed)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(immersionStyle), in: .full, .mixed)
    }
}
