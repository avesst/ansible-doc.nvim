local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values

local M = {}
local cache_dir = vim.fn.stdpath("cache") .. "/ansible-doc"
local cache_file = cache_dir .. "/modules"

local function init_cache()
  -- Set up cache directory
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, "p")
  end

  local file = io.open(cache_file, "r")
  if file then
    file:close()
    return
  end

  file = io.open(cache_file, "w")
  if file then
    file:close()
  else
    vim.notify("ansible-doc: Error: Could not create cache file!")
  end
end

local function check_executable()
  if vim.fn.executable("ansible-doc") > 0 then
    return true
  else
    vim.notify("ansible-doc: Can't find ansible-doc executable in $PATH", vim.log.levels.ERROR)
    return false
  end
end

local function build_cache(force_rebuild)
  local cache, err = io.open(cache_file, "r")
  if not cache then
    vim.notify("ansible-doc: Can't open cache file for reading: " .. err, vim.log.levels.ERROR)
    return nil
  end

  if force_rebuild then
    cache = io.open(cache_file, "w")
    if cache then cache:close() end
  else
    local cache_size = cache:seek("end")
    if cache_size ~= 0 then return end
  end

  vim.notify("ansible-doc: Building module cache. Use :AnsibleDoc rebuild to rebuild cache.")

  local result = vim.system({ "ansible-doc", "-l" }, {
    env = { { "PAGER", "cat" } }
  }):wait()

  cache, err = io.open(cache_file, "a")
  if not cache then
    vim.notify("ansible-doc: Can't open cache file for appending: " .. err, vim.log.levels.ERROR)
  end

  for line in string.gmatch(result.stdout, "[^\n]+") do
    local module = string.match(line, "^(%S+)")
    if module then
      if cache then
        cache:write(module .. "\n")
      end
    end
  end

  if cache then
    cache:close()
  end
end

local function load_cache()
  local lines = io.lines(vim.fn.stdpath("cache") .. "/ansible-doc/modules")
  local modules = {}

  for line in lines do
    table.insert(modules, line)
  end

  return modules
end

local function search_cache(search_string)
  local pattern = search_string .. "$"

  -- If search string is not FQCN, prepend a '.' to the pattern to only match with full resource name of FQCN
  if not string.match(search_string, "%w+%.%w+%.%w+") then
    pattern = "%." .. pattern
  end

  for _, module in ipairs(load_cache()) do
    local match = string.match(module, pattern)

    if match then
      return module
    end
  end

  return nil
end

local function parse_line()
  local line = vim.api.nvim_get_current_line()
  local pattern = "([%w_%.%-]+):"

  for match in line:gmatch(pattern) do
    return match
  end

  return nil
end

local function get_window_config()
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.9)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = "Ansible Documentation - ",
    title_pos = "center"
  }
end

local function view_documentation(fqcn)
  local config = get_window_config()
  config.title = config.title .. fqcn

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        vim.api.nvim_command("bdelete!")
      end)
    end
  })

  vim.api.nvim_open_win(buf, true, config)
  vim.keymap.set("t", "<ESC>", "<C-\\><C-n>", { buffer = true, silent = true })

  local pager = "less -+F"
  if vim.o.incsearch then pager = pager .. " --incsearch" end

  vim.fn.jobstart({ "ansible-doc", fqcn }, { term = true, env = { PAGER = pager } })

  vim.schedule(function()
    vim.api.nvim_command("startinsert")
  end)
end

function M.search_cursor()
  if not check_executable() then return end

  local search_string = parse_line()
  if not search_string then
    vim.notify("ansible-doc: Couldn't find a possible module directive under the cursor", vim.log.levels.WARN)
    return
  end

  local fqcn = search_cache(search_string)
  if not fqcn then
    vim.notify("ansible-doc: Found no module that matches \"" .. search_string .. "\"", vim.log.levels.WARN)
    return
  end

  view_documentation(fqcn)
end

function M.search(opts)
  if not check_executable() then return end

  local modules = load_cache()
  opts = opts or require("telescope.themes").get_dropdown {}
  pickers.new(opts, {
    prompt_title = "Ansible modules",
    finder = finders.new_table {
      results = modules
    },
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        view_documentation(selection[1])
      end)
      return true
    end
  }):find()
end

function M.init()
  init_cache()
  build_cache()

  vim.api.nvim_create_user_command("AnsibleDoc", function(opts)
    if opts.args == "search" then M.search() end
    if opts.args == "search_cursor" then M.search_cursor() end
    if opts.args == "rebuild" then build_cache(true) end
  end, {
    nargs = 1,
    complete = function(arg_lead, _, _)
      local options = { "search", "search_cursor", "rebuild" }
      local matches = {}

      for _, option in ipairs(options) do
        if option:match("^" .. arg_lead) then
          table.insert(matches, option)
        end
      end

      return matches
    end
  })
end

return M
