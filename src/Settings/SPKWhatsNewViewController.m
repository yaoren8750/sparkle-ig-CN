#import "SPKStrings.h"
#import "SPKWhatsNewViewController.h"
#import "../Tweak.h"

@implementation SPKWhatsNewViewController

// Release notes are curated from the conventional-commit log for the release range
// (see whats-new.sh). Feature rows carry a per-surface IG catalog glyph; fix rows
// share the `subtract` bullet so they read as one clean list. Icon names are
// SPKAssetUtils override keys — never SF Symbols. Keep in sync with README/FEATURES.
//
// Every content row is replaced wholesale each release. The keys name the change
// rather than its English wording, and the previous release's keys are deleted from
// every catalog, so a stale translation can never be reused for a different row.
- (NSArray<SPKPagedSheetPage *> *)buildPages {
    return @[
        [SPKPagedSheetPage pageWithTitle:SPKL(@"SETTINGS_WHATS_NEW_NEW_FEATURES_TEXT")
                                    body:[NSString stringWithFormat:SPKL(@"SETTINGS_WHATS_NEW_WHAT_S_NEW_VALUE_FORMAT"), SPKVersionString]
                                    rows:@[
                                        @{ @"icon": @"translate", @"text": SPKL(@"SETTINGS_WHATS_NEW_JAPANESE_POLISH_TEXT") },
                                        @{ @"icon": @"notification", @"text": SPKL(@"SETTINGS_WHATS_NEW_INSTAGRAM_TOAST_STYLE_TEXT") },
                                        @{ @"icon": @"pin", @"text": SPKL(@"SETTINGS_WHATS_NEW_SHARE_SHEET_PINS_TEXT") },
                                        @{ @"icon": @"eye", @"text": SPKL(@"SETTINGS_WHATS_NEW_STORIES_SEEN_LOCALLY_TEXT") },
                                        @{ @"icon": @"visual_search", @"text": SPKL(@"SETTINGS_WHATS_NEW_HIDE_REELS_VISUAL_SEARCH_TEXT") },
                                        @{ @"icon": @"app", @"text": SPKL(@"SETTINGS_WHATS_NEW_GLASS_APP_ICON_TEXT") },
                                    ]],
        [SPKPagedSheetPage pageWithTitle:SPKL(@"SETTINGS_WHATS_NEW_MORE_EXPLORE_TEXT")
                                    body:@""
                                    rows:@[
                                        @{ @"icon": @"link", @"text": SPKL(@"SETTINGS_WHATS_NEW_SIDELOAD_LINK_HANDOFF_TEXT") },
                                        @{ @"icon": @"ads", @"text": SPKL(@"SETTINGS_WHATS_NEW_HIDE_META_PROMOTIONS_TEXT") },
                                        @{ @"icon": @"reactions", @"text": SPKL(@"SETTINGS_WHATS_NEW_HIDE_COMMENT_EMOJI_BAR_TEXT") },
                                        @{ @"icon": @"autoscroll", @"text": SPKL(@"SETTINGS_WHATS_NEW_REELS_AUTO_SCROLL_TEXT") },
                                        @{ @"icon": @"meta_ai", @"text": SPKL(@"SETTINGS_WHATS_NEW_HIDE_STORY_AI_BUTTONS_TEXT") },
                                        @{ @"icon": @"share", @"text": SPKL(@"SETTINGS_WHATS_NEW_EXPORT_LANGUAGE_STRINGS_TEXT") },
                                        @{ @"text": SPKL(@"SETTINGS_WHATS_NEW_PLENTY_MORE_TEXT") },
                                    ]],
        [SPKPagedSheetPage pageWithTitle:SPKL(@"SETTINGS_WHATS_NEW_FIXES_IMPROVEMENTS_TEXT")
                                    body:@""
                                    rows:@[
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_INSTAGRAM_451_COMPATIBILITY_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_HIDDEN_TABS_SWIPE_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_EYE_EARLIER_STORIES_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_DOWNLOAD_BUSY_FALLBACK_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_PREVIEW_TRIM_QUALITY_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_AV1_FRAME_CAPTURE_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_INLINE_SUGGESTED_REELS_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_NATIVE_ALERT_STYLE_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_FOLLOW_BADGE_ACCOUNTS_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_FIX_CLASSIC_BLUE_410_TEXT") },
                                        @{ @"icon": @"subtract", @"text": SPKL(@"SETTINGS_WHATS_NEW_OTHER_BUG_FIXES_UI_IMPROVEMENTS_TEXT") },
                                    ]],
    ];
}

- (NSString *)finishButtonTitle {
    return SPKL(@"SETTINGS_WHATS_NEW_DONE_TEXT");
}

- (BOOL)allowsInteractiveDismiss {
    return YES;
}

@end
