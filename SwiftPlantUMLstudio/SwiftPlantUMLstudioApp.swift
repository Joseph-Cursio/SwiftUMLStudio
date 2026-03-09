//
//  SwiftPlantUMLstudioApp.swift
//  SwiftPlantUMLstudio
//
//  Created by joe cursio on 2/26/26.
//

import SwiftUI

@main
struct SwiftPlantUMLstudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1500, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
