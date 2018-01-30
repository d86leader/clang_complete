"
" File: clang_complete.vim
" Author: Xavier Deguillard <deguilx@gmail.com>
"
" Description: Use of clang to complete in C/C++.
"
" Help: Use :help clang_complete
"

if exists('g:clang_complete_loaded')
  finish
endif
let g:clang_complete_loaded = 1

au FileType c,cpp,objc,objcpp call <SID>ClangCompleteInit()
au FileType c.*,cpp.*,objc.*,objcpp.* call <SID>ClangCompleteInit()

let b:clang_parameters = ''
let b:clang_user_options = ''
let b:my_changedtick = 0

" Store plugin path, as this is available only when sourcing the file,
" not during a function call.
let s:plugin_path = escape(expand('<sfile>:p:h'), '\')

" Older versions of Vim can't check if a map was made with <expr>
let s:use_maparg = v:version > 703 || (v:version == 703 && has('patch32'))

if has('python')
  let s:py_cmd = 'python'
  let s:pyfile_cmd = 'pyfile'
elseif has('python3')
  let s:py_cmd = 'python3'
  let s:pyfile_cmd = 'py3file'
endif

function! s:ClangCompleteInit()
  let l:bufname = bufname("%")
  if l:bufname == ''
    return
  endif

  if exists('g:clang_use_library') && g:clang_use_library == 0
    echoerr "clang_complete: You can't use clang binary anymore."
    echoerr 'For more information see g:clang_use_library help.'
    return
  endif

  if !exists('g:clang_auto_select')
    let g:clang_auto_select = 0
  endif

  if !exists('g:clang_complete_auto')
    let g:clang_complete_auto = 1
  endif

  if !exists('g:clang_close_preview')
    let g:clang_close_preview = 0
  endif

  if !exists('g:clang_complete_copen')
    let g:clang_complete_copen = 0
  endif

  if !exists('g:clang_hl_errors')
    let g:clang_hl_errors = 1
  endif

  if !exists('g:clang_periodic_quickfix')
    let g:clang_periodic_quickfix = 0
  endif

  if !exists('g:clang_user_options')
    let g:clang_user_options = ''
  endif

  if !exists('g:clang_trailing_placeholder')
    let g:clang_trailing_placeholder = 0
  endif

  if !exists('g:clang_compilation_database')
    let g:clang_compilation_database = ''
  endif

  if !exists('g:clang_library_path')
    let g:clang_library_path = ''
  endif

  if !exists('g:clang_complete_macros')
    let g:clang_complete_macros = 0
  endif

  if !exists('g:clang_complete_patterns')
    let g:clang_complete_patterns = 0
  endif

  if !exists('g:clang_debug')
    let g:clang_debug = 0
  endif

  if !exists('g:clang_sort_algo')
    let g:clang_sort_algo = 'priority'
  endif

  if !exists('g:clang_auto_user_options')
    let g:clang_auto_user_options = '.clang_complete, path'
  endif

  if !exists('g:clang_jumpto_declaration_key')
    let g:clang_jumpto_declaration_key = '<C-]>'
  endif

  if !exists('g:clang_jumpto_declaration_in_preview_key')
    let g:clang_jumpto_declaration_in_preview_key = '<C-W>]'
  endif

  if !exists('g:clang_jumpto_back_key')
    let g:clang_jumpto_back_key = '<C-T>'
  endif

  if !exists('g:clang_make_default_keymappings')
    let g:clang_make_default_keymappings = 1
  endif

  if !exists('g:clang_restore_cr_imap')
    let g:clang_restore_cr_imap = 'iunmap <buffer> <CR>'
  endif

  if !exists('g:clang_omnicppcomplete_compliance')
    let g:clang_omnicppcomplete_compliance = 0
  endif

  if g:clang_omnicppcomplete_compliance == 1
    let g:clang_complete_auto = 0
    let g:clang_make_default_keymappings = 0
  endif

  call LoadUserOptions()

  let b:my_changedtick = b:changedtick
  let b:clang_parameters = '-x c'

  if &filetype =~ 'objc'
    let b:clang_parameters = '-x objective-c'
  endif

  if &filetype == 'cpp' || &filetype == 'objcpp' || &filetype =~ 'cpp.*' || &filetype =~ 'objcpp.*'
    let b:clang_parameters .= '++'
  endif

  if expand('%:e') =~ 'h.*'
    let b:clang_parameters .= '-header'
  endif

  let g:clang_complete_lib_flags = 0

  if g:clang_complete_macros == 1
    let g:clang_complete_lib_flags = 1
  endif

  if g:clang_complete_patterns == 1
    let g:clang_complete_lib_flags += 2
  endif

  if s:initClangCompletePython() != 1
    return
  endif

  " Disable every autocmd that could have been set.
  augroup ClangComplete
    autocmd!
  augroup end

endfunction

"loads clang executable options from file
function! LoadUserOptions()
  let b:clang_user_options = ''

  let l:option_sources = split(g:clang_auto_user_options, ',')
  let l:remove_spaces_cmd = 'substitute(v:val, "\\s*\\(.*\\)\\s*", "\\1", "")'
  let l:option_sources = map(l:option_sources, l:remove_spaces_cmd)

  for l:source in l:option_sources
    if l:source == 'gcc' || l:source == 'clang'
      echo "'" . l:source . "' in clang_auto_user_options is deprecated."
      continue
    endif
    if l:source == 'path'
      call s:parsePathOption()
    elseif l:source == 'compile_commands.json'
      call s:findCompilationDatase(l:source)
    elseif l:source == '.clang_complete'
      call s:parseConfig()
    else
      let l:getopts = 'getopts#' . l:source . '#getopts'
      silent call eval(l:getopts . '()')
    endif
  endfor
endfunction

" Used to tell if a flag needs a space between the flag and file
let s:flagInfo = {
\   '-I': {
\     'pattern': '-I\s*',
\     'output': '-I'
\   },
\   '-F': {
\     'pattern': '-F\s*',
\     'output': '-F'
\   },
\   '-iquote': {
\     'pattern': '-iquote\s*',
\     'output': '-iquote'
\   },
\   '-include': {
\     'pattern': '-include\s\+',
\     'output': '-include '
\   }
\ }

let s:flagPatterns = []
for s:flag in values(s:flagInfo)
  let s:flagPatterns = add(s:flagPatterns, s:flag.pattern)
endfor
let s:flagPattern = '\%(' . join(s:flagPatterns, '\|') . '\)'


function! s:processFilename(filename, root)
  " Handle Unix absolute path
  if matchstr(a:filename, '\C^[''"\\]\=/') != ''
    let l:filename = a:filename
  " Handle Windows absolute path
  elseif s:isWindows() 
       \ && matchstr(a:filename, '\C^"\=[a-zA-Z]:[/\\]') != ''
    let l:filename = a:filename
  " Convert relative path to absolute path
  else
    " If a windows file, the filename may need to be quoted.
    if s:isWindows()
      let l:root = substitute(a:root, '\\', '/', 'g')
      if matchstr(a:filename, '\C^".*"\s*$') == ''
        let l:filename = substitute(a:filename, '\C^\(.\{-}\)\s*$'
                                            \ , '"' . l:root . '\1"', 'g')
      else
        " Strip first double-quote and prepend the root.
        let l:filename = substitute(a:filename, '\C^"\(.\{-}\)"\s*$'
                                            \ , '"' . l:root . '\1"', 'g')
      endif
      let l:filename = substitute(l:filename, '/', '\\', 'g')
    else
      " For Unix, assume the filename is already escaped/quoted correctly
      let l:filename = shellescape(a:root) . a:filename
    endif
  endif
  
  return l:filename
endfunction

"used in 
function! s:parseConfig()
  let l:local_conf = findfile('.clang_complete', getcwd() . ',.;')
  if l:local_conf == '' || !filereadable(l:local_conf)
    return
  endif

  let l:sep = '/'
  if s:isWindows()
    let l:sep = '\'
  endif

  let l:root = fnamemodify(l:local_conf, ':p:h') . l:sep

  let l:opts = readfile(l:local_conf)
  for l:opt in l:opts
    " Ensure passed filenames are absolute. Only performed on flags which
    " require a filename/directory as an argument, as specified in s:flagInfo
    if matchstr(l:opt, '\C^\s*' . s:flagPattern . '\s*') != ''
      let l:flag = substitute(l:opt, '\C^\s*\(' . s:flagPattern . '\).*'
                            \ , '\1', 'g')
      let l:flag = substitute(l:flag, '^\(.\{-}\)\s*$', '\1', 'g')
      let l:filename = substitute(l:opt,
                                \ '\C^\s*' . s:flagPattern . '\(.\{-}\)\s*$',
                                \ '\1', 'g')
      let l:filename = s:processFilename(l:filename, l:root)
      let l:opt = s:flagInfo[l:flag].output . l:filename
    endif

    let b:clang_user_options .= ' ' . l:opt
  endfor
endfunction

function! s:findCompilationDatase(cdb)
  if g:clang_compilation_database == ''
    let l:local_conf = findfile(a:cdb, getcwd() . ',.;')
    if l:local_conf != '' && filereadable(l:local_conf)
      let g:clang_compilation_database = fnamemodify(l:local_conf, ":p:h")
    endif
  endif
endfunction

function! s:parsePathOption()
  let l:dirs = map(split(&path, '\\\@<![, ]'), 'substitute(v:val, ''\\\([, ]\)'', ''\1'', ''g'')')
  for l:dir in l:dirs
    if len(l:dir) == 0 || !isdirectory(l:dir)
      continue
    endif

    " Add only absolute paths
    if matchstr(l:dir, '\s*/') != ''
      let l:opt = '-I' . shellescape(l:dir)
      let b:clang_user_options .= ' ' . l:opt
    endif
  endfor
endfunction

function! s:initClangCompletePython()
  if !has('python') && !has('python3')
    echoerr 'clang_complete: No python support available.'
    echoerr 'Cannot use clang library'
    echoerr 'Compile vim with python support to use libclang'
    return 0
  endif

  " Only parse the python library once
  if !exists('s:libclang_loaded')
    execute s:py_cmd 'import sys'
    execute s:py_cmd 'import json'

    execute s:py_cmd 'sys.path = ["' . s:plugin_path . '"] + sys.path'
    execute s:pyfile_cmd fnameescape(s:plugin_path) . '/libclang.py'

    execute s:py_cmd "vim.command('let l:res = ' + str(initClangComplete(vim.eval('g:clang_complete_lib_flags'),"
                                                    \."vim.eval('g:clang_compilation_database'),"
                                                    \."vim.eval('g:clang_library_path'))))"
    if l:res == 0
      return 0
    endif
    let s:libclang_loaded = 1
  endif
  execute s:py_cmd 'WarmupCache()'
  return 1
endfunction

function! s:isWindows()
  " Check for win32 is enough since it's true on win64
  return has('win32')
endfunction

let b:col = 0

function! ClangComplete(findstart, base)
  if a:findstart
    "finding where to start completion

    let l:line = getline('.')
    let l:start = col('.') - 1
    let l:wsstart = l:start
    if l:line[l:wsstart - 1] =~ '\s'
      while l:wsstart > 0 && l:line[l:wsstart - 1] =~ '\s'
        let l:wsstart -= 1
      endwhile
    endif
    while l:start > 0 && l:line[l:start - 1] =~ '\i'
      let l:start -= 1
    endwhile
    let b:col = l:start + 1
    return l:start

  else
    "performing completion

    if g:clang_debug == 1
      let l:time_start = reltime()
    endif

    execute s:py_cmd "completions, timer = getCurrentCompletions(vim.eval('a:base'))"
    execute s:py_cmd "vim.command('let l:res = ' + completions)"
    execute s:py_cmd "timer.registerEvent('Load into vimscript')"

    execute s:py_cmd 'timer.finish()'

    if g:clang_debug == 1
      echom 'clang_complete: completion time ' . split(reltimestr(reltime(l:time_start)))[0]
    endif
    return l:res
  endif
endfunction

" vim: set ts=2 sts=2 sw=2 expandtab :
