import ARKit

/// Singleton registry so LiDARCameraView and LiDARSessionModule can share
/// one ARSession instead of fighting over the camera hardware.
final class SharedARSession {
    static let shared = SharedARSession()
    private init() {}

    /// The ARSession owned by LiDARCameraView (set when the view mounts, cleared on deinit).
    weak var viewSession: ARSession?
}
