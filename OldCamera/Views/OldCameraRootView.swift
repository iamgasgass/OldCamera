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
    /// The iOS 6 iris: closed at launch, opens when the camera runs.
    @State private var irisAperture: CGFloat = 0
    /// The iOS 6 3D flip of the viewfinder when switching camera.
    @State private var previewFlip: Double = 0

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
                .rotation3DEffect(.degrees(previewFlip), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                // The viewfinder fills the area above the silver toolbar.
                .frame(width: geometry.size.width, height: max(geometry.size.height - 60 - bottomInset, 1))
                .frame(maxHeight: .infinity, alignment: .top)

                if let focusPoint {
                    CameraFocusSquare()
                        .id(focusID)
                        .position(focusPoint)
                        .allowsHitTesting(false)
                }

                CameraIris(
                    aperture: irisAperture,
                    center: CGPoint(x: geometry.size.width / 2, y: (geometry.size.height - 60 - bottomInset) / 2)
                )
                .allowsHitTesting(false)

                if camera.access == .denied || camera.access == .unavailable {
                    accessMessage
                }

                if camera.shouldShowSpinner {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.8)
                        .allowsHitTesting(false)
                }

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
        .onChange(of: camera.photo) { photo in
            let roll = self.roll
            DispatchQueue.global(qos: .userInitiated).async {
                let thumbnail = photo?.thumbnailImage
                DispatchQueue.main.async { roll.showCaptured(thumbnail) }
            }
        }
        .alert(isPresented: $camera.showAlertError) {
            let error = camera.alertError
            if let secondary = error.secondaryButtonTitle {
                return Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    primaryButton: .default(Text(error.primaryButtonTitle)) { error.primaryAction?() },
                    secondaryButton: .cancel(Text(secondary)) { error.secondaryAction?() }
                )
            }
            return Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text(error.primaryButtonTitle)) { error.primaryAction?() }
            )
        }
        .onChange(of: camera.isRunning) { running in
            if running {
                openIris(after: 0.15)
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { irisAperture = 0 }
            }
        }
        .onChange(of: camera.flipCount) { _ in
            flipPreview()
        }
        .onChange(of: camera.shutterCount) { _ in
            // iOS 6: the iris snaps shut on the shutter and opens again.
            withAnimation(.easeIn(duration: 0.12)) { irisAperture = 0 }
            openIris(after: 0.22)
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

    private func openIris(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard camera.isRunning else { return }
            withAnimation(.easeOut(duration: 0.4)) { irisAperture = 1 }
        }
    }

    private func flipPreview() {
        withAnimation(.easeIn(duration: 0.22)) { previewFlip = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { previewFlip = -90 }
            withAnimation(.easeOut(duration: 0.28)) { previewFlip = 0 }
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
