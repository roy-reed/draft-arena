class_name SFX
extends Node
# 程序化音效（自包含）：_ready 时用纯 GDScript 合成 16-bit PCM 单声道 22050Hz 的 AudioStreamWAV，一次生成常驻。
# 与 fx.gd 同一套模式：main 把本节点 add_child 进树后，任何脚本直接调用静态方法（如 SFX.play("shoot")），无需 preload。
# 未挂载（I == null）或 enabled == false 时所有调用静默跳过，headless 与 smoke 自测零副作用。
# 无 BGM、不引用外部素材、不使用麦克风；音色固定（噪声用固定种子 LCG，可复现），仅播放时可做 ±5% 音高抖动。
# 音量只作用于 Master 总线且不落盘，持久化由主流程负责；接线说明见 docs/AUDIO_INTEGRATION.md。

static var I: SFX = null

var enabled := true

const SR := 22050             # 采样率（Hz）
const PEAK := 0.8             # 归一化峰值上限，留 20% 满幅余量
const FADE_IN_S := 0.003      # 每段淡入 3ms，防爆音
const FADE_OUT_S := 0.004     # 每段淡出 4ms
const POOL_SIZE := 10         # 池化播放器数量，全忙时抢占最老
const THROTTLE_MS := 40       # 同名音效连发节流窗口
const DEFAULT_VOLUME := 0.8

static var _volume := DEFAULT_VOLUME  # 逻辑音量静态保存：场景重载后由 _ready 重新应用到总线

var _sounds := {}                     # key -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _started := PackedInt64Array()    # 与 _players 对齐的最近起播时刻（ms），用于抢占最老
var _last_ms := {}                    # key -> 上次起播时刻（ms），节流表


func _ready() -> void:
	I = self
	_build_sounds()
	_build_pool()
	_apply_volume()


func _exit_tree() -> void:
	if I == self:
		I = null


# ---- 静态入口：调用点无需判空 ----


static func play(key: String, pitch_jitter := true) -> void:
	if I == null or not I.enabled:
		return
	I._play_impl(key, pitch_jitter)


static func set_volume(v: float) -> void:
	# 逻辑值始终记录（保证 get_volume 与持久化回读一致）；总线应用需实例已挂载且未禁用
	_volume = clampf(v, 0.0, 1.0)
	if I == null or not I.enabled:
		return
	I._apply_volume()


static func get_volume() -> float:
	return _volume


# ---- 播放与音量 ----


func _play_impl(key: String, jitter: bool) -> void:
	if not _sounds.has(key):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(key, -1000000)) < THROTTLE_MS:
		return
	_last_ms[key] = now
	var p := _acquire()
	if p == null:
		return
	p.stream = _sounds[key]
	p.pitch_scale = randf_range(0.95, 1.05) if jitter else 1.0
	p.play()


func _acquire() -> AudioStreamPlayer:
	for i in _players.size():
		if not _players[i].playing:
			_started[i] = Time.get_ticks_msec()
			return _players[i]
	# 全忙：抢占最早起播的播放器
	var best := 0
	for i in _players.size():
		if _started[i] < _started[best]:
			best = i
	_started[best] = Time.get_ticks_msec()
	return _players[best]


func _apply_volume() -> void:
	# v=0 时 linear_to_db(0) 为 -inf，改走总线静音特判
	AudioServer.set_bus_mute(0, _volume <= 0.0005)
	if _volume > 0.0005:
		AudioServer.set_bus_volume_db(0, linear_to_db(_volume))


func _build_pool() -> void:
	_started.resize(POOL_SIZE)
	_started.fill(0)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _build_sounds() -> void:
	_sounds.clear()
	_sounds["shoot"] = _bake_shoot()
	_sounds["hit"] = _bake_hit()
	_sounds["kill"] = _bake_kill()
	_sounds["hurt"] = _bake_hurt()
	_sounds["pick"] = _bake_pick()
	_sounds["wave"] = _bake_wave()
	_sounds["boss"] = _bake_boss()
	_sounds["win"] = _bake_win()
	_sounds["lose"] = _bake_lose()
	_sounds["click"] = _bake_click()
	_sounds["dash"] = _bake_dash()


# ---- 音色合成（全部确定性：固定扫频/固定种子噪声，无外部素材、无全局随机） ----


func _bake_shoot() -> AudioStreamWAV:
	# 约 90ms：短噪声突发（tau 20ms）+ 880→440Hz 下滑正弦（tau 45ms）
	var b := _buf(0.09)
	_noise(b, 0.0, 0.09, 0.9, 0.02, 1357)
	_tone(b, 0.0, 0.09, 880.0, 440.0, 0.55, 0.045)
	return _bake(b)


func _bake_hit() -> AudioStreamWAV:
	# 约 40ms：1200Hz 短 click（tau 8ms）+ 噪声（tau 6ms）
	var b := _buf(0.04)
	_tone(b, 0.0, 0.04, 1200.0, 1150.0, 0.9, 0.008)
	_noise(b, 0.0, 0.04, 0.7, 0.006, 246)
	return _bake(b)


func _bake_kill() -> AudioStreamWAV:
	# 约 220ms：500→120Hz 下滑 chirp，混 30% 方波增加颗粒感（tau 90ms）
	var b := _buf(0.22)
	_tone(b, 0.0, 0.22, 500.0, 120.0, 1.0, 0.09, 0.0, 0.3)
	return _bake(b)


func _bake_hurt() -> AudioStreamWAV:
	# 约 150ms：210→170Hz 锯齿波，drive 削顶失真（tau 70ms）
	var b := _buf(0.15)
	_saw(b, 0.0, 0.15, 210.0, 170.0, 0.9, 0.07, 2.2)
	return _bake(b)


func _bake_pick() -> AudioStreamWAV:
	# 约 140ms：660Hz 与 990Hz 两连音（各段自带 3ms/4ms 淡入淡出）
	var b := _buf(0.14)
	_tone(b, 0.0, 0.065, 660.0, 660.0, 0.8, 0.05)
	_tone(b, 0.065, 0.075, 990.0, 990.0, 0.8, 0.06)
	return _bake(b)


func _bake_wave() -> AudioStreamWAV:
	# 约 300ms：523/659/784Hz 三连上行琶音，含 25% 二次谐波提亮
	var b := _buf(0.30)
	var fs: Array[float] = [523.25, 659.25, 783.99]
	for i in fs.size():
		_tone(b, i * 0.095, 0.105, fs[i], fs[i], 0.8, 0.12, 0.25)
	return _bake(b)


func _bake_boss() -> AudioStreamWAV:
	# 约 400ms：220Hz + 277Hz 双低音持续，9Hz 颤音调制，尾部 30ms 收尾
	var b := _buf(0.40)
	_tone(b, 0.0, 0.40, 220.0, 220.0, 0.8, 0.0, 0.0, 0.0, 9.0, 0.35)
	_tone(b, 0.0, 0.40, 277.0, 277.0, 0.55, 0.0, 0.0, 0.0, 9.0, 0.35)
	_fade_tail(b, 30.0)
	return _bake(b)


func _bake_win() -> AudioStreamWAV:
	# 约 600ms：五音上行琶音（C5-E5-G5-C6-E6），末音拖长
	var b := _buf(0.60)
	var fs: Array[float] = [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for i in fs.size():
		var st := i * 0.11
		var dur := 0.16 if i == fs.size() - 1 else 0.12
		_tone(b, st, dur, fs[i], fs[i], 0.8, 0.1, 0.2)
	_fade_tail(b, 40.0)
	return _bake(b)


func _bake_lose() -> AudioStreamWAV:
	# 约 700ms：四音下行（G4-E4-C4-G3），末音拖长并长淡出
	var b := _buf(0.70)
	var fs: Array[float] = [392.0, 330.0, 262.0, 196.0]
	for i in 3:
		_tone(b, i * 0.14, 0.13, fs[i], fs[i], 0.8, 0.09, 0.15)
	_tone(b, 0.42, 0.28, fs[3], fs[3], 0.8, 0.18, 0.15)
	_fade_tail(b, 60.0)
	return _bake(b)


func _bake_click() -> AudioStreamWAV:
	# 约 25ms：2000Hz 极短 tick（tau 6ms）
	var b := _buf(0.025)
	_tone(b, 0.0, 0.025, 2000.0, 1800.0, 1.0, 0.006)
	return _bake(b)


func _bake_dash() -> AudioStreamWAV:
	# 约 160ms：带通噪声呼啸——确定性白噪声经中心频率 700→2200Hz 上扫的带通滤波，再乘正弦包络
	var dur := 0.16
	var b := _buf(dur)
	var n := b.size()
	var sd := 8642
	var low := 0.0
	var band := 0.0
	var q := 0.9
	for i in n:
		var t := float(i) / SR
		var fc := lerpf(700.0, 2200.0, t / dur)
		var f := 2.0 * sin(PI * fc / SR)
		sd = (sd * 1103515245 + 12345) & 0x7FFFFFFF
		var n_in := float(sd) * (1.0 / 1073741824.0) - 1.0
		low += f * band
		var high := n_in - low - q * band
		band += f * high
		b[i] = band * sin(PI * t / dur)
	return _bake(b)


# ---- 合成基础件 ----


# 叠加一段扫频音：f0→f1 线性扫频；tau>0 时指数衰减（时间常数秒）；
# harm2 为二次谐波比例，sq 为方波混合比例（0..1），trem_hz/trem_depth 为颤音调制
func _tone(buf: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float, tau: float,
		harm2 := 0.0, sq := 0.0, trem_hz := 0.0, trem_depth := 0.0) -> void:
	var n := int(dur * SR)
	var off := int(start * SR)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := f0 if dur <= 0.0 else lerpf(f0, f1, t / dur)
		ph += TAU * f / SR
		var s := sin(ph)
		if harm2 > 0.0:
			s += harm2 * sin(2.0 * ph)
		if sq > 0.0:
			s = s * (1.0 - sq) + sq * signf(s)
		var e := exp(-t / tau) if tau > 0.0 else 1.0
		if trem_hz > 0.0:
			e *= 1.0 - trem_depth * 0.5 * (1.0 - sin(TAU * trem_hz * t))
		e *= _seg_fade(t, dur)
		var idx := off + i
		if idx < buf.size():
			buf[idx] += amp * e * s


# 叠加一段锯齿波（drive>1 时削顶失真）
func _saw(buf: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float, tau: float, drive := 1.0) -> void:
	var n := int(dur * SR)
	var off := int(start * SR)
	var phz := 0.0
	for i in n:
		var t := float(i) / SR
		var f := f0 if dur <= 0.0 else lerpf(f0, f1, t / dur)
		phz += f / SR
		var s := 2.0 * (phz - floorf(phz)) - 1.0
		s = clampf(s * drive, -0.9, 0.9)
		var e := exp(-t / tau) if tau > 0.0 else 1.0
		e *= _seg_fade(t, dur)
		var idx := off + i
		if idx < buf.size():
			buf[idx] += amp * e * s


# 叠加一段确定性白噪声突发：固定种子 LCG，保证音色可复现
func _noise(buf: PackedFloat32Array, start: float, dur: float, amp: float, tau: float, seed_val: int) -> void:
	var n := int(dur * SR)
	var off := int(start * SR)
	var sd := seed_val & 0x7FFFFFFF
	if sd == 0:
		sd = 1
	for i in n:
		sd = (sd * 1103515245 + 12345) & 0x7FFFFFFF
		var t := float(i) / SR
		var e := exp(-t / tau) if tau > 0.0 else 1.0
		e *= _seg_fade(t, dur)
		var idx := off + i
		if idx < buf.size():
			buf[idx] += amp * e * (float(sd) * (1.0 / 1073741824.0) - 1.0)


func _seg_fade(t: float, dur: float) -> float:
	var fi := minf(t / FADE_IN_S, 1.0)
	var fo := minf((dur - t) / FADE_OUT_S, 1.0)
	return fi * fo


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(int(dur * SR), 1))
	return b


# 结尾再补一段更长的线性淡出（音乐性收尾，避免尾音戛止）
func _fade_tail(buf: PackedFloat32Array, ms: float) -> void:
	var n := mini(int(ms * 0.001 * SR), buf.size())
	var base := buf.size() - n
	for i in n:
		buf[base + i] *= 1.0 - float(i) / float(n)


# 归一化到 PEAK 并转 16-bit 小端 PCM
func _bake(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for x in buf:
		peak = maxf(peak, absf(x))
	var g := PEAK / peak if peak > 0.0001 else 0.0
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(roundf(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	return s
