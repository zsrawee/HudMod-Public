extends AudioStreamPlayer2D
class_name CustomAudioStreamPlayer

func set_data(data: PackedByteArray) -> void:
	var sr: int = 44100
	var sample_count: int = data.size() / 4
	var out: PackedByteArray = PackedByteArray()
	out.resize(sample_count * 2)
	for i in sample_count:
		var f: float = data.decode_float(i * 4)
		var s16: int = clampi(int(f * 32767.0), -32768, 32767)
		out.encode_s16(i * 2, s16)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.data = out
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	stream = wav
