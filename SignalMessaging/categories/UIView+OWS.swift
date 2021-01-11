//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension UIEdgeInsets {
    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.init(top: top,
                  left: CurrentAppContext().isRTL ? trailing : leading,
                  bottom: bottom,
                  right: CurrentAppContext().isRTL ? leading : trailing)
    }

    func plus(_ inset: CGFloat) -> UIEdgeInsets {
        var newInsets = self
        newInsets.top += inset
        newInsets.bottom += inset
        newInsets.left += inset
        newInsets.right += inset
        return newInsets
    }

    func minus(_ inset: CGFloat) -> UIEdgeInsets {
        return plus(-inset)
    }
}

// MARK: -

@objc
public extension UINavigationController {
    func pushViewController(_ viewController: UIViewController,
                                   animated: Bool,
                                   completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        pushViewController(viewController, animated: animated)
        CATransaction.commit()
    }

    func popViewController(animated: Bool,
                                  completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        popViewController(animated: animated)
        CATransaction.commit()
    }

    func popToViewController(_ viewController: UIViewController,
                                    animated: Bool,
                                    completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        self.popToViewController(viewController, animated: animated)
        CATransaction.commit()
    }
}

// MARK: -

@objc
public extension UIView {
    func renderAsImage() -> UIImage? {
        return renderAsImage(opaque: false, scale: UIScreen.main.scale)
    }

    func renderAsImage(opaque: Bool, scale: CGFloat) -> UIImage? {
        if #available(iOS 10, *) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = opaque
            let renderer = UIGraphicsImageRenderer(bounds: self.bounds,
                                                   format: format)
            return renderer.image { (context) in
                self.layer.render(in: context.cgContext)
            }
        } else {
            UIGraphicsBeginImageContextWithOptions(bounds.size, opaque, scale)
            if let _ = UIGraphicsGetCurrentContext() {
                drawHierarchy(in: bounds, afterScreenUpdates: true)
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return image
            }
            owsFailDebug("Could not create graphics context.")
            return nil
        }
    }

    class func spacer(withWidth width: CGFloat) -> UIView {
        let view = UIView()
        view.autoSetDimension(.width, toSize: width)
        return view
    }

    class func spacer(withHeight height: CGFloat) -> UIView {
        let view = UIView()
        view.autoSetDimension(.height, toSize: height)
        return view
    }

    class func spacer(matchingHeightOf matchView: UIView, withMultiplier multiplier: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.autoMatch(.height, to: .height, of: matchView, withMultiplier: multiplier)
        return spacer
    }

    class func hStretchingSpacer() -> UIView {
        let view = UIView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }

    @nonobjc
    class func vStretchingSpacer(minHeight: CGFloat? = nil, maxHeight: CGFloat? = nil) -> UIView {
        let view = UIView()
        view.setContentHuggingVerticalLow()
        view.setCompressionResistanceVerticalLow()

        if let minHeight = minHeight {
            view.autoSetDimension(.height, toSize: minHeight, relation: .greaterThanOrEqual)
        }
        if let maxHeight = maxHeight {
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                view.autoSetDimension(.height, toSize: maxHeight)
            }
        }

        return view
    }

    func applyScaleAspectFitLayout(subview: UIView, aspectRatio: CGFloat) -> [NSLayoutConstraint] {
        guard subviews.contains(subview) else {
            owsFailDebug("Not a subview.")
            return []
        }

        // This emulates the behavior of contentMode = .scaleAspectFit using
        // iOS auto layout constraints.
        //
        // This allows ConversationInputToolbar to place the "cancel" button
        // in the upper-right hand corner of the preview content.
        var constraints = [NSLayoutConstraint]()
        constraints.append(contentsOf: subview.autoCenterInSuperview())
        constraints.append(subview.autoPin(toAspectRatio: aspectRatio))
        constraints.append(subview.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual))
        constraints.append(subview.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual))
        NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultHigh) {
            constraints.append(subview.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .equal))
            constraints.append(subview.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .equal))
        }

        return constraints
    }

    func setShadow(radius: CGFloat = 2.0, opacity: Float = 0.66, offset: CGSize = .zero, color: CGColor = UIColor.black.cgColor) {
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
        layer.shadowColor = color
    }

    class func accessibilityIdentifier(in container: NSObject, name: String) -> String {
        return "\(type(of: container)).\(name)"
    }

    class func accessibilityIdentifier(containerName: String, name: String) -> String {
        return "\(containerName).\(name)"
    }

    func setAccessibilityIdentifier(in container: NSObject, name: String) {
        self.accessibilityIdentifier = UIView.accessibilityIdentifier(in: container, name: name)
    }
}

// MARK: -

@objc
public extension UIViewController {
    func presentActionSheet(_ alert: ActionSheetController) {
        self.presentActionSheet(alert, animated: true)
    }

    func presentActionSheet(_ alert: ActionSheetController, animated: Bool) {
        self.present(alert, animated: animated)
    }

    func presentActionSheet(_ alert: ActionSheetController, completion: @escaping (() -> Void)) {
        self.present(alert,
                     animated: true,
                     completion: completion)
    }

    /// A convenience function to present a modal view full screen, not using
    /// the default card style added in iOS 13.
    @objc(presentFullScreenViewController:animated:completion:)
    func presentFullScreen(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        viewControllerToPresent.modalPresentationStyle = .fullScreen
        present(viewControllerToPresent, animated: animated, completion: completion)
    }

    @objc(presentFormSheetViewController:animated:completion:)
    func presentFormSheet(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        // Presenting form sheet on iPhone should always use the default presentation style.
        // We get this for free, except on phones with the regular width size class (big phones
        // in landscape, XR, XS Max, 8+, etc.)
        if UIDevice.current.isIPad {
            viewControllerToPresent.modalPresentationStyle = .formSheet
        }
        present(viewControllerToPresent, animated: animated, completion: completion)
    }
}

// MARK: -

public extension CGFloat {
    func clamp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloatClamp(self, minValue, maxValue)
    }

    func clamp01() -> CGFloat {
        return CGFloatClamp01(self)
    }

    // Linear interpolation
    func lerp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloatLerp(minValue, maxValue, self)
    }

    // Inverse linear interpolation
    func inverseLerp(_ minValue: CGFloat, _ maxValue: CGFloat, shouldClamp: Bool = false) -> CGFloat {
        let value = CGFloatInverseLerp(self, minValue, maxValue)
        return (shouldClamp ? CGFloatClamp01(value) : value)
    }

    static let halfPi: CGFloat = CGFloat.pi * 0.5

    func fuzzyEquals(_ other: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        return abs(self - other) < tolerance
    }

    var square: CGFloat {
        return self * self
    }
}

// MARK: -

public extension Double {
    func clamp(_ minValue: Double, _ maxValue: Double) -> Double {
        return max(minValue, min(maxValue, self))
    }

    func clamp01() -> Double {
        return clamp(0, 1)
    }

    // Linear interpolation
    func lerp(_ minValue: Double, _ maxValue: Double) -> Double {
        return (minValue * (1 - self)) + (maxValue * self)
    }

    // Inverse linear interpolation
    func inverseLerp(_ minValue: Double, _ maxValue: Double, shouldClamp: Bool = false) -> Double {
        let value = (self - minValue) / (maxValue - minValue)
        return (shouldClamp ? value.clamp01() : value)
    }
}

// MARK: -

public extension Int {
    func clamp(_ minValue: Int, _ maxValue: Int) -> Int {
        assert(minValue <= maxValue)

        return Swift.max(minValue, Swift.min(maxValue, self))
    }
}

// MARK: -

public extension UInt {
    func clamp(_ minValue: UInt, _ maxValue: UInt) -> UInt {
        assert(minValue <= maxValue)

        return Swift.max(minValue, Swift.min(maxValue, self))
    }
}

// MARK: -

public extension CGPoint {
    func toUnitCoordinates(viewBounds: CGRect, shouldClamp: Bool) -> CGPoint {
        return CGPoint(x: (x - viewBounds.origin.x).inverseLerp(0, viewBounds.width, shouldClamp: shouldClamp),
                       y: (y - viewBounds.origin.y).inverseLerp(0, viewBounds.height, shouldClamp: shouldClamp))
    }

    func toUnitCoordinates(viewSize: CGSize, shouldClamp: Bool) -> CGPoint {
        return toUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize), shouldClamp: shouldClamp)
    }

    func fromUnitCoordinates(viewBounds: CGRect) -> CGPoint {
        return CGPoint(x: viewBounds.origin.x + x.lerp(0, viewBounds.size.width),
                       y: viewBounds.origin.y + y.lerp(0, viewBounds.size.height))
    }

    func fromUnitCoordinates(viewSize: CGSize) -> CGPoint {
        return fromUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize))
    }

    func inverse() -> CGPoint {
        return CGPoint(x: -x, y: -y)
    }

    func plus(_ value: CGPoint) -> CGPoint {
        return CGPointAdd(self, value)
    }

    func minus(_ value: CGPoint) -> CGPoint {
        return CGPointSubtract(self, value)
    }

    func times(_ value: CGFloat) -> CGPoint {
        return CGPoint(x: x * value, y: y * value)
    }

    func min(_ value: CGPoint) -> CGPoint {
        // We use "Swift" to disambiguate the global function min() from this method.
        return CGPoint(x: Swift.min(x, value.x),
                       y: Swift.min(y, value.y))
    }

    func max(_ value: CGPoint) -> CGPoint {
        // We use "Swift" to disambiguate the global function max() from this method.
        return CGPoint(x: Swift.max(x, value.x),
                       y: Swift.max(y, value.y))
    }

    var length: CGFloat {
        return sqrt(x * x + y * y)
    }

    @inlinable
    func distance(_ other: CGPoint) -> CGFloat {
        return sqrt(pow(x - other.x, 2) + pow(y - other.y, 2))
    }

    @inlinable
    func within(_ delta: CGFloat, of other: CGPoint) -> Bool {
        return distance(other) <= delta
    }

    static let unit: CGPoint = CGPoint(x: 1.0, y: 1.0)

    static let unitMidpoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    func applyingInverse(_ transform: CGAffineTransform) -> CGPoint {
        return applying(transform.inverted())
    }

    func fuzzyEquals(_ other: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        return (x.fuzzyEquals(other.x, tolerance: tolerance) &&
            y.fuzzyEquals(other.y, tolerance: tolerance))
    }

    static func tan(angle: CGFloat) -> CGPoint {
        return CGPoint(x: sin(angle),
                       y: cos(angle))
    }

    func clamp(_ rect: CGRect) -> CGPoint {
        return CGPoint(x: x.clamp(rect.minX, rect.maxX),
                       y: y.clamp(rect.minY, rect.maxY))
    }
}

// MARK: -

public extension CGSize {
    var aspectRatio: CGFloat {
        guard self.height > 0 else {
            return 0
        }

        return self.width / self.height
    }

    var asPoint: CGPoint {
        return CGPoint(x: width, y: height)
    }

    var ceil: CGSize {
        return CGSizeCeil(self)
    }

    var abs: CGSize {
        return CGSize(width: Swift.abs(width), height: Swift.abs(height))
    }

    init(square: CGFloat) {
        self.init(width: square, height: square)
    }
}

// MARK: -

public extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }

    var topLeft: CGPoint {
        return origin
    }

    var topRight: CGPoint {
        return CGPoint(x: maxX, y: minY)
    }

    var bottomLeft: CGPoint {
        return CGPoint(x: minX, y: maxY)
    }

    var bottomRight: CGPoint {
        return CGPoint(x: maxX, y: maxY)
    }
}

// MARK: -

public extension CGAffineTransform {
    static func translate(_ point: CGPoint) -> CGAffineTransform {
        return CGAffineTransform(translationX: point.x, y: point.y)
    }

    static func scale(_ scaling: CGFloat) -> CGAffineTransform {
        return CGAffineTransform(scaleX: scaling, y: scaling)
    }

    func translate(_ point: CGPoint) -> CGAffineTransform {
        return translatedBy(x: point.x, y: point.y)
    }

    func scale(_ scaling: CGFloat) -> CGAffineTransform {
        return scaledBy(x: scaling, y: scaling)
    }

    func rotate(_ angleRadians: CGFloat) -> CGAffineTransform {
        return rotated(by: angleRadians)
    }
}

// MARK: -

public extension UIBezierPath {
    func addRegion(withPoints points: [CGPoint]) {
        guard let first = points.first else {
            owsFailDebug("No points.")
            return
        }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
        addLine(to: first)
    }
}

// MARK: -

@objc
public extension UIBarButtonItem {
    convenience init(image: UIImage?, style: UIBarButtonItem.Style, target: Any?, action: Selector?, accessibilityIdentifier: String) {
        self.init(image: image, style: style, target: target, action: action)

        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(image: UIImage?, landscapeImagePhone: UIImage?, style: UIBarButtonItem.Style, target: Any?, action: Selector?, accessibilityIdentifier: String) {
        self.init(image: image, landscapeImagePhone: landscapeImagePhone, style: style, target: target, action: action)

        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(title: String?, style: UIBarButtonItem.Style, target: Any?, action: Selector?, accessibilityIdentifier: String) {
        self.init(title: title, style: style, target: target, action: action)

        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(barButtonSystemItem systemItem: UIBarButtonItem.SystemItem, target: Any?, action: Selector?, accessibilityIdentifier: String) {
        self.init(barButtonSystemItem: systemItem, target: target, action: action)

        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(customView: UIView, accessibilityIdentifier: String) {
        self.init(customView: customView)

        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

// MARK: -

@objc
public extension UIButton {
    func setTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) {
        guard let templateImage = templateImage else {
            owsFailDebug("Missing image")
            return
        }
        setImage(templateImage.withRenderingMode(.alwaysTemplate), for: .normal)
        self.tintColor = tintColor
    }

    func setTemplateImageName(_ imageName: String, tintColor: UIColor) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        setTemplateImage(image, tintColor: tintColor)
    }

    class func withTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) -> UIButton {
        let imageView = UIButton()
        imageView.setTemplateImage(templateImage, tintColor: tintColor)
        return imageView
    }

    class func withTemplateImageName(_ imageName: String, tintColor: UIColor) -> UIButton {
        let imageView = UIButton()
        imageView.setTemplateImageName(imageName, tintColor: tintColor)
        return imageView
    }
}

// MARK: -

@objc
public extension UIImageView {
    func setImage(imageName: String) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        self.image = image
    }

    func setTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) {
        guard let templateImage = templateImage else {
            owsFailDebug("Missing image")
            return
        }
        self.image = templateImage.withRenderingMode(.alwaysTemplate)
        self.tintColor = tintColor
    }

    func setTemplateImageName(_ imageName: String, tintColor: UIColor) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        setTemplateImage(image, tintColor: tintColor)
    }

    class func withTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) -> UIImageView {
        let imageView = UIImageView()
        imageView.setTemplateImage(templateImage, tintColor: tintColor)
        return imageView
    }

    class func withTemplateImageName(_ imageName: String, tintColor: UIColor) -> UIImageView {
        let imageView = UIImageView()
        imageView.setTemplateImageName(imageName, tintColor: tintColor)
        return imageView
    }
}

// MARK: -

@objc
public extension UISearchBar {
    var textField: UITextField? {
        // TODO Xcode 11: Delete this once we're compiling only in Xcode 11
        #if swift(>=5.1)
        if #available(iOS 13, *) { return searchTextField }
        #endif

        guard let textField = self.value(forKey: "_searchField") as? UITextField else {
            owsFailDebug("Couldn't find UITextField.")
            return nil
        }
        return textField
    }
}

// MARK: -

@objc
public extension UITextView {
    func acceptAutocorrectSuggestion() {
        // https://stackoverflow.com/a/27865136/4509555
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }
}

// MARK: -

@objc
public extension UITextField {
    func acceptAutocorrectSuggestion() {
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }
}

public extension UIView {
    func firstAncestor<T>(ofType type: T.Type) -> T? {
        guard let superview = superview else {
            return nil
        }

        return superview as? T ?? superview.firstAncestor(ofType: type)
    }
}

public extension UIToolbar {
    static func clear() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.backgroundColor = .clear

        // Making a toolbar transparent requires setting an empty uiimage
        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)

        // hide 1px top-border
        toolbar.clipsToBounds = true

        return toolbar
    }
 }
