#if os(macOS)
import CoreGraphics
import Observation
import SwiftUI

struct SolarSystemLabel: Identifiable, Equatable {
    let id: String
    let name: String
    let position: CGPoint
    let isSelected: Bool
    let displayColor: Color

    static func == (lhs: SolarSystemLabel, rhs: SolarSystemLabel) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.position == rhs.position
            && lhs.isSelected == rhs.isSelected
    }
}

@Observable
final class SolarSystemViewport {
    var labels: [SolarSystemLabel] = []

    func update(labels: [SolarSystemLabel]) {
        guard self.labels != labels else {
            return
        }
        self.labels = labels
    }
}
#endif
