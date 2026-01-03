vim9script

# ---- Load guard ---- #{{{
if exists('g:loaded_logicpat')
  finish
endif
g:loaded_logicpat = 1
#}}}

# ---- Defaults ---- #{{{
if !exists('g:logicpat_contains')
  g:logicpat_contains = 1
endif
if !exists('g:logicpat_flags')
  g:logicpat_flags = 'nw'
endif
if !exists('g:logicpat_auto_hlsearch')
  g:logicpat_auto_hlsearch = 1
endif
#}}}

import autoload 'logicpat.vim' as logicpat

# ---- Public commands ---- #{{{
command! -nargs=* LogicPat call logicpat.LogicPat(<q-args>, true) |
      \ if get(g:, 'logicpat_auto_hlsearch', 1) |
      \   v:hlsearch = 1 |
      \ endif
silent! command -nargs=* LP   call logicpat.LogicPat(<q-args>, true) |
      \ if get(g:, 'logicpat_auto_hlsearch', 1) |
      \   v:hlsearch = 1 |
      \ endif
command! -nargs=+ LPE echomsg logicpat.LogicPat(<q-args>, false)
command! -nargs=+ LogicPatFlags let g:logicpat_flags = <q-args>
silent! command -nargs=+ LPF let g:logicpat_flags = <q-args>
#}}}
