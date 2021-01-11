//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer
import SignalServiceKit

// A modal view that be used during blocking interactions (e.g. waiting on response from
// service or on the completion of a long-running local operation).
@objc
public class ModalActivityIndicatorViewController: OWSViewController {

    let canCancel: Bool

    @objc
    public var wasCancelled: Bool = false

    var activityIndicator: UIActivityIndicatorView?

    var presentTimer: Timer?

    var wasDimissed: Bool = false

    private static let kPresentationDelayDefault: TimeInterval = 1
    private let presentationDelay: TimeInterval

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public required init(canCancel: Bool, presentationDelay: TimeInterval) {
        self.canCancel = canCancel
        self.presentationDelay = presentationDelay

        super.init(nibName: nil, bundle: nil)
    }

    @objc
    public class func present(fromViewController: UIViewController,
                              canCancel: Bool,
                              backgroundBlock : @escaping (ModalActivityIndicatorViewController) -> Void) {
        present(fromViewController: fromViewController,
                canCancel: canCancel,
                presentationDelay: kPresentationDelayDefault,
                backgroundBlock: backgroundBlock)
    }

    @objc
    public class func present(fromViewController: UIViewController,
                              canCancel: Bool,
                              presentationDelay: TimeInterval,
                              backgroundBlock : @escaping (ModalActivityIndicatorViewController) -> Void) {
        AssertIsOnMainThread()

        let view = ModalActivityIndicatorViewController(canCancel: canCancel, presentationDelay: presentationDelay)
        // Present this modal _over_ the current view contents.
        view.modalPresentationStyle = .overFullScreen
        fromViewController.present(view,
                                   animated: false) {
                                    DispatchQueue.global().async {
                                        backgroundBlock(view)
                                    }
        }
    }

    @objc
    public func dismiss(completion : @escaping () -> Void) {
        AssertIsOnMainThread()

        if !wasDimissed {
            // Only dismiss once.
            self.dismiss(animated: false, completion: completion)
            wasDimissed = true
        } else {
            // If already dismissed, wait a beat then call completion.
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    public override func loadView() {
        super.loadView()

        self.view.backgroundColor = (Theme.isDarkThemeEnabled
            ? UIColor(white: 0.35, alpha: 0.35)
            : UIColor(white: 0, alpha: 0.25))
        self.view.isOpaque = false

        let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()

        if canCancel {
            let cancelButton = UIButton(type: .custom)
            cancelButton.setTitle(CommonStrings.cancelButton, for: .normal)
            cancelButton.setTitleColor(UIColor.white, for: .normal)
            cancelButton.backgroundColor = UIColor.ows_gray80
            let font = UIFont.ows_dynamicTypeBody.ows_semibold()
            cancelButton.titleLabel?.font = font
            cancelButton.layer.cornerRadius = ScaleFromIPhone5To7Plus(4, 5)
            cancelButton.clipsToBounds = true
            cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
            let buttonWidth = ScaleFromIPhone5To7Plus(140, 160)
            let buttonHeight = OWSFlatButton.heightForFont(font)
            self.view.addSubview(cancelButton)
            cancelButton.autoHCenterInSuperview()
            cancelButton.autoPinEdge(toSuperviewEdge: .bottom, withInset: 50)
            cancelButton.autoSetDimension(.width, toSize: buttonWidth)
            cancelButton.autoSetDimension(.height, toSize: buttonHeight)
        }

        guard presentationDelay > 0 else {
            return
        }

        // Hide the modal until the presentation animation completes.
        self.view.layer.opacity = 0.0
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.activityIndicator?.startAnimating()

        guard presentationDelay > 0 else {
            return
        }

        // Hide the the modal and wait for a second before revealing it,
        // to avoid "blipping" in the modal during short blocking operations.
        //
        // NOTE: It will still intercept user interactions while hidden, as it
        //       should.
        self.presentTimer?.invalidate()
        self.presentTimer = Timer.weakScheduledTimer(withTimeInterval: presentationDelay, target: self, selector: #selector(presentTimerFired), userInfo: nil, repeats: false)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        clearTimer()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.activityIndicator?.stopAnimating()

        clearTimer()
    }

    private func clearTimer() {
        self.presentTimer?.invalidate()
        self.presentTimer = nil
    }

    @objc func presentTimerFired() {
        AssertIsOnMainThread()

        clearTimer()

        // Fade in the modal.
        UIView.animate(withDuration: 0.35) {
            self.view.layer.opacity = 1.0
        }
    }

    @objc func cancelPressed() {
        AssertIsOnMainThread()

        wasCancelled = true

        dismiss {
        }
    }
}
