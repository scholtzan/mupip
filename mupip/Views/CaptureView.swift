//
//  CaptureView.swift
//  mupip
//
//  Created by Anna Scholtz on 2022-12-30.
//

import SwiftUI

struct CaptureView: NSViewRepresentable {
    private let contentLayer = CALayer()
    
    init() {
        contentLayer.contentsGravity = .resizeAspect
    }
    
    func makeNSView(context: Context) -> CaptureVideoView {
        CaptureVideoView(layer: contentLayer)
    }
    
    func updateFrame(_ frame: CapturedFrame) {
        contentLayer.contents = frame.surface
    }
    
    func updateNSView(_ nsView: CaptureVideoView, context: Context) {
        
    }
    
    class CaptureVideoView: NSView {
        init(layer: CALayer) {
            super.init(frame: .zero)
            
            self.layer = layer
            wantsLayer = true
        }
        
        required init?(coder: NSCoder) {
            fatalError("Not implemented")
        }
    }
}

struct CaptureView_Previews: PreviewProvider {
    static var previews: some View {
        CaptureView()
    }
}
