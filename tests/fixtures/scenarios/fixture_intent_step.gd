class_name FixtureIntentStep
extends ScenarioStep
## A test step that sends one intent and is done when the event it causes reaches the bot (#1509):
## the runner (ScenarioPlay._fixture_intent) sends `intent_kind()` with `intent_args()` once, then
## waits for `done_event()` matching `done_fields(peer)`, or for the Rejected `expect_rejected`
## names. Test steps like these live beside their fixture scenarios in tests/fixtures/scenarios/,
## not in core/content/scenario/ with the closed list (#1510).


func sends_intent() -> bool:
	return true


## The intent the step sends (Intents).
func intent_kind() -> StringName:
	return &""


## The intent's arguments.
func intent_args() -> Dictionary:
	return {}


## The event that shows the intent applied.
func done_event() -> StringName:
	return &""


## The fields that event holds for the bot of peer id `peer`.
func done_fields(_peer: int) -> Dictionary:
	return {}
