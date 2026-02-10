/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import UIKit
import os.log

/// Handles network requests for the Multiset Localization API
/// Uses single-frame localization via query-form endpoint
final class LocalizationService {

    // MARK: - Singleton
    static let shared = LocalizationService()

    // MARK: - Constants
    private let maxRetries = 1
    private let initialRetryDelay: TimeInterval = 1.0
    private let retryableCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    private let jpegQuality: CGFloat = 0.8

    // MARK: - Private Properties
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MultiSetWearable", category: "LocalizationService")
    private let authManager = AuthManager.shared

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Public Methods

    /// Send a single-frame localization request
    /// - Parameters:
    ///   - image: The captured image from glasses
    /// - Returns: LocalizationResult on success
    func sendLocalizationRequest(image: UIImage) async throws -> LocalizationResult {
        guard let imageData = image.jpegData(compressionQuality: jpegQuality) else {
            throw LocalizationError.imageConversionFailed
        }

        let width = Int(image.size.width)
        let height = Int(image.size.height)

        return try await sendLocalizationRequest(
            imageData: imageData,
            imageWidth: width,
            imageHeight: height
        )
    }

    /// Send a single-frame localization request with raw image data
    /// - Parameters:
    ///   - imageData: JPEG image data
    ///   - imageWidth: Image width in pixels
    ///   - imageHeight: Image height in pixels
    /// - Returns: LocalizationResult on success
    func sendLocalizationRequest(
        imageData: Data,
        imageWidth: Int,
        imageHeight: Int
    ) async throws -> LocalizationResult {
        // Get auth token
        let token = try await authManager.getToken()

        // Build multipart request
        let boundary = UUID().uuidString
        let body = buildMultipartBody(
            imageData: imageData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            boundary: boundary
        )

        guard let url = URL(string: LocalizationConfig.queryURL) else {
            throw LocalizationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Execute with retry logic
        return try await executeWithRetry(request: request)
    }

    // MARK: - Private Methods

    private func executeWithRetry(request: URLRequest) async throws -> LocalizationResult {
        var lastError: Error = LocalizationError.unknown
        var delay = initialRetryDelay

        for attempt in 0..<maxRetries {
            do {
                logger.debug("Attempt \(attempt + 1)/\(self.maxRetries)")
                return try await executeRequest(request)
            } catch let error as LocalizationError {
                lastError = error

                // Check if error is retryable
                if case .httpError(let statusCode) = error, retryableCodes.contains(statusCode) {
                    logger.warning("Request failed with retryable code \(statusCode), retrying...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2  // Exponential backoff
                    continue
                }

                // Non-retryable error, throw immediately
                throw error
            } catch {
                lastError = error

                // Network errors are retryable
                if (error as NSError).domain == NSURLErrorDomain {
                    logger.warning("Network error, retrying: \(error.localizedDescription)")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2
                    continue
                }

                throw error
            }
        }

        throw lastError
    }

    private func executeRequest(_ request: URLRequest) async throws -> LocalizationResult {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalizationError.invalidResponse
        }

        logger.debug("Response code: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            logger.error("Localization failed: \(httpResponse.statusCode) - \(body)")
            throw LocalizationError.httpError(statusCode: httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(LocalizationResult.self, from: data)

        if result.poseFound, let position = result.posePosition {
            logger.debug("Localized: \(position.description), confidence: \(String(format: "%.0f", (result.confidence ?? 0) * 100))%")
        } else {
            logger.debug("Localization: pose not found")
        }

        return result
    }

    private func buildMultipartBody(
        imageData: Data,
        imageWidth: Int,
        imageHeight: Int,
        boundary: String
    ) -> Data {
        var body = Data()
        let config = LocalizationConfig.shared
        let intrinsics = calculateIntrinsics(width: imageWidth, height: imageHeight)

        // Helper function to add form field
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        // Camera intrinsics
        addField("isRightHanded", "false")
        addField("fx", String(format: "%.2f", intrinsics.fx))
        addField("fy", String(format: "%.2f", intrinsics.fy))
        addField("px", String(format: "%.2f", intrinsics.px))
        addField("py", String(format: "%.2f", intrinsics.py))
        addField("width", "\(imageWidth)")
        addField("height", "\(imageHeight)")

        // Map codes
        if !config.mapCode.isEmpty {
            addField("mapCode", config.mapCode)
        }
        if !config.mapSetCode.isEmpty {
            addField("mapSetCode", config.mapSetCode)
        }

        // Image file
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"queryImage\"; filename=\"frame.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n")

        // End boundary
        body.append("--\(boundary)--\r\n")

        return body
    }

    private func calculateIntrinsics(width: Int, height: Int) -> CameraIntrinsics {
        let config = LocalizationConfig.shared
        let baseWidth = RayBanMetaIntrinsics.width
        let baseHeight = RayBanMetaIntrinsics.height
        let baseFx = config.focalLengthX
        let baseFy = config.focalLengthY

        // If dimensions match base, use configured intrinsics directly
        if width == baseWidth && height == baseHeight {
            return config.intrinsics
        }

        // Calculate scale factor
        let baseAspect = Float(baseWidth) / Float(baseHeight)
        let imageAspect = Float(width) / Float(height)

        let scale: Float
        let px: Float
        let py: Float

        if abs(baseAspect - imageAspect) < 0.05 {
            // Similar aspect ratio - simple scaling
            scale = Float(width) / Float(baseWidth)
            px = RayBanMetaIntrinsics.px * scale
            py = RayBanMetaIntrinsics.py * scale
        } else {
            // Different aspect ratio - use uniform scale and center principal point
            scale = min(
                Float(width) / Float(baseWidth),
                Float(height) / Float(baseHeight)
            )
            px = Float(width) / 2
            py = Float(height) / 2
        }

        return CameraIntrinsics(
            width: width,
            height: height,
            fx: baseFx * scale,
            fy: baseFy * scale,
            px: px,
            py: py
        )
    }
}

// MARK: - Errors

enum LocalizationError: LocalizedError {
    case imageConversionFailed
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case unknown

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to JPEG format."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .httpError(let statusCode):
            return "Request failed with status code: \(statusCode)"
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
