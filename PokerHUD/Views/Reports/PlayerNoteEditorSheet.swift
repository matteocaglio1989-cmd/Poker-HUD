import SwiftUI

/// Phase 4 PR3: modal sheet used by `OpponentDetailView` to add or edit a
/// player note. Two fields:
///   • A multi-line text editor for the note body.
///   • A 6-swatch colour picker (matching the persisted `color` column on
///     `PlayerNote`) so the user can colour-code notes by category.
///
/// Used in two modes:
///   • `mode = .add(playerId)` — creates a new note.
///   • `mode = .edit(note)`    — pre-populates with existing values and
///                               persists with `updateNote`.
struct PlayerNoteEditorSheet: View {
    enum Mode: Identifiable {
        case add(playerId: Int64)
        case edit(PlayerNote)

        var id: String {
            switch self {
            case .add(let playerId):  return "add-\(playerId)"
            case .edit(let note):     return "edit-\(note.id ?? -1)"
            }
        }
    }

    let mode: Mode
    /// Called once after a successful save with the persisted note.
    let onSave: (PlayerNote) -> Void
    /// Called for explicit deletes (only available in `.edit` mode).
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String
    @State private var selectedColor: NoteColor

    private let repo = PlayerRepository()

    init(
        mode: Mode,
        onSave: @escaping (PlayerNote) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .add:
            _noteText = State(initialValue: "")
            _selectedColor = State(initialValue: .neutral)
        case .edit(let note):
            _noteText = State(initialValue: note.note ?? "")
            _selectedColor = State(initialValue: NoteColor.from(rawValue: note.color))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(headerTitle)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Note")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $noteText)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Colour")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    ForEach(NoteColor.allCases) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(color.swatch)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedColor == color ? Color.primary : Color.secondary.opacity(0.3),
                                            lineWidth: selectedColor == color ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(color.displayName)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                if case .edit = mode, let onDelete = onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 360)
    }

    private var headerTitle: String {
        switch mode {
        case .add:  return "New player note"
        case .edit: return "Edit player note"
        }
    }

    private func save() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            switch mode {
            case .add(let playerId):
                var note = PlayerNote(
                    id: nil,
                    playerId: playerId,
                    note: trimmed,
                    color: selectedColor.rawValue,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try repo.addNote(&note)
                onSave(note)
            case .edit(let original):
                var updated = original
                updated.note = trimmed
                updated.color = selectedColor.rawValue
                try repo.updateNote(updated)
                onSave(updated)
            }
            dismiss()
        } catch {
            // Surface the error to the console — the parent view's own
            // error state isn't accessible from this sheet, and a popover
            // alert here would block the editor.
            Log.app.error("[PlayerNoteEditorSheet] save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Colour palette

/// Phase 4 PR3: 6-swatch palette persisted to `PlayerNote.color`.
/// Stored as the rawValue string so the column stays self-describing.
enum NoteColor: String, CaseIterable, Identifiable, Hashable {
    case neutral
    case red
    case orange
    case yellow
    case green
    case blue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neutral: return "Neutral"
        case .red:     return "Red"
        case .orange:  return "Orange"
        case .yellow:  return "Yellow"
        case .green:   return "Green"
        case .blue:    return "Blue"
        }
    }

    var swatch: Color {
        switch self {
        case .neutral: return Color.gray
        case .red:     return Color.red
        case .orange:  return Color.orange
        case .yellow:  return Color.yellow
        case .green:   return Color.green
        case .blue:    return Color.blue
        }
    }

    /// Tolerant decoder for legacy / unknown values.
    static func from(rawValue: String?) -> NoteColor {
        guard let raw = rawValue, let parsed = NoteColor(rawValue: raw) else {
            return .neutral
        }
        return parsed
    }
}
