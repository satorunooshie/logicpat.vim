# logicpat.vim

**logicpat** is a Vim9-only logical pattern compiler that turns boolean
expressions into Vim search regexes.

It lets you combine words and patterns using logical operators like
**AND**, **OR**, and **NOT**, with implicit ANDs and optional raw-regex
escapes.

This plugin is a Vim9 script rewrite of Vim’s built-in *LogiPat.vim*
runtime plugin by Charles E. Campbell. It keeps the everyday usage
while reimplementing the parser with a shunting-yard algorithm and
adding a few small conveniences.

---

## Relationship to the original LogiPat

**logicpat** is inspired by the original *LogiPat.vim* by Charles E. Campbell
and is intended to be usable in largely the same way for common searches.

This section summarizes what is compatible, what is extended, and what differs.

### Usage compatibility

For typical interactive searches, logicpat can be used in the same style as
the original LogiPat.

Examples that work the same way:

```vim
:LogicPat foo bar
:LogicPat foo | bar
:LogicPat foo !bar
:LogicPat foo (bar | baz)
```

These expressions follow the same basic ideas:

* space-separated terms imply AND
* `|` expresses OR
* `!` negates a term or group
* parentheses group expressions

If you are used to typing logical search expressions rather than full regexes,
the workflow should feel familiar.

---

### Extensions and additions

logicpat adds several features that are not present in the original LogiPat:

* **Explicit operator precedence**

  * `!` binds tighter than `&`, which binds tighter than `|`
  * precedence is consistent and predictable even in complex expressions

* **Raw regex tokens**

  * `r"..."` or `r/.../` inserts a regex verbatim without wrapping
  * useful when mixing logical composition with hand-written regex

* **Sugar helper functions**

  * `word()`, `iword()` for word-boundary matches
  * `lit()` for literal (very-nomagic) text
  * `re()` for explicit regex fragments

* **Configurable contains behavior**

  * plain terms are wrapped as `.*term.*` by default
  * this can be disabled via `g:logicpat_contains`

* **Vim9 script implementation**

  * uses Vim9 script
  * designed to be split into `plugin/` and `autoload/`

---

### Behavioral differences

There are a few points where logicpat behaves differently and may require
attention when switching from the original LogiPat:

* **NOT (`!`) semantics**

  * `!pat` is implemented as *whole-line negation*
  * it matches lines that do not match the given pattern

* **Parsing model**

  * expressions are parsed structurally rather than expanded heuristically
  * ambiguous expressions are resolved by precedence rules instead of position

* **Scope**

  * logicpat focuses only on compiling logical expressions into regexes
  * it does not attempt to emulate all historical behaviors of the original

* **Search motion and flags**

  * the original `LogiPat.vim` called `search()` with no flags by default,
    which moves the cursor to the first match
  * logicpat always adds `nw` to the flags, so the cursor does not move on
    `:LogicPat`; use `n`/`N` to jump just like after a normal `/` search

* **Error handling**

  * syntax errors (unmatched parentheses, missing operands, unknown operators)
    are detected during parsing and reported as `LogicPat:` errors
  * in expressions that were previously “accepted but behaved oddly”, you may
    now see explicit errors instead

These differences are intentional and aim to make behavior explicit and
predictable.

---

### When to use which

* Use **logicpat** when you want:

  * logical composition of search patterns
  * predictable operator behavior
  * a Vim9-only, self-contained implementation

* Use the original **LogiPat** if you rely on:

  * legacy Vimscript environments
  * historical behaviors specific to that implementation

---

## Features

- Vim9 script only (no legacy VimL)
- Boolean operators:
  - `!` — NOT
  - `&` — AND
  - `|` — OR
- **Implicit AND**
  - `foo bar` → `foo & bar`
- Parentheses for grouping
- Optional *contains* wrapping (`.*pat.*`)
- Raw regex escape (`r"..."`, `r/.../`)
- Sugar helpers:
  - `word()`, `iword()`, `lit()`, `re()`
- Clean operator precedence and associativity
- Designed for interactive searching

---

## Requirements

- Vim **9.0+**
- Neovim is **not supported**

---

## Installation

Place the files in your runtimepath:

```

plugin/logicpat.vim
autoload/logicpat.vim

```

or install via your favorite plugin manager.

To avoid conflicts with Vim’s built-in `LogiPat.vim` runtime plugin, add

```vim
let g:loaded_logiPat = 1
```

to your `vimrc` before other plugins are loaded.

---

## Basic usage

Search using logical expressions:

```vim
:LogicPat foo bar
```

Equivalent to “both `foo` and `bar` appear on the same line”.

With OR:

```vim
:LogicPat foo | bar
```

With NOT:

```vim
:LogicPat foo !bar
```

Parentheses are supported:

```vim
:LogicPat foo & (bar | baz)
```

The resulting regex is placed in `/` and searched immediately.

---

## Implicit AND

Adjacent terms are automatically combined with AND:

```vim
:LogicPat foo bar baz
```

is equivalent to:

```vim
foo & bar & baz
```

---

## Raw regex escape

If you need full control over part of the pattern, use raw regex tokens:

```vim
:LogicPat foo r"\v(bar|baz)\d+" qux
```

Raw regex tokens are **not wrapped** and are inserted verbatim.
They bypass the default `.*...*` contains wrapping even when
`g:logicpat_contains` is enabled.

Supported forms:

```vim
r"foo.*bar"
r/foo.*bar/
```

---

## Sugar helpers

### `word()`

Match a whole word:

```vim
:LogicPat word(foo)
```

→ `\<foo\>`

### `iword()`

Case-insensitive whole word:

```vim
:LogicPat iword(foo)
```

### `lit()`

Literal (very nomagic):

```vim
:LogicPat lit(foo.bar)
```

### `re()`

Explicit regex (same as raw token):

```vim
:LogicPat re(foo.*bar)
```

---

## Contains wrapping

By default, plain terms are treated as “contains” matches:

```vim
foo
```

becomes:

```vim
.*foo.*
```

You can disable this behavior:

```vim
let g:logicpat_contains = 0
```

---

## Highlighting

`LogicPat` respects Vim's `'hlsearch'` option and can automatically enable
search highlighting after a logical search:

```vim
let g:logicpat_auto_hlsearch = 1   " default
```

When this is non‑zero, `:LogicPat` and `:LP` set `v:hlsearch` so that all
matches of the compiled pattern are highlighted immediately.  Set it to `0`
if you prefer to manage `:nohlsearch` / `v:hlsearch` yourself.

---

## Commands

| Command                  | Description                           |
| ------------------------ | ------------------------------------- |
| `:LogicPat {expr}`       | Compile `{expr}` and search           |
| `:LP {expr}`             | Short alias                           |
| `:LPE {expr}`            | Echo compiled regex without searching |
| `:LogicPatFlags {flags}` | Set default search flags              |
| `:LPF {flags}`           | Short alias                           |

Search flags are passed to `search()` (e.g. `n`, `w`, `c`).
By default, `LogicPat()` adds the flags `nw`, so the cursor does not
move; hit `n`/`N` afterward to jump to matches.

---

## Examples

```vim
:LogicPat error !debug
:LogicPat foo (bar | baz)
:LogicPat word(main) & !iword(test)
:LogicPat foo r"\v\d{4}-\d{2}-\d{2}"
```

---

## Design notes

* LogicPat is a **logical pattern compiler**, not a file browser or grep tool
* If you want to write raw regexes only, use Vim’s `/` directly
* NOT (`!`) is implemented as **whole-line negation**
* Parsing is done via a shunting-yard algorithm with explicit precedence and
  associativity
