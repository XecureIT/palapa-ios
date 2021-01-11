//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSNotificationName_DeviceListUpdateSucceeded;
extern NSString *const NSNotificationName_DeviceListUpdateFailed;
extern NSString *const NSNotificationName_DeviceListUpdateModifiedDeviceList;

@class OWSDevice;

@interface OWSDevicesService : NSObject

+ (void)refreshDevices;

+ (void)unlinkDevice:(OWSDevice *)device
             success:(void (^)(void))successCallback
             failure:(void (^)(NSError *))failureCallback;

@end

NS_ASSUME_NONNULL_END
