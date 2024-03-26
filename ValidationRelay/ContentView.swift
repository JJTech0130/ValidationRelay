//
//  ContentView.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import SwiftUI

struct ContentView: View {
    //@State private var registrationCode = "Not Connected"
    //@State private var connectionStatusMessage = ""
    
    @State private var wantRelayConnected = false // TODO: Come up with a method to auto connect
    
    @AppStorage("selectedRelay") private var selectedRelay = "Beeper"
    @AppStorage("customRelayURL") private var customRelayURL = ""
    
    //private var relayConnectionManager: RelayConnectionManager? = nil
    @ObservedObject var relayConnectionManager: RelayConnectionManager
    
//    init() {
//        relayConnectionManager = RelayConnectionManager(registrationCodeBinding: $registrationCode, connectionStatusMessageBinding: $connectionStatusMessage)
//    }
    
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
                }
            } footer: {
                Text(relayConnectionManager.connectionStatusMessage)
            }
            Section {
                // TODO: Actually support running in the background
                Toggle("Run in Background", isOn: .constant(false))
                    .disabled(true)
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
                Button("Reset Registration Code") {
                    // Do reset stuff
                }
                    //.foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .disabled(true)
            } footer: {
                Text("You will need to re-enter the code on your other devices")
            }
        }
        .listStyle(.grouped)
    }

}

#Preview {
    ContentView(relayConnectionManager: RelayConnectionManager())
}
