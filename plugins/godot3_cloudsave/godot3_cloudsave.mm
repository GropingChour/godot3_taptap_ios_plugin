
#include "godot3_cloudsave.h"
#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation.h>
#include <zlib.h>
#include <dirent.h>
#include <sys/stat.h>

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
    
    ClassDB::bind_method(D_METHOD("isAvailable"), &Godot3CloudSave::isAvailable);
}

bool Godot3CloudSave::isAvailable() {
    return [[NSFileManager defaultManager] ubiquityIdentityToken] != nil;
}

// Helpers
Dictionary recordToDictionary(CKRecord *record) {
    Dictionary dict;
    dict["archiveUuid"] = String([record.recordID.recordName UTF8String]);
    dict["updatedTime"] = (uint64_t)([record.modificationDate timeIntervalSince1970] * 1000);
    
    NSString *metadataStr = record[@"metadata"];
    if (metadataStr) {
        dict["metadata"] = String([metadataStr UTF8String]);
    } else {
        dict["metadata"] = "";
    }
    
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

void Godot3CloudSave::createArchive(String metadataJson, String archiveFilePath, String archiveCoverPath) {
    NSLog(@"[CloudSave] createArchive: start. filePath=%s coverPath=%s",
          archiveFilePath.utf8().get_data(), archiveCoverPath.utf8().get_data());

    NSString *filePath = [NSString stringWithUTF8String:archiveFilePath.utf8()];
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir];
    if (!exists) {
        NSLog(@"[CloudSave] createArchive: ERROR - path not found: %@", filePath);
        Dictionary ret;
        ret["type"] = "create_archive_failed";
        ret["msg"] = "Path not found: " + archiveFilePath;
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

    // Store metadata JSON string directly
    NSString *metaStr = [NSString stringWithUTF8String:metadataJson.utf8()];
    if (!metaStr || metaStr.length == 0) metaStr = @"{}";
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
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] createArchive: saving record to CloudKit...");
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
        } else {
            NSLog(@"[CloudSave] createArchive: SUCCESS - saved record=%@", savedRecord.recordID.recordName);
            ret["type"] = "create_archive_success";
            ret["data"] = recordToDictionary(savedRecord);
        }
        _post_event(ret);
    }];
}

void Godot3CloudSave::getArchiveList() {
    NSLog(@"[CloudSave] getArchiveList: start");

    NSPredicate *predicate = [NSPredicate predicateWithValue:YES];
    CKQuery *query = [[CKQuery alloc] initWithRecordType:@"GameArchive" predicate:predicate];
    query.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"modificationDate" ascending:NO]];

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
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] getArchiveList: executing query on GameArchive...");
    [database performQuery:query inZoneWithID:nil completionHandler:^(NSArray<CKRecord *> * _Nullable results, NSError * _Nullable error) {
        Dictionary ret;
        if (error) {
            NSLog(@"[CloudSave] getArchiveList: ERROR - query failed. code=%ld domain=%@ desc=%@",
                  (long)error.code, error.domain, error.localizedDescription);
            // CKErrorUnknownItem (code=11): record type doesn't exist yet (first run, no saves uploaded).
            // Treat this as an empty list rather than a failure.
            if (error.code == 11) {
                NSLog(@"[CloudSave] getArchiveList: record type 'GameArchive' not found in schema - treating as empty list (first run)");
                Dictionary data;
                data["list"] = Array();
                ret["type"] = "get_archive_list_success";
                ret["data"] = data;
                _post_event(ret);
                return;
            }
            ret["type"] = "get_archive_list_failed";
            ret["msg"] = String([error.localizedDescription UTF8String]);
        } else {
            NSLog(@"[CloudSave] getArchiveList: SUCCESS - found %lu records", (unsigned long)results.count);
            Array list;
            for (CKRecord *record in results) {
                NSLog(@"[CloudSave] getArchiveList: record uuid=%@ modified=%@",
                      record.recordID.recordName, record.modificationDate);
                list.push_back(recordToDictionary(record));
            }
            Dictionary data;
            data["list"] = list;
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
                    ret["data"] = recordToDictionary(record);
                } else {
                    ret["type"] = "download_archive_failed";
                    ret["msg"] = isZip ? "Unzip failed" : "File copy failed";
                    ret["uuid"] = archiveUuid;
                }
            } else {
                NSLog(@"[CloudSave] downloadArchiveData: ERROR - no file asset in record (asset=%@)", asset);
                ret["type"] = "download_archive_failed";
                ret["msg"] = "No file asset in record";
                ret["uuid"] = archiveUuid;
            }
        }
        _post_event(ret);
    }];
}

void Godot3CloudSave::updateArchive(String archiveUuid, String metadataJson, String archiveFilePath, String archiveCoverPath) {
    NSLog(@"[CloudSave] updateArchive: start. uuid=%s filePath=%s",
          archiveUuid.utf8().get_data(), archiveFilePath.utf8().get_data());

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

        // Store metadata JSON string directly
        NSString *metaStr = [NSString stringWithUTF8String:metadataJson.utf8()];
        if (!metaStr || metaStr.length == 0) metaStr = @"{}";
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
            } else {
                NSLog(@"[CloudSave] updateArchive: SUCCESS - saved %lu records", (unsigned long)savedRecords.count);
                ret["type"] = "update_archive_success";
                if (savedRecords.count > 0) {
                    ret["data"] = recordToDictionary(savedRecords[0]);
                }
            }
            _post_event(ret);
        };

        [database addOperation:op];
    }];
}

void Godot3CloudSave::deleteArchive(String archiveUuid) {
    NSLog(@"[CloudSave] deleteArchive: start. uuid=%s", archiveUuid.utf8().get_data());

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
        _post_event(ret);
        return;
    }

    NSLog(@"[CloudSave] deleteArchive: deleting record uuid=%@...", uuid);
    [database deleteRecordWithID:recordID completionHandler:^(CKRecordID * _Nullable deletedID, NSError * _Nullable error) {
        Dictionary ret;
        if (error) {
            NSLog(@"[CloudSave] deleteArchive: ERROR - delete failed. code=%ld domain=%@ desc=%@",
                  (long)error.code, error.domain, error.localizedDescription);
            ret["type"] = "delete_archive_failed";
            ret["msg"] = String([error.localizedDescription UTF8String]);
        } else {
            NSLog(@"[CloudSave] deleteArchive: SUCCESS - deleted uuid=%@", deletedID.recordName);
            ret["type"] = "delete_archive_success";
            ret["uuid"] = archiveUuid;
        }
        _post_event(ret);
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
                 }
             } else {
                 NSLog(@"[CloudSave] getArchiveCover: ERROR - no cover asset in record (coverAsset=%@)", coverAsset);
                 ret["type"] = "get_archive_cover_failed";
                 ret["msg"] = "No cover asset";
             }
         }
         _post_event(ret);
    }];
}
