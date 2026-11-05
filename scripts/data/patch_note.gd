class_name PatchNote
extends Resource
## One release in the patch list ("Was is neu?" in the main menu): its version, when it went live and
## what changed, one translation key per line (i18n/strings.csv, PATCH_<version>_<n>).

@export var version: String = ""
## Shown as is ("05.11.2026").
@export var date: String = ""
@export var line_keys: PackedStringArray = PackedStringArray()
