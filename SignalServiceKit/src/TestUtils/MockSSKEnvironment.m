//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWS2FAManager.h"
#import "OWSAttachmentDownloads.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSBlockingManager.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeContactsUpdater.h"
#import "OWSFakeMessageSender.h"
#import "OWSFakeNetworkManager.h"
#import "OWSFakeProfileManager.h"
#import "OWSIdentityManager.h"
#import "OWSMessageDecrypter.h"
#import "OWSMessageManager.h"
#import "OWSMessageReceiver.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSPrimaryStorage.h"
#import "OWSReadReceiptManager.h"
#import "SSKPreKeyStore.h"
#import "SSKSessionStore.h"
#import "SSKSignedPreKeyStore.h"
#import "StorageCoordinator.h"
#import "TSAccountManager.h"
#import "TSSocketManager.h"
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/ProfileManagerProtocol.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSPrimaryStorage (Tests)

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation MockSSKEnvironment

+ (void)activate
{
    [SMKEnvironment setShared:[[SMKEnvironment alloc] initWithAccountIdFinder:[OWSAccountIdFinder new]]];

    MockSSKEnvironment *instance = [self new];
    [self setShared:instance];
    [instance configure];

    [instance warmCaches];
}

- (instancetype)init
{
    // Ensure that OWSBackgroundTaskManager is created now.
    [OWSBackgroundTaskManager sharedManager];

    StorageCoordinator *storageCoordinator = [StorageCoordinator new];
    SDSDatabaseStorage *databaseStorage = storageCoordinator.databaseStorage;
    // Unlike AppSetup, we always load YDB in the tests.
    OWSPrimaryStorage *primaryStorage = databaseStorage.yapPrimaryStorage;

    id<ContactsManagerProtocol> contactsManager = [OWSFakeContactsManager new];
    OWSLinkPreviewManager *linkPreviewManager = [OWSLinkPreviewManager new];
    TSNetworkManager *networkManager = [OWSFakeNetworkManager new];
    OWSMessageSender *messageSender = [OWSFakeMessageSender new];
    MessageSenderJobQueue *messageSenderJobQueue = [MessageSenderJobQueue new];

    OWSMessageManager *messageManager = [OWSMessageManager new];
    OWSBlockingManager *blockingManager = [OWSBlockingManager new];
    OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithDatabaseStorage:databaseStorage];
    SSKSessionStore *sessionStore = [SSKSessionStore new];
    SSKPreKeyStore *preKeyStore = [SSKPreKeyStore new];
    SSKSignedPreKeyStore *signedPreKeyStore = [SSKSignedPreKeyStore new];
    id<OWSUDManager> udManager = [OWSUDManagerImpl new];
    OWSMessageDecrypter *messageDecrypter = [OWSMessageDecrypter new];
    SSKMessageDecryptJobQueue *messageDecryptJobQueue = [SSKMessageDecryptJobQueue new];
    OWSBatchMessageProcessor *batchMessageProcessor = [OWSBatchMessageProcessor new];
    OWSMessageReceiver *messageReceiver = [OWSMessageReceiver new];
    TSSocketManager *socketManager = [[TSSocketManager alloc] init];
    TSAccountManager *tsAccountManager = [TSAccountManager new];
    OWS2FAManager *ows2FAManager = [OWS2FAManager new];
    OWSDisappearingMessagesJob *disappearingMessagesJob = [OWSDisappearingMessagesJob new];
    OWSReadReceiptManager *readReceiptManager = [OWSReadReceiptManager new];
    OWSOutgoingReceiptManager *outgoingReceiptManager = [OWSOutgoingReceiptManager new];
    id<SSKReachabilityManager> reachabilityManager = [SSKReachabilityManagerImpl new];
    id<SyncManagerProtocol> syncManager = [[OWSMockSyncManager alloc] init];
    id<OWSTypingIndicators> typingIndicators = [[OWSTypingIndicatorsImpl alloc] init];
    OWSAttachmentDownloads *attachmentDownloads = [[OWSAttachmentDownloads alloc] init];
    StickerManager *stickerManager = [[StickerManager alloc] init];
    SignalServiceAddressCache *signalServiceAddressCache = [SignalServiceAddressCache new];
    AccountServiceClient *accountServiceClient = [FakeAccountServiceClient new];
    OWSFakeStorageServiceManager *storageServiceManager = [OWSFakeStorageServiceManager new];
    SSKPreferences *sskPreferences = [SSKPreferences new];

    self = [super initWithContactsManager:contactsManager
                       linkPreviewManager:linkPreviewManager
                            messageSender:messageSender
                    messageSenderJobQueue:messageSenderJobQueue
                           profileManager:[OWSFakeProfileManager new]
                           primaryStorage:primaryStorage
                          contactsUpdater:[OWSFakeContactsUpdater new]
                           networkManager:networkManager
                           messageManager:messageManager
                          blockingManager:blockingManager
                          identityManager:identityManager
                             sessionStore:sessionStore
                        signedPreKeyStore:signedPreKeyStore
                              preKeyStore:preKeyStore
                                udManager:udManager
                         messageDecrypter:messageDecrypter
                   messageDecryptJobQueue:messageDecryptJobQueue
                    batchMessageProcessor:batchMessageProcessor
                          messageReceiver:messageReceiver
                            socketManager:socketManager
                         tsAccountManager:tsAccountManager
                            ows2FAManager:ows2FAManager
                  disappearingMessagesJob:disappearingMessagesJob
                       readReceiptManager:readReceiptManager
                   outgoingReceiptManager:outgoingReceiptManager
                      reachabilityManager:reachabilityManager
                              syncManager:syncManager
                         typingIndicators:typingIndicators
                      attachmentDownloads:attachmentDownloads
                           stickerManager:stickerManager
                          databaseStorage:databaseStorage
                signalServiceAddressCache:signalServiceAddressCache
                     accountServiceClient:accountServiceClient
                    storageServiceManager:storageServiceManager
                       storageCoordinator:storageCoordinator
                           sskPreferences:sskPreferences];

    if (!self) {
        return nil;
    }

    self.callMessageHandler = [OWSFakeCallMessageHandler new];
    self.notificationsManager = [NoopNotificationsManager new];

    return self;
}

- (void)configure
{
        __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [[self configureYdb]
                .then(^{
                    OWSAssertIsOnMainThread();

                    return [self configureGrdb];
                })
                .then(^{
                    OWSAssertIsOnMainThread();

                    dispatch_semaphore_signal(semaphore);
                }) retainUntilComplete];

        // Registering extensions is a complicated process than can move
        // on and off the main thread.  While we wait for it to complete,
        // we need to process the run loop so that the work on the main
        // thread can be completed.
        while (YES) {
            // Wait up to 10 ms.
            BOOL success
                = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_MSEC)))
                == 0;
            if (success) {
                break;
            }

            // Process a single "source" (e.g. item) on the default run loop.
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, false);
        }
}

- (AnyPromise *)configureYdb
{
    if (!self.databaseStorage.canLoadYdb) {
        return [AnyPromise promiseWithValue:@(1)];
    }
    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [OWSStorage registerExtensionsWithCompletionBlock:^() {
            [self.storageCoordinator markStorageSetupAsComplete];

            // The value doesn't matter, we just need any non-NSError value.
            resolve(@(1));
        }];
    }];
    return promise;
}

- (AnyPromise *)configureGrdb
{
    OWSAssertIsOnMainThread();

    GRDBSchemaMigrator *grdbSchemaMigrator = [GRDBSchemaMigrator new];
    [grdbSchemaMigrator runSchemaMigrations];

    return [AnyPromise promiseWithValue:@(1)];
}

@end

#endif

NS_ASSUME_NONNULL_END
