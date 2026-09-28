-- Autocommands

local group = vim.api.nvim_create_augroup("UserAutocmds", {
	clear = true,
})

-- Filetype detection
-- Files under config/lsp/ are only loaded when vim.lsp.enable() names a
-- server, so this cannot live there: "jsonl" is not an LSP server and the
-- detection (and syntax/jsonl.vim with it) would never run.
vim.filetype.add({
	extension = {
		jsonl = "jsonl",
		ndjson = "jsonl",
	},
})

-- Enable line numbers in normal editing windows
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = group,
	callback = function(event)
		if vim.bo[event.buf].buftype ~= "" then
			return
		end

		vim.wo.number = true
		vim.wo.relativenumber = true
		vim.wo.signcolumn = "yes"
	end,
})

-- Highlight yanked text
vim.api.nvim_create_autocmd("TextYankPost", {
	group = group,
	callback = function()
		(vim.hl or vim.highlight).on_yank({
			timeout = 150,
		})
	end,
})

-- Remove trailing whitespace before saving
local keep_trailing_whitespace = {
	markdown = true,
	text = true,
	gitcommit = true,
	gitsendemail = true,
	diff = true,
	patch = true,
}

local whitespace_line_limit = 20000

vim.api.nvim_create_autocmd("BufWritePre", {
	group = group,
	callback = function(event)
		local buf = event.buf
		local filetype = vim.bo[buf].filetype

		if keep_trailing_whitespace[filetype] then
			return
		end

		if vim.api.nvim_buf_line_count(buf) > whitespace_line_limit then
			return
		end

		local view = vim.fn.winsaveview()

		vim.cmd([[keeppatterns %s/\s\+$//e]])

		vim.fn.winrestview(view)
	end,
})

-- Restore cursor position when reopening a file
vim.api.nvim_create_autocmd("BufReadPost", {
	group = group,
	callback = function(event)
		local mark = vim.api.nvim_buf_get_mark(event.buf, '"')

		if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(event.buf) then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

-- Close temporary windows with q
vim.api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = {
		"help",
		"qf",
		"query",
		"man",
		"notify",
		"lspinfo",
	},
	callback = function(event)
		vim.keymap.set("n", "q", "<cmd>close<cr>", {
			buffer = event.buf,
			silent = true,
		})
	end,
})
