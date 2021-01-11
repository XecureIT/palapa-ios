//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationListViewController.h"
#import "AppDelegate.h"
#import "AppSettingsViewController.h"
#import "ConversationListCell.h"
#import "OWSNavigationController.h"
#import "OWSPrimaryStorage.h"
#import "ProfileViewController.h"
#import "RegistrationUtils.h"
#import "PALAPA-Swift.h"
#import "SignalApp.h"
#import "TSAccountManager.h"
#import "TSGroupThread.h"
#import "ViewControllerUtils.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Threading.h>
#import <SignalCoreKit/iOSVersions.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/Theme.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <StoreKit/StoreKit.h>
#import <YapDatabase/YapDatabaseViewChange.h>
#import <YapDatabase/YapDatabaseViewConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kArchivedConversationsReuseIdentifier = @"kArchivedConversationsReuseIdentifier";

typedef NS_ENUM(NSInteger, ConversationListMode) {
    ConversationListMode_Archive,
    ConversationListMode_Inbox,
};

// The bulk of the content in this view is driven by a YapDB view/mapping.
// However, we also want to optionally include ReminderView's at the top
// and an "Archived Conversations" button at the bottom. Rather than introduce
// index-offsets into the Mapping calculation, we introduce two pseudo groups
// to add a top and bottom section to the content, and create cells for those
// sections without consulting the YapMapping.
// This is a bit of a hack, but it consolidates the hacks into the Reminder/Archive section
// and allows us to leaves the bulk of the content logic on the happy path.
NSString *const kReminderViewPseudoGroup = @"kReminderViewPseudoGroup";
NSString *const kArchiveButtonPseudoGroup = @"kArchiveButtonPseudoGroup";

@interface ConversationListViewController () <UITableViewDelegate,
    UITableViewDataSource,
    UIViewControllerPreviewingDelegate,
    UISearchBarDelegate,
    ConversationSearchViewDelegate,
    ConversationListDatabaseSnapshotDelegate,
    OWSBlockListCacheDelegate,
    CameraFirstCaptureDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) UIView *emptyInboxView;

@property (nonatomic) UIView *firstConversationCueView;
@property (nonatomic) UILabel *firstConversationLabel;

@property (nonatomic, readonly) ThreadMapping *threadMapping;
@property (nonatomic) ConversationListMode conversationListMode;
@property (nonatomic) id previewingContext;
@property (nonatomic, readonly) NSCache<NSString *, ThreadViewModel *> *threadViewModelCache;
@property (nonatomic) BOOL isViewVisible;
@property (nonatomic) BOOL shouldObserveDBModifications;
@property (nonatomic) BOOL hasEverAppeared;

// Mark: Search

@property (nonatomic, readonly) OWSSearchBar *searchBar;
@property (nonatomic) ConversationSearchViewController *searchResultsController;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSBlockListCache *blocklistCache;

// Views

@property (nonatomic, readonly) UIStackView *reminderStackView;
@property (nonatomic, readonly) UITableViewCell *reminderViewCell;
@property (nonatomic, readonly) ExpirationNagView *expiredView;
@property (nonatomic, readonly) UIView *endOfLifeOSView;
@property (nonatomic, readonly) UIView *deregisteredView;
@property (nonatomic, readonly) UIView *outageView;
@property (nonatomic, readonly) UIView *archiveReminderView;
@property (nonatomic, readonly) UIView *missingContactsPermissionView;

@property (nonatomic) BOOL hasArchivedThreadsRow;
@property (nonatomic) BOOL hasThemeChanged;
@property (nonatomic) BOOL hasVisibleReminders;

@end

#pragma mark -

@implementation ConversationListViewController

#pragma mark - Init

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _conversationListMode = ConversationListMode_Inbox;

    [self commonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    OWSFailDebug(@"Do not load this from the storyboard.");

    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)commonInit
{
    _blocklistCache = [OWSBlockListCache new];
    [_blocklistCache startObservingAndSyncStateWithDelegate:self];
    _threadViewModelCache = [NSCache new];
    _threadMapping = [ThreadMapping new];
}

#pragma mark - Dependencies

- (OWSContactsManager *)contactsManager
{
    return Environment.shared.contactsManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

// POST GRDB TODO - Remove
- (nullable OWSPrimaryStorage *)primaryStorage
{
    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];
    if (StorageCoordinator.dataStoreForUI == DataStoreGrdb) {
        [self.databaseStorage.grdbStorage.conversationListDatabaseObserver appendSnapshotDelegate:self];
    } else {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(uiDatabaseDidUpdateExternally:)
                                                     name:OWSUIDatabaseConnectionDidUpdateExternallyNotification
                                                   object:self.primaryStorage.dbNotificationObject];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(uiDatabaseWillUpdate:)
                                                     name:OWSUIDatabaseConnectionWillUpdateNotification
                                                   object:self.primaryStorage.dbNotificationObject];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(uiDatabaseDidUpdate:)
                                                     name:OWSUIDatabaseConnectionDidUpdateNotification
                                                   object:self.primaryStorage.dbNotificationObject];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange:)
                                                 name:RegistrationStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(outageStateDidChange:)
                                                 name:OutageDetection.outageStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localProfileDidChange:)
                                                 name:kNSNotificationName_LocalProfileDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)signalAccountsDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self reloadTableViewData];

    if (!self.firstConversationCueView.isHidden) {
        [self updateFirstConversationLabel];
    }
}

- (void)registrationStateDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self updateReminderViews];
}

- (void)outageStateDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self updateReminderViews];
}

- (void)localProfileDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self updateBarButtonItems];
}

#pragma mark - Theme

- (void)themeDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self applyTheme];
    [self.tableView reloadData];

    self.hasThemeChanged = YES;
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.tableView);
    OWSAssertDebug(self.searchBar);

    if (self.splitViewController.isCollapsed) {
        self.view.backgroundColor = Theme.backgroundColor;
        self.tableView.backgroundColor = Theme.backgroundColor;
        [self.searchBar switchToStyle:OWSSearchBarStyle_Default];
    } else {
        self.view.backgroundColor = Theme.secondaryBackgroundColor;
        self.tableView.backgroundColor = Theme.secondaryBackgroundColor;
        [self.searchBar switchToStyle:OWSSearchBarStyle_SecondaryBar];
    }

    [self updateBarButtonItems];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    if (!self.isViewLoaded) {
        return;
    }

    // There is a subtle difference in when the split view controller
    // transitions between collapsed and expanded state on iPad vs
    // when it does on iPhone. We reloadData here in order to ensure
    // the background color of all of our cells is updated to reflect
    // the current state, so it's important that we're only doing this
    // once the state is ready, otherwise there will be a flash of the
    // wrong background color. For iPad, this moment is _before_ the
    // transition occurs. For iPhone, this moment is _during_ the
    // transition. We reload in the right places accordingly.

    if (UIDevice.currentDevice.isIPad) {
        [self.tableView reloadData];
    }

    [coordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            [self applyTheme];
            if (!UIDevice.currentDevice.isIPad) {
                [self.tableView reloadData];
            }
        }
                        completion:nil];
}

#pragma mark - View Life Cycle

- (void)loadView
{
    [super loadView];

    UIStackView *reminderStackView = [UIStackView new];
    _reminderStackView = reminderStackView;
    reminderStackView.axis = UILayoutConstraintAxisVertical;
    reminderStackView.spacing = 0;
    _reminderViewCell = [UITableViewCell new];
    self.reminderViewCell.selectionStyle = UITableViewCellSelectionStyleNone;
    [self.reminderViewCell.contentView addSubview:reminderStackView];
    [reminderStackView autoPinEdgesToSuperviewEdges];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _reminderViewCell);
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, reminderStackView);

    __weak ConversationListViewController *weakSelf = self;
    ReminderView *deregisteredView = [ReminderView
        nagWithText:TSAccountManager.sharedInstance.isPrimaryDevice
            ? NSLocalizedString(@"DEREGISTRATION_WARNING", @"Label warning the user that they have been de-registered.")
            : NSLocalizedString(
                @"UNLINKED_WARNING", @"Label warning the user that they have been unlinked from their primary device.")
          tapAction:^{
              ConversationListViewController *strongSelf = weakSelf;
              if (!strongSelf) {
                  return;
              }
              [RegistrationUtils showReregistrationUIFromViewController:strongSelf];
          }];
    _deregisteredView = deregisteredView;
    [reminderStackView addArrangedSubview:deregisteredView];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, deregisteredView);

    ReminderView *endOfLifeOSView =
        [ReminderView nagWithText:NSLocalizedString(@"END_OF_LIFE_OS_WARNING",
                                      @"Label indicating that this OS version is no longer supported.")
                        tapAction:nil];
    _endOfLifeOSView = endOfLifeOSView;
    [reminderStackView addArrangedSubview:endOfLifeOSView];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, endOfLifeOSView);

    ExpirationNagView *expiredView = [ExpirationNagView new];
    _expiredView = expiredView;
    [reminderStackView addArrangedSubview:expiredView];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, expiredView);

    ReminderView *outageView = [ReminderView
        nagWithText:NSLocalizedString(@"OUTAGE_WARNING", @"Label warning the user that the Signal service may be down.")
          tapAction:nil];
    _outageView = outageView;
    [reminderStackView addArrangedSubview:outageView];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, outageView);

    ReminderView *archiveReminderView =
        [ReminderView explanationWithText:NSLocalizedString(@"INBOX_VIEW_ARCHIVE_MODE_REMINDER",
                                              @"Label reminding the user that they are in archive mode.")];
    _archiveReminderView = archiveReminderView;
    [reminderStackView addArrangedSubview:archiveReminderView];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, archiveReminderView);

    ReminderView *missingContactsPermissionView = [ReminderView
        nagWithText:NSLocalizedString(@"INBOX_VIEW_MISSING_CONTACTS_PERMISSION",
                        @"Multi-line label explaining how to show names instead of phone numbers in your inbox")
          tapAction:^{
              [[UIApplication sharedApplication] openSystemSettings];
          }];
    _missingContactsPermissionView = missingContactsPermissionView;
    [reminderStackView addArrangedSubview:missingContactsPermissionView];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, missingContactsPermissionView);

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.separatorColor = Theme.cellSeparatorColor;
    [self.tableView registerClass:[ConversationListCell class]
           forCellReuseIdentifier:ConversationListCell.cellReuseIdentifier];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kArchivedConversationsReuseIdentifier];
    [self.view addSubview:self.tableView];
    [self.tableView autoPinEdgesToSuperviewEdges];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _tableView);
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _searchBar);

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;

    self.emptyInboxView = [self createEmptyInboxView];
    [self.view addSubview:self.emptyInboxView];
    [self.emptyInboxView autoPinWidthToSuperviewMargins];
    [self.emptyInboxView autoVCenterInSuperview];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _emptyInboxView);

    [self createFirstConversationCueView];
    [self.view addSubview:self.firstConversationCueView];
    [self.firstConversationCueView autoPinToTopLayoutGuideOfViewController:self withInset:0.f];
    // This inset bakes in assumptions about UINavigationBar layout, but I'm not sure
    // there's a better way to do it, since it isn't safe to use iOS auto layout with
    // UINavigationBar contents.
    [self.firstConversationCueView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:6.f];
    [self.firstConversationCueView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                                    withInset:10
                                                     relation:NSLayoutRelationGreaterThanOrEqual];
    [self.firstConversationCueView autoPinEdgeToSuperviewMargin:ALEdgeBottom
                                                       relation:NSLayoutRelationGreaterThanOrEqual];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _firstConversationCueView);
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _firstConversationLabel);

    UIRefreshControl *pullToRefreshView = [UIRefreshControl new];
    pullToRefreshView.tintColor = [UIColor grayColor];
    [pullToRefreshView addTarget:self
                          action:@selector(pullToRefreshPerformed:)
                forControlEvents:UIControlEventValueChanged];
    [self.tableView insertSubview:pullToRefreshView atIndex:0];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, pullToRefreshView);
}

- (UIView *)createEmptyInboxView
{
    NSArray<NSString *> *emptyInboxImageNames = @[
        @"home_empty_splash_1",
        @"home_empty_splash_2",
        @"home_empty_splash_3",
        @"home_empty_splash_4",
        @"home_empty_splash_5",
    ];
    NSString *emptyInboxImageName = emptyInboxImageNames[arc4random_uniform((uint32_t)emptyInboxImageNames.count)];
    UIImageView *emptyInboxImageView = [UIImageView new];
    emptyInboxImageView.image = [UIImage imageNamed:emptyInboxImageName];
    emptyInboxImageView.layer.minificationFilter = kCAFilterTrilinear;
    emptyInboxImageView.layer.magnificationFilter = kCAFilterTrilinear;
    [emptyInboxImageView autoPinToAspectRatioWithSize:emptyInboxImageView.image.size];
    CGSize navControllerSize = self.navigationController.view.frame.size;
    CGFloat emptyInboxImageSize = MIN(navControllerSize.width, navControllerSize.height) * 0.65f;
    [emptyInboxImageView autoSetDimension:ALDimensionWidth toSize:emptyInboxImageSize];

    UILabel *emptyInboxLabel = [UILabel new];
    emptyInboxLabel.text = NSLocalizedString(
        @"INBOX_VIEW_EMPTY_INBOX", @"Message shown in the conversation list when the inbox is empty.");
    emptyInboxLabel.font = UIFont.ows_dynamicTypeBodyClampedFont;
    emptyInboxLabel.textColor = Theme.secondaryTextAndIconColor;
    emptyInboxLabel.textAlignment = NSTextAlignmentCenter;
    emptyInboxLabel.numberOfLines = 0;
    emptyInboxLabel.lineBreakMode = NSLineBreakByWordWrapping;

    UIStackView *emptyInboxStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        emptyInboxImageView,
        emptyInboxLabel,
    ]];
    emptyInboxStack.axis = UILayoutConstraintAxisVertical;
    emptyInboxStack.alignment = UIStackViewAlignmentCenter;
    emptyInboxStack.spacing = 12;
    emptyInboxStack.layoutMargins = UIEdgeInsetsMake(50, 50, 50, 50);
    emptyInboxStack.layoutMarginsRelativeArrangement = YES;
    return emptyInboxStack;
}

- (void)createFirstConversationCueView
{
    const CGFloat kTailWidth = 16.f;
    const CGFloat kTailHeight = 8.f;
    const CGFloat kTailHMargin = 12.f;

    UILabel *label = [UILabel new];
    label.textColor = UIColor.ows_whiteColor;
    label.font = UIFont.ows_dynamicTypeBodyClampedFont;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;

    OWSLayerView *layerView = [OWSLayerView new];
    layerView.layoutMargins = UIEdgeInsetsMake(11 + kTailHeight, 16, 11, 16);
    CAShapeLayer *shapeLayer = [CAShapeLayer new];
    shapeLayer.fillColor = UIColor.ows_signalBlueColor.CGColor;
    [layerView.layer addSublayer:shapeLayer];
    layerView.layoutCallback = ^(UIView *view) {
        UIBezierPath *bezierPath = [UIBezierPath new];

        // Bubble
        CGRect bubbleBounds = view.bounds;
        bubbleBounds.origin.y += kTailHeight;
        bubbleBounds.size.height -= kTailHeight;
        [bezierPath appendPath:[UIBezierPath bezierPathWithRoundedRect:bubbleBounds cornerRadius:8]];

        // Tail
        CGPoint tailTop = CGPointMake(kTailHMargin + kTailWidth * 0.5f, 0.f);
        CGPoint tailLeft = CGPointMake(kTailHMargin, kTailHeight);
        CGPoint tailRight = CGPointMake(kTailHMargin + kTailWidth, kTailHeight);
        if (!CurrentAppContext().isRTL) {
            tailTop.x = view.width - tailTop.x;
            tailLeft.x = view.width - tailLeft.x;
            tailRight.x = view.width - tailRight.x;
        }
        [bezierPath moveToPoint:tailTop];
        [bezierPath addLineToPoint:tailLeft];
        [bezierPath addLineToPoint:tailRight];
        [bezierPath addLineToPoint:tailTop];
        shapeLayer.path = bezierPath.CGPath;
        shapeLayer.frame = view.bounds;
    };

    [layerView addSubview:label];
    [label autoPinEdgesToSuperviewMargins];

    layerView.userInteractionEnabled = YES;
    [layerView
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(firstConversationCueWasTapped:)]];

    self.firstConversationCueView = layerView;
    self.firstConversationLabel = label;
}

- (void)firstConversationCueWasTapped:(UITapGestureRecognizer *)gestureRecognizer
{
    OWSLogInfo(@"");

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [AppPreferences setHasDimissedFirstConversationCue:YES transaction:transaction];
    }];

    [self updateViewState];
}

- (NSArray<SignalAccount *> *)suggestedAccountsForFirstContact
{
    NSMutableArray<SignalAccount *> *accounts = [NSMutableArray new];

    for (SignalAccount *account in self.contactsManager.signalAccounts) {
        if (account.recipientAddress.isLocalAddress) {
            continue;
        }
        if (accounts.count >= 3) {
            break;
        }
        [accounts addObject:account];
    }

    return [accounts copy];
}

- (void)updateFirstConversationLabel
{

    NSArray<SignalAccount *> *signalAccounts = self.suggestedAccountsForFirstContact;

    NSString *formatString = @"";
    NSMutableArray<NSString *> *contactNames = [NSMutableArray new];
    if (signalAccounts.count >= 3) {
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[0]]];
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[1]]];
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[2]]];

        formatString = NSLocalizedString(@"HOME_VIEW_FIRST_CONVERSATION_OFFER_3_CONTACTS_FORMAT",
            @"Format string for a label offering to start a new conversation with your contacts, if you have at least "
            @"3 Signal contacts.  Embeds {{The names of 3 of your Signal contacts}}.");
    } else if (signalAccounts.count == 2) {
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[0]]];
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[1]]];

        formatString = NSLocalizedString(@"HOME_VIEW_FIRST_CONVERSATION_OFFER_2_CONTACTS_FORMAT",
            @"Format string for a label offering to start a new conversation with your contacts, if you have 2 Signal "
            @"contacts.  Embeds {{The names of 2 of your Signal contacts}}.");
    } else if (signalAccounts.count == 1) {
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[0]]];

        formatString = NSLocalizedString(@"HOME_VIEW_FIRST_CONVERSATION_OFFER_1_CONTACT_FORMAT",
            @"Format string for a label offering to start a new conversation with your contacts, if you have 1 Signal "
            @"contact.  Embeds {{The name of 1 of your Signal contacts}}.");
    }

    NSString *embedToken = @"%@";
    NSArray<NSString *> *formatSplits = [formatString componentsSeparatedByString:embedToken];
    // We need to use a complicated format string that possibly embeds multiple contact names.
    // Translator error could easily lead to an invalid format string.
    // We need to verify that it was translated properly.
    BOOL isValidFormatString = (contactNames.count > 0 && formatSplits.count == contactNames.count + 1);
    for (NSString *contactName in contactNames) {
        if ([contactName containsString:embedToken]) {
            isValidFormatString = NO;
        }
    }

    NSMutableAttributedString *_Nullable attributedString = nil;
    if (isValidFormatString) {
        attributedString = [[NSMutableAttributedString alloc] initWithString:formatString];
        while (contactNames.count > 0) {
            NSString *contactName = contactNames.firstObject;
            [contactNames removeObjectAtIndex:0];

            NSRange range = [attributedString.string rangeOfString:embedToken];
            if (range.location == NSNotFound) {
                // Error
                attributedString = nil;
                break;
            }

            NSAttributedString *formattedName =
                [[NSAttributedString alloc] initWithString:contactName
                                                attributes:@{
                                                    NSFontAttributeName : self.firstConversationLabel.font.ows_semibold,
                                                }];
            [attributedString replaceCharactersInRange:range withAttributedString:formattedName];
        }
    }

    if (!attributedString) {
        // The default case handles the no-contacts scenario and all error cases.
        NSString *defaultText = NSLocalizedString(@"HOME_VIEW_FIRST_CONVERSATION_OFFER_NO_CONTACTS",
            @"A label offering to start a new conversation with your contacts, if you have no Signal contacts.");
        attributedString = [[NSMutableAttributedString alloc] initWithString:defaultText];
    }

    self.firstConversationLabel.attributedText = [attributedString copy];
}

- (void)updateReminderViews
{
    self.archiveReminderView.hidden = self.conversationListMode != ConversationListMode_Archive;
    // App is killed and restarted when the user changes their contact permissions, so need need to "observe" anything
    // to re-render this.
    self.missingContactsPermissionView.hidden = !self.contactsManager.isSystemContactsDenied;
    self.deregisteredView.hidden = !TSAccountManager.sharedInstance.isDeregistered;
    self.outageView.hidden = !OutageDetection.sharedManager.hasOutage;
    self.endOfLifeOSView.hidden = !SSKAppExpiry.isEndOfLifeOSVersion;

    self.expiredView.hidden = !SSKAppExpiry.isExpiringSoon;
    [self.expiredView updateText];

    self.hasVisibleReminders = !self.archiveReminderView.isHidden || !self.missingContactsPermissionView.isHidden
        || !self.deregisteredView.isHidden || !self.outageView.isHidden || !self.expiredView.isHidden
        || !self.endOfLifeOSView.isHidden;
}

- (void)setHasVisibleReminders:(BOOL)hasVisibleReminders
{
    if (_hasVisibleReminders == hasVisibleReminders) {
        return;
    }
    _hasVisibleReminders = hasVisibleReminders;
    // If the reminders show/hide, reload the table.
    [self.tableView reloadData];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self observeNotifications];
    [self resetMappings];
    [self tableViewSetUp];

    switch (self.conversationListMode) {
        case ConversationListMode_Inbox:
            // TODO: Should our app name be translated?  Probably not.
            self.title
                = NSLocalizedString(@"HOME_VIEW_TITLE_INBOX", @"Title for the conversation list's default mode.");
            break;
        case ConversationListMode_Archive:
            self.title
                = NSLocalizedString(@"HOME_VIEW_TITLE_ARCHIVE", @"Title for the conversation list's 'archive' mode.");
            break;
    }

    [self applyDefaultBackButton];

    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)]
        && (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable)) {
        [self registerForPreviewingWithDelegate:self sourceView:self.tableView];
    }

    // Search

    _searchBar = [OWSSearchBar new];
    self.searchBar.placeholder = NSLocalizedString(@"HOME_VIEW_CONVERSATION_SEARCHBAR_PLACEHOLDER",
        @"Placeholder text for search bar which filters conversations.");
    self.searchBar.delegate = self;
    self.searchBar.textField.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"conversation_search");
    [self.searchBar sizeToFit];

    // Setting tableHeader calls numberOfSections, which must happen after updateMappings has been called at least once.
    OWSAssertDebug(self.tableView.tableHeaderView == nil);
    self.tableView.tableHeaderView = self.searchBar;
    // Hide search bar by default.  User can pull down to search.
    self.tableView.contentOffset = CGPointMake(0, CGRectGetHeight(self.searchBar.frame));

    ConversationSearchViewController *searchResultsController = [ConversationSearchViewController new];
    searchResultsController.delegate = self;
    self.searchResultsController = searchResultsController;
    [self addChildViewController:searchResultsController];
    [self.view addSubview:searchResultsController.view];
    [searchResultsController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [searchResultsController.view autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [searchResultsController.view autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    if (@available(iOS 11, *)) {
        [searchResultsController.view autoPinTopToSuperviewMarginWithInset:56];
    } else {
        [searchResultsController.view autoPinToTopLayoutGuideOfViewController:self withInset:40];
    }
    searchResultsController.view.hidden = YES;

    [self updateReminderViews];
    [self updateBarButtonItems];

    [self applyTheme];
}

- (void)applyDefaultBackButton
{
    // We don't show any text for the back button, so there's no need to localize it. But because we left align the
    // conversation title view, we add a little tappable padding after the back button, by having a title of spaces.
    // Admittedly this is kind of a hack and not super fine grained, but it's simple and results in the interactive pop
    // gesture animating our title view nicely vs. creating our own back button bar item with custom padding, which does
    // not properly animate with the "swipe to go back" or "swipe left for info" gestures.
    NSUInteger paddingLength = 3;
    NSString *paddingString = [@"" stringByPaddingToLength:paddingLength withString:@" " startingAtIndex:0];

    self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:paddingString
                                         style:UIBarButtonItemStylePlain
                                        target:nil
                                        action:nil
                       accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"back")];
}

- (void)applyArchiveBackButton
{
    self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:CommonStrings.backButton
                                         style:UIBarButtonItemStylePlain
                                        target:nil
                                        action:nil
                       accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"back")];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self displayAnyUnseenUpgradeExperience];
    [self applyDefaultBackButton];

    if (self.hasThemeChanged) {
        [self.tableView reloadData];
        self.hasThemeChanged = NO;
    }

    // Whether or not the theme has changed, always ensure
    // the right theme is applied. The initial collapsed
    // state of the split view controller is determined between
    // `viewWillAppear` and `viewDidAppear`, so this is the soonest
    // we can know the right thing to display.
    [self applyTheme];

    [self requestReviewIfAppropriate];

    [self.searchResultsController viewDidAppear:animated];

    self.hasEverAppeared = YES;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];

    [self.searchResultsController viewDidDisappear:animated];
}

- (void)updateBarButtonItems
{
    if (self.conversationListMode != ConversationListMode_Inbox) {
        return;
    }

    //  Settings button.
    UIBarButtonItem *settingsButton;
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 0)) {
        const NSUInteger kAvatarSize = 28;
        UIImage *_Nullable localProfileAvatarImage = [OWSProfileManager.sharedManager localProfileAvatarImage];
        UIImage *avatarImage = (localProfileAvatarImage
                ?: [[[OWSContactAvatarBuilder alloc] initForLocalUserWithDiameter:kAvatarSize] buildDefaultImage]);
        OWSAssertDebug(avatarImage);

        UIButton *avatarButton = [AvatarImageButton buttonWithType:UIButtonTypeCustom];
        [avatarButton addTarget:self action:@selector(showAppSettings) forControlEvents:UIControlEventTouchUpInside];
        [avatarButton setImage:avatarImage forState:UIControlStateNormal];
        [avatarButton autoSetDimension:ALDimensionWidth toSize:kAvatarSize];
        [avatarButton autoSetDimension:ALDimensionHeight toSize:kAvatarSize];

        settingsButton = [[UIBarButtonItem alloc] initWithCustomView:avatarButton];
    } else {
        // iOS 9 and 10 have a bug around layout of custom views in UIBarButtonItem,
        // so we just use a simple icon.
        UIImage *image = [UIImage imageNamed:@"button_settings_white"];
        settingsButton = [[UIBarButtonItem alloc] initWithImage:image
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(showAppSettings)
                                        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"settings")];
    }
    settingsButton.accessibilityLabel = CommonStrings.openSettingsButton;
    
    UIBarButtonItem *personalnotes =[[UIBarButtonItem alloc] initWithImage:[Theme iconImage:ThemeIconPersonalNotes]
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(openPersonalNotes)];
    
    //self.navigationItem.leftBarButtonItem = settingsButton;
    self.navigationItem.leftBarButtonItems = @[ settingsButton, personalnotes ];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, settingsButton);

    UIBarButtonItem *compose = [[UIBarButtonItem alloc] initWithImage:[Theme iconImage:ThemeIconCompose]
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(showNewConversationView)];
    compose.accessibilityLabel
        = NSLocalizedString(@"COMPOSE_BUTTON_LABEL", @"Accessibility label from compose button.");
    compose.accessibilityHint = NSLocalizedString(
        @"COMPOSE_BUTTON_HINT", @"Accessibility hint describing what you can do with the compose button");
    compose.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"compose");

    if (SSKFeatureFlags.cameraFirstCaptureFlow) {
        UIBarButtonItem *camera = [[UIBarButtonItem alloc] initWithImage:[Theme iconImage:ThemeIconCameraButton]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(showCameraView)];
        camera.accessibilityLabel
            = NSLocalizedString(@"CAMERA_BUTTON_LABEL", @"Accessibility label for camera button.");
        camera.accessibilityHint = NSLocalizedString(
            @"CAMERA_BUTTON_HINT", @"Accessibility hint describing what you can do with the camera button");
        camera.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"camera");

        self.navigationItem.rightBarButtonItems = @[ compose, camera ];
    } else {
        self.navigationItem.rightBarButtonItems = @[ compose ];
    }
}

- (nullable UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
                       viewControllerForLocation:(CGPoint)location
{
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];

    if (!indexPath) {
        return nil;
    }

    if (indexPath.section != ConversationListViewControllerSectionConversations) {
        return nil;
    }

    [previewingContext setSourceRect:[self.tableView rectForRowAtIndexPath:indexPath]];

    ConversationViewController *vc = [ConversationViewController new];
    TSThread *thread = [self threadForIndexPath:indexPath];
    self.lastViewedThread = thread;
    [vc configureForThread:thread action:ConversationViewActionNone focusMessageId:nil];
    [vc peekSetup];

    return vc;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
     commitViewController:(UIViewController *)viewControllerToCommit
{
    ConversationViewController *vc = (ConversationViewController *)viewControllerToCommit;
    [vc popped];

    [self.navigationController pushViewController:vc animated:NO];
}

- (void)showNewConversationView
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // Dismiss any message actions if they're presented
    [self.conversationSplitViewController.selectedConversationViewController dismissMessageActionsAnimated:YES];

    ComposeViewController *viewController = [ComposeViewController new];

    [self.contactsManager requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
        if (error) {
            OWSLogError(@"Error when requesting contacts: %@", error);
        }
        // Even if there is an error fetching contacts we proceed to the next screen.
        // As the compose view will present the proper thing depending on contact access.
        //
        // We just want to make sure contact access is *complete* before showing the compose
        // screen to avoid flicker.
        OWSNavigationController *modal = [[OWSNavigationController alloc] initWithRootViewController:viewController];
        [self.navigationController presentFormSheetViewController:modal animated:YES completion:nil];
    }];
}

- (void)showNewGroupView
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // Dismiss any message actions if they're presented
    [self.conversationSplitViewController.selectedConversationViewController dismissMessageActionsAnimated:YES];

    NewGroupViewController *viewController = [NewGroupViewController new];

    [self.contactsManager requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
        if (error) {
            OWSLogError(@"Error when requesting contacts: %@", error);
        }
        // Even if there is an error fetching contacts we proceed to the next screen.
        // As the compose view will present the proper thing depending on contact access.
        //
        // We just want to make sure contact access is *complete* before showing the compose
        // screen to avoid flicker.
        OWSNavigationController *modal = [[OWSNavigationController alloc] initWithRootViewController:viewController];
        [self.navigationController presentFormSheetViewController:modal animated:YES completion:nil];
    }];
}

- (void)showAppSettings
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // Dismiss any message actions if they're presented
    [self.conversationSplitViewController.selectedConversationViewController dismissMessageActionsAnimated:YES];

    OWSNavigationController *navigationController = [AppSettingsViewController inModalNavigationController];
    [self presentFormSheetViewController:navigationController animated:YES completion:nil];
}

- (void)openPersonalNotes
{
    OWSAssertIsOnMainThread();
    
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:TSAccountManager.localAddress];
    [SignalApp.sharedApp presentConversationForThread:thread animated:YES];
}

- (void)focusSearch
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // If we have presented a conversation list (the archive) search there instead.
    if (self.presentedConversationListViewController) {
        [self.presentedConversationListViewController focusSearch];
        return;
    }

    [self.searchBar becomeFirstResponder];
}

- (void)selectPreviousConversation
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // If we have presented a conversation list (the archive) navigate through that instead.
    if (self.presentedConversationListViewController) {
        [self.presentedConversationListViewController selectPreviousConversation];
        return;
    }

    TSThread *_Nullable currentThread = self.conversationSplitViewController.selectedThread;
    NSIndexPath *_Nullable previousIndexPath = [self.threadMapping indexPathBeforeThread:currentThread];
    if (previousIndexPath) {
        [self presentThread:[self threadForIndexPath:previousIndexPath] action:ConversationViewActionCompose animated:YES];
        [self.tableView selectRowAtIndexPath:previousIndexPath
                                    animated:YES
                              scrollPosition:UITableViewScrollPositionNone];
    }
}

- (void)selectNextConversation
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // If we have presented a conversation list (the archive) navigate through that instead.
    if (self.presentedConversationListViewController) {
        [self.presentedConversationListViewController selectNextConversation];
        return;
    }

    TSThread *_Nullable currentThread = self.conversationSplitViewController.selectedThread;
    NSIndexPath *_Nullable nextIndexPath = [self.threadMapping indexPathAfterThread:currentThread];
    if (nextIndexPath) {
        [self presentThread:[self threadForIndexPath:nextIndexPath] action:ConversationViewActionCompose animated:YES];
        [self.tableView selectRowAtIndexPath:nextIndexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
}

- (void)archiveSelectedConversation
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    TSThread *_Nullable selectedThread = self.conversationSplitViewController.selectedThread;

    if (!selectedThread) {
        return;
    }

    if (selectedThread.isArchived) {
        return;
    }

    [self.conversationSplitViewController closeSelectedConversationAnimated:YES];

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [selectedThread archiveThreadWithTransaction:transaction];
    }];
    [self updateViewState];
}

- (void)unarchiveSelectedConversation
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    TSThread *_Nullable selectedThread = self.conversationSplitViewController.selectedThread;

    if (!selectedThread) {
        return;
    }

    if (!selectedThread.isArchived) {
        return;
    }

    [self.conversationSplitViewController closeSelectedConversationAnimated:YES];

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [selectedThread unarchiveThreadWithTransaction:transaction];
    }];
    [self updateViewState];
}

- (void)showCameraView
{
    // Dismiss any message actions if they're presented
    [self.conversationSplitViewController.selectedConversationViewController dismissMessageActionsAnimated:YES];

    [self ows_askForCameraPermissions:^(BOOL cameraGranted) {
        if (!cameraGranted) {
            OWSLogWarn(@"camera permission denied.");
            return;
        }
        [self ows_askForMicrophonePermissions:^(BOOL micGranted) {
            if (!micGranted) {
                OWSLogWarn(@"proceeding, though mic permission denied.");
                // We can still continue without mic permissions, but any captured video will
                // be silent.
            }

            CameraFirstCaptureNavigationController *cameraModal =
                [CameraFirstCaptureNavigationController cameraFirstModal];
            cameraModal.cameraFirstCaptureSendFlow.delegate = self;

            [self presentFullScreenViewController:cameraModal animated:YES completion:nil];
        }];
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.isViewVisible = YES;

    BOOL isShowingSearchResults = !self.searchResultsController.view.hidden;
    if (isShowingSearchResults) {
        OWSAssertDebug(self.searchBar.text.ows_stripped.length > 0);
        [self scrollSearchBarToTopAnimated:NO];
        [self.searchBar becomeFirstResponder];
    } else if (self.lastViewedThread) {
        OWSAssertDebug(self.searchBar.text.ows_stripped.length == 0);

        // When returning to conversation list, try to ensure that the "last" thread is still
        // visible.  The threads often change ordering while in conversation view due
        // to incoming & outgoing messages.
        NSIndexPath *_Nullable indexPathOfLastThread =
            [self.threadMapping indexPathForUniqueId:self.lastViewedThread.uniqueId];
        if (indexPathOfLastThread) {
            [self.tableView scrollToRowAtIndexPath:indexPathOfLastThread
                                  atScrollPosition:UITableViewScrollPositionNone
                                          animated:NO];
        }
    }

    [self updateViewState];
    [self applyDefaultBackButton];
    if ([self updateHasArchivedThreadsRow]) {
        [self.tableView reloadData];
    }

    [self.searchResultsController viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    self.isViewVisible = NO;

    [self.searchResultsController viewWillDisappear:animated];
}

- (void)setIsViewVisible:(BOOL)isViewVisible
{
    _isViewVisible = isViewVisible;

    [self updateShouldObserveDBModifications];
}

- (void)updateShouldObserveDBModifications
{
    BOOL isAppForegroundAndActive = CurrentAppContext().isAppForegroundAndActive;
    self.shouldObserveDBModifications = self.isViewVisible && isAppForegroundAndActive;
}

- (void)setShouldObserveDBModifications:(BOOL)shouldObserveDBModifications
{
    if (_shouldObserveDBModifications == shouldObserveDBModifications) {
        return;
    }

    _shouldObserveDBModifications = shouldObserveDBModifications;

    if (self.shouldObserveDBModifications) {
        [self resetMappings];
    }
}

- (void)reloadTableViewData
{
    // PERF: come up with a more nuanced cache clearing scheme
    [self.threadViewModelCache removeAllObjects];
    [self.tableView reloadData];
}

- (void)resetMappings
{
    [BenchManager benchWithTitle:@"ConversationListViewController#resetMappings"
                           block:^{
                               [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
                                   [self.threadMapping updateSwallowingErrorsWithIsViewingArchive:self.isViewingArchive
                                                                                      transaction:transaction];
                               }];

                               [self updateHasArchivedThreadsRow];
                               [self reloadTableViewData];

                               [self updateViewState];
                           }];
}

- (BOOL)isViewingArchive
{
    return self.conversationListMode == ConversationListMode_Archive;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self updateViewState];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self updateShouldObserveDBModifications];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self updateShouldObserveDBModifications];
}

#pragma mark - startup

- (NSArray<ExperienceUpgrade *> *)unseenUpgradeExperiences
{
    OWSAssertIsOnMainThread();

    __block NSArray<ExperienceUpgrade *> *unseenUpgrades;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        unseenUpgrades = [ExperienceUpgradeFinder.sharedManager allUnseenWithTransaction:transaction];
    }];
    return unseenUpgrades;
}

- (void)displayAnyUnseenUpgradeExperience
{
    OWSAssertIsOnMainThread();

    NSArray<ExperienceUpgrade *> *unseenUpgrades = [self unseenUpgradeExperiences];

    if (unseenUpgrades.count > 0) {
        ExperienceUpgrade *firstUpgrade = unseenUpgrades.firstObject;
        UIViewController *_Nullable viewController =
            [ExperienceUpgradeViewController viewControllerForExperienceUpgrade:firstUpgrade];
        if (viewController == nil) {
            OWSFailDebug(@"Could not display experience upgrade.");
            return;
        }
        [self presentFormSheetViewController:viewController animated:YES completion:nil];
    } else {
        [OWSActionSheets showIOSUpgradeNagIfNecessary];
    }
}

- (void)tableViewSetUp
{
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Table View Data Source

// Returns YES IFF this value changes.
- (BOOL)updateHasArchivedThreadsRow
{
    BOOL hasArchivedThreadsRow
        = (self.conversationListMode == ConversationListMode_Inbox && self.numberOfArchivedThreads > 0);
    if (self.hasArchivedThreadsRow == hasArchivedThreadsRow) {
        return NO;
    }
    self.hasArchivedThreadsRow = hasArchivedThreadsRow;

    return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)aSection
{
    ConversationListViewControllerSection section = (ConversationListViewControllerSection)aSection;
    switch (section) {
        case ConversationListViewControllerSectionReminders: {
            return self.hasVisibleReminders ? 1 : 0;
        }
        case ConversationListViewControllerSectionConversations: {
            return [self.threadMapping numberOfItemsInSection:section];
        }
        case ConversationListViewControllerSectionArchiveButton: {
            return self.hasArchivedThreadsRow ? 1 : 0;
        }
    }

    OWSFailDebug(@"failure: unexpected section: %lu", (unsigned long)section);
    return 0;
}

- (ThreadViewModel *)threadViewModelForIndexPath:(NSIndexPath *)indexPath
{
    TSThread *threadRecord = [self threadForIndexPath:indexPath];
    OWSAssertDebug(threadRecord);

    ThreadViewModel *_Nullable cachedThreadViewModel = [self.threadViewModelCache objectForKey:threadRecord.uniqueId];
    if (cachedThreadViewModel) {
        return cachedThreadViewModel;
    }

    __block ThreadViewModel *_Nullable newThreadViewModel;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        newThreadViewModel = [[ThreadViewModel alloc] initWithThread:threadRecord transaction:transaction];
    }];
    [self.threadViewModelCache setObject:newThreadViewModel forKey:threadRecord.uniqueId];
    return newThreadViewModel;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ConversationListViewControllerSection section = (ConversationListViewControllerSection)indexPath.section;

    UITableViewCell *_Nullable cell;

    switch (section) {
        case ConversationListViewControllerSectionReminders: {
            OWSAssert(self.reminderStackView);
            cell = self.reminderViewCell;
            break;
        }
        case ConversationListViewControllerSectionConversations: {
            cell = [self tableView:tableView cellForConversationAtIndexPath:indexPath];
            break;
        }
        case ConversationListViewControllerSectionArchiveButton: {
            cell = [self cellForArchivedConversationsRow:tableView];
            break;
        }
    }

    if (!cell) {
        OWSFailDebug(@"failure: unexpected section: %lu", (unsigned long)section);
        cell = [UITableViewCell new];
    }

    if (!self.splitViewController.isCollapsed) {
        cell.selectedBackgroundView.backgroundColor
            = Theme.isDarkThemeEnabled ? UIColor.ows_gray65Color : UIColor.ows_gray15Color;
        cell.backgroundColor = Theme.secondaryBackgroundColor;
    }

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForConversationAtIndexPath:(NSIndexPath *)indexPath
{
    ConversationListCell *cell =
        [self.tableView dequeueReusableCellWithIdentifier:ConversationListCell.cellReuseIdentifier];
    OWSAssertDebug(cell);

    ThreadViewModel *thread = [self threadViewModelForIndexPath:indexPath];

    BOOL isBlocked = [self.blocklistCache isThreadBlocked:thread.threadRecord];
    [cell configureWithThread:thread isBlocked:isBlocked];

    NSString *cellName;
    if (thread.threadRecord.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread.threadRecord;
        cellName = [NSString stringWithFormat:@"cell-group-%@", groupThread.groupModel.groupName];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread.threadRecord;
        cellName = [NSString stringWithFormat:@"cell-contact-%@", contactThread.contactAddress.stringForDisplay];
    }
    cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, cellName);

    if ([self isConversationActiveForThread:thread.threadRecord]) {
        [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    } else {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
    }

    return cell;
}

- (UITableViewCell *)cellForArchivedConversationsRow:(UITableView *)tableView
{
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kArchivedConversationsReuseIdentifier];
    OWSAssertDebug(cell);
    [OWSTableItem configureCell:cell];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }

    UIImage *disclosureImage = [UIImage imageNamed:(CurrentAppContext().isRTL ? @"NavBarBack" : @"NavBarBackRTL")];
    OWSAssertDebug(disclosureImage);
    UIImageView *disclosureImageView = [UIImageView new];
    disclosureImageView.image = [disclosureImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    disclosureImageView.tintColor = [UIColor colorWithRGBHex:0xd1d1d6];
    [disclosureImageView setContentHuggingHigh];
    [disclosureImageView setCompressionResistanceHigh];

    UILabel *label = [UILabel new];
    label.text = NSLocalizedString(@"HOME_VIEW_ARCHIVED_CONVERSATIONS", @"Label for 'archived conversations' button.");
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont ows_dynamicTypeBodyFont];
    label.textColor = Theme.primaryTextColor;

    UIStackView *stackView = [UIStackView new];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.spacing = 5;
    // If alignment isn't set, UIStackView uses the height of
    // disclosureImageView, even if label has a higher desired height.
    stackView.alignment = UIStackViewAlignmentCenter;
    [stackView addArrangedSubview:label];
    [stackView addArrangedSubview:disclosureImageView];
    [cell.contentView addSubview:stackView];
    [stackView autoCenterInSuperview];
    // Constrain to cell margins.
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeLeading relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeTrailing relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeTop];
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeBottom];

    cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"archived_conversations");

    return cell;
}

- (TSThread *)threadForIndexPath:(NSIndexPath *)indexPath
{
    return [self.threadMapping threadForIndexPath:indexPath];
}

- (void)pullToRefreshPerformed:(UIRefreshControl *)refreshControl
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"beggining refreshing.");

    [[AppEnvironment.shared.messageFetcherJob run].then(^{
        if (TSAccountManager.sharedInstance.isRegisteredPrimaryDevice) {
            return [AnyPromise promiseWithValue:nil];
        }

        return [SSKEnvironment.shared.syncManager sendAllSyncRequestMessagesWithTimeout:20];
    }).ensure(^{
        OWSLogInfo(@"ending refreshing.");
        [refreshControl endRefreshing];
    }) retainUntilComplete];
}

#pragma mark - Edit Actions

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath
{
    return;
}

- (nullable NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ConversationListViewControllerSection section = (ConversationListViewControllerSection)indexPath.section;
    switch (section) {
        case ConversationListViewControllerSectionReminders: {
            return @[];
        }
        case ConversationListViewControllerSectionConversations: {
            UITableViewRowAction *deleteAction =
                [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault
                                                   title:NSLocalizedString(@"TXT_DELETE_TITLE", nil)
                                                 handler:^(UITableViewRowAction *action, NSIndexPath *swipedIndexPath) {
                                                     [self tableViewCellTappedDelete:swipedIndexPath];
                                                 }];

            UITableViewRowAction *archiveAction;
            if (self.conversationListMode == ConversationListMode_Inbox) {
                archiveAction = [UITableViewRowAction
                    rowActionWithStyle:UITableViewRowActionStyleNormal
                                 title:NSLocalizedString(@"ARCHIVE_ACTION",
                                           @"Pressing this button moves a thread from the inbox to the archive")
                               handler:^(UITableViewRowAction *_Nonnull action, NSIndexPath *_Nonnull tappedIndexPath) {
                                   [self archiveIndexPath:tappedIndexPath];
                               }];

            } else {
                archiveAction = [UITableViewRowAction
                    rowActionWithStyle:UITableViewRowActionStyleNormal
                                 title:NSLocalizedString(@"UNARCHIVE_ACTION",
                                           @"Pressing this button moves an archived thread from the archive back to "
                                           @"the inbox")
                               handler:^(UITableViewRowAction *_Nonnull action, NSIndexPath *_Nonnull tappedIndexPath) {
                                   [self archiveIndexPath:tappedIndexPath];
                               }];
            }

            // The first action will be auto-performed for "very long swipes".
            return @[
                archiveAction,
                deleteAction,
            ];
        }
        case ConversationListViewControllerSectionArchiveButton: {
            return @[];
        }
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    ConversationListViewControllerSection section = (ConversationListViewControllerSection)indexPath.section;
    switch (section) {
        case ConversationListViewControllerSectionReminders: {
            return NO;
        }
        case ConversationListViewControllerSectionConversations: {
            return YES;
        }
        case ConversationListViewControllerSectionArchiveButton: {
            return NO;
        }
    }
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    [self scrollSearchBarToTopAnimated:NO];

    [self updateSearchResultsVisibility];

    [self ensureSearchBarCancelButton];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    [self updateSearchResultsVisibility];

    [self ensureSearchBarCancelButton];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self updateSearchResultsVisibility];

    [self ensureSearchBarCancelButton];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self updateSearchResultsVisibility];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    self.searchBar.text = nil;

    [self dismissSearchKeyboard];

    [self updateSearchResultsVisibility];

    [self ensureSearchBarCancelButton];
}

- (void)ensureSearchBarCancelButton
{
    BOOL shouldShowCancelButton = (self.searchBar.isFirstResponder || self.searchBar.text.length > 0);
    if (self.searchBar.showsCancelButton == shouldShowCancelButton) {
        return;
    }
    [self.searchBar setShowsCancelButton:shouldShowCancelButton animated:self.isViewVisible];
}

- (void)updateSearchResultsVisibility
{
    OWSAssertIsOnMainThread();

    NSString *searchText = self.searchBar.text.ows_stripped;
    self.searchResultsController.searchText = searchText;
    BOOL isSearching = searchText.length > 0;
    self.searchResultsController.view.hidden = !isSearching;

    if (isSearching) {
        [self scrollSearchBarToTopAnimated:NO];
        self.tableView.scrollEnabled = NO;
    } else {
        self.tableView.scrollEnabled = YES;
    }
}

- (void)scrollSearchBarToTopAnimated:(BOOL)isAnimated
{
    CGFloat topInset = self.topLayoutGuide.length;
    [self.tableView setContentOffset:CGPointMake(0, -topInset) animated:isAnimated];
}

- (void)dismissSearchKeyboard
{
    [self.searchBar resignFirstResponder];
    OWSAssertDebug(!self.searchBar.isFirstResponder);
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self dismissSearchKeyboard];
}

#pragma mark - ConversationSearchViewDelegate

- (void)conversationSearchViewWillBeginDragging
{
    [self dismissSearchKeyboard];
}

#pragma mark - HomeFeedTableViewCellDelegate

- (void)tableViewCellTappedDelete:(NSIndexPath *)indexPath
{
    if (indexPath.section != ConversationListViewControllerSectionConversations) {
        OWSFailDebug(@"failure: unexpected section: %lu", (unsigned long)indexPath.section);
        return;
    }

    TSThread *thread = [self threadForIndexPath:indexPath];

    __weak ConversationListViewController *weakSelf = self;
    ActionSheetController *alert = [[ActionSheetController alloc]
        initWithTitle:NSLocalizedString(@"CONVERSATION_DELETE_CONFIRMATION_ALERT_TITLE",
                          @"Title for the 'conversation delete confirmation' alert.")
              message:NSLocalizedString(@"CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGE",
                          @"Message for the 'conversation delete confirmation' alert.")];
    [alert addAction:[[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", nil)
                                                        style:ActionSheetActionStyleDestructive
                                                      handler:^(ActionSheetAction *action) {
                                                          [weakSelf deleteThread:thread];
                                                      }]];
    [alert addAction:[OWSActionSheets cancelAction]];

    [self presentActionSheet:alert];
}

- (void)deleteThread:(TSThread *)thread
{
    // If this conversation is currently selected, close it.
    if ([self.conversationSplitViewController.selectedThread.uniqueId isEqualToString:thread.uniqueId]) {
        [self.conversationSplitViewController closeSelectedConversationAnimated:YES];
    }

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        if ([thread isKindOfClass:[TSGroupThread class]]) {
            TSGroupThread *groupThread = (TSGroupThread *)thread;
            if (groupThread.isLocalUserInGroup) {
                [groupThread softDeleteThreadWithTransaction:transaction];
            } else {
                [groupThread anyRemoveWithTransaction:transaction];
                [self.databaseStorage touchThread:groupThread transaction:transaction];
            }
        } else {
            // contact thread
            [thread softDeleteThreadWithTransaction:transaction];
        }
    }];

    [self updateViewState];
}

- (void)archiveIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section != ConversationListViewControllerSectionConversations) {
        OWSFailDebug(@"failure: unexpected section: %lu", (unsigned long)indexPath.section);
        return;
    }

    TSThread *thread = [self threadForIndexPath:indexPath];

    // If this conversation is currently selected, close it.
    if ([self.conversationSplitViewController.selectedThread.uniqueId isEqualToString:thread.uniqueId]) {
        [self.conversationSplitViewController closeSelectedConversationAnimated:YES];
    }

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        switch (self.conversationListMode) {
            case ConversationListMode_Inbox:
                [thread archiveThreadWithTransaction:transaction];
                break;
            case ConversationListMode_Archive:
                [thread unarchiveThreadWithTransaction:transaction];
                break;
        }
    }];
    [self updateViewState];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSLogInfo(@"%ld %ld", (long)indexPath.row, (long)indexPath.section);

    [self dismissSearchKeyboard];

    ConversationListViewControllerSection section = (ConversationListViewControllerSection)indexPath.section;
    switch (section) {
        case ConversationListViewControllerSectionReminders: {
            break;
        }
        case ConversationListViewControllerSectionConversations: {
            TSThread *thread = [self threadForIndexPath:indexPath];
            [self presentThread:thread action:ConversationViewActionNone animated:YES];
            break;
        }
        case ConversationListViewControllerSectionArchiveButton: {
            [self showArchivedConversations];
            break;
        }
    }
}

- (void)presentThread:(TSThread *)thread action:(ConversationViewAction)action animated:(BOOL)isAnimated
{
    [BenchManager startEventWithTitle:@"Presenting Conversation"
                              eventId:[NSString stringWithFormat:@"presenting-conversation-%@", thread.uniqueId]];
    [self presentThread:thread action:action focusMessageId:nil animated:isAnimated];
}

- (void)presentThread:(TSThread *)thread
               action:(ConversationViewAction)action
       focusMessageId:(nullable NSString *)focusMessageId
             animated:(BOOL)isAnimated
{
    if (thread == nil) {
        OWSFailDebug(@"Thread unexpectedly nil");
        return;
    }

    [self.conversationSplitViewController presentThread:thread
                                                 action:action
                                         focusMessageId:focusMessageId
                                               animated:isAnimated];
}

- (BOOL)isConversationActiveForThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [self.conversationSplitViewController.selectedThread.uniqueId isEqualToString:thread.uniqueId];
}

#pragma mark - Groupings

- (void)showArchivedConversations
{
    OWSAssertDebug(self.conversationListMode == ConversationListMode_Inbox);

    // When showing archived conversations, we want to use a conventional "back" button
    // to return to the "inbox" conversation list.
    [self applyArchiveBackButton];

    // Push a separate instance of this view using "archive" mode.
    ConversationListViewController *conversationList = [ConversationListViewController new];
    conversationList.conversationListMode = ConversationListMode_Archive;
    [self showViewController:conversationList sender:self];
}

- (nullable ConversationListViewController *)presentedConversationListViewController
{
    UIViewController *_Nullable topViewController = self.navigationController.topViewController;
    if (topViewController == self) {
        return nil;
    }

    if (![topViewController isKindOfClass:[ConversationListViewController class]]) {
        return nil;
    }

    return (ConversationListViewController *)topViewController;
}

- (NSString *)currentGrouping
{
    switch (self.conversationListMode) {
        case ConversationListMode_Inbox:
            return TSInboxGroup;
        case ConversationListMode_Archive:
            return TSArchiveGroup;
    }
}

#pragma mark - Database delegates

#pragma mark GRDB Update

- (void)conversationListDatabaseSnapshotWillUpdate
{
    OWSAssertIsOnMainThread();
    [self anyUIDBWillUpdate];
}

- (void)conversationListDatabaseSnapshotDidUpdateWithUpdatedThreadIds:(NSSet<NSString *> *)updatedThreadIds
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(StorageCoordinator.dataStoreForUI == DataStoreGrdb);

    if (!self.shouldObserveDBModifications) {
        return;
    }

    [self anyUIDBDidUpdateWithUpdatedThreadIds:updatedThreadIds];
}

- (void)conversationListDatabaseSnapshotDidUpdateExternally
{
    OWSAssertIsOnMainThread();
    [self anyUIDBDidUpdateExternally];
}

- (void)conversationListDatabaseSnapshotDidReset
{
    OWSAssertIsOnMainThread();
    if (self.shouldObserveDBModifications) {
        // We don't need to do this if we're not observing db modifications since we'll
        // do it when we resume.
        [self resetMappings];
    }
}

#pragma mark YapDB Update

- (void)uiDatabaseWillUpdate:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    [self anyUIDBWillUpdate];
}

- (void)uiDatabaseDidUpdate:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(StorageCoordinator.dataStoreForUI == DataStoreYdb);

    if (!self.shouldObserveDBModifications) {
        return;
    }

    NSArray *notifications = notification.userInfo[OWSUIDatabaseConnectionNotificationsKey];
    YapDatabaseConnection *uiDatabaseConnection = self.primaryStorage.uiDatabaseConnection;
    if (![[uiDatabaseConnection ext:TSThreadDatabaseViewExtensionName] hasChangesForGroup:self.currentGrouping
                                                                          inNotifications:notifications]) {

        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            [self.threadMapping updateSwallowingErrorsWithIsViewingArchive:self.isViewingArchive
                                                               transaction:transaction];
        }];
        [self updateViewState];

        return;
    }

    NSSet<NSString *> *updatedThreadIds = [self.threadMapping updatedYapItemIdsForNotifications:notifications];
    [self anyUIDBDidUpdateWithUpdatedThreadIds:updatedThreadIds];
}

- (void)uiDatabaseDidUpdateExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    [self anyUIDBDidUpdateExternally];
}

#pragma mark AnyDB Update

- (void)anyUIDBWillUpdate
{
    OWSAssertIsOnMainThread();
    [BenchManager startEventWithTitle:@"uiDatabaseUpdate" eventId:@"uiDatabaseUpdate"];
}

- (void)anyUIDBDidUpdateWithUpdatedThreadIds:(NSSet<NSString *> *)updatedItemIds
{
    OWSAssertIsOnMainThread();

    if (updatedItemIds.count < 1) {
        // Ignoring irrelevant update.
        [self updateViewState];
        return;
    }

    __block ThreadMappingDiff *_Nullable mappingDiff;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        mappingDiff =
            [self.threadMapping updateAndCalculateDiffSwallowingErrorsWithIsViewingArchive:self.isViewingArchive
                                                                            updatedItemIds:updatedItemIds
                                                                               transaction:transaction];
    }];

    // We want this regardless of if we're currently viewing the archive.
    // So we run it before the early return
    [self updateViewState];

    if (mappingDiff == nil) {
        // Diffing failed, reload to get back to a known good state.
        [self.tableView reloadData];
        return;
    }

    if (mappingDiff.sectionChanges.count == 0 && mappingDiff.rowChanges.count == 0) {
        return;
    }

    if ([self updateHasArchivedThreadsRow]) {
        [self.tableView reloadData];
        return;
    }

    [self.tableView beginUpdates];

    OWSAssertDebug(mappingDiff.sectionChanges.count == 0);
    for (ThreadMappingRowChange *rowChange in mappingDiff.rowChanges) {
        NSString *key = rowChange.uniqueRowId;
        OWSAssertDebug(key);
        [self.threadViewModelCache removeObjectForKey:key];

        switch (rowChange.type) {
            case ThreadMappingChangeDelete: {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.oldIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case ThreadMappingChangeInsert: {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case ThreadMappingChangeMove: {
                // NOTE: we perform moves using a "delete" and "insert"
                //       rather than a "move".  This ensures that moved
                //       items are also reloaded.  This is how UICollectionView
                //       performs reloads internally.
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.oldIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case ThreadMappingChangeUpdate: {
                [self.tableView reloadRowsAtIndexPaths:@[ rowChange.oldIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
        }
    }

    [self.tableView endUpdates];
    [BenchManager completeEventWithEventId:@"uiDatabaseUpdate"];
}

- (void)anyUIDBDidUpdateExternally
{
    OWSLogVerbose(@"");
    OWSAssertIsOnMainThread();

    if (self.shouldObserveDBModifications) {
        // External database modifications can't be converted into incremental updates,
        // so rebuild everything.  This is expensive and usually isn't necessary, but
        // there's no alternative.
        //
        // We don't need to do this if we're not observing db modifications since we'll
        // do it when we resume.
        [self resetMappings];
    }
}

#pragma mark -

- (NSUInteger)numberOfInboxThreads
{
    return self.threadMapping.inboxCount;
}

- (NSUInteger)numberOfArchivedThreads
{
    return self.threadMapping.archiveCount;
}

- (void)updateViewState
{
    if (self.shouldShowFirstConversationCue) {
        [_tableView setHidden:YES];
        [self.emptyInboxView setHidden:NO];
        [self.firstConversationCueView setHidden:NO];
        [self updateFirstConversationLabel];
    } else {
        [_tableView setHidden:NO];
        [self.emptyInboxView setHidden:YES];
        [self.firstConversationCueView setHidden:YES];
    }
}

- (BOOL)shouldShowFirstConversationCue
{
    __block BOOL hasDimissedFirstConversationCue;
    __block BOOL hasSavedThread;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasDimissedFirstConversationCue = [AppPreferences hasDimissedFirstConversationCueWithTransaction:transaction];
        hasSavedThread = [SSKPreferences hasSavedThreadWithTransaction:transaction];
    }];

    return (self.conversationListMode == ConversationListMode_Inbox && self.numberOfInboxThreads == 0
        && self.numberOfArchivedThreads == 0 && !hasDimissedFirstConversationCue && !hasSavedThread);
}

// We want to delay asking for a review until an opportune time.
// If the user has *just* launched Signal they intend to do something, we don't want to interrupt them.
- (void)requestReviewIfAppropriate
{
    static NSUInteger callCount = 0;
    callCount++;
    if (self.hasEverAppeared && callCount > 25) {
        OWSLogDebug(@"requesting review");
        if (@available(iOS 10, *)) {
            // In Debug this pops up *every* time, which is helpful, but annoying.
            // In Production this will pop up at most 3 times per 365 days.
#ifndef DEBUG
            static dispatch_once_t onceToken;
            // Despite `SKStoreReviewController` docs, some people have reported seeing the "request review" prompt
            // repeatedly after first installation. Let's make sure it only happens at most once per launch.
            dispatch_once(&onceToken, ^{
                [SKStoreReviewController requestReview];
            });
#endif
        }
    } else {
        OWSLogDebug(@"not requesting review");
    }
}

#pragma mark - OWSBlockListCacheDelegate

- (void)blockListCacheDidUpdate:(OWSBlockListCache *_Nonnull)blocklistCache
{
    OWSLogVerbose(@"");
    [self reloadTableViewData];
}

#pragma mark - CameraFirstCaptureDelegate

- (void)cameraFirstCaptureSendFlowDidComplete:(CameraFirstCaptureSendFlow *)cameraFirstCaptureSendFlow
{
    [self dismissViewControllerAnimated:true completion:nil];
}

- (void)cameraFirstCaptureSendFlowDidCancel:(CameraFirstCaptureSendFlow *)cameraFirstCaptureSendFlow
{
    [self dismissViewControllerAnimated:true completion:nil];
}

@end

NS_ASSUME_NONNULL_END
