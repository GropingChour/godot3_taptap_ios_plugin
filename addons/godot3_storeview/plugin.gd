tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("StoreView", "res://addons/godot3_storeview/storeview.gd")
	print("✅ Godot3StoreView plugin loaded")

func _exit_tree() -> void:
	remove_autoload_singleton("StoreView")
	print("❌ Godot3StoreView plugin unloaded")
