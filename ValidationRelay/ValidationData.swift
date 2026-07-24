//
//  ValidationData.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import Foundation

enum ValidationDataError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case missingPlistValue(String)
    case nativeFailure(String, Int)
    case nativeOutputMissing(String)
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Apple returned an invalid response."
        case .httpStatus(let status):
            return "Apple returned HTTP status \(status)."
        case .missingPlistValue(let key):
            return "Apple's response did not contain \(key)."
        case .nativeFailure(let operation, let status):
            return "\(operation) failed with status \(status)."
        case .nativeOutputMissing(let operation):
            return "\(operation) did not return data."
        case .requestTimedOut:
            return "The validation request timed out."
        }
    }
}

private let validationQueue = DispatchQueue(label: "app.openbubbles.validation-relay.validation")
private let validationRequestTimeout: TimeInterval = 30

private func fetchValidationData(_ request: URLRequest) throws -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    var requestResult: Result<Data, Error>?

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = validationRequestTimeout
    configuration.timeoutIntervalForResource = validationRequestTimeout
    let session = URLSession(configuration: configuration)
    let task = session.dataTask(with: request) { data, response, error in
        defer {
            semaphore.signal()
        }

        if let error {
            requestResult = .failure(error)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse,
              let data else {
            requestResult = .failure(ValidationDataError.invalidResponse)
            return
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            requestResult = .failure(ValidationDataError.httpStatus(httpResponse.statusCode))
            return
        }
        requestResult = .success(data)
    }
    task.resume()

    guard semaphore.wait(timeout: .now() + validationRequestTimeout + 5) == .success else {
        task.cancel()
        session.invalidateAndCancel()
        throw ValidationDataError.requestTimedOut
    }
    session.finishTasksAndInvalidate()
    guard let requestResult else {
        throw ValidationDataError.invalidResponse
    }
    return try requestResult.get()
}

private func getCertificate() throws -> Data {
    guard let url = URL(string: "https://static.ess.apple.com/identity/validation/cert-1.0.plist") else {
        throw ValidationDataError.invalidResponse
    }
    let data = try fetchValidationData(URLRequest(url: url))
    guard let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
    ) as? [String: Any],
          let certificate = plist["cert"] as? Data else {
        throw ValidationDataError.missingPlistValue("cert")
    }
    return certificate
}

private func initializeValidation(_ request: Data) throws -> Data {
    let requestBody = try PropertyListSerialization.data(
        fromPropertyList: ["session-info-request": request],
        format: .xml,
        options: 0
    )

    guard let url = URL(string: "https://identity.ess.apple.com/WebObjects/TDIdentityService.woa/wa/initializeValidation") else {
        throw ValidationDataError.invalidResponse
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = requestBody
    urlRequest.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")

    let data = try fetchValidationData(urlRequest)
    guard let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
    ) as? [String: Any],
          let sessionInfo = plist["session-info"] as? Data else {
        throw ValidationDataError.missingPlistValue("session-info")
    }
    return sessionInfo
}

private func generateValidationData() throws -> Data {
    let certificate = try getCertificate()
    var validationContext: UInt64 = 0
    var sessionRequest: NSData?
    var status = NACInit(certificate, &validationContext, &sessionRequest)
    guard status == 0 else {
        throw ValidationDataError.nativeFailure("NACInit", Int(status))
    }
    guard let sessionRequest else {
        throw ValidationDataError.nativeOutputMissing("NACInit")
    }

    let sessionInfo = try initializeValidation(sessionRequest as Data)
    status = NACKeyEstablishment(validationContext, sessionInfo)
    guard status == 0 else {
        throw ValidationDataError.nativeFailure("NACKeyEstablishment", Int(status))
    }

    var signature: NSData?
    status = NACSign(validationContext, Data(), &signature)
    guard status == 0 else {
        throw ValidationDataError.nativeFailure("NACSign", Int(status))
    }
    guard let signature else {
        throw ValidationDataError.nativeOutputMissing("NACSign")
    }
    return signature as Data
}

func generateValidationData(
    completion: @escaping (Result<Data, Error>) -> Void
) {
    validationQueue.async {
        do {
            completion(.success(try generateValidationData()))
        } catch {
            completion(.failure(error))
        }
    }
}
