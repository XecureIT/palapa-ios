//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSContactOffersInteraction.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersInteraction ()

@property (nonatomic) BOOL hasBlockOffer;
@property (nonatomic) BOOL hasAddToContactsOffer;
@property (nonatomic) BOOL hasAddToProfileWhitelistOffer;

@end

@implementation OWSContactOffersInteraction

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                        timestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                    hasBlockOffer:(BOOL)hasBlockOffer
            hasAddToContactsOffer:(BOOL)hasAddToContactsOffer
    hasAddToProfileWhitelistOffer:(BOOL)hasAddToProfileWhitelistOffer
{
    self = [super initWithUniqueId:uniqueId timestamp:timestamp inThread:thread];

    if (!self) {
        return self;
    }

    _hasBlockOffer = hasBlockOffer;
    _hasAddToContactsOffer = hasAddToContactsOffer;
    _hasAddToProfileWhitelistOffer = hasAddToProfileWhitelistOffer;

    return self;
}

- (BOOL)shouldUseReceiptDateForSorting
{
    // Use the timestamp, not the "received at" timestamp to sort,
    // since we're creating these interactions after the fact and back-dating them.
    return NO;
}

- (BOOL)isDynamicInteraction
{
    return YES;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_Offer;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSFailDebug(@"This interaction should never be saved to the database.");
}

@end

NS_ASSUME_NONNULL_END
