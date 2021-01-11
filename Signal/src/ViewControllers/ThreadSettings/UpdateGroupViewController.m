//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "UpdateGroupViewController.h"
#import "AvatarViewHelper.h"
#import "OWSNavigationController.h"
#import "PALAPA-Swift.h"
#import "ViewControllerUtils.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/BlockListUIUtils.h>
#import <SignalMessaging/ContactTableViewCell.h>
#import <SignalMessaging/ContactsViewHelper.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSTableViewController.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface UpdateGroupViewController () <UIImagePickerControllerDelegate,
    UITextFieldDelegate,
    AvatarViewHelperDelegate,
    RecipientPickerDelegate,
    UINavigationControllerDelegate,
    OWSNavigationView>

@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) AvatarViewHelper *avatarViewHelper;

@property (nonatomic, readonly) RecipientPickerViewController *recipientPicker;
@property (nonatomic, readonly) AvatarImageView *avatarView;
@property (nonatomic, readonly) UIImageView *cameraImageView;
@property (nonatomic, readonly) UITextField *groupNameTextField;

@property (nonatomic, nullable) NSData *groupAvatarData;
@property (nonatomic, nullable) NSSet<PickedRecipient *> *previousMemberRecipients;
@property (nonatomic) NSMutableSet<PickedRecipient *> *memberRecipients;
@property (nonatomic) NSMutableSet<PickedRecipient *> *adminRecipients;

@property (nonatomic) BOOL hasUnsavedChanges;

@end

#pragma mark -

@implementation UpdateGroupViewController

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

- (void)commonInit
{
    _messageSender = SSKEnvironment.shared.messageSender;
    _avatarViewHelper = [AvatarViewHelper new];
    _avatarViewHelper.delegate = self;

    self.memberRecipients = [NSMutableSet new];
    self.adminRecipients = [NSMutableSet new];
}

#pragma mark - View Lifecycle

- (void)loadView
{
    [super loadView];

    OWSAssertDebug(self.thread);
    OWSAssertDebug(self.thread.groupModel);
    OWSAssertDebug(self.thread.groupModel.groupMembers);

    self.view.backgroundColor = Theme.backgroundColor;

    [self.memberRecipients
        addObjectsFromArray:[self.thread.groupModel.groupMembers map:^(SignalServiceAddress *address) {
            return [PickedRecipient forAddress:address];
        }]];
    self.previousMemberRecipients = [self.memberRecipients copy];
    
    [self.adminRecipients
        addObjectsFromArray:[self.thread.groupModel.groupAdmins map:^(SignalServiceAddress *address) {
            return [PickedRecipient forAddress:address];
        }]];

    self.title = NSLocalizedString(@"EDIT_GROUP_DEFAULT_TITLE", @"The navbar title for the 'update group' view.");

    // First section.

    UIView *firstSection = [self firstSectionHeader];
    [self.view addSubview:firstSection];
    [firstSection autoSetDimension:ALDimensionHeight toSize:100.f];
    [firstSection autoPinWidthToSuperview];
    [firstSection autoPinToTopLayoutGuideOfViewController:self withInset:0];

    _recipientPicker = [RecipientPickerViewController new];
    self.recipientPicker.delegate = self;
    self.recipientPicker.shouldShowGroups = NO;
    self.recipientPicker.allowsSelectingUnregisteredPhoneNumbers = NO;
    self.recipientPicker.shouldShowAlphabetSlider = NO;
    self.recipientPicker.pickedRecipients = self.memberRecipients.allObjects;

    [self addChildViewController:self.recipientPicker];
    [self.view addSubview:self.recipientPicker.view];
    [self.recipientPicker.view autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.recipientPicker.view autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
    [self.recipientPicker.view autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:firstSection];
    [self.recipientPicker.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
}

- (void)setHasUnsavedChanges:(BOOL)hasUnsavedChanges
{
    _hasUnsavedChanges = hasUnsavedChanges;

    [self updateNavigationBar];
}

- (void)updateNavigationBar
{
    self.navigationItem.rightBarButtonItem = (self.hasUnsavedChanges
            ? [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"EDIT_GROUP_UPDATE_BUTTON",
                                                         @"The title for the 'update group' button.")
                                               style:UIBarButtonItemStylePlain
                                              target:self
                                              action:@selector(updateGroupPressed)
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"update")]
            : nil);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    switch (self.mode) {
        case UpdateGroupMode_EditGroupName:
            [self.groupNameTextField becomeFirstResponder];
            break;
        case UpdateGroupMode_EditGroupAvatar:
            [self showChangeAvatarUI];
            break;
        default:
            break;
    }
    // Only perform these actions the first time the view appears.
    self.mode = UpdateGroupMode_Default;
}

- (UIView *)firstSectionHeader
{
    OWSAssertDebug(self.thread);
    OWSAssertDebug(self.thread.groupModel);

    UIView *firstSectionHeader = [UIView new];
    firstSectionHeader.userInteractionEnabled = YES;
    [firstSectionHeader
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headerWasTapped:)]];
    firstSectionHeader.backgroundColor = [Theme backgroundColor];
    UIView *threadInfoView = [UIView new];
    [firstSectionHeader addSubview:threadInfoView];
    [threadInfoView autoPinWidthToSuperviewWithMargin:16.f];
    [threadInfoView autoPinHeightToSuperviewWithMargin:16.f];

    AvatarImageView *avatarView = [AvatarImageView new];
    _avatarView = avatarView;

    [threadInfoView addSubview:avatarView];
    [avatarView autoVCenterInSuperview];
    [avatarView autoPinLeadingToSuperviewMargin];
    [avatarView autoSetDimension:ALDimensionWidth toSize:kLargeAvatarSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:kLargeAvatarSize];
    _groupAvatarData = self.thread.groupModel.groupAvatarData;

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
    _cameraImageView = cameraImageView;

    [self updateAvatarView];

    UITextField *groupNameTextField = [OWSTextField new];
    _groupNameTextField = groupNameTextField;
    self.groupNameTextField.text = [self.thread.groupModel.groupName ows_stripped];
    groupNameTextField.textColor = Theme.primaryTextColor;
    groupNameTextField.font = [UIFont ows_dynamicTypeTitle2Font];
    groupNameTextField.placeholder
        = NSLocalizedString(@"NEW_GROUP_NAMEGROUP_REQUEST_DEFAULT", @"Placeholder text for group name field");
    groupNameTextField.delegate = self;
    [groupNameTextField addTarget:self
                           action:@selector(groupNameDidChange:)
                 forControlEvents:UIControlEventEditingChanged];
    [threadInfoView addSubview:groupNameTextField];
    [groupNameTextField autoVCenterInSuperview];
    [groupNameTextField autoPinTrailingToSuperviewMargin];
    [groupNameTextField autoPinLeadingToTrailingEdgeOfView:avatarView offset:16.f];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, groupNameTextField);

    [avatarView
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTouched:)]];
    avatarView.userInteractionEnabled = YES;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, avatarView);

    return firstSectionHeader;
}

- (void)headerWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.groupNameTextField becomeFirstResponder];
    }
}

- (void)avatarTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self showChangeAvatarUI];
    }
}

- (void)addRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    self.hasUnsavedChanges = YES;
    [self.memberRecipients addObject:recipient];
    self.recipientPicker.pickedRecipients = self.memberRecipients.allObjects;
}

- (void)removeRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    self.hasUnsavedChanges = YES;
    [self.memberRecipients removeObject:recipient];
    [self.adminRecipients removeObject:recipient];
    self.recipientPicker.pickedRecipients = self.memberRecipients.allObjects;
}

- (void)addAdminRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    self.hasUnsavedChanges = YES;
    [self.adminRecipients addObject:recipient];
    self.recipientPicker.pickedRecipients = self.memberRecipients.allObjects;
}

- (void)removeAdminRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    self.hasUnsavedChanges = YES;
    [self.adminRecipients removeObject:recipient];
    self.recipientPicker.pickedRecipients = self.memberRecipients.allObjects;
}

- (BOOL)isCurrentAdminRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    return [self.adminRecipients containsObject:recipient];
}

#pragma mark - Methods

- (void)updateGroup
{
    OWSAssertDebug(self.conversationSettingsViewDelegate);

    [self.groupNameTextField acceptAutocorrectSuggestion];

    NSArray *newMembersList = [self.memberRecipients.allObjects map:^(PickedRecipient *recipient) {
        OWSAssertDebug(recipient.address.isValid);
        return recipient.address;
    }];
    
    NSArray *newAdminsList = [self.adminRecipients.allObjects map:^(PickedRecipient *recipient) {
        OWSAssertDebug(recipient.address.isValid);
        return recipient.address;
    }];
        
    NSMutableSet *removedMemberRecipients = [self.previousMemberRecipients mutableCopy];
    [removedMemberRecipients minusSet:self.memberRecipients];
    NSArray *extraGroupRecipients = [removedMemberRecipients.allObjects map:^(PickedRecipient *recipient) {
        OWSAssertDebug(recipient.address.isValid);
        return recipient.address;
    }];
    
    // GroupsV2 TODO: Use GroupManager.
    TSGroupModel *groupModel = [[TSGroupModel alloc] initWithGroupId:self.thread.groupModel.groupId
                                                                name:self.groupNameTextField.text
                                                          avatarData:self.groupAvatarData
                                                             members:newMembersList
                                                               owner:self.thread.groupModel.groupOwner
                                                              admins:newAdminsList
                                                       groupsVersion:self.thread.groupModel.groupsVersion];
    [self.conversationSettingsViewDelegate groupWasUpdated:groupModel extraGroupRecipients:extraGroupRecipients];
}

#pragma mark - Group Avatar

- (void)showChangeAvatarUI
{
    [self.groupNameTextField resignFirstResponder];

    [self.avatarViewHelper showChangeAvatarUI];
}

- (void)setGroupAvatarData:(nullable NSData *)groupAvatarData
{
    OWSAssertIsOnMainThread();

    _groupAvatarData = groupAvatarData;

    self.hasUnsavedChanges = YES;

    [self updateAvatarView];
}

- (void)updateAvatarView
{
    UIImage *_Nullable groupAvatar;
    if (self.groupAvatarData.length > 0) {
        groupAvatar = [UIImage imageWithData:self.groupAvatarData];
    }
    self.cameraImageView.hidden = groupAvatar != nil;

    if (!groupAvatar) {
        groupAvatar = [[[OWSGroupAvatarBuilder alloc] initWithThread:self.thread diameter:kLargeAvatarSize] build];
    }

    self.avatarView.image = groupAvatar;
}

#pragma mark - Event Handling

- (void)backButtonPressed
{
    [self.groupNameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, return to conversation settings view.
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    ActionSheetController *alert = [[ActionSheetController alloc]
        initWithTitle:NSLocalizedString(@"EDIT_GROUP_VIEW_UNSAVED_CHANGES_TITLE",
                          @"The alert title if user tries to exit update group view without saving changes.")
              message:NSLocalizedString(@"EDIT_GROUP_VIEW_UNSAVED_CHANGES_MESSAGE",
                          @"The alert message if user tries to exit update group view without saving changes.")];
    [alert addAction:[[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"ALERT_SAVE",
                                                                  @"The label for the 'save' button in action sheets.")
                                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"save")
                                                        style:ActionSheetActionStyleDefault
                                                      handler:^(ActionSheetAction *action) {
                                                          OWSAssertDebug(self.conversationSettingsViewDelegate);

                                                          [self updateGroup];

                                                          [self.conversationSettingsViewDelegate
                                                              popAllConversationSettingsViewsWithCompletion:nil];
                                                      }]];
    [alert addAction:[[ActionSheetAction alloc]
                                   initWithTitle:NSLocalizedString(@"ALERT_DONT_SAVE",
                                                     @"The label for the 'don't save' button in action sheets.")
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dont_save")
                                           style:ActionSheetActionStyleDestructive
                                         handler:^(ActionSheetAction *action) {
                                             [self.navigationController popViewControllerAnimated:YES];
                                         }]];
    [self presentActionSheet:alert];
}

- (void)updateGroupPressed
{
    OWSAssertDebug(self.conversationSettingsViewDelegate);

    [self updateGroup];

    [self.conversationSettingsViewDelegate popAllConversationSettingsViewsWithCompletion:nil];
}

- (void)groupNameDidChange:(id)sender
{
    self.hasUnsavedChanges = YES;
}

#pragma mark - Text Field Delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self.groupNameTextField resignFirstResponder];
    return NO;
}

#pragma mark - AvatarViewHelperDelegate

- (nullable NSString *)avatarActionSheetTitle
{
    return NSLocalizedString(
        @"NEW_GROUP_ADD_PHOTO_ACTION", @"Action Sheet title prompting the user for a group avatar");
}

- (void)avatarDidChange:(UIImage *)image
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(image);

    self.groupAvatarData = [TSGroupModel dataForGroupAvatar:image];
}

- (UIViewController *)fromViewController
{
    return self;
}

- (BOOL)hasClearAvatarAction
{
    return NO;
}

#pragma mark - RecipientPickerDelegate

- (void)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
     didSelectRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    __weak __typeof(self) weakSelf;
    BOOL isCurrentMember = [self.memberRecipients containsObject:recipient];
    BOOL isBlocked = [self.recipientPicker.contactsViewHelper isSignalServiceAddressBlocked:recipient.address];
    if (isCurrentMember) {
        if (![self.thread isRemoteAddressGroupOwner:recipient.address] &&
            (self.thread.isLocalUserGroupOwner || self.thread.isLocalUserGroupAdmin)) {
            ActionSheetController *alert = [[ActionSheetController alloc]
                                            initWithTitle:@"Select Action"
                                                  message:nil];
            [alert addAction:[[ActionSheetAction alloc]
                              initWithTitle:@"Remove Member"
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"remove_member")
                                      style:ActionSheetActionStyleDefault
                                    handler:^(ActionSheetAction *action) {
                                        [self removeRecipient:recipient];
                                    }]];
            if (self.thread.isLocalUserGroupOwner) {
                if ([self isCurrentAdminRecipient:recipient]) {
                    [alert addAction:[[ActionSheetAction alloc]
                                      initWithTitle:@"Revoke Group Admin"
                            accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"revoke_admin")
                                              style:ActionSheetActionStyleDefault
                                            handler:^(ActionSheetAction *action) {
                                                [self removeAdminRecipient:recipient];
                                            }]];
                } else {
                    [alert addAction:[[ActionSheetAction alloc]
                                      initWithTitle:@"Make Group Admin"
                            accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"make_admin")
                                              style:ActionSheetActionStyleDefault
                                            handler:^(ActionSheetAction *action) {
                                                [self addAdminRecipient:recipient];
                                            }]];
                }
            }
            [alert addAction:[[ActionSheetAction alloc]
                              initWithTitle:@"Cancel"
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"cancel")
                                      style:ActionSheetActionStyleCancel
                                    handler:nil]];
            [self presentActionSheet:alert];
        }
    } else if (isBlocked) {
        [BlockListUIUtils showUnblockAddressActionSheet:recipient.address
                                     fromViewController:self
                                        blockingManager:self.recipientPicker.contactsViewHelper.blockingManager
                                        contactsManager:self.recipientPicker.contactsViewHelper.contactsManager
                                        completionBlock:^(BOOL isStillBlocked) {
                                            if (!isStillBlocked) {
                                                [weakSelf addRecipient:recipient];
                                                [weakSelf.navigationController popToViewController:self animated:YES];
                                            }
                                        }];
    } else {
        BOOL didShowSNAlert = [SafetyNumberConfirmationAlert
            presentAlertIfNecessaryWithAddress:recipient.address
                              confirmationText:NSLocalizedString(@"SAFETY_NUMBER_CHANGED_CONFIRM_"
                                                                 @"ADD_TO_GROUP_ACTION",
                                                   @"button title to confirm adding "
                                                   @"a recipient to a group when "
                                                   @"their safety "
                                                   @"number has recently changed")
                               contactsManager:self.recipientPicker.contactsViewHelper.contactsManager
                                    completion:^(BOOL didConfirmIdentity) {
                                        if (didConfirmIdentity) {
                                            [weakSelf addRecipient:recipient];
                                            [weakSelf.navigationController popToViewController:self animated:YES];
                                        }
                                    }];
        if (didShowSNAlert) {
            return;
        }

        [self addRecipient:recipient];
        [self.navigationController popToViewController:self animated:YES];
    }
}

- (BOOL)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
     canSelectRecipient:(PickedRecipient *)recipient
{
    return YES;
}

- (nullable NSString *)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
          accessoryMessageForRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    BOOL isCurrentMember = [self.memberRecipients containsObject:recipient];
    BOOL isCurrentOwner = [self.thread.groupModel.groupOwner isEqual:recipient.address];
    BOOL isCurrentAdmin = [self.adminRecipients containsObject:recipient];
    BOOL isBlocked = [self.recipientPicker.contactsViewHelper isSignalServiceAddressBlocked:recipient.address];

    if (isCurrentMember) {
        if (isCurrentOwner) {
            return @"Owner";
        } else if (isCurrentAdmin) {
            return @"Admin";
        } else {
            return NSLocalizedString(@"NEW_GROUP_MEMBER_LABEL", @"An indicator that a user is a member of the group.");
        }
    } else if (isBlocked) {
        return MessageStrings.conversationIsBlocked;
    } else {
        return nil;
    }
}

- (void)recipientPickerTableViewWillBeginDragging:(RecipientPickerViewController *)recipientPickerViewController
{
    [self.groupNameTextField resignFirstResponder];
}

#pragma mark - OWSNavigationView

- (BOOL)shouldCancelNavigationBack
{
    BOOL result = self.hasUnsavedChanges;
    if (result) {
        [self backButtonPressed];
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
