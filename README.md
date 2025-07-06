# ansible-doc.nvim
> Simple plugin to quickly peek Ansible modules and their documentation.

## Requirements
- Neovim >= 0.7.0
- Telescope
- Ansible installed, with `ansible-doc` in your `$PATH`

## Installation
```lua
-- lazy.nvim
{
  "avesst/ansible-doc.nvim",
  dependencies = { 'nvim-telescope/telescope.nvim' },
  ft = "yaml.ansible", -- optional
  keys = {
    { "<leader>am", "<cmd>AnsibleDoc search<cr>",        desc = "Search Ansible modules" },
    { "<leader>ad", "<cmd>AnsibleDoc search_cursor<cr>", desc = "Search cursor line for Ansible modules" }
  }
}
```

### Usage

> [!NOTE]
> On first load, the plugins uses `ansible-doc -l` to build a cache of all the installed modules on your system, which it then uses to search for modules. If you subsequently install/uninstall any modules, you need to run `:AnsibleDoc rebuild` to rebuild the cache.

#### Commands
- `:AnsibleDoc search`

    Brings up a Telescope window to search all installed modules. Pressing `<CR>` opens documentation.

- `:AnsibleDoc search_cursor`

    Parses the current line and tries to find a valid module directive, if so; opens the documentation.

- `:AnsibleDoc rebuild`

    Rebuild the module cache needed for the plugin to work.


The documentation opens up in a floating terminal window, in insert mode, displaying `ansible-doc` for your selected module. This terminal window have two key bindings in insert mode:

- `<ESC>` - Normal mode.
- `q` - close.
