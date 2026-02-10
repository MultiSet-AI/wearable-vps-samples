/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import os.log

/// Manages authentication with the Multiset API
actor AuthManager {

    // MARK: - Singleton
    static let shared = AuthManager()

    // MARK: - Private Properties
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MultiSetWearable", category: "AuthManager")
    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    // Token validity: 1 hour with 5-minute buffer
    private let tokenValidityDuration: TimeInterval = 3600  // 1 hour
    private let tokenExpiryBuffer: TimeInterval = 300       // 5 minutes

    private init() {}

    // MARK: - Public Methods

    /// Get authentication token, using cached token if still valid
    func getToken() async throws -> String {
        // Return cached token if still valid (with 5 minute buffer)
        if let token = cachedToken, Date() < tokenExpiry.addingTimeInterval(-tokenExpiryBuffer) {
            return token
        }

        // Fetch new token
        return try await fetchNewToken()
    }

    /// Clear cached token (for logout or token refresh)
    func clearToken() {
        cachedToken = nil
        tokenExpiry = .distantPast
        logger.debug("Auth token cleared")
    }

    /// Force re-authentication with current credentials
    func forceReauthenticate() async throws -> String {
        logger.debug("Force re-authentication requested")
        clearToken()
        return try await fetchNewToken()
    }

    /// Check if we have a valid cached token
    func hasValidToken() -> Bool {
        guard cachedToken != nil else { return false }
        return Date() < tokenExpiry.addingTimeInterval(-tokenExpiryBuffer)
    }

    // MARK: - Private Methods

    private func fetchNewToken() async throws -> String {
        let config = LocalizationConfig.shared

        guard config.hasCredentials else {
            throw AuthError.notConfigured
        }

        let credentials = "\(LocalizationConfig.clientId):\(LocalizationConfig.clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw AuthError.invalidCredentials
        }
        let base64Credentials = credentialsData.base64EncodedString()

        guard let url = URL(string: LocalizationConfig.authURL) else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data()
        request.timeoutInterval = 30

        logger.debug("Requesting authentication token...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            logger.error("Auth failed with code: \(httpResponse.statusCode), body: \(body)")
            throw AuthError.authenticationFailed(statusCode: httpResponse.statusCode)
        }

        let json = try JSONDecoder().decode(TokenResponse.self, from: data)

        guard !json.token.isEmpty else {
            logger.error("No token in response")
            throw AuthError.noTokenReceived
        }

        // Cache token for 1 hour
        cachedToken = json.token
        tokenExpiry = Date().addingTimeInterval(tokenValidityDuration)

        logger.debug("Authentication successful, token cached")
        return json.token
    }
}

// MARK: - Supporting Types

private struct TokenResponse: Decodable {
    let token: String
}

enum AuthError: LocalizedError {
    case notConfigured
    case invalidCredentials
    case invalidURL
    case invalidResponse
    case authenticationFailed(statusCode: Int)
    case noTokenReceived

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SDK not configured. Please set up credentials first."
        case .invalidCredentials:
            return "Invalid credentials format."
        case .invalidURL:
            return "Invalid authentication URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .authenticationFailed(let statusCode):
            return "Authentication failed with status code: \(statusCode)"
        case .noTokenReceived:
            return "No token received from server."
        }
    }
}
