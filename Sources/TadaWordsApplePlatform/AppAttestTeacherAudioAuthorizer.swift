import CryptoKit
import DeviceCheck
@preconcurrency import Foundation
import TadaWordsDomain

struct AuthorizedTeacherAudioRequest: Sendable {
    let body: Data
    let appAttestHeader: String
}

protocol TeacherAudioRequestAuthorizing: Sendable {
    func authorize(
        body: @Sendable (String) throws -> Data
    ) async throws -> AuthorizedTeacherAudioRequest

    func resetRegistration() async
}

/// Owns the device-local App Attest key and signs the exact canonical request
/// bytes sent to PawGoo. The opaque key identifier is not child or Profile data.
actor AppAttestTeacherAudioAuthorizer: TeacherAudioRequestAuthorizing {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let keyIDDefaultsKey =
        "app.tadawords.teacher-audio.app-attest-key-id.v1"

    private let endpoint: URL
    private let service: DCAppAttestService
    private let defaults: UserDefaults
    private let dataLoader: DataLoader
    private var keyID: String?

    init(
        endpoint: URL,
        service: DCAppAttestService = .shared,
        defaults: UserDefaults = .standard,
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.endpoint = endpoint
        self.service = service
        self.defaults = defaults
        self.dataLoader = dataLoader
        keyID = defaults.string(forKey: Self.keyIDDefaultsKey)
    }

    func authorize(
        body: @Sendable (String) throws -> Data
    ) async throws -> AuthorizedTeacherAudioRequest {
        guard service.isSupported else {
            throw TeacherWordAudioError.appAttestUnavailable
        }
        let keyID = try await registeredKeyID()
        let challenge = try await challenge(purpose: "assert")
        let requestBody = try body(challenge)
        let assertion = try await service.generateAssertion(
            keyID,
            clientDataHash: Data(SHA256.hash(data: requestBody))
        )
        let header = try JSONEncoder().encode(
            AssertionHeader(
                keyId: keyID,
                assertion: assertion.base64EncodedString()
            )
        )
        return AuthorizedTeacherAudioRequest(
            body: requestBody,
            appAttestHeader: header.base64EncodedString()
        )
    }

    func resetRegistration() {
        keyID = nil
        defaults.removeObject(forKey: Self.keyIDDefaultsKey)
    }

    private func registeredKeyID() async throws -> String {
        if let keyID { return keyID }

        let challenge = try await challenge(purpose: "register")
        let generatedKeyID = try await service.generateKey()
        let attestation = try await service.attestKey(
            generatedKeyID,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8)))
        )
        var request = URLRequest(url: endpointURL(path: "/v1/app-attest/register"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RegistrationPayload(
                challenge: challenge,
                keyId: generatedKeyID,
                attestation: attestation.base64EncodedString()
            )
        )
        let (_, response) = try await dataLoader(request)
        guard let http = response as? HTTPURLResponse else {
            throw TeacherWordAudioError.invalidResponse
        }
        guard http.statusCode == 204 else {
            throw TeacherWordAudioError.serverRejected(
                statusCode: http.statusCode
            )
        }
        keyID = generatedKeyID
        defaults.set(generatedKeyID, forKey: Self.keyIDDefaultsKey)
        return generatedKeyID
    }

    private func challenge(purpose: String) async throws -> String {
        var request = URLRequest(
            url: endpointURL(path: "/v1/app-attest/challenge")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChallengeRequest(purpose: purpose)
        )
        let (data, response) = try await dataLoader(request)
        guard let http = response as? HTTPURLResponse else {
            throw TeacherWordAudioError.invalidResponse
        }
        guard http.statusCode == 201 else {
            throw TeacherWordAudioError.serverRejected(
                statusCode: http.statusCode
            )
        }
        return try JSONDecoder().decode(ChallengeResponse.self, from: data).challenge
    }

    private func endpointURL(path: String) -> URL {
        var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        )!
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private struct ChallengeRequest: Encodable {
        let purpose: String
    }

    private struct ChallengeResponse: Decodable {
        let challenge: String
    }

    private struct RegistrationPayload: Encodable {
        let challenge: String
        let keyId: String
        let attestation: String
    }

    private struct AssertionHeader: Encodable {
        let keyId: String
        let assertion: String
    }
}
