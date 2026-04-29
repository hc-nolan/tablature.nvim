# tablature.nvim

A guitar tablature editor for Neovim. Insert tab staff blocks into any buffer and edit them with a dedicated tab mode.

## Features

- Insert formatted tab staff blocks inline in any buffer
- Enter a tab editing mode with cursor-aware navigation
- Write single or double-digit fret numbers at the cursor
- Beat-column highlighting and position indicator while editing
- Configurable tuning, time signature, and staff layout

## Requirements

- Neovim 0.12+

## Installation

Using `vim.pack` (Neovim 0.12):

```lua
vim.pack.add("https://github.com/hc-nolan/tablature.nvim")
```

No `setup()` call is required — the plugin initialises automatically with defaults. Call `setup()` only if you want to override options.

## Usage

### Keymaps

| Key           | Action                                      |
|---------------|---------------------------------------------|
| `<leader>ti`  | Insert a new tab staff block below cursor   |
| `<leader>te`  | Enter tab editing mode (cursor on a staff)  |

Both keys are mapped via `<Plug>` names, so you can remap them freely:

```lua
vim.keymap.set("n", "<leader>gi", "<Plug>(tablature-insert)")
vim.keymap.set("n", "<leader>ge", "<Plug>(tablature-edit)")
```

### Tab mode

While in tab mode the following keys are active:

| Key(s)          | Action                          |
|-----------------|---------------------------------|
| `h` / `<Left>`  | Move left one sub-column        |
| `l` / `<Right>` | Move right one sub-column       |
| `H`             | Move left one beat              |
| `L`             | Move right one beat             |
| `{`             | Move left one measure           |
| `}`             | Move right one measure          |
| `j`             | Move to next string (lower)     |
| `k`             | Move to previous string (higher)|
| `0`–`9`         | Write fret number (stays in place; type two digits for double-digit frets) |
| `<Space>`       | Clear cell (write filler char)  |
| `<BS>`          | Clear cell and move left        |
| `<Esc>` / `q`   | Exit tab mode                   |

Tab mode exits automatically if you leave the buffer or window.

Tab mode keys are configured separately from `default_mappings` via the `tabmode_keys` option. Each entry specifies a `key`, a `func` to call, and a `desc`. You can remap, remove, or extend them freely.

> **Note:** replacing `tabmode_keys` entirely removes all default bindings — include any defaults you want to keep.

The full set of defaults (copy this as a starting point):

```lua
require("tablature").setup({
  tabmode_keys = {
    { key = "h",       func = function() require("tablature.mode").move_left()            end, desc = "Tab mode: move left" },
    { key = "<Left>",  func = function() require("tablature.mode").move_left()            end, desc = "Tab mode: move left" },
    { key = "l",       func = function() require("tablature.mode").move_right()           end, desc = "Tab mode: move right" },
    { key = "<Right>", func = function() require("tablature.mode").move_right()           end, desc = "Tab mode: move right" },
    { key = "H",       func = function() require("tablature.mode").move_previous_beat()   end, desc = "Tab mode: move to previous beat" },
    { key = "L",       func = function() require("tablature.mode").move_next_beat()       end, desc = "Tab mode: move to next beat" },
    { key = "{",       func = function() require("tablature.mode").move_previous_measure() end, desc = "Tab mode: move to previous measure" },
    { key = "}",       func = function() require("tablature.mode").move_next_measure()    end, desc = "Tab mode: move to next measure" },
    { key = "j",       func = function() require("tablature.mode").move_next_string()     end, desc = "Tab mode: move to next string" },
    { key = "k",       func = function() require("tablature.mode").move_previous_string() end, desc = "Tab mode: move to previous string" },
    { key = "<Space>", func = function() require("tablature.mode").clear_cell()           end, desc = "Tab mode: clear cell" },
    { key = "<BS>",    func = function() require("tablature.mode").clear_cell_and_move_left() end, desc = "Tab mode: clear cell and move left" },
    { key = "<Esc>",   func = function() require("tablature.mode").exit()                 end, desc = "Tab mode: exit tab mode" },
    { key = "q",       func = function() require("tablature.mode").exit()                 end, desc = "Tab mode: exit tab mode" },
  },
})
```

## Configuration

```lua
require("tablature").setup({
  -- Whether or not to register the default keymaps (<leader>ti and <leader>te)
  default_mappings = true,

  -- Tab mode key bindings (see "Tab mode" section above for details)
  -- tabmode_keys = { ... },

  -- How many sub-columns per beat (4 = sixteenth notes, 2 = eighth notes, etc.)
  divisions = 4,

  -- Beats per measure
  beats_per_measure = 4,

  -- Number of measures inserted with <leader>ti
  default_measures = 2,

  -- String names, top to bottom (high to low pitch)
  strings = { "e", "B", "G", "D", "A", "E" },

  -- Character used to fill empty cells
  filler = "-",

  -- Measure separator character
  measure_sep = "|",
})
```

### Example: drop D tuning

```lua
require("tablature").setup({
  strings = { "e", "B", "G", "D", "A", "D" },
})
```

### Example: 3/4 time with eighth-note resolution

```lua
require("tablature").setup({
  beats_per_measure = 3,
  divisions = 2,
})
```
