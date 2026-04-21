#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFNotificationRecord : NSObject

@property (nonatomic, copy, nullable) NSString *bundleIdentifier;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *body;
@property (nonatomic, copy, nullable) NSString *header;
@property (nonatomic, copy, nullable) NSString *message;
@property (nonatomic, copy) NSString *joinedText;
@property (nonatomic, strong) NSDate *timestamp;

+ (instancetype)recordFromNotificationRequest:(id)request;
+ (instancetype)recordFromBulletin:(id)bulletin;
- (NSDictionary *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
