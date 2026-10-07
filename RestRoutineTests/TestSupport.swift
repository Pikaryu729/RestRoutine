import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import RestRoutine

enum TestSupport {
    static let chicago = TimeZone(identifier: "America/Chicago")!

    static func calendar(_ zone: TimeZone = chicago) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, zone: TimeZone = chicago) -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Contexts crash if their container is released, so tests keep them alive here.
    @MainActor private static var retained: [ModelContainer] = []

    @MainActor
    static func inMemoryStore() throws -> (ModelContainer, JournalStore) {
        let container = try Persistence.makeContainer(inMemory: true)
        retained.append(container)
        return (container, JournalStore(context: container.mainContext))
    }

    /// A fresh preferences store, so tests never touch the app's own settings.
    static func defaults(_ theme: ThemeSettings? = nil) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        if let theme { defaults.themeSettings = theme }
        return defaults
    }

    static func settle(_ seconds: TimeInterval = 0.8) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Hosts a view in a window of a fixed size. The window is rendered
    /// without being ordered on screen, so nothing appears on the desktop.
    @MainActor
    static func window<V: View>(_ view: V, size: CGSize, title: String = "Rest & Routine",
                                dark: Bool = false) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: 120, y: 120), size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        settle()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return window
    }

    /// The window's current drawing, titlebar included.
    @MainActor
    static func image(of window: NSWindow) throws -> CGImage {
        settle(0.3)
        let view = window.contentView!.superview ?? window.contentView!
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        if let layer = view.layer {
            // Rendering the layer tree also draws labels that cacheDisplay leaves out.
            let scale = window.backingScaleFactor
            let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
            let context = try XCTUnwrap(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            if view.isFlipped {
                context.translateBy(x: 0, y: view.bounds.height)
                context.scaleBy(x: 1, y: -1)
            }
            layer.render(in: context)
            return try XCTUnwrap(context.makeImage())
        }
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try XCTUnwrap(rep.cgImage)
    }

    /// The sRGB color drawn at a point measured in points from the window's top-left corner.
    @MainActor
    static func color(in window: NSWindow, at point: CGPoint) throws -> (red: Int, green: Int, blue: Int) {
        let image = try image(of: window)
        let scale = CGFloat(image.width) / (window.contentView!.superview ?? window.contentView!).bounds.width
        // The image is drawn in sRGB, so its raw pixel values are sRGB values.
        let rep = NSBitmapImageRep(cgImage: image)
        var pixel = [Int](repeating: 0, count: 4)
        rep.getPixel(&pixel, atX: Int(point.x * scale), y: Int(point.y * scale))
        return (pixel[0], pixel[1], pixel[2])
    }

    static func rgb(_ color: Color) -> (red: Int, green: Int, blue: Int) {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (Int((ns.redComponent * 255).rounded()), Int((ns.greenComponent * 255).rounded()),
                Int((ns.blueComponent * 255).rounded()))
    }

    static func assertColor(_ actual: (red: Int, green: Int, blue: Int), _ expected: Color, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let e = rgb(expected)
        let close = abs(actual.red - e.red) <= 3 && abs(actual.green - e.green) <= 3 && abs(actual.blue - e.blue) <= 3
        XCTAssertTrue(close, "\(message): drew \(actual), expected \(e)", file: file, line: line)
    }

    /// Every SwiftUI accessibility element in a window, as assistive apps see them.
    /// SwiftUI builds its elements on request, so this asks for the element
    /// under points across the window and then walks the tree from each one.
    @MainActor
    static func accessibilityElements(in window: NSWindow) -> [AccessibleElement] {
        let root = window.contentView!
        var seen = Set<ObjectIdentifier>()
        var found: [AccessibleElement] = []
        func visit(_ element: AccessibleElement) {
            guard seen.insert(ObjectIdentifier(element)).inserted else { return }
            found.append(element)
            (element.accessibilityChildren() ?? []).compactMap(swiftUIElement).forEach(visit)
        }
        for x in stride(from: 4.0, to: root.bounds.width, by: 12) {
            for y in stride(from: 4.0, to: root.bounds.height, by: 12) {
                let point = window.convertPoint(toScreen: root.convert(NSPoint(x: x, y: y), to: nil))
                var hit = root.accessibilityHitTest(point)
                // A scroll view answers for itself; its content answers for what it shows.
                if let scrollView = hit as? NSScrollView { hit = scrollView.documentView?.accessibilityHitTest(point) }
                guard var element = swiftUIElement(hit) else { continue }
                // Climb to the outermost SwiftUI element, then walk down from it.
                while let parent = swiftUIElement(element.accessibilityParent()) { element = parent }
                visit(element)
            }
        }
        return found
    }

    /// SwiftUI's own elements answer the accessibility messages without
    /// declaring the Swift protocol, so tests reach them through this one.
    private static func swiftUIElement(_ object: Any?) -> AccessibleElement? {
        guard let object = object as? NSObject, !(object is NSView),
              String(describing: type(of: object)).contains("AccessibilityNode") else { return nil }
        return unsafeBitCast(object, to: AccessibleElement.self)
    }

    @MainActor
    static func buttonLabels(in window: NSWindow) -> [String] {
        accessibilityElements(in: window).filter { $0.accessibilityRole() == .button }.compactMap { $0.accessibilityLabel() }
    }

    /// Presses the first button with the given label, as VoiceOver or a click would.
    @MainActor
    static func press(_ label: String, in window: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        guard let button = accessibilityElements(in: window).first(where: {
            $0.accessibilityRole() == .button && $0.accessibilityLabel() == label
        }) else {
            XCTFail("No button labeled \(label); buttons: \(buttonLabels(in: window))", file: file, line: line)
            return
        }
        XCTAssertTrue(button.accessibilityPerformPress(), "pressing \(label)", file: file, line: line)
        settle(0.5)
    }

    /// Opens the pop-up button with the given label and chooses an item from
    /// its menu, as a person would with the pointer or VoiceOver.
    @MainActor
    static func choose(_ item: String, from label: String, in window: NSWindow,
                       file: StaticString = #filePath, line: UInt = #line) {
        guard let popUp = accessibilityElements(in: window).first(where: {
            $0.accessibilityRole() == .popUpButton && $0.accessibilityLabel() == label
        }) else {
            XCTFail("No pop-up button labeled \(label)", file: file, line: line)
            return
        }
        var chosen = false
        var opened: NSMenu?
        let observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            opened = note.object as? NSMenu
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        // The menu tracks in its own run loop; pick the item once it is open.
        let timer = Timer(timeInterval: 0.3, repeats: true) { timer in
            guard let menu = opened else { return }
            let index = menu.indexOfItem(withTitle: item)
            if index >= 0 {
                menu.performActionForItem(at: index)
                chosen = true
            }
            menu.cancelTrackingWithoutAnimation()
            timer.invalidate()
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        _ = popUp.accessibilityPerformPress()
        settle(0.5)
        XCTAssertTrue(chosen, "\(label) offers \(item)", file: file, line: line)
    }
}

/// The accessibility messages the tests send to SwiftUI's elements.
@objc protocol AccessibleElement {
    func accessibilityLabel() -> String?
    func accessibilityRole() -> NSAccessibility.Role?
    func accessibilityChildren() -> [Any]?
    func accessibilityParent() -> Any?
    func accessibilityPerformPress() -> Bool
}
