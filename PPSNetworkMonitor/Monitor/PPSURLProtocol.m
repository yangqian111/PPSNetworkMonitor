//
//  PPSURLProtocol.m
//  PPSNetworkMonitor
//
//  Created by ppsheep on 2017/4/8.
//  Copyright © 2017年 ppsheep. All rights reserved.
//

#import "PPSURLProtocol.h"
#import "PPSURLSessionConfiguration.h"

static NSString *const PPSHTTP = @"PPSHTTP";//为了避免canInitWithRequest和canonicalRequestForRequest的死循环

@interface PPSURLProtocol()<NSURLConnectionDelegate,NSURLConnectionDataDelegate>

@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSURLRequest *pps_request;
@property (nonatomic, strong) NSURLResponse *pps_response;
@property (nonatomic, strong) NSMutableData *pps_data;


@end

@implementation PPSURLProtocol

#pragma mark - init
- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

+ (void)load {
    
}

+ (void)start {
    PPSURLSessionConfiguration *sessionConfiguration = [PPSURLSessionConfiguration defaultConfiguration];
    [NSURLProtocol registerClass:[PPSURLProtocol class]];
    if (![sessionConfiguration isSwizzle]) {
        [sessionConfiguration load];
    }
}

+ (void)end {
    PPSURLSessionConfiguration *sessionConfiguration = [PPSURLSessionConfiguration defaultConfiguration];
    [NSURLProtocol unregisterClass:[PPSURLProtocol class]];
    if ([sessionConfiguration isSwizzle]) {
        [sessionConfiguration unload];
    }
}


/**
 需要控制的请求

 @param request 此次请求
 @return 是否需要监控
 */
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    
    if (![request.URL.scheme isEqualToString:@"http"] &&
        ![request.URL.scheme isEqualToString:@"https"]) {
        return NO;
    }
    //如果是已经拦截过的  就放行
    if ([NSURLProtocol propertyForKey:PPSHTTP inRequest:request] ) {
        return NO;
    }
    return YES;
}

/**
 设置我们自己的自定义请求
 可以在这里统一加上头之类的
 
 @param request 应用的此次请求
 @return 我们自定义的请求
 */
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableReqeust = [request mutableCopy];
    [NSURLProtocol setProperty:@YES
                        forKey:PPSHTTP
                     inRequest:mutableReqeust];
    return [mutableReqeust copy];
}

- (void)startLoading {
    NSURLRequest *request = [[self class] canonicalRequestForRequest:self.request];
    self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    self.pps_request = self.request;
}

- (void)stopLoading {
    [self.connection cancel];

    //获取请求方法
    NSString *requestMethod = self.pps_request.HTTPMethod;
    NSLog(@"请求方法：%@\n",requestMethod);
    
    //获取请求头
    NSDictionary *headers = self.pps_request.allHTTPHeaderFields;
    NSLog(@"请求头：\n");
    for (NSString *key in headers.allKeys) {
        NSLog(@"%@ : %@",key,headers[key]);
    }

    //获取请求结果
    NSString *string = [self responseJSONFromData:self.pps_data];
    NSLog(@"请求结果：%@",string);
    
}

#pragma mark - NSURLConnectionDelegate
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    [self.client URLProtocol:self didFailWithError:error];
}

- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection{
    return YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge{
    [self.client URLProtocol:self didReceiveAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection
didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    [self.client URLProtocol:self didCancelAuthenticationChallenge:challenge];
}

#pragma mark - NSURLConnectionDataDelegate
-(NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response{
    if (response != nil) {
        self.pps_response = response;
        [self.client URLProtocol:self wasRedirectedToRequest:request redirectResponse:response];
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection
didReceiveResponse:(NSURLResponse *)response {
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    self.pps_response = response;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
    [self.pps_data appendData:data];
    NSLog(@"receiveData");
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    return cachedResponse;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [[self client] URLProtocolDidFinishLoading:self];
}

//转换json
-(id)responseJSONFromData:(NSData *)data {
    if(data == nil) return nil;
    NSError *error = nil;
    id returnValue = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if(error) {
        NSLog(@"JSON Parsing Error: %@", error);
        //https://github.com/coderyi/NetworkEye/issues/3
        return nil;
    }
    //https://github.com/coderyi/NetworkEye/issues/1
    if (!returnValue || returnValue == [NSNull null]) {
        return nil;
    }
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:returnValue options:NSJSONWritingPrettyPrinted error:nil];
    NSString *jsonString = [[NSString alloc]initWithData:jsonData encoding:NSUTF8StringEncoding];
    return jsonString;
}

@end
