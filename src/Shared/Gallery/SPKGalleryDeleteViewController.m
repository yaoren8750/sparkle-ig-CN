#import "SPKGalleryDeleteViewController.h"
#import "../../AssetUtils.h"
#import "../../Utils.h"
#import "../UI/SPKIGAlertPresenter.h"
#import "SPKGalleryCoreDataStack.h"
#import "SPKGalleryFile.h"

typedef NS_ENUM(NSInteger, SPKGalleryDeleteSection) {
    SPKGalleryDeleteSectionGlobal = 0,
    SPKGalleryDeleteSectionType,
    SPKGalleryDeleteSectionSource,
    SPKGalleryDeleteSectionUser,
    SPKGalleryDeleteSectionCount
};

@interface SPKGalleryDeleteAction : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong, nullable) NSPredicate *predicate;
@property (nonatomic, copy, nullable) NSString *successTitle;
@property (nonatomic, assign) BOOL navigatesToUsers;
@end

@implementation SPKGalleryDeleteAction
@end

@interface SPKGalleryDeleteUserItem : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, assign) NSInteger count;
@end

@implementation SPKGalleryDeleteUserItem
@end

@interface SPKGalleryDeleteViewController ()
@property (nonatomic, assign) SPKGalleryDeletePageMode mode;
@property (nonatomic, strong) NSArray<NSArray<SPKGalleryDeleteAction *> *> *sections;
@property (nonatomic, strong) NSArray<SPKGalleryDeleteUserItem *> *users;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *countCache;
@end

@implementation SPKGalleryDeleteViewController

- (UIView *)selectionBackgroundView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [SPKUtils SPKColor_InstagramPressedBackground];
    return view;
}

- (instancetype)initWithMode:(SPKGalleryDeletePageMode)mode {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _mode = mode;
        _countCache = @{};
        _sections = @[];
        _users = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.mode == SPKGalleryDeletePageModeRoot ? @"Delete Files" : @"Delete by User";
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SPKUtils SPKColor_InstagramSeparator];
    self.tableView.tintColor = [SPKUtils SPKColor_InstagramBlue];
    [self reloadDataModel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadDataModel];
    [self.tableView reloadData];
}

- (SPKGalleryDeleteAction *)actionWithTitle:(NSString *)title
                                   iconName:(NSString *)iconName
                                  predicate:(nullable NSPredicate *)predicate
                               successTitle:(nullable NSString *)successTitle {
    SPKGalleryDeleteAction *action = [SPKGalleryDeleteAction new];
    action.title = title;
    action.iconName = iconName;
    action.predicate = predicate;
    action.successTitle = successTitle;
    return action;
}

- (void)reloadDataModel {
    if (self.mode == SPKGalleryDeletePageModeUsers) {
        [self reloadUsers];
        return;
    }

    self.sections = @[
        @[ [self actionWithTitle:@"Delete All Files" iconName:@"trash" predicate:nil successTitle:@"All files deleted"] ],
        @[
            [self actionWithTitle:@"Delete All Images"
                         iconName:@"photo"
                        predicate:[NSPredicate predicateWithFormat:@"mediaType == %d", SPKGalleryMediaTypeImage]
                     successTitle:@"Images deleted"],
            [self actionWithTitle:@"Delete All Videos"
                         iconName:@"video"
                        predicate:[NSPredicate predicateWithFormat:@"mediaType == %d", SPKGalleryMediaTypeVideo]
                     successTitle:@"Videos deleted"],
            [self actionWithTitle:@"Delete All Audio"
                         iconName:@"audio"
                        predicate:[NSPredicate predicateWithFormat:@"mediaType == %d", SPKGalleryMediaTypeAudio]
                     successTitle:@"Audio deleted"]
        ],
        @[
            [self actionWithTitle:@"Delete Feed Posts"
                         iconName:@"feed"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceFeed]
                     successTitle:@"Feed posts deleted"],
            [self actionWithTitle:@"Delete Stories"
                         iconName:@"story"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceStories]
                     successTitle:@"Stories deleted"],
            [self actionWithTitle:@"Delete Reels"
                         iconName:@"reels"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceReels]
                     successTitle:@"Reels deleted"],
            [self actionWithTitle:@"Delete Thumbnails"
                         iconName:@"photo_gallery"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceThumbnail]
                     successTitle:@"Thumbnails deleted"],
            [self actionWithTitle:@"Delete DM Media"
                         iconName:@"messages"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceDMs]
                     successTitle:@"DM media deleted"],
            [self actionWithTitle:@"Delete Profile Pictures"
                         iconName:@"user_circle"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceProfile]
                     successTitle:@"Profile pictures deleted"],
            [self actionWithTitle:@"Delete Instants"
                         iconName:@"instants"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceInstants]
                     successTitle:@"Instants deleted"],
            [self actionWithTitle:@"Delete Audio Page Media"
                         iconName:@"audio_page"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceAudioPage]
                     successTitle:@"Audio page media deleted"],
            [self actionWithTitle:@"Delete Comment Media"
                         iconName:@"comment"
                        predicate:[NSPredicate predicateWithFormat:@"source == %d", SPKGallerySourceComments]
                     successTitle:@"Comment media deleted"]
        ],
        @[]
    ];

    SPKGalleryDeleteAction *usersAction = [self actionWithTitle:@"Delete by User" iconName:@"users" predicate:nil successTitle:nil];
    usersAction.navigatesToUsers = YES;
    self.sections = @[
        self.sections[0],
        self.sections[1],
        self.sections[2],
        @[ usersAction ]
    ];

    [self rebuildCountCache];
}

- (void)rebuildCountCache {
    NSManagedObjectContext *ctx = [SPKGalleryCoreDataStack shared].viewContext;
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (NSArray<SPKGalleryDeleteAction *> *section in self.sections) {
        for (SPKGalleryDeleteAction *action in section) {
            if (action.navigatesToUsers) {
                continue;
            }
            NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
            req.predicate = action.predicate;
            NSInteger count = [ctx countForFetchRequest:req error:nil];
            counts[action.title] = @(MAX(count, 0));
        }
    }

    NSFetchRequest *distinctReq = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    distinctReq.resultType = NSDictionaryResultType;
    distinctReq.propertiesToFetch = @[ @"sourceUsername" ];
    distinctReq.returnsDistinctResults = YES;
    NSArray<NSDictionary *> *rows = [ctx executeFetchRequest:distinctReq error:nil] ?: @[];
    NSInteger userCount = 0;
    for (__unused NSDictionary *row in rows) {
        userCount += 1;
    }
    counts[@"Delete by User"] = @(userCount);
    self.countCache = counts;
}

- (void)reloadUsers {
    NSManagedObjectContext *ctx = [SPKGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    NSArray<SPKGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];

    NSMutableDictionary<NSString *, SPKGalleryDeleteUserItem *> *items = [NSMutableDictionary dictionary];
    for (SPKGalleryFile *file in files) {
        NSString *username = [file.sourceUsername stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *key = username.length > 0 ? username : @"__unknown__";
        SPKGalleryDeleteUserItem *item = items[key];
        if (!item) {
            item = [SPKGalleryDeleteUserItem new];
            item.username = username.length > 0 ? username : nil;
            item.displayName = username.length > 0 ? username : @"Unknown User";
            items[key] = item;
        }
        item.count += 1;
    }

    self.users = [[items allValues] sortedArrayUsingComparator:^NSComparisonResult(SPKGalleryDeleteUserItem *lhs, SPKGalleryDeleteUserItem *rhs) {
        return [lhs.displayName localizedCaseInsensitiveCompare:rhs.displayName];
    }];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.mode == SPKGalleryDeletePageModeUsers) {
        return nil;
    }
    switch (section) {
    case SPKGalleryDeleteSectionGlobal:
        return nil;
    case SPKGalleryDeleteSectionType:
        return @"Delete by Type";
    case SPKGalleryDeleteSectionSource:
        return @"Delete by Source";
    case SPKGalleryDeleteSectionUser:
        return @"Delete by User";
    }
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.mode == SPKGalleryDeletePageModeUsers ? 1 : self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.mode == SPKGalleryDeletePageModeUsers) {
        return self.users.count;
    }
    return self.sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    }
    cell.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];
    cell.selectedBackgroundView = [self selectionBackgroundView];
    cell.textLabel.textColor = [SPKUtils SPKColor_InstagramDestructive];
    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.textColor = [SPKUtils SPKColor_InstagramSecondaryText];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.tintColor = [SPKUtils SPKColor_InstagramDestructive];

    if (self.mode == SPKGalleryDeletePageModeUsers) {
        SPKGalleryDeleteUserItem *item = self.users[indexPath.row];
        cell.textLabel.text = item.displayName;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)item.count];
        cell.imageView.image = [SPKAssetUtils instagramIconNamed:@"user" pointSize:24.0];
        return cell;
    }

    SPKGalleryDeleteAction *action = self.sections[indexPath.section][indexPath.row];
    cell.textLabel.text = action.title;
    NSNumber *count = self.countCache[action.title];
    if (count) {
        cell.detailTextLabel.text = count.integerValue > 0 ? [NSString stringWithFormat:@"%ld", (long)count.integerValue] : nil;
    }
    cell.imageView.image = [SPKAssetUtils instagramIconNamed:action.iconName pointSize:24.0];
    cell.accessoryType = action.navigatesToUsers ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.mode == SPKGalleryDeletePageModeUsers) {
        SPKGalleryDeleteUserItem *item = self.users[indexPath.row];
        NSPredicate *predicate = item.username.length > 0
                                     ? [NSPredicate predicateWithFormat:@"sourceUsername == %@", item.username]
                                     : [NSPredicate predicateWithFormat:@"sourceUsername == nil OR sourceUsername == ''"];
        NSString *title = [NSString stringWithFormat:@"Delete %@?", item.displayName];
        [self confirmDeleteWithTitle:title predicate:predicate successTitle:@"User files deleted"];
        return;
    }

    SPKGalleryDeleteAction *action = self.sections[indexPath.section][indexPath.row];
    if (action.navigatesToUsers) {
        SPKGalleryDeleteViewController *vc = [[SPKGalleryDeleteViewController alloc] initWithMode:SPKGalleryDeletePageModeUsers];
        vc.onDidDelete = self.onDidDelete;
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    [self confirmDeleteWithTitle:action.title predicate:action.predicate successTitle:action.successTitle ?: @"Files deleted"];
}

- (void)confirmDeleteWithTitle:(NSString *)title predicate:(nullable NSPredicate *)predicate successTitle:(NSString *)successTitle {
    NSManagedObjectContext *ctx = [SPKGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SPKGalleryFile"];
    req.predicate = predicate;
    NSArray<SPKGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];
    if (files.count == 0) {
        SPKNotify(kSPKNotificationGalleryBulkDelete, @"No files to delete", nil, @"error_filled", SPKNotificationToneError);
        return;
    }

    NSString *message = [NSString stringWithFormat:@"This will permanently remove %ld file%@.", (long)files.count, files.count == 1 ? @"" : @"s"];
    [SPKIGAlertPresenter presentAlertFromViewController:self
                                                  title:title
                                                message:message
                                                actions:@[
                                                    [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                style:SPKIGAlertActionStyleCancel
                                                                              handler:nil],
                                                    [SPKIGAlertAction actionWithTitle:@"删除"
                                                                                style:SPKIGAlertActionStyleDestructive
                                                                              handler:^{
                                                                                  NSFileManager *fm = [NSFileManager defaultManager];
                                                                                  for (SPKGalleryFile *file in files) {
                                                                                      NSString *filePath = file.filePath;
                                                                                      if ([fm fileExistsAtPath:filePath]) {
                                                                                          [fm removeItemAtPath:filePath error:nil];
                                                                                      }
                                                                                      NSString *thumbPath = file.thumbnailPath;
                                                                                      if ([fm fileExistsAtPath:thumbPath]) {
                                                                                          [fm removeItemAtPath:thumbPath error:nil];
                                                                                      }
                                                                                      [ctx deleteObject:file];
                                                                                  }
                                                                                  [ctx save:nil];
                                                                                  [self reloadDataModel];
                                                                                  [self.tableView reloadData];
                                                                                  if (self.onDidDelete) {
                                                                                      self.onDidDelete();
                                                                                  }
                                                                                  SPKNotify(kSPKNotificationGalleryBulkDelete, successTitle, nil, @"circle_check_filled", SPKNotificationToneSuccess);
                                                                              }],
                                                ]];
}

@end
