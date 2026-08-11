class_name TtsSpeaker
extends RefCounted

## 表示中のセリフと同じ本文を音声読み上げする薄いラッパ。
## DisplayServer TTS が使えない環境では黙ってスキップ(例外にしない)。
## テストでは spoken に積まれた本文を検証する。

## 読み上げた本文の履歴(検証用。本番でも害はない)。
var spoken: PackedStringArray = PackedStringArray()
## false なら OS TTS を呼ばず履歴だけ残す(ヘッドレステスト向け)。
var use_system_tts: bool = true
## 音声 ID。空なら既定音声。
var voice_id: String = ""
var volume: float = 1.0
var pitch: float = 1.0
var rate: float = 1.0


func speak(text: String) -> void:
	var line := text.strip_edges()
	if line == "":
		return
	spoken.append(line)
	if not use_system_tts:
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	# 連続発話で重ならないよう直前を止める。
	DisplayServer.tts_stop()
	var voice := voice_id
	if voice == "":
		var voices: Array = DisplayServer.tts_get_voices_for_language("ja")
		if voices.is_empty():
			voices = DisplayServer.tts_get_voices()
		if not voices.is_empty():
			# Godot 4: 要素は Dictionary {name, id, language} または id 文字列。
			var first: Variant = voices[0]
			if typeof(first) == TYPE_DICTIONARY:
				voice = str((first as Dictionary).get("id", ""))
			else:
				voice = str(first)
	DisplayServer.tts_speak(line, voice, volume, pitch, rate, 0, false)


func clear_history() -> void:
	spoken.clear()


func last_spoken() -> String:
	if spoken.is_empty():
		return ""
	return spoken[spoken.size() - 1]
