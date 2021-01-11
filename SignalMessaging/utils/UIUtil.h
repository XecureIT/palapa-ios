//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "UIFont+OWS.h"
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/UIImage+OWS.h>

#define ACCESSIBILITY_IDENTIFIER_WITH_NAME(_root_view, _variable_name)                                                 \
    ([NSString stringWithFormat:@"%@.%@", _root_view.class, _variable_name])
#define SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(_root_view, _variable_name)                                               \
    _variable_name.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(_root_view, (@ #_variable_name))

typedef void (^completionBlock)(void);

/**
 *
 * UIUtil contains various class methods that centralize common app UI functionality that would otherwise be hardcoded.
 *
 */

@interface UIUtil : NSObject

+ (void)applyRoundedBorderToImageView:(UIImageView *)imageView;
+ (void)removeRoundedBorderToImageView:(UIImageView *__strong *)imageView;

+ (void)setupSignalAppearence;

@end
