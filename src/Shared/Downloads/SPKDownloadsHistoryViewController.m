#import "SPKDownloadsHistoryViewController.h"

#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../Account/SPKAccountManager.h"
#import "../Gallery/SPKGallerySaveMetadata.h"
#import "../Gallery/SPKGalleryViewController.h"
#import "../MediaPreview/SPKFullScreenMediaPlayer.h"
#import "../MediaPreview/SPKMediaItem.h"
#import "../UI/SPKChipBar.h"
#import "../UI/SPKIGAlertPresenter.h"
#import "../UI/SPKMediaChrome.h"
#import "SPKDownloadService.h"
#import "SPKDownloadTypes.h"
#import "SPKDownloadsSettingsViewController.h"
#import <AVFoundation/AVFoundation.h>

#pragma mark - Helpers

static NSString *SPKDownloadHistoryDisplayUsername(NSString *username) {
    NSString *trimmed = [username stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > 30)
        return nil;
    NSString *lower = trimmed.lowercaseString;
    NSSet<NSString *> *blocked = [NSSet setWithArray:@[
        @"more", @"options", @"menu", @"close", @"done", @"cancel", @"all",
        @"active", @"queued", @"failed", @"completed", @"clipboard", @"download",
        @"save", @"share", @"copy", @"gallery", @"photos", @"instants"
    ]];
    if ([blocked containsObject:lower])
        return nil;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"] invertedSet];
    return [trimmed rangeOfCharacterFromSet:invalid].location == NSNotFound ? trimmed : nil;
}

static NSString *SPKDownloadHistoryDateString(NSTimeInterval timestamp) {
    if (timestamp <= 0)
        return @"";
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MMM d 'at' h:mm a";
    });
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

#pragma mark - Row model

typedef NS_ENUM(NSUInteger, SPKDownloadsHistoryRowKind) {
    SPKDownloadsHistoryRowKindJob,
    SPKDownloadsHistoryRowKindChild,
};

@interface SPKDownloadsHistoryRow : NSObject
@property (nonatomic, assign) SPKDownloadsHistoryRowKind kind;
@property (nonatomic, strong) SPKDownloadJob *job;
@property (nonatomic, strong, nullable) SPKDownloadItem *item;
@property (nonatomic, assign) BOOL expanded;
@end
@implementation SPKDownloadsHistoryRow
@end

#pragma mark - Cell

@interface SPKDownloadHistoryCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIImageView *statusBadge;
@property (nonatomic, strong) UIImageView *rowTypeIcon;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIView *highlightOverlay;
@property (nonatomic, strong) UIView *separatorLine;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *technicalLabel;
@property (nonatomic, strong) UIView *pillBackground;
@property (nonatomic, strong) UILabel *pillLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *compactStatusIcon;
@property (nonatomic, strong) UILabel *compactLabel;
@property (nonatomic, strong) NSLayoutConstraint *thumbLeading;
@property (nonatomic, strong) NSLayoutConstraint *rowTypeIconWidth;
@property (nonatomic, strong) NSLayoutConstraint *separatorLeading;
@property (nonatomic, copy, nullable) NSString *representedID;
@end

@implementation SPKDownloadHistoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
        self.contentView.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        // Highlight overlay (manual — avoids separator jump that UIKit selection causes)
        _highlightOverlay = [UIView new];
        _highlightOverlay.translatesAutoresizingMaskIntoConstraints = NO;
        _highlightOverlay.backgroundColor = [SPKUtils SPKColor_ListRowPressedOverlay];
        _highlightOverlay.hidden = YES;
        [self.contentView addSubview:_highlightOverlay];
        [NSLayoutConstraint activateConstraints:@[
            [_highlightOverlay.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_highlightOverlay.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_highlightOverlay.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_highlightOverlay.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        ]];

        // Custom separator line (avoids the jump issue with system separators)
        _separatorLine = [UIView new];
        _separatorLine.translatesAutoresizingMaskIntoConstraints = NO;
        _separatorLine.backgroundColor = [SPKUtils SPKColor_InstagramSeparator];
        [self.contentView addSubview:_separatorLine];
        _separatorLeading = [_separatorLine.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:80];
        [NSLayoutConstraint activateConstraints:@[
            _separatorLeading,
            [_separatorLine.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_separatorLine.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_separatorLine.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        ]];

        // Thumbnail 52x52, rounded
        _thumbnailView = [UIImageView new];
        _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailView.clipsToBounds = YES;
        _thumbnailView.layer.cornerRadius = 6;
        _thumbnailView.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];
        [self.contentView addSubview:_thumbnailView];

        // Status badge (bottom-right of thumbnail)
        _statusBadge = [UIImageView new];
        _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _statusBadge.contentMode = UIViewContentModeScaleAspectFit;
        _statusBadge.hidden = YES;
        [self.contentView addSubview:_statusBadge];

        // Title
        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        // Media type icon (14x14 in the technical row)
        _rowTypeIcon = [UIImageView new];
        _rowTypeIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _rowTypeIcon.contentMode = UIViewContentModeScaleAspectFit;
        _rowTypeIcon.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
        [self.contentView addSubview:_rowTypeIcon];

        // Technical label
        _technicalLabel = [UILabel new];
        _technicalLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _technicalLabel.font = [UIFont systemFontOfSize:12];
        _technicalLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
        _technicalLabel.numberOfLines = 1;
        _technicalLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_technicalLabel];

        // Pill
        _pillBackground = [UIView new];
        _pillBackground.translatesAutoresizingMaskIntoConstraints = NO;
        _pillBackground.backgroundColor = [SPKUtils SPKColor_InstagramTertiaryBackground];
        _pillBackground.layer.cornerRadius = 5;
        _pillBackground.clipsToBounds = YES;
        [self.contentView addSubview:_pillBackground];

        _pillLabel = [UILabel new];
        _pillLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _pillLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _pillLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
        _pillLabel.numberOfLines = 1;
        [_pillBackground addSubview:_pillLabel];

        // Date label
        _dateLabel = [UILabel new];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.font = [UIFont systemFontOfSize:11];
        _dateLabel.textColor = [SPKUtils SPKColor_InstagramTertiaryText];
        _dateLabel.numberOfLines = 1;
        _dateLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_dateLabel];

        _thumbLeading = [_thumbnailView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16];
        _rowTypeIconWidth = [_rowTypeIcon.widthAnchor constraintEqualToConstant:14];

        [NSLayoutConstraint activateConstraints:@[
            _thumbLeading,
            [_thumbnailView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_thumbnailView.widthAnchor constraintEqualToConstant:52],
            [_thumbnailView.heightAnchor constraintEqualToConstant:52],

            [_statusBadge.trailingAnchor constraintEqualToAnchor:_thumbnailView.trailingAnchor
                                                        constant:3],
            [_statusBadge.bottomAnchor constraintEqualToAnchor:_thumbnailView.bottomAnchor
                                                      constant:3],
            [_statusBadge.widthAnchor constraintEqualToConstant:16],
            [_statusBadge.heightAnchor constraintEqualToConstant:16],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_thumbnailView.trailingAnchor
                                                      constant:12],
            [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailView.topAnchor
                                                  constant:-1],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                                 constant:-16],

            [_rowTypeIcon.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_rowTypeIcon.centerYAnchor constraintEqualToAnchor:_technicalLabel.centerYAnchor],
            _rowTypeIconWidth,
            [_rowTypeIcon.heightAnchor constraintEqualToConstant:14],

            [_technicalLabel.leadingAnchor constraintEqualToAnchor:_rowTypeIcon.trailingAnchor
                                                          constant:4],
            [_technicalLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                                      constant:3],
            [_technicalLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                                     constant:-16],
            [_technicalLabel.heightAnchor constraintGreaterThanOrEqualToConstant:14],

            [_pillBackground.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_pillBackground.topAnchor constraintEqualToAnchor:_technicalLabel.bottomAnchor
                                                      constant:4],
            [_pillLabel.leadingAnchor constraintEqualToAnchor:_pillBackground.leadingAnchor
                                                     constant:8],
            [_pillLabel.trailingAnchor constraintEqualToAnchor:_pillBackground.trailingAnchor
                                                      constant:-8],
            [_pillLabel.topAnchor constraintEqualToAnchor:_pillBackground.topAnchor
                                                 constant:3],
            [_pillLabel.bottomAnchor constraintEqualToAnchor:_pillBackground.bottomAnchor
                                                    constant:-3],

            [_dateLabel.leadingAnchor constraintEqualToAnchor:_pillBackground.trailingAnchor
                                                     constant:8],
            [_dateLabel.centerYAnchor constraintEqualToAnchor:_pillBackground.centerYAnchor],
            [_dateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                                constant:-36],
        ]];

        // Chevron (custom, not accessoryView — avoids selection color bleed)
        _chevronView = [UIImageView new];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        _chevronView.tintColor = [SPKUtils SPKColor_InstagramTertiaryText];
        _chevronView.hidden = YES;
        [self.contentView addSubview:_chevronView];
        [NSLayoutConstraint activateConstraints:@[
            [_chevronView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                        constant:-16],
            [_chevronView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:12],
            [_chevronView.heightAnchor constraintEqualToConstant:12],
        ]];

        // Compact child layout: a small status icon + single metadata line, both
        // vertically centered. Independent of the parent layout (which anchors the
        // title to the thumbnail top and breaks at short row heights).
        _compactStatusIcon = [UIImageView new];
        _compactStatusIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _compactStatusIcon.contentMode = UIViewContentModeScaleAspectFit;
        _compactStatusIcon.hidden = YES;
        [self.contentView addSubview:_compactStatusIcon];

        _compactLabel = [UILabel new];
        _compactLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _compactLabel.font = [UIFont systemFontOfSize:13];
        _compactLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
        _compactLabel.numberOfLines = 1;
        _compactLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _compactLabel.hidden = YES;
        [self.contentView addSubview:_compactLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_compactStatusIcon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                             constant:40],
            [_compactStatusIcon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_compactStatusIcon.widthAnchor constraintEqualToConstant:16],
            [_compactStatusIcon.heightAnchor constraintEqualToConstant:16],

            [_compactLabel.leadingAnchor constraintEqualToAnchor:_compactStatusIcon.trailingAnchor
                                                        constant:10],
            [_compactLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_compactLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                                   constant:-16],
        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (animated) {
        [UIView animateWithDuration:highlighted ? 0.05 : 0.3
                         animations:^{
                             self.highlightOverlay.hidden = !highlighted;
                         }];
    } else {
        self.highlightOverlay.hidden = !highlighted;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.highlightOverlay.hidden = YES;
    self.thumbnailView.image = nil;
    self.thumbnailView.tintColor = nil;
    self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbnailView.hidden = NO;
    self.thumbnailView.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];
    self.thumbnailView.layer.cornerRadius = 6;
    self.statusBadge.image = nil;
    self.statusBadge.hidden = YES;
    self.rowTypeIcon.image = nil;
    self.rowTypeIcon.hidden = NO;
    self.rowTypeIconWidth.constant = 14;
    self.titleLabel.text = nil;
    self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    self.technicalLabel.text = nil;
    self.pillLabel.text = nil;
    self.pillBackground.hidden = NO;
    self.dateLabel.text = nil;
    self.dateLabel.hidden = NO;
    self.thumbLeading.constant = 16;
    self.chevronView.hidden = YES;
    self.chevronView.transform = CGAffineTransformIdentity;
    self.compactStatusIcon.hidden = YES;
    self.compactStatusIcon.image = nil;
    self.compactLabel.hidden = YES;
    self.compactLabel.text = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.representedID = nil;
}

@end

#pragma mark - View Controller

@interface SPKDownloadsHistoryViewController () <UITableViewDelegate, UITableViewDataSource, SPKChipBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SPKChipBar *chipBar;
@property (nonatomic, copy) NSArray<SPKDownloadsHistoryRow *> *rows;
@property (nonatomic, strong) NSMutableSet<NSString *> *expandedJobIDs;
@property (nonatomic, assign) BOOL swipeInProgress;

@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyStateIcon;
@property (nonatomic, strong) UILabel *emptyStateTitle;
@property (nonatomic, strong) UILabel *emptyStateSubtitle;

@property (nonatomic, assign) BOOL lastHasHiddenPill;
@property (nonatomic, assign) BOOL lastHasActiveJobs;
@property (nonatomic, assign) BOOL hasSetInitialTopBarStates;
@end

@implementation SPKDownloadsHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"下载";
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.expandedJobIDs = [NSMutableSet set];

    // Chrome
    [self updateTopBarItems];
    if (self.navigationController.viewControllers.firstObject == self) {
        SPKMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ SPKMediaChromeTopBarButtonItem(@"xmark", self, @selector(close)) ]);
    }

    // Chip bar
    self.chipBar = [[SPKChipBar alloc] initWithFrame:CGRectZero];
    self.chipBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipBar.delegate = self;
    [self.chipBar setItems:@[ @"全部", @"进行中", @"排队中", @"失败", @"最近" ]
                   symbols:@[ @"download", @"play", @"clock", @"error", @"circle_check" ]
           selectedSymbols:@[ @"download_filled", @"play_filled", @"clock_filled", @"error_filled", @"circle_check_filled" ]];
    self.chipBar.selectedIndex = 0;
    [self.view addSubview:self.chipBar];

    // Table
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[SPKDownloadHistoryCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];

    [self setupEmptyState];

    [NSLayoutConstraint activateConstraints:@[
        [self.chipBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.chipBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipBar.heightAnchor constraintEqualToConstant:50],

        [self.tableView.topAnchor constraintEqualToAnchor:self.chipBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serviceDidChange) name:SPKDownloadServiceDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:SPKAccountDidChangeNotification object:nil];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = NO;
        SPKApplyMediaChromeNavigationBar(self.navigationController.navigationBar);
    }
    // Catch an in-app account switch that didn't fire while this view was up.
    [[SPKAccountManager shared] refreshCurrentAccount];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Reload (swipe-safe)

- (void)serviceDidChange {
    // Skip full reloads while the user is swiping a row — this prevents
    // the swipe action from snapping back during an active download.
    if (self.swipeInProgress)
        return;
    [self reload];
}

- (void)reload {
    SPKDownloadHistoryFilter filter = [self currentFilter];
    NSArray<SPKDownloadJob *> *jobs = [[SPKDownloadService shared] jobsMatchingFilter:filter];

    // Per-account scope: when per-account settings are on, show only the current
    // account's downloads (plus legacy/unstamped jobs so existing history isn't
    // hidden). A job keeps the account that started it, regardless of switches.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSPKPrefPerAccountSettings]) {
        NSString *pk = [SPKAccountManager currentAccountPK];
        if (pk.length > 0) {
            jobs = [jobs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SPKDownloadJob *job, NSDictionary *bindings) {
                             return job.ownerAccountPK.length == 0 || [job.ownerAccountPK isEqualToString:pk];
                         }]];
        }
    }

    NSMutableArray *rows = [NSMutableArray array];
    for (SPKDownloadJob *job in jobs) {
        SPKDownloadsHistoryRow *parent = [SPKDownloadsHistoryRow new];
        parent.kind = SPKDownloadsHistoryRowKindJob;
        parent.job = job;
        parent.expanded = [self.expandedJobIDs containsObject:job.jobID];
        [rows addObject:parent];
        if (job.items.count > 1 && parent.expanded) {
            for (SPKDownloadItem *item in job.items) {
                SPKDownloadsHistoryRow *child = [SPKDownloadsHistoryRow new];
                child.kind = SPKDownloadsHistoryRowKindChild;
                child.job = job;
                child.item = item;
                [rows addObject:child];
            }
        }
    }
    self.rows = rows;
    [self.tableView reloadData];
    [self updateEmptyState];
    [self updateTopBarItems];
}

- (void)updateTopBarItems {
    BOOL hasHiddenPill = [[SPKDownloadService shared] hasActiveJobWithHiddenPill];

    BOOL hasActiveJobs = NO;
    for (SPKDownloadJob *job in [[SPKDownloadService shared] jobsMatchingFilter:SPKDownloadHistoryFilterAll]) {
        if (job.state == SPKDownloadStateRunning || job.state == SPKDownloadStateQueued || job.state == SPKDownloadStatePending) {
            hasActiveJobs = YES;
            break;
        }
    }

    if (self.hasSetInitialTopBarStates &&
        hasHiddenPill == self.lastHasHiddenPill &&
        hasActiveJobs == self.lastHasActiveJobs) {
        return;
    }

    self.lastHasHiddenPill = hasHiddenPill;
    self.lastHasActiveJobs = hasActiveJobs;
    self.hasSetInitialTopBarStates = YES;

    UIMenu *menu = [self moreMenu];
    UIBarButtonItem *moreItem = SPKMediaChromeTopBarMenuButtonItem(@"more", menu, @"更多");
    UIBarButtonItem *settingsItem = SPKMediaChromeTopBarButtonItem(@"settings", self, @selector(pushSettings));
    if (hasHiddenPill) {
        UIBarButtonItem *showProgressItem = SPKMediaChromeTopBarButtonItem(@"play_filled", self, @selector(showProgressTapped));
        SPKMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ showProgressItem, settingsItem, moreItem ]);
    } else {
        SPKMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ settingsItem, moreItem ]);
    }
}

- (void)pushSettings {
    SPKDownloadsSettingsViewController *vc = [SPKDownloadsSettingsViewController new];
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UINavigationController *nav = [[SPKChromeNavigationController alloc] initWithRootViewController:vc];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)showProgressTapped {
    [[SPKDownloadService shared] reshowProgressPill];
    [self reload];
}

- (SPKDownloadHistoryFilter)currentFilter {
    switch (self.chipBar.selectedIndex) {
    case 1:
        return SPKDownloadHistoryFilterActive;
    case 2:
        return SPKDownloadHistoryFilterQueued;
    case 3:
        return SPKDownloadHistoryFilterFailed;
    case 4:
        return SPKDownloadHistoryFilterRecent;
    default:
        return SPKDownloadHistoryFilterAll;
    }
}

#pragma mark - Empty state

- (void)setupEmptyState {
    self.emptyStateView = [UIView new];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.hidden = YES;
    [self.view addSubview:self.emptyStateView];

    self.emptyStateIcon = [[UIImageView alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"empty" pointSize:96 renderingMode:UIImageRenderingModeAlwaysTemplate]];
    self.emptyStateIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.emptyStateIcon.tintColor = [SPKUtils SPKColor_InstagramTertiaryText];
    [self.emptyStateView addSubview:self.emptyStateIcon];

    self.emptyStateTitle = [UILabel new];
    self.emptyStateTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.emptyStateTitle.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    self.emptyStateTitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateTitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateTitle];

    self.emptyStateSubtitle = [UILabel new];
    self.emptyStateSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateSubtitle.font = [UIFont systemFontOfSize:14];
    self.emptyStateSubtitle.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    self.emptyStateSubtitle.textAlignment = NSTextAlignmentCenter;
    self.emptyStateSubtitle.numberOfLines = 0;
    [self.emptyStateView addSubview:self.emptyStateSubtitle];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor
                                                          constant:-30],
        [self.emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor
                                                                       constant:40],
        [self.emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor
                                                                     constant:-40],

        [self.emptyStateIcon.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor],
        [self.emptyStateIcon.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [self.emptyStateIcon.widthAnchor constraintEqualToConstant:96],
        [self.emptyStateIcon.heightAnchor constraintEqualToConstant:96],

        [self.emptyStateTitle.topAnchor constraintEqualToAnchor:self.emptyStateIcon.bottomAnchor
                                                       constant:18],
        [self.emptyStateTitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateTitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],

        [self.emptyStateSubtitle.topAnchor constraintEqualToAnchor:self.emptyStateTitle.bottomAnchor
                                                          constant:6],
        [self.emptyStateSubtitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateSubtitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],
        [self.emptyStateSubtitle.bottomAnchor constraintEqualToAnchor:self.emptyStateView.bottomAnchor],
    ]];
}

- (void)updateEmptyState {
    BOOL empty = (self.rows.count == 0);
    self.emptyStateView.hidden = !empty;
    self.tableView.hidden = empty;
    if (!empty)
        return;

    self.emptyStateIcon.image = [SPKAssetUtils instagramIconNamed:@"empty" pointSize:96 renderingMode:UIImageRenderingModeAlwaysTemplate];
    switch ([self currentFilter]) {
    case SPKDownloadHistoryFilterFailed:
        self.emptyStateTitle.text = @"没有失败的下载";
        self.emptyStateSubtitle.text = @"下载失败的任务会显示在这里。";
        break;

    case SPKDownloadHistoryFilterActive:
        self.emptyStateTitle.text = @"没有进行中的下载";
        self.emptyStateSubtitle.text = @"正在下载的任务会显示在这里。";
        break;

    case SPKDownloadHistoryFilterQueued:
        self.emptyStateTitle.text = @"没有排队中的下载";
        self.emptyStateSubtitle.text = @"等待下载的任务会显示在这里。";
        break;

    case SPKDownloadHistoryFilterRecent:
        self.emptyStateTitle.text = @"没有最近的下载";
        self.emptyStateSubtitle.text = @"最近完成或取消的下载会显示在这里。";
        break;

    default:
        self.emptyStateTitle.text = @"暂无下载";
        self.emptyStateSubtitle.text = @"从动态、Reels 或快拍中下载媒体，即可在这里查看下载记录。";
        break;
    
    }
}

#pragma mark - More menu

- (void)clearFinished {
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:@"清除已完成的下载"
                                                message:@"清除已完成的下载记录及其预览副本。进行中和排队中的下载不会受到影响；已保存到照片或图库的媒体也不会被删除。"
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:nil],
                                                    [SPKIGAlertAction actionWithTitle:@"清除"
                                                                                style:SPKIGAlertActionStyleDestructive
                                                                              handler:^{
                                                                                  [[SPKDownloadService shared] clearFinishedHistory];
                                                                                  [self reload];
                                                                              }],
                                                ]];
}

- (UIMenu *)moreMenu {
    return [UIMenu menuWithTitle:@"" children:[self moreMenuElements]];
}

- (NSArray<UIMenuElement *> *)moreMenuElements {
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *elements = [NSMutableArray array];

    // Navigation actions (top)
    NSMutableArray<UIAction *> *nav = [NSMutableArray array];
    [nav addObject:[UIAction actionWithTitle:@"打开图库"
                                       image:[SPKAssetUtils menuIconNamed:@"sparkle_gallery"]
                                  identifier:nil
                                     handler:^(__unused UIAction *a) {
                                         [SPKGalleryViewController presentGallery];
                                     }]];
    [nav addObject:[UIAction actionWithTitle:@"打开照片"
                                       image:[SPKAssetUtils menuIconNamed:@"photo_gallery"]
                                  identifier:nil
                                     handler:^(__unused UIAction *a) {
                                         [SPKUtils openPhotosApp];
                                     }]];
    [elements addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:nav]];

    // Destructive actions (bottom — inline section keeps them visually grouped last)
    NSMutableArray<UIAction *> *destructive = [NSMutableArray array];

    UIAction *clearAction = [UIAction actionWithTitle:@"清除已完成"
                                                image:[SPKAssetUtils menuIconNamed:@"trash"]
                                           identifier:nil
                                              handler:^(__unused UIAction *a) {
                                                  [weakSelf clearFinished];
                                              }];
    clearAction.attributes = UIMenuElementAttributesDestructive;
    [destructive addObject:clearAction];

    BOOL hasActive = NO;
    for (SPKDownloadJob *job in [[SPKDownloadService shared] jobsMatchingFilter:SPKDownloadHistoryFilterAll]) {
        if (job.state == SPKDownloadStateRunning || job.state == SPKDownloadStateQueued || job.state == SPKDownloadStatePending) {
            hasActive = YES;
            break;
        }
    }
    if (hasActive) {
        UIAction *cancelAll = [UIAction actionWithTitle:@"取消所有正在下载的任务"
                                                  image:[SPKAssetUtils menuIconNamed:@"xmark"]
                                             identifier:nil
                                                handler:^(__unused UIAction *a) {
                                                    [SPKDownloadService confirmCancelAllActive];
                                                }];
        cancelAll.attributes = UIMenuElementAttributesDestructive;
        [destructive addObject:cancelAll];
    }

    [elements addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:destructive]];
    return elements;
}

#pragma mark - SPKChipBarDelegate

- (void)chipBar:(SPKChipBar *)bar didSelectIndex:(NSInteger)index {
    (void)bar;
    (void)index;
    [self reload];
}

#pragma mark - Cell configuration helpers

/// Returns the icon name reflecting the ACTION that was performed on this job.
/// Batch share/clipboard jobs use CacheOnly destination + finalize flags, so we must
/// check those flags first; otherwise they'd all show the generic download icon.
static NSString *SPKActionIconForJob(SPKDownloadJob *job) {
    if (job.request.finalizeAsBatchShare)
        return @"share";
    if (job.request.finalizeAsBatchClipboard)
        return @"copy";
    switch (job.request.destination) {
    case SPKDownloadDestinationPhotos:
        return @"photo";
    case SPKDownloadDestinationGallery:
        return @"sparkle_gallery";
    case SPKDownloadDestinationShare:
        return @"share";
    case SPKDownloadDestinationClipboard:
        return @"copy";
    default:
        return @"download";
    }
}

/// Returns the media-type icon name for the row-type icon.
static NSString *SPKMediaIconName(SPKDownloadMediaKind kind) {
    switch (kind) {
    case SPKDownloadMediaKindVideo:
        return @"video_filled";
    case SPKDownloadMediaKindAudio:
        return @"audio";
    default:
        return @"photo_filled";
    }
}

/// YES when a job is an Instants batch whose children span more than one source user.
/// Instants bulk actions can pull snaps from multiple accounts, so the per-child rows
/// need the username to stay unambiguous. Single-user jobs (incl. feed carousels) don't.
static BOOL SPKJobIsMultiUserInstants(SPKDownloadJob *job) {
    if (job.request.sourceSurface != SPKDownloadSourceSurfaceInstants)
        return NO;
    NSMutableSet<NSString *> *users = [NSMutableSet set];
    for (SPKDownloadItem *item in job.items) {
        NSString *trimmed = [item.metadata.sourceUsername stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0)
            [users addObject:trimmed.lowercaseString];
        if (users.count > 1)
            return YES;
    }
    return NO;
}

/// Sets the status badge on the cell.
static void SPKApplyStatusBadge(SPKDownloadHistoryCell *cell, SPKDownloadState state) {
    NSString *icon = nil;
    UIColor *color = nil;
    switch (state) {
    case SPKDownloadStateSucceeded:
        icon = @"circle_check_filled";
        color = [UIColor systemGreenColor];
        break;
    case SPKDownloadStateFailed:
    case SPKDownloadStateInterrupted:
        icon = @"error_filled";
        color = [SPKUtils SPKColor_InstagramDestructive];
        break;
    case SPKDownloadStateCancelled:
        icon = @"circle_off";
        color = [SPKUtils SPKColor_InstagramSecondaryText];
        break;
    case SPKDownloadStateRunning:
    case SPKDownloadStateFinalizing:
        icon = @"play_filled";
        color = [SPKUtils SPKColor_InstagramBlue];
        break;
    case SPKDownloadStateQueued:
    case SPKDownloadStatePending:
    case SPKDownloadStateWaitingForPreflight:
        icon = @"clock";
        color = [SPKUtils SPKColor_InstagramSecondaryText];
        break;
    case SPKDownloadStatePartial:
        icon = @"error";
        color = [UIColor systemOrangeColor];
        break;
    default:
        break;
    }
    if (icon) {
        cell.statusBadge.image = [SPKAssetUtils instagramIconNamed:icon pointSize:12];
        cell.statusBadge.tintColor = color;
        cell.statusBadge.hidden = NO;
    } else {
        cell.statusBadge.hidden = YES;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return self.rows[indexPath.row].kind == SPKDownloadsHistoryRowKindChild ? 52 : 72;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPKDownloadHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    SPKDownloadsHistoryRow *row = self.rows[indexPath.row];
    SPKDownloadJob *job = row.job;
    SPKDownloadItem *item = row.item;

    if (row.kind == SPKDownloadsHistoryRowKindChild && item) {
        [self configureCell:cell withChildItem:item job:job];
    } else {
        [self configureCell:cell withJob:job];
    }
    return cell;
}

- (void)configureCell:(SPKDownloadHistoryCell *)cell withJob:(SPKDownloadJob *)job {
    cell.representedID = job.jobID;

    // Title
    cell.titleLabel.text = job.title ?: @"下载";

    // Thumbnail: destination action icon, no tint bleed
    NSString *actionIcon = SPKActionIconForJob(job);
    cell.thumbnailView.contentMode = UIViewContentModeCenter;
    cell.thumbnailView.image = [SPKAssetUtils instagramIconNamed:actionIcon pointSize:24];
    cell.thumbnailView.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];

    // Status badge
    SPKApplyStatusBadge(cell, job.state);

    // Row-type icon (carousel vs media kind)
    cell.rowTypeIcon.hidden = NO;
    cell.rowTypeIconWidth.constant = 14;
    if (job.items.count > 1) {
        cell.rowTypeIcon.image = [SPKAssetUtils instagramIconNamed:@"carousel_filled" pointSize:12];
    } else {
        SPKDownloadItem *first = job.items.firstObject;
        cell.rowTypeIcon.image = [SPKAssetUtils instagramIconNamed:SPKMediaIconName(first.mediaKind) pointSize:12];
    }

    // Technical line (gallery-style: size • duration for video/audio, size • items for carousel)
    NSMutableArray *parts = [NSMutableArray array];
    if (job.state == SPKDownloadStateRunning || job.state == SPKDownloadStateFinalizing) {
        int pct = MIN(100, MAX(0, (int)(job.aggregateProgress * 100)));
        [parts addObject:[NSString stringWithFormat:@"%d%%", pct]];
    }
    if (job.items.count > 1) {
        [parts addObject:[NSString stringWithFormat:@"%lu 个项目", (unsigned long)job.items.count]];
    } else {
        SPKDownloadItem *first = job.items.firstObject;
        int64_t size = first.totalBytesExpected > 0 ? first.totalBytesExpected : first.bytesWritten;
        if (size > 0) {
            [parts addObject:[NSByteCountFormatter stringFromByteCount:size countStyle:NSByteCountFormatterCountStyleFile]];
        }
        // Duration for video/audio (like gallery)
        SPKGallerySaveMetadata *meta = first.metadata ?: first.request.metadata;
        double duration = meta.durationSeconds;
        if (duration > 0.5 && (first.mediaKind == SPKDownloadMediaKindVideo || first.mediaKind == SPKDownloadMediaKindAudio)) {
            NSInteger total = (NSInteger)llround(duration);
            if (total >= 3600) {
                [parts addObject:[NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(total / 3600), (long)((total % 3600) / 60), (long)(total % 60)]];
            } else {
                [parts addObject:[NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)]];
            }
        }
    }
    cell.technicalLabel.text = [parts componentsJoinedByString:@" • "];

    // Pill: source surface
    cell.pillBackground.hidden = NO;
    cell.pillLabel.text = SPKDownloadSourceSurfaceDisplayName(job.request.sourceSurface);

    // Date
    cell.dateLabel.hidden = NO;
    cell.dateLabel.text = SPKDownloadHistoryDateString(job.createdAt);

    // Chevron for carousels (animated rotation on expand/collapse)
    if (job.items.count > 1) {
        cell.chevronView.image = [UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium]];
        cell.chevronView.hidden = NO;
        BOOL expanded = [self.expandedJobIDs containsObject:job.jobID];
        cell.chevronView.transform = expanded
                                         ? CGAffineTransformMakeRotation(M_PI_2) // 90° = chevron.down
                                         : CGAffineTransformIdentity;            // 0° = chevron.right
    } else {
        cell.chevronView.hidden = YES;
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.thumbLeading.constant = 16;
    cell.separatorLeading.constant = 80;
}

- (void)configureCell:(SPKDownloadHistoryCell *)cell withChildItem:(SPKDownloadItem *)item job:(SPKDownloadJob *)job {
    cell.representedID = item.itemID;

    // Hide ALL parent-layout views; the compact child uses its own centered views.
    cell.thumbnailView.hidden = YES;
    cell.thumbnailView.image = nil;
    cell.statusBadge.hidden = YES;
    cell.rowTypeIcon.hidden = YES;
    cell.rowTypeIconWidth.constant = 0;
    cell.titleLabel.text = nil;
    cell.technicalLabel.text = nil;
    cell.pillBackground.hidden = YES;
    cell.dateLabel.hidden = YES;
    cell.chevronView.hidden = YES;

    // Status icon
    NSString *statusIcon = nil;
    UIColor *statusColor = nil;
    switch (item.state) {
    case SPKDownloadStateSucceeded:
        statusIcon = @"circle_check_filled";
        statusColor = [UIColor systemGreenColor];
        break;
    case SPKDownloadStateFailed:
    case SPKDownloadStateInterrupted:
        statusIcon = @"error_filled";
        statusColor = [SPKUtils SPKColor_InstagramDestructive];
        break;
    case SPKDownloadStateCancelled:
        statusIcon = @"circle_off";
        statusColor = [SPKUtils SPKColor_InstagramSecondaryText];
        break;
    case SPKDownloadStateRunning:
    case SPKDownloadStateFinalizing:
        statusIcon = @"play_filled";
        statusColor = [SPKUtils SPKColor_InstagramBlue];
        break;
    case SPKDownloadStateQueued:
    case SPKDownloadStatePending:
    case SPKDownloadStateWaitingForPreflight:
        statusIcon = @"clock";
        statusColor = [SPKUtils SPKColor_InstagramSecondaryText];
        break;
    case SPKDownloadStatePartial:
        statusIcon = @"error";
        statusColor = [UIColor systemOrangeColor];
        break;
    default:
        break;
    }
    cell.compactStatusIcon.hidden = (statusIcon == nil);
    cell.compactStatusIcon.image = statusIcon ? [SPKAssetUtils instagramIconNamed:statusIcon pointSize:14] : nil;
    cell.compactStatusIcon.tintColor = statusColor;

    // Single metadata line
    NSMutableArray *parts = [NSMutableArray array];
    if (SPKJobIsMultiUserInstants(job)) {
        NSString *user = [item.metadata.sourceUsername stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (user.length > 0)
            [parts addObject:[@"@" stringByAppendingString:user]];
    }
    switch (item.mediaKind) {
    case SPKDownloadMediaKindVideo:
        [parts addObject:@"视频"];
        break;
    case SPKDownloadMediaKindAudio:
        [parts addObject:@"音频"];
        break;
    case SPKDownloadMediaKindImage:
        [parts addObject:@"照片"];
        break;
    default:
        [parts addObject:[NSString stringWithFormat:@"第 %ld 项", (long)(item.index + 1)]];
        break;
    }
    if (item.state == SPKDownloadStateRunning || item.state == SPKDownloadStateFinalizing) {
        int pct = MIN(100, MAX(0, (int)(item.progress * 100)));
        [parts addObject:[NSString stringWithFormat:@"%d%%", pct]];
    }
    int64_t size = item.totalBytesExpected > 0 ? item.totalBytesExpected : item.bytesWritten;
    if (size > 0) {
        [parts addObject:[NSByteCountFormatter stringFromByteCount:size countStyle:NSByteCountFormatterCountStyleFile]];
    }
    if (item.metadata.durationSeconds > 0.5) {
        NSInteger total = (NSInteger)llround(item.metadata.durationSeconds);
        if (total >= 3600) {
            [parts addObject:[NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(total / 3600), (long)((total % 3600) / 60), (long)(total % 60)]];
        } else {
            [parts addObject:[NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)]];
        }
    }
    cell.compactLabel.hidden = NO;
    cell.compactLabel.text = [parts componentsJoinedByString:@" • "];

    cell.separatorLeading.constant = 56;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SPKDownloadsHistoryRow *row = self.rows[indexPath.row];

    // Expand/collapse carousel
    if (row.kind == SPKDownloadsHistoryRowKindJob && row.job.items.count > 1) {
        BOOL wasExpanded = [self.expandedJobIDs containsObject:row.job.jobID];
        if (wasExpanded)
            [self.expandedJobIDs removeObject:row.job.jobID];
        else
            [self.expandedJobIDs addObject:row.job.jobID];

        // Animate chevron rotation
        SPKDownloadHistoryCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        if (cell.chevronView && !cell.chevronView.hidden) {
            [UIView animateWithDuration:0.25
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseInOut
                             animations:^{
                                 cell.chevronView.transform = wasExpanded
                                                                  ? CGAffineTransformIdentity              // collapse: chevron.right
                                                                  : CGAffineTransformMakeRotation(M_PI_2); // expand: chevron.down
                             }
                             completion:nil];
        }
        [self reload];
        return;
    }

    SPKDownloadItem *item = row.item ?: row.job.items.firstObject;
    if (!item)
        return;

    // Failed/interrupted → show error alert with Retry + Dismiss
    if (item.state == SPKDownloadStateFailed || item.state == SPKDownloadStateInterrupted) {
        NSString *title = item.state == SPKDownloadStateFailed ? @"下载失败"
        : @"下载中断";
        NSString *message = item.error.localizedDescription ?: item.detail ?
                                                                           : @"发生未知错误。";
        NSString *jobID = row.job.jobID;
        NSString *itemID = item.itemID;
        BOOL isChild = (row.kind == SPKDownloadsHistoryRowKindChild);
        [SPKIGAlertPresenter presentAlertFromViewController:self
                                                      title:title
                                                    message:message
                                                    actions:@[
                                                        [SPKIGAlertAction actionWithTitle:@"关闭"
                                                                                    style:SPKIGAlertActionStyleCancel
                                                                                  handler:nil],
                                                        [SPKIGAlertAction actionWithTitle:@"重试"
                                                                                    style:SPKIGAlertActionStyleDefault
                                                                                  handler:^{
                                                                                      if (isChild)
                                                                                          [[SPKDownloadService shared] retryItemID:itemID inJobID:jobID];
                                                                                      else
                                                                                          [[SPKDownloadService shared] retryJobID:jobID];
                                                                                  }],
                                                    ]];
        return;
    }

    // Completed → preview
    NSString *path = item.finalPath ?: item.stagedPath;
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        // For carousel children: build all sibling items so the user can swipe between them
        if (row.kind == SPKDownloadsHistoryRowKindChild && row.job.items.count > 1) {
            NSMutableArray<SPKMediaItem *> *allMedia = [NSMutableArray array];
            NSInteger startIndex = 0;
            for (NSUInteger i = 0; i < row.job.items.count; i++) {
                SPKDownloadItem *sibling = row.job.items[i];
                NSString *siblingPath = sibling.finalPath ?: sibling.stagedPath;
                if (siblingPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:siblingPath]) {
                    SPKMediaItem *m = [SPKMediaItem itemWithFileURL:[NSURL fileURLWithPath:siblingPath]];
                    m.galleryMetadata = sibling.metadata;
                    [allMedia addObject:m];
                    if ([sibling.itemID isEqualToString:item.itemID])
                        startIndex = (NSInteger)allMedia.count - 1;
                }
            }
            if (allMedia.count > 0) {
                [SPKFullScreenMediaPlayer showMediaItems:allMedia startingAtIndex:startIndex metadata:item.metadata playbackSource:SPKFullScreenPlaybackSourceUnknown sourceView:nil controller:self pausePlayback:nil resumePlayback:nil];
                return;
            }
        }
        // Single item preview
        SPKMediaItem *media = [SPKMediaItem itemWithFileURL:[NSURL fileURLWithPath:path]];
        [SPKFullScreenMediaPlayer showMediaItems:@[ media ] startingAtIndex:0 metadata:item.metadata playbackSource:SPKFullScreenPlaybackSourceUnknown sourceView:nil controller:self pausePlayback:nil resumePlayback:nil];
        return;
    }

    if ([row.job.completionAction isEqualToString:@"openGallery"])
        [SPKGalleryViewController presentGallery];
    else if ([row.job.completionAction isEqualToString:@"openPhotos"])
        [SPKUtils openPhotosApp];
}

#pragma mark - Swipe Actions (swipe-safe)

- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    self.swipeInProgress = YES;
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    self.swipeInProgress = NO;
    // Catch up on any notifications we skipped
    [self reload];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) {
    (void)tableView;
    if (indexPath.row >= (NSInteger)self.rows.count)
        return nil;
    SPKDownloadsHistoryRow *row = self.rows[indexPath.row];
    SPKDownloadItem *item = row.item ?: row.job.items.firstObject;
    if (!item)
        return nil;

    NSMutableArray *actions = [NSMutableArray array];

    // Retry (failed / interrupted / cancelled)
    if (item.state == SPKDownloadStateFailed || item.state == SPKDownloadStateInterrupted || item.state == SPKDownloadStateCancelled) {
        UIContextualAction *retry = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:nil
                                                                          handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                                                                              (void)a;
                                                                              (void)v;
                                                                              if (row.kind == SPKDownloadsHistoryRowKindChild)
                                                                                  [[SPKDownloadService shared] retryItemID:item.itemID inJobID:row.job.jobID];
                                                                              else
                                                                                  [[SPKDownloadService shared] retryJobID:row.job.jobID];
                                                                              done(YES);
                                                                          }];
        retry.image = [SPKAssetUtils menuIconNamed:@"arrow_cw"];
        retry.backgroundColor = [SPKUtils SPKColor_InstagramBlue];
        retry.accessibilityLabel = @"重试";
        [actions addObject:retry];
    }

    // Cancel (active)
    if (!SPKDownloadStateIsTerminal(item.state)) {
        UIContextualAction *cancel = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                             title:nil
                                                                           handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                                                                               (void)a;
                                                                               (void)v;
                                                                               if (row.kind == SPKDownloadsHistoryRowKindChild)
                                                                                   [[SPKDownloadService shared] cancelItemID:item.itemID inJobID:row.job.jobID];
                                                                               else
                                                                                   [[SPKDownloadService shared] cancelJobID:row.job.jobID];
                                                                               done(YES);
                                                                           }];
        cancel.image = [SPKAssetUtils menuIconNamed:@"xmark"];
        cancel.backgroundColor = [SPKUtils SPKColor_InstagramDestructive];
        cancel.accessibilityLabel = @"取消";
        [actions addObject:cancel];
    }

    // Remove
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:nil
                                                                       handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                                                                           (void)a;
                                                                           (void)v;
                                                                           [[SPKDownloadService shared] removeJobID:row.job.jobID];
                                                                           done(YES);
                                                                       }];
    remove.image = [SPKAssetUtils menuIconNamed:@"trash"];
    remove.backgroundColor = [SPKUtils SPKColor_InstagramDestructive];
    remove.accessibilityLabel = @"移除";
    [actions addObject:remove];

    // Copy link
    NSString *link = item.linkString ?: item.request.linkString;
    if (link.length > 0) {
        UIContextualAction *copy = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                           title:nil
                                                                         handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                                                                             (void)a;
                                                                             (void)v;
                                                                             UIPasteboard.generalPasteboard.string = link;
                                                                             done(YES);
                                                                         }];
        copy.image = [SPKAssetUtils menuIconNamed:@"copy"];
        copy.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryText];
        copy.accessibilityLabel = @"复制链接";
        [actions addObject:copy];
    }

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:actions];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

@end
