"""The thin guard: which shell commands write to the ask-protected paths (docs/AGENT_WORKFLOW.md §8.2).

`Edit(**/.claude/settings.json)` and `Edit(**/addons/**)` ask rules stop the file tools, but not a shell write:
Claude Code checks a redirect or `tee` target only against Edit allow and deny rules, and cannot see where
`Copy-Item` or `cp` writes. The PreToolUse hook (`run hook guard`) passes Bash and PowerShell commands here and asks
the human when one writes to `.claude/settings*.json` or `addons/`. Everything else passes silently, so the agent
can work alone.

Like those Edit rules, it protects the project's own paths (the main checkout and its worktrees): a scratch copy
under the temp folder is not a dependency. It resolves each target against the session's working directory, `cd`
and the variables the same command assigns; `$TEMP`, `$env:TEMP`, `~` and similar are outside the project. A path it
cannot resolve counts as protected when its text names one. It also looks inside `bash -c`, `powershell -Command`,
pipelines (`Get-ChildItem addons | Remove-Item`) and one-line inline writes (`python -c`, `[IO.File]::WriteAllText`).
It does not run scripts. Pure functions only; the hook entry point is in hooks.py.
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

# Commands that only prefix the real command.
PREFIXES = {"sudo", "env", "command", "builtin", "exec", "nohup", "time", "nice", "xargs", "call", "."}
# Where the working directory moves for the rest of the command.
CD_VERBS = {"cd", "chdir", "pushd", "set-location", "sl", "push-location"}
# The last positional argument (or the destination option) is written; the others are only read.
COPY_VERBS = {"cp", "copy", "copy-item", "cpi", "install", "rsync", "scp"}
# Every positional argument after the first is a destination.
COPY_REST_VERBS = {"xcopy", "robocopy"}
# Every path argument is written (moved, removed, created or overwritten).
WRITE_VERBS = {
    "mv", "move", "move-item", "mi", "ren", "rename", "rename-item", "rni",
    "rm", "del", "erase", "rd", "rmdir", "ri", "remove-item",
    "touch", "mkdir", "md", "new-item", "ni", "ln", "truncate", "chmod", "chown", "attrib", "icacls",
    "set-content", "sc", "add-content", "ac", "clear-content", "clc", "out-file", "tee", "tee-object",
    "set-itemproperty", "sp", "new-itemproperty", "export-csv", "export-clixml", "set-acl", "patch",
}  # fmt: skip
# Commands that change the paths a pipeline feeds them (`Get-ChildItem addons | Remove-Item`, `| xargs rm`). Copies
# are not here: the pipeline gives them sources, and their destination is on the command line.
PIPED_PATH_VERBS = {
    "rm", "del", "erase", "rd", "rmdir", "ri", "remove-item", "mv", "move", "move-item", "mi",
    "ren", "rename", "rename-item", "rni", "clear-content", "clc",
}  # fmt: skip
# A pipeline item, when it stands where a path goes.
PIPE_ITEM_RE = re.compile(r"^(\$_|\$psitem|\{\})", re.IGNORECASE)
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
NESTED_CODE_OPTIONS = {"-c", "-command", "/c", "/k"}
DESTINATION_OPTIONS = {"-destination", "-dest", "-t", "--target-directory", "-destinationpath"}
PATH_OPTIONS = {"-path", "-literalpath", "-filepath"}

# APIs that write files from inline code (python -c, node -e, [IO.File]::...). A line that uses one and also names a
# protected path counts as a write.
WRITE_API_RE = re.compile(
    r"\[(?:System\.)?IO\.(?:File|Directory)\]::(?:Write|Append|Copy|Move|Delete|Create|Replace|Open(?!Read))"
    r"|(?:System\.)?IO\.StreamWriter"
    r"|\bopen\([^)]*,\s*['\"][wax]"
    r"|\.write_(?:text|bytes)\("
    r"|\bshutil\.(?:copy|move|rmtree)"
    r"|\bos\.(?:remove|unlink|rename|replace|rmdir|makedirs|mkdir|truncate)\("
    r"|\.(?:unlink|rmdir|touch|symlink_to)\("
    r"|\bjson\.dump\("
    r"|\bfs\.(?:write|append|copy|rename|unlink|rm|mkdir|truncate)",
    re.IGNORECASE,
)
PROTECTED_TEXT_RE = re.compile(
    r"(?:^|[\s'\"=(/\\:,])addons(?:[/\\'\"\s),]|$)|\.claude[/\\]+settings[^/\\\s'\"]*\.json",
    re.IGNORECASE,
)
SETTINGS_NAMES = ("settings.json", "settings.local.json")


def protected(path: str) -> str | None:
    """Which ask-protected area a path names ('addons/' or '.claude/settings*.json'), or None.

    Any `addons` folder counts (a worktree's too). A `.claude` folder counts when the path is the folder itself or a
    file in it that is, or could match, `settings*.json`: its settings are the agent's own permissions.
    """
    parts = [p for p in path.replace("\\", "/").lower().split("/") if p not in ("", ".")]
    for index, part in enumerate(parts):
        if part == "addons":
            return "addons/"
        if part != ".claude":
            continue
        if index == len(parts) - 1:
            return ".claude/settings*.json"
        name = parts[index + 1]
        if fnmatch.fnmatch(name, "settings*.json") or any(fnmatch.fnmatch(real, name) for real in SETTINGS_NAMES):
            return ".claude/settings*.json"
    return None


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

    def __init__(self, root: str, cwd: str) -> None:
        self.root = normalize(root)
        self.cwd: str | None = normalize(cwd) if cwd else self.root
        self.stack: list[str | None] = []
        self.vars: dict[str, str | None] = {"claude_project_dir": self.root}
        self.tainted: dict[str, str] = {}

    def child(self) -> Paths:
        """The view of a nested shell (`bash -c`): same directory and variables; its `cd` stays inside it."""
        inner = Paths(self.root, "")
        inner.cwd, inner.vars, inner.tainted = self.cwd, dict(self.vars), dict(self.tainted)
        return inner

    def expand(self, token: str) -> str | None:
        """token with its variables replaced; None when one of them is unknown."""
        unknown = False

        def value(match: re.Match[str]) -> str:
            nonlocal unknown
            name = next(group for group in match.groups() if group).lower()
            if name == "pwd" and self.cwd:
                return self.cwd
            if name in self.vars and self.vars[name] is not None:
                return str(self.vars[name])
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
            return protected(token) or next((self.tainted[n] for n in sorted(names) if n in self.tainted), None)
        if path == OUTSIDE or not path.startswith(self.root + "/"):
            return None
        return protected(path[len(self.root) + 1 :])

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
            self.cwd = self.resolve(dest[0])

    def assign(self, words: list[str]) -> bool:
        """Record `S=value`, `export S=value` or PowerShell `$S = value`. True if words were an assignment."""
        if words[0] == "export" and len(words) == 2:
            words = words[1:]
        if len(words) == 1 and (match := ASSIGN_RE.match(words[0])):
            name, raw = match.group(1), match.group(2)
        elif len(words) >= 2 and words[1] == "=" and (var := re.match(r"^\$(?:env:)?([A-Za-z_]\w*)$", words[0])):
            name, raw = var.group(1), (words[2] if len(words) == 3 else "$unknown")
        else:
            return False
        name = name.lower()
        self.vars[name] = self.expand(raw)
        # A value this cannot compute (`$p = Join-Path $root addons`) still counts as protected if its words name one.
        area = next((a for a in map(protected, words[1:]) if a), None) if self.vars[name] is None else None
        if area:
            self.tainted[name] = area
        else:
            self.tainted.pop(name, None)
        return True


# --- lexing both shells ---------------------------------------------------------------------------------------------


class Segment:
    """One simple command: its words, its output redirect targets, and the pipeline it belongs to.
    (Plain classes, not dataclasses: this module runs before every shell command, and the import costs.)"""

    def __init__(self, pipeline: int = 0, after_pipe: bool = False) -> None:
        self.words: list[str] = []
        self.redirects: list[str] = []
        self.pipeline = pipeline
        self.after_pipe = after_pipe


HEREDOC_RE = re.compile(r"""\s*(['"]?)([A-Za-z0-9_.-]+)\1""")


def _lex(command: str, shell: str) -> list[tuple[str, str]]:
    """Tokens as (kind, text). Kinds: word, op (a separator), redir (an output target follows), skip (the next word
    is data: an input redirect or a here-string). Quotes are removed with each shell's escape character (backslash
    in bash, backtick in PowerShell, where a backslash is a path separator). Heredoc and here-string bodies are data,
    never commands."""
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

    while i < n:
        c = command[i]
        nxt = command[i + 1] if i + 1 < n else ""
        if c == "\n":
            op("\n", 1)
            for delimiter, strip_tabs in heredocs:  # skip the bodies of heredocs opened on this line
                while i < n:
                    end = command.find("\n", i)
                    line = command[i : end if end != -1 else n].rstrip("\r")
                    i = end + 1 if end != -1 else n
                    if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                        break
            heredocs = []
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
                j += 2 if command[j] == escape and j + 1 < n else 1
            word.append(command[i + 1 : j])
            has_word = True
            i = j + 1
        elif c == "`":  # bash command substitution (the PowerShell backtick is its escape, handled above)
            op("`", 1)
        elif c in ";(){}":
            op(c, 1)
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
    for kind, text in _lex(command, shell):
        if kind == "op":
            if current.words or current.redirects:
                segments.append(current)
            if text == "|":
                piped = True
            elif text not in ("(", ")", "{", "}", "`"):
                pipeline, piped = pipeline + 1, False
            current = Segment(pipeline=pipeline, after_pipe=piped)
            pending = ""
        elif kind in ("redir", "skip"):
            pending = kind
        elif pending == "redir":
            current.redirects.append(text)
            pending = ""
        elif pending == "skip":
            pending = ""
        else:
            current.words.append(text)
    if current.words or current.redirects:
        segments.append(current)
    return segments


# --- analysis ---------------------------------------------------------------------------------------------------------


def _verb(word: str) -> str:
    name = word.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return re.sub(r"\.(exe|cmd|bat|com)$", "", name)


def _command_words(words: list[str]) -> list[str]:
    """Words from the real command on: leading VAR=value assignments and prefixes such as sudo or xargs removed."""
    i = 0
    while i < len(words):
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[i]):
            i += 1
        elif _verb(words[i]) in PREFIXES:
            i += 1
            while i < len(words) and (words[i].startswith("-") or words[i] == "{}"):
                i += 1
        else:
            break
    return words[i:]


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


class Finding:
    def __init__(self, path: str, area: str, verb: str) -> None:
        self.path, self.area, self.verb = path, area, verb

    def __repr__(self) -> str:
        return f"Finding({self.verb} -> {self.path}: {self.area})"


class Analysis:
    def __init__(self, paths: Paths) -> None:
        self.paths = paths
        self.findings: list[Finding] = []

    def add(self, path: str, verb: str, cwd: str | None = "") -> None:
        area = self.paths.area(path, cwd)
        if area:
            self.findings.append(Finding(path, area, verb))

    def command(self, command: str, shell: str, depth: int = 0) -> None:
        mentioned: dict[int, bool] = {}
        for segment in split(command, shell):
            for target in segment.redirects:
                self.add(target, ">")
            if not segment.words or self.paths.assign(segment.words):
                continue
            words = _command_words(segment.words)
            if not words:
                continue
            verb, args = _verb(words[0]), words[1:]
            if verb in CD_VERBS or verb in ("popd", "pop-location"):
                self.paths.cd(verb, args)
                continue
            if verb == "git":
                self.git(args)
            else:
                for path in self.targets(verb, args, depth):
                    self.add(path, words[0])
            if (
                segment.after_pipe
                and mentioned.get(segment.pipeline)
                and verb in PIPED_PATH_VERBS
                and all(PIPE_ITEM_RE.match(p) for p in _positionals(args, PATH_OPTIONS | DESTINATION_OPTIONS)[:1])
            ):
                self.findings.append(Finding("(paths from the pipeline)", "piped", words[0]))
            names_protected = any(self.paths.area(arg) for arg in args)
            mentioned[segment.pipeline] = mentioned.get(segment.pipeline, False) or names_protected
        for line in re.split(r"[\n;]", command):
            if WRITE_API_RE.search(line):
                match = PROTECTED_TEXT_RE.search(line)
                if match:
                    area = "addons/" if "addons" in match.group(0).lower() else ".claude/settings*.json"
                    self.findings.append(Finding(line.strip()[:80], area, "inline write"))

    def git(self, args: list[str]) -> None:
        i, work_dir = 0, ""
        while i < len(args) and args[i].startswith("-"):
            if args[i] in ("-C", "-c") and i + 1 < len(args):
                work_dir = args[i + 1] if args[i] == "-C" else work_dir
                i += 2
            else:
                i += 1
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
            positionals = _positionals(args, PATH_OPTIONS | DESTINATION_OPTIONS)
            has_path_option = bool(_option_values(args, PATH_OPTIONS))
            return positionals[-1:] if len(positionals) >= 2 or has_path_option else []
        if verb in COPY_REST_VERBS:
            return _positionals(args)[1:]
        if verb in WRITE_VERBS:
            return [a for a in args if not a.startswith("-")] + _option_values(args, PATH_OPTIONS)
        if verb == "dd":
            return [a[3:] for a in args if a.startswith("of=")]
        if verb in EXTRACT_VERBS:
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
                inner = Analysis(self.paths.child())
                inner.command(code, NESTED_SHELLS[verb], depth + 1)
                self.findings += inner.findings
        return []

    @staticmethod
    def nested_code(verb: str, args: list[str]) -> str:
        if verb in ("invoke-expression", "iex"):
            return " ".join(args)
        for index, arg in enumerate(args):
            if arg.lower() in NESTED_CODE_OPTIONS:
                return " ".join(args[index + 1 :])
        return ""


def check(command: str, shell: str, cwd: str, root: str) -> list[Finding]:
    """Findings for one Bash or PowerShell command run in cwd; empty when it writes to no ask-protected path of the
    project at root."""
    analysis = Analysis(Paths(root, cwd))
    analysis.command(command, shell)
    return analysis.findings


def reason(findings: list[Finding]) -> str:
    """The text shown in the permission prompt."""
    shown = sorted({f"{f.verb} -> {f.path}" for f in findings})
    areas = sorted({f.area for f in findings})
    return (
        f"Shell write to an ask-protected path ({', '.join(areas)}): {'; '.join(shown[:5])}. "
        "Agent permissions and dependencies change only with your OK (docs/AGENT_WORKFLOW.md §8.2)."
    )

