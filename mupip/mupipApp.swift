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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.level = .floating
        }
    }
}

@main
struct mupipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @StateObject var multiScreenRecorder = MultiScreenRecorder()
    private var selectionHandler = SelectionHandler()
    
    private let logger = Logger()
    
    var body: some Scene {
        WindowGroup {
            ContentView(multiScreenRecorder: multiScreenRecorder)
        }.windowStyle(HiddenTitleBarWindowStyle())

        
        MenuBarExtra("mupip") {
            Menu("Capture") {
                Button("Display") {
                    selectionHandler.select(capture: .display(nil), onSelect: { [self] (screenRecorder: ScreenRecorder) in
                        Task {
                            await self.multiScreenRecorder.add(screenRecorder: screenRecorder)
                        }
                    })
                }
                Button("Window") {
                    selectionHandler.select(capture: .window(nil), onSelect: { [self] (screenRecorder: ScreenRecorder) in
                        Task {
                            await self.multiScreenRecorder.add(screenRecorder: screenRecorder)
                        }
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

}
