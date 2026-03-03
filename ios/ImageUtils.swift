import CoreVideo
import UIKit

/// Utility functions for saving camera and depth buffers to disk.
struct ImageUtils {

    /// Save a camera pixel buffer as a JPEG file. Returns the file path.
    static func savePixelBufferAsJPEG(_ pixelBuffer: CVPixelBuffer, prefix: String) -> String? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.85) else {
            return nil
        }

        let fileName = "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let filePath = NSTemporaryDirectory() + fileName

        do {
            try jpegData.write(to: URL(fileURLWithPath: filePath))
            return filePath
        } catch {
            return nil
        }
    }

    /// Save a Float32 depth map as raw binary data.
    /// File format: UInt32(width) + UInt32(height) + contiguous Float32 values.
    static func saveDepthMapAsData(_ depthMap: CVPixelBuffer, prefix: String) -> String? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        var data = Data()

        var w = UInt32(width)
        var h = UInt32(height)
        data.append(Data(bytes: &w, count: MemoryLayout<UInt32>.size))
        data.append(Data(bytes: &h, count: MemoryLayout<UInt32>.size))

        for row in 0..<height {
            let rowStart = baseAddress.advanced(by: row * bytesPerRow)
            data.append(Data(bytes: rowStart, count: width * MemoryLayout<Float32>.size))
        }

        let fileName = "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1000)).depth"
        let filePath = NSTemporaryDirectory() + fileName

        do {
            try data.write(to: URL(fileURLWithPath: filePath))
            return filePath
        } catch {
            return nil
        }
    }
}
