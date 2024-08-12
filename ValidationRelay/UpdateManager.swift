import Foundation

class UpdateManager {
    
    static let shared = UpdateManager()
    
    private init() {}
    
    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/JJTech0130/ValidationRelay/releases/latest") else {
            print("Invalid URL")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching update info: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    self.handleUpdate(version: tagName)
                } else {
                    print("Invalid JSON structure")
                }
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
            self.downloadAndUpdate()
        } else {
            print("App is up to date")
        }
    }
    
    private func downloadAndUpdate() {
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
        let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) } + [nil]
        
        let result = posix_spawn(&pid, rootHelperPath, nil, nil, argv, nil)
        
        if result == 0 {
            print("Update installation started")
        } else {
            print("Error starting update installation: \(result)")
        }
        
        for arg in argv {
            free(arg)
        }
    }
}
