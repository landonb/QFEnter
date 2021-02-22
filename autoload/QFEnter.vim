" File:         autoload/QFEnter.vim
" Description:  Open a Quickfix item in a window you choose.
" Author:       yssl <http://github.com/yssl>
" License:      MIT License

" functions
function! s:ExecuteCC(lnumqf, isloclist)
	if a:isloclist
		let cmd = g:qfenter_ll_cmd
	else
		let cmd = g:qfenter_cc_cmd
	endif
	let cc_cmd = substitute(cmd, '##', a:lnumqf, "")
	execute cc_cmd
endfunction

function! s:ExecuteCN(count, isloclist)
	if a:isloclist
		let cmd = g:qfenter_lne_cmd
	else
		let cmd = g:qfenter_cn_cmd
	endif
	try
		execute cmd
	catch E553
		echo 'QFEnter: cnext: No more items'
	endtry
endfunction

function! s:ExecuteCP(count, isloclist)
	if a:isloclist
		let cmd = g:qfenter_lp_cmd
	else
		let cmd = g:qfenter_cp_cmd
	endif
	try
		execute cmd
	catch E553
		echo 'QFEnter: cprev: No more items'
	endtry
endfunction

" GetTabWinNR* functions
" return value: [tabpagenr, winnr, hasfocus, isnewtabwin]
" 	tabpagenr: tabpage number of the target window
"	winnr: window number of the target window
"   hasfocus: whether the target window already has focus or not
"   isnewtabwin: 
"	   - 'nt': the target window is in a newly created tab
"      - 'nw': the target window is a newly created window
"      - otherwise: the target window is one of existing windows

function! QFEnter#GetTabWinNR_Open()
	call s:GoToPreviousWindowOrFirstNonSpecial()
	return [tabpagenr(), winnr(), 1, '']
endfunction

function! QFEnter#GetTabWinNR_VOpen()
	call s:GoToPreviousWindowOrFirstNonSpecial()
	vnew
	return [tabpagenr(), winnr(), 1, 'nw']
endfunction

function! QFEnter#GetTabWinNR_HOpen()
	call s:GoToPreviousWindowOrFirstNonSpecial()
	new
	return [tabpagenr(), winnr(), 1, 'nw']
endfunction

function! QFEnter#GetTabWinNR_TOpen()
	let s:qfview = winsaveview()

	let s:modifier = ''
	let widthratio = winwidth(0)*&lines
	let heightratio = winheight(0)*&columns
	if widthratio > heightratio
		let s:modifier = s:modifier.''
		let s:qfresize = 'resize '.winheight(0)
	else
		let s:modifier = s:modifier.'vert'
		let s:qfresize = 'vert resize '.winwidth(0)
	endif

	if winnr() <= winnr('$')/2
		let s:modifier = s:modifier.' topleft'
	else
		let s:modifier = s:modifier.' botright'
	endif

	" add this line to match the behavior of VOpen() and HOpen()
	" (lb): Checking non-special won't matter in new tab, so skip:
	" 	" call s:GoToPreviousWindowOrFirstNonSpecial()
	wincmd p

	tabnew

	return [tabpagenr(), winnr(), 1, 'nt']
endfunction

function! s:GoToPreviousWindowOrFirstNonSpecial()
	wincmd p

	if exists('*SensibleOpenMoveCursorAvoidSpecial')
		" FIXME/2021-02-21: Publish this function to a new plugin.
		" Sorry folks! For now it's in a private Vim configurator.
		" - It's mostly useful to avoid sending file to project.vim
		"   window.
		call SensibleOpenMoveCursorAvoidSpecial()
	endif
endfunction

"qfopencmd: 'cc', 'cn', 'cp'
function! s:OpenQFItem(tabwinfunc, qfopencmd, qflnum)
	let lnumqf = a:qflnum

	if len(getloclist(0)) > 0
		let isloclist = 1
	else
		let isloclist = 0
	endif

	" for g:qfenter_prevtabwin_policy
	let prev_qf_tabnr = tabpagenr()
	let prev_qf_winnr = winnr()
	let orig_prev_qf_winnr = prev_qf_winnr

	" (lb): Remember the current buffer number (the quickfix buffer number),
	" and the current cursor position within it (which we'll restore later).
	" - We'll restore the quickfix cursor position after invoking the quickfix
	"   command (e.g., :cc). The quickfix command opens the indicated 'error'
	"   from the quickfix window, but it also moves the cursor back to the
	"   first column.
	"   - My use case: To preserve window jumping continuity. Specifically,
	"     I have (tmux + Vim) window jumpers wired to the Ctrl+Super+Arrow
	"     keys. So I can Ctrl-Super-Up and Ctrl-Super-Down back and forth
	"     between the quickfix and some window above it. But once I <CR> a
	"     quickfix line to open the file, the cursor resets to column 0, and
	"     then the Ctrl-Super-Up goes to the leftmost window, which is not
	"     necessarily the window to which it had been going! By restoring
	"     the cursor position, I can Ctrl-Super-Down to quickfix, <CR> to
	"     open a file in the window that I had just jumped downed from, and
	"     then I can Ctrl-Super-Down and Ctrl-Super-Up back and forth between
	"     those two windows. (Without restoring the cursor position, if it
	"     remains in the first column, then after <CR> to open a file and
	"     Ctrl-Super-Down to jump back down to quickfix, a Ctrl-Super-Up
	"     would move the cursor to the left-most window, and not necesarily
	"     to the window it was just in! And for me, the left-most window
	"     is normally the project tray, which I don't open quickfix errors
	"     in, so opening a quickfix error almost certainly breaks my jump
	"     flow. Refs: landonb/vim-tmux-navigator, landonb/dubs_project_tray.)
	let l:qfbufnr = bufnr('%')
	let l:qf_restore_cursor = getpos(".")

	" jump to a window or tab in which quickfix item to be opened
	exec 'let ret = '.a:tabwinfunc.'()'
	let target_tabnr = ret[0]
	let target_winnr = ret[1]
	let hasfocus = ret[2]
	let target_newtabwin = ret[3]
	if !hasfocus
		call s:JumpToTab(target_tabnr)
		call s:JumpToWin(target_winnr)
	endif

	if g:qfenter_prevtabwin_policy==#'qf'
		if target_newtabwin==#'nt'
			if prev_qf_tabnr >= target_tabnr
				let prev_qf_tabnr += 1
			endif
			call s:JumpToTab(prev_qf_tabnr)
			call s:JumpToWin(prev_qf_winnr)
			call s:JumpToTab(target_tabnr)
		else
			if target_newtabwin==#'nw' && prev_qf_winnr >= target_winnr
				let prev_qf_winnr += 1
			endif
			" (lb): See my previous comment. This is the path QFEnter always
			" takes for me (as I only use <CR> or double-click to open 'errors').
			" - I didn't change any code here, just highlighting the 2 JumpToWin
			"   calls here -- and because hasfocus=1, the `!hasfocus` branch was
			"   not taken, so this first JumpToWin(prev_qf_winnr) is a no-op;
			"   and then the cursor is moved to the target window to receive
			"   the open file (from which :cc will be run).
			call s:JumpToWin(prev_qf_winnr)
			call s:JumpToWin(target_winnr)
		endif
	elseif g:qfenter_prevtabwin_policy==#'none'
	elseif g:qfenter_prevtabwin_policy==#'legacy'
		if target_newtabwin==#'nt'
			if prev_qf_tabnr >= target_tabnr
				let prev_qf_tabnr += 1
			endif
			call s:JumpToTab(prev_qf_tabnr)
			call s:JumpToWin(prev_qf_winnr)
			call s:JumpToTab(target_tabnr)
		endif
	else
		echoerr 'QFEnter: '''.g:qfenter_prevtabwin_policy.''' is an undefined value for g:qfenter_prevtabwin_policy.'
	endif

	let excluded = 0
	for ft in g:qfenter_exclude_filetypes
		if ft==#&filetype
			let excluded = 1
			break
		endif
	endfor
	if excluded
		echo "QFEnter: Quickfix items cannot be opened in a '".&filetype."' window"
		wincmd p
		return
	endif

	" execute vim quickfix open commands
	if a:qfopencmd==#'cc'
		call s:ExecuteCC(lnumqf, isloclist)
	elseif a:qfopencmd==#'cn'
		call s:ExecuteCN(lnumqf, isloclist)
	elseif a:qfopencmd==#'cp'
		call s:ExecuteCP(lnumqf, isloclist)
	endif

	" (lb): See my previous comments. / Above, this plugin moved the cursor
	" to the target window and then called :cc (if user <CR>'ed or double-
	" clicked). Vim then highlighted the quickfix 'error' that the cursor
	" was on and opened the associated file. Vim also moved the cursor to
	" the first column in the quickfix buffer. / Here we restore the cursor
	" position, so that using the vim-tmux-navigator plugin window jumper
	" jumps back to where it was previously jumping in the quickfix buffer.
	" - Note that I only use <CR> and double-click to open quickfix errors,
	"   so this is the only use case I've tested. (Works for me!) But I half-
	"   assume this approach is generic enough for all the different QFEnter
	"   commands (at least those that don't open a new tab).
	" - First, resolve the quickfix buffer number to its window number (which
	"   may have changed, if a new window was opened). Then, call win_execute
	"   to run setpos() within that buffer (Vim silently activates that window,
	"   runs the command, then returns to the current window).
	let l:qfwinnr = bufwinid(l:qfbufnr)
	" Note that the code snippet I saw online calls 'redraw', but I haven't
	" found that necessary, e.g.,:
	"   call win_execute(l:qfwinnr, [
	"     \ 'call setpos(".", ' . string(l:qf_restore_cursor) . ')',
	"     \ 'redraw'
	"     \ ])
	call win_execute(l:qfwinnr, 'call setpos(".", ' . string(l:qf_restore_cursor) . ')')

	" check if switchbuf applied.
	" if useopen or usetab are applied with new window or tab command, close
	" the newly opened tab or window.
	let qfopened_tabnr = tabpagenr()
	let qfopened_winnr = winnr()
	if (match(&switchbuf,'useopen')>-1 || match(&switchbuf,'usetab')>-1)
		if target_newtabwin==#'nt'
			if target_tabnr!=qfopened_tabnr
				call s:JumpToTab(target_tabnr)
				call s:CloseCurrentTabAndJumpTo(qfopened_tabnr)
			endif
		elseif target_newtabwin==#'nw'
			if target_tabnr!=qfopened_tabnr	|"when 'usetab' applied
				call s:JumpToTab(target_tabnr)

				" Close The empty, newly created target window and jump to the quickfix window.
				" When returning from the tab containing the selecte item window to original tab,
				if g:qfenter_prevtabwin_policy==#'qf' || g:qfenter_prevtabwin_policy==#'leagcy'
					" the quickfix window should have a focus.
					call s:CloseCurrentWinAndJumpTo(prev_qf_winnr)
				else
					" the original 'wincmd p' window of quickfix should have a focus.
					" Just 'quit' makes the right or bottom window of the window close which has been newly created,
					" ti works correctly.
					quit
				endif

				call s:JumpToTab(qfopened_tabnr)

			elseif target_winnr!=qfopened_winnr
				call s:JumpToWin(target_winnr)
				call s:CloseCurrentWinAndJumpTo(qfopened_winnr)

				" To set quickfix window as a prevous window.
				"
				" Let's say we have opened an item with some 'nw' command which had already opened in a window A.
				" During the opening process, a new window N is created and 'cc' (or other) command 
				" make the focus jump to A due to the switchbuf option. So window history is quickfix Q - N - A.
				" Then N is closed. So it should be Q - A, meaning that 'wincmd p' in A make a jump to Q.
				" BUT the default behavior of vim is not like this. 'wincmd p' in A just stays in A.
				" This code reconnects Q and A in terms of prev win history.
				"
				" Note that checking if g:qfenter_prevtabwin_policy==#'qf' in not necessary
				" beause the prev window still should be the quickfix window even if the option is 'none'
				" becuase not a new window but one of existing windows is focused.
				call s:JumpToWin(orig_prev_qf_winnr)
				wincmd p
			endif
		" if the target window is one of existing windows, do nothing 
		" because the target window had focused and qfopencmd (such as cc) has moved the focus
		" to the right window, so there are no remaining artifacts.
		endif
	endif

	" restore quickfix window when tab mode
	if target_newtabwin==#'nt'
		if g:qfenter_enable_autoquickfix
			if isloclist
				exec s:modifier 'lopen'
			else
				exec s:modifier 'copen'
			endif
			exec s:qfresize
			call winrestview(s:qfview)
			wincmd p
		endif
	endif
endfunction

function! QFEnter#OpenQFItem(tabwinfunc, qfopencmd, keepfocus, isvisual)
	let qfbufnr = bufnr('%')
	let qflnum = line('.')

	if a:isvisual
		let vblnum2 = getpos("'>")[1]
	endif

	call s:OpenQFItem(a:tabwinfunc, a:qfopencmd, qflnum)

	if a:isvisual
		if qflnum==vblnum2
			if a:keepfocus==1
				redraw
				let qfwinnr = bufwinnr(qfbufnr)
				exec qfwinnr.'wincmd w'
			endif
		else
			let qfwinnr = bufwinnr(qfbufnr)
			exec qfwinnr.'wincmd w'
		endif
	else
		if a:keepfocus==1
			redraw
			let qfwinnr = bufwinnr(qfbufnr)
			exec qfwinnr.'wincmd w'
		endif
	endif
endfunction

fun! s:CloseCurrentWinAndJumpTo(return_winnr)
	let prevwinnr = a:return_winnr
	if prevwinnr > winnr()
		let prevwinnr = prevwinnr - 1
	endif

	quit

	call s:JumpToWin(prevwinnr)
endfun

fun! s:JumpToWin(winnum)
	exec a:winnum.'wincmd w'
endfun

fun! s:CloseCurrentTabAndJumpTo(return_tabnr)
	let prevtabnr = a:return_tabnr
	if prevtabnr > tabpagenr()
		let prevtabnr = prevtabnr - 1
	endif

	tabclose

	call s:JumpToTab(prevtabnr)
endfun

fun! s:JumpToTab(tabnum)
	exec 'tabnext' a:tabnum
endfun

" vim:set noet sw=4 sts=4 ts=4 tw=78:
