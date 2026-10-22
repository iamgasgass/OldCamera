import UIKit
import SwiftUI
import Photos
import AVFoundation

/// Drives the full-screen viewer (OldOS `photo_destination`): one page per
/// asset in a `UIPageViewController`, so photos can be swiped like on iOS 6.
/// Pages show the photo at its normal size (aspect fit — OldOS filled and
/// cropped the screen), zoom with pinch / double tap, and play videos.
final class CameraRollViewerModel: NSObject, ObservableObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    @Published private(set) var index = 0
    @Published private(set) var count = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentIsVideo = false
    @Published private(set) var slideshow = false

    let pager = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: [.interPageSpacing: 20]
    )

    private(set) var album: CameraRollAlbum = .cameraRoll
    private(set) var assets: PHFetchResult<PHAsset> = PHAsset.fetchAssets(withLocalIdentifiers: [], options: nil)
    private var configured = false
    private var slideshowTimer: Timer?

    var onTap: (() -> Void)?
    var onEmpty: (() -> Void)?
    var onSlideshowChange: ((Bool) -> Void)?

    override init() {
        super.init()
        pager.dataSource = self
        pager.delegate = self
        pager.view.backgroundColor = .black
    }

    var currentAsset: PHAsset? {
        index < assets.count ? assets.object(at: index) : nil
    }

    private var currentPage: CameraRollPageController? {
        pager.viewControllers?.first as? CameraRollPageController
    }

    // MARK: Setup

    func configure(album: CameraRollAlbum, startIndex: Int) {
        guard !configured else { return }
        configured = true
        self.album = album
        assets = album.fetchAssets()
        count = assets.count
        guard count > 0 else {
            onEmpty?()
            return
        }
        show(index: min(max(startIndex, 0), count - 1), direction: .forward, animated: false)
    }

    /// Library changed (deletion, new photo): keep the current asset if it
    /// still exists, otherwise stay at the same position.
    func reload() {
        guard configured else { return }
        let currentID = currentAsset?.localIdentifier
        let previousIndex = index
        assets = album.fetchAssets()
        count = assets.count
        guard count > 0 else {
            stopSlideshow()
            onEmpty?()
            return
        }
        var newIndex = min(previousIndex, count - 1)
        if let currentID {
            for candidate in [previousIndex, previousIndex - 1, previousIndex + 1] where candidate >= 0 && candidate < count {
                if assets.object(at: candidate).localIdentifier == currentID {
                    newIndex = candidate
                    break
                }
            }
        }
        if assets.object(at: newIndex).localIdentifier != currentID || currentPage == nil {
            show(index: newIndex, direction: .forward, animated: false)
        } else {
            index = newIndex
            currentPage?.index = newIndex
        }
    }

    private func page(at index: Int) -> CameraRollPageController? {
        guard index >= 0, index < assets.count else { return nil }
        let page = CameraRollPageController(asset: assets.object(at: index), index: index)
        page.model = self
        return page
    }

    private func show(index newIndex: Int, direction: UIPageViewController.NavigationDirection, animated: Bool) {
        guard let page = page(at: newIndex) else { return }
        currentPage?.stopPlayback()
        pager.setViewControllers([page], direction: direction, animated: animated)
        didShow(page)
    }

    private func didShow(_ page: CameraRollPageController) {
        index = page.index
        currentIsVideo = page.asset.mediaType == .video
        if !slideshow {
            isPlaying = false
        }
    }

    // MARK: Data source / delegate

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? CameraRollPageController else { return nil }
        return self.page(at: page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? CameraRollPageController else { return nil }
        return self.page(at: page.index + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        stopSlideshow()
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed else { return }
        previousViewControllers.compactMap { $0 as? CameraRollPageController }.forEach { $0.stopPlayback() }
        if let page = currentPage { didShow(page) }
    }

    // MARK: Toolbar actions

    func next() {
        guard index + 1 < count else { return }
        stopSlideshow()
        show(index: index + 1, direction: .forward, animated: true)
    }

    func previous() {
        guard index > 0 else { return }
        stopSlideshow()
        show(index: index - 1, direction: .reverse, animated: true)
    }

    /// Play: a video plays / pauses; a photo starts the iOS 6 slideshow.
    func togglePlay() {
        if currentIsVideo {
            currentPage?.togglePlayback()
        } else if slideshow {
            stopSlideshow()
        } else {
            startSlideshow()
        }
    }

    func pageTapped() {
        if slideshow {
            stopSlideshow()
            return
        }
        onTap?()
    }

    func playbackChanged(_ playing: Bool, on page: CameraRollPageController) {
        guard page === currentPage else { return }
        isPlaying = playing
    }

    // MARK: Slideshow

    private func startSlideshow() {
        guard count > 1 else { return }
        slideshow = true
        isPlaying = true
        onSlideshowChange?(true)
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.advanceSlideshow()
        }
    }

    private func advanceSlideshow() {
        guard slideshow else { return }
        guard index + 1 < count, let page = page(at: index + 1) else {
            stopSlideshow()
            return
        }
        UIView.transition(with: pager.view, duration: 0.8, options: .transitionCrossDissolve, animations: {
            self.pager.setViewControllers([page], direction: .forward, animated: false)
        }, completion: nil)
        didShow(page)
    }

    func stopSlideshow() {
        guard slideshow else { return }
        slideshow = false
        isPlaying = false
        slideshowTimer?.invalidate()
        slideshowTimer = nil
        onSlideshowChange?(false)
    }

    func teardown() {
        stopSlideshow()
        currentPage?.stopPlayback()
    }
}

// MARK: - Page

/// One asset: a zooming scroll view for photos (fit to screen, pinch,
/// double tap), plus the OldOS play overlay and an `AVPlayerLayer` for videos.
final class CameraRollPageController: UIViewController, UIScrollViewDelegate {
    let asset: PHAsset
    var index: Int
    weak var model: CameraRollViewerModel?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let playButton = UIButton(type: .custom)
    private let playerView = CameraRollPlayerView()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var requestID: PHImageRequestID?
    private var loadedSize: CGSize = .zero
    private var requestingPlayer = false

    init(asset: PHAsset, index: Int) {
        self.asset = asset
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
    }

    private var isVideo: Bool { asset.mediaType == .video }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = isVideo ? 1 : 4
        scrollView.bouncesZoom = true
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.isHidden = true
        playerView.isUserInteractionEnabled = false
        view.addSubview(playerView)

        if isVideo {
            playButton.setImage(UIImage(named: "VideoOverlayPlay"), for: .normal)
            playButton.sizeToFit()
            playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
            view.addSubview(playButton)
        }

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(singleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playButton.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        if scrollView.zoomScale == 1 {
            layoutImage()
        }
        if view.bounds.size != loadedSize, view.bounds.width > 0 {
            loadedSize = view.bounds.size
            loadImage()
        }
    }

    // MARK: Image

    private func loadImage() {
        let scale = UIScreen.main.scale
        var target = CGSize(width: view.bounds.width * scale * 2.5, height: view.bounds.height * scale * 2.5)
        target.width = min(target.width, CGFloat(asset.pixelWidth))
        target.height = min(target.height, CGFloat(asset.pixelHeight))
        if target.width <= 0 || target.height <= 0 {
            target = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        }
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = CameraRollImages.image(for: asset, fitting: target) { [weak self] image, _ in
            guard let self, let image else { return }
            let first = self.imageView.image == nil
            self.imageView.image = image
            if first || self.scrollView.zoomScale == 1 {
                self.layoutImage()
            }
        }
    }

    /// Fits the photo in the page at its normal size and centres it.
    private func layoutImage() {
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return }
        let imageSize: CGSize
        if let image = imageView.image, image.size.width > 0, image.size.height > 0 {
            imageSize = image.size
        } else if asset.pixelWidth > 0, asset.pixelHeight > 0 {
            imageSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        } else {
            imageSize = bounds
        }
        let ratio = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
        scrollView.zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        if !isVideo {
            let pixelRatio = CGFloat(asset.pixelWidth) / max(fitted.width * UIScreen.main.scale, 1)
            scrollView.maximumZoomScale = min(max(pixelRatio, 2.5), 6)
        }
        centerContent()
        scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
    }

    private func centerContent() {
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize
        let x = max(0, (bounds.width - content.width) / 2)
        let y = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        isVideo ? nil : imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard !isVideo else { return }
        if scrollView.zoomScale > 1.01 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let scale = min(2.5, scrollView.maximumZoomScale)
            let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTapped() {
        model?.pageTapped()
    }

    // MARK: Video

    @objc private func playTapped() {
        togglePlayback()
    }

    func togglePlayback() {
        guard isVideo else { return }
        if let player, player.timeControlStatus == .playing {
            player.pause()
            playButton.isHidden = false
            model?.playbackChanged(false, on: self)
            return
        }
        if let player {
            playerView.isHidden = false
            playButton.isHidden = true
            player.play()
            model?.playbackChanged(true, on: self)
            return
        }
        guard !requestingPlayer else { return }
        requestingPlayer = true
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingPlayer = false
                guard let item else { return }
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                let player = AVPlayer(playerItem: item)
                self.player = player
                self.playerView.playerLayer.player = player
                self.playerView.isHidden = false
                self.playButton.isHidden = true
                self.endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    // OldOS: back to the start with the play overlay.
                    self.player?.seek(to: .zero)
                    self.playButton.isHidden = false
                    self.model?.playbackChanged(false, on: self)
                }
                player.play()
                self.model?.playbackChanged(true, on: self)
            }
        }
    }

    func stopPlayback() {
        guard isVideo, let player else { return }
        player.pause()
        player.seek(to: .zero)
        playerView.isHidden = true
        playButton.isHidden = false
        model?.playbackChanged(false, on: self)
    }
}

/// OldOS `PlayerView`: a view backed by an `AVPlayerLayer` (aspect fit).
final class CameraRollPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// SwiftUI host of the pager.
struct CameraRollPagerView: UIViewControllerRepresentable {
    let model: CameraRollViewerModel

    func makeUIViewController(context: Context) -> UIPageViewController {
        model.pager
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {}
}
