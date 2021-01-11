//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewController.h"
#import "BlockListUIUtils.h"
#import "ContactsViewHelper.h"
#import "FingerprintViewController.h"
#import "OWSAddToContactViewController.h"
#import "OWSBlockingManager.h"
#import "OWSSoundSettingsViewController.h"
#import "PhoneNumber.h"
#import "ShowGroupMembersViewController.h"
#import "PALAPA-Swift.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "UpdateGroupViewController.h"
#import <ContactsUI/ContactsUI.h>
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSAvatarBuilder.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/OWSSounds.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

//#define SHOW_COLOR_PICKER

const CGFloat kIconViewLength = 24;

@interface OWSConversationSettingsViewController () <ContactsViewHelperDelegate,
#ifdef SHOW_COLOR_PICKER
    ColorPickerDelegate,
#endif
    OWSSheetViewControllerDelegate>

@property (nonatomic) TSThread *thread;

@property (nonatomic) NSArray<NSNumber *> *disappearingMessagesDurations;
@property (nonatomic) OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) UIImageView *avatarView;
@property (nonatomic, readonly) UILabel *disappearingMessagesDurationLabel;
#ifdef SHOW_COLOR_PICKER
@property (nonatomic) OWSColorPicker *colorPicker;
#endif

@end

#pragma mark -

@implementation OWSConversationSettingsViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)commonInit
{
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];

    [self observeNotifications];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (OWSContactsManager *)contactsManager
{
    return Environment.shared.contactsManager;
}

- (OWSMessageSender *)messageSender
{
    return SSKEnvironment.shared.messageSender;
}

- (OWSBlockingManager *)blockingManager
{
    return [OWSBlockingManager sharedManager];
}

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(identityStateDidChange:)
                                                 name:kNSNotificationName_IdentityStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];
}

- (NSString *)threadName
{
    NSString *threadName = [self.contactsManager displayNameForThreadWithSneakyTransaction:self.thread];

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        return threadName;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    NSString *_Nullable phoneNumber = contactThread.contactAddress.phoneNumber;
    if (phoneNumber && [threadName isEqualToString:phoneNumber]) {
        threadName = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:phoneNumber];
    }

    return threadName;
}

- (BOOL)isGroupThread
{
    return [self.thread isKindOfClass:[TSGroupThread class]];
}

- (BOOL)hasSavedGroupIcon
{
    if (![self isGroupThread]) {
        return NO;
    }

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    return groupThread.groupModel.groupAvatarData.length > 0;
}

- (BOOL)hasGroupEditPermission
{
    if (![self isGroupThread]) {
        return NO;
    }
    
    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    return groupThread.isLocalUserGroupOwner || groupThread.isLocalUserGroupAdmin;
}

- (void)configureWithThread:(TSThread *)thread
{
    OWSAssertDebug(thread);
    self.thread = thread;

    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        self.title = NSLocalizedString(
            @"CONVERSATION_SETTINGS_CONTACT_INFO_TITLE", @"Navbar title when viewing settings for a 1-on-1 thread");
    } else {
        self.title = NSLocalizedString(
            @"CONVERSATION_SETTINGS_GROUP_INFO_TITLE", @"Navbar title when viewing settings for a group thread");
    }
}

- (BOOL)hasExistingContact
{
    OWSAssertDebug([self.thread isKindOfClass:[TSContactThread class]]);
    TSContactThread *contactThread = (TSContactThread *)self.thread;
    SignalServiceAddress *recipientAddress = contactThread.contactAddress;
    return [self.contactsManager hasSignalAccountForAddress:recipientAddress];
}

#pragma mark - CNContactViewControllerDelegate

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(nullable CNContact *)contact
{
    [self updateTableContents];
    [self.navigationController popToViewController:self animated:YES];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView.estimatedRowHeight = 45;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    _disappearingMessagesDurationLabel = [UILabel new];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _disappearingMessagesDurationLabel);

    self.disappearingMessagesDurations = [OWSDisappearingMessagesConfiguration validDurationsSeconds];

    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        self.disappearingMessagesConfiguration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:self.thread transaction:transaction];
    }];

#ifdef SHOW_COLOR_PICKER
    self.colorPicker = [[OWSColorPicker alloc] initWithThread:self.thread];
    self.colorPicker.delegate = self;
#endif

    [self updateTableContents];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (self.showVerificationOnAppear) {
        self.showVerificationOnAppear = NO;
        if (self.isGroupThread) {
            [self showGroupMembersView];
        } else {
            [self showVerificationView];
        }
    }
}

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    contents.title = NSLocalizedString(@"CONVERSATION_SETTINGS", @"title for conversation settings screen");

    BOOL isNoteToSelf = self.thread.isNoteToSelf;

    __weak OWSConversationSettingsViewController *weakSelf = self;

    // Main section.

    OWSTableSection *mainSection = [OWSTableSection new];

    mainSection.customHeaderView = [self mainSectionHeader];
    mainSection.customHeaderHeight = @(100.f);

    if ([self.thread isKindOfClass:[TSContactThread class]] && self.contactsManager.supportsContactEditing
        && !self.hasExistingContact) {
        [mainSection addItem:[OWSTableItem
                                 itemWithCustomCellBlock:^{
                                     return [weakSelf
                                          disclosureCellWithName:
                                              NSLocalizedString(@"CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
                                                  @"button in conversation settings view.")
                                                            icon:ThemeIconSettingsAddToContacts
                                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                     OWSConversationSettingsViewController,
                                                                     @"add_to_system_contacts")];
                                 }
                                 actionBlock:^{
                                     ActionSheetController *actionSheet =
                                         [[ActionSheetController alloc] initWithTitle:nil message:nil];

                                     NSString *createNewTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_NEW_CONTACT",
                                                                                  @"Label for 'new contact' button in conversation settings view.");
                                     [actionSheet
                                         addAction:[[ActionSheetAction alloc]
                                                       initWithTitle:createNewTitle
                                                               style:ActionSheetActionStyleDefault
                                                             handler:^(ActionSheetAction *_Nonnull action) {
                                                                 OWSConversationSettingsViewController *strongSelf
                                                                     = weakSelf;
                                                                 OWSCAssertDebug(strongSelf);
                                                                 [strongSelf presentContactViewController];
                                                             }]];

                                     NSString *addToExistingTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                                                      @"Label for 'new contact' button in conversation settings view.");
                                     [actionSheet
                                         addAction:[[ActionSheetAction alloc]
                                                       initWithTitle:addToExistingTitle
                                                               style:ActionSheetActionStyleDefault
                                                             handler:^(ActionSheetAction *_Nonnull action) {
                                                                 OWSConversationSettingsViewController *strongSelf
                                                                     = weakSelf;
                                                                 OWSCAssertDebug(strongSelf);
                                                                 TSContactThread *contactThread
                                                                     = (TSContactThread *)strongSelf.thread;
                                                                 [strongSelf
                                                                     presentAddToContactViewControllerWithAddress:
                                                                         contactThread.contactAddress];
                                                             }]];

                                     [self presentActionSheet:actionSheet];
                                 }]];
    }

    [mainSection addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 return [weakSelf
                                      disclosureCellWithName:MediaStrings.allMedia
                                                        icon:ThemeIconSettingsAllMedia
                                     accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                 OWSConversationSettingsViewController, @"all_media")];
                             }
                             actionBlock:^{
                                 [weakSelf showMediaGallery];
                             }]];

    if (SSKFeatureFlags.conversationSearch) {
        [mainSection addItem:[OWSTableItem
                                 itemWithCustomCellBlock:^{
                                     NSString *title = NSLocalizedString(@"CONVERSATION_SETTINGS_SEARCH",
                                         @"Table cell label in conversation settings which returns the user to the "
                                         @"conversation with 'search mode' activated");
                                     return [weakSelf
                                          disclosureCellWithName:title
                                                            icon:ThemeIconSettingsSearch
                                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                     OWSConversationSettingsViewController, @"search")];
                                 }
                                 actionBlock:^{
                                     [weakSelf tappedConversationSearch];
                                 }]];
    }

    if (!isNoteToSelf && !self.isGroupThread && self.thread.hasSafetyNumbers) {
        [mainSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            return [weakSelf
                                 disclosureCellWithName:NSLocalizedString(@"VERIFY_PRIVACY",
                                                            @"Label for button or row which allows users to verify the "
                                                            @"safety number of another user.")
                                                   icon:ThemeIconSettingsViewSafetyNumber
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                            OWSConversationSettingsViewController, @"safety_numbers")];
                        }
                        actionBlock:^{
                            [weakSelf showVerificationView];
                        }]];
    }

    // Indicate if the user is in the system contacts
    if (!isNoteToSelf && !self.isGroupThread && self.hasExistingContact) {
        [mainSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            OWSConversationSettingsViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);

                            return [strongSelf
                                 disclosureCellWithName:NSLocalizedString(
                                                            @"CONVERSATION_SETTINGS_VIEW_IS_SYSTEM_CONTACT",
                                                            @"Indicates that user is in the system contacts list.")
                                                   icon:ThemeIconSettingsUserInContacts
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                            OWSConversationSettingsViewController, @"is_in_contacts")];
                        }
                        actionBlock:^{
                            if (weakSelf.contactsManager.supportsContactEditing) {
                                [weakSelf presentContactViewController];
                            }
                        }]];
    }

    // Show profile status and allow sharing your profile for threads that are not in the whitelist.
    // This goes away when phoneNumberPrivacy is enabled, since profile sharing become mandatory.
    __block BOOL isThreadInProfileWhitelist;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        isThreadInProfileWhitelist =
            [self.profileManager isThreadInProfileWhitelist:self.thread transaction:transaction];
    }];
    if (SSKFeatureFlags.phoneNumberPrivacy || isNoteToSelf) {
        // Do nothing
    } else if (isThreadInProfileWhitelist) {
        [mainSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            OWSConversationSettingsViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);

                            return [strongSelf
                                      labelCellWithName:
                                          (strongSelf.isGroupThread
                                                  ? NSLocalizedString(
                                                      @"CONVERSATION_SETTINGS_VIEW_PROFILE_IS_SHARED_WITH_GROUP",
                                                      @"Indicates that user's profile has been shared with a group.")
                                                  : NSLocalizedString(
                                                      @"CONVERSATION_SETTINGS_VIEW_PROFILE_IS_SHARED_WITH_USER",
                                                      @"Indicates that user's profile has been shared with a user."))
                                                   icon:ThemeIconSettingsProfile
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                            OWSConversationSettingsViewController,
                                                            @"profile_is_shared")];
                        }
                                    actionBlock:nil]];
    } else {
        [mainSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            OWSConversationSettingsViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);

                            UITableViewCell *cell = [strongSelf
                                 disclosureCellWithName:
                                     (strongSelf.isGroupThread
                                             ? NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE_WITH_GROUP",
                                                 @"Action that shares user profile with a group.")
                                             : NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE_WITH_USER",
                                                 @"Action that shares user profile with a user."))
                                                   icon:ThemeIconSettingsProfile
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                            OWSConversationSettingsViewController, @"share_profile")];
                            cell.userInteractionEnabled = !strongSelf.hasLeftGroup;

                            return cell;
                        }
                        actionBlock:^{
                            [weakSelf showShareProfileAlert];
                        }]];
    }

    [mainSection addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 UITableViewCell *cell = [OWSTableItem newCell];
                                 OWSConversationSettingsViewController *strongSelf = weakSelf;
                                 OWSCAssertDebug(strongSelf);
                                 cell.preservesSuperviewLayoutMargins = YES;
                                 cell.contentView.preservesSuperviewLayoutMargins = YES;
                                 cell.selectionStyle = UITableViewCellSelectionStyleNone;

                                 ThemeIcon icon = strongSelf.disappearingMessagesConfiguration.isEnabled
                                     ? ThemeIconSettingsTimer
                                     : ThemeIconSettingsTimerDisabled;
                                 UIImageView *iconView = [strongSelf viewForIcon:icon];

                                 UILabel *rowLabel = [UILabel new];
                                 rowLabel.text = NSLocalizedString(
                                     @"DISAPPEARING_MESSAGES", @"table cell label in conversation settings");
                                 rowLabel.textColor = Theme.primaryTextColor;
                                 rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
                                 rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                                 UISwitch *switchView = [UISwitch new];
                                 switchView.on = strongSelf.disappearingMessagesConfiguration.isEnabled;
                                 [switchView addTarget:strongSelf
                                                action:@selector(disappearingMessagesSwitchValueDidChange:)
                                      forControlEvents:UIControlEventValueChanged];

                                 UIStackView *topRow =
                                     [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel, switchView ]];
                                 topRow.spacing = strongSelf.iconSpacing;
                                 topRow.alignment = UIStackViewAlignmentCenter;
                                 [cell.contentView addSubview:topRow];
                                 [topRow autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeBottom];

                                 UILabel *subtitleLabel = [UILabel new];
                                 subtitleLabel.text = NSLocalizedString(
                                     @"DISAPPEARING_MESSAGES_DESCRIPTION", @"subheading in conversation settings");
                                 subtitleLabel.textColor = Theme.primaryTextColor;
                                 subtitleLabel.font = [UIFont ows_dynamicTypeCaption1Font];
                                 subtitleLabel.numberOfLines = 0;
                                 subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
                                 [cell.contentView addSubview:subtitleLabel];
                                 [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:topRow withOffset:8];
                                 [subtitleLabel autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:rowLabel];
                                 [subtitleLabel autoPinTrailingToSuperviewMargin];
                                 [subtitleLabel autoPinBottomToSuperviewMargin];

                                 cell.userInteractionEnabled = !strongSelf.hasLeftGroup;

                                 switchView.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                     OWSConversationSettingsViewController, @"disappearing_messages_switch");
                                 cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                     OWSConversationSettingsViewController, @"disappearing_messages");

                                 return cell;
                             }
                                     customRowHeight:UITableViewAutomaticDimension
                                         actionBlock:nil]];

    if (self.disappearingMessagesConfiguration.isEnabled) {
        [mainSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            UITableViewCell *cell = [OWSTableItem newCell];
                            OWSConversationSettingsViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);
                            cell.preservesSuperviewLayoutMargins = YES;
                            cell.contentView.preservesSuperviewLayoutMargins = YES;
                            cell.selectionStyle = UITableViewCellSelectionStyleNone;

                            UIImageView *iconView = [strongSelf viewForIcon:ThemeIconSettingsTimer];

                            UILabel *rowLabel = strongSelf.disappearingMessagesDurationLabel;
                            [strongSelf updateDisappearingMessagesDurationLabel];
                            rowLabel.textColor = Theme.primaryTextColor;
                            rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
                            // don't truncate useful duration info which is in the tail
                            rowLabel.lineBreakMode = NSLineBreakByTruncatingHead;

                            UIStackView *topRow =
                                [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
                            topRow.spacing = strongSelf.iconSpacing;
                            topRow.alignment = UIStackViewAlignmentCenter;
                            [cell.contentView addSubview:topRow];
                            [topRow autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeBottom];

                            UISlider *slider = [UISlider new];
                            slider.maximumValue = (float)(strongSelf.disappearingMessagesDurations.count - 1);
                            slider.minimumValue = 0;
                            slider.continuous = YES; // NO fires change event only once you let go
                            slider.value = strongSelf.disappearingMessagesConfiguration.durationIndex;
                            [slider addTarget:strongSelf
                                          action:@selector(durationSliderDidChange:)
                                forControlEvents:UIControlEventValueChanged];
                            [cell.contentView addSubview:slider];
                            [slider autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:topRow withOffset:6];
                            [slider autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:rowLabel];
                            [slider autoPinTrailingToSuperviewMargin];
                            [slider autoPinBottomToSuperviewMargin];

                            cell.userInteractionEnabled = !strongSelf.hasLeftGroup;

                            slider.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                OWSConversationSettingsViewController, @"disappearing_messages_slider");
                            cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                OWSConversationSettingsViewController, @"disappearing_messages_duration");

                            return cell;
                        }
                                customRowHeight:UITableViewAutomaticDimension
                                    actionBlock:nil]];
    }
#ifdef SHOW_COLOR_PICKER
    [mainSection
        addItem:[OWSTableItem
                    itemWithCustomCellBlock:^{
                        OWSConversationSettingsViewController *strongSelf = weakSelf;
                        OWSCAssertDebug(strongSelf);

                        ConversationColorName colorName = strongSelf.thread.conversationColorName;
                        UIColor *currentColor =
                            [OWSConversationColor conversationColorOrDefaultForColorName:colorName].themeColor;
                        NSString *title = NSLocalizedString(@"CONVERSATION_SETTINGS_CONVERSATION_COLOR",
                            @"Label for table cell which leads to picking a new conversation color");
                        return [strongSelf
                                       cellWithName:title
                                               icon:ThemeIconColorPalette
                                disclosureIconColor:currentColor
                            accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                        OWSConversationSettingsViewController, @"conversation_color")];
                    }
                    actionBlock:^{
                        [weakSelf showColorPicker];
                    }]];
#endif

    [contents addSection:mainSection];

    // Group settings section.

    if (self.isGroupThread) {
        NSArray *groupItems = @[
            [OWSTableItem
                itemWithCustomCellBlock:^{
                    UITableViewCell *cell =
                        [weakSelf disclosureCellWithName:NSLocalizedString(@"EDIT_GROUP_ACTION",
                                                             @"table cell label in conversation settings")
                                                    icon:ThemeIconSettingsEditGroup
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                             OWSConversationSettingsViewController, @"edit_group")];
                    cell.userInteractionEnabled = !weakSelf.hasLeftGroup;
                    return cell;
                }
                actionBlock:^{
                    [weakSelf showUpdateGroupView:UpdateGroupMode_Default];
                }],
            [OWSTableItem
                itemWithCustomCellBlock:^{
                    UITableViewCell *cell =
                        [weakSelf disclosureCellWithName:NSLocalizedString(@"LIST_GROUP_MEMBERS_ACTION",
                                                             @"table cell label in conversation settings")
                                                    icon:ThemeIconSettingsShowGroup
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                             OWSConversationSettingsViewController, @"group_members")];
                    cell.userInteractionEnabled = !weakSelf.hasLeftGroup;
                    return cell;
                }
                actionBlock:^{
                    [weakSelf showGroupMembersView];
                }],
            [OWSTableItem
                itemWithCustomCellBlock:^{
                    UITableViewCell *cell =
                        [weakSelf disclosureCellWithName:NSLocalizedString(@"LEAVE_GROUP_ACTION",
                                                             @"table cell label in conversation settings")
                                                    icon:ThemeIconSettingsLeaveGroup
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                             OWSConversationSettingsViewController, @"leave_group")];
                    cell.userInteractionEnabled = !weakSelf.hasLeftGroup;

                    return cell;
                }
                actionBlock:^{
                    [weakSelf didTapLeaveGroup];
                }],
        ];

        [contents addSection:[OWSTableSection sectionWithTitle:NSLocalizedString(@"GROUP_MANAGEMENT_SECTION",
                                                                   @"Conversation settings table section title")
                                                         items:groupItems]];
    }

    // Mute thread section.

    if (!isNoteToSelf) {
        OWSTableSection *notificationsSection = [OWSTableSection new];
        // We need a section header to separate the notifications UI from the group settings UI.
        notificationsSection.headerTitle = NSLocalizedString(
            @"SETTINGS_SECTION_NOTIFICATIONS", @"Label for the notifications section of conversation settings view.");

        [notificationsSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            UITableViewCell *cell =
                                [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
                            [OWSTableItem configureCell:cell];
                            OWSConversationSettingsViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);
                            cell.preservesSuperviewLayoutMargins = YES;
                            cell.contentView.preservesSuperviewLayoutMargins = YES;
                            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

                            UIImageView *iconView = [strongSelf viewForIcon:ThemeIconSettingsMessageSound];

                            UILabel *rowLabel = [UILabel new];
                            rowLabel.text = NSLocalizedString(@"SETTINGS_ITEM_NOTIFICATION_SOUND",
                                @"Label for settings view that allows user to change the notification sound.");
                            rowLabel.textColor = Theme.primaryTextColor;
                            rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
                            rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                            UIStackView *contentRow =
                                [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
                            contentRow.spacing = strongSelf.iconSpacing;
                            contentRow.alignment = UIStackViewAlignmentCenter;
                            [cell.contentView addSubview:contentRow];
                            [contentRow autoPinEdgesToSuperviewMargins];

                            OWSSound sound = [OWSSounds notificationSoundForThread:strongSelf.thread];
                            cell.detailTextLabel.text = [OWSSounds displayNameForSound:sound];

                            cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                OWSConversationSettingsViewController, @"notifications");

                            return cell;
                        }
                        customRowHeight:UITableViewAutomaticDimension
                        actionBlock:^{
                            OWSSoundSettingsViewController *vc = [OWSSoundSettingsViewController new];
                            vc.thread = weakSelf.thread;
                            [weakSelf.navigationController pushViewController:vc animated:YES];
                        }]];

        [notificationsSection
            addItem:
                [OWSTableItem
                    itemWithCustomCellBlock:^{
                        UITableViewCell *cell =
                            [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
                        [OWSTableItem configureCell:cell];
                        OWSConversationSettingsViewController *strongSelf = weakSelf;
                        OWSCAssertDebug(strongSelf);
                        cell.preservesSuperviewLayoutMargins = YES;
                        cell.contentView.preservesSuperviewLayoutMargins = YES;
                        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

                        UIImageView *iconView = [strongSelf viewForIcon:ThemeIconSettingsMuted];

                        UILabel *rowLabel = [UILabel new];
                        rowLabel.text = NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_LABEL",
                            @"label for 'mute thread' cell in conversation settings");
                        rowLabel.textColor = Theme.primaryTextColor;
                        rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
                        rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                        NSString *muteStatus = NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_NOT_MUTED",
                            @"Indicates that the current thread is not muted.");
                        NSDate *mutedUntilDate = strongSelf.thread.mutedUntilDate;
                        NSDate *now = [NSDate date];
                        if (mutedUntilDate != nil && [mutedUntilDate timeIntervalSinceDate:now] > 0) {
                            NSCalendar *calendar = [NSCalendar currentCalendar];
                            NSCalendarUnit calendarUnits = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
                            NSDateComponents *muteUntilComponents =
                                [calendar components:calendarUnits fromDate:mutedUntilDate];
                            NSDateComponents *nowComponents = [calendar components:calendarUnits fromDate:now];
                            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                            if (nowComponents.year != muteUntilComponents.year
                                || nowComponents.month != muteUntilComponents.month
                                || nowComponents.day != muteUntilComponents.day) {

                                [dateFormatter setDateStyle:NSDateFormatterShortStyle];
                                [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
                            } else {
                                [dateFormatter setDateStyle:NSDateFormatterNoStyle];
                                [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
                            }

                            muteStatus = [NSString
                                stringWithFormat:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTED_UNTIL_FORMAT",
                                                     @"Indicates that this thread is muted until a given date or time. "
                                                     @"Embeds {{The date or time which the thread is muted until}}."),
                                [dateFormatter stringFromDate:mutedUntilDate]];
                        }

                        UIStackView *contentRow =
                            [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
                        contentRow.spacing = strongSelf.iconSpacing;
                        contentRow.alignment = UIStackViewAlignmentCenter;
                        [cell.contentView addSubview:contentRow];
                        [contentRow autoPinEdgesToSuperviewMargins];

                        cell.detailTextLabel.text = muteStatus;

                        cell.accessibilityIdentifier
                            = ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"mute");

                        return cell;
                    }
                    customRowHeight:UITableViewAutomaticDimension
                    actionBlock:^{
                        [weakSelf showMuteUnmuteActionSheet];
                    }]];
        notificationsSection.footerTitle = NSLocalizedString(
            @"MUTE_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of muting a thread.");
        [contents addSection:notificationsSection];
    }
    // Block Conversation section.

    if (!isNoteToSelf) {
        OWSTableSection *section = [OWSTableSection new];
        if (self.thread.isGroupThread) {
            section.footerTitle = NSLocalizedString(
                @"BLOCK_GROUP_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of blocking a group.");
        } else {
            section.footerTitle = NSLocalizedString(
                @"BLOCK_USER_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of blocking another user.");
        }

        [section addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 OWSConversationSettingsViewController *strongSelf = weakSelf;
                                 if (!strongSelf) {
                                     return [UITableViewCell new];
                                 }

                                 NSString *cellTitle;
                                 if (strongSelf.thread.isGroupThread) {
                                     cellTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_BLOCK_THIS_GROUP",
                                         @"table cell label in conversation settings");
                                 } else {
                                     cellTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_BLOCK_THIS_USER",
                                         @"table cell label in conversation settings");
                                 }
                                 UITableViewCell *cell = [strongSelf
                                      disclosureCellWithName:cellTitle
                                                        icon:ThemeIconSettingsBlock
                                     accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                 OWSConversationSettingsViewController, @"block")];

                                 cell.selectionStyle = UITableViewCellSelectionStyleNone;

                                 UISwitch *switchView = [UISwitch new];
                                 switchView.on = [strongSelf.blockingManager isThreadBlocked:strongSelf.thread];
                                 [switchView addTarget:strongSelf
                                                action:@selector(blockConversationSwitchDidChange:)
                                      forControlEvents:UIControlEventValueChanged];
                                 cell.accessoryView = switchView;
                                 switchView.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                     OWSConversationSettingsViewController, @"block_conversation_switch");

                                 return cell;
                             }
                                         actionBlock:nil]];
        [contents addSection:section];
    }

    self.contents = contents;
}

- (CGFloat)iconSpacing
{
    return 12.f;
}

- (UITableViewCell *)cellWithName:(NSString *)name
                             icon:(ThemeIcon)icon
              disclosureIconColor:(UIColor *)disclosureIconColor
{
    UITableViewCell *cell = [self cellWithName:name icon:icon];
    OWSColorPickerAccessoryView *accessoryView =
        [[OWSColorPickerAccessoryView alloc] initWithColor:disclosureIconColor];
    [accessoryView sizeToFit];
    cell.accessoryView = accessoryView;

    return cell;
}

- (UITableViewCell *)cellWithName:(NSString *)name icon:(ThemeIcon)icon
{
    UIImageView *iconView = [self viewForIcon:icon];
    return [self cellWithName:name iconView:iconView];
}

- (UITableViewCell *)cellWithName:(NSString *)name iconView:(UIView *)iconView
{
    OWSAssertDebug(name.length > 0);

    UITableViewCell *cell = [OWSTableItem newCell];
    cell.preservesSuperviewLayoutMargins = YES;
    cell.contentView.preservesSuperviewLayoutMargins = YES;

    UILabel *rowLabel = [UILabel new];
    rowLabel.text = name;
    rowLabel.textColor = Theme.primaryTextColor;
    rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
    rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIStackView *contentRow = [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
    contentRow.spacing = self.iconSpacing;

    [cell.contentView addSubview:contentRow];
    [contentRow autoPinEdgesToSuperviewMargins];

    return cell;
}

- (UITableViewCell *)disclosureCellWithName:(NSString *)name
                                       icon:(ThemeIcon)icon
                    accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
    UITableViewCell *cell = [self cellWithName:name icon:icon];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = accessibilityIdentifier;
    return cell;
}

- (UITableViewCell *)labelCellWithName:(NSString *)name
                                  icon:(ThemeIcon)icon
               accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
    UITableViewCell *cell = [self cellWithName:name icon:icon];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityIdentifier = accessibilityIdentifier;
    return cell;
}

- (UIView *)mainSectionHeader
{
    UIView *mainSectionHeader = [UIView new];
    UIView *threadInfoView = [UIView containerView];
    [mainSectionHeader addSubview:threadInfoView];
    [threadInfoView autoPinWidthToSuperviewWithMargin:16.f];
    [threadInfoView autoPinHeightToSuperviewWithMargin:16.f];

    UIImage *avatarImage = [OWSAvatarBuilder buildImageForThread:self.thread diameter:kLargeAvatarSize];
    OWSAssertDebug(avatarImage);

    AvatarImageView *avatarView = [[AvatarImageView alloc] initWithImage:avatarImage];
    _avatarView = avatarView;
    [threadInfoView addSubview:avatarView];
    [avatarView autoVCenterInSuperview];
    [avatarView autoPinLeadingToSuperviewMargin];
    [avatarView autoSetDimension:ALDimensionWidth toSize:kLargeAvatarSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:kLargeAvatarSize];

    if (self.isGroupThread && !self.hasSavedGroupIcon && self.hasGroupEditPermission) {
        UIImageView *cameraImageView = [UIImageView new];
        [cameraImageView setTemplateImageName:@"camera-outline-24" tintColor:Theme.secondaryTextAndIconColor];
        [threadInfoView addSubview:cameraImageView];

        [cameraImageView autoSetDimensionsToSize:CGSizeMake(32, 32)];
        cameraImageView.contentMode = UIViewContentModeCenter;
        cameraImageView.backgroundColor = Theme.backgroundColor;
        cameraImageView.layer.cornerRadius = 16;
        cameraImageView.layer.shadowColor =
            [(Theme.isDarkThemeEnabled ? Theme.darkThemeWashColor : Theme.primaryTextColor) CGColor];
        cameraImageView.layer.shadowOffset = CGSizeMake(1, 1);
        cameraImageView.layer.shadowOpacity = 0.5;
        cameraImageView.layer.shadowRadius = 4;

        [cameraImageView autoPinTrailingToEdgeOfView:avatarView];
        [cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:avatarView];
    }

    UIView *threadNameView = [UIView containerView];
    [threadInfoView addSubview:threadNameView];
    [threadNameView autoVCenterInSuperview];
    [threadNameView autoPinTrailingToSuperviewMargin];
    [threadNameView autoPinLeadingToTrailingEdgeOfView:avatarView offset:16.f];

    UILabel *threadTitleLabel = [UILabel new];
    threadTitleLabel.text = self.threadName;
    threadTitleLabel.textColor = Theme.primaryTextColor;
    threadTitleLabel.font = [UIFont ows_dynamicTypeTitle2Font];
    threadTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [threadNameView addSubview:threadTitleLabel];
    [threadTitleLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [threadTitleLabel autoPinWidthToSuperview];

    __block UIView *lastTitleView = threadTitleLabel;

    const CGFloat kSubtitlePointSize = 12.f;
    void (^addSubtitle)(NSAttributedString *) = ^(NSAttributedString *subtitle) {
        UILabel *subtitleLabel = [UILabel new];
        subtitleLabel.textColor = Theme.secondaryTextAndIconColor;
        subtitleLabel.font = [UIFont ows_regularFontWithSize:kSubtitlePointSize];
        subtitleLabel.attributedText = subtitle;
        subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [threadNameView addSubview:subtitleLabel];
        [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastTitleView];
        [subtitleLabel autoPinLeadingToSuperviewMargin];
        lastTitleView = subtitleLabel;
    };

    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)self.thread;
        NSString *threadName = [self.contactsManager displayNameForThreadWithSneakyTransaction:contactThread];

        SignalServiceAddress *recipientAddress = contactThread.contactAddress;
        NSString *_Nullable phoneNumber = recipientAddress.phoneNumber;
        if (phoneNumber.length > 0) {
            NSString *formattedPhoneNumber =
                [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:phoneNumber];

            if (![threadName isEqualToString:formattedPhoneNumber]) {
                NSAttributedString *subtitle = [[NSAttributedString alloc] initWithString:formattedPhoneNumber];
                addSubtitle(subtitle);
            }
        }

        __block NSString *_Nullable username;
        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            username = [self.profileManager usernameForAddress:recipientAddress transaction:transaction];
        }];
        if (username.length > 0) {
            NSString *formattedUsername = [CommonFormats formatUsername:username];
            if (![threadName isEqualToString:formattedUsername]) {
                addSubtitle([[NSAttributedString alloc] initWithString:formattedUsername]);
            }
        }

        if (!SSKFeatureFlags.profileDisplayChanges
            && ![self.contactsManager hasNameInSystemContactsForAddress:recipientAddress]) {
            NSString *_Nullable profileName = [self.contactsManager formattedProfileNameForAddress:recipientAddress];
            if (profileName) {
                addSubtitle([[NSAttributedString alloc] initWithString:profileName]);
            }
        }

#if DEBUG
        NSString *uuidText = [NSString stringWithFormat:@"UUID: %@", contactThread.contactAddress.uuid ?: @"Unknown"];
        addSubtitle([[NSAttributedString alloc] initWithString:uuidText]);
#endif

        BOOL isVerified = [[OWSIdentityManager sharedManager] verificationStateForAddress:recipientAddress]
            == OWSVerificationStateVerified;
        if (isVerified) {
            NSMutableAttributedString *subtitle = [NSMutableAttributedString new];
            // "checkmark"
            [subtitle appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:LocalizationNotNeeded(@"\uf00c ")
                                                     attributes:@{
                                                         NSFontAttributeName :
                                                             [UIFont ows_fontAwesomeFont:kSubtitlePointSize],
                                                     }]];
            [subtitle appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:NSLocalizedString(@"PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                                    @"Badge indicating that the user is verified.")]];
            addSubtitle(subtitle);
        }
    }

    // TODO Message Request: In order to debug the profile is getting shared in the right moments,
    // display the thread whitelist state in settings. Eventually we can probably delete this.
#if DEBUG
    __block BOOL isThreadInProfileWhitelist;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        isThreadInProfileWhitelist =
            [self.profileManager isThreadInProfileWhitelist:self.thread transaction:transaction];
    }];
    NSString *hasSharedProfile =
        [NSString stringWithFormat:@"Whitelisted: %@", isThreadInProfileWhitelist ? @"Yes" : @"No"];
    addSubtitle([[NSAttributedString alloc] initWithString:hasSharedProfile]);
#endif

    [lastTitleView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [mainSectionHeader
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(conversationNameTouched:)]];
    mainSectionHeader.userInteractionEnabled = YES;

    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, mainSectionHeader);

    return mainSectionHeader;
}

- (void)conversationNameTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        if (self.isGroupThread) {
            CGPoint location = [sender locationInView:self.avatarView];
            if (CGRectContainsPoint(self.avatarView.bounds, location)) {
                [self showUpdateGroupView:UpdateGroupMode_EditGroupAvatar];
            } else {
                [self showUpdateGroupView:UpdateGroupMode_EditGroupName];
            }
        } else {
            if (self.contactsManager.supportsContactEditing) {
                [self presentContactViewController];
            }
        }
    }
}

- (UIImageView *)viewForIcon:(ThemeIcon)icon
{
    UIImage *iconImage = [Theme iconImage:icon];
    OWSAssertDebug(iconImage);
    UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
    iconView.tintColor = Theme.primaryIconColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.minificationFilter = kCAFilterTrilinear;
    iconView.layer.magnificationFilter = kCAFilterTrilinear;

    [iconView autoSetDimensionsToSize:CGSizeMake(kIconViewLength, kIconViewLength)];

    return iconView;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    NSIndexPath *_Nullable selectedPath = [self.tableView indexPathForSelectedRow];
    if (selectedPath) {
        // HACK to unselect rows when swiping back
        // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
        [self.tableView deselectRowAtIndexPath:selectedPath animated:animated];
    }

    [self updateTableContents];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    __block BOOL shouldSave;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        shouldSave = [self.disappearingMessagesConfiguration hasChangedWithTransaction:transaction];
    }];
    if (!shouldSave) {
        // Every time we change the configuration we notify the contact and
        // create an update interaction.
        //
        // We don't want to do either if these are unmodified defaults
        // of if nothing has changed.
        return;
    }

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.disappearingMessagesConfiguration anyUpsertWithTransaction:transaction];

        // MJK TODO - should be safe to remove this senderTimestamp
        OWSDisappearingConfigurationUpdateInfoMessage *infoMessage =
            [[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                     initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                thread:self.thread
                         configuration:self.disappearingMessagesConfiguration
                   createdByRemoteName:nil
                createdInExistingGroup:NO];
        [infoMessage anyInsertWithTransaction:transaction];

        OWSDisappearingMessagesConfigurationMessage *message = [[OWSDisappearingMessagesConfigurationMessage alloc]
            initWithConfiguration:self.disappearingMessagesConfiguration
                           thread:self.thread];

        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    }];
}

#pragma mark - Actions

- (void)showShareProfileAlert
{
    [self.profileManager presentAddThreadToProfileWhitelist:self.thread
                                         fromViewController:self
                                                    success:^{
                                                        [self updateTableContents];
                                                    }];
}

- (void)showVerificationView
{
    OWSAssertDebug([self.thread isKindOfClass:[TSContactThread class]]);
    TSContactThread *contactThread = (TSContactThread *)self.thread;
    SignalServiceAddress *contactAddress = contactThread.contactAddress;
    OWSAssertDebug(contactAddress.isValid);

    [FingerprintViewController presentFromViewController:self address:contactAddress];
}

- (void)showGroupMembersView
{
    ShowGroupMembersViewController *showGroupMembersViewController = [ShowGroupMembersViewController new];
    [showGroupMembersViewController configWithThread:(TSGroupThread *)self.thread];
    [self.navigationController pushViewController:showGroupMembersViewController animated:YES];
}

- (void)showUpdateGroupView:(UpdateGroupMode)mode
{
    if (!self.hasGroupEditPermission) {
        [OWSActionSheets
            showActionSheetWithTitle:@"No Permission"
                             message:@"You do not have permission to edit this group. Either owner or admin can edit the group."];
        return;
    }
    
    OWSAssertDebug(self.conversationSettingsViewDelegate);

    UpdateGroupViewController *updateGroupViewController = [UpdateGroupViewController new];
    updateGroupViewController.conversationSettingsViewDelegate = self.conversationSettingsViewDelegate;
    updateGroupViewController.thread = (TSGroupThread *)self.thread;
    updateGroupViewController.mode = mode;
    [self.navigationController pushViewController:updateGroupViewController animated:YES];
}

- (void)presentContactViewController
{
    if (!self.contactsManager.supportsContactEditing) {
        OWSFailDebug(@"Contact editing not supported");
        return;
    }
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", [self.thread class]);
        return;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;

    CNContactViewController *_Nullable contactViewController =
        [self.contactsViewHelper contactViewControllerForAddress:contactThread.contactAddress editImmediately:YES];

    if (!contactViewController) {
        OWSFailDebug(@"Unexpectedly missing contact VC");
        return;
    }

    contactViewController.delegate = self;
    [self.navigationController pushViewController:contactViewController animated:YES];
}

- (void)presentAddToContactViewControllerWithAddress:(SignalServiceAddress *)address
{
    if (!self.contactsManager.supportsContactEditing) {
        // Should not expose UI that lets the user get here.
        OWSFailDebug(@"Contact editing not supported.");
        return;
    }

    if (!self.contactsManager.isSystemContactsAuthorized) {
        [self.contactsViewHelper presentMissingContactAccessAlertControllerFromViewController:self];
        return;
    }

    OWSAddToContactViewController *viewController = [OWSAddToContactViewController new];
    [viewController configureWithAddress:address];
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)didTapLeaveGroup
{
    ActionSheetController *alert = [[ActionSheetController alloc]
        initWithTitle:NSLocalizedString(@"CONFIRM_LEAVE_GROUP_TITLE", @"Alert title")
              message:NSLocalizedString(@"CONFIRM_LEAVE_GROUP_DESCRIPTION", @"Alert body")];

    ActionSheetAction *leaveAction = [[ActionSheetAction alloc]
                  initWithTitle:NSLocalizedString(@"LEAVE_BUTTON_TITLE", @"Confirmation button within contextual alert")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"leave_group_confirm")
                          style:ActionSheetActionStyleDestructive
                        handler:^(ActionSheetAction *_Nonnull action) {
                            [self leaveGroup];
                        }];
    [alert addAction:leaveAction];
    [alert addAction:[OWSActionSheets cancelAction]];

    [self presentActionSheet:alert];
}

- (BOOL)hasLeftGroup
{
    if (self.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        return !groupThread.isLocalUserInGroup;
    }

    return NO;
}

- (void)leaveGroup
{
    TSGroupThread *gThread = (TSGroupThread *)self.thread;
    TSOutgoingMessage *message =
        [TSOutgoingMessage outgoingMessageInThread:gThread groupMetaMessage:TSGroupMetaMessageQuit expiresInSeconds:0];

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];

        [gThread leaveGroupWithTransaction:transaction];
    }];

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)disappearingMessagesSwitchValueDidChange:(UISwitch *)sender
{
    UISwitch *disappearingMessagesSwitch = (UISwitch *)sender;

    [self toggleDisappearingMessages:disappearingMessagesSwitch.isOn];

    [self updateTableContents];
}

- (void)blockConversationSwitchDidChange:(id)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        OWSFailDebug(@"Unexpected sender for block user switch: %@", sender);
    }
    UISwitch *blockConversationSwitch = (UISwitch *)sender;

    BOOL isCurrentlyBlocked = [self.blockingManager isThreadBlocked:self.thread];

    __weak OWSConversationSettingsViewController *weakSelf = self;
    if (blockConversationSwitch.isOn) {
        OWSAssertDebug(!isCurrentlyBlocked);
        if (isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showBlockThreadActionSheet:self.thread
                                  fromViewController:self
                                     blockingManager:self.blockingManager
                                     contactsManager:self.contactsManager
                                       messageSender:self.messageSender
                                     completionBlock:^(BOOL isBlocked) {
                                         // Update switch state if user cancels action.
                                         blockConversationSwitch.on = isBlocked;

                                         [weakSelf updateTableContents];
                                     }];

    } else {
        OWSAssertDebug(isCurrentlyBlocked);
        if (!isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showUnblockThreadActionSheet:self.thread
                                    fromViewController:self
                                       blockingManager:self.blockingManager
                                       contactsManager:self.contactsManager
                                       completionBlock:^(BOOL isBlocked) {
                                           // Update switch state if user cancels action.
                                           blockConversationSwitch.on = isBlocked;

                                           [weakSelf updateTableContents];
                                       }];
    }
}

- (void)toggleDisappearingMessages:(BOOL)flag
{
    self.disappearingMessagesConfiguration = [self.disappearingMessagesConfiguration copyWithIsEnabled:flag];

    [self updateTableContents];
}

- (void)durationSliderDidChange:(UISlider *)slider
{
    // snap the slider to a valid value
    NSUInteger index = (NSUInteger)(slider.value + 0.5);
    [slider setValue:index animated:YES];
    NSNumber *numberOfSeconds = self.disappearingMessagesDurations[index];
    uint32_t durationSeconds = [numberOfSeconds unsignedIntValue];
    self.disappearingMessagesConfiguration =
        [self.disappearingMessagesConfiguration copyAsEnabledWithDurationSeconds:durationSeconds];

    [self updateDisappearingMessagesDurationLabel];
}

- (void)updateDisappearingMessagesDurationLabel
{
    if (self.disappearingMessagesConfiguration.isEnabled) {
        NSString *keepForFormat = NSLocalizedString(@"KEEP_MESSAGES_DURATION",
            @"Slider label embeds {{TIME_AMOUNT}}, e.g. '2 hours'. See *_TIME_AMOUNT strings for examples.");
        self.disappearingMessagesDurationLabel.text =
            [NSString stringWithFormat:keepForFormat, self.disappearingMessagesConfiguration.durationString];
    } else {
        self.disappearingMessagesDurationLabel.text
            = NSLocalizedString(@"KEEP_MESSAGES_FOREVER", @"Slider label when disappearing messages is off");
    }

    [self.disappearingMessagesDurationLabel setNeedsLayout];
    [self.disappearingMessagesDurationLabel.superview setNeedsLayout];
}

- (void)showMuteUnmuteActionSheet
{
    // The "unmute" action sheet has no title or message; the
    // action label speaks for itself.
    NSString *title = nil;
    NSString *message = nil;
    if (!self.thread.isMuted) {
        title = NSLocalizedString(
            @"CONVERSATION_SETTINGS_MUTE_ACTION_SHEET_TITLE", @"Title of the 'mute this thread' action sheet.");
        message = NSLocalizedString(
            @"MUTE_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of muting a thread.");
    }

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:title message:message];

    __weak OWSConversationSettingsViewController *weakSelf = self;
    if (self.thread.isMuted) {
        ActionSheetAction *action =
            [[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_UNMUTE_ACTION",
                                                         @"Label for button to unmute a thread.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"unmute")
                                               style:ActionSheetActionStyleDestructive
                                             handler:^(ActionSheetAction *_Nonnull ignore) {
                                                 [weakSelf setThreadMutedUntilDate:nil];
                                             }];
        [actionSheet addAction:action];
    } else {
#ifdef DEBUG
        [actionSheet
            addAction:[[ActionSheetAction alloc]
                                    initWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_MINUTE_ACTION",
                                                      @"Label for button to mute a thread for a minute.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_minute")
                                            style:ActionSheetActionStyleDestructive
                                          handler:^(ActionSheetAction *_Nonnull ignore) {
                                              NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                              NSCalendar *calendar = [NSCalendar currentCalendar];
                                              [calendar setTimeZone:timeZone];
                                              NSDateComponents *dateComponents = [NSDateComponents new];
                                              [dateComponents setMinute:1];
                                              NSDate *mutedUntilDate = [calendar dateByAddingComponents:dateComponents
                                                                                                 toDate:[NSDate date]
                                                                                                options:0];
                                              [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                          }]];
#endif
        [actionSheet
            addAction:[[ActionSheetAction alloc]
                                    initWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_HOUR_ACTION",
                                                      @"Label for button to mute a thread for a hour.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_hour")
                                            style:ActionSheetActionStyleDestructive
                                          handler:^(ActionSheetAction *_Nonnull ignore) {
                                              NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                              NSCalendar *calendar = [NSCalendar currentCalendar];
                                              [calendar setTimeZone:timeZone];
                                              NSDateComponents *dateComponents = [NSDateComponents new];
                                              [dateComponents setHour:1];
                                              NSDate *mutedUntilDate = [calendar dateByAddingComponents:dateComponents
                                                                                                 toDate:[NSDate date]
                                                                                                options:0];
                                              [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                          }]];
        [actionSheet
            addAction:[[ActionSheetAction alloc]
                                    initWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_DAY_ACTION",
                                                      @"Label for button to mute a thread for a day.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_day")
                                            style:ActionSheetActionStyleDestructive
                                          handler:^(ActionSheetAction *_Nonnull ignore) {
                                              NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                              NSCalendar *calendar = [NSCalendar currentCalendar];
                                              [calendar setTimeZone:timeZone];
                                              NSDateComponents *dateComponents = [NSDateComponents new];
                                              [dateComponents setDay:1];
                                              NSDate *mutedUntilDate = [calendar dateByAddingComponents:dateComponents
                                                                                                 toDate:[NSDate date]
                                                                                                options:0];
                                              [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                          }]];
        [actionSheet
            addAction:[[ActionSheetAction alloc]
                                    initWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_WEEK_ACTION",
                                                      @"Label for button to mute a thread for a week.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_week")
                                            style:ActionSheetActionStyleDestructive
                                          handler:^(ActionSheetAction *_Nonnull ignore) {
                                              NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                              NSCalendar *calendar = [NSCalendar currentCalendar];
                                              [calendar setTimeZone:timeZone];
                                              NSDateComponents *dateComponents = [NSDateComponents new];
                                              [dateComponents setDay:7];
                                              NSDate *mutedUntilDate = [calendar dateByAddingComponents:dateComponents
                                                                                                 toDate:[NSDate date]
                                                                                                options:0];
                                              [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                          }]];
        [actionSheet
            addAction:[[ActionSheetAction alloc]
                                    initWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_YEAR_ACTION",
                                                      @"Label for button to mute a thread for a year.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_year")
                                            style:ActionSheetActionStyleDestructive
                                          handler:^(ActionSheetAction *_Nonnull ignore) {
                                              NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                              NSCalendar *calendar = [NSCalendar currentCalendar];
                                              [calendar setTimeZone:timeZone];
                                              NSDateComponents *dateComponents = [NSDateComponents new];
                                              [dateComponents setYear:1];
                                              NSDate *mutedUntilDate = [calendar dateByAddingComponents:dateComponents
                                                                                                 toDate:[NSDate date]
                                                                                                options:0];
                                              [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                          }]];
    }

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [self presentActionSheet:actionSheet];
}

- (void)setThreadMutedUntilDate:(nullable NSDate *)value
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.thread updateWithMutedUntilDate:value transaction:transaction];
    }];

    [self updateTableContents];
}

- (void)showMediaGallery
{
    OWSLogDebug(@"");

    MediaTileViewController *tileVC = [[MediaTileViewController alloc] initWithThread:self.thread];
    [self.navigationController pushViewController:tileVC animated:YES];
}

- (void)tappedConversationSearch
{
    [self.conversationSettingsViewDelegate conversationSettingsDidRequestConversationSearch:self];
}

#pragma mark - Notifications

- (void)identityStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    SignalServiceAddress *address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    OWSAssertDebug(address.isValid);

    TSContactThread *_Nullable contactThread;
    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        contactThread = (TSContactThread *)self.thread;
    }

    if (address.isValid && contactThread && [contactThread.contactAddress isEqualToAddress:address]) {
        [self updateTableContents];
    }
}

#pragma mark - ColorPickerDelegate

#ifdef SHOW_COLOR_PICKER

- (void)showColorPicker
{
    OWSSheetViewController *sheetViewController = self.colorPicker.sheetViewController;
    sheetViewController.delegate = self;

    [self presentViewController:sheetViewController
                       animated:YES
                     completion:^() {
                         OWSLogInfo(@"presented sheet view");
                     }];
}

- (void)colorPicker:(OWSColorPicker *)colorPicker
    didPickConversationColor:(OWSConversationColor *_Nonnull)conversationColor
{
    OWSLogDebug(@"picked color: %@", conversationColor.name);
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.thread updateConversationColorName:conversationColor.name transaction:transaction];
    }];

    [self.contactsManager.avatarCache removeAllImages];
    [self.contactsManager clearColorNameCache];
    [self updateTableContents];
    [self.conversationSettingsViewDelegate conversationColorWasUpdated];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ConversationConfigurationSyncOperation *operation =
            [[ConversationConfigurationSyncOperation alloc] initWithThread:self.thread];
        OWSAssertDebug(operation.isReady);
        [operation start];
    });
}

#endif

#pragma mark - OWSSheetViewController

- (void)sheetViewControllerRequestedDismiss:(OWSSheetViewController *)sheetViewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
