class_name UpgradeCatalog
extends Resource
## Everything the Speisekarte can offer in a run: weapons (evolutions included, they are only ever
## offered once earned) and passives / Knödl upgrades. An item's index here is its id on the wire,
## so host and client must load the same catalog (the handshake checks the build). Adding content
## means adding a .tres and listing it here, no code.

@export var weapons: Array[WeaponData] = []
@export var passives: Array[PassiveData] = []
