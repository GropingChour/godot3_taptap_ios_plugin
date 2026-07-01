extends Node

const PLUGIN_NAME := "Godot3CloudSave"
var singleton

#region Enum Definitions
# Cloned from TapTap if needed, or placeholder
enum CloudSaveResultCode {
	SUCCESS = 0
}
#endregion

#region Signals (Matching TapTap API)
signal onCloudSaveCallback(result_code)

signal onCreateArchiveSuccess(archive_data)
signal onCreateArchiveFailed(error_data)
signal onCreateArchiveCompleted(result, err)

signal onGetArchiveListSuccess(archives)
signal onGetArchiveListFailed(error_data)
signal onGetArchiveListCompleted(result, err)

signal onDownloadArchiveDataSuccess(archive_data)
signal onDownloadArchiveDataFailed(error_data)
signal onDownloadArchiveDataCompleted(result, err)

signal onUpdateArchiveSuccess(archive_data)
signal onUpdateArchiveFailed(error_data)
signal onUpdateArchiveCompleted(result, err)

signal onDeleteArchiveSuccess(archive_data)
signal onDeleteArchiveFailed(error_data)
signal onDeleteArchiveCompleted(result, err)

signal onGetArchiveCoverSuccess(cover_data)
signal onGetArchiveCoverFailed(error_data)
signal onGetArchiveCoverCompleted(result, err)
#endregion

func _ready():
	# Keep dispatching CloudKit events while the scene tree is paused (e.g. loading screen).
	pause_mode = Node.PAUSE_MODE_PROCESS
	_ensure_singleton()

func _ensure_singleton() -> bool:
	if singleton:
		return true
	if Engine.has_singleton(PLUGIN_NAME):
		singleton = Engine.get_singleton(PLUGIN_NAME)
		return true
	return false

func _process(delta):
	if not _ensure_singleton():
		return
		
	var count = singleton.get_pending_event_count()
	while count > 0:
		var event = singleton.pop_pending_event()
		if typeof(event) != TYPE_DICTIONARY:
			count -= 1
			continue
		_dispatch_event(event)
		count -= 1

func _normalize_archive(raw: Dictionary) -> Dictionary:
	var ret = raw.duplicate(true)
	if not ret.has("uuid") and ret.has("archiveUuid"):
		ret["uuid"] = ret["archiveUuid"]
	if not ret.has("modifiedTime") and ret.has("updatedTime"):
		ret["modifiedTime"] = ret["updatedTime"]
	return ret

func _dispatch_event(event: Dictionary):
	var type = event.get("type", "")
	var data = event.get("data", {}) 
	var msg = event.get("msg", "")
	var code = int(event.get("code", -1))
	var uuid = event.get("uuid", "")
	var err_message = {"message": msg, "code": code}
	var err_error = {"error": msg, "code": code}
	if code == 300001 or code == 300002:
		emit_signal("onCloudSaveCallback", code)
	
	match type:
		"create_archive_success":
			var archive_data = _normalize_archive(data)
			emit_signal("onCreateArchiveSuccess", archive_data)
			emit_signal("onCreateArchiveCompleted", archive_data, OK)
		"create_archive_failed":
			emit_signal("onCreateArchiveFailed", err_message)
			emit_signal("onCreateArchiveCompleted", null, ERR_BUG)
		
		"get_archive_list_success":
			var list_raw = data.get("archives", data.get("list", []))
			var archives = []
			for item in list_raw:
				if item is Dictionary:
					archives.append(_normalize_archive(item))
			var list_data = {"archives": archives, "count": int(data.get("count", archives.size()))}
			emit_signal("onGetArchiveListSuccess", list_data)
			emit_signal("onGetArchiveListCompleted", list_data, OK)
		"get_archive_list_failed":
			emit_signal("onGetArchiveListFailed", err_message)
			emit_signal("onGetArchiveListCompleted", null, ERR_BUG)
			
		"download_archive_success":
			var download_data = data
			emit_signal("onDownloadArchiveDataSuccess", download_data)
			emit_signal("onDownloadArchiveDataCompleted", download_data, OK)
		"download_archive_failed":
			emit_signal("onDownloadArchiveDataFailed", err_error)
			emit_signal("onDownloadArchiveDataCompleted", null, ERR_BUG)
			
		"update_archive_success":
			var update_data = _normalize_archive(data)
			emit_signal("onUpdateArchiveSuccess", update_data)
			emit_signal("onUpdateArchiveCompleted", update_data, OK)
		"update_archive_failed":
			emit_signal("onUpdateArchiveFailed", err_message)
			emit_signal("onUpdateArchiveCompleted", null, ERR_BUG)
			
		"delete_archive_success":
			var ret_data = data if (data is Dictionary and data.size() > 0) else {"archiveUuid": uuid, "uuid": uuid}
			emit_signal("onDeleteArchiveSuccess", ret_data)
			emit_signal("onDeleteArchiveCompleted", ret_data, OK)
		"delete_archive_failed":
			emit_signal("onDeleteArchiveFailed", err_message)
			emit_signal("onDeleteArchiveCompleted", null, ERR_BUG)
			
		"get_archive_cover_success":
			emit_signal("onGetArchiveCoverSuccess", data) 
			emit_signal("onGetArchiveCoverCompleted", data, OK)
		"get_archive_cover_failed":
			emit_signal("onGetArchiveCoverFailed", err_message)
			emit_signal("onGetArchiveCoverCompleted", null, ERR_BUG)

#region Public API
func createArchive(metadata: Dictionary, archiveFilePath: String, archiveCoverPath: String = "") -> void:
	if not _ensure_singleton(): return
	var absPath = ProjectSettings.globalize_path(archiveFilePath)
	var absCover = ""
	if archiveCoverPath != "":
		absCover = ProjectSettings.globalize_path(archiveCoverPath)
	singleton.createArchive(JSON.print(metadata), absPath, absCover)

func getArchiveList() -> void:
	if not _ensure_singleton():
		var err_message = {"message": "CloudSave singleton not available", "code": 300002}
		emit_signal("onGetArchiveListFailed", err_message)
		emit_signal("onGetArchiveListCompleted", null, ERR_BUG)
		return
	singleton.getArchiveList()

func downloadArchiveData(archiveUuid: String, archiveFileId: String, localArchivePath: String) -> void:
	if not _ensure_singleton(): return
	var absPath = ProjectSettings.globalize_path(localArchivePath)
	singleton.downloadArchiveData(archiveUuid, archiveFileId, absPath)

func updateArchive(archiveUuid: String, metadata: Dictionary, archiveFilePath: String, archiveCoverPath: String = "") -> void:
	if not _ensure_singleton(): return
	var absPath = ProjectSettings.globalize_path(archiveFilePath)
	var absCover = ""
	if archiveCoverPath != "":
		absCover = ProjectSettings.globalize_path(archiveCoverPath)
	singleton.updateArchive(archiveUuid, JSON.print(metadata), absPath, absCover)

func deleteArchive(archiveUuid: String) -> void:
	if not _ensure_singleton(): return
	singleton.deleteArchive(archiveUuid)

func getArchiveCover(archiveUuid: String, archiveFileId: String) -> void:
	if not _ensure_singleton(): return
	singleton.getArchiveCover(archiveUuid, archiveFileId)

func showTip(text: String) -> void:
	if not _ensure_singleton(): return
	singleton.showTip(text)
#endregion
