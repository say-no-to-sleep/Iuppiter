#if os(macOS)
import Foundation
import MetalKit
import ModelIO
import simd

struct SphereVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>
}

struct ShapeMeshResource {
    let parts: [ShapeMeshPart]
    let normalizationTransform: simd_float4x4
    let usesProjectedTextureCoordinates: Bool
}

struct ShapeMeshPart {
    let vertexBuffer: MTLBuffer
    let vertexBufferOffset: Int
    let indexBuffer: MTLBuffer
    let indexBufferOffset: Int
    let indexCount: Int
    let indexType: MTLIndexType
}

final class RendererShapeMeshStore {
    private let device: MTLDevice
    private var shapeMeshCache: [String: ShapeMeshResource] = [:]

    init(device: MTLDevice) {
        self.device = device
    }

    func shapeMesh(named name: String) -> ShapeMeshResource? {
        if let cached = shapeMeshCache[name] {
            return cached
        }

        guard let url = Bundle.main.modelURL(named: name) ?? Bundle.main.textureURL(named: name) else {
            return nil
        }

        let resource: ShapeMeshResource?
        if url.pathExtension.lowercased() == "obj" {
            resource = objShapeMesh(url: url)
        } else if url.pathExtension.lowercased() == "msh" {
            resource = orbiterMshShapeMesh(url: url)
        } else {
            resource = modelIOShapeMesh(url: url)
        }

        if let resource {
            shapeMeshCache[name] = resource
        }
        return resource
    }

    private func objShapeMesh(url: URL) -> ShapeMeshResource? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(16_384)
        indices.reserveCapacity(65_536)

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("v ") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 4,
                      let x = Float(parts[1]),
                      let y = Float(parts[2]),
                      let z = Float(parts[3]) else {
                    continue
                }
                positions.append(SIMD3<Float>(x, y, z))
            } else if line.hasPrefix("f ") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 4 else {
                    continue
                }
                for part in parts[1...3] {
                    let vertexToken = part.split(separator: "/", omittingEmptySubsequences: false).first ?? part
                    guard let oneBasedIndex = UInt32(vertexToken), oneBasedIndex > 0 else {
                        continue
                    }
                    indices.append(oneBasedIndex - 1)
                }
            }
        }

        guard positions.count >= 3, indices.count >= 3, indices.count % 3 == 0 else {
            return nil
        }

        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for faceStart in stride(from: 0, to: indices.count, by: 3) {
            let ia = Int(indices[faceStart])
            let ib = Int(indices[faceStart + 1])
            let ic = Int(indices[faceStart + 2])
            guard ia < positions.count, ib < positions.count, ic < positions.count else {
                continue
            }
            let normal = cross(positions[ib] - positions[ia], positions[ic] - positions[ia])
            normals[ia] += normal
            normals[ib] += normal
            normals[ic] += normal
        }

        var vertices: [SphereVertex] = []
        vertices.reserveCapacity(positions.count)
        for index in positions.indices {
            let accumulatedNormal = normals[index]
            let fallbackNormal = length(positions[index]) > 0.0001 ? normalize(positions[index]) : SIMD3<Float>(0, 1, 0)
            let normal = length(accumulatedNormal) > 0.0001 ? normalize(accumulatedNormal) : fallbackNormal
            vertices.append(SphereVertex(position: positions[index], normal: normal, uv: SIMD2<Float>(0.5, 0.5)))
        }

        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<SphereVertex>.stride,
            options: [.storageModeShared]
        ),
        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.stride,
            options: [.storageModeShared]
        ) else {
            return nil
        }

        return ShapeMeshResource(
            parts: [
                ShapeMeshPart(
                    vertexBuffer: vertexBuffer,
                    vertexBufferOffset: 0,
                    indexBuffer: indexBuffer,
                    indexBufferOffset: 0,
                    indexCount: indices.count,
                    indexType: .uint32
                )
            ],
            normalizationTransform: normalizationTransform(for: positions),
            usesProjectedTextureCoordinates: true
        )
    }

    private func orbiterMshShapeMesh(url: URL) -> ShapeMeshResource? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("GEOM ") else {
                lineIndex += 1
                continue
            }

            let headerParts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard headerParts.count >= 3,
                  let vertexCount = Int(headerParts[1]),
                  let faceCount = Int(headerParts[2]) else {
                return nil
            }

            var vertices: [SphereVertex] = []
            var positions: [SIMD3<Float>] = []
            vertices.reserveCapacity(vertexCount)
            positions.reserveCapacity(vertexCount)
            lineIndex += 1

            for _ in 0..<vertexCount {
                guard lineIndex < lines.count else { return nil }
                let parts = lines[lineIndex].split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 8,
                      let x = Float(parts[0]),
                      let y = Float(parts[1]),
                      let z = Float(parts[2]),
                      let nx = Float(parts[3]),
                      let ny = Float(parts[4]),
                      let nz = Float(parts[5]),
                      let u = Float(parts[6]),
                      let v = Float(parts[7]) else {
                    return nil
                }

                let position = SIMD3<Float>(x, y, z)
                let rawNormal = SIMD3<Float>(nx, ny, nz)
                let fallbackNormal = length(position) > 0.0001 ? normalize(position) : SIMD3<Float>(0, 1, 0)
                let normal = length(rawNormal) > 0.0001 ? normalize(rawNormal) : fallbackNormal
                positions.append(position)
                vertices.append(SphereVertex(position: position, normal: normal, uv: SIMD2<Float>(u, v)))
                lineIndex += 1
            }

            var indices: [UInt32] = []
            indices.reserveCapacity(faceCount * 3)
            for _ in 0..<faceCount {
                guard lineIndex < lines.count else { return nil }
                let parts = lines[lineIndex].split(whereSeparator: { $0 == " " || $0 == "\t" })
                let vertexCountLimit = UInt32(vertexCount)
                guard parts.count >= 3,
                      let a = UInt32(parts[0]),
                      let b = UInt32(parts[1]),
                      let c = UInt32(parts[2]),
                      a < vertexCountLimit,
                      b < vertexCountLimit,
                      c < vertexCountLimit else {
                    return nil
                }
                indices.append(a)
                indices.append(b)
                indices.append(c)
                lineIndex += 1
            }

            guard let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<SphereVertex>.stride,
                options: [.storageModeShared]
            ),
            let indexBuffer = device.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt32>.stride,
                options: [.storageModeShared]
            ) else {
                return nil
            }

            return ShapeMeshResource(
                parts: [
                    ShapeMeshPart(
                        vertexBuffer: vertexBuffer,
                        vertexBufferOffset: 0,
                        indexBuffer: indexBuffer,
                        indexBufferOffset: 0,
                        indexCount: indices.count,
                        indexType: .uint32
                    )
                ],
                normalizationTransform: normalizationTransform(for: positions),
                usesProjectedTextureCoordinates: false
            )
        }

        return nil
    }

    private func modelIOShapeMesh(url: URL) -> ShapeMeshResource? {
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: MemoryLayout<SIMD3<Float>>.stride,
            bufferIndex: 0
        )
        vertexDescriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: MemoryLayout<SIMD3<Float>>.stride * 2,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SphereVertex>.stride)

        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: vertexDescriptor, bufferAllocator: allocator)
        let mdlMeshes = asset.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
        guard !mdlMeshes.isEmpty else {
            return nil
        }

        var parts: [ShapeMeshPart] = []
        var minBounds = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)

        for mdlMesh in mdlMeshes {
            if mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3) == nil {
                mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.4)
            }

            updateBounds(from: mdlMesh.boundingBox, minBounds: &minBounds, maxBounds: &maxBounds)
            guard let mtkMesh = try? MTKMesh(mesh: mdlMesh, device: device),
                  let vertexBuffer = mtkMesh.vertexBuffers.first else {
                continue
            }

            for submesh in mtkMesh.submeshes where submesh.indexCount > 0 {
                parts.append(
                    ShapeMeshPart(
                        vertexBuffer: vertexBuffer.buffer,
                        vertexBufferOffset: vertexBuffer.offset,
                        indexBuffer: submesh.indexBuffer.buffer,
                        indexBufferOffset: submesh.indexBuffer.offset,
                        indexCount: submesh.indexCount,
                        indexType: submesh.indexType
                    )
                )
            }
        }

        guard !parts.isEmpty else {
            return nil
        }

        return ShapeMeshResource(
            parts: parts,
            normalizationTransform: normalizationTransform(minBounds: minBounds, maxBounds: maxBounds),
            usesProjectedTextureCoordinates: true
        )
    }

    private func updateBounds(
        from box: MDLAxisAlignedBoundingBox,
        minBounds: inout SIMD3<Float>,
        maxBounds: inout SIMD3<Float>
    ) {
        let boxMin = SIMD3<Float>(box.minBounds.x, box.minBounds.y, box.minBounds.z)
        let boxMax = SIMD3<Float>(box.maxBounds.x, box.maxBounds.y, box.maxBounds.z)
        minBounds = SIMD3<Float>(
            Swift.min(minBounds.x, boxMin.x),
            Swift.min(minBounds.y, boxMin.y),
            Swift.min(minBounds.z, boxMin.z)
        )
        maxBounds = SIMD3<Float>(
            Swift.max(maxBounds.x, boxMax.x),
            Swift.max(maxBounds.y, boxMax.y),
            Swift.max(maxBounds.z, boxMax.z)
        )
    }

    private func normalizationTransform(for positions: [SIMD3<Float>]) -> simd_float4x4 {
        guard let first = positions.first else {
            return .identity()
        }

        var minBounds = first
        var maxBounds = first
        for position in positions.dropFirst() {
            minBounds = SIMD3<Float>(
                Swift.min(minBounds.x, position.x),
                Swift.min(minBounds.y, position.y),
                Swift.min(minBounds.z, position.z)
            )
            maxBounds = SIMD3<Float>(
                Swift.max(maxBounds.x, position.x),
                Swift.max(maxBounds.y, position.y),
                Swift.max(maxBounds.z, position.z)
            )
        }
        return normalizationTransform(minBounds: minBounds, maxBounds: maxBounds)
    }

    private func normalizationTransform(
        minBounds: SIMD3<Float>,
        maxBounds: SIMD3<Float>
    ) -> simd_float4x4 {
        guard minBounds.x.isFinite,
              minBounds.y.isFinite,
              minBounds.z.isFinite,
              maxBounds.x.isFinite,
              maxBounds.y.isFinite,
              maxBounds.z.isFinite else {
            return .identity()
        }

        let center = (minBounds + maxBounds) * 0.5
        let extent = maxBounds - minBounds
        let radius = Swift.max(extent.x, Swift.max(extent.y, extent.z)) * 0.5
        guard radius > 0.0001 else {
            return .identity()
        }

        return simd_float4x4.scale(SIMD3<Float>(repeating: 1.0 / radius))
            * simd_float4x4.translation(-center)
    }
}
#endif
