return {
	cmd = {
		"vscode-eslint-language-server",
		"--stdio",
	},
	filetypes = {
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
		"vue",
		"svelte",
	},
	root_markers = {
		"eslint.config.js",
		"eslint.config.mjs",
		"eslint.config.cjs",
		".eslintrc",
		".eslintrc.json",
		".eslintrc.js",
		"package.json",
		".git",
	},
	settings = {
		validate = "on",
		useESLintClass = false,
		experimental = {},
		format = false,
		quiet = false,
		onIgnoredFiles = "off",
		rulesCustomizations = {},
		run = "onType",
		problems = {
			shortenToSingleLine = false,
		},
		nodePath = vim.NIL,
		workingDirectory = {
			mode = "location",
		},
		codeActionOnSave = {
			enable = false,
			mode = "all",
		},
		codeAction = {
			disableRuleComment = {
				enable = true,
				location = "separateLine",
			},
			showDocumentation = {
				enable = true,
			},
		},
	},
	before_init = function(_, config)
		local root_dir = config.root_dir

		if not root_dir then
			return
		end

		config.settings = config.settings or {}

		config.settings.workspaceFolder = {
			uri = vim.uri_from_fname(root_dir),
			name = vim.fn.fnamemodify(root_dir, ":t"),
		}
	end,
	handlers = {
		["eslint/openDoc"] = function(_, result)
			if result and result.url then
				vim.ui.open(result.url)
			end

			return {}
		end,
		["eslint/confirmESLintExecution"] = function()
			return 4
		end,
		["eslint/probeFailed"] = function()
			vim.notify("Sunflower: ESLint probe failed", vim.log.levels.WARN)

			return {}
		end,
		["eslint/noLibrary"] = function()
			vim.notify("Sunflower: unable to find the ESLint library", vim.log.levels.WARN)

			return {}
		end,
	},
}
