"=============================================================================
" runner.vim --- code runner for SpaceVim
" Copyright (c) 2016-2017 Shidong Wang & Contributors
" Author: Shidong Wang < wsdjeg at 163.com >
" URL: https://spacevim.org
" License: GPLv3
"=============================================================================

let s:JOB = SpaceVim#api#import('job')
let s:BUFFER = SpaceVim#api#import('vim#buffer')
let s:STRING = SpaceVim#api#import('data#string')
let s:FILE = SpaceVim#api#import('file')


let s:runners = {}

let s:bufnr = 0

function! s:open_win() abort
  if s:bufnr != 0 && bufexists(s:bufnr)
    exe 'bd ' . s:bufnr
  endif
  botright split __runner__
  let lines = &lines * 30 / 100
  exe 'resize ' . lines
  setlocal buftype=nofile bufhidden=wipe nobuflisted nolist
        \ noswapfile
        \ nowrap
        \ cursorline
        \ nospell
        \ nonu
        \ norelativenumber
        \ winfixheight
        \ nomodifiable
  set filetype=SpaceVimRunner
  nnoremap <silent><buffer> q :call SpaceVim#plugins#runner#close()<cr>
  let s:bufnr = bufnr('%')
  wincmd p
endfunction

let s:target = ''

function! s:async_run(runner) abort
  if type(a:runner) == type('')
    try
      let cmd = printf(a:runner, get(s:, 'selected_file', bufname('%')))
    catch
      let cmd = a:runner
    endtry
    call SpaceVim#logger#info('   cmd:' . string(cmd))
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 3, 0, ['[Running] ' . cmd, '', repeat('-', 20)])
    let s:lines += 3
    let s:start_time = reltime()
    let s:job_id =  s:JOB.start(cmd,{
          \ 'on_stdout' : function('s:on_stdout'),
          \ 'on_stderr' : function('s:on_stderr'),
          \ 'on_exit' : function('s:on_exit'),
          \ })
  elseif type(a:runner) == type([])
    let s:target = s:FILE.unify_path(tempname(), ':p')
    let compile_cmd = substitute(printf(a:runner[0], bufname('%')), '#TEMP#', s:target, 'g')
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 3, 0, [
          \ '[Compile] ' . compile_cmd,
          \ '[Running] ' . s:target,
          \ '',
          \ repeat('-', 20)])
    let s:lines += 4
    let s:start_time = reltime()
    let s:job_id =  s:JOB.start(compile_cmd,{
          \ 'on_stdout' : function('s:on_stdout'),
          \ 'on_stderr' : function('s:on_stderr'),
          \ 'on_exit' : function('s:on_compile_exit'),
          \ })
  elseif type(a:runner) == type({})
    let exe = call(a:runner.exe, [])
    let cmd = exe + a:runner.opt + [get(s:, 'selected_file', bufname('%'))]
    call SpaceVim#logger#info('   cmd:' . string(cmd))
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 3, 0, ['[Running] ' . join(cmd), '', repeat('-', 20)])
    let s:lines += 3
    let s:start_time = reltime()
    let s:job_id =  s:JOB.start(cmd,{
          \ 'on_stdout' : function('s:on_stdout'),
          \ 'on_stderr' : function('s:on_stderr'),
          \ 'on_exit' : function('s:on_exit'),
          \ })
  endif
endfunction

" @vimlint(EVL103, 1, a:id)
" @vimlint(EVL103, 1, a:data)
" @vimlint(EVL103, 1, a:event)
function! s:on_compile_exit(id, data, event) abort
  if a:data == 0
    let s:job_id =  s:JOB.start(s:target,{
          \ 'on_stdout' : function('s:on_stdout'),
          \ 'on_stderr' : function('s:on_stderr'),
          \ 'on_exit' : function('s:on_exit'),
          \ })
  else
    let s:end_time = reltime(s:start_time)
    let s:status.is_exit = 1
    let s:status.exit_code = a:data
    let done = ['', '[Done] exited with code=' . a:data . ' in ' . s:STRING.trim(reltimestr(s:end_time)) . ' seconds']
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, done)
    call s:update_statusline()
  endif
endfunction
" @vimlint(EVL103, 0, a:id)
" @vimlint(EVL103, 0, a:data)
" @vimlint(EVL103, 0, a:event)

function! s:update_statusline() abort
  redrawstatus!
endfunction

function! SpaceVim#plugins#runner#reg_runner(ft, runner) abort
  let s:runners[a:ft] = a:runner
  let desc = '[' . a:ft . '] ' . string(a:runner)
  let cmd = "call SpaceVim#plugins#runner#set_language('" . a:ft . "')"
  call add(g:unite_source_menu_menus.RunnerLanguage.command_candidates, [desc,cmd])
endfunction

" this func should support specific a runner
" the runner can be a string
function! SpaceVim#plugins#runner#open(...) abort
  let s:lines = 0
  let s:status = {
        \ 'is_running' : 0,
        \ 'is_exit' : 0,
        \ 'has_errors' : 0,
        \ 'exit_code' : 0
        \ }
  let s:selected_language = get(s:, 'selected_language', &filetype)
  let runner = get(a:000, 0, get(s:runners, empty(s:selected_language) ? &filetype : s:selected_language , ''))
  if !empty(runner)
    call s:open_win()
    call s:async_run(runner)
    call s:update_statusline()
  endif
endfunction

" @vimlint(EVL103, 1, a:job_id)
" @vimlint(EVL103, 1, a:data)
" @vimlint(EVL103, 1, a:event)
if has('nvim') && exists('*chanclose')
  let s:_out_data = ['']
  function! s:on_stdout(job_id, data, event) abort
    let s:_out_data[-1] .= a:data[0]
    call extend(s:_out_data, a:data[1:])
    if s:_out_data[-1] ==# ''
      call remove(s:_out_data, -1)
      let lines = s:_out_data
    else
      let lines = s:_out_data
    endif
    if !empty(lines)
      call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, lines)
    endif
    let s:lines += len(lines)
    let s:_out_data = ['']
    call s:update_statusline()
  endfunction

  let s:_err_data = ['']
  function! s:on_stderr(job_id, data, event) abort
    let s:_out_data[-1] .= a:data[0]
    call extend(s:_out_data, a:data[1:])
    if s:_out_data[-1] ==# ''
      call remove(s:_out_data, -1)
      let lines = s:_out_data
    else
      let lines = s:_out_data
    endif
    if !empty(lines)
      call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, lines)
    endif
    let s:lines += len(lines)
    let s:_out_data = ['']
    call s:update_statusline()
  endfunction
else
  function! s:on_stdout(job_id, data, event) abort
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, a:data)
    let s:lines += len(a:data)
    call s:update_statusline()
  endfunction

  function! s:on_stderr(job_id, data, event) abort
    let s:status.has_errors = 1
    call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, a:data)
    let s:lines += len(a:data)
    call s:update_statusline()
  endfunction
endif

function! s:on_exit(job_id, data, event) abort
  let s:end_time = reltime(s:start_time)
  let s:status.is_exit = 1
  let s:status.exit_code = a:data
  let done = ['', '[Done] exited with code=' . a:data . ' in ' . s:STRING.trim(reltimestr(s:end_time)) . ' seconds']
  call s:BUFFER.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, done)
  call s:update_statusline()

endfunction
" @vimlint(EVL103, 0, a:job_id)
" @vimlint(EVL103, 0, a:data)
" @vimlint(EVL103, 0, a:event)

function! s:debug_info() abort
  return []
endfunction


function! SpaceVim#plugins#runner#status() abort
  if s:status.is_running == 1
  elseif s:status.is_exit == 1
    return 'exit code : ' . s:status.exit_code 
          \ . '    time: ' . s:STRING.trim(reltimestr(s:end_time))
          \ . '    language: ' . get(s:, 'selected_language', &ft)
  endif
  return ''
endfunction

function! SpaceVim#plugins#runner#close() abort
  if s:status.is_exit == 0
    call s:JOB.stop(s:job_id)
  endif
  exe 'bd ' s:bufnr
endfunction

function! SpaceVim#plugins#runner#select_file() abort
  let s:lines = 0
  let s:status = {
        \ 'is_running' : 0,
        \ 'is_exit' : 0,
        \ 'has_errors' : 0,
        \ 'exit_code' : 0
        \ }
  let s:selected_file = browse(0,'select a file to run', getcwd(), '')
  let runner = get(a:000, 0, get(s:runners, &filetype, ''))
  let s:selected_language = &filetype
  if !empty(runner)
    call SpaceVim#logger#info('Code runner startting:')
    call SpaceVim#logger#info('selected file :' . s:selected_file)
    call s:open_win()
    call s:async_run(runner)
    call s:update_statusline()
  endif
endfunction

let g:unite_source_menu_menus =
      \ get(g:,'unite_source_menu_menus',{})
let g:unite_source_menu_menus.RunnerLanguage = {'description':
      \ 'Custom mapped keyboard shortcuts                   [SPC] p p'}
let g:unite_source_menu_menus.RunnerLanguage.command_candidates =
      \ get(g:unite_source_menu_menus.RunnerLanguage,'command_candidates', [])

function! SpaceVim#plugins#runner#select_language()
  " @todo use denite or unite to select language
  " and set the s:selected_language
  " the all language is keys(s:runners)
  Denite menu:RunnerLanguage
endfunction

function! SpaceVim#plugins#runner#set_language(lang)
  " @todo use denite or unite to select language
  " and set the s:selected_language
  " the all language is keys(s:runners)
  let s:selected_language = a:lang
endfunction
