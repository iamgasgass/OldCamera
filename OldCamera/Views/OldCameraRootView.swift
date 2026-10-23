import SwiftUI
import AVFoundation

/// OldOS `Camera`: the live preview under the header capsules and the
/// silver toolbar. Full screen on modern devices: the preview fills the
/// display, the header sits below the Dynamic Island and the toolbar runs
/// down behind the home indicator. The thumbnail opens the Camera Roll
/// viewer (inert in OldOS).
struct OldCameraRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var camera = CameraService()
    @StateObject private var rollNavigator = CameraRollNavigator()
    @StateObject private var safeArea = OldOSSafeArea()
    @ObservedObject private var roll = CameraRoll.shared

    @State private var focusPoint: CGPoint?
    @State private var focusID = UUID()
    @State private var pinchStartZoom: CGFloat?
    @State private var showZoom = false
    @State private var zoomHideWork: DispatchWorkItem?
    @State private var shutterOpacity: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let topInset = max(geometry.safeAreaInsets.top, safeArea.insets.top)
            let bottomInset = max(geometry.safeAreaInsets.bottom, safeArea.insets.bottom)

            ZStack {
                Color.black

                CameraPreview(session: camera.session, onTap: { point, device in
                    focus(at: point, device: device)
                }, onPinch: { scale, ended in
                    pinch(scale, ended: ended)
                })

                if let focusPoint {
                    CameraFocusSquare()
                        .id(focusID)
                        .position(focusPoint)
                        .allowsHitTesting(false)
                }

                if camera.access == .denied || camera.access == .unavailable {
                    accessMessage
                }

                Color.black
                    .opacity(shutterOpacity)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    CameraHeader(camera: camera)
                        .padding(.top, max(topInset, 20) + 10)
                    Spacer()
                    if showZoom {
                        CameraZoomSlider(camera: camera) {
                            scheduleZoomHide()
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                    }
                    CameraToolbar(camera: camera, roll: roll, bottomInset: bottomInset) {
                        rollNavigator.openViewer(at: max(roll.count - 1, 0))
                    }
                }

                if let viewer = rollNavigator.viewer {
                    CameraRollViewerView(request: viewer, topInset: topInset, bottomInset: bottomInset)
                        .id(viewer.id)
                        .transition(.move(edge: .bottom))
                        .zIndex(10)
                }

                if let sheet = rollNavigator.sheet {
                    CameraRollActionSheet(
                        title: sheet.title,
                        buttons: sheet.buttons,
                        bottomInset: bottomInset,
                        onCancel: { rollNavigator.dismissSheet() }
                    )
                    .id(sheet.id)
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear { safeArea.refresh() }
        }
        .ignoresSafeArea()
        .environment(\.oldCameraTheme, OldCameraTheme.theme(isDark: colorScheme == .dark))
        .environmentObject(rollNavigator)
        .sheet(item: $rollNavigator.systemSheet) { sheet in
            switch sheet {
            case .share(let items):
                CameraRollShareSheet(items: items)
            case .mail(let attachment):
                CameraRollMailComposer(attachment: attachment).ignoresSafeArea()
            case .message(let attachment):
                CameraRollMessageComposer(attachment: attachment).ignoresSafeArea()
            }
        }
        .onAppear {
            CameraSettings.shared.apply()
            camera.start()
            roll.start()
            updateStatusBar()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                CameraSettings.shared.apply()
                if rollNavigator.viewer == nil { camera.start() }
                roll.reload()
            case .background:
                camera.stop()
            default:
                break
            }
        }
        .onChange(of: rollNavigator.viewer) { viewer in
            // The preview pauses behind the Camera Roll, like iOS 6.
            if viewer == nil {
                camera.start()
            } else {
                camera.stop()
            }
            updateStatusBar()
        }
        .onChange(of: rollNavigator.hideBars) { _ in updateStatusBar() }
        .onChange(of: camera.shutterCount) { _ in
            shutterOpacity = 1
            withAnimation(.easeOut(duration: 0.35)) { shutterOpacity = 0 }
        }
    }

    private var accessMessage: some View {
        VStack(spacing: 10) {
            Text(camera.access == .denied ? "No Access to Camera" : "Camera Unavailable")
                .font(OldOSFont.bold(20))
                .foregroundColor(.white)
            Text(camera.access == .denied
                 ? "Allow OldCamera to use the camera in Settings › Privacy & Security › Camera."
                 : "The camera is not available on this device or is in use by another app.")
                .font(OldOSFont.bold(14))
                .foregroundColor(.oldOS(180, 180, 184))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .onTapGesture {
            if camera.access == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func updateStatusBar() {
        CameraStatusBar.shared.hidden = rollNavigator.viewer == nil || rollNavigator.hideBars
    }

    // MARK: Focus / zoom

    private func focus(at point: CGPoint, device: CGPoint) {
        guard camera.isRunning else { return }
        camera.focus(at: device)
        focusID = UUID()
        focusPoint = point
        let id = focusID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if focusID == id {
                withAnimation(.easeOut(duration: 0.2)) { focusPoint = nil }
            }
        }
    }

    private func pinch(_ scale: CGFloat, ended: Bool) {
        guard camera.isRunning else { return }
        if pinchStartZoom == nil { pinchStartZoom = camera.zoom }
        camera.setZoom((pinchStartZoom ?? 1) * scale)
        withAnimation(.easeOut(duration: 0.2)) { showZoom = true }
        if ended {
            pinchStartZoom = nil
            scheduleZoomHide()
        } else {
            zoomHideWork?.cancel()
        }
    }

    private func scheduleZoomHide() {
        zoomHideWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) { showZoom = false }
        }
        zoomHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}

/// The iOS 6 zoom slider ("−  ●——  +") shown while zooming.
struct CameraZoomSlider: View {
    @ObservedObject var camera: CameraService
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("−")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: -1)
            GeometryReader { geometry in
                let width = geometry.size.width
                let progress = camera.maxZoom > 1 ? (camera.zoom - 1) / (camera.maxZoom - 1) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.45))
                        .oldOSStrokeCapsule(Color.white.opacity(0.55), lineWidth: 1)
                        .frame(height: 6)
                    Circle()
                        .fill(LinearGradient(oldOS: [.oldOS(250, 250, 250), .oldOS(170, 172, 176)]))
                        .overlay(Circle().stroke(Color.oldOS(90, 90, 92), lineWidth: 0.6))
                        .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 1)
                        .frame(width: 24, height: 24)
                        .offset(x: (width - 24) * progress)
                }
                .frame(height: 28)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let fraction = min(max((value.location.x - 12) / max(width - 24, 1), 0), 1)
                        camera.setZoom(1 + fraction * (camera.maxZoom - 1))
                        onChange()
                    }
                )
            }
            .frame(height: 28)
            Text("+")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: -1)
        }
    }
}
