//
//  PPSURLSessionConfiguration.h
//  PPSNetworkMonitor
//
//  Created by ppsheep on 2017/4/10.
//  Copyright © 2017年 ppsheep. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PPSURLSessionConfiguration : NSObject

@property (nonatomic,assign) BOOL isSwizzle;

+ (PPSURLSessionConfiguration *)defaultConfiguration;

/**
 *  swizzle NSURLSessionConfiguration's protocolClasses method
 */
- (void)load;

/**
 *  make NSURLSessionConfiguration's protocolClasses method is normal
 */
- (void)unload;

@end
