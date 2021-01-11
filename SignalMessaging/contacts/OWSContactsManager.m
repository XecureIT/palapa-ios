//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsManager.h"
#import "Environment.h"
#import "OWSFormat.h"
#import "OWSProfileManager.h"
#import "ViewControllerUtils.h"
#import <Contacts/Contacts.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/iOSVersions.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSContactsManagerSignalAccountsDidChangeNotification
    = @"OWSContactsManagerSignalAccountsDidChangeNotification";

NSString *const OWSContactsManagerCollection = @"OWSContactsManagerCollection";
NSString *const OWSContactsManagerKeyLastKnownContactPhoneNumbers
    = @"OWSContactsManagerKeyLastKnownContactPhoneNumbers";
NSString *const OWSContactsManagerKeyNextFullIntersectionDate = @"OWSContactsManagerKeyNextFullIntersectionDate2";

@interface OWSContactsManager () <SystemContactsFetcherDelegate>

@property (nonatomic) BOOL isContactsUpdateInFlight;
// This reflects the contents of the device phone book and includes
// contacts that do not correspond to any signal account.
@property (atomic) NSArray<Contact *> *allContacts;
@property (atomic) NSDictionary<NSString *, Contact *> *allContactsMap;
@property (atomic) NSArray<SignalAccount *> *signalAccounts;
@property (atomic) NSDictionary<NSString *, SignalAccount *> *phoneNumberSignalAccountMap;
@property (atomic) NSDictionary<NSUUID *, SignalAccount *> *uuidSignalAccountMap;
@property (nonatomic, readonly) SystemContactsFetcher *systemContactsFetcher;
@property (nonatomic, readonly) AnySignalAccountFinder *accountFinder;
@property (nonatomic, readonly) NSCache<NSString *, CNContact *> *cnContactCache;
@property (nonatomic, readonly) NSCache<NSString *, UIImage *> *cnContactAvatarCache;
@property (nonatomic, readonly) NSCache<SignalServiceAddress *, NSString *> *colorNameCache;
@property (atomic) BOOL isSetup;

@end

#pragma mark -

@implementation OWSContactsManager

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (OWSProfileManager *)profileManager
{
    return OWSProfileManager.sharedManager;
}

#pragma mark -

- (id)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:OWSContactsManagerCollection];

    // TODO: We need to configure the limits of this cache.
    _avatarCache = [ImageCache new];
    _colorNameCache = [NSCache new];

    _accountFinder = [AnySignalAccountFinder new];

    _allContacts = @[];
    _allContactsMap = @{};
    _phoneNumberSignalAccountMap = @{};
    _uuidSignalAccountMap = @{};
    _signalAccounts = @[];
    _systemContactsFetcher = [SystemContactsFetcher new];
    _systemContactsFetcher.delegate = self;
    _cnContactCache = [NSCache new];
    _cnContactCache.countLimit = 50;
    _cnContactAvatarCache = [NSCache new];
    _cnContactAvatarCache.countLimit = 25;

    OWSSingletonAssert();

    [AppReadiness runNowOrWhenAppWillBecomeReady:^{
        [self setup];
        
        [self startObserving];
    }];

    return self;
}

- (void)setup {
    __block NSMutableArray<SignalAccount *> *signalAccounts;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSUInteger signalAccountCount = [SignalAccount anyCountWithTransaction:transaction];
        OWSLogInfo(@"loading %lu signal accounts from cache.", (unsigned long)signalAccountCount);

        signalAccounts = [[NSMutableArray alloc] initWithCapacity:signalAccountCount];

        [SignalAccount anyEnumerateWithTransaction:transaction
                                             block:^(SignalAccount *signalAccount, BOOL *stop) {
                                                 [signalAccounts addObject:signalAccount];
                                             }];
    }];
    [self updateSignalAccounts:signalAccounts shouldSetHasLoadedContacts:NO];
}

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t _serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serialQueue = dispatch_queue_create("org.whispersystems.contacts.buildSignalAccount", DISPATCH_QUEUE_SERIAL);
    });

    return _serialQueue;
}

#pragma mark - System Contact Fetching

// Request contacts access if you haven't asked recently.
- (void)requestSystemContactsOnce
{
    [self requestSystemContactsOnceWithCompletion:nil];
}

- (void)requestSystemContactsOnceWithCompletion:(void (^_Nullable)(NSError *_Nullable error))completion
{
    [self.systemContactsFetcher requestOnceWithCompletion:completion];
}

- (void)fetchSystemContactsOnceIfAlreadyAuthorized
{
    [self.systemContactsFetcher fetchOnceIfAlreadyAuthorized];
}

- (AnyPromise *)userRequestedSystemContactsRefresh
{
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [self.systemContactsFetcher userRequestedRefreshWithCompletion:^(NSError *error){
            if (error) {
                OWSLogError(@"refreshing contacts failed with error: %@", error);
            }
            resolve(error ?: @(1));
        }];
    }];
}

- (BOOL)isSystemContactsAuthorized
{
    return self.systemContactsFetcher.isAuthorized;
}

- (BOOL)isSystemContactsDenied
{
    return self.systemContactsFetcher.isDenied;
}

- (BOOL)systemContactsHaveBeenRequestedAtLeastOnce
{
    return self.systemContactsFetcher.systemContactsHaveBeenRequestedAtLeastOnce;
}

- (BOOL)supportsContactEditing
{
    return self.systemContactsFetcher.supportsContactEditing;
}

#pragma mark - CNContacts

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId
{
    OWSAssertDebug(self.cnContactCache);

    if (!contactId) {
        return nil;
    }

    CNContact *_Nullable cnContact;
    @synchronized(self.cnContactCache) {
        cnContact = [self.cnContactCache objectForKey:contactId];
        if (!cnContact) {
            cnContact = [self.systemContactsFetcher fetchCNContactWithContactId:contactId];
            if (cnContact) {
                [self.cnContactCache setObject:cnContact forKey:contactId];
            }
        }
    }

    return cnContact;
}

- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId
{
    // Don't bother to cache avatar data.
    CNContact *_Nullable cnContact = [self cnContactWithId:contactId];
    return [Contact avatarDataForCNContact:cnContact];
}

- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId
{
    OWSAssertDebug(self.cnContactAvatarCache);

    if (!contactId) {
        return nil;
    }

    UIImage *_Nullable avatarImage;
    @synchronized(self.cnContactAvatarCache) {
        avatarImage = [self.cnContactAvatarCache objectForKey:contactId];
        if (!avatarImage) {
            NSData *_Nullable avatarData = [self avatarDataForCNContactId:contactId];
            if (avatarData && [avatarData ows_isValidImage]) {
                avatarImage = [UIImage imageWithData:avatarData];
            }
            if (avatarImage) {
                [self.cnContactAvatarCache setObject:avatarImage forKey:contactId];
            }
        }
    }

    return avatarImage;
}

#pragma mark - SystemContactsFetcherDelegate

- (void)systemContactsFetcher:(SystemContactsFetcher *)systemsContactsFetcher
              updatedContacts:(NSArray<Contact *> *)contacts
                isUserRequested:(BOOL)isUserRequested
{
    BOOL shouldClearStaleCache;
    // On iOS 11.2, only clear the contacts cache if the fetch was initiated by the user.
    // iOS 11.2 rarely returns partial fetches and we use the cache to prevent contacts from
    // periodically disappearing from the UI.
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 2) && !SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 3)) {
        shouldClearStaleCache = isUserRequested;
    } else {
        shouldClearStaleCache = YES;
    }
    [self updateWithContacts:contacts
                      didLoad:YES
              isUserRequested:isUserRequested
        shouldClearStaleCache:shouldClearStaleCache];
}

- (void)systemContactsFetcher:(SystemContactsFetcher *)systemContactsFetcher
       hasAuthorizationStatus:(enum ContactStoreAuthorizationStatus)authorizationStatus
{
    if (authorizationStatus == ContactStoreAuthorizationStatusRestricted
        || authorizationStatus == ContactStoreAuthorizationStatusDenied) {
        // Clear the contacts cache if access to the system contacts is revoked.
        [self updateWithContacts:@[] didLoad:NO isUserRequested:NO shouldClearStaleCache:YES];
    }
}

#pragma mark - Intersection

- (NSSet<NSString *> *)phoneNumbersForIntersectionWithContacts:(NSArray<Contact *> *)contacts
{
    OWSAssertDebug(contacts);

    NSMutableSet<NSString *> *phoneNumbers = [NSMutableSet set];

    for (Contact *contact in contacts) {
        for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
            [phoneNumbers addObject:phoneNumber.toE164];
        }
    }

    return phoneNumbers;
}

- (void)intersectContacts:(NSArray<Contact *> *)contacts
          isUserRequested:(BOOL)isUserRequested
               completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssertDebug(contacts);
    OWSAssertDebug(completion);
    OWSAssertIsOnMainThread();


    dispatch_async(self.serialQueue, ^{
        __block BOOL isFullIntersection = YES;
        __block BOOL isRegularlyScheduledRun = NO;
        __block NSSet<NSString *> *allContactPhoneNumbers;
        __block NSSet<NSString *> *phoneNumbersForIntersection;
        __block NSMutableSet<SignalRecipient *> *existingRegisteredRecipients = [NSMutableSet new];
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            // Contact updates initiated by the user should always do a full intersection.
            if (!isUserRequested) {
                NSDate *_Nullable nextFullIntersectionDate =
                    [self.keyValueStore getDate:OWSContactsManagerKeyNextFullIntersectionDate transaction:transaction];
                if (nextFullIntersectionDate && [nextFullIntersectionDate isAfterNow]) {
                    isFullIntersection = NO;
                } else {
                    isRegularlyScheduledRun = YES;
                }
            }

            [SignalRecipient anyEnumerateWithTransaction:transaction
                                                   block:^(SignalRecipient *signalRecipient, BOOL *stop) {
                                                       if (signalRecipient.devices.count > 0) {
                                                           [existingRegisteredRecipients addObject:signalRecipient];
                                                       }
                                                   }];

            allContactPhoneNumbers = [self phoneNumbersForIntersectionWithContacts:contacts];
            phoneNumbersForIntersection = allContactPhoneNumbers;

            if (!isFullIntersection) {
                // Do a "delta" intersection instead of a "full" intersection:
                // only intersect new contacts which were not in the last successful
                // "full" intersection.
                NSSet<NSString *> *_Nullable lastKnownContactPhoneNumbers =
                    [self.keyValueStore getObject:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                      transaction:transaction];
                if (lastKnownContactPhoneNumbers) {
                    // Do a "delta" sync which only intersects phone numbers not included
                    // in the last full intersection.
                    NSMutableSet<NSString *> *newPhoneNumbers = [allContactPhoneNumbers mutableCopy];
                    [newPhoneNumbers minusSet:lastKnownContactPhoneNumbers];
                    phoneNumbersForIntersection = newPhoneNumbers;
                } else {
                    // Without a list of "last known" contact phone numbers, we'll have to do a full intersection.
                    isFullIntersection = YES;
                }
            }
        }];
        OWSAssertDebug(phoneNumbersForIntersection);

        if (phoneNumbersForIntersection.count < 1) {
            OWSLogInfo(@"Skipping intersection; no contacts to intersect.");
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(nil);
            });
            return;
        } else if (isFullIntersection) {
            OWSLogInfo(@"Doing full intersection with %zu contacts.", phoneNumbersForIntersection.count);
        } else {
            OWSLogInfo(@"Doing delta intersection with %zu contacts.", phoneNumbersForIntersection.count);
        }

        [self intersectContacts:phoneNumbersForIntersection
            retryDelaySeconds:1.0
            success:^(NSSet<SignalRecipient *> *registeredRecipients) {
                if (isRegularlyScheduledRun) {
                    NSMutableSet<SignalRecipient *> *newSignalRecipients = [registeredRecipients mutableCopy];
                    [newSignalRecipients minusSet:existingRegisteredRecipients];

                    if (newSignalRecipients.count == 0) {
                        OWSLogInfo(@"No new recipients.");
                    } else {
                        __block NSSet<NSString *> *_Nullable lastKnownContactPhoneNumbers;
                        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                            lastKnownContactPhoneNumbers =
                                [self.keyValueStore getObject:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                                  transaction:transaction];
                        }];

                        if (lastKnownContactPhoneNumbers != nil && lastKnownContactPhoneNumbers.count > 0) {
                            [OWSNewAccountDiscovery.shared discoveredNewRecipients:newSignalRecipients];
                        } else {
                            OWSLogInfo(@"skipping new recipient notification for first successful contact sync.");
                        }
                    }
                }

                [self markIntersectionAsComplete:allContactPhoneNumbers isFullIntersection:isFullIntersection];

                completion(nil);
            }
            failure:^(NSError *error) {
                completion(error);
            }];
    });
}

- (void)markIntersectionAsComplete:(NSSet<NSString *> *)phoneNumbersForIntersection
                isFullIntersection:(BOOL)isFullIntersection
{
    OWSAssertDebug(phoneNumbersForIntersection.count > 0);

    dispatch_async(self.serialQueue, ^{
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            if (isFullIntersection) {
                // replace last known numbers
                [self.keyValueStore setObject:phoneNumbersForIntersection
                                          key:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                  transaction:transaction];

                const NSUInteger contactCount = phoneNumbersForIntersection.count;

                const NSUInteger minIntersectionsPerDay = 1;
                const NSUInteger maxIntersectionsPerDay = 4;
                // Try to target half the known limit, reserving some capacity for manual refreshes
                // and manual lookup-by-phonenumber.
                const NSUInteger maxContactsPerDay = 10000;
                NSUInteger fullIntersectionsPerDay;
                if (contactCount > 0) {
                    fullIntersectionsPerDay = maxContactsPerDay / contactCount;
                    fullIntersectionsPerDay = MAX(minIntersectionsPerDay, fullIntersectionsPerDay);
                    fullIntersectionsPerDay = MIN(maxIntersectionsPerDay, fullIntersectionsPerDay);
                } else {
                    fullIntersectionsPerDay = maxIntersectionsPerDay;
                }
                const NSTimeInterval nextFullIntersectionInterval = kDayInterval / fullIntersectionsPerDay;

                NSDate *nextFullIntersectionDate = [NSDate dateWithTimeIntervalSinceNow:nextFullIntersectionInterval];
                OWSLogDebug(@"contactCount: %lu, fullIntersectionsPerDay: %lu, nextFullIntersectionInterval: %lu, "
                            @"currentDate: %@, nextFullIntersectionDate: %@",
                    (unsigned long)contactCount,
                    (unsigned long)fullIntersectionsPerDay,
                    (unsigned long)nextFullIntersectionInterval,
                    [NSDate new],
                    nextFullIntersectionDate);

                [self.keyValueStore setDate:nextFullIntersectionDate
                                        key:OWSContactsManagerKeyNextFullIntersectionDate
                                transaction:transaction];
            } else {
                NSSet<NSString *> *_Nullable lastKnownContactPhoneNumbers =
                    [self.keyValueStore getObject:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                      transaction:transaction];

                // If a user has a "flaky" address book, perhaps a network linked directory that
                // goes in and out of existence, we could get thrashing between what the last
                // known set is, causing us to re-intersect contacts many times within the debounce
                // interval. So while we're doing incremental intersections, we *accumulate*,
                // rather than replace the set of recently intersected contacts.
                if ([lastKnownContactPhoneNumbers isKindOfClass:NSSet.class]) {
                    NSSet<NSString *> *_Nullable accumulatedSet =
                        [lastKnownContactPhoneNumbers setByAddingObjectsFromSet:phoneNumbersForIntersection];

                    // replace last known numbers
                    [self.keyValueStore setObject:accumulatedSet
                                              key:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                      transaction:transaction];
                } else {
                    // replace last known numbers
                    [self.keyValueStore setObject:phoneNumbersForIntersection
                                              key:OWSContactsManagerKeyLastKnownContactPhoneNumbers
                                      transaction:transaction];
                }
            }
        }];
    });
}

- (void)intersectContacts:(NSSet<NSString *> *)phoneNumbers
        retryDelaySeconds:(double)retryDelaySeconds
                  success:(void (^)(NSSet<SignalRecipient *> *))successParameter
                  failure:(void (^)(NSError *))failureParameter
{
    OWSAssertDebug(phoneNumbers.count > 0);
    OWSAssertDebug(retryDelaySeconds > 0);
    OWSAssertDebug(successParameter);
    OWSAssertDebug(failureParameter);

    void (^success)(NSArray<SignalRecipient *> *) = ^(NSArray<SignalRecipient *> *registeredRecipients) {
        OWSLogInfo(@"Successfully intersected contacts.");
        successParameter([NSSet setWithArray:registeredRecipients]);
    };
    void (^failure)(NSError *) = ^(NSError *error) {
        if ([error.domain isEqualToString:OWSSignalServiceKitErrorDomain]
            && error.code == OWSErrorCodeContactsUpdaterRateLimit) {
            OWSLogError(@"Contact intersection hit rate limit with error: %@", error);
            failureParameter(error);
            return;
        }

        OWSLogWarn(@"Failed to intersect contacts with error: %@. Rescheduling", error);

        // Retry with exponential backoff.
        //
        // TODO: Abort if another contact intersection succeeds in the meantime.
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retryDelaySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self intersectContacts:phoneNumbers
                      retryDelaySeconds:retryDelaySeconds * 2.0
                                success:successParameter
                                failure:failureParameter];
            });
    };
    [[ContactsUpdater sharedUpdater] lookupIdentifiers:phoneNumbers.allObjects success:success failure:failure];
}

- (void)startObserving
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileWillChange:)
                                                 name:kNSNotificationName_OtherUsersProfileWillChange
                                               object:nil];
}

- (void)otherUsersProfileWillChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        SignalServiceAddress *address = notification.userInfo[kNSNotificationKey_ProfileAddress];
        OWSAssertDebug(address.isValid);

        [self.avatarCache removeAllImagesForKey:address.stringForDisplay];
    }];
}

- (void)updateWithContacts:(NSArray<Contact *> *)contacts
                   didLoad:(BOOL)didLoad
           isUserRequested:(BOOL)isUserRequested
     shouldClearStaleCache:(BOOL)shouldClearStaleCache
{
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary<NSString *, Contact *> *allContactsMap = [NSMutableDictionary new];
        for (Contact *contact in contacts) {
            for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
                NSString *phoneNumberE164 = phoneNumber.toE164;
                if (phoneNumberE164.length > 0) {
                    allContactsMap[phoneNumberE164] = contact;
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.allContacts = contacts;
            self.allContactsMap = [allContactsMap copy];
            [self.cnContactCache removeAllObjects];
            [self.cnContactAvatarCache removeAllObjects];

            [self.avatarCache removeAllImages];

            [self intersectContacts:contacts
                    isUserRequested:isUserRequested
                         completion:^(NSError *_Nullable error) {
                             // TODO: Should we do this on error?
                             [self buildSignalAccountsAndClearStaleCache:shouldClearStaleCache didLoad:didLoad];
                         }];
        });
    });
}

- (void)buildSignalAccountsAndClearStaleCache:(BOOL)shouldClearStaleCache didLoad:(BOOL)didLoad
{
    dispatch_async(self.serialQueue, ^{
        NSMutableArray<SignalAccount *> *systemContactsSignalAccounts = [NSMutableArray new];
        NSArray<Contact *> *contacts = self.allContacts;

        // We use a transaction only to load the SignalRecipients for each contact,
        // in order to avoid database deadlock.
        NSMutableDictionary<NSString *, NSArray<SignalRecipient *> *> *contactIdToSignalRecipientsMap =
            [NSMutableDictionary new];
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            for (Contact *contact in contacts) {
                NSArray<SignalRecipient *> *signalRecipients = [contact signalRecipientsWithTransaction:transaction];
                contactIdToSignalRecipientsMap[contact.uniqueId] = signalRecipients;
            }
        }];

        NSMutableSet<SignalServiceAddress *> *seenAddresses = [NSMutableSet new];
        for (Contact *contact in contacts) {
            NSArray<SignalRecipient *> *signalRecipients = contactIdToSignalRecipientsMap[contact.uniqueId];
            for (SignalRecipient *signalRecipient in [signalRecipients sortedArrayUsingSelector:@selector((compare:))]) {
                if ([seenAddresses containsObject:signalRecipient.address]) {
                    OWSLogDebug(@"Ignoring duplicate contact: %@, %@", signalRecipient.address, contact.fullName);
                    continue;
                }
                [seenAddresses addObject:signalRecipient.address];

                SignalAccount *signalAccount = [[SignalAccount alloc] initWithSignalRecipient:signalRecipient];
                signalAccount.contact = contact;
                if (signalRecipients.count > 1) {
                    signalAccount.multipleAccountLabelText =
                        [[self class] accountLabelForContact:contact address:signalRecipient.address];
                }
                [signalAccount tryToCacheContactAvatarData];
                [systemContactsSignalAccounts addObject:signalAccount];
            }
        }

        NSMutableArray<SignalAccount *> *persistedSignalAccounts = [NSMutableArray new];
        NSMutableDictionary<SignalServiceAddress *, SignalAccount *> *persistedSignalAccountMap =
            [NSMutableDictionary new];
        NSMutableDictionary<SignalServiceAddress *, SignalAccount *> *signalAccountsToKeep = [NSMutableDictionary new];
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            [SignalAccount
                anyEnumerateWithTransaction:transaction
                                      block:^(SignalAccount *signalAccount, BOOL *stop) {
                                          persistedSignalAccountMap[signalAccount.recipientAddress] = signalAccount;
                                          [persistedSignalAccounts addObject:signalAccount];
                                          if (signalAccount.contact.isFromContactSync) {
                                              signalAccountsToKeep[signalAccount.recipientAddress] = signalAccount;
                                          }
                                      }];
        }];

        NSMutableArray<SignalAccount *> *signalAccountsToUpsert = [NSMutableArray new];
        for (SignalAccount *signalAccount in systemContactsSignalAccounts) {
            if (signalAccountsToKeep[signalAccount.recipientAddress] != nil
                && !signalAccountsToKeep[signalAccount.recipientAddress].contact.isFromContactSync) {
                OWSFailDebug(@"Ignoring redundant signal account: %@", signalAccount.recipientAddress);
                continue;
            }

            SignalAccount *_Nullable persistedSignalAccount = persistedSignalAccountMap[signalAccount.recipientAddress];

            if (persistedSignalAccount == nil) {
                // new Signal Account
                signalAccountsToKeep[signalAccount.recipientAddress] = signalAccount;
                [signalAccountsToUpsert addObject:signalAccount];
                continue;
            }

            if ([persistedSignalAccount hasSameContent:signalAccount]) {
                // Same value, no need to save.
                signalAccountsToKeep[signalAccount.recipientAddress] = persistedSignalAccount;
                continue;
            }

            // value changed, save account

            if (persistedSignalAccount.contact.isFromContactSync) {
                OWSLogInfo(@"replacing SignalAccount from synced contact with SignalAccount from system contacts");
            }

            signalAccountsToKeep[signalAccount.recipientAddress] = signalAccount;
            [signalAccountsToUpsert addObject:signalAccount];
        }

        // Clean up orphans.
        NSMutableArray<SignalAccount *> *signalAccountsToRemove = [NSMutableArray new];
        for (SignalAccount *signalAccount in persistedSignalAccounts) {
            if (signalAccount == signalAccountsToKeep[signalAccount.recipientAddress]) {
                continue;
            }

            // In theory we want to remove SignalAccounts if the user deletes the corresponding system contact.
            // However, as of iOS 11.2 CNContactStore occasionally gives us only a subset of the system contacts.
            // Because of that, it's not safe to clear orphaned accounts.
            // Because we still want to give users a way to clear their stale accounts, if they pull-to-refresh
            // their contacts we'll clear the cached ones.
            // RADAR: https://bugreport.apple.com/web/?problemID=36082946
            BOOL isOrphan = signalAccountsToKeep[signalAccount.recipientAddress] == nil;
            if (isOrphan && !shouldClearStaleCache) {
                OWSLogVerbose(@"Ensuring old SignalAccount is not inadvertently lost: %@", signalAccount);
                // Make note that we're retaining this orphan; otherwise we could
                // retain multiple orphans for a given recipient.
                signalAccountsToKeep[signalAccount.recipientAddress] = signalAccount;
                continue;
            } else {
                // Always cleanup instances that have been replaced by another instance.
            }

            [signalAccountsToRemove addObject:signalAccount];
        }

        // Update cached SignalAccounts on disk
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            if (signalAccountsToUpsert.count > 0) {
                OWSLogInfo(@"Saving %lu SignalAccounts", (unsigned long)signalAccountsToUpsert.count);
                for (SignalAccount *signalAccount in signalAccountsToUpsert) {
                    OWSLogVerbose(@"Saving SignalAccount: %@", signalAccount);
                    [signalAccount anyUpsertWithTransaction:transaction];
                }
            }

            if (signalAccountsToRemove.count > 0) {
                OWSLogInfo(@"Removing %lu old SignalAccounts.", (unsigned long)signalAccountsToRemove.count);
                for (SignalAccount *signalAccount in signalAccountsToRemove) {
                    OWSLogVerbose(@"Removing old SignalAccount: %@", signalAccount);
                    [signalAccount anyRemoveWithTransaction:transaction];
                }
            }

            OWSLogInfo(
                @"SignalAccount cache size: %lu.", (unsigned long)[SignalAccount anyCountWithTransaction:transaction]);
        }];

        // Add system contacts to the profile whitelist immediately
        // so that they do not see the "message request" UI.
        [self.profileManager addUsersToProfileWhitelist:seenAddresses.allObjects];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateSignalAccounts:signalAccountsToKeep.allValues shouldSetHasLoadedContacts:didLoad];
        });
    });
}

- (void)updateSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts
    shouldSetHasLoadedContacts:(BOOL)shouldSetHasLoadedContacts
{
    OWSAssertIsOnMainThread();

    if ([signalAccounts isEqual:self.signalAccounts]) {
        OWSLogDebug(@"SignalAccounts unchanged.");
        self.isSetup = YES;
        return;
    }

    if (shouldSetHasLoadedContacts) {
        _hasLoadedContacts = YES;
    }

    NSMutableArray<SignalServiceAddress *> *allAddresses = [NSMutableArray new];
    NSMutableDictionary<NSString *, SignalAccount *> *phoneNumberSignalAccountMap = [NSMutableDictionary new];
    NSMutableDictionary<NSUUID *, SignalAccount *> *uuidSignalAccountMap = [NSMutableDictionary new];
    for (SignalAccount *signalAccount in signalAccounts) {
        if (signalAccount.recipientPhoneNumber) {
            phoneNumberSignalAccountMap[signalAccount.recipientPhoneNumber] = signalAccount;
        }
        if (signalAccount.recipientUUID) {
            uuidSignalAccountMap[signalAccount.recipientUUID] = signalAccount;
        }
        [allAddresses addObject:signalAccount.recipientAddress];
    }

    self.phoneNumberSignalAccountMap = [phoneNumberSignalAccountMap copy];
    self.uuidSignalAccountMap = [uuidSignalAccountMap copy];

    self.signalAccounts = [signalAccounts sortedArrayUsingComparator:self.signalAccountComparator];

    [self.profileManager setContactAddresses:allAddresses];

    self.isSetup = YES;

    [[NSNotificationCenter defaultCenter]
        postNotificationNameAsync:OWSContactsManagerSignalAccountsDidChangeNotification
                           object:nil];
}

- (nullable NSString *)cachedContactNameForAddress:(SignalServiceAddress *)address
{
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address];
    return [self cachedContactNameForAddress:address signalAccount:signalAccount];
}

- (nullable NSString *)cachedContactNameForAddress:(SignalServiceAddress *)address
                                       transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address);
    OWSAssertDebug(transaction);

    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
    return [self cachedContactNameForAddress:address signalAccount:signalAccount];
}

- (nullable NSString *)cachedContactNameForAddress:(SignalServiceAddress *)address
                                     signalAccount:(nullable SignalAccount *)signalAccount
{
    OWSAssertDebug(address);

    if (!signalAccount) {
        // search system contacts for no-longer-registered signal users, for which there will be no SignalAccount
        NSString *_Nullable phoneNumber = [self phoneNumberForAddress:address];
        Contact *_Nullable nonSignalContact = self.allContactsMap[phoneNumber];
        if (!nonSignalContact) {
            return nil;
        }
        return nonSignalContact.fullName;
    }

    NSString *fullName = signalAccount.contactFullName;
    if (fullName.length == 0) {
        return nil;
    }

    NSString *multipleAccountLabelText = signalAccount.multipleAccountLabelText;
    if (multipleAccountLabelText.length == 0) {
        return fullName;
    }

    return [NSString stringWithFormat:@"%@ (%@)", fullName, multipleAccountLabelText];
}

- (nullable NSString *)phoneNumberForAddress:(SignalServiceAddress *)address
{
    if (address.phoneNumber != nil) {
        return address.phoneNumber;
    }

    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address];
    return signalAccount.recipientPhoneNumber;
}

- (nullable NSString *)phoneNumberForAddress:(SignalServiceAddress *)address
                                 transaction:(SDSAnyReadTransaction *)transaction
{
    if (address.phoneNumber != nil) {
        return address.phoneNumber;
    }

    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
    return signalAccount.recipientPhoneNumber;
}

#pragma mark - View Helpers

// TODO move into Contact class.
+ (NSString *)accountLabelForContact:(Contact *)contact address:(SignalServiceAddress *)address
{
    OWSAssertDebug(contact);
    OWSAssertDebug(address.isValid);
    OWSAssertDebug([contact.registeredAddresses containsObject:address]);

    if (contact.registeredAddresses.count <= 1) {
        return nil;
    }

    // 1. Find the address type of this account.
    NSString *addressLabel = [contact nameForAddress:address];

    // 2. Find all addresses for this contact of the same type.
    NSMutableArray<SignalServiceAddress *> *addressesWithTheSameName = [NSMutableArray new];
    for (SignalServiceAddress *registeredAddress in contact.registeredAddresses) {
        if ([addressLabel isEqualToString:[contact nameForAddress:registeredAddress]]) {
            [addressesWithTheSameName addObject:registeredAddress];
        }
    }

    OWSAssertDebug([addressesWithTheSameName containsObject:address]);
    if (addressesWithTheSameName.count > 1) {
        NSUInteger index =
            [[addressesWithTheSameName sortedArrayUsingSelector:@selector((compare:))] indexOfObject:address];
        NSString *indexText = [OWSFormat formatInt:(int)index + 1];
        addressLabel =
            [NSString stringWithFormat:NSLocalizedString(@"PHONE_NUMBER_TYPE_AND_INDEX_NAME_FORMAT",
                                           @"Format for phone number label with an index. Embeds {{Phone number label "
                                           @"(e.g. 'home')}} and {{index, e.g. 2}}."),
                      addressLabel,
                      indexText];
    }

    return addressLabel.filterStringForDisplay;
}

- (void)clearColorNameCache
{
    [self.colorNameCache removeAllObjects];
}

- (ConversationColorName)conversationColorNameForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();

    _Nullable ConversationColorName cachedColorName = [self.colorNameCache objectForKey:address];
    if (cachedColorName != nil) {
        return cachedColorName;
    }

    ConversationColorName colorName = [TSContactThread conversationColorNameForContactAddress:address
                                                                                  transaction:transaction];
    [self.colorNameCache setObject:colorName forKey:address];

    return colorName;
}

- (BOOL)phoneNumber:(PhoneNumber *)phoneNumber1 matchesNumber:(PhoneNumber *)phoneNumber2
{
    return [phoneNumber1.toE164 isEqualToString:phoneNumber2.toE164];
}

#pragma mark - Whisper User Management

- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber
{
    OWSAssertDebug(phoneNumber.length > 0);

    return self.allContactsMap[phoneNumber] != nil;
}

- (BOOL)isSystemContactWithAddress:(SignalServiceAddress *)address
{
    NSString *phoneNumber = address.phoneNumber;
    if (phoneNumber.length == 0) {
        return NO;
    }
    return [self isSystemContactWithPhoneNumber:phoneNumber];
}

- (BOOL)isSystemContactWithSignalAccount:(NSString *)phoneNumber
{
    OWSAssertDebug(phoneNumber.length > 0);

    return [self hasSignalAccountForAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
}

- (BOOL)hasNameInSystemContactsForAddress:(SignalServiceAddress *)address
{
    return [self cachedContactNameForAddress:address].length > 0;
}

- (NSString *)displayNameForThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    if ([thread isKindOfClass:TSContactThread.class]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self displayNameForAddress:contactThread.contactAddress transaction:transaction];
    } else if ([thread isKindOfClass:TSGroupThread.class]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return groupThread.groupNameOrDefault;
    } else {
        OWSFailDebug(@"unexpected thread: %@", thread);
        return @"";
    }
}

- (NSString *)displayNameForThreadWithSneakyTransaction:(TSThread *)thread
{
    if ([thread isKindOfClass:TSContactThread.class]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        __block NSString *name;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            name = [self displayNameForAddress:contactThread.contactAddress transaction:transaction];
        }];
        return name;
    } else if ([thread isKindOfClass:TSGroupThread.class]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return groupThread.groupNameOrDefault;
    } else {
        OWSFailDebug(@"unexpected thread: %@", thread);
        return @"";
    }
}

- (NSString *)unknownContactName
{
    return NSLocalizedString(
        @"UNKNOWN_CONTACT_NAME", @"Displayed if for some reason we can't determine a contacts phone number *or* name");
}

- (nullable NSString *)nameFromSystemContactsForAddress:(SignalServiceAddress *)address
{
    return [self cachedContactNameForAddress:address];
}

- (NSString *)displayNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    // Prefer a saved name from system contacts, if available
    NSString *_Nullable savedContactName = [self cachedContactNameForAddress:address transaction:transaction];
    if (savedContactName.length > 0) {
        return savedContactName;
    }

    NSString *_Nullable phoneNumber = [self phoneNumberForAddress:address transaction:transaction];
    if (phoneNumber) {
        phoneNumber = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:phoneNumber];
    }

    NSString *_Nullable profileName = [self.profileManager profileNameForAddress:address transaction:transaction];

    // We only include the profile name in the display name if the feature is enabled.
    if (SSKFeatureFlags.profileDisplayChanges && profileName.length > 0) {
        return profileName;
    }

    NSString *_Nullable username = [self.profileManager usernameForAddress:address transaction:transaction];
    if (username) {
        username = [CommonFormats formatUsername:username];
    }

    // else fall back to phone number or UUID
    return phoneNumber ?: username ?: address.stringForDisplay;
}

- (NSString *)displayNameForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    __block NSString *displayName;

    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        displayName = [self displayNameForAddress:address transaction:transaction];
    }];

    return displayName;
}

- (NSString *_Nonnull)displayNameForSignalAccount:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);

    return [self displayNameForAddress:signalAccount.recipientAddress];
}

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address);

    __block SignalAccount *_Nullable signalAccount;

    if (address.uuid) {
        signalAccount = self.uuidSignalAccountMap[address.uuid];
    }

    if (!signalAccount && address.phoneNumber) {
        signalAccount = self.phoneNumberSignalAccountMap[address.phoneNumber];
    }

    // If contact intersection hasn't completed, it might exist on disk
    // even if it doesn't exist in memory yet.
    if (!signalAccount) {
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            signalAccount = [self.accountFinder signalAccountForAddress:address transaction:transaction];
        }];
    }

    return signalAccount;
}

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address);
    OWSAssertDebug(transaction);

    __block SignalAccount *_Nullable signalAccount;

    if (address.uuid) {
        signalAccount = self.uuidSignalAccountMap[address.uuid];
    }

    if (!signalAccount && address.phoneNumber) {
        signalAccount = self.phoneNumberSignalAccountMap[address.phoneNumber];
    }

    // If contact intersection hasn't completed, it might exist on disk
    // even if it doesn't exist in memory yet.
    if (!signalAccount) {
        signalAccount = [self.accountFinder signalAccountForAddress:address transaction:transaction];
    }

    return signalAccount;
}

- (SignalAccount *)fetchOrBuildSignalAccountForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address);

    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address];
    return (signalAccount ?: [[SignalAccount alloc] initWithSignalServiceAddress:address]);
}

- (BOOL)hasSignalAccountForAddress:(SignalServiceAddress *)address
{
    return [self fetchSignalAccountForAddress:address] != nil;
}

- (nullable UIImage *)systemContactOrSyncedImageForAddress:(nullable SignalServiceAddress *)address
{
    if (address == nil) {
        OWSFailDebug(@"address was unexpectedly nil");
        return nil;
    }

    NSString *_Nullable phoneNumber = [self phoneNumberForAddress:address];
    Contact *_Nullable contact = self.allContactsMap[phoneNumber];

    if (contact != nil && contact.cnContactId != nil) {
        UIImage *_Nullable systemContactImage = [self avatarImageForCNContactId:contact.cnContactId];
        if (systemContactImage != nil) {
            return systemContactImage;
        }
    }

    // If we haven't loaded system contacts yet, we may have a cached copy in the db
    SignalAccount *signalAccount = [self fetchSignalAccountForAddress:address];
    if (signalAccount == nil) {
        return nil;
    }

    contact = signalAccount.contact;
    OWSAssertDebug(signalAccount.contact);
    if (contact != nil && contact.cnContactId != nil) {
        UIImage *_Nullable systemContactImage = [self avatarImageForCNContactId:contact.cnContactId];
        if (systemContactImage != nil) {
            return systemContactImage;
        }
    }

    if (signalAccount.contactAvatarJpegData != nil) {
        return [[UIImage alloc] initWithData:signalAccount.contactAvatarJpegData];
    }

    return nil;
}

- (nullable UIImage *)profileImageForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address
{
    if (address == nil) {
        OWSFailDebug(@"address was unexpectedly nil");
        return nil;
    }

    __block UIImage *_Nullable image;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        image = [self.profileManager profileAvatarForAddress:address transaction:transaction];
    }];
    return image;
}

- (nullable NSData *)profileImageDataForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address
{
    if (address == nil) {
        OWSFailDebug(@"address was unexpectedly nil");
        return nil;
    }

    __block NSData *_Nullable data;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        data = [self.profileManager profileAvatarDataForAddress:address transaction:transaction];
    }];
    return data;
}

- (nullable UIImage *)imageForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address
{
    if (address == nil) {
        OWSFailDebug(@"address was unexpectedly nil");
        return nil;
    }

    __block UIImage *_Nullable image = [self systemContactOrSyncedImageForAddress:address];
    if (image != nil) {
        return image;
    }

    // Else try to use the image from their profile
    return [self profileImageForAddressWithSneakyTransaction:address];
}

- (nullable UIImage *)imageForAddress:(nullable SignalServiceAddress *)address
                          transaction:(SDSAnyReadTransaction *)transaction
{
    if (address == nil) {
        OWSFailDebug(@"address was unexpectedly nil");
        return nil;
    }

    __block UIImage *_Nullable image = [self systemContactOrSyncedImageForAddress:address];
    if (image != nil) {
        return image;
    }

    // Else try to use the image from their profile
    return [self.profileManager profileAvatarForAddress:address transaction:transaction];
}

- (NSComparisonResult)compareSignalAccount:(SignalAccount *)left withSignalAccount:(SignalAccount *)right
{
    return self.signalAccountComparator(left, right);
}

- (NSComparisonResult (^)(SignalAccount *left, SignalAccount *right))signalAccountComparator
{
    return ^NSComparisonResult(SignalAccount *left, SignalAccount *right) {
        NSString *leftName = [self comparableNameForSignalAccount:left];
        NSString *rightName = [self comparableNameForSignalAccount:right];

        NSComparisonResult nameComparison = [leftName caseInsensitiveCompare:rightName];
        if (nameComparison == NSOrderedSame) {
            return [left.recipientAddress.stringForDisplay compare:right.recipientAddress.stringForDisplay];
        }

        return nameComparison;
    };
}

- (BOOL)shouldSortByGivenName
{
    return [[CNContactsUserDefaults sharedDefaults] sortOrder] == CNContactSortOrderGivenName;
}

- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    SignalAccount *_Nullable signalAccount = [self fetchSignalAccountForAddress:address transaction:transaction];
    if (signalAccount != nil) {
        return [self comparableNameForSignalAccount:signalAccount
                                        transaction:transaction];
    }

    NSString *_Nullable phoneNumber = signalAccount.recipientPhoneNumber;
    if (phoneNumber != nil) {
        Contact *_Nullable contact = self.allContactsMap[phoneNumber];
        NSString *_Nullable comparableContactName = [self comparableNameForContact:contact];
        if (comparableContactName.length > 0) {
            return comparableContactName;
        }
    }

    // Fall back to non-contact display name.
    return [self displayNameForAddress:address transaction:transaction];
}

- (nullable NSString *)comparableNameForContact:(nullable Contact *)contact
{
    if (contact == nil) {
        return nil;
    }

    if (self.shouldSortByGivenName) {
        return contact.comparableNameFirstLast;
    }

    return contact.comparableNameLastFirst;
}

- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
{
    NSString *_Nullable name = [self comparableNameForContact:signalAccount.contact];

    if (name.length < 1) {
        name = [self displayNameForSignalAccount:signalAccount];
    }

    return name;
}

- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
                                 transaction:(SDSAnyReadTransaction *)transaction
{
    NSString *_Nullable name = [self comparableNameForContact:signalAccount.contact];

    if (name.length < 1) {
        name = [self displayNameForAddress:signalAccount.recipientAddress transaction:transaction];
    }

    return name;
}

#pragma mark -

- (NSString *)legacyDisplayNameForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    // Prefer a saved name from system contacts, if available
    NSString *_Nullable savedContactName = [self cachedContactNameForAddress:address];
    if (savedContactName.length > 0) {
        return savedContactName;
    }

    __block NSString *_Nullable profileName;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        profileName = [self.profileManager profileNameForAddress:address transaction:transaction];
    }];

    if (profileName.length > 0) {
        return [[address.stringForDisplay stringByAppendingString:@" ~"] stringByAppendingString:profileName];
    }

    // else fall back to phone number / uuid
    return address.stringForDisplay;
}

- (NSAttributedString *)attributedLegacyDisplayNameForAddress:(SignalServiceAddress *)address
                                                  primaryFont:(UIFont *)primaryFont
                                                secondaryFont:(UIFont *)secondaryFont
{
    OWSAssertDebug(primaryFont);
    OWSAssertDebug(secondaryFont);

    return [self attributedLegacyDisplayNameForAddress:address
                                     primaryAttributes:@{
                                         NSFontAttributeName : primaryFont,
                                     }
                                   secondaryAttributes:@{
                                       NSFontAttributeName : secondaryFont,
                                   }];
}

- (NSAttributedString *)attributedLegacyDisplayNameForAddress:(SignalServiceAddress *)address
                                            primaryAttributes:(NSDictionary *)primaryAttributes
                                          secondaryAttributes:(NSDictionary *)secondaryAttributes
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(primaryAttributes.count > 0);
    OWSAssertDebug(secondaryAttributes.count > 0);

    // Prefer a saved name from system contacts, if available
    NSString *_Nullable savedContactName = [self cachedContactNameForAddress:address];
    if (savedContactName.length > 0) {
        return [[NSAttributedString alloc] initWithString:savedContactName attributes:primaryAttributes];
    }

    __block NSString *_Nullable profileName;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        profileName = [self.profileManager profileNameForAddress:address transaction:transaction];
    }];

    if (profileName.length > 0) {
        NSAttributedString *result = [[NSAttributedString alloc] initWithString:address.stringForDisplay
                                                                     attributes:primaryAttributes];
        result = [result stringByAppendingString:[[NSAttributedString alloc] initWithString:@" "]];
        result = [result stringByAppendingString:[[NSAttributedString alloc] initWithString:@"~"
                                                                                 attributes:secondaryAttributes]];
        result = [result stringByAppendingString:[[NSAttributedString alloc] initWithString:profileName
                                                                                 attributes:secondaryAttributes]];
        return [result copy];
    }

    // else fall back to phone number / uuid
    return [[NSAttributedString alloc] initWithString:address.stringForDisplay attributes:primaryAttributes];
}

- (nullable NSString *)formattedProfileNameForAddress:(SignalServiceAddress *)address
{
    __block NSString *_Nullable profileName;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        profileName = [self formattedProfileNameForAddress:address transaction:transaction];
    }];
    return profileName;
}

- (nullable NSString *)formattedProfileNameForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    NSString *_Nullable profileName = [self.profileManager profileNameForAddress:address transaction:transaction];

    if (profileName.length > 0) {
        return [@"~" stringByAppendingString:profileName];
    }

    return nil;
}

- (nullable NSString *)contactOrProfileNameForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    NSString *_Nullable name = [self cachedContactNameForAddress:address];

    if (name.length == 0) {
        __block NSString *_Nullable profileName;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            profileName = [self.profileManager profileNameForAddress:address transaction:transaction];
        }];

        if (profileName.length > 0) {
            name = profileName;
        }
    }

    return name;
}

NS_ASSUME_NONNULL_END

@end
