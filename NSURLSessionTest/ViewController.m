//
//  ViewController.m
//  NSURLSessionTest
//
//  Created by Null on 17/3/22.
//  Copyright © 2017年 zcs_yang. All rights reserved.
//

#import "ViewController.h"
#import <SSZipArchive.h>

@interface ViewController ()<NSURLSessionDownloadDelegate,UIWebViewDelegate>
@property (weak, nonatomic) IBOutlet UILabel *progressLabel;
@property (weak, nonatomic) IBOutlet UIButton *button;

@property (nonatomic ,strong)NSURLSession *session;
@property (nonatomic ,strong)NSURLSessionDownloadTask *task;
@property (nonatomic ,strong)NSData *resumeData;

@property (nonatomic ,strong)NSString *path;
@property (nonatomic ,strong)NSString *htmlPath;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (NSURLSession *)session{
    if (_session) {
        return _session;
    }
    _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[[NSOperationQueue alloc] init]];
    return _session;
}

- (void)startTaskWithURL:(NSURL *)URL{
    self.task = [self.session downloadTaskWithURL:URL];
    [self.task resume];
    [self.button setTitle:@"downloading" forState:UIControlStateNormal];
}

- (void)resumeWithURL:(NSURL *)URL{
    self.task = [self.session downloadTaskWithResumeData:self.resumeData];
    [self.task resume];
    self.resumeData = nil;
    [self.button setTitle:@"downloading" forState:UIControlStateNormal];
}

- (void)suspend{
    [self.task cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
        self.resumeData = resumeData;
        self.task = nil;
    }];
    [self.button setTitle:@"suspend" forState:UIControlStateNormal];
}

- (IBAction)startDownload:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://codeload.github.com/nullyang/EFNewsContentHtml/zip/master"];
    if ([self.button.titleLabel.text isEqualToString:@"start"]) {
        [self startTaskWithURL:url];
    }else if ([self.button.titleLabel.text isEqualToString:@"suspend"]){
        [self resumeWithURL:url];
    }else if ([self.button.titleLabel.text isEqualToString:@"downloading"]){
        [self suspend];
    }
}

- (IBAction)unZip:(UIButton *)sender {
    NSString *destination = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    NSLog(@"%@",destination);
    [SSZipArchive unzipFileAtPath:self.path toDestination:destination progressHandler:^(NSString * _Nonnull entry, unz_file_info zipInfo, long entryNumber, long total) {
        if ([entry containsString:@"SNBodyTemplate.html"]) {
            self.htmlPath = [destination stringByAppendingPathComponent:entry];
        }
    } completionHandler:^(NSString * _Nonnull path, BOOL succeeded, NSError * _Nonnull error) {
        NSLog(@"path = %@",path);
        [[NSFileManager defaultManager]removeItemAtPath:path error:nil];
        [self openWebview];
    }];
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

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType{
    
    return YES;
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location{
    if (location) {
        self.path = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:downloadTask.response.suggestedFilename];
        [[NSFileManager defaultManager]moveItemAtURL:location toURL:[NSURL fileURLWithPath:self.path] error:nil];
        [self.button setTitle:@"complete" forState:UIControlStateNormal];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    dispatch_sync(dispatch_get_main_queue(), ^{
        if ((100.0*totalBytesWritten / totalBytesExpectedToWrite) > 0) {
            self.progressLabel.text = [NSString stringWithFormat:@"%.2f%%",(100.0*totalBytesWritten / totalBytesExpectedToWrite)];
        }
    });
}


@end
