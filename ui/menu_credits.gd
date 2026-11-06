extends MarginContainer
## The credits in the corner of the title screen: the game's name, who made
## it, and links that open in the browser.


func _ready() -> void:
	var title: String = ProjectSettings.get_setting("application/config/name")
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	%NameVersionLabel.text = title if version == "" else "%s v%s" % [title, version]
	%CreatedByLabel.meta_clicked.connect(_on_meta_clicked)
	%DiscordLabel.meta_clicked.connect(_on_meta_clicked)


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))
