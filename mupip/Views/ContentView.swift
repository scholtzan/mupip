import SwiftUI
import OSLog

struct ContentView: View {
    private let logger = Logger()
    
    @StateObject var screenRecorder: ScreenRecorder
    @State private var isHovered: Bool = false
    @State private var audioAnimationTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var audioIcon = 1
    
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
              
            VStack {
                if self.isHovered {
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
                }
                Spacer()
                ZStack(alignment: Alignment(horizontal: .trailing, vertical: .top), content: {
                    HStack(alignment: .center) {
                        Spacer()
                        if self.isHovered {
                            if self.screenRecorder.isPaused {
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
                                .controlSize(.regular)
                                .padding(.bottom, 10)
                            }
                        }
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        if screenRecorder.isPlayingAudio {
                            Label("", systemImage: "speaker.wave.\(audioIcon).fill")
                                .font(.title)
                                .labelStyle(.iconOnly)
                                .frame(width: 10, height: 10)
                                .foregroundColor(.gray)
                                .controlSize(.mini)
                                .padding(.bottom, 10)
                                .padding(.trailing, 10)
                        }
                        
                        if screenRecorder.isInactive {
                            Label("", systemImage: "zzz")
                                .font(.title)
                                .labelStyle(.iconOnly)
                                .frame(width: 10, height: 10)
                                .foregroundColor(.gray)
                                .controlSize(.mini)
                                .padding(.bottom, 10)
                                .padding(.trailing, 10)
                        }
                    }
                })
            }
        })
        .onHover { over in
            if !over {
                isHovered = false
            }
        }
        .onReceive(audioAnimationTimer) { _ in
            if audioIcon == 3 {
                audioIcon = 1
            } else {
                audioIcon += 1
            }
        }
    }
}
