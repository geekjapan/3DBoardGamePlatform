class_name SpeechDirector
extends Node

## 対局セッションの MoveEvent を監視し、LINES モードの発話を吹き出しで出す。
## GameController を書き換えず、last_move_event の差分で着手を検出する。

var session: GameSession
var board_view: BoardView
var resolver: SpeechResolver
var square_size: float = BoardLayout.DEFAULT_SQUARE_SIZE

## 取られた駒など、親にできない吹き出しの置き場。
var _world_bubbles: Node3D
var _last_event: MoveEvent = null


func setup(
	p_session: GameSession,
	p_board_view: BoardView,
	p_resolver: SpeechResolver,
	p_square_size: float = BoardLayout.DEFAULT_SQUARE_SIZE,
) -> void:
	session = p_session
	board_view = p_board_view
	resolver = p_resolver
	square_size = p_square_size
	if _world_bubbles == null:
		_world_bubbles = Node3D.new()
		_world_bubbles.name = "WorldSpeechBubbles"
		add_child(_world_bubbles)
	set_process(true)


func _process(_delta: float) -> void:
	if session == null or resolver == null:
		return
	var event := session.last_move_event()
	if event == null or event == _last_event:
		return
	_last_event = event
	present_event(event)


func present_event(event: MoveEvent) -> Array:
	## テストからも呼べる入口。表示した SpeechBubble の配列を返す。
	var shown: Array = []
	if resolver == null:
		return shown
	var plan: Array = resolver.plan(event)
	for item in plan:
		var utterance := item as SpeechUtterance
		if utterance == null or utterance.text == "":
			continue
		var bubble := _spawn_bubble(utterance)
		if bubble != null:
			shown.append(bubble)
	return shown


func _spawn_bubble(utterance: SpeechUtterance) -> SpeechBubble:
	var bubble := SpeechBubble.new(utterance.text)
	var piece_node: PieceNode = null
	if board_view != null and not utterance.is_victim:
		piece_node = board_view.piece_node_at(utterance.square)

	if piece_node != null and is_instance_valid(piece_node):
		# 駒の子に付ければ移動・カメラ回転でも追従する。
		piece_node.add_child(bubble)
		bubble.position = Vector3.ZERO
		return bubble

	# 取られた駒やノード未同期時はマスのワールド座標に置く。
	if _world_bubbles == null:
		_world_bubbles = Node3D.new()
		_world_bubbles.name = "WorldSpeechBubbles"
		add_child(_world_bubbles)
	var world := BoardLayout.square_to_world(utterance.square, square_size)
	_world_bubbles.add_child(bubble)
	# ツリー外では global_position が使えないのでローカルで置く。
	if _world_bubbles.is_inside_tree():
		bubble.global_position = world
	else:
		bubble.position = world
	return bubble
