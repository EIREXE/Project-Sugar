extends SugarEditorTab

"""
Editor for VN scenes
"""

var character : Dictionary
var code_viewer := TextEdit.new()

onready var hbox_container := get_node("VBoxContainer/HSplitContainer")
onready var main_container := get_node("VBoxContainer")
var editor_container := VBoxContainer.new()
var main_panel := Panel.new()
var layer_list_vbox := VBoxContainer.new()
var main_panel_vbox := VBoxContainer.new()

const SceneEditorTab := preload("res://system/debug/file_editor/scene_editor/scene_editor.gd")

const EDITABLE_FIELDS = {
	"name": {
		"name": "CHARACTER_EDITOR_CHARACTER_NAME"
	},
	"color": {
		"name": "CHARACTER_EDITOR_CHARACTER_NAME_TEXT_COLOR",
		"type_override": "color"
	}
}

var field_controls = {}

const SugarGraphicsLayerEditor = preload("res://system/debug/file_editor/character_editor/graphics_layer_editor.gd")

func _on_field_color_changed(color: Color, field):
	field_controls[field].line_edit.text = color.to_html()
	character[field] = color.to_html()

func _ready():
	var buttons_container := HBoxContainer.new()
	main_container.add_child(buttons_container)
	$VBoxContainer.move_child(buttons_container, 0)
	main_container.add_child(code_viewer)

	buttons_container.alignment = HBoxContainer.ALIGN_END
	
	var view_code_button = Button.new()
	view_code_button.hint_tooltip = tr("SCENE_EDITOR_HINT_VIEW_CODE")
	view_code_button.icon = ImageTexture.new()
	view_code_button.icon.load("res://system/debug/file_editor/icons/icon_script.svg")
	
	buttons_container.add_child(view_code_button)

	
	code_viewer.size_flags_vertical = SIZE_EXPAND_FILL
	code_viewer.visible = false
	code_viewer.syntax_highlighting = true
	code_viewer.show_line_numbers = true
	code_viewer.add_color_region("\"", "\"", Color("#ffcf7d34"))
	code_viewer.add_keyword_color("true", Color("#ffcc8242"))
	code_viewer.readonly = true

	view_code_button.connect("button_down", self, "_toggle_code_view")
	editor_container.add_child(hbox_container)
	main_panel.size_flags_vertical = SIZE_EXPAND_FILL
	main_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	
	main_panel.add_child(main_panel_vbox)
	
	main_panel_vbox.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	
	var scene_vbox = VBoxContainer.new()
	scene_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	scene_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	layer_list_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	layer_list_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	
	var layer_list_button_container = HBoxContainer.new()
	buttons_container.add_child(layer_list_button_container)
	
	layer_list_button_container.alignment = BoxContainer.ALIGN_END
	
	var add_layer_button = Button.new()
	add_layer_button.icon = ImageTexture.new()
	add_layer_button.icon.load("res://system/debug/file_editor/icons/icon_add.svg")
	add_layer_button.hint_tooltip = tr("CHARACTER_EDITOR_ADD_GRAPHICS_LAYER")
	
	add_layer_button.connect("button_down", self, "_on_add_graphics_layer")
	
	layer_list_button_container.add_child(add_layer_button)
	
	main_panel_vbox.margin_top = 10
	main_panel_vbox.margin_left = 10
	main_panel_vbox.margin_right = -10
func _toggle_code_view():
	code_viewer.visible = !code_viewer.visible
	#hbox_container.visible = !hbox_container.visible
	if code_viewer.visible:
		code_viewer.text = get_content()

func set_content(_content):
	content = _content
	character = JSON.parse(_content).result
	#add_fields()
	
func add_new_graphics_layer(layer_name):
	var layer = SugarGraphicsLayerEditor.new()
	layer.layer_data = character.graphics_layers[layer_name]
	layer.layer_internal_name = layer_name
	layer_list_vbox.add_child(layer)
	layer.character = get_character_internal_name()
	layer.connect("layer_changed", self, "_on_layer_changed")
	layer.connect("layer_internal_name_changed", self, "_on_layer_internal_name_changed")
	layer.connect("move_up", self, "_on_move_layer_up")
	layer.connect("move_down", self, "_on_move_layer_down")
	layer.connect("delete", self, "_on_delete_layer")
	
func swap_layers(idx1: int, idx2: int):
	var layer1_name = character.graphics_layers.keys()[idx1]
	var layer2_name = character.graphics_layers.keys()[idx2]
	var layer1_data = character.graphics_layers.values()[idx1]
	var layer2_data = character.graphics_layers.values()[idx2]
	
	var new_dict = {}
	var layers := character.graphics_layers as Dictionary
	
	for key in layers:
		if key == layer1_name:
			new_dict[layer2_name] = layer2_data
		elif key == layer2_name:
			new_dict[layer1_name] = layer1_data
		else:
			new_dict[key] = layers[key]
	character.graphics_layers = new_dict
	
func _on_move_layer_up(layer_idx: int):
	swap_layers(layer_idx, layer_idx-1)
func _on_move_layer_down(layer_idx: int):
	swap_layers(layer_idx, layer_idx+1)
func _on_delete_layer(layer_name: String):
	character.graphics_layers.erase(layer_name)
	
func _on_layer_changed(name, data):
	character.graphics_layers[name] = data
	
func _on_layer_internal_name_changed(idx: int, new_name: String):
	var layers := character.graphics_layers as Dictionary
	var new_dict = {}
	for i in range(layers.values().size()):
		var layer = layers.values()[i]
		if i == idx:
			new_dict[new_name] = layer
		else:
			var layer_name = layers.keys()[i]
			new_dict[layer_name] = layer
	character.graphics_layers = new_dict
func get_character_internal_name():
	return path.split("/")[-1].split(".json")[0]
	
func _on_add_graphics_layer():
	var data = SJSON.get_format_defaults("character_graphics_layer")
	var unique_name_found := false
	var i := 0
	var layer_name = "new layer"
	while character.graphics_layers.has(layer_name):
		i += 1
		layer_name = "new_layer" + str(i)
	character.graphics_layers[layer_name] = data
	add_new_graphics_layer(layer_name)
func _on_field_text_changed(value, field):
	character[field] = value
	if field_controls[field].has("color"):
		field_controls[field].color.color = Color(value)
func get_content():
	return JSON.print(character, "  ")
func _on_open_graphics_directory():
	var dir := Directory.new()
	var character_dir : String = "res://game/characters/" + get_character_internal_name()
	var result := dir.make_dir_recursive(character_dir)
	if result == OK:
		OS.shell_open(ProjectSettings.globalize_path(character_dir))
	else:
		push_error("Error creating directory %s" % character_dir)