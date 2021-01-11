//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AboutTableViewController.h"
#import "PALAPA-Swift.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/UIUtil.h>

@import SafariServices;

@implementation AboutTableViewController

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_ABOUT", @"Navbar title");

    [self updateTableContents];

    // Crash app if user performs obscure gesture in order to test
    // crash reporting.
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(crashApp)];
    gesture.numberOfTouchesRequired = 2;
    gesture.numberOfTapsRequired = 5;
    [self.tableView addGestureRecognizer:gesture];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pushTokensDidChange:)
                                                 name:[OWSSyncPushTokensJob PushTokensDidChange]
                                               object:nil];
}

- (void)pushTokensDidChange:(NSNotification *)notification
{
    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak AboutTableViewController *weakSelf = self;

    OWSTableSection *informationSection = [OWSTableSection new];
    informationSection.headerTitle = NSLocalizedString(@"SETTINGS_INFORMATION_HEADER", @"");
    [informationSection addItem:[OWSTableItem labelItemWithText:NSLocalizedString(@"SETTINGS_VERSION", @"")
                                                  accessoryText:[[[NSBundle mainBundle] infoDictionary]
                                                                    objectForKey:@"CFBundleVersion"]]];

    [informationSection
        addItem:[OWSTableItem
                     disclosureItemWithText:NSLocalizedString(@"SETTINGS_LEGAL_TERMS_CELL", @"table cell label")
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"terms")
                                actionBlock:^{
                                    SFSafariViewController *safariVC = [[SFSafariViewController alloc]
                                        initWithURL:[NSURL URLWithString:kLegalTermsUrlString]];
                                    [weakSelf presentViewController:safariVC animated:YES completion:nil];
                                }]];

    [contents addSection:informationSection];

//    OWSTableSection *helpSection = [OWSTableSection new];
//    helpSection.headerTitle = NSLocalizedString(@"SETTINGS_HELP_HEADER", @"");
//    [helpSection
//        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_SUPPORT", @"")
//                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"support")
//                                         actionBlock:^{
//                                             SFSafariViewController *safariVC = [[SFSafariViewController alloc]
//                                                 initWithURL:[NSURL URLWithString:@"https://support.signal.org"]];
//                                             [weakSelf presentViewController:safariVC animated:YES completion:nil];
//                                         }]];
//    [contents addSection:helpSection];

    UILabel *copyrightLabel = [UILabel new];
    copyrightLabel.text = NSLocalizedString(@"SETTINGS_COPYRIGHT", @"");
    copyrightLabel.textColor = Theme.secondaryTextAndIconColor;
    copyrightLabel.font = [UIFont ows_regularFontWithSize:15.0f];
    copyrightLabel.numberOfLines = 2;
    copyrightLabel.lineBreakMode = NSLineBreakByWordWrapping;
    copyrightLabel.textAlignment = NSTextAlignmentCenter;
    informationSection.customFooterView = copyrightLabel;
    informationSection.customFooterHeight = @(60.f);

    if (SSKFeatureFlags.verboseAboutView) {
        [self addVerboseContents:contents];
    }

    self.contents = contents;
}

- (void)addVerboseContents:(OWSTableContents *)contents
{
    __block NSUInteger threadCount;
    __block NSUInteger messageCount;
    __block NSUInteger attachmentCount;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        threadCount = [TSThread anyCountWithTransaction:transaction];
        messageCount = [TSInteraction anyCountWithTransaction:transaction];
        attachmentCount = [TSAttachment anyCountWithTransaction:transaction];
    }];

    NSByteCountFormatter *byteCountFormatter = [NSByteCountFormatter new];

    // format counts with thousands separator
    NSNumberFormatter *numberFormatter = [NSNumberFormatter new];
    numberFormatter.formatterBehavior = NSNumberFormatterBehavior10_4;
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;

    OWSTableSection *debugSection = [OWSTableSection new];

    debugSection.headerTitle = @"Debug";

    NSString *environmentName = TSConstants.isUsingProductionService ? @"Production" : @"Staging";
    [debugSection
     addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Environment: %@", environmentName]]];

    NSString *formattedThreadCount = [numberFormatter stringFromNumber:@(threadCount)];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Threads: %@", formattedThreadCount]]];

    NSString *formattedMessageCount = [numberFormatter stringFromNumber:@(messageCount)];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Messages: %@", formattedMessageCount]]];

    NSString *formattedAttachmentCount = [numberFormatter stringFromNumber:@(attachmentCount)];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Attachments: %@",
                                                                    formattedAttachmentCount]]];

    NSString *dbSize = [byteCountFormatter stringFromByteCount:(long long)[self.databaseStorage databaseFileSize]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database size: %@", dbSize]]];

    NSString *dbWALSize =
        [byteCountFormatter stringFromByteCount:(long long)[self.databaseStorage databaseWALFileSize]];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database WAL size: %@", dbWALSize]]];

    NSString *dbSHMSize =
        [byteCountFormatter stringFromByteCount:(long long)[self.databaseStorage databaseSHMFileSize]];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database SHM size: %@", dbSHMSize]]];

    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"dataStoreForUI: %@",
                                                          NSStringForDataStore(StorageCoordinator.dataStoreForUI)]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"hasYdbFile: %d",
                                                                    StorageCoordinator.hasYdbFile]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"hasGrdbFile: %d",
                                                                    StorageCoordinator.hasGrdbFile]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"hasUnmigratedYdbFile: %d",
                                                                    StorageCoordinator.hasUnmigratedYdbFile]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"didEverUseYdb: %d",
                                                                    SSKPreferences.didEverUseYdb]]];

    [contents addSection:debugSection];

    OWSPreferences *preferences = Environment.shared.preferences;
    NSString *_Nullable pushToken = [preferences getPushToken];
    NSString *_Nullable voipToken = [preferences getVoipToken];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Push Token: %@", pushToken ?: @"None"]]];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"VOIP Token: %@", voipToken ?: @"None"]]];

    // Strip prefix from category, otherwise it's too long to fit into cell on a small device.
    NSString *audioCategory =
        [AVAudioSession.sharedInstance.category stringByReplacingOccurrencesOfString:@"AVAudioSessionCategory"
                                                                          withString:@""];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Audio Category: %@", audioCategory]]];
}

- (void)crashApp
{
    OWSFail(@"crashApp");
}

@end
