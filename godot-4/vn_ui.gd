extends Node2D

# Copyright (c) 2023 Lars Rune Præstmark (or "SeaLiteral" as I call myself on some websites)
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


# Declare member variables here. Examples:
# Start and end of the longest possible chapter
const CHAPTER_STARTED = 0
const CHAPTER_ENDED = 65536

var released_change = 100.0
var released_limit = 0.0
var vn_position = 0
var vn_chapter = null
var vn_anim_dict = {}
var vn_text = ["."]
var vn_defaults = {
	"min_font_size": 8,
	"max_font_size": 100
}
var vn_configuration = {
	"text_language": "en",
	"text_cps": 50,
	"font_size": 50,
	"scroll_sensitivity": 4.9,
	"voice_volume": 100,
	"text_mode": "CHARACTERS",
	"skip_delay": 0.25,
	"auto_delay": 1.0,
	"auto_cps": 15.0,
	"self_voicing": 0
}

var qm_buttons = {
	"back": go_backwards,
	"skip": toggle_skipping,
	"auto": toggle_auto,
	"history": create_history_screen_from_game,
	"menus": toggle_menu
}

var known_text_modes = ["CHARACTERS", "INSTANT", "WORDS"]
var vn_previous_text_mode = "CHARACTERS"
var vn_theme = null
var vn_sorted_configuration = []
var vn_text_linebreaks = []
var vn_showhide_dict = {}
var quick_menu = null
var game_state = "MENU"
var text_font = null
var highlight_group = "NONE"
var scroll_speed = 5
var fast_scroll_speed = 100
var vn_reversible_animations = ['camera_up', 'camera_down']
var vn_chapter_positions = {}
var vn_chapter_names = {}
var vn_first_chapter = 'intro'
var vn_savedata_filename = "user://sheepmo.txt"
var vn_running_buttons = {}

var vn_screen_text = []
var vn_screen_highlight = -1

var text_shown_amount = 0.0
var text_scrolled_amount = 0.0
var text_showing = ""
var text_box_width = 1600.0
var text_default_size = 0
var vn_language_changed = true
var input_mouse_undoing = 0
var input_mouse_undone = 0.0
var input_vertical = 0
var input_horizontal = 0
var input_skipping = false
var next_skip_delay = 0.0
var input_autoing = false
var next_auto_delay = 0.0

var vn_tts=[]

var ui_data = {}

var ui={}
var vn_sprites = {}

func stop_highlighting():
	#highlight_group = "LEAVE"
	highlight_group = "NONE"
	$dummy_control/TextureButton.grab_focus()

func get_file_text(file_name):
	var read_contents = ""
	if not FileAccess.file_exists(file_name):
		return null
	var read_file = FileAccess.open (file_name, FileAccess.READ)
	read_contents = ""
	while read_file.get_position() < read_file.get_length():
		var found_line = read_file.get_line()
		read_contents += found_line +"\n"
	read_file.close()
	return (read_contents)

func get_string_linebreaks(text, width):
	var current_line = ""
	var found_breaks = []
	var character_count=0
	var last_space = -1
	for character in text:
		if (character=='\n'):
			found_breaks.append(character_count)
			current_line = ""
		elif (character==' '):
			var current_pixel_length = text_font.get_string_size(current_line+' ').x
			if (current_pixel_length>width):
				found_breaks.append(last_space)
				current_line = ""
			else:
				current_line += ' '
				last_space = character_count
		#elif (not ' ' in current_line):
		#	pass # FIXME: handle words that don't fit
		else:
			current_line += character
		character_count += 1
	var current_pixel_length = text_font.get_string_size(current_line).x
	if (current_pixel_length>width):
		found_breaks.append(last_space)
	return found_breaks

func load_vn_script(target_language):
	var vn_contents = get_file_text("res://vn_script.txt")
	if vn_contents == null:
		vn_text = [tr('ERROR_NO_SCRIPT')]
		vn_text_linebreaks=[[]]
		return
	vn_text = []
	vn_text_linebreaks = []
	vn_anim_dict = {}
	vn_showhide_dict = {}
	vn_chapter_positions = {}
	vn_chapter_names = {}
	var last_text = ""
	var last_language=""
	var last_anim = "camera_idle"
	for vn_line in vn_contents.split("\n"):
		if ((vn_line=="") and (last_text!="")):
			vn_text.append(last_text)
			vn_text_linebreaks.append(get_string_linebreaks(last_text, text_box_width))
			last_text = ""
		elif vn_line.begins_with("@"):
			var line_words = vn_line.split(" ")
			if line_words[0]=="@anim":
				# print (len(vn_text))
				var next_animation = "camera_idle"
				if len(line_words)>1:
					var animation_name = line_words[1]
					if animation_name == "camera_down":
						next_animation="camera_liedown"
					vn_anim_dict[len(vn_text)]=[animation_name, next_animation, last_anim]
					last_anim = next_animation
			elif line_words[0] in ["@show", "@hide"]:
				if len(line_words)==2:
					vn_showhide_dict[len(vn_text)]=line_words
			if line_words[0]=="@chapter":
				if (len(line_words)>1):
					vn_chapter_positions[line_words[1]]=len(vn_text)
					vn_chapter_names[len(vn_text)]=line_words[1]
		elif (vn_line.begins_with(target_language+"=")):
			last_text = vn_line.substr(3)
			last_language=target_language
		elif (len(vn_line)>3):
			if vn_line[2]=='=':
				last_language=vn_line.split('=')[0]
				if (last_text!=""):
					vn_text.append(last_text)
					vn_text_linebreaks.append(get_string_linebreaks(last_text, text_box_width))
				last_text = ""
			elif ((last_language==target_language) and (vn_line.begins_with("   "))):
				last_text += "\n"+(vn_line.substr(3))
		elif vn_line=="":
			pass
	if last_text!="":
		vn_text.append(last_text)
		vn_text_linebreaks.append(get_string_linebreaks(last_text, text_box_width))

func get_initial_language():
	if ('text_language' in vn_configuration):
		var found_language = vn_configuration['text_language']
		#print('there is a language: '+str(found_language))
		if found_language in ['en', 'da', 'es']:
			set_language(found_language)
			return
	else:
		pass#print('no language')
	vn_configuration["text_language"] = TranslationServer.get_locale()
	var got_language = false
	for language_code in ["en", "da", "es"]:
		if vn_configuration["text_language"].begins_with(language_code):
			set_language(language_code)
			got_language = true
	if not got_language:
		set_language("en")

func reposition_ui(new_size):
	if (new_size<vn_defaults['min_font_size']):
		new_size = vn_defaults['min_font_size']
	elif (new_size>vn_defaults['max_font_size']):
		new_size = vn_defaults['max_font_size']
	if (new_size<=50):
		ui['vn_text_container'].set_position(ui['vn_textbox_base_position'])
		ui['vn_text_container'].size=ui['vn_textbox_base_size']
		ui['vn_textbox'].set_position(ui['vn_textbox_inner_position'])
		ui['vn_textbox'].size=ui['vn_textbox_inner_size']
		return
	var position_difference = (new_size-50)
	ui['vn_text_container'].set_position(ui['vn_textbox_base_position']- Vector2(0.0, position_difference))
	ui['vn_text_container'].size=ui['vn_textbox_base_size']+Vector2(0.0, position_difference)
	ui['vn_textbox'].set_position(ui['vn_textbox_inner_position']-Vector2(0.0, position_difference*0.3))
	ui['vn_textbox'].size=ui['vn_textbox_inner_size']+Vector2(0.0, position_difference*0.3)

func perhaps_read(text, forced_speech=false):
	if ((vn_configuration['self_voicing']==0) and not forced_speech):
		return
	if (len(vn_tts)==0):
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(tr(text), vn_tts[0])

# Called when the node enters the scene tree for the first time.
func _ready():
	#print('test dictionary', typeof(test_dictionary), ", " , TYPE_DICTIONARY)
	ui['animation_camera']=$camera_animation_player
	ui['vn_hud']=$camera_animation_player/Camera2D/Control
	ui['vn_quickmenu']=$camera_animation_player/Camera2D/Control/HBoxContainer
	ui['vn_text_container']=$camera_animation_player/Camera2D/Control/ColorRect
	ui['vn_textbox']=$camera_animation_player/Camera2D/Control/ColorRect/RichTextLabel
	ui['menu_box']=$camera_animation_player/Camera2D/Outer_control/menu_scroll/menu_box
	ui['screen_textbox']=$camera_animation_player/Camera2D/Outer_control/ColorRect/textbox
	ui['screen_box']=$camera_animation_player/Camera2D/Outer_control
	ui['vn_textbox_base_position'] = ui['vn_text_container'].get_transform().get_origin()
	ui['vn_textbox_base_size']=ui['vn_text_container'].size
	ui['vn_textbox_inner_position'] = ui['vn_textbox'].get_transform().get_origin()
	ui['vn_textbox_inner_size']=ui['vn_textbox'].size
	vn_sprites['witch']=$"landskab/sprites/Node2D/test-sprite"
	vn_sprites['animation_player']=$landskab/sprites
	vn_sprites['content']=$landskab/sprites/Node2D
	vn_configuration['text_cps']=50.0
	vn_configuration['font_size']=50
	vn_configuration['game_title']='Sheep Monologue'
	vn_configuration['game_version']=1.3
	vn_configuration['scroll_sensitivity']=4.9
	vn_configuration['voice_volume']=100
	vn_configuration['text_mode']="CHARACTERS"
	var actual_config = get_file_text(vn_savedata_filename)
	if actual_config==null:
		actual_config = """# Metadata
game_title=Sheep Monologue
game_version=1.3
# Settings and unlocks:
text_cps=50
text_mode=CHARACTERS
font_size=50
scroll_sensitivity=4.9
voice_volume=100"""
	decode_settings(actual_config)
	text_font = $camera_animation_player/Camera2D/Control/ColorRect/RichTextLabel.get_theme_default_font()
	#text_font = ui['vn_textbox'].normal_font
	vn_theme = load("res://default_theme.tres")
	vn_theme.default_font_size = vn_configuration['font_size']
	text_default_size=50
	if not 'text_language' in vn_configuration:
		get_initial_language()
	else:
		set_language(vn_configuration['text_language'])
	# TODO: Separate quick menu and add tooltips
	quick_menu = ui['vn_quickmenu']
	for button_name in ["back", "skip@run", "auto", "history", "menus"]:
	# ["back", "auto", "skip", "history", "menus"]:
		var has_running_state=false
		if button_name.ends_with('@run'):
			button_name=button_name.split('@')[0]
			has_running_state=true
		var new_button = TextureButton.new()
		new_button.name = "qm_"+button_name
		var texture_normal = load("res://gui/"+button_name+".png")
		if has_running_state:
			var texture_running = load("res://gui/"+button_name+"-running.png")
			vn_running_buttons[button_name]=[new_button, texture_normal, texture_running]
		new_button.texture_normal = texture_normal
		new_button.material = load ("res://button-material.tres")
		if button_name in qm_buttons:
			new_button.connect("pressed", qm_buttons[button_name])
		new_button.texture_focused = load("res://gui/"+button_name+"-focus.png")
		quick_menu.add_child(new_button)
	# text_font.get_string_size()
	ui['animation_camera'].play("camera_idle")
	animate_position(1)
	show_menu()

func decode_settings(text):
	vn_sorted_configuration = []
	for config_line in text.split('\n'):
		#print("Handling line: "+config_line)
		if (config_line.begins_with('#')):
			vn_sorted_configuration.append(config_line)
			continue
		elif (  (not '=' in config_line) or (config_line.begins_with("="))):
			continue
		var equal_position = config_line.find('=')
		var first_part = config_line.substr(0, equal_position)
		vn_sorted_configuration.append(first_part)
		var last_part = config_line.substr(equal_position+1)
		#print('first '+first_part+' last '+last_part+ "middle: "+str(equal_position))
		var digits = 0
		var non_digits = 0
		var decode_result = last_part
		for character in last_part:
			if character in '0123456789.':
				digits += 1
			else:
				non_digits += 1
		if ((digits>0) and (non_digits==0)):
			if (last_part.count ('.')==0):
				decode_result = int(last_part)
			elif (last_part.count ('.')==1):
				decode_result = float(last_part)
		vn_configuration[first_part] = decode_result
	if 'font_size' in vn_configuration:
		reposition_ui(vn_configuration['font_size'])
	if 'text_mode' in vn_configuration:
		vn_previous_text_mode = vn_configuration['text_mode']
		if (vn_configuration['text_mode'] not in known_text_modes):
			vn_configuration['text_mode'] = "CHARACTERS"
			# print("unknown text mode when decoding settings")

func save_settings():
	if (vn_configuration['game_version']<1.3):
		vn_configuration['game_version']=1.3
	var stored_text_mode = vn_configuration['text_mode']
	if (vn_configuration['text_mode']!=vn_previous_text_mode):
		vn_configuration['text_mode']=vn_previous_text_mode
	var to_write = ''
	for i in vn_configuration:
		if (not i in vn_sorted_configuration):
			vn_sorted_configuration.append(i)
	for i in vn_sorted_configuration:
		if i.begins_with('#'):
			to_write += str(i) + '\n'
		elif i in vn_configuration:
			to_write += i + '=' + str(vn_configuration[i]) + '\n'
	if (vn_configuration['text_mode'] not in known_text_modes):
		vn_configuration['text_mode'] = stored_text_mode
		#vn_previous_text_mode = stored_text_mode
	if get_file_text(vn_savedata_filename)==to_write:
		return
	var save_file = FileAccess.open(vn_savedata_filename, FileAccess.WRITE)
	save_file.store_string(to_write)
	save_file.close()
		

func delay_action():
	if (released_change<=released_limit):
		released_change = 0.0
		return true
	released_change = 0.0
	return false

func create_button(button_text, button_callback, button_hint, button_meta=null):
	var menu_box = ui['menu_box']
	var new_button = Button.new()
	new_button.text = button_text
	new_button.tooltip_text = button_hint
	if (button_meta!=null):
		new_button.connect("pressed", button_callback.bind(button_meta))
		#new_button.connect ("pressed", self, button_callback, button_meta)
	else:
		new_button.connect ("pressed", button_callback)
	menu_box.add_child(new_button)
	return new_button
func create_label(label_text):
	var menu_box = ui['menu_box']
	var new_label = Label.new()
	new_label.text = label_text
	new_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	menu_box.add_child(new_label)
	return new_label

func create_separator():
	var menu_box = ui['menu_box']
	var new_separator = HSeparator.new()
	menu_box.add_child(new_separator)

func create_slider(label_text, initial_value,
		from=0, to=100, step=1, to_change=[],
		slider_callback=update_config_labels,
		new_hint=null):
	var value_text = tr(label_text).replace('%f', str(initial_value))
	var new_label = create_label(value_text)
	var menu_box = ui['menu_box']
	var new_slider = HSlider.new()
	new_slider.min_value = from
	new_slider.max_value = to
	new_slider.step = step
	new_slider.value = initial_value
	new_slider.connect("value_changed", slider_callback.bind(to_change))
	if new_hint:
		new_slider.tooltip_text = new_hint
	menu_box.add_child(new_slider)
	return [new_slider, new_label]

func update_config_labels(amount_set=null, to_change=[]):
	var change_label=null
	var change_objects=[]
	if (len(to_change)>=1):
		change_label = to_change[0]
		vn_configuration[change_label]=amount_set
		# print("font? "+str(typeof(text_font))+" "+str(TYPE_OBJECT))
	if (len(to_change)>=2):
		change_objects = to_change[1]
	for pair in change_objects:
		var larger_object = pair[0]
		var object_part = pair[1]
		if (typeof(larger_object)==TYPE_DICTIONARY):
			larger_object[object_part]=amount_set
		else:
			larger_object.set(object_part, amount_set)
	if ((change_label=="text_cps") and ('text_cps' in ui_data)):
		vn_configuration["text_cps"] = ui_data['text_cps'][0].value
	for i in ui_data:
		print (i)
		ui_data[i][1].text = tr('CM_'+(i.to_upper())).replace('%f', str(vn_configuration[i]))
	if change_label=='font_size':
		vn_theme.default_font_size = amount_set
		reposition_ui(amount_set)

func create_main_menu():
	destroy_menu()
	if vn_position!=0:
		create_button("MM_CONTINUE", hide_menu, "MH_CONTINUE")
		create_button("MM_HISTORY", create_history_screen_from_menu, "MH_HISTORY")
		create_button("MM_RESTART", start_vn, "MH_RESTART")
	else:
		create_button("MM_PLAY", start_vn, "MH_PLAY")
	create_button("MM_LOAD", create_load_menu, "MH_LOAD")
	create_button("MM_LANGUAGE", create_language_menu, "MH_LANGUAGE")
	create_button("MM_CONFIG", create_config_menu, "MH_CONFIG")
	create_button("MM_CREDITS", create_credits_screen, "MH_CREDITS")
	create_button("MM_HELP", create_help_screen, "MH_HELP")
	game_state = "MENU"
	ui['screen_box'].show()
	ui["vn_hud"].hide()

func create_language_menu():
	destroy_menu()
	create_button("English", set_language, "English", 'en')
	create_button("Dansk", set_language, "Danish", 'da')
	create_button("Español", set_language, "Spanish", 'es')
	create_button("SM_BACK_TO_MENU", create_main_menu, "SH_BACK_TO_MENU")
	game_state = "LANGUAGE_MENU"
	ui['screen_box'].show()
	ui["vn_hud"].hide()

func create_load_menu():
	destroy_menu()
	create_label("LM_PICK_CHAPTER_LABEL")
	for chapter in vn_chapter_positions:
		if ((('chapter:'+chapter) in vn_configuration) or
			(chapter==vn_first_chapter)):
			create_button('CHAPTER_'+chapter, conditionally_load_chapter, "", [chapter])
	create_separator()
	create_button("SM_BACK_TO_MENU", create_main_menu, "SH_BACK_TO_MENU")
	game_state = "LOAD_MENU"
	ui['screen_box'].show()
	ui["vn_hud"].hide()

func conditionally_load_chapter(chapter_data):
	var chapter_name = chapter_data[0]
	print (chapter_name)
	if chapter_name in vn_chapter_positions:
		start_vn()
		vn_position = vn_chapter_positions[chapter_name]
		vn_chapter = null
		animate_position(0)

func create_accessibility_menu(from_game=true):
	destroy_menu()
	ui_data ['font_size'] = create_slider(
		"CM_FONT_SIZE", vn_configuration['font_size'],
		vn_defaults['min_font_size'], vn_defaults['max_font_size'],
		1, ['font_size', [[vn_theme, 'text_default_size']]])
	create_separator()
	ui_data ['scroll_sensitivity'] = create_slider(
		"CM_SCROLL_SENSITIVITY", vn_configuration["scroll_sensitivity"],
		0, 5, 0.1, ['scroll_sensitivity'],
		update_config_labels,
		'Used for mouse "rollback"\nand "rollforward"')
	create_separator()
	if from_game:
		create_button("SM_BACK_TO_MENU", hide_menu, "SH_BACK_TO_MENU")
	else:
		create_button("SM_BACK_TO_MENU", create_config_menu, "SH_BACK_TO_MENU")###
	game_state = "CONFIG_MENU"
	ui['screen_box'].show()


func create_audio_menu():
	destroy_menu()
	ui_data ['voice_volume'] = create_slider(
		"CM_VOICE_VOLUME", vn_configuration["voice_volume"],
		0, 100, 1, ['voice_volume'])
	create_separator()
	create_button("SM_BACK_TO_MENU", create_config_menu, "SH_BACK_TO_MENU")
	game_state = "AUDIO_MENU"
	ui['screen_box'].show()


func create_text_menu():
	destroy_menu()
	ui_data ['text_cps'] = create_slider(
		"CM_TEXT_CPS", vn_configuration["text_cps"],
		0, 100, 0.1, ['text_cps'])
	create_separator()
	ui_data ['auto_delay'] = create_slider(
		"CM_AUTO_DELAY", vn_configuration["auto_delay"],
		0, 20, 0.1, ['auto_delay'])
	ui_data ['auto_cps'] = create_slider(
		"CM_AUTO_CPS", vn_configuration["auto_cps"],
		1, 80, 0.1, ['auto_cps'])
	create_separator()
	ui_data ['skip_delay'] = create_slider(
		"CM_SKIP_DELAY", vn_configuration["skip_delay"],
		1, 10, 0.1, ['skip_delay'])
	create_separator()
	create_button("SM_BACK_TO_MENU", create_config_menu, "SH_BACK_TO_MENU")
	game_state = "TEXT_MENU"
	ui['screen_box'].show()
	ui["vn_hud"].show() # for previewing stuff ######

func create_config_menu():
	destroy_menu()
	create_button("CM_TEXT", create_text_menu, "MH_TEXT")
	create_button("CM_ACCESSIBILITY", create_accessibility_menu,
					"MH_ACCESSIBILITY", false)
	#create_button("CM_AUDIO", create_audio_menu, "MH_AUDIO")
	create_separator()
	create_button("SM_BACK_TO_MENU", apply_settings, "SH_BACK_TO_MENU")
	game_state = "CONFIG_MENU"
	ui['screen_box'].show()
	ui["vn_hud"].hide()

func set_language (language_code):
	TranslationServer.set_locale(language_code)
	load_vn_script(language_code)
	vn_configuration["text_language"] = language_code
	vn_tts = DisplayServer.tts_get_voices_for_language(language_code)
	vn_language_changed = true
	# create_main_menu()

func apply_settings():
	load_vn_script(vn_configuration["text_language"])
	create_main_menu()

func create_text_screen(screen_text, stay_in_menu):
	destroy_menu()
	# var menu_box = $camera_animation_player/Camera2D/Outer_control/menu_box
	show_menu_backgrounds()
	vn_screen_text = []
	vn_screen_highlight = -1
	for i in(screen_text.split("\n\n")):
		var praf = i
		for format_mark in ['[color=blue]', '[color=#800]', '[/color]']:
			praf = praf.replace(format_mark, '')
		praf = praf.replace('\n','.\n').replace(':.\n',':\n')
		for number in '0123456789':
			praf = praf.replace('.'+number, ' '+tr('VOICE_DECIMAL_POINT')+' '+number)
		vn_screen_text.append(praf)
	var use_label = ui['screen_textbox']
	use_label.bbcode_enabled = true
	use_label.text = screen_text
	use_label.show()
	if stay_in_menu:
		create_button("SM_BACK_TO_MENU", create_main_menu, "SH_BACK_TO_MENU")
	else:
		create_button("SM_BACK_TO_MENU", hide_menu, "SH_BACK_TO_GAME")

func create_credits_screen():
	var screen_text = get_file_text ("res://credits_"+vn_configuration["text_language"]+".txt")
	if screen_text==null:
		screen_text = tr("ERROR_SCREEN_TEXT_NOT_FOUND")
	create_text_screen(screen_text, true)
	game_state = "ABOUT_SCREEN"

func create_help_screen():
	var screen_text = get_file_text ("res://controls_"+vn_configuration["text_language"]+".txt")
	if screen_text==null:
		screen_text = tr("ERROR_SCREEN_TEXT_NOT_FOUND")
	create_text_screen(screen_text, true)
	game_state = "HELP_SCREEN"

func create_history_screen(stay_in_menu):
	var history_text = ""
	var line_count=0
	for vn_line in vn_text:
		if line_count<vn_position:
			history_text += vn_line + "\n\n"
		else:
			break
		line_count+=1
	create_text_screen(history_text, stay_in_menu)

func create_history_screen_from_game():
	create_history_screen(false)
	game_state = "HISTORY_SCREEN"

func create_history_screen_from_menu():
	create_history_screen(true)
	game_state = "HISTORY_FROM_MENU_SCREEN"

func start_vn():
	vn_position = 0
	hide_menu()
	vn_chapter = null
	animate_position(1)

func destroy_menu():
	ui_data = {}
	var menu_box = ui['menu_box']
	for old_button in menu_box.get_children():
		menu_box.remove_child(old_button)
	var about_label = ui['screen_textbox']
	about_label.hide()
	stop_highlighting()
	save_settings()
	if (vn_language_changed==true):
		animate_position(1)

func animate_position(animate_direction):
	vn_language_changed = false
	if vn_position in vn_showhide_dict:
		var showhide_action = vn_showhide_dict[vn_position]
		if showhide_action[0]=="@show":
			vn_sprites['content'].show()
			vn_sprites['animation_player'].play('witch_idle')
		elif showhide_action[0]=="@hide":
			vn_sprites['animation_player'].stop()
			vn_sprites['content'].hide()
	if vn_position in vn_chapter_names:
		var chapter_name = str(vn_chapter_names[vn_position])
		var chapter_reference = 'chapter:'+chapter_name
		if not chapter_reference in vn_configuration:
			vn_configuration[chapter_reference] = CHAPTER_STARTED
		if ((animate_direction==1) and (vn_chapter!=null)):
			var previous_chapter_reference='chapter:'+vn_chapter
			vn_configuration[previous_chapter_reference] = CHAPTER_ENDED
		vn_chapter = chapter_name
	else:
		var chapter_reference = 'chapter:'+vn_chapter
		if (vn_configuration[chapter_reference] != CHAPTER_ENDED):
			var adjusted_position = (vn_position-(vn_chapter_positions[vn_chapter])+
										CHAPTER_STARTED)
			if (vn_configuration[chapter_reference]<adjusted_position):
				vn_configuration[chapter_reference]=adjusted_position
	var to_play = null
	var play_backwards = false
	if (animate_direction==-1):
		if vn_position<len(vn_text)-1:
			if (vn_position+1) in vn_anim_dict:
				to_play = vn_anim_dict[vn_position+1][2]
				if vn_anim_dict[vn_position+1][0] in vn_reversible_animations:
					to_play = vn_anim_dict[vn_position+1][0]
					play_backwards = true
	if vn_position in vn_anim_dict:
		to_play = vn_anim_dict[vn_position][0]
	if to_play!=null:
		if play_backwards:
			ui['animation_camera'].play_backwards(to_play)
		else:
			ui['animation_camera'].play(to_play)
	text_showing = vn_text[vn_position]
	text_shown_amount = 0.0
	if (animate_direction!=1):
		text_shown_amount = len(text_showing)+0.1
	if (game_state=='GAME'):
		perhaps_read(text_showing)

func maybe_stop_skipping():
	if should_stop_skipping():
		stop_skipping()

func should_stop_skipping():
	var chapter_status = vn_configuration['chapter:'+vn_chapter]
	var relative_position = (vn_position-vn_chapter_positions[vn_chapter]+
								CHAPTER_STARTED)
	if (chapter_status>relative_position):
		return false
	else:
		return true

func go_forwards(allow_delay=true, skip_animation=false):
	if (delay_action() and allow_delay):
		return
	vn_position += 1
	# print ("chapter: "+vn_chapter)
	if (vn_position>=len(vn_text)):
		# print("end of text")
		vn_position = 0
		var previous_chapter_reference='chapter:'+vn_chapter
		vn_configuration[previous_chapter_reference] = CHAPTER_ENDED
		vn_chapter = null
		#animate_position(1)
		hide_menu()
		show_menu()
	else:
		if skip_animation:
			animate_position(2)
		else:
			animate_position(1)
		maybe_stop_skipping()
	stop_highlighting()

func advance_text_outer():
	if (text_shown_amount>(len(text_showing))):
		go_forwards()
	else:
		text_shown_amount = len(text_showing)+0.1

func go_backwards():
	if delay_action():
		return
	vn_position -= 1
	if (vn_position<0):
		vn_position = 0
	animate_position(-1)
	stop_highlighting()

func toggle_skipping():
	# XYZ: This function doesn't always get called
	#  when the button gets clicked.
	#  This might mean the engine thinks two single clicks
	#  are one double click, but I can't find any
	#  official explanation of it.
	#  I hope to find a solution, but for now
	#  all I can do here is document it.
	if (input_skipping):
		stop_skipping()
	else:
		start_skipping()
	maybe_stop_skipping()

func toggle_auto():
	input_autoing = not input_autoing
	if (not input_autoing):
		stop_autoing()
	else:
		stop_skipping()

func toggle_selfvoice():
	if vn_configuration['self_voicing']==1:
		perhaps_read('TTS stopped.', true)
		vn_configuration['self_voicing'] = 0
	else:
		perhaps_read('TTS started.', true)
		vn_configuration['self_voicing'] = 1
	print("Toggled speech to "+str(vn_configuration['self_voicing']))

func start_skipping():
	input_skipping = true
	var skip_buttons = vn_running_buttons['skip']
	#skip_buttons[0].texture_normal = skip_buttons[2]
	stop_autoing()

func stop_skipping():
	input_skipping = false
	var skip_buttons = vn_running_buttons['skip']
	#skip_buttons[0].texture_normal = skip_buttons[1]

func stop_autoing():
	input_autoing = false

func handle_skipping(last_delay):
	if (game_state!= 'GAME'):
		stop_skipping()
		return
	# TODO: Handle text animation
	if not (input_skipping or (Input.is_action_pressed("skip_active"))):
		return
	if should_stop_skipping():
		return
	if next_skip_delay<0.0:
		next_skip_delay = vn_configuration['skip_delay']
		go_forwards(false, true)
	next_skip_delay-=last_delay

func handle_auto(last_delay):
	if (game_state!= 'GAME'):
		stop_autoing()
		return
	# TODO: Handle text animation
	if not input_autoing:
		return
	if next_auto_delay<0.0:
		var fast_reading = float(len(text_showing))/vn_configuration['auto_cps']
		next_auto_delay = vn_configuration['auto_delay']+fast_reading
		go_forwards(false)
	next_auto_delay-=last_delay

func show_menu_backgrounds():
	if delay_action():
		return
	ui['screen_box'].show()
	ui["vn_hud"].hide()
	game_state = "MENU"

func hide_menu_backgrounds():
	if delay_action():
		return
	ui["vn_hud"].show()
	ui['screen_box'].hide()
	game_state = "MENU"

func show_menu():
	show_menu_backgrounds()
	create_main_menu()

func hide_menu():
	if delay_action():
		return
	destroy_menu()
	ui["vn_hud"].show()
	ui['screen_box'].hide()
	game_state = "GAME"
	perhaps_read(text_showing)

func toggle_menu():
	if game_state == "MENU":
		hide_menu()
	elif game_state == "GAME":
		show_menu()
	elif game_state == "HISTORY_SCRREN":
		hide_menu()
	elif game_state == "HISTORY_FROM_MENU_SCREEN":
		hide_menu()
	else:
		show_menu()

func handle_focus(scroll_amount=0.0):
	var scroll_step = vn_configuration['font_size']/2
	if highlight_group == "LEAVE":
		$dummy_control/TextureButton.grab_focus()
		highlight_group = "NONE"
	var change_focus_v = 0
	var scroll_vertical = 0.0
	if (Input.is_action_just_pressed("ui_down")):
		change_focus_v = 1
		text_scrolled_amount = 0.0
	elif (Input.is_action_pressed("ui_down")):
		if ((text_scrolled_amount)<vn_configuration['scroll_sensitivity']):
			text_scrolled_amount+=scroll_amount
		if (text_scrolled_amount>vn_configuration['scroll_sensitivity']):
			scroll_vertical=1.0
	if (Input.is_action_just_pressed("ui_up")):
		change_focus_v = -1
		text_scrolled_amount = 0.0
	elif (Input.is_action_pressed("ui_up")):
		if ((text_scrolled_amount)<vn_configuration['scroll_sensitivity']):
			text_scrolled_amount+=scroll_amount
		if ((text_scrolled_amount)>vn_configuration['scroll_sensitivity']):
			scroll_vertical-=1.0
	var change_focus_h = 0
	if (Input.is_action_just_pressed("ui_right")):
		change_focus_h = 1
		text_scrolled_amount = 0.0
	if (Input.is_action_just_pressed("ui_left")):
		change_focus_h = -1
		text_scrolled_amount = 0.0
	if (change_focus_v!=0) or (change_focus_h!=0):
		if (highlight_group=="NONE"):
			# print("Direction from nowhere: "+game_state)
			if game_state.ends_with("MENU"):
				highlight_group = "MENU"
				var menu_box = ui['menu_box']
				var found_button=null
				var button_list = menu_box.get_children()
				if (change_focus_v==-1):
					button_list.invert()
				for candidate_button in button_list:
					var is_interactive = candidate_button.has_signal("pressed")
					if (candidate_button.has_signal("value_changed")):
						is_interactive = true
					if (is_interactive):
						found_button=candidate_button
						break
				found_button.grab_focus()
			elif (game_state.ends_with("SCREEN")):
				if (change_focus_v!=0):
					ui['screen_textbox'].get_v_scroll_bar().grab_focus()
					ui['screen_textbox'].get_v_scroll_bar().value+=scroll_step*change_focus_v
				if (change_focus_h>0):
					vn_screen_highlight+=1
					if vn_screen_highlight>=len(vn_screen_text):
						vn_screen_highlight=0
					elif vn_screen_highlight<0:
						vn_screen_highlight=len(vn_screen_text)-1
					perhaps_read(vn_screen_text[vn_screen_highlight])
				elif (change_focus_h<0):
					vn_screen_highlight-=1
					if vn_screen_highlight>=len(vn_screen_text):
						vn_screen_highlight=0
					elif vn_screen_highlight<0:
						vn_screen_highlight=len(vn_screen_text)-1
					perhaps_read(vn_screen_text[vn_screen_highlight])
			elif game_state == "GAME":
				if (change_focus_h!=0):
					highlight_group = "QUICKMENU"
					var menu_box = ui['vn_quickmenu']
					var found_button = menu_box.get_children()[0]
					if change_focus_h==-1:
						found_button = menu_box.get_children()[-1]
					found_button.grab_focus()
					perhaps_read(tr(found_button.name.to_upper()))
				elif (change_focus_v!=0):
					ui['vn_textbox'].get_v_scroll_bar().grab_focus()
					ui['vn_textbox'].get_v_scroll_bar().value+=scroll_step*change_focus_v
		elif ((game_state=='GAME') and (change_focus_v!=0)):
			ui['vn_textbox'].get_v_scroll_bar().value+=scroll_step*change_focus_v
			#ui['vn_textbox'].get_v_scroll_bar().grab_focus()
		elif ((game_state=='GAME') and (change_focus_h!=0)):
			var menu_box = ui['vn_quickmenu']
			for found_button in menu_box.get_children():
				if found_button.has_focus():
						perhaps_read(tr(found_button.name.to_upper()))
		elif (game_state=='GAME'):
			ui['vn_textbox'].get_v_scroll_bar().value+=scroll_step
		#else:
			#print('vertical: '+str(change_focus_v)+' in '+game_state)
	elif (scroll_vertical!=0.0):
		if (game_state=='GAME'):
			ui['vn_textbox'].get_v_scroll_bar().value+=fast_scroll_speed*scroll_vertical*scroll_amount
		else:
			ui['screen_textbox'].get_v_scroll_bar().value+=fast_scroll_speed*scroll_vertical*scroll_amount
	if ((input_vertical!=0) or (input_horizontal!=0)):
		# TODO: Add speaking of labels and screen text
		if (game_state.ends_with("MENU")):
			var button_list = ui['menu_box'].get_children()
			var option_text = ""
			for button in button_list:
				if (button.is_class("BaseButton") or 
					(button.is_class("Label"))):
					option_text = button.text
				if button.has_focus():
					for number in '0123456789':
						option_text = option_text.replace('.'+number,
														' '+tr('VOICE_DECIMAL_POINT')+' '+number)
					perhaps_read (option_text)
		input_vertical=0
		input_horizontal=0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	handle_focus(delta)
	handle_skipping(delta)
	handle_auto(delta)
	var mouse_just_undid = false
	if (input_mouse_undoing and (input_mouse_undone>=5.0-vn_configuration['scroll_sensitivity'])):
		input_mouse_undoing = false
		input_mouse_undone = 0.0
		mouse_just_undid = true
	elif (input_mouse_undoing):
		input_mouse_undoing = false
		input_mouse_undone = 0.0
	elif (input_mouse_undone<0.5):
		input_mouse_undone += delta
	# var camera = $camera_animation_player/Camera2D
	if (Input.is_action_just_pressed("ui_accept") or
		Input.is_action_just_pressed("vn_forwards")):
		if (game_state=="GAME") and (highlight_group=="NONE"):
			advance_text_outer()
	elif (Input.is_action_just_pressed("ui_page_up") or
			Input.is_action_just_pressed("undo_step") or
			mouse_just_undid):
		if game_state=="GAME":
			go_backwards()
	elif (Input.is_action_just_pressed("ui_cancel")):
		toggle_menu()
	elif (Input.is_action_just_pressed("skip_toggle")):
		if (game_state=="GAME"):
			toggle_skipping()
	elif (Input.is_action_just_pressed("accessibility_screen")):
		create_accessibility_menu(true)
	elif (Input.is_action_just_pressed("menu_voice")):
		toggle_selfvoice()
	else:
		released_change += delta
	text_shown_amount += delta*vn_configuration["text_cps"]
	update_text()

func update_text():
	var current_shown_length = floor(text_shown_amount)
	var changed_text = text_showing
	if ((vn_configuration['text_mode']=="CHARACTERS") and 
			(vn_configuration['text_cps']>0)):
		var check_linebreaks = current_shown_length
		if (check_linebreaks<(len(text_showing))):
			while (check_linebreaks>0):
				if text_showing[check_linebreaks] == ' ':
					if check_linebreaks in vn_text_linebreaks[vn_position]:
						# current_shown_length = check_linebreaks
						changed_text[check_linebreaks] = '\n'
					break
				check_linebreaks -= 1
			#.get_wordwrap_string_size(extended_text, text_box_width)
	elif ((current_shown_length<len(text_showing)) and
			(vn_configuration['text_mode']=="WORDS") and
			vn_configuration['text_cps']>0):
		while ((current_shown_length>0) and (text_showing[current_shown_length]!=' ')):
			current_shown_length -= 1
	else:#if (text_mode=="INSTANT"):
		current_shown_length=len(text_showing)
		var new_length = current_shown_length+0.1
		if (text_shown_amount<new_length):
			text_shown_amount=new_length
	var text_shown = changed_text.substr(0, current_shown_length)
	ui['vn_textbox'].text=text_shown

func _input(event):
	if event.is_action("mouse_undo"):
		input_mouse_undoing = 1
	elif event.is_action("mouse_redo"):
		input_mouse_undoing = -1
	elif event.is_action_released("ui_down"):
		input_vertical = 1
	elif event.is_action_released("ui_up"):
		input_vertical = 1
