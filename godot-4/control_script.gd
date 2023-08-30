extends Button

func _notification(what):
	if (what==NOTIFICATION_FOCUS_ENTER):
		print(text)

# Called when the node enters the scene tree for the first time.
#func _ready():
#	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
