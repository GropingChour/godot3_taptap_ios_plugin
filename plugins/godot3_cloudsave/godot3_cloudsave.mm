
#include "godot3_cloudsave.h"
#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation.h>

#if VERSION_MAJOR == 4
#import "platform/ios/app_delegate.h"
#define GODOT_BYTE_ARRAY Variant::PACKED_BYTE_ARRAY
#else
#import "platform/iphone/app_delegate.h"
#define GODOT_BYTE_ARRAY Variant::POOL_BYTE_ARRAY
#endif

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
    
    ClassDB::bind_method(D_METHOD("createArchive", "metadata", "archiveFilePath", "archiveCoverPath"), &Godot3CloudSave::createArchive);
    ClassDB::bind_method(D_METHOD("getArchiveList"), &Godot3CloudSave::getArchiveList);
    ClassDB::bind_method(D_METHOD("downloadArchiveData", "archiveUuid", "archiveFileId", "localArchivePath"), &Godot3CloudSave::downloadArchiveData);
    ClassDB::bind_method(D_METHOD("updateArchive", "archiveUuid", "metadata", "archiveFilePath", "archiveCoverPath"), &Godot3CloudSave::updateArchive);
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

void Godot3CloudSave::createArchive(Dictionary metadata, String archiveFilePath, String archiveCoverPath) {
    NSLog(@"[CloudSave] createArchive: start. filePath=%s coverPath=%s",
          archiveFilePath.utf8().get_data(), archiveCoverPath.utf8().get_data());

    NSString *filePath = [NSString stringWithUTF8String:archiveFilePath.utf8()];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"[CloudSave] createArchive: ERROR - file not found at path: %@", filePath);
        Dictionary ret;
        ret["type"] = "create_archive_failed";
        ret["msg"] = "File not found: " + archiveFilePath;
        _post_event(ret);
        return;
    }

    NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    NSLog(@"[CloudSave] createArchive: file found, size=%@ bytes", fileAttrs[NSFileSize]);

    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSLog(@"[CloudSave] createArchive: generated UUID=%@", uuid);
    CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:uuid];
    CKRecord *record = [[CKRecord alloc] initWithRecordType:@"GameArchive" recordID:recordID];

    record[@"file"] = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:filePath]];
    NSLog(@"[CloudSave] createArchive: file asset attached");

    if (archiveCoverPath.length() > 0) {
        NSString *coverPath = [NSString stringWithUTF8String:archiveCoverPath.utf8()];
        if ([[NSFileManager defaultManager] fileExistsAtPath:coverPath]) {
            record[@"cover"] = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:coverPath]];
            NSLog(@"[CloudSave] createArchive: cover asset attached from %@", coverPath);
        } else {
            NSLog(@"[CloudSave] createArchive: WARNING - cover file not found at %@, skipping", coverPath);
        }
    }

    String metaStr = String(Variant(metadata));
    record[@"metadata"] = [NSString stringWithUTF8String:metaStr.utf8()];
    NSLog(@"[CloudSave] createArchive: metadata set: %s", metaStr.utf8().get_data());

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
                NSError *copyError = nil;
                NSString *destPath = [NSString stringWithUTF8String:localArchivePath.utf8()];
                NSFileManager *fm = [NSFileManager defaultManager];

                if ([fm fileExistsAtPath:destPath]) {
                    NSLog(@"[CloudSave] downloadArchiveData: existing file at dest, removing...");
                    [fm removeItemAtPath:destPath error:nil];
                }

                // Ensure destination directory exists
                NSString *destDir = [destPath stringByDeletingLastPathComponent];
                if (![fm fileExistsAtPath:destDir]) {
                    [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];
                    NSLog(@"[CloudSave] downloadArchiveData: created dest directory: %@", destDir);
                }

                NSLog(@"[CloudSave] downloadArchiveData: copying from %@ to %@", asset.fileURL.path, destPath);
                [fm copyItemAtURL:asset.fileURL toURL:[NSURL fileURLWithPath:destPath] error:&copyError];

                if (copyError) {
                    NSLog(@"[CloudSave] downloadArchiveData: ERROR - copy failed. code=%ld desc=%@",
                          (long)copyError.code, copyError.localizedDescription);
                    ret["type"] = "download_archive_failed";
                    ret["msg"] = String([copyError.localizedDescription UTF8String]);
                    ret["uuid"] = archiveUuid;
                } else {
                    NSDictionary *destAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:destPath error:nil];
                    NSLog(@"[CloudSave] downloadArchiveData: SUCCESS - file saved at %@, size=%@", destPath, destAttrs[NSFileSize]);
                    ret["type"] = "download_archive_success";
                    ret["uuid"] = archiveUuid;
                    ret["data"] = recordToDictionary(record);
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

void Godot3CloudSave::updateArchive(String archiveUuid, Dictionary metadata, String archiveFilePath, String archiveCoverPath) {
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
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            NSLog(@"[CloudSave] updateArchive: attaching new file asset, size=%@", fileAttrs[NSFileSize]);
            record[@"file"] = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:filePath]];
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

        String metaStr = String(Variant(metadata));
        record[@"metadata"] = [NSString stringWithUTF8String:metaStr.utf8()];
        NSLog(@"[CloudSave] updateArchive: metadata updated: %s", metaStr.utf8().get_data());

        CKModifyRecordsOperation *op = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:@[record] recordIDsToDelete:nil];
        op.savePolicy = CKRecordSaveIfServerRecordUnchanged;
        NSLog(@"[CloudSave] updateArchive: submitting CKModifyRecordsOperation...");

        op.modifyRecordsCompletionBlock = ^(NSArray<CKRecord *> * _Nullable savedRecords, NSArray<CKRecordID *> * _Nullable deletedRecordIDs, NSError * _Nullable operationError) {
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
