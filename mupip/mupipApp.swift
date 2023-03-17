import AppKit
import Carbon.HIToolbox
import Cocoa
import OSLog
import ScreenCaptureKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // open settings window if some permissions are missing
        if !AXIsProcessTrusted() {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        Task {
            do {
                try await
                    SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            } catch {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}

@main
struct mupipApp: App {
    @StateObject var multiScreenRecorder = MultiScreenRecorder()

    @State private var windows: [NSWindow] = .init() // capture windows
    private var selectionHandler = SelectionHandler()

    @NSApplicationDelegateAdaptor(AppDelegate.self) var Delegate

    @AppStorage("captureHeight") private var captureHeight = DefaultSettings.captureHeight
    @AppStorage("captureCorner") private var captureCorner = DefaultSettings.captureCorner

    private let logger = Logger()

    var body: some Scene {
        MenuBarExtra("mupip", systemImage: "camera.on.rectangle.fill") {
            Menu("Capture") {
                Button("Display") {
                    selectionHandler.select(capture: .display(nil), onSelect: { [self] (screenRecorder: ScreenRecorder, frame: CGSize) in
                        newCapture(screenRecorder: screenRecorder, frame: frame)
                    })
                }.keyboardShortcut("d")
                Button("Window") {
                    selectionHandler.select(capture: .window(nil), onSelect: { [self] (screenRecorder: ScreenRecorder, frame: CGSize) in
                        newCapture(screenRecorder: screenRecorder, frame: frame)
                    })
                }.keyboardShortcut("w")
                Button("Window Portion") {
                    selectionHandler.select(capture: .portion(nil), onSelect: { [self] (screenRecorder: ScreenRecorder, frame: CGSize) in
                        newCapture(screenRecorder: screenRecorder, frame: frame)
                    })
                }.keyboardShortcut("p")
            }
            Button("Gather Captures") {
                self.gatherCaptures()
            }.keyboardShortcut("g")
            Button("Close All Captures") {
                self.closeAllCaptures()
            }.keyboardShortcut("x")

            Divider()

            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }.keyboardShortcut("s")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }

        Settings {
            SettingsView(multiScreenRecorder: multiScreenRecorder)
        }.defaultSize(CGSize(width: 400, height: 400))
    }

    func closeAllCaptures() {
        // remove all capture windows
        Task {
            await multiScreenRecorder.removeAll()
        }

        for window in windows {
            window.close()
        }

        windows = []
    }

    func gatherCaptures() {
        // move all capture windows into one corner of the active screen
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens

        // get active screen based on mouse location
        if let activeScreen = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            // align capture windows in the most compact way in one corner
            let windowRows = Int(Double(windows.count).squareRoot().rounded(.up))
            for (i, window) in windows.enumerated() {
                let row = Double(windowRows - 1) - Double((i + 1) % windowRows)
                let col = Double((Double(i + 1) / Double(windowRows)).rounded(.up))
                let windowSize = NSSize(
                    width: min(round(window.frame.width * (CGFloat(captureHeight) / window.frame.height)), CGFloat(captureHeight)),
                    height: min(round(window.frame.height * (CGFloat(captureHeight) / window.frame.width)), CGFloat(captureHeight))
                )
                var x = 0.0
                var y = 0.0

                switch captureCorner {
                case .topRight:
                    x = activeScreen.visibleFrame.maxX - col * Double(captureHeight + 10)
                    y = activeScreen.visibleFrame.maxY - (row + 1) * Double(captureHeight + 10)
                case .topLeft:
                    x = activeScreen.visibleFrame.minX + (col - 1) * Double(captureHeight + 10)
                    y = activeScreen.visibleFrame.maxY - (row + 1) * Double(captureHeight + 10)
                case .bottomRight:
                    x = activeScreen.visibleFrame.maxX - col * Double(captureHeight + 10)
                    y = activeScreen.visibleFrame.minY + row * Double(captureHeight + 10)
                case .bottomLeft:
                    x = activeScreen.visibleFrame.minX + (col - 1) * Double(captureHeight + 10)
                    y = activeScreen.visibleFrame.minY + row * Double(captureHeight + 10)
                }

                let position = CGPoint(x: x, y: y)
                window.setFrame(NSRect(origin: position, size: windowSize), display: true)
            }
        }
    }

    func newCapture(screenRecorder: ScreenRecorder, frame: CGSize) {
        // create a new capture
        Task {
            await self.multiScreenRecorder.add(screenRecorder: screenRecorder)
        }

        var newWindow: NSWindow? = nil
        let contentView = ContentView(screenRecorder: screenRecorder, onDelete: { [self] (screenRecorder: ScreenRecorder) in
            Task {
                await self.multiScreenRecorder.remove(screenRecorder: screenRecorder)
            }

            // remove capture window when screen recorder is closed
            if let window = newWindow {
                window.close()
                if let i = windows.firstIndex(of: window) {
                    windows.remove(at: i)
                }
            }
        }, onGoToCapture: {
            [self] (screenRecorder: ScreenRecorder) in
            self.goToCapture(screenRecorder: screenRecorder)
        })

        screenRecorder.onStoppedRunning = { [self] (screenRecorder: ScreenRecorder) in
            // remove screen recorders from MultiScreenRecorder that have stopped
            Task {
                await multiScreenRecorder.remove(screenRecorder: screenRecorder)
                contentView.onDelete(screenRecorder)
            }
        }

        // create a new capture window
        newWindow = NSWindow(contentViewController: NSHostingController(rootView: contentView))
        newWindow!.titleVisibility = .hidden
        newWindow!.titlebarAppearsTransparent = true
        newWindow!.level = .floating
        newWindow!.makeKeyAndOrderFront(newWindow)
        newWindow!.tabbingMode = .disallowed
        newWindow!.standardWindowButton(.miniaturizeButton)!.isHidden = true
        newWindow!.standardWindowButton(.zoomButton)!.isHidden = true
        newWindow!.standardWindowButton(.closeButton)!.isHidden = true
        newWindow!.styleMask = [.borderless, .resizable]
        newWindow!.isMovableByWindowBackground = true
        newWindow!.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // set default size and aspect ratio based on the recorded screen portion
        var windowFrame = newWindow!.frame
        windowFrame.size = NSSize(width: round(frame.width * (CGFloat(captureHeight) / frame.height)), height: CGFloat(captureHeight))
        newWindow!.setFrame(windowFrame, display: true)
        newWindow!.aspectRatio = NSMakeSize(round(frame.width * (CGFloat(captureHeight) / frame.height)), CGFloat(captureHeight))
        windows.append(newWindow!)
    }

    func goToCapture(screenRecorder: ScreenRecorder) {
        // go to the window the is captured by the recorder
        var windowID: CGWindowID? = nil

        switch screenRecorder.capture {
        case .display:
            break
        case let .window(window):
            if window != nil {
                windowID = window!.windowID
            }
        case let .portion(portion):
            if portion != nil {
                windowID = portion!.window.windowID
            }
        }

        if windowID != nil {
            if let availableWindows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] {
                // find the window matching the stored window ID
                if let window = (availableWindows.first { $0[kCGWindowNumber as String] as! Int == windowID! }) {
                    // determine process ID of window
                    let ownerPID = window[kCGWindowOwnerPID as String] as! Int

                    // get window index
                    let windowIndex = availableWindows
                        .filter { $0[kCGWindowOwnerPID as String] as! Int == ownerPID }
                        .firstIndex { $0[kCGWindowNumber as String] as! Int == windowID! }

                    // create accesssibility object for the window process ID
                    var axElements: AnyObject?
                    let appID = AXUIElementCreateApplication(pid_t(ownerPID))
                    AXUIElementCopyAttributeValue(appID, kAXWindowsAttribute as CFString, &axElements)
                    let axWindows = axElements as! [AXUIElement]

                    if windowIndex != nil && windowIndex! < axWindows.count {
                        // bring window to front
                        let app = NSRunningApplication(processIdentifier: pid_t(ownerPID))
                        let axWindow = axWindows[windowIndex!]
                        app!.activate(options: [.activateIgnoringOtherApps])
                        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    }
                }
            }
        }
    }
}
