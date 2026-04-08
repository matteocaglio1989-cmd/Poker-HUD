import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Phase 3 PR4: dropdown export menu shown in the Reports toolbar.
/// Lets the user save the currently-rendered player stats as CSV, JSON,
/// or a PDF snapshot of the table view.
///
/// PDF rendering closure is `@escaping () -> AnyView` so the caller can
/// pass an arbitrary SwiftUI view (today the player table; future PRs
/// could swap in the heat map or the situational view) without
/// `ExportMenu` having to know about any of them.
struct ExportMenu: View {
    let stats: [PlayerStats]
    let pdfSnapshotView: () -> AnyView
    let suggestedFilenameRoot: String

    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button("Export as CSV…", action: exportCSV)
            Button("Export as JSON…", action: exportJSON)
            Button("Export as PDF…", action: exportPDF)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .alert("Export Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Actions

    private func exportCSV() {
        let content = CSVExporter.playerStatsCSV(stats)
        save(
            data: Data(content.utf8),
            defaultName: "\(suggestedFilenameRoot).csv",
            contentType: .commaSeparatedText
        )
    }

    private func exportJSON() {
        do {
            let data = try JSONExporter.playerStatsJSON(stats)
            save(
                data: data,
                defaultName: "\(suggestedFilenameRoot).json",
                contentType: .json
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportPDF() {
        Task { @MainActor in
            do {
                let data = try PDFExporter.render(view: pdfSnapshotView())
                save(
                    data: data,
                    defaultName: "\(suggestedFilenameRoot).pdf",
                    contentType: .pdf
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - NSSavePanel wiring

    private func save(data: Data, defaultName: String, contentType: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.title = "Export Poker HUD Stats"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                Task { @MainActor in
                    errorMessage = "Couldn't save: \(error.localizedDescription)"
                }
            }
        }
    }
}
