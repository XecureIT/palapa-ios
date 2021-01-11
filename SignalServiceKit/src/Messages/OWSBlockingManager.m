//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSBlockingManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBlockedPhoneNumbersMessage.h"
#import "OWSMessageSender.h"
#import "SSKEnvironment.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const kNSNotificationName_BlockListDidChange = @"kNSNotificationName_BlockListDidChange";
NSNotificationName const OWSBlockingManagerBlockedSyncDidComplete = @"OWSBlockingManagerBlockedSyncDidComplete";

// These keys are used to persist the current local "block list" state.
NSString *const kOWSBlockingManager_BlockedPhoneNumbersKey = @"kOWSBlockingManager_BlockedPhoneNumbersKey";
NSString *const kOWSBlockingManager_BlockedUUIDsKey = @"kOWSBlockingManager_BlockedUUIDsKey";
NSString *const kOWSBlockingManager_BlockedGroupMapKey = @"kOWSBlockingManager_BlockedGroupMapKey";

// These keys are used to persist the most recently synced remote "block list" state.
NSString *const kOWSBlockingManager_SyncedBlockedPhoneNumbersKey = @"kOWSBlockingManager_SyncedBlockedPhoneNumbersKey";
NSString *const kOWSBlockingManager_SyncedBlockedUUIDsKey = @"kOWSBlockingManager_SyncedBlockedUUIDsKey";
NSString *const kOWSBlockingManager_SyncedBlockedGroupIdsKey = @"kOWSBlockingManager_SyncedBlockedGroupIdsKey";

@interface OWSBlockingManager ()

// We don't store the phone numbers as instances of PhoneNumber to avoid
// consistency issues between clients, but these should all be valid e164
// phone numbers.
@property (atomic, readonly) NSMutableSet<NSString *> *blockedPhoneNumberSet;
@property (atomic, readonly) NSMutableSet<NSString *> *blockedUUIDSet;
@property (atomic, readonly) NSMutableDictionary<NSData *, TSGroupModel *> *blockedGroupMap;

@end

#pragma mark -

@implementation OWSBlockingManager

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (id<StorageServiceManagerProtocol>)storageServiceManager
{
    return SSKEnvironment.shared.storageServiceManager;
}

#pragma mark -

+ (SDSKeyValueStore *)keyValueStore
{
    NSString *const kOWSBlockingManager_BlockListCollection = @"kOWSBlockingManager_BlockedPhoneNumbersCollection";
    return [[SDSKeyValueStore alloc] initWithCollection:kOWSBlockingManager_BlockListCollection];
}

#pragma mark -

+ (instancetype)sharedManager
{
    OWSAssertDebug(SSKEnvironment.shared.blockingManager);

    return SSKEnvironment.shared.blockingManager;
}

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();
    
    [AppReadiness runNowOrWhenAppWillBecomeReady:^{
        [self ensureLazyInitializationOnLaunch];
    }];

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
}

- (OWSMessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (void)warmCaches
{
    [self ensureLazyInitializationOnLaunch];
}

- (void)ensureLazyInitializationOnLaunch
{
    @synchronized(self)
    {
        [self ensureLazyInitialization];
    }
}

#pragma mark -

- (BOOL)isThreadBlocked:(TSThread *)thread
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self isAddressBlocked:contactThread.contactAddress];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return [self isGroupIdBlocked:groupThread.groupModel.groupId];
    } else {
        OWSFailDebug(@"%@ failure unexpected thread type", self.logTag);
        return NO;
    }
}

#pragma mark - Contact Blocking

- (NSSet<SignalServiceAddress *> *)blockedAddresses
{
    NSMutableSet *blockedAddresses = [NSMutableSet new];
    for (NSString *phoneNumber in self.blockedPhoneNumbers) {
        [blockedAddresses addObject:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
    }
    for (NSString *uuid in self.blockedUUIDs) {
        [blockedAddresses addObject:[[SignalServiceAddress alloc] initWithUuidString:uuid phoneNumber:nil]];
    }
    // TODO UUID - optimize this. Maybe blocking manager should store a SignalServiceAddressSet as
    // it's state instead of the two separate sets.
    return blockedAddresses;
}

- (void)addBlockedAddressLocally:(SignalServiceAddress *)address wasLocallyInitiated:(BOOL)wasLocallyInitiated;
{
    OWSAssertDebug(address.isValid);

    OWSLogInfo(@"addBlockedAddress: %@", address);

    BOOL wasBlocked = [self isAddressBlocked:address];

    @synchronized(self)
    {
        [self ensureLazyInitialization];

        if (address.phoneNumber && ![_blockedPhoneNumberSet containsObject:address.phoneNumber]) {
            [_blockedPhoneNumberSet addObject:address.phoneNumber];
        }

        if (address.uuidString && ![_blockedUUIDSet containsObject:address.uuidString]) {
            [_blockedUUIDSet addObject:address.uuidString];
        }
    }

    if (wasLocallyInitiated && wasBlocked != [self isAddressBlocked:address]) {
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAddresses:@[ address ]];
    }
}

- (void)addBlockedAddress:(SignalServiceAddress *)address wasLocallyInitiated:(BOOL)wasLocallyInitiated;
{
    [self addBlockedAddressLocally:address wasLocallyInitiated:wasLocallyInitiated];
    [self handleUpdateWithSneakyTransactionAndSendSyncMessage:wasLocallyInitiated];
}

- (void)addBlockedAddress:(SignalServiceAddress *)address
      wasLocallyInitiated:(BOOL)wasLocallyInitiated
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [self addBlockedAddressLocally:address wasLocallyInitiated:wasLocallyInitiated];

    [self handleUpdateAndSendSyncMessage:wasLocallyInitiated transaction:transaction];
}

- (void)removeBlockedAddressLocally:(SignalServiceAddress *)address wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    OWSAssertDebug(address.isValid);

    OWSLogInfo(@"removeBlockedAddress: %@", address);

    BOOL wasBlocked = [self isAddressBlocked:address];

    @synchronized(self)
    {
        [self ensureLazyInitialization];

        if (address.phoneNumber && [_blockedPhoneNumberSet containsObject:address.phoneNumber]) {
            [_blockedPhoneNumberSet removeObject:address.phoneNumber];
        }

        if (address.uuidString && [_blockedUUIDSet containsObject:address.uuidString]) {
            [_blockedUUIDSet removeObject:address.uuidString];
        }
    }

    // The block state changed, schedule a backup with the storage service
    if (wasLocallyInitiated && wasBlocked != [self isAddressBlocked:address]) {
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAddresses:@[ address ]];
    }
}

- (void)removeBlockedAddress:(SignalServiceAddress *)address wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    [self removeBlockedAddressLocally:address wasLocallyInitiated:wasLocallyInitiated];
    [self handleUpdateWithSneakyTransactionAndSendSyncMessage:wasLocallyInitiated];
}

- (void)removeBlockedAddress:(SignalServiceAddress *)address
         wasLocallyInitiated:(BOOL)wasLocallyInitiated
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [self removeBlockedAddressLocally:address wasLocallyInitiated:wasLocallyInitiated];

    [self handleUpdateAndSendSyncMessage:wasLocallyInitiated transaction:transaction];
}

- (void)processIncomingSyncWithBlockedPhoneNumbers:(nullable NSSet<NSString *> *)blockedPhoneNumbers
                                      blockedUUIDs:(nullable NSSet<NSUUID *> *)blockedUUIDs
                                   blockedGroupIds:(nullable NSSet<NSData *> *)blockedGroupIds
                                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSLogInfo(@"");

    [transaction addCompletionWithBlock:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:OWSBlockingManagerBlockedSyncDidComplete object:nil];
    }];

    BOOL hasGroupChanges = NO;

    @synchronized(self)
    {
        // this could deadlock
        [self ensureLazyInitialization];

        BOOL hasChanges = NO;

        if (blockedPhoneNumbers != nil && ![_blockedPhoneNumberSet isEqualToSet:blockedPhoneNumbers]) {
            hasChanges = YES;
            _blockedPhoneNumberSet = [blockedPhoneNumbers mutableCopy];
        }

        if (blockedUUIDs != nil) {
            NSMutableSet<NSString *> *blockedUUIDstrings = [NSMutableSet new];
            for (NSUUID *uuid in blockedUUIDs) {
                // since we store uuidStrings, rather than UUIDs, we need to
                // be sure to round-trip any foreign input to ensure consistent
                // serialization.
                OWSAssertDebug([uuid isKindOfClass:[NSUUID class]]);
                [blockedUUIDstrings addObject:uuid.UUIDString];
            }
            if (![_blockedUUIDSet isEqualToSet:blockedUUIDstrings]) {
                hasChanges = YES;
                _blockedUUIDSet = blockedUUIDstrings;
            }
        }

        if (blockedGroupIds != nil && ![[NSSet setWithArray:_blockedGroupMap.allKeys] isEqualToSet:blockedGroupIds]) {
            hasChanges = YES;
            hasGroupChanges = YES;
        }

        if (!hasChanges) {
            return;
        }
    }

    // Re-generate the group map only if the groupIds have changed.
    if (hasGroupChanges) {
        NSMutableDictionary<NSData *, TSGroupModel *> *newGroupMap = [NSMutableDictionary new];

        for (NSData *groupId in blockedGroupIds) {
            TSGroupThread *groupThread = [TSGroupThread getOrCreateThreadWithGroupId:groupId transaction:transaction];
            newGroupMap[groupId] = groupThread.groupModel;
        }

        @synchronized(self) {
            _blockedGroupMap = newGroupMap;
        }
    }

    [self handleUpdateAndSendSyncMessage:NO transaction:transaction];
}

- (NSArray<NSString *> *)blockedPhoneNumbers
{
    @synchronized(self)
    {
        [self ensureLazyInitialization];

        return [_blockedPhoneNumberSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }
}

- (NSArray<NSString *> *)blockedUUIDs
{
    @synchronized(self) {
        [self ensureLazyInitialization];

        return [_blockedUUIDSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }
}

- (BOOL)isAddressBlocked:(SignalServiceAddress *)address
{
    OWSAssertDebug(self.isInitialized);

    return [self.blockedPhoneNumbers containsObject:address.phoneNumber] ||
        [self.blockedUUIDs containsObject:address.uuidString];
}

#pragma mark - Group Blocking

- (NSArray<NSData *> *)blockedGroupIds
{
    @synchronized(self) {
        [self ensureLazyInitialization];
        return self.blockedGroupMap.allKeys;
    }
}

- (NSArray<TSGroupModel *> *)blockedGroups
{
    @synchronized(self) {
        [self ensureLazyInitialization];
        return self.blockedGroupMap.allValues;
    }
}

- (BOOL)isGroupIdBlocked:(NSData *)groupId
{
    OWSAssertDebug(self.isInitialized);

    return self.blockedGroupMap[groupId] != nil;
}

- (nullable TSGroupModel *)cachedGroupDetailsWithGroupId:(NSData *)groupId
{
    @synchronized(self) {
        return self.blockedGroupMap[groupId];
    }
}

- (void)addBlockedGroup:(TSGroupModel *)groupModel wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    NSData *groupId = groupModel.groupId;
    OWSAssertDebug(groupId.length > 0);

    OWSLogInfo(@"groupId: %@", groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if ([self isGroupIdBlocked:groupId]) {
            // Ignore redundant changes.
            return;
        }
        self.blockedGroupMap[groupId] = groupModel;
    }

    [self handleUpdateWithSneakyTransactionAndSendSyncMessage:wasLocallyInitiated];
}

- (void)addBlockedGroup:(TSGroupModel *)groupModel
    wasLocallyInitiated:(BOOL)wasLocallyInitiated
            transaction:(SDSAnyWriteTransaction *)transaction
{
    NSData *groupId = groupModel.groupId;
    OWSAssertDebug(groupId.length > 0);

    OWSLogInfo(@"groupId: %@", groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if ([self isGroupIdBlocked:groupId]) {
            // Ignore redundant changes.
            return;
        }
        self.blockedGroupMap[groupId] = groupModel;
    }

    [self handleUpdateAndSendSyncMessage:wasLocallyInitiated transaction:transaction];
}

- (void)removeBlockedGroupId:(NSData *)groupId wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    OWSAssertDebug(groupId.length > 0);

    OWSLogInfo(@"groupId: %@", groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if (![self isGroupIdBlocked:groupId]) {
            // Ignore redundant changes.
            return;
        }

        [self.blockedGroupMap removeObjectForKey:groupId];
    }

    [self handleUpdateWithSneakyTransactionAndSendSyncMessage:wasLocallyInitiated];
}

- (void)removeBlockedGroupId:(NSData *)groupId
         wasLocallyInitiated:(BOOL)wasLocallyInitiated
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    OWSLogInfo(@"groupId: %@", groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if (![self isGroupIdBlocked:groupId]) {
            // Ignore redundant changes.
            return;
        }

        [self.blockedGroupMap removeObjectForKey:groupId];
    }

    [self handleUpdateAndSendSyncMessage:wasLocallyInitiated transaction:transaction];
}


#pragma mark - Thread Blocking

- (void)addBlockedThread:(TSThread *)thread wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    if (thread.isGroupThread) {
        OWSAssertDebug([thread isKindOfClass:[TSGroupThread class]]);
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self addBlockedGroup:groupThread.groupModel wasLocallyInitiated:wasLocallyInitiated];
    } else {
        OWSAssertDebug([thread isKindOfClass:[TSContactThread class]]);
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addBlockedAddress:contactThread.contactAddress wasLocallyInitiated:wasLocallyInitiated];
    }
}

- (void)removeBlockedThread:(TSThread *)thread wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    if (thread.isGroupThread) {
        OWSAssertDebug([thread isKindOfClass:[TSGroupThread class]]);
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self removeBlockedGroupId:groupThread.groupModel.groupId wasLocallyInitiated:wasLocallyInitiated];
    } else {
        OWSAssertDebug([thread isKindOfClass:[TSContactThread class]]);
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self removeBlockedAddress:contactThread.contactAddress wasLocallyInitiated:wasLocallyInitiated];
    }
}

#pragma mark - Updates

// This should be called every time the block list changes.

- (void)handleUpdateWithSneakyTransactionAndSendSyncMessage:(BOOL)sendSyncMessage
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self handleUpdateAndSendSyncMessage:sendSyncMessage transaction:transaction];
    }];
}

- (void)handleUpdateAndSendSyncMessage:(BOOL)sendSyncMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    NSArray<NSString *> *blockedPhoneNumbers = [self blockedPhoneNumbers];
    NSArray<NSString *> *blockedUUIDs = [self blockedUUIDs];

    NSDictionary *blockedGroupMap;
    @synchronized(self) {
        blockedGroupMap = [self.blockedGroupMap copy];
    }
    NSArray<NSData *> *blockedGroupIds = blockedGroupMap.allKeys;

    [OWSBlockingManager.keyValueStore setObject:blockedPhoneNumbers
                                            key:kOWSBlockingManager_BlockedPhoneNumbersKey
                                    transaction:transaction];
    [OWSBlockingManager.keyValueStore setObject:blockedUUIDs
                                            key:kOWSBlockingManager_BlockedUUIDsKey
                                    transaction:transaction];
    [OWSBlockingManager.keyValueStore setObject:blockedGroupMap
                                            key:kOWSBlockingManager_BlockedGroupMapKey
                                    transaction:transaction];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (sendSyncMessage) {
            [self sendBlockListSyncMessageWithPhoneNumbers:blockedPhoneNumbers
                                                     uuids:blockedUUIDs
                                                  groupIds:blockedGroupIds];
        } else {
            // If this update came from an incoming block list sync message,
            // update the "synced blocked list" state immediately,
            // since we're now in sync.
            //
            // There could be data loss if both clients modify the block list
            // at the same time, but:
            //
            // a) Block list changes will be rare.
            // b) Conflicting block list changes will be even rarer.
            // c) It's unlikely a user will make conflicting changes on two
            //    devices around the same time.
            // d) There isn't a good way to avoid this.
            [self saveSyncedBlockListWithPhoneNumbers:blockedPhoneNumbers uuids:blockedUUIDs groupIds:blockedGroupIds];
        }

        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_BlockListDidChange
                                                                 object:nil
                                                               userInfo:nil];
    });
}

// This method should only be called from within a synchronized block.
- (BOOL)isInitialized
{
    @synchronized(self) {
        return _blockedPhoneNumberSet != nil;
    }
}

// This method should only be called from within a synchronized block.
- (void)ensureLazyInitialization
{
    if (_blockedPhoneNumberSet != nil) {
        OWSAssertDebug(_blockedGroupMap);
        OWSAssertDebug(_blockedUUIDSet);

        // already loaded
        return;
    }

    OWSLogVerbose(@"");
    __block NSArray<NSString *> *_Nullable blockedPhoneNumbers;
    __block NSArray<NSString *> *blockedUUIDs;
    __block NSDictionary<NSData *, TSGroupModel *> *storedBlockedGroupMap;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        blockedPhoneNumbers = [OWSBlockingManager.keyValueStore getObject:kOWSBlockingManager_BlockedPhoneNumbersKey
                                                              transaction:transaction];
        blockedUUIDs =
            [OWSBlockingManager.keyValueStore getObject:kOWSBlockingManager_BlockedUUIDsKey transaction:transaction];
        storedBlockedGroupMap =
            [OWSBlockingManager.keyValueStore getObject:kOWSBlockingManager_BlockedGroupMapKey transaction:transaction];
    }];
    _blockedPhoneNumberSet = [[NSMutableSet alloc] initWithArray:(blockedPhoneNumbers ?: @[])];
    _blockedUUIDSet = [[NSMutableSet alloc] initWithArray:(blockedUUIDs ?: @[])];

    if ([storedBlockedGroupMap isKindOfClass:[NSDictionary class]]) {
        _blockedGroupMap = [storedBlockedGroupMap mutableCopy];
    } else {
        _blockedGroupMap = [NSMutableDictionary new];
    }

    [self syncBlockListIfNecessary];
    [self observeNotifications];
}

- (void)syncBlockList
{
    OWSAssertDebug(_blockedPhoneNumberSet);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self sendBlockListSyncMessageWithPhoneNumbers:self.blockedPhoneNumbers
                                                 uuids:self.blockedUUIDs
                                              groupIds:self.blockedGroupIds];
    });
}

// This method should only be called from within a synchronized block.
- (void)syncBlockListIfNecessary
{
    OWSAssertDebug(_blockedPhoneNumberSet);

    // If we haven't yet successfully synced the current "block list" changes,
    // try again to sync now.
    __block NSArray<NSString *> *syncedBlockedPhoneNumbers;
    __block NSArray<NSString *> *syncedBlockedUUIDs;
    __block NSArray<NSData *> *syncedBlockedGroupIds;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        syncedBlockedPhoneNumbers =
            [OWSBlockingManager.keyValueStore getObject:kOWSBlockingManager_SyncedBlockedPhoneNumbersKey
                                            transaction:transaction];
        syncedBlockedUUIDs = [OWSBlockingManager.keyValueStore getObject:kOWSBlockingManager_SyncedBlockedUUIDsKey
                                                             transaction:transaction];
        syncedBlockedGroupIds = [OWSBlockingManager.keyValueStore getObject:kOWSBlockingManager_SyncedBlockedGroupIdsKey
                                                                transaction:transaction];
    }];

    NSSet<NSString *> *syncedBlockedPhoneNumberSet = [[NSSet alloc] initWithArray:(syncedBlockedPhoneNumbers ?: @[])];
    NSSet<NSString *> *syncedBlockedUUIDsSet = [[NSSet alloc] initWithArray:(syncedBlockedUUIDs ?: @[])];
    NSSet<NSData *> *syncedBlockedGroupIdSet = [[NSSet alloc] initWithArray:(syncedBlockedGroupIds ?: @[])];

    NSArray<NSData *> *localBlockedGroupIds = self.blockedGroupIds;
    NSSet<NSData *> *localBlockedGroupIdSet = [[NSSet alloc] initWithArray:localBlockedGroupIds];

    if ([self.blockedPhoneNumberSet isEqualToSet:syncedBlockedPhoneNumberSet] &&
        [self.blockedUUIDSet isEqualToSet:syncedBlockedUUIDsSet] &&
        [localBlockedGroupIdSet isEqualToSet:syncedBlockedGroupIdSet]) {
        OWSLogVerbose(@"Ignoring redundant block list sync");
        return;
    }

    OWSLogInfo(@"retrying sync of block list");
    [self sendBlockListSyncMessageWithPhoneNumbers:self.blockedPhoneNumbers
                                             uuids:self.blockedUUIDs
                                          groupIds:localBlockedGroupIds];
}

- (void)sendBlockListSyncMessageWithPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
                                           uuids:(NSArray<NSString *> *)blockedUUIDs
                                        groupIds:(NSArray<NSData *> *)blockedGroupIds
{
    OWSAssertDebug(blockedPhoneNumbers);
    OWSAssertDebug(blockedUUIDs);
    OWSAssertDebug(blockedGroupIds);

    __block TSThread *_Nullable thread;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        thread = [TSAccountManager getOrCreateLocalThreadWithTransaction:transaction];
    }];
    if (thread == nil) {
        OWSFailDebug(@"Missing thread.");
        return;
    }

    OWSBlockedPhoneNumbersMessage *message = [[OWSBlockedPhoneNumbersMessage alloc] initWithThread:thread
                                                                                      phoneNumbers:blockedPhoneNumbers
                                                                                             uuids:blockedUUIDs
                                                                                          groupIds:blockedGroupIds];

    [self.messageSender sendMessage:message.asPreparer
        success:^{
            OWSLogInfo(@"Successfully sent blocked phone numbers sync message");

            // DURABLE CLEANUP - we could replace the custom durability logic in this class
            // with a durable JobQueue.
            [self saveSyncedBlockListWithPhoneNumbers:blockedPhoneNumbers uuids:blockedUUIDs groupIds:blockedGroupIds];
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to send blocked phone numbers sync message with error: %@", error);
        }];
}

/// Records the last block list which we successfully synced.
- (void)saveSyncedBlockListWithPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
                                      uuids:(NSArray<NSString *> *)blockedUUIDs
                                   groupIds:(NSArray<NSData *> *)blockedGroupIds
{
    OWSAssertDebug(blockedPhoneNumbers);
    OWSAssertDebug(blockedUUIDs);
    OWSAssertDebug(blockedGroupIds);

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [OWSBlockingManager.keyValueStore setObject:blockedPhoneNumbers
                                                key:kOWSBlockingManager_SyncedBlockedPhoneNumbersKey
                                        transaction:transaction];
        [OWSBlockingManager.keyValueStore setObject:blockedUUIDs
                                                key:kOWSBlockingManager_SyncedBlockedUUIDsKey
                                        transaction:transaction];
        [OWSBlockingManager.keyValueStore setObject:blockedGroupIds
                                                key:kOWSBlockingManager_SyncedBlockedGroupIdsKey
                                        transaction:transaction];
    }];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        @synchronized(self)
        {
            [self syncBlockListIfNecessary];
        }
    }];
}

@end

NS_ASSUME_NONNULL_END
