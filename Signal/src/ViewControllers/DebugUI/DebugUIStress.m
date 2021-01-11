//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "DebugUIStress.h"
#import "OWSMessageSender.h"
#import "OWSTableViewController.h"
#import "SignalApp.h"
#import "ThreadUtil.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/OWSDynamicOutgoingMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIStress

#pragma mark - Dependencies

+ (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    return self.class.messageSenderJobQueue;
}

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

+ (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Stress";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    OWSAssertDebug(thread);
    
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];

    [items addObject:[OWSTableItem itemWithTitle:@"Send empty message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread block:^(SignalRecipient *recipient) {
                                             return [NSData new];
                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send random noise message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(SignalRecipient *recipient) {
                                                             NSUInteger contentLength = arc4random_uniform(32);
                                                             return [Cryptography generateRandomBytes:contentLength];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send no payload message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty null message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        SSKProtoNullMessageBuilder *nullMessageBuilder =
                                                                            [SSKProtoNullMessage builder];
                                                                        contentBuilder.nullMessage =
                                                                            [nullMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send random null message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(SignalRecipient *recipient) {
                                                             SSKProtoContentBuilder *contentBuilder =
                                                                 [SSKProtoContent builder];
                                                             SSKProtoNullMessageBuilder *nullMessageBuilder =
                                                                 [SSKProtoNullMessage builder];
                                                             NSUInteger contentLength = arc4random_uniform(32);
                                                             nullMessageBuilder.padding =
                                                                 [Cryptography generateRandomBytes:contentLength];
                                                             contentBuilder.nullMessage =
                                                                 [nullMessageBuilder buildIgnoringErrors];
                                                             return [[contentBuilder buildIgnoringErrors]
                                                                 serializedDataIgnoringErrors];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty sync message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessage builder];
                                                                        contentBuilder.syncMessage =
                                                                            [syncMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty sync sent message"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessage builder];
                                                                        SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                                            [SSKProtoSyncMessageSent builder];
                                                                        syncMessageBuilder.sent =
                                                                            [sentBuilder buildIgnoringErrors];
                                                                        contentBuilder.syncMessage =
                                                                            [syncMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send whitespace text data message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(SignalRecipient *recipient) {
                                                             SSKProtoContentBuilder *contentBuilder =
                                                                 [SSKProtoContent builder];
                                                             SSKProtoDataMessageBuilder *dataBuilder =
                                                                 [SSKProtoDataMessage builder];
                                                             dataBuilder.body = @" ";
                                                             [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                              thread:thread];
                                                             contentBuilder.dataMessage =
                                                                 [dataBuilder buildIgnoringErrors];
                                                             return [[contentBuilder buildIgnoringErrors]
                                                                 serializedDataIgnoringErrors];
                                                         }];
                                     }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send bad attachment data message"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                                SSKProtoAttachmentPointerBuilder *attachmentPointer =
                                                    [SSKProtoAttachmentPointer
                                                        builderWithId:arc4random_uniform(32) + 1];
                                                [attachmentPointer setContentType:@"1"];
                                                [attachmentPointer setSize:arc4random_uniform(32) + 1];
                                                [attachmentPointer setDigest:[Cryptography generateRandomBytes:1]];
                                                [attachmentPointer setFileName:@" "];
                                                [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send normal text data message"
                                     actionBlock:^{
                                         [DebugUIStress
                                             sendStressMessage:thread
                                                         block:^(SignalRecipient *recipient) {
                                                             SSKProtoContentBuilder *contentBuilder =
                                                                 [SSKProtoContent builder];
                                                             SSKProtoDataMessageBuilder *dataBuilder =
                                                                 [SSKProtoDataMessage builder];
                                                             dataBuilder.body = @"alice";
                                                             [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                              thread:thread];
                                                             contentBuilder.dataMessage =
                                                                 [dataBuilder buildIgnoringErrors];
                                                             return [[contentBuilder buildIgnoringErrors]
                                                                 serializedDataIgnoringErrors];
                                                         }];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send N text messages with same timestamp"
                                     actionBlock:^{
                                         uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                                         for (int i = 0; i < 3; i++) {
                                             [DebugUIStress
                                                 sendStressMessage:thread
                                                         timestamp:timestamp
                                                             block:^(SignalRecipient *recipient) {
                                                                 SSKProtoContentBuilder *contentBuilder =
                                                                     [SSKProtoContent builder];
                                                                 SSKProtoDataMessageBuilder *dataBuilder =
                                                                     [SSKProtoDataMessage builder];
                                                                 dataBuilder.body = [NSString stringWithFormat:@"%@ %d",
                                                                                              [NSUUID UUID].UUIDString,
                                                                                              i];
                                                                 [DebugUIStress ensureGroupOfDataBuilder:dataBuilder
                                                                                                  thread:thread];
                                                                 contentBuilder.dataMessage =
                                                                     [dataBuilder buildIgnoringErrors];
                                                                 return [[contentBuilder buildIgnoringErrors]
                                                                     serializedDataIgnoringErrors];
                                                             }];
                                         }
                                     }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send text message with current timestamp"
                           actionBlock:^{
                               uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                               [DebugUIStress
                                   sendStressMessage:thread
                                           timestamp:timestamp
                                               block:^(SignalRecipient *recipient) {
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send text message with future timestamp"
                           actionBlock:^{
                               uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                               timestamp += kHourInMs;
                               [DebugUIStress
                                   sendStressMessage:thread
                                           timestamp:timestamp
                                               block:^(SignalRecipient *recipient) {
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Send text message with past timestamp"
                           actionBlock:^{
                               uint64_t timestamp = [NSDate ows_millisecondTimeStamp];
                               timestamp -= kHourInMs;
                               [DebugUIStress
                                   sendStressMessage:thread
                                           timestamp:timestamp
                                               block:^(SignalRecipient *recipient) {
                                                   SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                   SSKProtoDataMessageBuilder *dataBuilder =
                                                       [SSKProtoDataMessage builder];
                                                   dataBuilder.body =
                                                       [[NSUUID UUID].UUIDString stringByAppendingString:@" now"];
                                                   [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                                   contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                                   return [[contentBuilder buildIgnoringErrors]
                                                       serializedDataIgnoringErrors];
                                               }];
                           }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send N text messages with same timestamp"
                                     actionBlock:^{
                                         SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                         SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                         dataBuilder.body = @"alice";
                                         contentBuilder.dataMessage = [dataBuilder buildIgnoringErrors];
                                         [DebugUIStress ensureGroupOfDataBuilder:dataBuilder thread:thread];
                                         NSData *data =
                                             [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];

                                         uint64_t timestamp = [NSDate ows_millisecondTimeStamp];

                                         for (int i = 0; i < 3; i++) {
                                             [DebugUIStress sendStressMessage:thread
                                                                    timestamp:timestamp
                                                                        block:^(SignalRecipient *recipient) {
                                                                            return data;
                                                                        }];
                                         }
                                     }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 1"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationE164 = @"abc";
                                                sentBuilder.timestamp = arc4random_uniform(32) + 1;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 2"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationE164 = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 3"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationE164 = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                                dataBuilder.body = @" ";
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 4"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationE164 = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                                dataBuilder.body = @" ";
                                                SSKProtoGroupContextBuilder *groupBuilder = [SSKProtoGroupContext
                                                    builderWithId:[Cryptography generateRandomBytes:1]];
                                                [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
                                                dataBuilder.group = [groupBuilder buildIgnoringErrors];
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Send malformed sync sent message 5"
                        actionBlock:^{
                            [DebugUIStress
                                sendStressMessage:thread
                                            block:^(SignalRecipient *recipient) {
                                                SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
                                                SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                    [SSKProtoSyncMessage builder];
                                                SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                    [SSKProtoSyncMessageSent builder];
                                                sentBuilder.destinationE164 = @"abc";
                                                sentBuilder.timestamp = 0;
                                                SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
                                                dataBuilder.body = @" ";
                                                SSKProtoGroupContextBuilder *groupBuilder = [SSKProtoGroupContext
                                                    builderWithId:[Cryptography generateRandomBytes:1]];
                                                [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
                                                dataBuilder.group = [groupBuilder buildIgnoringErrors];
                                                sentBuilder.message = [dataBuilder buildIgnoringErrors];
                                                syncMessageBuilder.sent = [sentBuilder buildIgnoringErrors];
                                                contentBuilder.syncMessage = [syncMessageBuilder buildIgnoringErrors];
                                                return
                                                    [[contentBuilder buildIgnoringErrors] serializedDataIgnoringErrors];
                                            }];
                        }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Send empty sync sent message 6"
                                     actionBlock:^{
                                         [DebugUIStress sendStressMessage:thread
                                                                    block:^(SignalRecipient *recipient) {
                                                                        SSKProtoContentBuilder *contentBuilder =
                                                                            [SSKProtoContent builder];
                                                                        SSKProtoSyncMessageBuilder *syncMessageBuilder =
                                                                            [SSKProtoSyncMessage builder];
                                                                        SSKProtoSyncMessageSentBuilder *sentBuilder =
                                                                            [SSKProtoSyncMessageSent builder];
                                                                        sentBuilder.destinationE164 = @"abc";
                                                                        syncMessageBuilder.sent =
                                                                            [sentBuilder buildIgnoringErrors];
                                                                        contentBuilder.syncMessage =
                                                                            [syncMessageBuilder buildIgnoringErrors];
                                                                        return [[contentBuilder buildIgnoringErrors]
                                                                            serializedDataIgnoringErrors];
                                                                    }];
                                     }]];

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [items addObject:[OWSTableItem itemWithTitle:@"Hallucinate twin group"
                                         actionBlock:^{
                                             [DebugUIStress hallucinateTwinGroup:groupThread];
                                         }]];
    }

    [items addObject:[OWSTableItem itemWithTitle:@"Make group w. unregistered users"
                                     actionBlock:^{
                                         [DebugUIStress makeUnregisteredGroup];
                                     }]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)ensureGroupOfDataBuilder:(SSKProtoDataMessageBuilder *)dataBuilder thread:(TSThread *)thread
{
    OWSAssertDebug(dataBuilder);
    OWSAssertDebug(thread);

    if (![thread isKindOfClass:[TSGroupThread class]]) {
        return;
    }

    TSGroupThread *groupThread = (TSGroupThread *)thread;
    SSKProtoGroupContextBuilder *groupBuilder = [SSKProtoGroupContext builderWithId:groupThread.groupModel.groupId];
    [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
    [groupBuilder setId:groupThread.groupModel.groupId];
    [dataBuilder setGroup:groupBuilder.buildIgnoringErrors];
}

+ (void)sendStressMessage:(TSOutgoingMessage *)message
{
    OWSAssertDebug(message);

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    }];
}

+ (void)sendStressMessage:(TSThread *)thread
                    block:(DynamicOutgoingMessageBlock)block
{
    OWSAssertDebug(thread);
    OWSAssertDebug(block);

    OWSDynamicOutgoingMessage *message =
        [[OWSDynamicOutgoingMessage alloc] initWithPlainTextDataBlock:block thread:thread];

    [self sendStressMessage:message];
}

+ (void)sendStressMessage:(TSThread *)thread timestamp:(uint64_t)timestamp block:(DynamicOutgoingMessageBlock)block
{
    OWSAssertDebug(thread);
    OWSAssertDebug(block);

    OWSDynamicOutgoingMessage *message =
        [[OWSDynamicOutgoingMessage alloc] initWithPlainTextDataBlock:block timestamp:timestamp thread:thread];

    [self sendStressMessage:message];
}

// Creates a new group (by cloning the current group) without informing the,
// other members. This can be used to test "group info requests", etc.
+ (void)hallucinateTwinGroup:(TSGroupThread *)groupThread
{
    NSString *groupName = [groupThread.groupModel.groupName stringByAppendingString:@" Copy"];
    [GroupManager createGroupObjcWithMembers:groupThread.groupModel.groupMembers
                                     groupId:nil
                                        name:groupName
                                       owner:groupThread.groupModel.groupOwner
                                      admins:groupThread.groupModel.groupAdmins
                                  avatarData:groupThread.groupModel.groupAvatarData
                                     success:^(TSGroupThread * thread) {
                                         [SignalApp.sharedApp presentConversationForThread:thread animated:YES];
                                     } failure:^(NSError * error) {
                                         OWSFailDebug(@"Error: %@", error);
                                     }];
}

+ (void)makeUnregisteredGroup
{
    NSMutableArray<SignalServiceAddress *> *recipientAddresses = [NSMutableArray new];
    for (int i = 0; i < 3; i++) {
        NSMutableString *recipientNumber = [@"+1999" mutableCopy];
        for (int j = 0; j < 3; j++) {
            uint32_t digit = arc4random_uniform(10);
            [recipientNumber appendFormat:@"%d", (int)digit];
        }
        [recipientAddresses addObject:[[SignalServiceAddress alloc] initWithUuid:[NSUUID UUID]
                                                                     phoneNumber:recipientNumber]];
    }
    [recipientAddresses addObject:self.tsAccountManager.localAddress];

    if (SSKFeatureFlags.allowUUIDOnlyContacts) {
        for (int i = 0; i < 3; i++) {
            [recipientAddresses addObject:[[SignalServiceAddress alloc] initWithUuid:[NSUUID UUID] phoneNumber:nil]];
        }
    }

    [GroupManager createGroupObjcWithMembers:recipientAddresses
                                     groupId:nil
                                        name:NSUUID.UUID.UUIDString
                                       owner:nil
                                      admins:@[]
                                  avatarData:nil
                                     success:^(TSGroupThread * thread) {
                                         [SignalApp.sharedApp presentConversationForThread:thread animated:YES];
                                     } failure:^(NSError * error) {
                                         OWSFailDebug(@"Error: %@", error);
                                     }];
}

@end

NS_ASSUME_NONNULL_END

#endif
