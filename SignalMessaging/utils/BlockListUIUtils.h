//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class OWSBlockingManager;
@class OWSContactsManager;
@class OWSMessageSender;
@class SignalAccount;
@class SignalServiceAddress;
@class TSGroupModel;
@class TSThread;

typedef void (^BlockActionCompletionBlock)(BOOL isBlocked);

@interface BlockListUIUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Block

+ (void)showBlockThreadActionSheet:(TSThread *)thread
                fromViewController:(UIViewController *)fromViewController
                   blockingManager:(OWSBlockingManager *)blockingManager
                   contactsManager:(OWSContactsManager *)contactsManager
                     messageSender:(OWSMessageSender *)messageSender
                   completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showBlockAddressActionSheet:(SignalServiceAddress *)address
                 fromViewController:(UIViewController *)fromViewController
                    blockingManager:(OWSBlockingManager *)blockingManager
                    contactsManager:(OWSContactsManager *)contactsManager
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showBlockSignalAccountActionSheet:(SignalAccount *)signalAccount
                       fromViewController:(UIViewController *)fromViewController
                          blockingManager:(OWSBlockingManager *)blockingManager
                          contactsManager:(OWSContactsManager *)contactsManager
                          completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

#pragma mark - Unblock

+ (void)showUnblockThreadActionSheet:(TSThread *)thread
                  fromViewController:(UIViewController *)fromViewController
                     blockingManager:(OWSBlockingManager *)blockingManager
                     contactsManager:(OWSContactsManager *)contactsManager
                     completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockAddressActionSheet:(SignalServiceAddress *)address
                   fromViewController:(UIViewController *)fromViewController
                      blockingManager:(OWSBlockingManager *)blockingManager
                      contactsManager:(OWSContactsManager *)contactsManager
                      completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockSignalAccountActionSheet:(SignalAccount *)signalAccount
                         fromViewController:(UIViewController *)fromViewController
                            blockingManager:(OWSBlockingManager *)blockingManager
                            contactsManager:(OWSContactsManager *)contactsManager
                            completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

+ (void)showUnblockGroupActionSheet:(TSGroupModel *)groupModel
                 fromViewController:(UIViewController *)fromViewController
                    blockingManager:(OWSBlockingManager *)blockingManager
                    completionBlock:(nullable BlockActionCompletionBlock)completionBlock;

#pragma mark - UI Utils

+ (NSString *)formatDisplayNameForAlertTitle:(NSString *)displayName;
+ (NSString *)formatDisplayNameForAlertMessage:(NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
