class_name WebPage
extends RefCounted
## The page around the game in the browser (web/shell.html).


## The first screen stands: the loading screen fades out (it would otherwise wait 8 s at most).
static func loaded() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.knoedlReady && window.knoedlReady()", true)
