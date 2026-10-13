class_name DeliveryRoute
extends ContentPart
## One row of Delivery by meaning (#683's ADR DE2, ARCHITECTURE §9.5.24): items of `item` go to
## the place of `drop_off`. No behaviour: DeliveryByMeaning reads its routes, and its check names a
## route with no item or no drop-off. One drop-off may serve several routes; one item kind is in one
## route only.

## The item kind carried (two-handed in the House's data, DD6 (a)).
@export var item: ItemKind
## The place it belongs: a StationKind with no palette whose tag has exactly one marker on each map
## the task type lists (DE3).
@export var drop_off: StationKind
