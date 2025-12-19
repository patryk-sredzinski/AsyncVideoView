//
//  AsyncVideoAsset.swift
//  AsyncVideoView
//
//  Created by Patryk Średziński on 10/04/2025.
//

import AVFoundation
import IteoLogger

enum AsyncVideoAssetError: Error {
    case videoTrackNotAvailable
    case videoTrackNotPlayable
}

final class AsyncVideoAsset: NSObject {
    let urlAsset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
    let timeRange: CMTimeRange
    let preferredTransform: CGAffineTransform

    init(url: URL) async throws {
        let urlAsset = AVURLAsset(url: url)
        async let tracks = urlAsset.loadTracks(withMediaType: .video)
        async let duration = urlAsset.load(.duration)
        async let isPlayable = urlAsset.load(.isPlayable)

        let (loadedTracks, loadedDuration, loadedIsPlayable) = try await (tracks, duration, isPlayable)
        guard loadedIsPlayable else {
            IteoLogger.default.log(.error, .video, "AsyncAsset init failed - video track not playable for URL", url)
            throw AsyncVideoAssetError.videoTrackNotPlayable
        }
        guard let loadedVideoTrack = loadedTracks.first else {
            IteoLogger.default.log(.error, .video, "AsyncAsset init failed - video track not available for URL", url)
            throw AsyncVideoAssetError.videoTrackNotAvailable
        }

        async let timeRange = loadedVideoTrack.load(.timeRange)
        async let preferredTransform = loadedVideoTrack.load(.preferredTransform)

        let (loadedTimeRange, loadedPreferredTransform) = try await (timeRange, preferredTransform)

        self.urlAsset = urlAsset
        self.track = loadedVideoTrack
        self.duration = loadedDuration
        self.timeRange = loadedTimeRange
        self.preferredTransform = loadedPreferredTransform
    }
}

