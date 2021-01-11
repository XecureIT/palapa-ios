//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWSFlatButton: UIView {

    private let button: UIButton

    private var pressedBlock : (() -> Void)?

    private var upColor: UIColor?
    private var downColor: UIColor?

    @objc
    public override var accessibilityIdentifier: String? {
        didSet {
            guard let accessibilityIdentifier = self.accessibilityIdentifier else {
                return
            }
            button.accessibilityIdentifier = "\(accessibilityIdentifier).button"
        }
    }

    override public var backgroundColor: UIColor? {
        willSet {
            owsFailDebug("Use setBackgroundColors(upColor:) instead.")
        }
    }

    public var titleEdgeInsets: UIEdgeInsets {
        set {
            button.titleEdgeInsets = newValue
        }
        get {
            return button.titleEdgeInsets
        }
    }

    public var contentEdgeInsets: UIEdgeInsets {
        set {
            button.contentEdgeInsets = newValue
        }
        get {
            return button.contentEdgeInsets
        }
    }

    @objc
    public init() {
        AssertIsOnMainThread()

        button = UIButton(type: .custom)

        super.init(frame: CGRect.zero)

        createContent()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private func createContent() {
        self.addSubview(button)
        button.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
        button.ows_autoPinToSuperviewEdges()
    }

    @objc
    public class func button(title: String,
                             font: UIFont,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             width: CGFloat,
                             height: CGFloat,
                             target: Any,
                             selector: Selector) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.setTitle(title: title,
                        font: font,
                        titleColor: titleColor )
        button.setBackgroundColors(upColor: backgroundColor)
        button.useDefaultCornerRadius()
        button.setSize(width: width, height: height)
        button.addTarget(target: target, selector: selector)
        return button
    }

    @objc
    public class func button(title: String,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             width: CGFloat,
                             height: CGFloat,
                             target: Any,
                             selector: Selector) -> OWSFlatButton {
        return OWSFlatButton.button(title: title,
                                    font: fontForHeight(height),
                                    titleColor: titleColor,
                                    backgroundColor: backgroundColor,
                                    width: width,
                                    height: height,
                                    target: target,
                                    selector: selector)
    }

    @objc
    public class func button(title: String,
                             font: UIFont,
                             titleColor: UIColor,
                             backgroundColor: UIColor,
                             target: Any,
                             selector: Selector) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.setTitle(title: title,
                        font: font,
                        titleColor: titleColor )
        button.setBackgroundColors(upColor: backgroundColor)
        button.useDefaultCornerRadius()
        button.addTarget(target: target, selector: selector)
        return button
    }

    @objc
    public class func fontForHeight(_ height: CGFloat) -> UIFont {
        // Cap the "button height" at 40pt or button text can look
        // excessively large.
        let fontPointSize = round(min(40, height) * 0.45)
        return UIFont.ows_semiboldFont(withSize: fontPointSize)
    }

    @objc
    public class func heightForFont(_ font: UIFont) -> CGFloat {
        // Button height should be 48pt if the font is 17pt.
        return font.pointSize * 48 / 17
    }

    // MARK: Methods

    @objc
    public func setTitle(title: String, font: UIFont,
                         titleColor: UIColor ) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel!.font = font
    }

    @objc
    public func setBackgroundColors(upColor: UIColor,
                                    downColor: UIColor ) {
        button.setBackgroundImage(UIImage(color: upColor), for: .normal)
        button.setBackgroundImage(UIImage(color: downColor), for: .highlighted)
    }

    @objc
    public func setBackgroundColors(upColor: UIColor ) {
        setBackgroundColors(upColor: upColor,
                            downColor: upColor.withAlphaComponent(0.7) )
    }

    @objc
    public func setSize(width: CGFloat, height: CGFloat) {
        button.autoSetDimension(.width, toSize: width)
        button.autoSetDimension(.height, toSize: height)
    }

    @objc
    public func useDefaultCornerRadius() {
        // To my eye, this radius tends to look right regardless of button size
        // (within reason) or device size. 
        button.layer.cornerRadius = 5
        button.clipsToBounds = true
    }

    @objc
    public func setEnabled(_ isEnabled: Bool) {
        button.isEnabled = isEnabled
    }

    @objc
    public func addTarget(target: Any,
                          selector: Selector) {
        button.addTarget(target, action: selector, for: .touchUpInside)
    }

    @objc
    public func setPressedBlock(_ pressedBlock: @escaping () -> Void) {
        guard self.pressedBlock == nil else {
            owsFailDebug("Button already has pressed block.")
            return
        }
        self.pressedBlock = pressedBlock
    }

    @objc
    internal func buttonPressed() {
        pressedBlock?()
    }

    @objc
    public func enableMultilineLabel() {
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.titleLabel?.textAlignment = .center
    }

    @objc
    public var font: UIFont? {
        return button.titleLabel?.font
    }

    @objc
    public func autoSetHeightUsingFont() {
        guard let font = font else {
            owsFailDebug("Missing button font.")
            return
        }
        autoSetDimension(.height, toSize: font.lineHeight * 2.5)
    }
}
