//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKJobRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSIncomingContactSyncJobRecord : SSKJobRecord

@property (class, nonatomic, readonly) NSString *defaultLabel;

@property (nonatomic, readonly) NSString *attachmentId;

- (instancetype)initWithAttachmentId:(NSString *)attachmentId label:(NSString *)label;

- (instancetype)initWithLabel:(NSString *)label NS_UNAVAILABLE;

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                    failureCount:(NSUInteger)failureCount
                           label:(NSString *)label
                          sortId:(unsigned long long)sortId
                          status:(SSKJobRecordStatus)status
                    attachmentId:(NSString *)attachmentId
NS_SWIFT_NAME(init(grdbId:uniqueId:failureCount:label:sortId:status:attachmentId:));

// clang-format on

// --- CODE GENERATION MARKER

@end

NS_ASSUME_NONNULL_END
