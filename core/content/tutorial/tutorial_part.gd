class_name TutorialPart
extends Resource
## The base of the tutorial's parts (docs/design/tutorial.md §3, E64; ARCHITECTURE §9.3): a closed
## list like the content API's, data only. The client's LessonRunner (client/tutorial/) plays
## them; nothing in core/ reads them. A new part is an engine request.


## The part's name in the design's §3 table (`EventSeen`).
func part_name() -> StringName:
	return &""


## What makes this part unusable; empty when it is fine.
func problems() -> PackedStringArray:
	return PackedStringArray()
