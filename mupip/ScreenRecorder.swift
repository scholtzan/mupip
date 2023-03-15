//
//  ScreenRecorder.swift
//  mupip
//
//  Created by Anna Scholtz on 2023-01-02.
//

import Accelerate
import AVFAudio
import Cocoa
import Combine
import Foundation
import OSLog
import ScreenCaptureKit
import SwiftUI

enum Frame {
    case captured(CapturedFrame)
    case idle
}

struct CapturedFrame {
    let surface: IOSurface?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
}

struct Portion {
    let window: SCWindow
    let sourceRect: CGRect
}

enum Capture {
    case display(SCDisplay?)
    case window(SCWindow?)
    case portion(Portion?)
}

@MainActor
class ScreenRecorder: ObservableObject, Hashable, Identifiable {
    @AppStorage("refreshFrequency") private var refreshFrequency = DefaultSettings.refreshFrequency
    @AppStorage("inactivityThreshold") private var inactivityThreshold = DefaultSettings.inactivityThreshold

    let id = UUID()
    private var cropRect: CGRect? = nil

    nonisolated static func == (lhs: ScreenRecorder, rhs: ScreenRecorder) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    nonisolated func hash(into hasher: inout Hasher) {
        return hasher.combine(ObjectIdentifier(self))
    }

    private let logger = Logger()

    var onStoppedRunning: ((ScreenRecorder) -> Void)? = nil

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

    @Published var isPlayingAudio = false
    @Published var isInactive = false

    private var isSetup = false
    private var subscriptions = Set<AnyCancellable>()
    private var stream: SCStream?
    private let videoBufferQueue = DispatchQueue(label: "net.scholtzan.mupip.VideoBufferQueue")
    private let audioBufferQueue = DispatchQueue(label: "net.scholtzan.mupip.AudioBufferQueue")
    private var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?
    private var lastUpdated: Date = .init()

    lazy var captureView: CaptureView = .init()

    private var streamConfiguration: SCStreamConfiguration {
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.excludesCurrentProcessAudio = false

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

        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(refreshFrequency))
        return streamConfig
    }

    private var contentFilter: SCContentFilter {
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

    func start() async {
        if !isSetup {
            await record()
            isSetup = true
        }

        do {
            let config = streamConfiguration
            let filter = contentFilter
            isRunning = true
            isPaused = false

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

    func stop(close: Bool) async {
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
        let channelCount = Int(audioBuffer.format.channelCount)
        let length = vDSP_Length(audioBuffer.frameLength)
        var isSilent = true

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
        var max: Float = 0.0
        vDSP_maxv(data, strideFrames, &max, length)

        if max > 0 {
            return false
        }

        return true
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
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first else { return nil }

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

        var pixelBuffer: CVPixelBuffer?

        if cropRect == nil {
            pixelBuffer = sampleBuffer.imageBuffer
        } else {
            pixelBuffer = sampleBuffer.imageBuffer!.crop(to: cropRect!)
        }

        guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }

        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)

        guard let contentRectDict = attachments[.contentRect], var contentRect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary),
              let contentScale = attachments[.contentScale] as? CGFloat,
              let scaleFactor = attachments[.scaleFactor] as? CGFloat else { return nil }

        if cropRect != nil {
            contentRect = cropRect!
        }

        let frame = Frame.captured(CapturedFrame(surface: surface, contentRect: contentRect, contentScale: contentScale, scaleFactor: scaleFactor))

        return frame
    }

    private func createAudioBuffer(for sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
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
