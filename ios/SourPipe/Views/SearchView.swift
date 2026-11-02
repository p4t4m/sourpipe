import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = ItemListModel()
    @State private var query = ""
    @State private var submitted = ""
    @State private var filter: String?
    @State private var suggestions: [String] = []
    @State private var correction: String?
    @State private var directRoute: Route?
    @State private var linkError: String?

    private var service: ServiceInfo? { store.currentService }
    private var showingResults: Bool { !submitted.isEmpty && query == submitted }

    var body: some View {
        List {
            if showingResults {
                results
            } else {
                suggestionRows
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.isLoading && model.items.isEmpty && showingResults { ProgressView() }
        }
        .navigationTitle("Search")
        .navigationDestination(isPresented: Binding(
            get: { directRoute != nil }, set: { if !$0 { directRoute = nil } }
        )) {
            if let directRoute { RouteScreen(route: directRoute) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { ServiceMenu() }
        }
        .searchable(text: $query, prompt: "Search or paste a link")
        .autocorrectionDisabled()
        .onSubmit(of: .search) { submit(query) }
        .task(id: query) { await loadSuggestions() }
        .onChange(of: store.library.settings.serviceId) { _ in
            filter = nil
            if !submitted.isEmpty { submit(submitted) }
        }
        .alert("Could not open the link", isPresented: Binding(
            get: { linkError != nil }, set: { if !$0 { linkError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linkError ?? "")
        }
    }

    @ViewBuilder private var suggestionRows: some View {
        let rows = query.isEmpty ? store.library.searches : suggestions
        ForEach(rows, id: \.self) { text in
            Button {
                query = text
                submit(text)
            } label: {
                Label(text, systemImage: query.isEmpty ? "clock" : "magnifyingglass")
                    .foregroundColor(.primary)
            }
        }
        .onDelete { offsets in
            if query.isEmpty { store.library.searches.remove(atOffsets: offsets) }
        }
    }

    @ViewBuilder private var results: some View {
        if let filters = service?.searchFilters, !filters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(filters, id: \.self) { candidate in
                        Button(Format.filterTitle(candidate)) {
                            filter = candidate
                            submit(submitted)
                        }
                        .buttonStyle(.bordered)
                        .tint(candidate == (filter ?? filters.first) ? Color.accentColor : Color.secondary)
                    }
                }
            }
            .listRowSeparator(.hidden)
        }
        if let correction {
            Button("Search for \"\(correction)\" instead") {
                query = correction
                submit(correction)
            }
        }
        if let error = model.error {
            StatusView(title: "Search failed", message: error) { submit(submitted) }
        } else if model.items.isEmpty && !model.isLoading {
            Text("No results").foregroundColor(.secondary)
        }
        ItemListSection(model: model)
    }

    private func loadSuggestions() async {
        let text = query
        guard !text.isEmpty, text != submitted, !isLink(text), let service else {
            suggestions = []
            return
        }
        // Debounce: this task is cancelled by the next keystroke.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        let found = (try? await Extractor.suggestions(serviceId: service.id, query: text)) ?? []
        if !Task.isCancelled { suggestions = found }
    }

    private func isLink(_ text: String) -> Bool {
        text.hasPrefix("http://") || text.hasPrefix("https://")
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let service else { return }
        if isLink(trimmed) {
            Task {
                do {
                    directRoute = try await LinkResolver.route(for: trimmed)
                } catch {
                    linkError = error.localizedDescription
                }
            }
            return
        }
        store.library.recordSearch(trimmed)
        submitted = trimmed
        query = trimmed
        correction = nil
        let chosen = filter
        Task {
            var suggestion: String?
            await model.load(serviceId: service.id,
                             source: .search(query: trimmed, filter: chosen)) {
                let page = try await Extractor.search(serviceId: service.id, query: trimmed,
                                                      filter: chosen)
                await MainActor.run { suggestion = page.suggestion }
                return page
            }
            if let suggestion, !suggestion.isEmpty, suggestion != trimmed {
                correction = suggestion
            }
        }
    }
}
