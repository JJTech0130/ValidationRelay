//
//  ContentView.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("autoConnect") private var wantRelayConnected = false
    
    @AppStorage("selectedRelay") private var selectedRelay = "Beeper"
    @AppStorage("customRelayURL") private var customRelayURL = ""
    
    @ObservedObject var relayConnectionManager: RelayConnectionManager
    
    init(relayConnectionManager: RelayConnectionManager) {
        self.relayConnectionManager = relayConnectionManager
        if wantRelayConnected {
            relayConnectionManager.connect(getCurrentRelayURL())
        }
        ApplicationMonitor.shared.start()
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
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Relay", isOn: $wantRelayConnected)
                        .onChange(of: wantRelayConnected) { newValue in
                            // Connect or disconnect the relay
                            if newValue {
                                relayConnectionManager.connect(getCurrentRelayURL())
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
        
    }

}

#Preview {
    ContentView(relayConnectionManager: RelayConnectionManager())
}
