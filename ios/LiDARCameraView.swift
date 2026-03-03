import UIKit
import ARKit
import RealityKit
import ExpoModulesCore

/// Native AR camera view with optional depth heatmap overlay and
/// draw-to-select region gesture.
class LiDARCameraView: ExpoView {
    private var arView: ARView?
    private var depthOverlayView: UIImageView?
    private var selectionBoxLayer: CAShapeLayer?
    private var panStartPoint: CGPoint = .zero
    private var isShowingDepthOverlay = false
    private var currentOverlayOpacity: CGFloat = 0.5

    let onRegionSelected = EventDispatcher()

    // MARK: - Lifecycle

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        setupARView()
        setupDepthOverlay()
        setupGesture()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        arView?.frame = bounds
        depthOverlayView?.frame = bounds
    }

    // MARK: - Setup

    private func setupARView() {
        let view = ARView(frame: bounds)
        view.automaticallyConfigureSession = false
        view.renderOptions = [.disablePersonOcclusion, .disableMotionBlur]
        addSubview(view)
        arView = view

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            let config = ARWorldTrackingConfiguration()
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                config.sceneReconstruction = .meshWithClassification
            }
            view.session.run(config)
            view.session.delegate = self
        }
    }

    private func setupDepthOverlay() {
        let overlay = UIImageView(frame: bounds)
        overlay.contentMode = .scaleAspectFill
        overlay.alpha = 0
        overlay.isUserInteractionEnabled = false
        addSubview(overlay)
        depthOverlayView = overlay
    }

    private func setupGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.systemBlue.cgColor
        layer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15).cgColor
        layer.lineWidth = 2.0
        layer.lineDashPattern = [6, 3]
        self.layer.addSublayer(layer)
        selectionBoxLayer = layer
    }

    // MARK: - Public Methods

    func toggleDepthOverlay(_ show: Bool) {
        isShowingDepthOverlay = show
        UIView.animate(withDuration: 0.25) {
            self.depthOverlayView?.alpha = show ? self.currentOverlayOpacity : 0
        }
    }

    func setOverlayOpacity(_ opacity: CGFloat) {
        currentOverlayOpacity = opacity
        if isShowingDepthOverlay {
            depthOverlayView?.alpha = opacity
        }
    }

    // MARK: - Region Selection Gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            panStartPoint = location
            selectionBoxLayer?.isHidden = false

        case .changed:
            let rect = CGRect(
                x: min(panStartPoint.x, location.x),
                y: min(panStartPoint.y, location.y),
                width: abs(location.x - panStartPoint.x),
                height: abs(location.y - panStartPoint.y)
            )
            selectionBoxLayer?.path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath

        case .ended, .cancelled:
            let rect = CGRect(
                x: min(panStartPoint.x, location.x),
                y: min(panStartPoint.y, location.y),
                width: abs(location.x - panStartPoint.x),
                height: abs(location.y - panStartPoint.y)
            )

            if rect.width > 20, rect.height > 20 {
                let normalizedRect: [String: Any] = [
                    "x": Double(rect.origin.x / bounds.width),
                    "y": Double(rect.origin.y / bounds.height),
                    "width": Double(rect.width / bounds.width),
                    "height": Double(rect.height / bounds.height)
                ]
                onRegionSelected(normalizedRect)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.selectionBoxLayer?.isHidden = true
            }

        default:
            break
        }
    }

    // MARK: - Depth Heatmap

    private func renderDepthHeatmap(_ depthMap: CVPixelBuffer) -> UIImage? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        var minDepth: Float = .greatestFiniteMagnitude
        var maxDepth: Float = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * MemoryLayout<Float32>.size
                let depth = baseAddress.advanced(by: offset)
                    .assumingMemoryBound(to: Float32.self).pointee
                if depth > 0.05, depth < 5.0 {
                    minDepth = min(minDepth, depth)
                    maxDepth = max(maxDepth, depth)
                }
            }
        }

        guard maxDepth > minDepth else { return nil }
        let range = maxDepth - minDepth

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * MemoryLayout<Float32>.size
                let depth = baseAddress.advanced(by: offset)
                    .assumingMemoryBound(to: Float32.self).pointee

                let pixelOffset = (y * width + x) * 4
                if depth > 0.05, depth < 5.0 {
                    let normalized = (depth - minDepth) / range
                    let (r, g, b) = heatmapColor(normalized)
                    pixelData[pixelOffset] = r
                    pixelData[pixelOffset + 1] = g
                    pixelData[pixelOffset + 2] = b
                    pixelData[pixelOffset + 3] = 200
                } else {
                    pixelData[pixelOffset + 3] = 0
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else { return nil }

        return UIImage(cgImage: cgImage)
    }

    /// Maps 0-1 to a blue -> green -> red heatmap.
    private func heatmapColor(_ value: Float) -> (UInt8, UInt8, UInt8) {
        let v = max(0, min(1, value))
        if v < 0.5 {
            let t = v * 2.0
            return (0, UInt8(t * 255), UInt8((1.0 - t) * 255))
        } else {
            let t = (v - 0.5) * 2.0
            return (UInt8(t * 255), UInt8((1.0 - t) * 255), 0)
        }
    }
}

// MARK: - ARSessionDelegate

extension LiDARCameraView: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isShowingDepthOverlay else { return }
        guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else { return }

        if let heatmap = renderDepthHeatmap(depthMap) {
            DispatchQueue.main.async {
                self.depthOverlayView?.image = heatmap
            }
        }
    }
}
