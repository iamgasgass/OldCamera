import SwiftUI
import AVFoundation

// OldOS `camera_header`, `camera_capsule`, `camera_tool_bar` and
// `camera_flipper`, with the controls that OldOS only drew now working.

/// Rotation of the glyphs when the phone is turned (iOS 6 rotated the icons,
/// not the interface).
func cameraIconAngle(_ orientation: UIDeviceOrientation) -> Angle {
    switch orientation {
    case .landscapeLeft: return .degrees(90)
    case .landscapeRight: return .degrees(-90)
    case .portraitUpsideDown: return .degrees(180)
    default: return .zero
    }
}

// MARK: - Capsule

/// OldOS `camera_capsule`: the translucent white pill with a dark outline.
struct CameraCapsule<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Capsule()
                .fill(OldCameraSilverChrome.capsuleFill)
                .oldOSStrokeCapsule(OldCameraSilverChrome.capsuleStroke, lineWidth: 0.95)
            content()
        }
    }
}

// MARK: - Header

/// OldOS `camera_header`: flash capsule, HDR capsule, front / back toggle,
/// and the recording time while filming.
struct CameraHeader: View {
    @ObservedObject var camera: CameraService
    @State private var flashExpanded = false

    private let capsuleHeight: CGFloat = 64.0 / 120.0 * 62.0

    var body: some View {
        HStack(spacing: 0) {
            if camera.hasFlash {
                flashCapsule
                    .padding(.leading, 8)
            }
            Spacer(minLength: 0)
            if camera.isRecording {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.35))
                        .oldOSStrokeRoundedRectangle(6, Color.white.opacity(0.25), lineWidth: 0.95)
                        .frame(width: 95, height: 64.0 / 120.0 * 55.0)
                    Text(timeString(camera.recordingTime))
                        .font(OldOSFont.regular(19))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
                .padding(.trailing, 8)
                .transition(.opacity)
            } else if camera.canFlip {
                Button {
                    OldCameraHaptics.tap()
                    withAnimation(.easeInOut(duration: 0.35)) { flashExpanded = false }
                    camera.flip()
                } label: {
                    Image("CameraFlip")
                        .resizable()
                        .frame(width: 65, height: 65.0 / 120.0 * 62.0)
                        .rotationEffect(cameraIconAngle(camera.deviceOrientation))
                        .animation(.easeInOut(duration: 0.3), value: camera.deviceOrientation)
                }
                .buttonStyle(.plain)
                .disabled(camera.isBusy)
                .padding(.trailing, 8)
                .transition(.opacity)
            }
        }
        .overlay(
            HStack {
                Spacer()
                if camera.mode == .photo && !flashExpanded {
                    Button {
                        OldCameraHaptics.tap()
                        camera.hdr.toggle()
                    } label: {
                        CameraCapsule {
                            Text(camera.hdr ? "HDR On" : "HDR Off")
                                .font(OldOSFont.bold(14))
                                .foregroundColor(OldCameraSilverChrome.capsuleText)
                        }
                        .frame(width: 95, height: capsuleHeight)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                Spacer()
            }
        )
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
        .animation(.easeInOut(duration: 0.2), value: camera.mode)
    }

    /// iOS 6: tap the bolt to unfold Auto / On / Off, tap a choice to fold it.
    private var flashCapsule: some View {
        CameraCapsule {
            HStack(spacing: 0) {
                Image("FlashBolt")
                    .rotationEffect(cameraIconAngle(camera.deviceOrientation))
                    .animation(.easeInOut(duration: 0.3), value: camera.deviceOrientation)
                    .padding(.leading, 10)
                if flashExpanded {
                    ForEach(CameraFlash.allCases) { option in
                        Button {
                            OldCameraHaptics.tap()
                            camera.flash = option
                            withAnimation(.easeInOut(duration: 0.25)) { flashExpanded = false }
                        } label: {
                            Text(option.rawValue)
                                .font(OldOSFont.bold(14))
                                .foregroundColor(OldCameraSilverChrome.capsuleText)
                                .opacity(option == camera.flash ? 1 : 0.55)
                                .frame(width: 44, height: capsuleHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 2)
                } else {
                    Text(camera.flash.rawValue)
                        .font(OldOSFont.bold(14))
                        .foregroundColor(OldCameraSilverChrome.capsuleText)
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, 6)
                }
            }
        }
        .frame(width: flashExpanded ? 172 : 80, height: capsuleHeight)
        .contentShape(Capsule())
        .onTapGesture {
            guard !flashExpanded else { return }
            OldCameraHaptics.tap()
            withAnimation(.easeInOut(duration: 0.25)) { flashExpanded = true }
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

// MARK: - Toolbar

/// OldOS `camera_tool_bar`: the brushed silver bar with the last-photo
/// thumbnail, the silver shutter and the photo / video switch. Extended
/// behind the home indicator.
struct CameraToolbar: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var roll: CameraRoll
    let bottomInset: CGFloat
    let openRoll: () -> Void

    @State private var blink = false
    private let blinkTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    HStack {
                        thumbnail
                        Spacer(minLength: 0)
                    }
                    .frame(width: geometry.size.width / 4.5)
                    .padding(.leading, 8)

                    Spacer(minLength: 0)

                    shutter(width: geometry.size.width / 3.25)

                    Spacer(minLength: 0)

                    CameraModeSwitch(camera: camera)
                        .frame(width: geometry.size.width / 4.75, height: 82.0 / 2.0)
                        .padding(.trailing, 8)
                }
                .frame(height: 60)
            }
            .frame(height: 60)
            Color.clear.frame(height: bottomInset)
        }
        .background(
            VStack(spacing: 0) {
                LinearGradient(oldOS: OldCameraSilverChrome.toolbar).frame(height: 60)
                OldCameraSilverChrome.toolbarBottom
            }
        )
        .onReceive(blinkTimer) { _ in
            blink.toggle()
        }
    }

    private var thumbnail: some View {
        Button {
            guard roll.count > 0 else { return }
            OldCameraHaptics.tap()
            openRoll()
        } label: {
            Group {
                if let image = roll.thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("RollPlaceholder")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 41, height: 41)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.black.opacity(0.45), lineWidth: 1.5)
                    .blur(radius: 0.8)
                    .offset(y: 2.0 / 3.0)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            )
            .shadow(color: Color.white.opacity(0.48), radius: 0, x: 0, y: 0.8)
            .oldOSStrokeRoundedRectangle(3, .oldOS(73, 74, 76), lineWidth: 0.33)
            .rotationEffect(cameraIconAngle(camera.deviceOrientation))
            .animation(.easeInOut(duration: 0.3), value: camera.deviceOrientation)
        }
        .buttonStyle(.plain)
    }

    private func shutter(width: CGFloat) -> some View {
        Button {
            switch camera.mode {
            case .photo:
                camera.capturePhoto()
            case .video:
                OldCameraHaptics.press()
                camera.toggleRecording()
            }
        } label: {
            ZStack {
                Image("ShutterSilver")
                    .resizable(capInsets: EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22), resizingMode: .stretch)
                    .frame(width: width, height: 82.0 / 2.0)
                Group {
                    if camera.mode == .photo {
                        Image("ShutterCamera")
                    } else if camera.isRecording && blink {
                        Image("ShutterRecordOn")
                    } else {
                        Image("ShutterRecordOff")
                    }
                }
                .rotationEffect(cameraIconAngle(camera.deviceOrientation))
                .animation(.easeInOut(duration: 0.3), value: camera.deviceOrientation)
            }
        }
        .buttonStyle(CameraShutterStyle())
        .disabled(camera.access != .granted || (camera.mode == .photo && camera.isBusy))
    }
}

/// The shutter darkens slightly while pressed.
struct CameraShutterStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
    }
}

// MARK: - Photo / video switch (`camera_flipper`)

struct CameraModeSwitch: View {
    @ObservedObject var camera: CameraService
    @State private var offset: CGFloat = 0
    @State private var dragging = false

    private let track = LinearGradient(oldOS: [
        OldOSStop(.oldOS(103, 104, 107), 0),
        OldOSStop(.oldOS(141, 143, 148), 0.65)
    ])

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = width - width / 3
            VStack(spacing: 1) {
                HStack {
                    Image("ModeCamera")
                        .rotationEffect(cameraIconAngle(camera.deviceOrientation))
                    Spacer()
                    Image("ModeVideo")
                        .rotationEffect(cameraIconAngle(camera.deviceOrientation))
                }
                .animation(.easeInOut(duration: 0.3), value: camera.deviceOrientation)
                ZStack {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: width, height: 15)
                        .oldOSInnerShadowBackground(Capsule(), track, radius: 0.8, offset: CGPoint(x: 0, y: 2.0 / 3.0), intensity: 0.45)
                        .shadow(color: Color.white.opacity(0.48), radius: 0, x: 0, y: 0.8)
                        .oldOSStrokeCapsule(.oldOS(73, 74, 76), lineWidth: 0.33)
                    Capsule()
                        .fill(LinearGradient(oldOS: [.oldOS(227, 229, 232), .oldOS(119, 121, 126)]))
                        .shadow(color: Color.black.opacity(0.25), radius: 1, x: offset > width / 2 ? -1 : 1, y: 1)
                        .oldOSStrokeCapsule(.oldOS(114, 113, 113), lineWidth: 0.7)
                        .frame(width: width / 3, height: 14)
                        .offset(x: -width / 2 + offset + width / 6)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !camera.isRecording else { return }
                        dragging = true
                        offset = min(max(value.location.x - width / 6, 0), travel)
                    }
                    .onEnded { value in
                        guard !camera.isRecording else { return }
                        dragging = false
                        let moved = abs(value.translation.width) > 4
                        let toVideo: Bool
                        if moved {
                            toVideo = offset > travel / 2
                        } else {
                            // A tap flips to the other side.
                            toVideo = camera.mode == .photo
                        }
                        withAnimation(.linear(duration: 0.1)) {
                            offset = toVideo ? travel : 0
                        }
                        OldCameraHaptics.tap()
                        camera.setMode(toVideo ? .video : .photo)
                    }
            )
            .onAppear { offset = camera.mode == .video ? travel : 0 }
            .onChange(of: camera.mode) { mode in
                guard !dragging else { return }
                withAnimation(.linear(duration: 0.1)) { offset = mode == .video ? travel : 0 }
            }
        }
    }
}
