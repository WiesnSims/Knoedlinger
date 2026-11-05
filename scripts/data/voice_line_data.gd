class_name VoiceLineData
extends Resource
## One spoken enemy line (EnemyVoices): when it may be said, the text shown over the head and the
## voice file. The voices are made by tools/audio/voices/voices.py (eSpeak NG, a filter per voice).

## IDLE: now and then, near a player. ATTACK: as its telegraphed attack starts. DEATH: last words.
## CRUSHED: killed by a Knödl. EAT: a Bröselfresser biting a Knödl. ARRIVE, HALF, BEATEN: a boss
## turning up, down to half its health, beaten (the Kontrolleur and the Riesen-Wirt arrive too);
## these are always said.
enum Moment { IDLE, ATTACK, DEATH, CRUSHED, EAT, ARRIVE, HALF, BEATEN }

@export var moment: Moment = Moment.IDLE
## Translation key of the text over the head (i18n/strings.csv).
@export var text_key: String = ""
## Sound id in assets/audio/sfx (voice_<enemy>_<line>).
@export var sound: StringName = &""
## Chance this line is said when its moment comes; below 0 = the moment's chance in balance.tres.
@export var chance: float = -1.0
