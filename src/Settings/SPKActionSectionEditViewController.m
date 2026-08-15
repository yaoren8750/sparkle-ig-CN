#import "SPKActionSectionEditViewController.h"
#import "../Shared/UI/SPKSwitch.h"
#import "SPKActionSectionIconPickerViewController.h"
#import "SPKInstagramIconCatalog.h"
#import "SPKTopicSettingsSupport.h"

#import "../AssetUtils.h"
#import "../Shared/ActionButton/SPKActionDescriptor.h"
#import "../Utils.h"

static char kSPKSectionEditFieldAssocKey;
static char kSPKSectionEditSwitchAssocKey;

@interface SPKActionSectionEditViewController () <UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate, UITableViewDropDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) SPKActionButtonConfiguration *configuration;
@property (nonatomic, copy) NSString *sectionIdentifier;
@property (nonatomic, copy) dispatch_block_t onChange;

@end

@implementation SPKActionSectionEditViewController

- (UIView *)selectionBackgroundView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [SPKUtils SPKColor_InstagramPressedBackground];
    return view;
}

- (NSString *)displayTitleForSectionIconName:(NSString *)iconName {
    for (SPKActionDescriptor *descriptor in [SPKActionDescriptor availableSectionIconDescriptors]) {
        if ([descriptor.iconName isEqualToString:iconName]) {
            return descriptor.title ?: iconName;
        }
    }
    return [SPKInstagramIconCatalog displayNameForIconName:iconName];
}

- (void)showIconPicker {
    SPKActionMenuSection *section = [self currentSection];
    if (!section)
        return;

    __weak typeof(self) weakSelf = self;
    SPKActionSectionIconPickerViewController *controller = [[SPKActionSectionIconPickerViewController alloc] initWithSelectedIconName:section.iconName
                                                                                                                             onSelect:^(NSString *iconName) {
                                                                                                                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                                                                                 if (!strongSelf)
                                                                                                                                     return;
                                                                                                                                 SPKActionMenuSection *strongSection = [strongSelf currentSection];
                                                                                                                                 strongSection.iconName = iconName;
                                                                                                                                 [strongSelf.configuration save];
                                                                                                                                 if (strongSelf.onChange)
                                                                                                                                     strongSelf.onChange();
                                                                                                                                 [strongSelf.tableView reloadData];
                                                                                                                             }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (instancetype)initWithConfiguration:(SPKActionButtonConfiguration *)configuration
                    sectionIdentifier:(NSString *)sectionIdentifier
                             onChange:(dispatch_block_t)onChange {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _sectionIdentifier = [sectionIdentifier copy];
        _onChange = [onChange copy];
        self.title = @"编辑分组";
    }
    return self;
}

- (SPKActionMenuSection *)currentSection {
    return [self.configuration sectionWithIdentifier:self.sectionIdentifier];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    self.tableView.backgroundColor = [SPKUtils SPKColor_InstagramGroupedBackground];
    self.tableView.separatorColor = [SPKUtils SPKColor_InstagramSeparator];
    self.tableView.tintColor = [SPKUtils SPKColor_InstagramBlue];
    [self.view addSubview:self.tableView];
}

- (BOOL)isBulkSection {
    return [[self currentSection].identifier isEqualToString:@"bulk"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // The Bulk section's contents are derived from the single-item actions, so it
    // only exposes the Section header (title/icon/collapsible) — no assignable
    // action lists.
    return [self isBulkSection] ? 1 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0)
        return 3;
    if (section == 1)
        return [self currentSection].actions.count;
    return self.configuration.supportedActions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0)
        return @"分组";
    if (section == 1)
        return @"Actions in This Section";
    return @"Available Actions";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self isBulkSection]) {
        return section == 0 ? @"Bulk shows Download All / Copy All / Select Media on carousels. Its actions and order are derived from your single-item Download and Copy actions.\nReorder or rename this section to control where Bulk appears in the menu." : nil;
    }
    if (section == 1)
        return @"Drag to reorder actions in this section. Remove an action to send it to the unassigned bucket.";
    if (section == 2)
        return @"Tap an action to assign it here. If it is already in another section, it will move.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SPKActionMenuSection *section = [self currentSection];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    UIListContentConfiguration *config = cell.defaultContentConfiguration;
    UIImage *deferredIconAccessoryImage = nil;
    cell.backgroundColor = [SPKUtils SPKColor_InstagramSecondaryBackground];
    cell.tintColor = [SPKUtils SPKColor_InstagramBlue];
    cell.selectedBackgroundView = [self selectionBackgroundView];
    config.textProperties.color = [SPKUtils SPKColor_InstagramPrimaryText];
    config.secondaryTextProperties.color = [SPKUtils SPKColor_InstagramSecondaryText];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            config.text = @"Title";
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 180, 30)];
            field.textAlignment = NSTextAlignmentRight;
            field.placeholder = @"分组";
            field.text = section.title;
            field.returnKeyType = UIReturnKeyDone;
            field.delegate = self;
            objc_setAssociatedObject(field, &kSPKSectionEditFieldAssocKey, self, OBJC_ASSOCIATION_ASSIGN);
            [field addTarget:self action:@selector(titleFieldChanged:) forControlEvents:UIControlEventEditingChanged];
            cell.accessoryView = field;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            config.text = @"Choose Icon";
            config.secondaryText = nil;
            config.image = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

            UIImage *iconImage = SPKSettingsIcon(section.iconName);
            if (iconImage) {
                deferredIconAccessoryImage = iconImage;
            }

            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (indexPath.row == 2) {
            config.text = @"Collapsible";
            SPKSwitch *toggle = [[SPKSwitch alloc] init];
            toggle.on = section.collapsible;
            objc_setAssociatedObject(toggle, &kSPKSectionEditSwitchAssocKey, self, OBJC_ASSOCIATION_ASSIGN);
            [toggle addTarget:self action:@selector(collapsibleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 1) {
        NSString *identifier = section.actions[indexPath.row];
        config.text = SPKActionDescriptorDisplayTitle(identifier, self.configuration.topicTitle);
        config.image = SPKSettingsIcon(SPKActionDescriptorIconName(identifier));
        config.imageProperties.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];
        cell.showsReorderControl = YES;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        NSString *identifier = self.configuration.supportedActions[indexPath.row];
        config.text = SPKActionDescriptorDisplayTitle(identifier, self.configuration.topicTitle);
        config.image = SPKSettingsIcon(SPKActionDescriptorIconName(identifier));
        config.imageProperties.tintColor = [SPKUtils SPKColor_InstagramPrimaryText];

        NSString *owner = [self.configuration sectionIdentifierForAction:identifier];
        if ([owner isEqualToString:section.identifier]) {
            UIImageView *checkmarkView = [[UIImageView alloc] initWithImage:[SPKAssetUtils instagramIconNamed:@"circle_check_filled"]];
            checkmarkView.tintColor = [SPKUtils SPKColor_InstagramBlue];
            cell.accessoryView = checkmarkView;
            config.secondaryText = nil;
        } else {
            cell.accessoryView = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
            if (owner.length > 0) {
                SPKActionMenuSection *ownerSection = [self.configuration sectionWithIdentifier:owner];
                config.secondaryText = ownerSection.title;
            } else {
                config.secondaryText = @"Unassigned";
            }
        }
    }

    cell.contentConfiguration = config;
    if (deferredIconAccessoryImage) {
        UIImageView *iconView = [[UIImageView alloc] initWithImage:deferredIconAccessoryImage];
        iconView.tintColor = [SPKUtils SPKColor_InstagramSecondaryText];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:iconView];
        [NSLayoutConstraint activateConstraints:@[
            [iconView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [iconView.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [iconView.widthAnchor constraintEqualToConstant:24.0],
            [iconView.heightAnchor constraintEqualToConstant:24.0]
        ]];
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1)
        return @[];
    NSString *identifier = [self currentSection].actions[indexPath.row];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:identifier]];
    item.localObject = identifier;
    return @[ item ];
}

- (BOOL)tableView:(UITableView *)tableView dragSessionAllowsMoveOperation:(id<UIDragSession>)session {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView dragSessionIsRestrictedToDraggingApplication:(id<UIDragSession>)session {
    return YES;
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    if (session.localDragSession == nil || destinationIndexPath.section != 1) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *destinationIndexPath = coordinator.destinationIndexPath;
    id<UITableViewDropItem> dropItem = coordinator.items.firstObject;
    NSIndexPath *sourceIndexPath = dropItem.sourceIndexPath;
    if (!destinationIndexPath || !sourceIndexPath || sourceIndexPath.section != 1 || destinationIndexPath.section != 1)
        return;

    NSInteger rowCount = [self currentSection].actions.count;
    NSInteger destinationRow = MIN(MAX(0, destinationIndexPath.row), MAX(0, rowCount - 1));
    NSIndexPath *target = [NSIndexPath indexPathForRow:destinationRow inSection:1];

    [tableView
        performBatchUpdates:^{
            [self.configuration moveActionInSectionIdentifier:self.sectionIdentifier fromIndex:sourceIndexPath.row toIndex:target.row];
            [self.configuration save];
            if (self.onChange)
                self.onChange();
            [tableView moveRowAtIndexPath:sourceIndexPath toIndexPath:target];
        }
                 completion:nil];
    [coordinator dropItem:dropItem.dragItem toRowAtIndexPath:target];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 1) {
        [self showIconPicker];
    } else if (indexPath.section == 1) {
        NSString *identifier = [self currentSection].actions[indexPath.row];
        [self.configuration setAction:identifier assignedToSectionIdentifier:nil];
        [self.configuration save];
        if (self.onChange)
            self.onChange();
        [self.tableView reloadData];
    } else if (indexPath.section == 2) {
        NSString *identifier = self.configuration.supportedActions[indexPath.row];
        NSString *owner = [self.configuration sectionIdentifierForAction:identifier];
        if ([owner isEqualToString:self.sectionIdentifier]) {
            [self.configuration setAction:identifier assignedToSectionIdentifier:nil];
        } else {
            [self.configuration setAction:identifier assignedToSectionIdentifier:self.sectionIdentifier];
        }
        [self.configuration save];
        if (self.onChange)
            self.onChange();
        [self.tableView reloadData];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)titleFieldChanged:(UITextField *)sender {
    SPKActionMenuSection *section = [self currentSection];
    section.title = sender.text.length > 0 ? sender.text : @"分组";
    [self.configuration save];
    if (self.onChange)
        self.onChange();
}

- (void)collapsibleSwitchChanged:(UISwitch *)sender {
    SPKActionMenuSection *section = [self currentSection];
    section.collapsible = sender.isOn;
    [self.configuration save];
    if (self.onChange)
        self.onChange();
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

@end
