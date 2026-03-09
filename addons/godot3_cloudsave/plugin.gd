tool
extends EditorPlugin

func _enter_tree():
	# Add the singleton to autoload? Or just let user do it?
	# Usually ios plugins rely on the engine singleton being available.
	# But the GDScript wrapper needs to be loaded to use the high-level API.
	add_autoload_singleton("ICloudSave", "res://addons/godot3_cloudsave/iCloudSave.gd")

func _exit_tree():
	remove_autoload_singleton("ICloudSave")
