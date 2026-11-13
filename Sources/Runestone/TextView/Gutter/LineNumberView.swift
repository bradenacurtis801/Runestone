import UIKit

final class LineNumberView: UIView, ReusableView {
    var textColor: UIColor {
        get {
            titleLabel.textColor
        }
        set {
            titleLabel.textColor = newValue
        }
    }
    var font: UIFont {
        get {
            titleLabel.font
        }
        set {
            titleLabel.font = newValue
        }
    }
    var text: String? {
        get {
            titleLabel.text
        }
        set {
            titleLabel.text = newValue
        }
    }

    private let tintView = UIView()

    /// Tints the line's whole row of the gutter, `rowFrame` being that row in this view's own coordinates (it reaches outside the number); `nil` takes it away.
    func setGutterTint(_ color: UIColor?, rowFrame: CGRect) {
        guard let color else {
            tintView.isHidden = true
            return
        }
        if tintView.superview == nil {
            insertSubview(tintView, at: 0)
        }
        tintView.isHidden = false
        tintView.backgroundColor = color
        tintView.frame = rowFrame
    }

    private let titleLabel: UILabel = {
        let this = UILabel()
        this.textAlignment = .right
        return this
    }()

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = titleLabel.intrinsicContentSize
        titleLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: size.height)
    }
}
