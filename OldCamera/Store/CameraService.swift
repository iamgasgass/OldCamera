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
    /// Toggled when the shutter fires (for the shutter animation).
    @Published private(set) var shutterCount = 0

    @Published var flash: CameraFlash = .auto {
        didSet { applyTorch() }
    }
    @Published var hdr = true

    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.iamgasgass.oldcamera.session")
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var processors: [Int64: CameraPhotoProcessor] = [:]
    private var configured = false
    private var recordingTimer: Timer?
    private var recordingStart: Date?
    private var orientationObserver: NSObjectProtocol?

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
        }
    }

    /// OldOS `end_session`.
    func stop() {
        if isRecording { toggleRecording() }
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func configureAndRun() {
        queue.async {
            if !self.configured {
                self.configureSession()
            }
            guard self.configured else { return }
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = Self.device(for: .back) ?? Self.device(for: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.access = .unavailable }
            return
        }
        session.addInput(input)
        videoInput = input

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.access = .unavailable }
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
        queue.async {
            guard let current = self.videoInput else { return }
            let target: AVCaptureDevice.Position = current.device.position == .back ? .front : .back
            guard let device = Self.device(for: target),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async { self.isBusy = false }
                return
            }
            self.session.beginConfiguration()
            self.session.removeInput(current)
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
            } else {
                self.session.addInput(current)
            }
            self.session.commitConfiguration()
            self.updatePhotoDimensions()
            self.publishDevice(self.videoInput?.device ?? device)
            DispatchQueue.main.async {
                self.isBusy = false
                self.applyTorch()
            }
        }
    }

    // MARK: Focus / zoom

    /// Tap to focus and expose at a point of the preview (device coordinates).
    func focus(at devicePoint: CGPoint) {
        queue.async {
            guard let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
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
            // HDR On: the full multi-frame (Smart HDR) pipeline; Off: a single fast frame.
            settings.photoQualityPrioritization = hdr ? self.photoOutput.maxPhotoQualityPrioritization : .speed

            let processor = CameraPhotoProcessor(settings: settings, willCapture: {
                DispatchQueue.main.async { self.shutterCount += 1 }
            }, completion: { processor in
                self.queue.async {
                    self.processors[processor.settings.uniqueID] = nil
                }
                DispatchQueue.main.async { self.isBusy = false }
            })
            self.processors[settings.uniqueID] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
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
    private var data: Data?

    init(settings: AVCapturePhotoSettings, willCapture: @escaping () -> Void, completion: @escaping (CameraPhotoProcessor) -> Void) {
        self.settings = settings
        self.willCapture = willCapture
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapture()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error == nil {
            data = photo.fileDataRepresentation()
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error == nil, let data else {
            completion(self)
            return
        }
        CameraLibraryWriter.savePhoto(data, fileType: settings.processedFileType) {
            self.completion(self)
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
