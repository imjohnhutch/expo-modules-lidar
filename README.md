# expo-lidar

An Expo module that bridges Apple's LiDAR sensor into React Native via ARKit. Capture depth frames, measure real-world dimensions in millimeters, render live depth heatmaps, and export 3D meshes — all from JavaScript.

## Features

- **`isSupported()`** — detect LiDAR hardware at runtime
- **`startSession()` / `stopSession()`** — manage the ARKit session
- **`captureDepthFrame()`** — save aligned color + depth images to disk
- **`measureRegion(x, y, w, h)`** — measure a bounding box in real-world mm using depth + camera intrinsics
- **`exportMesh(x, y, w, h)`** — export the AR mesh within a region as `.obj`
- **`<LiDARCameraView />`** — native AR camera view with depth heatmap overlay and draw-to-select gesture
- **Events** — `onDepthFrameCaptured`, `onMeshUpdated`, `onMeasurementComplete`

## Requirements

| | Minimum |
|---|---|
| Expo SDK | 52+ |
| iOS | 17.0+ |
| React Native | 0.76+ |
| Hardware | iPhone 12 Pro+, iPad Pro 2020+ (LiDAR-equipped) |

> **Note:** This module requires a **development build** (`npx expo run:ios`). It does not work with Expo Go.

## Installation

```bash
npm install expo-lidar
# or
yarn add expo-lidar
```

Then regenerate your native project:

```bash
npx expo prebuild --clean
```

### app.json / app.config.js

Add the plugin and camera permission:

```json
{
  "expo": {
    "plugins": ["expo-lidar"],
    "ios": {
      "infoPlist": {
        "NSCameraUsageDescription": "This app uses the camera and LiDAR sensor for 3D depth capture."
      }
    }
  }
}
```

## API

### Functions

```ts
import {
  isSupported,
  startSession,
  stopSession,
  captureDepthFrame,
  measureRegion,
  exportMesh,
} from 'expo-lidar';
```

#### `isSupported(): Promise<boolean>`

Returns `true` if the device has a LiDAR sensor. Always `false` on Android.

#### `startSession(): Promise<void>`

Starts an ARKit session with scene depth and mesh reconstruction. Throws if LiDAR is not supported.

#### `stopSession(): Promise<void>`

Pauses and tears down the AR session.

#### `captureDepthFrame(): Promise<DepthFrame | null>`

Captures the current frame. Returns paths to the saved color image (JPEG) and depth map (binary Float32), plus camera intrinsics.

```ts
const frame = await captureDepthFrame();
// frame.colorImagePath — "/tmp/.../color_1234.jpg"
// frame.depthMapPath   — "/tmp/.../depth_1234.depth"
// frame.intrinsics     — [fx, fy, cx, cy]
// frame.timestamp      — ARFrame timestamp
```

#### `measureRegion(x, y, width, height): Promise<RegionMeasurement | null>`

Measures a normalized bounding box (0-1 coords) using the depth buffer and camera intrinsics. Returns real-world dimensions in millimeters.

```ts
const m = await measureRegion(0.3, 0.3, 0.4, 0.4);
// m.widthMM, m.heightMM, m.surfaceAreaMM2, m.averageDepthMM, m.depthProfile
```

#### `exportMesh(x, y, width, height): Promise<string | null>`

Exports the AR mesh within the region as a `.obj` file. Returns the file path.

### Events

```ts
import { onDepthFrameCaptured, onMeshUpdated, onMeasurementComplete } from 'expo-lidar';

const sub = onDepthFrameCaptured((event) => {
  // event.timestamp, event.depthWidth, event.depthHeight,
  // event.averageDepthM, event.trackingState
});

// Clean up
sub.remove();
```

### Native View

```tsx
import { LiDARCameraView } from 'expo-lidar';

<LiDARCameraView
  style={{ flex: 1 }}
  showDepthOverlay={true}
  overlayOpacity={0.5}
  onRegionSelected={(event) => {
    const { x, y, width, height } = event.nativeEvent;
    // Normalized 0-1 coordinates of the drawn box
  }}
/>
```

## Depth Map Format

The `.depth` files saved by `captureDepthFrame()` use a simple binary format:

| Offset | Type | Description |
|--------|------|-------------|
| 0 | UInt32 | Width |
| 4 | UInt32 | Height |
| 8 | Float32[] | Depth values in meters (row-major) |

## How Measurement Works

The module uses the LiDAR depth buffer and camera intrinsics to project each pixel in the selected region into 3D space:

```
X_world = (pixel_x - cx) * depth / fx
Y_world = (pixel_y - cy) * depth / fy
Z_world = depth
```

Surface area is estimated by triangulating a grid of these 3D points. The depth profile samples the center row to show relative elevation across the region.

## Android

On Android, `isSupported()` returns `false` and all other functions are no-ops that return `null`. The module compiles and links without error so you can use it in cross-platform projects with a runtime check.

## License

MIT
