"""The thin guard: which shell commands write to the ask-protected paths (docs/AGENT_WORKFLOW.md §8.2).

`Edit(**/.claude/settings.json)` and `Edit(**/addons/**)` ask rules stop the file tools, but not a shell write:
Claude Code checks a redirect or `tee` target only against Edit allow and deny rules, and cannot see where
`Copy-Item` or `cp` writes. The PreToolUse hook (`run hook guard`) passes Bash and PowerShell commands here and asks
the human when one writes to `.claude/settings*.json` or `addons/`. Everything else passes silently, so the agent
can work alone.

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
    "sudo", "env", "command", "builtin", "exec", "nohup", "time", "nice", "xargs", "call", ".",
    "do", "then", "else", "elif", "if", "while", "until", "!",
}  # fmt: skip
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
DESTINATION_OPTIONS = {"-destination", "-dest", "-t", "--target-directory", "-destinationpath"}
PATH_OPTIONS = {"-path", "-literalpath", "-filepath"}
# PowerShell options whose value is data, never a path that is written.
VALUE_OPTIONS = {
    "-value", "-inputobject", "-encoding", "-itemtype", "-type", "-filter", "-include", "-exclude", "-delimiter",
    "-name", "-propertytype", "-aclobject",
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
            self.cwd = self.resolve(dest[0])

    def remember(self, name: str, value: str | None, words: list[str]) -> None:
        """Record a variable. A value this cannot compute (`$p = Join-Path $root addons`, a `for` loop variable)
        still counts as protected when its words name a protected path."""
        name = name.lower()
        if name == "null":
            return
        self.vars[name] = self.expand(value) if value is not None else None
        area = None
        if self.vars[name] is None:
            area = next((a for a in (protected(w) or text_area(w) for w in words) if a), None)
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
            simple = len(words) == 3 and not words[2].startswith(("$(", "["))
            self.remember(var.group(1), words[2] if simple else None, words[2:])
            return [] if simple else words[2:]
        loop = words[1:] if words[0].lower() in ("for", "foreach") else words
        if len(loop) >= 3 and loop[1].lower() == "in" and (m := re.match(r"^\$?([A-Za-z_]\w*)$", loop[0])):
            self.remember(m.group(1), None, loop[2:])
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
            via_xargs = via_xargs or _verb(words[i]) == "xargs"
            i += 1
            while i < len(words) and (words[i].startswith("-") or words[i] == "{}"):
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

    def code(self, text: str, verb: str) -> None:
        """Inline interpreter code: a line that uses a file-writing API and names a protected path."""
        for line in text.splitlines():
            if WRITE_API_RE.search(line) and (area := text_area(line)):
                self.findings.append(Finding(line.strip()[:80], area, verb))

    def command(self, command: str, shell: str, depth: int = 0) -> None:
        mentioned: dict[int, bool] = {}
        piped_words: dict[int, list[str]] = {}
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
                self.simple(segment, words, via_xargs, mentioned, piped_words, depth)
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
                inner = Analysis(self.paths.child())
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
