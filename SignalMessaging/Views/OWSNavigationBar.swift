//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
public protocol NavBarLayoutDelegate: class {
    func navBarCallLayoutDidChange(navbar: OWSNavigationBar)
}

@objc
public class OWSNavigationBar: UINavigationBar {

    @objc
    public weak var navBarLayoutDelegate: NavBarLayoutDelegate?

    @objc
    public let navbarWithoutStatusHeight: CGFloat = 44

    @objc
    public var callBannerHeight: CGFloat {
        return OWSWindowManagerCallBannerHeight()
    }

    @objc
    public var statusBarHeight: CGFloat {
        return CurrentAppContext().statusBarHeight
    }

    @objc
    public var fullWidth: CGFloat {
        return superview?.frame.width ?? .zero
    }

    public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public static let backgroundBlurMutingFactor: CGFloat = 0.5
    var blurEffectView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(callDidChange), name: .OWSWindowManagerCallDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeStatusBarFrame), name: UIApplication.didChangeStatusBarFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    // MARK: Theme

    private func applyTheme() {
        guard respectsTheme else {
            return
        }

        if currentStyle == .secondaryBar {
            let color = Theme.secondaryBackgroundColor
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)
        } else if UIAccessibility.isReduceTransparencyEnabled {
            blurEffectView?.isHidden = true
            let color = Theme.navbarBackgroundColor
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)
        } else {
            // Make navbar more translucent than default. Navbars remove alpha from any assigned backgroundColor, so
            // to achieve transparency, we have to assign a transparent image.
            let color = Theme.navbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)

            let blurEffect = Theme.barBlurEffect

            let blurEffectView: UIVisualEffectView = {
                if let existingBlurEffectView = self.blurEffectView {
                    existingBlurEffectView.isHidden = false
                    return existingBlurEffectView
                }

                let blurEffectView = UIVisualEffectView()
                blurEffectView.isUserInteractionEnabled = false

                self.blurEffectView = blurEffectView
                self.insertSubview(blurEffectView, at: 0)

                // navbar frame doesn't account for statusBar, so, same as the built-in navbar background, we need to exceed
                // the navbar bounds to have the blur extend up and behind the status bar.
                blurEffectView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: -statusBarHeight, left: 0, bottom: 0, right: 0))

                return blurEffectView
            }()

            blurEffectView.effect = blurEffect

            // remove hairline below bar.
            self.shadowImage = UIImage()

            // On iOS11, despite inserting the blur at 0, other views are later inserted into the navbar behind the blur,
            // so we have to set a zindex to avoid obscuring navbar title/buttons.
            blurEffectView.layer.zPosition = -1
        }
    }

    public func snapshotViewIncludingBackground(afterScreenUpdates: Bool) -> UIView? {
        let originalFrame = self.frame
        let originalBounds = self.bounds

        // NavigationBars are weird because though it appears as though the status bar
        // content is "in" or maybe "above" (z-index) the navbar, the navbar frame is strictly
        // lower (y-index) than the status bar.
        // To work with that, the navbar background, including the blur effect when transparency
        // is enabled, extends beyond the navbars's bounds. This allows the background to extend
        // up (y-index) and under (z-index) the status bar, without clips to bounds.
        //
        // Snapshots, however, clip to bounds. So as to capture the full size of the background
        // in our snapshot we temporarily adjust the navbars frame.
        self.frame = CGRect(x: 0, y: callBannerHeight, width: fullWidth, height: navbarWithoutStatusHeight + statusBarHeight)
        self.bounds = self.frame
        defer {
            self.frame = originalFrame
            self.bounds = originalBounds
        }

        guard let barSnapshot = self.snapshotView(afterScreenUpdates: afterScreenUpdates) else {
            owsFailDebug("barSnapshot was unexpectedly nil")
            return nil
        }

        barSnapshot.frame.origin = .zero

        return barSnapshot
    }

    @objc
    public func themeDidChange() {
        Logger.debug("")
        applyTheme()
    }

    @objc
    public var respectsTheme: Bool = true {
        didSet {
            themeDidChange()
        }
    }

    // MARK: Layout

    @objc
    public func callDidChange() {
        Logger.debug("")
        self.navBarLayoutDelegate?.navBarCallLayoutDidChange(navbar: self)
    }

    @objc
    public func didChangeStatusBarFrame() {
        Logger.debug("")
        self.navBarLayoutDelegate?.navBarCallLayoutDidChange(navbar: self)
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard OWSWindowManager.shared.hasCall else {
            return super.sizeThatFits(size)
        }

        if #available(iOS 11, *) {
            return super.sizeThatFits(size)
        } else if #available(iOS 10, *) {
            // iOS10
            // sizeThatFits is repeatedly called to determine how much space to reserve for that navbar.
            // That is, increasing this causes the child view controller to be pushed down.
            // (as of iOS11, this is not used and instead we use additionalSafeAreaInsets)
            return CGSize(width: fullWidth, height: navbarWithoutStatusHeight + statusBarHeight)
        } else {
            // iOS9
            // sizeThatFits is repeatedly called to determine how much space to reserve for that navbar.
            // That is, increasing this causes the child view controller to be pushed down.
            // (as of iOS11, this is not used and instead we use additionalSafeAreaInsets)            
            return CGSize(width: fullWidth, height: navbarWithoutStatusHeight + callBannerHeight + 20)
        }
    }

    public override func layoutSubviews() {
        guard CurrentAppContext().isMainApp else {
            super.layoutSubviews()
            return
        }
        guard OWSWindowManager.shared.hasCall else {
            super.layoutSubviews()
            return
        }

        guard #available(iOS 11, *) else {
            super.layoutSubviews()
            return
        }

        super.layoutSubviews()

        self.frame = CGRect(x: 0, y: callBannerHeight, width: fullWidth, height: navbarWithoutStatusHeight)
        self.bounds = CGRect(x: 0, y: 0, width: fullWidth, height: navbarWithoutStatusHeight)

        // This is only necessary on iOS11, which has some private views within that lay outside of the navbar.
        // They aren't actually visible behind the call status bar, but they looks strange during present/dismiss
        // animations for modal VC's
        for subview in self.subviews {
            let stringFromClass = NSStringFromClass(subview.classForCoder)
            if stringFromClass.contains("BarBackground") {
                subview.frame = self.bounds
            } else if stringFromClass.contains("BarContentView") {
                subview.frame = self.bounds
            }
        }
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()

        // `fullWidth` will not be accurate until the navbar has a defined
        // superview. By forcing a re-layout after moving to a superview, we
        // ensure that the correct width is always used. This works around a bug
        // on iPad where the navigation bar is larger than the application frame
        // when in slide over mode.
        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: Override Theme

    @objc
    public enum NavigationBarStyle: Int {
        case clear, alwaysDark, `default`, secondaryBar
    }

    private var currentStyle: NavigationBarStyle?

    @objc
    public func switchToStyle(_ style: NavigationBarStyle) {
        let applyDarkThemeOverride = {
            self.barStyle = .black
            self.titleTextAttributes = [NSAttributedString.Key.foregroundColor: Theme.darkThemePrimaryColor]
            self.barTintColor = Theme.darkThemeBackgroundColor.withAlphaComponent(0.6)
            self.tintColor = Theme.darkThemePrimaryColor
        }

        let removeDarkThemeOverride = {
            self.barStyle = Theme.barStyle
            self.titleTextAttributes = [NSAttributedString.Key.foregroundColor: Theme.primaryTextColor]
            self.barTintColor = Theme.backgroundColor.withAlphaComponent(0.6)
            self.tintColor = Theme.primaryTextColor
        }

        let applyTransparentBarOverride = {
            self.blurEffectView?.isHidden = true
            self.clipsToBounds = true

            // Making a toolbar transparent requires setting an empty uiimage
            self.setBackgroundImage(UIImage(), for: .default)
            self.shadowImage = UIImage()
            self.backgroundColor = .clear
        }

        let removeTransparentBarOverride = {
            self.blurEffectView?.isHidden = false
            self.clipsToBounds = false

            self.setBackgroundImage(nil, for: .default)
            self.shadowImage = nil
        }

        let applySecondaryBarOverride = {
            self.blurEffectView?.isHidden = true
            self.shadowImage = UIImage()
        }

        let removeSecondaryBarOverride = {
            self.blurEffectView?.isHidden = false
            self.shadowImage = nil
        }

        currentStyle = style

        switch style {
        case .clear:
            respectsTheme = false
            removeSecondaryBarOverride()
            applyDarkThemeOverride()
            applyTransparentBarOverride()
        case .alwaysDark:
            respectsTheme = false
            removeSecondaryBarOverride()
            removeTransparentBarOverride()
            applyDarkThemeOverride()
        case .default:
            respectsTheme = true
            removeDarkThemeOverride()
            removeTransparentBarOverride()
            removeSecondaryBarOverride()
            applyTheme()
        case .secondaryBar:
            respectsTheme = true
            removeDarkThemeOverride()
            removeTransparentBarOverride()
            applySecondaryBarOverride()
            applyTheme()
        }
    }
}
