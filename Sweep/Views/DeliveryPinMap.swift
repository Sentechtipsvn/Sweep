import MapKit
import SwiftUI

enum DeliveryMapLayer: String, CaseIterable {
    case street = "OpenStreetMap", apple = "Apple Maps", satellite = "Vệ tinh"
}

@MainActor final class DeliveryPinCamera: ObservableObject {
    weak var map: MKMapView?
    private(set) var target = CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)
    @Published var hasSelection = false
    var center: CLLocationCoordinate2D { map?.centerCoordinate ?? target }
    func move(_ point: CLLocationCoordinate2D) {
        target = point
        map?.setRegion(region, animated: false)
        hasSelection = true
    }
    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: target, latitudinalMeters: 950, longitudinalMeters: 950)
    }
}

private final class StreetTiles: MKTileOverlay {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 48 << 20, diskPath: "SendeliStreetTiles")
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        var request = URLRequest(url: url(forTilePath: path))
        request.setValue("Sendeli/0.9 (+https://github.com/Sentechtipsvn/Sweep)", forHTTPHeaderField: "User-Agent")
        Self.session.dataTask(with: request) { data, response, error in
            if let error { result(nil, error); return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                result(nil, URLError(.badServerResponse)); return
            }
            result(data, nil)
        }.resume()
    }
}

struct DeliveryPinMap: UIViewRepresentable {
    let camera: DeliveryPinCamera
    let layer: DeliveryMapLayer
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        camera.map = map
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.setRegion(camera.region, animated: false)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator; pan.cancelsTouchesInView = false
        map.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pick(_:)))
        tap.delegate = context.coordinator; tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.layer != layer else { return }
        coordinator.layer = layer
        map.removeOverlays(map.overlays)
        map.mapType = layer == .satellite ? .hybrid : .standard
        if layer == .street {
            let tiles = StreetTiles(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
            tiles.minimumZ = 0; tiles.maximumZ = 19; tiles.canReplaceMapContent = true
            map.addOverlay(tiles, level: .aboveLabels)
        }
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let camera: DeliveryPinCamera
        var layer: DeliveryMapLayer?
        init(camera: DeliveryPinCamera) { self.camera = camera }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .changed && !camera.hasSelection { camera.hasSelection = true }
        }
        @objc func pick(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = camera.map else { return }
            map.setCenter(map.convert(gesture.location(in: map), toCoordinateFrom: map), animated: false)
            camera.hasSelection = true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tiles) }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
