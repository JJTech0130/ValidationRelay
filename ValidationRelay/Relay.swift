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
    
    //init() {}

    func connect(_ url: URL) {
        logItems.log("Connecting to \(url)")
        connectionStatusMessage = "Connecting..."
        currentURL = url

        connectionDelegate = RelayConnectionDelegate(manager: self)
    }

    func disconnect() {
        logItems.log("Disconnecting on request")
        connectionStatusMessage = ""
        currentURL = nil
        
        connectionDelegate?.disconnect()
        connectionDelegate = nil
    }

    func triggerReconnect() {
        logItems.log("Triggering reconnect")
        connectionStatusMessage = "Reconnecting..."
        // Delete the delegate so that more errors don't come in
        connectionDelegate?.disconnect()
        connectionDelegate = nil
        // Wait a bit then try again
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.connectionDelegate = RelayConnectionDelegate(manager: self)
        }
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
        manager.logItems.log("Websocket did connect")
        manager.connectionStatusMessage = "Connected"
        var registerCommand = ["command": "register", "data": ["": ""]] as [String : Any]
        if manager.currentURL?.absoluteString == manager.savedRegistrationURL {
            print("Using saved registration code")
            manager.logItems.log("Using saved registration code \(manager.savedRegistrationCode)")
            manager.logItems.log("Using saved registration secret \(manager.savedRegistrationSecret)")
            registerCommand["data"] = ["code": manager.savedRegistrationCode, "secret": manager.savedRegistrationSecret]
        }
        let data = try! JSONSerialization.data(withJSONObject: registerCommand)
        print(String(data: data, encoding: .utf8)!)
        connection.send(string: String(data: data, encoding: .utf8)!)
    }
    
    func webSocketDidDisconnect(connection: WebSocketConnection, closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        manager.logItems.log("Websocket did disconnect", isError: true)
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
        manager.logItems.log("Websocket error: \(error)", isError: true)
        self.manager.triggerReconnect()
    }
    
    func webSocketDidReceivePong(connection: WebSocketConnection) {
        // Respond to a WebSocket connection receiving a Pong from the peer
        //print("pong")
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, string: String) {
        print("Got string msg")
        // Parse as JSON
        let json = try! JSONSerialization.jsonObject(with: string.data(using: .utf8)!, options: [])
        print(json)
        
        // Save registration code
        if let jsonDict = json as? [String: Any] {
            if let data = jsonDict["data"] as? [String: Any] {
                if let code = data["code"] as? String {
                    manager.registrationCode = code
                    if manager.savedRegistrationCode != code {
                        manager.logItems.log("New registration code \(code)")
                        manager.logItems.log("secret \(data["secret"] as? String ?? "")")
                    }
                    manager.savedRegistrationCode = code
                    manager.savedRegistrationSecret = data["secret"] as? String ?? ""
                    manager.savedRegistrationURL = manager.currentURL?.absoluteString ?? ""
                }
            }
            if let command = jsonDict["command"] as? String {
                if command == "get-version-info" {
                    let versionInfo = ["command": "response", "data": ["versions": getIdentifiers()], "id": jsonDict["id"]!] as [String : Any]
                    print("Sending version info: \(versionInfo)")
                    manager.logItems.log("Sending version info: \(versionInfo)")
                    let data = try! JSONSerialization.data(withJSONObject: versionInfo)
                    connection.send(string: String(data: data, encoding: .utf8)!)
                }
                if command == "get-validation-data" {
                    print("Sending val data")
                    let v = generateValidationData()
                    print("Validation data: \(v.base64EncodedString())")
                    manager.logItems.log("Generated validation data: \(v.base64EncodedString())")
                    let validationData = ["command": "response", "data": ["data": v.base64EncodedString()], "id": jsonDict["id"]!] as [String : Any]
                    let data = try! JSONSerialization.data(withJSONObject: validationData)
                    connection.send(string: String(data: data, encoding: .utf8)!)
                }
            }
        }
        // Respond to a WebSocket connection receiving a `String` message
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, data: Data) {
        // Respond to a WebSocket connection receiving a binary `Data` message
        //  let json = try! JSONSerialization.jsonObject(with: data, options: [])
        print("got data msg")
        print(data)
    }
}

