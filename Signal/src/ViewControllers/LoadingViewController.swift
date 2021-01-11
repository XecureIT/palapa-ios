//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// The initial presentation is intended to be indistinguishable from the Launch Screen.
// After a delay we present some "loading" UI so the user doesn't think the app is frozen.
@objc
public class LoadingViewController: UIViewController {

    var logoView: UIImageView!
    var topLabel: UILabel!
    var bottomLabel: UILabel!
    let labelStack = UIStackView()
    var topLabelTimer: Timer?
    var bottomLabelTimer: Timer?

    override public func loadView() {
        self.view = UIView()
        view.backgroundColor = UIColor.ows_signalBlue

        self.logoView = UIImageView(image: #imageLiteral(resourceName: "logoSignal"))
        view.addSubview(logoView)

        logoView.autoCenterInSuperview()

        self.topLabel = buildLabel()
        topLabel.alpha = 0
        topLabel.font = UIFont.ows_dynamicTypeTitle2
        topLabel.text = NSLocalizedString("DATABASE_VIEW_OVERLAY_TITLE", comment: "Title shown while the app is updating its database.")
        labelStack.addArrangedSubview(topLabel)

        self.bottomLabel = buildLabel()
        bottomLabel.alpha = 0
        bottomLabel.font = UIFont.ows_dynamicTypeBody
        bottomLabel.text = NSLocalizedString("DATABASE_VIEW_OVERLAY_SUBTITLE", comment: "Subtitle shown while the app is updating its database.")
        labelStack.addArrangedSubview(bottomLabel)

        labelStack.axis = .vertical
        labelStack.alignment = .center
        labelStack.spacing = 8
        view.addSubview(labelStack)

        labelStack.autoPinEdge(.top, to: .bottom, of: logoView, withOffset: 20)
        labelStack.autoPinLeadingToSuperviewMargin()
        labelStack.autoPinTrailingToSuperviewMargin()
        labelStack.setCompressionResistanceHigh()
        labelStack.setContentHuggingHigh()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: NSNotification.Name.OWSApplicationDidEnterBackground,
                                               object: nil)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // We only show the "loading" UI if it's a slow launch. Otherwise this ViewController
        // should be indistinguishable from the launch screen.
        let kTopLabelThreshold: TimeInterval = 5
        topLabelTimer = Timer.weakScheduledTimer(withTimeInterval: kTopLabelThreshold, target: self, selector: #selector(showTopLabel), userInfo: nil, repeats: false)

        let kBottomLabelThreshold: TimeInterval = 15
        topLabelTimer = Timer.weakScheduledTimer(withTimeInterval: kBottomLabelThreshold, target: self, selector: #selector(showBottomLabelAnimated), userInfo: nil, repeats: false)
    }

    // UIStackView removes hidden subviews from the layout.
    // UIStackView considers views with a sufficiently low
    // alpha to be "hidden".  This can cause layout to glitch
    // briefly when returning from background.  Therefore we
    // use a "min" alpha value when fading in labels that is
    // high enough to avoid this UIStackView behavior.
    private let kMinAlpha: CGFloat = 0.1

    @objc
    private func showBottomLabelAnimated() {
        Logger.verbose("")

        bottomLabel.layer.removeAllAnimations()
        bottomLabel.alpha = kMinAlpha
        UIView.animate(withDuration: 0.1) {
            self.bottomLabel.alpha = 1
        }
    }

    @objc
    private func showTopLabel() {
        topLabel.layer.removeAllAnimations()
        topLabel.alpha = 0.2
        UIView.animate(withDuration: 0.9, delay: 0, options: [.autoreverse, .repeat, .curveEaseInOut], animations: {
            self.topLabel.alpha = 1.0
        }, completion: nil)
    }

    private func showBottomLabel() {
        bottomLabel.layer.removeAllAnimations()
        self.bottomLabel.alpha = 1
    }

    // MARK: -

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        Logger.info("")

        guard viewHasEnteredBackground else {
            // If the app is returning from background, skip any
            // animations and show the top and bottom labels.
            return
        }

        topLabelTimer?.invalidate()
        topLabelTimer = nil
        bottomLabelTimer?.invalidate()
        bottomLabelTimer = nil

        showTopLabel()
        showBottomLabel()

        labelStack.layoutSubviews()
        view.layoutSubviews()
    }

    private var viewHasEnteredBackground = false

    @objc func didEnterBackground() {
        AssertIsOnMainThread()

        Logger.info("")

        viewHasEnteredBackground = true
    }

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    // MARK: 

    private func buildLabel() -> UILabel {
        let label = UILabel()

        label.textColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        return label
    }
}
