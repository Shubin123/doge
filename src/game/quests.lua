--[[
  Quests: the way through the game, in order. The gate, then each region in
  regions.list: the portals only take you to one once the boss of every
  region before it is beaten (bosses.isRegionOpen, game/portal.lua).

  The log is read off what's happened (the gate and what's beaten,
  game/bosses.lua), so it can't fall out of step with the fights. All it
  keeps of its own is where you've been (quests.visited, in saves; in
  multiplayer everyone has their own). It's drawn in the bag's panel
  (game/inventory.lua). A new region in regions.list is a new quest; a new
  kind of boss needs a line in FIGHTS.
]]
local quests = {}

-- What a region's quest is called (else its name)
local TITLES = {
    wasteland = "Free the Wasteland",
    castle = "Take back the Castle",
    neon = "Shut down Neon City",
    sanctum = "Silence the Sanctum",
}

-- What's asked of you at a lair, by the kind of boss (regions.list's `boss`)
local FIGHTS = {
    swarm = "Kill the Connectome, the brain the flies answer to, at its lair up the main avenue",
    bear = "Beat the bear at its lair up the main avenue",
    castellan = "Defeat the Castellan and her guard, before the keep up the main avenue",
    arm = "Wreck the Assembly Arm, bolted down at its lair up the main avenue",
    choir = "Bring down the Choir up the main avenue: Seraph, Ophan and Cherub, all three at once",
}

quests.visited = {} -- region id -> you've been there
local hinted = false

local function step(text, done)
    return { text = text, done = done and true or false }
end

local function quest(title, steps)
    local done = true
    for _, s in ipairs(steps) do done = done and s.done end
    return { title = title, steps = steps, done = done }
end

--- Every quest in order: { title, done, current, steps = { { text, done } } }.
--- `current` is on the first one not done.
function quests.log()
    local open = bosses.isGateOpen()
    local list = { quest("Open the Gate", {
        step("Stand in the Courtyard's portal and summon its guardian", open or bosses.gateFight()),
        step("Beat the guardian", open),
    }) }
    for i = 2, #regions.list do
        local r = regions.list[i]
        local steps = { step("Step into a portal and travel to " .. r.name, quests.visited[r.id] or bosses.beaten[r.id]) }
        if r.boss then steps[2] = step(FIGHTS[r.boss], bosses.cleared(r.id)) end
        list[#list + 1] = quest(TITLES[r.id] or r.name, steps)
    end
    for _, q in ipairs(list) do
        if not q.done then
            q.current = true
            break
        end
    end
    return list
end

--- Each frame, after regions.update: where you are counts as somewhere
--- you've been. The first frame of a game still at the gate says where the
--- log is.
function quests.update()
    quests.visited[regions.current.id] = true
    if not hinted then
        hinted = true
        if not bosses.isGateOpen() then inventory.notify("Press I for your bag and quests") end
    end
end

--- Where you've been, for a save
function quests.getSaveData()
    local list = {}
    for id in pairs(quests.visited) do list[#list + 1] = id end
    table.sort(list)
    return { visited = list }
end

--- Put back a getSaveData() (nil, for a save from before the log: nowhere yet)
function quests.restore(data)
    quests.visited = {}
    for _, id in ipairs(data and data.visited or {}) do quests.visited[id] = true end
end

return quests
