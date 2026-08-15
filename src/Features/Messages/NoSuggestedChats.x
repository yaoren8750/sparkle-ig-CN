#import "../../InstagramHeaders.h"
#import "../../Utils.h"

// Channels dms tab (header)
%group SPKNoSuggestedChatsHooks

%hook IGDirectInboxHeaderSectionController
- (id)viewModel {
    id originalViewModel = %orig;

    if ([[originalViewModel title] isEqualToString:@"Suggested"]) {

        if ([SPKUtils getBoolPref:@"msgs_hide_suggested_chats"]) {
            SPKLog(@"General", @"[Sparkle] Hiding suggested chats (header: channels tab)");

            return nil;
        }
    }

    return originalViewModel;
}
%end

%end

void SPKInstallNoSuggestedChatsHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:@"msgs_hide_suggested_chats"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKNoSuggestedChatsHooks,
                       IGDirectInboxHeaderSectionController = SPKResolveIGClass(@"IGDirectInboxViewControllerSwift.IGDirectInboxHeaderSectionController", @"IGDirectInboxHeaderSectionController"));
    });
}
