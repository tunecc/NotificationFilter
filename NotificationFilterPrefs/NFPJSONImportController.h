#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFPJSONImportController : UIViewController

- (instancetype)initWithInitialText:(NSString *)initialText
                      importHandler:(void (^)(NSDictionary * _Nullable payload, NSError * _Nullable error))importHandler;

+ (NSDictionary * _Nullable)payloadFromJSONString:(NSString *)jsonString error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
