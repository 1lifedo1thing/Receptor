#import "RCPackagesViewController.h"
#import "RCRespring.h"
#import "ReceptorUI.h"

@implementation RCPackagesViewController
- (id)initWithMode:(NSString *)mode item:(NSDictionary *)item {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) { _mode = [mode copy]; _selection = [item copy]; _message = [@"Close Cydia completely before changing sources/packages. Keep Receptor open until operations finish. APT uses the device’s networking and certificate support." copy]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = [_mode isEqual:@"root"] ? @"Packages" : [_mode capitalizedString];
    if ([_mode isEqual:@"package"]) self.title = [_selection objectForKey:@"Name"] ?: [_selection objectForKey:@"Package"];
    if ([_mode isEqual:@"plan"]) {
        self.title = @"Review changes";
        UITextView *text = [[[UITextView alloc] initWithFrame:self.view.bounds] autorelease]; text.editable = NO;
        text.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, MAX(250, self.tableView.bounds.size.height - 120));
        text.text = [_plan objectForKey:@"output"]; text.font = [UIFont fontWithName:@"Courier" size:12]; text.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.tableView.tableHeaderView = text;
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Confirm" style:UIBarButtonItemStyleDone target:self action:@selector(confirmPlan)] autorelease]; return;
    }
    if ([_mode isEqual:@"sources"]) {
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addSource)] autorelease];
        [self begin:[NSArray arrayWithObject:@"sources"]];
    }
    if ([_mode isEqual:@"installed"] || [_mode isEqual:@"search"]) {
        _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,44)]; _search.delegate = self;
        _search.placeholder = [_mode isEqual:@"search"] ? @"Package name — tap Search" : @"Filter installed packages"; self.tableView.tableHeaderView = _search;
        if ([_mode isEqual:@"installed"]) [self begin:[NSArray arrayWithObject:@"installed"]];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:YES animated:animated];
    if (_items && ![[RCPackageManager sharedManager] busy] && ([_mode isEqual:@"installed"] || [_mode isEqual:@"sources"])) [self begin:[NSArray arrayWithObject:_mode]];
}
- (void)begin:(NSArray *)arguments {
    if ([[RCPackageManager sharedManager] run:arguments delegate:self]) {
        [_pending release]; _pending = [arguments copy]; [_message release]; _message = [@"Working… Keep Receptor open. Package operations cannot be cancelled halfway through." copy];
        self.navigationItem.rightBarButtonItem.enabled = NO;
        if ([_mode isEqual:@"plan"]) ((UITextView *)self.tableView.tableHeaderView).text = [NSString stringWithFormat:@"Operation running. Keep Receptor open…\n\n%@", [_plan objectForKey:@"output"]];
        else [self.tableView reloadData];
    }
}
- (void)showText:(NSString *)text title:(NSString *)title {
    UIViewController *controller = [[UIViewController alloc] init]; controller.title = title;
    UITextView *view = [[UITextView alloc] initWithFrame:self.view.bounds]; view.editable = NO; view.text = text ?: @"No output.";
    view.font = [UIFont fontWithName:@"Courier" size:12]; view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; controller.view = view; [view release];
    controller.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Respring" style:UIBarButtonItemStylePlain target:[RCRespring sharedController] action:@selector(requestRespring)] autorelease];
    [self.navigationController pushViewController:controller animated:YES]; [controller release];
}
- (void)filter {
    NSMutableArray *items = [NSMutableArray array]; NSString *query = _search.text ?: @"";
    for (NSDictionary *item in _items) {
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@", [item objectForKey:@"Package"] ?: @"", [item objectForKey:@"Name"] ?: @"", [item objectForKey:@"Description"] ?: @""];
        if (![_mode isEqual:@"installed"] || ![query length] || [text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) [items addObject:item];
    }
    [_visible release]; _visible = [items copy]; [self.tableView reloadData];
}
- (void)packageOperationFinished:(NSDictionary *)result {
    self.navigationItem.rightBarButtonItem.enabled = YES;
    if ([_mode isEqual:@"plan"]) ((UITextView *)self.tableView.tableHeaderView).text = [_plan objectForKey:@"output"];
    NSString *failure = [result objectForKey:@"error"];
    if (!failure && [[result objectForKey:@"status"] intValue]) failure = [result objectForKey:@"output"] ?: @"APT failed. Check the operation log.";
    [_message release]; _message = [failure ?: [result objectForKey:@"output"] ?: @"Loaded. Refresh indexes to find newly added sources/packages." copy];
    if ([_message length] > 400) { NSString *shortMessage = [[_message substringToIndex:400] stringByAppendingString:@"… See the operation log for full output."]; [_message release]; _message = [shortMessage copy]; }
    NSString *operation = [result objectForKey:@"operation"];
    if (failure) { [self showText:failure title:@"Operation failed"]; }
    else if ([result objectForKey:@"items"]) { [_items release]; _items = [[result objectForKey:@"items"] copy]; [self filter]; }
    else if ([operation hasPrefix:@"plan-"]) {
        RCPackagesViewController *review = [[RCPackagesViewController alloc] initWithMode:@"plan" item:_selection]; review->_remove = [operation isEqual:@"plan-remove"]; review->_plan = [result copy];
        [self.navigationController pushViewController:review animated:YES]; [review release];
    } else if ([operation hasPrefix:@"source-"]) [self begin:[NSArray arrayWithObject:@"sources"]];
    else if ([operation hasPrefix:@"apply-"]) {
        self.navigationItem.rightBarButtonItem.enabled = NO;
        [self showText:[NSString stringWithFormat:@"%@\n\nOperation finished. Reload Installed to check the result. Respring only if the package author requires it; no automatic restart detection is performed.", [result objectForKey:@"output"] ?: @""] title:@"Package result"];
    } else [self showText:[result objectForKey:@"output"] title:[operation isEqual:@"refresh"] ? @"Refresh result" : [operation isEqual:@"last-result"] ? @"Package operation log" : @"Package details"];
    if (![_mode isEqual:@"plan"]) [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; if ([_mode isEqual:@"root"]) return 5; if ([_mode isEqual:@"package"]) return 3; return [_visible count];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if ([_mode isEqual:@"package"]) { NSString *description = [_selection objectForKey:@"Description"] ?: @""; if ([description length] > 512) description = [[description substringToIndex:512] stringByAppendingString:@"…"]; return [NSString stringWithFormat:@"%@\n%@\n%@", [_selection objectForKey:@"Package"], description, _message]; }
    return _message;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"package"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"package"] autorelease];
    cell.detailTextLabel.text = nil; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if ([_mode isEqual:@"root"]) cell.textLabel.text = [[NSArray arrayWithObjects:@"Sources", @"Search packages", @"Installed packages", @"Refresh repository indexes", @"Operation log", nil] objectAtIndex:index.row];
    else if ([_mode isEqual:@"package"]) cell.textLabel.text = [[NSArray arrayWithObjects:@"Package details", @"Install / Upgrade…", @"Remove…", nil] objectAtIndex:index.row];
    else {
        NSDictionary *item = [_visible objectAtIndex:index.row];
        cell.textLabel.text = [_mode isEqual:@"sources"] ? [item objectForKey:@"name"] : [item objectForKey:@"Name"] ?: [item objectForKey:@"Package"];
        cell.detailTextLabel.text = [_mode isEqual:@"sources"] ? [item objectForKey:@"line"] : [NSString stringWithFormat:@"%@  %@", [item objectForKey:@"Version"] ?: @"", [item objectForKey:@"Description"] ?: @""];
    }
    cell.textLabel.lineBreakMode = UILineBreakModeMiddleTruncation; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES]; if ([[RCPackageManager sharedManager] busy]) return; [_search resignFirstResponder];
    if ([_mode isEqual:@"root"]) {
        if (index.row == 3) { [self begin:[NSArray arrayWithObject:@"refresh"]]; return; }
        if (index.row == 4) { [self begin:[NSArray arrayWithObject:@"last-result"]]; return; }
        NSString *mode = index.row == 0 ? @"sources" : index.row == 1 ? @"search" : @"installed";
        RCPackagesViewController *controller = [[RCPackagesViewController alloc] initWithMode:mode item:nil]; [self.navigationController pushViewController:controller animated:YES]; [controller release]; return;
    }
    if ([_mode isEqual:@"package"]) {
        [self begin:[NSArray arrayWithObjects:index.row == 0 ? @"details" : index.row == 1 ? @"plan-install" : @"plan-remove", [_selection objectForKey:@"Package"], nil]]; return;
    }
    NSDictionary *item = [_visible objectAtIndex:index.row];
    if ([_mode isEqual:@"sources"]) {
        [_selection release]; _selection = [item copy];
        _prompt = [[UIAlertView alloc] initWithTitle:@"Remove repository?" message:[NSString stringWithFormat:@"Remove %@ from APT? Installed packages remain. For a Cydia-managed URI, all its distributions are removed from Cydia’s source records too. Fully close Cydia first.", [item objectForKey:@"name"]] delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Remove source", nil]; [_prompt show];
    } else { RCPackagesViewController *controller = [[RCPackagesViewController alloc] initWithMode:@"package" item:item]; [self.navigationController pushViewController:controller animated:YES]; [controller release]; }
}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text { (void)bar; (void)text; if ([_mode isEqual:@"installed"]) [self filter]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar { [bar resignFirstResponder]; if ([_mode isEqual:@"search"]) [self begin:[NSArray arrayWithObjects:@"search", bar.text ?: @"", nil]]; }
- (void)addSource {
    if (_prompt || [[RCPackageManager sharedManager] busy]) return;
    _prompt = [[UIAlertView alloc] initWithTitle:@"Add repository" message:@"Enter a flat Cydia HTTP(S) repository URL.\n\n\n" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Add", nil];
    _field = [[UITextField alloc] initWithFrame:CGRectMake(14, 88, 256, 30)]; _field.borderStyle = UITextBorderStyleRoundedRect; _field.backgroundColor = [UIColor whiteColor]; _field.text = @"https://";
    _field.keyboardType = UIKeyboardTypeURL; _field.autocorrectionType = UITextAutocorrectionTypeNo; _field.autocapitalizationType = UITextAutocapitalizationTypeNone; [_prompt addSubview:_field]; [_prompt show];
}
- (void)confirmPlan {
    if (_prompt || [[RCPackageManager sharedManager] busy]) return;
    _prompt = [[UIAlertView alloc] initWithTitle:_unsigned ? @"Allow unsigned packages?" : _remove ? @"Remove these packages?" : @"Install these packages?" message:_unsigned ? @"For this installation only, APT may install packages without authenticated repository signatures. A modified or untrusted repository could supply malicious code that runs as root. Proceed only if you trust this source. This preference is not saved." : @"Confirm all changes in the reviewed APT plan. Package scripts can run as root. Close Cydia and keep Receptor open. Repository authentication stays enabled by default. Legacy unsigned sources need the separate Allow unsigned option." delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:_unsigned ? @"Install unsigned" : @"Confirm", nil];
    if (!_unsigned && !_remove) [_prompt addButtonWithTitle:@"Allow unsigned…"];
    [_prompt show];
}
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index {
    if (alert != _prompt) return; [_prompt autorelease]; _prompt = nil;
    NSString *url = [[_field.text copy] autorelease]; [_field release]; _field = nil;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if ([_mode isEqual:@"plan"] && index == 2 && !_remove) { _unsigned = YES; [self confirmPlan]; return; }
    if (index != 1) { _unsigned = NO; return; }
    if ([_mode isEqual:@"plan"]) {
        [self begin:[NSArray arrayWithObjects:_remove ? @"apply-remove" : _unsigned ? @"apply-unsigned-install" : @"apply-install", [_selection objectForKey:@"Package"], [_plan objectForKey:@"token"], nil]];
        _unsigned = NO;
    } else if (url) [self begin:[NSArray arrayWithObjects:@"source-add", url, nil]];
    else [self begin:[NSArray arrayWithObjects:@"source-remove", [_selection objectForKey:@"id"], nil]];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown; }
- (void)dealloc {
    if ([RCPackageManager sharedManager].delegate == self) [RCPackageManager sharedManager].delegate = nil;
    _search.delegate = nil; _prompt.delegate = nil; [_prompt dismissWithClickedButtonIndex:0 animated:NO];
    [_mode release]; [_items release]; [_visible release]; [_selection release]; [_plan release]; [_pending release]; [_message release]; [_search release]; [_prompt release]; [_field release]; [super dealloc];
}
@end
