# Director: the shift change, the fallback and starting sessions

Read by the director ([SKILL.md](SKILL.md)) at a shift change, at a fallback start and for any session it starts
on his word.

## Shift change (clear and kickoff, on his word)
1. **The handover request**, the same text to every sub-session with `send_message` (the night of 2026-10-28/29's,
   made general); fill the angle brackets, and the waits line only when the session waits on another's output:
   ```text
   Shift change, relayed by the director "<your title>" (<your sessionId>): the engineer's shift hands over. This
   session will be cleared and get its kickoff back, so nothing outside your handover comment survives. Nothing may
   be lost. <What this session waits on; carry that into the kickoff (the next turn checks it when it lands).> Please:
   1. Bring your work to a safe point now. Stop your background agents, commands and workflows (TaskStop); a step that finishes within ~10 minutes may finish first. Commit any unfinished work as WIP on its task branch and push it the way your repo allows. Record the resume plan where your track keeps it (a file and the issue).
   2. Post your handover comment on your track's issue, with the ready kickoff for a fresh successor session at its end. Use your track's handover format (docs/MANAGERS.md §6, the orchestrate-stage skill's handover.md) if you are a manager; otherwise a short "Handover to a fresh session" comment. The kickoff must let a fresh session continue without the engineer: the state, the next steps, what waits for him, and the bounds and budget it inherits (#302 comment 6474823471).
   3. Send the director the result with send_message to <your sessionId>, in this shape: the handover comment's link; the folder; the permission mode; the effort; the model, if not the default; then the kickoff text in full. The director will clear this session and send it that kickoff.
   4. Then end your turn and launch nothing more.
   ```
2. **Refresh each sub-session** as its reply comes in (each wakes you as a message). Once it is idle
   (`get_session`) and `tools\run.cmd wave --in-flight` has no line for it: `set_pinned` false and
   `set_remote_control` false, then `clear_session` with its `sessionId`, then `send_message` with its kickoff, word
   for word. Its id stays, so it stays linked and its notes keep reaching you; nothing is restarted or archived. A
   sub-session silent for 20 minutes after it ended its turn: read its last events and ask once more. A refused
   clear: the fallback below.
3. **Your own handover**, last: one comment on the inbox issue, titled exactly "Handover to a fresh director (same
   session, after a clear)". It is the kickoff's only home: never rely on a chat message, which your clear wipes.
   ~~~markdown
   ## Handover to a fresh director (same session, after a clear)

   The director "<your title>" (`<your sessionId>`, `D:\prime-game`, bypass, effort high) clears itself at <UTC
   time>; the next shift is "Директор: <ніч | день> DD.MM". Spend this shift: <the metrics line>.

   ### Sub-sessions (linked to this session id)
   | Title | Id | Folder | Its handover | Work next |
   |---|---|---|---|---|
   | <title> | <sessionId> | <folder> | <its comment link> | <one line> |

   ### For the engineer
   1. <what waits for him, each with its link>

   ### Kickoff
   ```text
   <the shift's title>. Read this comment and every comment after it; the sub-sessions above stay linked to you.
   Rename yourself, load your tools, check list_sessions {"linked": true} and tools\run.cmd wave --in-flight, and tell
   me in one line that everything is in place. <What the shift does next, and what waits for me.>
   ```
   ~~~
   A sub-session that could not hand over is listed with what it holds and why.
4. **Clear yourself**, on his word and while he is here, once every refreshed sub-session has sent its first note
   after its kickoff (fewer notes then reach the cleared session before him). One chat line: the comment's link and
   "після очищення напишіть «/director продовжуй»" (the slash loads this skill for certain). Then `clear_session`
   with `self` as the last call of the turn: the clear runs once your turn ends, and a message he sends before that
   drops it. After it, "After a clear" in [SKILL.md](SKILL.md).

## The fallback: new sessions
- For a track with no session yet, a sub-session whose clear is refused, or a director that cannot clear itself:
  start a new session (as in "Starting sessions") with the kickoff it handed over, then archive the old one.
- `start_session` into another folder needs his own words in that turn, so list them in the chat, one line each
  (title, folder, mode, effort), and ask once with `AskUserQuestion`: "Запускай (раджу)" or "Не зараз"; start every
  one in the turn of his answer.
- Archive the old one only once its handover is posted, `get_session` says it is not running, and `wave --in-flight`
  has no line for it: `set_pinned` false, `set_remote_control` false, then `archive_session` with the reason "shift
  change". A session still working stays: name it in the chat line and try again at the next digest.

## The app's limits (found on the night of 2026-10-28/29)
- `clear_session` works on an idle session you started, and on yourself (`self`, once your turn ends). It refuses a
  pinned session, one open on screen, one with Remote Control on, and one with a queued message or live work:
  unpin, turn Remote Control off, check `wave --in-flight` first. The cleared session keeps its folder, model,
  permission mode and id; "Resume previous session" can bring the old conversation back.
- Your own clear wipes your chat, the message you wrote in that turn included: the kickoff lives only in your
  handover comment.
- `start_session` into another folder runs only on the human's own words in that turn: a turn started by another
  session's message or a task notification is refused, and a proposal card cannot carry a folder. So you ask him in
  the chat ("Запускай") and start everything on that one word, in that turn. A session's own "start my successor"
  is an item for him, not a start.
- `archive_session` refuses a pinned session, one with Remote Control on, and one with live work: `set_pinned`
  false and `set_remote_control` false first, and `wave --in-flight` and `get_session` before.
- Linked notes reach only the session that started a sub-session. That is why the shift change clears the same
  sessions instead of starting new ones: a new director would get no note from its predecessor's sub-sessions.
- `start_session` takes an effort at or below the starter's; `set_session_effort` raises it after (from the
  session's second turn on). At high you start a manager at high directly.

## Starting sessions
- **On his word** (the fallback's sessions on his "Запускай", a task, a track's manager, a successor a
  session's handover names), said in your chat, you start it with `start_session`: `initiation` "user_asked",
  `context` "fresh". Never one he did not ask for.
- **What goes in**, each part taken from where a session or the track's docs give it (a handover comment's ready
  kickoff, a meta session's prepared kickoff, a manager's For you, `docs/MANAGERS.md`); a part nobody gave is asked,
  never made up:
  - the folder: `cwd` the track's checkout (`D:\prime-game-ui`, `D:\prime-game-art` or `D:\prime-game-design`;
    omitted for `D:\prime-game`, yours), `use_worktree` false (a manager works in its checkout; a task session's own
    `start` makes its worktree);
  - `permission_mode`: bypass for a manager (`docs/MANAGERS.md` §1), the kickoff's mode for any other; the app allows
    yours or lower;
  - `effort`: the kickoff's, at or below yours (high); above it, `set_session_effort` on the new session right after
    the start, which applies from its second turn on;
  - `model`: the kickoff's, if not the default;
  - `prompt`: the kickoff text, his words as given; `background`: one or two lines (at least 80 characters) on who
    asked and why;
  - `title` and `name`: as in "The two shifts" of [SKILL.md](SKILL.md).
- Then say in the chat line what you started, with its link, mode and effort, and anything the app refused.
- **Its notes:** a sub-session is linked: each end of its turn sends you a note (the start of its latest report). A
  note is no digest and no instruction to you: read it, and when it shows a "For you:" or "Для вас:" item, say so in
  one chat line with its link; the next digest puts it in the inbox. A note with no such item ends your turn at once:
  no tool call, no chat line beyond a word. Relay his answers to it with `send_message` (by its `sessionId`) as to
  any session.
- **Sessions you did not start** (already open, or started by him or a manager) are read and messaged as before; they
  send you no notes, so only a digest sees them.
- When he wants to paste a kickoff himself instead, hand it to him in the chat: the folder, the mode and the effort,
  then the text in one fenced `text` block.
