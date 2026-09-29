import AppKit
import Observation
import SwiftUI

struct HistoryPanelView: View {
    @Bindable var viewModel: HistoryPanelViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var shouldScrollSelectionIntoView = true

    var body: some View {
        VStack(spacing: 11) {
            searchField

            HStack(alignment: .top, spacing: 22) {
                resultsColumn
                    .frame(width: 455)

                previewColumn
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 15)
        .frame(width: AppConstants.historyPanelWidth, height: AppConstants.historyPanelHeight)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 14)
        .preferredColorScheme(.light)
        .task(id: viewModel.presentationToken) {
            isSearchFocused = true
            shouldScrollSelectionIntoView = true
        }
    }

    private var searchField: some View {
        HStack {
            TextField("Search clipboard history", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.8))
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.confirmSelection()
                }
                .tint(Color.black.opacity(0.78))
        }
        .padding(.horizontal, 13)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.94))
                .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
        )
    }

    private var resultsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if viewModel.filteredItems.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                                HistoryRowView(
                                    item: item,
                                    isSelected: item.id == viewModel.selectedItem?.id
                                )
                                .id(item.id)
                                .overlay {
                                    HistoryRowMouseInteractionOverlay(
                                        onMouseDown: {
                                            shouldScrollSelectionIntoView = false
                                            viewModel.select(item)
                                        },
                                        onDoubleClickMouseUp: {
                                            viewModel.confirmSelection()
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.selectedItemID) { _, newValue in
                    guard let newValue else { return }
                    guard shouldScrollSelectionIntoView else {
                        shouldScrollSelectionIntoView = true
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 13) {
            Group {
                if let selectedItem = viewModel.selectedItem {
                    ScrollView {
                        Text(selectedItem.text)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.78))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No item selected")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.78))

                        Text("Copy text in any app to build your local clipboard history.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.48))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }

            Spacer(minLength: 0)

            if let selectedItem = viewModel.selectedItem {
                Text("Copied \(selectedItem.createdAt.formatted(date: .abbreviated, time: .shortened))  •  \(selectedItem.displaySourceAppName)")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.38))
            }
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No matches")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.8))

            Text("Try a shorter query or copy more text to build history.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.48))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.94, green: 0.945, blue: 0.94),
                Color(red: 0.86, green: 0.875, blue: 0.87)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct HistoryRowView: View {
    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.96) : Color.black.opacity(0.46))
                .frame(width: 22, height: 22)

            Text(primaryLine)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.74))
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .padding(.horizontal, 10)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    private var primaryLine: String {
        item.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color(red: 0.18, green: 0.55, blue: 0.57) : Color.clear)
    }
}

struct HistoryRowMouseInteractionOverlay: NSViewRepresentable {
    let onMouseDown: () -> Void
    let onDoubleClickMouseUp: () -> Void

    func makeNSView(context: Context) -> HistoryRowMouseInteractionView {
        let view = HistoryRowMouseInteractionView()
        view.onMouseDown = onMouseDown
        view.onDoubleClickMouseUp = onDoubleClickMouseUp
        return view
    }

    func updateNSView(_ nsView: HistoryRowMouseInteractionView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onDoubleClickMouseUp = onDoubleClickMouseUp
    }
}

final class HistoryRowMouseInteractionView: NSView {
    var onMouseDown: (() -> Void)?
    var onDoubleClickMouseUp: (() -> Void)?

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount >= 2 else { return }
        onDoubleClickMouseUp?()
    }
}
