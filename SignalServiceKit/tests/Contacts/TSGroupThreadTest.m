//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSGroupThread.h"
#import "SSKBaseTestObjC.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSGroupThreadTest : SSKBaseTestObjC

@end

@implementation TSGroupThreadTest

- (void)testHasSafetyNumbers
{
    TSGroupThread *groupThread = [TSGroupThread new];
    XCTAssertFalse(groupThread.hasSafetyNumbers);
}

@end

NS_ASSUME_NONNULL_END
