import SwiftUI
import Photos

/// OldOS `photo_destination` + `photo_destination_tool_bar`: the photo on
/// black, "3 of 120" in the black glass title bar with the album back
/// button, and the toolbar with Action, Previous, Play / Pause, Next and
/// Trash. Tapping the photo hides / shows the bars (and the status bar).
struct CameraRollViewerView: View {
    @EnvironmentObject private var navigator: CameraRollNavigator
    @ObservedObject private var library = CameraRoll.shared
    @StateObject private var model = CameraRollViewerModel()
    let request: CameraRollViewerRequest
    let topInset: CGFloat
    let bottomInset: CGFloat

    var body: some View {
        ZStack {
            Color.black
            CameraRollPagerView(model: model)

            VStack(spacing: 0) {
                CameraRollTitleBar(
                    title: model.count > 0 ? "\(model.index + 1) of \(model.count)" : "",
                    topInset: topInset,
                    titleWidth: 140
                ) {
                    CameraRollBackButton(title: "Camera") {
                        model.teardown()
                        navigator.closeViewer()
                    }
                } trailing: {
                    EmptyView()
                }
                Spacer()
                toolbar
            }
            .opacity(navigator.hideBars ? 0 : 1)
            .allowsHitTesting(!navigator.hideBars)
        }
        .onAppear {
            let nav = navigator
            model.onTap = { [weak nav] in
                guard let nav else { return }
                withAnimation(.linear(duration: nav.hideBars ? 0.1 : 0.25)) {
                    nav.hideBars.toggle()
                }
            }
            model.onEmpty = { [weak nav] in
                nav?.closeViewer()
            }
            model.onSlideshowChange = { [weak nav] running in
                withAnimation(.linear(duration: 0.25)) {
                    nav?.hideBars = running
                }
            }
            model.configure(album: request.album, startIndex: request.startIndex)
        }
        .onDisappear {
            model.teardown()
        }
        .onChange(of: library.revision) { _ in
            model.reload()
        }
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CameraRollToolbarButton(image: "BarAction") {
                    if let asset = model.currentAsset {
                        CameraRollActions.presentShareOptions(for: asset, navigator: navigator)
                    }
                }
                Spacer()
                CameraRollToolbarButton(image: "BarPrevious", enabled: model.index > 0) {
                    model.previous()
                }
                CameraRollToolbarButton(image: model.isPlaying ? "BarPause" : "BarPlay") {
                    model.togglePlay()
                }
                CameraRollToolbarButton(image: "BarNext", enabled: model.index + 1 < model.count) {
                    model.next()
                }
                Spacer()
                CameraRollToolbarButton(image: "BarTrash") {
                    if let asset = model.currentAsset {
                        CameraRollActions.confirmDelete([asset], navigator: navigator)
                    }
                }
            }
            .frame(height: 45)
            Color.clear.frame(height: bottomInset)
        }
        .background(CameraRollToolbarBackground())
    }
}
