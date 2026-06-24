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
## HudModServer - Lightweight HTTP server for remote control via terminal ##
## Listens on http://127.0.0.1:9876, accepts JSON commands                ##
#############################################################################
extends Node

const PORT: int = 9876

var _server: TCPServer
var _bufs: Array[String] = []
var _conns: Array[StreamPeerTCP] = []

var _clipboard_clips: Array[MediaClipRes] = []

class ChangeEntry:
	var timestamp: float
	var actor: String
	var action: String
	var target: String
	var details: Dictionary
	var snapshot_before: String

func _init():
	pass

var _changes_log: Array[Dictionary] = []
var _snapshots: Dictionary = {}
var _snapshot_counter: int = 0

const _PERSIST_DIR: String = "user://hms_persist"
const _CHANGES_FILE: String = "changes_log.json"
const _SNAPSHOTS_FILE: String = "snapshots.json"

func _persist_path(filename: String) -> String:
	return ProjectSettings.globalize_path(_PERSIST_DIR) + "/" + filename

func _persist_save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_PERSIST_DIR))
	var f1: FileAccess = FileAccess.open(_persist_path(_CHANGES_FILE), FileAccess.WRITE)
	if f1:
		f1.store_string(JSON.new().stringify(_changes_log.slice(-500)))
		f1.close()
	var f2: FileAccess = FileAccess.open(_persist_path(_SNAPSHOTS_FILE), FileAccess.WRITE)
	if f2:
		f2.store_string(JSON.new().stringify({"counter": _snapshot_counter, "data": _snapshots}))
		f2.close()

func _persist_load() -> void:
	var p1: String = _persist_path(_CHANGES_FILE)
	if FileAccess.file_exists(p1):
		var f: FileAccess = FileAccess.open(p1, FileAccess.READ)
		if f:
			var j: JSON = JSON.new()
			if j.parse(f.get_as_text()) == OK and j.data is Array:
				_changes_log.clear()
				for entry in j.data:
					if entry is Dictionary:
						_changes_log.append(entry)
			f.close()
	var p2: String = _persist_path(_SNAPSHOTS_FILE)
	if FileAccess.file_exists(p2):
		var f2: FileAccess = FileAccess.open(p2, FileAccess.READ)
		if f2:
			var j2: JSON = JSON.new()
			if j2.parse(f2.get_as_text()) == OK and j2.data is Dictionary:
				_snapshot_counter = j2.data.get("counter", 0)
				_snapshots = j2.data.get("data", {})
			f2.close()

func _ready() -> void:
	_persist_load()
	_start_server()


func _start_server() -> void:
	_server = TCPServer.new()
	var err: Error = _server.listen(PORT, "127.0.0.1")
	if err != OK:
		push_error("HudModServer: Cannot listen on 127.0.0.1:", PORT, " (error ", err, ")")
		return
	print("HudModServer: Listening on http://127.0.0.1:", PORT)


func _process(_delta: float) -> void:
	if not _server:
		return
	
	while _server.is_connection_available():
		var conn: StreamPeerTCP = _server.take_connection()
		conn.set_no_delay(true)
		_conns.append(conn)
		_bufs.append("")
	
	var i: int = 0
	while i < _conns.size():
		var conn: StreamPeerTCP = _conns[i]
		if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.remove_at(i)
			_bufs.remove_at(i)
			continue
		
		var avail: int = conn.get_available_bytes()
		if avail <= 0:
			i += 1
			continue
		
		var result: Array = conn.get_data(avail)
		if result[0] != OK:
			_conns.remove_at(i)
			_bufs.remove_at(i)
			continue
		
		_bufs[i] += (result[1] as PackedByteArray).get_string_from_utf8()
		var raw: String = _bufs[i]
		
		var header_end: int = raw.find("\r\n\r\n")
		if header_end == -1:
			i += 1
			continue
		
		var body_start: int = header_end + 4
		var content_length: int = 0
		for line: String in raw.substr(0, header_end).split("\r\n"):
			if line.findn("content-length:") == 0:
				content_length = line.substr(15).strip_edges().to_int()
				break
		
		var expected: int = body_start + content_length
		if raw.length() < expected:
			i += 1
			continue
		
		var body: String = raw.substr(body_start, content_length)
		var first_line: String = raw.substr(0, raw.find("\r\n"))
		var parts: PackedStringArray = first_line.split(" ")
		var method: String = parts[0] if parts.size() > 0 else "GET"
		
		if method == "GET" and body.is_empty():
			_send_status(conn)
			_conns.remove_at(i)
			_bufs.remove_at(i)
			continue
		
		if body.is_empty():
			_send_error(conn, "Empty body")
			_conns.remove_at(i)
			_bufs.remove_at(i)
			continue
		
		var req: Dictionary = _try_parse_json(body)
		if req.is_empty():
			_send_error(conn, "Invalid JSON")
			_conns.remove_at(i)
			_bufs.remove_at(i)
			continue
		
		_dispatch(conn, req)
		_conns.remove_at(i)
		_bufs.remove_at(i)


func _try_parse_json(body: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(body) == OK:
		return json.data
	
	var fixed: String = body.replace("'", "\"")
	if json.parse(fixed) == OK:
		return json.data
	
	for pair: String in body.split("&"):
		var kv: PackedStringArray = pair.split("=", true, 1)
		if kv.size() == 2:
			var result: Dictionary = {}
			result[kv[0]] = kv[1]
			return result
	
	if body.begins_with("{") and body.ends_with("}"):
		body = body.substr(1, body.length() - 2)
		var result: Dictionary = {}
		for raw_pair: String in body.split(","):
			var kv: PackedStringArray = raw_pair.split(":", true, 1)
			if kv.size() != 2: continue
			var k: String = kv[0].strip_edges().trim_prefix('"').trim_suffix('"')
			var v: String = kv[1].strip_edges().trim_prefix('"').trim_suffix('"')
			result[k] = v
		if not result.is_empty():
			return result
	
	return {}


func _send_status(conn: StreamPeerTCP) -> void:
	_send_response(conn, 200, {"status": "alive", "info": "HudModServer running"})

func _send_error(conn: StreamPeerTCP, msg: String) -> void:
	_send_response(conn, 400, {"error": msg})

func _dispatch(conn: StreamPeerTCP, req: Dictionary) -> void:
	var cmd: String = req.get("cmd", "")
	match cmd:
		"eval":
			_cmd_eval(conn, req)
		"exec":
			_cmd_exec(conn, req)
		"read":
			_cmd_read(conn, req)
		"write":
			_cmd_write(conn, req)
		"edit":
			_cmd_edit(conn, req)
		"ls":
			_cmd_ls(conn, req)
		"status":
			_cmd_status(conn, req)
		"screenshot":
			_cmd_screenshot(conn, req)
		"frame":
			_cmd_frame(conn, req)
		"flip":
			_cmd_flip(conn, req)
		"opacity":
			_cmd_opacity(conn, req)
		"load_video":
			_cmd_load_video(conn, req)
		"inspect":
			_cmd_inspect(conn, req)
		"discover":
			_cmd_discover(conn, req)
		"capabilities":
			_cmd_capabilities(conn, req)
		"project_new":
			_cmd_project_new(conn, req)
		"project_open":
			_cmd_project_open(conn, req)
		"project_save":
			_cmd_project_save(conn, req)
		"project_save_as":
			_cmd_project_save_as(conn, req)
		"project_info":
			_cmd_project_info(conn, req)
		"project_settings":
			_cmd_project_settings(conn, req)
		"layer_list":
			_cmd_layer_list(conn, req)
		"layer_add":
			_cmd_layer_add(conn, req)
		"layer_remove":
			_cmd_layer_remove(conn, req)
		"layer_move":
			_cmd_layer_move(conn, req)
		"layer_set":
			_cmd_layer_set(conn, req)
		"clip_add":
			_cmd_clip_add(conn, req)
		"clip_remove":
			_cmd_clip_remove(conn, req)
		"clip_move":
			_cmd_clip_move(conn, req)
		"clip_split":
			_cmd_clip_split(conn, req)
		"clip_duplicate":
			_cmd_clip_duplicate(conn, req)
		"clip_info":
			_cmd_clip_info(conn, req)
		"clip_list":
			_cmd_clip_list(conn, req)
		"clip_set":
			_cmd_clip_set(conn, req)
		"comp_list":
			_cmd_comp_list(conn, req)
		"comp_list_available":
			_cmd_comp_list_available(conn, req)
		"comp_add":
			_cmd_comp_add(conn, req)
		"comp_remove":
			_cmd_comp_remove(conn, req)
		"comp_move":
			_cmd_comp_move(conn, req)
		"comp_set":
			_cmd_comp_set(conn, req)
		"comp_get":
			_cmd_comp_get(conn, req)
		"render_start":
			_cmd_render_start(conn, req)
		"render_cancel":
			_cmd_render_cancel(conn, req)
		"render_settings":
			_cmd_render_settings(conn, req)
		"playback_play":
			_cmd_playback_play(conn, req)
		"playback_stop":
			_cmd_playback_stop(conn, req)
		"playback_seek":
			_cmd_playback_seek(conn, req)
		"playback_set":
			_cmd_playback_set(conn, req)
		"media_list":
			_cmd_media_list(conn, req)
		"media_register":
			_cmd_media_register(conn, req)
		"media_remove":
			_cmd_media_remove(conn, req)
		"undo":
			_cmd_undo(conn, req)
		"redo":
			_cmd_redo(conn, req)
		"timemarker_add":
			_cmd_timemarker_add(conn, req)
		"timemarker_remove":
			_cmd_timemarker_remove(conn, req)
		"timemarker_list":
			_cmd_timemarker_list(conn, req)
		"editor_settings":
			_cmd_editor_settings(conn, req)
		"keyframe_add":
			_cmd_keyframe_add(conn, req)
		"keyframe_remove":
			_cmd_keyframe_remove(conn, req)
		"keyframe_list":
			_cmd_keyframe_list(conn, req)
		"context":
			_cmd_context(conn, req)
		"transcribe":
			_cmd_transcribe(conn, req)
		"clip_copy":
			_cmd_clip_copy(conn, req)
		"clip_paste":
			_cmd_clip_paste(conn, req)
		"clip_import":
			_cmd_clip_import(conn, req)
		"clip_trim":
			_cmd_clip_trim(conn, req)
		"text_add":
			_cmd_text_add(conn, req)
		"text_set":
			_cmd_text_set(conn, req)
		"media_import":
			_cmd_media_import(conn, req)
		"comp_enable":
			_cmd_comp_enable(conn, req)
		"comp_disable":
			_cmd_comp_disable(conn, req)
		"layer_duplicate":
			_cmd_layer_duplicate(conn, req)
		"timeline_goto":
			_cmd_timeline_goto(conn, req)
		"timeline_length":
			_cmd_timeline_length(conn, req)
		"changes_log":
			_cmd_changes_log(conn, req)
		"changes_clear":
			_cmd_changes_clear(conn, req)
		"snapshot":
			_cmd_snapshot(conn, req)
		"diff":
			_cmd_diff(conn, req)
		"review":
			_cmd_review(conn, req)
		"project_state":
			_cmd_project_state(conn, req)
		"style_analyze":
			_cmd_style_analyze(conn, req)
		"style_list":
			_cmd_style_list(conn, req)
		"style_info":
			_cmd_style_info(conn, req)
		"style_delete":
			_cmd_style_delete(conn, req)
		"style_compare":
			_cmd_style_compare(conn, req)
		"style_apply":
			_cmd_style_apply(conn, req)
		"style_teach_start":
			_cmd_style_teach_start(conn, req)
		"style_teach_log":
			_cmd_style_teach_log(conn, req)
		"style_teach_ask":
			_cmd_style_teach_ask(conn, req)
		"style_teach_answer":
			_cmd_style_teach_answer(conn, req)
		"style_teach_end":
			_cmd_style_teach_end(conn, req)
		"style_practice":
			_cmd_style_practice(conn, req)
		"style_evaluate":
			_cmd_style_evaluate(conn, req)
		"style_sessions":
			_cmd_style_sessions(conn, req)
		"style_session_load":
			_cmd_style_session_load(conn, req)
		_:
			_send_response(conn, 400, {"error": "Unknown command: " + cmd, "hint": "Use capabilities command for full list"})


func _send_response(conn: StreamPeerTCP, status_code: int, data: Dictionary) -> void:
	var status_text: String = "OK" if status_code == 200 else "Error"
	var body: String = JSON.new().stringify(data)
	var response: String = "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n%s" % [status_code, status_text, body.length(), body]
	conn.put_data(response.to_utf8_buffer())
	conn.poll()
	conn.disconnect_from_host()


func _send_binary_response(conn: StreamPeerTCP, status_code: int, mime: String, data: PackedByteArray) -> void:
	var status_text: String = "OK" if status_code == 200 else "Error"
	var header: String = "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" % [status_code, status_text, mime, data.size()]
	var response: PackedByteArray = header.to_utf8_buffer() + data
	conn.put_data(response)
	conn.poll()
	conn.disconnect_from_host()


func _capture_viewport_png() -> PackedByteArray:
	if not Scene2 or not Scene2.viewport:
		return PackedByteArray()
	var vp: SubViewport = Scene2.viewport
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	if img.is_empty():
		return PackedByteArray()
	return img.save_png_to_buffer()


func _cmd_screenshot(conn: StreamPeerTCP, req: Dictionary) -> void:
	var png: PackedByteArray = await _capture_viewport_png()
	if png.is_empty():
		_send_response(conn, 500, {"error": "Failed to capture viewport"})
		return
	_send_binary_response(conn, 200, "image/png", png)


func _cmd_frame(conn: StreamPeerTCP, req: Dictionary) -> void:
	var frame: int = req.get("frame", -1)
	if frame >= 0:
		PlaybackServer.position = frame
		await get_tree().process_frame
	var png: PackedByteArray = await _capture_viewport_png()
	if png.is_empty():
		_send_response(conn, 500, {"error": "Failed to capture frame"})
		return
	_send_binary_response(conn, 200, "image/png", png)


func _cmd_eval(conn: StreamPeerTCP, req: Dictionary) -> void:
	var code: String = req.get("code", "").strip_edges()
	if code.is_empty():
		_send_response(conn, 400, {"error": "Empty code"})
		return
	var is_simple: bool = not (";" in code) and not ("\n" in code) and not ("var " in code)
	if is_simple:
		_cmd_run_script(conn, "return (" + code + ")")
	else:
		_cmd_run_script(conn, code)


func _cmd_exec(conn: StreamPeerTCP, req: Dictionary) -> void:
	var code: String = req.get("code", "").strip_edges()
	if code.is_empty():
		_send_response(conn, 400, {"error": "Empty code"})
		return
	_cmd_run_script(conn, code)


func _cmd_run_script(conn: StreamPeerTCP, body: String) -> void:
	var gdscript: GDScript = GDScript.new()
	gdscript.source_code = "extends Node\nfunc _run():\n\t" + body.replace("\n", "\n\t")
	var err: Error = gdscript.reload()
	if err != OK:
		_send_response(conn, 400, {"error": "Script error (check syntax)", "hint": "For multi-statement code, include 'return' before the last value. For single expressions, just write the expression."})
		return
	
	var obj: Node = gdscript.new()
	var result = obj._run()
	var out: String = var_to_str(result) if result != null else "null"
	obj.free()
	_send_response(conn, 200, {"result": out})


func _cmd_read(conn: StreamPeerTCP, req: Dictionary) -> void:
	var file: String = req.get("file", "")
	if file.is_empty():
		_send_response(conn, 400, {"error": "Empty file"})
		return
	
	var path: String = _resolve_path(file)
	if not FileAccess.file_exists(path):
		_send_response(conn, 404, {"error": "File not found: " + file})
		return
	
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not f:
		_send_response(conn, 500, {"error": "Could not open: " + file})
		return
	
	var content: String = f.get_as_text()
	f.close()
	_send_response(conn, 200, {"file": file, "content": content})


func _cmd_write(conn: StreamPeerTCP, req: Dictionary) -> void:
	var file: String = req.get("file", "")
	var content: String = req.get("content", "")
	if file.is_empty():
		_send_response(conn, 400, {"error": "Empty file"})
		return
	
	var path: String = _resolve_path(file)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		_send_response(conn, 500, {"error": "Could not write: " + file})
		return
	
	f.store_string(content)
	f.close()
	_send_response(conn, 200, {"result": "written", "file": file})


func _cmd_edit(conn: StreamPeerTCP, req: Dictionary) -> void:
	var file: String = req.get("file", "")
	var old_string: String = req.get("old", "")
	var new_string: String = req.get("new", "")
	var replace_all: bool = req.get("replace_all", false)
	
	if file.is_empty():
		_send_response(conn, 400, {"error": "Empty file"})
		return
	
	var path: String = _resolve_path(file)
	if not FileAccess.file_exists(path):
		_send_response(conn, 404, {"error": "File not found: " + file})
		return
	
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not f:
		_send_response(conn, 500, {"error": "Could not open: " + file})
		return
	
	var content: String = f.get_as_text()
	f.close()
	
	if replace_all:
		if old_string not in content:
			_send_response(conn, 404, {"error": "old_string not found"})
			return
		var count: int = content.count(old_string)
		content = content.replace(old_string, new_string)
		f = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(content)
		f.close()
		_send_response(conn, 200, {"result": "edited", "file": file, "replacements": count})
	else:
		var idx: int = content.find(old_string)
		if idx == -1:
			_send_response(conn, 404, {"error": "old_string not found"})
			return
		content = content.substr(0, idx) + new_string + content.substr(idx + old_string.length())
		f = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(content)
		f.close()
		_send_response(conn, 200, {"result": "edited", "file": file})


func _cmd_ls(conn: StreamPeerTCP, req: Dictionary) -> void:
	var path: String = req.get("path", "res://")
	var resolved: String = _resolve_path(path)
	
	var dir: DirAccess = DirAccess.open(resolved)
	if not dir:
		_send_response(conn, 404, {"error": "Directory not found: " + path})
		return
	
	var files: Array[Dictionary] = []
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var is_dir: bool = dir.current_is_dir()
		if is_dir:
			name += "/"
		files.append({"name": name, "dir": is_dir})
		name = dir.get_next()
	
	_send_response(conn, 200, {"path": path, "files": files})


func _cmd_status(conn: StreamPeerTCP, req: Dictionary) -> void:
	var data: Dictionary = {
		"project_open": ProjectServer2.project_path != null,
		"is_rendering": Renderer.is_working,
		"is_paused": Renderer.is_paused
	}
	
	if ProjectServer2.project_res:
		data["project_name"] = ProjectServer2.project_res.project_name
		data["fps"] = ProjectServer2.project_res.fps
		data["width"] = ProjectServer2.project_res.resolution.x
		data["height"] = ProjectServer2.project_res.resolution.y
		data["length_frames"] = ProjectServer2.project_res.root_clip_res.length
	
	_send_response(conn, 200, data)


func _cmd_edit_clips(conn: StreamPeerTCP, do_flip: bool, set_opacity: float) -> void:
	if not ProjectServer2.project_res or not ProjectServer2.project_res.root_clip_res:
		_send_response(conn, 400, {"error": "No project open"})
		return
	
	var count: int = 0
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	for layer: LayerRes in root.layers:
		for clip_frame: int in layer.clips:
			var clip: MediaClipRes = layer.clips[clip_frame]
			for comp: ComponentRes in clip.get_section_comps_absolute(&"Display2D"):
				if do_flip:
					var s_val = comp.get("scale")
					var s: Vector2 = Vector2.ONE if s_val == null else s_val
					comp.set("scale", Vector2(s.x * -1.0, s.y))
				if set_opacity >= 0.0:
					comp.set("opacity", set_opacity)
				count += 1
	
	PlaybackServer.position = PlaybackServer.position
	Scene2.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_send_response(conn, 200, {"result": "done", "clips": count})


func _cmd_flip(conn: StreamPeerTCP, req: Dictionary) -> void:
	_cmd_edit_clips(conn, true, -1.0)

func _cmd_opacity(conn: StreamPeerTCP, req: Dictionary) -> void:
	var raw = req.get("value")
	if raw == null:
		_send_response(conn, 400, {"error": "Missing 'value' field (0.0 to 1.0)"})
		return
	var val: float = float(str(raw))
	if val < 0.0 or val > 1.0:
		_send_response(conn, 400, {"error": "Opacity must be between 0.0 and 1.0"})
		return
	_cmd_edit_clips(conn, false, val)


func _cmd_load_video(conn: StreamPeerTCP, req: Dictionary) -> void:
	var path: String = req.get("path", "")
	if path.is_empty():
		_send_response(conn, 400, {"error": "Missing 'path' parameter"})
		return
	if not FileAccess.file_exists(path):
		_send_response(conn, 404, {"error": "Video file not found: " + path})
		return
	if MediaCache.video_contexts_has(path):
		_send_response(conn, 200, {"result": "already_registered", "path": path})
		return
	
	var video_decoder: VideoDecoder = VideoDecoder.new()
	video_decoder.set_internal_enhance(false)
	video_decoder.set_video_path(path)
	
	var opened: bool = false
	for try_time: int in 5:
		if video_decoder.open():
			opened = true
			break
	
	if not opened:
		_send_response(conn, 500, {"error": "Could not open video with VideoDecoder"})
		return
	
	var total_frames: int = video_decoder.get_total_frames_native()
	if total_frames < 1:
		total_frames = video_decoder.get_total_frames_by_timebase()
		if total_frames < 1:
			total_frames = video_decoder.get_total_frames_by_dur()
	
	var ctx: MediaCache.VideoContext = MediaCache.VideoContext.new()
	ctx.video_path = path
	ctx.resolution = video_decoder.get_resolution()
	ctx.duration = video_decoder.get_duration()
	ctx.fps = video_decoder.get_fps()
	ctx.total_frames = total_frames
	ctx.bit_depth = video_decoder.get_bit_depth()
	
	MediaCache.video_contexts[path] = ctx
	
	var streams_data: Array[PackedByteArray] = AudioHelper.create_data_from_path(path)
	var audio_data_res = null if streams_data.is_empty() else MediaCache.AudioF32Data.new(streams_data[0])
	MediaCache.audio_datas[path] = audio_data_res
	
	var ids_exists: PackedStringArray = EditorServer.get_ids_from_pathes(DirAccess.get_files_at(ProjectServer2.project_thumbnail_path))
	MediaServer.server_register_video(path, video_decoder, audio_data_res, ids_exists, "", "", "")
	
	_send_response(conn, 200, {
		"result": "registered",
		"path": path,
		"resolution": str(ctx.resolution.x) + "x" + str(ctx.resolution.y),
		"fps": ctx.fps,
		"duration_sec": ctx.duration,
		"total_frames": total_frames
	})


func _cmd_inspect(conn: StreamPeerTCP, req: Dictionary) -> void:
	var target: String = req.get("target", "")
	if target.is_empty():
		var names: PackedStringArray = []
		for child: Node in get_tree().root.get_children():
			if child.get_script() or child.get_child_count() > 0:
				names.append(child.name)
		_send_response(conn, 200, {"autoloads": names, "hint": "Use inspect with 'target' parameter e.g. {\"cmd\":\"inspect\",\"target\":\"ProjectServer2\"}"})
		return

	var obj = get_tree().root.get_node_or_null(target)
	if not obj:
		_send_response(conn, 404, {"error": "Target not found: " + target})
		return

	var methods: Array[Dictionary] = []
	for m in obj.get_method_list():
		if m.name.begins_with("_"):
			continue
		var args: Array = []
		for a in m.args:
			args.append({"name": a.name, "type": a.type})
		methods.append({"name": m.name, "args": args, "return_type": m.return.type if m.has("return") else -1})

	var properties: Array[Dictionary] = []
	for p in obj.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			properties.append({"name": p.name, "type": p.type, "hint": p.hint_string})

	var signals: Array[Dictionary] = []
	for s in obj.get_signal_list():
		if s.name.begins_with("_"):
			continue
		var args: Array = []
		for a in s.args:
			args.append({"name": a.name, "type": a.type})
		signals.append({"name": s.name, "args": args})

	_send_response(conn, 200, {
		"target": target,
		"type": obj.get_class(),
		"methods": methods,
		"properties": properties,
		"signals": signals
	})


func _parse_source_functions(src_path: String) -> Array[Dictionary]:
	var f: FileAccess = FileAccess.open(src_path, FileAccess.READ)
	if not f: return []
	var src: String = f.get_as_text()
	f.close()
	var lines: PackedStringArray = src.split("\n")
	var funcs: Array[Dictionary] = []
	var i: int = 0
	while i < lines.size():
		var line: String = lines[i].strip_edges()
		if line.begins_with("func ") and not line.begins_with("func _"):
			var comment: String = ""
			var j: int = i - 1
			while j >= 0:
				var pl: String = lines[j].strip_edges()
				if pl.begins_with("#"):
					var p: String = pl.trim_prefix("#").strip_edges()
					if comment == "":
						comment = p
					else:
						comment = p + " | " + comment
				elif pl.is_empty():
					if comment != "":
						break
				else:
					break
				j -= 1
			var brace: int = line.find("(")
			if brace != -1:
				var name_end: int = line.substr(0, brace).find(" ")
				var fname: String = line.substr(name_end + 1, brace - name_end - 1).strip_edges()
				funcs.append({"name": fname, "signature": line, "comment": comment.strip_edges()})
		i += 1
	return funcs


func _cmd_discover(conn: StreamPeerTCP, req: Dictionary) -> void:
	var target: String = req.get("target", "all")
	
	if target == "all":
		var names: PackedStringArray = []
		for child: Node in get_tree().root.get_children():
			if child.get_script() or child.get_child_count() > 0:
				names.append(child.name)
		_send_response(conn, 200, {
			"autoloads": names,
			"hint": "Use discover with 'target'=autoload_name (e.g. MediaServer, ProjectServer2, Renderer) or 'target'=all_workflows"
		})
		return
	
	if target == "all_workflows":
		var workflows: Array[Dictionary] = []
		for child: Node in get_tree().root.get_children():
			if not child.get_script(): continue
			var script: Script = child.get_script()
			var src_path: String = script.resource_path
			if not src_path.begins_with("res://"): continue
			var funcs: Array[Dictionary] = _parse_source_functions(src_path)
			if not funcs.is_empty():
				workflows.append({"name": child.name, "path": src_path, "functions": funcs})
		
		var extra_paths: Array[Dictionary] = [
			{"name": "ProjectRes", "path": "res://Build/Res/ProjectRes.gd"},
			{"name": "RootClipRes", "path": "res://Build/Res/MediaClipRes/RootClipRes.gd"},
			{"name": "LayerRes", "path": "res://Build/Res/MediaClipRes/LayerRes.gd"},
			{"name": "MediaClipRes", "path": "res://Build/Res/MediaClipRes/MediaClipRes.gd"},
			{"name": "VideoClipRes", "path": "res://Build/Res/MediaClipRes/VideoClipRes.gd"},
			{"name": "CompCanvasItem", "path": "res://Build/Res/Component/CanvasItem.gd"},
			{"name": "Display2DClipRes", "path": "res://Build/Res/MediaClipRes/Display2DClipRes.gd"}
		]
		for ec: Dictionary in extra_paths:
			var funcs: Array[Dictionary] = _parse_source_functions(ec.path)
			if not funcs.is_empty():
				workflows.append({"name": ec.name, "path": ec.path, "functions": funcs})
		
		_send_response(conn, 200, {"workflows": workflows})
		return
	
	var obj = get_tree().root.get_node_or_null(target)
	if obj and obj.get_script():
		var script: Script = obj.get_script()
		var src_path: String = script.resource_path
		var funcs: Array[Dictionary] = _parse_source_functions(src_path)
		_send_response(conn, 200, {"target": target, "source": src_path, "functions": funcs})
		return
	
	_send_response(conn, 404, {"error": "Target not found: " + target, "hint": "Use 'all' to list autoloads or 'all_workflows' for full map"})


func _cmd_capabilities(_conn: StreamPeerTCP, _req: Dictionary) -> void:
	var caps: Dictionary = {
		"categories": [
			{
				"name": "Project Management",
				"functions": [
					{"cmd": "project_new", "desc": "Create new project", "params": {"name": "str (optional)", "dir": "str (required)", "fps": "int (optional, default 30)", "width": "int (1920)", "height": "int (1080)"}},
					{"cmd": "project_open", "desc": "Open existing project", "params": {"dir": "str (path to project folder)"}},
					{"cmd": "project_save", "desc": "Save current project"},
					{"cmd": "project_save_as", "desc": "Save project to new location", "params": {"dir": "str (target path)"}},
					{"cmd": "project_info", "desc": "Get full project details: name, fps, resolution, layers, clips, playback state"},
					{"cmd": "project_settings", "desc": "Get or set project settings", "params": {"name": "str", "fps": "int", "width": "int", "height": "int"}},
					{"eval": "ProjectServer2.new_project(project_res, dir_path)", "desc": "Create new project (advanced)"},
					{"eval": "ProjectServer2.open_project(path)", "desc": "Open project by path"},
					{"eval": "ProjectServer2.save()", "desc": "Save project via eval"},
					{"eval": "ProjectServer2.save_as(dir_path)", "desc": "Save as via eval"}
				]
			},
			{
				"name": "Layers",
				"functions": [
					{"cmd": "layer_list", "desc": "List all layers with clips, properties, mute/volume"},
					{"cmd": "layer_add", "desc": "Add a new layer", "params": {"index": "int (optional, default end)"}},
					{"cmd": "layer_remove", "desc": "Remove layer by index", "params": {"index": "int"}},
					{"cmd": "layer_move", "desc": "Move layer from one index to another", "params": {"from": "int", "to": "int"}},
					{"cmd": "layer_set", "desc": "Set layer properties", "params": {"index": "int", "name": "str", "locked": "bool", "hidden": "bool", "color": "str (hex)", "mute": "bool (root only)", "volume": "float (0-1, root only)"}},
					{"eval": "root_clip_res.add_layer(idx)", "desc": "Add layer via eval"},
					{"eval": "root_clip_res.remove_layer(idx)", "desc": "Remove layer via eval"},
					{"eval": "root_clip_res.move_layer(from, to)", "desc": "Move layer via eval"}
				]
			},
			{
				"name": "Clips",
				"functions": [
					{"cmd": "clip_list", "desc": "List clips in specific layer or all layers", "params": {"layer": "int (optional, omit for all)"}},
					{"cmd": "clip_info", "desc": "Get full clip details with components and properties", "params": {"layer": "int", "frame": "int"}},
					{"cmd": "clip_add", "desc": "Add clip to layer", "params": {"layer": "int", "frame": "int", "media": "str (path) or type (classname)", "length": "int (frames)"}},
					{"cmd": "clip_remove", "desc": "Remove clip from layer", "params": {"layer": "int", "frame": "int"}},
					{"cmd": "clip_move", "desc": "Move clip to new position", "params": {"from_layer": "int", "from_frame": "int", "to_layer": "int", "to_frame": "int"}},
					{"cmd": "clip_split", "desc": "Split clip at position", "params": {"layer": "int", "frame": "int", "split_pos": "int"}},
					{"cmd": "clip_duplicate", "desc": "Duplicate clip", "params": {"layer": "int", "frame": "int"}},
					{"cmd": "clip_set", "desc": "Set clip properties (from, length)", "params": {"layer": "int", "frame": "int", "from": "int", "length": "int"}},
					{"eval": "root_clip_res.split_clip(layer, frame, split_pos, true, true)", "desc": "Split clip (advanced)"},
					{"eval": "root_clip_res.split_clips(coords, split_pos, true, true)", "desc": "Split multiple clips"},
					{"eval": "root_clip_res.add_clips(layer, frame, [clip1, clip2], method)", "desc": "Add multiple clips", "method_hint": "0=place_on_top, 1=insert, 2=overwrite, 3=fit_to_fill, 4=replace"},
					{"eval": "root_clip_res.remove_clips([Vector2i(layer, frame)])", "desc": "Remove clips by coord array"},
					{"eval": "root_clip_res.move_clips(from_coords, to_coords, -1)", "desc": "Move clips by coord arrays"}
				]
			},
			{
				"name": "Media Import",
				"functions": [
					{"cmd": "media_list", "desc": "List registered media", "params": {"filter": "'all', 'images', 'videos', 'audio'"}},
					{"cmd": "media_register", "desc": "Register a media file in the project cache", "params": {"path": "str (full file path)"}},
					{"cmd": "media_remove", "desc": "Deregister media from cache", "params": {"path": "str"}},
					{"eval": "MediaCache.register_video(path, ids, id, thumb, wave)", "desc": "Register video in cache"},
					{"eval": "MediaCache.register_image(path, ids, id, thumb)", "desc": "Register image in cache"},
					{"eval": "MediaCache.register_audio(path, ids, id, thumb, wave)", "desc": "Register audio in cache"},
					{"eval": "MediaServer.get_media_type_from_path(path)", "desc": "Detect media type by file extension"},
					{"eval": "MediaCache.get_video_context(path)", "desc": "Get video metadata: resolution, fps, duration, frames"},
					{"eval": "MediaCache.get_image(path)", "desc": "Get registered image"},
					{"eval": "MediaCache.get_audio_data(path)", "desc": "Get registered audio data"},
					{"eval": "MediaCache.load_media_cache_from_file_system(fs)", "desc": "Bulk register all media from project file system"}
				]
			},
			{
				"name": "Components (Effects & Filters)",
				"functions": [
					{"cmd": "comp_list", "desc": "List all available component sections and types"},
					{"cmd": "comp_list_available", "desc": "List all component class names and clip types"},
					{"cmd": "comp_add", "desc": "Add component to clip", "params": {"layer": "int", "frame": "int", "section": "str (e.g. Display2D, Image, Color)", "type": "str (component classname)"}},
					{"cmd": "comp_remove", "desc": "Remove component from clip", "params": {"layer": "int", "frame": "int", "section": "str", "index": "int"}},
					{"cmd": "comp_move", "desc": "Reorder component", "params": {"layer": "int", "frame": "int", "section": "str", "from": "int", "to": "int"}},
					{"cmd": "comp_set", "desc": "Set component property", "params": {"layer": "int", "frame": "int", "section": "str", "index": "int", "property": "str", "value": "any (or dict with type hint)"}},
					{"cmd": "comp_get", "desc": "Get component properties", "params": {"layer": "int", "frame": "int", "section": "str", "index": "int"}},

					{"name": "CompCanvasItem (Transform Properties)", "desc": "Built-in Display2D component for all clips", "eval_hint": "clip.get_section_comps_absolute('Display2D')[0]"},
					{"eval": "comp.set('position', Vector2(x,y))", "desc": "Set clip position on canvas"},
					{"eval": "comp.set('scale', Vector2(x,y))", "desc": "Set clip scale"},
					{"eval": "comp.set('rotation_degrees', val)", "desc": "Set clip rotation in degrees"},
					{"eval": "comp.set('skew', val)", "desc": "Set clip skew"},
					{"eval": "comp.set('modulate', Color(r,g,b,a))", "desc": "Set clip color tint"},
					{"eval": "comp.set('opacity', val)", "desc": "Set clip opacity 0.0-1.0"},
					{"eval": "comp.set('blend_mode', int)", "desc": "Set blend mode (0=normal, 1=darken, etc)"},
					{"eval": "comp.set('show_behind_parent', bool)", "desc": "Show behind parent toggle"},
					{"eval": "comp.set('clip_children', int)", "desc": "Clip children mode"},
					{"eval": "comp.set('texture_filter', int)", "desc": "Texture filter mode"},
					{"eval": "comp.set('texture_repeat', int)", "desc": "Texture repeat mode"},

					{"name": "Image Effect Components", "desc": "Available Image section components"},
					{"class": "ChromaKey", "desc": "Green/blue screen keying", "props": "key_color(Color), similarity(0-1), smoothness(0-1), spill_removal(0-1)"},
					{"class": "Invert", "desc": "Invert colors"},
					{"class": "Mask", "desc": "Mask effect"},
					{"class": "Offset", "desc": "Offset effect"},
					{"class": "Perspective", "desc": "Perspective transform"},
					{"class": "Sharpen", "desc": "Sharpen image"},
					{"class": "Kawahara", "desc": "Kawahara sharpen filter"},
					{"class": "Denoise", "desc": "Denoise filter"},
					{"class": "Clarity", "desc": "Clarity enhancement"},
					{"class": "Vignette", "desc": "Vignette darkening around edges"},
					{"class": "FilmGrain", "desc": "Film grain effect"},
					{"class": "Bars", "desc": "Letterbox bars"},
					{"class": "VHS", "desc": "VHS tape effect"},
					{"class": "LEDGrid", "desc": "LED grid effect"},
					{"class": "Glitch", "desc": "Glitch effect"},
					{"class": "GlitchWeird", "desc": "Weird glitch effect"},
					{"class": "Voronoi", "desc": "Voronoi pattern"},
					{"class": "ToonEdge", "desc": "Toon/cartoon edge"},
					{"class": "Sketch", "desc": "Sketch effect"},
					{"class": "Posterize", "desc": "Posterize colors"},
					{"class": "Pixelate", "desc": "Pixelation effect"},
					{"class": "Hexagon", "desc": "Hexagon pattern"},
					{"class": "Halftone", "desc": "Halftone pattern"},
					{"class": "Emboss", "desc": "Emboss effect"},
					{"class": "BlurRotational", "desc": "Rotational blur"},
					{"class": "BlurRay", "desc": "Ray blur"},
					{"class": "BlurMotion", "desc": "Motion blur"},
					{"class": "DistTwirl", "desc": "Twirl distortion"},
					{"class": "DistRipple", "desc": "Ripple distortion"},
					{"class": "DistLens", "desc": "Lens distortion"},
					{"class": "DistHeat", "desc": "Heat haze distortion"},
					{"class": "DistBulge", "desc": "Bulge distortion"},
					{"class": "Rays", "desc": "Light rays"},
					{"class": "RadialChromaticAberration", "desc": "Radial chromatic aberration"},
					{"class": "LensFlare", "desc": "Lens flare"},
					{"class": "Glow", "desc": "Glow effect"},
					{"class": "DirectionalChromaticAberration", "desc": "Directional chromatic aberration"},

					{"name": "Color Components", "desc": "Available Color section components"},
					{"class": "LGG", "desc": "Log/Lift/Gamma/Gain color correction"},
					{"class": "Tone", "desc": "Tone color adjustment"},
					{"class": "WhiteBalance", "desc": "White balance correction"},
					{"class": "HSL", "desc": "HSL color grading"},
					{"class": "HSLPerColor", "desc": "HSL per-color grading"},

					{"name": "Display2D Components", "desc": "Available Display2D section components"},
					{"class": "DrawArrow", "desc": "Draw arrow shape"},
					{"class": "DrawCircle", "desc": "Draw circle shape"},
					{"class": "DrawPolygon", "desc": "Draw polygon shape"},
					{"class": "DrawRect", "desc": "Draw rectangle shape"},
					{"class": "DrawStar", "desc": "Draw star shape"},
					{"class": "Follow", "desc": "Follow transform"},
					{"class": "Shake", "desc": "Camera shake effect"},
					{"class": "Wave2D", "desc": "2D wave effect"},
					{"class": "Fade", "desc": "Fade in/out animation"},
					{"class": "Popup", "desc": "Popup animation"},
					{"class": "Slide", "desc": "Slide animation"},
					{"class": "Swing", "desc": "Swing animation"},

					{"name": "Text Components", "desc": "Available Text section components"},
					{"class": "TextTransform", "desc": "Text transform"},
					{"class": "TextBackground", "desc": "Text background"},
					{"class": "TextMagnet", "desc": "Text magnet shape"},
					{"class": "TextExtrude", "desc": "Text extrude"},
					{"class": "TextCurved", "desc": "Text on curve"},
					{"class": "TextRainbow", "desc": "Rainbow text color"},
					{"class": "TextGradient", "desc": "Gradient text color"},
					{"class": "TextBounce", "desc": "Bouncing text animation"},
					{"class": "TextFlip", "desc": "Flipping text animation"},
					{"class": "TextPulse", "desc": "Pulsing text animation"},
					{"class": "TextShake", "desc": "Shaking text animation"},
					{"class": "TextWave", "desc": "Waving text animation"},
					{"class": "TextWind", "desc": "Wind text animation"},
					{"class": "TextInOutType", "desc": "Text in/out animation"},
					{"class": "TextGenShape", "desc": "Text generation shape"},

					{"name": "Particles Components", "desc": "Available Particles section components"},
					{"name": "AudioSettings", "desc": "Sound section - audio volume/pan settings"}
				]
			},
			{
				"name": "Keyframes & Animation",
				"functions": [
					{"cmd": "keyframe_list", "desc": "List all keyframes in a clip", "params": {"layer": "int", "frame": "int"}},
					{"cmd": "keyframe_add", "desc": "Add keyframe to component property", "params": {"layer": "int", "frame": "int (clip)", "section": "str", "comp_index": "int", "property": "str", "keyframe_frame": "int"}},
					{"cmd": "keyframe_remove", "desc": "Remove keyframe", "params": {"layer": "int", "frame": "int (clip)", "section": "str", "comp_index": "int", "property": "str", "keyframe_frame": "int"}},
					{"eval": "comp.set_animated_prop(property, value, frame)", "desc": "Set animated property with keyframe"},
					{"eval": "comp.remove_anim_prop(property, frame)", "desc": "Remove keyframe from property"},
					{"eval": "comp.animations[comp][property]", "desc": "Access AnimationRes for property"},
					{"eval": "anim_res.profiles[i].keys", "desc": "Access curve keys in animation profile"}
				]
			},
			{
				"name": "Playback Control",
				"functions": [
					{"cmd": "playback_play", "desc": "Start video playback"},
					{"cmd": "playback_stop", "desc": "Stop/pause playback"},
					{"cmd": "playback_seek", "desc": "Seek to specific frame", "params": {"frame": "int"}},
					{"cmd": "playback_set", "desc": "Set playback parameters", "params": {"volume": "float 0-1", "replay": "bool"}},
					{"cmd": "frame", "desc": "Seek to frame and capture screenshot as PNG", "params": {"frame": "int"}},
					{"exec": "PlaybackServer.playing=true", "desc": "Start playback via exec"},
					{"exec": "PlaybackServer.playing=false", "desc": "Pause playback via exec"},
					{"eval": "PlaybackServer.position", "desc": "Get current frame position"},
					{"eval": "PlaybackServer.is_playing()", "desc": "Check if playing"},
					{"eval": "PlaybackServer.volume", "desc": "Get current volume"}
				]
			},
			{
				"name": "Render & Export",
				"functions": [
					{"cmd": "render_start", "desc": "Start rendering video", "params": {"output": "str (output file path, optional)"}},
					{"cmd": "render_cancel", "desc": "Cancel rendering"},
					{"cmd": "render_settings", "desc": "Get render settings", "params": {"get": "true"}},
					{"cmd": "status", "desc": "Check render status and project info"},
					{"exec": "Renderer.start(output, video_renderer, audio_renderer)", "desc": "Start render (advanced)"},
					{"exec": "Renderer.cancel()", "desc": "Cancel render"},
					{"exec": "Renderer.pause()", "desc": "Pause render"},
					{"exec": "Renderer.resume()", "desc": "Resume render"},
					{"eval": "Renderer.is_working", "desc": "Check if renderer is working"},
					{"eval": "Renderer.is_paused", "desc": "Check if renderer is paused"}
				]
			},
			{
				"name": "Time Markers",
				"functions": [
					{"cmd": "timemarker_list", "desc": "List all time markers"},
					{"cmd": "timemarker_add", "desc": "Add time marker", "params": {"frame": "int (optional, defaults to current)"}},
					{"cmd": "timemarker_remove", "desc": "Remove time marker", "params": {"frame": "int"}},
					{"eval": "project_res.add_timemarker(frame)", "desc": "Add time marker via eval"},
					{"eval": "project_res.remove_timemarker(frame)", "desc": "Remove time marker via eval"}
				]
			},
			{
				"name": "Editor Settings",
				"functions": [
					{"cmd": "editor_settings", "desc": "Get or set editor settings", "params": {"get": "bool", "replay": "bool", "auto_save_interval": "float"}},
					{"eval": "EditorServer.editor_settings.edit.replay", "desc": "Get replay toggle"},
					{"eval": "EditorServer.editor_settings.performance.frames_dropped", "desc": "Get/set frames dropped for performance"},
					{"eval": "EditorServer.editor_settings.performance.video_scale_factor", "desc": "Get/set video scale factor (0.1-1.0)"},
					{"eval": "EditorServer.editor_settings.performance.video_max_frame_cache", "desc": "Get/set max cached frames"},
					{"eval": "EditorServer.editor_settings.performance.low_quality_for_playback", "desc": "Toggle low quality playback"},
					{"eval": "EditorServer.editor_settings.theme.content_scale", "desc": "Get/set UI content scale"}
				]
			},
			{
				"name": "Clip Types (Spawnable)",
				"functions": [
					{"class": "VideoClipRes", "desc": "Video media clip", "key_prop": "video (path to registered video)"},
					{"class": "ImageClipRes", "desc": "Image media clip", "key_prop": "image (path to registered image)"},
					{"class": "AudioClipRes", "desc": "Audio clip"},
					{"class": "Text2DClipRes", "desc": "2D text overlay clip"},
					{"class": "Display2DClipRes", "desc": "Empty 2D object container clip"},
					{"class": "Particles2DClipRes", "desc": "Particle system clip"},
					{"class": "Camera2DClipRes", "desc": "Camera clip"},
					{"class": "AdjustmentClipRes", "desc": "Adjustment layer clip"},
					{"class": "Shape2DClipRes", "desc": "Shape object clip (prototype)"},
					{"class": "Audio2DClipRes", "desc": "2D audio clip (prototype)"}
				]
			},
			{
				"name": "Undo & Redo",
				"functions": [
					{"cmd": "undo", "desc": "Undo last action"},
					{"cmd": "redo", "desc": "Redo last undone action"},
					{"eval": "ProjectServer2.undo()", "desc": "Undo via eval"},
					{"eval": "ProjectServer2.redo()", "desc": "Redo via eval"},
					{"eval": "ProjectServer2.undo_redo.has_undo()", "desc": "Check if undo available"},
					{"eval": "ProjectServer2.undo_redo.has_redo()", "desc": "Check if redo available"}
				]
			},
			{
				"name": "File Operations",
				"functions": [
					{"cmd": "read", "desc": "Read file content", "params": {"file": "str (path)"}},
					{"cmd": "write", "desc": "Write content to file", "params": {"file": "str", "content": "str"}},
					{"cmd": "edit", "desc": "Find and replace in file", "params": {"file": "str", "old": "str", "new": "str", "replace_all": "bool"}},
					{"cmd": "ls", "desc": "List directory contents", "params": {"path": "str (default res://)"}},
					{"eval": "DirAccess.get_files_at(path)", "desc": "Get files list at path"},
					{"eval": "DirAccess.get_directories_at(path)", "desc": "Get subdirectories list"}
				]
			},
			{
				"name": "Screenshots & Viewport",
				"functions": [
					{"cmd": "screenshot", "desc": "Capture current viewport as PNG"},
					{"cmd": "frame", "desc": "Seek to frame and capture PNG", "params": {"frame": "int"}},
					{"eval": "Scene2.viewport.get_texture().get_image()", "desc": "Get raw viewport image"}
				]
			},
			{
				"name": "Script Execution & Inspection",
				"functions": [
					{"cmd": "eval", "desc": "Evaluate GDScript expression and return result", "params": {"code": "str (expression)"}},
					{"cmd": "exec", "desc": "Execute GDScript statements (void)", "params": {"code": "str (statements)"}},
					{"cmd": "inspect", "desc": "List methods/properties/signals of any autoload or node", "params": {"target": "str (node name)"}},
					{"cmd": "discover", "desc": "Read source code functions with comments", "params": {"target": "str (autoload name), 'all', or 'all_workflows'"}},
					{"cmd": "capabilities", "desc": "Full feature map with all commands and eval hints", "params": {"target": "str (optional filter category)", "flat": "bool (flatten output)"}},
					{"cmd": "context", "desc": "Get full project context as readable text: all layers, clips, components, keyframes, playback state", "params": {"format": "'text' (default)"}},
					{"cmd": "transcribe", "desc": "Extract audio from video and convert speech to text via local faster-whisper (100% offline, no API key)", "params": {"path": "str (video file path)", "layer": "int (alt: layer index)", "frame": "int (alt: clip frame)", "model": "str (optional: tiny, base, small, medium, large; default base)", "max_secs": "int (optional, max audio duration, default 60)"}}
				]
			},
			{
				"name": "Clipboard & Import (Full Control)",
				"functions": [
					{"cmd": "clip_copy", "desc": "Copy a clip to internal clipboard", "params": {"layer": "int", "frame": "int"}},
					{"cmd": "clip_paste", "desc": "Paste copied clip to timeline", "params": {"layer": "int (target layer)", "frame": "int (target frame, default: current position)", "method": "int (0=place_on_top, 1=insert, 2=overwrite, 3=fit_to_fill, 4=replace)"}},
					{"cmd": "clip_import", "desc": "Import media file and add to timeline in one step (auto-registers + creates clip)", "params": {"path": "str (full file path)", "layer": "int (default 0)", "frame": "int (default: current position)", "length": "int (auto-detected from media)", "method": "int (0-4 placement method)"}},
					{"cmd": "clip_trim", "desc": "Trim clip edges (adjust from/length)", "params": {"layer": "int", "frame": "int", "side": "str ('left' or 'right')", "amount": "int (frames to trim)"}},
					{"cmd": "text_add", "desc": "Add a text clip to timeline", "params": {"layer": "int (default 0)", "frame": "int (default: current position)", "text": "str", "length": "int (default 90)", "font_size": "int (default 24)", "color": "str (hex, default #ffffff)", "method": "int (0-4)"}},
					{"cmd": "text_set", "desc": "Update text clip properties", "params": {"layer": "int", "frame": "int", "text": "str", "font_size": "int", "color": "str (hex)", "outline_size": "int", "outline_color": "str (hex)", "shadow_size": "int", "shadow_color": "str (hex)", "horizontal_alignment": "str or int ('left'/'center'/'right' or 0/1/2)"}},
					{"cmd": "media_import", "desc": "Register media files into project cache (thumbnail + waveform generation)", "params": {"path": "str", "paths": "array of str"}},
					{"cmd": "layer_duplicate", "desc": "Duplicate a layer with all its clips", "params": {"index": "int (source layer index)"}},
					{"cmd": "comp_enable", "desc": "Enable a disabled component", "params": {"layer": "int", "frame": "int", "index": "int", "section": "str (default Display2D)"}},
					{"cmd": "comp_disable", "desc": "Disable a component (keeps it on clip)", "params": {"layer": "int", "frame": "int", "index": "int", "section": "str (default Display2D)"}},
					{"cmd": "timeline_goto", "desc": "Stop playback and seek to frame", "params": {"frame": "int"}},
					{"cmd": "timeline_length", "desc": "Get or set timeline length", "params": {"set": "int (new length in frames)"}}
				]
			},
			{
				"name": "Collaborative Editing & Review",
				"functions": [
					{"cmd": "changes_log", "desc": "View all logged changes (who did what when)", "params": {"actor": "str (optional filter)", "since": "float (optional unix timestamp)", "limit": "int (default 100)"}},
					{"cmd": "changes_clear", "desc": "Clear the change log"},
					{"cmd": "snapshot", "desc": "Save/load project state snapshots for diff comparison", "params": {"action": "str ('save', 'list', 'get')", "id": "str (for 'get')"}},
					{"cmd": "diff", "desc": "Compare current state with a saved snapshot", "params": {"snapshot": "str (snapshot id)"}},
					{"cmd": "review", "desc": "Get a human-readable review of project state and recent changes", "params": {"format": "str (default 'text')"}},
					{"cmd": "project_state", "desc": "Get full project state as structured JSON (all layers, clips, components, properties)", "params": {}},
					{"workflow": "1. Save snapshot before editing: {\"cmd\":\"snapshot\",\"action\":\"save\"}", "desc": "Take snapshot before making changes"},
					{"workflow": "2. Make changes via any edit command", "desc": "Edit clips, layers, components, etc."},
					{"workflow": "3. Check diff: {\"cmd\":\"diff\",\"snapshot\":\"snap_1\"}", "desc": "See what changed since snapshot"},
					{"workflow": "4. Review: {\"cmd\":\"review\"}", "desc": "Get full summary before export"},
					{"workflow": "5. User verifies in GUI, then export", "desc": "Visual confirmation before rendering"}
				]
			}
		],
		"usage_hint": "COLLABORATIVE WORKFLOW: Save snapshot -> Make changes -> Diff to see changes -> Review -> Export. Use 'project_state' for full JSON state. All changes are auto-logged with timestamps.",
		"autoloads_available": ["ProjectServer2", "MediaCache", "MediaServer", "Scene2", "PlaybackServer", "Renderer", "EditorServer", "GlobalServer", "InterfaceServer", "ClassServer", "HudModServer"],
		"clip_types_available": ["VideoClipRes", "ImageClipRes", "AudioClipRes", "Text2DClipRes", "Display2DClipRes", "Particles2DClipRes", "Camera2DClipRes", "AdjustmentClipRes", "Shape2DClipRes", "Audio2DClipRes"],
		"component_sections": ["Display2D", "Image", "Color", "Transition", "Sound", "Text", "Particles", "Camera", "Layout"],
		"value_type_hint": "For Vector2 values, send: {\"type\":\"Vector2\",\"x\":1.0,\"y\":2.0}. For Color: {\"type\":\"Color\",\"r\":1,\"g\":0,\"b\":0,\"a\":1} or {\"type\":\"Color_html\",\"html\":\"#ff0000\"}. Plain numbers/bools/strings are auto-detected."
	}
	var resp: Dictionary = {"capabilities": caps, "total_categories": caps.categories.size()}
	if _req.get("target", "") != "":
		for cat: Dictionary in caps.categories:
			if cat.name.to_lower().find(_req.target.to_lower()) != -1:
				resp = cat
				break
	if _req.get("flat", false):
		var flat: Array[Dictionary] = []
		for cat: Dictionary in caps.categories:
			for fn: Dictionary in cat.functions:
				fn["category"] = cat.name
				flat.append(fn)
		resp = {"functions": flat, "total": flat.size()}
	_send_response(_conn, 200, resp)


func _require_project(conn: StreamPeerTCP) -> bool:
	if not ProjectServer2.project_res or not ProjectServer2.project_res.root_clip_res:
		_send_response(conn, 400, {"error": "No project open"})
		return false
	return true

func _require_media_path(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	return true


# ── Collaborative Editing Helpers ──────────────────────────────────────────

func _log_change(actor: String, action: String, target: String, details: Dictionary = {}) -> void:
	var entry: Dictionary = {
		"timestamp": Time.get_unix_time_from_system(),
		"time_str": Time.get_datetime_string_from_system(false, true),
		"actor": actor,
		"action": action,
		"target": target,
		"details": details
	}
	_changes_log.append(entry)
	if _changes_log.size() > 500:
		_changes_log = _changes_log.slice(-500)
	_persist_save()

func _capture_state_snapshot() -> Dictionary:
	if not ProjectServer2.project_res or not ProjectServer2.project_res.root_clip_res:
		return {"empty": true}
	var p: ProjectRes = ProjectServer2.project_res
	var root: RootClipRes = p.root_clip_res
	var state: Dictionary = {
		"project_name": p.project_name,
		"fps": p.fps,
		"resolution": {"x": p.resolution.x, "y": p.resolution.y},
		"timeline_length": root.length,
		"current_frame": PlaybackServer.position,
		"layers": []
	}
	for li: int in root.layers.size():
		var layer: LayerRes = root.layers[li]
		var layer_data: Dictionary = {
			"index": li,
			"name": layer.custom_name,
			"locked": layer.locked,
			"hidden": layer.hidden,
			"clips": []
		}
		for frame: int in layer.clips:
			var c: MediaClipRes = layer.clips[frame]
			var clip_data: Dictionary = {
				"frame": frame,
				"type": c.get_classname(),
				"name": c.get_display_name(),
				"from": c.from,
				"length": c.length,
				"components": {}
			}
			for section: String in c.components:
				var comps_list: Array[Dictionary] = []
				for comp: ComponentRes in c.components[section]:
					var props: Dictionary = {}
					for prop_d: Dictionary in comp.get_property_list():
						if prop_d.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
							var pname: String = prop_d.name
							if pname in ["animations", "captured_props", "properties", "owner", "get_prop_func"]:
								continue
							var pval = comp.get(pname)
							if typeof(pval) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_VECTOR2, TYPE_COLOR]:
								props[pname] = pval
					comps_list.append({"classname": comp.get_classname(), "enabled": comp.enabled, "props": props})
				clip_data["components"][section] = comps_list
			if c is Text2DClipRes:
				clip_data["text"] = (c as Text2DClipRes).text
				clip_data["font_size"] = (c as Text2DClipRes).font_size
			layer_data["clips"].append(clip_data)
		state["layers"].append(layer_data)
	return state

func _compare_states(old_state: Dictionary, new_state: Dictionary) -> Array[Dictionary]:
	var diffs: Array[Dictionary] = []
	if old_state.is_empty() or new_state.is_empty():
		if old_state.is_empty() and not new_state.is_empty():
			diffs.append({"type": "project_created", "detail": "Project state appeared"})
		elif not old_state.is_empty() and new_state.is_empty():
			diffs.append({"type": "project_cleared", "detail": "Project state removed"})
		return diffs
	if old_state.get("project_name", "") != new_state.get("project_name", ""):
		diffs.append({"type": "project_renamed", "from": old_state.project_name, "to": new_state.project_name})
	if old_state.get("timeline_length", 0) != new_state.get("timeline_length", 0):
		diffs.append({"type": "timeline_length_changed", "from": old_state.timeline_length, "to": new_state.timeline_length})
	var old_layers: Array = old_state.get("layers", [])
	var new_layers: Array = new_state.get("layers", [])
	if old_layers.size() != new_layers.size():
		diffs.append({"type": "layer_count_changed", "from": old_layers.size(), "to": new_layers.size()})
	var max_layers: int = mini(old_layers.size(), new_layers.size())
	for li: int in max_layers:
		var ol: Dictionary = old_layers[li]
		var nl: Dictionary = new_layers[li]
		if ol.get("name", "") != nl.get("name", ""):
			diffs.append({"type": "layer_renamed", "layer": li, "from": ol.name, "to": nl.name})
		var old_clips: Array = ol.get("clips", [])
		var new_clips: Array = nl.get("clips", [])
		if old_clips.size() != new_clips.size():
			diffs.append({"type": "clip_count_changed", "layer": li, "from": old_clips.size(), "to": new_clips.size()})
		var old_frame_map: Dictionary = {}
		for cd: Dictionary in old_clips:
			old_frame_map[cd.frame] = cd
		var new_frame_map: Dictionary = {}
		for cd: Dictionary in new_clips:
			new_frame_map[cd.frame] = cd
		for frame: int in old_frame_map:
			if not new_frame_map.has(frame):
				diffs.append({"type": "clip_removed", "layer": li, "frame": frame, "name": old_frame_map[frame].get("name", "")})
		for frame: int in new_frame_map:
			if not old_frame_map.has(frame):
				diffs.append({"type": "clip_added", "layer": li, "frame": frame, "name": new_frame_map[frame].get("name", ""), "type_name": new_frame_map[frame].get("type", "")})
			else:
				var oc: Dictionary = old_frame_map[frame]
				var nc: Dictionary = new_frame_map[frame]
				if oc.get("from", 0) != nc.get("from", 0) or oc.get("length", 0) != nc.get("length", 0):
					diffs.append({"type": "clip_modified", "layer": li, "frame": frame, "name": nc.get("name", ""), "changes": {"from": {"old": oc.from, "new": nc.from}, "length": {"old": oc.length, "new": nc.length}}})
				if oc.get("text", "") != nc.get("text", ""):
					diffs.append({"type": "text_changed", "layer": li, "frame": frame, "from": oc.get("text", ""), "to": nc.get("text", "")})
	return diffs


# ── Collaborative Commands ─────────────────────────────────────────────────

func _cmd_changes_log(conn: StreamPeerTCP, req: Dictionary) -> void:
	var actor_filter: String = req.get("actor", "")
	var since: float = req.get("since", 0.0)
	var limit: int = req.get("limit", 100)
	var filtered: Array[Dictionary] = []
	for entry: Dictionary in _changes_log:
		if actor_filter != "" and entry.actor != actor_filter:
			continue
		if since > 0.0 and entry.timestamp < since:
			continue
		filtered.append(entry)
	var result: Array[Dictionary] = filtered.slice(-limit)
	_send_response(conn, 200, {"changes": result, "total": filtered.size(), "log_size": _changes_log.size()})

func _cmd_changes_clear(_conn: StreamPeerTCP, _req: Dictionary) -> void:
	_changes_log.clear()
	_persist_save()
	_send_response(_conn, 200, {"result": "changes_log_cleared"})

func _cmd_snapshot(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var action: String = req.get("action", "save")
	match action:
		"save":
			var state: Dictionary = _capture_state_snapshot()
			_snapshot_counter += 1
			var snap_id: String = "snap_%d" % _snapshot_counter
			_snapshots[snap_id] = state
			var snap_list: Array = _snapshots.keys()
			if snap_list.size() > 20:
				var old_key: String = snap_list[0]
				_snapshots.erase(old_key)
			_persist_save()
			_send_response(conn, 200, {"result": "snapshot_saved", "id": snap_id, "total_snapshots": _snapshots.size()})
		"list":
			var snap_ids: Array = _snapshots.keys()
			_send_response(conn, 200, {"snapshots": snap_ids})
		"get":
			var snap_id: String = req.get("id", "")
			if _snapshots.has(snap_id):
				_send_response(conn, 200, {"id": snap_id, "state": _snapshots[snap_id]})
			else:
				_send_response(conn, 404, {"error": "Snapshot not found: " + snap_id})
		_:
			_send_response(conn, 400, {"error": "action must be 'save', 'list', or 'get'"})

func _cmd_diff(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var snap_id: String = req.get("snapshot", "")
	if snap_id.is_empty():
		_send_response(conn, 400, {"error": "Need 'snapshot' parameter (snapshot id to compare against)"})
		return
	if not _snapshots.has(snap_id):
		_send_response(conn, 404, {"error": "Snapshot not found: " + snap_id})
		return
	var old_state: Dictionary = _snapshots[snap_id]
	var new_state: Dictionary = _capture_state_snapshot()
	var diffs: Array[Dictionary] = _compare_states(old_state, new_state)
	_send_response(conn, 200, {
		"snapshot": snap_id,
		"diffs": diffs,
		"total_changes": diffs.size(),
		"has_changes": diffs.size() > 0
	})

func _cmd_review(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var format: String = req.get("format", "text")
	var lines: PackedStringArray = []
	lines.append("=== COLLABORATIVE REVIEW ===")
	lines.append("Project: %s" % ProjectServer2.project_res.project_name)
	lines.append("Time: %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("")

	var changes_count: int = _changes_log.size()
	lines.append("--- CHANGE LOG (%d total) ---" % changes_count)
	if changes_count == 0:
		lines.append("  No changes logged yet.")
	else:
		var recent: Array[Dictionary] = _changes_log.slice(-20)
		for entry: Dictionary in recent:
			lines.append("  [%s] %s: %s -> %s" % [entry.time_str, entry.actor, entry.action, entry.target])
			if not entry.details.is_empty():
				lines.append("         Details: %s" % str(entry.details))
	lines.append("")

	lines.append("--- CURRENT PROJECT STATE ---")
	var state: Dictionary = _capture_state_snapshot()
	if state.is_empty():
		lines.append("  No project open.")
	else:
		lines.append("  FPS: %d | Resolution: %dx%d | Length: %d frames" % [state.fps, state.resolution.x, state.resolution.y, state.timeline_length])
		lines.append("  Current Frame: %d" % state.current_frame)
		lines.append("  Layers: %d" % state.layers.size())
		for layer: Dictionary in state.layers:
			lines.append("    Layer %d: %s (%d clips)" % [layer.index, layer.name, layer.clips.size()])
			for clip: Dictionary in layer.clips:
				lines.append("      [%d] %s (%s) from=%d len=%d" % [clip.frame, clip.name, clip.type, clip.from, clip.length])
				if clip.has("text") and not clip.text.is_empty():
					lines.append("        Text: \"%s\" (size=%d)" % [clip.text, clip.get("font_size", 24)])
	lines.append("")

	if _snapshots.size() > 0:
		lines.append("--- SNAPSHOTS (%d) ---" % _snapshots.size())
		for snap_id: String in _snapshots:
			lines.append("  %s" % snap_id)
	else:
		lines.append("--- SNAPSHOTS ---")
		lines.append("  No snapshots saved. Use snapshot command to save state before edits.")

	lines.append("")
	lines.append("=== REVIEW COMPLETE ===")

	if format == "text":
		_send_response(conn, 200, {"format": "text", "review": "\n".join(lines)})
	else:
		_send_response(conn, 200, {"format": format, "error": "Only 'text' format supported"})

func _cmd_project_state(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	var state: Dictionary = _capture_state_snapshot()
	_send_response(conn, 200, {"state": state})


# ── Project Commands ─────────────────────────────────────────────────────────

func _cmd_project_new(conn: StreamPeerTCP, req: Dictionary) -> void:
	var name: String = req.get("name", "HudMod Video")
	var dir: String = req.get("dir", "")
	var fps: int = req.get("fps", 30)
	var width: int = req.get("width", 1920)
	var height: int = req.get("height", 1080)
	if dir.is_empty():
		_send_response(conn, 400, {"error": "Missing 'dir' parameter"})
		return
	var pr: ProjectRes = ProjectRes.new()
	pr.project_name = name
	pr.fps = fps
	pr.resolution = Vector2(width, height)
	pr.root_clip_res = RootClipRes.new()
	var result: ProjectRes = ProjectServer2.new_project(pr, dir)
	if result:
		_log_change("terminal", "project_created", name, {"dir": dir, "fps": fps, "resolution": "%dx%d" % [width, height]})
		_send_response(conn, 200, {"result": "project_created", "dir": dir})
	else:
		_send_response(conn, 500, {"error": "Failed to create project", "dir": dir})

func _cmd_project_open(conn: StreamPeerTCP, req: Dictionary) -> void:
	var dir: String = req.get("dir", "")
	if dir.is_empty():
		_send_response(conn, 400, {"error": "Missing 'dir' parameter"})
		return
	var ok: bool = ProjectServer2.open_project(dir)
	if ok:
		_log_change("terminal", "project_opened", dir)
		_send_response(conn, 200, {"result": "project_opened", "dir": dir})
	else:
		_send_response(conn, 500, {"error": "Failed to open project", "dir": dir})

func _cmd_project_save(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	ProjectServer2.save()
	_send_response(conn, 200, {"result": "saved"})

func _cmd_project_save_as(conn: StreamPeerTCP, req: Dictionary) -> void:
	var dir: String = req.get("dir", "")
	if dir.is_empty():
		_send_response(conn, 400, {"error": "Missing 'dir' parameter"})
		return
	ProjectServer2.save_as(dir)
	_send_response(conn, 200, {"result": "saved_as", "dir": dir})

func _cmd_project_info(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	var p: ProjectRes = ProjectServer2.project_res
	var root: RootClipRes = p.root_clip_res
	var layer_count: int = root.layers.size()
	var total_clips: int = 0
	for layer: LayerRes in root.layers:
		total_clips += layer.clips.size()
	_send_response(conn, 200, {
		"name": p.project_name,
		"fps": p.fps,
		"resolution": {"width": p.resolution.x, "height": p.resolution.y},
		"length_frames": root.length,
		"layers": layer_count,
		"total_clips": total_clips,
		"timemarkers": p.timemarkers.size(),
		"is_rendering": Renderer.is_working,
		"is_paused": Renderer.is_paused,
		"current_frame": PlaybackServer.position,
		"is_playing": PlaybackServer.is_playing()
	})

func _cmd_project_settings(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var p: ProjectRes = ProjectServer2.project_res
	if req.has("name"): p.project_name = req.name
	if req.has("fps"): p.fps = req.fps
	if req.has("width") and req.has("height"):
		p.resolution = Vector2(req.width, req.height)
	_send_response(conn, 200, {"result": "updated", "name": p.project_name, "fps": p.fps, "resolution": {"width": p.resolution.x, "height": p.resolution.y}})


# ── Layer Commands ───────────────────────────────────────────────────────────

func _cmd_layer_list(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	var layers_out: Array[Dictionary] = []
	for i: int in root.layers.size():
		var l: LayerRes = root.layers[i]
		var is_root: bool = l is RootLayerRes
		var clips_out: Array[Dictionary] = []
		for frame: int in l.clips:
			var c: MediaClipRes = l.clips[frame]
			clips_out.append({"frame": frame, "type": c.get_classname(), "name": c.get_display_name(), "length": c.length, "from": c.from})
		layers_out.append({
			"index": i,
			"name": l.custom_name,
			"locked": l.locked,
			"hidden": l.hidden,
			"color": "#" + l.custom_color.to_html(),
			"clip_count": l.clips.size(),
			"clips": clips_out,
			"mute": l.mute if is_root else null,
			"volume": l.volume if is_root else null
		})
	_send_response(conn, 200, {"layers": layers_out})

func _cmd_layer_add(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var idx: int = req.get("index", -1)
	if idx < 0: idx = ProjectServer2.project_res.root_clip_res.layers.size()
	var layer: LayerRes = ProjectServer2.project_res.root_clip_res.add_layer(idx)
	_log_change("terminal", "layer_added", "Layer %d" % idx)
	_send_response(conn, 200, {"result": "layer_added", "index": idx})

func _cmd_layer_remove(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var idx: int = req.get("index", -1)
	if idx < 0 or idx >= ProjectServer2.project_res.root_clip_res.layers.size():
		_send_response(conn, 400, {"error": "Invalid layer index"})
		return
	ProjectServer2.project_res.root_clip_res.remove_layer(idx)
	_log_change("terminal", "layer_removed", "Layer %d" % idx)
	_send_response(conn, 200, {"result": "layer_removed", "index": idx})

func _cmd_layer_move(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var from_idx: int = req.get("from", -1)
	var to_idx: int = req.get("to", -1)
	if from_idx < 0 or to_idx < 0:
		_send_response(conn, 400, {"error": "Need 'from' and 'to' indices"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if from_idx >= root.layers.size() or to_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Index out of range"})
		return
	root.move_layer(from_idx, to_idx)
	_send_response(conn, 200, {"result": "layer_moved", "from": from_idx, "to": to_idx})

func _cmd_layer_set(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var idx: int = req.get("index", -1)
	if idx < 0 or idx >= ProjectServer2.project_res.root_clip_res.layers.size():
		_send_response(conn, 400, {"error": "Invalid layer index"})
		return
	var l: LayerRes = ProjectServer2.project_res.root_clip_res.layers[idx]
	if req.has("name"): l.custom_name = req.name
	if req.has("locked"): l.locked = bool(req.locked)
	if req.has("hidden"): l.hidden = bool(req.hidden)
	if req.has("color"):
		var col: Color = Color.html(req.color) if typeof(req.color) == TYPE_STRING else l.custom_color
		l.custom_color = col
	if l is RootLayerRes:
		var rl: RootLayerRes = l
		if req.has("mute"): rl.mute = bool(req.mute)
		if req.has("volume"): rl.volume = float(req.volume)
	_send_response(conn, 200, {"result": "layer_updated", "index": idx})


# ── Clip Commands ────────────────────────────────────────────────────────────

func _cmd_clip_add(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", 0)
	var frame: int = req.get("frame", 0)
	var media_path: String = req.get("media", "")
	var clip_type: String = req.get("type", "")
	var length: int = req.get("length", 30)

	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return

	var clip: MediaClipRes
	if not clip_type.is_empty():
		if ClassServer.media_clip_classes.has(clip_type):
			clip = ClassServer.media_clip_classes[clip_type].script.new()
		else:
			_send_response(conn, 400, {"error": "Unknown clip type: " + clip_type, "available": ClassServer.media_clip_classes.keys()})
			return
	elif not media_path.is_empty():
		var media_type: int = MediaServer.get_media_type_from_path(media_path)
		match media_type:
			MediaServer.MediaType.IMAGE:
				clip = ImageClipRes.new()
				clip.image = media_path
				length = max(length, 30)
			MediaServer.MediaType.VIDEO:
				clip = VideoClipRes.new()
				clip.video = media_path
				if MediaCache.video_contexts_has(media_path):
					var ctx: MediaCache.VideoContext = MediaCache.get_video_context(media_path)
					length = int(ctx.duration * ctx.fps)
			MediaServer.MediaType.AUDIO:
				clip = AudioClipRes.new()
			_:
				_send_response(conn, 400, {"error": "Unknown media type for: " + media_path})
				return
	else:
		_send_response(conn, 400, {"error": "Need 'type' or 'media' parameter"})
		return

	clip.from = 0
	clip.length = length
	var placed: Dictionary[Vector2i, MediaClipRes] = root.add_clips(layer_idx, frame, [clip], 0, true, false)
	var coords: Array = placed.keys()
	_log_change("terminal", "clip_added", clip.get_classname(), {"layer": layer_idx, "frame": frame, "length": length, "coords": str(coords)})
	_send_response(conn, 200, {"result": "clip_added", "coords": str(coords)})

func _cmd_clip_remove(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	if layer_idx < 0 or frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer' and 'frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	var clip_name: String = c.get_display_name() if c else "unknown"
	root.remove_clips([Vector2i(layer_idx, frame)], true, false)
	_log_change("terminal", "clip_removed", clip_name, {"layer": layer_idx, "frame": frame})
	_send_response(conn, 200, {"result": "clip_removed"})

func _cmd_clip_move(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var from_layer: int = req.get("from_layer", -1)
	var from_frame: int = req.get("from_frame", -1)
	var to_layer: int = req.get("to_layer", -1)
	var to_frame: int = req.get("to_frame", -1)
	if from_layer < 0 or from_frame < 0 or to_frame < 0:
		_send_response(conn, 400, {"error": "Need 'from_layer', 'from_frame', 'to_frame'"})
		return
	if to_layer < 0: to_layer = from_layer
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	root.move_clips([Vector2i(from_layer, from_frame)], [Vector2i(to_layer, to_frame)], -1, true, false)
	_send_response(conn, 200, {"result": "clip_moved"})

func _cmd_clip_split(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var split_pos: int = req.get("split_pos", -1)
	if layer_idx < 0 or frame < 0 or split_pos < 0:
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'split_pos'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var layer: LayerRes = root.layers[layer_idx]
	if not layer.clips.has(frame):
		_send_response(conn, 400, {"error": "No clip at that frame"})
		return
	root.split_clips([Vector2i(layer_idx, frame)], split_pos, true, true, false)
	_send_response(conn, 200, {"result": "clip_split"})

func _cmd_clip_duplicate(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	if layer_idx < 0 or frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer' and 'frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var original: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not original:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var dupl: MediaClipRes = original.duplicate_media_res()
	var target_frame: int = frame + original.length + 1
	root.add_clips(layer_idx, target_frame, [dupl], 0, true, false)
	_send_response(conn, 200, {"result": "clip_duplicated", "target_frame": target_frame})

func _cmd_clip_info(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	if layer_idx < 0 or frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer' and 'frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var comps_out: Array[Dictionary] = []
	for section: String in c.components:
		for comp: ComponentRes in c.components[section]:
			var props: Dictionary = {}
			for p: Dictionary in comp.get_property_list():
				if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					props[p.name] = comp.get(p.name)
			comps_out.append({"classname": comp.get_classname(), "section": section, "enabled": comp.enabled, "forced": comp.forced, "properties": props})
	_send_response(conn, 200, {
		"classname": c.get_classname(),
		"display_name": c.get_display_name(),
		"layer": layer_idx,
		"frame": frame,
		"from": c.from,
		"length": c.length,
		"id": c.id,
		"component_count": comps_out.size(),
		"components": comps_out
	})

func _cmd_clip_list(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= 0 and layer_idx < root.layers.size():
		var l: LayerRes = root.layers[layer_idx]
		var clips_out: Array[Dictionary] = []
		for frame: int in l.clips:
			var c: MediaClipRes = l.clips[frame]
			clips_out.append({"frame": frame, "type": c.get_classname(), "name": c.get_display_name(), "length": c.length, "from": c.from, "id": c.id})
		_send_response(conn, 200, {"layer": layer_idx, "clips": clips_out})
	else:
		var all_out: Array[Dictionary] = []
		for li: int in root.layers.size():
			var l: LayerRes = root.layers[li]
			var clips_out: Array[Dictionary] = []
			for frame: int in l.clips:
				var c: MediaClipRes = l.clips[frame]
				clips_out.append({"frame": frame, "type": c.get_classname(), "name": c.get_display_name(), "length": c.length})
			all_out.append({"layer": li, "name": l.custom_name, "clip_count": l.clips.size(), "clips": clips_out})
		_send_response(conn, 200, {"layers": all_out})

func _cmd_clip_set(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	if layer_idx < 0 or frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer' and 'frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	if req.has("from"): c.from = req.from
	if req.has("length"): c.length = req.length
	_send_response(conn, 200, {"result": "clip_updated", "from": c.from, "length": c.length})


# ── Extended Clip Commands ──────────────────────────────────────────────────

func _cmd_clip_copy(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	if layer_idx < 0 or frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer' and 'frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var dupl: MediaClipRes = c.duplicate_media_res()
	_clipboard_clips = [dupl]
	_send_response(conn, 200, {"result": "copied", "type": c.get_classname(), "name": c.get_display_name(), "length": c.length})

func _cmd_clip_paste(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	if _clipboard_clips.is_empty():
		_send_response(conn, 400, {"error": "Clipboard empty. Use clip_copy first."})
		return
	var layer_idx: int = req.get("layer", 0)
	var frame: int = req.get("frame", -1)
	if frame < 0:
		frame = PlaybackServer.position
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var pasted: Array[MediaClipRes] = []
	for c: MediaClipRes in _clipboard_clips:
		pasted.append(c.duplicate_media_res())
	var place_method: int = req.get("method", 0)
	var placed: Dictionary = root.add_clips(layer_idx, frame, pasted, place_method, true, false)
	_send_response(conn, 200, {"result": "pasted", "clips": pasted.size(), "coords": str(placed.keys())})

func _cmd_clip_import(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var path: String = req.get("path", "")
	if path.is_empty():
		_send_response(conn, 400, {"error": "Missing 'path' parameter"})
		return
	if not FileAccess.file_exists(path):
		_send_response(conn, 404, {"error": "File not found: " + path})
		return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	if frame < 0:
		frame = PlaybackServer.position
	if layer_idx < 0:
		layer_idx = 0
	var length: int = req.get("length", -1)
	var place_method: int = req.get("method", 0)

	var media_type: int = MediaServer.get_media_type_from_path(path)
	if media_type != MediaServer.MediaType.IMAGE and media_type != MediaServer.MediaType.VIDEO and media_type != MediaServer.MediaType.AUDIO:
		_send_response(conn, 400, {"error": "Unsupported media type for: " + path})
		return

	var ids_exists: PackedStringArray = EditorServer.get_ids_from_pathes(DirAccess.get_files_at(ProjectServer2.project_thumbnail_path))
	MediaCache.register_from_path(path, ids_exists)

	var clip: MediaClipRes
	match media_type:
		MediaServer.MediaType.IMAGE:
			clip = ImageClipRes.new()
			clip.image = path
			if length < 0: length = 30
		MediaServer.MediaType.VIDEO:
			clip = VideoClipRes.new()
			clip.video = path
			if MediaCache.video_contexts_has(path):
				var ctx: MediaCache.VideoContext = MediaCache.get_video_context(path)
				if length < 0: length = int(ctx.duration * ctx.fps)
			else:
				if length < 0: length = 300
		MediaServer.MediaType.AUDIO:
			clip = AudioClipRes.new()
			if length < 0: length = 30
		_:
			_send_response(conn, 400, {"error": "Unsupported media type"})
			return

	clip.from = 0
	clip.length = length
	if clip is Display2DClipRes:
		clip._init_clip_res()
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	var placed: Dictionary = root.add_clips(layer_idx, frame, [clip], place_method, true, false)
	_log_change("terminal", "clip_imported", path.get_file(), {"layer": layer_idx, "frame": frame, "type": clip.get_classname(), "length": length, "coords": str(placed.keys())})
	_send_response(conn, 200, {
		"result": "imported",
		"path": path,
		"type": clip.get_classname(),
		"length": length,
		"coords": str(placed.keys())
	})

func _run_ffmpeg_metadata(path: String) -> void:
	var ffmpeg_path: String = ProjectSettings.globalize_path("res://addons/ffmpeg_codec/ffmpeg.exe")
	var args: PackedStringArray = ["-i", path]
	var output: Array = []
	OS.execute(ffmpeg_path, args, output, true)
	var dur_str: String = ""
	var fps_val: float = 30.0
	var w: int = 0
	var h: int = 0
	var dims_re: RegEx = RegEx.new()
	dims_re.compile("(\\d+)x(\\d+)")
	var fps_re: RegEx = RegEx.new()
	fps_re.compile("(\\d+(\\.\\d+)?)\\s*(fps|tbr|tbn|tbc)")
	for line: String in output:
		if "Duration:" in line:
			var idx: int = line.find("Duration:")
			if idx != -1:
				var rest: String = line.substr(idx + 9)
				var comma: int = rest.find(",")
				if comma != -1:
					dur_str = rest.substr(0, comma).strip_edges()
		if line.find("Stream") != -1 and line.find("Video:") != -1:
			var res: RegExMatch = dims_re.search(line)
			if res:
				w = res.get_string(1).to_int()
				h = res.get_string(2).to_int()
			var fm: RegExMatch = fps_re.search(line)
			if fm:
				fps_val = fm.get_string(1).to_float()
	if dur_str.is_empty() or w == 0:
		return
	var parts: PackedStringArray = dur_str.split(":")
	var dur_sec: float = 0.0
	if parts.size() == 3:
		dur_sec = parts[0].to_float() * 3600.0 + parts[1].to_float() * 60.0 + parts[2].to_float()
	var total_frames: int = int(dur_sec * fps_val)
	var ctx: MediaCache.VideoContext = MediaCache.VideoContext.new()
	ctx.video_path = path
	ctx.resolution = Vector2i(w, h)
	ctx.duration = dur_sec
	ctx.fps = fps_val
	ctx.total_frames = total_frames
	ctx.bit_depth = 8
	MediaCache.video_contexts[path] = ctx
	MediaCache.audio_datas[path] = MediaCache.default_audio_f32_data
	MediaCache.video_contexts_update_max_cache_size()

func _cmd_clip_trim(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var side: String = req.get("side", "right")
	var amount: int = req.get("amount", 0)
	if layer_idx < 0 or frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer' and 'frame'"})
		return
	if amount == 0:
		_send_response(conn, 400, {"error": "Need 'amount' (frames to trim)"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	match side:
		"left":
			var max_trim: int = c.length - 1
			var actual: int = mini(absi(amount), max_trim)
			c.from += actual
			c.length -= actual
		"right":
			var actual: int = mini(absi(amount), c.length - 1)
			c.length -= actual
		_:
			_send_response(conn, 400, {"error": "side must be 'left' or 'right'"})
			return
	PlaybackServer.position = PlaybackServer.position
	Scene2.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_send_response(conn, 200, {"result": "trimmed", "side": side, "amount": amount, "new_length": c.length, "new_from": c.from})


# ── Text Commands ───────────────────────────────────────────────────────────

func _cmd_text_add(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	if frame < 0:
		frame = PlaybackServer.position
	if layer_idx < 0:
		layer_idx = 0
	var text_content: String = req.get("text", "Text")
	var length: int = req.get("length", 90)
	var font_size: int = req.get("font_size", 24)
	var font_color: String = req.get("color", "#ffffff")
	var place_method: int = req.get("method", 0)
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var clip: Text2DClipRes = Text2DClipRes.new()
	clip.text = text_content
	clip.font_size = font_size
	clip.font_color = Color.html(font_color)
	clip.from = 0
	clip.length = length
	clip._init_clip_res()
	var placed: Dictionary = root.add_clips(layer_idx, frame, [clip], place_method, true, false)
	_send_response(conn, 200, {
		"result": "text_added",
		"text": text_content,
		"length": length,
		"coords": str(placed.keys())
	})
	_log_change("terminal", "text_added", text_content, {"layer": layer_idx, "frame": frame, "font_size": font_size, "color": font_color, "length": length})

func _cmd_text_set(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	if layer_idx < 0 or frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer' and 'frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	if not c is Text2DClipRes:
		_send_response(conn, 400, {"error": "Clip is not a Text2D clip (it's " + c.get_classname() + ")"})
		return
	var tc: Text2DClipRes = c as Text2DClipRes
	if req.has("text"): tc.text = req.text
	if req.has("font_size"): tc.font_size = int(req.font_size)
	if req.has("color"): tc.font_color = Color.html(req.color)
	if req.has("outline_size"): tc.outline_size = int(req.outline_size)
	if req.has("outline_color"): tc.outline_color = Color.html(req.outline_color)
	if req.has("shadow_size"): tc.shadow_size = int(req.shadow_size)
	if req.has("shadow_color"): tc.shadow_color = Color.html(req.shadow_color)
	if req.has("horizontal_alignment"):
		var align: String = str(req.horizontal_alignment).to_lower()
		match align:
			"left", "0": tc.horizontal_alignment = 0
			"center", "1": tc.horizontal_alignment = 1
			"right", "2": tc.horizontal_alignment = 2
	Scene2.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_send_response(conn, 200, {"result": "text_updated", "text": tc.text})


# ── Media Import to Project Filesystem ─────────────────────────────────────

func _cmd_media_import(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var paths: Array = []
	if req.has("path"):
		paths.append(str(req.path))
	elif req.has("paths"):
		for p in req.paths:
			paths.append(str(p))
	if paths.is_empty():
		_send_response(conn, 400, {"error": "Need 'path' or 'paths' parameter"})
		return
	var results: Array[Dictionary] = []
	for path: String in paths:
		if not FileAccess.file_exists(path):
			results.append({"path": path, "error": "File not found"})
			continue
		var ids_exists: PackedStringArray = EditorServer.get_ids_from_pathes(DirAccess.get_files_at(ProjectServer2.project_thumbnail_path))
		var err: MediaCache.LOAD_ERR = MediaCache.register_from_path(path, ids_exists)
		if err == MediaCache.LOAD_ERR.SUCCESS:
			results.append({"path": path, "result": "imported"})
		elif err == MediaCache.LOAD_ERR.LOAD_ERR_ALREADY_EXISTS:
			results.append({"path": path, "result": "already_imported"})
		else:
			results.append({"path": path, "error": "Failed: " + str(err)})
	_send_response(conn, 200, {"results": results, "total": results.size()})


# ── Component Enable/Disable ────────────────────────────────────────────────

func _cmd_comp_enable(conn: StreamPeerTCP, req: Dictionary) -> void:
	_cmd_comp_set_enabled(conn, req, true)

func _cmd_comp_disable(conn: StreamPeerTCP, req: Dictionary) -> void:
	_cmd_comp_set_enabled(conn, req, false)

func _cmd_comp_set_enabled(conn: StreamPeerTCP, req: Dictionary, enabled: bool) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var index: int = req.get("index", -1)
	var section: String = req.get("section", "Display2D")
	if layer_idx < 0 or frame < 0 or index < 0:
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'index'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var comps: Array = c.get_section_comps_absolute(section)
	if index < 0 or index >= comps.size():
		_send_response(conn, 400, {"error": "Component index out of range"})
		return
	comps[index].enabled = enabled
	Scene2.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_send_response(conn, 200, {"result": "component_" + ("enabled" if enabled else "disabled"), "index": index})


# ── Layer Duplicate ─────────────────────────────────────────────────────────

func _cmd_layer_duplicate(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("index", -1)
	if layer_idx < 0:
		_send_response(conn, 400, {"error": "Need 'index' parameter"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var src_layer: LayerRes = root.layers[layer_idx]
	var new_idx: int = layer_idx + 1
	var new_layer: LayerRes = root.add_layer(new_idx)
	new_layer.custom_name = src_layer.custom_name + " Copy"
	new_layer.locked = src_layer.locked
	new_layer.hidden = src_layer.hidden
	new_layer.custom_color = src_layer.custom_color
	if new_layer is RootLayerRes and src_layer is RootLayerRes:
		(new_layer as RootLayerRes).mute = (src_layer as RootLayerRes).mute
		(new_layer as RootLayerRes).volume = (src_layer as RootLayerRes).volume
	var added_clips: int = 0
	for frame: int in src_layer.clips:
		var orig: MediaClipRes = src_layer.clips[frame]
		var dupl: MediaClipRes = orig.duplicate_media_res()
		root.add_clips(new_idx, frame, [dupl], 0, false, false)
		added_clips += 1
	_send_response(conn, 200, {"result": "layer_duplicated", "from": layer_idx, "to": new_idx, "clips": added_clips})


# ── Timeline Navigation ─────────────────────────────────────────────────────

func _cmd_timeline_goto(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var frame: int = req.get("frame", -1)
	if frame < 0:
		_send_response(conn, 400, {"error": "Need 'frame' parameter"})
		return
	PlaybackServer.stop()
	PlaybackServer.position = frame
	_send_response(conn, 200, {"result": "seeked", "frame": frame})

func _cmd_timeline_length(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if req.has("set"):
		var new_len: int = int(req.set)
		if new_len > 0:
			root.length = new_len
			_send_response(conn, 200, {"result": "length_set", "length": new_len})
		else:
			_send_response(conn, 400, {"error": "Length must be > 0"})
	else:
		_send_response(conn, 200, {"length": root.length})


# ── Component Commands ───────────────────────────────────────────────────────

func _cmd_comp_list(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	var sections: Array[Dictionary] = []
	for section_key: StringName in ClassServer.comps_sections_infos:
		var info: ClassServer.CompsSectionInfo = ClassServer.comps_sections_infos[section_key]
		var subsections: Array[Dictionary] = []
		for sub: StringName in info.subsections:
			var comps: Dictionary = ClassServer.component_res_sorted_by_sections.get(section_key, {}).get(sub, {})
			var names: Array[String] = []
			for cn: StringName in comps:
				names.append(cn)
			subsections.append({"name": sub, "components": names})
		sections.append({"section": section_key, "subsections": subsections})
	_send_response(conn, 200, {"sections": sections})

func _cmd_comp_list_available(conn: StreamPeerTCP, _req: Dictionary) -> void:
	var all: Array[String] = []
	for cn: StringName in ClassServer.component_res_classes:
		all.append(cn)
	var media_types: Array[String] = []
	for cn: StringName in ClassServer.media_clip_classes:
		media_types.append(cn)
	_send_response(conn, 200, {"components": all, "clip_types": media_types})

func _cmd_comp_add(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var section: String = req.get("section", "Display2D")
	var comp_type: String = req.get("type", "")
	if layer_idx < 0 or frame < 0 or comp_type.is_empty():
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'type'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	if not ClassServer.component_res_classes.has(comp_type):
		_send_response(conn, 400, {"error": "Unknown component: " + comp_type})
		return
	var comp: ComponentRes = ClassServer.component_res_classes[comp_type].script.new()
	c.add_component(section, comp)
	_log_change("terminal", "component_added", comp_type, {"layer": layer_idx, "frame": frame, "section": section})
	_send_response(conn, 200, {"result": "component_added", "type": comp_type, "section": section})

func _cmd_comp_remove(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var index: int = req.get("index", -1)
	var section: String = req.get("section", "Display2D")
	if layer_idx < 0 or frame < 0 or index < 0:
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'index'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var comps: Array = c.get_section_comps_absolute(section)
	if index < 0 or index >= comps.size():
		_send_response(conn, 400, {"error": "Component index out of range"})
		return
	c.remove_at_component(section, index)
	_send_response(conn, 200, {"result": "component_removed"})

func _cmd_comp_move(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var from_idx: int = req.get("from", -1)
	var to_idx: int = req.get("to", -1)
	var section: String = req.get("section", "Display2D")
	if layer_idx < 0 or frame < 0 or from_idx < 0 or to_idx < 0:
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'from', 'to'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	c.move_component(section, from_idx, to_idx)
	_send_response(conn, 200, {"result": "component_moved"})

func _cmd_comp_set(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var index: int = req.get("index", -1)
	var section: String = req.get("section", "Display2D")
	var property: String = req.get("property", "")
	var value = req.get("value", null)
	if layer_idx < 0 or frame < 0 or index < 0 or property.is_empty() or value == null:
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'index', 'property', 'value'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var comps: Array = c.get_section_comps_absolute(section)
	if index < 0 or index >= comps.size():
		_send_response(conn, 400, {"error": "Component index out of range"})
		return
	comps[index].set(property, _parse_value(value))
	_log_change("terminal", "property_set", "%s.%s" % [comps[index].get_classname(), property], {"layer": layer_idx, "frame": frame, "section": section, "index": index, "value": str(value)})
	_send_response(conn, 200, {"result": "property_set", "property": property})

func _cmd_comp_get(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var index: int = req.get("index", -1)
	var section: String = req.get("section", "Display2D")
	if layer_idx < 0 or frame < 0 or index < 0:
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'index'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	if layer_idx >= root.layers.size():
		_send_response(conn, 400, {"error": "Layer index out of range"})
		return
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var comps: Array = c.get_section_comps_absolute(section)
	if index < 0 or index >= comps.size():
		_send_response(conn, 400, {"error": "Component index out of range"})
		return
	var comp: ComponentRes = comps[index]
	var props: Dictionary = {}
	for p: Dictionary in comp.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var pv = comp.get(p.name)
			if typeof(pv) == TYPE_OBJECT and pv is Resource:
				props[p.name] = "<resource:%s>" % pv.resource_path if pv.resource_path else "<resource>"
			else:
				props[p.name] = pv
	_send_response(conn, 200, {"classname": comp.get_classname(), "section": section, "index": index, "enabled": comp.enabled, "forced": comp.forced, "properties": props})

func _parse_value(val) -> Variant:
	if val is Dictionary and val.has("type"):
		match val.type:
			"Vector2": return Vector2(val.get("x", 0), val.get("y", 0))
			"Vector3": return Vector3(val.get("x", 0), val.get("y", 0), val.get("z", 0))
			"Color":
				return Color(
					val.get("r", 1.0), val.get("g", 1.0),
					val.get("b", 1.0), val.get("a", 1.0)
				)
			"Color_html": return Color.html(val.get("html", "#ffffff"))
	return val


# ── Render Commands ──────────────────────────────────────────────────────────

func _cmd_render_start(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	if Renderer.is_working:
		_send_response(conn, 400, {"error": "Already rendering"})
		return
	var output: String = req.get("output", "")
	if output.is_empty():
		output = ProjectServer2.project_path.path_join("render_output.mp4")
	_send_response(conn, 200, {"result": "render_started", "output": output})
	Renderer.start(output, null, null)

func _cmd_render_cancel(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not Renderer.is_working:
		_send_response(conn, 400, {"error": "Not rendering"})
		return
	Renderer.cancel()
	_send_response(conn, 200, {"result": "render_cancelled"})

func _cmd_render_settings(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var p: ProjectRes = ProjectServer2.project_res
	if req.get("get", false):
		_send_response(conn, 200, {
			"fps": p.fps,
			"resolution": {"width": p.resolution.x, "height": p.resolution.y},
			"length_frames": p.root_clip_res.length,
			"is_rendering": Renderer.is_working,
			"is_paused": Renderer.is_paused,
			"ffmpeg_path": Renderer._ffmpeg_path
		})
		return
	_send_response(conn, 200, {"result": "use eval for granular render settings"})


# ── Playback Commands ────────────────────────────────────────────────────────

func _cmd_playback_play(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	if not PlaybackServer.is_playing():
		PlaybackServer.play()
	_send_response(conn, 200, {"result": "playing"})

func _cmd_playback_stop(conn: StreamPeerTCP, _req: Dictionary) -> void:
	PlaybackServer.stop()
	_send_response(conn, 200, {"result": "stopped"})

func _cmd_playback_seek(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var frame: int = req.get("frame", -1)
	if frame < 0:
		_send_response(conn, 400, {"error": "Need 'frame' parameter"})
		return
	PlaybackServer.position = frame
	_send_response(conn, 200, {"result": "seeked", "frame": frame})

func _cmd_playback_set(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	if req.has("volume"):
		PlaybackServer.volume = clampf(float(req.volume), 0.0, 1.0)
	if req.has("replay"):
		EditorServer.editor_settings.edit.replay = bool(req.replay)
	_send_response(conn, 200, {"result": "playback_updated"})


# ── Media Commands ───────────────────────────────────────────────────────────

func _cmd_media_list(conn: StreamPeerTCP, req: Dictionary) -> void:
	var filter: String = req.get("filter", "all")
	var out: Dictionary = {}
	if filter == "all" or filter == "images":
		var imgs: Array[Dictionary] = []
		for p: StringName in MediaCache.images:
			imgs.append({"path": p, "size": MediaCache.images[p].get_size()})
		out["images"] = imgs
	if filter == "all" or filter == "videos":
		var vids: Array[Dictionary] = []
		for p: StringName in MediaCache.video_contexts:
			var ctx: MediaCache.VideoContext = MediaCache.video_contexts[p]
			vids.append({"path": p, "resolution": str(ctx.resolution), "fps": ctx.fps, "duration": ctx.duration, "frames": ctx.total_frames})
		out["videos"] = vids
	if filter == "all" or filter == "audio":
		var auds: Array[Dictionary] = []
		for p: StringName in MediaCache.audio_datas:
			auds.append({"path": p})
		out["audio"] = auds
	_send_response(conn, 200, out)

func _cmd_media_register(conn: StreamPeerTCP, req: Dictionary) -> void:
	var path: String = req.get("path", "")
	if not _require_media_path(path):
		_send_response(conn, 400, {"error": "File not found: " + path})
		return
	var ids_exists: PackedStringArray = EditorServer.get_ids_from_pathes(DirAccess.get_files_at(ProjectServer2.project_thumbnail_path))
	var err: MediaCache.LOAD_ERR = MediaCache.register_from_path(path, ids_exists)
	if err == MediaCache.LOAD_ERR.SUCCESS:
		_send_response(conn, 200, {"result": "registered", "path": path})
	elif err == MediaCache.LOAD_ERR.LOAD_ERR_ALREADY_EXISTS:
		_send_response(conn, 200, {"result": "already_registered", "path": path})
	else:
		_send_response(conn, 500, {"error": "Failed to register: " + str(err)})

func _cmd_media_remove(conn: StreamPeerTCP, req: Dictionary) -> void:
	var path: String = req.get("path", "")
	if path.is_empty():
		_send_response(conn, 400, {"error": "Need 'path' parameter"})
		return
	MediaCache.deregister_from_path(path, "", ProjectServer2.project_thumbnail_path, ProjectServer2.project_waveform_path)
	_send_response(conn, 200, {"result": "deregistered", "path": path})


# ── Undo/Redo ────────────────────────────────────────────────────────────────

func _cmd_undo(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	ProjectServer2.undo()
	_send_response(conn, 200, {"result": "undone"})

func _cmd_redo(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	ProjectServer2.redo()
	_send_response(conn, 200, {"result": "redone"})


# ── Time Marker Commands ─────────────────────────────────────────────────────

func _cmd_timemarker_add(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var frame: int = req.get("frame", -1)
	if frame < 0:
		frame = PlaybackServer.position
	var p: ProjectRes = ProjectServer2.project_res
	p.add_timemarker(frame)
	_send_response(conn, 200, {"result": "timemarker_added", "frame": frame})

func _cmd_timemarker_remove(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var frame: int = req.get("frame", -1)
	if frame < 0:
		_send_response(conn, 400, {"error": "Need 'frame' parameter"})
		return
	var p: ProjectRes = ProjectServer2.project_res
	p.remove_timemarker(frame)
	_send_response(conn, 200, {"result": "timemarker_removed", "frame": frame})

func _cmd_timemarker_list(conn: StreamPeerTCP, _req: Dictionary) -> void:
	if not _require_project(conn): return
	var markers: Array[Dictionary] = []
	var p: ProjectRes = ProjectServer2.project_res
	for frame: int in p.timemarkers:
		markers.append({"frame": frame})
	_send_response(conn, 200, {"timemarkers": markers})


# ── Editor Settings Command ──────────────────────────────────────────────────

func _cmd_editor_settings(conn: StreamPeerTCP, req: Dictionary) -> void:
	if req.get("get", false):
		var es = EditorServer.editor_settings
		_send_response(conn, 200, {
			"version": EditorServer.version_info.version_name,
			"replay": es.edit.replay,
			"auto_save_interval": es.edit.auto_save_interval,
			"frames_dropped": es.performance.frames_dropped,
			"video_scale_factor": es.performance.video_scale_factor,
			"video_max_frame_cache": es.performance.video_max_frame_cache,
			"low_quality_for_playback": es.performance.low_quality_for_playback,
			"content_scale": es.theme.content_scale
		})
		return
	if req.has("replay"):
		EditorServer.editor_settings.edit.replay = bool(req.replay)
		_send_response(conn, 200, {"result": "replay_updated"})
		return
	_send_response(conn, 200, {"result": "use get=true to read, or set specific fields"})


# ── Keyframe Commands ────────────────────────────────────────────────────────

func _cmd_keyframe_add(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var comp_idx: int = req.get("comp_index", 0)
	var property: String = req.get("property", "")
	var keyframe_frame: int = req.get("keyframe_frame", -1)
	var section: String = req.get("section", "Display2D")
	if layer_idx < 0 or frame < 0 or property.is_empty() or keyframe_frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'property', 'keyframe_frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var comps: Array = c.get_section_comps_absolute(section)
	if comp_idx < 0 or comp_idx >= comps.size():
		_send_response(conn, 400, {"error": "Component index out of range"})
		return
	var comp: ComponentRes = comps[comp_idx]
	var val = comp.get(property)
	if val == null:
		_send_response(conn, 400, {"error": "Property not found: " + property})
		return
	comp.request_animation_keyframe(comp, property, val, keyframe_frame)
	_send_response(conn, 200, {"result": "keyframe_added", "property": property, "frame": keyframe_frame})

func _cmd_keyframe_remove(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var comp_idx: int = req.get("comp_index", 0)
	var property: String = req.get("property", "")
	var keyframe_frame: int = req.get("keyframe_frame", -1)
	var section: String = req.get("section", "Display2D")
	if layer_idx < 0 or frame < 0 or property.is_empty() or keyframe_frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer', 'frame', 'property', 'keyframe_frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var comps: Array = c.get_section_comps_absolute(section)
	if comp_idx < 0 or comp_idx >= comps.size():
		_send_response(conn, 400, {"error": "Component index out of range"})
		return
	var comp: ComponentRes = comps[comp_idx]
	comp.remove_animation_keyframe(comp, property, keyframe_frame)
	_send_response(conn, 200, {"result": "keyframe_removed"})

func _cmd_keyframe_list(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var layer_idx: int = req.get("layer", -1)
	var frame: int = req.get("frame", -1)
	var section: String = req.get("section", "Display2D")
	if layer_idx < 0 or frame < 0:
		_send_response(conn, 400, {"error": "Need 'layer' and 'frame'"})
		return
	var root: RootClipRes = ProjectServer2.project_res.root_clip_res
	var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
	if not c:
		_send_response(conn, 400, {"error": "No clip at that position"})
		return
	var kfs: Array[Dictionary] = []
	for section_key: String in c.components:
		for comp: ComponentRes in c.components[section_key]:
			if comp.animations.has(comp):
				var anims: Dictionary = comp.animations[comp]
				for prop_key: String in anims:
					var anim_res: AnimationRes = anims[prop_key]
					for pi: int in anim_res.profiles.size():
						var profile: CurveProfile = anim_res.profiles[pi]
						for kf: int in profile.keys:
							kfs.append({"component": comp.get_classname(), "property": prop_key, "frame": kf, "value": profile.keys[kf].value})
	_send_response(conn, 200, {"keyframes": kfs})


# ── Context Command (full project state as text) ───────────────────────────

func _cmd_context(conn: StreamPeerTCP, req: Dictionary) -> void:
	var lines: PackedStringArray = []
	var fmt: String = req.get("format", "text")

	if not ProjectServer2.project_res or not ProjectServer2.project_res.root_clip_res:
		_send_response(conn, 200, {"format": fmt, "context": "No project open."})
		return

	var p: ProjectRes = ProjectServer2.project_res
	var root: RootClipRes = p.root_clip_res

	lines.append("=== PROJECT: %s ===" % p.project_name)
	lines.append("FPS: %d | Resolution: %dx%d | Length: %d frames | Delta: %.4f" % [p.fps, p.resolution.x, p.resolution.y, root.length, p.delta])
	lines.append("Timemarkers: %d" % p.timemarkers.size())

	var markers: Array[int] = []
	for mf: int in p.timemarkers:
		markers.append(mf)
	markers.sort()
	if markers.size() > 0:
		lines.append("Marker frames: %s" % str(markers))

	lines.append("")
	lines.append("--- PLAYBACK ---")
	lines.append("Frame: %d | Playing: %s | Volume: %.2f" % [PlaybackServer.position, PlaybackServer.is_playing(), PlaybackServer.volume if "volume" in PlaybackServer else 1.0])
	lines.append("Render: working=%s paused=%s" % [Renderer.is_working, Renderer.is_paused])

	lines.append("")
	lines.append("--- LAYERS (%d total) ---" % root.layers.size())

	for li: int in root.layers.size():
		var layer: LayerRes = root.layers[li]
		var name_str: String = layer.custom_name if not layer.custom_name.is_empty() else "(unnamed)"
		var flags: String = ""
		if layer.locked: flags += " LOCKED"
		if layer.hidden: flags += " HIDDEN"
		if layer is RootLayerRes:
			var rl: RootLayerRes = layer
			if rl.mute: flags += " MUTED"
			flags += " vol=%.2f" % rl.volume
		lines.append("")
		lines.append("  Layer %d: %s%s" % [li, name_str, flags])
		lines.append("  Clips: %d" % layer.clips.size())

		var sorted_frames: Array[int] = []
		for cf: int in layer.clips:
			sorted_frames.append(cf)
		sorted_frames.sort()

		for cf: int in sorted_frames:
			var c: MediaClipRes = layer.clips[cf]
			var ct: String = c.get_classname()
			var cn: String = c.get_display_name()
			lines.append("    [%d] %s (%s) from=%d len=%d id=%s" % [cf, cn, ct, c.from, c.length, c.id])

			for section_key: String in c.components:
				var comps: Array = c.components[section_key]
				if comps.is_empty(): continue
				lines.append("      Section <%s>:" % section_key)
				for ci: int in comps.size():
					var comp: ComponentRes = comps[ci]
					var cname: String = comp.get_classname()
					var status: String = ""
					if comp.forced: status += " [forced]"
					if not comp.enabled: status += " [disabled]"
					lines.append("        %d: %s%s" % [ci, cname, status])

					var props_out: PackedStringArray = []
					for prop_d: Dictionary in comp.get_property_list():
						if prop_d.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
							var pname: String = prop_d.name
							if pname in ["animations", "captured_props", "properties", "enabled", "forced", "method_type", "owner", "get_prop_func"]:
								continue
							var pval = comp.get(pname)
							if typeof(pval) == TYPE_OBJECT:
								if pval is Resource:
									props_out.append("%s=<res>" % pname)
							elif typeof(pval) == TYPE_VECTOR2:
								props_out.append("%s=(%.2f,%.2f)" % [pname, pval.x, pval.y])
							elif typeof(pval) == TYPE_COLOR:
								props_out.append("%s=#%s" % [pname, pval.to_html()])
							elif typeof(pval) == TYPE_BOOL:
								props_out.append("%s=%s" % [pname, str(pval).to_lower()])
							elif typeof(pval) in [TYPE_INT, TYPE_FLOAT]:
								props_out.append("%s=%s" % [pname, str(pval)])
							elif typeof(pval) == TYPE_STRING and not (pval as String).is_empty():
								var short: String = (pval as String)
								if short.length() > 60:
									short = short.substr(0, 57) + "..."
								props_out.append("%s=\"%s\"" % [pname, short])
					if props_out.size() > 0:
						lines.append("          props: %s" % ", ".join(props_out))

					if comp.animations.has(comp):
						var anims: Dictionary = comp.animations[comp]
						for prop_key: String in anims:
							var anim_res: AnimationRes = anims[prop_key]
							var kf_count: int = 0
							for pi: int in anim_res.profiles.size():
								kf_count += anim_res.profiles[pi].keys.size()
							if kf_count > 0:
								lines.append("          keyframes: %d on '%s'" % [kf_count, prop_key])

	if fmt == "text":
		_send_response(conn, 200, {"format": "text", "context": "\n".join(lines)})
	else:
		_send_response(conn, 200, {"format": fmt, "error": "Unsupported format. Use 'text'."})


func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


# ── Transcribe Command (Speech-to-Text via Whisper API) ──────────────────

func _cmd_transcribe(conn: StreamPeerTCP, req: Dictionary) -> void:
	var path: String = req.get("path", "")
	if path.is_empty():
		var layer_idx: int = req.get("layer", -1)
		var frame: int = req.get("frame", -1)
		if layer_idx >= 0 and frame >= 0:
			if not _require_project(conn): return
			var root: RootClipRes = ProjectServer2.project_res.root_clip_res
			if layer_idx < root.layers.size():
				var c: MediaClipRes = root.layers[layer_idx].clips.get(frame)
				if c:
					if c.has_method("get_file_path"):
						path = c.get_file_path()
					var cn: String = c.get_classname()
					match cn:
						"VideoClipRes":
							var vcr: VideoClipRes = c as VideoClipRes
							if vcr and not vcr.video.is_empty():
								path = vcr.video
						"ImageClipRes":
							var icr: ImageClipRes = c as ImageClipRes
							if icr and not icr.image.is_empty():
								path = icr.image
						"AudioClipRes":
							var acr: AudioClipRes = c as AudioClipRes
							if acr and not acr.audio.is_empty():
								path = acr.audio
	if path.is_empty():
		_send_response(conn, 400, {"error": "Need 'path' or 'layer'+'frame'"})
		return
	path = _resolve_path(path)
	if not FileAccess.file_exists(path):
		_send_response(conn, 404, {"error": "File not found: " + path})
		return

	var max_secs: int = clampi(req.get("max_secs", 60), 1, 600)
	var model_size: String = req.get("model", "base")

	# Extract audio via ffmpeg to temp WAV
	var temp_dir: String = ProjectSettings.globalize_path("user://.hms_transcribe")
	var wav_path: String = temp_dir + "/audio.wav"
	DirAccess.make_dir_recursive_absolute(temp_dir)

	var ffmpeg_cmd: String = ProjectSettings.globalize_path("res://addons/ffmpeg_codec/ffmpeg.exe")
	if not FileAccess.file_exists(ffmpeg_cmd):
		ffmpeg_cmd = "ffmpeg"
	var ffmpeg_args: PackedStringArray = ["-y", "-i", path, "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1"]
	if max_secs > 0:
		ffmpeg_args.append("-t")
		ffmpeg_args.append(str(max_secs))
	ffmpeg_args.append(ProjectSettings.globalize_path(wav_path))
	var ff_output: Array[String] = []
	var ff_exit: int = OS.execute(ffmpeg_cmd, ffmpeg_args, ff_output, true)
	if ff_exit != 0:
		_send_response(conn, 500, {"error": "ffmpeg failed", "details": "\n".join(ff_output)})
		return

	# Run faster-whisper locally via Python (write result to file to avoid code-page issues)
	var script_path: String = ProjectSettings.globalize_path("res://addons/hms_scripts/transcribe.py")
	var result_path: String = temp_dir + "/result.json"
	DirAccess.remove_absolute(result_path)
	var py_args: PackedStringArray = ["-u", script_path, model_size, ProjectSettings.globalize_path(wav_path), result_path]
	var py_output: Array[String] = []
	var py_exit: int = OS.execute("py", py_args, py_output, true)
	DirAccess.remove_absolute(wav_path)

	if py_exit != 0:
		_send_response(conn, 500, {"error": "Local Whisper failed", "details": "\n".join(py_output)})
		return

	if not FileAccess.file_exists(result_path):
		_send_response(conn, 500, {"error": "No result file produced", "details": "\n".join(py_output)})
		return

	var rf: FileAccess = FileAccess.open(result_path, FileAccess.READ)
	var result_str: String = rf.get_as_text() if rf else ""
	if rf: rf.close()
	DirAccess.remove_absolute(result_path)

	var j: JSON = JSON.new()
	if j.parse(result_str) == OK and j.data is Dictionary:
		var d: Dictionary = j.data
		if d.has("error"):
			_send_response(conn, 500, {"error": "Whisper error: " + d["error"]})
			return
		var transcript: String = d.get("text", result_str)
		var resp_data: Dictionary = {"transcript": transcript}
		if d.has("language"): resp_data["language"] = d["language"]
		if d.has("duration"): resp_data["duration"] = d["duration"]
		_send_response(conn, 200, resp_data)
		return
	_send_response(conn, 200, {"transcript": result_str})


# ── Style Profile Commands ─────────────────────────────────────────────────

var _style_profiles_dir: String = "res://profiles"
var _style_sessions_dir: String = "res://profiles/sessions"
var _style_session: Dictionary = {}
var _style_decisions: Array = []
var _style_questions: Array = []

func _style_get_profiles_path() -> String:
	return ProjectSettings.globalize_path(_style_profiles_dir)

func _style_get_sessions_path() -> String:
	return ProjectSettings.globalize_path(_style_sessions_dir)

func _style_ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)

func _style_save_json(path: String, data: Dictionary) -> bool:
	_style_ensure_dir(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not f: return false
	f.store_string(JSON.new().stringify(data, "\t"))
	f.close()
	return true

func _style_load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not f: return {}
	var text: String = f.get_as_text()
	f.close()
	var j: JSON = JSON.new()
	if j.parse(text) != OK: return {}
	return j.data if j.data is Dictionary else {}

func _style_list_files(dir_path: String, ext: String) -> Array:
	_style_ensure_dir(dir_path)
	var result: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if not dir: return result
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(ext):
			result.append(fname.get_basename())
		fname = dir.get_next()
	dir.list_dir_end()
	return result

func _style_average(arr: Array) -> float:
	if arr.is_empty(): return 0.0
	var s: float = 0.0
	for v in arr: s += float(v)
	return s / arr.size()

func _style_mode(arr: Array) -> int:
	if arr.is_empty(): return 0
	var counts: Dictionary = {}
	for v in arr: counts[v] = counts.get(v, 0) + 1
	var best: int = arr[0]
	var best_count: int = 0
	for k in counts:
		if counts[k] > best_count:
			best_count = counts[k]
			best = k
	return best

func _style_range(arr: Array) -> Dictionary:
	if arr.is_empty(): return {"min": 0, "max": 0}
	var mn: float = float(arr[0])
	var mx: float = float(arr[0])
	for v in arr:
		var fv: float = float(v)
		if fv < mn: mn = fv
		if fv > mx: mx = fv
	return {"min": mn, "max": mx}

func _style_analyze_project(state: Dictionary) -> Dictionary:
	if state.is_empty() or state.get("empty", false): return {}
	var freq: Dictionary = {}
	var settings: Dictionary = {}
	var total_clips: int = 0
	var text_sizes: Array = []
	var text_count: int = 0
	var outline_count: int = 0
	var shadow_count: int = 0
	var transitions: Array = []
	var in_durs: Array = []
	var out_durs: Array = []
	var sat_vals: Array = []
	var durations: Array = []

	for layer: Dictionary in state.get("layers", []):
		for clip: Dictionary in layer.get("clips", []):
			total_clips += 1
			durations.append(clip.get("length", 0))
			if clip.get("type", "") == "Text2DClipRes":
				text_count += 1
				text_sizes.append(clip.get("font_size", 24))
			for section: String in clip.get("components", {}):
				for comp: Dictionary in clip["components"][section]:
					var cn: String = comp.get("classname", "")
					if cn.is_empty(): continue
					freq[cn] = freq.get(cn, 0) + 1
					if not settings.has(cn): settings[cn] = comp.get("props", {})
					var props: Dictionary = comp.get("props", {})
					if cn in ["CompHSL", "CompHSLPerColor"] and props.has("saturation"):
						sat_vals.append(props["saturation"])
					if cn in ["CompFade", "CompSlide", "CompSwing", "CompPopup", "CompTextInOutType"]:
						transitions.append(cn)
						if props.has("in_duration"): in_durs.append(props["in_duration"])
						if props.has("out_duration"): out_durs.append(props["out_duration"])
					if props.has("outline_size") and props["outline_size"] > 0: outline_count += 1
					if props.has("shadow_size") and props["shadow_size"] > 0: shadow_count += 1

	var sorted_effects: Array = freq.keys()
	sorted_effects.sort_custom(func(a, b): return freq[a] > freq[b])
	var avg_dur: float = _style_average(durations)
	var pacing: String = "moderate"
	if avg_dur < 30: pacing = "fast"
	elif avg_dur > 120: pacing = "slow"
	var style: String = "balanced"
	if "CompFilmGrain" in sorted_effects or "CompVignette" in sorted_effects or "CompBars" in sorted_effects:
		style = "cinematic"
	elif "CompGlitch" in sorted_effects or "CompVHS" in sorted_effects:
		style = "retro"
	elif pacing == "fast": style = "energetic"
	var complexity: String = "basic"
	if freq.size() > 8: complexity = "advanced"
	elif freq.size() > 4: complexity = "intermediate"

	return {
		"profile_name": "",
		"created_at": Time.get_datetime_string_from_system(false, true),
		"analyzed_from": 1,
		"summary": {"editing_style": style, "complexity": complexity, "has_text": text_count > 0, "has_transitions": transitions.size() > 0, "pacing": pacing},
		"effects": {"frequency": freq, "top_effects": sorted_effects.slice(0, 10), "default_settings": settings, "total_clips": total_clips, "unique_effects": freq.size()},
		"text_style": {"total_clips": text_count, "font_sizes": text_sizes, "most_used_size": _style_mode(text_sizes) if text_sizes.size() > 0 else 24, "has_outlines": outline_count > text_count * 0.3, "has_shadows": shadow_count > text_count * 0.3},
		"color_grading": {"average_saturation": _style_average(sat_vals), "warmth": "warm" if _style_average(sat_vals) > 0.1 else ("cool" if _style_average(sat_vals) < -0.1 else "neutral")},
		"transitions": {"preferred": transitions.slice(0, 5), "frequency": freq, "in_duration_range": _style_range(in_durs), "out_duration_range": _style_range(out_durs), "has_transitions": transitions.size() > 0},
		"timing": {"average_clip_duration": avg_dur, "clip_duration_range": _style_range(durations), "pacing": pacing, "total_clips": total_clips},
		"avoid": []
	}

func _style_compare(a: Dictionary, b: Dictionary) -> Dictionary:
	var score: float = 0.0
	var details: Dictionary = {}
	var feedback: Array = []
	var fa: Dictionary = a.get("effects", {}).get("frequency", {})
	var fb: Dictionary = b.get("effects", {}).get("frequency", {})
	if not fa.is_empty():
		var matches: int = 0
		for eff: String in fa:
			if fb.has(eff): matches += 1
			else: feedback.append("Missing effect: " + eff)
		var eff_score: float = float(matches) / maxf(float(fa.size()), 1.0)
		score += eff_score * 0.4
		details["effects_match"] = roundi(eff_score * 100)
	else:
		details["effects_match"] = 50
	var sat_a: float = a.get("color_grading", {}).get("average_saturation", 0.0)
	var sat_b: float = b.get("color_grading", {}).get("average_saturation", 0.0)
	var color_score: float = maxf(1.0 - absf(sat_a - sat_b), 0.0)
	score += color_score * 0.3
	details["color_match"] = roundi(color_score * 100)
	var size_a: int = a.get("text_style", {}).get("most_used_size", 24)
	var size_b: int = b.get("text_style", {}).get("most_used_size", 24)
	var text_score: float = maxf(1.0 - absf(float(size_a - size_b)) / 50.0, 0.0)
	score += text_score * 0.2
	details["text_match"] = roundi(text_score * 100)
	var dur_a: float = a.get("timing", {}).get("average_clip_duration", 60)
	var dur_b: float = b.get("timing", {}).get("average_clip_duration", 60)
	var time_score: float = maxf(1.0 - absf(dur_a - dur_b) / maxf(dur_a, 1.0), 0.0)
	score += time_score * 0.1
	details["timing_match"] = roundi(time_score * 100)
	var total: int = roundi(score * 100)
	var rating: String = "poor"
	if total >= 85: rating = "excellent"
	elif total >= 70: rating = "good"
	elif total >= 50: rating = "fair"
	return {"score": total, "rating": rating, "details": details, "feedback": feedback}

# ── Style Command Handlers ─────────────────────────────────────────────────

func _cmd_style_analyze(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var state: Dictionary = _capture_state_snapshot()
	if state.is_empty() or state.get("empty", false):
		_send_response(conn, 400, {"error": "No project data to analyze"})
		return
	var profile: Dictionary = _style_analyze_project(state)
	if profile.is_empty():
		_send_response(conn, 500, {"error": "Analysis failed"})
		return
	var profile_name: String = req.get("name", "")
	if profile_name.is_empty():
		profile_name = str(ProjectServer2.project_res.project_name).to_lower().replace(" ", "_")
	profile["profile_name"] = profile_name
	var path: String = _style_get_profiles_path() + "/" + profile_name + ".json"
	var save: bool = _style_save_json(path, profile)
	_log_change("terminal", "style_analyzed", profile_name, {})
	_send_response(conn, 200, {"result": "profile_saved" if save else "analysis_only", "profile_name": profile_name, "summary": profile.summary, "effects_count": profile.effects.unique_effects, "text_clips": profile.text_style.total_clips, "pacing": profile.timing.pacing})

func _cmd_style_list(conn: StreamPeerTCP, req: Dictionary) -> void:
	var profiles: Array = _style_list_files(_style_get_profiles_path(), ".json")
	_send_response(conn, 200, {"profiles": profiles, "total": profiles.size()})

func _cmd_style_info(conn: StreamPeerTCP, req: Dictionary) -> void:
	var pn: String = req.get("name", "")
	if pn.is_empty():
		_send_response(conn, 400, {"error": "Need 'name' parameter"})
		return
	var profile: Dictionary = _style_load_json(_style_get_profiles_path() + "/" + pn + ".json")
	if profile.is_empty():
		_send_response(conn, 404, {"error": "Profile not found: " + pn})
		return
	_send_response(conn, 200, {"profile": profile})

func _cmd_style_delete(conn: StreamPeerTCP, req: Dictionary) -> void:
	var pn: String = req.get("name", "")
	if pn.is_empty():
		_send_response(conn, 400, {"error": "Need 'name' parameter"})
		return
	var path: String = _style_get_profiles_path() + "/" + pn + ".json"
	var deleted: bool = FileAccess.file_exists(path)
	if deleted: DirAccess.remove_absolute(path)
	_send_response(conn, 200, {"result": "deleted" if deleted else "not_found", "name": pn})

func _cmd_style_compare(conn: StreamPeerTCP, req: Dictionary) -> void:
	var na: String = req.get("a", "")
	var nb: String = req.get("b", "")
	if na.is_empty() or nb.is_empty():
		_send_response(conn, 400, {"error": "Need 'a' and 'b' parameters"})
		return
	var pa: Dictionary = _style_load_json(_style_get_profiles_path() + "/" + na + ".json")
	var pb: Dictionary = _style_load_json(_style_get_profiles_path() + "/" + nb + ".json")
	if pa.is_empty():
		_send_response(conn, 404, {"error": "Profile not found: " + na})
		return
	if pb.is_empty():
		_send_response(conn, 404, {"error": "Profile not found: " + nb})
		return
	_send_response(conn, 200, _style_compare(pa, pb))

func _cmd_style_apply(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var pn: String = req.get("name", "")
	if pn.is_empty():
		_send_response(conn, 400, {"error": "Need 'name' parameter"})
		return
	var profile: Dictionary = _style_load_json(_style_get_profiles_path() + "/" + pn + ".json")
	if profile.is_empty():
		_send_response(conn, 404, {"error": "Profile not found: " + pn})
		return
	_send_response(conn, 200, {"result": "profile_loaded", "profile": pn, "summary": profile.get("summary", {})})

func _cmd_style_teach_start(conn: StreamPeerTCP, req: Dictionary) -> void:
	var video: String = req.get("video", "")
	if video.is_empty():
		_send_response(conn, 400, {"error": "Need 'video' parameter"})
		return
	var sid: String = "session_" + str(int(Time.get_unix_time_from_system()))
	_style_session = {"session_id": sid, "video": video, "started_at": Time.get_datetime_string_from_system(false, true), "status": "guided", "decisions": [], "questions": [], "style_extracted": {}}
	_style_decisions = []
	_style_questions = []
	_send_response(conn, 200, {"result": "session_started", "session_id": sid, "video": video})

func _cmd_style_teach_log(conn: StreamPeerTCP, req: Dictionary) -> void:
	var action: String = req.get("action", "")
	if action.is_empty():
		_send_response(conn, 400, {"error": "Need 'action' parameter"})
		return
	var d: Dictionary = {"step": _style_decisions.size() + 1, "action": action, "details": req.get("details", {}), "reason": req.get("reason", "user_instruction"), "timestamp": Time.get_datetime_string_from_system(false, true)}
	_style_decisions.append(d)
	_style_session["decisions"] = _style_decisions
	_send_response(conn, 200, {"result": "decision_logged", "total_decisions": _style_decisions.size(), "action": action})

func _cmd_style_teach_ask(conn: StreamPeerTCP, req: Dictionary) -> void:
	var question: String = req.get("question", "")
	if question.is_empty():
		var pending: Array = []
		for q: Dictionary in _style_questions:
			if not q.get("answered", false): pending.append(q)
		_send_response(conn, 200, {"pending_questions": pending, "total": pending.size()})
		return
	var q_id: String = "q_" + str(_style_questions.size() + 1)
	var q: Dictionary = {"id": q_id, "question": question, "context": req.get("context", ""), "asked_at": Time.get_datetime_string_from_system(false, true), "user_answer": "", "answered": false}
	_style_questions.append(q)
	_style_session["questions"] = _style_questions
	_send_response(conn, 200, {"result": "question_asked", "question_id": q_id, "question": question})

func _cmd_style_teach_answer(conn: StreamPeerTCP, req: Dictionary) -> void:
	var qid: String = req.get("question_id", "")
	var answer: String = req.get("answer", "")
	if qid.is_empty() or answer.is_empty():
		_send_response(conn, 400, {"error": "Need 'question_id' and 'answer'"})
		return
	for q: Dictionary in _style_questions:
		if q.get("id", "") == qid:
			q["user_answer"] = answer
			q["answered"] = true
			break
	_send_response(conn, 200, {"result": "answer_recorded", "question_id": qid})

func _cmd_style_teach_end(conn: StreamPeerTCP, req: Dictionary) -> void:
	_style_session["status"] = "completed"
	_style_session["ended_at"] = Time.get_datetime_string_from_system(false, true)
	_style_session["decisions"] = _style_decisions
	_style_session["questions"] = _style_questions
	_style_ensure_dir(_style_get_sessions_path())
	var path: String = _style_get_sessions_path() + "/" + _style_session.session_id + ".json"
	var save: bool = _style_save_json(path, _style_session)
	_log_change("terminal", "teach_session_ended", _style_session.session_id, {"decisions": _style_decisions.size()})
	_send_response(conn, 200, {"result": "session_ended", "session_id": _style_session.session_id, "total_decisions": _style_decisions.size(), "total_questions": _style_questions.size(), "saved": save})
	_style_session = {}
	_style_decisions = []
	_style_questions = []

func _cmd_style_practice(conn: StreamPeerTCP, req: Dictionary) -> void:
	if not _require_project(conn): return
	var pn: String = req.get("name", "")
	if pn.is_empty():
		_send_response(conn, 400, {"error": "Need 'name' parameter"})
		return
	var profile: Dictionary = _style_load_json(_style_get_profiles_path() + "/" + pn + ".json")
	if profile.is_empty():
		_send_response(conn, 404, {"error": "Profile not found: " + pn})
		return
	var state: Dictionary = _capture_state_snapshot()
	var top: Array = profile.get("effects", {}).get("top_effects", [])
	_send_response(conn, 200, {"result": "practice_plan", "profile": pn, "top_effects_to_apply": top.slice(0, 5), "project_state": state})

func _cmd_style_evaluate(conn: StreamPeerTCP, req: Dictionary) -> void:
	var sid: String = req.get("session", "")
	var pn: String = req.get("profile", "")
	if sid.is_empty() and pn.is_empty():
		_send_response(conn, 400, {"error": "Need 'session' or 'profile'"})
		return
	var original: Dictionary = {}
	if not sid.is_empty():
		var s: Dictionary = _style_load_json(_style_get_sessions_path() + "/" + sid + ".json")
		original = s
	if not pn.is_empty():
		original = _style_load_json(_style_get_profiles_path() + "/" + pn + ".json")
	if original.is_empty():
		_send_response(conn, 404, {"error": "No data to compare against"})
		return
	if not _require_project(conn): return
	var current: Dictionary = _style_analyze_project(_capture_state_snapshot())
	var comparison: Dictionary = _style_compare(original, current)
	_send_response(conn, 200, {"result": "evaluation", "original_source": sid if not sid.is_empty() else pn, "evaluation": comparison})

func _cmd_style_sessions(conn: StreamPeerTCP, req: Dictionary) -> void:
	var sessions: Array = _style_list_files(_style_get_sessions_path(), ".json")
	_send_response(conn, 200, {"sessions": sessions, "total": sessions.size()})

func _cmd_style_session_load(conn: StreamPeerTCP, req: Dictionary) -> void:
	var sid: String = req.get("session", "")
	if sid.is_empty():
		_send_response(conn, 400, {"error": "Need 'session' parameter"})
		return
	var session: Dictionary = _style_load_json(_style_get_sessions_path() + "/" + sid + ".json")
	if session.is_empty():
		_send_response(conn, 404, {"error": "Session not found: " + sid})
		return
	_send_response(conn, 200, {"session": session})
