class_name MapInfo
extends Resource
## A map as the menu lists it (the map itself is data/maps/<id>.tres, loaded only for the run).

@export var id: StringName = &""
## Translation keys of the name and the one-line description.
@export var name_key: String = ""
@export var desc_key: String = ""
## Colour of the little swatch in the map choice.
@export var swatch: Color = Color(0.45, 0.6, 0.35)
