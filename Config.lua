-- Config.lua
-- Ella's Currency Tracker - AceConfig options and Blizzard Settings integration
-- Author: theswiftfox

local ADDON_NAME = "EllasCurrencyTracker"
local ECT = _G.EllasCurrencyTracker

local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions    = LibStub("AceDBOptions-3.0")

---------------------------------------------------------------------------
-- Currency discovery (collects all currencies visible to the character)
---------------------------------------------------------------------------

-- Cache: { [headerName] = { { id=, name=, amount=, icon= }, ... }, ... }
ECT.discoveredCategories = {}
-- Flat lookup: { [currencyID] = { id=, name=, amount=, icon=, category= } }
ECT.discoveredFlat = {}
-- Search filter state
ECT.currencyFilter = ""

function ECT:DiscoverCurrencies()
    local categories = {}
    local flat = {}

    if not (C_CurrencyInfo
            and C_CurrencyInfo.GetCurrencyListSize
            and C_CurrencyInfo.GetCurrencyListInfo) then
        self.discoveredCategories = categories
        self.discoveredFlat = flat
        return
    end

    -- Remember which headers were originally expanded
    local wasExpanded = {}
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
        if ok and info and info.isHeader and info.isHeaderExpanded and info.name then
            wasExpanded[info.name] = true
        end
    end

    -- Expand all collapsed headers (repeat until stable)
    local function ExpandAll()
        local changed = false
        for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
            if ok and info and info.isHeader and not info.isHeaderExpanded then
                pcall(C_CurrencyInfo.ExpandCurrencyList, i, true)
                changed = true
            end
        end
        return changed
    end
    repeat until not ExpandAll()

    -- Collect all entries grouped by header
    local currentHeader = "General"
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
        if ok and info then
            if info.isHeader then
                currentHeader = info.name or "Other"
                if not categories[currentHeader] then
                    categories[currentHeader] = {}
                end
            else
                local id = info.currencyID
                if id then
                    if not categories[currentHeader] then
                        categories[currentHeader] = {}
                    end
                    local entry = {
                        id       = id,
                        name     = info.name,
                        amount   = info.quantity or 0,
                        icon     = info.iconFileID,
                        category = currentHeader,
                    }
                    tinsert(categories[currentHeader], entry)
                    flat[id] = entry
                end
            end
        end
    end

    -- Restore original header expansion state
    local function RestoreHeaders()
        local changed = false
        for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
            if ok and info and info.isHeader and info.isHeaderExpanded and info.name then
                if not wasExpanded[info.name] then
                    pcall(C_CurrencyInfo.ExpandCurrencyList, i, false)
                    changed = true
                end
            end
        end
        return changed
    end
    repeat until not RestoreHeaders()

    -- Ensure tracked currencies appear even if not in the character's list
    for _, id in ipairs(self.db.profile.tracked) do
        if not flat[id] then
            local info = self:GetCurrencyInfoByID(id)
            if info then
                local entry = {
                    id       = id,
                    name     = info.name,
                    amount   = info.amount or 0,
                    icon     = info.icon,
                    category = "Other",
                }
                if not categories["Other"] then categories["Other"] = {} end
                tinsert(categories["Other"], entry)
                flat[id] = entry
            end
        end
    end

    self.discoveredCategories = categories
    self.discoveredFlat = flat
end

---------------------------------------------------------------------------
-- Helpers for building dynamic options
---------------------------------------------------------------------------

--- Format a currency name with an inline icon texture for AceConfig display.
local function CurrencyLabel(info)
    local icon = info.icon
    local name = info.name or ("Currency " .. tostring(info.id))
    if icon then
        return ("|T%s:16:16:0:0|t  %s"):format(tostring(icon), name)
    end
    return name
end

--- Format a currency description showing the current amount.
local function CurrencyDesc(info)
    local amount = info.amount or 0
    return "Current amount: " .. tostring(amount) .. "  |  ID: " .. tostring(info.id)
end

---------------------------------------------------------------------------
-- Build the "Currencies" tab: categorized toggles for discovery/tracking
---------------------------------------------------------------------------

local function BuildCurrencyArgs()
    local args = {}
    local filter = (ECT.currencyFilter or ""):lower()

    -- Search box
    args.search = {
        type  = "input",
        name  = "Search",
        desc  = "Filter currencies by name",
        order = 1,
        width = "double",
        get   = function() return ECT.currencyFilter or "" end,
        set   = function(_, val)
            ECT.currencyFilter = val
            LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
        end,
    }
    args.refresh = {
        type = "execute",
        name = "Refresh List",
        desc = "Re-scan all available currencies",
        order = 2,
        func = function()
            ECT:DiscoverCurrencies()
            LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
        end,
    }
    args.spacer = {
        type = "description",
        name = " ",
        order = 3,
        width = "full",
    }

    -- Sort category names for stable ordering
    local sortedCats = {}
    for cat in pairs(ECT.discoveredCategories) do
        tinsert(sortedCats, cat)
    end
    table.sort(sortedCats)

    for catIdx, catName in ipairs(sortedCats) do
        local entries = ECT.discoveredCategories[catName]
        local catKey = "cat_" .. catIdx
        local catArgs = {}
        local hasVisibleEntry = false

        -- Sort entries within category by name
        local sorted = {}
        for _, e in ipairs(entries) do tinsert(sorted, e) end
        table.sort(sorted, function(a, b) return (a.name or "") < (b.name or "") end)

        for entryIdx, entry in ipairs(sorted) do
            local matchesFilter = (filter == "")
                or (entry.name and entry.name:lower():find(filter, 1, true))
            if matchesFilter then
                hasVisibleEntry = true
                local cid = entry.id
                catArgs["c" .. cid] = {
                    type  = "toggle",
                    name  = CurrencyLabel(entry),
                    desc  = CurrencyDesc(entry),
                    order = entryIdx,
                    width = "full",
                    get   = function() return ECT:IsTracked(cid) end,
                    set   = function(_, val)
                        ECT:ToggleTracked(cid)
                        LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                    end,
                }
            end
        end

        if hasVisibleEntry then
            args[catKey] = {
                type   = "group",
                name   = catName,
                order  = 10 + catIdx,
                inline = true,
                args   = catArgs,
            }
        end
    end

    return args
end

---------------------------------------------------------------------------
-- Build the "Tracked Order" tab: reorder and remove tracked currencies
---------------------------------------------------------------------------

local function BuildTrackedArgs()
    local args = {}
    local tracked = ECT.db.profile.tracked
    local N = #tracked

    if N == 0 then
        args.empty = {
            type  = "description",
            name  = "No currencies tracked yet. Use the Currencies tab to add some.",
            order = 1,
            width = "full",
            fontSize = "medium",
        }
        return args
    end

    args.header = {
        type  = "description",
        name  = ("Tracking %d / 18 currencies. Drag to reorder using the buttons below."):format(N),
        order = 0,
        width = "full",
        fontSize = "medium",
    }

    for i = 1, N do
        local id = tracked[i]
        local info = ECT.discoveredFlat[id] or ECT:GetCurrencyInfoByID(id)
        local slotKey = "slot" .. i

        args[slotKey] = {
            type   = "group",
            name   = CurrencyLabel(info),
            order  = i,
            inline = true,
            args   = {
                moveUp = {
                    type     = "execute",
                    name     = "Move Up",
                    order    = 1,
                    width    = 0.6,
                    disabled = (i == 1),
                    func     = function()
                        ECT:MoveCurrency(i, i - 1)
                        LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                    end,
                },
                moveDown = {
                    type     = "execute",
                    name     = "Move Down",
                    order    = 2,
                    width    = 0.6,
                    disabled = (i == N),
                    func     = function()
                        ECT:MoveCurrency(i, i + 1)
                        LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                    end,
                },
                remove = {
                    type  = "execute",
                    name  = "Remove",
                    order = 3,
                    width = 0.6,
                    func  = function()
                        ECT:RemoveCurrency(id)
                        LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                    end,
                },
            },
        }
    end

    return args
end

---------------------------------------------------------------------------
-- Main options table
---------------------------------------------------------------------------

local function GetOptions()
    local options = {
        type = "group",
        name = "Ella's Currency Tracker",
        childGroups = "tab",
        args = {
            -----------------------------------------------------------------
            -- Tab 1: Display settings
            -----------------------------------------------------------------
            display = {
                type  = "group",
                name  = "Display",
                order = 1,
                args  = {
                    headerGeneral = {
                        type  = "header",
                        name  = "General",
                        order = 1,
                    },
                    titleStyle = {
                        type   = "select",
                        name   = "Title Style",
                        desc   = "How to display the addon title above the currency lines",
                        order  = 2,
                        values = { FULL = "Full Size", SMALL = "Small / Subtle", NONE = "Hidden" },
                        get    = function() return ECT.db.profile.titleStyle end,
                        set    = function(_, val)
                            ECT.db.profile.titleStyle = val
                            ECT:UpdateMainFrame()
                        end,
                    },
                    titleText = {
                        type   = "input",
                        name   = "Title Text",
                        desc   = "Custom text displayed in the title bar",
                        order  = 2.5,
                        width  = "double",
                        disabled = function() return ECT.db.profile.titleStyle == "NONE" end,
                        get    = function() return ECT.db.profile.titleText end,
                        set    = function(_, val)
                            ECT.db.profile.titleText = val
                            ECT:UpdateMainFrame()
                        end,
                    },
                    titleTextReset = {
                        type  = "execute",
                        name  = "Reset Title",
                        desc  = "Reset the title text to its default value",
                        order = 2.6,
                        width = 0.7,
                        disabled = function()
                            return ECT.db.profile.titleText == ECT.DB_DEFAULTS.profile.titleText
                        end,
                        func  = function()
                            ECT.db.profile.titleText = ECT.DB_DEFAULTS.profile.titleText
                            ECT:UpdateMainFrame()
                            LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                        end,
                    },
                    growDirection = {
                        type   = "select",
                        name   = "Growth Direction",
                        desc   = "Direction the currency list grows from the anchor",
                        order  = 3,
                        values = { DOWN = "Down", UP = "Up" },
                        get    = function() return ECT.db.profile.grow end,
                        set    = function(_, val)
                            ECT.db.profile.grow = val
                            ECT:RebuildLines()
                        end,
                    },
                    iconSide = {
                        type   = "select",
                        name   = "Icon Position",
                        desc   = "Which side of the row to show the currency icon",
                        order  = 4,
                        values = { LEFT = "Left", RIGHT = "Right" },
                        get    = function() return ECT.db.profile.iconSide end,
                        set    = function(_, val)
                            ECT.db.profile.iconSide = val
                            ECT:RebuildLines()
                        end,
                    },
                    headerAppearance = {
                        type  = "header",
                        name  = "Appearance",
                        order = 10,
                    },
                    bgAlpha = {
                        type     = "range",
                        name     = "Background Opacity",
                        desc     = "Opacity of the overlay background (0 = invisible, 1 = opaque)",
                        order    = 11,
                        min      = 0,
                        max      = 1,
                        step     = 0.05,
                        isPercent = true,
                        get      = function() return ECT.db.profile.bgAlpha end,
                        set      = function(_, val)
                            ECT.db.profile.bgAlpha = val
                            ECT:UpdateMainFrame()
                        end,
                    },
                    altRowShading = {
                        type  = "toggle",
                        name  = "Alternating Row Shading",
                        desc  = "Apply subtle alternating background shading to rows",
                        order = 12,
                        width = "full",
                        get   = function() return ECT.db.profile.altRowShading end,
                        set   = function(_, val)
                            ECT.db.profile.altRowShading = val
                            ECT:RebuildLines()
                        end,
                    },
                    fontColor = {
                        type     = "color",
                        name     = "Currency Font Color",
                        desc     = "Color for currency names and amounts",
                        order    = 13,
                        hasAlpha = false,
                        get      = function()
                            local c = ECT.db.profile.fontColor
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            ECT.db.profile.fontColor = { r = r, g = g, b = b }
                            ECT:RebuildLines()
                        end,
                    },
                    titleColor = {
                        type     = "color",
                        name     = "Title Color",
                        desc     = "Color for the main title text",
                        order    = 14,
                        hasAlpha = false,
                        get      = function()
                            local c = ECT.db.profile.titleColor
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            ECT.db.profile.titleColor = { r = r, g = g, b = b }
                            ECT:UpdateMainFrame()
                        end,
                    },
                    headerFormatting = {
                        type  = "header",
                        name  = "Formatting",
                        order = 20,
                    },
                    formatNumbers = {
                        type  = "toggle",
                        name  = "Format Numbers",
                        desc  = "Add comma separators to large amounts (e.g. 1,234,567)",
                        order = 21,
                        width = "full",
                        get   = function() return ECT.db.profile.formatNumbers end,
                        set   = function(_, val)
                            ECT.db.profile.formatNumbers = val
                            ECT:RebuildLines()
                        end,
                    },
                    showMax = {
                        type  = "toggle",
                        name  = "Show Max / Cap",
                        desc  = "Display \"current / max\" for currencies that have a cap",
                        order = 22,
                        width = "full",
                        get   = function() return ECT.db.profile.showMax end,
                        set   = function(_, val)
                            ECT.db.profile.showMax = val
                            ECT:RebuildLines()
                        end,
                    },
                    capWarning = {
                        type  = "toggle",
                        name  = "Cap Warning",
                        desc  = "Highlight the amount in a warning color when a currency has reached its maximum cap",
                        order = 23,
                        width = "full",
                        get   = function() return ECT.db.profile.capWarning end,
                        set   = function(_, val)
                            ECT.db.profile.capWarning = val
                            ECT:RebuildLines()
                        end,
                    },
                    capWarningColor = {
                        type     = "color",
                        name     = "Cap Warning Color",
                        desc     = "Color used to highlight amounts that have reached the currency cap",
                        order    = 24,
                        hasAlpha = false,
                        disabled = function() return not ECT.db.profile.capWarning end,
                        get      = function()
                            local c = ECT.db.profile.capWarningColor
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            ECT.db.profile.capWarningColor = { r = r, g = g, b = b }
                            ECT:RebuildLines()
                        end,
                    },
                    headerInteraction = {
                        type  = "header",
                        name  = "Interaction",
                        order = 30,
                    },
                    rowTooltip = {
                        type  = "toggle",
                        name  = "Row-Wide Tooltip",
                        desc  = "Show currency tooltip when hovering anywhere on the row (instead of only the icon)",
                        order = 31,
                        width = "full",
                        get   = function() return ECT.db.profile.rowTooltip end,
                        set   = function(_, val)
                            ECT.db.profile.rowTooltip = val
                        end,
                    },
                    mouseThrough = {
                        type  = "toggle",
                        name  = "Mouse-Through",
                        desc  = "Allow mouse clicks to pass through the currency overlay",
                        order = 32,
                        width = "full",
                        get   = function() return ECT.db.profile.mouseThrough end,
                        set   = function(_, val)
                            ECT.db.profile.mouseThrough = val
                            ECT:RebuildLines()
                        end,
                    },
                    anchorLock = {
                        type  = "toggle",
                        name  = "Unlock Anchor",
                        desc  = "Unlock the overlay so it can be repositioned by dragging the title bar",
                        order = 33,
                        width = "full",
                        get   = function() return ECT:IsAnchorUnlocked() end,
                        set   = function(_, val)
                            ECT:ToggleAnchor()
                            LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
                        end,
                    },
                    headerSize = {
                        type  = "header",
                        name  = "Sizing",
                        order = 40,
                    },
                    fontSize = {
                        type     = "range",
                        name     = "Font Size",
                        desc     = "Size of the currency text",
                        order    = 41,
                        min      = 8,
                        max      = 20,
                        step     = 1,
                        get      = function() return ECT.db.profile.fontSize end,
                        set      = function(_, val)
                            ECT.db.profile.fontSize = val
                            ECT:RebuildLines()
                        end,
                    },
                    lineHeight = {
                        type     = "range",
                        name     = "Line Height",
                        desc     = "Pixel height of each currency line",
                        order    = 42,
                        min      = 14,
                        max      = 36,
                        step     = 1,
                        get      = function() return ECT.db.profile.lineHeight end,
                        set      = function(_, val)
                            ECT.db.profile.lineHeight = val
                            ECT:RebuildLines()
                        end,
                    },
                    frameWidth = {
                        type     = "range",
                        name     = "Frame Width",
                        desc     = "Width of the currency overlay",
                        order    = 43,
                        min      = 140,
                        max      = 400,
                        step     = 5,
                        get      = function() return ECT.db.profile.anchor.width end,
                        set      = function(_, val)
                            ECT.db.profile.anchor.width = val
                            ECT:UpdateMainFrame()
                        end,
                    },
                    frameScale = {
                        type      = "range",
                        name      = "Frame Scale",
                        desc      = "Overall scale of the currency overlay",
                        order     = 44,
                        min       = 0.5,
                        max       = 2.0,
                        step      = 0.05,
                        isPercent = true,
                        get       = function() return ECT.db.profile.anchor.scale end,
                        set       = function(_, val)
                            ECT.db.profile.anchor.scale = val
                            ECT:UpdateMainFrame()
                        end,
                    },
                },
            },

            -----------------------------------------------------------------
            -- Tab 2: Currency picker
            -----------------------------------------------------------------
            currencies = {
                type  = "group",
                name  = "Currencies",
                order = 2,
                args  = BuildCurrencyArgs(),
            },

            -----------------------------------------------------------------
            -- Tab 3: Tracked order management
            -----------------------------------------------------------------
            trackedOrder = {
                type  = "group",
                name  = "Tracked Order",
                order = 3,
                args  = BuildTrackedArgs(),
            },

            -----------------------------------------------------------------
            -- Tab 4: Profiles (auto-generated by AceDBOptions)
            -----------------------------------------------------------------
            profiles = AceDBOptions:GetOptionsTable(ECT.db),
        },
    }

    -- Ensure profiles tab has correct ordering
    options.args.profiles.order = 4

    return options
end

---------------------------------------------------------------------------
-- Options table wrapper for dynamic rebuild
---------------------------------------------------------------------------

-- AceConfigRegistry calls this function every time the dialog needs to
-- render, so dynamic content (currencies, tracked order) stays fresh.
local function OptionsTableProvider(uiType, uiName, appName)
    -- Rebuild dynamic tabs each time the config is accessed
    return GetOptions()
end

---------------------------------------------------------------------------
-- Setup (called from Core.lua OnInitialize)
---------------------------------------------------------------------------

function ECT:SetupConfig()
    -- Discover currencies for the first time
    self:DiscoverCurrencies()

    -- Register options with AceConfig (use a function provider for dynamic content)
    AceConfig:RegisterOptionsTable(ADDON_NAME, OptionsTableProvider)

    -- Add to Blizzard Settings panel
    local frame, categoryId = AceConfigDialog:AddToBlizOptions(ADDON_NAME, "Ella's Currency Tracker")
    self.settingsCategoryId = categoryId
end

function ECT:OpenConfig()
    if self.settingsCategoryId then
        Settings.OpenToCategory(self.settingsCategoryId)
    else
        -- Fallback if category registration failed for some reason
        AceConfigDialog:Open(ADDON_NAME)
    end
end
