//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class AccountServiceClient;
@class ContactsUpdater;
@class MessageSenderJobQueue;
@class OWS2FAManager;
@class OWSAttachmentDownloads;
@class OWSBatchMessageProcessor;
@class OWSBlockingManager;
@class OWSDisappearingMessagesJob;
@class OWSIdentityManager;
@class OWSLinkPreviewManager;
@class OWSMessageDecrypter;
@class OWSMessageManager;
@class OWSMessageReceiver;
@class OWSMessageSender;
@class OWSOutgoingReceiptManager;
@class OWSPrimaryStorage;
@class OWSReadReceiptManager;
@class SDSDatabaseStorage;
@class SSKMessageDecryptJobQueue;
@class SSKPreKeyStore;
@class SSKPreferences;
@class SSKSessionStore;
@class SSKSignedPreKeyStore;
@class SignalServiceAddressCache;
@class StickerManager;
@class StorageCoordinator;
@class TSAccountManager;
@class TSNetworkManager;
@class TSSocketManager;
@class YapDatabaseConnection;

@protocol ContactsManagerProtocol;
@protocol NotificationsProtocol;
@protocol OWSCallMessageHandler;
@protocol ProfileManagerProtocol;
@protocol OWSUDManager;
@protocol SSKReachabilityManager;
@protocol SyncManagerProtocol;
@protocol OWSTypingIndicators;
@protocol StorageServiceManagerProtocol;

@interface SSKEnvironment : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                     linkPreviewManager:(OWSLinkPreviewManager *)linkPreviewManager
                          messageSender:(OWSMessageSender *)messageSender
                  messageSenderJobQueue:(MessageSenderJobQueue *)messageSenderJobQueue
                         profileManager:(id<ProfileManagerProtocol>)profileManager
                         primaryStorage:(nullable OWSPrimaryStorage *)primaryStorage
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
                         messageManager:(OWSMessageManager *)messageManager
                        blockingManager:(OWSBlockingManager *)blockingManager
                        identityManager:(OWSIdentityManager *)identityManager
                           sessionStore:(SSKSessionStore *)sessionStore
                      signedPreKeyStore:(SSKSignedPreKeyStore *)signedPreKeyStore
                            preKeyStore:(SSKPreKeyStore *)preKeyStore
                              udManager:(id<OWSUDManager>)udManager
                       messageDecrypter:(OWSMessageDecrypter *)messageDecrypter
                 messageDecryptJobQueue:(SSKMessageDecryptJobQueue *)messageDecryptJobQueue
                  batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
                        messageReceiver:(OWSMessageReceiver *)messageReceiver
                          socketManager:(TSSocketManager *)socketManager
                       tsAccountManager:(TSAccountManager *)tsAccountManager
                          ows2FAManager:(OWS2FAManager *)ows2FAManager
                disappearingMessagesJob:(OWSDisappearingMessagesJob *)disappearingMessagesJob
                     readReceiptManager:(OWSReadReceiptManager *)readReceiptManager
                 outgoingReceiptManager:(OWSOutgoingReceiptManager *)outgoingReceiptManager
                    reachabilityManager:(id<SSKReachabilityManager>)reachabilityManager
                            syncManager:(id<SyncManagerProtocol>)syncManager
                       typingIndicators:(id<OWSTypingIndicators>)typingIndicators
                    attachmentDownloads:(OWSAttachmentDownloads *)attachmentDownloads
                         stickerManager:(StickerManager *)stickerManager
                        databaseStorage:(SDSDatabaseStorage *)databaseStorage
              signalServiceAddressCache:(SignalServiceAddressCache *)signalServiceAddressCache
                   accountServiceClient:(AccountServiceClient *)accountServiceClient
                  storageServiceManager:(id<StorageServiceManagerProtocol>)storageServiceManager
                     storageCoordinator:(StorageCoordinator *)storageCoordinator
                         sskPreferences:(SSKPreferences *)sskPreferences NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly, class) SSKEnvironment *shared;

+ (void)setShared:(SSKEnvironment *)env;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

+ (BOOL)hasShared;

@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) OWSLinkPreviewManager *linkPreviewManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) MessageSenderJobQueue *messageSenderJobQueue;
@property (nonatomic, readonly) id<ProfileManagerProtocol> profileManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSMessageManager *messageManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;
@property (nonatomic, readonly) SSKSessionStore *sessionStore;
@property (nonatomic, readonly) SSKSignedPreKeyStore *signedPreKeyStore;
@property (nonatomic, readonly) SSKPreKeyStore *preKeyStore;
@property (nonatomic, readonly) id<OWSUDManager> udManager;
@property (nonatomic, readonly) OWSMessageDecrypter *messageDecrypter;
@property (nonatomic, readonly) SSKMessageDecryptJobQueue *messageDecryptJobQueue;
@property (nonatomic, readonly) OWSBatchMessageProcessor *batchMessageProcessor;
@property (nonatomic, readonly) OWSMessageReceiver *messageReceiver;
@property (nonatomic, readonly) TSSocketManager *socketManager;
@property (nonatomic, readonly) TSAccountManager *tsAccountManager;
@property (nonatomic, readonly) OWS2FAManager *ows2FAManager;
@property (nonatomic, readonly) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic, readonly) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic, readonly) OWSOutgoingReceiptManager *outgoingReceiptManager;
@property (nonatomic, readonly) id<SyncManagerProtocol> syncManager;
@property (nonatomic, readonly) id<SSKReachabilityManager> reachabilityManager;
@property (nonatomic, readonly) id<OWSTypingIndicators> typingIndicators;
@property (nonatomic, readonly) OWSAttachmentDownloads *attachmentDownloads;
@property (nonatomic, readonly) SignalServiceAddressCache *signalServiceAddressCache;
@property (nonatomic, readonly) AccountServiceClient *accountServiceClient;
@property (nonatomic, readonly) id<StorageServiceManagerProtocol> storageServiceManager;

@property (nonatomic, readonly) StickerManager *stickerManager;
@property (nonatomic, readonly) SDSDatabaseStorage *databaseStorage;
@property (nonatomic, readonly) StorageCoordinator *storageCoordinator;
@property (nonatomic, readonly) SSKPreferences *sskPreferences;

@property (nonatomic, readonly, nullable) OWSPrimaryStorage *primaryStorage;

// This property is configured after Environment is created.
@property (atomic, nullable) id<OWSCallMessageHandler> callMessageHandler;
// This property is configured after Environment is created.
@property (atomic) id<NotificationsProtocol> notificationsManager;

@property (atomic, readonly) YapDatabaseConnection *migrationDBConnection;

- (BOOL)isComplete;

- (void)warmCaches;

@end

NS_ASSUME_NONNULL_END
