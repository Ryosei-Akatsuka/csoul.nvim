local color = require("csoul.color")

local M = {}

local W, H = 120, 36
local LEFT_X, LEFT_W = 3, 40
local RIGHT_X = 47
local RIGHT_END = W - 4
local RIGHT_W = RIGHT_END - RIGHT_X + 1
local HEADER_Y, SEARCH_Y, HEADS_Y = 2, 4, 6
local LIST_Y, LIST_ROWS = 8, 23
local PANEL_Y, PANEL_ROWS = LIST_Y + 7, 14
local CODE_Y = PANEL_Y + 1
local CHIPS_Y = PANEL_Y + PANEL_ROWS + 3
local FOOTER_Y = H - 2
local ACTIVE_LINE = 8
local SAMPLE_FILE = "main.rs"
local GLYPH = "󱓻"

local SAMPLE = {
  { { "use", "keyword" }, { " " }, { "std", "module" }, { "::", "punct" }, { "collections", "module" }, { "::", "punct" }, { "HashMap", "type" }, { ";", "punct" } },
  {},
  { { "fn", "keyword" }, { " " }, { "main", "function" }, { "() {", "punct" } },
  {
    { "    " }, { "let", "keyword" }, { " " }, { "words", "variable" }, { " " }, { "=", "operator" }, { " " },
    { "[", "punct" }, { '"rust"', "string" }, { ", ", "punct" }, { '"code"', "string" }, { ", ", "punct" },
    { '"rust"', "string" }, { ", ", "punct" }, { '"design"', "string" }, { ", ", "punct" }, { '"code"', "string" }, { "];", "punct" },
  },
  {
    { "    " }, { "let", "keyword" }, { " " }, { "mut", "keyword" }, { " " }, { "counts", "variable" }, { " " }, { "=", "operator" },
    { " " }, { "HashMap", "type" }, { "::", "punct" }, { "new", "function" }, { "();", "punct" },
  },
  {},
  {
    { "    " }, { "for", "keyword" }, { " " }, { "word", "variable" }, { " " }, { "in", "keyword" }, { " " },
    { "words", "variable" }, { " {", "punct" },
  },
  {
    { "        " }, { "*", "operator" }, { "counts", "variable" }, { ".", "punct" }, { "entry", "function" }, { "(", "punct" },
    { "word", "variable" }, { ").", "punct" }, { "or_insert", "function" }, { "(", "punct" }, { "0", "number" }, { ")", "punct" },
    { " " }, { "+=", "operator" }, { " " }, { "1", "number" }, { ";", "punct" },
  },
  { { "    }", "punct" } },
  {},
  {
    { "    " }, { "let", "keyword" }, { " " }, { "mut", "keyword" }, { " " }, { "ranked", "variable" }, { ": ", "punct" },
    { "Vec", "type" }, { "<_>", "punct" }, { " " }, { "=", "operator" }, { " " }, { "counts", "variable" }, { ".", "punct" },
    { "into_iter", "function" }, { "()", "punct" }, { ".", "punct" }, { "collect", "function" }, { "();", "punct" },
  },
  {
    { "    " }, { "ranked", "variable" }, { ".", "punct" }, { "sort_by_key", "function" }, { "(|(_, ", "punct" },
    { "count", "variable" }, { ")| ", "punct" }, { "std::cmp::", "module" }, { "Reverse", "type" }, { "(", "punct" },
    { "*", "operator" }, { "count", "variable" }, { "));", "punct" },
  },
  {
    { "    " }, { "println!", "macro" }, { "(", "punct" }, { '"{ranked:?}"', "string" }, { ");", "punct" },
  },
  { { "}", "punct" } },
}

M.W, M.H = W, H
M.LEFT_X, M.SEARCH_Y, M.LIST_Y, M.LIST_ROWS = LEFT_X, SEARCH_Y, LIST_Y, LIST_ROWS

local function width(text)
  local plain = text:gsub("[\128-\191]", "")
  return #plain
end

local function fit(text, limit)
  if width(text) <= limit then
    return text
  end
  return text:sub(1, math.max(0, limit - 2)) .. ".."
end

local function filter_chips(counts)
  return {
    { key = "all", text = " ALL " .. counts.all .. " " },
    { key = "dark", text = " DARK " .. counts.dark .. " " },
    { key = "light", text = " LIGHT " .. counts.light .. " " },
  }
end

local function chip_start(counts)
  local total = 2
  for _, chip in ipairs(filter_chips(counts)) do
    total = total + width(chip.text)
  end
  return RIGHT_END - total + 1
end

function M.field(counts)
  local x = LEFT_X + 3
  return { x = x, y = SEARCH_Y, width = (chip_start(counts) - 2) - x + 1 }
end

local Canvas = {}
Canvas.__index = Canvas

local function new_canvas(fg, bg)
  local cells = {}
  for y = 1, H do
    cells[y] = {}
    for x = 1, W do
      cells[y][x] = { ch = " ", fg = fg, bg = bg, bold = false, italic = false }
    end
  end
  return setmetatable({ cells = cells }, Canvas)
end

function Canvas:put(x, y, text, style)
  style = style or {}
  if y < 0 or y >= H then
    return
  end
  local i = 0
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local xx = x + i
    if xx >= 0 and xx < W then
      local cell = self.cells[y + 1][xx + 1]
      cell.ch = ch
      if style.fg then
        cell.fg = style.fg
      end
      if style.bg then
        cell.bg = style.bg
      end
      cell.bold = style.bold or false
      cell.italic = style.italic or false
    end
    i = i + 1
  end
end

function Canvas:fill(x, y, w, h, bg)
  for yy = y, y + h - 1 do
    if yy >= 0 and yy < H then
      for xx = x, x + w - 1 do
        if xx >= 0 and xx < W then
          local cell = self.cells[yy + 1][xx + 1]
          cell.ch = " "
          cell.bg = bg
        end
      end
    end
  end
end

function Canvas:flatten()
  local lines, runs = {}, {}
  for y = 1, H do
    local parts, byte, run = {}, 0, nil
    for x = 1, W do
      local cell = self.cells[y][x]
      local key = table.concat({ cell.fg, cell.bg, cell.bold and "b" or "", cell.italic and "i" or "" }, "|")
      if not run or run.key ~= key then
        if run then
          run.stop = byte
          runs[#runs + 1] = run
        end
        run = {
          key = key,
          row = y - 1,
          start = byte,
          style = { fg = cell.fg, bg = cell.bg, bold = cell.bold, italic = cell.italic },
        }
      end
      parts[#parts + 1] = cell.ch
      byte = byte + #cell.ch
    end
    run.stop = byte
    runs[#runs + 1] = run
    lines[y] = table.concat(parts)
  end
  return lines, runs
end

local function hint(c, x, y, key, label, p)
  c:put(x, y, key, { fg = p.fg })
  c:put(x + #key + 1, y, label, { fg = color.mix(p.fg, p.bg, 0.54) })
  return #key + 1 + #label
end

local function draw_header(c, p, view)
  local rest
  if view.detected > 0 then
    rest = string.format("%d detected · nvim %s", view.detected, view.version)
  else
    rest = "no colorschemes found"
  end
  c:put(RIGHT_END - width(rest) + 1, HEADER_Y, rest, { fg = color.mix(p.fg, p.bg, 0.52) })
end

local function draw_search(c, p, view)
  local chips = filter_chips(view.counts)
  local x0 = chip_start(view.counts)
  local field_bg = color.mix(p.bg, p.surface, 0.38)
  c:fill(LEFT_X, SEARCH_Y, x0 - 2 - LEFT_X + 1, 1, field_bg)
  c:put(LEFT_X + 1, SEARCH_Y, "/", { fg = p.accent, bg = field_bg })

  local x = x0
  for _, chip in ipairs(chips) do
    local active = chip.key == view.filter
    local bg = active and p.accent or color.mix(p.bg, p.surface, 0.28)
    local fg = active and color.ink_on(p.accent) or color.mix(p.fg, p.bg, 0.48)
    c:put(x, SEARCH_Y, chip.text, { fg = fg, bg = bg, bold = active })
    x = x + width(chip.text) + 1
  end
end

local function draw_headers(c, p, view)
  c:put(LEFT_X, HEADS_Y, "Schemes", { fg = color.mix(p.fg, p.bg, 0.46) })
  c:put(LEFT_X + 9, HEADS_Y, string.format("%d / %d", view.shown, view.total), { fg = color.mix(p.fg, p.bg, 0.68) })
  c:put(RIGHT_X, HEADS_Y, "Preview", { fg = color.mix(p.fg, p.bg, 0.46) })
end

local function draw_list(c, p, view)
  if #view.rows == 0 then
    c:put(LEFT_X, LIST_Y, "No colorscheme matches.", { fg = color.mix(p.fg, p.bg, 0.52) })
    return
  end

  local muted = {}
  for j = 1, 10 do
    muted[j] = p.muted
  end

  for i, row in ipairs(view.rows) do
    local y = LIST_Y + i - 1
    local selected = row.index == view.selected

    if selected then
      c:fill(LEFT_X, y, LEFT_W, 1, color.mix(p.bg, p.accent, 0.10))
      c:put(LEFT_X, y, " ", { bg = p.accent })
    end

    c:put(LEFT_X + 2, y, string.format("%02d", row.index), {
      fg = selected and p.accent or color.mix(p.fg, p.bg, 0.65),
      bold = selected,
    })
    c:put(LEFT_X + 5, y, fit(row.entry.name, 16), {
      fg = selected and color.mix(p.fg, "#ffffff", 0.20) or color.mix(p.fg, p.bg, 0.05),
      bold = selected,
    })

    for j, colour in ipairs(row.palette and row.palette.mini or muted) do
      c:put(LEFT_X + 21 + j, y, GLYPH, { fg = colour })
    end

    local tag, tag_fg
    if selected then
      tag, tag_fg = "current", p.green
    elseif row.entry.light then
      tag, tag_fg = "light", p.amber
    else
      tag, tag_fg = "dark", color.mix(p.fg, p.bg, 0.52)
    end
    c:put(LEFT_X + LEFT_W - #tag, y, tag, { fg = tag_fg, bold = selected })
  end
end

local function draw_preview(c, p, entry)
  local section = color.mix(p.fg, p.bg, 0.46)

  c:put(RIGHT_X + 1, LIST_Y, fit(entry.name, RIGHT_W - 1), { fg = p.fg, bold = true })

  local ratio = color.contrast(p.fg, p.bg)
  local grade = ratio >= 7.0 and "AAA" or ratio >= 4.5 and "AA" or "A"
  local kind = entry.light and "LIGHT" or "DARK"
  local meta = table.concat({ fit(entry.source, 24), kind, entry.origin, string.format("%s %.1f", grade, ratio) }, "  ")
  c:put(RIGHT_X + 1, LIST_Y + 1, meta, { fg = color.mix(p.fg, p.bg, 0.55) })

  local palette_y = LIST_Y + 3
  for i, colour in ipairs(p.swatches) do
    local x = RIGHT_X + 1 + (i - 1) * 9
    c:fill(x, palette_y, 8, 1, colour)
    c:put(x, palette_y, " " .. colour, { fg = color.ink_on(colour) })
  end

  local label_y = LIST_Y + 6
  c:put(RIGHT_X + 1, label_y, "Syntax", { fg = section })
  c:put(RIGHT_END - width(SAMPLE_FILE) + 1, label_y, SAMPLE_FILE, { fg = color.mix(p.fg, p.bg, 0.70) })

  local panel_bg = entry.light and p.bg or color.mix(p.bg, "#000000", 0.30)
  local bottom_y = PANEL_Y + PANEL_ROWS + 1
  c:fill(RIGHT_X, PANEL_Y, RIGHT_W, PANEL_ROWS + 2, panel_bg)
  local inset = entry.light and 1 or 0
  c:fill(RIGHT_X + inset, CODE_Y + ACTIVE_LINE - 1, RIGHT_W - 2 * inset, 1, color.mix(panel_bg, p.accent, 0.065))

  if entry.light then
    local edge = { fg = p.border }
    c:put(RIGHT_X, PANEL_Y, "┌" .. string.rep("─", RIGHT_W - 2) .. "┐", edge)
    for y = CODE_Y, bottom_y - 1 do
      c:put(RIGHT_X, y, "│", edge)
      c:put(RIGHT_END, y, "│", edge)
    end
    c:put(RIGHT_X, bottom_y, "└" .. string.rep("─", RIGHT_W - 2) .. "┘", edge)
  end

  for i, segments in ipairs(SAMPLE) do
    local y = CODE_Y + i - 1
    c:put(RIGHT_X + 2, y, string.format("%2d", i), {
      fg = i == ACTIVE_LINE and p.amber or color.mix(p.fg, panel_bg, 0.62),
      bold = i == ACTIVE_LINE,
    })
    local x = RIGHT_X + 5
    for _, segment in ipairs(segments) do
      local style = segment[2] and p.syntax[segment[2]] or { fg = p.fg }
      c:put(x, y, segment[1], { fg = style.fg, bold = style.bold, italic = style.italic })
      x = x + width(segment[1])
    end
  end

  c:put(RIGHT_X + 1, CHIPS_Y, "UI", { fg = section })
  local x = RIGHT_X + 12
  local error_bg = color.mix(p.surface, p.bg, 0.16)
  local ui_chips = {
    { "Normal", p.bg, p.fg },
    { "Visual", p.selection, p.fg },
    { "Search", p.search, p.fg },
    { "Error", error_bg, p.red },
    { "Hint", error_bg, p.cyan },
  }
  for _, chip in ipairs(ui_chips) do
    local text = " " .. chip[1] .. " "
    c:put(x, CHIPS_Y, text, { fg = chip[3], bg = chip[2] })
    x = x + width(text) + 1
  end
end

local function draw_footer(c, p)
  local x = LEFT_X
  for _, pair in ipairs({
    { "j/k", "move" },
    { "/", "search" },
    { "tab", "filter" },
    { "enter", "apply" },
    { "esc", "close" },
  }) do
    x = x + hint(c, x, FOOTER_Y, pair[1], pair[2], p) + 3
  end
end

function M.build(view)
  local p = view.palette
  local c = new_canvas(p.fg, p.bg)
  draw_header(c, p, view)
  draw_search(c, p, view)
  draw_headers(c, p, view)
  draw_list(c, p, view)
  if view.entry then
    draw_preview(c, p, view.entry)
  end
  draw_footer(c, p)
  return c:flatten()
end

return M
