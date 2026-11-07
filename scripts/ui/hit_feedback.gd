class_name HitFeedback
extends CanvasLayer
## The local player's hit on screen (1.4.1, C6): a red glow on the screen edge as strong as the hit,
## a bright arc on the side a big hit came from, and a slow pulse while HP is low. Krampus red, as
## everything that means danger (docs/UI-STYLE.md). "Weniger Blitzen" halves it. Under the HUD, gone
## with it (`covered`); hidden while there is nothing to show, after its first frames (so its shader
## is compiled behind the loading screen, not on the first hit).

## Seconds for a full glow and a direction arc to fade.
const FADE: float = 0.45
const ARC_FADE: float = 0.7
## Low HP: glow strength and pulse speed (radians per second).
const LOW_GLOW: float = 0.22
const LOW_SPEED: float = 5.5
## Frames it stays drawn at the start (shader warm-up).
const WARM_FRAMES: int = 30

## True while the HUD steps back (a full-screen panel is open).
var covered: Callable
## Below 30 % HP: the pulse.
var low_hp: bool = false

var _rect: ColorRect
var _material: ShaderMaterial
var _strength: float = 0.0
var _dir: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _warm: int = WARM_FRAMES


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/hit_vignette.gdshader")
	_material.set_shader_parameter(&"tint", UiStyle.color("danger"))
	_rect.material = _material
	add_child(_rect)


## A hit: `amount` 0..1 (share of max HP, at least a visible minimum), `direction` on screen toward the
## attacker (x right, y down; zero = none).
func hit(amount: float, direction: Vector2 = Vector2.ZERO) -> void:
	var soft: float = 0.5 if Settings.get_bool(&"reduce_flashing") else 1.0
	_strength = maxf(_strength, clampf(0.35 + amount * 3.0, 0.35, 1.0) * soft)
	if direction.length_squared() > 0.0001:
		_dir = direction.normalized() * soft


func _process(delta: float) -> void:
	_time += delta
	_strength = move_toward(_strength, 0.0, delta / FADE)
	_dir = _dir.move_toward(Vector2.ZERO, delta / ARC_FADE)
	var soft: float = 0.5 if Settings.get_bool(&"reduce_flashing") else 1.0
	var pulse: float = (LOW_GLOW * (0.6 + 0.4 * sin(_time * LOW_SPEED))) * soft if low_hp else 0.0
	var hidden: bool = covered.is_valid() and covered.call()
	if _warm > 0:
		_warm -= 1
		_rect.visible = true
	else:
		_rect.visible = not hidden and (_strength > 0.01 or _dir.length_squared() > 0.0001 or pulse > 0.0)
	_material.set_shader_parameter(&"strength", _strength)
	_material.set_shader_parameter(&"dir", _dir)
	_material.set_shader_parameter(&"pulse", pulse)
