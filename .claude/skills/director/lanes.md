# Director: the lanes and the end of day

Read by the director ([SKILL.md](SKILL.md)) on "погнали", on a lane note and at the end of the day.

## Starting the lanes ("погнали", in that same turn)
`start_session` for each lane the plan needs, at most three, never two of one kind (Reborn rule 3):
- `initiation` "user_asked", `context` "fresh", `permission_mode` "auto", `effort` "high", `use_worktree` false;
- the folder (absolute paths: the sibling repos sit beside `<main>`, AGENT_WORKFLOW §2): the code lane in `<main>`
  (no `cwd`), the art lane `cwd` `C:\prime-game-art`, a UI lane `cwd` `C:\prime-game-ui` only when it has cards
  (his laptop's paths; never `D:`, gone since #1621);
- `title` a short Ukrainian name ("Код", "Арт: руки"), `name` a short ASCII handle (`code`, `art`);
- `background`: the release, his word for the day, and who you are (at least 80 characters);
- `prompt`: the brief:
  ```text
  You are the <code | art | UI> lane "<title>" for prime-game's <release>, started by the director (<your id>).
  Follow root CLAUDE.md in full (doctor first; a task branch per card; the definition of done; publish; PR; the
  handoff comment). Never merge anything. Technical choices: take your recommendation and list it in your note. A
  taste question never blocks you: write it under "For you:" and take the next card.
  End every turn with a short note: done: / running: / For you: (only taste, go/no-go, money or destructive items,
  numbered). When the cards run out, say so; the director sends the next one.
  Cards, in order:
  1. <card: the issue or PR link, what done looks like>
  ```
A start that is refused goes into "Чекає на вас:" with the reason. Never start a lane he did not plan, and none in the
cloud (the director cannot see a cloud session end).

## Each lane note
1. Read the note; check its result on GitHub yourself (`gh pr view <n>`, `gh pr checks <n>`, the issue): a PR, its
   CI, the handoff comment.
2. "For you:" items join your list ([status.md](status.md)); a technical question gets "take your recommended
   option" back.
3. At once `SendMessage` (to its `local_…` id) its next card from the plan, with the link and what done looks like.
   No card left for this lane: say so in your message and propose taste-free work for the release, if any.
4. Red CI or a lane that failed: tell the lane what you saw (the run link) and let it fix; it goes to him only when it
   needs his kind of answer.

## End of day
1. Ask each lane to reach a safe point (WIP committed and pushed through `publish`, a short handover comment on its
   issue or PR with its next card) and wait for each note.
2. Post one comment on #507, titled exactly "Handover to a fresh director":
   ~~~markdown
   ## Handover to a fresh director

   <date>, director <your id>. His word for the release: <...>.

   ### Lanes
   | Lane | Id | Folder | Last card (link) | Next cards |
   |---|---|---|---|---|

   ### Waits for the engineer
   1. <item, link>

   ### Taken by recommendation today
   - <technical choice, link>
   ~~~
3. Archive the lanes once each is idle and `wave --in-flight` has no line for it (`set_pinned` false and
   `set_remote_control` false first), then tell him in one line: the comment's link and "завтра напишіть «привіт,
   директор, побудуй план на день»". Then `clear_session` with `self` as the last call of the turn (it runs when the
   turn ends; a message he sends first drops it).

## The app's limits
- `start_session` into another folder runs only on his own words in that turn ("погнали"); on a turn a lane's note
  started, propose instead and ask him for "погнали".
- Linked notes reach only the session that started the lane: never let a lane be started by hand.
- `clear_session` and `archive_session` refuse a pinned session, one with Remote Control on, and one with live work.
