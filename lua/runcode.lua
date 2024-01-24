local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local log = require("plenary.log")



-- Find project root
-- This might be useful to automatically detect e.g. the right python intepreter
Find_root = {}
if package.loaded['lspconfig'] then
	local util = require("lspconfig/util")

	local metatable = {
		__index = function()
			return function(fname)
				return util.root_pattern(".git")(fname) or
					util.path.dirname(fname)
			end
		end
	}
	setmetatable(Find_root, metatable)


	Find_root.python = function(fname)
		return util.root_pattern(".git", "setup.py", "setup.cfg", "pyproject.toml", "requirements.txt")(fname) or
			util.path.dirname(fname)
	end
	Find_root.js = function(fname)
		return util.root_pattern(".git", "package.json")(fname) or
			util.path.dirname(fname)
	end
	Find_root.ts = function(fname)
		return util.root_pattern(".git", "package.json", "tsconfig.json")(fname) or
			util.path.dirname(fname)
	end
	Find_root.go = function(fname)
		return util.root_pattern(".git", "go.mod")(fname) or
			util.path.dirname(fname)
	end
end



-- Setup logging
local log_levels = { "trace", "debug", "info", "warn", "error", "fatal" }

local function set_log_level()
	-- setup log level with vim.g
	-- vim.g.runner_log_level = "debug"
	local log_level = vim.env.RUNCODE_LOG_LEVEL or vim.g.runcode_log_level

	for _, level in pairs(log_levels) do
		if level == log_level then
			return log_level
		end
	end

	return "warn" -- default, if user hasn't set to one from log_levels
end

local logger = {}

logger = log.new({
	plugin = "runcode.log", -- will be saved to .cache/nvim/runner.log
	level = set_log_level(),
})



-- setup helper functions
local function map(func, array)
	local new_array = {}
	for i, v in ipairs(array) do
		new_array[i] = func(v)
	end
	return new_array
end

local function color_error(str)
	if str == "" then
		return str
	end
	return string.format("  || %s", str)
end


-- Setup runner module
local M = {}

RunnerConfig = {}

function M.get_config()
	return RunnerConfig
end

local function set_popup(ui_config)
	if ui_config.mode == "float" then
		local popup = Popup({
			enter = true,
			focusable = true,
			border = {
				padding = {
					top = 2
				},
				style = "rounded",
				text = {
					top = "Running... " .. vim.api.nvim_buf_get_name(0),
					center_align = "center",
				}
			},
			position = "50%",
			size = {
				width = ui_config.width * 100 .. "%",
				height = ui_config.height * 100 .. "%",
			},
		})

		-- unmount component when cursor leaves buffer
		popup:on(event.BufLeave, function()
			popup:unmount()
		end)

		-- Keymaps (only) for the popup
		popup:map('n', '<C-z>', function() M:background() end)
		-- TODO: set keymap for running the project from root

		return popup
	end
end


local function close_popup(popup, jobId, closeKeys)
	-- close popup key bindings
	for _, key in ipairs(closeKeys) do
		popup:map("n", key, function()
			vim.fn.jobstop(jobId)
			popup:unmount()
		end, { noremap = true })
	end
end



-- Detect file type automatically
-- kudos to plenary.nvim (https://github.com/nvim-lua/plenary.nvim)
local filetypes = {
	py = "python",
	js = "javascript",
	ts = "javascript",
	go = "go",
	md = "markdown"
}

local parts = function(filename)
	local current_match = filename:match("[^" .. "/" .. "].*")
	local possibilities = {}
	while current_match do
		current_match = current_match:match "[^.]%.(.*)"
		if current_match then
			table.insert(possibilities, current_match:lower())
		else
			return possibilities
		end
	end
	return possibilities
end

local detect_from_extension = function(filepath)
	local exts = parts(filepath)
	for _, ext in ipairs(exts) do
		local match = ext and filetypes[ext]
		if match then
			return match
		end
	end
	return ""
end

function M:run(tmpfile)
	local u_config = self.get_config().user_config
	u_config.before_run()

	local popup = set_popup(u_config.ui)

	local runfile = "%"
	local current_buffer = vim.api.nvim_buf_get_name(0)

	if tmpfile then
		runfile = tmpfile
	else
		runfile = current_buffer
	end

	local cmd = u_config.commands[detect_from_extension(current_buffer)]

	-- mount/open the component
	popup:mount()

	-- set popup specific options
	vim.api.nvim_set_option_value("wrap", true, { win = popup.winid })
	vim.api.nvim_set_option_value("number", true, { win = popup.winid })

	vim.api.nvim_buf_set_lines(popup.bufnr, 0, 0, false, { "--- process started ----" })

	local job_id = vim.fn.jobstart(cmd .. " " .. runfile, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			if data then
				vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, data)
				--vim.api.nvim_buf_set_lines(popup.bufnr, 0, 0, false, data)
			end
		end,
		on_stderr = function(_, data)
			if data then
				if popup.winid then
					vim.api.nvim_win_set_hl_ns(popup.winid, self.ns)
				end
				vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, map(color_error, data))
			end
		end,
		on_exit = function()
			vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, { "--- process exited ---" })
		end
	})

	if job_id > 0 then
		self.state.running = true
		self.state.job_id = job_id
		self.state.popup = popup
		close_popup(popup, job_id, u_config.close_keys)
		logger.debug("Job running:", job_id)
	else
		logger.warn("Job failed", job_id)
	end
end

function M:halt()
	self.state.running = false
	vim.fn.jobstop(self.state.job_id)
end

function M:background()
	self.state.background = true
	self.state.popup:hide()
end

function M:continue()
	self.state.background = false
	self.state.popup:show()
end

function M.setup(self, cfg)
	logger.trace("setup(): Setting up...")

	-- initialize program state
	local state = {
		popup = {},
		running = false,
		background = false
	}

	self.state = state

	-- set runner configurations
	local config = {
		user_config = nil,
	}

	local defaults = {
		-- choose default mode (valid term, tab, float, toggle)
		ui = {
			mode = "float",
			height = 0.8,
			width = 0.8,
		},
		before_run = function()
			vim.cmd(":w")
		end,
		close_keys = { "q", "<C-c>" },
		run_keys = {
			run = "<C-x>",
			run_root = "<C-p>" -- TODO
		},
		commands = {
			markdown = "glow",
			javascript = "deno run --allow-net --allow-run",
			python = "python -u",
			go = "go run",
			sh = "sh"
		}
	}

	config.user_config = vim.tbl_deep_extend('force', defaults, cfg or {})

	-- save config to global variable
	RunnerConfig = config

	-- set keymaps
	vim.keymap.set('n', '<C-x>', function()
		if self.state.background then
			M:continue()
		elseif self.state.running then
			M:halt()
		else
			M:run()
		end
	end)
	vim.keymap.set('v', '<C-x>', function()
		if self.state.background then
			M:continue()
		elseif self.state.running then
			M:halt()
		else
			M:run(M.get_visual_selection())
		end
	end)

	-- set highlight group and match regex
	vim.api.nvim_create_autocmd({ "WinEnter" }, {
		pattern = "*",
		command = "match RunnerError /||.*/"
	})
	self.ns = vim.api.nvim_create_namespace("runner")
	vim.api.nvim_set_hl(self.ns, "RunnerError", { fg = "red" })
end

-- should only be called for debug purposes
function M.print_config()
	print(vim.inspect(RunnerConfig))
end

-- TODO (handle this in plugin initialization e.g. with Lazy)
M:setup({
	commands = {
		python = "python3 -u",
	}
})

function M.get_visual_selection()
	local strip_ws = false
	local strip_len
	--
	-- exit visual mode in order to access the last selection
	local keys = vim.api.nvim_replace_termcodes('<ESC>', true, false, true)
	vim.api.nvim_feedkeys(keys, 'x', false)

	-- get the visual selection
	local line_start = vim.api.nvim_buf_get_mark(0, "<")
	local line_end = vim.api.nvim_buf_get_mark(0, ">")
	local lines = vim.api.nvim_buf_get_lines(0, line_start[1] - 1, line_end[1], false)

	-- write the selection to temporary file (/tmp/nvim.user/...)
	local tmpfile = vim.fn.tempname()
	file = io.open(tmpfile, "w")
	io.output(file)
	for i, v in ipairs(lines) do
		-- indent code correctly (by removing unnecessary whitespace from the start of rows)
		if i == 1 then
			_, strip_len = string.find(v, '^%s*')
			if strip_len > 0 then
				strip_ws = true
			end
		end

		if strip_ws then
			v = string.gsub(v, "^" .. string.rep("%s", strip_len), "")
		end

		io.write(v)
		io.write("\n")
	end
	io.close(file)

	return tmpfile
end

-- logger.debug("Complete config:", M.get_config())

return M
