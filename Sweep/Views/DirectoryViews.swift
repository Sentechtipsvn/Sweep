import SwiftUI
import MapKit
import CoreLocation
import ContactsUI
import PhotosUI
import Vision

func openGoogleMaps(_ destination: String) {
    guard let native = DeliveryDirections.googleMaps(address: destination), let web = DeliveryDirections.googleMaps(address: destination, native: false) else { return }
    UIApplication.shared.open(UIApplication.shared.canOpenURL(native) ? native : web)
}
private struct ContactDraft: Identifiable {
    var id = UUID()
    var contact: DeliveryContact?
    var name = ""
    var phone = ""
}
struct ContactsView: View {
    var editable = false
    var seller: String? = nil
    @EnvironmentObject private var store: DeliveryStore
    @State private var query = ""
    @State private var draft: ContactDraft?
    @State private var picker = false
    @State private var picked: ContactDraft?
    private var contacts: [DeliveryContact] {
        let all = store.ledger.contacts ?? []
        guard let seller else { return all }
        let matches = all.filter { $0.matches(seller) }
        return matches.isEmpty ? all.filter { $0.role == "Bán hàng" } : matches
    }
    var body: some View {
        List {
            if seller != nil { Text("Chọn đúng người bán hàng trên phiếu để liên hệ.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(contacts.filter { query.isEmpty || ($0.name + $0.phone + $0.aliases).localizedStandardContains(query) }) { contact in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(contact.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(contact.role).font(.caption).foregroundStyle(.secondary)
                            Button { draft = ContactDraft(contact: contact) } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("Sửa " + contact.name)
                        }
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !contact.phone.isEmpty { Text(contact.phone).font(.subheadline).textSelection(.enabled) }
                            if let zalo = ContactLinks.zalo(contact.zalo) { Link("Zalo", destination: zalo).buttonStyle(SweepCompactPill()) }
                        }
                        Spacer(minLength: 8)
                        SweepCallButton(phone: contact.phone)
                    }
                }.padding(.vertical, 8)
                .contextMenu {
                    if !contact.phone.isEmpty { Button("Sao chép số", systemImage: "doc.on.doc") { UIPasteboard.general.string = contact.phone } }
                    Button("Sửa liên hệ", systemImage: "pencil") { draft = ContactDraft(contact: contact) }
                }
            }
            if contacts.isEmpty { Text("Chưa có liên hệ. Chọn từ Danh bạ hoặc thêm thủ công.").foregroundStyle(.secondary) }
        }.navigationTitle("Liên hệ nhanh").searchable(text: $query, prompt: "Tên, số điện thoại")
            .toolbar {
                Menu {
                    Button("Chọn từ Danh bạ", systemImage: "person.crop.circle.badge.plus") { picker = true }
                    Button("Nhập thủ công", systemImage: "square.and.pencil") { draft = ContactDraft() }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm liên hệ")
            }
            .sheet(isPresented: $picker, onDismiss: { if let picked { draft = picked; self.picked = nil } }) {
                SweepContactPicker(select: { name, phone in picked = ContactDraft(name: name, phone: phone); picker = false }, cancel: { picker = false })
            }
            .sheet(item: $draft) { value in
                NavigationStack { ContactEditor(contact: value.contact, initialName: value.name, initialPhone: value.phone) }
            }
    }
}
struct ContactEditor: View {
    var contact: DeliveryContact? = nil
    var initialName = ""
    var initialPhone = ""
    var role = "Bán hàng"
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var zalo = ""
    @State private var aliases = ""
    @State private var kind = "Bán hàng"
    @State private var remove = false
    @State private var duplicate: DeliveryContact?
    @State private var confirmDuplicate = false
    @State private var qr: PhotosPickerItem?
    @State private var qrCandidate = ""
    @State private var confirmQR = false
    @State private var readingQR = false
    var body: some View {
        Form {
            Section {
                TextField("Tên", text: $name)
                TextField("Số điện thoại", text: $phone).keyboardType(.phonePad)
                Picker("Nhóm", selection: $kind) { ForEach(["Bán hàng", "Tài xế", "Chành xe", "Khác"], id: \.self) { Text($0) } }
                TextField("Mã trên phiếu, ví dụ TEL", text: $aliases)
                Text("Nhiều mã cách nhau bằng dấu phẩy. Không dùng số khách để liên hệ bán hàng.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("Zalo · không bắt buộc") {
                    TextField("Dán liên kết Zalo nếu có", text: $zalo).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    PhotosPicker(selection: $qr, matching: .images, preferredItemEncoding: .compatible) { Label("Đọc QR Zalo từ ảnh", systemImage: "qrcode") }.disabled(readingQR)
                    if readingQR { ProgressView("Đang đọc QR…") }
                    if !phone.isEmpty { Button("Sao chép số để tìm trong Zalo") { UIPasteboard.general.string = phone } }
                    Text("Không cần biết link để lưu liên hệ. QR sẽ được kiểm tra và cho xem trước; Sweep không tự nhắn tin.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Lưu liên hệ") { saveCheckingDuplicate() }.buttonStyle(SweepPill(selected: true))
            if let contact { Button("Xoá liên hệ", role: .destructive) { remove = true }
                .alert("Xoá \(contact.name)?", isPresented: $remove) {
                    Button("Xoá", role: .destructive) { if store.change({ $0.contacts?.removeAll { $0.id == contact.id } }) { dismiss() } }
                    Button("Huỷ", role: .cancel) {}
                }
            }
        }.navigationTitle(contact == nil ? "Thêm liên hệ" : "Sửa liên hệ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Xong") { dismiss() } } }
            .onAppear { name = contact?.name ?? initialName; phone = contact?.phone ?? initialPhone; zalo = contact?.zalo ?? ""; aliases = contact?.aliases ?? ""; kind = contact?.role ?? role }
            .alert("Số này đã có trong Sweep", isPresented: $confirmDuplicate) {
                Button("Cập nhật liên hệ đã có") { persist(replacing: duplicate) }
                Button("Giữ thành người riêng") { persist(replacing: nil) }
                Button("Hủy", role: .cancel) {}
            } message: { Text(duplicate?.name ?? "") }
            .alert("Dùng liên kết QR này?", isPresented: $confirmQR) {
                Button("Dùng liên kết") { zalo = qrCandidate }
                Button("Hủy", role: .cancel) {}
            } message: { Text(qrCandidate) }
            .onChange(of: qr) { _, item in
                guard let item else { return }
                Task {
                    readingQR = true; defer { readingQR = false; qr = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), data.count <= 80 * 1024 * 1024 else { throw DeliveryError.invalid("Chưa tải được ảnh QR hoặc ảnh quá lớn.") }
                        let values = try await Task.detached(priority: .userInitiated) {
                            let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
                            try VNImageRequestHandler(data: data).perform([request])
                            return (request.results ?? []).compactMap(\.payloadStringValue).filter { ContactLinks.zalo($0) != nil }
                        }.value
                        guard Set(values).count == 1, let first = values.first else { throw DeliveryError.invalid("Ảnh cần có một QR liên kết Zalo hợp lệ. Sếp chọn lại ảnh hoặc dán link.") }
                        qrCandidate = first; confirmQR = true
                    } catch { store.message = error.localizedDescription }
                }
            }
    }
    private func saveCheckingDuplicate() {
        let key = ContactLinks.phoneKey(phone)
        duplicate = (store.ledger.contacts ?? []).first { $0.id != contact?.id && !key.isEmpty && ContactLinks.phoneKey($0.phone) == key }
        if duplicate != nil { confirmDuplicate = true } else { persist(replacing: nil) }
    }
    private func persist(replacing other: DeliveryContact?) {
        let value = DeliveryContact(id: other?.id ?? contact?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone.trimmingCharacters(in: .whitespacesAndNewlines), zalo: other != nil && zalo.isEmpty ? other!.zalo : zalo.trimmingCharacters(in: .whitespacesAndNewlines), aliases: other != nil && aliases.isEmpty ? other!.aliases : aliases, role: kind)
        if store.change({ try $0.saveContact(value) }) { dismiss() }
    }
}
private struct SweepContactPicker: UIViewControllerRepresentable {
    let select: (String, String) -> Void
    let cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(select: select, cancel: cancel) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController(); picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
        return picker
    }
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let select: (String, String) -> Void
        let cancel: () -> Void
        init(select: @escaping (String, String) -> Void, cancel: @escaping () -> Void) { self.select = select; self.cancel = cancel }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { cancel() }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            if let phone = contact.phoneNumbers.first?.value.stringValue { select(CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName, phone) }
        }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
            if let phone = property.value as? CNPhoneNumber { select(CNContactFormatter.string(from: property.contact, style: .fullName) ?? property.contact.givenName, phone.stringValue) }
        }
    }
}
struct PlacesView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var query = ""
    @State private var editing: DeliveryPlace?
    var body: some View {
        List {
            ForEach((store.ledger.places ?? []).filter { query.isEmpty || ($0.customer + $0.address + $0.phone).localizedStandardContains(query) }) { place in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(place.customer).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(place.kind).font(.caption).foregroundStyle(.secondary)
                            Button { editing = place } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("Sửa " + place.customer)
                        }
                    }
                    Text(place.address).font(.subheadline)
                    if !place.phone.isEmpty { Text(place.phone).font(.subheadline).textSelection(.enabled) }
                    HStack {
                        Button("Google Maps") { openGoogleMaps(place.destination) }.buttonStyle(SweepCompactPill())
                        Spacer(minLength: 8)
                        SweepCallButton(phone: place.phone)
                    }
                }.padding(.vertical, 8)
            }
            if (store.ledger.places ?? []).isEmpty { Text("Chưa lưu vị trí.").foregroundStyle(.secondary) }
        }.navigationTitle("Vị trí").searchable(text: $query, prompt: "Khách, chành, địa chỉ")
            .toolbar { NavigationLink { PlaceEditor() } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm vị trí") }
            .sheet(item: $editing) { place in NavigationStack { PlaceEditor(place: place).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Xong") { editing = nil } } } } }
    }
}
@MainActor
final class DeliveryGPS: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var problem = ""
    @Published var accuracy: Double?
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
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) < 60 else {
            problem = "Chưa nhận được vị trí mới. Sếp thử lại hoặc chọn trên bản đồ."; return
        }
        accuracy = location.horizontalAccuracy; coordinate = location.coordinate
    }
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
                if let accuracy = gps.accuracy { Text("Độ chính xác GPS khoảng \(Int(accuracy.rounded())) m. Kiểm tra lại điểm trước khi lưu.").font(.caption).foregroundStyle(.secondary) }
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
        if store.change({ ledger in
            try ledger.savePlace(value)
            if let order, order.settlement?.route == .freight, kind == "Chành xe",
               let i = ledger.orders.firstIndex(where: { $0.id == order.id }) {
                ledger.orders[i].freightPlaceID = ledger.places?.first(where: { $0.key == value.key })?.id
            }
        }) { dismiss() }
    }
}
