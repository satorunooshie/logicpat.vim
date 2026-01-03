vim9script
# LogicPat: Vim9 script rewrite
# Adds:
# 1) configurable contains wrapping (g:logicpat_contains, default 1)
# 2) raw-regex tokens: r"..." and r/.../
# 3) sugar funcs: word(), iword(), lit(), re()
#
# Portions of the original idea inspired by LogiPat.vim
# Copyright (C) 1999-2011 Charles E. Campbell
#
# This code is a complete rewrite and does not contain original source code.

# ---- Regex builders ---- #{{{
def WrapMaybeContains(pat: string): string
  return (get(g:, 'logicpat_contains', 1) ? '.*' .. pat .. '.*' : pat)
enddef

def NotRegex(pat: string): string
  # Whole-string negation: "string does NOT match pat"
  return '^\%(' .. pat .. '\)\@!.*$'
enddef

def AndRegex(a: string, b: string): string
  return '\%(' .. a .. '\&' .. b .. '\)'
enddef

def OrRegex(a: string, b: string): string
  return '\%(' .. a .. '\|' .. b .. '\)'
enddef
#}}}

# ---- Operator table ---- #{{{
const OPS = {
  '!': { prec: 3, arity: 1, assoc: 'right', apply: function('NotRegex') },
  '&': { prec: 2, arity: 2, assoc: 'left',  apply: function('AndRegex') },
  '|': { prec: 1, arity: 2, assoc: 'left',  apply: function('OrRegex') },
}
#}}}

# ---- Token helpers ---- #{{{
def ReadQuoted(s: string, start: number): dict<any>
  # Reads " ... " with escapes \" and \\.
  var i = start
  if s[i] !=# '"'
    throw 'LogicPat: internal: ReadQuoted called at non-quote'
  endif
  i += 1
  var pat = ''
  while true
    if i >= len(s)
      throw 'LogicPat: unterminated quote at pos ' .. start
    endif
    var ch = s[i]
    if ch ==# '"'
      i += 1
      break
    endif
    if ch ==# '\'
      if i + 1 >= len(s)
        throw 'LogicPat: dangling escape in quote at pos ' .. i
      endif
      var nx = s[i + 1]
      if nx ==# '"' || nx ==# '\'
        pat ..= nx
        i += 2
        continue
      endif
      # unknown escape: keep backslash as-is (lets users write \v etc)
      pat ..= ch
      i += 1
      continue
    endif
    pat ..= ch
    i += 1
  endwhile
  return { text: pat, next: i }
enddef

def ReadSlashRaw(s: string, start: number): dict<any>
  # Reads r/.../ raw regex; delimiter is '/', backslash can escape '/'
  var i = start
  if s[i] !=# '/'
    throw 'LogicPat: internal: ReadSlashRaw called at non-/'
  endif
  i += 1
  var pat = ''
  while true
    if i >= len(s)
      throw 'LogicPat: unterminated r/.../ at pos ' .. start
    endif
    var ch = s[i]
    if ch ==# '/'
      i += 1
      break
    endif
    if ch ==# '\' && i + 1 < len(s) && s[i + 1] ==# '/'
      pat ..= '\/'
      i += 2
      continue
    endif
    pat ..= ch
    i += 1
  endwhile
  return { text: pat, next: i }
enddef

def ParseSugar(fn: string, arg: string): string
  # arg is already a regex string (no wrapping happens here)
  if fn ==# 'word'
    return '\<' .. arg .. '\>'
  elseif fn ==# 'iword'
    return '\c\<' .. arg .. '\>'
  elseif fn ==# 'lit'
    return '\V' .. arg
  elseif fn ==# 're'
    return arg
  else
    throw 'LogicPat: unknown function ' .. fn
  endif
enddef

def ReadFuncCall(s: string, start: number): dict<any>
  # Parses: name( ... )
  # Where ... is either:
  #   - "quoted"
  #   - r"quoted" / r/.../
  #   - bareword (until ')' respecting whitespace)
  #
  # Returns { text: compiledRegex, next: indexAfterCloseParen }
  var i = start
  var name = matchstr(s[i :], '^\h\w*')
  if name ==# ''
    throw 'LogicPat: expected function name at pos ' .. i
  endif
  i += len(name)
  if i >= len(s) || s[i] !=# '('
    throw 'LogicPat: expected ( after ' .. name .. ' at pos ' .. i
  endif
  i += 1

  # skip whitespace
  while i < len(s) && s[i] =~# '\s'
    i += 1
  endwhile
  if i >= len(s)
    throw 'LogicPat: unterminated function call ' .. name
  endif

  var arg = ''

  # arg: r"..." or r/.../
  if s[i] ==# 'r' && i + 1 < len(s) && (s[i + 1] ==# '"' || s[i + 1] ==# '/')
    i += 1
    if s[i] ==# '"'
      var q = ReadQuoted(s, i)
      arg = q.text
      i = q.next
    else
      var r = ReadSlashRaw(s, i)
      arg = r.text
      i = r.next
    endif

  # arg: "..."
  elseif s[i] ==# '"'
    var q = ReadQuoted(s, i)
    arg = q.text
    i = q.next

  # arg: bare until ')' (trim outer spaces)
  else
    var j = i
    while j < len(s) && s[j] !=# ')'
      j += 1
    endwhile
    if j >= len(s)
      throw 'LogicPat: unterminated function call ' .. name .. ' at pos ' .. start
    endif
    arg = trim(s[i : j - 1])
    i = j
  endif

  # skip whitespace
  while i < len(s) && s[i] =~# '\s'
    i += 1
  endwhile
  if i >= len(s) || s[i] !=# ')'
    throw 'LogicPat: expected ) to close ' .. name .. ' at pos ' .. i
  endif
  i += 1

  return { text: ParseSugar(name, arg), next: i }
enddef
#}}}

# ---- Tokenize ---- #{{{
# Token: { t: 'pat'|'op'|'(' | ')', v: string, pos: number }
def Tokenize(expr: string): list<dict<any>>
  var s = expr
  var i = 0
  var out: list<dict<any>> = []

  while i < len(s)
    if s[i] =~# '\s'
      i += 1
      continue
    endif

    # Sugar: name(...)
    if s[i] =~# '\h'
      # Lookahead for identifier + '(' with optional spaces before '('? keep strict: name(
      var name = matchstr(s[i :], '^\h\w*')
      var j = i + len(name)
      if name !=# '' && j < len(s) && s[j] ==# '('
        var fc = ReadFuncCall(s, i)
        add(out, { t: 'pat', v: fc.text, pos: i })
        i = fc.next
        continue
      endif
      # else fallthrough to bareword token below
    endif

    # Raw regex token: r"..." or r/.../
    if s[i] ==# 'r' && i + 1 < len(s) && (s[i + 1] ==# '"' || s[i + 1] ==# '/')
      var start = i
      i += 1
      if s[i] ==# '"'
        var q = ReadQuoted(s, i)
        add(out, { t: 'pat', v: q.text, pos: start })
        i = q.next
      else
        var r = ReadSlashRaw(s, i)
        add(out, { t: 'pat', v: r.text, pos: start })
        i = r.next
      endif
      continue
    endif

    # Quoted pattern: "..." (wrap maybe contains)
    if s[i] ==# '"'
      var q = ReadQuoted(s, i)
      add(out, { t: 'pat', v: WrapMaybeContains(q.text), pos: i })
      i = q.next
      continue
    endif

    # Operators / parens (allow && and ||)
    if s[i] =~# '[!()|&]'
      var ch = s[i]
      var start = i
      i += 1
      if (ch ==# '|' || ch ==# '&') && i < len(s) && s[i] ==# ch
        i += 1
      endif
      if ch ==# '(' || ch ==# ')'
        add(out, { t: ch, v: ch, pos: start })
      else
        add(out, { t: 'op', v: ch, pos: start })
      endif
      continue
    endif

    # Bareword (wrap maybe contains)
    var start = i
    var j = i
    while j < len(s) && s[j] !~# '\s' && s[j] !~# '[!()|&"]'
      j += 1
    endwhile
    if j == start
      throw 'LogicPat: unsupported char "' .. s[i] .. '" at pos ' .. i
    endif
    var word = s[start : j - 1]
    i = j
    add(out, { t: 'pat', v: WrapMaybeContains(word), pos: start })
  endwhile

  return out
enddef
#}}}

# ---- Implicit AND ---- #{{{
def NeedsImplicitAnd(prev: dict<any>, cur: dict<any>): bool
  var prev_is_value = (prev.t ==# 'pat' || prev.t ==# ')')
  var cur_is_valueish = (cur.t ==# 'pat' || cur.t ==# '(' || (cur.t ==# 'op' && cur.v ==# '!'))
  return prev_is_value && cur_is_valueish
enddef

def NormalizeTokens(toks: list<dict<any>>): list<dict<any>>
  if len(toks) == 0
    return toks
  endif
  var out: list<dict<any>> = [toks[0]]
  for idx in range(1, len(toks) - 1)
    var cur = toks[idx]
    var prev = out[-1]
    if NeedsImplicitAnd(prev, cur)
      add(out, { t: 'op', v: '&', pos: cur.pos })
    endif
    add(out, cur)
  endfor
  return out
enddef
#}}}

# ---- Apply operator ---- #{{{
def ApplyOp(op: string, stack: list<string>, pos: number): void
  if !has_key(OPS, op)
    throw 'LogicPat: unknown operator ' .. op .. ' near pos ' .. pos
  endif

  var spec = OPS[op]

  if spec.arity == 1
    if len(stack) < 1
      throw 'LogicPat: missing operand for ' .. op .. ' near pos ' .. pos
    endif
    var x = remove(stack, -1)
    add(stack, spec.apply(x))
    return
  elseif spec.arity == 2
    if len(stack) < 2
      throw 'LogicPat: missing operand for ' .. op .. ' near pos ' .. pos
    endif
    var b = remove(stack, -1)
    var a = remove(stack, -1)
    add(stack, spec.apply(a, b))
    return
  endif

  throw 'LogicPat: invalid arity for ' .. op .. ' near pos ' .. pos
enddef
#}}}

# ---- Shunting-yard helpers: precedence/associativity ---- #{{{
def ShouldPop(topop: string, newop: string): bool
  var tp = OPS[topop].prec
  var np = OPS[newop].prec

  if tp > np
    return true
  endif
  if tp < np
    return false
  endif

  # same precedence: left-assoc pops, right-assoc doesn't
  return OPS[newop].assoc ==# 'left'
enddef
#}}}

# ---- Compile: shunting-yard ---- #{{{
def ToRegex(expr: string): string
  var toks = NormalizeTokens(Tokenize(expr))
  if len(toks) == 0
    throw 'LogicPat: empty expression'
  endif

  var out: list<string> = []
  var ops: list<dict<any>> = [] # {op,pos}

  for tk in toks
    if tk.t ==# 'pat'
      add(out, tk.v)
      continue
    endif

    if tk.t ==# '('
      add(ops, { op: '(', pos: tk.pos })
      continue
    endif

    if tk.t ==# ')'
      while len(ops) > 0 && ops[-1].op !=# '('
        var top = remove(ops, -1)
        ApplyOp(top.op, out, top.pos)
      endwhile
      if len(ops) == 0
        throw 'LogicPat: too many ) near pos ' .. tk.pos
      endif
      remove(ops, -1) # pop '('
      continue
    endif

    if tk.t ==# 'op'
      var op = tk.v
      if !has_key(OPS, op)
        throw 'LogicPat: unknown operator ' .. op .. ' near pos ' .. tk.pos
      endif

      while len(ops) > 0 && ops[-1].op !=# '('
        var topop = ops[-1].op
        if !has_key(OPS, topop)
          throw 'LogicPat: unknown operator ' .. topop .. ' near pos ' .. ops[-1].pos
        endif

        if ShouldPop(topop, op)
          var top = remove(ops, -1)
          ApplyOp(top.op, out, top.pos)
        else
          break
        endif
      endwhile

      add(ops, { op: op, pos: tk.pos })
      continue
    endif
  endfor

  while len(ops) > 0
    var top = remove(ops, -1)
    if top.op ==# '('
      throw 'LogicPat: too many ( near pos ' .. top.pos
    endif
    ApplyOp(top.op, out, top.pos)
  endwhile

  if len(out) != 1
    throw 'LogicPat: invalid expression'
  endif
  return out[0]
enddef
#}}}

# ---- Public API ---- #{{{
export def LogicPat(pat: string, dosearch: bool = false, flags: string = ''): string
  var rx: string
  try
    rx = ToRegex(pat)
  catch
    echoerr v:exception
    return ''
  endtry

  if dosearch
    var fl = flags
    if fl ==# ''
      fl = get(g:, 'logicpat_flags', 'nw')
    endif
    @/ = rx
    search(rx, fl)
  endif

  return rx
enddef
#}}}
