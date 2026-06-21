#if os(macOS)
import Foundation
import ImageIO
import MetalKit
import ModelIO
import simd
import UniformTypeIdentifiers

private struct SphereVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>
}

private struct OrbitVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}

private struct FlareVertex {
    var position: SIMD2<Float>
    var local: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct RenderUniforms {
    var modelMatrix: simd_float4x4
    var viewProjectionMatrix: simd_float4x4
    var normalMatrix: simd_float4x4
    var sunDirection: SIMD4<Float>
    var tintColor: SIMD4<Float>
    var cameraPosition: SIMD4<Float>     // camera world position (focus-relative)
    var opacity: Float
    var layerKind: Float
    var specularRoughness: Float         // [0=mirror, 1=diffuse]; star draws: unused
    var starCameraDistance: Float        // star draws: camera-to-star distance
    var bumpStrength: Float
    var specularMapStrength: Float
    var hasBumpMap: Float
    var hasSpecularMap: Float
    var textureProjection: Float
    var bumpMapIsNormalMap: Float
    var emissionMapStrength: Float
    var hasEmissionMap: Float
    var surfaceTintStrength: Float
}

private struct OrbitUniforms {
    var viewProjectionMatrix: simd_float4x4
}

private struct LightingOccluder {
    var positionRadius: SIMD4<Float>
}

private struct LightingParameters {
    var sunPositionRadius: SIMD4<Float>
    var occluderCount: Int32
    var selfOccluderIndex: Int32
    var padding: SIMD2<Float>
}

private struct ShapeMeshResource {
    let parts: [ShapeMeshPart]
    let normalizationTransform: simd_float4x4
    let usesProjectedTextureCoordinates: Bool
}

private struct ShapeMeshPart {
    let vertexBuffer: MTLBuffer
    let vertexBufferOffset: Int
    let indexBuffer: MTLBuffer
    let indexBufferOffset: Int
    let indexCount: Int
    let indexType: MTLIndexType
}

private struct LightingContext {
    let occluders: [LightingOccluder]
    let occluderIndicesByBodyID: [String: Int32]
    let sunPosition: SIMD3<Float>
    let sunRadius: Float
}

private struct PhotoRenderTarget {
    let renderPassDescriptor: MTLRenderPassDescriptor
    let colorTexture: MTLTexture
}

private struct CameraFrame {
    let eye: SIMD3<Float>
    let target: SIMD3<Float>
    let up: SIMD3<Float>
}

private struct CameraProjectionMetrics {
    let nearPlane: Float
    let farPlane: Float
    let fovyRadians: Float
    let skyScale: Float
}

private enum RemoteTextureProcessing: Hashable {
    /// Load the downloaded bytes verbatim via MTKTextureLoader.
    case raw
    /// Extract a single cloud-density channel from the source image. The real
    /// cloud mask in maps like Matt Eason's `clouds-alpha.png` lives in the
    /// alpha channel (the luminance channel is a land/sea overlay and is useless
    /// as a mask), and MTKTextureLoader's decode of luminance+alpha PNGs does
    /// not reliably surface that alpha to the shader — so we decode and extract
    /// it on the CPU into a clean grayscale texture.
    case cloudDensity
}

private struct RemoteTextureKey: Hashable {
    let urlString: String
    let isSRGB: Bool
    let processing: RemoteTextureProcessing
}

private final class RemoteTextureEntry {
    var texture: MTLTexture?
    // Sentinel in the distant past so a brand-new entry always refreshes on its
    // first use, regardless of how large the refresh interval is or how recently
    // the machine booted (timestamps are seconds-since-boot, not wall clock).
    var lastRequestTime: CFTimeInterval = -.greatestFiniteMagnitude
    var isLoading = false
}

/// Describes a planet's equatorial ring plane for ring-shadow projection onto the surface.
private struct RingShadow {
    var planeNormal: SIMD4<Float>   // xyz = world-space normal, w = 1 if ring present
    var planetCenter: SIMD4<Float>  // xyz = planet centre (focus-relative), w = inner radius
    var outerRadius: Float
    var pad0: Float
    var pad1: Float
    var pad2: Float

    init(planeNormal: SIMD4<Float>, planetCenter: SIMD4<Float>, outerRadius: Float) {
        self.planeNormal  = planeNormal
        self.planetCenter = planetCenter
        self.outerRadius  = outerRadius
        self.pad0 = 0; self.pad1 = 0; self.pad2 = 0
    }
}

private extension PlanetRenderer {
    static let emptyRingShadow = RingShadow(
        planeNormal:  SIMD4<Float>(0, 1, 0, 0), // w = 0 → disabled
        planetCenter: SIMD4<Float>(0, 0, 0, 0),
        outerRadius:  0
    )
}

final class PlanetRenderer: NSObject, MTKViewDelegate, MetalCameraInputDelegate {
    private static let maxLightingOccluders = 32
    private static let skyTextureName = "16k_deep_star_map.jpg"
    private static let j2000MeanObliquityRadians = Float(23.4392911 * .pi / 180.0)

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureLoader: MTKTextureLoader
    private let spherePipelineState: MTLRenderPipelineState
    private let ringPipelineState: MTLRenderPipelineState
    private let orbitPipelineState: MTLRenderPipelineState
    private let flarePipelineState: MTLRenderPipelineState
    private let opaqueDepthState: MTLDepthStencilState
    private let transparentDepthState: MTLDepthStencilState
    private let overlayDepthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private let indexCount: Int
    private let ringVertexBuffer: MTLBuffer
    private let ringIndexBuffer: MTLBuffer
    private let ringIndexCount: Int
    private let fallbackTexture: MTLTexture
    private var textureCache: [String: MTLTexture] = [:]
    private var dataTextureCache: [String: MTLTexture] = [:]
    private var remoteTextureCache: [RemoteTextureKey: RemoteTextureEntry] = [:]
    private let remoteTextureLock = NSLock()
    private var shapeMeshCache: [String: ShapeMeshResource] = [:]
    private var orbitVertexBufferCache: [String: MTLBuffer] = [:]

    private var selectedBodyID = NativeBodyCatalog.defaultSelection.id
    private var cameraDistance: Float = 72
    private var cameraYaw: Float = 0
    private var cameraPitch: Float = 0.32
    private var cameraTargetOffset = SIMD3<Float>(repeating: 0)
    private var timeRate: Double = 1.0
    private var isPaused = false
    private var isLiveView = true
    private var simulatedSeconds: Double = SolarSystemSimulation.simulatedSeconds()
    private var lastFrameTime = CACurrentMediaTime()
    weak var viewport: SolarSystemViewport?
    private var options = NativeRenderOptions()
    private var observationMode: ObservationMode = .orbit
    private var planetariumLocation = PlanetariumLocation.waterloo
    private var lockedBodyID: String? = NativeBodyCatalog.defaultSelection.id
    private var lastSimulationDateReportTime: CFTimeInterval = -.greatestFiniteMagnitude
    private var lastReportedPlanetariumHeading: Double?
    private var liveBlendStartSeconds: Double?
    private var liveBlendStartTime: CFTimeInterval = 0
    private var pendingPhotoCapture = false
    var onZoom: ((Float) -> Void)?
    var onSimulationDateChange: ((Date) -> Void)?
    var onPlanetariumHeadingChange: ((Double) -> Void)?
    var onBodyPick: ((String?) -> Void)?

    init?(device: MTLDevice, metalView: MTKView) {
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)

        let mesh = SphereMesh.make(latitudeBands: 72, longitudeBands: 144)
        let ringMesh = RingMesh.make(segments: 192)
        guard let vertexBuffer = device.makeBuffer(
            bytes: mesh.vertices,
            length: mesh.vertices.count * MemoryLayout<SphereVertex>.stride,
            options: [.storageModeShared]
        ),
        let indexBuffer = device.makeBuffer(
            bytes: mesh.indices,
            length: mesh.indices.count * MemoryLayout<UInt32>.stride,
            options: [.storageModeShared]
        ),
        let ringVertexBuffer = device.makeBuffer(
            bytes: ringMesh.vertices,
            length: ringMesh.vertices.count * MemoryLayout<SphereVertex>.stride,
            options: [.storageModeShared]
        ),
        let ringIndexBuffer = device.makeBuffer(
            bytes: ringMesh.indices,
            length: ringMesh.indices.count * MemoryLayout<UInt32>.stride,
            options: [.storageModeShared]
        ) else {
            return nil
        }
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = mesh.indices.count
        self.ringVertexBuffer = ringVertexBuffer
        self.ringIndexBuffer = ringIndexBuffer
        self.ringIndexCount = ringMesh.indices.count

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: MetalShaderSource.planet, options: nil)
        } catch {
            return nil
        }
        guard let planetVertex = library.makeFunction(name: "planetVertex"),
              let planetFragment = library.makeFunction(name: "planetFragment"),
              let ringFragment = library.makeFunction(name: "ringFragment"),
              let orbitVertex = library.makeFunction(name: "orbitVertex"),
              let orbitFragment = library.makeFunction(name: "orbitFragment"),
              let flareVertex = library.makeFunction(name: "flareVertex"),
              let flareFragment = library.makeFunction(name: "flareFragment") else {
            return nil
        }

        let sphereVertexDescriptor = MTLVertexDescriptor()
        sphereVertexDescriptor.attributes[0].format = .float3
        sphereVertexDescriptor.attributes[0].offset = 0
        sphereVertexDescriptor.attributes[0].bufferIndex = 0
        sphereVertexDescriptor.attributes[1].format = .float3
        sphereVertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        sphereVertexDescriptor.attributes[1].bufferIndex = 0
        sphereVertexDescriptor.attributes[2].format = .float2
        sphereVertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        sphereVertexDescriptor.attributes[2].bufferIndex = 0
        sphereVertexDescriptor.layouts[0].stride = MemoryLayout<SphereVertex>.stride

        let spherePipelineDescriptor = MTLRenderPipelineDescriptor()
        spherePipelineDescriptor.vertexFunction = planetVertex
        spherePipelineDescriptor.fragmentFunction = planetFragment
        spherePipelineDescriptor.vertexDescriptor = sphereVertexDescriptor
        spherePipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        spherePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        spherePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        spherePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        spherePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        spherePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        spherePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        spherePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        spherePipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat

        let ringPipelineDescriptor = MTLRenderPipelineDescriptor()
        ringPipelineDescriptor.vertexFunction = planetVertex
        ringPipelineDescriptor.fragmentFunction = ringFragment
        ringPipelineDescriptor.vertexDescriptor = sphereVertexDescriptor
        ringPipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        ringPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        ringPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        ringPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        ringPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        ringPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        ringPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        ringPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        ringPipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat

        let orbitPipelineDescriptor = MTLRenderPipelineDescriptor()
        orbitPipelineDescriptor.vertexFunction = orbitVertex
        orbitPipelineDescriptor.fragmentFunction = orbitFragment
        orbitPipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        orbitPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        orbitPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        orbitPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        orbitPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        orbitPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        orbitPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        orbitPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        orbitPipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat

        let flarePipelineDescriptor = MTLRenderPipelineDescriptor()
        flarePipelineDescriptor.vertexFunction = flareVertex
        flarePipelineDescriptor.fragmentFunction = flareFragment
        flarePipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        flarePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        flarePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        flarePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        flarePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        flarePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        flarePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        flarePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        flarePipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat

        do {
            self.spherePipelineState = try device.makeRenderPipelineState(descriptor: spherePipelineDescriptor)
            self.ringPipelineState = try device.makeRenderPipelineState(descriptor: ringPipelineDescriptor)
            self.orbitPipelineState = try device.makeRenderPipelineState(descriptor: orbitPipelineDescriptor)
            self.flarePipelineState = try device.makeRenderPipelineState(descriptor: flarePipelineDescriptor)
        } catch {
            return nil
        }

        let opaqueDepthDescriptor = MTLDepthStencilDescriptor()
        opaqueDepthDescriptor.depthCompareFunction = .greater
        opaqueDepthDescriptor.isDepthWriteEnabled = true

        let transparentDepthDescriptor = MTLDepthStencilDescriptor()
        transparentDepthDescriptor.depthCompareFunction = .greaterEqual
        transparentDepthDescriptor.isDepthWriteEnabled = false

        let overlayDepthDescriptor = MTLDepthStencilDescriptor()
        overlayDepthDescriptor.depthCompareFunction = .always
        overlayDepthDescriptor.isDepthWriteEnabled = false

        guard let opaqueDepthState = device.makeDepthStencilState(descriptor: opaqueDepthDescriptor),
              let transparentDepthState = device.makeDepthStencilState(descriptor: transparentDepthDescriptor),
              let overlayDepthState = device.makeDepthStencilState(descriptor: overlayDepthDescriptor),
              let fallbackTexture = PlanetRenderer.makeFallbackTexture(device: device) else {
            return nil
        }
        self.opaqueDepthState = opaqueDepthState
        self.transparentDepthState = transparentDepthState
        self.overlayDepthState = overlayDepthState
        self.fallbackTexture = fallbackTexture

        super.init()
    }

    func update(
        body: NativeCelestialBody,
        cameraDistance: Float,
        timeRate: Double,
        isPaused: Bool,
        isLiveView: Bool,
        options: NativeRenderOptions,
        observationMode: ObservationMode,
        planetariumLocation: PlanetariumLocation,
        lockedBodyID: String?
    ) {
        if selectedBodyID != body.id {
            selectedBodyID = body.id
            cameraTargetOffset = .zero
        }
        if self.cameraDistance != cameraDistance {
            self.cameraDistance = cameraDistance
        }
        if self.timeRate != timeRate {
            self.timeRate = timeRate
        }
        if self.isPaused != isPaused {
            self.isPaused = isPaused
        }
        if self.isLiveView != isLiveView {
            if isLiveView {
                liveBlendStartSeconds = simulatedSeconds
                liveBlendStartTime = CACurrentMediaTime()
            } else {
                liveBlendStartSeconds = nil
            }
            self.isLiveView = isLiveView
        }
        if self.observationMode != observationMode {
            self.observationMode = observationMode
            cameraTargetOffset = .zero
            if observationMode == .planetarium {
                cameraYaw = 0
                cameraPitch = max(cameraPitch, 0.85)
                reportPlanetariumHeading()
            }
        }
        self.planetariumLocation = planetariumLocation.clamped
        if self.lockedBodyID != lockedBodyID {
            self.lockedBodyID = lockedBodyID
            cameraTargetOffset = .zero
        }
        self.options = options
    }

    func jumpToToday() {
        jump(to: Date())
    }

    func jump(to date: Date) {
        simulatedSeconds = SolarSystemSimulation.simulatedSeconds(for: date)
        reportSimulationDate(force: true, at: CACurrentMediaTime())
    }

    func rotateCamera(deltaX: Float, deltaY: Float, viewportSize: CGSize) {
        if observationMode == .planetarium, lockedBodyID != nil {
            clearBodyLockFromRenderer()
        }

        let angularMotion = dragAngularMotion(deltaX: deltaX, deltaY: deltaY, viewportSize: viewportSize)
        cameraYaw -= angularMotion.x
        let nextPitch = cameraPitch + angularMotion.y
        if observationMode == .planetarium {
            cameraPitch = min(1.45, max(-0.10, nextPitch))
            reportPlanetariumHeading()
        } else {
            cameraPitch = min(1.28, max(-1.20, nextPitch))
        }
    }

    func zoomCamera(delta: Float) {
        let zoomFactor = exp(-delta * 0.012)
        if observationMode == .planetarium {
            cameraDistance = min(400.0, max(1.0, cameraDistance / zoomFactor))
        } else {
            cameraDistance = min(260.0, max(0.00001, cameraDistance * zoomFactor))
        }
        onZoom?(cameraDistance)
    }

    private func dragAngularMotion(deltaX: Float, deltaY: Float, viewportSize: CGSize) -> SIMD2<Float> {
        let width = max(Float(viewportSize.width), 1)
        let height = max(Float(viewportSize.height), 1)
        let aspect = max(width / height, 0.01)
        let fovy = currentCameraFovyRadians()
        let fovx = 2.0 * atan(tan(fovy * 0.5) * aspect)

        return SIMD2<Float>(
            deltaX * fovx / width,
            deltaY * fovy / height
        )
    }

    private func currentCameraFovyRadians() -> Float {
        if observationMode == .planetarium {
            return planetariumFovyRadians(for: cameraDistance)
        }
        return .pi / 4.0
    }

    private func planetariumFovyRadians(for magnification: Float) -> Float {
        let normalizedMagnification = min(400.0, max(1.0, magnification))
        let baseFovy = Float.pi / 2.0
        return max(degreesToRadians(0.08), baseFovy / normalizedMagnification)
    }

    private func activeFocusBodyID() -> String {
        if let lockedBodyID {
            return lockedBodyID
        }
        if observationMode == .planetarium {
            return "earth"
        }
        return NativeBodyCatalog.defaultSelection.id
    }

    private func clearBodyLockFromRenderer() {
        lockedBodyID = nil
        selectedBodyID = observationMode == .planetarium ? "earth" : NativeBodyCatalog.defaultSelection.id
        cameraTargetOffset = .zero
        reportPlanetariumHeading()
        onBodyPick?(nil)
    }

    func pickBody(at point: CGPoint, viewportSize: CGSize) {
        let snapshot = SolarSystemSimulation.snapshot(
            elapsedSeconds: simulatedSeconds,
            selectedBodyID: activeFocusBodyID(),
            options: options
        )
        let focusState = cameraFocusState(in: snapshot)
        let focus = focusState.position
        let aspect = max(Float(viewportSize.width / max(viewportSize.height, 1)), 0.01)
        let projectionMetrics = cameraProjectionMetrics(for: focusState)
        let projection = simd_float4x4.perspectiveReversedZ(
            fovyRadians: projectionMetrics.fovyRadians,
            aspect: aspect,
            near: projectionMetrics.nearPlane,
            far: projectionMetrics.farPlane
        )
        let cameraFrame = cameraFrame(for: focusState, snapshot: snapshot)
        let viewMatrix = simd_float4x4.lookAt(
            eye: cameraFrame.eye,
            target: cameraFrame.target,
            up: cameraFrame.up
        )
        let viewProjection = projection * viewMatrix
        let hiddenBodyIDs = visuallyOccludedBodyIDs(
            states: snapshot.states,
            focus: focus,
            cameraPosition: cameraFrame.eye
        )

        if let bodyID = pickedBodyID(
            at: point,
            viewportSize: viewportSize,
            snapshot: snapshot,
            viewProjection: viewProjection,
            focus: focus,
            cameraPosition: cameraFrame.eye,
            fovyRadians: projectionMetrics.fovyRadians,
            hiddenBodyIDs: hiddenBodyIDs
        ) {
            selectedBodyID = bodyID
            lockedBodyID = bodyID
            cameraTargetOffset = .zero
            reportPlanetariumHeading()
            onBodyPick?(bodyID)
        } else {
            clearBodyLockFromRenderer()
        }
    }

    func movePhotoCamera(_ move: PhotoCameraMove) {
        let panStep = max(cameraDistance * 0.0035, 0.00005)
        let pitchStep: Float = 0.025
        let horizontalDistance = cos(cameraPitch)
        let cameraOffsetDirection = normalize(SIMD3<Float>(
            sin(cameraYaw) * horizontalDistance,
            sin(cameraPitch),
            cos(cameraYaw) * horizontalDistance
        ))
        let forward = -cameraOffsetDirection
        let right = normalize(SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw)))
        let up = normalize(cross(right, forward))

        switch move {
        case .forward:
            cameraTargetOffset += up * panStep
        case .backward:
            cameraTargetOffset -= up * panStep
        case .left:
            cameraTargetOffset -= right * panStep
        case .right:
            cameraTargetOffset += right * panStep
        case .up:
            cameraPitch = min(1.28, cameraPitch + pitchStep)
        case .down:
            cameraPitch = max(-1.20, cameraPitch - pitchStep)
        }
    }

    func requestPhotoCapture() {
        pendingPhotoCapture = true
    }

    private func reportSimulationDate(force: Bool, at timestamp: CFTimeInterval) {
        guard force || timestamp - lastSimulationDateReportTime >= 0.25 else {
            return
        }

        lastSimulationDateReportTime = timestamp
        onSimulationDateChange?(SolarSystemSimulation.date(forSimulatedSeconds: simulatedSeconds))
    }

    private func reportPlanetariumHeading() {
        guard observationMode == .planetarium else {
            return
        }

        var degrees = Double(cameraYaw * 180.0 / .pi).truncatingRemainder(dividingBy: 360)
        if degrees < 0 {
            degrees += 360
        }
        if let lastReportedPlanetariumHeading,
           abs(lastReportedPlanetariumHeading - degrees) < 0.1 {
            return
        }
        lastReportedPlanetariumHeading = degrees
        onPlanetariumHeadingChange?(degrees)
    }

    private func updateLiveSimulationSeconds(at timestamp: CFTimeInterval) {
        let targetSeconds = SolarSystemSimulation.simulatedSeconds()
        guard let blendStartSeconds = liveBlendStartSeconds else {
            simulatedSeconds = targetSeconds
            return
        }

        let progress = min(1.0, max(0.0, (timestamp - liveBlendStartTime) / 1.4))
        let easedProgress = progress * progress * (3.0 - 2.0 * progress)
        simulatedSeconds = blendStartSeconds + (targetSeconds - blendStartSeconds) * easedProgress

        if progress >= 1.0 {
            liveBlendStartSeconds = nil
            simulatedSeconds = targetSeconds
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let shouldCapturePhoto = pendingPhotoCapture
        if shouldCapturePhoto {
            pendingPhotoCapture = false
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let photoRenderTarget: PhotoRenderTarget?
        let renderPassDescriptor: MTLRenderPassDescriptor
        let drawable: CAMetalDrawable?
        if shouldCapturePhoto {
            guard let target = makePhotoRenderTarget(
                size: view.drawableSize,
                colorPixelFormat: view.colorPixelFormat,
                depthPixelFormat: view.depthStencilPixelFormat,
                clearColor: view.clearColor,
                clearDepth: view.clearDepth
            ) else {
                return
            }
            photoRenderTarget = target
            renderPassDescriptor = target.renderPassDescriptor
            drawable = nil
        } else {
            guard let descriptor = view.currentRenderPassDescriptor,
                  let currentDrawable = view.currentDrawable else {
                return
            }
            photoRenderTarget = nil
            renderPassDescriptor = descriptor
            drawable = currentDrawable
        }

        let now = CACurrentMediaTime()
        let frameDelta = max(0, min(now - lastFrameTime, 0.25))
        lastFrameTime = now

        if isLiveView {
            updateLiveSimulationSeconds(at: now)
        } else {
            if !isPaused {
                simulatedSeconds += frameDelta
                    * max(timeRate, 0.0)
                    / SolarSystemSimulation.calendarSecondsPerSimulationSecond
            }
        }
        reportSimulationDate(force: false, at: now)

        let elapsed = simulatedSeconds
        let snapshot = SolarSystemSimulation.snapshot(
            elapsedSeconds: elapsed,
            selectedBodyID: activeFocusBodyID(),
            options: options
        )
        let focusState = cameraFocusState(in: snapshot)
        let focus = focusState.position
        let lightingContext = lightingContext(for: snapshot, focus: focus)

        let aspect = max(Float(view.drawableSize.width / max(view.drawableSize.height, 1)), 0.01)
        let projectionMetrics = cameraProjectionMetrics(for: focusState)
        let nearPlane = projectionMetrics.nearPlane
        let farPlane = projectionMetrics.farPlane
        let projection = simd_float4x4.perspectiveReversedZ(
            fovyRadians: projectionMetrics.fovyRadians,
            aspect: aspect,
            near: nearPlane,
            far: farPlane
        )
        let cameraFrame = cameraFrame(for: focusState, snapshot: snapshot)
        let eyeRelative = cameraFrame.eye
        let cameraToSunDist = length(lightingContext.sunPosition - eyeRelative)
        let viewMatrix = simd_float4x4.lookAt(
            eye: eyeRelative,
            target: cameraFrame.target,
            up: cameraFrame.up
        )
        let viewProjection = projection * viewMatrix
        let visuallyOccludedBodyIDs = visuallyOccludedBodyIDs(
            states: snapshot.states,
            focus: focus,
            cameraPosition: eyeRelative
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        if options.showLabels {
            updateLabels(
                snapshot: snapshot,
                viewProjection: viewProjection,
                viewportSize: view.bounds.size,
                focus: focus,
                hiddenBodyIDs: visuallyOccludedBodyIDs
            )
        } else {
            DispatchQueue.main.async { [weak viewport] in
                viewport?.update(labels: [])
            }
        }

        encoder.setFragmentSamplerState(SamplerCache.linearSampler(device: device), index: 0)
        drawSkyBackground(
            encoder: encoder,
            cameraWorldPos: eyeRelative,
            viewProjection: viewProjection,
            radius: min(farPlane * 0.45, max(900.0, projectionMetrics.skyScale * 40.0))
        )

        if options.showOrbits {
            drawOrbitLines(encoder: encoder, snapshot: snapshot, viewProjection: viewProjection, focus: focus)
        }

        encoder.setRenderPipelineState(spherePipelineState)
        encoder.setDepthStencilState(opaqueDepthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        for state in snapshot.states {
            if visuallyOccludedBodyIDs.contains(state.body.id) {
                continue
            }

            let isProcedural = state.body.assetTier == "procedural"
            let isStar       = state.body.kind == .star
            let bodyPos      = state.position - focus
            let starCameraDistance: Float = isStar
                ? cameraToSunDist
                : 0.0
            let shadow  = isStar ? Self.emptyRingShadow : makeRingShadow(for: state, position: bodyPos)
            let ringTex = state.body.ring.map { texture(named: $0.textureName) } ?? fallbackTexture
            let surfaceTex = liveSurfaceTexture(for: state.body, at: now)
                ?? texture(named: state.body.textureName)
            if !isStar,
               let shapeModelName = state.body.shapeModelName,
               let shapeMesh = shapeMesh(named: shapeModelName) {
                drawShapeModel(
                    encoder: encoder,
                    mesh: shapeMesh,
                    state: state,
                    position: bodyPos,
                    sceneRadius: state.sceneRadius,
                    texture: surfaceTex,
                    opacity: 1.0,
                    layerKind: isProcedural ? 4.0 : 0.0,
                    rotationMultiplier: 1.0,
                    viewProjection: viewProjection,
                    lightingContext: lightingContext,
                    cameraWorldPos: eyeRelative,
                    specularRoughness: state.body.specularRoughness,
                    materialMaps: state.body.materialMaps,
                    ringShadow: shadow,
                    ringTexture: ringTex
                )
            } else {
                drawSphere(
                    encoder: encoder,
                    state: state,
                    position: bodyPos,
                    sceneRadius: state.sceneRadius,
                    texture: surfaceTex,
                    opacity: 1.0,
                    layerKind: isProcedural ? 4.0 : (isStar ? 3.0 : 0.0),
                    rotationMultiplier: 1.0,
                    viewProjection: viewProjection,
                    lightingContext: lightingContext,
                    cameraWorldPos: eyeRelative,
                    specularRoughness: state.body.specularRoughness,
                    starCameraDistance: starCameraDistance,
                    materialMaps: state.body.materialMaps,
                    ringShadow: shadow,
                    ringTexture: ringTex
                )
            }
        }

        encoder.setDepthStencilState(transparentDepthState)
        encoder.setRenderPipelineState(ringPipelineState)
        encoder.setVertexBuffer(ringVertexBuffer, offset: 0, index: 0)
        for state in snapshot.states where state.body.ring != nil {
            if visuallyOccludedBodyIDs.contains(state.body.id) {
                continue
            }

            drawRing(
                encoder: encoder,
                state: state,
                position: state.position - focus,
                viewProjection: viewProjection,
                lightingContext: lightingContext,
                cameraWorldPos: eyeRelative
            )
        }

        encoder.setRenderPipelineState(spherePipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        for state in snapshot.states where state.body.kind != .star {
            if visuallyOccludedBodyIDs.contains(state.body.id) {
                continue
            }

            for layer in state.body.cloudLayers {
                guard let cloudTexture = cloudTexture(for: layer, at: now) else {
                    continue
                }

                encoder.setRenderPipelineState(spherePipelineState)
                encoder.setDepthStencilState(transparentDepthState)
                encoder.setFrontFacing(.clockwise)
                encoder.setCullMode(.back)
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                drawSphere(
                    encoder: encoder,
                    state: state,
                    position: state.position - focus,
                    sceneRadius: state.sceneRadius * layer.radiusScale,
                    texture: cloudTexture,
                    opacity: layer.opacity,
                    layerKind: 1.0,
                    rotationMultiplier: layer.rotationRateMultiplier,
                    viewProjection: viewProjection,
                    lightingContext: lightingContext,
                    cameraWorldPos: eyeRelative,
                    specularRoughness: 1.0,
                    starCameraDistance: 0,
                    materialMaps: .none,
                    ringShadow: Self.emptyRingShadow,
                    ringTexture: fallbackTexture
                )
                encoder.setCullMode(.none)
            }
        }

        drawSunLensFlare(
            encoder: encoder,
            sunPosition: lightingContext.sunPosition,
            cameraPosition: eyeRelative,
            states: snapshot.states,
            focus: focus,
            viewProjection: viewProjection,
            aspect: aspect
        )

        encoder.endEncoding()
        if let photoRenderTarget {
            captureTexture(photoRenderTarget.colorTexture, commandBuffer: commandBuffer)
        } else if let drawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    private func makePhotoRenderTarget(
        size: CGSize,
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat,
        clearColor: MTLClearColor,
        clearDepth: Double
    ) -> PhotoRenderTarget? {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.storageMode = .private
        colorDescriptor.usage = [.renderTarget]

        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDescriptor.storageMode = .private
        depthDescriptor.usage = [.renderTarget]

        guard let colorTexture = device.makeTexture(descriptor: colorDescriptor),
              let depthTexture = device.makeTexture(descriptor: depthDescriptor) else {
            return nil
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = clearDepth

        return PhotoRenderTarget(
            renderPassDescriptor: renderPassDescriptor,
            colorTexture: colorTexture
        )
    }

    private func captureTexture(_ sourceTexture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: sourceTexture.pixelFormat,
            width: sourceTexture.width,
            height: sourceTexture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared

        guard let readbackTexture = device.makeTexture(descriptor: descriptor),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder(),
              let outputURL = Self.makePhotoOutputURL() else {
            return
        }

        blitEncoder.copy(
            from: sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: 1),
            to: readbackTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            Self.writePNG(texture: readbackTexture, to: outputURL)
        }
    }

    private static func makePhotoOutputURL() -> URL? {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        let outputDirectory = baseDirectory.appendingPathComponent("Iuppiter Photos", isDirectory: true)

        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let timestamp = formatter.string(from: Date())
        return outputDirectory.appendingPathComponent("Iuppiter-\(timestamp).png")
    }

    private static func writePNG(texture: MTLTexture, to url: URL) {
        let bytesPerPixel = 4
        let bytesPerRow = texture.width * bytesPerPixel
        let byteCount = bytesPerRow * texture.height
        var imageData = Data(count: byteCount)
        imageData.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            texture.getBytes(
                baseAddress,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }

        guard let provider = CGDataProvider(data: imageData as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: texture.width,
                height: texture.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }

        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private func drawSkyBackground(
        encoder: MTLRenderCommandEncoder,
        cameraWorldPos: SIMD3<Float>,
        viewProjection: simd_float4x4,
        radius: Float
    ) {
        // NASA's deep star map is an equirectangular celestial/equatorial map
        // centered at RA 0h. The simulation uses +Y as ecliptic north, so tilt
        // the map from J2000 equatorial north to ecliptic north. The pi Y-rotation
        // compensates for the sphere mesh UV convention: texture center maps to -X.
        let raZeroToEclipticX = simd_float4x4.rotation(radians: .pi, axis: SIMD3<Float>(0, 1, 0))
        let equatorialToEcliptic = simd_float4x4.rotation(
            radians: -Self.j2000MeanObliquityRadians,
            axis: SIMD3<Float>(1, 0, 0)
        )
        let model = simd_float4x4.translation(cameraWorldPos)
            * equatorialToEcliptic
            * raZeroToEclipticX
            * simd_float4x4.scale(SIMD3<Float>(repeating: radius))
        let normalMatrix = model.inverse.transpose

        var uniforms = RenderUniforms(
            modelMatrix: model,
            viewProjectionMatrix: viewProjection,
            normalMatrix: normalMatrix,
            sunDirection: SIMD4<Float>(0, 1, 0, 0),
            tintColor: SIMD4<Float>(repeating: 1),
            cameraPosition: SIMD4<Float>(cameraWorldPos, 0),
            opacity: 1.0,
            layerKind: 5.0,
            specularRoughness: 1.0,
            starCameraDistance: 0,
            bumpStrength: 0,
            specularMapStrength: 0,
            hasBumpMap: 0,
            hasSpecularMap: 0,
            textureProjection: 0,
            bumpMapIsNormalMap: 0,
            emissionMapStrength: 0,
            hasEmissionMap: 0,
            surfaceTintStrength: 0
        )
        var lightingParameters = LightingParameters(
            sunPositionRadius: SIMD4<Float>(0, 0, 0, 1),
            occluderCount: 0,
            selfOccluderIndex: -1,
            padding: SIMD2<Float>(repeating: 0)
        )
        var ringShadow = Self.emptyRingShadow

        encoder.setRenderPipelineState(spherePipelineState)
        encoder.setDepthStencilState(overlayDepthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        setLighting(LightingContext(occluders: [], occluderIndicesByBodyID: [:], sunPosition: .zero, sunRadius: 1), parameters: &lightingParameters, encoder: encoder)
        encoder.setFragmentBytes(&ringShadow, length: MemoryLayout<RingShadow>.stride, index: 4)
        encoder.setFragmentTexture(texture(named: Self.skyTextureName), index: 0)
        encoder.setFragmentTexture(fallbackTexture, index: 1)
        encoder.setFragmentTexture(fallbackTexture, index: 2)
        encoder.setFragmentTexture(fallbackTexture, index: 3)
        encoder.setFragmentTexture(fallbackTexture, index: 4)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
    }

    private func drawOrbitLines(
        encoder: MTLRenderCommandEncoder,
        snapshot: SolarSystemSnapshot,
        viewProjection: simd_float4x4,
        focus: SIMD3<Float>
    ) {
        encoder.setRenderPipelineState(orbitPipelineState)
        encoder.setDepthStencilState(transparentDepthState)

        var uniforms = OrbitUniforms(viewProjectionMatrix: viewProjection)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<OrbitUniforms>.stride, index: 1)

        for orbit in snapshot.orbitPaths where orbit.semiMajorAxis > 0 {
            let vertices = orbitVertices(for: orbit, focus: focus)
            let byteCount = vertices.count * MemoryLayout<OrbitVertex>.stride
            guard let buffer = orbitVertexBuffer(for: orbit.bodyID, byteCount: byteCount) else {
                continue
            }

            vertices.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress {
                    buffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
                }
            }

            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: vertices.count)
        }
    }

    private func orbitVertexBuffer(for orbitID: String, byteCount: Int) -> MTLBuffer? {
        if let cached = orbitVertexBufferCache[orbitID], cached.length >= byteCount {
            return cached
        }

        guard let buffer = device.makeBuffer(length: byteCount, options: [.storageModeShared]) else {
            return nil
        }
        orbitVertexBufferCache[orbitID] = buffer
        return buffer
    }

    private func orbitVertices(for orbit: NativeOrbitPath, focus: SIMD3<Float>) -> [OrbitVertex] {
        let segments = min(768, max(192, Int((orbit.semiMajorAxis * 18.0).rounded(.up))))
        var E_values: [Float] = []
        E_values.reserveCapacity(segments + 2)
        
        for index in 0...segments {
            E_values.append(Float(index) / Float(segments) * .pi * 2.0)
        }
        
        // Normalize body's eccentric anomaly to [0, 2pi]
        var normE = orbit.currentEccentricAnomaly.truncatingRemainder(dividingBy: 2.0 * .pi)
        if normE < 0 {
            normE += 2.0 * .pi
        }
        
        // Insert normE into sorted E_values to ensure a vertex is placed exactly at the body's position
        if let insertIndex = E_values.firstIndex(where: { $0 > normE }) {
            E_values.insert(normE, at: insertIndex)
        } else {
            E_values.append(normE)
        }
        
        var vertices: [OrbitVertex] = []
        vertices.reserveCapacity(E_values.count)

        for E in E_values {
            // 1. Orbital plane coordinates (x towards periapsis)
            let xp = orbit.semiMajorAxis * (cos(E) - orbit.eccentricity)
            let zp = orbit.semiMajorAxis * sqrt(1.0 - orbit.eccentricity * orbit.eccentricity) * sin(E)
            let flat = SIMD3<Float>(xp, 0.0, zp)
            
            // 2. Rotate by argument of periapsis in plane (around Y-axis)
            let rotatedInPlane = rotateVector(flat, radians: -orbit.argumentOfPeriapsis, axis: SIMD3<Float>(0, 1, 0))
            
            // 3. Tilt by inclination around X-axis
            let tilted = rotateVector(rotatedInPlane, radians: orbit.inclination, axis: SIMD3<Float>(1, 0, 0))
            
            // 4. Rotate by longitude of ascending node around Y-axis
            let positioned = rotateVector(tilted, radians: -orbit.longitudeOfAscendingNode, axis: SIMD3<Float>(0, 1, 0))
            
            // 5. If equatorial-referenced (BODY), tilt by the parent planet's axial tilt around the X-axis
            var finalOffset = positioned
            if orbit.referencePlane == "BODY" {
                let parentTiltRad = orbit.parentAxialTiltDegrees * .pi / 180.0
                finalOffset = rotateVector(positioned, radians: parentTiltRad, axis: SIMD3<Float>(1, 0, 0))
            }
            finalOffset.x = -finalOffset.x
            
            let position = (orbit.center - focus) + finalOffset
            vertices.append(OrbitVertex(position: position, color: orbit.color))
        }

        return vertices
    }

    private func drawSunLensFlare(
        encoder: MTLRenderCommandEncoder,
        sunPosition: SIMD3<Float>,
        cameraPosition: SIMD3<Float>,
        states: [NativeBodyRenderState],
        focus: SIMD3<Float>,
        viewProjection: simd_float4x4,
        aspect: Float
    ) {
        let cameraToSun = sunPosition - cameraPosition
        let cameraToSunDistance = length(cameraToSun)
        guard cameraToSunDistance > 0.0001 else { return }
        let sunRay = cameraToSun / cameraToSunDistance

        for state in states where state.body.kind != .star {
            let center = state.position - focus
            let cameraToBody = center - cameraPosition
            let projectedDistance = dot(cameraToBody, sunRay)
            if projectedDistance <= 0 || projectedDistance >= cameraToSunDistance {
                continue
            }
            let closestPoint = cameraPosition + sunRay * projectedDistance
            let screenSpaceRadius = state.sceneRadius * 1.04
            if length(center - closestPoint) < screenSpaceRadius {
                return
            }
        }

        let clip = viewProjection * SIMD4<Float>(sunPosition.x, sunPosition.y, sunPosition.z, 1)
        guard clip.w > 0.0001 else { return }

        let ndc = SIMD2<Float>(clip.x / clip.w, clip.y / clip.w)
        let distanceFromScreen = length(ndc)
        guard abs(ndc.x) < 1.35, abs(ndc.y) < 1.35 else { return }

        let edgeFade = 1.0 - smoothstep(0.82, 1.32, distanceFromScreen)
        guard edgeFade > 0.001 else { return }

        let intensity = min(0.95, max(0.18, 0.78 * edgeFade))
        var vertices: [FlareVertex] = []
        vertices.reserveCapacity(48)

        appendFlareQuad(
            center: ndc,
            radius: SIMD2<Float>(0.070 / max(aspect, 0.01), 0.070),
            color: SIMD4<Float>(1.0, 0.78, 0.34, 0.58 * intensity),
            into: &vertices
        )
        appendFlareQuad(
            center: ndc,
            radius: SIMD2<Float>(0.185 / max(aspect, 0.01), 0.185),
            color: SIMD4<Float>(1.0, 0.48, 0.14, 0.16 * intensity),
            into: &vertices
        )
        appendFlareQuad(
            center: ndc,
            radius: SIMD2<Float>(0.370 / max(aspect, 0.01), 0.370),
            color: SIMD4<Float>(0.95, 0.34, 0.10, 0.045 * intensity),
            into: &vertices
        )

        let axis = -ndc
        let ghostSpecs: [(Float, Float, SIMD4<Float>)] = [
            (0.42, 0.040, SIMD4<Float>(0.98, 0.72, 0.32, 0.18 * intensity)),
            (0.72, 0.026, SIMD4<Float>(0.35, 0.70, 1.00, 0.10 * intensity)),
            (1.08, 0.052, SIMD4<Float>(1.00, 0.34, 0.18, 0.085 * intensity))
        ]
        for (offset, radius, color) in ghostSpecs {
            let center = ndc + axis * offset
            appendFlareQuad(
                center: center,
                radius: SIMD2<Float>(radius / max(aspect, 0.01), radius),
                color: color,
                into: &vertices
            )
        }

        encoder.setRenderPipelineState(flarePipelineState)
        encoder.setDepthStencilState(overlayDepthState)
        vertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            encoder.setVertexBytes(baseAddress, length: bytes.count, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
    }

    private func appendFlareQuad(
        center: SIMD2<Float>,
        radius: SIMD2<Float>,
        color: SIMD4<Float>,
        into vertices: inout [FlareVertex]
    ) {
        let minPoint = center - radius
        let maxPoint = center + radius
        vertices.append(FlareVertex(position: SIMD2<Float>(minPoint.x, minPoint.y), local: SIMD2<Float>(-1, -1), color: color))
        vertices.append(FlareVertex(position: SIMD2<Float>(maxPoint.x, minPoint.y), local: SIMD2<Float>(1, -1), color: color))
        vertices.append(FlareVertex(position: SIMD2<Float>(maxPoint.x, maxPoint.y), local: SIMD2<Float>(1, 1), color: color))
        vertices.append(FlareVertex(position: SIMD2<Float>(maxPoint.x, maxPoint.y), local: SIMD2<Float>(1, 1), color: color))
        vertices.append(FlareVertex(position: SIMD2<Float>(minPoint.x, maxPoint.y), local: SIMD2<Float>(-1, 1), color: color))
        vertices.append(FlareVertex(position: SIMD2<Float>(minPoint.x, minPoint.y), local: SIMD2<Float>(-1, -1), color: color))
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let t = min(1, max(0, (value - edge0) / max(edge1 - edge0, 0.0001)))
        return t * t * (3 - 2 * t)
    }

    private func lightingContext(for snapshot: SolarSystemSnapshot, focus: SIMD3<Float>) -> LightingContext {
        let occluderStates = snapshot.states
            .filter { $0.body.kind != .star && $0.sceneRadius > 0 }
            .sorted {
                if $0.sceneRadius != $1.sceneRadius {
                    return $0.sceneRadius > $1.sceneRadius
                }
                return $0.body.id < $1.body.id
            }
            .prefix(Self.maxLightingOccluders)

        var indicesByBodyID: [String: Int32] = [:]
        var occluders: [LightingOccluder] = []
        occluders.reserveCapacity(Self.maxLightingOccluders)

        for (index, state) in occluderStates.enumerated() {
            indicesByBodyID[state.body.id] = Int32(index)
            let relativeOccluderPos = state.position - focus
            occluders.append(
                LightingOccluder(
                    positionRadius: SIMD4<Float>(
                        relativeOccluderPos.x,
                        relativeOccluderPos.y,
                        relativeOccluderPos.z,
                        state.sceneRadius
                    )
                )
            )
        }

        let sunRadius = snapshot.states.first { $0.body.kind == .star }?.sceneRadius ?? 1.0
        let relativeSunPos = snapshot.sunPosition - focus
        return LightingContext(
            occluders: occluders,
            occluderIndicesByBodyID: indicesByBodyID,
            sunPosition: relativeSunPos,
            sunRadius: sunRadius
        )
    }

    private func drawRing(
        encoder: MTLRenderCommandEncoder,
        state: NativeBodyRenderState,
        position: SIMD3<Float>,
        viewProjection: simd_float4x4,
        lightingContext: LightingContext,
        cameraWorldPos: SIMD3<Float>
    ) {
        guard let ring = state.body.ring else { return }

        let model = simd_float4x4.translation(position)
            * ringOrientationMatrix(for: state.body)
            * simd_float4x4.scale(SIMD3<Float>(repeating: state.sceneRadius * ring.outerRadiusBodyRadii))
        let normalMatrix = model.inverse.transpose
        let toSun = lightingContext.sunPosition - position
        let sunDirection = length(toSun) > 0.0001 ? normalize(toSun) : SIMD3<Float>(0, 1, 0)

        var uniforms = RenderUniforms(
            modelMatrix: model,
            viewProjectionMatrix: viewProjection,
            normalMatrix: normalMatrix,
            sunDirection: SIMD4<Float>(sunDirection, 0),
            tintColor: state.body.displayColor.simdRGBA,
            cameraPosition: SIMD4<Float>(cameraWorldPos, 0),
            opacity: ring.opacity,
            layerKind: ring.innerRadiusBodyRadii / ring.outerRadiusBodyRadii,
            specularRoughness: 1.0,
            starCameraDistance: 0,
            bumpStrength: 0,
            specularMapStrength: 0,
            hasBumpMap: 0,
            hasSpecularMap: 0,
            textureProjection: 0,
            bumpMapIsNormalMap: 0,
            emissionMapStrength: 0,
            hasEmissionMap: 0,
            surfaceTintStrength: 0
        )
        var lightingParameters = LightingParameters(
            sunPositionRadius: SIMD4<Float>(lightingContext.sunPosition, lightingContext.sunRadius),
            occluderCount: Int32(lightingContext.occluders.count),
            selfOccluderIndex: -1,
            padding: SIMD2<Float>(repeating: 0)
        )

        encoder.setVertexBuffer(ringVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        setLighting(lightingContext, parameters: &lightingParameters, encoder: encoder)
        encoder.setFragmentTexture(texture(named: ring.textureName), index: 0)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: ringIndexCount,
            indexType: .uint32,
            indexBuffer: ringIndexBuffer,
            indexBufferOffset: 0
        )
    }

    private func drawSphere(
        encoder: MTLRenderCommandEncoder,
        state: NativeBodyRenderState,
        position: SIMD3<Float>,
        sceneRadius: Float,
        texture: MTLTexture,
        opacity: Float,
        layerKind: Float,
        rotationMultiplier: Float = 1.0,
        viewProjection: simd_float4x4,
        lightingContext: LightingContext,
        cameraWorldPos: SIMD3<Float>,
        specularRoughness: Float,
        starCameraDistance: Float,
        materialMaps: NativeMaterialMaps,
        ringShadow: RingShadow,
        ringTexture: MTLTexture
    ) {
        let spin = state.rotationAngleRadians * rotationMultiplier + surfaceYawOffset(for: state.body)
        let model = simd_float4x4.translation(position)
            * visualMeshOrientationMatrix(for: state.body)
            * simd_float4x4.rotation(radians: spin, axis: SIMD3<Float>(0, 1, 0))
            * surfaceRollMatrix(for: state.body)
            * simd_float4x4.scale(fallbackSphereScale(for: state.body) * sceneRadius)
        let normalMatrix = model.inverse.transpose

        let toSun = lightingContext.sunPosition - position
        let sunDirection = length(toSun) > 0.0001 ? normalize(toSun) : SIMD3<Float>(0, 1, 0)
        let tint = state.body.displayColor.simdRGBA
        var uniforms = RenderUniforms(
            modelMatrix: model,
            viewProjectionMatrix: viewProjection,
            normalMatrix: normalMatrix,
            sunDirection: SIMD4<Float>(sunDirection, 0),
            tintColor: tint,
            cameraPosition: SIMD4<Float>(cameraWorldPos, 0),
            opacity: opacity,
            layerKind: layerKind,
            specularRoughness: specularRoughness,
            starCameraDistance: starCameraDistance,
            bumpStrength: materialMaps.bumpStrength,
            specularMapStrength: materialMaps.specularStrength,
            hasBumpMap: materialMaps.bumpMapName == nil ? 0 : 1,
            hasSpecularMap: materialMaps.specularMapName == nil && materialMaps.specularMapURL == nil ? 0 : 1,
            textureProjection: 0,
            bumpMapIsNormalMap: materialMaps.bumpMapIsNormalMap ? 1 : 0,
            emissionMapStrength: materialMaps.emissionStrength,
            hasEmissionMap: materialMaps.emissionMapName == nil ? 0 : 1,
            surfaceTintStrength: state.body.surfaceTintStrength
        )
        var lightingParameters = LightingParameters(
            sunPositionRadius: SIMD4<Float>(lightingContext.sunPosition, lightingContext.sunRadius),
            occluderCount: Int32(lightingContext.occluders.count),
            selfOccluderIndex: lightingContext.occluderIndicesByBodyID[state.body.id] ?? -1,
            padding: SIMD2<Float>(repeating: 0)
        )

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        setLighting(lightingContext, parameters: &lightingParameters, encoder: encoder)
        var shadow = ringShadow
        encoder.setFragmentBytes(&shadow, length: MemoryLayout<RingShadow>.stride, index: 4)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(ringTexture, index: 1)
        encoder.setFragmentTexture(materialMaps.bumpMapName.map { dataTexture(named: $0) } ?? fallbackTexture, index: 2)
        encoder.setFragmentTexture(specularTexture(for: materialMaps) ?? fallbackTexture, index: 3)
        encoder.setFragmentTexture(materialMaps.emissionMapName.map { self.texture(named: $0) } ?? fallbackTexture, index: 4)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
    }

    private func drawShapeModel(
        encoder: MTLRenderCommandEncoder,
        mesh: ShapeMeshResource,
        state: NativeBodyRenderState,
        position: SIMD3<Float>,
        sceneRadius: Float,
        texture: MTLTexture,
        opacity: Float,
        layerKind: Float,
        rotationMultiplier: Float = 1.0,
        viewProjection: simd_float4x4,
        lightingContext: LightingContext,
        cameraWorldPos: SIMD3<Float>,
        specularRoughness: Float,
        materialMaps: NativeMaterialMaps,
        ringShadow: RingShadow,
        ringTexture: MTLTexture
    ) {
        let spin = state.rotationAngleRadians * rotationMultiplier + surfaceYawOffset(for: state.body)
        let model = simd_float4x4.translation(position)
            * visualMeshOrientationMatrix(for: state.body)
            * simd_float4x4.rotation(radians: spin, axis: SIMD3<Float>(0, 1, 0))
            * surfaceRollMatrix(for: state.body)
            * simd_float4x4.scale(SIMD3<Float>(repeating: sceneRadius))
            * mesh.normalizationTransform
        let normalMatrix = model.inverse.transpose

        let toSun = lightingContext.sunPosition - position
        let sunDirection = length(toSun) > 0.0001 ? normalize(toSun) : SIMD3<Float>(0, 1, 0)
        var uniforms = RenderUniforms(
            modelMatrix: model,
            viewProjectionMatrix: viewProjection,
            normalMatrix: normalMatrix,
            sunDirection: SIMD4<Float>(sunDirection, 0),
            tintColor: state.body.displayColor.simdRGBA,
            cameraPosition: SIMD4<Float>(cameraWorldPos, 0),
            opacity: opacity,
            layerKind: layerKind,
            specularRoughness: specularRoughness,
            starCameraDistance: 0,
            bumpStrength: materialMaps.bumpStrength,
            specularMapStrength: materialMaps.specularStrength,
            hasBumpMap: materialMaps.bumpMapName == nil ? 0 : 1,
            hasSpecularMap: materialMaps.specularMapName == nil && materialMaps.specularMapURL == nil ? 0 : 1,
            textureProjection: mesh.usesProjectedTextureCoordinates ? 1 : 0,
            bumpMapIsNormalMap: materialMaps.bumpMapIsNormalMap ? 1 : 0,
            emissionMapStrength: materialMaps.emissionStrength,
            hasEmissionMap: materialMaps.emissionMapName == nil ? 0 : 1,
            surfaceTintStrength: state.body.surfaceTintStrength
        )
        var lightingParameters = LightingParameters(
            sunPositionRadius: SIMD4<Float>(lightingContext.sunPosition, lightingContext.sunRadius),
            occluderCount: Int32(lightingContext.occluders.count),
            selfOccluderIndex: lightingContext.occluderIndicesByBodyID[state.body.id] ?? -1,
            padding: SIMD2<Float>(repeating: 0)
        )

        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        setLighting(lightingContext, parameters: &lightingParameters, encoder: encoder)
        var shadow = ringShadow
        encoder.setFragmentBytes(&shadow, length: MemoryLayout<RingShadow>.stride, index: 4)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(ringTexture, index: 1)
        encoder.setFragmentTexture(materialMaps.bumpMapName.map { dataTexture(named: $0) } ?? fallbackTexture, index: 2)
        encoder.setFragmentTexture(specularTexture(for: materialMaps) ?? fallbackTexture, index: 3)
        encoder.setFragmentTexture(materialMaps.emissionMapName.map { self.texture(named: $0) } ?? fallbackTexture, index: 4)

        for part in mesh.parts {
            encoder.setVertexBuffer(part.vertexBuffer, offset: part.vertexBufferOffset, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: part.indexCount,
                indexType: part.indexType,
                indexBuffer: part.indexBuffer,
                indexBufferOffset: part.indexBufferOffset
            )
        }
    }

    private func setLighting(
        _ context: LightingContext,
        parameters: inout LightingParameters,
        encoder: MTLRenderCommandEncoder
    ) {
        if context.occluders.isEmpty {
            var placeholder = LightingOccluder(positionRadius: SIMD4<Float>(repeating: 0))
            encoder.setFragmentBytes(&placeholder, length: MemoryLayout<LightingOccluder>.stride, index: 2)
        } else {
            context.occluders.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    return
                }
                encoder.setFragmentBytes(baseAddress, length: bytes.count, index: 2)
            }
        }
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<LightingParameters>.stride, index: 3)
    }

    private func fallbackSphereScale(for body: NativeCelestialBody) -> SIMD3<Float> {
        switch body.id {
        case "deimos":
            return SIMD3<Float>(1.0, 0.665, 0.763)
        default:
            return SIMD3<Float>(repeating: 1.0)
        }
    }

    private func cameraOffset(for selectedState: NativeBodyRenderState) -> SIMD3<Float> {
        let selectedScale = selectedState.sceneRadius * 1.35
        let distance = max(cameraDistance, selectedScale)
        let horizontalDistance = cos(cameraPitch) * distance
        return SIMD3<Float>(
            sin(cameraYaw) * horizontalDistance,
            sin(cameraPitch) * distance,
            cos(cameraYaw) * horizontalDistance
        )
    }

    private func cameraFocusState(in snapshot: SolarSystemSnapshot) -> NativeBodyRenderState {
        if observationMode == .planetarium,
           let earthState = snapshot.states.first(where: { $0.body.id == "earth" }) {
            return earthState
        }
        return snapshot.selectedState
    }

    private func cameraProjectionMetrics(for focusState: NativeBodyRenderState) -> CameraProjectionMetrics {
        if observationMode == .planetarium {
            let nearPlane = max(1e-9, focusState.sceneRadius * 0.0005)
            return CameraProjectionMetrics(
                nearPlane: nearPlane,
                farPlane: 1200.0,
                fovyRadians: planetariumFovyRadians(for: cameraDistance),
                skyScale: 900.0
            )
        }

        let selectedScale = focusState.sceneRadius * 1.35
        let actualDistance = max(cameraDistance, selectedScale)
        return CameraProjectionMetrics(
            nearPlane: max(1e-9, min(0.02, actualDistance * 0.08)),
            farPlane: max(1200.0, actualDistance * 200.0 + 500.0),
            fovyRadians: .pi / 4.0,
            skyScale: actualDistance
        )
    }

    private func cameraFrame(for focusState: NativeBodyRenderState, snapshot: SolarSystemSnapshot) -> CameraFrame {
        if observationMode == .planetarium {
            let lockedTarget = lockedBodyID.flatMap { bodyID in
                snapshot.states.first { $0.body.id == bodyID && $0.body.id != "earth" }
            }
            return planetariumCameraFrame(for: focusState, lockedTarget: lockedTarget)
        }

        return CameraFrame(
            eye: cameraTargetOffset + cameraOffset(for: focusState),
            target: cameraTargetOffset,
            up: SIMD3<Float>(0, 1, 0)
        )
    }

    private func planetariumCameraFrame(
        for earthState: NativeBodyRenderState,
        lockedTarget: NativeBodyRenderState?
    ) -> CameraFrame {
        let basis = planetariumLocalBasis(for: planetariumLocation)
        let surfaceTransform = planetariumSurfaceTransform(for: earthState)
        let localUp = transformDirection(basis.up, by: surfaceTransform)
        let localNorth = transformDirection(basis.north, by: surfaceTransform)
        let localEast = transformDirection(basis.east, by: surfaceTransform)
        let eyeLift = max(earthState.sceneRadius * 0.006, 1e-7)
        let surfacePoint = localUp * earthState.sceneRadius
        let eye = surfacePoint + localUp * eyeLift
        let viewDirection: SIMD3<Float>
        if let lockedTarget {
            let targetPosition = lockedTarget.position - earthState.position
            let cameraToTarget = targetPosition - eye
            if length(cameraToTarget) > max(lockedTarget.sceneRadius * 0.001, 1e-8) {
                viewDirection = normalize(cameraToTarget)
                syncPlanetariumAngles(
                    viewDirection: viewDirection,
                    localNorth: localNorth,
                    localEast: localEast,
                    localUp: localUp
                )
            } else {
                viewDirection = manualPlanetariumViewDirection(
                    localNorth: localNorth,
                    localEast: localEast,
                    localUp: localUp
                )
            }
        } else {
            viewDirection = manualPlanetariumViewDirection(
                localNorth: localNorth,
                localEast: localEast,
                localUp: localUp
            )
        }
        let projectedUp = localUp - viewDirection * dot(localUp, viewDirection)
        let cameraUp = length(projectedUp) > 0.001 ? normalize(projectedUp) : localNorth

        return CameraFrame(
            eye: eye,
            target: eye + viewDirection,
            up: cameraUp
        )
    }

    private func manualPlanetariumViewDirection(
        localNorth: SIMD3<Float>,
        localEast: SIMD3<Float>,
        localUp: SIMD3<Float>
    ) -> SIMD3<Float> {
        let horizontal = cos(cameraPitch)
        return normalize(
            localNorth * (cos(cameraYaw) * horizontal)
                + localEast * (sin(cameraYaw) * horizontal)
                + localUp * sin(cameraPitch)
        )
    }

    private func syncPlanetariumAngles(
        viewDirection: SIMD3<Float>,
        localNorth: SIMD3<Float>,
        localEast: SIMD3<Float>,
        localUp: SIMD3<Float>
    ) {
        let upComponent = clampSigned(dot(viewDirection, localUp))
        let horizontal = viewDirection - localUp * upComponent
        if length(horizontal) > 1e-5 {
            let horizontalDirection = normalize(horizontal)
            cameraYaw = atan2(
                dot(horizontalDirection, localEast),
                dot(horizontalDirection, localNorth)
            )
        }
        cameraPitch = asin(upComponent)
        reportPlanetariumHeading()
    }

    private func planetariumLocalBasis(
        for location: PlanetariumLocation
    ) -> (up: SIMD3<Float>, north: SIMD3<Float>, east: SIMD3<Float>) {
        let latitude = Float(location.clamped.latitudeDegrees * .pi / 180.0)
        let longitude = Float(location.clamped.longitudeDegrees * .pi / 180.0)
        let cosLatitude = cos(latitude)
        let sinLatitude = sin(latitude)
        let cosLongitude = cos(longitude)
        let sinLongitude = sin(longitude)

        let up = normalize(SIMD3<Float>(
            -cosLatitude * cosLongitude,
            sinLatitude,
            cosLatitude * sinLongitude
        ))
        let north = normalize(SIMD3<Float>(
            sinLatitude * cosLongitude,
            cosLatitude,
            -sinLatitude * sinLongitude
        ))
        let east = normalize(SIMD3<Float>(
            sinLongitude,
            0,
            cosLongitude
        ))

        return (up, north, east)
    }

    private func planetariumSurfaceTransform(for state: NativeBodyRenderState) -> simd_float4x4 {
        let spin = state.rotationAngleRadians + surfaceYawOffset(for: state.body)
        return visualMeshOrientationMatrix(for: state.body)
            * simd_float4x4.rotation(radians: spin, axis: SIMD3<Float>(0, 1, 0))
            * surfaceRollMatrix(for: state.body)
    }

    private func transformDirection(_ direction: SIMD3<Float>, by matrix: simd_float4x4) -> SIMD3<Float> {
        let transformed = matrix * SIMD4<Float>(direction.x, direction.y, direction.z, 0)
        return normalize(SIMD3<Float>(transformed.x, transformed.y, transformed.z))
    }

    private func pickedBodyID(
        at point: CGPoint,
        viewportSize: CGSize,
        snapshot: SolarSystemSnapshot,
        viewProjection: simd_float4x4,
        focus: SIMD3<Float>,
        cameraPosition: SIMD3<Float>,
        fovyRadians: Float,
        hiddenBodyIDs: Set<String>
    ) -> String? {
        let width = max(Float(viewportSize.width), 1)
        let height = max(Float(viewportSize.height), 1)
        let hitPoint = SIMD2<Float>(Float(point.x), Float(point.y))
        let focalY = height * 0.5 / max(tan(fovyRadians * 0.5), 1e-6)
        var bestHit: (id: String, cameraDistance: Float, pixelDistance: Float)?

        for state in snapshot.states where state.sceneRadius > 0 {
            if hiddenBodyIDs.contains(state.body.id) {
                continue
            }
            if observationMode == .planetarium, state.body.id == "earth" {
                continue
            }

            let relativePosition = state.position - focus
            let clip = viewProjection * SIMD4<Float>(relativePosition, 1)
            guard clip.w > 0.001 else {
                continue
            }

            let normalized = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
            guard normalized.x >= -1.2,
                  normalized.x <= 1.2,
                  normalized.y >= -1.2,
                  normalized.y <= 1.2,
                  normalized.z >= 0,
                  normalized.z <= 1.0 else {
                continue
            }

            let screenCenter = SIMD2<Float>(
                (normalized.x * 0.5 + 0.5) * width,
                (1.0 - (normalized.y * 0.5 + 0.5)) * height
            )
            let cameraToBody = relativePosition - cameraPosition
            let cameraDistance = length(cameraToBody)
            guard cameraDistance > max(state.sceneRadius, 1e-8) else {
                continue
            }

            let angularRadius = asin(clampUnit(state.sceneRadius / cameraDistance))
            let projectedRadius = max(7.0, tan(angularRadius) * focalY)
            let pixelDistance = length(hitPoint - screenCenter)
            guard pixelDistance <= projectedRadius else {
                continue
            }

            if let currentBest = bestHit {
                let closer = cameraDistance < currentBest.cameraDistance
                let moreCentered = abs(cameraDistance - currentBest.cameraDistance) < 1e-5
                    && pixelDistance < currentBest.pixelDistance
                if closer || moreCentered {
                    bestHit = (state.body.id, cameraDistance, pixelDistance)
                }
            } else {
                bestHit = (state.body.id, cameraDistance, pixelDistance)
            }
        }

        return bestHit?.id
    }

    private func visuallyOccludedBodyIDs(
        states: [NativeBodyRenderState],
        focus: SIMD3<Float>,
        cameraPosition: SIMD3<Float>
    ) -> Set<String> {
        let occluders = states.filter { $0.body.kind != .star && $0.sceneRadius > 0 }
        var hiddenIDs = Set<String>()

        for target in states where target.sceneRadius > 0 {
            let targetPosition = target.position - focus
            if isFullyHiddenFromCamera(
                targetPosition: targetPosition,
                targetRadius: target.sceneRadius,
                targetID: target.body.id,
                occluders: occluders,
                focus: focus,
                cameraPosition: cameraPosition
            ) {
                hiddenIDs.insert(target.body.id)
            }
        }

        return hiddenIDs
    }

    private func isFullyHiddenFromCamera(
        targetPosition: SIMD3<Float>,
        targetRadius: Float,
        targetID: String,
        occluders: [NativeBodyRenderState],
        focus: SIMD3<Float>,
        cameraPosition: SIMD3<Float>
    ) -> Bool {
        let cameraToTarget = targetPosition - cameraPosition
        let targetDistance = length(cameraToTarget)
        guard targetDistance > max(targetRadius, 1e-6) else {
            return false
        }

        let targetDirection = cameraToTarget / targetDistance
        let targetAngularRadius = asin(clampUnit(targetRadius / targetDistance))

        for occluder in occluders where occluder.body.id != targetID {
            let occluderPosition = occluder.position - focus
            let cameraToOccluder = occluderPosition - cameraPosition
            let occluderDistance = length(cameraToOccluder)
            guard occluderDistance > max(occluder.sceneRadius, 1e-6),
                  occluderDistance < targetDistance else {
                continue
            }

            let occluderDirection = cameraToOccluder / occluderDistance
            let angularSeparation = acos(clampSigned(dot(targetDirection, occluderDirection)))
            let occluderAngularRadius = asin(clampUnit(occluder.sceneRadius / occluderDistance))

            if angularSeparation + targetAngularRadius <= occluderAngularRadius {
                return true
            }
        }

        return false
    }

    private func clampUnit(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    private func clampSigned(_ value: Float) -> Float {
        min(1, max(-1, value))
    }

    /// Builds a RingShadow for any body that has a ring (e.g. Saturn).
    /// The ring lies in the planet's equatorial plane. For Saturn this must use the
    /// IAU pole direction, not just obliquity, because the equator also has a node
    /// in the J2000 ecliptic frame used by the satellite ephemerides.
    private func makeRingShadow(for state: NativeBodyRenderState, position: SIMD3<Float>) -> RingShadow {
        guard let ring = state.body.ring else { return Self.emptyRingShadow }
        let normal = bodyPoleDirection(for: state.body)
        let innerR = state.sceneRadius * ring.innerRadiusBodyRadii
        let outerR = state.sceneRadius * ring.outerRadiusBodyRadii
        return RingShadow(
            planeNormal:  SIMD4<Float>(normal.x, normal.y, normal.z, 1),  // w=1 → ring is active
            planetCenter: SIMD4<Float>(position.x, position.y, position.z, innerR),
            outerRadius:  outerR
        )
    }

    private func ringOrientationMatrix(for body: NativeCelestialBody) -> simd_float4x4 {
        if body.id == "saturn" {
            return rotationFromLocalYAxis(to: bodyPoleDirection(for: body))
        }
        return axialTiltMatrix(for: body)
    }

    private func visualMeshOrientationMatrix(for body: NativeCelestialBody) -> simd_float4x4 {
        if body.id == "saturn" {
            return rotationFromLocalYAxis(to: bodyPoleDirection(for: body))
        }
        return axialTiltMatrix(for: body)
    }

    private func surfaceYawOffset(for body: NativeCelestialBody) -> Float {
        switch body.id {
        case "moon":
            return .pi + degreesToRadians(8.0)
        default:
            return 0
        }
    }

    private func surfaceRollMatrix(for body: NativeCelestialBody) -> simd_float4x4 {
        switch body.id {
        case "moon":
            return simd_float4x4.rotation(
                radians: degreesToRadians(-12.0),
                axis: SIMD3<Float>(1, 0, 0)
            )
        default:
            return .identity()
        }
    }

    private func degreesToRadians(_ degrees: Float) -> Float {
        degrees * .pi / 180.0
    }

    private func axialTiltMatrix(for body: NativeCelestialBody) -> simd_float4x4 {
        simd_float4x4.rotation(
            radians: body.axialTiltDegrees * .pi / 180.0,
            axis: SIMD3<Float>(1, 0, 0)
        )
    }

    private func bodyPoleDirection(for body: NativeCelestialBody) -> SIMD3<Float> {
        switch body.id {
        case "saturn":
            // IAU/WGCCRE J2000 north pole: RA 40.589 deg, Dec 83.537 deg.
            return poleDirectionFromEquatorial(rightAscensionDegrees: 40.589, declinationDegrees: 83.537)
        default:
            return normalize(rotateVector(
                SIMD3<Float>(0, 1, 0),
                radians: body.axialTiltDegrees * .pi / 180.0,
                axis: SIMD3<Float>(1, 0, 0)
            ))
        }
    }

    private func poleDirectionFromEquatorial(
        rightAscensionDegrees: Double,
        declinationDegrees: Double
    ) -> SIMD3<Float> {
        let ra = rightAscensionDegrees * .pi / 180.0
        let dec = declinationDegrees * .pi / 180.0
        let obliquity = 23.4392911 * .pi / 180.0

        let equatorial = SIMD3<Double>(
            cos(dec) * cos(ra),
            cos(dec) * sin(ra),
            sin(dec)
        )
        let ecliptic = SIMD3<Double>(
            equatorial.x,
            equatorial.y * cos(obliquity) + equatorial.z * sin(obliquity),
            -equatorial.y * sin(obliquity) + equatorial.z * cos(obliquity)
        )

        // App coordinates map to Horizons/J2000 ecliptic as:
        // ecliptic X = -app X, ecliptic Y = app Z, ecliptic Z = -app Y.
        return normalize(SIMD3<Float>(
            Float(-ecliptic.x),
            Float(-ecliptic.z),
            Float(ecliptic.y)
        ))
    }

    private func rotationFromLocalYAxis(to targetDirection: SIMD3<Float>) -> simd_float4x4 {
        let source = SIMD3<Float>(0, 1, 0)
        let target = normalize(targetDirection)
        let dotValue = max(-1, min(1, dot(source, target)))

        if dotValue > 0.999_999 {
            return .identity()
        }
        if dotValue < -0.999_999 {
            return simd_float4x4.rotation(radians: .pi, axis: SIMD3<Float>(1, 0, 0))
        }

        let axis = normalize(cross(source, target))
        let angle = acos(dotValue)
        return simd_float4x4.rotation(radians: angle, axis: axis)
    }

    private func updateLabels(
        snapshot: SolarSystemSnapshot,
        viewProjection: simd_float4x4,
        viewportSize: CGSize,
        focus: SIMD3<Float>,
        hiddenBodyIDs: Set<String>
    ) {
        guard let viewport else {
            return
        }

        let width = max(viewportSize.width, 1)
        let height = max(viewportSize.height, 1)
        let selectedID = snapshot.selectedState.body.id
        let labels = snapshot.states.compactMap { state -> SolarSystemLabel? in
            if hiddenBodyIDs.contains(state.body.id) {
                return nil
            }

            let relativePosition = state.position - focus
            let anchor = relativePosition + SIMD3<Float>(0, state.sceneRadius * 1.45, 0)
            let clip = viewProjection * SIMD4<Float>(anchor, 1)
            guard clip.w > 0.001 else {
                return nil
            }

            let normalized = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
            guard normalized.x >= -1.08,
                  normalized.x <= 1.08,
                  normalized.y >= -1.08,
                  normalized.y <= 1.08,
                  normalized.z >= 0,
                  normalized.z <= 1.0 else {
                return nil
            }

            return SolarSystemLabel(
                id: state.body.id,
                name: state.body.name,
                position: CGPoint(
                    x: CGFloat((normalized.x * 0.5 + 0.5) * Float(width)),
                    y: CGFloat((1.0 - (normalized.y * 0.5 + 0.5)) * Float(height))
                ),
                isSelected: state.body.id == selectedID,
                displayColor: state.body.displayColor
            )
        }

        DispatchQueue.main.async { [weak viewport] in
            viewport?.update(labels: labels)
        }
    }

    private func shapeMesh(named name: String) -> ShapeMeshResource? {
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

    /// Returns the live base-map texture for a body if one is configured and has
    /// finished downloading, otherwise nil (callers fall back to the bundled map).
    private func liveSurfaceTexture(for body: NativeCelestialBody, at timestamp: CFTimeInterval) -> MTLTexture? {
        guard let template = body.liveSurfaceMapURLTemplate else { return nil }
        let urlString = template.replacingOccurrences(of: "{DATE}", with: Self.liveImageryDateString())
        return remoteTexture(
            urlString: urlString,
            isSRGB: true,
            processing: .raw,
            refreshInterval: 6 * 3600,
            at: timestamp
        )
    }

    /// UTC date (yesterday) used for daily live imagery. Yesterday is used so the
    /// requested day is fully processed and globally complete at the source.
    private static func liveImageryDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = Date().addingTimeInterval(-24 * 3600)
        return formatter.string(from: yesterday)
    }

    private func cloudTexture(for layer: NativeCloudLayer, at timestamp: CFTimeInterval) -> MTLTexture? {
        // Prefer the live (real-time) cloud map when available, but fall back to
        // the bundled cloud texture while the download is pending or if it fails,
        // so clouds always render. Cloud maps encode density (not color), so they
        // are loaded as linear data textures to keep the shader's mask semantics
        // consistent across the live alpha map and the bundled grayscale map.
        if let liveTextureURL = layer.liveTextureURL,
           let live = remoteTexture(
                urlString: liveTextureURL,
                isSRGB: false,
                processing: .cloudDensity,
                refreshInterval: layer.refreshIntervalSeconds,
                at: timestamp
           ) {
            return live
        }

        guard let textureName = cloudTextureName(for: layer, at: timestamp) else {
            return nil
        }
        return dataTexture(named: textureName)
    }

    private func cloudTextureName(for layer: NativeCloudLayer, at timestamp: CFTimeInterval) -> String? {
        guard !layer.textureNames.isEmpty else {
            return layer.textureName
        }
        guard layer.textureNames.count > 1, layer.animationFrameDuration > 0 else {
            return layer.textureNames[0]
        }

        let frame = Int(floor(timestamp / CFTimeInterval(layer.animationFrameDuration))) % layer.textureNames.count
        return layer.textureNames[frame]
    }

    private func specularTexture(for maps: NativeMaterialMaps) -> MTLTexture? {
        if let specularMapURL = maps.specularMapURL,
           let texture = remoteTexture(
                urlString: specularMapURL,
                isSRGB: false,
                refreshInterval: maps.specularRefreshIntervalSeconds,
                at: CACurrentMediaTime()
           ) {
            return texture
        }

        return maps.specularMapName.map { dataTexture(named: $0) }
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

    private func texture(named name: String) -> MTLTexture {
        if let cached = textureCache[name] {
            return cached
        }

        guard let url = Bundle.main.textureURL(named: name) else {
            return fallbackTexture
        }

        do {
            let texture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.SRGB: true,
                MTKTextureLoader.Option.generateMipmaps: true,
            ])
            textureCache[name] = texture
            return texture
        } catch {
            return fallbackTexture
        }
    }

    private func dataTexture(named name: String) -> MTLTexture {
        if let cached = dataTextureCache[name] {
            return cached
        }

        guard let url = Bundle.main.textureURL(named: name) else {
            return fallbackTexture
        }

        do {
            let texture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.SRGB: false,
                MTKTextureLoader.Option.generateMipmaps: true,
            ])
            dataTextureCache[name] = texture
            return texture
        } catch {
            return fallbackTexture
        }
    }

    private func remoteTexture(
        urlString: String,
        isSRGB: Bool,
        processing: RemoteTextureProcessing = .raw,
        refreshInterval: TimeInterval,
        at timestamp: CFTimeInterval
    ) -> MTLTexture? {
        let key = RemoteTextureKey(urlString: urlString, isSRGB: isSRGB, processing: processing)
        let minimumInterval = max(refreshInterval, 5)

        remoteTextureLock.lock()
        let entry: RemoteTextureEntry
        if let cachedEntry = remoteTextureCache[key] {
            entry = cachedEntry
        } else {
            let newEntry = RemoteTextureEntry()
            remoteTextureCache[key] = newEntry
            entry = newEntry
        }

        let cachedTexture = entry.texture
        let shouldRefresh = !entry.isLoading && timestamp - entry.lastRequestTime >= minimumInterval
        if shouldRefresh {
            entry.isLoading = true
            entry.lastRequestTime = timestamp
        }
        remoteTextureLock.unlock()

        if shouldRefresh {
            refreshRemoteTexture(key: key)
        }

        return cachedTexture
    }

    private func refreshRemoteTexture(key: RemoteTextureKey) {
        guard let url = URL(string: key.urlString) else {
            finishRemoteTextureLoad(key: key, texture: nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data else {
                self.finishRemoteTextureLoad(key: key, texture: nil)
                return
            }

            let texture: MTLTexture?
            switch key.processing {
            case .cloudDensity:
                texture = self.makeCloudDensityTexture(from: data)
            case .raw:
                texture = try? self.textureLoader.newTexture(data: data, options: [
                    MTKTextureLoader.Option.SRGB: key.isSRGB,
                    MTKTextureLoader.Option.generateMipmaps: true,
                ])
            }

            self.finishRemoteTextureLoad(key: key, texture: texture)
        }.resume()
    }

    /// Decodes image bytes and produces a linear grayscale texture whose value is
    /// the cloud density. If the source has a varying alpha channel (e.g. the live
    /// `clouds-alpha.png`, which stores the real cloud mask in alpha), that alpha
    /// is used; otherwise the luminance is used (e.g. a plain grayscale cloud map).
    private func makeCloudDensityTexture(from data: Data) -> MTLTexture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let pixelCount = width * height
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Decide whether the alpha channel carries real information.
        var alphaMin: UInt8 = 255
        var alphaMax: UInt8 = 0
        var sampleIndex = 3
        let sampleStride = max(1, pixelCount / 100_000) * 4
        while sampleIndex < rgba.count {
            let a = rgba[sampleIndex]
            if a < alphaMin { alphaMin = a }
            if a > alphaMax { alphaMax = a }
            sampleIndex += sampleStride
        }
        let alphaCarriesMask = Int(alphaMax) - Int(alphaMin) > 8

        // Pack the chosen density channel into a single-channel buffer.
        var density = [UInt8](repeating: 0, count: pixelCount)
        for pixelIndex in 0..<pixelCount {
            let rgbaOffset = pixelIndex * 4
            if alphaCarriesMask {
                density[pixelIndex] = rgba[rgbaOffset + 3]
            } else {
                // Rec. 601 luma; rgb is un-premultiplied here since alpha == 255.
                let red = Int(rgba[rgbaOffset])
                let green = Int(rgba[rgbaOffset + 1])
                let blue = Int(rgba[rgbaOffset + 2])
                density[pixelIndex] = UInt8((red * 299 + green * 587 + blue * 114) / 1000)
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: density,
            bytesPerRow: width
        )
        generateMipmaps(for: texture)
        return texture
    }

    private func generateMipmaps(for texture: MTLTexture) {
        guard texture.mipmapLevelCount > 1,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            return
        }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func finishRemoteTextureLoad(key: RemoteTextureKey, texture: MTLTexture?) {
        remoteTextureLock.lock()
        defer { remoteTextureLock.unlock() }

        let entry = remoteTextureCache[key] ?? RemoteTextureEntry()
        if remoteTextureCache[key] == nil {
            remoteTextureCache[key] = entry
        }
        if let texture {
            entry.texture = texture
        }
        entry.isLoading = false
    }

    private static func makeFallbackTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        var pixel: UInt32 = 0xffffffff
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: MemoryLayout<UInt32>.stride
        )
        return texture
    }
}

private enum SphereMesh {
    static func make(latitudeBands: Int, longitudeBands: Int) -> (vertices: [SphereVertex], indices: [UInt32]) {
        var vertices: [SphereVertex] = []
        var indices: [UInt32] = []

        for latitude in 0...latitudeBands {
            let v = Float(latitude) / Float(latitudeBands)
            let theta = v * .pi
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            for longitude in 0...longitudeBands {
                let u = Float(longitude) / Float(longitudeBands)
                let phi = u * .pi * 2.0
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)
                let normal = SIMD3<Float>(sinTheta * cosPhi, cosTheta, sinTheta * sinPhi)
                vertices.append(SphereVertex(position: normal, normal: normal, uv: SIMD2<Float>(1.0 - u, v)))
            }
        }

        let row = longitudeBands + 1
        for latitude in 0..<latitudeBands {
            for longitude in 0..<longitudeBands {
                let first = UInt32(latitude * row + longitude)
                let second = UInt32(first + UInt32(row))
                indices.append(first)
                indices.append(second)
                indices.append(first + 1)
                indices.append(second)
                indices.append(second + 1)
                indices.append(first + 1)
            }
        }

        return (vertices, indices)
    }
}

private enum RingMesh {
    static func make(segments: Int) -> (vertices: [SphereVertex], indices: [UInt32]) {
        var vertices: [SphereVertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity((segments + 1) * 2)

        for index in 0...segments {
            let u = Float(index) / Float(segments)
            let angle = u * .pi * 2.0
            let radialDirection = SIMD3<Float>(cos(angle), 0, sin(angle))
            vertices.append(
                SphereVertex(
                    position: radialDirection,
                    normal: SIMD3<Float>(0, 1, 0),
                    uv: SIMD2<Float>(1, u)
                )
            )
            vertices.append(
                SphereVertex(
                    position: radialDirection * 0.001,
                    normal: SIMD3<Float>(0, 1, 0),
                    uv: SIMD2<Float>(0, u)
                )
            )
        }

        for index in 0..<segments {
            let outer0 = UInt32(index * 2)
            let inner0 = outer0 + 1
            let outer1 = UInt32((index + 1) * 2)
            let inner1 = outer1 + 1
            indices.append(outer0)
            indices.append(inner0)
            indices.append(outer1)
            indices.append(outer1)
            indices.append(inner0)
            indices.append(inner1)
        }

        return (vertices, indices)
    }
}
#endif
