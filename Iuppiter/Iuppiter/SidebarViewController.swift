import SwiftUI

struct BodiesSidebar: View {
    let bodies: [NativeCelestialBody]
    @Binding var selectedBodyID: String
    @State private var searchText = ""

    var body: some View {
        let model = BodySidebarModel(bodies: bodies, searchText: searchText)

        List(selection: $selectedBodyID) {
            if model.isSearching {
                searchResultsSection(model)
            } else {
                hierarchySections(model)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search bodies")
        .navigationTitle("Iuppiter")
        .navigationSubtitle("Solar System")
    }

    @ViewBuilder
    private func hierarchySections(_ model: BodySidebarModel) -> some View {
        if !model.stars.isEmpty {
            Section("Star") {
                ForEach(model.stars) { body in
                    BodySidebarRow(body: body)
                        .tag(body.id)
                }
            }
        }

        if !model.planets.isEmpty {
            Section("Planets") {
                ForEach(model.planets) { group in
                    BodySidebarGroupRow(group: group)
                }
            }
        }

        if !model.dwarfPlanets.isEmpty {
            Section("Dwarf Planets") {
                ForEach(model.dwarfPlanets) { group in
                    BodySidebarGroupRow(group: group)
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultsSection(_ model: BodySidebarModel) -> some View {
        Section("Results") {
            if model.searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(model.searchResults) { body in
                    BodySidebarRow(body: body, subtitle: model.searchSubtitle(for: body))
                        .tag(body.id)
                }
            }
        }
    }
}

private struct BodySidebarModel {
    let stars: [NativeCelestialBody]
    let planets: [BodySidebarGroup]
    let dwarfPlanets: [BodySidebarGroup]
    let searchResults: [NativeCelestialBody]

    private let bodiesByID: [String: NativeCelestialBody]
    private let trimmedSearchText: String

    var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    init(bodies: [NativeCelestialBody], searchText: String) {
        let indexedBodies = Dictionary(uniqueKeysWithValues: bodies.map { ($0.id, $0) })
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        bodiesByID = indexedBodies
        trimmedSearchText = query
        stars = bodies.filter { $0.kind == .star }
        planets = Self.groupedBodies(ofKind: .planet, bodies: bodies)
        dwarfPlanets = Self.groupedBodies(ofKind: .dwarfPlanet, bodies: bodies)

        guard !query.isEmpty else {
            searchResults = []
            return
        }

        let bodyLookup = indexedBodies
        searchResults = bodies.filter { candidate in
            let parentName = candidate.parentID.flatMap { bodyLookup[$0]?.name } ?? ""
            return candidate.name.matchesSidebarSearch(query)
                || candidate.kind.title.matchesSidebarSearch(query)
                || parentName.matchesSidebarSearch(query)
        }
    }

    func searchSubtitle(for body: NativeCelestialBody) -> String {
        guard let parentID = body.parentID,
              let parent = bodiesByID[parentID] else {
            return body.kind.title
        }
        return "\(body.kind.title) of \(parent.name)"
    }

    private static func groupedBodies(
        ofKind kind: NativeBodyKind,
        bodies: [NativeCelestialBody]
    ) -> [BodySidebarGroup] {
        let moonsByParent = Dictionary(grouping: bodies.filter { $0.kind == .moon }) { moon in
            moon.parentID ?? ""
        }

        return bodies
            .filter { $0.kind == kind }
            .map { body in
                BodySidebarGroup(
                    body: body,
                    children: moonsByParent[body.id] ?? []
                )
            }
    }
}

private struct BodySidebarGroup: Identifiable {
    let body: NativeCelestialBody
    let children: [NativeCelestialBody]

    var id: String {
        body.id
    }
}

private struct BodySidebarGroupRow: View {
    let group: BodySidebarGroup

    var body: some View {
        if group.children.isEmpty {
            BodySidebarRow(body: group.body)
                .tag(group.body.id)
        } else {
            DisclosureGroup {
                ForEach(group.children) { child in
                    BodySidebarRow(body: child, subtitle: child.kind.title)
                        .tag(child.id)
                }
            } label: {
                BodySidebarRow(
                    body: group.body,
                    subtitle: "\(group.body.kind.title) · \(group.children.count) moons"
                )
            }
            .tag(group.body.id)
        }
    }
}

private struct BodySidebarRow: View {
    let celestialBody: NativeCelestialBody
    var subtitle: String?

    init(body: NativeCelestialBody, subtitle: String? = nil) {
        self.celestialBody = body
        self.subtitle = subtitle
    }

    private var secondaryText: String {
        subtitle ?? celestialBody.kind.title
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(celestialBody.name)
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "circle.fill")
                .foregroundStyle(celestialBody.displayColor)
                .font(.caption)
                .accessibilityHidden(true)
        }
        .help("\(celestialBody.kind.title) · \(celestialBody.radiusKilometers.formatted()) km")
        .accessibilityLabel("\(celestialBody.name), \(secondaryText)")
    }
}

private extension String {
    func matchesSidebarSearch(_ query: String) -> Bool {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
