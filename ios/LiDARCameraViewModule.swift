import ExpoModulesCore

public class LiDARCameraViewModule: Module {
    public func definition() -> ModuleDefinition {
        Name("LiDARCameraView")

        View(LiDARCameraView.self) {
            Prop("showDepthOverlay") { (view: LiDARCameraView, show: Bool) in
                view.toggleDepthOverlay(show)
            }

            Prop("overlayOpacity") { (view: LiDARCameraView, opacity: Double) in
                view.setOverlayOpacity(CGFloat(opacity))
            }

            Events("onRegionSelected")
        }
    }
}
