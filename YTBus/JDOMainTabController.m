//
//  JDOMainTabController.m
//  YTBus
//
//  Created by zhang yi on 14-10-31.
//  Copyright (c) 2014年 胶东在线. All rights reserved.
//

#import "JDOMainTabController.h"
#import "JDODatabase.h"
#import "AFNetworking.h"
#import "SSZipArchive.h"
#import "MBProgressHUD.h"
#import "JDOConstants.h"


@interface JDOMainTabController () <SSZipArchiveDelegate> {
    MBProgressHUD *hud;
}
//UINavigationBar
@end

@implementation JDOMainTabController

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
    self.tabBar.backgroundImage = [UIImage imageNamed:@"导航底图"];
    self.tabBar.itemPositioning = UITabBarItemPositioningFill;
    if (After_iOS7){
        self.tabBar.translucent = false;
    }
    
    // 设置tabBarItem的图标
    NSArray *imageNames = @[@"附近",@"线路",@"站点",@"换乘",@"更多"];
    for(int i=0; i<self.tabBar.items.count; i++){
        UITabBarItem *item = self.tabBar.items[i];
        item.title = nil;
        // 按TabBar的默认item大小128*96进行裁图会让图标向上偏移
        item.imageInsets = UIEdgeInsetsMake(5.5, 0, -5.5, 0);
        UIImage *selectedImg = [[UIImage imageNamed:[imageNames[i] stringByAppendingString:@"2"]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        UIImage *unselectedImg = [[UIImage imageNamed:[imageNames[i] stringByAppendingString:@"1"]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        if (After_iOS7) {
            item.image = unselectedImg;
            item.selectedImage = selectedImg;
        }else{
            [item setFinishedSelectedImage:selectedImg withFinishedUnselectedImage:unselectedImg];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (![JDODatabase isDBExistInDocument]) {
        // 若document中不存在数据库文件，则下载数据库文件
        hud = [MBProgressHUD showHUDAddedTo:self.view animated:true];
        hud.dimBackground = true;
        hud.minShowTime = 1.0f;
        hud.labelText = @"初始化数据";
        NSURL *URL = [NSURL URLWithString:@"http://218.56.32.7:1030/SynBusSoftWebservice/DownloadServlet?method=downloadDb"];
        NSURLRequest *request = [NSURLRequest requestWithURL:URL];
        NSLog(@"开始下载");
        AFHTTPRequestOperation *op = [[AFHTTPRequestOperation alloc] initWithRequest:request];
        [op setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            NSLog(@"下载完成，开始保存");
            NSData *zipData = (NSData *)responseObject;
            BOOL success = [JDODatabase saveZipFile:zipData];
            NSLog(@"保存完成，开始解压");
            if ( success) { // 解压缩文件
                BOOL result = [JDODatabase unzipDBFile:self];
                if ( result) {
                    // 正在解压
                }else{  // 解压文件出错
                    [JDODatabase openDB:1];
                }
            }else{  // 保存文件出错
                [JDODatabase openDB:1];
            }
            [hud hide:true];
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Error: %@", error);
            [JDODatabase openDB:1];
            [hud hide:true];
        }];
        [[NSOperationQueue mainQueue] addOperation:op];
    }else{
        //TODO 更新最新数据
        [JDODatabase openDB:2];
    }

}

- (void)zipArchiveDidUnzipArchiveAtPath:(NSString *)path zipInfo:(unz_global_info)zipInfo unzippedPath:(NSString *)unzippedPath{
    NSLog(@"解压完成，打开数据库");
    [JDODatabase openDB:2];
}

- (void)zipArchiveProgressEvent:(NSInteger)loaded total:(NSInteger)total{
    NSLog(@"解压进度:%g",loaded*1.0/total);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
