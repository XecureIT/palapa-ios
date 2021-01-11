//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactsViewHelper.h"
#import "Environment.h"
#import "UIUtil.h"
#import <ContactsUI/ContactsUI.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactsViewHelper () <OWSBlockListCacheDelegate>

// This property is a cached value that is lazy-populated.
@property (nonatomic, nullable) NSArray<Contact *> *nonSignalContacts;

@property (nonatomic) NSDictionary<NSString *, SignalAccount *> *phoneNumberSignalAccountMap;
@property (nonatomic) NSDictionary<NSUUID *, SignalAccount *> *uuidSignalAccountMap;

@property (nonatomic) NSArray<SignalAccount *> *signalAccounts;

@property (nonatomic, readonly) OWSBlockListCache *blockListCache;

@property (nonatomic) BOOL shouldNotifyDelegateOfUpdatedContacts;
@property (nonatomic, readonly) FullTextSearcher *fullTextSearcher;

@end

#pragma mark -

@implementation ContactsViewHelper

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (instancetype)initWithDelegate:(id<ContactsViewHelperDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(delegate);
    _delegate = delegate;

    _blockingManager = [OWSBlockingManager sharedManager];
    _blockListCache = [OWSBlockListCache new];
    [_blockListCache startObservingAndSyncStateWithDelegate:self];

    _fullTextSearcher = FullTextSearcher.shared;

    _contactsManager = Environment.shared.contactsManager;
    _profileManager = [OWSProfileManager sharedManager];

    // We don't want to notify the delegate in the `updateContacts`.
    [self updateContacts];
    self.shouldNotifyDelegateOfUpdatedContacts = YES;

    [self observeNotifications];

    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)signalAccountsDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateContacts];
}

#pragma mark - Contacts

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(address);

    SignalAccount *_Nullable signalAccount;

    if (address.uuid) {
        signalAccount = self.uuidSignalAccountMap[address.uuid];
    }

    if (!signalAccount && address.phoneNumber) {
        signalAccount = self.phoneNumberSignalAccountMap[address.phoneNumber];
    }

    return signalAccount;
}

- (SignalAccount *)fetchOrBuildSignalAccountForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address);

    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address];
    return (signalAccount ?: [[SignalAccount alloc] initWithSignalServiceAddress:address]);
}

- (BOOL)isSignalAccountHidden:(SignalAccount *)signalAccount
{
    OWSAssertIsOnMainThread();

    if ([self.delegate respondsToSelector:@selector(shouldHideLocalNumber)] && [self.delegate shouldHideLocalNumber] &&
        [self isCurrentUser:signalAccount]) {

        return YES;
    }

    return NO;
}

- (BOOL)isCurrentUser:(SignalAccount *)signalAccount
{
    OWSAssertIsOnMainThread();

    if (signalAccount.recipientAddress.isLocalAddress) {
        return YES;
    }

    NSString *localNumber = [TSAccountManager localNumber];
    for (PhoneNumber *phoneNumber in signalAccount.contact.parsedPhoneNumbers) {
        if ([[phoneNumber toE164] isEqualToString:localNumber]) {
            return YES;
        }
    }

    return NO;
}

- (SignalServiceAddress *)localAddress
{
    return TSAccountManager.localAddress;
}

- (BOOL)isSignalServiceAddressBlocked:(SignalServiceAddress *)address
{
    OWSAssertIsOnMainThread();

    return [self.blockListCache isAddressBlocked:address];
}

- (BOOL)isGroupIdBlocked:(NSData *)groupId
{
    OWSAssertIsOnMainThread();

    return [self.blockListCache isGroupIdBlocked:groupId];
}

- (BOOL)isThreadBlocked:(TSThread *)thread
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self isSignalServiceAddressBlocked:contactThread.contactAddress];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return [self isGroupIdBlocked:groupThread.groupModel.groupId];
    } else {
        OWSFailDebug(@"%@ failure: unexpected thread: %@", self.logTag, thread.class);
        return NO;
    }
}

- (BOOL)hasUpdatedContactsAtLeastOnce
{
    return self.contactsManager.hasLoadedContacts;
}

- (void)updateContacts
{
    OWSAssertIsOnMainThread();

    NSMutableDictionary<NSString *, SignalAccount *> *phoneNumberSignalAccountMap = [NSMutableDictionary new];
    NSMutableDictionary<NSUUID *, SignalAccount *> *uuidSignalAccountMap = [NSMutableDictionary new];
    NSMutableArray<SignalAccount *> *signalAccounts = [NSMutableArray new];
    for (SignalAccount *signalAccount in self.contactsManager.signalAccounts) {
        if (![self isSignalAccountHidden:signalAccount]) {
            if (signalAccount.recipientPhoneNumber) {
                phoneNumberSignalAccountMap[signalAccount.recipientPhoneNumber] = signalAccount;
            }
            if (signalAccount.recipientUUID) {
                uuidSignalAccountMap[signalAccount.recipientUUID] = signalAccount;
            }
            [signalAccounts addObject:signalAccount];
        }
    }
    self.phoneNumberSignalAccountMap = [phoneNumberSignalAccountMap copy];
    self.uuidSignalAccountMap = [uuidSignalAccountMap copy];
    self.signalAccounts = [signalAccounts copy];
    self.nonSignalContacts = nil;

    // Don't fire delegate "change" events during initialization.
    if (self.shouldNotifyDelegateOfUpdatedContacts) {
        [self.delegate contactsViewHelperDidUpdateContacts];
    }
}

- (NSArray<NSString *> *)searchTermsForSearchString:(NSString *)searchText
{
    return [[[searchText ows_stripped]
        componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *_Nullable searchTerm,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return searchTerm.length > 0;
        }]];
}

- (NSArray<SignalAccount *> *)signalAccountsMatchingSearchString:(NSString *)searchText
                                                     transaction:(SDSAnyReadTransaction *)transaction
{
    // Check for matches against "Note to Self".
    NSMutableArray<SignalAccount *> *signalAccountsToSearch = [self.signalAccounts mutableCopy];
    SignalAccount *selfAccount = [[SignalAccount alloc] initWithSignalServiceAddress:self.localAddress];
    [signalAccountsToSearch addObject:selfAccount];
    return [self.fullTextSearcher filterSignalAccounts:signalAccountsToSearch
                                        withSearchText:searchText
                                           transaction:transaction];
}

- (BOOL)doesContact:(Contact *)contact matchSearchTerm:(NSString *)searchTerm
{
    OWSAssertDebug(contact);
    OWSAssertDebug(searchTerm.length > 0);

    if ([contact.fullName.lowercaseString containsString:searchTerm.lowercaseString]) {
        return YES;
    }

    NSString *asPhoneNumber = [PhoneNumber removeFormattingCharacters:searchTerm];
    if (asPhoneNumber.length > 0) {
        for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
            if ([phoneNumber.toE164 containsString:asPhoneNumber]) {
                return YES;
            }
        }
    }

    return NO;
}

- (BOOL)doesContact:(Contact *)contact matchSearchTerms:(NSArray<NSString *> *)searchTerms
{
    OWSAssertDebug(contact);
    OWSAssertDebug(searchTerms.count > 0);

    for (NSString *searchTerm in searchTerms) {
        if (![self doesContact:contact matchSearchTerm:searchTerm]) {
            return NO;
        }
    }

    return YES;
}

- (NSArray<Contact *> *)nonSignalContactsMatchingSearchString:(NSString *)searchText
{
    NSArray<NSString *> *searchTerms = [self searchTermsForSearchString:searchText];

    if (searchTerms.count < 1) {
        return [NSArray new];
    }

    return [self.nonSignalContacts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Contact *contact,
                                                                   NSDictionary<NSString *, id> *_Nullable bindings) {
        return [self doesContact:contact matchSearchTerms:searchTerms];
    }]];
}

- (void)warmNonSignalContactsCacheAsync
{
    OWSAssertIsOnMainThread();
    if (self.nonSignalContacts != nil) {
        return;
    }

    NSMutableSet<Contact *> *nonSignalContactSet = [NSMutableSet new];
    __block NSArray<Contact *> *nonSignalContacts;

    [self.databaseStorage
        asyncReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            for (Contact *contact in self.contactsManager.allContactsMap.allValues) {
                NSArray<SignalRecipient *> *signalRecipients = [contact signalRecipientsWithTransaction:transaction];
                if (signalRecipients.count < 1) {
                    [nonSignalContactSet addObject:contact];
                }
            }
            nonSignalContacts = [nonSignalContactSet.allObjects
                sortedArrayUsingComparator:^NSComparisonResult(Contact *_Nonnull left, Contact *_Nonnull right) {
                    return [left.fullName compare:right.fullName];
                }];
        }
        completion:^{
            self.nonSignalContacts = nonSignalContacts;
        }];
}

- (nullable NSArray<Contact *> *)nonSignalContacts
{
    OWSAssertIsOnMainThread();

    if (!_nonSignalContacts) {
        NSMutableSet<Contact *> *nonSignalContacts = [NSMutableSet new];
        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            for (Contact *contact in self.contactsManager.allContactsMap.allValues) {
                NSArray<SignalRecipient *> *signalRecipients = [contact signalRecipientsWithTransaction:transaction];
                if (signalRecipients.count < 1) {
                    [nonSignalContacts addObject:contact];
                }
            }
        }];
        _nonSignalContacts = [nonSignalContacts.allObjects
            sortedArrayUsingComparator:^NSComparisonResult(Contact *_Nonnull left, Contact *_Nonnull right) {
                return [left.fullName compare:right.fullName];
            }];
    }

    return _nonSignalContacts;
}

#pragma mark - Editing

- (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController
{
    [ContactsViewHelper presentMissingContactAccessAlertControllerFromViewController:viewController];
}

+ (void)presentMissingContactAccessAlertControllerFromViewController:(UIViewController *)viewController
{
    ActionSheetController *alert = [[ActionSheetController alloc]
        initWithTitle:NSLocalizedString(@"EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_TITLE", comment
                                        : @"Alert title for when the user has just tried to edit a "
                                          @"contacts after declining to give Signal contacts "
                                          @"permissions")
              message:NSLocalizedString(@"EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_BODY", comment
                                        : @"Alert body for when the user has just tried to edit a "
                                          @"contacts after declining to give Signal contacts "
                                          @"permissions")];

    [alert addAction:[[ActionSheetAction alloc]
                                   initWithTitle:NSLocalizedString(@"AB_PERMISSION_MISSING_ACTION_NOT_NOW",
                                                     @"Button text to dismiss missing contacts permission alert")
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"not_now")
                                           style:ActionSheetActionStyleCancel
                                         handler:nil]];

    ActionSheetAction *_Nullable openSystemSettingsAction =
        [CurrentAppContext() openSystemSettingsActionWithCompletion:nil];
    if (openSystemSettingsAction) {
        [alert addAction:openSystemSettingsAction];
    }

    [viewController presentActionSheet:alert];
}

- (nullable CNContactViewController *)contactViewControllerForAddress:(SignalServiceAddress *)address
                                                      editImmediately:(BOOL)shouldEditImmediately
{
    return [self contactViewControllerForAddress:address
                                 editImmediately:shouldEditImmediately
                          addToExistingCnContact:nil];
}

- (nullable CNContactViewController *)contactViewControllerForAddress:(SignalServiceAddress *)address
                                                      editImmediately:(BOOL)shouldEditImmediately
                                               addToExistingCnContact:(CNContact *_Nullable)existingContact
{
    OWSAssertIsOnMainThread();

    SignalAccount *signalAccount = [self fetchSignalAccountForAddress:address];

    if (!self.contactsManager.supportsContactEditing) {
        // Should not expose UI that lets the user get here.
        OWSFailDebug(@"Contact editing not supported.");
        return nil;
    }

    if (!self.contactsManager.isSystemContactsAuthorized) {
        [self presentMissingContactAccessAlertControllerFromViewController:CurrentAppContext().frontmostViewController];
        return nil;
    }

    CNContactViewController *_Nullable contactViewController;
    CNContact *_Nullable cnContact = nil;
    if (existingContact) {
        CNMutableContact *updatedContact = [existingContact mutableCopy];
        NSMutableArray<CNLabeledValue *> *phoneNumbers
            = (updatedContact.phoneNumbers ? [updatedContact.phoneNumbers mutableCopy] : [NSMutableArray new]);
        // Only add recipientId as a phone number for the existing contact
        // if its not already present.
        BOOL hasPhoneNumber = NO;
        if (address.phoneNumber) {
            for (CNLabeledValue *existingPhoneNumber in phoneNumbers) {
                CNPhoneNumber *phoneNumber = existingPhoneNumber.value;
                if ([phoneNumber.stringValue isEqualToString:address.phoneNumber]) {
                    OWSFailDebug(
                        @"We currently only should the 'add to existing contact' UI for phone numbers that don't "
                        @"correspond to an existing user.");
                    hasPhoneNumber = YES;
                    break;
                }
            }
            if (!hasPhoneNumber) {
                CNPhoneNumber *phoneNumber = [CNPhoneNumber phoneNumberWithStringValue:address.phoneNumber];
                CNLabeledValue<CNPhoneNumber *> *labeledPhoneNumber =
                    [CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMain value:phoneNumber];
                [phoneNumbers addObject:labeledPhoneNumber];
                updatedContact.phoneNumbers = phoneNumbers;

                // When adding a phone number to an existing contact, immediately enter
                // "edit" mode.
                shouldEditImmediately = YES;
            }
            cnContact = updatedContact;
        }
    }
    if (signalAccount && !cnContact && signalAccount.contact.cnContactId != nil) {
        cnContact = [self.contactsManager cnContactWithId:signalAccount.contact.cnContactId];
    }
    if (cnContact) {
        if (shouldEditImmediately) {
            // Not actually a "new" contact, but this brings up the edit form rather than the "Read" form
            // saving our users a tap in some cases when we already know they want to edit.
            contactViewController = [CNContactViewController viewControllerForNewContact:cnContact];

            // Default title is "New Contact". We could give a more descriptive title, but anything
            // seems redundant - the context is sufficiently clear.
            contactViewController.title = @"";
        } else {
            contactViewController = [CNContactViewController viewControllerForContact:cnContact];
        }
    }

    if (!contactViewController) {
        CNMutableContact *newContact = [CNMutableContact new];
        if (address.phoneNumber) {
            CNPhoneNumber *phoneNumber = [CNPhoneNumber phoneNumberWithStringValue:address.phoneNumber];
            CNLabeledValue<CNPhoneNumber *> *labeledPhoneNumber =
                [CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMain value:phoneNumber];
            newContact.phoneNumbers = @[ labeledPhoneNumber ];
        }

        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            newContact.givenName = [self.profileManager profileNameForAddress:address transaction:transaction];
        }];

        contactViewController = [CNContactViewController viewControllerForNewContact:newContact];
    }

    contactViewController.allowsActions = NO;
    contactViewController.allowsEditing = YES;
    contactViewController.edgesForExtendedLayout = UIRectEdgeNone;
    contactViewController.view.backgroundColor = Theme.backgroundColor;

    return contactViewController;
}

- (void)blockListCacheDidUpdate:(OWSBlockListCache *)blocklistCache
{
    OWSAssertIsOnMainThread();
    [self updateContacts];
}

@end

NS_ASSUME_NONNULL_END
