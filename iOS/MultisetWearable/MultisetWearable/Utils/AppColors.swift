/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// App color palette matching the Android MetaCamera design
enum AppColors {
    // MARK: - Background Colors
    static let primaryBackground = Color(hex: "0D1117")
    static let cardBackground = Color(hex: "161B22")
    static let secondaryBackground = Color(hex: "1C1C1E")

    // MARK: - Accent Colors
    static let accentBlue = Color(hex: "58A6FF")
    static let accentGreen = Color(hex: "3FB950")
    static let accentPurple = Color(hex: "8B5CF6")
    static let accentRed = Color(hex: "FF3B30")

    // MARK: - Text Colors
    static let textPrimary = Color(hex: "F0F6FC")
    static let textSecondary = Color(hex: "8B949E")

    // MARK: - Action Colors
    static let green = Color(hex: "61BC63")
    static let red = Color(hex: "FF3B30")
    static let yellow = Color(hex: "FFCC00")
    static let deepBlue = Color(hex: "0064E0")

    // MARK: - Gradients
    static let backgroundGradient = LinearGradient(
        colors: [Color(hex: "0D1117"), Color(hex: "161B22")],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
