#if os(macOS)
import MetalKit
import SwiftUI

struct MetalSolarSystemView: NSViewRepresentable {
    let selectedBody: NativeCelestialBody
    let lockedBodyID: String?
    @Binding var cameraDistance: Double
    let timeRate: Double
    let isPaused: Bool
    @Binding var isLiveView: Bool
    @Binding var simulationDate: Date
    @Binding var dateSelectionTrigger: Bool
    @Binding var planetariumHeadingDegrees: Double
    @Binding var photoCaptureTrigger: Bool
    let viewport: SolarSystemViewport
    let options: NativeRenderOptions
    let observationMode: ObservationMode
    let planetariumLocation: PlanetariumLocation
    let isPhotoMode: Bool
    let selectBodyFromViewport: (String?) -> Void
    let exitPhotoMode: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = InteractiveMetalView()
        view.isPhotoMode = isPhotoMode
        view.onExitPhotoMode = exitPhotoMode
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.framebufferOnly = false
        view.clearColor = MTLClearColor(red: 0.004, green: 0.006, blue: 0.014, alpha: 1.0)
        view.clearDepth = 0.0
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        context.coordinator.cameraDistanceBinding = _cameraDistance
        context.coordinator.simulationDateBinding = _simulationDate
        context.coordinator.planetariumHeadingBinding = _planetariumHeadingDegrees

        if let device = view.device,
           let renderer = PlanetRenderer(device: device, metalView: view) {
            renderer.viewport = viewport
            renderer.update(
                body: selectedBody,
                cameraDistance: Float(cameraDistance),
                timeRate: timeRate,
                isPaused: isPaused,
                isLiveView: isLiveView,
                options: options,
                observationMode: observationMode,
                planetariumLocation: planetariumLocation,
                lockedBodyID: lockedBodyID
            )
            renderer.jump(to: simulationDate)
            renderer.onZoom = { newDistance in
                DispatchQueue.main.async {
                    context.coordinator.cameraDistanceBinding?.wrappedValue = Double(newDistance)
                }
            }
            renderer.onSimulationDateChange = { date in
                DispatchQueue.main.async {
                    context.coordinator.simulationDateBinding?.wrappedValue = date
                }
            }
            renderer.onPlanetariumHeadingChange = { headingDegrees in
                DispatchQueue.main.async {
                    context.coordinator.planetariumHeadingBinding?.wrappedValue = headingDegrees
                }
            }
            renderer.onBodyPick = { bodyID in
                DispatchQueue.main.async {
                    selectBodyFromViewport(bodyID)
                }
            }
            view.delegate = renderer
            view.cameraDelegate = renderer
            context.coordinator.renderer = renderer
            context.coordinator.lastDateSelectionTrigger = dateSelectionTrigger
            context.coordinator.lastPhotoCaptureTrigger = photoCaptureTrigger
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.cameraDistanceBinding = _cameraDistance
        context.coordinator.simulationDateBinding = _simulationDate
        context.coordinator.planetariumHeadingBinding = _planetariumHeadingDegrees
        if let interactiveView = nsView as? InteractiveMetalView {
            interactiveView.isPhotoMode = isPhotoMode
            interactiveView.onExitPhotoMode = exitPhotoMode
            if isPhotoMode {
                interactiveView.window?.makeFirstResponder(interactiveView)
            }
        }
        context.coordinator.renderer?.viewport = viewport
        context.coordinator.renderer?.update(
            body: selectedBody,
            cameraDistance: Float(cameraDistance),
            timeRate: timeRate,
            isPaused: isPaused,
            isLiveView: isLiveView,
            options: options,
            observationMode: observationMode,
            planetariumLocation: planetariumLocation,
            lockedBodyID: lockedBodyID
        )
        context.coordinator.renderer?.onBodyPick = { bodyID in
            DispatchQueue.main.async {
                selectBodyFromViewport(bodyID)
            }
        }
        
        if dateSelectionTrigger != context.coordinator.lastDateSelectionTrigger {
            context.coordinator.lastDateSelectionTrigger = dateSelectionTrigger
            context.coordinator.renderer?.jump(to: simulationDate)
        }

        if photoCaptureTrigger != context.coordinator.lastPhotoCaptureTrigger {
            context.coordinator.lastPhotoCaptureTrigger = photoCaptureTrigger
            context.coordinator.renderer?.requestPhotoCapture()
        }
    }

    final class Coordinator {
        var renderer: PlanetRenderer?
        var cameraDistanceBinding: Binding<Double>?
        var simulationDateBinding: Binding<Date>?
        var planetariumHeadingBinding: Binding<Double>?
        var lastDateSelectionTrigger: Bool = false
        var lastPhotoCaptureTrigger: Bool = false
    }
}

protocol MetalCameraInputDelegate: AnyObject {
    func rotateCamera(deltaX: Float, deltaY: Float, viewportSize: CGSize)
    func zoomCamera(delta: Float)
    func pickBody(at point: CGPoint, viewportSize: CGSize)
    func movePhotoCamera(_ move: PhotoCameraMove)
    func requestPhotoCapture()
}

enum PhotoCameraMove {
    case forward
    case backward
    case left
    case right
    case up
    case down
}

final class InteractiveMetalView: MTKView {
    weak var cameraDelegate: MetalCameraInputDelegate?
    var isPhotoMode = false
    var onExitPhotoMode: (() -> Void)?
    private var mouseDownLocation = CGPoint.zero
    private var lastMouseLocation = CGPoint.zero
    private var didDragSinceMouseDown = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        lastMouseLocation = mouseDownLocation
        didDragSinceMouseDown = false
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        lastMouseLocation = mouseDownLocation
        didDragSinceMouseDown = false
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y)
        guard !didDragSinceMouseDown, distance < 4 else {
            return
        }

        cameraDelegate?.pickBody(
            at: CGPoint(x: location.x, y: bounds.height - location.y),
            viewportSize: bounds.size
        )
    }

    override func mouseDragged(with event: NSEvent) {
        didDragSinceMouseDown = true
        let location = convert(event.locationInWindow, from: nil)
        let deltaX = location.x - lastMouseLocation.x
        let deltaY = lastMouseLocation.y - location.y
        lastMouseLocation = location

        cameraDelegate?.rotateCamera(
            deltaX: Float(deltaX),
            deltaY: Float(deltaY),
            viewportSize: bounds.size
        )
    }

    override func rightMouseDragged(with event: NSEvent) {
        didDragSinceMouseDown = true
        let location = convert(event.locationInWindow, from: nil)
        let deltaX = location.x - lastMouseLocation.x
        let deltaY = lastMouseLocation.y - location.y
        lastMouseLocation = location

        cameraDelegate?.rotateCamera(
            deltaX: Float(deltaX),
            deltaY: Float(deltaY),
            viewportSize: bounds.size
        )
    }

    override func scrollWheel(with event: NSEvent) {
        cameraDelegate?.zoomCamera(delta: Float(event.scrollingDeltaY))
    }

    override func keyDown(with event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }

        if key == "s",
           event.modifierFlags.contains(.command),
           event.modifierFlags.contains(.shift) {
            cameraDelegate?.requestPhotoCapture()
            return
        }

        guard isPhotoMode else {
            super.keyDown(with: event)
            return
        }

        switch key {
        case "w":
            cameraDelegate?.movePhotoCamera(.forward)
        case "s":
            cameraDelegate?.movePhotoCamera(.backward)
        case "a":
            cameraDelegate?.movePhotoCamera(.left)
        case "d":
            cameraDelegate?.movePhotoCamera(.right)
        case "e":
            cameraDelegate?.movePhotoCamera(.up)
        case "q":
            cameraDelegate?.movePhotoCamera(.down)
        case "\u{1b}":
            onExitPhotoMode?()
        default:
            super.keyDown(with: event)
        }
    }
}
#endif
