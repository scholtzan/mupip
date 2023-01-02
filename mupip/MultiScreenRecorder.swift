//
//  MultiScreenRecorder.swift
//  mupip
//
//  Created by Anna Scholtz on 2023-01-02.
//

import Foundation
import OSLog
import ScreenCaptureKit

@MainActor
class MultiScreenRecorder: ObservableObject {
    @Published var screenRecorders: [ScreenRecorder] = [ScreenRecorder(), ScreenRecorder()]
    
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
}
