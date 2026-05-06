--   Arise Shadow Hunt — Auto Farming GUI
--   Theme : Full Orange iPhone 17 Pro Max
--   By    : FLa Project  (Fixed by Assistant)
--   Platform : Android (Delta) + PC (Xeno) — Full Support
--   [UPDATED] Floating Bubble diganti dengan versi sc_baru (v14.5)

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local RS               = game:GetService("ReplicatedStorage")
local TeleportService  = game:GetService("TeleportService")
local GuiService       = game:GetService("GuiService")

local LP  = Players.LocalPlayer
local PG  = LP.PlayerGui

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
local Remotes             = RS:WaitForChild("Remotes", 10)
local RE_CollectItem      = Remotes:WaitForChild("CollectItem", 10)
local RE_ExtraReward      = Remotes:WaitForChild("ExtraReward", 10)
local RE_AutoHeroQuirk    = Remotes:FindFirstChild("AutoRandomHeroQuirk")
local RE_RandomHeroQuirk  = Remotes:WaitForChild("RandomHeroQuirk", 10)

if not RE_RandomHeroQuirk then
    warn("[ ASH ] FATAL: RandomHeroQuirk tidak ditemukan! AutoReroll tidak akan berfungsi.")
end

local RE_Click     = Remotes:FindFirstChild("ClickEnemy")
local RE_Atk       = Remotes:FindFirstChild("PlayerClickAttackSkill")
local RE_Death     = Remotes:FindFirstChild("EnemyDeath")
local RE_HeroMove  = Remotes:FindFirstChild("HeroMoveToEnemyPos")
local RE_HeroStand = Remotes:FindFirstChild("HeroStandTo")
local RE_HeroSkill = Remotes:FindFirstChild("HeroPlaySkillAnim")

local RE_EquipWeapon          = Remotes:WaitForChild("EquipWeapon", 10)
local RE_RandomWeaponQuirk    = Remotes:WaitForChild("RandomWeaponQuirk", 10)
local RE_RandomHeroEquipGrade = Remotes:WaitForChild("RandomHeroEquipGrade", 10)
local RE_RerollHalo           = Remotes:FindFirstChild("RerollHalo")
local RE_StartTp              = Remotes:FindFirstChild("StartLocalPlayerTeleport")
local RE_LocalTp              = Remotes:FindFirstChild("LocalPlayerTeleport")

-- RAID REMOTES (dari SimpleSpy)
local RE_GetRaidTeamInfos         = Remotes:FindFirstChild("GetRaidTeamInfos")
local RE_CreateRaidTeam           = Remotes:FindFirstChild("CreateRaidTeam")
local RE_StartChallengeRaidMap    = Remotes:FindFirstChild("StartChallengeRaidMap")
local RE_RaidStartTp              = Remotes:FindFirstChild("StartLocalPlayerTeleport")
local RE_EquipHeroWithData        = Remotes:FindFirstChild("EquipHeroWithData")
local RE_LocalTpSuccess           = Remotes:FindFirstChild("LocalPlayerTeleportSuccess")
local RE_GetDrawHeroId            = Remotes:FindFirstChild("GetDrawHeroId")
local RE_GainRaidsRewards         = Remotes:FindFirstChild("GainRaidsRewards")
local RE_QuitRaidsMap             = Remotes:FindFirstChild("QuitRaidsMap")
local RE_UpdateRaidInfo           = Remotes:FindFirstChild("UpdateRaidInfo")

local MY_USER_ID = LP.UserId
local HERO_GUIDS = {}

-- ============================================================
-- IsValidUUID
-- ============================================================
local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local function IsValidUUID(s)
    return type(s) == "string" and #s == 36 and s:match(UUID_PATTERN) ~= nil
end

-- ============================================================
-- WARNA
-- ============================================================
local C = {
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
local function New(class, props)
    local obj = Instance.new(class)
    for k, v in pairs(props) do pcall(function() obj[k] = v end) end
    return obj
end

local function Frame(parent, color, size)
    return New("Frame", {
        Parent = parent, BackgroundColor3 = color,
        Size = size or UDim2.new(1,0,1,0), BorderSizePixel = 0
    })
end

local function Btn(parent, color, size)
    return New("TextButton", {
        Parent = parent, BackgroundColor3 = color,
        Size = size or UDim2.new(1,0,1,0), BorderSizePixel = 0,
        Text = "", AutoButtonColor = false
    })
end

local function Label(parent, text, size, color, font, xalign)
    return New("TextLabel", {
        Parent = parent, BackgroundTransparency = 1,
        Size = UDim2.new(1,0,1,0), Text = text, TextSize = size or 14,
        TextColor3 = color or C.TXT, Font = font or Enum.Font.Gotham,
        TextXAlignment = xalign or Enum.TextXAlignment.Left, BorderSizePixel = 0
    })
end

local function Corner(obj, r)
    New("UICorner", {Parent = obj, CornerRadius = UDim.new(0, r or 8)})
end

local function Stroke(obj, color, thickness, transparency)
    New("UIStroke", {
        Parent = obj, Color = color or C.BORD,
        Thickness = thickness or 1, Transparency = transparency or 0
    })
end

local function Padding(obj, top, bottom, left, right)
    New("UIPadding", {
        Parent = obj,
        PaddingTop    = UDim.new(0, top    or 6),
        PaddingBottom = UDim.new(0, bottom or 6),
        PaddingLeft   = UDim.new(0, left   or 8),
        PaddingRight  = UDim.new(0, right  or 8),
    })
end

local function ListLayout(parent, dir, align, spacing)
    return New("UIListLayout", {
        Parent = parent,
        FillDirection       = dir    or Enum.FillDirection.Vertical,
        HorizontalAlignment = align  or Enum.HorizontalAlignment.Left,
        SortOrder           = Enum.SortOrder.LayoutOrder,
        Padding             = UDim.new(0, spacing or 4),
    })
end

local function GuiInsetY()
    local ok, y = pcall(function() return GuiService:GetGuiInset().Y end)
    return (ok and type(y) == "number") and y or 36
end

-- ============================================================
-- SCREEN GUI
-- ============================================================
local ScreenGui = New("ScreenGui", {
    Parent = PG, Name = "ASH_GUI",
    ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999, IgnoreGuiInset = true,
})

local _vp = workspace.CurrentCamera.ViewportSize
local _isSmallScreen = _vp.X < 700
local WIN_W = _isSmallScreen and math.min(math.floor(_vp.X * 0.96), 420) or 500
local WIN_H = _isSmallScreen and math.min(math.floor(_vp.Y * 0.82), 380) or 360

local Window = Frame(ScreenGui, C.BG, UDim2.new(0, WIN_W, 0, WIN_H))
Window.Position = UDim2.new(0.5, -WIN_W/2, 0.05, 0)
Window.ClipsDescendants = true
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
local Bubble = Btn(ScreenGui, C.TBAR, UDim2.new(0,58,0,58))
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
local function FloatBubble()
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
local function BuildTopBar()
    local TopBar = Frame(Window, C.TBAR, UDim2.new(1,0,0,40))
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

    local function WinBtn(xOffset, color, symbol)
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
    local function ShowBubble()
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
    local function ShowWin()
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

local Body = Frame(Window, C.BG3, UDim2.new(1,0,1,-40))
Body.Position = UDim2.new(0,0,0,40)

local SideBar = Frame(Body, C.SIDEBAR, UDim2.new(0, SIDEBAR_W, 1, 0))
local SideScroll = New("ScrollingFrame", {
    Parent = SideBar, Size = UDim2.new(1,0,1,-8), Position = UDim2.new(0,0,0,4),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = _isSmallScreen and 4 or 2, ScrollBarImageColor3 = C.ACC,
    CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
ListLayout(SideScroll, nil, Enum.HorizontalAlignment.Center, 2)
Padding(SideScroll, 4, 4, 4, 4)

local ContentFrame = Frame(Body, C.BLACK, UDim2.new(1,-SIDEBAR_W,1,0))
ContentFrame.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
ContentFrame.BackgroundTransparency = 1

-- ============================================================
-- TAB SYSTEM
-- ============================================================
local NAV_ITEMS = {
    {tag="main",     ico="🏠", lbl="Main"},
    {tag="farm",     ico="⚔",  lbl="Farm"},
    {tag="attack",   ico="💥", lbl="Attack"},
    {tag="autoraid", ico="⚡", lbl="Raid"},
    {tag="player",   ico="🧍", lbl="Player"},
    {tag="autoroll", ico="🎲", lbl="Reroll"},
    {tag="settings", ico="⚙",  lbl="Settings"},
}

local Panels   = {}
local NavRefs  = {}
local ActiveTab = ""

local function NewPanel(tag)
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

local function SwitchTab(tag)
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
local function SectionHeader(panel, title, order)
    local f = Frame(panel, C.BLACK, UDim2.new(1,0,0,20))
    f.BackgroundTransparency = 1; f.LayoutOrder = order or 0
    local l = Label(f, "  "..title, 11, C.ACC2, Enum.Font.GothamBold)
    l.Size = UDim2.new(1,0,1,0)
    local line = Frame(f, C.ACC2, UDim2.new(1,0,0,1))
    line.Position = UDim2.new(0,0,1,-1); line.BackgroundTransparency = 0.6
end

local function ToggleRow(panel, title, desc, order, onToggle)
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
local STATE = {autoCollect=false, autoDestroyer=false, autoArise=false, autoRoll=false, noClip=false, antiAfk=false}
local LOOPS = {}
local COLLECTED = {}

local function StopLoop(key)
    if LOOPS[key] then
        pcall(function() task.cancel(LOOPS[key]) end)
        LOOPS[key] = nil
    end
end

local function StartLoop(key, fn)
    StopLoop(key)
    LOOPS[key] = task.spawn(fn)
end

local MA = {running=false, thread=nil, killed=0, killTarget=7, autoCollect=true}
local AG = {running=false, thread=nil, killed=0, collected=0, currentTarget=nil, autoCollect=true}

-- RAID STATE
local RAID = {
    running     = false,
    thread      = nil,
    killed      = 0,
    collected   = 0,
    loopCount   = 0,
    autoAttack  = true,
    autoCollect = true,
    autoJoin    = true,
    joinDelay   = 3,
    nextDelay   = 5,
    raidId      = 935108,
    statusLbl   = nil,
    killLbl     = nil,
    loopLbl     = nil,
    dot         = nil,
}
local _raidOn = false

local _maStatusLbl  = nil
local _noClipConn   = nil
local _antiAfkThread= nil
local _antiAfkStart = nil
local _deadG        = {}
local _mOn          = false
local _agOn         = false
local ORIGIN_POS    = Vector3.new(0,0,0)

local StatusDots = {}
local StatusLbls = {}

-- ============================================================
-- MAPS
-- ============================================================
local MAPS = {}
for i = 1, 18 do
    MAPS[i] = {name="Map "..i, id=50000+i, remote=i<=4 and "Start" or "Local"}
end
local MR = {selected={}, nextMapDelay=3, teleportDelay=3}

local function TpMap(m)
    if m.remote == "Start" then
        pcall(function() RE_StartTp:FireServer({mapId=m.id}) end)
    else
        pcall(function() RE_LocalTp:FireServer({mapId=m.id}) end)
    end
end

-- ============================================================
-- SKILL KEYS
-- ============================================================
local SKL = {
    Z={on=false,t=nil,label="Z"},
    X={on=false,t=nil,label="X"},
    C={on=false,t=nil,label="C"},
    V={on=false,t=nil,label="V"},
    F={on=false,t=nil,label="F"},
}
local SKL_TYPE = {Z=1,X=2,C=3,V=4,F=5}

local function SkOn(n)
    local s = SKL[n]; if s.t then return end
    s.on = true
    s.t = task.spawn(function()
        while s.on do
            for _, hGuid in ipairs(HERO_GUIDS) do
                if RE_HeroSkill then
                    pcall(function()
                        RE_HeroSkill:FireServer({
                            heroGuid  = hGuid,
                            skillType = SKL_TYPE[n] or 1,
                            masterId  = MY_USER_ID,
                        })
                    end)
                end
            end
            task.wait(0.8)
        end
        s.t = nil
    end)
end

local function SkOff(n)
    local s = SKL[n]; s.on = false
    if s.t then pcall(function() task.cancel(s.t) end); s.t = nil end
end

-- ============================================================
-- ENEMY HELPERS
-- ============================================================
local function GetEnemies()
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

local function IsDead(e)
    if _deadG[e.guid] then return true end
    if not e.model or not e.model.Parent then return true end
    local h = e.model:FindFirstChildOfClass("Humanoid")
    return not h or h.Health <= 0
end

local function SaveOrigin()
    local char = LP.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then ORIGIN_POS = hrp.Position end
end

local function ReturnHRPToOrigin()
    local char = LP.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame = CFrame.new(ORIGIN_POS) end
end

local function FireAllDamage(g, ep)
    if RE_Click then pcall(function() RE_Click:InvokeServer({enemyGuid=g, enemyPos=ep}) end) end
    if RE_Atk   then
        pcall(function() RE_Atk:FireServer({attackEnemyGUID=g}) end)
        pcall(function() RE_Atk:FireServer(g) end)
    end
    for _, hGuid in ipairs(HERO_GUIDS) do
        if RE_HeroSkill then
            pcall(function() RE_HeroSkill:FireServer({heroGuid=hGuid, enemyGuid=g, skillType=1, masterId=MY_USER_ID}) end)
            pcall(function() RE_HeroSkill:FireServer({heroGuid=hGuid, enemyGuid=g, skillType=2, masterId=MY_USER_ID}) end)
            pcall(function() RE_HeroSkill:FireServer({heroGuid=hGuid, enemyGuid=g, skillType=3, masterId=MY_USER_ID}) end)
        end
        if RE_HeroStand then
            pcall(function() RE_HeroStand:FireServer({masterId=MY_USER_ID, cframe=CFrame.new(ep+Vector3.new(2,0,2)), guid=hGuid}) end)
        end
    end
end

local function FireHeroRemotes(enemyGuid, enemyPos)
    if not RE_HeroMove then return end
    local heroPosInfos = {}
    for i, hg in ipairs(HERO_GUIDS) do
        heroPosInfos[hg] = enemyPos + Vector3.new((i-1)*3-3, 0, i%2==0 and 2 or -2)
    end
    pcall(function()
        RE_HeroMove:FireServer({
            attackTarget       = enemyGuid,
            userId             = MY_USER_ID,
            heroTagetPosInfos  = heroPosInfos,
        })
    end)
end

if RE_Death then
    RE_Death.OnClientEvent:Connect(function(d)
        if not d then return end
        local g = d.enemyGuid or d.guid
        if g then
            _deadG[g] = true
            if MA.running then MA.killed = MA.killed + 1 end
            if AG.running then AG.killed = AG.killed + 1 end
        end
    end)
end

-- ============================================================
-- DESTROY WORKER
-- ============================================================
local function StartDestroyWorker(checkFn)
    local dstQ = {}
    task.spawn(function()
        while checkFn() do
            if #dstQ > 0 then
                local d = table.remove(dstQ, 1)
                pcall(function() RE_ExtraReward:FireServer({isSell=true, guid=d.guid}) end)
                task.wait(0.1)
            end
            task.wait(0.05)
        end
    end)
end

-- ============================================================
-- ATTACK LOOPS
-- ============================================================
local function AttackLoop_Mass(onStatus)
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

local function AttackLoop_Goyang(onStatus)
    SaveOrigin()
    while AG.running do
        local tgt = AG.currentTarget
        if not tgt then
            if onStatus then onStatus("Tap nama musuh di daftar...") end
            task.wait(0.2); continue
        end
        if IsDead(tgt) or not tgt.model.Parent then
            if onStatus then onStatus("["..tgt.model.Name.."] mati — tap musuh lain") end
            ReturnHRPToOrigin(); task.wait(0.3); continue
        end
        local tHrp = tgt.model:FindFirstChild("HumanoidRootPart")
        if not tHrp then task.wait(0.1); continue end
        local g, snapPos = tgt.guid, tHrp.Position
        local char = LP.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = CFrame.new(snapPos + Vector3.new(0,2,2)) end
        end
        FireHeroRemotes(g, snapPos)
        if onStatus then onStatus("Goyang → ["..tgt.model.Name.."]  Kill: "..AG.killed) end
        local activeTgt = tgt
        while AG.running do
            if AG.currentTarget ~= activeTgt then break end
            if IsDead(activeTgt) or not activeTgt.model.Parent then
                ReturnHRPToOrigin(); break
            end
            FireAllDamage(g, snapPos); task.wait()
        end
    end
    ReturnHRPToOrigin(); return false
end

-- ============================================================
-- RUN LOOP / RUN AG
-- ============================================================
local function RunLoop(state, cfg, loopFn, onStatus, onDone)
    state.running = true; state.killed = 0; state.collected = 0
    StartDestroyWorker(function() return state.running end)
    state.thread = task.spawn(function()
        local last = 0
        while state.running do
            local sel = {}
            for i = 1, #MAPS do if cfg.selected[i] then table.insert(sel, i) end end
            if #sel > 0 then
                local ni = nil
                for _, i in ipairs(sel) do if i > last then ni = i; break end end
                if not ni then ni = sel[1]; last = 0 end
                last = ni
                local m = MAPS[ni]
                if onStatus then onStatus("→ "..m.name) end
                TpMap(m)
                local d = 0
                while d < cfg.teleportDelay and state.running do task.wait(0.2); d = d + 0.2 end
                if not state.running then break end
                if not loopFn(onStatus) then break end
                if onStatus then onStatus("Selesai, delay "..cfg.nextMapDelay.."s...") end
                d = 0
                while d < cfg.nextMapDelay and state.running do task.wait(0.2); d = d + 0.2 end
            else
                last = 0
                local done = loopFn(onStatus)
                if done and state.running then
                    local d = 0
                    while d < cfg.nextMapDelay and state.running do task.wait(0.2); d = d + 0.2 end
                end
            end
        end
        state.running = false
        if onDone then onDone() end
    end)
end

local function RunAG(onStatus, onDone)
    AG.running = true; AG.killed = 0; AG.collected = 0
    StartDestroyWorker(function() return AG.running end)
    AG.thread = task.spawn(function()
        while AG.running do
            local done = AttackLoop_Goyang(onStatus)
            if not AG.running then break end
            if done then task.wait(1) end
        end
        AG.running = false
        if onDone then onDone() end
    end)
end

-- ============================================================
-- AUTO FUNCTIONS
-- ============================================================
local function DoAutoCollect(on)
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
                        pcall(function() RE_CollectItem:InvokeServer(guid) end)
                        pcall(function() RE_ExtraReward:FireServer({isSell=true, guid=guid}) end)
                        task.wait(0.05)
                    end
                end
            end
            task.wait(0.25)
        end
    end)
end

local _destroyerConn = nil
local function DoAutoDestroyer(on)
    StopLoop("destroyer")
    if _destroyerConn then _destroyerConn:Disconnect(); _destroyerConn = nil end
    if not on then return end
    _destroyerConn = workspace.DescendantAdded:Connect(function(obj)
        if not STATE.autoDestroyer then return end
        task.wait(0.1)
        local guid; pcall(function() guid = obj:GetAttribute("GUID") end)
        if guid then pcall(function() RE_ExtraReward:FireServer({isSell=true, guid=guid}) end) end
    end)
end

local _ariseConn = nil
local function DoAutoArise(on)
    StopLoop("arise")
    if _ariseConn then _ariseConn:Disconnect(); _ariseConn = nil end
    if not on then return end
    _ariseConn = workspace.DescendantAdded:Connect(function(obj)
        if not STATE.autoArise then return end
        task.wait(0.1)
        local guid; pcall(function() guid = obj:GetAttribute("GUID") end)
        if guid then pcall(function() RE_ExtraReward:FireServer({isSell=false, isAuto=false, guid=guid}) end) end
    end)
end

local function RefreshStatus()
    local map = {
        collect   = {STATE.autoCollect,   "Auto Collect Gold"},
        destroyer = {STATE.autoDestroyer, "Auto Destroyer"},
        arise     = {STATE.autoArise,     "Auto Arise"},
        roll      = {STATE.autoRoll,      "Auto Roll"},
        noClip    = {STATE.noClip,        "No Clip"},
        antiAfk   = {STATE.antiAfk,       "Anti AFK"},
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

local function DoMassAttack(on)
    if on then
        _mOn = true
        RunLoop(MA, MR, AttackLoop_Mass,
            function(msg) if _maStatusLbl then _maStatusLbl.Text = msg end end,
            function() _mOn = false; if _maStatusLbl then _maStatusLbl.Text = "Selesai" end end)
    else
        _mOn = false; MA.running = false
        if MA.thread then pcall(function() task.cancel(MA.thread) end); MA.thread = nil end
        if _maStatusLbl then _maStatusLbl.Text = "Idle" end
    end
end

local function DoRejoin()
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end)
end

-- ============================================================
-- QUIRK DATA
-- ============================================================
local QUIRK_LIST_PER_SLOT = {
    {
        {id=99001,name="Silver Purse"},  {id=99002,name="Raw Strength"},   {id=99003,name="Tiny Luck"},
        {id=99004,name="Precise Strike"},{id=99005,name="Combo Rhythm"},   {id=99006,name="Lucky Charm"},
        {id=99007,name="Gold Sense"},    {id=99008,name="Berserker's Rage"},{id=99009,name="Rapid Slash"},
        {id=99010,name="Godslayer"},     {id=99011,name="Phantom Rush"},    {id=99012,name="Legend Hunter"},
        {id=99013,name="Midas Touch"},   {id=99014,name="Hyper Sprint"},    {id=99015,name="Time Skipper"},
        {id=99016,name="Cosmic Luck"},   {id=99017,name="Destiny Rewrite"},
    },
    {
        {id=99019,name="Thrifty Novice"},      {id=99020,name="Sharp Instinct"},       {id=99021,name="Mana Surge"},
        {id=99022,name="Meticulous"},          {id=99023,name="Keen Eyes"},            {id=99024,name="Elemental Affinity"},
        {id=99025,name="Resource Master"},     {id=99026,name="Killer Instinct"},      {id=99027,name="Arcane Mastery"},
        {id=99028,name="Combat Optimization"}, {id=99029,name="Efficient Destruction"},{id=99030,name="Savage Blow"},
        {id=99031,name="Resource Conqueror"},  {id=99032,name="Elemental Overload"},   {id=99033,name="Crimson Executioner"},
        {id=99034,name="God's Gift"},          {id=99035,name="Apocalypse Carnival"},  {id=99036,name="Divine Judgment"},
    },
    {
        {id=99037,name="Awakening Will"},   {id=99038,name="Omen of Doom"},       {id=99041,name="Breath of the End"},
        {id=99042,name="Sharp Edge"},       {id=99043,name="Boiling Fury"},       {id=99045,name="Breaking Power"},
        {id=99047,name="Whisper of Death"}, {id=99048,name="Annihilation Boost"}, {id=99049,name="Slayer's Instinct"},
        {id=99050,name="Harbinger of Ruin"},{id=99052,name="Godslayer's Fury"},   {id=99053,name="Deicide's Endgame"},
        {id=99054,name="Final Arbiter"},
    },
}

local QUIRK_MAP = {}
for _, list in ipairs(QUIRK_LIST_PER_SLOT) do
    for _, q in ipairs(list) do QUIRK_MAP[q.id] = q.name end
end

local W_QUIRK_LIST_PER_SLOT = {
    {
        {id=99055,name="Improved Drop Rate"}, {id=99056,name="Party ATK"},          {id=99057,name="Divine Proc Chance"},
        {id=99058,name="Team Crit Rate"},     {id=99059,name="Group Skill DMG"},    {id=99060,name="Serendipity"},
        {id=99061,name="Master Looter"},      {id=99062,name="Gold Gain"},           {id=99063,name="Divine Intervention"},
        {id=99064,name="Item Drop Rate"},     {id=99065,name="Critical Resonance"},  {id=99066,name="Prosperous Hunter"},
        {id=99067,name="Celestial Onslaught"},{id=99068,name="Lucky Scavenger"},    {id=99069,name="Titan's Wrath"},
        {id=99070,name="Omnipotent Benefactor"},{id=99071,name="Archangel's Judgment"},{id=99072,name="Avatar of Destruction"},
    },
    {
        {id=99073,name="Improved Drop Rate"}, {id=99074,name="Party ATK"},          {id=99075,name="Divine Proc Chance"},
        {id=99076,name="Team Crit Rate"},     {id=99077,name="Group Skill DMG"},    {id=99078,name="Serendipity"},
        {id=99079,name="Master Looter"},      {id=99080,name="Gold Gain"},           {id=99081,name="Divine Intervention"},
        {id=99082,name="Item Drop Rate"},     {id=99083,name="Critical Resonance"},  {id=99084,name="Prosperous Hunter"},
        {id=99085,name="Celestial Onslaught"},{id=99086,name="Lucky Scavenger"},    {id=99087,name="Titan's Wrath"},
        {id=99088,name="Omnipotent Benefactor"},{id=99089,name="Archangel's Judgment"},{id=99090,name="Avatar of Destruction"},
    },
    {
        {id=99091,name="Improved Drop Rate"}, {id=99092,name="Party ATK"},          {id=99093,name="Divine Proc Chance"},
        {id=99094,name="Team Crit Rate"},     {id=99095,name="Group Skill DMG"},    {id=99096,name="Serendipity"},
        {id=99097,name="Master Looter"},      {id=99098,name="Gold Gain"},           {id=99099,name="Divine Intervention"},
        {id=99100,name="Item Drop Rate"},     {id=99101,name="Critical Resonance"},  {id=99102,name="Prosperous Hunter"},
        {id=99103,name="Celestial Onslaught"},{id=99104,name="Lucky Scavenger"},    {id=99105,name="Titan's Wrath"},
        {id=99106,name="Omnipotent Benefactor"},{id=99107,name="Archangel's Judgment"},{id=99108,name="Avatar of Destruction"},
    },
}

local W_QUIRK_MAP = {}
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
-- REROLL STATE
-- ============================================================
local HR = {
    guid="", captured=false, captureMethod="",
    slotDrawId         = {920001, 920002, 920003},
    slotDrawIdCaptured = {false, false, false},
    slotRunning        = {false, false, false},
    slotTarget         = {{},{},{}},
    running            = false,
    statusLbl          = nil,
    dotRef             = nil,
    captureStatusLbl   = nil,
    slotStatusLbl      = {nil,nil,nil},
    slotSummaryLbls    = {nil,nil,nil},
    weaponSlotLbls     = {nil,nil,nil},
}

local WR = {
    guid="", captured=false, running=false,
    slotDrawId  = {960001, 960002, 960003},
    slotRunning = {false, false, false},
    slotTarget  = {{},{},{}},
    statusLbl   = nil,
    dotRef      = nil,
    slotSummaryLbls = {nil,nil,nil},
    weaponSlotLbls  = {nil,nil,nil},
}

local PGR = {
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
local HALO = {
    running    = {false, false, false},
    statLbls   = {nil, nil, nil},
    dotRefs    = {nil, nil, nil},
    attemptLbls= {nil, nil, nil},
    toggleBtns = {nil, nil, nil},
    toggleKnobs= {nil, nil, nil},
    enOnFlags  = {false, false, false},
}

local MAX_PER_SLOT   = 3
local W_MAX_PER_SLOT = 3
local _spyLog        = {}
local _layer0Active  = false
local _watcherConns  = {}

-- ============================================================
-- DD LAYER
-- ============================================================
local DDLayer = Frame(ScreenGui, C.BLACK, UDim2.new(1,0,1,0))
DDLayer.BackgroundTransparency = 1; DDLayer.ZIndex = 9998; DDLayer.Visible = false
DDLayer.Name = "ASH_DD"

local _activeDDClose = nil
local function CloseActiveDD()
    if _activeDDClose then _activeDDClose(); _activeDDClose = nil end
end
DDLayer.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        CloseActiveDD()
    end
end)

-- ============================================================
-- QUIRK HELPERS
-- ============================================================
local function AddQuirkToSlot(slotIndex, quirkId, quirkName)
    if not slotIndex or not quirkId then return end
    local list = QUIRK_LIST_PER_SLOT[slotIndex]
    if not list then return end
    for _, q in ipairs(list) do
        if q.id == quirkId then
            if quirkName and not quirkName:find("^ID:") then q.name = quirkName end
            return
        end
    end
    table.insert(list, {id=quirkId, name=quirkName or ("ID:"..quirkId)})
    if not QUIRK_MAP[quirkId] then QUIRK_MAP[quirkId] = quirkName or ("ID:"..quirkId) end
end

local function GetSlotSummary(slotIndex)
    local ids = {}
    for id in pairs(HR.slotTarget[slotIndex]) do table.insert(ids, id) end
    if #ids == 0 then return "--" end
    local names = {}
    for _, id in ipairs(ids) do table.insert(names, QUIRK_MAP[id] or "?") end
    table.sort(names)
    if #names == 1 then return names[1] end
    if #names <= 2 then return table.concat(names, ", ") end
    return names[1]..", "..names[2].." +"..(#names-2).." lagi"
end

local function GetWeaponSlotSummary(slotIndex)
    local ids = {}
    for id in pairs(WR.slotTarget[slotIndex]) do table.insert(ids, id) end
    if #ids == 0 then return "--" end
    local names = {}
    for _, id in ipairs(ids) do table.insert(names, W_QUIRK_MAP[id] or "?") end
    table.sort(names)
    if #names == 1 then return names[1] end
    if #names <= 2 then return table.concat(names, ", ") end
    return names[1]..", "..names[2].." +"..(#names-2).." lagi"
end

-- ============================================================
-- FORWARD DECLARATIONS
-- ============================================================
local StartSlotLoop
local StartWeaponSlotLoop
local SetHeroGuid
local SetWeaponGuid

-- ============================================================
-- SLOT ROLL FUNCTIONS
-- ============================================================
local function RefreshSlotUI(slotIndex)
    local summary = GetSlotSummary(slotIndex)
    if HR.slotSummaryLbls[slotIndex] then
        HR.slotSummaryLbls[slotIndex].Text = summary
    end
    if HR.weaponSlotLbls[slotIndex] then
        HR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": "..summary
        HR.weaponSlotLbls[slotIndex].TextColor3 = C.TXT2
    end
    if STATE.autoRoll and HR.slotRunning[slotIndex] and HR.captured and HR.guid ~= "" then
        HR.slotRunning[slotIndex] = false
        StopLoop("roll"..slotIndex)
        task.spawn(function()
            task.wait(0.05)
            if STATE.autoRoll then StartSlotLoop(slotIndex) end
        end)
    end
end

local function RefreshWeaponSlotUI(slotIndex)
    local summary = GetWeaponSlotSummary(slotIndex)
    if WR.slotSummaryLbls[slotIndex] then WR.slotSummaryLbls[slotIndex].Text = summary end
    if WR.weaponSlotLbls[slotIndex] then
        WR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": "..summary
        WR.weaponSlotLbls[slotIndex].TextColor3 = C.TXT2
    end
end

local function RefreshPGSummary(si)
    if not PGR.sumLbls[si] then return end
    local names = {}
    for _, g in ipairs(PG_GRADES_PER_MACHINE[si]) do
        if PGR.targets[si][g.id] then names[#names+1] = g.name end
    end
    PGR.sumLbls[si].Text = #names > 0 and table.concat(names, " / ") or "--"
end

local function StopSlotRoll(slotIndex, reason)
    HR.slotRunning[slotIndex] = false
    StopLoop("roll"..slotIndex)
    if HR.slotStatusLbl[slotIndex] then
        HR.slotStatusLbl[slotIndex].Text = reason or "✓ Selesai"
        HR.slotStatusLbl[slotIndex].TextColor3 = Color3.fromRGB(80,220,80)
    end
    if not (HR.slotRunning[1] or HR.slotRunning[2] or HR.slotRunning[3]) then
        HR.running = false; STATE.autoRoll = false
        if HR.statusLbl then
            HR.statusLbl.Text = "✓ Semua slot selesai"
            HR.statusLbl.TextColor3 = Color3.fromRGB(80,220,80)
        end
        if HR.dotRef then HR.dotRef.BackgroundColor3 = Color3.fromRGB(100,100,100) end
        RefreshStatus()
    end
end

local function _ScanQuirkId(tbl, slotIdSet, depth)
    if depth > 3 then return nil end
    local PRIO = {"finalResultId","quirkId","resultId","quirk_id","id","Id","ID","result","Result","finalId","drawResultId"}
    for _, key in ipairs(PRIO) do
        local v = tbl[key]
        if type(v) == "number" and slotIdSet[v] then return v end
        if type(v) == "number" and QUIRK_MAP[v]  then return v end
    end
    for _, v in pairs(tbl) do
        if type(v) == "number" and slotIdSet[v] then return v end
        if type(v) == "table" then
            local f = _ScanQuirkId(v, slotIdSet, depth+1)
            if f then return f end
        end
    end
    for _, v in pairs(tbl) do
        if type(v) == "number" and QUIRK_MAP[v] then return v end
    end
    return nil
end

StartSlotLoop = function(slotIndex)
    local slotPool = QUIRK_LIST_PER_SLOT[slotIndex]
    local allIdsInSlot = {}
    for _, q in ipairs(slotPool) do table.insert(allIdsInSlot, q.id) end
    HR.slotRunning[slotIndex] = true
    local initStr = GetSlotSummary(slotIndex)
    if HR.slotStatusLbl[slotIndex] then
        HR.slotStatusLbl[slotIndex].Text = "⟳ rolling..."
        HR.slotStatusLbl[slotIndex].TextColor3 = Color3.fromRGB(255,200,100)
    end
    if HR.weaponSlotLbls[slotIndex] then
        HR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": 🔄 Mencari: "..initStr
        HR.weaponSlotLbls[slotIndex].TextColor3 = Color3.fromRGB(255,200,100)
    end
    LOOPS["roll"..slotIndex] = task.spawn(function()
        local attempt = 0
        while HR.slotRunning[slotIndex] do
            attempt = attempt + 1
            local curTargets = {}
            for id in pairs(HR.slotTarget[slotIndex]) do table.insert(curTargets, id) end
            local curHasTarget = (#curTargets > 0)
            local curTargetStr = curHasTarget and GetSlotSummary(slotIndex) or "apapun"
            if HR.slotStatusLbl[slotIndex] then
                HR.slotStatusLbl[slotIndex].Text = "⟳ #"..attempt.." | "..curTargetStr
                HR.slotStatusLbl[slotIndex].TextColor3 = Color3.fromRGB(255,200,100)
            end
            if HR.weaponSlotLbls[slotIndex] then
                HR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": 🔄 #"..attempt.." → "..curTargetStr
                HR.weaponSlotLbls[slotIndex].TextColor3 = Color3.fromRGB(255,200,100)
            end
            if not RE_RandomHeroQuirk then
                RE_RandomHeroQuirk = Remotes:FindFirstChild("RandomHeroQuirk")
            end
            if not RE_RandomHeroQuirk then task.wait(2); continue end
            local ok, result = pcall(function()
                return RE_RandomHeroQuirk:InvokeServer({heroGuid=HR.guid, drawId=HR.slotDrawId[slotIndex]})
            end)
            if not ok then task.wait(0.5); continue end
            if type(result) == "table" then
                local slotIdSet = {}
                for _, q in ipairs(slotPool) do slotIdSet[q.id] = true end
                local gotId = _ScanQuirkId(result, slotIdSet, 0)
                local name  = QUIRK_MAP[gotId] or (gotId and ("ID:"..tostring(gotId)) or "???")
                if HR.weaponSlotLbls[slotIndex] then
                    HR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": ⚡ "..name
                    HR.weaponSlotLbls[slotIndex].TextColor3 = Color3.fromRGB(220,220,80)
                end
                local curTargetSet = {}
                for _, id in ipairs(curTargets) do curTargetSet[id] = true end
                local isHit = gotId ~= nil and (slotIdSet[gotId] or QUIRK_MAP[gotId])
                              and (not curHasTarget or curTargetSet[gotId] == true)
                if isHit then
                    StopSlotRoll(slotIndex, "✓ "..name.." (#"..attempt..")")
                    if HR.weaponSlotLbls[slotIndex] then
                        HR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": ✅ "..name
                        HR.weaponSlotLbls[slotIndex].TextColor3 = Color3.fromRGB(80,220,80)
                    end
                    return
                end
                task.wait(0.05)
            else
                task.wait(0.3)
            end
        end
    end)
end

local function DoAutoRoll(on)
    for i = 1, 3 do HR.slotRunning[i] = false end
    StopLoop("roll1"); StopLoop("roll2"); StopLoop("roll3")
    if not on then
        HR.running = false
        if HR.statusLbl then HR.statusLbl.Text = "Idle"; HR.statusLbl.TextColor3 = C.TXT2 end
        if HR.dotRef then HR.dotRef.BackgroundColor3 = Color3.fromRGB(100,100,100) end
        for i = 1, 3 do
            if HR.slotStatusLbl[i] then
                HR.slotStatusLbl[i].Text = "Idle"; HR.slotStatusLbl[i].TextColor3 = C.TXT2
            end
        end
        return
    end
    if (not HR.captured or HR.guid == "") and #HERO_GUIDS > 0 then
        SetHeroGuid(HERO_GUIDS[1], "fallback:HeroGuids")
    end
    if not HR.captured or HR.guid == "" then
        if HR.statusLbl then
            HR.statusLbl.Text = "Klik ReRoll manual 1x dulu di game!"
            HR.statusLbl.TextColor3 = Color3.fromRGB(255,100,60)
        end
        STATE.autoRoll = false; RefreshStatus(); return
    end
    task.spawn(function()
        task.wait(0.05)
        if not STATE.autoRoll then return end
        HR.running = true
        if HR.dotRef then HR.dotRef.BackgroundColor3 = Color3.fromRGB(255,200,60) end
        StartSlotLoop(1); StartSlotLoop(2); StartSlotLoop(3)
    end)
end

-- ============================================================
-- WEAPON ROLL FUNCTIONS
-- ============================================================
local function StopWeaponSlotRoll(slotIndex)
    WR.slotRunning[slotIndex] = false
    StopLoop("wroll"..slotIndex)
    if not (WR.slotRunning[1] or WR.slotRunning[2] or WR.slotRunning[3]) then
        WR.running = false
        if WR.statusLbl then
            WR.statusLbl.Text = "Semua slot selesai"
            WR.statusLbl.TextColor3 = Color3.fromRGB(80,220,80)
        end
        if WR.dotRef then WR.dotRef.BackgroundColor3 = Color3.fromRGB(100,100,100) end
    end
end

StartWeaponSlotLoop = function(slotIndex)
    local slotPool = W_QUIRK_LIST_PER_SLOT[slotIndex]
    local allIds = {}
    for _, q in ipairs(slotPool) do table.insert(allIds, q.id) end
    WR.slotRunning[slotIndex] = true
    local initStr = GetWeaponSlotSummary(slotIndex)
    if WR.weaponSlotLbls[slotIndex] then
        WR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": Mencari: "..initStr
        WR.weaponSlotLbls[slotIndex].TextColor3 = Color3.fromRGB(255,200,100)
    end
    LOOPS["wroll"..slotIndex] = task.spawn(function()
        local attempt = 0
        while WR.slotRunning[slotIndex] do
            attempt = attempt + 1
            local curTargets = {}
            for id in pairs(WR.slotTarget[slotIndex]) do table.insert(curTargets, id) end
            local curHasTarget = (#curTargets > 0)
            local curTargetStr = curHasTarget and GetWeaponSlotSummary(slotIndex) or "apapun"
            if WR.weaponSlotLbls[slotIndex] then
                WR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": #"..attempt.." → "..curTargetStr
                WR.weaponSlotLbls[slotIndex].TextColor3 = Color3.fromRGB(255,200,100)
            end
            if not RE_RandomWeaponQuirk then task.wait(1); continue end
            local ok, result = pcall(function()
                return RE_RandomWeaponQuirk:InvokeServer({guid=WR.guid, drawId=WR.slotDrawId[slotIndex]})
            end)
            if not ok then task.wait(0.5); continue end
            if type(result) == "table" then
                local slotIdSet = {}
                for _, q in ipairs(slotPool) do slotIdSet[q.id] = true end
                local gotId = nil
                local PRIO = {"finalResultId","quirkId","resultId","id","Id","result","Result"}
                for _, key in ipairs(PRIO) do
                    local v = result[key]
                    if type(v) == "number" and (slotIdSet[v] or W_QUIRK_MAP[v]) then gotId = v; break end
                end
                if not gotId then
                    for _, v in pairs(result) do
                        if type(v) == "number" and (slotIdSet[v] or W_QUIRK_MAP[v]) then gotId = v; break end
                    end
                end
                local name = W_QUIRK_MAP[gotId] or (gotId and ("ID:"..tostring(gotId)) or "???")
                if WR.weaponSlotLbls[slotIndex] then
                    WR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": ⚡ "..name
                    WR.weaponSlotLbls[slotIndex].TextColor3 = Color3.fromRGB(220,220,80)
                end
                local curTargetSet = {}
                for _, id in ipairs(curTargets) do curTargetSet[id] = true end
                local isValid = gotId ~= nil and (slotIdSet[gotId] or W_QUIRK_MAP[gotId])
                local hit = isValid and (not curHasTarget or curTargetSet[gotId] == true)
                if hit then
                    StopWeaponSlotRoll(slotIndex)
                    if WR.weaponSlotLbls[slotIndex] then
                        WR.weaponSlotLbls[slotIndex].Text = "Slot "..slotIndex..": ✅ "..name
                        WR.weaponSlotLbls[slotIndex].TextColor3 = Color3.fromRGB(80,220,80)
                    end
                    return
                end
                task.wait(0.05)
            else
                task.wait(0.3)
            end
        end
    end)
end

local function DoAutoRollWeapon(on)
    for i = 1, 3 do WR.slotRunning[i] = false end
    StopLoop("wroll1"); StopLoop("wroll2"); StopLoop("wroll3")
    if not on then
        WR.running = false
        if WR.statusLbl then WR.statusLbl.Text = "Idle"; WR.statusLbl.TextColor3 = C.TXT2 end
        if WR.dotRef then WR.dotRef.BackgroundColor3 = Color3.fromRGB(100,100,100) end
        return
    end
    if not WR.captured or WR.guid == "" then
        if WR.statusLbl then
            WR.statusLbl.Text = "Equip weapon dulu di inventory!"
            WR.statusLbl.TextColor3 = Color3.fromRGB(255,100,60)
        end
        return
    end
    WR.running = true
    task.spawn(function()
        task.wait(0.05)
        if not WR.running then return end
        if WR.dotRef then WR.dotRef.BackgroundColor3 = Color3.fromRGB(255,200,60) end
        StartWeaponSlotLoop(1); StartWeaponSlotLoop(2); StartWeaponSlotLoop(3)
    end)
end

-- ============================================================
-- PET GEAR FASTROLL
-- ============================================================
local function SetPetGearGuid(guid, drawId)
    if not guid or guid == "" then return end
    if not IsValidUUID(guid) then return end
    for i, did in ipairs(PG_DRAW_IDS) do
        if drawId == did then
            if PGR.guids[i] == guid then return end
            PGR.guids[i] = guid; PGR.captured[i] = true
            if PGR.statLbls[i] then
                PGR.statLbls[i].Text = "✔ GUID captured — siap roll"
                PGR.statLbls[i].TextColor3 = Color3.fromRGB(80,220,80)
            end
            if PGR.dotRefs[i] then PGR.dotRefs[i].BackgroundColor3 = Color3.fromRGB(80,220,80) end
            return
        end
    end
    for i = 1, 3 do
        if not PGR.captured[i] then
            PGR.guids[i] = guid; PGR.captured[i] = true
            if PGR.statLbls[i] then
                PGR.statLbls[i].Text = "✔ GUID captured (auto)"
                PGR.statLbls[i].TextColor3 = Color3.fromRGB(80,220,80)
            end
            if PGR.dotRefs[i] then PGR.dotRefs[i].BackgroundColor3 = Color3.fromRGB(80,220,80) end
            return
        end
    end
end

local function PGR_SetToggleOff(si)
    PGR.enOnFlags[si] = false
    if PGR.toggleBtns[si] then
        PGR.toggleBtns[si].BackgroundColor3 = Color3.fromRGB(60,60,60)
    end
    if PGR.toggleKnobs[si] then
        PGR.toggleKnobs[si].Position = UDim2.new(0,2,0.5,-8)
    end
end

local function PGR_GetTargetStr(si)
    local list = {}
    for _, g in ipairs(PG_GRADES_PER_MACHINE[si]) do
        if PGR.targets[si][g.id] then list[#list+1] = g.name end
    end
    return #list > 0 and table.concat(list, " / ") or "--"
end

local function DoAutoRollPetGear(si, on)
    local key = "pgroll"..si
    PGR.running[si] = false
    StopLoop(key)

    local function setStatus(dot, txt, col)
        if PGR.dotRefs[si]  then PGR.dotRefs[si].BackgroundColor3 = dot end
        if PGR.statLbls[si] then PGR.statLbls[si].Text = txt; PGR.statLbls[si].TextColor3 = col end
    end

    if not on then
        setStatus(Color3.fromRGB(100,100,100), "⏹ Idle", C.TXT2)
        if PGR.attemptLbls[si] then PGR.attemptLbls[si].Text = "Attempt: —" end
        if PGR.lastLbls[si]    then PGR.lastLbls[si].Text    = "Last: —" end
        return
    end

    if next(PGR.targets[si]) == nil then
        setStatus(Color3.fromRGB(255,100,80), "⚠ Pilih target grade dulu!", Color3.fromRGB(255,100,80))
        PGR_SetToggleOff(si)
        return
    end

    PGR.running[si] = true

    LOOPS[key] = task.spawn(function()
        local attempt   = 0
        setStatus(Color3.fromRGB(255,200,60), "⟳ Memulai roll...", Color3.fromRGB(255,200,60))

        local myGradePool = PG_GRADES_PER_MACHINE[si]
        local myGradeIdSet = {}
        for _, g in ipairs(myGradePool) do myGradeIdSet[g.id] = true end
        while PGR.running[si] do
            if not PGR.captured[si] or PGR.guids[si] == "" then
                setStatus(Color3.fromRGB(255,200,60), "⚠ Roll "..PG_MACHINE_NAMES[si].." 1x dulu di game!", Color3.fromRGB(255,200,60))
                task.wait(1); continue
            end
            if next(PGR.targets[si]) == nil then
                setStatus(Color3.fromRGB(255,80,80), "⚠ Target grade kosong! Pilih dulu.", Color3.fromRGB(255,80,80))
                task.wait(1); continue
            end
            local remote = RE_RandomHeroEquipGrade
            if not remote then
                setStatus(Color3.fromRGB(255,80,80), "⚠ Remote tidak ditemukan!", Color3.fromRGB(255,80,80))
                task.wait(2); continue
            end
            attempt = attempt + 1
            local targetStr = PGR_GetTargetStr(si)
            setStatus(Color3.fromRGB(255,160,30), "🔄 Rolling #"..attempt.."  |  Target: "..targetStr, C.ACC2)
            if PGR.attemptLbls[si] then
                PGR.attemptLbls[si].Text = "Attempt: #"..attempt
                PGR.attemptLbls[si].TextColor3 = C.TXT2
            end
            local ok, res = pcall(function()
                return remote:InvokeServer({guid = PGR.guids[si], drawId = PG_DRAW_IDS[si]})
            end)
            if not ok then
                setStatus(Color3.fromRGB(255,80,80), "⚠ Error remote (#"..attempt..")", Color3.fromRGB(255,80,80))
                task.wait(0.5); continue
            end
            local gotId   = nil
            local gotName = "?"
            if type(res) == "table" then
                if type(res.data) == "table" and type(res.data.grade) == "number" then
                    gotId = res.data.grade
                end
                if not gotId then
                    local function ScanId(tbl, depth)
                        if depth > 6 or gotId then return end
                        for _, v in pairs(tbl) do
                            if gotId then break end
                            if type(v) == "number" and myGradeIdSet[v] then
                                gotId = v
                            elseif type(v) == "table" then
                                ScanId(v, depth + 1)
                            end
                        end
                    end
                    ScanId(res, 0)
                end
                if gotId then gotName = PG_GRADE_MAP[gotId] or ("ID:"..tostring(gotId)) end
            elseif res == false or res == nil then
                task.wait(0.5); continue
            end
            if PGR.lastLbls[si] then
                local isTarget = gotId and PGR.targets[si][gotId]
                PGR.lastLbls[si].Text = "Last: "..gotName.." (id:"..tostring(gotId or "?")..")"
                PGR.lastLbls[si].TextColor3 = isTarget and Color3.fromRGB(80,220,80) or Color3.fromRGB(180,180,180)
            end
            local hit = gotId ~= nil and myGradeIdSet[gotId] and PGR.targets[si][gotId]
            if hit then
                PGR.running[si] = false
                StopLoop(key)
                setStatus(Color3.fromRGB(80,220,80), "✅ DAPAT "..gotName.."!  ("..attempt.."x roll)", Color3.fromRGB(80,220,80))
                if PGR.attemptLbls[si] then
                    PGR.attemptLbls[si].Text  = "✅ Selesai dalam "..attempt.." roll"
                    PGR.attemptLbls[si].TextColor3 = Color3.fromRGB(80,220,80)
                end
                if PGR.lastLbls[si] then
                    PGR.lastLbls[si].Text = "✅ "..gotName
                    PGR.lastLbls[si].TextColor3 = Color3.fromRGB(80,220,80)
                end
                PGR_SetToggleOff(si)
                return
            end
            task.wait(0.1)
        end
        setStatus(Color3.fromRGB(100,100,100), "⏹ Dihentikan ("..attempt.."x roll)", C.TXT2)
        if PGR.attemptLbls[si] then
            PGR.attemptLbls[si].Text = "Attempt: "..attempt.."x"
            PGR.attemptLbls[si].TextColor3 = C.TXT2
        end
    end)
end

-- ============================================================
-- AUTO ROLL HALO
-- ============================================================
local function HALO_SetToggleOff(hi)
    HALO.enOnFlags[hi] = false
    if HALO.toggleBtns[hi]  then HALO.toggleBtns[hi].BackgroundColor3  = Color3.fromRGB(60,60,60) end
    if HALO.toggleKnobs[hi] then HALO.toggleKnobs[hi].Position = UDim2.new(0,2,0.5,-9) end
end

local function DoAutoRollHalo(hi, on)
    local key = "haloroll"..hi
    HALO.running[hi] = false
    StopLoop(key)

    local function setStatus(dot, txt, col)
        if HALO.dotRefs[hi]  then HALO.dotRefs[hi].BackgroundColor3 = dot end
        if HALO.statLbls[hi] then HALO.statLbls[hi].Text = txt; HALO.statLbls[hi].TextColor3 = col end
    end

    if not on then
        setStatus(Color3.fromRGB(100,100,100), "⏹ Idle", C.TXT2)
        if HALO.attemptLbls[hi] then HALO.attemptLbls[hi].Text = "Attempt: —" end
        return
    end

    HALO.running[hi] = true

    LOOPS[key] = task.spawn(function()
        local attempt = 0
        if not RE_RerollHalo then
            setStatus(Color3.fromRGB(255,80,80), "⚠ Remote RerollHalo tidak ditemukan!", Color3.fromRGB(255,80,80))
            HALO_SetToggleOff(hi)
            HALO.running[hi] = false
            return
        end
        local startOffset = (hi - 1) * 0.15
        if startOffset > 0 then task.wait(startOffset) end
        setStatus(Color3.fromRGB(255,200,60), "⟳ Memulai gacha "..HALO_NAMES[hi].."...", Color3.fromRGB(255,200,60))
        local interval = 0.30 + (hi - 1) * 0.03
        while HALO.running[hi] do
            attempt = attempt + 1
            if HALO.attemptLbls[hi] then
                HALO.attemptLbls[hi].Text = "Attempt: #"..attempt
                HALO.attemptLbls[hi].TextColor3 = C.TXT2
            end
            setStatus(Color3.fromRGB(255,160,30), "🎰 Gacha #"..attempt.."  |  "..HALO_NAMES[hi], C.ACC2)
            task.spawn(function()
                pcall(function() RE_RerollHalo:InvokeServer(HALO_DRAW_ID[hi]) end)
            end)
            task.wait(interval)
        end
        setStatus(Color3.fromRGB(100,100,100), "⏹ Dihentikan ("..attempt.."x gacha)", C.TXT2)
        if HALO.attemptLbls[hi] then
            HALO.attemptLbls[hi].Text = "Total: "..attempt.."x gacha"
            HALO.attemptLbls[hi].TextColor3 = C.TXT2
        end
    end)
end

-- ============================================================
-- GUID CAPTURE
-- ============================================================
SetHeroGuid = function(guid, method)
    if not guid or guid == "" then return end
    if not IsValidUUID(guid) then return end
    if HR.guid == guid then return end
    local isSwitch = HR.captured and HR.guid ~= "" and HR.guid ~= guid
    HR.guid = guid; HR.captured = true; HR.captureMethod = method or "unknown"
    if HR.statusLbl then
        HR.statusLbl.Text = isSwitch and "Hero berganti — GUID updated!" or "Captured ["..(method or "?").."] — siap reroll"
        HR.statusLbl.TextColor3 = Color3.fromRGB(80,220,80)
    end
    if HR.captureStatusLbl then
        HR.captureStatusLbl.Text = "["..(method or "?").."] — "..HR.guid:sub(1,18).."..."
        HR.captureStatusLbl.TextColor3 = Color3.fromRGB(80,220,80)
    end
    if HR.dotRef then HR.dotRef.BackgroundColor3 = Color3.fromRGB(80,220,80) end
    if isSwitch and STATE.autoRoll then
        task.spawn(function()
            for i = 1, 3 do HR.slotRunning[i] = false; StopLoop("roll"..i) end
            task.wait(0.1)
            if not STATE.autoRoll then return end
            for i = 1, 3 do StartSlotLoop(i) end
            if HR.statusLbl then
                HR.statusLbl.Text = "Restart — hero baru aktif"
                HR.statusLbl.TextColor3 = Color3.fromRGB(255,200,60)
            end
        end)
    end
end

SetWeaponGuid = function(guid)
    if not guid or guid == "" then return end
    if not IsValidUUID(guid) then return end
    if WR.guid == guid then return end
    local isSwitch = WR.captured and WR.guid ~= ""
    WR.guid = guid; WR.captured = true
    if WR.statusLbl then
        WR.statusLbl.Text = isSwitch and "Weapon berganti — GUID updated!" or "Captured — siap reroll"
        WR.statusLbl.TextColor3 = Color3.fromRGB(80,220,80)
    end
    if WR.dotRef then WR.dotRef.BackgroundColor3 = Color3.fromRGB(80,220,80) end
    if isSwitch and WR.running then
        task.spawn(function()
            for i = 1, 3 do WR.slotRunning[i] = false; StopLoop("wroll"..i) end
            task.wait(0.1)
            if not WR.running then return end
            for i = 1, 3 do StartWeaponSlotLoop(i) end
            if WR.statusLbl then
                WR.statusLbl.Text = "Restart — weapon baru aktif"
                WR.statusLbl.TextColor3 = Color3.fromRGB(255,200,60)
            end
        end)
    end
end

-- ============================================================
-- UNIVERSAL SPY
-- ============================================================
local function SetupUniversalSpy()
    if _layer0Active then return end

    local function HandleRequest(self, method, ...)
        local args = {...}
        if RE_EquipWeapon and self == RE_EquipWeapon then
            local g = args[1]
            if type(g) == "string" and IsValidUUID(g) then
                SetWeaponGuid(g)
            elseif type(g) == "table" then
                local gv = g.guid or g.weaponGuid or g.id
                if gv and IsValidUUID(tostring(gv)) then SetWeaponGuid(tostring(gv)) end
            end
        end
        if RE_HeroMove and self == RE_HeroMove then
            local a = args[1]
            if type(a) == "table" and type(a.heroTagetPosInfos) == "table" then
                for hGuid in pairs(a.heroTagetPosInfos) do
                    if IsValidUUID(tostring(hGuid)) then
                        HERO_GUIDS = {tostring(hGuid)}
                        SetHeroGuid(tostring(hGuid), "HeroMove"); break
                    end
                end
            end
        end
        if self == RE_RandomHeroQuirk or self == RE_AutoHeroQuirk then
            local a = args[1]
            if type(a) == "table" then
                local g = a.heroGuid or a.HeroGuid or a.hero_guid or a.guid
                if g and IsValidUUID(tostring(g)) then
                    SetHeroGuid(tostring(g), tostring(self.Name))
                end
                local d = a.drawId or a.DrawId
                if type(d) == "number" then
                    local found = false
                    for si = 1, 3 do
                        if HR.slotDrawId[si] == d then
                            HR.slotDrawIdCaptured[si] = true; found = true; break
                        end
                    end
                    if not found then
                        for si = 1, 3 do
                            if not HR.slotDrawIdCaptured[si] then
                                HR.slotDrawId[si] = d; HR.slotDrawIdCaptured[si] = true; break
                            end
                        end
                    end
                end
                if type(a.stopQuirkIds) == "table" then
                    local slotIdx = nil
                    local d2 = a.drawId or a.DrawId
                    if type(d2) == "number" then
                        for si, did in ipairs(HR.slotDrawId) do
                            if did == d2 then slotIdx = si; break end
                        end
                    end
                    if slotIdx then
                        for _, qid in ipairs(a.stopQuirkIds) do
                            if type(qid) == "number" and not QUIRK_MAP[qid] then
                                AddQuirkToSlot(slotIdx, qid, "ID:"..qid)
                            end
                        end
                    end
                end
            end
        end
        if RE_RandomHeroEquipGrade and self == RE_RandomHeroEquipGrade then
            local a = type(args[1]) == "table" and args[1] or {}
            local g = a.guid or a.Guid or a.heroEquipGuid or a.equipGuid
            local d = a.drawId or a.DrawId
            if g then
                for i, did in ipairs(PG_DRAW_IDS) do
                    if d == did and PGR.captured[i] and PGR.guids[i] ~= tostring(g) then
                        if PGR.running[i] then
                            PGR.running[i] = false; StopLoop("pgroll"..i)
                            if PGR.statLbls[i] then
                                PGR.statLbls[i].Text = "⚠ Item berganti — GUID diperbarui"
                                PGR.statLbls[i].TextColor3 = Color3.fromRGB(255,200,60)
                            end
                        end
                    end
                end
                SetPetGearGuid(tostring(g), d)
            end
        end
    end

    local function HandleResponse(self, sentArgs, res)
        if self ~= RE_RandomHeroQuirk and self ~= RE_AutoHeroQuirk then return end
        if type(res) ~= "table" then return end
        local slotIdx = nil
        local a = sentArgs[1]
        if type(a) == "table" then
            local d = a.drawId or a.DrawId
            if type(d) == "number" then
                for si, did in ipairs(HR.slotDrawId) do
                    if did == d then slotIdx = si; break end
                end
            end
        end
        local function ScanQuirks(tbl, depth)
            if depth > 5 or type(tbl) ~= "table" then return end
            local id   = tbl.quirkId or tbl.finalResultId or tbl.resultId or tbl.id or tbl.Id
            local name = tbl.quirkName or tbl.name or tbl.Name or tbl.title or tbl.displayName
            if type(id) == "number" and id >= 90000 and id <= 99999
            and type(name) == "string" and #name > 0 and not name:find("^ID:") then
                AddQuirkToSlot(slotIdx or 1, id, name)
            end
            for _, v in pairs(tbl) do
                if type(v) == "table" then ScanQuirks(v, depth+1) end
            end
        end
        ScanQuirks(res, 0)
    end

    local hooked = false

    if not hooked and type(hookmetamethod) == "function" then
        local ok, err = pcall(function()
            local oldNC
            oldNC = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                HandleRequest(self, method, ...)
                if method == "InvokeServer"
                and (self == RE_RandomHeroQuirk or self == RE_AutoHeroQuirk) then
                    local sentArgs = {...}
                    local res = oldNC(self, ...)
                    HandleResponse(self, sentArgs, res)
                    return res
                end
                return oldNC(self, ...)
            end)
        end)
        if ok then hooked = true; warn("[ ASH ] Hook: hookmetamethod OK (Delta/Xeno)")
        else warn("[ ASH ] hookmetamethod gagal: "..tostring(err)) end
    end

    if not hooked and type(getrawmetatable) == "function" and type(setreadonly) == "function" then
        local ok, err = pcall(function()
            local mt = getrawmetatable(game)
            local oldNC = rawget(mt, "__namecall")
            setreadonly(mt, false)
            local newFn = function(self, ...)
                local method = getnamecallmethod()
                HandleRequest(self, method, ...)
                if method == "InvokeServer"
                and (self == RE_RandomHeroQuirk or self == RE_AutoHeroQuirk) then
                    local sentArgs = {...}
                    local ok2, res = pcall(oldNC, self, ...)
                    if ok2 then HandleResponse(self, sentArgs, res) end
                    return res
                end
                return oldNC(self, ...)
            end
            mt.__namecall = (type(newcclosure) == "function") and newcclosure(newFn) or newFn
            setreadonly(mt, true)
        end)
        if ok then hooked = true; warn("[ ASH ] Hook: getrawmetatable OK (fallback)")
        else warn("[ ASH ] getrawmetatable gagal: "..tostring(err)) end
    end

    if hooked then
        _layer0Active = true
        if HR.captureStatusLbl then
            HR.captureStatusLbl.Text = "⟳ Hook aktif — equip weapon / klik ReRoll 1x"
            HR.captureStatusLbl.TextColor3 = Color3.fromRGB(255,200,100)
        end
    else
        warn("[ ASH ] Semua method hook gagal — gunakan scan manual")
        if HR.captureStatusLbl then
            HR.captureStatusLbl.Text = "⚠ Hook gagal — executor tidak support"
            HR.captureStatusLbl.TextColor3 = Color3.fromRGB(255,80,80)
        end
    end
end

local function ScanHeroGuidFromData()
    if HR.captured then return true end
    local GUID_KEYS = {"heroGuid","HeroGuid","hero_guid","HEROGUID","guid","GUID","Guid","heroId","HeroId"}
    local function TryScanInstance(obj)
        if not obj then return end
        pcall(function()
            for k, v in pairs(obj:GetAttributes()) do
                if type(v) == "string" and IsValidUUID(v) then
                    local kl = k:lower()
                    if kl:find("guid") or kl:find("hero") or kl:find("id") then
                        SetHeroGuid(v, "scan:attr:"..obj.Name.."."..k)
                        if HR.captured then return end
                    end
                end
            end
        end)
        pcall(function()
            for _, key in ipairs(GUID_KEYS) do
                local child = obj:FindFirstChild(key)
                if child and child.Value and IsValidUUID(tostring(child.Value)) then
                    SetHeroGuid(tostring(child.Value), "scan:child:"..obj.Name.."."..key)
                    if HR.captured then return end
                end
            end
        end)
    end
    local roots = {
        LP, LP.Character,
        LP:FindFirstChild("leaderstats"), LP:FindFirstChild("PlayerData"),
        RS:FindFirstChild("PlayerData"), RS:FindFirstChild("Data"),
        workspace:FindFirstChild("Players"),
    }
    for _, root in ipairs(roots) do
        if HR.captured then return true end
        if root then
            TryScanInstance(root)
            pcall(function()
                for _, child in ipairs(root:GetChildren()) do
                    if HR.captured then break end; TryScanInstance(child)
                end
            end)
        end
    end
    return HR.captured
end

local function SetupAttributeWatcher()
    if #_watcherConns > 0 then return end
    local WATCH_KEYS = {"heroGuid","HeroGuid","guid","GUID","heroId","HeroId","selectedHero"}
    local function WatchInstance(obj)
        if not obj then return end
        for _, key in ipairs(WATCH_KEYS) do
            pcall(function()
                local conn = obj:GetAttributeChangedSignal(key):Connect(function()
                    if HR.captured then return end
                    local v = obj:GetAttribute(key)
                    if v and IsValidUUID(tostring(v)) then
                        SetHeroGuid(tostring(v), "watcher:"..obj.Name.."."..key)
                    end
                end)
                table.insert(_watcherConns, conn)
            end)
        end
    end
    WatchInstance(LP)
    if LP.Character then WatchInstance(LP.Character) end
    LP.CharacterAdded:Connect(function(char) WatchInstance(char) end)
    table.insert(_watcherConns, RS.DescendantAdded:Connect(function(obj)
        if HR.captured then return end
        pcall(function()
            for k, v in pairs(obj:GetAttributes()) do
                if type(v) == "string" and IsValidUUID(v) then
                    SetHeroGuid(v, "watcher:RS.new:"..obj.Name.."."..k)
                    if HR.captured then return end
                end
            end
        end)
        WatchInstance(obj)
    end))
end

local function InitAllCaptureLayers()
    SetupUniversalSpy()
    task.spawn(function()
        task.wait(0.3)
        if not HR.captured then ScanHeroGuidFromData() end
        task.wait(0.2)
        if not HR.captured then SetupAttributeWatcher() end
        if not HR.captured and HR.captureStatusLbl then
            HR.captureStatusLbl.Text = "⟳ Spy aktif — klik ReRoll 1x di game"
            HR.captureStatusLbl.TextColor3 = Color3.fromRGB(255,200,100)
        end
    end)
    task.spawn(function()
        local attempt = 0
        while not HR.captured do
            task.wait(4); attempt = attempt + 1
            if not HR.captured then
                ScanHeroGuidFromData()
                if attempt >= 5 and not HR.captured and HR.captureStatusLbl then
                    HR.captureStatusLbl.Text = "⚠ Belum ada UUID — pastikan panel ReRoll terbuka"
                    HR.captureStatusLbl.TextColor3 = Color3.fromRGB(255,80,80)
                end
            end
        end
    end)
end

-- ============================================================
-- DROPDOWN HELPER (shared)
-- ============================================================
local function MakeGenericDropdown(params)
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
        local function UpdateCount()
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
    SectionHeader(p, "PENGATURAN CEPAT", 0)
    ToggleRow(p, "Auto Collect + Destroyer", "Aktifkan Auto Collect otomatis saat Destroyer ON", 1,
        function(on)
            if STATE.autoDestroyer then STATE.autoCollect = on; DoAutoCollect(on); RefreshStatus() end
        end)
end)()

-- ============================================================
-- PANEL : FARM
-- ============================================================
local agDot, agTxtLbl, agKLbl, agELbl
local eEnemyRows = {}
local eEnemyNames = {}
local activeEName = nil
local eBtnRefLbl
local FindLiveEnemyByName, SelectEnemyName, RefreshEnemies

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

    local acCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,36))
    acCard.LayoutOrder = 2; Corner(acCard,7); Stroke(acCard,C.BORD,1,0.4)
    Padding(acCard,6,6,10,8)
    local acLbl = Label(acCard,"Auto Collect Gold / Item",11,C.TXT,Enum.Font.GothamBold)
    acLbl.Size = UDim2.new(0.7,0,0,16); acLbl.Position = UDim2.new(0,0,0,2)
    local acSub = Label(acCard,"Destroyer: Aktif",9,C.GRN,Enum.Font.Gotham)
    acSub.Size = UDim2.new(0.7,0,0,13); acSub.Position = UDim2.new(0,0,0,20)
    local acToggle = Btn(acCard,C.NSEL,UDim2.new(0,36,0,20))
    acToggle.AnchorPoint = Vector2.new(1, 0.5)
    acToggle.Position = UDim2.new(1,-10,0.5,0); Corner(acToggle,10)
    local acKnob = Frame(acToggle,C.YEL,UDim2.new(0,14,0,14))
    acKnob.AnchorPoint = Vector2.new(0, 0.5)
    acKnob.Position = UDim2.new(0,3,0.5,0); Corner(acKnob,7)
    local acOn = true
    acToggle.MouseButton1Click:Connect(function()
        acOn = not acOn; AG.autoCollect = acOn
        TweenService:Create(acToggle,TweenInfo.new(0.14),{BackgroundColor3=acOn and C.NSEL or Color3.fromRGB(22,20,18)}):Play()
        TweenService:Create(acKnob,TweenInfo.new(0.14),{
            Position=acOn and UDim2.new(1,-16,0.5,0) or UDim2.new(0,2,0.5,0),
            BackgroundColor3=acOn and C.YEL or C.DK}):Play()
        acSub.Text = acOn and "Destroyer: Aktif" or "Destroyer: Nonaktif"
        acSub.TextColor3 = acOn and C.GRN or C.RED
    end)

    local tgtHdr = Label(p,"Target Musuh (pilih yang mau diserang)",10,C.AG,Enum.Font.GothamBold)
    tgtHdr.Size = UDim2.new(1,0,0,18); tgtHdr.LayoutOrder = 3

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
            btn.MouseButton1Click:Connect(function()
                if activeEName == bnm then SelectEnemyName(nil)
                else SelectEnemyName(bnm) end
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

    local function SetAGUI(on)
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

-- ============================================================
-- PANEL : ATTACK
-- ============================================================
;(function()
    local p = NewPanel("attack")

    local ddBackdrop = Instance.new("TextButton",ScreenGui)
    ddBackdrop.Size=UDim2.new(1,0,1,0); ddBackdrop.Position=UDim2.new(0,0,0,0)
    ddBackdrop.BackgroundTransparency=1; ddBackdrop.Text=""; ddBackdrop.ZIndex=49
    ddBackdrop.AutoButtonColor=false; ddBackdrop.Visible=false
    local _openDDs = {}

    local function OpenDD(list)
        for _, d in ipairs(_openDDs) do d.Visible = false end
        _openDDs = {}; list.Visible = true; table.insert(_openDDs, list); ddBackdrop.Visible = true
    end
    local function CloseAllDD()
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

    local function MakeSimpleDD(card, title, opts, vals, defIdx, onSelect, lo)
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

        local function UpdateMapDDLbl()
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
        local dn,dc=d.n,d.c
        sb.MouseButton1Click:Connect(function()
            if SKL[dn].on then
                SkOff(dn); sb.BackgroundColor3=C.BG3; st.Text="OFF"; st.TextColor3=C.TXT3
            else
                SkOn(dn); sb.BackgroundColor3=Color3.fromRGB(20,10,42); st.Text="ON"; st.TextColor3=dc
            end
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
    local function SetSpeed(relX)
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
        if _antiAfkThread then task.cancel(_antiAfkThread); _antiAfkThread=nil end
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
-- PANEL : AUTO ROLL — HERO
-- ============================================================
;(function()
    local p = NewPanel("autoroll")
    local ddOpen = false

    local ddHeader=Btn(p,C.SURFACE,UDim2.new(1,0,0,38))
    ddHeader.LayoutOrder=0; Corner(ddHeader,8); Stroke(ddHeader,C.BORD,1,0.4)
    local ddIcon=Label(ddHeader,"▶",12,C.ACC2,Enum.Font.GothamBold)
    ddIcon.Size=UDim2.new(0,20,1,0); ddIcon.Position=UDim2.new(0,10,0,0)
    local ddLabel=Label(ddHeader,"⚡  Hero Ability Fastroll",13,C.TXT,Enum.Font.GothamBold)
    ddLabel.Size=UDim2.new(1,-40,1,0); ddLabel.Position=UDim2.new(0,30,0,0)

    local ddBody=Frame(p,C.BG2,UDim2.new(1,0,0,0))
    ddBody.LayoutOrder=1; ddBody.ClipsDescendants=true; Corner(ddBody,8); Stroke(ddBody,C.BORD,1,0.3)
    ddBody.Visible=false
    local ddInner=Frame(ddBody,C.BLACK,UDim2.new(1,-16,0,0))
    ddInner.BackgroundTransparency=1; ddInner.Position=UDim2.new(0,8,0,8)
    local ddLayout=New("UIListLayout",{Parent=ddInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

    local function ResizeDDBody()
        ddLayout:ApplyLayout()
        local h=ddLayout.AbsoluteContentSize.Y+16
        ddInner.Size=UDim2.new(1,0,0,h); ddBody.Size=UDim2.new(1,0,0,h+16)
    end

    local weaponCard=Frame(ddInner,C.SURFACE,UDim2.new(1,0,0,0))
    weaponCard.AutomaticSize=Enum.AutomaticSize.Y
    weaponCard.LayoutOrder=0; Corner(weaponCard,8); Stroke(weaponCard,C.BORD,1,0.4)
    local wcPad=Instance.new("UIPadding",weaponCard)
    wcPad.PaddingTop=UDim.new(0,8); wcPad.PaddingBottom=UDim.new(0,8)
    wcPad.PaddingLeft=UDim.new(0,12); wcPad.PaddingRight=UDim.new(0,8)
    local wcLayout=Instance.new("UIListLayout",weaponCard)
    wcLayout.SortOrder=Enum.SortOrder.LayoutOrder; wcLayout.Padding=UDim.new(0,4)
    local wsTitle=Label(weaponCard,"Hero Status",12,C.TXT,Enum.Font.GothamBold)
    wsTitle.Size=UDim2.new(1,0,0,16); wsTitle.LayoutOrder=0
    wsTitle.TextYAlignment=Enum.TextYAlignment.Center
    local wsSlot1=Label(weaponCard,"Slot 1: —",10.5,C.TXT2,Enum.Font.Gotham)
    wsSlot1.Size=UDim2.new(1,0,0,14); wsSlot1.LayoutOrder=1
    wsSlot1.TextYAlignment=Enum.TextYAlignment.Center
    local wsSlot2=Label(weaponCard,"Slot 2: —",10.5,C.TXT2,Enum.Font.Gotham)
    wsSlot2.Size=UDim2.new(1,0,0,14); wsSlot2.LayoutOrder=2
    wsSlot2.TextYAlignment=Enum.TextYAlignment.Center
    local wsSlot3=Label(weaponCard,"Slot 3: —",10.5,C.TXT2,Enum.Font.Gotham)
    wsSlot3.Size=UDim2.new(1,0,0,14); wsSlot3.LayoutOrder=3
    wsSlot3.TextYAlignment=Enum.TextYAlignment.Center
    HR.weaponSlotLbls={wsSlot1,wsSlot2,wsSlot3}
    HR.slotStatusLbl={wsSlot1,wsSlot2,wsSlot3}

    local statusCard=Frame(ddInner,C.SURFACE,UDim2.new(1,0,0,44))
    statusCard.LayoutOrder=1; Corner(statusCard,8); Stroke(statusCard,C.BORD,1,0.4); Padding(statusCard,6,6,12,8)
    local arTitle=Label(statusCard,"AutoReroll Status",12,C.TXT,Enum.Font.GothamBold)
    arTitle.Size=UDim2.new(1,0,0,16); arTitle.Position=UDim2.new(0,0,0,4)
    local arDot=Frame(statusCard,Color3.fromRGB(100,100,100),UDim2.new(0,7,0,7))
    arDot.Position=UDim2.new(0,0,0,25); Corner(arDot,4)
    HR.dotRef=arDot
    local arStatusLbl=Label(statusCard,"Idle",10.5,C.TXT2,Enum.Font.Gotham)
    arStatusLbl.Size=UDim2.new(1,-12,0,13); arStatusLbl.Position=UDim2.new(0,12,0,24)
    arStatusLbl.TextWrapped=true
    HR.statusLbl=arStatusLbl

    for si=1,3 do
        local si_l=si
        local slotRow=Frame(ddInner,C.SURFACE,UDim2.new(1,0,0,40))
        slotRow.LayoutOrder=si+1; Corner(slotRow,8); Stroke(slotRow,C.BORD,1,0.4)
        local slotLbl=Label(slotRow,"Target Slot "..si,12,C.TXT,Enum.Font.GothamBold)
        slotLbl.Size=UDim2.new(0,90,0,18); slotLbl.Position=UDim2.new(0,12,0,4)
        local slotSub=Label(slotRow,"(max "..MAX_PER_SLOT..")",9.5,C.TXT3,Enum.Font.Gotham)
        slotSub.Size=UDim2.new(0,90,0,12); slotSub.Position=UDim2.new(0,12,0,22)
        local ddBtn=Btn(slotRow,C.DD_BG,UDim2.new(0.52,0,0,28))
        ddBtn.Position=UDim2.new(0.46,0,0.5,-14); Corner(ddBtn,6); Stroke(ddBtn,C.BORD2,1,0.3)
        local ddLbl=Label(ddBtn,"--",10.5,C.TXT2,Enum.Font.Gotham,Enum.TextXAlignment.Left)
        ddLbl.Size=UDim2.new(1,-20,1,0); ddLbl.Position=UDim2.new(0,7,0,0); ddLbl.TextTruncate=Enum.TextTruncate.AtEnd
        HR.slotSummaryLbls[si]=ddLbl
        local arr=Label(ddBtn,"▼",10,C.ACC,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        arr.Size=UDim2.new(0,16,1,0); arr.Position=UDim2.new(1,-18,0,0)
        MakeGenericDropdown({
            ddBtn=ddBtn, list=QUIRK_LIST_PER_SLOT[si], maxSel=MAX_PER_SLOT,
            selTable=HR.slotTarget[si],
            onRefresh=function() RefreshSlotUI(si_l) end,
            summaryLbl=ddLbl,
        })
    end

    local enRow=Frame(ddInner,C.SURFACE,UDim2.new(1,0,0,44))
    enRow.LayoutOrder=5; Corner(enRow,8); Stroke(enRow,C.BORD,1,0.4)
    local enLbl=Label(enRow,"Enable AutoReroll",12,C.TXT,Enum.Font.GothamBold)
    enLbl.Size=UDim2.new(0.7,0,0,18); enLbl.Position=UDim2.new(0,12,0,6)
    local enSub=Label(enRow,"Aktifkan auto reroll semua slot",10,C.TXT3,Enum.Font.Gotham)
    enSub.Size=UDim2.new(0.85,0,0,13); enSub.Position=UDim2.new(0,12,0,24)
    local enToggle=Btn(enRow,Color3.fromRGB(60,60,60),UDim2.new(0,36,0,20))
    enToggle.Position=UDim2.new(1,-48,0.5,-10); Corner(enToggle,10)
    local enKnob=Frame(enToggle,C.TXT,UDim2.new(0,16,0,16)); enKnob.Position=UDim2.new(0,2,0.5,-8); Corner(enKnob,8)
    local enOn=false
    enToggle.MouseButton1Click:Connect(function()
        enOn=not enOn; STATE.autoRoll=enOn
        enToggle.BackgroundColor3=enOn and C.ACC or Color3.fromRGB(60,60,60)
        enKnob.Position=enOn and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
        DoAutoRoll(enOn)
        for i=1,3 do RefreshSlotUI(i) end
        RefreshStatus()
    end)

    ddHeader.MouseButton1Click:Connect(function()
        ddOpen=not ddOpen; ddBody.Visible=ddOpen; ddIcon.Text=ddOpen and "▼" or "▶"
        if ddOpen then task.defer(ResizeDDBody) end
    end)
end)()

-- ============================================================
-- PANEL : AUTO ROLL — WEAPON
-- ============================================================
;(function()
    local p = Panels["autoroll"]
    local wddOpen = false

    local wddHeader=Btn(p,C.SURFACE,UDim2.new(1,0,0,38))
    wddHeader.LayoutOrder=10; Corner(wddHeader,8); Stroke(wddHeader,C.BORD,1,0.4)
    local wddIcon=Label(wddHeader,"▶",12,C.ACC2,Enum.Font.GothamBold)
    wddIcon.Size=UDim2.new(0,20,1,0); wddIcon.Position=UDim2.new(0,10,0,0)
    local wddLabel=Label(wddHeader,"⚔  Weapon Ability Fastroll",13,C.TXT,Enum.Font.GothamBold)
    wddLabel.Size=UDim2.new(1,-40,1,0); wddLabel.Position=UDim2.new(0,30,0,0)

    local wddBody=Frame(p,C.BG2,UDim2.new(1,0,0,0))
    wddBody.LayoutOrder=11; wddBody.ClipsDescendants=true; Corner(wddBody,8); Stroke(wddBody,C.BORD,1,0.3)
    wddBody.Visible=false
    local wddInner=Frame(wddBody,C.BLACK,UDim2.new(1,-16,0,0))
    wddInner.BackgroundTransparency=1; wddInner.Position=UDim2.new(0,8,0,8)
    local wddLayout=New("UIListLayout",{Parent=wddInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

    local function ResizeWDDBody()
        wddLayout:ApplyLayout()
        local h=wddLayout.AbsoluteContentSize.Y+16
        wddInner.Size=UDim2.new(1,0,0,h); wddBody.Size=UDim2.new(1,0,0,h+16)
    end

    local wStatusCard=Frame(wddInner,C.SURFACE,UDim2.new(1,0,0,0))
    wStatusCard.AutomaticSize=Enum.AutomaticSize.Y
    wStatusCard.LayoutOrder=0; Corner(wStatusCard,8); Stroke(wStatusCard,C.BORD,1,0.4)
    local wscPad=Instance.new("UIPadding",wStatusCard)
    wscPad.PaddingTop=UDim.new(0,8); wscPad.PaddingBottom=UDim.new(0,8)
    wscPad.PaddingLeft=UDim.new(0,12); wscPad.PaddingRight=UDim.new(0,8)
    local wscLayout=Instance.new("UIListLayout",wStatusCard)
    wscLayout.SortOrder=Enum.SortOrder.LayoutOrder; wscLayout.Padding=UDim.new(0,4)
    local wstTitle=Label(wStatusCard,"Weapon Status",12,C.TXT,Enum.Font.GothamBold)
    wstTitle.Size=UDim2.new(1,0,0,16); wstTitle.LayoutOrder=0
    wstTitle.TextYAlignment=Enum.TextYAlignment.Center
    local wstSlot1=Label(wStatusCard,"Slot 1: —",10.5,C.TXT2,Enum.Font.Gotham)
    wstSlot1.Size=UDim2.new(1,0,0,14); wstSlot1.LayoutOrder=1
    wstSlot1.TextYAlignment=Enum.TextYAlignment.Center
    local wstSlot2=Label(wStatusCard,"Slot 2: —",10.5,C.TXT2,Enum.Font.Gotham)
    wstSlot2.Size=UDim2.new(1,0,0,14); wstSlot2.LayoutOrder=2
    wstSlot2.TextYAlignment=Enum.TextYAlignment.Center
    local wstSlot3=Label(wStatusCard,"Slot 3: —",10.5,C.TXT2,Enum.Font.Gotham)
    wstSlot3.Size=UDim2.new(1,0,0,14); wstSlot3.LayoutOrder=3
    wstSlot3.TextYAlignment=Enum.TextYAlignment.Center
    WR.weaponSlotLbls={wstSlot1,wstSlot2,wstSlot3}

    local wArCard=Frame(wddInner,C.SURFACE,UDim2.new(1,0,0,44))
    wArCard.LayoutOrder=1; Corner(wArCard,8); Stroke(wArCard,C.BORD,1,0.4); Padding(wArCard,6,6,12,8)
    local wArTitle=Label(wArCard,"AutoReroll Status",12,C.TXT,Enum.Font.GothamBold)
    wArTitle.Size=UDim2.new(1,0,0,16); wArTitle.Position=UDim2.new(0,0,0,4)
    local wArDot=Frame(wArCard,Color3.fromRGB(100,100,100),UDim2.new(0,7,0,7))
    wArDot.Position=UDim2.new(0,0,0,25); Corner(wArDot,4)
    WR.dotRef=wArDot
    local wArStatusLbl=Label(wArCard,"Idle",10.5,C.TXT2,Enum.Font.Gotham)
    wArStatusLbl.Size=UDim2.new(1,-12,0,13); wArStatusLbl.Position=UDim2.new(0,12,0,24)
    wArStatusLbl.TextWrapped=true
    WR.statusLbl=wArStatusLbl

    for wsi=1,3 do
        local wsi_l=wsi
        local wSlotRow=Frame(wddInner,C.SURFACE,UDim2.new(1,0,0,40))
        wSlotRow.LayoutOrder=wsi+1; Corner(wSlotRow,8); Stroke(wSlotRow,C.BORD,1,0.4)
        local wSlotLbl=Label(wSlotRow,"Target Slot "..wsi,12,C.TXT,Enum.Font.GothamBold)
        wSlotLbl.Size=UDim2.new(0,90,0,18); wSlotLbl.Position=UDim2.new(0,12,0,4)
        local wSlotSub=Label(wSlotRow,"(max "..W_MAX_PER_SLOT..")",9.5,C.TXT3,Enum.Font.Gotham)
        wSlotSub.Size=UDim2.new(0,90,0,12); wSlotSub.Position=UDim2.new(0,12,0,22)
        local wDdBtn=Btn(wSlotRow,C.DD_BG,UDim2.new(0.52,0,0,28))
        wDdBtn.Position=UDim2.new(0.46,0,0.5,-14); Corner(wDdBtn,6); Stroke(wDdBtn,C.BORD2,1,0.3)
        local wDdLbl=Label(wDdBtn,"--",10.5,C.TXT2,Enum.Font.Gotham,Enum.TextXAlignment.Left)
        wDdLbl.Size=UDim2.new(1,-20,1,0); wDdLbl.Position=UDim2.new(0,7,0,0); wDdLbl.TextTruncate=Enum.TextTruncate.AtEnd
        WR.slotSummaryLbls[wsi]=wDdLbl
        local wArrow=Label(wDdBtn,"▼",10,C.ACC,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        wArrow.Size=UDim2.new(0,16,1,0); wArrow.Position=UDim2.new(1,-18,0,0)
        MakeGenericDropdown({
            ddBtn=wDdBtn, list=W_QUIRK_LIST_PER_SLOT[wsi], maxSel=W_MAX_PER_SLOT,
            selTable=WR.slotTarget[wsi],
            onRefresh=function() RefreshWeaponSlotUI(wsi_l) end,
            summaryLbl=wDdLbl,
        })
    end

    local wEnRow=Frame(wddInner,C.SURFACE,UDim2.new(1,0,0,44))
    wEnRow.LayoutOrder=5; Corner(wEnRow,8); Stroke(wEnRow,C.BORD,1,0.4)
    local wEnLbl=Label(wEnRow,"Enable AutoReroll",12,C.TXT,Enum.Font.GothamBold)
    wEnLbl.Size=UDim2.new(0.7,0,0,18); wEnLbl.Position=UDim2.new(0,12,0,6)
    local wEnSub=Label(wEnRow,"Aktifkan auto reroll weapon",10,C.TXT3,Enum.Font.Gotham)
    wEnSub.Size=UDim2.new(0.85,0,0,13); wEnSub.Position=UDim2.new(0,12,0,24)
    local wEnToggle=Btn(wEnRow,Color3.fromRGB(60,60,60),UDim2.new(0,36,0,20))
    wEnToggle.Position=UDim2.new(1,-48,0.5,-10); Corner(wEnToggle,10)
    local wEnKnob=Frame(wEnToggle,C.TXT,UDim2.new(0,16,0,16)); wEnKnob.Position=UDim2.new(0,2,0.5,-8); Corner(wEnKnob,8)
    local wEnOn=false
    wEnToggle.MouseButton1Click:Connect(function()
        wEnOn=not wEnOn; WR.running=wEnOn
        wEnToggle.BackgroundColor3=wEnOn and C.ACC or Color3.fromRGB(60,60,60)
        wEnKnob.Position=wEnOn and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
        DoAutoRollWeapon(wEnOn)
        for i=1,3 do RefreshWeaponSlotUI(i) end
    end)

    wddHeader.MouseButton1Click:Connect(function()
        wddOpen=not wddOpen; wddBody.Visible=wddOpen; wddIcon.Text=wddOpen and "▼" or "▶"
        if wddOpen then task.defer(ResizeWDDBody) end
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

    local function ResizePGBody()
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

        local function onTargetChange()
            RefreshPGSummary(msi_l)
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

    local function ResizeHaloBody()
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
-- PANEL : CATATAN AUTO REROLL
-- ============================================================
;(function()
    local p = Panels["autoroll"]
    local noteOpen   = false
    local noteHeader = Btn(p, Color3.fromRGB(50,20,5), UDim2.new(1,0,0,38))
    noteHeader.LayoutOrder = 40; Corner(noteHeader,8); Stroke(noteHeader,C.ACC,1,0.5)
    local noteIcon  = Label(noteHeader,"▶",12,C.ACC2,Enum.Font.GothamBold)
    noteIcon.Size   = UDim2.new(0,20,1,0); noteIcon.Position = UDim2.new(0,10,0,0)
    local noteLabel = Label(noteHeader,"📋  Catatan Penting — Cara Pakai AutoReroll",13,Color3.fromRGB(255,200,80),Enum.Font.GothamBold)
    noteLabel.Size  = UDim2.new(1,-40,1,0); noteLabel.Position = UDim2.new(0,30,0,0)

    local noteBody  = Frame(p, Color3.fromRGB(25,12,3), UDim2.new(1,0,0,0))
    noteBody.LayoutOrder = 41; noteBody.ClipsDescendants = true
    Corner(noteBody,8); Stroke(noteBody,C.ACC,1,0.4); noteBody.Visible = false

    local noteInner = Frame(noteBody, C.BLACK, UDim2.new(1,-16,0,0))
    noteInner.BackgroundTransparency = 1; noteInner.Position = UDim2.new(0,8,0,10)
    local noteLayout = New("UIListLayout",{Parent=noteInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,10)})

    local function ResizeNoteBody()
        noteLayout:ApplyLayout()
        local h = noteLayout.AbsoluteContentSize.Y + 20
        noteInner.Size = UDim2.new(1,0,0,h); noteBody.Size = UDim2.new(1,0,0,h+20)
    end

    local function NoteBlock(order, icon, title, titleColor, lines)
        local block = Frame(noteInner, Color3.fromRGB(35,18,5), UDim2.new(1,0,0,0))
        block.LayoutOrder = order; block.AutomaticSize = Enum.AutomaticSize.Y
        Corner(block,8); Stroke(block,Color3.fromRGB(180,80,0),1,0.5)
        local bPad = Instance.new("UIPadding",block)
        bPad.PaddingLeft=UDim.new(0,10); bPad.PaddingRight=UDim.new(0,10)
        bPad.PaddingTop=UDim.new(0,8);   bPad.PaddingBottom=UDim.new(0,8)
        local bLayout = New("UIListLayout",{Parent=block,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,5)})
        local titleLbl = Label(block,icon.."  "..title,11.5,titleColor,Enum.Font.GothamBold)
        titleLbl.Size = UDim2.new(1,0,0,0); titleLbl.AutomaticSize = Enum.AutomaticSize.Y
        titleLbl.TextWrapped = true; titleLbl.LayoutOrder = 0
        for i, line in ipairs(lines) do
            local lbl = Label(block,line,10.5,Color3.fromRGB(230,210,180),Enum.Font.Gotham)
            lbl.Size = UDim2.new(1,0,0,0); lbl.AutomaticSize = Enum.AutomaticSize.Y
            lbl.TextWrapped = true; lbl.LayoutOrder = i; lbl.TextXAlignment = Enum.TextXAlignment.Left
        end
        return block
    end

    NoteBlock(1,"⚡","Auto Roll Hero",Color3.fromRGB(255,200,60),{
        "1.  Masuk ke Mesin Roll Hero.",
        "2.  Masukkan Hero yang ingin di-reroll.",
        "3.  Klik Reroll 1x secara manual.",
        "4.  Tunggu status berubah HIJAU (GUID terdeteksi).",
        "5.  Pilih target Quirk di slot yang diinginkan.",
        "6.  Aktifkan toggle AutoReroll → script jalan otomatis.",
    })
    NoteBlock(2,"⚔️","Auto Roll Weapon",Color3.fromRGB(180,220,255),{
        "1.  Equip dulu senjata yang ingin di-reroll.",
        "2.  Tunggu status berubah HIJAU (GUID terbaca).",
        "3.  Pilih target Quirk di setiap slot.",
        "4.  Aktifkan toggle AutoReroll → script jalan otomatis.",
    })
    NoteBlock(3,"🐾","Auto Roll Pet Gear",Color3.fromRGB(180,255,180),{
        "1.  Masuk ke Mesin Roll Pet Gear (R / Y / B).",
        "2.  Pilih Pet Gear yang ingin di-reroll.",
        "3.  Klik Reroll 1x secara manual.",
        "4.  Tunggu status berubah HIJAU (GUID terdeteksi).",
        "5.  Pilih target Grade di dropdown.",
        "6.  Aktifkan toggle Fastroll.",
        "⚠  Ingin jalankan 3 mesin sekaligus?",
        "    → Datangi setiap mesin satu per satu,",
        "       lakukan langkah 1–5 di tiap mesin,",
        "       lalu aktifkan semua toggle.",
    })

    local noteBlock = Frame(noteInner, Color3.fromRGB(60,10,10), UDim2.new(1,0,0,0))
    noteBlock.LayoutOrder = 4; noteBlock.AutomaticSize = Enum.AutomaticSize.Y
    Corner(noteBlock,8); Stroke(noteBlock,Color3.fromRGB(255,60,60),1,0.4)
    local nbPad = Instance.new("UIPadding",noteBlock)
    nbPad.PaddingLeft=UDim.new(0,10); nbPad.PaddingRight=UDim.new(0,10)
    nbPad.PaddingTop=UDim.new(0,8);   nbPad.PaddingBottom=UDim.new(0,8)
    New("UIListLayout",{Parent=noteBlock,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})
    local noteTitleLbl = Label(noteBlock,"⚠  PENTING",12,Color3.fromRGB(255,80,80),Enum.Font.GothamBold)
    noteTitleLbl.Size = UDim2.new(1,0,0,18); noteTitleLbl.LayoutOrder = 0
    local noteTextLbl = Label(noteBlock,
        "Jika target sudah tercapai, keluar dari game\n"..
        "lalu masuk kembali untuk melihat hasil\n"..
        "AutoReroll yang sudah kamu dapatkan.",
        10.5,Color3.fromRGB(255,180,180),Enum.Font.GothamBold)
    noteTextLbl.Size = UDim2.new(1,0,0,0); noteTextLbl.AutomaticSize = Enum.AutomaticSize.Y
    noteTextLbl.TextWrapped = true; noteTextLbl.LayoutOrder = 1
    noteTextLbl.TextXAlignment = Enum.TextXAlignment.Left

    noteHeader.MouseButton1Click:Connect(function()
        noteOpen = not noteOpen
        noteBody.Visible = noteOpen
        noteIcon.Text = noteOpen and "▼" or "▶"
        if noteOpen then task.defer(ResizeNoteBody) end
    end)
end)()


-- ============================================================
-- AUTO RAID : LOGIC (SimpleSpy verified)
-- ============================================================
-- ============================================================
-- RAID LIVE LIST — listen UpdateRaidInfo dari server
-- RE1001 = rank rendah, RE1002 = rank tinggi (dari data SimpleSpy)
-- ============================================================
local RAID_LIVE   = {}   -- semua raid aktif: [raidId] = {raidId, mapId, spawnName, rank, endTime, label}
local RAID_ID_LIST = {}  -- list terurut untuk UI
local _raidIdRefreshCb = nil

-- Mapping spawnName → rank number (untuk sorting Easy/Medium/Hard)
local SPAWN_RANK = {
    RE1001 = 1,
    RE1002 = 2,
    RE1003 = 3,
    RE1004 = 4,
    RE1005 = 5,
}

local RANK_LABEL = {
    [1] = "★ Rank 1",
    [2] = "★★ Rank 2",
    [3] = "★★★ Rank 3",
    [4] = "★★★★ Rank 4",
    [5] = "★★★★★ Rank 5",
}

local function RebuildRaidList()
    -- Sort berdasarkan rank (spawnName)
    local sorted = {}
    for _, entry in pairs(RAID_LIVE) do
        table.insert(sorted, entry)
    end
    table.sort(sorted, function(a, b)
        return (a.rank or 99) < (b.rank or 99)
    end)

    RAID_ID_LIST = {}
    for _, e in ipairs(sorted) do
        table.insert(RAID_ID_LIST, {
            label     = (RANK_LABEL[e.rank] or e.spawnName).." — Map "..(e.mapId-50000).." (ID:"..e.raidId..")",
            id        = e.raidId,
            rank      = e.rank,
            mapId     = e.mapId,
            spawnName = e.spawnName,
        })
    end

    if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end
end

-- Listen UpdateRaidInfo dari server
local function StartRaidNotifListener()
    if not RE_UpdateRaidInfo then
        warn("[ ASH RAID ] UpdateRaidInfo remote tidak ditemukan!")
        return
    end

    RE_UpdateRaidInfo.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local action    = data.action
        local raidInfos = data.raidInfos

        if type(raidInfos) ~= "table" then return end

        if action == "AddRaidEnters" or action == nil then
            -- Tambah raid baru ke list
            for raidId, info in pairs(raidInfos) do
                if type(info) == "table" then
                    local spawnName = info.spawnName or "RE1001"
                    local rank      = SPAWN_RANK[spawnName] or 1
                    RAID_LIVE[raidId] = {
                        raidId    = tonumber(raidId) or raidId,
                        mapId     = info.mapId,
                        spawnName = spawnName,
                        rank      = rank,
                        endTime   = info.endTime,
                        label     = (RANK_LABEL[rank] or spawnName).." Map "..(info.mapId and (info.mapId-50000) or "?"),
                    }
                end
            end

        elseif action == "RemoveRaidEnters" then
            -- Hapus raid yang sudah selesai/expired
            for raidId in pairs(raidInfos) do
                RAID_LIVE[raidId] = nil
            end
        end

        RebuildRaidList()
    end)

    warn("[ ASH RAID ] ✅ Listening UpdateRaidInfo — menunggu notifikasi raid...")
end

-- Panggil saat init
StartRaidNotifListener()

-- FetchRaidIds: ambil raid yang ada di map sekarang via GetRaidTeamInfos
local function FetchRaidIds()
    if not RE_GetRaidTeamInfos then return RAID_ID_LIST end
    local ok, result = pcall(function()
        return RE_GetRaidTeamInfos:InvokeServer()
    end)
    if ok and type(result) == "table" then
        for _, info in pairs(result) do
            if type(info) == "table" and info.raidId then
                local spawnName = info.spawnName or "RE1001"
                local rank      = SPAWN_RANK[spawnName] or 1
                RAID_LIVE[info.raidId] = {
                    raidId    = info.raidId,
                    mapId     = info.mapId,
                    spawnName = spawnName,
                    rank      = rank,
                    endTime   = info.endTime,
                    label     = (RANK_LABEL[rank] or spawnName).." Map "..(info.mapId and (info.mapId-50000) or "?"),
                }
            end
        end
        RebuildRaidList()
    end
    return RAID_ID_LIST
end



local function StopRaid()
    RAID.running = false
    if RAID.thread then
        pcall(function() task.cancel(RAID.thread) end)
        RAID.thread = nil
    end
end

local function RaidStatusUpdate(msg, color)
    if RAID.statusLbl then
        RAID.statusLbl.Text = msg
        RAID.statusLbl.TextColor3 = color or Color3.fromRGB(255,210,160)
    end
    if RAID.dot then
        RAID.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100)
    end
end

local function RaidCounterUpdate()
    if RAID.killLbl then RAID.killLbl.Text = "Kill: "..RAID.killed end
    if RAID.loopLbl then RAID.loopLbl.Text = "Loop: "..RAID.loopCount end
end

-- Collect semua item di workspace
local function RaidCollectAll()
    local golds = workspace:FindFirstChild("Golds")
    if golds then
        for _, obj in ipairs(golds:GetChildren()) do
            local guid = obj:GetAttribute("GUID")
            if guid then
                RAID.collected = RAID.collected + 1
                pcall(function() RE_CollectItem:InvokeServer(guid) end)
                task.wait(0.05)
            end
        end
    end
end

-- Scan workspace secara menyeluruh untuk enemy/boss raid
-- Boss raid bisa ada di folder berbeda (Enemys, Bosses, RaidEnemys, dll)
local RAID_ENEMY_FOLDERS = {
    "Enemys","Enemy","Enemies",
    "Bosses","Boss","RaidBoss","RaidBosses",
    "RaidEnemy","RaidEnemys","RaidEnemies",
    "Monsters","Monster",
}

local function GetRaidEnemies()
    local list = {}

    -- Cara 1: Cari di folder-folder yang diketahui
    for _, fname in ipairs(RAID_ENEMY_FOLDERS) do
        local folder = workspace:FindFirstChild(fname)
        if folder then
            for _, e in ipairs(folder:GetChildren()) do
                if e:IsA("Model") then
                    local g   = e:GetAttribute("EnemyGuid")
                              or e:GetAttribute("BossGuid")
                              or e:GetAttribute("Guid")
                              or e:GetAttribute("guid")
                              or e:GetAttribute("GUID")
                    local hrp = e:FindFirstChild("HumanoidRootPart")
                    local hum = e:FindFirstChildOfClass("Humanoid")
                    if g and hrp and hum and hum.Health > 0 then
                        table.insert(list, {guid=g, hrp=hrp, model=e})
                    end
                end
            end
        end
    end

    -- Cara 2: Kalau masih kosong, deep-scan seluruh workspace (lebih lambat tapi pasti ketemu)
    if #list == 0 then
        local function DeepScan(parent, depth)
            if depth > 4 then return end
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Model") then
                    local g   = child:GetAttribute("EnemyGuid")
                              or child:GetAttribute("BossGuid")
                              or child:GetAttribute("Guid")
                              or child:GetAttribute("guid")
                              or child:GetAttribute("GUID")
                    local hrp = child:FindFirstChild("HumanoidRootPart")
                    local hum = child:FindFirstChildOfClass("Humanoid")
                    if g and hrp and hum and hum.Health > 0 then
                        table.insert(list, {guid=g, hrp=hrp, model=child})
                    end
                end
                DeepScan(child, depth + 1)
            end
        end
        pcall(function() DeepScan(workspace, 0) end)
    end

    -- Cara 3: Kalau masih kosong, coba pakai Guid dari nama model
    -- (beberapa game simpan guid sebagai nama model)
    if #list == 0 then
        for _, desc in ipairs(workspace:GetDescendants()) do
            if desc:IsA("Model") then
                local hum = desc:FindFirstChildOfClass("Humanoid")
                local hrp = desc:FindFirstChild("HumanoidRootPart")
                if hum and hum.Health > 0 and hrp then
                    -- Cek apakah nama model format UUID
                    if desc.Name:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
                        table.insert(list, {guid=desc.Name, hrp=hrp, model=desc})
                    end
                end
            end
        end
    end

    return list
end

-- Serang semua enemy/boss raid
local function RaidAttackAll()
    local enemies = GetRaidEnemies()
    local count   = #enemies
    for _, e in ipairs(enemies) do
        local g = e.guid
        local p = e.hrp.Position
        -- ClickEnemy
        if RE_Click then
            pcall(function() RE_Click:InvokeServer({enemyGuid=g, enemyPos=p}) end)
        end
        -- PlayerClickAttackSkill
        if RE_Atk then
            pcall(function() RE_Atk:FireServer({attackEnemyGUID=g}) end)
            pcall(function() RE_Atk:FireServer(g) end)
        end
        -- Hero skills
        for _, hGuid in ipairs(HERO_GUIDS) do
            if RE_HeroSkill then
                for sk = 1, 3 do
                    pcall(function()
                        RE_HeroSkill:FireServer({
                            heroGuid  = hGuid,
                            enemyGuid = g,
                            skillType = sk,
                            masterId  = MY_USER_ID,
                        })
                    end)
                end
            end
            if RE_HeroMove then
                pcall(function()
                    RE_HeroMove:FireServer({
                        attackTarget      = g,
                        userId            = MY_USER_ID,
                        heroTagetPosInfos = {[hGuid]=p+Vector3.new(2,0,2)},
                    })
                end)
            end
            if RE_HeroStand then
                pcall(function()
                    RE_HeroStand:FireServer({
                        masterId = MY_USER_ID,
                        cframe   = CFrame.new(p + Vector3.new(2,0,2)),
                        guid     = hGuid,
                    })
                end)
            end
        end
        -- Teleport karakter ke dekat boss
        local char = LP.Character
        if char then
            local hrp2 = char:FindFirstChild("HumanoidRootPart")
            if hrp2 then
                pcall(function() hrp2.CFrame = CFrame.new(p + Vector3.new(0,2,3)) end)
            end
        end
    end
    return count
end

-- Hitung enemy/boss raid yang masih hidup
local function CountAliveEnemies()
    local enemies = GetRaidEnemies()
    return #enemies
end

-- Main loop raid
local function StartRaidLoop()
    StopRaid()
    RAID.running   = true
    RAID.killed    = 0
    RAID.collected = 0
    RAID.loopCount = 0
    RaidStatusUpdate("⚡ Memulai Auto Raid...", Color3.fromRGB(255,200,60))

    RAID.thread = task.spawn(function()
        while RAID.running do

            -- ── STEP 1 : Cek Info Team Raid ──
            RaidStatusUpdate("🔍 Mengecek info team raid...", Color3.fromRGB(100,200,255))
            if RE_GetRaidTeamInfos then
                pcall(function() RE_GetRaidTeamInfos:InvokeServer() end)
            end
            task.wait(0.5)
            if not RAID.running then break end

            -- ── STEP 2 : Buat Team Raid ──
            RaidStatusUpdate("👥 Membuat team raid (ID: "..RAID.raidId..")...", Color3.fromRGB(100,200,255))
            if RE_CreateRaidTeam then
                pcall(function() RE_CreateRaidTeam:InvokeServer(RAID.raidId) end)
            end
            task.wait(1)
            if not RAID.running then break end

            -- ── STEP 3 : Start Challenge Raid Map ──
            RaidStatusUpdate("🗺 Memulai challenge raid map...", Color3.fromRGB(255,180,60))
            if RE_StartChallengeRaidMap then
                pcall(function() RE_StartChallengeRaidMap:FireServer() end)
            end
            task.wait(0.5)
            if not RAID.running then break end

            -- ── STEP 4 : Teleport ke Map Raid ──
            RaidStatusUpdate("🌀 Teleport ke map raid...", Color3.fromRGB(180,100,255))
            if RE_RaidStartTp then
                pcall(function()
                    RE_RaidStartTp:FireServer({
                        hostId = MY_USER_ID,
                        mapId  = 50302,
                    })
                end)
            end
            -- Tunggu sesuai joinDelay
            local d = 0
            while d < RAID.joinDelay and RAID.running do
                task.wait(0.2); d = d + 0.2
            end
            if not RAID.running then break end

            -- ── STEP 5 : Equip Hero + Konfirmasi Teleport ──
            if RE_EquipHeroWithData then
                pcall(function() RE_EquipHeroWithData:FireServer() end)
            end
            if RE_LocalTpSuccess then
                pcall(function() RE_LocalTpSuccess:InvokeServer() end)
            end
            task.wait(0.5)
            if not RAID.running then break end

            -- ── STEP 6 : Auto Attack Loop ──
            if RAID.autoAttack then

                -- Tunggu boss spawn dulu (max 15 detik)
                RaidStatusUpdate("⏳ Menunggu boss spawn...", Color3.fromRGB(255,200,60))
                local spawnWait = 0
                while RAID.running and spawnWait < 15 do
                    if CountAliveEnemies() > 0 then break end
                    task.wait(0.3); spawnWait = spawnWait + 0.3
                end

                if CountAliveEnemies() == 0 then
                    RaidStatusUpdate("⚠ Boss tidak ditemukan di workspace, lanjut...", Color3.fromRGB(255,150,50))
                    task.wait(1)
                else
                    -- Boss ketemu, mulai serang
                    local atkT   = 0
                    local emptyT = 0
                    local lastAlive = CountAliveEnemies()

                    while RAID.running do
                        local enemies = GetRaidEnemies()
                        local alive   = #enemies

                        if alive == 0 then
                            emptyT = emptyT + 0.15
                            if emptyT >= 2.5 then
                                RAID.killed = RAID.killed + 1
                                RaidCounterUpdate()
                                RaidStatusUpdate("💀 Boss mati! Kill: "..RAID.killed, Color3.fromRGB(100,255,150))
                                task.wait(0.5)
                                break
                            end
                        else
                            emptyT = 0
                            -- Serang setiap enemy yang ketemu
                            for _, e in ipairs(enemies) do
                                local g = e.guid
                                local p = e.hrp.Position
                                -- ClickEnemy
                                if RE_Click then
                                    pcall(function() RE_Click:InvokeServer({enemyGuid=g, enemyPos=p}) end)
                                end
                                -- RE_Atk
                                if RE_Atk then
                                    pcall(function() RE_Atk:FireServer({attackEnemyGUID=g}) end)
                                    pcall(function() RE_Atk:FireServer(g) end)
                                end
                                -- Hero skills + move
                                for _, hGuid in ipairs(HERO_GUIDS) do
                                    if RE_HeroSkill then
                                        for sk = 1, 3 do
                                            pcall(function()
                                                RE_HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=sk,masterId=MY_USER_ID})
                                            end)
                                        end
                                    end
                                    if RE_HeroMove then
                                        pcall(function()
                                            RE_HeroMove:FireServer({
                                                attackTarget=g, userId=MY_USER_ID,
                                                heroTagetPosInfos={[hGuid]=p+Vector3.new(2,0,2)},
                                            })
                                        end)
                                    end
                                    if RE_HeroStand then
                                        pcall(function()
                                            RE_HeroStand:FireServer({masterId=MY_USER_ID,cframe=CFrame.new(p+Vector3.new(2,0,2)),guid=hGuid})
                                        end)
                                    end
                                end
                                -- Snap player ke boss
                                local char = LP.Character
                                if char then
                                    local hrpChar = char:FindFirstChild("HumanoidRootPart")
                                    if hrpChar then
                                        pcall(function() hrpChar.CFrame = CFrame.new(p + Vector3.new(0,2,3)) end)
                                    end
                                end
                            end
                            RaidStatusUpdate("⚔ Boss: "..alive.." HP  |  Kill: "..RAID.killed, Color3.fromRGB(255,100,30))
                        end

                        task.wait(0.08)
                        atkT = atkT + 0.08
                        if atkT > 180 then
                            RaidStatusUpdate("⏰ Timeout 3 menit, lanjut collect...", Color3.fromRGB(255,200,60))
                            break
                        end
                    end
                end
            end
            if not RAID.running then break end

            -- ── STEP 7 : GetDrawHeroId (drop loot dari boss) ──
            -- Dipanggil otomatis oleh server, tidak perlu manual invoke
            task.wait(0.5)

            -- ── STEP 8 : Auto Collect Item ──
            if RAID.autoCollect then
                RaidStatusUpdate("💰 Mengambil item...", Color3.fromRGB(100,255,150))
                RaidCollectAll()
                task.wait(0.3)
            end

            -- ── STEP 9 : Ambil Reward Raid ──
            RaidStatusUpdate("🎁 Mengambil reward raid...", Color3.fromRGB(255,220,80))
            if RE_GainRaidsRewards then
                -- Loop slot reward 1–3
                for slot = 1, 3 do
                    pcall(function() RE_GainRaidsRewards:InvokeServer(slot) end)
                    task.wait(0.2)
                end
            end
            task.wait(0.3)
            if not RAID.running then break end

            -- ── STEP 10 : Quit Raid Map ──
            RaidStatusUpdate("🚪 Keluar dari map raid...", Color3.fromRGB(200,100,100))
            if RE_QuitRaidsMap then
                pcall(function()
                    RE_QuitRaidsMap:InvokeServer({
                        currentSlotIndex = 2,
                        toMapId          = 50001,
                    })
                end)
            end
            task.wait(0.5)
            if not RAID.running then break end

            -- ── STEP 11 : Teleport Balik ke Map Normal ──
            RaidStatusUpdate("🌀 Kembali ke map normal...", Color3.fromRGB(180,100,255))
            if RE_RaidStartTp then
                pcall(function()
                    RE_RaidStartTp:FireServer({mapId = 50001})
                end)
            end
            if RE_EquipHeroWithData then
                pcall(function() RE_EquipHeroWithData:FireServer() end)
            end
            if RE_LocalTpSuccess then
                pcall(function() RE_LocalTpSuccess:InvokeServer() end)
            end

            -- ── SELESAI 1 LOOP ──
            RAID.loopCount = RAID.loopCount + 1
            RaidCounterUpdate()
            RaidStatusUpdate("✅ Loop "..RAID.loopCount.." selesai! Delay "..RAID.nextDelay.."s...", Color3.fromRGB(100,255,150))
            if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,255,150) end

            local d2 = 0
            while d2 < RAID.nextDelay and RAID.running do
                task.wait(0.2); d2 = d2 + 0.2
            end
        end

        RAID.running = false
        _raidOn = false
        RaidStatusUpdate("⏹ Idle — Auto Raid berhenti", Color3.fromRGB(160,148,135))
        if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
    end)
end

-- ============================================================
-- PANEL : AUTO RAID (dipecah jadi sub-fungsi — fix local limit)
-- ============================================================

-- Sub-fungsi 1: Status card
local function BuildRaidStatusCard(p)
    local card = Frame(p, Color3.fromRGB(30,14,3), UDim2.new(1,0,0,0))
    card.LayoutOrder=1; card.AutomaticSize=Enum.AutomaticSize.Y
    Corner(card,10); Stroke(card,C.ACC,1,0.3); Padding(card,10,10,12,12)
    New("UIListLayout",{Parent=card,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

    local dotRow = Frame(card,Color3.fromRGB(0,0,0),UDim2.new(1,0,0,26))
    dotRow.BackgroundTransparency=1; dotRow.LayoutOrder=0
    local dot = Frame(dotRow,Color3.fromRGB(100,100,100),UDim2.new(0,10,0,10))
    dot.Position=UDim2.new(0,0,0.5,-5); Corner(dot,5)
    RAID.dot = dot
    local stLbl = Label(dotRow,"⏹ Idle — Aktifkan untuk mulai Raid",11,C.TXT2,Enum.Font.Gotham)
    stLbl.Size=UDim2.new(1,-18,1,0); stLbl.Position=UDim2.new(0,18,0,0)
    stLbl.TextTruncate=Enum.TextTruncate.AtEnd
    RAID.statusLbl = stLbl

    local cRow = Frame(card,Color3.fromRGB(22,10,2),UDim2.new(1,0,0,24))
    cRow.LayoutOrder=1; Corner(cRow,6); Stroke(cRow,C.BORD,1,0.5)
    local kLbl = Label(cRow,"Kill: 0",10.5,C.ACC2,Enum.Font.GothamBold)
    kLbl.Size=UDim2.new(0.5,0,1,0); kLbl.Position=UDim2.new(0,8,0,0)
    RAID.killLbl = kLbl
    local lLbl = Label(cRow,"Loop: 0",10.5,C.TXT3,Enum.Font.GothamBold)
    lLbl.Size=UDim2.new(0.5,0,1,0); lLbl.Position=UDim2.new(0.5,0,0,0)
    RAID.loopLbl = lLbl
end


-- Sub-fungsi 2: Difficulty selector + live raid list
local function BuildRaidIdSelector(p)

    -- ── SECTION HEADER ──
    SectionHeader(p,"PILIH DIFFICULTY",2)

    -- State
    local DIFF_MODE    = "easy"
    local PREF_RAIDID  = nil  -- untuk mode preferred

    -- Info raid yang dipilih saat ini
    local selCard = Frame(p,Color3.fromRGB(28,12,2),UDim2.new(1,0,0,32))
    selCard.LayoutOrder=3; Corner(selCard,8); Stroke(selCard,C.ACC,1,0.3)
    local selLbl = Label(selCard,"⏳ Menunggu notifikasi Raid...",11,C.TXT3,Enum.Font.Gotham)
    selLbl.Size=UDim2.new(1,-8,1,0); selLbl.Position=UDim2.new(0,8,0,0)
    selLbl.TextTruncate=Enum.TextTruncate.AtEnd

    -- ── 4 TOMBOL DIFFICULTY ──
    local diffRow = Frame(p,Color3.fromRGB(0,0,0),UDim2.new(1,0,0,34))
    diffRow.BackgroundTransparency=1; diffRow.LayoutOrder=4

    local DIFFS = {
        {key="easy",      ico="⬇",  label="Easy",      color=Color3.fromRGB(60,200,80)},
        {key="medium",    ico="➡",  label="Medium",    color=Color3.fromRGB(220,190,40)},
        {key="hard",      ico="⬆",  label="Hard",      color=Color3.fromRGB(220,70,60)},
        {key="preferred", ico="⚙",  label="Preferred", color=Color3.fromRGB(100,160,255)},
    }
    local dBtns = {}

    -- Fungsi resolve raid berdasarkan difficulty
    local function GetRaidByDiff(mode)
        if #RAID_ID_LIST == 0 then return nil end
        if mode == "easy" then
            return RAID_ID_LIST[1]
        elseif mode == "medium" then
            return RAID_ID_LIST[math.ceil(#RAID_ID_LIST/2)]
        elseif mode == "hard" then
            return RAID_ID_LIST[#RAID_ID_LIST]
        elseif mode == "preferred" then
            for _, r in ipairs(RAID_ID_LIST) do
                if r.id == PREF_RAIDID then return r end
            end
            return RAID_ID_LIST[1]
        end
        return RAID_ID_LIST[1]
    end

    local function UpdateSelLabel()
        local r = GetRaidByDiff(DIFF_MODE)
        if r then
            RAID.raidId  = r.id
            RAID.raidMapId = r.mapId
            selLbl.Text  = "🎯 "..r.label
            selLbl.TextColor3 = C.ACC2
        else
            selLbl.Text  = "⏳ Menunggu notifikasi Raid..."
            selLbl.TextColor3 = C.TXT3
        end
    end

    local function SelectDiff(key)
        DIFF_MODE = key
        for _, ref in ipairs(dBtns) do
            local sel = ref.key == key
            ref.btn.BackgroundColor3 = sel and ref.color or Color3.fromRGB(40,18,3)
            ref.lbl.TextColor3 = sel and Color3.fromRGB(255,255,255) or C.TXT2
            local st = ref.btn:FindFirstChildWhichIsA("UIStroke")
            if st then st.Transparency = sel and 0.1 or 0.7 end
        end
        UpdateSelLabel()
    end

    for i, d in ipairs(DIFFS) do
        local btn = Btn(diffRow,Color3.fromRGB(40,18,3),UDim2.new(0.25,-3,1,0))
        btn.Position=UDim2.new((i-1)*0.25,2,0,0)
        Corner(btn,6); Stroke(btn,d.color,1,0.7)
        local bl = Label(btn,d.ico.." "..d.label,9.5,C.TXT2,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        bl.Size=UDim2.new(1,0,1,0)
        table.insert(dBtns,{key=d.key,btn=btn,lbl=bl,color=d.color})
        btn.MouseButton1Click:Connect(function() SelectDiff(d.key) end)
    end
    SelectDiff("easy")

    -- ── PREFERRED LIST — semua raid aktif ──
    SectionHeader(p,"RAID AKTIF",5)

    local listCard = Frame(p,Color3.fromRGB(20,10,2),UDim2.new(1,0,0,0))
    listCard.LayoutOrder=6; listCard.AutomaticSize=Enum.AutomaticSize.Y
    Corner(listCard,8); Stroke(listCard,C.BORD,1,0.4); Padding(listCard,6,6,8,8)
    New("UIListLayout",{Parent=listCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})

    local listStatus = Label(listCard,"⏳ Belum ada raid aktif — tunggu notifikasi...",10,C.TXT3,Enum.Font.Gotham)
    listStatus.Size=UDim2.new(1,0,0,0); listStatus.AutomaticSize=Enum.AutomaticSize.Y
    listStatus.TextWrapped=true; listStatus.LayoutOrder=0

    -- Tombol Refresh manual
    local refRow = Frame(p,Color3.fromRGB(0,0,0),UDim2.new(1,0,0,28))
    refRow.BackgroundTransparency=1; refRow.LayoutOrder=7
    local refBtn = Btn(refRow,Color3.fromRGB(50,20,3),UDim2.new(1,0,1,0))
    Corner(refBtn,7); Stroke(refBtn,C.ACC,1,0.4)
    local refLbl = Label(refBtn,"🔄 Refresh (ambil dari map sekarang)",11,C.ACC2,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    refLbl.Size=UDim2.new(1,0,1,0)
    refBtn.MouseButton1Click:Connect(function()
        refLbl.Text="⏳ Fetching..."
        task.spawn(function()
            FetchRaidIds()
            refLbl.Text="🔄 Refresh (ambil dari map sekarang)"
        end)
    end)

    -- Rebuild list raid aktif
    local function RebuildUI()
        -- Hapus tombol lama
        for _, ch in ipairs(listCard:GetChildren()) do
            if ch ~= listStatus and not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
                ch:Destroy()
            end
        end

        if #RAID_ID_LIST == 0 then
            listStatus.Text = "⏳ Belum ada raid aktif — tunggu notifikasi..."
            listStatus.TextColor3 = C.TXT3
            UpdateSelLabel()
            return
        end

        listStatus.Text = "✅ "..#RAID_ID_LIST.." Raid aktif:"
        listStatus.TextColor3 = Color3.fromRGB(100,255,150)

        -- Tandai Easy/Medium/Hard
        local easyR  = RAID_ID_LIST[1]
        local medR   = RAID_ID_LIST[math.ceil(#RAID_ID_LIST/2)]
        local hardR  = RAID_ID_LIST[#RAID_ID_LIST]

        local DIFF_COLORS = {
            [60200] = Color3.fromRGB(60,200,80),   -- easy
            [220190] = Color3.fromRGB(220,190,40), -- medium
            [220070] = Color3.fromRGB(220,70,60),  -- hard
        }

        for i, r in ipairs(RAID_ID_LIST) do
            local tag = ""
            local tagColor = C.TXT2
            if r.id == easyR.id   then tag=" [Easy]";  tagColor=Color3.fromRGB(60,200,80)   end
            if r.id == medR.id    then tag=" [Medium]"; tagColor=Color3.fromRGB(220,190,40)  end
            if r.id == hardR.id   then tag=" [Hard]";   tagColor=Color3.fromRGB(220,70,60)   end

            local sel = (r.id == PREF_RAIDID)
            local rb  = Btn(listCard,sel and Color3.fromRGB(50,22,5) or Color3.fromRGB(35,15,2),UDim2.new(1,0,0,28))
            rb.LayoutOrder=i; Corner(rb,6); Stroke(rb,sel and C.ACC or C.BORD,1,sel and 0.2 or 0.6)

            local rbL = Label(rb,(sel and "● " or "○ ")..r.label..tag,10.5,tagColor,Enum.Font.Gotham)
            rbL.Size=UDim2.new(1,-8,1,0); rbL.Position=UDim2.new(0,8,0,0)
            rbL.TextTruncate=Enum.TextTruncate.AtEnd

            rb.MouseButton1Click:Connect(function()
                PREF_RAIDID = r.id
                SelectDiff("preferred")
                RebuildUI()
            end)
        end

        UpdateSelLabel()
    end

    -- Register callback — dipanggil setiap kali UpdateRaidInfo masuk
    _raidIdRefreshCb = RebuildUI
end


-- Sub-fungsi 3: Main toggle
local function BuildRaidMainToggle(p)
    SectionHeader(p,"KONTROL",5)
    local row = Frame(p,Color3.fromRGB(35,15,2),UDim2.new(1,0,0,50))
    row.LayoutOrder=6; Corner(row,10); Stroke(row,C.ACC,1.5,0.2)
    local mL = Label(row,"⚡  Auto Raid",13,C.TXT,Enum.Font.GothamBold)
    mL.Size=UDim2.new(0.65,0,0,20); mL.Position=UDim2.new(0,12,0,8)
    local mS = Label(row,"Jalankan loop raid otomatis",10,C.TXT3,Enum.Font.Gotham)
    mS.Size=UDim2.new(0.65,0,0,14); mS.Position=UDim2.new(0,12,0,28)
    local pill = Btn(row,Color3.fromRGB(120,40,0),UDim2.new(0,50,0,26))
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
        row.BackgroundColor3=_raidOn and Color3.fromRGB(50,25,3) or Color3.fromRGB(35,15,2)
        if _raidOn then StartRaidLoop()
        else StopRaid(); RaidStatusUpdate("⏹ Idle — Auto Raid dimatikan",Color3.fromRGB(160,148,135)) end
    end)
end

-- Sub-fungsi 4: Opsi toggles
local function BuildRaidOpsiToggles(p)
    SectionHeader(p,"OPSI",7)
    local _,sA=ToggleRow(p,"⚔  Auto Attack","Serang boss/musuh secara otomatis",8,function(on) RAID.autoAttack=on end)
    sA(true)
    local _,sC=ToggleRow(p,"💰  Auto Collect","Ambil semua item & reward setelah raid",9,function(on) RAID.autoCollect=on end)
    sC(true)
end

-- Sub-fungsi 5: Delay rows
local function BuildRaidDelayRows(p)
    SectionHeader(p,"PENGATURAN DELAY",10)
    local function MakeDelayRow(order,icon,title,desc,getV,setV,mn,mx)
        local row=Frame(p,C.SURFACE,UDim2.new(1,0,0,50))
        row.LayoutOrder=order; Corner(row,8); Stroke(row,C.BORD,1,0.4)
        local lb=Label(row,icon.."  "..title,12,C.TXT,Enum.Font.GothamBold)
        lb.Size=UDim2.new(0.55,0,0,18); lb.Position=UDim2.new(0,12,0,8)
        local sb=Label(row,desc,10,C.TXT2,Enum.Font.Gotham)
        sb.Size=UDim2.new(0.7,0,0,14); sb.Position=UDim2.new(0,12,0,28)
        local vL=Label(row,getV().."s",12,C.ACC2,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        vL.Size=UDim2.new(0,28,0,20); vL.Position=UDim2.new(1,-88,0.5,-10)
        local bm=Btn(row,Color3.fromRGB(120,40,0),UDim2.new(0,24,0,24))
        bm.Position=UDim2.new(1,-66,0.5,-12); Corner(bm,6)
        local bmL=Label(bm,"−",14,C.TXT,Enum.Font.GothamBold,Enum.TextXAlignment.Center); bmL.Size=UDim2.new(1,0,1,0)
        local bp=Btn(row,Color3.fromRGB(120,40,0),UDim2.new(0,24,0,24))
        bp.Position=UDim2.new(1,-38,0.5,-12); Corner(bp,6)
        local bpL=Label(bp,"+",14,C.TXT,Enum.Font.GothamBold,Enum.TextXAlignment.Center); bpL.Size=UDim2.new(1,0,1,0)
        bm.MouseButton1Click:Connect(function() setV(math.max(mn,getV()-1)); vL.Text=getV().."s" end)
        bp.MouseButton1Click:Connect(function() setV(math.min(mx,getV()+1)); vL.Text=getV().."s" end)
    end
    MakeDelayRow(11,"⏱","Join Delay","Jeda sebelum mulai serang boss",
        function() return RAID.joinDelay end,function(v) RAID.joinDelay=v end,1,30)
    MakeDelayRow(12,"🔁","Delay Antar Raid","Jeda sebelum memulai raid berikutnya",
        function() return RAID.nextDelay end,function(v) RAID.nextDelay=v end,1,60)
end

-- Sub-fungsi 6: Flow info card
local function BuildRaidFlowCard(p)
    local fc=Frame(p,Color3.fromRGB(20,10,2),UDim2.new(1,0,0,0))
    fc.LayoutOrder=13; fc.AutomaticSize=Enum.AutomaticSize.Y
    Corner(fc,8); Stroke(fc,C.ACC,1,0.5); Padding(fc,10,10,12,12)
    New("UIListLayout",{Parent=fc,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})
    local function FL(order,txt,col)
        local l=Label(fc,txt,10,col or Color3.fromRGB(220,200,170),Enum.Font.Gotham)
        l.Size=UDim2.new(1,0,0,0); l.AutomaticSize=Enum.AutomaticSize.Y
        l.TextWrapped=true; l.LayoutOrder=order
    end
    local ft=Label(fc,"📡  Alur Remote Raid",11,Color3.fromRGB(255,200,60),Enum.Font.GothamBold)
    ft.Size=UDim2.new(1,0,0,0); ft.AutomaticSize=Enum.AutomaticSize.Y; ft.LayoutOrder=0
    FL(1,"1. GetRaidTeamInfos    → Cek info team")
    FL(2,"2. CreateRaidTeam      → Buat team (Raid ID)")
    FL(3,"3. StartChallengeRaidMap → Konfirmasi map")
    FL(4,"4. StartLocalPlayerTeleport → TP ke raid")
    FL(5,"5. EquipHeroWithData + TeleportSuccess")
    FL(6,"6. ClickEnemy (loop)   → Serang boss")
    FL(7,"7. CollectItem (loop)  → Ambil item")
    FL(8,"8. GainRaidsRewards    → Ambil reward slot")
    FL(9,"9. QuitRaidsMap        → Keluar raid")
    FL(10,"10. StartLocalPlayerTeleport → TP balik")
    FL(11,"⚠ Jika raid gagal, coba ganti Raid ID.",Color3.fromRGB(255,130,100))
end

-- Rakit semua sub-fungsi ke panel
;(function()
    local p = NewPanel("autoraid")
    SectionHeader(p,"AUTO RAID",0)
    BuildRaidStatusCard(p)
    BuildRaidIdSelector(p)
    BuildRaidMainToggle(p)
    BuildRaidOpsiToggles(p)
    BuildRaidDelayRows(p)
    BuildRaidFlowCard(p)
end)()


-- ============================================================
-- PANEL : SETTINGS
-- ============================================================
;(function()
    local p = NewPanel("settings")
    SectionHeader(p,"PENGATURAN LANJUTAN",0)
    ToggleRow(p,"Izinkan HTTP Request","Aktifkan akses internet untuk fitur eksternal",2,function(on)
        pcall(function() game:GetService("HttpService").HttpEnabled=on end)
    end)
end)()

-- ============================================================
-- INIT
-- ============================================================
SwitchTab("main")
RefreshStatus()
InitAllCaptureLayers()

print("[ ASH GUI ] Loaded — Bubble diganti versi sc_baru (v14.5) — by FLa")
