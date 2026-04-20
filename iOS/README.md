# MultiSet VPS for Wearables

A sample iOS application demonstrating Visual Positioning System (VPS) integration with Meta Ray-Ban Smart Glasses. This app showcases localization, turn-by-turn navigation, and multiplayer pose sharing using the MultiSet VPS API and the Meta Wearables Device Access Toolkit (DAT SDK).

## Features

- **Smart Glasses Pairing**: Connect to Meta Ray-Ban Smart Glasses via Bluetooth
- **Live Video Streaming**: Real-time camera feed from the glasses
- **VPS Localization**: Capture images and get precise 6-DOF position and orientation
- **Navigation**: Turn-by-turn audio guidance to Points of Interest (POIs)
- **Multiplayer Demo**: Act as a client that joins a host running the MultiSet iOS SDK and streams its localized pose for real-time shared-space experiences
- **Audio Feedback**: Navigation instructions played through the glasses speakers
- **Optimized Streaming & Localization**: Session pre-warming, on-device image downscaling, video-frame fast path, and confidence-gated retries for low end-to-end latency

## Prerequisites

- iOS 17.0+
- Xcode 15.0+
- Swift 5.0+
- Meta Ray-Ban Smart Glasses (with the latest firmware)
- Meta AI App with Developer Mode enabled
- Meta Wearables DAT SDK 0.6.0 (resolved automatically via Swift Package Manager)
- MultiSet VPS API credentials (Client ID and Client Secret)
- A mapped environment with navigation data
- (Multiplayer only) A second device running the MultiSet iOS SDK multiplayer host, on the same local network as the iPhone running this app

---

## Getting Started

### 1. Clone and Open Project

```bash
git clone <repository-url>
cd wearable-vps-samples/iOS/MultisetWearable
open MultisetWearable.xcodeproj
```

### 2. Configure API Credentials

Get your credentials from the MultiSet Developer Portal: https://developer.multiset.ai/credentials

There are two ways to supply credentials. Choose the one that fits your workflow:

---

#### Option A — Hardcode defaults in Swift (quick local testing)

Edit `MultisetWearable/Services/LocalizationConfig.swift` and fill in the defaults directly:

```swift
// MARK: - Hardcoded Credential Defaults
private static let defaultClientID     = "your_client_id_here"
private static let defaultClientSecret = "your_client_secret_here"

// MARK: - Enter Map/MapSet Code
private static let mapCode    = "MAP_XXXXXXXXXX"   // for single-map localization
private static let mapSetCode = ""                  // for multi-map; leave empty if using mapCode
```

> **Note**: Keep secrets out of source control. Use this option only for local testing.

---

#### Option B — Info.plist + xcconfig (recommended for shared / production builds)

1. Add your build variables to an `.xcconfig` file (or in Xcode → Build Settings → User-Defined):

   ```
   MULTISET_CLIENT_ID     = your_client_id_here
   MULTISET_CLIENT_SECRET = your_client_secret_here
   ```

2. The `Info.plist` already contains the `MultisetConfig` dictionary that reads these variables:

   ```xml
   <key>MultisetConfig</key>
   <dict>
       <key>ClientID</key>
       <string>$(MULTISET_CLIENT_ID)</string>
       <key>ClientSecret</key>
       <string>$(MULTISET_CLIENT_SECRET)</string>
   </dict>
   ```

   The app resolves `ClientID` / `ClientSecret` from `Info.plist` at runtime. If the keys are absent or unresolved, it falls back to the hardcoded defaults in Option A.

---

#### Setting Map Code at Runtime (alternative to hardcoding)

`mapCode` and `mapSetCode` are persisted in **UserDefaults** and can also be set without recompiling:

- Open the **Settings screen** (gear icon) inside the app and enter your Map Code there, **or**
- Set them programmatically: `LocalizationConfig.shared.mapCode = "MAP_XXXXXXXXXX"`

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

The app sends a multipart/form-data request with the following fields. The examples shown are the values produced after the on-device downscale described in [Performance Optimizations](#performance-optimizations):

| Field | Description | Example |
|-------|-------------|---------|
| `queryImage` | JPEG image from glasses camera (downscaled before upload) | Binary data |
| `width` | Image width in pixels | `540` |
| `height` | Image height in pixels | `720` |
| `fx` | Focal length X (pixels) | `422.25` |
| `fy` | Focal length Y (pixels) | `422.9` |
| `px` | Principal point X | `270.35` |
| `py` | Principal point Y | `363.75` |
| `mapCode` | Target map identifier | `MAP_XXXXXXXXXX` |
| `mapSetCode` | Map set identifier (optional) | `MAPSET_XXX` |
| `isRightHanded` | Coordinate system flag (`false` for Unity/left-handed, `true` for ARKit/right-handed) | `false` |

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

The app uses calibrated camera intrinsics for Ray-Ban Meta glasses. Three resolution presets are available, each with its own set of intrinsics. The localization API caps input images at 1280 px on the longest side, so the full-capture frame is downscaled before upload — the app picks the right set of intrinsics automatically.

**Localization upload (540 × 720)** — full capture scaled 0.5× for the VPS API

| Parameter | Value | Description |
|-----------|-------|-------------|
| Resolution | 540 × 720 | Half capture resolution used in the upload payload |
| Focal Length (fx) | 422.25 px | Scaled from calibrated fx (× 0.5) |
| Focal Length (fy) | 422.9 px | Scaled from calibrated fy (× 0.5) |
| Principal Point (px) | 270.35 px | Scaled principal point X |
| Principal Point (py) | 363.75 px | Scaled principal point Y |

**Medium streaming resolution (504 × 896)** — used for the live video feed and the fast-path navigation re-localization

| Parameter | Value | Description |
|-----------|-------|-------------|
| Resolution | 504 × 896 | Center-cropped 9:16 streaming resolution |
| Focal Length (fx) | 525.5 px | Scaled from calibrated fx |
| Focal Length (fy) | 526.3 px | Scaled from calibrated fy |
| Principal Point (px) | 252.0 px | Center of 504 px width |
| Principal Point (py) | 448.0 px | Center of 896 px height |

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

## Multiplayer Demo

The Multiplayer Demo lets a user wearing Ray-Ban Meta glasses join a shared-space session hosted on another device running the **MultiSet iOS SDK**. The wearable app acts as a **client**: it streams video from the glasses, localizes against the same map the host is using, and broadcasts its 6-DOF pose to the host so the host can render this player's position (and optionally an avatar) inside a live AR scene.

### How It Works

- **Transport**: Apple Multipeer Connectivity on the local network. The service type is `multiset-sdk`, which matches the MultiSet iOS SDK host. No internet connection is required between the two devices once connected.
- **Discovery**: The wearable app browses for peers advertising the `multiset-sdk` service and auto-joins the first host that accepts the invitation.
- **Localization**: The client localizes once when the session starts, then periodically re-localizes (roughly once per second) to keep the pose fresh. Re-localization uses the fast video-frame path, so it doesn't incur a Bluetooth photo round-trip.
- **Pose streaming**: While localized, the app sends pose updates to the host at ~20 Hz over unreliable datagrams (prioritizes freshness over delivery guarantees). Player info (name and a randomly assigned vibrant color) is sent reliably.
- **Coordinate system**: Multiplayer uses the same left-handed coordinate system as the Unity-based host by default, so poses drop directly into the host's world without conversion. The request still sets `isRightHanded=false`.
- **Audio**: Re-localization runs silently during multiplayer so the host experience isn't interrupted by success/failure chimes on the glasses.

### Running the Demo

1. Start the MultiSet iOS SDK multiplayer host on a nearby device and load the same map used by this app (same `mapCode`).
2. Make sure both devices are on the same Wi-Fi network and that Local Network permission is granted to this app (iOS prompts the first time).
3. Launch MultiSet Wearable, pair the glasses, and pick **"Multiplayer Demo"** from the feature selection screen.
4. Enter a display name (or accept the device-name default) and tap **Join Session**. The app browses for the host and connects automatically.
5. Tap **Start Streaming**. After the first successful localization, the glasses' pose starts streaming to the host and your avatar appears in the host scene.
6. Leave the session at any time — the app tears down the multipeer session and stops the stream cleanly.

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
