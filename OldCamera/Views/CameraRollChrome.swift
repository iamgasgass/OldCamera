import SwiftUI

// The black translucent iOS 6 chrome of the Camera Roll viewer opened from
// the camera thumbnail: `photos_title_bar`, the black back button
// (`UINavigationBarBlackTranslucentBack`), the viewer toolbar buttons
// (`tool_bar_button`) and the black action sheet (`photo_video_share_view`).

// MARK: - Title bar

/// `photos_title_bar`: 65% black glass over the content, extended behind the
/// status bar / Dynamic Island as iOS 6 black translucent status bar.
struct CameraRollTitleBar<Leading: View, Trailing: View>: View {
    let title: String
    let topInset: CGFloat
    var forward = true
    var titleWidth: CGFloat? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            Color.black.opacity(0.55)
                .frame(height: topInset)

            ZStack {
                LinearGradient(oldOS: OldCameraBlackChrome.translucentBar)
                    .oldOSInnerShadowBottom(color: OldCameraBlackChrome.highlight, radius: 0.025)
                    .oldOSBorder(width: 0.95, edges: [.bottom], color: OldCameraBlackChrome.hairline)
                    .opacity(OldCameraBlackChrome.translucentOpacity)
                    .shadow(color: Color.black.opacity(0.25), radius: 0.25, x: 0, y: -0.5)

                HStack {
                    Spacer()
                    Text(title)
                        .font(OldOSFont.bold(22))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.21), radius: 0, x: 0, y: -1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: titleWidth ?? 200)
                        .id(title)
                        .transition(
                            AnyTransition.asymmetric(
                                insertion: .move(edge: forward ? .trailing : .leading),
                                removal: .move(edge: forward ? .leading : .trailing)
                            ).combined(with: .opacity)
                        )
                    Spacer()
                }

                HStack {
                    leading()
                    Spacer()
                    trailing()
                }
            }
            .frame(height: 60)
        }
    }
}

/// The pointed black back button ("Albums", "Camera Roll").
struct CameraRollBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            OldCameraHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(OldOSFont.bold(13))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.45), radius: 0, x: 0, y: -0.6)
                .lineLimit(1)
                .fixedSize()
                .offset(y: -0.5)
                .padding(.leading, 17)
                .padding(.trailing, 9)
                .frame(height: 30)
                .background(Image("NavBackBlack").resizable())
                .frame(height: 33)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
    }
}

/// OldOS `tool_bar_button`: a bare glyph, centred in its slot.
struct CameraRollToolbarButton: View {
    let image: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                guard enabled else { return }
                OldCameraHaptics.tap()
                action()
            } label: {
                Image(image)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.25)
            Spacer(minLength: 0)
        }
    }
}

/// `photo_destination_tool_bar` background: the same 65% black glass.
struct CameraRollToolbarBackground: View {
    var body: some View {
        LinearGradient(oldOS: OldCameraBlackChrome.translucentBar)
            .oldOSInnerShadowBottom(color: OldCameraBlackChrome.highlight, radius: 0.025)
            .oldOSBorder(width: 0.95, edges: [.top], color: .black)
            .opacity(OldCameraBlackChrome.translucentOpacity)
    }
}

// MARK: - Action sheet

/// OldOS `photo_video_share_view`: the black iOS 6 sheet with silver
/// buttons (red for destructive) and the black Cancel button.
struct CameraRollActionSheet: View {
    var title: String? = nil
    let buttons: [CameraRollSheetButton]
    var bottomInset: CGFloat = 0
    let onCancel: () -> Void

    @State private var shown = false

    private var titleHeight: CGFloat { title == nil ? 0 : 34 }

    private func height(_ available: CGFloat) -> CGFloat {
        min(30 + 28 + titleHeight + CGFloat(buttons.count) * 55 + 50 + 35 + bottomInset, available * 0.92)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { onCancel() }

                ZStack {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(LinearGradient(oldOS: [Color.oldOS(101, 100, 100, 0.88), Color.oldOS(31, 30, 30, 0.88)]))
                            .oldOSInnerShadowBottom(color: Color.white.opacity(0.98), radius: 0.1)
                            .oldOSBorder(width: 1, edges: [.top], color: .black)
                            .frame(height: 30)
                        Rectangle()
                            .fill(LinearGradient(oldOS: [Color.oldOS(21, 20, 20, 0.88), Color.black.opacity(0.9)]))
                    }

                    VStack(spacing: 0) {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                if let title {
                                    Text(title)
                                        .font(OldOSFont.regular(15))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 25)
                                        .frame(height: titleHeight)
                                        .padding(.top, 20)
                                }
                                ForEach(Array(buttons.enumerated()), id: \.element.id) { index, button in
                                    sheetButton(button)
                                        .padding(.top, index == 0 && title == nil ? 28 : 2.5)
                                        .padding(.bottom, 2.5)
                                }
                            }
                        }
                        cancelButton
                            .padding(.top, 10)
                            .padding(.bottom, 25 + bottomInset)
                    }
                }
                .frame(height: height(geometry.size.height))
                .offset(y: shown ? 0 : height(geometry.size.height))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.3)) { shown = true }
        }
    }

    private func bevel<Inner: View>(dimmed: Bool = false, @ViewBuilder inner: () -> Inner) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(oldOS: [.oldOS(3, 3, 3), .oldOS(21, 21, 21), .oldOS(32, 32, 32)]))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(LinearGradient(oldOS: [.oldOS(83, 83, 83), .oldOS(143, 143, 143)]), lineWidth: 0.5)
                )
                .opacity(dimmed ? 0.6 : 1)
            inner()
        }
        .padding([.leading, .trailing], 25)
        .frame(minHeight: 50, maxHeight: 50)
    }

    private func sheetButton(_ button: CameraRollSheetButton) -> some View {
        Button {
            OldCameraHaptics.tap()
            button.action()
        } label: {
            bevel {
                if button.destructive {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(oldOSButtonGradient(.red))
                        .oldOSAddBorder(LinearGradient(oldOS: [Color.white.opacity(0.9), Color.white.opacity(0.25)]), width: 0.4, cornerRadius: 9)
                        .padding(3)
                    Text(button.title)
                        .font(OldOSFont.bold(18))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.6), radius: 0, x: 0, y: -0.6)
                        .lineLimit(1)
                } else {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(oldOS: [
                            OldOSStop(.oldOS(235, 235, 236), 0),
                            OldOSStop(.oldOS(208, 209, 211), 0.52),
                            OldOSStop(.oldOS(192, 193, 196), 0.52),
                            OldOSStop(.oldOS(192, 193, 196), 1)
                        ]))
                        .oldOSAddBorder(LinearGradient(oldOS: [Color.white.opacity(0.9), Color.white.opacity(0.25)]), width: 0.4, cornerRadius: 9)
                        .padding(3)
                    Text(button.title)
                        .font(OldOSFont.bold(18))
                        .foregroundColor(.black)
                        .shadow(color: Color.white.opacity(0.9), radius: 0, x: 0, y: 0.9)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cancelButton: some View {
        Button {
            OldCameraHaptics.tap()
            onCancel()
        } label: {
            bevel(dimmed: true) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(oldOS: [
                        OldOSStop(.oldOS(124, 124, 124), 0),
                        OldOSStop(.oldOS(26, 26, 26), 0.50),
                        OldOSStop(.oldOS(0, 0, 0), 0.53),
                        OldOSStop(.oldOS(0, 0, 0), 1)
                    ]))
                    .oldOSAddBorder(LinearGradient(oldOS: [Color.gray.opacity(0.9), Color.gray.opacity(0.35)]), width: 0.4, cornerRadius: 9)
                    .padding(3)
                    .opacity(0.6)
                Text("Cancel")
                    .font(OldOSFont.bold(18))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.9), radius: 0, x: 0, y: -0.9)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
