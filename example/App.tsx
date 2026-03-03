/**
 * Example usage of expo-lidar.
 *
 * This file is not part of the published package — it's a reference
 * for how to integrate the module into your own Expo app.
 */

import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Platform } from 'react-native';
import {
  isSupported,
  startSession,
  stopSession,
  measureRegion,
  captureDepthFrame,
  exportMesh,
  LiDARCameraView,
  type RegionMeasurement,
  type RegionSelectedEvent,
} from 'expo-lidar';

export default function LiDARExample() {
  const [supported, setSupported] = useState<boolean | null>(null);
  const [measurement, setMeasurement] = useState<RegionMeasurement | null>(null);
  const [lastRegion, setLastRegion] = useState<RegionSelectedEvent | null>(null);
  const [showDepth, setShowDepth] = useState(false);

  useEffect(() => {
    let mounted = true;

    (async () => {
      const ok = await isSupported();
      if (!mounted) return;
      setSupported(ok);
      if (ok) await startSession();
    })();

    return () => {
      mounted = false;
      stopSession();
    };
  }, []);

  const handleRegionSelected = async (event: { nativeEvent: RegionSelectedEvent }) => {
    const region = event.nativeEvent;
    setLastRegion(region);

    const result = await measureRegion(region.x, region.y, region.width, region.height);
    if (result) setMeasurement(result);
  };

  const handleCapture = async () => {
    const frame = await captureDepthFrame();
    if (frame) {
      console.log('Color:', frame.colorImagePath);
      console.log('Depth:', frame.depthMapPath);
    }
  };

  const handleExport = async () => {
    if (!lastRegion) return;
    const path = await exportMesh(
      lastRegion.x, lastRegion.y, lastRegion.width, lastRegion.height,
    );
    if (path) console.log('Mesh saved:', path);
  };

  if (supported === null) {
    return <View style={s.center}><Text>Checking LiDAR...</Text></View>;
  }

  if (!supported) {
    return (
      <View style={s.center}>
        <Text style={s.title}>LiDAR Not Available</Text>
        <Text style={s.sub}>
          Requires iPhone 12 Pro+ or iPad Pro 2020+.
        </Text>
      </View>
    );
  }

  return (
    <View style={s.container}>
      <LiDARCameraView
        style={s.camera}
        showDepthOverlay={showDepth}
        overlayOpacity={0.5}
        onRegionSelected={handleRegionSelected}
      />

      {measurement && (
        <View style={s.overlay}>
          <Text style={s.measure}>
            {measurement.widthMM.toFixed(1)} x {measurement.heightMM.toFixed(1)} mm
          </Text>
          <Text style={s.measure}>
            Area: {measurement.surfaceAreaMM2.toFixed(1)} mm²
          </Text>
        </View>
      )}

      <View style={s.controls}>
        <TouchableOpacity onPress={() => setShowDepth(!showDepth)} style={s.btn}>
          <Text style={s.btnText}>{showDepth ? 'Hide' : 'Show'} Depth</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={handleCapture} style={s.btn}>
          <Text style={s.btnText}>Capture</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={handleExport} style={s.btn}>
          <Text style={s.btnText}>Export 3D</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 32 },
  camera: { flex: 1 },
  title: { fontSize: 20, fontWeight: '700', marginBottom: 8, textAlign: 'center' },
  sub: { fontSize: 16, color: '#666', textAlign: 'center' },
  overlay: {
    position: 'absolute', top: 80, left: 16,
    backgroundColor: 'rgba(0,0,0,0.7)', padding: 12, borderRadius: 8,
  },
  measure: { color: '#fff', fontSize: 16, fontWeight: '600' },
  controls: {
    flexDirection: 'row', justifyContent: 'space-around',
    padding: 16, backgroundColor: '#111',
  },
  btn: {
    backgroundColor: '#2563EB', paddingHorizontal: 16,
    paddingVertical: 10, borderRadius: 8,
  },
  btnText: { color: '#fff', fontWeight: '600' },
});
