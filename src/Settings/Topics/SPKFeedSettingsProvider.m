#import "SPKFeedSettingsProvider.h"

#import "../../Features/Feed/HeaderActionButton.h"
#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../SPKTopicSettingsSupport.h"

static NSString *const kSPKFeedActionButtonEnabledKey = @"feed_action_btn";

@implementation SPKFeedSettingsProvider

+ (SPKSetting *)rootSetting {
    return SPKTopicNavigationSetting(@"主页动态", @"feed", 24.0, @[
        
        SPKTopicSection(@"操作按钮", @[
            [SPKSetting switchCellWithTitle:@"主页操作按钮"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:kSPKFeedActionButtonEnabledKey],
            
            SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSourceFeed),
            
            SPKActionButtonConfigurationNavigationSetting(
                SPKActionButtonSourceFeed,
                @"主页",
                SPKActionButtonSupportedActionsForSource(SPKActionButtonSourceFeed),
                SPKActionButtonDefaultSectionsForSource(SPKActionButtonSourceFeed)
            )
        ],
        @"设置点击操作按钮时执行的操作。长按可打开完整操作菜单。"),
        
        
        SPKTopicSection(@"顶部快捷按钮", @[
            [SPKSetting switchCellWithTitle:@"主页顶部按钮"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:kSPKHeaderButtonEnabledKey],
            
            SPKFeedHeaderButtonDefaultActionNavigationSetting(),
            
            [SPKSetting navigationCellWithTitle:@"配置快捷入口"
                                       subtitle:@""
                                           icon:SPKSettingsIcon(@"sliders")
                                    navSections:@[
                                        
                SPKTopicSection(@"快捷入口", @[
                    
                    [SPKSetting switchCellWithTitle:@"图库"
                                               icon:SPKSettingsIcon(@"sparkle_gallery")
                                        defaultsKey:@"feed_header_button_dest_gallery"],
                    
                    [SPKSetting switchCellWithTitle:@"主页分析"
                                               icon:SPKSettingsIcon(@"profile_analyzer")
                                        defaultsKey:@"feed_header_button_dest_analyzer"],
                    
                    [SPKSetting switchCellWithTitle:@"已删除消息"
                                               icon:SPKSettingsIcon(@"channels")
                                        defaultsKey:@"feed_header_button_dest_deleted"],
                    
                    [SPKSetting switchCellWithTitle:@"下载"
                                               icon:SPKSettingsIcon(@"download")
                                        defaultsKey:@"feed_header_button_dest_downloads"],
                    
                    [SPKSetting switchCellWithTitle:@"Sparkle 设置"
                                               icon:SPKSettingsIcon(@"settings")
                                        defaultsKey:@"feed_header_button_dest_settings"],
                    
                ],
                @"选择主页顶部按钮可以打开的功能。启用一个入口后可直接点击打开；启用多个入口后，长按按钮可选择。")
            ]],
        ],
        @"在主页顶部添加 Sparkle 快捷按钮。点击打开当前设置的入口，长按打开已启用入口的菜单。"),
        
        
        SPKTopicSection(@"界面布局", @[
            
            SPKSettingApplySelectedMenuIcon(
                [SPKSetting menuCellWithTitle:@"主页动态"
                                         icon:SPKSettingsIcon(@"feed")
                                         menu:SPKMainFeedModeMenu()],
                SPKSettingsIcon(@"feed")
            ),
            
            [SPKSetting switchCellWithTitle:@"停用应用图标手势"
                                       icon:SPKSettingsIcon(@"app")
                                defaultsKey:@"feed_disable_appicon_gesture"],
            
            [SPKSetting switchCellWithTitle:@"隐藏快拍栏"
                                       icon:SPKSettingsIcon(@"story")
                                defaultsKey:@"feed_hide_stories_tray"],
            
            [SPKSetting switchCellWithTitle:@"隐藏整个主页动态"
                                       icon:SPKSettingsIcon(@"feed")
                                defaultsKey:@"feed_hide_entire_feed"],
            
            [SPKSetting switchCellWithTitle:@"隐藏推荐帖子"
                                       icon:SPKSettingsIcon(@"carousel")
                                defaultsKey:@"feed_hide_suggested_posts"],
            
            [SPKSetting switchCellWithTitle:@"隐藏推荐 Reels"
                                       icon:SPKSettingsIcon(@"reels_gallery")
                                defaultsKey:@"feed_hide_suggested_reels"],
            
            [SPKSetting switchCellWithTitle:@"隐藏推荐 Threads 帖子"
                                       icon:SPKSettingsIcon(@"threads")
                                defaultsKey:@"feed_hide_suggested_threads"],
            
            [SPKSetting switchCellWithTitle:@"隐藏转发按钮"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"feed_hide_repost_btn"
                            requiresRestart:YES]
            
        ],
        @"1. 强制使用 Instagram 按时间排序的“关注”动态，而不是算法推荐的“为你推荐”动态。页面标题仍显示“为你推荐”。\n"
         @"2. 停止长按主页顶部 Logo 时打开 Instagram 应用图标选择器。Sparkle 已在设置中提供独立的应用图标设置。\n"
         @"3. 隐藏主页顶部的横向快拍栏。\n"
         @"4. 隐藏整个主页动态，仅保留顶部栏。\n"
         @"5. 隐藏主页中的算法推荐帖子。\n"
         @"6. 隐藏主页中的推荐 Reels。\n"
         @"7. 隐藏主页中的推荐 Threads 帖子。\n"
         @"8. 隐藏主页帖子的转发按钮。"),
        
        
        SPKTopicSection(@"互动数据", @[
            
            [SPKSetting switchCellWithTitle:@"隐藏点赞数"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"feed_hide_like_count"],
            
            [SPKSetting switchCellWithTitle:@"隐藏评论数"
                                       icon:SPKSettingsIcon(@"comment")
                                defaultsKey:@"feed_hide_comment_count"],
            
            [SPKSetting switchCellWithTitle:@"隐藏转发数"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"feed_hide_repost_count"],
            
            [SPKSetting switchCellWithTitle:@"隐藏分享数"
                                       icon:SPKSettingsIcon(@"messages")
                                defaultsKey:@"feed_hide_reshare_count"]
            
        ],
        nil),
        
        
        SPKTopicSection(@"媒体", @[
            
            [SPKSetting switchCellWithTitle:@"长按展开媒体"
                                       icon:SPKSettingsIcon(@"expand")
                                defaultsKey:@"feed_long_press_expand"],
            
            [SPKSetting switchCellWithTitle:@"停用视频自动播放"
                                       icon:SPKSettingsIcon(@"autoplay_off")
                                defaultsKey:@"feed_disable_autoplay"
                            requiresRestart:YES],
            
            [SPKSetting switchCellWithTitle:@"展开视频时默认静音"
                                       icon:SPKSettingsIcon(@"volume_off")
                                defaultsKey:@"feed_expanded_vid_start_muted"],
            
        ],
        @"长按主页中的媒体即可展开查看。自动播放设置可阻止主页视频自动播放。"),
        
        
        SPKTopicSection(@"刷新", @[
            
            [SPKSetting switchCellWithTitle:@"停用主页刷新"
                                       icon:SPKSettingsIcon(@"home")
                                defaultsKey:@"feed_disable_home_refresh"],
            
            [SPKSetting switchCellWithTitle:@"停用后台刷新"
                                       icon:SPKSettingsIcon(@"arrow_cw")
                                defaultsKey:@"feed_disable_bg_refresh"]
            
        ],
        @"阻止重复点击主页标签触发刷新，也可阻止应用在后台活动时自动刷新。"),
        
        
        SPKTopicSection(@"操作确认", @[
            
            [SPKSetting switchCellWithTitle:@"点赞前确认"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"feed_confirm_post_like"],
            
            [SPKSetting switchCellWithTitle:@"双击点赞前确认"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"feed_confirm_double_tap_like"],
            
            [SPKSetting switchCellWithTitle:@"转发前确认"
                                       icon:SPKSettingsIcon(@"repost")
                                defaultsKey:@"feed_confirm_repost"],
            
            [SPKSetting switchCellWithTitle:@"发表评论前确认"
                                       icon:SPKSettingsIcon(@"comment")
                                defaultsKey:@"feed_confirm_post_comment"]
            
        ],
        @"在执行已启用的主页操作前显示确认提示。")
    ]);
}

@end
