// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import SwiftUI

struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()
    @State private var entryBeingEdited: WeightEntry?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    SwiftUI.ProgressView("Loading history…")
                case .failed(let message):
                    ContentUnavailableView("Couldn’t load history", systemImage: "exclamationmark.triangle", description: Text(message))
                case .ready:
                    if viewModel.entries.isEmpty {
                        ContentUnavailableView("No entries", systemImage: "clock", description: Text("Your check-ins will appear here."))
                    } else {
                        List {
                            ForEach(viewModel.entries) { entry in
                                Button { entryBeingEdited = entry } label: { entryRow(entry) }
                                    .buttonStyle(.plain)
                                    .swipeActions {
                                        Button(role: .destructive) { viewModel.requestDelete(entry) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .refreshable { await viewModel.refresh() }
            .sheet(item: $entryBeingEdited) { entry in
                EntryEditorView(entry: entry)
            }
            .alert("Couldn’t update history", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func entryRow(_ entry: WeightEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year()).font(.headline)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(viewModel.unit.formatted(kilograms: entry.kilograms)).font(.headline).monospacedDigit()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
