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
        showTitle   = true,
        anchor = {
            point         = "CENTER",
            relativePoint = "CENTER",
            x             = 0,
            y             = 0,
            width         = 240,
            scale         = 1,
        },
        lineHeight  = 20,
        font        = "Fonts\\FRIZQT__.TTF",
        fontSize    = 12,
        fontColor   = { r = 1, g = 1, b = 1 },
        titleColor  = { r = 1, g = 1, b = 1 },
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
                id     = id,
                name   = info.name or ("Currency " .. tostring(id)),
                amount = info.quantity or 0,
                icon   = info.iconFileID,
                max    = info.maxQuantity,
            }
        end
    end
    return { id = id, name = ("Currency " .. tostring(id)), amount = 0, icon = nil }
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

local function AcquireLine(index)
    local profile = ECT.db.profile
    local f = framePool[index]
    if f and f:IsShown() then return f end

    if not f then
        f = CreateFrame("Frame", ADDON_NAME .. "Line" .. index, mainFrame)
        f:SetSize(profile.anchor.width or 240, profile.lineHeight)

        -- Icon container (separate frame for tooltip hit-testing)
        f.iconFrame = CreateFrame("Frame", nil, f)
        local iconSize = profile.lineHeight - 4
        f.iconFrame:SetSize(iconSize, iconSize)
        f.iconFrame:SetPoint("RIGHT", -2, 0)
        f.iconFrame.icon = f.iconFrame:CreateTexture(nil, "ARTWORK")
        f.iconFrame.icon:SetSize(iconSize, iconSize)
        f.iconFrame.icon:SetPoint("CENTER")

        -- Tooltip on icon hover
        f.iconFrame:EnableMouse(true)
        f.iconFrame:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            if not parent or not parent.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local info = ECT:GetCurrencyInfoByID(parent.id)
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
        end)
        f.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Amount (right-aligned, next to icon)
        f.amount = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.amount:SetPoint("RIGHT", f.iconFrame, "LEFT", -6, 0)
        f.amount:SetJustifyH("RIGHT")

        -- Name (left-aligned)
        f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.name:SetPoint("LEFT", 2, 0)
        f.name:SetJustifyH("LEFT")

        f.id = nil
        framePool[index] = f
    end
    f:Show()
    return f
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

    for i = 1, N do
        local id = tracked[i]
        local info = self:GetCurrencyInfoByID(id)
        if info then
            local line = AcquireLine(i)
            line:SetSize(mainFrame:GetWidth(), lineHeight)

            -- Update icon size to match current lineHeight
            local iconSize = lineHeight - 4
            line.iconFrame:SetSize(iconSize, iconSize)
            line.iconFrame.icon:SetSize(iconSize, iconSize)

            if info.icon then
                line.iconFrame.icon:SetTexture(info.icon)
                line.iconFrame.icon:Show()
                line.iconFrame:Show()
            else
                line.iconFrame:Hide()
            end

            line.amount:SetFont(profile.font, fontSize)
            line.amount:SetTextColor(fc.r, fc.g, fc.b)
            line.amount:SetText(tostring(info.amount))

            line.name:SetFont(profile.font, fontSize)
            line.name:SetTextColor(fc.r, fc.g, fc.b)
            line.name:SetText(info.name or ("Currency " .. id))
            line.id = id

            line:ClearAllPoints()
            if profile.grow == "UP" then
                if i == 1 then
                    line:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 4, 16)
                else
                    line:SetPoint("BOTTOMLEFT", framePool[i - 1], "TOPLEFT", 0, 2)
                end
            else -- DOWN
                if i == 1 then
                    line:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, profile.showTitle and -20 or -4)
                else
                    line:SetPoint("TOPLEFT", framePool[i - 1], "BOTTOMLEFT", 0, -2)
                end
            end
        end
    end

    ReleaseUnusedLines(N + 1)
    local titleOffset = profile.showTitle and 20 or 4
    local height = titleOffset + (N * (lineHeight + 2)) + 4
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
                line.iconFrame.icon:SetTexture(info.icon)
                line.iconFrame.icon:Show()
                line.iconFrame:Show()
            else
                line.iconFrame:Hide()
            end
            line.amount:SetFont(profile.font, fontSize)
            line.amount:SetTextColor(fc.r, fc.g, fc.b)
            line.amount:SetText(tostring(info.amount))

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
    mainFrame:SetBackdropColor(0, 0, 0, 0)
    mainFrame:SetBackdropBorderColor(0, 0, 0, 0)

    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:EnableMouse(false)
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)

    -- Anchor drag handle
    local btn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    btn:SetSize(18, 5)
    btn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 5, 0)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture("Interface\\Buttons\\GoldGradiant")
    btn:EnableMouse(true)
    btn:SetAlpha(0.7)
    btn.icon:SetDesaturated(true)

    btn:SetScript("OnMouseDown", function()
        if anchorUnlocked then mainFrame:StartMoving() end
    end)
    btn:SetScript("OnMouseUp", function()
        if anchorUnlocked then
            mainFrame:StopMovingOrSizing()
            ECT:SaveAnchorPosition()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(anchorUnlocked
            and "Drag to move"
            or "Anchor locked \226\128\148 use /ect anchor to unlock")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.anchorBtn = btn

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

    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ECT:SaveAnchorPosition()
    end)

    -- Title
    if not mainFrame.title then
        mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        mainFrame.title:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 6, 0)
    end
    if profile.showTitle then
        mainFrame.title:SetText("Ella's Currency Tracker")
        mainFrame.title:SetTextColor(profile.titleColor.r, profile.titleColor.g, profile.titleColor.b)
        mainFrame.title:Show()
    else
        mainFrame.title:Hide()
    end

    self:RebuildLines()
end

function ECT:ToggleAnchor()
    if not mainFrame then self:CreateMainFrame() end
    anchorUnlocked = not anchorUnlocked
    mainFrame:EnableMouse(anchorUnlocked)
    if mainFrame.anchorBtn then
        mainFrame.anchorBtn:SetAlpha(anchorUnlocked and 1 or 0.7)
        mainFrame.anchorBtn.icon:SetDesaturated(not anchorUnlocked)
    end
    self:Print(anchorUnlocked and "Anchor unlocked - drag to move" or "Anchor locked")
end

---------------------------------------------------------------------------
-- AceAddon lifecycle
---------------------------------------------------------------------------

function ECT:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("EllasCurrencyTrackerDB", self.DB_DEFAULTS, true)

    -- Migrate old SavedVariables format if present
    self:MigrateOldData()

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

function ECT:MigrateOldData()
    -- Detect old per-character variable from the pre-Ace3 version
    if type(EllasCurrencyCharacterProfile) == "table"
       and EllasCurrencyCharacterProfile.activeProfile then
        local oldGlobal = _G.EllasCurrencyTrackerDB
        -- Old format had a flat "profiles" table (no AceDB "profileKeys")
        if oldGlobal and oldGlobal.profiles and not oldGlobal.profileKeys then
            local oldName    = EllasCurrencyCharacterProfile.activeProfile
            local oldProfile = oldGlobal.profiles[oldName]
            if oldProfile and oldProfile.tracked and #self.db.profile.tracked == 0 then
                local p = self.db.profile
                p.tracked    = oldProfile.tracked or {}
                p.grow       = oldProfile.grow or "DOWN"
                p.lineHeight = oldProfile.lineHeight or 20
                p.font       = oldProfile.font or p.font
                if oldProfile.anchor then
                    for k, v in pairs(oldProfile.anchor) do p.anchor[k] = v end
                end
                -- Old colors were {r, g, b} arrays; convert to {r=, g=, b=}
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
                self:Print("Migrated data from old profile format.")
            end
        end
        -- Clear the obsolete per-character variable
        EllasCurrencyCharacterProfile = nil
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
