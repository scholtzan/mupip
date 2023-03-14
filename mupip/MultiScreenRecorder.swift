import Foundation
import ScreenCaptureKit

@MainActor
class MultiScreenRecorder: ObservableObject {
    @Published var screenRecorders: [ScreenRecorder] = [ScreenRecorder()]
    
    var hasRecordingPermissions: Bool {
        get async {
            var hasPermissions = false
                do {
                    try await
                    SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    hasPermissions = true
                } catch {
                    hasPermissions = false
                }
            return hasPermissions
        }
    }
    
    var hasWindowControlPermissions: Bool {
        get {
            if AXIsProcessTrusted() {
                return true
            } else {
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
        await self.screenRecorders[at].stop(close: true)
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
