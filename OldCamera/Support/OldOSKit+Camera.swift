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

/// The iOS 6 camera chrome (`camera_tool_bar`, `camera_capsule`,
/// `camera_flipper`) in the two skins: the stock brushed silver (Light) and
/// OldSafari's Private Browsing graphite (Dark).
struct OldCameraTheme {
    let isDark: Bool
    let toolbar: [OldOSStop]
    let toolbarBottom: Color
    let capsuleFill: Color
    let capsuleStroke: Color
    let capsuleText: Color
    /// Flash bolt / mode glyphs: `nil` keeps the original artwork.
    let glyphTint: Color?
    /// The flip toggle and the silver shutter are darkened in Dark.
    let artworkBrightness: Double
    let artworkSaturation: Double
    let invertFlip: Bool
    let shutterIconTint: Color?
    let recessStroke: Color
    let recessHighlight: Color
    let switchTrack: [OldOSStop]
    let switchKnob: [Color]
    let switchKnobStroke: Color

    static func theme(isDark: Bool) -> OldCameraTheme {
        isDark ? .dark : .standard
    }

    /// OldOS values.
    static let standard = OldCameraTheme(
        isDark: false,
        toolbar: [
            OldOSStop(.oldOS(255, 255, 255), 0),
            OldOSStop(.oldOS(123, 125, 131), 1)
        ],
        toolbarBottom: .oldOS(123, 125, 131),
        capsuleFill: Color.white.opacity(0.25 * 0.8),
        capsuleStroke: Color.oldOS(21, 21, 21).opacity(0.85),
        capsuleText: Color.oldOS(21, 21, 21).opacity(0.85),
        glyphTint: nil,
        artworkBrightness: 0,
        artworkSaturation: 1,
        invertFlip: false,
        shutterIconTint: nil,
        recessStroke: .oldOS(73, 74, 76),
        recessHighlight: Color.white.opacity(0.48),
        switchTrack: [
            OldOSStop(.oldOS(103, 104, 107), 0),
            OldOSStop(.oldOS(141, 143, 148), 0.65)
        ],
        switchKnob: [.oldOS(227, 229, 232), .oldOS(119, 121, 126)],
        switchKnobStroke: .oldOS(114, 113, 113)
    )

    /// OldSafari Private Browsing graphite.
    static let dark = OldCameraTheme(
        isDark: true,
        toolbar: [
            OldOSStop(.oldOS(122, 122, 124), 0),
            OldOSStop(.oldOS(96, 96, 98), 0.04),
            OldOSStop(.oldOS(58, 58, 60), 0.51),
            OldOSStop(.oldOS(50, 50, 52), 0.51),
            OldOSStop(.oldOS(28, 28, 30), 1)
        ],
        toolbarBottom: .oldOS(28, 28, 30),
        capsuleFill: Color.black.opacity(0.35),
        capsuleStroke: Color.white.opacity(0.25),
        capsuleText: .oldOS(228, 230, 234),
        glyphTint: .oldOS(228, 230, 234),
        artworkBrightness: -0.42,
        artworkSaturation: 0,
        invertFlip: true,
        shutterIconTint: .oldOS(228, 230, 234),
        recessStroke: .oldOS(10, 10, 11),
        recessHighlight: Color.white.opacity(0.12),
        switchTrack: [
            OldOSStop(.oldOS(28, 28, 30), 0),
            OldOSStop(.oldOS(58, 58, 60), 0.65)
        ],
        switchKnob: [.oldOS(122, 122, 124), .oldOS(58, 58, 60)],
        switchKnobStroke: .oldOS(10, 10, 11)
    )
}

private struct OldCameraThemeKey: EnvironmentKey {
    static let defaultValue: OldCameraTheme = .standard
}

extension EnvironmentValues {
    var oldCameraTheme: OldCameraTheme {
        get { self[OldCameraThemeKey.self] }
        set { self[OldCameraThemeKey.self] = newValue }
    }
}

extension Image {
    /// Draws the artwork as is, or as a template in `tint` (Dark glyphs).
    @ViewBuilder
    func cameraGlyph(_ tint: Color?) -> some View {
        if let tint {
            self.renderingMode(.template).foregroundColor(tint)
        } else {
            self
        }
    }
}

/// "Aspect UI" (Settings › OldCamera, from `Settings.bundle`).
final class CameraSettings: ObservableObject {
    static let shared = CameraSettings()
    static let appearanceKey = "OldCamera.Appearance"

    private var observer: NSObjectProtocol?

    private init() {
        UserDefaults.standard.register(defaults: [Self.appearanceKey: "system"])
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.apply()
        }
    }

    private var style: UIUserInterfaceStyle {
        switch UserDefaults.standard.string(forKey: Self.appearanceKey) {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    /// Applied to every window, so the alerts and system sheets follow too.
    func apply() {
        let style = self.style
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows where window.overrideUserInterfaceStyle != style {
            window.overrideUserInterfaceStyle = style
        }
    }
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
