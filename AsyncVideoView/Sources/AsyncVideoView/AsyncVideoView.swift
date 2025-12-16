//
//  AsyncVideoView.swift
//  VUIUtils
//
//  Created by Patryk Średziński on 10/04/2025.
//

import AVFoundation
import UIKit

enum AsyncAssetError: Error {
    case videoTrackNotAvailable
    case videoTrackNotPlayable
}

final class AsyncAsset: NSObject {
    let urlAsset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
    let timeRange: CMTimeRange
    let prefferedTransform: CGAffineTransform

    init(url: URL) async throws {
        let urlAsset = AVURLAsset(url: url)
        async let tracks = urlAsset.loadTracks(withMediaType: .video)
        async let duration = urlAsset.load(.duration)
        async let isPlayable = urlAsset.load(.isPlayable)

        let (loadedTracks, loadedDuration, loadedIsPlayable) = try await (tracks, duration, isPlayable)
        guard loadedIsPlayable else {
            print("AsyncVideoView: AsyncAsset init failed - video track not playable for URL: \(url)")
            throw AsyncAssetError.videoTrackNotPlayable
        }
        guard let loadedVideoTrack = loadedTracks.first else {
            print("AsyncVideoView: AsyncAsset init failed - video track not available for URL: \(url)")
            throw AsyncAssetError.videoTrackNotAvailable
        }

        async let timeRange = loadedVideoTrack.load(.timeRange)
        async let preferredTransform = loadedVideoTrack.load(.preferredTransform)

        let (loadedTimeRange, loadedPreferredTransform) = try await (timeRange, preferredTransform)

        self.urlAsset = urlAsset
        self.track = loadedVideoTrack
        self.duration = loadedDuration
        self.timeRange = loadedTimeRange
        self.prefferedTransform = loadedPreferredTransform
    }
}

@MainActor
public protocol AsyncVideoViewDelegate: AnyObject {
    func asyncVideoView(videoView: AsyncVideoView, didReceiveAssetDuration assetDuration: CMTime)
    func asyncVideoViewDidRenderFrame(videoView: AsyncVideoView, timestamp: CMTime)
}

public final class AsyncVideoView: UIView {
    private let workingQueue = DispatchQueue(label: "com.vama.AsyncVideoViewQueue")
    private let displayLayer = AVSampleBufferDisplayLayer()

    private var assetReader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var asset: AsyncAsset?
    private var currentURL: URL?
    private var isReading = false

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
            print("AsyncVideoView: deinit - cleaning up display layer")
            displayLayer.stopRequestingMediaData()
            displayLayer.flushAndRemoveImage()
        }
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
    func configure(url: URL) {
        if currentURL != url {
            stopAndCleanup()
        }
        currentURL = url
        print("AsyncVideoView: configure called, url: \(String(describing: url.lastPathComponent))")
    }

    func start() {
        guard let currentURL else {
            print("AsyncVideoView: start called but currentURL is nil")
            return
        }
        print("AsyncVideoView: start called, url: \(String(describing: currentURL.lastPathComponent))")
        workingQueue.async { [weak self] in
            self?.setupWithURL(currentURL)
        }
    }

    func stop() {
        print("AsyncVideoView: stop called, url: \(String(describing: currentURL?.lastPathComponent))")
        stopAndCleanup()
    }
}

private extension AsyncVideoView {
    private func commonInit() {
        displayLayer.videoGravity = .resizeAspect
        layer.addSublayer(displayLayer)
        backgroundColor = .clear
    }

    private func stopAndCleanup() {
        isReading = false
        
        onMainThread { [weak self] in
            guard let self else {
                print("AsyncVideoView: stopAndCleanup onMainThread - self is nil")
                return
            }
            displayLayer.stopRequestingMediaData()
            displayLayer.flushAndRemoveImage()
        }

        workingQueue.async { [weak self] in
            guard let self else {
                print("AsyncVideoView: stopAndCleanup workingQueue - self is nil")
                return
            }
            assetReader?.cancelReading()
            asset?.urlAsset.cancelLoading()
            assetReader = nil
            videoOutput = nil
            assetReader = nil
        }
    }

    private func loadAsset(_ url: URL, completion: @escaping (AsyncAsset?) -> Void) {
        Task {
            do {
                let asset = try await AsyncAsset(url: url)
                completion(asset)
            } catch {
                print("AsyncVideoView: loadAsset failed with error: \(error) for URL: \(url)")
                completion(nil)
            }
        }
    }

    private func setupWithURL(_ url: URL) {
        guard currentURL == url else {
            print("AsyncVideoView: setupWithURL early return - currentURL changed (current: \(String(describing: currentURL?.lastPathComponent)), requested: \(url.lastPathComponent))")
            return
        }

        loadAsset(url) { [weak self] asset in
            guard let asset else {
                print("AsyncVideoView: Failed to setup asset for URL: \(url)")
                return
            }
            guard let self else {
                print("AsyncVideoView: setupWithURL early return - self is nil")
                return
            }
            guard currentURL == url else {
                print("AsyncVideoView: setupWithURL early return - currentURL changed during asset load (current: \(String(describing: currentURL?.lastPathComponent)), requested: \(url.lastPathComponent))")
                return
            }
            self.asset = asset

            onMainThread { [weak self] in
                guard let self else {
                    print("AsyncVideoView: setupWithURL onMainThread - self is nil")
                    return
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                displayLayer.setAffineTransform(asset.prefferedTransform)
                CATransaction.commit()
                delegate?.asyncVideoView(videoView: self, didReceiveAssetDuration: asset.duration)
            }
            workingQueue.async { [weak self] in
                guard let self else {
                    print("AsyncVideoView: setupWithURL workingQueue - self is nil")
                    return
                }
                startReading(url: url)
            }
        }
    }

    private func startReading(url: URL) {
        guard let asset else {
            print("AsyncVideoView: No native asset available for reading")
            return
        }
        guard currentURL == url else {
            print("AsyncVideoView: startReading early return - currentURL changed (current: \(String(describing: currentURL?.lastPathComponent)), requested: \(url.lastPathComponent))")
            return
        }

        guard let assetReader = try? AVAssetReader(asset: asset.urlAsset) else {
            print("AsyncVideoView: Failed to create AVAssetReader")
            return
        }

        let videoTrack = asset.track

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        videoOutput.supportsRandomAccess = true
        assetReader.add(videoOutput)

        guard assetReader.startReading() else {
            print("AsyncVideoView: Failed to start reading: \(String(describing: assetReader.error))")
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
            print("AsyncVideoView: setupControlTimebase failed - could not create control timebase")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                print("AsyncVideoView: setupControlTimebase DispatchQueue.main - self is nil")
                return
            }
            self.displayLayer.controlTimebase = controlTimebase
            CMTimebaseSetTime(controlTimebase, time: CMTime.zero)
            CMTimebaseSetRate(controlTimebase, rate: 1.0)
        }
    }

    private func startEnqueueingFrames(url: URL) {
        guard currentURL == url, isReading else {
            print("AsyncVideoView: startEnqueueingFrames early return - currentURL mismatch or not reading (currentURL: \(String(describing: currentURL?.lastPathComponent)), requested: \(url.lastPathComponent), isReading: \(isReading))")
            return
        }

        displayLayer.requestMediaDataWhenReady(on: workingQueue) { [weak self] in
            guard let self else {
                print("AsyncVideoView: startEnqueueingFrames requestMediaDataWhenReady closure - self is nil")
                return
            }

            guard currentURL == url, isReading else {
                print("AsyncVideoView: startEnqueueingFrames closure early return - currentURL mismatch or not reading (currentURL: \(String(describing: currentURL?.lastPathComponent)), requested: \(url.lastPathComponent), isReading: \(isReading))")
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        print("AsyncVideoView: startEnqueueingFrames DispatchQueue.main (assetReader nil) - self is nil")
                        return
                    }
                    displayLayer.stopRequestingMediaData()
                }
                return
            }

            guard let assetReader else {
                print("AsyncVideoView: No asset reader available")
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        print("AsyncVideoView: startEnqueueingFrames DispatchQueue.main (assetReader nil) - self is nil")
                        return
                    }
                    displayLayer.stopRequestingMediaData()
                }
                return
            }

            if assetReader.status == .failed {
                print("AsyncVideoView: Asset reader failed with error: \(String(describing: assetReader.error))")
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        print("AsyncVideoView: startEnqueueingFrames DispatchQueue.main (reconfigure) - self is nil")
                        return
                    }
                    start()
                }
                return
            }

            guard assetReader.status == .reading else {
                print("AsyncVideoView: Asset reader stopped reading with status: \(assetReader.status)")
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        print("AsyncVideoView: startEnqueueingFrames DispatchQueue.main (reconfigure) - self is nil")
                        return
                    }
                    start()
                }
                return
            }

            guard displayLayer.isReadyForMoreMediaData else {
                print("AsyncVideoView: Not ready")
                return
            }
            
            guard displayLayer.status != .failed else {
                print("AsyncVideoView: Display layer failed with error: \(String(describing: displayLayer.error))")
                stopAndCleanup()
                return
            }

            guard let sampleBuffer = videoOutput?.copyNextSampleBuffer() else {
                print("AsyncVideoView: No sample buffer available, looping video for URL: \(url.lastPathComponent)")
                loopVideo(url: url)
                return
            }

            guard currentURL == url else {
                print("AsyncVideoView: startEnqueueingFrames early return after sample buffer - currentURL mismatch (currentURL: \(String(describing: currentURL?.lastPathComponent)), requested: \(url.lastPathComponent))")
                return
            }

            guard isReading else {
                print("AsyncVideoView: startEnqueueingFrames early return after sample buffer - not reading")
                return
            }

            displayLayer.enqueue(sampleBuffer)

            let timeStamp = sampleBuffer.presentationTimeStamp
            Task { [weak self] in
                guard let self else {
                    print("AsyncVideoView: startEnqueueingFrames Task (delegate callback) - self is nil")
                    return
                }
                await delegate?.asyncVideoViewDidRenderFrame(videoView: self, timestamp: timeStamp)
            }

        }
    }

    private func loopVideo(url: URL) {
        guard currentURL == url, isReading else {
            print("AsyncVideoView: loopVideo early return - currentURL mismatch or not reading (currentURL: \(String(describing: currentURL?.lastPathComponent)), requested: \(url.lastPathComponent), isReading: \(isReading))")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                print("AsyncVideoView: loopVideo DispatchQueue.main - self is nil")
                return
            }
            displayLayer.stopRequestingMediaData()
            displayLayer.flush()
        }

        guard let videoOutput, let assetReader, let asset else {
            print("AsyncVideoView: Missing components for looping, cleaning up")
            stopAndCleanup()
            return
        }

        guard CMTIME_IS_NUMERIC(asset.timeRange.start) else {
            print("AsyncVideoView: Invalid time range for looping, cleaning up")
            stopAndCleanup()
            return
        }

        guard assetReader.status != .failed else {
            print("AsyncVideoView: loopVideo early return - AssetReader in failed state, cleaning up, error: \(String(describing: assetReader.error))")
            stopAndCleanup()
            return
        }

        let beginningTimeRange = NSValue(timeRange: asset.timeRange)
        videoOutput.reset(forReadingTimeRanges: [beginningTimeRange])
        setupControlTimebase()
        startEnqueueingFrames(url: url)
    }

    private func onMainThread(_ closure: @escaping () -> Void ) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.async {
                closure()
            }
        }
    }
}
