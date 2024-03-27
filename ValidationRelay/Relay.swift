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
    // TODO: Don't fake these
    // Use uname to get hardware version
    // Use UIDevice to get software version
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
class RelayConnectionManager: WebSocketConnectionDelegate, ObservableObject {
    
    var connection: WebSocketConnection?
    
    @Published var registrationCode: String = "None"
    @Published var connectionStatusMessage: String = ""
    @Published var logItems = LogItems()
    
    // These must all be saved together
    @AppStorage("savedRegistrationSecret") public var savedRegistrationSecret = ""
    @AppStorage("savedRegistrationCode") public var savedRegistrationCode = ""
    @AppStorage("savedRegistrationURL") public var savedRegistrationURL = ""
    
    var currentURL: URL? = nil
    
    func connect(_ url: URL) {
        logItems.log("Connecting to \(url)")
        connectionStatusMessage = "Connecting..."
        currentURL = url
        let connection = NWWebSocket(url: url, connectAutomatically: true)
        connection.delegate = self
        connection.connect()
        connection.ping(interval: 30)
        self.connection = connection
        //print(getIdentifiers())
    }
    
    func disconnect() {
        logItems.log("Disconnecting on request")
        connection?.disconnect(closeCode: .protocolCode(.normalClosure))
        currentURL = nil
    }
    
    func webSocketDidConnect(connection: WebSocketConnection) {
        logItems.log("Websocket did connect")
        connectionStatusMessage = "Connected"
        var registerCommand = ["command": "register", "data": ["": ""]] as [String : Any]
        if currentURL?.absoluteString == savedRegistrationURL {
            print("Using saved registration code")
            logItems.log("Using saved registration code \(savedRegistrationCode)")
            registerCommand["data"] = ["code": savedRegistrationCode, "secret": savedRegistrationSecret]
        }
        let data = try! JSONSerialization.data(withJSONObject: registerCommand)
        print(String(data: data, encoding: .utf8)!)
        connection.send(string: String(data: data, encoding: .utf8)!)
    }
    func webSocketDidDisconnect(connection: WebSocketConnection, closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        logItems.log("Websocket did disconnect", isError: true)
        print("Disconnected")
        // Check if "error" is in the current status message, if so don't clear it
        if !connectionStatusMessage.contains("Error") {
            connectionStatusMessage = ""
        }
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
        logItems.log("Websocket error: \(error)", isError: true)
        connectionStatusMessage = "Error connecting to relay: \(error)"
    }

       func webSocketDidReceivePong(connection: WebSocketConnection) {
           // Respond to a WebSocket connection receiving a Pong from the peer
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
                        registrationCode = code
                        if savedRegistrationCode != code {
                            logItems.log("New registration code \(code)")
                        }
                        savedRegistrationCode = code
                        savedRegistrationSecret = data["secret"] as? String ?? ""
                        savedRegistrationURL = currentURL?.absoluteString ?? ""
                    }
                }
                if let command = jsonDict["command"] as? String {
                    if command == "get-version-info" {
                        let versionInfo = ["command": "response", "data": ["versions": getIdentifiers()], "id": jsonDict["id"]!] as [String : Any]
                        print("Sending version info: \(versionInfo)")
                        logItems.log("Sending version info: \(versionInfo)")
                        let data = try! JSONSerialization.data(withJSONObject: versionInfo)
                        connection.send(string: String(data: data, encoding: .utf8)!)
                    }
                    if command == "get-validation-data" {
                        print("Sending val data")
                        let v = generateValidationData()
                        print("Validation data: \(v.base64EncodedString())")
                        logItems.log("Generated validation data: \(v.base64EncodedString())")
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

