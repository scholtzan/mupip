import SwiftUI
import OSLog

struct ContentView: View {
    private let logger = Logger()
    
    @StateObject var multiScreenRecorder = MultiScreenRecorder()
    
    var body: some View {
        HStack {
            ForEach(0..<multiScreenRecorder.screenRecorders.count, id: \.self) { i in
                multiScreenRecorder.screenRecorders[i].captureView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(multiScreenRecorder.screenRecorders[i].contentSize, contentMode: .fit)
            }
        }
        .padding()
        .navigationTitle("mupip")
        .onAppear {
            Task {
                if await multiScreenRecorder.hasRecordingPermissions {
                    await multiScreenRecorder.start()
                } else {
                    logger.error("No permissions to capture screen")
                }
            }
        }
    }
}
