//
//  ExampleViewController.swift
//  AsyncVideoViewExample
//
//  Created by Patryk Średziński on 15/12/2025.
//

import UIKit

class ExampleViewController: UIViewController {

    private let sampleVideos = [
        "boat.mp4",
        "day_city.mp4",
        "fireplace.mp4",
        "night_city.mp4",
        "starfish.mp4",
        "cabana.mov",
        "cicada.mp4",
        "day_square.mp4",
        "legs.mp4",
        "people_walking.mp4",
        "surfing.mp4"
    ]

    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private var videoUrl: [URL] = []

    init(cellHeight: CGFloat) {
        VideoCell.cellHeight = cellHeight
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        generateRandomData()
    }

    private func setupView() {
        title = "Example"
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(VideoCell.self, forCellReuseIdentifier: VideoCell.identifier)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func generateRandomData() {
        for _ in 1...1000 {
            let fileFullName = sampleVideos.randomElement()!
            let fileData = fileFullName.split(separator: ".")
            let fileName = String(fileData[0])
            let fileExtension = String(fileData[1])
            guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
                fatalError("Could not load video \(fileName)")
            }
            videoUrl.append(url)
        }
        tableView.reloadData()
    }
}

extension ExampleViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videoUrl.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: VideoCell.identifier, for: indexPath) as? VideoCell else {
            return UITableViewCell()
        }
        cell.configure(videoUrl[indexPath.row])
        return cell
    }
}

extension ExampleViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? VideoCell else {
            return
        }
        cell.willDisplay()
    }
    
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? VideoCell else {
            return
        }
        cell.didEndDisplaying()
    }
}
