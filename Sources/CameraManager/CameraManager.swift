//
//  CameraManager.swift
//
//
//  Created by Emil Rakhmangulov on 05.05.2022.
//

import AVFoundation
import UIKit

@available(iOS 13.0, *)
public class CameraManager: NSObject {
    
    public override init() {}
    
    //MARK: - Parameters
    
    public var onRecordingDone: ((URL) -> Void) = { _ in }
    @Atomical public var lastImageBuffer: CVImageBuffer?
    public var session = AVCaptureSession()
    
    var videoQueue = DispatchQueue(label: "videoQueue",
                                   qos: .userInitiated,
                                   attributes: .concurrent,
                                   autoreleaseFrequency: .inherit)
    
    let dataOutputQueue = DispatchQueue(label: "videoDataOutputQueue",
                                        qos: .userInitiated,
                                        attributes: [],
                                        autoreleaseFrequency: .workItem)
    
    public let videoOutput = AVCaptureVideoDataOutput()
    public let audioOutput = AVCaptureAudioDataOutput()
    public var activeInput: AVCaptureDeviceInput?
    var recorder = VideoRecorder()
    public var currentDevicePosition = AVCaptureDevice.Position.front
    public var isFrontCamera: Bool {
        return currentDevicePosition == .front
    }
    public var currentVideoOrientation = AVCaptureVideoOrientation.portrait

    public var sessionTorchMode = AVCaptureDevice.TorchMode.off {
        didSet {
            if let input = self.activeInput {
                let device = input.device
                if device.hasTorch, device.torchMode != sessionTorchMode {
                    do {
                        try device.lockForConfiguration()
                        if device.isTorchModeSupported(sessionTorchMode) {
                            device.torchMode = sessionTorchMode
                        }
                        device.unlockForConfiguration()
                    } catch {
                        print("TorchMode failed to lock device for configuration")
                    }
                }
            }
        }
    }
    
    public var torchMode: AVCaptureDevice.TorchMode {
        get {
            return sessionTorchMode
        }
        set {
            sessionTorchMode = newValue
        }
    }
    
    public var currentZoomFactor: Float {
        return Float(activeInput?.device.videoZoomFactor ?? CGFloat(1.0))
    }
    
    public var maxZoomFactor: Float {
        guard let camera = activeInput?.device else { return 1.0 }
        return Float(camera.activeFormat.videoMaxZoomFactor)
    }
    
    public func setupSession() {
        videoQueue.sync {
            session.beginConfiguration()
//            session.sessionPreset = .hd1280x720
            session.sessionPreset = .high
            session.automaticallyConfiguresApplicationAudioSession = false
            
            setupVideoInput(position: currentDevicePosition)
            setupAudioInput()
            setupAudioOutput()
            setupVideoOutput()
            
            setupVideoOrientationIfPossible()
            setupAutofocusIfPossible()
            setupAutofocus()
            ensureMirroring()
            
            session.commitConfiguration()
        }
    }
    
    public func setupPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
    }
    
    public func ensureMirroring() {
        videoOutput.connection(with: .video)?.isVideoMirrored = currentDevicePosition == .front
    }
    
    #warning("Unused Zoom")
    public func setZoomFactor(factor: Float) {
        guard let camera = activeInput?.device else { return }
        let correctedZoomFactor = max(1.0, min(factor, maxZoomFactor))
        
        do {
            try camera.lockForConfiguration()
            camera.videoZoomFactor = CGFloat(correctedZoomFactor)
            camera.unlockForConfiguration()
        } catch {
            print(error)
        }
    }
    
    #warning("Unused Focus")
    public func handleFocusTap(point: CGPoint) {
        var convertedPoint: CGPoint? = nil
        let screenSize = UIScreen.main.bounds.size
        if point != .zero {
            let x = point.y / screenSize.height
            var y = point.x / screenSize.width
            if !isFrontCamera {
                y = 1 - y
            }
            let focusPoint = CGPoint(x: x, y: y)
            convertedPoint = focusPoint
        }
        guard let camera = activeInput?.device else { return }
        
        do {
            try camera.lockForConfiguration()
            
            let focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
            let exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
            let whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .continuousAutoWhiteBalance
            
            if camera.isFocusPointOfInterestSupported && camera.isFocusModeSupported(focusMode) {
                camera.focusPointOfInterest = convertedPoint ?? camera.exposurePointOfInterest
                camera.focusMode = focusMode
            }
            
            if camera.isExposurePointOfInterestSupported && camera.isExposureModeSupported(exposureMode) {
                camera.exposurePointOfInterest = convertedPoint ?? camera.exposurePointOfInterest
                camera.exposureMode = exposureMode
            }
            
            if camera.isWhiteBalanceModeSupported(whiteBalanceMode) {
                camera.whiteBalanceMode = whiteBalanceMode
            }
            
            camera.isSubjectAreaChangeMonitoringEnabled = true
            
            camera.unlockForConfiguration()
        } catch {
            print("Failed to configure focus")
        }
    }
    
    public func setupAutofocus() {
        guard let camera = activeInput?.device else { return }
        do {
            try camera.lockForConfiguration()
                
            let focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
            let exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
            let whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .continuousAutoWhiteBalance
            
            if camera.isFocusModeSupported(focusMode) {
                camera.focusMode = focusMode
            }
            
            if camera.isExposureModeSupported(exposureMode) {
                camera.exposureMode = exposureMode
            }
            
            if camera.isWhiteBalanceModeSupported(whiteBalanceMode) {
                camera.whiteBalanceMode = whiteBalanceMode
            }
            camera.isSubjectAreaChangeMonitoringEnabled = true
            
            camera.unlockForConfiguration()
        } catch {
            print("Failed to configure focus")
        }
    }
    
    #warning("Unused Flip")
    public func flipDevice() {
        if currentDevicePosition == .back {
            currentDevicePosition = .front
        } else {
            currentDevicePosition = .back
        }
        setupSession()
    }
    
    public func startSession() {
        if !session.isRunning {
            videoQueue.sync {
                self.session.startRunning()
            }
        }
    }
    
    public func stopSession() {
        if session.isRunning {
            videoQueue.sync {
                self.session.stopRunning()
            }
        }
    }
    
    public func startRecording() {
        recorder.startRecording()
    }
    
    public func stopRecording() {
        recorder.stopRecording { [weak self] url in
            guard let self = self, let url = url else { return }
            self.onRecordingDone(url)
        }
    }
    
    public func setupAutofocusIfPossible() {
        if let input = self.activeInput {
            let device = input.device
            if device.isSmoothAutoFocusSupported {
                do {
                    try device.lockForConfiguration()
                    device.isSmoothAutoFocusEnabled = true
                    device.unlockForConfiguration()
                } catch {
                    print("Error setting configuration: \(error)")
                }
            }
        }
    }
    
    public func setupVideoOrientationIfPossible() {
        let connection = self.videoOutput.connection(with: .video)
        if connection?.isVideoOrientationSupported ?? false {
            connection?.videoOrientation = self.currentVideoOrientation
        }
    }
    
    public func setupAudioOutput() {
        audioOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }
    }
    
    public func setupAudioInput() {
        guard let mic = AVCaptureDevice.default(for: .audio) else { return }
        do {
            let micInput = try AVCaptureDeviceInput(device: mic)
            if session.canAddInput(micInput) {
                session.addInput(micInput)
            }
        } catch {
            print("Error setting device audio input: \(error)")
        }
    }
    
    public func setupVideoOutput() {
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
    }
    
    public func setupVideoInput(position: AVCaptureDevice.Position) {
        guard let camera = captureDevice(with: position) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            for input in session.inputs {
                for port in input.ports {
                    if port.mediaType == .video {
                        session.removeInput(input)
                        break
                    }
                }
            }
            if session.canAddInput(input) {
                session.addInput(input)
                activeInput = input
                
                do {
                    try input.device.lockForConfiguration()
                    
                    if input.device.isFocusModeSupported(.continuousAutoFocus) {
                        input.device.focusMode = .continuousAutoFocus
                    } else if input.device.isFocusModeSupported(.autoFocus) {
                        input.device.focusMode = .autoFocus
                    }
                    
                    if input.device.isExposureModeSupported(.continuousAutoExposure) {
                        input.device.exposureMode = .continuousAutoExposure
                    } else if input.device.isExposureModeSupported(.autoExpose) {
                        input.device.exposureMode = .autoExpose
                    }
                    
                    if input.device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        input.device.whiteBalanceMode = .continuousAutoWhiteBalance
                    } else if input.device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                        input.device.whiteBalanceMode = .autoWhiteBalance
                    }
                    
                    input.device.unlockForConfiguration()
                } catch {
                    print("cant setup autofocus")
                }
            }
        } catch {
            print("Error setting device video input: \(error)")
        }
    }
    
    public func captureDevice(with position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        currentDevicePosition = position
        var deviceTypes: [AVCaptureDevice.DeviceType] = [AVCaptureDevice.DeviceType.builtInWideAngleCamera]
        deviceTypes.append(.builtInDualCamera)
        
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: position)
        for device in discoverySession.devices {
            if device.deviceType == AVCaptureDevice.DeviceType.builtInDualCamera {
                return device
            }
        }
        return discoverySession.devices.first
    }
}

extension CameraManager: AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let videoConnection = videoOutput.connection(with: .video), videoConnection.isActive,
              let audioConnection = audioOutput.connection(with: .audio), audioConnection.isActive else {
            return
        }

        if output is AVCaptureVideoDataOutput {
            self.recorder.appendBuffer(sampleBuffer, mediaType: .video)
            lastImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        } else {
            self.recorder.appendBuffer(sampleBuffer, mediaType: .audio)
        }
    }
}
