//
//  AsyncVideoView.swift
//  AsyncVideoView
//
//  Created by Patryk Średziński on 10/04/2025.
//

import AVFoundation

@MainActor
public protocol AsyncVideoViewDelegate: AnyObject {
    func asyncVideoView(videoView: AsyncVideoView, didReceiveAssetDuration assetDuration: CMTime)
    func asyncVideoView(videoView: AsyncVideoView, didRenderFrame timeStamp: CMTime)
}

