class_name SilentVoice
extends VoiceRule
## `Silent` (ARCHITECTURE §6, §9.4): nobody hears anybody. The base mode's Loading (the old scene's
## positions are gone) and End (the game is frozen). A phase with no voice rule is silent too;
## this part says so in the data, where the designer sees it. Its hearing radius is the base
## class's 0 (VoiceRule.hearing_radius_m), so the client plays and sends nothing in it (E41).
