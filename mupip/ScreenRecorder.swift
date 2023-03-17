import Accelerate
import AVFAudio
import Cocoa
import Combine
import Foundation
import OSLog
import ScreenCaptureKit
import SwiftUI

// State of a captured frame
enum Frame {
    case captured(CapturedFrame)
    case idle
}

// Wrapper for captured frame
struct CapturedFrame {
    let surface: IOSurface?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
}

// Selected window portion to be captured
struct Portion {
    let window: SCWindow
    let sourceRect: CGRect
}

// Screen capture type
enum Capture {
    // Capture a specific display
    case display(SCDisplay?)

    // Capture a specific window
    case window(SCWindow?)

    // Capture a portion of a window
    case portion(Portion?)
}

@MainActor
class ScreenRecorder: ObservableObject, Hashable, Identifiable {
    @AppStorage("refreshFrequency") private var refreshFrequency = DefaultSettings.refreshFrequency
    @AppStorage("inactivityThreshold") private var inactivityThreshold = DefaultSettings.inactivityThreshold

    @Published var isRunning = false {
        didSet {
            if isRunning == false && onStoppedRunning != nil {
                onStoppedRunning!(self)
            }
        }
    }

    @Published var isPaused = false
    @Published var capture: Capture = .display(nil) {
        didSet { update() }
    }

    @Published var contentSize = CGSize(width: 1, height: 1)
    @Published var isPlayingAudio = false // window is the source for audio playing
    @Published var isInactive = false // no activity in screen capture

    lazy var captureView: CaptureView = .init()
    var onStoppedRunning: ((ScreenRecorder) -> Void)? = nil
    let id = UUID()

    private let logger = Logger()
    private var cropRect: CGRect? = nil // selected window portion
    private var isSetup = false // screen recorder set up is done
    private var subscriptions = Set<AnyCancellable>()
    private var stream: SCStream?
    private let videoBufferQueue = DispatchQueue(label: "net.scholtzan.mupip.VideoBufferQueue")
    private let audioBufferQueue = DispatchQueue(label: "net.scholtzan.mupip.AudioBufferQueue")
    private var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?
    private var lastUpdated: Date = .init() // timestamp when capture content changed last
    private var streamConfiguration: SCStreamConfiguration {
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.excludesCurrentProcessAudio = false

        // stream configs based on captured content
        switch capture {
        case let .display(display):
            if display != nil {
                streamConfig.width = display!.width
                streamConfig.height = display!.height
                streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
            }
        case let .window(window):
            if window != nil {
                streamConfig.width = Int(window!.frame.width)
                streamConfig.height = Int(window!.frame.height)
                streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
            }
        case let .portion(portion):
            if portion != nil {
                streamConfig.width = Int(portion!.window.frame.width)
                streamConfig.height = Int(portion!.window.frame.height)
                streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
                cropRect = portion?.sourceRect
            }
        }

        // set capture refresh frequency
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(refreshFrequency))
        return streamConfig
    }

    private var contentFilter: SCContentFilter {
        // capture content filter settings
        let filter: SCContentFilter
        switch capture {
        case let .display(display):
            guard display != nil else { fatalError("No display selected") }
            filter = SCContentFilter(display: display!, excludingWindows: [])
        case let .window(window):
            guard window != nil else { fatalError("No window selected") }
            filter = SCContentFilter(desktopIndependentWindow: window!)
        case let .portion(portion):
            guard portion != nil else { fatalError("No window portion selected") }
            filter = SCContentFilter(desktopIndependentWindow: portion!.window)
        }

        return filter
    }

    nonisolated static func == (lhs: ScreenRecorder, rhs: ScreenRecorder) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    nonisolated func hash(into hasher: inout Hasher) {
        return hasher.combine(ObjectIdentifier(self))
    }

    func start() async {
        // Start and set up the screen recorder
        if !isSetup {
            await record()
            isSetup = true
        }

        do {
            let config = streamConfiguration
            let filter = contentFilter
            isRunning = true
            isPaused = false

            // handle recorded frames and audio
            let capturedFrames = AsyncThrowingStream<Frame, Error> { continuation in
                let streamOutput = CapturedStreamOutput(continuation: continuation, cropRect: self.cropRect)
                streamOutput.capturedFrameHandler = { continuation.yield($0) }
                streamOutput.audioBufferHandler = { self.processAudio(audioBuffer: $0) }

                do {
                    stream = SCStream(filter: filter, configuration: config, delegate: streamOutput)
                    try stream?.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: videoBufferQueue)
                    try stream?.addStreamOutput(streamOutput, type: .audio, sampleHandlerQueue: audioBufferQueue)
                    stream?.startCapture()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            for try await frame in capturedFrames {
                switch frame {
                case .idle:
                    // determine whether capture has been inactive for long enough to show an indicator
                    let elapsed = Int(Date().timeIntervalSince(lastUpdated))
                    if elapsed > Int(inactivityThreshold) {
                        isInactive = true
                    }
                case let .captured(f):
                    captureView.updateFrame(f)
                    isInactive = false
                    lastUpdated = Date()

                    if contentSize != f.size {
                        contentSize = f.size
                    }
                }
            }
        } catch {
            logger.error("\(error.localizedDescription)")
            isRunning = false
        }
    }

    func record() async {
        guard !isSetup else { return }
        await refresh()
        Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink {
            [weak self] _ in guard let self = self else { return }
            Task {
                await self.refresh()
            }
        }.store(in: &subscriptions)
    }

    func stop(close: Bool) async {
        // Stop screen recorder
        guard isRunning else { return }

        if !isPaused {
            do {
                try await stream?.stopCapture()
                continuation?.finish()
            } catch {
                continuation?.finish(throwing: error)
            }
        }

        if close {
            isRunning = false
        } else {
            isPaused = true
        }
    }

    private func processAudio(audioBuffer: AVAudioPCMBuffer) {
        // Process recorded audio to show an audio playing indicator
        let channelCount = Int(audioBuffer.format.channelCount)
        let length = vDSP_Length(audioBuffer.frameLength)
        var isSilent = true

        // Check all buffers and channels for audio playing
        if let floatData = audioBuffer.floatChannelData {
            for channel in 0 ..< channelCount {
                if isSilent {
                    isSilent = checkSilent(data: floatData[channel], strideFrames: audioBuffer.stride, length: length)
                }
            }
        } else if let int16Data = audioBuffer.int16ChannelData {
            for channel in 0 ..< channelCount {
                var floatChannelData: [Float] = Array(repeating: Float(0.0), count: Int(audioBuffer.frameLength))
                vDSP_vflt16(int16Data[channel], audioBuffer.stride, &floatChannelData, audioBuffer.stride, length)
                var scalar = Float(INT16_MAX)
                vDSP_vsdiv(floatChannelData, audioBuffer.stride, &scalar, &floatChannelData, audioBuffer.stride, length)

                if isSilent {
                    isSilent = checkSilent(data: floatChannelData, strideFrames: audioBuffer.stride, length: length)
                }
            }
        } else if let int32Data = audioBuffer.int32ChannelData {
            for channel in 0 ..< channelCount {
                var floatChannelData: [Float] = Array(repeating: Float(0.0), count: Int(audioBuffer.frameLength))
                vDSP_vflt32(int32Data[channel], audioBuffer.stride, &floatChannelData, audioBuffer.stride, length)
                var scalar = Float(INT32_MAX)
                vDSP_vsdiv(floatChannelData, audioBuffer.stride, &scalar, &floatChannelData, audioBuffer.stride, length)

                if isSilent {
                    isSilent = checkSilent(data: floatChannelData, strideFrames: audioBuffer.stride, length: length)
                }
            }
        }

        DispatchQueue.main.async {
            self.isPlayingAudio = !isSilent
        }
    }

    private func checkSilent(data: UnsafePointer<Float>, strideFrames: Int, length: vDSP_Length) -> Bool {
        // Check if audio is playing
        var max: Float = 0.0
        vDSP_maxv(data, strideFrames, &max, length)

        if max > 0 {
            return false
        }

        return true
    }

    private func refresh() async {
        // Setup capture content
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let availableDisplays = content.displays
            let availableWindows = filterWindows(content.windows)

            switch capture {
            case let .display(display):
                if display == nil {
                    capture = .display(availableDisplays.first)
                }
            case let .window(window):
                if window == nil {
                    capture = .window(availableWindows.first)
                }
            case let .portion(portion):
                if portion == nil {
                    if let window = availableWindows.first {
                        capture = .portion(Portion(window: window, sourceRect: window.frame))
                    } else {
                        capture = .portion(nil)
                    }
                }
            }
        } catch {
            logger.error("Failed to record screen: \(error.localizedDescription)")
        }
    }

    private func update() {
        // Update screen recorder
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

    private func filterWindows(_ windows: [SCWindow]) -> [SCWindow] {
        // Get windows that available to be recorded
        windows.sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
}

// Stream output handler
private class CapturedStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var capturedFrameHandler: ((Frame) -> Void)?
    var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)?

    private var continuation: AsyncThrowingStream<Frame, Error>.Continuation?
    private var cropRect: CGRect?

    init(continuation: AsyncThrowingStream<Frame, Error>.Continuation?, cropRect: CGRect?) {
        self.continuation = continuation
        self.cropRect = cropRect
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch outputType {
        case .screen:
            guard let frame = createFrame(for: sampleBuffer, cropRect: cropRect) else { return }
            capturedFrameHandler?(frame)
        case .audio:
            guard let samples = createAudioBuffer(for: sampleBuffer) else { return }
            audioBufferHandler?(samples)
        @unknown default:
            fatalError("Unhandled SCStreamOutputType \(outputType)")
        }
    }

    private func createFrame(for sampleBuffer: CMSampleBuffer, cropRect: CGRect?) -> Frame? {
        // Create a capture frame
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first else { return nil }

        // determine captured frame status
        if let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int {
            let status = SCFrameStatus(rawValue: statusRawValue)
            if status != .complete {
                if status == .idle {
                    return Frame.idle
                }
                return nil
            }
        } else {
            return nil
        }

        // crop captured frame if window portion is recorded
        var pixelBuffer: CVPixelBuffer?
        if cropRect == nil {
            pixelBuffer = sampleBuffer.imageBuffer
        } else {
            pixelBuffer = sampleBuffer.imageBuffer!.crop(to: cropRect!)
        }

        // get frame attributes
        guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)

        guard let contentRectDict = attachments[.contentRect], var contentRect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary),
              let contentScale = attachments[.contentScale] as? CGFloat,
              let scaleFactor = attachments[.scaleFactor] as? CGFloat else { return nil }

        if cropRect != nil {
            contentRect = cropRect!
        }

        // create frame object
        let frame = Frame.captured(CapturedFrame(surface: surface, contentRect: contentRect, contentScale: contentScale, scaleFactor: scaleFactor))
        return frame
    }

    private func createAudioBuffer(for sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        // Capture audio
        var audioBufferListPointer: UnsafePointer<AudioBufferList>?
        try? sampleBuffer.withAudioBufferList { abl, _ in
            audioBufferListPointer = abl.unsafePointer
        }

        guard let audioBufferList = audioBufferListPointer,
              let streamDescription = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(standardFormatWithSampleRate: streamDescription.mSampleRate, channels: streamDescription.mChannelsPerFrame) else { return nil }

        return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList)
    }

    func stream(_: SCStream, didStopWithError error: Error) {
        continuation?.finish(throwing: error)
    }
}
