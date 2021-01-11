//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSContactsManagerSignalAccountsDidChangeNotification;

@class AnyPromise;
@class ImageCache;
@class SDSAnyReadTransaction;
@class SDSKeyValueStore;
@class SignalAccount;
@class SignalServiceAddress;
@class TSThread;
@class UIFont;

/**
 * Get latest Signal contacts, and be notified when they change.
 */
@interface OWSContactsManager : NSObject <ContactsManagerProtocol>

#pragma mark - Accessors

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@property (nonnull, readonly) ImageCache *avatarCache;


@property (atomic, readonly) NSArray<Contact *> *allContacts;

@property (atomic, readonly) NSDictionary<NSString *, Contact *> *allContactsMap;

// order of the signalAccounts array respects the systems contact sorting preference
@property (atomic, readonly) NSArray<SignalAccount *> *signalAccounts;

// This will return an instance of SignalAccount for _known_ signal accounts.
- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address;

- (nullable SignalAccount *)fetchSignalAccountForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyReadTransaction *)transaction;

// This will always return an instance of SignalAccount.
- (SignalAccount *)fetchOrBuildSignalAccountForAddress:(SignalServiceAddress *)address;
- (BOOL)hasSignalAccountForAddress:(SignalServiceAddress *)address;

#pragma mark - System Contact Fetching

// Must call `requestSystemContactsOnce` before accessing this method
@property (nonatomic, readonly) BOOL isSystemContactsAuthorized;
@property (nonatomic, readonly) BOOL isSystemContactsDenied;
@property (nonatomic, readonly) BOOL systemContactsHaveBeenRequestedAtLeastOnce;

@property (nonatomic, readonly) BOOL supportsContactEditing;

@property (atomic, readonly) BOOL isSetup;

// Not set until a contact fetch has completed.
// Set even if no contacts are found.
@property (nonatomic, readonly) BOOL hasLoadedContacts;

// Request systems contacts and start syncing changes. The user will see an alert
// if they haven't previously.
- (void)requestSystemContactsOnce;
- (void)requestSystemContactsOnceWithCompletion:(void (^_Nullable)(NSError *_Nullable error))completion;

// Ensure's the app has the latest contacts, but won't prompt the user for contact
// access if they haven't granted it.
- (void)fetchSystemContactsOnceIfAlreadyAuthorized;

// This variant will fetch system contacts if contact access has already been granted,
// but not prompt for contact access. Also, it will always notify delegates, even if
// contacts haven't changed, and will clear out any stale cached SignalAccounts
- (AnyPromise *)userRequestedSystemContactsRefresh;

#pragma mark - Util

- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber;
- (BOOL)isSystemContactWithAddress:(SignalServiceAddress *)address;
- (BOOL)isSystemContactWithSignalAccount:(NSString *)phoneNumber;
- (BOOL)hasNameInSystemContactsForAddress:(SignalServiceAddress *)address;

/**
 * Used for sorting, respects system contacts name sort order preference.
 */
- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount;
- (NSString *)comparableNameForSignalAccount:(SignalAccount *)signalAccount
                                 transaction:(SDSAnyReadTransaction *)transaction;
- (NSString *)comparableNameForAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (nullable UIImage *)systemContactOrSyncedImageForAddress:(nullable SignalServiceAddress *)address;
- (nullable UIImage *)profileImageForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address;
- (nullable NSData *)profileImageDataForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address;
- (nullable UIImage *)imageForAddress:(nullable SignalServiceAddress *)address
                          transaction:(SDSAnyReadTransaction *)transaction;
- (nullable UIImage *)imageForAddressWithSneakyTransaction:(nullable SignalServiceAddress *)address;

- (void)clearColorNameCache;
- (NSString *)conversationColorNameForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction;

// Legacy display name helpers, once the `profileDisplayChanges` feature is enabled these can go away.
- (NSString *)legacyDisplayNameForAddress:(SignalServiceAddress *)address;
- (NSAttributedString *)attributedLegacyDisplayNameForAddress:(SignalServiceAddress *)address
                                                  primaryFont:(UIFont *)primaryFont
                                                secondaryFont:(UIFont *)secondaryFont;
- (NSAttributedString *)attributedLegacyDisplayNameForAddress:(SignalServiceAddress *)address
                                            primaryAttributes:(NSDictionary *)primaryAttributes
                                          secondaryAttributes:(NSDictionary *)secondaryAttributes;
- (nullable NSString *)formattedProfileNameForAddress:(SignalServiceAddress *)address;
- (nullable NSString *)formattedProfileNameForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)contactOrProfileNameForAddress:(SignalServiceAddress *)address;

@end

NS_ASSUME_NONNULL_END
