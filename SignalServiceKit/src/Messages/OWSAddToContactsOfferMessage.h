//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"

NS_ASSUME_NONNULL_BEGIN

// This is a deprecated class, we're keeping it around to avoid YapDB serialization errors
// TODO - remove this class, clean up existing instances, ensure any missed ones don't explode (UnknownDBObject)
__attribute__((deprecated)) @interface OWSAddToContactsOfferMessage : TSInfoMessage

// --- CODE GENERATION MARKER

// --- CODE GENERATION MARKER

@end

NS_ASSUME_NONNULL_END
