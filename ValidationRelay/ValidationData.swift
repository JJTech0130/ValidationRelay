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
    case bundledCertificateInvalid

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
        case .bundledCertificateInvalid:
            return "The bundled Apple validation certificate is invalid."
        }
    }
}

private let validationQueue = DispatchQueue(label: "app.openbubbles.validation-relay.validation")
private let validationRequestTimeout: TimeInterval = 30
// SHA-256: 1B172B7411B63A03C6E220C11A5B7C6D08DA91A418B59E5B2794AAC0EC6EE4DA
private let bundledValidationCertificateBase64 = """
AQIAAAQWMIIEEjCCAvqgAwIBAgIBHDANBgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBw
bGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJv
b3QgQ0EwHhcNMTEwMTI2MTkwMTM0WhcNMTkwMTI2MTkwMTM0WjCBhTELMAkGA1UEBhMCVVMxEzARBgNVBAoMCkFw
cGxlIEluYy4xJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MTkwNwYDVQQDDDBBcHBsZSBT
eXN0ZW0gSW50ZWdyYXRpb24gQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
ggEKAoIBAQDa4A+Yl8tYKYYqC7ieGVoxwy0OaixSAe4dA/uCQWnNUCY2ercMbw45A7jUGFajCLI8w/s2QeTXyGdg
MgtOMn2H9/3NU7AauvwfbMlFB62COPOofMROwrFW2T6ybW0EQRrBmkfArBV8LXiRqweiZbF6g92YS3dA2O5Q68dr
WAgGl1dVfSf4Cua1Feenk/nxgOZCeT8W0zKdEXZBKQoxCe8PW/jzp6n3Ug27+C10rKZJHx/OewWnhT2+z6KnqiOF
Zv7FFhJ+W+Ixd5ECCd9+fuSK4OxBrBcsBOC8eaSJeEQGiztLoLyE4rCCtTK+BBwD7YI+dTcUz3WfgjFtzwkUhtEn
AgMBAAGjga4wgaswDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFPAwc2Py7x2szOYJ
MsH6eXqxaVBoMB8GA1UdIwQYMBaAFCvQaUeUdgn+9GuNLkCm90dNfwheMDYGA1UdHwQvMC0wK6ApoCeGJWh0dHA6
Ly93d3cuYXBwbGUuY29tL2FwcGxlY2Evcm9vdC5jcmwwEAYKKoZIhvdjZAYCBAQCBQAwDQYJKoZIhvcNAQEFBQAD
ggEBAD17j60fDCKKm0ujz/grsB9o4Qz3nCSDFgMt07Ko0EPorzyXJsit1SzETFVTAUnQ4rT75tty0Zi7/JvITreP
zGWGf0S52icqTt/L39N930Fx+LPAHaIKM7nsK8Vzcvvhyl2OLzT0a8RPD8iKrA/7byVut66Ox+QCuCBOXVZMSZex
JHR+yZOTNIyZ0afAHNPUwq5p65+fV+Jox8rVxSKCZEFY/njRysH5NmprRPezhnJ6ZEAXMZ28rHXw+jNR5b0Balg/
8ACumVwKwsnpXhyHAuygCFVBKpuMZIWOUAPN4BGvznIZ61Lzr5Ktky6Undav/8Am8d6UkhzZvD02zFX6ONsAAAUx
MIIFLTCCBBWgAwIBAgIISyyRSB2bfaAwDQYJKoZIhvcNAQEFBQAwgYUxCzAJBgNVBAYTAlVTMRMwEQYDVQQKDApB
cHBsZSBJbmMuMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTE5MDcGA1UEAwwwQXBwbGUg
U3lzdGVtIEludGVncmF0aW9uIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTExMDMyNTAxMTMzMloXDTE0MDMy
NDAxMTMzMlowaTEdMBsGA1UEAwwURFJNIFRlY2hub2xvZ2llcyBBMDExJjAkBgNVBAsMHUFwcGxlIENlcnRpZmlj
YXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzCCASIwDQYJKoZIhvcNAQEB
BQADggEPADCCAQoCggEBALQGbX5lc5fhv0mx+poiLqfTcYEga0lBFcLbYHrGordNei+OwWMHHATMk9jgDci48lvO
bfpCyxBAwiQKp+QdJoKKPjCGXe0XOO6Hq73oSEpJd4Uut5GEmyl9QQWgefWtjMEL2J1p55yyqUbQS/4JGFAkillH
KyJVR+1RIp1C6Z3ugcNHzeRvCio/TyvSBNC4jOhkmN/OYFObiBrP1MINdGW/84WHX0uHEKKHim0+QFUO+Z+ZzDKT
g1GIybn4XskZXxfna5t8Ot3/aN/U0TRVdOz3S+gckHWF8vxD/6VEI1I/+/Uh44MWP74KdPk8dJlq/j/SWqFQ4y6L
SA0iJjvVnkkCAwEAAaOCAbowggG2MB0GA1UdDgQWBBTSJCP76+iOj3GchO5icz3pXiQJLzAMBgNVHRMBAf8EAjAA
MB8GA1UdIwQYMBaAFPAwc2Py7x2szOYJMsH6eXqxaVBoMIIBDgYDVR0gBIIBBTCCAQEwgf4GCSqGSIb3Y2QFATCB
8DAoBggrBgEFBQcCARYcaHR0cDovL3d3dy5hcHBsZS5jb20vYXBwbGVjYTCBwwYIKwYBBQUHAgIwgbYMgbNSZWxp
YW5jZSBvbiB0aGlzIGNlcnRpZmljYXRlIGJ5IGFueSBwYXJ0eSBhc3N1bWVzIGFjY2VwdGFuY2Ugb2YgdGhlIHRo
ZW4gYXBwbGljYWJsZSBzdGFuZGFyZCB0ZXJtcyBhbmQgY29uZGl0aW9ucyBvZiB1c2UsIGNlcnRpZmljYXRlIHBv
bGljeSBhbmQgY2VydGlmaWNhdGlvbiBwcmFjdGljZSBzdGF0ZW1lbnRzLjAvBgNVHR8EKDAmMCSgIqAghh5odHRw
Oi8vY3JsLmFwcGxlLmNvbS9hc2ljYS5jcmwwDgYDVR0PAQH/BAQDAgWgMBMGCiqGSIb3Y2QGDAEBAf8EAgUAMA0G
CSqGSIb3DQEBBQUAA4IBAQB9eadjbkE7vsHOsYz6bTAguLpJMJI9HVXOucItS2LFykD2t7yx9tKm+q0Ba08czK7O
RiD/wrPALHdP0BNETIfHYS0Px8xDLjc6N/2umJoStkmwqnfTU4GWgM2E23OqR6ggVjbC2aXpDDwiHXnv57BPCX1e
+7Iio7b3IyUJg3moNFaE5kWtIqEcVZyiLx+2Ibn/2A/Jcwl28AMXGY/po/zmQstfZIaWjGg/wqBYQtSfdm2Vv8D3
2xR0/Fqogsem/FaKN7fIcpy8m0TRRuKNJNl/J3nxdLnFsrDC4SYG5P+vpQvZox6V20SRzOlLAjID5lL2pypaIzTQ
HRfy6+rCeQrp
"""

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

private func certificateFromPlist(_ data: Data) throws -> Data {
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

private func isCertificateTrustError(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else {
        return false
    }
    return [
        .secureConnectionFailed,
        .serverCertificateHasBadDate,
        .serverCertificateUntrusted,
        .serverCertificateNotYetValid,
        .clientCertificateRejected
    ].contains(urlError.code)
}

private func getCertificate() throws -> Data {
    guard let url = URL(string: "https://static.ess.apple.com/identity/validation/cert-1.0.plist") else {
        throw ValidationDataError.invalidResponse
    }
    do {
        return try certificateFromPlist(
            fetchValidationData(URLRequest(url: url))
        )
    } catch {
        guard isCertificateTrustError(error),
              let bundledCertificate = Data(
                base64Encoded: bundledValidationCertificateBase64,
                options: .ignoreUnknownCharacters
              ),
              bundledCertificate.count == 2385 else {
            throw error
        }
        return bundledCertificate
    }
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
