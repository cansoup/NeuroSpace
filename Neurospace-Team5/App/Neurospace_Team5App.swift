//
//  Neurospace_Team5App.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//

import SwiftUI

@main
struct Neurospace_Team5App: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: appModel.mainWindowID) {
            ContentView()
                .environment(appModel)
        }

        WindowGroup(id: appModel.congratsWindowID) {
            CongratsView()
                .environment(appModel)
        }
        .defaultSize(width: 400, height: 300)

        WindowGroup(id: appModel.missionFailedWindowID) {
            MissionFailedView()
                .environment(appModel)
        }
        .defaultSize(width: 400, height: 320)

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
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
