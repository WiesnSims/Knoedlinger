class_name UpgradeCatalog
extends Resource
## Everything a build can hold in a run: weapons (evolutions included, they are only ever offered
## once earned) and stat upgrades, which the Speisekarte offers, and the items (Kirtagsware), which
## only chests give. An entry's index here is its id on the wire, so host and client must load the
## same catalog (the handshake checks the build). Adding content means adding a .tres and listing
## it here, no code.

@export var weapons: Array[WeaponData] = []
@export var passives: Array[PassiveData] = []
@export var items: Array[ItemData] = []
