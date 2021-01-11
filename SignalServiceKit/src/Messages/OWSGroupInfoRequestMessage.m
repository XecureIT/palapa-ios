//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSGroupInfoRequestMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSGroupInfoRequestMessage ()

@property (nonatomic) NSData *groupId;

@end

#pragma mark -

@implementation OWSGroupInfoRequestMessage

- (instancetype)initWithThread:(TSThread *)thread groupId:(NSData *)groupId
{
    // MJK TODO - remove senderTimestamp
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
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

    OWSAssertDebug(groupId.length > 0);
    _groupId = groupId;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)isSilent
{
    // Avoid "phantom messages"

    return YES;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContext builderWithId:self.groupId];
    [groupContextBuilder setType:SSKProtoGroupContextTypeRequestInfo];

    NSError *error;
    SSKProtoGroupContext *_Nullable groupContextProto = [groupContextBuilder buildAndReturnError:&error];
    if (error || !groupContextProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [SSKProtoDataMessage builder];
    [builder setTimestamp:self.timestamp];
    [builder setGroup:groupContextProto];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
