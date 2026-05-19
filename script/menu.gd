extends Control

@onready var account_label: Label = $account_label

func _ready() -> void:
	var email := str(get_tree().get_meta("current_user_email", ""))
	if email.is_empty():
		account_label.text = "NOT CONNECTED"
	else:
		account_label.text = "CONNECTED: " + email
