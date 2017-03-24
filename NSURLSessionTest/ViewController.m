//
//  ViewController.m
//  NSURLSessionTest
//
//  Created by Null on 17/3/22.
//  Copyright © 2017年 zcs_yang. All rights reserved.
//

#import "ViewController.h"
#import "DownloadHtmlHelper.h"
#import <SSZipArchive.h>

@interface ViewController ()<UIWebViewDelegate>
@property (weak, nonatomic) IBOutlet UILabel *progressLabel;
@property (weak, nonatomic) IBOutlet UIButton *button;

@property (nonatomic ,strong)NSString *htmlPath;
@property (nonatomic ,strong)DownloadHtmlHelper *helper;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (IBAction)startDownload:(id)sender {
    [self.helper downloadFileWithUrl:@"http://down10.zol.com.cn/xitongruanjian/CleanMyMacv3.6.dmg" version:@"1.0.0" progress:^(int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
        NSLog(@"%@   %@",@(totalBytesWritten),@(totalBytesExpectedToWrite));
    } complete:^(NSURL *targetFileURL,NSURLResponse *response) {
        NSLog(@"targetUrl = %@",targetFileURL.absoluteString);
    } failure:^(NSError *error) {
        NSLog(@"error = %@",error.localizedDescription);
    }];
}

- (IBAction)unZip:(UIButton *)sender {
//    NSString *destination = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
//    NSLog(@"%@",destination);
//    [SSZipArchive unzipFileAtPath:self.path toDestination:destination progressHandler:^(NSString * _Nonnull entry, unz_file_info zipInfo, long entryNumber, long total) {
//        if ([entry containsString:@"SNBodyTemplate.html"]) {
//            self.htmlPath = [destination stringByAppendingPathComponent:entry];
//        }
//    } completionHandler:^(NSString * _Nonnull path, BOOL succeeded, NSError * _Nonnull error) {
//        NSLog(@"path = %@",path);
//        [[NSFileManager defaultManager]removeItemAtPath:path error:nil];
//        [self openWebview];
//    }];
}
- (IBAction)closeWeb:(id)sender {
    for (UIView *view in self.view.subviews) {
        if ([view isKindOfClass:[UIWebView class]]) {
            [view removeFromSuperview];
        }
    }
}

- (void)openWebview{
    if (!self.htmlPath) {
        return;
    }
    
    UIWebView *webview = [[UIWebView alloc]initWithFrame:CGRectMake(0, 60, self.view.frame.size.width, self.view.frame.size.height - 80)];
    webview.scalesPageToFit = YES;
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL fileURLWithPath:self.htmlPath]];
    [webview loadRequest:request];
    webview.delegate = self;
    [self.view addSubview:webview];
}

- (DownloadHtmlHelper *)helper{
    if (_helper) {
        return _helper;
    }
    _helper = [[DownloadHtmlHelper alloc]init];
    return _helper;
}


@end
