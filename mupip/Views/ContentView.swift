import SwiftUI
import OSLog

struct ContentView: View {
    private let logger = Logger()
    
    @StateObject var screenRecorder: ScreenRecorder
    @State private var isHovered: Bool = false
    var onDelete: (ScreenRecorder) -> Void
    
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .top), content: {
            screenRecorder.captureView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(screenRecorder.contentSize, contentMode: .fit)
                .onHover { over in
                    if over {
                        self.isHovered = true
                    }
                }

            if self.isHovered {
                Button(action: {
                    self.onDelete(self.screenRecorder)
                }) {
                    Image(systemName: "trash.fill")
                }
                .padding(.trailing, 10)
                .padding(.top, 10)
            }
        })
        .onHover { over in
            if !over {
                isHovered = false
            }
        }
    }
}
