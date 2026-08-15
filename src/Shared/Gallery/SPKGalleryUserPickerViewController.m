#import "SPKGalleryUserPickerViewController.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#include <UIKit/UIKit.h>

@interface SPKGalleryUserPickerViewController () <UISearchResultsUpdating, UISearchBarDelegate>
// All usernames, sorted alphabetically.
@property (nonatomic, copy) NSArray<NSString *> *allUsernames;
// Current selection (stored verbatim; membership tested case-insensitively).
@property (nonatomic, strong) NSMutableSet<NSString *> *selected;

// A–Z sectioning (used when not searching).
@property (nonatomic, copy) NSArray<NSString *> *sectionTitles;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSString *> *> *sectionedUsers;

// Search state.
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, copy) NSArray<NSString *> *filteredUsernames;
@property (nonatomic, strong) UIBarButtonItem *clearItem;
@end

@implementation SPKGalleryUserPickerViewController

- (instancetype)initWithUsernames:(NSArray<NSString *> *)usernames selected:(NSSet<NSString *> *)selected {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _allUsernames = [usernames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        _selected = [NSMutableSet setWithSet:selected ?: [NSSet set]];
        [self rebuildSections];
    }
    return self;
}

- (NSSet<NSString *> *)selectedUsernames {
    return [self.selected copy];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.sectionIndexColor = [SPKUtils SPKColor_InstagramBlue];
    self.tableView.sectionIndexBackgroundColor = [UIColor clearColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"user"];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.placeholder = @"搜索用户";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"check" pointSize:24.0]
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(dismissPicker)];
    done.tintColor = [SPKUtils SPKColor_InstagramBlue];
    done.accessibilityLabel = @"完成";
    self.navigationItem.rightBarButtonItem = done;

    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"backspace" pointSize:24.0]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(clearSelection)];
    clear.accessibilityLabel = @"清除选择";
    self.clearItem = clear;
    self.navigationItem.leftBarButtonItem = clear;

    [self updateChrome];
}

- (void)dismissPicker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Data

- (void)rebuildSections {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *buckets = [NSMutableDictionary dictionary];
    for (NSString *username in self.allUsernames) {
        NSString *key = [self sectionKeyForUsername:username];
        NSMutableArray<NSString *> *bucket = buckets[key];
        if (!bucket) {
            bucket = [NSMutableArray array];
            buckets[key] = bucket;
            [titles addObject:key];
        }
        [bucket addObject:username];
    }
    // "#" (non-letter) sorts after the alphabet.
    [titles sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if ([a isEqualToString:@"#"])
            return NSOrderedDescending;
        if ([b isEqualToString:@"#"])
            return NSOrderedAscending;
        return [a compare:b];
    }];
    self.sectionTitles = titles;
    self.sectionedUsers = buckets;
}

- (NSString *)sectionKeyForUsername:(NSString *)username {
    if (username.length == 0)
        return @"#";
    NSString *first = [[username substringToIndex:1] uppercaseString];
    unichar c = [first characterAtIndex:0];
    if (c >= 'A' && c <= 'Z')
        return first;
    return @"#";
}

- (BOOL)isSearching {
    return self.searchQuery.length > 0;
}

- (NSString *)usernameAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isSearching]) {
        return indexPath.row < (NSInteger)self.filteredUsernames.count ? self.filteredUsernames[indexPath.row] : nil;
    }
    NSString *title = self.sectionTitles[indexPath.section];
    NSArray<NSString *> *bucket = self.sectionedUsers[title];
    return indexPath.row < (NSInteger)bucket.count ? bucket[indexPath.row] : nil;
}

- (BOOL)isUsernameSelected:(NSString *)username {
    if (username.length == 0)
        return NO;
    for (NSString *selected in self.selected) {
        if ([selected caseInsensitiveCompare:username] == NSOrderedSame)
            return YES;
    }
    return NO;
}

- (void)toggleUsername:(NSString *)username {
    if (username.length == 0)
        return;
    NSString *existing = nil;
    for (NSString *selected in self.selected) {
        if ([selected caseInsensitiveCompare:username] == NSOrderedSame) {
            existing = selected;
            break;
        }
    }
    if (existing) {
        [self.selected removeObject:existing];
    } else {
        [self.selected addObject:username];
    }
    [self notifySelectionChanged];
}

- (void)notifySelectionChanged {
    [self updateChrome];
    if (self.selectionChanged) {
        self.selectionChanged([self.selected copy]);
    }
}

- (void)updateChrome {
    NSUInteger count = self.selected.count;
    self.title = count > 0 ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)count] : @"Select Users";
    // Clear stays on the left (checkmark is on the right) but greys out when there
    // is nothing to clear.
    self.clearItem.enabled = count > 0;
}

- (void)clearSelection {
    if (self.selected.count == 0)
        return;
    [self.selected removeAllObjects];
    [self notifySelectionChanged];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self isSearching] ? 1 : (NSInteger)self.sectionTitles.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isSearching]) {
        return (NSInteger)self.filteredUsernames.count;
    }
    NSString *title = self.sectionTitles[section];
    return (NSInteger)self.sectionedUsers[title].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self isSearching])
        return nil;
    return self.sectionTitles[section];
}

- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return [self isSearching] ? nil : self.sectionTitles;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"user" forIndexPath:indexPath];
    NSString *username = [self usernameAtIndexPath:indexPath];
    cell.textLabel.text = username ?: @"";
    cell.textLabel.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    cell.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [self applySelectionAccessoryToCell:cell selected:[self isUsernameSelected:username]];
    return cell;
}

// Trailing two-tone circle that fills in when selected, matching the gallery's
// selection iconography.
- (void)applySelectionAccessoryToCell:(UITableViewCell *)cell selected:(BOOL)selected {
    UIImageView *iconView = [cell.accessoryView isKindOfClass:[UIImageView class]]
                                ? (UIImageView *)cell.accessoryView
                                : nil;
    if (!iconView) {
        iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, 24.0, 24.0)];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        cell.accessoryView = iconView;
    }
    iconView.image = [SPKAssetUtils instagramIconNamed:(selected ? @"circle_check_filled" : @"circle") pointSize:24.0];
    // Same tint whether empty or filled — the shape conveys selection, not color.
    iconView.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NSString *username = [self usernameAtIndexPath:indexPath];
    [self toggleUsername:username];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [self applySelectionAccessoryToCell:cell selected:[self isUsernameSelected:username]];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.searchQuery = query;
    if (query.length > 0) {
        self.filteredUsernames = [self.allUsernames filteredArrayUsingPredicate:
                                                        [NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] %@", query]];
    } else {
        self.filteredUsernames = @[];
    }
    [self.tableView reloadData];
}

@end
