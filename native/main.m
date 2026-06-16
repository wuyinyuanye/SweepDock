#import <Cocoa/Cocoa.h>

static NSString * const SweepDockPath = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

static NSString *SweepDockStringValue(id value);
static NSString *SweepDockCleanCategoryStats(NSArray<NSDictionary<NSString *, id> *> *rows);
static unsigned long long SweepDockFileSizeAtPath(NSString *path);
static NSArray<NSDictionary<NSString *, id> *> *SweepDockDirectoryRows(NSString *path);
static NSString *SweepDockFormatDirectoryRows(NSString *path, NSArray<NSDictionary<NSString *, id> *> *rows);
static NSColor *SweepDockTextColor(void);
static NSColor *SweepDockSecondaryTextColor(void);
static NSColor *SweepDockPanelColor(void);
static NSColor *SweepDockSidebarColor(void);
static NSColor *SweepDockCardColor(void);
static NSColor *SweepDockAccentColor(void);
static NSColor *SweepDockDangerColor(void);

static NSMutableDictionary<NSString *, NSString *> *SweepDockEnvironment(void) {
    NSMutableDictionary<NSString *, NSString *> *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *home = NSHomeDirectory();
    NSString *user = NSUserName();
    NSString *tmp = NSTemporaryDirectory();

    environment[@"PATH"] = SweepDockPath;
    environment[@"TERM"] = @"xterm-256color";
    environment[@"LC_ALL"] = @"en_US.UTF-8";
    environment[@"LANG"] = @"en_US.UTF-8";

    if (home.length > 0) {
        environment[@"HOME"] = home;
    }
    if (user.length > 0) {
        environment[@"USER"] = user;
        environment[@"LOGNAME"] = user;
    }
    if (tmp.length > 0) {
        environment[@"TMPDIR"] = tmp;
    }
    if (!environment[@"SHELL"]) {
        environment[@"SHELL"] = @"/bin/zsh";
    }
    if (![fm fileExistsAtPath:environment[@"HOME"] ?: @""]) {
        environment[@"HOME"] = NSHomeDirectory();
    }

    return environment;
}

static NSString *SweepDockFindMole(void) {
    NSArray *paths = @[@"/opt/homebrew/bin/mo", @"/usr/local/bin/mo", @"/usr/bin/mo", @"/bin/mo"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fm isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

static NSDictionary<NSString *, id> *SweepDockRunCommandWithInput(NSString *executable, NSArray<NSString *> *arguments, NSString *standardInput) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    task.environment = SweepDockEnvironment();

    NSPipe *outputPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = outputPipe;
    if (standardInput.length > 0) {
        task.standardInput = [NSPipe pipe];
    }

    NSString *output = @"";
    int status = 126;

    @try {
        [task launch];
        if (standardInput.length > 0 && [task.standardInput isKindOfClass:[NSPipe class]]) {
            NSData *inputData = [standardInput dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
            NSFileHandle *inputHandle = [(NSPipe *)task.standardInput fileHandleForWriting];
            [inputHandle writeData:inputData];
            [inputHandle closeFile];
        }
        NSData *data = [[outputPipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        status = task.terminationStatus;
        output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"（无法解码命令输出）";
        if (output.length == 0) {
            output = @"（没有输出）";
        }
    } @catch (NSException *exception) {
        output = [NSString stringWithFormat:@"命令运行失败：%@", exception.reason ?: @"未知错误"];
    }

    return @{
        @"status": @(status),
        @"output": output,
    };
}

static NSDictionary<NSString *, id> *SweepDockRunCommand(NSString *executable, NSArray<NSString *> *arguments) {
    return SweepDockRunCommandWithInput(executable, arguments, nil);
}

static NSString *SweepDockFormatBytes(unsigned long long bytes) {
    NSArray<NSString *> *units = @[@"B", @"KB", @"MB", @"GB", @"TB"];
    double value = (double)bytes;
    NSUInteger index = 0;
    while (value >= 1024.0 && index < units.count - 1) {
        value /= 1024.0;
        index++;
    }
    return [NSString stringWithFormat:@"%.2f %@", value, units[index]];
}

static NSString *SweepDockFormatAnalyzeJSON(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return json;
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:[NSDictionary class]]) {
        return json;
    }

    NSDictionary *root = (NSDictionary *)object;
    NSArray *entries = root[@"entries"];
    NSNumber *totalSize = root[@"total_size"];
    NSString *path = root[@"path"] ?: @"/";

    NSMutableString *formatted = [NSMutableString string];
    [formatted appendFormat:@"磁盘分析：%@\n", path];
    if ([totalSize respondsToSelector:@selector(unsignedLongLongValue)]) {
        [formatted appendFormat:@"总占用：%@\n", SweepDockFormatBytes(totalSize.unsignedLongLongValue)];
    }
    [formatted appendString:@"\n"];

    if (![entries isKindOfClass:[NSArray class]] || entries.count == 0) {
        [formatted appendString:@"没有可展示的分析条目。"];
        return formatted;
    }

    [formatted appendString:@"主要空间占用\n"];
    [formatted appendString:@"----------------------------------------\n"];

    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = entry[@"name"] ?: @"未命名";
        NSString *entryPath = entry[@"path"] ?: @"";
        NSNumber *size = entry[@"size"] ?: @0;
        BOOL insight = [entry[@"insight"] boolValue];
        NSString *tag = insight ? @"  建议关注" : @"";

        [formatted appendFormat:@"%@  %@%@\n", SweepDockFormatBytes(size.unsignedLongLongValue), name, tag];
        if (entryPath.length > 0) {
            [formatted appendFormat:@"    %@\n", entryPath];
        }
        [formatted appendString:@"\n"];
    }

    return formatted;
}

static NSArray<NSDictionary<NSString *, id> *> *SweepDockAnalyzeEntries(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @[];
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:[NSDictionary class]]) {
        return @[];
    }

    NSArray *entries = ((NSDictionary *)object)[@"entries"];
    if (![entries isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        [rows addObject:@{
            @"name": SweepDockStringValue(entry[@"name"]),
            @"size": SweepDockFormatBytes([entry[@"size"] unsignedLongLongValue]),
            @"path": SweepDockStringValue(entry[@"path"]),
            @"tag": [entry[@"insight"] boolValue] ? @"建议关注" : @"目录",
            @"is_dir": @([entry[@"is_dir"] boolValue]),
        }];
    }
    return rows;
}

static unsigned long long SweepDockFileSizeAtPath(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory]) {
        return 0;
    }

    if (!isDirectory) {
        NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
        return [attributes[NSFileSize] unsignedLongLongValue];
    }

    unsigned long long total = 0;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:path]
                                includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLFileSizeKey, NSURLTotalFileAllocatedSizeKey]
                                                   options:(NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants)
                                              errorHandler:^BOOL(NSURL *url, NSError *error) {
        return YES;
    }];

    for (NSURL *url in enumerator) {
        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            continue;
        }
        NSNumber *allocatedSize = nil;
        NSNumber *fileSize = nil;
        [url getResourceValue:&allocatedSize forKey:NSURLTotalFileAllocatedSizeKey error:nil];
        [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        total += allocatedSize.unsignedLongLongValue ?: fileSize.unsignedLongLongValue;
    }

    return total;
}

static NSArray<NSDictionary<NSString *, id> *> *SweepDockDirectoryRows(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return @[];
    }

    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:path error:nil] ?: @[];
    NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
    for (NSString *child in children) {
        if ([child hasPrefix:@"."]) {
            continue;
        }
        NSString *childPath = [path stringByAppendingPathComponent:child];
        BOOL childIsDirectory = NO;
        [fm fileExistsAtPath:childPath isDirectory:&childIsDirectory];
        unsigned long long size = SweepDockFileSizeAtPath(childPath);
        [rows addObject:@{
            @"name": child,
            @"size": SweepDockFormatBytes(size),
            @"bytes": @(size),
            @"path": childPath,
            @"tag": childIsDirectory ? @"目录" : @"文件",
            @"is_dir": @(childIsDirectory),
        }];
    }

    [rows sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *a, NSDictionary<NSString *, id> *b) {
        return [b[@"bytes"] compare:a[@"bytes"]];
    }];
    return rows;
}

static NSString *SweepDockFormatDirectoryRows(NSString *path, NSArray<NSDictionary<NSString *, id> *> *rows) {
    unsigned long long total = 0;
    for (NSDictionary<NSString *, id> *row in rows ?: @[]) {
        total += [row[@"bytes"] unsignedLongLongValue];
    }

    NSMutableString *formatted = [NSMutableString string];
    [formatted appendFormat:@"目录分析：%@\n", path ?: @""];
    [formatted appendFormat:@"当前层合计：%@ · %lu 个条目\n", SweepDockFormatBytes(total), (unsigned long)(rows ?: @[]).count];
    [formatted appendString:@"----------------------------------------\n\n"];
    for (NSDictionary<NSString *, id> *row in rows ?: @[]) {
        [formatted appendFormat:@"%@  %@  %@\n",
            SweepDockStringValue(row[@"size"]),
            SweepDockStringValue(row[@"tag"]),
            SweepDockStringValue(row[@"name"])];
        [formatted appendFormat:@"    %@\n\n", SweepDockStringValue(row[@"path"])];
    }
    return formatted;
}

static NSString *SweepDockAnalyzeSummary(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @"";
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return @"";
    }
    NSDictionary *root = (NSDictionary *)object;
    NSArray *entries = root[@"entries"];
    NSNumber *totalSize = root[@"total_size"];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if ([totalSize respondsToSelector:@selector(unsignedLongLongValue)]) {
        [parts addObject:[NSString stringWithFormat:@"总占用 %@", SweepDockFormatBytes(totalSize.unsignedLongLongValue)]];
    }
    if ([entries isKindOfClass:[NSArray class]]) {
        [parts addObject:[NSString stringWithFormat:@"%lu 个条目", (unsigned long)entries.count]];
    }
    return [parts componentsJoinedByString:@" · "];
}

static NSString *SweepDockFirstMatch(NSString *text, NSString *pattern) {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    if (error) {
        return nil;
    }
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || match.numberOfRanges < 2) {
        return nil;
    }
    NSRange range = [match rangeAtIndex:1];
    if (range.location == NSNotFound) {
        return nil;
    }
    return [text substringWithRange:range];
}

static NSString *SweepDockCleanItemStatus(NSString *line) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"→"]) {
        return @"可清理";
    }
    if ([trimmed hasPrefix:@"✓"]) {
        return @"正常";
    }
    if ([trimmed hasPrefix:@"◎"]) {
        return @"跳过";
    }
    if ([trimmed hasPrefix:@"•"]) {
        return @"需确认";
    }
    if ([trimmed hasPrefix:@"☞"]) {
        return @"提示";
    }
    return @"说明";
}

static NSArray<NSDictionary<NSString *, id> *> *SweepDockFilterRows(NSArray<NSDictionary<NSString *, id> *> *rows, NSString *query, NSString *tag) {
    NSString *needle = [[query ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSString *wantedTag = [tag ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (needle.length == 0) {
        if (wantedTag.length == 0 || [wantedTag isEqualToString:@"全部"]) {
            return rows ?: @[];
        }
    }

    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *row in rows ?: @[]) {
        NSString *rowTag = SweepDockStringValue(row[@"tag"]);
        if (wantedTag.length > 0 && ![wantedTag isEqualToString:@"全部"] && ![rowTag isEqualToString:wantedTag]) {
            continue;
        }
        NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@ %@",
            SweepDockStringValue(row[@"size"]),
            SweepDockStringValue(row[@"name"]),
            SweepDockStringValue(row[@"tag"]),
            SweepDockStringValue(row[@"path"])] lowercaseString];
        if (needle.length == 0 || [haystack containsString:needle]) {
            [filtered addObject:row];
        }
    }
    return filtered;
}

static NSString *SweepDockFormatCleanDryRun(NSString *output) {
    NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableString *formatted = [NSMutableString string];

    NSString *potential = SweepDockFirstMatch(output, @"Potential space: ([^|\\n]+)");
    NSString *items = SweepDockFirstMatch(output, @"Items: ([0-9]+)");
    NSString *categories = SweepDockFirstMatch(output, @"Categories: ([0-9]+)");
    NSString *detailFile = SweepDockFirstMatch(output, @"Detailed file list: ([^\\n]+)");

    [formatted appendString:@"清理预览完成，未删除任何文件。\n"];
    if (potential.length > 0 || items.length > 0 || categories.length > 0) {
        [formatted appendString:@"\n摘要\n"];
        [formatted appendString:@"----------------------------------------\n"];
        if (potential.length > 0) {
            [formatted appendFormat:@"潜在可释放空间：%@\n", [potential stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
        if (items.length > 0) {
            [formatted appendFormat:@"候选条目：%@\n", items];
        }
        if (categories.length > 0) {
            [formatted appendFormat:@"涉及分类：%@\n", categories];
        }
        if (detailFile.length > 0) {
            [formatted appendFormat:@"详细清单：%@\n", detailFile];
        }
    }

    [formatted appendString:@"\n分类明细\n"];
    [formatted appendString:@"----------------------------------------\n"];

    NSString *currentCategory = nil;
    NSMutableArray<NSString *> *pendingNotes = [NSMutableArray array];
    BOOL foundCategory = NO;

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }

        if ([trimmed hasPrefix:@"➤"]) {
            currentCategory = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [formatted appendFormat:@"\n%@\n", currentCategory];
            foundCategory = YES;
            [pendingNotes removeAllObjects];
            continue;
        }

        if (!currentCategory) {
            continue;
        }

        if ([trimmed hasPrefix:@"↳"]) {
            NSString *note = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [pendingNotes addObject:note];
            continue;
        }

        if ([trimmed hasPrefix:@"→"] || [trimmed hasPrefix:@"✓"] || [trimmed hasPrefix:@"◎"] || [trimmed hasPrefix:@"•"] || [trimmed hasPrefix:@"☞"]) {
            NSString *status = SweepDockCleanItemStatus(trimmed);
            NSString *body = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [formatted appendFormat:@"  [%@] %@\n", status, body];
            for (NSString *note in pendingNotes) {
                [formatted appendFormat:@"        %@\n", note];
            }
            [pendingNotes removeAllObjects];
        }
    }

    if (!foundCategory) {
        [formatted appendString:@"没有识别到分类明细，保留原始输出：\n\n"];
        [formatted appendString:output];
    }

    return formatted;
}

static NSString *SweepDockCleanSummary(NSString *output, NSArray<NSDictionary<NSString *, id> *> *rows) {
    NSString *potential = [(SweepDockFirstMatch(output, @"Potential space: ([^|\\n]+)") ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *items = SweepDockFirstMatch(output, @"Items: ([0-9]+)") ?: @"";
    NSString *categories = SweepDockFirstMatch(output, @"Categories: ([0-9]+)") ?: @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (potential.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"潜在空间 %@", potential]];
    }
    if (items.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"%@ 个候选条目", items]];
    }
    if (categories.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"%@ 个分类", categories]];
    }
    [parts addObject:[NSString stringWithFormat:@"表格 %lu 行", (unsigned long)(rows ?: @[]).count]];
    NSString *categoryStats = SweepDockCleanCategoryStats(rows);
    if (categoryStats.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"主要分类：%@", categoryStats]];
    }
    return [parts componentsJoinedByString:@" · "];
}

static NSString *SweepDockCleanItemSize(NSString *body) {
    NSString *size = SweepDockFirstMatch(body, @"([0-9]+(?:\\.[0-9]+)?\\s?(?:B|KB|MB|GB|TB))\\s+dry");
    if (size.length > 0) {
        return size;
    }
    size = SweepDockFirstMatch(body, @"\\(([0-9]+(?:\\.[0-9]+)?\\s?(?:B|KB|MB|GB|TB))\\)");
    if (size.length > 0) {
        return size;
    }
    if ([body containsString:@"0B"]) {
        return @"0B";
    }
    return @"";
}

static NSArray<NSDictionary<NSString *, id> *> *SweepDockCleanPreviewRows(NSString *output) {
    NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *rows = [NSMutableArray array];
    NSString *currentCategory = @"";
    NSMutableArray<NSString *> *pendingNotes = [NSMutableArray array];

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }

        if ([trimmed hasPrefix:@"➤"]) {
            currentCategory = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [pendingNotes removeAllObjects];
            continue;
        }

        if ([trimmed hasPrefix:@"↳"]) {
            NSString *note = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (note.length > 0) {
                [pendingNotes addObject:note];
            }
            continue;
        }

        if (![trimmed hasPrefix:@"→"] && ![trimmed hasPrefix:@"✓"] && ![trimmed hasPrefix:@"◎"] && ![trimmed hasPrefix:@"•"] && ![trimmed hasPrefix:@"☞"]) {
            continue;
        }

        NSString *status = SweepDockCleanItemStatus(trimmed);
        NSString *body = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *notes = [pendingNotes componentsJoinedByString:@" | "];
        NSString *path = notes.length > 0 ? [NSString stringWithFormat:@"%@ · %@", currentCategory, notes] : currentCategory;
        [rows addObject:@{
            @"size": SweepDockCleanItemSize(body),
            @"name": body,
            @"tag": status,
            @"path": path ?: @"",
        }];
        [pendingNotes removeAllObjects];
    }

    return rows;
}

static NSString *SweepDockCleanCategoryStats(NSArray<NSDictionary<NSString *, id> *> *rows) {
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *cleanableCounts = [NSMutableDictionary dictionary];

    for (NSDictionary<NSString *, id> *row in rows ?: @[]) {
        NSString *category = SweepDockStringValue(row[@"path"]);
        NSRange noteRange = [category rangeOfString:@" · "];
        if (noteRange.location != NSNotFound) {
            category = [category substringToIndex:noteRange.location];
        }
        if (category.length == 0) {
            category = @"未分类";
        }

        counts[category] = @([counts[category] unsignedIntegerValue] + 1);
        if ([SweepDockStringValue(row[@"tag"]) isEqualToString:@"可清理"]) {
            cleanableCounts[category] = @([cleanableCounts[category] unsignedIntegerValue] + 1);
        }
    }

    NSArray<NSString *> *sortedCategories = [counts keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [b compare:a];
    }];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger limit = MIN((NSUInteger)3, sortedCategories.count);
    for (NSUInteger index = 0; index < limit; index++) {
        NSString *category = sortedCategories[index];
        NSUInteger total = [counts[category] unsignedIntegerValue];
        NSUInteger cleanable = [cleanableCounts[category] unsignedIntegerValue];
        if (cleanable > 0) {
            [parts addObject:[NSString stringWithFormat:@"%@ %lu 项（可清理 %lu）", category, (unsigned long)total, (unsigned long)cleanable]];
        } else {
            [parts addObject:[NSString stringWithFormat:@"%@ %lu 项", category, (unsigned long)total]];
        }
    }

    return [parts componentsJoinedByString:@" · "];
}

static NSString *SweepDockStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    return @"";
}

static NSColor *SweepDockTextColor(void) {
    return [NSColor colorWithCalibratedRed:0.09 green:0.10 blue:0.12 alpha:1.0];
}

static NSColor *SweepDockSecondaryTextColor(void) {
    return [NSColor colorWithCalibratedRed:0.39 green:0.42 blue:0.48 alpha:1.0];
}

static NSColor *SweepDockPanelColor(void) {
    return [NSColor colorWithCalibratedRed:0.945 green:0.948 blue:0.952 alpha:1.0];
}

static NSColor *SweepDockSidebarColor(void) {
    return [NSColor colorWithCalibratedRed:0.915 green:0.920 blue:0.925 alpha:1.0];
}

static NSColor *SweepDockCardColor(void) {
    return [NSColor colorWithCalibratedRed:0.985 green:0.987 blue:0.990 alpha:1.0];
}

static NSColor *SweepDockAccentColor(void) {
    return [NSColor colorWithCalibratedRed:0.16 green:0.17 blue:0.19 alpha:1.0];
}

static NSColor *SweepDockDangerColor(void) {
    return [NSColor colorWithCalibratedRed:0.58 green:0.35 blue:0.12 alpha:1.0];
}

static NSString *SweepDockPercent(NSNumber *number) {
    if (![number respondsToSelector:@selector(doubleValue)]) {
        return @"-";
    }
    return [NSString stringWithFormat:@"%.1f%%", number.doubleValue];
}

static NSString *SweepDockFormatStatusJSON(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return json;
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:[NSDictionary class]]) {
        return json;
    }

    NSDictionary *root = (NSDictionary *)object;
    NSDictionary *hardware = root[@"hardware"];
    NSDictionary *cpu = root[@"cpu"];
    NSDictionary *memory = root[@"memory"];
    NSArray *disks = root[@"disks"];
    NSArray *network = root[@"network"];
    NSArray *topProcesses = root[@"top_processes"];
    NSDictionary *proxy = root[@"proxy"];

    NSMutableString *formatted = [NSMutableString string];
    [formatted appendString:@"系统状态\n"];
    [formatted appendString:@"----------------------------------------\n"];
    [formatted appendFormat:@"主机：%@\n", SweepDockStringValue(root[@"host"])];
    [formatted appendFormat:@"系统：%@\n", SweepDockStringValue(hardware[@"os_version"] ?: root[@"platform"])];
    [formatted appendFormat:@"机型：%@ · %@ · 内存 %@\n",
        SweepDockStringValue(hardware[@"model"]),
        SweepDockStringValue(hardware[@"cpu_model"]),
        SweepDockStringValue(hardware[@"total_ram"])];
    [formatted appendFormat:@"运行时间：%@\n", SweepDockStringValue(root[@"uptime"])];
    [formatted appendFormat:@"健康分：%@ / 100（%@）\n",
        SweepDockStringValue(root[@"health_score"]),
        SweepDockStringValue(root[@"health_score_msg"])];

    [formatted appendString:@"\n资源\n"];
    [formatted appendString:@"----------------------------------------\n"];
    [formatted appendFormat:@"CPU：%@ · 负载 %.2f / %.2f / %.2f · 核心 %@\n",
        SweepDockPercent(cpu[@"usage"]),
        [cpu[@"load1"] doubleValue],
        [cpu[@"load5"] doubleValue],
        [cpu[@"load15"] doubleValue],
        SweepDockStringValue(cpu[@"core_count"])];
    if ([memory isKindOfClass:[NSDictionary class]]) {
        [formatted appendFormat:@"内存：%@ / %@（%@）· 可用 %@ · Swap %@\n",
            SweepDockFormatBytes([memory[@"used"] unsignedLongLongValue]),
            SweepDockFormatBytes([memory[@"total"] unsignedLongLongValue]),
            SweepDockPercent(memory[@"used_percent"]),
            SweepDockFormatBytes([memory[@"available"] unsignedLongLongValue]),
            SweepDockFormatBytes([memory[@"swap_used"] unsignedLongLongValue])];
    }
    if ([disks isKindOfClass:[NSArray class]]) {
        for (NSDictionary *disk in disks) {
            if (![disk isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            [formatted appendFormat:@"磁盘 %@：%@ / %@（%@）\n",
                SweepDockStringValue(disk[@"mount"]),
                SweepDockFormatBytes([disk[@"used"] unsignedLongLongValue]),
                SweepDockFormatBytes([disk[@"total"] unsignedLongLongValue]),
                SweepDockPercent(disk[@"used_percent"])];
        }
    }

    [formatted appendString:@"\n网络\n"];
    [formatted appendString:@"----------------------------------------\n"];
    if ([proxy isKindOfClass:[NSDictionary class]] && [proxy[@"enabled"] boolValue]) {
        [formatted appendFormat:@"代理：%@ %@\n", SweepDockStringValue(proxy[@"type"]), SweepDockStringValue(proxy[@"host"])];
    } else {
        [formatted appendString:@"代理：未启用\n"];
    }
    if ([network isKindOfClass:[NSArray class]]) {
        for (NSDictionary *iface in network) {
            if (![iface isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *ip = SweepDockStringValue(iface[@"ip"]);
            if (ip.length == 0) {
                continue;
            }
            [formatted appendFormat:@"%@：%@ · ↓ %.2f MB/s · ↑ %.2f MB/s\n",
                SweepDockStringValue(iface[@"name"]),
                ip,
                [iface[@"rx_rate_mbs"] doubleValue],
                [iface[@"tx_rate_mbs"] doubleValue]];
        }
    }

    [formatted appendString:@"\n高占用进程\n"];
    [formatted appendString:@"----------------------------------------\n"];
    if ([topProcesses isKindOfClass:[NSArray class]] && topProcesses.count > 0) {
        for (NSDictionary *process in topProcesses) {
            if (![process isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            [formatted appendFormat:@"%@  CPU %.1f%%  内存 %.1f%%  PID %@\n",
                SweepDockStringValue(process[@"name"]),
                [process[@"cpu"] doubleValue],
                [process[@"memory"] doubleValue],
                SweepDockStringValue(process[@"pid"])];
        }
    } else {
        [formatted appendString:@"暂无进程告警。\n"];
    }

    return formatted;
}

static NSString *SweepDockStatusSummary(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @"";
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return @"";
    }
    NSDictionary *root = (NSDictionary *)object;
    NSDictionary *cpu = root[@"cpu"];
    NSDictionary *memory = root[@"memory"];
    NSArray *disks = root[@"disks"];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"健康分 %@", SweepDockStringValue(root[@"health_score"])]];
    if ([cpu isKindOfClass:[NSDictionary class]]) {
        [parts addObject:[NSString stringWithFormat:@"CPU %@", SweepDockPercent(cpu[@"usage"])]];
    }
    if ([memory isKindOfClass:[NSDictionary class]]) {
        [parts addObject:[NSString stringWithFormat:@"内存 %@", SweepDockPercent(memory[@"used_percent"])]];
    }
    if ([disks isKindOfClass:[NSArray class]] && disks.count > 0) {
        NSDictionary *disk = disks.firstObject;
        if ([disk isKindOfClass:[NSDictionary class]]) {
            [parts addObject:[NSString stringWithFormat:@"磁盘 %@", SweepDockPercent(disk[@"used_percent"])]];
        }
    }
    return [parts componentsJoinedByString:@" · "];
}

static NSString *SweepDockFormatHistoryJSON(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return json;
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:[NSDictionary class]]) {
        return json;
    }

    NSDictionary *root = (NSDictionary *)object;
    NSDictionary *logs = root[@"logs"];
    NSArray *sessions = root[@"sessions"];
    NSArray *deletions = root[@"deletions"];

    NSMutableString *formatted = [NSMutableString string];
    [formatted appendString:@"清理历史\n"];
    [formatted appendString:@"----------------------------------------\n"];
    [formatted appendFormat:@"操作日志：%@\n", SweepDockStringValue(logs[@"operations"])];
    [formatted appendFormat:@"删除日志：%@\n", SweepDockStringValue(logs[@"deletions"])];
    [formatted appendFormat:@"最近记录：%@ 条\n", SweepDockStringValue(root[@"limit"])];

    [formatted appendString:@"\n最近会话\n"];
    [formatted appendString:@"----------------------------------------\n"];
    if ([sessions isKindOfClass:[NSArray class]] && sessions.count > 0) {
        for (NSDictionary *session in sessions) {
            if (![session isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *actions = session[@"actions"];
            [formatted appendFormat:@"%@  %@  %@ · %@ 项 · 操作 %@\n",
                SweepDockStringValue(session[@"started_at"]),
                SweepDockStringValue(session[@"command"]),
                SweepDockStringValue(session[@"size"]),
                SweepDockStringValue(session[@"items"]),
                SweepDockStringValue(session[@"operation_count"])];
            if ([actions isKindOfClass:[NSDictionary class]]) {
                [formatted appendFormat:@"    删除 %@ · 跳过 %@ · 失败 %@\n",
                    SweepDockStringValue(actions[@"removed"]),
                    SweepDockStringValue(actions[@"skipped"]),
                    SweepDockStringValue(actions[@"failed"])];
            }
        }
    } else {
        [formatted appendString:@"暂无历史会话。\n"];
    }

    [formatted appendString:@"\n删除记录\n"];
    [formatted appendString:@"----------------------------------------\n"];
    if ([deletions isKindOfClass:[NSArray class]] && deletions.count > 0) {
        for (NSDictionary *deletion in deletions) {
            if (![deletion isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            [formatted appendFormat:@"%@\n", deletion];
        }
    } else {
        [formatted appendString:@"暂无删除记录。\n"];
    }

    return formatted;
}

static NSString *SweepDockHistorySummary(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @"";
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return @"";
    }
    NSDictionary *root = (NSDictionary *)object;
    NSArray *sessions = root[@"sessions"];
    NSArray *deletions = root[@"deletions"];
    return [NSString stringWithFormat:@"最近会话 %lu 条 · 删除记录 %lu 条",
        (unsigned long)([sessions isKindOfClass:[NSArray class]] ? sessions.count : 0),
        (unsigned long)([deletions isKindOfClass:[NSArray class]] ? deletions.count : 0)];
}

static NSString *SweepDockFormatUninstallListJSON(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return json;
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:[NSArray class]]) {
        return json;
    }

    NSArray *apps = (NSArray *)object;
    NSMutableString *formatted = [NSMutableString string];
    [formatted appendFormat:@"已安装应用：%lu 个\n", (unsigned long)apps.count];
    [formatted appendString:@"----------------------------------------\n"];
    [formatted appendString:@"在右上角输入应用名，然后点“卸载预览”。请使用下面显示的名称。\n\n"];

    for (NSDictionary *app in apps) {
        if (![app isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        [formatted appendFormat:@"%@\n", SweepDockStringValue(app[@"uninstall_name"] ?: app[@"name"])];
        [formatted appendFormat:@"    Bundle ID：%@\n", SweepDockStringValue(app[@"bundle_id"])];
        [formatted appendFormat:@"    路径：%@\n\n", SweepDockStringValue(app[@"path"])];
    }

    return formatted;
}

static NSString *SweepDockUninstallListSummary(NSString *json, NSUInteger rowCount) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSUInteger count = [object isKindOfClass:[NSArray class]] ? [(NSArray *)object count] : rowCount;
    return [NSString stringWithFormat:@"已安装应用 %lu 个 · 表格 %lu 行", (unsigned long)count, (unsigned long)rowCount];
}

static NSArray<NSDictionary<NSString *, id> *> *SweepDockUninstallListRows(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @[];
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![object isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *app in (NSArray *)object) {
        if (![app isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = SweepDockStringValue(app[@"uninstall_name"] ?: app[@"name"]);
        [rows addObject:@{
            @"name": name,
            @"size": SweepDockStringValue(app[@"size"]),
            @"tag": SweepDockStringValue(app[@"source"]),
            @"path": SweepDockStringValue(app[@"path"]),
            @"uninstall_name": name,
        }];
    }
    return rows;
}

static NSString *SweepDockFormatUninstallDryRun(NSString *output) {
    NSMutableString *formatted = [NSMutableString string];
    [formatted appendString:@"卸载预览完成，未删除任何文件。\n"];
    [formatted appendString:@"----------------------------------------\n\n"];
    [formatted appendString:output];
    return formatted;
}

static NSString *SweepDockFormatUninstallRun(NSString *output) {
    NSMutableString *formatted = [NSMutableString string];
    [formatted appendString:@"卸载命令已完成。\n"];
    [formatted appendString:@"----------------------------------------\n"];
    [formatted appendString:@"Mole 默认会把可恢复项目移动到 macOS 废纸篓；如需恢复，请先检查废纸篓和下面的命令输出。\n\n"];
    [formatted appendString:output];
    return formatted;
}

static NSString *SweepDockFormatPurgeDryRun(NSString *output) {
    NSMutableString *formatted = [NSMutableString string];
    [formatted appendString:@"项目清理预览完成，未删除任何文件。\n"];
    [formatted appendString:@"----------------------------------------\n\n"];
    [formatted appendString:output];
    return formatted;
}

static NSString *SweepDockPurgeSummary(NSString *output) {
    if ([output containsString:@"No old project artifacts"]) {
        return @"没有发现旧项目产物";
    }
    NSString *potential = SweepDockFirstMatch(output, @"Potential space: ([^|\\n]+)");
    if (potential.length > 0) {
        return [NSString stringWithFormat:@"潜在空间 %@", [potential stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    }
    return @"项目清理预览完成";
}

static NSString *SweepDockFormatOptimizeDryRun(NSString *output) {
    NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableString *formatted = [NSMutableString string];
    NSString *wouldApply = SweepDockFirstMatch(output, @"Would apply ([0-9]+ optimizations)");

    [formatted appendString:@"系统优化预览完成，未修改任何文件。\n"];
    if (wouldApply.length > 0) {
        [formatted appendFormat:@"将执行：%@\n", wouldApply];
    }
    [formatted appendString:@"----------------------------------------\n"];

    NSString *currentCategory = nil;
    BOOL foundCategory = NO;
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }
        if ([trimmed isEqualToString:@"PERFORMANCE DIAGNOSIS"]) {
            currentCategory = @"性能诊断";
            [formatted appendFormat:@"\n%@\n", currentCategory];
            foundCategory = YES;
            continue;
        }
        if ([trimmed hasPrefix:@"➤"]) {
            currentCategory = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [formatted appendFormat:@"\n%@\n", currentCategory];
            foundCategory = YES;
            continue;
        }
        if (!currentCategory) {
            continue;
        }
        if ([trimmed hasPrefix:@"→"] || [trimmed hasPrefix:@"✓"] || [trimmed hasPrefix:@"◎"] || [trimmed hasPrefix:@"☞"]) {
            NSString *status = SweepDockCleanItemStatus(trimmed);
            NSString *body = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [formatted appendFormat:@"  [%@] %@\n", status, body];
        }
    }

    if (!foundCategory) {
        [formatted appendString:@"\n"];
        [formatted appendString:output];
    }

    return formatted;
}

static NSString *SweepDockFormatOptimizeRun(NSString *output) {
    NSMutableString *formatted = [NSMutableString string];
    [formatted appendString:@"系统优化命令已完成。\n"];
    [formatted appendString:@"----------------------------------------\n\n"];
    [formatted appendString:output];
    return formatted;
}

static NSString *SweepDockOptimizeSummary(NSString *output) {
    NSString *wouldApply = SweepDockFirstMatch(output, @"Would apply ([0-9]+ optimizations)");
    if (wouldApply.length > 0) {
        return [NSString stringWithFormat:@"将执行 %@", wouldApply];
    }
    return @"系统优化预览完成";
}

static int SweepDockSelfTest(void) {
    NSString *mole = SweepDockFindMole();
    if (mole.length == 0) {
        fprintf(stderr, "FAIL: mo executable not found\n");
        return 1;
    }

    NSArray<NSArray<NSString *> *> *tests = @[
        @[@"--help"],
        @[@"status"],
        @[@"analyze", @"--json"],
        @[@"clean", @"--dry-run"],
        @[@"history", @"--json"],
        @[@"uninstall", @"--list"],
        @[@"purge", @"--dry-run"],
        @[@"optimize", @"--dry-run"],
    ];

    for (NSArray<NSString *> *arguments in tests) {
        NSString *command = [NSString stringWithFormat:@"%@ %@", mole, [arguments componentsJoinedByString:@" "]];
        printf("TEST %s\n", command.UTF8String);
        NSDictionary<NSString *, id> *result = SweepDockRunCommand(mole, arguments);
        int status = [result[@"status"] intValue];
        NSString *output = result[@"output"];
        BOOL allowedNonZero = (arguments.count >= 2 &&
            [arguments[0] isEqualToString:@"purge"] &&
            [arguments[1] isEqualToString:@"--dry-run"] &&
            status == 2 &&
            [output containsString:@"No old project artifacts"]);
        if (status != 0 && !allowedNonZero) {
            fprintf(stderr, "FAIL: %s exited with code %d\n%s\n", command.UTF8String, status, output.UTF8String);
            return status == 0 ? 1 : status;
        }
        if (arguments.count >= 2 && [arguments[0] isEqualToString:@"analyze"] && [arguments[1] isEqualToString:@"--json"]) {
            NSString *formatted = SweepDockFormatAnalyzeJSON(output);
            NSArray *rows = SweepDockAnalyzeEntries(output);
            NSArray *filtered = SweepDockFilterRows(rows, @"Library", @"全部");
            NSString *summary = SweepDockAnalyzeSummary(output);
            NSArray *directoryRows = SweepDockDirectoryRows(@"/Applications");
            if (![formatted containsString:@"磁盘分析"] || ![formatted containsString:@"主要空间占用"] || rows.count == 0 || filtered.count == 0 || summary.length == 0 || directoryRows.count == 0) {
                fprintf(stderr, "FAIL: analyze JSON formatting did not produce expected summary\n%s\n", formatted.UTF8String);
                return 1;
            }
        }
        if (arguments.count >= 1 && [arguments[0] isEqualToString:@"status"]) {
            NSString *formatted = SweepDockFormatStatusJSON(output);
            NSString *summary = SweepDockStatusSummary(output);
            if (![formatted containsString:@"系统状态"] || ![formatted containsString:@"资源"] || summary.length == 0) {
                fprintf(stderr, "FAIL: status JSON formatting did not produce expected summary\n%s\n", formatted.UTF8String);
                return 1;
            }
        }
        if (arguments.count >= 2 && [arguments[0] isEqualToString:@"clean"] && [arguments[1] isEqualToString:@"--dry-run"]) {
            NSString *formatted = SweepDockFormatCleanDryRun(output);
            NSArray *rows = SweepDockCleanPreviewRows(output);
            NSArray *filtered = SweepDockFilterRows(rows, @"cache", @"全部");
            NSArray *statusFiltered = SweepDockFilterRows(rows, @"", @"可清理");
            NSString *summary = SweepDockCleanSummary(output, rows);
            NSString *categoryStats = SweepDockCleanCategoryStats(rows);
            if (![formatted containsString:@"清理预览完成"] || ![formatted containsString:@"分类明细"] || rows.count == 0 || filtered.count == 0 || statusFiltered.count == 0 || summary.length == 0 || categoryStats.length == 0) {
                fprintf(stderr, "FAIL: clean dry-run formatting did not produce expected summary\n%s\n", formatted.UTF8String);
                return 1;
            }
        }
        if (arguments.count >= 2 && [arguments[0] isEqualToString:@"history"] && [arguments[1] isEqualToString:@"--json"]) {
            NSString *formatted = SweepDockFormatHistoryJSON(output);
            NSString *summary = SweepDockHistorySummary(output);
            if (![formatted containsString:@"清理历史"] || ![formatted containsString:@"最近会话"] || summary.length == 0) {
                fprintf(stderr, "FAIL: history JSON formatting did not produce expected summary\n%s\n", formatted.UTF8String);
                return 1;
            }
        }
        if (arguments.count >= 2 && [arguments[0] isEqualToString:@"uninstall"] && [arguments[1] isEqualToString:@"--list"]) {
            NSString *formatted = SweepDockFormatUninstallListJSON(output);
            NSArray *rows = SweepDockUninstallListRows(output);
            NSArray *filtered = SweepDockFilterRows(rows, @"app", @"全部");
            NSString *summary = SweepDockUninstallListSummary(output, rows.count);
            if (![formatted containsString:@"已安装应用"] || ![formatted containsString:@"卸载预览"] || rows.count == 0 || filtered.count == 0 || summary.length == 0) {
                fprintf(stderr, "FAIL: uninstall list formatting did not produce expected summary\n%s\n", formatted.UTF8String);
                return 1;
            }
        }
        if (arguments.count >= 2 && [arguments[0] isEqualToString:@"purge"] && [arguments[1] isEqualToString:@"--dry-run"]) {
            NSString *formatted = SweepDockFormatPurgeDryRun(output);
            NSString *summary = SweepDockPurgeSummary(output);
            if (![formatted containsString:@"项目清理预览完成"] || summary.length == 0) {
                fprintf(stderr, "FAIL: purge dry-run formatting did not produce expected summary\n%s\n", formatted.UTF8String);
                return 1;
            }
        }
        if (arguments.count >= 2 && [arguments[0] isEqualToString:@"optimize"] && [arguments[1] isEqualToString:@"--dry-run"]) {
            NSString *formatted = SweepDockFormatOptimizeDryRun(output);
            NSString *summary = SweepDockOptimizeSummary(output);
            if (![formatted containsString:@"系统优化预览完成"] || summary.length == 0) {
                fprintf(stderr, "FAIL: optimize dry-run formatting did not produce expected summary\n%s\n", formatted.UTF8String);
                return 1;
            }
        }
        printf("PASS: %s\n", command.UTF8String);
    }

    printf("SELF TEST PASSED\n");
    return 0;
}

@interface SweepDockAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property NSWindow *window;
@property NSTextView *outputView;
@property NSScrollView *tableScrollView;
@property NSTableView *analyzeTableView;
@property NSLayoutConstraint *analyzeTableHeightConstraint;
@property NSSearchField *tableSearchField;
@property NSLayoutConstraint *tableSearchWidthConstraint;
@property NSPopUpButton *tableStatusFilter;
@property NSLayoutConstraint *tableStatusWidthConstraint;
@property NSArray<NSDictionary<NSString *, id> *> *analyzeRows;
@property NSArray<NSDictionary<NSString *, id> *> *allTableRows;
@property NSTextField *statusField;
@property NSTextField *pathField;
@property NSTextField *commandField;
@property NSTextField *summaryField;
@property NSTextField *outputTitleField;
@property NSTextField *appNameField;
@property NSButton *outputCopyButton;
@property NSButton *openDetailButton;
@property NSButton *detailPathButton;
@property NSButton *openLogButton;
@property NSButton *previewUninstallButton;
@property NSButton *runUninstallButton;
@property NSButton *analyzeParentButton;
@property NSButton *analyzeFinderButton;
@property NSButton *analyzeTrashButton;
@property NSLayoutConstraint *openDetailWidthConstraint;
@property NSLayoutConstraint *detailPathWidthConstraint;
@property NSLayoutConstraint *openLogWidthConstraint;
@property NSLayoutConstraint *analyzeParentWidthConstraint;
@property NSLayoutConstraint *analyzeFinderWidthConstraint;
@property NSLayoutConstraint *analyzeTrashWidthConstraint;
@property NSLayoutConstraint *appNameWidthConstraint;
@property NSLayoutConstraint *previewUninstallWidthConstraint;
@property NSLayoutConstraint *runUninstallWidthConstraint;
@property NSString *molePath;
@property NSString *lastDetailFilePath;
@property NSString *lastLogFilePath;
@property NSString *currentAnalyzePath;
@property NSDate *lastCleanPreviewAt;
@property NSDate *lastUninstallPreviewAt;
@property NSString *lastUninstallPreviewName;
@property NSDate *lastOptimizePreviewAt;
@property BOOL isRunning;
@end

@implementation SweepDockAppDelegate

- (NSView *)cardViewWithRadius:(CGFloat)radius {
    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.wantsLayer = YES;
    view.layer.backgroundColor = SweepDockCardColor().CGColor;
    view.layer.cornerRadius = radius;
    view.layer.borderWidth = 1;
    view.layer.borderColor = [NSColor colorWithCalibratedWhite:0.84 alpha:0.75].CGColor;
    return view;
}

- (void)styleButton:(NSButton *)button prominent:(BOOL)prominent danger:(BOOL)danger {
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.font = [NSFont systemFontOfSize:13 weight:prominent ? NSFontWeightSemibold : NSFontWeightMedium];
    button.alignment = NSTextAlignmentCenter;
    button.lineBreakMode = NSLineBreakByTruncatingTail;
    button.wantsLayer = YES;
    button.layer.cornerRadius = prominent ? 7 : 6;
    button.layer.masksToBounds = YES;
    if (prominent) {
        if (danger) {
            button.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.985 green:0.972 blue:0.948 alpha:1.0].CGColor;
            button.layer.borderWidth = 1;
            button.layer.borderColor = [NSColor colorWithCalibratedRed:0.78 green:0.66 blue:0.48 alpha:0.85].CGColor;
            button.contentTintColor = SweepDockDangerColor();
        } else {
            button.layer.backgroundColor = SweepDockAccentColor().CGColor;
            button.layer.borderWidth = 1;
            button.layer.borderColor = [NSColor colorWithCalibratedWhite:0.10 alpha:0.95].CGColor;
            button.contentTintColor = [NSColor whiteColor];
        }
    } else {
        button.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.56].CGColor;
        button.layer.borderWidth = 1;
        button.layer.borderColor = [NSColor colorWithCalibratedWhite:0.76 alpha:0.70].CGColor;
        button.contentTintColor = SweepDockTextColor();
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
    [self refreshMole:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 1220, 760);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:(NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable |
                                                        NSWindowStyleMaskResizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"SweepDock";
    self.window.minSize = NSMakeSize(1140, 680);
    if (@available(macOS 10.14, *)) {
        self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
    [self.window center];

    NSView *root = self.window.contentView;
    root.wantsLayer = YES;
    root.layer.backgroundColor = SweepDockPanelColor().CGColor;

    NSView *sidebar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 720)];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.wantsLayer = YES;
    sidebar.layer.backgroundColor = SweepDockSidebarColor().CGColor;
    [root addSubview:sidebar];

    NSView *main = [[NSView alloc] initWithFrame:NSZeroRect];
    main.translatesAutoresizingMaskIntoConstraints = NO;
    main.wantsLayer = YES;
    main.layer.backgroundColor = SweepDockPanelColor().CGColor;
    [root addSubview:main];

    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:284],
        [main.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [main.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [main.topAnchor constraintEqualToAnchor:root.topAnchor],
        [main.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];

    NSTextField *title = [self label:@"SweepDock" font:[NSFont systemFontOfSize:30 weight:NSFontWeightBold] color:SweepDockTextColor()];
    [sidebar addSubview:title];

    NSTextField *subtitle = [self label:@"Mole CLI 桌面控制台"
                                   font:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
                                  color:SweepDockSecondaryTextColor()];
    [sidebar addSubview:subtitle];

    NSView *statusCard = [self cardViewWithRadius:8];
    statusCard.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.965 green:0.966 blue:0.962 alpha:1.0].CGColor;
    statusCard.layer.borderColor = [NSColor colorWithCalibratedWhite:0.76 alpha:0.70].CGColor;
    [sidebar addSubview:statusCard];

    self.statusField = [self label:@"正在检测 Mole CLI..." font:[NSFont boldSystemFontOfSize:14] color:SweepDockTextColor()];
    [statusCard addSubview:self.statusField];

    self.pathField = [self label:@"" font:[NSFont systemFontOfSize:11] color:SweepDockSecondaryTextColor()];
    self.pathField.lineBreakMode = NSLineBreakByWordWrapping;
    [statusCard addSubview:self.pathField];

    NSArray *buttons = @[
        @[@"系统状态", @"status", @NO],
        @[@"磁盘分析", @"analyze --json", @NO],
        @[@"清理预览", @"clean --dry-run", @NO],
        @[@"执行清理", @"clean", @YES],
        @[@"清理历史", @"history --json", @NO],
        @[@"应用卸载", @"uninstall --list", @NO],
        @[@"项目清理", @"purge --dry-run", @NO],
        @[@"优化预览", @"optimize --dry-run", @NO],
        @[@"执行优化", @"optimize", @YES],
        @[@"Mole 帮助", @"--help", @NO],
    ];

    NSMutableArray<NSButton *> *actionButtons = [NSMutableArray array];
    for (NSArray *item in buttons) {
        NSButton *button = [NSButton buttonWithTitle:item[0]
                                              target:self
                                              action:@selector(actionButtonClicked:)];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [self styleButton:button prominent:YES danger:[item[2] boolValue]];
        button.identifier = item[1];
        button.tag = [item[2] boolValue] ? 1 : 0;
        [sidebar addSubview:button];
        [actionButtons addObject:button];
    }

    NSButton *refresh = [NSButton buttonWithTitle:@"刷新检测" target:self action:@selector(refreshMole:)];
    refresh.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:refresh prominent:NO danger:NO];
    [sidebar addSubview:refresh];

    NSView *workspace = [self cardViewWithRadius:8];
    [main addSubview:workspace];

    self.outputTitleField = [self label:@"欢迎使用" font:[NSFont systemFontOfSize:24 weight:NSFontWeightBold] color:SweepDockTextColor()];
    [workspace addSubview:self.outputTitleField];

    self.commandField = [self label:@"还没有运行任何命令。" font:[NSFont systemFontOfSize:12] color:SweepDockSecondaryTextColor()];
    [workspace addSubview:self.commandField];

    self.summaryField = [self label:@"" font:[NSFont systemFontOfSize:12] color:SweepDockSecondaryTextColor()];
    [workspace addSubview:self.summaryField];

    self.outputCopyButton = [NSButton buttonWithTitle:@"复制输出" target:self action:@selector(copyCurrentOutput:)];
    self.outputCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.outputCopyButton prominent:NO danger:NO];
    [workspace addSubview:self.outputCopyButton];

    self.tableSearchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    self.tableSearchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableSearchField.placeholderString = @"筛选表格";
    self.tableSearchField.target = self;
    self.tableSearchField.action = @selector(filterTableRows:);
    self.tableSearchField.hidden = YES;
    [workspace addSubview:self.tableSearchField];

    self.tableStatusFilter = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.tableStatusFilter.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableStatusFilter addItemsWithTitles:@[@"全部"]];
    self.tableStatusFilter.target = self;
    self.tableStatusFilter.action = @selector(filterTableRows:);
    self.tableStatusFilter.hidden = YES;
    [workspace addSubview:self.tableStatusFilter];

    self.openDetailButton = [NSButton buttonWithTitle:@"打开清单" target:self action:@selector(openDetailFile:)];
    self.openDetailButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.openDetailButton prominent:NO danger:NO];
    self.openDetailButton.enabled = NO;
    self.openDetailButton.hidden = YES;
    [workspace addSubview:self.openDetailButton];

    self.detailPathButton = [NSButton buttonWithTitle:@"复制路径" target:self action:@selector(copyDetailPath:)];
    self.detailPathButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.detailPathButton prominent:NO danger:NO];
    self.detailPathButton.enabled = NO;
    self.detailPathButton.hidden = YES;
    [workspace addSubview:self.detailPathButton];

    self.openLogButton = [NSButton buttonWithTitle:@"打开日志" target:self action:@selector(openLogFile:)];
    self.openLogButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.openLogButton prominent:NO danger:NO];
    self.openLogButton.enabled = NO;
    self.openLogButton.hidden = YES;
    [workspace addSubview:self.openLogButton];

    self.appNameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.appNameField.translatesAutoresizingMaskIntoConstraints = NO;
    self.appNameField.placeholderString = @"输入应用名";
    self.appNameField.hidden = YES;
    [workspace addSubview:self.appNameField];

    self.previewUninstallButton = [NSButton buttonWithTitle:@"卸载预览" target:self action:@selector(previewUninstall:)];
    self.previewUninstallButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.previewUninstallButton prominent:NO danger:NO];
    self.previewUninstallButton.hidden = YES;
    [workspace addSubview:self.previewUninstallButton];

    self.runUninstallButton = [NSButton buttonWithTitle:@"执行卸载" target:self action:@selector(runUninstall:)];
    self.runUninstallButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.runUninstallButton prominent:NO danger:YES];
    self.runUninstallButton.hidden = YES;
    [workspace addSubview:self.runUninstallButton];

    self.analyzeParentButton = [NSButton buttonWithTitle:@"上级" target:self action:@selector(openAnalyzeParent:)];
    self.analyzeParentButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.analyzeParentButton prominent:NO danger:NO];
    self.analyzeParentButton.hidden = YES;
    [workspace addSubview:self.analyzeParentButton];

    self.analyzeFinderButton = [NSButton buttonWithTitle:@"Finder" target:self action:@selector(openAnalyzeInFinder:)];
    self.analyzeFinderButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.analyzeFinderButton prominent:NO danger:NO];
    self.analyzeFinderButton.hidden = YES;
    [workspace addSubview:self.analyzeFinderButton];

    self.analyzeTrashButton = [NSButton buttonWithTitle:@"移到废纸篓" target:self action:@selector(trashSelectedAnalyzeItem:)];
    self.analyzeTrashButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self styleButton:self.analyzeTrashButton prominent:NO danger:YES];
    self.analyzeTrashButton.hidden = YES;
    [workspace addSubview:self.analyzeTrashButton];

    self.openDetailWidthConstraint = [self.openDetailButton.widthAnchor constraintEqualToConstant:0];
    self.detailPathWidthConstraint = [self.detailPathButton.widthAnchor constraintEqualToConstant:0];
    self.openLogWidthConstraint = [self.openLogButton.widthAnchor constraintEqualToConstant:0];
    self.analyzeParentWidthConstraint = [self.analyzeParentButton.widthAnchor constraintEqualToConstant:0];
    self.analyzeFinderWidthConstraint = [self.analyzeFinderButton.widthAnchor constraintEqualToConstant:0];
    self.analyzeTrashWidthConstraint = [self.analyzeTrashButton.widthAnchor constraintEqualToConstant:0];
    self.appNameWidthConstraint = [self.appNameField.widthAnchor constraintEqualToConstant:0];
    self.previewUninstallWidthConstraint = [self.previewUninstallButton.widthAnchor constraintEqualToConstant:0];
    self.runUninstallWidthConstraint = [self.runUninstallButton.widthAnchor constraintEqualToConstant:0];
    self.tableSearchWidthConstraint = [self.tableSearchField.widthAnchor constraintEqualToConstant:0];
    self.tableStatusWidthConstraint = [self.tableStatusFilter.widthAnchor constraintEqualToConstant:0];

    self.tableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.tableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableScrollView.hasVerticalScroller = YES;
    self.tableScrollView.borderType = NSNoBorder;
    self.tableScrollView.wantsLayer = YES;
    self.tableScrollView.layer.cornerRadius = 8;
    self.tableScrollView.layer.borderWidth = 1;
    self.tableScrollView.layer.borderColor = [NSColor colorWithCalibratedWhite:0.84 alpha:0.85].CGColor;
    self.tableScrollView.hidden = YES;
    [workspace addSubview:self.tableScrollView];

    self.analyzeTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.analyzeTableView.delegate = self;
    self.analyzeTableView.dataSource = self;
    self.analyzeTableView.usesAlternatingRowBackgroundColors = YES;
    self.analyzeTableView.rowHeight = 30;
    self.analyzeTableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    self.analyzeTableView.gridColor = [NSColor colorWithCalibratedWhite:0.88 alpha:0.8];
    self.analyzeTableView.doubleAction = @selector(tableRowDoubleClicked:);
    self.analyzeTableView.target = self;

    NSArray *columns = @[
        @[@"size", @"大小", @90],
        @[@"name", @"项目", @220],
        @[@"tag", @"状态", @90],
        @[@"path", @"位置或备注", @420],
    ];
    for (NSArray *columnInfo in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:columnInfo[0]];
        column.title = columnInfo[1];
        column.width = [columnInfo[2] doubleValue];
        [self.analyzeTableView addTableColumn:column];
    }
    self.tableScrollView.documentView = self.analyzeTableView;
    self.analyzeTableHeightConstraint = [self.tableScrollView.heightAnchor constraintEqualToConstant:0];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.wantsLayer = YES;
    scrollView.layer.cornerRadius = 8;
    scrollView.layer.borderWidth = 1;
    scrollView.layer.borderColor = [NSColor colorWithCalibratedWhite:0.84 alpha:0.85].CGColor;
    [workspace addSubview:scrollView];

    self.outputView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.outputView.editable = NO;
    self.outputView.selectable = YES;
    self.outputView.font = [NSFont monospacedSystemFontOfSize:12.5 weight:NSFontWeightRegular];
    self.outputView.textColor = SweepDockTextColor();
    self.outputView.backgroundColor = [NSColor colorWithCalibratedRed:0.985 green:0.99 blue:0.995 alpha:1.0];
    self.outputView.insertionPointColor = SweepDockTextColor();
    self.outputView.textContainerInset = NSMakeSize(16, 14);
    scrollView.drawsBackground = YES;
    scrollView.backgroundColor = self.outputView.backgroundColor;
    self.outputView.string = @"欢迎使用 SweepDock。\n\n请从左侧选择一个操作。建议先运行“清理预览”，确认将要处理的内容后再执行真实清理。";
    scrollView.documentView = self.outputView;

    title.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.outputTitleField.translatesAutoresizingMaskIntoConstraints = NO;
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryField.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:22],
        [title.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:24],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [statusCard.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:20],
        [statusCard.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-20],
        [statusCard.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:18],
        [statusCard.heightAnchor constraintEqualToConstant:82],
        [self.statusField.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:14],
        [self.statusField.topAnchor constraintEqualToAnchor:statusCard.topAnchor constant:12],
        [self.pathField.leadingAnchor constraintEqualToAnchor:self.statusField.leadingAnchor],
        [self.pathField.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-14],
        [self.pathField.topAnchor constraintEqualToAnchor:self.statusField.bottomAnchor constant:6],
        [refresh.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:20],
        [refresh.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-20],
        [refresh.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-20],
        [refresh.heightAnchor constraintEqualToConstant:34],
        [workspace.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:24],
        [workspace.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-24],
        [workspace.topAnchor constraintEqualToAnchor:main.topAnchor constant:24],
        [workspace.bottomAnchor constraintEqualToAnchor:main.bottomAnchor constant:-24],
        [self.outputTitleField.leadingAnchor constraintEqualToAnchor:workspace.leadingAnchor constant:24],
        [self.outputTitleField.trailingAnchor constraintLessThanOrEqualToAnchor:self.tableStatusFilter.leadingAnchor constant:-12],
        [self.outputTitleField.topAnchor constraintEqualToAnchor:workspace.topAnchor constant:22],
        [self.commandField.leadingAnchor constraintEqualToAnchor:self.outputTitleField.leadingAnchor],
        [self.commandField.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor constant:-24],
        [self.commandField.topAnchor constraintEqualToAnchor:self.outputTitleField.bottomAnchor constant:6],
        [self.summaryField.leadingAnchor constraintEqualToAnchor:self.outputTitleField.leadingAnchor],
        [self.summaryField.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor constant:-24],
        [self.summaryField.topAnchor constraintEqualToAnchor:self.commandField.bottomAnchor constant:4],
        [self.openLogButton.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor constant:-24],
        [self.openLogButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.openLogWidthConstraint,
        [self.analyzeTrashButton.trailingAnchor constraintEqualToAnchor:self.openLogButton.leadingAnchor constant:-8],
        [self.analyzeTrashButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.analyzeTrashWidthConstraint,
        [self.analyzeFinderButton.trailingAnchor constraintEqualToAnchor:self.analyzeTrashButton.leadingAnchor constant:-8],
        [self.analyzeFinderButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.analyzeFinderWidthConstraint,
        [self.analyzeParentButton.trailingAnchor constraintEqualToAnchor:self.analyzeFinderButton.leadingAnchor constant:-8],
        [self.analyzeParentButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.analyzeParentWidthConstraint,
        [self.runUninstallButton.trailingAnchor constraintEqualToAnchor:self.analyzeParentButton.leadingAnchor constant:-8],
        [self.runUninstallButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.runUninstallWidthConstraint,
        [self.previewUninstallButton.trailingAnchor constraintEqualToAnchor:self.runUninstallButton.leadingAnchor constant:-8],
        [self.previewUninstallButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        [self.appNameField.trailingAnchor constraintEqualToAnchor:self.previewUninstallButton.leadingAnchor constant:-8],
        [self.appNameField.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.appNameWidthConstraint,
        self.previewUninstallWidthConstraint,
        [self.detailPathButton.trailingAnchor constraintEqualToAnchor:self.appNameField.leadingAnchor constant:-8],
        [self.detailPathButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.detailPathWidthConstraint,
        [self.openDetailButton.trailingAnchor constraintEqualToAnchor:self.detailPathButton.leadingAnchor constant:-8],
        [self.openDetailButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.openDetailWidthConstraint,
        [self.outputCopyButton.trailingAnchor constraintEqualToAnchor:self.openDetailButton.leadingAnchor constant:-8],
        [self.outputCopyButton.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        [self.tableSearchField.trailingAnchor constraintEqualToAnchor:self.outputCopyButton.leadingAnchor constant:-8],
        [self.tableSearchField.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.tableSearchWidthConstraint,
        [self.tableStatusFilter.trailingAnchor constraintEqualToAnchor:self.tableSearchField.leadingAnchor constant:-8],
        [self.tableStatusFilter.centerYAnchor constraintEqualToAnchor:self.outputTitleField.centerYAnchor],
        self.tableStatusWidthConstraint,
        [self.tableScrollView.leadingAnchor constraintEqualToAnchor:workspace.leadingAnchor constant:24],
        [self.tableScrollView.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor constant:-24],
        [self.tableScrollView.topAnchor constraintEqualToAnchor:self.summaryField.bottomAnchor constant:14],
        self.analyzeTableHeightConstraint,
        [scrollView.leadingAnchor constraintEqualToAnchor:workspace.leadingAnchor constant:24],
        [scrollView.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor constant:-24],
        [scrollView.topAnchor constraintEqualToAnchor:self.tableScrollView.bottomAnchor constant:16],
        [scrollView.bottomAnchor constraintEqualToAnchor:workspace.bottomAnchor constant:-24],
    ]];

    NSView *previous = statusCard;
    for (NSButton *button in actionButtons) {
        [NSLayoutConstraint activateConstraints:@[
            [button.centerXAnchor constraintEqualToAnchor:sidebar.centerXAnchor],
            [button.widthAnchor constraintEqualToConstant:232],
            [button.topAnchor constraintEqualToAnchor:previous.bottomAnchor constant:9],
            [button.heightAnchor constraintEqualToConstant:34],
        ]];
        previous = button;
    }

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    return label;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.analyzeRows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.analyzeRows.count) {
        return @"";
    }
    return self.analyzeRows[row][tableColumn.identifier] ?: @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.analyzeTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.analyzeRows.count) {
        return;
    }
    NSString *uninstallName = self.analyzeRows[row][@"uninstall_name"];
    if (uninstallName.length > 0 && !self.appNameField.hidden) {
        self.appNameField.stringValue = uninstallName;
        self.lastUninstallPreviewAt = nil;
        self.lastUninstallPreviewName = nil;
    }
}

- (void)setAnalyzeRowsVisible:(BOOL)visible rows:(NSArray<NSDictionary<NSString *, id> *> *)rows {
    self.allTableRows = rows ?: @[];
    self.analyzeRows = self.allTableRows;
    self.tableSearchField.hidden = !visible;
    self.tableStatusFilter.hidden = !visible;
    self.tableScrollView.hidden = !visible;
    self.tableSearchWidthConstraint.constant = visible ? 160 : 0;
    self.tableStatusWidthConstraint.constant = visible ? 110 : 0;
    if (!visible) {
        self.tableSearchField.stringValue = @"";
        [self.tableStatusFilter removeAllItems];
        [self.tableStatusFilter addItemWithTitle:@"全部"];
    } else {
        NSMutableOrderedSet<NSString *> *tags = [NSMutableOrderedSet orderedSetWithObject:@"全部"];
        for (NSDictionary<NSString *, id> *row in self.allTableRows) {
            NSString *tag = SweepDockStringValue(row[@"tag"]);
            if (tag.length > 0) {
                [tags addObject:tag];
            }
        }
        [self.tableStatusFilter removeAllItems];
        [self.tableStatusFilter addItemsWithTitles:tags.array];
    }
    self.analyzeTableHeightConstraint.constant = visible ? 230 : 0;
    [self.analyzeTableView reloadData];
}

- (void)filterTableRows:(id)sender {
    self.analyzeRows = SweepDockFilterRows(self.allTableRows, self.tableSearchField.stringValue, self.tableStatusFilter.titleOfSelectedItem);
    [self.analyzeTableView reloadData];
    if (self.allTableRows.count > 0) {
        self.summaryField.stringValue = [NSString stringWithFormat:@"表格 %lu / %lu 行", (unsigned long)self.analyzeRows.count, (unsigned long)self.allTableRows.count];
    }
}

- (void)refreshMole:(id)sender {
    self.molePath = [self findMole];
    if (self.molePath.length > 0) {
        self.statusField.stringValue = @"Mole CLI 已就绪";
        self.pathField.stringValue = self.molePath;
    } else {
        self.statusField.stringValue = @"未检测到 Mole CLI";
        self.pathField.stringValue = @"请先安装：brew install mole";
        self.outputView.string = @"未检测到 Mole CLI。\n\n请先用 Homebrew 安装：\n  brew install mole";
    }
}

- (NSString *)findMole {
    return SweepDockFindMole();
}

- (void)setDetailFilePath:(NSString *)path {
    self.lastDetailFilePath = path;
    BOOL enabled = path.length > 0;
    self.openDetailButton.enabled = enabled;
    self.detailPathButton.enabled = enabled;
    self.openDetailButton.hidden = !enabled;
    self.detailPathButton.hidden = !enabled;
    self.openDetailWidthConstraint.constant = enabled ? 76 : 0;
    self.detailPathWidthConstraint.constant = enabled ? 76 : 0;
}

- (void)setLogFilePath:(NSString *)path {
    self.lastLogFilePath = path;
    BOOL enabled = path.length > 0;
    self.openLogButton.enabled = enabled;
    self.openLogButton.hidden = !enabled;
    self.openLogWidthConstraint.constant = enabled ? 76 : 0;
}

- (void)setAnalyzeControlsVisible:(BOOL)visible {
    self.analyzeParentButton.hidden = !visible;
    self.analyzeFinderButton.hidden = !visible;
    self.analyzeTrashButton.hidden = !visible;
    self.analyzeParentWidthConstraint.constant = visible ? 58 : 0;
    self.analyzeFinderWidthConstraint.constant = visible ? 70 : 0;
    self.analyzeTrashWidthConstraint.constant = visible ? 92 : 0;
}

- (NSDictionary<NSString *, id> *)selectedAnalyzeRow {
    NSInteger row = self.analyzeTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.analyzeRows.count) {
        return nil;
    }
    return self.analyzeRows[row];
}

- (void)showDirectoryAnalysisAtPath:(NSString *)path {
    BOOL isDirectory = NO;
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return;
    }
    self.currentAnalyzePath = path;
    NSArray *rows = SweepDockDirectoryRows(path);
    [self setUninstallControlsVisible:NO];
    [self setAnalyzeControlsVisible:YES];
    [self setAnalyzeRowsVisible:YES rows:rows];
    self.outputTitleField.stringValue = @"目录分析";
    self.commandField.stringValue = [NSString stringWithFormat:@"本地目录：%@", path];
    self.summaryField.stringValue = [NSString stringWithFormat:@"%@ · 表格 %lu 行", path, (unsigned long)rows.count];
    self.outputView.string = SweepDockFormatDirectoryRows(path, rows);
}

- (void)tableRowDoubleClicked:(id)sender {
    NSDictionary<NSString *, id> *row = [self selectedAnalyzeRow];
    NSString *path = SweepDockStringValue(row[@"path"]);
    if (path.length == 0) {
        return;
    }
    BOOL isDirectory = [row[@"is_dir"] boolValue];
    if (!isDirectory) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
        return;
    }
    [self showDirectoryAnalysisAtPath:path];
}

- (void)openAnalyzeParent:(id)sender {
    NSString *path = self.currentAnalyzePath;
    if (path.length == 0 || [path isEqualToString:@"/"]) {
        return;
    }
    NSString *parent = [path stringByDeletingLastPathComponent];
    if (parent.length == 0) {
        parent = @"/";
    }
    [self showDirectoryAnalysisAtPath:parent];
}

- (void)openAnalyzeInFinder:(id)sender {
    NSDictionary<NSString *, id> *row = [self selectedAnalyzeRow];
    NSString *path = SweepDockStringValue(row[@"path"]);
    if (path.length == 0) {
        path = self.currentAnalyzePath;
    }
    if (path.length == 0) {
        return;
    }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}

- (void)trashSelectedAnalyzeItem:(id)sender {
    NSDictionary<NSString *, id> *row = [self selectedAnalyzeRow];
    NSString *path = SweepDockStringValue(row[@"path"]);
    if (path.length == 0) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"移到废纸篓？";
    alert.informativeText = [NSString stringWithFormat:@"将把下面的项目移到 macOS 废纸篓：\n%@", path];
    [alert addButtonWithTitle:@"移到废纸篓"];
    [alert addButtonWithTitle:@"取消"];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSError *error = nil;
    NSURL *url = [NSURL fileURLWithPath:path];
    BOOL ok = [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:nil error:&error];
    if (!ok) {
        NSAlert *failed = [[NSAlert alloc] init];
        failed.messageText = @"移动失败";
        failed.informativeText = error.localizedDescription ?: @"无法移动到废纸篓。";
        [failed addButtonWithTitle:@"好的"];
        failed.alertStyle = NSAlertStyleWarning;
        [failed runModal];
        return;
    }

    [self showDirectoryAnalysisAtPath:self.currentAnalyzePath ?: [path stringByDeletingLastPathComponent]];
}

- (void)openDetailFile:(id)sender {
    if (self.lastDetailFilePath.length == 0) {
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:self.lastDetailFilePath];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openLogFile:(id)sender {
    if (self.lastLogFilePath.length == 0) {
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:self.lastLogFilePath];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)copyDetailPath:(id)sender {
    if (self.lastDetailFilePath.length == 0) {
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:self.lastDetailFilePath forType:NSPasteboardTypeString];
}

- (void)copyCurrentOutput:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:self.outputView.string ?: @"" forType:NSPasteboardTypeString];
}

- (void)setUninstallControlsVisible:(BOOL)visible {
    self.appNameField.hidden = !visible;
    self.previewUninstallButton.hidden = !visible;
    self.runUninstallButton.hidden = !visible;
    self.appNameWidthConstraint.constant = visible ? 170 : 0;
    self.previewUninstallWidthConstraint.constant = visible ? 84 : 0;
    self.runUninstallWidthConstraint.constant = visible ? 84 : 0;
}

- (void)previewUninstall:(id)sender {
    if (self.isRunning) {
        return;
    }

    NSString *appName = [self.appNameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (appName.length == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"请输入应用名";
        alert.informativeText = @"请使用“应用卸载”列表里显示的名称，例如 Google Chrome 或 Telegram。";
        [alert addButtonWithTitle:@"好的"];
        alert.alertStyle = NSAlertStyleInformational;
        [alert runModal];
        return;
    }
    [self runMoleWithArguments:@[@"uninstall", @"--dry-run", appName] title:@"卸载预览"];
}

- (void)runUninstall:(id)sender {
    if (self.isRunning) {
        return;
    }

    NSString *appName = [self.appNameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (appName.length == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"请输入应用名";
        alert.informativeText = @"请先在“应用卸载”列表中选择应用，或手动输入列表里显示的名称。";
        [alert addButtonWithTitle:@"好的"];
        alert.alertStyle = NSAlertStyleInformational;
        [alert runModal];
        return;
    }

    if (!self.lastUninstallPreviewAt || ![self.lastUninstallPreviewName isEqualToString:appName]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"请先运行同一应用的卸载预览";
        alert.informativeText = @"为了避免误删，SweepDock 要求先对当前应用成功运行“卸载预览”，确认将会移动哪些文件后再执行卸载。";
        [alert addButtonWithTitle:@"好的"];
        alert.alertStyle = NSAlertStyleInformational;
        [alert runModal];
        return;
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *previewTime = [formatter stringFromDate:self.lastUninstallPreviewAt] ?: @"刚刚";

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"确认卸载 %@？", appName];
    alert.informativeText = [NSString stringWithFormat:@"上次卸载预览：%@\n\nMole 默认会把应用和残留文件移动到 macOS 废纸篓，仍建议先确认预览内容。", previewTime];
    [alert addButtonWithTitle:@"执行卸载"];
    [alert addButtonWithTitle:@"取消"];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    [self runMoleWithArguments:@[@"uninstall", appName] title:@"执行卸载"];
}

- (void)actionButtonClicked:(NSButton *)sender {
    if (self.isRunning) {
        return;
    }

    if (!self.molePath) {
        [self refreshMole:nil];
        return;
    }

    NSArray<NSString *> *arguments = [sender.identifier componentsSeparatedByString:@" "];

    if (sender.tag == 1 && arguments.count >= 1 && [arguments[0] isEqualToString:@"clean"]) {
        if (!self.lastCleanPreviewAt) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"请先运行清理预览";
            alert.informativeText = @"为了避免误删，SweepDock 要求先成功运行“清理预览”，确认候选项目后再执行真实清理。";
            [alert addButtonWithTitle:@"好的"];
            alert.alertStyle = NSAlertStyleInformational;
            [alert runModal];
            return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"确认执行真实清理？";
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *previewTime = [formatter stringFromDate:self.lastCleanPreviewAt] ?: @"刚刚";
        alert.informativeText = [NSString stringWithFormat:@"上次清理预览：%@\n\n真实清理可能会永久删除缓存、日志和生成文件。", previewTime];
        [alert addButtonWithTitle:@"执行 mo clean"];
        [alert addButtonWithTitle:@"取消"];
        alert.alertStyle = NSAlertStyleWarning;
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }

    if (sender.tag == 1 && arguments.count >= 1 && [arguments[0] isEqualToString:@"optimize"]) {
        if (!self.lastOptimizePreviewAt) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"请先运行优化预览";
            alert.informativeText = @"为了避免误操作，SweepDock 要求先成功运行“优化预览”，确认将要执行的维护项目后再执行真实优化。";
            [alert addButtonWithTitle:@"好的"];
            alert.alertStyle = NSAlertStyleInformational;
            [alert runModal];
            return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"确认执行系统优化？";
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *previewTime = [formatter stringFromDate:self.lastOptimizePreviewAt] ?: @"刚刚";
        alert.informativeText = [NSString stringWithFormat:@"上次优化预览：%@\n\n真实优化会刷新系统缓存和服务，并修复 Mole 判断为安全的维护项。", previewTime];
        [alert addButtonWithTitle:@"执行 mo optimize"];
        [alert addButtonWithTitle:@"取消"];
        alert.alertStyle = NSAlertStyleWarning;
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }

    [self runMoleWithArguments:arguments title:sender.title];
}

- (NSString *)displayTitleForArguments:(NSArray<NSString *> *)arguments fallback:(NSString *)fallback {
    if (arguments.count >= 1 && [arguments[0] isEqualToString:@"status"]) {
        return @"系统状态";
    }
    if (arguments.count >= 2 && [arguments[0] isEqualToString:@"analyze"]) {
        return @"磁盘分析";
    }
    if (arguments.count >= 2 && [arguments[0] isEqualToString:@"clean"] && [arguments[1] isEqualToString:@"--dry-run"]) {
        return @"清理预览";
    }
    if (arguments.count >= 1 && [arguments[0] isEqualToString:@"clean"]) {
        return @"执行清理";
    }
    if (arguments.count >= 2 && [arguments[0] isEqualToString:@"history"]) {
        return @"清理历史";
    }
    if (arguments.count >= 2 && [arguments[0] isEqualToString:@"uninstall"] && [arguments[1] isEqualToString:@"--list"]) {
        return @"应用卸载";
    }
    if (arguments.count >= 2 && [arguments[0] isEqualToString:@"uninstall"] && [arguments[1] isEqualToString:@"--dry-run"]) {
        return @"卸载预览";
    }
    if (arguments.count >= 1 && [arguments[0] isEqualToString:@"uninstall"]) {
        return @"执行卸载";
    }
    if (arguments.count >= 2 && [arguments[0] isEqualToString:@"purge"] && [arguments[1] isEqualToString:@"--dry-run"]) {
        return @"项目清理";
    }
    if (arguments.count >= 2 && [arguments[0] isEqualToString:@"optimize"] && [arguments[1] isEqualToString:@"--dry-run"]) {
        return @"优化预览";
    }
    if (arguments.count >= 1 && [arguments[0] isEqualToString:@"optimize"]) {
        return @"执行优化";
    }
    if (arguments.count >= 1 && [arguments[0] isEqualToString:@"--help"]) {
        return @"Mole 帮助";
    }
    return fallback ?: @"命令输出";
}

- (void)runMoleWithArguments:(NSArray<NSString *> *)arguments title:(NSString *)title {
    self.isRunning = YES;
    NSString *command = [NSString stringWithFormat:@"%@ %@", self.molePath, [arguments componentsJoinedByString:@" "]];
    NSString *displayTitle = [self displayTitleForArguments:arguments fallback:title];
    self.outputTitleField.stringValue = displayTitle;
    [self setDetailFilePath:nil];
    [self setLogFilePath:nil];
    [self setAnalyzeControlsVisible:NO];
    [self setUninstallControlsVisible:(arguments.count >= 1 && [arguments[0] isEqualToString:@"uninstall"])];
    [self setAnalyzeRowsVisible:NO rows:@[]];
    self.commandField.stringValue = [NSString stringWithFormat:@"正在运行：%@", command];
    self.summaryField.stringValue = @"";
    self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n正在运行...", command];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL uninstallCommand = (arguments.count >= 1 && [arguments[0] isEqualToString:@"uninstall"] &&
            !(arguments.count >= 2 && [arguments[1] isEqualToString:@"--list"]));
        BOOL optimizeRunCommand = (arguments.count >= 1 && [arguments[0] isEqualToString:@"optimize"] &&
            !(arguments.count >= 2 && [arguments[1] isEqualToString:@"--dry-run"]));
        NSDictionary<NSString *, id> *result = SweepDockRunCommandWithInput(self.molePath, arguments, (uninstallCommand || optimizeRunCommand) ? @"y\n" : nil);
        int status = [result[@"status"] intValue];
        NSString *output = result[@"output"];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.isRunning = NO;
            self.commandField.stringValue = [NSString stringWithFormat:@"%@ 已结束，退出码 %d", command, status];
            if (status != 0 && [output containsString:@"operation not permitted"]) {
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n权限受限，命令没有成功完成。\n\n如果你是在受限环境里运行，请从 Finder 正常双击打开 SweepDock.app；如果仍然失败，请到“系统设置 > 隐私与安全性”里给 SweepDock 需要的权限。\n\n原始输出：\n%@", command, output];
            } else if (status == 0 && arguments.count >= 1 && [arguments[0] isEqualToString:@"status"]) {
                self.summaryField.stringValue = SweepDockStatusSummary(output);
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatStatusJSON(output)];
            } else if (status == 0 && arguments.count >= 2 && [arguments[0] isEqualToString:@"analyze"] && [arguments[1] isEqualToString:@"--json"]) {
                NSArray *rows = SweepDockAnalyzeEntries(output);
                self.currentAnalyzePath = @"/";
                [self setAnalyzeControlsVisible:YES];
                [self setAnalyzeRowsVisible:YES rows:rows];
                self.summaryField.stringValue = [NSString stringWithFormat:@"%@ · 表格 %lu 行", SweepDockAnalyzeSummary(output), (unsigned long)rows.count];
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatAnalyzeJSON(output)];
            } else if (status == 0 && arguments.count >= 2 && [arguments[0] isEqualToString:@"clean"] && [arguments[1] isEqualToString:@"--dry-run"]) {
                self.lastCleanPreviewAt = [NSDate date];
                [self setDetailFilePath:SweepDockFirstMatch(output, @"Detailed file list: ([^\\n]+)")];
                NSArray *rows = SweepDockCleanPreviewRows(output);
                [self setAnalyzeRowsVisible:YES rows:rows];
                self.summaryField.stringValue = SweepDockCleanSummary(output, rows);
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatCleanDryRun(output)];
            } else if (status == 0 && arguments.count >= 2 && [arguments[0] isEqualToString:@"history"] && [arguments[1] isEqualToString:@"--json"]) {
                [self setLogFilePath:SweepDockFirstMatch(output, @"\"operations\"\\s*:\\s*\"([^\"]+)\"")];
                self.summaryField.stringValue = SweepDockHistorySummary(output);
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatHistoryJSON(output)];
            } else if (status == 0 && arguments.count >= 2 && [arguments[0] isEqualToString:@"uninstall"] && [arguments[1] isEqualToString:@"--list"]) {
                NSArray *rows = SweepDockUninstallListRows(output);
                [self setAnalyzeRowsVisible:YES rows:rows];
                self.summaryField.stringValue = SweepDockUninstallListSummary(output, rows.count);
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatUninstallListJSON(output)];
            } else if (status == 0 && arguments.count >= 2 && [arguments[0] isEqualToString:@"uninstall"] && [arguments[1] isEqualToString:@"--dry-run"]) {
                self.lastUninstallPreviewAt = [NSDate date];
                self.lastUninstallPreviewName = arguments.count >= 3 ? arguments[2] : @"";
                self.summaryField.stringValue = @"卸载预览完成，未删除任何文件";
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatUninstallDryRun(output)];
            } else if (status == 0 && arguments.count >= 1 && [arguments[0] isEqualToString:@"uninstall"]) {
                self.lastUninstallPreviewAt = nil;
                self.lastUninstallPreviewName = nil;
                self.summaryField.stringValue = @"卸载命令已完成";
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatUninstallRun(output)];
            } else if ((status == 0 || status == 2) && arguments.count >= 2 && [arguments[0] isEqualToString:@"purge"] && [arguments[1] isEqualToString:@"--dry-run"]) {
                self.summaryField.stringValue = SweepDockPurgeSummary(output);
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatPurgeDryRun(output)];
            } else if (status == 0 && arguments.count >= 2 && [arguments[0] isEqualToString:@"optimize"] && [arguments[1] isEqualToString:@"--dry-run"]) {
                self.lastOptimizePreviewAt = [NSDate date];
                self.summaryField.stringValue = SweepDockOptimizeSummary(output);
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatOptimizeDryRun(output)];
            } else if (status == 0 && arguments.count >= 1 && [arguments[0] isEqualToString:@"optimize"]) {
                self.lastOptimizePreviewAt = nil;
                self.summaryField.stringValue = @"系统优化命令已完成";
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, SweepDockFormatOptimizeRun(output)];
            } else {
                self.outputView.string = [NSString stringWithFormat:@"$ %@\n\n%@", command, output];
            }
        });
    });
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
            return SweepDockSelfTest();
        }

        NSApplication *app = [NSApplication sharedApplication];
        SweepDockAppDelegate *delegate = [[SweepDockAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
