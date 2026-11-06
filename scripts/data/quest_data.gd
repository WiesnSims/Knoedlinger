class_name QuestData
extends Resource
## One Gemeindeamt quest, an "Auftrag" (GAME-DESIGN.md, "Meta progression"): a goal counted over all
## runs or reached in one, stamped on a form when done, paying Schilling and unlocking something.
## Whatever a quest unlocks is locked until then (Profile.is_unlocked), so no other flag is needed.
##
## Kinds (`kind`, with `filter` and `target`):
##   kills          enemies beaten over all runs (filter: enemy id, or all)
##   cash_ins       Wirtshaus cash-ins over all runs (filter: tier 0..3 as text, or any)
##   level          a level reached in one run (filter: character id, or any)
##   wins           runs won (filter: character id or map id, or any)
##   runs           runs played
##   bosses         a boss beaten, over all runs (filter: boss id)
##   boss_no_throw  a boss beaten in a run without a single Schupfn (filter: boss id)
##   stempel        Stempel collected over all runs
##   knodl          the biggest Knödl of one run, in mass
##   survive        minutes survived in one run
##   overtime       minutes of Nachspielzeit (past Sperrstund') in one run (filter: character id, or any)
##   schilling      Schilling earned over all runs
##   items          different items found
##   grant_win      a run won at this Grant level or higher (target = level index)
##   coop           co-op deeds over all runs (filter: runs, revives, passes, streit, merge_cash_xl,
##                  family_win, knodl_revive_<character id>)
##   daily_streak   Tageskarte runs on days in a row (the best streak)
##   daily_days     days with a Tageskarte run
##   chests         map chests opened over all runs (1.4)
##   chests_run     map chests opened in one run
##   gold           gold earned over all runs
##   standler       items bought from Der Standler over all runs
##   marterl        Marterl prayed at over all runs

@export var id: StringName = &""
@export var title_key: String = ""
@export var desc_key: String = ""
@export var kind: StringName = &"kills"
@export var filter: StringName = &""
@export var target: float = 1.0
@export var reward_schilling: int = 0
## What it unlocks: &"character", &"weapon", &"passive", &"item", &"map", &"knodl" (sort), or &"" = nothing.
@export var unlock_kind: StringName = &""
@export var unlock_id: StringName = &""
