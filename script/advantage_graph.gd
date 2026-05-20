extends Control

var history: Array[float] = []
var current_diff: int = 0

func set_gold_history(values: Array[float], diff: int) -> void:
	history = values.duplicate()
	current_diff = diff
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var center_y := rect.size.y * 0.5
	draw_line(Vector2(0, center_y), Vector2(rect.size.x, center_y), Color(0.8, 0.8, 0.8, 0.45), 3.0)

	if history.size() < 2:
		_draw_gold_text(center_y)
		return

	var max_abs := 1000.0
	for value in history:
		max_abs = maxf(max_abs, abs(value))

	var points := PackedVector2Array()
	for i in range(history.size()):
		var x := float(i) / float(max(1, history.size() - 1)) * rect.size.x
		var normalized: float = clampf(history[i] / max_abs, -1.0, 1.0)
		var y: float = center_y - normalized * rect.size.y * 0.42
		points.append(Vector2(x, y))

	var color := Color(0.1, 0.9, 0.28, 1.0)
	if current_diff < 0:
		color = Color(1.0, 0.18, 0.18, 1.0)
	elif current_diff == 0:
		color = Color(1.0, 0.9, 0.25, 1.0)

	draw_polyline(points, color, 5.0)
	_draw_gold_text(center_y)

func _draw_gold_text(center_y: float) -> void:
	var text := "+%d GOLD" % current_diff
	var color := Color(0.1, 0.9, 0.28, 1.0)
	if current_diff < 0:
		text = "%d GOLD" % current_diff
		color = Color(1.0, 0.18, 0.18, 1.0)
	elif current_diff == 0:
		text = "EVEN GOLD"
		color = Color(1.0, 0.9, 0.25, 1.0)

	var font := get_theme_default_font()
	var font_size := 30
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, center_y - 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
