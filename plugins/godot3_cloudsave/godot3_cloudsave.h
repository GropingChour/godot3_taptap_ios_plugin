#ifndef GODOT3_CLOUDSAVE_H
#define GODOT3_CLOUDSAVE_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#else
#include "core/object.h"
#endif

class Godot3CloudSave : public Object {
    GDCLASS(Godot3CloudSave, Object);
    
    static Godot3CloudSave *instance;
    List<Variant> pending_events;

public:
    static Godot3CloudSave *get_singleton();
    
    Godot3CloudSave();
    ~Godot3CloudSave();

    void _post_event(Variant p_event);
    int get_pending_event_count();
    Variant pop_pending_event();

    // Cloud Save API
    void createArchive(String metadataJson, String archiveFilePath, String archiveCoverPath);
    void getArchiveList();
    void downloadArchiveData(String archiveUuid, String archiveFileId, String localArchivePath);
    void updateArchive(String archiveUuid, String metadataJson, String archiveFilePath, String archiveCoverPath);
    void deleteArchive(String archiveUuid);
    void getArchiveCover(String archiveUuid, String archiveFileId);

    void showTip(String text);

    bool isAvailable();

protected:
    static void _bind_methods();
};

#endif
