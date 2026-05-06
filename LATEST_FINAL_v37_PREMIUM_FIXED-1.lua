--   Arise Shadow Hunt — Auto Farming GUI
--   Theme : Full Orange iPhone 17 Pro Max
--   By    : FLa Project  (Fixed by Assistant — v112)
--   Platform : Android (Delta) + PC (Xeno) — Full Support
--   [v51] __namecall hook: skip semua non-remote via == check (fix TeleportPanel crash)
--   [v51] ResetSnapshot dijadikan global (fix nil error di difficulty dropdown)
--   [v51] Difficulty dropdown: task.defer fix DDLayer stealing clicks
--   [v51] Preferred map: static 1-18
--   [v73] FIX: HERO_GUIDS tidak di-wipe saat masuk raid (hero tetap serang)
--   [v73] FIX: RaidFireDamage fire attackType 1+2+3 (damage lebih konsisten)
--   [v73] FIX: Boss search retry sampai 20 detik + TP ulang tiap 2 detik
--   [v73] FIX: Chest scan multi-nama + retry 3 detik setelah boss mati
--   [v73] FIX: RaidCollectAll scan workspace root + semua folder reward
--   [v73] FIX: HERO_GUIDS recovery otomatis via HeroUseSkill scan tiap masuk raid
--   [v112] FIX: Live timer MA+Raid+Siege, waiting status info MA/Raid aktif, timer sesi
--   [v113] FIX: Siege data.action (bukan actionType) + GetCityRaidInfos scan awal + pre-listen
--   [v114] NEW: Rune Map — filter raid berdasarkan minimum grade via TextChatService
--   [v114] NEW: Auto Siege collapsible (buka/tutup seperti Auto Raid)
--   [v115] NEW: Chat History Scan — parse riwayat chat saat script load
--   [v115] NEW: Siege detection via chat "X, MapName has begun. Come and join in."
--   [v115] FIX: PickRaidByDifficulty — Rune Map Only mode (tanpa Preferred, hanya grade)
--   [v115] FIX: Grade [SS] ditambahkan ke GRADE_RANK (antara S dan G)

do
Players          = game:GetService("Players")
TweenService     = game:GetService("TweenService")
UserInputService = game:GetService("UserInputService")
RunService       = game:GetService("RunService")
RS               = game:GetService("ReplicatedStorage")
TeleportService  = game:GetService("TeleportService")
GuiService       = game:GetService("GuiService")
VIM              = game:GetService("VirtualInputManager")

LP  = Players.LocalPlayer
PG  = LP.PlayerGui

-- ============================================================
-- [v113] PRE-LISTEN UpdateCityRaidInfo — SEBELUM task.wait(3)
-- PENTING: field dari sniffing adalah data.action (BUKAN data.actionType)
-- Listener dipasang sedini mungkin agar tidak miss event saat rejoin.
-- GetCityRaidInfos dipanggil setelah listener terpasang untuk scan state awal.
-- ============================================================
local CITY_TO_MAP_EARLY = {[1000001]=3,[1000002]=7,[1000003]=10,[1000004]=13}
_siegeLiveEarly = {}   -- buffer sementara sebelum SIEGE table siap

task.spawn(function()
    local Rem = RS:WaitForChild("Remotes", 15)
    if not Rem then return end
    local re = Rem:WaitForChild("UpdateCityRaidInfo", 10)
    if not re then return end
    re.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local id     = data.id
        local action = data.action   -- [v113] FIX: field asli adalah "action" bukan "actionType"
        if not id or not action then return end
        local mn = CITY_TO_MAP_EARLY[id]
        if not mn then return end
        if action == "OpenCityRaid" then
            _siegeLiveEarly[id] = mn
            warn("[ ASH SIEGE ] ✅ Map "..mn.." BUKA")
        elseif action == "CloseCityRaid" then
            _siegeLiveEarly[id] = nil
            warn("[ ASH SIEGE ] 🔒 Map "..mn.." TUTUP  nextTime="..tostring(data.nextTime))
        end
        if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
        if SIEGE and SIEGE.live then
            if action == "OpenCityRaid" then
                SIEGE.live[id] = mn
            elseif action == "CloseCityRaid" then
                SIEGE.live[id] = nil
            end
        end
    end)
    warn("[ ASH SIEGE ] Listener UpdateCityRaidInfo terpasang (pre-wait)")

    -- [v113] GetCityRaidInfos — scan state awal semua siege
    -- Dipanggil SETELAH listener terpasang agar tidak ada race condition
    task.wait(0.5)
    pcall(function()
        local getCR = Rem:FindFirstChild("GetCityRaidInfos")
        if not getCR then
            warn("[ ASH SIEGE ] GetCityRaidInfos tidak ditemukan — andalkan notif saja")
            return
        end
        local result = getCR:InvokeServer()
        if type(result) ~= "table" then return end
        for _, entry in ipairs(result) do
            if type(entry) ~= "table" then continue end
            local id     = entry.id
            local action = entry.action
            local mn     = CITY_TO_MAP_EARLY[id]
            if not mn then continue end
            if action == "OpenCityRaid" then
                _siegeLiveEarly[id] = mn
                warn("[ ASH SIEGE ] ✅ GetCityRaidInfos — Map "..mn.." BUKA")
            else
                _siegeLiveEarly[id] = nil
                warn("[ ASH SIEGE ] 🔒 GetCityRaidInfos — Map "..mn.." TUTUP")
            end
            if SIEGE and SIEGE.live then
                if action == "OpenCityRaid" then SIEGE.live[id] = mn
                else SIEGE.live[id] = nil end
            end
        end
        if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
    end)
end)

-- ============================================================
-- CLEANUP OLD GUI
-- ============================================================
for _, name in ipairs({"ASH_GUI", "ASH_DD"}) do
    pcall(function()
        local old = PG:FindFirstChild(name)
        if old then old:Destroy() end
    end)
end
task.wait(3)

-- ============================================================
-- REMOTES
-- ============================================================
Remotes = RS:WaitForChild("Remotes", 10)
RE = {
    CollectItem          = Remotes:WaitForChild("CollectItem", 10),
    ExtraReward          = Remotes:FindFirstChild("ExtraReward"),
    ShowReward           = Remotes:FindFirstChild("ShowReward"),
    DropItems            = Remotes:FindFirstChild("DropItems"),
    AutoHeroQuirk        = Remotes:FindFirstChild("AutoRandomHeroQuirk"),
    RandomHeroQuirk      = Remotes:WaitForChild("RandomHeroQuirk", 10),
    Click                = Remotes:FindFirstChild("ClickEnemy"),
    Atk                  = Remotes:FindFirstChild("PlayerClickAttackSkill"),
    Death                = Remotes:FindFirstChild("EnemyDeath"),
    HeroMove             = Remotes:FindFirstChild("HeroMoveToEnemyPos"),
    HeroStand            = Remotes:FindFirstChild("HeroStandTo"),
    HeroSkill            = Remotes:FindFirstChild("HeroPlaySkillAnim"),
    HeroUseSkill         = Remotes:FindFirstChild("HeroUseSkill"),
    EquipWeapon          = Remotes:WaitForChild("EquipWeapon", 10),
    RandomWeaponQuirk    = Remotes:WaitForChild("RandomWeaponQuirk", 10),
    RandomHeroEquipGrade = Remotes:WaitForChild("RandomHeroEquipGrade", 10),
    RerollHalo           = Remotes:FindFirstChild("RerollHalo"),
    RerollOrnament       = Remotes:WaitForChild("RerollOrnament", 15),
    StartTp              = Remotes:FindFirstChild("StartLocalPlayerTeleport"),
    LocalTp              = Remotes:FindFirstChild("LocalPlayerTeleport"),
    CreateRaidTeam           = Remotes:FindFirstChild("CreateRaidTeam"),
    StartChallengeRaidMap    = Remotes:FindFirstChild("StartChallengeRaidMap"),
    EquipHeroWithData        = Remotes:FindFirstChild("EquipHeroWithData"),
    LocalTpSuccess           = Remotes:FindFirstChild("LocalPlayerTeleportSuccess"),
    GainRaidsRewards         = Remotes:FindFirstChild("GainRaidsRewards"),

    GetDrawHeroId            = Remotes:FindFirstChild("GetDrawHeroId"),
    GetRaidTeamInfos         = Remotes:FindFirstChild("GetRaidTeamInfos"),
}

MY_USER_ID = LP.UserId
HERO_GUIDS, HERO_DATA = {}, {}  -- hero data
-- { [heroGuid] = attackType } -- auto-populated via HeroUseSkill hook

-- HeroUseSkill capture: dilakukan via __namecall di SetupUniversalSpy (setelah 30s)
-- ExtraReward & GainRaidsRewards: dipanggil langsung di AttackLoop, tidak perlu hook

-- ============================================================
-- IsValidUUID
-- ============================================================
UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
function IsValidUUID(s)
    return type(s) == "string" and #s == 36 and s:match(UUID_PATTERN) ~= nil
end

-- ============================================================
-- WARNA
-- ============================================================
C = {
    BG       = Color3.fromRGB(210, 85, 10),
    BG2      = Color3.fromRGB(185, 70,  5),
    BG3      = Color3.fromRGB(165, 58,  2),
    SURFACE  = Color3.fromRGB(175, 65,  5),
    SURFACE2 = Color3.fromRGB(195, 75,  8),
    SIDEBAR  = Color3.fromRGB(145, 50,  0),
    ACC      = Color3.fromRGB(255, 160, 60),
    ACC2     = Color3.fromRGB(255, 200,100),
    ACC3     = Color3.fromRGB(255, 220,140),
    BORD     = Color3.fromRGB(230, 110, 30),
    BORD2    = Color3.fromRGB(255, 150, 55),
    TXT      = Color3.fromRGB(255, 250,240),
    TXT2     = Color3.fromRGB(255, 210,160),
    TXT3     = Color3.fromRGB(255, 180,100),
    TBAR     = Color3.fromRGB(140, 48,  0),
    SEL_BG   = Color3.fromRGB(130, 45,  0),
    SEL_BORD = Color3.fromRGB(255, 190, 80),
    WIN_CLOSE= Color3.fromRGB(220, 55, 65),
    WIN_MIN  = Color3.fromRGB(255, 190, 50),
    WIN_MAX  = Color3.fromRGB( 60, 210, 80),
    BLACK    = Color3.fromRGB(  0,   0,  0),
    DD_BG    = Color3.fromRGB(100, 35,  0),
    DD_HOVER = Color3.fromRGB(160, 58,  3),
    GRN      = Color3.fromRGB( 55, 210, 90),
    RED      = Color3.fromRGB(215,  50, 60),
    YEL      = Color3.fromRGB(255, 195, 60),
    DIM      = Color3.fromRGB(160, 148,135),
    DK       = Color3.fromRGB( 80,  72, 65),
    AG       = Color3.fromRGB(255, 140, 20),
    ROW      = Color3.fromRGB( 22,  22, 28),
    NSEL     = Color3.fromRGB( 90,  35,  8),
}

-- ============================================================
-- UI HELPERS
-- ============================================================
function New(class, props)
    local obj = Instance.new(class)
    for k, v in pairs(props) do pcall(function() obj[k] = v end) end
    return obj
end

function Frame(parent, color, size)
    return New("Frame", {
        Parent = parent, BackgroundColor3 = color,
        Size = size or UDim2.new(1,0,1,0), BorderSizePixel = 0
    })
end

function Btn(parent, color, size)
    return New("TextButton", {
        Parent = parent, BackgroundColor3 = color,
        Size = size or UDim2.new(1,0,1,0), BorderSizePixel = 0,
        Text = "", AutoButtonColor = false
    })
end

function Label(parent, text, size, color, font, xalign)
    return New("TextLabel", {
        Parent = parent, BackgroundTransparency = 1,
        Size = UDim2.new(1,0,1,0), Text = text, TextSize = size or 14,
        TextColor3 = color or C.TXT, Font = font or Enum.Font.Gotham,
        TextXAlignment = xalign or Enum.TextXAlignment.Left, BorderSizePixel = 0
    })
end

function Corner(obj, r)
    New("UICorner", {Parent = obj, CornerRadius = UDim.new(0, r or 8)})
end

function Stroke(obj, color, thickness, transparency)
    New("UIStroke", {
        Parent = obj, Color = color or C.BORD,
        Thickness = thickness or 1, Transparency = transparency or 0
    })
end

function Padding(obj, top, bottom, left, right)
    New("UIPadding", {
        Parent = obj,
        PaddingTop    = UDim.new(0, top    or 6),
        PaddingBottom = UDim.new(0, bottom or 6),
        PaddingLeft   = UDim.new(0, left   or 8),
        PaddingRight  = UDim.new(0, right  or 8),
    })
end

function ListLayout(parent, dir, align, spacing)
    return New("UIListLayout", {
        Parent = parent,
        FillDirection       = dir    or Enum.FillDirection.Vertical,
        HorizontalAlignment = align  or Enum.HorizontalAlignment.Left,
        SortOrder           = Enum.SortOrder.LayoutOrder,
        Padding             = UDim.new(0, spacing or 4),
    })
end

function GuiInsetY()
    local ok, y = pcall(function() return GuiService:GetGuiInset().Y end)
    return (ok and type(y) == "number") and y or 36
end

-- ============================================================
-- SCREEN GUI
-- ============================================================
ScreenGui = New("ScreenGui", {
    Parent = PG, Name = "ASH_GUI",
    ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999, IgnoreGuiInset = true,
    Active = false,
})

local _vp = workspace.CurrentCamera.ViewportSize
_isSmallScreen = _vp.X < 700
WIN_W = _isSmallScreen and math.min(math.floor(_vp.X * 0.96), 420) or 500
WIN_H = _isSmallScreen and math.min(math.floor(_vp.Y * 0.82), 380) or 360

Window = Frame(ScreenGui, C.BG, UDim2.new(0, WIN_W, 0, WIN_H))
Window.Position = UDim2.new(0.5, -WIN_W/2, 0.05, 0)
Window.ClipsDescendants = true
Window.Active = false
Corner(Window, 14)
Stroke(Window, C.BORD2, 1.5, 0)
New("UIGradient", {
    Parent = Window,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.BG),
        ColorSequenceKeypoint.new(1, C.BG3),
    }),
    Rotation = 135,
})

-- ============================================================
-- BUBBLE — DIGANTI DARI sc_baru (v14.5)
-- Perubahan vs versi lama FLA_FIX_V10:
--   • Tampilan: gradient orange + label "FLa" & "ASH"
--   • Drag: pakai delta posisi sederhana + clamp viewport
--   • Float: sin wave ringan via task.spawn loop
--   • Show/Hide: pop tween Back + shrink tween Back
-- ============================================================
Bubble = Btn(ScreenGui, C.TBAR, UDim2.new(0,58,0,58))
Bubble.Position = UDim2.new(0.5,-29,0,50)
Bubble.Visible  = false
Bubble.ZIndex   = 10
Corner(Bubble, 30)

;(function()
    -- Gradient
    local g = Instance.new("UIGradient", Bubble)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255,120,30)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(160,50,5)),
    })
    g.Rotation = 135

    -- Stroke
    local s = Instance.new("UIStroke", Bubble)
    s.Color = Color3.fromRGB(255,175,80); s.Thickness = 2; s.Transparency = 0.15

    -- Label atas: "FLa"
    local l1 = Instance.new("TextLabel", Bubble)
    l1.Size = UDim2.new(1,0,0.55,0); l1.Position = UDim2.new(0,0,0.07,0)
    l1.BackgroundTransparency = 1; l1.Text = "FLa"; l1.TextSize = 15
    l1.Font = Enum.Font.GothamBold; l1.TextColor3 = Color3.fromRGB(255,255,255)
    l1.TextXAlignment = Enum.TextXAlignment.Center

    -- Label bawah: "ASH"
    local l2 = Instance.new("TextLabel", Bubble)
    l2.Size = UDim2.new(1,0,0.3,0); l2.Position = UDim2.new(0,0,0.64,0)
    l2.BackgroundTransparency = 1; l2.Text = "ASH"; l2.TextSize = 7
    l2.Font = Enum.Font.Gotham; l2.TextColor3 = C.ACC2
    l2.TextXAlignment = Enum.TextXAlignment.Center
end)()

-- Float Animation
function FloatBubble()
    task.spawn(function()
        local t = 0
        while Bubble.Visible do
            t = t + task.wait(0.03)
            local p = Bubble.Position
            Bubble.Position = UDim2.new(
                p.X.Scale, p.X.Offset,
                p.Y.Scale, p.Y.Offset + math.sin(t*2)*4 - math.sin((t-0.03)*2)*4
            )
        end
    end)
end

-- Drag Bubble
;(function()
    local bd  = false
    local bsm = Vector2.new()
    local bsp = Vector2.new()

    Bubble.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            bd  = true
            bsm = Vector2.new(i.Position.X, i.Position.Y)
            bsp = Vector2.new(Bubble.AbsolutePosition.X, Bubble.AbsolutePosition.Y)
        end
    end)

    UserInputService.InputChanged:Connect(function(i)
        if bd and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
            local inset = GuiService:GetGuiInset()
            local vp    = workspace.CurrentCamera.ViewportSize
            Bubble.Position = UDim2.new(
                0, math.clamp(bsp.X + (i.Position.X - bsm.X), 0, vp.X - 58),
                0, math.clamp(bsp.Y + (i.Position.Y - bsm.Y) - inset.Y, 0, vp.Y - 58)
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            bd = false
        end
    end)
end)()

-- ============================================================
-- TOPBAR
-- ============================================================
function BuildTopBar()
    TopBar = Frame(Window, C.TBAR, UDim2.new(1,0,0,40))
    Corner(TopBar, 14)
    local TBFix = Frame(TopBar, C.TBAR, UDim2.new(1,0,0,14))
    TBFix.Position = UDim2.new(0,0,1,-14)

    local IconBg = Frame(TopBar, C.SEL_BG, UDim2.new(0,28,0,28))
    IconBg.Position = UDim2.new(0,8,0.5,-14)
    Corner(IconBg, 7); Stroke(IconBg, C.ACC, 1, 0.3)
    local IconLbl = Label(IconBg, "⚔", 16, C.ACC2, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
    IconLbl.Size = UDim2.new(1,0,1,0)

    local TitleLbl = Label(TopBar, "Auto Farming", 15, C.ACC2, Enum.Font.GothamBold)
    TitleLbl.Size = UDim2.new(0,160,0,22); TitleLbl.Position = UDim2.new(0,44,0,5)
    local SubLbl = Label(TopBar, "Arise Shadow Hunt  •  by FLa", 11, C.TXT3, Enum.Font.Gotham)
    SubLbl.Size = UDim2.new(0,220,0,14); SubLbl.Position = UDim2.new(0,44,0,23)

    function WinBtn(xOffset, color, symbol)
        local b = Btn(TopBar, color, UDim2.new(0,20,0,20))
        b.Position = UDim2.new(0, xOffset, 0.5, -10); Corner(b, 10)
        local l = Label(b, symbol, 11, C.BLACK, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        l.Size = UDim2.new(1,0,1,0)
        return b
    end

    local BtnMin   = WinBtn(WIN_W - 68, C.WIN_MIN, "—")
    local BtnMax   = WinBtn(WIN_W - 46, C.WIN_MAX, "□")
    local BtnClose = WinBtn(WIN_W - 24, C.WIN_CLOSE, "✕")

    -- Drag Window
    local dragging, dragStart, startPos = false, nil, nil
    TopBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = Window.Position
        end
    end)
    TopBar.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            Window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)

    -- Show Bubble (minimize) — dari sc_baru
    function ShowBubble()
        Window.Visible = false
        local vp = workspace.CurrentCamera.ViewportSize
        Bubble.Position = UDim2.new(0, vp.X/2 - 29, 0, 50)
        Bubble.Size     = UDim2.new(0,0,0,0)
        Bubble.Visible  = true
        TweenService:Create(Bubble,
            TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = UDim2.new(0,58,0,58)}
        ):Play()
        FloatBubble()
    end

    -- Show Window (restore) — dari sc_baru
    function ShowWin()
        TweenService:Create(Bubble,
            TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In),
            {Size = UDim2.new(0,0,0,0)}
        ):Play()
        task.wait(0.19)
        Bubble.Visible = false
        Bubble.Size    = UDim2.new(0,58,0,58)
        Window.Visible = true
    end

    BtnMin.MouseButton1Click:Connect(ShowBubble)
    Bubble.MouseButton1Click:Connect(ShowWin)

    -- Maximize tetap dari versi lama
    local isFS, prevSz, prevPs = false, Window.Size, Window.Position
    BtnMax.MouseButton1Click:Connect(function()
        isFS = not isFS
        if isFS then
            prevSz = Window.Size; prevPs = Window.Position
            TweenService:Create(Window, TweenInfo.new(0.2),
                {Size = UDim2.new(1,0,1,0), Position = UDim2.new(0,0,0,0)}):Play()
        else
            TweenService:Create(Window, TweenInfo.new(0.2),
                {Size = prevSz, Position = prevPs}):Play()
        end
    end)
    BtnClose.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)
end
BuildTopBar()

-- ============================================================
-- BODY & SIDEBAR
-- ============================================================
local SIDEBAR_W = _isSmallScreen and 72 or 100

Body = Frame(Window, C.BG3, UDim2.new(1,0,1,-40))
Body.Position = UDim2.new(0,0,0,40)
Body.Active = false

local SideBar = Frame(Body, C.SIDEBAR, UDim2.new(0, SIDEBAR_W, 1, 0))
local SideScroll = New("ScrollingFrame", {
    Parent = SideBar, Size = UDim2.new(1,0,1,-8), Position = UDim2.new(0,0,0,4),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = _isSmallScreen and 4 or 2, ScrollBarImageColor3 = C.ACC,
    CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
ListLayout(SideScroll, nil, Enum.HorizontalAlignment.Center, 2)
Padding(SideScroll, 4, 4, 4, 4)

ContentFrame = Frame(Body, C.BLACK, UDim2.new(1,-SIDEBAR_W,1,0))
ContentFrame.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
ContentFrame.BackgroundTransparency = 1

-- ============================================================
-- TAB SYSTEM
-- ============================================================
local NAV_ITEMS = {
    {tag="main",     ico="🏠", lbl="Main"},
    {tag="farm",     ico="⚔",  lbl="Farm"},
    {tag="attack",   ico="💥", lbl="Attack"},
    {tag="autoraid", ico="⚡", lbl="Automation"},
    {tag="player",   ico="🧍", lbl="Player"},
    {tag="autoroll", ico="🎲", lbl="Reroll"},
    {tag="claim",    ico="🎁", lbl="Claim"},
    {tag="settings", ico="⚙",  lbl="Settings"},
}

Panels, NavRefs = {}, {}
ActiveTab = ""

function NewPanel(tag)
    local p = New("ScrollingFrame", {
        Parent = ContentFrame, Size = UDim2.new(1,0,1,0),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = _isSmallScreen and 5 or 3,
        ScrollBarImageColor3 = C.ACC,
        CanvasSize = UDim2.new(0,0,0,0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    })
    ListLayout(p, nil, Enum.HorizontalAlignment.Center, 5)
    Padding(p, 8, 8, 8, 8)
    Panels[tag] = p; return p
end

function SwitchTab(tag)
    if ActiveTab == tag then return end
    ActiveTab = tag
    for t, p in pairs(Panels) do p.Visible = (t == tag) end
    for _, ref in ipairs(NavRefs) do
        local sel = ref.tag == tag
        TweenService:Create(ref.bg, TweenInfo.new(0.12), {
            BackgroundTransparency = sel and 0 or 1,
            BackgroundColor3 = sel and C.SEL_BG or C.SIDEBAR,
        }):Play()
        ref.bar.BackgroundColor3 = sel and C.ACC2 or C.SIDEBAR
        ref.lbl.TextColor3 = sel and C.ACC2 or C.TXT2
        ref.ico.TextColor3 = sel and C.ACC2 or C.TXT3
        local s = ref.bg:FindFirstChildWhichIsA("UIStroke")
        if sel then
            if not s then
                New("UIStroke", {Parent = ref.bg, Color = C.SEL_BORD, Thickness = 1, Transparency = 0.4})
            end
        else
            if s then s:Destroy() end
        end
    end
end

for i, item in ipairs(NAV_ITEMS) do
    local bg = Btn(SideScroll, C.SIDEBAR, UDim2.new(1,-8,0,34))
    bg.LayoutOrder = i; bg.BackgroundTransparency = 1; Corner(bg, 8)
    local bar = Frame(bg, C.SIDEBAR, UDim2.new(0,3,0.5,0))
    bar.Position = UDim2.new(0,0,0.25,0); Corner(bar, 2)
    local icoL = Label(bg, item.ico, 15, C.TXT3, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
    icoL.Size = UDim2.new(0,24,1,0); icoL.Position = UDim2.new(0,6,0,0)
    local lblL = Label(bg, item.lbl, 11, C.TXT2, Enum.Font.Gotham, Enum.TextXAlignment.Left)
    lblL.Size = UDim2.new(1,-34,1,0); lblL.Position = UDim2.new(0,32,0,0)
    lblL.TextTruncate = Enum.TextTruncate.AtEnd
    NavRefs[i] = {tag=item.tag, bg=bg, bar=bar, ico=icoL, lbl=lblL}
    bg.MouseButton1Click:Connect(function() SwitchTab(item.tag) end)
end

-- ============================================================
-- PANEL HELPERS
-- ============================================================
function SectionHeader(panel, title, order)
    local f = Frame(panel, C.BLACK, UDim2.new(1,0,0,20))
    f.BackgroundTransparency = 1; f.LayoutOrder = order or 0
    local l = Label(f, "  "..title, 11, C.ACC2, Enum.Font.GothamBold)
    l.Size = UDim2.new(1,0,1,0)
    local line = Frame(f, C.ACC2, UDim2.new(1,0,0,1))
    line.Position = UDim2.new(0,0,1,-1); line.BackgroundTransparency = 0.6
end

function ToggleRow(panel, title, desc, order, onToggle)
    local h = desc and 50 or 38
    local row = Frame(panel, C.SURFACE, UDim2.new(1,0,0,h))
    row.LayoutOrder = order or 1; Corner(row, 8); Stroke(row, C.BORD, 1, 0.4)
    local lbl = Label(row, title, 12, C.TXT, Enum.Font.GothamBold)
    lbl.Size = UDim2.new(1,-60,0,18); lbl.Position = UDim2.new(0,12,0, desc and 8 or 10)
    if desc then
        local sub = Label(row, desc, 10, C.TXT2, Enum.Font.Gotham)
        sub.Size = UDim2.new(1,-60,0,14); sub.Position = UDim2.new(0,12,0,26)
    end
    local pill = Btn(row, Color3.fromRGB(120,40,0), UDim2.new(0,44,0,24))
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Position = UDim2.new(1,-10,0.5,0); Corner(pill, 12)
    local knob = Frame(pill, Color3.fromRGB(190,130,70), UDim2.new(0,18,0,18))
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Position = UDim2.new(0,3,0.5,0); Corner(knob, 9)
    local state = false
    local function SetState(v)
        state = v
        TweenService:Create(pill, TweenInfo.new(0.16), {BackgroundColor3 = v and C.ACC2 or Color3.fromRGB(120,40,0)}):Play()
        TweenService:Create(knob, TweenInfo.new(0.16), {
            Position = v and UDim2.new(1,-21,0.5,0) or UDim2.new(0,3,0.5,0),
            BackgroundColor3 = v and Color3.fromRGB(255,255,255) or Color3.fromRGB(190,130,70),
        }):Play()
        if onToggle then onToggle(v) end
    end
    pill.MouseButton1Click:Connect(function() SetState(not state) end)
    return row, SetState
end

-- ============================================================
-- STATE & LOOPS
-- ============================================================
STATE = {autoCollect=false, autoDestroyer=false, autoArise=false, noClip=false, antiAfk=false, hideReward=false, hideUI=false, autoMagnet=false, autoConfirm=false, autoClose=false}
LOOPS, COLLECTED = {}, {}

function StopLoop(key)
    if LOOPS[key] then
        pcall(function() task.cancel(LOOPS[key]) end)
        LOOPS[key] = nil
    end
end

function StartLoop(key, fn)
    StopLoop(key)
    LOOPS[key] = task.spawn(fn)
end

MA = {running=false, thread=nil, killed=0, killTarget=7, autoCollect=true}
AG = {running=false, thread=nil, killed=0, collected=0, currentTarget=nil, autoCollect=true}

-- RAID STATE
RAID = {
    running     = false,
    inMap       = false,   -- true saat karakter sedang di dalam map raid
    thread      = nil,
    sukses      = 0,   -- counter raid berhasil (masuk+bunuh bos+ambil reward)
    collected   = 0,
    raidId      = 0,
    raidMapId   = 50001,
    slotIndex   = 2,       -- dapat dari EnterRaidsUpdateInfo
    _raidDone   = false,   -- true saat ChallengeRaidsSuccess/Fail fire

    statusLbl   = nil,
    suksesLbl   = nil,     -- label UI sukses (ganti killLbl/loopLbl)
    dot         = nil,
    -- Difficulty & preferred maps
    difficulty  = "easy",  -- "easy" | "medium" | "hard" | "preferred"
    preferMaps  = {},      -- set: {[mapNumber]=true} (1..18)
    runeGrades  = {},      -- [v114] Rune Map: set grade aktif {["M++"]=true, ...}
    runeEnabled = false,   -- [v114] Rune Map toggle
    diffLbl     = nil,     -- label UI difficulty
    -- Snapshot: MapId yang di-lock saat notif raid pertama kali masuk
    -- Key: "easy"/"medium"/"hard" → locked to specific mapId until restarted or diff changed
    snapshotMapId = nil,   -- mapId hasil jepretan sesuai difficulty saat ini
}
_raidOn        = false
-- Snapshot system: list map yang dijepret saat notif raid pertama masuk
-- Reset setiap 5 menit, lalu tunggu notif raid berikutnya
RAID_SNAPSHOT     = {}       -- sorted list mapId saat dijepret {mapId, ...}
_snapshotTime     = 0        -- tick() saat snapshot diambil
_SNAPSHOT_TTL     = 300      -- 5 menit dalam detik
_snapshotTaken    = false    -- sudah jepret atau belum
_raidInterrupt = false  -- true saat raid muncul & Mass Attack harus pause
local _lastBossGuid  = nil    -- guid boss terakhir untuk ExtraReward auto-claim
_siegeInterrupt = false  -- true saat siege pakai remote -> raid pause
local _gainRaidsLock = false   -- flag cegah infinite loop di hook GainRaidsRewards
_webhookEnabled = false
_webhookUrl     = ""

-- ============================================================
-- AUTO CONFIRM / AUTO CLOSE
-- Scan GUI tiap 0.3s, cari button Confirm/Close
-- Panggil callback via Activated:Fire() sebagai fallback Delta
-- ============================================================
_popupThread, _popupRunning = nil, false

local POPUP_CONFIRM_KEYS = {"confirm", "ok", "yes", "lanjut", "proceed", "accept"}
local POPUP_CLOSE_KEYS   = {"close", "cancel", "batal", "exit", "dismiss", "skip", "no"}
-- GUI yang TIDAK boleh di-auto-click apapun (online reward, daily login, dll)
local POPUP_GUI_BLACKLIST = {
    ["OnlineRewardPanel"] = true,
    ["OnlineReward"]      = true,
    ["DailyReward"]       = true,
    ["DailyLogin"]        = true,
}

-- Popup scanner hanya akan scan ScreenGui yang muncul SETELAH game load
-- dan bukan termasuk GUI persistent milik game.
-- Pendekatan: cek apakah parent ScreenGui-nya "baru muncul" (bukan persistent)
-- Persistent GUI game biasanya sudah ada sejak awal — kita skip semua yang
-- sudah ada saat script inject. List di-build saat startup.
local _existingGuis = {}
task.spawn(function()
    task.wait(2) -- tunggu game load dulu
    for _, g in ipairs(PG:GetChildren()) do
        _existingGuis[g] = true
    end
end)

function _isIgnored(obj)
    -- Skip GUI milik script kita sendiri
    local root = obj
    while root.Parent and root.Parent ~= PG do
        root = root.Parent
    end
    -- root sekarang adalah ScreenGui level pertama di bawah PG
    if root == ScreenGui then return true end
    -- Skip semua GUI yang sudah ada saat script inject (persistent game UI)
    if _existingGuis[root] then return true end
    -- Skip GUI yang ada di blacklist (online reward, daily login, dll)
    if POPUP_GUI_BLACKLIST[root.Name] then return true end
    -- Skip kalau nama root mengandung "reward" atau "login" atau "daily"
    local rn = root.Name:lower()
    if rn:find("onlinereward") or rn:find("dailyreward") or rn:find("dailylogin") then
        return true
    end
    return false
end

function _fuzzyMatch(text, keys)
    local low = text:lower():gsub("%s+","")
    for _, k in ipairs(keys) do
        if low:find(k, 1, true) then return true end
    end
    return false
end


function ScanAndClickPopup()
    for _, obj in ipairs(PG:GetDescendants()) do
        if obj:IsA("TextButton") and obj.Visible
        and obj.Text ~= "" and not _isIgnored(obj) then
            local txt = obj.Text
            if STATE.autoConfirm and _fuzzyMatch(txt, POPUP_CONFIRM_KEYS) then
                pcall(function() obj.Activated:Fire() end)
                pcall(function() obj.MouseButton1Click:Fire() end)
                return
            end
            if STATE.autoClose and _fuzzyMatch(txt, POPUP_CLOSE_KEYS) then
                pcall(function() obj.Activated:Fire() end)
                pcall(function() obj.MouseButton1Click:Fire() end)
                return
            end
        end
    end
end

function StartPopupScanner()
    _popupRunning = false
    if _popupThread then
        pcall(function() task.cancel(_popupThread) end)
        _popupThread = nil
    end
    if not STATE.autoConfirm and not STATE.autoClose then return end
    _popupRunning = true
    _popupThread = task.spawn(function()
        while _popupRunning and (STATE.autoConfirm or STATE.autoClose) do
            pcall(ScanAndClickPopup)
            task.wait(0.3)
        end
        _popupRunning = false
        _popupThread  = nil
    end)
end

-- ============================================================
-- HIDE REWARD
-- Pendekatan: permanent ChildAdded watcher di PlayerGui
-- Tidak bergantung pada ShowReward event (banyak popup muncul tanpa event itu)
-- Langsung destroy saat muncul, tanpa delay
-- ============================================================

-- Whitelist: GUI yang TIDAK boleh di-destroy meski hideReward ON
local _REWARD_GUI_WHITELIST = {
    ["ProximityPrompts"] = true,
    ["TopBar"]           = true,
    ["MobileJump"]       = true,
    ["MobileMove"]       = true,
    ["TouchGui"]         = true,
    ["TouchControlGui"]  = true,
    ["BillboardGui"]     = true,
    ["PlayerListGui"]    = true,
    ["ChatGui"]          = true,
    ["RobloxGui"]        = true,
    ["ASH_GUI"]          = true,
    ["ASH_DD"]           = true,
    -- [v80] TipsPanel DIHAPUS dari whitelist — popup reward raid, harus bisa di-close
}

function _isRewardGui(gui)
    if _existingGuis[gui] then return false end        -- sudah ada saat inject
    if gui == ScreenGui then return false end           -- GUI kita sendiri
    if _REWARD_GUI_WHITELIST[gui.Name] then return false end  -- whitelist
    return true
end

-- Track GUI reward yang sedang di-hide supaya bisa di-restore saat toggle OFF
_hiddenRewardGuis = {}

-- Nama-nama GUI reward yang sudah dikonfirmasi dari debug log
local _REWARD_GUI_NAMES = {
    ["RaidsFightPanel"] = true,
    ["TipsPanel"]       = true,  -- confirmed: bagian dari reward flow
}
local _rewardWindowOpen = false  -- masih dipakai di event hook

function _hideOneGui(gui)
    if not gui or not gui.Parent then return end
    pcall(function()
        gui.Enabled = false
        _hiddenRewardGuis[gui] = true
    end)
end

-- Scan GUI di PlayerGui yang BARU di-enable setelah event ShowReward/DropItems
-- Hanya hide GUI yang: tidak di whitelist, bukan milik kita, DAN sedang Enabled
-- Tidak menyentuh GUI yang memang sudah Enabled dari awal (persistent game UI)
local _guiEnabledAtInject = {}  -- snapshot state Enabled saat inject
task.spawn(function()
    task.wait(2.5)  -- tunggu setelah _existingGuis snapshot
    for _, g in ipairs(PG:GetChildren()) do
        pcall(function() _guiEnabledAtInject[g] = g.Enabled end)
    end
end)

function ScanAndHideExistingRewardGuis()
    for _, gui in ipairs(PG:GetChildren()) do
        -- Hanya target GUI yang namanya confirmed sebagai reward popup
        if _REWARD_GUI_NAMES[gui.Name] then
            pcall(_hideOneGui, gui)
        end
    end
end

-- Restore semua GUI yang di-hide saat toggle OFF
function RestoreHiddenRewardGuis()
    for gui, _ in pairs(_hiddenRewardGuis) do
        pcall(function()
            -- Cek Parent dulu: kalau nil berarti sudah di-destroy game, skip
            if gui and gui.Parent then
                gui.Enabled = true
            end
        end)
    end
    -- Kosongkan tabel apapun hasilnya
    _hiddenRewardGuis = {}
end

-- Semua hook hide reward — hanya aktif saat toggle ON
-- Tidak ada koneksi apapun saat script load
_rewardConns = {}  -- semua koneksi disimpan untuk bisa dilepas saat toggle OFF
_tipsPanelConn = nil
_childAddedConn = nil

-- Helper: pasang watcher Enabled pada satu GUI supaya tidak bisa di-re-enable game
-- Semua koneksi disimpan ke _rewardConns agar bisa di-disconnect saat toggle OFF
function WatchAndBlock(gui)
    if not gui or not gui.Parent then return end
    local watchConn
    watchConn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not STATE.hideReward then
            pcall(function() watchConn:Disconnect() end)
            return
        end
        if gui.Enabled then
            pcall(function() gui.Enabled = false end)
        end
    end)
    -- Simpan ke _rewardConns supaya TeardownHideRewardHooks bisa disconnect
    table.insert(_rewardConns, watchConn)
end

function SetupHideRewardHooks()
    -- ChildAdded: tangkap popup reward saat di-add ke PlayerGui
    if not _childAddedConn then
        _childAddedConn = PG.ChildAdded:Connect(function(gui)
            if not STATE.hideReward then return end
            if _REWARD_GUI_NAMES[gui.Name] then
                pcall(_hideOneGui, gui)
                WatchAndBlock(gui)
            end
        end)
    end

    -- Watch TipsPanel (persistent GUI)
    if not _tipsPanelConn then
        local tipsPanel = PG:FindFirstChild("TipsPanel")
        if tipsPanel then
            _tipsPanelConn = tipsPanel:GetPropertyChangedSignal("Enabled"):Connect(function()
                if not STATE.hideReward then
                    pcall(function() _tipsPanelConn:Disconnect() end)
                    _tipsPanelConn = nil
                    return
                end
                if tipsPanel.Enabled then
                    pcall(function()
                        tipsPanel.Enabled = false
                        _hiddenRewardGuis[tipsPanel] = true
                    end)
                end
            end)
        end
    end

    -- Hook ShowReward & DropItems remote events
    for _, remoteName in ipairs({"ShowReward", "DropItems"}) do
        local re = Remotes:FindFirstChild(remoteName)
        if re then
            local conn = re.OnClientEvent:Connect(function()
                if not STATE.hideReward then return end
                _rewardWindowOpen = true
                pcall(ScanAndHideExistingRewardGuis)
                task.delay(0.1, function()
                    if STATE.hideReward then pcall(ScanAndHideExistingRewardGuis) end
                end)
                task.delay(0.3, function()
                    if STATE.hideReward then pcall(ScanAndHideExistingRewardGuis) end
                end)
                task.delay(5, function() _rewardWindowOpen = false end)
            end)
            table.insert(_rewardConns, conn)
        end
    end
end

function TeardownHideRewardHooks()
    -- Lepas _childAddedConn
    if _childAddedConn then
        pcall(function() _childAddedConn:Disconnect() end)
        _childAddedConn = nil
    end
    -- Lepas _tipsPanelConn
    if _tipsPanelConn then
        pcall(function() _tipsPanelConn:Disconnect() end)
        _tipsPanelConn = nil
    end
    -- Lepas semua koneksi lain (termasuk WatchAndBlock connections)
    for _, conn in ipairs(_rewardConns) do
        pcall(function() conn:Disconnect() end)
    end
    _rewardConns = {}
end

-- Bersihkan dead refs tiap 10 detik
task.spawn(function()
    while true do
        task.wait(10)
        for gui, _ in pairs(_hiddenRewardGuis) do
            if not gui or not gui.Parent then
                _hiddenRewardGuis[gui] = nil
            end
        end
    end
end)

-- ============================================================
-- HIDE UI — Sembunyikan semua UI game, GUI kita tetap kelihatan
-- ============================================================
local _hiddenUIGuis = {}

-- GUI game yang tidak boleh di-hide (diperlukan untuk interaksi game)
local _UI_WHITELIST = {
    -- Image 1
    ["LoadPanel"]               = true,
    ["MountPanel"]              = true,
    ["BreathingPanel"]          = true,
    ["TowerExchangePanel"]      = true,
    ["EquipmentPanel"]          = true,
    ["LimitedTimeShopPanel"]    = true,
    ["TouchGui"]                = true,
    ["TopbarCenteredClipped"]   = true,
    ["TopbarStandardClipped"]   = true,
    ["TopbarStandard"]          = true,
    ["TopbarCentered"]          = true,
    ["MainPanel"]               = true,
    ["SwitchPanel"]             = true,
    ["ItemsPanel"]              = true,
    ["HeroListPanel"]           = true,
    ["ShopPanel"]               = true,
    ["TeleportPanel"]           = true,
    -- Image 2
    ["GemsPanel"]               = true,
    ["HeroEquipPanel"]          = true,
    ["HaloPanel"]               = true,
    ["AntiquePanel"]            = true,
    ["SettingPanel"]            = true,
    ["ReferralRewardPanel"]     = true,
    ["SeasonPassPanel"]         = true,
    ["SevenLoginPanel"]         = true,
    ["OnlineRewardPanel"]       = true,
    ["ChristmasSpinPanel"]      = true,
    ["DrawHaloPanel"]           = true,
    ["RandomShopPanel"]         = true,
    -- Image 3
    ["ProximityPrompts"]        = true,
    ["HeroEquipGradePanel"]     = true,
    ["QuirkNewPanel"]           = true,
    ["QuirkInheritPanel"]       = true,
    ["TowerWavePanel"]          = true,
    ["TowerRankPanel"]          = true,
    ["HaloExchangePanel"]       = true,
    ["AscensionPanel"]          = true,
    ["QuirkWeaponPanel"]        = true,
    -- Image 4
    ["OrnamentPanel"]           = true,
    ["PotionMergePanel"]        = true,
    ["HeroGradeUpPanel"]        = true,
    -- Tambahan sistem Roblox
    ["TipsFloatingPanel"]       = true,
    ["TipsPanel"]               = true,
    ["RaidsFightPanel"]         = true,
    ["RobloxGui"]               = true,
    ["CoreGui"]                 = true,
}

-- [v90] Hide UI: sembunyikan SEMUA UI game tanpa terkecuali
-- Kecuali ASH_GUI milik script sendiri
-- Sifatnya tidak permanen — restore saat toggle OFF
_hiddenUIGuis    = {}
_hideUIWatcher   = nil
_hideUIActive    = false

function HideAllGameUI()
    _hiddenUIGuis = {}
    -- Hide semua ScreenGui di PlayerGui kecuali ASH_GUI
    for _, gui in ipairs(PG:GetChildren()) do
        if gui == ScreenGui then continue end  -- skip GUI kita sendiri
        pcall(function()
            if gui:IsA("ScreenGui") or gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
                _hiddenUIGuis[gui] = gui.Enabled
                gui.Enabled = false
            end
        end)
    end
    -- Pasang watcher: GUI baru yang muncul saat hideUI ON langsung di-hide
    if _hideUIWatcher then pcall(function() _hideUIWatcher:Disconnect() end) end
    _hideUIActive  = true
    _hideUIWatcher = PG.ChildAdded:Connect(function(gui)
        if not _hideUIActive then return end
        if gui == ScreenGui then return end
        task.defer(function()
            pcall(function()
                if gui:IsA("ScreenGui") or gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
                    _hiddenUIGuis[gui] = gui.Enabled
                    gui.Enabled = false
                end
            end)
        end)
    end)
end

function RestoreAllGameUI()
    -- Stop watcher dulu
    _hideUIActive = false
    if _hideUIWatcher then
        pcall(function() _hideUIWatcher:Disconnect() end)
        _hideUIWatcher = nil
    end
    -- Restore semua GUI ke state sebelumnya
    for gui, wasEnabled in pairs(_hiddenUIGuis) do
        pcall(function()
            if gui and gui.Parent then
                gui.Enabled = wasEnabled
            end
        end)
    end
    _hiddenUIGuis = {}
end

-- GUI baru masuk saat hideUI ON → langsung hide (kecuali whitelist)
-- PG.ChildAdded untuk hideUI ditangani oleh SetupHideRewardHooks saat toggle ON

RAID.autoKillBoss    = false  -- toggle: teleport ke raja + auto attack sampai mati

_maStatusLbl, _noClipConn, _antiAfkThread, _antiAfkStart = nil, nil, nil, nil
local _deadG, _mOn, _agOn, _tgtThread = {}, false, false, nil
local ORIGIN_POS, _destroyerConn, _ariseConn = Vector3.new(0,0,0), nil, nil
local StatusDots, StatusLbls = {}, {}

-- ============================================================
-- MAPS
-- ============================================================
local MAPS = {}
for i = 1, 18 do
    MAPS[i] = {name="Map "..i, id=50000+i, remote=i<=4 and "Start" or "Local"}
end
MR = {selected={}, nextMapDelay=3, teleportDelay=3}

function TpMap(m)
    MR.lastMapId = m.id  -- simpan map terakhir sebelum masuk raid
    if m.remote == "Start" then
        pcall(function() RE.StartTp:FireServer({mapId=m.id}) end)
    else
        pcall(function() RE.LocalTp:FireServer({mapId=m.id}) end)
    end
end

-- ============================================================
-- SKILL KEYS
-- ============================================================
SKL = {
    Z={on=false,t=nil,label="Z"},
    X={on=false,t=nil,label="X"},
    C={on=false,t=nil,label="C"},
    V={on=false,t=nil,label="V"},
    F={on=false,t=nil,label="F"},
    type_map = {Z=1,X=2,C=3,V=4,F=5},
    key_map  = {Z=Enum.KeyCode.Z,X=Enum.KeyCode.X,C=Enum.KeyCode.C,V=Enum.KeyCode.V,F=Enum.KeyCode.F},
    ui       = {},
}
-- SKL_TYPE, SKL_KEY, SKL_UI merged into SKL table below
-- Simulasi tekan tombol keyboard via VirtualInputManager (sama seperti script lama)
function PK(k)
    pcall(function()
        VIM:SendKeyEvent(true,  k, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, k, false, game)
    end)
end

-- Referensi tombol UI skill (diisi saat panel dibuat)
-- SKL_UI merged into SKL table

function SkFireOnce(n)
    -- Simulasi tekan tombol Z/X/C/V/F langsung via VirtualInputManager
    -- Sama persis seperti player menekan tombol sendiri — tidak butuh enemyGuid
    PK(SKL.key_map[n])
end

function SkSetUI(n, on)
    local u = SKL.ui[n]
    if not u then return end
    local dc = ({Z=Color3.fromRGB(255,80,80),X=Color3.fromRGB(255,160,40),
                 C=Color3.fromRGB(80,220,120),V=Color3.fromRGB(80,180,255),
                 F=Color3.fromRGB(200,80,255)})[n]
    u.btn.BackgroundColor3 = on and Color3.fromRGB(20,10,42) or Color3.fromRGB(30,20,14)
    u.lbl.Text      = on and "ON" or "OFF"
    u.lbl.TextColor3 = on and dc or Color3.fromRGB(120,120,120)
end

function SkOn(n)
    local s = SKL[n]; if s.t then return end
    s.on = true
    SkSetUI(n, true)
    s.t = task.spawn(function()
        while s.on do
            SkFireOnce(n)
            task.wait(0.8)
        end
        s.t = nil
    end)
end

function SkOff(n)
    local s = SKL[n]; s.on = false
    SkSetUI(n, false)
    if s.t then pcall(function() task.cancel(s.t) end); s.t = nil end
end

-- ── Keyboard listener: tekan Z/X/C/V/F untuk toggle skill ──
-- Bekerja di PC (keyboard) dan Android (simulasi via Roblox touch-to-keycode)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local keyMap = {
        [Enum.KeyCode.Z] = "Z",
        [Enum.KeyCode.X] = "X",
        [Enum.KeyCode.C] = "C",
        [Enum.KeyCode.V] = "V",
        [Enum.KeyCode.F] = "F",
    }
    local n = keyMap[input.KeyCode]
    if not n then return end
    if SKL[n].on then SkOff(n) else SkOn(n) end
end)

-- ============================================================
-- ENEMY HELPERS
-- ============================================================
function GetEnemies()
    local list = {}
    local f = workspace:FindFirstChild("Enemys")
    if not f then return list end
    for _, e in ipairs(f:GetChildren()) do
        if e:IsA("Model") then
            local g   = e:GetAttribute("EnemyGuid")
            local h   = e:FindFirstChild("HumanoidRootPart")
            local hum = e:FindFirstChildOfClass("Humanoid")
            if g and h and hum and hum.Health > 0 then
                table.insert(list, {model=e, guid=g, hrp=h})
            end
        end
    end
    return list
end

function IsDead(e)
    if _deadG[e.guid] then return true end
    if not e.model or not e.model.Parent then return true end
    local h = e.model:FindFirstChildOfClass("Humanoid")
    return not h or h.Health <= 0
end

function SaveOrigin()
    local char = LP.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then ORIGIN_POS = hrp.Position end
end

function ReturnHRPToOrigin()
    local char = LP.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame = CFrame.new(ORIGIN_POS) end
end

function FireAllDamage(g, ep)
    -- RE.Click pakai InvokeServer (blocking) — pisah ke thread sendiri
    -- supaya tidak delay remote lain
    if RE.Click then
        task.spawn(function()
            pcall(function() RE.Click:InvokeServer({enemyGuid=g, enemyPos=ep}) end)
        end)
    end
    -- RE.Atk: serangan karakter utama
    if RE.Atk then
        pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
    end
    -- Hero: fire satu per satu dengan jeda kecil supaya server tidak throttle
    for _, hGuid in ipairs(HERO_GUIDS) do
        if RE.HeroUseSkill then
            -- Hanya fire attackType 1 — cukup untuk trigger damage
            -- attackType 2 & 3 hanya difire kalau attackType 1 sudah confirmed
            pcall(function() RE.HeroUseSkill:FireServer({
                heroGuid   = hGuid,
                attackType = 1,
                userId     = MY_USER_ID,
                enemyGuid  = g,
            }) end)
        elseif RE.HeroSkill then
            -- Fallback kalau HeroUseSkill tidak ada
            pcall(function() RE.HeroSkill:FireServer({
                heroGuid=hGuid, enemyGuid=g, skillType=1, masterId=MY_USER_ID
            }) end)
        end
    end
end

function FireHeroRemotes(enemyGuid, enemyPos)
    if not RE.HeroMove then return end
    pcall(function()
        RE.HeroMove:FireServer({
            attackTarget      = enemyGuid,
            userId            = MY_USER_ID,
            heroTagetPosInfos = {},
        })
    end)
end

if RE.Death then
    RE.Death.OnClientEvent:Connect(function(d)
        if not d then return end
        local g = d.enemyGuid or d.guid
        if g then
            _deadG[g] = true
            if MA.running then MA.killed = MA.killed + 1 end
            if AG.running then AG.killed = AG.killed + 1 end
            -- [v50] gabung counter siege di sini, hapus listener kedua di bawah
            if SIEGE and SIEGE.running then
                SIEGE.killed = SIEGE.killed + 1
                if SiegeCounterUpdate then SiegeCounterUpdate() end
            end
        end
    end)
end

-- ============================================================
-- DESTROY WORKER
-- ============================================================
function StartDestroyWorker(checkFn)
    task.spawn(function()
        local collected = {}
        while checkFn() do
            local golds = workspace:FindFirstChild("Golds")
            if golds then
                for _, obj in ipairs(golds:GetChildren()) do
                    if not checkFn() then break end
                    local guid = obj:GetAttribute("GUID")
                    if guid and not collected[guid] then
                        collected[guid] = true
                        pcall(function() RE.CollectItem:InvokeServer(guid) end)
                        if not (STATE and STATE.hideReward) then pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end) end
                        if AG.running then AG.collected = AG.collected + 1 end
                        if MA.running then MA.collected = (MA.collected or 0) + 1 end
                        task.wait(0.05)
                    end
                end
            end
            task.wait(0.25)
        end
    end)
end

-- ============================================================
-- ATTACK LOOPS
-- ============================================================
function AttackLoop_Mass(onStatus)
    _deadG = {}
    local start, wt = MA.killed, 0
    while wt < 6 and MA.running do
        if #GetEnemies() > 0 then break end
        if onStatus then onStatus("Tidak ada musuh ("..math.floor(6-wt).."s)") end
        task.wait(0.4); wt = wt + 0.4
    end
    if not MA.running then return false end
    if #GetEnemies() == 0 then
        if onStatus then onStatus("Map kosong, skip...") end; return true
    end
    local emptyT, lastKill, stuckT = 0, MA.killed, 0
    while MA.running do
        local isAll = (MA.killTarget == 0)
        local here  = MA.killed - start
        local alive = 0
        for _, e in ipairs(GetEnemies()) do
            if not IsDead(e) then alive = alive + 1 end
        end
        if isAll then
            if alive == 0 then
                emptyT = emptyT + 0.08
                if emptyT >= 1.5 then return true end
                task.wait(0.08); continue
            end
            emptyT = 0
            if onStatus then onStatus("Kill All: "..alive.." sisa") end
        else
            if here >= MA.killTarget then return true end
            if onStatus then onStatus(alive.." hidup  "..here.."/"..MA.killTarget) end
        end
        if alive == 1 then
            if onStatus then onStatus("Sisa 1, skip map...") end; return true
        end
        if MA.killed > lastKill then
            lastKill = MA.killed; stuckT = 0
        else
            stuckT = stuckT + 0.08
            if stuckT >= 1.0 then
                if onStatus then onStatus("Stuck, skip map...") end; return true
            end
        end
        -- Cek interrupt dari Auto Raid atau Auto Siege sebelum lanjut attack
        if _raidInterrupt or _siegeInterrupt then return "interrupted" end

        for _, e in ipairs(GetEnemies()) do
            if not IsDead(e) then
                local hrp = e.model and e.model:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local g, p = e.guid, hrp.Position
                    task.spawn(function()
                        FireAllDamage(g, p)
                        FireHeroRemotes(g, p)
                    end)
                end
            end
        end
        task.wait(0.08)
    end
    return false
end

-- Cari musuh terdekat dari posisi karakter utama
function GetNearestEnemy()
    local char = LP.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local myPos = hrp.Position
    local nearest, nearestDist = nil, math.huge
    for _, e in ipairs(GetEnemies()) do
        if not IsDead(e) and e.hrp then
            local d = (e.hrp.Position - myPos).Magnitude
            if d < nearestDist then
                nearestDist = d
                nearest = e
            end
        end
    end
    return nearest
end

-- Pilih musuh secara random dari daftar yang masih hidup
function GetRandomEnemy()
    local alive = {}
    for _, e in ipairs(GetEnemies()) do
        if not IsDead(e) and e.hrp then
            table.insert(alive, e)
        end
    end
    if #alive == 0 then return nil end
    return alive[math.random(1, #alive)]
end

function TpToEnemy(tgt)
    if not tgt or not tgt.hrp then return end
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    -- Raycast ke bawah dari posisi musuh untuk cari lantai aman
    local origin = tgt.hrp.Position + Vector3.new(0, 5, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ex = {}
    if LP.Character then table.insert(ex, LP.Character) end
    local ef = workspace:FindFirstChild("Enemys")
    if ef then table.insert(ex, ef) end
    params.FilterDescendantsInstances = ex
    local result = workspace:Raycast(origin, Vector3.new(0, -50, 0), params)
    local safePos = result and (result.Position + Vector3.new(0, 3, 0)) or (tgt.hrp.Position + Vector3.new(0, 3, 0))
    hrp.CFrame = CFrame.new(safePos)
end

function AttackLoop_Goyang(onStatus)
    SaveOrigin()
    local currentTgt = nil

    -- Mulai: TP ke musuh terdekat
    local first = GetNearestEnemy()
    if first then
        currentTgt = first
        TpToEnemy(currentTgt)
        FireHeroRemotes(currentTgt.guid, currentTgt.hrp.Position)
        if onStatus then onStatus("Goyang → ["..currentTgt.model.Name.."] (terdekat)  Kill: "..AG.killed) end
    end

    while AG.running do
        -- Target mati / habis → cari random berikutnya
        if not currentTgt or IsDead(currentTgt) or not currentTgt.model.Parent then
            local waited = false
            while AG.running do
                local next = GetRandomEnemy()
                if next then
                    if waited then
                        if onStatus then onStatus("Musuh muncul! Mulai dalam 2s...") end
                        task.wait(2)
                        if not AG.running then break end
                    end
                    currentTgt = next
                    TpToEnemy(currentTgt)
                    FireHeroRemotes(currentTgt.guid, currentTgt.hrp.Position)
                    if onStatus then onStatus("Goyang → ["..currentTgt.model.Name.."]  Kill: "..AG.killed) end
                    break
                else
                    if onStatus then onStatus("Menunggu musuh muncul...") end
                    waited = true
                    task.wait(0.5)
                end
            end
            if not AG.running then break end
        end

        -- Serang musuh saat ini
        if currentTgt and not IsDead(currentTgt) and currentTgt.model.Parent then
            local pos = currentTgt.hrp and currentTgt.hrp.Position or Vector3.new(0,0,0)
            FireAllDamage(currentTgt.guid, pos)
        end

        task.wait()
    end

    ReturnHRPToOrigin()
    return false
end

function RunAG(onStatus, onDone)
    AG.running = true; AG.killed = 0; AG.collected = 0
    StartDestroyWorker(function() return AG.running end)
    AG.thread = task.spawn(function()
        AttackLoop_Goyang(onStatus)
        AG.running = false
        ReturnHRPToOrigin()
        if onDone then onDone() end
    end)
end


-- ============================================================
-- AUTO FUNCTIONS
-- ============================================================
function DoAutoCollect(on)
    StopLoop("collect"); COLLECTED = {}
    if not on then return end
    StartLoop("collect", function()
        while STATE.autoCollect do
            local golds = workspace:FindFirstChild("Golds")
            if golds then
                for _, obj in ipairs(golds:GetChildren()) do
                    if not STATE.autoCollect then break end
                    local guid = obj:GetAttribute("GUID")
                    if guid and not COLLECTED[guid] then
                        COLLECTED[guid] = true
                        pcall(function() RE.CollectItem:InvokeServer(guid) end)
                        if not (STATE and STATE.hideReward) then pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end) end
                        task.wait(0.05)
                    end
                end
            end
            task.wait(0.25)
        end
    end)
end

local _destroyerConn = nil
function DoAutoDestroyer(on)
    StopLoop("destroyer")
    if _destroyerConn then _destroyerConn:Disconnect(); _destroyerConn = nil end
    if not on then return end
    _destroyerConn = workspace.DescendantAdded:Connect(function(obj)
        if not STATE.autoDestroyer then return end
        task.wait(0.1)
        local guid; pcall(function() guid = obj:GetAttribute("GUID") end)
        if not (STATE and STATE.hideReward) then if guid then pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end) end end
    end)
end

local _ariseConn = nil
function DoAutoArise(on)
    StopLoop("arise")
    if _ariseConn then _ariseConn:Disconnect(); _ariseConn = nil end
    if not on then return end
    _ariseConn = workspace.DescendantAdded:Connect(function(obj)
        if not STATE.autoArise then return end
        task.wait(0.1)
        local guid; pcall(function() guid = obj:GetAttribute("GUID") end)
        if not (STATE and STATE.hideReward) then if guid then pcall(function() RE.ExtraReward:FireServer({isSell=false, isAuto=false, guid=guid}) end) end end
    end)
end

-- ============================================================
-- AUTO MAGNET — collect gold & item saat jatuh (real-time)
-- ============================================================
-- Note: _magnetConn & _magnetSeen di outer scope supaya DoAutoMagnet
-- bisa di-akses dari toggle panel MAIN
local _magnetConn   = nil
local _magnetSeen   = {}

local _MAGNET_FOLDERS = {"Golds", "Items", "Drops", "Rewards"}

function DoAutoMagnet(on)
    if _magnetConn then _magnetConn:Disconnect(); _magnetConn = nil end
    _magnetSeen = {}
    if not on then return end

    -- Collect semua yang sudah ada di workspace sekarang
    task.spawn(function()
        for _, folderName in ipairs(_MAGNET_FOLDERS) do
            local folder = workspace:FindFirstChild(folderName)
            if not folder then continue end
            for _, obj in ipairs(folder:GetChildren()) do
                if not STATE.autoMagnet then return end
                local guid; pcall(function() guid = obj:GetAttribute("GUID") end)
                if guid and not _magnetSeen[guid] then
                    _magnetSeen[guid] = true
                    pcall(function() RE.CollectItem:InvokeServer(guid) end)
                    task.wait(0.03)
                end
            end
        end
    end)

    -- Polling loop sebagai backup: scan ulang tiap 0.5s
    -- Ini untuk catch gold yang mungkin miss oleh DescendantAdded
    task.spawn(function()
        while STATE.autoMagnet do
            for _, folderName in ipairs(_MAGNET_FOLDERS) do
                local folder = workspace:FindFirstChild(folderName)
                if folder then
                    for _, obj in ipairs(folder:GetChildren()) do
                        if not STATE.autoMagnet then break end
                        local guid; pcall(function() guid = obj:GetAttribute("GUID") end)
                        if guid and not _magnetSeen[guid] then
                            _magnetSeen[guid] = true
                            pcall(function() RE.CollectItem:InvokeServer(guid) end)
                        end
                    end
                end
            end
            task.wait(0.5)
        end
    end)

    -- Watch: langsung collect saat ada item/gold baru jatuh
    _magnetConn = workspace.DescendantAdded:Connect(function(obj)
        if not STATE.autoMagnet then return end
        task.delay(0.08, function()
            if not STATE.autoMagnet then return end

            local guid; pcall(function() guid = obj:GetAttribute("GUID") end)
            if not guid then return end
            local parent = obj.Parent
            if not parent then return end
            local isDropFolder = false
            for _, fn in ipairs(_MAGNET_FOLDERS) do
                if parent.Name == fn and parent.Parent == workspace then
                    isDropFolder = true; break
                end
            end
            if not isDropFolder then return end
            if _magnetSeen[guid] then return end
            _magnetSeen[guid] = true
            pcall(function() RE.CollectItem:InvokeServer(guid) end)
        end)
    end)
end

function RefreshStatus()
    local map = {
        collect   = {STATE.autoCollect,   "Auto Collect Gold"},
        destroyer = {STATE.autoDestroyer, "Auto Destroyer"},
        arise     = {STATE.autoArise,     "Auto Arise"},
        noClip    = {STATE.noClip,        "No Clip"},
        antiAfk   = {STATE.antiAfk,       "Anti AFK"},
        magnet    = {STATE.autoMagnet,    "Auto Magnet"},
    }
    for key, data in pairs(map) do
        local active, label = data[1], data[2]
        if StatusDots[key] then
            StatusDots[key].BackgroundColor3 = active and Color3.fromRGB(80,220,80) or Color3.fromRGB(100,100,100)
        end
        if StatusLbls[key] then
            StatusLbls[key].Text = label..(active and "  —  ON" or "  —  OFF")
            StatusLbls[key].TextColor3 = active and C.ACC2 or C.TXT2
        end
    end
end

-- Pause Mass Attack dan tunggu sampai raid/siege selesai
function WaitRaidDone()
    local t = 0
    while (_raidInterrupt or _siegeInterrupt) and MA.running do
        t = t + 0.5
        local reason = _raidInterrupt and "Auto Raid" or "Auto Siege"
        if _maStatusLbl then
            _maStatusLbl.Text = "⏸ Pause ("..reason..") — "..math.floor(t).."s"
            _maStatusLbl.TextColor3 = Color3.fromRGB(255,140,0)
        end
        task.wait(0.5)
    end
    if MA.running then task.wait(1.5) end
    if _maStatusLbl and MA.running then
        _maStatusLbl.Text = "▶ Lanjut setelah pause..."
        _maStatusLbl.TextColor3 = Color3.fromRGB(100,200,255)
    end
end

-- Tunggu siege selesai dengan watchdog safety
-- Auto reset _siegeInterrupt kalau Siege tidak running atau max 30 detik
function WaitSiegeDone()
    local waited = 0
    while _siegeInterrupt do
        task.wait(0.5)
        waited = waited + 0.5
        if not SIEGE.running then
            _siegeInterrupt = false; break
        end
        if waited >= 30 then
            _siegeInterrupt = false; break
        end
    end
end

function DoMassAttack(on)
    if on then
        _mOn = true
        MA.running = true
        MA.killed  = 0
        MA.collected = 0
        StartDestroyWorker(function() return MA.running end)
        MA.thread = task.spawn(function()
            local _maStart = os.time()
            local function maStatus(msg, col)
                if _maStatusLbl then
                    local dur = os.time() - _maStart
                    local ts  = string.format("%02d:%02d:%02d", math.floor(dur/3600), math.floor(dur/60)%60, dur%60)
                    _maStatusLbl.Text = "["..ts.."] "..msg
                    _maStatusLbl.TextColor3 = col or C.ACC2
                end
            end
            while MA.running do
                if _raidInterrupt then WaitRaidDone() end
                if not MA.running then break end

                local mapsToUse = {}
                for i = 1, 18 do if MR.selected[i] then table.insert(mapsToUse, MAPS[i]) end end

                if #mapsToUse == 0 then
                    local cont = AttackLoop_Mass(function(msg)
                        maStatus(msg)
                    end)
                    if cont == "interrupted" then
                        WaitRaidDone()
                    elseif not cont or not MA.running then
                        break
                    end
                    if _raidInterrupt then WaitRaidDone() end
                    task.wait(MR.nextMapDelay)
                else
                    for _, m in ipairs(mapsToUse) do
                        if not MA.running then break end
                        if _raidInterrupt then WaitRaidDone() end
                        if not MA.running then break end
                        if _raidInterrupt then continue end
                        maStatus("🚀 TP ke "..m.name.."...", Color3.fromRGB(180,220,255))
                        TpMap(m)
                        task.wait(MR.teleportDelay)
                        if not MA.running then break end
                        local cont = AttackLoop_Mass(function(msg)
                            maStatus("["..m.name.."] "..msg)
                        end)
                        if cont == "interrupted" then
                            WaitRaidDone()
                        elseif not cont or not MA.running then
                            break
                        end
                        if _raidInterrupt then WaitRaidDone() end
                        if not MA.running then break end
                        maStatus("✅ Selesai "..m.name.." — pindah map...", Color3.fromRGB(100,255,150))
                        task.wait(MR.nextMapDelay)
                    end
                end
            end
            _mOn = false
            MA.running = false
            if _maStatusLbl then
                _maStatusLbl.Text = "⏹ Selesai"
                _maStatusLbl.TextColor3 = C.DIM
            end
        end)
    else
        _mOn = false; MA.running = false
        if MA.thread then pcall(function() task.cancel(MA.thread) end); MA.thread = nil end
        if _maStatusLbl then _maStatusLbl.Text = "Idle" end
    end
end

function DoRejoin()
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end)
end

-- ============================================================
-- QUIRK DATA
-- ============================================================
-- Hero: hanya tampilkan quirk tier tinggi per slot, max pilih 3
QUIRK_LIST_PER_SLOT = {
    -- Slot 1 (6 pilihan, max 3)
    {
        {id=99013,name="Midas Touch"},
        {id=99014,name="Hyper Sprint"},
        {id=99015,name="Time Skipper"},
        {id=99016,name="Cosmic Luck"},
        {id=99017,name="Destiny Rewrite"},
        {id=99018,name="Final Judgment"},
    },
    -- Slot 2 (6 pilihan, max 3)
    {
        {id=99031,name="Resource Conqueror"},
        {id=99032,name="Elemental Overload"},
        {id=99033,name="Crimson Executioner"},
        {id=99034,name="God's Gift"},
        {id=99035,name="Apocalypse Carnival"},
        {id=99036,name="Divine Judgment"},
    },
    -- Slot 3 (5 pilihan, max 3)
    {
        {id=99049,name="Slayer's Instinct"},
        {id=99050,name="Harbinger of Ruin"},
        {id=99052,name="Godslayer's Fury"},
        {id=99053,name="Deicide's Endgame"},
        {id=99054,name="Final Arbiter"},
    },
}
MAX_PER_SLOT = 3

QUIRK_MAP = {}
for _, list in ipairs(QUIRK_LIST_PER_SLOT) do
    for _, q in ipairs(list) do QUIRK_MAP[q.id] = q.name end
end

-- Weapon: hanya tampilkan quirk tier tinggi per slot, max pilih 3
W_QUIRK_LIST_PER_SLOT = {
    -- Slot 1 (6 pilihan, max 3)
    {
        {id=99067,name="Celestial Onslaught"},
        {id=99068,name="Lucky Scavenger"},
        {id=99069,name="Titan's Wrath"},
        {id=99070,name="Omnipotent Benefactor"},
        {id=99071,name="Archangel's Judgment"},
        {id=99072,name="Avatar of Destruction"},
    },
    -- Slot 2 (6 pilihan, max 3)
    {
        {id=99085,name="Celestial Onslaught"},
        {id=99086,name="Lucky Scavenger"},
        {id=99087,name="Titan's Wrath"},
        {id=99088,name="Omnipotent Benefactor"},
        {id=99089,name="Archangel's Judgment"},
        {id=99090,name="Avatar of Destruction"},
    },
    -- Slot 3 (6 pilihan, max 3)
    {
        {id=99103,name="Celestial Onslaught"},
        {id=99104,name="Lucky Scavenger"},
        {id=99105,name="Titan's Wrath"},
        {id=99106,name="Omnipotent Benefactor"},
        {id=99107,name="Archangel's Judgment"},
        {id=99108,name="Avatar of Destruction"},
    },
}
W_MAX_PER_SLOT = 3

W_QUIRK_MAP = {}
for _, list in ipairs(W_QUIRK_LIST_PER_SLOT) do
    for _, q in ipairs(list) do W_QUIRK_MAP[q.id] = q.name end
end

local PG_MACHINE_NAMES = {"R-Pet Gear", "Y-Pet Gear", "B-Pet Gear"}
local PG_DRAW_IDS      = {980001, 980002, 980003}

local PG_GRADES_PER_MACHINE = {
    {
        {id=990001, name="E"},  {id=990002, name="D"},  {id=990003, name="C"},
        {id=990004, name="B"},  {id=990005, name="A"},  {id=990006, name="S"},
        {id=990007, name="SS"}, {id=990008, name="G"},  {id=990009, name="N"},
        {id=990010, name="M"},
    },
    {
        {id=990011, name="E"},  {id=990012, name="D"},  {id=990013, name="C"},
        {id=990014, name="B"},  {id=990015, name="A"},  {id=990016, name="S"},
        {id=990017, name="SS"}, {id=990018, name="G"},  {id=990019, name="N"},
        {id=990020, name="M"},
    },
    {
        {id=990021, name="E"},  {id=990022, name="D"},  {id=990023, name="C"},
        {id=990024, name="B"},  {id=990025, name="A"},  {id=990026, name="S"},
        {id=990027, name="SS"}, {id=990028, name="G"},  {id=990029, name="N"},
        {id=990030, name="M"},
    },
}

local PG_GRADE_MAP = {}
for _, list in ipairs(PG_GRADES_PER_MACHINE) do
    for _, g in ipairs(list) do PG_GRADE_MAP[g.id] = g.name end
end

-- ============================================================
PGR = {
    guids       = {"","",""},
    captured    = {false,false,false},
    targets     = {{},{},{}},
    running     = {false,false,false},
    statLbls    = {nil,nil,nil},
    dotRefs     = {nil,nil,nil},
    sumLbls     = {nil,nil,nil},
    attemptLbls = {nil,nil,nil},
    lastLbls    = {nil,nil,nil},
    toggleBtns  = {nil,nil,nil},
    toggleKnobs = {nil,nil,nil},
    enOnFlags   = {false,false,false},
}

local HALO_NAMES   = {"Bronze Halo", "Gold Halo", "Diamond Halo"}
local HALO_DRAW_ID = {1, 2, 3}
HALO = {
    running    = {false, false, false},
    statLbls   = {nil, nil, nil},
    dotRefs    = {nil, nil, nil},
    attemptLbls= {nil, nil, nil},
    toggleBtns = {nil, nil, nil},
    toggleKnobs= {nil, nil, nil},
    enOnFlags  = {false, false, false},
}

-- ── HALO LOOP THREADS ──
local HALO_THREADS = {nil, nil, nil}

DoAutoRollHalo = function(hi, on)
    -- Stop loop lama kalau ada
    if HALO_THREADS[hi] then
        task.cancel(HALO_THREADS[hi])
        HALO_THREADS[hi] = nil
    end

    HALO.running[hi] = on

    local function setStatus(txt, col)
        if HALO.statLbls[hi] then
            HALO.statLbls[hi].Text = txt
            HALO.statLbls[hi].TextColor3 = col or Color3.fromRGB(160,148,135)
        end
        if HALO.dotRefs[hi] then
            HALO.dotRefs[hi].BackgroundColor3 = on and Color3.fromRGB(80,220,80) or Color3.fromRGB(100,100,100)
        end
    end

    if not on then
        setStatus("⏹ Idle", Color3.fromRGB(160,148,135))
        return
    end

    local drawId = HALO_DRAW_ID[hi]

    HALO_THREADS[hi] = task.spawn(function()
        local attempt = 0
        while HALO.running[hi] do
            attempt = attempt + 1
            if HALO.attemptLbls[hi] then
                HALO.attemptLbls[hi].Text = "Attempt: "..attempt
            end
            setStatus("🎲 Rolling #"..attempt.."...", Color3.fromRGB(255,200,60))

            local ok, res = pcall(function()
                return RE.RerollHalo:InvokeServer(drawId)
            end)

            if not ok then
                setStatus("⚠ Error — retry...", Color3.fromRGB(255,100,60))
                task.wait(1)
            else
                setStatus("✅ Roll #"..attempt.." selesai", Color3.fromRGB(80,220,80))
                task.wait(0.05)
            end
        end
        setStatus("⏹ Idle", Color3.fromRGB(160,148,135))
    end)
end

-- ============================================================
-- ORNAMENT DATA  (di-wrap dalam 1 tabel untuk hemat local slot)
-- ============================================================
_ASH_ORN = {}

_ASH_ORN.MACHINES = {
    {name="Headdress",            machineId=400001},
    {name="Ornament Machine",     machineId=400002},
    {name="Wealth Blessing",      machineId=400003},
    {name="Shadowhunter Blessing",machineId=400004},
    {name="Primordial Blessing",  machineId=400005},
    {name="Monarch Power",        machineId=400006},
}

_ASH_ORN.QUIRK_LIST    = {}
_ASH_ORN.QUIRK_MAP     = {}
_ASH_ORN.emptyHintRefs = {}   -- ref ke emptyHint label per mesin
for i = 1, #_ASH_ORN.MACHINES do
    _ASH_ORN.QUIRK_LIST[i] = {}
end


_ASH_ORN.STATE = {
    running     = {false,false,false,false,false,false},
    targets     = {{},{},{},{},{},{}},
    statLbls    = {nil,nil,nil,nil,nil,nil},
    dotRefs     = {nil,nil,nil,nil,nil,nil},
    attemptLbls = {nil,nil,nil,nil,nil,nil},
    lastLbls    = {nil,nil,nil,nil,nil,nil},
    sumLbls     = {nil,nil,nil,nil,nil,nil},
    toggleBtns  = {nil,nil,nil,nil,nil,nil},
    toggleKnobs = {nil,nil,nil,nil,nil,nil},
    enOnFlags   = {false,false,false,false,false,false},
}
ORN = _ASH_ORN.STATE

function _ASH_ORN.AddQuirk(machineIdx, quirkId, quirkName)
    if not machineIdx or not quirkId then return end
    local list = _ASH_ORN.QUIRK_LIST[machineIdx]
    if not list then return end
    for _, q in ipairs(list) do
        if q.id == quirkId then
            if quirkName and not quirkName:find("^ID:") then q.name = quirkName end
            return
        end
    end
    table.insert(list, {id=quirkId, name=quirkName or ("ID:"..quirkId)})
    if not _ASH_ORN.QUIRK_MAP[quirkId] then _ASH_ORN.QUIRK_MAP[quirkId] = quirkName or ("ID:"..quirkId) end
end

function _ASH_ORN.GetSummary(mi)
    local names = {}
    for id in pairs(ORN.targets[mi]) do
        table.insert(names, _ASH_ORN.QUIRK_MAP[id] or ("ID:"..tostring(id)))
    end
    table.sort(names)
    if #names == 0 then return "--" end
    if #names == 1 then return names[1] end
    if #names <= 2 then return table.concat(names, ", ") end
    return names[1]..", "..names[2].." +"..(#names-2).." lagi"
end

function _ASH_ORN.SetToggleOff(mi)
    ORN.enOnFlags[mi] = false
    if ORN.toggleBtns[mi]  then ORN.toggleBtns[mi].BackgroundColor3  = Color3.fromRGB(60,60,60) end
    if ORN.toggleKnobs[mi] then ORN.toggleKnobs[mi].Position = UDim2.new(0,2,0.5,-9) end
end

function _ASH_ORN.DoRoll(mi, on)
    local key = "ornroll"..mi
    ORN.running[mi] = false
    StopLoop(key)

    function setStatus(dot, txt, col)
        if ORN.dotRefs[mi]  then ORN.dotRefs[mi].BackgroundColor3 = dot end
        if ORN.statLbls[mi] then ORN.statLbls[mi].Text = txt; ORN.statLbls[mi].TextColor3 = col end
    end

    if not on then
        setStatus(Color3.fromRGB(100,100,100), "⏹ Idle", C.TXT2)
        if ORN.attemptLbls[mi] then ORN.attemptLbls[mi].Text = "Attempt: —" end
        if ORN.lastLbls[mi]    then ORN.lastLbls[mi].Text    = "Last: —" end
        return
    end

    ORN.running[mi] = true

    LOOPS[key] = task.spawn(function()
        local attempt = 0
        setStatus(Color3.fromRGB(255,200,60), "⟳ Memulai roll...", Color3.fromRGB(255,200,60))
        local mInfo = _ASH_ORN.MACHINES[mi]

        while ORN.running[mi] do
            if not RE.RerollOrnament then
                RE.RerollOrnament = Remotes:FindFirstChild("RerollOrnament")
            end
            if not RE.RerollOrnament then
                setStatus(Color3.fromRGB(255,80,80), "⚠ Remote RerollOrnament tidak ditemukan!", Color3.fromRGB(255,80,80))
                task.wait(2); continue
            end
            attempt = attempt + 1
            setStatus(Color3.fromRGB(255,160,30), "🔄 Roll #"..attempt, C.ACC2)
            if ORN.attemptLbls[mi] then
                ORN.attemptLbls[mi].Text = "Attempt: #"..attempt
                ORN.attemptLbls[mi].TextColor3 = C.TXT2
            end

            local ok, res = pcall(function()
                return RE.RerollOrnament:InvokeServer({machineId=mInfo.machineId, isAuto=false})
            end)
            if not ok then
                setStatus(Color3.fromRGB(255,80,80), "⚠ Error remote (#"..attempt..")", Color3.fromRGB(255,80,80))
                task.wait(0.5); continue
            end

            local gotId   = nil
            local gotName = "?"
            if type(res) == "table" then
                -- ── PRIORITY 1: Format baru ornament { ornamentIds={[1]=410003}, count=1 } ──
                if type(res.ornamentIds) == "table" then
                    local oid = res.ornamentIds[1]
                    if type(oid) == "number" and oid > 0 then
                        gotId   = oid
                        gotName = _ASH_ORN.QUIRK_MAP[oid] or ("ID:"..tostring(oid))
                        _ASH_ORN.AddQuirk(mi, oid, gotName)
                    end
                end
                -- ── PRIORITY 2: Scan nested ornamentIds di sub-table ──
                if not gotId then
                    function ScanOrnamentIds(tbl, depth)
                        if depth > 4 or type(tbl) ~= "table" or gotId then return end
                        if type(tbl.ornamentIds) == "table" then
                            local oid = tbl.ornamentIds[1]
                            if type(oid) == "number" and oid > 0 then
                                gotId   = oid
                                gotName = _ASH_ORN.QUIRK_MAP[oid] or ("ID:"..tostring(oid))
                                _ASH_ORN.AddQuirk(mi, oid, gotName)
                                return
                            end
                        end
                        for _, v in pairs(tbl) do
                            if type(v) == "table" then ScanOrnamentIds(v, depth+1) end
                        end
                    end
                    ScanOrnamentIds(res, 0)
                end
                -- ── PRIORITY 3: Fallback scan generic quirkId/resultId/id ──
                if not gotId then
                    function ScanAndLearn(tbl, depth)
                        if depth > 5 or type(tbl) ~= "table" or gotId then return end
                        local id   = tbl.quirkId or tbl.finalResultId or tbl.resultId or tbl.ornamentId
                        local name = tbl.quirkName or tbl.name or tbl.Name or tbl.title or tbl.displayName
                        if type(id) == "number" and id > 0 then
                            if type(name) == "string" and #name > 0 and not name:find("^ID:") then
                                _ASH_ORN.AddQuirk(mi, id, name)
                                if not gotId then gotId = id; gotName = name end
                            elseif not gotId then
                                gotId   = id
                                gotName = _ASH_ORN.QUIRK_MAP[id] or ("ID:"..tostring(id))
                            end
                        end
                        for _, v in pairs(tbl) do
                            if type(v) == "table" then ScanAndLearn(v, depth+1) end
                        end
                    end
                    ScanAndLearn(res, 0)
                end
                -- ── PRIORITY 4: Last resort — ambil angka pertama yang masuk akal (4xxxxx) ──
                if not gotId then
                    function ScanNum(tbl, depth)
                        if depth > 4 or gotId then return end
                        for _, v in pairs(tbl) do
                            if type(v) == "number" and v >= 400000 and v < 500000 and not gotId then
                                gotId   = v
                                gotName = _ASH_ORN.QUIRK_MAP[v] or ("ID:"..tostring(v))
                                _ASH_ORN.AddQuirk(mi, v, gotName)
                            elseif type(v) == "table" then ScanNum(v, depth+1) end
                        end
                    end
                    ScanNum(res, 0)
                end
            elseif res == false or res == nil then
                task.wait(0.5); continue
            end

            if ORN.lastLbls[mi] then
                ORN.lastLbls[mi].Text = "Last: "..gotName
                ORN.lastLbls[mi].TextColor3 = Color3.fromRGB(180,180,180)
            end

            task.wait(0.1)
        end
        setStatus(Color3.fromRGB(100,100,100), "⏹ Dihentikan ("..attempt.."x roll)", C.TXT2)
        if ORN.attemptLbls[mi] then
            ORN.attemptLbls[mi].Text = "Attempt: "..attempt.."x"
            ORN.attemptLbls[mi].TextColor3 = C.TXT2
        end
    end)
end


_spyLog        = {}
_layer0Active  = false
_HR_RPT        = nil   -- laporan hero fastroll
_WR_RPT        = nil   -- laporan weapon fastroll
_watcherConns  = {}

-- ============================================================
-- DD LAYER
-- ============================================================
DDLayer = Frame(ScreenGui, C.BLACK, UDim2.new(1,0,1,0))
DDLayer.BackgroundTransparency = 1; DDLayer.ZIndex = 9998; DDLayer.Visible = false
DDLayer.Active = false
DDLayer.Name = "ASH_DD"

_activeDDClose = nil
-- Forward declare AutoRoll functions used in panels (global, cross-scope)
DoAutoRollHero        = nil
DoAutoRollWeapon      = nil
DoAutoRollPetGear     = nil
InitAllCaptureLayers  = nil

-- CloseActiveDD: tutup dropdown yang sedang terbuka
CloseActiveDD = function()
    if _activeDDClose then _activeDDClose(); _activeDDClose = nil end
end

-- DDLayer: klik di luar dropdown → tutup
DDLayer.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        task.defer(CloseActiveDD)
    end
end)



-- DROPDOWN HELPER (shared)
-- ============================================================
MakeGenericDropdown = function(params)
    local ddBtn     = params.ddBtn
    local list      = params.list
    local maxSel    = params.maxSel or 3
    local selTable  = params.selTable
    local onRefresh = params.onRefresh
    local summaryLbl= params.summaryLbl
    local qMapRef   = params.quirkMapRef or {}

    ddBtn.MouseButton1Click:Connect(function()
        CloseActiveDD()
        local absPos  = ddBtn.AbsolutePosition
        local absSize = ddBtn.AbsoluteSize
        local ITEM_H  = 28
        local contentH= #list * (ITEM_H + 2) + 10
        local scrollH = math.min(contentH, _isSmallScreen and 170 or 200)
        local popupW  = absSize.X + 30
        local HEADER_H= 32

        local popup = Instance.new("Frame")
        popup.Parent = DDLayer; popup.BackgroundColor3 = C.DD_BG; popup.BorderSizePixel = 0
        popup.Size = UDim2.new(0, popupW, 0, HEADER_H + scrollH)
        popup.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 3)
        popup.ZIndex = 9999; popup.ClipsDescendants = true
        Corner(popup, 8); Stroke(popup, C.BORD2, 1, 0.2)

        local hdr = Frame(popup, Color3.fromRGB(90,30,0), UDim2.new(1,0,0,HEADER_H)); hdr.ZIndex = 9999
        local countLbl = Label(hdr, "0/"..maxSel.." dipilih", 10.5, C.ACC2, Enum.Font.GothamBold)
        countLbl.Size = UDim2.new(0.6,0,1,0); countLbl.Position = UDim2.new(0,8,0,0); countLbl.ZIndex = 9999
        local clrBtn = Btn(hdr, Color3.fromRGB(180,50,50), UDim2.new(0,50,0,20))
        clrBtn.Position = UDim2.new(1,-56,0.5,-10); Corner(clrBtn,5); clrBtn.ZIndex = 9999
        local cL = Label(clrBtn,"Clear",10,Color3.fromRGB(255,255,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        cL.Size = UDim2.new(1,0,1,0); cL.ZIndex = 9999

        local sf = Instance.new("ScrollingFrame")
        sf.Parent = popup; sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0
        sf.Position = UDim2.new(0,0,0,HEADER_H); sf.Size = UDim2.new(1,0,0,scrollH)
        sf.CanvasSize = UDim2.new(0,0,0,contentH)
        sf.ScrollBarThickness = 6; sf.ScrollBarImageColor3 = C.ACC
        sf.ScrollingDirection = Enum.ScrollingDirection.Y; sf.ZIndex = 9999
        Instance.new("UIListLayout",sf).SortOrder = Enum.SortOrder.LayoutOrder
        local sfp = Instance.new("UIPadding",sf)
        sfp.PaddingTop=UDim.new(0,4); sfp.PaddingBottom=UDim.new(0,4)
        sfp.PaddingLeft=UDim.new(0,4); sfp.PaddingRight=UDim.new(0,8)

        local rowRefs = {}
        function UpdateCount()
            local n = 0; for _ in pairs(selTable) do n = n + 1 end
            countLbl.Text = n.."/"..maxSel.." dipilih"
            countLbl.TextColor3 = n >= maxSel and Color3.fromRGB(255,100,80) or C.ACC2
        end

        for _, q in ipairs(list) do
            local qRow = Btn(sf, C.DD_BG, UDim2.new(1,-8,0,ITEM_H)); qRow.ZIndex = 9999; Corner(qRow,5)
            local tBox = Frame(qRow, C.SEL_BG, UDim2.new(0,16,0,16))
            tBox.Position = UDim2.new(0,6,0.5,-8); Corner(tBox,3); tBox.ZIndex = 9999; Stroke(tBox,C.BORD2,1,0.4)
            local tMark = Label(tBox,"✓",11,C.BLACK,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
            tMark.Size = UDim2.new(1,0,1,0); tMark.ZIndex = 9999
            local isSelected = (selTable[q.id] == true or selTable[q.name] == true)
            tMark.Visible = isSelected
            local qLbl = Label(qRow,"  "..(q.name or q),11,isSelected and C.ACC2 or C.TXT,Enum.Font.Gotham)
            qLbl.Size = UDim2.new(1,-30,1,0); qLbl.Position = UDim2.new(0,28,0,0); qLbl.ZIndex = 9999
            if isSelected then qRow.BackgroundColor3 = Color3.fromRGB(140,52,0) end
            local key = q.id or q.name or q
            rowRefs[key] = {bg=qRow, tick=tMark, lbl=qLbl}

            qRow.MouseButton1Click:Connect(function()
                if selTable[key] then
                    selTable[key] = nil
                else
                    local n = 0; for _ in pairs(selTable) do n = n + 1 end
                    if n >= maxSel then
                        local old = countLbl.Text
                        countLbl.Text = "MAX "..maxSel.." tercapai!"; countLbl.TextColor3 = Color3.fromRGB(255,60,60)
                        task.delay(1.2, function() UpdateCount() end)
                        return
                    end
                    selTable[key] = true
                end
                for k2, ref in pairs(rowRefs) do
                    local sel = (selTable[k2] == true)
                    ref.bg.BackgroundColor3 = sel and Color3.fromRGB(140,52,0) or C.DD_BG
                    ref.tick.Visible = sel; ref.lbl.TextColor3 = sel and C.ACC2 or C.TXT
                end
                UpdateCount()
                if onRefresh then onRefresh() end
            end)
        end
        UpdateCount()
        clrBtn.MouseButton1Click:Connect(function()
            for k2 in pairs(selTable) do selTable[k2] = nil end
            for _, ref in pairs(rowRefs) do
                ref.bg.BackgroundColor3 = C.DD_BG; ref.tick.Visible = false; ref.lbl.TextColor3 = C.TXT
            end
            UpdateCount(); if onRefresh then onRefresh() end
        end)
        DDLayer.Visible = true
        _activeDDClose = function() popup:Destroy(); DDLayer.Visible = false end
    end)
end

-- ============================================================
-- PANEL : MAIN
-- ============================================================
;(function()
    local p = NewPanel("main")

    -- ── Section header ──
    local secHdr = Label(p,"TAMPILAN",10,C.TXT3,Enum.Font.GothamBold)
    secHdr.LayoutOrder=1; secHdr.Size=UDim2.new(1,0,0,16)

    -- ── Toggle: Hide Reward Popup ──
    ToggleRow(p,"🎁  Hide Reward Popup","Sembunyikan popup reward secara instan saat muncul",2,function(on)
        STATE.hideReward = on
        if on then
            -- Pasang semua hook BARU saat toggle ON
            pcall(SetupHideRewardHooks)
            pcall(ScanAndHideExistingRewardGuis)
        else
            -- Lepas semua hook saat toggle OFF
            pcall(TeardownHideRewardHooks)
            pcall(RestoreHiddenRewardGuis)
        end
    end)

    -- ── Toggle: Hide UI ──
    ToggleRow(p,"🙈  Hide UI","Sembunyikan semua UI game (HUD, topbar, dll) — GUI ASH tetap kelihatan",3,function(on)
        STATE.hideUI = on
        if on then
            pcall(HideAllGameUI)
        else
            pcall(RestoreAllGameUI)
        end
    end)

    -- ── Toggle: Auto Magnet ──
    ToggleRow(p,"🧲  Auto Magnet","Collect gold & item otomatis saat jatuh — langsung masuk ke kantong",4,function(on)
        STATE.autoMagnet = on
        DoAutoMagnet(on)
    end)
end)()

-- ============================================================
-- PANEL : FARM
-- ============================================================
do -- [FIX] farm panel locals wrapped to free registers
local agDot, agTxtLbl, agKLbl, agELbl
local eEnemyRows = {}
local eEnemyNames = {}
local activeEName = nil
local eBtnRefLbl
local FindLiveEnemyByName, SelectEnemyName, RefreshEnemies, RunAG_Targeted

;(function()
    local p = NewPanel("farm")

    local agSBF = Frame(p, C.SURFACE, UDim2.new(1,0,0,28))
    agSBF.LayoutOrder = 0; Corner(agSBF,7); Stroke(agSBF,C.AG,1,0.3)

    agDot = Frame(agSBF, C.DK, UDim2.new(0,8,0,8))
    agDot.Position = UDim2.new(0,8,0.5,-4); agDot.BorderSizePixel = 0
    Instance.new("UICorner",agDot).CornerRadius = UDim.new(1,0)

    agTxtLbl = Label(agSBF,"STANDBY",10,C.DIM,Enum.Font.GothamBold)
    agTxtLbl.Size = UDim2.new(0.5,0,1,0); agTxtLbl.Position = UDim2.new(0,22,0,0)
    agTxtLbl.TextTruncate = Enum.TextTruncate.AtEnd

    agKLbl = Label(agSBF,"0 kill  0 item",9,C.AG,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
    agKLbl.Size = UDim2.new(0.44,0,1,0); agKLbl.Position = UDim2.new(0.50,4,0,0)

    agELbl = Label(p,"Belum di-refresh",9,C.DIM,Enum.Font.Gotham)
    agELbl.Size = UDim2.new(1,0,0,14); agELbl.LayoutOrder = 1

    local tgtHdr = Label(p,"Target Musuh (pilih yang mau diserang)",10,C.AG,Enum.Font.GothamBold)
    tgtHdr.Size = UDim2.new(1,0,0,18); tgtHdr.LayoutOrder = 2

    local eCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,260))
    eCard.LayoutOrder = 4; Corner(eCard,9); Stroke(eCard,C.BORD,1,0.4)
    Padding(eCard,6,6,10,8)

    local eHeaderRow = Frame(eCard, C.BLACK, UDim2.new(1,0,0,22))
    eHeaderRow.BackgroundTransparency = 1; eHeaderRow.Position = UDim2.new(0,0,0,0)

    local eCntL = Label(eHeaderRow,"—",9,C.DK,Enum.Font.GothamBold)
    eCntL.Size = UDim2.new(0.6,0,1,0); eCntL.Position = UDim2.new(0,0,0,0)

    local eBtnRefresh = Btn(eHeaderRow, Color3.fromRGB(20,80,40), UDim2.new(0,80,0,20))
    eBtnRefresh.Position = UDim2.new(1,-80,0,1); Corner(eBtnRefresh,6); Stroke(eBtnRefresh,C.GRN,1,0.3)
    eBtnRefLbl = Label(eBtnRefresh,"Refresh",9,C.GRN,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    eBtnRefLbl.Size = UDim2.new(1,0,1,0)

    local eBox = Instance.new("ScrollingFrame",eCard)
    eBox.Size = UDim2.new(1,0,0,224); eBox.Position = UDim2.new(0,0,0,28)
    eBox.BackgroundColor3 = Color3.fromRGB(13,7,26); eBox.BorderSizePixel = 0
    eBox.ScrollBarThickness = 3; eBox.ScrollBarImageColor3 = C.AG
    eBox.CanvasSize = UDim2.new(0,0,0,0); eBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Corner(eBox,9); Stroke(eBox,C.BORD,1,0.4)
    local ePad = Instance.new("UIPadding",eBox)
    ePad.PaddingTop=UDim.new(0,5); ePad.PaddingBottom=UDim.new(0,5)
    ePad.PaddingLeft=UDim.new(0,5); ePad.PaddingRight=UDim.new(0,5)
    local eList = Instance.new("UIListLayout",eBox)
    eList.Padding=UDim.new(0,4); eList.SortOrder=Enum.SortOrder.LayoutOrder

    local ePlaceholder = Instance.new("TextLabel",eBox)
    ePlaceholder.Size=UDim2.new(1,0,0,44); ePlaceholder.BackgroundTransparency=1
    ePlaceholder.Text="Tekan Refresh untuk memuat daftar musuh di map ini"
    ePlaceholder.TextSize=9; ePlaceholder.Font=Enum.Font.Gotham
    ePlaceholder.TextColor3=C.DK; ePlaceholder.TextXAlignment=Enum.TextXAlignment.Center
    ePlaceholder.TextWrapped=true

    local function EnemyIco(name)
        local n = name:lower()
        if n:find("dragon") then return "🐉"
        elseif n:find("wolf") or n:find("beast") then return "🐺"
        elseif n:find("golem") or n:find("stone") then return "🪨"
        elseif n:find("demon") or n:find("devil") then return "😈"
        elseif n:find("slime") then return "🟢"
        elseif n:find("ghost") or n:find("spirit") then return "👻"
        elseif n:find("fire") or n:find("flame") then return "🔥"
        elseif n:find("ice") or n:find("frost") then return "❄"
        elseif n:find("boss") then return "💀"
        elseif n:find("pumpkin") then return "🎃"
        elseif n:find("bear") then return "🐻"
        elseif n:find("elf") then return "🧝"
        elseif n:find("sword") then return "⚔"
        elseif n:find("archer") then return "🏹"
        else return "👾" end
    end

    FindLiveEnemyByName = function(nm)
        for _, e in ipairs(GetEnemies()) do
            if e.model.Name == nm and not IsDead(e) then return e end
        end
        return nil
    end

    -- Serang 1 target spesifik, thread independen (tidak pakai AG state)
    RunAG_Targeted = function(targetName, onStatus, onDone)
        local killed = 0
        _tgtThread = task.spawn(function()
            SaveOrigin()
            local tgt = FindLiveEnemyByName(targetName)
            if tgt then
                TpToEnemy(tgt)
                FireHeroRemotes(tgt.guid, tgt.hrp.Position)
                if onStatus then onStatus("Target → ["..targetName.."]  Kill: "..killed) end
            end
            while _tgtThread do
                tgt = FindLiveEnemyByName(targetName)
                if not tgt then
                    if onStatus then onStatus("Menunggu ["..targetName.."] muncul...") end
                    while _tgtThread do
                        task.wait(0.5)
                        tgt = FindLiveEnemyByName(targetName)
                        if tgt then
                            if onStatus then onStatus("["..targetName.."] muncul! Mulai 2s...") end
                            task.wait(2)
                            if not _tgtThread then break end
                            TpToEnemy(tgt)
                            FireHeroRemotes(tgt.guid, tgt.hrp.Position)
                            if onStatus then onStatus("Target → ["..targetName.."]  Kill: "..killed) end
                            break
                        end
                    end
                    if not _tgtThread then break end
                    tgt = FindLiveEnemyByName(targetName)
                    if not tgt then task.wait(); continue end
                end
                if not IsDead(tgt) and tgt.model.Parent then
                    local pos = tgt.hrp and tgt.hrp.Position or Vector3.new(0,0,0)
                    FireAllDamage(tgt.guid, pos)
                end
                task.wait()
            end
            _tgtThread = nil
            ReturnHRPToOrigin()
            if onDone then onDone() end
        end)
    end

    SelectEnemyName = function(nm)
        if activeEName and eEnemyRows[activeEName] then
            local old = eEnemyRows[activeEName]
            TweenService:Create(old.row,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(18,10,36)}):Play()
            old.stroke.Color=C.BORD; old.nameLbl.TextColor3=C.DIM; old.dot.Visible=false
        end
        activeEName = nm
        if not nm then AG.currentTarget = nil; eCntL.Text = "—"; return end
        local r = eEnemyRows[nm]
        if r then
            TweenService:Create(r.row,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(90,38,10)}):Play()
            r.stroke.Color=C.AG; r.nameLbl.TextColor3=C.TXT; r.dot.Visible=true
        end
        eCntL.Text = ">> "..nm
        AG.currentTarget = FindLiveEnemyByName(nm)
    end

    RefreshEnemies = function()
        for _, r in pairs(eEnemyRows) do
            if r.row and r.row.Parent then r.row:Destroy() end
        end
        eEnemyRows = {}; eEnemyNames = {}
        ePlaceholder.Visible = false
        activeEName = nil; AG.currentTarget = nil; eCntL.Text = "—"
        local enemies = GetEnemies()
        if #enemies == 0 then
            ePlaceholder.Text = "Tidak ada musuh di map ini."
            ePlaceholder.Visible = true
            agELbl.Text = "Tidak ada musuh di map ini"
            agELbl.TextColor3 = Color3.fromRGB(220,130,60)
            return
        end
        local nameCount = {}
        for _, e in ipairs(enemies) do nameCount[e.model.Name] = (nameCount[e.model.Name] or 0) + 1 end
        local names = {}
        for nm in pairs(nameCount) do table.insert(names, nm) end
        table.sort(names); eEnemyNames = names
        for idx, nm in ipairs(names) do
            local cnt = nameCount[nm]; local ico = EnemyIco(nm)
            local row = Instance.new("Frame",eBox)
            row.LayoutOrder=idx; row.Size=UDim2.new(1,0,0,36)
            row.BackgroundColor3=Color3.fromRGB(18,10,36); row.BorderSizePixel=0
            Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
            local rs = Instance.new("UIStroke",row); rs.Color=C.BORD; rs.Thickness=1
            local btn = Instance.new("TextButton",row)
            btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1
            btn.Text=""; btn.AutoButtonColor=false
            local dot = Instance.new("Frame",row)
            dot.Size=UDim2.new(0,4,0.6,0); dot.Position=UDim2.new(0,2,0.2,0)
            dot.BackgroundColor3=C.AG; dot.BorderSizePixel=0; dot.Visible=false
            Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
            local iL=Instance.new("TextLabel",row)
            iL.Size=UDim2.new(0,24,1,0); iL.Position=UDim2.new(0,8,0,0)
            iL.BackgroundTransparency=1; iL.Text=ico; iL.TextSize=14
            iL.Font=Enum.Font.GothamBold; iL.TextColor3=C.YEL; iL.TextXAlignment=Enum.TextXAlignment.Center
            local nL=Instance.new("TextLabel",row)
            nL.Size=UDim2.new(1,-74,1,0); nL.Position=UDim2.new(0,34,0,0)
            nL.BackgroundTransparency=1; nL.Text=nm; nL.TextSize=9.5
            nL.Font=Enum.Font.GothamBold; nL.TextColor3=C.DIM; nL.TextXAlignment=Enum.TextXAlignment.Left
            nL.TextTruncate=Enum.TextTruncate.AtEnd
            local cL=Instance.new("TextLabel",row)
            cL.Size=UDim2.new(0,34,1,0); cL.Position=UDim2.new(1,-36,0,0)
            cL.BackgroundTransparency=1; cL.Text="x"..cnt; cL.TextSize=9
            cL.Font=Enum.Font.GothamBold; cL.TextColor3=C.DK; cL.TextXAlignment=Enum.TextXAlignment.Right
            eEnemyRows[nm]={row=row, stroke=rs, nameLbl=nL, cntLbl=cL, dot=dot}
            local bnm = nm
            local tbnOn = false   -- toggle state untuk baris ini
            local tbnThread = nil -- thread khusus baris ini

            local function StopTbn()
                tbnOn = false
                if tbnThread then
                    pcall(function() task.cancel(tbnThread) end)
                    tbnThread = nil
                end
                -- Visual: kembalikan baris ke normal
                TweenService:Create(row, TweenInfo.new(0.12), {BackgroundColor3=Color3.fromRGB(18,10,36)}):Play()
                rs.Color = C.BORD; nL.TextColor3 = C.DIM; dot.Visible = false
                eCntL.Text = "—"
                ReturnHRPToOrigin()
            end

            btn.MouseButton1Click:Connect(function()
                if tbnOn then
                    -- Sedang jalan → matikan
                    StopTbn()
                else
                    -- Matikan thread baris lain kalau ada
                    if _tgtThread then
                        pcall(function() task.cancel(_tgtThread) end)
                        _tgtThread = nil
                    end
                    tbnOn = true
                    -- Visual: highlight baris ini
                    TweenService:Create(row, TweenInfo.new(0.12), {BackgroundColor3=Color3.fromRGB(90,38,10)}):Play()
                    rs.Color = C.AG; nL.TextColor3 = C.TXT; dot.Visible = true
                    eCntL.Text = ">> "..bnm

                    -- Jalankan loop serang target ini
                    tbnThread = task.spawn(function()
                        _tgtThread = tbnThread
                        SaveOrigin()
                        -- Jalankan auto collect selama tbnOn aktif
                        task.spawn(function()
                            local collected = {}
                            while tbnOn do
                                for _, folderName in ipairs({"Golds","Items","Drops","Rewards"}) do
                                    local folder = workspace:FindFirstChild(folderName)
                                    if folder then
                                        for _, obj in ipairs(folder:GetChildren()) do
                                            if not tbnOn then break end
                                            local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid")
                                            if guid and not collected[guid] then
                                                collected[guid] = true
                                                pcall(function() RE.CollectItem:InvokeServer(guid) end)
                                                if not (STATE and STATE.hideReward) then pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end) end
                                                task.wait(0.05)
                                            end
                                        end
                                    end
                                end
                                task.wait(0.25)
                            end
                        end)
                        -- TP ke target pertama
                        local tgt = FindLiveEnemyByName(bnm)
                        if tgt then
                            TpToEnemy(tgt)
                            task.wait(0.3) -- beri jeda server sync setelah TP
                            FireHeroRemotes(tgt.guid, tgt.hrp.Position)
                            agTxtLbl.Text = "Target → ["..bnm.."]  Kill: 0"
                        end
                        local killCount = 0
                        local lastGuid = tgt and tgt.guid or nil

                        function FireTgt(t)
                            if not t or not t.hrp or not t.model.Parent then return end
                            local pos = t.hrp.Position
                            if RE.Click then pcall(function() RE.Click:InvokeServer({enemyGuid=t.guid, enemyPos=pos}) end) end
                            if RE.Atk then
                                pcall(function() RE.Atk:FireServer({attackEnemyGUID=t.guid}) end)
                                pcall(function() RE.Atk:FireServer(t.guid) end)
                            end
                            for _, hGuid in ipairs(HERO_GUIDS) do
                                if RE.HeroUseSkill then
                                    for aType = 1, 3 do
                                        pcall(function() RE.HeroUseSkill:FireServer({
                                            heroGuid=hGuid, attackType=aType,
                                            userId=MY_USER_ID, enemyGuid=t.guid,
                                        }) end)
                                    end
                                end
                                if RE.HeroSkill then
                                    pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid, enemyGuid=t.guid, skillType=1, masterId=MY_USER_ID}) end)
                                end
                            end
                        end

                        while tbnOn do
                            -- Ambil instance musuh hidup dengan nama ini
                            tgt = FindLiveEnemyByName(bnm)

                            if not tgt then
                                -- Semua musuh nama ini mati → tunggu respawn
                                agTxtLbl.Text = "Menunggu ["..bnm.."] respawn..."
                                while tbnOn do
                                    task.wait(0.5)
                                    tgt = FindLiveEnemyByName(bnm)
                                    if tgt then
                                        agTxtLbl.Text = bnm.." respawn! Mulai 2s..."
                                        task.wait(2)
                                        if not tbnOn then break end
                                        -- TP ke instance baru
                                        TpToEnemy(tgt)
                                        task.wait(0.3)
                                        FireHeroRemotes(tgt.guid, tgt.hrp.Position)
                                        lastGuid = tgt.guid
                                        break
                                    end
                                end
                                if not tbnOn then break end
                                tgt = FindLiveEnemyByName(bnm)
                                if not tgt then task.wait(); continue end
                            end

                            -- Cek apakah instance berubah (musuh mati, ada instance baru)
                            if tgt.guid ~= lastGuid then
                                lastGuid = tgt.guid
                                TpToEnemy(tgt)
                                task.wait(0.3)
                                FireHeroRemotes(tgt.guid, tgt.hrp.Position)
                            end

                            -- Serang
                            if not IsDead(tgt) and tgt.model.Parent then
                                FireTgt(tgt)
                                killCount = AG.killed
                                agTxtLbl.Text = "Target → ["..bnm.."]  Kill: "..killCount
                            end
                            task.wait()
                        end
                        _tgtThread = nil
                        tbnThread = nil
                        StopTbn()
                    end)
                end
            end)
        end
        agELbl.Text = #names.." jenis  |  "..#enemies.." total  —  tap untuk serang"
        agELbl.TextColor3 = C.GRN
    end

    task.spawn(function()
        while ScreenGui.Parent do
            if #eEnemyNames > 0 then
                local liveCnt = {}
                for _, e in ipairs(GetEnemies()) do
                    if not IsDead(e) then liveCnt[e.model.Name] = (liveCnt[e.model.Name] or 0)+1 end
                end
                for _, nm in ipairs(eEnemyNames) do
                    local r = eEnemyRows[nm]; if not r then continue end
                    local alive = liveCnt[nm] or 0
                    r.cntLbl.Text = "x"..alive
                    r.cntLbl.TextColor3 = alive == 0 and Color3.fromRGB(120,40,40) or C.DK
                end
                if activeEName and (AG.currentTarget == nil or IsDead(AG.currentTarget) or not AG.currentTarget.model.Parent) then
                    AG.currentTarget = FindLiveEnemyByName(activeEName)
                end
            end
            task.wait(0.5)
        end
    end)

    eBtnRefresh.MouseButton1Click:Connect(function()
        eBtnRefLbl.Text = "Loading..."
        task.spawn(function() RefreshEnemies(); task.wait(0.3); eBtnRefLbl.Text = "Refresh" end)
    end)

    local agBtn = Btn(p, C.ACC, UDim2.new(1,0,0,44))
    agBtn.LayoutOrder = 5; Corner(agBtn,9)
    do
        local g = Instance.new("UIGradient",agBtn)
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(230,95,20)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(140,45,5)),
        }); g.Rotation = 135
        local s = Instance.new("UIStroke",agBtn); s.Color=C.AG; s.Thickness=1; s.Transparency=0.35
    end
    local agBtnLbl = Label(agBtn,"MULAI AUTO GOYANG",13,C.TXT,Enum.Font.GothamBold)
    agBtnLbl.Size = UDim2.new(1,0,1,0); agBtnLbl.TextXAlignment = Enum.TextXAlignment.Center

    function SetAGUI(on)
        if on then
            TweenService:Create(agBtn,TweenInfo.new(0.15),{BackgroundColor3=Color3.fromRGB(200,40,40)}):Play()
            agBtnLbl.Text="BERHENTI GOYANG"; agDot.BackgroundColor3=C.AG; agTxtLbl.TextColor3=C.AG
        else
            TweenService:Create(agBtn,TweenInfo.new(0.15),{BackgroundColor3=C.ACC}):Play()
            agBtnLbl.Text="MULAI AUTO GOYANG"
            agDot.BackgroundColor3=C.DK; agTxtLbl.TextColor3=C.DIM; agTxtLbl.Text="STANDBY"
        end
    end

    agBtn.MouseButton1Click:Connect(function()
        TweenService:Create(agBtn,TweenInfo.new(0.07),{Size=UDim2.new(1,0,0,40)}):Play()
        task.wait(0.07)
        TweenService:Create(agBtn,TweenInfo.new(0.1),{Size=UDim2.new(1,0,0,44)}):Play()
        if _agOn then
            _agOn=false; AG.running=false
            if AG.thread then pcall(function() task.cancel(AG.thread) end); AG.thread=nil end
            ReturnHRPToOrigin(); SetAGUI(false)
        else
            _agOn=true; SetAGUI(true)
            RunAG(
                function(msg) agTxtLbl.Text=msg; agKLbl.Text=AG.killed.." kill  "..AG.collected.." item" end,
                function() _agOn=false; SetAGUI(false) end
            )
        end
    end)
end)()
end -- do (farm panel locals)

-- ============================================================
-- PANEL : ATTACK
-- ============================================================
;(function()
    local p = NewPanel("attack")

    local ddBackdrop = Instance.new("TextButton",ScreenGui)
    ddBackdrop.Size=UDim2.new(1,0,1,0); ddBackdrop.Position=UDim2.new(0,0,0,0)
    ddBackdrop.BackgroundTransparency=1; ddBackdrop.Text=""; ddBackdrop.ZIndex=49
    ddBackdrop.AutoButtonColor=false; ddBackdrop.Visible=false; ddBackdrop.Active=false
    local _openDDs = {}

    function OpenDD(list)
        for _, d in ipairs(_openDDs) do d.Visible = false end
        _openDDs = {}; list.Visible = true; table.insert(_openDDs, list); ddBackdrop.Visible = true
    end
    function CloseAllDD()
        for _, d in ipairs(_openDDs) do d.Visible = false end
        _openDDs = {}; ddBackdrop.Visible = false
    end
    ddBackdrop.MouseButton1Click:Connect(CloseAllDD)

    SectionHeader(p,"MASS ATTACK",0)

    local maCard = Frame(p,C.SURFACE,UDim2.new(1,0,0,44))
    maCard.LayoutOrder=1; Corner(maCard,8); Stroke(maCard,C.BORD,1,0.4)
    Padding(maCard,6,6,12,8)
    local maTitleLbl = Label(maCard,"Status",12,C.TXT,Enum.Font.GothamBold)
    maTitleLbl.Size=UDim2.new(0.4,0,0,16); maTitleLbl.Position=UDim2.new(0,0,0,4)
    local maStatusText = Label(maCard,"Idle",11,C.TXT2,Enum.Font.Gotham,Enum.TextXAlignment.Right)
    maStatusText.Size=UDim2.new(0.6,0,0,16); maStatusText.Position=UDim2.new(0.4,0,0,4)
    maStatusText.TextTruncate=Enum.TextTruncate.AtEnd
    _maStatusLbl = maStatusText

    function MakeSimpleDD(card, title, opts, vals, defIdx, onSelect, lo)
        local c = Frame(p,C.SURFACE,UDim2.new(1,0,0,38))
        c.LayoutOrder=lo; Corner(c,8); Stroke(c,C.BORD,1,0.4); Padding(c,6,6,12,8)
        local lbl = Label(c,title,12,C.TXT,Enum.Font.GothamBold)
        lbl.Size=UDim2.new(0.5,0,1,0); lbl.Position=UDim2.new(0,0,0,0)
        local curIdx = defIdx
        local ddBtn = Btn(c,C.BG3,UDim2.new(0.5,-4,1,-4))
        ddBtn.Position=UDim2.new(0.5,0,0,2); Corner(ddBtn,6); Stroke(ddBtn,C.BORD,1,0.2)
        local ddLbl = Label(ddBtn,"  "..opts[curIdx],11,C.ACC2,Enum.Font.GothamBold)
        ddLbl.Size=UDim2.new(1,-18,1,0)
        local arr = Label(ddBtn,"▾",11,C.TXT2,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        arr.Size=UDim2.new(0,16,1,0); arr.Position=UDim2.new(1,-18,0,0)

        local list = Instance.new("Frame",ScreenGui)
        list.Size=UDim2.new(0,130,0,#opts*28+8)
        list.BackgroundColor3=Color3.fromRGB(22,18,14); list.BorderSizePixel=0
        list.ZIndex=50; list.Visible=false
        Instance.new("UICorner",list).CornerRadius=UDim.new(0,8)
        Instance.new("UIStroke",list).Color=C.BORD
        local ll=Instance.new("UIListLayout",list); ll.Padding=UDim.new(0,2); ll.SortOrder=Enum.SortOrder.LayoutOrder
        Instance.new("UIPadding",list).PaddingTop=UDim.new(0,4)

        local irefs = {}
        for i, opt in ipairs(opts) do
            local item=Instance.new("TextButton",list)
            item.Size=UDim2.new(1,-8,0,26); item.LayoutOrder=i
            item.BackgroundColor3=i==curIdx and Color3.fromRGB(90,35,8) or Color3.fromRGB(32,24,16)
            item.BackgroundTransparency=i==curIdx and 0 or 0.4
            item.BorderSizePixel=0; item.Text=""; item.AutoButtonColor=false; item.ZIndex=51
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)
            local iL=Instance.new("TextLabel",item)
            iL.Size=UDim2.new(1,-8,1,0); iL.Position=UDim2.new(0,8,0,0)
            iL.BackgroundTransparency=1; iL.Text=opt; iL.TextSize=11
            iL.Font=Enum.Font.GothamBold; iL.TextColor3=i==curIdx and C.ACC2 or C.TXT
            iL.TextXAlignment=Enum.TextXAlignment.Left; iL.ZIndex=52
            irefs[i]={btn=item,lbl=iL}
            local ii=i
            item.MouseButton1Click:Connect(function()
                curIdx=ii; ddLbl.Text="  "..opts[ii]
                for j,r in ipairs(irefs) do
                    r.btn.BackgroundColor3=j==ii and Color3.fromRGB(90,35,8) or Color3.fromRGB(32,24,16)
                    r.btn.BackgroundTransparency=j==ii and 0 or 0.4
                    r.lbl.TextColor3=j==ii and C.ACC2 or C.TXT
                end
                if vals then onSelect(vals[ii]) else onSelect(ii) end
                CloseAllDD()
            end)
        end
        ddBtn.MouseButton1Click:Connect(function()
            if list.Visible then CloseAllDD(); return end
            local ap=ddBtn.AbsolutePosition; local as=ddBtn.AbsoluteSize
            list.Position=UDim2.new(0,ap.X,0,ap.Y+as.Y+2-GuiInsetY())
            list.Size=UDim2.new(0,as.X,0,#opts*28+8)
            OpenDD(list)
        end)
    end

    MakeSimpleDD(nil,"Kill Target",
        {"5","10","15","20","Kill All"},{5,10,15,20,0},1,
        function(v) MA.killTarget=v end, 2)

    do
        local mapCard=Frame(p,C.SURFACE,UDim2.new(1,0,0,38))
        mapCard.LayoutOrder=3; Corner(mapCard,8); Stroke(mapCard,C.BORD,1,0.4); Padding(mapCard,6,6,12,8)
        local mapLbl=Label(mapCard,"Rotation Map",12,C.TXT,Enum.Font.GothamBold)
        mapLbl.Size=UDim2.new(0.5,0,1,0)
        local mapOpts={"Semua Map"}
        for i=1,18 do mapOpts[i+1]="Map "..i end
        local mapSelSet={}
        local mapDDBtn=Btn(mapCard,C.BG3,UDim2.new(0.5,-4,1,-4))
        mapDDBtn.Position=UDim2.new(0.5,0,0,2); Corner(mapDDBtn,6); Stroke(mapDDBtn,C.BORD,1,0.2)
        local mapDDLbl=Label(mapDDBtn,"  Pilih Map",11,C.ACC2,Enum.Font.GothamBold)
        mapDDLbl.Size=UDim2.new(1,-18,1,0)
        local mapArrow=Label(mapDDBtn,"▾",11,C.TXT2,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        mapArrow.Size=UDim2.new(0,16,1,0); mapArrow.Position=UDim2.new(1,-18,0,0)

        function UpdateMapDDLbl()
            local count=0; for _ in pairs(mapSelSet) do count=count+1 end
            if count==0 then mapDDLbl.Text="  Map saat ini"
            elseif count==18 then mapDDLbl.Text="  Semua Map"
            else mapDDLbl.Text="  "..count.." Map dipilih" end
        end

        local mapListH=math.min(#mapOpts*28+8,180)
        local mapList=Instance.new("Frame",ScreenGui)
        mapList.Size=UDim2.new(0,130,0,mapListH); mapList.BackgroundColor3=Color3.fromRGB(22,18,14)
        mapList.BorderSizePixel=0; mapList.ZIndex=50; mapList.Visible=false; mapList.ClipsDescendants=true
        Instance.new("UICorner",mapList).CornerRadius=UDim.new(0,8)
        Instance.new("UIStroke",mapList).Color=C.BORD

        local mapScroll=Instance.new("ScrollingFrame",mapList)
        mapScroll.Size=UDim2.new(1,0,1,0); mapScroll.BackgroundTransparency=1; mapScroll.BorderSizePixel=0
        mapScroll.ScrollBarThickness=3; mapScroll.ScrollBarImageColor3=C.ACC
        mapScroll.CanvasSize=UDim2.new(0,0,0,#mapOpts*28+8); mapScroll.ZIndex=51
        local mapScrollLayout=Instance.new("UIListLayout",mapScroll)
        mapScrollLayout.Padding=UDim.new(0,2); mapScrollLayout.SortOrder=Enum.SortOrder.LayoutOrder
        Instance.new("UIPadding",mapScroll).PaddingTop=UDim.new(0,4)

        local mapItemRefs={}
        for i,opt in ipairs(mapOpts) do
            local item=Instance.new("TextButton",mapScroll)
            item.Size=UDim2.new(1,-8,0,26); item.LayoutOrder=i
            item.BackgroundColor3=Color3.fromRGB(32,24,16); item.BackgroundTransparency=0.4
            item.BorderSizePixel=0; item.Text=""; item.AutoButtonColor=false; item.ZIndex=52
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)
            local chk=Instance.new("TextLabel",item); chk.Size=UDim2.new(0,16,1,0); chk.Position=UDim2.new(0,4,0,0)
            chk.BackgroundTransparency=1; chk.Text=""; chk.TextSize=11
            chk.Font=Enum.Font.GothamBold; chk.TextColor3=C.GRN; chk.ZIndex=53
            local iLbl=Instance.new("TextLabel",item); iLbl.Size=UDim2.new(1,-24,1,0); iLbl.Position=UDim2.new(0,20,0,0)
            iLbl.BackgroundTransparency=1; iLbl.Text=opt; iLbl.TextSize=11
            iLbl.Font=Enum.Font.GothamBold; iLbl.TextColor3=C.TXT; iLbl.TextXAlignment=Enum.TextXAlignment.Left; iLbl.ZIndex=53
            mapItemRefs[i]={btn=item,chk=chk,lbl=iLbl}
            local ii=i
            item.MouseButton1Click:Connect(function()
                if ii==1 then
                    local anyOff=false
                    for j=1,18 do if not mapSelSet[j] then anyOff=true; break end end
                    if anyOff then
                        for j=1,18 do mapSelSet[j]=true; MR.selected[j]=true end
                        for j=2,#mapItemRefs do mapItemRefs[j].chk.Text="✓"; mapItemRefs[j].lbl.TextColor3=C.ACC2 end
                        mapItemRefs[1].chk.Text="✓"; mapItemRefs[1].lbl.TextColor3=C.ACC2
                    else
                        for j=1,18 do mapSelSet[j]=nil; MR.selected[j]=nil end
                        for j=1,#mapItemRefs do mapItemRefs[j].chk.Text=""; mapItemRefs[j].lbl.TextColor3=C.TXT end
                    end
                else
                    local mi=ii-1; mapSelSet[mi]=not mapSelSet[mi]; MR.selected[mi]=mapSelSet[mi]
                    mapItemRefs[ii].chk.Text=mapSelSet[mi] and "✓" or ""
                    mapItemRefs[ii].lbl.TextColor3=mapSelSet[mi] and C.ACC2 or C.TXT
                    local allOn=true; for j=1,18 do if not mapSelSet[j] then allOn=false; break end end
                    mapItemRefs[1].chk.Text=allOn and "✓" or ""; mapItemRefs[1].lbl.TextColor3=allOn and C.ACC2 or C.TXT
                end
                UpdateMapDDLbl()
            end)
        end
        mapDDBtn.MouseButton1Click:Connect(function()
            if mapList.Visible then CloseAllDD(); return end
            local ap=mapDDBtn.AbsolutePosition; local as=mapDDBtn.AbsoluteSize
            mapList.Position=UDim2.new(0,ap.X,0,ap.Y+as.Y+2-GuiInsetY())
            OpenDD(mapList)
        end)
    end

    MakeSimpleDD(nil,"Delay Pindah Map",
        {"1 detik","3 detik","5 detik","7 detik","10 detik"},{1,3,5,7,10},2,
        function(v) MR.nextMapDelay=v end, 4)

    local skillCard=Frame(p,C.SURFACE,UDim2.new(1,0,0,64))
    skillCard.LayoutOrder=5; Corner(skillCard,8); Stroke(skillCard,C.BORD,1,0.4); Padding(skillCard,8,8,12,8)
    local skillTitle=Label(skillCard,"Auto Skill",12,C.TXT,Enum.Font.GothamBold)
    skillTitle.Size=UDim2.new(1,0,0,16); skillTitle.Position=UDim2.new(0,0,0,0)
    local skillRow=Frame(skillCard,C.BLACK,UDim2.new(1,0,0,32))
    skillRow.BackgroundTransparency=1; skillRow.Position=UDim2.new(0,0,0,20)
    New("UIListLayout",{Parent=skillRow,FillDirection=Enum.FillDirection.Horizontal,
        SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})
    for i,d in ipairs({{n="Z",c=Color3.fromRGB(255,80,80)},{n="X",c=Color3.fromRGB(255,160,40)},{n="C",c=Color3.fromRGB(80,220,120)},{n="V",c=Color3.fromRGB(80,180,255)},{n="F",c=Color3.fromRGB(200,80,255)}}) do
        local sb=Btn(skillRow,C.BG3,UDim2.new(0,40,0,32)); sb.LayoutOrder=i; Corner(sb,6); Stroke(sb,C.BORD,1,0.3)
        local sl=Label(sb,d.n,12,d.c,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        sl.Size=UDim2.new(1,0,0,18); sl.Position=UDim2.new(0,0,0,2)
        sl.TextYAlignment=Enum.TextYAlignment.Center
        local st=Label(sb,"OFF",8,C.TXT3,Enum.Font.Gotham,Enum.TextXAlignment.Center)
        st.Size=UDim2.new(1,0,0,11); st.Position=UDim2.new(0,0,0,19)
        st.TextYAlignment=Enum.TextYAlignment.Center
        -- Simpan referensi ke SKL_UI supaya SkSetUI bisa update tampilan
        SKL.ui[d.n] = {btn=sb, lbl=st}
        local dn=d.n
        sb.MouseButton1Click:Connect(function()
            if SKL[dn].on then SkOff(dn) else SkOn(dn) end
        end)
    end

    ToggleRow(p,"Mass Attack","Serang semua musuh di map sekaligus",6,function(on)
        DoMassAttack(on)
    end)
end)()

-- ============================================================
-- PANEL : PLAYER
-- ============================================================
;(function()
    local p = NewPanel("player")

    local afkCard=Frame(p,C.SURFACE,UDim2.new(1,0,0,54))
    afkCard.LayoutOrder=-1; Corner(afkCard,8); Stroke(afkCard,C.BORD,1,0.4); Padding(afkCard,6,6,12,8)
    local afkTitle=Label(afkCard,"⏱  Sesi & Waktu (WIB)",12,C.TXT,Enum.Font.GothamBold)
    afkTitle.Size=UDim2.new(1,0,0,16); afkTitle.Position=UDim2.new(0,0,0,2)
    local afkTimeLbl=Label(afkCard,"WIB: --:--:--  |  Aktif: 00:00:00",10.5,C.TXT2,Enum.Font.Gotham)
    afkTimeLbl.Size=UDim2.new(1,0,0,13); afkTimeLbl.Position=UDim2.new(0,0,0,22)

    task.spawn(function()
        while true do
            task.wait(1)
            local utc=os.time(); local wib=utc+(7*3600)
            local h=math.floor(wib/3600)%24; local m=math.floor(wib/60)%60; local s=wib%60
            local wibStr=string.format("%02d:%02d:%02d",h,m,s)
            local durStr="00:00:00"
            if STATE.antiAfk and _antiAfkStart then
                local dur=os.time()-_antiAfkStart
                durStr=string.format("%02d:%02d:%02d",math.floor(dur/3600),math.floor(dur/60)%60,dur%60)
            end
            pcall(function()
                afkTimeLbl.Text="WIB: "..wibStr.."  |  Aktif: "..durStr
                afkTimeLbl.TextColor3=STATE.antiAfk and C.ACC2 or C.TXT2
            end)
        end
    end)

    SectionHeader(p,"PLAYER SETTINGS",0)

    local wsCard=Frame(p,C.SURFACE,UDim2.new(1,0,0,70))
    wsCard.LayoutOrder=1; Corner(wsCard,8); Stroke(wsCard,C.BORD,1,0.4); Padding(wsCard,8,8,12,8)
    local wsTitle=Label(wsCard,"Walk Speed",12,C.TXT,Enum.Font.GothamBold)
    wsTitle.Size=UDim2.new(0.6,0,0,16); wsTitle.Position=UDim2.new(0,0,0,4)
    local wsValLbl=Label(wsCard,"16 (100%)",11,C.ACC2,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
    wsValLbl.Size=UDim2.new(0.4,0,0,16); wsValLbl.Position=UDim2.new(0.6,0,0,4)
    local sliderTrack=Frame(wsCard,C.BG3,UDim2.new(1,0,0,8))
    sliderTrack.Position=UDim2.new(0,0,0,30); Corner(sliderTrack,4); Stroke(sliderTrack,C.BORD,1,0.5)
    local sliderFill=Frame(sliderTrack,C.ACC,UDim2.new(0.1,0,1,0)); Corner(sliderFill,4)
    local sliderKnob=Frame(sliderTrack,C.ACC2,UDim2.new(0,14,0,14))
    sliderKnob.Position=UDim2.new(0.1,-7,0.5,-7); Corner(sliderKnob,7); Stroke(sliderKnob,C.ACC3,1.5,0)
    local presetRow=Frame(wsCard,C.BLACK,UDim2.new(1,0,0,16))
    presetRow.BackgroundTransparency=1; presetRow.Position=UDim2.new(0,0,0,46)
    local presets={{lbl="0%",v=0},{lbl="100%",v=16},{lbl="300%",v=48},{lbl="500%",v=80},{lbl="1000%",v=160}}
    local presetW=1/#presets
    for i,pr in ipairs(presets) do
        local pb=Btn(presetRow,C.BG3,UDim2.new(presetW,-2,1,0))
        pb.Position=UDim2.new((i-1)*presetW,1,0,0); Corner(pb,3)
        local pl=Label(pb,pr.lbl,9,C.TXT3,Enum.Font.Gotham,Enum.TextXAlignment.Center)
        pl.Size=UDim2.new(1,0,1,0)
        pb.MouseButton1Click:Connect(function()
            local char=LP.Character
            if char then local hum=char:FindFirstChild("Humanoid"); if hum then hum.WalkSpeed=pr.v end end
            local pct=math.floor(pr.v/16*100)
            wsValLbl.Text=pr.v.." ("..pct.."%)"
            sliderFill.Size=UDim2.new(math.clamp(pr.v/160,0,1),0,1,0)
            sliderKnob.Position=UDim2.new(math.clamp(pr.v/160,0,1),-7,0.5,-7)
        end)
    end
    local isDragging=false
    function SetSpeed(relX)
        local frac=math.clamp(relX,0,1); local spd=math.floor(frac*160)
        wsValLbl.Text=spd.." ("..math.floor(spd/16*100).."%)"
        sliderFill.Size=UDim2.new(frac,0,1,0); sliderKnob.Position=UDim2.new(frac,-7,0.5,-7)
        local char=LP.Character
        if char then local hum=char:FindFirstChild("Humanoid"); if hum then hum.WalkSpeed=spd end end
    end
    sliderTrack.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            isDragging=true; local rel=(i.Position.X-sliderTrack.AbsolutePosition.X)/sliderTrack.AbsoluteSize.X; SetSpeed(rel)
        end
    end)
    sliderTrack.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then isDragging=false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if isDragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            SetSpeed((i.Position.X-sliderTrack.AbsolutePosition.X)/sliderTrack.AbsoluteSize.X)
        end
    end)

    ToggleRow(p,"No Clip","Tembus tembok & objek apapun selama aktif",2,function(on)
        STATE.noClip=on
        if _noClipConn then _noClipConn:Disconnect(); _noClipConn=nil end
        if on then
            _noClipConn=RunService.Stepped:Connect(function()
                local char=LP.Character; if not char then return end
                for _,part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then part.CanCollide=false end
                end
            end)
        else
            local char=LP.Character
            if char then
                local hrp=char:FindFirstChild("HumanoidRootPart"); local hum=char:FindFirstChildOfClass("Humanoid")
                if hrp and hum then
                    local pos=hrp.CFrame; hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    task.wait(0.1); hrp.CFrame=pos
                end
            end
        end
        RefreshStatus()
    end)

    ToggleRow(p,"Anti AFK","Mencegah kick sistem idle 15 menit",4,function(on)
        STATE.antiAfk=on
        if _antiAfkThread then pcall(function() task.cancel(_antiAfkThread) end); _antiAfkThread=nil end
        if on then
            _antiAfkStart=os.time()
            _antiAfkThread=task.spawn(function()
                while STATE.antiAfk do
                    pcall(function()
                        local cam=workspace.CurrentCamera
                        if cam then
                            local cf=cam.CFrame; cam.CFrame=cf*CFrame.Angles(0,0.001,0)
                            task.wait(0.05); cam.CFrame=cf
                        end
                    end)
                    task.wait(60)
                end
            end)
        else
            _antiAfkStart=nil
        end
        RefreshStatus()
    end)

    SectionHeader(p,"LAINNYA",10)
    local rejoinCard=Frame(p,C.SURFACE,UDim2.new(1,0,0,50))
    rejoinCard.LayoutOrder=11; Corner(rejoinCard,8); Stroke(rejoinCard,C.BORD,1,0.4); Padding(rejoinCard,8,8,12,8)
    local rejoinLbl=Label(rejoinCard,"Rejoin Server",12,C.TXT,Enum.Font.GothamBold)
    rejoinLbl.Size=UDim2.new(0.65,0,0,18); rejoinLbl.Position=UDim2.new(0,0,0,6)
    local rejoinSub=Label(rejoinCard,"Reconnect ke server yang sama",10,C.TXT3,Enum.Font.Gotham)
    rejoinSub.Size=UDim2.new(0.85,0,0,14); rejoinSub.Position=UDim2.new(0,0,0,26)
    local rejoinBtn=Btn(rejoinCard,C.ACC,UDim2.new(0,70,0,30))
    rejoinBtn.Position=UDim2.new(1,-76,0.5,-15); Corner(rejoinBtn,8); Stroke(rejoinBtn,C.ACC2,1,0.2)
    local rejoinBtnLbl=Label(rejoinBtn,"Rejoin",12,C.BLACK,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    rejoinBtnLbl.Size=UDim2.new(1,0,1,0)
    rejoinBtn.MouseButton1Click:Connect(function()
        rejoinBtnLbl.Text="..."; task.wait(0.5); DoRejoin()
    end)
end)()

-- ============================================================
-- PANEL : HERO FASTROLL
-- ============================================================
;(function()
    local p = NewPanel("autoroll")
    local hrOpen = false

    -- State
    _HR_RPT = {
        guid     = "",
        nameLbl  = nil,
        slotLbls = {nil,nil,nil},
        slotTarget = {{},{},{}},
        running  = false,
        SetSlot  = function(i,txt,col)
            if _HR_RPT.slotLbls[i] then
                _HR_RPT.slotLbls[i].Text = txt
                _HR_RPT.slotLbls[i].TextColor3 = col or Color3.fromRGB(160,148,135)
            end
        end,
        Refresh  = function()
            if not _HR_RPT.nameLbl then return end
            if _HR_RPT.guid and _HR_RPT.guid ~= "" then
                local found = nil
                pcall(function()
                    for _, obj in ipairs(game.Players.LocalPlayer.PlayerGui:GetDescendants()) do
                        if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
                        and obj.Name == "NameText"
                        and obj.Parent and obj.Parent.Name == "HeroFrame"
                        and obj.Parent.Parent and obj.Parent.Parent.Name == "SelectHeroBtn" then
                            local t = obj.Text
                            if t and #t > 2 and not t:match("^%s*$") then
                                found = t; break
                            end
                        end
                    end
                end)
                if found then
                    _HR_RPT.nameLbl.Text = found
                    _HR_RPT.nameLbl.TextColor3 = Color3.fromRGB(80,220,80)
                else
                    _HR_RPT.nameLbl.Text = "GUID captured — nama tidak terbaca"
                    _HR_RPT.nameLbl.TextColor3 = Color3.fromRGB(255,200,60)
                end
            else
                _HR_RPT.nameLbl.Text = "Silahkan Reroll 1x dulu di mesin Hero"
                _HR_RPT.nameLbl.TextColor3 = Color3.fromRGB(180,220,255)
            end
        end,
        SetToggleOff = function() end,  -- diisi setelah toggle dibuat
    }

    -- Header dropdown
    local hrHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,38))
    hrHeader.LayoutOrder = 1; Corner(hrHeader,8); Stroke(hrHeader,C.BORD,1,0.4)
    local hrIcon = Label(hrHeader,"▶",12,C.ACC2,Enum.Font.GothamBold)
    hrIcon.Size = UDim2.new(0,20,1,0); hrIcon.Position = UDim2.new(0,10,0,0)
    local hrLabel = Label(hrHeader,"Hero Fastroll",13,C.TXT,Enum.Font.GothamBold)
    hrLabel.Size = UDim2.new(1,-40,1,0); hrLabel.Position = UDim2.new(0,30,0,0)

    local hrBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
    hrBody.LayoutOrder = 2; hrBody.ClipsDescendants = true
    Corner(hrBody,8); Stroke(hrBody,C.BORD,1,0.3); hrBody.Visible = false

    local hrInner = Frame(hrBody, C.BLACK, UDim2.new(1,-16,0,0))
    hrInner.BackgroundTransparency = 1; hrInner.Position = UDim2.new(0,8,0,8)
    local hrLayout = New("UIListLayout",{Parent=hrInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8)})

    local function ResizeHRBody()
        hrLayout:ApplyLayout()
        local h = hrLayout.AbsoluteContentSize.Y + 20
        hrInner.Size = UDim2.new(1,0,0,h); hrBody.Size = UDim2.new(1,0,0,h+16)
    end

    -- Card laporan (1 kotak besar)
    local rptCard = Frame(hrInner, C.SURFACE, UDim2.new(1,0,0,0))
    rptCard.LayoutOrder = 1; Corner(rptCard,8); Stroke(rptCard,C.BORD,1,0.4)
    rptCard.AutomaticSize = Enum.AutomaticSize.Y
    local rptPad = Instance.new("UIPadding", rptCard)
    rptPad.PaddingLeft=UDim.new(0,10); rptPad.PaddingRight=UDim.new(0,10)
    rptPad.PaddingTop=UDim.new(0,8);  rptPad.PaddingBottom=UDim.new(0,8)
    New("UIListLayout",{Parent=rptCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})

    -- Nama hero
    local nameRow = Frame(rptCard, Color3.fromRGB(35,35,35), UDim2.new(1,0,0,26))
    nameRow.LayoutOrder = 0; Corner(nameRow,6)
    local namePre = Label(nameRow,"Hero :",11,C.TXT3,Enum.Font.GothamBold)
    namePre.Size=UDim2.new(0,46,1,0); namePre.Position=UDim2.new(0,8,0,0)
    namePre.TextXAlignment=Enum.TextXAlignment.Left
    local nameLbl = Label(nameRow,"Silahkan Reroll 1x dulu di mesin Hero",11,Color3.fromRGB(180,220,255),Enum.Font.Gotham)
    nameLbl.Size=UDim2.new(1,-58,1,0); nameLbl.Position=UDim2.new(0,54,0,0)
    nameLbl.TextXAlignment=Enum.TextXAlignment.Left
    nameLbl.TextTruncate=Enum.TextTruncate.AtEnd
    _HR_RPT.nameLbl = nameLbl

    -- Status slot 1-3
    local slotNames = {"Slot 1","Slot 2","Slot 3"}
    for i = 1, 3 do
        local sRow = Frame(rptCard, Color3.fromRGB(28,28,28), UDim2.new(1,0,0,24))
        sRow.LayoutOrder = i; Corner(sRow,5)
        local sPre = Label(sRow,slotNames[i].." :",11,C.TXT3,Enum.Font.GothamBold)
        sPre.Size=UDim2.new(0,46,1,0); sPre.Position=UDim2.new(0,8,0,0)
        sPre.TextXAlignment=Enum.TextXAlignment.Left
        local sLbl = Label(sRow,"Idle",11,Color3.fromRGB(160,148,135),Enum.Font.Gotham)
        sLbl.Size=UDim2.new(1,-58,1,0); sLbl.Position=UDim2.new(0,54,0,0)
        sLbl.TextXAlignment=Enum.TextXAlignment.Left
        sLbl.TextTruncate=Enum.TextTruncate.AtEnd
        _HR_RPT.slotLbls[i] = sLbl
    end

    -- Divider
    local div1 = Frame(hrInner, Color3.fromRGB(60,60,60), UDim2.new(1,0,0,1))
    div1.LayoutOrder = 2; div1.BackgroundTransparency = 0.5

    -- Dropdown target per slot
    for si = 1, 3 do
        local si_l = si
        local tRow = Frame(hrInner, C.BG2, UDim2.new(1,0,0,32))
        tRow.LayoutOrder = 2 + si; Corner(tRow,6)

        local tLbl = Label(tRow,"Target "..slotNames[si].." :",11,C.TXT,Enum.Font.GothamBold)
        tLbl.Size=UDim2.new(0,92,1,0); tLbl.Position=UDim2.new(0,8,0,0)
        tLbl.TextXAlignment=Enum.TextXAlignment.Left

        local tDdBtn = Btn(tRow, C.DD_BG, UDim2.new(1,-108,0,24))
        tDdBtn.Position=UDim2.new(0,100,0.5,-12); Corner(tDdBtn,5); Stroke(tDdBtn,C.BORD2,1,0.3)
        local tDdLbl = Label(tDdBtn,"-- pilih quirk --",10,C.TXT2,Enum.Font.Gotham,Enum.TextXAlignment.Left)
        tDdLbl.Size=UDim2.new(1,-20,1,0); tDdLbl.Position=UDim2.new(0,7,0,0)
        tDdLbl.TextTruncate=Enum.TextTruncate.AtEnd
        local tArrow = Label(tDdBtn,"▼",9,C.ACC,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        tArrow.Size=UDim2.new(0,14,1,0); tArrow.Position=UDim2.new(1,-16,0,0)

        MakeGenericDropdown({
            ddBtn    = tDdBtn,
            list     = QUIRK_LIST_PER_SLOT[si_l],
            maxSel   = MAX_PER_SLOT,
            selTable = _HR_RPT.slotTarget[si_l],
            onRefresh = function()
                local names = {}
                for _, q in ipairs(QUIRK_LIST_PER_SLOT[si_l]) do
                    if _HR_RPT.slotTarget[si_l][q.id] then
                        table.insert(names, q.name)
                    end
                end
                tDdLbl.Text = #names > 0 and table.concat(names," / ") or "-- pilih quirk --"
                tDdLbl.TextColor3 = #names > 0 and C.ACC2 or C.TXT2
            end,
        })
    end

    -- Toggle Auto Roll Hero
    local toggleRow = Frame(hrInner, Color3.fromRGB(40,25,10), UDim2.new(1,0,0,34))
    toggleRow.LayoutOrder = 7; Corner(toggleRow,8); Stroke(toggleRow,C.ACC,1,0.7)
    local tgLbl = Label(toggleRow,"Auto Roll Hero",12,C.TXT,Enum.Font.GothamBold)
    tgLbl.Size=UDim2.new(0.55,0,1,0); tgLbl.Position=UDim2.new(0,10,0,0)
    local tgSub = Label(toggleRow,"ON = mulai roll otomatis",9,C.TXT3,Enum.Font.Gotham)
    tgSub.Size=UDim2.new(0.55,0,0,12); tgSub.Position=UDim2.new(0,10,1,-14)
    local hrPill = Btn(toggleRow,Color3.fromRGB(60,60,60),UDim2.new(0,40,0,22))
    hrPill.Position=UDim2.new(1,-50,0.5,-11); Corner(hrPill,11)
    local hrKnob = Frame(hrPill,C.TXT,UDim2.new(0,18,0,18))
    hrKnob.Position=UDim2.new(0,2,0.5,-9); Corner(hrKnob,9)

    local function SetHeroToggleUI(on)
        TweenService:Create(hrPill,TweenInfo.new(0.15),{BackgroundColor3=on and Color3.fromRGB(60,180,60) or Color3.fromRGB(60,60,60)}):Play()
        TweenService:Create(hrKnob,TweenInfo.new(0.15),{
            Position=on and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9),
            BackgroundColor3=on and Color3.fromRGB(255,255,255) or C.TXT,
        }):Play()
    end

    _HR_RPT.SetToggleOff = function()
        _HR_RPT.running = false
        SetHeroToggleUI(false)
    end

    hrPill.MouseButton1Click:Connect(function()
        _HR_RPT.running = not _HR_RPT.running
        SetHeroToggleUI(_HR_RPT.running)
        if _HR_RPT.running then
            DoAutoRollHero(true)
        else
            DoAutoRollHero(false)
        end
    end)

    hrHeader.MouseButton1Click:Connect(function()
        hrOpen = not hrOpen
        hrBody.Visible = hrOpen
        hrIcon.Text = hrOpen and "▼" or "▶"
        if hrOpen then task.defer(ResizeHRBody) end
    end)
end)()

-- ============================================================
-- PANEL : WEAPON FASTROLL
-- ============================================================
;(function()
    local p = Panels["autoroll"]
    local wrOpen = false

    _WR_RPT = {
        guid     = "",
        nameLbl  = nil,
        slotLbls = {nil,nil,nil},
        slotTarget = {{},{},{}},
        running  = false,
        SetSlot  = function(i,txt,col)
            if _WR_RPT.slotLbls[i] then
                _WR_RPT.slotLbls[i].Text = txt
                _WR_RPT.slotLbls[i].TextColor3 = col or Color3.fromRGB(160,148,135)
            end
        end,
        Refresh  = function()
            if not _WR_RPT.nameLbl then return end
            if _WR_RPT.guid and _WR_RPT.guid ~= "" then
                _WR_RPT.nameLbl.Text = "Terdeteksi"
                _WR_RPT.nameLbl.TextColor3 = Color3.fromRGB(80,220,80)
            else
                _WR_RPT.nameLbl.Text = "Silahkan Reroll 1x dulu di mesin Weapon"
                _WR_RPT.nameLbl.TextColor3 = Color3.fromRGB(180,220,255)
            end
        end,
        SetToggleOff = function() end,
    }

    local wrHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,38))
    wrHeader.LayoutOrder = 10; Corner(wrHeader,8); Stroke(wrHeader,C.BORD,1,0.4)
    local wrIcon = Label(wrHeader,"▶",12,C.ACC2,Enum.Font.GothamBold)
    wrIcon.Size=UDim2.new(0,20,1,0); wrIcon.Position=UDim2.new(0,10,0,0)
    local wrLabel = Label(wrHeader,"Weapon Fastroll",13,C.TXT,Enum.Font.GothamBold)
    wrLabel.Size=UDim2.new(1,-40,1,0); wrLabel.Position=UDim2.new(0,30,0,0)

    local wrBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
    wrBody.LayoutOrder=11; wrBody.ClipsDescendants=true
    Corner(wrBody,8); Stroke(wrBody,C.BORD,1,0.3); wrBody.Visible=false

    local wrInner = Frame(wrBody, C.BLACK, UDim2.new(1,-16,0,0))
    wrInner.BackgroundTransparency=1; wrInner.Position=UDim2.new(0,8,0,8)
    local wrLayout = New("UIListLayout",{Parent=wrInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8)})

    local function ResizeWRBody()
        wrLayout:ApplyLayout()
        local h = wrLayout.AbsoluteContentSize.Y + 20
        wrInner.Size=UDim2.new(1,0,0,h); wrBody.Size=UDim2.new(1,0,0,h+16)
    end

    -- Card laporan
    local rptCard = Frame(wrInner, C.SURFACE, UDim2.new(1,0,0,0))
    rptCard.LayoutOrder=1; Corner(rptCard,8); Stroke(rptCard,C.BORD,1,0.4)
    rptCard.AutomaticSize=Enum.AutomaticSize.Y
    local rptPad = Instance.new("UIPadding",rptCard)
    rptPad.PaddingLeft=UDim.new(0,10); rptPad.PaddingRight=UDim.new(0,10)
    rptPad.PaddingTop=UDim.new(0,8);  rptPad.PaddingBottom=UDim.new(0,8)
    New("UIListLayout",{Parent=rptCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})

    local nameRow = Frame(rptCard, Color3.fromRGB(35,35,35), UDim2.new(1,0,0,26))
    nameRow.LayoutOrder=0; Corner(nameRow,6)
    local namePre = Label(nameRow,"Weapon :",11,C.TXT3,Enum.Font.GothamBold)
    namePre.Size=UDim2.new(0,58,1,0); namePre.Position=UDim2.new(0,8,0,0)
    namePre.TextXAlignment=Enum.TextXAlignment.Left
    local nameLbl = Label(nameRow,"Silahkan Reroll 1x dulu di mesin Weapon",11,Color3.fromRGB(180,220,255),Enum.Font.Gotham)
    nameLbl.Size=UDim2.new(1,-70,1,0); nameLbl.Position=UDim2.new(0,66,0,0)
    nameLbl.TextXAlignment=Enum.TextXAlignment.Left
    nameLbl.TextTruncate=Enum.TextTruncate.AtEnd
    _WR_RPT.nameLbl = nameLbl

    local slotNames = {"Slot 1","Slot 2","Slot 3"}
    for i = 1, 3 do
        local sRow = Frame(rptCard, Color3.fromRGB(28,28,28), UDim2.new(1,0,0,24))
        sRow.LayoutOrder=i; Corner(sRow,5)
        local sPre = Label(sRow,slotNames[i].." :",11,C.TXT3,Enum.Font.GothamBold)
        sPre.Size=UDim2.new(0,46,1,0); sPre.Position=UDim2.new(0,8,0,0)
        sPre.TextXAlignment=Enum.TextXAlignment.Left
        local sLbl = Label(sRow,"Idle",11,Color3.fromRGB(160,148,135),Enum.Font.Gotham)
        sLbl.Size=UDim2.new(1,-58,1,0); sLbl.Position=UDim2.new(0,54,0,0)
        sLbl.TextXAlignment=Enum.TextXAlignment.Left
        sLbl.TextTruncate=Enum.TextTruncate.AtEnd
        _WR_RPT.slotLbls[i] = sLbl
    end

    local div1 = Frame(wrInner, Color3.fromRGB(60,60,60), UDim2.new(1,0,0,1))
    div1.LayoutOrder=2; div1.BackgroundTransparency=0.5

    for si = 1, 3 do
        local si_l = si
        local tRow = Frame(wrInner, C.BG2, UDim2.new(1,0,0,32))
        tRow.LayoutOrder=2+si; Corner(tRow,6)

        local tLbl = Label(tRow,"Target "..slotNames[si].." :",11,C.TXT,Enum.Font.GothamBold)
        tLbl.Size=UDim2.new(0,92,1,0); tLbl.Position=UDim2.new(0,8,0,0)
        tLbl.TextXAlignment=Enum.TextXAlignment.Left

        local tDdBtn = Btn(tRow, C.DD_BG, UDim2.new(1,-108,0,24))
        tDdBtn.Position=UDim2.new(0,100,0.5,-12); Corner(tDdBtn,5); Stroke(tDdBtn,C.BORD2,1,0.3)
        local tDdLbl = Label(tDdBtn,"-- pilih quirk --",10,C.TXT2,Enum.Font.Gotham,Enum.TextXAlignment.Left)
        tDdLbl.Size=UDim2.new(1,-20,1,0); tDdLbl.Position=UDim2.new(0,7,0,0)
        tDdLbl.TextTruncate=Enum.TextTruncate.AtEnd
        local tArrow = Label(tDdBtn,"▼",9,C.ACC,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        tArrow.Size=UDim2.new(0,14,1,0); tArrow.Position=UDim2.new(1,-16,0,0)

        MakeGenericDropdown({
            ddBtn    = tDdBtn,
            list     = W_QUIRK_LIST_PER_SLOT[si_l],
            maxSel   = W_MAX_PER_SLOT,
            selTable = _WR_RPT.slotTarget[si_l],
            onRefresh = function()
                local names = {}
                for _, q in ipairs(W_QUIRK_LIST_PER_SLOT[si_l]) do
                    if _WR_RPT.slotTarget[si_l][q.id] then
                        table.insert(names, q.name)
                    end
                end
                tDdLbl.Text = #names > 0 and table.concat(names," / ") or "-- pilih quirk --"
                tDdLbl.TextColor3 = #names > 0 and C.ACC2 or C.TXT2
            end,
        })
    end

    local toggleRow = Frame(wrInner, Color3.fromRGB(40,25,10), UDim2.new(1,0,0,34))
    toggleRow.LayoutOrder=7; Corner(toggleRow,8); Stroke(toggleRow,C.ACC,1,0.7)
    local tgLbl = Label(toggleRow,"Auto Roll Weapon",12,C.TXT,Enum.Font.GothamBold)
    tgLbl.Size=UDim2.new(0.55,0,1,0); tgLbl.Position=UDim2.new(0,10,0,0)
    local tgSub = Label(toggleRow,"ON = mulai roll otomatis",9,C.TXT3,Enum.Font.Gotham)
    tgSub.Size=UDim2.new(0.55,0,0,12); tgSub.Position=UDim2.new(0,10,1,-14)
    local wrPill = Btn(toggleRow,Color3.fromRGB(60,60,60),UDim2.new(0,40,0,22))
    wrPill.Position=UDim2.new(1,-50,0.5,-11); Corner(wrPill,11)
    local wrKnob = Frame(wrPill,C.TXT,UDim2.new(0,18,0,18))
    wrKnob.Position=UDim2.new(0,2,0.5,-9); Corner(wrKnob,9)

    local function SetWeaponToggleUI(on)
        TweenService:Create(wrPill,TweenInfo.new(0.15),{BackgroundColor3=on and Color3.fromRGB(60,180,60) or Color3.fromRGB(60,60,60)}):Play()
        TweenService:Create(wrKnob,TweenInfo.new(0.15),{
            Position=on and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9),
            BackgroundColor3=on and Color3.fromRGB(255,255,255) or C.TXT,
        }):Play()
    end

    _WR_RPT.SetToggleOff = function()
        _WR_RPT.running = false
        SetWeaponToggleUI(false)
    end

    wrPill.MouseButton1Click:Connect(function()
        _WR_RPT.running = not _WR_RPT.running
        SetWeaponToggleUI(_WR_RPT.running)
        if _WR_RPT.running then
            DoAutoRollWeapon(true)
        else
            DoAutoRollWeapon(false)
        end
    end)

    wrHeader.MouseButton1Click:Connect(function()
        wrOpen = not wrOpen
        wrBody.Visible = wrOpen
        wrIcon.Text = wrOpen and "▼" or "▶"
        if wrOpen then task.defer(ResizeWRBody) end
    end)
end)()

-- ============================================================
-- PANEL : AUTO ROLL — PET GEAR
-- ============================================================
;(function()
    local p = Panels["autoroll"]
    local pgOpen = false

    local pgHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,38))
    pgHeader.LayoutOrder = 20; Corner(pgHeader,8); Stroke(pgHeader,C.BORD,1,0.4)
    local pgIcon  = Label(pgHeader,"▶",12,C.ACC2,Enum.Font.GothamBold)
    pgIcon.Size   = UDim2.new(0,20,1,0); pgIcon.Position = UDim2.new(0,10,0,0)
    local pgLabel = Label(pgHeader,"🐾  Pet Gear Fastroll",13,C.TXT,Enum.Font.GothamBold)
    pgLabel.Size  = UDim2.new(1,-40,1,0); pgLabel.Position = UDim2.new(0,30,0,0)

    local pgBody  = Frame(p, C.BG2, UDim2.new(1,0,0,0))
    pgBody.LayoutOrder = 21; pgBody.ClipsDescendants = true
    Corner(pgBody,8); Stroke(pgBody,C.BORD,1,0.3); pgBody.Visible = false

    local pgInner = Frame(pgBody, C.BLACK, UDim2.new(1,-16,0,0))
    pgInner.BackgroundTransparency = 1; pgInner.Position = UDim2.new(0,8,0,8)
    local pgLayout = New("UIListLayout",{Parent=pgInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8)})

    function ResizePGBody()
        pgLayout:ApplyLayout()
        local h = pgLayout.AbsoluteContentSize.Y + 20
        pgInner.Size = UDim2.new(1,0,0,h); pgBody.Size = UDim2.new(1,0,0,h+16)
    end

    for msi = 1, 3 do
        local msi_l = msi

        local mCard = Frame(pgInner, C.SURFACE, UDim2.new(1,0,0,0))
        mCard.LayoutOrder = msi; Corner(mCard,8); Stroke(mCard,C.BORD,1,0.5)
        mCard.AutomaticSize = Enum.AutomaticSize.Y
        local mPad = Instance.new("UIPadding", mCard)
        mPad.PaddingLeft=UDim.new(0,12); mPad.PaddingRight=UDim.new(0,12)
        mPad.PaddingTop=UDim.new(0,10);  mPad.PaddingBottom=UDim.new(0,10)
        New("UIListLayout",{Parent=mCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

        local mTitle = Label(mCard,"🐾 "..PG_MACHINE_NAMES[msi],12,C.ACC2,Enum.Font.GothamBold)
        mTitle.Size = UDim2.new(1,0,0,18); mTitle.LayoutOrder = 0

        local statRow = Frame(mCard, Color3.fromRGB(35,35,35), UDim2.new(1,0,0,26))
        statRow.LayoutOrder = 1; Corner(statRow,6); Stroke(statRow,C.BORD2,1,0.5)
        local mDot = Frame(statRow, Color3.fromRGB(100,100,100), UDim2.new(0,8,0,8))
        mDot.Position = UDim2.new(0,7,0.5,-4); Corner(mDot,4)
        PGR.dotRefs[msi] = mDot
        local mStLbl = Label(statRow,"⏹ Idle — Pilih target & aktifkan Roll",10,C.TXT2,Enum.Font.Gotham)
        mStLbl.Size = UDim2.new(1,-22,1,0); mStLbl.Position = UDim2.new(0,21,0,0)
        mStLbl.TextTruncate = Enum.TextTruncate.AtEnd
        PGR.statLbls[msi] = mStLbl

        local infoRow = Frame(mCard, Color3.fromRGB(28,28,28), UDim2.new(1,0,0,22))
        infoRow.LayoutOrder = 2; Corner(infoRow,5)
        local attLbl = Label(infoRow,"Attempt: —",9.5,C.TXT3,Enum.Font.Gotham)
        attLbl.Size = UDim2.new(0.5,0,1,0); attLbl.Position = UDim2.new(0,8,0,0)
        PGR.attemptLbls[msi] = attLbl
        local lastLbl = Label(infoRow,"Last: —",9.5,Color3.fromRGB(180,180,180),Enum.Font.Gotham,Enum.TextXAlignment.Right)
        lastLbl.Size = UDim2.new(0.5,-10,1,0); lastLbl.Position = UDim2.new(0.5,0,0,0)
        PGR.lastLbls[msi] = lastLbl

        local divLine = Frame(mCard, Color3.fromRGB(60,60,60), UDim2.new(1,0,0,1))
        divLine.LayoutOrder = 3; divLine.BackgroundTransparency = 0.5

        local tRow = Frame(mCard, C.BG2, UDim2.new(1,0,0,32))
        tRow.LayoutOrder = 4; Corner(tRow,6)
        local tLbl = Label(tRow,"🎯 Target:",11,C.TXT,Enum.Font.GothamBold)
        tLbl.Size = UDim2.new(0,72,1,0); tLbl.Position = UDim2.new(0,8,0,0)

        local tDdBtn = Btn(tRow, C.DD_BG, UDim2.new(1,-88,0,24))
        tDdBtn.Position = UDim2.new(0,80,0.5,-12); Corner(tDdBtn,5); Stroke(tDdBtn,C.BORD2,1,0.3)
        local tDdLbl = Label(tDdBtn,"-- pilih grade --",10,C.TXT2,Enum.Font.Gotham,Enum.TextXAlignment.Left)
        tDdLbl.Size = UDim2.new(1,-20,1,0); tDdLbl.Position = UDim2.new(0,7,0,0)
        tDdLbl.TextTruncate = Enum.TextTruncate.AtEnd
        PGR.sumLbls[msi] = tDdLbl
        local tArrow = Label(tDdBtn,"▼",9,C.ACC,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        tArrow.Size = UDim2.new(0,14,1,0); tArrow.Position = UDim2.new(1,-16,0,0)

        local tHint = Label(tRow,"(maks 3)",8.5,C.TXT3,Enum.Font.Gotham,Enum.TextXAlignment.Right)
        tHint.Size = UDim2.new(0,0,1,0); tHint.AutomaticSize = Enum.AutomaticSize.X
        tHint.Position = UDim2.new(1,-4,0,0); tHint.AnchorPoint = Vector2.new(1,0)

        function onTargetChange()
            local names = {}
            for _, g in ipairs(PG_GRADES_PER_MACHINE[msi_l]) do
                if PGR.targets[msi_l][g.id] then names[#names+1] = g.name end
            end
            if PGR.sumLbls[msi_l] then
                PGR.sumLbls[msi_l].Text = #names > 0 and table.concat(names," / ") or "-- pilih grade --"
                PGR.sumLbls[msi_l].TextColor3 = #names > 0 and C.ACC2 or C.TXT2
            end
            if PGR.running[msi_l] and PGR.statLbls[msi_l] then
                if #names == 0 then
                    PGR.statLbls[msi_l].Text = "⚠ Target dikosongkan!"
                    PGR.statLbls[msi_l].TextColor3 = Color3.fromRGB(255,100,80)
                else
                    PGR.statLbls[msi_l].Text = "🔄 Target → "..table.concat(names," / ")
                    PGR.statLbls[msi_l].TextColor3 = Color3.fromRGB(255,200,60)
                end
            end
        end

        MakeGenericDropdown({
            ddBtn      = tDdBtn,
            list       = PG_GRADES_PER_MACHINE[msi],
            maxSel     = 3,
            selTable   = PGR.targets[msi],
            onRefresh  = onTargetChange,
        })

        local enRow = Frame(mCard, Color3.fromRGB(40,25,10), UDim2.new(1,0,0,34))
        enRow.LayoutOrder = 5; Corner(enRow,8); Stroke(enRow,C.ACC,1,0.7)

        local enLbl = Label(enRow,"⚡ Fastroll",12,C.TXT,Enum.Font.GothamBold)
        enLbl.Size = UDim2.new(0.55,0,1,0); enLbl.Position = UDim2.new(0,10,0,0)
        local enSub = Label(enRow,"ON = mulai roll otomatis",9,C.TXT3,Enum.Font.Gotham)
        enSub.Size = UDim2.new(0.55,0,0,12); enSub.Position = UDim2.new(0,10,1,-14)

        local enToggle = Btn(enRow, Color3.fromRGB(60,60,60), UDim2.new(0,40,0,22))
        enToggle.Position = UDim2.new(1,-50,0.5,-11); Corner(enToggle,11)
        local enKnob = Frame(enToggle, C.TXT, UDim2.new(0,18,0,18))
        enKnob.Position = UDim2.new(0,2,0.5,-9); Corner(enKnob,9)

        PGR.toggleBtns[msi]  = enToggle
        PGR.toggleKnobs[msi] = enKnob

        enToggle.MouseButton1Click:Connect(function()
            PGR.enOnFlags[msi_l] = not PGR.enOnFlags[msi_l]
            local enOn = PGR.enOnFlags[msi_l]
            enToggle.BackgroundColor3 = enOn and C.ACC or Color3.fromRGB(60,60,60)
            enKnob.Position = enOn and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
            enRow.BackgroundColor3 = enOn and Color3.fromRGB(60,30,0) or Color3.fromRGB(40,25,10)
            Stroke(enRow, enOn and Color3.fromRGB(255,140,0) or C.ACC, 1, enOn and 0.3 or 0.7)
            DoAutoRollPetGear(msi_l, enOn)
        end)
    end

    pgHeader.MouseButton1Click:Connect(function()
        pgOpen = not pgOpen
        pgBody.Visible = pgOpen
        pgIcon.Text = pgOpen and "▼" or "▶"
        if pgOpen then task.defer(ResizePGBody) end
    end)
end)()

-- ============================================================
-- PANEL : AUTO ROLL — HALO
-- ============================================================
;(function()
    local p = Panels["autoroll"]
    local haloOpen = false

    local haloHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,38))
    haloHeader.LayoutOrder = 30; Corner(haloHeader,8); Stroke(haloHeader,C.BORD,1,0.4)
    local haloIcon  = Label(haloHeader,"▶",12,C.ACC2,Enum.Font.GothamBold)
    haloIcon.Size   = UDim2.new(0,20,1,0); haloIcon.Position = UDim2.new(0,10,0,0)
    local haloLabel = Label(haloHeader,"😇  Auto Gacha Halo",13,C.TXT,Enum.Font.GothamBold)
    haloLabel.Size  = UDim2.new(1,-40,1,0); haloLabel.Position = UDim2.new(0,30,0,0)

    local haloBody  = Frame(p, C.BG2, UDim2.new(1,0,0,0))
    haloBody.LayoutOrder = 31; haloBody.ClipsDescendants = true
    Corner(haloBody,8); Stroke(haloBody,C.BORD,1,0.3); haloBody.Visible = false

    local haloInner = Frame(haloBody, C.BLACK, UDim2.new(1,-16,0,0))
    haloInner.BackgroundTransparency = 1; haloInner.Position = UDim2.new(0,8,0,8)
    local haloLayout = New("UIListLayout",{Parent=haloInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8)})

    function ResizeHaloBody()
        haloLayout:ApplyLayout()
        local h = haloLayout.AbsoluteContentSize.Y + 20
        haloInner.Size = UDim2.new(1,0,0,h); haloBody.Size = UDim2.new(1,0,0,h+16)
    end

    local HALO_COLORS = {Color3.fromRGB(180,100,40), Color3.fromRGB(220,180,30), Color3.fromRGB(100,200,255)}
    local HALO_ICONS  = {"🥉","🥇","💠"}

    for hi = 1, 3 do
        local hi_l = hi

        local hCard = Frame(haloInner, C.SURFACE, UDim2.new(1,0,0,0))
        hCard.LayoutOrder = hi; Corner(hCard,8); Stroke(hCard,C.BORD,1,0.5)
        hCard.AutomaticSize = Enum.AutomaticSize.Y
        local hPad = Instance.new("UIPadding", hCard)
        hPad.PaddingLeft=UDim.new(0,12); hPad.PaddingRight=UDim.new(0,12)
        hPad.PaddingTop=UDim.new(0,10);  hPad.PaddingBottom=UDim.new(0,10)
        New("UIListLayout",{Parent=hCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

        local hTitle = Label(hCard, HALO_ICONS[hi].." "..HALO_NAMES[hi], 12, HALO_COLORS[hi], Enum.Font.GothamBold)
        hTitle.Size = UDim2.new(1,0,0,18); hTitle.LayoutOrder = 0

        local statRow = Frame(hCard, Color3.fromRGB(35,35,35), UDim2.new(1,0,0,26))
        statRow.LayoutOrder = 1; Corner(statRow,6); Stroke(statRow,C.BORD2,1,0.5)
        local hDot = Frame(statRow, Color3.fromRGB(100,100,100), UDim2.new(0,8,0,8))
        hDot.Position = UDim2.new(0,7,0.5,-4); Corner(hDot,4)
        HALO.dotRefs[hi] = hDot
        local hStLbl = Label(statRow,"⏹ Idle — Aktifkan untuk mulai gacha",10,C.TXT2,Enum.Font.Gotham)
        hStLbl.Size = UDim2.new(1,-22,1,0); hStLbl.Position = UDim2.new(0,21,0,0)
        hStLbl.TextTruncate = Enum.TextTruncate.AtEnd
        HALO.statLbls[hi] = hStLbl

        local infoRow = Frame(hCard, Color3.fromRGB(28,28,28), UDim2.new(1,0,0,22))
        infoRow.LayoutOrder = 2; Corner(infoRow,5)
        local attLbl = Label(infoRow,"Attempt: —",9.5,C.TXT3,Enum.Font.Gotham)
        attLbl.Size = UDim2.new(1,-8,1,0); attLbl.Position = UDim2.new(0,8,0,0)
        HALO.attemptLbls[hi] = attLbl

        local enRow = Frame(hCard, Color3.fromRGB(30,20,5), UDim2.new(1,0,0,34))
        enRow.LayoutOrder = 4; Corner(enRow,8); Stroke(enRow, HALO_COLORS[hi], 1, 0.6)

        local enLbl = Label(enRow,"⚡ Auto Gacha",12,C.TXT,Enum.Font.GothamBold)
        enLbl.Size = UDim2.new(0.6,0,1,0); enLbl.Position = UDim2.new(0,10,0,0)
        local enSub = Label(enRow,"ON = mulai gacha otomatis",9,C.TXT3,Enum.Font.Gotham)
        enSub.Size = UDim2.new(0.6,0,0,12); enSub.Position = UDim2.new(0,10,1,-14)

        local enToggle = Btn(enRow, Color3.fromRGB(60,60,60), UDim2.new(0,40,0,22))
        enToggle.Position = UDim2.new(1,-50,0.5,-11); Corner(enToggle,11)
        local enKnob = Frame(enToggle, C.TXT, UDim2.new(0,18,0,18))
        enKnob.Position = UDim2.new(0,2,0.5,-9); Corner(enKnob,9)

        HALO.toggleBtns[hi]  = enToggle
        HALO.toggleKnobs[hi] = enKnob

        enToggle.MouseButton1Click:Connect(function()
            HALO.enOnFlags[hi_l] = not HALO.enOnFlags[hi_l]
            local enOn = HALO.enOnFlags[hi_l]
            enToggle.BackgroundColor3 = enOn and HALO_COLORS[hi_l] or Color3.fromRGB(60,60,60)
            enKnob.Position = enOn and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
            enRow.BackgroundColor3 = enOn and Color3.fromRGB(50,35,5) or Color3.fromRGB(30,20,5)
            Stroke(enRow, HALO_COLORS[hi_l], 1, enOn and 0.2 or 0.6)
            DoAutoRollHalo(hi_l, enOn)
        end)
    end

    haloHeader.MouseButton1Click:Connect(function()
        haloOpen = not haloOpen
        haloBody.Visible = haloOpen
        haloIcon.Text = haloOpen and "▼" or "▶"
        if haloOpen then task.defer(ResizeHaloBody) end
    end)
end)()

-- ============================================================
-- PANEL : AUTO ROLL — ORNAMENT
-- ============================================================
;(function()
    local p = Panels["autoroll"]
    local ornOpen = false

    local ornHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,38))
    ornHeader.LayoutOrder = 35; Corner(ornHeader,8); Stroke(ornHeader,C.BORD,1,0.4)
    local ornIcon  = Label(ornHeader,"▶",12,C.ACC2,Enum.Font.GothamBold)
    ornIcon.Size   = UDim2.new(0,20,1,0); ornIcon.Position = UDim2.new(0,10,0,0)
    local ornLabel = Label(ornHeader,"💍  Auto Roll Ornament",13,C.TXT,Enum.Font.GothamBold)
    ornLabel.Size  = UDim2.new(1,-40,1,0); ornLabel.Position = UDim2.new(0,30,0,0)

    local ornBody  = Frame(p, C.BG2, UDim2.new(1,0,0,0))
    ornBody.LayoutOrder = 36; ornBody.ClipsDescendants = true
    Corner(ornBody,8); Stroke(ornBody,C.BORD,1,0.3); ornBody.Visible = false

    local ornInner = Frame(ornBody, C.BLACK, UDim2.new(1,-16,0,0))
    ornInner.BackgroundTransparency = 1; ornInner.Position = UDim2.new(0,8,0,8)
    ornInner.AutomaticSize = Enum.AutomaticSize.Y
    local ornLayout = New("UIListLayout",{Parent=ornInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8)})
    Instance.new("UIPadding", ornInner).PaddingBottom = UDim.new(0, 12)

    function ResizeOrnBody()
        ornLayout:ApplyLayout()
        local h = ornLayout.AbsoluteContentSize.Y + 28
        ornInner.Size = UDim2.new(1,0,0,h)
        ornBody.Size = UDim2.new(1,0,0,h+16)
    end

    local ORN_COLORS = {
        Color3.fromRGB(200,160,255),
        Color3.fromRGB(255,180,100),
        Color3.fromRGB(100,220,180),
        Color3.fromRGB(255,120,120),
        Color3.fromRGB(120,200,255),
        Color3.fromRGB(200,255,120),
    }
    local ORN_ICONS = {"👑","💎","💰","🌑","🌿","⚡"}

    -- Info cara pakai
    local infoCard = Frame(ornInner, Color3.fromRGB(30,15,5), UDim2.new(1,0,0,0))
    infoCard.LayoutOrder = 0; infoCard.AutomaticSize = Enum.AutomaticSize.Y
    Corner(infoCard,7); Stroke(infoCard,C.ACC,1,0.5)
    local infoPad = Instance.new("UIPadding",infoCard)
    infoPad.PaddingLeft=UDim.new(0,10); infoPad.PaddingRight=UDim.new(0,10)
    infoPad.PaddingTop=UDim.new(0,7);   infoPad.PaddingBottom=UDim.new(0,7)
    local infoLbl = Label(infoCard,
        "💡 Aktifkan toggle Fastroll untuk mulai roll otomatis tanpa berhenti.",
        9.5, Color3.fromRGB(230,210,170), Enum.Font.Gotham)
    infoLbl.Size = UDim2.new(1,0,0,0); infoLbl.AutomaticSize = Enum.AutomaticSize.Y
    infoLbl.TextWrapped = true; infoLbl.LayoutOrder = 0

    for mi = 1, #_ASH_ORN.MACHINES do
        local mi_l = mi
        local mInfo = _ASH_ORN.MACHINES[mi]

        local mCard = Frame(ornInner, C.SURFACE, UDim2.new(1,0,0,0))
        mCard.LayoutOrder = mi; Corner(mCard,8); Stroke(mCard,C.BORD,1,0.5)
        mCard.AutomaticSize = Enum.AutomaticSize.Y
        local mPad = Instance.new("UIPadding", mCard)
        mPad.PaddingLeft=UDim.new(0,12); mPad.PaddingRight=UDim.new(0,12)
        mPad.PaddingTop=UDim.new(0,10);  mPad.PaddingBottom=UDim.new(0,10)
        New("UIListLayout",{Parent=mCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

        -- Title
        local mTitle = Label(mCard, ORN_ICONS[mi].." "..mInfo.name, 12, ORN_COLORS[mi], Enum.Font.GothamBold)
        mTitle.Size = UDim2.new(1,0,0,18); mTitle.LayoutOrder = 0

        -- Status row
        local statRow = Frame(mCard, Color3.fromRGB(35,35,35), UDim2.new(1,0,0,26))
        statRow.LayoutOrder = 1; Corner(statRow,6); Stroke(statRow,C.BORD2,1,0.5)
        local mDot = Frame(statRow, Color3.fromRGB(100,100,100), UDim2.new(0,8,0,8))
        mDot.Position = UDim2.new(0,7,0.5,-4); Corner(mDot,4)
        ORN.dotRefs[mi] = mDot
        local mStLbl = Label(statRow,"⏹ Idle — Pilih target & aktifkan Roll",10,C.TXT2,Enum.Font.Gotham)
        mStLbl.Size = UDim2.new(1,-22,1,0); mStLbl.Position = UDim2.new(0,21,0,0)
        mStLbl.TextTruncate = Enum.TextTruncate.AtEnd
        ORN.statLbls[mi] = mStLbl

        -- Info attempt & last
        local infoRow = Frame(mCard, Color3.fromRGB(28,28,28), UDim2.new(1,0,0,22))
        infoRow.LayoutOrder = 2; Corner(infoRow,5)
        local attLbl = Label(infoRow,"Attempt: —",9.5,C.TXT3,Enum.Font.Gotham)
        attLbl.Size = UDim2.new(0.5,0,1,0); attLbl.Position = UDim2.new(0,8,0,0)
        ORN.attemptLbls[mi] = attLbl
        local lastLbl = Label(infoRow,"Last: —",9.5,Color3.fromRGB(180,180,180),Enum.Font.Gotham,Enum.TextXAlignment.Right)
        lastLbl.Size = UDim2.new(0.5,-10,1,0); lastLbl.Position = UDim2.new(0.5,0,0,0)
        ORN.lastLbls[mi] = lastLbl

        local divLine = Frame(mCard, Color3.fromRGB(60,60,60), UDim2.new(1,0,0,1))
        divLine.LayoutOrder = 3; divLine.BackgroundTransparency = 0.5

        -- Enable toggle
        local enRow = Frame(mCard, Color3.fromRGB(40,25,10), UDim2.new(1,0,0,34))
        enRow.LayoutOrder = 6; Corner(enRow,8); Stroke(enRow,ORN_COLORS[mi],1,0.7)

        local enLbl = Label(enRow,"⚡ Fastroll",12,C.TXT,Enum.Font.GothamBold)
        enLbl.Size = UDim2.new(0.55,0,1,0); enLbl.Position = UDim2.new(0,10,0,0)
        local enSub = Label(enRow,"ON = mulai roll otomatis",9,C.TXT3,Enum.Font.Gotham)
        enSub.Size = UDim2.new(0.55,0,0,12); enSub.Position = UDim2.new(0,10,1,-14)

        local enToggle = Btn(enRow, Color3.fromRGB(60,60,60), UDim2.new(0,40,0,22))
        enToggle.Position = UDim2.new(1,-50,0.5,-11); Corner(enToggle,11)
        local enKnob = Frame(enToggle, C.TXT, UDim2.new(0,18,0,18))
        enKnob.Position = UDim2.new(0,2,0.5,-9); Corner(enKnob,9)

        ORN.toggleBtns[mi]  = enToggle
        ORN.toggleKnobs[mi] = enKnob

        enToggle.MouseButton1Click:Connect(function()
            ORN.enOnFlags[mi_l] = not ORN.enOnFlags[mi_l]
            local enOn = ORN.enOnFlags[mi_l]
            enToggle.BackgroundColor3 = enOn and ORN_COLORS[mi_l] or Color3.fromRGB(60,60,60)
            enKnob.Position = enOn and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
            enRow.BackgroundColor3 = enOn and Color3.fromRGB(60,30,0) or Color3.fromRGB(40,25,10)
            Stroke(enRow, ORN_COLORS[mi_l], 1, enOn and 0.3 or 0.7)
            _ASH_ORN.DoRoll(mi_l, enOn)
        end)

        task.defer(ResizeOrnBody)
    end

    ornHeader.MouseButton1Click:Connect(function()
        ornOpen = not ornOpen
        ornBody.Visible = ornOpen
        ornIcon.Text = ornOpen and "▼" or "▶"
        if ornOpen then task.defer(ResizeOrnBody) end
    end)
end)()


;(function()
    local p = Panels["autoroll"]

end)()


-- ============================================================
;(function() -- [FIX] AutoRaid+Webhook: isolated scope
-- AUTO RAID : LOGIC (Data dari RaidSniffer v2)
-- Format confirmed:
--   UpdateRaidInfo → arg[1] = {
--     action   = "RemoveRaidEnters" | "AddRaidEnters"
--     raidInfos = {
--       [raidId(number)] = {
--         spawnName = "RE1001"/"RE1002"
--         endTime   = number
--         mapId     = number (50011, 50007, dst)
--         raidId    = number
--       }
--     }
--   }
-- ============================================================

-- RAID_LIVE: [raidId] = {raidId, mapId, spawnName, rank, label}
RAID_LIVE    = {}
RAID_ID_LIST = {}  -- sorted list untuk UI
_raidIdRefreshCb = nil

SPAWN_RANK = {
    RE1001 = 1, RE1002 = 2, RE1003 = 3, RE1004 = 4, RE1005 = 5, RE1006 = 6,
}
RANK_LABEL = {
    [1]="[D]", [2]="[M+]", [3]="[M++]",
    [4]="[S]", [5]="[XM]", [6]="[XM+]",
}
-- Nama map in-game (mapNum = mapId - 50000)
MAP_NAMES = {
    [1]  = "Shadow Gate City",
    [2]  = "Level Grinding Cavern",
    [3]  = "Shadow Castle",
    [4]  = "Seolhan Forest",
    [5]  = "Demon Castle - Tier 1",
    [6]  = "Orc Palace",
    [7]  = "Demon Castle - Tier 2",
    [8]  = "Ant Island",
    [9]  = "Land of Giant",
    [10] = "Plagueheart",
    [11] = "Umbralfrost Domain",
    [12] = "Kamish's Demise",
    [13] = "Lava Hell",
    [14] = "Illusory World",
    [15] = "Inferno Altar",
    [16] = "Shadow Throne",
    [17] = "Angel Holy Realm",
    [18] = "Golden Throne",
}

-- Koordinat spawn boss per map Raid (tpMapId = raidMapId + 100)
-- Karakter + hero langsung TP ke sini setelah masuk map
RAID_SPAWN_POS = {
    [50101] = Vector3.new(2424.9,  8.5,  482.9),  -- Map  1 Shadow Gate City
    [50102] = Vector3.new(1683.1,  8.6,  -24.1),  -- Map  2 Level Grinding Cavern
    [50103] = Vector3.new(1913.1, 10.5, -194.4),  -- Map  3 Shadow Castle
    [50104] = Vector3.new( 515.8,  7.6,  -98.0),  -- Map  4 Seolhan Forest
    [50105] = Vector3.new(-229.3,  9.6,   -2.3),  -- Map  5 Demon Castle Tier 1
    [50106] = Vector3.new(1998.2,  8.0,  237.7),  -- Map  6 Orc Palace
    [50107] = Vector3.new( -42.0,  8.4,  334.0),  -- Map  7 Demon Castle Tier 2
    [50108] = Vector3.new(-925.8,-396.2, -901.6),  -- Map  8 Ant Island
    [50109] = Vector3.new(   8.7, 13.0,  244.2),  -- Map  9 Land of Giant
    [50110] = Vector3.new(2003.0,  8.1,  344.0),  -- Map 10 Plagueheart
    [50111] = Vector3.new(2068.0, 49.4, -155.8),  -- Map 11 Umbralfrost Domain
    [50112] = Vector3.new(  16.5,  9.0,  269.5),  -- Map 12 Kamish's Demise
    [50113] = Vector3.new(2100.7, 63.1,  423.1),  -- Map 13 Lava Hell
    [50114] = Vector3.new(  27.8, 49.8,  303.9),  -- Map 14 Illusory World
    [50115] = Vector3.new(  -0.9, 24.0,  185.3),  -- Map 15 Inferno Altar
    [50116] = Vector3.new(1999.6, 17.0,  236.5),  -- Map 16 Shadow Throne
    [50117] = Vector3.new(  -0.4, 18.5,   93.5),  -- Map 17 Angel Holy Realm
    [50118] = Vector3.new(2000.0, 45.4,  234.7),  -- Map 18 Golden Throne
}

-- Pilih raidEntry dari RAID_ID_LIST sesuai difficulty
-- Ambil snapshot dari RAID_ID_LIST saat ini, simpan sebagai RAID_SNAPSHOT
-- Dipanggil sekali saat notif raid pertama masuk (atau setelah TTL reset)
-- Forward declare snapshot functions
TakeSnapshot, IsSnapshotValid, ResetSnapshot, PickRaidByDifficulty = nil, nil, nil, nil

do -- [FIX] snapshot logic wrapped

TakeSnapshot = function()
    if #RAID_ID_LIST == 0 then return false end
    -- Sort ascending by mapNum
    local sorted = {}
    for _, r in ipairs(RAID_ID_LIST) do table.insert(sorted, r) end
    table.sort(sorted, function(a, b) return (a.mapId - 50000) < (b.mapId - 50000) end)
    RAID_SNAPSHOT   = sorted
    _snapshotTime   = tick()
    _snapshotTaken  = true
    local maps = {}
    for _, r in ipairs(sorted) do table.insert(maps, tostring(r.mapId - 50000)) end
    RaidStatusUpdate("Snapshot: Map " .. table.concat(maps, ","), Color3.fromRGB(100,255,180))
    return true
end

-- Cek apakah snapshot masih valid (belum kadaluarsa 5 menit)
IsSnapshotValid = function()
    if not _snapshotTaken or #RAID_SNAPSHOT == 0 then return false end
    return (tick() - _snapshotTime) < _SNAPSHOT_TTL
end

-- Reset snapshot — GUI siap jepret lagi
ResetSnapshot = function()
    RAID_SNAPSHOT   = {}
    _snapshotTime   = 0
    _snapshotTaken  = false
end

-- [v115] Pilih raidEntry dari RAID_SNAPSHOT sesuai difficulty + Rune Map filter
-- Mode Preferred + Preferred Map: hanya map yang dipilih + grade ≥ minimum
-- Mode Preferred + Rune Map Only (preferMaps kosong): semua map, grade ≥ minimum, round-robin
-- Mode Easy/Medium/Hard + Rune Map: filter grade dulu, baru pilih posisi
_runeRRIdx = 0  -- round-robin index untuk Rune Map Only mode

PickRaidByDifficulty = function()
    if not IsSnapshotValid() then
        if #RAID_ID_LIST > 0 then TakeSnapshot() else return nil end
    end
    if #RAID_SNAPSHOT == 0 then return nil end

    local diff = RAID.difficulty
    local snap = RAID_SNAPSHOT  -- sorted ascending by mapId

    -- ── Mode PREFERRED ──
    if diff == "preferred" then
        local hasMapFilter = next(RAID.preferMaps) ~= nil
        local candidates = {}
        for _, r in ipairs(snap) do
            local mn = r.mapId - 50000
            local passMap  = (not hasMapFilter) or RAID.preferMaps[mn]
            local passRune = not RAID.runeEnabled or RuneMapCheck(r)
            if passMap and passRune then
                table.insert(candidates, r)
            end
        end
        if #candidates == 0 then
            -- Tidak ada yang cocok → fallback snap[1] agar tidak stuck
            return snap[1]
        end
        table.sort(candidates, function(a,b) return a.mapId < b.mapId end)

        -- Rune Map Only (tidak ada filter map): round-robin antar kandidat
        if not hasMapFilter and RAID.runeEnabled then
            _runeRRIdx = (_runeRRIdx % #candidates) + 1
            return candidates[_runeRRIdx]
        end
        -- Preferred Map: ambil yang mapId terkecil dari kandidat
        return candidates[1]
    end

    -- ── Mode EASY / MEDIUM / HARD ──
    -- Kalau Rune Map aktif: filter grade dulu, baru pilih posisi
    if RAID.runeEnabled and next(RAID.runeGrades) ~= nil then
        local filtered = {}
        for _, r in ipairs(snap) do
            if RuneMapCheck(r) then table.insert(filtered, r) end
        end
        if #filtered > 0 then
            if diff == "easy"   then return filtered[1] end
            if diff == "hard"   then return filtered[#filtered] end
            if diff == "medium" then return filtered[math.min(5, #filtered)] end
        end
        -- Tidak ada yang lolos filter → fallback tanpa filter
    end

    if diff == "easy"   then return snap[1] end
    if diff == "hard"   then return snap[#snap] end
    if diff == "medium" then return snap[math.min(5, #snap)] end

    return snap[1]
end

end -- do (snapshot logic)

-- ============================================================
-- [v115] CHAT SCANNER — History + Realtime (Raid & Siege)
-- ──────────────────────────────────────────────────────────
-- FORMAT RAID  : "The MaFissure appeared in 8,Ant Island [M++]"
--   keyword    : "MaFissure" + "appeared in"
--   parse      : mapNum (number setelah "appeared in ") + grade (dalam [...])
--
-- FORMAT SIEGE : "3, Shadow Castle has begun. Come and join in."
--   keyword    : "has begun" — map 3/7/10/13 TANPA grade = Siege
--   bedanya dgn Raid: Raid selalu punya "MaFissure" dan grade [...],
--   Siege hanya punya nomor map + "has begun", tanpa grade sama sekali
--
-- Grade urutan: E < D < C < B < A < S < SS < G < N < M < M+ < M++
-- [v115] SS ditambahkan antara S dan G sesuai game
-- ============================================================
GRADE_RANK = {
    ["E"]=1, ["D"]=2, ["C"]=3, ["B"]=4, ["A"]=5,
    ["S"]=6, ["SS"]=7, ["G"]=8, ["N"]=9, ["M"]=10, ["M+"]=11, ["M++"]=12,
}
GRADE_LIST = {"E","D","C","B","A","S","SS","G","N","M","M+","M++"}

-- Live grade cache: {[mapNum] = "M++"} — diisi dari chat (untuk Raid)
_runeGradeCache = {}

-- Siege chat open cache: {[mapNum] = true/false} — diisi dari chat "has begun"
_siegeChatOpen = {}

-- ── Helper: parse satu baris teks chat ──
-- Dipanggil oleh history scan DAN realtime listener
-- Deteksi Raid: "MaFissure" + "appeared in" → mapNum + grade
-- Deteksi Siege: "has begun" + mapNum salah satu dari {3,7,10,13} + TANPA grade
function ParseChatLine(text)
    if type(text) ~= "string" or #text < 3 then return end

    -- ── RAID: "The MaFissure appeared in 8,Ant Island [M++]" ──
    if text:find("MaFissure") and text:find("appeared") then
        -- Pattern: "appeared in 8,..." lalu "[M++]"
        local mapStr, rest = text:match("appeared in (%d+),(.+)")
        if mapStr then
            local mapNum = tonumber(mapStr)
            -- Ambil grade dari dalam [...] — tangani M+ dan M++ sebelum yang lebih pendek
            local grade = rest:match("%[M%+%+%]") and "M++"
                       or rest:match("%[M%+%]")  and "M+"
                       or rest:match("%[SS%]")   and "SS"
                       or rest:match("%[([EDCBASGMN])%]")
            if mapNum and grade and GRADE_RANK[grade] then
                -- Hanya update kalau grade baru >= yang sudah ada (ambil terbaik)
                local prev = _runeGradeCache[mapNum]
                if not prev or (GRADE_RANK[grade] > GRADE_RANK[prev]) then
                    _runeGradeCache[mapNum] = grade
                    warn("[ ASH RAID SCAN ] Map "..mapNum.." = ["..grade.."]"
                        ..(prev and " (update dari ["..prev.."])" or " (baru)"))
                end
                -- Wakeup raid loop
                if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
            end
        end
        return  -- sudah diproses sebagai Raid, skip cek Siege
    end

    -- ── SIEGE: "3, Shadow Castle has begun. Come and join in." ──
    -- Ciri khas: "has begun" + mapNum {3,7,10,13} + TIDAK ada grade [...]
    if text:find("has begun") then
        -- Pastikan tidak ada grade (bukan Raid yang kebetulan ada "has begun")
        local hasGrade = text:find("%[M%+%+%]") or text:find("%[M%+%]")
                      or text:find("%[SS%]")    or text:find("%[[EDCBASGMN]%]")
        if not hasGrade then
            for _, mn in ipairs({3, 7, 10, 13}) do
                -- Cek mapNum di awal pesan: "3, " atau " 3," atau sekedar angka tersebut
                if text:find("^"..mn..",") or text:find("%f[%d]"..mn..",%s") then
                    _siegeChatOpen[mn] = true
                    warn("[ ASH SIEGE SCAN ] Map "..mn.." OPEN (chat: has begun)")
                    -- Update SIEGE.live jika tabel sudah tersedia
                    if SIEGE and SIEGE.live and SIEGE_DATA and SIEGE_DATA[mn] then
                        SIEGE.live[SIEGE_DATA[mn].cityRaidId] = mn
                    end
                    -- Wakeup siege loop
                    if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
                    -- Auto-trigger webhook jika mode siege/both
                    if _webhookEnabled and _webhookUrl ~= ""
                    and (_webhookMode == "siege" or _webhookMode == "both") then
                        task.spawn(SendWebhookNotif)
                    end
                    break
                end
            end
        end
    end
end

-- ── Scan HISTORY chat yang sudah ada saat script load ──
-- Menangkap notif raid/siege yang muncul SEBELUM script dieksekusi
local function ScanChatHistory()
    local scanned, foundRaid, foundSiege = 0, 0, 0
    pcall(function()
        local TCS = game:GetService("TextChatService")
        local channels = TCS:FindFirstChild("TextChannels")
        if not channels then return end
        for _, ch in ipairs(channels:GetChildren()) do
            if ch:IsA("TextChannel") then
                for _, msgObj in ipairs(ch:GetChildren()) do
                    if msgObj:IsA("TextChatMessage") then
                        local txt = ""
                        pcall(function() txt = msgObj.Text or "" end)
                        if #txt > 0 then
                            local prevRaid = next(_runeGradeCache)
                            local prevSiege = next(_siegeChatOpen)
                            ParseChatLine(txt)
                            if next(_runeGradeCache) ~= prevRaid then foundRaid = foundRaid + 1 end
                            if next(_siegeChatOpen) ~= prevSiege then foundSiege = foundSiege + 1 end
                            scanned = scanned + 1
                        end
                    end
                end
            end
        end
    end)
    local raidCount, siegeCount = 0, 0
    for _ in pairs(_runeGradeCache) do raidCount = raidCount + 1 end
    for _ in pairs(_siegeChatOpen)  do siegeCount = siegeCount + 1 end
    warn("[ ASH SCAN ] History: "..scanned.." pesan → "
        ..raidCount.." Raid map grade, "..siegeCount.." Siege map open")
end

-- ── Realtime listener ──
local function StartChatListener()
    pcall(function()
        local TCS = game:GetService("TextChatService")
        TCS.MessageReceived:Connect(function(msg)
            ParseChatLine(msg.Text or "")
        end)
        warn("[ ASH SCAN ] Realtime listener aktif (Raid + Siege)")
    end)
end

-- ── Init: scan history dulu, lalu pasang realtime ──
task.spawn(function()
    task.wait(1.5)   -- tunggu chat channel ter-load
    ScanChatHistory()
    StartChatListener()
end)

-- ── Cek apakah raid entry lolos filter Rune Map ──
-- Returns: true = lolos (boleh masuk), false = skip
-- Mode "Rune Map Only" (preferMaps kosong): tidak ada filter map, hanya filter grade
function RuneMapCheck(raidEntry)
    if not RAID.runeEnabled then return true end
    local mapNum = raidEntry and raidEntry.mapId and (raidEntry.mapId - 50000)
    if not mapNum then return false end

    -- Filter map — HANYA aktif jika preferMaps tidak kosong
    local hasMapFilter = next(RAID.preferMaps) ~= nil
    if hasMapFilter and not RAID.preferMaps[mapNum] then
        return false
    end

    -- Filter grade
    local hasGradeFilter = next(RAID.runeGrades) ~= nil
    if not hasGradeFilter then return true end  -- semua grade lolos

    local cachedGrade = _runeGradeCache[mapNum]
    if not cachedGrade then return false end  -- belum ada data → skip

    local cachedRank = GRADE_RANK[cachedGrade] or 0
    local minRank = 99
    for g, _ in pairs(RAID.runeGrades) do
        local r = GRADE_RANK[g] or 99
        if r < minRank then minRank = r end
    end
    return cachedRank >= minRank
end

-- Forward declare raid+webhook functions
SendWebhookNotif=nil; RebuildRaidList=nil; FetchRaidIds=nil; ParseRaidEntry=nil
DisconnectRaidConns=nil; ConnectRaidListeners=nil; RaidFireDamage=nil

do -- [FIX] webhook + raid logic wrapped to free top-level locals

_WH = {}  -- global supaya bisa diakses dari Settings UI panel
-- ============================================================
-- WEBHOOK HELPERS
-- ============================================================
-- HTTP request via executor API (Delta/Synapse/etc)
-- Lebih reliable dari HttpService untuk request ke domain external
_WH.Post = function(url, body, headers)
    headers = headers or {}
    headers["Content-Type"] = headers["Content-Type"] or "application/json"
    local payload = { Url = url, Method = "POST", Headers = headers, Body = body }
    -- Cek semua kemungkinan nama function executor (Delta, Synapse, Krnl, dll)
    local reqFunc = request or http_request or
        (syn and syn.request) or
        (http and http.request) or
        (fluxus and fluxus.request) or
        nil
    if reqFunc then
        -- Executor API: langsung kirim, tidak perlu pcall karena async
        task.spawn(function() pcall(reqFunc, payload) end)
        return true
    end
    -- Fallback Roblox HttpService (hanya work untuk non-Discord domain)
    local HS = game:GetService("HttpService")
    pcall(function() HS:SetHttpEnabled(true) end)
    local ok = pcall(function()
        HS:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
    end)
    return ok
end

_WH.Get = function(url)
    local reqFunc = request or http_request or
        (syn and syn.request) or
        (http and http.request) or
        (fluxus and fluxus.request) or
        nil
    if reqFunc then
        local ok, res = pcall(reqFunc, { Url = url, Method = "GET" })
        if ok and res then return res.Body or res.body end
    end
    local HS = game:GetService("HttpService")
    pcall(function() HS:SetHttpEnabled(true) end)
    local ok, res = pcall(function() return HS:GetAsync(url) end)
    return ok and res or nil
end

-- [v115] Webhook mode: "raid" | "siege" | "both"
_webhookMode = "both"

-- Kirim notif Raid ke webhook
-- [v115] SendWebhookRaid — sumber data HANYA dari _runeGradeCache (chat scan)
-- Format chat: "The MaFissure appeared in X,MapName [Grade]"
-- Tidak pakai RAID_ID_LIST / e.label supaya tidak ngaco
local function SendWebhookRaid(url, isDiscord, isTelegram)
    local parts = {"⚡ [ASH] RAID — "..os.date("%d/%m %H:%M:%S")}

    -- Kumpulkan semua map yang sudah terdeteksi dari chat scan
    local found = {}
    for mn = 1, 18 do
        local grade = _runeGradeCache and _runeGradeCache[mn]
        if grade then
            table.insert(found, {mn=mn, grade=grade})
        end
    end

    if #found > 0 then
        table.insert(parts, "📊 Raid terdeteksi dari chat ("..#found.." map):")
        for _, d in ipairs(found) do
            local mapName = MAP_NAMES[d.mn] or ("Map "..d.mn)
            table.insert(parts, "  • "..d.mn..", "..mapName.." ["..d.grade.."]")
        end
    else
        table.insert(parts, "⏳ Belum ada data raid dari chat scan.")
    end

    -- Info target aktif (dari Rune Map filter)
    if RAID.runeEnabled then
        local minGrade = nil
        local minRank  = 99
        for g, _ in pairs(RAID.runeGrades) do
            local r = GRADE_RANK[g] or 99
            if r < minRank then minRank = r; minGrade = g end
        end
        if minGrade then
            table.insert(parts, "🎯 Filter aktif: minimum ["..minGrade.."] ke atas")
        end
    end
    if RAID.difficulty == "preferred" and next(RAID.preferMaps) then
        local maps = {}
        for mn in pairs(RAID.preferMaps) do table.insert(maps, "Map "..mn) end
        table.sort(maps)
        table.insert(parts, "📌 Preferred: "..table.concat(maps, ", "))
    end

    local body = table.concat(parts, "\n")
    pcall(function()
        local HS = game:GetService("HttpService")
        if isDiscord then
            _WH.Post(url, HS:JSONEncode({content = body}))
        else
            local enc = body:gsub("([^%w%-_%.%~])", function(c) return string.format("%%%02X", string.byte(c)) end)
            _WH.Get(url.."&text="..enc)
        end
    end)
end

-- Kirim notif Siege ke webhook
local function SendWebhookSiege(url, isDiscord, isTelegram)
    local parts = {"🏰 [ASH] SIEGE UPDATE — "..os.date("%H:%M:%S")}
    local CITY_BY_MAP = {[3]=1000001,[7]=1000002,[10]=1000003,[13]=1000004}
    local MAP_SIEGE_NAMES = {[3]="Shadow Castle",[7]="Demon Castle - Tier 2",[10]="Plagueheart",[13]="Lava Hell"}
    local anyOpen = false
    for _, mn in ipairs({3,7,10,13}) do
        local cid   = CITY_BY_MAP[mn]
        local isOpen = SIEGE and SIEGE.live and SIEGE.live[cid]
        local chatOpen = _siegeChatOpen and _siegeChatOpen[mn]
        local open = isOpen or chatOpen
        local icon = open and "✅" or "🔒"
        table.insert(parts, "  "..icon.." Map "..mn.." — "..(MAP_SIEGE_NAMES[mn] or "")..(open and " OPEN" or " CLOSED"))
        if open then anyOpen = true end
    end
    if not anyOpen then
        table.insert(parts, "  (tidak ada siege aktif saat ini)")
    end
    local body = table.concat(parts, "\n")
    pcall(function()
        local HS = game:GetService("HttpService")
        if isDiscord then
            _WH.Post(url, HS:JSONEncode({content = body}))
        else
            local enc = body:gsub("([^%w%-_%.%~])", function(c) return string.format("%%%02X", string.byte(c)) end)
            _WH.Get(url.."&text="..enc)
        end
    end)
end

SendWebhookNotif = function()
    if not _webhookEnabled or _webhookUrl == "" then return end
    local isDiscord  = _webhookUrl:find("discord%.com/api/webhooks")
    local isTelegram = _webhookUrl:find("api%.telegram%.org")
    if not isDiscord and not isTelegram then return end
    task.spawn(function()
        if _webhookMode == "raid" or _webhookMode == "both" then
            SendWebhookRaid(_webhookUrl, isDiscord, isTelegram)
        end
        if _webhookMode == "siege" or _webhookMode == "both" then
            if _webhookMode == "both" then task.wait(0.3) end
            SendWebhookSiege(_webhookUrl, isDiscord, isTelegram)
        end
    end)
end

_WH.SendCustomMessage = function(url, msg, onDone, onFail)
    if not url or url == "" then
        if onFail then onFail("URL kosong") end; return
    end
    local isDiscord  = url:find("discord%.com/api/webhooks")
    local isTelegram = url:find("api%.telegram%.org")
    if not isDiscord and not isTelegram then
        if onFail then onFail("URL tidak dikenali") end; return
    end
    -- Cek executor request tersedia
    local reqFunc = request or http_request or
        (syn and syn.request) or (http and http.request) or
        (fluxus and fluxus.request) or nil
    if not reqFunc then
        if onFail then onFail("Executor tidak support HTTP") end; return
    end
    task.spawn(function()
        local HS = game:GetService("HttpService")
        if isDiscord then
            local body = HS:JSONEncode({ content = tostring(msg) })
            pcall(reqFunc, { Url = url, Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body })
        else
            local enc = tostring(msg):gsub("([^%w%-_%.%~])", function(c)
                return string.format("%%%02X", string.byte(c))
            end)
            pcall(reqFunc, { Url = url .. "&text=" .. enc, Method = "GET" })
        end
        task.wait(0.5)
        if onDone then onDone() end
    end)
end
_WH.VerifyWebhookUrl = function(url, onValid, onInvalid)
    -- Verifikasi hanya cek format URL, tidak perlu HTTP request
    -- Discord/Telegram memblokir GET dari Roblox HttpService
    if url == "" then
        if onInvalid then onInvalid("URL kosong") end; return
    end
    local isDiscord  = url:find("discord%.com/api/webhooks/")
    local isTelegram = url:find("api%.telegram%.org/bot[^/]+/sendMessage")
    if isDiscord then
        -- Cek format: harus ada numeric ID dan token setelah /webhooks/
        local id, token = url:match("webhooks/(%d+)/([%w_%-]+)")
        if id and token and #token > 10 then
            if onValid then onValid() end
        else
            if onInvalid then onInvalid("Format Discord webhook salah") end
        end
    elseif isTelegram then
        -- Cek format: harus ada chat_id
        if url:find("chat_id=") then
            if onValid then onValid() end
        else
            if onInvalid then onInvalid("Telegram URL butuh chat_id=...") end
        end
    else
        if onInvalid then onInvalid("Bukan URL Discord/Telegram valid") end
    end
end

RebuildRaidList = function()
    local sorted = {}
    for _, e in pairs(RAID_LIVE) do table.insert(sorted, e) end
    -- Sort by mapId ascending (map 1 → map 18)
    table.sort(sorted, function(a, b) return (a.mapId or 0) < (b.mapId or 0) end)
    RAID_ID_LIST = {}
    for _, e in ipairs(sorted) do
        table.insert(RAID_ID_LIST, {
            label     = "Map "..(e.mapId-50000).." - "..(MAP_NAMES[e.mapId-50000] or ("Map "..(e.mapId-50000))).." - "..(RANK_LABEL[e.rank] or ("["..e.spawnName.."]")).." (ID:"..e.raidId..")",
            id        = e.raidId,
            rank      = e.rank,
            mapId     = e.mapId,
            spawnName = e.spawnName,
        })
    end
    if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end
    -- Kirim webhook setiap RAID_LIVE berubah
    if _webhookEnabled and _webhookUrl ~= "" then
        task.spawn(SendWebhookNotif)
    end
end

-- Parse satu entry raidInfos
ParseRaidEntry = function(k, info)
    if type(info) ~= "table" then return end
    local raidId    = info.raidId or (type(k)=="number" and k) or tonumber(k)
    local mapId     = info.mapId
    local spawnName = info.spawnName or "RE1001"
    if not raidId or not mapId then return end
    local rank    = SPAWN_RANK[spawnName] or 0
    local mapNum  = mapId - 50000
    local mapName = MAP_NAMES[mapNum] or ("Map "..mapNum)
    local rankLbl = RANK_LABEL[rank] or ("["..spawnName.."]")
    RAID_LIVE[raidId] = {
        raidId    = raidId,
        mapId     = mapId,
        spawnName = spawnName,
        rank      = rank,
        endTime   = info.endTime,
        label     = "Map "..mapNum.." - "..mapName.." - "..rankLbl,
    }
end

-- ============================================================
-- RAID LISTENER — Self-healing, reconnect otomatis setelah
-- rejoin / relog / teleport. Tidak bergantung pada instance
-- remote yang sudah di-destroy.
-- ============================================================

-- Koneksi aktif disimpan agar bisa di-disconnect sebelum reconnect
_WH.raidConns = {}

DisconnectRaidConns = function()
    for _, conn in ipairs(_WH.raidConns) do
        pcall(function() conn:Disconnect() end)
    end
    _WH.raidConns = {}
end

-- Fungsi utama: connect ke semua remote raid
-- Dipanggil saat pertama load DAN setiap kali Remotes berubah
ConnectRaidListeners = function()
    DisconnectRaidConns()

    -- Selalu re-fetch referensi remote terbaru dari Remotes folder
    local _RE_Update  = Remotes:FindFirstChild("UpdateRaidInfo")
    local _RE_Team    = Remotes:FindFirstChild("UpdateRaidTeamInfo")
    local _RE_Enter   = Remotes:FindFirstChild("EnterRaidsUpdateInfo")
    local _RE_Success = Remotes:FindFirstChild("ChallengeRaidsSuccess")
    local _RE_Fail    = Remotes:FindFirstChild("ChallengeRaidsFail")

    -- ── UpdateRaidInfo: notif raid muncul/hilang (KUNCI UTAMA) ──
    if _RE_Update then
        local conn = _RE_Update.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local action    = data.action
            local raidInfos = data.raidInfos
            if type(raidInfos) ~= "table" then return end
            if action == "RemoveRaidEnters" then
                for k in pairs(raidInfos) do
                    local raidId = type(k)=="number" and k or tonumber(k)
                    if raidId then RAID_LIVE[raidId] = nil end
                end
            else
                for k, info in pairs(raidInfos) do
                    ParseRaidEntry(k, info)
                end
            end
            RebuildRaidList()
        end)
        table.insert(_WH.raidConns, conn)
    end

    -- ── UpdateRaidTeamInfo: player lain join raid ──
    if _RE_Team then
        local conn = _RE_Team.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local raidId = data.raidId
            local mapId  = data.mapId
            if raidId and mapId and not RAID_LIVE[raidId] then
                ParseRaidEntry(raidId, {raidId=raidId, mapId=mapId, spawnName="RE1001"})
                RebuildRaidList()
            end
        end)
        table.insert(_WH.raidConns, conn)
    end

    -- ── EnterRaidsUpdateInfo: dapat slotIndex ──
    if _RE_Enter then
        local conn = _RE_Enter.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            if data.slotIndex then
                RAID.slotIndex = data.slotIndex
            end
        end)
        table.insert(_WH.raidConns, conn)
    end

    -- ── ChallengeRaidsSuccess: handled di StartRaidLoop ──
    if _RE_Success then
        local conn = _RE_Success.OnClientEvent:Connect(function()
            -- Counting via StartRaidLoop (RAID.sukses)
        end)
        table.insert(_WH.raidConns, conn)
    end

    -- ── ChallengeRaidsFail: raid gagal ──
    if _RE_Fail then
        local conn = _RE_Fail.OnClientEvent:Connect(function()
            -- handled di StartRaidLoop via local connF
            -- ini hanya fallback counter
        end)
        table.insert(_WH.raidConns, conn)
    end

    warn("[ ASH RAID ] ✅ Listener reconnected ("..#_WH.raidConns.." koneksi aktif)")
end

-- Pertama kali: connect langsung saat GUI muncul
task.spawn(function()
    local _RE = Remotes:FindFirstChild("UpdateRaidInfo")
    if _RE then
        ConnectRaidListeners()
    else
        -- Remote belum ada, tunggu via ChildAdded
        local conn
        conn = Remotes.ChildAdded:Connect(function(child)
            if child.Name == "UpdateRaidInfo" then
                conn:Disconnect()
                ConnectRaidListeners()
            end
        end)
    end
end)

-- Fetch manual via GetRaidTeamInfos (dipanggil saat start)
-- [FIX] dipindah ke atas watcher agar tidak nil saat dipanggil
FetchRaidIds = function()
    local RE = Remotes:FindFirstChild("GetRaidTeamInfos")
    if not RE then return end
    local ok, res = pcall(function() return RE:InvokeServer() end)
    if not ok or type(res) ~= "table" then return end
    -- Struktur sama dengan UpdateRaidInfo raidInfos
    -- {[raidId] = {raidId, mapId, spawnName, ...}}
    for k, info in pairs(res) do
        if type(info) == "table" then
            ParseRaidEntry(k, info)
        end
    end
    if next(RAID_LIVE) then
        RebuildRaidList()
    end
end

-- ── WATCHER: Auto-reconnect kalau Remotes folder refresh ──
task.spawn(function()
    -- Inisialisasi dengan remote yang sudah ada agar tidak trigger di awal
    local lastRemoteRef = Remotes:FindFirstChild("UpdateRaidInfo")
    while ScreenGui.Parent do
        task.wait(2)
        local current = Remotes:FindFirstChild("UpdateRaidInfo")
        if current ~= lastRemoteRef then
            lastRemoteRef = current
            if current then
                ConnectRaidListeners()
                task.spawn(function()
                    task.wait(0.5)
                    FetchRaidIds()
                end)
            end
        end
    end
end)

-- ── Helpers ──
function StopRaid()
    _raidInterrupt = false
    RAID.running = false
    if RAID.thread then
        pcall(function() task.cancel(RAID.thread) end)
        RAID.thread = nil
    end
end

_raidSessionStart = nil  -- waktu mulai raid session

function RaidStatusUpdate(msg, color)
    if RAID.statusLbl then
        local ts = ""
        if _raidSessionStart then
            local dur = os.time() - _raidSessionStart
            ts = string.format("[%02d:%02d:%02d] ", math.floor(dur/3600), math.floor(dur/60)%60, dur%60)
        end
        RAID.statusLbl.Text = ts..msg
        RAID.statusLbl.TextColor3 = color or Color3.fromRGB(255,210,160)
    end
    if RAID.dot then
        RAID.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100)
    end
end

function RaidCounterUpdate()
    if RAID.suksesLbl then RAID.suksesLbl.Text = "Sukses: "..RAID.sukses end
end

-- [v73 FIX] RaidCollectAll — scan lebih agresif:
-- 1. Scan semua folder reward yang mungkin
-- 2. Scan workspace root langsung (ada item yang tidak di-folder)
-- 3. Retry 1x setelah 1.5 detik untuk item yang spawn delayed
function RaidCollectAll()
    local collected_guids = {}
    local function collectFolder(folder)
        if not folder then return end
        for _, obj in ipairs(folder:GetChildren()) do
            local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid")
                      or obj:GetAttribute("guid") or obj:GetAttribute("ItemGuid")
            if guid and not collected_guids[guid] then
                collected_guids[guid] = true
                RAID.collected = RAID.collected + 1
                pcall(function() RE.CollectItem:InvokeServer(guid) end)
                if not (STATE and STATE.hideReward) then
                    pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                end
                task.wait(0.05)
            end
        end
    end

    -- Round 1: scan semua folder reward
    local folders = {"Golds","Items","Drops","Rewards","Loot","Chests","RewardItems","DropItems"}
    for _, folderName in ipairs(folders) do
        collectFolder(workspace:FindFirstChild(folderName))
    end

    -- Scan workspace root untuk item loose (tidak dalam folder)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") or obj:IsA("Part") or obj:IsA("BasePart") then
            local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid")
                      or obj:GetAttribute("guid") or obj:GetAttribute("ItemGuid")
            if guid and not collected_guids[guid] then
                collected_guids[guid] = true
                RAID.collected = RAID.collected + 1
                pcall(function() RE.CollectItem:InvokeServer(guid) end)
                if not (STATE and STATE.hideReward) then
                    pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                end
                task.wait(0.05)
            end
        end
    end

    -- [v73] Round 2: tunggu 1.5 detik lalu scan ulang (item spawn delayed)
    task.wait(1.5)
    for _, folderName in ipairs(folders) do
        collectFolder(workspace:FindFirstChild(folderName))
    end
end

-- Scan enemy/boss di workspace
function GetRaidEnemies()
    local list = {}
    for _, fname in ipairs({"Enemys","Enemy","Enemies","Bosses","Boss","RaidBoss","RaidEnemys"}) do
        local folder = workspace:FindFirstChild(fname)
        if folder then
            for _, e in ipairs(folder:GetChildren()) do
                if e:IsA("Model") then
                    local g   = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid")
                              or e:GetAttribute("Guid") or e:GetAttribute("GUID")
                    local hrp = e:FindFirstChild("HumanoidRootPart")
                    local hum = e:FindFirstChildOfClass("Humanoid")
                    if g and hrp and hum and hum.Health > 0 then
                        table.insert(list, {guid=g, hrp=hrp, model=e})
                    end
                end
            end
        end
    end
    return list
end

-- Serang semua enemy raid
-- [v73 FIX] Fire attackType 1+2+3 supaya damage konsisten (sebelumnya hanya 1)
RaidFireDamage = function(g, p)
    if RE.Click then
        task.spawn(function()
            pcall(function() RE.Click:InvokeServer({enemyGuid=g, enemyPos=p}) end)
        end)
    end
    if RE.Atk then
        pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
    end
    for _, hGuid in ipairs(HERO_GUIDS) do
        if RE.HeroUseSkill then
            -- [v73 FIX] Fire semua attackType 1, 2, 3 bukan hanya 1
            for _, aType in ipairs({1, 2, 3}) do
                pcall(function() RE.HeroUseSkill:FireServer({
                    heroGuid   = hGuid,
                    attackType = aType,
                    userId     = MY_USER_ID,
                    enemyGuid  = g,
                }) end)
            end
        elseif RE.HeroSkill then
            pcall(function() RE.HeroSkill:FireServer({
                heroGuid=hGuid, enemyGuid=g, skillType=1, masterId=MY_USER_ID
            }) end)
        end
    end
end

-- Main loop
function StartRaidLoop()
    StopRaid()
    RAID.running      = true
    RAID.sukses       = 0
    RAID.collected    = 0
    RAID.snapshotMapId = nil
    ResetSnapshot()
    RaidCounterUpdate()
    _raidSessionStart = os.time()  -- [v112] timer sesi raid

    RAID.thread = task.spawn(function()
        while RAID.running do

            -- ── CEK SIEGE INTERRUPT ──
            if _siegeInterrupt then
                RaidStatusUpdate("⏸ Pause — Siege sedang berlangsung...", Color3.fromRGB(255,140,0))
                WaitSiegeDone()
                if not RAID.running then break end
                RaidStatusUpdate("▶ Siege selesai — lanjut cari raid...", Color3.fromRGB(100,200,255))
                task.wait(0.3)
            end

            -- ── STEP 1: Resolve raidEntry dari RAID_LIVE ──
            -- RAID_LIVE diisi oleh UpdateRaidInfo OnClientEvent
            _raidInterrupt = false
            RaidStatusUpdate("Waiting", Color3.fromRGB(255,200,60))
            task.wait(0.3)

            local raidEntry = nil

            -- Cek apakah snapshot perlu di-reset (TTL 5 menit)
            if _snapshotTaken and not IsSnapshotValid() then
                ResetSnapshot()
                RaidStatusUpdate("Waiting", Color3.fromRGB(255,200,60))
            end

            -- Coba ambil entry dari snapshot
            function ResolveFromSnapshot()
                local picked = PickRaidByDifficulty()
                if not picked then return nil end
                -- Cari entry live yang mapId-nya cocok dengan pilihan snapshot
                for _, r in ipairs(RAID_ID_LIST) do
                    if r.mapId == picked.mapId then return r end
                end
                return nil
            end

            raidEntry = ResolveFromSnapshot()

            -- Tunggu sampai ada raid yang cocok (live-switch difficulty support)
            while RAID.running and not raidEntry do
                -- CEK SIEGE INTERRUPT saat menunggu
                if _siegeInterrupt then
                    RaidStatusUpdate("Pause — Siege sedang berlangsung...", Color3.fromRGB(255,140,0))
                    WaitSiegeDone()
                    if not RAID.running then break end
                    RaidStatusUpdate("Lanjut cari raid...", Color3.fromRGB(100,200,255))
                end

                -- Cek TTL snapshot setiap iterasi
                if _snapshotTaken and not IsSnapshotValid() then
                    ResetSnapshot()
                    RaidStatusUpdate("Waiting", Color3.fromRGB(255,200,60))
                end

                -- Coba resolve (juga handle live-switch difficulty karena PickRaidByDifficulty selalu baca RAID.difficulty terkini)
                raidEntry = ResolveFromSnapshot()

                if not raidEntry then
                    -- [v50 FIX] Kalau RAID_ID_LIST sudah ada data (dari FetchRaidIds)
                    -- tapi snapshot belum diambil → ambil sekarang, jangan tunggu notif
                    -- Ini fix skenario relog: raid sudah ada tapi notif sudah lewat
                    if not _snapshotTaken and #RAID_ID_LIST > 0 then
                        TakeSnapshot()
                        raidEntry = ResolveFromSnapshot()
                        if raidEntry then continue end
                    end
                    RaidStatusUpdate("Waiting", Color3.fromRGB(255,200,60))
                    task.wait(1)
                end
            end
            if not RAID.running then break end

            -- Snapshot diambil di sini kalau belum ada (notif baru pertama masuk)
            if not _snapshotTaken and #RAID_ID_LIST > 0 then
                TakeSnapshot()
                -- Resolve ulang setelah snapshot diambil
                raidEntry = ResolveFromSnapshot() or raidEntry
            end

            -- ── CEK SIEGE INTERRUPT sebelum masuk raid ──
            if _siegeInterrupt then
                RaidStatusUpdate("⏸ Pause — Siege sedang berlangsung...", Color3.fromRGB(255,140,0))
                WaitSiegeDone()
                if not RAID.running then break end
                RaidStatusUpdate("▶ Siege selesai — lanjut cari raid...", Color3.fromRGB(100,200,255))
                task.wait(0.3)
            end

            -- Raid ditemukan → pause Mass Attack
            _raidInterrupt = true
            RAID.inMap = true

            -- Tunggu Mass Attack benar-benar berhenti sebelum lanjut
            -- MA cek _raidInterrupt di setiap iterasi, beri waktu dia selesai iterasi saat ini
            if MA.running then
                RaidStatusUpdate("⏸ Tunggu Mass Attack berhenti...", Color3.fromRGB(255,140,0))
                local waitMA = 0
                while MA.running and _raidInterrupt and waitMA < 2 do
                    task.wait(0.1)
                    waitMA = waitMA + 0.1
                end
            end

            RAID.raidId    = raidEntry.id
            RAID.raidMapId = raidEntry.mapId
            RAID.slotIndex = 2  -- reset tiap masuk raid baru, diupdate oleh EnterRaidsUpdateInfo
            if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end

            -- [v88] TipsPanel: Enabled=false saat raid, restore Enabled=true setelah sukses
            -- Tidak Destroy() — hanya disembunyikan sementara selama sesi raid
            local _tipsWatcher  = nil
            local _tipsActive   = true
            local _tipsHidden   = {}  -- simpan referensi TipsPanel yang di-hide untuk restore
            local function HideTipsPanel()
                pcall(function()
                    local tips = PG:FindFirstChild("TipsPanel")
                    if tips and tips.Enabled then
                        tips.Enabled = false
                        _tipsHidden[tips] = true
                    end
                end)
            end
            local function RestoreTipsPanel()
                for tips, _ in pairs(_tipsHidden) do
                    pcall(function()
                        if tips and tips.Parent then
                            tips.Enabled = true
                        end
                    end)
                end
                _tipsHidden = {}
            end
            _tipsWatcher = PG.ChildAdded:Connect(function(gui)
                if not _tipsActive then return end
                if gui.Name == "TipsPanel" then
                    task.defer(function()
                        pcall(function()
                            gui.Enabled = false
                            _tipsHidden[gui] = true
                        end)
                    end)
                end
            end)
            -- Hide yang sudah ada saat watcher dipasang
            HideTipsPanel()

            local mn = raidEntry.mapId - 50000
            local mapLabel = MAP_NAMES[mn] or ("Map "..mn)
            RaidStatusUpdate("Masuk Map "..mn.." - "..mapLabel, Color3.fromRGB(80,220,80))
            task.wait(0.3)
            if not RAID.running then break end

            -- ── STEP 2: Buat team ──
            RaidStatusUpdate("👥 Membuat team (ID:"..RAID.raidId..")...", Color3.fromRGB(100,200,255))
            if RE.CreateRaidTeam then
                pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end)
            end
            task.wait(0.5)
            if not RAID.running then break end

            -- ── STEP 4: Konfirmasi map ──
            if RE.StartChallengeRaidMap then
                pcall(function() RE.StartChallengeRaidMap:FireServer() end)
            end
            task.wait(0.3)
            if not RAID.running then break end

            -- ── STEP 5: Teleport ke map raid ──
            -- SimpleSpy: {hostId=userId, mapId=50302} — hostId WAJIB ada
            local mn_tp   = RAID.raidMapId - 50000
            local tpMapId = RAID.raidMapId + 100
            warn("[ ASH RAID ] STEP5 TP: raidMapId="..RAID.raidMapId.." tpMapId="..tpMapId)
            RaidStatusUpdate("🌀 TP ke Map "..mn_tp.."...", Color3.fromRGB(180,100,255))
            if RE.StartTp then
                pcall(function() RE.StartTp:FireServer({
                    hostId = MY_USER_ID,
                    mapId  = tpMapId,
                }) end)
            end
            task.wait(2)
            if not RAID.running then break end

            -- ── STEP 6: EquipHeroWithData → LocalPlayerTeleportSuccess ──
            -- [v73 FIX] HERO_GUIDS TIDAK di-wipe agar hero tetap menyerang
            -- Hanya di-wipe jika memang kosong dari awal (belum pernah capture)
            -- Backup GUID sebelum fire EquipHeroWithData
            local _heroGuidBackup = {}
            for _, g in ipairs(HERO_GUIDS) do table.insert(_heroGuidBackup, g) end

            if RE.EquipHeroWithData then
                pcall(function() RE.EquipHeroWithData:FireServer() end)
            end
            task.wait(0.2)
            if RE.LocalTpSuccess then
                pcall(function() RE.LocalTpSuccess:InvokeServer() end)
            end
            task.wait(1)

            -- [v73 FIX] Kalau HERO_GUIDS kosong setelah equip, restore dari backup
            if #HERO_GUIDS == 0 and #_heroGuidBackup > 0 then
                HERO_GUIDS = _heroGuidBackup
                warn("[ ASH RAID v73 ] HERO_GUIDS kosong setelah equip, restore dari backup: "..#HERO_GUIDS.." hero")
            end

            -- [v73 FIX] Kalau masih kosong, coba scan HeroUseSkill dari workspace
            if #HERO_GUIDS == 0 then
                warn("[ ASH RAID v73 ] HERO_GUIDS masih kosong — coba scan dari character data")
                -- Scan DataModel untuk hero data yang mungkin tersedia
                pcall(function()
                    local heroFolder = RS:FindFirstChild("HeroData") or RS:FindFirstChild("Heroes")
                    if heroFolder then
                        for _, h in ipairs(heroFolder:GetChildren()) do
                            local g = h:GetAttribute("heroGuid") or h:GetAttribute("guid") or h:GetAttribute("HeroGuid")
                            if type(g) == "string" and IsValidUUID(g) then
                                local already = false
                                for _, existing in ipairs(HERO_GUIDS) do
                                    if existing == g then already = true; break end
                                end
                                if not already then table.insert(HERO_GUIDS, g) end
                            end
                        end
                    end
                end)
                if #HERO_GUIDS > 0 then
                    warn("[ ASH RAID v73 ] Berhasil recover "..#HERO_GUIDS.." hero GUID dari workspace")
                else
                    warn("[ ASH RAID v73 ] HERO_GUIDS tetap kosong — hero tidak akan ikut serang (klik Reroll dulu 1x)")
                end
            end

            -- ── STEP 6: Di dalam raid ──
            RAID._raidDone  = false
            local _raidSuccess = false

            local connS2, connF2
            local RE_S2 = Remotes:FindFirstChild("ChallengeRaidsSuccess")
            local RE_F2 = Remotes:FindFirstChild("ChallengeRaidsFail")
            if RE_S2 then
                connS2 = RE_S2.OnClientEvent:Connect(function()
                    RAID._raidDone = true; _raidSuccess = true
                end)
            end
            if RE_F2 then
                connF2 = RE_F2.OnClientEvent:Connect(function()
                    RAID._raidDone = true
                    RaidStatusUpdate("💀 Raid gagal, skip...", Color3.fromRGB(255,100,60))
                end)
            end

            if RAID.autoKillBoss then
                RaidStatusUpdate("⏳ Masuk map...", Color3.fromRGB(160,148,135))
                for i = 1, 6 do
                    if not RAID.running then break end
                    task.wait(1)
                end

                if RAID.running then
                    local BOSS_NAMES = {
                        "goblin king","giant arachnid","buryura","igris",
                        "leader of the polar","arch lich","kargalgan",
                        "baran","beru","grendal","monarch plague","frostborne",
                        "legia","monarch beastly","beastly fangs","silas",
                        "unbreakable monarch","yogumunt","monarch of transfiguration",
                        "transfiguration","antares","ashborn","dominion","absolute",
                        "monarch","fragment","boss",
                    }
                    local function IsBoss(name)
                        local n = name:lower()
                        for _, k in ipairs(BOSS_NAMES) do
                            if n:find(k, 1, true) then return true end
                        end
                        return false
                    end

                    -- [v73 FIX] Cari boss max 20 detik (sebelumnya 10 detik), retry TP tiap 2 detik
                    local boss = nil
                    local waitBoss = 0
                    while RAID.running and not boss and waitBoss < 20 and not RAID._raidDone do
                        for _, e in ipairs(GetRaidEnemies()) do
                            if IsBoss(e.model.Name) then
                                boss = e
                                RaidStatusUpdate("👑 Boss: ["..e.model.Name.."]", Color3.fromRGB(255,80,80))
                                break
                            end
                        end
                        if not boss then
                            RaidStatusUpdate("🔍 Cari boss... ("..math.floor(waitBoss).."s/20s)", Color3.fromRGB(160,148,135))
                            task.wait(0.5); waitBoss = waitBoss + 0.5
                        end
                    end

                    if boss and RAID.running then
                        local bossPos = Vector3.new(0,0,0)
                        pcall(function() bossPos = boss.hrp.Position end)

                        -- TP karakter + hero ke boss, diulang tiap 2 detik sampai boss mati
                        local _tpThread = task.spawn(function()
                            while RAID.running and not RAID._raidDone do
                                pcall(function()
                                    local char  = LP.Character
                                    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
                                    local curPos = boss.hrp and boss.hrp.Position or bossPos
                                    if myHrp then
                                        myHrp.CFrame = CFrame.new(curPos + Vector3.new(3,0,0))
                                    end
                                    FireHeroRemotes(boss.guid, curPos)
                                end)
                                task.wait(2)
                            end
                        end)
                        RaidStatusUpdate("👑 TP ke boss — serang!", Color3.fromRGB(255,80,80))
                        task.wait(0.15)

                        -- Serang boss sampai mati (model hilang / humanoid 0)
                        local bossGuid = boss.guid
                        while RAID.running and not RAID._raidDone do
                            if not boss.model or not boss.model.Parent then break end
                            local hum = boss.model:FindFirstChildOfClass("Humanoid")
                            if hum and hum.Health <= 0 then break end
                            local p = boss.hrp and boss.hrp.Position or bossPos
                            task.spawn(function()
                                pcall(function() RaidFireDamage(bossGuid, p) end)
                                pcall(function() FireHeroRemotes(bossGuid, p) end)
                            end)
                            task.wait(0.08)
                        end

                        -- Stop TP thread
                        pcall(function() task.cancel(_tpThread) end)

                        -- [v86] Boss mati → wait 2s → langsung Ambil Reward → keluar
                        RaidStatusUpdate("💀 Boss mati — ambil reward...", Color3.fromRGB(100,255,150))
                        task.wait(2)

                        RaidStatusUpdate("🎁 Mengambil reward...", Color3.fromRGB(255,220,80))
                        pcall(function()
                            local gainRemote = Remotes:FindFirstChild("GainRaidsRewards")
                            if gainRemote then
                                gainRemote:InvokeServer(1)
                            end
                        end)
                        -- Hide TipsPanel setelah GainRaidsRewards (akan di-restore setelah sukses)
                        HideTipsPanel()
                        task.wait(1.5)
                        _raidSuccess  = true
                        RAID._raidDone = true
                        RaidStatusUpdate("✅ Reward diambil — keluar raid!", Color3.fromRGB(80,255,120))
                    else
                        RaidStatusUpdate("⚠ Boss tidak ditemukan — lewati", Color3.fromRGB(255,150,50))
                    end
                end
            else
                RaidStatusUpdate("⚔ Di dalam raid — menunggu hasil...", Color3.fromRGB(255,180,40))
                local waited = 0
                while RAID.running and not RAID._raidDone and waited < 300 do
                    task.wait(1); waited = waited + 1
                    if waited % 15 == 0 then
                        RaidStatusUpdate("⚔ Dalam raid... ("..waited.."s)", Color3.fromRGB(255,180,40))
                    end
                end
            end

            if connS2 then pcall(function() connS2:Disconnect() end) end
            if connF2 then pcall(function() connF2:Disconnect() end) end

            -- Hitung sukses
            if _raidSuccess then
                RAID.sukses = RAID.sukses + 1
                RaidCounterUpdate()
                RaidStatusUpdate("✅ Sukses ke-"..RAID.sukses.." — Map "..mn, Color3.fromRGB(100,255,150))
            end
            if not RAID.running then break end

            -- ── STEP 7: Pasca raid ──
            -- [v87] Langsung TP ke toMapId bersamaan dengan status "Keluar Raid"
            RaidStatusUpdate("🚪 Keluar raid...", Color3.fromRGB(200,100,100))
            pcall(function()
                if RE.StartTp then
                    RE.StartTp:FireServer({
                        hostId = MY_USER_ID,
                        mapId  = RAID.raidMapId,
                    })
                end
            end)
            task.wait(0.5)
            -- [v89] Stop watcher + auto restore TipsPanel setelah 60 detik
            -- Popup biasanya hilang sendiri dalam beberapa detik, 60 detik untuk memastikan
            _tipsActive = false
            pcall(function() _tipsWatcher:Disconnect() end)
            task.delay(60, function()
                RestoreTipsPanel()
            end)
            RAID_LIVE[RAID.raidId] = nil
            RebuildRaidList()
            -- Tidak reset snapshot di sini agar Easy/Medium/Hard konsisten
            -- Snapshot hanya reset saat TTL habis (5 menit) atau ganti difficulty
            -- Release interrupt LEBIH AWAL supaya Mass Attack tidak jeda lama
            task.wait(0.5)
            _raidInterrupt = false
            RAID.inMap = false

            -- Cooldown 20 detik — status tetap "Waiting"
            local COOLDOWN = 15
            for cd = COOLDOWN, 1, -1 do
                if not RAID.running then break end
                if _siegeInterrupt then
                    RaidStatusUpdate("⏸ Cooldown pause — Siege berlangsung...", Color3.fromRGB(255,140,0))
                    WaitSiegeDone()
                    if not RAID.running then break end
                end
                RaidStatusUpdate("⏳ Cooldown: "..cd.."s lagi...", Color3.fromRGB(160,148,135))
                if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
                task.wait(1)
            end

            if RAID.running then
                RaidStatusUpdate("🔍 Cooldown selesai — cari raid berikutnya...", Color3.fromRGB(100,255,150))
                if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
            end
        end

        _raidInterrupt = false
        _siegeInterrupt = false
        RAID.running = false
        RAID.inMap = false
        _raidOn = false
        RaidStatusUpdate("⏹ Idle — Auto Raid berhenti", Color3.fromRGB(160,148,135))
        if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
    end)
end



-- ══════════════════════════════════════════════════════════════

-- ============================================================
end -- do (webhook + raid logic)

-- ============================================================
end)() -- [FIX] end AutoRaid+Webhook isolated scope

-- ============================================================
-- PANEL : AUTOMATION — Auto Raid UI
-- ============================================================
;(function()
    local p = NewPanel("autoraid")
    SectionHeader(p,"AUTOMATION",0)

    -- ════════════════════════════════════════════
    -- DROPDOWN 1: AUTO RAID
    -- ════════════════════════════════════════════
    local raidOpen = false

    local raidHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,42))
    raidHeader.LayoutOrder = 1; Corner(raidHeader,10); Stroke(raidHeader,C.ACC,1,0.4)
    local raidArrow = Label(raidHeader,"▶",13,C.ACC2,Enum.Font.GothamBold)
    raidArrow.Size = UDim2.new(0,22,1,0); raidArrow.Position = UDim2.new(0,10,0,0)
    local raidHeaderLbl = Label(raidHeader,"⚡  Auto Raid",14,C.TXT,Enum.Font.GothamBold)
    raidHeaderLbl.Size = UDim2.new(1,-50,1,0); raidHeaderLbl.Position = UDim2.new(0,34,0,0)

    local raidBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
    raidBody.LayoutOrder = 2; raidBody.ClipsDescendants = true
    Corner(raidBody,10); Stroke(raidBody,C.ACC,1,0.25); raidBody.Visible = false

    local raidInner = Frame(raidBody, C.BLACK, UDim2.new(1,-16,0,0))
    raidInner.BackgroundTransparency = 1; raidInner.Position = UDim2.new(0,8,0,8)
    local raidLayout = New("UIListLayout",{Parent=raidInner, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,6)})

    function ResizeRaidBody()
        raidLayout:ApplyLayout()
        local h = raidLayout.AbsoluteContentSize.Y + 16
        raidInner.Size = UDim2.new(1,0,0,h)
        raidBody.Size  = UDim2.new(1,0,0,h+16)
    end

    raidHeader.MouseButton1Click:Connect(function()
        raidOpen = not raidOpen; raidBody.Visible = raidOpen
        raidArrow.Text = raidOpen and "▼" or "▶"
        if raidOpen then task.defer(ResizeRaidBody) end
    end)

    -- ── STATUS CARD ──
    local statusCard = Frame(raidInner, Color3.fromRGB(30,14,3), UDim2.new(1,0,0,0))
    statusCard.LayoutOrder=0; statusCard.AutomaticSize=Enum.AutomaticSize.Y
    Corner(statusCard,8); Stroke(statusCard,C.ACC,1,0.3)
    Padding(statusCard,8,8,10,10)
    New("UIListLayout",{Parent=statusCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})

    -- Dot + status text row
    local raidDotRow = Frame(statusCard, C.BLACK, UDim2.new(1,0,0,24))
    raidDotRow.BackgroundTransparency=1; raidDotRow.LayoutOrder=0
    local _raidDot = Frame(raidDotRow, Color3.fromRGB(100,100,100), UDim2.new(0,10,0,10))
    _raidDot.Position = UDim2.new(0,0,0.5,-5); Corner(_raidDot,5)
    RAID.dot = _raidDot
    local _raidStatusLbl = Label(raidDotRow,"⏹ Idle",10.5,C.TXT2,Enum.Font.Gotham)
    _raidStatusLbl.Size = UDim2.new(1,-18,1,0); _raidStatusLbl.Position = UDim2.new(0,18,0,0)
    _raidStatusLbl.TextTruncate = Enum.TextTruncate.AtEnd
    RAID.statusLbl = _raidStatusLbl

    -- Counter: hanya Sukses (masuk+bunuh bos+ambil reward)
    local raidCountRow = Frame(statusCard, Color3.fromRGB(22,12,2), UDim2.new(1,0,0,22))
    raidCountRow.LayoutOrder=1; Corner(raidCountRow,6); Stroke(raidCountRow,C.BORD,1,0.5)
    local _raidSuksesLbl = Label(raidCountRow,"Sukses: 0",10,Color3.fromRGB(100,255,150),Enum.Font.GothamBold)
    _raidSuksesLbl.Size=UDim2.new(1,0,1,0); _raidSuksesLbl.Position=UDim2.new(0,8,0,0)
    RAID.suksesLbl = _raidSuksesLbl
    -- Legacy refs (dipakai RaidCounterUpdate)
    RAID.loopLbl = nil
    RAID.killLbl = nil

    -- ════════════════════════════════════════════
    -- DIFFICULTY SELECTOR
    -- ════════════════════════════════════════════
    local diffHdr = Label(raidInner,"DIFFICULTY",10,C.TXT3,Enum.Font.GothamBold)
    diffHdr.LayoutOrder=2; diffHdr.Size=UDim2.new(1,0,0,16)

    local diffCard = Frame(raidInner,C.SURFACE,UDim2.new(1,0,0,38))
    diffCard.LayoutOrder=3; Corner(diffCard,8); Stroke(diffCard,C.BORD,1,0.4); Padding(diffCard,6,6,12,8)
    local diffTitle = Label(diffCard,"Mode",12,C.TXT,Enum.Font.GothamBold)
    diffTitle.Size=UDim2.new(0.38,0,1,0)

    local DIFF_OPTS   = {"Easy","Medium","Hard","Preferred"}
    local DIFF_KEYS   = {"easy","medium","hard","preferred"}
    local DIFF_COLORS = {
        Color3.fromRGB(80,220,80),
        Color3.fromRGB(255,200,60),
        Color3.fromRGB(255,80,80),
        Color3.fromRGB(100,180,255),
    }
    local DIFF_DESC = {
        "Easy = map angka terkecil",
        "Medium = map angka tengah",
        "Hard = map angka terbesar",
        "Preferred = map pilihan kamu",
    }
    local curDiff = 1

    local diffDDBtn = Btn(diffCard,C.BG3,UDim2.new(0.62,-4,1,-4))
    diffDDBtn.Position=UDim2.new(0.38,0,0,2); Corner(diffDDBtn,6); Stroke(diffDDBtn,C.BORD,1,0.2)
    local diffDDLbl = Label(diffDDBtn,"  "..DIFF_OPTS[curDiff],11,DIFF_COLORS[curDiff],Enum.Font.GothamBold)
    diffDDLbl.Size=UDim2.new(1,-18,1,0)
    local diffArr = Label(diffDDBtn,"v",11,C.TXT2,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    diffArr.Size=UDim2.new(0,16,1,0); diffArr.Position=UDim2.new(1,-18,0,0)
    RAID.diffLbl = diffDDLbl

    local diffDesc = Label(raidInner,DIFF_DESC[curDiff],10,C.TXT3,Enum.Font.Gotham)
    diffDesc.LayoutOrder=4; diffDesc.Size=UDim2.new(1,0,0,14)

    -- Preferred map card (hidden by default) — rebuilt, proper sizing
    -- Layout: padding 8px semua sisi, row title (18px) + gap (6px) + row button (24px) = 48px content + 16px padding = 64px total
    local prefCard = Frame(raidInner,C.SURFACE,UDim2.new(1,0,0,64))
    prefCard.LayoutOrder=5; Corner(prefCard,8); Stroke(prefCard,Color3.fromRGB(100,180,255),1,0.3)
    prefCard.ClipsDescendants=true
    prefCard.Visible = false

    -- Row 1: judul kiri + counter kanan
    local prefRow1 = Frame(prefCard,C.SURFACE,UDim2.new(1,-16,0,18))
    prefRow1.Position=UDim2.new(0,8,0,8); prefRow1.BackgroundTransparency=1
    local prefTitle = Label(prefRow1,"🗺  Map Preferred",11,Color3.fromRGB(120,190,255),Enum.Font.GothamBold)
    prefTitle.Size=UDim2.new(0.6,0,1,0); prefTitle.Position=UDim2.new(0,0,0,0)
    local prefCountLbl = Label(prefRow1,"0 map dipilih",10,C.TXT3,Enum.Font.Gotham,Enum.TextXAlignment.Right)
    prefCountLbl.Size=UDim2.new(0.4,0,1,0); prefCountLbl.Position=UDim2.new(0.6,0,0,0)

    -- Row 2: dropdown button full width
    local prefDDBtn = Btn(prefCard,C.BG3,UDim2.new(1,-16,0,24))
    prefDDBtn.Position=UDim2.new(0,8,0,32); Corner(prefDDBtn,6); Stroke(prefDDBtn,Color3.fromRGB(100,180,255),1,0.4)
    local prefDDLbl = Label(prefDDBtn,"  Klik untuk pilih map...",10,C.TXT3,Enum.Font.Gotham)
    prefDDLbl.Size=UDim2.new(1,-22,1,0); prefDDLbl.Position=UDim2.new(0,6,0,0)
    local prefArr = Label(prefDDBtn,"▾",11,Color3.fromRGB(100,180,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    prefArr.Size=UDim2.new(0,18,1,0); prefArr.Position=UDim2.new(1,-20,0,0)

    function UpdatePrefLabel()
        local n = 0; for _ in pairs(RAID.preferMaps) do n=n+1 end
        prefCountLbl.Text = n == 0 and "0 map dipilih" or n.." map dipilih"
        if n == 0 then
            prefDDLbl.Text = "  Klik untuk pilih map..."
            prefDDLbl.TextColor3 = C.TXT3
        else
            local names = {}
            for mn in pairs(RAID.preferMaps) do table.insert(names, "Map "..mn) end
            table.sort(names)
            prefDDLbl.Text = "  "..table.concat(names, ", ")
            prefDDLbl.TextColor3 = Color3.fromRGB(100,180,255)
        end
    end

    -- Preferred map dropdown popup
    prefDDBtn.MouseButton1Click:Connect(function()
        CloseActiveDD()
        local absPos  = prefDDBtn.AbsolutePosition
        local absSize = prefDDBtn.AbsoluteSize
        local ITEM_H  = 26
        local contentH = 18 * (ITEM_H + 2) + 42
        local scrollH  = math.min(contentH, _isSmallScreen and 180 or 210)
        local HEADER_H = 32

        local popup = Instance.new("Frame")
        popup.Parent=DDLayer; popup.BackgroundColor3=C.DD_BG; popup.BorderSizePixel=0
        popup.Size=UDim2.new(0,absSize.X+20,0,HEADER_H+scrollH)
        popup.Position=UDim2.new(0,absPos.X,0,absPos.Y+absSize.Y+3)
        popup.ZIndex=9999; popup.ClipsDescendants=true
        Corner(popup,8); Stroke(popup,Color3.fromRGB(100,180,255),1,0.2)

        local hdr=Frame(popup,Color3.fromRGB(20,40,80),UDim2.new(1,0,0,HEADER_H)); hdr.ZIndex=9999
        local cntLbl=Label(hdr,"0/18 dipilih",10.5,Color3.fromRGB(100,180,255),Enum.Font.GothamBold)
        cntLbl.Size=UDim2.new(0.6,0,1,0); cntLbl.Position=UDim2.new(0,8,0,0); cntLbl.ZIndex=9999
        local clrBtn=Btn(hdr,Color3.fromRGB(120,30,30),UDim2.new(0,48,0,20))
        clrBtn.Position=UDim2.new(1,-54,0.5,-10); Corner(clrBtn,5); clrBtn.ZIndex=9999
        local cL=Label(clrBtn,"Clear",10,Color3.fromRGB(255,255,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        cL.Size=UDim2.new(1,0,1,0); cL.ZIndex=9999

        local sf=Instance.new("ScrollingFrame")
        sf.Parent=popup; sf.BackgroundTransparency=1; sf.BorderSizePixel=0
        sf.Position=UDim2.new(0,0,0,HEADER_H); sf.Size=UDim2.new(1,0,0,scrollH)
        sf.CanvasSize=UDim2.new(0,0,0,contentH)
        sf.ScrollBarThickness=5; sf.ScrollBarImageColor3=Color3.fromRGB(100,180,255)
        sf.ScrollingDirection=Enum.ScrollingDirection.Y; sf.ZIndex=9999
        Instance.new("UIListLayout",sf).SortOrder=Enum.SortOrder.LayoutOrder
        local sfp=Instance.new("UIPadding",sf)
        sfp.PaddingTop=UDim.new(0,4); sfp.PaddingLeft=UDim.new(0,4); sfp.PaddingRight=UDim.new(0,6)

        -- Dropdown preferred: static Map 1-18 (nomor map Raid)
        -- Player pilih dulu, nanti dicocokkan dengan snapshot saat raid masuk
        local rowRefs = {}

        function UpdateCnt()
            local n=0; for _ in pairs(RAID.preferMaps) do n=n+1 end
            cntLbl.Text=n.."/18 dipilih"
        end

        function BuildRows()
            for _, ref in pairs(rowRefs) do
                if ref.btn and ref.btn.Parent then ref.btn:Destroy() end
            end
            rowRefs = {}

            for mn = 1, 18 do
                local item=Instance.new("TextButton",sf)
                item.Size=UDim2.new(1,-4,0,ITEM_H); item.LayoutOrder=mn
                item.BackgroundColor3=RAID.preferMaps[mn] and Color3.fromRGB(20,50,100) or Color3.fromRGB(28,20,12)
                item.BackgroundTransparency=0.3; item.BorderSizePixel=0
                item.Text=""; item.AutoButtonColor=false; item.ZIndex=9999
                Instance.new("UICorner",item).CornerRadius=UDim.new(0,5)
                local tick=Instance.new("TextLabel",item)
                tick.Size=UDim2.new(0,18,1,0); tick.BackgroundTransparency=1
                tick.Text=RAID.preferMaps[mn] and "[v]" or ""; tick.TextSize=11
                tick.Font=Enum.Font.GothamBold; tick.TextColor3=Color3.fromRGB(100,180,255)
                tick.ZIndex=9999
                local iLbl=Instance.new("TextLabel",item)
                iLbl.Size=UDim2.new(1,-24,1,0); iLbl.Position=UDim2.new(0,20,0,0)
                iLbl.BackgroundTransparency=1
                iLbl.Text="  Map "..mn.." — "..(MAP_NAMES[mn] or "Map "..mn)
                iLbl.TextSize=10; iLbl.Font=Enum.Font.GothamBold
                iLbl.TextColor3=RAID.preferMaps[mn] and Color3.fromRGB(100,180,255) or C.TXT
                iLbl.TextXAlignment=Enum.TextXAlignment.Left; iLbl.ZIndex=9999
                iLbl.TextTruncate=Enum.TextTruncate.AtEnd
                rowRefs[mn]={btn=item,tick=tick,lbl=iLbl}
                local mn_l=mn
                item.MouseButton1Click:Connect(function()
                    RAID.preferMaps[mn_l]=not RAID.preferMaps[mn_l] or nil
                    rowRefs[mn_l].tick.Text = RAID.preferMaps[mn_l] and "[v]" or ""
                    rowRefs[mn_l].btn.BackgroundColor3 = RAID.preferMaps[mn_l] and Color3.fromRGB(20,50,100) or Color3.fromRGB(28,20,12)
                    rowRefs[mn_l].lbl.TextColor3 = RAID.preferMaps[mn_l] and Color3.fromRGB(100,180,255) or C.TXT
                    UpdateCnt(); UpdatePrefLabel()
                end)
            end
            sf.CanvasSize = UDim2.new(0,0,0,18*(ITEM_H+2)+8)
            UpdateCnt()
        end

        BuildRows()

        -- Auto-refresh rows setiap kali RAID_ID_LIST berubah
        local prevRaidCount = #RAID_ID_LIST
        local refreshConn
        refreshConn = RunService.Heartbeat:Connect(function()
            if not popup.Parent then
                refreshConn:Disconnect(); return
            end
            if #RAID_ID_LIST ~= prevRaidCount then
                prevRaidCount = #RAID_ID_LIST
                BuildRows()
            end
        end)

        clrBtn.MouseButton1Click:Connect(function()
            for mn = 1, 18 do RAID.preferMaps[mn] = nil end
            BuildRows(); UpdatePrefLabel()
        end)
        DDLayer.Visible=true
        _activeDDClose=function() popup:Destroy(); DDLayer.Visible=false end
    end)

    -- Difficulty dropdown popup
    diffDDBtn.MouseButton1Click:Connect(function()
        CloseActiveDD()
        local absPos  = diffDDBtn.AbsolutePosition
        local absSize = diffDDBtn.AbsoluteSize
        local ITEM_H  = 28

        local popup = Instance.new("Frame")
        popup.Parent=DDLayer; popup.BackgroundColor3=C.DD_BG; popup.BorderSizePixel=0
        popup.Size=UDim2.new(0,absSize.X+10,0,#DIFF_OPTS*(ITEM_H+2)+12)
        popup.Position=UDim2.new(0,absPos.X,0,absPos.Y+absSize.Y+3)
        popup.ZIndex=9999
        Corner(popup,8); Stroke(popup,C.BORD2,1,0.2)

        local ll=Instance.new("UIListLayout",popup); ll.Padding=UDim.new(0,2); ll.SortOrder=Enum.SortOrder.LayoutOrder
        Instance.new("UIPadding",popup).PaddingTop=UDim.new(0,4)

        local irefs = {}
        for i,opt in ipairs(DIFF_OPTS) do
            local item=Instance.new("TextButton",popup)
            item.Size=UDim2.new(1,-8,0,ITEM_H); item.LayoutOrder=i
            item.BackgroundColor3=i==curDiff and Color3.fromRGB(60,30,5) or Color3.fromRGB(28,20,12)
            item.BackgroundTransparency=i==curDiff and 0 or 0.4
            item.BorderSizePixel=0; item.Text=""; item.AutoButtonColor=false; item.ZIndex=9999
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)
            local iL=Instance.new("TextLabel",item)
            iL.Size=UDim2.new(1,-8,1,0); iL.Position=UDim2.new(0,8,0,0)
            iL.BackgroundTransparency=1; iL.Text=opt; iL.TextSize=11
            iL.Font=Enum.Font.GothamBold; iL.TextColor3=DIFF_COLORS[i]
            iL.TextXAlignment=Enum.TextXAlignment.Left; iL.ZIndex=9999
            irefs[i]={btn=item,lbl=iL}
            local ii=i
            item.MouseButton1Click:Connect(function()
                -- Tutup popup dulu sebelum update apapun
                CloseActiveDD()
                curDiff=ii
                RAID.difficulty=DIFF_KEYS[ii]
                RAID.snapshotMapId=nil
                ResetSnapshot()
                diffDDLbl.Text="  "..DIFF_OPTS[ii]
                diffDDLbl.TextColor3=DIFF_COLORS[ii]
                diffDesc.Text=DIFF_DESC[ii]
                prefCard.Visible = (DIFF_KEYS[ii]=="preferred")
                task.defer(ResizeRaidBody)
            end)
        end
        DDLayer.Visible=true
        _activeDDClose=function() popup:Destroy(); DDLayer.Visible=false end
    end)

    -- ════════════════════════════════════════════
    -- [v114] RUNE MAP — Filter Grade Minimum
    -- ════════════════════════════════════════════
    local runeHdr = Label(raidInner,"RUNE MAP",10,C.TXT3,Enum.Font.GothamBold)
    runeHdr.LayoutOrder=6; runeHdr.Size=UDim2.new(1,0,0,16)

    local runeCard = Frame(raidInner,C.SURFACE,UDim2.new(1,0,0,0))
    runeCard.LayoutOrder=7; runeCard.AutomaticSize=Enum.AutomaticSize.Y
    Corner(runeCard,8); Stroke(runeCard,Color3.fromRGB(180,100,255),1,0.4)
    New("UIPadding",{Parent=runeCard,
        PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,8),
        PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)})
    local runeInner = Frame(runeCard,C.BLACK,UDim2.new(1,0,0,0))
    runeInner.BackgroundTransparency=1; runeInner.AutomaticSize=Enum.AutomaticSize.Y
    New("UIListLayout",{Parent=runeInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

    -- Toggle Rune Map ON/OFF
    local runeToggleRow = Frame(runeInner,Color3.fromRGB(30,15,45),UDim2.new(1,0,0,46))
    runeToggleRow.LayoutOrder=0; Corner(runeToggleRow,8)
    Stroke(runeToggleRow,Color3.fromRGB(160,80,255),1,0.4)
    local runeTL = Label(runeToggleRow,"🔮  Rune Map",13,C.TXT,Enum.Font.GothamBold)
    runeTL.Size=UDim2.new(0.7,0,0,20); runeTL.Position=UDim2.new(0,10,0,6)
    local runeTSub = Label(runeToggleRow,"Filter raid berdasarkan minimum grade",9.5,C.TXT3,Enum.Font.Gotham)
    runeTSub.Size=UDim2.new(0.7,0,0,14); runeTSub.Position=UDim2.new(0,10,0,26)
    local runePill = Btn(runeToggleRow,Color3.fromRGB(60,20,80),UDim2.new(0,50,0,26))
    runePill.AnchorPoint=Vector2.new(1,0.5); runePill.Position=UDim2.new(1,-10,0.5,0); Corner(runePill,13)
    local runeKnob = Frame(runePill,Color3.fromRGB(130,60,180),UDim2.new(0,20,0,20))
    runeKnob.AnchorPoint=Vector2.new(0,0.5); runeKnob.Position=UDim2.new(0,3,0.5,0); Corner(runeKnob,10)

    -- Label status rune
    local runeStatusLbl = Label(runeInner,"Status: Nonaktif",9.5,C.TXT3,Enum.Font.Gotham)
    runeStatusLbl.LayoutOrder=1; runeStatusLbl.Size=UDim2.new(1,0,0,14)

    -- Grade selector grid
    local gradeTitle = Label(runeInner,"Minimum Grade (pilih satu atau lebih):",10,C.TXT2,Enum.Font.GothamBold)
    gradeTitle.LayoutOrder=2; gradeTitle.Size=UDim2.new(1,0,0,16)

    local gradeGrid = Frame(runeInner,C.BLACK,UDim2.new(1,0,0,0))
    gradeGrid.BackgroundTransparency=1; gradeGrid.LayoutOrder=3
    gradeGrid.AutomaticSize=Enum.AutomaticSize.Y
    New("UIGridLayout",{
        Parent=gradeGrid,
        CellSize=UDim2.new(0,_isSmallScreen and 46 or 52,0,28),
        CellPadding=UDim2.new(0,4,0,4),
        SortOrder=Enum.SortOrder.LayoutOrder,
    })

    local GRADE_COLORS_UI = {
        ["E"]=Color3.fromRGB(150,150,150),
        ["D"]=Color3.fromRGB(100,200,100),
        ["C"]=Color3.fromRGB(80,180,255),
        ["B"]=Color3.fromRGB(100,140,255),
        ["A"]=Color3.fromRGB(180,100,255),
        ["S"]=Color3.fromRGB(255,180,50),
        ["SS"]=Color3.fromRGB(255,220,0),   -- [v115] SS: kuning terang
        ["G"]=Color3.fromRGB(255,120,40),
        ["N"]=Color3.fromRGB(255,80,80),
        ["M"]=Color3.fromRGB(255,60,120),
        ["M+"]=Color3.fromRGB(220,40,180),
        ["M++"]=Color3.fromRGB(200,30,255),
    }

    local gradeRefs = {}

    local function UpdateRuneStatus()
        local activeGrades = {}
        for _, g in ipairs(GRADE_LIST) do
            if RAID.runeGrades[g] then table.insert(activeGrades, g) end
        end
        local on = RAID.runeEnabled
        if not on then
            runeStatusLbl.Text = "Status: Nonaktif"
            runeStatusLbl.TextColor3 = C.TXT3
        elseif #activeGrades == 0 then
            runeStatusLbl.Text = "Status: Aktif — semua grade (tidak ada filter)"
            runeStatusLbl.TextColor3 = Color3.fromRGB(100,220,100)
        else
            -- Cari minimum rank
            local minRank = 99
            for _, g in ipairs(activeGrades) do
                local r = GRADE_RANK[g] or 99
                if r < minRank then minRank = r end
            end
            -- Cari nama grade minimum
            local minGrade = "?"
            for g, r in pairs(GRADE_RANK) do
                if r == minRank then minGrade = g end
            end
            runeStatusLbl.Text = "Status: Aktif — minimum ["..minGrade.."] ke atas"
            runeStatusLbl.TextColor3 = Color3.fromRGB(200,120,255)
        end
        task.defer(ResizeRaidBody)
    end

    for i, grade in ipairs(GRADE_LIST) do
        local g_l = grade
        local col = GRADE_COLORS_UI[grade] or C.ACC
        local btn = Btn(gradeGrid,Color3.fromRGB(28,16,4),UDim2.new(0,1,0,1))
        btn.LayoutOrder=i; Corner(btn,6)
        Stroke(btn,col,1,0.6)
        local lbl = Label(btn,grade,10.5,col,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        lbl.Size=UDim2.new(1,0,1,0)
        gradeRefs[grade] = {btn=btn, lbl=lbl}

        btn.MouseButton1Click:Connect(function()
            RAID.runeGrades[g_l] = not RAID.runeGrades[g_l] or nil
            local active = RAID.runeGrades[g_l]
            TweenService:Create(btn,TweenInfo.new(0.14),{
                BackgroundColor3 = active and Color3.fromRGB(50,20,80) or Color3.fromRGB(28,16,4)
            }):Play()
            local stk = btn:FindFirstChildWhichIsA("UIStroke")
            if stk then stk.Transparency = active and 0 or 0.6 end
            lbl.TextColor3 = active and Color3.fromRGB(255,255,255) or col
            UpdateRuneStatus()
        end)
    end

    -- Toggle ON/OFF rune map
    runePill.MouseButton1Click:Connect(function()
        RAID.runeEnabled = not RAID.runeEnabled
        local on = RAID.runeEnabled
        TweenService:Create(runePill,TweenInfo.new(0.16),{
            BackgroundColor3 = on and Color3.fromRGB(140,60,220) or Color3.fromRGB(60,20,80)
        }):Play()
        TweenService:Create(runeKnob,TweenInfo.new(0.16),{
            Position = on and UDim2.new(1,-23,0.5,0) or UDim2.new(0,3,0.5,0),
            BackgroundColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(130,60,180),
        }):Play()
        runeToggleRow.BackgroundColor3 = on and Color3.fromRGB(45,20,65) or Color3.fromRGB(30,15,45)
        -- Kalau Rune Map ON tapi difficulty bukan preferred → switch ke preferred
        if on and RAID.difficulty ~= "preferred" then
            RAID.difficulty = "preferred"
            curDiff = 4
            diffDDLbl.Text = "  "..DIFF_OPTS[4]
            diffDDLbl.TextColor3 = DIFF_COLORS[4]
            diffDesc.Text = DIFF_DESC[4]
            prefCard.Visible = true
        end
        UpdateRuneStatus()
        task.defer(ResizeRaidBody)
    end)

    UpdateRuneStatus()

    -- ════════════════════════════════════════════
    -- [v115] SCAN CACHE — Hasil scan chat (history + realtime)
    -- ════════════════════════════════════════════
    local scanHdr = Label(raidInner,"HASIL SCAN CHAT",10,C.TXT3,Enum.Font.GothamBold)
    scanHdr.LayoutOrder=8; scanHdr.Size=UDim2.new(1,0,0,16)

    local scanCard = Frame(raidInner,Color3.fromRGB(12,20,12),UDim2.new(1,0,0,0))
    scanCard.LayoutOrder=9; scanCard.AutomaticSize=Enum.AutomaticSize.Y
    Corner(scanCard,8); Stroke(scanCard,Color3.fromRGB(80,200,100),1,0.4)
    New("UIPadding",{Parent=scanCard,
        PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,8),
        PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)})
    local scanInner = Frame(scanCard,C.BLACK,UDim2.new(1,0,0,0))
    scanInner.BackgroundTransparency=1; scanInner.AutomaticSize=Enum.AutomaticSize.Y
    New("UIListLayout",{Parent=scanInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)})

    local scanSubLbl = Label(scanInner,"✅ Auto scan saat load — update realtime dari chat",
        9, Color3.fromRGB(140,210,140), Enum.Font.Gotham)
    scanSubLbl.Size=UDim2.new(1,0,0,14); scanSubLbl.LayoutOrder=0

    -- Refs untuk rows yang dirender ulang
    local _scanRowObjs = {}

    local function RebuildScanCache()
        for _, obj in ipairs(_scanRowObjs) do
            if obj and obj.Parent then obj:Destroy() end
        end
        _scanRowObjs = {}

        local hasData = false
        for mn = 1, 18 do
            local g = _runeGradeCache[mn]
            if g then
                hasData = true
                local col = GRADE_COLORS_UI[g] or C.ACC
                local row = Frame(scanInner,Color3.fromRGB(18,28,18),UDim2.new(1,0,0,22))
                row.LayoutOrder = 10 + mn; Corner(row,4)

                local mapL = Label(row,"Map "..mn,9.5,C.TXT2,Enum.Font.GothamBold)
                mapL.Size=UDim2.new(0,42,1,0); mapL.Position=UDim2.new(0,6,0,0)

                local nameL = Label(row,(MAP_NAMES[mn] or ""),9,C.DIM,Enum.Font.Gotham)
                nameL.Size=UDim2.new(1,-80,1,0); nameL.Position=UDim2.new(0,52,0,0)
                nameL.TextTruncate=Enum.TextTruncate.AtEnd

                local gradeL = Label(row,"["..g.."]",10,col,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
                gradeL.Size=UDim2.new(0,32,1,0); gradeL.Position=UDim2.new(1,-34,0,0)

                table.insert(_scanRowObjs, row)
            end
        end

        if not hasData then
            local empty = Label(scanInner,"⏳ Belum ada data — tunggu notif raid muncul di chat",
                9, C.DIM, Enum.Font.Gotham)
            empty.Size=UDim2.new(1,0,0,14); empty.LayoutOrder=11
            table.insert(_scanRowObjs, empty)
        end
        task.defer(ResizeRaidBody)
    end

    RebuildScanCache()

    -- Auto-refresh saat cache berubah (cek tiap 2 detik)
    local _prevCacheSize = 0
    task.spawn(function()
        while ScreenGui.Parent do
            task.wait(2)
            local sz = 0
            for _ in pairs(_runeGradeCache) do sz = sz + 1 end
            if sz ~= _prevCacheSize then
                _prevCacheSize = sz
                RebuildScanCache()
            end
        end
    end)

    -- ════════════════════════════════════════════
    -- KONTROL TOGGLE
    -- ════════════════════════════════════════════
    local kontrolHdr = Label(raidInner,"KONTROL",10,C.TXT3,Enum.Font.GothamBold)
    kontrolHdr.LayoutOrder=11; kontrolHdr.Size=UDim2.new(1,0,0,16)

    local ctrlRow = Frame(raidInner,Color3.fromRGB(35,15,2),UDim2.new(1,0,0,50))
    ctrlRow.LayoutOrder=12; Corner(ctrlRow,10); Stroke(ctrlRow,C.ACC,1.5,0.2)
    local mL = Label(ctrlRow,"Auto Raid",13,C.TXT,Enum.Font.GothamBold)
    mL.Size=UDim2.new(0.65,0,0,20); mL.Position=UDim2.new(0,12,0,8)
    local mS = Label(ctrlRow,"Jalankan loop raid otomatis",10,C.TXT3,Enum.Font.Gotham)
    mS.Size=UDim2.new(0.65,0,0,14); mS.Position=UDim2.new(0,12,0,28)
    local pill = Btn(ctrlRow,Color3.fromRGB(120,40,0),UDim2.new(0,50,0,26))
    pill.AnchorPoint=Vector2.new(1,0.5); pill.Position=UDim2.new(1,-12,0.5,0); Corner(pill,13)
    local knob = Frame(pill,Color3.fromRGB(190,130,70),UDim2.new(0,20,0,20))
    knob.AnchorPoint=Vector2.new(0,0.5); knob.Position=UDim2.new(0,3,0.5,0); Corner(knob,10)
    pill.MouseButton1Click:Connect(function()
        _raidOn=not _raidOn
        TweenService:Create(pill,TweenInfo.new(0.16),{BackgroundColor3=_raidOn and C.ACC or Color3.fromRGB(120,40,0)}):Play()
        TweenService:Create(knob,TweenInfo.new(0.16),{
            Position=_raidOn and UDim2.new(1,-23,0.5,0) or UDim2.new(0,3,0.5,0),
            BackgroundColor3=_raidOn and Color3.fromRGB(255,255,255) or Color3.fromRGB(190,130,70),
        }):Play()
        ctrlRow.BackgroundColor3=_raidOn and Color3.fromRGB(50,25,3) or Color3.fromRGB(35,15,2)
        if _raidOn then
            StartRaidLoop()
        else
            StopRaid()
            RaidStatusUpdate("Idle — Auto Raid dimatikan",Color3.fromRGB(160,148,135))
        end
    end)

    -- Toggle Auto Kill Boss
    local bossRow = Frame(raidInner,Color3.fromRGB(35,15,2),UDim2.new(1,0,0,50))
    bossRow.LayoutOrder=13; Corner(bossRow,10); Stroke(bossRow,Color3.fromRGB(180,60,60),1,0.3)
    local bL = Label(bossRow,"Auto Kill Boss",13,C.TXT,Enum.Font.GothamBold)
    bL.Size=UDim2.new(0.65,0,0,20); bL.Position=UDim2.new(0,12,0,8)
    local bS = Label(bossRow,"TP ke raja & serang sampai mati",10,C.TXT3,Enum.Font.Gotham)
    bS.Size=UDim2.new(0.65,0,0,14); bS.Position=UDim2.new(0,12,0,28)
    local bPill = Btn(bossRow,Color3.fromRGB(80,20,20),UDim2.new(0,50,0,26))
    bPill.AnchorPoint=Vector2.new(1,0.5); bPill.Position=UDim2.new(1,-12,0.5,0); Corner(bPill,13)
    local bKnob = Frame(bPill,Color3.fromRGB(160,80,80),UDim2.new(0,20,0,20))
    bKnob.AnchorPoint=Vector2.new(0,0.5); bKnob.Position=UDim2.new(0,3,0.5,0); Corner(bKnob,10)
    bPill.MouseButton1Click:Connect(function()
        RAID.autoKillBoss = not RAID.autoKillBoss
        local on = RAID.autoKillBoss
        TweenService:Create(bPill,TweenInfo.new(0.16),{BackgroundColor3=on and Color3.fromRGB(200,50,50) or Color3.fromRGB(80,20,20)}):Play()
        TweenService:Create(bKnob,TweenInfo.new(0.16),{
            Position=on and UDim2.new(1,-23,0.5,0) or UDim2.new(0,3,0.5,0),
            BackgroundColor3=on and Color3.fromRGB(255,255,255) or Color3.fromRGB(160,80,80),
        }):Play()
        bossRow.BackgroundColor3=on and Color3.fromRGB(50,10,10) or Color3.fromRGB(35,15,2)
    end)

    task.defer(ResizeRaidBody)

end)()


-- ============================================================
-- AUTO SIEGE — v96
-- Flow: EnterCityRaidMap → StartLocalPlayerTeleport → LocalTpSuccess
--       → MA V2 serang semua enemy sampai habis → GainRaidsRewards(1)
--       → TipsPanel hide/restore → MA biasa resume setelah 3 detik
-- Trigger: Listener notif UpdateCityRaidInfo + polling fallback tiap 30 detik
-- ============================================================

local SIEGE_DATA = {
    [3]  = {name="Map 3  — Shadow Castle",    cityRaidId=1000001, tpMapId=50201},
    [7]  = {name="Map 7  — Forest of Giants", cityRaidId=1000002, tpMapId=50202},
    [10] = {name="Map 10 — Plagueheart",      cityRaidId=1000003, tpMapId=50203},
    [13] = {name="Map 13 — Demon Castle",     cityRaidId=1000004, tpMapId=50204},
}
local SIEGE_MAP_NUMS = {3, 7, 10, 13}

SIEGE = {
    running   = false,
    thread    = nil,
    inMap     = false,
    mapActive = {[3]=false,[7]=false,[10]=false,[13]=false},
    statusLbl = nil,
    dot       = nil,
    countLbls = {},
    count     = {[3]=0,[7]=0,[10]=0,[13]=0},
    live      = {},  -- {[cityRaidId] = mapNum} — diisi notif server
}
-- [v113] Merge buffer early ke SIEGE.live (event yang datang sebelum GUI ready)
if _siegeLiveEarly then
    for id, mn in pairs(_siegeLiveEarly) do
        SIEGE.live[id] = mn
        warn("[ ASH SIEGE ] ✅ Merge early buffer — Map "..mn.." sudah live")
    end
end

-- ── UI helpers ──
_siegeSessionStart = nil  -- waktu mulai siege session

SiegeStatus = function(msg, color)
    if SIEGE.statusLbl then
        local ts = ""
        if _siegeSessionStart then
            local dur = os.time() - _siegeSessionStart
            ts = string.format("[%02d:%02d:%02d] ", math.floor(dur/3600), math.floor(dur/60)%60, dur%60)
        end
        SIEGE.statusLbl.Text = ts..msg
        SIEGE.statusLbl.TextColor3 = color or C.TXT2
    end
    if SIEGE.dot then
        SIEGE.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100)
    end
end

SiegeCounterUpdate = function()
    for _, mn in ipairs(SIEGE_MAP_NUMS) do
        if SIEGE.countLbls[mn] then
            SIEGE.countLbls[mn].Text = "Sukses: "..(SIEGE.count[mn] or 0)
        end
    end
end

StopSiege = function()
    SIEGE.running    = false
    SIEGE.inMap      = false
    _siegeInterrupt  = false
    if SIEGE.thread then
        pcall(function() task.cancel(SIEGE.thread) end)
        SIEGE.thread = nil
    end
    SiegeStatus("⏹ Idle", Color3.fromRGB(100,100,100))
end

-- ── Wakeup event untuk siege loop ──
-- [v113] Listener UpdateCityRaidInfo sudah dipasang di awal script (pre-wait).
-- ConnectSiegeNotif hanya dipakai untuk reconnect di StartSiegeLoop.
local _siegeNotifConn = nil  -- tidak dipakai lagi, dijaga agar tidak nil-error
local _siegeWakeup    = nil

local function ConnectSiegeNotif()
    -- [v113] Listener sudah aktif di pre-listen block atas.
    -- Fungsi ini hanya memastikan _siegeWakeup ready untuk di-Fire.
    -- Tidak perlu re-connect OnClientEvent (sudah terpasang permanent).
end

-- ── Masuk Siege ──
local function SiegeEnter(mn)
    local d = SIEGE_DATA[mn]
    if not d then return false end
    -- [v109] Flow benar dari SimpleSpy:
    -- EnterCityRaidMap → StartLocalPlayerTeleport → EquipHeroWithData → LocalPlayerTeleportSuccess
    pcall(function()
        Remotes:FindFirstChild("EnterCityRaidMap"):FireServer(d.cityRaidId)
    end)
    task.wait(0.5)
    pcall(function()
        Remotes:FindFirstChild("StartLocalPlayerTeleport"):FireServer({mapId=d.tpMapId})
    end)
    task.wait(0.5)
    pcall(function()
        Remotes:FindFirstChild("EquipHeroWithData"):FireServer()
    end)
    task.wait(0.3)
    pcall(function()
        RE.LocalTpSuccess:InvokeServer()
    end)
    task.wait(1.5)
    return true
end

-- ── MA V2: serang semua enemy sampai benar-benar habis ──
local function SiegeAttackV2(onStatus)
    local emptyT = 0
    while SIEGE.running and SIEGE.inMap do
        local enemies = GetEnemies()
        local alive = 0
        for _, e in ipairs(enemies) do
            if not IsDead(e) then alive = alive + 1 end
        end
        if alive == 0 then
            emptyT = emptyT + 0.08
            if emptyT >= 1.5 then
                if onStatus then onStatus("✅ Semua enemy mati!") end
                return true
            end
            task.wait(0.08); continue
        end
        emptyT = 0
        if onStatus then onStatus("⚔ MA V2 — "..alive.." enemy") end
        for _, e in ipairs(enemies) do
            if not IsDead(e) then
                local hrp = e.model and e.model:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local g, p = e.guid, hrp.Position
                    task.spawn(function()
                        FireAllDamage(g, p)
                        FireHeroRemotes(g, p)
                    end)
                end
            end
        end
        task.wait(0.08)
    end
    return false
end

-- ── Main Siege Loop ──
-- [v113] Fungsi bantu: re-scan state siege via GetCityRaidInfos
local function RescanSiegeLive()
    -- [v115] Sumber 1: merge _siegeChatOpen dari chat scanner
    -- Chat "X, MapName has begun" → _siegeChatOpen[mn] = true
    if _siegeChatOpen then
        local CITY_BY_MAP = {[3]=1000001,[7]=1000002,[10]=1000003,[13]=1000004}
        for mn, isOpen in pairs(_siegeChatOpen) do
            local cid = CITY_BY_MAP[mn]
            if cid then
                if isOpen then
                    SIEGE.live[cid] = mn
                    warn("[ ASH SIEGE ] ✅ Chat cache — Map "..mn.." BUKA")
                else
                    SIEGE.live[cid] = nil
                end
            end
        end
    end
    -- [v115] Sumber 2: remote GetCityRaidInfos (lebih akurat, override chat cache)
    pcall(function()
        local getCR = Remotes:FindFirstChild("GetCityRaidInfos")
        if not getCR then return end
        local result = getCR:InvokeServer()
        if type(result) ~= "table" then return end
        local CITY_TO_MAP = {[1000001]=3,[1000002]=7,[1000003]=10,[1000004]=13}
        for _, entry in ipairs(result) do
            if type(entry) ~= "table" then continue end
            local id     = entry.id
            local action = entry.action
            local mn     = CITY_TO_MAP[id]
            if not mn then continue end
            if action == "OpenCityRaid" then
                SIEGE.live[id] = mn
                warn("[ ASH SIEGE ] ✅ Rescan remote — Map "..mn.." BUKA")
            else
                SIEGE.live[id] = nil
                warn("[ ASH SIEGE ] 🔒 Rescan remote — Map "..mn.." TUTUP")
            end
        end
    end)
end

StartSiegeLoop = function()
    if SIEGE.running then return end
    SIEGE.running = true
    SIEGE.inMap   = false
    _siegeSessionStart = os.time()
    for _, mn in ipairs(SIEGE_MAP_NUMS) do SIEGE.count[mn] = 0 end
    SiegeCounterUpdate()

    if _siegeWakeup then pcall(function() _siegeWakeup:Destroy() end) end
    _siegeWakeup = Instance.new("BindableEvent")

    -- [v113] Merge early buffer ke SIEGE.live saat loop mulai
    if _siegeLiveEarly then
        for id, mn in pairs(_siegeLiveEarly) do
            SIEGE.live[id] = mn
        end
    end

    -- [v115] Merge chat scan cache ke SIEGE.live
    -- (sudah dihandle di dalam RescanSiegeLive)

    -- [v113+v115] Scan awal: chat cache + remote GetCityRaidInfos
    RescanSiegeLive()

    SIEGE.thread = task.spawn(function()
        local _waitingTicks = 0  -- hitung berapa lama sudah waiting

        while SIEGE.running do

            -- Kumpulkan map yang dipilih user
            local toRun = {}
            for _, mn in ipairs(SIEGE_MAP_NUMS) do
                if SIEGE.mapActive[mn] then table.insert(toRun, mn) end
            end

            if #toRun == 0 then
                SiegeStatus("⏳ Pilih map dulu...", Color3.fromRGB(160,148,135))
                if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
                _waitingTicks = 0
                task.wait(1); continue
            end

            -- Cek SIEGE.live untuk map yang dipilih
            local targetMap = nil
            for _, mn in ipairs(toRun) do
                if SIEGE.live[SIEGE_DATA[mn].cityRaidId] then
                    targetMap = mn; break
                end
            end

            if not targetMap then
                -- [v112] MA & Raid tetap jalan saat waiting siege
                local activeFeatures = {}
                if MA.running then table.insert(activeFeatures, "MA") end
                if RAID.running then table.insert(activeFeatures, "Raid") end
                local featStr = #activeFeatures > 0 and " | "..table.concat(activeFeatures,"+").." aktif" or ""
                SiegeStatus("⏳ Waiting Siege"..featStr.."...", Color3.fromRGB(255,200,60))
                if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
                local woke = false
                local conn = _siegeWakeup.Event:Connect(function() woke = true end)
                task.wait(1); conn:Disconnect()
                _waitingTicks = _waitingTicks + 1
                -- [v113] Setiap 10 detik re-scan via GetCityRaidInfos
                -- sebagai fallback kalau notif terlewat
                if _waitingTicks >= 10 then
                    _waitingTicks = 0
                    warn("[ ASH SIEGE ] Re-scan GetCityRaidInfos (fallback)...")
                    RescanSiegeLive()
                end
                continue
            end
            _waitingTicks = 0

            -- ── Masuk map ──
            local d = SIEGE_DATA[targetMap]
            SiegeStatus("🚀 Masuk "..d.name.."...", Color3.fromRGB(180,120,255))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(180,120,255) end

            local ok = SiegeEnter(targetMap)
            if not SIEGE.running then break end
            if not ok then
                -- [v107] Gagal masuk → cooldown 5 detik sebelum coba lagi
                SiegeStatus("⚠ Gagal masuk "..SIEGE_DATA[targetMap].name.." — retry 5s...", Color3.fromRGB(255,150,50))
                task.wait(5)
                continue
            end

            -- ── Pause MA biasa ──
            _siegeInterrupt = true
            SIEGE.inMap     = true

            -- ── Pasang TipsPanel watcher selama di Siege ──
            local _tipsSiegeActive = true
            local _tipsSiegeHidden = {}
            local _tipsSiegeWatch  = PG.ChildAdded:Connect(function(gui)
                if not _tipsSiegeActive then return end
                if gui.Name == "TipsPanel" then
                    task.defer(function()
                        pcall(function()
                            gui.Enabled = false
                            _tipsSiegeHidden[gui] = true
                        end)
                    end)
                end
            end)
            pcall(function()
                local tips = PG:FindFirstChild("TipsPanel")
                if tips then tips.Enabled = false; _tipsSiegeHidden[tips] = true end
            end)

            -- ── MA V2: serang sampai semua habis ──
            SiegeStatus("⚔ "..d.name.." — MA V2 aktif!", Color3.fromRGB(80,220,80))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(80,220,80) end

            SiegeAttackV2(function(msg)
                SiegeStatus(msg, Color3.fromRGB(80,220,80))
            end)

            if not SIEGE.running then
                _tipsSiegeActive = false
                pcall(function() _tipsSiegeWatch:Disconnect() end)
                break
            end

            -- ── Semua enemy habis → GainRaidsRewards ──
            SiegeStatus("🎁 Ambil reward siege...", Color3.fromRGB(255,220,80))
            pcall(function()
                local gainRemote = Remotes:FindFirstChild("GainRaidsRewards")
                if gainRemote then gainRemote:InvokeServer(1) end
            end)
            task.wait(0.5)

            -- ── Stop watcher + restore TipsPanel setelah 60 detik ──
            _tipsSiegeActive = false
            pcall(function() _tipsSiegeWatch:Disconnect() end)
            task.delay(60, function()
                for gui, _ in pairs(_tipsSiegeHidden) do
                    pcall(function()
                        if gui and gui.Parent then gui.Enabled = true end
                    end)
                end
            end)

            -- ── Update counter + status ──
            SIEGE.count[targetMap] = (SIEGE.count[targetMap] or 0) + 1
            SiegeCounterUpdate()
            SIEGE.live[d.cityRaidId] = nil
            SiegeStatus("✅ Selesai "..d.name, Color3.fromRGB(100,255,150))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(100,255,150) end

            -- ── Resume MA biasa setelah 3 detik ──
            SIEGE.inMap     = false
            _siegeInterrupt = false
            task.wait(3)
        end

        _siegeInterrupt = false
        SIEGE.running   = false
        SIEGE.inMap     = false
        if _siegeNotifConn then pcall(function() _siegeNotifConn:Disconnect() end) end
        SiegeStatus("⏹ Idle", Color3.fromRGB(100,100,100))
        if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
    end)
end

-- ============================================================
-- PANEL : AUTO SIEGE (UI) — di dalam panel Automation yang sama
-- ============================================================
;(function()
    local p = Panels["autoraid"]
    if not p then return end

    -- ════════════════════════════════════════════
    -- AUTO SIEGE — Collapsible (seperti Auto Raid)
    -- ════════════════════════════════════════════
    local siegeOpen = false

    local siegeHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,42))
    siegeHeader.LayoutOrder = 20; Corner(siegeHeader,10); Stroke(siegeHeader,Color3.fromRGB(100,160,255),1,0.4)
    local siegeArrow = Label(siegeHeader,"▶",13,Color3.fromRGB(100,160,255),Enum.Font.GothamBold)
    siegeArrow.Size = UDim2.new(0,22,1,0); siegeArrow.Position = UDim2.new(0,10,0,0)
    local siegeHeaderLbl = Label(siegeHeader,"🏰  Auto Siege",14,C.TXT,Enum.Font.GothamBold)
    siegeHeaderLbl.Size = UDim2.new(1,-50,1,0); siegeHeaderLbl.Position = UDim2.new(0,34,0,0)

    local siegeBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
    siegeBody.LayoutOrder = 21; siegeBody.ClipsDescendants = true
    Corner(siegeBody,10); Stroke(siegeBody,Color3.fromRGB(100,160,255),1,0.25); siegeBody.Visible = false

    local siegeInner = Frame(siegeBody, C.BLACK, UDim2.new(1,-16,0,0))
    siegeInner.BackgroundTransparency = 1; siegeInner.Position = UDim2.new(0,8,0,8)
    local siegeLayout = New("UIListLayout",{Parent=siegeInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

    local function ResizeSiegeBody()
        siegeLayout:ApplyLayout()
        local h = siegeLayout.AbsoluteContentSize.Y + 16
        siegeInner.Size = UDim2.new(1,0,0,h)
        siegeBody.Size  = UDim2.new(1,0,0,h+16)
    end

    siegeHeader.MouseButton1Click:Connect(function()
        siegeOpen = not siegeOpen; siegeBody.Visible = siegeOpen
        siegeArrow.Text = siegeOpen and "▼" or "▶"
        if siegeOpen then task.defer(ResizeSiegeBody) end
    end)

    -- Gunakan siegeInner sebagai parent untuk semua konten siege
    local p = siegeInner  -- shadow p agar kode di bawah tetap pakai p

    -- Status bar
    local statusCard = Frame(p, Color3.fromRGB(25,12,2), UDim2.new(1,0,0,32))
    statusCard.LayoutOrder = 0; Corner(statusCard,8); Stroke(statusCard,C.ACC,1,0.3)
    SIEGE.dot = Frame(statusCard, Color3.fromRGB(100,100,100), UDim2.new(0,8,0,8))
    SIEGE.dot.Position = UDim2.new(0,8,0.5,-4); Corner(SIEGE.dot,4)
    SIEGE.statusLbl = Label(statusCard,"⏹ Idle — aktifkan map untuk mulai",10,C.TXT2,Enum.Font.Gotham)
    SIEGE.statusLbl.Size = UDim2.new(1,-24,1,0)
    SIEGE.statusLbl.Position = UDim2.new(0,22,0,0)
    SIEGE.statusLbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- Toggle utama
    ToggleRow(p,"⚡  Auto Siege","ON = masuk siege otomatis + MA V2 aktif",1,function(on)
        if on then StartSiegeLoop() else StopSiege() end
    end)

    -- Map selector card
    local mapCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,0))
    mapCard.LayoutOrder = 2; mapCard.AutomaticSize = Enum.AutomaticSize.Y
    Corner(mapCard,8); Stroke(mapCard,C.BORD,1,0.4)
    New("UIPadding",{Parent=mapCard,
        PaddingTop=UDim.new(0,10), PaddingBottom=UDim.new(0,10),
        PaddingLeft=UDim.new(0,8), PaddingRight=UDim.new(0,8)})
    local mapInner = Frame(mapCard, C.BLACK, UDim2.new(1,0,0,0))
    mapInner.BackgroundTransparency = 1; mapInner.AutomaticSize = Enum.AutomaticSize.Y
    New("UIListLayout",{Parent=mapInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

    local mapTitle = Label(mapInner,"🗺  Pilih Map Target Siege",11,C.ACC2,Enum.Font.GothamBold)
    mapTitle.Size = UDim2.new(1,0,0,18); mapTitle.LayoutOrder = 0

    local MAP_COLORS = {[3]=Color3.fromRGB(255,140,40),[7]=Color3.fromRGB(100,220,80),[10]=Color3.fromRGB(80,180,255),[13]=Color3.fromRGB(200,80,255)}
    local MAP_ICONS  = {[3]="⚔",[7]="🌲",[10]="☠",[13]="😈"}
    local MAP_DESCS  = {[3]="Shadow Castle",[7]="Forest of Giants",[10]="Plagueheart",[13]="Demon Castle"}

    for _, mn in ipairs(SIEGE_MAP_NUMS) do
        local mn_l = mn
        local col  = MAP_COLORS[mn]

        local row = Frame(mapInner, Color3.fromRGB(28,16,4), UDim2.new(1,0,0,46))
        row.LayoutOrder = mn; Corner(row,8); Stroke(row,Color3.fromRGB(90,55,0),1,0.55)

        local ico = Label(row, MAP_ICONS[mn], 18, col, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        ico.Size = UDim2.new(0,30,1,0); ico.Position = UDim2.new(0,8,0,0)

        local nameLbl = Label(row, "Map "..mn, 12, C.TXT, Enum.Font.GothamBold)
        nameLbl.Size = UDim2.new(1,-120,0,17); nameLbl.Position = UDim2.new(0,44,0,6)

        local descLbl = Label(row, MAP_DESCS[mn], 9, C.DIM, Enum.Font.Gotham)
        descLbl.Size = UDim2.new(1,-120,0,13); descLbl.Position = UDim2.new(0,44,0,26)

        SIEGE.countLbls[mn] = Label(row,"Sukses: 0",9,C.ACC2,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
        SIEGE.countLbls[mn].Size = UDim2.new(0,60,1,0)
        SIEGE.countLbls[mn].Position = UDim2.new(1,-118,0,0)

        -- Toggle pill
        local pill = Btn(row, Color3.fromRGB(55,32,4), UDim2.new(0,44,0,24))
        pill.AnchorPoint = Vector2.new(1,0.5); pill.Position = UDim2.new(1,-10,0.5,0); Corner(pill,12)
        local knob = Frame(pill, Color3.fromRGB(130,75,18), UDim2.new(0,18,0,18))
        knob.AnchorPoint = Vector2.new(0,0.5); knob.Position = UDim2.new(0,3,0.5,0); Corner(knob,9)

        pill.MouseButton1Click:Connect(function()
            SIEGE.mapActive[mn_l] = not SIEGE.mapActive[mn_l]
            local active = SIEGE.mapActive[mn_l]

            TweenService:Create(pill, TweenInfo.new(0.16), {
                BackgroundColor3 = active and col or Color3.fromRGB(55,32,4)
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.16), {
                Position         = active and UDim2.new(1,-21,0.5,0) or UDim2.new(0,3,0.5,0),
                BackgroundColor3 = active and Color3.fromRGB(255,255,255) or Color3.fromRGB(130,75,18),
            }):Play()
            TweenService:Create(row, TweenInfo.new(0.16), {
                BackgroundColor3 = active and Color3.fromRGB(40,20,5) or Color3.fromRGB(28,16,4)
            }):Play()
            local stk = row:FindFirstChildWhichIsA("UIStroke")
            if stk then
                stk.Color       = active and col or Color3.fromRGB(90,55,0)
                stk.Transparency = active and 0.3 or 0.55
            end
            nameLbl.TextColor3 = active and col or C.TXT

            local anyActive = false
            for _, m in ipairs(SIEGE_MAP_NUMS) do
                if SIEGE.mapActive[m] then anyActive = true; break end
            end
            if anyActive and not SIEGE.running then
                StartSiegeLoop()
            elseif not anyActive and SIEGE.running then
                StopSiege()
            end
        end)
    end

    -- Stop button
    local stopRow = Frame(p, Color3.fromRGB(55,10,10), UDim2.new(1,0,0,38))
    stopRow.LayoutOrder = 3; Corner(stopRow,10); Stroke(stopRow,Color3.fromRGB(220,50,50),1,0.4)
    local stopBtn = Btn(stopRow, Color3.fromRGB(170,25,25), UDim2.new(0.55,0,0,26))
    stopBtn.AnchorPoint = Vector2.new(0.5,0.5); stopBtn.Position = UDim2.new(0.5,0,0.5,0)
    Corner(stopBtn,8); Stroke(stopBtn,Color3.fromRGB(255,80,80),1,0.3)
    local stopLbl = Label(stopBtn,"⏹  Stop Siege",11,Color3.fromRGB(255,255,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    stopLbl.Size = UDim2.new(1,0,1,0)
    stopBtn.MouseButton1Click:Connect(function()
        for _, mn in ipairs(SIEGE_MAP_NUMS) do SIEGE.mapActive[mn] = false end
        StopSiege()
    end)

    -- Resize siege body setelah semua konten terbuild
    task.defer(ResizeSiegeBody)
end)()



-- PANEL : CLAIM REWARD
-- ============================================================
;(function()
    local p = NewPanel("claim")
    SectionHeader(p,"AUTO CLAIM REWARD",0)

    -- Status label
    local statusCard = Frame(p, Color3.fromRGB(25,12,2), UDim2.new(1,0,0,32))
    statusCard.LayoutOrder = 1; Corner(statusCard,8); Stroke(statusCard,C.ACC,1,0.3)
    local statusLbl = Label(statusCard,"⏹ Idle — tekan Claim All untuk mulai",10,C.TXT2,Enum.Font.Gotham)
    statusLbl.Size = UDim2.new(1,-16,1,0); statusLbl.Position = UDim2.new(0,8,0,0)

    -- Log panel (snipping output)
    local logCard = Frame(p, Color3.fromRGB(15,8,2), UDim2.new(1,0,0,120))
    logCard.LayoutOrder = 2; Corner(logCard,8); Stroke(logCard,C.BORD,1,0.4)
    local logScroll = New("ScrollingFrame",{
        Parent=logCard, Size=UDim2.new(1,-8,1,-8),
        Position=UDim2.new(0,4,0,4),
        BackgroundTransparency=1, BorderSizePixel=0,
        ScrollBarThickness=3, ScrollBarImageColor3=C.ACC,
        CanvasSize=UDim2.new(0,0,0,0),
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
    })
    ListLayout(logScroll,nil,Enum.HorizontalAlignment.Left,2)
    local logLines = {}

    function Log(msg, col)
        -- Print ke console juga
        print("[ASH CLAIM] " .. msg)
        -- Tambah ke GUI log
        local lbl = Label(logScroll, msg, 8, col or C.TXT2, Enum.Font.RobotoMono)
        lbl.Size = UDim2.new(1,0,0,13)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        table.insert(logLines, lbl)
        -- Hapus baris lama kalau lebih dari 30
        if #logLines > 30 then
            logLines[1]:Destroy()
            table.remove(logLines, 1)
        end
        -- Auto scroll ke bawah
        task.defer(function()
            logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
        end)
    end

    function SetStatus(msg, col)
        statusLbl.Text = msg
        statusLbl.TextColor3 = col or C.TXT2
        Log(msg, col)
    end

    -- Helper buat row claim
    function ClaimRow(order, icon, title, desc, fn)
        local row = Frame(p, C.SURFACE, UDim2.new(1,0,0,54))
        row.LayoutOrder = order; Corner(row,9); Stroke(row,C.BORD,1,0.3)
        Padding(row,6,6,10,8)

        local ico = Label(row, icon, 18, C.ACC2, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        ico.Size = UDim2.new(0,24,0,24); ico.Position = UDim2.new(0,0,0.5,-12)

        local ttl = Label(row, title, 11, C.TXT, Enum.Font.GothamBold)
        ttl.Size = UDim2.new(1,-90,0,16); ttl.Position = UDim2.new(0,28,0,4)

        local sub = Label(row, desc, 9, C.DIM, Enum.Font.Gotham)
        sub.Size = UDim2.new(1,-90,0,13); sub.Position = UDim2.new(0,28,0,22)

        local btn = Btn(row, C.ACC, UDim2.new(0,52,0,26))
        btn.AnchorPoint = Vector2.new(1,0.5); btn.Position = UDim2.new(1,-6,0.5,0)
        Corner(btn,8)
        local btnLbl = Label(btn,"CLAIM",9,C.BLACK,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        btnLbl.Size = UDim2.new(1,0,1,0)

        btn.MouseButton1Click:Connect(function()
            btn.BackgroundColor3 = C.DIM
            btnLbl.Text = "..."
            task.spawn(function()
                fn(sub, SetStatus)
                btn.BackgroundColor3 = C.GRN
                btnLbl.Text = "✓"
                task.wait(2)
                btn.BackgroundColor3 = C.ACC
                btnLbl.Text = "CLAIM"
            end)
        end)

        return row, sub
    end

    -- ── Online Reward ──
    ClaimRow(2, "🌐", "Online Reward", "Auto scan & klaim semua online reward", function(sub, status)
        local RE = Remotes:FindFirstChild("ClaimOnlineReward")
        if not RE then status("❌ Remote tidak ditemukan", C.RED); return end
        local claimed = 0
        local tried = 0
        local consecutive_fail = 0

        -- Strategy: scan id 1-500
        -- consecutive_fail hanya mulai dihitung SETELAH claim pertama berhasil
        -- Sebelum claim pertama: tetap scan terus tanpa stop
        -- Setelah claim pertama: stop kalau 15 id berturut-turut gagal (reward habis)
        local ever_claimed = false
        status("🔍 Scanning online reward ids...", C.YEL)

        for id = 1, 500 do
            local ok, res = pcall(function()
                return RE:InvokeServer({id = tostring(id)})
            end)
            tried = tried + 1

            if ok and res == true then
                claimed = claimed + 1
                consecutive_fail = 0
                ever_claimed = true
                Log("✅ id="..id.." diklaim!", C.GRN)
                status("🌐 Claimed "..claimed.." reward (id "..id..")", C.GRN)
            else
                if ever_claimed then
                    -- Sudah pernah claim → mulai hitung fail
                    consecutive_fail = consecutive_fail + 1
                    if consecutive_fail >= 15 then
                        Log("🛑 Stop — 15 fail setelah claim terakhir (id "..id..")", C.DIM)
                        break
                    end
                end
                -- Sebelum claim pertama: scan terus tanpa stop
            end

            task.wait(0.05)
        end

        if claimed > 0 then
            status("✅ Online Reward selesai — "..claimed.." diklaim dari "..tried.." scan", C.GRN)
            sub.Text = "Terakhir: "..claimed.." reward diklaim"
            sub.TextColor3 = C.GRN
        else
            status("ℹ Tidak ada online reward yang bisa diklaim", C.YEL)
            sub.Text = "Semua sudah diklaim / belum tersedia"
        end
    end)

    -- ── Season Task Reward ──
    ClaimRow(3, "📋", "Season Task Reward", "Klaim semua season task reward", function(sub, status)
        local RE = Remotes:FindFirstChild("ClaimSeasonTaskReward")
        if not RE then status("❌ Remote tidak ditemukan", C.RED); return end
        status("⏳ Claiming season task reward...", C.YEL)
        local ok, res = pcall(function() return RE:FireServer() end)
        Log("📋 SeasonTask → ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.RED)
        task.wait(0.5)
        status("✅ Season Task Reward diklaim", C.GRN)
        sub.Text = "Terakhir: berhasil diklaim"
        sub.TextColor3 = C.GRN
    end)

    -- ── Season Pass Reward ──
    ClaimRow(4, "🎫", "Season Pass Reward", "Klaim semua season pass reward", function(sub, status)
        local RE = Remotes:FindFirstChild("ClaimSeasonPassReward")
        if not RE then status("❌ Remote tidak ditemukan", C.RED); return end
        status("⏳ Claiming season pass reward...", C.YEL)
        local ok, res = pcall(function() return RE:FireServer() end)
        Log("🎫 SeasonPass → ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.RED)
        task.wait(0.5)
        status("✅ Season Pass Reward diklaim", C.GRN)
        sub.Text = "Terakhir: berhasil diklaim"
        sub.TextColor3 = C.GRN
    end)

    -- ── 7 Day Login Reward ──
    ClaimRow(5, "📅", "7 Day Login Reward", "Klaim semua hari (1-7)", function(sub, status)
        local RE = Remotes:FindFirstChild("ClaimSevenLoginReward")
        if not RE then status("❌ Remote tidak ditemukan", C.RED); return end
        local claimed = 0
        status("⏳ Claiming 7 day login reward...", C.YEL)
        for day = 1, 7 do
            local ok, res = pcall(function() return RE:FireServer(day) end)
            Log("📅 Day "..day.." → ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.DIM)
            if ok then claimed = claimed + 1 end
            task.wait(0.3)
        end
        status("✅ 7 Day Login selesai — "..claimed.."/7 diklaim", C.GRN)
        sub.Text = "Terakhir: "..claimed.."/7 hari diklaim"
        sub.TextColor3 = C.GRN
    end)

    -- ── Raid Reward ──
    ClaimRow(7, "📆", "Daily Task Reward", "Klaim reward daily task yang sudah selesai", function(sub, status)
        local RE = Remotes:FindFirstChild("ClaimDailyTaskReward")
        if not RE then status("❌ Remote tidak ditemukan", C.RED); return end
        status("⏳ Claiming daily task reward...", C.YEL)
        local ok, res = pcall(function() return RE:FireServer() end)
        Log("📆 DailyTask → ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.RED)
        task.wait(0.5)
        if ok then
            status("✅ Daily Task Reward diklaim", C.GRN)
            sub.Text = "Terakhir: berhasil diklaim"
            sub.TextColor3 = C.GRN
        else
            status("⚠ Daily Task gagal (mungkin belum ada task selesai)", C.YEL)
        end
    end)

    -- ── Claim ALL button ──
    local allBtn = Btn(p, C.ACC, UDim2.new(1,0,0,38))
    allBtn.LayoutOrder = 10; Corner(allBtn,10); Stroke(allBtn,C.ACC2,1,0.2)
    local allLbl = Label(allBtn,"🎁  CLAIM ALL",13,C.BLACK,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    allLbl.Size = UDim2.new(1,0,1,0)

    allBtn.MouseButton1Click:Connect(function()
        allBtn.BackgroundColor3 = C.DIM
        allLbl.Text = "⏳ Claiming..."
        task.spawn(function()
            SetStatus("⏳ Claim All dimulai...", C.YEL)

            -- Online Reward (smart scan)
            local RE1 = Remotes:FindFirstChild("ClaimOnlineReward")
            if RE1 then
                SetStatus("🌐 Online Reward scanning...", C.YEL)
                local fail, ever = 0, false
                for id = 1, 500 do
                    local ok, res = pcall(function() return RE1:InvokeServer({id = tostring(id)}) end)
                    if ok and res == true then
                        fail = 0; ever = true
                        Log("✅ OnlineReward id="..id.." diklaim", C.GRN)
                    elseif ever then
                        fail = fail + 1
                        if fail >= 15 then break end
                    end
                    task.wait(0.05)
                end
            end

            -- Season Task
            local RE2 = Remotes:FindFirstChild("ClaimSeasonTaskReward")
            if RE2 then
                SetStatus("📋 Season Task...", C.YEL)
                pcall(function() RE2:FireServer() end)
                task.wait(0.3)
            end

            -- Season Pass
            local RE3 = Remotes:FindFirstChild("ClaimSeasonPassReward")
            if RE3 then
                SetStatus("🎫 Season Pass...", C.YEL)
                pcall(function() RE3:FireServer() end)
                task.wait(0.3)
            end

            -- 7 Day Login
            local RE4 = Remotes:FindFirstChild("ClaimSevenLoginReward")
            if RE4 then
                SetStatus("📅 7 Day Login...", C.YEL)
                for day = 1, 7 do
                    pcall(function() RE4:FireServer(day) end)
                    task.wait(0.2)
                end
            end

            -- Daily Task Reward
            local RE6 = Remotes:FindFirstChild("ClaimDailyTaskReward")
            if RE6 then
                SetStatus("📆 Daily Task Reward...", C.YEL)
                pcall(function() RE6:FireServer() end)
                task.wait(0.3)
            end

            SetStatus("✅ Claim All selesai!", C.GRN)
            allBtn.BackgroundColor3 = C.GRN
            allLbl.Text = "✅  CLAIM ALL SELESAI"
            task.wait(3)
            allBtn.BackgroundColor3 = C.ACC
            allLbl.Text = "🎁  CLAIM ALL"
        end)
    end)
end)()

-- ============================================================
-- WEBHOOK SENDER
-- ============================================================
-- ============================================================
-- PANEL : SETTINGS
-- ============================================================
;(function()
    local p = NewPanel("settings")
    SectionHeader(p,"PENGATURAN LANJUTAN",0)
    SectionHeader(p,"WEBHOOK NOTIFIKASI",1)

    -- Info card
    local infoCard = Frame(p, Color3.fromRGB(20,25,35), UDim2.new(1,0,0,0))
    infoCard.LayoutOrder=2; infoCard.AutomaticSize=Enum.AutomaticSize.Y
    Corner(infoCard,8); Stroke(infoCard,Color3.fromRGB(80,130,220),1,0.4); Padding(infoCard,8,8,10,10)
    local infoLbl = Label(infoCard,
        "Kirim notif Raid / Siege ke Discord atau Telegram.\nData diambil dari chat scan (history + realtime).\nPaste URL webhook Discord atau Telegram bot di bawah.",
        10,Color3.fromRGB(160,190,255),Enum.Font.Gotham)
    infoLbl.Size=UDim2.new(1,0,0,0); infoLbl.AutomaticSize=Enum.AutomaticSize.Y; infoLbl.TextWrapped=true

    -- ── [v115] Mode Dropdown: Raid / Siege / Keduanya ──
    local modeCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,0))
    modeCard.LayoutOrder=25; modeCard.AutomaticSize=Enum.AutomaticSize.Y
    Corner(modeCard,9); Stroke(modeCard,Color3.fromRGB(180,120,255),1,0.4)
    Padding(modeCard,8,8,10,10)
    New("UIListLayout",{Parent=modeCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

    local modeHdr = Label(modeCard,"🔔  Mode Notifikasi Webhook",11,C.TXT,Enum.Font.GothamBold)
    modeHdr.Size=UDim2.new(1,0,0,16); modeHdr.LayoutOrder=0

    local modeSub = Label(modeCard,"Pilih jenis notif yang dikirim ke webhook",9.5,C.TXT3,Enum.Font.Gotham)
    modeSub.Size=UDim2.new(1,0,0,13); modeSub.LayoutOrder=1

    -- Dropdown button
    local MODE_OPTS = {
        {key="raid",  label="⚡  Raid Only",      desc="Notif saat Raid muncul/update",  col=Color3.fromRGB(255,180,60)},
        {key="siege", label="🏰  Siege Only",     desc="Notif saat Siege buka/tutup",    col=Color3.fromRGB(100,180,255)},
        {key="both",  label="⚡🏰  Raid + Siege", desc="Notif Raid dan Siege sekaligus", col=Color3.fromRGB(160,255,160)},
    }
    local curModeIdx = 3  -- default: both

    local modeDDBtn = Btn(modeCard, C.DD_BG, UDim2.new(1,0,0,28))
    modeDDBtn.LayoutOrder=2; Corner(modeDDBtn,7); Stroke(modeDDBtn,Color3.fromRGB(180,120,255),1,0.3)
    local modeDDLbl = Label(modeDDBtn,"  "..MODE_OPTS[curModeIdx].label,10.5,MODE_OPTS[curModeIdx].col,Enum.Font.GothamBold)
    modeDDLbl.Size=UDim2.new(1,-22,1,0); modeDDLbl.Position=UDim2.new(0,4,0,0)
    local modeArr = Label(modeDDBtn,"▼",10,Color3.fromRGB(180,120,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    modeArr.Size=UDim2.new(0,18,1,0); modeArr.Position=UDim2.new(1,-20,0,0)

    local modeDescLbl = Label(modeCard,MODE_OPTS[curModeIdx].desc,9,C.TXT3,Enum.Font.Gotham)
    modeDescLbl.Size=UDim2.new(1,0,0,13); modeDescLbl.LayoutOrder=3

    modeDDBtn.MouseButton1Click:Connect(function()
        CloseActiveDD()
        local absPos  = modeDDBtn.AbsolutePosition
        local absSize = modeDDBtn.AbsoluteSize
        local ITEM_H  = 36

        local popup = Instance.new("Frame")
        popup.Parent=DDLayer; popup.BackgroundColor3=C.DD_BG; popup.BorderSizePixel=0
        popup.Size=UDim2.new(0,absSize.X+10,0,#MODE_OPTS*(ITEM_H+2)+12)
        popup.Position=UDim2.new(0,absPos.X,0,absPos.Y+absSize.Y+3)
        popup.ZIndex=9999
        Corner(popup,8); Stroke(popup,Color3.fromRGB(180,120,255),1,0.2)

        local ll=Instance.new("UIListLayout",popup)
        ll.Padding=UDim.new(0,2); ll.SortOrder=Enum.SortOrder.LayoutOrder
        Instance.new("UIPadding",popup).PaddingTop=UDim.new(0,5)

        for i, opt in ipairs(MODE_OPTS) do
            local item=Instance.new("TextButton",popup)
            item.Size=UDim2.new(1,-8,0,ITEM_H); item.LayoutOrder=i
            item.BackgroundColor3=i==curModeIdx and Color3.fromRGB(55,25,80) or Color3.fromRGB(28,15,40)
            item.BackgroundTransparency=i==curModeIdx and 0 or 0.3
            item.BorderSizePixel=0; item.Text=""; item.AutoButtonColor=false; item.ZIndex=9999
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)

            local iL=Instance.new("TextLabel",item)
            iL.Size=UDim2.new(1,-8,0,16); iL.Position=UDim2.new(0,10,0,4)
            iL.BackgroundTransparency=1; iL.Text=opt.label; iL.TextSize=11
            iL.Font=Enum.Font.GothamBold; iL.TextColor3=opt.col
            iL.TextXAlignment=Enum.TextXAlignment.Left; iL.ZIndex=9999

            local iD=Instance.new("TextLabel",item)
            iD.Size=UDim2.new(1,-8,0,13); iD.Position=UDim2.new(0,10,0,20)
            iD.BackgroundTransparency=1; iD.Text=opt.desc; iD.TextSize=9
            iD.Font=Enum.Font.Gotham; iD.TextColor3=C.DIM
            iD.TextXAlignment=Enum.TextXAlignment.Left; iD.ZIndex=9999

            local ii=i
            item.MouseButton1Click:Connect(function()
                CloseActiveDD()
                curModeIdx     = ii
                _webhookMode   = opt.key
                modeDDLbl.Text = "  "..opt.label
                modeDDLbl.TextColor3 = opt.col
                modeDescLbl.Text = opt.desc
            end)
        end
        DDLayer.Visible=true
        _activeDDClose=function() popup:Destroy(); DDLayer.Visible=false end
    end)

    -- URL input
    local urlCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,58))
    urlCard.LayoutOrder=3; Corner(urlCard,9); Stroke(urlCard,C.BORD,1,0.4); Padding(urlCard,8,8,10,10)
    New("UIListLayout",{Parent=urlCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,5)})
    local urlHdr=Label(urlCard,"URL Webhook",10.5,C.TXT2,Enum.Font.GothamBold)
    urlHdr.Size=UDim2.new(1,0,0,14); urlHdr.LayoutOrder=0
    local urlBox = Instance.new("TextBox")
    urlBox.Parent=urlCard; urlBox.LayoutOrder=1
    urlBox.Size=UDim2.new(1,0,0,24); urlBox.BackgroundColor3=Color3.fromRGB(18,14,10)
    urlBox.BorderSizePixel=0; urlBox.TextSize=9.5; urlBox.Font=Enum.Font.Gotham
    urlBox.TextColor3=C.TXT2; urlBox.PlaceholderColor3=C.DIM
    urlBox.PlaceholderText="https://discord.com/api/webhooks/..."
    urlBox.Text=_webhookUrl; urlBox.TextXAlignment=Enum.TextXAlignment.Left
    urlBox.ClearTextOnFocus=false
    Corner(urlBox,5); Stroke(urlBox,C.BORD,1,0.3)
    local urlPad=Instance.new("UIPadding",urlBox)
    urlPad.PaddingLeft=UDim.new(0,6); urlPad.PaddingRight=UDim.new(0,6)
    urlBox.FocusLost:Connect(function()
        _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
    end)

    -- Platform detect label
    local platformLbl = Label(p,"",9.5,C.DIM,Enum.Font.Gotham)
    platformLbl.LayoutOrder=4; platformLbl.Size=UDim2.new(1,0,0,13)
    function UpdatePlatformLbl()
        local url = _webhookUrl
        if url:find("discord%.com/api/webhooks") then
            platformLbl.Text="✅ Discord webhook terdeteksi"; platformLbl.TextColor3=Color3.fromRGB(100,220,100)
        elseif url:find("api%.telegram%.org") then
            platformLbl.Text="✅ Telegram bot API terdeteksi"; platformLbl.TextColor3=Color3.fromRGB(100,180,255)
        elseif url=="" then
            platformLbl.Text="Belum ada URL"; platformLbl.TextColor3=C.DIM
        else
            platformLbl.Text="⚠ URL tidak dikenali (Discord/Telegram saja)"; platformLbl.TextColor3=Color3.fromRGB(255,180,60)
        end
    end
    urlBox.FocusLost:Connect(function() UpdatePlatformLbl() end)
    UpdatePlatformLbl()

    -- Toggle aktifkan webhook
    local wRow = Frame(p,Color3.fromRGB(20,25,40),UDim2.new(1,0,0,50))
    wRow.LayoutOrder=5; Corner(wRow,9); Stroke(wRow,Color3.fromRGB(80,130,220),1,0.3)
    local wL=Label(wRow,"🔔  Aktifkan Webhook",13,C.TXT,Enum.Font.GothamBold)
    wL.Size=UDim2.new(0.65,0,0,20); wL.Position=UDim2.new(0,10,0,6)
    local wS=Label(wRow,"Kirim notif otomatis setiap update",9.5,C.TXT3,Enum.Font.Gotham)
    wS.Size=UDim2.new(0.65,0,0,14); wS.Position=UDim2.new(0,10,0,26)
    local wPill=Btn(wRow,Color3.fromRGB(30,50,100),UDim2.new(0,50,0,26))
    wPill.AnchorPoint=Vector2.new(1,0.5); wPill.Position=UDim2.new(1,-10,0.5,0); Corner(wPill,13)
    local wKnob=Frame(wPill,Color3.fromRGB(80,110,180),UDim2.new(0,20,0,20))
    wKnob.AnchorPoint=Vector2.new(0,0.5); wKnob.Position=UDim2.new(0,3,0.5,0); Corner(wKnob,10)
    wPill.MouseButton1Click:Connect(function()
        _webhookEnabled=not _webhookEnabled; local on=_webhookEnabled
        _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
        TweenService:Create(wPill,TweenInfo.new(0.16),{BackgroundColor3=on and Color3.fromRGB(60,100,220) or Color3.fromRGB(30,50,100)}):Play()
        TweenService:Create(wKnob,TweenInfo.new(0.16),{
            Position=on and UDim2.new(1,-23,0.5,0) or UDim2.new(0,3,0.5,0),
            BackgroundColor3=on and Color3.fromRGB(255,255,255) or Color3.fromRGB(80,110,180),
        }):Play()
        wRow.BackgroundColor3=on and Color3.fromRGB(25,40,80) or Color3.fromRGB(20,25,40)
        UpdatePlatformLbl()
        if on then task.spawn(SendWebhookNotif) end
    end)

    -- ── Row: Test Webhook + Verify Link ──
    local btnRow = Frame(p, C.BLACK, UDim2.new(1,0,0,36))
    btnRow.LayoutOrder=6; btnRow.BackgroundTransparency=1
    New("UIListLayout",{Parent=btnRow,FillDirection=Enum.FillDirection.Horizontal,
        SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8)})

    -- Test Webhook
    local testRow=Frame(btnRow,Color3.fromRGB(20,35,20),UDim2.new(0.5,-4,1,0))
    testRow.LayoutOrder=1; Corner(testRow,9); Stroke(testRow,Color3.fromRGB(60,180,60),1,0.3)
    local testBtn=Btn(testRow,Color3.fromRGB(30,100,30),UDim2.new(1,-16,0,24))
    testBtn.AnchorPoint=Vector2.new(0.5,0.5); testBtn.Position=UDim2.new(0.5,0,0.5,0)
    Corner(testBtn,7); Stroke(testBtn,Color3.fromRGB(80,220,80),1,0.3)
    local testLbl=Label(testBtn,"📡  Test Webhook",10,Color3.fromRGB(200,255,200),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    testLbl.Size=UDim2.new(1,0,1,0)
    testBtn.MouseButton1Click:Connect(function()
        _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
        UpdatePlatformLbl()
        local msg = "🧪 [ASH Test] Webhook aktif! Mode: "..(_webhookMode or "both"):upper()
        testLbl.Text="⏳ Mengirim..."; testLbl.TextColor3=Color3.fromRGB(255,220,60)
        _WH.SendCustomMessage(_webhookUrl, msg,
            function()
                task.spawn(function()
                    testLbl.Text="✅ Terkirim!"; testLbl.TextColor3=Color3.fromRGB(100,255,100)
                    task.wait(2.5)
                    testLbl.Text="📡  Test Webhook"; testLbl.TextColor3=Color3.fromRGB(200,255,200)
                end)
            end,
            function(err)
                task.spawn(function()
                    testLbl.Text="❌ "..err; testLbl.TextColor3=Color3.fromRGB(255,80,60)
                    task.wait(2.5)
                    testLbl.Text="📡  Test Webhook"; testLbl.TextColor3=Color3.fromRGB(200,255,200)
                end)
            end
        )
    end)

    -- Verify Link
    local verRow=Frame(btnRow,Color3.fromRGB(20,25,40),UDim2.new(0.5,-4,1,0))
    verRow.LayoutOrder=2; Corner(verRow,9); Stroke(verRow,Color3.fromRGB(80,130,220),1,0.3)
    local verBtn=Btn(verRow,Color3.fromRGB(25,50,120),UDim2.new(1,-16,0,24))
    verBtn.AnchorPoint=Vector2.new(0.5,0.5); verBtn.Position=UDim2.new(0.5,0,0.5,0)
    Corner(verBtn,7); Stroke(verBtn,Color3.fromRGB(100,160,255),1,0.3)
    local verLbl=Label(verBtn,"🔍  Verify Link",10,Color3.fromRGB(180,210,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    verLbl.Size=UDim2.new(1,0,1,0)
    verBtn.MouseButton1Click:Connect(function()
        _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
        UpdatePlatformLbl()
        verLbl.Text="⏳ Mengecek..."; verLbl.TextColor3=Color3.fromRGB(255,220,60)
        _WH.VerifyWebhookUrl(_webhookUrl,
            function()
                task.spawn(function()
                    verLbl.Text="✅ Link Valid!"; verLbl.TextColor3=Color3.fromRGB(100,255,100)
                    task.wait(2.5)
                    verLbl.Text="🔍  Verify Link"; verLbl.TextColor3=Color3.fromRGB(180,210,255)
                end)
            end,
            function(err)
                task.spawn(function()
                    verLbl.Text="❌ "..err; verLbl.TextColor3=Color3.fromRGB(255,80,60)
                    task.wait(2.5)
                    verLbl.Text="🔍  Verify Link"; verLbl.TextColor3=Color3.fromRGB(180,210,255)
                end)
            end
        )
    end)

    -- ── Kirim Sekarang (manual trigger sesuai mode) ──
    local sendNowCard = Frame(p, Color3.fromRGB(25,20,40), UDim2.new(1,0,0,38))
    sendNowCard.LayoutOrder=7; Corner(sendNowCard,9); Stroke(sendNowCard,Color3.fromRGB(180,120,255),1,0.3)
    local sendNowBtn = Btn(sendNowCard,Color3.fromRGB(70,30,120),UDim2.new(0.7,0,0,26))
    sendNowBtn.AnchorPoint=Vector2.new(0.5,0.5); sendNowBtn.Position=UDim2.new(0.5,0,0.5,0)
    Corner(sendNowBtn,8); Stroke(sendNowBtn,Color3.fromRGB(200,140,255),1,0.3)
    local sendNowLbl=Label(sendNowBtn,"📤  Kirim Notif Sekarang",10.5,Color3.fromRGB(230,200,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    sendNowLbl.Size=UDim2.new(1,0,1,0)
    sendNowBtn.MouseButton1Click:Connect(function()
        _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
        if _webhookUrl == "" then
            sendNowLbl.Text="⚠ URL kosong!"; sendNowLbl.TextColor3=Color3.fromRGB(255,180,60)
            task.delay(2, function() sendNowLbl.Text="📤  Kirim Notif Sekarang"; sendNowLbl.TextColor3=Color3.fromRGB(230,200,255) end)
            return
        end
        sendNowLbl.Text="⏳ Mengirim..."; sendNowLbl.TextColor3=Color3.fromRGB(255,220,60)
        task.spawn(function()
            SendWebhookNotif()
            task.wait(1)
            sendNowLbl.Text="✅ Terkirim!"; sendNowLbl.TextColor3=Color3.fromRGB(160,255,160)
            task.wait(2)
            sendNowLbl.Text="📤  Kirim Notif Sekarang"; sendNowLbl.TextColor3=Color3.fromRGB(230,200,255)
        end)
    end)
end)()


-- ============================================================
-- INIT
-- ============================================================
-- Pre-populate semua Ornament Quirk dengan nama lengkap
-- Urutan: common (atas) → rare (bawah)
-- Format: {machineIdx, quirkId, "nama"}
do
    local ORN_KNOWN = {
        -- ══════════════════════════════════════════
        -- [1] HEADDRESS — machineId=400001
        -- ══════════════════════════════════════════
        {1, 410001, "Glowing Blue Eyes"},
        {1, 410002, "Fox Ears"},
        {1, 410003, "Blossom Crown of the Abyss"},
        {1, 410004, "Demon Horns"},
        {1, 410005, "Wizard Hat"},
        {1, 410006, "Sharktooth Hood"},
        {1, 410007, "Bunny Boom Helmet"},
        {1, 410008, "Cursed Harvest Helmet"},
        {1, 410009, "Bloodforged Casque"},
        {1, 410010, "Jester's Madness Cap"},        -- ⭐ RAREST

        -- ══════════════════════════════════════════
        -- [2] ORNAMENT MACHINE — machineId=400002
        -- ══════════════════════════════════════════
        {2, 410011, "Fox Brush"},
        {2, 410012, "Whale's Tail"},
        {2, 410013, "Dragon's Tail"},
        {2, 410014, "Dinosaur Swimming Circle"},
        {2, 410015, "Ghastroot Parasite"},
        {2, 410016, "Wishy Star Bunny"},
        {2, 410017, "Mechanical Wing"},
        {2, 410018, "Demon Wing"},
        {2, 410019, "Prism Wings"},
        {2, 410020, "Omenwing of the Void"},         -- ⭐ RAREST

        -- ══════════════════════════════════════════
        -- [3] WEALTH BLESSING — machineId=400003
        -- ══════════════════════════════════════════
        {3, 410021, "Single Glow Bless"},
        {3, 410022, "Double Stack Bless"},
        {3, 410023, "Slant Bless"},
        {3, 410024, "Misstack Bless"},
        {3, 410025, "High Stack Bless"},
        {3, 410026, "Initial Bag Bless"},
        {3, 410027, "Full Bag Bless"},
        {3, 410028, "Bag Scatter Bless"},
        {3, 410029, "Supreme Crown Gold"},
        {3, 410030, "Imperial Crown Full Bag"},       -- ⭐ RAREST

        -- ══════════════════════════════════════════
        -- [4] SHADOWHUNTER BLESSING — machineId=400004
        -- ══════════════════════════════════════════
        {4, 410031, "Shadowfelin Gaze"},
        {4, 410032, "Techowl Capture"},
        {4, 410033, "Beastglow Frame"},
        {4, 410034, "Croucharmor Beam"},
        {4, 410035, "Silveraura Agile"},
        {4, 410036, "Demonwing Aura"},
        {4, 410037, "Spikedial Gothic"},
        {4, 410038, "Galaxyvortex Lightning"},
        {4, 410039, "Demonhand Lightning"},           -- ⭐ RAREST

        -- ══════════════════════════════════════════
        -- [5] PRIMORDIAL BLESSING — machineId=400005
        -- ══════════════════════════════════════════
        {5, 410040, "Dawn's Spark"},
        {5, 410041, "Blade's Guide"},
        {5, 410042, "Edge's Glow"},
        {5, 410043, "Power's Nudge"},
        {5, 410044, "Resurgent Edge"},
        {5, 410045, "Sixth Dawn's Gift"},
        {5, 410046, "Flame's Fuel"},
        {5, 410047, "Gold Star's Whisper"},
        {5, 410048, "Stardust's Fury"},               -- ⭐ RAREST

        -- ══════════════════════════════════════════
        -- [6] MONARCH POWER — machineId=400006
        -- ══════════════════════════════════════════
        {6, 410049, "Flames Power"},
        {6, 410050, "Giant Power"},
        {6, 410051, "Beast Power"},
        {6, 410052, "Plague Power"},
        {6, 410053, "Frosh Power"},
        {6, 410054, "Unbreakable Power"},
        {6, 410057, "Transfiguration Power"},
        {6, 410056, "Destruction Power"},
        {6, 410055, "Shadow Power"},                  -- ⭐ RAREST
    }
    for _, e in ipairs(ORN_KNOWN) do
        _ASH_ORN.AddQuirk(e[1], e[2], e[3])
    end
end

-- ============================================================
-- AUTO ROLL LOGIC — HERO
-- ============================================================
do
    local LOOPS_HR = {}

    local function StopHeroLoop(si)
        if LOOPS_HR[si] then
            task.cancel(LOOPS_HR[si])
            LOOPS_HR[si] = nil
        end
    end

    local function StartHeroSlot(si)
        StopHeroLoop(si)
        local list    = QUIRK_LIST_PER_SLOT[si]
        local targets = _HR_RPT and _HR_RPT.slotTarget and _HR_RPT.slotTarget[si] or {}
        local drawId  = {920001, 920002, 920003}

        -- Update nama hero saat slot 1 mulai
        if si == 1 and _HR_RPT then _HR_RPT.Refresh() end

        local function setSlot(txt, col)
            if _HR_RPT then _HR_RPT.SetSlot(si, txt, col) end
        end

        setSlot("Memulai...", Color3.fromRGB(255,200,60))

        LOOPS_HR[si] = task.spawn(function()
            local attempt = 0
            while true do
                -- Cek GUID tersedia
                if not (_HR_RPT and _HR_RPT.guid and _HR_RPT.guid ~= "") then
                    setSlot("⏳ Klik 1x di Mesin Reroll dulu", Color3.fromRGB(255,150,50))
                    task.wait(1); continue
                end
                -- Cek target dipilih — wajib ada sebelum roll
                local hasTarget = false
                for _ in pairs(targets) do hasTarget = true; break end
                if not hasTarget then
                    setSlot("⚠ Pilih target dulu di dropdown!", Color3.fromRGB(255,100,60))
                    task.wait(1); continue
                end

                attempt = attempt + 1
                local tStr = ""
                if hasTarget then
                    local names = {}
                    for _, q in ipairs(list) do
                        if targets[q.id] then table.insert(names, q.name) end
                    end
                    tStr = table.concat(names, " / ")
                end
                setSlot("Rolling #"..attempt..(tStr~="" and " | "..tStr or ""), Color3.fromRGB(255,200,60))

                local ok, res = pcall(function()
                    _ourCall = true
                    local r = RE.RandomHeroQuirk:InvokeServer({
                        heroGuid = _HR_RPT.guid,
                        drawId   = drawId[si],
                    })
                    _ourCall = false
                    return r
                end)
                if not ok then task.wait(0.5); continue end

                -- Tangkap hasil quirk
                local gotId = nil
                if type(res) == "table" then
                    local PRIO = {"finalResultId","quirkId","resultId","id","Id","result","Result"}
                    for _, key in ipairs(PRIO) do
                        local v = res[key]
                        if type(v) == "number" and QUIRK_MAP[v] then gotId = v; break end
                    end
                    if not gotId then
                        for _, v in pairs(res) do
                            if type(v) == "number" and QUIRK_MAP[v] then gotId = v; break end
                        end
                    end
                end

                local gotName = QUIRK_MAP[gotId] or (gotId and "ID:"..gotId or "?")
                -- [v103] Hanya stop kalau target dipilih DAN hasil cocok
                local hit = gotId and hasTarget and targets[gotId] == true

                if hit then
                    setSlot("Selesai: "..gotName.." (#"..attempt..")", Color3.fromRGB(80,220,80))
                    StopHeroLoop(si)
                    -- Cek apakah semua slot sudah selesai
                    local allDone = true
                    for i = 1, 3 do if LOOPS_HR[i] then allDone = false; break end end
                    if allDone and _HR_RPT then _HR_RPT.SetToggleOff() end
                    return
                end

                task.wait(0.05)
            end
        end)
    end

    DoAutoRollHero = function(on)
        for i = 1, 3 do StopHeroLoop(i) end
        if not on then
            for i = 1, 3 do
                if _HR_RPT then _HR_RPT.SetSlot(i, "Idle", Color3.fromRGB(160,148,135)) end
            end
            -- Reset GUID agar bisa capture ulang saat ganti hero
            if _HR_RPT then
                _HR_RPT.guid = ""
                _HR_RPT.Refresh()
            end
            return
        end
        -- GUID belum ada → tampil pesan, tunggu GUID, lalu auto-start
        if not (_HR_RPT and _HR_RPT.guid and _HR_RPT.guid ~= "") then
            for i = 1, 3 do
                if _HR_RPT then _HR_RPT.SetSlot(i, "Menunggu — klik 1x di Mesin Reroll", Color3.fromRGB(180,220,255)) end
            end
            -- Polling sampai GUID tersedia, lalu langsung mulai
            task.spawn(function()
                while not (_HR_RPT and _HR_RPT.guid and _HR_RPT.guid ~= "") do
                    task.wait(0.5)
                end
                -- Pastikan toggle masih ON sebelum mulai
                if _HR_RPT and _HR_RPT.running then
                    _HR_RPT.Refresh()
                    for i = 1, 3 do StartHeroSlot(i) end
                end
            end)
            return
        end
        for i = 1, 3 do StartHeroSlot(i) end
    end
end

-- ============================================================
-- AUTO ROLL LOGIC — WEAPON
-- ============================================================
do
    local LOOPS_WR = {}

    local function StopWeaponLoop(si)
        if LOOPS_WR[si] then
            task.cancel(LOOPS_WR[si])
            LOOPS_WR[si] = nil
        end
    end

    local function StartWeaponSlot(si)
        StopWeaponLoop(si)
        local list    = W_QUIRK_LIST_PER_SLOT[si]
        local targets = _WR_RPT and _WR_RPT.slotTarget and _WR_RPT.slotTarget[si] or {}
        local drawId  = {960001, 960002, 960003}

        -- Update nama weapon saat slot 1 mulai (cukup sekali)
        if si == 1 and _WR_RPT then _WR_RPT.Refresh() end

        local function setSlot(txt, col)
            if _WR_RPT then _WR_RPT.SetSlot(si, txt, col) end
        end

        setSlot("Memulai...", Color3.fromRGB(255,200,60))

        LOOPS_WR[si] = task.spawn(function()
            local attempt = 0
            while true do
                if not (_WR_RPT and _WR_RPT.guid and _WR_RPT.guid ~= "") then
                    setSlot("⏳ Klik 1x di Mesin Reroll dulu", Color3.fromRGB(255,150,50))
                    task.wait(1); continue
                end
                local hasTarget = false
                for _ in pairs(targets) do hasTarget = true; break end
                -- Wajib ada target sebelum roll
                if not hasTarget then
                    setSlot("⚠ Pilih target dulu di dropdown!", Color3.fromRGB(255,100,60))
                    task.wait(1); continue
                end

                attempt = attempt + 1
                local tStr = ""
                if hasTarget then
                    local names = {}
                    for _, q in ipairs(list) do
                        if targets[q.id] then table.insert(names, q.name) end
                    end
                    tStr = table.concat(names, " / ")
                end
                setSlot("Rolling #"..attempt..(tStr~="" and " | "..tStr or ""), Color3.fromRGB(255,200,60))

                local ok, res = pcall(function()
                    _ourCall = true
                    local r = RE.RandomWeaponQuirk:InvokeServer({
                        guid   = _WR_RPT.guid,
                        drawId = drawId[si],
                    })
                    _ourCall = false
                    return r
                end)
                if not ok then task.wait(0.5); continue end

                local gotId = nil
                if type(res) == "table" then
                    local PRIO = {"finalResultId","quirkId","resultId","id","Id","result","Result"}
                    for _, key in ipairs(PRIO) do
                        local v = res[key]
                        if type(v) == "number" and W_QUIRK_MAP[v] then gotId = v; break end
                    end
                    if not gotId then
                        for _, v in pairs(res) do
                            if type(v) == "number" and W_QUIRK_MAP[v] then gotId = v; break end
                        end
                    end
                end

                local gotName = W_QUIRK_MAP[gotId] or (gotId and "ID:"..gotId or "?")
                -- [v103] Hanya stop kalau target dipilih DAN hasil cocok
                local hit = gotId and hasTarget and targets[gotId] == true

                if hit then
                    setSlot("Selesai: "..gotName.." (#"..attempt..")", Color3.fromRGB(80,220,80))
                    StopWeaponLoop(si)
                    local allDone = true
                    for i = 1, 3 do if LOOPS_WR[i] then allDone = false; break end end
                    if allDone and _WR_RPT then _WR_RPT.SetToggleOff() end
                    return
                end

                task.wait(0.05)
            end
        end)
    end

    DoAutoRollWeapon = function(on)
        for i = 1, 3 do StopWeaponLoop(i) end
        if not on then
            for i = 1, 3 do
                if _WR_RPT then _WR_RPT.SetSlot(i, "Idle", Color3.fromRGB(160,148,135)) end
            end
            -- Reset GUID agar bisa capture ulang saat ganti weapon
            if _WR_RPT then
                _WR_RPT.guid = ""
                _WR_RPT.Refresh()
            end
            return
        end
        -- GUID belum ada → tampil pesan, tunggu GUID, lalu auto-start
        if not (_WR_RPT and _WR_RPT.guid and _WR_RPT.guid ~= "") then
            for i = 1, 3 do
                if _WR_RPT then _WR_RPT.SetSlot(i, "Menunggu — klik 1x di Mesin Reroll", Color3.fromRGB(180,220,255)) end
            end
            task.spawn(function()
                while not (_WR_RPT and _WR_RPT.guid and _WR_RPT.guid ~= "") do
                    task.wait(0.5)
                end
                if _WR_RPT and _WR_RPT.running then
                    _WR_RPT.Refresh()
                    for i = 1, 3 do StartWeaponSlot(i) end
                end
            end)
            return
        end
        for i = 1, 3 do StartWeaponSlot(i) end
    end

    -- ── DoAutoRollPetGear ──
    -- drawId fixed: 980001=slot1, 980002=slot2, 980003=slot3
    local PG_DRAW_IDS = {980001, 980002, 980003}
    local LOOPS_PG    = {}

    local function StopPetGearLoop(si)
        if LOOPS_PG[si] then
            pcall(function() task.cancel(LOOPS_PG[si]) end)
            LOOPS_PG[si] = nil
        end
    end

    local function StartPetGearSlot(si)
        StopPetGearLoop(si)
        local guid   = PGR.guids[si]
        local drawId = PG_DRAW_IDS[si]
        local targets = PGR.targets[si]

        local function setStatus(txt, col)
            if PGR.statLbls[si] then
                PGR.statLbls[si].Text      = txt
                PGR.statLbls[si].TextColor3 = col or C.TXT2
            end
            if PGR.dotRefs[si] then
                PGR.dotRefs[si].BackgroundColor3 = col or Color3.fromRGB(100,100,100)
            end
        end

        if not guid or guid == "" then
            setStatus("⏳ Klik 1x Reroll dulu di Mesin", Color3.fromRGB(180,220,255))
            -- Tunggu GUID ter-capture lalu auto-start
            task.spawn(function()
                while PGR.enOnFlags[si] do
                    if PGR.guids[si] and PGR.guids[si] ~= "" then
                        StartPetGearSlot(si)
                        return
                    end
                    task.wait(0.5)
                end
            end)
            return
        end

        local attempt = 0
        LOOPS_PG[si] = task.spawn(function()
            while PGR.enOnFlags[si] do
                -- Cek GUID
                if not (PGR.guids[si] and PGR.guids[si] ~= "") then
                    setStatus("⏳ Klik 1x Reroll dulu di Mesin", Color3.fromRGB(180,220,255))
                    task.wait(1); continue
                end
                -- Cek target — wajib ada sebelum roll
                local hasTarget = false
                for _ in pairs(PGR.targets[si]) do hasTarget = true; break end
                if not hasTarget then
                    setStatus("⚠ Pilih target dulu di dropdown!", Color3.fromRGB(255,100,60))
                    task.wait(1); continue
                end

                attempt = attempt + 1
                if PGR.attemptLbls[si] then
                    PGR.attemptLbls[si].Text = "Attempt: #"..attempt
                end
                setStatus("🔄 Roll #"..attempt, Color3.fromRGB(255,160,30))

                _ourCall = true
                local ok, res = pcall(function()
                    return RE.RandomHeroEquipGrade:InvokeServer({
                        guid   = PGR.guids[si],
                        drawId = PG_DRAW_IDS[si],
                    })
                end)
                _ourCall = false

                if not ok then
                    setStatus("⚠ Error — retry...", Color3.fromRGB(255,100,60))
                    task.wait(0.5); continue
                end

                local gotId = nil
                if type(res) == "table" then
                    gotId = res.gradeId or res.grade or res.id or res.resultId
                    if type(gotId) ~= "number" then
                        for _, v in pairs(res) do
                            if type(v) == "number" and v > 0 then gotId = v; break end
                        end
                    end
                end

                -- [v103] Hanya stop kalau target dipilih DAN hasil cocok
                local hit = gotId and hasTarget and PGR.targets[si][gotId] == true

                if hit then
                    setStatus("🎉 Target didapat! (#"..attempt..")", Color3.fromRGB(80,255,120))
                    if PGR.lastLbls[si] then
                        PGR.lastLbls[si].Text = "Last: ID "..tostring(gotId)
                    end
                    PGR.enOnFlags[si] = false
                    if PGR.toggleBtns[si]  then PGR.toggleBtns[si].BackgroundColor3  = Color3.fromRGB(60,60,60) end
                    if PGR.toggleKnobs[si] then PGR.toggleKnobs[si].Position = UDim2.new(0,2,0.5,-9) end
                    break
                else
                    setStatus("✅ Roll #"..attempt.." selesai", Color3.fromRGB(80,180,80))
                    if PGR.lastLbls[si] then
                        PGR.lastLbls[si].Text = "Last: "..(gotId and "ID:"..tostring(gotId) or "?")
                    end
                end
                task.wait(0.05)
            end
            setStatus("⏹ Idle", Color3.fromRGB(160,148,135))
        end)
    end

    DoAutoRollPetGear = function(si, on)
        StopPetGearLoop(si)
        if not on then
            -- [v103] Reset GUID saat toggle OFF — wajib Reroll 1x lagi
            PGR.guids[si]    = ""
            PGR.captured[si] = false
            if PGR.statLbls[si] then
                PGR.statLbls[si].Text      = "⏹ Idle — Reroll 1x lagi untuk mulai"
                PGR.statLbls[si].TextColor3 = C.TXT2
            end
            if PGR.dotRefs[si] then
                PGR.dotRefs[si].BackgroundColor3 = Color3.fromRGB(100,100,100)
            end
            return
        end
        -- Cek target dipilih dulu
        local hasTarget = false
        for _ in pairs(PGR.targets[si]) do hasTarget = true; break end
        if not hasTarget then
            if PGR.statLbls[si] then
                PGR.statLbls[si].Text      = "⚠ Pilih target dulu di dropdown!"
                PGR.statLbls[si].TextColor3 = Color3.fromRGB(255,100,60)
            end
            -- Tetap jalankan slot, dia akan loop tunggu target
        end
        StartPetGearSlot(si)
    end
end

-- ============================================================
-- CAPTURE SYSTEM — __namecall hook + flag _ourCall
-- ============================================================
do
    local function SetupUniversalSpy()
        if _layer0Active then return end
        _layer0Active = true

        local _rHero   = RE.RandomHeroQuirk
        local _rAuto   = RE.AutoHeroQuirk
        local _rWeapon = RE.RandomWeaponQuirk
        local _rPetG   = RE.RandomHeroEquipGrade
        local _rHeroSkill = RE.HeroUseSkill

        local ok, err = pcall(function()
            local mt   = getrawmetatable(game)
            local _old = mt.__namecall
            setreadonly(mt, false)

            mt.__namecall = newcclosure(function(self, ...)
                -- Auto-capture HERO_GUIDS dari HeroUseSkill
                if self == _rHeroSkill and not _ourCall then
                    local arg1 = select(1, ...)
                    if type(arg1) == "table" and type(arg1.heroGuid) == "string" then
                        local already = false
                        for _, g in ipairs(HERO_GUIDS) do
                            if g == arg1.heroGuid then already = true; break end
                        end
                        if not already then
                            table.insert(HERO_GUIDS, arg1.heroGuid)
                        end
                    end
                    return _old(self, ...)
                end

                -- Bukan remote target → teruskan langsung
                if self ~= _rHero and self ~= _rAuto
                and self ~= _rWeapon and self ~= _rPetG then
                    return _old(self, ...)
                end

                -- Cek apakah perlu di-intercept
                -- Hero & Weapon: intercept dari UI game hanya saat GUID belum ada
                -- Setelah GUID ada, hanya intercept dari _ourCall (loop kita)
                -- PetGear: stop intercept setelah semua ter-capture
                local needCapture = false
                if self == _rHero or self == _rAuto then
                    needCapture = not (_HR_RPT and _HR_RPT.guid and _HR_RPT.guid ~= "")
                elseif self == _rWeapon then
                    needCapture = not (_WR_RPT and _WR_RPT.guid and _WR_RPT.guid ~= "")
                elseif self == _rPetG then
                    -- [v101] Selalu capture PetGear — GUID bisa berubah tiap reroll
                    needCapture = true
                end

                -- UI game yang memanggil + tidak perlu intercept → skip
                if not _ourCall and not needCapture then
                    return _old(self, ...)
                end

                -- Capture method & arg1 SEBELUM _old dipanggil
                local m    = getnamecallmethod()
                local arg1 = select(1, ...)

                -- Jalankan remote asli
                local r1, r2, r3, r4, r5 = _old(self, ...)

                if m == "InvokeServer" or m == "FireServer" then

                    -- ── Hero: tangkap heroGuid ──
                    if self == _rHero or self == _rAuto then
                        if type(arg1) == "table" then
                            local g = arg1.heroGuid or arg1.HeroGuid or arg1.guid
                            if type(g) == "string" and IsValidUUID(g) then
                                if _HR_RPT then
                                    _HR_RPT.guid = g
                                    _HR_RPT.Refresh()
                                end
                            end
                        end

                    -- ── Weapon: tangkap weaponGuid dari RandomWeaponQuirk ──
                    elseif self == _rWeapon then
                        if type(arg1) == "table" then
                            local gv = arg1.guid or arg1.weaponGuid or arg1.id
                            if type(gv) == "string" and IsValidUUID(gv) then
                                if _WR_RPT then
                                    _WR_RPT.guid = gv
                                    _WR_RPT.Refresh()
                                end
                            end
                        end

                    -- ── PetGear: tangkap guid per mesin via drawId ──
                    elseif self == _rPetG then
                        warn("[ ASH PetGear ] Hook triggered! arg1="..tostring(type(arg1)))
                        if type(arg1) == "table" then
                            local g   = arg1.guid
                            local dId = arg1.drawId
                            warn("[ ASH PetGear ] guid="..tostring(g).." drawId="..tostring(dId))
                            if type(g) == "string" and IsValidUUID(g)
                            and type(dId) == "number" then
                                -- drawId fixed: 980001=slot1, 980002=slot2, 980003=slot3
                                local slotMap = {[980001]=1,[980002]=2,[980003]=3}
                                local si = slotMap[dId]
                                if si then
                                    PGR.guids[si]    = g
                                    PGR.captured[si] = true
                                    warn("[ ASH PetGear ] ✅ Slot "..si.." captured GUID: "..g)
                                    if PGR.statLbls[si] then
                                        PGR.statLbls[si].Text      = "✅ GUID captured — siap roll"
                                        PGR.statLbls[si].TextColor3 = Color3.fromRGB(80,220,80)
                                    end
                                else
                                    warn("[ ASH PetGear ] ⚠ drawId "..dId.." tidak dikenal!")
                                end
                            end
                        end
                    end

                    -- ── Auto-release hanya jika PetGear semua ter-capture ──
                    -- Hero & Weapon tidak di-release karena butuh update nama saat ganti
                    local petDone = PGR.captured[1] and PGR.captured[2] and PGR.captured[3]
                    local heroDone = _HR_RPT and _HR_RPT.guid and _HR_RPT.guid ~= ""
                    local weaponDone = _WR_RPT and _WR_RPT.guid and _WR_RPT.guid ~= ""
                    if heroDone and weaponDone and petDone then
                        -- Hanya release jika tidak ada yang butuh update nama lagi
                        -- (untuk saat ini biarkan hook tetap aktif)
                    end
                end

                return r1, r2, r3, r4, r5
            end)

            setreadonly(mt, true)
        end)

        if ok then
            warn("[ ASH ] Hook OK — Hero/Weapon/PetGear siap ditangkap")
            if _HR_RPT and _HR_RPT.nameLbl then
                _HR_RPT.nameLbl.Text = "Silahkan Klik dulu 1x di Mesin Reroll"
                _HR_RPT.nameLbl.TextColor3 = Color3.fromRGB(180,220,255)
            end
            if _WR_RPT and _WR_RPT.nameLbl then
                _WR_RPT.nameLbl.Text = "Silahkan Klik dulu 1x di Mesin Reroll"
                _WR_RPT.nameLbl.TextColor3 = Color3.fromRGB(180,220,255)
            end
        else
            warn("[ ASH ] Hook gagal: "..tostring(err))
        end
    end

    InitAllCaptureLayers = function()
        SetupUniversalSpy()
    end
end

SwitchTab("main")
RefreshStatus()
-- [v102] Hook langsung aktif saat GUI muncul, tidak perlu tunggu 30 detik
task.spawn(function()
    task.wait(2) -- tunggu sebentar sampai game selesai load
    InitAllCaptureLayers()
end)

print("[ ASH GUI ] V115 — Chat Scan + Siege Chat + SS grade + Webhook Mode Dropdown — by FLa")
end
