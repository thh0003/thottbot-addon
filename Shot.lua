-- Screenshot button: a small camera beside the minimap, `/thottbot shot` and a key binding
-- (Key Bindings -> Thottbot). It screenshots the target NPC or object (else the mouseover,
-- else the zone) and records that subject in ThottbotDB.shots under the stem of the file the
-- game writes, `WoWScrnShot_MMDDYY_HHMMSS`. The auto-upload page uploads the file once the
-- game has written Thottbot.lua (/reload or logout).
local ADDON, T = ...

BINDING_HEADER_THOTTBOT = 'Thottbot'
BINDING_NAME_THOTTBOT_SHOT = 'Screenshot for thottbot4ever.com'

local pending -- the subject of the screenshot being taken, until the game reports back
local hidUI, oldFormat
-- Seconds to wait for SCREENSHOT_SUCCEEDED / SCREENSHOT_FAILED before restoring the interface.
local SHOT_TIMEOUT = 5


-- What the screenshot shows: the target, else the mouseover (NPC or object), else the zone.
local function subject()
  for _, token in ipairs({ 'target', 'mouseover' }) do
    local kind, id = T.guid(UnitGUID and UnitGUID(token))
    if kind then return kind, id end
  end
  local m = T.pos()
  if m then return 'z', m end
  return nil
end

local function restore()
  if hidUI then UIParent:Show() end
  if oldFormat then SetCVar('screenshotFormat', oldFormat) end
  hidUI, oldFormat = nil, nil
end

local function oldest(shots)
  local key, at
  for k, s in pairs(shots) do
    if not at or (s.t or 0) < at then key, at = k, s.t or 0 end
  end
  return key
end

function T.shot()
  if not T.db or pending then return end
  if not Screenshot then
    T.log('screenshot failed: this client offers addons no screenshot call')
    return
  end
  local kind, id = subject()
  if not kind then
    T.log('screenshot: nothing to attach it to here (target an NPC or object, or stand in a zone)')
    return
  end
  local m, x, y = T.pos()
  pending = { k = kind, id = id }
  if m then pending.m, pending.x, pending.y = m, T.round4(x), T.round4(y) end
  -- The site takes JPEG or PNG; a TGA format is switched for this one shot.
  if GetCVar and SetCVar and GetCVar('screenshotFormat') == 'tga' then
    oldFormat = 'tga'
    SetCVar('screenshotFormat', 'jpeg')
    if GetCVar('screenshotFormat') ~= 'jpeg' then
      T.log('screenshot format is TGA, which cannot be uploaded; set Screenshot Format to JPG in System options')
    end
  end
  -- The game refuses to hide the interface in combat; then the shot keeps it.
  if UIParent and UIParent:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
    UIParent:Hide()
    hidUI = true
  end
  Screenshot()
  -- Never leave the interface hidden: if the game reports neither success nor failure, give up.
  local this = pending
  if C_Timer and C_Timer.After then
    C_Timer.After(SHOT_TIMEOUT, function()
      if pending ~= this then return end
      pending = nil
      restore()
      T.log('screenshot failed: the game did not report back; nothing was recorded')
    end)
  end
end

T.on('SCREENSHOT_SUCCEEDED', function()
  local shot = pending
  pending = nil
  restore()
  if not (shot and T.db) then return end
  shot.t = T.now()
  local shots = T.db.shots
  local n = 0
  for _ in pairs(shots) do n = n + 1 end
  while n >= T.MAX_SHOTS do
    shots[oldest(shots)] = nil
    n = n - 1
  end
  shots['WoWScrnShot_' .. date('%m%d%y_%H%M%S')] = shot
  T.log('screenshot saved; it uploads from thottbot4ever.com/addon/watch after /reload or logout')
end)

T.on('SCREENSHOT_FAILED', function()
  if not pending then return end
  pending = nil
  restore()
  T.log('screenshot failed; nothing was recorded')
end)

if not (CreateFrame and Minimap) then return end

local button = CreateFrame('Button', 'ThottbotShotButton', UIParent)
T.shotButton = button
button:SetSize(24, 24)
button:SetFrameStrata('MEDIUM')
button:SetMovable(true)
button:SetClampedToScreen(true)
button:EnableMouse(true)
button:RegisterForClicks('LeftButtonUp')
button:RegisterForDrag('LeftButton')
pcall(button.SetNormalTexture, button, 'Interface\\Icons\\INV_Misc_Spyglass_02')
pcall(button.SetHighlightTexture, button, 'Interface\\Buttons\\ButtonHilight-Square')

local function place()
  button:ClearAllPoints()
  local p = T.db and T.db.shotButton
  if p and p.point then
    button:SetPoint(p.point, UIParent, p.point, p.x, p.y)
  else
    button:SetPoint('CENTER', Minimap, 'BOTTOMLEFT', 4, 4)
  end
end

button:SetScript('OnDragStart', function(self) self:StartMoving() end)
button:SetScript('OnDragStop', function(self)
  self:StopMovingOrSizing()
  local point, _, _, x, y = self:GetPoint()
  if T.db and point then T.db.shotButton = { point = point, x = x, y = y } end
end)
button:SetScript('OnClick', function() T.shot() end)
button:SetScript('OnEnter', function(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
  GameTooltip:AddLine('Screenshot for thottbot4ever.com', 1, 1, 1)
  GameTooltip:AddLine('Your target, else what is under the mouse, else this zone. Uploads from the auto-upload page after /reload or logout. Drag to move.', 0.7, 0.7, 0.7, true)
  GameTooltip:Show()
end)
button:SetScript('OnLeave', function()
  if GameTooltip then GameTooltip:Hide() end
end)

T.onReady(place)
