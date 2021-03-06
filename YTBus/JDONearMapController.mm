//
//  JDONearMapController.m
//  YTBus
//
//  Created by zhang yi on 14-10-30.
//  Copyright (c) 2014年 胶东在线. All rights reserved.
//

#import "JDONearMapController.h"
#import "JDOStationModel.h"
#import "JDODatabase.h"
#import "JDOBusLine.h"
#import "JDOStationAnnotation.h"
#import "JDORealTimeController.h"
#import "UIDevice+Hardware.h"

@interface JDOPaoPaoTable : UITableView

@property (nonatomic,strong) JDOStationModel *station;

@end

@implementation JDOPaoPaoTable

@end

@interface JDONearMapController () <BMKMapViewDelegate,BMKLocationServiceDelegate,UITableViewDataSource,UITableViewDelegate> {
    BMKLocationService *_locService;
    CLLocationCoordinate2D lastSearchCoor;
    int distanceRadius;
    NSMutableArray *_stations;
    NSMutableArray *_linesOfFoundNearestStation;
    FMDatabase *_db;
    id dbObserver;
    id distanceObserver;
    BOOL needRefresh;
}

@end

@implementation JDONearMapController

- (void)viewDidLoad {
    [super viewDidLoad];

    _mapView.centerCoordinate = self.myselfCoor;
    _mapView.zoomEnabled = true;
    _mapView.zoomEnabledWithTap = true;
    _mapView.scrollEnabled = true;
    _mapView.rotateEnabled = true;
    _mapView.overlookEnabled = false;
    _mapView.showMapScaleBar = false;
    _mapView.zoomLevel = 17;
    _mapView.minZoomLevel = 15;
    _mapView.delegate = self;
    
    _locService = [[BMKLocationService alloc] init];
    distanceRadius = [[NSUserDefaults standardUserDefaults] integerForKey:@"nearby_distance"];
    if (distanceRadius == 0) {
        distanceRadius = 1000;
    }
    
    lastSearchCoor = CLLocationCoordinate2DMake(self.myselfCoor.latitude, self.myselfCoor.longitude) ;
    _db = [JDODatabase sharedDB];
    if (_db) {
        [self loadData];
    }else{
        dbObserver = [[NSNotificationCenter defaultCenter] addObserverForName:@"db_finished" object:nil queue:nil usingBlock:^(NSNotification *note) {
            _db = [JDODatabase sharedDB];
        }];
    }
    
    distanceObserver = [[NSNotificationCenter defaultCenter] addObserverForName:@"nearby_distance_changed" object:nil queue:nil usingBlock:^(NSNotification *note) {
        distanceRadius = [[NSUserDefaults standardUserDefaults] integerForKey:@"nearby_distance"];
        needRefresh = true;
    }];
}

- (void) loadData {
    _stations = [NSMutableArray new];   // 有线路的站点
    _linesOfFoundNearestStation = [NSMutableArray new];
    for(int i=0; i<_nearbyStations.count; i++){
        // 从数据库查询该站点途径的线路
        // 若站点没有公交线路通过，则认为该站点无效，例如7路通过的奥运酒店
        JDOStationModel *station = _nearbyStations[i];
        station.passLines = [NSMutableArray new];
        station.linesWhenStationIsNearest = [NSMutableArray new];
        FMResultSet *rs = [_db executeQuery:GetLinesByStation,station.fid];
        while ([rs next]) {
            JDOBusLine *busLine = [JDOBusLine new];
            busLine.lineId = [rs stringForColumn:@"LINEID"];
            busLine.lineName = [rs stringForColumn:@"LINENAME"];
            JDOBusLineDetail *lineDetail = [JDOBusLineDetail new];
            lineDetail.detailId = [rs stringForColumn:@"LINEDETAILID"];
            lineDetail.lineDetail = [rs stringForColumn:@"LINEDETAIL"];
            lineDetail.direction = [rs stringForColumn:@"LINEDIRECTION"];
            busLine.lineDetailPair = [@[lineDetail] mutableCopy];
            if (![_linesOfFoundNearestStation containsObject:lineDetail.detailId]) {
                [station.linesWhenStationIsNearest addObject:lineDetail.detailId];
                [_linesOfFoundNearestStation addObject:lineDetail.detailId];
            }
            [station.passLines addObject:busLine];
        }
        if (station.passLines.count >0) {
            [_stations addObject:station];
        }
    }
    [self addAnnotations];
}

- (void)didUpdateUserHeading:(BMKUserLocation *)userLocation{
    [_mapView updateLocationData:userLocation];
}

- (void)didFailToLocateUserWithError:(NSError *)error{
    
}

- (void)didUpdateUserLocation:(BMKUserLocation *)userLocation{
    [_mapView updateLocationData:userLocation];
    
    if (!_db) {
        return;
    }
    
    _myselfCoor = userLocation.location.coordinate;
    CLLocationDistance distance = BMKMetersBetweenMapPoints(BMKMapPointForCoordinate(lastSearchCoor),BMKMapPointForCoordinate(_myselfCoor));
    if (distance > 100 || needRefresh) {
        lastSearchCoor = _myselfCoor;
        needRefresh = false;
    }else{
        return;
    }
    [_nearbyStations removeAllObjects];
    
    double longitudeDelta = distanceRadius/85390.0;
    double latitudeDelta = distanceRadius/111000.0;
    NSString *sql = @"select * from STATION where gpsx2>? and gpsx2<? and gpsy2>? and gpsy2<? and stationname not like 't_%'";
    NSArray *argu = @[@(_myselfCoor.longitude-longitudeDelta),@(_myselfCoor.longitude+longitudeDelta),@(_myselfCoor.latitude-latitudeDelta),@(_myselfCoor.latitude+latitudeDelta)];
    FMResultSet *s = [_db executeQuery:sql withArgumentsInArray:argu];
    while ([s next]) {
        JDOStationModel *station = [JDOStationModel new];
        station.fid = [NSString stringWithFormat:@"%d",[s intForColumn:@"ID"]];
        station.name = [s stringForColumn:@"STATIONNAME"];
        station.direction = [s stringForColumn:@"GEOGRAPHICALDIRECTION"];
        station.gpsX = [NSNumber numberWithDouble:[s doubleForColumn:@"GPSX2"]];
        station.gpsY = [NSNumber numberWithDouble:[s doubleForColumn:@"GPSY2"]];
        // 对比与当前地理位置的距离小于1000的站点
        CLLocationCoordinate2D bdStation = CLLocationCoordinate2DMake(station.gpsY.doubleValue, station.gpsX.doubleValue);
        // gps坐标转百度坐标
//        CLLocationCoordinate2D bdStation = BMKCoorDictionaryDecode(BMKConvertBaiduCoorFrom(CLLocationCoordinate2DMake(station.gpsY.doubleValue, station.gpsX.doubleValue),BMK_COORDTYPE_GPS));
        // 转化为直角坐标测距
        CLLocationDistance distance = BMKMetersBetweenMapPoints(BMKMapPointForCoordinate(_myselfCoor),BMKMapPointForCoordinate(bdStation));
        if (distance < distanceRadius) {  // 附近站点
            station.distance = @(distance);
            [_nearbyStations addObject:station];
        }
    }
    
    // 按距离由近及远排序
    [_nearbyStations sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        JDOStationModel *station1 = (JDOStationModel *)obj1;
        JDOStationModel *station2 = (JDOStationModel *)obj2;
        if (station1.distance.doubleValue < station2.distance.doubleValue) {
            return NSOrderedAscending;
        }
        return NSOrderedDescending;
    }];
    
    [self loadData];
}

-(void)viewWillAppear:(BOOL)animated {
    [_mapView viewWillAppear];
    if (_locService) {
        _locService.delegate = self;
        [_locService startUserLocationService];
        _mapView.showsUserLocation = NO;
        _mapView.userTrackingMode = BMKUserTrackingModeNone;//设置定位的状态
        _mapView.showsUserLocation = YES;
        BMKLocationViewDisplayParam *param = [BMKLocationViewDisplayParam new];
//        param.locationViewImgName = @"";
        param.isAccuracyCircleShow = false;
        [_mapView updateLocationViewWithParam:param];
    }
}

-(void)viewWillDisappear:(BOOL)animated {
    [_mapView viewWillDisappear];
    if (_locService) {
        [_locService stopUserLocationService];
        _locService.delegate = nil;
        _mapView.showsUserLocation = NO;
    }
}

-(void)addAnnotations{
    if (self.mapView.annotations.count>0) {
        [self.mapView removeAnnotations:[NSArray arrayWithArray:self.mapView.annotations]];
    }
    for (int i=0; i<_stations.count; i++) {
        [self addPointAnnotation:_stations[i]];
    }
}

- (void)addPointAnnotation:(JDOStationModel *) station{
    JDOStationAnnotation *pointAnnotation = [[JDOStationAnnotation alloc] init];
    // GPS坐标转百度坐标
//    CLLocationCoordinate2D bdStation = BMKCoorDictionaryDecode(BMKConvertBaiduCoorFrom(CLLocationCoordinate2DMake(station.gpsY.doubleValue, station.gpsX.doubleValue),BMK_COORDTYPE_GPS));
//    pointAnnotation.coordinate = bdStation;
    pointAnnotation.coordinate = CLLocationCoordinate2DMake(station.gpsY.doubleValue, station.gpsX.doubleValue);
    pointAnnotation.station = station;
    [_mapView addAnnotation:pointAnnotation];
}

- (BMKAnnotationView *)mapView:(BMKMapView *)mapView viewForAnnotation:(id <BMKAnnotation>)annotation{
    static NSString *AnnotationViewID = @"annotationView";
    
    BMKPinAnnotationView *annotationView = (BMKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:AnnotationViewID];
    if (!annotationView) {
        annotationView = [[BMKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:AnnotationViewID];
        annotationView.pinColor = BMKPinAnnotationColorPurple;
        annotationView.animatesDrop = false;
        annotationView.draggable = false;
    }else{
        annotationView.annotation = annotation;
    }
    annotationView.paopaoView = [self createPaoPaoView:[(JDOStationAnnotation *)annotation station]];
    return annotationView;
}

- (void)mapView:(BMKMapView *)mapView didSelectAnnotationView:(BMKAnnotationView *)view{
    // 选中某个marker后，将此marker移动到地图中心偏下的位置，使其上方弹出的callout能在屏幕内显示全
    float delta = [[UIDevice currentDevice] isCurrentDeviceHardwareBetterThan:IPHONE_4S]?70:100;
    [mapView setCenterCoordinate:view.annotation.coordinate animated:YES];
    CGPoint p = [mapView convertCoordinate:view.annotation.coordinate toPointToView:mapView];
    CLLocationCoordinate2D coor = [mapView convertPoint:CGPointMake(p.x, p.y-delta) toCoordinateFromView:mapView];
    [mapView setCenterCoordinate:coor animated:YES];
}

- (BMKActionPaopaoView *)createPaoPaoView:(JDOStationModel *)station{
    NSArray *paopaoLines = station.passLines;
    // 弹出窗口中的线路数目如果小于180，则有多高就显示多高，否则最多显示180高度，内部表格滚动
    float tableHeight = paopaoLines.count*40<180?paopaoLines.count*40:180;
    UIView *customView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 189, 35+tableHeight+12)];
    
    UIImageView *header = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 189, 35)];
    header.image = [UIImage imageNamed:@"弹出列表01"];
    [customView addSubview:header];
    
    UILabel *title = [[UILabel alloc] initWithFrame:header.bounds];
    title.backgroundColor = [UIColor clearColor];   // iOS7以下label背景色为白色，以上为透明
    title.font = [UIFont boldSystemFontOfSize:15];
    title.minimumFontSize = 12;
    title.adjustsFontSizeToFitWidth = true;
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = [NSString stringWithFormat:@"%@[%@]  %d米",station.name,station.direction,[station.distance intValue]];
    [header addSubview:title];
    
    UIImageView *footer = [[UIImageView alloc] initWithFrame:CGRectMake(0, 35+tableHeight+12-51, 189, 51)];
    footer.image = [UIImage imageNamed:@"弹出列表04"];
    [customView addSubview:footer];
    
    JDOPaoPaoTable *paopaoTable = [[JDOPaoPaoTable alloc] initWithFrame:CGRectMake(0, 35, 189, tableHeight)];
    paopaoTable.station = station;
    paopaoTable.rowHeight = 40;
    paopaoTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    paopaoTable.delegate = self;
    paopaoTable.dataSource = self;
    [customView addSubview:paopaoTable];
    
    BMKActionPaopaoView *paopaoView = [[BMKActionPaopaoView alloc] initWithCustomView:customView];
    return paopaoView;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [self performSegueWithIdentifier:@"toRealtimeFromMap" sender:@[tableView,indexPath]];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"toRealtimeFromMap"]) {
        JDORealTimeController *rt = segue.destinationViewController;
        JDOPaoPaoTable *paopaoTable = [(NSArray *)sender objectAtIndex:0];
        NSIndexPath *indexPath = [(NSArray *)sender objectAtIndex:1];
        NSArray *paopaoLines = paopaoTable.station.passLines;
        rt.busLine = paopaoLines[indexPath.row];
        rt.busLine.nearbyStationPair = [NSMutableArray arrayWithArray:@[paopaoTable.station]];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    JDOPaoPaoTable *paopaoTable = (JDOPaoPaoTable *)tableView;
    NSArray *paopaoLines = paopaoTable.station.passLines;
    return paopaoLines.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *lineIdentifier = @"lineIdentifier";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:lineIdentifier];
    if( cell == nil){
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:lineIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UILabel *lineLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, 189-20-5, 40)];
        lineLabel.backgroundColor = [UIColor clearColor];
        lineLabel.font = [UIFont systemFontOfSize:14];
        lineLabel.minimumFontSize = 12;
        lineLabel.adjustsFontSizeToFitWidth = true;
        lineLabel.textColor = [UIColor colorWithRed:110/255.0f green:110/255.0f blue:110/255.0f alpha:1];
        lineLabel.tag = 3001;
        [cell addSubview:lineLabel];
        
        UIImageView *nearIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 1, 15, 39)];
        nearIcon.image = [UIImage imageNamed:@"近"];
        nearIcon.tag = 3002;
        [cell addSubview:nearIcon];
    }
    if (indexPath.row%2 == 0) {
        cell.backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"弹出列表02"]];
    }else{
        cell.backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"弹出列表03"]];
    }
    
    UILabel *lineLabel = (UILabel *)[cell viewWithTag:3001];
    UIImageView *nearIcon = (UIImageView *)[cell viewWithTag:3002];
    
    JDOPaoPaoTable *paopaoTable = (JDOPaoPaoTable *)tableView;
    NSArray *paopaoLines = paopaoTable.station.passLines;
    JDOBusLine *busLine = paopaoLines[indexPath.row];
    JDOBusLineDetail *lineDetail = busLine.lineDetailPair[0];
    NSArray *lineNamePair = [lineDetail.lineDetail componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"－-"]];

    NSString *lineContent;
    if (lineNamePair.count!=2) {
        NSLog(@"双向站点不全：%@",lineNamePair);
        lineContent = busLine.lineName;
    }else{
        lineContent = [NSString stringWithFormat:@"%@ 开往 %@",busLine.lineName,lineNamePair[1]];
    }
    lineLabel.text = lineContent;
    
    // 某条线路的该站点离当前位置最近，则用特殊颜色标示
    if ([paopaoTable.station.linesWhenStationIsNearest containsObject:lineDetail.detailId]) {
        nearIcon.hidden = false;
    }else{
        nearIcon.hidden = true;
    }
    return cell;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)dealloc{
    if (dbObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:dbObserver];
    }
    if (distanceObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:distanceObserver];
    }
}

@end
