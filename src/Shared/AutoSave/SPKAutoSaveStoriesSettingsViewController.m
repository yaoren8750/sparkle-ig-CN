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
        descriptor.masterTitle = @"自动保存快拍";
        descriptor.listIcon = @"users";
        descriptor.listProvider = ^UIViewController * {
            return SPKStoryAutoSaveListViewController();
        };
        descriptor.footerProvider = ^NSString *(BOOL allMode) {
            return allMode ? @"1. 在观看快拍时自动保存。已经保存过的快拍会跳过，因此重复观看不会再次保存。\n"
                              @"2. “所有用户”会保存所有用户的快拍，但排除列表中的用户除外。\n"
                              @"3. 这些用户的快拍不会自动保存。可以在此处或快拍操作菜单中添加用户。"
                           : @"1. 在观看快拍时自动保存。已经保存过的快拍会跳过，因此重复观看不会再次保存。\n"
                              @"2. “指定用户”只会保存你选择的用户的快拍。\n"
                              @"3. 这些用户的快拍会自动保存。可以在此处或快拍操作菜单中添加用户。";
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
        descriptor.masterTitle = @"自动保存阅后即焚媒体";
        descriptor.listIcon = @"messages";
        descriptor.listProvider = ^UIViewController * {
            return SPKDirectAutoSaveListViewController();
        };
        descriptor.footerProvider = ^NSString *(BOOL allMode) {
            return allMode ? @"1. 在打开阅后即焚和可重播的照片、视频时自动保存。已经保存过的媒体会跳过，因此重复播放不会再次保存。\n"
                              @"2. “所有聊天”会保存所有聊天中的媒体，但排除列表中的聊天除外。\n"
                              @"3. 这些聊天中的阅后即焚媒体不会自动保存。可以在此处，或查看器的操作菜单和眼睛按钮菜单中添加聊天。"
                           : @"1. 在打开阅后即焚和可重播的照片、视频时自动保存。已经保存过的媒体会跳过，因此重复播放不会再次保存。\n"
                              @"2. “指定聊天”只会保存你选择的聊天中的媒体。\n"
                              @"3. 这些聊天中的阅后即焚媒体会自动保存。可以在此处，或查看器的操作菜单和眼睛按钮菜单中添加聊天。";
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
        descriptor.title = @"瞬间";
        descriptor.masterTitle = @"自动保存瞬间";
        descriptor.listIcon = @"users";
        descriptor.listProvider = ^UIViewController * {
            return SPKInstantsAutoSaveListViewController();
        };
        descriptor.footerProvider = ^NSString *(BOOL allMode) {
            return allMode ? @"1. 在打开瞬间时自动保存，包括你逐个点击查看的每条瞬间。已经保存过的瞬间会跳过。\n"
                              @"2. “所有用户”会保存所有用户的瞬间，但排除列表中的用户除外。\n"
                              @"3. 这些用户的瞬间不会自动保存。可以在此处通过用户名添加用户。"
                           : @"1. 在打开瞬间时自动保存，包括你逐个点击查看的每条瞬间。已经保存过的瞬间会跳过。\n"
                              @"2. “指定用户”只会保存你选择的用户的瞬间。\n"
                              @"3. 这些用户的瞬间会自动保存。可以在此处通过用户名添加用户。";
        };
    });
    return descriptor;
}

@end
