// UpdateManager.swift

import Foundation
import UserNotifications
import UIKit

class UpdateManager {
    
    static let shared = UpdateManager()
    
    private init() {}
    
    func checkForUpdates(completion: (() -> Void)? = nil) {
        guard let url = URL(string: "https://api.github.com/repos/JJTech0130/ValidationRelay/releases/latest") else {
            print("Invalid URL")
            completion?()
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { completion?() }
            guard let data = data, error == nil else {
                print("Error fetching update info: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let releaseInfo = try decoder.decode(GitHubRelease.self, from: data)
                self.handleUpdate(version: releaseInfo.tag_name)
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }
    
    private func handleUpdate(version: String) {
        // Compare the version with the current app version
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            print("Unable to get current app version")
            return
        }
        
        if version.compare(currentVersion, options: .numeric) == .orderedDescending {
            print("New version available: \(version)")
            DispatchQueue.main.async {
                self.notifyUserAboutUpdate(version: version)
            }
        } else {
            print("App is up to date")
        }
    }
    
    private func notifyUserAboutUpdate(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Update Available"
        content.body = "A new version (\(version)) is available. Tap to update."
        content.sound = .default
        content.categoryIdentifier = "UPDATE_CATEGORY"
        
        // Set up the notification action
        let updateAction = UNNotificationAction(identifier: "UPDATE_NOW", title: "Update Now", options: [.foreground])
        let category = UNNotificationCategory(identifier: "UPDATE_CATEGORY", actions: [updateAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(identifier: "UpdateAvailable", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    func downloadAndUpdate() {
        guard let url = URL(string: "https://github.com/JJTech0130/ValidationRelay/releases/latest/download/ValidationRelay.ipa") else {
            print("Invalid download URL")
            return
        }
        
        let task = URLSession.shared.downloadTask(with: url) { location, response, error in
            guard let location = location, error == nil else {
                print("Error downloading update: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                let fileManager = FileManager.default
                let destinationURL = fileManager.temporaryDirectory.appendingPathComponent("ValidationRelay.ipa")
                
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                
                try fileManager.moveItem(at: location, to: destinationURL)
                
                self.installUpdate(at: destinationURL)
            } catch {
                print("Error handling downloaded file: \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }
    
    private func installUpdate(at url: URL) {
        let rootHelperPath = "/usr/libexec/trollstore-helper"
        let args = ["install", url.path]
        
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [rootHelperPath.withCString(strdup)] + args.map { $0.withCString(strdup) } + [nil]
        
        let result = posix_spawn(&pid, rootHelperPath, nil, nil, argv, nil)
        
        if result == 0 {
            print("Update installation started")
        } else {
            print("Error starting update installation: \(result)")
        }
        
        for arg in argv where arg != nil {
            free(arg)
        }
    }
    
    // Background Fetch Support -WIP
    
    func performBackgroundFetch(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        checkForUpdates {
            // Assuming updates are checked and handled
            completion(.newData)
        }
    }
}

// GitHubRelease Model - WIP

struct GitHubRelease: Decodable {
    let tag_name: String
}
