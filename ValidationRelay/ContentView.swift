//
//  ContentView.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoConnect") private var wantRelayConnected = true
    @AppStorage("keepAwake") private var keepAwake = true
    
    @AppStorage("selectedRelay") private var selectedRelay = "Beeper"
    @AppStorage("customRelayURL") private var customRelayURL = ""
    
    @ObservedObject var relayConnectionManager: RelayConnectionManager

    func getCurrentRelayURL() -> URL? {
        if selectedRelay == "Custom" {
            guard let components = URLComponents(string: customRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  components.scheme?.lowercased() == "wss",
                  components.host?.isEmpty == false,
                  components.user == nil,
                  components.password == nil,
                  components.percentEncodedQuery == nil,
                  components.fragment == nil else {
                return nil
            }
            return components.url
        } else if selectedRelay == "pypush" {
            return URL(string: "wss://registration-relay.jjtech.dev/api/v1/provider")!
        }
        
        // Default to Beeper relay
        return URL(string: "wss://registration-relay.beeper.com/api/v1/provider")!
    }

    func connectCurrentRelay() {
        guard let url = getCurrentRelayURL() else {
            relayConnectionManager.connectionStatusMessage = "Custom relay must be a secure wss:// URL without embedded credentials or a query."
            return
        }
        relayConnectionManager.connectIfNeeded(url)
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Relay", isOn: $wantRelayConnected)
                        .onChange(of: wantRelayConnected) { newValue in
                            // Connect or disconnect the relay
                            if newValue {
                                connectCurrentRelay()
                            } else {
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
                            UIApplication.shared.isIdleTimerDisabled = newValue
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
                    Text("You will need to re-enter the code on your other devices. Keep ValidationRelay open in the foreground and keep this iPhone awake.")
                }
            }
            .listStyle(.grouped)
            .navigationBarHidden(true)
            .navigationBarTitle("", displayMode: .inline)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = keepAwake
                if wantRelayConnected {
                    connectCurrentRelay()
                }
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active,
                      wantRelayConnected,
                      let url = getCurrentRelayURL() else {
                    return
                }
                UIApplication.shared.isIdleTimerDisabled = keepAwake
                relayConnectionManager.refreshOnForeground(url)
            }
        }
        
    }

}

#Preview {
    ContentView(relayConnectionManager: RelayConnectionManager())
}
