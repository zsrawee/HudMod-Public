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
extends Node

signal render_started()
signal frame_sended(frame: int)
signal render_paused()
signal render_resumed()
signal render_finished_successfully()
signal render_canceled_or_failed(error: String)
signal render_stopped()

@export var is_working: bool
@export var is_paused: bool

var output_path: String
var video_renderer: VideoRenderer
var audio_renderer: AudioRenderer

var latest_image: Image
var _render_frame_count: int = 0

var _ffmpeg_path: String = "res://addons/ffmpeg_codec/ffmpeg.exe"


func start(_output_path: String, _video_renderer: VideoRenderer, _audio_renderer: AudioRenderer) -> void:
	print("RENDER: start() called, output_path = ", _output_path)
	
	is_working = true
	is_paused = false
	_render_frame_count = 0
	
	EditorServer.update_from_performance_settings()
	
	PlaybackServer.stop()
	PlaybackServer.seek(0)
	
	output_path = _output_path
	video_renderer = _video_renderer
	audio_renderer = _audio_renderer
	
	_ffmpeg_cleanup_temp_dir()
	var dir: String = _ffmpeg_get_temp_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		render_canceled_or_failed.emit("Could not create temp render directory.")
		return
	
	print("RENDER: Using ffmpeg fallback for rendering")
	send_frame()
	render_started.emit()


func _ffmpeg_get_temp_dir() -> String:
	return ProjectServer2.project_path.path_join(".render_temp") if ProjectServer2.project_path else "user://.render_temp"


func _ffmpeg_cleanup_temp_dir() -> void:
	var dir: String = _ffmpeg_get_temp_dir()
	if DirAccess.dir_exists_absolute(dir):
		DirAccess.remove_absolute(dir)


func _ffmpeg_save_frame(image: Image, frame_idx: int) -> void:
	var dir: String = _ffmpeg_get_temp_dir()
	var path: String = dir.path_join("frame_%08d.png" % frame_idx)
	var err: Error = image.save_png(path)
	if err != OK:
		print("RENDER: Failed to save PNG frame ", frame_idx, ", error: ", err)


func _ffmpeg_encode_video() -> bool:
	print("RENDER: Encoding video with ffmpeg...")
	var temp_dir: String = _ffmpeg_get_temp_dir()
	var fps: int = ProjectServer2.project_res.fps
	
	var ffmpeg_exe: String = _ffmpeg_path
	if ffmpeg_exe.begins_with("res://"):
		ffmpeg_exe = ProjectSettings.globalize_path(ffmpeg_exe)
	
	if not FileAccess.file_exists(ffmpeg_exe):
		print("RENDER: ffmpeg not found at: ", ffmpeg_exe)
		return false
	
	var ext: String = output_path.get_extension().to_lower()
	
	var video_codec: String
	var pixel_fmt: String
	match ext:
		"webm":
			video_codec = "libvpx"
			pixel_fmt = "yuv420p"
		"avi":
			video_codec = "mpeg4"
			pixel_fmt = "yuv420p"
		"mkv":
			video_codec = "libvpx"
			pixel_fmt = "yuv420p"
		_:
			video_codec = "libvpx"
			pixel_fmt = "yuv420p"
	
	var audio_wav_path: String = temp_dir.path_join("audio.wav")
	var has_audio: bool = _ffmpeg_save_audio(audio_wav_path)
	
	var args: Array[String] = [
		"-y",
		"-framerate", str(fps),
		"-i", temp_dir.path_join("frame_%08d.png"),
		"-c:v", video_codec,
		"-b:v", "6M",
		"-pix_fmt", pixel_fmt,
		"-auto-alt-ref", "0"
	]
	
	if has_audio and FileAccess.file_exists(audio_wav_path):
		args.append("-i")
		args.append(audio_wav_path)
		args.append("-c:a")
		args.append("libopus" if ext == "webm" else "aac")
		args.append("-b:a")
		args.append("192k")
		args.append("-shortest")
	
	args.append(output_path)
	
	print("RENDER: Running: ", ffmpeg_exe, " ", " ".join(args))
	
	var output: Array[String] = []
	var exit_code: int = OS.execute(ffmpeg_exe, PackedStringArray(args), output, true)
	if exit_code != 0:
		print("RENDER: ffmpeg failed (exit ", exit_code, "):")
		for line: String in output:
			print("  ", line)
		return false
	
	print("RENDER: ffmpeg encoding complete")
	return true


func _ffmpeg_save_audio(wav_path: String) -> bool:
	if not audio_renderer:
		return false
	
	var total_samples: PackedByteArray
	var root_clip_res: RootClipRes = ProjectServer2.project_res.root_clip_res
	
	for frame_idx: int in _render_frame_count:
		var all_samples: Array[PackedByteArray] = _extract_root_samples_at(root_clip_res, frame_idx)
		var mixed: PackedByteArray = AudioMixer.mix_buffers(all_samples, 1.)
		total_samples.append_array(mixed)
	
	if total_samples.is_empty():
		return false
	
	var sample_rate: int = ProjectServer2.audio_mix_rate
	var num_channels: int = 2
	var bits_per_sample: int = 32
	var byte_rate: int = sample_rate * num_channels * bits_per_sample / 8
	var data_size: int = total_samples.size()
	
	var wav_file: FileAccess = FileAccess.open(wav_path, FileAccess.WRITE)
	if not wav_file:
		return false
	
	wav_file.store_buffer(&"RIFF".to_utf8_buffer())
	wav_file.store_32(36 + data_size)
	wav_file.store_buffer(&"WAVE".to_utf8_buffer())
	wav_file.store_buffer(&"fmt ".to_utf8_buffer())
	wav_file.store_32(16)
	wav_file.store_16(3)
	wav_file.store_16(num_channels)
	wav_file.store_32(sample_rate)
	wav_file.store_32(byte_rate)
	wav_file.store_16(num_channels * bits_per_sample / 8)
	wav_file.store_16(bits_per_sample)
	wav_file.store_buffer(&"data".to_utf8_buffer())
	wav_file.store_32(data_size)
	wav_file.store_buffer(total_samples)
	wav_file.close()
	
	return true


func send_frame() -> void:
	if not is_working:
		print("RENDER: send_frame - is_working false, force cancel")
		_force_cancel()
		return
	
	if is_paused:
		print("RENDER: send_frame - paused")
		return
	
	if not PlaybackServer.is_render_process_finished:
		await PlaybackServer.render_process_finished
	
	Scene2.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	
	latest_image = Scene2.viewport.get_texture().get_image()
	if latest_image.is_empty():
		print("RENDER: WARNING - captured image is EMPTY at frame ", _render_frame_count)
	
	_ffmpeg_save_frame(latest_image, _render_frame_count)
	
	frame_sended.emit(PlaybackServer.position)
	_render_frame_count += 1
	
	if PlaybackServer.position > ProjectServer2.project_res.root_clip_res.length:
		print("RENDER: All frames done (", _render_frame_count, " frames)")
		_finish()
		return
	
	PlaybackServer.position += 1
	send_frame()


func pause() -> void:
	is_paused = true
	render_paused.emit()

func resume() -> void:
	if is_paused:
		is_paused = false
		send_frame()
		render_resumed.emit()

func pause_resume() -> void:
	if Renderer.is_paused: Renderer.resume()
	else: Renderer.pause()

func cancel() -> void:
	is_working = false
	if is_paused:
		_force_cancel()


func _force_cancel() -> void:
	print("RENDER: _force_cancel() for ", output_path)
	_ffmpeg_cleanup_temp_dir()
	
	if FileAccess.file_exists(output_path):
		DirAccess.remove_absolute(output_path)
		print("RENDER: Deleted output file")
	
	EditorServer.update_from_performance_settings()
	
	render_canceled_or_failed.emit("The rendering was cancelled, output file was deleted.")
	render_stopped.emit()


func _finish() -> void:
	is_working = false
	
	var ffmpeg_ok: bool = _ffmpeg_encode_video()
	_ffmpeg_cleanup_temp_dir()
	
	if not ffmpeg_ok:
		render_canceled_or_failed.emit("FFmpeg encoding failed. Check console for details.")
		render_stopped.emit()
		EditorServer.update_from_performance_settings()
		return
	
	print("RENDER: _finish() - output_path = ", output_path)
	
	var file_exists: bool = FileAccess.file_exists(output_path)
	var file_size: int = -1
	if file_exists:
		var f: FileAccess = FileAccess.open(output_path, FileAccess.READ)
		if f:
			file_size = f.get_length()
			f.close()
	print("RENDER: File exists: ", file_exists, ", size: ", file_size, " bytes")
	
	if file_exists and file_size > 0 and ProjectServer2.project_res and ProjectServer2.import_file_system:
		var result: MediaCache.LOAD_ERR = ProjectServer2.import_file_system.create_file([], output_path)
		print("RENDER: Import result: ", result)
		var paths: Dictionary[StringName, String] = ProjectServer2._get_project_paths(ProjectServer2.project_path)
		ResourceSaver.save(ProjectServer2.import_file_system, paths.import_sys)
		if EditorServer.media_explorer:
			EditorServer.media_explorer.import_media(output_path)
	
	EditorServer.update_from_performance_settings()
	
	render_finished_successfully.emit()
	render_stopped.emit()
	
	OS.shell_show_in_file_manager(output_path)


func _extract_root_samples_at(root_clip_res: RootClipRes, position: int) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray]
	var layers: Array[LayerRes] = root_clip_res.layers
	for layer_idx: int in layers.size():
		var root_layer: RootLayerRes = layers[layer_idx]
		if root_layer.mute:
			continue
		result.append_array(_extract_layer_samples_at(root_layer, position))
	return result

func _extract_clip_samples_at(clip_res: MediaClipRes, position: int) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray]
	var layers: Array[LayerRes] = clip_res.layers
	for layer_idx: int in layers.size():
		var layer: LayerRes = layers[layer_idx]
		result.append_array(_extract_layer_samples_at(layer, position))
	return result

func _extract_layer_samples_at(layer_res: LayerRes, position: int) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray]
	var curr_clip_res: MediaClipRes = layer_res.displayed_clip_res
	if not curr_clip_res:
		return []
	
	if curr_clip_res is VideoClipRes or curr_clip_res is AudioClipRes:
		if curr_clip_res.audio_data_res:
			var samples: PackedByteArray = curr_clip_res.audio_data_res.extract_frame_samples(position - layer_res.displayed_frame + curr_clip_res.from)
			result.append(samples)
	
	result.append_array(_extract_clip_samples_at(curr_clip_res, position))
	
	return result
