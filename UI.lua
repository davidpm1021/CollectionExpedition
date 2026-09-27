local ADDON_NAME, CE = ...

CE.UI = CE.UI or {}
local UI = CE.UI

local tracker
local planner
local whyPanel
local helpPanel
local minimapButton

local function SavePosition(frame)
    if not CE.db then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    CE.db.trackerPoint = point
    CE.db.trackerRelativePoint = relativePoint
    CE.db.trackerX = x
    CE.db.trackerY = y
end

local function ApplyBackdrop(frame, r, g, b)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.04, 0.05, 0.07, 0.96)
    frame:SetBackdropBorderColor(r or 0.25, g or 0.9, b or 0.65, 0.95)
end

local function Atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end
    return 0
end

local function PositionMinimapButton()
    if not minimapButton or not Minimap then return end
    local angle = (CE.db and CE.db.minimapAngle) or 225
    local radians = math.rad(angle)
    local radius = 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

local function UpdateMinimapButtonDrag()
    if not minimapButton or not Minimap then return end
    local mx, my = Minimap:GetCenter()
    if not mx or not my then return end

    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale

    local angle = math.deg(Atan2(cy - my, cx - mx))
    if CE.db then
        CE.db.minimapAngle = angle
    end
    PositionMinimapButton()
end

function UI:Initialize()
    if tracker then return end

    tracker = CreateFrame("Frame", "CollectionExpeditionTracker", UIParent, "BackdropTemplate")
    tracker:SetSize(390, 182)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetClampedToScreen(true)
    tracker:SetMovable(true)
    tracker:EnableMouse(true)
    tracker:RegisterForDrag("LeftButton")
    tracker:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    tracker:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    ApplyBackdrop(tracker)

    if CE.db and CE.db.trackerPoint then
        tracker:SetPoint(CE.db.trackerPoint, UIParent, CE.db.trackerRelativePoint or CE.db.trackerPoint, CE.db.trackerX or 0, CE.db.trackerY or 0)
    else
        tracker:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end

    tracker.title = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tracker.title:SetPoint("TOPLEFT", 14, -12)
    tracker.title:SetText("COLLECTION EXPEDITION")
    tracker.title:SetTextColor(0.3, 1.0, 0.7)

    tracker.progress = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tracker.progress:SetPoint("TOPRIGHT", -38, -15)
    tracker.progress:SetJustifyH("RIGHT")

    tracker.kind = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tracker.kind:SetPoint("TOPLEFT", 14, -40)
    tracker.kind:SetTextColor(0.8, 0.8, 0.8)

    tracker.name = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    tracker.name:SetPoint("TOPLEFT", 14, -58)
    tracker.name:SetPoint("RIGHT", -14, 0)
    tracker.name:SetJustifyH("LEFT")
    tracker.name:SetWordWrap(false)

    tracker.source = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tracker.source:SetPoint("TOPLEFT", 14, -84)
    tracker.source:SetPoint("RIGHT", -14, 0)
    tracker.source:SetJustifyH("LEFT")

    tracker.coords = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tracker.coords:SetPoint("TOPLEFT", 14, -105)
    tracker.coords:SetTextColor(0.65, 0.9, 1.0)

    tracker.plan = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tracker.plan:SetPoint("TOPLEFT", 14, -125)
    tracker.plan:SetTextColor(0.9, 0.82, 0.4)

    tracker.nextButton = CreateFrame("Button", nil, tracker, "UIPanelButtonTemplate")
    tracker.nextButton:SetSize(78, 24)
    tracker.nextButton:SetPoint("BOTTOMRIGHT", -12, 10)
    tracker.nextButton:SetText("Skip")
    tracker.nextButton:SetScript("OnClick", function() CE:Advance(true) end)

    tracker.mapButton = CreateFrame("Button", nil, tracker, "UIPanelButtonTemplate")
    tracker.mapButton:SetSize(78, 24)
    tracker.mapButton:SetPoint("RIGHT", tracker.nextButton, "LEFT", -6, 0)
    tracker.mapButton:SetText("Map")
    tracker.mapButton:SetScript("OnClick", function()
        local current = CE:GetCurrentObjective()
        if not current then return end
        CE:RefreshWaypoint()
        if not InCombatLockdown() and C_Map and C_Map.OpenWorldMap then
            C_Map.OpenWorldMap(current.mapID or CE.Data.regions[CE.state.regionKey].mapID)
        end
    end)

    tracker.whyButton = CreateFrame("Button", nil, tracker, "UIPanelButtonTemplate")
    tracker.whyButton:SetSize(78, 24)
    tracker.whyButton:SetPoint("RIGHT", tracker.mapButton, "LEFT", -6, 0)
    tracker.whyButton:SetText("Why?")
    tracker.whyButton:SetScript("OnClick", function() UI:ToggleWhy() end)

    tracker.planButton = CreateFrame("Button", nil, tracker, "UIPanelButtonTemplate")
    tracker.planButton:SetSize(78, 24)
    tracker.planButton:SetPoint("RIGHT", tracker.whyButton, "LEFT", -6, 0)
    tracker.planButton:SetText("New Plan")
    tracker.planButton:SetScript("OnClick", function() UI:ShowPlanner() end)

    tracker.closeButton = CreateFrame("Button", nil, tracker, "UIPanelCloseButton")
    tracker.closeButton:SetPoint("TOPRIGHT", 4, 4)

    whyPanel = CreateFrame("Frame", "CollectionExpeditionWhyPanel", tracker, "BackdropTemplate")
    whyPanel:SetSize(390, 235)
    whyPanel:SetPoint("TOP", tracker, "BOTTOM", 0, -4)
    whyPanel:SetFrameStrata("MEDIUM")
    ApplyBackdrop(whyPanel, 0.35, 0.65, 1.0)

    whyPanel.title = whyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    whyPanel.title:SetPoint("TOPLEFT", 14, -12)
    whyPanel.title:SetText("WHY THIS STOP?")
    whyPanel.title:SetTextColor(0.45, 0.8, 1.0)

    whyPanel.text = whyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    whyPanel.text:SetPoint("TOPLEFT", 14, -40)
    whyPanel.text:SetPoint("BOTTOMRIGHT", -14, 14)
    whyPanel.text:SetJustifyH("LEFT")
    whyPanel.text:SetJustifyV("TOP")
    whyPanel.text:SetWordWrap(true)

    whyPanel:Hide()
    tracker:Hide()

    planner = CreateFrame("Frame", "CollectionExpeditionPlanner", UIParent, "BackdropTemplate")
    planner:SetSize(430, 250)
    planner:SetPoint("CENTER")
    planner:SetFrameStrata("DIALOG")
    planner:SetClampedToScreen(true)
    ApplyBackdrop(planner, 0.9, 0.75, 0.25)

    planner.title = planner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    planner.title:SetPoint("TOP", 0, -18)
    planner.title:SetText("PLAN AN EXPEDITION")
    planner.title:SetTextColor(1.0, 0.85, 0.3)

    planner.subtitle = planner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    planner.subtitle:SetPoint("TOP", 0, -48)
    planner.subtitle:SetWidth(390)
    planner.subtitle:SetText("How much time do you have?\nV0.2 will build the highest-value Timeless Isle route that fits.")

    local function AddBudgetButton(label, minutes, x, y)
        local button = CreateFrame("Button", nil, planner, "UIPanelButtonTemplate")
        button:SetSize(170, 34)
        button:SetPoint("TOPLEFT", x, y)
        button:SetText(label)
        button:SetScript("OnClick", function()
            CE:Start("timeless", minutes)
        end)
        return button
    end

    AddBudgetButton("30 minutes", 30, 38, -100)
    AddBudgetButton("60 minutes", 60, 222, -100)
    AddBudgetButton("120 minutes", 120, 38, -146)
    AddBudgetButton("Until I stop", nil, 222, -146)

    planner.note = planner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    planner.note:SetPoint("BOTTOM", 0, 22)
    planner.note:SetWidth(390)
    planner.note:SetText("Times and success values are planning heuristics, not guarantees. Rare spawns and drops can always run long.")
    planner.note:SetTextColor(0.75, 0.75, 0.75)

    planner.closeButton = CreateFrame("Button", nil, planner, "UIPanelCloseButton")
    planner.closeButton:SetPoint("TOPRIGHT", 4, 4)

    planner:Hide()

    helpPanel = CreateFrame("Frame", "CollectionExpeditionHelpPanel", UIParent, "BackdropTemplate")
    helpPanel:SetSize(430, 390)
    helpPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    helpPanel:SetFrameStrata("DIALOG")
    helpPanel:SetClampedToScreen(true)
    ApplyBackdrop(helpPanel, 0.35, 0.75, 1.0)

    helpPanel.title = helpPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    helpPanel.title:SetPoint("TOPLEFT", 16, -16)
    helpPanel.title:SetText("COLLECTION EXPEDITION HELP")
    helpPanel.title:SetTextColor(0.45, 0.85, 1.0)

    helpPanel.text = helpPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpPanel.text:SetPoint("TOPLEFT", 16, -48)
    helpPanel.text:SetPoint("BOTTOMRIGHT", -16, 16)
    helpPanel.text:SetJustifyH("LEFT")
    helpPanel.text:SetJustifyV("TOP")
    helpPanel.text:SetWordWrap(true)
    helpPanel.text:SetText(
        "|cffffffffYou do not need slash commands.|r\n" ..
        "Left-click the minimap map icon to open the planner.\n" ..
        "Right-click it to open this help panel. Drag it around the minimap to move it.\n\n" ..
        "|cff66ccffCommands|r\n" ..
        "/ce  - open planner\n" ..
        "/ce plan  - open planner\n" ..
        "/ce start 30  - start a 30-minute route\n" ..
        "/ce start 60  - start a 60-minute route\n" ..
        "/ce start 120  - start a 120-minute route\n" ..
        "/ce start all  - open-ended route\n" ..
        "/ce status  - show current target and remaining budget\n" ..
        "/ce why  - explain the current stop\n" ..
        "/ce next  - skip this stop and reroute\n" ..
        "/ce show  - reopen the tracker\n" ..
        "/ce stop  - stop the expedition and clear its waypoint\n" ..
        "/ce reset  - reset the current session\n" ..
        "/ce help  - open this panel"
    )

    helpPanel.closeButton = CreateFrame("Button", nil, helpPanel, "UIPanelCloseButton")
    helpPanel.closeButton:SetPoint("TOPRIGHT", 4, 4)
    helpPanel:Hide()

    if Minimap then
        minimapButton = CreateFrame("Button", "CollectionExpeditionMinimapButton", Minimap)
        minimapButton:SetSize(32, 32)
        minimapButton:SetFrameStrata("MEDIUM")
        minimapButton:SetFrameLevel(8)
        minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        minimapButton:RegisterForDrag("LeftButton")

        local border = minimapButton:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetSize(54, 54)
        border:SetPoint("CENTER", 10, -10)

        local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
        icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        minimapButton:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                UI:ToggleHelp()
            else
                UI:ShowPlanner()
            end
        end)

        minimapButton:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", UpdateMinimapButtonDrag)
        end)
        minimapButton:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            UpdateMinimapButtonDrag()
        end)

        minimapButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Collection Expedition", 0.3, 1.0, 0.7)
            GameTooltip:AddLine("Left-click: Plan an expedition", 1, 1, 1)
            GameTooltip:AddLine("Right-click: Commands & help", 1, 1, 1)
            GameTooltip:AddLine("Drag: Move this button", 0.8, 0.8, 0.8)

            local current = CE:GetCurrentObjective()
            if current then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Current: " .. CE:GetObjectiveName(current), 1.0, 0.82, 0.35)
            end
            GameTooltip:Show()
        end)
        minimapButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        PositionMinimapButton()
    end
end

function UI:ShowPlanner()
    if not planner then self:Initialize() end
    planner:Show()
end

function UI:HidePlanner()
    if planner then planner:Hide() end
end

function UI:ShowTracker()
    if not tracker then self:Initialize() end
    tracker:Show()
end

function UI:ToggleHelp(forceShow)
    if not helpPanel then self:Initialize() end
    if forceShow == true then
        helpPanel:Show()
    elseif helpPanel:IsShown() then
        helpPanel:Hide()
    else
        helpPanel:Show()
    end
end

function UI:ToggleWhy(forceShow)
    if not whyPanel then self:Initialize() end
    local current = CE:GetCurrentObjective()
    if not current then
        whyPanel:Hide()
        return
    end

    whyPanel.text:SetText(CE:GetWhyText(current))
    if forceShow == true then
        whyPanel:Show()
    elseif whyPanel:IsShown() then
        whyPanel:Hide()
    else
        whyPanel:Show()
    end
end

function UI:Refresh()
    if not tracker then return end

    local current = CE:GetCurrentObjective()
    if not CE.state.active or not current then
        tracker.progress:SetText("Not running")
        tracker.kind:SetText("Type /ce plan")
        tracker.name:SetText("Choose an expedition")
        tracker.source:SetText("V0.2 supports Timeless Isle")
        tracker.coords:SetText("")
        tracker.plan:SetText("")
        if whyPanel then whyPanel:Hide() end
        return
    end

    local region = CE.Data.regions[CE.state.regionKey]
    local remaining = #CE:GetMissingObjectives(CE.state.regionKey, true)
    local icon = current.kind == "mount" and "MOUNT" or "PET"
    local budgetRemaining = CE:GetRemainingBudgetMinutes()

    tracker.progress:SetText(string.format("%d remaining", remaining))
    tracker.kind:SetText(string.format("%s  •  %s", icon, region.name))
    tracker.name:SetText(CE:GetObjectiveName(current))
    tracker.source:SetText(string.format("%s: %s", current.method or "Source", current.source or "Unknown"))
    tracker.coords:SetText(string.format("Next stop  %.1f, %.1f", current.x * 100, current.y * 100))

    if budgetRemaining then
        tracker.plan:SetText(string.format("~%.1f min this stop  •  %.0f min budget left", current.plannedCostMinutes or 0, budgetRemaining))
    else
        tracker.plan:SetText(string.format("~%.1f min this stop  •  open-ended expedition", current.plannedCostMinutes or 0))
    end

    if whyPanel and whyPanel:IsShown() then
        whyPanel.text:SetText(CE:GetWhyText(current))
    end
end

function UI:ShowCompletion(regionName, acquired, remaining, reason)
    if not tracker then self:Initialize() end
    tracker:Show()
    tracker.progress:SetText(reason == "complete" and "Complete" or "Budget done")
    tracker.kind:SetText(regionName or "Expedition")
    tracker.name:SetText(reason == "complete" and "Collection route complete!" or "Expedition complete!")
    tracker.source:SetText(string.format("Collected this run: %d  •  Still missing: %d", acquired or 0, remaining or 0))
    tracker.coords:SetText("/ce plan to build another expedition")
    tracker.plan:SetText("")
    if whyPanel then whyPanel:Hide() end
end
