-- commandHints.lua - What each console command takes and does, matched
-- against what's typed so far. The console (ui/command.lua) lists these and
-- draws the matches above its input line.
local hints = {}

-- { name, args, description, sub = { subcommands, same shape } }
hints.commands = {
    { "help", nil, "List commands and shortcuts" },
    { "clear", nil, "Clear the output" },
    { "cont", nil, "Close the console (also: continue)" },
    { "exit", nil, "Quit the game" },
    { "reload", nil, "Restart the game" },
    { "tp", "[x] [y]", "Teleport the player (default 0 0)" },
    { "save", nil, "Quick save" },
    { "load", nil, "Quick load" },
    { "boss", nil, "Boss tools (bare: spawn at you)", sub = {
        { "spawn", "[x] [y]", "Spawn a boss (default: at you)" },
        { "despawn", "<id|all>", "Remove a boss, or all of them" },
        { "list", nil, "Count the active bosses" },
        { "damage", "<id> [amount]", "Hurt a boss (default 100)" },
    } },
    { "profile", nil, "Profiler", sub = {
        { "report", "[min_ms]", "Print timings over min_ms" },
        { "reset", nil, "Clear the timings" },
        { "on", nil, "Enable the profiler" },
        { "off", nil, "Disable the profiler" },
        { "export", "[file]", "Save timings as JSON" },
    } },
    { "benchmark", nil, "Benchmark", sub = {
        { "run", "[seconds]", "Reset profiler, show overlay" },
        { "report", nil, "Print the results" },
        { "export", "[file]", "Save the results as JSON" },
    } },
    { "spawn", nil, "Spawn things", sub = {
        { "enemies", "<count>", "Replace all enemies with <count>" },
        { "coins", "<count>", "XP glob count, applied on restart" },
    } },
}

local function startsWith(s, prefix)
    return s:sub(1, #prefix):lower() == prefix:lower()
end

local function item(prefix, c)
    local args = c[2] or (c.sub and "<cmd>")
    local desc = c[3]
    if c.sub then
        local names = {}
        for i, s in ipairs(c.sub) do names[i] = s[1] end
        desc = desc .. ": " .. table.concat(names, " ")
    end
    return {
        complete = prefix .. c[1] .. (args and " " or ""),
        label = prefix .. c[1] .. (args and " " .. args or ""),
        desc = desc,
    }
end

local function find(list, name)
    for _, c in ipairs(list) do
        if c[1] == name then return c end
    end
end

-- Hints for `input` from `list`: every command (or subcommand) the word
-- being typed could become, or once it's complete, that command's usage.
-- Returns {} when the input isn't a command at all (e.g. Lua code).
function hints.match(list, input)
    local items = {}
    local word, rest = input:match("^%s*(%S*)(.*)$")
    if rest == "" then
        for _, c in ipairs(list) do
            if startsWith(c[1], word) then items[#items + 1] = item("", c) end
        end
        return items
    end

    local c = find(list, word)
    if not c then return items end
    if not c.sub then
        items[1] = item("", c)
        return items
    end

    local subWord, subRest = rest:match("^%s+(%S*)(.*)$")
    for _, s in ipairs(c.sub) do
        local exact = subRest ~= "" and s[1] == subWord
        if exact or (subRest == "" and startsWith(s[1], subWord)) then
            items[#items + 1] = item(word .. " ", s)
        end
    end
    return items
end

-- The greyed-out rest of the first hint, to show after the typed text.
function hints.ghost(items, input)
    local first = items[1]
    if first and #first.complete > #input and startsWith(first.complete, input) then
        return first.complete:sub(#input + 1)
    end
    return ""
end

-- Tab completion state for a console: the first Tab completes to the first
-- hint, each further Tab cycles to the next one. Typing anything resets it.
function hints.newTab()
    return { base = nil, items = nil, index = 0 }
end

function hints.tab(state, list, input)
    if not state.base then
        state.base = input
        state.items = hints.match(list, input)
        state.index = 0
    end
    if #state.items == 0 then
        state.base = nil
        return input
    end
    state.index = state.index % #state.items + 1
    return state.items[state.index].complete
end

function hints.resetTab(state)
    state.base, state.items, state.index = nil, nil, 0
end

-- What to show for `input`: the cycling list while tabbing, else the matches.
function hints.current(state, list, input)
    if state.base then return state.items, state.index end
    return hints.match(list, input), 0
end

local MAX_ROWS = 8
local labelColor = { 1.0, 0.85, 0.3, 1 }
local descColor = { 0.65, 0.65, 0.65, 1 }

-- A box of hints whose bottom edge sits at `bottom`, `selected` highlighted
-- (0 = none). Shows the first MAX_ROWS around the selection.
function hints.draw(items, selected, x, bottom, font, maxWidth)
    if #items == 0 then return end
    local lineHeight = font:getHeight() + 2
    local first = math.max(1, math.min(selected - MAX_ROWS + 1, #items - MAX_ROWS + 1))
    local last = math.min(#items, first + MAX_ROWS - 1)
    local labelWidth = 0
    for i = first, last do
        labelWidth = math.max(labelWidth, font:getWidth(items[i].label))
    end
    local gap = font:getWidth("  ")
    local width = 0
    for i = first, last do
        width = math.max(width, labelWidth + gap + font:getWidth(items[i].desc or ""))
    end
    width = math.min(width + 16, maxWidth)
    local rows = last - first + 1 + ((first > 1 or last < #items) and 1 or 0)
    local top = bottom - rows * lineHeight - 6

    local r, g, b, a = love.graphics.getColor()
    love.graphics.setColor(0.06, 0.06, 0.08, 0.95)
    love.graphics.rectangle("fill", x, top, width, bottom - top, 4)
    love.graphics.setColor(0.2, 0.6, 0.9, 0.8)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, top, width, bottom - top, 4)

    love.graphics.setScissor(x, top, width, bottom - top)
    local y = top + 3
    for i = first, last do
        local it = items[i]
        if i == selected then
            love.graphics.setColor(0.2, 0.5, 0.8, 0.7)
            love.graphics.rectangle("fill", x + 2, y, width - 4, lineHeight, 3)
        end
        love.graphics.setColor(labelColor)
        love.graphics.print(it.label, x + 8, y)
        love.graphics.setColor(descColor)
        love.graphics.print(it.desc or "", x + 8 + labelWidth + gap, y)
        y = y + lineHeight
    end
    if first > 1 or last < #items then
        love.graphics.setColor(descColor)
        love.graphics.print(string.format("%d of %d  (Tab cycles)", math.max(selected, 1), #items), x + 8, y)
    end
    love.graphics.setScissor()
    love.graphics.setColor(r, g, b, a)
end

return hints
