class_name EngineFactory
extends RefCounted

## プロトコル名から EngineAdapter を生成する。
## 将棋(USI)を後から足すときはここに 1 行足すだけで入口が揃う。


static func create(protocol: String) -> EngineAdapter:
	match protocol:
		"uci":
			return UciEngine.new()
		"usi":
			return UsiEngine.new()
		_:
			return UciEngine.new()


static func supported_protocols() -> PackedStringArray:
	return PackedStringArray(["uci", "usi"])
