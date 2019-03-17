extends "base_line_editor.gd"

"""
Editor for VN dialogue lines
"""

var line_text = TextEdit.new()
var character_selector := OptionButton.new()

func load_characters():
	character_selector.clear()
	character_selector.add_item(tr("SCENE_EDITOR_NARRATOR"))
	character_selector.set_item_metadata(0, "")
	for character_name in GameManager.characters:
		var character = GameManager.characters[character_name]
		character_selector.add_item(character.name)
		character_selector.set_item_metadata(character_selector.get_item_count()-1, character_name)
		if character_name == line.character:
			character_selector.select(character_selector.get_item_count()-1)

func _ready():
	editable_area.add_child(line_text)
	line_text.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	rect_min_size = Vector2(0, 100)
	line_text.connect("text_changed", self, "on_text_changed")
	line_text.text = line.text
	load_characters()
	GameManager.connect("game_reloaded", self, "load_characters")
	character_selector.connect("item_selected", self, "on_character_selected")
	extra_buttons_container.add_child(character_selector)
func on_text_changed():
	line.text = line_text.text
	.update_line()
	
func on_character_selected(id):
	line.character = character_selector.get_item_metadata(id)
	.update_line()