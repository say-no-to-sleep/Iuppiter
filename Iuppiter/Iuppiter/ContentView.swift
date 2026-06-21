import SwiftUI

struct ContentView: View {
    @State private var selectedBodyID = NativeBodyCatalog.defaultSelection.id
    @State private var lockedBodyID: String? = NativeBodyCatalog.defaultSelection.id
    @State private var cameraDistance: Double = 72.0
    @State private var planetariumZoom: Double = 1.0
    @State private var timeRate: Double = TimeRatePreset.all[0].secondsPerSecond
    @State private var isPaused = false
    @State private var isLiveView = true
    @State private var simulationDate = Date()
    @State private var dateSelectionTrigger = false
    @State private var photoCaptureTrigger = false
    @State private var options = NativeRenderOptions()
    @State private var isPhotoMode = false
    @State private var observationMode: ObservationMode = .orbit
    @State private var planetariumLocation = PlanetariumLocation.waterloo
    @State private var planetariumHeadingDegrees = 0.0
    @State private var sidebarVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var isInspectorPresented = true
    #if os(macOS)
    @State private var viewport = SolarSystemViewport()
    #endif

    private var selectedBody: NativeCelestialBody {
        NativeBodyCatalog.body(withID: selectedBodyID) ?? NativeBodyCatalog.defaultSelection
    }

    private var visibleBodies: [NativeCelestialBody] {
        NativeBodyCatalog.bodies.filter { body in
            if body.kind != .moon { return true }
            if !options.showMoons { return false }
            if !options.showProcedural && body.assetTier == "procedural" { return false }
            return options.showMinorMoons || body.isMajor || body.parentID == "earth"
        }
    }

    private var simulationDateSelection: Binding<Date> {
        Binding(
            get: { simulationDate },
            set: { setSimulationDate($0) }
        )
    }

    private var viewportCameraDistance: Binding<Double> {
        Binding(
            get: {
                observationMode == .planetarium ? planetariumZoom : cameraDistance
            },
            set: { newValue in
                if observationMode == .planetarium {
                    planetariumZoom = min(PlanetariumLimits.maxZoom, max(PlanetariumLimits.minZoom, newValue))
                } else {
                    cameraDistance = newValue
                }
            }
        )
    }

    var body: some View {
        Group {
            if isPhotoMode {
                ZStack(alignment: .topTrailing) {
                    viewportScene(isPhotoMode: true)

                    PhotoModeToolbar(
                        capturePhoto: capturePhoto,
                        exitPhotoMode: { setPhotoMode(false) }
                    )
                    .padding(18)
                }
                .background(.black)
                .ignoresSafeArea()
            } else {
                NavigationSplitView(columnVisibility: $sidebarVisibility) {
                    SidebarViewController(
                        bodies: visibleBodies,
                        selectedBodyID: selectedBodyID,
                        selectBody: lockBody
                    )
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 320)
                } detail: {
                    viewportScene(isPhotoMode: false)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    isInspectorPresented.toggle()
                                } label: {
                                    Image(systemName: "sidebar.trailing")
                                }
                                .help("Toggle Inspector")
                                .accessibilityLabel("Toggle Inspector")
                            }
                        }
                        .inspector(isPresented: $isInspectorPresented) {
                            InspectorControls(
                                selectedBody: selectedBody,
                                cameraDistance: viewportCameraDistance,
                                timeRate: $timeRate,
                                isPaused: $isPaused,
                                isLiveView: $isLiveView,
                                simulationDate: simulationDateSelection,
                                photoCaptureTrigger: $photoCaptureTrigger,
                                observationMode: $observationMode,
                                planetariumLocation: $planetariumLocation,
                                planetariumHeadingDegrees: planetariumHeadingDegrees,
                                options: $options,
                                isTargetLocked: lockedBodyID != nil,
                                clearTargetLock: clearBodyLock,
                                setPhotoMode: setPhotoMode
                            )
                            .inspectorColumnWidth(min: 180, ideal: 240, max: 280)
                        }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: visibleBodies) { _, newValue in
            // Fallback selection if current selection becomes hidden
            if !newValue.contains(where: { $0.id == selectedBodyID }) {
                selectedBodyID = newValue.first?.id ?? NativeBodyCatalog.defaultSelection.id
            }
        }
        .onChange(of: observationMode) { _, newValue in
            if newValue == .planetarium {
                selectedBodyID = "earth"
                lockedBodyID = nil
            } else if lockedBodyID == nil {
                selectedBodyID = NativeBodyCatalog.defaultSelection.id
            }
        }
    }

    @ViewBuilder
    private func viewportScene(isPhotoMode: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            #if os(macOS)
                MetalSolarSystemView(
                    selectedBody: selectedBody,
                    lockedBodyID: lockedBodyID,
                    cameraDistance: viewportCameraDistance,
                    timeRate: timeRate,
                    isPaused: isPaused,
                    isLiveView: $isLiveView,
                    simulationDate: $simulationDate,
                    dateSelectionTrigger: $dateSelectionTrigger,
                    planetariumHeadingDegrees: $planetariumHeadingDegrees,
                    photoCaptureTrigger: $photoCaptureTrigger,
                    viewport: viewport,
                    options: isPhotoMode ? options.photoModeOptions : options,
                    observationMode: observationMode,
                    planetariumLocation: planetariumLocation,
                    isPhotoMode: isPhotoMode,
                    selectBodyFromViewport: handleViewportPick,
                    exitPhotoMode: { setPhotoMode(false) }
                )
            if !isPhotoMode {
                SolarSystemLabelsOverlay(labels: viewport.labels) { bodyID in
                    lockBody(bodyID)
                }
            }
            if observationMode == .planetarium, !isPhotoMode {
                PlanetariumCompassOverlay(headingDegrees: planetariumHeadingDegrees)
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

    private func setSimulationDate(_ date: Date) {
        simulationDate = date
        dateSelectionTrigger.toggle()
        isLiveView = false
    }

    private func lockBody(_ bodyID: String) {
        guard NativeBodyCatalog.body(withID: bodyID) != nil else {
            return
        }
        selectedBodyID = bodyID
        lockedBodyID = observationMode == .planetarium && bodyID == "earth" ? nil : bodyID
    }

    private func handleViewportPick(_ bodyID: String?) {
        if let bodyID {
            lockBody(bodyID)
        } else {
            clearBodyLock()
        }
    }

    private func clearBodyLock() {
        lockedBodyID = nil
        selectedBodyID = observationMode == .planetarium ? "earth" : NativeBodyCatalog.defaultSelection.id
    }

    private func toggleSidebar() {
        withAnimation(.smooth(duration: 0.18)) {
            sidebarVisibility = sidebarVisibility == .detailOnly ? .doubleColumn : .detailOnly
        }
    }

    private func setPhotoMode(_ enabled: Bool) {
        guard isPhotoMode != enabled else {
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            isPhotoMode = enabled
        }
    }

    private func capturePhoto() {
        photoCaptureTrigger.toggle()
    }
}

#if os(macOS)
private struct PlanetariumCompassOverlay: View {
    let headingDegrees: Double

    private var normalizedHeading: Double {
        var value = headingDegrees.truncatingRemainder(dividingBy: 360)
        if value < 0 {
            value += 360
        }
        return value
    }

    private var cardinalDirection: String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalizedHeading / 45.0).rounded()) % directions.count
        return directions[index]
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 52))
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
        HStack(spacing: 8) {
            Button(action: capturePhoto) {
                Label("Save Photo", systemImage: "square.and.arrow.down")
            }
            .accessibilityLabel("Save full resolution photo")

            Button(action: exitPhotoMode) {
                Label("Exit Photo", systemImage: "xmark")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .accessibilityLabel("Exit photo mode")
        }
        .buttonStyle(.bordered)
        .padding(10)
        .controlGlass(cornerRadius: 12, interactive: true)
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
    let planetariumHeadingDegrees: Double
    @Binding var options: NativeRenderOptions
    let isTargetLocked: Bool
    let clearTargetLock: () -> Void
    let setPhotoMode: (Bool) -> Void

    private var normalizedHeading: Double {
        var value = planetariumHeadingDegrees.truncatingRemainder(dividingBy: 360)
        if value < 0 {
            value += 360
        }
        return value
    }

    private var cardinalDirection: String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalizedHeading / 45.0).rounded()) % directions.count
        return directions[index]
    }

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

    var body: some View {
        Form {
            // Target Info Section
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

            // Observation Mode Section
            Section("Observation") {
                Picker("Mode", selection: $observationMode) {
                    ForEach(ObservationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(observationMode == .planetarium ? "Zoom" : "Camera Distance")
                        Spacer()
                        if observationMode == .planetarium {
                            Text("\(Int(cameraDistance.rounded()))×")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Slider(value: cameraControlValue, in: cameraControlRange)
                }
            }

            // Time Controls Section
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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Speed")
                            Spacer()
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
                }

                Text(simulationDate.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
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
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Display Options Section
            Section("Display") {
                Toggle("Orbit Lines", isOn: $options.showOrbits)
                Toggle("Nametags", isOn: $options.showLabels)
            }

            // Capture Section
            Section("Capture") {
                HStack(spacing: 8) {
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
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Lock Controls
            Section {
                Button {
                    clearTargetLock()
                } label: {
                    Label("Clear Target Lock", systemImage: "scope")
                }
                .disabled(!isTargetLocked)
                .help("Clear lock on selected celestial body")
            }

            // Conditional Planetarium Location Controls
            if observationMode == .planetarium {
                Section("Heading") {
                    LabeledContent("Direction") {
                        Text(cardinalDirection)
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Bearing") {
                        Text("\(Int(normalizedHeading.rounded()))°")
                            .monospacedDigit()
                    }
                }

                Section("Location") {
                    PlanetariumLocationControls(location: $planetariumLocation)
                }
            }
        }
        .formStyle(.grouped)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    ForEach(PlanetariumLocation.presets, id: \.name) { preset in
                        Button(preset.name) {
                            location = preset
                        }
                    }
                } label: {
                    Label("Presets", systemImage: "mappin.and.ellipse")
                }
            }

            HStack(spacing: 10) {
                CoordinateField(title: "Lat", value: latitude, range: -90...90)
                CoordinateField(title: "Lon", value: longitude, range: -180...180)
            }
        }
    }
}



private struct CoordinateField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            TextField(
                title,
                value: $value,
                format: .number.precision(.fractionLength(4))
            )
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: 92)

            Stepper(title, value: $value, in: range, step: 0.1)
                .labelsHidden()
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

#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
#endif

struct ControlGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool = true
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    #if os(macOS)
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    #else
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    #endif
                    
                    // Liquid glass sheen overlay (gloss)
                    LinearGradient(
                        colors: [
                            .white.opacity(0.15),
                            .white.opacity(0.03),
                            .clear,
                            .black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    
                    // Shiny bevel border (specular edges)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.4),
                                    .white.opacity(0.1),
                                    .clear,
                                    .black.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func controlGlass(cornerRadius: CGFloat, interactive: Bool = true) -> some View {
        self.modifier(ControlGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

