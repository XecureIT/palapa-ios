//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageDecrypter.h"
#import "NSData+messagePadding.h"
#import "NotificationsProtocol.h"
#import "OWSAnalytics.h"
#import "OWSBlockingManager.h"
#import "OWSDevice.h"
#import "OWSError.h"
#import "OWSIdentityManager.h"
#import "SSKEnvironment.h"
#import "SSKPreKeyStore.h"
#import "SSKSessionStore.h"
#import "SSKSignedPreKeyStore.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSPreKeyManager.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/SessionCipher.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalCoreKit/SCKExceptionWrapper.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSError *EnsureDecryptError(NSError *_Nullable error, NSString *fallbackErrorDescription)
{
    if (error) {
        return error;
    }
    OWSCFailDebug(@"Caller should provide specific error");
    return OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, fallbackErrorDescription);
}

#pragma mark -

@interface OWSMessageDecryptResult ()

@property (nonatomic) NSData *envelopeData;
@property (nonatomic, nullable) NSData *plaintextData;
@property (nonatomic) SignalServiceAddress *sourceAddress;
@property (nonatomic) UInt32 sourceDevice;
@property (nonatomic) BOOL isUDMessage;

@end

#pragma mark -

@implementation OWSMessageDecryptResult

+ (OWSMessageDecryptResult *)resultWithEnvelopeData:(NSData *)envelopeData
                                      plaintextData:(nullable NSData *)plaintextData
                                      sourceAddress:(SignalServiceAddress *)sourceAddress
                                       sourceDevice:(UInt32)sourceDevice
                                        isUDMessage:(BOOL)isUDMessage
{
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(sourceAddress.isValid);
    OWSAssertDebug(sourceDevice > 0);

    OWSMessageDecryptResult *result = [OWSMessageDecryptResult new];
    result.envelopeData = envelopeData;
    result.plaintextData = plaintextData;
    result.sourceAddress = sourceAddress;
    result.sourceDevice = sourceDevice;
    result.isUDMessage = isUDMessage;
    return result;
}

@end

#pragma mark -

@implementation OWSMessageDecrypter

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

#pragma mark - Dependencies

- (OWSBlockingManager *)blockingManager
{
    OWSAssertDebug(SSKEnvironment.shared.blockingManager);

    return SSKEnvironment.shared.blockingManager;
}

- (OWSIdentityManager *)identityManager
{
    OWSAssertDebug(SSKEnvironment.shared.identityManager);

    return SSKEnvironment.shared.identityManager;
}

- (id<OWSUDManager>)udManager
{
    OWSAssertDebug(SSKEnvironment.shared.udManager);

    return SSKEnvironment.shared.udManager;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
}

- (SSKPreKeyStore *)preKeyStore
{
    return SSKEnvironment.shared.preKeyStore;
}

- (SSKSignedPreKeyStore *)signedPreKeyStore
{
    return SSKEnvironment.shared.signedPreKeyStore;
}

#pragma mark - Blocking

- (BOOL)isEnvelopeSenderBlocked:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope);

    return [self.blockingManager isAddressBlocked:envelope.sourceAddress];
}

#pragma mark - Decryption

- (void)decryptEnvelope:(SSKProtoEnvelope *)envelope
           envelopeData:(NSData *)envelopeData
           successBlock:(DecryptSuccessBlock)successBlockParameter
           failureBlock:(DecryptFailureBlock)failureBlockParameter
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(successBlockParameter);
    OWSAssertDebug(failureBlockParameter);
    OWSAssertDebug([self.tsAccountManager isRegistered]);

    // successBlock is called synchronously so that we can avail ourselves of
    // the transaction.
    //
    // Ensure that failureBlock is called on a worker queue.
    DecryptFailureBlock failureBlock = ^() {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureBlockParameter();
        });
    };

    uint32_t localDeviceId = self.tsAccountManager.storedDeviceId;
    DecryptSuccessBlock successBlock = ^(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction) {
        // Ensure all blocked messages are discarded.
        if ([self isEnvelopeSenderBlocked:envelope]) {
            OWSLogInfo(@"Ignoring blocked envelope: %@", envelope.sourceAddress);
            return failureBlock();
        }

        if (result.sourceAddress.isLocalAddress && result.sourceDevice == localDeviceId) {
            // Self-sent messages should be discarded during the decryption process.
            OWSFailDebug(@"Unexpected self-sent sync message.");
            return failureBlock();
        }

        // Having received a valid (decryptable) message from this user,
        // make note of the fact that they have a valid Signal account.
        [SignalRecipient markRecipientAsRegistered:result.sourceAddress
                                          deviceId:result.sourceDevice
                                       transaction:transaction];

        successBlockParameter(result, transaction);
    };

    @try {
        OWSLogInfo(@"decrypting envelope: %@", [self descriptionForEnvelope:envelope]);

        if (!envelope.hasType) {
            OWSFailDebug(@"Incoming envelope is missing type.");
            return failureBlock();
        }
        if (![SDS fitsInInt64:envelope.timestamp]) {
            OWSFailDebug(@"Invalid timestamp.");
            return failureBlock();
        }
        if (envelope.hasServerTimestamp && ![SDS fitsInInt64:envelope.serverTimestamp]) {
            OWSFailDebug(@"Invalid serverTimestamp.");
            return failureBlock();
        }

        if (envelope.unwrappedType != SSKProtoEnvelopeTypeUnidentifiedSender) {
            if (!envelope.hasValidSource) {
                OWSFailDebug(@"incoming envelope has invalid source");
                return failureBlock();
            }

            if (!envelope.hasSourceDevice || envelope.sourceDevice < 1) {
                OWSFailDebug(@"incoming envelope has invalid source device");
                return failureBlock();
            }

            // We block UD messages later, after they are decrypted.
            if ([self isEnvelopeSenderBlocked:envelope]) {
                OWSLogInfo(@"ignoring blocked envelope: %@", envelope.sourceAddress);
                return failureBlock();
            }
        }

        switch (envelope.unwrappedType) {
            case SSKProtoEnvelopeTypeCiphertext: {
                [self throws_decryptSecureMessage:envelope
                    envelopeData:envelopeData
                    successBlock:^(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted secure message.");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"decrypting secure message from address: %@ failed with error: %@",
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandleSecureMessage]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            case SSKProtoEnvelopeTypePrekeyBundle: {
                [self throws_decryptPreKeyBundle:envelope
                    envelopeData:envelopeData
                    successBlock:^(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted pre-key whisper message");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"decrypting pre-key whisper message from address: %@ failed "
                                    @"with error: %@",
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandlePrekeyBundle]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            // These message types don't have a payload to decrypt.
            case SSKProtoEnvelopeTypeReceipt:
            case SSKProtoEnvelopeTypeKeyExchange:
            case SSKProtoEnvelopeTypeUnknown: {
                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                    OWSMessageDecryptResult *result =
                        [OWSMessageDecryptResult resultWithEnvelopeData:envelopeData
                                                          plaintextData:nil
                                                          sourceAddress:envelope.sourceAddress
                                                           sourceDevice:envelope.sourceDevice
                                                            isUDMessage:NO];
                    successBlock(result, transaction);
                }];
                // Return to avoid double-acknowledging.
                return;
            }
            case SSKProtoEnvelopeTypeUnidentifiedSender: {
                [self decryptUnidentifiedSender:envelope
                    successBlock:^(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction) {
                        OWSLogDebug(@"decrypted unidentified sender message");
                        successBlock(result, transaction);
                    }
                    failureBlock:^(NSError *_Nullable error) {
                        OWSLogError(@"decrypting unidentified sender message from address: %@ failed "
                                    @"with error: %@",
                            envelopeAddress(envelope),
                            error);
                        OWSProdError([OWSAnalyticsEvents messageManagerErrorCouldNotHandleUnidentifiedSenderMessage]);
                        failureBlock();
                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            default:
                OWSLogWarn(@"Received unhandled envelope type: %d", (int)envelope.unwrappedType);
                break;
        }
    } @catch (NSException *exception) {
        OWSFailDebug(@"Received an invalid envelope: %@", exception.debugDescription);
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorInvalidProtocolMessage]);

        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            ThreadlessErrorMessage *errorMessage = [ThreadlessErrorMessage corruptedMessageInUnknownThread];
            [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                transaction:transaction];
        }];
    }

    failureBlock();
}

- (void)throws_decryptSecureMessage:(SSKProtoEnvelope *)envelope
                       envelopeData:(NSData *)envelopeData
                       successBlock:(DecryptSuccessBlock)successBlock
                       failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    [self decryptEnvelope:envelope
              envelopeData:envelopeData
            cipherTypeName:@"Secure Message"
        cipherMessageBlock:^(NSData *encryptedData) {
            return [[WhisperMessage alloc] init_throws_withData:encryptedData];
        }
              successBlock:successBlock
              failureBlock:failureBlock];
}

- (void)throws_decryptPreKeyBundle:(SSKProtoEnvelope *)envelope
                      envelopeData:(NSData *)envelopeData
                      successBlock:(DecryptSuccessBlock)successBlock
                      failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    // Check whether we need to refresh our PreKeys every time we receive a PreKeyWhisperMessage.
    [TSPreKeyManager checkPreKeys];

    [self decryptEnvelope:envelope
              envelopeData:envelopeData
            cipherTypeName:@"PreKey Bundle"
        cipherMessageBlock:^(NSData *encryptedData) {
            return [[PreKeyWhisperMessage alloc] init_throws_withData:encryptedData];
        }
              successBlock:successBlock
              failureBlock:failureBlock];
}

- (void)decryptEnvelope:(SSKProtoEnvelope *)envelope
           envelopeData:(NSData *)envelopeData
         cipherTypeName:(NSString *)cipherTypeName
     cipherMessageBlock:(id<CipherMessage> (^_Nonnull)(NSData *))cipherMessageBlock
           successBlock:(DecryptSuccessBlock)successBlock
           failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(envelopeData);
    OWSAssertDebug(cipherTypeName.length > 0);
    OWSAssertDebug(cipherMessageBlock);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    int deviceId = envelope.sourceDevice;

    // DEPRECATED - Remove `legacyMessage` after all clients have been upgraded.
    NSData *encryptedData = envelope.content ?: envelope.legacyMessage;
    if (!encryptedData) {
        OWSProdFail([OWSAnalyticsEvents messageManagerErrorMessageEnvelopeHasNoContent]);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, @"Envelope has no content");
        return failureBlock(error);
    }

    [self.databaseStorage
        asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
            NSString *accountIdentifier = [[OWSAccountIdFinder new] ensureAccountIdForAddress:envelope.sourceAddress
                                                                                  transaction:transaction];
            @try {
                id<CipherMessage> cipherMessage = cipherMessageBlock(encryptedData);
                SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:self.sessionStore
                                                                        preKeyStore:self.preKeyStore
                                                                  signedPreKeyStore:self.signedPreKeyStore
                                                                   identityKeyStore:self.identityManager
                                                                        recipientId:accountIdentifier
                                                                           deviceId:deviceId];

                // plaintextData may be nil for some envelope types.
                NSData *_Nullable plaintextData =
                    [[cipher throws_decrypt:cipherMessage protocolContext:transaction] removePadding];
                OWSMessageDecryptResult *result = [OWSMessageDecryptResult resultWithEnvelopeData:envelopeData
                                                                                    plaintextData:plaintextData
                                                                                    sourceAddress:envelope.sourceAddress
                                                                                     sourceDevice:envelope.sourceDevice
                                                                                      isUDMessage:NO];
                successBlock(result, transaction);
            } @catch (NSException *exception) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self processException:exception envelope:envelope];
                    NSString *errorDescription = [NSString
                        stringWithFormat:@"Exception while decrypting %@: %@", cipherTypeName, exception.description];
                    OWSLogError(@"%@", errorDescription);
                    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                    failureBlock(error);
                });
            }
        }];
}

- (void)decryptUnidentifiedSender:(SSKProtoEnvelope *)envelope
                     successBlock:(DecryptSuccessBlock)successBlock
                     failureBlock:(void (^)(NSError *_Nullable error))failureBlock
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    // NOTE: We don't need to bother with `legacyMessage` for UD messages.
    NSData *encryptedData = envelope.content;
    if (!encryptedData) {
        NSString *errorDescription = @"UD Envelope is missing content.";
        OWSFailDebug(@"%@", errorDescription);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
        return failureBlock(error);
    }

    if (!envelope.hasServerTimestamp) {
        NSString *errorDescription = @"UD Envelope is missing server timestamp.";
        // TODO: We're seeing incoming UD envelopes without a server timestamp on staging.
        // Until this is fixed, disabling this assert.
        //        OWSFailDebug(@"%@", errorDescription);
        OWSLogError(@"%@", errorDescription);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
        return failureBlock(error);
    }
    UInt64 serverTimestamp = envelope.serverTimestamp;
    if (![SDS fitsInInt64:serverTimestamp]) {
        NSString *errorDescription = @"Invalid serverTimestamp.";
        OWSFailDebug(@"%@", errorDescription);
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
        return failureBlock(error);
    }

    id<SMKCertificateValidator> certificateValidator =
        [[SMKCertificateDefaultValidator alloc] initWithTrustRoot:self.udManager.trustRoot];

    SignalServiceAddress *localAddress = self.tsAccountManager.localAddress;
    uint32_t localDeviceId = self.tsAccountManager.storedDeviceId;

    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
        NSError *cipherError;
        SMKSecretSessionCipher *_Nullable cipher =
            [[SMKSecretSessionCipher alloc] initWithSessionStore:self.sessionStore
                                                     preKeyStore:self.preKeyStore
                                               signedPreKeyStore:self.signedPreKeyStore
                                                   identityStore:self.identityManager
                                                           error:&cipherError];
        if (cipherError || !cipher) {
            OWSFailDebug(@"Could not create secret session cipher: %@", cipherError);
            cipherError = EnsureDecryptError(cipherError, @"Could not create secret session cipher");
            return failureBlock(cipherError);
        }

        NSError *decryptError;
        SMKDecryptResult *_Nullable decryptResult =
            [cipher throwswrapped_decryptMessageWithCertificateValidator:certificateValidator
                                                          cipherTextData:encryptedData
                                                               timestamp:serverTimestamp
                                                               localE164:localAddress.phoneNumber
                                                               localUuid:localAddress.uuid
                                                           localDeviceId:localDeviceId
                                                         protocolContext:transaction
                                                                   error:&decryptError];

        if (!decryptResult) {
            if (!decryptError) {
                OWSFailDebug(@"Caller should provide specific error");
                NSError *error = OWSErrorWithCodeDescription(
                    OWSErrorCodeFailedToDecryptUDMessage, @"Could not decrypt UD message");
                return failureBlock(error);
            }

            // Decrypt Failure Part 1: Unwrap failure details

            NSError *_Nullable underlyingError;
            SSKProtoEnvelope *_Nullable identifiedEnvelope;

            if (![decryptError.domain isEqualToString:@"SignalMetadataKit.SecretSessionKnownSenderError"]) {
                underlyingError = decryptError;
                identifiedEnvelope = envelope;
            } else {
                underlyingError = decryptError.userInfo[NSUnderlyingErrorKey];

                NSString *_Nullable senderE164 = decryptError.userInfo[SecretSessionKnownSenderError.kSenderE164Key];
                NSUUID *_Nullable senderUuid = decryptError.userInfo[SecretSessionKnownSenderError.kSenderUuidKey];
                SignalServiceAddress *senderAddress = [[SignalServiceAddress alloc] initWithUuid:senderUuid
                                                                                     phoneNumber:senderE164];
                OWSAssert(senderAddress.isValid);

                NSNumber *senderDeviceId = decryptError.userInfo[SecretSessionKnownSenderError.kSenderDeviceIdKey];
                OWSAssert(senderDeviceId);

                SSKProtoEnvelopeBuilder *identifiedEnvelopeBuilder = envelope.asBuilder;
                identifiedEnvelopeBuilder.sourceE164 = senderAddress.phoneNumber;
                identifiedEnvelopeBuilder.sourceUuid = senderAddress.uuidString;
                identifiedEnvelopeBuilder.sourceDevice = senderDeviceId.unsignedIntValue;
                NSError *identifiedEnvelopeBuilderError;

                identifiedEnvelope = [identifiedEnvelopeBuilder buildAndReturnError:&identifiedEnvelopeBuilderError];
                if (identifiedEnvelopeBuilderError) {
                    OWSFailDebug(@"failure identifiedEnvelopeBuilderError: %@", identifiedEnvelopeBuilderError);
                }
            }
            OWSAssert(underlyingError);
            OWSAssert(identifiedEnvelope);

            NSException *_Nullable underlyingException;
            if ([underlyingError.domain isEqualToString:SCKExceptionWrapperErrorDomain]
                && underlyingError.code == SCKExceptionWrapperErrorThrown) {

                underlyingException = underlyingError.userInfo[SCKExceptionWrapperUnderlyingExceptionKey];
                OWSAssert(underlyingException);
            }

            // Decrypt Failure Part 2: Handle unwrapped failure details

            if (underlyingException) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self processException:underlyingException envelope:identifiedEnvelope];
                    NSString *errorDescription = [NSString
                        stringWithFormat:@"Exception while decrypting ud message: %@", underlyingException.description];
                    OWSLogError(@"%@", errorDescription);
                    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                    failureBlock(error);
                });
                return;
            }

            if ([underlyingError.domain isEqualToString:@"SignalMetadataKit.SMKSecretSessionCipherError"]
                && underlyingError.code == SMKSecretSessionCipherErrorSelfSentMessage) {
                // Self-sent messages can be safely discarded.
                failureBlock(underlyingError);
                return;
            }

            OWSFailDebug(@"Could not decrypt UD message: %@", underlyingError);
            failureBlock(underlyingError);
            return;
        }

        if (decryptResult.messageType == SMKMessageTypePrekey) {
            [TSPreKeyManager checkPreKeys];
        }

        NSString *_Nullable senderE164 = decryptResult.senderE164;
        NSUUID *_Nullable senderUuid = decryptResult.senderUuid;
        SignalServiceAddress *sourceAddress = [[SignalServiceAddress alloc] initWithUuid:senderUuid
                                                                             phoneNumber:senderE164];
        if (!sourceAddress.isValid) {
            NSString *errorDescription = [NSString stringWithFormat:@"Invalid UD sender: %@", sourceAddress];
            OWSFailDebug(@"%@", errorDescription);
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
            return failureBlock(error);
        }

        long sourceDeviceId = decryptResult.senderDeviceId;
        if (sourceDeviceId < 1 || sourceDeviceId > UINT32_MAX) {
            NSString *errorDescription = @"Invalid UD sender device id.";
            OWSFailDebug(@"%@", errorDescription);
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptUDMessage, errorDescription);
            return failureBlock(error);
        }
        NSData *plaintextData = [decryptResult.paddedPayload removePadding];

        SSKProtoEnvelopeBuilder *envelopeBuilder = [envelope asBuilder];
        [envelopeBuilder setSourceE164:sourceAddress.phoneNumber];
        [envelopeBuilder setSourceUuid:sourceAddress.uuidString];
        [envelopeBuilder setSourceDevice:(uint32_t)sourceDeviceId];
        NSError *envelopeBuilderError;
        NSData *_Nullable newEnvelopeData = [envelopeBuilder buildSerializedDataAndReturnError:&envelopeBuilderError];
        if (envelopeBuilderError || !newEnvelopeData) {
            OWSFailDebug(@"Could not update UD envelope data: %@", envelopeBuilderError);
            NSError *error = EnsureDecryptError(envelopeBuilderError, @"Could not update UD envelope data");
            return failureBlock(error);
        }

        OWSMessageDecryptResult *result = [OWSMessageDecryptResult resultWithEnvelopeData:newEnvelopeData
                                                                            plaintextData:plaintextData
                                                                            sourceAddress:sourceAddress
                                                                             sourceDevice:(uint32_t)sourceDeviceId
                                                                              isUDMessage:YES];
        successBlock(result, transaction);
    }];
}

- (void)processException:(NSException *)exception envelope:(SSKProtoEnvelope *)envelope
{
    NSString *logString = [NSString stringWithFormat:@"Got exception: %@ of type: %@ with reason: %@",
                                    exception.description,
                                    exception.name,
                                    exception.reason];
    if ([exception.name isEqualToString:DuplicateMessageException]) {
        OWSLogInfo(@"%@", logString);
    } else {
        OWSLogError(@"%@", logString);
    }

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSErrorMessage *errorMessage;

        if (!envelope.sourceAddress.isValid) {
            ThreadlessErrorMessage *errorMessage = [ThreadlessErrorMessage corruptedMessageInUnknownThread];
            [SSKEnvironment.shared.notificationsManager notifyUserForThreadlessErrorMessage:errorMessage
                                                                                transaction:transaction];
            return;
        }

        if ([exception.name isEqualToString:NoSessionException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorNoSession], envelope);
            errorMessage = [TSErrorMessage missingSessionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:InvalidKeyException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidKey], envelope);
            errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:InvalidKeyIdException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidKeyId], envelope);
            errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:DuplicateMessageException]) {
            // Duplicate messages are silently discarded.
            return;
        } else if ([exception.name isEqualToString:InvalidVersionException]) {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorInvalidMessageVersion], envelope);
            errorMessage = [TSErrorMessage invalidVersionWithEnvelope:envelope withTransaction:transaction];
        } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
            // Should no longer get here, since we now record the new identity for incoming messages.
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorUntrustedIdentityKeyException], envelope);
            OWSFailDebug(@"Failed to trust identity on incoming message from: %@", envelopeAddress(envelope));
            return;
        } else {
            OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorCorruptMessage], envelope);
            errorMessage = [TSErrorMessage corruptedMessageWithEnvelope:envelope withTransaction:transaction];
        }

        OWSAssertDebug(errorMessage);
        if (errorMessage != nil) {
            [errorMessage anyInsertWithTransaction:transaction];
            [self notifyUserForErrorMessage:errorMessage envelope:envelope transaction:transaction];
        }
    }];
}

- (void)notifyUserForErrorMessage:(TSErrorMessage *)errorMessage
                         envelope:(SSKProtoEnvelope *)envelope
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    TSThread *contactThread = [TSContactThread getOrCreateThreadWithContactAddress:envelope.sourceAddress
                                                                       transaction:transaction];
    [SSKEnvironment.shared.notificationsManager notifyUserForErrorMessage:errorMessage
                                                                   thread:contactThread
                                                              transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
