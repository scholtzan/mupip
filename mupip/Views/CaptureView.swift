import SwiftUI

// Render the captured content
struct CaptureView: NSViewRepresentable {
    private let contentLayer = CALayer()

    init() {
        contentLayer.contentsGravity = .resizeAspect
    }

    func makeNSView(context _: Context) -> CaptureVideoView {
        CaptureVideoView(layer: contentLayer)
    }

    func updateFrame(_ frame: CapturedFrame) {
        contentLayer.contents = frame.surface
    }

    func updateNSView(_: CaptureVideoView, context _: Context) {}

    class CaptureVideoView: NSView {
        init(layer: CALayer) {
            super.init(frame: .zero)

            self.layer = layer
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("Not implemented")
        }
    }
}
