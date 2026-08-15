#import "SPKGeneralSettingsProvider.h"

#import "../../AssetUtils.h"
#import "../../Shared/Account/SPKAccountManager.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../Utils.h"
#import "../SPKActionSectionIconPickerViewController.h"
#import "../SPKAppIconCatalog.h"
#import "../SPKAppIconPickerViewController.h"
#import "../SPKTopicSettingsSupport.h"

@implementation SPKGeneralSettingsProvider

+ (SPKSetting *)defaultMenuIconSetting {
    SPKActionSectionIconPickerViewController *controller =
        [[SPKActionSectionIconPickerViewController alloc] initWithSelectedIconName:SPKActionButtonOpenMenuIconName()
                                                                             onSelect:^(NSString *iconName) {
        SPKPreferenceSetObject(iconName.length > 0 ? iconName : @"action",
                               @"general_action_btn_default_menu_icon");
        [[NSNotificationCenter defaultCenter]
            postNotificationName:SPKActionButtonConfigurationDidChangeNotification
                          object:nil];
    }];

    controller.title = @"打开菜单图标";

    SPKSetting *setting =
        [SPKSetting navigationCellWithTitle:@"打开菜单图标"
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"action")
                             viewController:controller];

    setting.iconProvider = ^UIImage * {
        return SPKSettingsIcon(SPKActionButtonOpenMenuIconName());
    };

    return setting;
}

+ (SPKSetting *)appIconSetting {
    SPKAppIconPickerViewController *controller =
        [[SPKAppIconPickerViewController alloc]
            initWithSelectedIdentifier:[SPKAppIconCatalog currentAppIconIdentifier]
            onSelect:nil];

    SPKSetting *setting =
        [SPKSetting navigationCellWithTitle:@"应用图标"
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"app")
                             viewController:controller];

    setting.accessoryTextProvider = ^NSString * {
        SPKAppIconItem *currentIcon = [SPKAppIconCatalog currentAppIcon];
        return currentIcon.displayName.length > 0
            ? currentIcon.displayName
            : @"默认";
    };

    return setting;
}

+ (SPKSetting *)perAccountSetting {
    SPKSetting *setting =
        [SPKSetting switchCellWithTitle:@"账号独立设置"
                                   icon:SPKSettingsIcon(@"user_circle")
                            defaultsKey:kSPKPrefPerAccountSettings];

    setting.requiresRestart = YES;

    return setting;
}

+ (SPKSetting *)perAccountInfoSetting {
    return [SPKSetting buttonCellWithTitle:@"使用说明"
                                  subtitle:nil
                                      icon:SPKSettingsIcon(@"info")
                                    action:^{
        NSString *message =
            @"每个登录账号都可以使用独立的 Sparkle 设置。新登录的账号会继承当前设置，直到你对其进行修改。\n\n"
             "以下设置会在所有账号之间共享：\n"
             "• 应用图标\n"
             "• 外观与 Liquid Glass\n"
             "• 标签栏顺序和显示状态\n"
             "• 快速访问快捷方式（设置和图库）\n"
             "• 首页推荐 / 关注模式\n"
             "• 禁用视频自动播放\n"
             "• Reels 无限滚动和限制\n"
             "• 截屏时隐藏界面\n"
             "• 下载编码设置\n"
             "• 修复重复通知\n"
             "• 全局禁用（总开关）\n\n"
             "图库媒体归属由图库设置单独控制。";

        [SPKIGAlertPresenter
            presentAlertFromViewController:topMostController()
                                     title:@"账号独立设置"
                                   message:message
                                   actions:@[
            [SPKIGAlertAction actionWithTitle:@"确定"
                                         style:SPKIGAlertActionStyleCancel
                                       handler:nil]
        ]];
    }];
}

+ (SPKSetting *)rootSetting {
    SPKSetting *clearCacheSetting =
        [SPKSetting buttonCellWithTitle:@"清除缓存"
                               subtitle:@""
                                   icon:SPKSettingsIcon(@"trash")
                                 action:^(void) {
        unsigned long long freedBytes =
            [SPKUtils cleanCacheReturningFreedBytes];

        NSString *subtitle =
            freedBytes > 0
                ? [NSString stringWithFormat:@"已释放 %@",
                    [NSByteCountFormatter
                        stringFromByteCount:(long long)freedBytes
                                 countStyle:NSByteCountFormatterCountStyleFile]]
                : @"缓存已经是空的";

        SPKNotify(kSPKNotificationSettingsClearCache,
                  @"缓存已清除",
                  subtitle,
                  @"circle_check_filled",
                  SPKNotificationToneForIconResource(@"circle_check_filled"));
    }];

    clearCacheSetting.tintColor =
        [SPKUtils SPKColor_InstagramDestructive];

    clearCacheSetting.iconTintColor =
        [SPKUtils SPKColor_InstagramDestructive];

    clearCacheSetting.accessoryTextProvider = ^NSString * {
        return [SPKUtils formattedCacheSize];
    };

    return SPKTopicNavigationSetting(@"常规", @"settings", 24.0, @[
        SPKTopicSection(@"使用与操作", @[
            [SPKSetting switchCellWithTitle:@"复制文字"
                                       icon:SPKSettingsIcon(@"text")
                                defaultsKey:@"general_copy_text"],

            [SPKSetting switchCellWithTitle:@"不保存最近搜索"
                                       icon:SPKSettingsIcon(@"search")
                                defaultsKey:@"general_no_recent_searches"],

            [SPKSetting switchCellWithTitle:@"复制链接时移除追踪信息"
                                       icon:SPKSettingsIcon(@"user_unfollow")
                                defaultsKey:@"general_strip_share_link_tracking"],

            [SPKSetting switchCellWithTitle:@"长按发送以复制链接"
                                       icon:SPKSettingsIcon(@"link")
                                defaultsKey:@"general_hold_send_copy_link"],
        ],
        @"1. 长按应用中的文字即可复制。\n"
         "2. 搜索框不会再保存最近的搜索记录。\n"
         "3. 复制链接时移除用户标识和追踪参数。\n"
         "4. 长按发送 / 分享按钮即可复制帖子链接。"),

        SPKTopicSection(@"分享", @[
            [SPKSetting switchCellWithTitle:@"隐藏创建群聊按钮"
                                       icon:SPKSettingsIcon(@"group")
                                defaultsKey:@"general_hide_create_group"],

            [SPKSetting switchCellWithTitle:@"创建群聊前确认"
                                       icon:SPKSettingsIcon(@"group")
                                defaultsKey:@"general_confirm_create_group"],

            [SPKSetting switchCellWithTitle:@"发送帖子前确认"
                                       icon:SPKSettingsIcon(@"messages")
                                defaultsKey:@"general_confirm_send"],
        ],
        @"1. 在 Instagram 的发送 / 分享页面中隐藏创建群聊按钮。\n"
         "2. 创建群聊时显示确认提示。\n"
         "3. 发送帖子前显示确认提示。"),

        SPKTopicSection(@"推荐内容", @[
            [SPKSetting navigationCellWithTitle:@"广告"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"ads")
                                     navSections:@[
                SPKTopicSection(@"广告", @[
                    [SPKSetting switchCellWithTitle:@"隐藏首页广告"
                                        defaultsKey:@"general_hide_ads_feed"],

                    [SPKSetting switchCellWithTitle:@"隐藏快拍广告"
                                        defaultsKey:@"general_hide_ads_stories"],

                    [SPKSetting switchCellWithTitle:@"隐藏 Reels 广告"
                                        defaultsKey:@"general_hide_ads_reels"],

                    [SPKSetting switchCellWithTitle:@"隐藏探索广告"
                                        defaultsKey:@"general_hide_ads_explore"],

                    [SPKSetting switchCellWithTitle:@"隐藏 Reels 购物提示"
                                        defaultsKey:@"general_hide_reels_shopping_cta"]
                ],
                nil)
            ]],

            [SPKSetting navigationCellWithTitle:@"Meta AI"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"meta_ai")
                                     navSections:@[
                SPKTopicSection(@"", @[
                    [SPKSetting switchCellWithTitle:@"隐藏私信中的 Meta AI"
                                        defaultsKey:@"general_hide_meta_ai_msgs"],

                    [SPKSetting switchCellWithTitle:@"隐藏探索和搜索中的 Meta AI"
                                        defaultsKey:@"general_hide_meta_ai_explore"],

                    [SPKSetting switchCellWithTitle:@"隐藏评论中的 Meta AI"
                                        defaultsKey:@"general_hide_meta_ai_comments"],

                    [SPKSetting switchCellWithTitle:@"隐藏创作工具中的 Meta AI"
                                        defaultsKey:@"general_hide_meta_ai_creation"],

                    [SPKSetting switchCellWithTitle:@"隐藏 Meta AI 入口"
                                        defaultsKey:@"general_hide_meta_ai_global"]
                ],
                @"私信包括收件箱、编辑器、收件人、主题和消息菜单。"
                 "全局入口包括 Meta AI 按钮、占位提示以及其他品牌入口。")
            ]],

            [SPKSetting navigationCellWithTitle:@"推荐账号"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"users")
                                     navSections:@[
                SPKTopicSection(@"推荐账号", @[
                    [SPKSetting switchCellWithTitle:@"隐藏首页推荐账号"
                                        defaultsKey:@"general_hide_suggested_users_feed"],

                    [SPKSetting switchCellWithTitle:@"隐藏 Reels 推荐账号"
                                        defaultsKey:@"general_hide_suggested_users_reels"],

                    [SPKSetting switchCellWithTitle:@"隐藏私信推荐账号"
                                        defaultsKey:@"general_hide_suggested_users_msgs"],

                    [SPKSetting switchCellWithTitle:@"隐藏搜索推荐账号"
                                        defaultsKey:@"general_hide_suggested_users_search"],

                    [SPKSetting switchCellWithTitle:@"隐藏个人主页推荐账号"
                                        defaultsKey:@"general_hide_suggested_users_profile"],

                    [SPKSetting switchCellWithTitle:@"隐藏动态推荐账号"
                                        defaultsKey:@"general_hide_suggested_users_activity"],

                    [SPKSetting switchCellWithTitle:@"隐藏关注列表推荐"
                                        defaultsKey:@"general_hide_suggested_users_follow_lists"],

                    [SPKSetting switchCellWithTitle:@"隐藏订阅推荐"
                                        defaultsKey:@"general_hide_suggested_users_subscriptions"]
                ],
                nil)
            ]]
        ],
        @"控制广告、Meta AI 和推荐账号在不同页面中的显示。"),

        SPKTopicSection(@"媒体预览和菜单", @[
            [SPKSetting switchCellWithTitle:@"显示媒体信息"
                                       icon:SPKSettingsIcon(@"info")
                                defaultsKey:@"general_preview_show_metadata"],

            [SPKSetting switchCellWithTitle:@"在菜单中显示日期"
                                       icon:SPKSettingsIcon(@"calendar")
                                defaultsKey:@"general_action_btn_show_date"],
        ],
        @"1. 在展开的照片预览中显示作者和发布日期。\n"
         "2. 在操作菜单中显示帖子的具体发布时间。"),

        SPKTopicSection(@"评论", @[
            [SPKSetting switchCellWithTitle:@"复制评论"
                                       icon:SPKSettingsIcon(@"copy")
                                defaultsKey:@"general_comments_copy_text"],

            [SPKSetting switchCellWithTitle:@"评论媒体操作"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:@"general_comments_media_actions"],

            [SPKSetting switchCellWithTitle:@"从图库上传照片"
                                       icon:SPKSettingsIcon(@"photo")
                                defaultsKey:@"general_comments_gallery_upload"]
        ],
        @"1. 在评论菜单中添加复制选项。\n"
         "2. 为 GIF 和照片评论添加照片、分享、图库和链接操作。\n"
         "3. 长按评论输入框的照片按钮，可从 Sparkle 图库选择图片。"),

        SPKTopicSection(@"", @[
            [SPKSetting switchCellWithTitle:@"滑动关闭评论"
                                       icon:SPKSettingsIcon(@"left_right")
                                defaultsKey:@"general_comments_swipe_close"],

            SPKSettingApplySelectedMenuIcon(
                [SPKSetting menuCellWithTitle:@"滑动方向"
                                         icon:SPKSettingsIcon(@"left_right")
                                          menu:SPKSwipeCloseCommentsDirectionMenu()],
                SPKSettingsIcon(@"left_right")),
        ],
        @"通过水平滑动关闭评论页面，可选择滑动方向。"),

        SPKTopicSection(@"", @[
            [SPKSetting switchCellWithTitle:@"评论点赞确认"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"general_comments_confirm_like"],

            [SPKSetting switchCellWithTitle:@"隐藏评论购物内容"
                                       icon:SPKSettingsIcon(@"shopping_bag")
                                defaultsKey:@"general_comments_hide_shopping"],

            [SPKSetting switchCellWithTitle:@"隐藏礼物按钮"
                                       icon:SPKSettingsIcon(@"gift")
                                defaultsKey:@"general_comments_hide_gifts_button"],
        ],
        @"1. 点赞评论前显示确认提示。\n"
         "2. 隐藏评论区中的购物内容。\n"
         "3. 隐藏评论输入框中的礼物按钮。"),

        SPKTopicSection(@"账号", @[
            [self perAccountSetting],
            [self perAccountInfoSetting]
        ],
        @"为每个登录账号分别保存 Sparkle 设置。"),

        SPKTopicSection(@"存储", @[
            clearCacheSetting,

            [SPKSetting menuCellWithTitle:@"自动清理缓存"
                                     icon:SPKSettingsIcon(@"clock")
                                      menu:SPKCacheAutoClearMenu()]
        ],
        @"每次 Instagram 启动时自动检查并清理缓存。"),

        SPKTopicSection(@"应用", @[
            [self appIconSetting],

            [self defaultMenuIconSetting],

            [SPKSetting switchCellWithTitle:@"关闭应用触感反馈"
                                       icon:SPKSettingsIcon(@"haptics")
                                defaultsKey:@"general_disable_haptics"]
        ],
        @"选择 Instagram 应用图标。"
         "「打开菜单图标」用于设置操作按钮中的菜单图标。"
         "关闭应用触感反馈后，将停用 Instagram 中的触感和振动反馈。"),
    ]);
}

@end
