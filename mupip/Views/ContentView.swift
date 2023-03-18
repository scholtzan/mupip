import OSLog
import SwiftUI

// View rendering control elements and capture view
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
            // capture view
            screenRecorder.captureView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(screenRecorder.contentSize, contentMode: .fit)
                .onHover { over in
                    if over {
                        self.isHovered = true
                    }
                }

            if screenRecorder.isPaused {
                // darken view if capture is paused
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
                        case .portion(_), .window:
                            // Show button to go to captured window
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
                        // Show button to delete capture
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
                                // Show button to resume recording if capture is paused
                                Button(action: {
                                    Task {
                                        // Continue recording
                                        await self.screenRecorder.start()
                                    }
                                }) {
                                    Image(systemName: "play.square.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                                .controlSize(.regular)
                            } else {
                                // Show pause button if capture is in progress
                                Button(action: {
                                    Task {
                                        await self.screenRecorder.stop(close: false)
                                    }
                                }) {
                                    Image(systemName: "pause.rectangle.fill")
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                                .controlSize(.regular)
                            }
                        }
                        Spacer()

                        if screenRecorder.isPlayingAudio {
                            // Show animated icon if audio is coming from recorded capture
                            Label("", systemImage: "speaker.wave.\(audioIcon).fill")
                                .labelStyle(.iconOnly)
                                .frame(width: 16, height: 16)
                                .foregroundColor(.gray)
                                .padding(.trailing, 10)
                        }

                        if screenRecorder.isInactive {
                            // Show inactivitiy indicator if captured content hasn't changed for a while
                            Label("", systemImage: "zzz")
                                .labelStyle(.iconOnly)
                                .frame(width: 16, height: 16)
                                .foregroundColor(.gray)
                                .padding(.trailing, 10)
                        }
                    }
                    .padding(.bottom, 15)
                    .frame(height: 24)
                })
            }
        })
        .onHover { over in
            if !over {
                isHovered = false
            }
        }
        .onReceive(audioAnimationTimer) { _ in
            // update animated audio indicator
            if audioIcon == 3 {
                audioIcon = 1
            } else {
                audioIcon += 1
            }
        }
    }
}
