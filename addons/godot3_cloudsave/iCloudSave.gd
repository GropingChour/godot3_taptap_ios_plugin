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
	if Engine.has_singleton(PLUGIN_NAME):
		singleton = Engine.get_singleton(PLUGIN_NAME)
		print(PLUGIN_NAME + " initialized")
	else:
		print(PLUGIN_NAME + " singleton not found")

func _process(delta):
	if not singleton:
		return
		
	var count = singleton.get_pending_event_count()
	while count > 0:
		var event = singleton.pop_pending_event()
		_dispatch_event(event)
		count -= 1

func _dispatch_event(event: Dictionary):
	var type = event.get("type", "")
	var data = event.get("data", {}) 
	var msg = event.get("msg", "")
	var uuid = event.get("uuid", "")
	
	match type:
		"create_archive_success":
			emit_signal("onCreateArchiveSuccess", JSON.print(data))
			emit_signal("onCreateArchiveCompleted", data, OK)
		"create_archive_failed":
			emit_signal("onCreateArchiveFailed", msg)
			emit_signal("onCreateArchiveCompleted", null, FAILED)
		
		"get_archive_list_success":
			# TapTap expects a JSON string containing the list?
			emit_signal("onGetArchiveListSuccess", JSON.print(data))
			emit_signal("onGetArchiveListCompleted", data.get("list", []), OK)
		"get_archive_list_failed":
			emit_signal("onGetArchiveListFailed", msg)
			emit_signal("onGetArchiveListCompleted", [], FAILED)
			
		"download_archive_success":
			emit_signal("onDownloadArchiveDataSuccess", JSON.print(data))
			emit_signal("onDownloadArchiveDataCompleted", data, OK)
		"download_archive_failed":
			emit_signal("onDownloadArchiveDataFailed", msg)
			emit_signal("onDownloadArchiveDataCompleted", null, FAILED)
			
		"update_archive_success":
			emit_signal("onUpdateArchiveSuccess", JSON.print(data))
			emit_signal("onUpdateArchiveCompleted", data, OK)
		"update_archive_failed":
			emit_signal("onUpdateArchiveFailed", msg)
			emit_signal("onUpdateArchiveCompleted", null, FAILED)
			
		"delete_archive_success":
			var ret_data = {"archiveUuid": uuid}
			emit_signal("onDeleteArchiveSuccess", JSON.print(ret_data))
			emit_signal("onDeleteArchiveCompleted", ret_data, OK)
		"delete_archive_failed":
			emit_signal("onDeleteArchiveFailed", msg)
			emit_signal("onDeleteArchiveCompleted", null, FAILED)
			
		"get_archive_cover_success":
			emit_signal("onGetArchiveCoverSuccess", data) 
			emit_signal("onGetArchiveCoverCompleted", data, OK)
		"get_archive_cover_failed":
			emit_signal("onGetArchiveCoverFailed", msg)
			emit_signal("onGetArchiveCoverCompleted", null, FAILED)

#region Public API
func createArchive(metadata: Dictionary, archiveFilePath: String, archiveCoverPath: String = "") -> void:
	if not singleton: return
	var absPath = ProjectSettings.globalize_path(archiveFilePath)
	var absCover = ""
	if archiveCoverPath != "":
		absCover = ProjectSettings.globalize_path(archiveCoverPath)
	singleton.createArchive(JSON.print(metadata), absPath, absCover)

func getArchiveList() -> void:
	if not singleton: return
	singleton.getArchiveList()

func downloadArchiveData(archiveUuid: String, archiveFileId: String, localArchivePath: String) -> void:
	if not singleton: return
	var absPath = ProjectSettings.globalize_path(localArchivePath)
	singleton.downloadArchiveData(archiveUuid, archiveFileId, absPath)

func updateArchive(archiveUuid: String, metadata: Dictionary, archiveFilePath: String, archiveCoverPath: String = "") -> void:
	if not singleton: return
	var absPath = ProjectSettings.globalize_path(archiveFilePath)
	var absCover = ""
	if archiveCoverPath != "":
		absCover = ProjectSettings.globalize_path(archiveCoverPath)
	singleton.updateArchive(archiveUuid, JSON.print(metadata), absPath, absCover)

func deleteArchive(archiveUuid: String) -> void:
	if not singleton: return
	singleton.deleteArchive(archiveUuid)

func getArchiveCover(archiveUuid: String, archiveFileId: String) -> void:
	if not singleton: return
	singleton.getArchiveCover(archiveUuid, archiveFileId)
#endregion
