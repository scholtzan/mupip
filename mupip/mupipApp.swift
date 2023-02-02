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
        MenuBarExtra("mupip", systemImage: "hammer") {
            Menu("Capture") {
                Button("Display") {
                    selectionHandler.select(capture: .display(nil), onSelect: { [self] (screenRecorder: ScreenRecorder) in
                        newCapture(screenRecorder: screenRecorder)
                    })
                }
                Button("Window") {
                    selectionHandler.select(capture: .window(nil), onSelect: { [self] (screenRecorder: ScreenRecorder) in
                        newCapture(screenRecorder: screenRecorder)
                    })
                }
                Button("Selection") {
                    // todo
                }
            }
            Divider()
            
            Button("Close") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
    
    func newCapture(screenRecorder: ScreenRecorder) {
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
        
        var frame = newWindow!.frame
        frame.size = NSSize(width: 200, height: 200)
        newWindow!.setFrame(frame, display: true)
        
        newWindow!.titleVisibility = .hidden
        newWindow!.titlebarAppearsTransparent = true
        newWindow!.level = .floating
        newWindow!.makeKeyAndOrderFront(newWindow)
        newWindow!.tabbingMode = .disallowed
        newWindow!.standardWindowButton(.miniaturizeButton)!.isHidden = true
        newWindow!.standardWindowButton(.zoomButton)!.isHidden = true
        newWindow!.standardWindowButton(.closeButton)!.isHidden = true
        newWindow!.styleMask = .borderless
        

        // todo: drag drop window
        // onDrag method passed into view or notice drag and drop on contentview
        //newWindow!.performDrag()
             
        windows.append(newWindow!)
    }

}
