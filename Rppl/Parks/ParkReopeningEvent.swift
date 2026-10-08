import CoreLocation
import EventKit
import EventKitUI
import RpplCore
import SwiftUI

/// Native "add event" sheet. `EKEventEditViewController` runs out of process, so adding needs no
/// calendar permission (and we never read the calendar).
struct ParkReopeningEventSheet: UIViewControllerRepresentable {
    let park: Park
    let opening: ParkNextOpening
    let bookingURL: URL?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = String(localized: "\(park.name) opened")
        event.startDate = opening.start
        event.endDate = opening.end
        event.timeZone = park.resolvedTimeZone
        let location = EKStructuredLocation(title: park.address ?? park.name)
        location.geoLocation = CLLocation(latitude: park.location.lat, longitude: park.location.lon)
        event.structuredLocation = location
        event.url = bookingURL

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
