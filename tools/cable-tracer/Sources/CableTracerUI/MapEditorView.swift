import CableTracerCore
import MapKit
import RpplCore
import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
typealias PlatformColor = NSColor
typealias PlatformTapGesture = NSClickGestureRecognizer
typealias PlatformGestureDelegate = NSGestureRecognizerDelegate
#else
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
typealias PlatformColor = UIColor
typealias PlatformTapGesture = UITapGestureRecognizer
typealias PlatformGestureDelegate = UIGestureRecognizerDelegate
#endif

/// Satellite map with the cables as draggable polylines. MKMapView rather than SwiftUI's `Map`
/// because point dragging and click-to-add need the platform gesture hooks.
struct MapEditorView: PlatformViewRepresentable {
    let model: EditorModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    private func makeMapView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        #if os(macOS)
        mapView.showsZoomControls = true
        #endif
        let tap = PlatformTapGesture(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)
        context.coordinator.mapView = mapView
        return mapView
    }

    private func update(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastRevision != model.revision || coordinator.lastSelectedCable != model.selectedCableIndex || coordinator.lastReference != model.reference {
            coordinator.lastRevision = model.revision
            coordinator.lastSelectedCable = model.selectedCableIndex
            coordinator.lastReference = model.reference
            coordinator.rebuild(on: mapView)
        }
        if coordinator.lastFocus != model.focusRequest {
            coordinator.lastFocus = model.focusRequest
            if let region = model.focusRegion { mapView.setRegion(region, animated: coordinator.lastFocus > 1) }
        }
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MKMapView { makeMapView(context: context) }
    func updateNSView(_ mapView: MKMapView, context: Context) { update(mapView, context: context) }
    #else
    func makeUIView(context: Context) -> MKMapView { makeMapView(context: context) }
    func updateUIView(_ mapView: MKMapView, context: Context) { update(mapView, context: context) }
    #endif

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, PlatformGestureDelegate {
        let model: EditorModel
        weak var mapView: MKMapView?
        var lastRevision = -1
        var lastSelectedCable: Int?
        var lastFocus = 0
        var lastReference: ReferencePoints?

        init(model: EditorModel) { self.model = model }

        func rebuild(on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations)
            guard let park = model.draft else { return }

            let parkPin = MKPointAnnotation()
            parkPin.coordinate = CLLocationCoordinate2D(latitude: park.location.lat, longitude: park.location.lon)
            parkPin.title = park.name
            mapView.addAnnotation(parkPin)

            for (cableIndex, cable) in (park.cables ?? []).enumerated() {
                guard let points = cable.points, !points.isEmpty else { continue }
                var coordinates = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                if cable.direction?.isLoop == true, points.count >= 3 { coordinates.append(coordinates[0]) }
                let line = CablePolyline(coordinates: coordinates, count: coordinates.count)
                line.cableIndex = cableIndex
                line.isSelected = cableIndex == model.selectedCableIndex
                mapView.addOverlay(line)
                if cableIndex == model.selectedCableIndex {
                    for (pointIndex, point) in points.enumerated() {
                        let annotation = PointAnnotation(cableIndex: cableIndex, pointIndex: pointIndex)
                        annotation.coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
                        annotation.isStart = point.start == true
                        annotation.title = "\(pointIndex + 1)"
                        mapView.addAnnotation(annotation)
                    }
                }
            }
            for reference in model.reference.points(for: park.id) {
                let annotation = ReferenceAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: reference.coordinate.lat, longitude: reference.coordinate.lon)
                annotation.title = reference.label
                mapView.addAnnotation(annotation)
            }
        }

        // MARK: Gestures

        #if os(macOS)
        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
            model.isAddingPoints
        }
        #else
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            model.isAddingPoints
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
        #endif

        @objc func handleTap(_ recognizer: PlatformTapGesture) {
            guard let mapView, model.isAddingPoints else { return }
            let point = recognizer.location(in: mapView)
            #if os(iOS)
            if mapView.hitTest(point, with: nil) is MKAnnotationView { return }
            #else
            if mapView.hitTest(point) is MKAnnotationView { return }
            #endif
            model.appendPoint(mapView.convert(point, toCoordinateFrom: mapView))
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? CablePolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.isSelected ? PlatformColor.systemYellow : PlatformColor.systemCyan.withAlphaComponent(0.8)
            renderer.lineWidth = line.isSelected ? 4 : 2.5
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            func marker(_ identifier: String) -> MKMarkerAnnotationView {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.displayPriority = .required
                return view
            }
            if let point = annotation as? PointAnnotation {
                let view = marker("point")
                view.isDraggable = true
                view.canShowCallout = false
                view.glyphText = point.title ?? ""
                view.markerTintColor = point.isStart ? .systemGreen : .systemYellow
                view.titleVisibility = .hidden
                return view
            }
            if annotation is ReferenceAnnotation {
                let view = marker("reference")
                view.markerTintColor = .systemPurple
                view.glyphImage = PlatformImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)
                view.canShowCallout = true
                return view
            }
            let view = marker("park")
            view.markerTintColor = .systemRed
            view.glyphImage = PlatformImage(systemSymbolName: "mappin", accessibilityDescription: nil)
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard newState == .ending || newState == .canceling, let point = view.annotation as? PointAnnotation else { return }
            view.dragState = .none
            if newState == .ending {
                model.movePoint(cable: point.cableIndex, point: point.pointIndex, to: point.coordinate)
            }
        }
    }
}

#if !os(macOS)
extension UIImage {
    convenience init?(systemSymbolName: String, accessibilityDescription: String?) {
        self.init(systemName: systemSymbolName)
    }
}
#endif

final class CablePolyline: MKPolyline {
    var cableIndex = 0
    var isSelected = false
}

final class PointAnnotation: MKPointAnnotation {
    let cableIndex: Int
    let pointIndex: Int
    var isStart = false

    init(cableIndex: Int, pointIndex: Int) {
        self.cableIndex = cableIndex
        self.pointIndex = pointIndex
        super.init()
    }
}

final class ReferenceAnnotation: MKPointAnnotation {}
