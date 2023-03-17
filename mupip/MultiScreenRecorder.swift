import Foundation
import ScreenCaptureKit

@MainActor
class MultiScreenRecorder: ObservableObject {
    // Handler for multiple screen recorder instances
    @Published var screenRecorders: [ScreenRecorder] = [ScreenRecorder()]

    func start() async {
        // Start all screen recorders
        for recorder in screenRecorders {
            Task {
                await recorder.start()
            }
        }
    }

    func add(screenRecorder: ScreenRecorder) async {
        // Add a new screen recorder
        screenRecorders.append(screenRecorder)
        await screenRecorder.start()
    }

    func remove(at: Int) async {
        // Remove a specific screen recorder based on index
        await screenRecorders[at].stop(close: true)
        screenRecorders.remove(at: at)
    }

    func remove(screenRecorder: ScreenRecorder) async {
        // Remove a specific screen recorder instance
        if let i = screenRecorders.firstIndex(of: screenRecorder) {
            await remove(at: i)
        }
    }

    func removeAll() async {
        // Remove all screen recorders
        for recorder in screenRecorders {
            await remove(screenRecorder: recorder)
        }
    }
}
