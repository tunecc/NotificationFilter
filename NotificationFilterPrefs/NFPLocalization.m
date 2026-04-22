#import "NFPLocalization.h"
#import "../Shared/NFPreferences.h"

NSBundle *NFPPrefsBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundle = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/NotificationFilterPrefs.bundle"];
        if (!bundle) {
            bundle = [NSBundle bundleForClass:NSClassFromString(@"NFPRootListController") ?: [NSObject class]];
        }
        if (!bundle) {
            bundle = NSBundle.mainBundle;
        }
    });
    return bundle;
}

NSString *NFPLocalizedString(NSString *key) {
    return [NFPPrefsBundle() localizedStringForKey:key value:key table:@"Localizable"];
}

NSString *NFPLocalizedRuleEditorTitle(NFPRuleEditorKind editorKind) {
    switch (editorKind) {
        case NFPRuleEditorKindExclude:
            return NFPLocalizedString(@"RULE_EXCLUDE_TITLE");
        case NFPRuleEditorKindRegex:
            return NFPLocalizedString(@"RULE_REGEX_TITLE");
        default:
            return NFPLocalizedString(@"RULE_CONTAINS_TITLE");
    }
}

NSString *NFPLocalizedScopeName(NSString *scope) {
    if ([scope isEqualToString:NFRuleScopeTitle]) {
        return NFPLocalizedString(@"SCOPE_TITLE");
    }
    if ([scope isEqualToString:NFRuleScopeSubtitle]) {
        return NFPLocalizedString(@"SCOPE_SUBTITLE");
    }
    if ([scope isEqualToString:NFRuleScopeAll]) {
        return NFPLocalizedString(@"SCOPE_ALL");
    }
    return NFPLocalizedString(@"SCOPE_MESSAGE");
}

NSString *NFPLocalizedMatchModeName(NSString *mode) {
    if ([mode isEqualToString:NFMatchModeExclude]) {
        return NFPLocalizedString(@"RULE_EXCLUDE_TITLE");
    }
    if ([mode isEqualToString:NFMatchModeRegex]) {
        return NFPLocalizedString(@"RULE_REGEX_TITLE");
    }
    if ([mode isEqualToString:NFMatchModeContains]) {
        return NFPLocalizedString(@"RULE_CONTAINS_TITLE");
    }
    return mode.length > 0 ? mode : NFPLocalizedString(@"COMMON_UNKNOWN");
}

NSString *NFPLocalizedDeleteStatusName(NSString *status) {
    if ([status isEqualToString:@"success"]) {
        return NFPLocalizedString(@"DELETE_STATUS_SUCCESS");
    }
    if ([status isEqualToString:@"failed"]) {
        return NFPLocalizedString(@"DELETE_STATUS_FAILED");
    }
    if ([status isEqualToString:@"skipped"]) {
        return NFPLocalizedString(@"DELETE_STATUS_SKIPPED");
    }
    return status.length > 0 ? status : NFPLocalizedString(@"COMMON_UNKNOWN");
}

static NSString *NFPLocalizedDeleteMethodName(NSString *method) {
    if ([method isEqualToString:@"clearBulletinIDs"]) {
        return NFPLocalizedString(@"DELETE_METHOD_CLEAR_BULLETIN_IDS");
    }
    if ([method isEqualToString:@"withdrawPublisher"]) {
        return NFPLocalizedString(@"DELETE_METHOD_WITHDRAW_PUBLISHER");
    }
    if ([method isEqualToString:@"withdrawRecord"]) {
        return NFPLocalizedString(@"DELETE_METHOD_WITHDRAW_RECORD");
    }
    if ([method isEqualToString:@"removeBulletin"]) {
        return NFPLocalizedString(@"DELETE_METHOD_REMOVE_BULLETIN");
    }
    if ([method isEqualToString:@"removeBulletinReschedule"]) {
        return NFPLocalizedString(@"DELETE_METHOD_REMOVE_BULLETIN_RESCHEDULE");
    }
    if ([method isEqualToString:@"none"]) {
        return NFPLocalizedString(@"DELETE_METHOD_NONE");
    }
    if ([method isEqualToString:@"invalid-input"]) {
        return NFPLocalizedString(@"DELETE_METHOD_INVALID_INPUT");
    }
    return method.length > 0 ? method : NFPLocalizedString(@"COMMON_UNKNOWN");
}

NSString *NFPLocalizedDeleteMethodSummary(NSString *methods) {
    if (methods.length == 0) {
        return NFPLocalizedString(@"COMMON_UNKNOWN");
    }

    NSArray<NSString *> *components = [methods componentsSeparatedByString:@","];
    NSMutableArray<NSString *> *localizedComponents = [NSMutableArray arrayWithCapacity:components.count];
    for (NSString *component in components) {
        NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }
        [localizedComponents addObject:NFPLocalizedDeleteMethodName(trimmed)];
    }

    if (localizedComponents.count == 0) {
        return NFPLocalizedString(@"COMMON_UNKNOWN");
    }
    return [localizedComponents componentsJoinedByString:@", "];
}
