# Director: the digest, the inbox body and relays

Read by the director ([SKILL.md](SKILL.md)) for each digest he asks for ("що там?", "що нового?") and each answer
it relays.

## Each digest
1. **The inbox issue:** `gh issue list --state open --search "\"Engineer's inbox\" in:title" --json number,title`,
   the one titled exactly "Engineer's inbox"; read its body (your last digest). None: tell the engineer the two
   commands of AGENT_WORKFLOW §7.2 ("Set up") in the chat, one PowerShell block each, and digest into the chat only.
2. **GitHub:** `tools\run.cmd inbox` (all four repos in one call; `--since` 72 hours by default): open PRs' unanswered
   "Needs the engineer" items, the gate's exceptions (merges only he makes) and each thread's latest "For you:" block
   by his account, with how many comments came after it. An "Unavailable:" line goes into the footer.
3. **Sessions:** `list_sessions` (limit 30). For each session other than yours that is running or active since your
   last digest, in `D:\prime-game`, `D:\prime-game-ui`, `D:\prime-game-art` or `D:\prime-game-design` (#1124):
   `list_events` with a small limit (6; page back with `before_uuid` only when its last "For you:" or "Для вас:" block
   is cut). When many changed,
   `search_session_transcripts` for "Для вас:" and "For you:" first. Take each session's last block and the day's
   news in one line (merged, finished, stopped), not its whole story.
4. **Approvals (a heuristic; §7.2's probe):** a session with `isRunning` true whose last event is a call with no
   result (`[assistant] (called Bash)`) and whose `lastActivityAt` is over 5 minutes old probably waits on a
   permission card (agents block no call over 180 s). Name the session, its link and the tool; never claim more.
   Then `tools\run.cmd wave --stalled` (read-only; exit 3 means it flagged a session, not a failure): it names each
   other session whose finished runs or queued notifications wait behind a card or a stop. List each `stalled:` line
   in the inbox as one approval, quoted: the checkout, what it waits on, since when, and what the engineer clicks (the
   card to answer, or the session to open). Nothing flagged: no line.
   Then `tools\run.cmd wave --in-flight` (read-only, exit 0 either way, a few seconds; AGENT_WORKFLOW §11.11): one
   `in flight:` line per other session on this machine with background work of its own still running, across the four
   checkouts and their worktrees: a workflow run (its wf id), a background agent or a background command, each with
   its start. Match a line to `list_sessions` by its `desktop local_...` id (that session's `sessionId`), else by its
   title, else by its cwd (the transcript's may be a worktree under the session's cwd) and last record
   (`lastActivityAt`); the transcript id is no `local_...` id. Sort each session
   into one group: **waits for you** (a real "For you:" or "Для вас:" item, or GitHub has one), **running**
   (`isRunning` true, or an `in flight:` line: "waits on its own workflow <wf id>, started <time>", or its agent or
   command), else **silent, reason unseen** ("nothing in flight"). A run or agent whose journal or transcript has not
   moved for an hour may have died: say when it last wrote.
5. **Merge into one list.** One item per thing: a PR named by a session, its wave comment and `inbox` is one item,
   with the best link. Drop what a later comment or event answered (the engineer's words, an "Answered:" link, a
   merge). Order: approvals waiting, merges only he makes, decisions, commands, then things to look at. A decision
   item is a taste question only; a technical one is relayed back with his standing word ("take your recommended
   option", SKILL.md's Limits) and goes into the shift report's "taken for you", not the inbox.
6. **Rewrite the inbox body** in the format below (a file in your scratchpad, then `gh issue edit <n> --body-file`),
   only when something changed; the header's time either way is not worth an edit.
7. **The chat line:** one or two short lines in his language: what came and went since the last digest, with the
   inbox link (`+2: merge PR #490, a decision on PR #474; −1: #434 answered. <link>`), or "нічого нового".

## The inbox body
~~~markdown
# Engineer's inbox

Updated <UTC time> by the director "<your title>" (<first 8 of its id>); digests on demand only, no timer.

## To approve or decide
1. **Approval.** "<session title>" has waited <m> min on a <tool> call: open it. <session link>
2. **Merge.** PR #<n> "<title>": <the gate's exception, in plain words>. <PR link>
3. **Decision.** PR #<n>, question <k>: <the question in one line>; <options>; recommended <x>. <link>
4. **Command.** <why, one line>:
   ```powershell
   cd D:\prime-game; <the command, as the session gave it>
   ```

## To look at
1. Running: "<session title>" (<track>), waits on its own workflow <wf id>, started <time>. <session link>
2. Silent, reason unseen: "<session title>", nothing in flight. <session link>
3. <one line of news>. <link>

## Sources
<per repo and per session: read, or what was unavailable>; spend <once a shift>.
~~~
- Numbered items; each starts with its kind (**Approval.**, **Merge.**, **Decision.**, **Command.**) and carries a
  link or a ready command: a session's link, a PR or comment URL, or a PowerShell block that starts with `cd` to its
  absolute folder, copied as its session gave it (never one you made up). "Nothing." under an empty heading.
- Plain words: what goes wrong if it waits, the options, the recommendation; no jargon first (root `CLAUDE.md`).

## Relaying his answers
- He answers in your chat ("1A, 2 так"). An answer with two readings that build different things is read back in one
  sentence first. Then each answer goes to the session that asked:
  - `send_message` to that session: the item, his words quoted and translated into English, and the item's link;
  - refused (a session a scheduled task started is unattended and refuses it, probed on #484): a comment on the plan issue it watches
    (its wave comments' issue), or on the PR when the item came from one, starting "The engineer's answer, relayed by
    the director session <id> (<UTC time>):", his words quoted, then the item's link.
- The session that asked records the answer where it belongs ("Answered: <link>", an ADR line); you never do.
- Then drop the item from the inbox body at the next digest, and say in the chat line where each answer went.
- **His standing word** for a technical question (SKILL.md's Limits), sent the same way without asking him: "The
  engineer's standing word (https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6495904155): take your
  recommended option, <x>, and record it" with the item's link; a PR item is recorded as the trust ADR's last
  amendment says. The choice goes into your shift report's "taken for you".

