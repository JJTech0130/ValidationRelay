//
//  ValidationData.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import Foundation

//struct ValidationSession {
//    init() {
//        // Setup session, make request
//    }
//    
//    var expiry: Date {
//        get {
//            return Date()
//        }
//    }
//    
//    func sign(_ data: Data = Data()) -> Data {
//        return Data()
//    }
//}

/// Makes an HTTP request to http://static.ess.apple.com/identity/validation/cert-1.0.plist
/// parses the plist and extracts the raw certificate data
func getCertificate() -> Data {
    let url = URL(string: "http://static.ess.apple.com/identity/validation/cert-1.0.plist")!
    let data = try! Data(contentsOf: url)
    let plist = try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    let certData = plist["cert"] as! Data
    return certData
}

/// Makes an HTTPS POST to https://identity.ess.apple.com/WebObjects/TDIdentityService.woa/wa/initializeValidation
/// with a plist containing the session-info-request and returns the session-info
func initializeValidation(_ request: Data) -> Data {
    // Encode body as session-info-request key in plist
    let requestB = try! PropertyListSerialization.data(fromPropertyList: ["session-info-request": request], format: .xml, options: 0)
    
    let url = URL(string: "https://identity.ess.apple.com/WebObjects/TDIdentityService.woa/wa/initializeValidation")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.httpBody = requestB
    req.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
    NSLog("Making POST request to \(url) with body \(requestB)")
    let data = try! NSURLConnection.sendSynchronousRequest(req, returning: nil)
    // Parse the response
    NSLog("Got response \(data)")
    let plist = try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    NSLog("Got plist \(plist)")
    let sessionInfo = plist["session-info"] as! Data
    NSLog("Got session info \(sessionInfo)")
    return sessionInfo
}

func generateValidationData() -> Data {
    let cert: Data = getCertificate()
    var val_ctx: UInt64 = 0
    var session_req: NSData? = NSData()
    var ret = NACInit(cert, &val_ctx, &session_req)
    NSLog("NACInit returned \(ret)")
    assert(ret == 0)
    let sessionInfo = initializeValidation(session_req! as Data)
    NSLog("Got session info \(sessionInfo)")
    
    ret = NACKeyEstablishment(val_ctx, sessionInfo)
    NSLog("NACKeyEstablishment returned \(ret)")
    assert(ret == 0)
    
    var signature: NSData? = NSData()
    ret = NACSign(val_ctx, Data(), &signature)
    NSLog("NACSign returned \(ret)")
    assert(ret == 0)
    
    NSLog("VALIDATION DATA \(signature!.base64EncodedString())")
    
    return signature! as Data
}

