class_name SocialInteraction
extends RefCounted
## One interaction, bundled: what it is, who is in it, and what it produced.
##
## This is a short lived working object, not part of the persisted world. It
## exists so that the rules that apply an interaction and the code that records
## it share exactly the same data, instead of passing a dozen parallel
## arguments that could drift apart.
##
## [member left] is always the inhabitant with the lexicographically smaller id:
## a fixed convention that makes the roles of the two participants reproducible.
## For a help interaction [member giver] and [member receiver] say who gave and
## who received, which is not the same thing as the canonical order.

var kind: int = SocialEvent.Kind.GREETING
var outcome: int = SocialEvent.Outcome.NEUTRAL
var left: NpcRecord = null
var right: NpcRecord = null
var giver: NpcRecord = null
var receiver: NpcRecord = null
var initiator: NpcRecord = null
var place: NpcPlace = null
var tick: int = 0
var accepted: bool = true
var willingness: int = -1
var effects: Dictionary = {}
## Short reason written on the relationship, so the UI can say *why* a value
## moved and point at the event that documents it.
var reason: String = ""
var role_left: String = NpcMemory.ROLE_SHARED
var role_right: String = NpcMemory.ROLE_SHARED
var importance_left: int = 0
var importance_right: int = 0


## True when the interaction is complete enough to be recorded.
func is_complete() -> bool:
	return (
		left != null
		and right != null
		and place != null
		and not reason.is_empty()
	)


func other_of(record: NpcRecord) -> NpcRecord:
	if record == left:
		return right
	if record == right:
		return left
	return null


func role_of(record: NpcRecord) -> String:
	return role_left if record == left else role_right


func importance_of(record: NpcRecord) -> int:
	return importance_left if record == left else importance_right
