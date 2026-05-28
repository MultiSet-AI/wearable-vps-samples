# MultiSet Wearable VPS (Android)

A sample Android application demonstrating Visual Positioning System (VPS) integration with Meta Ray-Ban Smart Glasses. This app showcases localization and turn-by-turn navigation using the MultiSet VPS API and the Meta Wearables Device Access Toolkit (DAT SDK). It is the Android counterpart of the iOS `CameraAccess` sample.

## Features

- **Smart Glasses Pairing**: Connect to Meta Ray-Ban Smart Glasses via the Meta AI app
- **Live Video Streaming**: Real-time camera feed from the glasses
- **VPS Localization**: Capture an image and get a precise 6-DoF position and orientation
- **Navigation**: Turn-by-turn audio guidance to Points of Interest (POIs) with a live 2D map
- **Audio Feedback**: Navigation/localization cues played through the glasses speakers

## Prerequisites

- Android Studio (Giraffe/Hedgehog or newer)
- JDK 17 (bundled with recent Android Studio)
- Android SDK: **minSdk 31** (Android 12), targetSdk 34, compileSdk 35
- Meta Ray-Ban Smart Glasses
- Meta AI app with **Developer Mode** enabled
- MultiSet VPS API credentials (Client ID and Client Secret)
- A GitHub Personal Access Token with `read:packages` (the MWDAT artifacts are served from GitHub Packages)
- A mapped environment with navigation data (for the Navigation feature)

---

## Getting Started

### 1. Clone and Open Project

```bash
git clone <repository-url>
cd MultisetWearable
```

Open the project in Android Studio and let Gradle sync.

### 2. Configure Credentials

The project uses **two** gitignored properties files at the project root (`Android/MultisetWearable/`). Both are required for a clean build.

#### a. `local.properties` — SDK path + GitHub token

```properties
sdk.dir=/path/to/Android/sdk

# GitHub Personal Access Token with read:packages scope.
# Required by settings.gradle.kts to resolve the com.meta.wearable:mwdat-* artifacts
# from GitHub Packages (https://maven.pkg.github.com/facebook/meta-wearables-dat-android).
# Alternatively, export GITHUB_TOKEN as an environment variable instead of using this file.
github_token=ghp_xxxxxxxxxxxxxxxxxxxx
```

> **Get a GitHub PAT:** GitHub → Settings → Developer settings → Personal access tokens (classic) → `read:packages` scope.

#### b. `multiset.properties` — MultiSet SDK credentials and map

This file is the **single source of truth** for all MultiSet SDK configuration. `app/build.gradle.kts` reads it via `getMultisetProperty(...)` and injects the values into `BuildConfig` at build time; `MainActivity` then passes them to `SDKConfig.initialize(...)` on app start.

```properties
# ============================================================
# MULTISET SDK CONFIGURATION
# Get your credentials at: https://developer.multiset.ai/credentials
# ============================================================

# Authentication Credentials (Required)
MULTISET_CLIENT_ID=your-client-id
MULTISET_CLIENT_SECRET=your-client-secret

# Map Configuration — provide ONE of the following
MULTISET_MAP_CODE=MAP_XXXXXXXXXX
MULTISET_MAP_SET_CODE=
```

| Property | Description | Required |
|----------|-------------|----------|
| `MULTISET_CLIENT_ID` | Client ID from the developer portal | Yes |
| `MULTISET_CLIENT_SECRET` | Client secret from the developer portal | Yes |
| `MULTISET_MAP_CODE` | Single map identifier for localization | One of these |
| `MULTISET_MAP_SET_CODE` | Map set identifier for multi-map localization | is required |

Map code / mapset code can also be changed at runtime via the in-app **Settings** dialog (the gear icon on the feature-selection screen). Values changed there are persisted in `SharedPreferences` and override the build-time defaults from `multiset.properties` on subsequent launches.

> **Security:** Both `local.properties` and `multiset.properties` are listed in the repo `.gitignore` and should never be committed.

#### c. DAT credentials (`res/values/strings.xml`)

The Meta Wearables DAT SDK credentials live in `app/src/main/res/values/strings.xml` (`dat_application_id` + `dat_client_token`, surfaced into the manifest as `com.meta.wearable.mwdat.APPLICATION_ID` / `CLIENT_TOKEN`). Leave `dat_client_token` empty when using the Meta AI app's Developer Mode flow.

### 3. Build and Run

```bash
./gradlew assembleDebug     # build debug APK
./gradlew installDebug      # build + install on a connected device
```

Or in Android Studio: **Run > Run 'app'**.

---

## Pairing Meta Ray-Ban Smart Glasses

### Prerequisites

1. Install the **Meta AI** app on your phone
2. Pair your Ray-Ban Meta glasses with the Meta AI app
3. Enable **Developer Mode** in the Meta AI app settings

### Pairing Steps

1. Launch the MultiSet Wearable VPS app
2. Ensure your glasses are powered on and connected to the Meta AI app
3. Tap **"Connect My Glasses"**
4. The app hands off to Meta AI for authorization
5. Grant camera permission when prompted
6. Once authorized you return to the app with the glasses connected, and the **feature-selection menu** appears

### Connection Status

The home screen shows connection status:
- **Green indicator** ("Glasses Paired"): glasses connected and ready
- **Red / "Waiting"**: glasses not connected

After connecting, the feature menu offers **Localization Demo** and **Navigation Demo**.

---

## Video Streaming

Each live feature (Localization, Navigation) opens a camera stream:

1. Select a feature from the menu
2. The app requests camera permission from your glasses
3. Tap **"Start Camera Stream"** / **"Open Localization"** to begin the live feed

---

## VPS Localization

### How Localization Works

1. The app captures an image from the glasses camera (downscaled before upload)
2. The image is sent to the MultiSet VPS API with the camera intrinsics
3. The API returns the camera's 6-DoF pose (position + orientation) in the mapped environment
4. The result includes a confidence score and the position relative to the map origin

### Localization Request Payload

The app sends a `multipart/form-data` request (`POST /v1/vps/map/query-form`) with:

| Field | Description | Example |
|-------|-------------|---------|
| `queryImage` | JPEG image from the glasses camera | Binary data |
| `width` | Image width in pixels | `540` |
| `height` | Image height in pixels | `720` |
| `fx` | Focal length X (pixels) | `422.25` |
| `fy` | Focal length Y (pixels) | `422.9` |
| `px` | Principal point X | `270.35` |
| `py` | Principal point Y | `363.75` |
| `mapCode` | Target map identifier | `MAP_XXXXXXXXXX` |
| `mapSetCode` | Map set identifier (optional) | `MAPSET_XXX` |
| `isRightHanded` | Coordinate system flag | `false` |

The captured photo is downscaled by 0.5 before upload (e.g. 1080×1440 → 540×720); continuous navigation localization sends the live medium stream frame (504×896). `NetworkManager.calculateIntrinsics` scales the calibrated intrinsics to whatever resolution is actually uploaded.

### Localization Response

```json
{
  "poseFound": true,
  "position": { "x": 2.34, "y": -0.99, "z": 1.56 },
  "rotation": { "x": 0.0, "y": 0.707, "z": 0.0, "w": 0.707 },
  "confidence": 0.87,
  "mapIds": ["MAP_XXXXXXXXXX"]
}
```

The app resolves the pose as **root `position`/`rotation` → `estimatedPose` → `trackingPose`** (`LocalizationResult.posePosition` / `poseRotation`), matching the iOS app.

### Camera Intrinsics (calibrated, base resolution)

| Parameter | Value | Description |
|-----------|-------|-------------|
| Resolution | 1080 × 1440 | Full capture resolution |
| Focal Length (fx) | 844.5 px | Horizontal focal length |
| Focal Length (fy) | 845.8 px | Vertical focal length |
| Principal Point (px) | 540.7 px | Optical center X |
| Principal Point (py) | 727.5 px | Optical center Y |

These are scaled to the uploaded resolution (half: 540×720, medium: 504×896). Presets are tunable in the in-app Settings; defaults match the iOS calibrated values.

---

## Navigation

### Navigation System Overview

The navigation system provides turn-by-turn audio guidance from your current position to a selected Point of Interest (POI). It uses:

1. **VPS Localization**: continuous position updates during navigation
2. **Waypoint Graph**: precomputed navigation paths between locations
3. **A\* Pathfinding**: runtime path calculation when a precomputed path isn't available
4. **Audio Instructions**: directional guidance played through the glasses

### Navigation Flow

```
User Localizes → Selects POI → Path Calculated → Navigation Starts
                                      ↓
        ← Position Updates ← Continuous Localization (live video frame, ~50ms)
                                      ↓
                       Turn-by-Turn Audio Instructions + Live 2D Map
                                      ↓
                          Arrival Detection → Done
```

The navigation engine ports the iOS/Unity algorithm: circular-mean heading smoothing, dead reckoning, look-ahead targeting, instruction hysteresis (angle thresholds 20°/60°/150°), off-path recalculation, and arrival detection.

### Starting Navigation

1. Open the **Navigation Demo** and start the camera stream
2. Tap **Localize** to get your current position (wait for the green "Origin" indicator)
3. Tap the **destinations** button to view available POIs (sorted by distance)
4. Select a POI — navigation begins with audio instructions and a live 2D map (user position + heading, route, POIs)

The 2D map supports pinch-zoom, pan, recenter, and a full-screen view with a legend and POI detail/Navigate sheet.

---

## Importing Navigation Data from Unity

### Unity POI Data Export Scene

The navigation system requires POI and waypoint data exported from Unity, generated using the **MultiSet Unity SDK's POI Data Export Scene**.

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

### Importing Navigation Data into the App

1. **Export from Unity**:
   - Open your Unity project with the MultiSet SDK
   - Use the POI Data Export Scene to generate the JSON
   - Name the file `{mapCode}_navigation_data.json` (e.g. `MAP_QTTSRGRYP7HR_navigation_data.json`)

2. **Add to the Android project**:
   - Copy the file into `app/src/main/assets/navigation/`
   - The basename **must** match the configured Map Code

3. **Configure the Map Code**:
   - Set `MULTISET_MAP_CODE` in `multiset.properties` and rebuild, **or** open the in-app Settings (gear icon) and enter the Map Code at runtime
   - The app reloads the matching navigation data automatically when the map code changes

### Coordinate System

The app uses a **left-handed coordinate system** matching Unity's default:
- **X**: Right
- **Y**: Up
- **Z**: Forward

The VPS API is called with `isRightHanded=false` so the returned coordinates match the Unity-exported navigation data.

---

## Troubleshooting

For issues related to the Meta Wearables Device Access Toolkit, see the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or the [discussions forum](https://github.com/facebook/meta-wearables-dat-android/discussions).

## License

This source code is licensed under the license found in the LICENSE file in the root directory of this source tree. The MultiSet VPS integration is subject to the MultiSet License — see www.multiset.ai.
