//
//  Relay.swift
//  ValidationRelay
//
//  Created by James Gill on 3/25/24.
//

import Foundation
import Network
import NWWebSocket
import Security
import SwiftUI

func copyMobileGestaltString(_ key: String) -> String? {
    guard let answer = MGCopyAnswer(key as CFString) else {
        return nil
    }
    return answer.takeRetainedValue() as? String
}

func getIdentifiers() -> [String: String]? {
    var ustruct: utsname = utsname()
    uname(&ustruct)
    var ustruct2 = ustruct
    let machine = withUnsafePointer(to: &ustruct2.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: ustruct.machine)) {
            String(cString: $0)
        }
    }
    
    
    guard let softwareBuildID = buildNumber(),
          let uniqueDeviceID = copyMobileGestaltString("UniqueDeviceID"),
          let serialNumber = copyMobileGestaltString("SerialNumber") else {
        return nil
    }

    let identifiers = [
        "hardware_version": machine,
        "software_name": "iPhone OS",
        "software_version": UIDevice.current.systemVersion,
        "software_build_id": softwareBuildID,
        "unique_device_id": uniqueDeviceID,
        "serial_number": serialNumber
        
    ]
    return identifiers
}

enum RegistrationSecretStore {
    private static let service = "app.openbubbles.ValidationRelay"
    private static let account = "registration-secret"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String) -> Bool {
        if value.isEmpty {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        guard let data = value.data(using: .utf8) else {
            return false
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var newItem = query
        newItem.merge(attributes) { _, new in new }
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }
}

class RelayConnectionManager: ObservableObject {
    @Published var registrationCode: String = "None"
    @Published var connectionStatusMessage: String = ""
    @Published var logItems = LogItems()
    
    // These must all be saved together
    @AppStorage("savedRegistrationCode") public var savedRegistrationCode = ""
    @AppStorage("savedRegistrationURL") public var savedRegistrationURL = ""

    public var savedRegistrationSecret: String {
        get {
            RegistrationSecretStore.read() ?? ""
        }
        set {
            if !RegistrationSecretStore.write(newValue) {
                logItems.log("Failed to update the registration secret", isError: true)
            }
        }
    }
    
    var currentURL: URL? = nil
    var connectionDelegate: RelayConnectionDelegate? = nil
    
    var reconnectWork: DispatchWorkItem? = nil
    var connectionTimeoutWork: DispatchWorkItem? = nil
    var watchdogTimer: DispatchSourceTimer? = nil
    var lastPongAt: Date? = nil
    var shouldReconnect = false
    
    var backoff: Int = 2
    let maxBackoff: Int = 64
    let connectionTimeout: TimeInterval = 30
    let watchdogInterval: TimeInterval = 30
    let staleConnectionInterval: TimeInterval = 90

    init() {
        if let legacySecret = UserDefaults.standard.string(forKey: "savedRegistrationSecret"),
           !legacySecret.isEmpty,
           RegistrationSecretStore.read() == nil {
            _ = RegistrationSecretStore.write(legacySecret)
        }
        UserDefaults.standard.removeObject(forKey: "savedRegistrationSecret")
    }

    func connectIfNeeded(_ url: URL) {
        if shouldReconnect, currentURL == url, connectionDelegate != nil {
            return
        }
        connect(url)
    }

    func refreshOnForeground(_ url: URL) {
        guard shouldReconnect, currentURL == url else {
            connect(url)
            return
        }
        if connectionStatusMessage != "Connected" ||
            lastPongAt.map({ Date().timeIntervalSince($0) > staleConnectionInterval }) == true {
            triggerReconnect()
        }
    }

    private func beginConnection(_ url: URL) {
        let delegate = RelayConnectionDelegate(manager: self, url: url)
        connectionDelegate = delegate

        connectionTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak delegate] in
            guard let self,
                  let delegate,
                  self.connectionDelegate === delegate,
                  self.connectionStatusMessage != "Connected" else {
                return
            }
            self.connectionTimeoutWork = nil
            self.logItems.log("Websocket connection timed out", isError: true)
            self.triggerReconnect(delegate)
        }
        connectionTimeoutWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + connectionTimeout,
            execute: work
        )
    }

    func connect(_ url: URL) {
        let port = url.port.map { ":\($0)" } ?? ""
        logItems.log("Connecting to \(url.scheme ?? "wss")://\(url.host ?? "relay")\(port)")
        connectionStatusMessage = "Connecting..."
        currentURL = url
        shouldReconnect = true
        
        backoff = 2 // Reset backoff
        
        reconnectWork?.cancel()
        reconnectWork = nil
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
        stopWatchdog()

        let oldDelegate = connectionDelegate
        connectionDelegate = nil
        oldDelegate?.disconnect()
        beginConnection(url)
    }

    func disconnect() {
        logItems.log("Disconnecting on request")
        connectionStatusMessage = ""
        shouldReconnect = false
        currentURL = nil
        
        reconnectWork?.cancel()
        reconnectWork = nil
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
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
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
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
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
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
            guard self.shouldReconnect, let url = self.currentURL else {
                return
            }
            self.beginConnection(url)
        }
        // Wait a bit then try again
        DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(backoff), execute: work)
        
        reconnectWork = work
        backoff = min(backoff * 2, maxBackoff)
    }
}

class RelayConnectionDelegate: WebSocketConnectionDelegate, ObservableObject {
    var connection: WebSocketConnection
    weak var manager: RelayConnectionManager?

    init(
        manager: RelayConnectionManager,
        url: URL
    ) {
        self.manager = manager
        connection = NWWebSocket(url: url, connectAutomatically: true)
        connection.delegate = self
        connection.ping(interval: 30)
    }
    
    func disconnect() {
        connection.disconnect(closeCode: .protocolCode(.normalClosure))
    }
    
    func webSocketDidConnect(connection: WebSocketConnection) {
        guard let manager else {
            return
        }
        manager.didConnect(self)
        var registerCommand = ["command": "register", "data": ["": ""]] as [String : Any]
        if manager.currentURL?.absoluteString == manager.savedRegistrationURL {
            manager.logItems.log("Using saved registration credentials")
            registerCommand["data"] = ["code": manager.savedRegistrationCode, "secret": manager.savedRegistrationSecret]
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: registerCommand)
            guard let message = String(data: data, encoding: .utf8) else {
                manager.logItems.log("Failed to encode registration request", isError: true)
                return
            }
            connection.send(string: message)
        } catch {
            manager.logItems.log("Failed to create registration request", isError: true)
        }
    }
    
    func webSocketDidDisconnect(connection: WebSocketConnection, closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        manager?.didDisconnect(self)
    }
    
    func webSocketViabilityDidChange(connection: WebSocketConnection, isViable: Bool) {
        if !isViable {
            manager?.logItems.log("Websocket connection is no longer viable", isError: true)
            manager?.triggerReconnect(self)
        }
    }
    
    func webSocketDidAttemptBetterPathMigration(result: Result<WebSocketConnection, NWError>) {
        // Respond to when a WebSocket connection migrates to a better network path
        // (e.g. A device moves from a cellular connection to a Wi-Fi connection)
        manager?.logItems.log("Websocket connection attempted network path migration")
    }
    
    func webSocketDidReceiveError(connection: WebSocketConnection, error: NWError) {
        manager?.logItems.log("Websocket error: \(error)", isError: true)
        manager?.triggerReconnect(self)
    }
    
    func webSocketDidReceivePong(connection: WebSocketConnection) {
        manager?.didReceivePong(self)
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, string: String) {
        guard let manager else {
            return
        }
        guard let encodedMessage = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: encodedMessage, options: []) else {
            manager.logItems.log("Received an invalid relay message", isError: true)
            return
        }
        manager.didReceivePong(self)
        
        // Save registration code
        if let jsonDict = json as? [String: Any] {
            if jsonDict["command"] as? String == "response",
               let data = jsonDict["data"] as? [String: Any] {
                if let code = data["code"] as? String,
                   let secret = data["secret"] as? String,
                   code.range(
                    of: #"^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}(-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}){3}$"#,
                    options: .regularExpression
                   ) != nil,
                   secret.range(of: #"^[A-Za-z0-9+/]{1,64}$"#, options: .regularExpression) != nil {
                    manager.registrationCode = code
                    if manager.savedRegistrationCode != code {
                        manager.logItems.log("Received new registration credentials")
                    }
                    manager.savedRegistrationCode = code
                    manager.savedRegistrationSecret = secret
                    manager.savedRegistrationURL = manager.currentURL?.absoluteString ?? ""
                } else if data["code"] != nil || data["secret"] != nil {
                    manager.logItems.log("Rejected malformed registration credentials", isError: true)
                }
            }
            if let command = jsonDict["command"] as? String,
               command == "get-version-info" || command == "get-validation-data" {
                guard let requestID = jsonDict["id"] else {
                    manager.logItems.log("Received a relay request without an id", isError: true)
                    return
                }
                if command == "get-version-info" {
                    guard let identifiers = getIdentifiers() else {
                        manager.logItems.log("Failed to read device identifiers", isError: true)
                        return
                    }
                    let versionInfo = ["command": "response", "data": ["versions": identifiers], "id": requestID] as [String : Any]
                    manager.logItems.log("Sending device version information")
                    sendJSON(versionInfo, connection: connection)
                }
                if command == "get-validation-data" {
                    manager.logItems.log("Generating validation data")
                    generateValidationData { [weak self, weak manager] result in
                        DispatchQueue.main.async {
                            guard let self,
                                  let manager,
                                  manager.connectionDelegate === self else {
                                return
                            }
                            switch result {
                            case .success(let validationData):
                                manager.logItems.log("Generated validation data")
                                let response = [
                                    "command": "response",
                                    "data": ["data": validationData.base64EncodedString()],
                                    "id": requestID
                                ] as [String : Any]
                                self.sendJSON(response, connection: connection)
                            case .failure(let error):
                                manager.logItems.log(
                                    "Failed to generate validation data: \(error.localizedDescription)",
                                    isError: true
                                )
                            }
                        }
                    }
                }
            }
        }
        // Respond to a WebSocket connection receiving a `String` message
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, data: Data) {
        manager?.logItems.log("Received an unexpected binary relay message", isError: true)
    }

    private func sendJSON(_ object: [String: Any], connection: WebSocketConnection) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard let message = String(data: data, encoding: .utf8) else {
                manager?.logItems.log("Failed to encode relay response", isError: true)
                return
            }
            connection.send(string: message)
        } catch {
            manager?.logItems.log("Failed to create relay response", isError: true)
        }
    }
}

