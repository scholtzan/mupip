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
                Button("Selection") {
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

        })
        
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

}
