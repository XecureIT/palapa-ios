//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This header exposes private properties for SDS serialization.

@interface TSThread (SDS)

@property (nonatomic, copy, nullable, readonly) NSString *messageDraft;

@end

#pragma mark -

@interface TSMessage (SDS)

// This property is only intended to be used by GRDB queries.
@property (nonatomic, readonly) BOOL storedShouldStartExpireTimer;

@end

#pragma mark -

@interface TSInfoMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSErrorMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSOutgoingMessage (SDS)

@property (nonatomic, readonly) TSOutgoingMessageState legacyMessageState;
@property (nonatomic, readonly) BOOL legacyWasDelivered;
@property (nonatomic, readonly) BOOL hasLegacyMessageState;
@property (atomic, readonly)
    NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *recipientAddressStates;
@property (nonatomic, readonly) TSOutgoingMessageState storedMessageState;

@end

#pragma mark -

@interface OWSDisappearingConfigurationUpdateInfoMessage (SDS)

@property (nonatomic, readonly) uint32_t configurationDurationSeconds;

@property (nonatomic, readonly, nullable) NSString *createdByRemoteName;
@property (nonatomic, readonly) BOOL createdInExistingGroup;

@end

#pragma mark -

@interface TSCall (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSIncomingMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSAttachmentPointer (SDS)

@property (nonatomic, nullable, readonly) NSString *lazyRestoreFragmentId;

@end

#pragma mark -

@interface TSAttachmentStream (SDS)

@property (nullable, nonatomic, readonly) NSString *localRelativeFilePath;

@property (nullable, nonatomic, readonly) NSNumber *cachedImageWidth;
@property (nullable, nonatomic, readonly) NSNumber *cachedImageHeight;

@property (nullable, nonatomic, readonly) NSNumber *cachedAudioDurationSeconds;

@property (atomic, nullable, readonly) NSNumber *isValidImageCached;
@property (atomic, nullable, readonly) NSNumber *isValidVideoCached;

@end

#pragma mark -

@interface TSInvalidIdentityKeySendingErrorMessage (SDS)

@property (nonatomic, readonly) PreKeyBundle *preKeyBundle;

@end

#pragma mark -

@interface OWSOutgoingSentMessageTranscript (SDS)

@property (nonatomic, readonly) TSOutgoingMessage *message;

@property (nonatomic, readonly, nullable) NSString *sentRecipientId;

@property (nonatomic, readonly) BOOL isRecipientUpdate;

@end

#pragma mark -

@interface TSInvalidIdentityKeyReceivingErrorMessage (SDS)

@property (nonatomic, readonly, copy) NSString *authorId;

@property (atomic, readonly, nullable) NSData *envelopeData;

@end

#pragma mark -

@interface TSContactThread (SDS)

@property (nonatomic, nullable, readonly) NSString *contactPhoneNumber;
@property (nonatomic, nullable, readonly) NSString *contactUUID;

@end

#pragma mark -

@interface OWSUserProfile (SDS)

@property (atomic, nullable, readonly) NSString *recipientPhoneNumber;
@property (atomic, nullable, readonly) NSString *recipientUUID;

@end

#pragma mark -

@interface OWSLinkedDeviceReadReceipt (SDS)

@property (nonatomic, nullable, readonly) NSString *senderPhoneNumber;
@property (nonatomic, nullable, readonly) NSString *senderUUID;

@end

#pragma mark -

@interface OWSReaction (SDS)

@property (nonatomic, readonly, nullable) NSString *reactorE164;
@property (nonatomic, readonly, nullable) NSString *reactorUUID;

@end

NS_ASSUME_NONNULL_END
