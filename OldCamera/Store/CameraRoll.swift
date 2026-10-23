import SwiftUI
import Photos

/// OldOS `LastPhotoRetriever` + the library the camera roll viewer shows.
/// OldOS re-queried the last photo 0.65 s after the shutter (often before the
/// photo was saved, so the thumbnail lagged one shot behind); the thumbnail
/// now follows the library live.
final class CameraRoll: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = CameraRoll()

    @Published private(set) var thumbnail: UIImage?
    @Published private(set) var count = 0
    @Published private(set) var revision = 0
    @Published private(set) var canRead = false

    private var registered = false

    private override init() {
        super.init()
    }

    func start() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
                DispatchQueue.main.async { self?.reload() }
            }
        } else {
            reload()
        }
    }

    func reload() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        canRead = status == .authorized || status == .limited
        guard canRead else {
            thumbnail = nil
            count = 0
            return
        }
        if !registered {
            PHPhotoLibrary.shared().register(self)
            registered = true
        }
        let assets = CameraRollAlbum.cameraRoll.fetchAssets()
        count = assets.count
        revision += 1
        guard let last = assets.lastObject else {
            thumbnail = nil
            return
        }
        CameraRollImages.thumbnail(for: last, side: 60) { [weak self] image in
            if let image { self?.thumbnail = image }
        }
    }

    /// The thumbnail of the photo just taken, shown before the library
    /// reports it (Camera-SwiftUI `Photo.thumbnailImage`).
    func showCaptured(_ image: UIImage?) {
        if let image { thumbnail = image }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { self.reload() }
    }

    /// Deletes assets; iOS shows its own confirmation.
    func delete(_ assets: [PHAsset], completion: ((Bool) -> Void)? = nil) {
        guard !assets.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }, completionHandler: { success, _ in
            DispatchQueue.main.async { completion?(success) }
        })
    }
}

// MARK: - Images

/// Thumbnail / full-size requests (OldOS `getImageData` / `getMainImage`
/// were synchronous and blocked the UI; these are asynchronous and cached).
enum CameraRollImages {
    static let manager = PHCachingImageManager()

    @discardableResult
    static func thumbnail(for asset: PHAsset, side: CGFloat, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let scale = UIScreen.main.scale
        return manager.requestImage(
            for: asset,
            targetSize: CGSize(width: side * scale, height: side * scale),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    @discardableResult
    static func image(for asset: PHAsset, fitting size: CGSize, completion: @escaping (UIImage?, Bool) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        return PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            completion(image, degraded)
        }
    }

    static func cancel(_ id: PHImageRequestID) {
        manager.cancelImageRequest(id)
        PHImageManager.default().cancelImageRequest(id)
    }
}
