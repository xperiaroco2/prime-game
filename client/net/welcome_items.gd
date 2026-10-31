class_name WelcomeItems
extends RefCounted
## The hall's items as a Welcome lists them (ARCHITECTURE §4.2, #1404), folded into a ClientModel
## in place of any it knew: each row's kind and position; a carried one's holder and place, belted
## unless it is in the hand (whose place is then the holder's selected one); a locked one rests
## where it lies and no PickUp takes it (`locked`, on no station: a row carries no station facts).
## A row with a rest state this build does not know, a place out of 0..2, or a carried row with no
## holder (a lying one with a holder) is skipped. A carrier with an empty hand keeps the first
## place selected until its next Swapped or pickup: only the own player's is read, and a joiner
## carries nothing.

## A row's `where`, the wire's values: a copy of core/'s item rest states in the same order (a
## test pins it; client/net names no core/ state class). A flying item is never in a Welcome.
enum Rest { GROUND, HAND, LOCKED, BELT }


static func fold(model: ClientModel, rows: Array) -> void:
	model.items.clear()
	model.selected_places.clear()
	for row: Dictionary in rows:
		var where: int = row["where"]
		var place: int = row["place"]
		var holder: int = row["holder"]
		var carried := where == Rest.HAND or where == Rest.BELT
		if where < Rest.GROUND or where > Rest.BELT or place < 0 or place >= ClientModel.PLACES:
			continue
		if carried == (holder == ClientModel.NO_HOLDER):
			continue
		var item := ClientModel.Item.new()
		item.kind = row["kind"]
		item.position = row["position"]
		if carried:
			item.holder = holder
			item.carry_place = place
			item.belted = where == Rest.BELT
			if where == Rest.HAND:
				model.selected_places[holder] = place
		item.locked = where == Rest.LOCKED
		model.items[row["item"] as int] = item
