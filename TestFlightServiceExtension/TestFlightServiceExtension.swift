//
//  TestFlightServiceExtension.swift
//  TestFlightServiceExtension
//
//  Created by James Gill on 3/29/24.
//

import Foundation
import os.log

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
        super.`init`()
    }
    
    @objc func serviceExtensionTimeWillExpire() {
        os_log("Time is up!")
    }

    @objc func didReceivePushToken(_ pushToken: Any, reply: Any) {
        os_log("Received push token: %{public}@", log: OSLog.app, type: .error, pushToken as! CVarArg)
    }
}
