import AVFoundation
import UIKit
import IteoLogger

public final class AsyncVideoView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    private var currentURL: URL?

    public weak var delegate: AsyncVideoViewDelegate?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        cleanup()
        disableBackgroundHandling()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }

    public override func removeFromSuperview() {
        super.removeFromSuperview()
        cleanup()
    }
}

public extension AsyncVideoView {
    func configure(url: URL?) {
        guard currentURL != url else { return }
        cleanup()
        currentURL = url
    }

    func start() {
        guard let url = currentURL else {
            IteoLogger.default.log(.error, .video, "Start called but currentURL is nil")
            return
        }

        if let player {
            player.play()
            return
        }

        setupPlayer(with: url)
    }

    func stop() {
        player?.pause()
    }
}

private extension AsyncVideoView {
    private func commonInit() {
        backgroundColor = .clear
        enableBackgroundHandling()
    }

    private func setupPlayer(with url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.audioTimePitchAlgorithm = .timeDomain
        playerItem.appliesPerFrameHDRDisplayMetadata = false

        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none

        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = bounds
        layer.allowsEdgeAntialiasing = false
        layer.allowsGroupOpacity = false
        if #available(iOS 26.0, *) {
            layer.preferredDynamicRange = .standard
        } else  if #available(iOS 17.0, *) {
            layer.wantsExtendedDynamicRangeContent = false
        }
        self.layer.addSublayer(layer)
        self.playerLayer = layer

        setupObservers(for: playerItem, player: player, asset: asset)

        player.play()
    }

    private func setupObservers(for playerItem: AVPlayerItem, player: AVPlayer, asset: AVAsset) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { [weak self] in
                guard let self else { return }
                await MainActor.run {
                    self.delegate?.asyncVideoView(videoView: self, didRenderFrame: time)
                }
            }
        }

        Task { [weak self] in
            do {
                guard let self else { return }
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.delegate?.asyncVideoView(videoView: self, didReceiveAssetDuration: duration)
                }
            } catch {
                IteoLogger.default.log(.error, .video, "Failed to load duration", "error", error)
            }
        }
    }

    @objc private func playerItemDidReachEnd(notification: Notification) {
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
    }

    private func cleanup() {
        if let currentItem = player?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
        }

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
    }
}

private extension AsyncVideoView {
    private func enableBackgroundHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    private func disableBackgroundHandling() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidEnterBackground() {
        stop()
    }

    @objc private func appWillEnterForeground() {
        start()
    }
}

