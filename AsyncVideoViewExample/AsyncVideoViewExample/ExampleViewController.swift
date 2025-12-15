//
//  ExampleViewController.swift
//  AsyncVideoViewExample
//
//  Created by Patryk Średziński on 15/12/2025.
//

import UIKit

class ExampleViewController: UIViewController {

    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private var items: [String] = []

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
        tableView.register(VideoCell.self, forCellReuseIdentifier: VideoCell.identifier)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func generateRandomData() {
        for i in 1...1000 {
            items.append("Random Text \(i) - \(UUID().uuidString.prefix(8))")
        }
        tableView.reloadData()
    }
}

extension ExampleViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: VideoCell.identifier, for: indexPath) as? VideoCell else {
            return UITableViewCell()
        }
        cell.titleLabel.text = items[indexPath.row]
        return cell
    }
}
