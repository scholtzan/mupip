//
//  SelectionHandler.swift
//  mupip
//
//  Created by Anna Scholtz on 2023-01-15.
//

import SwiftUI
import OSLog
import ScreenCaptureKit
import Carbon.HIToolbox

@MainActor
class SelectionHandler {
    private var capture: Capture = .display(nil)
    private var selecting: Bool = false
    
    private var eventMonitor: Any?
    private var selection: NSWindow? = nil
    private var onSelect: ((ScreenRecorder, CGSize) -> Void)? = nil
    
    private var availableShareableContent: SCShareableContent? = nil
    
    private let logger = Logger()
    
    init() {
        Task {
            self.availableShareableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            await self.start()
        }
    }
    
    func start() async {
        do {
            self.eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [NSEvent.EventTypeMask.keyDown, NSEvent.EventTypeMask.mouseMoved, NSEvent.EventTypeMask.leftMouseDown, NSEvent.EventTypeMask.rightMouseDown],
                handler: { [self] (event: NSEvent) in
                    if !self.selecting {
                        return event
                    }
                    
                    let mouseLocation = NSEvent.mouseLocation
                    let availableDisplays = self.availableShareableContent!.displays
                    let displayWithMouse = (availableDisplays.first { NSMouseInRect(mouseLocation, $0.frame, false) })
                    
                    var currentScreen: NSScreen? = nil
                    for screen in NSScreen.screens {
                        if screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? UInt32 == displayWithMouse?.displayID {
                            currentScreen = screen
                        }
                    }
                    
                    switch event.type {
                    case .keyDown:

                        if Int(event.keyCode) == kVK_Escape {
                            self.selection?.close()
                            self.selecting = false
                        }
                    case .mouseMoved:
                        switch capture {
                        case .window(_):
                            if currentScreen != nil {
                                if let selectionFrame = self.windowWithMouse(mouseLocation: mouseLocation, currentScreen: currentScreen!)?.frame {
                                    selection!.setFrame(selectionFrame, display: true)
                                }
                            }
                        case .display(_):
                            selection!.setFrame(currentScreen!.frame, display: true)
                        }
                    case .leftMouseDown, .rightMouseDown:
                        switch capture {
                        case .window(_):
                            if currentScreen != nil {
                                if let selectedWindow = self.windowWithMouse(mouseLocation: mouseLocation, currentScreen: currentScreen!)?.window {
                                    let newScreenRecorder = ScreenRecorder()
                                    newScreenRecorder.capture = .window(selectedWindow)
                                    self.onSelect!(newScreenRecorder, selectedWindow.frame.size)
                                }
                            }
                            
                            self.selection?.close()
                            self.selecting = false
                        case .display(_):
                            let newScreenRecorder = ScreenRecorder()
                            newScreenRecorder.capture = .display(displayWithMouse)
                            self.onSelect!(newScreenRecorder, currentScreen!.frame.size)

                            self.selection?.close()
                            self.selecting = false
                        }
                    default:
                        break
                    }
                    
                    return event
                }
            )
        }
    }
    
    func select(capture: Capture, onSelect: @escaping ((ScreenRecorder, CGSize) -> Void)) {
        self.capture = capture
        self.selecting = true
        self.onSelect = onSelect
        
        self.selection = NSWindow()
        self.selection?.isReleasedWhenClosed = false
        self.selection!.titlebarAppearsTransparent = true
        self.selection!.makeKeyAndOrderFront(nil)
        self.selection!.titleVisibility = .hidden
        self.selection!.styleMask = .borderless
        self.selection!.level = .popUpMenu
        self.selection!.backgroundColor = NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.5)
        
        Task {
            self.availableShareableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        }
    }
    
    private func windowWithMouse(mouseLocation: NSPoint, currentScreen: NSScreen) -> (frame: NSRect, window: SCWindow)? {
        if let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[ String : Any]] {
            for dict in info {
                // Quartz window information to NSWindow information
                if  (dict["kCGWindowLayer"] as! Int) == 0 {
                    let y = (dict["kCGWindowBounds"] as! [String: Any])["Y"] as! CGFloat
                    let height = (dict["kCGWindowBounds"] as! [String: Any])["Height"] as! CGFloat
                    
                    let windowFrame = CGRect(
                        x: (dict["kCGWindowBounds"] as! [String: Any])["X"] as! CGFloat,
                        y: y,
                        width: (dict["kCGWindowBounds"] as! [String: Any])["Width"] as! CGFloat,
                        height: height
                    )
                    
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
                        let availableWindows = self.filterWindows(self.availableShareableContent!.windows)
                        for window in availableWindows {
                            if window.frame.width == windowFrame.width &&
                                window.frame.height == windowFrame.height &&
                                window.frame.minX == windowFrame.minX &&
                                window.frame.minY == windowFrame.minY {
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
        windows
            .sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
}
