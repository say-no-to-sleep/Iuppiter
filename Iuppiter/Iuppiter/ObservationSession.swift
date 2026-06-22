import Foundation
import Observation

@Observable
final class ObservationSession {
    var selectedBodyID = NativeBodyCatalog.defaultSelection.id
    var lockedBodyID: String? = NativeBodyCatalog.defaultSelection.id
    var cameraDistance: Double = 72.0
    var planetariumZoom: Double = 1.0
    var timeRate: Double = TimeRatePreset.all[0].secondsPerSecond
    var isPaused = false
    var isLiveView = true
    var simulationDate = Date()
    var dateSelectionTrigger = false
    var photoCaptureTrigger = false
    var options = NativeRenderOptions()
    var isPhotoMode = false
    var observationMode: ObservationMode = .orbit
    var planetariumLocation = PlanetariumLocation.waterloo
    var planetariumHeadingDegrees = 0.0

    var selectedBody: NativeCelestialBody {
        NativeBodyCatalog.body(withID: selectedBodyID) ?? NativeBodyCatalog.defaultSelection
    }

    var visibleBodies: [NativeCelestialBody] {
        NativeBodyCatalog.visibleBodies(options: options)
    }

    var viewportCameraDistance: Double {
        get {
            observationMode == .planetarium ? planetariumZoom : cameraDistance
        }
        set {
            if observationMode == .planetarium {
                planetariumZoom = min(PlanetariumLimits.maxZoom, max(PlanetariumLimits.minZoom, newValue))
            } else {
                cameraDistance = newValue
            }
        }
    }

    func setSimulationDate(_ date: Date) {
        simulationDate = date
        dateSelectionTrigger.toggle()
        isLiveView = false
    }

    func lockBody(_ bodyID: String) {
        guard NativeBodyCatalog.body(withID: bodyID) != nil else {
            return
        }
        selectedBodyID = bodyID
        lockedBodyID = observationMode == .planetarium && bodyID == "earth" ? nil : bodyID
    }

    func handleViewportPick(_ bodyID: String?) {
        if let bodyID {
            lockBody(bodyID)
        } else {
            clearBodyLock()
        }
    }

    func clearBodyLock() {
        lockedBodyID = nil
        selectedBodyID = observationMode == .planetarium ? "earth" : NativeBodyCatalog.defaultSelection.id
    }

    func setPhotoMode(_ enabled: Bool) {
        guard isPhotoMode != enabled else {
            return
        }
        isPhotoMode = enabled
    }

    func capturePhoto() {
        photoCaptureTrigger.toggle()
    }

    func handleVisibleBodiesChanged(_ bodies: [NativeCelestialBody]) {
        if !bodies.contains(where: { $0.id == selectedBodyID }) {
            selectedBodyID = bodies.first?.id ?? NativeBodyCatalog.defaultSelection.id
        }
    }

    func handleObservationModeChanged(_ mode: ObservationMode) {
        if mode == .planetarium {
            selectedBodyID = "earth"
            lockedBodyID = nil
        } else if lockedBodyID == nil {
            selectedBodyID = NativeBodyCatalog.defaultSelection.id
        }
    }
}
