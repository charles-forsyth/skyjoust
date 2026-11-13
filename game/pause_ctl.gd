extends Node
## Always-processing input listener so ESC/P/M/N/H/Q work even while Main is paused,
## while Main itself stays PROCESS_MODE_PAUSABLE so tweens, timers, and particles freeze cleanly.

signal toggle_pause
signal toggle_music
signal toggle_mute
signal toggle_help
signal quit_to_title


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_M:
				toggle_music.emit()
			KEY_N:
				toggle_mute.emit()
			KEY_H, KEY_F1:
				toggle_help.emit()
			KEY_Q:
				if get_tree().paused:
					quit_to_title.emit()
			KEY_ESCAPE, KEY_P:
				toggle_pause.emit()
