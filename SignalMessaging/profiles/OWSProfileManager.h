//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/ProfileManagerProtocol.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_ProfileWhitelistDidChange;
extern NSString *const kNSNotificationName_ProfileKeyDidChange;

extern const NSUInteger kOWSProfileManager_NameDataLength;
extern const NSUInteger kOWSProfileManager_MaxAvatarDiameter;

@class OWSAES256Key;
@class OWSMessageSender;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;
@class SDSKeyValueStore;
@class SignalServiceAddress;
@class TSNetworkManager;
@class TSThread;

// This class can be safely accessed and used from any thread.
@interface OWSProfileManager : NSObject <ProfileManagerProtocol>

@property (nonatomic, readonly) SDSKeyValueStore *whitelistedPhoneNumbersStore;
@property (nonatomic, readonly) SDSKeyValueStore *whitelistedUUIDsStore;
@property (nonatomic, readonly) SDSKeyValueStore *whitelistedGroupsStore;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

#pragma mark - Local Profile

// These two methods should only be called from the main thread.
- (OWSAES256Key *)localProfileKey;
// localUserProfileExists is true if there is _ANY_ local profile.
- (BOOL)localProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction;
// hasLocalProfile is true if there is a local profile with a name or avatar.
- (BOOL)hasLocalProfile;
- (nullable NSString *)localProfileName;
- (nullable NSString *)localUsername;
- (nullable UIImage *)localProfileAvatarImage;
- (nullable NSData *)localProfileAvatarData;

// This method is used to update the "local profile" state on the client
// and the service.  Client state is only updated if service state is
// successfully updated.
//
// This method should only be called from the main thread.
- (void)updateLocalProfileName:(nullable NSString *)profileName
                   avatarImage:(nullable UIImage *)avatarImage
                       success:(void (^)(void))successBlock
                       failure:(void (^)(void))failureBlock;

- (void)updateLocalUsername:(nullable NSString *)username transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName;

- (void)fetchAndUpdateLocalUsersProfile;

// The completions are invoked on the main thread.
- (void)fetchAndUpdateProfileForUsername:(NSString *)username
                                 success:(void (^)(SignalServiceAddress *))successHandler
                                notFound:(void (^)(void))notFoundHandler
                                 failure:(void (^)(NSError *))failureHandler;

#pragma mark - Profile Whitelist

// These methods are for debugging.
- (void)clearProfileWhitelist;
- (void)logProfileWhitelist;
- (void)debug_regenerateLocalProfileWithSneakyTransaction;
- (void)setLocalProfileKey:(OWSAES256Key *)key transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addThreadToProfileWhitelist:(TSThread *)thread;
- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses;

- (void)setContactAddresses:(NSArray<SignalServiceAddress *> *)contactAddresses;

#pragma mark - Other User's Profiles

// This method is for debugging.
- (void)logUserProfiles;

- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)profileNameForAddress:(SignalServiceAddress *)address
                                 transaction:(SDSAnyReadTransaction *)transaction;

- (nullable UIImage *)profileAvatarForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction;
- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)usernameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

- (void)updateProfileForAddress:(SignalServiceAddress *)address
           profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                       username:(nullable NSString *)username
                  avatarUrlPath:(nullable NSString *)avatarUrlPath;

#pragma mark - Clean Up

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction;

#pragma mark - User Interface

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler;

@end

NS_ASSUME_NONNULL_END
