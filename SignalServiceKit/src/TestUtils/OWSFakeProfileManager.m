//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeProfileManager.h"
#import "TSThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeProfileManager ()

@property (nonatomic, readonly) NSMutableDictionary<SignalServiceAddress *, OWSAES256Key *> *profileKeys;
@property (nonatomic, readonly) NSMutableSet<SignalServiceAddress *> *recipientWhitelist;
@property (nonatomic, readonly) NSMutableSet<NSString *> *threadWhitelist;
@property (nonatomic, readonly) OWSAES256Key *localProfileKey;

@end

#pragma mark -

@implementation OWSFakeProfileManager

@synthesize localProfileKey = _localProfileKey;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _profileKeys = [NSMutableDictionary new];
    _recipientWhitelist = [NSMutableSet new];
    _threadWhitelist = [NSMutableSet new];

    return self;
}

- (OWSAES256Key *)localProfileKey
{
    if (_localProfileKey == nil) {
        _localProfileKey = [OWSAES256Key generateRandomKey];
    }
    return _localProfileKey;
}

- (void)setProfileKeyData:(NSData *)profileKey
               forAddress:(SignalServiceAddress *)address
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAES256Key *_Nullable key = [OWSAES256Key keyWithData:profileKey];
    OWSAssert(key);
    self.profileKeys[address] = key;
}

- (void)setProfileName:(nullable NSString *)profileName
            forAddress:(SignalServiceAddress *)address
           transaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return self.profileKeys[address].keyData;
}

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.recipientWhitelist containsObject:address];
}

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.threadWhitelist containsObject:thread.uniqueId];
}

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
{
    [self.recipientWhitelist addObject:address];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
{
    [self.recipientWhitelist removeObject:address];
}

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
{
    [self.threadWhitelist addObject:groupId.hexadecimalString];
}

- (void)fetchAndUpdateLocalUsersProfile
{
    // Do nothing.
}

- (void)updateProfileForAddress:(nonnull SignalServiceAddress *)address
{
    // Do nothing.
}

- (void)warmCaches
{
    // Do nothing.
}

@end

#endif

NS_ASSUME_NONNULL_END
