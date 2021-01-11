//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingReactionMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingReactionMessage ()

@property (nonatomic, readonly) NSString *messageUniqueId;
@property (nonatomic, readonly) NSString *emoji;
@property (nonatomic, readonly) BOOL isRemoving;

@end

#pragma mark -

@implementation OWSOutgoingReactionMessage

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSMessage *)message
                         emoji:(NSString *)emoji
                    isRemoving:(BOOL)isRemoving
              expiresInSeconds:(uint32_t)expiresInSeconds
{
    OWSAssertDebug([thread.uniqueId isEqualToString:message.uniqueThreadId]);
    OWSAssertDebug(emoji.isSingleEmoji);

    // MJK TODO - remove senderTimestamp
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:expiresInSeconds
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMetaMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil
                                       linkPreview:nil
                                    messageSticker:nil
                                 isViewOnceMessage:NO];
    if (!self) {
        return self;
    }

    _messageUniqueId = message.uniqueId;
    _emoji = emoji;
    _isRemoving = isRemoving;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:self.messageUniqueId transaction:transaction];
    if (!message) {
        OWSFailDebug(@"unexpectedly missing message for reaction");
        return nil;
    }

    SSKProtoDataMessageReactionBuilder *reactionBuilder =
        [SSKProtoDataMessageReaction builderWithEmoji:self.emoji remove:self.isRemoving timestamp:message.timestamp];

    SignalServiceAddress *_Nullable messageAuthor;

    if ([message isKindOfClass:[TSOutgoingMessage class]]) {
        messageAuthor = TSAccountManager.sharedInstance.localAddress;
    } else if ([message isKindOfClass:[TSIncomingMessage class]]) {
        messageAuthor = ((TSIncomingMessage *)message).authorAddress;
    }

    if (!messageAuthor) {
        OWSFailDebug(@"message is missing author.");
        return nil;
    }

    if (messageAuthor.phoneNumber) {
        reactionBuilder.authorE164 = messageAuthor.phoneNumber;
    }

    if (messageAuthor.uuidString) {
        reactionBuilder.authorUuid = messageAuthor.uuidString;
    }

    NSError *error;
    SSKProtoDataMessageReaction *_Nullable reactionProto = [reactionBuilder buildAndReturnError:&error];
    if (error || !reactionProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];
    [builder setTimestamp:self.timestamp];
    [builder setReaction:reactionProto];
    [builder setRequiredProtocolVersion:SSKProtoDataMessageProtocolVersionReactions];

    return builder;
}

- (void)updateWithSendingError:(NSError *)error transaction:(SDSAnyWriteTransaction *)transaction
{
    [super updateWithSendingError:error transaction:transaction];

    // Do nothing if we successfully delivered to anyone. Only cleanup
    // local state if we fail to deliver to anyone.
    if (self.sentRecipientAddresses.count > 0) {
        OWSLogError(@"Failed to send reaction to some recipients: %@", error.localizedDescription);
        return;
    }

    SignalServiceAddress *_Nullable localAddress = TSAccountManager.sharedInstance.localAddress;
    if (!localAddress) {
        OWSFailDebug(@"unexpectedly missing local address");
        return;
    }

    TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:self.messageUniqueId transaction:transaction];
    if (!message) {
        OWSFailDebug(@"unexpectedly missing message for reaction");
        return;
    }

    OWSLogError(@"Failed to send reaction to all recipients: %@", error.localizedDescription);

    OWSReaction *_Nullable currentReaction = [message reactionForReactor:localAddress transaction:transaction];

    if (![NSString isNullableObject:currentReaction.uniqueId equalTo:self.createdReaction.uniqueId]) {
        OWSLogInfo(@"Skipping reversion, changes have been made since we tried to send this message.");
        return;
    }

    if (self.previousReaction) {
        [message recordReactionForReactor:self.previousReaction.reactor
                                    emoji:self.previousReaction.emoji
                          sentAtTimestamp:self.previousReaction.sentAtTimestamp
                      receivedAtTimestamp:self.previousReaction.receivedAtTimestamp
                              transaction:transaction];
    } else {
        [message removeReactionForReactor:localAddress transaction:transaction];
    }
}

@end

NS_ASSUME_NONNULL_END
