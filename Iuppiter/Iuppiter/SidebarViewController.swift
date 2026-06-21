import SwiftUI

struct SidebarViewController: View {
    let bodies: [NativeCelestialBody]
    let selectedBodyID: String
    let selectBody: (String) -> Void

    private var selection: Binding<String?> {
        Binding(
            get: { selectedBodyID },
            set: { newValue in
                if let newValue {
                    selectBody(newValue)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Iuppiter")
                    .font(.title2.weight(.semibold))
                Text("Native Metal renderer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            List(selection: selection) {
                Section("Bodies") {
                    ForEach(bodies) { body in
                        BodySidebarRow(
                            celestialBody: body,
                            isSelected: body.id == selectedBodyID
                        )
                        .tag(body.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(.bar)
    }
}

private struct BodySidebarRow: View {
    let celestialBody: NativeCelestialBody
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(celestialBody.displayColor)
                .frame(width: 14, height: 14)
                .shadow(color: celestialBody.displayColor.opacity(0.55), radius: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(celestialBody.name)
                    .font(.callout.weight(.semibold))
                Text(celestialBody.kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityLabel(celestialBody.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
