import ARKit
import simd

/// Exports ARMeshAnchor geometry within a projected 2D region of interest
/// as a Wavefront .obj file.
class MeshExporter {

    /// Filter mesh vertices that project into the given normalized 2D region
    /// and export the resulting submesh as .obj.
    ///
    /// - Parameters:
    ///   - anchors: ARMeshAnchors from the current AR session
    ///   - region: Normalized bounding box (0-1) defining the region of interest
    ///   - frame: Current ARFrame for camera matrices
    /// - Returns: File path to the exported .obj, or nil if no geometry matched.
    func exportRegionMesh(
        anchors: [ARMeshAnchor],
        region: CGRect,
        frame: ARFrame
    ) -> String? {
        let camera = frame.camera
        let viewMatrix = camera.viewMatrix(for: .portrait)
        let projMatrix = camera.projectionMatrix(for: .portrait,
                                                  viewportSize: camera.imageResolution,
                                                  zNear: 0.001, zFar: 10.0)
        let vpMatrix = projMatrix * viewMatrix

        var allVertices: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []
        var allFaces: [[Int]] = []

        for anchor in anchors {
            let geometry = anchor.geometry
            let modelMatrix = anchor.transform

            let vertices = geometry.vertices
            let normals = geometry.normals
            let faces = geometry.faces

            var localToGlobal: [Int: Int] = [:]

            for i in 0..<vertices.count {
                let localPos = vertices.buffer.contents()
                    .advanced(by: vertices.offset + vertices.stride * i)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee

                let worldPos4 = modelMatrix * SIMD4<Float>(localPos, 1.0)
                let worldPos = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)

                let clipPos = vpMatrix * SIMD4<Float>(worldPos, 1.0)
                guard clipPos.w > 0 else { continue }
                let ndc = SIMD2<Float>(clipPos.x / clipPos.w, clipPos.y / clipPos.w)

                let screenX = (ndc.x + 1.0) * 0.5
                let screenY = (1.0 - ndc.y) * 0.5

                let point = CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))
                guard region.contains(point) else { continue }

                let globalIdx = allVertices.count
                localToGlobal[i] = globalIdx
                allVertices.append(worldPos)

                let localNormal = normals.buffer.contents()
                    .advanced(by: normals.offset + normals.stride * i)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldNormal4 = modelMatrix * SIMD4<Float>(localNormal, 0.0)
                allNormals.append(normalize(SIMD3<Float>(worldNormal4.x, worldNormal4.y, worldNormal4.z)))
            }

            let faceIndicesPerFace = faces.indexCountPerPrimitive
            let indexBuffer = faces.buffer.contents().advanced(by: faces.offset)

            for f in 0..<faces.count {
                var faceIndices: [Int] = []
                var allInRegion = true

                for v in 0..<faceIndicesPerFace {
                    let byteOffset = (f * faceIndicesPerFace + v) * MemoryLayout<UInt32>.size
                    let vertexIndex = Int(indexBuffer.advanced(by: byteOffset)
                        .assumingMemoryBound(to: UInt32.self).pointee)

                    if let globalIdx = localToGlobal[vertexIndex] {
                        faceIndices.append(globalIdx)
                    } else {
                        allInRegion = false
                        break
                    }
                }

                if allInRegion, faceIndices.count == faceIndicesPerFace {
                    allFaces.append(faceIndices)
                }
            }
        }

        guard !allVertices.isEmpty, !allFaces.isEmpty else { return nil }
        return writeOBJ(vertices: allVertices, normals: allNormals, faces: allFaces)
    }

    // MARK: - OBJ Writer

    private func writeOBJ(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        faces: [[Int]]
    ) -> String? {
        var obj = "# expo-lidar mesh export\n"
        obj += "# Vertices: \(vertices.count), Faces: \(faces.count)\n\n"

        for v in vertices {
            obj += "v \(v.x) \(v.y) \(v.z)\n"
        }
        obj += "\n"

        for n in normals {
            obj += "vn \(n.x) \(n.y) \(n.z)\n"
        }
        obj += "\n"

        for face in faces {
            let indices = face.map { "\($0 + 1)//\($0 + 1)" }.joined(separator: " ")
            obj += "f \(indices)\n"
        }

        let fileName = "mesh_\(Int(Date().timeIntervalSince1970)).obj"
        let filePath = NSTemporaryDirectory() + fileName

        do {
            try obj.write(toFile: filePath, atomically: true, encoding: .utf8)
            return filePath
        } catch {
            return nil
        }
    }
}
