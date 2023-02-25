//
//  mupipApp.swift
//  mupip
//
//  Created by Anna Scholtz on 2022-12-30.
//

import SwiftUI
import OSLog
import ScreenCaptureKit
import Carbon.HIToolbox
import Cocoa


@main
struct mupipApp: App {
    @StateObject var multiScreenRecorder = MultiScreenRecorder()
    @State private var hoveredView: Int? = nil
    private var selectionHandler = SelectionHandler()
    @State private var windows: [NSWindow] = [NSWindow]()
    private var showControlPermissionDialog = true
        
    private let logger = Logger()
        
    var body: some Scene {
        MenuBarExtra("mupip", systemImage: "camera.on.rectangle.fill") {
            Menu("Capture") {
                Button("Display") {
                    selectionHandler.select(capture: .display(nil), onSelect: { [self] (screenRecorder: ScreenRecorder, frame: CGSize) in
                        newCapture(screenRecorder: screenRecorder, frame: frame)
                    })
                }
                Button("Window") {
                    selectionHandler.select(capture: .window(nil), onSelect: { [self] (screenRecorder: ScreenRecorder, frame: CGSize) in
                        newCapture(screenRecorder: screenRecorder, frame: frame)
                    })
                }
                Button("Window Portion") {
                    selectionHandler.select(capture: .portion(nil), onSelect: { [self] (screenRecorder: ScreenRecorder, frame: CGSize) in
                        newCapture(screenRecorder: screenRecorder, frame: frame)
                    })
                }
            }
            Button("Close All Captures") {
                self.closeAllCaptures()
            }.keyboardShortcut("c")
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
    
    func closeAllCaptures() {
        Task {
            await multiScreenRecorder.removeAll()
        }
        
        for window in self.windows {
            window.close()
        }
        
        self.windows = []
    }
    

    func newCapture(screenRecorder: ScreenRecorder, frame: CGSize) {
        Task {
            await self.multiScreenRecorder.add(screenRecorder: screenRecorder)
        }
        
        var newWindow: NSWindow? = nil
        let contentView = ContentView(screenRecorder: screenRecorder, onDelete: { [self] (screenRecorder: ScreenRecorder) in
            Task {
                await self.multiScreenRecorder.remove(screenRecorder: screenRecorder)
            }
            
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
            Task {
                await multiScreenRecorder.remove(screenRecorder: screenRecorder)
                contentView.onDelete(screenRecorder)
            }
        }
        
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
        
        var windowFrame = newWindow!.frame
        windowFrame.size = NSSize(width: round(frame.width * (200 / frame.height)), height: 200)
        newWindow!.setFrame(windowFrame, display: true)
        newWindow!.aspectRatio = NSMakeSize(round(frame.width * (200 / frame.height)), 200)
        windows.append(newWindow!)
    }
    
    func goToCapture(screenRecorder: ScreenRecorder) -> Void {
        var windowID: CGWindowID? = nil
        
        switch screenRecorder.capture {
        case .display(_):
            break
        case .window(let window):
            if window != nil {
                windowID = window!.windowID
            }
        case .portion(let portion):
            if portion != nil {
                windowID = portion!.window.windowID
            }
        }
        
        if windowID != nil {
            if let availableWindows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[ String : Any]] {
                if let window = (availableWindows.first { $0[kCGWindowNumber as String] as! Int == windowID! }) {
                    let ownerPID = window[kCGWindowOwnerPID as String] as! Int
                    let windowIndex = availableWindows
                      .filter { $0[kCGWindowOwnerPID as String] as! Int == ownerPID }
                      .firstIndex { $0[kCGWindowNumber as String] as! Int == windowID! }
                    
                    var axElements: AnyObject?
                    let appID = AXUIElementCreateApplication(pid_t(ownerPID))
                    AXUIElementCopyAttributeValue(appID, kAXWindowsAttribute as CFString, &axElements)
                    let axWindows = axElements as! [AXUIElement]
                    
                    if windowIndex != nil && windowIndex! < axWindows.count {
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
