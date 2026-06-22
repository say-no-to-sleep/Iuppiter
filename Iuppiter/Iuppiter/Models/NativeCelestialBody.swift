import SwiftUI

enum NativeBodyKind: String, Sendable {
    case star
    case planet
    case moon
    case dwarfPlanet

    var title: String {
        switch self {
        case .star:
            "Star"
        case .planet:
            "Planet"
        case .moon:
            "Moon"
        case .dwarfPlanet:
            "Dwarf Planet"
        }
    }
}

enum NativeReferencePlane: String, Sendable {
    case ecliptic = "ECLIPTIC"
    case body = "BODY"
}

enum NativeAssetTier: String, Sendable {
    case real
    case partialReal = "partial-real"
    case procedural
}

struct NativeCloudLayer: Identifiable, Equatable, Sendable {
    let id: String
    let textureName: String?
    let textureNames: [String]
    let liveTextureURL: String?
    let refreshIntervalSeconds: TimeInterval
    let radiusScale: Float
    let opacity: Float
    let rotationRateMultiplier: Float
    let animationFrameDuration: Float

    init(
        id: String,
        textureName: String?,
        textureNames: [String]? = nil,
        liveTextureURL: String? = nil,
        refreshIntervalSeconds: TimeInterval = 60,
        radiusScale: Float,
        opacity: Float,
        rotationRateMultiplier: Float,
        animationFrameDuration: Float = 0.35
    ) {
        self.id = id
        self.textureName = textureName
        self.textureNames = textureNames ?? textureName.map { [$0] } ?? []
        self.liveTextureURL = liveTextureURL
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.radiusScale = radiusScale
        self.opacity = opacity
        self.rotationRateMultiplier = rotationRateMultiplier
        self.animationFrameDuration = animationFrameDuration
    }
}

struct NativeRingConfig: Equatable, Sendable {
    let textureName: String
    let innerRadiusBodyRadii: Float
    let outerRadiusBodyRadii: Float
    let opacity: Float
}

struct NativeCelestialBody: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: NativeBodyKind
    let parentID: String?
    let radiusKilometers: Double
    let semiMajorAxisKilometers: Double?
    let orbitalPeriodDays: Double?
    let eccentricity: Double
    let inclinationDegrees: Double
    let longitudeOfAscendingNodeDegrees: Double
    let argumentOfPeriapsisDegrees: Double
    let meanAnomalyAtEpochDegrees: Double
    let referencePlane: NativeReferencePlane
    let textureName: String
    let shapeModelName: String?
    let displayColor: Color
    let axialTiltDegrees: Float
    let rotationPeriodHours: Float
    let ring: NativeRingConfig?
    let cloudLayers: [NativeCloudLayer]
    let isMajor: Bool
    let assetTier: NativeAssetTier
}

struct RawBody {
    let id: String
    let name: String
    let kind: NativeBodyKind
    let parentID: String?
    let radiusKilometers: Double
    let semiMajorAxisKilometers: Double?
    let orbitalPeriodDays: Double?
    let eccentricity: Double
    let inclinationDegrees: Double
    let longitudeOfAscendingNodeDegrees: Double
    let argumentOfPeriapsisDegrees: Double
    let meanAnomalyAtEpochDegrees: Double
    let referencePlane: NativeReferencePlane
    let textureName: String?
    let shapeModelName: String?
    let displayColor: Color
    let axialTiltDegrees: Float
    let rotationPeriodHours: Float?
    let ring: NativeRingConfig?
    let cloudLayers: [NativeCloudLayer]
    let isMajor: Bool
    let assetTier: NativeAssetTier
}

extension RawBody {
    static func moon(
        id: String,
        name: String,
        parentID: String,
        radiusKm: Double,
        semiMajorAxisKm: Double? = nil,
        orbitalPeriodDays: Double? = nil,
        eccentricity: Double = 0.0,
        inclinationDegrees: Double = 0.0,
        longitudeOfAscendingNodeDegrees: Double = 0.0,
        argumentOfPeriapsisDegrees: Double = 0.0,
        meanAnomalyAtEpochDegrees: Double = 0.0,
        referencePlane: NativeReferencePlane = .body,
        textureName: String? = nil,
        isMajor: Bool = false,
        color: Color,
        axialTilt: Float = 0.0,
        rotationPeriodHours: Float? = nil,
        cloudLayers: [NativeCloudLayer] = [],
        assetTier: NativeAssetTier = .procedural,
        shapeModelName: String? = nil
    ) -> RawBody {
        RawBody(
            id: id,
            name: name,
            kind: .moon,
            parentID: parentID,
            radiusKilometers: radiusKm,
            semiMajorAxisKilometers: semiMajorAxisKm,
            orbitalPeriodDays: orbitalPeriodDays,
            eccentricity: eccentricity,
            inclinationDegrees: inclinationDegrees,
            longitudeOfAscendingNodeDegrees: longitudeOfAscendingNodeDegrees,
            argumentOfPeriapsisDegrees: argumentOfPeriapsisDegrees,
            meanAnomalyAtEpochDegrees: meanAnomalyAtEpochDegrees,
            referencePlane: referencePlane,
            textureName: textureName,
            shapeModelName: shapeModelName,
            displayColor: color,
            axialTiltDegrees: axialTilt,
            rotationPeriodHours: rotationPeriodHours,
            ring: nil,
            cloudLayers: cloudLayers,
            isMajor: isMajor,
            assetTier: assetTier
        )
    }

    static func planet(
        id: String,
        name: String,
        radiusKm: Double,
        semiMajorAxisKm: Double,
        orbitalPeriodDays: Double,
        eccentricity: Double = 0.0,
        inclinationDegrees: Double = 0.0,
        longitudeOfAscendingNodeDegrees: Double = 0.0,
        argumentOfPeriapsisDegrees: Double = 0.0,
        meanAnomalyAtEpochDegrees: Double = 0.0,
        referencePlane: NativeReferencePlane = .ecliptic,
        textureName: String,
        color: Color,
        axialTilt: Float,
        rotationPeriodHours: Float,
        ring: NativeRingConfig? = nil,
        cloudLayers: [NativeCloudLayer] = [],
        isMajor: Bool = true,
        assetTier: NativeAssetTier = .real,
        shapeModelName: String? = nil
    ) -> RawBody {
        RawBody(
            id: id,
            name: name,
            kind: .planet,
            parentID: "sun",
            radiusKilometers: radiusKm,
            semiMajorAxisKilometers: semiMajorAxisKm,
            orbitalPeriodDays: orbitalPeriodDays,
            eccentricity: eccentricity,
            inclinationDegrees: inclinationDegrees,
            longitudeOfAscendingNodeDegrees: longitudeOfAscendingNodeDegrees,
            argumentOfPeriapsisDegrees: argumentOfPeriapsisDegrees,
            meanAnomalyAtEpochDegrees: meanAnomalyAtEpochDegrees,
            referencePlane: referencePlane,
            textureName: textureName,
            shapeModelName: shapeModelName,
            displayColor: color,
            axialTiltDegrees: axialTilt,
            rotationPeriodHours: rotationPeriodHours,
            ring: ring,
            cloudLayers: cloudLayers,
            isMajor: isMajor,
            assetTier: assetTier
        )
    }
}

enum NativeBodyCatalog {
    static let rawBodies: [RawBody] = [
        RawBody(
            id: "sun",
            name: "Sun",
            kind: .star,
            parentID: nil,
            radiusKilometers: 696_340,
            semiMajorAxisKilometers: nil,
            orbitalPeriodDays: nil,
            eccentricity: 0.0,
            inclinationDegrees: 0.0,
            longitudeOfAscendingNodeDegrees: 0.0,
            argumentOfPeriapsisDegrees: 0.0,
            meanAnomalyAtEpochDegrees: 0.0,
            referencePlane: .ecliptic,
            textureName: "HighRes/8k_sun.jpg",
            shapeModelName: nil,
            displayColor: Color(red: 1.0, green: 0.77, blue: 0.36),
            axialTiltDegrees: 7.25,
            rotationPeriodHours: 609.12,
            ring: nil,
            cloudLayers: [],
            isMajor: true,
            assetTier: .real
        ),
        .planet(id: "mercury", name: "Mercury", radiusKm: 2439.7, semiMajorAxisKm: 57909041.4565191, orbitalPeriodDays: 87.96903688803486, eccentricity: 0.2056378932728906, inclinationDegrees: 7.003394533425516, longitudeOfAscendingNodeDegrees: 48.29770967106519, argumentOfPeriapsisDegrees: 29.20127864068919, meanAnomalyAtEpochDegrees: 174.6539883898076, referencePlane: .ecliptic, textureName: "HighRes/8k_mercury.jpg", color: Color(red: 0.72, green: 0.69, blue: 0.65), axialTilt: 0.03, rotationPeriodHours: 1407.6),
        .planet(id: "venus", name: "Venus", radiusKm: 6051.8, semiMajorAxisKm: 108208006.2769907, orbitalPeriodDays: 224.6978258066756, eccentricity: 0.006783944929319707, inclinationDegrees: 3.394371788423513, longitudeOfAscendingNodeDegrees: 76.60656034841804, argumentOfPeriapsisDegrees: 54.83769890574852, meanAnomalyAtEpochDegrees: 50.3304932876963, referencePlane: .ecliptic, textureName: "HighRes/4k_venus_atmosphere.jpg", color: Color(red: 0.93, green: 0.79, blue: 0.53), axialTilt: 177.4, rotationPeriodHours: -5832.5),
        .planet(
            id: "earth",
            name: "Earth",
            radiusKm: 6371,
            semiMajorAxisKm: 149690622.8317032,
            orbitalPeriodDays: 365.596096176352,
            eccentricity: 0.01598580638834942,
            inclinationDegrees: 0.00394112011525619,
            longitudeOfAscendingNodeDegrees: 207.1607699903621,
            argumentOfPeriapsisDegrees: 255.4095832574782,
            meanAnomalyAtEpochDegrees: 6.781100473936021,
            referencePlane: .ecliptic,
            textureName: "HighRes/nasa_blue_marble_ng_8k.jpg",
            color: Color(red: 0.25, green: 0.56, blue: 1.0),
            axialTilt: 23.44,
            rotationPeriodHours: 23.9345,
            // No separate cloud layer: the live VIIRS true-color base map
            // (see liveSurfaceMapURLTemplate) already includes real clouds.
            cloudLayers: []
        ),
        .moon(id: "moon", name: "Moon", parentID: "earth", radiusKm: 1737.4, semiMajorAxisKm: 382691.3426164712, orbitalPeriodDays: 27.10288806289366, eccentricity: 0.0707596563702388, inclinationDegrees: 5.069162300983396, longitudeOfAscendingNodeDegrees: 331.5310540034619, argumentOfPeriapsisDegrees: 101.577537259836, meanAnomalyAtEpochDegrees: 196.5342893926136, referencePlane: .ecliptic, textureName: "HighRes/8k_moon.jpg", isMajor: true, color: Color(red: 0.84, green: 0.84, blue: 0.82), axialTilt: 6.68, rotationPeriodHours: 655.72, assetTier: .real),
        .planet(id: "mars", name: "Mars", radiusKm: 3389.5, semiMajorAxisKm: 227926848.331841, orbitalPeriodDays: 686.9157380734335, eccentricity: 0.09342811913473467, inclinationDegrees: 1.84748830466323, longitudeOfAscendingNodeDegrees: 49.4811745396814, argumentOfPeriapsisDegrees: 286.6086819441484, meanAnomalyAtEpochDegrees: 18.88902020879686, referencePlane: .ecliptic, textureName: "HighRes/8k_mars.jpg", color: Color(red: 0.83, green: 0.39, blue: 0.28), axialTilt: 25.19, rotationPeriodHours: 24.6229),
        .moon(id: "phobos", name: "Phobos", parentID: "mars", radiusKm: 11.3, semiMajorAxisKm: 9378.576749166921, orbitalPeriodDays: 0.31915799629988, eccentricity: 0.01543108360769796, inclinationDegrees: 26.12910976707083, longitudeOfAscendingNodeDegrees: 80.80859177832497, argumentOfPeriapsisDegrees: 233.3439833801328, meanAnomalyAtEpochDegrees: 138.0401698760688, referencePlane: .ecliptic, textureName: "Mars/Phobos_Viking_Mosaic_40ppd_DLRcontrol_rgb.png", color: Color(red: 0.56, green: 0.53, blue: 0.50), rotationPeriodHours: 7.65, assetTier: .partialReal, shapeModelName: "Mars/24878_Phobos_1_1000.usdz"),
        .moon(id: "deimos", name: "Deimos", parentID: "mars", radiusKm: 6.2, semiMajorAxisKm: 23459.53425385426, orbitalPeriodDays: 1.262639601390586, eccentricity: 0.0002563009058367043, inclinationDegrees: 24.12200416104555, longitudeOfAscendingNodeDegrees: 81.35341654319173, argumentOfPeriapsisDegrees: 37.5624143522008, meanAnomalyAtEpochDegrees: 255.6077796197496, referencePlane: .ecliptic, textureName: "Mars/deimos_hi_res/Textures/deimos_hires.png", color: Color(red: 0.64, green: 0.62, blue: 0.58), rotationPeriodHours: 30.31, assetTier: .partialReal, shapeModelName: "Mars/deimos_hi_res/deimos_hires_shape.usdz"),
        .planet(id: "jupiter", name: "Jupiter", radiusKm: 69911, semiMajorAxisKm: 778068838.0372915, orbitalPeriodDays: 4330.421329119179, eccentricity: 0.0483897581398392, inclinationDegrees: 1.30405251015745, longitudeOfAscendingNodeDegrees: 100.5262697371084, argumentOfPeriapsisDegrees: 273.2340355314389, meanAnomalyAtEpochDegrees: 20.20214660118108, referencePlane: .ecliptic, textureName: "HighRes/8k_jupiter.jpg", color: Color(red: 0.86, green: 0.68, blue: 0.48), axialTilt: 3.13, rotationPeriodHours: 9.925),
        .moon(id: "io", name: "Io", parentID: "jupiter", radiusKm: 1821.49, semiMajorAxisKm: 422048.9565587134, orbitalPeriodDays: 1.771474614473376, eccentricity: 0.00475133590238099, inclinationDegrees: 2.220365624943483, longitudeOfAscendingNodeDegrees: 338.4836305436955, argumentOfPeriapsisDegrees: 122.4624173899902, meanAnomalyAtEpochDegrees: 351.7204940584488, referencePlane: .ecliptic, textureName: "io.jpg", isMajor: true, color: Color(red: 0.95, green: 0.83, blue: 0.35), rotationPeriodHours: 42.46, assetTier: .real, shapeModelName: "Jovian/Io_1_3643.usdz"),
        .moon(id: "europa", name: "Europa", parentID: "jupiter", radiusKm: 1560.8, semiMajorAxisKm: 671298.4725497616, orbitalPeriodDays: 3.553602945596452, eccentricity: 0.009144600976512891, inclinationDegrees: 2.104332795727639, longitudeOfAscendingNodeDegrees: 326.0200658804138, argumentOfPeriapsisDegrees: 314.3001777061492, meanAnomalyAtEpochDegrees: 240.1042266717413, referencePlane: .ecliptic, textureName: "europa.jpg", isMajor: true, color: Color(red: 0.91, green: 0.89, blue: 0.82), rotationPeriodHours: 85.22, assetTier: .real),
        .moon(id: "ganymede", name: "Ganymede", parentID: "jupiter", radiusKm: 2631.2, semiMajorAxisKm: 1070652.804593871, orbitalPeriodDays: 7.157427261047517, eccentricity: 0.00166877840499463, inclinationDegrees: 2.34214951513592, longitudeOfAscendingNodeDegrees: 339.1328170596984, argumentOfPeriapsisDegrees: 23.30433597578471, meanAnomalyAtEpochDegrees: 52.85279425210319, referencePlane: .ecliptic, textureName: "ganymede.jpg", isMajor: true, color: Color(red: 0.71, green: 0.69, blue: 0.65), rotationPeriodHours: 171.72, assetTier: .real),
        .moon(id: "callisto", name: "Callisto", parentID: "jupiter", radiusKm: 2410.3, semiMajorAxisKm: 1884042.229618258, orbitalPeriodDays: 16.70800307100597, eccentricity: 0.006810847487051453, inclinationDegrees: 1.952396210891296, longitudeOfAscendingNodeDegrees: 336.7210532130393, argumentOfPeriapsisDegrees: 37.87762448533217, meanAnomalyAtEpochDegrees: 301.4972920717846, referencePlane: .ecliptic, textureName: "Jovian/callisto.jpg", isMajor: true, color: Color(red: 0.56, green: 0.51, blue: 0.46), rotationPeriodHours: 400.54, assetTier: .real),
        .moon(id: "amalthea", name: "Amalthea", parentID: "jupiter", radiusKm: 83.5, semiMajorAxisKm: 181992.4095300774, orbitalPeriodDays: 0.5016268961823924, eccentricity: 0.001930751202801474, inclinationDegrees: 1.910974028197365, longitudeOfAscendingNodeDegrees: 331.6591972884951, argumentOfPeriapsisDegrees: 224.5181523469313, meanAnomalyAtEpochDegrees: 341.6432551415637, referencePlane: .ecliptic, color: Color(red: 0.67, green: 0.45, blue: 0.40)),
        .moon(id: "himalia", name: "Himalia", parentID: "jupiter", radiusKm: 85, semiMajorAxisKm: 11488560.39385981, orbitalPeriodDays: 251.5934435809069, eccentricity: 0.1541368323027822, inclinationDegrees: 28.47472171925327, longitudeOfAscendingNodeDegrees: 35.24444954652696, argumentOfPeriapsisDegrees: 50.26596422499987, meanAnomalyAtEpochDegrees: 74.26182426954074, referencePlane: .ecliptic, color: Color(red: 0.46, green: 0.40, blue: 0.37)),
        .moon(id: "elara", name: "Elara", parentID: "jupiter", radiusKm: 43, semiMajorAxisKm: 11710356.90349817, orbitalPeriodDays: 258.9143369977627, eccentricity: 0.229689096470868, inclinationDegrees: 29.66930551084837, longitudeOfAscendingNodeDegrees: 83.27341435285057, argumentOfPeriapsisDegrees: 220.5550732417119, meanAnomalyAtEpochDegrees: 247.2397209986593, referencePlane: .ecliptic, color: Color(red: 0.47, green: 0.39, blue: 0.35)),
        .moon(id: "pasiphae", name: "Pasiphae", parentID: "jupiter", radiusKm: 30, semiMajorAxisKm: 23857019.25305253, orbitalPeriodDays: 752.8789830587787, eccentricity: 0.3985428967816763, inclinationDegrees: 153.5401655244044, longitudeOfAscendingNodeDegrees: 78.45613379522212, argumentOfPeriapsisDegrees: 277.1220840497217, meanAnomalyAtEpochDegrees: 349.7072888133598, referencePlane: .ecliptic, color: Color(red: 0.44, green: 0.36, blue: 0.32)),
        .moon(id: "sinope", name: "Sinope", parentID: "jupiter", radiusKm: 19, semiMajorAxisKm: 22871630.65398055, orbitalPeriodDays: 706.7187209834141, eccentricity: 0.2802274685171808, inclinationDegrees: 158.5566046221157, longitudeOfAscendingNodeDegrees: 49.22792896107791, argumentOfPeriapsisDegrees: 68.41645311700687, meanAnomalyAtEpochDegrees: 211.2418325210656, referencePlane: .ecliptic, color: Color(red: 0.44, green: 0.35, blue: 0.30)),
        .moon(id: "lysithea", name: "Lysithea", parentID: "jupiter", radiusKm: 18, semiMajorAxisKm: 11752465.54704005, orbitalPeriodDays: 260.3121159090468, eccentricity: 0.1365215836184044, inclinationDegrees: 27.02184266027225, longitudeOfAscendingNodeDegrees: 332.5354984432623, argumentOfPeriapsisDegrees: 122.3037856273921, meanAnomalyAtEpochDegrees: 347.962830308692, referencePlane: .ecliptic, color: Color(red: 0.46, green: 0.39, blue: 0.35)),
        .moon(id: "carme", name: "Carme", parentID: "jupiter", radiusKm: 23, semiMajorAxisKm: 22747401.38102489, orbitalPeriodDays: 700.96863941061, eccentricity: 0.2797183837695536, inclinationDegrees: 162.1309022270785, longitudeOfAscendingNodeDegrees: 229.9649102364868, argumentOfPeriapsisDegrees: 166.0463554181301, meanAnomalyAtEpochDegrees: 345.8794033422264, referencePlane: .ecliptic, color: Color(red: 0.44, green: 0.35, blue: 0.31)),
        .moon(id: "ananke", name: "Ananke", parentID: "jupiter", radiusKm: 14, semiMajorAxisKm: 20883626.07675684, orbitalPeriodDays: 616.6088660198052, eccentricity: 0.1591387752376353, inclinationDegrees: 149.0187650246644, longitudeOfAscendingNodeDegrees: 105.8341169053791, argumentOfPeriapsisDegrees: 135.1342283840346, meanAnomalyAtEpochDegrees: 182.8709508039719, referencePlane: .ecliptic, color: Color(red: 0.43, green: 0.35, blue: 0.32)),
        .moon(id: "leda", name: "Leda", parentID: "jupiter", radiusKm: 10, semiMajorAxisKm: 11094726.38387736, orbitalPeriodDays: 238.7678212641539, eccentricity: 0.1578291749286058, inclinationDegrees: 28.24218493558411, longitudeOfAscendingNodeDegrees: 183.2241640031561, argumentOfPeriapsisDegrees: 330.1377562019706, meanAnomalyAtEpochDegrees: 75.90152538234361, referencePlane: .ecliptic, color: Color(red: 0.47, green: 0.41, blue: 0.38)),
        .moon(id: "thebe", name: "Thebe", parentID: "jupiter", radiusKm: 49.3, semiMajorAxisKm: 222424.8145846819, orbitalPeriodDays: 0.677759725173616, eccentricity: 0.01994392396300082, inclinationDegrees: 2.790055355493379, longitudeOfAscendingNodeDegrees: 316.9249379201597, argumentOfPeriapsisDegrees: 140.8079048338325, meanAnomalyAtEpochDegrees: 145.6847970373929, referencePlane: .ecliptic, color: Color(red: 0.62, green: 0.46, blue: 0.42)),
        .moon(id: "adrastea", name: "Adrastea", parentID: "jupiter", radiusKm: 8.2, semiMajorAxisKm: 129873.4118867801, orbitalPeriodDays: 0.3023996451360847, eccentricity: 0.007135533731974223, inclinationDegrees: 2.209048569422669, longitudeOfAscendingNodeDegrees: 337.9070894047464, argumentOfPeriapsisDegrees: 57.6712898633887, meanAnomalyAtEpochDegrees: 20.01473328098655, referencePlane: .ecliptic, color: Color(red: 0.62, green: 0.48, blue: 0.44)),
        .moon(id: "metis", name: "Metis", parentID: "jupiter", radiusKm: 21.5, semiMajorAxisKm: 128879.0060046115, orbitalPeriodDays: 0.2989332123034715, eccentricity: 0.006786086016581741, inclinationDegrees: 2.211445731467792, longitudeOfAscendingNodeDegrees: 337.9598851807132, argumentOfPeriapsisDegrees: 278.3589932883216, meanAnomalyAtEpochDegrees: 149.9944976344705, referencePlane: .ecliptic, color: Color(red: 0.63, green: 0.49, blue: 0.45)),
        .planet(
            id: "saturn",
            name: "Saturn",
            radiusKm: 58232,
            semiMajorAxisKm: 1427592176.648032,
            orbitalPeriodDays: 10766.00290581868,
            eccentricity: 0.05527741349288962,
            inclinationDegrees: 2.488823921344009,
            longitudeOfAscendingNodeDegrees: 113.7037312641216,
            argumentOfPeriapsisDegrees: 338.3912170807541,
            meanAnomalyAtEpochDegrees: 318.2605297793882,
            referencePlane: .ecliptic,
            textureName: "HighRes/8k_saturn.jpg",
            color: Color(red: 0.88, green: 0.75, blue: 0.5),
            axialTilt: 26.73,
            rotationPeriodHours: 10.656,
            ring: NativeRingConfig(
                textureName: "HighRes/8k_saturn_ring_alpha.png",
                innerRadiusBodyRadii: 1.22,
                outerRadiusBodyRadii: 2.35,
                opacity: 0.82
            )
        ),
        .moon(id: "mimas", name: "Mimas", parentID: "saturn", radiusKm: 198.2, semiMajorAxisKm: 186029.8301289677, orbitalPeriodDays: 0.947418081343754, eccentricity: 0.02085769658841547, inclinationDegrees: 26.51488947151601, longitudeOfAscendingNodeDegrees: 168.739963644274, argumentOfPeriapsisDegrees: 54.35633760930512, meanAnomalyAtEpochDegrees: 53.88826828170568, referencePlane: .ecliptic, textureName: "Saturn/mimas.jpg", isMajor: true, color: Color(red: 0.84, green: 0.85, blue: 0.84), assetTier: .real),
        .moon(id: "enceladus", name: "Enceladus", parentID: "saturn", radiusKm: 252.1, semiMajorAxisKm: 238412.8595400889, orbitalPeriodDays: 1.37455547757105, eccentricity: 0.005178442683801833, inclinationDegrees: 28.04549217470252, longitudeOfAscendingNodeDegrees: 169.5181357915526, argumentOfPeriapsisDegrees: 140.4997182562393, meanAnomalyAtEpochDegrees: 94.4328271234408, referencePlane: .ecliptic, textureName: "enceladus.jpg", isMajor: true, color: Color(red: 0.96, green: 0.97, blue: 0.98), assetTier: .real, shapeModelName: "Saturn/Enceladus_1_504.usdz"),
        .moon(id: "tethys", name: "Tethys", parentID: "saturn", radiusKm: 531.1, semiMajorAxisKm: 294973.5058627459, orbitalPeriodDays: 1.891655633093175, eccentricity: 0.001043533566438817, inclinationDegrees: 27.73836741355769, longitudeOfAscendingNodeDegrees: 171.7613010818109, argumentOfPeriapsisDegrees: 92.22805095368115, meanAnomalyAtEpochDegrees: 210.5794540809002, referencePlane: .ecliptic, textureName: "tethys.jpg", isMajor: true, color: Color(red: 0.84, green: 0.87, blue: 0.87), assetTier: .real, shapeModelName: "Saturn/Tethys_1_1077.usdz"),
        .moon(id: "dione", name: "Dione", parentID: "saturn", radiusKm: 561.4, semiMajorAxisKm: 377643.2196016009, orbitalPeriodDays: 2.740248304942223, eccentricity: 0.002740806606289354, inclinationDegrees: 28.02481817957881, longitudeOfAscendingNodeDegrees: 169.5412981473387, argumentOfPeriapsisDegrees: 273.0304855849475, meanAnomalyAtEpochDegrees: 330.133624649141, referencePlane: .ecliptic, textureName: "dione.jpg", isMajor: true, color: Color(red: 0.78, green: 0.80, blue: 0.82), assetTier: .real, shapeModelName: "Saturn/Dione_1_1123.usdz"),
        .moon(id: "rhea", name: "Rhea", parentID: "saturn", radiusKm: 763.5, semiMajorAxisKm: 527244.0160688198, orbitalPeriodDays: 4.520478488150128, eccentricity: 0.001407470540508227, inclinationDegrees: 28.26212962069336, longitudeOfAscendingNodeDegrees: 169.9959344465088, argumentOfPeriapsisDegrees: 176.8318946131612, meanAnomalyAtEpochDegrees: 341.9942354169907, referencePlane: .ecliptic, textureName: "rhea.jpg", isMajor: true, color: Color(red: 0.73, green: 0.75, blue: 0.76), assetTier: .real, shapeModelName: "Saturn/Rhea_1_1529.usdz"),
        .moon(
            id: "titan",
            name: "Titan",
            parentID: "saturn",
            radiusKm: 2574.76,
            semiMajorAxisKm: 1221931.896759647,
            orbitalPeriodDays: 15.9472906548567,
            eccentricity: 0.02868616393865448,
            inclinationDegrees: 27.70709946501194,
            longitudeOfAscendingNodeDegrees: 169.07956837687,
            argumentOfPeriapsisDegrees: 178.1900863370771,
            meanAnomalyAtEpochDegrees: 175.0190190842841,
            referencePlane: .ecliptic,
            textureName: "titan.jpg",
            isMajor: true,
            color: Color(red: 0.85, green: 0.60, blue: 0.28),
            assetTier: .real
        ),
        .moon(id: "hyperion", name: "Hyperion", parentID: "saturn", radiusKm: 135, semiMajorAxisKm: 1486479.735818049, orbitalPeriodDays: 21.39963109083574, eccentricity: 0.09620825381863797, inclinationDegrees: 27.05504118542156, longitudeOfAscendingNodeDegrees: 169.5346420859346, argumentOfPeriapsisDegrees: 70.5840341993126, meanAnomalyAtEpochDegrees: 45.45687118449132, referencePlane: .ecliptic, color: Color(red: 0.62, green: 0.55, blue: 0.50), shapeModelName: "hyperion_shape.obj"),
        .moon(id: "iapetus", name: "Iapetus", parentID: "saturn", radiusKm: 734.3, semiMajorAxisKm: 3564620.138763961, orbitalPeriodDays: 79.46703212979406, eccentricity: 0.02782052191641459, inclinationDegrees: 16.99092180939638, longitudeOfAscendingNodeDegrees: 138.8861010138819, argumentOfPeriapsisDegrees: 232.9102845176791, meanAnomalyAtEpochDegrees: 280.7073723031353, referencePlane: .ecliptic, textureName: "Saturn/iapetus.jpg", isMajor: true, color: Color(red: 0.55, green: 0.51, blue: 0.47), assetTier: .real, shapeModelName: "Saturn/Iapetus_1_1471.usdz"),
        .moon(id: "phoebe", name: "Phoebe", parentID: "saturn", radiusKm: 106.5, semiMajorAxisKm: 12998056.34403859, orbitalPeriodDays: 553.3315309206498, eccentricity: 0.1724690565768658, inclinationDegrees: 172.8637876557985, longitudeOfAscendingNodeDegrees: 271.3619153336331, argumentOfPeriapsisDegrees: 9.455069541801342, meanAnomalyAtEpochDegrees: 86.4225911378453, referencePlane: .ecliptic, color: Color(red: 0.43, green: 0.38, blue: 0.35), shapeModelName: "phoebe_shape.obj"),
        .moon(id: "janus", name: "Janus", parentID: "saturn", radiusKm: 89.2, semiMajorAxisKm: 152052.6021043581, orbitalPeriodDays: 0.7000975911197839, eccentricity: 0.004968113274107662, inclinationDegrees: 27.9165829676019, longitudeOfAscendingNodeDegrees: 169.728043803661, argumentOfPeriapsisDegrees: 211.6014899567017, meanAnomalyAtEpochDegrees: 238.5726638427004, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.72, blue: 0.70), shapeModelName: "janus_shape.obj"),
        .moon(id: "epimetheus", name: "Epimetheus", parentID: "saturn", radiusKm: 58.2, semiMajorAxisKm: 152015.9671133336, orbitalPeriodDays: 0.6998445888218239, eccentricity: 0.01202133601943412, inclinationDegrees: 27.69736693865285, longitudeOfAscendingNodeDegrees: 169.4858413396692, argumentOfPeriapsisDegrees: 304.5430013587886, meanAnomalyAtEpochDegrees: 184.147827366367, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.71, blue: 0.69), shapeModelName: "epimetheus_shape.obj"),
        .moon(id: "helene", name: "Helene", parentID: "saturn", radiusKm: 18, semiMajorAxisKm: 377609.64808472, orbitalPeriodDays: 2.739885552135051, eccentricity: 0.007556681985459395, inclinationDegrees: 28.23676548288647, longitudeOfAscendingNodeDegrees: 169.7389652139935, argumentOfPeriapsisDegrees: 272.9241500156557, meanAnomalyAtEpochDegrees: 238.0515812733211, referencePlane: .ecliptic, color: Color(red: 0.82, green: 0.83, blue: 0.83), shapeModelName: "helene_shape.obj"),
        .moon(id: "telesto", name: "Telesto", parentID: "saturn", radiusKm: 12, semiMajorAxisKm: 294987.4865144314, orbitalPeriodDays: 1.891791148639491, eccentricity: 0.001025702293749403, inclinationDegrees: 28.33607113519339, longitudeOfAscendingNodeDegrees: 171.9472987315413, argumentOfPeriapsisDegrees: 143.8975424094017, meanAnomalyAtEpochDegrees: 350.4314225576818, referencePlane: .ecliptic, color: Color(red: 0.84, green: 0.85, blue: 0.85), shapeModelName: "telesto_shape.obj"),
        .moon(id: "calypso", name: "Calypso", parentID: "saturn", radiusKm: 10.5, semiMajorAxisKm: 294946.8512393604, orbitalPeriodDays: 1.891400263552273, eccentricity: 0.001475194405822098, inclinationDegrees: 26.62435846112744, longitudeOfAscendingNodeDegrees: 170.5337301538924, argumentOfPeriapsisDegrees: 36.88709071765516, meanAnomalyAtEpochDegrees: 317.0022023248021, referencePlane: .ecliptic, color: Color(red: 0.85, green: 0.85, blue: 0.85), shapeModelName: "calypso_shape.obj"),
        .moon(id: "atlas", name: "Atlas", parentID: "saturn", radiusKm: 15.1, semiMajorAxisKm: 138324.0842768081, orbitalPeriodDays: 0.6074555505438984, eccentricity: 0.006066655934883022, inclinationDegrees: 28.04850565040935, longitudeOfAscendingNodeDegrees: 169.5223811690488, argumentOfPeriapsisDegrees: 164.1456191249194, meanAnomalyAtEpochDegrees: 328.8088436713442, referencePlane: .ecliptic, color: Color(red: 0.76, green: 0.75, blue: 0.71), shapeModelName: "atlas_shape.obj"),
        .moon(id: "prometheus", name: "Prometheus", parentID: "saturn", radiusKm: 43.1, semiMajorAxisKm: 140025.9125154568, orbitalPeriodDays: 0.6187004277298551, eccentricity: 0.004168993609937357, inclinationDegrees: 28.05881534281314, longitudeOfAscendingNodeDegrees: 169.5307614211397, argumentOfPeriapsisDegrees: 245.0714029210312, meanAnomalyAtEpochDegrees: 6.946864936500788, referencePlane: .ecliptic, color: Color(red: 0.75, green: 0.75, blue: 0.72), shapeModelName: "prometheus_shape.obj"),
        .moon(id: "pandora", name: "Pandora", parentID: "saturn", radiusKm: 40.6, semiMajorAxisKm: 142352.1441837573, orbitalPeriodDays: 0.6341818647696011, eccentricity: 0.006066266741255947, inclinationDegrees: 28.07085519031195, longitudeOfAscendingNodeDegrees: 169.4260439223495, argumentOfPeriapsisDegrees: 53.09091081003791, meanAnomalyAtEpochDegrees: 120.5651030065492, referencePlane: .ecliptic, color: Color(red: 0.75, green: 0.74, blue: 0.72), shapeModelName: "pandora_shape.obj"),
        .moon(id: "pan", name: "Pan", parentID: "saturn", radiusKm: 14.0, semiMajorAxisKm: 134263.6880974321, orbitalPeriodDays: 0.5809057269016943, eccentricity: 0.005054930925093539, inclinationDegrees: 28.05183346029872, longitudeOfAscendingNodeDegrees: 169.5239694525524, argumentOfPeriapsisDegrees: 356.7654090518906, meanAnomalyAtEpochDegrees: 256.1763132866472, referencePlane: .ecliptic, color: Color(red: 0.82, green: 0.77, blue: 0.64), shapeModelName: "pan_shape.obj"),
        .moon(id: "methone", name: "Methone", parentID: "saturn", radiusKm: 1.6, semiMajorAxisKm: 194679.124657058, orbitalPeriodDays: 1.014254343604088, eccentricity: 0.003544770467205004, inclinationDegrees: 28.06849569761522, longitudeOfAscendingNodeDegrees: 169.5083880745374, argumentOfPeriapsisDegrees: 33.71282762354254, meanAnomalyAtEpochDegrees: 192.5120799564756, referencePlane: .ecliptic, color: Color(red: 0.89, green: 0.87, blue: 0.82)),
        .moon(id: "pallene", name: "Pallene", parentID: "saturn", radiusKm: 2.2, semiMajorAxisKm: 212701.1223485739, orbitalPeriodDays: 1.158303773815118, eccentricity: 0.002157269083305411, inclinationDegrees: 28.23301473670124, longitudeOfAscendingNodeDegrees: 169.5458422791783, argumentOfPeriapsisDegrees: 357.1029626601069, meanAnomalyAtEpochDegrees: 91.45570116396993, referencePlane: .ecliptic, color: Color(red: 0.87, green: 0.86, blue: 0.81)),
        .moon(id: "anthe", name: "Anthe", parentID: "saturn", radiusKm: 0.9, semiMajorAxisKm: 198128.5147365339, orbitalPeriodDays: 1.041329747101681, eccentricity: 0.003216362839156017, inclinationDegrees: 28.05906675723785, longitudeOfAscendingNodeDegrees: 169.5623252716445, argumentOfPeriapsisDegrees: 149.6711411928353, meanAnomalyAtEpochDegrees: 107.1389985298738, referencePlane: .ecliptic, color: Color(red: 0.88, green: 0.87, blue: 0.82)),
        .moon(id: "daphnis", name: "Daphnis", parentID: "saturn", radiusKm: 3.8, semiMajorAxisKm: 136500.0, orbitalPeriodDays: 0.59408, eccentricity: 0.0, inclinationDegrees: 28.052, longitudeOfAscendingNodeDegrees: 169.523, argumentOfPeriapsisDegrees: 0.0, meanAnomalyAtEpochDegrees: 153.6, referencePlane: .ecliptic, color: Color(red: 0.87, green: 0.85, blue: 0.79), shapeModelName: "daphnis_shape.obj"),
        .planet(id: "uranus", name: "Uranus", radiusKm: 25362, semiMajorAxisKm: 2882744743.771275, orbitalPeriodDays: 30896.55887127074, eccentricity: 0.04731601202281265, inclinationDegrees: 0.7711667425227704, longitudeOfAscendingNodeDegrees: 74.04289469941631, argumentOfPeriapsisDegrees: 92.09288198294756, meanAnomalyAtEpochDegrees: 147.999312340235, referencePlane: .ecliptic, textureName: "2k_uranus.jpg", color: Color(red: 0.58, green: 0.85, blue: 0.88), axialTilt: 97.77, rotationPeriodHours: -17.24),
        .moon(id: "ariel", name: "Ariel", parentID: "uranus", radiusKm: 578.9, semiMajorAxisKm: 190947.4244967836, orbitalPeriodDays: 2.52084598227288, eccentricity: 0.000395888858685924, inclinationDegrees: 97.71686709985312, longitudeOfAscendingNodeDegrees: 167.6654159633878, argumentOfPeriapsisDegrees: 248.912958576017, meanAnomalyAtEpochDegrees: 204.7922238835599, referencePlane: .ecliptic, textureName: "ariel.jpg", isMajor: true, color: Color(red: 0.78, green: 0.84, blue: 0.87), assetTier: .real),
        .moon(id: "umbriel", name: "Umbriel", parentID: "uranus", radiusKm: 584.7, semiMajorAxisKm: 266000.0244056127, orbitalPeriodDays: 4.14474718692344, eccentricity: 0.004077175452346204, inclinationDegrees: 97.71321037624881, longitudeOfAscendingNodeDegrees: 167.7248729842168, argumentOfPeriapsisDegrees: 56.96484728782928, meanAnomalyAtEpochDegrees: 304.7257622253383, referencePlane: .ecliptic, textureName: "umbriel.jpg", isMajor: true, color: Color(red: 0.55, green: 0.60, blue: 0.63), assetTier: .real),
        .moon(id: "titania", name: "Titania", parentID: "uranus", radiusKm: 788.9, semiMajorAxisKm: 436282.7228989208, orbitalPeriodDays: 8.706074995084119, eccentricity: 0.002314641847386604, inclinationDegrees: 97.76263338165293, longitudeOfAscendingNodeDegrees: 167.6431905140492, argumentOfPeriapsisDegrees: 242.9598668762839, meanAnomalyAtEpochDegrees: 42.96613913000328, referencePlane: .ecliptic, textureName: "titania.jpg", isMajor: true, color: Color(red: 0.74, green: 0.78, blue: 0.80), assetTier: .real),
        .moon(id: "oberon", name: "Oberon", parentID: "uranus", radiusKm: 761.4, semiMajorAxisKm: 583593.7944335277, orbitalPeriodDays: 13.46904181698382, eccentricity: 0.0007969484567786026, inclinationDegrees: 97.9056417305231, longitudeOfAscendingNodeDegrees: 167.7087844493209, argumentOfPeriapsisDegrees: 155.2749187543698, meanAnomalyAtEpochDegrees: 303.6228886465251, referencePlane: .ecliptic, textureName: "oberon.jpg", isMajor: true, color: Color(red: 0.65, green: 0.69, blue: 0.71), assetTier: .real),
        .moon(id: "miranda", name: "Miranda", parentID: "uranus", radiusKm: 235.8, semiMajorAxisKm: 129873.3869870135, orbitalPeriodDays: 1.414030664668315, eccentricity: 0.001205361195123524, inclinationDegrees: 98.48720272675946, longitudeOfAscendingNodeDegrees: 163.242835768015, argumentOfPeriapsisDegrees: 57.84557848545989, meanAnomalyAtEpochDegrees: 144.785927944351, referencePlane: .ecliptic, textureName: "miranda.jpg", isMajor: true, color: Color(red: 0.82, green: 0.85, blue: 0.85), assetTier: .real),
        .moon(id: "puck", name: "Puck", parentID: "uranus", radiusKm: 81, semiMajorAxisKm: 86052.90704976402, orbitalPeriodDays: 0.7626531193607655, eccentricity: 0.009563912193676676, inclinationDegrees: 98.64255003174877, longitudeOfAscendingNodeDegrees: 167.1189551856258, argumentOfPeriapsisDegrees: 218.6061864723382, meanAnomalyAtEpochDegrees: 274.901507309638, referencePlane: .ecliptic, color: Color(red: 0.71, green: 0.73, blue: 0.73)),
        .moon(id: "cordelia", name: "Cordelia", parentID: "uranus", radiusKm: 20, semiMajorAxisKm: 49835.30589435032, orbitalPeriodDays: 0.336112314142252, eccentricity: 0.00163985162346507, inclinationDegrees: 97.58532602621335, longitudeOfAscendingNodeDegrees: 167.7083053612052, argumentOfPeriapsisDegrees: 356.5562265739183, meanAnomalyAtEpochDegrees: 311.8073968365788, referencePlane: .ecliptic, color: Color(red: 0.70, green: 0.70, blue: 0.69)),
        .moon(id: "ophelia", name: "Ophelia", parentID: "uranus", radiusKm: 21, semiMajorAxisKm: 53838.9449454653, orbitalPeriodDays: 0.3774188112892202, eccentricity: 0.01105107380672335, inclinationDegrees: 97.52122526455584, longitudeOfAscendingNodeDegrees: 167.6996298373904, argumentOfPeriapsisDegrees: 141.0803663529104, meanAnomalyAtEpochDegrees: 334.8213475570083, referencePlane: .ecliptic, color: Color(red: 0.71, green: 0.71, blue: 0.70)),
        .moon(id: "bianca", name: "Bianca", parentID: "uranus", radiusKm: 26, semiMajorAxisKm: 59235.63817401277, orbitalPeriodDays: 0.4355653654849459, eccentricity: 0.006892711342090336, inclinationDegrees: 96.31912988909166, longitudeOfAscendingNodeDegrees: 169.5367809770911, argumentOfPeriapsisDegrees: 23.15501579592883, meanAnomalyAtEpochDegrees: 339.8765312824398, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .moon(id: "cressida", name: "Cressida", parentID: "uranus", radiusKm: 40, semiMajorAxisKm: 61833.62508635496, orbitalPeriodDays: 0.4645321686392325, eccentricity: 0.004584301327574541, inclinationDegrees: 96.63577586954194, longitudeOfAscendingNodeDegrees: 166.2310628100995, argumentOfPeriapsisDegrees: 114.433127147188, meanAnomalyAtEpochDegrees: 259.8779144529253, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .moon(id: "desdemona", name: "Desdemona", parentID: "uranus", radiusKm: 32, semiMajorAxisKm: 62723.129894402, orbitalPeriodDays: 0.4745918914081446, eccentricity: 0.005987615303770525, inclinationDegrees: 95.69122834883756, longitudeOfAscendingNodeDegrees: 165.2557275964431, argumentOfPeriapsisDegrees: 107.6434879130858, meanAnomalyAtEpochDegrees: 349.6394843738526, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .moon(id: "juliet", name: "Juliet", parentID: "uranus", radiusKm: 47, semiMajorAxisKm: 64421.35348054676, orbitalPeriodDays: 0.493996075822624, eccentricity: 0.005664574758731222, inclinationDegrees: 96.06270197208654, longitudeOfAscendingNodeDegrees: 170.1913026345734, argumentOfPeriapsisDegrees: 68.17907538478653, meanAnomalyAtEpochDegrees: 321.1624562554061, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .moon(id: "portia", name: "Portia", parentID: "uranus", radiusKm: 68, semiMajorAxisKm: 66159.79790163832, orbitalPeriodDays: 0.5141264961328071, eccentricity: 0.004529301321439202, inclinationDegrees: 95.17790148155595, longitudeOfAscendingNodeDegrees: 168.4770548795837, argumentOfPeriapsisDegrees: 153.3590984432051, meanAnomalyAtEpochDegrees: 214.6738297184929, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .moon(id: "rosalind", name: "Rosalind", parentID: "uranus", radiusKm: 36, semiMajorAxisKm: 69986.16272272833, orbitalPeriodDays: 0.5593672103229116, eccentricity: 0.003719363748000255, inclinationDegrees: 98.89293491997989, longitudeOfAscendingNodeDegrees: 168.8639886688405, argumentOfPeriapsisDegrees: 104.0707529005941, meanAnomalyAtEpochDegrees: 319.2529768170789, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .moon(id: "belinda", name: "Belinda", parentID: "uranus", radiusKm: 45, semiMajorAxisKm: 75310.6818439296, orbitalPeriodDays: 0.6244010157655763, eccentricity: 0.00220031427778789, inclinationDegrees: 96.90902812507299, longitudeOfAscendingNodeDegrees: 166.4656393035229, argumentOfPeriapsisDegrees: 13.44120027235515, meanAnomalyAtEpochDegrees: 277.1723540928215, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .moon(id: "perdita", name: "Perdita", parentID: "uranus", radiusKm: 15, semiMajorAxisKm: 76468.94219267411, orbitalPeriodDays: 0.6388609682028544, eccentricity: 0.004197874122130388, inclinationDegrees: 98.51436080681174, longitudeOfAscendingNodeDegrees: 169.0601573266781, argumentOfPeriapsisDegrees: 46.33020232656376, meanAnomalyAtEpochDegrees: 214.9162761615589, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .moon(id: "mab", name: "Mab", parentID: "uranus", radiusKm: 12, semiMajorAxisKm: 97777.1100487376, orbitalPeriodDays: 0.9237076210860308, eccentricity: 0.005861065230055584, inclinationDegrees: 96.23740325313909, longitudeOfAscendingNodeDegrees: 166.5660364880436, argumentOfPeriapsisDegrees: 344.5304202582033, meanAnomalyAtEpochDegrees: 80.72907331120223, referencePlane: .ecliptic, color: Color(red: 0.72, green: 0.73, blue: 0.72)),
        .planet(id: "neptune", name: "Neptune", radiusKm: 24622, semiMajorAxisKm: 4500762929.887115, orbitalPeriodDays: 60273.7666005881, eccentricity: 0.0102316353283902, inclinationDegrees: 1.773615543911655, longitudeOfAscendingNodeDegrees: 131.9185081836393, argumentOfPeriapsisDegrees: 278.7530270725777, meanAnomalyAtEpochDegrees: 254.5065922101274, referencePlane: .ecliptic, textureName: "2k_neptune.jpg", color: Color(red: 0.28, green: 0.46, blue: 0.88), axialTilt: 28.32, rotationPeriodHours: 16.11),
        .moon(
            id: "triton",
            name: "Triton",
            parentID: "neptune",
            radiusKm: 1353.4,
            semiMajorAxisKm: 354765.1413366171,
            orbitalPeriodDays: 5.877053200262932,
            eccentricity: 2.982831532195733e-05,
            inclinationDegrees: 129.1289114341591,
            longitudeOfAscendingNodeDegrees: 222.7780176737343,
            argumentOfPeriapsisDegrees: 292.4132882201414,
            meanAnomalyAtEpochDegrees: 167.808373787906,
            referencePlane: .ecliptic,
            textureName: "triton.jpg",
            isMajor: true,
            color: Color(red: 0.85, green: 0.72, blue: 0.68),
            assetTier: .real,
            shapeModelName: "Neptune/Triton_1_2707.usdz"
        ),
        .moon(id: "nereid", name: "Nereid", parentID: "neptune", radiusKm: 170, semiMajorAxisKm: 5515916.627072304, orbitalPeriodDays: 360.3463516191061, eccentricity: 0.7450365875611771, inclinationDegrees: 5.018693693420382, longitudeOfAscendingNodeDegrees: 320.0597846399918, argumentOfPeriapsisDegrees: 296.0093834743906, meanAnomalyAtEpochDegrees: 222.8770350172617, referencePlane: .ecliptic, color: Color(red: 0.62, green: 0.54, blue: 0.51)),
        .moon(id: "naiad", name: "Naiad", parentID: "neptune", radiusKm: 33, semiMajorAxisKm: 48294.29553250751, orbitalPeriodDays: 0.2952142672043909, eccentricity: 0.001369782368798635, inclinationDegrees: 33.10156556261634, longitudeOfAscendingNodeDegrees: 51.39378671206431, argumentOfPeriapsisDegrees: 213.7353292403972, meanAnomalyAtEpochDegrees: 40.1677409093827, referencePlane: .ecliptic, color: Color(red: 0.74, green: 0.75, blue: 0.74)),
        .moon(id: "thalassa", name: "Thalassa", parentID: "neptune", radiusKm: 41, semiMajorAxisKm: 50140.0815134471, orbitalPeriodDays: 0.3122993945523282, eccentricity: 0.001387692073972567, inclinationDegrees: 28.57897362303262, longitudeOfAscendingNodeDegrees: 48.72434384878114, argumentOfPeriapsisDegrees: 188.8946923479715, meanAnomalyAtEpochDegrees: 96.39849829114974, referencePlane: .ecliptic, color: Color(red: 0.74, green: 0.75, blue: 0.74)),
        .moon(id: "despina", name: "Despina", parentID: "neptune", radiusKm: 75, semiMajorAxisKm: 52587.98201157073, orbitalPeriodDays: 0.3354465614132991, eccentricity: 0.0009296209819933675, inclinationDegrees: 28.56718333000707, longitudeOfAscendingNodeDegrees: 49.00380539162423, argumentOfPeriapsisDegrees: 181.766878451924, meanAnomalyAtEpochDegrees: 315.1267614997923, referencePlane: .ecliptic, color: Color(red: 0.74, green: 0.75, blue: 0.74)),
        .moon(id: "galatea", name: "Galatea", parentID: "neptune", radiusKm: 88, semiMajorAxisKm: 62005.08258240638, orbitalPeriodDays: 0.4294716679302587, eccentricity: 0.000997509371147893, inclinationDegrees: 28.53159585326455, longitudeOfAscendingNodeDegrees: 49.0272149216573, argumentOfPeriapsisDegrees: 131.2940983428954, meanAnomalyAtEpochDegrees: 353.1919199898839, referencePlane: .ecliptic, color: Color(red: 0.74, green: 0.75, blue: 0.74)),
        .moon(id: "larissa", name: "Larissa", parentID: "neptune", radiusKm: 97, semiMajorAxisKm: 73592.47510295772, orbitalPeriodDays: 0.5553204869882861, eccentricity: 0.001242025916197138, inclinationDegrees: 28.54279484958053, longitudeOfAscendingNodeDegrees: 49.47928793442631, argumentOfPeriapsisDegrees: 334.8822662376975, meanAnomalyAtEpochDegrees: 339.4094348968938, referencePlane: .ecliptic, color: Color(red: 0.68, green: 0.69, blue: 0.69)),
        .moon(id: "proteus", name: "Proteus", parentID: "neptune", radiusKm: 210, semiMajorAxisKm: 117675.6999735395, orbitalPeriodDays: 1.122855040610827, eccentricity: 0.0002643253319469015, inclinationDegrees: 29.05241492848959, longitudeOfAscendingNodeDegrees: 48.71906020186979, argumentOfPeriapsisDegrees: 357.0567725355536, meanAnomalyAtEpochDegrees: 304.7929573180154, referencePlane: .ecliptic, color: Color(red: 0.56, green: 0.58, blue: 0.57)),
        .moon(id: "halimede", name: "Halimede", parentID: "neptune", radiusKm: 31, semiMajorAxisKm: 16575628.49598128, orbitalPeriodDays: 1877.148350933251, eccentricity: 0.250381852878418, inclinationDegrees: 112.7975106936114, longitudeOfAscendingNodeDegrees: 218.1545568759618, argumentOfPeriapsisDegrees: 155.9128040955902, meanAnomalyAtEpochDegrees: 230.3566420488523, referencePlane: .ecliptic, color: Color(red: 0.46, green: 0.40, blue: 0.37)),
        .moon(id: "psamathe", name: "Psamathe", parentID: "neptune", radiusKm: 20, semiMajorAxisKm: 48952802.88444453, orbitalPeriodDays: 9527.082682229033, eccentricity: 0.1695689736806079, inclinationDegrees: 122.5718504585232, longitudeOfAscendingNodeDegrees: 321.6922388309715, argumentOfPeriapsisDegrees: 143.0002614908613, meanAnomalyAtEpochDegrees: 174.9558636821116, referencePlane: .ecliptic, color: Color(red: 0.46, green: 0.40, blue: 0.37)),
        .moon(id: "sao", name: "Sao", parentID: "neptune", radiusKm: 22, semiMajorAxisKm: 22140868.15018551, orbitalPeriodDays: 2897.914434370532, eccentricity: 0.1397523720006695, inclinationDegrees: 53.10066895527294, longitudeOfAscendingNodeDegrees: 59.68338188447699, argumentOfPeriapsisDegrees: 64.21423224972069, meanAnomalyAtEpochDegrees: 7.305220610187689, referencePlane: .ecliptic, color: Color(red: 0.46, green: 0.40, blue: 0.37)),
        .moon(id: "laomedeia", name: "Laomedeia", parentID: "neptune", radiusKm: 21, semiMajorAxisKm: 23641780.11434893, orbitalPeriodDays: 3197.524274493118, eccentricity: 0.4018618821966127, inclinationDegrees: 38.99208712582344, longitudeOfAscendingNodeDegrees: 48.51944096473807, argumentOfPeriapsisDegrees: 138.8019159749453, meanAnomalyAtEpochDegrees: 162.4733466016785, referencePlane: .ecliptic, color: Color(red: 0.46, green: 0.40, blue: 0.37)),
        .moon(id: "neso", name: "Neso", parentID: "neptune", radiusKm: 30, semiMajorAxisKm: 49507976.73805396, orbitalPeriodDays: 9689.611327359937, eccentricity: 0.7290221616191075, inclinationDegrees: 142.6968048141622, longitudeOfAscendingNodeDegrees: 73.77670692877129, argumentOfPeriapsisDegrees: 109.8885799303342, meanAnomalyAtEpochDegrees: 193.5378483554908, referencePlane: .ecliptic, color: Color(red: 0.46, green: 0.40, blue: 0.37)),
        .planet(
            id: "pluto",
            name: "Pluto",
            radiusKm: 1188.3,
            semiMajorAxisKm: 5885107843.14798,
            orbitalPeriodDays: 90124.30851664598,
            eccentricity: 0.2476858305355733,
            inclinationDegrees: 17.17578604208126,
            longitudeOfAscendingNodeDegrees: 110.3361691631954,
            argumentOfPeriapsisDegrees: 113.0705563903158,
            meanAnomalyAtEpochDegrees: 15.36190513663378,
            referencePlane: .ecliptic,
            textureName: "pluto.jpg",
            color: Color(red: 0.73, green: 0.61, blue: 0.55),
            axialTilt: 119.6,
            rotationPeriodHours: -153.29,
            isMajor: true,
            assetTier: .real
        ),
        .moon(id: "charon", name: "Charon", parentID: "pluto", radiusKm: 606, semiMajorAxisKm: 19595.76725970738, orbitalPeriodDays: 6.387223163979606, eccentricity: 0.0001609843859699543, inclinationDegrees: 112.8877853224359, longitudeOfAscendingNodeDegrees: 227.3930499717047, argumentOfPeriapsisDegrees: 172.2673716396441, meanAnomalyAtEpochDegrees: 149.0757710199105, referencePlane: .ecliptic, textureName: "charon.jpg", isMajor: true, color: Color(red: 0.66, green: 0.64, blue: 0.63), assetTier: .real),
        .moon(id: "nix", name: "Nix", parentID: "pluto", radiusKm: 23, semiMajorAxisKm: 48927.26913283632, orbitalPeriodDays: 25.19969837232051, eccentricity: 0.007988456567198609, inclinationDegrees: 112.8717284972895, longitudeOfAscendingNodeDegrees: 227.377083273535, argumentOfPeriapsisDegrees: 340.6053518558605, meanAnomalyAtEpochDegrees: 244.1027213365596, referencePlane: .ecliptic, color: Color(red: 0.66, green: 0.66, blue: 0.64)),
        .moon(id: "hydra", name: "Hydra", parentID: "pluto", radiusKm: 30, semiMajorAxisKm: 65120.59269688432, orbitalPeriodDays: 38.69427703862821, eccentricity: 0.01181689297249006, inclinationDegrees: 112.6146145674748, longitudeOfAscendingNodeDegrees: 227.4470083910734, argumentOfPeriapsisDegrees: 236.6289314282276, meanAnomalyAtEpochDegrees: 92.03948131123616, referencePlane: .ecliptic, color: Color(red: 0.67, green: 0.66, blue: 0.64)),
        .moon(id: "kerberos", name: "Kerberos", parentID: "pluto", radiusKm: 14, semiMajorAxisKm: 58377.06773393948, orbitalPeriodDays: 32.84213138256408, eccentricity: 0.01499303292746564, inclinationDegrees: 113.3060361052374, longitudeOfAscendingNodeDegrees: 227.3885230558546, argumentOfPeriapsisDegrees: 68.47303890935579, meanAnomalyAtEpochDegrees: 276.3808238657948, referencePlane: .ecliptic, color: Color(red: 0.52, green: 0.51, blue: 0.49)),
        .moon(id: "styx", name: "Styx", parentID: "pluto", radiusKm: 10, semiMajorAxisKm: 43571.12064488187, orbitalPeriodDays: 21.17707627806605, eccentricity: 0.03229604138638816, inclinationDegrees: 112.8456220211691, longitudeOfAscendingNodeDegrees: 227.3599693856444, argumentOfPeriapsisDegrees: 26.61276326584533, meanAnomalyAtEpochDegrees: 176.0578626932984, referencePlane: .ecliptic, color: Color(red: 0.52, green: 0.51, blue: 0.49))
    ]

    static let bodies: [NativeCelestialBody] = {
        var result: [NativeCelestialBody] = []
        var parentMoonCounts: [String: Int] = [:]

        let baseByParent: [String: (radius: Double, step: Double, period: Double)] = [
            "mars": (9200.0, 13500.0, 0.75),
            "jupiter": (180000.0, 440000.0, 2.4),
            "saturn": (140000.0, 220000.0, 1.2),
            "uranus": (130000.0, 130000.0, 1.4),
            "neptune": (90000.0, 300000.0, 1.3),
            "pluto": (19000.0, 14000.0, 6.4)
        ]

        for raw in rawBodies {
            if raw.kind == .moon {
                let parentID = raw.parentID ?? "unknown"
                let index = parentMoonCounts[parentID] ?? 0
                parentMoonCounts[parentID] = index + 1

                let base = baseByParent[parentID] ?? (100000.0, 100000.0, 3.0)
                let defaultSemiMajorAxis = base.radius + Double(index) * base.step
                let defaultOrbitalPeriod = base.period * pow(Double(index + 1), 1.35)

                let semiMajorAxis = raw.semiMajorAxisKilometers ?? defaultSemiMajorAxis
                let orbitalPeriod = raw.orbitalPeriodDays ?? defaultOrbitalPeriod

                let isSynchronous = raw.isMajor
                let rotationPeriod = raw.rotationPeriodHours ?? Float(isSynchronous ? orbitalPeriod * 24.0 : 0.0)

                let texture = raw.textureName ?? (raw.assetTier == .procedural ? "" : "\(raw.id).jpg")

                result.append(NativeCelestialBody(
                    id: raw.id,
                    name: raw.name,
                    kind: raw.kind,
                    parentID: raw.parentID,
                    radiusKilometers: raw.radiusKilometers,
                    semiMajorAxisKilometers: semiMajorAxis,
                    orbitalPeriodDays: orbitalPeriod,
                    eccentricity: raw.eccentricity,
                    inclinationDegrees: raw.inclinationDegrees,
                    longitudeOfAscendingNodeDegrees: raw.longitudeOfAscendingNodeDegrees,
                    argumentOfPeriapsisDegrees: raw.argumentOfPeriapsisDegrees,
                    meanAnomalyAtEpochDegrees: raw.meanAnomalyAtEpochDegrees,
                    referencePlane: raw.referencePlane,
                    textureName: texture,
                    shapeModelName: raw.shapeModelName,
                    displayColor: raw.displayColor,
                    axialTiltDegrees: raw.axialTiltDegrees,
                    rotationPeriodHours: rotationPeriod,
                    ring: raw.ring,
                    cloudLayers: raw.cloudLayers,
                    isMajor: raw.isMajor,
                    assetTier: raw.assetTier
                ))
            } else {
                result.append(NativeCelestialBody(
                    id: raw.id,
                    name: raw.name,
                    kind: raw.kind,
                    parentID: raw.parentID,
                    radiusKilometers: raw.radiusKilometers,
                    semiMajorAxisKilometers: raw.semiMajorAxisKilometers,
                    orbitalPeriodDays: raw.orbitalPeriodDays,
                    eccentricity: raw.eccentricity,
                    inclinationDegrees: raw.inclinationDegrees,
                    longitudeOfAscendingNodeDegrees: raw.longitudeOfAscendingNodeDegrees,
                    argumentOfPeriapsisDegrees: raw.argumentOfPeriapsisDegrees,
                    meanAnomalyAtEpochDegrees: raw.meanAnomalyAtEpochDegrees,
                    referencePlane: raw.referencePlane,
                    textureName: raw.textureName ?? "",
                    shapeModelName: raw.shapeModelName,
                    displayColor: raw.displayColor,
                    axialTiltDegrees: raw.axialTiltDegrees,
                    rotationPeriodHours: raw.rotationPeriodHours ?? 0.0,
                    ring: raw.ring,
                    cloudLayers: raw.cloudLayers,
                    isMajor: raw.isMajor,
                    assetTier: raw.assetTier
                ))
            }
        }
        return result
    }()

    static let defaultSelection = bodies[0]

    static let bodyByID: [String: NativeCelestialBody] = {
        Dictionary(uniqueKeysWithValues: bodies.map { ($0.id, $0) })
    }()

    static func body(withID id: String) -> NativeCelestialBody? {
        bodyByID[id]
    }

    static func visibleBodies(options: NativeRenderOptions) -> [NativeCelestialBody] {
        bodies.filter { body in
            if body.kind != .moon { return true }
            if !options.showMoons { return false }
            if !options.showProcedural && body.assetTier == .procedural { return false }
            return options.showMinorMoons || body.isMajor || body.parentID == "earth"
        }
    }
}

struct NativeMaterialMaps: Equatable, Sendable {
    let bumpMapName: String?
    let bumpStrength: Float
    let bumpMapIsNormalMap: Bool
    let specularMapName: String?
    let specularMapURL: String?
    let specularRefreshIntervalSeconds: TimeInterval
    let specularStrength: Float
    let emissionMapName: String?
    let emissionStrength: Float

    init(
        bumpMapName: String?,
        bumpStrength: Float,
        specularMapName: String?,
        specularStrength: Float,
        bumpMapIsNormalMap: Bool = false,
        specularMapURL: String? = nil,
        specularRefreshIntervalSeconds: TimeInterval = 60,
        emissionMapName: String? = nil,
        emissionStrength: Float = 0
    ) {
        self.bumpMapName = bumpMapName
        self.bumpStrength = bumpStrength
        self.bumpMapIsNormalMap = bumpMapIsNormalMap
        self.specularMapName = specularMapName
        self.specularMapURL = specularMapURL
        self.specularRefreshIntervalSeconds = specularRefreshIntervalSeconds
        self.specularStrength = specularStrength
        self.emissionMapName = emissionMapName
        self.emissionStrength = emissionStrength
    }

    static let none = NativeMaterialMaps(
        bumpMapName: nil,
        bumpStrength: 0,
        specularMapName: nil,
        specularStrength: 0
    )
}

// MARK: - PBR Specular Roughness

extension NativeCelestialBody {
    var materialMaps: NativeMaterialMaps {
        switch id {
        case "earth":
            return NativeMaterialMaps(
                bumpMapName: "Maps/8k_earth_normal_map.tif",
                bumpStrength: 0.8,
                specularMapName: "Maps/8k_earth_specular_map.tif",
                specularStrength: 1.0,
                bumpMapIsNormalMap: true,
                specularMapURL: "https://clouds.matteason.co.uk/images/8192x4096/specular.jpg",
                specularRefreshIntervalSeconds: 60,
                emissionMapName: "Maps/8k_earth_nightmap.jpg",
                emissionStrength: 1.35
            )
        case "phobos":
            return NativeMaterialMaps(bumpMapName: "phobos_dem.jpg", bumpStrength: 5.0, specularMapName: nil, specularStrength: 0)
        case "enceladus":
            return NativeMaterialMaps(bumpMapName: "enceladus_dem.jpg", bumpStrength: 3.5, specularMapName: nil, specularStrength: 0)
        case "titan":
            return NativeMaterialMaps(bumpMapName: nil, bumpStrength: 0, specularMapName: "Saturn/titanspecular8k_by_mapperpro_dgtvajd.png", specularStrength: 1.0)
        case "ariel":
            return NativeMaterialMaps(bumpMapName: "Uranus/ArielBump.Png", bumpStrength: 2.8, specularMapName: nil, specularStrength: 0)
        case "umbriel":
            return NativeMaterialMaps(bumpMapName: "Uranus/UmbirelBump.png", bumpStrength: 2.4, specularMapName: nil, specularStrength: 0)
        case "titania":
            return NativeMaterialMaps(bumpMapName: "Uranus/TitaniaBump.png", bumpStrength: 2.4, specularMapName: nil, specularStrength: 0)
        case "oberon":
            return NativeMaterialMaps(bumpMapName: "Uranus/OberonBump.png", bumpStrength: 2.4, specularMapName: nil, specularStrength: 0)
        case "miranda":
            return NativeMaterialMaps(bumpMapName: "Uranus/MirandaBump.png", bumpStrength: 3.0, specularMapName: nil, specularStrength: 0)
        case "pluto":
            return NativeMaterialMaps(bumpMapName: "pluto_dem.jpg", bumpStrength: 3.5, specularMapName: nil, specularStrength: 0)
        case "charon":
            return NativeMaterialMaps(bumpMapName: "charon_dem.jpg", bumpStrength: 3.5, specularMapName: nil, specularStrength: 0)
        default:
            return .none
        }
    }

    var surfaceTintStrength: Float {
        id == "earth" ? 0.0 : 0.18
    }

    /// Optional live base-map URL. `{DATE}` is replaced at fetch time with a
    /// UTC calendar date (`yyyy-MM-dd`). Earth pulls NASA GIBS VIIRS daily
    /// true-color imagery — the real, current Earth (clouds included), which is
    /// why Earth has no separate cloud layer. Falls back to the bundled texture
    /// until the download completes.
    var liveSurfaceMapURLTemplate: String? {
        switch id {
        case "earth":
            return "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?"
                + "SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
                + "&LAYERS=VIIRS_SNPP_CorrectedReflectance_TrueColor"
                + "&CRS=EPSG:4326&BBOX=-90,-180,90,180&WIDTH=8192&HEIGHT=4096"
                + "&FORMAT=image/jpeg&TIME={DATE}"
        default:
            return nil
        }
    }

    /// Approximate surface roughness used for Oren-Nayar diffuse + Blinn-Phong specular.
    /// Range: 0 = perfect mirror, 1 = fully diffuse Lambertian.
    /// Values are derived from surface type without modifying the body catalog.
    var specularRoughness: Float {
        switch id {

        // ── Self-luminous ────────────────────────────────────────────────────
        case "sun":
            return 1.0  // stars don't use specular

        // ── Worlds with thick cloud cover / ocean mix ────────────────────────
        case "earth":   return 0.30   // ocean + cloud — nice specular highlights
        case "venus":   return 0.40   // total cloud deck, diffuse sheen
        case "titan":   return 0.50   // hazy orange clouds

        // ── Gas / ice giants ─────────────────────────────────────────────────
        case "jupiter": return 0.35   // banded ammonia clouds
        case "saturn":  return 0.38   // paler cloud bands
        case "uranus":  return 0.28   // methane haze, fairly smooth
        case "neptune": return 0.28   // similar to Uranus

        // ── Rocky/airless inner worlds ───────────────────────────────────────
        case "mercury": return 0.85   // heavily cratered regolith
        case "mars":    return 0.78   // dusty, ochre surface
        case "moon":    return 0.88   // ancient highland regolith

        // ── Volcanic / sulphur world ─────────────────────────────────────────
        case "io":      return 0.62   // sulphur deposits, mixed gloss

        // ── Icy Galilean & Saturnian moons ───────────────────────────────────
        case "europa":    return 0.12  // nearly pure water-ice, mirror-like
        case "ganymede":  return 0.22  // mixed ice + rock
        case "callisto":  return 0.35  // dark, dusty ice
        case "enceladus": return 0.10  // whitest body in the solar system
        case "mimas":     return 0.30
        case "tethys":    return 0.25
        case "dione":     return 0.28
        case "rhea":      return 0.22
        case "iapetus":   return 0.45  // dark leading hemisphere

        // ── Uranian moons ────────────────────────────────────────────────────
        case "miranda":  return 0.35
        case "ariel":    return 0.30
        case "umbriel":  return 0.50
        case "titania":  return 0.38
        case "oberon":   return 0.42

        // ── Neptunian moons ──────────────────────────────────────────────────
        case "triton":   return 0.25   // nitrogen ice, very bright

        // ── Kuiper Belt / dwarf planets ──────────────────────────────────────
        case "pluto":    return 0.45
        case "charon":   return 0.50
        case "eris":     return 0.30
        case "makemake": return 0.40
        case "haumea":   return 0.32

        default:
            // Stars → no specular; small procedural moons → rough regolith
            return kind == .star ? 1.0 : 0.82
        }
    }
}
