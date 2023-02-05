//
//  MultiScreenRecorder.swift
//  mupip
//
//  Created by Anna Scholtz on 2023-01-02.
//

import Foundation
import ScreenCaptureKit

@MainActor
class MultiScreenRecorder: ObservableObject {
    @Published var screenRecorders: [ScreenRecorder] = [ScreenRecorder()]
    
    var hasRecordingPermissions: Bool {
        get async {
            do {
                try await
                    SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                return true
            } catch {
                return false
            }
        }
    }
    
    func start() async {
        for recorder in self.screenRecorders {
            Task {
                await recorder.start()
            }
        }
    }
    
    func add(screenRecorder: ScreenRecorder) async {
        self.screenRecorders.append(screenRecorder)
        await screenRecorder.start()
    }
    
    func remove(at: Int) async {
        await self.screenRecorders[at].stop()
        self.screenRecorders.remove(at: at)
    }
    
    func remove(screenRecorder: ScreenRecorder) async {
        if let i = screenRecorders.firstIndex(of: screenRecorder) {
            await self.remove(at: i)
        }
    }
    
    func removeAll() async {
        for recorder in screenRecorders {
            await self.remove(screenRecorder: recorder)
        }
    }
}
