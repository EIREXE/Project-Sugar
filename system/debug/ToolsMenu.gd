extends WindowDialog

"""
Development tools menu, opened with F10
"""

const SugarToolWindow = preload("ToolWindow.gd")

var button_container = VBoxContainer.new()

var TOOLS = [
		{
			"name": tr("TOOLS_WINDOW_JSON_EDITOR"),
			"path": "res://system/debug/file_editor/editor.tscn"
		}
	]

var open_tools = {
	
	}

func _ready():
	window_title = tr("TOOLS_WINDOW_TITLE")
	add_child(button_container)
	button_container.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	for tool_info in TOOLS:
		var button := Button.new()
		button.text = tool_info["name"]
		button.connect("button_up", self, "_run_tool", [tool_info["path"]])
		button_container.add_child(button)
	
	button_container.add_child(HSeparator.new())
	
	var run_main_button = Button.new()
	run_main_button.text = tr("TOOLS_WINDOW_RUN_MAIN_SCENE")
	run_main_button.connect("button_down", GameManager, "run_vn_scene_from_file", ["res://game/scenes/main.json"])
	run_main_button.connect("button_down", self, "hide")
	button_container.add_child(run_main_button)
	
	var game_reload_button = Button.new()
	game_reload_button.text = tr("TOOLS_WINDOW_RELOAD_GAME")
	game_reload_button.connect("button_down", GameManager, "reload_game")
	game_reload_button.connect("button_down", self, "hide")
	button_container.add_child(game_reload_button)
	
func _run_tool(tool_path: String) -> void:
	if open_tools.has(tool_path):
		open_tools[tool_path].show()
	else:
		var scene = load(tool_path)
		var tool_window = SugarToolWindow.new() as WindowDialog
		var tool_instance = scene.instance()
		add_child(tool_window)
		tool_window.add_child(tool_instance)
		# HACK to prevent window from being hidden when clicked away, while still making use of popup_centered_ratio
		tool_window.popup_centered_ratio()
		tool_window.hide()
		tool_window.show()
		open_tools[tool_path] = tool_window
	
func _input(event):
	if OS.is_debug_build():
		if Input.is_action_just_released("open_debug"):
			var size = Vector2(ProjectSettings.get_setting("display/window/size/width"), ProjectSettings.get_setting("display/window/size/height"))
			get_tree().set_screen_stretch(SceneTree.STRETCH_MODE_DISABLED, SceneTree.STRETCH_ASPECT_KEEP_HEIGHT, size)
			popup_centered_ratio(0.25)