/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATDisplay

/// Immutable description of the current navigation state, captured on the main
/// actor and handed to the HUD builder.
struct NavHUDSnapshot: Sendable {
  var instruction: NavigationInstruction?
  var remainingDistance: Float
  /// Distance to the next maneuver target — the HUD's big number.
  var distanceToManeuver: Float?
  var destinationName: String?
  var waypointIndex: Int
  var totalWaypoints: Int

  // Geometry for the route preview (all optional — HUD still works without it).
  var userPosition: NavPosition?
  var userRotation: Rotation?
  var activePath: [Int]?
  /// Resolved route polyline (waypoints + destination) for the card's preview.
  var routePolyline: [NavPosition]? = nil
  /// Fraction of the route completed (0…1) for the progress bar.
  var progressFraction: Float = 0

  var isArrived: Bool { instruction == .destinationReached }
}

enum NavigationHUDBuilder {

  static func makeHUD(
    _ snapshot: NavHUDSnapshot,
    onStop: (@Sendable () -> Void)? = nil
  ) -> FlexBox {
    FlexBox(direction: .column, spacing: 10) {
      // --- Primary guidance card: arrow + distance + instruction text ---
      FlexBox(direction: .row, spacing: 14, crossAlignment: .center) {
        FlexBox(direction: .column, alignment: .center, crossAlignment: .center) {
          Icon(name: icon(for: snapshot.instruction), style: .filled)
        }

        FlexBox(direction: .column, spacing: 2) {
          Text(primaryLine(snapshot), style: .heading)
          if let secondary = secondaryLine(snapshot) {
            Text(secondary, style: .meta, color: .secondary)
          }
        }
        .flexGrow(1)
      }
      .padding(20)
      .background(.card)

      // --- Progress footer + stop control ---
      if snapshot.totalWaypoints > 0 && !snapshot.isArrived {
        FlexBox(direction: .row, spacing: 10, crossAlignment: .center) {
          FlexBox(direction: .column) {
            Text(progressLine(snapshot), style: .meta, color: .secondary)
          }
          .flexGrow(1)
          if let onStop {
            Button(label: "Stop", style: .secondary, iconName: .x, onClick: onStop)
          }
        }
      }
    }
  }

  /// The calm degraded-guidance variant: same frame, no map, behavioral prompt
  /// instead of an error. Self-heals back to the normal HUD without user action.
  static func makeReacquiring(_ snapshot: NavHUDSnapshot, onStop: (@Sendable () -> Void)? = nil) -> FlexBox {
    FlexBox(direction: .column, spacing: 8) {
      FlexBox(direction: .row, spacing: 14, crossAlignment: .center) {
        Icon(name: .circle8RaysLarge, style: .filled)
        FlexBox(direction: .column, spacing: 2) {
          Text("One moment", style: .heading)
          Text("Reacquiring position — glance at a sign or shelf nearby", style: .meta, color: .secondary)
        }
        .flexGrow(1)
      }
      .padding(16)
      .background(.card)

      FlexBox(direction: .row, spacing: 10, crossAlignment: .center) {
        FlexBox(direction: .column) {
          Text("holding…", style: .meta, color: .secondary)
        }
        .flexGrow(1)
        if let onStop {
          Button(label: "Stop", style: .secondary, iconName: .x, onClick: onStop)
        }
      }
    }
  }

  // MARK: - Content

  /// Big line: remaining distance, or arrival text.
  static func primaryLine(_ s: NavHUDSnapshot) -> String {
    if s.isArrived { return "Arrived" }
    return distanceText(s.remainingDistance)
  }

  /// Secondary line: the maneuver description and destination.
  static func secondaryLine(_ s: NavHUDSnapshot) -> String? {
    if s.isArrived {
      return s.destinationName
    }
    let maneuver = s.instruction?.description
    if let dest = s.destinationName {
      if let maneuver { return "\(maneuver) → \(dest)" }
      return "To \(dest)"
    }
    return maneuver
  }

  static func progressLine(_ s: NavHUDSnapshot) -> String {
    let current = min(s.waypointIndex + 1, max(s.totalWaypoints, 1))
    return "Waypoint \(current)/\(s.totalWaypoints)"
  }

  // MARK: - Icon mapping

  /// Maps a navigation maneuver to the closest MWDATDisplay HUD icon.
  static func icon(for instruction: NavigationInstruction?) -> IconName {
    switch instruction {
    case .moveForward, .navigationStarted, .none:
      return .caretUp
    case .turnLeft:
      return .arrowLeft
    case .turnRight:
      return .arrowRight
    case .slightLeft:
      return .caretLeft
    case .slightRight:
      return .caretRight
    case .turnAround:
      return .arrowULeft
    case .destinationReached:
      return .checkmarkCircle
    case .recalculating:
      return .twoArrowsClockwise
    }
  }

  // MARK: - Formatting

  /// Human-readable distance, meters with a km rollover.
  static func distanceText(_ meters: Float) -> String {
    let m = max(0, meters)
    if m >= 1000 { return String(format: "%.1f km", m / 1000) }
    if m >= 10 { return "\(Int(m.rounded())) m" }
    return String(format: "%.1f m", m)
  }

  /// Walk-time estimate at a comfortable indoor pace (~1.3 m/s).
  static func walkTimeText(_ meters: Float) -> String {
    let seconds = max(0, meters) / 1.3
    if seconds < 45 { return "under a min" }
    return "~\(Int((seconds / 60).rounded(.up))) min"
  }
}
