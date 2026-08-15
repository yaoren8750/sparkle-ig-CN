#import "SPKInstantsSavedUsersViewController.h"

#import "../../Utils.h"
#import "../ActionButton/ActionButtonLookupUtils.h"
#import "../Gallery/SPKGalleryCoreDataStack.h"
#import "../Gallery/SPKGalleryFile.h"
#import "../Gallery/SPKGalleryLockViewController.h"
#import "../Gallery/SPKGalleryManager.h"
#import "../Gallery/SPKGalleryViewController.h"
#import "../Messages/SPKDirectUserResolver.h"
#import "../UI/SPKChrome.h"
#import "../UI/SPKMediaChrome.h"

/// One author's saved Instants, as counted straight out of the Gallery.
@interface SPKInstantsSavedUser : NSObject
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy, nullable) NSString *pk;
@property (nonatomic, assign) NSUInteger count;
@property (nonatomic, strong, nullable) NSDate *lastSaved;
@end

@implementation SPKInstantsSavedUser
@end

/// Fetches every Instant in the Gallery, folded into one entry per author.
///
/// A dictionary fetch rather than object faults: this only needs four scalar columns, and
/// the list is rebuilt every time the sheet opens.
static NSArray<SPKInstantsSavedUser *> *SPKInstantsSavedUsers(void) {
    NSManagedObjectContext *ctx = [SPKGalleryCoreDataStack shared].viewContext;
    if (!ctx)
        return @[];

    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    request.resultType = NSDictionaryResultType;
    request.propertiesToFetch = @[ @"sourceUsername", @"sourceUserPK", @"dateAdded" ];
    request.predicate = [NSPredicate predicateWithFormat:@"source == %@ AND sourceUsername != nil AND sourceUsername != %@",
                                                         @(SPKGallerySourceInstants), @""];

    NSArray<NSDictionary *> *rows = [ctx executeFetchRequest:request error:nil];
    if (rows.count == 0)
        return @[];

    // Usernames are matched case-insensitively everywhere else in the Gallery (the filter
    // predicate uses ==[c]), so fold on a lowercase key and keep the first spelling seen.
    NSMutableDictionary<NSString *, SPKInstantsSavedUser *> *byKey = [NSMutableDictionary dictionary];
    for (NSDictionary *row in rows) {
        NSString *username = [SPKStringFromValue(row[@"sourceUsername"])
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (username.length == 0)
            continue;

        NSString *key = username.lowercaseString;
        SPKInstantsSavedUser *entry = byKey[key];
        if (!entry) {
            entry = [SPKInstantsSavedUser new];
            entry.username = username;
            byKey[key] = entry;
        }
        entry.count++;
        if (entry.pk.length == 0)
            entry.pk = SPKStringFromValue(row[@"sourceUserPK"]);

        NSDate *dateAdded = [row[@"dateAdded"] isKindOfClass:NSDate.class] ? row[@"dateAdded"] : nil;
        if (dateAdded && (!entry.lastSaved || [dateAdded compare:entry.lastSaved] == NSOrderedDescending))
            entry.lastSaved = dateAdded;
    }

    // Most recently saved first: the person whose Instant you just kept is the one you are
    // most likely looking for.
    return [byKey.allValues sortedArrayUsingComparator:^NSComparisonResult(SPKInstantsSavedUser *a, SPKInstantsSavedUser *b) {
        if (a.lastSaved && b.lastSaved && ![a.lastSaved isEqualToDate:b.lastSaved])
            return [b.lastSaved compare:a.lastSaved];
        if (a.lastSaved && !b.lastSaved)
            return NSOrderedAscending;
        if (!a.lastSaved && b.lastSaved)
            return NSOrderedDescending;
        return [a.username localizedCaseInsensitiveCompare:b.username];
    }];
}

@implementation SPKInstantsSavedUsersViewController

+ (BOOL)hasSavedInstants {
    NSManagedObjectContext *ctx = [SPKGalleryCoreDataStack shared].viewContext;
    if (!ctx)
        return NO;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    request.predicate = [NSPredicate predicateWithFormat:@"source == %@ AND sourceUsername != nil AND sourceUsername != %@",
                                                         @(SPKGallerySourceInstants), @""];
    request.fetchLimit = 1;
    return [ctx countForFetchRequest:request error:nil] > 0;
}

+ (void)presentFromViewController:(UIViewController *)presenter {
    if (!presenter)
        presenter = topMostController();
    while (presenter.presentedViewController)
        presenter = presenter.presentedViewController;
    if (!presenter)
        return;

    __weak UIViewController *weakPresenter = presenter;
    void (^present)(void) = ^{
        // The unlock screen may have come and gone in between, so fall back to whatever is
        // on top if the original presenter left the hierarchy.
        UIViewController *target = weakPresenter.view.window ? weakPresenter : topMostController();
        while (target.presentedViewController)
            target = target.presentedViewController;
        if (!target)
            return;
        SPKInstantsSavedUsersViewController *vc = [[SPKInstantsSavedUsersViewController alloc] init];
        UINavigationController *nav = [[SPKChromeNavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [target presentViewController:nav animated:YES completion:nil];
    };

    // The list names everyone whose Instants you kept, so it is behind the same lock as
    // the Gallery it reads from -- and authenticating here means no flash of the list.
    SPKGalleryManager *manager = [SPKGalleryManager sharedManager];
    if (manager.isLockEnabled && !manager.isUnlocked) {
        [SPKGalleryLockViewController presentUnlockFromViewController:presenter
                                                          completion:^(BOOL success) {
                                                              if (success)
                                                                  present();
                                                          }];
    } else {
        present();
    }
}

- (instancetype)init {
    if ((self = [super init])) {
        self.title = @"已保存快拍";
        self.allowsDelete = NO;
        self.emptyTitle = @"No saved instants";
        self.emptySubtitle = @"你保存或自动保存的快拍会显示在这里，并按发送者分类。";
        self.emptySearchSubtitle = @"没有符合搜索条件的账户。";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    SPKMediaChromeSetLeadingTopBarItems(self.navigationItem,
                                        @[ SPKMediaChromeTopBarButtonItem(@"xmark", self, @selector(spk_closeTapped)) ]);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Counts change while the sheet is open (the user browsed a folder and deleted, or an
    // auto-save landed), so rebuild rather than trusting the load-time snapshot.
    [self reloadItems];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Re-lock on the way out, the way the Gallery does when it is dismissed: the gallery
    // pushed from here is not the root of this stack, so its own re-lock never runs.
    if ((self.isBeingDismissed || self.navigationController.isBeingDismissed) &&
        [SPKGalleryManager sharedManager].isLockEnabled) {
        [[SPKGalleryManager sharedManager] lockGallery];
    }
}

- (void)spk_closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSArray<SPKUserListItem *> *)buildItems {
    NSMutableArray<SPKUserListItem *> *items = [NSMutableArray array];
    for (SPKInstantsSavedUser *user in SPKInstantsSavedUsers()) {
        SPKUserListItem *item = [SPKUserListItem new];
        item.pk = user.pk;
        item.title = [@"@" stringByAppendingString:user.username];
        item.subtitle = user.count == 1 ? @"1 instant"
                                        : [NSString stringWithFormat:@"%lu instants", (unsigned long)user.count];
        if (user.pk.length > 0)
            item.avatarURLString = spkDirectUserResolverProfilePicURLStringForPK(user.pk);
        item.representedObject = user;
        [items addObject:item];
    }
    return items;
}

- (void)didSelectItem:(SPKUserListItem *)item {
    SPKInstantsSavedUser *user = [item.representedObject isKindOfClass:SPKInstantsSavedUser.class] ? item.representedObject : nil;
    if (user.username.length == 0)
        return;
    // Pushed into this sheet's navigation stack rather than presented on top of it: a
    // second sheet sliding up over the first reads as a detour, a push reads as going one
    // level deeper. The gallery renders a back chevron for us when it isn't the root.
    SPKGalleryViewController *gallery =
        [SPKGalleryViewController galleryFilteredToSources:[NSSet setWithObject:@(SPKGallerySourceInstants)]
                                                usernames:[NSSet setWithObject:user.username]
                                                    title:item.title];
    [self.navigationController pushViewController:gallery animated:YES];
}

@end
