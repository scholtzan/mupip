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
    private var onSelect: ((ScreenRecorder) -> Void)? = nil
    
    private let logger = Logger()
    
    init() {
        Task {
            await self.start()
        }
    }
    
    func start() async {
        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            
            self.eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [NSEvent.EventTypeMask.keyDown, NSEvent.EventTypeMask.mouseMoved, NSEvent.EventTypeMask.leftMouseDown, NSEvent.EventTypeMask.rightMouseDown],
                handler: { [self] (event: NSEvent) in
                    if !self.selecting {
                        return event
                    }
                    
                    switch event.type {
                    case .keyDown:

                        if Int(event.keyCode) == kVK_Escape {
                            self.selection?.close()
                            self.selecting = false
                        }
                    case .mouseMoved:
                        let mouseLocation = NSEvent.mouseLocation

                        switch capture {
                        case .window(_):
                            break
                        case .display(_):
                            let availableDisplays = availableContent.displays
                            let displayWithMouse = (availableDisplays.first { NSMouseInRect(mouseLocation, $0.frame, false) })
                            
                            for screen in NSScreen.screens {
                                if screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? UInt32 == displayWithMouse?.displayID {
                                    selection!.setFrame(screen.frame, display: true)
                                }
                            }
                            
                        }
                    case .leftMouseDown, .rightMouseDown:
                        let mouseLocation = NSEvent.mouseLocation

                        switch capture {
                        case .window(_):
                            NSEvent.removeMonitor(self.eventMonitor!)
                        case .display(_):
                            let availableDisplays = availableContent.displays
                            let displayWithMouse = (availableDisplays.first { NSMouseInRect(mouseLocation, $0.frame, false) })
                            let newScreenRecorder = ScreenRecorder()
                            newScreenRecorder.capture = .display(displayWithMouse)
                            self.onSelect!(newScreenRecorder)

                            self.selection?.close()
                            self.selecting = false
                        }
                    default:
                        break
                    }
                    
                    return event
                }
            )
        } catch {
            logger.error("Failed to get capturable screen content.")
        }
    }
    
    func select(capture: Capture, onSelect: @escaping ((ScreenRecorder) -> Void)) {
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
    }
}
