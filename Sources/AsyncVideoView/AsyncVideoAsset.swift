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
        let loadedTracks = try await urlAsset.loadTracks(withMediaType: .video)
        let loadedDuration = try await urlAsset.load(.duration)
        let loadedIsPlayable = try await urlAsset.load(.isPlayable)
        guard loadedIsPlayable else {
            IteoLogger.default.log(.error, .video, "AsyncAsset init failed - video track not playable for URL", url)
            throw AsyncVideoAssetError.videoTrackNotPlayable
        }
        guard let loadedVideoTrack = loadedTracks.first else {
            IteoLogger.default.log(.error, .video, "AsyncAsset init failed - video track not available for URL", url)
            throw AsyncVideoAssetError.videoTrackNotAvailable
        }

        let loadedTimeRange = try await loadedVideoTrack.load(.timeRange)
        let loadedPreferredTransform = try await loadedVideoTrack.load(.preferredTransform)

        self.urlAsset = urlAsset
        self.track = loadedVideoTrack
        self.duration = loadedDuration
        self.timeRange = loadedTimeRange
        self.preferredTransform = loadedPreferredTransform
    }
}

