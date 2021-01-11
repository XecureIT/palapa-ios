//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ConversationViewAction) {
    ConversationViewActionNone,
    ConversationViewActionCompose,
    ConversationViewActionAudioCall,
    ConversationViewActionVideoCall,
};

@class TSInteraction;
@class TSThread;

@interface ConversationViewController : OWSViewController

@property (nonatomic, readonly) TSThread *thread;

- (void)configureForThread:(TSThread *)thread
                    action:(ConversationViewAction)action
            focusMessageId:(nullable NSString *)focusMessageId;

- (void)popKeyBoard;

- (void)scrollToFirstUnreadMessage:(BOOL)isAnimated;

#pragma mark 3D Touch Methods

- (void)peekSetup;
- (void)popped;

#pragma mark - Keyboard Shortcuts

- (void)showConversationSettings;
- (void)focusInputToolbar;
- (void)openAllMedia;
- (void)openStickerKeyboard;
- (void)openAttachmentKeyboard;
- (void)openGifSearch;
- (void)dismissMessageActionsAnimated:(BOOL)animated;

@end

#pragma mark - Internal Methods. Used in extensions

@class ConversationCollectionView;
@class ConversationViewModel;
@class SDSDatabaseStorage;

@interface ConversationViewController (Internal)

@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) ConversationViewModel *conversationViewModel;
@property (nonatomic, readonly) SDSDatabaseStorage *databaseStorage;
@property (nonatomic, readonly) BOOL isViewVisible;
@property (nonatomic, readonly) BOOL isPresentingMessageActions;

@end

NS_ASSUME_NONNULL_END
