//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AvatarViewHelper.h"
#import "OWSNavigationController.h"
#import "PALAPA-Swift.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface AvatarViewHelper () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@end

#pragma mark -

@implementation AvatarViewHelper

#pragma mark - Avatar Avatar

- (void)showChangeAvatarUI
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);

    ActionSheetController *actionSheet =
        [[ActionSheetController alloc] initWithTitle:self.delegate.avatarActionSheetTitle message:nil];
    [actionSheet addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *takePictureAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"MEDIA_FROM_CAMERA_BUTTON", @"media picker option to take photo or video")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *_Nonnull action) {
                  [self takePicture];
              }];
    [actionSheet addAction:takePictureAction];

    ActionSheetAction *choosePictureAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *_Nonnull action) {
                  [self chooseFromLibrary];
              }];
    [actionSheet addAction:choosePictureAction];

    if (self.delegate.hasClearAvatarAction) {
        ActionSheetAction *clearAction =
            [[ActionSheetAction alloc] initWithTitle:self.delegate.clearAvatarActionLabel
                                               style:ActionSheetActionStyleDefault
                                             handler:^(ActionSheetAction *_Nonnull action) {
                                                 [self.delegate clearAvatar];
                                             }];
        [actionSheet addAction:clearAction];
    }

    [self.delegate.fromViewController presentActionSheet:actionSheet];
}

- (void)takePicture
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);

    [self.delegate.fromViewController ows_askForCameraPermissions:^(BOOL granted) {
        if (!granted) {
            OWSLogWarn(@"Camera permission denied.");
            return;
        }

        UIImagePickerController *picker = [OWSImagePickerController new];
        picker.delegate = self;
        picker.allowsEditing = NO;
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage ];

        [self.delegate.fromViewController presentViewController:picker animated:YES completion:nil];
    }];
}

- (void)chooseFromLibrary
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);

    [self.delegate.fromViewController ows_askForMediaLibraryPermissions:^(BOOL granted) {
        if (!granted) {
            OWSLogWarn(@"Media Library permission denied.");
            return;
        }

        UIImagePickerController *picker = [OWSImagePickerController new];
        picker.delegate = self;
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage ];

        [self.delegate.fromViewController presentViewController:picker animated:YES completion:nil];
    }];
}

/*
 *  Dismissing UIImagePickerController
 */

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);

    [self.delegate.fromViewController dismissViewControllerAnimated:YES completion:nil];
}

/*
 *  Fetch data from UIImagePickerController
 */
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);

    UIImage *rawAvatar = [info objectForKey:UIImagePickerControllerOriginalImage];

    [self.delegate.fromViewController
        dismissViewControllerAnimated:YES
                           completion:^{
                               if (rawAvatar) {
                                   OWSAssertIsOnMainThread();

                                   CropScaleImageViewController *vc = [[CropScaleImageViewController alloc]
                                        initWithSrcImage:rawAvatar
                                       successCompletion:^(UIImage *_Nonnull dstImage) {
                                           dispatch_async(dispatch_get_main_queue(), ^{
                                               [self.delegate avatarDidChange:dstImage];
                                           });
                                       }];
                                   [self.delegate.fromViewController presentViewController:vc
                                                                                  animated:YES
                                                                                completion:nil];
                               }
                           }];
}

@end

NS_ASSUME_NONNULL_END
