//
//  ContentView.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import SwiftUI
import Foundation

private func spawn(path: String, args: [String]) -> Bool {
    var pid: pid_t = 0
    var argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }
    argv.append(nil)
    defer { argv.forEach { free($0) } }
    
    let status = posix_spawn(&pid, path, nil, nil, argv, nil)
    if status == 0 {
        waitpid(pid, nil, 0)
        return true
    }
    return false
}

struct ContentView: View {
    @AppStorage("autoConnect") private var wantRelayConnected = true
    @AppStorage("keepAwake") private var keepAwake = true
    
    @AppStorage("selectedRelay") private var selectedRelay = "Beeper"
    @AppStorage("customRelayURL") private var customRelayURL = ""
    
    @ObservedObject var relayConnectionManager: RelayConnectionManager
    
    @State private var killTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    
    init(relayConnectionManager: RelayConnectionManager) {
        self.relayConnectionManager = relayConnectionManager
        if wantRelayConnected {
            startKillingçç()
            relayConnectionManager.connect(getCurrentRelayURL())
        }
        if keepAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
    
    func getCurrentRelayURL() -> URL {
        if selectedRelay == "Custom" {
            if let url = URL(string: customRelayURL) {
                return url
            }
        } else if selectedRelay == "pypush" {
            return URL(string: "wss://registration-relay.jjtech.dev/api/v1/provider")!
        }
        
        // Default to Beeper relay
        selectedRelay = "Beeper"
        return URL(string: "wss://registration-relay.beeper.com/api/v1/provider")!
    }
    
    func startKillingIdentityservicesd() {
        killTask?.cancel()
        
        killTask = Task {
            while true {
                if Task.isCancelled { break }
                
                let success = spawn(path: "/usr/bin/killall", args: ["identityservicesd"])
                relayConnectionManager.logItems.log(
                    success ? "Killed identityservicesd" : "Failed to kill identityservicesd",
                    isError: !success
                )
                
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
            }
            relayConnectionManager.logItems.log("Stopped killing identityservicesd")
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Relay", isOn: $wantRelayConnected)
                        .onChange(of: wantRelayConnected) { newValue in
                            // Connect or disconnect the relay
                            if newValue {
                                startKillingIdentityservicesd()
                                relayConnectionManager.connect(getCurrentRelayURL())
                            } else {
                                killTask?.cancel()
                                relayConnectionManager.disconnect()
                            }
                        }
                    HStack {
                        Text("Registration Code")
                        Spacer()
                        Text(relayConnectionManager.registrationCode)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } footer: {
                    Text(relayConnectionManager.connectionStatusMessage)
                }
                Section {
                    //Toggle("Run in Background", isOn: .constant(false))
                    //    .disabled(true)
                    Picker("Relay", selection: $selectedRelay) {
                        Text("Beeper").tag("Beeper")
                        //Text("pypush").tag("pypush")
                        Text("Custom").tag("Custom")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedRelay) { newValue in
                        // Disconnect when the user is switching relay servers
                        wantRelayConnected = false
                    }
                    if (selectedRelay == "Custom") {
                        TextField("Custom Relay Server URL", text: $customRelayURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                    }
                } header: {
                    Text("Connection settings")
                } footer: {
                    Text("Beeper's relay server is recommended for most users")
                }
                
                Section {
                    // Navigation to Log page
                    NavigationLink(destination: LogView(logItems: relayConnectionManager.logItems)) {
                        Text("Log")
                    }
                    Button("Dim Display") {
                        UIScreen.main.brightness = 0.0
                        UIScreen.main.wantsSoftwareDimming = true
                    }
                    Toggle("Keep Awake", isOn: $keepAwake)
                        .onChange(of: keepAwake) { newValue in
                            if keepAwake {
                                UIApplication.shared.isIdleTimerDisabled = true
                            } else {
                                UIApplication.shared.isIdleTimerDisabled = false
                            }
                        }
                    Button("Reset Registration Code") {
                        relayConnectionManager.savedRegistrationURL = ""
                        relayConnectionManager.savedRegistrationCode = ""
                        relayConnectionManager.savedRegistrationSecret = ""
                        relayConnectionManager.registrationCode = "None"
                        wantRelayConnected = false
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("You will need to re-enter the code on your other devices")
                }
            }
            .listStyle(.grouped)
            .navigationBarHidden(true)
            .navigationBarTitle("", displayMode: .inline)
        }
        .onDisappear {
            killTask?.cancel()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                if !wantRelayConnected {
                    killTask?.cancel()
                }
            case .active:
                if wantRelayConnected {
                    startKillingIdentityservicesd()
                }
            default:
                break
            }
        }
    }

}

#Preview {
    ContentView(relayConnectionManager: RelayConnectionManager())
}
