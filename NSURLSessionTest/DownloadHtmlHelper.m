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
NSString *const TYYDownloadCacheFileInfoKey = @"TYYDownloadCacheFileInfoKey";

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

int64_t fileSizeForPath(NSString *path) {
    
    int64_t fileSize = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:path]) {
        NSError *error = nil;
        NSDictionary *fileDict = [fileManager attributesOfItemAtPath:path error:&error];
        if (!error && fileDict) {
            fileSize = [fileDict fileSize];
        }
    }
    return fileSize;
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

@interface DownloadHtmlHelper ()<NSURLSessionDataDelegate>
@property (nonatomic ,strong)NSString *url;
@property (nonatomic ,strong)NSString *version;
@property (nonatomic ,strong)NSString *filePath;
@property (nonatomic ,strong)NSString *fileName;
@property (nonatomic ,strong)NSString *trueName;
@property (nonatomic ,assign)int64_t totalBytesWritten;
@property (nonatomic ,assign)int64_t totalBytesExpectedToWrite;

@property (nonatomic ,strong)dispatch_queue_t synchronizationQueue;
@property (nonatomic ,strong)NSURLSession *session;
@property (nonatomic ,strong)NSURLSessionDataTask *task;
@property (nonatomic ,assign)UIBackgroundTaskIdentifier backgroundTaskId;

@property (nonatomic ,copy)void (^progressBlock)(int64_t,int64_t);
@property (nonatomic ,copy)void (^completeBlock)(NSURL*,NSURLResponse *);
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
        self.totalBytesExpectedToWrite = INT_MAX;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)downloadFileWithUrl:(NSString *)url version:(NSString *)version progress:(void (^)(int64_t, int64_t))progress complete:(void (^)(NSURL *, NSURLResponse *))complete failure:(void (^)(NSError *))failure{
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
        
        [self configureFilePath];
        if (self.totalBytesWritten >= self.totalBytesExpectedToWrite) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.completeBlock) {
                    self.completeBlock([NSURL fileURLWithPath:self.filePath ?: @""],nil);
                }
            });
            return;
        }
        // 当请求暂停一段时间后。转态会变化。所有要判断下状态
        if (!self.task || ((self.task.state != NSURLSessionTaskStateRunning) && (self.task.state != NSURLSessionTaskStateSuspended))) {
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.url]];
            
            NSString *range = [NSString stringWithFormat:@"bytes=%zd-", self.totalBytesWritten];
            [request setValue:range forHTTPHeaderField:@"Range"];
            self.task = [self.session dataTaskWithRequest:request];
            self.task.taskDescription = self.url;
        }
        
        [self.task resume];
    });
}

- (void)configureFilePath{
    NSDictionary *fileInfo = [[NSUserDefaults standardUserDefaults]valueForKey:TYYDownloadCacheFileInfoKey];
    NSString *cacheFilePath = [fileInfo valueForKey:@"filePath"];
    NSString *fileHeader = [NSString stringWithFormat:@"%@_%@.",getMD5String(self.url),self.version];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([cacheFilePath containsString:fileHeader] && [fileManager fileExistsAtPath:cacheFilePath]) {
        self.filePath = cacheFilePath;
        self.totalBytesExpectedToWrite = [[fileInfo valueForKey:@"totalBytesExpectedToWrite"] unsignedLongLongValue];
    }else {
        //之前没下载过
        //清空缓存文件夹内的所有缓存
        NSArray *paths = [fileManager subpathsAtPath:cacheFolder()];
        for (NSString *path in paths) {
            NSString *willDeletePath = [cacheFolder() stringByAppendingPathComponent:path];
            [fileManager removeItemAtPath:willDeletePath error:nil];
        }
    }
}

- (void)saveFileInfo{
    NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
    [fileInfo setValue:self.filePath forKey:@"filePath"];
    [fileInfo setValue:[NSNumber numberWithUnsignedLongLong:self.totalBytesWritten] forKey:@"totalBytesWritten"];
    [fileInfo setValue:[NSNumber numberWithUnsignedLongLong:self.totalBytesExpectedToWrite] forKey:@"totalBytesExpectedToWrite"];
    [[NSUserDefaults standardUserDefaults]setValue:fileInfo forKey:TYYDownloadCacheFileInfoKey];
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

- (void)suspend{
    [self.task suspend];
    [self saveFileInfo];
}

#pragma mark - <NSURLSessionDataDelegate>
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(nonnull NSURLResponse *)response completionHandler:(nonnull void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.totalBytesExpectedToWrite = self.totalBytesWritten + dataTask.countOfBytesExpectedToReceive;
    if (!self.filePath) {
        //只有在这里才能拿到正确的文件名
        self.trueName = dataTask.response.suggestedFilename;
        if (self.trueName.length) {
            self.fileName = [NSString stringWithFormat:@"%@_%@.%@", getMD5String(self.url),self.version, self.trueName];
        } else {
            self.fileName = getMD5String(self.url);
        }
        self.filePath = [cacheFolder() stringByAppendingPathComponent:self.fileName];
        [self saveFileInfo];
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    
    dispatch_sync(self.synchronizationQueue, ^{
        __block NSError *error = nil;
        
        NSInputStream *inputStream =  [[NSInputStream alloc] initWithData:data];
        NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:[NSURL fileURLWithPath:self.filePath] append:YES];
        [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [inputStream open];
        [outputStream open];
        
        while ([inputStream hasBytesAvailable] && [outputStream hasSpaceAvailable]) {
            uint8_t buffer[1024];
            
            NSInteger bytesRead = [inputStream read:buffer maxLength:1024];
            if (inputStream.streamError || bytesRead < 0) {
                error = inputStream.streamError;
                break;
            }
            
            NSInteger bytesWritten = [outputStream write:buffer maxLength:(NSUInteger)bytesRead];
            if (outputStream.streamError || bytesWritten < 0) {
                error = outputStream.streamError;
                break;
            }
            
            if (bytesRead == 0 && bytesWritten == 0) {
                break;
            }
        }
        [outputStream close];
        [inputStream close];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.progressBlock) {
                self.progressBlock(self.totalBytesWritten,self.totalBytesExpectedToWrite);
            }
        });
    });
    
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.failureBlock) {
                self.failureBlock(error);
            }
        });
    }else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.completeBlock) {
                self.completeBlock([NSURL fileURLWithPath:self.filePath],(NSURLResponse *)task.response);
            }
        });
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

- (int64_t)totalBytesWritten{
    return fileSizeForPath(self.filePath);
}

@end
