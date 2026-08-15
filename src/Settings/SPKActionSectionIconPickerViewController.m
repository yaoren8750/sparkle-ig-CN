#import "SPKActionSectionIconPickerViewController.h"

#import "../AssetUtils.h"
#import "../Shared/ActionButton/SPKActionDescriptor.h"
#import "SPKIconPickerViewController.h"
#import "SPKInstagramIconCatalog.h"

@interface SPKActionSectionIconPickerViewController ()
@property (nonatomic, copy) NSString *selectedIconName;
@property (nonatomic, copy) NSString *selectedCanonicalName;
@property (nonatomic, copy) void (^onSelect)(NSString *iconName);
@end

@implementation SPKActionSectionIconPickerViewController

- (instancetype)initWithSelectedIconName:(NSString *)selectedIconName
                                onSelect:(void (^)(NSString *iconName))onSelect {
    self = [super init];
    if (self) {
        _selectedIconName = [selectedIconName copy] ?: @"more";
        _selectedCanonicalName = [[self class] canonicalNameForIconName:_selectedIconName];
        _onSelect = [onSelect copy];
        self.title = @"分组图标";
    }
    return self;
}

// Maps any stored icon name (a shorthand alias like "carousel"/"action", or a
// raw "ig_icon_*" catalog name) to the canonical catalog name actually rendered,
// so a selection made via the old shorthand "Shortcuts" list still highlights the
// matching real icon in the unified Instagram list.
+ (NSString *)canonicalNameForIconName:(NSString *)iconName {
    if (iconName.length == 0)
        return @"";
    NSString *resolved = [SPKAssetUtils resolvedInstagramIconNameForName:iconName];
    return resolved.length > 0 ? resolved : iconName;
}

#pragma mark - SPKIconPickerViewController

- (SPKIconPickerCellStyle)cellStyle {
    return SPKIconPickerCellStyleGlyph;
}
- (NSString *)searchPlaceholder {
    return @"Search Icons";
}

- (NSArray<SPKIconPickerSection *> *)buildSections {
    NSMutableArray<SPKIconPickerItem *> *items = [NSMutableArray array];
    for (NSString *iconName in [SPKInstagramIconCatalog availableInstagramIconNames]) {
        NSString *title = [SPKInstagramIconCatalog displayNameForIconName:iconName];
        NSString *search = [NSString stringWithFormat:@"%@ %@", [SPKInstagramIconCatalog searchTextForIconName:iconName], [title lowercaseString]];
        [items addObject:[SPKIconPickerItem itemWithIdentifier:iconName title:title searchText:search]];
    }
    return @[ [SPKIconPickerSection sectionWithTitle:nil items:items] ];
}

- (UIImage *)imageForItem:(SPKIconPickerItem *)item {
    return [SPKAssetUtils instagramIconNamed:item.identifier
                                   pointSize:28.0
                                      source:[SPKInstagramIconCatalog isInstagramBundleIconName:item.identifier] ? SPKAssetCatalogSourceFBSharedFramework : SPKAssetCatalogSourceAutomatic
                               renderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (BOOL)isSelectedItem:(SPKIconPickerItem *)item {
    if (self.selectedCanonicalName.length == 0)
        return NO;
    if ([item.identifier isEqualToString:self.selectedIconName])
        return YES;
    return [[[self class] canonicalNameForIconName:item.identifier] isEqualToString:self.selectedCanonicalName];
}

- (void)didSelectItem:(SPKIconPickerItem *)item {
    self.selectedIconName = item.identifier;
    self.selectedCanonicalName = [[self class] canonicalNameForIconName:item.identifier];
    if (self.onSelect)
        self.onSelect(item.identifier);
    [self refreshSelectionHighlight];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
