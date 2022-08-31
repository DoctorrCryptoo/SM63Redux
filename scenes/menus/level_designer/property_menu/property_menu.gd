extends Panel

const TICKBOX = preload("../fields/boolean/tickbox_ld.tscn")
const INPUT_NUMBER = preload("../fields/number/input_number.tscn")
var properties: Dictionary = {}
var target_node: Node = null
onready var list: VBoxContainer = $PropertyList
onready var main = $"/root/Main"


func _on_CloseButton_pressed():
	hide()


func hide():
	visible = false


func show():
	visible = true
	var pos = get_global_mouse_position()
	rect_position = pos


func clear_children():
	for child in list.get_children(): # clear previous properties
		list.remove_child(child)
		child.queue_free()


func set_properties(new_properties, node):
	properties = new_properties
	clear_children()
	
	for key in new_properties:
		var inst = null
		var val = new_properties[key]
		match main.items[node.item_id].properties[key]["type"]:
			"bool":
				inst = TICKBOX.instance()
				inst.get_node("Label").text = key
				inst.pressed = new_properties[key]
			"uint", "sint":
				inst = INPUT_NUMBER.instance()
				inst.get_node("Label").text = key
				inst.pre_text = str(0 if val == null else val)
			"float":
				inst = INPUT_NUMBER.instance()
				inst.get_node("Label").text = key
				inst.pre_text = str(0 if val == null else val)
		if inst != null:
			list.add_child(inst)
	
	target_node = node
	
	call_deferred("resize_box")


func resize_box():
	rect_size = Vector2(list.rect_size.x + 36, list.rect_size.y + 36)


func on_value_changed(label, value):
	target_node.set_property(label, value)
