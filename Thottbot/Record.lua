-- Recorders: every game event the addon listens to and what it writes into ThottbotDB.
-- Everything is a no-op until ADDON_LOADED and while the player has paused recording.
local ADDON, T = ...

local CLASS = {
  normal = 'normal', elite = 'elite', rareelite = 'rareelite', rare = 'rare',
  worldboss = 'worldboss', trivial = 'normal', minus = 'normal',
}

local function nz(v)
  if type(v) == 'number' and v > 0 then return v end
  return nil
end

local function reaction(unit)
  if not UnitReaction then return nil end
  local ok, r = pcall(UnitReaction, unit, 'player')
  r = ok and T.plain(r)
  if type(r) ~= 'number' then return nil end
  if r <= 3 then return 'h' elseif r == 4 then return 'n' else return 'f' end
end

local function playerFaction()
  if not UnitFactionGroup then return nil end
  local ok, f = pcall(UnitFactionGroup, 'player')
  if not ok then return nil end
  if f == 'Alliance' then return 'A' elseif f == 'Horde' then return 'H' end
  return nil
end

local function unitTitle(unit)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
  if not ok or type(data) ~= 'table' or type(data.lines) ~= 'table' then return nil end
  local line = data.lines[2]
  local text = T.plain(line and line.leftText)
  if type(text) ~= 'string' or text == '' or text:find('^Level ') then return nil end
  return text
end

-- An NPC seen through a unit token: mouseover (m), target (t) or an interaction (i).
function T.recordUnit(unit, kind)
  if not T.active() then return end
  if not (UnitExists and UnitExists(unit)) then return end
  if UnitIsPlayer and UnitIsPlayer(unit) then return end
  local guid = UnitGUID and UnitGUID(unit)
  local k, id = T.guid(guid)
  if k ~= 'n' then return end
  if T.throttled(guid) then return end
  local rec = T.db.npcs[id]
  if not rec then
    rec = { name = '?', s = {} }
    T.db.npcs[id] = rec
  end
  local name = T.plain(UnitName and UnitName(unit))
  if type(name) == 'string' and name ~= '' then rec.name = name end
  local lvl = T.plain(UnitLevel and UnitLevel(unit))
  if type(lvl) == 'number' and lvl > 0 then
    rec.lmin = math.min(rec.lmin or lvl, lvl)
    rec.lmax = math.max(rec.lmax or lvl, lvl)
  end
  if lvl == -1 then
    rec.class = 'worldboss'
  elseif UnitClassification then
    local c = T.plain(UnitClassification(unit))
    if type(c) == 'string' then rec.class = CLASS[c] or 'normal' end
  end
  local ct = T.plain(UnitCreatureType and UnitCreatureType(unit))
  if type(ct) == 'string' and ct ~= '' then rec.ctype = ct end
  local r = reaction(unit)
  if r then rec.react = r end
  local pf = playerFaction()
  if pf then rec.pf = pf end
  local title = unitTitle(unit)
  if title then rec.title = title end
  T.sight(rec.s, kind)
end

-- What the client reports for the world object under the cursor: its GUID, or on clients
-- that type the tooltip instead, an Object type with the entry id. Returns id, name, key.
function T.worldCursor()
  if not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetWorldCursor)
  if not ok or type(data) ~= 'table' then return nil end
  local line = type(data.lines) == 'table' and data.lines[1]
  local name = T.plain(line and line.leftText)
  local guid = T.plain(data.guid)
  if guid then
    local k, id = T.guid(guid)
    if k == 'o' then return id, name, guid, data end
    return nil, name, guid, data
  end
  local objectType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
  local dataType, dataId = T.plain(data.type), T.plain(data.id)
  if objectType and dataType == objectType and type(dataId) == 'number' and dataId > 0 then
    return dataId, name, 'obj:' .. dataId, data
  end
  return nil, name, nil, data
end

-- A world object (chest, node, herb, quest object) under the cursor.
function T.recordWorldCursor()
  if not T.active() then return end
  local id, name, key = T.worldCursor()
  if not id then return end
  T.session.lastObject = { id = id, t = T.now() }
  if T.throttled(key) then return end
  local rec = T.db.objects[id]
  if not rec then
    rec = { name = '?', s = {} }
    T.db.objects[id] = rec
  end
  if type(name) == 'string' and name ~= '' then rec.name = name end
  T.sight(rec.s, 'm')
end

-- Item facts from the client's item cache, once per session per id.
function T.recordItem(link)
  if not T.active() then return end
  local id = T.itemId(link)
  if not id then return end
  if T.db.items[id] and T.session.items[id] then return end
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return end
  local ok, name, _, quality, ilvl, reqLevel, cn, sn, _, _, _, sell, classId, subclassId, bind =
    pcall(getInfo, link)
  if not ok or type(name) ~= 'string' or name == '' then return end
  local rec = {
    name = name,
    q = math.max(0, math.min(6, tonumber(quality) or 0)),
    il = nz(ilvl),
    rl = nz(reqLevel),
    cn = (type(cn) == 'string' and cn ~= '') and cn or nil,
    sn = (type(sn) == 'string' and sn ~= '') and sn or nil,
    sell = nz(sell),
    cls = type(classId) == 'number' and classId or nil,
    sub = type(subclassId) == 'number' and subclassId or nil,
    b = type(bind) == 'number' and bind or nil,
  }
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok2, data = pcall(C_TooltipInfo.GetItemByID, id)
    if ok2 and type(data) == 'table' and type(data.lines) == 'table' then
      local lines = {}
      for _, l in ipairs(data.lines) do
        local text = l.leftText
        if type(text) == 'string' and text ~= '' then
          lines[#lines + 1] = text:sub(1, 500)
          if #lines >= 40 then break end
        end
      end
      if #lines > 0 then rec.lines = lines end
    end
  end
  T.db.items[id] = rec
  T.session.items[id] = true
end

-- Loot ----------------------------------------------------------------------------------

local function lootSources(slot)
  if GetLootSourceInfo then
    local ok, a, b, c, d, e, f, g, h = pcall(GetLootSourceInfo, slot)
    if ok and a then return { a, b, c, d, e, f, g, h } end
  end
  local guid = UnitGUID and UnitGUID('target')
  if guid then return { guid, 1 } end
  return {}
end

-- One loot window: count each source once as a loot event (per spawn GUID for the
-- session) and each item once per event, whatever the slots say.
local function onLootOpened()
  if not T.active() then return end
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  local now = T.now()
  local eventSources = {}
  local eventItems = {}
  for slot = 1, n do
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local itemId = T.itemId(link)
    local sources = lootSources(slot)
    for i = 1, #sources, 2 do
      local guid = T.plain(sources[i])
      local k, id = T.guid(guid)
      if k then
        local key = k .. tostring(id)
        local counted = T.session.looted[guid]
        local expired = k == 'o' and counted and now - counted >= T.OBJECT_LOOT_EXPIRY
        if (not counted or expired) and not eventSources[key] then
          eventSources[key] = true
          T.session.looted[guid] = now
          local rec = T.db.loot[key]
          if not rec then
            rec = { n = 0, i = {} }
            T.db.loot[key] = rec
          end
          rec.n = rec.n + 1
        end
        if eventSources[key] and itemId then
          local rec = T.db.loot[key]
          local ikey = key .. ':' .. itemId
          local qty = 1
          if GetLootSlotInfo then
            local _, _, q = GetLootSlotInfo(slot)
            q = T.plain(q)
            if type(q) == 'number' and q > 0 then qty = q end
          end
          local entry = rec.i[itemId]
          if not entry then
            entry = { n = 0, q = 0 }
            rec.i[itemId] = entry
          end
          if not eventItems[ikey] then
            eventItems[ikey] = true
            entry.n = entry.n + 1
          end
          entry.q = entry.q + qty
        end
      end
    end
    if link then T.recordItem(link) end
  end
end

-- Vendors and trainers --------------------------------------------------------------

-- Price and limited-stock count of merchant slot i. The Forever client (Mainline UI) has
-- only C_MerchantFrame.GetItemInfo, which returns a table; older clients have the
-- multi-return global. Seen in the beta: the global is nil there ("attempt to call a nil value").
local function merchantItem(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
    if ok and type(info) == 'table' then return T.plain(info.price), T.plain(info.numAvailable) end
  end
  if GetMerchantItemInfo then
    local ok, _, _, price, _, numAvailable = pcall(GetMerchantItemInfo, i)
    if ok then return T.plain(price), T.plain(numAvailable) end
  end
  return nil, nil
end

-- MERCHANT_SHOW often arrives before the client has the item links (seen in the beta);
-- MERCHANT_UPDATE follows with them, so both scan and an empty scan never replaces a list.
local function onMerchantShow()
  if not T.active() then return end
  T.recordUnit('npc', 'i')
  local k, id = T.guid(UnitGUID and UnitGUID('npc'))
  if k ~= 'n' then return end
  if SetMerchantFilter and LE_LOOT_FILTER_ALL then pcall(SetMerchantFilter, LE_LOOT_FILTER_ALL) end
  local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
  local items = {}
  for i = 1, n do
    local link = GetMerchantItemLink and GetMerchantItemLink(i)
    local itemId = T.itemId(link)
    if itemId then
      local price, numAvailable = merchantItem(i)
      local entry = { id = itemId, p = math.max(0, tonumber(price) or 0) }
      if type(numAvailable) == 'number' and numAvailable >= 0 then entry.s = numAvailable end
      if GetMerchantItemCostInfo and GetMerchantItemCostItem then
        local ok, costCount = pcall(GetMerchantItemCostInfo, i)
        if ok and type(costCount) == 'number' and costCount > 0 then
          local ok2, _, _, costLink = pcall(GetMerchantItemCostItem, i, 1)
          local cid = ok2 and T.itemId(costLink)
          if cid then entry.c = cid end
        end
      end
      items[#items + 1] = entry
      T.recordItem(link)
      if #items >= 500 then break end
    end
  end
  local existing = T.db.vendors[id]
  if #items == 0 and existing and #existing.i > 0 then return end
  T.db.vendors[id] = { b = T.db.build, i = items }
end

local function spellId(link)
  link = T.plain(link)
  if type(link) ~= 'string' then return nil end
  local id = tonumber(link:match('spell:(%d+)')) or tonumber(link:match('enchant:(%d+)'))
  if id and id > 0 then return id end
  return nil
end

local function onTrainerShow()
  if not T.active() then return end
  T.recordUnit('npc', 'i')
  local k, id = T.guid(UnitGUID and UnitGUID('npc'))
  if k ~= 'n' then return end
  if SetTrainerServiceTypeFilter then
    for _, t in ipairs({ 'available', 'unavailable', 'used' }) do
      pcall(SetTrainerServiceTypeFilter, t, 1)
    end
  end
  if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
  local n = GetNumTrainerServices() or 0
  local spells = {}
  for i = 1, n do
    local ok, _, _, category = pcall(GetTrainerServiceInfo, i)
    if ok and category ~= 'header' then
      local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
      local sid = spellId(link)
      if sid then
        local cost = T.plain(GetTrainerServiceCost and GetTrainerServiceCost(i)) or 0
        local level = T.plain(GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)) or 0
        spells[#spells + 1] = {
          id = sid,
          c = math.max(0, tonumber(cost) or 0),
          l = math.max(0, math.min(100, tonumber(level) or 0)),
        }
        if #spells >= 500 then break end
      end
    end
  end
  local existing = T.db.trainers[id]
  if #spells == 0 and existing and #existing.s > 0 then return end
  T.db.trainers[id] = { b = T.db.build, s = spells }
end

-- Quests -----------------------------------------------------------------------------------

-- The NPC or object the quest frame belongs to, with the player's position.
local function questEnd()
  local k, id = T.guid(UnitGUID and UnitGUID('npc'))
  if not k then
    local lo = T.session.lastObject
    if lo and T.now() - lo.t <= 2 then k, id = 'o', lo.id end
  end
  if not k then return nil end
  local e = { k = k, id = id }
  local m, x, y = T.pos()
  if m then
    e.m = m
    e.x = T.round4(x)
    e.y = T.round4(y)
  end
  return e
end

local function questLevel(id)
  if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
    local ok, lvl = pcall(C_QuestLog.GetQuestDifficultyLevel, id)
    lvl = ok and T.plain(lvl)
    if type(lvl) == 'number' and lvl > 0 then return lvl end
  end
  local index
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
    local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, id)
    if ok then index = i end
  elseif GetQuestLogIndexByID then
    local ok, i = pcall(GetQuestLogIndexByID, id)
    if ok then index = i end
  end
  index = T.plain(index)
  if type(index) == 'number' and index > 0 and GetQuestLogTitle then
    local ok, _, lvl = pcall(GetQuestLogTitle, index)
    lvl = ok and T.plain(lvl)
    if type(lvl) == 'number' and lvl > 0 then return lvl end
  end
  return nil
end

local function questRewards(rec)
  local ri, rc = {}, {}
  for i = 1, (GetNumQuestRewards and GetNumQuestRewards()) or 0 do
    local link = GetQuestItemLink('reward', i)
    local id = T.itemId(link)
    if id then
      ri[#ri + 1] = id
      T.recordItem(link)
    end
  end
  for i = 1, (GetNumQuestChoices and GetNumQuestChoices()) or 0 do
    local link = GetQuestItemLink('choice', i)
    local id = T.itemId(link)
    if id then
      rc[#rc + 1] = id
      T.recordItem(link)
    end
  end
  if #ri > 0 then rec.ri = ri end
  if #rc > 0 then rec.rc = rc end
  local money = T.plain(GetRewardMoney and GetRewardMoney())
  if type(money) == 'number' and money > 0 then rec.money = money end
  local xp = T.plain(GetRewardXP and GetRewardXP())
  if type(xp) == 'number' and xp > 0 then rec.xp = xp end
end

local function questRecord()
  if not T.active() then return nil end
  local id = T.plain(GetQuestID and GetQuestID())
  if type(id) ~= 'number' or id <= 0 then return nil end
  T.recordUnit('npc', 'i')
  local rec = T.db.quests[id]
  if not rec then
    rec = { title = '?', b = T.db.build, t = T.now() }
    T.db.quests[id] = rec
  end
  rec.b = T.db.build
  rec.t = T.now()
  local title = T.plain(GetTitleText and GetTitleText())
  if type(title) == 'string' and title ~= '' then rec.title = title end
  local lvl = questLevel(id)
  if lvl then rec.lvl = lvl end
  return rec
end

local function text(fn)
  local s = T.plain(fn and fn())
  if type(s) == 'string' and s ~= '' then return s:sub(1, 8000) end
  return nil
end

local function onQuestDetail()
  local rec = questRecord()
  if not rec then return end
  rec.text = text(GetQuestText) or rec.text
  rec.obj = text(GetObjectiveText) or rec.obj
  rec.giver = questEnd() or rec.giver
  questRewards(rec)
end

local function onQuestProgress()
  local rec = questRecord()
  if not rec then return end
  rec.prog = text(GetProgressText) or rec.prog
  rec.ender = questEnd() or rec.ender
end

local function onQuestComplete()
  local rec = questRecord()
  if not rec then return end
  rec.comp = text(GetRewardText) or rec.comp
  rec.ender = questEnd() or rec.ender
  questRewards(rec)
end

-- Bags: item facts for everything carried, at most every 10 s.
local function onBagUpdate()
  if not T.active() then return end
  local now = T.now()
  if now - (T.session.lastBags or 0) < 10 then return end
  T.session.lastBags = now
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  if not (numSlots and itemLink) then return end
  for bag = 0, 4 do
    local ok, n = pcall(numSlots, bag)
    for slot = 1, (ok and n) or 0 do
      local ok2, link = pcall(itemLink, bag, slot)
      if ok2 and link then T.recordItem(link) end
    end
  end
end

-- Wiring ------------------------------------------------------------------------------------

T.on('UPDATE_MOUSEOVER_UNIT', function()
  T.recordUnit('mouseover', 'm')
end)
T.on('PLAYER_TARGET_CHANGED', function()
  T.recordUnit('target', 't')
end)
T.on('GOSSIP_SHOW', function()
  T.recordUnit('npc', 'i')
end)
T.on('CURSOR_CHANGED', T.recordWorldCursor)
T.on('LOOT_OPENED', onLootOpened)
T.on('MERCHANT_SHOW', onMerchantShow)
T.on('MERCHANT_UPDATE', onMerchantShow)
T.on('TRAINER_SHOW', onTrainerShow)
T.on('TRAINER_UPDATE', onTrainerShow)
T.on('QUEST_DETAIL', onQuestDetail)
T.on('QUEST_PROGRESS', onQuestProgress)
T.on('QUEST_COMPLETE', onQuestComplete)
T.on('BAG_UPDATE_DELAYED', onBagUpdate)

-- World objects do not fire a mouseover event: read the world cursor when a tooltip appears
-- and poll while one shows (the client may fill the tooltip data a moment later).
if GameTooltip and GameTooltip.HookScript then
  pcall(GameTooltip.HookScript, GameTooltip, 'OnShow', function() T.guard(T.recordWorldCursor) end)
end
local elapsed = 0
T.frame:SetScript('OnUpdate', function(_, dt)
  elapsed = elapsed + (dt or 0)
  if elapsed < 0.3 then return end
  elapsed = 0
  if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then T.guard(T.recordWorldCursor) end
end)
