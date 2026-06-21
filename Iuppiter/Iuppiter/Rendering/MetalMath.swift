#if os(macOS)
import AppKit
import Foundation
import Metal
import simd
import SwiftUI

extension simd_float4x4 {
    static func identity() -> simd_float4x4 {
        matrix_identity_float4x4
    }

    static func scale(_ scale: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(scale.x, 0, 0, 0),
            SIMD4<Float>(0, scale.y, 0, 0),
            SIMD4<Float>(0, 0, scale.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func translation(_ translation: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))
    }

    static func rotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        let axis = normalize(axis)
        let ct = cos(radians)
        let st = sin(radians)
        let ci = 1 - ct
        let x = axis.x
        let y = axis.y
        let z = axis.z

        return simd_float4x4(columns: (
            SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
            SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
            SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func perspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovyRadians * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        let w = (near * far) / (near - far)

        return simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, w, 0)
        ))
    }

    static func perspectiveReversedZ(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovyRadians * 0.5)
        let x = y / aspect
        let z = near / (far - near)
        let w = (near * far) / (far - near)

        return simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, w, 0)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }
}

extension Color {
    var simdRGBA: SIMD4<Float> {
        #if os(macOS)
        let resolved = NSColor(self).usingColorSpace(.extendedSRGB) ?? .white
        return SIMD4<Float>(
            Float(resolved.redComponent),
            Float(resolved.greenComponent),
            Float(resolved.blueComponent),
            Float(resolved.alphaComponent)
        )
        #else
        return SIMD4<Float>(1, 1, 1, 1)
        #endif
    }
}

extension Bundle {
    func textureURL(named name: String) -> URL? {
        resourceURL(named: name, preferredSubdirectory: "Resources/Textures")
    }

    func modelURL(named name: String) -> URL? {
        resourceURL(named: name, preferredSubdirectory: "Resources/Models")
    }

    private func resourceURL(named name: String, preferredSubdirectory: String) -> URL? {
        guard !name.isEmpty else {
            return nil
        }

        let relativeCandidates = [
            name,
            "\(preferredSubdirectory)/\(name)"
        ]
        if let resourceURL {
            for candidate in relativeCandidates {
                let url = resourceURL.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        let nsName = name as NSString
        let stem = nsName.deletingPathExtension
        let ext = nsName.pathExtension
        let leafName = nsName.lastPathComponent
        let leaf = leafName as NSString
        let leafStem = leaf.deletingPathExtension

        if let url = url(forResource: stem, withExtension: ext) {
            return url
        }
        if let url = url(forResource: stem, withExtension: ext, subdirectory: preferredSubdirectory) {
            return url
        }

        let parent = nsName.deletingLastPathComponent
        if parent != ".", parent != "" {
            let nestedSubdirectory = "\(preferredSubdirectory)/\(parent)"
            if let url = url(forResource: leafStem, withExtension: ext, subdirectory: nestedSubdirectory) {
                return url
            }
        }

        return urls(forResourcesWithExtension: ext, subdirectory: nil)?
            .first { $0.lastPathComponent == leafName }
    }
}

enum SamplerCache {
    private static var sampler: MTLSamplerState?

    static func linearSampler(device: MTLDevice) -> MTLSamplerState? {
        if let sampler {
            return sampler
        }

        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .clampToEdge
        let state = device.makeSamplerState(descriptor: descriptor)
        sampler = state
        return state
    }
}

func rotateVector(_ vector: SIMD3<Float>, radians: Float, axis: SIMD3<Float>) -> SIMD3<Float> {
    let axis = normalize(axis)
    let cosAngle = cos(radians)
    let sinAngle = sin(radians)
    return vector * cosAngle + cross(axis, vector) * sinAngle + axis * dot(axis, vector) * (1 - cosAngle)
}
#endif
