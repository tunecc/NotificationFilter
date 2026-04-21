#import "NFPLogDetailController.h"
#import "../Shared/NFPreferences.h"

@interface NFPLogDetailController ()

@property (nonatomic, copy) NSDictionary *entry;
@property (nonatomic, copy) NSString *displayName;

@end

@implementation NFPLogDetailController

- (instancetype)initWithEntry:(NSDictionary *)entry displayName:(NSString *)displayName {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _entry = [entry copy];
        _displayName = [displayName copy];
        self.title = @"通知详情";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.editable = NO;
    textView.alwaysBounceVertical = YES;
    textView.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    textView.textContainerInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    textView.text = [self formattedText];
    [self.view addSubview:textView];
}

- (NSString *)formattedText {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[self.entry[NFLogTimestampKey] doubleValue]];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"应用: %@", self.displayName]];
    [lines addObject:[NSString stringWithFormat:@"Bundle ID: %@", self.entry[NFLogBundleIdentifierKey] ?: @"未知"]];
    [lines addObject:[NSString stringWithFormat:@"时间: %@", [formatter stringFromDate:date]]];
    [lines addObject:[NSString stringWithFormat:@"作用域: %@", self.entry[NFLogMatchedScopeKey] ?: @"未知"]];
    [lines addObject:[NSString stringWithFormat:@"规则类型: %@", self.entry[NFLogMatchedModeKey] ?: @"未知"]];
    [lines addObject:[NSString stringWithFormat:@"命中规则: %@", self.entry[NFLogMatchedPatternKey] ?: @"未知"]];
    [lines addObject:@""];
    [lines addObject:[NSString stringWithFormat:@"Title: %@", self.entry[NFLogTitleKey] ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"Subtitle: %@", self.entry[NFLogSubtitleKey] ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"Header: %@", self.entry[NFLogHeaderKey] ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"Body: %@", self.entry[NFLogBodyKey] ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"Message: %@", self.entry[NFLogMessageKey] ?: @""]];
    [lines addObject:@""];
    [lines addObject:@"Joined Text:"];
    [lines addObject:self.entry[NFLogJoinedTextKey] ?: @""];

    return [lines componentsJoinedByString:@"\n"];
}

@end
