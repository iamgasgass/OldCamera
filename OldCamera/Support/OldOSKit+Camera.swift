import SwiftUI
import UIKit

// OldOS drawing helpers needed by the Camera screens that OldSafari never used.
// `OldOSKit.swift` is shared verbatim with OldSafari; additions live here.

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, content: (Self) -> Content) -> some View {
        if condition {
            content(self)
        } else {
            self
        }
    }

    /// OldOS `animationsDisabled()`.
    func oldOSAnimationsDisabled() -> some View {
        transaction { $0.animation = nil }
    }
}

/// OldOS `tool_bar_button_type` (the families used by the camera roll sheets).
enum OldOSButtonType {
    case black
    case red
}

/// OldOS `returnLinearGradient(_:)`, values copied 1:1.
func oldOSButtonGradient(_ type: OldOSButtonType) -> LinearGradient {
    switch type {
    case .black:
        return LinearGradient(oldOS: [
            OldOSStop(.oldOS(95, 95, 95), 0),
            OldOSStop(.oldOS(32, 32, 32), 0.51),
            OldOSStop(.oldOS(7.5, 7.5, 7.5), 0.51),
            OldOSStop(.oldOS(7.5, 7.5, 7.5), 1)
        ])
    case .red:
        return LinearGradient(oldOS: [
            OldOSStop(.oldOS(239, 135, 142), 0),
            OldOSStop(.oldOS(199, 52, 63), 0.48),
            OldOSStop(.oldOS(189, 20, 33), 0.49),
            OldOSStop(.oldOS(189, 20, 33), 1)
        ])
    }
}

/// The black translucent iOS 6 chrome of the camera roll viewer
/// (`photos_title_bar`, `photo_destination_tool_bar`).
enum OldCameraBlackChrome {
    static let translucentBar: [OldOSStop] = [
        OldOSStop(.oldOS(0, 0, 0), 0),
        OldOSStop(.oldOS(84, 84, 84), 0.005),
        OldOSStop(.oldOS(59, 59, 59), 0.04),
        OldOSStop(.oldOS(29, 29, 29), 0.5),
        OldOSStop(.oldOS(7.5, 7.5, 7.5), 0.51),
        OldOSStop(.oldOS(7.5, 7.5, 7.5), 1)
    ]
    static let translucentOpacity = 0.65
    static let hairline = Color.oldOS(45, 48, 51)
    static let highlight = Color.oldOS(230, 230, 230)
}

/// The silver iOS 6 camera chrome (`camera_tool_bar`, `camera_capsule`).
enum OldCameraSilverChrome {
    static let toolbar: [OldOSStop] = [
        OldOSStop(.oldOS(255, 255, 255), 0),
        OldOSStop(.oldOS(123, 125, 131), 1)
    ]
    static let toolbarBottom = Color.oldOS(123, 125, 131)
    static let capsuleFill = Color.white.opacity(0.25 * 0.8)
    static let capsuleStroke = Color.oldOS(21, 21, 21).opacity(0.85)
    static let capsuleText = Color.oldOS(21, 21, 21).opacity(0.85)
}

enum OldCameraHaptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func press() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

extension OldOSScreen {
    static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow }) ?? windows.first
    }

    static var topController: UIViewController? {
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

enum CameraAlert {
    static func show(title: String, message: String, settingsButton: Bool = false) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            if settingsButton, let url = URL(string: UIApplication.openSettingsURLString) {
                alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
                    UIApplication.shared.open(url)
                })
            }
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            OldOSScreen.topController?.present(alert, animated: true)
        }
    }
}
