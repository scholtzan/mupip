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
    private var selectOrigin: CGPoint? = nil
    private var onSelect: ((ScreenRecorder, CGSize) -> Void)? = nil
    private var availableShareableContent: SCShareableContent? = nil
    private var selectionOverlays: [NSWindow] = []
    private var currentSelectedWindow: (frame: NSRect, window: SCWindow)? = nil
    
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
                matching: [NSEvent.EventTypeMask.keyDown, NSEvent.EventTypeMask.mouseMoved, NSEvent.EventTypeMask.leftMouseDown, NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseDragged, NSEvent.EventTypeMask.leftMouseUp],
                handler: { [self] (event: NSEvent) in
                    if !self.selecting {
                        return event
                    }
                    
                    NSCursor.crosshair.push()
                    
                    let mouseLocation = NSEvent.mouseLocation
                    let availableDisplays = self.availableShareableContent!.displays
                    let displayWithMouse = (availableDisplays.first { self.mouseOnDisplay(mouseLocation: mouseLocation, frame: $0.frame) })
                    
                    var currentScreen: NSScreen? = nil
                    for screen in NSScreen.screens {
                        if screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? UInt32 == displayWithMouse?.displayID {
                            currentScreen = screen
                        }
                    }
                    
                    switch event.type {
                    case .keyDown:
                        if Int(event.keyCode) == kVK_Escape {
                            NSCursor.pop()
                            self.selection?.close()
                            self.selecting = false
                            for overlay in self.selectionOverlays {
                                overlay.close()
                            }
                            self.selectionOverlays =  []
                            self.currentSelectedWindow = nil
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
                            if currentScreen != nil {
                                selection!.setFrame(currentScreen!.frame, display: true)
                            }
                        case .portion(_):
                            break
                        }
                    case .leftMouseDragged:
                        switch capture {
                        case .window(_), .display(_):
                            break
                        case .portion(_):
                            if let origin = self.selectOrigin {
                                if let currentWindow = self.currentSelectedWindow {
                                    selection!.setFrame(self.selectionRect(origin: origin, mouseLocation: mouseLocation, windowFrame: currentWindow.frame), display: true)
                                }
                            } else {
                                if currentScreen != nil {
                                    if let windowWithMouse = self.windowWithMouse(mouseLocation: mouseLocation, currentScreen: currentScreen!) {
                                        self.selectOrigin = mouseLocation
                                        self.currentSelectedWindow = windowWithMouse
                                    } else {
                                        self.selectOrigin = nil
                                        self.selection?.close()
                                        self.selecting = false
                                        self.currentSelectedWindow = nil
                                        
                                        for overlay in self.selectionOverlays {
                                            overlay.close()
                                        }
                                        self.selectionOverlays =  []
                                        NSCursor.pop()
                                    }
                                }
                            }
                        }
                    case .leftMouseUp:
                        switch capture {
                        case .display(_), .window(_):
                            break
                        case .portion(_):
                            if let origin = self.selectOrigin {
                                if let window = self.currentSelectedWindow {
                                    let selectionRect = self.selectionRect(origin: origin, mouseLocation: mouseLocation, windowFrame: window.frame)

                                    let y = (window.frame.height - (selectionRect.minY - window.frame.minY)) - selectionRect.height
                                    
                                    let selectionFrame = NSRect(
                                        x: Int(selectionRect.minX - window.frame.minX),
                                        y: Int(y),
                                        width: Int(selectionRect.width),
                                        height: Int(selectionRect.height)
                                    )
                                    
                                    let newScreenRecorder = ScreenRecorder()
                                    newScreenRecorder.capture = .portion(Portion(window: window.window, sourceRect: selectionFrame))
                                    self.onSelect!(newScreenRecorder, selectionRect.size)
                                }
                            }

                            // todo: clearSelection method
                            self.selectOrigin = nil
                            self.selection?.close()
                            self.selecting = false
                            self.currentSelectedWindow = nil
                            
                            for overlay in self.selectionOverlays {
                                overlay.close()
                            }
                            self.selectionOverlays =  []
                            NSCursor.pop()
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
                            if currentScreen != nil {
                                let newScreenRecorder = ScreenRecorder()
                                newScreenRecorder.capture = .display(displayWithMouse)
                                self.onSelect!(newScreenRecorder, currentScreen!.frame.size)
                            }

                            self.selection?.close()
                            self.selecting = false
                            NSCursor.pop()
                        case .portion(_):
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
        var x1: CGFloat = 0
        var x2: CGFloat = 0
        var y1: CGFloat = 0
        var y2: CGFloat = 0
        
        if mouseLocation.x <= windowFrame.maxX && mouseLocation.x >= windowFrame.minX {
            if origin.x > mouseLocation.x {
                x2 = origin.x
                x1 = mouseLocation.x
            } else {
                x2 = mouseLocation.x
                x1 = origin.x
            }
        }
        
        if mouseLocation.y <= windowFrame.maxY && mouseLocation.y >= windowFrame.minY {
            if origin.y > mouseLocation.y {
                y2 = origin.y
                y1 = mouseLocation.y
            } else {
                y2 = mouseLocation.y
                y1 = origin.y
            }
        }
        
        return CGRect(x: x1, y: y1, width: abs(x2 - x1), height: abs(y2 - y1))
    }
    
    func select(capture: Capture, onSelect: @escaping ((ScreenRecorder, CGSize) -> Void)) {
        self.capture = capture
        self.selecting = true
        self.onSelect = onSelect
        
        switch capture {
        case .portion(_):
            self.showSelectionOverlays()
        default:
            break
        }
        
        self.selection = NSWindow()
        self.selection?.setFrame(NSRect(x: 0, y: 0, width: 0, height: 0), display: false)
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
    
    private func showSelectionOverlays() {
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
            
            self.selectionOverlays.append(overlayWindow)
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
            .filter { $0.isOnScreen }
    }
}
