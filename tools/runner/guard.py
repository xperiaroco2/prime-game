"""The thin guard: which shell commands write to the ask-protected paths, delete the project recursively, or
discard work with `git reset` (docs/AGENT_WORKFLOW.md §8.2).

`Edit(**/.claude/settings.json)` and `Edit(**/addons/**)` ask rules stop the file tools, but not a shell write:
Claude Code checks a redirect or `tee` target only against Edit allow and deny rules, and cannot see where
`Copy-Item` or `cp` writes. The PreToolUse hook (`run hook guard`) passes Bash and PowerShell commands here and asks
the human when one writes to `.claude/settings*.json` or `addons/`. Everything else passes silently, so the agent
can work alone.

Text ask rules cannot tell a delete of the agent's scratch folder from a delete of the repo, so the guard also judges
two commands by their target (issue #47):
- a recursive delete asks when a target is the project (the main checkout or a worktree), inside it, above it, a
  drive root, `/`, or the home or temp folder itself (`~`, `$HOME`, `$env:TEMP`), or cannot be resolved and names the
  project: its folder name, `git rev-parse --show-toplevel`, `$PWD` inside it, a command's output that names a path
  in it (`$(realpath core)`, `(Resolve-Path core)`), a variable assigned from such text, or a relative path after an
  unresolvable `cd` made from inside it. Recursive deletes are `rm -r` in any bash spelling, `Remove-Item -Recurse`
  (or `-r`, `-rec`), `rmdir /s`, `rd /s/q`, `del /s`, a plain delete fed by a recursive listing
  (`Get-ChildItem core -Recurse | Remove-Item`), an unfiltered `find -delete` or `find -exec rm -rf`, and
  `shutil.rmtree('x')` or `[IO.Directory]::Delete('x', $true)` with a literal path. The targets of a pipeline
  (`$_`, `{}`, `%`, none) are the paths its first command names, or the working directory. Regenerated output
  (`tools/out/`, `.godot/`) and the gitignored scratch folder `tests/scratch/` pass, in the main checkout and in
  every worktree; so do the scratchpad, `$TEMP/x`, `/tmp/x` and `~/x`.
- `git reset` asks with `--hard`, `--merge` or `--keep`, or when it moves the branch (`git reset HEAD~1`,
  `git reset --soft origin/main`, `git reset v0.1.0`), in a repository anywhere inside the project (`tools/out/`
  too). Unstaging (`git reset`, `git reset -q`, `git reset -- <paths>`, `git reset HEAD -- <paths>`,
  `git reset core`) passes. A lone argument is a revision when it looks like one (a SHA, `~`, `^`, `origin/x`,
  `refs/x`, `v1.2`, a task branch `net/40-x`, `main`); another bare name (`git reset feature-x`) counts as a path.
- Out of scope: deletes whose target only a run could show (a variable set in an earlier call, a path read from a
  file, a computed `rmtree(p)`), filtered deletes (`find . -name '*.orig' -delete`, `Get-ChildItem -Recurse -Filter
  *.tmp | Remove-Item`, `del /s *.tmp` outside the project), and `git checkout`/`restore`/`clean`/`stash drop`, which
  keep their own text ask rules.

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
DELETE, RESET = "recursive delete", "git reset"
# Commands that delete; each is recursive only with its recursive option.
DELETE_VERBS = {"rm", "del", "erase", "rd", "rmdir", "ri", "remove-item"}
# cmd.exe delete commands, and their switches (`rmdir /s /q x`, `rd /s/q x`): options, not paths.
CMD_DELETE_VERBS = {"rd", "rmdir", "del", "erase"}
CMD_SWITCH_RE = re.compile(r"^(/[a-z?])+$", re.IGNORECASE)
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
        self.stack: list[str | None] = []
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

    def child(self, shell: str | None = None) -> Paths:
        """The view of a nested shell (`bash -c`) or a `$(...)`: same directory and variables; its `cd` stays
        inside it."""
        inner = Paths(self.root, "", self.home, shell or self.shell)
        inner.cwd, inner.vars, inner.tainted = self.cwd, dict(self.vars), dict(self.tainted)
        inner.project_vars, inner.cwd_text, inner.cwd_base = set(self.project_vars), self.cwd_text, self.cwd_base
        return inner

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

    def project_target(self, token: str, cwd: str | None = "", disposable: bool = True) -> bool:
        """token, a delete target or a repository, is in the project: resolved, or by its text. A home or temp
        folder itself counts too."""
        text = self.expand(token)
        if text is not None and OUTSIDE_ROOT_RE.match(text):
            return True
        path = self.resolve(token, cwd)
        if path is not None:
            return self.in_project(path, disposable)
        return self.names_project(token) or self.computed(token)

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

    def expand(self, token: str) -> str | None:
        """token with its variables replaced; None when one of them is unknown."""
        unknown = False

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
            unknown = True
            return ""

        text = VAR_RE.sub(value, token)
        return None if unknown or "$" in text else text

    def resolve(self, token: str, cwd: str | None = "") -> str | None:
        """An absolute normalized path, OUTSIDE, or None when it cannot be known."""
        text = self.expand(token)
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
        """The protected area token writes to: inside this project only; by its text when it cannot be resolved."""
        path = self.resolve(token, cwd)
        if path is None:
            names = {next(g for g in m.groups() if g).lower() for m in VAR_RE.finditer(token)}
            tainted = next((self.tainted[n] for n in sorted(names) if n in self.tainted), None)
            return protected(token) or text_area(token) or tainted
        if path == OUTSIDE or not path.startswith(self.root + "/"):
            return None
        return project_area(path[len(self.root) + 1 :])

    def cd(self, verb: str, args: list[str]) -> None:
        if verb in ("popd", "pop-location"):
            self.cwd = self.stack.pop() if self.stack else None
            return
        if verb in ("pushd", "push-location"):
            self.stack.append(self.cwd)
        dest = _positionals(args, {"-path", "-literalpath"}) or _option_values(args, {"-path", "-literalpath"})
        if not dest:
            self.cwd = OUTSIDE if verb in ("cd", "chdir") else self.cwd  # bash `cd` alone goes home
        elif dest[0] == "-":
            self.cwd = None
        else:
            before = self.cwd
            self.cwd = self.resolve(dest[0])
            if self.cwd is None and not re.match(ABSOLUTE_RE, dest[0]):
                # An unresolvable relative `cd` stays under the directory it started from: `cd "lab$S"` in the
                # project is in the project.
                self.cwd_base = before if before is not None else self.cwd_base
                self.cwd_text = f"{self.cwd_text}/{dest[0]}" if before is None and self.cwd_text else dest[0]
            elif self.cwd is None:
                self.cwd_base, self.cwd_text = "", dest[0]
        if self.cwd is not None:
            self.cwd_text, self.cwd_base = "", ""

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
            current = Segment(pipeline=pipeline, after_pipe=piped)
            pending = ""
        elif kind == "sub":
            current.subs.append(text)
        elif kind == "heredoc":
            (segments[-1] if not (current.words or current.redirects) and segments else current).heredocs.append(text)
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


def _command_words(words: list[str]) -> tuple[list[str], bool]:
    """Words from the real command on (leading VAR=value assignments and prefixes such as sudo, xargs or `then`
    removed), and whether xargs feeds it."""
    i, via_xargs = 0, False
    while i < len(words):
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[i]):
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
    """A delete is recursive: bash `rm -r|-R|-rf|--recursive`, PowerShell `-Recurse` or any prefix of it (`-r`,
    `-rec`; in PowerShell `rm` is Remove-Item, so `rm -Force` is not), cmd.exe `rmdir /s`, `rd /s/q`, `del /s`."""
    for arg in args:
        low = arg.lower()
        if low == "--":
            return False
        name, _, value = low.partition(":")
        if low == "--recursive" or (verb == "rm" and shell == BASH and re.fullmatch(r"-[a-z]*r[a-z]*", low)):
            return True
        if len(name) >= 2 and "-recurse".startswith(name) and value not in ("$false", "0"):
            return True
        if verb in CMD_DELETE_VERBS and CMD_SWITCH_RE.match(low) and "/s" in re.findall(r"/[a-z?]", low):
            return True
    return False


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
        return not FIND_FILTERS & {a.lower() for a in args}
    if verb not in ("ls", "dir", "get-childitem", "gci"):
        return False
    if _option_values(args, {"-filter", "-include"}):
        return False  # `Get-ChildItem -Recurse -Filter *.tmp | Remove-Item` is a targeted cleanup
    if shell == BASH:
        return any(a == "--recursive" or re.fullmatch(r"-[a-zA-Z]*R[a-zA-Z]*", a) for a in args)
    return _recursive("remove-item", args, POWERSHELL)


def _find_deletes_all(args: list[str]) -> bool:
    """`find` deletes everything under its start paths: `-delete`, or `-exec rm -rf {}`, with no name or path
    filter (`find . -name '*.orig' -delete` is a targeted cleanup)."""
    lows = [a.lower() for a in args]
    if FIND_FILTERS & set(lows):
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
    def __init__(self, paths: Paths) -> None:
        self.paths = paths
        self.findings: list[Finding] = []
        self.piped_first: dict[int, list[str]] = {}

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
        for segment in split(command, shell):
            for target in segment.redirects:
                self.add(target, ">")
            for sub in segment.subs:
                if depth < 3:
                    self.command(sub, shell, depth + 1)
            words = segment.words
            if words:
                rest = self.paths.assign(words)
                words = words if rest is None else rest
            words, via_xargs = _command_words(words)
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
        if verb in DELETE_VERBS:
            first = self.piped_first.get(segment.pipeline) if segment.after_pipe else None
            recursive = _recursive(verb, args, self.paths.shell) or _recursive_listing(first, self.paths.shell)
            if recursive:
                fed = segment.after_pipe or via_xargs
                self.recursive_delete(words[0], args, (first or []) if fed else None)
        if verb == "find" and _find_deletes_all(args):
            for start in _find_starts(args) or ["."]:
                if self.paths.project_target(start):
                    self.findings.append(Finding(start, DELETE, words[0]))
        if INTERPRETER_RE.search(verb) or DOTNET_WRITE_RE.search(words[0]):
            for match in CODE_DELETE_RE.finditer("\n".join(words + segment.heredocs)):
                target = match.group(1) or match.group(2)
                if self.paths.project_target(target):
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
        if fed is not None and all(PIPE_ITEM_RE.match(t) for t in targets):
            targets = self.paths.output_paths(fed) if fed else ["."]
        for target in targets:
            if self.paths.project_target(target):
                self.findings.append(Finding(target, DELETE, verb))

    def git_reset(self, rest: list[str], work_dir: str) -> None:
        """`git reset` asks when it discards work (--hard, --merge, --keep) or moves the branch to another commit,
        in a repository in the project. With paths it changes only the index."""
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
        # No disposable-folder exemption: `git -C tools/out reset --hard` resets the project's own repository.
        if (options & RESET_MODES or moves) and self.paths.project_target(work_dir or ".", disposable=False):
            shown = " ".join(["git reset", *rest])
            self.findings.append(Finding(shown[:80], RESET, "git reset"))

    def git(self, args: list[str]) -> None:
        i, work_dir = 0, ""
        while i < len(args) and args[i].startswith("-"):
            if args[i] in ("-C", "-c") and i + 1 < len(args):
                work_dir = args[i + 1] if args[i] == "-C" else work_dir
                i += 2
            else:
                i += 1
        if i < len(args) and args[i].lower() == "reset":
            self.git_reset(args[i + 1 :], work_dir)
            return
        if i >= len(args) or args[i].lower() not in GIT_WRITES:
            return
        sub, rest = args[i].lower(), args[i + 1 :]
        if GIT_INDEX_ONLY & {a.lower() for a in rest} and "--worktree" not in rest:
            return
        cwd = self.paths.resolve(work_dir) if work_dir else ""
        for path in rest:
            if not path.startswith("-"):
                self.add(path, f"git {sub}", cwd)

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
                inner = Analysis(self.paths.child(NESTED_SHELLS[verb]))
                inner.command(code, NESTED_SHELLS[verb], depth + 1)
                self.findings += inner.findings
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
                code_option = low in ("/c", "/k")
            else:
                code_option = len(low) >= 2 and "-command".startswith(low)  # -c, -Com, -Command
            if code_option:
                return " ".join(args[index + 1 :])
        return ""


def check(command: str, shell: str, cwd: str, root: str, home: str = "") -> list[Finding]:
    """Findings for one Bash or PowerShell command run in cwd; empty when it writes to no ask-protected path of the
    project at root, deletes none of it recursively and resets none of it. home is the user's home folder, when
    known: `~` and `$HOME` resolve to it."""
    analysis = Analysis(Paths(root, cwd, home, shell))
    analysis.command(command, shell)
    return analysis.findings


def reason(findings: list[Finding]) -> str:
    """The text shown in the permission prompt."""
    writes = [f for f in findings if f.area not in (DELETE, RESET)]
    deletes = sorted({f"{f.verb} -> {f.path}" for f in findings if f.area == DELETE})
    resets = sorted({f.path for f in findings if f.area == RESET})
    parts = []
    if writes:
        shown = sorted({f"{f.verb} -> {f.path}" for f in writes})
        areas = sorted({f.area for f in writes})
        parts.append(
            f"Shell write to an ask-protected path ({', '.join(areas)}): {'; '.join(shown[:5])}. "
            "Agent permissions and dependencies change only with your OK."
        )
    if deletes:
        parts.append(f"Recursive delete in the project: {'; '.join(deletes[:5])}.")
    if resets:
        parts.append(f"git reset that discards work or moves the branch: {'; '.join(resets[:3])}.")
    return " ".join(parts) + " (docs/AGENT_WORKFLOW.md §8.2)"
