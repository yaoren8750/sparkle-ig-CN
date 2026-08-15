#import "SPKAutoSaveStoriesSettingsViewController.h"

#import "../Instants/SPKInstantsAutoSave.h"
#import "../Messages/SPKDirectAutoSave.h"
#import "../Stories/SPKStoryAutoSave.h"
#import "SPKAutoSaveFilter.h"

@implementation SPKAutoSaveStoriesSettingsViewController

+ (SPKAutoSaveSurfaceDescriptor *)descriptor {
    static SPKAutoSaveSurfaceDescriptor *descriptor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        descriptor = [SPKAutoSaveSurfaceDescriptor new];
        descriptor.filter = SPKStoryAutoSaveFilterConfig();
        descriptor.title = @"快拍";
        descriptor.masterTitle = @"Auto-Save Stories";
        descriptor.listIcon = @"users";
        descriptor.listProvider = ^UIViewController * {
            return SPKStoryAutoSaveListViewController();
        };
        descriptor.footerProvider = ^NSString *(BOOL allMode) {
            return allMode ? @"1. Save stories as you watch them. Stories you already have are skipped, so re-watching "
                             @"never saves twice.\n"
                             @"2. All Users saves every story except the users you exclude.\n"
                             @"3. Users whose stories are never auto-saved. Add them here or from the story action menu."
                           : @"1. Save stories as you watch them. Stories you already have are skipped, so re-watching "
                             @"never saves twice.\n"
                             @"2. Selected Users saves only the users you pick.\n"
                             @"3. Users whose stories are auto-saved. Add them here or from the story action menu.";
        };
    });
    return descriptor;
}

@end

@implementation SPKAutoSaveMessagesSettingsViewController

+ (SPKAutoSaveSurfaceDescriptor *)descriptor {
    static SPKAutoSaveSurfaceDescriptor *descriptor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        descriptor = [SPKAutoSaveSurfaceDescriptor new];
        descriptor.filter = SPKDirectAutoSaveFilterConfig();
        descriptor.title = @"消息";
        descriptor.masterTitle = @"Auto-Save View-Once Media";
        descriptor.listIcon = @"messages";
        descriptor.listProvider = ^UIViewController * {
            return SPKDirectAutoSaveListViewController();
        };
        descriptor.footerProvider = ^NSString *(BOOL allMode) {
            return allMode ? @"1. Save view-once and replayable photos and videos as you open them. Media you already "
                             @"have is skipped, so replaying never saves twice.\n"
                             @"2. All Chats saves every one except in the chats you exclude.\n"
                             @"3. Chats whose view-once media is never auto-saved. Add them here, or from the viewer's "
                             @"action menu and eye button menu."
                           : @"1. Save view-once and replayable photos and videos as you open them. Media you already "
                             @"have is skipped, so replaying never saves twice.\n"
                             @"2. Selected Chats saves only the chats you pick.\n"
                             @"3. Chats whose view-once media is auto-saved. Add them here, or from the viewer's action "
                             @"menu and eye button menu.";
        };
    });
    return descriptor;
}

@end

@implementation SPKAutoSaveInstantsSettingsViewController

+ (SPKAutoSaveSurfaceDescriptor *)descriptor {
    static SPKAutoSaveSurfaceDescriptor *descriptor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        descriptor = [SPKAutoSaveSurfaceDescriptor new];
        descriptor.filter = SPKInstantsAutoSaveFilterConfig();
        descriptor.title = @"Instants";
        descriptor.masterTitle = @"Auto-Save Instants";
        descriptor.listIcon = @"users";
        descriptor.listProvider = ^UIViewController * {
            return SPKInstantsAutoSaveListViewController();
        };
        descriptor.footerProvider = ^NSString *(BOOL allMode) {
            return allMode ? @"1. Save instants as you open them, including each one you tap through. Instants you "
                             @"already have are skipped.\n"
                             @"2. All Users saves every instant except from the users you exclude.\n"
                             @"3. Users whose instants are never auto-saved. Add them here by username."
                           : @"1. Save instants as you open them, including each one you tap through. Instants you "
                             @"already have are skipped.\n"
                             @"2. Selected Users saves only the users you pick.\n"
                             @"3. Users whose instants are auto-saved. Add them here by username.";
        };
    });
    return descriptor;
}

@end
