//
//  Untitled.swift
//  AsyncVideoViewExample
//
//  Created by Patryk Średziński on 15/12/2025.
//

import CoreMedia
import UIKit
import AsyncVideoView

class VideoCell: UITableViewCell {
    static var cellHeight: CGFloat = 100
    static let identifier = "VideoCell"

    var duration: CMTime = .zero
    var currentTimestamp: CMTime = .zero

    lazy var videoView: AsyncVideoView = {
        let view = AsyncVideoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        return view
    }()

    lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = UIFont.boldSystemFont(ofSize: 16)
        label.backgroundColor = .black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 8
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.backgroundColor = .orange
        contentView.addSubview(videoView)
        contentView.addSubview(timeLabel)

        let heightAnchorConstraint = videoView.heightAnchor.constraint(equalToConstant: Self.cellHeight)
        heightAnchorConstraint.priority = UILayoutPriority.defaultHigh

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: contentView.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            heightAnchorConstraint,
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            timeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            timeLabel.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        videoView.stop()
    }

    func configure(_ videoUrl: URL) {
        duration = .zero
        currentTimestamp = .zero
        updateTextLabel()
        videoView.configure(url: videoUrl)
    }

    func willDisplay() {
        videoView.start()
    }

    func didEndDisplaying() {
        videoView.stop()
    }

    private func updateTextLabel() {
        if duration == .zero || currentTimestamp == .zero {
            timeLabel.text = ""
            return
        }

        let durationSeconds = CMTimeGetSeconds(duration)
        let currentSeconds = CMTimeGetSeconds(currentTimestamp)
        guard durationSeconds.isFinite, currentSeconds.isFinite else {
            timeLabel.text = ""
            return
        }
        let durationText = String(format: "%02d:%02d", Int(durationSeconds) / 60, Int(durationSeconds) % 60)
        let currentText = String(format: "%02d:%02d", Int(currentSeconds) / 60, Int(currentSeconds) % 60)
        timeLabel.text = "\(currentText) / \(durationText)"
    }
}

extension VideoCell: AsyncVideoViewDelegate {
    func asyncVideoView(videoView: AsyncVideoView, didReceiveAssetDuration assetDuration: CMTime) {
        self.duration = assetDuration
        updateTextLabel()
    }
    
    func asyncVideoView(videoView: AsyncVideoView, didRenderFrame timeStamp: CMTime) {
        self.currentTimestamp = timeStamp
        updateTextLabel()
    }
}
