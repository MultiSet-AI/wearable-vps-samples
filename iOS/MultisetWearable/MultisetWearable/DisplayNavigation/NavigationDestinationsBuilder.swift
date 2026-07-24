/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATDisplay

/// Lightweight, Sendable POI descriptor for the glasses destination list.
struct NavDestination: Sendable {
  let id: Int
  let name: String
  let type: String
  let distance: Float?   // straight-line meters from the user, if localized
}

enum NavigationDestinationsBuilder {

  // MARK: - Welcome
  static func makeWelcome(
    mapName: String?,
    failedAttempt: Bool,
    logoURI: String? = nil,
    onLocalize: @escaping @Sendable () -> Void,
    onBrowseDestinations: (@Sendable () -> Void)? = nil
  ) -> FlexBox {
    FlexBox(direction: .column, spacing: 10) {
      FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
        if let logoURI {
          Image(uri: logoURI, sizePreset: .icon, cornerRadius: .medium)
        } else {
          Icon(name: .compassNorthUpRed, style: .filled)
        }
        FlexBox(direction: .column, spacing: 2) {
          Text("Welcome to MultiSet", style: .meta, color: .secondary)
          Text("Indoor Navigation", style: .heading)
          if let mapName, !mapName.isEmpty {
            Text("Map: \(mapName)", style: .meta, color: .secondary)
          }
        }
        .flexGrow(1)
      }
      .padding(16)
      .background(.card)

      if failedAttempt {
        Text("Couldn't find your position — face a distinctive area and try again.", style: .body)
      } else {
        Text("Find your position, pick a destination, and follow the arrows.", style: .body)
      }

      // Buttons must live in a centered row FlexBox.
      FlexBox(direction: .column, spacing: 4, crossAlignment: .center) {
        FlexBox(direction: .row, spacing: 10, alignment: .center, crossAlignment: .center) {
          Button(label: "Localize", style: .primary, iconName: .fourCornerFrame, onClick: onLocalize)
          if let onBrowseDestinations {
            Button(label: "Destinations", style: .secondary, iconName: .threeHorizontalLines, onClick: onBrowseDestinations)
          }
        }
        Text("Localize to see distances to POIs", style: .meta, color: .secondary)
      }
    }
  }

  // MARK: - Browse (pre-localization)

  /// Destination browser available before any position fix: every destination
  /// in the map, names only (distances need a pose). Tapping a row commits to
  /// that destination — the caller localizes first, then opens its confirm screen.
  static func makeBrowseList(
    _ destinations: [NavDestination],
    onSelect: @escaping @Sendable (Int) -> Void,
    onLocalize: @escaping @Sendable () -> Void,
    onBack: @escaping @Sendable () -> Void
  ) -> FlexBox {
    FlexBox(direction: .column, spacing: 8) {
      FlexBox(direction: .row, spacing: 10, crossAlignment: .center) {
        FlexBox(direction: .column, spacing: 2) {
          Text("Destinations", style: .heading)
          Text("Tap one to localize & go", style: .meta, color: .secondary)
        }
        .flexGrow(1)
        if destinations.count > 1 {
          Text("\(destinations.count) places", style: .meta, color: .secondary)
        }
      }

      if destinations.isEmpty {
        Text("No destinations in this map", style: .body, color: .secondary)
      }

      for destination in destinations {
        FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
          Icon(name: icon(for: destination.type), style: .filled)
          FlexBox(direction: .column, spacing: 2) {
            Text(destination.name, style: .body)
          }
          .flexGrow(1)
        }
        .padding(12)
        .background(.card)
        .onTap { onSelect(destination.id) }
      }

      FlexBox(direction: .row, spacing: 10, alignment: .center, crossAlignment: .center) {
        Button(label: "Localize", style: .primary, iconName: .fourCornerFrame, onClick: onLocalize)
        Button(label: "Back", style: .secondary, iconName: .x, onClick: onBack)
      }
    }
  }

  // MARK: - Localizing animation

  /// Number of distinct animation frames (cycled by the caller's timer).
  static let localizingFrameCount = 4

  /// One frame of the "scanning surroundings" animation. The Display kit has no
  /// intrinsic animation, so the caller re-sends successive frames (~0.8 s).
  static func makeLocalizing(frame: Int) -> FlexBox {
    let step = ((frame % localizingFrameCount) + localizingFrameCount) % localizingFrameCount
    let dots = String(repeating: ".", count: step + 1)
    return FlexBox(direction: .column, spacing: 12, alignment: .center, crossAlignment: .center) {
      FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
        Icon(name: step % 2 == 0 ? .fourArcsUpGrayscale : .fourArcsUpFilled, style: .filled)
        Text("Localizing\(dots)", style: .heading)
      }
      .padding(20)
      .background(.card)

      Text("Hold still and look around the space", style: .meta, color: .secondary)
    }
  }

  // MARK: - Destination list

  /// Builds the destination list (a single root `FlexBox`): ALL destinations in
  /// one vertical column, nearest-first with type glyphs. Content taller than
  /// the display scrolls with a temple swipe — no paging.
  /// - onSelect: fired with the chosen POI id when a row is tapped.
  /// - onRelocalize: optional manual re-fix control.
  static func makeList(
    _ destinations: [NavDestination],
    onSelect: @escaping @Sendable (Int) -> Void,
    onRelocalize: (@Sendable () -> Void)? = nil
  ) -> FlexBox {
    FlexBox(direction: .column, spacing: 8) {
      FlexBox(direction: .row, spacing: 10, crossAlignment: .center) {
        FlexBox(direction: .column) {
          Text("Where to?", style: .heading)
        }
        .flexGrow(1)
        if destinations.count > 1 {
          Text("\(destinations.count) places", style: .meta, color: .secondary)
        }
      }

      if destinations.isEmpty {
        Text("No destinations in this map", style: .body, color: .secondary)
      }

      for destination in destinations {
        FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
          Icon(name: icon(for: destination.type), style: .filled)
          FlexBox(direction: .column, spacing: 2) {
            Text(destination.name, style: .body)
            if let distance = destination.distance {
              Text(NavigationHUDBuilder.distanceText(distance), style: .meta, color: .secondary)
            }
          }
          .flexGrow(1)
        }
        .padding(12)
        .background(.card)
        .onTap { onSelect(destination.id) }
      }

      if let onRelocalize {
        FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
          Button(label: "Re-localize", style: .secondary, iconName: .fourCornerFrame, onClick: onRelocalize)
        }
      }
    }
  }

  // MARK: - Confirm

  /// Confirmation card for a tapped destination: name, distance + walk-time
  /// estimate, optional route-preview map, then Navigate or Cancel.
  static func makeConfirm(
    _ destination: NavDestination,
    routePreviewURI: String? = nil,
    onNavigate: @escaping @Sendable () -> Void,
    onCancel: @escaping @Sendable () -> Void
  ) -> FlexBox {
    FlexBox(direction: .column, spacing: 8) {
      FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
        Icon(name: icon(for: destination.type), style: .filled)
        FlexBox(direction: .column, spacing: 2) {
          Text(destination.name, style: .heading)
          if let distance = destination.distance {
            Text("\(NavigationHUDBuilder.distanceText(distance)) · \(NavigationHUDBuilder.walkTimeText(distance)) walk",
                 style: .meta, color: .secondary)
          }
        }
        .flexGrow(1)
      }
      .padding(16)
      .background(.card)

      // Route preview — a one-off image send.
      if let routePreviewURI {
        Image(uri: routePreviewURI, sizePreset: .fill, cornerRadius: .medium)
      }

      FlexBox(direction: .row, spacing: 10, alignment: .center, crossAlignment: .center) {
        Button(label: "Navigate", style: .primary, iconName: .triangleRightCircle, onClick: onNavigate)
        Button(label: "Cancel", style: .secondary, iconName: .x, onClick: onCancel)
      }
    }
  }

  // MARK: - Arrived

  /// The arrival screen: destination name, trip stats, and the next decision —
  /// another stop, or end the journey (glasses-side exit).
  static func makeArrived(
    destinationName: String,
    statsLine: String?,
    onNextStop: @escaping @Sendable () -> Void,
    onEnd: @escaping @Sendable () -> Void
  ) -> FlexBox {
    FlexBox(direction: .column, spacing: 10) {
      FlexBox(direction: .row, spacing: 14, crossAlignment: .center) {
        Icon(name: .checkmarkCircle, style: .filled)
        FlexBox(direction: .column, spacing: 2) {
          Text(destinationName, style: .heading)
          Text("You're here", style: .body)
          if let statsLine {
            Text(statsLine, style: .meta, color: .secondary)
          }
        }
        .flexGrow(1)
      }
      .padding(16)
      .background(.card)

      FlexBox(direction: .row, spacing: 10, alignment: .center, crossAlignment: .center) {
        Button(label: "Next stop", style: .primary, iconName: .triangleRightCircle, onClick: onNextStop)
        Button(label: "End", style: .secondary, iconName: .x, onClick: onEnd)
      }
    }
  }

  // MARK: - Icon mapping

  /// Maps a POI type to a HUD icon, with a safe default.
  static func icon(for type: String) -> IconName {
    switch type.lowercased() {
    case "room": return .house
    case "foodarea": return .forkKnife
    case "information": return .iCircle
    default: return .circleHandle
    }
  }
}
