#import "SPKReelsSettingsProvider.h"

#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../SPKTopicSettingsSupport.h"

static NSString *const kSPKReelsActionButtonEnabledKey = @"reels_action_btn";

@implementation SPKReelsSettingsProvider

+ (SPKSetting *)rootSetting {
    return SPKTopicNavigationSetting(@"Reels", @"reels", 24.0, @[
        SPKTopicSection(@"操作按钮", @[
            [SPKSetting switchCellWithTitle:@"Reels 操作按钮"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:kSPKReelsActionButtonEnabledKey],
            SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSourceReels),
            SPKActionButtonConfigurationNavigationSetting(
                SPKActionButtonSourceReels,
                @"Reels",
                SPKActionButtonSupportedActionsForSource(SPKActionButtonSourceReels),
                SPKActionButtonDefaultSectionsForSource(SPKActionButtonSourceReels)
            )
        ],
                        @"选择点击 Reels 操作按钮时执行的操作。长按可打开完整操作菜单。"),

        SPKTopicSection(@"播放与操作", @[
            [SPKSetting menuCellWithTitle:@"点击操作"
                                     icon:SPKSettingsIcon(@"play")
                                     menu:SPKReelsTapControlMenu()],

            [SPKSetting switchCellWithTitle:@"显示播放进度条"
                                       icon:SPKSettingsIcon(@"clock")
                                defaultsKey:@"reels_show_scrubber"],

            [SPKSetting switchCellWithTitle:@"禁止 Reels 自动取消静音"
                                       icon:SPKSettingsIcon(@"volume_off")
                                defaultsKey:@"reels_disable_auto_unmute"
                            requiresRestart:YES],

            [SPKSetting switchCellWithTitle:@"禁止刷新 Reels 标签页"
                                       icon:SPKSettingsIcon(@"arrow_cw")
                                defaultsKey:@"reels_disable_tab_refresh"]
        ],
                        @"点击操作用于设置点击 Reels 时的行为。"
                         @"关闭自动取消静音后，Reels 不会因音量或静音模式变化而自动恢复声音。"),

        SPKTopicSection(@"浏览限制", @[
            [SPKSetting switchCellWithTitle:@"禁止滑动切换 Reels"
                                       icon:SPKSettingsIcon(@"autoscroll")
                                defaultsKey:@"reels_disable_scrolling"
                            requiresRestart:YES],

            [SPKSetting switchCellWithTitle:@"限制连续浏览 Reels"
                                       icon:SPKSettingsIcon(@"arrow_down")
                                defaultsKey:@"reels_prevent_doom_scroll"],

            [SPKSetting stepperCellWithTitle:@"连续浏览上限"
                                    subtitle:@"仅加载 %@ 个%@"
                                 defaultsKey:@"reels_doom_scroll_limit"
                                         min:1
                                         max:100
                                        step:1
                                       label:@"Reels"                               singularLabel:@"Reel"]
        ],
                        @"1. 禁止上下滑动切换 Reels，停留在当前 Reels。\n"
                         @"2. 达到设定数量后停止继续加载 Reels。\n"
                         @"3. 设置触发“限制连续浏览”的 Reels 数量。"),

        SPKTopicSection(@"界面", @[
            [SPKSetting switchCellWithTitle:@"隐藏 Reels 顶部栏"
                                       icon:SPKSettingsIcon(@"reels")
                                defaultsKey:@"reels_hide_header"],

            [SPKSetting switchCellWithTitle:@"隐藏转发按钮"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"reels_hide_repost_btn"
                            requiresRestart:YES]
        ],
                        nil),

        SPKTopicSection(@"互动数据", @[
            [SPKSetting switchCellWithTitle:@"隐藏点赞数"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"reels_hide_like_count"],

            [SPKSetting switchCellWithTitle:@"隐藏评论数"
                                       icon:SPKSettingsIcon(@"comment")
                                defaultsKey:@"reels_hide_comment_count"],

            [SPKSetting switchCellWithTitle:@"隐藏转发数"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"reels_hide_repost_count"],

            [SPKSetting switchCellWithTitle:@"隐藏分享数"
                                       icon:SPKSettingsIcon(@"messages")
                                defaultsKey:@"reels_hide_reshare_count"],

            [SPKSetting switchCellWithTitle:@"隐藏收藏数"
                                       icon:SPKSettingsIcon(@"save")
                                defaultsKey:@"reels_hide_save_count"]
        ],
                        nil),

        SPKTopicSection(@"操作确认", @[
            [SPKSetting switchCellWithTitle:@"点赞前确认"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"reels_confirm_like"],

            [SPKSetting switchCellWithTitle:@"双击点赞前确认"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"reels_confirm_double_tap_like"],

            [SPKSetting switchCellWithTitle:@"刷新 Reels 前确认"
                                       icon:SPKSettingsIcon(@"arrow_cw")
                                defaultsKey:@"reels_confirm_refresh"],

            [SPKSetting switchCellWithTitle:@"转发前确认"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"reels_confirm_repost"]
        ],
                        @"在执行已启用的 Reels 操作前显示确认提示。")
    ]);
}

@end
