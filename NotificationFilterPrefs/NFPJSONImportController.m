#import "NFPJSONImportController.h"
#import "NFPLocalization.h"

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
        self.title = NFPLocalizedString(@"JSON_IMPORT_TITLE");
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
                                     userInfo:@{NSLocalizedDescriptionKey: NFPLocalizedString(@"JSON_IMPORT_UTF8_ERROR")}];
        }
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.tune.notificationfilter.import"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: NFPLocalizedString(@"JSON_IMPORT_ROOT_OBJECT_ERROR")}];
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
    self.navigationItem.prompt = NFPLocalizedString(@"JSON_IMPORT_PROMPT");

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
