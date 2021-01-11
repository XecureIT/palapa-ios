//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSMessage;
@class TSThread;

@interface OWSMessageUtils : NSObject

+ (instancetype)sharedManager;

- (NSUInteger)unreadMessagesCount;
- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;

- (void)updateApplicationBadgeCount;

@end

NS_ASSUME_NONNULL_END
