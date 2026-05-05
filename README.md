# tablature.nvim

A guitar tablature editor for Neovim. Insert tab staff blocks into any buffer and edit them with a dedicated tab mode.

## Requirements

Neovim 0.12+

## Installation

```lua
vim.pack.add("https://github.com/hc-nolan/tablature.nvim")
require('tablature').setup()
```

See below for changing the default configuration.


## Usage

| Key          | Action                                    |
|--------------|-------------------------------------------|
| `<leader>ti` | Insert a new tab staff block below cursor |
| `<leader>te` | Enter tab editing mode                    |

Both are `<Plug>` mappings and can be remapped:

```lua
vim.keymap.set("n", "<leader>gi", "<Plug>(tablature-insert)")
vim.keymap.set("n", "<leader>ge", "<Plug>(tablature-edit)")
```

### Tab mode

Tab mode activates when your cursor is on a staff line. A legend showing all active keybinds is displayed below the staff. The mode indicator above the staff shows `m:<measure> b:<beat>/<total>`.

- `h`/`l` — move left/right one beat slot
- `H`/`L`, `{`/`}` — jump to previous/next measure
- `j`/`k` — move to lower/higher string
- `0`–`9` — write fret; type a second digit immediately for double-digit frets
- `<Space>` — clear cell
- `<BS>` — clear cell and move left
- `T` — change tuning (relabels the staff in place)
- `B` — set beat count for the current measure
- `C` — enter chord mode
- `<Esc>`/`q` — exit

Tab mode exits automatically when you leave the buffer or window.

### Chord mode

Press `C` to open a shape picker. Once a shape is selected:

- `<Tab>`/`<S-Tab>` — cycle shapes
- `+`/`=`/`-` — slide root fret up/down
- `<CR>` — insert chord at cursor (stays in chord mode)
- `C` — re-open the shape picker
- `<Esc>`/`q` — return to tab mode

A preview overlay shows the voicing at the cursor position. A legend below the staff shows the active shape, current root fret, and available keys.

## Configuration

```lua
require("tablature").setup({
  -- Register <leader>ti / <leader>te
  default_mappings = true,

  -- Beat slots per measure (4 = quarter notes, 8 = eighth notes, etc.)
  beats = 4,

  -- Measures inserted by <leader>ti
  default_measures = 8,

  -- Fill character and measure separator
  filler = "-",
  measure_sep = "|",

  -- Tunings available in the picker (strings listed low → high)
  tunings = {
    { name = "Standard", strings = { "E", "A", "D", "G", "B", "e" } },
    { name = "Drop D",   strings = { "D", "A", "D", "G", "B", "e" } },
  },

  -- Chord shape library.
  -- "default" shapes appear for all tunings; shapes under a tuning name
  -- appear only when that tuning is active (and override default on collision).
  -- Each shape is a low→high list of fret offsets from a root fret.
  -- "x" = muted string; numeric values shift together as the root fret changes.
  chords = {
    default = {
      ["Power 5th (E root)"] = { "0", "2", "2", "x", "x", "x" },
    },
    Standard = {
      ["Major (E shape)"] = { "0", "2", "2", "1", "0", "0" },
      -- ...
    },
    ["Drop D"] = {
      ["Power (Drop D)"] = { "0", "0", "0", "x", "x", "x" },
      -- ...
    },
  },

  -- Tab mode keybindings. Each entry needs key, func, and desc.
  -- Replacing this table entirely removes all defaults — include any you want to keep.
  tabmode_keys = {
    { key = "h",       func = function() require("tablature.mode").move_left()             end, desc = "Tab mode: move left" },
    { key = "<Left>",  func = function() require("tablature.mode").move_left()             end, desc = "Tab mode: move left" },
    { key = "l",       func = function() require("tablature.mode").move_right()            end, desc = "Tab mode: move right" },
    { key = "<Right>", func = function() require("tablature.mode").move_right()            end, desc = "Tab mode: move right" },
    { key = "H",       func = function() require("tablature.mode").move_previous_measure() end, desc = "Tab mode: move to previous measure" },
    { key = "L",       func = function() require("tablature.mode").move_next_measure()     end, desc = "Tab mode: move to next measure" },
    { key = "{",       func = function() require("tablature.mode").move_previous_measure() end, desc = "Tab mode: move to previous measure" },
    { key = "}",       func = function() require("tablature.mode").move_next_measure()     end, desc = "Tab mode: move to next measure" },
    { key = "j",       func = function() require("tablature.mode").move_next_string()      end, desc = "Tab mode: move to next string" },
    { key = "k",       func = function() require("tablature.mode").move_previous_string()  end, desc = "Tab mode: move to previous string" },
    { key = "<Space>", func = function() require("tablature.mode").clear_cell()            end, desc = "Tab mode: clear cell" },
    { key = "<BS>",    func = function() require("tablature.mode").clear_cell_and_move_left() end, desc = "Tab mode: clear cell" },
    { key = "<Esc>",   func = function() require("tablature.mode").exit()                  end, desc = "Tab mode: exit tab mode" },
    { key = "q",       func = function() require("tablature.mode").exit()                  end, desc = "Tab mode: exit tab mode" },
    { key = "T",       func = function() require("tablature.mode").pick_tuning()           end, desc = "Tab mode: change tuning" },
    { key = "C",       func = function() require("tablature.mode").insert_chord()          end, desc = "Tab mode: insert chord" },
    { key = "B",       func = function() require("tablature.mode").set_beats()             end, desc = "Tab mode: set measure beats" },
  },
})
```
