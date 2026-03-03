import ARKit
import CoreVideo
import simd

/// Result of a depth-based region measurement.
public struct RegionMeasurement {
    /// Width of the measured region in millimeters.
    public let widthMM: Double
    /// Height of the measured region in millimeters.
    public let heightMM: Double
    /// Estimated surface area of the region in square millimeters.
    public let surfaceAreaMM2: Double
    /// Average depth (distance from camera) of the region in millimeters.
    public let averageDepthMM: Double
    /// Relative elevation profile sampled across the center row, in millimeters.
    /// Values are relative to the region's average depth (positive = closer to camera).
    public let depthProfile: [Double]
}

/// Measures real-world dimensions of a region using the LiDAR depth buffer
/// and camera intrinsics.
struct DepthMeasurer {

    /// Measure a region within a normalized bounding box (0-1 coords).
    ///
    /// Uses the depth buffer and camera intrinsics to project pixels into 3D:
    ///
    ///     X = (pixel_x - cx) * depth / fx
    ///     Y = (pixel_y - cy) * depth / fy
    ///     Z = depth
    ///
    /// - Parameters:
    ///   - region: Normalized bounding box (0-1 coords relative to depth buffer)
    ///   - depthBuffer: Float32 CVPixelBuffer from ARKit scene depth
    ///   - intrinsics: Camera intrinsics matrix (3x3)
    ///   - imageResolution: Camera image resolution for intrinsics scaling
    /// - Returns: A `RegionMeasurement` with real-world dimensions.
    static func measure(
        region: CGRect,
        depthBuffer: CVPixelBuffer,
        intrinsics: simd_float3x3,
        imageResolution: CGSize
    ) -> RegionMeasurement {

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return .zero
        }

        // Scale intrinsics to depth buffer resolution
        let scaleX = Float(depthWidth) / Float(imageResolution.width)
        let scaleY = Float(depthHeight) / Float(imageResolution.height)

        let fx = intrinsics.columns.0.x * scaleX
        let fy = intrinsics.columns.1.y * scaleY
        let cx = intrinsics.columns.2.x * scaleX
        let cy = intrinsics.columns.2.y * scaleY

        // Convert normalized region to pixel coordinates
        let startX = Int(region.origin.x * CGFloat(depthWidth))
        let startY = Int(region.origin.y * CGFloat(depthHeight))
        let endX = min(Int((region.origin.x + region.size.width) * CGFloat(depthWidth)), depthWidth - 1)
        let endY = min(Int((region.origin.y + region.size.height) * CGFloat(depthHeight)), depthHeight - 1)

        guard startX < endX, startY < endY else { return .zero }

        // Collect 3D points
        var points3D: [SIMD3<Float>] = []
        var depthValues: [Float] = []

        for py in startY...endY {
            for px in startX...endX {
                let offset = py * bytesPerRow + px * MemoryLayout<Float32>.size
                let depth = baseAddress.advanced(by: offset)
                    .assumingMemoryBound(to: Float32.self).pointee

                guard depth > 0.05, depth < 3.0 else { continue }

                let xWorld = (Float(px) - cx) * depth / fx
                let yWorld = (Float(py) - cy) * depth / fy

                points3D.append(SIMD3<Float>(xWorld, yWorld, depth))
                depthValues.append(depth)
            }
        }

        guard !points3D.isEmpty else { return .zero }

        // Bounding dimensions in world space
        var minPt = points3D[0]
        var maxPt = points3D[0]
        for p in points3D {
            minPt = min(minPt, p)
            maxPt = max(maxPt, p)
        }

        let extent = maxPt - minPt
        let widthM = Double(extent.x)
        let heightM = Double(extent.y)

        let avgDepth = Double(depthValues.reduce(0, +)) / Double(depthValues.count)

        // Surface area via triangulated grid
        let surfaceArea = estimateSurfaceArea(
            startX: startX, startY: startY, endX: endX, endY: endY,
            baseAddress: baseAddress, bytesPerRow: bytesPerRow,
            fx: fx, fy: fy, cx: cx, cy: cy
        )

        // Depth profile across center row
        let profileRow = (startY + endY) / 2
        var depthProfile: [Double] = []
        let profileStep = max(1, (endX - startX) / 20)
        for px in stride(from: startX, through: endX, by: profileStep) {
            let offset = profileRow * bytesPerRow + px * MemoryLayout<Float32>.size
            let depth = baseAddress.advanced(by: offset)
                .assumingMemoryBound(to: Float32.self).pointee
            if depth > 0.05, depth < 3.0 {
                depthProfile.append(Double(depth) * 1000.0)
            }
        }

        let profileAvg = depthProfile.isEmpty ? 0 : depthProfile.reduce(0, +) / Double(depthProfile.count)
        let normalizedProfile = depthProfile.map { $0 - profileAvg }

        return RegionMeasurement(
            widthMM: widthM * 1000.0,
            heightMM: heightM * 1000.0,
            surfaceAreaMM2: surfaceArea * 1_000_000.0,
            averageDepthMM: avgDepth * 1000.0,
            depthProfile: normalizedProfile
        )
    }

    // MARK: - Surface Area via Triangle Mesh

    private static func estimateSurfaceArea(
        startX: Int, startY: Int, endX: Int, endY: Int,
        baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        fx: Float, fy: Float, cx: Float, cy: Float
    ) -> Double {

        let step = 2
        let cols = (endX - startX) / step + 1
        let rows = (endY - startY) / step + 1
        guard cols > 1, rows > 1 else { return 0 }

        var grid: [[SIMD3<Float>?]] = Array(
            repeating: Array(repeating: nil, count: cols),
            count: rows
        )

        for row in 0..<rows {
            let py = startY + row * step
            for col in 0..<cols {
                let px = startX + col * step
                let offset = py * bytesPerRow + px * MemoryLayout<Float32>.size
                let depth = baseAddress.advanced(by: offset)
                    .assumingMemoryBound(to: Float32.self).pointee

                if depth > 0.05, depth < 3.0 {
                    let x = (Float(px) - cx) * depth / fx
                    let y = (Float(py) - cy) * depth / fy
                    grid[row][col] = SIMD3<Float>(x, y, depth)
                }
            }
        }

        var totalArea: Double = 0
        for row in 0..<(rows - 1) {
            for col in 0..<(cols - 1) {
                if let p00 = grid[row][col],
                   let p10 = grid[row][col + 1],
                   let p01 = grid[row + 1][col],
                   let p11 = grid[row + 1][col + 1] {
                    totalArea += Double(triangleArea(p00, p10, p01))
                    totalArea += Double(triangleArea(p10, p11, p01))
                }
            }
        }

        return totalArea
    }

    private static func triangleArea(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float {
        let ab = b - a
        let ac = c - a
        return length(cross(ab, ac)) * 0.5
    }
}

extension RegionMeasurement {
    static let zero = RegionMeasurement(
        widthMM: 0, heightMM: 0, surfaceAreaMM2: 0, averageDepthMM: 0, depthProfile: []
    )
}
