extends Node

## audio_recorder.gd
## 音频录制模块：负责录制麦克风音频并转换为PCM格式

signal audio_chunk_ready(audio_data: PackedByteArray)

var recording: bool = false
var effect: AudioEffectRecord
var recording_index: int = 0
var last_recording_position: int = 0

const SAMPLE_RATE: int = 48000
const CHANNELS: int = 1  # 单声道
const FORMAT: int = AudioStreamWAV.FORMAT_16_BITS

func _ready() -> void:
	# 获取或创建AudioEffectRecord
	var idx = AudioServer.get_bus_index("Record")
	if idx == -1:
		# 创建录音总线
		AudioServer.add_bus(1)
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Record")
	
	recording_index = idx
	
	# 检查是否已有录音效果
	var has_effect = false
	for i in range(AudioServer.get_bus_effect_count(idx)):
		var bus_effect = AudioServer.get_bus_effect(idx, i)
		if bus_effect is AudioEffectRecord:
			effect = bus_effect
			has_effect = true
			break
	
	if not has_effect:
		effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(idx, effect)

func start_recording() -> void:
	if recording:
		return
	
	recording = true
	last_recording_position = 0
	
	if recording_index == -1:
		recording_index = AudioServer.get_bus_index("Record")
		if recording_index == -1:
			print("无法找到录音总线")
			recording = false
			return
	
	effect.set_recording_active(true)
	print("开始录音...")

func stop_recording() -> PackedByteArray:
	if not recording:
		return PackedByteArray()
	
	recording = false
	effect.set_recording_active(false)
	
	# 等待一小段时间确保数据写入完成
	await get_tree().create_timer(0.1).timeout
	
	# 获取录音数据
	var recording_data = effect.get_recording()
	if recording_data == null:
		print("录音数据为空")
		return PackedByteArray()
	
	# 转换为16kHz单声道PCM
	var audio_data = _convert_audio(recording_data)
	print("录音结束，数据大小: ", audio_data.size(), " 字节")
	
	return audio_data

func get_latest_chunk() -> PackedByteArray:
	# 获取自上次调用以来的新音频数据
	if not recording or not effect:
		return PackedByteArray()
	
	var recording_data = effect.get_recording()
	if recording_data == null:
		return PackedByteArray()
	
	# 获取当前数据长度
	var current_length = recording_data.data.size()
	if current_length <= last_recording_position:
		return PackedByteArray()
	
	# 提取新数据
	var new_data = recording_data.data.slice(last_recording_position)
	last_recording_position = current_length
	
	# 转换为16kHz单声道PCM
	return _convert_audio_chunk(new_data, recording_data)

func _convert_audio_chunk(data: PackedByteArray, stream: AudioStreamWAV) -> PackedByteArray:
	# 简化版本：如果格式匹配，直接返回
	if stream.mix_rate == SAMPLE_RATE and stream.format == FORMAT and not stream.stereo:
		return data
	
	# 需要转换（这里简化处理）
	# 实际项目中应该实现完整的重采样和格式转换
	return data

func _convert_audio(stream: AudioStreamWAV) -> PackedByteArray:
	# 获取原始数据
	var data = stream.data
	
	# 如果已经是16kHz单声道16位，直接返回
	if stream.mix_rate == SAMPLE_RATE and stream.format == FORMAT and not stream.stereo:
		return data
	
	# 需要转换（简化版本）
	# 如果是立体声，只取左声道
	var samples = PackedInt32Array()
	var sample_count = data.size() / 2  # 16位 = 2字节
	
	if stream.stereo:
		# 立体声，只取左声道
		for i in range(0, sample_count, 2):
			var byte_idx = i * 2
			if byte_idx + 1 < data.size():
				var sample = data.decode_u16(byte_idx)
				samples.append(sample)
	else:
		# 单声道，直接使用
		for i in range(sample_count):
			var byte_idx = i * 2
			if byte_idx + 1 < data.size():
				var sample = data.decode_u16(byte_idx)
				samples.append(sample)
	
	# 转换回PackedByteArray
	var result = PackedByteArray()
	for sample in samples:
		result.append_array(PackedByteArray([sample & 0xFF, (sample >> 8) & 0xFF]))
	
	return result

func is_recording() -> bool:
	return recording
