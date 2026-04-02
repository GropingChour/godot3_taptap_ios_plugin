tool
extends EditorPlugin

func _enter_tree():
	add_autoload_singleton("AppleSignIn", "res://addons/apple_signin/AppleSignIn.gd")

func _exit_tree():
	remove_autoload_singleton("AppleSignIn")
