import Foundation
import simd

struct NativeRenderOptions: Equatable, Sendable {
    var showMoons: Bool = true
    var showMinorMoons: Bool = true
    var showProcedural: Bool = true
    var showLabels: Bool = true
    var showOrbits: Bool = true
}

struct NativeBodyRenderState {
    let body: NativeCelestialBody
    let position: SIMD3<Float>
    let sceneRadius: Float
    let rotationAngleRadians: Float
}

struct NativeOrbitPath {
    let bodyID: String
    let parentID: String?
    let center: SIMD3<Float>
    let semiMajorAxis: Float
    let eccentricity: Float
    let inclination: Float
    let longitudeOfAscendingNode: Float
    let argumentOfPeriapsis: Float
    let referencePlane: String
    let parentAxialTiltDegrees: Float
    let currentEccentricAnomaly: Float
    let color: SIMD4<Float>
}

struct SolarSystemSnapshot {
    let states: [NativeBodyRenderState]
    let orbitPaths: [NativeOrbitPath]
    let selectedState: NativeBodyRenderState
    let sunPosition: SIMD3<Float>
}

enum SolarSystemSimulation {
    static let astronomicalUnitKilometers = 149_597_870.7
    static let sceneUnitsPerAU: Float = 6.0
    static let daysPerSimulationSecond = 5.0
    static let calendarSecondsPerSimulationSecond = daysPerSimulationSecond * 86_400.0
    private static let charonToPlutoMassRatio: Float = 0.12175
    private static let plutoBinaryRadiusFraction = charonToPlutoMassRatio / (1.0 + charonToPlutoMassRatio)
    private static let charonBinaryRadiusFraction = 1.0 / (1.0 + charonToPlutoMassRatio)
    private static let j2000Epoch = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(abbreviation: "UTC"),
        year: 2000,
        month: 1,
        day: 1,
        hour: 12,
        minute: 0,
        second: 0
    ).date!

    static func simulatedSeconds(for date: Date = Date()) -> Double {
        daysSinceJ2000(for: date) / daysPerSimulationSecond
    }

    static func date(forSimulatedSeconds simulatedSeconds: Double) -> Date {
        j2000Epoch.addingTimeInterval(simulatedSeconds * calendarSecondsPerSimulationSecond)
    }

    static func daysSinceJ2000(for date: Date = Date()) -> Double {
        date.timeIntervalSince(j2000Epoch) / 86_400.0
    }

    static func snapshot(
        elapsedSeconds: Double,
        selectedBodyID: String,
        options: NativeRenderOptions
    ) -> SolarSystemSnapshot {
        let days = elapsedSeconds * daysPerSimulationSecond
        var positionsByID: [String: SIMD3<Float>] = [:]
        var states: [NativeBodyRenderState] = []
        var orbits: [NativeOrbitPath] = []
        var plutoCharonBarycenter: SIMD3<Float>?
        var plutoCharonRelativeOffset: SIMD3<Float>?
        var plutoCharonEccentricAnomaly: Float?
        var plutoCharonSceneSeparation: Float?

        let visibleBodies = NativeBodyCatalog.bodies.filter { body in
            if body.kind != .moon { return true }
            if !options.showMoons { return false }
            if !options.showProcedural && body.assetTier == "procedural" { return false }
            return options.showMinorMoons || body.isMajor || body.parentID == "earth"
        }

        for body in visibleBodies {
            let nominalParentPosition = body.parentID.flatMap { positionsByID[$0] } ?? .zero
            let parentPosition =
                body.parentID == "pluto" && body.id != "charon"
                    ? (plutoCharonBarycenter ?? nominalParentPosition)
                    : nominalParentPosition
            let parentBody = body.parentID.flatMap { NativeBodyCatalog.body(withID: $0) }
            var position: SIMD3<Float>

            if let semiMajorAxis = body.semiMajorAxisKilometers, semiMajorAxis > 0, let period = body.orbitalPeriodDays {
                let sceneA = Float(semiMajorAxis / astronomicalUnitKilometers) * sceneUnitsPerAU
                let keplerResult = computeKeplerianOffset(
                    body: body,
                    days: days,
                    semiMajorAxis: sceneA,
                    period: period,
                    parentBody: parentBody
                )
                position = parentPosition + keplerResult.offset

                let parentTilt = parentBody?.axialTiltDegrees ?? 0.0
                if body.id == "pluto",
                   let charon = NativeBodyCatalog.body(withID: "charon"),
                   let binary = plutoCharonRelativeOrbit(days: days, pluto: body) {
                    let barycenter = position
                    plutoCharonBarycenter = barycenter
                    plutoCharonRelativeOffset = binary.offset
                    plutoCharonEccentricAnomaly = binary.eccentricAnomaly
                    plutoCharonSceneSeparation = binary.sceneSeparation
                    position = barycenter - binary.offset * plutoBinaryRadiusFraction
                    appendOrbitPath(
                        for: body,
                        center: parentPosition,
                        semiMajorAxis: sceneA,
                        eccentricAnomaly: keplerResult.eccentricAnomaly,
                        parentTilt: parentTilt,
                        into: &orbits
                    )
                    appendOrbitPath(
                        for: charon,
                        center: barycenter,
                        semiMajorAxis: binary.sceneSeparation * plutoBinaryRadiusFraction,
                        eccentricAnomaly: binary.eccentricAnomaly,
                        parentTilt: body.axialTiltDegrees,
                        argumentOffset: .pi,
                        color: SIMD4<Float>(0.72, 0.62, 0.56, 0.28),
                        into: &orbits
                    )
                } else if body.id == "charon",
                          let barycenter = plutoCharonBarycenter,
                          let relativeOffset = plutoCharonRelativeOffset,
                          let eccentricAnomaly = plutoCharonEccentricAnomaly,
                          let sceneSeparation = plutoCharonSceneSeparation {
                    position = barycenter + relativeOffset * charonBinaryRadiusFraction
                    appendOrbitPath(
                        for: body,
                        center: barycenter,
                        semiMajorAxis: sceneSeparation * charonBinaryRadiusFraction,
                        eccentricAnomaly: eccentricAnomaly,
                        parentTilt: parentTilt,
                        into: &orbits
                    )
                } else {
                    appendOrbitPath(
                        for: body,
                        center: parentPosition,
                        semiMajorAxis: sceneA,
                        eccentricAnomaly: keplerResult.eccentricAnomaly,
                        parentTilt: parentTilt,
                        into: &orbits
                    )
                }
            } else {
                position = parentPosition
            }

            positionsByID[body.id] = position
            states.append(
                NativeBodyRenderState(
                    body: body,
                    position: position,
                    sceneRadius: sceneRadius(for: body),
                    rotationAngleRadians: rotationAngle(
                        for: body,
                        elapsedSeconds: elapsedSeconds,
                        daysSinceJ2000: days,
                        position: position,
                        parentPosition: parentPosition
                    )
                )
            )
        }

        let selected = states.first { $0.body.id == selectedBodyID } ?? states.first ?? NativeBodyRenderState(
            body: NativeBodyCatalog.defaultSelection,
            position: .zero,
            sceneRadius: 0.0279,
            rotationAngleRadians: 0
        )
        return SolarSystemSnapshot(
            states: states,
            orbitPaths: orbits,
            selectedState: selected,
            sunPosition: positionsByID["sun"] ?? .zero
        )
    }

    private static func plutoCharonRelativeOrbit(
        days: Double,
        pluto: NativeCelestialBody
    ) -> (offset: SIMD3<Float>, eccentricAnomaly: Float, sceneSeparation: Float)? {
        guard let charon = NativeBodyCatalog.body(withID: "charon"),
              let semiMajorAxis = charon.semiMajorAxisKilometers,
              let period = charon.orbitalPeriodDays,
              semiMajorAxis > 0 else {
            return nil
        }

        let sceneSeparation = Float(semiMajorAxis / astronomicalUnitKilometers) * sceneUnitsPerAU
        let orbit = computeKeplerianOffset(
            body: charon,
            days: days,
            semiMajorAxis: sceneSeparation,
            period: period,
            parentBody: pluto
        )

        return (orbit.offset, orbit.eccentricAnomaly, sceneSeparation)
    }

    private static func appendOrbitPath(
        for body: NativeCelestialBody,
        center: SIMD3<Float>,
        semiMajorAxis: Float,
        eccentricAnomaly: Float,
        parentTilt: Float,
        argumentOffset: Float = 0,
        color: SIMD4<Float>? = nil,
        into orbits: inout [NativeOrbitPath]
    ) {
        orbits.append(
            NativeOrbitPath(
                bodyID: body.id,
                parentID: body.parentID,
                center: center,
                semiMajorAxis: semiMajorAxis,
                eccentricity: Float(body.eccentricity),
                inclination: Float(body.inclinationDegrees * .pi / 180.0),
                longitudeOfAscendingNode: Float(body.longitudeOfAscendingNodeDegrees * .pi / 180.0),
                argumentOfPeriapsis: Float(body.argumentOfPeriapsisDegrees * .pi / 180.0) + argumentOffset,
                referencePlane: body.referencePlane,
                parentAxialTiltDegrees: parentTilt,
                currentEccentricAnomaly: eccentricAnomaly,
                color: color ?? orbitColor(for: body)
            )
        )
    }

    private static func computeKeplerianOffset(
        body: NativeCelestialBody,
        days: Double,
        semiMajorAxis: Float,
        period: Double,
        parentBody: NativeCelestialBody?
    ) -> (offset: SIMD3<Float>, eccentricAnomaly: Float) {
        let m0Rad = body.meanAnomalyAtEpochDegrees * .pi / 180.0
        // Normalize the initial mean anomaly calculation to [0, 2pi] to maintain high floating point precision
        let rawMeanAnomaly = m0Rad + (days / period) * 2.0 * .pi
        var meanAnomaly = rawMeanAnomaly.truncatingRemainder(dividingBy: 2.0 * .pi)
        if meanAnomaly < 0 {
            meanAnomaly += 2.0 * .pi
        }

        // Solve Kepler's equation: E - e sin E = M
        let ecc = body.eccentricity
        var E = meanAnomaly
        for _ in 0..<5 {
            E = E - (E - ecc * sin(E) - meanAnomaly) / (1.0 - ecc * cos(E))
        }

        // 1. Orbital plane coordinates (x towards periapsis)
        let xp = Double(semiMajorAxis) * (cos(E) - ecc)
        let zp = Double(semiMajorAxis) * sqrt(1.0 - ecc * ecc) * sin(E)
        let flat = SIMD3<Double>(xp, 0.0, zp)

        // 2. Rotate by argument of periapsis in plane (around Y-axis)
        let argPeriRad = body.argumentOfPeriapsisDegrees * .pi / 180.0
        let rotatedInPlane = rotateVectorD(flat, radians: -argPeriRad, axis: SIMD3<Double>(0, 1, 0))

        // 3. Tilt by inclination around X-axis
        let inclRad = body.inclinationDegrees * .pi / 180.0
        let tilted = rotateVectorD(rotatedInPlane, radians: inclRad, axis: SIMD3<Double>(1, 0, 0))

        // 4. Rotate by longitude of ascending node around Y-axis
        let nodeRad = body.longitudeOfAscendingNodeDegrees * .pi / 180.0
        let positioned = rotateVectorD(tilted, radians: -nodeRad, axis: SIMD3<Double>(0, 1, 0))

        // 5. If equatorial-referenced (BODY), tilt by the parent planet's axial tilt around the X-axis
        var finalOffset = positioned
        if body.referencePlane == "BODY", let parent = parentBody {
            let parentTiltRad = Double(parent.axialTiltDegrees) * .pi / 180.0
            finalOffset = rotateVectorD(positioned, radians: parentTiltRad, axis: SIMD3<Double>(1, 0, 0))
        }

        let displayOffset = displayCoordinateOffset(finalOffset)
        return (
            offset: SIMD3<Float>(Float(displayOffset.x), Float(displayOffset.y), Float(displayOffset.z)),
            eccentricAnomaly: Float(E)
        )
    }

    private static func displayCoordinateOffset(_ offset: SIMD3<Double>) -> SIMD3<Double> {
        // Horizons/J2000 vectors are right-handed, but the app's top-down camera
        // convention expects the horizontal orbital axis mirrored. Do this in
        // world space so textures and pointer controls are not screen-mirrored.
        SIMD3<Double>(-offset.x, offset.y, offset.z)
    }

    private static func rotateVectorD(_ vector: SIMD3<Double>, radians: Double, axis: SIMD3<Double>) -> SIMD3<Double> {
        let axis = normalize(axis)
        let cosAngle = cos(radians)
        let sinAngle = sin(radians)
        return vector * cosAngle + cross(axis, vector) * sinAngle + axis * dot(axis, vector) * (1.0 - cosAngle)
    }

    private static func sceneRadius(for body: NativeCelestialBody) -> Float {
        return Float(body.radiusKilometers / astronomicalUnitKilometers) * sceneUnitsPerAU
    }

    private static func rotationAngle(
        for body: NativeCelestialBody,
        elapsedSeconds: Double,
        daysSinceJ2000 days: Double,
        position: SIMD3<Float>,
        parentPosition: SIMD3<Float>
    ) -> Float {
        guard body.rotationPeriodHours != 0 else {
            return 0
        }

        if body.id == "earth" {
            return earthRotationAngle(for: body, daysSinceJ2000: days)
        }
        if isSynchronousMoon(body) {
            return parentFacingRotationAngle(for: body, position: position, parentPosition: parentPosition)
        }

        // The orbital simulation advances at 5 sim-days / real-sec → 120 sim-hours / real-sec.
        let simHoursPerSecond = daysPerSimulationSecond * 24.0
        let elapsed = elapsedSeconds * simHoursPerSecond / Double(body.rotationPeriodHours) * .pi * 2.0

        // ── Epoch seed ────────────────────────────────────────────────────────
        // For NON-SYNCHRONOUS non-Earth bodies, meanAnomalyAtEpochDegrees is an
        // ORBITAL parameter and must not be used as a rotation seed. Use IAU W0
        // values where available until per-body prime-meridian models are added.
        let epochSeed: Float
        switch body.id {
        case "mars":
            // IAU W0 = 176.630°
            epochSeed = Float((180.0 - 176.630) * .pi / 180.0)
        case "venus":
            // IAU W0 = 160.20°
            epochSeed = Float((180.0 - 160.20) * .pi / 180.0)
        case "jupiter":
            // IAU W0 = 284.95°
            epochSeed = Float((180.0 - 284.95) * .pi / 180.0)
        case "saturn":
            // IAU W0 = 38.90°
            epochSeed = Float((180.0 - 38.90) * .pi / 180.0)
        case "uranus":
            // IAU W0 = 203.81°
            epochSeed = Float((180.0 - 203.81) * .pi / 180.0)
        case "neptune":
            // IAU W0 = 253.18°
            epochSeed = Float((180.0 - 253.18) * .pi / 180.0)
        default:
            epochSeed = Float(body.meanAnomalyAtEpochDegrees * .pi / 180.0)
        }

        return Float(elapsed) + epochSeed
    }

    private static func isSynchronousMoon(_ body: NativeCelestialBody) -> Bool {
        guard body.kind == .moon,
              body.rotationPeriodHours > 0,
              let orbitalPeriodDays = body.orbitalPeriodDays else {
            return false
        }

        return abs(body.rotationPeriodHours - Float(orbitalPeriodDays) * 24.0) < 1.0
    }

    private static func parentFacingRotationAngle(
        for body: NativeCelestialBody,
        position: SIMD3<Float>,
        parentPosition: SIMD3<Float>
    ) -> Float {
        let toParent = SIMD3<Double>(
            Double(parentPosition.x - position.x),
            Double(parentPosition.y - position.y),
            Double(parentPosition.z - position.z)
        )
        let distance = length(toParent)
        guard distance > 0 else {
            return 0
        }

        let parentDirection = toParent / distance
        let untiltedParentDirection = rotateVectorD(
            parentDirection,
            radians: -Double(body.axialTiltDegrees) * .pi / 180.0,
            axis: SIMD3<Double>(1, 0, 0)
        )

        return Float(normalizeRadians(atan2(untiltedParentDirection.z, -untiltedParentDirection.x)))
    }

    private static func earthRotationAngle(for body: NativeCelestialBody, daysSinceJ2000 days: Double) -> Float {
        guard let semiMajorAxis = body.semiMajorAxisKilometers,
              let orbitalPeriod = body.orbitalPeriodDays,
              semiMajorAxis > 0 else {
            return 0
        }

        let orbit = computeKeplerianOffset(
            body: body,
            days: days,
            semiMajorAxis: 1.0,
            period: orbitalPeriod,
            parentBody: nil
        )
        let earthToSun = SIMD3<Double>(
            -Double(orbit.offset.x),
            -Double(orbit.offset.y),
            -Double(orbit.offset.z)
        )
        let distance = length(earthToSun)
        guard distance > 0 else {
            return 0
        }

        let sunDirection = earthToSun / distance
        let untiltedSun = rotateVectorD(
            sunDirection,
            radians: -Double(body.axialTiltDegrees) * .pi / 180.0,
            axis: SIMD3<Double>(1, 0, 0)
        )
        let noSpinSubsolarLongitude = atan2(untiltedSun.z, -untiltedSun.x)
        let targetSubsolarLongitude = solarSubsolarLongitude(daysSinceJ2000: days)

        return Float(normalizeRadians(noSpinSubsolarLongitude - targetSubsolarLongitude))
    }

    private static func solarSubsolarLongitude(daysSinceJ2000 days: Double) -> Double {
        let t = days / 36525.0
        let meanLongitude = normalizeDegrees(280.46646 + 36000.76983 * t + 0.0003032 * t * t)
        let meanAnomaly = normalizeDegrees(357.52911 + 35999.05029 * t - 0.0001537 * t * t)
        let meanAnomalyRad = meanAnomaly * .pi / 180.0
        let equationOfCenter =
            (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(meanAnomalyRad) +
            (0.019993 - 0.000101 * t) * sin(2.0 * meanAnomalyRad) +
            0.000289 * sin(3.0 * meanAnomalyRad)
        let trueLongitude = meanLongitude + equationOfCenter
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(omega * .pi / 180.0)
        let meanObliquity = 23.0 + (26.0 + (21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
        let obliquity = meanObliquity + 0.00256 * cos(omega * .pi / 180.0)
        let rightAscension = atan2(
            cos(obliquity * .pi / 180.0) * sin(apparentLongitude * .pi / 180.0),
            cos(apparentLongitude * .pi / 180.0)
        )
        let greenwichMeanSiderealTime = normalizeDegrees(280.46061837 + 360.98564736629 * days) * .pi / 180.0

        return normalizeRadians(rightAscension - greenwichMeanSiderealTime)
    }

    private static func normalizeDegrees(_ degrees: Double) -> Double {
        var normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        if normalized < 0 {
            normalized += 360.0
        }
        return normalized
    }

    private static func normalizeRadians(_ radians: Double) -> Double {
        var normalized = radians.truncatingRemainder(dividingBy: 2.0 * .pi)
        if normalized <= -.pi {
            normalized += 2.0 * .pi
        } else if normalized > .pi {
            normalized -= 2.0 * .pi
        }
        return normalized
    }

    private static func orbitColor(for body: NativeCelestialBody) -> SIMD4<Float> {
        switch body.kind {
        case .moon:
            SIMD4<Float>(0.54, 0.63, 0.72, 0.22)
        case .planet, .dwarfPlanet:
            SIMD4<Float>(0.21, 0.36, 0.54, 0.32)
        case .star:
            SIMD4<Float>(1, 0.8, 0.4, 0)
        }
    }
}
