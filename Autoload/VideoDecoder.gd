extends Resource
class_name VideoDecoder

var internal_enhance: bool
var _video_path: String
var _resolution: Vector2i = Vector2i(1080, 1920)
var _fps: float = 30.0
var _duration: float = 30.0
var _bit_depth: int = 8
var _total_frames: int = 900
var _curr_frame: int = 0
var _open: bool = false
var _color_matrix_idx: int = 0

var channel_y: PackedByteArray
var channel_u: PackedByteArray
var channel_v: PackedByteArray

func set_internal_enhance(val: bool) -> void:
	internal_enhance = val

func set_video_path(path: String) -> void:
	_video_path = path

func open() -> bool:
	_open = FileAccess.file_exists(_video_path)
	if _open:
		_resolution = Vector2i(1080, 1920)
		_fps = 30.0
		_duration = 30.0
		_total_frames = int(_fps * _duration)
		_bit_depth = 8
		_color_matrix_idx = 0
		_generate_channel_data()
	return _open

func _generate_channel_data() -> void:
	var y_size: Vector2i = Vector2i(270, 480)
	var uv_size: Vector2i = Vector2i(135, 240)
	var y_count: int = y_size.x * y_size.y
	var uv_count: int = uv_size.x * uv_size.y

	channel_y.resize(y_count)
	channel_u.resize(uv_count)
	channel_v.resize(uv_count)

	for i in y_count:
		channel_y[i] = 128
	for i in uv_count:
		channel_u[i] = 128
		channel_v[i] = 128

func get_total_frames_native() -> int:
	return _total_frames

func get_total_frames_by_timebase() -> int:
	return _total_frames

func get_total_frames_by_dur() -> int:
	return _total_frames

func get_resolution() -> Vector2i:
	return _resolution

func get_duration() -> float:
	return _duration

func get_fps() -> float:
	return _fps

func get_bit_depth() -> int:
	return _bit_depth

func get_width() -> int:
	return _resolution.x

func get_height() -> int:
	return _resolution.y

func get_curr_frame() -> int:
	return _curr_frame

func seek_frame(frame: int) -> bool:
	_curr_frame = frame
	return true

func seek_frame_smart(frame: int) -> bool:
	_curr_frame = frame
	return true

func update_video_data(scale: float) -> void:
	pass

func update_video_channels(scale: float) -> void:
	_generate_channel_data()

func get_channels_dim() -> Dictionary:
	return {"y": Vector2i(270, 480), "uv": Vector2i(135, 240)}

func get_video_data() -> PackedByteArray:
	return PackedByteArray()

func get_color_matrix_idx() -> int:
	return _color_matrix_idx

func set_channel_y(arr: Array) -> void:
	channel_y = PackedByteArray(arr)

func set_channel_u(arr: Array) -> void:
	channel_u = PackedByteArray(arr)

func set_channel_v(arr: Array) -> void:
	channel_v = PackedByteArray(arr)
