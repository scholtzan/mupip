import SwiftUI
import OSLog

struct ContentView: View {
    private let logger = Logger()
    
    @StateObject var screenRecorder: ScreenRecorder
    @State private var isHovered: Bool = false
    
    var onDelete: (ScreenRecorder) -> Void
    var onGoToCapture: (ScreenRecorder) -> Void
    
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
            
            if screenRecorder.isPaused {
                Rectangle()
                    .foregroundColor(Color.black.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(screenRecorder.contentSize, contentMode: .fit)
                    .onHover { over in
                        if over {
                            self.isHovered = true
                        }
                    }
            }
                       
            if self.isHovered {
                VStack {
                    HStack {
                        switch self.screenRecorder.capture {
                        case .portion(_), .window(_):
                            Button(action: {
                                self.onGoToCapture(self.screenRecorder)
                            }) {
                                Image(systemName: "macwindow")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                            .controlSize(.large)
                            .padding(.leading, 10)
                            .padding(.top, 10)
                        default:
                            Spacer()
                        }
                        Spacer()
                        Button(action: {
                            self.onDelete(self.screenRecorder)
                        }) {
                            Image(systemName: "xmark.square.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                        .controlSize(.large)
                        .padding(.trailing, 10)
                        .padding(.top, 10)
                    }
                    Spacer()
                    HStack(alignment: .center) {
                        Spacer()
                        if !self.screenRecorder.isPaused {
                            Button(action: {
                                Task {
                                    await self.screenRecorder.stop(close: false)
                                }
                            }) {
                                Image(systemName: "play.square.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                            .controlSize(.large)
                            .padding(.bottom, 10)
                        } else {
                            Button(action: {
                                Task {
                                    await self.screenRecorder.start()
                                }
                            }) {
                                Image(systemName: "pause.rectangle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                            .controlSize(.large)
                            .padding(.bottom, 10)
                        }
                        Spacer()
                    }
                }
            }
        })
        .onHover { over in
            if !over {
                isHovered = false
            }
        }
    }
}
