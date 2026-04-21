#import "NFLogStore.h"
#import "NFPreferences.h"

@implementation NFLogStore

+ (dispatch_queue_t)_logQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tune.notificationfilter.logstore", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

+ (NSArray<NSDictionary *> *)loadEntries {
    NSString *logPath = [NFPreferences logsFilePath];
    NSArray *entries = [NSArray arrayWithContentsOfFile:logPath];
    if (![entries isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *normalizedEntries = [NSMutableArray array];
    for (id entry in entries) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            [normalizedEntries addObject:entry];
        }
    }

    return normalizedEntries;
}

+ (void)appendBlockedEntry:(NSDictionary *)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return;
    }

    dispatch_async([self _logQueue], ^{
        NSMutableDictionary *mutableEntry = [entry mutableCopy];
        if (![mutableEntry[NFLogIdentifierKey] isKindOfClass:[NSString class]]) {
            mutableEntry[NFLogIdentifierKey] = [NSUUID UUID].UUIDString;
        }
        if (![mutableEntry[NFLogTimestampKey] respondsToSelector:@selector(doubleValue)]) {
            mutableEntry[NFLogTimestampKey] = @([[NSDate date] timeIntervalSince1970]);
        }

        NSMutableArray<NSDictionary *> *entries = [[self loadEntries] mutableCopy];
        [entries insertObject:[mutableEntry copy] atIndex:0];
        if (entries.count > 500) {
            [entries removeObjectsInRange:NSMakeRange(500, entries.count - 500)];
        }

        NSString *logPath = [NFPreferences logsFilePath];
        NSString *directoryPath = [logPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        [entries writeToFile:logPath atomically:YES];
    });
}

+ (void)clearEntries {
    dispatch_sync([self _logQueue], ^{
        NSString *logPath = [NFPreferences logsFilePath];
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
    });
}

@end
