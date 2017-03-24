//
//  DownloadHtmlHelper.m
//  NSURLSessionTest
//
//  Created by Null on 17/3/23.
//  Copyright © 2017年 zcs_yang. All rights reserved.
//

#import "DownloadHtmlHelper.h"
#import <CommonCrypto/CommonCrypto.h>

NSString *const TYYDownloadCacheFolderName = @"TYYDownloadCache";

static NSString *cacheFolder() {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    static NSString *cacheFolder;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!cacheFolder) {
            NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            cacheFolder = [cacheDir stringByAppendingPathComponent:TYYDownloadCacheFolderName];
        }
        NSError *error;
        if (![fileManager createDirectoryAtPath:cacheFolder withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"create cacheFold failure");
            cacheFolder = nil;
        }
    });
    return cacheFolder;
}

/**
 {
    "resumeData":resumeData,
    "url":url,
    "version":version
 }
 */
static NSString *localReceiptDataPath() {
    return [cacheFolder() stringByAppendingPathComponent:@"receipt.data"];
}

static NSString *getMD5String(NSString *str) {
    if (str == nil) return nil;
    
    const char *cstring = str.UTF8String;
    unsigned char bytes[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cstring, (CC_LONG)strlen(cstring), bytes);
    
    NSMutableString *md5String = [NSMutableString string];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [md5String appendFormat:@"%02x", bytes[i]];
    }
    return md5String;
}

@interface DownloadHtmlHelper ()<NSURLSessionDownloadDelegate>
@property (nonatomic ,strong)NSString *url;
@property (nonatomic ,strong)NSString *version;
@property (nonatomic ,strong)NSString *filePath;
@property (nonatomic ,strong)NSString *fileName;
@property (nonatomic ,strong)NSString *trueName;

@property (nonatomic ,strong)NSData *resumeData;

@property (nonatomic ,strong)dispatch_queue_t synchronizationQueue;
@property (nonatomic ,strong)NSURLSession *session;
@property (nonatomic ,strong)NSURLSessionDownloadTask *task;
@property (nonatomic ,assign)UIBackgroundTaskIdentifier backgroundTaskId;

@property (nonatomic ,copy)void (^progressBlock)(int64_t,int64_t);
@property (nonatomic ,copy)void (^completeBlock)(NSURL*);
@property (nonatomic ,copy)void (^failureBlock)(NSError *);
@end

@implementation DownloadHtmlHelper

+ (NSURLSessionConfiguration *)defaultURLSessionConfiguration {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    configuration.HTTPShouldSetCookies = YES;
    configuration.HTTPShouldUsePipelining = NO;
    configuration.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
    configuration.allowsCellularAccess = YES;
    configuration.timeoutIntervalForRequest = 10.0;
    configuration.HTTPMaximumConnectionsPerHost = 10;
    configuration.discretionary = YES;
    return configuration;
}

- (instancetype)init{
    if (self = [super init]) {
        NSURLSessionConfiguration *defaultConfiguration = [self.class defaultURLSessionConfiguration];
        
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        self.session = [NSURLSession sessionWithConfiguration:defaultConfiguration delegate:self delegateQueue:queue];
        
        self.synchronizationQueue = dispatch_queue_create("downloadHtml", DISPATCH_QUEUE_SERIAL);
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)downloadFileWithUrl:(NSString *)url version:(NSString *)version progress:(void (^)(int64_t, int64_t))progress complete:(void (^)(NSURL *))complete failure:(void (^)(NSError *))failure{
    dispatch_sync(self.synchronizationQueue, ^{
        if (!url.length) {
            if (failure) {
                NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
            return;
        }
        self.url = url;
        self.version = version;
        self.progressBlock = progress;
        self.completeBlock = complete;
        self.failureBlock = failure;
        
        [self getResumeData];
        
        if (self.resumeData) {
            self.task = [self.session downloadTaskWithResumeData:self.resumeData];
        }else {
            self.task = [self.session downloadTaskWithURL:[NSURL URLWithString:self.url]];
        }
        [self.task resume];
    });
}

- (void)getResumeData{
    NSDictionary *receipts = [NSDictionary dictionaryWithContentsOfFile:localReceiptDataPath()];
    if (!receipts) {
        return;
    }
    NSString *url = [receipts valueForKey:@"url"];
    if (![url isEqualToString:self.url]) {
        return;
    }
    NSString *version = [receipts valueForKey:@"version"];
    if ([version isEqualToString:self.version]) {
        return;
    }
    NSData *resumeData = [receipts valueForKey:@"resumeData"];
    if (resumeData) {
        self.resumeData = resumeData;
    }
}

- (void)applicationWillTerminate:(NSNotification *)not{
    [self suspend];
}

- (void)applicationDidReceiveMemoryWarning:(NSNotification *)not{
    [self suspend];
}

- (void)applicationWillResignActive:(NSNotification *)not{
    /// 捕获到失去激活状态后
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    BOOL hasApplication = UIApplicationClass && [UIApplicationClass respondsToSelector:@selector(sharedApplication)];
    if (hasApplication ) {
        __weak __typeof (self) weakSelf = self;
        UIApplication * app = [UIApplicationClass performSelector:@selector(sharedApplication)];
        self.backgroundTaskId = [app beginBackgroundTaskWithExpirationHandler:^{
            __strong __typeof (weakSelf) strongSelf = weakSelf;
            
            if (strongSelf) {
                [strongSelf suspend];
                
                [app endBackgroundTask:strongSelf.backgroundTaskId];
                strongSelf.backgroundTaskId = UIBackgroundTaskInvalid;
            }
        }];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)not{
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if(!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
        return;
    }
    if (self.backgroundTaskId != UIBackgroundTaskInvalid) {
        UIApplication * app = [UIApplication performSelector:@selector(sharedApplication)];
        [app endBackgroundTask:self.backgroundTaskId];
        self.backgroundTaskId = UIBackgroundTaskInvalid;
    }
}

- (void)suspend{
    if (!self.task || (self.task.state != NSURLSessionTaskStateRunning && self.task.state != NSURLSessionTaskStateSuspended)) {
        return;
    }
    [self.task cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
        self.resumeData = resumeData;
        [self saveReceipt];
        self.task = nil;
    }];
}

- (void)saveReceipt{
    NSMutableDictionary *receipts = [NSMutableDictionary dictionary];
    [receipts setValue:self.resumeData forKey:@"resumeData"];
    [receipts setValue:self.url forKey:@"url"];
    [receipts setValue:self.version forKey:@"version"];
    [receipts writeToFile:localReceiptDataPath() atomically:YES];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error{
    self.resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData];
    [self saveReceipt];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location{
    dispatch_sync(self.synchronizationQueue, ^{
        if (location) {
            NSError *error;
            [[NSFileManager defaultManager]moveItemAtURL:location toURL:[NSURL fileURLWithPath:self.filePath] error:&error];
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (self.completeBlock) {
                    self.completeBlock([NSURL fileURLWithPath:self.filePath]);
                }
            });
        }else {
            NSLog(@"下载失败");
        }
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes{

}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    ////定时cancel

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressBlock) {
            self.progressBlock(totalBytesWritten,totalBytesExpectedToWrite);
        }
    });
}

- (NSString *)filePath{
    NSString *path = [cacheFolder() stringByAppendingPathComponent:self.fileName];
    if (![path isEqualToString:_filePath] ) {
        if (_filePath && ![[NSFileManager defaultManager] fileExistsAtPath:_filePath]) {
            NSString *dir = [_filePath stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        _filePath = path;
    }
    return _filePath;
}

- (NSString *)fileName{
    if (_fileName == nil) {
        NSString *pathExtension = self.url.pathExtension;
        if (pathExtension.length) {
            _fileName = [NSString stringWithFormat:@"%@.%@", getMD5String(self.url), pathExtension];
        } else {
            _fileName = getMD5String(self.url);
        }
    }
    return _fileName;
}

- (NSString *)trueName{
    if (!_trueName) {
        _trueName = self.url.lastPathComponent;
    }
    return _trueName;
}

@end
