import SwiftUI
import WidgetKit

@main
struct RpplWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ParkHoursWidget()
        TopParksWidget()
        LastSessionWidget()
    }
}
