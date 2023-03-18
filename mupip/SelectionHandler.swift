import Carbon.HIToolbox
import OSLog
import ScreenCaptureKit
import SwiftUI

@MainActor
// Handler for selecteding content to be recorded
class SelectionHandler {
    private var capture: Capture = .display(nil)
    private var selecting: Bool = false {
        didSet {
            if selecting {
                // change cursor to crosshair while selecting
                DispatchQueue.main.async {
                    NSCursor.crosshair.push()
                }
            } else {
                NSCursor.pop()
                selectOrigin = nil
                selection?.close()
                currentSelectedWindow = nil

                for overlay in selectionOverlays {
                    overlay.close()
                }
                selectionOverlays = []
            }
        }
    }

    private var eventMonitor: Any?
    private var selection: NSWindow?
    private var selectOrigin: CGPoint?
    private var onSelect: ((ScreenRecorder, CGSize) -> Void)?
    private var availableShareableContent: SCShareableContent?
    private var selectionOverlays: [NSWindow] = []
    private var currentSelectedWindow: (frame: NSRect, window: SCWindow)?
    private let logger = Logger()

    init() {
        Task {
            self.availableShareableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            await self.start()
        }
    }

    func start() async {
        // Handle selection
        do {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [NSEvent.EventTypeMask.keyDown, NSEvent.EventTypeMask.mouseMoved, NSEvent.EventTypeMask.leftMouseDown, NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseDragged, NSEvent.EventTypeMask.leftMouseUp],
                handler: { [self] (event: NSEvent) in
                    if !self.selecting {
                        return event
                    }

                    // get current display based on mouse position
                    let mouseLocation = NSEvent.mouseLocation
                    let availableDisplays = self.availableShareableContent!.displays
                    let displayWithMouse = (availableDisplays.first { self.mouseOnDisplay(mouseLocation: mouseLocation, frame: $0.frame) })
                    var currentScreen: NSScreen?
                    for screen in NSScreen.screens {
                        if screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? UInt32 == displayWithMouse?.displayID {
                            currentScreen = screen
                        }
                    }

                    switch event.type {
                    case .keyDown:
                        // stop selecting
                        if Int(event.keyCode) == kVK_Escape {
                            self.selecting = false
                        }
                    case .mouseMoved:
                        switch capture {
                        case .window:
                            // select and highlight window mouse is hovering
                            if currentScreen != nil {
                                if let selectionFrame = self.windowWithMouse(mouseLocation: mouseLocation, currentScreen: currentScreen!)?.frame {
                                    selection!.setFrame(selectionFrame, display: true)
                                }
                            }
                        case .display:
                            // select and highlight screen with mouse cursor
                            if currentScreen != nil {
                                selection!.setFrame(currentScreen!.frame, display: true)
                            }
                        case .portion:
                            break
                        }
                    case .leftMouseDragged:
                        // dragging event only used when selecting window portion
                        switch capture {
                        case .window(_), .display:
                            break
                        case .portion:
                            if let origin = self.selectOrigin {
                                // selecting already in progress, expand selection
                                if let currentWindow = self.currentSelectedWindow {
                                    selection!.setFrame(self.selectionRect(origin: origin, mouseLocation: mouseLocation, windowFrame: currentWindow.frame), display: true)
                                }
                            } else {
                                // selecting window portion just started
                                if currentScreen != nil {
                                    if let windowWithMouse = self.windowWithMouse(mouseLocation: mouseLocation, currentScreen: currentScreen!) {
                                        self.selectOrigin = mouseLocation
                                        self.currentSelectedWindow = windowWithMouse
                                    } else {
                                        // clear selection if selection started outside of window boundaries
                                        self.selecting = false
                                    }
                                }
                            }
                        }
                    case .leftMouseUp:
                        // draggin event stopped, window portion selected
                        switch capture {
                        case .display(_), .window:
                            break
                        case .portion:
                            if let origin = self.selectOrigin {
                                if let window = self.currentSelectedWindow {
                                    // determine portion of window to record
                                    let selectionRect = self.selectionRect(origin: origin, mouseLocation: mouseLocation, windowFrame: window.frame)
                                    let y = (window.frame.height - (selectionRect.minY - window.frame.minY)) - selectionRect.height
                                    let selectionFrame = NSRect(
                                        x: Int(selectionRect.minX - window.frame.minX),
                                        y: Int(y),
                                        width: Int(selectionRect.width),
                                        height: Int(selectionRect.height)
                                    )

                                    // create new screen recorder for window portion
                                    let newScreenRecorder = ScreenRecorder()
                                    newScreenRecorder.capture = .portion(Portion(window: window.window, sourceRect: selectionFrame))
                                    self.onSelect!(newScreenRecorder, selectionRect.size)
                                }
                            }

                            self.selecting = false
                        }
                    case .leftMouseDown, .rightMouseDown:
                        // window or screen selected for recording
                        switch capture {
                        case .window:
                            if currentScreen != nil {
                                if let selectedWindow = self.windowWithMouse(mouseLocation: mouseLocation, currentScreen: currentScreen!)?.window {
                                    // create new screen recorder for selected window
                                    let newScreenRecorder = ScreenRecorder()
                                    newScreenRecorder.capture = .window(selectedWindow)
                                    self.onSelect!(newScreenRecorder, selectedWindow.frame.size)
                                }
                            }
                            self.selecting = false
                        case .display:
                            if currentScreen != nil {
                                // create new screen recorder for selected screen
                                let newScreenRecorder = ScreenRecorder()
                                newScreenRecorder.capture = .display(displayWithMouse)
                                self.onSelect!(newScreenRecorder, currentScreen!.frame.size)
                            }
                            self.selecting = false
                        case .portion:
                            break
                        }
                    default:
                        break
                    }

                    return event
                }
            )
        }
    }

    private func mouseOnDisplay(mouseLocation: CGPoint, frame: CGRect) -> Bool {
        // Check if mouse cursor is in screen frame
        if mouseLocation.x < frame.minX || mouseLocation.x > frame.maxX {
            return false
        }

        let normalizedY = (frame.height - (mouseLocation.y - frame.minY))

        if normalizedY < frame.minY || normalizedY > frame.maxY {
            return false
        }

        return true
    }

    private func selectionRect(origin: CGPoint, mouseLocation: CGPoint, windowFrame: CGRect) -> CGRect {
        // Determine position and dimension of the crop selection rectangle
        var x1: CGFloat = 0
        var x2: CGFloat = 0
        var y1: CGFloat = 0
        var y2: CGFloat = 0

        // Ensure that selection rectangle stays within window boundaries
        if mouseLocation.x <= windowFrame.maxX && mouseLocation.x >= windowFrame.minX {
            if origin.x > mouseLocation.x {
                x2 = origin.x
                x1 = mouseLocation.x
            } else {
                x2 = mouseLocation.x
                x1 = origin.x
            }
        } else if mouseLocation.x > windowFrame.maxX {
            x2 = windowFrame.maxX
            x1 = origin.x
        } else if mouseLocation.x < windowFrame.minX {
            x2 = origin.x
            x1 = windowFrame.minX
        }

        if mouseLocation.y <= windowFrame.maxY && mouseLocation.y >= windowFrame.minY {
            if origin.y > mouseLocation.y {
                y2 = origin.y
                y1 = mouseLocation.y
            } else {
                y2 = mouseLocation.y
                y1 = origin.y
            }
        } else if mouseLocation.y > windowFrame.maxY {
            y2 = windowFrame.maxY
            y1 = origin.y
        } else if mouseLocation.y < windowFrame.minY {
            y2 = origin.y
            y1 = windowFrame.minY
        }

        return CGRect(x: x1, y: y1, width: abs(x2 - x1), height: abs(y2 - y1))
    }

    func select(capture: Capture, onSelect: @escaping ((ScreenRecorder, CGSize) -> Void)) {
        // Setup selection
        self.capture = capture
        selecting = true
        self.onSelect = onSelect

        switch capture {
        case .portion:
            showSelectionOverlays()
        default:
            break
        }

        selection = NSWindow()
        selection?.setFrame(NSRect(x: 0, y: 0, width: 0, height: 0), display: false)
        selection?.isReleasedWhenClosed = false
        selection!.titlebarAppearsTransparent = true
        selection!.makeKeyAndOrderFront(nil)
        selection!.titleVisibility = .hidden
        selection!.styleMask = .borderless
        selection!.level = .popUpMenu
        selection!.backgroundColor = NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.5)

        Task {
            self.availableShareableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        }
    }

    private func showSelectionOverlays() {
        // Create a transparent overlay window on every screen in order for window portions to be selected
        for screen in NSScreen.screens {
            let overlayWindow = NSWindow()
            overlayWindow.isReleasedWhenClosed = false
            overlayWindow.titlebarAppearsTransparent = true
            overlayWindow.makeKeyAndOrderFront(nil)
            overlayWindow.titleVisibility = .hidden
            overlayWindow.styleMask = .borderless
            overlayWindow.level = .popUpMenu
            overlayWindow.backgroundColor = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.001)
            overlayWindow.setFrame(screen.frame, display: true)

            selectionOverlays.append(overlayWindow)
        }
    }

    private func windowWithMouse(mouseLocation: NSPoint, currentScreen: NSScreen) -> (frame: NSRect, window: SCWindow)? {
        // Determine window with current mouse cursor
        if let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] {
            for dict in info {
                // Quartz window information to NSWindow information
                if (dict["kCGWindowLayer"] as! Int) == 0 {
                    let y = (dict["kCGWindowBounds"] as! [String: Any])["Y"] as! CGFloat
                    let height = (dict["kCGWindowBounds"] as! [String: Any])["Height"] as! CGFloat

                    let windowFrame = CGRect(
                        x: (dict["kCGWindowBounds"] as! [String: Any])["X"] as! CGFloat,
                        y: y,
                        width: (dict["kCGWindowBounds"] as! [String: Any])["Width"] as! CGFloat,
                        height: height
                    )

                    // translate Quartz window information to positions that can be rendered on screen as selection
                    var displayCount: UInt32 = 0
                    CGGetActiveDisplayList(0, nil, &displayCount)
                    let allocatedDisplays = Int(displayCount)
                    let activeDisplays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: allocatedDisplays)

                    if allocatedDisplays <= 0 {
                        return nil
                    }

                    CGGetActiveDisplayList(displayCount, activeDisplays, &displayCount)
                    CGGetDisplaysWithRect(windowFrame, displayCount, activeDisplays, &displayCount)
                    let activeDisplaySize = CGDisplayBounds(activeDisplays[0])

                    let selectionFrame = NSRect(
                        x: windowFrame.minX,
                        y: (currentScreen.frame.minY) + (currentScreen.frame.height) - height - y + activeDisplaySize.minY,
                        width: windowFrame.width,
                        height: windowFrame.height
                    )

                    if NSMouseInRect(mouseLocation, selectionFrame, false) {
                        let availableWindows = filterWindows(availableShareableContent!.windows)
                        for window in availableWindows {
                            if window.frame.width == windowFrame.width,
                               window.frame.height == windowFrame.height,
                               window.frame.minX == windowFrame.minX,
                               window.frame.minY == windowFrame.minY
                            {
                                return (frame: selectionFrame, window: window)
                            }
                        }
                    }
                }
            }
        }

        return nil
    }

    private func filterWindows(_ windows: [SCWindow]) -> [SCWindow] {
        // Filter on screen windows
        windows
            .sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { $0.isOnScreen }
    }
}
