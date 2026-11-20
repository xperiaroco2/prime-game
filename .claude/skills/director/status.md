# Director: the status, the "For you" list and relays

Read by the director ([SKILL.md](SKILL.md)) when he asks "що там?", when he answers an item, and when a lane seems
stuck.

## The status
- Every message ends with "Працює зараз:" and "Чекає на вас:" ([SKILL.md](SKILL.md)); "що там?" gets the same two
  blocks, checked fresh: `list_sessions {"linked": true}`, `tools\run.cmd wave --in-flight`, and each lane's PR on
  GitHub. GitHub's half in one call: `tools\run.cmd inbox` (open PRs' "Needs the engineer" items, the gate's
  exceptions, each thread's latest "For you:").
- A lane with `isRunning` true whose last event (`list_events`, limit 6) is a call with no result and whose
  `lastActivityAt` is over 5 minutes old probably waits on a permission card: name it, its link and the tool, as an
  item under "Чекає на вас:". `tools\run.cmd wave --stalled` (exit 3 means it flagged one) confirms it.

## The "For you" list
- One list, kept by you, of every lane's "For you:" item: taste, go/no-go, money, destructive steps, the gate's
  exceptions. Each item is concrete (what to look at or decide, the options, your recommendation) and carries its
  link; read the whole history behind it first, not only the issue's body. Give it to him first when he looks in.
- Taste waits for him and never blocks a lane (Reborn rule 4).

## Relaying his answers
- An answer with two readings that build different things is read back in one sentence first.
- Then `SendMessage` to the lane that asked: the item, his words quoted and translated into English, the link. The
  lane records it where it belongs ("Answered: <link>"); you never do.
- A session you cannot message: a comment on the issue or PR the item came from, starting "The engineer's answer,
  relayed by the director (<UTC time>):", his words quoted.
