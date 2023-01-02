import SwiftUI
import OSLog

struct ContentView: View {
    private let logger = Logger()
    
    @StateObject var screenRecorder = ScreenRecorder()
    
    var body: some View {
        VStack {
            screenRecorder.captureView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(screenRecorder.contentSize, contentMode: .fit)
        }
        .padding()
        .navigationTitle("mupip")
        .onAppear {
            Task {
                if await screenRecorder.hasRecordingPermissions {
                    await screenRecorder.start()
                } else {
                    logger.error("No permissions to capture screen")
                }
            }
        }
    }
}
