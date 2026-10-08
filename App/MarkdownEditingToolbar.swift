import UIKit

final class MarkdownEditingToolbar: UIView {
  init(buttons: [UIButton], done: UIButton) {
    super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 60))
    autoresizingMask = [.flexibleWidth]

    let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    background.layer.cornerRadius = 20
    background.clipsToBounds = true
    background.translatesAutoresizingMaskIntoConstraints = false
    addSubview(background)

    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.alwaysBounceHorizontal = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    background.contentView.addSubview(scrollView)

    let content = UIStackView(arrangedSubviews: buttons)
    content.axis = .horizontal
    content.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(content)
    done.translatesAutoresizingMaskIntoConstraints = false
    background.contentView.addSubview(done)

    for button in buttons {
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }

    NSLayoutConstraint.activate([
      background.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      background.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      background.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      background.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      scrollView.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 4),
      scrollView.trailingAnchor.constraint(equalTo: done.leadingAnchor),
      scrollView.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 4),
      scrollView.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -4),
      content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      content.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
      done.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -4),
      done.topAnchor.constraint(equalTo: scrollView.topAnchor),
      done.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      done.widthAnchor.constraint(equalToConstant: 56)
    ])
  }

  required init?(coder: NSCoder) { nil }
}
