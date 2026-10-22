import SwiftUI
import Photos

/// OldOS `camera_state`.
enum CameraMode: Equatable {
    case photo
    case video
}

/// The iOS 6 flash capsule: Auto / On / Off (OldOS only drew "Auto").
enum CameraFlash: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case on = "On"
    case off = "Off"

    var id: String { rawValue }
}

/// The Camera Roll opened from the thumbnail of the camera toolbar.
struct CameraRollAlbum: Equatable {
    let title: String

    static let cameraRoll = CameraRollAlbum(title: "Camera Roll")

    /// Oldest first, like OldOS `PhotosObserver`.
    func fetchAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        return PHAsset.fetchAssets(with: options)
    }
}

struct CameraRollViewerRequest: Identifiable, Equatable {
    let id = UUID()
    let album: CameraRollAlbum
    let startIndex: Int
}

/// An iOS 6 action sheet request.
struct CameraRollSheetRequest: Identifiable {
    let id = UUID()
    var title: String? = nil
    let buttons: [CameraRollSheetButton]
}

struct CameraRollSheetButton: Identifiable {
    let id = UUID()
    let title: String
    var destructive: Bool = false
    let action: () -> Void
}

enum CameraRollSystemSheet: Identifiable {
    case share([Any])
    case mail(CameraRollAttachment)
    case message(CameraRollAttachment)

    var id: String {
        switch self {
        case .share: return "share"
        case .mail: return "mail"
        case .message: return "message"
        }
    }
}

/// Viewer / sheet state of the camera roll opened from Camera.
final class CameraRollNavigator: ObservableObject {
    @Published private(set) var viewer: CameraRollViewerRequest?
    @Published var hideBars = false
    @Published var sheet: CameraRollSheetRequest?
    @Published var systemSheet: CameraRollSystemSheet?

    func openViewer(at index: Int) {
        hideBars = false
        withAnimation(.easeOut(duration: 0.35)) {
            viewer = CameraRollViewerRequest(album: .cameraRoll, startIndex: index)
        }
    }

    func closeViewer() {
        withAnimation(.easeOut(duration: 0.35)) {
            viewer = nil
            hideBars = false
        }
    }

    func presentSheet(title: String? = nil, _ buttons: [CameraRollSheetButton]) {
        withAnimation(.easeOut(duration: 0.3)) {
            sheet = CameraRollSheetRequest(title: title, buttons: buttons)
        }
    }

    func dismissSheet() {
        withAnimation(.easeOut(duration: 0.3)) { sheet = nil }
    }
}
