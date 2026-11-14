import SwiftUI
import MapKit
import CoreLocation

func openGoogleMaps(_ destination: String) {
    guard let native = DeliveryDirections.googleMaps(address: destination), let web = DeliveryDirections.googleMaps(address: destination, native: false) else { return }
    UIApplication.shared.open(UIApplication.shared.canOpenURL(native) ? native : web)
}
struct ContactsView: View {
    var editable = false
    @EnvironmentObject private var store: DeliveryStore
    @State private var query = ""
    var body: some View {
        List {
            ForEach((store.ledger.contacts ?? []).filter { query.isEmpty || ($0.name + $0.phone + $0.aliases).localizedStandardContains(query) }) { contact in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(contact.name).font(.headline); Spacer(); Text(contact.role).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        if let tel = URL(string: "tel:" + contact.phone.filter { $0.isNumber || $0 == "+" }), !contact.phone.isEmpty { Link("Gọi", destination: tel).buttonStyle(SweepPill()) }
                        if let zalo = URL(string: contact.zalo), !contact.zalo.isEmpty { Link("Zalo", destination: zalo).buttonStyle(SweepPill()) }
                        if !contact.phone.isEmpty { Button { UIPasteboard.general.string = contact.phone } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Sao chép số điện thoại") }
                    }
                    if editable { NavigationLink("Sửa liên hệ") { ContactEditor(contact: contact) } }
                }.padding(.vertical, 6)
            }
            if (store.ledger.contacts ?? []).isEmpty { Text("Chưa có liên hệ. Thêm bán hàng hoặc tài xế để gọi nhanh.").foregroundStyle(.secondary) }
        }.navigationTitle("Liên hệ nhanh").searchable(text: $query, prompt: "Tên, số điện thoại")
            .toolbar { NavigationLink { ContactEditor() } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm liên hệ") }
    }
}
struct ContactEditor: View {
    var contact: DeliveryContact? = nil
    var initialName = ""
    var role = "Bán hàng"
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var zalo = ""
    @State private var aliases = ""
    @State private var kind = "Bán hàng"
    @State private var remove = false
    var body: some View {
        Form {
            Section {
                TextField("Tên", text: $name)
                TextField("Số điện thoại", text: $phone).keyboardType(.phonePad)
                TextField("Link hồ sơ / QR Zalo", text: $zalo).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Nhóm", selection: $kind) { ForEach(["Bán hàng", "Tài xế", "Khác"], id: \.self) { Text($0) } }
                TextField("Mã trên phiếu, ví dụ TEL", text: $aliases)
                Text("Nhiều mã cách nhau bằng dấu phẩy. Không dùng số khách để liên hệ bán hàng.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Lưu liên hệ") {
                let value = DeliveryContact(id: contact?.id ?? UUID(), name: name, phone: phone, zalo: zalo, aliases: aliases, role: kind)
                if store.change({ try $0.saveContact(value) }) { dismiss() }
            }.buttonStyle(SweepPill(selected: true))
            if let contact { Button("Xoá liên hệ", role: .destructive) { remove = true }
                .alert("Xoá \(contact.name)?", isPresented: $remove) {
                    Button("Xoá", role: .destructive) { if store.change({ $0.contacts?.removeAll { $0.id == contact.id } }) { dismiss() } }
                    Button("Huỷ", role: .cancel) {}
                }
            }
        }.navigationTitle(contact == nil ? "Thêm liên hệ" : "Sửa liên hệ").navigationBarTitleDisplayMode(.inline)
            .onAppear { name = contact?.name ?? initialName; phone = contact?.phone ?? ""; zalo = contact?.zalo ?? ""; aliases = contact?.aliases ?? ""; kind = contact?.role ?? role }
    }
}
struct PlacesView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var query = ""
    var body: some View {
        List {
            ForEach((store.ledger.places ?? []).filter { query.isEmpty || ($0.customer + $0.address + $0.phone).localizedStandardContains(query) }) { place in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(place.customer).font(.headline); Spacer(); Text(place.kind).font(.caption).foregroundStyle(.secondary) }
                    Text(place.address).font(.subheadline)
                    HStack {
                        Button("Google Maps") { openGoogleMaps(place.destination) }.buttonStyle(SweepPill())
                        NavigationLink { PlaceEditor(place: place) } label: { Image(systemName: "pencil") }.accessibilityLabel("Sửa vị trí")
                    }
                }.padding(.vertical, 5)
            }
            if (store.ledger.places ?? []).isEmpty { Text("Chưa lưu vị trí.").foregroundStyle(.secondary) }
        }.navigationTitle("Vị trí").searchable(text: $query, prompt: "Khách, chành, địa chỉ")
            .toolbar { NavigationLink { PlaceEditor() } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm vị trí") }
    }
}
@MainActor
final class DeliveryGPS: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var problem = ""
    private let manager = CLLocationManager()
    private var requested = false
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func request() {
        problem = ""; requested = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { problem = "Cho phép vị trí trong Cài đặt hoặc chọn trên bản đồ." }
        else { manager.requestLocation() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if requested && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { coordinate = locations.last?.coordinate }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { problem = error.localizedDescription }
}
struct PlaceEditor: View {
    var place: DeliveryPlace? = nil
    var order: DeliveryOrder? = nil
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gps = DeliveryGPS()
    @State private var customer = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var kind = "Khách hàng"
    @State private var lat = ""
    @State private var lon = ""
    @State private var map = false
    @State private var remove = false
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)
    @State private var position: MapCameraPosition = .automatic
    @State private var locating = false
    var body: some View {
        Form {
            Section {
                TextField("Tên khách / chành", text: $customer)
                TextField("Số điện thoại", text: $phone).keyboardType(.phonePad)
                TextField("Địa chỉ / chi nhánh", text: $address, axis: .vertical)
                Picker("Loại", selection: $kind) { Text("Khách hàng").tag("Khách hàng"); Text("Chành xe").tag("Chành xe") }
            }
            Section("Vị trí chính xác · tuỳ chọn") {
                Button("Lấy vị trí hiện tại") { gps.request() }
                Button("Chọn trên bản đồ") { prepareMap() }
                if locating { ProgressView() }
                if !gps.problem.isEmpty { Text(gps.problem).font(.caption).foregroundStyle(.red) }
                TextField("Vĩ độ", text: $lat).keyboardType(.numbersAndPunctuation)
                TextField("Kinh độ", text: $lon).keyboardType(.numbersAndPunctuation)
            }
            Button("Lưu vị trí") { save() }.buttonStyle(SweepPill(selected: true))
            if let place { Button("Xoá vị trí", role: .destructive) { remove = true }
                .alert("Xoá vị trí đã lưu?", isPresented: $remove) {
                    Button("Xoá", role: .destructive) { if store.change({ $0.places?.removeAll { $0.id == place.id } }) { dismiss() } }
                    Button("Huỷ", role: .cancel) {}
                }
            }
        }.navigationTitle("Lưu vị trí").navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheet { dismiss() } }
            .onAppear {
                customer = place?.customer ?? order?.customer ?? ""; phone = place?.phone ?? order?.phone ?? ""; address = place?.address ?? order?.address ?? ""
                kind = place?.kind ?? (order?.settlement?.route == .freight ? "Chành xe" : "Khách hàng")
                if kind == "Chành xe", place == nil { customer = ""; address = ""; phone = "" }
                lat = place?.latitude.map { String($0) } ?? ""; lon = place?.longitude.map { String($0) } ?? ""
            }
            .onChange(of: gps.coordinate?.latitude) { _, _ in if let c = gps.coordinate { lat = String(c.latitude); lon = String(c.longitude) } }
            .sheet(isPresented: $map) {
                NavigationStack {
                    Map(position: $position).overlay { Image(systemName: "mappin.circle.fill").font(.largeTitle).foregroundStyle(.red).allowsHitTesting(false) }
                        .onMapCameraChange(frequency: .onEnd) { context in mapCenter = context.region.center }
                        .safeAreaInset(edge: .bottom) { Button("Dùng vị trí ghim") { lat = String(mapCenter.latitude); lon = String(mapCenter.longitude); map = false }.buttonStyle(SweepPill(selected: true)).padding().background(.bar) }
                        .navigationTitle("Kéo bản đồ đến vị trí").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { map = false } } }
                }
            }
    }
    private func prepareMap() {
        if let a = Double(lat), let b = Double(lon) { mapCenter = CLLocationCoordinate2D(latitude: a, longitude: b); showMap(); return }
        guard !address.isEmpty else { showMap(); return }
        locating = true
        Task {
            defer { locating = false }
            do {
                let request = MKLocalSearch.Request(); request.naturalLanguageQuery = address
                let results = try await MKLocalSearch(request: request).start()
                if let item = results.mapItems.first { mapCenter = item.placemark.coordinate }
                showMap()
            } catch { store.message = "Chưa tìm được địa chỉ. Sếp có thể kéo bản đồ để chọn."; showMap() }
        }
    }
    private func showMap() { position = .region(MKCoordinateRegion(center: mapCenter, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012))); map = true }
    private func save() {
        if (!lat.isEmpty && Double(lat) == nil) || (!lon.isEmpty && Double(lon) == nil) { store.message = "Tọa độ phải là số, dùng dấu chấm thập phân."; return }
        let value = DeliveryPlace(id: place?.id ?? UUID(), customer: customer, phone: phone, address: address, kind: kind, latitude: Double(lat), longitude: Double(lon))
        if store.change({ try $0.savePlace(value) }) { dismiss() }
    }
}
