import ExpoModulesCore
import ARKit
import RealityKit
import CoreVideo

public class LiDARSessionModule: Module {
    private var arSession: ARSession?
    private var sessionDelegate: LiDARSessionDelegate?

    /// Returns the view's shared session if available, otherwise falls back
    /// to the module's own session. This avoids two ARSessions competing
    /// for the camera (which freezes the preview).
    private var activeSession: ARSession? {
        return SharedARSession.shared.viewSession ?? arSession
    }

    public func definition() -> ModuleDefinition {
        Name("ExpoLidar")

        Events("onDepthFrameCaptured", "onMeshUpdated", "onMeasurementComplete")

        // MARK: - Capability Check

        AsyncFunction("isSupported") { () -> Bool in
            if #available(iOS 17.0, *) {
                return ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
            }
            return false
        }

        // MARK: - Session Lifecycle

        AsyncFunction("startSession") { () in
            // If the camera view is already running an ARSession, piggyback
            // on it instead of creating a competing one.
            if SharedARSession.shared.viewSession != nil {
                return
            }

            guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
                throw LiDARError.notSupported
            }

            let config = ARWorldTrackingConfiguration()
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                config.sceneReconstruction = .meshWithClassification
            }
            config.environmentTexturing = .automatic

            let session = ARSession()
            let delegate = LiDARSessionDelegate(module: self)
            session.delegate = delegate

            self.arSession = session
            self.sessionDelegate = delegate

            session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        AsyncFunction("stopSession") { () in
            // Don't pause the view's session — only clean up if we own it.
            if SharedARSession.shared.viewSession != nil {
                return
            }
            self.arSession?.pause()
            self.arSession = nil
            self.sessionDelegate = nil
        }

        // Reset the world origin to the device's current pose without tearing
        // down the camera preview. Re-runs whichever session is active.
        AsyncFunction("resetTracking") { () in
            guard let session = self.activeSession,
                  let config = session.configuration else {
                throw LiDARError.sessionNotRunning
            }
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        // MARK: - Depth Frame Capture

        AsyncFunction("captureDepthFrame") { () -> [String: Any]? in
            guard let frame = self.activeSession?.currentFrame else { return nil }
            guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else {
                return nil
            }

            let colorImage = frame.capturedImage
            let intrinsics = frame.camera.intrinsics

            let colorPath = ImageUtils.savePixelBufferAsJPEG(colorImage, prefix: "color")
            let depthPath = ImageUtils.saveDepthMapAsData(depthMap, prefix: "depth")

            guard let cPath = colorPath, let dPath = depthPath else { return nil }

            // Camera pose: 4x4 column-major transform (world space)
            let t = frame.camera.transform
            let pose: [Float] = [
                t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
                t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
                t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
                t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
            ]

            return [
                "colorImagePath": cPath,
                "depthMapPath": dPath,
                "intrinsics": [
                    intrinsics.columns.0.x,
                    intrinsics.columns.1.y,
                    intrinsics.columns.2.x,
                    intrinsics.columns.2.y
                ],
                "pose": pose,
                "timestamp": frame.timestamp
            ]
        }

        // MARK: - Region Measurement

        AsyncFunction("measureRegion") {
            (x: Double, y: Double, width: Double, height: Double) -> [String: Any]? in

            guard let frame = self.activeSession?.currentFrame else { return nil }
            guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else {
                return nil
            }

            let region = CGRect(x: x, y: y, width: width, height: height)
            let measurement = DepthMeasurer.measure(
                region: region,
                depthBuffer: depthMap,
                intrinsics: frame.camera.intrinsics,
                imageResolution: frame.camera.imageResolution
            )

            let result: [String: Any] = [
                "widthMM": measurement.widthMM,
                "heightMM": measurement.heightMM,
                "surfaceAreaMM2": measurement.surfaceAreaMM2,
                "averageDepthMM": measurement.averageDepthMM,
                "depthProfile": measurement.depthProfile
            ]

            self.sendEvent("onMeasurementComplete", result)
            return result
        }

        // MARK: - Mesh Export

        AsyncFunction("exportMesh") {
            (x: Double, y: Double, width: Double, height: Double) -> String? in

            guard let frame = self.activeSession?.currentFrame else { return nil }

            let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            guard !meshAnchors.isEmpty else { return nil }

            let region = CGRect(x: x, y: y, width: width, height: height)
            let exporter = MeshExporter()
            return exporter.exportRegionMesh(
                anchors: meshAnchors,
                region: region,
                frame: frame
            )
        }
    }
}

// MARK: - Error Types

enum LiDARError: Error, LocalizedError {
    case notSupported
    case sessionNotRunning
    case noDepthData

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "LiDAR is not supported on this device"
        case .sessionNotRunning:
            return "AR session is not running"
        case .noDepthData:
            return "No depth data available"
        }
    }
}
