//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSSearchBarStyle) { OWSSearchBarStyle_Default, OWSSearchBarStyle_SecondaryBar };

@interface OWSSearchBar : UISearchBar

+ (void)applyThemeToSearchBar:(UISearchBar *)searchBar;
+ (void)applyThemeToSearchBar:(UISearchBar *)searchBar style:(OWSSearchBarStyle)style;

- (void)switchToStyle:(OWSSearchBarStyle)style;

@end

NS_ASSUME_NONNULL_END
