extends RefCounted

# Third-person camera preference, shared by the Settings screen and the
# player. Stored in its own small file so it does not touch the save data.
#   close:   tight over the right shoulder, low and near (default)
#   classic: centred behind the hero, further back

const PATH := "user://camera_settings.cfg"
const CLOSE := "close"
const CLASSIC := "classic"
const MODES := [CLOSE, CLASSIC]

static var _mode := ""


static func get_mode() -> String:
	if _mode.is_empty():
		_mode = CLOSE
		var config := ConfigFile.new()
		if config.load(PATH) == OK:
			var stored := String(config.get_value("camera", "mode", CLOSE))
			if stored in MODES:
				_mode = stored
	return _mode


static func set_mode(mode: String) -> void:
	if not mode in MODES:
		return
	_mode = mode
	var config := ConfigFile.new()
	config.set_value("camera", "mode", mode)
	config.save(PATH)


static func is_close() -> bool:
	return get_mode() == CLOSE
