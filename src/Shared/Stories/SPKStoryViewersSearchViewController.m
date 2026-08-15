#import "SPKStoryViewersSearchViewController.h"

#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../Avatars/SPKAvatarView.h"
#import "../UI/SPKChipBar.h"
#import "../UI/SPKMediaChrome.h"
#import "SPKStoryViewersFetcher.h"

static CGFloat const kSPKViewerAvatarSize = 52.0;

typedef NS_ENUM(NSInteger, SPKViewerFilter) {
    SPKViewerFilterAll = 0,
    SPKViewerFilterFollowing,
    SPKViewerFilterNotFollowing,
};

#pragma mark - Cell

@interface SPKStoryViewerCell : UITableViewCell
@property (nonatomic, strong) SPKAvatarView *avatarView;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadge;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *relationshipLabel;
@end

@implementation SPKStoryViewerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self)
        return self;
    self.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    self.selectedBackgroundView = [UIView new];
    self.selectedBackgroundView.backgroundColor = [SPKUtils SPKColor_ListRowPressedOverlay];

    _avatarView = [[SPKAvatarView alloc] initWithFrame:CGRectZero];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_avatarView];

    _usernameLabel = [UILabel new];
    _usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _usernameLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    _usernameLabel.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    [_usernameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _verifiedBadge = [UIImageView new];
    _verifiedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _verifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
    _verifiedBadge.image = [SPKAssetUtils instagramIconNamed:@"verified" pointSize:13.0];
    _verifiedBadge.hidden = YES;
    [_verifiedBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[ _usernameLabel, _verifiedBadge ]];
    nameRow.translatesAutoresizingMaskIntoConstraints = NO;
    nameRow.axis = UILayoutConstraintAxisHorizontal;
    nameRow.alignment = UIStackViewAlignmentCenter;
    nameRow.spacing = 4.0;
    [self.contentView addSubview:nameRow];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    _subtitleLabel.numberOfLines = 1;
    [self.contentView addSubview:_subtitleLabel];

    _relationshipLabel = [UILabel new];
    _relationshipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _relationshipLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    _relationshipLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    _relationshipLabel.textAlignment = NSTextAlignmentRight;
    [_relationshipLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_relationshipLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_relationshipLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_avatarView.widthAnchor constraintEqualToConstant:kSPKViewerAvatarSize],
        [_avatarView.heightAnchor constraintEqualToConstant:kSPKViewerAvatarSize],

        [nameRow.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12.0],
        [nameRow.topAnchor constraintEqualToAnchor:_avatarView.topAnchor constant:4.0],
        [nameRow.trailingAnchor constraintLessThanOrEqualToAnchor:_relationshipLabel.leadingAnchor constant:-10.0],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:nameRow.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:nameRow.bottomAnchor constant:3.0],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_relationshipLabel.leadingAnchor constant:-10.0],

        [_relationshipLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        [_relationshipLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    ]];
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.avatarView prepareForReuse];
    self.verifiedBadge.hidden = YES;
    self.relationshipLabel.text = nil;
}

@end

#pragma mark - VC

@interface SPKStoryViewersSearchViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, SPKChipBarDelegate>
@property (nonatomic, copy) NSString *mediaID;
@property (nonatomic, strong) SPKStoryViewersFetcher *fetcher;

@property (nonatomic, copy) NSArray<SPKStoryViewerModel *> *allViewers;
@property (nonatomic, copy) NSArray<SPKStoryViewerModel *> *shownViewers;
@property (nonatomic, assign) NSInteger totalCount;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL friendshipAvailable;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) SPKChipBar *filterChips;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UILabel *countLabel;

@property (nonatomic, strong) UIView *loadingOverlay;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, strong) UILabel *loadingLabel;

@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyStateIcon;
@property (nonatomic, strong) UILabel *emptyStateTitle;
@property (nonatomic, strong) UILabel *emptyStateSubtitle;

@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, assign) SPKViewerFilter filter;
@end

@implementation SPKStoryViewersSearchViewController

- (instancetype)initWithMediaID:(NSString *)mediaID title:(NSString *)title {
    if ((self = [super init])) {
        _mediaID = [mediaID copy];
        self.title = title.length ? title : @"快拍观看者";
        _filter = SPKViewerFilterAll;
    }
    return self;
}

+ (void)presentForMediaID:(NSString *)mediaID title:(NSString *)title {
    if (mediaID.length == 0)
        return;
    UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (root.presentedViewController)
        root = root.presentedViewController;
    SPKStoryViewersSearchViewController *vc = [[SPKStoryViewersSearchViewController alloc] initWithMediaID:mediaID title:title];
    UINavigationController *nav = [[SPKChromeNavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [root presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramBackground];

    SPKMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ SPKMediaChromeTopBarButtonItem(@"xmark", self, @selector(closeTapped)) ]);

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    self.tableView.separatorColor = [SPKUtils SPKColor_InstagramSeparator];
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 80.0, 0.0, 0.0);
    self.tableView.rowHeight = 72.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:[SPKStoryViewerCell class] forCellReuseIdentifier:@"v"];
    [self.view addSubview:self.tableView];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索观看者";
    [self.searchController.searchBar setImage:[SPKAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                             forSearchBarIcon:UISearchBarIconSearch
                                        state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [self buildTableHeader];
    [self setupLoadingOverlay];
    [self setupEmptyState];

    [self startFetch];
}

- (void)dealloc {
    [_fetcher cancel];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Header (filter + count)

- (void)buildTableHeader {
    self.headerContainer = [UIView new];
    self.headerContainer.backgroundColor = [SPKUtils SPKColor_InstagramBackground];

    self.filterChips = [[SPKChipBar alloc] init];
    self.filterChips.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterChips.delegate = self;
    // Fill the whole bar, each chip sized to its label (so "Not Following" gets a
    // wider chip) at full font — rather than equal thirds that shrink/truncate it.
    self.filterChips.distributesProportionally = YES;
    [self.filterChips setItems:@[ @"All", @"Following", @"Not Following" ]
                       symbols:@[ @"users", @"user_following", @"user_unfollow" ]];
    self.filterChips.selectedIndex = 0;
    [self.headerContainer addSubview:self.filterChips];

    self.countLabel = [UILabel new];
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.countLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    self.countLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    [self.headerContainer addSubview:self.countLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.filterChips.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor constant:0.0],
        [self.filterChips.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor constant:0.0],
        [self.filterChips.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor constant:0.0],

        [self.countLabel.topAnchor constraintEqualToAnchor:self.filterChips.bottomAnchor constant:10.0],
        [self.countLabel.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor constant:16.0],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor constant:-16.0],
        [self.countLabel.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor constant:-8.0],
    ]];
}

// The filter is only meaningful once we have follow relationships; hidden
// entirely when the response never carried them.
- (void)layoutTableHeader {
    CGFloat w = self.tableView.bounds.size.width;
    if (w < 1)
        return;
    BOOL showFilter = self.friendshipAvailable;
    self.filterChips.hidden = !showFilter;
    self.headerContainer.frame = CGRectMake(0, 0, w, 1);
    [self.headerContainer setNeedsLayout];
    [self.headerContainer layoutIfNeeded];
    CGFloat h = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height)
                                   withHorizontalFittingPriority:UILayoutPriorityRequired
                                         verticalFittingPriority:UILayoutPriorityFittingSizeLevel]
                    .height;
    CGRect target = CGRectMake(0, 0, w, h);
    if (!CGRectEqualToRect(self.headerContainer.frame, target) || self.tableView.tableHeaderView != self.headerContainer) {
        self.headerContainer.frame = target;
        self.tableView.tableHeaderView = self.headerContainer;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutTableHeader];
}

- (void)chipBar:(SPKChipBar *)bar didSelectIndex:(NSInteger)index {
    self.filter = (SPKViewerFilter)index;
    [self applyFilter];
}

#pragma mark - Fetch

- (void)startFetch {
    self.loading = YES;
    [self updateLoadingUI];
    __weak typeof(self) weakSelf = self;
    self.fetcher = [SPKStoryViewersFetcher fetchAllViewersForMediaID:self.mediaID
        progress:^(NSInteger fetched) {
            typeof(self) self = weakSelf;
            if (!self)
                return;
            self.loadingLabel.text = [NSString stringWithFormat:@"Loading viewers... %ld", (long)fetched];
        }
        completion:^(NSArray<SPKStoryViewerModel *> *viewers, NSInteger totalCount, NSError *error) {
            typeof(self) self = weakSelf;
            if (!self)
                return;
            self.loading = NO;
            self.allViewers = viewers;
            self.totalCount = totalCount;
            for (SPKStoryViewerModel *v in viewers) {
                if (v.friendshipKnown) {
                    self.friendshipAvailable = YES;
                    break;
                }
            }
            [self updateLoadingUI];
            [self applyFilter];
            [self.view setNeedsLayout];
            if (error && viewers.count == 0) {
                self.emptyStateTitle.text = @"Couldn't load viewers";
                self.emptyStateSubtitle.text = error.localizedDescription ?: @"Please try again.";
            }
        }];
}

#pragma mark - Filter

- (void)applyFilter {
    NSString *q = self.searchText.lowercaseString;
    BOOL hasQuery = q.length > 0;
    NSMutableArray *out = [NSMutableArray array];
    for (SPKStoryViewerModel *v in self.allViewers) {
        if (self.friendshipAvailable && v.friendshipKnown) {
            if (self.filter == SPKViewerFilterFollowing && !v.following)
                continue;
            if (self.filter == SPKViewerFilterNotFollowing && v.following)
                continue;
        }
        if (hasQuery) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@", v.username ?: @"", v.fullName ?: @""].lowercaseString;
            if (![hay containsString:q])
                continue;
        }
        [out addObject:v];
    }
    self.shownViewers = out;
    [self.tableView reloadData];
    [self updateCountLabel];
    [self updateEmptyState];
}

- (void)updateCountLabel {
    if (self.loading) {
        self.countLabel.text = @"";
        return;
    }
    NSInteger shown = self.shownViewers.count;
    NSInteger total = MAX(self.totalCount, (NSInteger)self.allViewers.count);
    if (self.searchText.length || (self.friendshipAvailable && self.filter != SPKViewerFilterAll)) {
        self.countLabel.text = [NSString stringWithFormat:@"%ld of %ld viewers", (long)shown, (long)total];
    } else {
        self.countLabel.text = total == 1 ? @"1 viewer" : [NSString stringWithFormat:@"%ld viewers", (long)total];
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchText = searchController.searchBar.text;
    [self applyFilter];
}

#pragma mark - Loading overlay

- (void)setupLoadingOverlay {
    self.loadingOverlay = [UIView new];
    self.loadingOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingOverlay.hidden = YES;
    [self.view addSubview:self.loadingOverlay];

    self.loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingSpinner.color = [SPKUtils SPKColor_InstagramSecondaryText];
    [self.loadingSpinner startAnimating];
    [self.loadingOverlay addSubview:self.loadingSpinner];

    self.loadingLabel = [UILabel new];
    self.loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.loadingLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.loadingLabel.textAlignment = NSTextAlignmentCenter;
    self.loadingLabel.text = @"Loading viewers...";
    [self.loadingOverlay addSubview:self.loadingLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.loadingOverlay.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingOverlay.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30.0],

        [self.loadingSpinner.topAnchor constraintEqualToAnchor:self.loadingOverlay.topAnchor],
        [self.loadingSpinner.centerXAnchor constraintEqualToAnchor:self.loadingOverlay.centerXAnchor],

        [self.loadingLabel.topAnchor constraintEqualToAnchor:self.loadingSpinner.bottomAnchor constant:12.0],
        [self.loadingLabel.leadingAnchor constraintEqualToAnchor:self.loadingOverlay.leadingAnchor],
        [self.loadingLabel.trailingAnchor constraintEqualToAnchor:self.loadingOverlay.trailingAnchor],
        [self.loadingLabel.bottomAnchor constraintEqualToAnchor:self.loadingOverlay.bottomAnchor],
        [self.loadingOverlay.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40.0],
        [self.loadingOverlay.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40.0],
    ]];
}

- (void)updateLoadingUI {
    self.loadingOverlay.hidden = !self.loading;
    if (self.loading) {
        [self.loadingSpinner startAnimating];
        self.tableView.hidden = YES;
    } else {
        [self.loadingSpinner stopAnimating];
        self.tableView.hidden = NO;
    }
}

#pragma mark - Empty state

- (void)setupEmptyState {
    self.emptyStateView = [UIView new];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.hidden = YES;
    [self.view addSubview:self.emptyStateView];

    self.emptyStateIcon = [[UIImageView alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"users_empty" pointSize:96.0 renderingMode:UIImageRenderingModeAlwaysTemplate]];
    self.emptyStateIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.emptyStateIcon.tintColor = [SPKUtils SPKColor_InstagramTertiaryText];
    [self.emptyStateView addSubview:self.emptyStateIcon];

    self.emptyStateTitle = [UILabel new];
    self.emptyStateTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateTitle.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    self.emptyStateTitle.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    self.emptyStateTitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateTitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateTitle];

    self.emptyStateSubtitle = [UILabel new];
    self.emptyStateSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateSubtitle.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.emptyStateSubtitle.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.emptyStateSubtitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateSubtitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateSubtitle];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20.0],
        [self.emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40.0],
        [self.emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40.0],

        [self.emptyStateIcon.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor],
        [self.emptyStateIcon.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [self.emptyStateIcon.widthAnchor constraintEqualToConstant:96.0],
        [self.emptyStateIcon.heightAnchor constraintEqualToConstant:96.0],

        [self.emptyStateTitle.topAnchor constraintEqualToAnchor:self.emptyStateIcon.bottomAnchor constant:18.0],
        [self.emptyStateTitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateTitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],

        [self.emptyStateSubtitle.topAnchor constraintEqualToAnchor:self.emptyStateTitle.bottomAnchor constant:6.0],
        [self.emptyStateSubtitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateSubtitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],
        [self.emptyStateSubtitle.bottomAnchor constraintEqualToAnchor:self.emptyStateView.bottomAnchor],
    ]];
}

- (void)updateEmptyState {
    if (self.loading) {
        self.emptyStateView.hidden = YES;
        return;
    }
    BOOL isEmpty = self.shownViewers.count == 0;
    self.emptyStateView.hidden = !isEmpty;
    if (!isEmpty)
        return;
    // A load failure sets its own copy in the completion handler; don't clobber it.
    if ([self.emptyStateTitle.text isEqualToString:@"Couldn't load viewers"])
        return;
    self.emptyStateIcon.image = [SPKAssetUtils instagramIconNamed:@"users_empty" pointSize:96.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
    if (self.searchText.length || (self.friendshipAvailable && self.filter != SPKViewerFilterAll)) {
        self.emptyStateTitle.text = @"No matches";
        self.emptyStateSubtitle.text = @"No viewers match your search.";
    } else {
        self.emptyStateTitle.text = @"No viewers yet";
        self.emptyStateSubtitle.text = @"No one has viewed this story.";
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.shownViewers.count;
}

- (NSString *)relationshipTextFor:(SPKStoryViewerModel *)v {
    if (!v.friendshipKnown)
        return nil;
    if (v.following && v.followedBy)
        return @"Mutual";
    if (v.following)
        return @"Following";
    if (v.followedBy)
        return @"Follows you";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPKStoryViewerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"v" forIndexPath:indexPath];
    SPKStoryViewerModel *v = self.shownViewers[indexPath.row];
    cell.usernameLabel.text = v.username.length ? [@"@" stringByAppendingString:v.username] : @"Unknown user";
    cell.subtitleLabel.text = v.fullName.length ? v.fullName : @"";
    cell.subtitleLabel.hidden = v.fullName.length == 0;
    cell.verifiedBadge.hidden = !v.isVerified;
    cell.relationshipLabel.text = [self relationshipTextFor:v];
    [cell.avatarView configureWithPK:v.pk urlString:v.profilePicURL];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SPKStoryViewerModel *v = self.shownViewers[indexPath.row];
    // The viewer list endpoint already gave us the pk; opening by username alone
    // would throw it away and resolve it again over the network.
    if (v.pk.length || v.username.length)
        [SPKUtils openInstagramProfileForUser:nil pk:v.pk username:v.username fromViewController:self];
}

@end
