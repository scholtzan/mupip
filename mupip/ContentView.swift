import SwiftUI
import OSLog

struct ContentView: View {
    private let logger = Logger()
    
    @StateObject var multiScreenRecorder: MultiScreenRecorder
    @State private var hoveredView: Int? = nil
    
    var body: some View {
        HStack {
            ForEach(multiScreenRecorder.screenRecorders, id: \.self) { screenRecorder in
                let i = multiScreenRecorder.screenRecorders.firstIndex(of: screenRecorder)
                ZStack(alignment: Alignment(horizontal: .trailing, vertical: .top), content: {
                    screenRecorder.captureView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(screenRecorder.contentSize, contentMode: .fit)
                        .onHover { over in
                            if over {
                                self.hoveredView = i
                            }
                        }
                    
                    if self.hoveredView == i {
                        Button(action: {
                            Task {
                                await multiScreenRecorder.remove(at: i!)
                            }
                        }) {
                            Image(systemName: "trash.fill")
                        }
                        .padding(.trailing, 10)
                        .padding(.top, 10)
                    }
                })
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
        .onHover { over in
            if !over {
                hoveredView = nil
            }
        }
    }
}
