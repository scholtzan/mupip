//
//  ScreenRecorder.swift
//  mupip
//
//  Created by Anna Scholtz on 2023-01-02.
//

import Foundation
import OSLog
import ScreenCaptureKit
import Combine

struct CapturedFrame {
    let surface: IOSurface?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
}

enum Capture {
    case display(SCDisplay?)
    case window(SCWindow?)
    // case portion
}

@MainActor
class ScreenRecorder: ObservableObject, Hashable {
    nonisolated static func == (lhs: ScreenRecorder, rhs: ScreenRecorder) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        return hasher.combine(ObjectIdentifier(self))
    }
    
    private let logger = Logger()
    
    @Published var isRunning = false
    
    @Published var capture: Capture = .display(nil) {
        didSet { update() }
    }
    
    @Published var contentSize = CGSize(width: 1, height: 1)
    
    private var isSetup = false
    private var subscriptions = Set<AnyCancellable>()
    private var stream: SCStream?
    private let videoBufferQueue = DispatchQueue(label: "net.scholtzan.mupip.VideoBufferQueue")
    private var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?
    
    lazy var captureView: CaptureView = {
        CaptureView()
    }()
    
    private var streamConfiguration: SCStreamConfiguration {
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = false // todo: allow audio capturing
        streamConfig.excludesCurrentProcessAudio = true // todo
        
        switch capture {
        case .display(let display):
            if display != nil {
                streamConfig.width = display!.width
                streamConfig.height = display!.height
            }
        case .window(let window):
            if window != nil {
                streamConfig.width = Int(window!.frame.width)
                streamConfig.height = Int(window!.frame.height)
            }
        }
        
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        
        return streamConfig
    }
    
    private var contentFilter: SCContentFilter {
        let filter: SCContentFilter
        switch capture {
        case .display(let display):
            guard display != nil else { fatalError("No display selected") }
            filter = SCContentFilter(display: display!, excludingWindows: [])
        case .window(let window):
            guard window != nil else { fatalError("No window selected") }
            filter = SCContentFilter(desktopIndependentWindow: window!)
        }
        
        return filter
    }
    
    func record() async {
        guard !isSetup else { return }
        await self.refresh()
        Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink {
            [weak self] _ in guard let self = self else { return }
            Task {
                await self.refresh()
            }
        }.store(in: &subscriptions)
    }
    
    func start() async {
        guard !isRunning else { return }
        
        if !isSetup {
            await record()
            isSetup = true
        }
        
        do {
            let config = streamConfiguration
            let filter = contentFilter
            isRunning = true
            
            let capturedFrames = AsyncThrowingStream<CapturedFrame, Error> { continuation in
                let streamOutput = CapturedStreamOutput(continuation: continuation)
                streamOutput.capturedFrameHandler = { continuation.yield($0) }
                
                do {
                    stream = SCStream(filter: filter, configuration: config, delegate: streamOutput)
                    try stream?.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: videoBufferQueue)
                    stream?.startCapture()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            for try await frame in capturedFrames {
                captureView.updateFrame(frame)
                
                if contentSize != frame.size {
                    contentSize = frame.size
                }
            }
        } catch {
            logger.error("\(error.localizedDescription)")
            isRunning = false
        }
    }
    
    func stop() async {
        guard isRunning else { return }
        do {
            try await stream?.stopCapture()
            continuation?.finish()
        } catch {
            continuation?.finish(throwing: error)
        }
        isRunning = false
    }
    
    private func filterWindows(_ windows: [SCWindow]) -> [SCWindow] {
        windows.sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
    
    private func refresh() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            
            let availableDisplays = content.displays
            let availableWindows = filterWindows(content.windows)
            
            switch capture {
            case .display(let display):
                if display == nil {
                    self.capture = .display(availableDisplays.first)
                }
            case .window(let window):
                if window == nil {
                    self.capture = .window(availableWindows.first)
                }
            }
        } catch {
            logger.error("Failed to record screen: \(error.localizedDescription)")
        }
    }
    
    private func update() {
        guard isRunning else { return }
        Task {
            do {
                try await stream?.updateConfiguration(streamConfiguration)
                try await stream?.updateContentFilter(contentFilter)
            } catch {
                logger.error("Failed to update stream: \(error.localizedDescription)")
            }
        }
    }
}

private class CapturedStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var capturedFrameHandler: ((CapturedFrame) -> Void)?
    
    private var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?
    
    init(continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?) {
        self.continuation = continuation
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        
        switch outputType {
        case .screen:
            guard let frame = createFrame(for: sampleBuffer) else { return }
            capturedFrameHandler?(frame)
        case .audio:
            return
        @unknown default:
            fatalError("Unhandled SCStreamOutputType \(outputType)")
        }
    }
    
    private func createFrame(for sampleBuffer: CMSampleBuffer) -> CapturedFrame? {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first else { return nil }
        
        guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int, let status = SCFrameStatus(rawValue: statusRawValue), status == .complete else { return nil }
        
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return nil }
        
        guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)
        
        guard let contentRectDict = attachments[.contentRect], let contentRect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary),
              let contentScale = attachments[.contentScale] as? CGFloat,
              let scaleFactor = attachments[.scaleFactor] as? CGFloat else { return nil }
        
        let frame = CapturedFrame(surface: surface, contentRect: contentRect, contentScale: contentScale, scaleFactor: scaleFactor)
        return frame
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation?.finish(throwing: error)
    }
}