//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;
@class OWSDevice;
@class PreKeyRecord;
@class SMKUDAccessKey;
@class SignalServiceAddress;
@class SignedPreKeyRecord;
@class TSRequest;

typedef NS_ENUM(NSUInteger, RemoteAttestationService);
typedef NS_ENUM(NSUInteger, TSVerificationTransport) { TSVerificationTransportVoice = 1, TSVerificationTransportSMS };

@interface OWSRequestFactory : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (TSRequest *)enable2FARequestWithPin:(NSString *)pin;

+ (TSRequest *)disable2FARequest;

+ (TSRequest *)enableRegistrationLockV2RequestWithToken:(NSString *)token;

+ (TSRequest *)disableRegistrationLockV2Request;

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithAddress:(SignalServiceAddress *)address timestamp:(UInt64)timestamp;

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithServerGuid:(NSString *)serverGuid;

+ (TSRequest *)deleteDeviceRequestWithDevice:(OWSDevice *)device;

+ (TSRequest *)deviceProvisioningCodeRequest;

+ (TSRequest *)deviceProvisioningRequestWithMessageBody:(NSData *)messageBody ephemeralDeviceId:(NSString *)deviceId;

+ (TSRequest *)getDevicesRequest;

+ (TSRequest *)getMessagesRequest;

+ (TSRequest *)getProfileRequestWithAddress:(SignalServiceAddress *)address
                                udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
    NS_SWIFT_NAME(getProfileRequest(address:udAccessKey:));

+ (TSRequest *)turnServerInfoRequest;

+ (TSRequest *)allocAttachmentRequest;

+ (TSRequest *)allocAttachmentRequestNoCdn;

+ (TSRequest *)attachmentRequestWithAttachmentId:(UInt64)attachmentId;

+ (TSRequest *)contactsIntersectionRequestWithHashesArray:(NSArray<NSString *> *)hashes;

+ (TSRequest *)profileAvatarUploadFormRequest;

+ (TSRequest *)profileAvatarUploadRequestNoCdn;

+ (TSRequest *)profileAvatarRetrieveRequestNoCdn:(NSString *)avatarId;

+ (TSRequest *)registerForPushRequestWithPushIdentifier:(NSString *)identifier voipIdentifier:(NSString *)voipId;

+ (TSRequest *)updateAttributesRequest;

+ (TSRequest *)accountWhoAmIRequest;

+ (TSRequest *)unregisterAccountRequest;

+ (TSRequest *)requestPreauthChallengeRequestWithRecipientId:(NSString *)recipientId
                                                   pushToken:(NSString *)pushToken
    NS_SWIFT_NAME(requestPreauthChallengeRequest(recipientId:pushToken:));

+ (TSRequest *)requestVerificationCodeRequestWithPhoneNumber:(NSString *)phoneNumber
                                            preauthChallenge:(nullable NSString *)preauthChallenge
                                                captchaToken:(nullable NSString *)captchaToken
                                                   transport:(TSVerificationTransport)transport;

+ (TSRequest *)submitMessageRequestWithAddress:(SignalServiceAddress *)recipientAddress
                                      messages:(NSArray *)messages
                                     timeStamp:(uint64_t)timeStamp
                                   udAccessKey:(nullable SMKUDAccessKey *)udAccessKey;

+ (TSRequest *)verifyPrimaryDeviceRequestWithVerificationCode:(NSString *)verificationCode
                                                  phoneNumber:(NSString *)phoneNumber
                                                      authKey:(NSString *)authKey
                                                          pin:(nullable NSString *)pin
    NS_SWIFT_NAME(verifyPrimaryDeviceRequest(verificationCode:phoneNumber:authKey:pin:));

+ (TSRequest *)verifySecondaryDeviceRequestWithVerificationCode:(NSString *)verificationCode
                                                    phoneNumber:(NSString *)phoneNumber
                                                        authKey:(NSString *)authKey
                                                     deviceName:(NSString *)deviceName
    NS_SWIFT_NAME(verifySecondaryDeviceRequest(verificationCode:phoneNumber:authKey:deviceName:));

#pragma mark - Prekeys

+ (TSRequest *)availablePreKeysCountRequest;

+ (TSRequest *)currentSignedPreKeyRequest;

+ (TSRequest *)recipientPreKeyRequestWithAddress:(SignalServiceAddress *)recipientAddress
                                        deviceId:(NSString *)deviceId
                                     udAccessKey:(nullable SMKUDAccessKey *)udAccessKey;

+ (TSRequest *)registerSignedPrekeyRequestWithSignedPreKeyRecord:(SignedPreKeyRecord *)signedPreKey;

+ (TSRequest *)registerPrekeysRequestWithPrekeyArray:(NSArray *)prekeys
                                         identityKey:(NSData *)identityKeyPublic
                                        signedPreKey:(SignedPreKeyRecord *)signedPreKey;

#pragma mark - Storage Service

+ (TSRequest *)storageAuthRequest;

#pragma mark - Remote Attestation

+ (TSRequest *)remoteAttestationRequestForService:(RemoteAttestationService)service
                                      withKeyPair:(ECKeyPair *)keyPair
                                      enclaveName:(NSString *)enclaveName
                                     authUsername:(NSString *)authUsername
                                     authPassword:(NSString *)authPassword;

+ (TSRequest *)remoteAttestationAuthRequestForService:(RemoteAttestationService)service;

#pragma mark - CDS

+ (TSRequest *)cdsEnclaveRequestWithRequestId:(NSData *)requestId
                                 addressCount:(NSUInteger)addressCount
                         encryptedAddressData:(NSData *)encryptedAddressData
                                      cryptIv:(NSData *)cryptIv
                                     cryptMac:(NSData *)cryptMac
                                  enclaveName:(NSString *)enclaveName
                                 authUsername:(NSString *)authUsername
                                 authPassword:(NSString *)authPassword
                                      cookies:(NSArray<NSHTTPCookie *> *)cookies;
+ (TSRequest *)cdsFeedbackRequestWithStatus:(NSString *)status
                                     reason:(nullable NSString *)reason NS_SWIFT_NAME(cdsFeedbackRequest(status:reason:));

#pragma mark - KBS

+ (TSRequest *)kbsEnclaveTokenRequestWithEnclaveName:(NSString *)enclaveName
                                        authUsername:(NSString *)authUsername
                                        authPassword:(NSString *)authPassword
                                             cookies:(NSArray<NSHTTPCookie *> *)cookies;

+ (TSRequest *)kbsEnclaveRequestWithRequestId:(NSData *)requestId
                                         data:(NSData *)data
                                      cryptIv:(NSData *)cryptIv
                                     cryptMac:(NSData *)cryptMac
                                  enclaveName:(NSString *)enclaveName
                                 authUsername:(NSString *)authUsername
                                 authPassword:(NSString *)authPassword
                                      cookies:(NSArray<NSHTTPCookie *> *)cookies;

#pragma mark - UD

+ (TSRequest *)udSenderCertificateRequest;

#pragma mark - Usernames

+ (TSRequest *)usernameSetRequest:(NSString *)username;
+ (TSRequest *)usernameDeleteRequest;
+ (TSRequest *)getProfileRequestWithUsername:(NSString *)username;

@end

NS_ASSUME_NONNULL_END
