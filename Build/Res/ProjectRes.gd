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
class_name ProjectRes extends UsableRes

signal resolution_changed(resolution: Vector2i)
signal fps_changed(fps: int)

signal timemarker_added(frame: int, timemarker: TimeMarkerRes)
signal timemarker_removed(frame: int, timemarker: TimeMarkerRes)
signal timemarker_moved(from_frame: int, to_frame: int, timemarker: TimeMarkerRes)

signal comment_added(frame: int, comment: CommentRes)
signal comment_removed(frame: int, comment: CommentRes)
signal comment_moved(from_frame: int, to_frame: int, comment: CommentRes)

@export var version_name: StringName

@export var project_name: StringName = &"HudMod Video"

@export var resolution: Vector2 = Vector2(1920, 1080):
	set(val):
		resolution = val
		resolution_changed.emit(resolution)

@export var fps: int = 30:
	set(val):
		fps = val
		delta = 1.0 / fps
		fps_changed.emit(fps)

@export var timemarkers: Dictionary[int, TimeMarkerRes]
@export var comments: Dictionary[int, CommentRes]
@export var root_clip_res: RootClipRes = RootClipRes.new()

var aspect_ratio: Vector2
var delta: float = 1. / fps

func _get_exported_props() -> Dictionary[StringName, ExportInfo]:
	return {
		&"project_name": export(string_args(project_name)),
		&"resolution": export(vec2_args(resolution, true)),
		&"fps": export(int_args(fps, 6, 120))
	}

func _exported_props_controllers_created(main_edit: EditContainer, props_controls: Dictionary[StringName, Control]) -> void:
	var resolution_edit: EditContainer = props_controls.resolution
	var vec2_ctrlr: Vector2Controller = resolution_edit.controller
	vec2_ctrlr.x_edit.min_val = 480; vec2_ctrlr.x_edit.max_val = 7680
	vec2_ctrlr.y_edit.min_val = 240; vec2_ctrlr.y_edit.max_val = 4320

func get_project_name() -> StringName: return project_name
func set_project_name(new_val: StringName) -> void: project_name = new_val

func get_resolution() -> Vector2i: return Vector2i(1024, 720)
func get_fps() -> int: return fps
func get_root_clip_res() -> RootClipRes: return root_clip_res

func set_resolution(new_val: Vector2) -> void: resolution = new_val
func set_fps(new_val: int) -> void: fps = new_val
func set_root_clip_res(new_val: RootClipRes) -> void: root_clip_res = new_val

func get_timemarkers() -> Dictionary[int, TimeMarkerRes]: return timemarkers
func set_timemarkers(new_val: Dictionary[int, TimeMarkerRes]) -> void: timemarkers = new_val

func get_comments() -> Dictionary[int, CommentRes]: return comments
func set_comments(new_val: Dictionary[int, CommentRes]) -> void: comments = new_val

func add_timemarker(frame: int) -> void:
	if timemarkers.has(frame): return
	var new_one:= TimeMarkerRes.new()
	timemarkers[frame] = new_one
	timemarker_added.emit(frame, new_one)

func remove_timemarker(frame: int) -> void:
	if not timemarkers.has(frame): return
	var timemarker: TimeMarkerRes = timemarkers[frame]
	timemarkers.erase(frame)
	timemarker_removed.emit(frame, timemarker)

func move_timemarker(from_frame: int, to_frame: int) -> void:
	if not timemarkers.has(from_frame) or timemarkers.has(to_frame): return
	var timemarker: TimeMarkerRes = timemarkers[from_frame]
	timemarkers.erase(timemarker)
	timemarkers[to_frame] = timemarker
	timemarker_moved.emit(from_frame, to_frame, timemarker)

func add_comment(frame: int) -> void:
	if comments.has(frame): return
	var new_one:= CommentRes.new()
	comments[frame] = new_one
	comment_added.emit(frame, new_one)

func remove_comment(frame: int) -> void:
	if not comments.has(frame): return
	var comment: CommentRes = comments[frame]
	comments.erase(frame)
	comment_removed.emit(frame, comment)

func move_comment(from_frame: int, to_frame: int) -> void:
	if not comments.has(from_frame) or comments.has(to_frame): return
	var comment: CommentRes = comments[from_frame]
	comments.erase(from_frame)
	comments[to_frame] = comment
	comment_moved.emit(from_frame, to_frame, comment)

func save_comments_json(project_dir: String) -> void:
	var data: Array[Dictionary] = []
	for frame: int in comments:
		var c: CommentRes = comments[frame]
		data.append({
			"frame": frame,
			"timecode": TimeServer.frame_to_timecode(frame),
			"name": String(c.custom_name),
			"color": "#%s" % c.custom_color.to_html(),
			"text": c.custom_text
		})
	data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.frame < b.frame)
	var file: FileAccess = FileAccess.open(project_dir.path_join("comments.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_comments_json(project_dir: String) -> void:
	var path: String = project_dir.path_join("comments.json")
	if not FileAccess.file_exists(path): return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file: return
	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK: return
	var data: Variant = json.data
	if not data is Array: return
	comments.clear()
	for entry: Dictionary in data:
		var frame: int = entry.get("frame", 0)
		var c:= CommentRes.new()
		c.custom_name = StringName(entry.get("name", ""))
		c.custom_color = Color.html(entry.get("color", "#ffff64"))
		c.custom_text = entry.get("text", "")
		comments[frame] = c
	comment_added.emit(0, CommentRes.new())

func export_project_json(project_dir: String) -> void:
	var data: Dictionary = {}
	data["project_name"] = String(project_name)
	data["resolution"] = {"x": int(resolution.x), "y": int(resolution.y)}
	data["fps"] = fps
	
	var layers_data: Array = []
	for layer_idx: int in root_clip_res.layers.size():
		var layer: LayerRes = root_clip_res.layers[layer_idx]
		var clips_data: Array = []
		for frame: int in layer.clips:
			var clip: MediaClipRes = layer.clips[frame]
			var clip_data: Dictionary = {
				"type": clip.get_classname(),
				"start_frame": frame,
				"length": clip.length,
				"from": clip.from,
				"id": String(clip.id) if clip.id else ""
			}
			var comps_data: Array = []
			for section: StringName in clip.components:
				for comp: ComponentRes in clip.components[section]:
					var comp_data: Dictionary = {
						"section": String(section),
						"type": comp.get_classname(),
						"enabled": comp.enabled,
						"method_type": int(comp.method_type)
					}
					var anims_data: Array = []
					for usable: UsableRes in comp.animations:
						var anim_dict: Dictionary = comp.animations[usable]
						for prop_key: StringName in anim_dict:
							var anim: AnimationRes = anim_dict[prop_key]
							var keys_data: Array = []
							for profile_idx: int in anim.profiles.size():
								var profile: CurveProfile = anim.profiles[profile_idx]
								for key_frame: int in profile.keys:
									var key: CurveKey = profile.keys[key_frame]
									keys_data.append({
										"frame": key_frame,
										"value": key.value,
										"profile_index": profile_idx
									})
							if keys_data.size() > 0:
								anims_data.append({
									"property": String(prop_key),
									"keyframes": keys_data
								})
					if anims_data.size() > 0:
						comp_data["animations"] = anims_data
					comps_data.append(comp_data)
			if comps_data.size() > 0:
				clip_data["components"] = comps_data
			clips_data.append(clip_data)
		layers_data.append({"layer_index": layer_idx, "clips": clips_data})
	data["layers"] = layers_data
	
	var tms: Array = []
	for frame: int in timemarkers:
		var tm: TimeMarkerRes = timemarkers[frame]
		tms.append({
			"frame": frame,
			"timecode": TimeServer.frame_to_timecode(frame),
			"name": String(tm.custom_name),
			"color": "#%s" % tm.custom_color.to_html(),
			"description": tm.custom_description
		})
	data["timemarkers"] = tms
	
	var cmts: Array = []
	for frame: int in comments:
		var c: CommentRes = comments[frame]
		cmts.append({
			"frame": frame,
			"timecode": TimeServer.frame_to_timecode(frame),
			"name": String(c.custom_name),
			"color": "#%s" % c.custom_color.to_html(),
			"text": c.custom_text
		})
	data["comments"] = cmts
	
	var file: FileAccess = FileAccess.open(project_dir.path_join("project_dump.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()




