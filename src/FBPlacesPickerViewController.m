/*
 * Copyright 2012 Facebook
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *    http://www.apache.org/licenses/LICENSE-2.0
 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "FBGraphObjectTableDataSource.h"
#import "FBGraphObjectTableSelection.h"
#import "FBGraphObjectPagingLoader.h"
#import "FBPlacesPickerViewController.h"
#import "FBRequestConnection.h"
#import "FBRequest.h"
#import "FBError.h"

static const NSInteger searchTextChangedTimerInterval = 2;
static const NSInteger defaultResultsLimit = 100;
static const NSInteger defaultRadius = 1000; // 1km
static NSString *defaultImageName =
@"FBiOSSDKResources.bundle/FBPlacesPickerView/images/fb_generic_place.png";

@interface FBPlacesPickerViewController () <FBPlacesPickerDelegate,
                                            FBGraphObjectSelectionChangedDelegate,
                                            FBGraphObjectViewControllerDelegate,
                                            FBGraphObjectPagingLoaderDelegate>

@property (nonatomic, retain) FBGraphObjectTableDataSource *dataSource;
@property (nonatomic, retain) FBGraphObjectTableSelection *selectionManager;
@property (nonatomic, retain) FBGraphObjectPagingLoader *loader;
@property (nonatomic, retain) NSTimer *searchTextChangedTimer;
@property (nonatomic) BOOL hasSearchTextChangedSinceLastQuery;

- (void)initialize;
- (void)loadDataPostThrottle;
- (NSTimer *)createSearchTextChangedTimer;
- (void)updateView;

@end

@implementation FBPlacesPickerViewController

@synthesize dataSource = _dataSource;
@synthesize delegate = _delegate;
@synthesize fieldsForRequest = _fieldsForRequest;
@synthesize hasSearchTextChangedSinceLastQuery = _hasSearchTextChangedSinceLastQuery;
@synthesize loader = _loader;
@synthesize locationCoordinate = _locationCoordinate;
@synthesize radiusInMeters = _radiusInMeters;
@synthesize resultsLimit = _resultsLimit;
@synthesize searchText = _searchText;
@synthesize searchTextChangedTimer = _searchTextChangedTimer;
@synthesize selectionManager = _selectionManager;
@synthesize spinner = _spinner;
@synthesize tableView = _tableView;

- (id)init
{
    [super init];

    if (self) {
        [self initialize];
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    [super initWithCoder:aDecoder];
    
    if (self) {
        [self initialize];
    }
    
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];

    if (self) {
        [self initialize];
    }
    
    return self;
}

- (void)initialize
{
    // Data Source
    FBGraphObjectTableDataSource *dataSource = [[FBGraphObjectTableDataSource alloc]
                                                init];
    dataSource.defaultPicture = [UIImage imageNamed:defaultImageName];
    dataSource.controllerDelegate = self;
    dataSource.itemSubtitleEnabled = YES;
    self.dataSource = dataSource;

    // Selection Manager
    FBGraphObjectTableSelection *selectionManager = [[FBGraphObjectTableSelection alloc]
                                                     initWithDataSource:dataSource];
    selectionManager.delegate = self;

    // Paging loader
    self.loader = [[FBGraphObjectPagingLoader alloc] initWithDataSource:self.dataSource];
    self.loader.delegate = self;

    // Self
    self.dataSource = dataSource;
    self.delegate = self;
    self.selectionManager = selectionManager;
    self.resultsLimit = defaultResultsLimit;
    self.radiusInMeters = defaultRadius;
    self.itemPicturesEnabled = YES;

    // cleanup
    [selectionManager release];
    [dataSource release];
}

- (void)dealloc
{
    [_loader cancel];
    _loader.delegate = nil;
    [_loader release];
    
    _dataSource.controllerDelegate = nil;

    [_dataSource release];
    [_fieldsForRequest release];
    [_searchText release];
    [_searchTextChangedTimer release];
    [_selectionManager release];
    [_spinner release];
    [_tableView release];
    
    [super dealloc];
}

#pragma mark - Custom Properties

- (BOOL)itemPicturesEnabled
{
    return self.dataSource.itemPicturesEnabled;
}

- (void)setItemPicturesEnabled:(BOOL)itemPicturesEnabled
{
    self.dataSource.itemPicturesEnabled = itemPicturesEnabled;
}

- (id<FBGraphPlace>)selection
{
    NSArray *selection = self.selectionManager.selection;
    if ([selection count]) {
        return [selection objectAtIndex:0];
    } else {
        return nil;
    }
}

- (void)setSession:(FBSession *)session {
    self.loader.session = session;
}

- (FBSession*)session {
    return self.loader.session;
}

#pragma mark - Public Methods

- (void)loadData
{
    // Sending a request on every keystroke is wasteful of bandwidth. Send a
    // request the first time the user types something, then set up a 2-second timer
    // and send whatever changes the user has made since then. (If nothing has changed
    // in 2 seconds, we reset so the next change will cause an immediate re-query.)
    if (!self.searchTextChangedTimer) {
        self.searchTextChangedTimer = [self createSearchTextChangedTimer];
        [self loadDataPostThrottle];
    } else {
        self.hasSearchTextChangedSinceLastQuery = YES;
    }
}

#pragma mark - private methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    CGRect bounds = self.view.bounds;

    if (!self.tableView) {
        UITableView *tableView = [[UITableView alloc] initWithFrame:bounds];
        tableView.allowsMultipleSelection = NO;
        tableView.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        self.tableView = tableView;
        [self.view addSubview:tableView];
        [tableView release];
    }

    if (!self.spinner) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithFrame:bounds];
        spinner.hidesWhenStopped = YES;
        spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
        spinner.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        // We want user to be able to scroll while we load.
        spinner.userInteractionEnabled = NO;

        self.spinner = spinner;
        [self.view addSubview:spinner];
        [spinner release];
    }

    self.tableView.delegate = self.selectionManager;
    [self.dataSource bindTableView:self.tableView];
    self.loader.tableView = self.tableView;
}

- (void)viewDidUnload
{
    [super viewDidUnload];

    self.loader.tableView = nil;
    self.spinner = nil;
    self.tableView = nil;
}

- (void)loadDataPostThrottle
{
    FBRequest *request = [FBRequest requestForPlacesSearchAtCoordinate:self.locationCoordinate 
                                                        radiusInMeters:self.radiusInMeters
                                                          resultsLimit:self.resultsLimit
                                                            searchText:self.searchText
                                                               session:self.session];
    
    NSString *fields = [self.dataSource fieldsForRequestIncluding:self.fieldsForRequest,
                        @"id", @"name", @"location", @"category", @"picture", nil];
    [request.parameters setObject:fields forKey:@"fields"];

    self.hasSearchTextChangedSinceLastQuery = NO;
    [self.loader startLoadingWithRequest:request];
    [self updateView];
}

- (void)updateView
{
    [self.dataSource update];
    [self.tableView reloadData];
}

- (NSTimer *)createSearchTextChangedTimer {
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:searchTextChangedTimerInterval
                                                      target:self 
                                                    selector:@selector(searchTextChangedTimerFired:) 
                                                    userInfo:nil 
                                                     repeats:YES];
    return timer;
}

- (void)searchTextChangedTimerFired:(NSTimer *)timer
{
    if (self.hasSearchTextChangedSinceLastQuery) {
        [self loadDataPostThrottle];
    } else {
        // Nothing has changed in 2 seconds. Invalidate and forget about this timer.
        // Next time the user types, we will fire a query immediately again.
        [self.searchTextChangedTimer invalidate];
        self.searchTextChangedTimer = nil;
    }
}

#pragma mark - FBGraphObjectSelectionChangedDelegate

- (void)graphObjectTableSelectionDidChange:
(FBGraphObjectTableSelection *)selection
{
    if ([self.delegate respondsToSelector:
         @selector(placesPickerViewControllerSelectionDidChange:)]) {
        [self.delegate placesPickerViewControllerSelectionDidChange:self];
    }
}

#pragma mark - FBGraphObjectViewControllerDelegate

- (BOOL)graphObjectTableDataSource:(FBGraphObjectTableDataSource *)dataSource
                filterIncludesItem:(id<FBGraphObject>)item
{
    id<FBGraphPlace> place = (id<FBGraphPlace>)item;

    if ([self.delegate
         respondsToSelector:@selector(placesPickerViewController:shouldIncludePlace:)]) {
        return [self.delegate placesPickerViewController:self
                                      shouldIncludePlace:place];
    } else {
        return YES;
    }
}

- (NSString *)graphObjectTableDataSource:(FBGraphObjectTableDataSource *)dataSource
                             titleOfItem:(id<FBGraphObject>)graphObject
{
    return [graphObject objectForKey:@"name"];
}

- (NSString *)graphObjectTableDataSource:(FBGraphObjectTableDataSource *)dataSource
                          subtitleOfItem:(id<FBGraphObject>)graphObject
{
    id<FBGraphPlace> place = (id<FBGraphPlace>)graphObject;
    id<FBGraphLocation> location = place.location;
    NSString *street = location.street;
    if (street) {
        return street;
    }
    return location.city;
}

- (UIImage *)graphObjectTableDataSource:(FBGraphObjectTableDataSource *)dataSource
                       pictureUrlOfItem:(id<FBGraphObject>)graphObject
{
    return [graphObject objectForKey:@"picture"];
}

#pragma mark FBGraphObjectPagingLoaderDelegate members

- (void)pagingLoader:(FBGraphObjectPagingLoader*)pagingLoader willLoadURL:(NSString*)url {
    // We only want to display our spinner on loading the first page. After that,
    // a spinner will display in the last cell to indicate to the user that data is loading.
    if (!self.dataSource.hasGraphObjects) {
        [self.spinner startAnimating];
    }
}

- (void)pagingLoader:(FBGraphObjectPagingLoader*)pagingLoader didLoadData:(NSDictionary*)results {
    [self.spinner stopAnimating];
    if ([self.delegate respondsToSelector:@selector(placesPickerViewControllerDataDidChange:)]) {
        [self.delegate placesPickerViewControllerDataDidChange:self];
    }
}

- (void)pagingLoader:(FBGraphObjectPagingLoader*)pagingLoader handleError:(NSError*)error {
    if ([self.delegate respondsToSelector:@selector(placesPickerViewController:handleError:)]) {
        [self.delegate placesPickerViewController:self handleError:error];
    }
    
}

@end
