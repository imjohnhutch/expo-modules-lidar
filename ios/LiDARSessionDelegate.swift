import ARKit
import ExpoModulesCore

class LiDARSessionDelegate: NSObject, ARSessionDelegate {
    private weak var module: LiDARSessionModule?
    private var lastFrameEmitTime: TimeInterval = 0
    private let frameEmitInterval: TimeInterval = 0.1 // 10 fps max for events

    init(module: LiDARSessionModule) {
        self.module = module
        super.init()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp
        guard now - lastFrameEmitTime >= frameEmitInterval else { return }
        lastFrameEmitTime = now

        guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else {
            return
        }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let avgDepth = computeCenterAverageDepth(depthMap)

        module?.sendEvent("onDepthFrameCaptured", [
            "timestamp": frame.timestamp,
            "depthWidth": depthWidth,
            "depthHeight": depthHeight,
            "averageDepthM": avgDepth,
            "trackingState": trackingStateString(frame.camera.trackingState)
        ])
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        emitMeshUpdate(anchors: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        emitMeshUpdate(anchors: anchors)
    }

    // MARK: - Helpers

    private func emitMeshUpdate(anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }

        var totalVertices = 0
        var totalFaces = 0
        for anchor in meshAnchors {
            totalVertices += anchor.geometry.vertices.count
            totalFaces += anchor.geometry.faces.count
        }

        module?.sendEvent("onMeshUpdated", [
            "meshAnchorCount": meshAnchors.count,
            "totalVertices": totalVertices,
            "totalFaces": totalFaces
        ])
    }

    private func computeCenterAverageDepth(_ depthMap: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return 0 }

        let centerX = width / 2
        let centerY = height / 2
        let sampleRadius = min(width, height) / 8

        var sum: Float = 0
        var count: Int = 0

        for dy in -sampleRadius..<sampleRadius {
            for dx in -sampleRadius..<sampleRadius {
                let px = centerX + dx
                let py = centerY + dy
                guard px >= 0, px < width, py >= 0, py < height else { continue }

                let offset = py * bytesPerRow + px * MemoryLayout<Float32>.size
                let depth = baseAddress.advanced(by: offset).assumingMemoryBound(to: Float32.self).pointee

                if depth > 0 && depth < 5.0 {
                    sum += depth
                    count += 1
                }
            }
        }

        return count > 0 ? sum / Float(count) : 0
    }

    private func trackingStateString(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal:
            return "normal"
        case .limited(let reason):
            switch reason {
            case .initializing: return "initializing"
            case .excessiveMotion: return "excessiveMotion"
            case .insufficientFeatures: return "insufficientFeatures"
            case .relocalizing: return "relocalizing"
            @unknown default: return "limited"
            }
        case .notAvailable:
            return "notAvailable"
        }
    }
}
