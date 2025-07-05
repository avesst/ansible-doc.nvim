# ansible-doc.nvim
> Simple plugin to quickly view Ansible module documentation in a floating terminal window for the module name under the cursor.

## Requirements
- Neovim >= 0.7.0
- Ansible installed, with `ansible-doc` in your `$PATH`

## Installation
```lua
-- lazy.nvim
{
  "avesst/ansible-doc.nvim",
  keys = {{ "<leader>ad", "<cmd>AnsibleDoc search<cr>", desc = "Open Ansible module documentation" }}
}
```

### Usage

> [!NOTE]
> On first load, the plugins uses `ansible-doc -l` to build a cache of all the installed modules on your system, which it then uses to search for valid modules. If you install additional modules, use `:AnsibleDoc rebuild` to rebuild the cache.

- Place your cursor on a line containing a module directive (e.g., `ansible.builtin.lineinfile:`).
- Run `:AnsibleDoc search` or use configured keybinding.
- Terminal window opens in insert mode, displaying the documentation.
- Insert mode keybindings:
    - Press `<ESC>` for normal mode.
    - Press `q` to close.
