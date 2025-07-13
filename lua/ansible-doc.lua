local M = {}
local cache_dir_path = vim.fn.stdpath("cache") .. "/ansible-doc"
local cache_file_path = cache_dir_path .. "/plugins"

local plugin_types = {
  "become",
  "cache",
  "callback",
  "cliconf",
  "connection",
  "httpapi",
  "inventory",
  "lookup",
  "netconf",
  "shell",
  "vars",
  "module",
  "strategy",
  "test",
  "filter",
  "role",
  "keyword"
}

local function cache_init(force_build, on_complete)
  if vim.fn.isdirectory(cache_dir_path) == 0 then vim.fn.mkdir(cache_dir_path, "p") end

  if vim.fn.filereadable(cache_file_path) == 0 then
    local file = io.open(cache_file_path, "w")
    if file then io.close(file) end
  end

  local cache_size = vim.fn.getfsize(cache_file_path)

  if not force_build and cache_size > 0 then
    if on_complete then on_complete(true) end
    return
  end

  vim.notify("ansible-doc: Building plugin cache, please wait..")

  local lines = {}
  local remaining_types = vim.deepcopy(plugin_types)

  local function process_next()
    if #remaining_types == 0 then
      local cache, err = io.open(cache_file_path, "w")
      if not cache then
        vim.notify("ansible-doc: Can't open cache file for writing: " .. err, vim.log.levels.ERROR)
        return
      else
        cache:write(table.concat(lines))
        cache:close()
        vim.notify("ansible-doc: Cache built successfully.")
      end
      if on_complete then on_complete(true) end
      return
    end

    local current_type = table.remove(remaining_types, 1)
    vim.system({ "ansible-doc", "-t", current_type, "-l" }, {
      env = { ["PAGER"] = "cat" }
    }, function(obj)
      if obj.code == 0 then
        for line in string.gmatch(obj.stdout, "[^\n]+") do
          local plugin = string.match(line, "^(%S+)")
          if plugin then
            table.insert(lines, current_type .. ";" .. plugin .. "\n")
          end
        end
      else
        vim.notify("ansible-doc: Failed to build cache for type " .. current_type .. ": " .. (obj.stderr or ""),
          vim.log.levels.WARN)
      end
      process_next() -- Chain to next type
    end)
  end

  process_next() -- Start the chain
end

local function check_executable()
  if vim.fn.executable("ansible-doc") == 0 then
    vim.notify("ansible-doc: Can't find ansible-doc executable in $PATH", vim.log.levels.ERROR)
    return false
  end

  return true
end

local function load_cache()
  local plugins = {}

  local cache_lines = io.lines(cache_file_path)
  for line in cache_lines do
    for type, name in string.gmatch(line, "(.+)%;(.+)") do
      table.insert(plugins, { name = name, type = type })
    end
  end

  table.sort(plugins, function(a, b)
    return a.name < b.name
  end)

  return plugins
end

local function search_cache(search_string)
  local patterns = {
    { pattern = "^" .. search_string .. "$" },  -- FQCN
    { pattern = "^" .. search_string .. ":$" }, -- Keyword with colon match
    { pattern = "%." .. search_string .. "$" }, -- Resource match (short name)
  }

  for _, plugin in ipairs(load_cache()) do
    for _, pattern in ipairs(patterns) do
      if string.match(plugin.name, pattern.pattern) then
        return plugin
      end
    end
  end
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

local function view_documentation(plugin)
  local config = get_window_config()
  config.title = config.title .. plugin.name

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

  -- Keywords has a colon suffix which need to be removed before calling ansible-doc
  local name = string.gsub(plugin.name, ":", "")

  vim.fn.jobstart({ "ansible-doc", "-t", plugin.type, name },
    { term = true, env = { PAGER = pager } })

  vim.schedule(function()
    vim.api.nvim_command("startinsert")
  end)
end

function M.search_cursor()
  if not check_executable() then return end

  local function perform_search()
    local search_string = parse_line()
    if not search_string then
      vim.notify("ansible-doc: Couldn't find a possible module directive under the cursor", vim.log.levels.WARN)
      return
    end
    local plugin = search_cache(search_string)
    if not plugin then
      vim.notify("ansible-doc: Found no plugin that matches \"" .. search_string .. "\"", vim.log.levels.WARN)
      return
    end

    view_documentation(plugin)
  end

  cache_init(false, function(success)
    if success then
      vim.schedule(perform_search)
    end
  end)
end

local function calculate_picker_width()
  local width = 0

  for _, plugin in ipairs(load_cache()) do
    local plugin_width = #(plugin.name .. plugin.type)
    if plugin_width > width then width = plugin_width end
  end

  return math.floor(math.max(width + 10, vim.o.columns * 0.35))
end

function M.search(opts)
  if not check_executable() then return end

  local function open_picker()
    local actions = require "telescope.actions"
    local action_state = require "telescope.actions.state"
    local pickers = require "telescope.pickers"
    local finders = require "telescope.finders"
    local conf = require("telescope.config").values
    local entry_display = require "telescope.pickers.entry_display"

    local plugins = load_cache()

    local picker_width = calculate_picker_width()

    opts = opts or require("telescope.themes").get_dropdown {
      layout_config = { width = picker_width }
    }

    pickers.new(opts, {
      prompt_title = "Ansible plugins",
      finder = finders.new_table {
        results = plugins,
        entry_maker = function(entry)
          return {
            value = entry,
            display = function(display_entry)
              local displayer = entry_display.create {
                separator = "",
                items = {
                  { width = #display_entry.value.name },
                  { width = (opts.layout_config.width - (#display_entry.value.name + #display_entry.value.type) - 6) },
                  { width = #display_entry.value.type },
                }
              }

              return displayer {
                { display_entry.value.name, "TelescopeNormal" },
                { " " },
                { display_entry.value.type, "TelescopeResultsDiffUntracked" }
              }
            end,
            ordinal = entry.name, -- Filter on plugin name
          }
        end,
      },
      sorter = conf.file_sorter(opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          view_documentation(selection.value)
        end)
        return true
      end,
    }):find()
  end
  cache_init(false, function(success)
    if success then
      vim.schedule(open_picker)
    end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("AnsibleDoc", function(opts)
    if opts.args == "search" then M.search() end
    if opts.args == "search_cursor" then M.search_cursor() end
    if opts.args == "rebuild" then cache_init(true) end
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
