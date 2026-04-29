extends CanvasLayer
class_name DebugPanel

var _log_label: RichTextLabel
var _on_action: Callable

func setup(on_action: Callable) -> void:
	_on_action = on_action
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var panel := PanelContainer.new()
	panel.offset_left = 20
	panel.offset_top = 130
	panel.offset_right = 350
	panel.offset_bottom = 520
	root.add_child(panel)

	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = "调试操作面板"
	vb.add_child(title)

	_add_button(vb, "M 移动", "move")
	_add_button(vb, "C 编制", "compose")
	_add_button(vb, "E 入城", "entry")
	_add_button(vb, "S 补给", "supply")
	_add_button(vb, "F 野战", "battle")
	_add_button(vb, "G 攻城", "siege")
	_add_button(vb, "T 月结算", "monthly")
	_add_button(vb, "Space 结束回合", "end_turn")
	_add_button(vb, "Y 一键演示", "full_demo")
	_add_button(vb, "R 重置", "reset")

	var log_panel := PanelContainer.new()
	log_panel.offset_left = 880
	log_panel.offset_top = 430
	log_panel.offset_right = 1260
	log_panel.offset_bottom = 700
	root.add_child(log_panel)
	_log_label = RichTextLabel.new()
	_log_label.fit_content = true
	_log_label.scroll_following = true
	log_panel.add_child(_log_label)

func set_logs(lines: Array[String]) -> void:
	if _log_label == null:
		return
	_log_label.clear()
	for line in lines:
		_log_label.append_text("- %s\n" % line)

func _add_button(parent: VBoxContainer, text: String, action_id: String) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(func() -> void:
		if _on_action.is_valid():
			_on_action.call(action_id)
	)
	parent.add_child(btn)
