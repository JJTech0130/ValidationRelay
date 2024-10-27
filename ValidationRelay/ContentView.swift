//
//  ContentView.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("autoConnect") private var wantRelayConnected = false
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("selectedRelay") private var selectedRelay = "Beeper"
    @AppStorage("customRelayURL") private var customRelayURL = ""

    @StateObject private var relayConnectionManager = RelayConnectionManager()
    @State private var customURLError: String?
    @State private var isConnecting: Bool = false
    @State private var connectionError: String?
    @State private var isDimmingDisplay: Bool = false  // Separate loading state for dimming

    init() {
        // Initialization is handled by @StateObject
    }

    private func getCurrentRelayURL() -> URL? {
        if selectedRelay == "Custom" {
            guard !customRelayURL.isEmpty, let url = URL(string: customRelayURL) else {
                customURLError = "Invalid URL"
                return nil
            }
            customURLError = nil
            return url
        } else if selectedRelay == "pypush" {
            return URL(string: "wss://registration-relay.jjtech.dev/api/v1/provider")
        }
        // Default to Beeper relay
        return URL(string: "wss://registration-relay.beeper.com/api/v1/provider")
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Relay", isOn: $wantRelayConnected)
                        .disabled(isConnecting)
                        .onChange(of: wantRelayConnected) { newValue in
                            handleConnectionChange(newValue)
                        }

                    HStack {
                        Text("Registration Code")
                        Spacer()
                        Text(relayConnectionManager.registrationCode)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(relayConnectionManager.connectionStatusMessage)
                        if let error = connectionError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Picker("Relay", selection: $selectedRelay) {
                        Text("Beeper").tag("Beeper")
                        Text("Custom").tag("Custom")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedRelay) { _ in
                        handleRelayChange()
                    }

                    if selectedRelay == "Custom" {
                        TextField("Custom Relay Server URL", text: $customRelayURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .onChange(of: customRelayURL) { _ in validateCustomURL() }
                        
                        if let error = customURLError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Connection settings")
                } footer: {
                    Text("Beeper's relay server is recommended for most users")
                }

                Section {
                    NavigationLink(destination: LogView(logItems: relayConnectionManager.logItems)) {
                        Text("Log")
                    }

                    Button(action: dimDisplay) {
                        if isDimmingDisplay {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Dim Display")
                        }
                    }

                    Toggle("Keep Awake", isOn: $keepAwake)
                        .onChange(of: keepAwake) { newValue in
                            UIApplication.shared.isIdleTimerDisabled = newValue
                        }

                    Button("Reset Registration Code") {
                        resetRegistration()
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
        .onAppear(perform: setupView)
    }

    private func handleConnectionChange(_ newValue: Bool) {
        isConnecting = true
        connectionError = nil
        if newValue, let url = getCurrentRelayURL() {
            relayConnectionManager.connect(url)
            relayConnectionManager.connectionStatusMessage = "Attempting to connect..."
        } else {
            relayConnectionManager.disconnect()
        }
        isConnecting = false
    }

    private func handleRelayChange() {
        relayConnectionManager.disconnect()
        wantRelayConnected = false
    }

    private func validateCustomURL() {
        if URL(string: customRelayURL) == nil {
            customURLError = "Invalid URL"
        } else {
            customURLError = nil
        }
    }

    private func resetRegistration() {
        relayConnectionManager.savedRegistrationURL = ""
        relayConnectionManager.savedRegistrationCode = ""
        relayConnectionManager.savedRegistrationSecret = ""
        relayConnectionManager.registrationCode = "None"
        wantRelayConnected = false
    }

    private func setupView() {
        if wantRelayConnected, let url = getCurrentRelayURL() {
            relayConnectionManager.connect(url)
        }
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }
    
    private func dimDisplay() {
        isDimmingDisplay = true
        UIScreen.main.brightness = 0.0
        UIScreen.main.wantsSoftwareDimming = true
        isDimmingDisplay = false
    }
}

#Preview {
    ContentView()
}
