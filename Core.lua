-- Core.lua
-- Ella's Currency Tracker - Main addon module
-- Author: theswiftfox

local ADDON_NAME = "EllasCurrencyTracker"
local ECT = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")

-- Make addon object accessible globally (for Config.lua)
_G.EllasCurrencyTracker = ECT

---------------------------------------------------------------------------
-- AceDB profile defaults
---------------------------------------------------------------------------
ECT.DB_DEFAULTS = {
    profile = {
        tracked     = {},       -- ordered array of currency IDs
        grow        = "DOWN",   -- "UP" or "DOWN"
        titleStyle  = "SMALL",  -- "FULL", "SMALL", or "NONE"
        anchor = {
            point         = "CENTER",
            relativePoint = "CENTER",
            x             = 0,
            y             = 0,
            width         = 240,
            scale         = 1,
        },
        lineHeight     = 20,
        font           = "Fonts\\FRIZQT__.TTF",
        fontSize       = 12,
        fontColor      = { r = 1, g = 1, b = 1 },
        titleColor     = { r = 1, g = 1, b = 1 },
        -- Display modernisation options
        bgAlpha        = 0.6,    -- background opacity (0 = invisible, 1 = opaque)
        altRowShading  = true,   -- alternating row background shading
        iconSide       = "LEFT", -- "LEFT" or "RIGHT"
        formatNumbers  = true,   -- add comma separators to amounts
        showMax        = true,   -- show "current / max" for capped currencies
        mouseThrough   = false,  -- allow clicks to pass through the overlay
        rowTooltip     = true,   -- show tooltip on entire row hover (vs icon only)
        capWarning     = true,   -- highlight amount when currency is at its cap
        capWarningColor = { r = 1, g = 0.2, b = 0.2 },  -- color for capped amounts
    },
}

---------------------------------------------------------------------------
-- Local state
---------------------------------------------------------------------------
local framePool      = {}
local mainFrame      = nil
local anchorUnlocked = false

---------------------------------------------------------------------------
-- Currency API helpers
---------------------------------------------------------------------------

function ECT:ParseCurrencyID(str)
    if not str then return nil end
    local id = tonumber(str)
    if id then return id end
    local parsed = str:match("currency:(%d+)")
    if parsed then return tonumber(parsed) end
    parsed = str:match("(%d+)")
    if parsed and #str < 7 then return tonumber(parsed) end
    return nil
end

function ECT:GetCurrencyInfoByID(id)
    if not id then return nil end
    -- Modern API (Dragonflight+)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
        if ok and info then
            return {
                id                     = id,
                name                   = info.name or ("Currency " .. tostring(id)),
                amount                 = info.quantity or 0,
                icon                   = info.iconFileID,
                max                    = info.maxQuantity,
                -- Seasonal / weekly cap fields
                totalEarned            = info.totalEarned or 0,
                useTotalEarnedForMaxQty = info.useTotalEarnedForMaxQty or false,
                canEarnPerWeek         = info.canEarnPerWeek or false,
                maxWeeklyQuantity      = info.maxWeeklyQuantity or 0,
                earnedThisWeek         = info.quantityEarnedThisWeek or 0,
            }
        end
    end
    return { id = id, name = ("Currency " .. tostring(id)), amount = 0, icon = nil }
end

---------------------------------------------------------------------------
-- Display helpers
---------------------------------------------------------------------------

--- Format a number with comma separators (e.g. 1234567 -> "1,234,567").
function ECT:FormatNumber(n)
    if not n or n == 0 then return "0" end
    local s = tostring(math.floor(n))
    local pos = #s % 3
    if pos == 0 then pos = 3 end
    local parts = { s:sub(1, pos) }
    for i = pos + 1, #s, 3 do
        parts[#parts + 1] = s:sub(i, i + 2)
    end
    return table.concat(parts, ",")
end

--- Format a currency amount string, applying comma formatting and max cap.
function ECT:FormatAmount(info)
    local profile = self.db.profile
    local amount = info.amount or 0
    local str
    if profile.formatNumbers then
        str = self:FormatNumber(amount)
    else
        str = tostring(amount)
    end
    if profile.showMax and info.max and info.max > 0 then
        local maxStr = profile.formatNumbers and self:FormatNumber(info.max) or tostring(info.max)
        str = str .. " / " .. maxStr
    end
    return str
end

--- Check whether a currency has reached its cap (weekly, seasonal, or simple).
--- @param info table  Info table from GetCurrencyInfoByID()
--- @return boolean
function ECT:IsAtCap(info)
    if not info then return false end

    -- Weekly cap: earnedThisWeek >= maxWeeklyQuantity
    if info.canEarnPerWeek and info.maxWeeklyQuantity and info.maxWeeklyQuantity > 0 then
        if (info.earnedThisWeek or 0) >= info.maxWeeklyQuantity then
            return true
        end
    end

    -- Total / seasonal cap
    if info.max and info.max > 0 then
        if info.useTotalEarnedForMaxQty then
            -- Seasonal: compare lifetime earned vs seasonal max
            return (info.totalEarned or 0) >= info.max
        else
            -- Simple wallet cap: compare current held amount vs max
            return info.amount >= info.max
        end
    end

    return false
end

---------------------------------------------------------------------------
-- Tracked currency management
---------------------------------------------------------------------------

function ECT:IsTracked(id)
    for _, v in ipairs(self.db.profile.tracked) do
        if v == id then return true end
    end
    return false
end

function ECT:AddCurrency(id)
    if not id then return false, "invalid id" end
    local tracked = self.db.profile.tracked
    if #tracked >= 18 then
        return false, "Limit of 18 tracked currencies reached"
    end
    for _, v in ipairs(tracked) do
        if v == id then return false, "already tracked" end
    end
    tinsert(tracked, id)
    self:RebuildLines()
    return true
end

function ECT:RemoveCurrency(id)
    if not id then return false, "invalid id" end
    local tracked = self.db.profile.tracked
    for i, v in ipairs(tracked) do
        if v == id then
            tremove(tracked, i)
            self:RebuildLines()
            return true
        end
    end
    return false, "not found"
end

function ECT:ToggleTracked(id)
    if self:IsTracked(id) then
        self:RemoveCurrency(id)
        return false
    else
        self:AddCurrency(id)
        return true
    end
end

function ECT:MoveCurrency(fromIndex, toIndex)
    local tracked = self.db.profile.tracked
    if fromIndex < 1 or fromIndex > #tracked then return end
    if toIndex < 1 or toIndex > #tracked then return end
    local val = tremove(tracked, fromIndex)
    tinsert(tracked, toIndex, val)
    self:RebuildLines()
end

---------------------------------------------------------------------------
-- Frame pool and line rendering
---------------------------------------------------------------------------

--- Shared tooltip handler: show currency tooltip anchored to the given frame.
local function ShowCurrencyTooltip(owner, currencyID)
    if not currencyID then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local info = ECT:GetCurrencyInfoByID(currencyID)
    if info and info.id then
        local link
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
            local ok, l = pcall(C_CurrencyInfo.GetCurrencyLink, info.id, 0)
            link = ok and l
        end
        if link then
            GameTooltip:SetHyperlink(link)
        else
            GameTooltip:SetText(info.name or ("Currency " .. info.id))
            GameTooltip:AddLine("Amount: " .. tostring(info.amount), 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function AcquireLine(index)
    local profile = ECT.db.profile
    local f = framePool[index]

    if not f then
        f = CreateFrame("Frame", ADDON_NAME .. "Line" .. index, mainFrame)
        f:SetSize(profile.anchor.width or 240, profile.lineHeight)

        -- Row background texture (for alternating shading)
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(1, 1, 1, 0.06)

        -- Icon texture (direct child, no sub-frame needed when row tooltip is used)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        local iconSize = profile.lineHeight - 4
        f.icon:SetSize(iconSize, iconSize)

        -- Amount text
        f.amount = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.amount:SetJustifyH("RIGHT")

        -- Name text
        f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.name:SetJustifyH("LEFT")

        -- Row-level mouse handling (tooltip + mouse-through toggle)
        f:EnableMouse(true)
        f:SetScript("OnEnter", function(self)
            if ECT.db.profile.rowTooltip then
                ShowCurrencyTooltip(self, self.id)
            end
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)

        f.id = nil
        framePool[index] = f
    end

    f:Show()
    return f
end

--- Reconfigure a line's anchors for icon side and text layout.
--- Called during RebuildLines when layout may have changed.
local function LayoutLine(line, profile)
    local iconSize = profile.lineHeight - 4
    line.icon:ClearAllPoints()
    line.amount:ClearAllPoints()
    line.name:ClearAllPoints()
    line.icon:SetSize(iconSize, iconSize)

    if profile.iconSide == "RIGHT" then
        -- Icon on right, amount left of icon, name on left
        line.icon:SetPoint("RIGHT", line, "RIGHT", -2, 0)
        line.amount:SetPoint("RIGHT", line.icon, "LEFT", -6, 0)
        line.name:SetPoint("LEFT", line, "LEFT", 4, 0)
        line.name:SetPoint("RIGHT", line.amount, "LEFT", -4, 0)
    else
        -- Icon on left, name right of icon, amount on right
        line.icon:SetPoint("LEFT", line, "LEFT", 2, 0)
        line.name:SetPoint("LEFT", line.icon, "RIGHT", 6, 0)
        line.name:SetPoint("RIGHT", line.amount, "LEFT", -4, 0)
        line.amount:SetPoint("RIGHT", line, "RIGHT", -4, 0)
    end
end

local function ReleaseUnusedLines(startIndex)
    for i = startIndex, #framePool do
        if framePool[i] then framePool[i]:Hide() end
    end
end

function ECT:RebuildLines()
    if not mainFrame then return end
    local profile = self.db.profile
    local tracked = profile.tracked
    local N = #tracked
    local lineHeight = profile.lineHeight or 20
    local fc = profile.fontColor
    local fontSize = profile.fontSize or 12

    mainFrame:SetWidth(profile.anchor.width or 240)

    -- Title offset: accounts for 4px backdrop top inset + title height + gap
    local titleOffset
    if profile.titleStyle == "FULL" then
        titleOffset = 26   -- 4 inset + 18 title + 4 gap
    elseif profile.titleStyle == "SMALL" then
        titleOffset = 20   -- 4 inset + 12 title + 4 gap
    else -- "NONE"
        titleOffset = 8    -- 4 inset + 4 pad
    end

    for i = 1, N do
        local id = tracked[i]
        local info = self:GetCurrencyInfoByID(id)
        if info then
            local line = AcquireLine(i)
            line:SetSize(mainFrame:GetWidth() - 8, lineHeight)
            LayoutLine(line, profile)

            -- Alternating row shading
            if profile.altRowShading and (i % 2 == 0) then
                line.bg:SetColorTexture(1, 1, 1, 0.06)
                line.bg:Show()
            elseif profile.altRowShading then
                line.bg:SetColorTexture(0, 0, 0, 0.03)
                line.bg:Show()
            else
                line.bg:Hide()
            end

            -- Icon
            if info.icon then
                line.icon:SetTexture(info.icon)
                line.icon:Show()
            else
                line.icon:Hide()
            end

            -- Font and colors
            line.amount:SetFont(profile.font, fontSize)
            -- Cap warning: color the amount when at cap (seasonal, weekly, or simple)
            if profile.capWarning and self:IsAtCap(info) then
                local cc = profile.capWarningColor
                line.amount:SetTextColor(cc.r, cc.g, cc.b)
            else
                line.amount:SetTextColor(fc.r, fc.g, fc.b)
            end
            line.amount:SetText(self:FormatAmount(info))

            line.name:SetFont(profile.font, fontSize)
            line.name:SetTextColor(fc.r, fc.g, fc.b)
            line.name:SetText(info.name or ("Currency " .. id))
            line.id = id

            -- Mouse-through: when enabled, clicks pass through lines
            line:EnableMouse(not profile.mouseThrough)

            -- Row tooltip vs icon-only tooltip
            -- When rowTooltip is off, we still want the row to be transparent to
            -- mouse events (unless mouseThrough is also off, which is handled above).

            -- Positioning (x=4 to clear left backdrop inset)
            line:ClearAllPoints()
            if profile.grow == "UP" then
                if i == 1 then
                    line:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 4, 8)
                else
                    line:SetPoint("BOTTOMLEFT", framePool[i - 1], "TOPLEFT", 0, 2)
                end
            else -- DOWN
                if i == 1 then
                    line:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -titleOffset)
                else
                    line:SetPoint("TOPLEFT", framePool[i - 1], "BOTTOMLEFT", 0, -2)
                end
            end
        end
    end

    ReleaseUnusedLines(N + 1)
    local height = titleOffset + (N * (lineHeight + 2)) + 8   -- +8 = 4 bottom pad + 4 bottom inset
    mainFrame:SetHeight(height)
end

function ECT:UpdateAll()
    local profile = self.db.profile
    local tracked = profile.tracked
    local fc = profile.fontColor
    local fontSize = profile.fontSize or 12

    for i = 1, #tracked do
        local id = tracked[i]
        local info = self:GetCurrencyInfoByID(id)
        local line = framePool[i]
        if line and info then
            if info.icon then
                line.icon:SetTexture(info.icon)
                line.icon:Show()
            else
                line.icon:Hide()
            end
            line.amount:SetFont(profile.font, fontSize)
            -- Cap warning: color the amount when at cap (seasonal, weekly, or simple)
            if profile.capWarning and self:IsAtCap(info) then
                local cc = profile.capWarningColor
                line.amount:SetTextColor(cc.r, cc.g, cc.b)
            else
                line.amount:SetTextColor(fc.r, fc.g, fc.b)
            end
            line.amount:SetText(self:FormatAmount(info))

            line.name:SetFont(profile.font, fontSize)
            line.name:SetTextColor(fc.r, fc.g, fc.b)
            line.name:SetText(info.name or ("Currency " .. id))
        end
    end
end

---------------------------------------------------------------------------
-- Main display frame
---------------------------------------------------------------------------

function ECT:SaveAnchorPosition()
    local profile = self.db.profile
    local point, _, relativePoint, x, y = mainFrame:GetPoint(1)
    profile.anchor.point = point
    profile.anchor.relativePoint = relativePoint
    profile.anchor.x = x
    profile.anchor.y = y
    profile.anchor.width = mainFrame:GetWidth()
    profile.anchor.scale = mainFrame:GetScale()
end

function ECT:CreateMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", ADDON_NAME .. "MainFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    mainFrame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    local alpha = self.db.profile.bgAlpha or 0.6
    mainFrame:SetBackdropColor(0, 0, 0, alpha)
    mainFrame:SetBackdropBorderColor(0, 0, 0, alpha * 0.8)

    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(false)

    -- Drag bar: spans the title area, visible only when anchor is unlocked
    local dragBar = CreateFrame("Frame", nil, mainFrame)
    dragBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -4)
    dragBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -4, -4)
    dragBar:SetHeight(20)

    dragBar.bg = dragBar:CreateTexture(nil, "BACKGROUND")
    dragBar.bg:SetAllPoints()
    dragBar.bg:SetColorTexture(1, 0.82, 0, 0.15)

    dragBar.text = dragBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragBar.text:SetPoint("CENTER")
    dragBar.text:SetText("Drag to move")
    dragBar.text:SetTextColor(1, 0.82, 0, 0.8)

    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function()
        mainFrame:StartMoving()
    end)
    dragBar:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        ECT:SaveAnchorPosition()
    end)

    dragBar:Hide()
    mainFrame.dragBar = dragBar

    -- Settings button (gear icon, opens config to Currencies tab)
    local settingsBtn = CreateFrame("Button", nil, mainFrame)
    settingsBtn:SetSize(14, 14)
    settingsBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -6, -6)

    settingsBtn.icon = settingsBtn:CreateTexture(nil, "ARTWORK")
    settingsBtn.icon:SetAllPoints()
    settingsBtn.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsBtn.icon:SetDesaturated(true)
    settingsBtn:SetAlpha(0.4)

    settingsBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        self.icon:SetDesaturated(false)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Open Currency Settings")
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.4)
        self.icon:SetDesaturated(true)
        GameTooltip:Hide()
    end)
    settingsBtn:SetScript("OnClick", function()
        local ACD = LibStub("AceConfigDialog-3.0")
        ACD:Open(ADDON_NAME)
        ACD:SelectGroup(ADDON_NAME, "currencies")
    end)

    -- Keep the button above the drag bar when anchor is unlocked
    settingsBtn:SetFrameLevel(mainFrame:GetFrameLevel() + 4)
    mainFrame.settingsBtn = settingsBtn

    self:UpdateMainFrame()
end

function ECT:UpdateMainFrame()
    if not mainFrame then return end
    local profile = self.db.profile

    mainFrame:ClearAllPoints()
    mainFrame:SetSize(profile.anchor.width, 200)
    mainFrame:SetPoint(
        profile.anchor.point, UIParent,
        profile.anchor.relativePoint,
        profile.anchor.x, profile.anchor.y)
    mainFrame:SetScale(profile.anchor.scale or 1)

    -- Background opacity
    local alpha = profile.bgAlpha or 0.6
    mainFrame:SetBackdropColor(0, 0, 0, alpha)
    mainFrame:SetBackdropBorderColor(0, 0, 0, alpha * 0.8)

    -- Title (positioned inside the backdrop insets: left=4 + 4pad, top=4 + 2pad)
    if not mainFrame.title then
        mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        mainFrame.title:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, -6)
    end

    local ts = profile.titleStyle or "SMALL"
    if ts == "FULL" then
        mainFrame.title:SetFontObject(GameFontNormalLarge)
        mainFrame.title:SetText("Ella's Currency Tracker")
        mainFrame.title:SetTextColor(profile.titleColor.r, profile.titleColor.g, profile.titleColor.b)
        mainFrame.title:Show()
    elseif ts == "SMALL" then
        mainFrame.title:SetFontObject(GameFontNormalSmall)
        mainFrame.title:SetText("Ella's Currency Tracker")
        mainFrame.title:SetTextColor(profile.titleColor.r, profile.titleColor.g, profile.titleColor.b)
        mainFrame.title:Show()
    else -- "NONE"
        mainFrame.title:Hide()
    end

    self:RebuildLines()
end

function ECT:ToggleAnchor()
    if not mainFrame then self:CreateMainFrame() end
    anchorUnlocked = not anchorUnlocked
    if mainFrame.dragBar then
        if anchorUnlocked then
            mainFrame.dragBar:Show()
        else
            mainFrame.dragBar:Hide()
        end
    end
    self:Print(anchorUnlocked and "Anchor unlocked - drag to move" or "Anchor locked")
end

---------------------------------------------------------------------------
-- AceAddon lifecycle
---------------------------------------------------------------------------

function ECT:OnInitialize()
    -- Snapshot old saved variables BEFORE AceDB takes over the global table.
    -- AceDB:New() restructures _G.EllasCurrencyTrackerDB and adds profileKeys,
    -- which would make the old data undetectable after the call.
    local oldSV, oldCharSV
    if self:HasOldData() then
        oldSV, oldCharSV = self:SnapshotOldData()
    end

    self.db = LibStub("AceDB-3.0"):New("EllasCurrencyTrackerDB", self.DB_DEFAULTS, true)

    -- Migrate old SavedVariables format if present (uses the pre-AceDB snapshot)
    if oldSV then
        self:MigrateOldData(oldSV, oldCharSV)
    end

    -- Upgrade showTitle -> titleStyle for any profile (new or migrated)
    self:UpgradeShowTitleCompat()

    -- React to profile switches
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied",  "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset",   "OnProfileChanged")

    -- Set up AceConfig options (defined in Config.lua)
    self:SetupConfig()

    -- Register slash commands
    self:RegisterChatCommand("ect", "SlashCommand")
end

function ECT:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyUpdate")
    self:RegisterEvent("BAG_UPDATE_DELAYED",      "OnCurrencyUpdate")
    self:RegisterEvent("CHAT_MSG_CURRENCY",       "OnCurrencyUpdate")
end

function ECT:OnProfileChanged()
    self:UpgradeShowTitleCompat()
    if mainFrame then
        self:UpdateMainFrame()
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
end

function ECT:OnPlayerEnteringWorld()
    self:CreateMainFrame()
    self:RebuildLines()
end

function ECT:OnCurrencyUpdate()
    self:UpdateAll()
end

---------------------------------------------------------------------------
-- Data migration from old (pre-Ace3) SavedVariables
---------------------------------------------------------------------------

--- Quick check whether the old (pre-Ace3) saved variable format is present.
--- No copies are made — this just inspects the raw globals.
function ECT:HasOldData()
    local rawGlobal = _G.EllasCurrencyTrackerDB
    local rawChar   = _G.EllasCurrencyCharacterProfile
    return type(rawGlobal) == "table"
       and type(rawGlobal.profiles) == "table"
       and not rawGlobal.profileKeys
       and type(rawChar) == "table"
       and rawChar.activeProfile ~= nil
end

--- Shallow-copy a table (one level deep).
local function shallowCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

--- Snapshot the old saved variables before AceDB:New() overwrites them.
--- Must be called BEFORE AceDB:New("EllasCurrencyTrackerDB", ...).
--- Caller should check HasOldData() first.
function ECT:SnapshotOldData()
    local rawGlobal = _G.EllasCurrencyTrackerDB
    local rawChar   = _G.EllasCurrencyCharacterProfile

    -- Deep-enough copy: copy each profile's top-level fields, plus
    -- shallow-copy sub-tables (tracked, anchor, fontColor, titleColor).
    local snapProfiles = {}
    for name, profile in pairs(rawGlobal.profiles) do
        if type(profile) == "table" then
            snapProfiles[name] = {
                tracked    = shallowCopy(profile.tracked),
                grow       = profile.grow,
                lineHeight = profile.lineHeight,
                font       = profile.font,
                anchor     = shallowCopy(profile.anchor),
                fontColor  = shallowCopy(profile.fontColor),
                titleColor = shallowCopy(profile.titleColor),
            }
        end
    end

    local snapGlobal = { profiles = snapProfiles }
    local snapChar   = { activeProfile = rawChar.activeProfile }
    return snapGlobal, snapChar
end

--- Migrate data from the pre-Ace3 snapshot into the current AceDB profile.
--- @param oldSV table|nil  Snapshot of old EllasCurrencyTrackerDB
--- @param oldCharSV table|nil  Snapshot of old EllasCurrencyCharacterProfile
function ECT:MigrateOldData(oldSV, oldCharSV)
    if not oldSV or not oldCharSV then return end

    -- Already have tracked currencies in the new profile — skip migration
    if #self.db.profile.tracked > 0 then return end

    -- Find the old profile by the name stored in the per-character variable
    local oldName    = oldCharSV.activeProfile
    local oldProfile = oldSV.profiles[oldName]

    -- If the exact name didn't match, also try a case-insensitive search
    -- (old addon used "default", AceDB convention is "Default")
    if not oldProfile then
        for name, profile in pairs(oldSV.profiles) do
            if name:lower() == oldName:lower() then
                oldProfile = profile
                break
            end
        end
    end

    if not oldProfile or not oldProfile.tracked or #oldProfile.tracked == 0 then
        return
    end

    -- Copy data into the current AceDB profile
    local p = self.db.profile
    p.tracked    = oldProfile.tracked
    p.grow       = oldProfile.grow or "DOWN"
    p.lineHeight = oldProfile.lineHeight or 20
    p.font       = oldProfile.font or p.font

    if oldProfile.anchor then
        for k, v in pairs(oldProfile.anchor) do p.anchor[k] = v end
    end

    -- Old colors were arrays {r, g, b}; convert to keyed {r=, g=, b=}
    if oldProfile.fontColor and type(oldProfile.fontColor[1]) == "number" then
        p.fontColor = {
            r = oldProfile.fontColor[1],
            g = oldProfile.fontColor[2],
            b = oldProfile.fontColor[3],
        }
    end
    if oldProfile.titleColor and type(oldProfile.titleColor[1]) == "number" then
        p.titleColor = {
            r = oldProfile.titleColor[1],
            g = oldProfile.titleColor[2],
            b = oldProfile.titleColor[3],
        }
    end

    -- Clear the obsolete per-character variable so migration doesn't re-trigger
    EllasCurrencyCharacterProfile = nil

    self:Print("Migrated data from old profile format.")
end

--- Upgrade in-place: convert old boolean showTitle to new titleStyle string.
--- Safe to call on any profile at any time.
function ECT:UpgradeShowTitleCompat()
    local p = self.db.profile
    if p.showTitle ~= nil then
        -- Old format: true/false boolean
        if p.showTitle == true then
            p.titleStyle = p.titleStyle or "SMALL"
        elseif p.showTitle == false then
            p.titleStyle = "NONE"
        end
        p.showTitle = nil   -- remove deprecated key
    end
end

---------------------------------------------------------------------------
-- Slash command handler
---------------------------------------------------------------------------

function ECT:SlashCommand(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "add" and rest ~= "" then
        local id = self:ParseCurrencyID(rest)
        if not id then
            self:Print("Could not parse currency id from input.")
            return
        end
        local ok, err = self:AddCurrency(id)
        if ok then
            self:Print("Added currency id " .. id)
            LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
        else
            self:Print(err or "failed")
        end

    elseif cmd == "remove" and rest ~= "" then
        local id = tonumber(rest)
        if not id then
            self:Print("Please provide a numeric currency id.")
            return
        end
        local ok, err = self:RemoveCurrency(id)
        if ok then
            self:Print("Removed " .. id)
            LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
        else
            self:Print(err or "failed")
        end

    elseif cmd == "list" then
        local tracked = self.db.profile.tracked
        if #tracked == 0 then
            self:Print("No currencies tracked.")
        else
            self:Print("Tracked currencies:")
            for i, id in ipairs(tracked) do
                local info = self:GetCurrencyInfoByID(id)
                if info then
                    self:Print(("[%d] %s  id:%d  amount:%s"):format(
                        i, info.name or "?", id, tostring(info.amount)))
                end
            end
        end

    elseif cmd == "grow" and rest ~= "" then
        local dir = rest:upper()
        if dir == "UP" or dir == "DOWN" then
            self.db.profile.grow = dir
            self:Print("Growth direction set to " .. dir)
            self:RebuildLines()
        else
            self:Print("Usage: /ect grow up|down")
        end

    elseif cmd == "anchor" then
        self:CreateMainFrame()
        self:ToggleAnchor()

    elseif cmd == "config" then
        self:OpenConfig()

    elseif cmd == "reset" then
        self.db:ResetProfile()
        self:Print("Profile reset to defaults.")

    elseif cmd == "help" or cmd == "" then
        self:PrintHelp()

    else
        self:Print("Unknown command. Type /ect help for usage.")
    end
end

function ECT:PrintHelp()
    self:Print("Commands:")
    self:Print("  /ect config         - open settings")
    self:Print("  /ect add <id|link>  - add currency")
    self:Print("  /ect remove <id>    - remove currency")
    self:Print("  /ect list           - list tracked currencies")
    self:Print("  /ect grow up|down   - set growth direction")
    self:Print("  /ect anchor         - toggle anchor move mode")
    self:Print("  /ect reset          - reset current profile")
end
