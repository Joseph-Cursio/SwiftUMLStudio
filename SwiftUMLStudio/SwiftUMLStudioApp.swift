//
//  SwiftUMLStudioApp.swift
//  SwiftUMLStudio
//
//  Created by joe cursio on 2/26/26.
//

import AppKit
import SwiftUI

// Prevents the macOS reopen Apple Event (kAEReopenApplication) from triggering
// window creation while the XCTest runner owns the process. Without this gate,
// macOS calls applicationOpenUntitledFile → AppWindowsController.showInitialWindows()
// which forces SwiftUI to re-evaluate the WindowGroup body via a LazyView, crashing
// at SerialExecutor.isMainExecutor.getter (null protocol witness) on macOS 26+.
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    // Primary gate: returning false short-circuits _handleAEReopen entirely,
    // preventing showInitialWindows() → LazyView re-evaluation.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !isRunningTests
    }

    // Belt-and-suspenders: also suppress the open-untitled-file query.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !isRunningTests
    }
}

@main
struct SwiftUMLStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            // Don't create the live view hierarchy when running tests — tests
            // provide their own isolated DiagramViewModels and must not share
            // the app's ObservationCenter / attribute-graph registrations.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                EmptyView()
            } else {
                ContentView()
                    .environment(subscriptionManager)
            }
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
