import SwiftUI
import MapKit

private final class MapsRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(MapPin.isMapLink) == true ? request : nil)
    }
}

struct PlaceMapPicker: View {
    let initial: CLLocationCoordinate2D?
    let address: String
    let select: (CLLocationCoordinate2D) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gps = DeliveryGPS()
    @State private var position: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var message = ""
    @State private var satellite = false
    @State private var searching = false
    @State private var request: Task<Void, Never>?
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("Tên tiệm, địa chỉ, tọa độ hoặc link Google Maps", text: $query)
                        .focused($editing).submitLabel(.search).onSubmit { search() }
                        .textFieldStyle(.roundedBorder)
                    Button { search() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Tìm vị trí")
                }.padding(8)
                if searching { ProgressView().padding(4) }
                if !message.isEmpty { Text(message).font(.caption).padding(.horizontal) }
                if !results.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                                Button {
                                    move(item.placemark.coordinate); query = item.name ?? query; results = []; editing = false
                                } label: {
                                    VStack(alignment: .leading) { Text(item.name ?? "Vị trí"); Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary) }
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }.frame(maxHeight: 160)
                }
                Map(position: $position)
                    .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .all))
                    .overlay { Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.red).shadow(color: .white, radius: 1).allowsHitTesting(false) }
                    .onMapCameraChange(frequency: .continuous) { center = $0.region.center }
                HStack {
                    Button(satellite ? "Đường phố" : "Vệ tinh") { satellite.toggle() }
                    Button { gps.request() } label: { Image(systemName: "location.fill") }.accessibilityLabel("Vị trí hiện tại")
                    if let url = MapPin.googleSearch(query.isEmpty ? address : query), !query.isEmpty || !address.isEmpty {
                        Link("Google Maps", destination: url)
                    }
                }.buttonStyle(SweepPill(expanded: false)).padding(.top, 6)
                Button("Dùng vị trí ghim") { if let center { select(center); dismiss() } }
                    .buttonStyle(SweepPill()).disabled(center == nil).padding(8)
            }
            .navigationTitle("Tìm và ghim vị trí").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } } }
            .onAppear {
                query = address
                move(initial ?? CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009))
                if initial == nil && !query.isEmpty { search() }
            }
            .onChange(of: gps.coordinate?.latitude) { _, _ in if let point = gps.coordinate { move(point); results = [] } }
            .onChange(of: gps.problem) { _, error in message = error }
            .onChange(of: query) { _, _ in if editing { request?.cancel(); searching = false; results = []; message = "" } }
            .onDisappear { request?.cancel() }
        }
    }
    private func move(_ point: CLLocationCoordinate2D) {
        center = point
        position = .region(.init(center: point, span: .init(latitudeDelta: 0.008, longitudeDelta: 0.008)))
    }
    private func search() {
        request?.cancel(); editing = false; results = []; message = ""
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { searching = false; return }
        request = Task { @MainActor in
            searching = true
            defer { if !Task.isCancelled { searching = false } }
            do {
                if let pin = MapPin.read(text) { move(.init(latitude: pin.latitude, longitude: pin.longitude)); return }
                if let url = URL(string: text), url.scheme != nil {
                    if MapPin.isMapLink(url), ["maps.app.goo.gl", "goo.gl"].contains(url.host?.lowercased() ?? "") {
                        let session = URLSession(configuration: .ephemeral, delegate: MapsRedirects(), delegateQueue: nil)
                        defer { session.invalidateAndCancel() }
                        var lookup = URLRequest(url: url, timeoutInterval: 10); lookup.httpMethod = "HEAD"
                        let (_, response) = try await session.data(for: lookup)
                        try Task.checkCancellation()
                        if let expanded = response.url, let pin = MapPin.read(expanded.absoluteString) {
                            move(.init(latitude: pin.latitude, longitude: pin.longitude)); return
                        }
                    }
                    message = "Link chưa có tọa độ ghim. Trong Google Maps, nhấn giữ điểm giao rồi sao chép cặp tọa độ."; return
                }
                let lookup = MKLocalSearch.Request()
                lookup.naturalLanguageQuery = text
                if let center { lookup.region = .init(center: center, latitudinalMeters: 25000, longitudinalMeters: 25000) }
                let matches = try await MKLocalSearch(request: lookup).start().mapItems
                try Task.checkCancellation()
                results = Array(matches.prefix(8))
                if results.isEmpty { message = "Chưa thấy kết quả. Thử Google Maps hoặc dán tọa độ của khách." }
            } catch {
                if !Task.isCancelled { message = "Chưa tra được vị trí. Sếp có thể dán tọa độ hoặc chọn trên bản đồ." }
            }
        }
    }
}
