class_name SpeechResolver
extends RefCounted

## MoveEvent とチーム割当から、誰が何を喋るかを決める(LINES モードの中核)。
## 見た目やノードを持たない。確率と乱択は注入可能な RNG に閉じる。

## 通常の移動で発話する既定確率。設定画面への露出は後続チケット。
const DEFAULT_MOVE_PROBABILITY := 0.3

## 動かし側イベントの優先度(高いほど採用)。重要イベントを漏らさない。
const MOVER_PRIORITY: PackedStringArray = [
	"game_over",
	"check",
	"captured",
	"promoted",
	"moved",
]

var catalog: SpeechCatalog
## 0.0 なら通常移動で発話なし、1.0 なら必ず発話。重要イベントでは無視。
var move_probability: float = DEFAULT_MOVE_PROBABILITY
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(p_catalog: SpeechCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else SpeechCatalog.new()
	rng.randomize()


func plan(event: MoveEvent) -> Array:
	## SpeechUtterance の配列。発話が無ければ空。
	var out: Array = []
	if event == null or catalog == null:
		return out

	var mover_key := _mover_event_key(event)
	if mover_key != "":
		var should := _should_speak_mover(event, mover_key)
		if should:
			var u := _build_utterance(
				event.mover_kind,
				event.mover_side,
				event.to_square(),
				mover_key,
				false
			)
			if u != null:
				out.append(u)

	if event.was_capture() and event.captured != null:
		var victim := _build_utterance(
			event.captured.kind,
			event.captured.side,
			event.captured_square,
			"captured_by",
			true
		)
		if victim != null:
			out.append(victim)

	return out


func is_important(event: MoveEvent) -> bool:
	## 重要イベント: 駒取り・王手・成り・勝敗。
	if event == null:
		return false
	return (
		event.was_capture()
		or event.is_check
		or event.was_promotion()
		or event.is_over
	)


func _should_speak_mover(event: MoveEvent, event_key: String) -> bool:
	if event_key != "moved":
		# 重要イベントは必ず発話を試みる(セリフ未定義なら結果として空になるだけ)。
		return true
	var p := clampf(move_probability, 0.0, 1.0)
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return rng.randf() < p


func _mover_event_key(event: MoveEvent) -> String:
	## 1 着手に複数フラグが立つ場合、最も重いイベントを 1 つ選ぶ。
	var candidates: PackedStringArray = []
	if event.is_over:
		candidates.append("game_over")
	if event.is_check:
		candidates.append("check")
	if event.was_capture():
		candidates.append("captured")
	if event.was_promotion():
		candidates.append("promoted")
	if candidates.is_empty():
		return "moved"
	for key in MOVER_PRIORITY:
		if candidates.has(key):
			return key
	return "moved"


func _build_utterance(
	kind: int,
	side: int,
	square: Vector2i,
	event_key: String,
	is_victim: bool,
) -> SpeechUtterance:
	# 陣営ごとのチーム割当からキャラクターを解決する(同一チームも可)。
	var character := catalog.character_for_kind(kind, side)
	if character == null:
		return null
	var pool := character.lines_for(event_key)
	if pool.is_empty():
		# イベントに対応するセリフが無い場合は黙る(クラッシュしない)。
		return null
	var text := _pick_line(pool)
	if text == "":
		return null
	var u := SpeechUtterance.new()
	u.event_key = event_key
	u.text = text
	u.character_id = character.id
	u.square = square
	u.side = side
	u.kind = kind
	u.is_victim = is_victim
	return u


func _pick_line(pool: PackedStringArray) -> String:
	if pool.is_empty():
		return ""
	if pool.size() == 1:
		return pool[0]
	return pool[rng.randi_range(0, pool.size() - 1)]
