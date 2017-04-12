# PPSNetworkMonitor
A Network Monitor

首先，我们需要介绍一下，在iOS中苹果提供了NSURLConnection、NSURLSession等优秀的网路接口供我们来调用，开源社区也有很多的开源库，如之前的ASIHttpRequest 现在的AFNetworking和Alamofire，我们接下来介绍的NSURLProtocol，都可以监控到这些开源库的网络请求。

### NSURLProtocol

NSURLProtocol是iOS网络加载系统中很强的一部分，它其实是一个抽象类，我们可以通过继承子类化来拦截APP中的网络请求。

举几个例子：

* 我们的APP内的所有请求都需要增加公共的头，像这种我们就可以直接通过NSURLProtocol来实现，当然实现的方式有很多种
* 再比如我们需要将APP某个API进行一些访问的统计
* 再比如我们需要统计APP内的网络请求失败率

等等，都可以用到

NSURLProtocol是一个抽象类，我们需要子类化才能实现网络请求拦截。

### 子类化NSURLProtocol

在NSURLProtocol中，我们需要告诉它哪些网络请求是需要我们拦截的，这个是通过方法can​Init​With​Request:​来实现的，比如我们现在需要拦截全部的HTTP和HTTPS请求，那么这个逻辑我们就可以在can​Init​With​Request:​中来定义

```objc
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
    return YES;
}

```

在方法canonicalRequestForRequest:中，我们可以自定义当前的请求request，当然如果不需要自定义，直接返回就行

```objc
/**
 设置我们自己的自定义请求
 可以在这里统一加上头之类的
 
 @param request 应用的此次请求
 @return 我们自定义的请求
 */
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}
```

对于每个NSURLProtocol的子类，都有一个client，通过它来对iOS的网络加载系统进行一系列的操作，比如，通知收到response或者错误的网络请求等等

这样，我们通过这两个方法，就已经能够拦截住iOS的网络请求了，但是这里有个问题

在我们上层业务调用网络请求的时候，首先会调用我们的can​Init​With​Request:方法，询问是否对该请求进行处理，接着会调用我们的canonicalRequestForRequest:来自定义一个request，接着又会去调用can​Init​With​Request:询问自定义的request是否需要处理，我们又返回YES，然后又去调用了canonicalRequestForRequest:，这样，就形成了一个死循环了，这肯定是我们不希望看到的。

有个处理方法，我们可以对每个处理过的request进行标记，在判断如果这个request已经处理过了，那么我们就不再进行处理，这样就有效避免了死循环

在我们自定义request的方法中，我们来设置处理标志

```objc
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableReqeust = [request mutableCopy];
    [NSURLProtocol setProperty:@YES
                        forKey:PPSHTTP
                     inRequest:mutableReqeust];
    return [mutableReqeust copy];
}
```

然后在我们的询问处理方法中，通过判断是否有处理过的标志，来进行拦截

```objc
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
```

这样，我们就避免了死循环

接下来，就是需要将这个request发送出去了，因为如果我们不处理这个request请求，系统会自动发出这个网络请求，但是当我们处理了这个请求，就需要我们手动来进行发送了。

我们要手动发送这个网络请求，需要重写startLoading方法

```objc
- (void)startLoading {
    NSURLRequest *request = [[self class] canonicalRequestForRequest:self.request];
    self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    self.pps_request = self.request;
}
```

解释一下上面的代码，因为我们拦截的这个请求是一个真实的请求，所以我们需要创建这样一个真实的网络请求，在第二行代码中，将我们自定义创建的request发了出了，第三行是为了保存当前的request，作为我们后面的处理对象。

当然，有start就有stop，stop就很简单了

```objc
- (void)stopLoading {
    [self.connection cancel];
}
```

在startLoading中，我们发起了一个NSURLConnection的请求，因为NSURLProtocol使我们自己定义的，所以我们需要将网络请求的一系列操作全部传递出去，不然上层就不知道当前网络的一个请求状态，那我们怎么将这个网络状态传到上层？在之前，我们说过每个protocol有一个NSURLProtocolClient实例，我们就通过这个client来传递。

传递一个网络请求，无外乎就是传递请求的一些过程，数据，结果等等。 发起了发起了一个NSURLConnection的请求，实现它的delegate就能够知道网络请求的一系列操作

```objc
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
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    return cachedResponse;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [[self client] URLProtocolDidFinishLoading:self];
}

```

其实从上面的代码，我们可以看出，我们就是在我们自己自定义的protocol中进行了一个传递过程，其他的也没有做操作

这样，基本的protocol就已经实现完成，那么怎样来拦截网络。我们需要将我们自定义的PPSURLProtocol通过NSURLProtocol注册到我们的网络加载系统中，告诉系统我们的网络请求处理类不再是默认的NSURLProtocol，而是我们自定义的PPSURLProtocol

我们在PPSURLProtocol暴露两个方法

```objc
#import <Foundation/Foundation.h>

@interface PPSURLProtocol : NSURLProtocol

+ (void)start;

+ (void)end;

@end
```

然后在我们的APP启动的时候，调用start，就可以监听到我们的网络请求。

```objc
+ (void)start {
    PPSURLSessionConfiguration *sessionConfiguration = [PPSURLSessionConfiguration defaultConfiguration];
    [NSURLProtocol registerClass:[PPSURLProtocol class]];
}

+ (void)end {
    PPSURLSessionConfiguration *sessionConfiguration = [PPSURLSessionConfiguration defaultConfiguration];
    [NSURLProtocol unregisterClass:[PPSURLProtocol class]];
}
```

目前为止，我们上面的代码已经能够监控到绝大部分的网络请求，但是呢，有一个却是特殊的。

对于NSURLSession发起的网络请求，我们发现通过shared得到的session发起的网络请求都能够监听到，但是通过方法*sessionWithConfiguration:delegate:delegateQueue:*得到的session，我们是不能监听到的，原因就出在NSURLSessionConfiguration上，我们进到NSURLSessionConfiguration里面看一下，他有一个属性

```objc
@property (nullable, copy) NSArray<Class> *protocolClasses;
```

我们能够看出，这是一个NSURLProtocol数组，上面我们提到了，我们监控网络是通过注册NSURLProtocol来进行网络监控的，但是通过*sessionWithConfiguration:delegate:delegateQueue:*得到的session，他的configuration中已经有一个NSURLProtocol，所以他不会走我们的protocol来，怎么解决这个问题呢？ 其实很简单，我们将NSURLSessionConfiguration的属性protocolClasses的get方法hook掉，通过返回我们自己的protocol，这样，我们就能够监控到通过*sessionWithConfiguration:delegate:delegateQueue:*得到的session的网络请求

```objc
- (void)load {
    
    self.isSwizzle=YES;
    Class cls = NSClassFromString(@"__NSCFURLSessionConfiguration") ?: NSClassFromString(@"NSURLSessionConfiguration");
    [self swizzleSelector:@selector(protocolClasses) fromClass:cls toClass:[self class]];
    
}

- (void)unload {
    
    self.isSwizzle=NO;
    Class cls = NSClassFromString(@"__NSCFURLSessionConfiguration") ?: NSClassFromString(@"NSURLSessionConfiguration");
    [self swizzleSelector:@selector(protocolClasses) fromClass:cls toClass:[self class]];
    
}

- (void)swizzleSelector:(SEL)selector fromClass:(Class)original toClass:(Class)stub {
    
    Method originalMethod = class_getInstanceMethod(original, selector);
    Method stubMethod = class_getInstanceMethod(stub, selector);
    if (!originalMethod || !stubMethod) {
        [NSException raise:NSInternalInconsistencyException format:@"Couldn't load NEURLSessionConfiguration."];
    }
    method_exchangeImplementations(originalMethod, stubMethod);
}

- (NSArray *)protocolClasses {
    
    return @[[PPSURLProtocol class]];
    //如果还有其他的监控protocol，也可以在这里加进去
}
```

在启动的时候，将这个方法替换掉，在移除监听的时候，恢复之前的方法

至此，我们的监听就完成了，如果我们需要将这所有的监听存起来，在protocol的start或者stop中获取到request和response，将他们存储起来就行，需要说明的是，据苹果的官方说明，因为请求参数可能会很大，为了保证性能，请求参数是没有被拦截掉的，就是post的HTTPBody是没有的，我没有获取出来，如果有其他的办法，还请告知

源码，放在了：

https://github.com/yangqian111/PPSNetworkMonitor

**我的个人微博：ppsheep_Qian**

**欢迎大家关注我的公众号，我会定期分享一些我在项目中遇到问题的解决办法和一些iOS实用的技巧，现阶段主要是整理出一些基础的知识记录下来**
![](http://ac-mhke0kuv.clouddn.com/830a4ead8294ceff5160.jpg)

文章也会同步更新到我的博客：
http://ppsheep.com
