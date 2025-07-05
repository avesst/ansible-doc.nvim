local M = {}
local cache_dir = vim.fn.stdpath("cache") .. "/ansible-doc"
local cache_file = cache_dir .. "/modules"
local fqcn = nil

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
  if vim.fn.executable("ansible-doc") > 0 then return true else return false end
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

local function search_cache(search_string)
  local pattern = search_string .. "$"

  -- If search string is not FQCN, prepend a '.' to the pattern to only match with full resource name of FQCN
  if not string.match(search_string, "%w+%.%w+%.%w+") then
    pattern = "%." .. pattern
  end

  for line in io.lines(cache_file) do
    local match = string.match(line, pattern)

    if match then
      return line
    end
  end

  return nil
end

local function parse_line()
  local line = vim.api.nvim_get_current_line()
  local pattern = "([%w_%.%-]+):$"

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
    title = "Ansible Documentation - " .. fqcn,
    title_pos = "center"
  }
end

local function view_documentation()
  local config = get_window_config()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_open_win(buf, true, config)
  vim.api.nvim_command("terminal ansible-doc " .. fqcn)
  vim.api.nvim_set_option_value("buftype", "terminal", { buf = buf })
  vim.keymap.set("t", "<ESC>", "<C-\\><C-n>", { buffer = true, silent = true })
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        vim.api.nvim_command("bdelete!")
      end)
    end
  })
  vim.api.nvim_command("startinsert")
end

function M.search()
  if not check_executable() then
    vim.notify("ansible-doc: Can't find ansible-doc executable in $PATH", vim.log.levels.ERROR)
    return
  end

  local search_string = parse_line()
  if not search_string then
    vim.notify("ansible-doc: Couldn't find a module directive under the cursor", vim.log.levels.WARN)
    return
  end

  fqcn = search_cache(search_string)
  if not fqcn then
    vim.notify("ansible-doc: Found no module that matches \"" .. search_string .. "\"", vim.log.levels.WARN)
    return
  end

  view_documentation()
end

function M.init()
  init_cache()
  build_cache()

  vim.api.nvim_create_user_command("AnsibleDoc", function(opts)
    if opts.args == 'search' then M.search() end
    if opts.args == 'rebuild' then build_cache(true) end
  end, {
    nargs = 1,
    complete = function(arg_lead, _, _)
      local options = { "search", "rebuild" }
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
