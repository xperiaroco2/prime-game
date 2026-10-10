class_name TutorialLessons
extends Resource
## The tutorial's lessons in order (docs/design/tutorial.md §1, §3; E64): the root of
## content/tutorial/tutorial.tres. Data only: the client's LessonRunner plays them.

@export var lessons: Array[TutorialLesson] = []


## What makes the lessons unusable; empty when they are fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if lessons.is_empty():
		found.append("no lessons")
	for i in lessons.size():
		var lesson := lessons[i]
		if lesson == null:
			found.append("lesson %d is empty" % (i + 1))
			continue
		for problem: String in lesson.problems():
			found.append("lesson %d: %s" % [i + 1, problem])
	return found
