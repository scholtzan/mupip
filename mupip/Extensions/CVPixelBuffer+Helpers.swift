//
//  CVPixelBuffer+Helpers.swift
//  mupip
//
//  Created by Anna Scholtz on 2023-02-11.
//

import Accelerate
import Cocoa
import Foundation

extension CVPixelBuffer {
    // based on https://github.com/hollance/CoreMLHelpers/blob/179ba6239886d2bc789430d6e466c54fddbbb654/CoreMLHelpers/CVPixelBuffer%2BResize.swift
    func crop(to rect: CGRect) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else {
            return nil
        }

        let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)

        let imageChannels = 4
        let startPos = Int(rect.origin.y) * inputImageRowBytes + imageChannels * Int(rect.origin.x)
        let outWidth = UInt(rect.width)
        let outHeight = UInt(rect.height)
        let croppedImageRowBytes = Int(outWidth) * imageChannels

        var inBuffer = vImage_Buffer()
        inBuffer.height = outHeight
        inBuffer.width = outWidth
        inBuffer.rowBytes = inputImageRowBytes

        inBuffer.data = baseAddress + UnsafeMutableRawPointer.Stride(startPos)

        guard let croppedImageBytes = malloc(Int(outHeight) * croppedImageRowBytes) else {
            return nil
        }

        var outBuffer = vImage_Buffer(data: croppedImageBytes, height: outHeight, width: outWidth, rowBytes: croppedImageRowBytes)

        let scaleError = vImageScale_ARGB8888(&inBuffer, &outBuffer, nil, vImage_Flags(0))

        guard scaleError == kvImageNoError else {
            free(croppedImageBytes)
            return nil
        }

        return croppedImageBytes.toCVPixelBuffer(pixelBuffer: self, targetWith: Int(outWidth), targetHeight: Int(outHeight), targetImageRowBytes: croppedImageRowBytes)
    }

    // based on https://github.com/hollance/CoreMLHelpers/blob/179ba6239886d2bc789430d6e466c54fddbbb654/CoreMLHelpers/CVPixelBuffer+Create.swift
    func copyToMetalCompatible() -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            String(kCVPixelBufferOpenGLCompatibilityKey): true,
            String(kCVPixelBufferIOSurfacePropertiesKey): [:],
        ]
        return deepCopy(withAttributes: attributes)
    }

    func deepCopy(withAttributes attributes: [String: Any] = [:]) -> CVPixelBuffer? {
        let srcPixelBuffer = self
        let srcFlags: CVPixelBufferLockFlags = .readOnly
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(srcPixelBuffer, srcFlags) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(srcPixelBuffer, srcFlags) }

        var combinedAttributes: [String: Any] = [:]

        // Copy attachment attributes.
        if let attachments = CVBufferCopyAttachments(srcPixelBuffer, .shouldPropagate) as? [String: Any] {
            for (key, value) in attachments {
                combinedAttributes[key] = value
            }
        }

        // Add user attributes.
        combinedAttributes = combinedAttributes.merging(attributes) { $1 }

        var maybePixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         CVPixelBufferGetWidth(srcPixelBuffer),
                                         CVPixelBufferGetHeight(srcPixelBuffer),
                                         CVPixelBufferGetPixelFormatType(srcPixelBuffer),
                                         combinedAttributes as CFDictionary,
                                         &maybePixelBuffer)

        guard status == kCVReturnSuccess, let dstPixelBuffer = maybePixelBuffer else {
            return nil
        }

        let dstFlags = CVPixelBufferLockFlags(rawValue: 0)
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(dstPixelBuffer, dstFlags) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(dstPixelBuffer, dstFlags) }

        for plane in 0 ... max(0, CVPixelBufferGetPlaneCount(srcPixelBuffer) - 1) {
            if let srcAddr = CVPixelBufferGetBaseAddressOfPlane(srcPixelBuffer, plane),
               let dstAddr = CVPixelBufferGetBaseAddressOfPlane(dstPixelBuffer, plane)
            {
                let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(srcPixelBuffer, plane)
                let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(dstPixelBuffer, plane)

                for h in 0 ..< CVPixelBufferGetHeightOfPlane(srcPixelBuffer, plane) {
                    let srcPtr = srcAddr.advanced(by: h * srcBytesPerRow)
                    let dstPtr = dstAddr.advanced(by: h * dstBytesPerRow)
                    dstPtr.copyMemory(from: srcPtr, byteCount: srcBytesPerRow)
                }
            }
        }
        return dstPixelBuffer
    }
}

extension UnsafeMutableRawPointer {
    // Converts the vImage buffer to CVPixelBuffer
    func toCVPixelBuffer(pixelBuffer: CVPixelBuffer, targetWith: Int, targetHeight: Int, targetImageRowBytes: Int) -> CVPixelBuffer? {
        let pixelBufferType = CVPixelBufferGetPixelFormatType(pixelBuffer)

        let releaseCallBack: CVPixelBufferReleaseBytesCallback = { _, pointer in
            if let pointer = pointer {
                free(UnsafeMutableRawPointer(mutating: pointer))
            }
        }

        var targetPixelBuffer: CVPixelBuffer?
        let conversionStatus = CVPixelBufferCreateWithBytes(nil, targetWith, targetHeight, pixelBufferType, self, targetImageRowBytes, releaseCallBack, nil, nil, &targetPixelBuffer)

        guard conversionStatus == kCVReturnSuccess else {
            free(self)
            return nil
        }

        return targetPixelBuffer?.copyToMetalCompatible()
    }
}
