//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppSetup.h"
#import "Environment.h"
#import "Theme.h"
#import "VersionMigrations.h"
#import <AxolotlKit/SessionCipher.h>
#import <SignalMessaging/OWSDatabaseMigration.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSAttachmentDownloads.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageDecrypter.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageReceiver.h>
#import <SignalServiceKit/OWSOutgoingReceiptManager.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSStorage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSSocketManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AppSetup

+ (void)setupEnvironmentWithAppSpecificSingletonBlock:(dispatch_block_t)appSpecificSingletonBlock
                                  migrationCompletion:(dispatch_block_t)migrationCompletion
{
    OWSAssertDebug(appSpecificSingletonBlock);
    OWSAssertDebug(migrationCompletion);

    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Order matters here.
        //
        // All of these "singletons" should have any dependencies used in their
        // initializers injected.
        [[OWSBackgroundTaskManager sharedManager] observeNotifications];

        StorageCoordinator *storageCoordinator = [StorageCoordinator new];
        SDSDatabaseStorage *databaseStorage = storageCoordinator.databaseStorage;
        OWSPrimaryStorage *_Nullable primaryStorage;
        if (databaseStorage.canLoadYdb) {
            primaryStorage = databaseStorage.yapPrimaryStorage;
        }

        // AFNetworking (via CFNetworking) spools it's attachments to NSTemporaryDirectory().
        // If you receive a media message while the device is locked, the download will fail if the temporary directory
        // is NSFileProtectionComplete
        BOOL success = [OWSFileSystem protectFileOrFolderAtPath:NSTemporaryDirectory()
                                             fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
        OWSAssert(success);

        OWSPreferences *preferences = [OWSPreferences new];

        TSNetworkManager *networkManager = [[TSNetworkManager alloc] initDefault];
        OWSContactsManager *contactsManager = [OWSContactsManager new];
        OWSLinkPreviewManager *linkPreviewManager = [OWSLinkPreviewManager new];
        ContactsUpdater *contactsUpdater = [ContactsUpdater new];
        OWSMessageSender *messageSender = [OWSMessageSender new];
        MessageSenderJobQueue *messageSenderJobQueue = [MessageSenderJobQueue new];
        OWSProfileManager *profileManager = [[OWSProfileManager alloc] initWithDatabaseStorage:databaseStorage];
        OWSMessageManager *messageManager = [OWSMessageManager new];
        OWSBlockingManager *blockingManager = [OWSBlockingManager new];
        OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithDatabaseStorage:databaseStorage];
        SSKSessionStore *sessionStore = [SSKSessionStore new];
        SSKSignedPreKeyStore *signedPreKeyStore = [SSKSignedPreKeyStore new];
        SSKPreKeyStore *preKeyStore = [SSKPreKeyStore new];
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
        OWSSyncManager *syncManager = [[OWSSyncManager alloc] initDefault];
        id<SSKReachabilityManager> reachabilityManager = [SSKReachabilityManagerImpl new];
        id<OWSTypingIndicators> typingIndicators = [[OWSTypingIndicatorsImpl alloc] init];
        OWSAttachmentDownloads *attachmentDownloads = [[OWSAttachmentDownloads alloc] init];
        StickerManager *stickerManager = [[StickerManager alloc] init];
        SignalServiceAddressCache *signalServiceAddressCache = [SignalServiceAddressCache new];
        AccountServiceClient *accountServiceClient = [AccountServiceClient new];
        OWSStorageServiceManager *storageServiceManager = OWSStorageServiceManager.shared;
        SSKPreferences *sskPreferences = [SSKPreferences new];

        OWSAudioSession *audioSession = [OWSAudioSession new];
        OWSIncomingContactSyncJobQueue *incomingContactSyncJobQueue = [OWSIncomingContactSyncJobQueue new];
        OWSIncomingGroupSyncJobQueue *incomingGroupSyncJobQueue = [OWSIncomingGroupSyncJobQueue new];
        LaunchJobs *launchJobs = [LaunchJobs new];
        OWSSounds *sounds = [OWSSounds new];
        id<OWSProximityMonitoringManager> proximityMonitoringManager = [OWSProximityMonitoringManagerImpl new];
        OWSWindowManager *windowManager = [[OWSWindowManager alloc] initDefault];

        [Environment setShared:[[Environment alloc] initWithAudioSession:audioSession
                                             incomingContactSyncJobQueue:incomingContactSyncJobQueue
                                               incomingGroupSyncJobQueue:incomingGroupSyncJobQueue
                                                              launchJobs:launchJobs
                                                             preferences:preferences
                                              proximityMonitoringManager:proximityMonitoringManager
                                                                  sounds:sounds
                                                           windowManager:windowManager]];

        [SMKEnvironment setShared:[[SMKEnvironment alloc] initWithAccountIdFinder:[OWSAccountIdFinder new]]];

        [SSKEnvironment setShared:[[SSKEnvironment alloc] initWithContactsManager:contactsManager
                                                               linkPreviewManager:linkPreviewManager
                                                                    messageSender:messageSender
                                                            messageSenderJobQueue:messageSenderJobQueue
                                                                   profileManager:profileManager
                                                                   primaryStorage:primaryStorage
                                                                  contactsUpdater:contactsUpdater
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
                                                                   sskPreferences:sskPreferences]];

        appSpecificSingletonBlock();

        OWSAssertDebug(SSKEnvironment.shared.isComplete);

        // Register renamed classes.
        [NSKeyedUnarchiver setClass:[OWSUserProfile class] forClassName:[OWSUserProfile collection]];
        [NSKeyedUnarchiver setClass:[OWSDatabaseMigration class] forClassName:[OWSDatabaseMigration collection]];
        [NSKeyedUnarchiver setClass:[ExperienceUpgrade class] forClassName:[ExperienceUpgrade collection]];
        [NSKeyedUnarchiver setClass:[ExperienceUpgrade class] forClassName:@"Signal.ExperienceUpgrade"];
        [NSKeyedUnarchiver setClass:[OWSGroupInfoRequestMessage class] forClassName:@"OWSSyncGroupsRequestMessage"];

        // Prevent device from sleeping during migrations.
        // This protects long migrations (e.g. the YDB-to-GRDB migration)
        // from the iOS 13 background crash.
        //
        // We can use any object.
        NSObject *sleepBlockObject = [NSObject new];
        [DeviceSleepManager.sharedInstance addBlockWithBlockObject:sleepBlockObject];

        dispatch_block_t completionBlock = ^{
            if (StorageCoordinator.dataStoreForUI == DataStoreYdb) {
                // It's only safe to do this for YDB. For GRDB-only users in
                // the post yap world, the tables for this won't exist yet on
                // the first launch of a new install.
                [SSKEnvironment.shared warmCaches];
            }

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (AppSetup.shouldTruncateGrdbWal) {
                    // Try to truncate GRDB WAL before any readers or writers are
                    // active.
                    NSError *_Nullable error;
                    [databaseStorage.grdbStorage syncTruncatingCheckpointAndReturnError:&error];
                    if (error != nil) {
                        OWSFailDebug(@"error: %@", error);
                    }
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    [storageCoordinator markStorageSetupAsComplete];

                    // Don't start database migrations until storage is ready.
                    [VersionMigrations performUpdateCheckWithCompletion:^() {
                        OWSAssertIsOnMainThread();

                        [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:sleepBlockObject];

                        if (StorageCoordinator.dataStoreForUI == DataStoreGrdb) {
                            [SSKEnvironment.shared warmCaches];
                        }
                        migrationCompletion();

                        OWSAssertDebug(backgroundTask);
                        backgroundTask = nil;
                    }];
                });
            });
        };

        if (databaseStorage.canLoadYdb) {
            [OWSStorage registerExtensionsWithCompletionBlock:completionBlock];
        } else {
            completionBlock();
        }
    });
}

+ (BOOL)shouldTruncateGrdbWal
{
    if (StorageCoordinator.dataStoreForUI != DataStoreGrdb) {
        return NO;
    }
    if (!CurrentAppContext().isMainApp) {
        return NO;
    }
    if (CurrentAppContext().mainApplicationStateOnLaunch == UIApplicationStateBackground) {
        return NO;
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
