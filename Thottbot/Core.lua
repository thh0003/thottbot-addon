-- Thottbot: passive data collection for thottbot4ever.com.
-- Core: database lifecycle, position and GUID helpers, the event frame, slash commands.
-- Runs on the client's Lua 5.1 and on Lua 5.4 in the test harness: no goto, //, bitwise
-- operators or integer subtypes; `unpack` shimmed below.
local ADDON, T = ...
_G.Thottbot = T

local unpack = table.unpack or unpack
T.unpack = unpack

T.FORMAT = 1
T.MAX_SIGHTINGS = 200
-- Repeat sightings of the same spawn within this many seconds are dropped.
T.THROTTLE = 30
-- A game object's spawn GUID can be reused after it respawns; its loot counts again after this.
T.OBJECT_LOOT_EXPIRY = 60
T.TABLES = { 'npcs', 'objects', 'loot', 'vendors', 'trainers', 'quests', 'items' }
T.PROBE = {
  'C_Map.GetBestMapForUnit', 'C_Map.GetPlayerMapPosition', 'C_TooltipInfo.GetWorldCursor',
  'C_TooltipInfo.GetUnit', 'C_TooltipInfo.GetItemByID', 'GetLootSourceInfo', 'C_Item.GetItemInfo',
  'GetItemInfo', 'GetItemInfoInstant', 'C_QuestLog.GetQuestDifficultyLevel', 'GetQuestLogIndexByID',
  'C_QuestLog.GetLogIndexForQuestID', 'C_AddOns.GetAddOnMetadata', 'GetAddOnMetadata',
  'C_Container.GetContainerItemLink', 'GetContainerItemLink', 'GetMerchantItemCostInfo',
  'GetMerchantItemCostItem', 'SetMerchantFilter', 'SetTrainerServiceTypeFilter',
  'GetTrainerServiceItemLink', 'UnitGUID', 'UnitClassification', 'UnitReaction', 'GetQuestID',
  'GetRewardXP', 'GetRewardMoney', 'Minimap',
}

T.handlers = {}
T.readyCallbacks = {}
T.session = { seen = {}, looted = {}, items = {}, lastObject = nil, lastBags = 0 }

local function log(msg)
  print('|cff8fd6ffThottbot|r: ' .. tostring(msg))
end
T.log = log

-- Walk `_G` for a dotted API name.
function T.api(name)
  local cur = _G
  for part in name:gmatch('[^%.]+') do
    if type(cur) ~= 'table' then return nil end
    cur = cur[part]
    if cur == nil then return nil end
  end
  return cur
end

function T.version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if get then
    local ok, v = pcall(get, ADDON, 'Version')
    if ok and type(v) == 'string' and v ~= '' then return v end
  end
  return '0.0.0'
end

function T.build()
  local version, buildNumber = GetBuildInfo()
  return tostring(version) .. '.' .. tostring(buildNumber)
end

function T.now()
  return time()
end

function T.round4(v)
  return math.floor(v * 10000 + 0.5) / 10000
end

local function hex16()
  local out = {}
  for i = 1, 16 do out[i] = string.format('%x', math.random(0, 15)) end
  return table.concat(out)
end

function T.newDB()
  local db = {
    format = T.FORMAT,
    version = T.version(),
    build = T.build(),
    fileId = hex16(),
    created = T.now(),
    paused = false,
  }
  for _, k in ipairs(T.TABLES) do db[k] = {} end
  return db
end

function T.initDB()
  if type(ThottbotDB) ~= 'table' or ThottbotDB.format ~= T.FORMAT then
    local minimap = type(ThottbotDB) == 'table' and ThottbotDB.minimap or nil
    ThottbotDB = T.newDB()
    ThottbotDB.minimap = minimap
  end
  local db = ThottbotDB
  db.version = T.version()
  db.build = T.build()
  for _, k in ipairs(T.TABLES) do
    if type(db[k]) ~= 'table' then db[k] = {} end
  end
  if type(db.fileId) ~= 'string' or #db.fileId ~= 16 then db.fileId = hex16() end
  if type(db.created) ~= 'number' then db.created = T.now() end
  db.paused = db.paused == true
  T.db = db
end

function T.clear()
  local minimap = T.db and T.db.minimap
  local probe = T.db and T.db.probe
  ThottbotDB = T.newDB()
  ThottbotDB.minimap = minimap
  ThottbotDB.probe = probe
  T.db = ThottbotDB
  T.session = { seen = {}, looted = {}, items = {}, lastObject = nil, lastBags = 0 }
end

-- Recording is on once the saved variables are loaded and the player has not paused it.
function T.active()
  return T.ready == true and T.db ~= nil and not T.db.paused
end

-- The Forever client (Midnight-era restrictions) hands addons "secret" values in some
-- contexts; seen in the beta: the world-cursor GUID while in a party for a dungeon. type()
-- still reports string or number, but indexing, comparing or concatenating one raises an
-- error, so every value read from the client goes through here and a secret counts as absent.
function T.plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- Run a recorder; an error becomes one chat line per distinct message instead of a red frame.
local reported = {}
function T.guard(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return true end
  local msg = tostring(err)
  if not reported[msg] then
    reported[msg] = true
    log('recorder error (reported once): ' .. msg)
  end
  return false
end

-- The player's position as uiMap id and 0-1 map coordinates; nil in an unmapped place.
function T.pos()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local ok, m = pcall(C_Map.GetBestMapForUnit, 'player')
  if not ok or not m then return nil end
  local ok2, p = pcall(C_Map.GetPlayerMapPosition, m, 'player')
  if not ok2 or not p then return nil end
  local x, y
  if p.GetXY then x, y = p:GetXY() else x, y = p.x, p.y end
  x, y = T.plain(x), T.plain(y)
  if type(x) ~= 'number' or type(y) ~= 'number' then return nil end
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return m, x, y
end

-- Creature-0-server-instance-zone-<entry>-spawn / GameObject-... -> 'n'|'o', entry id.
function T.guid(guid)
  guid = T.plain(guid)
  if type(guid) ~= 'string' then return nil end
  local kind, id = guid:match('^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-')
  if not kind then return nil end
  id = tonumber(id)
  if not id or id <= 0 then return nil end
  if kind == 'Creature' or kind == 'Vehicle' then return 'n', id end
  if kind == 'GameObject' then return 'o', id end
  return nil
end

function T.itemId(link)
  link = T.plain(link)
  if type(link) ~= 'string' then return nil end
  local id = tonumber(link:match('item:(%d+)'))
  if id and id > 0 then return id end
  return nil
end

-- True when this spawn GUID was recorded less than THROTTLE seconds ago (and marks it).
function T.throttled(guid)
  local now = T.now()
  local last = T.session.seen[guid]
  if last and now - last < T.THROTTLE then return true end
  T.session.seen[guid] = now
  return false
end

function T.sight(list, kind)
  local m, x, y = T.pos()
  if not m then return false end
  if #list >= T.MAX_SIGHTINGS then return false end
  list[#list + 1] = { m = m, x = T.round4(x), y = T.round4(y), t = T.now(), k = kind }
  return true
end

function T.counts()
  local c = {}
  for _, k in ipairs(T.TABLES) do
    local n = 0
    for _ in pairs(T.db[k]) do n = n + 1 end
    c[k] = n
  end
  local events = 0
  for _, l in pairs(T.db.loot) do events = events + (l.n or 0) end
  c.lootEvents = events
  return c
end

function T.statusLines()
  local c = T.counts()
  return {
    string.format('Thottbot %s on client %s%s', T.db.version, T.db.build, T.db.paused and ' (paused)' or ''),
    string.format('%d NPCs, %d objects, %d loot events, %d vendors, %d trainers, %d quests, %d items',
      c.npcs, c.objects, c.lootEvents, c.vendors, c.trainers, c.quests, c.items),
    'Upload WTF/Account/<ACCOUNT>/SavedVariables/Thottbot.lua at thottbot4ever.com/addon/upload after /reload.',
  }
end

function T.probe()
  local out = {}
  for _, name in ipairs(T.PROBE) do
    out[name] = T.api(name) ~= nil
  end
  local _, _, _, toc = GetBuildInfo()
  out['tocversion:' .. tostring(toc)] = true
  T.db.probe = out
  local missing = {}
  for _, name in ipairs(T.PROBE) do
    if not out[name] then missing[#missing + 1] = name end
  end
  log('probe: tocversion ' .. tostring(toc) .. '; missing: ' .. (#missing > 0 and table.concat(missing, ', ') or 'none'))
  return out
end

function T.command(msg)
  msg = (msg or ''):lower():match('^%s*(.-)%s*$')
  if not T.db then
    log('not loaded yet')
    return
  end
  if msg == 'pause' then
    T.db.paused = true
    log('recording paused')
  elseif msg == 'resume' then
    T.db.paused = false
    log('recording resumed')
  elseif msg == 'clear' then
    T.clear()
    log('data cleared; a fresh file starts now')
  elseif msg == 'probe' then
    T.probe()
  elseif msg == 'cursor' then
    -- Diagnostic: what the client reports for the object under the mouse right now.
    local id, name, key, data = T.worldCursor()
    if not data then
      log('cursor: no tooltip data (hover a chest, node or herb first)')
    else
      log(string.format('cursor: id %s, name %s, guid %s, type %s, dataId %s',
        tostring(id), tostring(name), tostring(data.guid or key), tostring(data.type), tostring(data.id)))
    end
  elseif msg == 'version' then
    log(T.db.version)
  elseif msg == '' or msg == 'status' then
    for _, line in ipairs(T.statusLines()) do log(line) end
  else
    log('commands: status, pause, resume, clear, probe, cursor, version')
  end
end

SLASH_THOTTBOT1 = '/thottbot'
SLASH_THOTTBOT2 = '/tb'
SlashCmdList['THOTTBOT'] = function(msg) T.command(msg) end

local frame = CreateFrame('Frame')
T.frame = frame

-- Register a handler; unknown events are ignored rather than erroring on older clients.
function T.on(event, fn)
  T.handlers[event] = fn
  pcall(frame.RegisterEvent, frame, event)
end

function T.onReady(fn)
  if T.ready then fn() else T.readyCallbacks[#T.readyCallbacks + 1] = fn end
end

frame:SetScript('OnEvent', function(_, event, ...)
  local h = T.handlers[event]
  if h then T.guard(h, ...) end
end)

T.on('ADDON_LOADED', function(name)
  if name ~= ADDON then return end
  T.initDB()
  T.ready = true
  for _, fn in ipairs(T.readyCallbacks) do fn() end
  T.readyCallbacks = {}
end)

T.on('PLAYER_LOGIN', function()
  if T.db then T.db.build = T.build() end
end)
