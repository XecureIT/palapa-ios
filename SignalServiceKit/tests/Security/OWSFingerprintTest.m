//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSFingerprint.h"
#import "SSKBaseTestObjC.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface OWSFingerprintTest : SSKBaseTestObjC

@end

#pragma mark -

@implementation OWSFingerprintTest

- (void)testDisplayableTextInsertsSpaces
{
    SignalServiceAddress *aliceStableAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+13231111111"];
    NSData *aliceIdentityKey = [Curve25519 generateKeyPair].publicKey;
    SignalServiceAddress *bobStableAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+14152222222"];
    NSData *bobIdentityKey = [Curve25519 generateKeyPair].publicKey;

    OWSFingerprint *aliceFingerprint = [OWSFingerprint fingerprintWithMyStableAddress:aliceStableAddress
                                                                        myIdentityKey:aliceIdentityKey
                                                                   theirStableAddress:bobStableAddress
                                                                     theirIdentityKey:bobIdentityKey
                                                                            theirName:@"Bob"
                                                                       hashIterations:2];

    NSString *displayableText = aliceFingerprint.displayableText;
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(0, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(1, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(2, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(3, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(4, 1)]);
    XCTAssertEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(5, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(6, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(7, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(8, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(9, 1)]);
    XCTAssertNotEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(10, 1)]);
    XCTAssertEqualObjects(@" ", [displayableText substringWithRange:NSMakeRange(11, 1)]);
}

- (void)testTextMatchesReciprocally
{
    SignalServiceAddress *aliceStableAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+13231111111"];
    NSData *aliceIdentityKey = [Curve25519 generateKeyPair].publicKey;
    SignalServiceAddress *bobStableAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+14152222222"];
    NSData *bobIdentityKey = [Curve25519 generateKeyPair].publicKey;
    SignalServiceAddress *charlieStableAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+14153333333"];
    NSData *charlieIdentityKey = [Curve25519 generateKeyPair].publicKey;

    OWSFingerprint *aliceFingerprint = [OWSFingerprint fingerprintWithMyStableAddress:aliceStableAddress
                                                                        myIdentityKey:aliceIdentityKey
                                                                   theirStableAddress:bobStableAddress
                                                                     theirIdentityKey:bobIdentityKey
                                                                            theirName:@"Bob"
                                                                       hashIterations:2];

    OWSFingerprint *bobFingerprint = [OWSFingerprint fingerprintWithMyStableAddress:bobStableAddress
                                                                      myIdentityKey:bobIdentityKey
                                                                 theirStableAddress:aliceStableAddress
                                                                   theirIdentityKey:aliceIdentityKey
                                                                          theirName:@"Alice"
                                                                     hashIterations:2];

    OWSFingerprint *charlieFingerprint = [OWSFingerprint fingerprintWithMyStableAddress:charlieStableAddress
                                                                          myIdentityKey:charlieIdentityKey
                                                                     theirStableAddress:aliceStableAddress
                                                                       theirIdentityKey:aliceIdentityKey
                                                                              theirName:@"Alice"
                                                                         hashIterations:2];

    XCTAssertEqualObjects(aliceFingerprint.displayableText, bobFingerprint.displayableText);
    XCTAssertNotEqualObjects(aliceFingerprint.displayableText, charlieFingerprint.displayableText);
}

@end
