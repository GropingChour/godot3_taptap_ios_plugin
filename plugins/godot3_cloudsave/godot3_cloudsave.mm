
#include "godot3_cloudsave.h"
#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <zlib.h>
#include <dirent.h>
#include <sys/stat.h>
#include <map>
#include <mutex>
#include <vector>

#if VERSION_MAJOR == 4
#import "platform/ios/app_delegate.h"
#define GODOT_BYTE_ARRAY Variant::PACKED_BYTE_ARRAY
#else
#import "platform/iphone/app_delegate.h"
#define GODOT_BYTE_ARRAY Variant::POOL_BYTE_ARRAY
#endif

// MARK: - ZIP Helper (matches GodotZipHelper in godot3_taptap.mm)

static void zip_write_le16(NSMutableData *buf, uint16_t v) {
    uint8_t b[2] = { (uint8_t)(v & 0xFF), (uint8_t)(v >> 8) };
    [buf appendBytes:b length:2];
}
static void zip_write_le32(NSMutableData *buf, uint32_t v) {
    uint8_t b[4] = { (uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF), (uint8_t)((v >> 16) & 0xFF), (uint8_t)(v >> 24) };
    [buf appendBytes:b length:4];
}
static uint16_t zip_read_le16(const uint8_t *p) { return (uint16_t)(p[0] | ((uint16_t)p[1] << 8)); }
static uint32_t zip_read_le32(const uint8_t *p) {
    return (uint32_t)(p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
}
static const uint32_t kCSZipLFHSig  = 0x04034b50U;
static const uint32_t kCSZipCDHSig  = 0x02014b50U;
static const uint32_t kCSZipEOCDSig = 0x06054b50U;

@interface GodotCloudSaveZipHelper : NSObject
+ (NSData *)zipPath:(NSString *)sourcePath;
+ (BOOL)unzipData:(NSData *)zipData toPath:(NSString *)destPath;
@end

@implementation GodotCloudSaveZipHelper

+ (void)addFile:(NSString *)filePath entryName:(NSString *)entryName buf:(NSMutableData *)buf entries:(NSMutableArray *)entries {
    NSData *raw = [NSData dataWithContentsOfFile:filePath];
    if (!raw) return;
    uint32_t crc = (uint32_t)crc32(0, (const Bytef *)raw.bytes, (uInt)raw.length);
    uLongf bound = compressBound((uLong)raw.length) + 32;
    NSMutableData *comp = [NSMutableData dataWithLength:bound];
    z_stream zs; memset(&zs, 0, sizeof(zs));
    deflateInit2(&zs, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
    zs.next_in = (Bytef *)raw.bytes; zs.avail_in = (uInt)raw.length;
    zs.next_out = (Bytef *)comp.mutableBytes; zs.avail_out = (uInt)bound;
    deflate(&zs, Z_FINISH); deflateEnd(&zs);
    uint32_t compSize = (uint32_t)(bound - zs.avail_out);
    [comp setLength:compSize];
    NSData *nameBytes = [entryName dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t offset = (uint32_t)buf.length;
    zip_write_le32(buf, kCSZipLFHSig); zip_write_le16(buf, 20); zip_write_le16(buf, 0);
    zip_write_le16(buf, 8); zip_write_le16(buf, 0); zip_write_le16(buf, 0);
    zip_write_le32(buf, crc); zip_write_le32(buf, compSize); zip_write_le32(buf, (uint32_t)raw.length);
    zip_write_le16(buf, (uint16_t)nameBytes.length); zip_write_le16(buf, 0);
    [buf appendData:nameBytes]; [buf appendData:comp];
    [entries addObject:@{ @"name": entryName, @"offset": @(offset), @"crc": @(crc),
                          @"compSize": @(compSize), @"rawSize": @(raw.length),
                          @"method": @(8), @"isDir": @NO }];
}

+ (void)addDirEntry:(NSString *)entryName buf:(NSMutableData *)buf entries:(NSMutableArray *)entries {
    NSString *n = [entryName hasSuffix:@"/"] ? entryName : [entryName stringByAppendingString:@"/"];
    NSData *nameBytes = [n dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t offset = (uint32_t)buf.length;
    zip_write_le32(buf, kCSZipLFHSig); zip_write_le16(buf, 20); zip_write_le16(buf, 0);
    zip_write_le16(buf, 0); zip_write_le16(buf, 0); zip_write_le16(buf, 0);
    zip_write_le32(buf, 0); zip_write_le32(buf, 0); zip_write_le32(buf, 0);
    zip_write_le16(buf, (uint16_t)nameBytes.length); zip_write_le16(buf, 0);
    [buf appendData:nameBytes];
    [entries addObject:@{ @"name": n, @"offset": @(offset), @"crc": @0,
                          @"compSize": @0, @"rawSize": @0, @"method": @0, @"isDir": @YES }];
}

+ (void)addDirectory:(NSString *)dirPath base:(NSString *)base buf:(NSMutableData *)buf entries:(NSMutableArray *)entries {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:dirPath error:nil];
    for (NSString *item in items) {
        NSString *fullPath  = [dirPath stringByAppendingPathComponent:item];
        NSString *entryName = base.length > 0 ? [base stringByAppendingPathComponent:item] : item;
        BOOL isDir = NO;
        [fm fileExistsAtPath:fullPath isDirectory:&isDir];
        if (isDir) {
            [self addDirEntry:entryName buf:buf entries:entries];
            [self addDirectory:fullPath base:entryName buf:buf entries:entries];
        } else {
            [self addFile:fullPath entryName:entryName buf:buf entries:entries];
        }
    }
}

+ (NSData *)zipPath:(NSString *)sourcePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableData *buf = [NSMutableData data];
    NSMutableArray *entries = [NSMutableArray array];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:sourcePath isDirectory:&isDir]) return nil;
    if (isDir) {
        [self addDirectory:sourcePath base:@"" buf:buf entries:entries];
    } else {
        [self addFile:sourcePath entryName:[sourcePath lastPathComponent] buf:buf entries:entries];
    }
    uint32_t cdOffset = (uint32_t)buf.length;
    for (NSDictionary *e in entries) {
        NSData *nameBytes = [[e[@"name"] description] dataUsingEncoding:NSUTF8StringEncoding];
        zip_write_le32(buf, kCSZipCDHSig); zip_write_le16(buf, 20); zip_write_le16(buf, 20);
        zip_write_le16(buf, 0); zip_write_le16(buf, [e[@"method"] unsignedShortValue]);
        zip_write_le16(buf, 0); zip_write_le16(buf, 0);
        zip_write_le32(buf, [e[@"crc"] unsignedIntValue]);
        zip_write_le32(buf, [e[@"compSize"] unsignedIntValue]);
        zip_write_le32(buf, [e[@"rawSize"] unsignedIntValue]);
        zip_write_le16(buf, (uint16_t)nameBytes.length); zip_write_le16(buf, 0); zip_write_le16(buf, 0);
        zip_write_le16(buf, 0); zip_write_le16(buf, 0); zip_write_le32(buf, 0);
        zip_write_le32(buf, [e[@"offset"] unsignedIntValue]);
        [buf appendData:nameBytes];
    }
    uint32_t cdSize = (uint32_t)buf.length - cdOffset;
    uint16_t count = (uint16_t)entries.count;
    zip_write_le32(buf, kCSZipEOCDSig); zip_write_le16(buf, 0); zip_write_le16(buf, 0);
    zip_write_le16(buf, count); zip_write_le16(buf, count);
    zip_write_le32(buf, cdSize); zip_write_le32(buf, cdOffset); zip_write_le16(buf, 0);
    return [NSData dataWithData:buf];
}

+ (BOOL)unzipData:(NSData *)zipData toPath:(NSString *)destPath {
    if (!zipData || zipData.length < 22) return NO;
    const uint8_t *bytes = (const uint8_t *)zipData.bytes;
    NSUInteger size = zipData.length;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger eocdPos = NSNotFound;
    for (NSInteger i = (NSInteger)size - 22; i >= 0; i--) {
        if (zip_read_le32(bytes + i) == kCSZipEOCDSig) { eocdPos = (NSUInteger)i; break; }
    }
    if (eocdPos == NSNotFound) return NO;
    uint16_t totalEntries = zip_read_le16(bytes + eocdPos + 10);
    uint32_t cdOffset     = zip_read_le32(bytes + eocdPos + 16);
    [fm createDirectoryAtPath:destPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSUInteger pos = cdOffset;
    for (int i = 0; i < totalEntries; i++) {
        if (pos + 46 > size) break;
        if (zip_read_le32(bytes + pos) != kCSZipCDHSig) break;
        uint16_t method   = zip_read_le16(bytes + pos + 10);
        /* crc32 field skipped — not verified on decompress */
        uint32_t compSz   = zip_read_le32(bytes + pos + 20);
        uint32_t rawSz    = zip_read_le32(bytes + pos + 24);
        uint16_t nameLen  = zip_read_le16(bytes + pos + 28);
        uint16_t extraLen = zip_read_le16(bytes + pos + 30);
        uint16_t commLen  = zip_read_le16(bytes + pos + 32);
        uint32_t lfhOffset= zip_read_le32(bytes + pos + 42);
        NSString *entryName = [[NSString alloc] initWithBytes:(bytes + pos + 46)
                                                       length:nameLen encoding:NSUTF8StringEncoding];
        pos += 46 + nameLen + extraLen + commLen;
        if (!entryName) continue;
        NSString *outPath = [destPath stringByAppendingPathComponent:entryName];
        if ([entryName hasSuffix:@"/"]) {
            [fm createDirectoryAtPath:outPath withIntermediateDirectories:YES attributes:nil error:nil];
            continue;
        }
        [[outPath stringByDeletingLastPathComponent] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [fm createDirectoryAtPath:[outPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        // Read local file header
        NSUInteger lfhPos = lfhOffset;
        if (lfhPos + 30 > size) continue;
        uint16_t lfhNameLen  = zip_read_le16(bytes + lfhPos + 26);
        uint16_t lfhExtraLen = zip_read_le16(bytes + lfhPos + 28);
        NSUInteger dataPos = lfhPos + 30 + lfhNameLen + lfhExtraLen;
        if (dataPos + compSz > size) continue;
        NSData *outData = nil;
        if (method == 0) {
            outData = [NSData dataWithBytes:(bytes + dataPos) length:rawSz];
        } else if (method == 8) {
            NSMutableData *decompressed = [NSMutableData dataWithLength:rawSz];
            z_stream zs; memset(&zs, 0, sizeof(zs));
            inflateInit2(&zs, -15);
            zs.next_in = (Bytef *)(bytes + dataPos); zs.avail_in = compSz;
            zs.next_out = (Bytef *)decompressed.mutableBytes; zs.avail_out = rawSz;
            int ret = inflate(&zs, Z_FINISH); inflateEnd(&zs);
            if (ret == Z_STREAM_END) outData = decompressed;
        }
        if (outData) [outData writeToFile:outPath atomically:YES];
    }
    return YES;
}

@end

Godot3CloudSave *Godot3CloudSave::instance = NULL;

// MARK: - Diagnostic helpers

/// Print iCloud account status, ubiquity identity token, and CloudKit container info.
/// Call this at any diagnostic point — it is read-only and has no side effects.
static void _log_icloud_diagnostics(NSString *caller) {
    NSFileManager *fm = [NSFileManager defaultManager];
    id token = [fm ubiquityIdentityToken];

    // Ubiquity token: non-nil means an iCloud account is signed in on this device.
    // The token value changes when the user switches Apple ID.
    NSLog(@"[CloudSave][Diag][%@] ubiquityIdentityToken=%@  (nil=not signed in / iCloud disabled)",
          caller, token ? token : @"<nil>");

    // CKContainer.currentUserAccountStatus gives the actual CloudKit login state.
    CKContainer *container = nil;
    @try {
        container = [CKContainer defaultContainer];
        NSLog(@"[CloudSave][Diag][%@] containerIdentifier=%@", caller, container.containerIdentifier);
    } @catch (NSException *e) {
        NSLog(@"[CloudSave][Diag][%@] CKContainer defaultContainer exception: %@", caller, e.reason);
        return;
    }

    [container accountStatusWithCompletionHandler:^(CKAccountStatus status, NSError *error) {
        NSString *statusStr;
        switch (status) {
            case CKAccountStatusAvailable:        statusStr = @"Available"; break;
            case CKAccountStatusNoAccount:        statusStr = @"NoAccount"; break;
            case CKAccountStatusRestricted:       statusStr = @"Restricted"; break;
            case CKAccountStatusCouldNotDetermine:statusStr = @"CouldNotDetermine"; break;
            default:                              statusStr = [NSString stringWithFormat:@"Unknown(%ld)", (long)status]; break;
        }
        if (error) {
            NSLog(@"[CloudSave][Diag][%@] accountStatus=ERROR code=%ld domain=%@ desc=%@",
                  caller, (long)error.code, error.domain, error.localizedDescription);
        } else {
            NSLog(@"[CloudSave][Diag][%@] accountStatus=%@", caller, statusStr);
        }
    }];

    // Fetch current user record ID — contains a stable per-Apple-ID identifier.
    [container fetchUserRecordIDWithCompletionHandler:^(CKRecordID *userRecordID, NSError *error) {
        if (error) {
            NSLog(@"[CloudSave][Diag][%@] userRecordID=ERROR code=%ld domain=%@ desc=%@",
                  caller, (long)error.code, error.domain, error.localizedDescription);
        } else {
            // recordName is a stable opaque ID per Apple ID — safe to log for cross-device correlation.
            NSLog(@"[CloudSave][Diag][%@] userRecordID=%@ (use this to verify same Apple ID across devices)",
                  caller, userRecordID.recordName);
        }
    }];
}

// MARK: - Recent write cache

static const uint64_t kRecentWriteCacheTTLMS = 30000;
static std::map<std::string, Dictionary> g_recent_write_cache;
static std::map<std::string, uint64_t> g_recent_write_cache_time;
static std::mutex g_recent_write_cache_mutex;

static uint64_t _now_ms() {
    return (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

static std::string _to_key(String p_uuid) {
    return std::string(p_uuid.utf8().get_data());
}

static int _file_size_or_zero(NSString *path) {
    if (!path || path.length == 0) return 0;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *size = attrs[NSFileSize];
    return size ? [size intValue] : 0;
}

static void _apply_metadata_to_archive_dict(NSString *metadata_json, Dictionary &dict) {
    NSString *meta = metadata_json ?: @"{}";
    dict["metadata"] = String([meta UTF8String]);

    NSString *name = @"";
    NSString *summary = @"";
    NSString *extra = @"";
    int64_t playtime = 0;

    NSData *meta_data = [meta dataUsingEncoding:NSUTF8StringEncoding];
    if (meta_data) {
        id parsed = [NSJSONSerialization JSONObjectWithData:meta_data options:0 error:nil];
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            NSDictionary *obj = (NSDictionary *)parsed;
            id n = obj[@"name"];
            id s = obj[@"summary"];
            id e = obj[@"extra"];
            id p = obj[@"playtime"];
            if ([n isKindOfClass:[NSString class]]) name = (NSString *)n;
            if ([s isKindOfClass:[NSString class]]) summary = (NSString *)s;
            if ([e isKindOfClass:[NSString class]]) extra = (NSString *)e;
            if ([p respondsToSelector:@selector(longLongValue)]) playtime = [p longLongValue];
        }
    }

    dict["name"] = String([name UTF8String]);
    dict["summary"] = String([summary UTF8String]);
    dict["extra"] = String([extra UTF8String]);
    dict["playtime"] = playtime;
}

static Dictionary _build_create_request_archive_dict(NSString *uuid, NSString *metadata_json, NSString *upload_file_path, NSString *cover_path) {
    Dictionary dict;
    uint64_t now_ms = _now_ms();

    dict["uuid"] = String([uuid UTF8String]);
    dict["archiveUuid"] = String([uuid UTF8String]);
    dict["fileId"] = String([uuid UTF8String]);
    dict["createdTime"] = now_ms;
    dict["modifiedTime"] = now_ms;
    dict["updatedTime"] = now_ms;
    dict["saveSize"] = _file_size_or_zero(upload_file_path);
    dict["coverSize"] = _file_size_or_zero(cover_path);

    _apply_metadata_to_archive_dict(metadata_json, dict);
    return dict;
}

static Dictionary _build_update_request_archive_dict(Dictionary base_dict, NSString *metadata_json, NSString *upload_file_path_or_nil, NSString *cover_path_or_nil) {
    Dictionary dict = base_dict;
    uint64_t now_ms = _now_ms();

    dict["modifiedTime"] = now_ms;
    dict["updatedTime"] = now_ms;

    _apply_metadata_to_archive_dict(metadata_json, dict);

    if (upload_file_path_or_nil && upload_file_path_or_nil.length > 0) {
        dict["saveSize"] = _file_size_or_zero(upload_file_path_or_nil);
    }
    if (cover_path_or_nil && cover_path_or_nil.length > 0) {
        dict["coverSize"] = _file_size_or_zero(cover_path_or_nil);
    }

    return dict;
}

static void _prune_recent_write_cache_locked() {
    uint64_t now_ms = _now_ms();
    std::vector<std::string> expired;
    for (const auto &it : g_recent_write_cache_time) {
        if (now_ms > it.second && now_ms - it.second > kRecentWriteCacheTTLMS) {
            expired.push_back(it.first);
        }
    }
    for (const auto &key : expired) {
        NSLog(@"[CloudSave][Cache] EXPIRE uuid=%s age_ms=%llu (TTL=%llu)",
              key.c_str(),
              now_ms - g_recent_write_cache_time[key],
              kRecentWriteCacheTTLMS);
        g_recent_write_cache.erase(key);
        g_recent_write_cache_time.erase(key);
    }
}

static void _cache_recent_write(String uuid, Dictionary archive_dict) {
    std::lock_guard<std::mutex> lock(g_recent_write_cache_mutex);
    _prune_recent_write_cache_locked();
    std::string key = _to_key(uuid);
    bool is_update = g_recent_write_cache.find(key) != g_recent_write_cache.end();
    g_recent_write_cache[key] = archive_dict;
    g_recent_write_cache_time[key] = _now_ms();
    NSLog(@"[CloudSave][Cache] %s uuid=%s  cache_size=%zu",
          is_update ? "UPDATE" : "INSERT",
          key.c_str(),
          g_recent_write_cache.size());
}

static bool _get_recent_write(String uuid, Dictionary &out_archive_dict) {
    std::lock_guard<std::mutex> lock(g_recent_write_cache_mutex);
    _prune_recent_write_cache_locked();
    std::string key = _to_key(uuid);
    auto it = g_recent_write_cache.find(key);
    if (it == g_recent_write_cache.end()) {
        NSLog(@"[CloudSave][Cache] MISS uuid=%s", key.c_str());
        return false;
    }
    uint64_t age_ms = _now_ms() - g_recent_write_cache_time[key];
    NSLog(@"[CloudSave][Cache] HIT  uuid=%s  age_ms=%llu", key.c_str(), age_ms);
    out_archive_dict = it->second;
    return true;
}

static Array _get_all_recent_writes() {
    std::lock_guard<std::mutex> lock(g_recent_write_cache_mutex);
    _prune_recent_write_cache_locked();
    Array list;
    for (const auto &it : g_recent_write_cache) {
        list.push_back(it.second);
    }
    NSLog(@"[CloudSave][Cache] get_all_recent_writes: returning %d entries", list.size());
    return list;
}

Godot3CloudSave::Godot3CloudSave() {
    instance = this;
}

Godot3CloudSave::~Godot3CloudSave() {
    instance = NULL;
}

Godot3CloudSave *Godot3CloudSave::get_singleton() {
    return instance;
}

void Godot3CloudSave::_post_event(Variant p_event) {
    pending_events.push_back(p_event);
}

int Godot3CloudSave::get_pending_event_count() {
    return pending_events.size();
}

Variant Godot3CloudSave::pop_pending_event() {
    Variant front = pending_events.front()->get();
    pending_events.pop_front();
    return front;
}

void Godot3CloudSave::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_pending_event_count"), &Godot3CloudSave::get_pending_event_count);
    ClassDB::bind_method(D_METHOD("pop_pending_event"), &Godot3CloudSave::pop_pending_event);
    
    ClassDB::bind_method(D_METHOD("createArchive", "metadataJson", "archiveFilePath", "archiveCoverPath"), &Godot3CloudSave::createArchive);
    ClassDB::bind_method(D_METHOD("getArchiveList"), &Godot3CloudSave::getArchiveList);
    ClassDB::bind_method(D_METHOD("downloadArchiveData", "archiveUuid", "archiveFileId", "localArchivePath"), &Godot3CloudSave::downloadArchiveData);
    ClassDB::bind_method(D_METHOD("updateArchive", "archiveUuid", "metadataJson", "archiveFilePath", "archiveCoverPath"), &Godot3CloudSave::updateArchive);
    ClassDB::bind_method(D_METHOD("deleteArchive", "archiveUuid"), &Godot3CloudSave::deleteArchive);
    ClassDB::bind_method(D_METHOD("getArchiveCover", "archiveUuid", "archiveFileId"), &Godot3CloudSave::getArchiveCover);
    ClassDB::bind_method(D_METHOD("showTip", "text"), &Godot3CloudSave::showTip);
    
    ClassDB::bind_method(D_METHOD("isAvailable"), &Godot3CloudSave::isAvailable);
}

bool Godot3CloudSave::isAvailable() {
    id token = [[NSFileManager defaultManager] ubiquityIdentityToken];
    NSLog(@"[CloudSave] isAvailable: ubiquityIdentityToken=%@", token ? @"present" : @"nil");
    return token != nil;
}

// MARK: - Toast Queue

static NSMutableArray *s_toastQueue = nil;
static BOOL s_isShowingToast = NO;

static void _process_toast_queue() {
    if (s_isShowingToast || s_toastQueue.count == 0) return;

    s_isShowingToast = YES;
    NSString *message = s_toastQueue[0];
    [s_toastQueue removeObjectAtIndex:0];

    // Create Toast View
    UIView *toastView = [[UIView alloc] init];
    toastView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    toastView.layer.cornerRadius = 10.0;
    toastView.clipsToBounds = YES;
    toastView.alpha = 0.0;

    // Create Label
    UILabel *label = [[UILabel alloc] init];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:14.0];
    label.numberOfLines = 0;
    [toastView addSubview:label];

    // Layout
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat maxWidth = screenSize.width * 0.8;
    CGSize textSize = [message boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{ NSFontAttributeName : label.font }
                                            context:nil]
                              .size;

    CGFloat padding = 20.0;
    CGFloat w = textSize.width + padding * 2;
    CGFloat h = textSize.height + padding * 2;
    toastView.frame = CGRectMake((screenSize.width - w) / 2, screenSize.height - 150, w, h);
    label.frame = CGRectMake(padding, padding, textSize.width, textSize.height);

    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    [keyWindow addSubview:toastView];

    // Animate
    [UIView animateWithDuration:0.3 animations:^{
        toastView.alpha = 1.0;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastView.alpha = 0.0;
            } completion:^(BOOL finished) {
                [toastView removeFromSuperview];
                s_isShowingToast = NO;
                _process_toast_queue();
            }];
        });
    }];
}

void Godot3CloudSave::showTip(String p_text) {
	NSString *message = [[NSString alloc] initWithUTF8String:p_text.utf8().get_data()];
	dispatch_async(dispatch_get_main_queue(), ^{
        if (s_toastQueue == nil) {
            s_toastQueue = [[NSMutableArray alloc] init];
        }
        [s_toastQueue addObject:message];
        _process_toast_queue();
	});

}

// Helpers
Dictionary recordToDictionary(CKRecord *record) {
    Dictionary dict;
    NSString *uuid = record.recordID.recordName ?: @"";
    dict["uuid"] = String([uuid UTF8String]);
    dict["archiveUuid"] = String([uuid UTF8String]);

    uint64_t createdTime = record.creationDate ? (uint64_t)([record.creationDate timeIntervalSince1970] * 1000) : 0;
    uint64_t modifiedTime = record.modificationDate ? (uint64_t)([record.modificationDate timeIntervalSince1970] * 1000) : createdTime;
    dict["createdTime"] = createdTime;
    dict["modifiedTime"] = modifiedTime;
    dict["updatedTime"] = modifiedTime;

    NSString *name = @"";
    NSString *summary = @"";
    NSString *extra = @"";
    int64_t playtime = 0;

    NSString *metadataStr = record[@"metadata"];
    if (metadataStr) {
        dict["metadata"] = String([metadataStr UTF8String]);
        NSData *metadataData = [metadataStr dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *metadataObj = nil;
        if (metadataData) {
            id parsed = [NSJSONSerialization JSONObjectWithData:metadataData options:0 error:nil];
            if ([parsed isKindOfClass:[NSDictionary class]]) {
                metadataObj = (NSDictionary *)parsed;
            }
        }
        if (metadataObj) {
            id n = metadataObj[@"name"];
            id s = metadataObj[@"summary"];
            id e = metadataObj[@"extra"];
            id p = metadataObj[@"playtime"];
            if ([n isKindOfClass:[NSString class]]) name = (NSString *)n;
            if ([s isKindOfClass:[NSString class]]) summary = (NSString *)s;
            if ([e isKindOfClass:[NSString class]]) extra = (NSString *)e;
            if ([p respondsToSelector:@selector(longLongValue)]) playtime = [p longLongValue];
        }
    } else {
        dict["metadata"] = "";
    }

    dict["name"] = String([name UTF8String]);
    dict["summary"] = String([summary UTF8String]);
    dict["extra"] = String([extra UTF8String]);
    dict["playtime"] = playtime;

    // CloudKit has no separate fileId concept for this custom record, use UUID for compatibility.
    dict["fileId"] = String([uuid UTF8String]);

    int coverSize = 0;
    CKAsset *coverAsset = record[@"cover"];
    if (coverAsset && coverAsset.fileURL) {
        NSNumber *coverSizeValue = nil;
        [coverAsset.fileURL getResourceValue:&coverSizeValue forKey:NSURLFileSizeKey error:nil];
        if (coverSizeValue) {
            coverSize = [coverSizeValue intValue];
        }
    }
    dict["coverSize"] = coverSize;

    CKAsset *fileAsset = record[@"file"];
    if (fileAsset && fileAsset.fileURL) {
         NSNumber *fileSizeValue = nil;
         [fileAsset.fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:nil];
         if (fileSizeValue) {
            dict["saveSize"] = [fileSizeValue intValue];
         } else {
            dict["saveSize"] = 0;
         }
    } else {
         dict["saveSize"] = 0;
    }
    return dict;
}

static bool _validate_metadata_and_limits(NSString *metadataJson,
                                          NSString *archiveFilePath,
                                          NSString *archiveCoverPath,
                                          String &out_msg,
                                          int &out_code) {
    out_msg = "";
    out_code = 0;

    NSString *metaStr = metadataJson ?: @"{}";
    NSData *metaData = [metaStr dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *metaObj = nil;
    if (metaData) {
        id parsed = [NSJSONSerialization JSONObjectWithData:metaData options:0 error:nil];
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            metaObj = (NSDictionary *)parsed;
        }
    }
    if (!metaObj) {
        out_code = 400009;
        out_msg = "Invalid metadata JSON";
        return false;
    }

    NSString *name = [metaObj[@"name"] isKindOfClass:[NSString class]] ? metaObj[@"name"] : @"";
    NSString *summary = [metaObj[@"summary"] isKindOfClass:[NSString class]] ? metaObj[@"summary"] : @"";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_-]+$" options:0 error:nil];
    NSUInteger nameMatches = [re numberOfMatchesInString:name options:0 range:NSMakeRange(0, name.length)];
    if (name.length == 0 || nameMatches == 0) {
        out_code = 400009;
        out_msg = "Invalid archive name";
        return false;
    }
    if (summary.length == 0) {
        out_code = 400009;
        out_msg = "Summary must not be empty";
        return false;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (archiveFilePath && archiveFilePath.length > 0) {
        NSDictionary *fileAttrs = [fm attributesOfItemAtPath:archiveFilePath error:nil];
        NSNumber *fileSize = fileAttrs[NSFileSize];
        if (fileSize && [fileSize unsignedLongLongValue] > 10ULL * 1024ULL * 1024ULL) {
            out_code = 400000;
            out_msg = "Archive file too large (max 10MB)";
            return false;
        }
    }

    if (archiveCoverPath && archiveCoverPath.length > 0 && [fm fileExistsAtPath:archiveCoverPath]) {
        NSDictionary *coverAttrs = [fm attributesOfItemAtPath:archiveCoverPath error:nil];
        NSNumber *coverSize = coverAttrs[NSFileSize];
        if (coverSize && [coverSize unsignedLongLongValue] > 512ULL * 1024ULL) {
            out_code = 400000;
            out_msg = "Cover file too large (max 512KB)";
            return false;
        }
    }

    return true;
}

static int _map_taptap_error_code(NSError *error, int default_code) {
    if (!error) return default_code;

    NSString *desc = error.localizedDescription ?: @"";
    if ([desc rangeOfString:@"not marked queryable" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [desc rangeOfString:@"not marked sortable" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return 300002;
    }

    if (![error.domain isEqualToString:CKErrorDomain]) {
        return default_code;
    }

    switch ((CKErrorCode)error.code) {
        case CKErrorNotAuthenticated:
        case CKErrorPermissionFailure:
            return 300001;

        case CKErrorUnknownItem:
            return 400002;

        case CKErrorQuotaExceeded:
            return 400005;

        case CKErrorLimitExceeded:
            return 400003;

        case CKErrorRequestRateLimited:
        case CKErrorZoneBusy:
        case CKErrorServerRecordChanged:
        case CKErrorBatchRequestFailed:
            return 400007;

        case CKErrorNetworkUnavailable:
        case CKErrorNetworkFailure:
        case CKErrorServiceUnavailable:
        case CKErrorOperationCancelled:
        case CKErrorAssetFileNotFound:
        case CKErrorAssetFileModified:
            return 400006;

        default:
            return default_code;
    }
}

void Godot3CloudSave::createArchive(String metadataJson, String archiveFilePath, String archiveCoverPath) {
    NSLog(@"[CloudSave] createArchive: start. filePath=%s coverPath=%s",
          archiveFilePath.utf8().get_data(), archiveCoverPath.utf8().get_data());
    _log_icloud_diagnostics(@"createArchive");

    NSString *filePath = [NSString stringWithUTF8String:archiveFilePath.utf8()];
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir];
    if (!exists) {
        NSLog(@"[CloudSave] createArchive: ERROR - path not found: %@", filePath);
        Dictionary ret;
        ret["type"] = "create_archive_failed";
        ret["msg"] = "Path not found: " + archiveFilePath;
        ret["code"] = 400000;
        _post_event(ret);
        return;
    }

    // If path is a directory, zip it first (same pattern as TapTap plugin)
    NSString *uploadFilePath = filePath;
    NSString *tempZipPath = nil;
    if (isDir) {
        NSLog(@"[CloudSave] createArchive: path is a directory, zipping contents...");
        NSData *zipData = [GodotCloudSaveZipHelper zipPath:filePath];
        if (!zipData) {
            NSLog(@"[CloudSave] createArchive: ERROR - failed to zip directory: %@", filePath);
            Dictionary ret;
            ret["type"] = "create_archive_failed";
            ret["msg"] = "Failed to zip directory: " + archiveFilePath;
            ret["code"] = 400000;
            _post_event(ret);
            return;
        }
        tempZipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"cloudsave_%@.zip", [[NSUUID UUID] UUIDString]]];
        [zipData writeToFile:tempZipPath atomically:YES];
        uploadFilePath = tempZipPath;
        NSLog(@"[CloudSave] createArchive: directory zipped to temp file: %@, size=%lu bytes",
              tempZipPath, (unsigned long)zipData.length);
    } else {
        NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        NSLog(@"[CloudSave] createArchive: file found, size=%@ bytes", fileAttrs[NSFileSize]);
    }

    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSLog(@"[CloudSave] createArchive: generated UUID=%@", uuid);
    CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:uuid];
    CKRecord *record = [[CKRecord alloc] initWithRecordType:@"GameArchive" recordID:recordID];

    record[@"file"] = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:uploadFilePath]];
    NSLog(@"[CloudSave] createArchive: file asset attached (isDir=%@, wasZipped=%@)",
          isDir ? @"YES" : @"NO", tempZipPath ? @"YES" : @"NO");

    if (archiveCoverPath.length() > 0) {
        NSString *coverPath = [NSString stringWithUTF8String:archiveCoverPath.utf8()];
        if ([[NSFileManager defaultManager] fileExistsAtPath:coverPath]) {
            record[@"cover"] = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:coverPath]];
            NSLog(@"[CloudSave] createArchive: cover asset attached from %@", coverPath);
        } else {
            NSLog(@"[CloudSave] createArchive: WARNING - cover file not found at %@, skipping", coverPath);
        }
    }

    NSString *metaStr = [NSString stringWithUTF8String:metadataJson.utf8()];
    if (!metaStr || metaStr.length == 0) metaStr = @"{}";

    NSString *coverPathForValidation = archiveCoverPath.length() > 0 ? [NSString stringWithUTF8String:archiveCoverPath.utf8()] : @"";
    Dictionary requestArchiveData = _build_create_request_archive_dict(uuid, metaStr, uploadFilePath, coverPathForValidation);

    String validation_msg;
    int validation_code = 0;
    if (!_validate_metadata_and_limits(metaStr, uploadFilePath, coverPathForValidation, validation_msg, validation_code)) {
        if (tempZipPath) {
            [[NSFileManager defaultManager] removeItemAtPath:tempZipPath error:nil];
        }
        Dictionary ret;
        ret["type"] = "create_archive_failed";
        ret["msg"] = validation_msg;
        ret["code"] = validation_code;
        _post_event(ret);
        return;
    }

    // Store metadata JSON string directly
    record[@"metadata"] = metaStr;
    NSLog(@"[CloudSave] createArchive: metadata set: %@", metaStr);

    CKContainer *container = nil;
    CKDatabase *database = nil;
    @try {
        container = [CKContainer defaultContainer];
        NSLog(@"[CloudSave] createArchive: container=%@", container.containerIdentifier);
        database = [container privateCloudDatabase];
    } @catch (NSException *exception) {
        NSLog(@"[CloudSave] createArchive: ERROR - CloudKit exception: %@", exception.reason);
        Dictionary ret;
        ret["type"] = "create_archive_failed";
        ret["msg"] = String("CloudKit disabled: ") + String([exception.reason UTF8String]);
        ret["code"] = 300002;
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] createArchive: saving record to CloudKit... uuid=%@ container=%@",
          uuid, container.containerIdentifier);
    [database saveRecord:record completionHandler:^(CKRecord *savedRecord, NSError *error) {
        // Cleanup temp zip regardless of outcome
        if (tempZipPath) {
            [[NSFileManager defaultManager] removeItemAtPath:tempZipPath error:nil];
            NSLog(@"[CloudSave] createArchive: temp zip cleaned up: %@", tempZipPath);
        }
        Dictionary ret;
        if (error) {
            NSLog(@"[CloudSave] createArchive: ERROR - save failed. code=%ld domain=%@ desc=%@",
                  (long)error.code, error.domain, error.localizedDescription);
            ret["type"] = "create_archive_failed";
            ret["msg"] = String([error.localizedDescription UTF8String]);
            ret["code"] = _map_taptap_error_code(error, 400006);
        } else {
            NSLog(@"[CloudSave] createArchive: SUCCESS - saved record=%@ createdAt=%@ container=%@",
                  savedRecord.recordID.recordName,
                  savedRecord.creationDate,
                  savedRecord.recordID.zoneID.zoneName);
            ret["type"] = "create_archive_success";
            ret["data"] = recordToDictionary(savedRecord);
            _cache_recent_write(String([uuid UTF8String]), requestArchiveData);
        }
        _post_event(ret);
    }];
}

void Godot3CloudSave::getArchiveList() {
    NSLog(@"[CloudSave] getArchiveList: start");
    _log_icloud_diagnostics(@"getArchiveList");

    NSPredicate *predicate = [NSPredicate predicateWithValue:YES];
    CKQuery *query = [[CKQuery alloc] initWithRecordType:@"GameArchive" predicate:predicate];
    // Avoid server-side sort/index dependency (e.g. ___modTime sortable).
    // We'll sort by modificationDate on client side after fetching.

    CKContainer *container = nil;
    CKDatabase *database = nil;
    @try {
        container = [CKContainer defaultContainer];
        NSLog(@"[CloudSave] getArchiveList: container=%@", container.containerIdentifier);
        database = [container privateCloudDatabase];
    } @catch (NSException *exception) {
        NSLog(@"[CloudSave] getArchiveList: ERROR - CloudKit exception: %@", exception.reason);
        Dictionary ret;
        ret["type"] = "get_archive_list_failed";
        ret["msg"] = String("CloudKit disabled: ") + String([exception.reason UTF8String]);
        ret["code"] = 300002;
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] getArchiveList: executing query on GameArchive... container=%@",
          container.containerIdentifier);
    [database performQuery:query inZoneWithID:nil completionHandler:^(NSArray<CKRecord *> * _Nullable results, NSError * _Nullable error) {
        Dictionary ret;
        if (error) {
            NSLog(@"[CloudSave] getArchiveList: ERROR - query failed. code=%ld domain=%@ desc=%@",
                  (long)error.code, error.domain, error.localizedDescription);
            // CKErrorUnknownItem (code=11): record type doesn't exist yet (first run, no saves uploaded).
            // Treat this as an empty list rather than a failure.
            if (error.code == 11) {
                NSLog(@"[CloudSave] getArchiveList: record type 'GameArchive' not found in schema - treating as empty list (first run)");
                Array cached = _get_all_recent_writes();
                Array list = cached.size() > 0 ? cached : Array();
                Dictionary data;
                data["list"] = list;
                data["archives"] = list;
                data["count"] = list.size();
                ret["type"] = "get_archive_list_success";
                ret["data"] = data;
                _post_event(ret);
                return;
            }
            // CKErrorServerRejectedRequest (code=12) with "recordName is not marked queryable"
            // can happen if server-side indexing/sorting is not fully configured.
            // Fallback: query without sort descriptors, then sort records client-side by modificationDate.
            if (error.code == 12 && [error.localizedDescription rangeOfString:@"recordName" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                NSLog(@"[CloudSave] getArchiveList: fallback to unsorted query (recordName not queryable)");
                CKQuery *fallbackQuery = [[CKQuery alloc] initWithRecordType:@"GameArchive" predicate:[NSPredicate predicateWithValue:YES]];
                CKQueryOperation *op = [[CKQueryOperation alloc] initWithQuery:fallbackQuery];
                NSMutableArray<CKRecord *> *fetchedRecords = [NSMutableArray array];

                op.recordFetchedBlock = ^(CKRecord * _Nonnull record) {
                    [fetchedRecords addObject:record];
                };

                op.queryCompletionBlock = ^(CKQueryCursor * _Nullable cursor, NSError * _Nullable operationError) {
                    Dictionary fallbackRet;
                    if (operationError) {
                        NSLog(@"[CloudSave] getArchiveList: fallback query ERROR - code=%ld domain=%@ desc=%@",
                              (long)operationError.code, operationError.domain, operationError.localizedDescription);
                        if (operationError.code == 12 && [operationError.localizedDescription rangeOfString:@"recordName" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                            NSLog(@"[CloudSave] getArchiveList: fallback still blocked by CloudKit index config, treating as empty list to avoid blocking app flow");
                            Array cached = _get_all_recent_writes();
                            Array list = cached.size() > 0 ? cached : Array();
                            Dictionary data;
                            data["list"] = list;
                            data["archives"] = list;
                            data["count"] = list.size();
                            fallbackRet["type"] = "get_archive_list_success";
                            fallbackRet["data"] = data;
                            _post_event(fallbackRet);
                            return;
                        }
                        fallbackRet["type"] = "get_archive_list_failed";
                        fallbackRet["msg"] = String([operationError.localizedDescription UTF8String]);
                        fallbackRet["code"] = _map_taptap_error_code(operationError, 300002);
                        _post_event(fallbackRet);
                        return;
                    }

                    [fetchedRecords sortUsingComparator:^NSComparisonResult(CKRecord *a, CKRecord *b) {
                        NSDate *ad = a.modificationDate ?: [NSDate distantPast];
                        NSDate *bd = b.modificationDate ?: [NSDate distantPast];
                        return [bd compare:ad];
                    }];

                    Array list;
                    for (CKRecord *record in fetchedRecords) {
                        list.push_back(recordToDictionary(record));
                    }

                    if (list.size() == 0) {
                        Array cached = _get_all_recent_writes();
                        if (cached.size() > 0) {
                            NSLog(@"[CloudSave] getArchiveList: fallback CACHE FALLBACK - CK returned 0, returning %d cached entries",
                                  cached.size());
                            list = cached;
                        } else {
                            NSLog(@"[CloudSave] getArchiveList: fallback CloudKit returned 0 and cache empty");
                        }
                    } else {
                        NSLog(@"[CloudSave] getArchiveList: fallback merging CK results with cache for %d records",
                              list.size());
                        for (int i = 0; i < list.size(); i++) {
                            Dictionary item = list[i];
                            String item_uuid = item.has("uuid") ? (String)item["uuid"] : "";
                            if (item_uuid.length() == 0) {
                                item_uuid = item.has("archiveUuid") ? (String)item["archiveUuid"] : "";
                            }
                            Dictionary cached_item;
                            if (item_uuid.length() > 0 && _get_recent_write(item_uuid, cached_item)) {
                                NSLog(@"[CloudSave] getArchiveList: fallback CACHE OVERRIDE uuid=%s",
                                      item_uuid.utf8().get_data());
                                list.set(i, cached_item);
                            }
                        }
                    }

                    Dictionary data;
                    data["list"] = list;
                    data["archives"] = list;
                    data["count"] = list.size();
                    fallbackRet["type"] = "get_archive_list_success";
                    fallbackRet["data"] = data;
                    NSLog(@"[CloudSave] getArchiveList: fallback SUCCESS - found %lu CK records, final count=%d",
                          (unsigned long)fetchedRecords.count, list.size());
                    _post_event(fallbackRet);
                };

                [database addOperation:op];
                return;
            }
            ret["type"] = "get_archive_list_failed";
            ret["msg"] = String([error.localizedDescription UTF8String]);
            ret["code"] = _map_taptap_error_code(error, 300002);
        } else {
            NSLog(@"[CloudSave] getArchiveList: raw query SUCCESS - found %lu records from CloudKit",
                  (unsigned long)results.count);
            NSArray<CKRecord *> *sortedResults = [results sortedArrayUsingComparator:^NSComparisonResult(CKRecord *a, CKRecord *b) {
                NSDate *ad = a.modificationDate ?: [NSDate distantPast];
                NSDate *bd = b.modificationDate ?: [NSDate distantPast];
                return [bd compare:ad];
            }];
            Array list;
            for (CKRecord *record in sortedResults) {
                NSLog(@"[CloudSave] getArchiveList: record uuid=%@ modified=%@",
                      record.recordID.recordName, record.modificationDate);
                list.push_back(recordToDictionary(record));
            }

            if (list.size() == 0) {
                Array cached = _get_all_recent_writes();
                if (cached.size() > 0) {
                    NSLog(@"[CloudSave] getArchiveList: CACHE FALLBACK - CloudKit returned 0, returning %d cached entries",
                          cached.size());
                    list = cached;
                } else {
                    NSLog(@"[CloudSave] getArchiveList: CloudKit returned 0 and cache is empty - final empty list");
                }
            } else {
                NSLog(@"[CloudSave] getArchiveList: merging CloudKit results with cache for %d records", list.size());
                for (int i = 0; i < list.size(); i++) {
                    Dictionary item = list[i];
                    String item_uuid = item.has("uuid") ? (String)item["uuid"] : "";
                    if (item_uuid.length() == 0) {
                        item_uuid = item.has("archiveUuid") ? (String)item["archiveUuid"] : "";
                    }
                    Dictionary cached_item;
                    if (item_uuid.length() > 0 && _get_recent_write(item_uuid, cached_item)) {
                        NSLog(@"[CloudSave] getArchiveList: CACHE OVERRIDE for uuid=%s",
                              item_uuid.utf8().get_data());
                        list.set(i, cached_item);
                    }
                }
            }

            Dictionary data;
            data["list"] = list;
            data["archives"] = list;
            data["count"] = list.size();
            NSLog(@"[CloudSave] getArchiveList: final list count=%d", list.size());
            ret["type"] = "get_archive_list_success";
            ret["data"] = data;
        }
        _post_event(ret);
    }];
}

void Godot3CloudSave::downloadArchiveData(String archiveUuid, String archiveFileId, String localArchivePath) {
    NSLog(@"[CloudSave] downloadArchiveData: start. uuid=%s destPath=%s",
          archiveUuid.utf8().get_data(), localArchivePath.utf8().get_data());

    NSString *uuid = [NSString stringWithUTF8String:archiveUuid.utf8()];
    CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:uuid];

    CKContainer *container = nil;
    CKDatabase *database = nil;
    @try {
        container = [CKContainer defaultContainer];
        NSLog(@"[CloudSave] downloadArchiveData: container=%@", container.containerIdentifier);
        database = [container privateCloudDatabase];
    } @catch (NSException *exception) {
        NSLog(@"[CloudSave] downloadArchiveData: ERROR - CloudKit exception: %@", exception.reason);
        Dictionary ret;
        ret["type"] = "download_archive_failed";
        ret["msg"] = String("CloudKit disabled: ") + String([exception.reason UTF8String]);
        ret["code"] = 300002;
        ret["uuid"] = archiveUuid;
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] downloadArchiveData: fetching record for uuid=%@", uuid);
    [database fetchRecordWithID:recordID completionHandler:^(CKRecord * _Nullable record, NSError * _Nullable error) {
        Dictionary ret;
        if (error || !record) {
            NSLog(@"[CloudSave] downloadArchiveData: ERROR - fetch failed. code=%ld domain=%@ desc=%@",
                  error ? (long)error.code : -1,
                  error ? error.domain : @"N/A",
                  error ? error.localizedDescription : @"Record not found");
            ret["type"] = "download_archive_failed";
            ret["msg"] = String(error ? [error.localizedDescription UTF8String] : "Record not found");
            ret["code"] = _map_taptap_error_code(error, 400002);
            ret["uuid"] = archiveUuid;
        } else {
            NSLog(@"[CloudSave] downloadArchiveData: record fetched, uuid=%@ modified=%@",
                  record.recordID.recordName, record.modificationDate);
            CKAsset *asset = record[@"file"];
            if (asset && asset.fileURL) {
                NSLog(@"[CloudSave] downloadArchiveData: file asset found at temp url=%@", asset.fileURL.path);
                NSString *destPath = [NSString stringWithUTF8String:localArchivePath.utf8()];
                NSFileManager *fm = [NSFileManager defaultManager];

                // Read the asset data to check if it's a zip
                NSData *assetData = [NSData dataWithContentsOfURL:asset.fileURL];
                NSLog(@"[CloudSave] downloadArchiveData: asset data size=%lu bytes", (unsigned long)assetData.length);

                // Check zip magic bytes: PK\x03\x04
                const uint8_t zipMagic[4] = { 0x50, 0x4B, 0x03, 0x04 };
                BOOL isZip = assetData.length >= 4 && memcmp(assetData.bytes, zipMagic, 4) == 0;
                NSLog(@"[CloudSave] downloadArchiveData: isZip=%@, destPath=%@",
                      isZip ? @"YES" : @"NO", destPath);

                BOOL success = NO;
                if (isZip) {
                    // Remove existing dest before unzipping
                    BOOL isDestDir = NO;
                    if ([fm fileExistsAtPath:destPath isDirectory:&isDestDir]) {
                        [fm removeItemAtPath:destPath error:nil];
                        NSLog(@"[CloudSave] downloadArchiveData: removed existing dest (isDir=%@)",
                              isDestDir ? @"YES" : @"NO");
                    }
                    NSLog(@"[CloudSave] downloadArchiveData: unzipping to %@", destPath);
                    success = [GodotCloudSaveZipHelper unzipData:assetData toPath:destPath];
                    if (success) {
                        NSLog(@"[CloudSave] downloadArchiveData: unzip SUCCESS");
                    } else {
                        NSLog(@"[CloudSave] downloadArchiveData: ERROR - unzip FAILED");
                    }
                } else {
                    // Plain file: just copy
                    if ([fm fileExistsAtPath:destPath]) {
                        [fm removeItemAtPath:destPath error:nil];
                    }
                    NSString *destDir = [destPath stringByDeletingLastPathComponent];
                    if (![fm fileExistsAtPath:destDir]) {
                        [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];
                    }
                    NSError *copyError = nil;
                    [fm copyItemAtURL:asset.fileURL toURL:[NSURL fileURLWithPath:destPath] error:&copyError];
                    success = (copyError == nil);
                    if (!success) {
                        NSLog(@"[CloudSave] downloadArchiveData: ERROR - copy failed. code=%ld desc=%@",
                              (long)copyError.code, copyError.localizedDescription);
                    }
                }

                if (success) {
                    NSDictionary *destAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:destPath error:nil];
                    NSLog(@"[CloudSave] downloadArchiveData: SUCCESS at %@, attrs=%@", destPath, destAttrs[NSFileSize]);
                    ret["type"] = "download_archive_success";
                    ret["uuid"] = archiveUuid;
                    Dictionary data;
                    data["path"] = localArchivePath;
                    data["size"] = assetData ? (int)assetData.length : 0;
                    ret["data"] = data;
                } else {
                    ret["type"] = "download_archive_failed";
                    ret["msg"] = isZip ? "Unzip failed" : "File copy failed";
                    ret["code"] = 400006;
                    ret["uuid"] = archiveUuid;
                }
            } else {
                NSLog(@"[CloudSave] downloadArchiveData: ERROR - no file asset in record (asset=%@)", asset);
                ret["type"] = "download_archive_failed";
                ret["msg"] = "No file asset in record";
                ret["code"] = 400002;
                ret["uuid"] = archiveUuid;
            }
        }
        _post_event(ret);
    }];
}

void Godot3CloudSave::updateArchive(String archiveUuid, String metadataJson, String archiveFilePath, String archiveCoverPath) {
    NSLog(@"[CloudSave] updateArchive: start. uuid=%s filePath=%s",
          archiveUuid.utf8().get_data(), archiveFilePath.utf8().get_data());
    _log_icloud_diagnostics(@"updateArchive");

    NSString *uuid = [NSString stringWithUTF8String:archiveUuid.utf8()];
    CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:uuid];

    CKContainer *container = nil;
    CKDatabase *database = nil;
    @try {
        container = [CKContainer defaultContainer];
        NSLog(@"[CloudSave] updateArchive: container=%@", container.containerIdentifier);
        database = [container privateCloudDatabase];
    } @catch (NSException *exception) {
        NSLog(@"[CloudSave] updateArchive: ERROR - CloudKit exception: %@", exception.reason);
        Dictionary ret;
        ret["type"] = "update_archive_failed";
        ret["msg"] = String("CloudKit disabled: ") + String([exception.reason UTF8String]);
        ret["code"] = 300002;
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] updateArchive: fetching existing record uuid=%@...", uuid);
    [database fetchRecordWithID:recordID completionHandler:^(CKRecord * _Nullable record, NSError * _Nullable error) {
        if (error || !record) {
            NSLog(@"[CloudSave] updateArchive: ERROR - fetch failed. code=%ld domain=%@ desc=%@",
                  error ? (long)error.code : -1,
                  error ? error.domain : @"N/A",
                  error ? error.localizedDescription : @"Record not found");
            Dictionary ret;
            ret["type"] = "update_archive_failed";
            ret["msg"] = String(error ? [error.localizedDescription UTF8String] : "Record not found");
            ret["code"] = _map_taptap_error_code(error, 400002);
            _post_event(ret);
            return;
        }

        NSLog(@"[CloudSave] updateArchive: record fetched, applying updates...");

        NSString *filePath = [NSString stringWithUTF8String:archiveFilePath.utf8()];
        BOOL isDir = NO;
        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir];
        __block NSString *tempZipPath = nil;
        if (fileExists) {
            NSString *uploadFilePath = filePath;
            if (isDir) {
                NSLog(@"[CloudSave] updateArchive: path is a directory, zipping contents...");
                NSData *zipData = [GodotCloudSaveZipHelper zipPath:filePath];
                if (!zipData) {
                    NSLog(@"[CloudSave] updateArchive: ERROR - failed to zip directory: %@", filePath);
                    Dictionary ret;
                    ret["type"] = "update_archive_failed";
                    ret["msg"] = "Failed to zip directory: " + archiveFilePath;
                    ret["code"] = 400000;
                    _post_event(ret);
                    return;
                }
                tempZipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"cloudsave_%@.zip", [[NSUUID UUID] UUIDString]]];
                [zipData writeToFile:tempZipPath atomically:YES];
                uploadFilePath = tempZipPath;
                NSLog(@"[CloudSave] updateArchive: directory zipped to %@, size=%lu bytes",
                      tempZipPath, (unsigned long)zipData.length);
            } else {
                NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
                NSLog(@"[CloudSave] updateArchive: attaching file asset, size=%@", fileAttrs[NSFileSize]);
            }
            record[@"file"] = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:uploadFilePath]];
        } else {
            NSLog(@"[CloudSave] updateArchive: WARNING - file not found at %@, keeping existing", filePath);
        }

        if (archiveCoverPath.length() > 0) {
            NSString *coverPath = [NSString stringWithUTF8String:archiveCoverPath.utf8()];
            if ([[NSFileManager defaultManager] fileExistsAtPath:coverPath]) {
                record[@"cover"] = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:coverPath]];
                NSLog(@"[CloudSave] updateArchive: cover asset attached");
            } else {
                NSLog(@"[CloudSave] updateArchive: WARNING - cover not found at %@, skipping", coverPath);
            }
        }

        NSString *metaStr = [NSString stringWithUTF8String:metadataJson.utf8()];
        if (!metaStr || metaStr.length == 0) metaStr = @"{}";

        Dictionary requestArchiveData = _build_update_request_archive_dict(
            recordToDictionary(record),
            metaStr,
            fileExists ? (isDir ? tempZipPath : filePath) : nil,
            (archiveCoverPath.length() > 0) ? [NSString stringWithUTF8String:archiveCoverPath.utf8()] : nil
        );

        String validation_msg;
        int validation_code = 0;
        NSString *coverPathForValidation = archiveCoverPath.length() > 0 ? [NSString stringWithUTF8String:archiveCoverPath.utf8()] : @"";
        NSString *filePathForValidation = fileExists ? (isDir ? tempZipPath : filePath) : @"";
        if (filePathForValidation && filePathForValidation.length > 0) {
            if (!_validate_metadata_and_limits(metaStr, filePathForValidation, coverPathForValidation, validation_msg, validation_code)) {
                if (tempZipPath) {
                    [[NSFileManager defaultManager] removeItemAtPath:tempZipPath error:nil];
                }
                Dictionary ret;
                ret["type"] = "update_archive_failed";
                ret["msg"] = validation_msg;
                ret["code"] = validation_code;
                _post_event(ret);
                return;
            }
        }

        // Store metadata JSON string directly
        record[@"metadata"] = metaStr;
        NSLog(@"[CloudSave] updateArchive: metadata updated: %@", metaStr);

        CKModifyRecordsOperation *op = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:@[record] recordIDsToDelete:nil];
        op.savePolicy = CKRecordSaveAllKeys;
        NSLog(@"[CloudSave] updateArchive: submitting CKModifyRecordsOperation...");

        op.modifyRecordsCompletionBlock = ^(NSArray<CKRecord *> * _Nullable savedRecords, NSArray<CKRecordID *> * _Nullable deletedRecordIDs, NSError * _Nullable operationError) {
            if (tempZipPath) {
                [[NSFileManager defaultManager] removeItemAtPath:tempZipPath error:nil];
                NSLog(@"[CloudSave] updateArchive: temp zip cleaned up: %@", tempZipPath);
            }
            Dictionary ret;
            if (operationError) {
                NSLog(@"[CloudSave] updateArchive: ERROR - modify failed. code=%ld domain=%@ desc=%@",
                      (long)operationError.code, operationError.domain, operationError.localizedDescription);
                ret["type"] = "update_archive_failed";
                ret["msg"] = String([operationError.localizedDescription UTF8String]);
                ret["code"] = _map_taptap_error_code(operationError, 400006);
            } else {
                NSLog(@"[CloudSave] updateArchive: SUCCESS - saved %lu records uuid=%s modifiedAt=%@",
                      (unsigned long)savedRecords.count,
                      archiveUuid.utf8().get_data(),
                      savedRecords.count > 0 ? savedRecords[0].modificationDate : nil);
                ret["type"] = "update_archive_success";
                if (savedRecords.count > 0) {
                    ret["data"] = recordToDictionary(savedRecords[0]);
                }
                _cache_recent_write(archiveUuid, requestArchiveData);
            }
            _post_event(ret);
        };

        [database addOperation:op];
    }];
}

void Godot3CloudSave::deleteArchive(String archiveUuid) {
    NSLog(@"[CloudSave] deleteArchive: start. uuid=%s", archiveUuid.utf8().get_data());
    _log_icloud_diagnostics(@"deleteArchive");

    NSString *uuid = [NSString stringWithUTF8String:archiveUuid.utf8()];
    CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:uuid];

    CKContainer *container = nil;
    CKDatabase *database = nil;
    @try {
        container = [CKContainer defaultContainer];
        NSLog(@"[CloudSave] deleteArchive: container=%@", container.containerIdentifier);
        database = [container privateCloudDatabase];
    } @catch (NSException *exception) {
        NSLog(@"[CloudSave] deleteArchive: ERROR - CloudKit exception: %@", exception.reason);
        Dictionary ret;
        ret["type"] = "delete_archive_failed";
        ret["msg"] = String("CloudKit disabled: ") + String([exception.reason UTF8String]);
        ret["code"] = 300002;
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] deleteArchive: fetching record before delete uuid=%@...", uuid);
    [database fetchRecordWithID:recordID completionHandler:^(CKRecord * _Nullable record, NSError * _Nullable fetchError) {
        if (fetchError || !record) {
            Dictionary ret;
            ret["type"] = "delete_archive_failed";
            ret["msg"] = String(fetchError ? [fetchError.localizedDescription UTF8String] : "Record not found");
            ret["code"] = _map_taptap_error_code(fetchError, 400002);
            _post_event(ret);
            return;
        }

        Dictionary archiveData = recordToDictionary(record);
        NSLog(@"[CloudSave] deleteArchive: deleting record uuid=%@...", uuid);
        [database deleteRecordWithID:recordID completionHandler:^(CKRecordID * _Nullable deletedID, NSError * _Nullable error) {
            Dictionary ret;
            if (error) {
                NSLog(@"[CloudSave] deleteArchive: ERROR - delete failed. code=%ld domain=%@ desc=%@",
                      (long)error.code, error.domain, error.localizedDescription);
                ret["type"] = "delete_archive_failed";
                ret["msg"] = String([error.localizedDescription UTF8String]);
                ret["code"] = _map_taptap_error_code(error, 400006);
            } else {
                NSLog(@"[CloudSave] deleteArchive: SUCCESS - deleted uuid=%@", deletedID.recordName);
                ret["type"] = "delete_archive_success";
                ret["uuid"] = archiveUuid;
                ret["data"] = archiveData;
            }
            _post_event(ret);
        }];
    }];
}

void Godot3CloudSave::getArchiveCover(String archiveUuid, String archiveFileId) {
    NSLog(@"[CloudSave] getArchiveCover: start. uuid=%s", archiveUuid.utf8().get_data());

    NSString *uuid = [NSString stringWithUTF8String:archiveUuid.utf8()];
    CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:uuid];

    CKContainer *container = nil;
    CKDatabase *database = nil;
    @try {
        container = [CKContainer defaultContainer];
        NSLog(@"[CloudSave] getArchiveCover: container=%@", container.containerIdentifier);
        database = [container privateCloudDatabase];
    } @catch (NSException *exception) {
        NSLog(@"[CloudSave] getArchiveCover: ERROR - CloudKit exception: %@", exception.reason);
        Dictionary ret;
        ret["type"] = "get_archive_cover_failed";
        ret["msg"] = String("CloudKit disabled: ") + String([exception.reason UTF8String]);
        ret["code"] = 300002;
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] getArchiveCover: fetching record uuid=%@...", uuid);
    [database fetchRecordWithID:recordID completionHandler:^(CKRecord * _Nullable record, NSError * _Nullable error) {
         Dictionary ret;
         if (error || !record) {
             NSLog(@"[CloudSave] getArchiveCover: ERROR - fetch failed. code=%ld domain=%@ desc=%@",
                   error ? (long)error.code : -1,
                   error ? error.domain : @"N/A",
                   error ? error.localizedDescription : @"Record not found");
             ret["type"] = "get_archive_cover_failed";
             ret["msg"] = String(error ? [error.localizedDescription UTF8String] : "Record not found");
             ret["code"] = _map_taptap_error_code(error, 400002);
         } else {
             NSLog(@"[CloudSave] getArchiveCover: record fetched, checking cover asset...");
             CKAsset *coverAsset = record[@"cover"];
             if (coverAsset && coverAsset.fileURL) {
                 NSLog(@"[CloudSave] getArchiveCover: cover asset found at %@", coverAsset.fileURL.path);
                 NSData *data = [NSData dataWithContentsOfURL:coverAsset.fileURL];
                 if (data) {
                     NSLog(@"[CloudSave] getArchiveCover: SUCCESS - cover data loaded, size=%lu bytes", (unsigned long)data.length);
                     ret["type"] = "get_archive_cover_success";
                     
                     PoolByteArray pba;
                     pba.resize([data length]);
                     {
                        PoolByteArray::Write w = pba.write();
                        memcpy(w.ptr(), [data bytes], [data length]);
                     }
                     ret["data"] = pba;
                 } else {
                     NSLog(@"[CloudSave] getArchiveCover: ERROR - cover asset URL exists but data is empty");
                     ret["type"] = "get_archive_cover_failed";
                     ret["msg"] = "Cover data empty";
                     ret["code"] = 400002;
                 }
             } else {
                 NSLog(@"[CloudSave] getArchiveCover: ERROR - no cover asset in record (coverAsset=%@)", coverAsset);
                 ret["type"] = "get_archive_cover_failed";
                 ret["msg"] = "No cover asset";
                 ret["code"] = 400002;
             }
         }
         _post_event(ret);
    }];
}
