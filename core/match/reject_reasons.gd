class_name RejectReasons
extends RefCounted
## The rejection reasons of the loop itself (ARCHITECTURE §3.1, §9.2). Each condition and cost
## names its own (§9.4). A reason depends only on facts the sender is entitled to (§4.1).

## The phase's allowlist does not name this intent from this sender.
const NOT_ACCEPTED := &"not_accepted"
## No phase class and no rule of the held item, the role or the mode handles the intent.
const NOTHING_TO_DO := &"nothing_to_do"
## A negated condition failed.
const NOT_ALLOWED := &"not_allowed"
## Applied, but the outcome it reported was dropped: an earlier one of the same step won.
const OUTCOME_DROPPED := &"outcome_dropped"
## Hello: the name is empty, too long or has a control character (2b).
const BAD_NAME := &"bad_name"
## Hello: another protocol version than the host's; DisconnectPeer follows (2b).
const WRONG_VERSION := &"wrong_version"
## Hello: the roster has the mode's maximum of players; DisconnectPeer follows (2b).
const FULL := &"full"
## SetReady to the flag the player has, or a second LoadAck (2b).
const UNCHANGED := &"unchanged"
## ChangeSettings: a key the mode does not declare, or a value that is not a whole number (2b).
const UNKNOWN_SETTING := &"unknown_setting"
## ChangeSettings: a value outside its SettingSpec's bounds (2b).
const OUT_OF_BOUNDS := &"out_of_bounds"
## ChangeSettings: a map the mode does not list (2b).
const UNKNOWN_MAP := &"unknown_map"
## An argument is missing or has the wrong type, such as SetReady without a bool `ready` (2b).
const BAD_ARGS := &"bad_args"
