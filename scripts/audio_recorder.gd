extends Node

const PetLoggerScript = preload("res://scripts/pet_logger.gd")
@onready var PetLogger = PetLoggerScript.new()

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

var mic_player: AudioStreamPlayer

func _ready() -> void:
	# 1. 检查是否存在名为 Record 的总线
	var idx = AudioServer.get_bus_index("Record")
	if idx == -1:
		# 如果没有，我们就在最末尾创建一个，并把它静音
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Record")
	
	recording_index = idx
	
	# 2. 强制 Record 总线静音 (Mute)，防止回传到 Master 产生回音
	# Mute 总线绝对不会影响 AudioEffectRecord 拿数据，这是 Godot 的底层设计
	AudioServer.set_bus_mute(idx, true)
	AudioServer.set_bus_volume_db(idx, 0.0)
	
	# 3. 建立采集链条
	if mic_player == null:
		mic_player = AudioStreamPlayer.new()
		add_child(mic_player)
	
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Record"
	mic_player.play() # 启动麦克风拉取数据
	
	# 4. 确保效果器就位
	_ensure_record_effect_exists(idx)

func _ensure_record_effect_exists(idx: int) -> void:
	for i in range(AudioServer.get_bus_effect_count(idx)):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectRecord:
			effect = AudioServer.get_bus_effect(idx, i)
			return
	
	# 如果总线上没有效果器，手动加一个
	var new_effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(idx, new_effect)
	effect = new_effect

func start_recording() -> void:
	if recording:
		return
	
	recording = true
	last_recording_position = 0
	
	if recording_index == -1:
		recording_index = AudioServer.get_bus_index("Record")
		if recording_index == -1:
			PetLogger.error("Audio", "Could not find 'Record' bus")
			recording = false
			return
	
	effect.set_recording_active(true)
	PetLogger.info("Audio", "Recording started on bus: %d" % recording_index)

func stop_recording() -> PackedByteArray:
	if not recording:
		return PackedByteArray()
	
	print("[Audio] Stopping recording...")
	recording = false
	effect.set_recording_active(false)
	
	# 等待一小段时间确保数据写入完成
	await get_tree().create_timer(0.1).timeout
	
	# 获取录音数据
	var recording_data = effect.get_recording()
	if recording_data == null:
		print("[Audio] Error: Recording data is null")
		return PackedByteArray()
	
	# 【参考官方Demo优化】显式设置元数据，确保转换前格式明确
	recording_data.mix_rate = SAMPLE_RATE
	recording_data.format = FORMAT
	recording_data.stereo = (CHANNELS == 2)
	
	# 转换为 PCM
	var audio_data = _convert_audio(recording_data)
	print("[Audio] Recording stopped. Raw size: ", recording_data.data.size(), ", Processed size: ", audio_data.size())
	
	return audio_data

func get_latest_chunk() -> PackedByteArray:
	# 获取自上次调用以来的新音频数据
	if not recording or not effect:
		return PackedByteArray()
	
	var recording_data = effect.get_recording()
	if recording_data == null:
		return PackedByteArray()
	
	# 【参考官方Demo优化】同步元数据
	recording_data.mix_rate = SAMPLE_RATE
	recording_data.format = FORMAT
	recording_data.stereo = (CHANNELS == 2)
	
	# 获取当前数据长度
	var current_length = recording_data.data.size()
	if current_length <= last_recording_position:
		return PackedByteArray()
	
	# 提取新数据
	var new_data = recording_data.data.slice(last_recording_position)
	last_recording_position = current_length
	
	# 转换为 PCM
	return _convert_audio_chunk(new_data, recording_data)

func _convert_audio_chunk(data: PackedByteArray, stream: AudioStreamWAV) -> PackedByteArray:
	# 简化版本：如果格式匹配，直接返回
	if stream.mix_rate == SAMPLE_RATE and stream.format == FORMAT and not stream.stereo:
		return data
	
	# 需要转换（这里简化处理）
	# 实际项目中应该实现完整的重采样和格式转换
	return data

func _convert_audio(stream: AudioStreamWAV) -> PackedByteArray:
	# 【原理重构】必须处理声道问题
	var raw_data = stream.data
	if raw_data.is_empty():
		return raw_data
		
	# 【核心修复】针对 2通道 48000Hz 的精准单声道提取
	if stream.stereo:
		var mono_data = PackedByteArray()
		var total_size = raw_data.size()
		mono_data.resize(total_size / 2) # 预分配一半的空间
		
		var write_idx = 0
		var read_idx = 0
		while read_idx < total_size:
			# 每个采样 2 字节（16位）。双声道结构是 [L, L, R, R]
			# 我们只取前两个字节 (左声道)
			mono_data[write_idx] = raw_data[read_idx]
			mono_data[write_idx+1] = raw_data[read_idx+1]
			write_idx += 2
			read_idx += 4 # 跳过右声道的 2 个字节
		return mono_data
	
	return raw_data

func is_recording() -> bool:
	return recording
