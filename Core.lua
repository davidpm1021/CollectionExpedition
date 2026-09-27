local ADDON_NAME, CE = ...

CE.VERSION = "0.2.1"
CE.state = CE.state or {}

local DEFAULT_STATE = {
    active = false,
    regionKey = nil,
    route = {},
    currentIndex = 0,
    skipped = {},
    acquiredThisRun = 0,
    pendingWaypoint = false,
    budgetMinutes = nil,
    startedAt = nil,
    plannedMinutes = 0,
}

for key, value in pairs(DEFAULT_STATE) do
    if CE.state[key] == nil then
        CE.state[key] = value
    end
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Collection Expedition:|r " .. tostring(msg))
end
CE.Print = Print

local function DistanceSq(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end

local function CopyTableShallow(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

function CE:IsOwned(objective)
    if not objective then
        return false
    end

    if objective.kind == "mount" then
        if not C_MountJournal or not C_MountJournal.GetMountInfoByID then
            return false
        end
        local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(objective.id)
        return isCollected == true
    end

    if objective.kind == "pet" then
        if not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then
            return false
        end
        local numCollected = C_PetJournal.GetNumCollectedInfo(objective.id)
        return (numCollected or 0) > 0
    end

    return false
end

function CE:GetObjectiveName(objective)
    if not objective then
        return "Unknown"
    end

    if objective.kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local name = C_MountJournal.GetMountInfoByID(objective.id)
        if name then
            return name
        end
    elseif objective.kind == "pet" and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local name = C_PetJournal.GetPetInfoBySpeciesID(objective.id)
        if name then
            return name
        end
    end

    return objective.name or (objective.kind .. " " .. tostring(objective.id))
end

function CE:GetMissingObjectives(regionKey, includeSkipped)
    local region = CE.Data.regions[regionKey]
    local missing = {}
    if not region then
        return missing
    end

    for _, objective in ipairs(region.objectives) do
        local skipped = self.state.skipped[objective.key] == true
        if not self:IsOwned(objective) and (includeSkipped or not skipped) then
            table.insert(missing, objective)
        end
    end

    return missing
end

function CE:GetPlayerPositionForRegion(region)
    if not region or not C_Map then
        return region and region.fallbackStart.x or 0.5, region and region.fallbackStart.y or 0.5
    end

    local pos = C_Map.GetPlayerMapPosition(region.mapID, "player")
    if pos and pos.GetXY then
        local x, y = pos:GetXY()
        if x and y and x > 0 and y > 0 then
            return x, y
        end
    end

    return region.fallbackStart.x, region.fallbackStart.y
end

function CE:GetTravelMinutes(region, ax, ay, bx, by)
    local distance = math.sqrt(DistanceSq(ax, ay, bx, by))
    return distance * (region.travelMinutesPerMapUnit or 7)
end

function CE:GetObjectiveAttemptMinutes(objective)
    return objective.estimatedAttemptMinutes or 8
end

function CE:GetObjectiveScore(objective, travelMinutes)
    local attemptMinutes = self:GetObjectiveAttemptMinutes(objective)
    local totalMinutes = math.max(1, travelMinutes + attemptMinutes)
    local successWeight = objective.successWeight or 0.20
    local collectionWeight = objective.collectionWeight or (objective.kind == "mount" and 2.0 or 1.0)

    -- Expected collection value per minute. This is a routing heuristic, not a
    -- statement of exact drop probability.
    return (successWeight * collectionWeight * 100) / totalMinutes
end

function CE:GetRemainingBudgetMinutes()
    if not self.state.budgetMinutes then
        return nil
    end

    if not self.state.startedAt then
        return self.state.budgetMinutes
    end

    local elapsed = math.max(0, (GetTime() - self.state.startedAt) / 60)
    return math.max(0, self.state.budgetMinutes - elapsed)
end

function CE:BuildRoute(regionKey, budgetMinutes)
    local region = CE.Data.regions[regionKey]
    if not region then
        return {}, 0
    end

    local candidates = self:GetMissingObjectives(regionKey)
    local route = {}
    local cx, cy = self:GetPlayerPositionForRegion(region)
    local remainingBudget = budgetMinutes or math.huge
    local plannedMinutes = 0

    while #candidates > 0 do
        local bestIndex = nil
        local bestScore = -math.huge
        local bestTravel = 0
        local bestCost = 0

        for index, objective in ipairs(candidates) do
            local travelMinutes = self:GetTravelMinutes(region, cx, cy, objective.x, objective.y)
            local costMinutes = travelMinutes + self:GetObjectiveAttemptMinutes(objective)

            if costMinutes <= remainingBudget then
                local score = self:GetObjectiveScore(objective, travelMinutes)
                if score > bestScore then
                    bestScore = score
                    bestIndex = index
                    bestTravel = travelMinutes
                    bestCost = costMinutes
                end
            end
        end

        if not bestIndex then
            break
        end

        local sourceObjective = table.remove(candidates, bestIndex)
        local nextObjective = CopyTableShallow(sourceObjective)
        nextObjective.plannedTravelMinutes = bestTravel
        nextObjective.plannedCostMinutes = bestCost
        nextObjective.plannerScore = bestScore
        table.insert(route, nextObjective)

        plannedMinutes = plannedMinutes + bestCost
        remainingBudget = remainingBudget - bestCost
        cx, cy = nextObjective.x, nextObjective.y
    end

    return route, plannedMinutes
end

function CE:GetCurrentObjective()
    if not self.state.active then
        return nil
    end
    return self.state.route[self.state.currentIndex]
end

function CE:GetWhyText(objective)
    if not objective then
        return "No active stop."
    end

    local travel = objective.plannedTravelMinutes or 0
    local attempt = self:GetObjectiveAttemptMinutes(objective)
    local total = objective.plannedCostMinutes or (travel + attempt)
    local score = objective.plannerScore or self:GetObjectiveScore(objective, travel)
    local kindValue = objective.kind == "mount" and "Mounts receive extra collection value in mixed routes." or "Pets are scored as one collection gain."

    return string.format(
        "|cffffffffWhy this stop?|r\n\n" ..
        "|cff66ccffEstimated route cost:|r %.1f min\n" ..
        "  %.1f min travel + %.1f min useful attempt\n\n" ..
        "|cff66ccffOpportunity:|r %s\n" ..
        "|cff66ccffAvailability:|r %s\n" ..
        "|cff66ccffPlanner score:|r %.2f value/min\n\n" ..
        "%s\n\n%s",
        total,
        travel,
        attempt,
        objective.chanceLabel or "Unknown",
        objective.availabilityLabel or objective.method or "Unknown",
        score,
        kindValue,
        objective.note or "The planner selected this because it currently offers a strong balance of travel cost and collection opportunity."
    )
end

function CE:ClearWaypoint()
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
    end
    if C_Map and C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end
end

function CE:SetWaypoint(objective)
    if not objective or not C_Map or not C_Map.SetUserWaypoint then
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        self.state.pendingWaypoint = true
        return false
    end

    local point = {
        uiMapID = objective.mapID or CE.Data.regions[self.state.regionKey].mapID,
        position = CreateVector2D(objective.x, objective.y),
    }

    local ok, wasSet = pcall(C_Map.SetUserWaypoint, point)
    if ok and wasSet ~= false then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        self.state.pendingWaypoint = false
        return true
    end

    return false
end

function CE:RefreshWaypoint()
    local objective = self:GetCurrentObjective()
    if objective then
        self:SetWaypoint(objective)
    end
end

function CE:Start(regionKey, budgetMinutes)
    regionKey = regionKey or "timeless"
    local region = CE.Data.regions[regionKey]
    if not region then
        Print("Unknown region. Try |cffffffff/ce plan|r")
        return
    end

    self.state.active = true
    self.state.regionKey = regionKey
    self.state.skipped = {}
    self.state.acquiredThisRun = 0
    self.state.budgetMinutes = budgetMinutes
    self.state.startedAt = GetTime()
    self.state.currentIndex = 1
    self.state.route, self.state.plannedMinutes = self:BuildRoute(regionKey, budgetMinutes)

    if #self.state.route == 0 then
        local missing = #self:GetMissingObjectives(regionKey)
        self:Stop(false)
        if missing == 0 then
            Print("You already own every collectible supported in " .. region.name .. ". Nice.")
        else
            Print("No supported stop fits that time budget from the current route position.")
        end
        return
    end

    local budgetLabel = budgetMinutes and (tostring(budgetMinutes) .. " min") or "until you stop"
    Print(string.format(
        "Expedition started: %s, %s. %d planned stops, about %.0f planned minutes.",
        region.name,
        budgetLabel,
        #self.state.route,
        self.state.plannedMinutes
    ))

    self:RefreshWaypoint()
    if self.UI then
        self.UI:HidePlanner()
        self.UI:ShowTracker()
        self.UI:Refresh()
    end
end

function CE:Stop(announce)
    if announce == nil then
        announce = true
    end
    self.state.active = false
    self.state.route = {}
    self.state.currentIndex = 0
    self.state.pendingWaypoint = false
    self.state.budgetMinutes = nil
    self.state.startedAt = nil
    self.state.plannedMinutes = 0
    self:ClearWaypoint()

    if self.UI then
        self.UI:Refresh()
    end
    if announce then
        Print("Expedition stopped.")
    end
end

function CE:FinishExpedition(reason)
    local region = CE.Data.regions[self.state.regionKey]
    local regionName = region and region.name or "Expedition"
    local acquired = self.state.acquiredThisRun
    local missing = #self:GetMissingObjectives(self.state.regionKey, true)

    self:Stop(false)

    if reason == "complete" or missing == 0 then
        Print(string.format("Collection route complete: %s. %d collected this run.", regionName, acquired))
    else
        Print(string.format("Time-budget expedition complete: %s. %d collected this run.", regionName, acquired))
    end

    if self.UI then
        self.UI:ShowCompletion(regionName, acquired, missing, reason)
    end
end

function CE:RebuildFromCurrentPosition()
    if not self.state.active or not self.state.regionKey then
        return
    end

    local remainingBudget = self:GetRemainingBudgetMinutes()
    self.state.route, self.state.plannedMinutes = self:BuildRoute(self.state.regionKey, remainingBudget)
    self.state.currentIndex = 1

    if #self.state.route == 0 then
        local remaining = #self:GetMissingObjectives(self.state.regionKey, true)
        self:FinishExpedition(remaining == 0 and "complete" or "budget")
        return
    end

    self:RefreshWaypoint()
    if self.UI then
        self.UI:Refresh()
    end
end

function CE:Advance(skipCurrent)
    local current = self:GetCurrentObjective()
    if not current then
        return
    end

    if skipCurrent and not self:IsOwned(current) then
        self.state.skipped[current.key] = true
        Print("Skipped for this run: " .. self:GetObjectiveName(current))
    end

    self:RebuildFromCurrentPosition()
end

function CE:CheckCurrentCompletion(reason)
    local current = self:GetCurrentObjective()
    if not current then
        return
    end

    if self:IsOwned(current) then
        self.state.acquiredThisRun = self.state.acquiredThisRun + 1
        Print("Collected: |cffffffff" .. self:GetObjectiveName(current) .. "|r")
        if PlaySound then
            pcall(PlaySound, SOUNDKIT and SOUNDKIT.UI_70_ARTIFACT_FORGE_APPEARANCE_LOCKED or 847)
        end
        self:RebuildFromCurrentPosition()
    elseif self.UI then
        self.UI:Refresh()
    end
end

function CE:Status()
    if not self.state.active then
        Print("No active expedition. Use |cffffffff/ce plan|r")
        return
    end

    local objective = self:GetCurrentObjective()
    local remaining = #self:GetMissingObjectives(self.state.regionKey, true)
    local budgetRemaining = self:GetRemainingBudgetMinutes()
    local budgetText = budgetRemaining and string.format(" %.0f min budget remaining.", budgetRemaining) or ""
    if objective then
        Print(string.format(
            "Next: %s at %.1f, %.1f. %d supported collectibles remain.%s",
            self:GetObjectiveName(objective),
            objective.x * 100,
            objective.y * 100,
            remaining,
            budgetText
        ))
    end
end

function CE:Reset()
    self:Stop(false)
    self.state.skipped = {}
    Print("Session reset.")
end

function CE:OpenPlanner()
    if self.UI then
        self.UI:ShowPlanner()
    end
end

function CE:HandleSlash(msg)
    local command, arg1, arg2 = string.match(string.lower(msg or ""), "^(%S*)%s*(%S*)%s*(.-)$")

    if command == "" then
        self:OpenPlanner()
    elseif command == "help" then
        if self.UI then
            self.UI:ToggleHelp(true)
        end
    elseif command == "plan" then
        self:OpenPlanner()
    elseif command == "start" then
        if arg1 == "" then
            self:OpenPlanner()
        elseif arg1 == "30" or arg1 == "60" or arg1 == "120" then
            self:Start("timeless", tonumber(arg1))
        elseif arg1 == "timeless" and (arg2 == "30" or arg2 == "60" or arg2 == "120") then
            self:Start("timeless", tonumber(arg2))
        elseif arg1 == "all" or arg1 == "timeless" then
            self:Start("timeless", nil)
        else
            Print("Use |cffffffff/ce start 30|r, |cffffffff/ce start 60|r, |cffffffff/ce start 120|r, or |cffffffff/ce start all|r")
        end
    elseif command == "stop" then
        self:Stop(true)
    elseif command == "next" or command == "skip" then
        self:Advance(true)
    elseif command == "status" then
        self:Status()
    elseif command == "show" then
        if self.UI then
            self.UI:ShowTracker()
            self.UI:Refresh()
        end
    elseif command == "why" then
        if self.UI then
            self.UI:ToggleWhy(true)
        end
    elseif command == "reset" then
        self:Reset()
    else
        Print("Unknown command. Use |cffffffff/ce help|r")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("NEW_MOUNT_ADDED")
eventFrame:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= ADDON_NAME then
            return
        end
        CollectionExpeditionDB = CollectionExpeditionDB or {}
        CE.db = CollectionExpeditionDB
    elseif event == "PLAYER_LOGIN" then
        SLASH_COLLECTIONEXPEDITION1 = "/collectionexpedition"
        SLASH_COLLECTIONEXPEDITION2 = "/ce"
        SLASH_COLLECTIONEXPEDITION3 = "/expedition"
        SlashCmdList.COLLECTIONEXPEDITION = function(msg)
            CE:HandleSlash(msg)
        end
        if CE.UI then
            CE.UI:Initialize()
        end
        Print("v" .. CE.VERSION .. " loaded. Click the minimap map icon or type |cffffffff/ce|r to plan an expedition.")
    elseif event == "NEW_MOUNT_ADDED" then
        local mountID = ...
        local current = CE:GetCurrentObjective()
        if current and current.kind == "mount" and current.id == mountID then
            C_Timer.After(0.25, function() CE:CheckCurrentCompletion("mount") end)
        elseif CE.state.active and CE.UI then
            CE.UI:Refresh()
        end
    elseif event == "PET_JOURNAL_LIST_UPDATE" then
        if CE.state.active then
            C_Timer.After(0.35, function() CE:CheckCurrentCompletion("pet") end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if CE.state.active and CE.state.pendingWaypoint then
            CE:RefreshWaypoint()
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if CE.state.active then
            C_Timer.After(1.0, function()
                CE:RefreshWaypoint()
                if CE.UI then CE.UI:Refresh() end
            end)
        end
    end
end)
