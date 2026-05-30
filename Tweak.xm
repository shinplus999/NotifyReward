#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <resolv.h>

#define NRLog(fmt, ...) /* NSLog(@"[NR] " fmt, ##__VA_ARGS__) */

#define NR_SERVER   @"http://127.0.0.1:1111/notification"
#define NR_SECRET   @"secretkey"
#define NR_BUNDLE   @"com.vib.myvib2prod"
#define NR_TITLE    @"Thông báo giao dịch"

static BOOL matches(NSString *appID, NSString *title) {
    return [appID isEqualToString:NR_BUNDLE] && [title isEqualToString:NR_TITLE];
}

static void sendHTTP(NSString *host, int port, NSString *path,
                               NSDictionary *headers, NSData *body,
                               void(^cb)(BOOL ok, int statusCode)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) { if (cb) cb(NO, 0); return; }

        unsigned int ifidx = if_nametoindex("en0");
        if (ifidx > 0) {
            setsockopt(sock, IPPROTO_IP, IP_BOUND_IF, &ifidx, sizeof(ifidx));
        } else {
            NRLog(@"en0 not found");
        }

        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(port);

        if (inet_pton(AF_INET, [host UTF8String], &addr.sin_addr) != 1) {
            char portStr[8]; snprintf(portStr, sizeof(portStr), "%d", port);
            struct addrinfo hints = {0}, *res = NULL;
            hints.ai_family = AF_INET;
            hints.ai_socktype = SOCK_STREAM;
            if (getaddrinfo([host UTF8String], portStr, &hints, &res) != 0 || !res) {
                close(sock); if (cb) cb(NO, 0); return;
            }
            memcpy(&addr, res->ai_addr, sizeof(addr));
            freeaddrinfo(res);
        }

        struct timeval tv = { .tv_sec = 5, .tv_usec = 0 };
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NRLog(@"connect failed: %s", strerror(errno));
            close(sock);
            if (cb) cb(NO, 0); return;
        }

        NSMutableString *req = [NSMutableString string];
        [req appendFormat:@"POST %@ HTTP/1.1\r\n", path];
        [req appendFormat:@"Host: %@\r\n", host];
        [req appendFormat:@"Content-Length: %lu\r\n", (unsigned long)body.length];
        for (NSString *k in headers)
            [req appendFormat:@"%@: %@\r\n", k, headers[k]];
        [req appendString:@"Connection: close\r\n\r\n"];

        NSMutableData *reqData = [[req dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        [reqData appendData:body];

        ssize_t sent = send(sock, reqData.bytes, reqData.length, 0);
        if (sent < 0) { close(sock); if (cb) cb(NO, 0); return; }

        NSMutableData *resp = [NSMutableData data];
        char buf[4096];
        ssize_t n;
        while ((n = recv(sock, buf, sizeof(buf), 0)) > 0) {
            [resp appendBytes:buf length:n];
        }
        close(sock);

        NSString *respStr = [[NSString alloc] initWithData:resp encoding:NSUTF8StringEncoding];
        int code = 0;
        if (respStr.length > 12) {
            const char *cs = [respStr UTF8String];
            code = atoi(cs + 9);
        }
        NRLog(@"resp %d", code);
        if (cb) cb(code >= 200 && code < 300, code);
    });
}

static void forward(NSString *app, NSString *title, NSString *text) {
    NSString *urlStr = NR_SERVER;
    NSString *secret = NR_SECRET;

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSDictionary *payload = @{
        @"appName": app ?: @"?",
        @"title": title ?: @"",
        @"text": text ?: @"",
        @"time": @((long long)[[NSDate date] timeIntervalSince1970])
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return;

    NSString *host = url.host;
    int port = url.port ? [url.port intValue] : ([url.scheme isEqualToString:@"https"] ? 443 : 80);
    NSString *path = url.path.length > 0 ? url.path : @"/";
    if (url.query.length > 0) path = [NSString stringWithFormat:@"%@?%@", path, url.query];

    NSDictionary *headers = @{
        @"Content-Type": @"application/json",
        @"x-bank-secret": secret,
    };

    sendHTTP(host, port, path, headers, json, nil);
}

static NSMutableSet *seenIDs(void) {
    static NSMutableSet *s = nil;
    static dispatch_once_t once; dispatch_once(&once, ^{ s = [NSMutableSet set]; });
    return s;
}

static void processBulletin(id obj) {
    @try {
        id bulletin = obj;
        if ([obj respondsToSelector:@selector(bulletin)])
            bulletin = [obj performSelector:@selector(bulletin)];

        NSString *app = [bulletin valueForKey:@"sectionID"];
        NSString *tit = [bulletin valueForKey:@"title"];
        NSString *msg = [bulletin valueForKey:@"message"];
        NSString *sub = [bulletin valueForKey:@"subtitle"];

        if (![app isKindOfClass:[NSString class]] || app.length == 0)
            app = [bulletin valueForKey:@"section"];
        if (![app isKindOfClass:[NSString class]] || app.length == 0) return;

        NSString *bid = [bulletin valueForKey:@"bulletinID"]
            ?: [[bulletin valueForKey:@"publisherBulletinID"] description]
            ?: [NSString stringWithFormat:@"%@|%@", app, tit];

        @synchronized (seenIDs()) {
            if ([seenIDs() containsObject:bid]) return;
            if (seenIDs().count > 1000) [seenIDs() removeAllObjects];
            [seenIDs() addObject:bid];
        }

        if (matches(app, tit)) {
            NSString *full = ([sub isKindOfClass:[NSString class]] && sub.length > 0)
                ? [NSString stringWithFormat:@"%@ %@", sub, msg ?: @""] : (msg ?: @"");
            forward(app, tit, full);
            NRLog(@"fwd %@ - %@", app, tit);
        }
    } @catch (NSException *e) {}
}

%config(generator=internal)

%hook BBServer
- (void)publishBulletinRequest:(id)arg1 destinations:(unsigned long long)arg2 { %orig; processBulletin(arg1); }
- (void)publishBulletin:(id)arg1 destinations:(unsigned long long)arg2 { %orig; processBulletin(arg1); }
%end

%ctor {
    NRLog(@"NotifyReward loaded");
}
