import SwiftUI

/// Phase 4 PR3: small popover used by `HandDetailView`'s tag chip row.
/// Lets the user quickly attach one of the `CommonHandTag` presets or
/// type a free-form tag of their own.
///
/// Bookmark is intentionally excluded from the preset chips here — the
/// dedicated star button in the toolbar is the better entry point for
/// that flow.
struct AddTagPopover: View {
    /// Called with the chosen tag string when the user picks one.
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customTag: String = ""

    private var presets: [CommonHandTag] {
        CommonHandTag.allCases.filter { $0 != .bookmark }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tag this hand")
                .font(.headline)

            // Preset chip grid
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                spacing: 8
            ) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        commit(preset.rawValue)
                    } label: {
                        Text(preset.displayName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.15))
                            )
                            .overlay(
                                Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                            )
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Free-form text field
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom tag")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("e.g. Cooler", text: $customTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitCustom() }
                    Button("Add") { commitCustom() }
                        .disabled(trimmedCustom.isEmpty)
                }
            }
        }
        .padding()
        .frame(width: 320)
    }

    private var trimmedCustom: String {
        customTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit(_ tag: String) {
        onPick(tag)
        dismiss()
    }

    private func commitCustom() {
        guard !trimmedCustom.isEmpty else { return }
        commit(trimmedCustom)
    }
}
