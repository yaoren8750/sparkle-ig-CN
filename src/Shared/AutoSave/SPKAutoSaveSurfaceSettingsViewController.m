#import "SPKAutoSaveSurfaceSettingsViewController.h"

#import "../../Settings/SPKSetting.h"
#import "../../Settings/SPKTopicSettingsSupport.h"
#import "../../Utils.h"
#import "SPKAutoSaveFilter.h"

@implementation SPKAutoSaveSurfaceDescriptor
@end

@implementation SPKAutoSaveSurfaceSettingsViewController

+ (SPKAutoSaveSurfaceDescriptor *)descriptor {
    NSAssert(NO, @"%@ must override +descriptor", NSStringFromClass(self));
    return nil;
}

+ (NSArray *)contentSections {
    SPKAutoSaveSurfaceDescriptor *descriptor = [self descriptor];
    SPKAutoSaveFilterConfig *filter = descriptor.filter;

    BOOL (^autoSaveEnabled)(void) = ^BOOL {
        return SPKAutoSaveFilterEnabled(filter);
    };

    SPKSetting *master = [SPKSetting switchCellWithTitle:descriptor.masterTitle
                                                    icon:SPKSettingsIcon(@"sparkle_gallery")
                                             defaultsKey:filter.enabledKey];
    master.reloadsTableOnSwitchChange = YES; // grey out / re-enable the dependents live

    SPKSetting *filterMode = [SPKSetting menuCellWithTitle:@"筛选模式"
                                                      icon:SPKSettingsIcon(@"filter")
                                                      menu:SPKAutoSaveFilterModeMenu(filter.filterModeKey, filter.subjectPlural)];
    filterMode.enabledProvider = autoSaveEnabled;

    SPKSetting *list = [SPKSetting navigationCellWithTitle:SPKAutoSaveFilterListTitle(filter)
                                                  subtitle:@""
                                                      icon:SPKSettingsIcon(descriptor.listIcon)
                                            viewController:descriptor.listProvider()];
    list.userInfo = @{@"accessoryText" : [NSString stringWithFormat:@"%lu", (unsigned long)SPKAutoSaveFilterList(filter).count]};
    list.enabledProvider = autoSaveEnabled;

    return @[ SPKTopicSection(descriptor.title,
                              @[ master, filterMode, list ],
                              descriptor.footerProvider(SPKAutoSaveFilterAllMode(filter))) ];
}

+ (NSArray *)searchSections {
    return [self contentSections];
}

- (instancetype)init {
    return [super initWithTitle:[[self class] descriptor].title
                       sections:[[self class] contentSections]
                   reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Rebuild so the list row reflects the current mode + count after editing it.
    [self replaceSections:[[self class] contentSections]];
}

- (void)menuChanged:(UICommand *)command {
    [super menuChanged:command];
    // Switching Filter Mode swaps which list is active, so the list row's title,
    // count, and the section footer all change with it.
    if ([command.propertyList[@"defaultsKey"] isEqualToString:[[self class] descriptor].filter.filterModeKey]) {
        [self replaceSections:[[self class] contentSections]];
    }
}

@end
