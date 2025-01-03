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
@export var vn_chapter: String = '_intro'#null
var vn_anim_dict: Dictionary = {}
var vn_anim_follow: Dictionary = {}
var vn_text = ["."]
var vn_speaker_changes = {}
var vn_characters = {
	"@NARRATOR": {
		"$name": ['"'],
		",border_collie": PackedStringArray(['_{', '.1.0', '.1.0', '.1.0', '_}'])
	}
}

var vn_choices={
	'left_or_right'=[[' Left', '.goto', '.go_left'],
					[' Right', '.goto', '.go_right']]
}
var vn_choice_events={}

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
	"skip": toggle_skipping_to,
	".skip": toggle_skipping,
	"auto": toggle_auto_to,
	".auto": toggle_auto,
	"history": create_history_screen_from_game,
	"menus": toggle_menu
}
var qm_last_press = ""

var known_text_modes = ["CHARACTERS", "INSTANT", "WORDS"]
var vn_previous_text_mode = "CHARACTERS"
var vn_theme = null
var vn_sorted_configuration = []
var vn_text_linebreaks = {}
var vn_showhide_dict = {}
var quick_menu = null
var game_state = 'MENU'
var text_font = null
var highlight_group = 'NONE'
var scroll_speed = 5
var fast_scroll_speed = 100
var vn_reversible_animations = ['camera_up', 'camera_down']
var vn_chapter_positions = {}
var vn_label_positions = {}
var vn_labels_to_chapters={}
var current_label_stack = []
var current_label_index = 0
var largest_label_index = 0
var vn_internal_speaker: String = ''
var vn_chapter_names = {}
var vn_label_names = {}
var vn_first_chapter = '_intro'
var vn_savedata_filename = "user://balevi.txt"
@export var vn_languages: PackedStringArray = ['en', 'da', 'es']
@export var vn_language_names: Dictionary = {'en':'English', 'da':'Dansk', 'es':'Español'}
@export var vn_text_filename: String = 'res://vn_script.txt'
###var vn_running_buttons = {}
@export var vn_use_text_buttons = false

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
#var input_skipping = false
var next_skip_delay = 0.0
var next_auto_delay = 0.0

var vn_tts=[]

var ui_data = {}

var ui={}
var vn_sprites = {}
var blv_keywords = ['_FOLLOW', '_ANIMATE', '_SHOW', '_HIDE', '_SPEAKER',
					'_CHAPTER', '_LABEL', '_CHARACTER', '_REM']

var pv_last_speaker: StringName
var pv_parsing_chapter: StringName
var pv_last_anim: StringName

var qm_toggles: Dictionary = { # TODO: Store auto state when paused
	'auto': false,
	'skip': false,
}
func qm_set_toggle(name: String, value: int):
	var prev_val = qm_toggles[name]
	var new_value = bool(value)
	if value==-1: not prev_val
	qm_toggles [name] = new_value
	ui['qm_'+name].set_pressed (new_value)

func stop_highlighting():
	#highlight_group = "LEAVE"
	highlight_group = "NONE"
	ui['dummy_button'].grab_focus()

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

func unquote_string(text):
	var new_value = ''
	var prev_ch = ''
	for ch in text:
		if prev_ch=='\\':
			if ch in '\\"\'': new_value+=ch
			elif ch=='n': new_value+='\n'
			elif ch=='t': new_value
			else:
				print('Error: invalid escape sequence!')
		elif ch=='"':
			pass
		elif (prev_ch=='"') and (ch=='"'):
			new_value+=ch
		else:
			new_value+=ch
		prev_ch = ch
	return new_value

# I initially implemented choices without parsing, hard-coding them.
#   Then I started working on parsing them while I also had decided
#   to switch to static typing. So that's why this function uses it
#   and the other ones mostly don't.
enum GT_line_state {WORD_START, WORD, QUOTED, UNQUOTED, ERROR}
func get_tokens(text:String) -> Array:
	var new_value: String = ''
	var prev_ch: String = ''
	var results: PackedStringArray = PackedStringArray([])
	var line_state: GT_line_state = GT_line_state.WORD_START
	for ch in text:
		match (line_state):
			GT_line_state.WORD_START:
				if ch in [' ', '\t']:
					pass
				elif ch=='"':
					new_value = ' '
					line_state = GT_line_state.QUOTED
				else:
					new_value = '.' + ch
					line_state = GT_line_state.WORD
			GT_line_state.WORD:
				if ch in [' ', '\t']:
					results.append(new_value)
					new_value = ''
					line_state = GT_line_state.WORD_START
				else: # FIXME: Reduce character set?
					new_value += ch
			GT_line_state.QUOTED:
				if prev_ch=='\\':
					if ch in ['\\', '"', '\'']: new_value+=ch
					elif ch=='n': new_value += '\n'
					elif ch=='t': new_value += '\t'
					else:
						print('Error: invalid escape sequence!')
				elif ch == '\\':
					pass
				elif ch=='"':
					line_state = GT_line_state.UNQUOTED
				else:
					new_value += ch
			GT_line_state.UNQUOTED:
				if ch in [' ', '\t']:
					results.append(new_value)
					new_value = ''
					line_state = GT_line_state.WORD_START
				elif ch == '"':
					new_value += ch
					line_state = GT_line_state.QUOTED
				else:
					results.append(new_value)
					new_value = '.' + ch
		prev_ch = ch
	##print('line ending: ', line_state, ' <', new_value, '>', GT_line_state.UNQUOTED)
	if line_state == GT_line_state.WORD_START:
			pass
	elif line_state == GT_line_state.QUOTED:
		results.append(new_value)
		new_value = ''
		line_state = GT_line_state.ERROR
	else:
		results.append(new_value)
		new_value = ''
		line_state = GT_line_state.WORD_START
	#print('parsed line: ', results)
	return [line_state, results]

func tokenise_text(in_text: String)->PackedStringArray:
	var out_tokens: PackedStringArray = []
	var current_part: String =''
	var inside_string: bool = false
	var escaping: bool = false
	var inside_dialogue: bool = false
	var held_text: String = ''
	var after_held: bool = false
	var ch_i: int = 0
	while (ch_i<len(in_text)):
		var ch: String = in_text[ch_i]
		if inside_string:
			if escaping:
				current_part += ch
				escaping = false
			elif ch == '\\': escaping = true
			elif ch == '"': inside_string = false
			else: current_part += ch
		elif inside_dialogue:
			if ch in '\v\n':
				held_text = current_part
				current_part = ''
				inside_dialogue = false
			else:
				current_part += ch
		elif held_text and (ch in ' \t') and (current_part == ''):
			after_held = true
		elif after_held and ch in '\v\n':
			out_tokens.append(held_text)
			held_text = ''
			after_held = false
		elif after_held:
			current_part = held_text + '\n' + ch
			held_text = ''
			after_held = false
			inside_dialogue = true # This is right, right?
		elif held_text:
			after_held = false
			out_tokens.append(held_text)
			held_text = ''
			ch_i -= 1
		elif current_part == '':
			if ch=='"':
				inside_string = true
				current_part = '"'
			elif ch in '@_#%$,^':
				current_part = ch
			elif ch=='=':
				current_part = '='
				inside_dialogue = true
			elif ch.is_valid_int():
				current_part = '0'+ch
			elif ch in ' \t\n\v':
				pass
			else:
				current_part = '_'+ch
		elif ch in ' \t\n\v':
			out_tokens.append(current_part)
			current_part=''
		elif (current_part[0]=='0') and (not ch.is_valid_int()):
			if ch=='.':
				current_part[0] = '.'
				current_part += ch
			else:
				current_part[0] = 'E'
				current_part += ch
		elif (current_part[0]=='.') and (not ch.is_valid_int()):
			current_part[0] = 'E'
			current_part += ch
		elif current_part[0] in '@_#%$,^0.E':
			current_part += ch
		if ((len(out_tokens)>0) and (out_tokens[len(out_tokens)-1]!='\n') and
			(ch in '\n\v') and (current_part=='')):
			out_tokens.append('\n')
		ch_i += 1
	if current_part!='':
		out_tokens.append(current_part)
	return out_tokens

func is_block(in_tokens: PackedStringArray, start_index: int)->bool:
	var found_is: bool = false
	var token_index: int = start_index # Probably not necessary in this language
	while(token_index<len(in_tokens)):
		if in_tokens[token_index]=='_IS': found_is = true
		if in_tokens[token_index]=='\n':
			return found_is
		token_index += 1
	return found_is

var vn_basic_ints: Dictionary = {}
var vn_basic_floats: Dictionary = {}
var vn_basic_strings: Dictionary = {}

func strings_from_basic(tokens: PackedStringArray, remove_prefix=false)->PackedStringArray:
	tokens.reverse()
	var source_stack:PackedStringArray = [' ',' ',' ',' ',' ',' ',' ',' ']
	var source_current_depth = 0
	for tok in tokens:
		if tok[0] in '#$%0."':
			if source_current_depth < len(source_stack):
				source_stack[source_current_depth] = tok
				source_current_depth += 1
			else:
				source_stack.append(tok)
				source_current_depth += 1
		elif tok[0] in '_!':
			if tok in ['_{', '_}']:
				var optok: String = '_{'
				if tok == '_{': optok = '_}'
				if source_current_depth < len(source_stack):
					source_stack[source_current_depth] = optok
					source_current_depth += 1
				else:
					source_stack.append(optok)
					source_current_depth += 1
			elif tok == '_ADD#':
				if len(source_stack)<2:
					return ['ERROR: integer addition without integers']
				var new_param_1: String = source_stack[source_current_depth-1]
				var new_param_2: String = source_stack[source_current_depth-2]
				if new_param_1[0] not in '0#':
					return ['ERROR: integer addition with non-integer source']
				if new_param_2[0] not in '0#':
					return ['ERROR: integer addition with non-integer source']
				# For one input:
				var new_input_1: int = 0
				if new_param_1[0] == '#':
					if new_param_1 not in vn_basic_ints:
						return ['ERROR: integer addition with undefined variable']
					new_input_1 = vn_basic_ints[new_param_1]
				else:
					var probably_an_int: String = new_param_1.substr(1)
					if not probably_an_int.is_valid_int():
						return ['ERROR: addition stumbled on tokenisation error']
					new_input_1 = probably_an_int.to_int()
				# Same for the other input:
				var new_input_2: int = 0
				if new_param_2[0] == '#':
					if new_param_2 not in vn_basic_ints:
						return ['ERROR: integer addition with undefined variable']
					new_input_2 = vn_basic_ints[new_param_2]
				else:
					var probably_an_int: String = new_param_2.substr(1)
					if not probably_an_int.is_valid_int():
						return ['ERROR: addition stumbled on tokenisation error']
					new_input_2 = probably_an_int.to_int()
				# End of repeated section
				var new_sum = new_input_1 + new_input_2
				source_stack[source_current_depth-2] = ("0%d" % new_sum)
				source_current_depth -= 1
	if source_current_depth == 0:
		return ['ERROR: No value']
	var final_value:PackedStringArray = []
	var last_element:String = source_stack[0]
	if last_element[0] in '#%$':
		if last_element[0] == '#':
			last_element = '"'+vn_basic_ints[last_element]
		if last_element[0] == '%':
			last_element = '"'+vn_basic_floats[last_element]
		elif last_element[0] == '$':
			last_element = '"'+vn_basic_strings[last_element]
		if remove_prefix and (last_element[0] in '0."'):
			last_element = last_element.substr(1)
		final_value.append(last_element)
	else:
		var count_elems: int = 0
		for i in source_stack:
			if remove_prefix and (i[0] in '0."'):
				i = i.substr(1)
			final_value.append(i)
			count_elems += 1
			if count_elems>=source_current_depth: break
	return final_value

func one_string_from_basic(tokens: PackedStringArray, remove_prefix=false)->String:
	var all_strings: PackedStringArray = strings_from_basic(tokens, remove_prefix)
	return ' '.join(all_strings)

func floats_from_basic(tokens: PackedStringArray)->PackedFloat32Array:
	var all_strings: PackedStringArray = strings_from_basic(tokens)
	var all_floats: PackedFloat32Array = []
	for elem in all_strings:
		if elem.begins_with('.'):
			var subelem: String = elem.substr(1)
			if subelem.is_valid_float():
				all_floats.append(subelem.to_float())
	return all_floats

func convert_line(in_line: PackedStringArray)->bool:
	var end_words: PackedStringArray = ['_CHAREND', '_CHOICEEND', '_OPTEND']
	if len(in_line)==0: return true
	if in_line[0][0] == '=':
		vn_text.append(in_line[0].substr(4))
	elif in_line[0][0] == '_':
		if (len(in_line)<2) and not (in_line[0] in end_words):
			print("Probably too few arguments for ", in_line[0])
			return false
		if '_IS' in in_line:
			var block_properties: Dictionary = {}
			print("This is an _IS block")
			if in_line[0]=='_CHARACTER':
				print("It's a character")
				var part_line:PackedStringArray = []
				var block_position: int = 0
				var block_depth = 0
				while (block_position<len(in_line)):
					var tok: StringName = in_line[block_position]
					if tok=='\n':
						if '_IS' in part_line:
							block_depth += 1
						elif '_CHAREND' in part_line:
							block_depth -= 1
						elif block_depth == 1:
							if len(part_line)==0: pass
							elif len(part_line)==1:
								print ("Character property has only one word")
								return false
							elif len(part_line)==2:
								print ("Character property has only two words")
								return false
							elif part_line[0] != '_HAS':
								print ("Character property without _HAS")
								return false
							elif len(part_line[1])>=1:
								# TODO: allow more complex expressions
								block_properties[part_line[1]] = part_line.slice(2)
								if '_LET' in block_properties[part_line[1]]:
									# The double E in "EError" is intentional
									block_properties[part_line[1]] = ['EError: Assignment in displayable value']
							else:
								print("ERROR: Line too short")
						elif len(part_line)==0: pass
						else:
							print ("Wrong depth in character")
						part_line = []
						#print(block_properties)
						print ("Adding character:")
						print(in_line[1])
						vn_characters[in_line[1]]=block_properties
					else:
						part_line.append(tok)
					block_position += 1
				return true
		if '_DO' in in_line:
			if in_line[0]=='_CHOICE':
				return true
		if in_line[0]=='_CHAPTER':
			vn_chapter_positions[in_line[1]]=len(vn_text)
			vn_chapter_names[len(vn_text)]=in_line[1]
			return true
		if in_line[0]=='_FOLLOW':
			return true # TODO
		if in_line[0]=='_ANIMATE': # TODO: probably support WIth
			var animation_name = ''
			var animation_player = ''
			if len(in_line)<3: return false
			animation_player = in_line[1]
			animation_name = in_line[2]
			if pv_last_anim in vn_anim_follow:
				pv_last_anim = vn_anim_follow[pv_last_anim]
			vn_anim_dict[len(vn_text)]=[animation_name, pv_last_anim, animation_player]
			pv_last_anim = animation_name
			return true # TODO
		if in_line[0]=='_SPEAKER':
			vn_speaker_changes[len(vn_text)]=[in_line[1], pv_last_speaker]
			pv_last_speaker = in_line[1]
			return true
		if in_line[0]=='_LABEL':
			vn_label_positions[in_line[1]]=len(vn_text)
			vn_label_names[len(vn_text)]=in_line[1]
			vn_labels_to_chapters[in_line[1]] = pv_parsing_chapter
			return true
		#print(in_line)
		return false
	return true

func load_vn_script(text_filename, target_language):
	var vn_contents = get_file_text(text_filename)
	if vn_contents == null:
		vn_text = [tr('ERROR_NO_SCRIPT')]
		vn_text_linebreaks={}
		return
	vn_text = []
	vn_text_linebreaks = {}
	vn_anim_dict = {}
	vn_anim_follow = {}
	vn_showhide_dict = {}
	vn_chapter_positions = {}
	vn_label_positions = {}
	### vn_choices = {} # Actually, probably load defaults from somewhere
	vn_labels_to_chapters = {}
	vn_choice_events={}
	vn_chapter_names = {}
	vn_speaker_changes = {0:['@NARRATOR','@NARRATOR']}
	var last_text = ""
	var last_language=""
	var last_anim = "camera_idle"
	var last_speaker = ""
	var is_new = 0
	var new_type = ''
	var new_name = ''
	var parsing_chapter = ' '
	var new_choice: Array = []
	var new_option: Dictionary = {}
	var current_line: PackedStringArray = []
	var prev_tok: StringName = ''
	var parsing_block: int = 0
	var count_lines = 0
	for tok in tokenise_text(vn_contents):
		if tok=='\n':
			var tokens_on_line = len(current_line)
			#print(tokens_on_line)
			if len(current_line)==0: pass
			elif current_line[0] == '_REM':
				current_line = []
			elif prev_tok in ['_IS', '_DO']:
				current_line.append(tok)
				parsing_block += 1
			elif parsing_block>0:
				current_line.append(tok)
			else:
				convert_line(current_line)
				count_lines += 1
				current_line = []
		else:
			current_line.append(tok)
			if parsing_block>0:
				if tok in ['_CHAREND', '_CHOICEND', '_OPTEND']:
					parsing_block -= 1
		prev_tok = tok
	print(count_lines)
	return # function ends here

func get_initial_language():
	if ('text_language' in vn_configuration):
		var found_language = vn_configuration['text_language']
		#print('there is a language: '+str(found_language))
		if found_language in vn_languages:
			set_language(found_language, false)
			return
	else:
		pass#print('no language')
	vn_configuration["text_language"] = TranslationServer.get_locale()
	var got_language = false
	for language_code in vn_languages:
		if vn_configuration["text_language"].begins_with(language_code):
			set_language(language_code, false)
			got_language = true
	if not got_language:
		set_language("en", false)

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
	var praf = text
	for format_mark in ['[color=blue]', '[color=#800]', '[/color]']:
		praf = praf.replace(format_mark, '')
	if praf.find('[url]')!=-1:
		for punctuation_pair in ['[url] ', '[/url] ',
							'. dot', '/ slash', ': colon',
							'- hyphen', '# hash', '_ underscore',
							'& ampersand', '% percent', '@ at_sign',
							'+ plus', '? question_mark', '= equal_sign',
							'www w_w_w',
							]:
			var punctuation_mark = punctuation_pair.split(' ')
			punctuation_mark[1]=' '+punctuation_mark[1].replace('_', ' ')+' '
			praf = praf.replace(punctuation_mark[0], punctuation_mark[1])
	praf = praf.replace('\n','.\n').replace(':.\n',':\n')
	for number in '0123456789':
		praf = praf.replace('.'+number, ' '+tr('VOICE_DECIMAL_POINT')+' '+number)
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(tr(praf), vn_tts[0])

# Called when the node enters the scene tree for the first time.
func _ready():
	#print('test dictionary', typeof(test_dictionary), ", " , TYPE_DICTIONARY)
	var ui_names = ['animation_camera:camera_animation_player',
		'vn_hud:HUD_holder', 'vn_adv_hud:adv_HUD',
		'vn_quickmenu:quick_menu_container',
		'vn_text_container:textbox_background', 'vn_textbox:textbox_text',
		'menu_box:menu_box', 'screen_textbox:screen_text',
		'screen_box:screen_holder', 'speaker_text:speaker_name',
		'speaker_box:speaker_background', 'dummy_button:dummy_button']
	for ui_phrase in ui_names:
		var ui_parts = ui_phrase.split(':')
		ui[ui_parts[0]]=find_child(ui_parts[1])
	
	ui['vn_textbox'].visible_characters_behavior=1
	
	# FIXME: I suppose this makes it harder to change the resolution,
	#        but I guess Godot isn't really designed with that in mind :(
	ui['vn_textbox_base_position'] = ui['vn_text_container'].get_transform().get_origin()
	ui['vn_textbox_base_size']=ui['vn_text_container'].size
	text_box_width = ui['vn_textbox'].size.x
	ui['vn_textbox_inner_position'] = ui['vn_textbox'].get_transform().get_origin()
	ui['vn_textbox_inner_size']=ui['vn_textbox'].size
	vn_sprites['witch']=find_child("witch_sprite")
	vn_sprites['animation_player']=$landskab/sprites
	#vn_sprites['content']=$landskab/sprites/Node2D
	vn_configuration['text_cps']=50.0
	vn_configuration['font_size']=50
	vn_configuration['game_title']='BLV Example Game'
	vn_configuration['game_version']=1.0
	vn_configuration['scroll_sensitivity']=4.9
	vn_configuration['voice_volume']=100
	vn_configuration['text_mode']="CHARACTERS"
	var actual_config = get_file_text(vn_savedata_filename)
	if actual_config==null:
		var element_order = ['# Metadata', 'game_title', 'game_version',
			'# Settings and unlocks:', 'text_cps', 'text_mode', 'font_size',
			'scroll_sensitivity', 'voice_volume']
		actual_config = ''
		for i in element_order:
			if i.begins_with('#'):
				actual_config += i+'\n'
			else:
				actual_config += i + '=' + str(vn_configuration[i])+'\n'
	decode_settings(actual_config)
	# text_font = ui['vn_textbox'].get_theme_default_font()
	#text_font = ui['vn_textbox'].normal_font
	vn_theme = load("res://default_theme.tres")
	vn_theme.default_font_size = vn_configuration['font_size']
	#print(vn_theme.get_type_list())
	for i in ["Label", "RichTextLabel", "TooltipLabel"]:
		print(i)
		var i1=(vn_theme.get_color_list(i))
		for j in i1:
			print(vn_theme.get_color(j, i))
	text_font = vn_theme.default_font #ui['vn_textbox'].get_theme_default_font()
	text_default_size=50
	if not 'text_language' in vn_configuration:
		get_initial_language()
	else:
		set_language(vn_configuration['text_language'], false)
	# TODO: Separate quick menu and add tooltips
	quick_menu = ui['vn_quickmenu']
	var button_count: int = 0
	for button_name in ["back", "skip@run", "auto@run", "history", "menus"]:
	# ["back", "auto", "skip", "history", "menus"]:
		if vn_use_text_buttons and (button_count>0):
			var sep = HSeparator.new()
			quick_menu.add_child(sep)
		var has_running_state=false
		if button_name.ends_with('@run'):
			button_name=button_name.split('@')[0]
			has_running_state=true
		var new_button = null
		if vn_use_text_buttons: new_button= Button.new()
		else: new_button= TextureButton.new()
		if has_running_state:
			new_button.toggle_mode = true
		new_button.name = "qm_"+button_name
		if (vn_use_text_buttons):
			new_button.text = button_name
		else:
			#if has_running_state:
			#	var texture_running = load("res://gui/"+button_name+"-running.png")
				###vn_running_buttons[button_name]=[new_button, texture_normal, texture_running]
			new_button.texture_normal = load("res://gui/"+button_name+".png")
			#new_button.material = load ("res://button-material.tres")
			new_button.texture_pressed = load("res://gui/"+button_name+"-focus.png")
			#new_button.texture_disabled = load("res://gui/"+button_name+"-disabled.png")
			new_button.texture_hover = load("res://gui/"+button_name+"-focus.png")
			new_button.texture_focused = load("res://gui/"+button_name+"-focus.png")
		if button_name in qm_buttons:
			if has_running_state:
				new_button.connect("toggled", qm_buttons[button_name])
			else:
				new_button.connect("pressed", qm_buttons[button_name])
		if has_running_state: new_button.connect("gui_input",
					redo_if_double_click.bind (qm_buttons['.'+button_name]))
		else: new_button.connect("gui_input", redo_if_double_click.bind (button_name))
		new_button.connect("mouse_entered", mouse_entered)
		new_button.connect("mouse_exited", mouse_exited)
		quick_menu.add_child(new_button)
		ui['qm_'+button_name]=new_button
		##print(new_button)
		button_count += 1
	# text_font.get_string_size()
	ui['animation_camera'].play("camera_idle")
	print(vn_choices)
	print('playing the first animation')
	animate_position(1)
	print('showing the menu')
	show_menu()

func mouse_entered(): print('mouse entered')
func mouse_exited(): print('mouse exited')

func redo_if_double_click(event: InputEvent, button_name: String):
	if event is InputEventMouseButton:
		var what = "released"
		if event.pressed: what="pressed"
		elif qm_last_press==button_name:
			print('Second part of double click')
			qm_buttons['.'+button_name].call()
		print("Mouse button "+what+" to ", button_name)
		if event.double_click:
			qm_last_press = button_name
		elif event.canceled:
			print('Canceled event')
			qm_last_press = ''
		else: qm_last_press = ''

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
		perhaps_read(tr("SN_INGAME"))
		create_button("MM_CONTINUE", hide_menu, "MH_CONTINUE")
		create_button("MM_HISTORY", create_history_screen_from_menu, "MH_HISTORY")
		create_button("MM_RESTART", start_vn, "MH_RESTART")
	else:
		perhaps_read(tr("SN_MAIN"))
		create_button("MM_PLAY", start_vn, "MH_PLAY")
	create_button("MM_LOAD", create_load_menu, "MH_LOAD")
	create_button("MM_LANGUAGE", create_language_menu, "MH_LANGUAGE")
	create_button("MM_CONFIG", create_config_menu, "MH_CONFIG")
	create_button("MM_CREDITS", create_credits_screen, "MH_CREDITS")
	create_button("MM_HELP", create_help_screen, "MH_HELP")
	game_state = 'MENU'
	ui['screen_box'].show()
	ui["vn_hud"].hide()

func create_language_menu():
	perhaps_read(tr("SN_LANGUAGE"))
	destroy_menu()
	for i in vn_languages:
		var language_name = vn_language_names[i]
		create_button(language_name, set_language, tr('LANG_'+(i.to_upper())), i)	
	#create_button("English", set_language, "English", 'en')
	#create_button("Dansk", set_language, "Danish", 'da')
	#create_button("Español", set_language, "Spanish", 'es')
	create_button("SM_BACK_TO_MENU", create_main_menu, "SH_BACK_TO_MENU")
	game_state = 'LANGUAGE_MENU'
	ui['screen_box'].show()
	ui["vn_hud"].hide()

func create_load_menu():
	perhaps_read(tr("SN_LOAD"))
	destroy_menu()
	create_label("LM_PICK_CHAPTER_LABEL")
	for chapter in vn_chapter_positions:
		if ((('chapter:'+chapter) in vn_configuration) or
			(chapter==vn_first_chapter)):
			create_button('CHAPTER_'+chapter, conditionally_load_chapter, "", [chapter])
	create_separator()
	create_button("SM_BACK_TO_MENU", create_main_menu, "SH_BACK_TO_MENU")
	game_state = 'LOAD_MENU'
	ui['screen_box'].show()
	ui["vn_hud"].hide()

func create_choice_menu(choice_options):
	perhaps_read(tr("SN_CHOICE"))
	destroy_menu()
	#print('choice: ',choice_options)
	for option in choice_options:
		print(option)
		if not 'text' in option: continue
		if not 'action' in option: continue
		#print('name and action found')
		# TODO: support other actions
		if len (option['action']) != 2: continue
		#print('action length OK')
		if option['action'][0] != '.goto': continue
		var target_label = option['action'][1].substr(1)
		##print('[', option['text'], ']')
		var button_text = option['text'].substr(1)
		#print('creating button: <', target_label, '> <', button_text, '>')
		create_button(button_text, load_label, "", [target_label])
		#print('choice created!')
	
	game_state = "CHOICE_SUBGAME"
	ui['screen_box'].show()
	ui['vn_adv_hud'].hide()
	ui['vn_quickmenu'].show()

func conditionally_load_chapter(chapter_data):
	var chapter_name = chapter_data[0]
	if chapter_name in vn_chapter_positions:
		start_vn()
		vn_position = vn_chapter_positions[chapter_name]
		vn_chapter = vn_first_chapter
		animate_position(0)

func load_label(label_data):
	var label_name = label_data[0]
	#print ('going to ', label_name)
	if label_name in vn_label_positions:
		#print(current_label_stack)
		#print(current_label_index)
		if ((len(current_label_stack)-1)>current_label_index):
			#print('overwriting position')
			current_label_index +=1
			current_label_stack[current_label_index] = [label_name, vn_position]
			largest_label_index = current_label_index
		else:
			#print('adding position')
			current_label_stack.append([label_name, vn_position])
			current_label_index += 1
		vn_position = vn_label_positions[label_name]
		vn_chapter = vn_labels_to_chapters[label_name]
		animate_position(0)
		if (true):
			#print('position when leaving the menu: ',vn_position)
			destroy_menu()
			hide_menu(true)
	else:
		print('Error: Label not found!')

func create_accessibility_menu(from_game=true):
	perhaps_read(tr("SN_ACCESSIBILITY"))
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
	game_state = 'CONFIG_MENU'
	ui['screen_box'].show()


func create_audio_menu():
	perhaps_read(tr("SN_SOUND"))
	destroy_menu()
	ui_data ['voice_volume'] = create_slider(
		"CM_VOICE_VOLUME", vn_configuration["voice_volume"],
		0, 100, 1, ['voice_volume'])
	create_separator()
	create_button("SM_BACK_TO_MENU", create_config_menu, "SH_BACK_TO_MENU")
	game_state = 'AUDIO_MENU'
	ui['screen_box'].show()


func create_text_menu():
	perhaps_read(tr("SN_TEXT"))
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
	game_state = 'TEXT_MENU'
	ui['screen_box'].show()
	ui["vn_hud"].show() # for previewing stuff ######

func create_config_menu():
	perhaps_read(tr("SN_SETTINGS"))
	destroy_menu()
	create_button("CM_TEXT", create_text_menu, "MH_TEXT")
	create_button("CM_ACCESSIBILITY", create_accessibility_menu,
					"MH_ACCESSIBILITY", false)
	#create_button("CM_AUDIO", create_audio_menu, "MH_AUDIO")
	create_separator()
	create_button("SM_BACK_TO_MENU", apply_settings, "SH_BACK_TO_MENU")
	game_state = 'CONFIG_MENU'
	ui['screen_box'].show()
	ui["vn_hud"].hide()

func set_language (language_code, to_menu=true):
	TranslationServer.set_locale(language_code)
	load_vn_script(vn_text_filename, language_code)
	vn_configuration["text_language"] = language_code
	vn_tts = DisplayServer.tts_get_voices_for_language(language_code)
	vn_language_changed = true
	if (to_menu):
		create_main_menu()

func apply_settings():
	load_vn_script(vn_text_filename, vn_configuration["text_language"])
	create_main_menu()

func create_text_screen(screen_text, stay_in_menu):
	destroy_menu()
	# var menu_box = $camera_animation_player/Camera2D/Outer_control/menu_box
	show_menu_backgrounds()
	vn_screen_text = []
	vn_screen_highlight = -1
	for i in(screen_text.split("\n\n")):
		vn_screen_text.append(i)
	var use_label = ui['screen_textbox']
	use_label.bbcode_enabled = true
	use_label.text = screen_text
	use_label.show()
	if stay_in_menu:
		create_button("SM_BACK_TO_MENU", create_main_menu, "SH_BACK_TO_MENU")
	else:
		create_button("SM_BACK_TO_MENU", hide_menu, "SH_BACK_TO_GAME")

func create_credits_screen():
	perhaps_read(tr("SN_CREDITS"))
	var screen_text = get_file_text ("res://credits_"+vn_configuration["text_language"]+".txt")
	if screen_text==null:
		screen_text = tr("ERROR_SCREEN_TEXT_NOT_FOUND")
	create_text_screen(screen_text, true)
	game_state = 'ABOUT_SCREEN'

func create_help_screen():
	perhaps_read(tr("SN_HELP"))
	var screen_text = get_file_text ("res://controls_"+vn_configuration["text_language"]+".txt")
	if screen_text==null:
		screen_text = tr("ERROR_SCREEN_TEXT_NOT_FOUND")
	create_text_screen(screen_text, true)
	game_state = 'HELP_SCREEN'

func create_history_screen(stay_in_menu):
	perhaps_read(tr("SN_HISTORY"))
	var history_text = ""
	var line_count=0
	var check_position = vn_position-1
	var alternate_stack_index = current_label_index
	while line_count<100:
		if check_position<0:
			break
		if (check_position+1) in vn_label_names:
			if current_label_stack[alternate_stack_index][0]==vn_label_names[check_position+1]:
				# TODO: check
				check_position = current_label_stack[alternate_stack_index][1]
				alternate_stack_index-=1
		var vn_line = vn_text[check_position]
		if vn_line=='': vn_line = '(choice)'
		history_text = vn_line + "\n\n" + history_text
		check_position -= 1
		line_count+=1
	create_text_screen(history_text, stay_in_menu)

func create_history_screen_from_game():
	create_history_screen(false)
	game_state = 'HISTORY_SCREEN'

func create_history_screen_from_menu():
	create_history_screen(true)
	game_state = 'HISTORY_FROM_MENU_SCREEN'

func start_vn():
	vn_position = 0
	current_label_index = 0
	largest_label_index = 0
	current_label_stack = [' '] # ' ' should compare unequal to any valid label
	hide_menu()
	vn_chapter = vn_first_chapter
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
		if (showhide_action[1]) not in vn_sprites:
			vn_sprites[showhide_action[1]]=find_child(showhide_action[1])
		if showhide_action[0]=="_SHOW":
			vn_sprites[showhide_action[1]].show()
			#vn_sprites['animation_player'].play('witch_idle')
		elif showhide_action[0]=="_HIDE":
			#vn_sprites['animation_player'].stop()
			vn_sprites[showhide_action[1]].hide()
	if (((vn_position in vn_speaker_changes) and (animate_direction>-1))
		or ((vn_position+1 in vn_speaker_changes) and (animate_direction==-1))
		):
		var speaker_change_position = vn_position
		if animate_direction==-1:
			speaker_change_position = vn_position+1
			##print("Switching back")
		else:
			pass
			##print("Switching forwards")
		## print ('new speaker: '+ str(vn_speaker_changes[vn_position]))
		var full_speaker = vn_speaker_changes[speaker_change_position]
		vn_internal_speaker = full_speaker[0]
		var previous_speaker = full_speaker[1]
		if (animate_direction==-1):
			vn_internal_speaker = full_speaker[1]
			previous_speaker = full_speaker[0]
		var local_speaker: String = tr('SPEAKER_'+vn_internal_speaker)
		if local_speaker.count ('SPEAKER_') == 1+ (vn_internal_speaker.count('SPEAKER_')):
			local_speaker = vn_internal_speaker
			if vn_internal_speaker not in vn_characters:
				pass
			elif '$name' in vn_characters[vn_internal_speaker]:
				var character_dictionary = vn_characters[vn_internal_speaker]
				if '$name' in character_dictionary:
					local_speaker = one_string_from_basic(character_dictionary['$name'], true)
		if vn_internal_speaker in vn_characters:
			var chosen_language = TranslationServer.get_locale()
			var speaker_found = vn_characters[vn_internal_speaker]
			if '$name'+'@'+chosen_language in speaker_found:
				local_speaker = speaker_found['name'+'@'+chosen_language]
			elif ('$name' in speaker_found) and (local_speaker.begins_with('SPEAKER_')):
				local_speaker = one_string_from_basic (speaker_found['$name'], true)
			if (',border_collie' in speaker_found):
				var colf_floats: PackedFloat32Array = floats_from_basic(speaker_found[',border_collie'])
				if len(colf_floats)==3:
					var colf = Vector3(colf_floats[0], colf_floats[1], colf_floats[2])
					ui['vn_text_container'].material.set_shader_parameter('border_collie', colf)
		if (((vn_internal_speaker=='') and (local_speaker=='SPEAKER_')) or
				(local_speaker=='')):
			##print ('Switching to \'none\' speaker')
			ui['speaker_text'].text=''
			ui['speaker_box'].hide()
			
		else:
			if previous_speaker=='':
				ui['speaker_box'].show()
				previous_speaker = 'none'
			ui['speaker_text'].text=local_speaker
			
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
	if (animate_direction==-1) and ((vn_position+1) in vn_label_names):
		if current_label_stack[current_label_index][0]==vn_label_names[vn_position+1]:
			# TODO: check
			vn_position = current_label_stack[current_label_index][1]
			current_label_index-=1
	if vn_position in vn_choice_events:
		#print('make a choice? ', game_state)
		if (game_state=='GAME') or (game_state=='CHOICE_SUBGAME'):
			var choice = vn_choice_events[vn_position]
			create_choice_menu(vn_choices[choice])
	var to_play: String = ''
	var try_backwards = false
	var player_to_use: String = ''
	if (animate_direction==-1):
		if vn_position<len(vn_text)-1:
			if (vn_position+1) in vn_anim_dict:
				#print("Going back from ", vn_anim_dict[vn_position+1])
				to_play = vn_anim_dict[vn_position+1][0]
				player_to_use = vn_anim_dict[vn_position+1][2]
				# TODO: replace backwards animation system
				if vn_anim_dict[vn_position+1][0]:
					#to_play = vn_anim_dict[vn_position+1][0]
					try_backwards = true
	if vn_position in vn_anim_dict:
		var animation_rule = vn_anim_dict[vn_position]
		#print('position: ', vn_position)
		#print(animation_rule)
		to_play = animation_rule[0]
		if to_play[0]=='"': to_play = to_play.substr(1)
		player_to_use = animation_rule[2]
		if player_to_use[0]=='"': player_to_use = player_to_use.substr(1)
		try_backwards=false
	if to_play!='':
		if player_to_use[0]=='"': player_to_use = player_to_use.substr(1)
		if to_play[0]=='"': to_play = to_play.substr(1)
		if try_backwards and (0==find_child(player_to_use).get_animation(to_play).get_loop_mode()):
			find_child(player_to_use).play_backwards(to_play)
		else:
			find_child(player_to_use).play(to_play)
	text_showing = vn_text[vn_position]
	text_shown_amount = 0.0
	if (animate_direction!=1):
		text_shown_amount = len(text_showing)+0.1
	if (game_state=='GAME'):
		perhaps_read(text_showing)
	if (((vn_position+1) in vn_choice_events) and
		(vn_position not in vn_choice_events) and
		(animate_direction==-1)
		):
		hide_menu(true)
		## print('hiding the choice screen: ', text_showing)
	#if (text_showing!='') and (vn_position not in vn_text_linebreaks):
	#	vn_text_linebreaks[vn_position]=get_string_linebreaks(text_showing,
	#ad I'llad										text_box_width)
		## print(text_showing)
		## print('linebreaks: ', vn_text_linebreaks[vn_position])

func maybe_stop_skipping():
	if should_stop_skipping():
		qm_set_toggle('skip', 0)

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
		vn_chapter = vn_first_chapter
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

func toggle_skipping_to(to_state: bool):
	print('Toggle skipping to ', to_state)
	qm_set_toggle('skip', int(to_state))
	maybe_stop_skipping()

func toggle_skipping():
	qm_set_toggle('skip', -1)

func toggle_auto():
	qm_set_toggle('auto',-1)

func toggle_auto_to(val: bool):
	qm_set_toggle('auto',int(val))

func toggle_selfvoice():
	if vn_configuration['self_voicing']==1:
		perhaps_read('TTS stopped.', true)
		vn_configuration['self_voicing'] = 0
	else:
		perhaps_read('TTS started.', true)
		vn_configuration['self_voicing'] = 1
	print("Toggled speech to "+str(vn_configuration['self_voicing']))

func handle_skipping(last_delay):
	if (game_state!= 'GAME'):
		qm_set_toggle('skip', 0)
		return
	# TODO: Handle text animation
	if not (qm_toggles['skip'] or (Input.is_action_pressed("skip_active"))):
		return
	if should_stop_skipping():
		return
	if next_skip_delay<0.0:
		next_skip_delay = vn_configuration['skip_delay']
		go_forwards(false, true)
	next_skip_delay-=last_delay

func handle_auto(last_delay):
	if (game_state!= 'GAME'):
		qm_set_toggle('auto', 0)
		return # TODO: Consider just pausing
	# TODO: Handle text animation
	if not qm_toggles['auto']:
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
	game_state = 'MENU'

func hide_menu_backgrounds():
	if delay_action():
		return
	ui["vn_hud"].show()
	ui['screen_box'].hide()
	game_state = 'MENU'

func show_menu():
	show_menu_backgrounds()
	create_main_menu()

func hide_menu(force_hide=false):
	# print('Probably hiding the menu')
	if delay_action() and not force_hide:
		print ('if I didn\'t have to wait')
		return
	destroy_menu()
	ui['vn_hud'].show()
	ui['vn_adv_hud'].show()
	if text_showing!='':
		print('probably showing a CG or choice')
		ui['vn_text_container'].show()
	ui['screen_box'].hide()
	game_state = 'GAME'
	if vn_position in vn_choice_events:
		# print('not hiding the screen UI completely')
		create_choice_menu(vn_choices[vn_choice_events[vn_position]])
	else:
		# print('hiding the screen UI completely')
		perhaps_read(text_showing)

func toggle_menu():
	if game_state == 'MENU':
		hide_menu()
	elif game_state == 'GAME':
		show_menu()
	elif game_state == 'HISTORY_SCRREN':
		hide_menu()
	elif game_state == 'HISTORY_FROM_MENU_SCREEN':
		hide_menu()
	else:
		show_menu()

func handle_focus(scroll_amount=0.0):
	var scroll_step = vn_configuration['font_size']/2
	if highlight_group == 'LEAVE':
		$dummy_control/TextureButton.grab_focus()
		highlight_group = 'NONE'
	var change_focus_v = 0
	var scroll_vertical = 0.0
	if (Input.is_action_just_pressed('ui_down')):
		change_focus_v = 1
		text_scrolled_amount = 0.0
	elif (Input.is_action_pressed('ui_down')):
		if ((text_scrolled_amount)<vn_configuration['scroll_sensitivity']):
			text_scrolled_amount+=scroll_amount
		if (text_scrolled_amount>vn_configuration['scroll_sensitivity']):
			scroll_vertical=1.0
	if (Input.is_action_just_pressed('ui_up')):
		change_focus_v = -1
		text_scrolled_amount = 0.0
	elif (Input.is_action_pressed('ui_up')):
		if ((text_scrolled_amount)<vn_configuration['scroll_sensitivity']):
			text_scrolled_amount+=scroll_amount
		if ((text_scrolled_amount)>vn_configuration['scroll_sensitivity']):
			scroll_vertical-=1.0
	var change_focus_h = 0
	if (Input.is_action_just_pressed('ui_right')):
		change_focus_h = 1
		text_scrolled_amount = 0.0
	if (Input.is_action_just_pressed('ui_left')):
		change_focus_h = -1
		text_scrolled_amount = 0.0
	if (change_focus_v!=0) or (change_focus_h!=0):
		if ((highlight_group=='NONE') or
			((game_state=='CHOICE_SUBGAME') and
				( ((highlight_group=='MENU') and (change_focus_h!=0)) or
				((highlight_group=='QUICKMENU') and (change_focus_v!=0)) )
				)
			):
			# print('Direction from nowhere: '+game_state)
			if (game_state.ends_with('MENU') or
				((game_state=='CHOICE_SUBGAME') and
					(change_focus_v!=0))):
				highlight_group = 'MENU'
				var menu_box = ui['menu_box']
				var found_button=null
				var button_list = menu_box.get_children()
				if (change_focus_v==-1):
					button_list.reverse() ### Check name
				for candidate_button in button_list:
					var is_interactive = candidate_button.has_signal('pressed')
					if (candidate_button.has_signal('value_changed')):
						is_interactive = true
					if (is_interactive):
						found_button=candidate_button
						break
				found_button.grab_focus()
			elif (game_state.ends_with('SCREEN')):
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
			elif ((game_state == 'GAME') or
				((game_state=='CHOICE_SUBGAME') and (change_focus_h!=0))
				):
				if (change_focus_h!=0):
					highlight_group = 'QUICKMENU'
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
		if (game_state.ends_with('MENU')):
			var button_list = ui['menu_box'].get_children()
			var option_text = ''
			for button in button_list:
				if (button.is_class('BaseButton') or 
					(button.is_class('Label'))):
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
	if (game_state.ends_with('SCREEN')):
		if (Input.is_action_just_pressed("ui_accept")):
			print("Accepted a screen?")
			var highlighted_line = vn_screen_text[vn_screen_highlight]
			print(highlighted_line)
			if '[url]' in (highlighted_line):
				var url_with_end = highlighted_line.split('[url]')[1]
				if '[/url]' in url_with_end:
					var meta = url_with_end.split('[/url]')[0]
					#print('This would open a URL:')
					#print(meta)
					OS.shell_open(str(meta))
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
			qm_set_toggle('skip', -1)
	elif (Input.is_action_just_pressed("accessibility_screen")):
		create_accessibility_menu(true)
	elif (Input.is_action_just_pressed("menu_voice")):
		toggle_selfvoice()
	else:
		released_change += delta
	text_shown_amount += delta*vn_configuration["text_cps"]
	update_text()

func update_text():
	var current_shown_length = floori(text_shown_amount)
	#var changed_text = text_showing
	if ((vn_configuration['text_mode']=="CHARACTERS") and 
			(vn_configuration['text_cps']>0)):
		pass
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
	#var text_shown = changed_text.substr(0, current_shown_length)
	ui['vn_textbox'].text=text_showing
	var text_ratio = min(1.0, text_shown_amount/(ui['vn_textbox'].get_total_character_count()))
	ui['vn_textbox'].visible_ratio = text_ratio

func _input(event):
	if event.is_action("mouse_undo"):
		input_mouse_undoing = 1
	elif event.is_action("mouse_redo"):
		input_mouse_undoing = -1
	elif event.is_action_released("ui_down"):
		input_vertical = 1
	elif event.is_action_released("ui_up"):
		input_vertical = 1

func _on_screen_text_meta_clicked(meta):
	OS.shell_open(str(meta))
