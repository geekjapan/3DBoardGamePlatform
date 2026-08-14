class_name LlmSpeechClient
extends RefCounted

## キャラクター性格と盤上状況からセリフを生成する。
## API キーは環境変数からのみ読む(ソース・設定ファイルには保存しない)。
## キー未設定 / 時間切れ / 失敗はすべて定型セリフへフォールバックする。

## 優先順。先頭から最初に非空の値を使う。
const ENV_KEY_NAMES: PackedStringArray = [
	"BOARDGAME_LLM_API_KEY",
	"OPENAI_API_KEY",
]

const DEFAULT_TIMEOUT_MS := SpeechSettings.DEFAULT_LLM_TIMEOUT_MS
const DEFAULT_ENDPOINT := "https://api.openai.com/v1/chat/completions"
const DEFAULT_MODEL := "gpt-4o-mini"

const REASON_OK := "ok"
const REASON_NO_KEY := "no_key"
const REASON_TIMEOUT := "timeout"
const REASON_ERROR := "error"

var timeout_ms: int = DEFAULT_TIMEOUT_MS
var endpoint: String = DEFAULT_ENDPOINT
var model: String = DEFAULT_MODEL

## テスト差し替え: () -> String。未設定なら OS.get_environment を使う。
var env_reader: Callable = Callable()
## テスト差し替え: (prompt: String, timeout_ms: int) -> Dictionary
## 返却: { "ok": bool, "text": String, "timed_out": bool, "error": String }
var transport: Callable = Callable()


func api_key() -> String:
	## 環境変数からのみ。設定ファイルや引数からは読まない。
	if env_reader.is_valid():
		return str(env_reader.call()).strip_edges()
	for name in ENV_KEY_NAMES:
		var value := OS.get_environment(name).strip_edges()
		if value != "":
			return value
	return ""


func has_api_key() -> bool:
	return api_key() != ""


func generate_or_fallback(context: Dictionary) -> Dictionary:
	## context 必須キー:
	##   fallback_text, personality, event_key
	## 任意: character_name, display_name, board_hint, side_label, kind_label
	## 返却: { text, used_fallback, reason }
	var fallback := str(context.get("fallback_text", "")).strip_edges()
	if not has_api_key():
		return _fallback(fallback, REASON_NO_KEY)

	var prompt := build_prompt(context)
	var result: Dictionary
	if transport.is_valid():
		var raw: Variant = transport.call(prompt, timeout_ms)
		if typeof(raw) != TYPE_DICTIONARY:
			return _fallback(fallback, REASON_ERROR)
		result = raw as Dictionary
	else:
		result = _http_generate(prompt, timeout_ms)

	if bool(result.get("timed_out", false)):
		return _fallback(fallback, REASON_TIMEOUT)
	if not bool(result.get("ok", false)):
		return _fallback(fallback, REASON_ERROR)
	var text := str(result.get("text", "")).strip_edges()
	# 改行や引用符を軽く整える。
	text = text.replace("\n", " ").strip_edges()
	if text.begins_with("「") and text.ends_with("」") and text.length() >= 2:
		text = text.substr(1, text.length() - 2).strip_edges()
	if text.begins_with("\"") and text.ends_with("\"") and text.length() >= 2:
		text = text.substr(1, text.length() - 2).strip_edges()
	if text == "":
		return _fallback(fallback, REASON_ERROR)
	return {
		"text": text,
		"used_fallback": false,
		"reason": REASON_OK,
	}


func build_prompt(context: Dictionary) -> String:
	var name := str(context.get("display_name", context.get("character_name", "駒")))
	var game_id := str(context.get("game_id", SpeechCatalog.GAME_CHESS))
	var game_role := "将棋の駒キャラクター" if game_id == SpeechCatalog.GAME_SHOGI else "チェスの駒キャラクター"
	var personality := str(context.get("personality", ""))
	var event_key := str(context.get("event_key", "moved"))
	var board_hint := str(context.get("board_hint", ""))
	var side_label := str(context.get("side_label", ""))
	var kind_label := str(context.get("kind_label", ""))
	var event_ja := _event_key_ja(event_key)
	var lines: PackedStringArray = [
		"ゲーム種別: %s" % game_id,
		"あなたは%sとして短い日本語のセリフを1つだけ返す。" % game_role,
		"説明や前置きは禁止。セリフ本文のみ。40文字以内。",
		"キャラクター名: %s" % name,
		"性格: %s" % personality,
		"陣営: %s" % side_label,
		"駒種: %s" % kind_label,
		"状況: %s (%s)" % [event_ja, event_key],
	]
	if board_hint != "":
		lines.append("盤面ヒント: %s" % board_hint)
	return "\n".join(lines)


func _fallback(text: String, reason: String) -> Dictionary:
	return {
		"text": text,
		"used_fallback": true,
		"reason": reason,
	}


func _event_key_ja(event_key: String) -> String:
	match event_key:
		"moved":
			return "移動した"
		"captured":
			return "相手の駒を取った"
		"captured_by":
			return "取られた"
		"check":
			return "王手をかけた"
		"promoted":
			return "成った"
		"game_over":
			return "対局が終わった"
		_:
			return event_key


func _http_generate(prompt: String, p_timeout_ms: int) -> Dictionary:
	## OpenAI 互換 Chat Completions。失敗・時間切れは例外にせず Dictionary で返す。
	var key := api_key()
	if key == "":
		return {"ok": false, "text": "", "timed_out": false, "error": "no_key"}

	var body := {
		"model": model,
		"messages": [
			{
				"role": "system",
				"content": "短い日本語のセリフを1つだけ返す。説明禁止。",
			},
			{"role": "user", "content": prompt},
		],
		"max_tokens": 80,
		"temperature": 0.9,
	}
	var payload := JSON.stringify(body)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % key,
	])

	var http := HTTPClient.new()
	var host := ""
	var path := ""
	var port := 443
	var use_tls := true
	var parsed := _parse_url(endpoint)
	host = str(parsed.get("host", ""))
	path = str(parsed.get("path", "/"))
	port = int(parsed.get("port", 443))
	use_tls = bool(parsed.get("tls", true))
	if host == "":
		return {"ok": false, "text": "", "timed_out": false, "error": "bad_endpoint"}

	var err := http.connect_to_host(host, port, TLSOptions.client() if use_tls else null)
	if err != OK:
		return {"ok": false, "text": "", "timed_out": false, "error": "connect_failed"}

	var deadline := Time.get_ticks_msec() + maxi(p_timeout_ms, 1)
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		if Time.get_ticks_msec() > deadline:
			http.close()
			return {"ok": false, "text": "", "timed_out": true, "error": "timeout"}
		http.poll()
		OS.delay_msec(10)

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		http.close()
		return {"ok": false, "text": "", "timed_out": false, "error": "not_connected"}

	err = http.request(HTTPClient.METHOD_POST, path, headers, payload)
	if err != OK:
		http.close()
		return {"ok": false, "text": "", "timed_out": false, "error": "request_failed"}

	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() > deadline:
			http.close()
			return {"ok": false, "text": "", "timed_out": true, "error": "timeout"}
		http.poll()
		OS.delay_msec(10)

	if not http.has_response():
		http.close()
		return {"ok": false, "text": "", "timed_out": false, "error": "no_response"}

	var code := http.get_response_code()
	var chunks := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec() > deadline:
			http.close()
			return {"ok": false, "text": "", "timed_out": true, "error": "timeout"}
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			chunks.append_array(chunk)
		else:
			OS.delay_msec(10)

	http.close()
	var text_body := chunks.get_string_from_utf8()
	if code < 200 or code >= 300:
		return {
			"ok": false,
			"text": "",
			"timed_out": false,
			"error": "http_%d" % code,
		}
	var parsed_json: Variant = JSON.parse_string(text_body)
	if typeof(parsed_json) != TYPE_DICTIONARY:
		return {"ok": false, "text": "", "timed_out": false, "error": "bad_json"}
	var choices: Variant = (parsed_json as Dictionary).get("choices", [])
	if not (choices is Array) or (choices as Array).is_empty():
		return {"ok": false, "text": "", "timed_out": false, "error": "no_choices"}
	var first: Variant = (choices as Array)[0]
	if typeof(first) != TYPE_DICTIONARY:
		return {"ok": false, "text": "", "timed_out": false, "error": "bad_choice"}
	var message: Variant = (first as Dictionary).get("message", {})
	if typeof(message) != TYPE_DICTIONARY:
		return {"ok": false, "text": "", "timed_out": false, "error": "bad_message"}
	var content := str((message as Dictionary).get("content", "")).strip_edges()
	if content == "":
		return {"ok": false, "text": "", "timed_out": false, "error": "empty_content"}
	return {"ok": true, "text": content, "timed_out": false, "error": ""}


func _parse_url(url: String) -> Dictionary:
	var u := url.strip_edges()
	var tls := true
	if u.begins_with("https://"):
		u = u.substr(8)
		tls = true
	elif u.begins_with("http://"):
		u = u.substr(7)
		tls = false
	var slash := u.find("/")
	var hostport := u if slash < 0 else u.substr(0, slash)
	var path := "/" if slash < 0 else u.substr(slash)
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon > 0:
		host = hostport.substr(0, colon)
		port = int(hostport.substr(colon + 1))
	return {"host": host, "path": path, "port": port, "tls": tls}
