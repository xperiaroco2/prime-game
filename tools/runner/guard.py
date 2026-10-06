"""The thin guard: which shell commands write to the ask-protected paths, or delete recursively or discard git work
beyond the session's own worktree and task branch (docs/AGENT_WORKFLOW.md §8.2).

`Edit(**/.claude/settings.json)` and `Edit(**/addons/**)` ask rules stop the file tools, but not a shell write:
Claude Code checks a redirect or `tee` target only against Edit allow and deny rules, and cannot see where
`Copy-Item` or `cp` writes. The PreToolUse hook (`run hook guard`) passes Bash and PowerShell commands here and asks
the human when one writes to `.claude/settings*.json` or `addons/`. Everything else passes silently, so the agent
can work alone.

Text ask rules cannot tell a delete of the agent's scratch folder from a delete of the repo, so the guard also judges
two commands by their target (issue #47):
- a recursive delete asks when a target is the project (the main checkout or a worktree), inside it (but not inside
  the session's own worktree, below), above it, a
  drive root, `/`, or the home or temp folder itself (`~`, `$HOME`, `$env:TEMP`), or cannot be resolved and names the
  project: its folder name, `git rev-parse --show-toplevel`, `$PWD` inside it, a command's output that names a path
  in it (`$(realpath core)`, `(Resolve-Path core)`), a variable assigned from such text, or a relative path after an
  unresolvable `cd` made from inside it. Recursive deletes are `rm -r` in any bash spelling, `Remove-Item -Recurse`
  (or `-r`, `-rec`), `rmdir /s`, `rd /s/q`, `del /s`, a plain delete fed by a recursive listing
  (`Get-ChildItem core -Recurse | Remove-Item`), an unfiltered `find -delete` or `find -exec rm -rf`, and
  `shutil.rmtree('x')` or `[IO.Directory]::Delete('x', $true)` with a literal path. The targets of a pipeline
  (`$_`, `{}`, `%`, none) are the paths its first command names, or the working directory. A PowerShell array
  (`a,b`) and a bash brace expansion (`x/{a,b}`) are judged item by item. Regenerated output (`tools/out/`,
  `.godot/`, any `__pycache__/`) and the gitignored scratch folder `tests/scratch/` pass, in the main checkout and in
  every worktree; so do the scratchpad, `$TEMP/x`, `/tmp/x` and `~/x`.
- No shell call keeps variables from an earlier one, so in bash a variable the command never assigns is also judged
  as empty (`rm -rf "$X"/*` is `rm -rf /*`; `cd "$X"` stays where it is). A bash subshell (`( ... )`, `$(...)`)
  keeps its `cd` and variables to itself; `cd -` and `popd` go back where the command was.
- `git reset` asks with `--hard`, `--merge` or `--keep`, or when it moves the branch (`git reset HEAD~1`,
  `git reset --soft origin/main`, `git reset v0.1.0`), in a repository anywhere inside the project (`tools/out/`
  too) but the session's own worktree (below). Unstaging (`git reset`, `git reset -q`, `git reset -- <paths>`, `git reset HEAD -- <paths>`,
  `git reset core`) passes. A lone argument is a revision when it looks like one (a SHA, `~`, `^`, `origin/x`,
  `refs/x`, `v1.2`, a task branch `net/40-x`, `main`); another bare name (`git reset feature-x`) counts as a path.
- Out of scope: deletes whose target only a run could show (a variable from the environment, a PowerShell variable
  the command never assigns, a path read from a file, a computed `rmtree(p)`), filtered deletes, even project-wide
  ones (`find . -name '*.orig' -delete`, `Get-ChildItem -Recurse -Filter *.tmp | Remove-Item`; a filter of `*` or
  before `-prune -o` is none), and links (a delete through a junction in `tests/scratch/` reaches its target).
- A filtered recursive delete in the temp folder (issue #464: a glob after `$TEMP`, `$TMP`, `$TMPDIR`, `$env:TEMP`,
  `%TEMP%` or `/tmp`, such as `rm -rf "$TEMP"/rmtree-*`, or a PowerShell `Get-ChildItem $env:TEMP -Filter 'x*'` that
  does not recurse, piped to `Remove-Item -Recurse`) is judged by what it matches: it passes unless the pattern
  reaches outside the folder (`..`) or has an unknown part, it may match a Claude scratchpad root or a folder that
  holds one (`claude/<project>/<session>/scratchpad`, any session's: the guard does not know the session), or a
  match the repository reader lists (hooks.GitFiles.temp_matches) is or holds a worktree. A literal path there is
  judged as before.

The session's own worktree is free (issue #51): the worktree `.claude/worktrees/<n>` its working directory is in, or,
for a session in the main checkout (a manager's task session, whose shell starts there on every call), the first
worktree its command enters with `cd` or `git -C`. The main checkout is owned only by a cloud session (issue #381:
`CLAUDE_CODE_REMOTE` true and not CI, common.cloud_session) whose working directory is in no worktree, while a task
branch (TASK_BRANCH_RE) is checked out there: its task number is that branch's, whichever task it is (no worktree folder
pins it). The repository (`.git`), `.claude` and the other worktrees (`.claude/worktrees`), and any glob that may name
them, stay outside it; so do `git clean -x|-X|-e|-ff` (ignored files and nested repositories), `git stash -a` and magic
pathspecs (`:(top)x`) there. Inside the own worktree (not its folder itself) recursive deletes pass. Git commands that
discard work or rewrite history (`reset` that discards or moves, `checkout`/`restore` of paths, `clean`, forced
`checkout`/`switch`, `rebase`, `stash drop|clear`, `worktree remove|move`) pass there on the task branch, and in a
repository outside the project; they ask in the main checkout (but a cloud session's, above), in another worktree, after
the command switched to another branch, and when their pathspec reaches another checkout. A pathspec the guard cannot
resolve (`core/$f.gd` in a loop, `$(git diff --name-only)`) is judged by the folder before its unknown part (issue #457:
git refuses a pathspec outside its repository), but not after a `..` in the unknown part, not when the folder or the
unknown part is in or names `.claude`, `.git` or `addons`, and not in a cloud session's main checkout.
`worktree remove|move` of an absolute path inside the own worktree passes; a relative name asks (git matches a worktree
by its last path parts).
Branch changes are judged by name whatever the checkout: deleting (`branch -d|-D`), moving (`branch -f`, `checkout -B`,
`switch -C`) or overwriting (`branch -M|-C`) a branch, or rebasing one by name (not `HEAD` or `@`: git then rebases a
detached HEAD), passes only for the task branch and its helpers (`<task branch>-x`, `<task branch>/x`); `stash
drop|clear` only for entries made on them (the stash is shared by every checkout). An interactive rebase is judged like
any other rebase, whatever editor it names (issue #457 reversed #104's editor ask: the engineer, 2026-10-06, "git is
protected on GitHub"). `rebase --update-refs`, `rebase --exec` and `git -c core.hooksPath=...` always ask. Rebase
options are read as git reads them (issue #105): a cluster letter by letter (`-qx`), an attached value (`-x'cmd'`), a
unique prefix of a long option (`--exe=cmd`, `--up`), and `rebase.updateRefs` set by `git -c` or `--config-env` counts
as `--update-refs`. A nested shell inherits the `VAR=value` prefixes of the command that starts it (`GIT_DIR=x bash -c
'...'`). Branch, ref and stash names come from a repository reader (hooks.GitFiles); without one no branch is the
session's own.

gh reads of other repositories run without a prompt (issue #68), so no text rule asks for `gh -R|--repo`. The guard
asks instead when a gh command names a repository other than this project's (`origin`, read by hooks.GitFiles) and
is not a read (GH_READS, `gh api` GET): through `-R|--repo`, `GH_REPO`, a github.com URL argument,
`gh repo <sub> owner/name`, `gh issue transfer`'s destination or a `gh api repos/owner/name/...` endpoint with a
write method (`-X`, or fields that make it a POST). The values of text options (`--body`, `--title`, `-f`) never
name the repository. Out of scope: GraphQL mutations (a node ID does not say its repository) and a gh command run in
a clone of another repository without naming it. A repository owned by gh's active account (what `gh api user` returns,
read from gh's `hosts.yml` by hooks.GitFiles; issue #464), also through a variable the command assigns or with only
its owner readable (`xperiaroco2/$1`), passes like this project's, so the rules judge the command, except the kinds
the rules deny or ask for (GH_OWNER_KEPT, GH_OWNER_KEPT_OPTIONS: merges, deletion, auth, secrets, ...), `gh issue
transfer`, and a `gh api` write that is not a POST or reaches a kept endpoint (GH_API_KEPT_RE): those keep the
guard's ask, since a spelling like `gh pr -R x merge` slips past the rules' text.

Like those Edit rules, it protects the project's own paths: `addons/` and `.claude/settings*.json` at the top of the
main checkout or of a worktree. It resolves each target against the session's working directory, `cd`, and the
variables the same command assigns; `$TEMP`, `$env:TEMP`, `~` and similar are outside the project. A target it
cannot resolve (an unknown variable, `$(...)`, a PowerShell `(...)` argument) counts as protected when its text names
a protected path. It also looks inside `bash -c`, `powershell -Command`, `$(...)`, pipelines
(`Get-ChildItem addons | Remove-Item`, `| xargs rm`), `for` loops over protected paths, and the inline code of
interpreters (`python -c`, a heredoc fed to Python, `node -e`) and .NET calls (`[IO.File]::WriteAllText`).
Out of scope: scripts it would have to run, globs that only match by expansion (`a*ons`), `git apply`, `awk -i`, `ed`.
Pure functions only; the hook entry point is in hooks.py.
"""

from __future__ import annotations

import fnmatch
import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

BASH, POWERSHELL = "bash", "powershell"

# A resolved path outside every project: temp, home, a URL.
OUTSIDE = "<outside>"
# Variables that always point outside the project.
OUTSIDE_VARS = {
    "temp", "tmp", "tmpdir", "home", "userprofile", "appdata", "localappdata", "programfiles", "programdata",
    "windir", "systemroot",
}  # fmt: skip
VAR_RE = re.compile(r"\$\{(\w+)\}|\$env:(\w+)|\$(\w+)|%(\w+)%", re.IGNORECASE)
ASSIGN_RE = re.compile(r"^\$?([A-Za-z_]\w*)=(.*)$", re.DOTALL)
PS_VAR_RE = re.compile(r"^\$(?:env:)?([A-Za-z_]\w*)$")

# A task branch, as start.py names it: `<area>/<n>-<slug>` (the same form as publish.TASK_BRANCH_RE).
TASK_BRANCH_RE = re.compile(r"^[a-z][a-z0-9]*/[0-9]+-[a-z0-9][a-z0-9._-]*$")

# Words that only prefix the real command.
PREFIXES = {
    "sudo", "env", "command", "builtin", "exec", "nohup", "time", "nice", "xargs", "call", ".", "timeout", "stdbuf",
    "do", "then", "else", "elif", "if", "while", "until", "!",
}  # fmt: skip
# Prefix options that take a separate value (`xargs -n 1 rm`, `nice -n 5 rm`), case-sensitive.
PREFIX_VALUED = {
    "xargs": {"-n", "-I", "-L", "-P", "-d", "-E", "-s", "-a"},
    "nice": {"-n"},
    "timeout": {"-s", "-k"},
    "stdbuf": {"-i", "-o", "-e"},
}
# Prefixes whose first argument after the options is a number or a duration (`timeout 60 rm`).
PREFIX_DURATION = {"timeout"}
# Where the working directory moves for the rest of the command.
CD_VERBS = {"cd", "chdir", "pushd", "set-location", "sl", "push-location"}
# The last positional argument (or the destination option) is written; the others are only read.
COPY_VERBS = {"cp", "copy", "copy-item", "cpi", "install", "rsync", "scp"}
# Every positional argument after the first is a destination.
COPY_REST_VERBS = {"xcopy", "robocopy"}
# Every path argument is written (moved, removed, created or overwritten).
WRITE_VERBS = {
    "mv", "move", "move-item", "mi", "ren", "rename", "rename-item", "rni",
    "rm", "del", "erase", "rd", "rmdir", "ri", "remove-item", "clear-content", "clc",
    "touch", "mkdir", "md", "new-item", "ni", "ln", "truncate", "chmod", "chown", "attrib", "icacls", "tee", "patch",
}  # fmt: skip
# PowerShell cmdlets that write their content to one path: -Path/-FilePath or the first positional argument. The
# other arguments are the content (`Add-Content .gitignore "addons/"` writes .gitignore).
CONTENT_VERBS = {
    "set-content", "sc", "add-content", "ac", "out-file", "tee-object", "set-itemproperty", "sp",
    "new-itemproperty", "export-csv", "export-clixml", "set-acl",
}  # fmt: skip
# Commands that change the paths a pipeline feeds them (`Get-ChildItem addons | Remove-Item`). Copies are not here:
# the pipeline gives them sources, and their destination is on the command line.
PIPED_PATH_VERBS = {
    "rm", "del", "erase", "rd", "rmdir", "ri", "remove-item", "mv", "move", "move-item", "mi",
    "ren", "rename", "rename-item", "rni", "clear-content", "clc",
}  # fmt: skip
# A pipeline item, when it stands where a path goes.
PIPE_ITEM_RE = re.compile(r"^(\$_|\$psitem|\{\}|%$)", re.IGNORECASE)
# Archive tools: every argument after the archive itself is where they extract to.
EXTRACT_VERBS = {"unzip", "expand-archive", "tar", "7z"}
# In-place editors: they write only with -i.
IN_PLACE_VERBS = {"sed", "perl"}
# Downloads: they write the value of their output option.
DOWNLOAD_VERBS = {"curl", "wget", "invoke-webrequest", "iwr", "invoke-restmethod", "irm", "start-bitstransfer"}
DOWNLOAD_OPTIONS = {"-o", "--output", "-outfile", "--output-document", "-p", "--directory-prefix", "-destination"}
# git subcommands that rewrite files in the working tree when they name a path (unless only the index changes).
GIT_WRITES = {"mv", "rm", "checkout", "restore", "clean", "stash"}
GIT_INDEX_ONLY = {"--cached", "--staged"}
# Shells whose code argument is analysed like a command of its own.
NESTED_SHELLS = {"bash": BASH, "sh": BASH, "zsh": BASH, "cmd": POWERSHELL, "powershell": POWERSHELL}
NESTED_SHELLS |= {"pwsh": POWERSHELL, "invoke-expression": POWERSHELL, "iex": POWERSHELL}
DESTINATION_OPTIONS = {"-destination", "-dest", "-t", "--target-directory", "-destinationpath"}
PATH_OPTIONS = {"-path", "-literalpath", "-filepath"}
# PowerShell options whose value is data, never a path that is written.
VALUE_OPTIONS = {
    "-value", "-inputobject", "-encoding", "-itemtype", "-type", "-filter", "-include", "-exclude", "-delimiter",
    "-name", "-propertytype", "-aclobject", "-erroraction", "-ea", "-warningaction", "-wa", "-errorvariable",
    "-ev", "-outvariable", "-ov", "-credential", "-stream",
}  # fmt: skip
INTERPRETER_RE = re.compile(r"python|^py$|^node$|^perl$|^ruby$|^php$|^deno$")

# APIs that write files from inline code. A line of interpreter code (or a .NET call) that uses one and also names a
# protected path counts as a write.
WRITE_API_RE = re.compile(
    r"\bopen\([^)]*,\s*['\"][wax]"
    r"|\.write_(?:text|bytes)\("
    r"|\bshutil\.(?:copy|move|rmtree)"
    r"|\bos\.(?:remove|unlink|rename|replace|rmdir|makedirs|mkdir|truncate)\("
    r"|\.(?:unlink|rmdir|touch|symlink_to)\("
    r"|\bjson\.dump\("
    r"|\.(?:writeFile|appendFile|copyFile|cp|rename|unlink|rm|rmdir|mkdir|truncate)(?:Sync)?\(",
    re.IGNORECASE,
)
DOTNET_WRITE_RE = re.compile(
    r"\[(?:System\.)?IO\.(?:File|Directory)\]::(?:Write|Append|Copy|Move|Delete|Create|Replace|Open(?!Read))"
    r"|(?:System\.)?IO\.StreamWriter",
    re.IGNORECASE,
)
PROTECTED_TEXT_RE = re.compile(
    r"(?:^|[\s'\"=(/\\:,])addons(?:[/\\'\"\s),]|$)|\.claude[/\\]+settings[^/\\\s'\"]*\.json",
    re.IGNORECASE,
)
SETTINGS_NAMES = ("settings.json", "settings.local.json")

# Finding areas of the target-judged commands (the others are the protected paths above, or "piped").
DELETE, GIT = "recursive delete", "git"
# A filtered recursive delete in the temp folder that may reach a Claude scratchpad root or a worktree (issue #464).
TEMP_DELETE = "filtered delete in temp"
# Commands that delete; each is recursive only with its recursive option.
DELETE_VERBS = {"rm", "del", "erase", "rd", "rmdir", "ri", "remove-item"}
# cmd.exe delete commands, and their switches (`rmdir /s /q x`, `rd /s/q x`): options, not paths.
CMD_DELETE_VERBS = {"rd", "rmdir", "del", "erase"}
# Git Bash rewrites `/s` to a path, so there it is spelled `//s`.
CMD_SWITCH_RE = re.compile(r"^(//?[a-z?])+$", re.IGNORECASE)
# Inside the project, but deleting it loses no work: output that the next run writes again (the runner's, Godot's
# import cache) and the gitignored scratch folder for temporary files that must live under res:// (a probe test).
# `git reset` does not get this exemption: git finds the project's repository from there.
DISPOSABLE = ("tools/out", ".godot", "tests/scratch")
# Text that names the project when a path cannot be resolved, besides its folder name (Paths.name_re).
TOPLEVEL_TEXT = "show-toplevel"
# A path that does not depend on the working directory, or that may not (a leading variable or `~`).
ABSOLUTE_RE = re.compile(r"^([A-Za-z]:)?[\\/~]|^[A-Za-z]:|^\$")
CWD_TEXT_RE = re.compile(r"\$pwd\b|\$\(pwd\)|get-location|\$\{pwd\}|%cd%", re.IGNORECASE)
# A home or temp folder itself (`~`, `$HOME`, `$env:TEMP\`, `$TEMP/*`), not a folder in it.
OUTSIDE_ROOT_RE = re.compile(r"^(<outside>|~)[/\\]*\*?$")
# A delete target in the temp folder (issue #464): `$TEMP/x`, `${TMPDIR}/x`, `$env:TEMP\x`, `%TEMP%\x`, `/tmp/x`; the
# variable's name (none for `/tmp`) and the part after it.
TEMP_TARGET_RE = re.compile(
    r"^(?:\$\{?(temp|tmp|tmpdir)\}?|\$env:(temp|tmp)|%(temp|tmp)%|/tmp)(?![\w:])[\\/]+(.*)$", re.IGNORECASE
)
# A glob character: the delete names what a pattern matches, not one path.
GLOB_RE = re.compile(r"[*?\[]")
# Where Claude Code keeps a session's scratchpad in the temp folder: `claude/<project>/<session>/scratchpad`.
SCRATCHPAD_PARTS = ("claude", "*", "*", "scratchpad")
# git reset modes that discard work in the working tree or the index.
RESET_MODES = {"--hard", "--merge", "--keep"}
# A lone `git reset` argument that is a revision rather than a path: HEAD~1, main^, @{u}, a SHA, a remote or ref
# (`origin/x`, `refs/x`), a version tag (`v0.1.0`), a task branch (`net/40-slug`) or a usual trunk name. Another
# bare name (`git reset core`, `git reset feature-x`) counts as a path, which is what git does when it exists.
REVISION_RE = re.compile(
    r"[~^]|@\{|^@$|^[0-9a-f]{7,40}$|^(?:origin|upstream|refs|remotes)/|^v?\d+(?:\.\d+)+$|^[a-z]+/\d+-"
    r"|^(?:main|master|develop|dev|trunk|(?:orig|fetch|merge)_head)$",
    re.IGNORECASE,
)
# A PowerShell cmdlet name (`Get-ChildItem`), where a `foreach` loop names its items.
CMDLET_RE = re.compile(r"^[A-Za-z]+-[A-Za-z]+$")
# Commands whose output is paths under their arguments, or under the working directory when they name none.
LISTING_VERBS = {"ls", "dir", "get-childitem", "gci", "find", "git", "fd", "tree"}
CWD_VERBS = {"pwd", "get-location", "gl"}
# find options that narrow what it deletes (`find . -name '*.orig' -delete` is a targeted cleanup).
FIND_FILTERS = {
    "-name", "-iname", "-path", "-ipath", "-wholename", "-regex", "-iregex", "-newer", "-mtime", "-mmin", "-size",
    "-empty", "-perm", "-user",
}  # fmt: skip
# Deletes in inline code whose first argument is a literal path: `shutil.rmtree('x')`,
# `[IO.Directory]::Delete('x', $true)`.
CODE_DELETE_RE = re.compile(
    r"\bshutil\.rmtree\(\s*[rRbB]?['\"]([^'\"]+)['\"]"
    r"|\[(?:system\.)?io\.directory\]::delete\$?\(\s*['\"]?([^'\",)]+?)['\"]?\s*,\s*\$true",
    re.IGNORECASE,
)


# Global git options whose value may be a separate word (`git --git-dir .git reset --hard`).
GIT_VALUED = {"-c", "-C", "--git-dir", "--work-tree", "--namespace", "--config-env"}
# Where a git command or a delete acts, relative to the session (issue #51): its own worktree, outside the project
# (a scratch repository), or somewhere else in the project (the main checkout, another worktree, a drive root above
# it, or text that names the project but cannot be resolved).
OWN, OUTSIDE_PROJECT, ELSEWHERE = "own", "outside", "elsewhere"
# A branch whose name continues the task branch's after one of these is one of its helpers
# (`tooling/51-x-backup`, `tooling/51-x/probe`).
HELPER_SEPARATORS = ("-", "/", ".", "_")
# Options of git subcommands that take a separate value (`git switch -c name`, `git rebase --onto x y`).
CHECKOUT_VALUED = {"-b", "-B", "--orphan", "--conflict", "--pathspec-from-file"}
SWITCH_VALUED = {"-c", "-C", "--create", "--force-create", "--orphan", "--conflict"}
RESTORE_VALUED = {"-s", "--source", "--conflict", "--pathspec-from-file"}
CLEAN_VALUED = {"-e", "--exclude"}
# git rebase reads its options as git's parse-options does (issue #105). Its long options (`git rebase
# --git-completion-helper-all`, git 2.49): one is named by any unique prefix (`--interac`, `--exe=x`, `--up`).
REBASE_LONG = (
    "--onto --keep-base --no-verify --quiet --verbose --no-stat --signoff --committer-date-is-author-date "
    "--reset-author-date --ignore-date --ignore-whitespace --whitespace --force-rebase --no-ff --continue --skip "
    "--abort --quit --edit-todo --show-current-patch --apply --merge --interactive --preserve-merges "
    "--rerere-autoupdate --empty --keep-empty --autosquash --update-refs --gpg-sign --autostash --exec "
    "--allow-empty-message --rebase-merges --fork-point --strategy --strategy-option --root "
    "--reschedule-failed-exec --reapply-cherry-picks --verify --stat --ff --no-onto --no-keep-base --no-quiet "
    "--no-verbose --no-signoff --no-committer-date-is-author-date --no-reset-author-date --no-ignore-date "
    "--no-ignore-whitespace --no-whitespace --no-force-rebase --no-preserve-merges --no-rerere-autoupdate "
    "--no-keep-empty --no-autosquash --no-update-refs --no-gpg-sign --no-autostash --no-exec "
    "--no-allow-empty-message --no-rebase-merges --no-fork-point --no-strategy --no-strategy-option --no-root "
    "--no-reschedule-failed-exec --no-reapply-cherry-picks"
).split()
# Long options whose value may be the next word (`--onto x`); `--gpg-sign` and `--rebase-merges` take only `=value`.
REBASE_LONG_VALUED = {"--onto", "--whitespace", "--empty", "--exec", "--strategy", "--strategy-option"}
# Single-dash letters, read one by one from a cluster (`-qi` is `-q -i`). A valued letter takes the rest of the
# cluster or the next word (`-x'cmd'`, `-Xtheirs`, `-s ort`). git reads the rest of `-r` and `-S` as their optional
# value (`-rx` is mode "x", an error); here they stay flags, so `-rx cmd` still counts as an exec.
REBASE_SHORT = {
    "i": "--interactive",
    "x": "--exec",
    "r": "--rebase-merges",
    "s": "--strategy",
    "X": "--strategy-option",
}
REBASE_SHORT_VALUED = {"s", "X", "x", "C"}
# Config values git reads as false (`git -c rebase.updateRefs=no`); any other value, or none, is true.
GIT_FALSE = {"false", "no", "off", "0", ""}
# git rebase forms that continue or end a rebase in progress: they name no branch.
REBASE_STEPS = {"--continue", "--skip", "--abort", "--quit", "--show-current-patch"}
STASH_REF_RE = re.compile(r"^(?:stash@\{(\d+)\}|(\d+))$", re.IGNORECASE)
# The unknown part of a git pathspec names a folder that may hold a protected path (`$(ls .claude)`, issue #457).
LITERAL_SHARED_RE = re.compile(r"(?:^|[^\w.-])(?:\.claude|\.git|addons)(?![\w-])", re.IGNORECASE)

# gh aimed at another repository (issue #68). The finding area of a gh command that may write there.
GH = "gh"
# gh commands that only read: they pass whatever repository they name. Any other gh command that names a repository
# other than this project's asks. None: every subcommand of the group reads.
GH_READS: dict[str, set[str] | None] = {
    "issue": {"view", "list", "ls", "status"},
    "pr": {"view", "list", "ls", "diff", "checks", "status"},
    "release": {"view", "list", "ls", "verify", "verify-asset"},
    "repo": {"view", "list", "ls", "clone"},
    "run": {"view", "list", "ls", "watch"},
    "workflow": {"view", "list", "ls"},
    "label": {"list", "ls"},
    "cache": {"list", "ls"},
    "ruleset": {"view", "list", "ls", "check"},
    "rs": {"view", "list", "ls", "check"},
    "search": None,
}
# gh api methods that only read.
GH_READ_METHODS = {"GET", "HEAD"}
# gh options whose value is text, never a repository the command acts on (`--body "see https://github.com/x/y"`).
GH_TEXT_OPTIONS = {
    "-b", "--body", "-t", "--title", "-n", "--notes", "-m", "--message", "-d", "--description", "-h", "--homepage",
    "-q", "--jq", "-T", "--template", "--json", "-S", "--search", "-f", "--raw-field", "-F", "--field",
    "--body-file", "--notes-file", "-H", "--header", "--input", "-p", "--preview",
}  # fmt: skip
# gh api options that take a separate value (the endpoint is the first other argument).
GH_API_VALUED = GH_TEXT_OPTIONS | {"-X", "--method", "--hostname", "--cache", "-R", "--repo"}
# gh api options that add fields: without -X the request is then a POST.
GH_API_FIELDS = {"-f", "--raw-field", "-F", "--field", "--input"}
# A github.com web URL of a repository (`https://github.com/godotengine/godot/issues/1`) or an API URL of one.
GH_URL_RE = re.compile(
    r"^(?:https?://)?(?:www\.)?github\.com/([^/\s]+)/([^/\s#?]+)"
    r"|^(?:https?://)?api\.github\.com/repos/([^/\s]+)/([^/\s#?]+)",
    re.IGNORECASE,
)
# A repository argument: `owner/name`, `github.com/owner/name` or `HOST/owner/name` (another host is another repo).
GH_REPO_RE = re.compile(r"^(?:([\w.-]+\.[a-z]+)/)?([\w.-]+)/([\w.-]+?)(?:\.git)?/?$", re.IGNORECASE)
# A gh api endpoint of one repository: `repos/owner/name/...`; `{owner}/{repo}` is the current repository.
GH_API_REPO_RE = re.compile(r"^/?repos/([^/\s]+)/([^/\s?]+)", re.IGNORECASE)
# The variable that names the repository gh acts on when a command names none (else the working directory's).
GH_REPO_ENV = "gh_repo"
# gh commands that keep asking in a repository of gh's own account (issue #464): every one a deny or ask rule of
# .claude/settings.json names (merges, deletion, auth, secrets, ...), since `gh pr -R x merge` slips past the rule's
# text, and `gh issue transfer`, which moves an issue out of this repository. None: every subcommand of the group.
GH_OWNER_KEPT: dict[str, set[str] | None] = {
    "pr": {"merge", "review"},
    "repo": {"delete", "archive", "unarchive", "rename", "edit", "deploy-key"},
    "issue": {"delete", "transfer"},
    "label": {"delete"},
    "project": {"delete"},
    "release": {"create", "edit", "delete", "delete-asset", "upload", "download"},
    "workflow": {"run", "enable", "disable"},
    "auth": None,
    "secret": None,
    "variable": None,
}
# gh options that keep the ask there too: `gh issue comment --delete-last` (an ask rule).
GH_OWNER_KEPT_OPTIONS = {"--delete-last"}
# gh api endpoints that keep asking there with any write method (only POST passes): merges, secrets and variables,
# deploy keys, workflow dispatches, releases and a repository transfer, the API twins of the kept commands.
GH_API_KEPT_RE = re.compile(
    r"/(?:merges?|secrets|variables|keys|dispatches|releases|transfer)(?:[/?#]|$)", re.IGNORECASE
)
# The owner of a repository whose name the guard cannot read (`xperiaroco2/$1`, `https://github.com/o/$n`).
GH_OWNER_RE = re.compile(r"^(?:(?:https?://)?(?:www\.)?github\.com/)?([\w.-]+)/", re.IGNORECASE)


class NoRepo:
    """What the guard knows about the repository when the hook cannot read it (and in most tests): nothing. A branch
    it cannot name is never the session's own, so branch deletes and stash drops ask."""

    def branch(self, checkout: str) -> str | None:
        """The branch checked out in checkout (a normalized path), or None."""
        return None

    def refs(self) -> set[str]:
        """Local branch, remote branch (`origin/x` and `x`) and tag names, lower-case."""
        return set()

    def stash_branches(self) -> list[str] | None:
        """The branch each stash entry was made on, `stash@{0}` first; None when unknown."""
        return None

    def busy(self, checkout: str) -> bool:
        """Another live Claude session works in checkout (a normalized worktree path)."""
        return False

    def github_repo(self) -> str | None:
        """This project's GitHub repository as `owner/name` (lower-case), from the `origin` remote; None when
        unknown, and then every repository a `gh` command names counts as another one."""
        return None

    def gh_user(self) -> str | None:
        """The login of gh's active github.com account (what `gh api user` returns), lower-case; None when unknown,
        and then no repository passes for its owner (issue #464)."""
        return None

    def temp_matches(self, pattern: str) -> list[tuple[str, bool]] | None:
        """What a glob pattern relative to the temp folder (`/`-separated, no `..`) matches now: each match's path
        relative to it, and whether it is or holds a worktree; None when the folder cannot be listed (issue #464)."""
        return None

# `$(git rev-parse --show-toplevel)`: the checkout that contains the working directory.
TOPLEVEL_SUB_RE = re.compile(r"\$\(\s*git\s+rev-parse\s+--show-toplevel\s*\)", re.IGNORECASE)
# One bash brace alternation (`a/{x,y}`), not a `${var}` expansion.
BRACE_RE = re.compile(r"(?<!\$)\{([^{}]*,[^{}]*)\}")
# A PowerShell array item that is a plain value: a quoted string or a word without spaces or code.
PS_ITEM_RE = re.compile(r"^'[^']*'$|^\"[^\"]*\"$|^[^\s$()'\"]+$")


def _split_commas(text: str) -> list[str]:
    """text split at its commas outside parentheses and quotes (a PowerShell array: `a,b`, `'a','b'`)."""
    parts, depth, quote, start = [], 0, "", 0
    for index, c in enumerate(text):
        if quote:
            quote = "" if c == quote else quote
        elif c in "'\"":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(text[start:index])
            start = index + 1
    return parts + [text[start:]]


def _braces(word: str, limit: int = 16) -> list[str]:
    """The words a bash brace expansion makes (`tests/scratch/{x,../../core}`), at most limit of them."""
    match = BRACE_RE.search(word)
    if not match:
        return [word]
    result: list[str] = []
    for alternative in match.group(1).split(","):
        result += _braces(word[: match.start()] + alternative + word[match.end() :], limit)
        if len(result) >= limit:
            break
    return result[:limit]


def project_root(root: str) -> str:
    """The main checkout of root, which may be a worktree under `.claude/worktrees/<n>`."""
    match = re.match(r"^(.*)/\.claude/worktrees/[^/]+$", root)
    return match.group(1) if match else root


def _settings_name(name: str) -> bool:
    """name is, or as a glob could match, .claude/settings*.json."""
    return fnmatch.fnmatch(name, "settings*.json") or any(fnmatch.fnmatch(real, name) for real in SETTINGS_NAMES)


def protected(path: str) -> str | None:
    """Which ask-protected area a path's text names ('addons/' or '.claude/settings*.json'), or None.

    Used for text that cannot be resolved: any `addons` folder counts, and a `.claude` folder counts when the path is
    the folder itself or a file in it that is, or could match, `settings*.json` (the agent's own permissions).
    """
    parts = [p for p in path.replace("\\", "/").lower().split("/") if p not in ("", ".")]
    for index, part in enumerate(parts):
        if part == "addons":
            return "addons/"
        if part == ".claude" and (index == len(parts) - 1 or _settings_name(parts[index + 1])):
            return ".claude/settings*.json"
    return None


def project_area(relative: str) -> str | None:
    """The protected area of a path relative to the project root: top-level `addons/` and `.claude/settings*.json`
    of the main checkout or of a worktree under `.claude/worktrees/<n>/`."""
    parts = [p for p in relative.lower().split("/") if p]
    if parts[:2] == [".claude", "worktrees"] and len(parts) > 3:
        parts = parts[3:]
    if not parts:
        return None
    if parts[0] == "addons":
        return "addons/"
    if parts[0] == ".claude" and (len(parts) == 1 or _settings_name(parts[1])):
        return ".claude/settings*.json"
    return None


def text_area(text: str) -> str | None:
    """The protected area named anywhere in free text (an unresolved `$(...)` or `(...)` argument)."""
    match = PROTECTED_TEXT_RE.search(text)
    if not match:
        return None
    return "addons/" if "addons" in match.group(0).lower() else ".claude/settings*.json"


def normalize(path: str) -> str:
    """Lower-case, forward slashes, `..` collapsed, Git Bash `/d/x` as `d:/x`, no trailing slash."""
    text = path.replace("\\", "/")
    msys = re.match(r"^/([A-Za-z])(/|$)", text)
    if msys:
        text = f"{msys.group(1)}:/{text[3:]}"
    parts: list[str] = []
    for part in text.lower().split("/"):
        if part == "..":
            if len(parts) > 1:
                parts.pop()
        elif part != "." and (part or not parts):
            parts.append(part)
    return "/".join(parts) or "/"


class Paths:
    """Resolves the paths of one command: working directory, `cd`, and the variables the command assigns."""

    def __init__(self, root: str, cwd: str, home: str = "", shell: str = BASH) -> None:
        self.root = project_root(normalize(root))
        self.cwd: str | None = normalize(cwd) if cwd else self.root
        # The real home folder, when the hook knows it: `~` and `$HOME` resolve to it, so a project under home stays
        # protected. Without it they are OUTSIDE.
        self.home = normalize(home) if home else ""
        self.shell = shell
        # Where `popd` and `cd -` go back to, as (cwd, cwd_text, cwd_base).
        self.stack: list[tuple[str | None, str, str]] = []
        self.oldpwd: tuple[str | None, str, str] | None = None
        self.vars: dict[str, str | None] = {"claude_project_dir": self.root}
        self.tainted: dict[str, str] = {}
        # Variables whose value is unknown but whose words name the project (`for d in core/*`).
        self.project_vars: set[str] = set()
        # The text of the last `cd` target that could not be resolved, and the resolved directory it started from
        # (OUTSIDE or "" when that is unknown too).
        self.cwd_text = ""
        self.cwd_base = ""
        # Text that names the project: its folder name (not `D--prime-game`, the scratchpad's), or the git top level.
        name = re.escape(self.root.rsplit("/", 1)[-1])
        self.name_re = re.compile(rf"(?:^|[/\\:\s'\"]){name}(?:[/\\\s'\"]|$)|{TOPLEVEL_TEXT}", re.IGNORECASE)
        # The session's own worktree (issue #51): the one its working directory is in. A session in the main checkout
        # (a manager's task session, whose shell starts there each call) owns the worktree its command first `cd`s
        # into, or names with `git -C`, unless another live session works there (busy). The main checkout is owned
        # only by a cloud session on a task branch (issue #381, Analysis).
        self.own = self.worktree_of(self.cwd)
        self.claim = self.own is None
        # A cloud session's task branch, when it owns the main checkout (issue #381; set by Analysis).
        self.task = ""
        self.busy: Callable[[str], bool] = lambda _: False
        # A checkout or switch in this command left the own task branch: later git commands act on another branch.
        self.off_branch = False
        # A `git stash` in this command changed the stash: the entries read before it no longer match their indices.
        self.stash_moved = False

    def child(self, shell: str | None = None, prefixes: dict[str, str] | None = None) -> Paths:
        """The view of a nested shell (`bash -c`) or a `$(...)`: same directory and variables; its `cd` stays
        inside it. prefixes are the `VAR=value` words before the nested shell (`GIT_DIR=x bash -c ...`): its
        environment, like exported variables (issue #105)."""
        inner = Paths(self.root, "", self.home, shell or self.shell)
        inner.cwd, inner.vars, inner.tainted = self.cwd, dict(self.vars), dict(self.tainted)
        inner.project_vars, inner.cwd_text, inner.cwd_base = set(self.project_vars), self.cwd_text, self.cwd_base
        for name, value in (prefixes or {}).items():
            # Recorded like an assignment: a value the guard cannot compute still counts as the project when it names
            # it (`D=$(realpath core) bash -c 'rm -rf "$D"'`).
            inner.remember(name, value, [f"{name}={value}"])
        inner.oldpwd, inner.own, inner.claim, inner.busy = self.oldpwd, self.own, self.claim, self.busy
        inner.task = self.task
        inner.off_branch, inner.stash_moved = self.off_branch, self.stash_moved
        return inner

    def adopt(self, inner: Paths) -> None:
        """What a nested shell did to the repository and to the claim outlives it (its `cd` does not)."""
        self.off_branch, self.stash_moved = inner.off_branch, inner.stash_moved
        if self.claim and not inner.claim:
            self.own, self.claim = inner.own, False

    def worktree_of(self, path: str | None) -> str | None:
        """The worktree `.claude/worktrees/<n>` of this project that holds a resolved path, or None."""
        if path is None or path == OUTSIDE:
            return None
        match = re.match(rf"^({re.escape(self.root)}/\.claude/worktrees/[^/]+)(/|$)", path)
        return match.group(1) if match else None

    def owned(self, path: str, root_too: bool = False) -> bool:
        """A resolved path is inside the session's own worktree (or is its folder, with root_too). A cloud session's
        main checkout (issue #381) holds the other worktrees and the repository: they are never its own."""
        if not self.own:
            return False
        if self.own == self.root and self.shared(path):
            return False
        return path.startswith(self.own + "/") or (root_too and path == self.own)

    def shared(self, path: str) -> bool:
        """A resolved path in the main checkout is, or may name by a glob, the repository (`.git`), `.claude` or
        `.claude/worktrees`, or is inside one of them: every checkout's, not one session's."""
        if not path.startswith(self.root + "/"):
            return False
        parts = path[len(self.root) + 1 :].split("/")

        def may_be(part: str, name: str) -> bool:
            # Bash globs that fnmatch reads otherwise (`[^.]`, `[[:lower:]]`, `{s..t}`): any glob may match. The lexer
            # splits an extglob (`shopt -s extglob; rm -rf @(.git)`) before its `(`, leaving `@`, `!` or `+`.
            return part == name or any(c in part for c in "*?[{(") or part in ("@", "!", "+")

        if may_be(parts[0], ".git"):
            return True
        return may_be(parts[0], ".claude") and (len(parts) == 1 or may_be(parts[1], "worktrees"))

    def claim_worktree(self, path: str | None) -> None:
        """A session outside every worktree owns the first worktree its command enters, unless another live session
        works there. Either way the claim is spent: a second worktree in the same command is never owned."""
        if self.claim and (worktree := self.worktree_of(path)):
            self.own, self.claim = (None if self.busy(worktree) else worktree), False

    def where(self, token: str, cwd: str | None = "", literal: bool = False) -> str:
        """Where a git repository or pathspec acts: OWN (the own worktree, its folder included), OUTSIDE_PROJECT, or
        ELSEWHERE. A PowerShell array or a bash brace expansion is judged item by item; the worst item wins. With
        literal, an item the guard cannot resolve but that names the project is judged by its literal part
        (`literal_place`) instead of counting as ELSEWHERE."""
        places = {self._where(item, cwd, literal) for item in self.items(token)}
        return next(p for p in (ELSEWHERE, OWN, OUTSIDE_PROJECT) if p in places or p == OUTSIDE_PROJECT)

    def _where(self, token: str, cwd: str | None, literal: bool = False) -> str:
        path = self.resolve(token, cwd)
        named = path is None and (self.names_project(token) or self.computed(token))
        if path is None and not named and self.shell == BASH:
            path = self.resolve(token, cwd, empty=True)  # no call keeps variables: an unassigned one is empty
        if path is None:
            if named and literal:
                return OWN if self.literal_place(token, cwd) == OWN else ELSEWHERE
            return ELSEWHERE if named else OUTSIDE_PROJECT
        return self.place(path)

    def literal_place(self, token: str, cwd: str | None = "") -> str | None:
        """Where the literal part of an unresolvable path is (issue #457): the folder before its first variable or
        command output (`core/events/$f.gd` is in `core/events`, `$(git diff --name-only)` in the working
        directory), as place() says. None when that folder cannot be resolved either, when a `..` after the
        unknown part may climb out of it, or when the folder is in a hidden folder (`.claude`, `.git`), `addons/` or a
        glob of the checkout's top, or the unknown part names `.claude`, `.git` or `addons` (`$(ls .claude)`): it
        may name a protected path there."""
        cut = re.search(r"[$(`%]", token)
        if cut is None:
            return None
        head, tail = token[: cut.start()], token[cut.start() :]
        if re.search(r"(^|[/\\])\.\.([/\\]|$)", tail) or LITERAL_SHARED_RE.search(tail):
            return None
        folder = re.sub(r"[^/\\]*$", "", head) or "."
        path = self.resolve(folder, cwd)
        if path is None:
            return None
        top = self.worktree_of(path) or self.root
        first = path[len(top) + 1 :].split("/", 1)[0] if path.startswith(top + "/") else ""
        if first.startswith(".") or first == "addons" or any(c in first for c in "*?[{"):
            return None
        return self.place(path)

    def place(self, path: str) -> str:
        """Where a resolved path is: OWN, OUTSIDE_PROJECT or ELSEWHERE."""
        if not self.in_project(path, disposable=False):
            return OUTSIDE_PROJECT
        return OWN if self.owned(path, root_too=True) else ELSEWHERE

    def save(self) -> tuple:
        """The state a bash subshell (`( ... )`, `$(...)`) cannot change for the rest of the command."""
        where = (self.cwd, self.cwd_text, self.cwd_base)
        variables = dict(self.vars), dict(self.tainted), set(self.project_vars)
        return where, list(self.stack), self.oldpwd, variables

    def restore(self, state: tuple) -> None:
        where, stack, self.oldpwd, (self.vars, self.tainted, self.project_vars) = state
        (self.cwd, self.cwd_text, self.cwd_base), self.stack = where, list(stack)

    def items(self, token: str) -> list[str]:
        """The paths one word names: a PowerShell array (`a,b`, `'a','b'`, `@('a','b')`) is one path per item, and a
        bash brace expansion (`x/{a,b}`) one per alternative."""
        if self.shell == BASH:
            return _braces(token)
        text = token
        wrapped = re.fullmatch(r"@?\$\((.*)\)", token, re.DOTALL)
        if wrapped and all(PS_ITEM_RE.match(p.strip()) for p in _split_commas(wrapped.group(1))):
            text = wrapped.group(1)
        parts = [p.strip().strip("'\"") for p in _split_commas(text)]
        return [p for p in parts if p] or [token]

    def toplevel(self) -> str | None:
        """The checkout that contains the working directory (a worktree or the main checkout), if it is known."""
        cwd = self.cwd
        if cwd is None or cwd == OUTSIDE:
            return None
        worktree = re.match(rf"^({re.escape(self.root)}/\.claude/worktrees/[^/]+)(/|$)", cwd)
        if worktree:
            return worktree.group(1)
        return self.root if cwd == self.root or cwd.startswith(self.root + "/") else None

    def root_like(self, path: str) -> bool:
        """A resolved path is a drive root, `/`, the home folder, or everything in one of them (`/*`)."""
        while path.endswith("/*"):
            path = path[:-2]
        return path in ("", "/") or bool(re.fullmatch(r"[a-z]:", path)) or (bool(self.home) and path == self.home)

    def in_project(self, path: str, disposable: bool = True) -> bool:
        """A resolved path is the project, inside it (disposable folders aside, when disposable), above it (`/`,
        `D:/`), or a drive root or the home folder."""
        if path == OUTSIDE:
            return False
        if self.root_like(path):
            return True
        parts, root = path.split("/"), self.root.split("/")
        if not all(fnmatch.fnmatchcase(r, p) for r, p in zip(root, parts)):
            return False
        if len(parts) <= len(root) or not disposable:
            return True
        relative = parts[len(root) :]
        if relative[:2] == [".claude", "worktrees"] and len(relative) > 3:
            relative = relative[3:]
        if "__pycache__" in relative:
            return False  # Python's bytecode cache, rebuilt on the next run
        return not any("/".join(relative + [""]).startswith(r + "/") for r in DISPOSABLE)

    def names_project(self, token: str, follow_cd: bool = True) -> bool:
        """Unresolvable text that names the project: its folder, the git top level, `$PWD` inside it, or a variable
        assigned from such text. A relative path after an unresolvable `cd` is in the project when that `cd`
        started there, or named it."""
        if self.name_re.search(token):
            return True
        if CWD_TEXT_RE.search(token) and self.cwd not in (None, OUTSIDE) and self.in_project(str(self.cwd)):
            return True
        names = {next(g for g in m.groups() if g).lower() for m in VAR_RE.finditer(token)}
        if names & self.project_vars:
            return True
        if not follow_cd or self.cwd is not None or not self.cwd_text or re.match(ABSOLUTE_RE, token):
            return False
        if self.cwd_base:
            return self.in_project(self.cwd_base)
        return self.names_project(self.cwd_text, follow_cd=False)

    def project_target(self, token: str, cwd: str | None = "", disposable: bool = True, own_ok: bool = False) -> bool:
        """token, a delete target, is in the project: resolved, or by its text. A home or temp folder itself counts
        too. With own_ok, a path inside the session's own worktree (not its folder itself) does not count. A
        PowerShell array or a bash brace expansion is judged item by item."""
        return any(self._project_target(item, cwd, disposable, own_ok) for item in self.items(token))

    def _project_target(self, token: str, cwd: str | None, disposable: bool, own_ok: bool) -> bool:
        text = self.expand(token)
        if text is not None and OUTSIDE_ROOT_RE.match(text):
            return True
        path = self.resolve(token, cwd)
        if path is not None:
            return self.in_project(path, disposable) and not (own_ok and self.owned(path))
        if self.names_project(token) or self.computed(token):
            return True
        if self.shell != BASH:
            return False
        # No shell call keeps variables from an earlier one: a variable this command never assigns is empty, or comes
        # from the environment. Judge the empty value too: `rm -rf "$X"/*` is `rm -rf /*`.
        empty = self.resolve(token, cwd, empty=True)
        return empty is not None and self.in_project(empty, disposable) and not (own_ok and self.owned(empty))

    def computed(self, token: str) -> bool:
        """An unresolvable token built from a command's output (`$(realpath core)`, PowerShell `(Resolve-Path x)`)
        is in the project when the text before it is, or, when it starts the token, when that command names a path
        in the project (`$(mktemp -d)` names none)."""
        start = token.find("$(")
        if start == -1:
            return False
        prefix = token[:start]
        if prefix:
            path = self.resolve(prefix)
            return path is not None and self.in_project(path)
        inner = self.child()
        for segment in split(token[start + 2 : _closing_paren(token, start + 1)], self.shell):
            words, _ = _command_words(segment.words)
            if not words:
                continue
            verb = _verb(words[0])
            if verb in CD_VERBS or verb in ("popd", "pop-location"):
                inner.cd(verb, words[1:])
            elif inner.output_in_project(words, listing=False):
                return True
        return False

    def output_in_project(self, words: list[str], listing: bool = True) -> bool:
        """The paths a command prints are in the project: it names such a path (`realpath core`,
        `Join-Path $root x`), or prints the working directory there (`pwd`; with listing, also a listing that
        names no path: `Get-ChildItem`, `git ls-files`)."""
        return any(self.project_target(p) for p in self.output_paths(words, listing))

    def output_paths(self, words: list[str], listing: bool = True) -> list[str]:
        verb, args = _verb(words[0]), words[1:]
        if verb in CWD_VERBS:
            return ["."]
        if verb == "git":
            args = args[1:]
        if verb == "find":
            paths = _find_starts(args)
        elif verb == "join-path":
            positionals = _positionals(args, {"-path", "-childpath"})
            option = _option_values(args, {"-path"})
            base = option or positionals[:1]
            child = _option_values(args, {"-childpath"}) or (positionals if option else positionals[1:])[:1]
            paths = ["/".join(base[:1] + child[:1])] if base else []
        else:
            paths = _positionals(args, PATH_OPTIONS | VALUE_OPTIONS) + _option_values(args, PATH_OPTIONS)
        paths = [p for p in paths if not PIPE_ITEM_RE.match(p)]
        return paths or (["."] if listing or verb in LISTING_VERBS else [])

    def expand(self, token: str, empty: bool = False) -> str | None:
        """token with its variables replaced; None when one of them is unknown. With empty, a variable this command
        never assigned is the empty string (one it assigned from something unknown, like a loop, stays unknown).
        `$(git rev-parse --show-toplevel)` is the checkout that contains the working directory, when that is known."""
        unknown = False
        if (top := self.toplevel()) is not None:
            token = TOPLEVEL_SUB_RE.sub(lambda _: top, token)

        def value(match: re.Match[str]) -> str:
            nonlocal unknown
            name = next(group for group in match.groups() if group).lower()
            if (name == "pwd" or (name == "cd" and match.group(4))) and self.cwd:
                return self.cwd
            if name in self.vars and self.vars[name] is not None:
                return str(self.vars[name])
            if name in ("home", "userprofile") and self.home:
                return self.home
            if name in OUTSIDE_VARS:
                return OUTSIDE
            unknown = unknown or not (empty and name not in self.vars)
            return ""

        text = VAR_RE.sub(value, token)
        return None if unknown or "$" in text else text

    def resolve(self, token: str, cwd: str | None = "", empty: bool = False) -> str | None:
        """An absolute normalized path, OUTSIDE, or None when it cannot be known (see expand for empty)."""
        text = self.expand(token, empty)
        base = self.cwd if cwd == "" else cwd
        if text is None:
            return None
        if self.home and text.startswith("~") and (len(text) == 1 or text[1] in "/\\"):
            text = self.home + text[1:]
        if OUTSIDE in text or text.startswith("~") or re.match(r"^[a-z][a-z0-9+.-]+://", text, re.IGNORECASE):
            if not text.lower().startswith("res://"):
                return OUTSIDE
            text = f"{self.root}/{text[6:]}"
        if re.match(r"^([A-Za-z]:)?[\\/]|^[A-Za-z]:", text):
            return normalize(text)
        if base is None or base == OUTSIDE:
            return base
        return normalize(f"{base}/{text}")

    def area(self, token: str, cwd: str | None = "") -> str | None:
        """The protected area token writes to: inside this project only; by its text when it cannot be resolved. A
        PowerShell array or a bash brace expansion is judged item by item."""
        return next((a for a in (self._area(item, cwd) for item in self.items(token)) if a), None)

    def _area(self, token: str, cwd: str | None) -> str | None:
        path = self.resolve(token, cwd)
        if path is None:
            names = {next(g for g in m.groups() if g).lower() for m in VAR_RE.finditer(token)}
            tainted = next((self.tainted[n] for n in sorted(names) if n in self.tainted), None)
            return protected(token) or text_area(token) or tainted
        if path == OUTSIDE or not path.startswith(self.root + "/"):
            return None
        return project_area(path[len(self.root) + 1 :])

    def cd(self, verb: str, args: list[str]) -> None:
        """Move the working directory. `popd` with an empty stack, `cd -` with no earlier `cd` in this command, and
        a `cd` to a variable this command never assigned (empty at run time: `cd ""` stays) keep it."""
        where = (self.cwd, self.cwd_text, self.cwd_base)
        if verb in ("popd", "pop-location"):
            if self.stack:
                self.oldpwd = where
                self.cwd, self.cwd_text, self.cwd_base = self.stack.pop()
            return
        dest = _positionals(args, {"-path", "-literalpath"}) or _option_values(args, {"-path", "-literalpath"})
        if dest and dest[0] == "-":
            if self.oldpwd is not None:
                (self.cwd, self.cwd_text, self.cwd_base), self.oldpwd = self.oldpwd, where
            return
        if dest and self.shell == BASH and self.expand(dest[0]) is None and self.expand(dest[0], empty=True) == "":
            return
        if verb in ("pushd", "push-location"):
            self.stack.append(where)
        self.oldpwd = where
        if not dest:
            self.cwd = OUTSIDE if verb in ("cd", "chdir") else self.cwd  # bash `cd` alone goes home
        else:
            before = self.cwd
            text = self.expand(dest[0])
            if text is None and self.shell == BASH:
                text = self.expand(dest[0], empty=True)  # `cd "lab$S"` is `cd lab`
            self.cwd = self.resolve(text if text is not None else dest[0])
            if self.cwd is None and not re.match(ABSOLUTE_RE, dest[0]):
                # An unresolvable relative `cd` stays under the directory it started from: `cd "lab$S"` in the
                # project is in the project.
                self.cwd_base = before if before is not None else self.cwd_base
                self.cwd_text = f"{self.cwd_text}/{dest[0]}" if before is None and self.cwd_text else dest[0]
            elif self.cwd is None:
                self.cwd_base, self.cwd_text = "", dest[0]
        if self.cwd is not None:
            self.cwd_text, self.cwd_base = "", ""
        self.claim_worktree(self.cwd)

    def remember(self, name: str, value: str | None, words: list[str], kind: str = "value") -> None:
        """Record a variable. A value this cannot compute still counts as protected when its words name a protected
        path, and as the project when it is in it: kind "value" (bash `S=$(realpath core)`), "command" (PowerShell
        `$d = Resolve-Path core`, `$p = Join-Path $root addons`) or "loop" (a `for` loop over `core/*`)."""
        name = name.lower()
        if name == "null":
            return
        self.vars[name] = self.expand(value) if value is not None else None
        area = None
        self.project_vars.discard(name)
        if self.vars[name] is None:
            area = next((a for a in (protected(w) or text_area(w) for w in words) if a), None)
            if not words:
                hit = False  # `$out = & $g ...`: the call is a command of its own
            elif kind == "value" and value is not None:
                hit = self.project_target(value)
            elif kind == "loop" and not (self.shell == POWERSHELL and CMDLET_RE.match(words[0])):
                hit = any(self.project_target(w) for w in words)
            elif len(words) == 1 and not CMDLET_RE.match(words[0]):
                hit = self.project_target(words[0])
            elif re.match(r"^[\w.\\/-]+$", words[0]) and not words[0].startswith("$"):
                hit = self.output_in_project(words, listing=False)  # a command: `Resolve-Path core`
            else:
                hit = any(self.names_project(w) or self.computed(w) for w in words)  # an expression
            if hit:
                self.project_vars.add(name)
        if area:
            self.tainted[name] = area
        else:
            self.tainted.pop(name, None)

    def assign(self, words: list[str]) -> list[str] | None:
        """Record `S=value`, `export S=value`, PowerShell `$S = value` or a `for S in ...` loop. Returns None when
        words are not one of those, else the words of a command still to check (`$null = New-Item addons\\x`)."""
        if words[0] == "export" and len(words) == 2:
            words = words[1:]
        if len(words) == 1 and (match := ASSIGN_RE.match(words[0])):
            self.remember(match.group(1), match.group(2), words)
            return []
        if len(words) >= 2 and words[1] == "=" and (var := PS_VAR_RE.match(words[0])):
            simple = len(words) == 3 and not words[2].startswith(("$(", "[")) and not CMDLET_RE.match(words[2])
            self.remember(var.group(1), words[2] if simple else None, words[2:], kind="command")
            return [] if simple else words[2:]
        loop = words[1:] if words[0].lower() in ("for", "foreach") else words
        if len(loop) >= 3 and loop[1].lower() == "in" and (m := re.match(r"^\$?([A-Za-z_]\w*)$", loop[0])):
            self.remember(m.group(1), None, loop[2:], kind="loop")
            return []
        return None


# --- lexing both shells ---------------------------------------------------------------------------------------------


class Segment:
    """One simple command: its words, output redirect targets, the code of its `$(...)`/`(...)` arguments, the bodies
    of its heredocs, and the pipeline it belongs to. (Plain classes, not dataclasses: this module runs before every
    shell command, and that import costs.)"""

    def __init__(self, pipeline: int = 0, after_pipe: bool = False) -> None:
        self.words: list[str] = []
        self.redirects: list[str] = []
        self.subs: list[str] = []
        self.heredocs: list[str] = []
        self.pipeline = pipeline
        self.after_pipe = after_pipe
        # "(" or ")" for a bash subshell boundary, which has no words: a `cd` inside does not leave it.
        self.scope = ""


HEREDOC_RE = re.compile(r"""\s*(['"]?)([A-Za-z0-9_.-]+)\1""")


def _closing_paren(command: str, start: int) -> int:
    """Index of the `)` that closes the `(` at start (quotes skipped), or len(command)."""
    depth, i, n = 0, start, len(command)
    while i < n:
        c = command[i]
        if c in "'\"":
            end = command.find(c, i + 1)
            i = (end if end != -1 else n) + 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def _lex(command: str, shell: str) -> list[tuple[str, str]]:
    """Tokens as (kind, text). Kinds: word; op (a separator); redir (an output target follows); skip (the next word
    is data: an input redirect or a here-string); sub (the code of a `$(...)`, or of a PowerShell `(...)` argument,
    which also stays in its word as `$(...)`); heredoc (a heredoc body). Quotes are removed with each shell's escape
    character: backslash in bash, backtick in PowerShell, where a backslash is a path separator."""
    escape = "\\" if shell == BASH else "`"
    tokens: list[tuple[str, str]] = []
    word: list[str] = []
    has_word = False
    heredocs: list[tuple[str, bool]] = []
    i, n = 0, len(command)

    def flush() -> None:
        nonlocal word, has_word
        if has_word:
            tokens.append(("word", "".join(word)))
        word, has_word = [], False

    def op(text: str, width: int) -> None:
        nonlocal i
        flush()
        tokens.append(("op", text))
        i += width

    def group(start: int) -> None:
        """A `(...)` at start becomes part of the current word and a sub token."""
        nonlocal i, has_word
        end = _closing_paren(command, start)
        inner = command[start + 1 : end]
        tokens.append(("sub", inner))
        word.append(f"$({inner})")
        has_word = True
        i = end + 1

    while i < n:
        c = command[i]
        nxt = command[i + 1] if i + 1 < n else ""
        after_word = has_word or (bool(tokens) and tokens[-1][0] == "word")
        if c == "\n":
            flush()
            for delimiter, strip_tabs in heredocs:  # heredoc bodies are data of the line that opened them
                body: list[str] = []
                i += 1
                while i < n:
                    end = command.find("\n", i)
                    line = command[i : end if end != -1 else n].rstrip("\r")
                    if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                        i = end if end != -1 else n
                        break
                    body.append(line)
                    i = end + 1 if end != -1 else n
                tokens.append(("heredoc", "\n".join(body)))
            heredocs = []
            tokens.append(("op", "\n"))
            i += 1
        elif c in " \t\r":
            flush()
            i += 1
        elif c == escape and nxt == "\n":  # line continuation
            i += 2
        elif c == escape and nxt:
            word.append(nxt)
            has_word = True
            i += 2
        elif c == "#" and not has_word:
            end = command.find("\n", i)
            i = end if end != -1 else n
        elif shell == POWERSHELL and command.startswith("<#", i):
            end = command.find("#>", i + 2)
            i = end + 2 if end != -1 else n
        elif c == "@" and not has_word and nxt and nxt in "'\"" and command[i + 2 : i + 3] in ("\n", "\r"):
            closing = re.compile(r"\r?\n" + re.escape(nxt) + "@").search(command, i + 2)
            word.append(command[i + 2 : closing.start() if closing else n])
            has_word = True
            i = closing.end() if closing else n
        elif c == "'":
            end = command.find("'", i + 1)
            end = end if end != -1 else n
            word.append(command[i + 1 : end])
            has_word = True
            i = end + 1
        elif c == '"':
            j = i + 1
            while j < n and command[j] != '"':
                if command[j] == "$" and command[j + 1 : j + 2] == "(":
                    tokens.append(("sub", command[j + 2 : _closing_paren(command, j + 1)]))
                j += 2 if command[j] == escape and j + 1 < n else 1
            word.append(command[i + 1 : j])
            has_word = True
            i = j + 1
        elif c == "$" and nxt == "(":
            group(i + 1)
        elif c == "(" and shell == POWERSHELL and after_word:
            group(i)
        elif c == "`":  # bash command substitution (the PowerShell backtick is its escape, handled above)
            op("`", 1)
        elif c in ";()":
            op(c, 1)
        elif c in "{}":
            # A brace is a separator only as a word of its own: `{}`, `${x}` and `a{b,c}` are words.
            standalone = not has_word and (c == "}" or nxt in ("", " ", "\t", "\n", "\r") or shell == POWERSHELL)
            if standalone and not (c == "{" and nxt == "}"):
                op(c, 1)
            else:
                word.append(c)
                has_word = True
                i += 1
        elif c == "|":
            op("||" if nxt == "|" else "|", 2 if nxt == "|" else 1)
        elif c == "&" and nxt == "&":
            op("&&", 2)
        elif c == "&" and nxt == ">":  # bash &> file
            flush()
            tokens.append(("redir", ""))
            i += 3 if command[i + 2 : i + 3] == ">" else 2
        elif c == "&":
            op("&", 1)
        elif c == ">" or (c in "0123456789*" and not has_word and nxt == ">"):
            flush()
            j = i + (1 if c == ">" else 2)
            if command[j : j + 1] == ">":
                j += 1
            if command[j : j + 1] in ("|", "!"):
                j += 1
            if command[j : j + 1] == "&":  # 2>&1, >&2: a file descriptor, not a file
                j += 1
                while j < n and (command[j].isdigit() or command[j] == "-"):
                    j += 1
            else:
                tokens.append(("redir", ""))
            i = j
        elif c == "<" and not has_word and shell == BASH:
            flush()
            if command.startswith("<<<", i):
                tokens.append(("skip", ""))
                i += 3
            elif command.startswith("<<", i):
                j = i + 2
                strip_tabs = command[j : j + 1] == "-"
                j += 1 if strip_tabs else 0
                match = HEREDOC_RE.match(command, j)
                if match:
                    heredocs.append((match.group(2), strip_tabs))
                    j = match.end()
                i = j
            else:
                tokens.append(("skip", ""))
                i += 1
        else:
            word.append(c)
            has_word = True
            i += 1
    flush()
    return tokens


def split(command: str, shell: str = BASH) -> list[Segment]:
    """Simple commands in order. `;`, newlines, `&&`, `||` and `&` start a new pipeline; `|` continues one."""
    segments: list[Segment] = []
    pipeline, piped = 0, False
    current = Segment()
    pending = ""

    def close() -> None:
        if current.words or current.redirects or current.subs or current.heredocs:
            segments.append(current)

    for kind, text in _lex(command, shell):
        if kind == "op":
            close()
            if text == "|":
                piped = True
            elif text not in ("(", ")", "{", "}", "`"):
                pipeline, piped = pipeline + 1, False
            if text in ("(", ")") and shell == BASH:
                segments.append(Segment(pipeline=pipeline))
                segments[-1].scope = text
            current = Segment(pipeline=pipeline, after_pipe=piped)
            pending = ""
        elif kind == "sub":
            current.subs.append(text)
        elif kind == "heredoc":
            last = next((s for s in reversed(segments) if not s.scope), None)
            (last if not (current.words or current.redirects) and last else current).heredocs.append(text)
        elif kind in ("redir", "skip"):
            pending = kind
        elif pending == "redir":
            current.redirects.append(text)
            pending = ""
        elif pending == "skip":
            pending = ""
        else:
            current.words.append(text)
    close()
    return segments


# --- analysis ---------------------------------------------------------------------------------------------------------


def _verb(word: str) -> str:
    name = word.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return re.sub(r"\.(exe|cmd|bat|com)$", "", name)


def _command_words(words: list[str], assignments: list[str] | None = None) -> tuple[list[str], bool]:
    """Words from the real command on (leading VAR=value assignments and prefixes such as sudo, xargs or `then`
    removed), and whether xargs feeds it. The skipped `VAR=value` words, including those after a prefix
    (`env GH_REPO=o/r gh ...`), are the command's own environment: they go to `assignments` when it is given."""
    i, via_xargs = 0, False
    while i < len(words):
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[i]):
            if assignments is not None:
                assignments.append(words[i])
            i += 1
        elif _verb(words[i]) in PREFIXES:
            prefix = _verb(words[i])
            via_xargs = via_xargs or prefix == "xargs"
            valued = PREFIX_VALUED.get(prefix, set())
            i += 1
            while i < len(words) and (words[i].startswith("-") or words[i] == "{}"):
                i += 2 if words[i] in valued else 1
            if prefix in PREFIX_DURATION and i < len(words) and re.match(r"^\d", words[i]):
                i += 1
        else:
            break
    return words[i:], via_xargs


def gh_repo_name(spec: str) -> str | None:
    """`owner/name` (lower-case) of a github.com repository as gh takes it: `owner/name`, `github.com/owner/name`,
    or a URL of the repository or of something in it; None for another host or text that names no repository."""
    url = GH_URL_RE.match(spec)
    if url:
        owner, name = url.group(1) or url.group(3), url.group(2) or url.group(4)
        return f"{owner}/{name.removesuffix('.git')}".lower()
    match = GH_REPO_RE.match(spec)
    if match and (match.group(1) or "github.com").lower() in ("github.com", "www.github.com"):
        return f"{match.group(2)}/{match.group(3)}".lower()
    return None


def _option_values(args: list[str], names: set[str]) -> list[str]:
    """Values of the named options, as `-o value`, `--opt=value` or PowerShell `-Opt:value`."""
    values = []
    for index, arg in enumerate(args):
        low = arg.lower()
        name, sep, _ = low.partition("=") if low.startswith("--") else low.partition(":")
        if name in names:
            if sep:
                values.append(arg[len(name) + 1 :])
            elif index + 1 < len(args):
                values.append(args[index + 1])
    return values


def _rebase_options(args: list[str]) -> tuple[list[str], list[str]]:
    """The options of a `git rebase` in order, as long names (`-qi` gives `-q`, `--interactive`; `--exe=x` gives
    `--exec`), and its positional arguments (the values of valued options left out)."""
    options: list[str] = []
    positionals: list[str] = []
    i = 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            positionals += args[i:]
            break
        if arg.startswith("--"):
            name, eq, _ = arg.partition("=")
            matches = [o for o in REBASE_LONG if o.startswith(name)]
            name = name if name in REBASE_LONG or len(matches) != 1 else matches[0]  # an ambiguous prefix fails
            options.append(name)
            i += 1 if not eq and name in REBASE_LONG_VALUED else 0
        elif arg.startswith("-") and len(arg) > 1:
            for at, letter in enumerate(arg[1:], 2):
                options.append(REBASE_SHORT.get(letter, "-" + letter))
                if letter in REBASE_SHORT_VALUED:
                    i += 1 if at == len(arg) else 0
                    break
        else:
            positionals.append(arg)
    return options, positionals


def _long_prefix(arg: str, option: str) -> bool:
    """arg is option or a unique prefix git accepts for it (`--fo` for `--force`), with or without `=value`."""
    name = arg.split("=", 1)[0]
    return len(name) > 3 and option.startswith(name)


def _clean_options(args: list[str]) -> tuple[str, list[str]]:
    """The short option letters and long option names of `git clean`, read as git reads them: `-e` takes the rest of
    its cluster or the next word as its value (`-en` is `-e n`, no dry run)."""
    letters, longs, i = "", [], 0
    while i < len(args) and args[i] != "--":
        arg = args[i]
        if arg.startswith("--"):
            longs.append(arg)
            if "=" not in arg and _long_prefix(arg, "--exclude"):
                i += 1
        elif arg.startswith("-") and len(arg) > 1:
            head, e, value = arg[1:].partition("e")
            letters += head + e
            if e and not value:
                i += 1
        i += 1
    return letters, longs


def _positionals(args: list[str], valued: set[str] | None = None) -> list[str]:
    """Arguments that are not options, nor the values of the options in valued."""
    result, skip = [], False
    for arg in args:
        if skip:
            skip = False
        elif arg.startswith("-") and len(arg) > 1:
            skip = arg.lower() in (valued or set())
        else:
            result.append(arg)
    return result


def _recursive(verb: str, args: list[str], shell: str = BASH) -> bool:
    """A delete is recursive: bash `rm -r|-R|-rf|--recursive` (or `--rec`), PowerShell `-Recurse` or any prefix of it (`-r`,
    `-rec`; in PowerShell `rm` is Remove-Item, so `rm -Force` is not), cmd.exe `rmdir /s`, `rd /s/q`, `del /s` (`//s` from Git Bash)."""
    for arg in args:
        low = arg.lower()
        if low == "--":
            return False
        name, _, value = low.partition(":")
        if (low.startswith("--r") and "--recursive".startswith(low)) or (
            verb == "rm" and shell == BASH and re.fullmatch(r"-[a-z]*r[a-z]*", low)
        ):
            return True
        if len(name) >= 2 and "-recurse".startswith(name) and value not in ("$false", "0"):
            return True
        if verb in CMD_DELETE_VERBS and CMD_SWITCH_RE.match(low) and "/s" in re.findall(r"/[a-z?]", low):
            return True
    return False


def _find_filtered(args: list[str]) -> bool:
    """`find` has a filter that narrows what it matches. `-name '*'` narrows nothing, and neither does a filter
    before `-prune -o` (`find . -path ./x -prune -o -delete` deletes everything else)."""
    lows = [a.lower() for a in args]
    start = max((i for i, a in enumerate(lows) if a == "-prune"), default=-1) + 1
    return any(
        low in FIND_FILTERS and not (index + 1 < len(args) and args[index + 1] == "*")
        for index, low in enumerate(lows)
        if index >= start
    )


def _find_starts(args: list[str]) -> list[str]:
    """The start paths of `find`: its arguments before the first option or expression."""
    end = next((i for i, a in enumerate(args) if a.startswith(("-", "(", "!"))), len(args))
    return args[:end]


def _recursive_listing(words: list[str] | None, shell: str) -> bool:
    """A pipeline that starts with a recursive listing (`Get-ChildItem core -Recurse`, `ls -R`, an unfiltered
    `find`) makes a plain delete at its end recursive: `Get-ChildItem core -Recurse | Remove-Item`."""
    if not words:
        return False
    verb, args = _verb(words[0]), words[1:]
    if verb == "find":
        return not _find_filtered(args)
    if verb not in ("ls", "dir", "get-childitem", "gci"):
        return False
    if any(v != "*" for v in _option_values(args, {"-filter", "-include"})):
        return False  # `Get-ChildItem -Recurse -Filter *.tmp | Remove-Item` is a targeted cleanup
    if shell == BASH:
        return any(a == "--recursive" or re.fullmatch(r"-[a-zA-Z]*R[a-zA-Z]*", a) for a in args)
    return _recursive("remove-item", args, POWERSHELL)


def _win32_filter(text: str) -> str | None:
    """A glob that matches at least what a PowerShell `-Filter` matches (issue #464), or None when the guard cannot
    tell. A filter matches the way Win32 FindFirstFile does, not fnmatch: `x.*` and `x.` also match `x` (so `*.*`
    matches every name), a `?` before a dot or at the end also matches nothing, and `[` is a literal. The 8.3 short
    names a filter also matches (`CLAUDE~1`) are not listed, so a filter with `~` is unknown."""
    if not text or "~" in text:
        return None
    text = text.replace("[", "[[]").replace("?", "*")
    if text.endswith(".*"):
        text = text[:-2] + "*"
    elif text.endswith("."):
        text = text[:-1] + "*"
    return text


def _scratchpad_holder(parts: list[str]) -> bool:
    """A path in the temp folder, as its parts, is or may match (as a glob) a Claude scratchpad root
    (`claude/<project>/<session>/scratchpad`) or a folder that holds one (issue #464)."""
    if len(parts) > len(SCRATCHPAD_PARTS):
        return False
    return all(
        fnmatch.fnmatchcase(name, part.lower()) or fnmatch.fnmatchcase(part.lower(), name)
        for part, name in zip(parts, SCRATCHPAD_PARTS, strict=False)
    )


def _find_deletes_all(args: list[str]) -> bool:
    """`find` deletes everything under its start paths: `-delete`, or `-exec rm -rf {}`, with no name or path
    filter (`find . -name '*.orig' -delete` is a targeted cleanup)."""
    lows = [a.lower() for a in args]
    if _find_filtered(args):
        return False
    if "-delete" in lows:
        return True
    for index, low in enumerate(lows):
        if low in ("-exec", "-execdir", "-ok", "-okdir") and index + 1 < len(args):
            verb = _verb(args[index + 1])
            if verb in DELETE_VERBS and (verb == "rmdir" or _recursive(verb, args[index + 2 :])):
                return True
    return False


class Finding:
    def __init__(self, path: str, area: str, verb: str) -> None:
        self.path, self.area, self.verb = path, area, verb

    def __repr__(self) -> str:
        return f"Finding({self.verb} -> {self.path}: {self.area})"


class Analysis:
    def __init__(self, paths: Paths, repo: NoRepo | None = None, cloud: bool = False) -> None:
        self.paths = paths
        self.repo = repo or NoRepo()
        self.paths.busy = self.repo.busy
        # A cloud session in no worktree owns the main checkout while its task branch is checked out there (#381).
        main = self.repo.branch(paths.root) if cloud and paths.own is None else None
        if main and TASK_BRANCH_RE.match(main):
            paths.own, paths.claim, paths.task = paths.root, False, main.lower()
        self.findings: list[Finding] = []
        self.piped_first: dict[int, list[str]] = {}
        # The `VAR=value` prefixes of the simple command being judged (`GIT_DIR=x git reset`).
        self.prefix_env: dict[str, str] = {}
        # The `-c name=value` and `--config-env` settings of the git command being judged.
        self.git_configs: list[str] = []

    def add(self, path: str, verb: str, cwd: str | None = "") -> None:
        area = self.paths.area(path, cwd)
        if area:
            self.findings.append(Finding(path, area, verb))

    def code(self, text: str, verb: str) -> None:
        """Inline interpreter code: a line that uses a file-writing API and names a protected path."""
        for line in text.splitlines():
            if WRITE_API_RE.search(line) and (area := text_area(line)):
                self.findings.append(Finding(line.strip()[:80], area, verb))

    def command(self, command: str, shell: str, depth: int = 0) -> None:
        self.paths.shell = shell
        mentioned: dict[int, bool] = {}
        piped_words: dict[int, list[str]] = {}
        # The command that starts each pipeline: where the paths a later `Remove-Item` or `xargs rm` gets come from.
        piped_first: dict[int, list[str]] = {}
        # The state before each open bash subshell `( ... )`, restored at its `)`.
        scopes: list[tuple] = []
        for segment in split(command, shell):
            if segment.scope == "(":
                scopes.append(self.paths.save())
                continue
            if segment.scope == ")":
                if scopes:
                    self.paths.restore(scopes.pop())
                continue
            for target in segment.redirects:
                self.add(target, ">")
            for sub in segment.subs:
                if depth < 3:
                    # A bash `$(...)` is a subshell; a PowerShell `$(...)` or `(...)` runs in the same session.
                    saved = self.paths.save() if shell == BASH else None
                    self.command(sub, shell, depth + 1)
                    if saved is not None:
                        self.paths.restore(saved)
            words = segment.words
            if words:
                rest = self.paths.assign(words)
                words = words if rest is None else rest
            assignments: list[str] = []
            words, via_xargs = _command_words(words, assignments)
            self.prefix_env = (
                {m.group(1).lower(): m.group(2) for m in map(ASSIGN_RE.match, assignments) if m} if words else {}
            )
            if words:
                self.piped_first = piped_first  # set here: the `$(...)` analysed above had their own
                self.simple(segment, words, via_xargs, mentioned, piped_words, depth)
                if not segment.after_pipe:
                    piped_first.setdefault(segment.pipeline, words)
            piped_words.setdefault(segment.pipeline, []).extend(segment.words)

    def simple(
        self,
        segment: Segment,
        words: list[str],
        via_xargs: bool,
        mentioned: dict[int, bool],
        piped_words: dict[int, list[str]],
        depth: int,
    ) -> None:
        verb, args = _verb(words[0]), words[1:]
        if verb in CD_VERBS or verb in ("popd", "pop-location"):
            self.paths.cd(verb, args)
            return
        if verb == "git":
            self.git(args)
        else:
            for path in self.targets(verb, args, depth):
                self.add(path, words[0])
        if verb == "gh":
            self.gh(args)
        if verb in DELETE_VERBS:
            first = self.piped_first.get(segment.pipeline) if segment.after_pipe else None
            recursive = _recursive(verb, args, self.paths.shell) or _recursive_listing(first, self.paths.shell)
            if recursive:
                fed = segment.after_pipe or via_xargs
                self.recursive_delete(words[0], args, (first or []) if fed else None)
        if verb == "find" and _find_deletes_all(args):
            for start in _find_starts(args) or ["."]:
                if self.paths.project_target(start, own_ok=True):
                    self.findings.append(Finding(start, DELETE, words[0]))
        if INTERPRETER_RE.search(verb) or DOTNET_WRITE_RE.search(words[0]):
            for match in CODE_DELETE_RE.finditer("\n".join(words + segment.heredocs)):
                target = match.group(1) or match.group(2)
                if self.paths.project_target(target, own_ok=True):
                    self.findings.append(Finding(target, DELETE, words[0]))
        joined = " ".join(words)
        if DOTNET_WRITE_RE.search(words[0]) or (verb == "new-object" and DOTNET_WRITE_RE.search(joined)):
            area = text_area(joined) or next((a for a in map(self.paths.area, args) if a), None)
            if area:
                self.findings.append(Finding(joined[:80], area, ".NET write"))
        if INTERPRETER_RE.search(verb):
            fed = piped_words.get(segment.pipeline, []) if segment.after_pipe else []
            self.code("\n".join(args + segment.heredocs + fed), words[0])
        if segment.after_pipe and mentioned.get(segment.pipeline):
            first = _positionals(args, PATH_OPTIONS | DESTINATION_OPTIONS | VALUE_OPTIONS)[:1]
            if verb in PIPED_PATH_VERBS and all(PIPE_ITEM_RE.match(p) for p in first):
                self.findings.append(Finding("(paths from the pipeline)", "piped", words[0]))
            elif via_xargs and (verb in WRITE_VERBS or (verb in IN_PLACE_VERBS and self.targets(verb, args, depth))):
                self.findings.append(Finding("(paths from xargs)", "piped", words[0]))
        names_protected = any(self.paths.area(arg) for arg in args)
        mentioned[segment.pipeline] = mentioned.get(segment.pipeline, False) or names_protected

    def recursive_delete(self, verb: str, args: list[str], fed: list[str] | None) -> None:
        """A recursive delete asks when a target is in the project. Targets from a pipeline or xargs (`$_`, `{}`,
        none) are the paths the command that starts the pipeline names, or the working directory."""
        cmd = _verb(verb) in CMD_DELETE_VERBS
        targets = [
            a
            for a in _positionals(args, PATH_OPTIONS | VALUE_OPTIONS) + _option_values(args, PATH_OPTIONS)
            if not (cmd and CMD_SWITCH_RE.match(a))
        ]
        filtered: set[str] = set()
        if fed is not None and all(PIPE_ITEM_RE.match(t) for t in targets):
            listed = self.paths.output_paths(fed) if fed else []
            targets = self.filtered_listing(fed, listed) if fed else ["."]
            filtered = set(targets) - set(listed)
        for target in targets:
            if self.paths.project_target(target, own_ok=True):
                self.findings.append(Finding(target, DELETE, verb))
            elif self.temp_glob_reaches(target, target in filtered):
                self.findings.append(Finding(target, TEMP_DELETE, verb))

    def filtered_listing(self, words: list[str], paths: list[str]) -> list[str]:
        """The paths a listing piped to a delete hands on: a PowerShell `Get-ChildItem <temp folder> -Filter x` that
        does not recurse hands on what `<temp folder>/x` matches, not the folder (issue #464), as the glob
        _win32_filter makes of x. Other listings and folders, and a filter the guard cannot read, are judged by their
        paths, as before (the temp folder itself asks)."""
        verb, args = _verb(words[0]), words[1:]
        if self.paths.shell != POWERSHELL or verb not in ("get-childitem", "gci", "ls", "dir"):
            return paths
        filters = _option_values(args, {"-filter"})
        if len(filters) != 1 or filters[0] in ("*", "") or _recursive("remove-item", args, POWERSHELL):
            return paths
        if any(a.lower().partition(":")[0] == "-depth" for a in args):
            return paths
        text = self.paths.expand(filters[0])
        pattern = _win32_filter(text) if text is not None and OUTSIDE not in text else None
        if pattern is None:
            return paths
        joined = [f"{p}/{pattern}" for p in paths]
        return [j if TEMP_TARGET_RE.match(j) else p for p, j in zip(paths, joined, strict=True)]

    def temp_glob_reaches(self, token: str, filtered: bool = False) -> bool:
        """A delete target that is a glob in the temp folder (`$TEMP/rmtree-*`, `$env:TEMP/x*`) may reach what no
        one meant (issue #464): a match outside the temp folder (`..`), a Claude scratchpad root or a folder that
        holds one (`claude/<project>/<session>/scratchpad`, by the pattern and by its matches), a worktree (by its
        matches, when the repository reader lists the folder), or what the guard cannot tell (an unknown variable).
        A literal path in the temp folder is judged as before (it passes), but not one a `-Filter` made (filtered):
        `Get-ChildItem $env:TEMP -Filter claude` names what it matches too."""
        for item in self.paths.items(token):
            match = TEMP_TARGET_RE.match(item)
            name = match and (match.group(1) or match.group(2) or match.group(3) or "").lower()
            if not match or (name and name in self.paths.vars):
                continue  # not the temp folder, or a variable the command set itself
            text = self.paths.expand(match.group(4), empty=self.paths.shell == BASH)
            if text is None or OUTSIDE in text:
                if GLOB_RE.search(match.group(4)):
                    return True
                continue
            if not filtered and not GLOB_RE.search(text):
                continue
            # Bash negates a class with `[^...]` as well as `[!...]`; fnmatch and glob take only `[!...]`.
            parts = [p.replace("[^", "[!") for p in text.replace("\\", "/").split("/") if p not in ("", ".")]
            if not parts or ".." in parts or _scratchpad_holder(parts):
                return True
            matches = self.repo.temp_matches("/".join(parts))
            if matches and any(worktree or _scratchpad_holder(path.split("/")) for path, worktree in matches):
                return True
        return False

    # --- git: free in the own worktree and task branch, asks elsewhere (issue #51) ------------------------------------

    def git(self, args: list[str]) -> None:
        """Judge a git command by where it acts (docs/AGENT_WORKFLOW.md §8.2). Commands that discard work or rewrite
        history pass in the session's own worktree on its task branch and in scratch repositories outside the
        project; they ask in the main checkout (but a cloud session's on its task branch, issue #381), in another
        worktree, and on another branch. Writes to the protected paths ask everywhere."""
        i, dirs, git_dir, work_tree, configs = 0, [], "", "", []
        while i < len(args) and args[i].startswith("-"):
            name, eq, value = args[i].partition("=")
            step = 1
            if not eq and args[i] in GIT_VALUED and i + 1 < len(args):
                value, step = args[i + 1], 2
            if name == "-C" and value:
                dirs.append(value)
            elif name == "--git-dir":
                git_dir = value
            elif name == "--work-tree":
                work_tree = value
            elif name == "-c":
                configs.append(value)
            elif name == "--config-env":
                configs.append(value.partition("=")[0] + "=?")  # the value comes from the environment
            i += step
        self.git_configs = configs
        if any("hookspath" in c.lower() for c in configs):
            # The deny rule on `git config *hooksPath*` cannot see `git -c core.hooksPath=... push`.
            self.git_finding(["git", *args], "sets core.hooksPath, which skips the pre-push hook")
        if i >= len(args):
            return
        sub, rest = args[i].lower(), args[i + 1 :]
        git_dir, work_tree = git_dir or self.git_env("git_dir"), work_tree or self.git_env("git_work_tree")
        place, base = self.git_repo(dirs, git_dir, work_tree)
        judge = GIT_JUDGES.get(sub)
        if judge and place != OUTSIDE_PROJECT:  # a scratch repository (a clone in the scratchpad) is free
            judge(self, rest, place, base)
        if sub not in GIT_WRITES or (GIT_INDEX_ONLY & {a.lower() for a in rest} and "--worktree" not in rest):
            return
        for path in rest:
            if not path.startswith("-"):
                self.add(path, f"git {sub}", base)

    def git_repo(self, dirs: list[str], git_dir: str, work_tree: str) -> tuple[str, str | None]:
        """Where the repository of a git command is (OWN, OUTSIDE_PROJECT or ELSEWHERE), and the directory its
        pathspecs start from ("" for the working directory, None when unknown). `-C` moves (and, from the main
        checkout, claims a worktree like `cd`); `--work-tree` and `--git-dir` name the checkout."""
        base: str | None = ""
        for folder in dirs:
            resolved = self.paths.resolve(folder, base)
            if resolved is None:
                return self.paths.where(folder, base), None
            base = resolved
            self.paths.claim_worktree(resolved)
        # The repository and the working tree are judged apart and the worse place wins: `--git-dir=<main>/.git
        # --work-tree=.` from the own worktree moves main. Without --work-tree the working tree is the directory.
        places = [self.paths.where(work_tree, base) if work_tree else self.paths.where(".", base)]
        if git_dir:
            path = self.paths.resolve(git_dir, base)
            if path is None:
                places.append(self.paths.where(git_dir, base))
            else:
                root = self.paths.root
                admin = re.match(rf"^{re.escape(root)}/\.git/worktrees/([^/]+)$", path)
                checkout = f"{root}/.claude/worktrees/{admin.group(1)}" if admin else path.removesuffix("/.git")
                places.append(self.paths.place(checkout))
        return next(p for p in (ELSEWHERE, OWN, OUTSIDE_PROJECT) if p in places or p == OUTSIDE_PROJECT), base

    def git_env(self, name: str) -> str:
        """GIT_DIR or GIT_WORK_TREE as the command sets it: a `VAR=value` prefix, or `export` / `$env:` earlier in
        the command. A value the guard cannot compute counts as the main checkout's: the worst case."""
        if name in self.prefix_env:
            return self.prefix_env[name] or "."
        if name in self.paths.vars:
            value = self.paths.vars[name]
            return value if value is not None else self.paths.root
        return ""

    def git_finding(self, words: list[str], why: str) -> None:
        self.findings.append(Finding(" ".join(words)[:100], GIT, why))

    def task_branch(self) -> str | None:
        """The own worktree's task branch: the branch checked out there, when it is `<area>/<n>-<slug>` for the
        worktree `.claude/worktrees/<n>` (start.py names both). Another branch checked out there (a parent, a spike)
        is not the task's, whatever a checkout in an earlier call did."""
        if not self.paths.own:
            return None
        current = self.repo.branch(self.paths.own)
        return current.lower() if current and self.task_name(current) else None

    def task_name(self, name: str) -> bool:
        """name has the form of the own task's branches: `<area>/<n>-...` for the own worktree `<n>`, or for the
        task branch a cloud session's main checkout was on when the command started."""
        if not self.paths.own:
            return False
        if self.paths.own == self.paths.root:
            number = re.escape(self.paths.task.split("/", 1)[1].split("-", 1)[0])
        else:
            number = re.escape(self.paths.own.rsplit("/", 1)[-1])
        return bool(re.match(rf"^[^/]+/{number}-", name.lower().removeprefix("refs/heads/")))

    def own_branch(self, name: str) -> bool:
        """name is the task branch of the own worktree, one of its helpers (`<task branch>-backup`), or the task
        branch a helper checked out there was made from."""
        task = self.task_branch()
        if not task or not self.task_name(name):
            return False
        name = name.lower().removeprefix("refs/heads/")
        pairs = ((name, task), (task, name))
        return name == task or any(a.startswith(b + s) for a, b in pairs for s in HELPER_SEPARATORS)

    def is_revision(self, word: str) -> bool:
        """A `git checkout` argument names a commit, not a path."""
        low = word.lower()
        return word == "-" or low == "head" or bool(REVISION_RE.search(word)) or low in self.repo.refs()

    def git_discards(self, shown: list[str], place: str, base: str | None, pathspecs: list[str] | None = None) -> None:
        """A command that discards work or rewrites history: silent in the own worktree on its task branch, and in a
        repository outside the project."""
        current = self.repo.branch(self.paths.own) if place == OWN and self.paths.own else None
        if place == ELSEWHERE:
            self.git_finding(shown, "outside this session's own worktree")
        elif place == OWN and self.paths.off_branch:
            self.git_finding(shown, "after this command left the task branch")
        elif current and not self.own_branch(current):
            # A detached HEAD (no current branch) stays free: no branch moves.
            self.git_finding(shown, f"on another branch ({current}) checked out in the own worktree")
        elif place == OWN and base is not None:
            # A pathspec the guard cannot resolve (`core/$f.gd` in a loop, `$(git diff --name-only)`) is judged by
            # its literal part (issue #457): git refuses one outside its repository. Not in a cloud session's main
            # checkout, whose working tree holds `.git`, `.claude` and the other worktrees.
            literal = self.paths.own != self.paths.root
            for spec in pathspecs or []:
                if spec.startswith(":") and not literal and spec != ":":
                    # A magic pathspec (`:(top).claude/worktrees`) may name the shared parts of a cloud checkout.
                    self.git_finding(shown, f"its path {spec} may reach the shared parts of the main checkout")
                    return
                if not spec.startswith((":", "-")) and self.paths.where(spec, base, literal) == ELSEWHERE:
                    self.git_finding(shown, f"its path {spec} is outside this session's own worktree")
                    return

    def git_move(self, shown: list[str], target: str, force: bool, place: str, base: str | None) -> None:
        """A checkout or switch to target. Without force it discards nothing and passes; with force it discards the
        changes of that checkout, and asks when target is not the task branch or a helper."""
        own = self.own_branch(target)
        if force and not own and place != OUTSIDE_PROJECT:
            self.git_finding(shown, f"discards changes to switch to another branch ({target})")
        elif force:
            self.git_discards(shown, place, base)
        if place == OWN:
            self.paths.off_branch = not own

    def git_other_branches(self, shown: list[str], names: list[str], what: str) -> bool:
        """Ask when a command changes a branch other than the task branch and its helpers."""
        others = [n for n in names if not self.own_branch(n)]
        if others:
            self.git_finding(shown, f"{what} another branch ({', '.join(others[:3])})")
        return bool(others)

    def git_reset(self, rest: list[str], place: str, base: str | None) -> None:
        """`git reset` discards work (--hard, --merge, --keep) or moves the branch to another commit. With paths it
        changes only the index, which passes everywhere."""
        split_at = rest.index("--") if "--" in rest else len(rest)
        before, paths = rest[:split_at], rest[split_at + 1 :]
        options = {a.lower().split("=")[0] for a in before if a.startswith("-")}
        positionals = [a for a in before if not a.startswith("-")]
        if "--pathspec-from-file" in options or len(positionals) > 1:
            paths = paths or positionals[1:]
        moves = False
        if positionals and not paths and not re.fullmatch(r"head|@", positionals[0], re.IGNORECASE):
            # Without `--`, git takes a lone argument that is no revision as a path (`git reset core/x.gd`). With
            # `--` after it, or `--soft`, which takes no paths, it is a commit.
            moves = "--" in rest or "--soft" in options or bool(REVISION_RE.search(positionals[0]))
        # No disposable-folder exemption: `git -C tools/out reset --hard` resets the checkout's own repository.
        if options & RESET_MODES or moves:
            self.git_discards(["git", "reset", *rest], place, base)

    def git_checkout(self, rest: list[str], place: str, base: str | None) -> None:
        """`git checkout` of paths discards their changes; of a branch it switches (see git_move); `-B` resets a
        branch."""
        shown = ["git", "checkout", *rest]
        split_at = rest.index("--") if "--" in rest else None
        before = rest if split_at is None else rest[:split_at]
        positionals = _positionals(before, CHECKOUT_VALUED)
        force = bool({"-f", "--force"} & set(before))
        new = _option_values(before, {"-b", "--orphan"})
        if new:
            if "-B" in before and self.git_other_branches(shown, new[:1], "resets"):
                return
            self.git_move(shown, new[0], force, place, base)
            return
        target, paths = None, positionals
        if split_at is not None:
            paths = rest[split_at + 1 :]  # before `--` only the commit the paths come from
        elif positionals and self.is_revision(positionals[0]):
            target, paths = positionals[0], positionals[1:]
        if paths or any(a.startswith("--pathspec-from-file") for a in before):
            self.git_discards(shown, place, base, paths)
        elif target is not None:
            self.git_move(shown, target, force, place, base)
        elif force:
            self.git_discards(shown, place, base)

    def git_switch(self, rest: list[str], place: str, base: str | None) -> None:
        shown = ["git", "switch", *rest]
        force = bool({"-f", "--force", "--discard-changes"} & set(rest))
        new = _option_values(rest, {"-c", "--create", "--force-create", "--orphan"})
        positionals = _positionals(rest, SWITCH_VALUED)
        target = new[0] if new else (positionals[0] if positionals else "")
        forced_new = "-C" in rest or any(a.startswith("--force-create") for a in rest)
        if new and forced_new and self.git_other_branches(shown, new[:1], "resets"):
            return
        if target:
            self.git_move(shown, target, force, place, base)
        elif force:
            self.git_discards(shown, place, base)

    def git_restore(self, rest: list[str], place: str, base: str | None) -> None:
        """`git restore` discards changes in the working tree; `--staged` alone only unstages, which passes."""
        staged = "--staged" in rest or "-S" in rest
        if staged and not ("--worktree" in rest or "-W" in rest):
            return
        args = [a for a in rest if a not in ("-S", "-W")]  # `-S` is not `-s <source>`
        self.git_discards(["git", "restore", *rest], place, base, _positionals(args, RESTORE_VALUED))

    def git_clean(self, rest: list[str], place: str, base: str | None) -> None:
        """`git clean` deletes untracked files; `-n` / `--dry-run` only lists them."""
        letters, longs = _clean_options(rest)
        if "n" in letters or any(_long_prefix(name, "--dry-run") for name in longs):
            return
        shown = ["git", "clean", *rest]
        if place == OWN and self.paths.own == self.paths.root:
            # A cloud session's main checkout (issue #381): ignored files (`-x`, `-X`, or un-ignored by `-e '!x'`)
            # include .claude/settings.local.json and the other worktrees, which a second force removes as nested
            # repositories.
            forces = letters.count("f") + sum(_long_prefix(name, "--force") for name in longs)
            excludes = "e" in letters or any(_long_prefix(name, "--exclude") for name in longs)
            if {"x", "X"} & set(letters) or excludes or forces > 1:
                self.git_finding(shown, "removes ignored files or nested repositories of the main checkout")
                return
        self.git_discards(shown, place, base, _positionals(rest, CLEAN_VALUED))

    def git_stash(self, rest: list[str], place: str, base: str | None) -> None:
        """`git stash drop` and `clear`. The stash is shared by every checkout of the repository, so they pass only
        for entries made on the task branch or a helper (a human's `start --stash` entry is never the agent's)."""
        action = rest[0].lower() if rest and not rest[0].startswith("-") else "push"
        moved, shown = self.paths.stash_moved, ["git", "stash", *rest]
        if action in ("push", "save") and place == OWN and self.paths.own == self.paths.root:
            # `--all` takes the ignored files of a cloud session's main checkout away (issue #381), as `clean -x`.
            options = [a for a in rest if a.startswith("-")]
            if any(_long_prefix(a, "--all") or re.fullmatch(r"-[a-zA-Z]*a[a-zA-Z]*", a) for a in options):
                self.git_finding(shown, "stashes the ignored files of the main checkout")
                return
        if action not in ("list", "show", "apply", "create"):
            self.paths.stash_moved = True
        if action not in ("drop", "clear"):
            return
        if moved:
            self.git_finding(shown, "the stash changed earlier in this command, so its entries cannot be told apart")
            return
        entries = self.repo.stash_branches()
        if action == "clear":
            chosen = entries
        else:
            refs = _positionals(rest[1:])
            match = STASH_REF_RE.match(refs[0]) if refs else None
            index = int(match.group(1) or match.group(2)) if match else (-1 if refs else 0)
            chosen = [entries[index]] if entries is not None and 0 <= index < len(entries) else None
        if chosen is None or any(not self.own_branch(b) for b in chosen):
            self.git_finding(shown, "drops stash entries this session cannot show are its own (the stash is shared)")
        else:
            self.git_discards(shown, place, base)

    def git_rebase(self, rest: list[str], place: str, base: str | None) -> None:
        """`git rebase` rewrites the history of the branch it names, or of the current one; naming `HEAD` or `@`
        moves no branch (git rebases a detached HEAD). An interactive rebase is judged like any other, whatever
        editor it names (issue #457: in the own worktree on its task branch it passes; an editor that opens costs
        that worktree's own rebase, which `git rebase --abort` ends). `--update-refs` and `--exec` always ask.
        Options are read as git reads them (issue #105): `-qi`, `-x'cmd'`, `--interac`, `--exe=cmd`."""
        shown = ["git", "rebase", *rest]
        order, positionals = _rebase_options(rest)
        options = set(order)
        if self.rebase_update_refs(order):
            self.git_finding(shown, "--update-refs (or rebase.updateRefs) moves other branches")
            return
        if "--exec" in options:
            self.git_finding(shown, "--exec runs commands the guard cannot judge")
            return
        if not REBASE_STEPS & options:
            named = positionals[:1] if "--root" in options else positionals[1:2]
            named = [n for n in named if n.lower() not in ("head", "@")]
            if named and self.git_other_branches(shown, named, "rewrites"):
                return
        self.git_discards(shown, place, base)

    def rebase_update_refs(self, options: list[str]) -> bool:
        """The rebase moves the other branches in its range: `rebase.updateRefs` from `git -c` (`-c
        rebase.updateRefs` alone is true), then the last `--update-refs` or `--no-update-refs`."""
        moves = False
        for setting in self.git_configs:
            key, eq, value = setting.partition("=")
            if key.strip().lower() == "rebase.updaterefs":
                moves = not eq or value.strip().strip("'\"").lower() not in GIT_FALSE
        for option in options:
            if option in ("--update-refs", "--no-update-refs"):
                moves = option == "--update-refs"
        return moves

    def git_branch(self, rest: list[str], place: str, base: str | None) -> None:
        """`git branch -d|-D|--delete` deletes, `-f` moves, `-M` / `-C` overwrite: only the task branch's helpers
        pass. Branches are shared by every checkout, so where the command runs does not matter."""
        shown = ["git", "branch", *rest]
        short = "".join(a[1:] for a in rest if a.startswith("-") and not a.startswith("--"))
        long = {a.split("=")[0] for a in rest if a.startswith("--")}
        names = _positionals(rest, {"-u", "--set-upstream-to", "--contains", "--no-contains", "--points-at"})
        if "d" in short.lower() or "--delete" in long:
            self.git_other_branches(shown, names, "deletes")
        elif "M" in short or "C" in short:
            self.git_other_branches(shown, names[:2], "overwrites")
        elif "f" in short or "--force" in long:
            self.git_other_branches(shown, names[:1], "moves")

    def git_worktree(self, rest: list[str], place: str, base: str | None) -> None:
        """`git worktree remove|move` pass for the own worktree's folder, an absolute path inside it (a worktree
        nested there, issue #457; also when a loop names its last part: `.../51/tools/out/w$i`), and an absolute path
        outside the project, only. git also takes the last parts of a worktree's path (`remove 47`, `worktrees/47`,
        `tools/out/w1`), so any other argument may name another worktree and asks."""
        if not rest or rest[0].lower() not in ("remove", "move"):
            return
        own = self.paths.own if self.paths.own != self.paths.root else None
        for target in _positionals(rest[1:])[:1]:
            path = self.paths.resolve(target, base if base is not None else "")
            absolute = bool(ABSOLUTE_RE.match(target))
            if path is not None and own and path == own:
                continue
            if absolute and own and path is not None and path.startswith(own + "/"):
                continue
            if absolute and own and path is None and self.paths.literal_place(target) == OWN:
                continue  # the folder before the unknown part is the own worktree or inside it: `.../51/w$i`
            if path is not None and absolute and self.paths.place(path) == OUTSIDE_PROJECT:
                continue
            self.git_finding(["git", "worktree", *rest], "may name another worktree or the main checkout")

    def git_update_ref(self, rest: list[str], place: str, base: str | None) -> None:
        """`git update-ref` deletes or moves a branch by its ref: judged like `git branch -D|-f`. `HEAD` moves the
        checked-out branch, like `git reset --soft`."""
        shown = ["git", "update-ref", *rest]
        if "--stdin" in rest:
            self.git_finding(shown, "--stdin changes refs the guard cannot see")
            return
        refs = _positionals(rest, {"-m"})[:1]
        if refs and refs[0].lower().startswith("refs/heads/"):
            self.git_other_branches(shown, refs, "moves or deletes")
        elif refs and refs[0].upper() == "HEAD":
            self.git_discards(shown, place, base)

    # --- gh: reads of other repositories pass, anything else there asks (issue #68) -----------------------------------

    def gh(self, args: list[str]) -> None:
        """A gh command that names a repository other than this project's asks, unless it only reads (GH_READS,
        `gh api` GET or HEAD). The repository comes from `-R|--repo`, `GH_REPO`, a github.com URL argument,
        `gh repo <sub> owner/name`, the destination of `gh issue transfer`, or a `gh api repos/owner/name/...`
        endpoint. A command that names no repository acts on this project's and is left to the rules; so is one that
        names a repository of gh's own account, unless it is a kept kind (GH_OWNER_KEPT, issue #464)."""
        group = args[0].lower() if args else ""
        # The subcommand is the first word after the group that is no option: `-R` is a persistent flag of the
        # group, so `gh issue -R o/r view 1` is a read too.
        sub, rest, i = "", args[1:], 1
        while i < len(args):
            if args[i] in ("-R", "--repo"):
                i += 2
            elif args[i].startswith("-"):
                i += 1
            else:
                sub, rest = args[i].lower(), args[1:i] + args[i + 1 :]
                break
        if group == "api":
            method, targets, endpoint = self.gh_api(args[1:])
            if method in GH_READ_METHODS:
                return
            kept = method != "POST" or bool(GH_API_KEPT_RE.search(endpoint))
        else:
            reads = GH_READS.get(group, set())
            if group in GH_READS and (reads is None or sub in reads):
                return
            targets = self.gh_targets(group, sub, rest)
            subs = GH_OWNER_KEPT.get(group, set())
            kept = group in GH_OWNER_KEPT and (subs is None or sub in subs)
            kept = kept or any(a.lower().partition("=")[0] in GH_OWNER_KEPT_OPTIONS for a in rest)
        env = self.gh_env()
        if env is not None:
            targets.append(env)
        own = self.repo.github_repo()
        others = [t for t in targets if own is None or gh_repo_name(self.gh_value(t)) != own]
        if others and not kept:
            # A repository of gh's own account passes like this one (issue #464): the rules judge the command.
            account = self.repo.gh_user()
            others = [t for t in others if account is None or self.gh_owner(t) != account]
        if others:
            self.findings.append(Finding(" ".join(["gh", *args])[:100], GH, others[0]))

    def gh_value(self, target: str) -> str:
        """A repository argument with the variables the command assigns filled in (`-R "$R"` after `R=o/r`)."""
        value = self.paths.expand(target)
        return target if value is None or OUTSIDE in value else value

    def gh_owner(self, target: str) -> str | None:
        """The lower-case owner of a repository argument on github.com, also when only its owner can be read
        (`xperiaroco2/$1`); None for another host or a value the guard cannot read."""
        value = self.gh_value(target)
        name = gh_repo_name(value)
        if name is not None:
            return name.split("/", 1)[0]
        match = GH_OWNER_RE.match(value)
        if not match or GH_REPO_RE.match(value) or "." in match.group(1):
            return None  # `ghe.example.com/o/r` names another host
        return match.group(1).lower()

    def gh_targets(self, group: str, sub: str, rest: list[str]) -> list[str]:
        """The repositories a gh command other than `gh api` names."""
        targets, positionals, i = [], [], 0
        while i < len(rest):
            arg = rest[i]
            name, eq, value = arg.partition("=") if arg.startswith("--") else (arg, "", "")
            if name in ("-R", "--repo"):
                if eq:
                    targets.append(value)
                elif i + 1 < len(rest):
                    targets.append(rest[i + 1])
                    i += 1
            elif arg.startswith("-R") and not arg.startswith("--"):
                targets.append(arg[2:])  # `-Rowner/name`
            elif name in GH_TEXT_OPTIONS:
                # An option is never the value of another one: `gh pr create -d -R x/y` (-d is --draft there).
                if not eq and i + 1 < len(rest) and not rest[i + 1].startswith("-"):
                    i += 1
            elif not arg.startswith("-"):
                positionals.append(arg)
            i += 1
        targets += [p for p in positionals if GH_URL_RE.match(p)]
        if group == "repo":
            targets += [p for p in positionals if not GH_URL_RE.match(p) and GH_REPO_RE.match(p)]
        if (group, sub) == ("issue", "transfer") and len(positionals) > 1:
            targets.append(positionals[1])
        return targets

    def gh_api(self, rest: list[str]) -> tuple[str, list[str], str]:
        """The method of a `gh api` request (GET unless -X names another, POST when fields are added), the
        repositories it names, and its endpoint ("" when none)."""
        method, fields, endpoint, targets, i = "", False, None, [], 0
        while i < len(rest):
            arg = rest[i]
            name, eq, value = arg.partition("=") if arg.startswith("--") else (arg, "", "")
            if name in GH_API_VALUED:
                given = value if eq else (rest[i + 1] if i + 1 < len(rest) else "")
                i += 0 if eq else 1
                if name in ("-X", "--method"):
                    method = given
                elif name in ("-R", "--repo"):
                    targets.append(given)
                fields = fields or name in GH_API_FIELDS
            elif re.match(r"^-X=?\w", arg):
                method = arg[2:].removeprefix("=")  # `-XPOST`, `-X=POST`
            elif re.match(r"^-[fF].", arg):
                fields = True  # `-fbody=x`, `-F=title=x`
            elif not arg.startswith("-") and endpoint is None:
                endpoint = arg
            i += 1
        if endpoint and "{owner}" not in endpoint and ":owner" not in endpoint:
            api = GH_API_REPO_RE.match(endpoint)
            if api:
                targets.append(f"{api.group(1)}/{api.group(2)}")
            elif GH_URL_RE.match(endpoint):
                targets.append(endpoint)
        return (method or ("POST" if fields else "GET")).upper(), targets, endpoint or ""

    def gh_env(self) -> str | None:
        """GH_REPO as the command sets it (a `VAR=value` prefix, or `export` / `$env:` earlier in the command); a
        value the guard cannot compute is kept as text that names no repository, so it counts as another one."""
        if GH_REPO_ENV in self.prefix_env:
            return self.prefix_env[GH_REPO_ENV]
        if GH_REPO_ENV in self.paths.vars:
            value = self.paths.vars[GH_REPO_ENV]
            return value if value is not None else "(computed)"
        return None

    def targets(self, verb: str, args: list[str], depth: int) -> list[str]:
        """The paths a command writes, as far as its text shows."""
        if verb in COPY_VERBS:
            explicit = _option_values(args, DESTINATION_OPTIONS)
            if explicit:
                return explicit
            positionals = _positionals(args, PATH_OPTIONS | DESTINATION_OPTIONS | VALUE_OPTIONS)
            has_path_option = bool(_option_values(args, PATH_OPTIONS))
            return positionals[-1:] if len(positionals) >= 2 or has_path_option else []
        if verb in COPY_REST_VERBS:
            return _positionals(args)[1:]
        if verb in WRITE_VERBS:
            return _positionals(args, PATH_OPTIONS | VALUE_OPTIONS) + _option_values(args, PATH_OPTIONS)
        if verb in CONTENT_VERBS:
            explicit = _option_values(args, PATH_OPTIONS)
            return explicit or _positionals(args, PATH_OPTIONS | VALUE_OPTIONS)[:1]
        if verb == "dd":
            return [a[3:] for a in args if a.startswith("of=")]
        if verb in EXTRACT_VERBS:
            if verb == "7z" and not (args and args[0].lower() in ("x", "e")):
                return []
            if verb == "tar" and not (
                (args and re.fullmatch(r"[a-z]*x[a-z]*", args[0]))
                or any(a == "--extract" or (re.match(r"^-[a-z]+$", a) and "x" in a) for a in args)
            ):
                return []
            rest = _positionals(args)[1:] + _option_values(args, {"-d", "-c", "--directory", "-destinationpath"})
            return rest + [a[2:] for a in args if re.match(r"^-[od][^-]", a)]
        if verb in IN_PLACE_VERBS:
            if any(re.match(r"^(-[a-z]*i|--in-place)", a) for a in args):
                return [a for a in args if not a.startswith("-")]
            return []
        if verb in DOWNLOAD_VERBS:
            return _option_values(args, DOWNLOAD_OPTIONS)
        if verb == "find" and any(a in ("-delete", "-exec", "-execdir", "-ok") for a in args):
            return [a for a in args if not a.startswith("-")]
        if verb in NESTED_SHELLS and depth < 3:
            code = self.nested_code(verb, args)
            if code:
                inner = Analysis(self.paths.child(NESTED_SHELLS[verb], self.prefix_env), self.repo)
                inner.command(code, NESTED_SHELLS[verb], depth + 1)
                self.findings += inner.findings
                self.paths.adopt(inner.paths)
        return []

    @staticmethod
    def nested_code(verb: str, args: list[str]) -> str:
        if verb in ("invoke-expression", "iex"):
            return " ".join(args)
        for index, arg in enumerate(args):
            low = arg.lower()
            if NESTED_SHELLS[verb] == BASH:
                code_option = bool(re.fullmatch(r"-[a-z]*c", low))  # -c, -lc, -ec, -xc
            elif verb == "cmd":
                code_option = low in ("/c", "/k", "//c", "//k")  # `//c` from Git Bash
            else:
                code_option = len(low) >= 2 and "-command".startswith(low)  # -c, -Com, -Command
            if code_option:
                return " ".join(args[index + 1 :])
        return ""


# git subcommands judged by where they act; the others (status, log, add, commit, push, ...) are left to the rules.
GIT_JUDGES = {
    "reset": Analysis.git_reset,
    "checkout": Analysis.git_checkout,
    "switch": Analysis.git_switch,
    "restore": Analysis.git_restore,
    "clean": Analysis.git_clean,
    "stash": Analysis.git_stash,
    "rebase": Analysis.git_rebase,
    "branch": Analysis.git_branch,
    "worktree": Analysis.git_worktree,
    "update-ref": Analysis.git_update_ref,
}


def check(
    command: str, shell: str, cwd: str, root: str, home: str = "", repo: NoRepo | None = None, cloud: bool = False
) -> list[Finding]:
    """Findings for one Bash or PowerShell command run in cwd; empty when it writes to no ask-protected path of the
    project at root, and deletes recursively or discards git work only in the session's own worktree, on its task
    branch, or outside the project. home is the user's home folder, when known: `~` and `$HOME` resolve to it. repo
    tells branch and stash names (hooks.GitFiles); without it no branch is the session's own. cloud: the command
    runs in a cloud session (common.cloud_session), whose main checkout on a task branch is its own (issue #381)."""
    analysis = Analysis(Paths(root, cwd, home, shell), repo, cloud)
    analysis.command(command, shell)
    return analysis.findings


def reason(findings: list[Finding]) -> str:
    """The text shown in the permission prompt."""
    writes = [f for f in findings if f.area not in (DELETE, TEMP_DELETE, GIT, GH)]
    deletes = sorted({f"{f.verb} -> {f.path}" for f in findings if f.area == DELETE})
    temps = sorted({f"{f.verb} -> {f.path}" for f in findings if f.area == TEMP_DELETE})
    gits = sorted({f"{f.path} ({f.verb})" for f in findings if f.area == GIT})
    ghs = sorted({f"{f.path} (repository {f.verb})" for f in findings if f.area == GH})
    parts = []
    if writes:
        shown = sorted({f"{f.verb} -> {f.path}" for f in writes})
        areas = sorted({f.area for f in writes})
        parts.append(
            f"Shell write to an ask-protected path ({', '.join(areas)}): {'; '.join(shown[:5])}. "
            "Agent permissions and dependencies change only with your OK."
        )
    if deletes:
        parts.append(f"Recursive delete in the project: {'; '.join(deletes[:5])} (outside this session's own worktree).")
    if temps:
        parts.append(
            f"Filtered recursive delete in the temp folder: {'; '.join(temps[:5])} may match a Claude scratchpad"
            " root (any session's) or a worktree, reach outside the temp folder, or match what the guard cannot tell."
        )
    if gits:
        parts.append(f"git that discards work or rewrites history: {'; '.join(gits[:3])}.")
    if ghs:
        parts.append(
            f"gh that may write to another repository: {'; '.join(ghs[:3])}. Reads of other repositories pass, and"
            " so do writes to your gh account's own ones, but merges, deletion, auth, secrets and the other changes"
            " the rules guard."
        )
    return " ".join(parts) + " (docs/AGENT_WORKFLOW.md §8.2)"
