//
//  DownloadHtmlHelper.h
//  NSURLSessionTest
//
//  Created by Null on 17/3/23.
//  Copyright © 2017年 zcs_yang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const TYYDownloadCacheFolderName;


@interface DownloadHtmlHelper : NSObject

@property (nonatomic ,assign , getter=isSupportResumeFromBreakPoint)BOOL supportResumeFromBreakPoint;
@property (nonatomic ,readonly)NSString *url;
@property (nonatomic ,readonly)NSString *filePath;
@property (nonatomic ,readonly)NSString *fileName;
@property (nonatomic ,readonly)NSString *trueName;

- (void)downloadFileWithUrl:(NSString *)url version:(NSString *)version progress:(void(^)(int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite))progress complete:(void(^)(NSURL *targetFileURL))complete failure:(void(^)(NSError *error))failure;

@end
