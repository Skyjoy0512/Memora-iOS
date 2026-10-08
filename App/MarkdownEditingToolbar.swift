import UIKit

final class MarkdownEditingToolbar: UIView {
  init(rows: [[UIButton]]) {
    super.init(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat(rows.count) * 44 + 16))
    autoresizingMask = [.flexibleWidth]

    let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    background.layer.cornerRadius = 20
    background.clipsToBounds = true
    background.translatesAutoresizingMaskIntoConstraints = false
    addSubview(background)

    let content = UIStackView()
    content.axis = .vertical
    content.distribution = .fillEqually
    content.translatesAutoresizingMaskIntoConstraints = false
    background.contentView.addSubview(content)

    for buttons in rows {
      let row = UIStackView(arrangedSubviews: buttons)
      row.distribution = .fillEqually
      for button in buttons {
        let minimumWidth = button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        minimumWidth.priority = .defaultHigh
        minimumWidth.isActive = true
      }
      content.addArrangedSubview(row)
    }

    NSLayoutConstraint.activate([
      background.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      background.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      background.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      background.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      content.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 4),
      content.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -4),
      content.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 4),
      content.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -4)
    ])
  }

  required init?(coder: NSCoder) { nil }
}
