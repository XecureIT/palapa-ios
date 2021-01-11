//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSUploadV2.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSRequestFactory.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSSocketManager.h>

NS_ASSUME_NONNULL_BEGIN

void AppendMultipartFormPath(id<AFMultipartFormData> formData, NSString *name, NSString *dataString)
{
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];

    [formData appendPartWithFormData:data name:name];
}

#pragma mark -

@interface OWSUploadForm : NSObject

// These properties will bet set for all uploads.
@property (nonatomic) NSString *formAcl;
@property (nonatomic) NSString *formKey;
@property (nonatomic) NSString *formPolicy;
@property (nonatomic) NSString *formAlgorithm;
@property (nonatomic) NSString *formCredential;
@property (nonatomic) NSString *formDate;
@property (nonatomic) NSString *formSignature;

// These properties will bet set for all attachment uploads.
@property (nonatomic, nullable) NSNumber *attachmentId;
@property (nonatomic, nullable) NSString *attachmentIdString;

// These properties will be set for all uploads without cdn
@property (nonatomic, nullable) NSString *location;

@end

#pragma mark -

// See: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html
@implementation OWSUploadForm

#pragma mark - Dependencies

- (AFHTTPSessionManager *)noCdnSessionManager
{
    return [OWSSignalService sharedInstance].noCDNSessionManager;
}

+ (nullable OWSUploadForm *)parse:(nullable NSDictionary *)formResponseObject
{
    if (![formResponseObject isKindOfClass:[NSDictionary class]]) {
        OWSFailDebug(@"Invalid upload form.");
        return nil;
    }
    NSDictionary *responseMap = formResponseObject;

    NSString *_Nullable formAcl = responseMap[@"acl"];
    if (![formAcl isKindOfClass:[NSString class]] || formAcl.length < 1) {
        OWSFailDebug(@"Invalid upload form: acl.");
        return nil;
    }
    NSString *_Nullable formKey = responseMap[@"key"];
    if (![formKey isKindOfClass:[NSString class]] || formKey.length < 1) {
        OWSFailDebug(@"Invalid upload form: key.");
        return nil;
    }
    NSString *_Nullable formPolicy = responseMap[@"policy"];
    if (![formPolicy isKindOfClass:[NSString class]] || formPolicy.length < 1) {
        OWSFailDebug(@"Invalid upload form: policy.");
        return nil;
    }
    NSString *_Nullable formAlgorithm = responseMap[@"algorithm"];
    if (![formAlgorithm isKindOfClass:[NSString class]] || formAlgorithm.length < 1) {
        OWSFailDebug(@"Invalid upload form: algorithm.");
        return nil;
    }
    NSString *_Nullable formCredential = responseMap[@"credential"];
    if (![formCredential isKindOfClass:[NSString class]] || formCredential.length < 1) {
        OWSFailDebug(@"Invalid upload form: credential.");
        return nil;
    }
    NSString *_Nullable formDate = responseMap[@"date"];
    if (![formDate isKindOfClass:[NSString class]] || formDate.length < 1) {
        OWSFailDebug(@"Invalid upload form: date.");
        return nil;
    }
    NSString *_Nullable formSignature = responseMap[@"signature"];
    if (![formSignature isKindOfClass:[NSString class]] || formSignature.length < 1) {
        OWSFailDebug(@"Invalid upload form: signature.");
        return nil;
    }

    NSNumber *_Nullable attachmentId = responseMap[@"attachmentId"];
    if (attachmentId == nil) {
        // This value is optional.
    } else if (![attachmentId isKindOfClass:[NSNumber class]]) {
        OWSFailDebug(@"Invalid upload form: attachmentId.");
        return nil;
    }
    NSString *_Nullable attachmentIdString = responseMap[@"attachmentIdString"];
    if (attachmentIdString == nil) {
        // This value is optional.
    } else if (![attachmentIdString isKindOfClass:[NSString class]] || attachmentIdString.length < 1) {
        OWSFailDebug(@"Invalid upload form: attachmentIdString.");
        return nil;
    }

    OWSUploadForm *form = [OWSUploadForm new];
    
    // Required properties.
    form.formAcl = formAcl;
    form.formKey = formKey;
    form.formPolicy = formPolicy;
    form.formAlgorithm = formAlgorithm;
    form.formCredential = formCredential;
    form.formDate = formDate;
    form.formSignature = formSignature;

    // Optional properties.
    form.attachmentId = attachmentId;
    form.attachmentIdString = attachmentIdString;

    return form;
}

+ (nullable OWSUploadForm *)parseAvatarForm:(nullable NSDictionary *)formResponseObject
{
    if (![formResponseObject isKindOfClass:[NSDictionary class]]) {
        OWSFailDebug(@"Invalid avatar form.");
        return nil;
    }
    NSDictionary *responseMap = formResponseObject;

    NSString *_Nullable formKey = responseMap[@"key"];
    if (![formKey isKindOfClass:[NSString class]] || formKey.length < 1) {
        OWSFailDebug(@"Invalid avatar form: key.");
        return nil;
    }
    NSString *_Nullable location = responseMap[@"location"];
    if (![location isKindOfClass:[NSString class]] || location.length < 1) {
        OWSFailDebug(@"Invalid avatar form: location.");
        return nil;
    }

    OWSUploadForm *form = [OWSUploadForm new];
    
    // Required properties.
    form.formKey = formKey;
    form.location = location;

    return form;
}

+ (nullable OWSUploadForm *)parseAttachmentForm:(nullable NSDictionary *)formResponseObject
{
    if (![formResponseObject isKindOfClass:[NSDictionary class]]) {
        OWSFailDebug(@"Invalid attachment form.");
        return nil;
    }
    NSDictionary *responseMap = formResponseObject;

    NSNumber *_Nullable attachmentId = responseMap[@"id"];
    if (![attachmentId isKindOfClass:[NSNumber class]]) {
        OWSFailDebug(@"Invalid attachment form: id.");
        return nil;
    }
    NSString *_Nullable location = responseMap[@"location"];
    if (![location isKindOfClass:[NSString class]] || location.length < 1) {
        OWSFailDebug(@"Invalid attachment form: location.");
        return nil;
    }

    OWSUploadForm *form = [OWSUploadForm new];
    
    // Required properties.
    form.attachmentId = attachmentId;
    form.location = location;

    return form;
}

- (void)appendToForm:(id<AFMultipartFormData>)formData
{
    // We have to build up the form manually vs. simply passing in a paramaters dict
    // because AWS is sensitive to the order of the form params (at least the "key"
    // field must occur early on).
    //
    // For consistency, all fields are ordered here in a known working order.
    AppendMultipartFormPath(formData, @"key", self.formKey);
    AppendMultipartFormPath(formData, @"acl", self.formAcl);
    AppendMultipartFormPath(formData, @"x-amz-algorithm", self.formAlgorithm);
    AppendMultipartFormPath(formData, @"x-amz-credential", self.formCredential);
    AppendMultipartFormPath(formData, @"x-amz-date", self.formDate);
    AppendMultipartFormPath(formData, @"policy", self.formPolicy);
    AppendMultipartFormPath(formData, @"x-amz-signature", self.formSignature);
}

- (void)uploadNoCdn:(NSData *_Nonnull)uploadData
           progress:(nullable void (^)(NSProgress * _Nonnull))uploadProgress
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure

{
    AFHTTPSessionManager *sessionManager = self.noCdnSessionManager;
    
    __block NSURLSessionUploadTask *uploadTask;
    NSURL *URL = [[NSURL alloc] initWithString:self.location];
    NSError *serializationError = nil;
    NSMutableURLRequest *request = [sessionManager.requestSerializer requestWithMethod:@"PUT"
                                                                      URLString:URL.absoluteString
                                                                     parameters:nil
                                                                          error:&serializationError];
        
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[uploadData length]] forHTTPHeaderField:@"Content-Length"];
    [request setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    
    if (serializationError) {
        failure(uploadTask, serializationError);
        return;
    }
    
    uploadTask = [sessionManager uploadTaskWithRequest:request fromData:uploadData progress:uploadProgress completionHandler:^(NSURLResponse * _Nonnull response, id _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            failure(uploadTask, error);
        } else {
            success(uploadTask, responseObject);
        }
    }];
    
    [uploadTask resume];
}

@end

#pragma mark -

@interface OWSAvatarUploadV2 ()

@property (nonatomic, nullable) NSData *avatarData;

@end

#pragma mark -

@implementation OWSAvatarUploadV2

#pragma mark - Dependencies

- (AFHTTPSessionManager *)uploadHTTPManager
{
    return [OWSSignalService sharedInstance].CDNSessionManager;
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

#pragma mark - Avatars

// If avatarData is nil, we are clearing the avatar.
- (AnyPromise *)uploadAvatarToService:(nullable NSData *)avatarData
                     clearLocalAvatar:(dispatch_block_t)clearLocalAvatar
                        progressBlock:(UploadProgressBlock)progressBlock
                                noCdn:(BOOL)noCdn
{
    OWSAssertDebug(avatarData == nil || avatarData.length > 0);
    self.avatarData = avatarData;

    __weak OWSAvatarUploadV2 *weakSelf = self;
    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            TSRequest *formRequest = noCdn ?
                                     [OWSRequestFactory profileAvatarUploadRequestNoCdn] :
                                     [OWSRequestFactory profileAvatarUploadFormRequest];
            
            [self.networkManager makeRequest:formRequest
                success:^(NSURLSessionDataTask *task, id _Nullable formResponseObject) {
                    OWSAvatarUploadV2 *_Nullable strongSelf = weakSelf;
                    if (!strongSelf) {
                        return resolve(OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Upload deallocated"));
                    }

                    if (avatarData == nil) {
                        OWSLogDebug(@"successfully cleared avatar");
                        clearLocalAvatar();
                        return resolve(@(1));
                    }

                    // TODO: Should we use a non-empty urlPath?
                    [[strongSelf parseFormAndUpload:formResponseObject urlPath:@"" progressBlock:progressBlock noCdn:noCdn]
                            .thenInBackground(^{
                                return resolve(@(1));
                            })
                            .catchInBackground(^(NSError *error) {
                                clearLocalAvatar();

                                resolve(error);
                            }) retainUntilComplete];
                }
                failure:^(NSURLSessionDataTask *task, NSError *error) {
                    // Only clear the local avatar if we have a response. Otherwise, we
                    // had a network failure and probably didn't reach the service.
                    if (task.response != nil) {
                        clearLocalAvatar();
                    }

                    OWSLogError(@"Failed to get profile avatar upload form: %@", error);
                    resolve(error);
                }];
        });
    }];
    return promise;
}

- (AnyPromise *)parseFormAndUpload:(nullable id)formResponseObject
                           urlPath:(NSString *)urlPath
                     progressBlock:(UploadProgressBlock)progressBlock
                             noCdn:(BOOL)noCdn
{
    OWSUploadForm *_Nullable form = noCdn ?
                                    [OWSUploadForm parseAvatarForm:formResponseObject] :
                                    [OWSUploadForm parse:formResponseObject];
    
    if (!form) {
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }

    self.urlPath = form.formKey;

    __weak OWSAvatarUploadV2 *weakSelf = self;
    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        if (noCdn) {
            [form uploadNoCdn:[weakSelf avatarData]
                progress:^(NSProgress *progress) {
                    OWSLogVerbose(@"Upload progress: %.2f%%", progress.fractionCompleted * 100);

                    progressBlock(progress);
                }
                success:^(NSURLSessionDataTask *uploadTask, id _Nullable responseObject) {
                    OWSLogInfo(@"Upload succeeded with key: %@", form.formKey);
                    return resolve(@(1));
                }
                failure:^(NSURLSessionDataTask *_Nullable uploadTask, NSError *error) {
                    OWSLogError(@"Upload failed with error: %@", error);
                    resolve(error);
                }];
        } else {
            [self.uploadHTTPManager POST:urlPath
                parameters:nil
                constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
                    OWSAvatarUploadV2 *_Nullable strongSelf = weakSelf;
                    if (!strongSelf) {
                        return resolve(OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Upload deallocated"));
                    }

                    // We have to build up the form manually vs. simply passing in a paramaters dict
                    // because AWS is sensitive to the order of the form params (at least the "key"
                    // field must occur early on).
                    //
                    // For consistency, all fields are ordered here in a known working order.
                    [form appendToForm:formData];
                    AppendMultipartFormPath(formData, @"Content-Type", OWSMimeTypeApplicationOctetStream);

                    NSData *_Nullable uploadData = strongSelf.avatarData;
                    if (uploadData.length < 1) {
                        OWSCFailDebug(@"Could not load upload data.");
                        return resolve(
                            OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Could not load upload data."));
                    }
                    OWSCAssertDebug(uploadData.length > 0);
                    [formData appendPartWithFormData:uploadData name:@"file"];

                    OWSLogVerbose(@"constructed body");
                }
                progress:^(NSProgress *progress) {
                    OWSLogVerbose(@"Upload progress: %.2f%%", progress.fractionCompleted * 100);

                    progressBlock(progress);
                }
                success:^(NSURLSessionDataTask *uploadTask, id _Nullable responseObject) {
                    OWSLogInfo(@"Upload succeeded with key: %@", form.formKey);
                    return resolve(@(1));
                }
                failure:^(NSURLSessionDataTask *_Nullable uploadTask, NSError *error) {
                    OWSLogError(@"Upload failed with error: %@", error);
                    resolve(error);
                }];
        }
    }];
    return promise;
}

@end

#pragma mark - Attachments

@interface OWSAttachmentUploadV2 ()

@property (nonatomic) TSAttachmentStream *attachmentStream;

@end

#pragma mark -

@implementation OWSAttachmentUploadV2

#pragma mark - Dependencies

- (AFHTTPSessionManager *)uploadHTTPManager
{
    return [OWSSignalService sharedInstance].CDNSessionManager;
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

- (TSSocketManager *)socketManager
{
    return SSKEnvironment.shared.socketManager;
}

#pragma mark -

- (nullable NSData *)attachmentData
{
    OWSAssertDebug(self.attachmentStream);

    NSData *encryptionKey;
    NSData *digest;
    NSError *error;
    NSData *attachmentData = [self.attachmentStream readDataFromFileWithError:&error];
    if (error) {
        OWSLogError(@"Failed to read attachment data with error: %@", error);
        return nil;
    }

    NSData *_Nullable encryptedAttachmentData = [Cryptography encryptAttachmentData:attachmentData
                                                                          shouldPad:YES
                                                                             outKey:&encryptionKey
                                                                          outDigest:&digest];
    if (!encryptedAttachmentData) {
        OWSFailDebug(@"could not encrypt attachment data.");
        return nil;
    }

    self.encryptionKey = encryptionKey;
    self.digest = digest;

    return encryptedAttachmentData;
}

// On success, yields an instance of OWSUploadV2.
- (AnyPromise *)uploadAttachmentToService:(TSAttachmentStream *)attachmentStream
                            progressBlock:(UploadProgressBlock)progressBlock
                                    noCdn:(BOOL)noCdn
{
    OWSAssertDebug(attachmentStream);

    self.attachmentStream = attachmentStream;

    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self uploadAttachmentToService:resolve progressBlock:progressBlock skipWebsocket:NO noCdn:noCdn];
        });
    }];
    return promise;
}

- (void)uploadAttachmentToService:(PMKResolver)resolve
                    progressBlock:(UploadProgressBlock)progressBlock
                    skipWebsocket:(BOOL)skipWebsocket
                            noCdn:(BOOL)noCdn
{
    TSRequest *formRequest = noCdn ?
                             [OWSRequestFactory allocAttachmentRequestNoCdn] :
                             [OWSRequestFactory allocAttachmentRequest];

    BOOL shouldUseWebsocket = (self.socketManager.canMakeRequests && !skipWebsocket);

    __weak OWSAttachmentUploadV2 *weakSelf = self;
    void (^formSuccess)(id _Nullable) = ^(id _Nullable formResponseObject) {
        OWSAttachmentUploadV2 *_Nullable strongSelf = weakSelf;
        if (!strongSelf) {
            return resolve(OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Upload deallocated"));
        }

        [[strongSelf parseFormAndUpload:formResponseObject urlPath:@"attachments/" progressBlock:progressBlock noCdn:noCdn]
                .thenInBackground(^{
                    resolve(@(1));
                })
                .catchInBackground(^(NSError *error) {
                    resolve(error);
                }) retainUntilComplete];
    };
    void (^formFailure)(NSError *) = ^(NSError *error) {
        OWSLogError(@"Failed to get attachment upload form: %@", error);
        resolve(error);
    };

    if (shouldUseWebsocket) {
        [self.socketManager makeRequest:formRequest
            success:^(id _Nullable responseObject) {
                formSuccess(responseObject);
            }
            failure:^(NSInteger statusCode, NSData *_Nullable responseData, NSError *_Nullable error) {
                OWSLogError(@"Websocket request failed: %d, %@", (int)statusCode, error);

                // Try again without websocket.
                [weakSelf uploadAttachmentToService:resolve progressBlock:progressBlock skipWebsocket:YES noCdn:noCdn];
            }];
    } else {
        [self.networkManager makeRequest:formRequest
            success:^(NSURLSessionDataTask *task, id _Nullable formResponseObject) {
                formSuccess(formResponseObject);
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                formFailure(error);
            }];
    }
}

#pragma mark -

- (AnyPromise *)parseFormAndUpload:(nullable id)formResponseObject
                           urlPath:(NSString *)urlPath
                     progressBlock:(UploadProgressBlock)progressBlock
                             noCdn:(BOOL)noCdn
{
    OWSUploadForm *_Nullable form = noCdn ?
                                    [OWSUploadForm parseAttachmentForm:formResponseObject] :
                                    [OWSUploadForm parse:formResponseObject];
    
    if (!form) {
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }
    UInt64 serverId = form.attachmentId.unsignedLongLongValue;
    if (serverId < 1) {
        return [AnyPromise
            promiseWithValue:OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Invalid upload form.")];
    }

    self.serverId = serverId;

    __weak OWSAttachmentUploadV2 *weakSelf = self;
    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        if (noCdn) {
            [form uploadNoCdn:[weakSelf attachmentData]
                 progress:^(NSProgress *progress) {
                     OWSLogVerbose(@"Upload progress: %.2f%%", progress.fractionCompleted * 100);

                     progressBlock(progress);
                 }
                 success:^(NSURLSessionDataTask *uploadTask, id _Nullable responseObject) {
                     OWSAttachmentUploadV2 *_Nullable strongSelf = weakSelf;
                     if (!strongSelf) {
                         return resolve(OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Upload deallocated"));
                     }

                     OWSLogInfo(@"Upload succeeded with key: %@", form.formKey);
                     return resolve(@(1));
                 }
                 failure:^(NSURLSessionDataTask *_Nullable uploadTask, NSError *error) {
                     OWSLogError(@"Upload failed with error: %@", error);
                     resolve(error);
                 }];
        } else {
            [self.uploadHTTPManager POST:urlPath
                parameters:nil
                constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
                    OWSAttachmentUploadV2 *_Nullable strongSelf = weakSelf;
                    if (!strongSelf) {
                        return resolve(OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Upload deallocated"));
                    }

                    // We have to build up the form manually vs. simply passing in a paramaters dict
                    // because AWS is sensitive to the order of the form params (at least the "key"
                    // field must occur early on).
                    //
                    // For consistency, all fields are ordered here in a known working order.
                    [form appendToForm:formData];
                    AppendMultipartFormPath(formData, @"Content-Type", OWSMimeTypeApplicationOctetStream);

                    NSData *_Nullable uploadData = [strongSelf attachmentData];
                    if (uploadData.length < 1) {
                        OWSCFailDebug(@"Could not load upload data.");
                        return resolve(
                            OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Could not load upload data."));
                    }
                    OWSAssertDebug(uploadData.length > 0);
                    [formData appendPartWithFormData:uploadData name:@"file"];

                    OWSLogVerbose(@"constructed %@ body", [NSByteCountFormatter stringFromByteCount:uploadData.length countStyle:NSByteCountFormatterCountStyleFile]);
                }
                progress:^(NSProgress *progress) {
                    OWSLogVerbose(@"Upload progress: %.2f%%", progress.fractionCompleted * 100);

                    progressBlock(progress);
                }
                success:^(NSURLSessionDataTask *uploadTask, id _Nullable responseObject) {
                    OWSAttachmentUploadV2 *_Nullable strongSelf = weakSelf;
                    if (!strongSelf) {
                        return resolve(OWSErrorWithCodeDescription(OWSErrorCodeUploadFailed, @"Upload deallocated"));
                    }

                    OWSLogInfo(@"Upload succeeded with key: %@", form.formKey);
                    return resolve(@(1));
                }
                failure:^(NSURLSessionDataTask *_Nullable uploadTask, NSError *error) {
                    OWSLogError(@"Upload failed with error: %@", error);
                    resolve(error);
                }];
        }
    }];
    return promise;
}

@end

NS_ASSUME_NONNULL_END
