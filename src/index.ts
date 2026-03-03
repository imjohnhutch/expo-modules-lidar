import { NativeModulesProxy, EventEmitter } from 'expo-modules-core';
import { requireNativeViewManager } from 'expo-modules-core';
import { Platform } from 'react-native';

const ExpoLidar = NativeModulesProxy.ExpoLidar;
const emitter = new EventEmitter(ExpoLidar);

// ────────────────────────────────────────────────────
// Types
// ────────────────────────────────────────────────────

/** Real-world measurement of a selected region. */
export interface RegionMeasurement {
  /** Width in millimeters. */
  widthMM: number;
  /** Height in millimeters. */
  heightMM: number;
  /** Estimated surface area in square millimeters. */
  surfaceAreaMM2: number;
  /** Average depth (distance from camera) in millimeters. */
  averageDepthMM: number;
  /**
   * Relative elevation profile sampled across the center of the region (mm).
   * Values are relative to the region average — positive means closer to camera.
   */
  depthProfile: number[];
}

/** A captured depth-aligned frame. */
export interface DepthFrame {
  /** Path to the saved color image (JPEG). */
  colorImagePath: string;
  /** Path to the saved depth map (binary Float32 file). */
  depthMapPath: string;
  /** Camera intrinsics: [fx, fy, cx, cy]. */
  intrinsics: [number, number, number, number];
  /** ARFrame timestamp. */
  timestamp: number;
}

/** Emitted on each depth frame update (~10 fps). */
export interface DepthFrameEvent {
  timestamp: number;
  depthWidth: number;
  depthHeight: number;
  /** Average depth at the center of the frame, in meters. */
  averageDepthM: number;
  /** AR tracking state: "normal", "initializing", "excessiveMotion", etc. */
  trackingState: string;
}

/** Emitted when AR mesh anchors are added or updated. */
export interface MeshUpdateEvent {
  meshAnchorCount: number;
  totalVertices: number;
  totalFaces: number;
}

/** Emitted by the LiDARCameraView when the user draws a selection box. */
export interface RegionSelectedEvent {
  x: number;
  y: number;
  width: number;
  height: number;
}

// ────────────────────────────────────────────────────
// Functions
// ────────────────────────────────────────────────────

/**
 * Check if the current device has a LiDAR sensor and supports scene depth.
 * Always returns `false` on Android.
 */
export async function isSupported(): Promise<boolean> {
  if (Platform.OS !== 'ios') return false;
  return ExpoLidar.isSupported();
}

/**
 * Start an AR session with scene depth and mesh reconstruction enabled.
 * Throws if LiDAR is not supported.
 */
export async function startSession(): Promise<void> {
  return ExpoLidar.startSession();
}

/** Pause and tear down the AR session. */
export async function stopSession(): Promise<void> {
  return ExpoLidar.stopSession();
}

/**
 * Capture the current depth-aligned frame (color image + depth map).
 * Files are saved to the app's temporary directory.
 */
export async function captureDepthFrame(): Promise<DepthFrame | null> {
  return ExpoLidar.captureDepthFrame();
}

/**
 * Measure a region defined by a normalized bounding box (0-1 coords).
 *
 * Uses the LiDAR depth buffer and camera intrinsics to compute real-world
 * dimensions in millimeters.
 *
 * @param x      Left edge (0-1)
 * @param y      Top edge (0-1)
 * @param width  Width (0-1)
 * @param height Height (0-1)
 */
export async function measureRegion(
  x: number,
  y: number,
  width: number,
  height: number,
): Promise<RegionMeasurement | null> {
  return ExpoLidar.measureRegion(x, y, width, height);
}

/**
 * Export the AR mesh within a normalized region as a Wavefront .obj file.
 * Returns the file path, or null if insufficient mesh data.
 *
 * @param x      Left edge (0-1)
 * @param y      Top edge (0-1)
 * @param width  Width (0-1)
 * @param height Height (0-1)
 */
export async function exportMesh(
  x: number,
  y: number,
  width: number,
  height: number,
): Promise<string | null> {
  return ExpoLidar.exportMesh(x, y, width, height);
}

// ────────────────────────────────────────────────────
// Events
// ────────────────────────────────────────────────────

/** Subscribe to throttled depth frame updates (~10 fps). */
export function onDepthFrameCaptured(callback: (event: DepthFrameEvent) => void) {
  return emitter.addListener('onDepthFrameCaptured', callback);
}

/** Subscribe to AR mesh anchor updates. */
export function onMeshUpdated(callback: (event: MeshUpdateEvent) => void) {
  return emitter.addListener('onMeshUpdated', callback);
}

/** Subscribe to measurement completion events. */
export function onMeasurementComplete(callback: (event: RegionMeasurement) => void) {
  return emitter.addListener('onMeasurementComplete', callback);
}

// ────────────────────────────────────────────────────
// Native View
// ────────────────────────────────────────────────────

/**
 * Native AR camera view with optional depth heatmap overlay.
 *
 * Props:
 * - `showDepthOverlay: boolean` — toggle depth visualization
 * - `overlayOpacity: number` — heatmap opacity (0-1)
 * - `onRegionSelected: (event) => void` — fires when user draws a selection box
 */
export const LiDARCameraView = requireNativeViewManager('LiDARCameraView');
