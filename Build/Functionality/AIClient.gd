class_name AIClient extends Object

var api_key: String
var api_url: String = "https://api.openai.com/v1/chat/completions"
var model: String = "gpt-4o-mini"
var temperature: float = 0.7
var max_tokens: int = 4096
var system_prompt: String = "You are a helpful video editing assistant integrated into the HudMod video editor."

var messages: Array[Dictionary] = []


func _init(p_api_key: String = "", p_api_url: String = "", p_model: String = "") -> void:
	api_key = p_api_key
	if not p_api_url.is_empty():
		api_url = p_api_url
	if not p_model.is_empty():
		model = p_model
	reset_conversation()


func reset_conversation() -> void:
	messages.clear()
	messages.append({&"role": &"system", &"content": system_prompt})


func add_message(role: String, content: String) -> void:
	messages.append({&"role": role, &"content": content})


func build_request_body(content: String) -> String:
	add_message(&"user", content)
	var body: Dictionary = {
		&"model": model,
		&"messages": messages,
		&"temperature": temperature,
		&"max_tokens": max_tokens,
		&"stream": false
	}
	return JSON.stringify(body)


func build_headers() -> PackedStringArray:
	return [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]


func process_response(body: PackedByteArray) -> String:
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		return ""
	var response: Dictionary = json.get_data()
	var choices: Array = response.get(&"choices", [])
	if choices.is_empty():
		return ""
	var message_content: String = choices[0].get(&"message", {}).get(&"content", "")
	add_message(&"assistant", message_content)
	return message_content


static func get_default_models() -> Array[Dictionary]:
	return [
		{&"name": "GPT-4o Mini", &"id": "gpt-4o-mini", &"url": "https://api.openai.com/v1/chat/completions"},
		{&"name": "GPT-4o", &"id": "gpt-4o", &"url": "https://api.openai.com/v1/chat/completions"},
		{&"name": "Claude 3 Haiku", &"id": "claude-3-haiku-20240307", &"url": "https://api.anthropic.com/v1/messages"},
		{&"name": "Llama 3 70B (Groq)", &"id": "llama3-70b-8192", &"url": "https://api.groq.com/openai/v1/chat/completions"},
		{&"name": "DeepSeek V3", &"id": "deepseek-chat", &"url": "https://api.deepseek.com/v1/chat/completions"},
	]
