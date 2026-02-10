/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// Configuration for the Multiset Localization SDK
final class LocalizationConfig {

    // MARK: - Singleton
    static let shared = LocalizationConfig()

    // MARK: - API Endpoints
    static let authURL = "https://api.multiset.ai/v1/m2m/token"
    static let queryURL = "https://api.multiset.ai/v1/vps/map/query-form"

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let mapCode = "multiset_map_code"
        static let mapSetCode = "multiset_map_set_code"
        static let intrinsicsPreset = "multiset_intrinsics_preset"
        static let customFocalLength = "multiset_custom_focal_length"
    }

    // MARK: - Default Credentials
    private static let defaultClientID = ""
    private static let defaultClientSecret = ""
    
    //MARK: - enter either MapCode or MapSetCode
    private static let defaultMapCode = ""
    private static let defaultMapSetCode = ""

    // MARK: - Credentials (from Info.plist build variables or defaults)
    var clientID: String {
        if let config = Bundle.main.object(forInfoDictionaryKey: "MultisetConfig") as? [String: Any],
           let clientID = config["ClientID"] as? String,
           !clientID.isEmpty,
           !clientID.hasPrefix("$(") {
            return clientID
        }
        return Self.defaultClientID
    }

    var clientSecret: String {
        if let config = Bundle.main.object(forInfoDictionaryKey: "MultisetConfig") as? [String: Any],
           let clientSecret = config["ClientSecret"] as? String,
           !clientSecret.isEmpty,
           !clientSecret.hasPrefix("$(") {
            return clientSecret
        }
        return Self.defaultClientSecret
    }

    // MARK: - Map Configuration (stored in UserDefaults)
    var mapCode: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Keys.mapCode)
            if let stored = stored, !stored.isEmpty {
                return stored
            }
            return Self.defaultMapCode
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.mapCode) }
    }

    var mapSetCode: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Keys.mapSetCode)
            if let stored = stored, !stored.isEmpty {
                return stored
            }
            return Self.defaultMapSetCode
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.mapSetCode) }
    }

    // MARK: - Camera Intrinsics
    var currentPreset: IntrinsicsPreset {
        get {
            let rawValue = UserDefaults.standard.string(forKey: Keys.intrinsicsPreset) ?? IntrinsicsPreset.calibrated.rawValue
            return IntrinsicsPreset(rawValue: rawValue) ?? .calibrated
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.intrinsicsPreset)
        }
    }

    var customFocalLength: Float {
        get { UserDefaults.standard.float(forKey: Keys.customFocalLength).nonZeroOr(844.5) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.customFocalLength) }
    }

    // MARK: - Computed Intrinsics
    var focalLengthX: Float {
        if currentPreset == .custom {
            return customFocalLength
        }
        if currentPreset == .calibrated {
            return RayBanMetaIntrinsics.calibratedFx
        }
        return currentPreset.focalLength
    }

    var focalLengthY: Float {
        if currentPreset == .custom {
            return customFocalLength
        }
        if currentPreset == .calibrated {
            return RayBanMetaIntrinsics.calibratedFy
        }
        return currentPreset.focalLength
    }

    var intrinsics: CameraIntrinsics {
        CameraIntrinsics(
            width: RayBanMetaIntrinsics.width,
            height: RayBanMetaIntrinsics.height,
            fx: focalLengthX,
            fy: focalLengthY,
            px: RayBanMetaIntrinsics.px,
            py: RayBanMetaIntrinsics.py
        )
    }

    // MARK: - Validation
    var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty && (!mapCode.isEmpty || !mapSetCode.isEmpty)
    }

    var hasCredentials: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    private init() {}
}

// MARK: - Camera Intrinsics Model
struct CameraIntrinsics {
    let width: Int
    let height: Int
    let fx: Float
    let fy: Float
    let px: Float
    let py: Float
    let isRightHanded: Bool = false
}

// MARK: - Ray-Ban Meta Base Intrinsics
// Calibrated from 3K video (1632x2176) and scaled to capture resolution (1080x1440)
// Calibration data: fx=1276.095, fy=1278.037, cx=817.052, cy=1099.243 @ 1632x2176
// Scale factor: 1080/1632 = 0.6618
enum RayBanMetaIntrinsics {
    static let width = 1080
    static let height = 1440
    // Calibrated principal point (slightly off-center, as is typical)
    static let px: Float = 540.7  // 817.052 * 0.6618
    static let py: Float = 727.5  // 1099.243 * 0.6618
    // Calibrated focal lengths
    static let calibratedFx: Float = 844.5  // 1276.095 * 0.6618
    static let calibratedFy: Float = 845.8  // 1278.037 * 0.6618
}

// MARK: - Intrinsics Presets
// Focal lengths calculated for 1080px width: fx = width / (2 * tan(FOV/2))
enum IntrinsicsPreset: String, CaseIterable, Identifiable {
    case calibrated = "calibrated"
    case wide100 = "wide_100"
    case wide90 = "wide_90"
    case moderate80 = "moderate_80"
    case moderate70 = "moderate_70"
    case default64 = "default_64"
    case narrow56 = "narrow_56"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calibrated: return "Calibrated (Recommended)"
        case .wide100: return "100° (Wide)"
        case .wide90: return "90°"
        case .moderate80: return "80°"
        case .moderate70: return "70°"
        case .default64: return "64°"
        case .narrow56: return "56° (Narrow)"
        case .custom: return "Custom"
        }
    }

    // Focal lengths for 1080px width
    var focalLength: Float {
        switch self {
        case .calibrated: return RayBanMetaIntrinsics.calibratedFx  // 844.5
        case .wide100: return 454.0   // 1080 / (2 * tan(50°))
        case .wide90: return 540.0    // 1080 / (2 * tan(45°))
        case .moderate80: return 643.0 // 1080 / (2 * tan(40°))
        case .moderate70: return 771.0 // 1080 / (2 * tan(35°))
        case .default64: return 864.0  // 1080 / (2 * tan(32°))
        case .narrow56: return 1017.0  // 1080 / (2 * tan(28°))
        case .custom: return 0  // Uses customFocalLength
        }
    }

    var description: String {
        switch self {
        case .calibrated: return "Calibrated from 3K video (~65° FOV)"
        case .wide100: return "Calculated for ~100° horizontal FOV"
        case .wide90: return "Calculated for ~90° horizontal FOV"
        case .moderate80: return "Calculated for ~80° horizontal FOV"
        case .moderate70: return "Calculated for ~70° horizontal FOV"
        case .default64: return "Calculated for ~64° horizontal FOV"
        case .narrow56: return "Calculated for ~56° horizontal FOV"
        case .custom: return "User-defined focal length"
        }
    }
}

// MARK: - Float Extension
private extension Float {
    func nonZeroOr(_ defaultValue: Float) -> Float {
        self == 0 ? defaultValue : self
    }
}
