//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface RemoteAttestationQuote : NSObject

@property (nonatomic, readonly) uint16_t version;
@property (nonatomic, readonly) uint16_t signType;
@property (nonatomic, readonly) BOOL isSigLinkable;
@property (nonatomic, readonly) uint32_t gid;
@property (nonatomic, readonly) uint16_t qeSvn;
@property (nonatomic, readonly) uint16_t pceSvn;
@property (nonatomic, readonly) NSData *basename;
@property (nonatomic, readonly) NSData *cpuSvn;
@property (nonatomic, readonly) uint64_t flags;
@property (nonatomic, readonly) uint64_t xfrm;
@property (nonatomic, readonly) NSData *mrenclave;
@property (nonatomic, readonly) NSData *mrsigner;
@property (nonatomic, readonly) uint16_t isvProdId;
@property (nonatomic, readonly) uint16_t isvSvn;
@property (nonatomic, readonly) NSData *reportData;
@property (nonatomic, readonly) NSData *signature;

+ (nullable RemoteAttestationQuote *)parseQuoteFromData:(NSData *)quoteData;

- (BOOL)isDebugQuote;

@end

NS_ASSUME_NONNULL_END
