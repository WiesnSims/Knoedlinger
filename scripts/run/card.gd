class_name Card
extends RefCounted
## One card on the Speisekarte (or out of a chest): a new item or a level of one, an evolution, or
## a fallback when nothing is left (gold, a heal). `index` points into the UpgradeCatalog.

enum Kind { WEAPON, PASSIVE, EVOLUTION, GOLD, HEAL }
## Gewöhnlich, Fein, Edel, Hofratswürdig (GAME-DESIGN.md); scales what a level gives.
enum Rarity { COMMON, FINE, NOBLE, HOFRAT }

var kind: Kind = Kind.WEAPON
var index: int = 0
var rarity: int = Rarity.COMMON
## The item's level once this card is taken (1 = new).
var level: int = 1


func _init(p_kind: Kind = Kind.WEAPON, p_index: int = 0, p_rarity: int = Rarity.COMMON, p_level: int = 1) -> void:
	kind = p_kind
	index = p_index
	rarity = p_rarity
	level = p_level


## Identifies the item for banishing: the same weapon or passive, whatever its level or rarity.
func item_key() -> int:
	var group: int = Kind.WEAPON if kind == Kind.EVOLUTION else kind
	return group * 256 + index


func same_item(other: Card) -> bool:
	return other != null and item_key() == other.item_key()
