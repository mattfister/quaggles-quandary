@tool
extends EditorPlugin

const BUTLER := "C:/Users/mattf/bin/butler/butler.exe"
const ITCH_TARGET := "freezebeam/quaggles-quandary:html5"

var _export_plugin: ButlerExportPlugin


func _enter_tree() -> void:
	_export_plugin = ButlerExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)


class ButlerExportPlugin extends EditorExportPlugin:
	var _export_dir := ""

	func _get_name() -> String:
		return "ButlerPush"

	func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
		if "web" in features:
			_export_dir = path.get_base_dir()
		else:
			_export_dir = ""

	func _export_end() -> void:
		if _export_dir.is_empty():
			return
		print("[ButlerPush] Pushing %s to %s ..." % [_export_dir, ITCH_TARGET])
		var output: Array[String] = []
		var exit_code := OS.execute(BUTLER, ["push", _export_dir, ITCH_TARGET], output, true)
		for line in output:
			print("[ButlerPush] ", line)
		if exit_code == 0:
			print("[ButlerPush] Upload complete.")
		else:
			push_error("[ButlerPush] butler exited with code %d" % exit_code)
