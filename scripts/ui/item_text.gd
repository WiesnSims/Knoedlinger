class_name ItemText
extends RefCounted
## What an item does, written from its data (1.4, DECISIONS 6.7): one line per stat, per named rule
## (ItemData.effect) and per ItemEffect, through translated templates, so the text never drifts from
## the balance. The chest reveal, the Speisekarte, Der Standler, the build view and the Almanach all
## use it. `stacks`: the copies held (values and chances add up as the game adds them).

## Old named rules (PlayerBuild.EFFECTS) whose value reads as a percentage.
const PERCENT_RULES: Array[StringName] = [&"free_chest", &"damage_per_chest", &"kill_blast", &"knodl_slope"]


static func describe(item: ItemData, stacks: int = 1, balance: BalanceData = null) -> PackedStringArray:
	stacks = maxi(stacks, 1)
	var lines := PackedStringArray()
	for key: StringName in item.stats:
		lines.append(Speisekarte.stat_text(key, item.stats[key] * stacks))
	if item.effect != &"":
		var value: float = item.effect_value * stacks
		var shown: String = num(value * 100.0) if PERCENT_RULES.has(item.effect) else num(value)
		if item.effect == &"bell" and balance != null:
			shown = num(balance.bell_seconds / maxf(value, 0.01))
		lines.append(_t("IFX_RULE_" + String(item.effect).to_upper()).replace("{v}", shown))
	for effect: ItemEffect in item.effects:
		lines.append(effect_line(effect, stacks, balance))
	return lines


## One effect as text: "10 % beim Treffer: 1,5 s einfrieren".
static func effect_line(effect: ItemEffect, stacks: int = 1, balance: BalanceData = null) -> String:
	var value: float = ItemProcs.stacked_value(effect, stacks)
	var chance: float = ItemProcs.stacked_chance(effect.chance, stacks)
	var base: float = balance.item_base_damage if balance != null else 20.0
	var trigger: String = ItemEffect.Trigger.keys()[effect.trigger]
	var action: String = ItemEffect.Action.keys()[effect.action]
	var head: String = _t("IFX_WHEN_" + trigger + ("_CHANCE" if chance < 0.999 else ""))
	head = head.replace("{c}", num(chance * 100.0)).replace("{s}", num(effect.seconds)).replace("{cd}", num(effect.cooldown))
	var body: String = _t("IFX_DO_" + action)
	if effect.trigger == ItemEffect.Trigger.LOW_HP and effect.action == ItemEffect.Action.DAMAGE:
		body = _t("IFX_DO_DAMAGE_UPTO")
	var amount: String = num(value)
	match effect.action:
		ItemEffect.Action.BURN, ItemEffect.Action.BLAST, ItemEffect.Action.CHAIN, ItemEffect.Action.DAMAGE, \
				ItemEffect.Action.PROC_CHANCE, ItemEffect.Action.RODEL, ItemEffect.Action.SHIELD:
			amount = num(value * 100.0)
		ItemEffect.Action.HEAL:
			if value < 1.0:
				body = _t("IFX_DO_HEAL_SHARE")
				amount = num(value * 100.0)
		ItemEffect.Action.DAMAGE_PER_KILL:
			amount = num(effect.value * 100.0 * 100.0)
		ItemEffect.Action.DAMAGE_PER_EXECUTE:
			amount = num(effect.value * 100.0)
		ItemEffect.Action.WISP, ItemEffect.Action.SHOCK, ItemEffect.Action.STRING_CUT:
			amount = num(roundf(base * value))
	body = body.replace("{v}", amount).replace("{r}", num(effect.radius)).replace("{s}", num(effect.seconds)) \
			.replace("{n}", num(effect.cap)).replace("{max}", num(effect.cap * 100.0))
	var line: String = body if head == "" else "%s %s" % [head, body]
	if effect.cooldown > 0.0 and effect.trigger != ItemEffect.Trigger.PERIODIC:
		line += " " + _t("IFX_COOLDOWN").replace("{cd}", num(effect.cooldown))
	return line


## A number the German way: 1,5 · 10 · 0,01.
static func num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	var text: String = ("%.2f" % value).rstrip("0").rstrip(".")
	return text.replace(".", ",")


static func _t(key: String) -> String:
	var text: String = TranslationServer.translate(key)
	return "" if text == key and key.begins_with("IFX_WHEN_ALWAYS") else text
