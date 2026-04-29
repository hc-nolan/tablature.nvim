# tablature.nvim

A guitar tablature editor for Neovim. Insert tab staff blocks into any buffer and edit them with a dedicated tab mode.

## Features

- Insert formatted tab staff blocks inline in any buffer
- Enter a tab editing mode with cursor-aware navigation
- Fret numbers written at the cursor advance automatically
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
| `0`–`9`         | Write fret number and advance   |
| `<Space>`       | Clear cell (write filler char)  |
| `<BS>`          | Move left and clear cell        |
| `<Esc>` / `q`   | Exit tab mode                   |

Tab mode exits automatically if you leave the buffer or window.

## Configuration

```lua
require("tablature").setup({
  -- Whether or not to register the default keymaps
  default_mappings = true,

  -- How many sub-columns per beat (4 = sixteenth notes, 2 = eighth notes, etc.)
  divisions = 4,

  -- Beats per measure
  beats_per_measure = 4,

  -- Number of measures inserted with <leader>ti
  default_measures = 4,

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
