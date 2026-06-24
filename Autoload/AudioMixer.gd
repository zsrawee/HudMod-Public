extends RefCounted
class_name AudioMixer

static func mix_buffers(buffers: Array[PackedByteArray], volume: float) -> PackedByteArray:
	if buffers.is_empty():
		return PackedByteArray()
	var len: int = buffers[0].size()
	var out: PackedByteArray = PackedByteArray()
	out.resize(len)
	var sample_count: int = len / 4
	for i in sample_count:
		var mixed: float = 0.0
		for buf in buffers:
			if i * 4 + 3 < buf.size():
				mixed += buf.decode_float(i * 4)
		mixed *= volume
		mixed = clampf(mixed, -1.0, 1.0)
		out.encode_float(i * 4, mixed)
	return out
