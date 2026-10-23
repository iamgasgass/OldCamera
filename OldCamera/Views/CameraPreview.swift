import SwiftUI
import AVFoundation

/// Camera-SwiftUI `CameraPreview`: the live `AVCaptureVideoPreviewLayer`,
/// aspect-filled and portrait. The tap recogniser of the original posted a
/// focus point to an invisible view; taps and pinches are now reported so
/// OldCamera can focus, show the iOS 6 focus square and zoom.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (_ layerPoint: CGPoint, _ devicePoint: CGPoint) -> Void
    var onPinch: (_ scale: CGFloat, _ ended: Bool) -> Void

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }

        var onTap: ((CGPoint, CGPoint) -> Void)?
        var onPinch: ((CGFloat, Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            previewLayer.videoGravity = .resizeAspectFill
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: self)
            let device = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
            onTap?(point, device)
        }

        @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .changed:
                onPinch?(gesture.scale, false)
            case .ended, .cancelled, .failed:
                onPinch?(gesture.scale, true)
            default:
                break
            }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        view.onTap = onTap
        view.onPinch = onPinch
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onTap = onTap
        uiView.onPinch = onPinch
        if let connection = uiView.previewLayer.connection, connection.isVideoOrientationSupported, connection.videoOrientation != .portrait {
            connection.videoOrientation = .portrait
        }
    }
}

/// The iOS 6 focus square: a blue box with ticks at the middle of each side
/// that shrinks into place and blinks.
struct CameraFocusSquare: View {
    @State private var scale: CGFloat = 1.6
    @State private var blink = false

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Color.oldOS(70, 160, 255), lineWidth: 1.5)
            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height
                Path { path in
                    path.move(to: CGPoint(x: w / 2, y: 0)); path.addLine(to: CGPoint(x: w / 2, y: 7))
                    path.move(to: CGPoint(x: w / 2, y: h)); path.addLine(to: CGPoint(x: w / 2, y: h - 7))
                    path.move(to: CGPoint(x: 0, y: h / 2)); path.addLine(to: CGPoint(x: 7, y: h / 2))
                    path.move(to: CGPoint(x: w, y: h / 2)); path.addLine(to: CGPoint(x: w - 7, y: h / 2))
                }
                .stroke(Color.oldOS(70, 160, 255), lineWidth: 1.5)
            }
        }
        .shadow(color: Color.black.opacity(0.4), radius: 1)
        .frame(width: 76, height: 76)
        .scaleEffect(scale)
        .opacity(blink ? 0.35 : 1)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { scale = 1 }
            withAnimation(.easeInOut(duration: 0.18).repeatCount(4, autoreverses: true).delay(0.3)) {
                blink = true
            }
        }
    }
}
