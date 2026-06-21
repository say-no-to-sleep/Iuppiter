import Foundation

enum PlanetariumLimits {
    static let minZoom = 1.0
    static let maxZoom = 2000.0
}

enum ObservationMode: String, CaseIterable, Identifiable, Sendable {
    case orbit
    case planetarium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orbit:
            "Orbit"
        case .planetarium:
            "Planetarium"
        }
    }
}

struct PlanetariumLocation: Equatable, Sendable {
    var name: String
    var latitudeDegrees: Double
    var longitudeDegrees: Double

    static let waterloo = PlanetariumLocation(
        name: "Waterloo, Ontario",
        latitudeDegrees: 43.4643,
        longitudeDegrees: -80.5204
    )

    static let presets: [PlanetariumLocation] = [
        .waterloo,
        PlanetariumLocation(name: "Toronto, Ontario", latitudeDegrees: 43.6532, longitudeDegrees: -79.3832),
        PlanetariumLocation(name: "New York, USA", latitudeDegrees: 40.7128, longitudeDegrees: -74.0060),
        PlanetariumLocation(name: "London, UK", latitudeDegrees: 51.5072, longitudeDegrees: -0.1276),
        PlanetariumLocation(name: "Tokyo, Japan", latitudeDegrees: 35.6764, longitudeDegrees: 139.6500),
        PlanetariumLocation(name: "Sydney, Australia", latitudeDegrees: -33.8688, longitudeDegrees: 151.2093)
    ]

    var clamped: PlanetariumLocation {
        PlanetariumLocation(
            name: name,
            latitudeDegrees: min(90, max(-90, latitudeDegrees)),
            longitudeDegrees: min(180, max(-180, longitudeDegrees))
        )
    }
}

struct TimeRatePreset: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let secondsPerSecond: Double

    static let all: [TimeRatePreset] = [
        TimeRatePreset(id: "second", label: "1 s/s", secondsPerSecond: 1),
        TimeRatePreset(id: "minute", label: "1 min/s", secondsPerSecond: 60),
        TimeRatePreset(id: "hour", label: "1 h/s", secondsPerSecond: 3_600),
        TimeRatePreset(id: "day", label: "1 d/s", secondsPerSecond: 86_400),
        TimeRatePreset(id: "week", label: "1 w/s", secondsPerSecond: 604_800),
        TimeRatePreset(id: "month", label: "1 mo/s", secondsPerSecond: 2_629_746),
        TimeRatePreset(id: "year", label: "1 y/s", secondsPerSecond: 31_556_952)
    ]

    static func closestIndex(to secondsPerSecond: Double) -> Int {
        all.indices.min { lhs, rhs in
            abs(logDistance(all[lhs].secondsPerSecond, secondsPerSecond))
                < abs(logDistance(all[rhs].secondsPerSecond, secondsPerSecond))
        } ?? 0
    }

    static func label(for secondsPerSecond: Double) -> String {
        all[closestIndex(to: secondsPerSecond)].label
    }

    private static func logDistance(_ lhs: Double, _ rhs: Double) -> Double {
        log10(max(lhs, 0.000_001)) - log10(max(rhs, 0.000_001))
    }
}
