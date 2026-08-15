#import "SPKInterfaceSettingsProvider.h"
#import "../../Shared/UI/SPKChrome.h"
#import "../../Utils.h"
#import "../SPKPreferenceAvailability.h"
#import "../SPKPreferences.h"
#import "../SPKTopicSettingsSupport.h"
#import "SPKNotificationSettingsProvider.h"

// 可导航的标签页。
// “+”是发布入口而不是独立页面，因此不参与隐藏标签页的判断。
static NSArray<NSString *> *SPKDestinationTabHideKeys(void) {
    return @[
        @"interface_hide_feed_tab",
        @"interface_hide_explore_tab",
        @"interface_hide_reels_tab",
        @"interface_hide_msgs_tab",
        @"interface_hide_profile_tab",
    ];
}

// 开启指定选项后，是否会导致所有可导航标签页都被隐藏。
static BOOL SPKEnablingKeyHidesEveryTab(NSString *keyToEnable) {
    for (NSString *key in SPKDestinationTabHideKeys()) {
        if ([key isEqualToString:keyToEnable])
            continue;

        if (![SPKUtils getBoolPref:key])
            return NO;
    }

    return YES;
}

static BOOL SPKIsMessagesOnlyMode(void) {
    BOOL msgsVisible = ![SPKUtils getBoolPref:@"interface_hide_msgs_tab"];
    BOOL feedHidden = [SPKUtils getBoolPref:@"interface_hide_feed_tab"];
    BOOL exploreHidden = [SPKUtils getBoolPref:@"interface_hide_explore_tab"];
    BOOL reelsHidden = [SPKUtils getBoolPref:@"interface_hide_reels_tab"];
    BOOL profileHidden = [SPKUtils getBoolPref:@"interface_hide_profile_tab"];

    BOOL usesClassic =
        [[SPKUtils getStringPref:@"interface_nav_order"] isEqualToString:@"classic"];

    BOOL createHidden =
        !usesClassic ||
        [SPKUtils getBoolPref:@"interface_hide_create_tab"];

    return msgsVisible &&
           feedHidden &&
           exploreHidden &&
           reelsHidden &&
           profileHidden &&
           createHidden;
}

// 隐藏标签页。
// 当当前标签页已经是最后一个可用入口时，禁止继续隐藏，避免应用没有可导航页面。
static SPKSetting *SPKHideTabSwitch(NSString *title,
                                     NSString *iconName,
                                     NSString *key) {
    SPKSetting *row =
        [SPKSetting switchCellWithTitle:title
                                   icon:SPKSettingsIcon(iconName)
                            defaultsKey:key
                       requiresRestart:YES];

    row.switchValueProvider = ^BOOL {
        return [SPKUtils getBoolPref:key];
    };

    row.enabledProvider = ^BOOL {
        if ([SPKUtils getBoolPref:key])
            return YES;

        return !SPKEnablingKeyHidesEveryTab(key);
    };

    row.reloadsTableOnSwitchChange = YES;

    row.switchChangeHandler = ^(BOOL isOn) {
        [[NSUserDefaults standardUserDefaults]
            setBool:isOn
            forKey:SPKEffectivePreferenceKey(key)];

        [SPKUtils showRestartConfirmation];
    };

    return row;
}

@implementation SPKInterfaceSettingsProvider

+ (SPKSetting *)rootSetting {
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[

        //
        // 通知
        //
        SPKTopicSection(@"通知", @[
            [SPKSetting navigationCellWithTitle:@"通知"
                                       subtitle:nil
                                           icon:SPKSettingsIcon(@"notification")
                                     navSections:[SPKNotificationSettingsProvider sections]]
        ],
        nil),

        //
        // 标签页
        //
        SPKTopicSection(@"标签页", @[
            [SPKSetting menuCellWithTitle:@"启动页面"
                                     icon:SPKSettingsIcon(@"home")
                                      menu:SPKLaunchTabMenu()],

            [SPKSetting menuCellWithTitle:@"标签页顺序"
                                     icon:SPKSettingsIcon(@"sort")
                                      menu:SPKNavigationIconOrderingMenu()],

            [SPKSetting menuCellWithTitle:@"标签页滑动切换"
                                     icon:SPKSettingsIcon(@"left_right")
                                      menu:SPKSwipeBetweenTabsMenu()],
        ],
        @"控制 Instagram 标签页的排列方式：\n"
         @"• 默认：使用 Instagram 默认布局\n"
         @"• 标准：首页、Reels、私信、探索、个人主页\n"
         @"• 经典：私信显示在右上角\n"
         @"• 交替：首页和 Reels 位置互换\n\n"
         @"如需恢复旧版布局，请选择“经典”，并关闭标签页滑动切换。"),

        //
        // 隐藏标签页
        //
        SPKTopicSection(@"隐藏标签页", @[
            SPKHideTabSwitch(@"隐藏首页", @"home", @"interface_hide_feed_tab"),

            SPKHideTabSwitch(@"隐藏探索", @"search", @"interface_hide_explore_tab"),

            ({
                // 经典布局下，私信位于右上角，因此不作为底部标签页显示。
                SPKSetting *hideMessagesTab =
                    SPKHideTabSwitch(@"隐藏私信", @"messages",
                                     @"interface_hide_msgs_tab");

                hideMessagesTab.hiddenProvider = ^BOOL {
                    return [[SPKUtils getStringPref:@"interface_nav_order"]
                        isEqualToString:@"classic"];
                };

                hideMessagesTab;
            }),

            SPKHideTabSwitch(@"隐藏 Reels", @"reels",
                             @"interface_hide_reels_tab"),

            ({
                // “+”仅在经典布局中作为独立标签页显示。
                SPKSetting *hideCreateTab =
                    [SPKSetting switchCellWithTitle:@"隐藏创建"
                                               icon:SPKSettingsIcon(@"plus")
                                        defaultsKey:@"interface_hide_create_tab"
                                   requiresRestart:YES];

                hideCreateTab.hiddenProvider = ^BOOL {
                    return ![[SPKUtils getStringPref:@"interface_nav_order"]
                        isEqualToString:@"classic"];
                };

                hideCreateTab;
            }),

            SPKHideTabSwitch(@"隐藏个人主页", @"user_circle",
                             @"interface_hide_profile_tab")
        ],
        nil),

        //
        // 仅私信模式
        //
        SPKTopicSection(@"仅私信模式", @[

            ({
                SPKSetting *s =
                    [SPKSetting switchCellWithTitle:@"隐藏标签栏"
                                               icon:nil
                                        defaultsKey:@"interface_hide_tab_bar_in_messages_only"];

                s.enabledProvider = ^BOOL {
                    return SPKIsMessagesOnlyMode();
                };

                s;
            }),

            ({
                SPKSetting *s =
                    [SPKSetting switchCellWithTitle:@"显示顶部快捷按钮"
                                               icon:nil
                                        defaultsKey:@"interface_show_header_button_in_messages_only"];

                s.enabledProvider = ^BOOL {
                    return SPKIsMessagesOnlyMode();
                };

                s;
            })
        ],
        @"仅启用“私信”时可以使用以下设置。\n"
         @"1. 隐藏底部标签栏，为私信页面腾出更多空间。启用后，长按右上角导航栏按钮即可进入 Sparkle 设置。\n"
         @"2. 在私信页面左上角显示首页快捷入口。"),

        //
        // 探索与搜索
        //
        SPKTopicSection(@"探索与搜索", @[
            [SPKSetting switchCellWithTitle:@"隐藏探索推荐网格"
                                       icon:SPKSettingsIcon(@"explore_grid")
                                defaultsKey:@"interface_hide_explore_grid"],

            [SPKSetting switchCellWithTitle:@"隐藏热门搜索"
                                       icon:SPKSettingsIcon(@"trending")
                                defaultsKey:@"interface_hide_trending_searches"],

            [SPKSetting switchCellWithTitle:@"打开剪贴板中的链接"
                                       icon:SPKSettingsIcon(@"link")
                                defaultsKey:@"interface_open_clipboard_link"]
        ],
        @"1. 隐藏探索页面中的推荐帖子网格。\n"
         @"2. 隐藏探索搜索框下方的热门搜索。\n"
         @"3. 长按探索标签页，打开剪贴板中的 Instagram 链接。"),

        //
        // 截屏与录屏
        //
        SPKTopicSection(@"截屏与录屏", @[
            ({
                SPKSetting *s =
                    [SPKSetting switchCellWithTitle:@"截屏时隐藏界面"
                                               icon:nil
                                        defaultsKey:@"interface_hide_ui_on_capture"];

                s.switchChangeHandler = ^(BOOL isOn) {
                    [[NSUserDefaults standardUserDefaults]
                        setBool:isOn
                        forKey:@"interface_hide_ui_on_capture"];

                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:
                            SPKHideUIOnCapturePreferenceDidChangeNotification
                        object:nil];
                };

                s;
            })
        ],
        @"截屏、录屏或屏幕镜像时隐藏 Sparkle 的界面元素。")
    ]];

    {
        //
        // 标签栏行为
        //
        SPKSetting *(^tabBarBehaviorCell)(void) = ^SPKSetting * {
            SPKSetting *tabBarBehavior =
                [SPKSetting menuCellWithTitle:@"标签栏行为"
                                         icon:nil
                                          menu:SPKLiquidGlassTabBarStateMenu()];

            tabBarBehavior.defaultsKey =
                kSPKPrefInterfaceLiquidGlassTabBarMode;

            tabBarBehavior.enabledProvider = ^BOOL {
                return [SPKUtils getBoolPref:
                    kSPKPrefInterfaceLiquidGlass];
            };

            return tabBarBehavior;
        };

        //
        // iOS 26+
        //
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"26.0")) {

            SPKSetting *liquidGlass =
                [SPKSetting switchCellWithTitle:@"Liquid Glass"
                                           defaultsKey:kSPKPrefInterfaceLiquidGlass
                                      requiresRestart:YES];

            liquidGlass.switchValueProvider = ^BOOL {
                return [SPKUtils getBoolPref:
                    kSPKPrefInterfaceLiquidGlass];
            };

            liquidGlass.switchChangeHandler = ^(BOOL isOn) {
                [[NSUserDefaults standardUserDefaults]
                    setBool:isOn
                    forKey:kSPKPrefInterfaceLiquidGlass];

                [SPKUtils showRestartConfirmation];
            };

            SPKSetting *progressiveBlur =
                [SPKSetting switchCellWithTitle:@"渐进式模糊"
                                           defaultsKey:kSPKPrefInterfaceProgressiveBlur
                                      requiresRestart:YES];

            [sections addObject:
                SPKTopicSection(@"Liquid Glass 与模糊", @[
                    liquidGlass,
                    progressiveBlur,
                    tabBarBehaviorCell(),
                ],
                @"1. 强制启用 Instagram 原生 Liquid Glass 界面。\n"
                 @"2. 恢复原生导航栏滚动时的渐进式模糊效果。\n"
                 @"3. 设置标签栏在滚动时的显示方式。")];

        } else {

            //
            // iOS 26 以下
            //
            SPKSetting *pillTabBar =
                [SPKSetting switchCellWithTitle:@"胶囊形标签栏"
                                           defaultsKey:kSPKPrefInterfaceLiquidGlass
                                      requiresRestart:YES];

            pillTabBar.switchValueProvider = ^BOOL {
                return [SPKUtils getBoolPref:
                    kSPKPrefInterfaceLiquidGlass];
            };

            pillTabBar.switchChangeHandler = ^(BOOL isOn) {
                [[NSUserDefaults standardUserDefaults]
                    setBool:isOn
                    forKey:kSPKPrefInterfaceLiquidGlass];

                [SPKUtils showRestartConfirmation];
            };

            [sections addObject:
                SPKTopicSection(@"标签栏", @[
                    pillTabBar,
                    tabBarBehaviorCell(),
                ],
                @"将标签栏调整为类似 iOS 26 的悬浮胶囊样式。"
                 @"Liquid Glass 模式需要 iOS 26，因此在当前系统上仅启用胶囊形标签栏。")];
        }
    }

    return SPKTopicNavigationSetting(@"界面", @"interface", 24.0, sections);
}

@end
