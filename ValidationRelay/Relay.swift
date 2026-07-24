//
//  Relay.swift
//  ValidationRelay
//
//  Created by James Gill on 3/25/24.
//

import Foundation
import Network
import NWWebSocket
import SwiftUI

func getIdentifiers() -> [String: String] {
    var ustruct: utsname = utsname()
    uname(&ustruct)
    var ustruct2 = ustruct
    let machine = withUnsafePointer(to: &ustruct2.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: ustruct.machine)) {
            String(cString: $0)
        }
    }
    
    
    let identifiers = [
        "hardware_version": machine,
        "software_name": "iPhone OS",
        "software_version": UIDevice.current.systemVersion,
        "software_build_id": buildNumber()!,
        "unique_device_id": MGCopyAnswer("UniqueDeviceID" as CFString)!.takeRetainedValue() as! String,
        "serial_number": MGCopyAnswer("SerialNumber" as CFString)!.takeRetainedValue() as! String
        
    ]
    return identifiers
}

class RelayConnectionManager: ObservableObject {
    @Published var registrationCode: String = "None"
    @Published var connectionStatusMessage: String = ""
    @Published var logItems = LogItems()
    
    // These must all be saved together
    @AppStorage("savedRegistrationSecret") public var savedRegistrationSecret = ""
    @AppStorage("savedRegistrationCode") public var savedRegistrationCode = ""
    @AppStorage("savedRegistrationURL") public var savedRegistrationURL = ""
    
    var currentURL: URL? = nil
    var connectionDelegate: RelayConnectionDelegate? = nil
    
    var reconnectWork: DispatchWorkItem? = nil
    var watchdogTimer: DispatchSourceTimer? = nil
    var lastPongAt: Date? = nil
    var shouldReconnect = false
    
    var backoff: Int = 2
    let maxBackoff: Int = 64
    let watchdogInterval: TimeInterval = 30
    let staleConnectionInterval: TimeInterval = 90

    func connect(_ url: URL) {
        logItems.log("Connecting to \(url)")
        connectionStatusMessage = "Connecting..."
        currentURL = url
        shouldReconnect = true
        
        backoff = 2 // Reset backoff
        
        reconnectWork?.cancel()
        reconnectWork = nil
        stopWatchdog()

        let oldDelegate = connectionDelegate
        connectionDelegate = nil
        oldDelegate?.disconnect()
        connectionDelegate = RelayConnectionDelegate(manager: self)
    }

    func disconnect() {
        logItems.log("Disconnecting on request")
        connectionStatusMessage = ""
        shouldReconnect = false
        currentURL = nil
        
        reconnectWork?.cancel()
        reconnectWork = nil
        stopWatchdog()
        
        let oldDelegate = connectionDelegate
        connectionDelegate = nil
        oldDelegate?.disconnect()
    }

    func didConnect(_ delegate: RelayConnectionDelegate) {
        guard connectionDelegate === delegate else {
            return
        }

        logItems.log("Websocket did connect")
        connectionStatusMessage = "Connected"
        lastPongAt = Date()
        startWatchdog()
    }

    func didReceivePong(_ delegate: RelayConnectionDelegate) {
        guard connectionDelegate === delegate else {
            return
        }

        lastPongAt = Date()
        backoff = 2
    }

    func didDisconnect(_ delegate: RelayConnectionDelegate) {
        guard connectionDelegate === delegate else {
            return
        }

        logItems.log("Websocket did disconnect", isError: true)
        triggerReconnect()
    }

    func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + watchdogInterval, repeating: watchdogInterval)
        timer.setEventHandler { [weak self] in
            guard let self,
                  self.shouldReconnect,
                  let lastPongAt = self.lastPongAt,
                  Date().timeIntervalSince(lastPongAt) > self.staleConnectionInterval else {
                return
            }

            self.logItems.log("Websocket heartbeat timed out", isError: true)
            self.triggerReconnect()
        }
        watchdogTimer = timer
        timer.resume()
    }

    func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
        lastPongAt = nil
    }

    func triggerReconnect(_ delegate: RelayConnectionDelegate? = nil) {
        if let delegate, connectionDelegate !== delegate {
            return
        }
        guard shouldReconnect, currentURL != nil else {
            return
        }
        guard reconnectWork == nil else {
            return
        }

        logItems.log("Triggering reconnect")
        connectionStatusMessage = "Reconnecting..."
        stopWatchdog()

        // Clear the active delegate before disconnecting it so its delayed
        // callbacks cannot schedule a second reconnect.
        let oldDelegate = connectionDelegate
        connectionDelegate = nil
        oldDelegate?.disconnect()
        print("Waiting for \(backoff) backoff seconds")
        
        let work = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.reconnectWork = nil
            guard self.shouldReconnect, self.currentURL != nil else {
                return
            }
            self.connectionDelegate = RelayConnectionDelegate(manager: self)
        }
        // Wait a bit then try again
        DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(backoff), execute: work)
        
        reconnectWork = work
        backoff = min(backoff * 2, maxBackoff)
    }
}

class RelayConnectionDelegate: WebSocketConnectionDelegate, ObservableObject {
    var connection: WebSocketConnection
    let manager: RelayConnectionManager

    init(
        manager: RelayConnectionManager
    ) {
        self.manager = manager
        connection = NWWebSocket(url: manager.currentURL!, connectAutomatically: true)
        connection.delegate = self
        connection.ping(interval: 30)
    }
    
    func disconnect() {
        connection.disconnect(closeCode: .protocolCode(.normalClosure))
    }
    
    func webSocketDidConnect(connection: WebSocketConnection) {
        manager.didConnect(self)
        var registerCommand = ["command": "register", "data": ["": ""]] as [String : Any]
        if manager.currentURL?.absoluteString == manager.savedRegistrationURL {
            manager.logItems.log("Using saved registration credentials")
            registerCommand["data"] = ["code": manager.savedRegistrationCode, "secret": manager.savedRegistrationSecret]
        }
        let data = try! JSONSerialization.data(withJSONObject: registerCommand)
        connection.send(string: String(data: data, encoding: .utf8)!)
    }
    
    func webSocketDidDisconnect(connection: WebSocketConnection, closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        manager.didDisconnect(self)
    }
    
    func webSocketViabilityDidChange(connection: WebSocketConnection, isViable: Bool) {
        if !isViable {
            manager.logItems.log("Websocket connection is no longer viable", isError: true)
            manager.triggerReconnect(self)
        }
    }
    
    func webSocketDidAttemptBetterPathMigration(result: Result<WebSocketConnection, NWError>) {
        // Respond to when a WebSocket connection migrates to a better network path
        // (e.g. A device moves from a cellular connection to a Wi-Fi connection)
        print("WebSocket connection attempted better path migration, ignoring")
    }
    
    func webSocketDidReceiveError(connection: WebSocketConnection, error: NWError) {
        print(error)
        manager.logItems.log("Websocket error: \(error)", isError: true)
        self.manager.triggerReconnect(self)
    }
    
    func webSocketDidReceivePong(connection: WebSocketConnection) {
        manager.didReceivePong(self)
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, string: String) {
        guard let encodedMessage = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: encodedMessage, options: []) else {
            manager.logItems.log("Received an invalid relay message", isError: true)
            return
        }
        manager.didReceivePong(self)
        
        // Save registration code
        if let jsonDict = json as? [String: Any] {
            if let data = jsonDict["data"] as? [String: Any] {
                if let code = data["code"] as? String {
                    manager.registrationCode = code
                    if manager.savedRegistrationCode != code {
                        manager.logItems.log("Received new registration credentials")
                    }
                    manager.savedRegistrationCode = code
                    manager.savedRegistrationSecret = data["secret"] as? String ?? ""
                    manager.savedRegistrationURL = manager.currentURL?.absoluteString ?? ""
                }
            }
            if let command = jsonDict["command"] as? String {
                if command == "get-version-info" {
                    let versionInfo = ["command": "response", "data": ["versions": getIdentifiers()], "id": jsonDict["id"]!] as [String : Any]
                    manager.logItems.log("Sending device version information")
                    let data = try! JSONSerialization.data(withJSONObject: versionInfo)
                    connection.send(string: String(data: data, encoding: .utf8)!)
                }
                if command == "get-validation-data" {
                    let v = generateValidationData()
                    manager.logItems.log("Generated validation data")
                    let validationData = ["command": "response", "data": ["data": v.base64EncodedString()], "id": jsonDict["id"]!] as [String : Any]
                    let data = try! JSONSerialization.data(withJSONObject: validationData)
                    connection.send(string: String(data: data, encoding: .utf8)!)
                }
            }
        }
        // Respond to a WebSocket connection receiving a `String` message
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, data: Data) {
        manager.logItems.log("Received an unexpected binary relay message", isError: true)
    }
}

