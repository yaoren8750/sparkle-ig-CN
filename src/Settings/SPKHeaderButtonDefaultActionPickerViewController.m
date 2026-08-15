#import "SPKHeaderButtonDefaultActionPickerViewController.h"

#import "../AssetUtils.h"
#import "../Features/Feed/HeaderActionButton.h"
#import "../Utils.h"

static NSString *const kSPKHeaderPickerCellIdentifier = @"SPKHeaderDefaultPickerCell";

// A picker row: an identifier ("menu" or a destination id), a display title, and
// an IG-bundle icon name.
@interface SPKHeaderPickerRow : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@end

@implementation SPKHeaderPickerRow
@end

@interface SPKHeaderButtonDefaultActionPickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SPKHeaderPickerRow *> *rows;
@end

@implementation SPKHeaderButtonDefaultActionPickerViewController

- (NSArray<SPKHeaderPickerRow *> *)buildRows {
    NSMutableArray<SPKHeaderPickerRow *> *rows = [NSMutableArray array];

    SPKHeaderPickerRow *menuRow = [SPKHeaderPickerRow new];
    menuRow.identifier = @"menu";
    menuRow.title = @"打开操作菜单";
    menuRow.iconName = @"action";
    [rows addObject:menuRow];

    for (SPKHeaderDestination *destination in SPKHeaderButtonEnabledDestinations()) {
        SPKHeaderPickerRow *row = [SPKHeaderPickerRow new];
        row.identifier = destination.identifier;
        row.title = destination.title;
        row.iconName = destination.iconName;
        [rows addObject:row];
    }
    return rows;
}

- (UIView *)selectionBackgroundView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [SPKUtils SPKColor_InstagramPressedBackground];
    return view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"默认点击操作";
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.rows = [self buildRows];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SPKUtils SPKColor_InstagramSeparator];
    self.tableView.tintColor = [SPKUtils SPKColor_InstagramBlue];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kSPKHeaderPickerCellIdentifier];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Rebuild each time: the enabled-destination set can change between opens, and
    // this VC instance is reused by the settings row.
    self.rows = [self buildRows];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"选择单击按钮时执行的操作。长按始终打开已启用操作的菜单。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSPKHeaderPickerCellIdentifier forIndexPath:indexPath];
    SPKHeaderPickerRow *row = self.rows[indexPath.row];

    UIListContentConfiguration *config = cell.defaultContentConfiguration;
    config.text = row.title;
    config.textProperties.color = [SPKUtils SPKColor_InstagramPrimaryText];
    config.image = [[SPKAssetUtils instagramIconNamed:row.iconName pointSize:24.0] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    config.imageProperties.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
    cell.contentConfiguration = config;

    cell.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];
    cell.tintColor = [SPKUtils SPKColor_InstagramBlue];
    cell.selectedBackgroundView = [self selectionBackgroundView];

    if ([row.identifier isEqualToString:SPKHeaderButtonResolvedDefaultActionIdentifier()]) {
        UIImageView *checkmark = [[UIImageView alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"circle_check_filled"]];
        checkmark.tintColor = [SPKUtils SPKColor_InstagramBlue];
        cell.accessoryView = checkmark;
    } else {
        cell.accessoryView = nil;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    SPKHeaderPickerRow *row = self.rows[indexPath.row];
    SPKPreferenceSetObject(row.identifier, kSPKHeaderButtonDefaultActionKey);
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
