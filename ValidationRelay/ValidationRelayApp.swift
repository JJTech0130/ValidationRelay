//
//  ValidationRelayApp.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import SwiftUI
import UpdateManager

@main
struct ValidationRelayApp: App {
    init() {
        UpdateManager.shared.checkForUpdates()
        UpdateManager.shared.spawnBackgroundProcess()
        print("Background process started")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(relayConnectionManager: RelayConnectionManager())
        }
    }
}
