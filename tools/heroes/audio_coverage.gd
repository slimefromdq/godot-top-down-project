extends RefCounted

# Audio checks for a hero test. Create it right after the hero spawns: it
# records every cue the hero fires while the test plays its kit, then
# checks() reports on the definition's AudioProfile:
#
#   - the hero has one, and no entry is an empty placeholder (no streams);
#   - a gun primary's <id>_fire has a sound with a Min Interval (rapid fire);
#   - the ultimate makes a sound (some <ultimate id>... entry fires);
#   - every entry is a cue the hero really fired: a misspelt or dead cue
#     name is never heard in game.
#
#   var audio = AUDIO_COVERAGE.new(hero)
#   ...play the kit...
#   for c in audio.checks(): _check(c[0], c[1], c[2])
#
# Everything is read at creation, so a test may free the hero before checks().

# Fired by the health and ability systems whether a test provokes them or not.
const ALWAYS_VALID: Array[StringName] = [&"spawn", &"hurt", &"heal", &"death", &"ability_failed"]

var profile: AudioProfile
var fire_cue: StringName = &""    # empty for a melee primary
var ultimate_id: String = ""
var fired: Dictionary[StringName, bool] = {}


func _init(hero: Hero) -> void:
	profile = hero.definition.audio_profile
	# Guns only: a melee primary's swings sound through the FeelProfile.
	var primary := hero.get_ability(&"primary")
	if primary is RangedAttackAbility:
		fire_cue = StringName(str(primary.ability_id) + "_fire")
	ultimate_id = str(hero.get_ability(&"ultimate").ability_id)
	hero.cue_triggered.connect(func(cue: StringName, _context: Dictionary): fired[cue] = true)


# [label, ok, detail] per check.
func checks() -> Array:
	if profile == null:
		return [["has an AudioProfile", false, "definition.audio_profile is empty"]]
	var result := [["has an AudioProfile", true, ""]]

	var empty := PackedStringArray()
	for cue in profile.cues:
		var sound := profile.cues[cue]
		if sound == null or sound.streams.is_empty() or sound.streams.has(null):
			empty.append(str(cue))
	result.append(["every sound has a stream", empty.is_empty(), ", ".join(empty)])

	if fire_cue != &"":
		var fire_sound: SoundCue = profile.cues.get(fire_cue)
		var ok := fire_sound != null and fire_sound.min_interval > 0.0
		result.append(["primary fire (%s) has a rate-limited sound" % fire_cue, ok,
			"" if ok else ("missing" if fire_sound == null else "min_interval is 0")])

	var ultimate_heard := false
	for cue in profile.cues:
		if str(cue).begins_with(ultimate_id) and fired.has(cue):
			ultimate_heard = true
	result.append(["the ultimate (%s) makes a sound" % ultimate_id, ultimate_heard, ""])

	var dead := PackedStringArray()
	for cue in profile.cues:
		if not fired.has(cue) and not ALWAYS_VALID.has(cue):
			dead.append(str(cue))
	result.append(["every audio cue fires in play", dead.is_empty(),
		"" if dead.is_empty() else "never fired: " + ", ".join(dead)])
	return result
