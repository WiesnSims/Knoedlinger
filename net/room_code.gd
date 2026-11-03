class_name RoomCode
extends RefCounted
## Four-letter room codes like KNDL (docs/DECISIONS.md: letters, not Berghittn's digits). I and O are
## left out because they are easy to mix up with 1 and 0. Used by the relay lobby in M6.

const ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ"
const LENGTH: int = 4


static func generate(rng: RandomNumberGenerator) -> String:
	var code: String = ""
	for i: int in LENGTH:
		code += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
	return code


## Upper-cases and trims what a player typed.
static func normalize(text: String) -> String:
	return text.strip_edges().to_upper()


static func is_valid(code: String) -> bool:
	if code.length() != LENGTH:
		return false
	for character: String in code:
		if not ALPHABET.contains(character):
			return false
	return true
