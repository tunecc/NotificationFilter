#import <Foundation/Foundation.h>

@class NFNotificationRecord;

NS_ASSUME_NONNULL_BEGIN

@interface NFMatchResult : NSObject

@property (nonatomic, assign) BOOL shouldBlock;
@property (nonatomic, copy, nullable) NSString *matchedScope;
@property (nonatomic, copy, nullable) NSString *matchedMode;
@property (nonatomic, copy, nullable) NSString *matchedPattern;

@end

@interface NFRuleEngine : NSObject

+ (NFMatchResult *)evaluateRecord:(NFNotificationRecord *)record
                      preferences:(NSDictionary *)preferences;

@end

NS_ASSUME_NONNULL_END
