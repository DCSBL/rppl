import XCTest

extension XCTestCase {
    /// Attaches a screenshot of the whole screen as `name`, upright, for the shots that run in landscape.
    ///
    /// `XCUIApplication.screenshot()` is wrong there on the Xcode 26 simulators: it rotates the landscape
    /// content as if the window were portrait and crops it to the screen's height, so the PNG shows the left
    /// window-height-wide column of the app (the list column, on a wide iPhone) rotated 90° and the rest
    /// black. `XCUIScreen.main.screenshot()` captures the framebuffer itself. The image is drawn once more so
    /// the PNG pixels are upright whatever orientation metadata the capture carries, and a capture that
    /// still comes back portrait-shaped while the device is in landscape is rotated into landscape.
    /// Logs the pixel and window sizes, so a CI log shows what was captured.
    func attachScreenshot(named name: String, of app: XCUIApplication) {
        let orientation = XCUIDevice.shared.orientation
        let captured = XCUIScreen.main.screenshot().image
        let image = Self.upright(captured, deviceOrientation: orientation)
        let window = app.windows.firstMatch.frame.size
        let pixels = "\(Int(image.size.width * image.scale))x\(Int(image.size.height * image.scale))"
        print("screenshot \(name): \(pixels) px, captured \(Int(captured.size.width))x\(Int(captured.size.height)) pt " +
              "(orientation \(captured.imageOrientation.rawValue)), window \(Int(window.width))x\(Int(window.height)) pt, " +
              "device \(orientation.rawValue)")
        let attachment = XCTAttachment(image: image, quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// `image` with its orientation metadata baked into the pixels, and turned by a quarter when the device is
    /// in landscape but the capture is portrait-shaped (a raw portrait framebuffer of a landscape screen).
    private static func upright(_ image: UIImage, deviceOrientation: UIDeviceOrientation) -> UIImage {
        let isPortraitShaped = image.size.height > image.size.width
        let quarterTurns: CGFloat
        switch deviceOrientation {
        case .landscapeLeft where isPortraitShaped: quarterTurns = -1 // content lies rotated clockwise: turn it back
        case .landscapeRight where isPortraitShaped: quarterTurns = 1
        default: quarterTurns = 0
        }
        let size = quarterTurns == 0 ? image.size : CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: quarterTurns * .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
        }
    }
}
