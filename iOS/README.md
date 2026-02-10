# MultiSet VPS for Wearables

A sample iOS application demonstrating Visual Positioning System (VPS) integration with Meta Ray-Ban Smart Glasses. This app showcases localization and turn-by-turn navigation using the MultiSet VPS API and Meta Wearables Device Access Toolkit (DAT SDK).

## Features

- **Smart Glasses Pairing**: Connect to Meta Ray-Ban Smart Glasses via Bluetooth
- **Live Video Streaming**: Real-time camera feed from the glasses
- **VPS Localization**: Capture images and get precise 6DOF position and orientation
- **Navigation**: Turn-by-turn audio guidance to Points of Interest (POIs)
- **Audio Feedback**: Navigation instructions played through the glasses speakers

## Prerequisites

- iOS 17.0+
- Xcode 15.0+
- Swift 5.0+
- Meta Ray-Ban Smart Glasses
- Meta AI App with Developer Mode enabled
- MultiSet VPS API credentials (Client ID and Client Secret)
- A mapped environment with navigation data

---

## Getting Started

### 1. Clone and Open Project

```bash
git clone <repository-url>
cd wearable-vps-samples/iOS/MultisetWearable
open MultisetWearable.xcodeproj
```

### 2. Configure API Credentials

**Important**: Configure your credentials before building the app.

Edit `MultisetWearable/Services/LocalizationConfig.swift` and fill in the configuration section:

```swift
// ╔════════════════════════════════════════════════════════════════════════════╗
// ║                    CONFIGURE YOUR CREDENTIALS HERE                          ║
// ╚════════════════════════════════════════════════════════════════════════════╝

/// Your MultiSet Client ID
static let clientId = "your_client_id_here"

/// Your MultiSet Client Secret
static let clientSecret = "your_client_secret_here"

/// Your Map Code for single-map localization (e.g., "MAP_XXXXXXXXXX")
static let mapCode = "MAP_XXXXXXXXXX"

/// Your Map Set Code for multi-map localization
/// Leave empty if using mapCode instead
static let mapSetCode = ""
```

Get your credentials from the MultiSet Developer Portal: https://developer.multiset.ai/credentials

### 3. Build and Run

```bash
xcodebuild -project MultisetWearable.xcodeproj -scheme MultisetWearable -sdk iphoneos build
```

Or in Xcode: `Cmd+B` (build), `Cmd+R` (run)

---

## Pairing Meta Ray-Ban Smart Glasses

### Prerequisites

1. Install the **Meta AI** app on your iPhone
2. Pair your Ray-Ban Meta glasses with the Meta AI app
3. Enable **Developer Mode** in Meta AI app settings

### Pairing Steps

1. Launch the MultiSet Wearable app
2. Ensure your glasses are powered on and connected to the Meta AI app
3. Tap **"Connect My Glasses"** button
4. The app will redirect to Meta AI for authorization
5. Grant camera permission when prompted
6. Once authorized, you'll return to the app with glasses connected

### Connection Status

The app displays connection status on the home screen:
- **Green indicator**: Glasses connected and ready
- **Red indicator**: Glasses not connected

---

## Video Streaming

### Starting a Stream

1. After glasses are paired, select **"Navigation Demo"** from the feature selection screen
2. The app automatically requests camera permission from your glasses
3. Once granted, tap **"Start Streaming"** to begin the live video feed

### Capturing Photos

During streaming, you can capture photos by:
1. Tapping the **capture (localization) button** on screen
2. The captured image will be used for localization

---

## VPS Localization

### How Localization Works

1. The app captures a photo from the glasses camera
2. The image is sent to the MultiSet VPS API with camera intrinsics
3. The API returns the camera's 6-DOF pose (position + orientation) in the mapped environment
4. Results include confidence score and position relative to the map origin

### Localization Request Payload

The app sends a multipart/form-data request with the following fields:

| Field | Description | Example |
|-------|-------------|---------|
| `queryImage` | JPEG image from glasses camera | Binary data |
| `width` | Image width in pixels | `1080` |
| `height` | Image height in pixels | `1440` |
| `fx` | Focal length X (pixels) | `844.5` |
| `fy` | Focal length Y (pixels) | `845.8` |
| `px` | Principal point X | `540.7` |
| `py` | Principal point Y | `727.5` |
| `mapCode` | Target map identifier | `MAP_XXXXXXXXXX` |
| `mapSetCode` | Map set identifier (optional) | `MAPSET_XXX` |
| `isRightHanded` | Coordinate system flag | `false` |

### Localization Response

```json
{
  "poseFound": true,
  "position": {
    "x": 2.34,
    "y": -0.99,
    "z": 1.56
  },
  "rotation": {
    "x": 0.0,
    "y": 0.707,
    "z": 0.0,
    "w": 0.707
  },
  "confidence": 0.87,
  "mapCodes": ["MAP_XXXXXXXXXX"]
}
```

### Camera Intrinsics

The app uses calibrated camera intrinsics for Ray-Ban Meta glasses:

| Parameter | Value | Description |
|-----------|-------|-------------|
| Resolution | 1080 x 1440 | Capture resolution |
| Focal Length (fx) | 844.5 px | Horizontal focal length |
| Focal Length (fy) | 845.8 px | Vertical focal length |
| Principal Point (px) | 540.7 px | Optical center X |
| Principal Point (py) | 727.5 px | Optical center Y |

---

## Navigation

### Navigation System Overview

The navigation system provides turn-by-turn audio guidance from your current position to a selected Point of Interest (POI). It uses:

1. **VPS Localization**: Continuous position updates during navigation
2. **Waypoint Graph**: Pre-computed navigation paths between locations
3. **A* Pathfinding**: Runtime path calculation when precomputed paths aren't available
4. **Audio Instructions**: Directional guidance played through the glasses

### Navigation Flow

```
User Localizes → Selects POI → Path Calculated → Navigation Starts
                                      ↓
           ← Position Updates ← Periodic Localization (200ms intervals)
                                      ↓
                        Turn-by-Turn Audio Instructions
                                      ↓
                          Arrival Detection → Done
```

### Starting Navigation

1. Tap **"Localize"** to get your current position
2. Wait for successful localization (green indicator)
3. Tap **"Select Destination"** to view available POIs
4. Select a POI from the list
5. Navigation begins with audio instructions

---

## Importing NavMesh Data from Unity

### Unity NavMeshExport Scene

The navigation system requires NavMesh data that includes POI and waypoint data exported from Unity. This data is generated using the **MultiSet Unity SDK's NavMeshExport Scene**.

- **MultiSet Unity SDK**: https://github.com/MultiSet-AI/multiset-unity-sdk
- **SDK Documentation**: https://docs.multiset.ai/quick-access/multiset-unity-sdk

### Data Structure Reference

#### POI (Point of Interest)

| Field | Type | Description |
|-------|------|-------------|
| `id` | Int | Unique identifier |
| `name` | String | Display name |
| `description` | String | Optional description |
| `type` | String | Category (Room, FoodArea, Exit, Information) |
| `position` | NavPosition | Position in map coordinates |
| `worldPosition` | NavPosition | Position in world coordinates |
| `nearestWaypointId` | Int | Closest waypoint for path calculation |
| `arrivalRadius` | Float | Distance threshold for arrival detection (meters) |

#### Waypoint

| Field | Type | Description |
|-------|------|-------------|
| `id` | Int | Unique identifier |
| `position` | NavPosition | Position in map coordinates |
| `connectedWaypoints` | [Int] | IDs of directly connected waypoints |

#### Precomputed Path

| Field | Type | Description |
|-------|------|-------------|
| `fromWaypointId` | Int | Starting waypoint |
| `toPoiId` | Int | Destination POI |
| `waypointPath` | [Int] | Ordered list of waypoint IDs |
| `totalDistance` | Float | Total path distance in meters |

### Importing Navigation Data into Xcode

1. **Export from Unity**:
   - Open your Unity project with MultiSet SDK
   - Use the NavMeshExport Scene to generate the JSON
   - Use NavMeshExportManager to Generate and export Navigation data.
   - A file: `{mapCode}_navigation_data.json` will be exported in the ExportedData folder.

2. **Add to Xcode Project**:
   - Locate the file in Finder
   - Drag and drop into `MultisetWearable/Resources/NavigationData/` folder in Xcode
   - Ensure "Copy items if needed" is checked
   - Select "MultisetWearable" target

3. **Configure Map Code**:
   - Open Settings in the app (gear icon)
   - Enter your Map Code (must match the filename)
   - The app will automatically load the navigation data

### Coordinate System

The app uses a **left-handed coordinate system** matching Unity's default:
- **X**: Right
- **Y**: Up
- **Z**: Forward

The VPS API is called with `isRightHanded=false` to ensure coordinates match the Unity-exported navigation data.

---

## License

Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. See LICENSE file for details.

For issues related to the Meta Wearables Device Access Toolkit, visit the [developer documentation](https://wearables.developer.meta.com/docs/develop/).
