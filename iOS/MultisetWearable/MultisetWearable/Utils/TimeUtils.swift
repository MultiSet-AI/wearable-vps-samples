/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

//
// TimeUtils.swift
//
// Utility for managing streaming time limits in the MultiSet Wearable app.
//

import Foundation
import SwiftUI

enum StreamTimeLimit: String, CaseIterable {
  case oneMinute = "1min"
  case fiveMinutes = "5min"
  case tenMinutes = "10min"
  case fifteenMinutes = "15min"
  case noLimit = "noLimit"

  var displayText: String {
    switch self {
    case .oneMinute:
      return "1m"
    case .fiveMinutes:
      return "5m"
    case .tenMinutes:
      return "10m"
    case .fifteenMinutes:
      return "15m"
    case .noLimit:
      return "No limit"
    }
  }

  var durationInSeconds: TimeInterval? {
    switch self {
    case .oneMinute:
      return 60
    case .fiveMinutes:
      return 300
    case .tenMinutes:
      return 600
    case .fifteenMinutes:
      return 900
    case .noLimit:
      return nil
    }
  }

  var isTimeLimited: Bool {
    switch self {
    case .noLimit:
      return false
    default:
      return true
    }
  }

  var next: StreamTimeLimit {
    switch self {
    case .oneMinute:
      return .fiveMinutes
    case .fiveMinutes:
      return .tenMinutes
    case .tenMinutes:
      return .fifteenMinutes
    case .fifteenMinutes:
      return .noLimit
    case .noLimit:
      return .oneMinute
    }
  }
}

extension TimeInterval {
  var formattedCountdown: String {
    let minutes = Int(self) / 60
    let seconds = Int(self) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
