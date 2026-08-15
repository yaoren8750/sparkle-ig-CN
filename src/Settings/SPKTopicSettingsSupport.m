#import "SPKTopicSettingsSupport.h"
#import "../Features/Feed/HeaderActionButton.h"
#import "SPKHeaderButtonDefaultActionPickerViewController.h"
#import "../Shared/UI/SPKNotificationCenter.h"
#import "SPKActionButtonDefaultActionPickerViewController.h"
#import "SPKBulkActionMenuEditViewController.h"
#import "SPKEditActionsListViewController.h"
#import "SPKPreferences.h"

#import "../AssetUtils.h"
#import "../Shared/AutoSave/SPKAutoSave.h"
#import "../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../Shared/ActionButton/SPKActionDescriptor.h"
#import "../Utils.h"

CGFloat const SPKSettingsCellIconPointSize = 24.0;

NSDictionary *SPKTopicSection(NSString *header, NSArray *rows, NSString *footer) {
    NSMutableDictionary *section = [@{
        @"header" : header ?: @"",
        @"rows" : rows ?: @[]
    } mutableCopy];

    if (footer.length > 0) {
        section[@"footer"] = footer;
    }

    return [section copy];
}

UIImage *SPKSettingsIcon(NSString *name) {
    return [SPKAssetUtils instagramIconNamed:name pointSize:SPKSettingsCellIconPointSize];
}

UIImage *SPKSettingsSystemIcon(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImage *symbol = [SPKAssetUtils resolvedImageNamed:name
                                              pointSize:pointSize
                                                 weight:weight
                                                 source:SPKResolvedImageSourceSystemSymbol
                                          renderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!symbol)
        return nil;

    // SF Symbols size by cap-height, so a wide/tall glyph (e.g.
    // button.vertical.right.press) renders to a larger bounding box than the
    // IG asset icons, which are a fixed square. Aspect-fit the symbol into the
    // same square canvas so it lines up with the other settings rows.
    CGFloat side = SPKSettingsCellIconPointSize;
    CGSize canvasSize = CGSizeMake(side, side);
    CGSize sourceSize = symbol.size;
    if (sourceSize.width <= 0.0 || sourceSize.height <= 0.0) {
        return symbol;
    }

    CGFloat scale = MIN(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height);
    CGSize drawSize = CGSizeMake(sourceSize.width * scale, sourceSize.height * scale);
    CGRect drawRect = CGRectMake((canvasSize.width - drawSize.width) / 2.0,
                                 (canvasSize.height - drawSize.height) / 2.0,
                                 drawSize.width,
                                 drawSize.height);

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvasSize format:format];
    UIImage *normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext *_Nonnull context) {
        (void)context;
        [symbol drawInRect:CGRectIntegral(drawRect)];
    }];
    return [normalized imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

SPKSetting *SPKSettingApplyIconTint(SPKSetting *setting, UIColor *tintColor) {
    setting.iconTintColor = tintColor;
    return setting;
}

static UIImage *SPKSelectedMenuIconInMenu(UIMenu *menu) {
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:[UIMenu class]]) {
            UIImage *icon = SPKSelectedMenuIconInMenu((UIMenu *)element);
            if (icon)
                return icon;
            continue;
        }

        if (![element isKindOfClass:[UICommand class]])
            continue;
        UICommand *command = (UICommand *)element;
        NSDictionary *propertyList = command.propertyList;
        NSString *defaultsKey = propertyList[@"defaultsKey"];
        NSString *value = propertyList[@"value"];
        NSString *iconName = propertyList[@"iconName"];
        if (defaultsKey.length == 0 || value.length == 0 || iconName.length == 0)
            continue;

        // Read through the namespaced accessor so the selected-icon lookup
        // matches how menuChanged: writes (per-account effective key). A raw
        // standardUserDefaults read misses the value when per-account prefs are
        // enabled, leaving the cell stuck on its fallback icon.
        NSString *saved = [SPKUtils getStringPref:defaultsKey];
        if ([saved isEqualToString:value]) {
            return SPKSettingsIcon(iconName);
        }
    }

    return nil;
}

SPKSetting *SPKSettingApplySelectedMenuIcon(SPKSetting *setting, UIImage *fallbackIcon) {
    __weak SPKSetting *weakSetting = setting;
    setting.iconProvider = ^UIImage * {
        SPKSetting *strongSetting = weakSetting;
        if (!strongSetting)
            return fallbackIcon;
        return SPKSelectedMenuIconInMenu(strongSetting.baseMenu) ?: fallbackIcon ?
                                                                                 : strongSetting.icon;
    };
    return setting;
}

SPKSetting *SPKTopicNavigationSetting(NSString *title, NSString *iconName, CGFloat iconSize, NSArray *sections) {
    CGFloat resolvedIconSize = iconSize > 0.0 ? iconSize : SPKSettingsCellIconPointSize;
    return SPKSettingApplyIconTint([SPKSetting navigationCellWithTitle:title
                                                              subtitle:@""
                                                                  icon:[SPKAssetUtils instagramIconNamed:iconName pointSize:resolvedIconSize]
                                                           navSections:sections],
                                   [SPKUtils SPKColor_InstagramPrimaryText]);
}

SPKSetting *SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSource source) {
    SPKSetting *setting = [SPKSetting navigationCellWithTitle:@"默认点击操作"
                                                     subtitle:@""
                                                         icon:SPKSettingsIcon(@"action")
                                               viewController:[[SPKActionButtonDefaultActionPickerViewController alloc] initWithSource:source]];
    setting.accessoryTextProvider = ^NSString * {
        return SPKActionButtonDefaultActionTitleForSource(source);
    };
    setting.iconProvider = ^UIImage * {
        return SPKSettingsIcon(SPKActionButtonDefaultActionIconNameForSource(source));
    };
    return setting;
}

static UICommand *SPKMenuCommand(NSString *title, NSString *imageName, NSString *fallback, NSString *defaultsKey, NSString *value, BOOL requiresRestart) {
    NSMutableDictionary *propertyList = @{
        @"defaultsKey" : defaultsKey,
        @"value" : value
    }.mutableCopy;

    if (requiresRestart) {
        propertyList[@"requiresRestart"] = @YES;
    }

    if (imageName.length > 0) {
        propertyList[@"iconName"] = imageName;
    }

    UIImage *image = [SPKAssetUtils resolvedImageNamed:imageName
                                     fallbackSystemName:fallback
                                             pointSize:22.0
                                                weight:UIImageSymbolWeightRegular
                                                source:(imageName.length > 0 ? SPKResolvedImageSourceInstagramIcon : SPKResolvedImageSourceSystemSymbol)
                                         renderingMode:UIImageRenderingModeAlwaysTemplate];

    return [UICommand commandWithTitle:title
                                 image:image
                                action:@selector(menuChanged:)
                          propertyList:[propertyList copy]];
}

SPKSetting *SPKActionButtonConfigurationNavigationSetting(SPKActionButtonSource source,
                                                           NSString *topicTitle,
                                                           NSArray<NSString *> *supportedActions,
                                                           NSArray<SPKActionMenuSection *> *defaultSections) {
    SPKEditActionsListViewController *controller =
        [[SPKEditActionsListViewController alloc] initWithSource:source
                                                      topicTitle:topicTitle];

    (void)supportedActions;
    (void)defaultSections;

    return [SPKSetting navigationCellWithTitle:@"配置操作"
                                      subtitle:@""
                                          icon:SPKSettingsIcon(@"slider")
                                viewController:controller];
}

UIMenu *SPKReelsTapControlMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"默认", nil, nil,
                       @"reels_tap_control",
                       @"default",
                       YES),

        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SPKMenuCommand(@"暂停/播放", nil, nil,
                           @"reels_tap_control",
                           @"pause",
                           YES),

            SPKMenuCommand(@"静音/取消静音", nil, nil,
                           @"reels_tap_control",
                           @"mute",
                           YES)
        ]]
    ]];
}

UIMenu *SPKMainFeedModeMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"为你推荐",
                       @"heart",
                       nil,
                       @"feed_mode",
                       @"default",
                       YES),

        SPKMenuCommand(@"关注",
                       @"users",
                       nil,
                       @"feed_mode",
                       @"following",
                       YES)
    ]];
}

UIMenu *SPKSeenButtonPositionMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"顶部",
                       @"arrow_up",
                       nil,
                       @"msgs_seen_button_position",
                       @"top",
                       NO),

        SPKMenuCommand(@"底部",
                       @"arrow_down",
                       nil,
                       @"msgs_seen_button_position",
                       @"bottom",
                       NO)
    ]];
}

UIMenu *SPKLastActiveFormatMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"关闭",
                       nil,
                       nil,
                       @"msgs_last_active_format",
                       @"off",
                       NO),

        SPKMenuCommand(@"智能",
                       nil,
                       nil,
                       @"msgs_last_active_format",
                       @"smart",
                       NO),

        SPKMenuCommand(@"日期与时间",
                       nil,
                       nil,
                       @"msgs_last_active_format",
                       @"datetime",
                       NO)
    ]];
}

UIMenu *SPKNavigationIconOrderingMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"默认",
                       nil,
                       nil,
                       @"interface_nav_order",
                       @"default",
                       YES),

        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SPKMenuCommand(@"经典布局",
                           nil,
                           nil,
                           @"interface_nav_order",
                           @"classic",
                           YES),

            SPKMenuCommand(@"标准布局",
                           nil,
                           nil,
                           @"interface_nav_order",
                           @"standard",
                           YES),

            SPKMenuCommand(@"交替布局",
                           nil,
                           nil,
                           @"interface_nav_order",
                           @"alternate",
                           YES)
        ]]
    ]];
}

UIMenu *SPKLaunchTabMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"默认",
                       nil,
                       nil,
                       @"interface_launch_tab",
                       @"default",
                       YES),

        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SPKMenuCommand(@"主页",
                           @"home",
                           nil,
                           @"interface_launch_tab",
                           @"feed",
                           YES),

            SPKMenuCommand(@"Reels",
                           @"reels",
                           nil,
                           @"interface_launch_tab",
                           @"reels",
                           YES),

            SPKMenuCommand(@"私信",
                           @"messages",
                           nil,
                           @"interface_launch_tab",
                           @"inbox",
                           YES),

            SPKMenuCommand(@"探索",
                           @"search",
                           nil,
                           @"interface_launch_tab",
                           @"explore",
                           YES),

            SPKMenuCommand(@"个人资料",
                           @"user_circle",
                           nil,
                           @"interface_launch_tab",
                           @"profile",
                           YES)
        ]]
    ]];
}

UIMenu *SPKSwipeBetweenTabsMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"默认",
                       nil,
                       nil,
                       @"interface_swipe_tabs",
                       @"default",
                       YES),

        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SPKMenuCommand(@"开启",
                           nil,
                           nil,
                           @"interface_swipe_tabs",
                           @"enabled",
                           YES),

            SPKMenuCommand(@"关闭",
                           nil,
                           nil,
                           @"interface_swipe_tabs",
                           @"disabled",
                           YES)
        ]]
    ]];
}

UIMenu *SPKLiquidGlassTabBarStateMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"默认",
                       nil,
                       nil,
                       kSPKPrefInterfaceLiquidGlassTabBarMode,
                       @"default",
                       YES),

        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SPKMenuCommand(@"固定",
                           nil,
                           nil,
                           kSPKPrefInterfaceLiquidGlassTabBarMode,
                           @"fixed",
                           YES),

            SPKMenuCommand(@"滚动时隐藏",
                           nil,
                           nil,
                           kSPKPrefInterfaceLiquidGlassTabBarMode,
                           @"hide",
                           YES)
        ]]
    ]];
}

UIMenu *SPKSwipeCloseCommentsDirectionMenu(void) {
    static NSString *const kSPKSwipeCloseCommentsDirectionKey =
        @"general_comments_swipe_close_direction";

    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"左右均可",
                       @"left_right",
                       nil,
                       kSPKSwipeCloseCommentsDirectionKey,
                       @"both",
                       NO),

        SPKMenuCommand(@"向左",
                       @"arrow_left",
                       nil,
                       kSPKSwipeCloseCommentsDirectionKey,
                       @"left",
                       NO),

        SPKMenuCommand(@"向右",
                       @"arrow_right",
                       nil,
                       kSPKSwipeCloseCommentsDirectionKey,
                       @"right",
                       NO)
    ]];
}

UIMenu *SPKCacheAutoClearMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"从不",
                       nil,
                       nil,
                       @"general_cache_auto_clear",
                       @"never",
                       NO),

        SPKMenuCommand(@"始终",
                       nil,
                       nil,
                       @"general_cache_auto_clear",
                       @"always",
                       NO),

        SPKMenuCommand(@"每天",
                       nil,
                       nil,
                       @"general_cache_auto_clear",
                       @"daily",
                       NO),

        SPKMenuCommand(@"每周",
                       nil,
                       nil,
                       @"general_cache_auto_clear",
                       @"weekly",
                       NO),

        SPKMenuCommand(@"每月",
                       nil,
                       nil,
                       @"general_cache_auto_clear",
                       @"monthly",
                       NO)
    ]];
}

UIMenu *SPKNotificationProgressSubtitleStyleMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"百分比与大小",
                       nil,
                       nil,
                       kSPKNotificationProgressSubtitleStyleKey,
                       @"both",
                       NO),

        SPKMenuCommand(@"百分比",
                       nil,
                       nil,
                       kSPKNotificationProgressSubtitleStyleKey,
                       @"percent",
                       NO),

        SPKMenuCommand(@"文件大小",
                       nil,
                       nil,
                       kSPKNotificationProgressSubtitleStyleKey,
                       @"bytes",
                       NO),

        SPKMenuCommand(@"关闭",
                       nil,
                       nil,
                       kSPKNotificationProgressSubtitleStyleKey,
                       @"off",
                       NO)
    ]];
}

UIMenu *SPKNotificationPillPositionMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"顶部",
                       nil,
                       nil,
                       kSPKNotificationPillPositionKey,
                       @"top",
                       NO),

        SPKMenuCommand(@"底部",
                       nil,
                       nil,
                       kSPKNotificationPillPositionKey,
                       @"bottom",
                       NO)
    ]];
}

UIMenu *SPKMediaVideoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"默认",
                       nil,
                       nil,
                       @"downloads_video_quality",
                       @"high_ignore_dash",
                       NO),

        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SPKMenuCommand(@"每次询问",
                           nil,
                           nil,
                           @"downloads_video_quality",
                           @"always_ask",
                           NO),

            SPKMenuCommand(@"高",
                           nil,
                           nil,
                           @"downloads_video_quality",
                           @"high",
                           NO),

            SPKMenuCommand(@"中",
                           nil,
                           nil,
                           @"downloads_video_quality",
                           @"medium",
                           NO),

            SPKMenuCommand(@"低",
                           nil,
                           nil,
                           @"downloads_video_quality",
                           @"low",
                           NO)
        ]]
    ]];
}

UIMenu *SPKMediaPhotoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"每次询问",
                       nil,
                       nil,
                       @"downloads_photo_quality",
                       @"always_ask",
                       NO),

        SPKMenuCommand(@"最高",
                       nil,
                       nil,
                       @"downloads_photo_quality",
                       @"max",
                       NO),

        SPKMenuCommand(@"高",
                       nil,
                       nil,
                       @"downloads_photo_quality",
                       @"high",
                       NO),

        SPKMenuCommand(@"中",
                       nil,
                       nil,
                       @"downloads_photo_quality",
                       @"medium",
                       NO),

        SPKMenuCommand(@"低",
                       nil,
                       nil,
                       @"downloads_photo_quality",
                       @"low",
                       NO)
    ]];
}

UIMenu *SPKAutoSaveDestinationMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"Sparkle 图库",
                       nil,
                       nil,
                       kSPKAutoSaveDestinationKey,
                       @"gallery",
                       NO),

        SPKMenuCommand(@"系统照片",
                       nil,
                       nil,
                       kSPKAutoSaveDestinationKey,
                       @"photos",
                       NO)
    ]];
}

UIMenu *SPKAutoSaveVideoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"默认",
                       nil,
                       nil,
                       kSPKAutoSaveVideoQualityKey,
                       @"high_ignore_dash",
                       NO),

        [UIMenu menuWithTitle:@""
                        image:nil
                   identifier:nil
                      options:UIMenuOptionsDisplayInline
                     children:@[
            SPKMenuCommand(@"高",
                           nil,
                           nil,
                           kSPKAutoSaveVideoQualityKey,
                           @"high",
                           NO),

            SPKMenuCommand(@"中",
                           nil,
                           nil,
                           kSPKAutoSaveVideoQualityKey,
                           @"medium",
                           NO),

            SPKMenuCommand(@"低",
                           nil,
                           nil,
                           kSPKAutoSaveVideoQualityKey,
                           @"low",
                           NO)
        ]]
    ]];
}

UIMenu *SPKAutoSavePhotoQualityMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(@"高",
                       nil,
                       nil,
                       kSPKAutoSavePhotoQualityKey,
                       @"high",
                       NO),

        SPKMenuCommand(@"低",
                       nil,
                       nil,
                       kSPKAutoSavePhotoQualityKey,
                       @"low",
                       NO)
    ]];
}

UIMenu *SPKAutoSaveFilterModeMenu(NSString *filterModeKey, NSString *subjectPlural) {
    return [UIMenu menuWithChildren:@[
        SPKMenuCommand(
            [NSString stringWithFormat:@"全部%@", subjectPlural],
            nil,
            nil,
            filterModeKey,
            @"all",
            NO
        ),

        SPKMenuCommand(
            [NSString stringWithFormat:@"仅所选%@", subjectPlural],
            nil,
            nil,
            filterModeKey,
            @"selected",
            NO
        )
    ]];
}

UIMenu *SPKStoryAutoSaveFilterModeMenu(void) {
    return SPKAutoSaveFilterModeMenu(
        @"stories_auto_save_filter_mode",
        @"用户"
    );
}

SPKSetting *SPKFeedHeaderButtonDefaultActionNavigationSetting(void) {
    SPKSetting *setting =
        [SPKSetting navigationCellWithTitle:@"默认点击操作"
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"action")
                             viewController:[SPKHeaderButtonDefaultActionPickerViewController new]];

    setting.accessoryTextProvider = ^NSString * {
        return SPKHeaderButtonDefaultActionTitle();
    };

    setting.iconProvider = ^UIImage * {
        return SPKSettingsIcon(SPKHeaderButtonDefaultActionIconName());
    };

    return setting;
}

UIMenu *SPKGalleryShortcutTargetMenu(void) {
    NSString *const kGalleryLongPressTabKey =
        @"gallery_quick_access_tab";

    NSString *const kGalleryQuickAccessDisabledValue =
        @"none";

    NSMutableArray<UIMenuElement *> *commands =
        [NSMutableArray array];

    NSArray<NSDictionary *> *items = @[
        @{
            @"title" : @"无",
            @"value" : kGalleryQuickAccessDisabledValue,
            @"icon" : @"circle_off"
        },

        @{
            @"title" : @"主页",
            @"value" : @"mainfeed-tab",
            @"icon" : @"home"
        },

        @{
            @"title" : @"Reels",
            @"value" : @"reels-tab",
            @"icon" : @"reels"
        }
    ];

    NSMutableArray *allItems = [items mutableCopy];

    if ([SPKUtils tabOrderSetTo:@"classic"]) {
        [allItems addObject:@{
            @"title" : @"创建",
            @"value" : @"camera-tab",
            @"icon" : @"plus"
        }];
    } else {
        [allItems addObject:@{
            @"title" : @"私信",
            @"value" : @"direct-inbox-tab",
            @"icon" : @"messages"
        }];
    }

    [allItems addObject:@{
        @"title" : @"个人资料",
        @"value" : @"profile-tab",
        @"icon" : @"user_circle"
    }];

    for (NSDictionary *item in allItems) {
        NSString *title = item[@"title"];
        NSString *value = item[@"value"];
        NSString *iconName = item[@"icon"];

        [commands addObject:
            SPKMenuCommand(
                title,
                iconName,
                nil,
                kGalleryLongPressTabKey,
                value,
                YES
            )
        ];
    }

    return [UIMenu menuWithChildren:commands];
}
