import SwiftUI
import AVFoundation
import Photos
import Combine

/// The capture engine: OldOS `CameraModel` + the Camera-SwiftUI
/// `CameraService` it wrapped, rewritten for OldCamera.
///
/// Fixed from OldOS:
/// - photos and videos were always saved in portrait: the device orientation
///   now goes into every capture, as on iOS 6;
/// - video was recorded with the photo preset (4:3, low frame size): video
///   mode switches the session to the video preset;
/// - the microphone was opened at launch for every photo: it is attached
///   only in video mode;
/// - flash ("Auto" was only drawn), HDR (only drawn), tap to focus (an
///   invisible view) and pinch zoom (an unused variable) now work;
/// - videos were saved with `UISaveVideoAtPathToSavedPhotosAlbum` without
///   permission handling: both photos and videos go through PhotoKit.
final class CameraService: NSObject, ObservableObject {
    enum Access {
        case unknown
        case granted
        case denied
        case unavailable
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var isRunning = false
    @Published private(set) var mode: CameraMode = .photo
    @Published private(set) var isRecording = false
    @Published private(set) var recordingTime: TimeInterval = 0
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var hasFlash = true
    @Published private(set) var canFlip = true
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 5
    @Published private(set) var isBusy = false
    /// Bumped when the shutter fires (iris animation).
    @Published private(set) var shutterCount = 0
    /// Bumped when switching camera (viewfinder flip animation).
    @Published private(set) var flipCount = 0

    // Camera-SwiftUI `CameraService` / OldOS `CameraModel` state.
    /// The capture buttons are disabled while the session is not usable.
    @Published private(set) var isCameraButtonDisabled = true
    /// Interrupted (call, multitasking, another app) or not running.
    @Published private(set) var isCameraUnavailable = true
    /// Shown when processing a photo takes longer than two seconds.
    @Published private(set) var shouldShowSpinner = false
    /// Flipped on / off when the shutter fires (`willCapturePhoto`).
    @Published private(set) var willCapturePhoto = false
    /// The last photo taken (`CameraModel.photo`).
    @Published private(set) var photo: CameraPhoto?
    /// `showAlertError` / `alertError`.
    @Published var showAlertError = false
    private(set) var alertError = CameraAlertError()

    @Published var flash: CameraFlash = .auto {
        didSet { applyTorch() }
    }
    @Published var hdr = true

    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.iamgasgass.oldcamera.session")
    @objc private dynamic var videoInput: AVCaptureDeviceInput!
    private var audioInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var processors: [Int64: CameraPhotoProcessor] = [:]
    private var configured = false
    private var recordingTimer: Timer?
    private var recordingStart: Date?
    private var orientationObserver: NSObjectProtocol?
    private var observersAdded = false
    private var keyValueObservations: [NSKeyValueObservation] = []

    /// Last known physical orientation (portrait-locked UI, rotating captures).
    @Published private(set) var deviceOrientation: UIDeviceOrientation = .portrait

    override init() {
        super.init()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let orientation = UIDevice.current.orientation
            if orientation.isPortrait || orientation.isLandscape {
                self?.deviceOrientation = orientation
            }
        }
    }

    deinit {
        if let orientationObserver { NotificationCenter.default.removeObserver(orientationObserver) }
    }

    // MARK: Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.access = granted ? .granted : .denied
                    if granted { self?.configureAndRun() }
                }
            }
        default:
            access = .denied
            presentAlert(CameraAlertError(
                title: "Camera Access",
                message: "OldCamera doesn't have permission to use the camera, please change privacy settings",
                primaryButtonTitle: "Settings",
                primaryAction: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                }
            ))
            isCameraUnavailable = true
            isCameraButtonDisabled = true
        }
    }

    private func presentAlert(_ alert: CameraAlertError) {
        let show = {
            self.alertError = alert
            self.showAlertError = true
        }
        if Thread.isMainThread { show() } else { DispatchQueue.main.async(execute: show) }
    }

    /// OldOS `end_session`.
    func stop() {
        if isRecording { toggleRecording() }
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isRunning = false
                self.isCameraButtonDisabled = true
                self.isCameraUnavailable = true
            }
        }
    }

    private func configureAndRun() {
        queue.async {
            if !self.configured {
                self.configureSession()
            }
            guard self.configured else { return }
            self.addObservers()
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.isRunning = running
                self.isCameraUnavailable = !running
                self.isCameraButtonDisabled = !running
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = Self.device(for: .back) ?? Self.device(for: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            configurationFailed()
            return
        }
        session.addInput(input)
        videoInput = input

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            configurationFailed()
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        session.commitConfiguration()
        updatePhotoDimensions()
        configured = true
        publishDevice(device)
        let canFlip = Self.device(for: .front) != nil && Self.device(for: .back) != nil
        DispatchQueue.main.async { self.canFlip = canFlip }
    }

    private func configurationFailed() {
        DispatchQueue.main.async {
            self.access = .unavailable
            self.isCameraButtonDisabled = true
            self.isCameraUnavailable = true
        }
        presentAlert(CameraAlertError(
            title: "Camera Error",
            message: "Camera configuration failed. Either your device camera is not available or other application is using it"
        ))
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInWideAngleCamera, .builtInDualWideCamera, .builtInDualCamera]
            : [.builtInWideAngleCamera, .builtInTrueDepthCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position).devices.first
    }

    private func publishDevice(_ device: AVCaptureDevice) {
        let hasFlash = device.hasFlash || device.hasTorch
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 5)
        let position = device.position
        DispatchQueue.main.async {
            self.hasFlash = hasFlash
            self.maxZoom = max(maxZoom, 1)
            self.position = position
            self.zoom = 1
        }
    }

    // MARK: Mode (OldOS `camera_flipper`)

    func setMode(_ newMode: CameraMode) {
        guard newMode != mode, !isRecording else { return }
        mode = newMode
        if newMode == .video {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                self.queue.async { self.reconfigure(for: newMode) }
            }
        } else {
            queue.async { self.reconfigure(for: newMode) }
        }
    }

    private func reconfigure(for newMode: CameraMode) {
        guard configured else { return }
        session.beginConfiguration()
        switch newMode {
        case .video:
            session.sessionPreset = .high
            if audioInput == nil,
               AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        case .photo:
            if session.outputs.contains(movieOutput) {
                session.removeOutput(movieOutput)
            }
            if let audioInput {
                session.removeInput(audioInput)
                self.audioInput = nil
            }
            session.sessionPreset = .photo
        }
        session.commitConfiguration()
        updatePhotoDimensions()
        DispatchQueue.main.async { self.applyTorch() }
    }

    /// Full-resolution stills for the active camera / format (call on `queue`).
    private func updatePhotoDimensions() {
        guard let device = videoInput?.device,
              let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return }
        if photoOutput.maxPhotoDimensions.width != largest.width || photoOutput.maxPhotoDimensions.height != largest.height {
            photoOutput.maxPhotoDimensions = largest
        }
    }

    // MARK: Flip (OldOS `flipCamera`)

    func flip() {
        guard !isRecording, configured else { return }
        isBusy = true
        isCameraButtonDisabled = true
        flipCount += 1
        queue.async {
            guard let current = self.videoInput else { return }
            let target: AVCaptureDevice.Position = current.device.position == .back ? .front : .back
            guard let device = Self.device(for: target),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.isCameraButtonDisabled = false
                }
                return
            }
            self.session.beginConfiguration()
            self.session.removeInput(current)
            if self.session.canAddInput(input) {
                NotificationCenter.default.removeObserver(self, name: AVCaptureDevice.subjectAreaDidChangeNotification, object: current.device)
                NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: AVCaptureDevice.subjectAreaDidChangeNotification, object: input.device)
                self.session.addInput(input)
                self.videoInput = input
            } else {
                self.session.addInput(current)
            }
            if let connection = self.photoOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
            self.photoOutput.maxPhotoQualityPrioritization = .quality
            self.session.commitConfiguration()
            self.updatePhotoDimensions()
            self.publishDevice(self.videoInput?.device ?? device)
            DispatchQueue.main.async {
                self.isBusy = false
                self.isCameraButtonDisabled = false
                self.applyTorch()
            }
        }
    }

    // MARK: Focus / zoom

    /// Tap to focus and expose at a point of the preview (device coordinates):
    /// Camera-SwiftUI `focus(at:)` (continuous AF / AE at the point), watching
    /// the subject area so focus returns to the centre when the scene changes.
    func focus(at devicePoint: CGPoint) {
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: true)
    }

    /// Camera-SwiftUI `focus(with:exposureMode:at:monitorSubjectAreaChange:)`.
    func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        queue.async {
            guard let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, 1), maxZoom)
        zoom = clamped
        queue.async {
            guard let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = min(clamped, device.maxAvailableVideoZoomFactor)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: Orientation

    private var captureOrientation: AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    // MARK: Photo (OldOS `capturePhoto`)

    func capturePhoto() {
        guard configured, mode == .photo, !isBusy else { return }
        let orientation = captureOrientation
        let flash = self.flash
        let hdr = self.hdr
        isBusy = true
        queue.async {
            if let connection = self.photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = orientation
            }
            var settings = AVCapturePhotoSettings()
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            if let device = self.videoInput?.device, device.hasFlash {
                let wanted: AVCaptureDevice.FlashMode
                switch flash {
                case .auto: wanted = .auto
                case .on: wanted = .on
                case .off: wanted = .off
                }
                if self.photoOutput.supportedFlashModes.contains(wanted) {
                    settings.flashMode = wanted
                }
            }
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            if let format = settings.availablePreviewPhotoPixelFormatTypes.first {
                settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: format]
            }
            // HDR On: the full multi-frame (Smart HDR) pipeline; Off: a single fast frame.
            settings.photoQualityPrioritization = hdr ? self.photoOutput.maxPhotoQualityPrioritization : .speed

            let processor = CameraPhotoProcessor(settings: settings, willCapture: {
                // Flash the screen to signal that a photo was taken.
                DispatchQueue.main.async {
                    self.shutterCount += 1
                    self.willCapturePhoto.toggle()
                    self.willCapturePhoto.toggle()
                }
            }, completion: { processor in
                if let data = processor.photoData {
                    let photo = CameraPhoto(originalData: data)
                    DispatchQueue.main.async { self.photo = photo }
                }
                self.queue.async {
                    self.processors[processor.settings.uniqueID] = nil
                }
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.isCameraButtonDisabled = false
                }
            }, processing: { animate in
                // Animates a spinner while the photo is processing.
                DispatchQueue.main.async { self.shouldShowSpinner = animate }
            })
            self.processors[settings.uniqueID] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    // MARK: KVO & observers (Camera-SwiftUI `addObservers`)

    /// Call on `queue`.
    private func addObservers() {
        guard !observersAdded, let device = videoInput?.device else { return }
        observersAdded = true

        let pressure = observe(\.videoInput.device.systemPressureState, options: .new) { [weak self] _, change in
            guard let state = change.newValue else { return }
            self?.setRecommendedFrameRateRange(for: state)
        }
        keyValueObservations.append(pressure)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(subjectAreaDidChange), name: AVCaptureDevice.subjectAreaDidChangeNotification, object: device)
        center.addObserver(self, selector: #selector(sessionRuntimeError), name: AVCaptureSession.runtimeErrorNotification, object: session)
        center.addObserver(self, selector: #selector(sessionWasInterrupted), name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionInterruptionEnded), name: AVCaptureSession.interruptionEndedNotification, object: session)
    }

    /// When the scene changes, focus / exposure go back to the centre.
    @objc private func subjectAreaDidChange(_ notification: Notification) {
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: CGPoint(x: 0.5, y: 0.5), monitorSubjectAreaChange: false)
    }

    /// If media services were reset, and the last start succeeded, restart.
    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        if error.code == .mediaServicesWereReset {
            queue.async {
                if self.configured {
                    self.session.startRunning()
                    let running = self.session.isRunning
                    DispatchQueue.main.async { self.isRunning = running }
                }
            }
        } else {
            resumeInterruptedSession()
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isCameraUnavailable = true
            self.isCameraButtonDisabled = true
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isCameraUnavailable = false
            self.isCameraButtonDisabled = false
        }
    }

    /// Camera-SwiftUI `resumeInterruptedSession`.
    func resumeInterruptedSession() {
        queue.async {
            self.session.startRunning()
            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.isRunning = running
                self.isCameraUnavailable = !running
                self.isCameraButtonDisabled = !running
            }
            if !running {
                self.presentAlert(CameraAlertError(title: "Camera Error", message: "Unable to resume camera"))
            }
        }
    }

    /// Camera-SwiftUI `setRecommendedFrameRateRangeForPressureState`.
    private func setRecommendedFrameRateRange(for state: AVCaptureDevice.SystemPressureState) {
        guard let device = videoInput?.device else { return }
        let level = state.level
        if level == .serious || level == .critical {
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: Video (OldOS `record`)

    func toggleRecording() {
        guard configured, mode == .video else { return }
        if movieOutput.isRecording || isRecording {
            queue.async { self.movieOutput.stopRecording() }
            stopTimer()
            isRecording = false
            CameraSounds.shared.play(.recordStop, delay: 0.15)
            applyTorch()
            return
        }
        let orientation = captureOrientation
        CameraSounds.shared.play(.recordStart)
        isRecording = true
        recordingTime = 0
        recordingStart = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStart else { return }
            self.recordingTime = Date().timeIntervalSince(start)
        }
        applyTorch()
        queue.async {
            if let connection = self.movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = orientation
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("OldCamera-\(UUID().uuidString).mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStart = nil
    }

    /// In video mode the flash capsule drives the torch (iOS 6: On lights it
    /// while recording, Auto lets iOS decide).
    private func applyTorch() {
        let mode = self.mode
        let flash = self.flash
        let recording = isRecording
        queue.async {
            guard let device = self.videoInput?.device, device.hasTorch else { return }
            let wanted: AVCaptureDevice.TorchMode
            if mode == .video && recording {
                switch flash {
                case .on: wanted = .on
                case .auto: wanted = .auto
                case .off: wanted = .off
                }
            } else {
                wanted = .off
            }
            guard device.isTorchModeSupported(wanted), device.torchMode != wanted else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = wanted
                device.unlockForConfiguration()
            } catch {}
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            if self.isRecording {
                self.isRecording = false
                self.stopTimer()
                self.applyTorch()
            }
        }
        let success = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        guard success else {
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        CameraLibraryWriter.saveVideo(at: outputFileURL)
    }
}

// MARK: - Photo processor (Camera-SwiftUI `PhotoCaptureProcessor`)

final class CameraPhotoProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    let settings: AVCapturePhotoSettings
    private let willCapture: () -> Void
    private let completion: (CameraPhotoProcessor) -> Void
    private let processing: (Bool) -> Void
    private(set) var photoData: Data?
    private var maxPhotoProcessingTime: CMTime?

    init(settings: AVCapturePhotoSettings,
         willCapture: @escaping () -> Void,
         completion: @escaping (CameraPhotoProcessor) -> Void,
         processing: @escaping (Bool) -> Void) {
        self.settings = settings
        self.willCapture = willCapture
        self.completion = completion
        self.processing = processing
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapture()
        // Show a spinner if processing takes more than two seconds.
        if let maxPhotoProcessingTime, maxPhotoProcessingTime > CMTime(seconds: 2, preferredTimescale: 1) {
            processing(true)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        processing(false)
        if error == nil {
            photoData = photo.fileDataRepresentation()
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error == nil, let data = photoData else {
            completion(self)
            return
        }
        CameraLibraryWriter.savePhoto(data, fileType: settings.processedFileType) {
            self.completion(self)
        }
    }
}

// MARK: - Photo (Camera-SwiftUI `Photo`, `AlertError`, `ImageResizer`)

struct CameraPhoto: Identifiable, Equatable {
    let id: String
    let originalData: Data

    init(id: String = UUID().uuidString, originalData: Data) {
        self.id = id
        self.originalData = originalData
    }

    var compressedData: Data? {
        CameraImageResizer(targetWidth: 800).resize(data: originalData)?.jpegData(compressionQuality: 0.5)
    }

    var thumbnailData: Data? {
        CameraImageResizer(targetWidth: 100).resize(data: originalData)?.jpegData(compressionQuality: 0.5)
    }

    var thumbnailImage: UIImage? {
        thumbnailData.flatMap(UIImage.init(data:))
    }

    var image: UIImage? {
        compressedData.flatMap(UIImage.init(data:))
    }
}

struct CameraAlertError {
    var title = ""
    var message = ""
    var primaryButtonTitle = "Accept"
    var secondaryButtonTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil
}

struct CameraImageResizer {
    let targetWidth: CGFloat

    func resize(data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return resize(image: image)
    }

    func resize(image: UIImage) -> UIImage? {
        let scale = targetWidth / max(image.size.width, 1)
        let size = CGSize(width: targetWidth, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Saving

/// Saves captures to the Camera Roll (add-only permission is enough).
enum CameraLibraryWriter {
    private static func authorize(_ completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { new in
                completion(new == .authorized || new == .limited)
            }
        default:
            completion(false)
        }
    }

    static func savePhoto(_ data: Data, fileType: AVFileType?, completion: @escaping () -> Void) {
        authorize { allowed in
            guard allowed else {
                CameraAlert.show(title: "Cannot Save Photo", message: "Allow OldCamera to add photos in Settings › Privacy & Security › Photos.", settingsButton: true)
                completion()
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = fileType?.rawValue
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
            }, completionHandler: { _, _ in
                completion()
            })
        }
    }

    static func saveVideo(at url: URL) {
        authorize { allowed in
            guard allowed else {
                try? FileManager.default.removeItem(at: url)
                CameraAlert.show(title: "Cannot Save Video", message: "Allow OldCamera to add videos in Settings › Privacy & Security › Photos.", settingsButton: true)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: options)
            }, completionHandler: { _, _ in
                try? FileManager.default.removeItem(at: url)
            })
        }
    }
}

// MARK: - Sounds

/// The iOS 6 record start / stop tones (`Resources/Sounds`).
final class CameraSounds {
    enum Sound: String {
        case recordStart = "RecordStart"
        case recordStop = "RecordStop"
    }

    static let shared = CameraSounds()
    private var players: [Sound: AVAudioPlayer] = [:]

    private init() {
        for sound in [Sound.recordStart, .recordStop] {
            if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf"),
               let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players[sound] = player
            }
        }
    }

    func play(_ sound: Sound, delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let player = self.players[sound] else { return }
            player.currentTime = 0
            player.play()
        }
    }
}
