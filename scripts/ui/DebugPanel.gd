extends CanvasLayer
class_name DebugPanel

var _log_label: RichTextLabel
var _on_action: Callable
var _selection_label: Label
var _buttons: Dictionary = {}

func setup(on_action: Callable) -> void:
	_on_action = on_action
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
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
	_selection_label = Label.new()
	_selection_label.text = "当前选中: 无"
	vb.add_child(_selection_label)

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
	set_selection_mode("none", "")

	var log_panel := PanelContainer.new()
	log_panel.mouse_filter = Control.MOUSE_FILTER_PASS
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
	_buttons[action_id] = btn

func set_selection_mode(selection_type: String, selected_id: String = "") -> void:
	if _selection_label != null:
		var target_text := "无"
		if selection_type == "city":
			target_text = "城市 %s" % selected_id
		elif selection_type == "unit":
			target_text = "部队 %s" % selected_id
		_selection_label.text = "当前选中: %s" % target_text

	var always_actions := {
		"monthly": true,
		"end_turn": true,
		"full_demo": true,
		"reset": true
	}
	var city_actions := {"compose": true}
	var unit_actions := {
		"move": true,
		"entry": true
	}
	for action_id in _buttons.keys():
		var button = _buttons[action_id]
		var button_visible := always_actions.has(action_id)
		if selection_type == "city" and city_actions.has(action_id):
			button_visible = true
		if selection_type == "unit" and unit_actions.has(action_id):
			button_visible = true
		button.visible = button_visible
