package expo.modules.lidar

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.Promise

class ExpoLidarModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("ExpoLidar")

        AsyncFunction("isSupported") { promise: Promise ->
            // LiDAR is an Apple-only hardware feature
            promise.resolve(false)
        }

        AsyncFunction("startSession") { promise: Promise ->
            promise.resolve(null)
        }

        AsyncFunction("stopSession") { promise: Promise ->
            promise.resolve(null)
        }

        AsyncFunction("captureDepthFrame") { promise: Promise ->
            promise.resolve(null)
        }

        AsyncFunction("measureRegion") { _: Double, _: Double, _: Double, _: Double, promise: Promise ->
            promise.resolve(null)
        }

        AsyncFunction("exportMesh") { _: Double, _: Double, _: Double, _: Double, promise: Promise ->
            promise.resolve(null)
        }

        Events("onDepthFrameCaptured", "onMeshUpdated", "onMeasurementComplete")
    }
}
