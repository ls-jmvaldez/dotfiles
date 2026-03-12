-- vim: set foldmethod=marker :
-- ─────────────────────────────────────────────────────────────────────────────
-- Options {{{
vim.opt.tabstop        = 2
vim.opt.shiftwidth     = 2
vim.opt.smartindent    = true
vim.opt.ignorecase     = true
vim.opt.incsearch      = true
vim.opt.wrap           = false
vim.opt.number         = true
vim.opt.relativenumber = true
vim.opt.swapfile       = false
vim.opt.undofile       = true
vim.opt.cursorcolumn   = false
vim.opt.winborder      = "rounded"
vim.opt.signcolumn     = "yes"
vim.o.completeopt      = "menu,menuone,noselect,noinsert"
vim.o.scrolloff        = 8

-- 🔁 Auto-reload files changed outside of Neovim (Claude Code / OpenCode / formatters / git, etc.)
vim.opt.autoread       = true
vim.opt.updatetime     = 200 -- faster CursorHold -> quicker :checktime
-- }}}

-- Auto-reload trigger (generic safety net) {{{
local autoread_aug     = vim.api.nvim_create_augroup("AutoReadOnExternalChanges", { clear = true })
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	group = autoread_aug,
	callback = function()
		if vim.fn.mode() ~= "c" then
			vim.cmd("checktime")
		end
	end,
})
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	group = autoread_aug,
	callback = function()
		-- quiet little heads-up; comment out if you dislike notifications
		pcall(vim.notify, "Reloaded: file changed on disk", vim.log.levels.INFO)
	end,
})
-- }}}

--Keymaps / Leader {{{
local map       = vim.keymap.set
vim.g.mapleader = " "
map('n', '<leader>o', ':update<CR>:source<CR>', { desc = 'Write & source' })
map('n', '<leader>w', ':write<CR>', { desc = 'Write' })
map('n', '<leader>q', ':quit<CR>', { desc = 'Quit' })
map({ 'n', 'v', 'x' }, '<leader>y', '"+y<CR>', { desc = 'Yank to system' })
map({ 'n', 'v', 'x' }, '<leader>d', '"+d<CR>', { desc = 'Delete to system' })
-- }}}

-- Plugins (vim.pack) {{{
vim.pack.add({
	{ name = "vague.nvim",                                       src = "https://github.com/vague2k/vague.nvim" },
	{ name = "oil.nvim",                                         src = "https://github.com/stevearc/oil.nvim" },
	{ name = "mini.pick",                                        src = "https://github.com/echasnovski/mini.pick" },
	{ name = "mini.extra",                                       src = "https://github.com/echasnovski/mini.extra" },
	{ name = "mini.icons",                                       src = "https://github.com/echasnovski/mini.icons" },
	{ name = "render-markdown.nvim",                             src = "https://github.com/MeanderingProgrammer/render-markdown.nvim" },
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter" },
	{ src = "https://github.com/neovim/nvim-lspconfig" },
	{ src = "https://github.com/mason-org/mason.nvim" },
	{ src = "https://github.com/nvim-lua/plenary.nvim" },
	{ src = "https://github.com/ThePrimeagen/harpoon" },
	{ src = "https://github.com/tpope/vim-fugitive" },
	{ src = "https://github.com/lewis6991/gitsigns.nvim" },
	{ src = "https://github.com/seblyng/roslyn.nvim" },
	{ src = "https://github.com/christoomey/vim-tmux-navigator" },

	-- OpenCode integration (optional snacks UI + opencode.nvim)
	{ name = "snacks.nvim",                                      src = "https://github.com/folke/snacks.nvim" },
	{ name = "opencode.nvim",                                    src = "https://github.com/nickjvandyke/opencode.nvim" },
})
-- }}}

-- Utils {{{
local function project_root()
	local markers = {
		'.git', 'pnpm-workspace.yaml', 'yarn.lock', 'package-lock.json', 'package.json',
	}
	local found = vim.fs.find(markers, { upward = true, stop = vim.loop.os_homedir() })
	return (found[1] and vim.fs.dirname(found[1])) or vim.uv.cwd()
end

-- Pickers (mini.pick / mini.extra) {{{
require('mini.pick').setup({
	mappings = {
		mark          = '<C-x>',
		mark_all      = '<A-a>',
		choose        = '<CR>',
		choose_marked = '<A-q>',
	},
})
require('mini.extra').setup({})

-- Convenience locals
local pick = MiniPick

-- Find files (project / git)
vim.keymap.set('n', '<leader>f', function()
	pick.builtin.files({
		tool = 'git', -- use git ls-files when possible
		-- cwd = project_root() -- uncomment if you want explicit root
	})
end, { desc = 'Find files' })

-- Find anything (project grep, mini.pick window first)
vim.keymap.set('n', '<leader>/', function()
	pick.builtin.grep({
		tool = 'rg',         -- guaranteed ripgrep
		cwd  = vim.loop.cwd(), -- same dir as your shell
		-- no pattern here: mini.pick opens a small "grep pattern" prompt,
		-- then immediately shows the picker over all matches
	})
end, { desc = 'Find in project' })

-- }}}


-- Render Markdown (render-markdown.nvim) {{{
local ok_rm, rm = pcall(require, "render-markdown")
if ok_rm then
	rm.setup({
		enabled = false, -- start "raw", toggle on when you want
		-- render_modes = { 'n', 'c', 't' }, -- default; uncomment if you want to customize
	})

	local rm_aug = vim.api.nvim_create_augroup("RenderMarkdownKeymaps", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = rm_aug,
		pattern = "markdown",
		callback = function(ev)
			-- Toggle rendering for THIS buffer only
			vim.keymap.set("n", "<leader>mv", function()
				rm.buf_toggle()
			end, { buffer = ev.buf, desc = "Markdown: toggle render (buffer)" })

			-- Optional: open a side-by-side rendered preview
			vim.keymap.set("n", "<leader>mp", "<cmd>RenderMarkdown preview<cr>", {
				buffer = ev.buf,
				desc = "Markdown: preview (side)",
			})
		end,
	})
end
-- }}}

-- OpenCode (opencode.nvim) {{{
-- Snacks is optional: opencode.nvim can use snacks.input / snacks.picker for nicer UI
pcall(function()
	require("snacks").setup({
		input = {},
		picker = {},
		terminal = {}, -- harmless to enable even if you won't use it much
	})
end)

-- opencode.nvim reads config from this global.
-- Using tmux provider matches your “opencode in its own tmux pane” workflow.
vim.g.opencode_opts = {
	provider = {
		enabled = "tmux",
		tmux = {
			-- leave empty to use plugin defaults
			-- (you can later tune split direction / size / target session/window if you want)
		},
	},
}

-- Keymaps live under <leader>z... so they don't conflict with your existing <leader>o map.
map({ "n", "x" }, "<leader>za", function()
	require("opencode").ask("@this: ", { submit = true })
end, { desc = "OpenCode: ask (@this)" })

map({ "n", "x" }, "<leader>zx", function()
	require("opencode").select()
end, { desc = "OpenCode: select/actions" })

-- OpenCode: toggle tmux provider (your current default)
vim.keymap.set({ "n", "t" }, "<leader>zt", function()
	vim.g.opencode_opts.provider.enabled = "tmux"
	require("opencode").toggle()
end, { desc = "OpenCode: toggle (tmux)" })

-- Optional: quick healthcheck
map("n", "<leader>zh", "<cmd>checkhealth opencode<cr>", { desc = "OpenCode: checkhealth" })
-- }}}


-- Oil {{{
require('oil').setup({ show_hidden = false })
map('n', '<leader>e', ':Oil<CR>', { desc = 'Oil file explorer' })
-- }}}

-- Harpoon {{{
require('plenary')
require('harpoon').setup()
local mark, ui = require('harpoon.mark'), require('harpoon.ui')
map('n', '<leader>a', mark.add_file, { desc = 'Harpoon add' })
map('n', '<C-e>', ui.toggle_quick_menu, { desc = 'Harpoon menu' })
map('n', '<C-h>', function() ui.nav_file(1) end)
map('n', '<C-j>', function() ui.nav_file(2) end)
map('n', '<C-k>', function() ui.nav_file(3) end)
map('n', '<C-l>', function() ui.nav_file(4) end)
map('n', '<C-S-p>', ui.nav_prev)
map('n', '<C-S-n>', ui.nav_next)
-- }}}

-- Git (Fugitive + Gitsigns) {{{
-- gitsigns setup
require('gitsigns').setup({
	-- defaults are fine; tweak here if you want custom signs or blame formatting
})

-- keymaps (function form = no cmdline flicker)
map('n', '<leader>gph', require('gitsigns').preview_hunk, { desc = 'Git: preview hunk' })
map('n', '<leader>gt', require('gitsigns').toggle_current_line_blame, { desc = 'Git: toggle blame (line)' })

-- map('n', '<leader>gs', ':Git<CR>',            { desc = 'Git: status (Fugitive)' })
-- map('n', '<leader>gc', ':Git commit<CR>',     { desc = 'Git: commit' })
-- map('n', '<leader>gp', ':Git push<CR>',       { desc = 'Git: push' })
-- map('n', '<leader>gl', ':Git log --oneline<CR>', { desc = 'Git: log oneline' })
-- }}}

-- Treesitter {{{
require('nvim-treesitter.configs').setup({
	auto_install = true,
	ensure_installed = {
		'typescript', 'tsx', 'javascript', 'json', 'html', 'css',
		'python', 'lua', 'c_sharp', 'markdown', 'markdown_inline', 'yaml'
	},
	highlight = { enable = true },
})
-- }}}

-- Mason {{{
require('mason').setup({
	registries = {
		"github:mason-org/mason-registry",
		"github:Crashdummyy/mason-registry",
	},
	ensure_installed = {
		'lua_ls', 'pyright', 'clangd', 'clang-format', 'codelldb',
		'staticcheck', 'delve', 'impl',
		'vtsls', 'eslint-lsp',
		'tailwindcss-language-server',
	},
})
-- }}}

-- LSP {{{
local function on_attach(client, bufnr)
	if client.name == 'clangd' then
		client.server_capabilities.documentFormattingProvider = false
	end
end

local lsp_aug = vim.api.nvim_create_augroup('MyLspAttachAll', { clear = true })
vim.api.nvim_create_autocmd('LspAttach', {
	group = lsp_aug,
	callback = function(args)
		local bufnr  = args.buf
		local client = vim.lsp.get_client_by_id(args.data.client_id)

		local function map(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, noremap = true, desc = desc })
		end

		map('n', 'K', vim.lsp.buf.hover, 'LSP: hover')
		map('n', '<leader>gd', vim.lsp.buf.definition, 'LSP: go to definition')
		map('n', '<leader>gr', vim.lsp.buf.references, 'LSP: references')
		map('n', 'gi', vim.lsp.buf.implementation, 'LSP: go to implementation')
		map('n', 'gD', vim.lsp.buf.type_definition, 'LSP: type definition')
		map('n', '<leader>ca', vim.lsp.buf.code_action, 'LSP: code action')

		-- Enable LSP completion if supported (your old block, merged here)
		if client and client.supports_method and client:supports_method('textDocument/completion') then
			vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
		end
	end,
})

-- Roslyn (C#) LSP
local ok_roslyn, roslyn = pcall(require, 'roslyn')
if ok_roslyn then
	roslyn.setup({
		-- This often helps with perf / shutdown:
		-- "roslyn" = let Roslyn do filewatching, disable Neovim's for it
		-- "off"    = nuke filewatching entirely if things are still bad
		filewatching = "roslyn",
	})
end

-- Extra LSP settings for Roslyn
vim.lsp.config("roslyn", {
	settings = {
		["csharp|background_analysis"] = {
			dotnet_analyzer_diagnostics_scope = "openFiles",
			dotnet_compiler_diagnostics_scope = "openFiles",
		},
		["csharp|symbol_search"] = {
			dotnet_search_reference_assemblies = true,
		},
		["csharp|inlay_hints"] = {
			csharp_enable_inlay_hints_for_implicit_object_creation = true,
			csharp_enable_inlay_hints_for_implicit_variable_types = true,
		},
		["csharp|code_lens"] = {
			dotnet_enable_references_code_lens = true,
		},
	},
})

-- Per-server configs
local servers = {
	lua_ls = {
		on_attach = on_attach,
		settings = { Lua = { workspace = { library = vim.api.nvim_get_runtime_file('', true) } } },
	},
	pyright = { on_attach = on_attach },
	clangd = {
		on_attach = on_attach,
		cmd = {
			'clangd', '--background-index', '--clang-tidy', '--header-insertion=iwyu',
			'--completion-style=detailed', '--function-arg-placeholders', '--fallback-style=llvm',
			'--query-driver=/usr/bin/cc,/usr/bin/c++', '--compile-commands-dir=build_files',
		},
	},
	vtsls = {
		on_attach = on_attach,
		settings = {
			typescript = {
				preferences = { includeCompletionsForModuleExports = true, quoteStyle = 'auto' },
				inlayHints = {
					parameterNames = { enabled = 'all' },
					variableTypes = { enabled = true },
					propertyDeclarationTypes = { enabled = true },
					functionLikeReturnTypes = { enabled = true },
					enumMemberValues = { enabled = true },
				},
				format = { semicolons = 'insert' },
			},
			javascript = { inlayHints = { parameterNames = { enabled = 'all' } } },
			vtsls = {
				tsserver = { useSyntaxServer = 'auto', maxTsServerMemory = 4096 },
				experimental = { completion = { enableServerSideFuzzyMatch = true } },
			},
		},
	},
	tailwindcss = {
		on_attach = on_attach,
		filetypes = {
			'html', 'css', 'scss', 'sass', 'postcss',
			'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'vue', 'svelte',
		},
		root_markers = {
			'tailwind.config.js', 'tailwind.config.cjs', 'tailwind.config.ts',
			'postcss.config.js', 'postcss.config.cjs', 'postcss.config.ts',
			'package.json', '.git',
		},
		settings = {
			tailwindCSS = {
				experimental = {
					classRegex = {
						'cva%(([^)]*)%)', 'clsx?%(([^)]*)%)', 'twMerge%(([^)]*)%)',
						{ 'cn%(([^)]*)%)', '[\"\'`]([^\"\'`]*?)[\"\'`]' },
					},
				},
			},
		},
	},
}

for name, cfg in pairs(servers) do
	vim.lsp.config(name, cfg)
end
vim.lsp.enable(vim.tbl_keys(servers))
-- }}}

-- Formatting {{{
map('n', '<leader>lf', vim.lsp.buf.format, { desc = 'LSP format' })
-- }}}

-- Theme {{{
vim.cmd('colorscheme vague')
vim.cmd('hi statusline guibg=NONE')
-- }}}

-- UI: Cmdline {{{
vim.opt.cmdheight = 0                            -- hide when idle (0.9+)
vim.opt.shortmess:append({ W = true, F = true }) -- suppress “written” & extra file info noise
vim.opt.showcmd    = false                       -- don’t echo typed command fragments
vim.opt.ruler      = false                       -- don’t duplicate row/col (your statusline shows it)
-- Make the statusline global so there’s only one bar
vim.opt.laststatus = 3
-- }}}

-- Status Line {{{
-- Git branch function
local function git_branch()
	local branch = vim.fn.system("git branch --show-current 2>/dev/null | tr -d '\n'")
	if branch ~= "" then
		return "  " .. branch .. " "
	end
	return ""
end

-- File type with icon
local function file_type()
	local ft = vim.bo.filetype
	local icons = {
		lua = "[LUA]",
		python = "[PY]",
		javascript = "[JS]",
		html = "[HTML]",
		css = "[CSS]",
		json = "[JSON]",
		markdown = "[MD]",
		vim = "[VIM]",
		sh = "[SH]",
	}

	if ft == "" then
		return "  "
	end

	return (icons[ft] or ft)
end

-- LSP status
local function lsp_status()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	if #clients > 0 then
		return "  LSP "
	end
	return ""
end

-- File size
local function file_size()
	local size = vim.fn.getfsize(vim.fn.expand('%'))
	if size < 0 then return "" end
	if size < 1024 then
		return size .. "B "
	elseif size < 1024 * 1024 then
		return string.format("%.1fK", size / 1024)
	else
		return string.format("%.1fM", size / 1024 / 1024)
	end
end

-- Mode indicators with icons
local function mode_icon()
	local mode = vim.fn.mode()
	local modes = {
		n = "NORMAL",
		i = "INSERT",
		v = "VISUAL",
		V = "V-LINE",
		["\22"] = "V-BLOCK", -- Ctrl-V
		c = "COMMAND",
		s = "SELECT",
		S = "S-LINE",
		["\19"] = "S-BLOCK", -- Ctrl-S
		R = "REPLACE",
		r = "REPLACE",
		["!"] = "SHELL",
		t = "TERMINAL"
	}
	return modes[mode] or "  " .. mode:upper()
end

_G.mode_icon = mode_icon
_G.git_branch = git_branch
_G.file_type = file_type
_G.file_size = file_size
_G.lsp_status = lsp_status

vim.cmd([[
  highlight StatusLineBold gui=bold cterm=bold
]])

-- Function to change statusline based on window focus
local function setup_dynamic_statusline()
	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
		callback = function()
			vim.opt_local.statusline = table.concat {
				"  ",
				"%#StatusLineBold#",
				"%{v:lua.mode_icon()}",
				"%#StatusLine#",
				" │ %f %h%m%r",
				"%{v:lua.git_branch()}",
				" │ ",
				"%{v:lua.file_type()}",
				" | ",
				"%{v:lua.file_size()}",
				" | ",
				"%{v:lua.lsp_status()}",
				"%=",     -- Right-align everything after this
				"%l:%c  %P ", -- Line:Column and Percentage
			}
		end
	})
	vim.api.nvim_set_hl(0, "StatusLineBold", { bold = true })

	vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
		callback = function()
			vim.opt_local.statusline = "  %f %h%m%r │ %{v:lua.file_type()} | %=  %l:%c   %P "
		end
	})
end

setup_dynamic_statusline()

-- }}}
