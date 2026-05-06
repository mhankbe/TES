-- ============================================================
-- FLa Project ASH | Solo Leveling Theme
-- Game  : Arise Shadow Hunt (115317601829407)
-- Support: Xeno (PC/Desktop) + Delta (Android/iOS Smartphone)
-- ============================================================

local Players               = game:GetService("Players")
local UserInputService      = game:GetService("UserInputService")
local ContextActionService  = game:GetService("ContextActionService")
local TweenService          = game:GetService("TweenService")
local CoreGui               = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- PLATFORM DETECTION
-- isMobile = true  -> Delta (smartphone), use Touch events
-- isMobile = false -> Xeno  (desktop),    use Mouse events
-- ============================================================
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ============================================================
-- HWID / IDENTITY
-- ============================================================
local function getHWID()
    local ok, result = pcall(function()
        if syn and syn.get_hwid then return syn.get_hwid() end
    end)
    if ok and result then return result end
    local ok2, name = pcall(function()
        if getexecutorname then return getexecutorname() end
    end)
    return tostring(LocalPlayer.UserId) .. (ok2 and name and ("_" .. name) or "")
end

local HWID        = getHWID()
local PlayerName  = LocalPlayer.Name
local DisplayName = LocalPlayer.DisplayName

-- ============================================================
-- THEME
-- ============================================================
local T = {
    BgMain        = Color3.fromRGB(9,  11, 22),
    BgSidebar     = Color3.fromRGB(11, 13, 28),
    BgContent     = Color3.fromRGB(13, 15, 32),
    BgHeader      = Color3.fromRGB(7,   8, 18),
    TabActive     = Color3.fromRGB(25, 45, 115),
    TabHover      = Color3.fromRGB(18, 28,  72),
    Accent        = Color3.fromRGB(55, 105, 255),
    AccentBright  = Color3.fromRGB(90, 145, 255),
    Border        = Color3.fromRGB(35,  55, 130),
    BorderDim     = Color3.fromRGB(22,  32,  80),
    Text          = Color3.fromRGB(195, 210, 255),
    TextDim       = Color3.fromRGB( 90, 110, 170),
    TextBright    = Color3.fromRGB(235, 242, 255),
    Red           = Color3.fromRGB(170,  35,  35),
    Green         = Color3.fromRGB( 25,  85,  25),
    DarkPurple    = Color3.fromRGB( 45,  45, 105),
    ConfirmBorder = Color3.fromRGB(200,  50,  50),
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    IsOpen           = true,
    IsExpanded       = false,
    ActiveTab        = "MAIN",
    AllFunctions     = {},
    FunctionsEnabled = true,
}

-- Counter values (persist across tab switches)
local CounterValues    = { RPet = 0, YPet = 0, BPet = 0, Supreme = 0 }
local CounterNumLabels = {}   -- live TextLabel refs, filled by buildMainTab
local AutoSellHeroEquipOn = false
local autoSellThread      = nil

-- ============================================================
-- AUTO SELL HERO EQUIP LOGIC
-- ============================================================
local RS            = game:GetService("ReplicatedStorage")
local UUID_PAT      = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

-- Map item display name prefix to counter key
local function getCounterKey(name)
    local s = tostring(name):upper()
    if s:sub(1,2) == "R-" then return "RPet"
    elseif s:sub(1,2) == "Y-" then return "YPet"
    elseif s:sub(1,2) == "B-" then return "BPet"
    end
    return nil
end

-- Increment a counter and refresh its visible label
local function addToCounter(key, n)
    if not CounterValues[key] then return end
    CounterValues[key] = CounterValues[key] + (n or 1)
    if CounterNumLabels[key] then
        CounterNumLabels[key].Text = tostring(CounterValues[key])
    end
end

-- Scan LocalPlayer's hierarchy for GUID-named objects (hero equip items)
-- Tries common attribute names to retrieve the display name for prefix detection
local function scanForEquips()
    local found = {}
    local function scan(parent, depth)
        if depth > 4 then return end
        local ok, children = pcall(function() return parent:GetChildren() end)
        if not ok then return end
        for _, child in ipairs(children) do
            if child.Name:match(UUID_PAT) then
                local display =
                    child:GetAttribute("Name")     or
                    child:GetAttribute("ItemName") or
                    child:GetAttribute("Type")     or
                    child:GetAttribute("Id")       or ""
                table.insert(found, { guid = child.Name, display = display })
            else
                scan(child, depth + 1)
            end
        end
    end
    scan(LocalPlayer, 0)
    return found
end

-- Auto-sell coroutine body — loops while AutoSellHeroEquipOn is true
local function runAutoSell()
    local remote = RS:FindFirstChild("Remotes")
        and RS.Remotes:FindFirstChild("DelectHeroEquips")
    if not remote then return end

    while AutoSellHeroEquipOn do
        local items = scanForEquips()
        if #items == 0 then
            task.wait(2)
        else
            for _, item in ipairs(items) do
                if not AutoSellHeroEquipOn then break end
                local sold = pcall(function()
                    remote:FireServer({ item.guid })
                end)
                if sold then
                    local key = getCounterKey(item.display)
                    if key then addToCounter(key, 1) end
                end
                task.wait(0.35)
            end
            task.wait(1)
        end
    end
end

-- Toggle the auto-sell loop on or off
local function setAutoSell(on)
    AutoSellHeroEquipOn = on
    if on then
        if autoSellThread then pcall(task.cancel, autoSellThread) end
        autoSellThread = task.spawn(runAutoSell)
    else
        if autoSellThread then
            pcall(task.cancel, autoSellThread)
            autoSellThread = nil
        end
    end
end

-- ============================================================
-- REMOTES (shared across features)
-- ============================================================
local Remotes = RS:WaitForChild("Remotes", 10)
local RE = {
    CollectItem  = Remotes and Remotes:WaitForChild("CollectItem", 10),
    ExtraReward  = Remotes and Remotes:FindFirstChild("ExtraReward"),
}

-- ============================================================
-- AUTO SELL WEAPON LOGIC
-- ============================================================
local AutoSellWeaponOn = false
local autoSellWeaponThread = nil

local function scanForWeapons()
    local found = {}
    pcall(function()
        -- Weapons usually stored under LocalPlayer or ReplicatedStorage
        local function scan(parent, depth)
            if depth > 4 then return end
            local ok, children = pcall(function() return parent:GetChildren() end)
            if not ok then return end
            for _, child in ipairs(children) do
                if child.Name:match(UUID_PAT) then
                    local wType = child:GetAttribute("weaponGuid")
                                or child:GetAttribute("guid")
                                or child:GetAttribute("GUID")
                    if wType then
                        table.insert(found, { guid = child.Name, wGuid = wType })
                    end
                else
                    scan(child, depth + 1)
                end
            end
        end
        scan(LocalPlayer, 0)
    end)
    return found
end

local function runAutoSellWeapon()
    local remote = Remotes and Remotes:FindFirstChild("DelectHeroEquips")
    if not remote then return end
    while AutoSellWeaponOn do
        local items = scanForWeapons()
        if #items == 0 then
            task.wait(2)
        else
            for _, item in ipairs(items) do
                if not AutoSellWeaponOn then break end
                pcall(function() remote:FireServer({ item.guid }) end)
                task.wait(0.35)
            end
            task.wait(1)
        end
    end
end

local function setAutoSellWeapon(on)
    AutoSellWeaponOn = on
    if on then
        if autoSellWeaponThread then pcall(task.cancel, autoSellWeaponThread) end
        autoSellWeaponThread = task.spawn(runAutoSellWeapon)
    else
        if autoSellWeaponThread then
            pcall(task.cancel, autoSellWeaponThread)
            autoSellWeaponThread = nil
        end
    end
end

-- ============================================================
-- AUTO COLLECT GOLD/ITEM LOGIC
-- ============================================================
local AutoCollectGoldOn = false
local _collectThread = nil
local _collectConn   = nil

local COLLECT_FOLDERS = {"Golds","Items","Drops","Rewards","Loot","DropItems","RewardItems"}

local function runAutoCollectGold()
    local collected = {}
    while AutoCollectGoldOn do
        pcall(function()
            -- Magnet: TP items ke player
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local playerPos = hrp and hrp.Position

            for _, folderName in ipairs(COLLECT_FOLDERS) do
                if not AutoCollectGoldOn then break end
                local folder = workspace:FindFirstChild(folderName)
                if folder then
                    for _, obj in ipairs(folder:GetChildren()) do
                        if not AutoCollectGoldOn then break end
                        -- TP item ke player
                        if playerPos then
                            pcall(function()
                                if obj:IsA("BasePart") then
                                    obj.CFrame = CFrame.new(playerPos + Vector3.new(
                                        math.random(-2,2), 0, math.random(-2,2)))
                                elseif obj:IsA("Model") then
                                    local part = obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart
                                    if part then
                                        part.CFrame = CFrame.new(playerPos + Vector3.new(
                                            math.random(-2,2), 0, math.random(-2,2)))
                                    end
                                end
                            end)
                        end
                        -- Collect via remote
                        local guid = obj:GetAttribute("GUID")
                                  or obj:GetAttribute("Guid")
                                  or obj:GetAttribute("guid")
                        if guid and not collected[guid] then
                            collected[guid] = true
                            if RE.CollectItem then
                                pcall(function() RE.CollectItem:InvokeServer(guid) end)
                            end
                            if RE.ExtraReward then
                                pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                            end
                            task.wait(0.03)
                        end
                    end
                end
            end
        end)
        task.wait(0.5)
    end
end

local function setAutoCollectGold(on)
    AutoCollectGoldOn = on
    if on then
        if _collectThread then pcall(task.cancel, _collectThread) end
        _collectThread = task.spawn(runAutoCollectGold)
        -- Also watch new items spawning
        if _collectConn then pcall(function() _collectConn:Disconnect() end) end
        local collected2 = {}
        _collectConn = workspace.DescendantAdded:Connect(function(obj)
            if not AutoCollectGoldOn then return end
            task.delay(0.15, function()
                if not AutoCollectGoldOn then return end
                local guid = obj:GetAttribute("GUID")
                if not guid or collected2[guid] then return end
                local parent = obj.Parent
                if not parent then return end
                for _, fn in ipairs(COLLECT_FOLDERS) do
                    if parent.Name == fn and parent.Parent == workspace then
                        collected2[guid] = true
                        -- TP to player
                        pcall(function()
                            local char = LocalPlayer.Character
                            local hrp = char and char:FindFirstChild("HumanoidRootPart")
                            if hrp and obj:IsA("BasePart") then
                                obj.CFrame = CFrame.new(hrp.Position + Vector3.new(0,0,1))
                            end
                        end)
                        if RE.CollectItem then
                            pcall(function() RE.CollectItem:InvokeServer(guid) end)
                        end
                        break
                    end
                end
            end)
        end)
    else
        if _collectThread then pcall(task.cancel, _collectThread); _collectThread = nil end
        if _collectConn then pcall(function() _collectConn:Disconnect() end); _collectConn = nil end
    end
end

-- ============================================================
-- HIDE DAMAGE LOGIC
-- ============================================================
local HideDamageOn = false
local _hideDmgConn = nil

local function setHideDamage(on)
    HideDamageOn = on
    if _hideDmgConn then pcall(function() _hideDmgConn:Disconnect() end); _hideDmgConn = nil end
    if on then
        -- Hide existing damage numbers
        pcall(function()
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("BillboardGui") and (
                    obj.Name:find("Damage") or obj.Name:find("damage")
                    or obj.Name:find("Hit") or obj.Name:find("Number")
                    or obj.Name:find("FloatingText") or obj.Name:find("DmgLabel")
                ) then
                    obj.Enabled = false
                end
            end
        end)
        -- Watch for new damage numbers
        _hideDmgConn = workspace.DescendantAdded:Connect(function(obj)
            if not HideDamageOn then return end
            if obj:IsA("BillboardGui") and (
                obj.Name:find("Damage") or obj.Name:find("damage")
                or obj.Name:find("Hit") or obj.Name:find("Number")
                or obj.Name:find("FloatingText") or obj.Name:find("DmgLabel")
            ) then
                task.defer(function() obj.Enabled = false end)
            end
        end)
    else
        -- Re-enable existing ones
        pcall(function()
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("BillboardGui") and (
                    obj.Name:find("Damage") or obj.Name:find("damage")
                    or obj.Name:find("Hit") or obj.Name:find("Number")
                    or obj.Name:find("FloatingText") or obj.Name:find("DmgLabel")
                ) then
                    obj.Enabled = true
                end
            end
        end)
    end
end

-- ============================================================
-- HIDE NOTIF/REWARD LOGIC
-- ============================================================
local HideNotifOn = false
local _hideNotifConn = nil

local NOTIF_NAMES = {
    "RewardsFrame", "RewardPanel", "ResultFrame",
    "NotificationFrame", "FloatingReward", "ItemNotification",
    "CityFightPanel", "TowerReward", "DungeonReward",
}

local function isNotifFrame(obj)
    if not obj:IsA("Frame") and not obj:IsA("ScreenGui") then return false end
    for _, n in ipairs(NOTIF_NAMES) do
        if obj.Name == n then return true end
    end
    return false
end

local function setHideNotif(on)
    HideNotifOn = on
    if _hideNotifConn then pcall(function() _hideNotifConn:Disconnect() end); _hideNotifConn = nil end
    if on then
        -- Hide existing
        pcall(function()
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if pg then
                for _, obj in ipairs(pg:GetDescendants()) do
                    if isNotifFrame(obj) and obj.Visible then
                        obj.Visible = false
                    end
                end
            end
        end)
        -- Watch for new popups
        _hideNotifConn = PlayerGui.DescendantAdded:Connect(function(obj)
            if not HideNotifOn then return end
            task.delay(0.05, function()
                if isNotifFrame(obj) then
                    pcall(function() obj.Visible = false end)
                end
            end)
        end)
    end
end
-- to fit all 8 sidebar tabs (header=44, playerstrip=72, 8 tabs×28 + gaps/padding)
local viewport   = workspace.CurrentCamera.ViewportSize
local guiW       = math.clamp(math.floor(viewport.X * 0.42), 300, 620)
local _minGuiH   = 44 + 72 + (8 * 28) + (7 * 2) + 16   -- = 390 px minimum
local guiH       = math.max(math.floor(guiW * 0.825), _minGuiH)

local NormalSize   = UDim2.fromOffset(guiW, guiH)
local NormalPos    = UDim2.new(0.5, -guiW/2, 0.5, -guiH/2)
local ExpandedSize = UDim2.new(1, -20, 1, -20)
local ExpandedPos  = UDim2.new(0, 10, 0, 10)

-- ============================================================
-- SCREEN GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name            = "FLaProjectASH_GUI"
ScreenGui.ResetOnSpawn    = false
ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder    = 99
ScreenGui.IgnoreGuiInset  = true

local ok = pcall(function() ScreenGui.Parent = CoreGui end)
if not ok then ScreenGui.Parent = PlayerGui end

-- ============================================================
-- UNIVERSAL DRAG SYSTEM
-- Supports Mouse (Xeno/Desktop) AND Touch (Delta/Mobile)
--
-- Precision approach:
--   All input positions are read from the GLOBAL UserInputService,
--   so coordinates are always in the same screen space as
--   AbsolutePosition. This eliminates any coordinate mismatch.
--
--   The offset is calculated as:
--     offsetX = tapX - frame.AbsolutePosition.X
--     offsetY = tapY - frame.AbsolutePosition.Y
--   So frame always moves such that the exact tap point
--   stays pinned under the finger/cursor.
-- ============================================================

local drag = {
    active  = false,
    frame   = nil,
    offsetX = 0,
    offsetY = 0,
}

local dragTargets = {}   -- list of {frame, hitRegion} pairs

local function isPress(t)
    return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end
local function isMove(t)
    return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
end

-- Register a draggable frame. hitRegion defines the clickable/tappable area.
local function registerDrag(frame, hitRegion)
    table.insert(dragTargets, {frame = frame, hit = hitRegion})
end

-- Single global press handler — checks bounds of every registered hit region
UserInputService.InputBegan:Connect(function(input, gp)
    if not isPress(input.UserInputType) then return end
    local px, py = input.Position.X, input.Position.Y
    for _, entry in ipairs(dragTargets) do
        local ap = entry.hit.AbsolutePosition
        local as = entry.hit.AbsoluteSize
        if px >= ap.X and px <= ap.X + as.X
        and py >= ap.Y and py <= ap.Y + as.Y then
            drag.active  = true
            drag.frame   = entry.frame
            -- Offset = distance from tap point to frame top-left
            -- This makes the exact tap position stay under finger
            drag.offsetX = px - entry.frame.AbsolutePosition.X
            drag.offsetY = py - entry.frame.AbsolutePosition.Y
            break
        end
    end
end)

-- High-priority action bound via ContextActionService.
-- When drag is active:
--   1. Moves our frame with the pointer.
--   2. Returns Sink  -> game camera never receives the input.
-- When drag is inactive:
--   Returns Pass -> game works normally (camera, skills, etc).
ContextActionService:BindActionAtPriority(
    "FLa_DragSink",
    function(_, state, input)
        if not drag.active or not drag.frame then
            return Enum.ContextActionResult.Pass
        end
        -- Move frame while pointer is moving
        if state == Enum.UserInputState.Change and isMove(input.UserInputType) then
            local px, py = input.Position.X, input.Position.Y
            drag.frame.Position = UDim2.fromOffset(
                px - drag.offsetX,
                py - drag.offsetY
            )
        end
        -- Sink: prevents the game camera from rotating
        return Enum.ContextActionResult.Sink
    end,
    false,                                  -- no on-screen button
    2000,                                   -- Enum.ContextActionPriority.High.Value
    Enum.UserInputType.MouseButton1,
    Enum.UserInputType.MouseMovement,
    Enum.UserInputType.Touch
)

-- Release drag
UserInputService.InputEnded:Connect(function(input)
    if isPress(input.UserInputType) then
        drag.active = false
        drag.frame  = nil
    end
end)

-- ============================================================
-- MINI ICON  (appears after Minimize, top-center of screen)
-- ============================================================
local MiniFrame = Instance.new("Frame")
MiniFrame.Name                   = "MiniIcon"
MiniFrame.Size                   = UDim2.fromOffset(60, 60)
MiniFrame.Position               = UDim2.new(0.5, -30, 0, 20)
MiniFrame.BackgroundColor3       = T.BgSidebar
MiniFrame.BackgroundTransparency = 0.35
MiniFrame.BorderSizePixel        = 0
MiniFrame.Visible                = false
MiniFrame.ZIndex                 = 30
MiniFrame.Parent                 = ScreenGui

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,12); c.Parent = MiniFrame
    local s = Instance.new("UIStroke"); s.Color = T.Accent; s.Thickness = 2; s.Parent = MiniFrame

    local t1 = Instance.new("TextLabel")
    t1.Size = UDim2.new(1,0,0.54,0); t1.Position = UDim2.new(0,0,0.05,0)
    t1.BackgroundTransparency = 1; t1.Text = "FLa"
    t1.TextColor3 = T.AccentBright; t1.TextScaled = true
    t1.Font = Enum.Font.GothamBold; t1.ZIndex = 31; t1.Parent = MiniFrame

    local t2 = Instance.new("TextLabel")
    t2.Size = UDim2.new(1,0,0.32,0); t2.Position = UDim2.new(0,0,0.63,0)
    t2.BackgroundTransparency = 1; t2.Text = "ASH"
    t2.TextColor3 = T.TextDim; t2.TextScaled = true
    t2.Font = Enum.Font.Gotham; t2.ZIndex = 31; t2.Parent = MiniFrame
end

-- Hit region over mini icon (for drag + tap detection)
local MiniHit = Instance.new("Frame")
MiniHit.Size                   = UDim2.new(1,0,1,0)
MiniHit.BackgroundTransparency = 1
MiniHit.ZIndex                 = 32
MiniHit.Parent                 = MiniFrame

registerDrag(MiniFrame, MiniHit)

-- Tap to restore GUI (uses global UIS for consistent coordinates)
-- Tap  = press held < 0.25s AND finger/cursor moved < 14px
-- Drag = held longer OR moved further → GUI stays hidden
local miniPressPos  = nil
local miniPressTime = 0

UserInputService.InputBegan:Connect(function(input)
    if not isPress(input.UserInputType) then return end
    if not MiniFrame.Visible then return end
    local px, py = input.Position.X, input.Position.Y
    local ap = MiniHit.AbsolutePosition
    local as = MiniHit.AbsoluteSize
    if px >= ap.X and px <= ap.X + as.X
    and py >= ap.Y and py <= ap.Y + as.Y then
        miniPressPos  = Vector2.new(px, py)
        miniPressTime = tick()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if not isPress(input.UserInputType) then return end
    if not miniPressPos then return end
    local held = tick() - miniPressTime
    local cur  = Vector2.new(input.Position.X, input.Position.Y)
    local dist = (cur - miniPressPos).Magnitude
    miniPressPos = nil
    if held < 0.25 and dist < 14 then
        MiniFrame.Visible = false
        local mainFrame   = ScreenGui:FindFirstChild("FLaMain")
        if mainFrame then mainFrame.Visible = true end
        State.IsOpen = true
    end
end)

-- ============================================================
-- MAIN WINDOW
-- ============================================================
local Main = Instance.new("Frame")
Main.Name                    = "FLaMain"
Main.Size                    = NormalSize
Main.Position                = NormalPos
Main.BackgroundColor3        = T.BgMain
Main.BackgroundTransparency  = 0.42
Main.BorderSizePixel         = 0
Main.ZIndex                  = 2
Main.Parent                  = ScreenGui

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = Main
    local s = Instance.new("UIStroke"); s.Color = T.Border; s.Thickness = 1.5; s.Parent = Main
end

-- ============================================================
-- HEADER
-- ============================================================
local headerH = 44

local Header = Instance.new("Frame")
Header.Name                   = "Header"
Header.Size                   = UDim2.new(1, 0, 0, headerH)
Header.BackgroundColor3       = T.BgHeader
Header.BackgroundTransparency = 0.38
Header.BorderSizePixel        = 0
Header.ZIndex                 = 3
Header.Parent                 = Main

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = Header
    local cover = Instance.new("Frame")
    cover.Size = UDim2.new(1,0,0,12); cover.Position = UDim2.new(0,0,1,-12)
    cover.BackgroundColor3 = T.BgHeader; cover.BackgroundTransparency = 0.38
    cover.BorderSizePixel = 0; cover.ZIndex = 3; cover.Parent = Header
    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1,0,0,1); sep.Position = UDim2.new(0,0,1,-1)
    sep.BackgroundColor3 = T.Border; sep.BorderSizePixel = 0; sep.ZIndex = 4; sep.Parent = Header
end

local BrandLabel = Instance.new("TextLabel")
BrandLabel.Size = UDim2.new(0,220,1,0); BrandLabel.Position = UDim2.new(0,12,0,0)
BrandLabel.BackgroundTransparency = 1; BrandLabel.Text = "FLa Project ASH"
BrandLabel.TextColor3 = T.AccentBright; BrandLabel.TextSize = 15
BrandLabel.Font = Enum.Font.GothamBold; BrandLabel.TextXAlignment = Enum.TextXAlignment.Left
BrandLabel.ZIndex = 4; BrandLabel.Parent = Header

local SubLabel = Instance.new("TextLabel")
SubLabel.Size = UDim2.new(0,100,1,0); SubLabel.Position = UDim2.new(0,222,0,0)
SubLabel.BackgroundTransparency = 1; SubLabel.Text = "v1.0 | ASH"
SubLabel.TextColor3 = T.TextDim; SubLabel.TextSize = 11
SubLabel.Font = Enum.Font.Gotham; SubLabel.TextXAlignment = Enum.TextXAlignment.Left
SubLabel.ZIndex = 4; SubLabel.Parent = Header

-- Drag region on header (invisible, sits behind control buttons)
local HeaderDrag = Instance.new("Frame")
HeaderDrag.Size                   = UDim2.new(1, -120, 1, 0)
HeaderDrag.BackgroundTransparency = 1
HeaderDrag.ZIndex                 = 4
HeaderDrag.Parent                 = Header

registerDrag(Main, HeaderDrag)

-- Control buttons (larger for mobile friendliness)
local btnW = isMobile and 34 or 28
local btnH = isMobile and 28 or 22

local function makeCtrlBtn(label, color, offsetX)
    local btn = Instance.new("TextButton")
    btn.Size                   = UDim2.fromOffset(btnW, btnH)
    btn.Position               = UDim2.new(1, offsetX, 0.5, -btnH/2)
    btn.BackgroundColor3       = color
    btn.BackgroundTransparency = 0.25
    btn.BorderSizePixel        = 0
    btn.Text                   = label
    btn.TextColor3             = T.TextBright
    btn.TextSize               = isMobile and 13 or 11
    btn.Font                   = Enum.Font.GothamBold
    btn.ZIndex                 = 6
    btn.Parent                 = Header
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = btn
    btn.MouseEnter:Connect(function() btn.BackgroundTransparency = 0 end)
    btn.MouseLeave:Connect(function() btn.BackgroundTransparency = 0.25 end)
    return btn
end

local gap = btnW + 6
local CloseBtn  = makeCtrlBtn("X",   T.Red,        -(gap * 1 - 6))
local ExpandBtn = makeCtrlBtn("[]",  T.Green,      -(gap * 2 - 4))
local MinBtn    = makeCtrlBtn("_",   T.DarkPurple, -(gap * 3 - 2))

-- ============================================================
-- SIDEBAR
-- ============================================================
local SidebarW = isMobile and 110 or 130

local Sidebar = Instance.new("Frame")
Sidebar.Name                   = "Sidebar"
Sidebar.Size                   = UDim2.new(0, SidebarW, 1, -headerH)
Sidebar.Position               = UDim2.new(0, 0, 0, headerH)
Sidebar.BackgroundColor3       = T.BgSidebar
Sidebar.BackgroundTransparency = 0.40
Sidebar.BorderSizePixel        = 0
Sidebar.ZIndex                 = 3
Sidebar.Parent                 = Main

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = Sidebar
    local coverR = Instance.new("Frame")
    coverR.Size = UDim2.new(0,12,1,0); coverR.Position = UDim2.new(1,-12,0,0)
    coverR.BackgroundColor3 = T.BgSidebar; coverR.BackgroundTransparency = 0.40
    coverR.BorderSizePixel = 0; coverR.ZIndex = 3; coverR.Parent = Sidebar
    local div = Instance.new("Frame")
    div.Size = UDim2.new(0,1,1,0); div.Position = UDim2.new(1,-1,0,0)
    div.BackgroundColor3 = T.BorderDim; div.BorderSizePixel = 0; div.ZIndex = 4; div.Parent = Sidebar
end

-- Tab list (scrollable)
local TabScroll = Instance.new("ScrollingFrame")
TabScroll.Size                   = UDim2.new(1,0,1,-80)
TabScroll.BackgroundTransparency = 1
TabScroll.BorderSizePixel        = 0
TabScroll.ScrollBarThickness     = 2
TabScroll.ScrollBarImageColor3   = T.Border
TabScroll.CanvasSize             = UDim2.new(0,0,0,0)
TabScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
TabScroll.ZIndex                 = 4
TabScroll.Parent                 = Sidebar

do
    local l = Instance.new("UIListLayout")
    l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0,2); l.Parent = TabScroll
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0,8); p.PaddingLeft = UDim.new(0,5); p.PaddingRight = UDim.new(0,5)
    p.Parent = TabScroll
end

-- Player info at bottom of sidebar
local stripH = 72
local PlayerStrip = Instance.new("Frame")
PlayerStrip.Size                   = UDim2.new(1,0,0,stripH)
PlayerStrip.Position               = UDim2.new(0,0,1,-stripH)
PlayerStrip.BackgroundColor3       = Color3.fromRGB(8,10,22)
PlayerStrip.BackgroundTransparency = 0.45
PlayerStrip.BorderSizePixel        = 0
PlayerStrip.ZIndex                 = 5
PlayerStrip.Parent                 = Sidebar

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = PlayerStrip
    local tc = Instance.new("Frame")
    tc.Size = UDim2.new(1,0,0,10)
    tc.BackgroundColor3 = Color3.fromRGB(8,10,22); tc.BackgroundTransparency = 0.45
    tc.BorderSizePixel = 0; tc.ZIndex = 5; tc.Parent = PlayerStrip
    local tl = Instance.new("Frame")
    tl.Size = UDim2.new(1,0,0,1)
    tl.BackgroundColor3 = T.BorderDim; tl.BorderSizePixel = 0; tl.ZIndex = 6; tl.Parent = PlayerStrip
end

-- Avatar
local AvatarH = Instance.new("Frame")
AvatarH.Size = UDim2.new(0,34,0,34); AvatarH.Position = UDim2.new(0,7,0.5,-17)
AvatarH.BackgroundColor3 = T.Accent; AvatarH.BackgroundTransparency = 0.5
AvatarH.BorderSizePixel = 0; AvatarH.ZIndex = 6; AvatarH.Parent = PlayerStrip
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = AvatarH
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(1,0,1,0); img.BackgroundTransparency = 1; img.ZIndex = 7; img.Parent = AvatarH
    local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(1,0); ic.Parent = img
    local thumb = Players:GetUserThumbnailAsync(
        LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
    img.Image = thumb
end

local NameLbl = Instance.new("TextLabel")
NameLbl.Size = UDim2.new(1,-48,0,18); NameLbl.Position = UDim2.new(0,46,0.5,-20)
NameLbl.BackgroundTransparency = 1; NameLbl.Text = DisplayName
NameLbl.TextColor3 = T.TextBright; NameLbl.TextSize = 11
NameLbl.Font = Enum.Font.GothamBold; NameLbl.TextXAlignment = Enum.TextXAlignment.Left
NameLbl.TextTruncate = Enum.TextTruncate.AtEnd; NameLbl.ZIndex = 6; NameLbl.Parent = PlayerStrip

local UserLbl = Instance.new("TextLabel")
UserLbl.Size = UDim2.new(1,-48,0,15); UserLbl.Position = UDim2.new(0,46,0.5,-1)
UserLbl.BackgroundTransparency = 1; UserLbl.Text = "@" .. PlayerName
UserLbl.TextColor3 = T.TextDim; UserLbl.TextSize = 10
UserLbl.Font = Enum.Font.Gotham; UserLbl.TextXAlignment = Enum.TextXAlignment.Left
UserLbl.TextTruncate = Enum.TextTruncate.AtEnd; UserLbl.ZIndex = 6; UserLbl.Parent = PlayerStrip

local HWIDLbl = Instance.new("TextLabel")
HWIDLbl.Size = UDim2.new(1,-48,0,13); HWIDLbl.Position = UDim2.new(0,46,1,-17)
HWIDLbl.BackgroundTransparency = 1; HWIDLbl.Text = "ID: " .. string.sub(HWID,1,16) .. ".."
HWIDLbl.TextColor3 = Color3.fromRGB(55,70,125); HWIDLbl.TextSize = 9
HWIDLbl.Font = Enum.Font.Gotham; HWIDLbl.TextXAlignment = Enum.TextXAlignment.Left
HWIDLbl.ZIndex = 6; HWIDLbl.Parent = PlayerStrip

-- ============================================================
-- CONTENT AREA (right, empty — filled by future commands)
-- ============================================================
local ContentArea = Instance.new("Frame")
ContentArea.Name                   = "ContentArea"
ContentArea.Size                   = UDim2.new(1, -SidebarW, 1, -headerH)
ContentArea.Position               = UDim2.new(0, SidebarW, 0, headerH)
ContentArea.BackgroundColor3       = T.BgContent
ContentArea.BackgroundTransparency = 0.40
ContentArea.BorderSizePixel        = 0
ContentArea.ZIndex                 = 3
ContentArea.Parent                 = Main

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = ContentArea
    local cl = Instance.new("Frame")
    cl.Size = UDim2.new(0,12,1,0)
    cl.BackgroundColor3 = T.BgContent; cl.BackgroundTransparency = 0.40
    cl.BorderSizePixel = 0; cl.ZIndex = 3; cl.Parent = ContentArea
end

local ContentTitle = Instance.new("TextLabel")
ContentTitle.Size = UDim2.new(1,-16,0,38); ContentTitle.Position = UDim2.new(0,14,0,0)
ContentTitle.BackgroundTransparency = 1; ContentTitle.Text = "MAIN"
ContentTitle.TextColor3 = T.AccentBright; ContentTitle.TextSize = 15
ContentTitle.Font = Enum.Font.GothamBold; ContentTitle.TextXAlignment = Enum.TextXAlignment.Left
ContentTitle.ZIndex = 5; ContentTitle.Parent = ContentArea

local TitleDiv = Instance.new("Frame")
TitleDiv.Size = UDim2.new(1,-20,0,1); TitleDiv.Position = UDim2.new(0,10,0,38)
TitleDiv.BackgroundColor3 = T.BorderDim; TitleDiv.BorderSizePixel = 0
TitleDiv.ZIndex = 4; TitleDiv.Parent = ContentArea

local ContentScroll = Instance.new("ScrollingFrame")
ContentScroll.Name                   = "ContentScroll"
ContentScroll.Size                   = UDim2.new(1,-8,1,-48)
ContentScroll.Position               = UDim2.new(0,4,0,43)
ContentScroll.BackgroundTransparency = 1
ContentScroll.BorderSizePixel        = 0
ContentScroll.ScrollBarThickness     = 3
ContentScroll.ScrollBarImageColor3   = T.Accent
ContentScroll.CanvasSize             = UDim2.new(0,0,0,0)
ContentScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
ContentScroll.ZIndex                 = 4
ContentScroll.Parent                 = ContentArea

-- ============================================================
-- MAIN TAB CONTENT BUILDER
-- ============================================================
local function buildMainTab()
    -- Clear all children (GuiObjects + UIComponents) from ContentScroll
    for _, c in pairs(ContentScroll:GetChildren()) do c:Destroy() end

    -- Vertical list layout
    local list = Instance.new("UIListLayout")
    list.SortOrder   = Enum.SortOrder.LayoutOrder
    list.Padding     = UDim.new(0, 10)
    list.Parent      = ContentScroll

    local pad = Instance.new("UIPadding")
    pad.PaddingTop    = UDim.new(0, 10)
    pad.PaddingLeft   = UDim.new(0, 8)
    pad.PaddingRight  = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.Parent        = ContentScroll

    -- ---- Counter grid (4 boxes side-by-side) ----
    local counterRow = Instance.new("Frame")
    counterRow.LayoutOrder          = 1
    counterRow.Size                 = UDim2.new(1, 0, 0, 72)
    counterRow.BackgroundTransparency = 1
    counterRow.ZIndex               = 5
    counterRow.Parent               = ContentScroll

    local boxDefs = {
        { key = "RPet",    label = "R", color = Color3.fromRGB(220, 55,  55)  },
        { key = "YPet",    label = "Y", color = Color3.fromRGB(230, 200,  0)  },
        { key = "BPet",    label = "B", color = Color3.fromRGB(55,  145, 235) },
        { key = "Supreme", label = "S", color = Color3.fromRGB(30,  200,  80) },
    }

    -- Reset module-level label refs so addToCounter can reach them
    for k in pairs(CounterNumLabels) do CounterNumLabels[k] = nil end

    for i, def in ipairs(boxDefs) do
        local frac   = (i - 1) / 4
        local gapOff = (i - 1) * 4

        local box = Instance.new("Frame")
        box.Size                 = UDim2.new(0.25, -3, 1, 0)
        box.Position             = UDim2.new(frac, gapOff, 0, 0)
        box.BackgroundColor3     = Color3.fromRGB(8, 12, 26)
        box.BackgroundTransparency = 0.25
        box.BorderSizePixel      = 0
        box.ZIndex               = 5
        box.Parent               = counterRow

        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = box
        local bs = Instance.new("UIStroke"); bs.Color = T.BorderDim; bs.Thickness = 1; bs.Parent = box

        -- Letter label (top-left)
        local lbl = Instance.new("TextLabel")
        lbl.Size                 = UDim2.new(0, 20, 0, 16)
        lbl.Position             = UDim2.new(0, 6, 0, 5)
        lbl.BackgroundTransparency = 1
        lbl.Text                 = def.label
        lbl.TextColor3           = def.color
        lbl.TextSize             = 11
        lbl.Font                 = Enum.Font.GothamBold
        lbl.ZIndex               = 6
        lbl.Parent               = box

        -- Big number (center)
        local num = Instance.new("TextLabel")
        num.Size                 = UDim2.new(1, 0, 1, -20)
        num.Position             = UDim2.new(0, 0, 0, 20)
        num.BackgroundTransparency = 1
        num.Text                 = tostring(CounterValues[def.key])
        num.TextColor3           = def.color
        num.TextScaled           = true
        num.Font                 = Enum.Font.GothamBold
        num.ZIndex               = 6
        num.Parent               = box

        CounterNumLabels[def.key] = num
    end

    -- ---- RESET COUNTER button ----
    local resetBtn = Instance.new("TextButton")
    resetBtn.LayoutOrder             = 2
    resetBtn.Size                    = UDim2.new(1, 0, 0, 34)
    resetBtn.BackgroundColor3        = Color3.fromRGB(38, 14, 14)
    resetBtn.BackgroundTransparency  = 0.15
    resetBtn.BorderSizePixel         = 0
    resetBtn.Text                    = "RESET COUNTER"
    resetBtn.TextColor3              = Color3.fromRGB(220, 75, 75)
    resetBtn.TextSize                = 12
    resetBtn.Font                    = Enum.Font.GothamBold
    resetBtn.ZIndex                  = 5
    resetBtn.Parent                  = ContentScroll

    local rbc = Instance.new("UICorner"); rbc.CornerRadius = UDim.new(0, 8); rbc.Parent = resetBtn
    local rbs = Instance.new("UIStroke"); rbs.Color = Color3.fromRGB(160, 45, 45); rbs.Thickness = 1; rbs.Parent = resetBtn

    resetBtn.MouseButton1Click:Connect(function()
        CounterValues.RPet    = 0
        CounterValues.YPet    = 0
        CounterValues.BPet    = 0
        CounterValues.Supreme = 0
        for key, numLbl in pairs(CounterNumLabels) do
            numLbl.Text = "0"
        end
    end)

    -- Hover effect on reset button
    resetBtn.MouseEnter:Connect(function()
        resetBtn.BackgroundColor3 = Color3.fromRGB(60, 18, 18)
    end)
    resetBtn.MouseLeave:Connect(function()
        resetBtn.BackgroundColor3 = Color3.fromRGB(38, 14, 14)
    end)

    -- ---- Auto Sell HeroEquip toggle row ----
    local toggleRow = Instance.new("Frame")
    toggleRow.LayoutOrder            = 3
    toggleRow.Size                   = UDim2.new(1, 0, 0, 40)
    toggleRow.BackgroundColor3       = Color3.fromRGB(8, 12, 26)
    toggleRow.BackgroundTransparency = 0.25
    toggleRow.BorderSizePixel        = 0
    toggleRow.ZIndex                 = 5
    toggleRow.Parent                 = ContentScroll

    local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 8); tc.Parent = toggleRow
    local ts = Instance.new("UIStroke"); ts.Color = T.BorderDim; ts.Thickness = 1; ts.Parent = toggleRow

    local toggleLbl = Instance.new("TextLabel")
    toggleLbl.Size               = UDim2.new(1, -58, 1, 0)
    toggleLbl.Position           = UDim2.new(0, 12, 0, 0)
    toggleLbl.BackgroundTransparency = 1
    toggleLbl.Text               = "Auto Sell HeroEquip"
    toggleLbl.TextColor3         = T.Text
    toggleLbl.TextSize           = 11
    toggleLbl.Font               = Enum.Font.Gotham
    toggleLbl.TextXAlignment     = Enum.TextXAlignment.Left
    toggleLbl.ZIndex             = 6
    toggleLbl.Parent             = toggleRow

    -- Toggle pill background
    local pillBg = Instance.new("Frame")
    pillBg.Size              = UDim2.new(0, 40, 0, 22)
    pillBg.Position          = UDim2.new(1, -50, 0.5, -11)
    pillBg.BackgroundColor3  = Color3.fromRGB(38, 38, 58)
    pillBg.BorderSizePixel   = 0
    pillBg.ZIndex            = 6
    pillBg.Parent            = toggleRow

    local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1, 0); pc.Parent = pillBg

    -- Toggle dot
    local dot = Instance.new("Frame")
    dot.Size             = UDim2.new(0, 16, 0, 16)
    dot.Position         = UDim2.new(0, 3, 0.5, -8)
    dot.BackgroundColor3 = Color3.fromRGB(110, 110, 140)
    dot.BorderSizePixel  = 0
    dot.ZIndex           = 7
    dot.Parent           = pillBg

    local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot

    local function refreshToggle()
        if AutoSellHeroEquipOn then
            pillBg.BackgroundColor3 = T.Accent
            dot.BackgroundColor3    = T.TextBright
            dot.Position            = UDim2.new(1, -19, 0.5, -8)
        else
            pillBg.BackgroundColor3 = Color3.fromRGB(38, 38, 58)
            dot.BackgroundColor3    = Color3.fromRGB(110, 110, 140)
            dot.Position            = UDim2.new(0, 3, 0.5, -8)
        end
    end
    refreshToggle()

    -- Full-row clickable hit region
    local toggleHit = Instance.new("TextButton")
    toggleHit.Size               = UDim2.new(1, 0, 1, 0)
    toggleHit.BackgroundTransparency = 1
    toggleHit.Text               = ""
    toggleHit.ZIndex             = 8
    toggleHit.Parent             = toggleRow

    toggleHit.MouseButton1Click:Connect(function()
        AutoSellHeroEquipOn = not AutoSellHeroEquipOn
        refreshToggle()
        setAutoSell(AutoSellHeroEquipOn)
    end)

    -- ── Helper: create a standard toggle row ──
    local function makeToggleRow(parent, order, label, isOn, onToggle)
        local row = Instance.new("Frame")
        row.LayoutOrder            = order
        row.Size                   = UDim2.new(1, 0, 0, 40)
        row.BackgroundColor3       = Color3.fromRGB(8, 12, 26)
        row.BackgroundTransparency = 0.25
        row.BorderSizePixel        = 0
        row.ZIndex                 = 5
        row.Parent                 = parent

        local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row
        local rs = Instance.new("UIStroke"); rs.Color = T.BorderDim; rs.Thickness = 1; rs.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -58, 1, 0); lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1; lbl.Text = label
        lbl.TextColor3 = T.Text; lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham; lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 6; lbl.Parent = row

        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(0, 40, 0, 22); bg.Position = UDim2.new(1, -50, 0.5, -11)
        bg.BackgroundColor3 = Color3.fromRGB(38, 38, 58); bg.BorderSizePixel = 0
        bg.ZIndex = 6; bg.Parent = row
        Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

        local dt = Instance.new("Frame")
        dt.Size = UDim2.new(0, 16, 0, 16); dt.Position = UDim2.new(0, 3, 0.5, -8)
        dt.BackgroundColor3 = Color3.fromRGB(110, 110, 140); dt.BorderSizePixel = 0
        dt.ZIndex = 7; dt.Parent = bg
        Instance.new("UICorner", dt).CornerRadius = UDim.new(1, 0)

        local state = isOn
        local function refresh()
            if state then
                bg.BackgroundColor3 = T.Accent; dt.BackgroundColor3 = T.TextBright
                dt.Position = UDim2.new(1, -19, 0.5, -8)
            else
                bg.BackgroundColor3 = Color3.fromRGB(38, 38, 58)
                dt.BackgroundColor3 = Color3.fromRGB(110, 110, 140)
                dt.Position = UDim2.new(0, 3, 0.5, -8)
            end
        end
        refresh()

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 1, 0); hit.BackgroundTransparency = 1
        hit.Text = ""; hit.ZIndex = 8; hit.Parent = row
        hit.MouseButton1Click:Connect(function()
            state = not state; refresh()
            if onToggle then onToggle(state) end
        end)

        return row
    end

    -- ── Auto Sell Weapon ──
    makeToggleRow(ContentScroll, 4, "Auto Sell Weapon", AutoSellWeaponOn, function(on)
        setAutoSellWeapon(on)
    end)

    -- ── Auto Collect Gold/Item ──
    makeToggleRow(ContentScroll, 5, "Auto Collect Gold/Item", AutoCollectGoldOn, function(on)
        setAutoCollectGold(on)
    end)

    -- ── Hide Damage ──
    makeToggleRow(ContentScroll, 6, "Hide Damage", HideDamageOn, function(on)
        setHideDamage(on)
    end)

    -- ── Hide Notif/Reward ──
    makeToggleRow(ContentScroll, 7, "Hide Notif/Reward", HideNotifOn, function(on)
        setHideNotif(on)
    end)
end

-- ============================================================
-- TAB BUTTONS
-- ============================================================
local TabButtons = {}
local Tabs = {"MAIN","ATTACK","FARM","AUTOMATION","REROLL","CLAIMS","PLAYERS","WEBHOOKS"}

-- Calculate tab button height so all 8 tabs fill the sidebar without overflowing
-- Available space = guiH - header(44) - playerstrip(72) - topPadding(16) - gaps(7x2)
local _availForTabs = guiH - 44 - 72 - 16 - (7 * 2)
local _calcBtnH     = math.floor(_availForTabs / #Tabs)
local tabBtnH       = math.max(28, math.min(_calcBtnH, isMobile and 44 or 40))

local function switchTab(name)
    State.ActiveTab   = name
    ContentTitle.Text = name
    for tname, btn in pairs(TabButtons) do
        if tname == name then
            btn.BackgroundColor3       = T.TabActive
            btn.BackgroundTransparency = 0.1
            btn.TextColor3             = T.TextBright
        else
            btn.BackgroundColor3       = T.BgSidebar
            btn.BackgroundTransparency = 1
            btn.TextColor3             = T.TextDim
        end
    end
    -- Clear everything (GuiObjects + UIComponents like UIListLayout, UIPadding)
    for _, child in pairs(ContentScroll:GetChildren()) do
        child:Destroy()
    end
    -- Build tab-specific content
    if name == "MAIN" then buildMainTab() end
end

for i, tabName in ipairs(Tabs) do
    local btn = Instance.new("TextButton")
    btn.LayoutOrder              = i
    btn.Size                     = UDim2.new(1,0,0,tabBtnH)
    btn.BackgroundColor3         = T.BgSidebar
    btn.BackgroundTransparency   = 1
    btn.BorderSizePixel          = 0
    btn.Text                     = tabName
    btn.TextColor3               = T.TextDim
    btn.TextSize                 = isMobile and 12 or 11
    btn.Font                     = Enum.Font.GothamBold
    btn.TextXAlignment           = Enum.TextXAlignment.Left
    btn.ZIndex                   = 4
    btn.Parent                   = TabScroll

    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,6); bc.Parent = btn
    local bp = Instance.new("UIPadding"); bp.PaddingLeft = UDim.new(0,10); bp.Parent = btn

    btn.MouseEnter:Connect(function()
        if tabName ~= State.ActiveTab then
            btn.BackgroundColor3       = T.TabHover
            btn.BackgroundTransparency = 0.2
        end
    end)
    btn.MouseLeave:Connect(function()
        if tabName ~= State.ActiveTab then
            btn.BackgroundColor3       = T.BgSidebar
            btn.BackgroundTransparency = 1
        end
    end)
    btn.MouseButton1Click:Connect(function() switchTab(tabName) end)

    TabButtons[tabName] = btn
end

switchTab("MAIN")

-- ============================================================
-- CLOSE CONFIRMATION DIALOG
-- ============================================================
local ConfirmDialog = Instance.new("Frame")
ConfirmDialog.Name                   = "ConfirmDialog"
ConfirmDialog.Size                   = UDim2.fromOffset(300, 135)
ConfirmDialog.Position               = UDim2.new(0.5,-150,0.5,-67)
ConfirmDialog.BackgroundColor3       = Color3.fromRGB(10,10,24)
ConfirmDialog.BackgroundTransparency = 0.30
ConfirmDialog.BorderSizePixel        = 0
ConfirmDialog.Visible                = false
ConfirmDialog.ZIndex                 = 50
ConfirmDialog.Parent                 = ScreenGui

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = ConfirmDialog
    local s = Instance.new("UIStroke"); s.Color = T.ConfirmBorder; s.Thickness = 2; s.Parent = ConfirmDialog
end

local ConfTitle = Instance.new("TextLabel")
ConfTitle.Size = UDim2.new(1,0,0,36); ConfTitle.Position = UDim2.new(0,0,0,6)
ConfTitle.BackgroundTransparency = 1; ConfTitle.Text = "FLa Project ASH - KONFIRMASI"
ConfTitle.TextColor3 = T.AccentBright; ConfTitle.TextSize = 12
ConfTitle.Font = Enum.Font.GothamBold; ConfTitle.ZIndex = 51; ConfTitle.Parent = ConfirmDialog

local ConfMsg = Instance.new("TextLabel")
ConfMsg.Size = UDim2.new(1,-20,0,36); ConfMsg.Position = UDim2.new(0,10,0,38)
ConfMsg.BackgroundTransparency = 1; ConfMsg.TextWrapped = true
ConfMsg.Text = "Apakah kamu yakin ingin keluar?\nSemua fungsi akan dinonaktifkan sepenuhnya."
ConfMsg.TextColor3 = T.Text; ConfMsg.TextSize = 11; ConfMsg.Font = Enum.Font.Gotham
ConfMsg.ZIndex = 51; ConfMsg.Parent = ConfirmDialog

local ConfYes = Instance.new("TextButton")
ConfYes.Size = UDim2.fromOffset(118,30); ConfYes.Position = UDim2.new(0.5,-122,1,-40)
ConfYes.BackgroundColor3 = T.Red; ConfYes.BackgroundTransparency = 0.1
ConfYes.BorderSizePixel = 0; ConfYes.Text = "YA, KELUAR"
ConfYes.TextColor3 = T.TextBright; ConfYes.TextSize = 11; ConfYes.Font = Enum.Font.GothamBold
ConfYes.ZIndex = 52; ConfYes.Parent = ConfirmDialog
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = ConfYes end

local ConfNo = Instance.new("TextButton")
ConfNo.Size = UDim2.fromOffset(118,30); ConfNo.Position = UDim2.new(0.5,4,1,-40)
ConfNo.BackgroundColor3 = T.DarkPurple; ConfNo.BackgroundTransparency = 0.1
ConfNo.BorderSizePixel = 0; ConfNo.Text = "BATAL"
ConfNo.TextColor3 = T.TextBright; ConfNo.TextSize = 11; ConfNo.Font = Enum.Font.GothamBold
ConfNo.ZIndex = 52; ConfNo.Parent = ConfirmDialog
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = ConfNo end

-- ============================================================
-- WINDOW CONTROLS
-- ============================================================
local function doMinimize()
    Main.Visible      = false
    MiniFrame.Visible = true
    State.IsOpen      = false
end

local function doExpand()
    State.IsExpanded = not State.IsExpanded
    local ti = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    if State.IsExpanded then
        TweenService:Create(Main, ti, {Size = ExpandedSize, Position = ExpandedPos}):Play()
        ExpandBtn.Text = "[-]"
    else
        TweenService:Create(Main, ti, {Size = NormalSize, Position = NormalPos}):Play()
        ExpandBtn.Text = "[]"
    end
end

local function doClose()
    ConfirmDialog.Visible = true
end

ConfYes.MouseButton1Click:Connect(function()
    State.FunctionsEnabled = false
    for _, f in pairs(State.AllFunctions) do
        if f.disable then pcall(f.disable) end
    end
    ConfirmDialog.Visible = false
    Main.Visible          = false
    MiniFrame.Visible     = false
    task.delay(0.4, function()
        if ScreenGui and ScreenGui.Parent then
            ScreenGui:Destroy()
        end
    end)
end)

ConfNo.MouseButton1Click:Connect(function()
    ConfirmDialog.Visible = false
end)

MinBtn.MouseButton1Click:Connect(doMinimize)
ExpandBtn.MouseButton1Click:Connect(doExpand)
CloseBtn.MouseButton1Click:Connect(doClose)

-- ============================================================
-- GUI loaded and ready
-- Platform: " .. (isMobile and "Mobile (Delta)" or "Desktop (Xeno)") .. "
-- ============================================================
