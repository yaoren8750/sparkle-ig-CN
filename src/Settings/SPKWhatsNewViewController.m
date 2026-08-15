#import "SPKWhatsNewViewController.h"
#import "../Tweak.h"

@implementation SPKWhatsNewViewController

// Release notes are curated from the conventional-commit log for the release range
// (see whats-new.sh). Feature rows carry a per-surface IG catalog glyph; fix rows
// share the `subtract` bullet so they read as one clean list. Icon names are
// SPKAssetUtils override keys — never SF Symbols. Keep in sync with README/FEATURES.
- (NSArray<SPKPagedSheetPage *> *)buildPages {
    return @[
        [SPKPagedSheetPage pageWithTitle:@"New Features"
                                    body:[NSString stringWithFormat:@"What's new in %@", SPKVersionString]
                                    rows:@[
                                        @{ @"icon": @"sparkle_gallery", @"text": @"Import media into the Gallery from Files or a Regram vault" },
                                        @{ @"icon": @"folder", @"text": @"Browse every Gallery file at once, without entering folders" },
                                        @{ @"icon": @"crop", @"text": @"Crop, rotate and flip a video, with finer trimming" },
                                        @{ @"icon": @"instants", @"text": @"Upload any media as an instant" },
                                        @{ @"icon": @"instants_burst", @"text": @"Browse the instants you saved, grouped by person" },
                                        @{ @"icon": @"download", @"text": @"Auto-save stories, view-once messages and instants as you view them" },
                                        @{ @"icon": @"external_link", @"text": @"Profiles, posts and reels open as real Instagram pages" },
                                    ]],
        [SPKPagedSheetPage pageWithTitle:@"More To Explore"
                                    body:@""
                                    rows:@[
                                        @{ @"icon": @"hd_check_filled", @"text": @"Refined photo quality tiers with 4K fetching" },
                                        @{ @"icon": @"folder", @"text": @"Save downloads into a custom Photos album" },
                                        @{ @"icon": @"pinch", @"text": @"Pinch to zoom into videos in the full-screen preview" },
                                        @{ @"icon": @"messages", @"text": @"Refined messages-only mode" },
                                        @{ @"icon": @"story_preview", @"text": @"See message previews by long pressing a chat" },
                                        @{ @"icon": @"sticker", @"text": @"Upload videos as story stickers from Photos or Sparkle Gallery" },
                                        @{ @"icon": @"calendar", @"text": @"See a post's date in the action button menu" },
                                        @{ @"icon": @"profile_analyzer", @"text": @"Swipe to delete a single change in Profile Analyzer" },
                                        @{ @"icon": @"filter", @"text": @"Sort, filter and search the Gallery picker across folders" },
                                        @{ @"text": @"...and plenty more!" },
                                    ]],
        [SPKPagedSheetPage pageWithTitle:@"Fixes & Improvements"
                                    body:@""
                                    rows:@[
                                        @{ @"icon": @"subtract", @"text": @"Fixed a long-standing freeze that made the app crawl after a few screens" },
                                        @{ @"icon": @"subtract", @"text": @"Notifications are now instant and don't duplicate" },
                                        @{ @"icon": @"subtract", @"text": @"Much faster Gallery: instant opening, smoother picker, far less memory" },
                                        @{ @"icon": @"subtract", @"text": @"Story preview and inbox refresh work again on the latest Instagram" },
                                        @{ @"icon": @"subtract", @"text": @"Instants now download/auto-save in full resolution" },
                                        @{ @"icon": @"subtract", @"text": @"Poll vote counts now respect hide UI on capture" },
                                        @{ @"icon": @"subtract", @"text": @"Safe Mode now explains itself, and offers to turn itself off" },
                                        @{ @"icon": @"subtract", @"text": @"Other bug fixes & UI improvements" },
                                    ]],
    ];
}

- (NSString *)finishButtonTitle {
    return @"完成";
}

- (BOOL)allowsInteractiveDismiss {
    return YES;
}

@end
