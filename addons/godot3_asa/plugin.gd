tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("ASA", "res://addons/godot3_asa/asa.gd")
	print("✅ Godot3ASA plugin loaded")

func _exit_tree() -> void:
	remove_autoload_singleton("ASA")
	print("❌ Godot3ASA plugin unloaded")
