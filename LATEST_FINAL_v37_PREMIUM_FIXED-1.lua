--[[
    AUTO FARM RANDOM - STANDALONE
    by FLa Project

    FITUR:
    - Scan semua musuh di workspace.Enemys (map aktif player saat ini)
    - Pilih 1 musuh secara RANDOM, teleport + freeze player ke posisi musuh itu
    - Spam remote "ClickEnemy" (InvokeServer) terus-terusan ke musuh itu sampai mati
    - Begitu musuh mati / hilang, otomatis re-roll musuh random berikutnya
    - GUI sederhana: Start/Stop, status target sekarang, counter kill, jumlah musuh di map

    CATATAN:
    - EnemyGUID/posisi diisi otomatis dari musuh yang dipilih, tidak perlu input manual.
    - Loop spam pakai task.wait() kosong (rate ngikut frame rate executor), bukan
      fixed-timestep -- simpel & cukup buat farming biasa.
    - Kalau remote yang dipakai server kamu beda nama/argumen, tinggal ganti di
      bagian RE_Click / FireFarmAttack di bawah.
]]

-- ====================== SERVICES & INIT ======================
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local LP      = Players.LocalPlayer
local PG      = LP:WaitForChild("PlayerGui")

local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
    local w = 0
    repeat
        task.wait(0.5)
        w = w + 1
        Remotes = RS:FindFirstChild("Remotes")
    until Remotes or w >= 30
end

local RE_Click = Remotes and Remotes:FindFirstChild("ClickEnemy")

-- ====================== STATE ======================
local Running       = false
local CurrentTarget = nil   -- {model, guid, hrp, name}
local KillCount      = 0
local _frozenWS       = nil
local _mainThread, _spamThread

-- ====================== HELPERS ======================
local function GetEnemiesInMap()
    local result = {}
    local enemiesFolder = workspace:FindFirstChild("Enemys")
    if not enemiesFolder then return result end

    for _, model in ipairs(enemiesFolder:GetChildren()) do
        if model:IsA("Model") then
            local hum = model:FindFirstChildOfClass("Humanoid")
            local hrp = model:FindFirstChild("HumanoidRootPart")
            local guid = model:GetAttribute("guid") or model:GetAttribute("Guid") or model:GetAttribute("GUID")
            if hum and hrp and guid and hum.Health > 0 then
                table.insert(result, {
                    model = model,
                    hrp   = hrp,
                    guid  = guid,
                    name  = model.Name,
                })
            end
        end
    end
    return result
end

local function PickRandomEnemy()
    local pool = GetEnemiesInMap()
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

local function IsTargetAlive(t)
    if not t or not t.model or not t.model.Parent then return false end
    local hum = t.model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

local function FreezePlayer()
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        _frozenWS = hum.WalkSpeed
        hum.WalkSpeed = 0
        hum.JumpPower = 0
    end
end

local function UnfreezePlayer()
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = _frozenWS or 16
        hum.JumpPower = 50
    end
    _frozenWS = nil
end

local function TpToTarget(t)
    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not t or not t.hrp then return end
    hrp.CFrame = t.hrp.CFrame * CFrame.new(0, 0, 4)
end

-- ====================== MAIN LOGIC ======================
local function StartFarm()
    Running = true
    CurrentTarget = nil
    KillCount = 0
    FreezePlayer()

    -- Thread cari/retarget musuh random + teleport
    _mainThread = task.spawn(function()
        while Running do
            if not CurrentTarget or not IsTargetAlive(CurrentTarget) then
                CurrentTarget = PickRandomEnemy()
                if CurrentTarget then
                    TpToTarget(CurrentTarget)
                    FreezePlayer()

                    local hum = CurrentTarget.model:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local capturedGuid = CurrentTarget.guid
                        hum.Died:Connect(function()
                            KillCount = KillCount + 1
                            if CurrentTarget and CurrentTarget.guid == capturedGuid then
                                CurrentTarget = nil
                            end
                        end)
                    end
                end
            end
            task.wait(0.15)
        end
    end)

    -- Thread spam ClickEnemy ke target saat ini
    _spamThread = task.spawn(function()
        while Running do
            if CurrentTarget and IsTargetAlive(CurrentTarget) and RE_Click then
                pcall(function()
                    RE_Click:InvokeServer({ enemyGuid = CurrentTarget.guid })
                end)
            end
            task.wait()
        end
    end)
end

local function StopFarm()
    Running = false
    for _, th in ipairs({ _mainThread, _spamThread }) do
        if th then pcall(function() task.cancel(th) end) end
    end
    _mainThread, _spamThread = nil, nil
    CurrentTarget = nil
    UnfreezePlayer()
end

-- ====================== GUI ======================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFarmRandomGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PG

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 230, 0, 190)
Main.Position = UDim2.new(0, 20, 0.5, -95)
Main.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui
local MainCorner = Instance.new("UICorner"); MainCorner.CornerRadius = UDim.new(0, 10); MainCorner.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundTransparency = 1
Title.Text = "AUTO FARM RANDOM"
Title.TextColor3 = Color3.fromRGB(150, 130, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.Parent = Main

local Body = Instance.new("Frame")
Body.Size = UDim2.new(1, -16, 1, -38)
Body.Position = UDim2.new(0, 8, 0, 34)
Body.BackgroundTransparency = 1
Body.Parent = Main
local BodyLayout = Instance.new("UIListLayout")
BodyLayout.Padding = UDim.new(0, 6)
BodyLayout.Parent = Body

local function MakeStatusLbl(order)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.LayoutOrder = order
    lbl.Text = ""
    lbl.TextColor3 = Color3.fromRGB(180, 180, 195)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = Body
    return lbl
end

local TargetLbl = MakeStatusLbl(1)
local KillLbl    = MakeStatusLbl(2)
local CountLbl   = MakeStatusLbl(3)

if not RE_Click then
    local warnLbl = MakeStatusLbl(4)
    warnLbl.Text = "[!] Remote ClickEnemy TIDAK ditemukan!"
    warnLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
end

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, 0, 0, 32)
ToggleBtn.LayoutOrder = 5
ToggleBtn.BackgroundColor3 = Color3.fromRGB(150, 130, 255)
ToggleBtn.Text = "START"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 13
ToggleBtn.AutoButtonColor = false
ToggleBtn.Parent = Body
local ToggleCorner = Instance.new("UICorner"); ToggleCorner.CornerRadius = UDim.new(0, 8); ToggleCorner.Parent = ToggleBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 22, 0, 22)
CloseBtn.Position = UDim2.new(1, -28, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 35)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = Main
local CloseCorner = Instance.new("UICorner"); CloseCorner.CornerRadius = UDim.new(0, 6); CloseCorner.Parent = CloseBtn

ToggleBtn.MouseButton1Click:Connect(function()
    if Running then
        StopFarm()
        ToggleBtn.Text = "START"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(150, 130, 255)
    else
        StartFarm()
        ToggleBtn.Text = "STOP"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    StopFarm()
    ScreenGui:Destroy()
end)

-- Loop update GUI status
task.spawn(function()
    while ScreenGui.Parent do
        if Running then
            if CurrentTarget and IsTargetAlive(CurrentTarget) then
                TargetLbl.Text = "Target: " .. CurrentTarget.name .. " •" .. CurrentTarget.guid:sub(-5)
                TargetLbl.TextColor3 = Color3.fromRGB(150, 220, 150)
            else
                TargetLbl.Text = "Target: mencari musuh..."
                TargetLbl.TextColor3 = Color3.fromRGB(220, 200, 130)
            end
        else
            TargetLbl.Text = "Target: -"
            TargetLbl.TextColor3 = Color3.fromRGB(150, 150, 165)
        end
        KillLbl.Text = "Kill: " .. KillCount
        CountLbl.Text = "Musuh di map: " .. #GetEnemiesInMap()
        task.wait(0.2)
    end
end)
