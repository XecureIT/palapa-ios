//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSConversationSettingsViewController;
@class TSGroupModel;
@class SignalServiceAddress;

@protocol OWSConversationSettingsViewDelegate <NSObject>

- (void)conversationColorWasUpdated;
- (void)groupWasUpdated:(TSGroupModel *)groupModel extraGroupRecipients:(NSArray<SignalServiceAddress *> *)extraGroupRecipients;
- (void)conversationSettingsDidRequestConversationSearch:(OWSConversationSettingsViewController *)conversationSettingsViewController;

- (void)popAllConversationSettingsViewsWithCompletion:(void (^_Nullable)(void))completionBlock;

@end

NS_ASSUME_NONNULL_END
