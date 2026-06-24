#############################################################################
##  This file is part of: HudMod Video Editor                              ##
##  https://omar-top.itch.io/hudmod-video-editor                           ##
## ----------------------------------------------------------------------- ##
##  Copyright © 2026 Omar Mohammed Balita.                                 ##
## ----------------------------------------------------------------------- ##
##  This program is free software: you can redistribute it and/or modify   ##
##  it under the terms of the GNU General Public License as published by   ##
##  the Free Software Foundation, either version 3 of the License, or      ##
##  (at your option) any later version.                                    ##
##                                                                         ##
##  This program is distributed in the hope that it will be useful,        ##
##  but WITHOUT ANY WARRANTY; without even the implied warranty of         ##
##  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the           ##
##  GNU General Public License for more details.                           ##
##                                                                         ##
##  You should have received a copy of the GNU General Public License      ##
##  along with this program. If not, see <https://www.gnu.org/licenses/>.  ##
#############################################################################
class_name AIChat extends EditorControl

const SETTINGS_KEY_API_KEY: String = "ai/api_key"
const SETTINGS_KEY_MODEL_ID: String = "ai/model_id"
const SETTINGS_KEY_API_URL: String = "ai/api_url"

const DEFAULT_API_URL: String = "https://api.openai.com/v1/chat/completions"
const DEFAULT_MODEL_ID: String = "gpt-4o-mini"

var _ai_client: AIClient
var _http_request: HTTPRequest

var _chat_container: VBoxContainer
var _scroll_cont: ScrollContainer
var _input_line_edit: LineEdit
var _send_button: Button
var _settings_button: Button
var _is_waiting_response: bool = false


func _ready_editor() -> void:
	super()
	
	_ai_client = AIClient.new()
	_restore_settings()
	
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_http_request_completed)
	
	_scroll_cont = IS.create_scroll_container()
	body.add_child(_scroll_cont)
	IS.expand(_scroll_cont, true, true)
	
	_chat_container = VBoxContainer.new()
	_chat_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	_chat_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_cont.add_child(_chat_container)
	
	var bottom_bar: BoxContainer = IS.create_box_container(10, false, {size_flags_vertical = 0, custom_minimum_size = Vector2(0, 40)})
	body.add_child(bottom_bar)
	
	_input_line_edit = IS.create_line_edit("Type your message to AI...", "", null, {size_flags_horizontal = Control.SIZE_EXPAND_FILL})
	bottom_bar.add_child(_input_line_edit)
	_input_line_edit.text_submitted.connect(_on_send_pressed)
	
	_send_button = IS.create_button("Send", null, "", false, false, true, {custom_minimum_size = Vector2(60, 0)})
	bottom_bar.add_child(_send_button)
	_send_button.pressed.connect(_on_send_pressed)
	
	_settings_button = IS.create_button("Settings", null, "", false, false, true, {custom_minimum_size = Vector2(70, 0)})
	bottom_bar.add_child(_settings_button)
	_settings_button.pressed.connect(_on_settings_pressed)
	
	_add_system_message("AI Chat", "Hello! I'm your AI assistant for HudMod. Ask me anything about video editing or your project.")


func _restore_settings() -> void:
	if EditorServer.editor_settings.edit.has_meta(&"ai_api_key"):
		_ai_client.api_key = EditorServer.editor_settings.edit.get_meta(&"ai_api_key")
	if EditorServer.editor_settings.edit.has_meta(&"ai_model_id"):
		_ai_client.model = EditorServer.editor_settings.edit.get_meta(&"ai_model_id")
	else:
		_ai_client.model = DEFAULT_MODEL_ID
	if EditorServer.editor_settings.edit.has_meta(&"ai_api_url"):
		_ai_client.api_url = EditorServer.editor_settings.edit.get_meta(&"ai_api_url")
	else:
		_ai_client.api_url = DEFAULT_API_URL


func _on_send_pressed(msg: String = "") -> void:
	if _is_waiting_response:
		return
	
	var text: String = msg if not msg.is_empty() else _input_line_edit.text.strip_edges()
	if text.is_empty():
		return
	
	_input_line_edit.text = ""
	_add_user_message(text)
	
	if _ai_client.api_key.is_empty():
		_add_system_message("Error", "Please set your API key in Settings first.")
		_on_settings_pressed()
		return
	
	_is_waiting_response = true
	_send_button.disabled = true
	_send_button.text = "Wait..."
	
	_add_system_message("AI", "Thinking...")
	
	var body_str: String = _ai_client.build_request_body(text)
	var headers: PackedStringArray = _ai_client.build_headers()
	_http_request.request(_ai_client.api_url, headers, HTTPClient.METHOD_POST, body_str)


func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_waiting_response = false
	_send_button.disabled = false
	_send_button.text = "Send"
	
	_remove_last_message()  # Remove "Thinking..." message
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_add_system_message("Error", "Request failed. Check connection and try again.")
		return
	
	if response_code != 200:
		var error_msg: String = "API Error (" + str(response_code) + ")"
		if body.size() > 0:
			var json: JSON = JSON.new()
			var parse_err: int = json.parse(body.get_string_from_utf8())
			if parse_err == OK:
				var data = json.get_data()
				if data is Dictionary and data.has(&"error"):
					var err_val = data.error
					if err_val is Dictionary:
						error_msg += ": " + str(err_val.get(&"message", ""))
					else:
						error_msg += ": " + str(err_val)
		_add_system_message("Error", error_msg)
		return
	
	var response_text: String = _ai_client.process_response(body)
	if response_text.is_empty():
		_add_system_message("Error", "Failed to parse API response.")
		return
	
	_add_ai_message(response_text)


func _add_user_message(text: String) -> void:
	var msg_label: Label = IS.create_label("", "", IS.label_settings_main)
	msg_label.text = text
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.modulate = Color(0.7, 0.85, 1.0)
	msg_label.custom_minimum_size.y = 20
	msg_label.add_theme_constant_override(&"margin_left", 8)
	msg_label.add_theme_constant_override(&"margin_right", 8)
	msg_label.text_direction = Control.TEXT_DIRECTION_AUTO
	_chat_container.add_child(msg_label)
	_scroll_to_bottom()


func _add_ai_message(text: String) -> void:
	var msg_label: Label = IS.create_label("", "", IS.label_settings_main)
	msg_label.text = text
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.modulate = Color(1.0, 0.9, 0.7)
	msg_label.custom_minimum_size.y = 20
	msg_label.add_theme_constant_override(&"margin_left", 8)
	msg_label.add_theme_constant_override(&"margin_right", 8)
	msg_label.text_direction = Control.TEXT_DIRECTION_AUTO
	_chat_container.add_child(msg_label)
	_scroll_to_bottom()


func _add_system_message(title: String, text: String) -> void:
	var msg_label: Label = IS.create_label("", "", IS.label_settings_header)
	msg_label.text = text
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.custom_minimum_size.y = 20
	msg_label.add_theme_constant_override(&"margin_left", 8)
	msg_label.add_theme_constant_override(&"margin_right", 8)
	msg_label.text_direction = Control.TEXT_DIRECTION_AUTO
	_chat_container.add_child(msg_label)
	_scroll_to_bottom()


func _remove_last_message() -> void:
	var last_idx: int = _chat_container.get_child_count() - 1
	if last_idx >= 0:
		var last_child: Control = _chat_container.get_child(last_idx)
		_chat_container.remove_child(last_child)
		last_child.queue_free()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	_scroll_cont.scroll_vertical = int(_scroll_cont.get_v_scroll_bar().max_value)


func _on_settings_pressed() -> void:
	var win_cont: BoxContainer = WindowManager.popup_accept_window(get_window(), Vector2(480, 400), "AI Settings")
	var win: WindowManager.AcceptWindow = win_cont.get_window()
	win.accepted.connect(_on_settings_save.bind(win))
	
	var scroll: ScrollContainer = IS.create_scroll_container()
	win_cont.add_child(scroll)
	IS.expand(scroll, true, true)
	
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(vbox)
	IS.expand(vbox, true, false)
	
	var api_key_label: Label = IS.create_label("API Key:", "", IS.label_settings_main)
	vbox.add_child(api_key_label)
	
	var api_key_edit: LineEdit = IS.create_line_edit("sk-...", _ai_client.api_key)
	vbox.add_child(api_key_edit)
	IS.expand(api_key_edit, true, false)
	
	var model_label: Label = IS.create_label("Model:", "", IS.label_settings_main)
	vbox.add_child(model_label)
	
	var model_edit: LineEdit = IS.create_line_edit("gpt-4o-mini", _ai_client.model)
	vbox.add_child(model_edit)
	IS.expand(model_edit, true, false)
	
	var url_label: Label = IS.create_label("API URL:", "", IS.label_settings_main)
	vbox.add_child(url_label)
	
	var url_edit: LineEdit = IS.create_line_edit("https://...", _ai_client.api_url)
	vbox.add_child(url_edit)
	IS.expand(url_edit, true, false)
	
	win.set_meta(&"api_key_edit", api_key_edit)
	win.set_meta(&"model_edit", model_edit)
	win.set_meta(&"url_edit", url_edit)


func _on_settings_save(win: WindowManager.AcceptWindow) -> void:
	var api_key_edit: LineEdit = win.get_meta(&"api_key_edit")
	var model_edit: LineEdit = win.get_meta(&"model_edit")
	var url_edit: LineEdit = win.get_meta(&"url_edit")
	
	_ai_client.api_key = api_key_edit.text.strip_edges()
	_ai_client.model = model_edit.text.strip_edges()
	_ai_client.api_url = url_edit.text.strip_edges()

	EditorServer.editor_settings.edit.set_meta(&"ai_api_key", _ai_client.api_key)
	EditorServer.editor_settings.edit.set_meta(&"ai_model_id", _ai_client.model)
	EditorServer.editor_settings.edit.set_meta(&"ai_api_url", _ai_client.api_url)
	ResourceSaver.save(EditorServer.editor_settings, EditorServer.editor_settings_path)
