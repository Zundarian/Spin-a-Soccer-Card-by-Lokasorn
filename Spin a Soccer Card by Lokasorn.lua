-- Spin a Soccer Card by Lokasorn v1.0
-- Modern client menu with reliable toggles and a configurable money delay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local VirtualInputManager
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local APP_NAME = "Spin a Soccer Card by Lokasorn"
local APP_VERSION = "v1.0"
local GUI_NAME = "Lokasorn_SpinSoccer_Menu"
local DISCORD_INVITE = "https://discord.gg/Xd3ZQ5rd7V"

local Settings = {
    MenuVisible = true,

    AutoMoney = false,
    AutoOpenPacks = false,
    AutoRebirth = false,
    AutoIndex = false,

    MoneyDelay = 2.0,
}

local Theme = {
    Background = Color3.fromRGB(12, 15, 20),
    Panel = Color3.fromRGB(21, 26, 34),
    Panel2 = Color3.fromRGB(28, 34, 44),
    Panel3 = Color3.fromRGB(35, 42, 54),
    Text = Color3.fromRGB(241, 245, 249),
    Muted = Color3.fromRGB(148, 163, 184),
    Line = Color3.fromRGB(64, 75, 92),
    Accent = Color3.fromRGB(20, 184, 166),
    AccentSoft = Color3.fromRGB(17, 94, 89),
    Warm = Color3.fromRGB(245, 158, 11),
    Good = Color3.fromRGB(34, 197, 94),
    Off = Color3.fromRGB(71, 85, 105),
    Danger = Color3.fromRGB(248, 113, 113),
    Discord = Color3.fromRGB(88, 101, 242),
}

local ScreenGui
local MenuFrame
local StatusLabel
local FeatureControls = {}
local LastRun = {}
local Busy = {}
local RemoteCache = {}
local RemoteCacheTime = 0
local PackState = {
    Stage = "waiting",
    LastAction = 0,
    LastPackSeen = 0,
    LastTarget = nil,
    LastResult = 0,
    LastResultPack = nil,
    LastAmount = 0,
    LastAutoPath = nil,
    LastHidePath = nil,
}
local IndexState = {
    LastClaimAll = 0,
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function clampDelay(value, minValue, maxValue, step)
    local numberValue = tonumber(value)
    if not numberValue then
        return minValue
    end

    numberValue = math.clamp(numberValue, minValue, maxValue)
    if step and step > 0 then
        numberValue = math.floor((numberValue / step) + 0.5) * step
    end

    return math.floor(numberValue * 100 + 0.5) / 100
end

local function formatDelay(value)
    local rounded = math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
    if rounded % 1 == 0 then
        return tostring(math.floor(rounded))
    end
    return string.format("%.2f", rounded):gsub("0+$", ""):gsub("%.$", "")
end

local function getPlayerGui()
    return LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
end

local function setStatus(text, color)
    if StatusLabel then
        StatusLabel.Text = trim(text)
        StatusLabel.TextColor3 = color or Theme.Muted
    end
end

local function addCorner(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
    return corner
end

local function addStroke(instance, color, transparency, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Theme.Line
    stroke.Transparency = transparency or 0
    stroke.Thickness = thickness or 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.LineJoinMode = Enum.LineJoinMode.Round
    stroke.Parent = instance
    return stroke
end

local function safeGetText(guiObject)
    local ok, value = pcall(function()
        return guiObject.Text
    end)

    if ok then
        return tostring(value or "")
    end

    return ""
end

local function isGuiVisible(guiObject)
    if not guiObject then
        return false
    end

    local current = guiObject
    while current do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end

        if current:IsA("ScreenGui") and not current.Enabled then
            return false
        end

        current = current.Parent
    end

    local okSize, size = pcall(function()
        return guiObject.AbsoluteSize
    end)

    return okSize and size.X > 0 and size.Y > 0
end

local function safeDescendants(root)
    if not root then
        return {}
    end

    local ok, descendants = pcall(function()
        return root:GetDescendants()
    end)

    if ok then
        return descendants
    end

    return {}
end

local function safeChildren(root)
    if not root then
        return {}
    end

    local ok, children = pcall(function()
        return root:GetChildren()
    end)

    if ok then
        return children
    end

    return {}
end

local function safeIsA(instance, className)
    if not instance then
        return false
    end

    local ok, result = pcall(function()
        return instance:IsA(className)
    end)

    return ok and result == true
end

local function safeFullName(instance)
    if not instance then
        return "<nil>"
    end

    local ok, name = pcall(function()
        return instance:GetFullName()
    end)

    if ok then
        return tostring(name)
    end

    return tostring(instance.Name or instance)
end

local function tracePackActionButton(kind, button)
    local path = safeFullName(button)
    local stateKey = kind == "Hide" and "LastHidePath" or "LastAutoPath"

    if PackState[stateKey] ~= path then
        PackState[stateKey] = path
        warn(APP_NAME .. " " .. kind .. " button: " .. path)
    end
end

local function getHaystack(guiObject)
    local text = safeGetText(guiObject)
    return lower((guiObject.Name or "") .. " " .. text .. " " .. safeFullName(guiObject))
end

local function containsAny(haystack, words)
    if not words or #words == 0 then
        return true
    end

    for _, word in ipairs(words) do
        if string.find(haystack, lower(word), 1, true) then
            return true
        end
    end

    return false
end

local function containsBlockedWord(haystack, blockedWords)
    for _, word in ipairs(blockedWords or {}) do
        if string.find(haystack, lower(word), 1, true) then
            return true
        end
    end

    return false
end

local function findByPath(root, pathParts)
    local current = root
    for _, part in ipairs(pathParts) do
        if not current then
            return nil
        end

        current = current:FindFirstChild(part)
    end

    return current
end

local function getGuiSearchRoots()
    local roots = { getPlayerGui() }

    local okCoreGui, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    if okCoreGui and coreGui then
        table.insert(roots, coreGui)
    end

    return roots
end

local function isLiveGuiObject(guiObject)
    if not guiObject or not safeIsA(guiObject, "GuiObject") then
        return false
    end

    local okParent, parent = pcall(function()
        return guiObject.Parent
    end)

    if not okParent or not parent then
        return false
    end

    for _, root in ipairs(getGuiSearchRoots()) do
        local ok, isDescendant = pcall(function()
            return guiObject:IsDescendantOf(root)
        end)

        if ok and isDescendant then
            return true
        end
    end

    return false
end

local function findButtons(root, includeWords, blockedWords, visibleOnly, limit)
    local results = {}
    for _, object in ipairs(safeDescendants(root)) do
        if safeIsA(object, "GuiButton") then
            local haystack = getHaystack(object)
            local isMatch = containsAny(haystack, includeWords) and not containsBlockedWord(haystack, blockedWords)
            if isMatch and (not visibleOnly or isGuiVisible(object)) then
                table.insert(results, object)
                if limit and #results >= limit then
                    break
                end
            end
        end
    end

    return results
end

local function activateGuiButton(button)
    if not isLiveGuiObject(button) then
        return false
    end

    if not isGuiVisible(button) then
        return false
    end

    pcall(function()
        button.Active = true
        if safeIsA(button, "GuiButton") then
            button.Selectable = true
        end
    end)

    local fired = false
    local centerX = 0
    local centerY = 0
    local beginInput
    local endInput

    pcall(function()
        local position = button.AbsolutePosition
        local size = button.AbsoluteSize
        centerX = position.X + (size.X / 2)
        centerY = position.Y + (size.Y / 2)
        beginInput = {
            UserInputType = Enum.UserInputType.MouseButton1,
            UserInputState = Enum.UserInputState.Begin,
            Position = Vector3.new(centerX, centerY, 0),
        }
        endInput = {
            UserInputType = Enum.UserInputType.MouseButton1,
            UserInputState = Enum.UserInputState.End,
            Position = Vector3.new(centerX, centerY, 0),
        }
    end)

    local signalCalls = {
        { "Activated", beginInput, 1 },
        { "MouseButton1Click" },
        { "MouseButton1Down", centerX, centerY },
        { "MouseButton1Up", centerX, centerY },
        { "InputBegan", beginInput },
        { "InputEnded", endInput },
    }

    if typeof(getconnections) == "function" then
        for _, signalCall in ipairs(signalCalls) do
            local signalName = signalCall[1]
            local signal
            local hasSignal = pcall(function()
                signal = button[signalName]
            end)

            if hasSignal and signal then
                local okConnections, connections = pcall(getconnections, signal)
                if okConnections and connections and #connections > 0 then
                    for _, connection in ipairs(connections) do
                        local enabled = true
                        pcall(function()
                            enabled = connection.Enabled ~= false
                        end)

                        if enabled then
                            local called = false
                            local ok = pcall(function()
                                if typeof(connection.Fire) == "function" then
                                    called = true
                                    if #signalCall == 3 then
                                        connection:Fire(signalCall[2], signalCall[3])
                                    elseif #signalCall == 2 then
                                        connection:Fire(signalCall[2])
                                    else
                                        connection:Fire()
                                    end
                                elseif typeof(connection.Function) == "function" then
                                    called = true
                                    if #signalCall == 3 then
                                        connection.Function(signalCall[2], signalCall[3])
                                    elseif #signalCall == 2 then
                                        connection.Function(signalCall[2])
                                    else
                                        connection.Function()
                                    end
                                end
                            end)

                            if ok and called then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    if typeof(firesignal) == "function" then
        local signalCalls = {
            { "InputBegan", beginInput },
            { "MouseButton1Down", centerX, centerY },
            { "MouseButton1Up", centerX, centerY },
            { "MouseButton1Click" },
            { "Activated", beginInput, 1 },
            { "InputEnded", endInput },
        }

        for _, signalCall in ipairs(signalCalls) do
            local signalName = signalCall[1]
            local signal

            local hasSignal = pcall(function()
                signal = button[signalName]
            end)

            if hasSignal and signal then
                local ok = pcall(function()
                    if #signalCall == 3 then
                        firesignal(signal, signalCall[2], signalCall[3])
                    elseif #signalCall == 2 then
                        firesignal(signal, signalCall[2])
                    else
                        firesignal(signal)
                    end
                end)

                fired = fired or ok
            end
        end
    end

    if fired then
        return true
    end

    local okActivate = pcall(function()
        button:Activate()
    end)

    if okActivate then
        return true
    end

    if VirtualInputManager and centerX > 0 and centerY > 0 then
        local ok = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 0)
            task.wait(0.03)
            VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 0)
        end)

        if ok then
            return true
        end
    end

    if VirtualInputManager and safeIsA(button, "GuiButton") then
        local previousSelected = GuiService.SelectedObject
        local ok = pcall(function()
            GuiService.SelectedObject = button
            task.wait()

            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
            task.wait(0.04)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        end)

        pcall(function()
            GuiService.SelectedObject = previousSelected
        end)

        if ok then
            return true
        end
    end

    okActivate = pcall(function()
        button:Activate()
    end)

    if okActivate then
        return true
    end

    return false
end

local function rebuildRemoteCache()
    RemoteCache = {}
    RemoteCacheTime = os.clock()

    for _, object in ipairs(safeDescendants(ReplicatedStorage)) do
        if object:IsA("RemoteEvent") or object:IsA("RemoteFunction") then
            local key = lower(object.Name)
            if not RemoteCache[key] then
                RemoteCache[key] = object
            end
        end
    end
end

local function getRemote(name)
    if os.clock() - RemoteCacheTime > 4 then
        rebuildRemoteCache()
    end

    return RemoteCache[lower(name)]
end

local function getRemoteByKeywords(keywords)
    if os.clock() - RemoteCacheTime > 4 then
        rebuildRemoteCache()
    end

    for _, remote in pairs(RemoteCache) do
        local haystack = getHaystack(remote)
        local matched = true
        for _, word in ipairs(keywords) do
            if not string.find(haystack, lower(word), 1, true) then
                matched = false
                break
            end
        end

        if matched then
            return remote
        end
    end

    return nil
end

local function callRemote(remote, ...)
    if not remote then
        return false
    end

    local args = { ... }
    local ok, err = pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(table.unpack(args))
        elseif remote:IsA("RemoteFunction") then
            remote:InvokeServer(table.unpack(args))
        end
    end)

    if not ok then
        warn(APP_NAME .. " remote error: " .. tostring(err))
    end

    return ok
end

local function readChildText(root, childName)
    local child
    pcall(function()
        child = root and root:FindFirstChild(childName, true)
    end)

    if child and (safeIsA(child, "TextLabel") or safeIsA(child, "TextButton") or safeIsA(child, "TextBox")) then
        return trim(safeGetText(child))
    end

    return ""
end

local function parseAmount(text)
    local amount = tonumber(tostring(text or ""):match("(%d+)"))
    return amount or 0
end

local function addPackTarget(targets, name, amount, source, instance)
    name = trim(name)
    amount = tonumber(amount) or 0

    if name == "" or amount <= 0 then
        return
    end

    for _, target in ipairs(targets) do
        if target.Name == name and target.Source == source then
            target.Amount = math.max(target.Amount, amount)
            return
        end
    end

    table.insert(targets, {
        Name = name,
        Amount = amount,
        Source = source,
        Instance = instance,
    })
end

local function collectInventoryPacks()
    local playerGui = getPlayerGui()
    local targets = {}
    local packContainer = findByPath(playerGui, { "HUD", "Bottom", "PackContainer" })

    if not packContainer then
        return targets
    end

    local currentPack
    pcall(function()
        currentPack = packContainer:FindFirstChild("CurrentPack")
    end)

    if currentPack and safeIsA(currentPack, "GuiObject") and isGuiVisible(currentPack) then
        addPackTarget(
            targets,
            readChildText(currentPack, "PackName"),
            parseAmount(readChildText(currentPack, "Amount")),
            "current",
            currentPack
        )
    end

    local otherPacks = findByPath(packContainer, { "OtherPacks", "ScrollingFrame" })
    if otherPacks then
        for _, child in ipairs(safeChildren(otherPacks)) do
            if safeIsA(child, "GuiObject") then
                local ok = pcall(function()
                    addPackTarget(
                        targets,
                        readChildText(child, "PackName"),
                        parseAmount(readChildText(child, "Amount")),
                        "other",
                        child
                    )
                end)

                if not ok then
                    warn(APP_NAME .. " pack parse skipped: " .. safeFullName(child))
                end
            end
        end
    end

    table.sort(targets, function(a, b)
        if a.Source ~= b.Source then
            return a.Source == "current"
        end

        return a.Amount > b.Amount
    end)

    return targets
end

local function getGuiTextTree(root)
    local parts = { root.Name }

    if safeIsA(root, "TextLabel") or safeIsA(root, "TextButton") or safeIsA(root, "TextBox") then
        table.insert(parts, safeGetText(root))
    end

    for _, child in ipairs(safeDescendants(root)) do
        table.insert(parts, child.Name)
        if safeIsA(child, "TextLabel") or safeIsA(child, "TextButton") or safeIsA(child, "TextBox") then
            table.insert(parts, safeGetText(child))
        end
    end

    return lower(table.concat(parts, " "))
end

local function findExactPackOpeningButton(name)
    local exactPaths = {
        { "PackOpeningUI", "Frame", "ButtonsContainer", name },
        { "PackOpeningUI", "Frame", "ButtonContainer", name },
        { "PackOpeningUI", "Frame", "Buttons", name },
        { "PackOpeningUI", "ButtonsContainer", name },
        { "PackOpeningUI", "ButtonContainer", name },
        { "PackOpeningUI", "Buttons", name },
        { "PackOpeningUI", "Frame", name },
        { "PackOpeningUI", name },
    }

    for _, root in ipairs(getGuiSearchRoots()) do
        for _, path in ipairs(exactPaths) do
            local object = findByPath(root, path)
            if object and safeIsA(object, "GuiButton") and isGuiVisible(object) then
                return object
            end
        end
    end

    return nil
end

local function findPackActionButton(action)
    local wantedName = action == "hide" and "Hide" or "AutoOpen"
    local exact = findExactPackOpeningButton(wantedName)
    if exact then
        return exact
    end

    local includeWords = action == "hide"
        and { "hide", "minimize", "minimized" }
        or { "autoopen", "auto-open", "auto open" }

    local blockedWords = action == "hide"
        and {
            "starter",
            "shop",
            "gemshop",
            "packcontainer",
            "rightbuttons",
            "changingbutton",
            "topbar",
            "codex",
            "lokasorn_spinsoccer_menu",
        }
        or {
            "autoskip",
            "auto skip",
            "autobuy",
            "auto buy",
            "collect money",
            "2x money",
            "vip",
            "starter",
            "godly",
            "luck",
            "robux",
            "rbx",
            "price",
            "shop",
            "currentpack",
            "packcontainer",
            "rightbuttons",
            "changingbutton",
            "topbar",
            "codex",
            "lokasorn_spinsoccer_menu",
        }

    local candidates = {}

    for _, root in ipairs(getGuiSearchRoots()) do
        for _, object in ipairs(safeDescendants(root)) do
            if safeIsA(object, "GuiButton") and isGuiVisible(object) then
                local text = getGuiTextTree(object)
                local objectName = lower(object.Name)
                local nameMatches = objectName == lower(wantedName)
                if (nameMatches or containsAny(text, includeWords)) and not containsBlockedWord(text, blockedWords) then
                    local path = lower(safeFullName(object))
                    local score = 0

                    if nameMatches then
                        score = score + 100
                    end
                    if string.find(path, "packopeningui", 1, true) then
                        score = score + 80
                    end
                    if string.find(path, "buttonscontainer", 1, true) then
                        score = score + 40
                    end
                    if string.find(path, "buttoncontainer", 1, true) then
                        score = score + 35
                    end
                    if string.find(path, "packanimationcontroller", 1, true) then
                        score = score + 20
                    end

                    table.insert(candidates, {
                        Object = object,
                        Score = score,
                        Path = path,
                    })
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.Score ~= b.Score then
            return a.Score > b.Score
        end

        return #a.Path < #b.Path
    end)

    if candidates[1] then
        return candidates[1].Object
    end

    return nil
end

local function waitForPackAnimationUI(maxSeconds)
    local deadline = os.clock() + (maxSeconds or 6)
    while os.clock() < deadline do
        if findPackActionButton("auto") or findPackActionButton("hide") then
            return true
        end
        task.wait(0.1)
    end

    return false
end

local function canRebirthNow()
    local playerGui = getPlayerGui()

    local hudIndicator = findByPath(playerGui, {
        "HUD", "LeftButtons", "Rebirth", "CanRebirth"
    })
    if hudIndicator and isGuiVisible(hudIndicator) then
        return true
    end

    local modalButton = findByPath(playerGui, {
        "Rebirth", "Frame", "Main", "Details", "RebirthButton"
    })
    if modalButton and isGuiVisible(modalButton) then
        local notEnough = modalButton:FindFirstChild("NotEnough")
        local locked = modalButton:FindFirstChild("Locked")
        local notEnoughVisible = notEnough and isGuiVisible(notEnough)
        local lockedVisible = locked and isGuiVisible(locked)
        if not notEnoughVisible and not lockedVisible then
            return true
        end
    end

    return false
end

local function findIndexClaimButtons()
    local playerGui = getPlayerGui()
    local indexGui = playerGui:FindFirstChild("Index")
    local buttons = {}

    if not indexGui then
        return buttons
    end

    for _, object in ipairs(safeDescendants(indexGui)) do
        if safeIsA(object, "GuiButton") and object.Name == "ClaimButton" and isGuiVisible(object) then
            local text = getGuiTextTree(object)
            if containsAny(text, { "claim" }) and not containsBlockedWord(text, { "claimed", "locked" }) then
                table.insert(buttons, object)
            end
        end
    end

    return buttons
end

local function actionAutoIndex()
    local buttons = findIndexClaimButtons()
    local hits = 0

    for _, button in ipairs(buttons) do
        if activateGuiButton(button) then
            hits = hits + 1
            task.wait(0.05)
        end
    end

    if hits > 0 then
        IndexState.LastClaimAll = os.clock()
        setStatus("Auto Index: " .. hits .. " claim buttons pressed", Theme.Accent)
        return true
    end

    local now = os.clock()
    if now - IndexState.LastClaimAll >= 12 then
        local claimAll = getRemote("ClaimAllIndexGems")
        if claimAll and callRemote(claimAll) then
            IndexState.LastClaimAll = now
            setStatus("Auto Index: index gems checked", Theme.Muted)
            return true
        end
    end

    setStatus("Auto Index: no new claims available", Theme.Muted)
    return true
end

local function actionOpenPacks()
    local now = os.clock()
    local targets = collectInventoryPacks()

    if #targets == 0 then
        if PackState.Stage ~= "waiting" then
            PackState.Stage = "waiting"
            PackState.LastTarget = nil
            PackState.LastResultPack = nil
            PackState.LastAmount = 0
            setStatus("Packs: done, waiting for new packs", Theme.Muted)
            return true
        end

        setStatus("Packs: no packs in inventory", Theme.Muted)
        return false
    end

    local target = targets[1]

    if PackState.Stage == "hidden_opening" then
        PackState.LastPackSeen = now

        local progressed = target.Name ~= PackState.LastTarget
            or target.Amount ~= PackState.LastAmount

        if progressed then
            PackState.LastAction = now
            PackState.LastTarget = target.Name
            PackState.LastAmount = target.Amount
        end

        if now - PackState.LastAction > 30 then
            PackState.Stage = "waiting"
            PackState.LastAction = now
            setStatus("Packs: no progress, re-engaging", Theme.Warm)
            return true
        end

        setStatus("Packs: auto-open running (" .. target.Name .. " x" .. target.Amount .. ")", Theme.Muted)
        return true
    end

    if PackState.Stage == "auto_open_enabled" then
        local hideButton = findPackActionButton("hide")
        if hideButton then
            tracePackActionButton("Hide", hideButton)
            if activateGuiButton(hideButton) then
                PackState.Stage = "hidden_opening"
                PackState.LastAction = now
                setStatus("Packs: hide activated", Theme.Accent)
                return true
            end

            setStatus("Packs: hide found, signal failed", Theme.Danger)
            return false
        end

        if now - PackState.LastAction < 15 then
            setStatus("Packs: waiting for hide button", Theme.Muted)
            return true
        end

        PackState.Stage = "pack_opened"
        PackState.LastAction = now
        setStatus("Packs: hide not found, retrying auto-open", Theme.Warm)
        return true
    end

    if PackState.Stage == "pack_opened" then
        local autoOpenButton = findPackActionButton("auto")
        if autoOpenButton then
            tracePackActionButton("AutoOpen", autoOpenButton)
            if activateGuiButton(autoOpenButton) then
                PackState.Stage = "auto_open_enabled"
                PackState.LastAction = now
                setStatus("Packs: auto-open pressed, waiting for hide", Theme.Accent)
                return true
            end

            setStatus("Packs: auto-open found, signal failed", Theme.Danger)
            return false
        end

        local hideButton = findPackActionButton("hide")
        if hideButton then
            tracePackActionButton("Hide", hideButton)
            if activateGuiButton(hideButton) then
                PackState.Stage = "hidden_opening"
                PackState.LastAction = now
                setStatus("Packs: no auto-open visible, hide pressed", Theme.Accent)
                return true
            end

            setStatus("Packs: hide found, signal failed", Theme.Danger)
            return false
        end

        if now - PackState.LastAction < 12 then
            setStatus("Packs: waiting for auto-open button", Theme.Muted)
            return true
        end

        PackState.Stage = "waiting"
    end

    local openAutoButton = findPackActionButton("auto")
    if openAutoButton then
        tracePackActionButton("AutoOpen", openAutoButton)
        if activateGuiButton(openAutoButton) then
            PackState.Stage = "auto_open_enabled"
            PackState.LastAction = now
            setStatus("Packs: open animation, auto-open pressed", Theme.Accent)
            return true
        end

        setStatus("Packs: open animation, auto-open failed", Theme.Danger)
        return false
    end

    local openHideButton = findPackActionButton("hide")
    if openHideButton then
        tracePackActionButton("Hide", openHideButton)
        if activateGuiButton(openHideButton) then
            PackState.Stage = "hidden_opening"
            PackState.LastAction = now
            setStatus("Packs: open animation minimized", Theme.Accent)
            return true
        end

        setStatus("Packs: open animation, hide failed", Theme.Danger)
        return false
    end

    if not target.Instance or not safeIsA(target.Instance, "GuiButton") then
        setStatus("Packs: pack button not found", Theme.Danger)
        return false
    end

    if not activateGuiButton(target.Instance) then
        setStatus("Packs: pack signal failed", Theme.Danger)
        return false
    end

    setStatus("Packs: " .. target.Name .. " clicked, waiting for UI", Theme.Muted)

    local uiReady = waitForPackAnimationUI(6)

    PackState.Stage = "pack_opened"
    PackState.LastAction = os.clock()
    PackState.LastPackSeen = PackState.LastAction
    PackState.LastTarget = target.Name
    PackState.LastAmount = target.Amount

    if uiReady then
        setStatus("Packs: " .. target.Name .. " x" .. target.Amount .. " opened", Theme.Accent)
    else
        setStatus("Packs: " .. target.Name .. " clicked, UI not yet visible", Theme.Warm)
    end

    return true
end

local function actionAutoMoney()
    local hits = 0

    local collectSlot = getRemote("CollectSlot")
    if collectSlot then
        for slot = 1, 30 do
            if callRemote(collectSlot, slot) then
                hits = hits + 1
            end
            task.wait(0.01)
        end
    end

    local playerGui = getPlayerGui()
    local guiNames = {
        "AutoSell",
        "YourBooth",
        "VisitBooth",
        "HUD",
    }

    for _, guiName in ipairs(guiNames) do
        local gui = playerGui:FindFirstChild(guiName)
        if gui then
            local buttons = findButtons(gui, { "collect", "cash", "money", "coin" }, {
                "gem",
                "gems",
                "reward",
                "daily",
                "group",
                "leave",
                "shop",
                "buy",
                "purchase",
                "robux",
                "rbx",
                "pack",
                "spin",
            }, true, 3)

            for _, button in ipairs(buttons) do
                if activateGuiButton(button) then
                    hits = hits + 1
                    task.wait(0.05)
                end
            end
        end
    end

    if hits > 0 then
        setStatus("Auto Money: " .. hits .. " actions", Theme.Accent)
        return true
    end

    setStatus("Auto Money: no money target found", Theme.Muted)
    return false
end

local function actionRebirth()
    if not canRebirthNow() then
        setStatus("Rebirth: not yet available, waiting", Theme.Muted)
        return true
    end

    local playerGui = getPlayerGui()

    local modalButton = findByPath(playerGui, {
        "Rebirth", "Frame", "Main", "Details", "RebirthButton"
    })
    if modalButton and isGuiVisible(modalButton) and safeIsA(modalButton, "GuiButton") then
        if activateGuiButton(modalButton) then
            setStatus("Rebirth: modal button triggered", Theme.Accent)
            return true
        end
    end

    local remote = getRemote("Rebirth") or getRemoteByKeywords({ "rebirth" })
    if remote and callRemote(remote) then
        setStatus("Rebirth: remote triggered", Theme.Accent)
        return true
    end

    local guiNames = { "Rebirth", "RebirthPrompt" }
    for _, guiName in ipairs(guiNames) do
        local gui = playerGui:FindFirstChild(guiName)
        if gui then
            local buttons = findButtons(gui, { "rebirth", "confirm", "accept" }, { "cancel", "close", "buy", "robux", "rbx" }, true, 2)
            for _, button in ipairs(buttons) do
                if activateGuiButton(button) then
                    setStatus("Rebirth: fallback button triggered", Theme.Accent)
                    return true
                end
            end
        end
    end

    setStatus("Rebirth: available, but no clickable target", Theme.Warm)
    return false
end

-- Feature order: Auto Money is the first card in the menu.
local Features = {
    {
        Id = "money",
        Title = "Auto Money",
        Description = "Collects your money on the set delay.",
        SettingKey = "AutoMoney",
        DelayKey = "MoneyDelay",
        MinDelay = 0.5,
        MaxDelay = 20,
        Step = 0.5,
        Action = actionAutoMoney,
    },
    {
        Id = "packs",
        Title = "Auto Packs",
        Description = "Opens packs from your inventory automatically.",
        SettingKey = "AutoOpenPacks",
        Interval = 0.5,
        Action = actionOpenPacks,
    },
    {
        Id = "rebirth",
        Title = "Auto Rebirth",
        Description = "Rebirths as soon as it's available.",
        SettingKey = "AutoRebirth",
        Interval = 2,
        Action = actionRebirth,
    },
    {
        Id = "index",
        Title = "Auto Index",
        Description = "Claims index gem rewards automatically.",
        SettingKey = "AutoIndex",
        Interval = 1.5,
        Action = actionAutoIndex,
    },
}

local function makeDraggable(handle, target)
    local dragging = false
    local dragStart
    local startPosition

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = target.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - dragStart
        target.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end)
end

local function createLabel(parent, text, size, weight, color)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Font = weight or Enum.Font.Gotham
    label.Text = text
    label.TextColor3 = color or Theme.Text
    label.TextSize = size or 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = parent
    return label
end

local function createSmallButton(parent, text)
    local button = Instance.new("TextButton")
    button.AutoButtonColor = false
    button.BackgroundColor3 = Theme.Panel3
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamBold
    button.Text = text
    button.TextColor3 = Theme.Text
    button.TextSize = 14
    button.Parent = parent

    addCorner(button, 8)
    addStroke(button, Theme.Line, 0.35, 1)

    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Theme.AccentSoft }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Panel3 }):Play()
    end)

    return button
end

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or APP_NAME,
            Text = text or "",
            Duration = duration or 5,
        })
    end)
end

local function openDiscord()
    local copied = false
    pcall(function()
        if typeof(setclipboard) == "function" then
            setclipboard(DISCORD_INVITE)
            copied = true
        elseif typeof(toclipboard) == "function" then
            toclipboard(DISCORD_INVITE)
            copied = true
        end
    end)

    if copied then
        setStatus("Discord invite copied to clipboard", Theme.Discord)
        notify("Discord", "Invite copied: " .. DISCORD_INVITE, 6)
    else
        setStatus("Discord: " .. DISCORD_INVITE, Theme.Discord)
        notify("Discord", DISCORD_INVITE, 8)
    end
end

local function updateToggle(feature)
    local controls = FeatureControls[feature.Id]
    if not controls then
        return
    end

    local enabled = Settings[feature.SettingKey] == true
    controls.StateText.Text = enabled and "ON" or "OFF"
    controls.Toggle.BackgroundColor3 = enabled and Theme.Accent or Theme.Off
    controls.CardStroke.Color = enabled and Theme.Accent or Theme.Line
    controls.CardStroke.Transparency = enabled and 0 or 0.45
    controls.CardStroke.Thickness = enabled and 2 or 1

    TweenService:Create(
        controls.Knob,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = enabled and UDim2.new(1, -28, 0.5, -11) or UDim2.new(0, 6, 0.5, -11) }
    ):Play()
end

local function setFeatureEnabled(feature, enabled)
    Settings[feature.SettingKey] = enabled == true

    if feature.Id == "packs" then
        PackState.Stage = "waiting"
        PackState.LastAction = 0
        PackState.LastPackSeen = 0
        PackState.LastTarget = nil
        PackState.LastAmount = 0
        PackState.LastAutoPath = nil
        PackState.LastHidePath = nil
    elseif feature.Id == "index" then
        IndexState.LastClaimAll = 0
    end

    updateToggle(feature)
    setStatus(feature.Title .. (Settings[feature.SettingKey] and " enabled" or " paused"), Settings[feature.SettingKey] and Theme.Accent or Theme.Muted)
end

local function updateDelayBox(feature)
    local controls = FeatureControls[feature.Id]
    if controls and controls.DelayBox and feature.DelayKey then
        controls.DelayBox.Text = formatDelay(Settings[feature.DelayKey])
    end
end

local function setFeatureDelay(feature, value)
    if not feature.DelayKey then
        return
    end

    Settings[feature.DelayKey] = clampDelay(value, feature.MinDelay, feature.MaxDelay, feature.Step)
    updateDelayBox(feature)
    setStatus(feature.Title .. " Delay: " .. formatDelay(Settings[feature.DelayKey]) .. "s", Theme.Muted)
end

local function createFeatureCard(parent, feature)
    local card = Instance.new("Frame")
    card.Name = feature.Id .. "Card"
    card.BackgroundColor3 = Theme.Panel2
    card.BorderSizePixel = 0
    card.Size = UDim2.new(1, -4, 0, feature.DelayKey and 126 or 86)
    card.Parent = parent

    addCorner(card, 12)
    local cardStroke = addStroke(card, Theme.Line, 0.45, 1)

    local cardPadding = Instance.new("UIPadding")
    cardPadding.PaddingTop = UDim.new(0, 12)
    cardPadding.PaddingBottom = UDim.new(0, 12)
    cardPadding.PaddingLeft = UDim.new(0, 14)
    cardPadding.PaddingRight = UDim.new(0, 14)
    cardPadding.Parent = card

    local title = createLabel(card, feature.Title, 15, Enum.Font.GothamBold, Theme.Text)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.Size = UDim2.new(1, -100, 0, 22)

    local description = createLabel(card, feature.Description, 12, Enum.Font.Gotham, Theme.Muted)
    description.Position = UDim2.new(0, 0, 0, 24)
    description.Size = UDim2.new(1, -100, 0, 36)
    description.TextWrapped = true
    description.TextYAlignment = Enum.TextYAlignment.Top

    local toggle = Instance.new("TextButton")
    toggle.Name = "Toggle"
    toggle.AutoButtonColor = false
    toggle.BackgroundColor3 = Theme.Off
    toggle.BorderSizePixel = 0
    toggle.Position = UDim2.new(1, -82, 0, 0)
    toggle.Size = UDim2.new(0, 82, 0, 34)
    toggle.Text = ""
    toggle.Parent = card
    addCorner(toggle, 17)

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.BackgroundColor3 = Theme.Text
    knob.BorderSizePixel = 0
    knob.Position = UDim2.new(0, 6, 0.5, -11)
    knob.Size = UDim2.new(0, 22, 0, 22)
    knob.Parent = toggle
    addCorner(knob, 11)

    local stateText = createLabel(toggle, "OFF", 11, Enum.Font.GothamBold, Theme.Text)
    stateText.Position = UDim2.new(0, 0, 0, 0)
    stateText.Size = UDim2.new(1, 0, 1, 0)
    stateText.TextXAlignment = Enum.TextXAlignment.Center

    local delayBox
    local minusButton
    local plusButton

    if feature.DelayKey then
        local delayRow = Instance.new("Frame")
        delayRow.Name = "DelayRow"
        delayRow.BackgroundTransparency = 1
        delayRow.Position = UDim2.new(0, 0, 1, -42)
        delayRow.Size = UDim2.new(1, 0, 0, 36)
        delayRow.Parent = card

        local delayLabel = createLabel(delayRow, "Delay", 12, Enum.Font.GothamBold, Theme.Muted)
        delayLabel.Position = UDim2.new(0, 0, 0, 0)
        delayLabel.Size = UDim2.new(0, 52, 1, 0)

        minusButton = createSmallButton(delayRow, "-")
        minusButton.Position = UDim2.new(0, 58, 0, 2)
        minusButton.Size = UDim2.new(0, 32, 0, 32)

        delayBox = Instance.new("TextBox")
        delayBox.Name = "DelayBox"
        delayBox.BackgroundColor3 = Theme.Panel
        delayBox.BorderSizePixel = 0
        delayBox.ClearTextOnFocus = false
        delayBox.Font = Enum.Font.GothamBold
        delayBox.PlaceholderText = "sec"
        delayBox.Text = formatDelay(Settings[feature.DelayKey])
        delayBox.TextColor3 = Theme.Text
        delayBox.TextSize = 14
        delayBox.Position = UDim2.new(0, 96, 0, 2)
        delayBox.Size = UDim2.new(0, 78, 0, 32)
        delayBox.Parent = delayRow
        addCorner(delayBox, 8)
        addStroke(delayBox, Theme.Line, 0.35, 1)

        plusButton = createSmallButton(delayRow, "+")
        plusButton.Position = UDim2.new(0, 180, 0, 2)
        plusButton.Size = UDim2.new(0, 32, 0, 32)

        local seconds = createLabel(delayRow, "Seconds", 12, Enum.Font.Gotham, Theme.Muted)
        seconds.Position = UDim2.new(0, 222, 0, 0)
        seconds.Size = UDim2.new(1, -222, 1, 0)
    end

    FeatureControls[feature.Id] = {
        CardStroke = cardStroke,
        Toggle = toggle,
        Knob = knob,
        StateText = stateText,
        DelayBox = delayBox,
    }

    toggle.Activated:Connect(function()
        setFeatureEnabled(feature, not Settings[feature.SettingKey])
    end)

    if feature.DelayKey then
        minusButton.Activated:Connect(function()
            setFeatureDelay(feature, (Settings[feature.DelayKey] or feature.MinDelay) - feature.Step)
        end)

        plusButton.Activated:Connect(function()
            setFeatureDelay(feature, (Settings[feature.DelayKey] or feature.MinDelay) + feature.Step)
        end)

        delayBox.FocusLost:Connect(function()
            local cleaned = delayBox.Text:gsub(",", ".")
            setFeatureDelay(feature, cleaned)
        end)
    end

    updateToggle(feature)
    updateDelayBox(feature)
end

local function createCopyIcon(parent, baseColor)
    local container = Instance.new("Frame")
    container.Name = "CopyIcon"
    container.BackgroundTransparency = 1
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Size = UDim2.new(0, 20, 0, 22)
    container.Parent = parent

    -- Back square (drawn behind, only an outline visible at the top-left).
    local back = Instance.new("Frame")
    back.Name = "Back"
    back.BackgroundTransparency = 1
    back.BorderSizePixel = 0
    back.Position = UDim2.new(0, 0, 0, 0)
    back.Size = UDim2.new(0, 13, 0, 15)
    back.Parent = container
    addCorner(back, 3)
    local backStroke = Instance.new("UIStroke")
    backStroke.Color = Theme.Text
    backStroke.Thickness = 1.5
    backStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    backStroke.LineJoinMode = Enum.LineJoinMode.Round
    backStroke.Parent = back

    -- Front square (drawn on top, filled with the card colour so the overlap
    -- of the back square is hidden, producing the classic copy-icon look).
    local front = Instance.new("Frame")
    front.Name = "Front"
    front.BackgroundColor3 = baseColor
    front.BorderSizePixel = 0
    front.Position = UDim2.new(0, 5, 0, 6)
    front.Size = UDim2.new(0, 13, 0, 15)
    front.Parent = container
    addCorner(front, 3)
    local frontStroke = Instance.new("UIStroke")
    frontStroke.Color = Theme.Text
    frontStroke.Thickness = 1.5
    frontStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    frontStroke.LineJoinMode = Enum.LineJoinMode.Round
    frontStroke.Parent = front

    return container, front
end

local function createDiscordCard(parent)
    local button = Instance.new("TextButton")
    button.Name = "DiscordCard"
    button.AutoButtonColor = false
    button.BackgroundColor3 = Theme.Discord
    button.BorderSizePixel = 0
    button.Text = ""
    button.Size = UDim2.new(1, -4, 0, 44)
    button.Parent = parent
    addCorner(button, 12)
    addStroke(button, Color3.fromRGB(120, 130, 250), 0.25, 1)

    local label = createLabel(button, "Join our Discord  -  Click to copy", 14, Enum.Font.GothamBold, Theme.Text)
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.new(0.5, -16, 0.5, 0)
    label.Size = UDim2.new(1, -60, 1, 0)
    label.TextXAlignment = Enum.TextXAlignment.Center

    local _, copyFront = createCopyIcon(button, Theme.Discord)
    local icon = button:FindFirstChild("CopyIcon")
    if icon then
        icon.Position = UDim2.new(1, -34, 0.5, 0)
    end

    button.MouseEnter:Connect(function()
        local hover = Color3.fromRGB(108, 121, 255)
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
        TweenService:Create(copyFront, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Discord }):Play()
        TweenService:Create(copyFront, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Discord }):Play()
    end)

    button.Activated:Connect(openDiscord)

    return button
end

local function createUI()
    local playerGui = getPlayerGui()
    local oldGui = playerGui:FindFirstChild(GUI_NAME)
    if oldGui then
        oldGui:Destroy()
    end

    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = GUI_NAME
    ScreenGui.DisplayOrder = 999999
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = playerGui

    MenuFrame = Instance.new("Frame")
    MenuFrame.Name = "Main"
    MenuFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MenuFrame.BackgroundColor3 = Theme.Background
    MenuFrame.BorderSizePixel = 0
    MenuFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    MenuFrame.Size = UDim2.new(0, 500, 0, 620)
    MenuFrame.Visible = Settings.MenuVisible
    MenuFrame.Parent = ScreenGui
    addCorner(MenuFrame, 16)
    addStroke(MenuFrame, Color3.fromRGB(82, 95, 115), 0.25, 1)

    local scale = Instance.new("UIScale")
    scale.Parent = MenuFrame

    local function updateScale()
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        scale.Scale = math.clamp(viewport.X / 760, 0.74, 1)
    end

    updateScale()
    if workspace.CurrentCamera then
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
    end

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundColor3 = Theme.Panel
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, 72)
    header.Parent = MenuFrame
    addCorner(header, 16)

    local headerMask = Instance.new("Frame")
    headerMask.BackgroundColor3 = Theme.Panel
    headerMask.BorderSizePixel = 0
    headerMask.Position = UDim2.new(0, 0, 1, -16)
    headerMask.Size = UDim2.new(1, 0, 0, 16)
    headerMask.Parent = header

    local accent = Instance.new("Frame")
    accent.BackgroundColor3 = Theme.Accent
    accent.BorderSizePixel = 0
    accent.Position = UDim2.new(0, 0, 1, -2)
    accent.Size = UDim2.new(1, 0, 0, 2)
    accent.Parent = header

    local title = createLabel(header, APP_NAME .. " " .. APP_VERSION, 19, Enum.Font.GothamBlack, Theme.Text)
    title.Position = UDim2.new(0, 18, 0, 12)
    title.Size = UDim2.new(1, -70, 0, 24)

    local subtitle = createLabel(header, "K or RightShift: toggle menu", 12, Enum.Font.Gotham, Theme.Muted)
    subtitle.Position = UDim2.new(0, 18, 0, 38)
    subtitle.Size = UDim2.new(1, -70, 0, 18)

    local closeButton = createSmallButton(header, "X")
    closeButton.Position = UDim2.new(1, -52, 0, 18)
    closeButton.Size = UDim2.new(0, 34, 0, 34)
    closeButton.Activated:Connect(function()
        Settings.MenuVisible = false
        MenuFrame.Visible = false
    end)

    makeDraggable(header, MenuFrame)

    local content = Instance.new("ScrollingFrame")
    content.Name = "Content"
    content.Active = true
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.CanvasSize = UDim2.new(0, 0, 0, 0)
    content.Position = UDim2.new(0, 14, 0, 88)
    content.ScrollBarImageColor3 = Theme.Accent
    content.ScrollBarThickness = 4
    content.Size = UDim2.new(1, -28, 1, -152)
    content.ClipsDescendants = false
    content.Parent = MenuFrame

    local contentPadding = Instance.new("UIPadding")
    contentPadding.PaddingTop = UDim.new(0, 4)
    contentPadding.PaddingBottom = UDim.new(0, 4)
    contentPadding.PaddingLeft = UDim.new(0, 4)
    contentPadding.PaddingRight = UDim.new(0, 10)
    contentPadding.Parent = content

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 10)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = content

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        content.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 16)
    end)

    for _, feature in ipairs(Features) do
        createFeatureCard(content, feature)
    end

    createDiscordCard(content)

    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.BackgroundColor3 = Theme.Panel
    footer.BorderSizePixel = 0
    footer.Position = UDim2.new(0, 14, 1, -50)
    footer.Size = UDim2.new(1, -28, 0, 36)
    footer.Parent = MenuFrame
    addCorner(footer, 10)
    addStroke(footer, Theme.Line, 0.45, 1)

    StatusLabel = createLabel(footer, "Ready. Enable the modules you want.", 12, Enum.Font.GothamBold, Theme.Muted)
    StatusLabel.Position = UDim2.new(0, 12, 0, 0)
    StatusLabel.Size = UDim2.new(1, -24, 1, 0)

    return ScreenGui
end

local function runFeature(feature)
    if Busy[feature.Id] then
        return
    end

    Busy[feature.Id] = true

    local ok, err = pcall(feature.Action)
    if not ok then
        setStatus(feature.Title .. " Error: " .. tostring(err), Theme.Danger)
        warn(APP_NAME .. " " .. feature.Id .. " error: " .. tostring(err))
    end

    Busy[feature.Id] = false
end

local function getFeatureInterval(feature)
    if feature.DelayKey then
        return math.max(Settings[feature.DelayKey] or feature.MinDelay, feature.MinDelay)
    end

    return feature.Interval or feature.MinDelay or 1
end

local function startScheduler()
    RunService.Heartbeat:Connect(function()
        local now = os.clock()

        for _, feature in ipairs(Features) do
            if Settings[feature.SettingKey] then
                local nextRun = LastRun[feature.Id] or 0
                if now >= nextRun then
                    LastRun[feature.Id] = now + getFeatureInterval(feature)
                    task.spawn(runFeature, feature)
                end
            end
        end
    end)
end

createUI()
rebuildRemoteCache()
startScheduler()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or UserInputService:GetFocusedTextBox() then
        return
    end

    if input.KeyCode == Enum.KeyCode.K or input.KeyCode == Enum.KeyCode.RightShift then
        Settings.MenuVisible = not Settings.MenuVisible
        if MenuFrame then
            MenuFrame.Visible = Settings.MenuVisible
        end
    end
end)

print(APP_NAME .. " " .. APP_VERSION .. " loaded. Press K or RightShift to toggle the menu.")
