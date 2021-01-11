//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "PrivacySettingsTableViewController.h"
#import "BlockListViewController.h"
#import "OWS2FASettingsViewController.h"
#import "PALAPA-Swift.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@import SafariServices;

NS_ASSUME_NONNULL_BEGIN

static NSString *const kSealedSenderInfoURL = @"https://signal.org/blog/sealed-sender/";

@implementation PrivacySettingsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");

    [self observeNotifications];

    [self updateTableContents];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self updateTableContents];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenLockDidChange:)
                                                 name:OWSScreenLock.ScreenLockDidChange
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(configurationSettingsDidChange:) name:OWSSyncManagerConfigurationSyncDidCompleteNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (id<OWSUDManager>)udManager
{
    return SSKEnvironment.shared.udManager;
}

- (OWSPreferences *)preferences
{
    return Environment.shared.preferences;
}

- (OWSReadReceiptManager *)readReceiptManager
{
    return OWSReadReceiptManager.sharedManager;
}

- (id<OWSTypingIndicators>)typingIndicators
{
    return SSKEnvironment.shared.typingIndicators;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (TSAccountManager *)accountManager
{
    return TSAccountManager.sharedInstance;
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak PrivacySettingsTableViewController *weakSelf = self;

    OWSTableSection *blocklistSection = [OWSTableSection new];
    blocklistSection.headerTitle
        = NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE", @"Label for the block list section of the settings view");
    [blocklistSection
        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE",
                                                         @"Label for the block list section of the settings view")
                             accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"blocklist"]
                                         actionBlock:^{
                                             [weakSelf showBlocklist];
                                         }]];
    [contents addSection:blocklistSection];

    OWSTableSection *readReceiptsSection = [OWSTableSection new];
    readReceiptsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_READ_RECEIPT", @"Label for the 'read receipts' setting.");
    readReceiptsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_READ_RECEIPTS_SECTION_FOOTER", @"An explanation of the 'read receipts' setting.");
    [readReceiptsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_READ_RECEIPT",
                                                     @"Label for the 'read receipts' setting.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"read_receipts"]
                    isOnBlock:^{
                        return [OWSReadReceiptManager.sharedManager areReadReceiptsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleReadReceiptsSwitch:)]];
    [contents addSection:readReceiptsSection];

    OWSTableSection *typingIndicatorsSection = [OWSTableSection new];
    typingIndicatorsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_TYPING_INDICATORS", @"Label for the 'typing indicators' setting.");
    typingIndicatorsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_TYPING_INDICATORS_FOOTER", @"An explanation of the 'typing indicators' setting.");
    [typingIndicatorsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_TYPING_INDICATORS",
                                                     @"Label for the 'typing indicators' setting.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"typing_indicators"]
                    isOnBlock:^{
                        return [SSKEnvironment.shared.typingIndicators areTypingIndicatorsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleTypingIndicatorsSwitch:)]];
    [contents addSection:typingIndicatorsSection];

    // If pins are enabled for everyone, show the change pin section
    // TODO Linked PIN editing
    if (SSKFeatureFlags.pinsForEveryone && self.accountManager.isRegisteredPrimaryDevice) {
        OWSTableSection *pinsSection = [OWSTableSection new];
        pinsSection.headerTitle
            = NSLocalizedString(@"SETTINGS_PINS_TITLE", @"Title for the 'PINs' section of the privacy settings.");
        pinsSection.footerTitle
            = NSLocalizedString(@"SETTINGS_PINS_FOOTER", @"Footer for the 'PINs' section of the privacy settings.");
        [pinsSection
            addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_PINS_ITEM",
                                                             @"Label for the 'pins' item of the privacy settings.")
                                 accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"pin"]
                                             actionBlock:^{
                                                 [weakSelf showChangePin];
                                             }]];
        [contents addSection:pinsSection];
    }

    OWSTableSection *screenLockSection = [OWSTableSection new];
    screenLockSection.headerTitle = NSLocalizedString(
        @"SETTINGS_SCREEN_LOCK_SECTION_TITLE", @"Title for the 'screen lock' section of the privacy settings.");
    screenLockSection.footerTitle = NSLocalizedString(
        @"SETTINGS_SCREEN_LOCK_SECTION_FOOTER", @"Footer for the 'screen lock' section of the privacy settings.");
    [screenLockSection
        addItem:[OWSTableItem
                    switchItemWithText:NSLocalizedString(@"SETTINGS_SCREEN_LOCK_SWITCH_LABEL",
                                           @"Label for the 'enable screen lock' switch of the privacy settings.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"screenlock"]
                    isOnBlock:^{
                        return [OWSScreenLock.sharedManager isScreenLockEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:self
                    selector:@selector(isScreenLockEnabledDidChange:)]];
    [contents addSection:screenLockSection];

    if (OWSScreenLock.sharedManager.isScreenLockEnabled) {
        OWSTableSection *screenLockTimeoutSection = [OWSTableSection new];
        uint32_t screenLockTimeout = (uint32_t)round(OWSScreenLock.sharedManager.screenLockTimeout);
        NSString *screenLockTimeoutString = [self formatScreenLockTimeout:screenLockTimeout useShortFormat:YES];
        [screenLockTimeoutSection
            addItem:[OWSTableItem
                         disclosureItemWithText:
                             NSLocalizedString(@"SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
                                 @"Label for the 'screen lock activity timeout' setting of the privacy settings.")
                                     detailText:screenLockTimeoutString
                        accessibilityIdentifier:[NSString
                                                    stringWithFormat:@"settings.privacy.%@", @"screen_lock_timeout"]
                                    actionBlock:^{
                                        [weakSelf showScreenLockTimeoutUI];
                                    }]];
        [contents addSection:screenLockTimeoutSection];
    }

    OWSTableSection *screenSecuritySection = [OWSTableSection new];
    screenSecuritySection.headerTitle = NSLocalizedString(@"SETTINGS_SECURITY_TITLE", @"Section header");
    screenSecuritySection.footerTitle = NSLocalizedString(@"SETTINGS_SCREEN_SECURITY_DETAIL", nil);
    [screenSecuritySection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_SCREEN_SECURITY", @"")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"screen_security"]
                    isOnBlock:^{
                        return [Environment.shared.preferences screenSecurityIsEnabled];
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleScreenSecuritySwitch:)]];
    [contents addSection:screenSecuritySection];

    if (SSKFeatureFlags.calling) {
        // Allow calls to connect directly vs. using TURN exclusively
        OWSTableSection *callingSection = [OWSTableSection new];
        callingSection.headerTitle
            = NSLocalizedString(@"SETTINGS_SECTION_TITLE_CALLING", @"settings topic header for table section");
        callingSection.footerTitle = NSLocalizedString(@"SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE_DETAIL",
            @"User settings section footer, a detailed explanation");
        [callingSection
            addItem:[OWSTableItem
                        switchItemWithText:NSLocalizedString(@"SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE",
                                               @"Table cell label")
                        accessibilityIdentifier:[NSString
                                                    stringWithFormat:@"settings.privacy.%@", @"calling_hide_ip_address"]
                        isOnBlock:^{
                            return [Environment.shared.preferences doCallsHideIPAddress];
                        }
                        isEnabledBlock:^{
                            return YES;
                        }
                        target:weakSelf
                        selector:@selector(didToggleCallsHideIPAddressSwitch:)]];
        [contents addSection:callingSection];

        if (CallUIAdapter.isCallkitDisabledForLocale) {
            // Hide all CallKit-related prefs; CallKit is disabled.
        } else if (@available(iOS 11, *)) {
            OWSTableSection *callKitSection = [OWSTableSection new];
            [callKitSection
                addItem:[OWSTableItem
                            switchItemWithText:NSLocalizedString(
                                                   @"SETTINGS_PRIVACY_CALLKIT_SYSTEM_CALL_LOG_PREFERENCE_TITLE",
                                                   @"Short table cell label")
                            accessibilityIdentifier:[NSString
                                                        stringWithFormat:@"settings.privacy.%@", @"callkit_history"]
                            isOnBlock:^{
                                return [Environment.shared.preferences isSystemCallLogEnabled];
                            }
                            isEnabledBlock:^{
                                return YES;
                            }
                            target:weakSelf
                            selector:@selector(didToggleEnableSystemCallLogSwitch:)]];
            callKitSection.footerTitle = NSLocalizedString(
                @"SETTINGS_PRIVACY_CALLKIT_SYSTEM_CALL_LOG_PREFERENCE_DESCRIPTION", @"Settings table section footer.");
            [contents addSection:callKitSection];
        } else if (@available(iOS 10, *)) {
            OWSTableSection *callKitSection = [OWSTableSection new];
            callKitSection.footerTitle
                = NSLocalizedString(@"SETTINGS_SECTION_CALL_KIT_DESCRIPTION", @"Settings table section footer.");
            [callKitSection
                addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_PRIVACY_CALLKIT_TITLE",
                                                             @"Short table cell label")
                            accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"callkit"]
                            isOnBlock:^{
                                return [Environment.shared.preferences isCallKitEnabled];
                            }
                            isEnabledBlock:^{
                                return YES;
                            }
                            target:weakSelf
                            selector:@selector(didToggleEnableCallKitSwitch:)]];
            if (self.preferences.isCallKitEnabled) {
                [callKitSection addItem:[OWSTableItem switchItemWithText:NSLocalizedString(
                                                                             @"SETTINGS_PRIVACY_CALLKIT_PRIVACY_TITLE",
                                                                             @"Label for 'CallKit privacy' preference")
                                            accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@",
                                                                              @"callkit_privacy"]
                                            isOnBlock:^{
                                                return (BOOL) ![Environment.shared.preferences isCallKitPrivacyEnabled];
                                            }
                                            isEnabledBlock:^{
                                                return YES;
                                            }
                                            target:weakSelf
                                            selector:@selector(didToggleEnableCallKitPrivacySwitch:)]];
            }
            [contents addSection:callKitSection];
        }
    }

    // If pins are enabled for everyone, everyone has registration lock so we don't need this section
    // TODO Linked PIN editing
    if (!SSKFeatureFlags.pinsForEveryone && self.accountManager.isRegisteredPrimaryDevice) {
        OWSTableSection *twoFactorAuthSection = [OWSTableSection new];
        twoFactorAuthSection.headerTitle = NSLocalizedString(
            @"SETTINGS_TWO_FACTOR_AUTH_TITLE", @"Title for the 'two factor auth' section of the privacy settings.");
        [twoFactorAuthSection
            addItem:[OWSTableItem
                        disclosureItemWithText:NSLocalizedString(@"SETTINGS_TWO_FACTOR_AUTH_ITEM",
                                                   @"Label for the 'two factor auth' item of the privacy settings.")
                                    detailText:([OWS2FAManager.sharedManager is2FAEnabled]
                                                       ? NSLocalizedString(@"SETTINGS_TWO_FACTOR_AUTH_ENABLED",
                                                           @"Indicates that 'two factor auth' is enabled in the "
                                                           @"privacy settings.")
                                                       : NSLocalizedString(@"SETTINGS_TWO_FACTOR_AUTH_DISABLED",
                                                           @"Indicates that 'two factor auth' is disabled in the "
                                                           @"privacy settings."))accessibilityIdentifier
                                              :[NSString stringWithFormat:@"settings.privacy.%@", @"2fa"]
                                   actionBlock:^{
                                       [weakSelf show2FASettings];
                                   }]];
        [contents addSection:twoFactorAuthSection];
    }

    OWSTableSection *historyLogsSection = [OWSTableSection new];
    historyLogsSection.headerTitle = NSLocalizedString(@"SETTINGS_HISTORYLOG_TITLE", @"Section header");
    [historyLogsSection
        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_CLEAR_HISTORY", @"")
                             accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"clear_logs"]
                                         actionBlock:^{
                                             [weakSelf clearHistoryLogs];
                                         }]];
    [contents addSection:historyLogsSection];

    OWSTableSection *unidentifiedDeliveryIndicatorsSection = [OWSTableSection new];
    unidentifiedDeliveryIndicatorsSection.headerTitle
        = NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_SECTION_TITLE", @"table section label");
    [unidentifiedDeliveryIndicatorsSection
        addItem:[OWSTableItem
                    itemWithCustomCellBlock:^UITableViewCell * {
                        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                                       reuseIdentifier:@"UITableViewCellStyleValue1"];
                        [OWSTableItem configureCell:cell];
                        cell.preservesSuperviewLayoutMargins = YES;
                        cell.contentView.preservesSuperviewLayoutMargins = YES;
                        cell.selectionStyle = UITableViewCellSelectionStyleNone;

                        UILabel *label = [UILabel new];
                        label.text
                            = NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_SHOW_INDICATORS", @"switch label");
                        label.font = [UIFont ows_regularFontWithSize:18.f];
                        label.textColor = Theme.primaryTextColor;
                        [label setContentHuggingHorizontalHigh];

                        UIImage *icon = [UIImage imageNamed:@"ic_secret_sender_indicator"];
                        UIImageView *iconView = [[UIImageView alloc]
                            initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                        iconView.tintColor = Theme.secondaryTextAndIconColor;
                        [iconView setContentHuggingHorizontalHigh];

                        UIView *spacer = [UIView new];
                        [spacer setContentHuggingHorizontalLow];

                        UIStackView *stackView =
                            [[UIStackView alloc] initWithArrangedSubviews:@[ label, iconView, spacer ]];
                        stackView.axis = UILayoutConstraintAxisHorizontal;
                        stackView.spacing = 10;
                        stackView.alignment = UIStackViewAlignmentCenter;

                        [cell.contentView addSubview:stackView];
                        [stackView ows_autoPinToSuperviewMargins];

                        UISwitch *cellSwitch = [UISwitch new];
                        [cellSwitch setOn:Environment.shared.preferences.shouldShowUnidentifiedDeliveryIndicators];
                        [cellSwitch addTarget:weakSelf
                                       action:@selector(didToggleUDShowIndicatorsSwitch:)
                             forControlEvents:UIControlEventValueChanged];
                        cell.accessoryView = cellSwitch;
                        cellSwitch.accessibilityIdentifier =
                            [NSString stringWithFormat:@"settings.privacy.%@", @"sealed_sender"];

                        return cell;
                    }
                    customRowHeight:UITableViewAutomaticDimension
                    actionBlock:^{
                        NSURL *url = [NSURL URLWithString:kSealedSenderInfoURL];
                        OWSCAssertDebug(url);
                        SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:url];
                        [weakSelf presentViewController:safariVC animated:YES completion:nil];
                    }]];

    unidentifiedDeliveryIndicatorsSection.footerTitle
        = NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_SHOW_INDICATORS_FOOTER", @"table section footer");
    [contents addSection:unidentifiedDeliveryIndicatorsSection];

    // Only the primary device can adjust the unrestricted UD setting. We don't sync this setting.
    if (self.accountManager.isRegisteredPrimaryDevice) {
        OWSTableSection *unidentifiedDeliveryUnrestrictedSection = [OWSTableSection new];
        OWSTableItem *unrestrictedAccessItem = [OWSTableItem
            switchItemWithText:NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_UNRESTRICTED_ACCESS", @"switch label")
            accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"sealed_sender_unrestricted"]
            isOnBlock:^{
                return [SSKEnvironment.shared.udManager shouldAllowUnrestrictedAccessLocal];
            }
            isEnabledBlock:^{
                return YES;
            }
            target:weakSelf
            selector:@selector(didToggleUDUnrestrictedAccessSwitch:)];
        [unidentifiedDeliveryUnrestrictedSection addItem:unrestrictedAccessItem];
        unidentifiedDeliveryUnrestrictedSection.footerTitle
            = NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_UNRESTRICTED_ACCESS_FOOTER", @"table section footer");
        [contents addSection:unidentifiedDeliveryUnrestrictedSection];
    }

    OWSTableSection *unidentifiedDeliveryLearnMoreSection = [OWSTableSection new];
    [unidentifiedDeliveryLearnMoreSection
        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_UNIDENTIFIED_DELIVERY_LEARN_MORE",
                                                         @"Label for a link to more info about unidentified delivery.")
                             accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@",
                                                               @"sealed_sender_learn_more"]
                                         actionBlock:^{
                                             NSURL *url = [NSURL URLWithString:kSealedSenderInfoURL];
                                             OWSCAssertDebug(url);
                                             SFSafariViewController *safariVC =
                                                 [[SFSafariViewController alloc] initWithURL:url];
                                             [weakSelf presentViewController:safariVC animated:YES completion:nil];
                                         }]];
    // [contents addSection:unidentifiedDeliveryLearnMoreSection];

    OWSTableSection *linkPreviewsSection = [OWSTableSection new];
    [linkPreviewsSection
        addItem:[OWSTableItem switchItemWithText:NSLocalizedString(@"SETTINGS_LINK_PREVIEWS",
                                                     @"Setting for enabling & disabling link previews.")
                    accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.%@", @"link_previews"]
                    isOnBlock:^{
                        if (!weakSelf) {
                            return NO;
                        }
                        PrivacySettingsTableViewController *strongSelf = weakSelf;

                        __block BOOL areLinkPreviewsEnabled;
                        [strongSelf.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                            areLinkPreviewsEnabled = [SSKPreferences areLinkPreviewsEnabledWithTransaction:transaction];
                        }];
                        return areLinkPreviewsEnabled;
                    }
                    isEnabledBlock:^{
                        return YES;
                    }
                    target:weakSelf
                    selector:@selector(didToggleLinkPreviewsEnabled:)]];
    linkPreviewsSection.headerTitle = NSLocalizedString(
        @"SETTINGS_LINK_PREVIEWS_HEADER", @"Header for setting for enabling & disabling link previews.");
    linkPreviewsSection.footerTitle = NSLocalizedString(
        @"SETTINGS_LINK_PREVIEWS_FOOTER", @"Footer for setting for enabling & disabling link previews.");
    [contents addSection:linkPreviewsSection];

    self.contents = contents;
}

#pragma mark - Events

- (void)showBlocklist
{
    BlockListViewController *vc = [BlockListViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)clearHistoryLogs
{
    ActionSheetController *alert =
        [[ActionSheetController alloc] initWithTitle:nil
                                             message:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION",
                                                         @"Alert message before user confirms clearing history")];

    [alert addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *deleteAction = [[ActionSheetAction
        alloc] initWithTitle:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON",
                                 @"Confirmation text for button which deletes all message, calling, attachments, etc.")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"delete")
                          style:ActionSheetActionStyleDestructive
                        handler:^(ActionSheetAction *_Nonnull action) {
                            [self deleteThreadsAndMessages];
                        }];
    [alert addAction:deleteAction];

    [self presentActionSheet:alert];
}

- (void)deleteThreadsAndMessages
{
    [ThreadUtil deleteAllContent];
}

- (void)didToggleScreenSecuritySwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled screen security: %@", enabled ? @"ON" : @"OFF");
    [self.preferences setScreenSecurity:enabled];
}

- (void)didToggleReadReceiptsSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled areReadReceiptsEnabled: %@", enabled ? @"ON" : @"OFF");
    [self.readReceiptManager setAreReadReceiptsEnabledWithSneakyTransactionAndSyncConfiguration:enabled];
}

- (void)didToggleTypingIndicatorsSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled areTypingIndicatorsEnabled: %@", enabled ? @"ON" : @"OFF");
    [self.typingIndicators setTypingIndicatorsEnabledAndSendSyncMessageWithValue:enabled];
}

- (void)didToggleCallsHideIPAddressSwitch:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    OWSLogInfo(@"toggled callsHideIPAddress: %@", enabled ? @"ON" : @"OFF");
    [self.preferences setDoCallsHideIPAddress:enabled];
}

- (void)didToggleEnableSystemCallLogSwitch:(UISwitch *)sender
{
    OWSLogInfo(@"user toggled call kit preference: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.preferences setIsSystemCallLogEnabled:sender.isOn];

    // rebuild callUIAdapter since CallKit configuration changed.
    [AppEnvironment.shared.callService createCallUIAdapter];
}

- (void)didToggleEnableCallKitSwitch:(UISwitch *)sender
{
    OWSLogInfo(@"user toggled call kit preference: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.preferences setIsCallKitEnabled:sender.isOn];

    // rebuild callUIAdapter since CallKit vs not changed.
    [AppEnvironment.shared.callService createCallUIAdapter];

    // Show/Hide dependent switch: CallKit privacy
    [self updateTableContents];
}

- (void)didToggleEnableCallKitPrivacySwitch:(UISwitch *)sender
{
    OWSLogInfo(@"user toggled call kit privacy preference: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.preferences setIsCallKitPrivacyEnabled:!sender.isOn];

    // rebuild callUIAdapter since CallKit configuration changed.
    [AppEnvironment.shared.callService createCallUIAdapter];
}

- (void)didToggleUDUnrestrictedAccessSwitch:(UISwitch *)sender
{
    OWSLogInfo(@"toggled to: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.udManager setShouldAllowUnrestrictedAccessLocal:sender.isOn];
}

- (void)didToggleUDShowIndicatorsSwitch:(UISwitch *)sender
{
    OWSLogInfo(@"toggled to: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.preferences setShouldShowUnidentifiedDeliveryIndicatorsAndSendSyncMessage:sender.isOn];
}

- (void)didToggleLinkPreviewsEnabled:(UISwitch *)sender
{
    OWSLogInfo(@"toggled to: %@", (sender.isOn ? @"ON" : @"OFF"));
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [SSKPreferences setAreLinkPreviewsEnabledAndSendSyncMessage:sender.isOn transaction:transaction];
    }];
}

- (void)show2FASettings
{
    OWSLogInfo(@"");

    OWS2FASettingsViewController *vc = [OWS2FASettingsViewController new];
    vc.mode = OWS2FASettingsMode_Status;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showChangePin
{
    OWSLogInfo(@"");

    __weak PrivacySettingsTableViewController *weakSelf = self;
    OWSPinSetupViewController *vc = [OWSPinSetupViewController changingWithCompletionHandler:^{
        [weakSelf.navigationController popToViewController:weakSelf animated:YES];
    }];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)isScreenLockEnabledDidChange:(UISwitch *)sender
{
    BOOL shouldBeEnabled = sender.isOn;

    if (shouldBeEnabled == OWSScreenLock.sharedManager.isScreenLockEnabled) {
        OWSLogInfo(@"ignoring redundant screen lock.");
        return;
    }

    OWSLogInfo(@"trying to set is screen lock enabled: %@", @(shouldBeEnabled));

    [OWSScreenLock.sharedManager setIsScreenLockEnabled:shouldBeEnabled];
}

- (void)screenLockDidChange:(NSNotification *)notification
{
    OWSLogInfo(@"");

    [self updateTableContents];
}

- (void)showScreenLockTimeoutUI
{
    OWSLogInfo(@"");

    ActionSheetController *alert = [[ActionSheetController alloc]
        initWithTitle:NSLocalizedString(@"SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
                          @"Label for the 'screen lock activity timeout' setting of the privacy settings.")
              message:nil];
    for (NSNumber *timeoutValue in OWSScreenLock.sharedManager.screenLockTimeouts) {
        uint32_t screenLockTimeout = (uint32_t)round(timeoutValue.doubleValue);
        NSString *screenLockTimeoutString = [self formatScreenLockTimeout:screenLockTimeout useShortFormat:NO];

        ActionSheetAction *action = [[ActionSheetAction alloc]
                      initWithTitle:screenLockTimeoutString
            accessibilityIdentifier:[NSString stringWithFormat:@"settings.privacy.timeout.%@", timeoutValue]
                              style:ActionSheetActionStyleDefault
                            handler:^(ActionSheetAction *ignore) {
                                [OWSScreenLock.sharedManager setScreenLockTimeout:screenLockTimeout];
                            }];
        [alert addAction:action];
    }
    [alert addAction:[OWSActionSheets cancelAction]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentActionSheet:alert];
}

- (NSString *)formatScreenLockTimeout:(NSInteger)value useShortFormat:(BOOL)useShortFormat
{
    if (value <= 1) {
        return NSLocalizedString(@"SCREEN_LOCK_ACTIVITY_TIMEOUT_NONE",
            @"Indicates a delay of zero seconds, and that 'screen lock activity' will timeout immediately.");
    }
    return [NSString formatDurationSeconds:(uint32_t)value useShortFormat:useShortFormat];
}

- (void)configurationSettingsDidChange:(NSNotification *)notification
{
    OWSLogInfo(@"");

    [self updateTableContents];
}

@end

NS_ASSUME_NONNULL_END
