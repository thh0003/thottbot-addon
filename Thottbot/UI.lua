-- Minimap button: shows the status tooltip, left click pauses/resumes, right click prints
-- the slash help, drag moves it around the minimap rim (angle saved in ThottbotDB.minimap).
local ADDON, T = ...

if not (Minimap and CreateFrame) then return end

local RADIUS = 80
local button = CreateFrame('Button', 'ThottbotMinimapButton', Minimap)
T.button = button
button:SetSize(32, 32)
button:SetFrameStrata('MEDIUM')
button:SetMovable(true)
button:EnableMouse(true)
button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
button:RegisterForDrag('LeftButton')
-- The addon's own icon (logo.tga, alongside this file; the path takes no extension). A client
-- that cannot load it leaves the button blank rather than erroring, so fall back to the stock
-- note icon when the texture does not take.
local ICON = 'Interface\\AddOns\\Thottbot\\logo'
local FALLBACK_ICON = 'Interface\\Icons\\INV_Misc_Note_01'
pcall(button.SetNormalTexture, button, ICON)
local normal = button.GetNormalTexture and button:GetNormalTexture()
if not (normal and normal.GetTexture and normal:GetTexture()) then
  pcall(button.SetNormalTexture, button, FALLBACK_ICON)
end
pcall(button.SetHighlightTexture, button, 'Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')

local function angle()
  return (T.db and T.db.minimap and T.db.minimap.angle) or 225
end

local function place()
  local a = math.rad(angle())
  button:ClearAllPoints()
  button:SetPoint('CENTER', Minimap, 'CENTER', math.cos(a) * RADIUS, math.sin(a) * RADIUS)
end

local function dragTo()
  if not (GetCursorPosition and Minimap.GetCenter) then return end
  local mx, my = Minimap:GetCenter()
  if not mx then return end
  local cx, cy = GetCursorPosition()
  local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
  cx, cy = cx / scale, cy / scale
  local a = math.deg(math.atan2 and math.atan2(cy - my, cx - mx) or math.atan(cy - my, cx - mx))
  if T.db then T.db.minimap = { angle = a } end
  place()
end

button:SetScript('OnDragStart', function(self)
  self:SetScript('OnUpdate', dragTo)
end)
button:SetScript('OnDragStop', function(self)
  self:SetScript('OnUpdate', nil)
end)
button:SetScript('OnClick', function(_, mouse)
  if not T.db then return end
  if mouse == 'RightButton' then
    T.command('help')
  else
    T.command(T.db.paused and 'resume' or 'pause')
  end
end)
button:SetScript('OnEnter', function(self)
  if not (GameTooltip and T.db) then return end
  GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
  for _, line in ipairs(T.statusLines()) do GameTooltip:AddLine(line, 1, 1, 1, true) end
  GameTooltip:AddLine('Left click: pause/resume. Right click: commands. Drag to move.', 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
button:SetScript('OnLeave', function()
  if GameTooltip then GameTooltip:Hide() end
end)

T.onReady(place)
