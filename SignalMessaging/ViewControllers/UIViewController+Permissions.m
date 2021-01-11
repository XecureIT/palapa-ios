//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "UIViewController+Permissions.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIUtil.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (Permissions)

- (void)ows_askForCameraPermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForCameraPermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^callback)(BOOL) = ^(BOOL granted) {
        DispatchMainThreadSafe(^{
            callbackParam(granted);
        });
    };

    if (CurrentAppContext().reportedApplicationState == UIApplicationStateBackground) {
        OWSLogError(@"Skipping camera permissions request when app is in background.");
        callback(NO);
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]
        && !Platform.isSimulator) {
        OWSLogError(@"Camera ImagePicker source not available");
        callback(NO);
        return;
    }

    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusDenied) {
        ActionSheetController *alert = [[ActionSheetController alloc]
            initWithTitle:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_TITLE", @"Alert title")
                  message:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_MESSAGE", @"Alert body")];

        ActionSheetAction *_Nullable openSettingsAction = [CurrentAppContext() openSystemSettingsActionWithCompletion:^{
            callback(NO);
        }];
        if (openSettingsAction != nil) {
            [alert addAction:openSettingsAction];
        }

        ActionSheetAction *dismissAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.dismissButton
                                                                              style:ActionSheetActionStyleCancel
                                                                            handler:^(ActionSheetAction *action) {
                                                                                callback(NO);
                                                                            }];
        [alert addAction:dismissAction];

        [self presentActionSheet:alert];
    } else if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:callback];
    } else {
        OWSLogError(@"Unknown AVAuthorizationStatus: %ld", (long)status);
        callback(NO);
    }
}

- (void)ows_askForMediaLibraryPermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForMediaLibraryPermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^completionCallback)(BOOL) = ^(BOOL granted) {
        DispatchMainThreadSafe(^{
            callbackParam(granted);
        });
    };

    void (^presentSettingsDialog)(void) = ^(void) {
        DispatchMainThreadSafe(^{
            ActionSheetController *alert = [[ActionSheetController alloc]
                initWithTitle:NSLocalizedString(@"MISSING_MEDIA_LIBRARY_PERMISSION_TITLE",
                                  @"Alert title when user has previously denied media library access")
                      message:NSLocalizedString(@"MISSING_MEDIA_LIBRARY_PERMISSION_MESSAGE",
                                  @"Alert body when user has previously denied media library access")];

            ActionSheetAction *_Nullable openSettingsAction =
                [CurrentAppContext() openSystemSettingsActionWithCompletion:^() {
                    completionCallback(NO);
                }];
            if (openSettingsAction) {
                [alert addAction:openSettingsAction];
            }

            ActionSheetAction *dismissAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.dismissButton
                                                                                  style:ActionSheetActionStyleCancel
                                                                                handler:^(ActionSheetAction *action) {
                                                                                    completionCallback(NO);
                                                                                }];
            [alert addAction:dismissAction];

            [self presentActionSheet:alert];
        });
    };

    if (CurrentAppContext().reportedApplicationState == UIApplicationStateBackground) {
        OWSLogError(@"Skipping media library permissions request when app is in background.");
        completionCallback(NO);
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        OWSLogError(@"PhotoLibrary ImagePicker source not available");
        completionCallback(NO);
    }

    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];

    switch (status) {
        case PHAuthorizationStatusAuthorized: {
            completionCallback(YES);
            return;
        }
        case PHAuthorizationStatusDenied: {
            presentSettingsDialog();
            return;
        }
        case PHAuthorizationStatusNotDetermined: {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus newStatus) {
                if (newStatus == PHAuthorizationStatusAuthorized) {
                    completionCallback(YES);
                } else {
                    presentSettingsDialog();
                }
            }];
            return;
        }
        case PHAuthorizationStatusRestricted: {
            // when does this happen?
            OWSFailDebug(@"PHAuthorizationStatusRestricted");
            return;
        }
    }
}

- (void)ows_askForMicrophonePermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForMicrophonePermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^callback)(BOOL) = ^(BOOL granted) {
        DispatchMainThreadSafe(^{
            callbackParam(granted);
        });
    };

    if (CurrentAppContext().reportedApplicationState == UIApplicationStateBackground) {
        OWSLogError(@"Skipping microphone permissions request when app is in background.");
        callback(NO);
        return;
    }

    [[AVAudioSession sharedInstance] requestRecordPermission:callback];
}

- (void)ows_showNoMicrophonePermissionActionSheet
{
    DispatchMainThreadSafe(^{
        ActionSheetController *alert = [[ActionSheetController alloc]
            initWithTitle:NSLocalizedString(@"CALL_AUDIO_PERMISSION_TITLE",
                              @"Alert title when calling and permissions for microphone are missing")
                  message:NSLocalizedString(@"CALL_AUDIO_PERMISSION_MESSAGE",
                              @"Alert message when calling and permissions for microphone are missing")];

        ActionSheetAction *_Nullable openSettingsAction =
            [CurrentAppContext() openSystemSettingsActionWithCompletion:nil];
        if (openSettingsAction) {
            [alert addAction:openSettingsAction];
        }

        [alert addAction:OWSActionSheets.dismissAction];

        [self presentActionSheet:alert];
    });
}

@end

NS_ASSUME_NONNULL_END
