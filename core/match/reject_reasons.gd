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
