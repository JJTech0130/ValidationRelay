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
    
    guard let build = buildNumber() else {
        print("Failed to retrieve build number")
        return [:]
    }
    
    guard let uniqueDeviceID = MGCopyAnswer("UniqueDeviceID" as CFString)?.takeRetainedValue() as? String else {
        print("Failed to retrieve UniqueDeviceID")
        return [:]
    }
    
    guard let serialNumber = MGCopyAnswer("SerialNumber" as CFString)?.takeRetainedValue() as? String else {
        print("Failed to retrieve SerialNumber")
        return [:]
    }
    
    let identifiers = [
        "hardware_version": machine,
        "software_name": "iPhone OS",
        "software_version": UIDevice.current.systemVersion,
        "software_build_id": build,
        "unique_device_id": uniqueDeviceID,
        "serial_number": serialNumber
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
    
    var backoff: Int = 2
    let maxBackoff: Int = 64 // Maximum backoff in seconds

    func connect(_ url: URL) {
        logItems.log("Connecting to \(url)")
        connectionStatusMessage = "Connecting..."
        currentURL = url
        
        backoff = 2 // Reset backoff
        
        reconnectWork?.cancel()
        reconnectWork = nil

        connectionDelegate = RelayConnectionDelegate(manager: self)
    }

    func disconnect() {
        logItems.log("Disconnecting on request")
        connectionStatusMessage = ""
        currentURL = nil
        
        reconnectWork?.cancel()
        reconnectWork = nil
        
        connectionDelegate?.disconnect()
        connectionDelegate = nil
    }

    func triggerReconnect() {
        logItems.log("Triggering reconnect")
        connectionStatusMessage = "Reconnecting..."
        connectionDelegate?.disconnect()
        connectionDelegate = nil
        print("Waiting for \(backoff) backoff seconds")
        
        reconnectWork?.cancel()
        reconnectWork = nil
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.connectionDelegate = RelayConnectionDelegate(manager: self)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(backoff), execute: work)
        
        reconnectWork = work
        backoff = min(backoff * 2, maxBackoff)
    }
}

class RelayConnectionDelegate: WebSocketConnectionDelegate, ObservableObject {
    var connection: WebSocketConnection?
    weak var manager: RelayConnectionManager?

    init(manager: RelayConnectionManager) {
        self.manager = manager
        guard let currentURL = manager.currentURL else {
            manager.logItems.log("Current URL is nil", isError: true)
            return
        }
        connection = NWWebSocket(url: currentURL, connectAutomatically: true)
        connection?.delegate = self
        connection?.ping(interval: 30)
    }
    
    func disconnect() {
        connection?.disconnect(closeCode: .protocolCode(.normalClosure))
    }
    
    func webSocketDidConnect(connection: WebSocketConnection) {
        DispatchQueue.main.async {
            self.manager?.logItems.log("Websocket did connect")
            self.manager?.connectionStatusMessage = "Connected"
            var registerCommand: [String: Any] = ["command": "register", "data": ["": ""]]
            
            if self.manager?.currentURL?.absoluteString == self.manager?.savedRegistrationURL {
                print("Using saved registration code")
                self.manager?.logItems.log("Using saved registration code \(self.manager?.savedRegistrationCode ?? "")")
                self.manager?.logItems.log("Using saved registration secret \(self.manager?.savedRegistrationSecret ?? "")")
                registerCommand["data"] = ["code": self.manager?.savedRegistrationCode ?? "", "secret": self.manager?.savedRegistrationSecret ?? ""]
            }
            
            do {
                let data = try JSONSerialization.data(withJSONObject: registerCommand)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                    connection.send(string: jsonString)
                }
            } catch {
                self.manager?.logItems.log("JSON Serialization failed: \(error)", isError: true)
            }
        }
    }
    
    func webSocketDidDisconnect(connection: WebSocketConnection, closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        manager?.logItems.log("Websocket did disconnect", isError: true)
        print("Disconnected")
    }
    
    func webSocketViabilityDidChange(connection: WebSocketConnection, isViable: Bool) {
        // Respond to a WebSocket connection viability change event
        print("WebSocket connection viability changed to \(isViable), ignoring")
    }
    
    func webSocketDidAttemptBetterPathMigration(result: Result<WebSocketConnection, NWError>) {
        // Respond to when a WebSocket connection migrates to a better network path
        // (e.g. A device moves from a cellular connection to a Wi-Fi connection)
        print("WebSocket connection attempted better path migration, ignoring")
    }
    
    func webSocketDidReceiveError(connection: WebSocketConnection, error: NWError) {
        print(error)
        manager?.logItems.log("Websocket error: \(error)", isError: true)
        self.manager?.triggerReconnect()
    }
    
    func webSocketDidReceivePong(connection: WebSocketConnection) {
        // Respond to a WebSocket connection receiving a Pong from the peer
        //print("pong")
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, string: String) {
        DispatchQueue.main.async {
            print("Got string msg")
            // Parse as JSON
            let json = try! JSONSerialization.jsonObject(with: string.data(using: .utf8)!, options: [])
            print(json)
            
            // Save registration code
            if let jsonDict = json as? [String: Any] {
                if let data = jsonDict["data"] as? [String: Any] {
                    if let code = data["code"] as? String {
                        self.manager?.registrationCode = code
                        if self.manager?.savedRegistrationCode != code {
                            self.manager?.logItems.log("New registration code \(code)")
                            self.manager?.logItems.log("secret \(data["secret"] as? String ?? "")")
                        }
                        self.manager?.savedRegistrationCode = code
                        self.manager?.savedRegistrationSecret = data["secret"] as? String ?? ""
                        self.manager?.savedRegistrationURL = self.manager?.currentURL?.absoluteString ?? ""
                    }
                }
                if let command = jsonDict["command"] as? String {
                    if command == "get-version-info" {
                        let versionInfo = ["command": "response", "data": ["versions": getIdentifiers()], "id": jsonDict["id"]!] as [String : Any]
                        print("Sending version info: \(versionInfo)")
                        self.manager?.logItems.log("Sending version info: \(versionInfo)")
                        let data = try! JSONSerialization.data(withJSONObject: versionInfo)
                        connection.send(string: String(data: data, encoding: .utf8)!)
                    }
                    if command == "get-validation-data" {
                        print("Sending validation data")
                        let validationData = generateValidationData()
                        let v = validationData.base64EncodedString()
                        print("Validation data: \(v)")
                        self.manager?.logItems.log("Generated validation data: \(v)")
                        let validationDataDict: [String: Any] = [
                            "command": "response",
                            "data": ["data": v],
                            "id": jsonDict["id"] ?? ""
                        ]
                        do {
                            let data = try JSONSerialization.data(withJSONObject: validationDataDict)
                            if let jsonString = String(data: data, encoding: .utf8) {
                                connection.send(string: jsonString)
                            }
                        } catch {
                            self.manager?.logItems.log("JSON Serialization failed: \(error)", isError: true)
                        }
                    }
                }
            }
            // Respond to a WebSocket connection receiving a `String` message
        }
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, data: Data) {
        // Respond to a WebSocket connection receiving a binary `Data` message
        //  let json = try! JSONSerialization.jsonObject(with: data, options: [])
        print("got data msg")
        print(data)
    }
}