#import "NFPJSONImportController.h"

@interface NFPJSONImportController ()

@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) void (^importHandler)(NSDictionary * _Nullable payload, NSError * _Nullable error);
@property (nonatomic, strong) UITextView *textView;

@end

@implementation NFPJSONImportController

- (instancetype)initWithInitialText:(NSString *)initialText
                      importHandler:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))importHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = @"粘贴 JSON";
        _initialText = [initialText copy] ?: @"";
        _importHandler = [importHandler copy];
    }
    return self;
}

+ (NSDictionary *)payloadFromJSONString:(NSString *)jsonString error:(NSError **)error {
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tune.notificationfilter.import"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"JSON 文本无法编码为 UTF-8。"}];
        }
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.tune.notificationfilter.import"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"JSON 顶层必须是对象。"}];
        }
        return nil;
    }

    return object;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                            target:self
                                                                                            action:@selector(importTapped)];
    self.navigationItem.prompt = @"粘贴完整配置 JSON，保存后会覆盖当前规则";

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.alwaysBounceVertical = YES;
    textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    textView.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    textView.textContainerInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    textView.text = self.initialText;
    [self.view addSubview:textView];
    self.textView = textView;
}

- (void)importTapped {
    NSError *error = nil;
    NSDictionary *payload = [NFPJSONImportController payloadFromJSONString:self.textView.text error:&error];
    if (self.importHandler) {
        self.importHandler(payload, error);
    }

    if (payload && !error) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end
