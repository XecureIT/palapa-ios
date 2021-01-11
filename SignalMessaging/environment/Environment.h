//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SSKEnvironment.h>

@class LaunchJobs;
@class OWSAudioSession;
@class OWSContactsManager;
@class OWSIncomingContactSyncJobQueue;
@class OWSIncomingGroupSyncJobQueue;
@class OWSPreferences;
@class OWSSounds;
@class OWSWindowManager;

@protocol OWSProximityMonitoringManager;

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/
// TODO: Rename to SMGEnvironment?
@interface Environment : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithAudioSession:(OWSAudioSession *)audioSession
         incomingContactSyncJobQueue:(OWSIncomingContactSyncJobQueue *)incomingContactSyncJobQueue
           incomingGroupSyncJobQueue:(OWSIncomingGroupSyncJobQueue *)incomingGroupSyncJobQueue
                          launchJobs:(LaunchJobs *)launchJobs
                         preferences:(OWSPreferences *)preferences
          proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                              sounds:(OWSSounds *)sounds
                       windowManager:(OWSWindowManager *)windowManager;

@property (nonatomic, readonly) OWSAudioSession *audioSession;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSIncomingContactSyncJobQueue *incomingContactSyncJobQueue;
@property (nonatomic, readonly) OWSIncomingGroupSyncJobQueue *incomingGroupSyncJobQueue;
@property (nonatomic, readonly) LaunchJobs *launchJobs;
@property (nonatomic, readonly) id<OWSProximityMonitoringManager> proximityMonitoringManager;
@property (nonatomic, readonly) OWSPreferences *preferences;
@property (nonatomic, readonly) OWSSounds *sounds;
@property (nonatomic, readonly) OWSWindowManager *windowManager;

@property (class, nonatomic) Environment *shared;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

@end
