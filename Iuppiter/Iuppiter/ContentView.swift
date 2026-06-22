import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var session = ObservationSession()
    @State private var sidebarVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var isInspectorPresented = true
    @State private var photoExportDocument = PNGPhotoDocument()
    @State private var isPhotoExporterPresented = false
    @State private var photoExportFilename = "Iuppiter.png"
    @State private var rendererAlert: RendererAlert?
    #if os(macOS)
    @State private var viewport = SolarSystemViewport()
    #endif

    private var selectedBody: NativeCelestialBody {
        session.selectedBody
    }

    private var visibleBodies: [NativeCelestialBody] {
        session.visibleBodies
    }

    private var simulationDateSelection: Binding<Date> {
        Binding(
            get: { session.simulationDate },
            set: { session.setSimulationDate($0) }
        )
    }

    private var viewportCameraDistance: Binding<Double> {
        Binding(
            get: { session.viewportCameraDistance },
            set: { session.viewportCameraDistance = $0 }
        )
    }

    private var sidebarSelection: Binding<String> {
        Binding(
            get: { session.selectedBodyID },
            set: { session.lockBody($0) }
        )
    }

    var body: some View {
        @Bindable var session = session

        Group {
            if session.isPhotoMode {
                ZStack(alignment: .topTrailing) {
                    viewportScene(isPhotoMode: true)

                    PhotoModeToolbar(
                        capturePhoto: session.capturePhoto,
                        exitPhotoMode: { setPhotoMode(false) }
                    )
                    .padding(18)
                }
                .background(.black)
                .ignoresSafeArea()
            } else {
                NavigationSplitView(columnVisibility: $sidebarVisibility) {
                    BodiesSidebar(
                        bodies: visibleBodies,
                        selectedBodyID: sidebarSelection
                    )
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 320)
                } detail: {
                    viewportScene(isPhotoMode: false)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    isInspectorPresented.toggle()
                                } label: {
                                    Label("Inspector", systemImage: "sidebar.trailing")
                                }
                                .help("Toggle Inspector")
                                .keyboardShortcut("i", modifiers: [.command, .option])
                            }
                        }
                        .inspector(isPresented: $isInspectorPresented) {
                            InspectorControls(
                                selectedBody: selectedBody,
                                cameraDistance: viewportCameraDistance,
                                timeRate: $session.timeRate,
                                isPaused: $session.isPaused,
                                isLiveView: $session.isLiveView,
                                simulationDate: simulationDateSelection,
                                photoCaptureTrigger: $session.photoCaptureTrigger,
                                observationMode: $session.observationMode,
                                planetariumLocation: $session.planetariumLocation,
                                options: $session.options,
                                isTargetLocked: session.lockedBodyID != nil,
                                clearTargetLock: session.clearBodyLock,
                                setPhotoMode: setPhotoMode
                            )
                            .inspectorColumnWidth(min: 180, ideal: 240, max: 280)
                            .formStyle(.grouped)
                        }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: visibleBodies) { _, newValue in
            session.handleVisibleBodiesChanged(newValue)
        }
        .onChange(of: session.observationMode) { _, newValue in
            session.handleObservationModeChanged(newValue)
        }
        .fileExporter(
            isPresented: $isPhotoExporterPresented,
            document: photoExportDocument,
            contentType: .png,
            defaultFilename: photoExportFilename
        ) { result in
            if case .failure(let error) = result {
                reportRendererError("Photo export failed: \(error.localizedDescription)")
            }
        }
        .alert(item: $rendererAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func viewportScene(isPhotoMode: Bool) -> some View {
        @Bindable var session = session

        ZStack(alignment: .bottomLeading) {
            #if os(macOS)
                MetalSolarSystemView(
                    selectedBody: selectedBody,
                    lockedBodyID: session.lockedBodyID,
                    cameraDistance: viewportCameraDistance,
                    timeRate: session.timeRate,
                    isPaused: session.isPaused,
                    isLiveView: $session.isLiveView,
                    simulationDate: $session.simulationDate,
                    dateSelectionTrigger: $session.dateSelectionTrigger,
                    planetariumHeadingDegrees: $session.planetariumHeadingDegrees,
                    photoCaptureTrigger: $session.photoCaptureTrigger,
                    viewport: viewport,
                    options: isPhotoMode ? session.options.photoModeOptions : session.options,
                    observationMode: session.observationMode,
                    planetariumLocation: session.planetariumLocation,
                    isPhotoMode: isPhotoMode,
                    selectBodyFromViewport: session.handleViewportPick,
                    exportPhoto: exportPhoto,
                    reportRendererError: reportRendererError,
                    exitPhotoMode: { setPhotoMode(false) }
                )
            if !isPhotoMode {
                SolarSystemLabelsOverlay(labels: viewport.labels) { bodyID in
                    session.lockBody(bodyID)
                }
            }
            if session.observationMode == .planetarium, !isPhotoMode {
                PlanetariumCompassOverlay(headingDegrees: session.planetariumHeadingDegrees)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(16)
                    .allowsHitTesting(false)
            }
            #else
            Text("Metal renderer is currently enabled for macOS.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif


        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func exportPhoto(_ data: Data) {
        photoExportDocument = PNGPhotoDocument(data: data)
        photoExportFilename = Self.photoExportFilename()
        isPhotoExporterPresented = true
    }

    private func setPhotoMode(_ enabled: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            session.setPhotoMode(enabled)
        }
    }

    private func reportRendererError(_ message: String) {
        guard rendererAlert?.message != message else {
            return
        }
        rendererAlert = RendererAlert(message: message)
    }

    private static func photoExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Iuppiter-\(formatter.string(from: Date())).png"
    }
}

private struct RendererAlert: Identifiable {
    let id = UUID()
    let title = "Renderer Issue"
    let message: String
}

#if os(macOS)
private struct PlanetariumCompassOverlay: View {
    let headingDegrees: Double

    @ScaledMetric(relativeTo: .title) private var iconSize = 52

    private var normalizedHeading: Double {
        PlanetariumHeading.normalizedDegrees(headingDegrees)
    }

    private var cardinalDirection: String {
        PlanetariumHeading.cardinalDirection(for: headingDegrees)
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: iconSize))
                .symbolRenderingMode(.hierarchical)
                .rotationEffect(.degrees(-normalizedHeading))
                .animation(.easeOut(duration: 0.12), value: normalizedHeading)

            Text("\(cardinalDirection) · \(Int(normalizedHeading.rounded()))°")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heading \(cardinalDirection), \(Int(normalizedHeading.rounded())) degrees")
    }
}

private struct SolarSystemLabelsOverlay: View {
    let labels: [SolarSystemLabel]
    let selectBody: (String) -> Void

    var body: some View {
        GeometryReader { _ in
            ForEach(labels) { label in
                Button {
                    selectBody(label.id)
                } label: {
                    Text(label.name)
                        .font(label.isSelected ? .callout.weight(.semibold) : .caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, label.isSelected ? 7 : 5)
                        .padding(.vertical, label.isSelected ? 4 : 2)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 1)
                        .background(label.isSelected ? label.displayColor.opacity(0.28) : .black.opacity(0.01))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(label.isSelected ? label.displayColor.opacity(0.8) : .clear, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .position(label.position)
                .accessibilityLabel(label.name)
            }
        }
    }
}
#endif


private struct PhotoModeToolbar: View {
    let capturePhoto: () -> Void
    let exitPhotoMode: () -> Void

    var body: some View {
        ControlGroup {
            Button(action: capturePhoto) {
                Label("Save Photo", systemImage: "square.and.arrow.down")
            }
            .help("Save full resolution photo")

            Button(action: exitPhotoMode) {
                Label("Exit Photo", systemImage: "xmark")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help("Exit photo mode")
        }
        .controlSize(.large)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}





private struct InspectorControls: View {
    let selectedBody: NativeCelestialBody
    @Binding var cameraDistance: Double
    @Binding var timeRate: Double
    @Binding var isPaused: Bool
    @Binding var isLiveView: Bool
    @Binding var simulationDate: Date
    @Binding var photoCaptureTrigger: Bool
    @Binding var observationMode: ObservationMode
    @Binding var planetariumLocation: PlanetariumLocation
    @Binding var options: NativeRenderOptions
    let isTargetLocked: Bool
    let clearTargetLock: () -> Void
    let setPhotoMode: (Bool) -> Void

    private var timeRateIndex: Binding<Double> {
        Binding(
            get: { Double(TimeRatePreset.closestIndex(to: timeRate)) },
            set: { newValue in
                let index = min(
                    max(Int(newValue.rounded()), 0),
                    TimeRatePreset.all.count - 1
                )
                timeRate = TimeRatePreset.all[index].secondsPerSecond
            }
        )
    }

    private var cameraControlValue: Binding<Double> {
        Binding(
            get: {
                if observationMode == .planetarium {
                    return log10(max(cameraDistance, 1))
                }
                return log10(cameraDistance)
            },
            set: { newValue in
                if observationMode == .planetarium {
                    cameraDistance = min(PlanetariumLimits.maxZoom, max(PlanetariumLimits.minZoom, pow(10, newValue)))
                } else {
                    cameraDistance = pow(10, newValue)
                }
            }
        )
    }

    private var cameraControlRange: ClosedRange<Double> {
        observationMode == .planetarium ? 0.0...log10(PlanetariumLimits.maxZoom) : -5.0...2.4
    }

    private var cameraControlLabel: String {
        observationMode == .planetarium ? "Zoom" : "Camera Distance"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Target") {
                    Text(observationMode == .planetarium ? "Planetarium" : selectedBody.name)
                        .fontWeight(.semibold)
                }

                if observationMode == .planetarium {
                    LabeledContent("Location") {
                        Text(planetariumLocation.name)
                    }
                } else {
                    LabeledContent("Radius") {
                        Text("\(selectedBody.radiusKilometers.formatted()) km")
                    }

                    if let orbitText = selectedBody.orbitSummary {
                        Text(orbitText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Status") {
                    Text(isTargetLocked ? "Target locked" : "Free view")
                        .foregroundStyle(isTargetLocked ? .primary : .secondary)
                }
            }

            Section("Observation") {
                Picker("Mode", selection: $observationMode) {
                    ForEach(ObservationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent(cameraControlLabel) {
                    if observationMode == .planetarium {
                        Text("\(Int(cameraDistance.rounded()))×")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Slider(value: cameraControlValue, in: cameraControlRange)
            }

            Section("Time") {
                DatePicker(
                    "Date & Time",
                    selection: $simulationDate,
                    displayedComponents: [.date, .hourAndMinute]
                )

                if isLiveView {
                    LabeledContent("Speed") {
                        Text("Live")
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                } else {
                    LabeledContent("Speed") {
                        Text(TimeRatePreset.label(for: timeRate))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: timeRateIndex,
                        in: 0...Double(TimeRatePreset.all.count - 1),
                        step: 1
                    )
                }

                Text(simulationDate.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                ControlGroup {
                    Button {
                        isPaused.toggle()
                    } label: {
                        Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    }
                    .help(isPaused ? "Resume simulation" : "Pause simulation")

                    Button {
                        timeRate = TimeRatePreset.all[0].secondsPerSecond
                        isPaused = false
                    } label: {
                        Label("1×", systemImage: "clock.arrow.circlepath")
                    }
                    .help("Reset simulation speed to 1 s/s")

                    Button {
                        simulationDate = Date()
                    } label: {
                        Label("Now", systemImage: "calendar")
                    }
                    .help("Set simulation date to current time")

                    Button {
                        isLiveView.toggle()
                        if isLiveView {
                            isPaused = false
                        }
                    } label: {
                        Label("Live", systemImage: "livephoto")
                    }
                    .help("Sync to real-time clock")
                }
            }

            Section("Display") {
                Toggle("Orbit Lines", isOn: $options.showOrbits)
                Toggle("Nametags", isOn: $options.showLabels)
            }

            Section("Capture") {
                ControlGroup {
                    Button {
                        setPhotoMode(true)
                    } label: {
                        Label("Photo Mode", systemImage: "camera.viewfinder")
                    }
                    .help("Enter photo mode")

                    Button {
                        photoCaptureTrigger.toggle()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .help("Save snapshot of current view")
                }
            }

            Section {
                Button {
                    clearTargetLock()
                } label: {
                    Label("Clear Target Lock", systemImage: "scope")
                }
                .disabled(!isTargetLocked)
                .help("Clear lock on selected celestial body")
            }

            if observationMode == .planetarium {
                Section("Location") {
                    PlanetariumLocationControls(location: $planetariumLocation)
                }
            }
        }
        .onChange(of: timeRate) { _, _ in
            isLiveView = false
        }
        .onChange(of: isPaused) { _, newValue in
            if newValue {
                isLiveView = false
            }
        }
    }
}

private struct PlanetariumLocationControls: View {
    @Binding var location: PlanetariumLocation

    private var latitude: Binding<Double> {
        Binding(
            get: { location.latitudeDegrees },
            set: { newValue in
                location.latitudeDegrees = min(90, max(-90, newValue))
                location.name = "Custom Location"
            }
        )
    }

    private var longitude: Binding<Double> {
        Binding(
            get: { location.longitudeDegrees },
            set: { newValue in
                location.longitudeDegrees = min(180, max(-180, newValue))
                location.name = "Custom Location"
            }
        )
    }

    private var presetName: Binding<String> {
        Binding(
            get: {
                if PlanetariumLocation.presets.contains(where: { $0.name == location.name }) {
                    return location.name
                }
                return "Custom"
            },
            set: { newName in
                if let preset = PlanetariumLocation.presets.first(where: { $0.name == newName }) {
                    location = preset
                }
            }
        )
    }

    var body: some View {
        Picker("Preset", selection: presetName) {
            Text("Custom").tag("Custom")
            ForEach(PlanetariumLocation.presets, id: \.name) { preset in
                Text(preset.name).tag(preset.name)
            }
        }

        CoordinateControl(
            title: "Latitude",
            value: latitude,
            range: -90...90,
            rangeLabel: "-90...90"
        )

        CoordinateControl(
            title: "Longitude",
            value: longitude,
            range: -180...180,
            rangeLabel: "-180...180"
        )
    }
}

private struct CoordinateControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let rangeLabel: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(4)))
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 96)

                Stepper(title, value: $value, in: range, step: 0.1)
                    .labelsHidden()

                Text(rangeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .leading)
            }
        }
    }
}

private extension NativeRenderOptions {
    var photoModeOptions: NativeRenderOptions {
        var copy = self
        copy.showLabels = false
        copy.showOrbits = false
        return copy
    }
}

private extension NativeCelestialBody {
    var orbitSummary: String? {
        guard let parentID, let semiMajorAxisKilometers else {
            return nil
        }
        let au = semiMajorAxisKilometers / SolarSystemSimulation.astronomicalUnitKilometers
        let parentName = NativeBodyCatalog.body(withID: parentID)?.name ?? parentID
        if parentID == "sun" {
            return "Orbiting \(parentName) at \(au.formatted(.number.precision(.fractionLength(2)))) AU"
        }
        return "Orbiting \(parentName) at \(semiMajorAxisKilometers.formatted()) km"
    }
}
