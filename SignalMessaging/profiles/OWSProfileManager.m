//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileManager.h"
#import "Environment.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/OWSRequestBuilder.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/OWSUploadV2.h>
#import <SignalServiceKit/OWSUserProfile.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/UIImage+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_ProfileWhitelistDidChange = @"kNSNotificationName_ProfileWhitelistDidChange";

NSString *const kNSNotificationName_ProfileKeyDidChange = @"kNSNotificationName_ProfileKeyDidChange";

// The max bytes for a user's profile name, encoded in UTF8.
// Before encrypting and submitting we NULL pad the name data to this length.
const NSUInteger kOWSProfileManager_NameDataLength = 26;
const NSUInteger kOWSProfileManager_MaxAvatarDiameter = 640;

static const BOOL kAvatarUploadNoCdn = YES;
static const BOOL kAvatarDownloadNoCdn = YES;

typedef void (^ProfileManagerFailureBlock)(NSError *error);

@interface OWSProfileManager ()

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) OWSUserProfile *localUserProfile;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSCache<NSString *, UIImage *> *profileAvatarImageCache;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSMutableSet<SignalServiceAddress *> *currentAvatarDownloads;

@end

#pragma mark -

// Access to most state should happen while synchronized on the profile manager.
// Writes should happen off the main thread, wherever possible.
@implementation OWSProfileManager

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

@synthesize localUserProfile = _localUserProfile;

+ (instancetype)sharedManager
{
    return SSKEnvironment.shared.profileManager;
}

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();
    OWSAssertDebug(databaseStorage);

    NSString *const kOWSProfileManager_UserPhoneNumberWhitelistCollection
        = @"kOWSProfileManager_UserWhitelistCollection";
    NSString *const kOWSProfileManager_UserUUIDWhitelistCollection = @"kOWSProfileManager_UserUUIDWhitelistCollection";
    NSString *const kOWSProfileManager_GroupWhitelistCollection = @"kOWSProfileManager_GroupWhitelistCollection";

    _whitelistedPhoneNumbersStore =
        [[SDSKeyValueStore alloc] initWithCollection:kOWSProfileManager_UserPhoneNumberWhitelistCollection];
    _whitelistedUUIDsStore =
        [[SDSKeyValueStore alloc] initWithCollection:kOWSProfileManager_UserUUIDWhitelistCollection];
    _whitelistedGroupsStore = [[SDSKeyValueStore alloc] initWithCollection:kOWSProfileManager_GroupWhitelistCollection];

    _profileAvatarImageCache = [NSCache new];
    _currentAvatarDownloads = [NSMutableSet new];

    OWSSingletonAssert();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (TSAccountManager.sharedInstance.isRegistered) {
            [self rotateLocalProfileKeyIfNecessary];
        }
    }];

    [self observeNotifications];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockListDidChange:)
                                                 name:kNSNotificationName_BlockListDidChange
                                               object:nil];
}

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

- (AFHTTPSessionManager *)avatarHTTPManager
{
    return [OWSSignalService sharedInstance].CDNSessionManager;
}

- (AFHTTPSessionManager *)noCdnSessionManager
{
    return [OWSSignalService sharedInstance].noCDNSessionManager;
}

- (OWSIdentityManager *)identityManager
{
    return SSKEnvironment.shared.identityManager;
}

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

- (OWSBlockingManager *)blockingManager
{
    return SSKEnvironment.shared.blockingManager;
}

- (id<SyncManagerProtocol>)syncManager
{
    return SSKEnvironment.shared.syncManager;
}

- (id<OWSUDManager>)udManager
{
    OWSAssertDebug(SSKEnvironment.shared.udManager);

    return SSKEnvironment.shared.udManager;
}

#pragma mark - User Profile Accessor

- (void)warmCaches
{
    [self ensureLocalProfileCached];
}

- (void)ensureLocalProfileCached
{
    // Since localUserProfile can create a transaction, we want to make sure it's not called for the first
    // time unexpectedly (e.g. in a nested transaction.)
    __unused OWSUserProfile *profile = [self localUserProfile];
}

#pragma mark - Local Profile

- (OWSUserProfile *)localUserProfile
{
    @synchronized(self)
    {
        if (_localUserProfile) {
            OWSAssertDebug(_localUserProfile.profileKey);

            return _localUserProfile;
        }
    }

    // We create the profile outside the @synchronized block
    // to avoid any risk of deadlock.  Thanks to ensureLocalProfileCached,
    // there should be no risk of races.  And races should be harmless
    // since: a) getOrBuildUserProfileForAddress is idempotent and b) we use
    // the "update with..." pattern.
    //
    // We first try using a read block to avoid opening a write block.
    __block OWSUserProfile *_Nullable localUserProfile;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        localUserProfile = [OWSUserProfile getUserProfileForAddress:OWSUserProfile.localProfileAddress
                                                        transaction:transaction];
    }];

    if (localUserProfile != nil) {
        @synchronized(self) {
            _localUserProfile = localUserProfile;
        }
        return localUserProfile;
    }

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        localUserProfile =
            [OWSUserProfile getOrBuildUserProfileForAddress:OWSUserProfile.localProfileAddress transaction:transaction];
    }];

    @synchronized(self) {
        _localUserProfile = localUserProfile;
    }

    OWSAssertDebug(_localUserProfile.profileKey);

    return _localUserProfile;
}

- (BOOL)localProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSUserProfile localUserProfileExistsWithTransaction:transaction];
}

- (OWSAES256Key *)localProfileKey
{
    OWSAssertDebug(self.localUserProfile.profileKey.keyData.length == kAES256_KeyByteLength);

    return self.localUserProfile.profileKey;
}

- (BOOL)hasLocalProfile
{
    return (self.localProfileName.length > 0 || self.localProfileAvatarImage != nil);
}

- (nullable NSString *)localProfileName
{
    return self.localUserProfile.profileName;
}

- (nullable UIImage *)localProfileAvatarImage
{
    return [self loadProfileAvatarWithFilename:self.localUserProfile.avatarFileName];
}

- (nullable NSData *)localProfileAvatarData
{
    NSString *_Nullable filename = self.localUserProfile.avatarFileName;
    if (filename.length < 1) {
        return nil;
    }
    return [self loadProfileDataWithFilename:filename];
}

- (nullable NSString *)localUsername
{
    return self.localUserProfile.username;
}

- (void)updateLocalProfileName:(nullable NSString *)profileName
                   avatarImage:(nullable UIImage *)avatarImage
                       success:(void (^)(void))successBlockParameter
                       failure:(void (^)(void))failureBlockParameter
{
    OWSAssertDebug(successBlockParameter);
    OWSAssertDebug(failureBlockParameter);

    // Ensure that the success and failure blocks are called on the main thread.
    void (^failureBlock)(void) = ^{
        OWSLogError(@"Updating service with profile failed.");

        // We use a "self-only" contact sync to indicate to desktop
        // that we've changed our profile and that it should do a
        // profile fetch for "self".
        //
        // NOTE: We also inform the desktop in the failure case,
        //       since that _may have_ affected service state.
        if (self.tsAccountManager.isRegisteredPrimaryDevice) {
            [[self.syncManager syncLocalContact] retainUntilComplete];
        }

        // Notify all our devices that the profile has changed.
        // Older linked devices may not handle this message.
        [self.syncManager sendFetchLatestProfileSyncMessage];

        dispatch_async(dispatch_get_main_queue(), ^{
            failureBlockParameter();
        });
    };
    void (^successBlock)(void) = ^{
        OWSLogInfo(@"Successfully updated service with profile.");

        // We use a "self-only" contact sync to indicate to desktop
        // that we've changed our profile and that it should do a
        // profile fetch for "self".
        if (self.tsAccountManager.isRegisteredPrimaryDevice) {
            [[self.syncManager syncLocalContact] retainUntilComplete];
        }

        // Notify all our devices that the profile has changed.
        // Older linked devices may not handle this message.
        [self.syncManager sendFetchLatestProfileSyncMessage];

        dispatch_async(dispatch_get_main_queue(), ^{
            successBlockParameter();
        });
    };

    // The final steps are to:
    //
    // * Try to update the service.
    // * Update client state on success.
    void (^tryToUpdateService)(NSString *_Nullable, NSString *_Nullable) = ^(
        NSString *_Nullable avatarUrlPath, NSString *_Nullable avatarFileName) {
        [self updateServiceWithProfileName:profileName
            success:^{
                OWSUserProfile *userProfile = self.localUserProfile;
                OWSAssertDebug(userProfile);

                [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
                    [userProfile updateWithProfileName:profileName
                                         avatarUrlPath:avatarUrlPath
                                        avatarFileName:avatarFileName
                                           transaction:transaction
                                            completion:^{
                                                if (avatarFileName) {
                                                    [self updateProfileAvatarCache:avatarImage filename:avatarFileName];
                                                }

                                                successBlock();
                                            }];
                }];
            }
            failure:^(NSError *error) {
                failureBlock();
            }];
    };

    OWSUserProfile *userProfile = self.localUserProfile;
    OWSAssertDebug(userProfile);

    if (avatarImage) {
        // If we have a new avatar image, we must first:
        //
        // * Encode it to JPEG.
        // * Write it to disk.
        // * Encrypt it
        // * Upload it to asset service
        // * Send asset service info to Signal Service
        if (self.localProfileAvatarImage == avatarImage) {
            OWSAssertDebug(userProfile.avatarUrlPath.length > 0);
            OWSAssertDebug(userProfile.avatarFileName.length > 0);

            OWSLogVerbose(@"Updating local profile on service with unchanged avatar.");
            // If the avatar hasn't changed, reuse the existing metadata.
            tryToUpdateService(userProfile.avatarUrlPath, userProfile.avatarFileName);
        } else {
            OWSLogVerbose(@"Updating local profile on service with new avatar.");
            [self writeAvatarToDisk:avatarImage
                success:^(NSData *data, NSString *fileName) {
                    [self uploadAvatarToService:data
                        success:^(NSString *_Nullable avatarUrlPath) {
                            tryToUpdateService(avatarUrlPath, fileName);
                        }
                        failure:^(NSError *error) {
                            failureBlock();
                        }];
                }
                failure:^(NSError *error) {
                    failureBlock();
                }];
        }
    } else if (userProfile.avatarUrlPath) {
        OWSLogVerbose(@"Updating local profile on service with cleared avatar.");
        [self uploadAvatarToService:nil
            success:^(NSString *_Nullable avatarUrlPath) {
                tryToUpdateService(nil, nil);
            }
            failure:^(NSError *error) {
                failureBlock();
            }];
    } else {
        OWSLogVerbose(@"Updating local profile on service with no avatar.");
        tryToUpdateService(nil, nil);
    }
}

- (void)updateLocalUsername:(nullable NSString *)username transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(username == nil || username.length > 0);

    OWSUserProfile *userProfile = self.localUserProfile;
    OWSAssertDebug(self.localUserProfile);

    [userProfile updateWithUsername:username transaction:transaction];
}

- (void)writeAvatarToDisk:(UIImage *)avatar
                  success:(void (^)(NSData *data, NSString *fileName))successBlock
                  failure:(ProfileManagerFailureBlock)failureBlock {
    OWSAssertDebug(avatar);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (avatar) {
            NSData *data = [self processedImageDataForRawAvatar:avatar];
            OWSAssertDebug(data);
            if (data) {
                NSString *fileName = [self generateAvatarFilename];
                NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:fileName];
                BOOL success = [data writeToFile:filePath atomically:YES];
                OWSAssertDebug(success);
                if (success) {
                    return successBlock(data, fileName);
                }
            }
        }
        failureBlock(OWSErrorWithCodeDescription(OWSErrorCodeAvatarWriteFailed, @"Avatar write failed."));
    });
}

- (NSData *)processedImageDataForRawAvatar:(UIImage *)image
{
    NSUInteger kMaxAvatarBytes = 5 * 1000 * 1000;

    if (image.size.width != kOWSProfileManager_MaxAvatarDiameter
        || image.size.height != kOWSProfileManager_MaxAvatarDiameter) {
        // To help ensure the user is being shown the same cropping of their avatar as
        // everyone else will see, we want to be sure that the image was resized before this point.
        OWSFailDebug(@"Avatar image should have been resized before trying to upload");
        image = [image resizedImageToFillPixelSize:CGSizeMake(kOWSProfileManager_MaxAvatarDiameter,
                                                       kOWSProfileManager_MaxAvatarDiameter)];
    }

    NSData *_Nullable data = UIImageJPEGRepresentation(image, 0.95f);
    if (data.length > kMaxAvatarBytes) {
        // Our avatar dimensions are so small that it's incredibly unlikely we wouldn't be able to fit our profile
        // photo. e.g. generating pure noise at our resolution compresses to ~200k.
        OWSFailDebug(@"Suprised to find profile avatar was too large. Was it scaled properly? image: %@", image);
    }

    return data;
}

// If avatarData is nil, we are clearing the avatar.
- (void)uploadAvatarToService:(NSData *_Nullable)avatarData
                      success:(void (^)(NSString *_Nullable avatarUrlPath))successBlock
                      failure:(ProfileManagerFailureBlock)failureBlock {
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);
    OWSAssertDebug(avatarData == nil || avatarData.length > 0);

    // We want to clear the local user's profile avatar as soon as
    // we request the upload form, since that request clears our
    // avatar on the service.
    //
    // TODO: Revisit this so that failed profile updates don't leave
    // the profile avatar blank, etc.
    void (^clearLocalAvatar)(void) = ^{
        // This completion block will never be called within a transaction.
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            OWSUserProfile *userProfile = self.localUserProfile;
            [userProfile updateWithAvatarUrlPath:nil avatarFileName:nil transaction:transaction completion:nil];
        }];
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *_Nullable encryptedAvatarData;
        if (avatarData) {
            encryptedAvatarData = [self encryptProfileData:avatarData];
            OWSAssertDebug(encryptedAvatarData.length > 0);
        }

        OWSAvatarUploadV2 *upload = [OWSAvatarUploadV2 new];
        [[upload uploadAvatarToService:encryptedAvatarData
                      clearLocalAvatar:clearLocalAvatar
                         progressBlock:^(NSProgress *progress){
                             // Do nothing.
                         }
                                 noCdn:kAvatarUploadNoCdn]
                .thenInBackground(^{
                    OWSLogVerbose(@"Upload complete.");

                    successBlock(upload.urlPath);
                })
                .catchInBackground(^(NSError *error) {
                    OWSLogError(@"Failed: %@", error);

                    failureBlock(error);
                }) retainUntilComplete];
    });
}

- (void)updateServiceWithProfileName:(nullable NSString *)localProfileName
                             success:(void (^)(void))successBlock
                             failure:(ProfileManagerFailureBlock)failureBlock {
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *_Nullable encryptedPaddedName = [self encryptProfileNameWithUnpaddedName:localProfileName];

        TSRequest *request = [OWSRequestBuilder profileNameSetRequestWithEncryptedPaddedName:encryptedPaddedName];
        [self.networkManager makeRequest:request
            success:^(NSURLSessionDataTask *task, id responseObject) {
                successBlock();
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                OWSLogError(@"Failed to update profile with error: %@", error);
                failureBlock(error);
            }];
    });
}

- (void)fetchAndUpdateLocalUsersProfile
{
    SignalServiceAddress *_Nullable localAddress = self.tsAccountManager.localAddress;
    if (!localAddress.isValid) {
        return;
    }
    [self updateProfileForAddress:localAddress];
}

- (void)updateProfileForAddress:(SignalServiceAddress *)address
{
    [ProfileFetcherJob fetchAndUpdateProfileWithAddress:address ignoreThrottling:YES];
}

- (void)fetchAndUpdateProfileForUsername:(NSString *)username
                                 success:(void (^)(SignalServiceAddress *))success
                                notFound:(void (^)(void))notFound
                                 failure:(void (^)(NSError *))failure
{
    OWSAssertDebug(username.length > 0);

    // Check if we have a cached profile for this username, if so avoid fetching it from the service
    // since we are limited to 100 username lookups per day.

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block OWSUserProfile *_Nullable userProfile;
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            userProfile = [OWSUserProfile userProfileForUsername:username transaction:transaction];
        }];

        if (userProfile) {
            success(userProfile.address);
            return;
        }

        [ProfileFetcherJob fetchAndUpdateProfileWithUsername:username
                                                     success:success
                                                    notFound:notFound
                                                     failure:failure];
    });
}

#pragma mark - Profile Key Rotation

- (nullable NSString *)groupKeyForGroupId:(NSData *)groupId {
    NSString *groupIdKey = [groupId hexadecimalString];
    return groupIdKey;
}

- (nullable NSData *)groupIdForGroupKey:(NSString *)groupKey {
    NSData *_Nullable groupId = [NSData dataFromHexString:groupKey];
    if (groupId.length != (NSUInteger)kGroupIdLength) {
        OWSFailDebug(@"Parsed group id has unexpected length: %@ (%lu)",
            groupId.hexadecimalString,
            (unsigned long)groupId.length);
        return nil;
    }
    return [groupId copy];
}

- (void)rotateLocalProfileKeyIfNecessary {
    if (!self.tsAccountManager.isRegisteredPrimaryDevice) {
        OWSAssertDebug(self.tsAccountManager.isRegistered);
        OWSLogVerbose(@"Not rotating profile key on non-primary device");
        return;
    }

    [self
        rotateLocalProfileKeyIfNecessaryWithSuccess:^{
        }
                                            failure:^(NSError *error) {
                                            }];
}

- (void)rotateLocalProfileKeyIfNecessaryWithSuccess:(dispatch_block_t)success
                                            failure:(ProfileManagerFailureBlock)failure {
    OWSAssertDebug(AppReadiness.isAppReady);

    if (!self.tsAccountManager.isRegistered) {
        OWSFailDebug(@"tsAccountManager.isRegistered was unexpectely false");
        success();
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableSet<NSString *> *whitelistedPhoneNumbers = [NSMutableSet new];
        NSMutableSet<NSString *> *whitelistedUUIDS = [NSMutableSet new];
        NSMutableSet<NSData *> *whitelistedGroupIds = [NSMutableSet new];
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            [whitelistedPhoneNumbers
                addObjectsFromArray:[self.whitelistedPhoneNumbersStore allKeysWithTransaction:transaction]];
            [whitelistedUUIDS addObjectsFromArray:[self.whitelistedUUIDsStore allKeysWithTransaction:transaction]];
            NSArray<NSString *> *whitelistedGroupKeys =
                [self.whitelistedGroupsStore allKeysWithTransaction:transaction];

            for (NSString *groupKey in whitelistedGroupKeys) {
                NSData *_Nullable groupId = [self groupIdForGroupKey:groupKey];
                if (!groupId) {
                    OWSFailDebug(@"Couldn't parse group key: %@.", groupKey);
                    continue;
                }

                [whitelistedGroupIds addObject:groupId];

                // Note we don't add `group.recipientIds` to the `whitelistedRecipientIds`.
                //
                // Whenever we message a contact, be it in a 1:1 thread or in a group thread,
                // we add them to the contact whitelist, so there's no reason to redundnatly
                // add them here.
                //
                // Furthermore, doing so would cause the following problem:
                // - Alice is in group Book Club
                // - Add Book Club to your profile white list
                // - Message Book Club, which also adds Alice to your profile whitelist.
                // - Block Alice, but not Book Club
                //
                // Now, at this point we'd want to rotate our profile key once, since Alice has
                // it via BookClub.
                //
                // However, after we did. The next time we check if we should rotate our profile
                // key, adding all `group.recipientIds` to `whitelistedRecipientIds` here, would
                // include Alice, and we'd rotate our profile key every time this method is called.
            }
        }];

        SignalServiceAddress *_Nullable localAddress = [self.tsAccountManager localAddress];
        NSString *_Nullable localNumber = localAddress.phoneNumber;
        if (localNumber) {
            [whitelistedPhoneNumbers removeObject:localNumber];
        } else {
            OWSFailDebug(@"Missing localNumber");
        }

        NSString *_Nullable localUUID = localAddress.uuidString;
        if (localUUID) {
            [whitelistedUUIDS removeObject:localUUID];
        } else {
            if (SSKFeatureFlags.allowUUIDOnlyContacts) {
                OWSFailDebug(@"Missing localUUID");
            }
        }

        NSSet<NSString *> *blockedPhoneNumbers = [NSSet setWithArray:self.blockingManager.blockedPhoneNumbers];
        NSSet<NSString *> *blockedUUIDs = [NSSet setWithArray:self.blockingManager.blockedUUIDs];
        NSSet<NSData *> *blockedGroupIds = [NSSet setWithArray:self.blockingManager.blockedGroupIds];

        // Find the users and groups which are both a) blocked b) may have our current profile key.
        NSMutableSet<NSString *> *intersectingPhoneNumbers = [blockedPhoneNumbers mutableCopy];
        [intersectingPhoneNumbers intersectSet:whitelistedPhoneNumbers];
        NSMutableSet<NSString *> *intersectingUUIDS = [blockedUUIDs mutableCopy];
        [intersectingUUIDS intersectSet:whitelistedUUIDS];
        NSMutableSet<NSData *> *intersectingGroupIds = [blockedGroupIds mutableCopy];
        [intersectingGroupIds intersectSet:whitelistedGroupIds];

        BOOL isProfileKeySharedWithBlocked
            = (intersectingPhoneNumbers.count > 0 || intersectingUUIDS.count > 0 || intersectingGroupIds.count > 0);
        if (!isProfileKeySharedWithBlocked) {
            // No need to rotate the profile key.
            return success();
        }
        [self rotateProfileKeyWithIntersectingPhoneNumbers:intersectingPhoneNumbers
                                         intersectingUUIDs:intersectingUUIDS
                                      intersectingGroupIds:intersectingGroupIds
                                                   success:success
                                                   failure:failure];
    });
}

- (void)rotateProfileKeyWithIntersectingPhoneNumbers:(NSSet<NSString *> *)intersectingPhoneNumbers
                                   intersectingUUIDs:(NSSet<NSString *> *)intersectingUUIDs
                                intersectingGroupIds:(NSSet<NSData *> *)intersectingGroupIds
                                             success:(dispatch_block_t)success
                                             failure:(ProfileManagerFailureBlock)failure
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Rotate the profile key
        OWSLogInfo(@"Rotating the profile key.");

        // Make copies of the current local profile state.
        OWSUserProfile *localUserProfile = self.localUserProfile;
        NSString *_Nullable oldProfileName = localUserProfile.profileName;
        NSString *_Nullable oldAvatarFileName = localUserProfile.avatarFileName;
        __block NSData *_Nullable oldAvatarData;

        // Rotate the stored profile key.
        AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
            [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
                SignalServiceAddress *_Nullable localAddress =
                    [self.tsAccountManager localAddressWithTransaction:transaction];
                oldAvatarData = [self profileAvatarDataForAddress:localAddress transaction:transaction];

                [self.localUserProfile updateWithProfileKey:[OWSAES256Key generateRandomKey]
                                                transaction:transaction
                                                 completion:^{
                                                     // The value doesn't matter, we just need any non-NSError value.
                                                     resolve(@(1));
                                                 }];
            }];
        }];

        // Try to re-upload our profile name, if any.
        //
        // This may fail.
        promise = promise.thenInBackground(^(id value) {
            if (oldProfileName.length < 1) {
                return [AnyPromise promiseWithValue:@(1)];
            }
            return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
                [self updateServiceWithProfileName:oldProfileName
                    success:^{
                        OWSLogInfo(@"Update to profile name succeeded.");

                        // The value doesn't matter, we just need any non-NSError value.
                        resolve(@(1));
                    }
                    failure:^(NSError *error) {
                        resolve(error);
                    }];
            }];
        });

        // Try to re-upload our profile avatar, if any.
        //
        // This may fail.
        promise = promise.thenInBackground(^(id value) {
            if (oldAvatarData.length < 1 || oldAvatarFileName.length < 1) {
                return [AnyPromise promiseWithValue:@(1)];
            }
            return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
                [self uploadAvatarToService:oldAvatarData
                    success:^(NSString *_Nullable avatarUrlPath) {
                        OWSLogInfo(@"Update to profile avatar after profile key rotation succeeded.");
                        // The profile manager deletes the underlying file when updating a profile URL
                        // So we need to copy the underlying file to a new location.
                        NSString *oldPath = [OWSUserProfile profileAvatarFilepathWithFilename:oldAvatarFileName];
                        NSString *newAvatarFilename = [self generateAvatarFilename];
                        NSString *newPath = [OWSUserProfile profileAvatarFilepathWithFilename:newAvatarFilename];
                        NSError *error;
                        [NSFileManager.defaultManager copyItemAtPath:oldPath toPath:newPath error:&error];
                        OWSAssertDebug(!error);

                        [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
                            [self.localUserProfile updateWithAvatarUrlPath:avatarUrlPath
                                                            avatarFileName:newAvatarFilename
                                                               transaction:transaction
                                                                completion:^{
                                                                    // The value doesn't matter, we just need any
                                                                    // non-NSError value.
                                                                    resolve(@(1));
                                                                }];
                        }];
                    }
                    failure:^(NSError *error) {
                        OWSLogInfo(@"Update to profile avatar after profile key rotation failed.");
                        resolve(error);
                    }];
            }];
        });

        // Try to re-upload our profile avatar, if any.
        //
        // This may fail.
        promise = promise.thenInBackground(^(id value) {
            // Remove blocked users and groups from profile whitelist.
            //
            // This will always succeed.
            [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                [self.whitelistedPhoneNumbersStore removeValuesForKeys:intersectingPhoneNumbers.allObjects
                                                           transaction:transaction];
                [self.whitelistedUUIDsStore removeValuesForKeys:intersectingUUIDs.allObjects transaction:transaction];
                for (NSData *groupId in intersectingGroupIds) {
                    NSString *groupIdKey = [self groupKeyForGroupId:groupId];
                    [self.whitelistedGroupsStore removeValueForKey:groupIdKey transaction:transaction];
                }
            }];
            return @(1);
        });

        // Update account attributes.
        //
        // This may fail.
        promise = promise.thenInBackground(^(id value) {
            return [self.tsAccountManager updateAccountAttributes];
        });

        // Fetch local profile.
        promise = promise.then(^(id value) {
            [self fetchAndUpdateLocalUsersProfile];

            return @(1);
        });

        // Sync local profile key.
        if (self.tsAccountManager.isRegisteredPrimaryDevice) {
            promise = promise.thenInBackground(^(id value) {
                return [self.syncManager syncLocalContact];
            });
        }

        promise = promise.thenInBackground(^(id value) {
            [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_ProfileKeyDidChange
                                                                     object:nil
                                                                   userInfo:nil];

            success();
        });
        promise = promise.catch(^(NSError *error) {
            if ([error isKindOfClass:[NSError class]]) {
                failure(error);
            } else {
                failure(OWSErrorMakeAssertionError(@"Profile key rotation failure missing error."));
            }
        });
        [promise retainUntilComplete];
    });
}

#pragma mark - Profile Whitelist

- (void)clearProfileWhitelist
{
    OWSLogWarn(@"Clearing the profile whitelist.");

    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.whitelistedPhoneNumbersStore removeAllWithTransaction:transaction];
        [self.whitelistedUUIDsStore removeAllWithTransaction:transaction];
        [self.whitelistedGroupsStore removeAllWithTransaction:transaction];

        OWSAssertDebug(0 == [self.whitelistedPhoneNumbersStore numberOfKeysWithTransaction:transaction]);
        OWSAssertDebug(0 == [self.whitelistedUUIDsStore numberOfKeysWithTransaction:transaction]);
        OWSAssertDebug(0 == [self.whitelistedGroupsStore numberOfKeysWithTransaction:transaction]);
    }];
}

- (void)logProfileWhitelist
{
    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
        OWSLogError(@"kOWSProfileManager_UserPhoneNumberWhitelistCollection: %lu",
            (unsigned long)[self.whitelistedPhoneNumbersStore numberOfKeysWithTransaction:transaction]);
        for (NSString *key in [self.whitelistedPhoneNumbersStore allKeysWithTransaction:transaction]) {
            OWSLogError(@"\t profile whitelist user phone number: %@", key);
        }
        OWSLogError(@"kOWSProfileManager_UserUUIDWhitelistCollection: %lu",
            (unsigned long)[self.whitelistedUUIDsStore numberOfKeysWithTransaction:transaction]);
        for (NSString *key in [self.whitelistedUUIDsStore allKeysWithTransaction:transaction]) {
            OWSLogError(@"\t profile whitelist user uuid: %@", key);
        }
        OWSLogError(@"kOWSProfileManager_GroupWhitelistCollection: %lu",
            (unsigned long)[self.whitelistedGroupsStore numberOfKeysWithTransaction:transaction]);
        for (NSString *key in [self.whitelistedGroupsStore allKeysWithTransaction:transaction]) {
            OWSLogError(@"\t profile whitelist group: %@", key);
        }
    }];
}

- (void)debug_regenerateLocalProfileWithSneakyTransaction
{
    OWSUserProfile *userProfile = self.localUserProfile;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [userProfile clearWithProfileKey:[OWSAES256Key generateRandomKey] transaction:transaction completion:nil];
    }];
    [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];
}

- (void)setLocalProfileKey:(OWSAES256Key *)key transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSUserProfile *localUserProfile;
    
    @synchronized(self)
    {
        // If it didn't exist, create it in a safe way as accessing the property
        // will do a sneaky transaction.
        if (!_localUserProfile) {
            // We assert on the ivar directly here, as we want this to be cached already
            // by the time this method is called. If it's not, we've changed our caching
            // logic and should re-evalulate this method.
            OWSFailDebug(@"Missing local profile when setting key.");

            _localUserProfile = [OWSUserProfile getOrBuildUserProfileForAddress:OWSUserProfile.localProfileAddress transaction:transaction];
        }
        localUserProfile = _localUserProfile;
    }

    [localUserProfile clearWithProfileKey:key transaction:transaction completion:nil];
}

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    [self addUsersToProfileWhitelist:@[ address ]];
}

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
{
    OWSAssertDebug(addresses);

    // Try to avoid opening a write transaction.
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction * readTransaction) {
        NSMutableSet<SignalServiceAddress *> *newAddresses = [NSMutableSet new];
        for (SignalServiceAddress *address in addresses) {
            
            // Normally we add all system contacts to the whitelist, but we don't want to do that for
            // blocked contacts.
            if ([self.blockingManager isAddressBlocked:address]) {
                continue;
            }
            
            // We want to add both the UUID and the phone number to the white list.
            // It's possible we white listed one but not both, so we check each.
            
            BOOL shouldAdd = NO;
            if (address.uuidString) {
                BOOL currentlyWhitelisted =
                [self.whitelistedUUIDsStore hasValueForKey:address.uuidString transaction:readTransaction];
                if (!currentlyWhitelisted) {
                    shouldAdd = YES;
                }
            }
            
            if (address.phoneNumber) {
                BOOL currentlyWhitelisted =
                [self.whitelistedPhoneNumbersStore hasValueForKey:address.phoneNumber transaction:readTransaction];
                if (!currentlyWhitelisted) {
                    shouldAdd = YES;
                }
            }
            
            if (shouldAdd) {
                [newAddresses addObject:address];
            }
        }
        
        if (newAddresses.count < 1) {
            return;
        }
        
        [self.databaseStorage
         asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
             for (SignalServiceAddress *address in newAddresses) {
                 if (address.uuidString) {
                     [self.whitelistedUUIDsStore setBool:YES key:address.uuidString transaction:writeTransaction];
                 }
                 
                 if (address.phoneNumber) {
                     [self.whitelistedPhoneNumbersStore setBool:YES key:address.phoneNumber transaction:writeTransaction];
                 }
             }
         }
         completion:^{
             // Mark the new whitelisted addresses for update
             if (newAddresses.count > 0) {
                 [OWSStorageServiceManager.shared recordPendingUpdatesWithUpdatedAddresses:newAddresses.allObjects];
             }
             
             for (SignalServiceAddress *address in newAddresses) {
                 [[NSNotificationCenter defaultCenter]
                  postNotificationNameAsync:kNSNotificationName_ProfileWhitelistDidChange
                  object:nil
                  userInfo:@ {
                      kNSNotificationKey_ProfileAddress : address,
                  }];
             }
         }];
    }];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    [self removeUsersFromProfileWhitelist:@[ address ]];
}

- (void)removeUsersFromProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
{
    OWSAssertDebug(addresses);

    // Try to avoid opening a write transaction.
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *readTransaction) {
        NSMutableSet<SignalServiceAddress *> *removedAddresses = [NSMutableSet new];
        for (SignalServiceAddress *address in addresses) {

            // We want to remove both the UUID and the phone number from the white list.
            // It's possible we white listed one but not both, so we check each.

            BOOL shouldRemove = NO;
            if (address.uuidString) {
                BOOL currentlyWhitelisted = [self.whitelistedUUIDsStore hasValueForKey:address.uuidString
                                                                           transaction:readTransaction];
                if (currentlyWhitelisted) {
                    shouldRemove = YES;
                }
            }

            if (address.phoneNumber) {
                BOOL currentlyWhitelisted = [self.whitelistedPhoneNumbersStore hasValueForKey:address.phoneNumber
                                                                                  transaction:readTransaction];
                if (currentlyWhitelisted) {
                    shouldRemove = YES;
                }
            }

            if (shouldRemove) {
                [removedAddresses addObject:address];
            }
        }

        if (removedAddresses.count < 1) {
            return;
        }

        [self.databaseStorage
            asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
                for (SignalServiceAddress *address in removedAddresses) {
                    if (address.uuidString) {
                        [self.whitelistedUUIDsStore removeValueForKey:address.uuidString transaction:writeTransaction];
                    }

                    if (address.phoneNumber) {
                        [self.whitelistedPhoneNumbersStore removeValueForKey:address.phoneNumber
                                                                 transaction:writeTransaction];
                    }
                }
            }
            completion:^{
                // Mark the removed whitelisted addresses for update
                if (removedAddresses.count > 0) {
                    [OWSStorageServiceManager.shared
                        recordPendingUpdatesWithUpdatedAddresses:removedAddresses.allObjects];
                }

                for (SignalServiceAddress *address in removedAddresses) {
                    [[NSNotificationCenter defaultCenter]
                        postNotificationNameAsync:kNSNotificationName_ProfileWhitelistDidChange
                                           object:nil
                                         userInfo:@ {
                                             kNSNotificationKey_ProfileAddress : address,
                                         }];
                }
            }];
    }];
}

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    // isAddressBlocked can open a sneaky transaction in
    // BlockingManager.ensureLazyInitialization(), but we avoid this
    // by ensuring that BlockingManager.warmCaches() is always
    // called first, immediately after registering the database views.
    if ([self.blockingManager isAddressBlocked:address]) {
        return NO;
    }

    BOOL result = NO;
    if (address.uuidString) {
        result = [self.whitelistedUUIDsStore hasValueForKey:address.uuidString transaction:transaction];
    }

    if (!result && address.phoneNumber) {
        result = [self.whitelistedPhoneNumbersStore hasValueForKey:address.phoneNumber transaction:transaction];
    }
    return result;
}

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    // Try to avoid opening a write transaction.
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction * readTransaction) {
        if ([self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:readTransaction]) {
            // Do nothing.
            return;
        }
        [self.databaseStorage
         asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
             [self.whitelistedGroupsStore setBool:YES key:groupIdKey transaction:writeTransaction];
         }
         completion:^{
             [[NSNotificationCenter defaultCenter]
              postNotificationNameAsync:kNSNotificationName_ProfileWhitelistDidChange
              object:nil
              userInfo:@{
                         kNSNotificationKey_ProfileGroupId : groupId,
                         }];
         }];
    }];
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        [self addGroupIdToProfileWhitelist:groupId];

        // When we add a group to the profile whitelist, we might as well
        // also add all current members to the profile whitelist
        // individually as well just in case delivery of the profile key
        // fails.
        [self addUsersToProfileWhitelist:groupThread.recipientAddresses];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress];
    }
}

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    // isGroupIdBlocked can open a sneaky transaction in
    // BlockingManager.ensureLazyInitialization(), but we avoid this
    // by ensuring that BlockingManager.warmCaches() is always
    // called first.  I've added asserts within BlockingManager around
    // this.
    if ([self.blockingManager isGroupIdBlocked:groupId]) {
        return NO;
    }

    NSString *groupIdKey = [self groupKeyForGroupId:groupId];

    return [self.whitelistedGroupsStore hasValueForKey:groupIdKey transaction:transaction];
}

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        return [self isGroupIdInProfileWhitelist:groupId transaction:transaction];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self isUserInProfileWhitelist:contactThread.contactAddress transaction:transaction];
    }
}

- (void)setContactAddresses:(NSArray<SignalServiceAddress *> *)contactAddresses
{
    OWSAssertDebug(contactAddresses);

    [self addUsersToProfileWhitelist:contactAddresses];
}

#pragma mark - Other User's Profiles

- (void)logUserProfiles
{
    [self.databaseStorage asyncReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        OWSLogError(@"logUserProfiles: %ld", (unsigned long)[OWSUserProfile anyCountWithTransaction:transaction]);

        [OWSUserProfile anyEnumerateWithTransaction:transaction
                                            batched:YES
                                              block:^(OWSUserProfile *userProfile, BOOL *stop) {
                                                  OWSLogError(@"\t [%@]: has profile key: %d, has avatar URL: %d, has "
                                                              @"avatar file: %d, name: %@, username: %@",
                                                      userProfile.address,
                                                      userProfile.profileKey != nil,
                                                      userProfile.avatarUrlPath != nil,
                                                      userProfile.avatarFileName != nil,
                                                      userProfile.profileName,
                                                      userProfile.username);
                                              }];
    }];
}

- (void)setProfileKeyData:(NSData *)profileKeyData
               forAddress:(SignalServiceAddress *)address
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAES256Key *_Nullable profileKey = [OWSAES256Key keyWithData:profileKeyData];
    if (profileKey == nil) {
        OWSFailDebug(@"Failed to make profile key for key data");
        return;
    }

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];

    OWSAssertDebug(userProfile);
    if (userProfile.profileKey && [userProfile.profileKey.keyData isEqual:profileKey.keyData]) {
        // Ignore redundant update.
        return;
    }

    [userProfile
        clearWithProfileKey:profileKey
                transaction:transaction
                 completion:^{
                     dispatch_async(dispatch_get_main_queue(), ^{
                         [self.udManager setUnidentifiedAccessMode:UnidentifiedAccessModeUnknown address:address];
                         [self updateProfileForAddress:address];
                     });
                 }];
}

- (void)setProfileName:(nullable NSString *)profileName
            forAddress:(SignalServiceAddress *)address
           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];
    [userProfile updateWithProfileName:profileName transaction:transaction completion:nil];
}

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return [self profileKeyForAddress:address transaction:transaction].keyData;
}

- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.profileKey;
}

- (nullable NSString *)profileNameForAddress:(SignalServiceAddress *)address
                                 transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    return userProfile.profileName;
}

- (nullable UIImage *)profileAvatarForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileAvatarWithFilename:userProfile.avatarFileName];
    }

    if (userProfile.avatarUrlPath.length > 0) {
        [self downloadAvatarForUserProfile:userProfile noCdn:kAvatarDownloadNoCdn];
    }

    return nil;
}

- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileDataWithFilename:userProfile.avatarFileName];
    }

    return nil;
}

- (nullable NSString *)usernameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    OWSUserProfile *_Nullable userProfile = [self getUserProfileForAddress:address transaction:transaction];

    if (userProfile.username.length > 0) {
        return userProfile.username;
    }

    return nil;
}

- (nullable OWSUserProfile *)getUserProfileForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    // For "local reads", use the local user profile.
    return (address.isLocalAddress ? self.localUserProfile
                                   : [OWSUserProfile getUserProfileForAddress:address transaction:transaction]);
}

- (NSString *)generateAvatarFilename
{
    return [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
}

- (void)downloadAvatarForUserProfile:(OWSUserProfile *)userProfile
                               noCdn:(BOOL)noCdn
{
    OWSAssertDebug(userProfile);

    __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (userProfile.avatarUrlPath.length < 1) {
            OWSFailDebug(@"Malformed avatar URL: %@", userProfile.avatarUrlPath);
            return;
        }
        NSString *_Nullable avatarUrlPathAtStart = userProfile.avatarUrlPath;

        if (userProfile.profileKey.keyData.length < 1 || userProfile.avatarUrlPath.length < 1) {
            return;
        }

        OWSAES256Key *profileKeyAtStart = userProfile.profileKey;

        NSString *fileName = [self generateAvatarFilename];
        NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:fileName];

        @synchronized(self.currentAvatarDownloads)
        {
            if ([self.currentAvatarDownloads containsObject:userProfile.address]) {
                // Download already in flight; ignore.
                return;
            }
            [self.currentAvatarDownloads addObject:userProfile.address];
        }

        OWSLogVerbose(@"downloading profile avatar: %@", userProfile.uniqueId);

        NSString *tempDirectory = OWSTemporaryDirectory();
        NSString *tempFilePath = [tempDirectory stringByAppendingPathComponent:fileName];

        void (^completionHandler)(NSURLResponse *_Nonnull, NSURL *_Nullable, NSError *_Nullable) = ^(
            NSURLResponse *_Nonnull response, NSURL *_Nullable filePathParam, NSError *_Nullable error) {
            // Ensure disk IO and decryption occurs off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *_Nullable encryptedData = (error ? nil : [NSData dataWithContentsOfFile:tempFilePath]);
                NSData *_Nullable decryptedData = [self decryptProfileData:encryptedData profileKey:profileKeyAtStart];
                UIImage *_Nullable image = nil;
                if (decryptedData) {
                    BOOL success = [decryptedData writeToFile:filePath atomically:YES];
                    if (success) {
                        image = [UIImage imageWithContentsOfFile:filePath];
                    }
                }

                @synchronized(self.currentAvatarDownloads)
                {
                    [self.currentAvatarDownloads removeObject:userProfile.address];
                }

                __block OWSUserProfile *latestUserProfile;
                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                    latestUserProfile =
                        [OWSUserProfile getOrBuildUserProfileForAddress:userProfile.address transaction:transaction];
                }];

                if (latestUserProfile.profileKey.keyData.length < 1
                    || ![latestUserProfile.profileKey isEqual:userProfile.profileKey]) {
                    OWSLogWarn(@"Ignoring avatar download for obsolete user profile.");
                } else if (![avatarUrlPathAtStart isEqualToString:latestUserProfile.avatarUrlPath]) {
                    OWSLogInfo(@"avatar url has changed during download");
                    if (latestUserProfile.avatarUrlPath.length > 0) {
                        [self downloadAvatarForUserProfile:latestUserProfile noCdn:kAvatarDownloadNoCdn];
                    }
                } else if (error) {
                    if ([response isKindOfClass:NSHTTPURLResponse.class]
                        && ((NSHTTPURLResponse *)response).statusCode == 403) {
                        OWSLogInfo(@"no avatar for: %@", userProfile.address);
                    } else {
                        OWSLogError(@"avatar download for %@ failed with error: %@", userProfile.address, error);
                    }
                } else if (!encryptedData) {
                    OWSLogError(@"avatar encrypted data for %@ could not be read.", userProfile.address);
                } else if (!decryptedData) {
                    OWSLogError(@"avatar data for %@ could not be decrypted.", userProfile.address);
                } else if (!image) {
                    OWSLogError(@"avatar image for %@ could not be loaded with error: %@", userProfile.address, error);
                } else {
                    [self updateProfileAvatarCache:image filename:fileName];

                    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                        [latestUserProfile updateWithAvatarFileName:fileName transaction:transaction completion:nil];
                    }];
                }

                // If we're updating the profile that corresponds to our local number,
                // update the local profile as well.
                if (userProfile.address.isLocalAddress) {
                    OWSUserProfile *localUserProfile = self.localUserProfile;
                    OWSAssertDebug(localUserProfile);

                    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                        [localUserProfile updateWithAvatarFileName:fileName transaction:transaction completion:nil];
                    }];
                    [self updateProfileAvatarCache:image filename:fileName];
                }

                OWSAssertDebug(backgroundTask);
                backgroundTask = nil;
            });
        };

        if (noCdn) {
            [self getAvatarLocationNoCdn:userProfile tempFilePath:tempFilePath completionHandler:completionHandler];
        } else {
            [self downloadAvatarFromService:userProfile tempFilePath:tempFilePath completionHandler:completionHandler location:nil];
        }
    });
}

- (void)getAvatarLocationNoCdn:(OWSUserProfile *)userProfile
                  tempFilePath:(NSString *)tempFilePath
             completionHandler:(void (^)(NSURLResponse *_Nonnull, NSURL *_Nullable, NSError *_Nullable))completionHandler
{
    OWSAssertDebug(userProfile);
    
    TSRequest *formRequest = [OWSRequestFactory profileAvatarRetrieveRequestNoCdn:userProfile.avatarUrlPath];
    
    [self.networkManager makeRequest:formRequest
        success:^(NSURLSessionDataTask *task, id _Nullable formResponseObject) {
            if (![formResponseObject isKindOfClass:[NSDictionary class]]) {
                OWSFailDebug(@"Invalid avatar form.");
                return;
            }
            NSDictionary *responseMap = formResponseObject;

            NSString *_Nullable location = responseMap[@"location"];
            if (![location isKindOfClass:[NSString class]] || location.length < 1) {
                OWSFailDebug(@"Invalid avatar form: location.");
                return;
            }
        
            [self downloadAvatarFromService:userProfile tempFilePath:tempFilePath completionHandler:completionHandler location:location];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            OWSLogError(@"Failed to get avatar form: %@", error);
        }];
}

- (void)downloadAvatarFromService:(OWSUserProfile *)userProfile
                     tempFilePath:(NSString *)tempFilePath
                completionHandler:(void (^)(NSURLResponse *_Nonnull, NSURL *_Nullable, NSError *_Nullable))completionHandler
                         location:(nullable NSString *)location
{
    OWSAssertDebug(userProfile);
    OWSAssertDebug(tempFilePath);
    
    AFHTTPSessionManager *manager;
    NSURL *avatarUrl;
    
    if (location.length > 0) {
        manager = self.noCdnSessionManager;
        avatarUrl = [[NSURL alloc] initWithString:location];
    } else {
        manager = self.avatarHTTPManager;
        avatarUrl = [NSURL URLWithString:userProfile.avatarUrlPath relativeToURL:self.avatarHTTPManager.baseURL];
    }
    
    NSError *serializationError;
    NSMutableURLRequest *request =
        [self.avatarHTTPManager.requestSerializer requestWithMethod:@"GET"
                                                          URLString:avatarUrl.absoluteString
                                                         parameters:nil
                                                              error:&serializationError];
    if (location.length > 0) {
        [request setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];
    }
    if (serializationError) {
        OWSFailDebug(@"serializationError: %@", serializationError);
        return;
    }

    __block NSURLSessionDownloadTask *downloadTask = [manager downloadTaskWithRequest:request
        progress:^(NSProgress *_Nonnull downloadProgress) {
            OWSLogVerbose(@"Downloading avatar for %@ %f", userProfile.address, downloadProgress.fractionCompleted);
        }
        destination:^NSURL *_Nonnull(NSURL *_Nonnull targetPath, NSURLResponse *_Nonnull response) {
            return [NSURL fileURLWithPath:tempFilePath];
        }
        completionHandler:completionHandler];
    [downloadTask resume];
}

- (void)updateProfileForAddress:(SignalServiceAddress *)address
           profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                       username:(nullable NSString *)username
                  avatarUrlPath:(nullable NSString *)avatarUrlPath
{
    OWSAssertDebug(address.isValid);

    OWSLogDebug(@"update profile for: %@ name: %@ avatar: %@", address, profileNameEncrypted, avatarUrlPath);

    // Ensure decryption, etc. off main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSUserProfile *localUserProfile = self.localUserProfile;
        OWSAssertDebug(localUserProfile);

        __block OWSUserProfile *userProfile;
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            userProfile = [OWSUserProfile getOrBuildUserProfileForAddress:address transaction:transaction];

            // If we're updating the profile that corresponds to our local number,
            // make sure we're using the latest key.
            if (address.isLocalAddress) {
                [userProfile updateWithProfileKey:self.localUserProfile.profileKey
                                      transaction:transaction
                                       completion:nil];
            }

            if (!userProfile.profileKey) {
                [userProfile updateWithUsername:username transaction:transaction];
                return;
            }

            // Decryption is slightly expensive to do inside this write transaction.
            NSString *_Nullable profileName =
                [self decryptProfileNameData:profileNameEncrypted profileKey:userProfile.profileKey];

            [userProfile updateWithProfileName:profileName
                                      username:username
                                 avatarUrlPath:avatarUrlPath
                                   transaction:transaction
                                    completion:nil];

            // If we're updating the profile that corresponds to our local number,
            // update the local profile as well.
            if (address.isLocalAddress) {
                [localUserProfile updateWithProfileName:profileName
                                               username:username
                                          avatarUrlPath:avatarUrlPath
                                            transaction:transaction
                                             completion:nil];
            }
        }];

        // Whenever we change avatarUrlPath, OWSUserProfile clears avatarFileName.
        // So if avatarUrlPath is set and avatarFileName is not set, we should to
        // download this avatar. downloadAvatarForUserProfile will de-bounce
        // downloads.
        if (userProfile.avatarUrlPath.length > 0 && userProfile.avatarFileName.length < 1) {
            [self downloadAvatarForUserProfile:userProfile noCdn:kAvatarDownloadNoCdn];
        }
    });
}

- (BOOL)isNullableDataEqual:(NSData *_Nullable)left toData:(NSData *_Nullable)right
{
    if (left == nil && right == nil) {
        return YES;
    } else if (left == nil || right == nil) {
        return YES;
    } else {
        return [left isEqual:right];
    }
}

- (BOOL)isNullableStringEqual:(NSString *_Nullable)left toString:(NSString *_Nullable)right
{
    if (left == nil && right == nil) {
        return YES;
    } else if (left == nil || right == nil) {
        return YES;
    } else {
        return [left isEqualToString:right];
    }
}

#pragma mark - Profile Encryption

- (nullable NSData *)encryptProfileData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssertDebug(profileKey.keyData.length == kAES256_KeyByteLength);

    if (!encryptedData) {
        return nil;
    }

    return [Cryptography encryptAESGCMWithProfileData:encryptedData key:profileKey];
}

- (nullable NSData *)decryptProfileData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssertDebug(profileKey.keyData.length == kAES256_KeyByteLength);

    if (!encryptedData) {
        return nil;
    }

    return [Cryptography decryptAESGCMWithProfileData:encryptedData key:profileKey];
}

- (nullable NSString *)decryptProfileNameData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssertDebug(profileKey.keyData.length == kAES256_KeyByteLength);

    NSData *_Nullable decryptedData = [self decryptProfileData:encryptedData profileKey:profileKey];
    if (decryptedData.length < 1) {
        return nil;
    }


    // Unpad profile name.
    NSUInteger unpaddedLength = 0;
    const char *bytes = decryptedData.bytes;

    // Work through the bytes until we encounter our first
    // padding byte (our padding scheme is NULL bytes)
    for (NSUInteger i = 0; i < decryptedData.length; i++) {
        if (bytes[i] == 0x00) {
            break;
        }
        unpaddedLength = i + 1;
    }

    NSData *unpaddedData = [decryptedData subdataWithRange:NSMakeRange(0, unpaddedLength)];

    return [[NSString alloc] initWithData:unpaddedData encoding:NSUTF8StringEncoding];
}

- (nullable NSData *)encryptProfileData:(nullable NSData *)data
{
    return [self encryptProfileData:data profileKey:self.localProfileKey];
}

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName
{
    OWSAssertIsOnMainThread();

    NSData *nameData = [profileName dataUsingEncoding:NSUTF8StringEncoding];
    return nameData.length > kOWSProfileManager_NameDataLength;
}

- (nullable NSData *)encryptProfileNameWithUnpaddedName:(NSString *)name
{
    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (nameData.length > kOWSProfileManager_NameDataLength) {
        OWSFailDebug(@"name data is too long with length:%lu", (unsigned long)nameData.length);
        return nil;
    }

    NSUInteger paddingByteCount = kOWSProfileManager_NameDataLength - nameData.length;

    NSMutableData *paddedNameData = [nameData mutableCopy];
    // Since we want all encrypted profile names to be the same length on the server, we use `increaseLengthBy`
    // to pad out any remaining length with 0 bytes.
    [paddedNameData increaseLengthBy:paddingByteCount];
    OWSAssertDebug(paddedNameData.length == kOWSProfileManager_NameDataLength);

    return [self encryptProfileData:[paddedNameData copy] profileKey:self.localProfileKey];
}

#pragma mark - Avatar Disk Cache

- (nullable NSData *)loadProfileDataWithFilename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:filename];
    return [NSData dataWithContentsOfFile:filePath];
}

- (nullable UIImage *)loadProfileAvatarWithFilename:(NSString *)filename
{
    if (filename.length == 0) {
        return nil;
    }

    UIImage *_Nullable image = nil;
    @synchronized(self.profileAvatarImageCache)
    {
        image = [self.profileAvatarImageCache objectForKey:filename];
    }
    if (image) {
        return image;
    }

    NSData *data = [self loadProfileDataWithFilename:filename];
    if (![data ows_isValidImage]) {
        return nil;
    }
    image = [UIImage imageWithData:data];
    [self updateProfileAvatarCache:image filename:filename];
    return image;
}

- (void)updateProfileAvatarCache:(nullable UIImage *)image filename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    @synchronized(self.profileAvatarImageCache)
    {
        if (image) {
            [self.profileAvatarImageCache setObject:image forKey:filename];
        } else {
            [self.profileAvatarImageCache removeObjectForKey:filename];
        }
    }
}

#pragma mark - User Interface

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler
{
    OWSAssertIsOnMainThread();

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:nil message:nil];

    NSString *shareTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE",
        @"Button to confirm that user wants to share their profile with a user or group.");
    [actionSheet
        addAction:[[ActionSheetAction alloc] initWithTitle:shareTitle
                                   accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"share_profile")
                                                     style:ActionSheetActionStyleDefault
                                                   handler:^(ActionSheetAction *_Nonnull action) {
                                                       [self userAddedThreadToProfileWhitelist:thread];
                                                       successHandler();
                                                   }]];
    [actionSheet addAction:[OWSActionSheets cancelAction]];

    [fromViewController presentActionSheet:actionSheet];
}

- (void)userAddedThreadToProfileWhitelist:(TSThread *)thread
{
    OWSAssertIsOnMainThread();

    BOOL isFeatureEnabled = NO;
    if (!isFeatureEnabled) {
        OWSLogWarn(@"skipping sending profile-key message because the feature is not yet fully available.");
        [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];
        return;
    }

    // MJK TODO - should be safe to remove this senderTimestamp
    OWSProfileKeyMessage *message = [[OWSProfileKeyMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                           inThread:thread];
    [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    }];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // TODO: Sync if necessary.
}

- (void)blockListDidChange:(NSNotification *)notification {
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self rotateLocalProfileKeyIfNecessary];
    }];
}

#pragma mark - Clean Up

+ (NSSet<NSString *> *)allProfileAvatarFilePathsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSUserProfile allProfileAvatarFilePathsWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
