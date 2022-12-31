//
//  mupipApp.swift
//  mupip
//
//  Created by Anna Scholtz on 2022-12-30.
//

import SwiftUI

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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }.windowStyle(HiddenTitleBarWindowStyle())
        
        MenuBarExtra("mupip") {
            Button("Close") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
