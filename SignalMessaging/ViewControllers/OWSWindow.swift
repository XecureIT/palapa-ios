//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class OWSWindow: UIWindow {
    public override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: NSNotification.Name.ThemeDidChange,
            object: nil
        )

        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    private func applyTheme() {
        guard #available(iOS 13, *) else { return }

        // TODO Xcode 11: Delete this once we're compiling only in Xcode 11
        #if swift(>=5.1)

        // Ensure system UI elements use the appropriate styling for the selected theme.
        switch Theme.getOrFetchCurrentTheme() {
        case .light:
            overrideUserInterfaceStyle = .light
        case .dark:
            overrideUserInterfaceStyle = .dark
        case .system:
            overrideUserInterfaceStyle = .unspecified
        }

        #endif
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard #available(iOS 13, *) else { return }

        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            Theme.systemThemeChanged()
        }
    }
}
