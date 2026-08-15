#import "SPKDeletedMessagesUserDetailViewController.h"

#import "../../../AssetUtils.h"
#import "../../../Shared/Avatars/SPKAvatarCache.h"
#import "../../../Shared/MediaPreview/SPKFullScreenMediaPlayer.h"
#import "../../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../../Shared/UI/SPKMediaChrome.h"
#import "../../../Utils.h"
#import "SPKDeletedMessageBubbleCell.h"
#import "SPKDeletedMessagesAvatarView.h"
#import "SPKDeletedMessagesChipBar.h"
#import "SPKDeletedMessagesDate.h"
#import "SPKDeletedMessagesFilter.h"
#import "SPKDeletedMessagesStorage.h"

@interface SPKDeletedMessagesUserDetailViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, SPKDeletedMessagesChipBarDelegate, SPKDeletedMessageBubbleCellDelegate>
@property (nonatomic, strong) SPKDeletedMessageGroup *group;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) SPKDeletedMessagesChipBar *chipBar;
@property (nonatomic, strong) NSLayoutConstraint *chipBarHeight;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, assign) BOOL titleShowingIdentity;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyStateIcon;
@property (nonatomic, strong) UILabel *emptyStateTitle;
@property (nonatomic, strong) UILabel *emptyStateSubtitle;
@property (nonatomic, strong) SPKDeletedMessagesFilter *filter;
@property (nonatomic, copy) NSArray<SPKDeletedMessage *> *messages;
@property (nonatomic, copy) NSArray<SPKDeletedMessage *> *visibleMessages;
@property (nonatomic, copy, nullable) NSString *threadId; // resolved from the group's messages
@property (nonatomic, assign) BOOL shouldScrollToBottomOnReload;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property (nonatomic, strong) dispatch_queue_t thumbnailQueue;
@end

@implementation SPKDeletedMessagesUserDetailViewController

// Chip filter columns — see SPKDeletedMessagesViewController for the rationale.
static NSArray<NSString *> *SPKDMDetailChipTitles(void) {
    return @[ @"Text", @"Photo", @"视频", @"Voice", @"GIF", @"Sticker", @"Shares", @"链接", @"Reaction" ];
}
static NSArray<NSString *> *SPKDMDetailChipSymbols(void) {
    return @[ @"message", @"photo", @"video", @"voice", @"gif", @"sticker", @"shares", @"link", @"reactions" ];
}
static NSArray<NSString *> *SPKDMDetailChipSelectedSymbols(void) {
    return @[ @"message", @"photo_filled", @"video_filled", @"voice_filled", @"gif_filled", @"sticker_filled", @"shares_filled", @"link", @"reactions" ];
}
static SPKDeletedMessageKind SPKDMDetailChipKindForIndex(NSInteger index) {
    switch (index) {
    case 0:
        return SPKDeletedMessageKindText;
    case 1:
        return SPKDeletedMessageKindPhoto;
    case 2:
        return SPKDeletedMessageKindVideo;
    case 3:
        return SPKDeletedMessageKindVoice;
    case 4:
        return SPKDeletedMessageKindGif;
    case 5:
        return SPKDeletedMessageKindSticker;
    case 6:
        return SPKDeletedMessageKindShare;
    case 7:
        return SPKDeletedMessageKindLink;
    case 8:
        return SPKDeletedMessageKindReaction;
    default:
        return SPKDeletedMessageKindUnknown;
    }
}

- (instancetype)initWithGroup:(SPKDeletedMessageGroup *)group ownerPK:(NSString *)ownerPK {
    if ((self = [super init])) {
        _group = group;
        _ownerPK = ownerPK.length ? [ownerPK copy] : @"anon";
        _filter = [SPKDeletedMessagesFilter new];
        // Default to oldest-first so the chat reads top-to-bottom.
        _filter.sort = SPKDMSortOldest;
        // Resolve the thread this sender's messages belong to so we can show the
        // full conversation (their unsends + your own) in chat order.
        for (SPKDeletedMessage *m in group.messages) {
            if (m.threadId.length) {
                _threadId = [m.threadId copy];
                break;
            }
        }
        _thumbnailCache = [NSCache new];
        _thumbnailCache.countLimit = 120;
        _thumbnailQueue = dispatch_queue_create("com.sparkle.deletedmessages.detailthumbs", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Groups keep the thread title. 1:1 threads use a static title so the
    // sticky profile header can serve as the primary identity anchor.
    self.title = self.group.isGroup
                     ? (self.group.displayName.length ? self.group.displayName : @"Group Chat")
                     : @"已删除消息";
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramBackground];

    if (!self.group.isGroup) {
        // Compact-bar title starts generic and morphs into the sender's identity
        // once the (non-sticky) profile header scrolls out of view — see
        // spk_updateTitleMorphForScrollView:. Groups keep a static title since
        // there's no single identity to morph to.
        UILabel *titleLabel = [UILabel new];
        // Auto Layout (not a fixed frame) so the title view re-fits its intrinsic
        // width every time the text changes — otherwise the frame stays locked to
        // the initial "Deleted Messages" width and a longer @username truncates
        // far too early. It now only truncates at the real space available between
        // the back button and the trailing items.
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        titleLabel.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        titleLabel.text = @"已删除消息";
        self.navigationItem.titleView = titleLabel;
        self.titleLabel = titleLabel;
    }

    UIBarButtonItem *moreItem = SPKMediaChromeTopBarMenuButtonItem(@"more", [self moreMenu], @"更多");
    SPKMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ moreItem ]);

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索消息";
    [self.searchController.searchBar setImage:[SPKAssetUtils instagramIconNamed:@"search" pointSize:18.0]
                             forSearchBarIcon:UISearchBarIconSearch
                                        state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.chipBar = [[SPKDeletedMessagesChipBar alloc] initWithFrame:CGRectZero];
    self.chipBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipBar.delegate = self;
    [self.chipBar setItems:SPKDMDetailChipTitles() symbols:SPKDMDetailChipSymbols() selectedSymbols:SPKDMDetailChipSelectedSymbols()];
    [self.view addSubview:self.chipBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramBackground];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90.0;
    self.tableView.allowsSelection = NO;
    [self.tableView registerClass:[SPKDeletedMessageBubbleCell class] forCellReuseIdentifier:SPKDeletedMessageBubbleCellReuseID];
    [self.view addSubview:self.tableView];

    [self setupEmptyState];

    self.chipBarHeight = [self.chipBar.heightAnchor constraintEqualToConstant:50.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.chipBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        self.chipBarHeight,
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.chipBar.bottomAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    if (!self.group.isGroup) {
        // tableHeaderView scrolls with content (non-sticky) so it doesn't
        // permanently eat screen space. UITableView sets the width to its own
        // width; we only need to supply the height.
        UIView *header = [self buildProfileHeaderView];
        header.frame = CGRectMake(0, 0, 0, 56.0);
        self.tableView.tableHeaderView = header;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:SPKDeletedMessagesDidChangeNotification object:nil];
    [self reloadData];
}

- (void)setupEmptyState {
    self.emptyStateView = [UIView new];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.hidden = YES;
    [self.view addSubview:self.emptyStateView];

    self.emptyStateIcon = [[UIImageView alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"messages_empty" pointSize:96.0 renderingMode:UIImageRenderingModeAlwaysTemplate]];
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
        [self.emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor
                                                          constant:-30.0],
        [self.emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor
                                                                       constant:40.0],
        [self.emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor
                                                                     constant:-40.0],

        [self.emptyStateIcon.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor],
        [self.emptyStateIcon.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [self.emptyStateIcon.widthAnchor constraintEqualToConstant:96.0],
        [self.emptyStateIcon.heightAnchor constraintEqualToConstant:96.0],

        [self.emptyStateTitle.topAnchor constraintEqualToAnchor:self.emptyStateIcon.bottomAnchor
                                                       constant:18.0],
        [self.emptyStateTitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateTitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],

        [self.emptyStateSubtitle.topAnchor constraintEqualToAnchor:self.emptyStateTitle.bottomAnchor
                                                          constant:6.0],
        [self.emptyStateSubtitle.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor],
        [self.emptyStateSubtitle.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor],
        [self.emptyStateSubtitle.bottomAnchor constraintEqualToAnchor:self.emptyStateView.bottomAnchor],
    ]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData {
    // When the thread is known, show the whole conversation (incoming + your
    // own unsends) in chat order. Otherwise fall back to this sender only.
    if (self.threadId.length) {
        self.messages = [SPKDeletedMessagesStorage messagesForThreadId:self.threadId ownerPK:self.ownerPK];
    } else {
        self.messages = [SPKDeletedMessagesStorage messagesForSenderPK:self.group.senderPk ownerPK:self.ownerPK];
    }
    // A fresh data load should land on the newest message at the bottom.
    self.shouldScrollToBottomOnReload = YES;
    [self applyFilter];
    [self rebuildMenus];
}

- (void)applyFilter {
    self.visibleMessages = [self.filter apply:self.messages ?: @[]];
    [self updateChipBarVisibility];
    [self updateEmptyState];
    [self.tableView reloadData];
    if (self.shouldScrollToBottomOnReload) {
        self.shouldScrollToBottomOnReload = NO;
        [self scrollToBottomAnimated:NO];
    }
}

// Jump to the latest (bottom-most) message, chat-style.
- (void)scrollToBottomAnimated:(BOOL)animated {
    NSInteger count = (NSInteger)self.visibleMessages.count;
    if (count == 0)
        return;
    // Defer until the table has laid out its rows so the offset is correct with
    // self-sizing cells.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger rows = [self.tableView numberOfRowsInSection:0];
        if (rows == 0)
            return;
        [self.tableView layoutIfNeeded];
        NSIndexPath *last = [NSIndexPath indexPathForRow:rows - 1 inSection:0];
        [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
    });
}

- (NSUInteger)distinctKindCount {
    NSMutableSet<NSNumber *> *kinds = [NSMutableSet set];
    for (SPKDeletedMessage *message in self.messages)
        [kinds addObject:@(message.kind)];
    return kinds.count;
}

- (void)updateChipBarVisibility {
    BOOL show = ([self distinctKindCount] >= 2) || [self.filter hasKindFilter];
    BOOL hidden = !show;
    if (self.chipBar.hidden != hidden) {
        self.chipBar.hidden = hidden;
        self.chipBarHeight.constant = hidden ? 0.0 : 50.0;
    }
}

#pragma mark - Scroll-linked chrome

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self spk_updateTitleMorphForScrollView:scrollView];
}

// Morphs the compact-bar title from "Deleted Messages" to the sender's name/
// username once the profile header (56pt tableHeaderView) has scrolled past.
- (void)spk_updateTitleMorphForScrollView:(UIScrollView *)scrollView {
    if (!self.titleLabel)
        return; // groups keep a static title
    static const CGFloat kThreshold = 40.0;
    BOOL shouldShowIdentity = scrollView.contentOffset.y > kThreshold;
    if (shouldShowIdentity == self.titleShowingIdentity)
        return;
    self.titleShowingIdentity = shouldShowIdentity;
    NSString *text = shouldShowIdentity ? [self identityTitleText] : @"已删除消息";
    [UIView transitionWithView:self.titleLabel
                      duration:0.2
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
                        self.titleLabel.text = text;
                    }
                    completion:nil];
}

- (NSString *)identityTitleText {
    if (self.group.senderUsername.length)
        return [@"@" stringByAppendingString:self.group.senderUsername];
    if (self.group.senderFullName.length)
        return self.group.senderFullName;
    return @"Unknown";
}

- (void)updateEmptyState {
    BOOL isEmpty = (self.visibleMessages.count == 0);
    self.emptyStateView.hidden = !isEmpty;
    self.tableView.hidden = isEmpty;
    if (!isEmpty)
        return;

    if (![self.filter isEmpty]) {
        self.emptyStateTitle.text = @"No matches";
        self.emptyStateSubtitle.text = @"No messages match the current filters.";
    } else {
        self.emptyStateTitle.text = @"Nothing here yet";
        self.emptyStateSubtitle.text = @"This sender's unsent messages will show up here.";
    }
}

- (void)rebuildMenus {
    // The more menu is deferred (self-refreshing); nothing to reassign.
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.filter.searchText = searchController.searchBar.text;
    [self applyFilter];
}

#pragma mark - Chip Bar

- (void)chipBar:(SPKDeletedMessagesChipBar *)bar didChangeSelection:(NSSet<NSNumber *> *)selectedIndices {
    [self.filter clearKinds];
    for (NSNumber *index in selectedIndices) {
        SPKDeletedMessageKind kind = SPKDMDetailChipKindForIndex(index.integerValue);
        if (kind != SPKDeletedMessageKindUnknown)
            [self.filter toggleKind:kind];
    }
    [self applyFilter];
}

#pragma mark - Menus

// The bar button keeps a stable menu whose children are resolved fresh each
// time it opens, so pin/block titles always reflect current state without
// needing to reassign the bar button item's menu.
- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([weakSelf moreMenuElements]);
    }];
    return [UIMenu menuWithTitle:@"" children:@[ deferred ]];
}

- (NSArray<UIMenuElement *> *)moreMenuElements {
    __weak typeof(self) weakSelf = self;

    BOOL isGroup = self.group.isGroup;
    NSString *noun = isGroup ? @"Chat" : @"Sender";

    UIAction *pinAction = [UIAction actionWithTitle:[NSString stringWithFormat:@"%@ %@", self.group.isPinned ? @"Unpin" : @"Pin", noun]
                                              image:[SPKAssetUtils menuIconNamed:(self.group.isPinned ? @"pin_filled" : @"pin_outline")]
                                         identifier:nil
                                            handler:^(__unused UIAction *a) {
                                                [SPKDeletedMessagesStorage setSenderPinned:!weakSelf.group.isPinned senderPK:weakSelf.group.flagKey ownerPK:weakSelf.ownerPK];
                                                weakSelf.group.isPinned = !weakSelf.group.isPinned;
                                            }];

    UIAction *blockAction = [UIAction actionWithTitle:[NSString stringWithFormat:@"%@ %@", self.group.isBlocked ? @"Unblock" : @"Block", noun]
                                                image:[SPKAssetUtils menuIconNamed:self.group.isBlocked ? @"circle" : @"block"]
                                           identifier:nil
                                              handler:^(__unused UIAction *a) {
                                                  [SPKDeletedMessagesStorage setSenderBlocked:!weakSelf.group.isBlocked senderPK:weakSelf.group.flagKey ownerPK:weakSelf.ownerPK];
                                                  weakSelf.group.isBlocked = !weakSelf.group.isBlocked;
                                              }];

    UIAction *deleteAction = [UIAction actionWithTitle:[NSString stringWithFormat:@"Delete %@ Log", noun]
                                                 image:[SPKAssetUtils menuIconNamed:@"trash"]
                                            identifier:nil
                                               handler:^(__unused UIAction *a) {
                                                   NSString *who = isGroup ? weakSelf.group.displayName
                                                                           : (weakSelf.group.senderUsername.length ? [@"@" stringByAppendingString:weakSelf.group.senderUsername] : @"this sender");
                                                   [SPKIGAlertPresenter presentAlertFromViewController:weakSelf
                                                                                                 title:isGroup ? @"Delete group log?" : @"Delete sender log?"
                                                                                               message:[NSString stringWithFormat:@"This removes all logged messages from %@.", who]
                                                                                               actions:@[
                                                                                                   [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                                                               style:SPKIGAlertActionStyleCancel
                                                                                                                             handler:nil],
                                                                                                   [SPKIGAlertAction actionWithTitle:@"删除"
                                                                                                                               style:SPKIGAlertActionStyleDestructive
                                                                                                                             handler:^{
                                                                                                                                 if (weakSelf.group.isGroup)
                                                                                                                                     [SPKDeletedMessagesStorage deleteMessagesForThreadId:weakSelf.group.threadId ownerPK:weakSelf.ownerPK];
                                                                                                                                 else
                                                                                                                                     [SPKDeletedMessagesStorage deleteMessagesForSenderPK:weakSelf.group.senderPk ownerPK:weakSelf.ownerPK];
                                                                                                                                 [weakSelf.navigationController popViewControllerAnimated:YES];
                                                                                                                             }],
                                                                                               ]];
                                               }];
    /// TODO: investigate whether native UIMenu destructive tint can be customized. UIMenuElement exposes no supported color API.
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    UIMenu *destructiveSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[ deleteAction ]];

    UIAction *refreshAvatarsAction = [UIAction actionWithTitle:@"Refresh Profile Pictures"
                                                         image:[SPKAssetUtils menuIconNamed:@"user_circle"]
                                                    identifier:nil
                                                       handler:^(__unused UIAction *a) {
                                                           [[SPKAvatarCache shared] purge];
                                                           [weakSelf.tableView reloadData];
                                                       }];

    if (!isGroup && self.group.senderUsername.length) {
        NSString *username = self.group.senderUsername;
        // See the header button: passing the pk avoids a lookup round trip.
        NSString *senderPK = self.group.senderPk;
        UIAction *openProfileAction = [UIAction actionWithTitle:@"打开个人资料"
                                                          image:[SPKAssetUtils menuIconNamed:@"user"]
                                                     identifier:nil
                                                         handler:^(__unused UIAction *a) {
                                                             [SPKUtils openInstagramProfileForUser:nil pk:senderPK username:username fromViewController:weakSelf];
                                                         }];
        return @[ openProfileAction, pinAction, blockAction, refreshAvatarsAction, destructiveSection ];
    }

    return @[ pinAction, blockAction, refreshAvatarsAction, destructiveSection ];
}

#pragma mark - Profile header (1:1 only)

// Scrolling table header for 1:1 threads: profile picture, full name, @username,
// and an "Open Profile" button. Scrolls away with the content so it never
// permanently steals space. Groups skip this — identity lives in the navbar title
// and the per-bubble sender labels.
- (UIView *)buildProfileHeaderView {
    UIView *container = [UIView new];
    container.backgroundColor = [SPKUtils SPKColor_InstagramBackground];

    // Avatar (36pt circle).
    SPKDeletedMessagesAvatarView *avatar = [[SPKDeletedMessagesAvatarView alloc] initWithFrame:CGRectZero];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    [avatar configureWithPK:self.group.senderPk urlString:self.group.senderProfilePicURL];
    [container addSubview:avatar];

    // Name label.
    UILabel *nameLabel = [UILabel new];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    nameLabel.textColor = [SPKUtils SPKColor_InstagramPrimaryText];
    nameLabel.numberOfLines = 1;
    NSString *displayName = self.group.senderFullName.length ? self.group.senderFullName
                                                             : (self.group.senderUsername.length ? self.group.senderUsername : @"Unknown");
    nameLabel.text = displayName;

    // Username label.
    UILabel *usernameLabel = [UILabel new];
    usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    usernameLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    usernameLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    usernameLabel.numberOfLines = 1;
    usernameLabel.hidden = (self.group.senderUsername.length == 0);
    if (self.group.senderUsername.length) {
        usernameLabel.text = [@"@" stringByAppendingString:self.group.senderUsername];
    }

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[ nameLabel, usernameLabel ]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2.0;
    textStack.alignment = UIStackViewAlignmentLeading;
    [container addSubview:textStack];

    // "Open Profile" button (only when username is known).
    if (self.group.senderUsername.length) {
        NSString *username = self.group.senderUsername;
        // Sender pk when we have one: it skips the username -> pk lookup that
        // otherwise delays the profile appearing. Empty for group threads.
        NSString *senderPK = self.group.isGroup ? nil : self.group.senderPk;
        UIButton *openBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        openBtn.translatesAutoresizingMaskIntoConstraints = NO;
        UIImage *icon = [SPKAssetUtils instagramIconNamed:@"external_link" pointSize:18.0 renderingMode:UIImageRenderingModeAlwaysTemplate];
        if (!icon)
            icon = [UIImage systemImageNamed:@"arrow.up.right"];
        [openBtn setImage:icon forState:UIControlStateNormal];
        openBtn.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
        openBtn.accessibilityLabel = @"打开个人资料";
        [openBtn addAction:[UIAction actionWithTitle:@""
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction *a) {
                                                 [SPKUtils openInstagramProfileForUser:nil pk:senderPK username:username fromViewController:self];
                                             }]
            forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:openBtn];

        [NSLayoutConstraint activateConstraints:@[
            [openBtn.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                                   constant:-16.0],
            [openBtn.centerYAnchor constraintEqualToAnchor:avatar.centerYAnchor],
            [openBtn.widthAnchor constraintEqualToConstant:30.0],
            [openBtn.heightAnchor constraintEqualToConstant:30.0],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:openBtn.leadingAnchor
                                                               constant:-8.0],
        ]];
    } else {
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-16.0].active = YES;
    }

    // Separator line at bottom.
    UIView *separator = [UIView new];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [SPKUtils SPKColor_InstagramTertiaryBackground];
    [container addSubview:separator];

    [NSLayoutConstraint activateConstraints:@[
        [avatar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                             constant:16.0],
        [avatar.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [avatar.widthAnchor constraintEqualToConstant:36.0],
        [avatar.heightAnchor constraintEqualToConstant:36.0],
        [avatar.topAnchor constraintGreaterThanOrEqualToAnchor:container.topAnchor
                                                      constant:10.0],
        [avatar.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor
                                                      constant:-10.0],

        [textStack.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor
                                                constant:12.0],
        [textStack.centerYAnchor constraintEqualToAnchor:avatar.centerYAnchor],

        [separator.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5],
    ]];

    return container;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleMessages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPKDeletedMessageBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:SPKDeletedMessageBubbleCellReuseID forIndexPath:indexPath];
    cell.delegate = self;
    SPKDeletedMessage *message = self.visibleMessages[indexPath.row];

    UIImage *cached = message.messageId.length ? [self.thumbnailCache objectForKey:message.messageId] : nil;
    BOOL outgoing = self.ownerPK.length && [message.senderPk isEqualToString:self.ownerPK];
    [cell configureWithMessage:message thumbnail:cached outgoing:outgoing];

    // In a group, show sender avatar + name on the first bubble in each run.
    NSString *senderName = nil;
    NSString *senderPk = nil;
    NSString *senderAvatarURL = nil;
    if (self.group.isGroup && !outgoing) {
        SPKDeletedMessage *prev = indexPath.row > 0 ? self.visibleMessages[indexPath.row - 1] : nil;
        BOOL newSender = !prev || ![prev.senderPk isEqualToString:message.senderPk];
        if (newSender) {
            senderName = message.senderFullName.length ? message.senderFullName
                                                       : (message.senderUsername.length ? [@"@" stringByAppendingString:message.senderUsername] : nil);
            senderPk = message.senderPk;
            senderAvatarURL = message.senderProfilePicURL;
        }
    }
    [cell applySenderName:senderName senderPk:senderPk avatarURL:senderAvatarURL];
    if (!cached && [self messageHasThumbnail:message]) {
        [self loadThumbnailForMessage:message atIndexPath:indexPath];
    }
    return cell;
}

#pragma mark - Thumbnails

- (BOOL)messageHasThumbnail:(SPKDeletedMessage *)message {
    NSString *rel = message.thumbnailPath ?: message.mediaPath;
    if (!rel.length)
        return NO;
    NSString *path = [SPKDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:self.ownerPK];
    return (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]);
}

- (void)loadThumbnailForMessage:(SPKDeletedMessage *)message atIndexPath:(NSIndexPath *)indexPath {
    NSString *rel = message.thumbnailPath ?: message.mediaPath;
    NSString *path = [SPKDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:self.ownerPK];
    if (!path.length)
        return;
    NSString *messageId = message.messageId;

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.thumbnailQueue, ^{
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (!image)
            return;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf)
            return;
        if (messageId.length)
            [strongSelf.thumbnailCache setObject:image forKey:messageId];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Update the live cell directly (a row reload can be missed during
            // initial layout before visible rows are registered).
            SPKDeletedMessageBubbleCell *cell = (SPKDeletedMessageBubbleCell *)[strongSelf.tableView cellForRowAtIndexPath:indexPath];
            if ([cell isKindOfClass:[SPKDeletedMessageBubbleCell class]]) {
                [cell applyLoadedThumbnail:image forMessageId:messageId];
            }
        });
    });
}

#pragma mark - Bubble delegate

- (void)bubbleCell:(SPKDeletedMessageBubbleCell *)cell didTapMediaForMessage:(SPKDeletedMessage *)message {
    NSString *rel = message.mediaPath ?: message.thumbnailPath;
    NSString *path = rel.length ? [SPKDeletedMessagesStorage absolutePathForRelativePath:rel ownerPK:self.ownerPK] : nil;
    if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]) {
        // SPKFullScreenMediaPlayer detects audio/video/image by extension and
        // presents the right player — voice notes play here too.
        [SPKFullScreenMediaPlayer showFileURL:[NSURL fileURLWithPath:path]];
        return;
    }
    // Deep-link kinds (share/link) have no local blob — open the URL externally.
    NSString *urlStr = message.mediaURL.length ? message.mediaURL : message.thumbnailURL;
    NSURL *url = urlStr.length ? [NSURL URLWithString:urlStr] : nil;
    if (url)
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

#pragma mark - Context menu

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    SPKDeletedMessage *message = self.visibleMessages[indexPath.row];
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:indexPath
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
                                                        return [weakSelf contextMenuForMessage:message];
                                                    }];
}

- (UITargetedPreview *)tableView:(UITableView *)tableView previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    id identifier = configuration.identifier;
    NSIndexPath *indexPath = [identifier isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)identifier : nil;
    SPKDeletedMessageBubbleCell *cell = indexPath ? (SPKDeletedMessageBubbleCell *)[tableView cellForRowAtIndexPath:indexPath] : nil;
    return [cell isKindOfClass:SPKDeletedMessageBubbleCell.class] ? [cell contextMenuTargetedPreview] : nil;
}

- (UITargetedPreview *)tableView:(UITableView *)tableView previewForDismissingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self tableView:tableView previewForHighlightingContextMenuWithConfiguration:configuration];
}

- (UIMenu *)contextMenuForMessage:(SPKDeletedMessage *)message {
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];

    if (message.text.length || message.previewText.length) {
        UIAction *copyAction = [UIAction actionWithTitle:@"Copy Text"
                                                   image:[SPKAssetUtils menuIconNamed:@"copy"]
                                              identifier:nil
                                                 handler:^(__unused UIAction *a) {
                                                     UIPasteboard.generalPasteboard.string = message.text ?: message.previewText;
                                                     SPKNotify(kSPKNotificationUnsentMessage, @"已复制到剪贴板", nil, @"circle_check_filled", SPKNotificationToneSuccess);
                                                 }];
        [children addObject:copyAction];
    }

    NSURL *mediaURL = [self localOrRemoteURLForMessage:message];
    if (mediaURL) {
        UIAction *shareAction = [UIAction actionWithTitle:@"分享"
                                                    image:[SPKAssetUtils menuIconNamed:@"share"]
                                               identifier:nil
                                                  handler:^(__unused UIAction *a) {
                                                      UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[ mediaURL ] applicationActivities:nil];
                                                      [weakSelf presentViewController:vc animated:YES completion:nil];
                                                  }];
        [children addObject:shareAction];

        if (![mediaURL isFileURL]) {
            UIAction *copyLinkAction = [UIAction actionWithTitle:@"复制链接"
                                                           image:[SPKAssetUtils menuIconNamed:@"link"]
                                                      identifier:nil
                                                         handler:^(__unused UIAction *a) {
                                                             UIPasteboard.generalPasteboard.string = mediaURL.absoluteString;
                                                             SPKNotify(kSPKNotificationUnsentMessage, @"Copied link", nil, @"circle_check_filled", SPKNotificationToneSuccess);
                                                         }];
            [children addObject:copyLinkAction];
        }
    }

    UIAction *deleteAction = [UIAction actionWithTitle:@"删除"
                                                 image:[SPKAssetUtils menuIconNamed:@"trash"]
                                            identifier:nil
                                               handler:^(__unused UIAction *a) {
                                                   [SPKDeletedMessagesStorage deleteMessageId:message.messageId forOwnerPK:weakSelf.ownerPK];
                                               }];
    /// TODO: investigate whether native UIMenu destructive tint can be customized. UIMenuElement exposes no supported color API.
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    UIMenu *destructiveSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[ deleteAction ]];
    [children addObject:destructiveSection];

    return [UIMenu menuWithTitle:@"" children:children];
}

- (NSURL *)localOrRemoteURLForMessage:(SPKDeletedMessage *)message {
    NSString *path = [SPKDeletedMessagesStorage absolutePathForRelativePath:(message.mediaPath ?: message.thumbnailPath) ownerPK:self.ownerPK];
    if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path])
        return [NSURL fileURLWithPath:path];
    if (message.mediaURL.length)
        return [NSURL URLWithString:message.mediaURL];
    if (message.thumbnailURL.length)
        return [NSURL URLWithString:message.thumbnailURL];
    return nil;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPKDeletedMessage *message = self.visibleMessages[indexPath.row];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:nil
                                                                             handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
                                                                                 [SPKDeletedMessagesStorage deleteMessageId:message.messageId forOwnerPK:self.ownerPK];
                                                                                 completionHandler(YES);
                                                                             }];
    deleteAction.image = [SPKAssetUtils menuIconNamed:@"trash"];
    deleteAction.backgroundColor = [SPKUtils SPKColor_InstagramDestructive];
    deleteAction.accessibilityLabel = @"删除";
    return [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
}

@end
