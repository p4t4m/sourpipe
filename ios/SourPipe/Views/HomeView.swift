import SwiftUI

struct ServiceMenu: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Menu {
            Picker("Service", selection: $store.library.settings.serviceId) {
                ForEach(store.services) { service in
                    Text(service.name).tag(service.id)
                }
            }
        } label: {
            Label(store.currentService?.name ?? "Service", systemImage: "globe")
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = ItemListModel()
    @State private var kiosk: String?

    private var service: ServiceInfo? { store.currentService }
    private var selectedKiosk: String? { kiosk ?? service?.defaultKiosk }

    var body: some View {
        List {
            if let kiosks = service?.kiosks, kiosks.count > 1 {
                Picker("Section", selection: Binding(
                    get: { selectedKiosk ?? "" },
                    set: { kiosk = $0 }
                )) {
                    ForEach(kiosks, id: \.self) { Text(Format.kioskTitle($0)).tag($0) }
                }
            }
            if let error = model.error {
                StatusView(title: "Could not load this section", message: error) {
                    Task { await load() }
                }
            }
            ItemListSection(model: model)
        }
        .listStyle(.plain)
        .overlay {
            if model.isLoading && model.items.isEmpty { ProgressView() }
        }
        .navigationTitle(selectedKiosk.map(Format.kioskTitle) ?? "Home")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { ServiceMenu() }
        }
        .refreshable { await load() }
        .task(id: "\(store.library.settings.serviceId)/\(selectedKiosk ?? "")") { await load() }
        .onChange(of: store.library.settings.serviceId) { _ in kiosk = nil }
    }

    private func load() async {
        guard let service, let id = selectedKiosk else { return }
        await model.load(serviceId: service.id, source: nil) {
            try await Extractor.kiosk(serviceId: service.id, id: id)
        }
    }
}
