// Hide the Meta AI effects button in the story camera's side tools menu, as
// part of the Meta AI "Creation Tools" toggle.
//
// The story camera hands IGCameraToolsMenu an array of tool buttons; the menu
// lays them out and decides which ones overflow behind the open/close chevron.
// Dropping the gen-AI tool from that array before the menu sees it makes the
// remaining tools close the gap, where hiding the view would leave its slot
// reserved.
//
// Tools carry a stable identifier that never varies by language. On 450.1 the
// effects tool is kIGStoryCameraToolIdentifierGenAIImagine, with the
// accessibility identifier story-camera-genai-imagine; both are assigned before
// the menu is created. Matching the gen-AI prefix also covers sibling tools.
//
// The pref is re-checked each time a menu is built, so the toggle applies the
// next time the camera is created.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"

static BOOL SPKIsStoryCameraGenAITool(id tool) {
    if ([tool respondsToSelector:@selector(identifier)]) {
        id identifier = [tool identifier];
        if ([identifier isKindOfClass:NSString.class] && [identifier hasPrefix:@"kIGStoryCameraToolIdentifierGenAI"])
            return YES;
    }
    if ([tool isKindOfClass:UIView.class])
        return [((UIView *)tool).accessibilityIdentifier hasPrefix:@"story-camera-genai"];
    return NO;
}

static id SPKStoryCameraToolsWithoutGenAI(id tools) {
    if (![SPKUtils getBoolPref:@"general_hide_meta_ai_creation"] || ![tools isKindOfClass:NSArray.class])
        return tools;

    NSIndexSet *kept = [(NSArray *)tools indexesOfObjectsPassingTest:^BOOL(id tool, NSUInteger idx, BOOL *stop) {
        return !SPKIsStoryCameraGenAITool(tool);
    }];
    if (kept.count == [(NSArray *)tools count])
        return tools;
    return [(NSArray *)tools objectsAtIndexes:kept];
}

%group SPKHideMetaAIStoryCameraHooks

%hook IGCameraToolsMenu

- (id)initWithTools:(id)tools store:(id)store {
    return %orig(SPKStoryCameraToolsWithoutGenAI(tools), store);
}

- (id)initWithTools:(id)tools userSession:(id)session {
    return %orig(SPKStoryCameraToolsWithoutGenAI(tools), session);
}

%end

%end // group SPKHideMetaAIStoryCameraHooks

void SPKInstallHideMetaAIStoryCameraHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (NSClassFromString(@"IGCameraToolsMenu")) {
            %init(SPKHideMetaAIStoryCameraHooks);
        }
    });
}
