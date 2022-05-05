//
//  VideoRecorder.swift
//
//
//  Created by Emil Rakhmangulov on 05.05.2022.
//

import AVFoundation

class VideoRecorder {
    
    private(set) var isWriting = false
    private var videoWriter: AVAssetWriter!
    private var videoWriterInput: AVAssetWriterInput!
    private var audioWriterInput: AVAssetWriterInput!
    private var sessionAtSourceTime: CMTime?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    private let recordingQueue = DispatchQueue(label: "recording")
    typealias VideoRecorderCompletion = (URL?) -> Void

    func startRecording() {
        recordingQueue.async {
            self.reset()
            
            let resultUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).mov")
            guard let currentVideoWriter = try? AVAssetWriter(url: resultUrl, fileType: .mp4) else { return }
            self.videoWriter = currentVideoWriter
            
            self.videoWriter.shouldOptimizeForNetworkUse = false
            
            self.videoWriterInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoWidthKey: 720,
                    AVVideoHeightKey: 1280,
//                    Compression format
                    AVVideoCodecKey: AVVideoCodecType.h264
                ]
            )
            self.videoWriterInput.expectsMediaDataInRealTime = true
            if self.videoWriter.canAdd(self.videoWriterInput) {
//                Adds an input to an asset writer.
                self.videoWriter.add(self.videoWriterInput)
            }
            
            self.audioWriterInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44100,
                    AVEncoderBitRateKey: 128000
                ]
            )
            self.audioWriterInput.expectsMediaDataInRealTime = true
            if self.videoWriter.canAdd(self.audioWriterInput) {
                self.videoWriter.add(self.audioWriterInput)
            }
            
            self.pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: self.videoWriterInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
                ]
            )
            
            self.videoWriter.startWriting()
            self.isWriting = true
        }
    }

    func appendBuffer(_ sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        recordingQueue.async {
            guard self.isWriting else { return }
            
            if self.sessionAtSourceTime == nil && mediaType == .video {
                self.sessionAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.videoWriter.startSession(atSourceTime: self.sessionAtSourceTime!)
            }
            
            switch mediaType {
            case .video where self.videoWriter.inputs.contains(self.videoWriterInput):
                if self.videoWriterInput.isReadyForMoreMediaData {
                    self.videoWriterInput.append(sampleBuffer)
                }
            case .audio where self.videoWriter.inputs.contains(self.audioWriterInput):
                if self.audioWriterInput.isReadyForMoreMediaData && self.sessionAtSourceTime != nil {
                    self.audioWriterInput.append(sampleBuffer)
                }
            default:
                break
            }
        }
    }
    
    func stopRecording(completion: @escaping VideoRecorderCompletion) {
        recordingQueue.async {
            guard self.isWriting else { return }
            self.reset()
            
            self.videoWriter.finishWriting { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    completion(self?.videoWriter?.outputURL)
                }
            }
        }
    }
    
    private func reset() {
        sessionAtSourceTime = nil
        isWriting = false
    }
}
