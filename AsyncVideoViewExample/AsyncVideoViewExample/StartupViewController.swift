//
//  ExampleViewController.swift
//  AsyncVideoViewExample
//
//  Created by Patryk Średziński on 15/12/2025.
//

import UIKit

class StartupViewController: UIViewController {

    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let cellHeights: [CGFloat] = [50, 75, 100, 200, 300, 400, 500, 1000]

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupStackView()
        (stackView.arrangedSubviews[3] as? UIButton)?.sendActions(for: .touchUpInside)
    }

    private func setupView() {
        title = "Startup"
    }

    private func setupStackView() {
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        cellHeights.forEach { cellHeight in
            let button = UIButton()
            button.setTitle("Cell Height \(Int(cellHeight))px", for: .normal)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addAction(UIAction(title: "Start \(cellHeight)", handler: { [weak self] _ in
                self?.navigationController?.pushViewController(ExampleViewController(cellHeight: cellHeight), animated: true)
            }), for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }

    }
}
