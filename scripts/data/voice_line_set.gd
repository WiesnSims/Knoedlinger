class_name VoiceLineSet
extends Resource
## Everything one enemy (or the Riesen-Wirt) can say (data/voice_lines/<id>.tres). The order is what
## co-op sends (a line's index), so host and clients of one version agree.

@export var lines: Array[VoiceLineData] = []


## Indices of the lines for `moment`.
func lines_for(moment: VoiceLineData.Moment) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in lines.size():
		if lines[k].moment == moment:
			out.append(k)
	return out
