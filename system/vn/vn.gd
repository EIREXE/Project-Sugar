extends Control

"""
Visual novel game
"""

onready var background = get_node("Panel/Background")
onready var character_container = get_node("Panel/CharacterContainer")
onready var tie := get_node("Panel/StoryContainer")
# Lines that require waiting instead of being executed at once
const WAIT_LINES = ["text_line"]

var current_position = 0.0
var current_line = 0
var lines : Array = []

var visible_characters = {}

# Runs a scene from scene data
func run_scene(scene: Dictionary) -> void:
	set_process(false)
	lines = scene.lines
	current_line = 0
	_continue_parsing()

# Returns the current line's target text in the correct locale, and also applies settings such as auto_quote
func _get_current_line_text():
	var target_text : String
	# We try to get the current line based on the current locale, if this fails
	# we will just try to get it from the fallback locale, if this fails too we
	# will attempt to get the first line we can find, if there are no lines the
	# text will be ### LINE NOT FOUND ###
	if lines[current_line].text.has(TranslationServer.get_locale()):
		target_text = lines[current_line].text[TranslationServer.get_locale()]
	elif lines[current_line].text.has(ProjectSettings.get_setting("locale/fallback")):
		target_text = lines[current_line].text[ProjectSettings.get_setting("locale/fallback")]
	else:
		target_text = "### LINE NOT FOUND ###"
		if lines[current_line].text.size() > 0:
			target_text = lines[current_line].text.values()[0]
		push_error("Line translation not found uwu")
		
	if GameManager.game_info.auto_quote:
		target_text = "\"%s\"" % target_text
	return target_text

func change_background(background_filename: String):
	background.texture = ImageTexture.new()
	background.texture.load("res://game/backgrounds/" + background_filename)

# Shows a character
func change_character_visibility(line: Dictionary):
	if GameManager.characters.has(line.character):
		var character = GameManager.characters[line.character]
		if visible_characters.has(line.character):
			visible_characters[line.character].queue_free()
		if line.show:
			if character.graphics_layers.has(line.layer):
				var main_node = Control.new()
				main_node.size_flags_horizontal = SIZE_EXPAND_FILL
				for texture_path in character.graphics_layers[line.layer].graphics:
					var path = "res://game/characters/%s/%s" % [line.character, texture_path]
					var texture_rect := TextureRect.new()
					texture_rect.texture = ImageTexture.new()
					texture_rect.expand = true
					texture_rect.texture.load(path)
					texture_rect.set_anchors_and_margins_preset(Control.PRESET_WIDE)
					texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					texture_rect.size_flags_horizontal = SIZE_EXPAND_FILL

					main_node.add_child(texture_rect)
				character_container.add_child(main_node)
				visible_characters[line.character] = character_container
			else:
				push_error("Character %s doesn't have graphics layer %s" % [line.character, line.layer])
	else:
		push_error("Character %s not found" % line.character)

func show_current_line_text():
	tie.show_text(_get_current_line_text(), lines[current_line].character)

# Executes a non-text line
func _execute_line(line):
	match line.__format:
		"text_line":
			show_current_line_text()
		"background_change_line":
			change_background(line.background)
		"change_character_visibility_line":
			change_character_visibility(line)

# Continues parsing lines
func _continue_parsing():
	for line_i in range(current_line, lines.size(), 1):
		current_line = line_i
		_execute_line(lines[line_i])
		if lines[line_i].__format in WAIT_LINES:
			break

func _on_text_line_skipped():
	if current_line != lines.size()-1:
		if current_line + 1 < lines.size():
			current_line += 1
		_continue_parsing()

func _ready():
	set_process(false)
	tie.connect("line_skipped", self, "_on_text_line_skipped")