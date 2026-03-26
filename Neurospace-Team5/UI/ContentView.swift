//
//  ContentView.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 16/3/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let controller = appModel.gameController

        VStack(alignment: .leading, spacing: 16) {
            Text("Neurospace Bubble Pop")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("BCI-controlled pointer prototype")
                .font(.headline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Connection: \(controller.connectionState.displayText)")
                Text("Session: \(controller.sessionState.rawValue.capitalized)")
                Text("Intent: \(controller.currentIntent.rawValue)")
                Text("Score: \(controller.score)")
            }
            .font(.title3)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Debug Controls")
                    .font(.headline)

                HStack {
                    Button("Reset") {
                        controller.resetGame()
                    }
                }

                HStack {
                    Button("Left") { controller.applyIntent(.moveLeft) }
                    Button("Right") { controller.applyIntent(.moveRight) }
                    Button("Idle") { controller.applyIntent(.idle) }
                }
            }

            Divider()

            ToggleImmersiveSpaceButton()
        }
        .padding(24)
        .frame(minWidth: 520)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
