//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactsUpdater.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "PhoneNumber.h"
#import "SSKEnvironment.h"
#import "TSNetworkManager.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactsUpdater ()

@property (nonatomic, readonly) NSOperationQueue *contactIntersectionQueue;

@end

#pragma mark -

@implementation ContactsUpdater

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

+ (instancetype)sharedUpdater {
    OWSAssertDebug(SSKEnvironment.shared.contactsUpdater);

    return SSKEnvironment.shared.contactsUpdater;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactIntersectionQueue = [NSOperationQueue new];
    _contactIntersectionQueue.maxConcurrentOperationCount = 1;
    _contactIntersectionQueue.name = self.logTag;

    OWSSingletonAssert();

    return self;
}

- (void)lookupIdentifiers:(NSArray<NSString *> *)identifiers
                 success:(void (^)(NSArray<SignalRecipient *> *recipients))success
                 failure:(void (^)(NSError *error))failure
{
    if (identifiers.count < 1) {
        OWSFailDebug(@"Cannot lookup zero identifiers");
        DispatchMainThreadSafe(^{
            failure(
                OWSErrorWithCodeDescription(OWSErrorCodeInvalidMethodParameters, @"Cannot lookup zero identifiers"));
        });
        return;
    }

    [self contactIntersectionWithSet:[NSSet setWithArray:identifiers]
        success:^(NSSet<SignalRecipient *> *recipients) {
            if (recipients.count == 0) {
                OWSLogInfo(@"no contacts are Signal users");
            }
            DispatchMainThreadSafe(^{
                success(recipients.allObjects);
            });
        }
        failure:^(NSError *error) {
            DispatchMainThreadSafe(^{
                failure(error);
            });
        }];
}

- (void)contactIntersectionWithSet:(NSSet<NSString *> *)phoneNumbersToLookup
                           success:(void (^)(NSSet<SignalRecipient *> *recipients))success
                           failure:(void (^)(NSError *error))failure
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CDSContactQueryBuilder *builder =
            [[CDSContactQueryBuilder alloc] initWithPhoneNumbersToLookup:phoneNumbersToLookup];

        __block NSError *error;
        __block CDSContactQueryCollection *queryCollection;
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            queryCollection = [builder buildWithTransaction:transaction error:&error];
            [builder removeStaleWithTransaction:transaction];
        }];

        if (error) {
            failure(error);
            return;
        }

        NSMutableSet<SignalRecipient *> *registeredRecipients = [NSMutableSet new];
        if (SSKFeatureFlags.useOnlyModernContactDiscovery) {
            SSKContactDiscoveryOperation *operation =
                [[SSKContactDiscoveryOperation alloc] initWithQueryCollection:queryCollection];

            NSArray<NSOperation *> *operationAndDependencies = [operation.dependencies arrayByAddingObject:operation];
            [self.contactIntersectionQueue addOperations:operationAndDependencies waitUntilFinished:YES];

            if (operation.failingError != nil) {
                failure(operation.failingError);
                return;
            }

            OWSAssertDebug(operation.isFinished);
            NSSet<SignalServiceAddress *> *registeredAddresses = operation.registeredAddresses;

            NSMutableSet<NSString *> *unregisterdPhoneNumbers = [phoneNumbersToLookup mutableCopy];

            [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                for (SignalServiceAddress *registeredAddress in registeredAddresses) {
                    NSString *registeredPhoneNumber = registeredAddress.phoneNumber;
                    if (registeredPhoneNumber == nil) {
                        OWSFailDebug(@"registeredPhoneNumber was unexpetedly nil");
                        continue;
                    }

                    [unregisterdPhoneNumbers removeObject:registeredPhoneNumber];
                    SignalRecipient *recipient = [SignalRecipient markRecipientAsRegisteredAndGet:registeredAddress
                                                                                      transaction:transaction];
                    [registeredRecipients addObject:recipient];
                }

                for (NSString *unregisteredPhoneNumber in unregisterdPhoneNumbers) {
                    SignalServiceAddress *unregisteredAddress =
                        [[SignalServiceAddress alloc] initWithPhoneNumber:unregisteredPhoneNumber];

                    [SignalRecipient markRecipientAsUnregistered:unregisteredAddress transaction:transaction];
                }
            }];
        } else {
            OWSLegacyContactDiscoveryOperation *operation =
                [[OWSLegacyContactDiscoveryOperation alloc] initWithQueryCollection:queryCollection];

            NSArray<NSOperation *> *operationAndDependencies = [operation.dependencies arrayByAddingObject:operation];
            [self.contactIntersectionQueue addOperations:operationAndDependencies waitUntilFinished:YES];

            if (operation.failingError != nil) {
                failure(operation.failingError);
                return;
            }

            NSSet<NSString *> *registeredPhoneNumbers = operation.registeredPhoneNumbers;
            [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                for (NSString *phoneNumber in phoneNumbersToLookup) {
                    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber];
                    if ([registeredPhoneNumbers containsObject:phoneNumber]) {
                        SignalRecipient *recipient = [SignalRecipient markRecipientAsRegisteredAndGet:address
                                                                                          transaction:transaction];
                        [registeredRecipients addObject:recipient];
                    } else {
                        [SignalRecipient markRecipientAsUnregistered:address transaction:transaction];
                    }
                }
            }];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            success([registeredRecipients copy]);
        });
    });
}

@end

NS_ASSUME_NONNULL_END
