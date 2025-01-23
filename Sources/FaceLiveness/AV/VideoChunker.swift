//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AVFoundation
import CoreImage
import UIKit

final class VideoChunker {
  var state = State.pending
  let assetWriter: AVAssetWriter
  let assetWriterDelegate: AssetWriterDelegate
  let assetWriterInput: AVAssetWriterInput
  let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
  var startTimeSeconds: Double?
  var provideSingleFrame: ((UIImage) -> Void)?
  var onSingleFrameCaptured: ((UIImage) -> Void)?

  init(
    assetWriter: AVAssetWriter,
    assetWriterDelegate: AssetWriterDelegate,
    assetWriterInput: AVAssetWriterInput,
    onSingleFrameCaptured: ((UIImage) -> Void)? = nil
  ) {
    self.assetWriter = assetWriter
    self.assetWriterDelegate = assetWriterDelegate
    self.assetWriterInput = assetWriterInput
    self.pixelBufferAdaptor = .init(assetWriterInput: assetWriterInput)
    self.assetWriterInput.expectsMediaDataInRealTime = true
    self.assetWriter.delegate = assetWriterDelegate
    self.assetWriter.add(assetWriterInput)
    self.onSingleFrameCaptured = onSingleFrameCaptured
  }

  func start() {
    guard state == .pending else { return }
    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: .zero)
    state = .writing
  }

  func finish(singleFrame: @escaping (UIImage) -> Void) {
    self.provideSingleFrame = singleFrame
    state = .awaitingSingleFrame

    // explicitly calling `endSession` is unnecessary
    if assetWriter.status != .completed {
      assetWriter.finishWriting {}
    }
  }

  private func singleFrameToUIImage(from buffer: CVPixelBuffer) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: buffer)
    let context = CIContext()
    // Must create CGIMage to correctly render the UI Image
    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
      return UIImage(cgImage: cgImage)
    }
    return nil
  }

  func consume(_ buffer: CMSampleBuffer) {
    if state == .awaitingSingleFrame {
      guard let imageBuffer = buffer.imageBuffer else { return }
      let singleFrame = singleFrame(from: imageBuffer)
      provideSingleFrame?(singleFrame)
      if let uiImage = singleFrameToUIImage(from: imageBuffer) {
        onSingleFrameCaptured?(uiImage)
      }
      state = .complete
    }

    guard state == .writing else { return }
    if assetWriterInput.isReadyForMoreMediaData {
      let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
      if startTimeSeconds == nil { startTimeSeconds = timestamp }
      guard let startTimeSeconds else {
        return
      }
      let presentationTime = CMTime(seconds: timestamp - startTimeSeconds, preferredTimescale: 600)
      guard let imageBuffer = buffer.imageBuffer else { return }

      pixelBufferAdaptor.append(
        imageBuffer,
        withPresentationTime: presentationTime
      )
    }
  }

  private func singleFrame(from buffer: CVPixelBuffer) -> UIImage {
    let ciImage = CIImage(cvPixelBuffer: buffer)
    let uiImage = UIImage(ciImage: ciImage)
    return uiImage
  }

}
