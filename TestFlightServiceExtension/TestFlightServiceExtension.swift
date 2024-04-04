//
//  TestFlightServiceExtension.swift
//  TestFlightServiceExtension
//
//  Created by James Gill on 4/4/24.
//

import Foundation
import os.log
import UIKit

extension OSLog {
    static let app = OSLog(category: "Application")
    
    private convenience init(category: String, bundle: Bundle = Bundle.main) {
        let identifier = bundle.infoDictionary?["CFBundleIdentifier"] as? String
        self.init(subsystem: (identifier ?? "").appending(".logs"), category: category)
    }
}

@objc class TestFlightServiceExtension : ASDTestFlightServiceExtension {
    @objc override func `init`() {
        os_log("Hello, Initializing Service Extension...", log: OSLog.app, type: .error)
        let options = FBSOpenApplicationOptions()
        options.dictionary = [FBSOpenApplicationOptionKeyUnlockDevice : true]
        print(options)
        FBSOpenApplicationService().openApplication("com.apple.TestFlight", withOptions: options, completion: nil)
        // Log the SerialNumber to prove we have entitlements
        //let serial = MGCopyAnswer("SerialNumber" as CFString)!.takeRetainedValue() as! String
        //os_log("Serial Number: %{public}@", log: OSLog.app, type: .error, serial)
        // Start a background loop to log we are alive
        DispatchQueue.global(qos: .background).async {
            while true {
                os_log("Still alive...", log: OSLog.app, type: .error)
                sleep(5)
            }
        }
        super.`init`()
    }
    
//    @objc override func beginRequest(with context: NSExtensionContext) {
//        os_log("Hello, Beginning Request...", log: OSLog.app, type: .error)
//        //let url = URL(string: "validationrelay://")!
//        //context.open(url, completionHandler: nil)
//        super.beginRequest(with: context)
//    }
    
    @objc func serviceExtensionTimeWillExpire() {
        os_log("Time is up!")
    }

    @objc func didReceivePushToken(_ pushToken: Any, reply: Any) {
        os_log("Received push token: %{public}@", log: OSLog.app, type: .error, pushToken as! CVarArg)
    }
}
