//
//  AsyncVideoView.swift
//  AsyncVideoView
//
//  Created by Patryk Średziński on 10/04/2025.
//

import AVFoundation
import UIKit
import IteoLogger

public final class AsyncVideoView: UIView {
    private let workingQueue = DispatchQueue(label: "com.vama.AsyncVideoViewQueue")
    private let displayLayer = AVSampleBufferDisplayLayer()

    private static let videoOutputSettings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]

    private var assetReader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var asset: AsyncVideoAsset?
    private var currentURL: URL?
    private var isReading = false
    private var frameCount = 0

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
        isReading = false
        assetReader?.cancelReading()
        asset?.urlAsset.cancelLoading()
        let displayLayer = self.displayLayer
        onMainThread {
            displayLayer.stopRequestingMediaData()
            displayLayer.flushAndRemoveImage()
        }
        disableBackgroundHandling()
    }

    public override func removeFromSuperview() {
        super.removeFromSuperview()
        stopAndCleanup()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}

public extension AsyncVideoView {
    func configure(url: URL?) {
        if currentURL != url {
            stopAndCleanup()
        }
        currentURL = url
    }

    func start() {
        guard let currentURL else {
            IteoLogger.default.log(.error, .video, "Start called but currentURL is nil")
            return
        }
        workingQueue.async { [weak self] in
            self?.setupWithURL(currentURL)
        }
    }

    func stop() {
        stopAndCleanup()
    }
}

private extension AsyncVideoView {
    private func commonInit() {
        displayLayer.videoGravity = .resizeAspect
        layer.addSublayer(displayLayer)
        backgroundColor = .clear
        enableBackgroundHandling()
    }

    private func stopAndCleanup() {
        isReading = false
        frameCount = 0

        onMainThread { [weak self] in
            guard let self else { return }
            displayLayer.stopRequestingMediaData()
            displayLayer.flushAndRemoveImage()
        }

        workingQueue.async { [weak self] in
            guard let self else { return }
            assetReader?.cancelReading()
            asset?.urlAsset.cancelLoading()
            assetReader = nil
            videoOutput = nil
        }
    }

    private func loadAsset(_ url: URL, completion: @escaping (AsyncVideoAsset?) -> Void) {
        Task {
            do {
                let asset = try await AsyncVideoAsset(url: url)
                completion(asset)
            } catch {
                IteoLogger.default.log(.error, .video, "loadAsset failed with error", "error", error, url)
                completion(nil)
            }
        }
    }

    private func setupWithURL(_ url: URL) {
        guard isValidURL(url, context: "setupWithURL") else {
            return
        }

        loadAsset(url) { [weak self] asset in
            guard let self else { return }
            guard let asset else {
                IteoLogger.default.log(.error, .video, "Failed to setup asset for URL", "url", url)
                return
            }
            guard isValidURL(url, context: "setupWithURL during asset load") else {
                return
            }
            self.asset = asset

            onMainThread { [weak self] in
                guard let self else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                displayLayer.setAffineTransform(asset.preferredTransform)
                CATransaction.commit()
                delegate?.asyncVideoView(videoView: self, didReceiveAssetDuration: asset.duration)
            }
            workingQueue.async { [weak self] in
                guard let self else { return }
                startReading(url: url)
            }
        }
    }

    private func startReading(url: URL) {
        guard let asset else {
            IteoLogger.default.log(.error, .video, "No native asset available for reading")
            return
        }
        guard isValidURL(url, context: "startReading") else {
            return
        }

        guard let assetReader = try? AVAssetReader(asset: asset.urlAsset) else {
            IteoLogger.default.log(.error, .video, "Failed to create AVAssetReader")
            return
        }

        let videoTrack = asset.track
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: Self.videoOutputSettings)
        videoOutput.supportsRandomAccess = true
        assetReader.add(videoOutput)

        guard assetReader.startReading() else {
            IteoLogger.default.log(.error, .video, "Failed to start reading", "error", String(describing: assetReader.error))
            return
        }

        self.assetReader = assetReader
        self.videoOutput = videoOutput
        self.isReading = true

        setupControlTimebase()
        startEnqueueingFrames(url: url)
    }

    private func setupControlTimebase() {
        var controlTimebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &controlTimebase
        )

        guard let controlTimebase else {
            IteoLogger.default.log(.error, .video, "setupControlTimebase failed - could not create control timebase")
            return
        }

        onMainThread { [weak self] in
            guard let self else { return }
            self.displayLayer.controlTimebase = controlTimebase
            CMTimebaseSetTime(controlTimebase, time: CMTime.zero)
            CMTimebaseSetRate(controlTimebase, rate: 1.0)
        }
    }

    private func startEnqueueingFrames(url: URL) {
        guard isValidURL(url, context: "startEnqueueingFrames") else {
            return
        }

        guard isReading else {
            IteoLogger.default.log(.warning, .video, "startEnqueueingFrames early return - not reading")
            return
        }

        displayLayer.requestMediaDataWhenReady(on: workingQueue) { [weak self] in
            self?.handleLayerReadyForData(url: url)
        }
    }

    private func handleLayerReadyForData(url: URL) {
        guard isValidURL(url) else {
            stopDisplayLayer()
            return
        }

        guard isReading else {
            IteoLogger.default.log(.warning, .video, "startEnqueueingFrames closure early return - not reading")
            stopDisplayLayer()
            return
        }

        guard let assetReader else {
            IteoLogger.default.log(.warning, .video, "No asset reader available")
            stopDisplayLayer()
            return
        }

        if assetReader.status == .failed {
            IteoLogger.default.log(.error, .video, "Asset reader failed with error", "error", String(describing: assetReader.error))
            onMainThread { [weak self] in
                self?.start()
            }
            return
        }

        guard assetReader.status == .reading else {
            IteoLogger.default.log(.warning, .video, "Asset reader stopped reading with status", "status", "\(assetReader.status)")
            onMainThread { [weak self] in
                self?.start()
            }
            return
        }

        guard displayLayer.status != .failed else {
            IteoLogger.default.log(.error, .video, "Display layer failed with error", "error", String(describing: displayLayer.error))
            stopAndCleanup()
            start()
            return
        }

        while displayLayer.isReadyForMoreMediaData {
            guard let sampleBuffer = videoOutput?.copyNextSampleBuffer() else {
                loopVideo(url: url)
                return
            }

            frameCount += 1

            guard isValidURL(url), isReading else {
                return
            }

            let frameTime = sampleBuffer.presentationTimeStamp

            if let controlTimebase = displayLayer.controlTimebase {
                let displayTime = controlTimebase.time
                        let drift = CMTimeSubtract(displayTime, frameTime)
                        let driftSeconds = abs(drift.seconds)

                if driftSeconds > 0.25 {
                    CMTimebaseSetTime(controlTimebase, time: frameTime)
                    displayLayer.flush()
                    IteoLogger.default.log(.warning, .video, "Drift detected, flushing layer", "drift", driftSeconds)
                    continue
                }
            }

            displayLayer.enqueue(sampleBuffer)

            if frameCount == 1 || frameCount % 30 == 0 {
                onMainThread { [weak self] in
                    guard let self else { return }
                    delegate?.asyncVideoView(videoView: self, didRenderFrame: frameTime)
                }
            }
        }
    }

    private func loopVideo(url: URL) {
        guard isValidURL(url, context: "loopVideo"), isReading else {
            return
        }

        onMainThread { [weak self] in
            guard let self else { return }
            displayLayer.stopRequestingMediaData()
            displayLayer.flush()
        }

        guard let videoOutput, let assetReader, let asset else {
            IteoLogger.default.log(.error, .video, "Missing components for looping, cleaning up")
            stopAndCleanup()
            return
        }

        guard CMTIME_IS_NUMERIC(asset.timeRange.start) else {
            IteoLogger.default.log(.error, .video, "Invalid time range for looping, cleaning up")
            stopAndCleanup()
            return
        }

        guard assetReader.status != .failed else {
            IteoLogger.default.log(.error, .video, "loopVideo early return - AssetReader in failed state, cleaning up", "error", String(describing: assetReader.error))
            stopAndCleanup()
            return
        }

        let beginningTimeRange = NSValue(timeRange: asset.timeRange)
        videoOutput.reset(forReadingTimeRanges: [beginningTimeRange])
        setupControlTimebase()
        startEnqueueingFrames(url: url)
    }

    private func onMainThread(_ closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.async {
                closure()
            }
        }
    }

    private func isValidURL(_ url: URL, context: String = "") -> Bool {
        guard currentURL == url else {
            let contextMsg = context.isEmpty ? "" : " - \(context)"
            IteoLogger.default.log(.warning, .video, "URL validation failed\(contextMsg)", "currentURL", currentURL?.lastPathComponent ?? "nil", "requested", url.lastPathComponent)
            return false
        }
        return true
    }

    private func stopDisplayLayer() {
        onMainThread { [weak self] in
            guard let self else { return }
            displayLayer.stopRequestingMediaData()
        }
    }
}

private extension AsyncVideoView {
    private func enableBackgroundHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
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
