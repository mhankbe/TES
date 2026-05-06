-- ASH Auto Farm - by FLa Project
do
 local _RS2 = game:GetService("ReplicatedStorage")
 local _LP2 = game:GetService("Players").LocalPlayer
 local _w = 0
 repeat
 task.wait(1); _w = _w + 1
 until (_RS2:FindFirstChild("Remotes") and _LP2.Character) or _w >= 15
 -- [v254] Kurangi fixed delay: 5s -> 2s (cukup untuk Delta Android)
 task.wait(2)
end

do
Players = game:GetService("Players")
TweenService = game:GetService("TweenService")
UserInputService = game:GetService("UserInputService")
RunService = game:GetService("RunService")
RS = game:GetService("ReplicatedStorage")
TeleportService = game:GetService("TeleportService")
GuiService = game:GetService("GuiService")
VIM = game:GetService("VirtualInputManager")

LP = Players.LocalPlayer
PG = LP.PlayerGui

-- ============================================================
-- [v232] UpdateCityRaidInfo listener dipindah ke SETELAH GUI load
-- (lihat ConnectUpdateCityRaidListener di bawah SwitchTab)
-- Variabel buffer tetap dideklarasi di sini agar tersedia global
-- ============================================================
local CITY_TO_MAP_EARLY = {[1000001]=3,[1000002]=7,[1000003]=10,[1000004]=13}

-- Forward declare siege snapshot functions (definisi ada di bawah setelah SIEGE table siap)

-- [v232] Placeholder: listener sesungguhnya dipasang setelah GUI load
-- Fungsi ini di-define ulang di bawah setelah SIEGE table siap
ConnectUpdateCityRaidListener = nil -- forward declare

-- [v232] GetCityRaidInfos sekarang dipanggil dari ConnectUpdateCityRaidListener
-- setelah GUI load + delay 5 detik (lihat di bawah SwitchTab)
end -- do globals

-- ============================================================
-- CLEANUP OLD GUI
-- ============================================================
for _, name in ipairs({"ASH_GUI", "ASH_NightFrost", "ASH_DD"}) do
 pcall(function()
 local old = PG:FindFirstChild(name)
 if old then old:Destroy() end
 end)
end


-- [v254] Loop wait duplikat dihapus - sudah ditangani di block pertama atas

-- ============================================================
-- REMOTES
-- ============================================================
Remotes = RS:WaitForChild("Remotes", 10)
RE = {
 CollectItem = Remotes:WaitForChild("CollectItem", 10),
 ExtraReward = Remotes:FindFirstChild("ExtraReward"),
 ShowReward = Remotes:FindFirstChild("ShowReward"),
 DropItems = Remotes:FindFirstChild("DropItems"),
 AutoHeroQuirk = Remotes:FindFirstChild("AutoRandomHeroQuirk"),
 RandomHeroQuirk = Remotes:WaitForChild("RandomHeroQuirk", 10),
 Click = Remotes:FindFirstChild("ClickEnemy"),
 Atk = Remotes:FindFirstChild("PlayerClickAttackSkill"),
 Death = Remotes:FindFirstChild("EnemyDeath"),
 HeroMove = Remotes:FindFirstChild("HeroMoveToEnemyPos"),
 HeroStand = Remotes:FindFirstChild("HeroStandTo"),
 HeroSkill = Remotes:FindFirstChild("HeroPlaySkillAnim"),
 HeroUseSkill = Remotes:FindFirstChild("HeroUseSkill"),
 EquipWeapon = Remotes:WaitForChild("EquipWeapon", 10),
 RandomWeaponQuirk = Remotes:WaitForChild("RandomWeaponQuirk", 10),
 RandomHeroEquipGrade = Remotes:WaitForChild("RandomHeroEquipGrade", 10),
 RerollHalo = Remotes:FindFirstChild("RerollHalo"),
 RerollOrnament = Remotes:WaitForChild("RerollOrnament", 15),
 StartTp = Remotes:FindFirstChild("StartLocalPlayerTeleport"),
 LocalTp = Remotes:FindFirstChild("LocalPlayerTeleport"),
 CreateRaidTeam = Remotes:FindFirstChild("CreateRaidTeam"),
 StartChallengeRaidMap = Remotes:FindFirstChild("StartChallengeRaidMap"),
 EquipHeroWithData = Remotes:FindFirstChild("EquipHeroWithData"),
 LocalTpSuccess = Remotes:FindFirstChild("LocalPlayerTeleportSuccess"),
 GainRaidsRewards = Remotes:FindFirstChild("GainRaidsRewards"),
 UseRaidItem = Remotes:FindFirstChild("UseRaidItem"),

 GetDrawHeroId = Remotes:FindFirstChild("GetDrawHeroId"),
 GetRaidTeamInfos = Remotes:FindFirstChild("GetRaidTeamInfos"),
 UnEquipHero = Remotes:FindFirstChild("UnequipAllHero"),
 EquipBestHero = Remotes:FindFirstChild("AutoEquipBestHero"),
 DeleteWeapons = Remotes:FindFirstChild("DeleteWeapons"),
 DecomposeItems = Remotes:FindFirstChild("DecomposeItems"),
}

MY_USER_ID = LP.UserId
HERO_GUIDS, HERO_DATA = {}, {} -- hero data
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
-- ============================================================
-- TEMA : Solo Leveling (1.lua T) — Dark Navy & Bright Accent + Glass
-- ============================================================
C = {
 -- Background & panel (maps to T.BgMain / BgContent / BgSidebar / TabHover)
 BG = Color3.fromRGB( 9,  11, 22),
 BG2 = Color3.fromRGB(13, 15, 32),
 BG3 = Color3.fromRGB(13, 15, 32),
 SURFACE = Color3.fromRGB(18, 28, 72),
 SURFACE2 = Color3.fromRGB(22, 32, 80),
 SIDEBAR = Color3.fromRGB(11, 13, 28),
 ACC = Color3.fromRGB(55, 105, 255),
 ACC2 = Color3.fromRGB(90, 145, 255),
 ACC3 = Color3.fromRGB(72, 125, 255),
 BORD = Color3.fromRGB(35,  55, 130),
 BORD2 = Color3.fromRGB(55, 105, 255),
 TXT = Color3.fromRGB(195, 210, 255),
 TXT2 = Color3.fromRGB(235, 242, 255),
 TXT3 = Color3.fromRGB( 90, 110, 170),
 TBAR = Color3.fromRGB( 7,  8, 18),
 SEL_BG = Color3.fromRGB(25, 45, 115),
 SEL_BORD = Color3.fromRGB(55, 105, 255),
 WIN_CLOSE= Color3.fromRGB(200,  50,  50),
 WIN_MIN = Color3.fromRGB(252, 211,  77),
 WIN_MAX = Color3.fromRGB(110, 231, 183),
 BLACK = Color3.fromRGB( 0, 0, 0),
 DD_BG = Color3.fromRGB(13, 15, 32),
 DD_HOVER = Color3.fromRGB(18, 28, 72),
 GRN = Color3.fromRGB( 25,  85,  25),
 RED = Color3.fromRGB(170,  35,  35),
 YEL = Color3.fromRGB(252, 211,  77),
 DIM = Color3.fromRGB( 90, 110, 170),
 DK = Color3.fromRGB(55, 105, 255),
 AG = Color3.fromRGB(55, 105, 255),
 ROW = Color3.fromRGB(18, 28, 72),
 NSEL = Color3.fromRGB(22, 32, 80),
 PILL_OFF = Color3.fromRGB(22, 32, 80),
 PILL_ON = Color3.fromRGB(25, 45, 115),
 KNOB_OFF = Color3.fromRGB( 90, 110, 170),
 KNOB_ON = Color3.fromRGB(235, 242, 255),
}

-- ============================================================
-- THEME SYSTEM CONFIGURATION
-- ============================================================
_G.CurrentTheme = "Solo Leveling"
_G.PotatoMode = false
_G.ThemeTransparency = 0.42
_G.DisableAnimations = false

local ThemePalettes = { 
    -- Batches 1-10 
    ["Solo Leveling"] = {BG = Color3.fromRGB(10, 15, 30), Accent = Color3.fromRGB(0, 200, 255), Text = Color3.fromRGB(255, 255, 255)}, 
    ["Naruto"] = {BG = Color3.fromRGB(0, 0, 0), Accent = Color3.fromRGB(255, 100, 0), Text = Color3.fromRGB(255, 0, 0)}, 
    ["Sasuke"] = {BG = Color3.fromRGB(20, 10, 30), Accent = Color3.fromRGB(100, 0, 255), Text = Color3.fromRGB(0, 220, 255)}, 
    ["One Piece"] = {BG = Color3.fromRGB(150, 0, 0), Accent = Color3.fromRGB(255, 215, 0), Text = Color3.fromRGB(0, 100, 255)}, 
    ["Demon Slayer"] = {BG = Color3.fromRGB(0, 50, 0), Accent = Color3.fromRGB(0, 0, 0), Text = Color3.fromRGB(100, 200, 255)}, 
    ["Dragon Ball"] = {BG = Color3.fromRGB(255, 120, 0), Accent = Color3.fromRGB(255, 255, 0), Text = Color3.fromRGB(0, 100, 255)}, 
    ["Transformer"] = {BG = Color3.fromRGB(0, 50, 200), Accent = Color3.fromRGB(200, 0, 0), Text = Color3.fromRGB(150, 150, 150)}, 
    ["God Of War"] = {BG = Color3.fromRGB(200, 200, 200), Accent = Color3.fromRGB(150, 0, 0), Text = Color3.fromRGB(215, 185, 0)}, 
    ["Devil May Cry"] = {BG = Color3.fromRGB(150, 0, 0), Accent = Color3.fromRGB(0, 0, 0), Text = Color3.fromRGB(200, 200, 200)}, 
    ["Tekken 5"] = {BG = Color3.fromRGB(10, 20, 50), Accent = Color3.fromRGB(255, 215, 0), Text = Color3.fromRGB(100, 100, 100)}, 
    -- Batches 11-20 
    ["GTA San Andreas"] = {BG = Color3.fromRGB(0, 100, 0), Accent = Color3.fromRGB(0, 0, 0), Text = Color3.fromRGB(255, 255, 255)}, 
    ["Final Fantasy X"] = {BG = Color3.fromRGB(50, 150, 255), Accent = Color3.fromRGB(255, 215, 0), Text = Color3.fromRGB(255, 255, 255)}, 
    ["NFS Underground 2"] = {BG = Color3.fromRGB(0, 255, 0), Accent = Color3.fromRGB(0, 0, 0), Text = Color3.fromRGB(255, 100, 0)}, 
    ["Windows 11"] = {BG = Color3.fromRGB(200, 220, 255), Accent = Color3.fromRGB(240, 240, 240), Text = Color3.fromRGB(100, 100, 100)}, 
    ["MacOS"] = {BG = Color3.fromRGB(200, 200, 200), Accent = Color3.fromRGB(0, 150, 255), Text = Color3.fromRGB(50, 50, 50)}, 
    ["Fortnite"] = {BG = Color3.fromRGB(0, 200, 255), Accent = Color3.fromRGB(150, 0, 255), Text = Color3.fromRGB(255, 255, 0)}, 
    ["CSGO"] = {BG = Color3.fromRGB(200, 200, 0), Accent = Color3.fromRGB(0, 100, 200), Text = Color3.fromRGB(80, 80, 80)}, 
    ["Roblox"] = {BG = Color3.fromRGB(200, 0, 0), Accent = Color3.fromRGB(0, 150, 255), Text = Color3.fromRGB(200, 200, 200)}, 
    ["Resident Evil"] = {BG = Color3.fromRGB(200, 0, 0), Accent = Color3.fromRGB(0, 150, 0), Text = Color3.fromRGB(0, 0, 0)}, 
    ["iPhone"] = {BG = Color3.fromRGB(180, 180, 180), Accent = Color3.fromRGB(80, 0, 150), Text = Color3.fromRGB(10, 10, 10)}, 
    -- Batches 21-30 
    ["Gojek"] = {BG = Color3.fromRGB(0, 180, 0), Accent = Color3.fromRGB(0, 0, 0), Text = Color3.fromRGB(255, 255, 255)}, 
    ["One Punch Man"] = {BG = Color3.fromRGB(255, 215, 0), Accent = Color3.fromRGB(255, 255, 255), Text = Color3.fromRGB(200, 0, 0)}, 
    ["Gundam"] = {BG = Color3.fromRGB(255, 255, 255), Accent = Color3.fromRGB(255, 215, 0), Text = Color3.fromRGB(0, 100, 255)}, 
    ["Jujutsu Kaisen"] = {BG = Color3.fromRGB(10, 10, 10), Accent = Color3.fromRGB(150, 0, 0), Text = Color3.fromRGB(150, 0, 255)}, 
    ["Nezuko"] = {BG = Color3.fromRGB(255, 182, 193), Accent = Color3.fromRGB(139, 0, 0), Text = Color3.fromRGB(139, 69, 19)}, 
    ["Rengoku Kyojuro"] = {BG = Color3.fromRGB(255, 215, 0), Accent = Color3.fromRGB(255, 100, 0), Text = Color3.fromRGB(255, 69, 0)}, 
    ["Kanroji Mitsuri"] = {BG = Color3.fromRGB(255, 182, 193), Accent = Color3.fromRGB(191, 255, 0), Text = Color3.fromRGB(255, 255, 255)}, 
    ["Tokito Muichiro"] = {BG = Color3.fromRGB(0, 128, 128), Accent = Color3.fromRGB(10, 10, 10), Text = Color3.fromRGB(180, 255, 220)}, 
    ["Shinazugawa Sanemi"] = {BG = Color3.fromRGB(85, 107, 47), Accent = Color3.fromRGB(255, 255, 255), Text = Color3.fromRGB(50, 50, 50)}, 
    ["Muzan"] = {BG = Color3.fromRGB(10, 10, 10), Accent = Color3.fromRGB(139, 0, 0), Text = Color3.fromRGB(255, 255, 255)} 
}

-- ============================================================
 -- UI HELPERS
 -- ============================================================
function SystemNotify(text, duration)
    local n = Instance.new("Frame", ScreenGui)
    n.Size = UDim2.new(0, 300, 0, 40)
    n.Position = UDim2.new(0.5, -150, 0, -50)
    n.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    n.BackgroundTransparency = 0.1
    n.ZIndex = 1000
    
    local c = Instance.new("UICorner", n); c.CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke", n ); s.Color = Color3.fromRGB(255, 100, 0); s.Thickness = 2
    
    local l = Instance.new("TextLabel", n)
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(255, 255, 255)
    l.TextSize = 12
    l.Font = Enum.Font.GothamBold
    l.TextXAlignment = Enum.TextXAlignment.Center
    
    TweenService:Create(n, TweenInfo.new(0.5, Enum.EasingStyle.Back), {Position = UDim2.new(0.5, -150, 0.1, 20)}):Play()
    task.delay(duration or 3, function()
        TweenService:Create(n, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {Position = UDim2.new(0.5, -150, 0, -50), BackgroundTransparency = 1}):Play()
        task.delay(0.5, function() n:Destroy() end)
    end)
end

function New(class, props)
  local obj = Instance.new(class)
 for k, v in pairs(props) do pcall(function() obj[k] = v end) end
 return obj
end

function Frame(parent, color, size)
 return New("Frame", {
 Parent = parent, BackgroundColor3 = color,
 BackgroundTransparency = 0.42,
 Size = size or UDim2.new(1,0,1,0), BorderSizePixel = 0
 })
end

function Btn(parent, color, size)
 return New("TextButton", {
 Parent = parent, BackgroundColor3 = color,
 BackgroundTransparency = 0.2,
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
 New("UICorner", {Parent = obj, CornerRadius = UDim.new(0, r or 10)})
end

function Stroke(obj, color, thickness, transparency)
 New("UIStroke", {
 Parent = obj, Color = color or C.BORD,
 Thickness = thickness or 1.5, Transparency = transparency or 0
 })
end

function Padding(obj, top, bottom, left, right)
 New("UIPadding", {
 Parent = obj,
 PaddingTop = UDim.new(0, top or 6),
 PaddingBottom = UDim.new(0, bottom or 6),
 PaddingLeft = UDim.new(0, left or 8),
 PaddingRight = UDim.new(0, right or 8),
 })
end

function ListLayout(parent, dir, align, spacing)
 return New("UIListLayout", {
 Parent = parent,
 FillDirection = dir or Enum.FillDirection.Vertical,
 HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
 SortOrder = Enum.SortOrder.LayoutOrder,
 Padding = UDim.new(0, spacing or 4),
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
 Parent = PG, Name = "ASH_NightFrost",
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
Corner(Window, 10)
Stroke(Window, C.BORD, 1.5, 0.88)
-- Glass rim (Solo Leveling accent)
New("UIStroke", { Color = C.ACC, Thickness = 1.5, Transparency = 0.65, Parent = Window })
-- ============================================================
Bubble = Btn(ScreenGui, C.TBAR, UDim2.new(0,58,0,58))
Bubble.Position = UDim2.new(0.5,-29,0,50)
Bubble.Visible = false
Bubble.ZIndex = 10
Corner(Bubble, 12) -- [v273] Rounded Square Style

do
 -- Solo Leveling glass bubble (accent gradient)
 local g = Instance.new("UIGradient", Bubble)
 g.Color = ColorSequence.new({
 ColorSequenceKeypoint.new(0, Color3.fromRGB( 25, 45, 115)),
 ColorSequenceKeypoint.new(0.55, Color3.fromRGB( 55, 105, 255)),
 ColorSequenceKeypoint.new(1, Color3.fromRGB( 90, 145, 255)),
 })
 g.Rotation = 135

 local s = Instance.new("UIStroke", Bubble)
 s.Color = Color3.fromRGB(130, 80, 255); -- [v273] Purple stroke (Premium Look)
 s.Thickness = 2
 s.Transparency = 0.1

 -- [v273 FIX: ULTRA COMPATIBILITY (rbxthumb)]
 local logo = Instance.new("ImageLabel", Bubble)
 logo.Name = "MainLogo"
 logo.Size = UDim2.new(0.7, 0, 0.7, 0)
 logo.Position = UDim2.new(0.15, 0, 0.15, 0)
 logo.BackgroundTransparency = 1
 logo.ZIndex = 25
 -- Gunakan rbxthumb agar Decal ID otomatis terbaca sebagai Image oleh Roblox
 logo.Image = "rbxthumb://type=Asset&id=133989674192597&w=420&h=420"
 logo.ImageColor3 = Color3.fromRGB(255, 255, 255)
 logo.ScaleType = Enum.ScaleType.Fit
 
 task.spawn(function()
     task.wait(2)
     if not logo.IsLoaded or logo.ContentImageSize == Vector2.new(0,0) then
         -- Fallback: Gunakan Headshot pemain jika ID tetap gagal (agar tidak blank hitam)
         local content, isReady = Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
         if isReady then  
         end
     end
 end)
end

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
do
 local bd = false
 local bsm = Vector2.new()
 local bsp = Vector2.new()

 Bubble.InputBegan:Connect(function(i)
 if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
 bd = true
 bsm = Vector2.new(i.Position.X, i.Position.Y)
 bsp = Vector2.new(Bubble.AbsolutePosition.X, Bubble.AbsolutePosition.Y)
 end
 end)

 UserInputService.InputChanged:Connect(function(i)
 if bd and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
 local inset = GuiService:GetGuiInset()
 local vp = workspace.CurrentCamera.ViewportSize
 Bubble.Position = UDim2.new(
 0, math.clamp(bsp.X + (i.Position.X - bsm.X), 0, vp.X - 58),
 0, math.clamp(bsp.Y + (i.Position.Y - bsm.Y) - inset.Y, 0, vp.Y - 58)
 )
 end
 end)

 UserInputService.InputEnded:Connect(function(i)
 if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
 bd = false
 end
 end)
end

-- ============================================================
-- TOPBAR
-- ============================================================
function BuildTopBar()
 TopBar = Frame(Window, C.TBAR, UDim2.new(1,0,0,40))
 Corner(TopBar, 10)
 New("UIGradient", {
 Color = ColorSequence.new(
 C.ACC:Lerp(C.TBAR, 0.82),
 C.TBAR
 ),
 Rotation = 90,
 Parent = TopBar,
 })
 Stroke(TopBar, C.BORD, 1.5, 0.88)
 local TBFix = Frame(TopBar, C.TBAR, UDim2.new(1,0,0,14))
 TBFix.Position = UDim2.new(0,0,1,-14)

 -- [v239] Badge "AS" Night Frost style
 local IconBg = Frame(TopBar, C.ACC, UDim2.new(0,28,0,28))
 IconBg.Position = UDim2.new(0,8,0.5,-14)
 Corner(IconBg, 10); Stroke(IconBg, C.ACC, 1.5, 0.3)
 local IconLbl = Label(IconBg, "AS", 11, C.TXT, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
 IconLbl.Size = UDim2.new(1,0,1,0)

 local TitleLbl = Label(TopBar, "Auto Farming ASH", 14, C.TXT, Enum.Font.GothamBold)
 TitleLbl.Size = UDim2.new(0,160,0,22); TitleLbl.Position = UDim2.new(0,44,0,5)
 local SubLbl = Label(TopBar, "by FLa Project", 11, C.TXT3, Enum.Font.Gotham)
 SubLbl.Size = UDim2.new(0,180,0,13); SubLbl.Position = UDim2.new(0,50,0,26)

 -- Buat tombol dengan posisi absolut (bukan anchor kanan)
 local function MkWinBtn(xPos, color, sym)
 local b = Btn(TopBar, color, UDim2.new(0,22,0,22))
 b.Position = UDim2.new(0, xPos, 0.5, -11)
 Corner(b, 11)
 local l = Label(b, sym, 12, Color3.fromRGB(255,255,255), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
 l.Size = UDim2.new(1,0,1,0)
 return b
 end

 -- Minimize = kiri, Fullscreen = tengah, Close = kanan
 local BtnMin = MkWinBtn(WIN_W - 78, C.WIN_MIN, "-")
 local BtnMax = MkWinBtn(WIN_W - 52, C.WIN_MAX, "+")
 local BtnClose = MkWinBtn(WIN_W - 26, C.WIN_CLOSE, "x")

 -- Drag Window
 local dragging, dragStart, startPos = false, nil, nil
 TopBar.InputBegan:Connect(function(i)
 if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
 dragging = true; dragStart = i.Position; startPos = Window.Position
 end
 end)
 TopBar.InputEnded:Connect(function(i)
 if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
 dragging = false
 end
 end)
 UserInputService.InputChanged:Connect(function(i)
 if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
 local d = i.Position - dragStart
 Window.Position = UDim2.new(
 startPos.X.Scale, startPos.X.Offset + d.X,
 startPos.Y.Scale, startPos.Y.Offset + d.Y
 )
 end
 end)

 -- Show Bubble (minimize) - dari sc_baru
 function ShowBubble()
 Window.Visible = false
 local vp = workspace.CurrentCamera.ViewportSize
 Bubble.Position = UDim2.new(0, vp.X/2 - 29, 0, 50)
 Bubble.Size = UDim2.new(0,0,0,0)
 Bubble.Visible = true
 TweenService:Create(Bubble,
 TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
 {Size = UDim2.new(0,58,0,58)}
 ):Play()
 FloatBubble()
 end

 -- Show Window (restore) - dari sc_baru
 function ShowWin()
 TweenService:Create(Bubble,
 TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In),
 {Size = UDim2.new(0,0,0,0)}
 ):Play()
 task.wait(0.19)
 Bubble.Visible = false
 Bubble.Size = UDim2.new(0,58,0,58)
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
 BtnClose.MouseButton1Click:Connect(function()
 -- [v243] Popup konfirmasi "Are you sure?" sebelum close GUI
 -- Cegah double-popup
 if ScreenGui:FindFirstChild("ASH_CloseConfirm") then return end

 local popupGui = New("Frame", {
 Parent = ScreenGui,
 Name = "ASH_CloseConfirm",
 Size = UDim2.new(0, 240, 0, 108),
 Position = UDim2.new(0.5, -120, 0.5, -54),
 BackgroundColor3 = C.BG2,
 BackgroundTransparency = 0.42,
 BorderSizePixel = 0,
 ZIndex = 200,
 })
 Corner(popupGui, 10)
 Stroke(popupGui, C.WIN_CLOSE, 1.5, 0)

 -- Judul
 local popTitle = New("TextLabel", {
 Parent = popupGui,
 Size = UDim2.new(1,0,0,36),
 Position = UDim2.new(0,0,0,0),
 BackgroundTransparency = 1,
 Text = " Are you Gay?",
 TextSize = 13,
 TextColor3 = C.WIN_CLOSE,
 Font = Enum.Font.GothamBold,
 TextXAlignment = Enum.TextXAlignment.Center,
 ZIndex = 201,
 })

 local popSub = New("TextLabel", {
 Parent = popupGui,
 Size = UDim2.new(1,-16,0,22),
 Position = UDim2.new(0,8,0,34),
 BackgroundTransparency = 1,
 Text = "all features will be reset.",
 TextSize = 10,
 TextColor3 = C.TXT3,
 Font = Enum.Font.Gotham,
 TextXAlignment = Enum.TextXAlignment.Center,
 TextWrapped = true,
 ZIndex = 201,
 })

 -- Tombol NO
 local btnNo = New("TextButton", {
 Parent = popupGui,
 Size = UDim2.new(0, 96, 0, 30),
 Position = UDim2.new(0, 12, 0, 66),
 BackgroundColor3 = C.SURFACE2,
 BackgroundTransparency = 0.2,
 BorderSizePixel = 0,
 Text = "NO",
 TextSize = 12,
 TextColor3 = C.TXT2,
 Font = Enum.Font.GothamBold,
 AutoButtonColor = false,
 ZIndex = 201,
 })
 Corner(btnNo, 10)
 Stroke(btnNo, C.BORD, 1.5, 0.5)

 -- Tombol YES
 local btnYes = New("TextButton", {
 Parent = popupGui,
 Size = UDim2.new(0, 96, 0, 30),
 Position = UDim2.new(0, 132, 0, 66),
 BackgroundColor3 = C.WIN_CLOSE,
 BackgroundTransparency = 0.2,
 BorderSizePixel = 0,
 Text = "YES",
 TextSize = 12,
 TextColor3 = Color3.fromRGB(255,255,255),
 Font = Enum.Font.GothamBold,
 AutoButtonColor = false,
 ZIndex = 201,
 })
 Corner(btnYes, 10)

 -- NO: tutup popup saja
 btnNo.MouseButton1Click:Connect(function()
 pcall(function() popupGui:Destroy() end)
 end)

 -- YES: stop semua fitur lalu destroy GUI
 btnYes.MouseButton1Click:Connect(function()
 pcall(function() popupGui:Destroy() end)
 -- [v238 FIX] Stop semua fitur sebelum destroy GUI
 pcall(function() if StopRaid then StopRaid() end end)
 pcall(function()
 if SIEGE then
 SIEGE.running = false
 SIEGE.inMap = false
 if SIEGE.thread then
 pcall(function() task.cancel(SIEGE.thread) end)
 SIEGE.thread = nil
 end
 end
 end)
 pcall(function()
 if MA then
 MA.running = false
 if MA.thread then
 pcall(function() task.cancel(MA.thread) end)
 MA.thread = nil
 end
 end
 end)
 -- Stop Merge Potion loop
 pcall(function()
 if _mergeRunning ~= nil then _mergeRunning = false end
 if _mergeThread ~= nil then
 pcall(function() task.cancel(_mergeThread) end)
 _mergeThread = nil
 end
 end)
 -- Stop Use Potion loop
 pcall(function()
 if _useRunning ~= nil then _useRunning = false end
 if _useThread ~= nil then
 pcall(function() task.cancel(_useThread) end)
 _useThread = nil
 end
 end)
 _raidOn = false
 _raidInterrupt = false
 _siegeInterrupt = false
 MODE.current = "idle" -- [v252] hard reset MODE dispatcher
 -- Destroy semua GUI ASH
 for _, gname in ipairs({"ASH_NightFrost","ASH_GUI","ASH_DD"}) do
 pcall(function()
 local g = LP.PlayerGui:FindFirstChild(gname)
 if g then g:Destroy() end
 end)
 end
 end)
 end)
end
BuildTopBar()

-- ============================================================
-- USER PROFILE SECTION (v273)
-- ============================================================
local function CreateUserProfile(parent)
    local profileFrame = Frame(parent, C.BLACK, UDim2.new(1, -12, 0, 50))
    profileFrame.Position = UDim2.new(0, 6, 1, -56)
    profileFrame.BackgroundTransparency = 0.8
    Corner(profileFrame, 8)
    
    local img = New("ImageLabel", {
        Parent = profileFrame,
        Size = UDim2.new(0, 36, 0, 36),
        Position = UDim2.new(0, 7, 0.5, -18),
        BackgroundColor3 = C.BLACK,
        BackgroundTransparency = 0.5,
        Image = "rbxassetid://0", -- Placeholder
        BorderSizePixel = 0
    })
    Corner(img, 18) -- Bulat sempurna
    New("UIStroke", {Parent = img, Color = C.ACC2, Thickness = 1, Transparency = 0.5})

    local nameLbl = Label(profileFrame, LP.DisplayName, 11, C.ACC2, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
    nameLbl.Size = UDim2.new(1, -50, 0, 14)
    nameLbl.Position = UDim2.new(0, 50, 0, 10)
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

    local userLbl = Label(profileFrame, "@"..LP.Name, 9, C.DIM, Enum.Font.GothamMedium, Enum.TextXAlignment.Left)
    userLbl.Size = UDim2.new(1, -50, 0, 12)
    userLbl.Position = UDim2.new(0, 50, 0, 24)
    userLbl.TextTruncate = Enum.TextTruncate.AtEnd

    local execName = "Unknown"
    pcall(function() execName = identifyexecutor() or "Executor" end)
    local idLbl = Label(profileFrame, "ID: "..LP.UserId.." | "..execName, 8, C.DIM, Enum.Font.GothamMedium, Enum.TextXAlignment.Left)
    idLbl.Size = UDim2.new(1, -50, 0, 10)
    idLbl.Position = UDim2.new(0, 50, 0, 36)
    idLbl.TextTransparency = 0.4
    idLbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- Load Thumbnail asinkron
    task.spawn(function()
        local content, isReady = Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
        if isReady then img.Image = content end
    end)
end

-- ============================================================
-- BODY & SIDEBAR
-- ============================================================
local SIDEBAR_W = _isSmallScreen and 72 or 100

Body = Frame(Window, C.BG, UDim2.new(1,0,1,-44))
Body.Position = UDim2.new(0,0,0,44)
Body.Active = false

local SideBar = Frame(Body, C.SIDEBAR, UDim2.new(0, SIDEBAR_W, 1, 0))
local SideScroll = New("ScrollingFrame", {
 Parent = SideBar, Size = UDim2.new(1,0,1,-65), Position = UDim2.new(0,0,0,4),
 BackgroundTransparency = 1, BorderSizePixel = 0,
 ScrollBarThickness = _isSmallScreen and 4 or 2, ScrollBarImageColor3 = C.ACC,
 CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
ListLayout(SideScroll, nil, Enum.HorizontalAlignment.Center, 2)
Padding(SideScroll, 4, 4, 4, 4)

-- Render Profile Section di bawah SideBar
CreateUserProfile(SideBar)

ContentFrame = Frame(Body, C.BLACK, UDim2.new(1,-SIDEBAR_W,1,0))
ContentFrame.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
ContentFrame.BackgroundTransparency = 1

-- ============================================================
-- TAB SYSTEM
-- ============================================================
local NAV_ITEMS = {
 {tag="main", ico="", lbl="Main"},
 {tag="farm", ico="", lbl="Farm"},
 {tag="autoraid", ico="", lbl="Automation"},
 {tag="player", ico="", lbl="Player"},
 {tag="autoroll", ico="", lbl="Reroll"},
 {tag="claim", ico="", lbl="Claim"},
 {tag="settings", ico="", lbl="Settings"},
 {tag="theme", ico="", lbl="Theme"},
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
 Padding(p, 10, 8, 10, 8)
 Panels[tag] = p; return p
end

function SwitchTab(tag)
 if ActiveTab == tag then return end
 ActiveTab = tag
 for t, p in pairs(Panels) do p.Visible = (t == tag) end
 for _, ref in ipairs(NavRefs) do
 local sel = ref.tag == tag
 -- Bubble selected: oranye solid + teks putih tebal
 -- Bubble unselected: oranye gelap semi-transparan + teks putih muda
 TweenService:Create(ref.bg, TweenInfo.new(0.15), {
 BackgroundTransparency = sel and 0.18 or 0.72,
 BackgroundColor3 = sel and C.SURFACE or C.BLACK,
 }):Play()
 ref.lbl.TextColor3 = sel and C.ACC2 or C.DIM
 ref.lbl.Font = sel and Enum.Font.GothamBold or Enum.Font.GothamBold
 local s = ref.bg:FindFirstChildWhichIsA("UIStroke")
 if sel then
 if not s then
 New("UIStroke", {Parent = ref.bg, Color = C.ACC2, Thickness = 1.5, Transparency = 0})
 else
 s.Color = C.ACC2; s.Thickness = 1.5; s.Transparency = 0
 end
 else
 if s then s:Destroy() end
 end
 end
end

for i, item in ipairs(NAV_ITEMS) do
 -- Bubble style: rounded pill, center text, no icon
 local bg = Btn(SideScroll, C.BLACK, UDim2.new(1,-6,0,32))
 bg.LayoutOrder = i
 bg.BackgroundTransparency = 1
 bg.AutoButtonColor = false
 Corner(bg, 10) -- Night Frost: slight round corners
 -- Dummy bar (tidak ditampilkan, tetap ada untuk kompatibilitas SwitchTab)
 local bar = Frame(bg, C.SIDEBAR, UDim2.new(0,0,0,0))
 bar.BackgroundTransparency = 1
 -- Label: full width, center aligned, tidak truncate
 local lblL = Label(bg, item.lbl, 11, C.DIM, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
 lblL.Size = UDim2.new(1,0,1,0)
 lblL.Position = UDim2.new(0,0,0,0)
 lblL.TextScaled = false
 lblL.TextWrapped = false
 lblL.TextTruncate = Enum.TextTruncate.None
 -- Dummy ico label (kompatibilitas SwitchTab)
 local icoL = Label(bg, "", 1, C.TXT, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
 icoL.Size = UDim2.new(0,0,0,0)
 icoL.BackgroundTransparency = 1
NavRefs[i] = {tag=item.tag, bg=bg, bar=bar, ico=icoL, lbl=lblL}
 bg.MouseButton1Click:Connect(function() SwitchTab(item.tag) end)
end

-- ============================================================
-- THEME ENGINE (VFX & COLORS)
-- ============================================================
local function CleanupVFX()
    for _, v in ipairs(Window:GetChildren()) do
        if v.Name == "VFX" or v:IsA("UIGradient") then
            v:Destroy()
        end
    end
end

local function SpawnVFXParticle(config)
    if _G.PotatoMode then return end
    local p = Instance.new("Frame")
    p.Name = "VFX"
    p.Size = config.Size or UDim2.fromOffset(4, 4)
    p.Position = config.StartPos
    p.BackgroundColor3 = config.Color
    p.BorderSizePixel = 0
    p.ZIndex = 10
    p.Parent = Window
    if config.Shape == "Circle" then Corner(p, 100) end
    if config.Rotation then p.Rotation = config.Rotation end

    local tween = TweenService:Create(p, TweenInfo.new(config.Duration, config.Easing or Enum.EasingStyle.Sine), {
        Position = config.EndPos,
        BackgroundTransparency = 1,
        Rotation = config.EndRotation or p.Rotation
    })
    tween:Play()
    tween.Completed:Connect(function() p:Destroy() end)
end

function ApplyTheme(name)
    local p = ThemePalettes[name]
    if not p then return end
    _G.CurrentTheme = name
    CleanupVFX()

    -- Phase 1: Color Tweens
    local ti = TweenInfo.new(0.6, Enum.EasingStyle.Exponential)
    TweenService:Create(Window, ti, {BackgroundColor3 = p.BG, BackgroundTransparency = _G.ThemeTransparency}):Play()
    
    -- Update UI Colors for future elements
    C.BG = p.BG; C.ACC = p.Accent; C.TXT = p.Text
    C.SURFACE = p.BG:Lerp(Color3.new(1,1,1), 0.05)
    C.ACC2 = p.Accent:Lerp(Color3.new(1,1,1), 0.2)
    C.DIM = p.Text:Lerp(p.BG, 0.4)

    -- Phase 2: VFX
    if _G.PotatoMode then return end
    
    task.spawn(function()
        local myTheme = name
        while _G.CurrentTheme == myTheme and not _G.PotatoMode do
            if name == "Rengoku Kyojuro" then
                if not Window:FindFirstChildWhichIsA("UIGradient") then
                    local g = Instance.new("UIGradient", Window)
                    g.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,0)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,100,0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255,200,0))})
                    task.spawn(function() 
                        while _G.CurrentTheme == myTheme and g.Parent and not _G.PotatoMode do 
                            TweenService:Create(g, TweenInfo.new(1.5, Enum.EasingStyle.Linear), {Offset = Vector2.new(1, 0)}):Play()
                            task.wait(1.5)
                            g.Offset = Vector2.new(-1, 0)
                        end 
                    end)
                end
                SpawnVFXParticle({StartPos = UDim2.new(math.random(),0,1,0), EndPos = UDim2.new(math.random(),0,0,-50), Color = Color3.fromRGB(255,math.random(50,150),0), Size = UDim2.fromOffset(math.random(3,6),math.random(3,6)), Duration = math.random(1,2), Shape = "Circle"})
                task.wait(0.2)
            elseif name == "Nezuko" then
                SpawnVFXParticle({StartPos = UDim2.new(math.random(),0,-0.1,0), EndPos = UDim2.new(math.random()+0.2,0,1.1,0), Color = Color3.fromRGB(255,182,193), Size = UDim2.fromOffset(8,4), Duration = 4, Rotation = 45, EndRotation = 180})
                task.wait(0.5)
            elseif name == "Kanroji Mitsuri" then
                SpawnVFXParticle({StartPos = UDim2.new(math.random(),0,-0.1,0), EndPos = UDim2.new(math.random(),0,1.1,0), Color = math.random() > 0.5 and Color3.fromRGB(255,182,193) or Color3.fromRGB(191,255,0), Size = UDim2.fromOffset(6,6), Duration = 3, Shape = "Circle"})
                task.wait(0.4)
            elseif name == "Tokito Muichiro" then
                SpawnVFXParticle({StartPos = UDim2.new(-0.1,0,math.random(),0), EndPos = UDim2.new(1.1,0,math.random(),0), Color = Color3.fromRGB(0, 128, 128), Size = UDim2.fromOffset(math.random(20,50), 2), Duration = 5, BackgroundTransparency = 0.6})
                task.wait(0.8)
            elseif name == "Shinazugawa Sanemi" then
                SpawnVFXParticle({StartPos = UDim2.new(1.1,0,math.random(),0), EndPos = UDim2.new(-0.1,0,math.random()+0.2,0), Color = Color3.fromRGB(85, 107, 47), Size = UDim2.fromOffset(12, 2), Duration = 1.5, Rotation = math.random(-30,30)})
                task.wait(0.25)
            elseif name == "Muzan" then
                local b = Instance.new("Frame", Window); b.Name = "VFX"; b.Size = UDim2.fromOffset(15,15); b.Position = UDim2.new(math.random(),0,math.random(),0); b.BackgroundColor3 = Color3.fromRGB(139,0,0); b.BackgroundTransparency = 0.3; Corner(b, 10); TweenService:Create(b, TweenInfo.new(1.5), {Size = UDim2.fromOffset(0,0), BackgroundTransparency = 1, Rotation = 180}):Play(); task.delay(1.5, function() b:Destroy() end)
                task.wait(0.6)
            elseif name == "Naruto" then
                SpawnVFXParticle({StartPos = UDim2.new(math.random(),0,1,0), EndPos = UDim2.new(math.random(),0,0,-50), Color = Color3.fromRGB(255,100,0), Size = UDim2.fromOffset(5,5), Duration = 2, Shape = "Circle"})
                task.wait(0.4)
            elseif name == "Sasuke" then
                local l = Instance.new("Frame", Window); l.Name = "VFX"; l.Size = UDim2.new(0,2,0,math.random(40,120)); l.Position = UDim2.new(math.random(),0,math.random(),0); l.Rotation = math.random(0,360); l.BackgroundColor3 = Color3.fromRGB(100,200,255); l.BorderSizePixel = 0; l.ZIndex = 10; task.delay(0.1, function() l:Destroy() end)
                task.wait(math.random(0.5, 1.5))
            elseif name == "One Piece" then
                SpawnVFXParticle({StartPos = UDim2.new(math.random(),0,-0.1,0), EndPos = UDim2.new(math.random(),0,1.1,0), Color = Color3.fromRGB(255,215,0), Size = UDim2.fromOffset(6,6), Duration = 3, Shape = "Circle"})
                task.wait(0.5)
            elseif name == "Dragon Ball" then
                SpawnVFXParticle({StartPos = UDim2.new(math.random(),0,1,0), EndPos = UDim2.new(math.random(),0,0,-50), Color = Color3.fromRGB(255,255,0), Size = UDim2.fromOffset(4,15), Duration = 1, Easing = Enum.EasingStyle.Exponential})
                task.wait(0.2)
            elseif name == "One Punch Man" then
                SpawnVFXParticle({StartPos = UDim2.new(0.5,0,0.5,0), EndPos = UDim2.new(math.random(),0,math.random(),0), Color = Color3.fromRGB(255,0,0), Size = UDim2.fromOffset(10,2), Duration = 0.5, Easing = Enum.EasingStyle.Quad})
                task.wait(0.1)
            elseif name == "Jujutsu Kaisen" then
                local b = Instance.new("Frame", Window); b.Name = "VFX"; b.Size = UDim2.fromOffset(20,20); b.Position = UDim2.new(math.random(),0,math.random(),0); b.BackgroundColor3 = Color3.fromRGB(150,0,255); b.BackgroundTransparency = 0.5; Corner(b, 10); TweenService:Create(b, TweenInfo.new(1), {Size = UDim2.fromOffset(0,0), BackgroundTransparency = 1}):Play(); task.delay(1, function() b:Destroy() end)
                task.wait(0.8)
            elseif name == "Zenitsu" or name == "Demon Slayer" then
                local l = Instance.new("Frame", Window); l.Name = "VFX"; l.Size = UDim2.new(math.random(),0,0,1); l.Position = UDim2.new(0,0,math.random(),0); l.BackgroundColor3 = Color3.fromRGB(255,255,0); task.delay(0.1, function() l:Destroy() end)
                task.wait(1.5)
            elseif name == "Windows 11" or name == "MacOS" or name == "iPhone" then
                if not Window:FindFirstChildWhichIsA("UIGradient") then
                    local g = Instance.new("UIGradient", Window)
                    g.Color = ColorSequence.new(p.BG, p.Accent)
                    task.spawn(function() while _G.CurrentTheme == myTheme and g.Parent do TweenService:Create(g, TweenInfo.new(5, Enum.EasingStyle.Sine), {Offset = Vector2.new(0.5, 0)}):Play(); task.wait(5); TweenService:Create(g, TweenInfo.new(5, Enum.EasingStyle.Sine), {Offset = Vector2.new(-0.5, 0)}):Play(); task.wait(5) end end)
                end
                task.wait(2)
            else
                -- Generic Flowing Gradient for all other themes
                if not Window:FindFirstChildWhichIsA("UIGradient") then
                    local g = Instance.new("UIGradient", Window)
                    g.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, p.BG), ColorSequenceKeypoint.new(0.5, p.Accent), ColorSequenceKeypoint.new(1, p.BG)})
                    task.spawn(function() while _G.CurrentTheme == myTheme and g.Parent do TweenService:Create(g, TweenInfo.new(4, Enum.EasingStyle.Linear), {Rotation = 360}):Play(); task.wait(4); g.Rotation = 0 end end)
                end
                task.wait(1)
            end
        end
    end)
end

-- ============================================================
-- PANEL HELPERS
-- ============================================================
function SectionHeader(panel, title, order)
 local f = Frame(panel, C.BLACK, UDim2.new(1,0,0,20))
 f.BackgroundTransparency = 1; f.LayoutOrder = order or 0
 local l = Label(f, " "..title, 13, C.TXT, Enum.Font.GothamBold)
 l.Size = UDim2.new(1,0,1,0)
 local line = Frame(f, C.ACC, UDim2.new(1,0,0,1))
 line.Position = UDim2.new(0,0,1,-1); line.BackgroundTransparency = 0.42
end

function ToggleRow(panel, title, desc, order, onToggle)
 -- desc tidak ditampilkan (V139: clean toggle, nama fitur saja)
 local row = Frame(panel, C.SURFACE, UDim2.new(1,0,0,44))
 row.LayoutOrder = order or 1; Corner(row, 10); Stroke(row, C.BORD, 1.5, 0.88)
 local lbl = Label(row, title, 13, C.TXT, Enum.Font.GothamBold)
 lbl.Size = UDim2.new(1,-68,0,20); lbl.Position = UDim2.new(0,14, 0.5, -10)
 local pill = Btn(row, C.PILL_OFF, UDim2.new(0,52,0,30))
 pill.AnchorPoint = Vector2.new(1, 0.5)
 pill.Position = UDim2.new(1,-12,0.5,0); Corner(pill, 15)
 local knob = Frame(pill, C.KNOB_OFF, UDim2.new(0,24,0,24))
 knob.AnchorPoint = Vector2.new(0, 0.5)
 knob.Position = UDim2.new(0,3,0.5,0); Corner(knob, 12)
 local state = false
 local function SetState(v)
 state = v
 TweenService:Create(pill, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {BackgroundColor3 = v and C.PILL_ON or C.PILL_OFF}):Play()
 TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
 Position = v and UDim2.new(1,-27,0.5,0) or UDim2.new(0,3,0.5,0),
 BackgroundColor3 = v and C.KNOB_ON or C.KNOB_OFF,
 }):Play()
 if onToggle then onToggle(v) end
 end
 pill.MouseButton1Click:Connect(function() SetState(not state) end)
 return row, SetState
end

function SliderRow(panel, title, min, max, default, onMove)
    local row = Frame(panel, C.SURFACE, UDim2.new(1,0,0,52))
    row.LayoutOrder = 1; Corner(row, 10); Stroke(row, C.BORD, 1.5, 0.88)
    local lbl = Label(row, title, 13, C.TXT, Enum.Font.GothamBold)
    lbl.Size = UDim2.new(1,-20,0,20); lbl.Position = UDim2.new(0,14, 0, 6)
    
    local bar = Frame(row, C.BLACK, UDim2.new(1,-28,0,6))
    bar.Position = UDim2.new(0.5,0,0,36); bar.AnchorPoint = Vector2.new(0.5,0)
    Corner(bar, 3)
    
    local fill = Frame(bar, C.ACC, UDim2.new((default-min)/(max-min), 0, 1, 0))
    Corner(fill, 3)
    
    local knob = Btn(bar, C.TXT, UDim2.new(0,14,0,14))
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new((default-min)/(max-min), 0, 0.5, 0)
    Corner(knob, 7)
    
    local valLbl = Label(row, tostring(default), 11, C.DIM, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
    valLbl.Position = UDim2.new(1,-25,0,6)

    local dragging = false
    local function Update(input)
        local pos = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        knob.Position = UDim2.new(pos, 0, 0.5, 0)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        local val = math.floor(min + (pos * (max - min)))
        valLbl.Text = tostring(val)
        if onMove then onMove(val) end
    end
    
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            Update(input)
        end
    end)
    return row
end

-- ============================================================
-- STATE & LOOPS
-- ============================================================
STATE = {autoCollect=false, autoDestroyer=false, autoArise=false, noClip=false, antiAfk=false, autoConfirm=false, autoClose=false}
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
 running = false,
 inMap = false,
 thread = nil,
 sukses = 0,
 collected = 0,
 raidId = 0,
 raidMapId = 50001,
 slotIndex = 2,
 fromMapId = nil,
 serverMapId = nil,
 _raidDone = false,

 statusLbl = nil,
 suksesLbl = nil,
 dot = nil,
 difficulty = "easy",
 pickMode = "default",
 snapshotMapId = nil,
}
_raidOn = false

-- ============================================================
-- [v252] MODE DISPATCHER - Single source of truth
-- ============================================================
MODE = {
 current = "idle", -- "idle"|"ma"|"raid"|"siege"
 priority = { siege=3, raid=2, ma=1, idle=0 },
 _prev = {}, -- stack: simpan mode yang diinterrupt, untuk resume
}

function MODE:_p(name)
 return self.priority[name] or 0
end

function MODE:IsHigherPriority(incoming)
 return self:_p(incoming) > self:_p(self.current)
end

-- Request: boleh masuk kalau slot kosong ATAU priority lebih tinggi
function MODE:Request(name)
 if self.current == "idle" or self:IsHigherPriority(name) then
 self.current = name
 return true
 end
 return false
end

-- Release: hanya release kalau kamu yang pegang
function MODE:Release(name)
 if self.current == name then
 self.current = "idle"
 end
end

-- ForceSet: override tanpa cek (untuk dungeon yang priority max)
function MODE:ForceSet(name)
 self.current = name
end

-- WaitAndRequest: tunggu sampai bisa masuk (timeout detik)
-- Kembalikan true kalau berhasil, false kalau timeout
function MODE:WaitAndRequest(name, timeout)
 local t = 0
 local limit = timeout or 30
 while not self:Request(name) and t < limit do
 task.wait(0.5); t = t + 0.5
 end
 return self.current == name
end

--  Alias getter (baca-saja) 
-- ============================================================

_raidInterrupt = false -- true saat raid muncul & Mass Attack harus pause
local _lastBossGuid = nil -- guid boss terakhir untuk ExtraReward auto-claim
_siegeInterrupt = false -- true saat siege pakai remote -> raid pause
local _gainRaidsLock = false -- flag cegah infinite loop di hook GainRaidsRewards
_webhookEnabled = false
_webhookUrl = ""
_whSilent = false -- true saat scan history awal (jangan fire webhook duplikat)
-- [v129] Sistem cooldown + pending webhook (dari V117)

-- ============================================================
-- AUTO CONFIRM / AUTO CLOSE
-- Scan GUI tiap 0.3s, cari button Confirm/Close
-- Panggil callback via Activated:Fire() sebagai fallback Delta
-- ============================================================
_popupThread, _popupRunning = nil, false

-- ============================================================
-- ANIMATION SNIFFER [v264]
-- ============================================================
-- ANIMATION DISABLER [v264 FIX: ULTRA AGGRESSIVE]
-- ============================================================
local function StopTracks(animator)
    if not animator or not _G.DisableAnimations then return end
    pcall(function()
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            track:Stop(0)
        end
    end)
end

local function MonitorAnimator(animator)
    if not animator:IsA("Animator") then return end
    
    -- Stop existing
    StopTracks(animator)
    
    -- Stop new
    animator.AnimationPlayed:Connect(function(track)
        if _G.DisableAnimations then
            pcall(function() track:Stop(0) end)
        end
    end)
end

function StopAllWorkspaceAnimations()
    if not _G.DisableAnimations then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Animator") then
            StopTracks(obj)
        end
    end
end

task.spawn(function()
    -- Scan existing animators
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Animator") then
            task.spawn(MonitorAnimator, obj)
        end
    end
    
    -- Watch for new animators (Players & NPCs)
    workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Animator") then
            task.spawn(MonitorAnimator, obj)
        end
    end)

    -- Pantau Player (Fallback)
    game.Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function(char)
            local hum = char:WaitForChild("Humanoid", 10)
            if hum then
                local animator = hum:WaitForChild("Animator", 10)
                if animator then MonitorAnimator(animator) end
            end
        end)
    end)

    -- [v264] Fast Loop Fallback: Paksa stop setiap 1 detik jika toggle ON
    -- Ini untuk menangkap animasi yang mungkin bypass listener (jarang tapi mungkin)
    task.spawn(function()
        while true do
            task.wait(1)
            if _G.DisableAnimations then
                StopAllWorkspaceAnimations()
            end
        end
    end)
end)

local POPUP_CONFIRM_KEYS = {"confirm", "ok", "yes", "continue", "proceed", "accept"}
local POPUP_CLOSE_KEYS = {"close", "cancel", "cancel", "exit", "dismiss", "skip", "no"}
-- GUI yang TIDAK boleh di-auto-click apapun (online reward, daily login, dll)
local POPUP_GUI_BLACKLIST = {
 ["OnlineRewardPanel"] = true,
 ["OnlineReward"] = true,
 ["DailyReward"] = true,
 ["DailyLogin"] = true,
}

-- Popup scanner hanya akan scan ScreenGui yang muncul SETELAH game load
-- dan bukan termasuk GUI persistent milik game.
-- Pendekatan: cek apakah parent ScreenGui-nya "baru muncul" (bukan persistent)
-- Persistent GUI game biasanya sudah ada sejak awal - kita skip semua yang
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
 if obj:IsA("TextButton") and obj.Visible and obj.Text ~= "" and not _isIgnored(obj) then
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
 _popupThread = nil
 end)
end


RAID.autoKillBoss = false -- toggle: teleport ke raja + auto attack sampai mati
RAID.bossDelay = 3 -- detik delay sebelum TP ke boss (1-10, user-controlled)

_maStatusLbl, _noClipConn, _antiAfkThread, _antiAfkStart = nil, nil, nil, nil
local _deadG, _mOn, _agOn, _tgtThread = {}, false, false, nil
local _activeTbnRow = nil -- [v188-FIX] track row tbn yang sedang aktif
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
 MR.lastMapId = m.id -- simpan map terakhir sebelum masuk raid
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
 key_map = {Z=Enum.KeyCode.Z,X=Enum.KeyCode.X,C=Enum.KeyCode.C,V=Enum.KeyCode.V,F=Enum.KeyCode.F},
 ui = {},
}
-- SKL_TYPE, SKL_KEY, SKL_UI merged into SKL table below
-- Simulasi tekan tombol keyboard via VirtualInputManager (sama seperti script lama)
function PK(k)
 pcall(function()
 VIM:SendKeyEvent(true, k, false, game)
 task.wait(0.05)
 VIM:SendKeyEvent(false, k, false, game)
 end)
end

-- Referensi tombol UI skill (diisi saat panel dibuat)
-- SKL_UI merged into SKL table

function SkFireOnce(n)
 -- Simulasi tekan tombol Z/X/C/V/F langsung via VirtualInputManager
 -- Sama persis seperti player menekan tombol sendiri - tidak butuh enemyGuid
 PK(SKL.key_map[n])
end

function SkSetUI(n, on)
 local u = SKL.ui[n]
 if not u then return end
 -- ON: latar oranye terang, teks warna skill
 -- OFF: latar oranye gelap (C.BG3), teks putih
 u.btn.BackgroundColor3 = on and Color3.fromRGB(180,65,5) or C.BG3
 u.lbl.Text = on and "ON" or "OFF"
 u.lbl.TextColor3 = on and Color3.fromRGB(255,255,255) or C.TXT
 -- Stroke terang saat ON
 local stk = u.btn:FindFirstChildWhichIsA("UIStroke")
 if stk then stk.Color = on and C.ACC2 or C.BORD; stk.Transparency = on and 0 or 0.3 end
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

--  Keyboard listener: tekan Z/X/C/V/F untuk toggle skill 
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
 -- Cek semua folder yang mungkin berisi enemy (normal + siege)
 local ENEMY_FOLDERS = {"Enemys", "EnemyCityRaid", "CityRaidEnemys", "Enemies"}
 local seen = {}
 for _, folderName in ipairs(ENEMY_FOLDERS) do
 local f = workspace:FindFirstChild(folderName)
 if f then
 for _, e in ipairs(f:GetChildren()) do
 if e:IsA("Model") then
 local g = e:GetAttribute("EnemyGuid")
 local h = e:FindFirstChild("HumanoidRootPart")
 local hum = e:FindFirstChildOfClass("Humanoid")
 if g and h and hum and hum.Health > 0 and not seen[g] then
 seen[g] = true
 table.insert(list, {model=e, guid=g, hrp=h})
 end
 end
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

-- [FIX v242] Satu dedicated hero attack thread mengurus type 1+2+3
-- Interval tetap 0.5s antar siklus penuh - tidak overflow AnimationTrack limit 64
-- FireAllDamage hanya update target, tidak fire hero langsung
-- RE.Atk & RE.Click tetap sync karena itu attack player bukan hero
local _heroAtkTarget = nil -- guid target hero saat ini
local _heroAtkThread = nil -- thread hero attack
local _heroAtkTick = 0 -- tick() siklus terakhir

-- [v256-FIX] Helper: validasi enemy guid masih punya HumanoidRootPart yang valid
local function IsEnemyGuidValid(g)
 if not g then return false end
 local ENEMY_FOLDERS = {"Enemys", "EnemyCityRaid", "CityRaidEnemys", "Enemies", "Enemy"}
 for _, folderName in ipairs(ENEMY_FOLDERS) do
  local f = workspace:FindFirstChild(folderName)
  if f then
   for _, e in ipairs(f:GetChildren()) do
    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
     local hrp = e:FindFirstChild("HumanoidRootPart")
     local hum = e:FindFirstChildOfClass("Humanoid")
     if hrp and hum and hum.Health > 0 then
      return true
     end
     return false
    end
   end
  end
 end
 -- Fallback: cek CityRaidEnter (enemy Siege nested di sini)
 pcall(function()
  local mapF = workspace:FindFirstChild("Map")
  local cre = mapF and mapF:FindFirstChild("CityRaidEnter")
  if cre then
   for _, e in ipairs(cre:GetDescendants()) do
    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
     local hrp = e:FindFirstChild("HumanoidRootPart")
     local hum = e:FindFirstChildOfClass("Humanoid")
     if hrp and hum and hum.Health > 0 then
      return true
     end
    end
   end
  end
 end)
 return false
end

local function EnsureHeroAtkThread()
 if _heroAtkThread then return end
 _heroAtkThread = task.spawn(function()
  local _lastFire = {}
  while ScreenGui and ScreenGui.Parent do
   local g = _heroAtkTarget
   if g and #HERO_GUIDS > 0 and (tick() - _heroAtkTick) >= 0.5 and IsEnemyGuidValid(g) then
    _heroAtkTick = tick()
    for _, hGuid in ipairs(HERO_GUIDS) do
     local last = _lastFire[hGuid] or 0
     if (tick() - last) >= 0.5 then
      _lastFire[hGuid] = tick()
      if RE.HeroUseSkill then
       pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
       task.wait(0.1)
       if not IsEnemyGuidValid(g) then break end
       pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=2,userId=MY_USER_ID,enemyGuid=g}) end)
       task.wait(0.1)
       if not IsEnemyGuidValid(g) then break end
       pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=3,userId=MY_USER_ID,enemyGuid=g}) end)
      end
     end
     task.wait(0.05)
    end
   end
   task.wait(0.05)
  end
  _heroAtkThread = nil
 end)
end

local _skillTarget = nil
local function EnsureSkillThread() EnsureHeroAtkThread() end

local _heroFireTick = {}
function FireAttack(g, pos)
 if not g then return end
 if RE.Atk then pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end) end
 if RE.HeroUseSkill and #HERO_GUIDS > 0 then
  local now = tick()
  local last = _heroFireTick[g] or 0
  if now - last >= 0.4 then
   _heroFireTick[g] = now
   for _, hGuid in ipairs(HERO_GUIDS) do
    pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
    pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=2,userId=MY_USER_ID,enemyGuid=g}) end)
   end
  end
 end
end

function FireAllDamage(g, ep)
 if not IsEnemyGuidValid(g) then return end
 if RE.Click then
  task.spawn(function()
   pcall(function() RE.Click:InvokeServer({enemyGuid=g, enemyPos=ep}) end)
  end)
 end
 if RE.Atk then
  pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
 end
 _heroAtkTarget = g
 _skillTarget = g
 EnsureHeroAtkThread()
 if not RE.HeroUseSkill and RE.HeroSkill then
  for _, hGuid in ipairs(HERO_GUIDS) do
   pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=1,masterId=MY_USER_ID}) end)
  end
 end
end

function FireHeroRemotes(enemyGuid, enemyPos)
 local pos = enemyPos or Vector3.new(0,0,0)
 if #HERO_GUIDS == 0 then return end
 local posInfos = {}
 for _, hGuid in ipairs(HERO_GUIDS) do
  table.insert(posInfos, {heroGuid=hGuid, targetPos=pos})
 end
 if RE.HeroMove then
  pcall(function() RE.HeroMove:FireServer({attackTarget=enemyGuid,userId=MY_USER_ID,heroTagetPosInfos=posInfos}) end)
 end
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
 local DROP_FOLDERS = {"Golds","Items","Drops","Rewards","Loot","DropItems","RewardItems"}
 task.spawn(function()
 local collected = {}
 while checkFn() do
 for _, folderName in ipairs(DROP_FOLDERS) do
 if not checkFn() then break end
 local folder = workspace:FindFirstChild(folderName)
 if folder then
 for _, obj in ipairs(folder:GetChildren()) do
 if not checkFn() then break end
 local guid = obj:GetAttribute("GUID")
 if guid and not collected[guid] then
 collected[guid] = true
 pcall(function() RE.CollectItem:InvokeServer(guid) end)
 pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
 if AG.running then AG.collected = AG.collected + 1 end
 if MA.running then MA.collected = (MA.collected or 0) + 1 end
 task.wait(0.03)
 end
 end
 end
 end
 task.wait(0.2)
 end
 end)
 task.spawn(function()
 local collected2 = {}
 local DROP_FOLDERS2 = {"Golds","Items","Drops","Rewards","Loot","DropItems","RewardItems"}
 local conn = workspace.DescendantAdded:Connect(function(obj)
 if not checkFn() then return end
 task.delay(0.1, function()
 if not checkFn() then return end
 local guid = obj:GetAttribute("GUID")
 if not guid or collected2[guid] then return end
 local parent = obj.Parent
 if not parent then return end
 for _, fn in ipairs(DROP_FOLDERS2) do
 if parent.Name == fn and parent.Parent == workspace then
 collected2[guid] = true
 pcall(function() RE.CollectItem:InvokeServer(guid) end)
 pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
 break
 end
 end
 end)
 end)
 while checkFn() do
     task.wait(0.5)
 end
 pcall(function() conn:Disconnect() end)
 end)
end

-- ============================================================
-- [v257] AUTO GOLD MAGNET - TP semua gold/drop ke player
-- Gold di game hanya ter-collect kalau dekat player
-- Fungsi ini TP semua item di folder Golds/Items/Drops ke posisi player
-- Dipanggil periodik selama MA/AG/Raid aktif
-- ============================================================
local _goldMagnetRunning = false
function StartGoldMagnet(checkFn)
 if _goldMagnetRunning then return end
 _goldMagnetRunning = true
 task.spawn(function()
 local GOLD_FOLDERS = {"Golds","Items","Drops","Rewards","Loot","DropItems","RewardItems"}
 while checkFn() do
 pcall(function()
 local char = LP.Character
 local hrp = char and char:FindFirstChild("HumanoidRootPart")
 if not hrp then return end
 local playerPos = hrp.Position
 for _, folderName in ipairs(GOLD_FOLDERS) do
 local folder = workspace:FindFirstChild(folderName)
 if folder then
 for _, obj in ipairs(folder:GetChildren()) do
 pcall(function()
 -- TP item ke dekat player
 if obj:IsA("BasePart") then
 obj.CFrame = CFrame.new(playerPos + Vector3.new(
 math.random(-3,3), 0, math.random(-3,3)))
 elseif obj:IsA("Model") then
 local part = obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart
 if part then
 part.CFrame = CFrame.new(playerPos + Vector3.new(
 math.random(-3,3), 0, math.random(-3,3)))
 end
 end
 -- Juga coba collect via remote (double layer)
 local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid")
 if guid then
 pcall(function() RE.CollectItem:InvokeServer(guid) end)
 end
 end)
 end
 end
 end
 end)
 task.wait(0.5)
 end
 _goldMagnetRunning = false
 end)
end

-- ============================================================
-- ATTACK LOOPS
-- ============================================================
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
 -- [v188] offset dinaikkan ke +5 agar tidak jatuh ke bawah tanah/jurang
 local safePos = result and (result.Position + Vector3.new(3, 5, 0)) or (tgt.hrp.Position + Vector3.new(3, 5, 0))
 hrp.CFrame = CFrame.new(safePos)
end

-- ============================================================
-- AUTO FUNCTIONS
-- ============================================================
function DoAutoCollect(on)
 StopLoop("collect"); COLLECTED = {}
 if not on then return end
 local _COL_FOLDERS = {"Golds","Items","Drops","Rewards","Loot","DropItems","RewardItems"}
 StartLoop("collect", function()
 while STATE.autoCollect do
 for _, folderName in ipairs(_COL_FOLDERS) do
 if not STATE.autoCollect then break end
 local folder = workspace:FindFirstChild(folderName)
 if folder then
 for _, obj in ipairs(folder:GetChildren()) do
 if not STATE.autoCollect then break end
 local guid = obj:GetAttribute("GUID")
 if guid and not COLLECTED[guid] then
 COLLECTED[guid] = true
 pcall(function() RE.CollectItem:InvokeServer(guid) end)
 pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
 task.wait(0.03)
 end
 end
 end
 end
 task.wait(0.2)
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
 if guid then pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end) end
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
 if guid then pcall(function() RE.ExtraReward:FireServer({isSell=false, isAuto=false, guid=guid}) end) end
 end)
end

function RefreshStatus()
 local map = {
 collect = {STATE.autoCollect, "Auto Collect Gold"},
 destroyer = {STATE.autoDestroyer, "Auto Destroyer"},
 arise = {STATE.autoArise, "Auto Arise"},
 noClip = {STATE.noClip, "NO CLIP"},
 antiAfk = {STATE.antiAfk, "ANTI AFK"},
 }
 for key, data in pairs(map) do
 local active, label = data[1], data[2]
 if StatusDots[key] then
 StatusDots[key].BackgroundColor3 = active and Color3.fromRGB(80,220,80) or Color3.fromRGB(100,100,100)
 end
 if StatusLbls[key] then
 StatusLbls[key].Text = label..(active and " - ON" or " - OFF")
 StatusLbls[key].TextColor3 = active and C.ACC2 or C.TXT2
 end
 end
end

-- [v257] WaitRaidDone - MA pause HANYA saat player di dalam raid map
-- Kalau raid loop aktif tapi lagi "waiting raid berikutnya" -> MA JALAN
-- Kalau raid loop aktif DAN player di dalam raid map -> MA PAUSE
function WaitRaidDone()
 local t = 0
 local function shouldPause()
  -- [FIX] Kalau RAID tidak running sama sekali, jangan pause
  if not RAID.running then return false, nil end

  -- Siege: [INDEPENDEN] siege tidak pause MA

  -- Raid: hanya pause kalau player BENAR-BENAR di dalam map raid
  if _raidInterrupt and RAID.inMap then return true, "Auto Raid" end
  if MODE.current == "raid" and RAID.inMap then return true, "Auto Raid" end

  return false, nil
 end
 local pause, reason = shouldPause()
 while pause and MA.running do
  t = t + 0.5
  -- [FIX] Timeout 60 detik: paksa resume kalau stuck
  if t >= 60 then
   _raidInterrupt = false
   RAID.inMap = false
   _siegeInterrupt = false
   if MODE.current ~= "idle" and MODE.current ~= "ma" then
    MODE.current = "idle"
   end
   break
  end
  local label = reason or "Other Fiture"
  if _maStatusLbl then
   _maStatusLbl.Text = "[||] Pause ("..label..") - "..math.floor(t).."s"
   _maStatusLbl.TextColor3 = Color3.fromRGB(255,140,0)
  end
  task.wait(0.5)
  pause, reason = shouldPause()
 end
 if MA.running then task.wait(0.5) end
 if _maStatusLbl and MA.running then
  _maStatusLbl.Text = "> Continue After pause..."
  _maStatusLbl.TextColor3 = C.ACC3
 end
end

-- [v252] WaitSiegeDone - pakai MODE dispatcher sebagai sumber utama
function WaitSiegeDone()
    local waited = 0
    while (SIEGE and SIEGE.inMap) or _siegeInterrupt or MODE.current == "siege" do
        -- [FIX] Jika SIEGE sudah tidak running (toggle OFF), langsung break
        if not SIEGE or not SIEGE.running then
            _siegeInterrupt = false
            if MODE.current == "siege" then MODE.current = "idle" end
            MODE:Release("siege")
            if SIEGE then SIEGE.inMap = false end
            break
        end
        task.wait(0.5)
        waited = waited + 0.5
        local inSiege, _ = IsInSiegeMap()
        if not inSiege and not (SIEGE and SIEGE.inMap) then
            _siegeInterrupt = false
            if MODE.current == "siege" then MODE.current = "idle" end
            MODE:Release("siege")
            break
        end
        -- Timeout 30 detik: paksa release
        if waited >= 30 then
            _siegeInterrupt = false
            if MODE.current == "siege" then MODE.current = "idle" end
            MODE:Release("siege")
            if SIEGE then SIEGE.inMap = false end
            break
        end
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
local HALO_NAMES = {"Bronze Halo", "Gold Halo", "Diamond Halo"}
local HALO_DRAW_ID = {1, 2, 3}
HALO = {
 running = {false, false, false},
 statLbls = {nil, nil, nil},
 dotRefs = {nil, nil, nil},
 attemptLbls= {nil, nil, nil},
 toggleBtns = {nil, nil, nil},
 toggleKnobs= {nil, nil, nil},
 enOnFlags = {false, false, false},
}

--  HALO LOOP THREADS 
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
 setStatus("[.] Idle", Color3.fromRGB(160,148,135))
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
 setStatus("[R] Rolling #"..attempt.."...", Color3.fromRGB(255,200,60))

 local ok, res = pcall(function()
 return RE.RerollHalo:InvokeServer(drawId)
 end)

 if not ok then
 setStatus("[!] Error - retry...", Color3.fromRGB(255,100,60))
 task.wait(1)
 else
 setStatus("[OK] Roll #"..attempt.." DONE", Color3.fromRGB(80,220,80))
 task.wait(0.05)
 end
 end
 setStatus("[.] Idle", Color3.fromRGB(160,148,135))
 end)
end

-- ============================================================
-- ORNAMENT DATA (di-wrap dalam 1 tabel untuk hemat local slot)
-- ============================================================
_ASH_ORN = {}

_ASH_ORN.MACHINES = {
 {name="Headdress", machineId=400001},
 {name="Ornament Machine", machineId=400002},
 {name="Wealth Blessing", machineId=400003},
 {name="Shadowhunter Blessing",machineId=400004},
 {name="Primordial Blessing", machineId=400005},
 {name="Monarch Power", machineId=400006},
}

_ASH_ORN.QUIRK_LIST = {}
_ASH_ORN.QUIRK_MAP = {}
_ASH_ORN.emptyHintRefs = {} -- ref ke emptyHint label per mesin
for i = 1, #_ASH_ORN.MACHINES do
 _ASH_ORN.QUIRK_LIST[i] = {}
end


_ASH_ORN.STATE = {
 running = {false,false,false,false,false,false},
 targets = {{},{},{},{},{},{}},
 statLbls = {nil,nil,nil,nil,nil,nil},
 dotRefs = {nil,nil,nil,nil,nil,nil},
 attemptLbls = {nil,nil,nil,nil,nil,nil},
 lastLbls = {nil,nil,nil,nil,nil,nil},
 sumLbls = {nil,nil,nil,nil,nil,nil},
 toggleBtns = {nil,nil,nil,nil,nil,nil},
 toggleKnobs = {nil,nil,nil,nil,nil,nil},
 enOnFlags = {false,false,false,false,false,false},
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
 if ORN.toggleBtns[mi] then ORN.toggleBtns[mi].BackgroundColor3 = C.BG3 end
 if ORN.toggleKnobs[mi] then ORN.toggleKnobs[mi].Position = UDim2.new(0,2,0.5,-9) end
end

function _ASH_ORN.DoRoll(mi, on)
 local key = "ornroll"..mi
 ORN.running[mi] = false
 StopLoop(key)

 function setStatus(dot, txt, col)
 if ORN.dotRefs[mi] then ORN.dotRefs[mi].BackgroundColor3 = dot end
 if ORN.statLbls[mi] then ORN.statLbls[mi].Text = txt; ORN.statLbls[mi].TextColor3 = col end
 end

 if not on then
 setStatus(Color3.fromRGB(100,100,100), "[.] Idle", C.TXT2)
 if ORN.attemptLbls[mi] then ORN.attemptLbls[mi].Text = "Attempt: -" end
 if ORN.lastLbls[mi] then ORN.lastLbls[mi].Text = "Last: -" end
 return
 end

 ORN.running[mi] = true

 LOOPS[key] = task.spawn(function()
 local attempt = 0
 setStatus(Color3.fromRGB(255,200,60), "[~] START...", Color3.fromRGB(255,200,60))
 local mInfo = _ASH_ORN.MACHINES[mi]

 while ORN.running[mi] do
 if not RE.RerollOrnament then
 RE.RerollOrnament = Remotes:FindFirstChild("RerollOrnament")
 end
 if not RE.RerollOrnament then
 setStatus(Color3.fromRGB(255,80,80), "[!] RerollOrnament NOT FOUND!", Color3.fromRGB(255,80,80))
 task.wait(2); continue
 end
 attempt = attempt + 1
 setStatus(Color3.fromRGB(255,160,30), "[~] Roll #"..attempt, C.ACC2)
 if ORN.attemptLbls[mi] then
 ORN.attemptLbls[mi].Text = "Attempt: #"..attempt
 ORN.attemptLbls[mi].TextColor3 = C.TXT2
 end

 local ok, res = pcall(function()
 return RE.RerollOrnament:InvokeServer({machineId=mInfo.machineId, isAuto=false})
 end)
 if not ok then
 setStatus(Color3.fromRGB(255,80,80), "[!] Error (#"..attempt..")", Color3.fromRGB(255,80,80))
 task.wait(0.5); continue
 end

 local gotId = nil
 local gotName = ""
 if type(res) == "table" then
 --  PRIORITY 1: Format baru ornament { ornamentIds={[1]=410003}, count=1 } 
 if type(res.ornamentIds) == "table" then
 local oid = res.ornamentIds[1]
 if type(oid) == "number" and oid > 0 then
 gotId = oid
 gotName = _ASH_ORN.QUIRK_MAP[oid] or ("ID:"..tostring(oid))
 _ASH_ORN.AddQuirk(mi, oid, gotName)
 end
 end
 --  PRIORITY 2: Scan nested ornamentIds di sub-table 
 if not gotId then
 local function ScanOrnamentIds(tbl, depth)
 if depth > 4 or type(tbl) ~= "table" or gotId then return end
 if type(tbl.ornamentIds) == "table" then
 local oid = tbl.ornamentIds[1]
 if type(oid) == "number" and oid > 0 then
 gotId = oid
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
 --  PRIORITY 3: Fallback scan generic quirkId/resultId/id 
 if not gotId then
 local function ScanAndLearn(tbl, depth)
 if depth > 5 or type(tbl) ~= "table" or gotId then return end
 local id = tbl.quirkId or tbl.finalResultId or tbl.resultId or tbl.ornamentId
 local name = tbl.quirkName or tbl.name or tbl.Name or tbl.title or tbl.displayName
 if type(id) == "number" and id > 0 then
 if type(name) == "string" and #name > 0 and not name:find("^ID:") then
 _ASH_ORN.AddQuirk(mi, id, name)
 if not gotId then gotId = id; gotName = name end
 elseif not gotId then
 gotId = id
 gotName = _ASH_ORN.QUIRK_MAP[id] or ("ID:"..tostring(id))
 end
 end
 for _, v in pairs(tbl) do
 if type(v) == "table" then ScanAndLearn(v, depth+1) end
 end
 end
 ScanAndLearn(res, 0)
 end
 --  PRIORITY 4: Last resort - ambil angka pertama yang masuk akal (4xxxxx) 
 if not gotId then
 local function ScanNum(tbl, depth)
 if depth > 4 or gotId then return end
 for _, v in pairs(tbl) do
 if type(v) == "number" and v >= 400000 and v < 500000 and not gotId then
 gotId = v
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
 setStatus(Color3.fromRGB(100,100,100), "[.] STOPPED ("..attempt.."x roll)", C.TXT2)
 if ORN.attemptLbls[mi] then
 ORN.attemptLbls[mi].Text = "Attempt: "..attempt.."x"
 ORN.attemptLbls[mi].TextColor3 = C.TXT2
 end
 end)
end


_spyLog = {}
_layer0Active = false
_HR_RPT = nil -- laporan hero fastroll
_watcherConns = {}

-- ============================================================
-- DD LAYER
-- ============================================================
DDLayer = Frame(ScreenGui, C.BLACK, UDim2.new(1,0,1,0))
DDLayer.BackgroundTransparency = 1; DDLayer.ZIndex = 9998; DDLayer.Visible = false
DDLayer.Active = false
DDLayer.Name = "ASH_DD"

_activeDDClose = nil
-- Forward declare AutoRoll functions used in panels (global, cross-scope)
DoAutoRollHero = nil
InitAllCaptureLayers = nil

-- CloseActiveDD: tutup dropdown yang sedang terbuka
CloseActiveDD = function()
 if _activeDDClose then _activeDDClose(); _activeDDClose = nil end
end

-- DDLayer: klik di luar dropdown -> tutup
DDLayer.InputBegan:Connect(function(i)
 if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
 task.defer(CloseActiveDD)
 end
end)


-- DROPDOWN HELPER (shared)
-- ============================================================
MakeGenericDropdown = function(params)
 local ddBtn = params.ddBtn
 local list = params.list
 local maxSel = params.maxSel or 3
 local selTable = params.selTable
 local onRefresh = params.onRefresh
 local summaryLbl= params.summaryLbl
 local qMapRef = params.quirkMapRef or {}

 ddBtn.MouseButton1Click:Connect(function()
 CloseActiveDD()
 local absPos = ddBtn.AbsolutePosition
 local absSize = ddBtn.AbsoluteSize
 local ITEM_H = 28
 local contentH= #list * (ITEM_H + 2) + 10
 local scrollH = math.min(contentH, _isSmallScreen and 170 or 200)
 local popupW = absSize.X + 30
 local HEADER_H= 32

 local popup = Instance.new("Frame")
 popup.Parent = DDLayer; popup.BackgroundColor3 = C.DD_BG; popup.BorderSizePixel = 0
 popup.Size = UDim2.new(0, popupW, 0, HEADER_H + scrollH)
 popup.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 3)
 popup.ZIndex = 9999; popup.ClipsDescendants = true
 Corner(popup, 10); Stroke(popup, C.BORD2, 1.5, 0.2)

 local hdr = Frame(popup, C.TBAR, UDim2.new(1,0,0,HEADER_H)); hdr.ZIndex = 9999
 local countLbl = Label(hdr, "0/"..maxSel.." SELECTED", 12, C.TXT, Enum.Font.GothamBold)
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
 sfp.PaddingLeft=UDim.new(0,4); sfp.PaddingRight=UDim.new(0, 10)

 local rowRefs = {}
 function UpdateCount()
 local n = 0; for _ in pairs(selTable) do n = n + 1 end
 countLbl.Text = n.."/"..maxSel.." SELECTED"
 countLbl.TextColor3 = n >= maxSel and Color3.fromRGB(255,100,80) or C.ACC2
 end

 for _, q in ipairs(list) do
 local qRow = Btn(sf, C.DD_BG, UDim2.new(1,-8,0,ITEM_H)); qRow.ZIndex = 9999; Corner(qRow,5)
 local tBox = Frame(qRow, C.SEL_BG, UDim2.new(0,16,0,16))
 tBox.Position = UDim2.new(0,6,0.5,-8); Corner(tBox,3); tBox.ZIndex = 9999; Stroke(tBox,C.BORD2, 1.5,0.4)
 local tMark = Label(tBox,"v",11,C.BLACK,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 tMark.Size = UDim2.new(1,0,1,0); tMark.ZIndex = 9999
 local isSelected = (selTable[q.id] == true or selTable[q.name] == true)
 tMark.Visible = isSelected
 local qLbl = Label(qRow," "..(q.name or q),11,isSelected and C.ACC2 or C.TXT,Enum.Font.GothamBold)
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
 countLbl.Text = "MAX "..maxSel.." SUCCES!"; countLbl.TextColor3 = Color3.fromRGB(255,60,60)
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
do
 local p = NewPanel("main")
 -- [v186] FIX: deklarasi variabel yang hilang
 local _autoSellOn = false
 local _sellConn = nil
 local _lockedGuids = {}
 local _cnt = {R=0, Y=0, B=0, other=0, skipped=0}
 local _sellToggleCb = nil

 --  Counter laporan (DI ATAS toggle) 
 local cntCard = Frame(p, C.BG3, UDim2.new(1,0,0,0))
 cntCard.LayoutOrder=1; cntCard.AutomaticSize=Enum.AutomaticSize.Y
 Corner(cntCard, 10); Stroke(cntCard,C.BORD, 1.5,0.5)
 Padding(cntCard,4,4,8,8)
 New("UIListLayout",{Parent=cntCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)})

 local cntRow1 = Frame(cntCard,C.BG2,UDim2.new(1,0,0,28))
 cntRow1.LayoutOrder=1; Corner(cntRow1,6)
 local rLbl=Label(cntRow1,"R-Pet: 0",13,Color3.fromRGB(255,110,110),Enum.Font.GothamBold)
 rLbl.Size=UDim2.new(0.25,0,1,0); rLbl.Position=UDim2.new(0,6,0,0)
 rLbl.TextXAlignment=Enum.TextXAlignment.Left
 local yLbl=Label(cntRow1,"Y-Pet: 0",13,Color3.fromRGB(255,230,60),Enum.Font.GothamBold)
 yLbl.Size=UDim2.new(0.25,0,1,0); yLbl.Position=UDim2.new(0.25,0,0,0)
 yLbl.TextXAlignment=Enum.TextXAlignment.Center
 local bLbl=Label(cntRow1,"B-Pet: 0",13,Color3.fromRGB(100,210,255),Enum.Font.GothamBold)
 bLbl.Size=UDim2.new(0.25,0,1,0); bLbl.Position=UDim2.new(0.5,0,0,0)
 bLbl.TextXAlignment=Enum.TextXAlignment.Center
 local skipLbl=Label(cntRow1,"Supreme: 0",13,C.ACC2,Enum.Font.GothamBold)
 skipLbl.Size=UDim2.new(0.25,0,1,0); skipLbl.Position=UDim2.new(0.75,0,0,0)
 skipLbl.TextXAlignment=Enum.TextXAlignment.Right

 local resetBtn=Btn(cntCard,C.BG2,UDim2.new(1,0,0,22))
 resetBtn.LayoutOrder=2; Corner(resetBtn,6); Stroke(resetBtn,C.BORD, 1.5,0.6)
 local resetLbl=Label(resetBtn,"RESET COUTER",11,C.DIM,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 resetLbl.Size=UDim2.new(1,0,1,0)

 local function RefreshCounters()
 pcall(function()
 rLbl.Text = "R-Pet: ".._cnt.R
 yLbl.Text = "Y-Pet: ".._cnt.Y
 bLbl.Text = "B-Pet: ".._cnt.B
 skipLbl.Text = "Supreme: ".._cnt.skipped
 end)
 end
 resetBtn.MouseButton1Click:Connect(function()
 _cnt={R=0,Y=0,B=0,other=0,skipped=0}; RefreshCounters()
 SetSellStatus("[OK] DONE RESET", Color3.fromRGB(160,220,160))
 end)

 --  Disable Animation Toggle
  local _animRow, _animSet = ToggleRow(p, "DISABLE ALL ANIMATIONS", "", 2, function(on)
      _G.DisableAnimations = on
      if on then
          task.spawn(StopAllWorkspaceAnimations)
      end
  end)

 --  Toggle Auto Sell (DI BAWAH counter) 
 local _sellToggleRow, _sellToggleSet = ToggleRow(p,"AUTO SELL HERO EQUIP","Auto sell all items (except Locked)",4,function(on)
 _autoSellOn = on
 if _sellToggleCb then _sellToggleCb(on) end
 end)

 --  Status bar 
 local function SetSellStatus(msg, col)
 pcall(function()
 sellStLbl.Text = msg
 sellStLbl.TextColor3 = col or C.DIM
 sellDot.BackgroundColor3 = col or C.BG3
 end)
 end

 -- GUID name cache
 local _guidNames = {}
 local function scanGuidNames()
 pcall(function()
 local panel = PG:FindFirstChild("HeroEquipPanel")
 if not panel then return end
 for _, obj in ipairs(panel:GetDescendants()) do
 pcall(function()
 if obj.Name == "NameText" and obj:IsA("TextLabel") and #obj.Text > 0 then
 local itemName = obj.Text
 local p2 = obj.Parent
 for _ = 1, 8 do
 if not p2 then break end
 if p2:IsA("ImageButton") then
 local n = p2.Name
 if n:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
 _guidNames[n] = itemName; break
 end
 end
 p2 = p2.Parent
 end
 end
 end)
 end
 end)
 end

 -- Ambil tipe (R/Y/B) dari nama item
 local function getType(name)
 if not name or #name == 0 then return "other" end
 local f = name:sub(1,1):upper()
 if f=="R" then return "R" elseif f=="Y" then return "Y" elseif f=="B" then return "B"
 else return "other" end
 end

 -- Ambil grade dari nama item: "Y-Star Sapphire [M]" -> "M"
 -- Format: huruf/kode grade biasanya ada di awal nama setelah tipe
 -- misal "Y-Star [M+] ..." atau grade dari field data
 local function getGrade(item)
 local d = (item.data and type(item.data)=="table") and item.data or item
 -- Coba dari field grade di data
 local g = d.grade or d.Grade or d.gradeId or d.gradeType
 if g then return tostring(g):upper() end
 -- Coba parse dari nama item: cari bracket [X] atau [M+] dll
 local name = item.name or item.Name or item.itemName or d.name or ""
 local found = name:match("%[M%+%+%]") and "M++" or name:match("%[M%+%]") and "M+" or name:match("%[SS%]") and "SS" or name:match("%[([EDCBAGSNMedcbagsn])%]")
 if found then return found:upper() end
 return nil -- tidak diketahui
 end

 -- Cek apakah item harus dijual berdasarkan filter
 local function shouldSell(item, name, isLock)
 -- Rule 1: locked -> skip
 if isLock then return false, "locked" end
 -- Rule 2: Supreme -> skip
 if name and name:lower():find("supreme", 1, true) then return false, "Supreme" end
 -- Rule 3: cek tipe
 local typ = getType(name)
 if typ ~= "other" and not _sellTypes[typ] then return false, "tipe "..typ.." dimatikan" end
 -- Rule 4: cek grade
 local grade = getGrade(item)
 if grade then
 local itemRank = _SELL_GRADE_RANK[grade] or 0
 local minRank = _SELL_GRADE_RANK[_minGrade] or 1
 if itemRank >= minRank then return false, "grade "..grade.." >= min ".._minGrade end
 end
 return true, ""
 end

 local function doSell(guid, name)
 -- [v186] Confirmed SimpleSpy: DelectHeroEquips:FireServer({guid})
 local remote = Remotes:FindFirstChild("DelectHeroEquips")
 if not remote then return end
 pcall(function()
 remote:FireServer({guid})
 local prefix = getType(name)
 _cnt[prefix] = (_cnt[prefix] or 0) + 1
 RefreshCounters()
 SetSellStatus("Sold ["..((_cnt.R+_cnt.Y+_cnt.B+_cnt.other)).."] "..name:sub(1,24), Color3.fromRGB(255,160,40))
 end)
 end

 local function StartAutoSell()
 if _sellConn then pcall(function() _sellConn:Disconnect() end) end
 local updateRemote = Remotes:FindFirstChild("UpdateHeroEquip")
 if not updateRemote then SetSellStatus("[!] NOT FOUND!", C.RED); return end
 scanGuidNames()

 pcall(function()
 local lockR = Remotes:FindFirstChild("LockHeroEquip")
 local unlockR = Remotes:FindFirstChild("UnlockHeroEquip")
 if lockR then lockR.OnClientEvent:Connect(function(d)
 local g=type(d)=="string" and d or (type(d)=="table" and (d.guid or d[1])) or nil
 if g then _lockedGuids[g]=true end
 end) end
 if unlockR then unlockR.OnClientEvent:Connect(function(d)
 local g=type(d)=="string" and d or (type(d)=="table" and (d.guid or d[1])) or nil
 if g then _lockedGuids[g]=nil end
 end) end
 end)

 _sellConn = updateRemote.OnClientEvent:Connect(function(data)
 if not _autoSellOn then return end
 if type(data) ~= "table" then return end
 task.spawn(function()
 task.wait(0.3)
 -- [v186] Struktur confirmed dari sniff:
 -- item = { guid="...", data = { id=970002, isLock=bool, grade=990001, guid="..." } }
 local items = {}
 if data.heroEquips and type(data.heroEquips)=="table" then items=data.heroEquips
 elseif data[1] and type(data[1])=="table" then items=data
 elseif data.guid then items={data} end

 for _, item in ipairs(items) do
 if not _autoSellOn then break end

 local guid = item.guid
 if not guid or #tostring(guid)==0 then continue end

 local d = (item.data and type(item.data)=="table") and item.data or item
 local isLock = d.isLock or d.locked or d.isLocked or false
 if _lockedGuids[tostring(guid)] then isLock = true end

 if isLock then
 _cnt.skipped=(_cnt.skipped or 0)+1; RefreshCounters()
 continue
 end

 -- Scan UI dulu biar nama item tersedia
 scanGuidNames()
 local name = _guidNames[tostring(guid)] or ""
 local prefix = getType(name) -- R/Y/B dari huruf pertama nama

 task.wait(0.15)
 local remote = Remotes:FindFirstChild("DelectHeroEquips")
 if remote then
 local ok = pcall(function() remote:FireServer({tostring(guid)}) end)
 if ok then
 -- Counter naik di luar pcall, berdasarkan tipe nama
 _cnt[prefix] = (_cnt[prefix] or 0) + 1
 RefreshCounters()
 local total = _cnt.R + _cnt.Y + _cnt.B + _cnt.other
 local label = #name > 0 and name:sub(1,20) or ("ID:"..tostring(d.id or "?"))
 SetSellStatus("Sold ["..total.."] "..prefix..": "..label, Color3.fromRGB(255,160,40))
 end
 end
 end
 task.delay(0.5, scanGuidNames)
 end)
 end)
 SetSellStatus("[OK] Monitoring Active - Sell All except Locked", Color3.fromRGB(100,220,100))
 end

 _sellToggleCb = function(on)
 if on then
 StartAutoSell()
 else
 if _sellConn then pcall(function() _sellConn:Disconnect() end); _sellConn = nil end
 local total = _cnt.R + _cnt.Y + _cnt.B + _cnt.other
 SetSellStatus("Idle - "..total.." SELL", C.BG3)
 end
 end

 -- Divider
 local divMain = Frame(p, C.BORD, UDim2.new(1,0,0,1))
 divMain.LayoutOrder=5; divMain.BackgroundTransparency=0.42

 -- 
 -- HIDE REROLL CHAT
 -- Sembunyikan pesan reroll dari chat history
 -- Format server: "Congratulations, [player] just reroll a weapon's super quirk [NamaQuirk]"
 -- Remote trigger: AutoRandomWeaponQuirk / AutoRandomHeroQuirk
 -- 
 local _hideRerollChat = false
 local _hideRerollConn = nil

 -- Keyword yang mau disembunyikan (lowercase, match partial)
 local HIDE_KEYWORDS = {
 "Congratulations", -- weapon quirk reroll
 "just reroll a super quirk", -- hero quirk reroll
 "just reroll", -- fallback semua jenis reroll
 "super quirk", -- tangkap notif quirk langka
 }

 local function _matchHideKeyword(txt)
 local lower = txt:lower()
 for _, kw in ipairs(HIDE_KEYWORDS) do
 if lower:find(kw, 1, true) then return true end
 end
 return false
 end

 -- Sembunyikan satu TextLabel (BodyText) dan parent frame-nya
 local function _hideRerollLabel(lbl)
 pcall(function()
 if not lbl or not lbl.Parent then return end
 local txt = (lbl.Text or ""):gsub("<[^>]+>","")
 if not _matchHideKeyword(txt) then return end
 -- Sembunyikan parent frame (biasanya TextMessage container)
 local target = lbl.Parent
 -- Naik sampai ketemu Frame/ImageLabel yang bisa di-hide
 for _ = 1, 4 do
 if not target or not target.Parent then break end
 if target:IsA("Frame") or target:IsA("ImageLabel") then
 target.Visible = false
 return
 end
 target = target.Parent
 end
 -- Fallback: hide label langsung
 lbl.Visible = false
 end)
 end

 local function _startHideRerollChat()
 pcall(function()
 local CG = game:GetService("CoreGui")
 local expChat = CG:FindFirstChild("ExperienceChat")
 if not expChat then
 -- Coba tunggu sebentar
 task.spawn(function()
 local ec = CG:WaitForChild("ExperienceChat", 10)
 if ec and _hideRerollChat then
 -- Scan yang sudah ada
 for _, v in ipairs(ec:GetDescendants()) do
 if v:IsA("TextLabel") and v.Name == "BodyText" then
 _hideRerollLabel(v)
 end
 end
 -- Watch baru
 _hideRerollConn = ec.DescendantAdded:Connect(function(v)
 if v:IsA("TextLabel") and v.Name == "BodyText" then
 task.wait(0.15)
 if _hideRerollChat then _hideRerollLabel(v) end
 end
 end)
 end
 end)
 return
 end
 -- Scan semua BodyText yang sudah ada di history
 for _, v in ipairs(expChat:GetDescendants()) do
 if v:IsA("TextLabel") and v.Name == "BodyText" then
 _hideRerollLabel(v)
 end
 end
 -- Watch BodyText baru yang muncul
 _hideRerollConn = expChat.DescendantAdded:Connect(function(v)
 if v:IsA("TextLabel") and v.Name == "BodyText" then
 task.wait(0.15)
 if _hideRerollChat then _hideRerollLabel(v) end
 end
 end)
 end)
 end

 local function _stopHideRerollChat()
 if _hideRerollConn then
 pcall(function() _hideRerollConn:Disconnect() end)
 _hideRerollConn = nil
 end
 end

 -- [v264] Metode 2: Hook via remote fire timing
 -- AutoRandomWeaponQuirk / AutoRandomHeroQuirk di-fire -> 
 -- schedule hide chat message berikutnya dalam 3 detik
 local _rerollHideNames = {
 AutoRandomWeaponQuirk = true,
 AutoRandomHeroQuirk = true,
 AutoHeroQuirk = true,
 }
 local _rerollHidePending = false

 local function _scheduleHideNextRerollMsg()
 if _rerollHidePending then return end
 _rerollHidePending = true
 task.delay(0.5, function()
 -- Scan ExperienceChat untuk pesan baru dalam window 3 detik
 local deadline = tick() + 3
 task.spawn(function()
 pcall(function()
 local CG = game:GetService("CoreGui")
 local ec = CG:FindFirstChild("ExperienceChat")
 if not ec then _rerollHidePending = false; return end
 while tick() < deadline do
 for _, v in ipairs(ec:GetDescendants()) do
 if v:IsA("TextLabel") and v.Name == "BodyText" and v.Visible then
 local txt = (v.Text or ""):gsub("<[^>]+>",""):lower()
 if txt:find("just reroll",1,true) or txt:find("super quirk",1,true) then
 _hideRerollLabel(v)
 end
 end
 end
 task.wait(0.2)
 end
 _rerollHidePending = false
 end)
 end)
 end)
 end

 -- Hook __namecall untuk deteksi fire AutoRandomWeaponQuirk/AutoRandomHeroQuirk
 -- Hanya aktif kalau toggle Hide Reroll Chat ON
 task.spawn(function()
 task.wait(2) -- tunggu hook system ready
 pcall(function()
 local mt = getrawmetatable(game)
 local old_nc = mt.__namecall
 setreadonly(mt, false)
 mt.__namecall = newcclosure(function(self, ...)
 local method = getnamecallmethod()
 if _hideRerollChat and (method == "FireServer" or method == "InvokeServer") then
 pcall(function()
 if _rerollHideNames[self.Name] then
 _scheduleHideNextRerollMsg()
 end
 end)
 end
 return old_nc(self, ...)
 end)
 setreadonly(mt, true)
 end)
 end)

 -- UI Toggle Row
 local hrRow = Frame(p, C.SURFACE, UDim2.new(1,0,0,44))
 hrRow.LayoutOrder = 3; Corner(hrRow,10); Stroke(hrRow, C.BORD, 1.5, 0.3)
 local hrLbl = Label(hrRow, "HIDE REROLL CHAT", 13, C.TXT, Enum.Font.GothamBold)
 hrLbl.Size = UDim2.new(1,-68,0,20); hrLbl.Position = UDim2.new(0,14,0.5,-10)
 local hrPill = Btn(hrRow, C.PILL_OFF, UDim2.new(0,52,0,30))
 hrPill.AnchorPoint = Vector2.new(1,0.5); hrPill.Position = UDim2.new(1,-12,0.5,0); Corner(hrPill,13)
 local hrKnob = Frame(hrPill, C.KNOB_OFF, UDim2.new(0,24,0,24))
 hrKnob.AnchorPoint = Vector2.new(0,0.5); hrKnob.Position = UDim2.new(0,3,0.5,0); Corner(hrKnob,10)

 hrPill.MouseButton1Click:Connect(function()
 _hideRerollChat = not _hideRerollChat
 local on = _hideRerollChat
 TweenService:Create(hrPill, TweenInfo.new(0.16), {BackgroundColor3 = on and C.PILL_ON or C.PILL_OFF}):Play()
 TweenService:Create(hrKnob, TweenInfo.new(0.16), {
 Position = on and UDim2.new(1,-27,0.5,0) or UDim2.new(0,3,0.5,0),
 BackgroundColor3 = on and C.KNOB_ON or C.KNOB_OFF,
 }):Play()
 if on then
 _startHideRerollChat()
 else
 _stopHideRerollChat()
 end
 end)

 -- 
 -- 
 -- ============================================================
 -- PANEL : FARM
 -- ============================================================
do
 local p = NewPanel("farm")

 -- State
 local RA = { running=false, threads={}, killed=0, cur=nil }
 local TA = { running=false, threads={}, killed=0, cur=nil, targetName=nil }
 local _deadG_F = {}
 local HERO_GUIDS_F = {}

 -- [FIX] SetupFarmHook dihapus - hook __namecall cukup satu di SetupUniversalSpy
 -- HERO_GUIDS_F sekarang alias ke HERO_GUIDS global agar tidak ada duplikasi hook
 local HERO_GUIDS_F = HERO_GUIDS -- alias, bukan copy

 -- Death listener
 if RE.Death then
 RE.Death.OnClientEvent:Connect(function(d)
 if not d then return end
 local g = d.enemyGuid or d.guid
 if g then
 _deadG_F[g] = true
 if RA.running then RA.killed = RA.killed+1 end
 if TA.running then TA.killed = TA.killed+1 end
 end
 end)
 end

 -- Helpers
 local function IsPosValidF(hrp)
 if not hrp then return false end
 local pos = hrp.Position
 if pos.X~=pos.X or pos.Y~=pos.Y or pos.Z~=pos.Z then return false end
 if math.abs(pos.X)>1e10 or math.abs(pos.Y)>1e10 or math.abs(pos.Z)>1e10 then return false end
 return true
 end

 local function GetEnemiesF()
  local list = {}
  local seen = {}
  -- Primary + fallback folders
  local FOLDERS = {"Enemys","EnemyCityRaid","CityRaidEnemys","Enemies","Enemy"}
  for _, fname in ipairs(FOLDERS) do
   local f = workspace:FindFirstChild(fname)
   if f then
    for _,e in ipairs(f:GetChildren()) do
     if e:IsA("Model") then
      local g = e:GetAttribute("EnemyGuid")
      local h = e:FindFirstChild("HumanoidRootPart")
      local hum = e:FindFirstChildOfClass("Humanoid")
      if g and h and hum and hum.Health>0 and not seen[g] and IsPosValidF(h) then
       seen[g] = true
       table.insert(list, {model=e, guid=g, hrp=h})
      end
     end
    end
   end
  end
  return list
 end

 local function IsDeadF(e)
 if not e then return true end
 if _deadG_F[e.guid] then return true end
 if not e.model or not e.model.Parent then return true end
 local h = e.model:FindFirstChildOfClass("Humanoid")
 if not h or h.Health<=0 then return true end
 if not IsPosValidF(e.hrp) then return true end
 return false
 end

 local function FindByNameF(nm)
 for _,e in ipairs(GetEnemiesF()) do
 if e.model.Name==nm and not IsDeadF(e) then return e end
 end
 return nil
 end

 local function TpToF(tgt)
 if not tgt or not tgt.hrp then return end
 local char = LP.Character; if not char then return end
 local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
 local tgtPos = tgt.hrp.Position
 if tgtPos.Y < -100 then return end
 local dir = (hrp.Position - tgtPos)
 if dir.Magnitude < 0.5 then dir = Vector3.new(1,0,0) end
 dir = Vector3.new(dir.X, 0, dir.Z).Unit
 local nearPos = tgtPos + dir*4
 local params = RaycastParams.new()
 params.FilterType = Enum.RaycastFilterType.Exclude
 local ex = {}
 if LP.Character then table.insert(ex, LP.Character) end
 local ef = workspace:FindFirstChild("Enemys"); if ef then table.insert(ex, ef) end
 params.FilterDescendantsInstances = ex
 local safePos
 for _,orig in ipairs({nearPos+Vector3.new(0,20,0), nearPos+Vector3.new(0,10,0), tgtPos+Vector3.new(4,20,0)}) do
 local r = workspace:Raycast(orig, Vector3.new(0,-80,0), params)
 if r and r.Position.Y >= (tgtPos.Y-30) then safePos = r.Position+Vector3.new(0,3,0); break end
 end
 hrp.CFrame = CFrame.new(safePos or nearPos+Vector3.new(0,3,0))
 end

 local function FCharF(g, pos)
  -- Confirmed SimpleSpy: hanya PlayerClickAttackSkill, tidak ada ClickEnemy
  if RE.Atk then pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end) end
 end

 local function FHeroF(g)
  if not RE.HeroUseSkill or #HERO_GUIDS_F == 0 then return end
  local now = tick()
  local last = _heroFireTick[g] or 0
  if now - last < 0.4 then return end
  _heroFireTick[g] = now
  for _, h in ipairs(HERO_GUIDS_F) do
   pcall(function() RE.HeroUseSkill:FireServer({heroGuid=h,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
   pcall(function() RE.HeroUseSkill:FireServer({heroGuid=h,attackType=2,userId=MY_USER_ID,enemyGuid=g}) end)
  end
 end

 local function StartCollectF(checkFn)
 task.spawn(function()
 local col = {}
 while checkFn() do
 for _,fn in ipairs({"Golds","Items","Drops","Rewards"}) do
 local f = workspace:FindFirstChild(fn)
 if f then for _,o in ipairs(f:GetChildren()) do
 if not checkFn() then break end
 local g = o:GetAttribute("GUID") or o:GetAttribute("Guid")
 if g and not col[g] then
 col[g] = true
 pcall(function() RE.CollectItem:InvokeServer(g) end)
 task.wait(0.05)
 end
 end end
 end
 task.wait(0.25)
 end
 end)
 end

 -- Random Attack
 local function StartRA()
  -- Pastikan HERO_GUIDS terisi sebelum attack
  if #HERO_GUIDS == 0 then
   pcall(function()
    for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
     local g = obj:GetAttribute("heroGuid") or obj:GetAttribute("guid")
     if type(g)=="string" and IsValidUUID(g) then
      local dup=false
      for _,ex in ipairs(HERO_GUIDS) do if ex==g then dup=true; break end end
      if not dup then table.insert(HERO_GUIDS, g) end
     end
    end
   end)
  end
  RA.running=true; RA.killed=0; RA.cur=nil; RA.threads={}
 local tChar = task.spawn(function()
  local tpT = 0
  while RA.running do
   if not RA.cur or IsDeadF(RA.cur) or not RA.cur.model.Parent then
    _deadG_F={}; RA.cur=nil
    for _,e in ipairs(GetEnemiesF()) do
     if not IsDeadF(e) then RA.cur=e; break end
    end
    if RA.cur and not TA.running then TpToF(RA.cur); tpT=0 end
   end
   if RA.cur and not IsDeadF(RA.cur) and RA.cur.model.Parent then
    FCharF(RA.cur.guid, RA.cur.hrp.Position)
    tpT = tpT + task.wait()
    if tpT>=2 and not TA.running then tpT=0; TpToF(RA.cur) end
   else
    task.wait()
   end
  end
 end)
 local tHero = task.spawn(function()
  while RA.running do
   local cur = RA.cur
   if cur and not IsDeadF(cur) and cur.model.Parent and cur.model:FindFirstChild("HumanoidRootPart") then
    FHeroF(cur.guid)
   end
   task.wait()
  end
 end)
 RA.threads = {tChar, tHero}
 StartCollectF(function() return RA.running end)
 end

 local function StopRA()
 RA.running = false
 for _,t in ipairs(RA.threads) do pcall(function() task.cancel(t) end) end
 RA.threads={}; RA.cur=nil
 end

 -- Target Attack
 local function StartTA(targetName, onStatus)
 TA.running=true; TA.killed=0; TA.targetName=targetName; TA.cur=nil; TA.threads={}
 local tChar = task.spawn(function()
 local lastGuid=nil; local tpT=0
 while TA.running do
 local tgt = FindByNameF(targetName)
 if not tgt then
 TA.cur = nil
 if onStatus then onStatus("WAITING ["..targetName.."] respawn...") end
 while TA.running do
 task.wait(0.3); tgt=FindByNameF(targetName)
 if tgt then break end
 end
 if not TA.running then break end
 _deadG_F={}; lastGuid=nil
 end
 if tgt and not IsDeadF(tgt) and tgt.model.Parent then
 TA.cur = tgt
 if tgt.guid~=lastGuid then lastGuid=tgt.guid; TpToF(tgt); tpT=0 end
 FCharF(tgt.guid, tgt.hrp.Position)
 tpT = tpT + task.wait()
 if tpT>=2 then tpT=0; TpToF(tgt) end
 if onStatus then onStatus(">> ["..targetName.."] Kill: "..TA.killed) end
 else
 task.wait()
 end
 end
 end)
 local tHero = task.spawn(function()
 while TA.running do
  local tgt = TA.cur
  if tgt and not IsDeadF(tgt) and tgt.model.Parent and tgt.model:FindFirstChild("HumanoidRootPart") then
   FHeroF(tgt.guid)
  end
  task.wait()
 end
 end)
 TA.threads = {tChar, tHero}
 StartCollectF(function() return TA.running end)
 end

 local function StopTA()
 TA.running = false
 for _,t in ipairs(TA.threads) do pcall(function() task.cancel(t) end) end
 TA.threads={}; TA.cur=nil; TA.targetName=nil
 end

 -- GUI
 local _, SetRA = ToggleRow(p, "Random Attack", "Attack Enemy", 1, function(on)
 if on then StartRA() else StopRA() end
 end)

 local raKillLbl = Label(p, "Kill: 0", 10, C.DIM, Enum.Font.GothamBold)
 raKillLbl.Size = UDim2.new(1,0,0,14); raKillLbl.LayoutOrder = 2

 SectionHeader(p, "SELECT ENEMY", 3)

 -- Refresh button
 local refCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,36))
 refCard.LayoutOrder = 4; Corner(refCard, 10); Stroke(refCard, C.BORD, 1.5, 0.5)

 local refBtn = Btn(refCard, C.BG2, UDim2.new(0,80,0,26))
 refBtn.Position = UDim2.new(1,-88,0.5,-13)
 refBtn.Text = "Refresh"; refBtn.TextSize = 10
 refBtn.Font = Enum.Font.GothamBold; refBtn.TextColor3 = C.ACC
 Corner(refBtn, 6); Stroke(refBtn, C.BORD, 1.5, 0.3)

 local statLbl = Label(refCard, "Click Refresh to reload the enemies", 10, C.DIM, Enum.Font.GothamBold)
 statLbl.Size = UDim2.new(1,-100,1,0); statLbl.Position = UDim2.new(0,10,0,0)

 -- Scroll list
 local eScroll = Instance.new("ScrollingFrame", p)
 eScroll.Size = UDim2.new(1,0,0,160); eScroll.LayoutOrder = 5
 eScroll.BackgroundColor3 = C.BG2; eScroll.BorderSizePixel = 0
 eScroll.ScrollBarThickness = 3; eScroll.ScrollBarImageColor3 = C.ACC
 eScroll.CanvasSize = UDim2.new(0,0,0,0)
 eScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
 Corner(eScroll, 9); Stroke(eScroll, C.BORD, 1.5, 0.5)
 Padding(eScroll, 5, 5, 6, 6)
 ListLayout(eScroll, nil, nil, 4)

 local ePH = Label(eScroll, "Click Refresh to reload the enemies", 10, C.DIM, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
 ePH.Size = UDim2.new(1,0,0,44); ePH.TextWrapped = true

 local eRows = {}
 local activeRow = nil
 local taOn = false

 local function StopCurrentTA()
 taOn = false; StopTA()
 if activeRow then
 activeRow.f.BackgroundColor3 = C.BG2
 activeRow.s.Color = C.BORD
 activeRow.n.TextColor3 = C.DIM
 activeRow.pill.BackgroundColor3 = C.PILL_OFF
 activeRow.knob.Position = UDim2.new(0,3,0.5,0)
 activeRow = nil
 end
 statLbl.TextColor3 = C.DIM
 statLbl.Text = "Stop Kill: "..TA.killed
 end

 local function RefreshEnemies()
 if taOn then StopCurrentTA() end
 for _,r in pairs(eRows) do if r.f and r.f.Parent then r.f:Destroy() end end
 eRows = {}; ePH.Visible = false

 local enemies = GetEnemiesF()
 if #enemies == 0 then
 ePH.Text = "Tidak ada musuh di map ini"; ePH.Visible = true
 statLbl.Text = "Map kosong"; return
 end

 local nc = {}
 for _,e in ipairs(enemies) do nc[e.model.Name]=(nc[e.model.Name] or 0)+1 end
 local names = {}
 for nm in pairs(nc) do table.insert(names, nm) end
 table.sort(names)

 for idx, nm in ipairs(names) do
 local row = Frame(eScroll, C.BG2, UDim2.new(1,0,0,36))
 row.LayoutOrder = idx; Corner(row, 7)
 local rs = Instance.new("UIStroke", row); rs.Color = C.BORD; rs.Thickness = 1.5; rs.Transparency = 0.3

 local nL = Label(row, nm, 12, C.DIM, Enum.Font.GothamBold)
 nL.Size = UDim2.new(1,-80,1,0); nL.Position = UDim2.new(0,10,0,0)
 nL.TextTruncate = Enum.TextTruncate.AtEnd

 local cL = Label(row, "x"..nc[nm], 10, C.DIM, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
 cL.Size = UDim2.new(0,28,1,0); cL.Position = UDim2.new(1,-72,0,0)

 local pill = Btn(row, C.PILL_OFF, UDim2.new(0,52,0,30))
 pill.AnchorPoint = Vector2.new(1,0.5)
 pill.Position = UDim2.new(1,-6,0.5,0); Corner(pill, 15)
 local knob = Frame(pill, C.KNOB_OFF, UDim2.new(0,24,0,24))
 knob.AnchorPoint = Vector2.new(0,0.5)
 knob.Position = UDim2.new(0,3,0.5,0); Corner(knob, 12)

 local rd = {f=row, s=rs, n=nL, c=cL, pill=pill, knob=knob}
 eRows[nm] = rd

 pill.MouseButton1Click:Connect(function()
 if taOn and activeRow == rd then
 StopCurrentTA()
 else
 if taOn then StopCurrentTA() end
 taOn = true; activeRow = rd
 row.BackgroundColor3 = C.SURFACE2
 rs.Color = C.ACC; nL.TextColor3 = C.TXT
 TweenService:Create(pill, TweenInfo.new(0.18), {BackgroundColor3=C.PILL_ON}):Play()
 TweenService:Create(knob, TweenInfo.new(0.18), {Position=UDim2.new(1,-27,0.5,0), BackgroundColor3=C.KNOB_ON}):Play()
 statLbl.TextColor3 = C.ACC
 statLbl.Text = ">> ["..nm.."]"
 StartTA(nm, function(msg) statLbl.Text = msg end)
 end
 end)
 end

 statLbl.Text = #names.." jenis "..#enemies.." total"
 statLbl.TextColor3 = C.DIM

 task.spawn(function()
 while p.Parent and #names > 0 do
 local live = {}
 for _,e in ipairs(GetEnemiesF()) do
 if not IsDeadF(e) then live[e.model.Name]=(live[e.model.Name] or 0)+1 end
 end
 for _,nm2 in ipairs(names) do
 local r = eRows[nm2]; if not r then continue end
 local a = live[nm2] or 0
 r.c.Text = "x"..a
 r.c.TextColor3 = a==0 and C.RED or C.DIM
 end
 if RA.running then raKillLbl.Text = "Kill: "..RA.killed end
 if taOn then statLbl.Text = ">> ["..(TA.targetName or "?").."] Kill: "..TA.killed end
 task.wait(0.5)
 end
 end)
 end

 refBtn.MouseButton1Click:Connect(function()
 refBtn.Text = "Loading..."
 task.spawn(function() RefreshEnemies(); task.wait(0.3); refBtn.Text = "Refresh" end)
 end)
end

-- ============================================================
-- PANEL : ATTACK
-- ============================================================
do
 -- ============================================================
-- PANEL : PLAYER
-- ============================================================
do
 local p = NewPanel("player")

 local afkCard=Frame(p,C.SURFACE,UDim2.new(1,0,0,54))
 afkCard.LayoutOrder=-1; Corner(afkCard, 10); Stroke(afkCard,C.BORD, 1.5,0.88); Padding(afkCard,6,6,12,8)
 local afkTitle=Label(afkCard,"Session & Time (WIB) - Indonesia",12,C.TXT,Enum.Font.GothamBold)
 afkTitle.Size=UDim2.new(1,0,0,16); afkTitle.Position=UDim2.new(0,0,0,2)
 local afkTimeLbl=Label(afkCard,"WIB: --:--:-- | Active: 00:00:00",10.5,C.TXT2,Enum.Font.GothamBold)
 afkTimeLbl.Size=UDim2.new(1,0,0,13); afkTimeLbl.Position=UDim2.new(0,0,0,22)

 task.spawn(function()
 while ScreenGui and ScreenGui.Parent do
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
 afkTimeLbl.Text="WIB: "..wibStr.." | Active: "..durStr
 afkTimeLbl.TextColor3=STATE.antiAfk and C.ACC2 or C.TXT2
 end)
 end
 end)

 SectionHeader(p,"PLAYER SETTINGS",0)

 local wsCard=Frame(p,C.SURFACE,UDim2.new(1,0,0,70))
 wsCard.LayoutOrder=1; Corner(wsCard, 10); Stroke(wsCard,C.BORD, 1.5,0.88); Padding(wsCard,8,8,12,8)
 local wsTitle=Label(wsCard,"SPEED RUN",12,C.TXT,Enum.Font.GothamBold)
 wsTitle.Size=UDim2.new(0.6,0,0,16); wsTitle.Position=UDim2.new(0,0,0,4)
 local wsValLbl=Label(wsCard,"16 (100%)",11,C.ACC2,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
 wsValLbl.Size=UDim2.new(0.4,0,0,16); wsValLbl.Position=UDim2.new(0.6,0,0,4)
 local sliderTrack=Frame(wsCard,C.BG3,UDim2.new(1,0,0,8))
 sliderTrack.Position=UDim2.new(0,0,0,30); Corner(sliderTrack,4); Stroke(sliderTrack,C.BORD, 1.5,0.88)
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
 local pl=Label(pb,pr.lbl,9,C.TXT3,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
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
 _antiAfkStart = os.time()
 _antiAfkThread = task.spawn(function()
 -- Anti AFK - multi-metode, interval acak 3-5 menit
 -- Kombinasi client-side + server-side agar tidak terdeteksi idle
 local _rng = Random.new()
 local _lastRemoteUse = 0

 while STATE.antiAfk do
 -- Interval acak 3-5 menit
 local interval = 180 + _rng:NextInteger(0, 120)
 local waited = 0
 while waited < interval and STATE.antiAfk do
 task.wait(1); waited = waited + 1
 end
 if not STATE.antiAfk then break end

 pcall(function()
 local char = LP.Character
 if not char then return end
 local hum = char:FindFirstChildOfClass("Humanoid")
 local hrp = char:FindFirstChild("HumanoidRootPart")
 if not hum or hum.Health <= 0 then return end

 -- [1] hum:Move micro nudge - reset input idle timer (semua executor)
 pcall(function()
 local nudge = Vector3.new(
 (_rng:NextNumber() - 0.5) * 0.3,
 0,
 (_rng:NextNumber() - 0.5) * 0.3
 )
 hum:Move(nudge, false)
 task.wait(0.1 + _rng:NextNumber() * 0.1)
 hum:Move(Vector3.zero, false)
 end)

 task.wait(0.1 + _rng:NextNumber() * 0.1)

 -- [2] HumanoidRootPart CFrame jitter micro - tidak terlihat
 -- Server menerima posisi berubah -> tidak dianggap idle
 pcall(function()
 if hrp then
 local cf = hrp.CFrame
 local dx = (_rng:NextNumber() - 0.5) * 0.05
 local dz = (_rng:NextNumber() - 0.5) * 0.05
 hrp.CFrame = cf * CFrame.new(dx, 0, dz)
 task.wait(0.05)
 hrp.CFrame = cf
 end
 end)

 task.wait(0.1)

 -- [3] Camera micro jitter - reset client idle
 pcall(function()
 local cam = workspace.CurrentCamera
 if cam and cam.CameraType == Enum.CameraType.Custom then
 local cf = cam.CFrame
 cam.CFrame = cf * CFrame.Angles(
 0,
 0.0001 * (_rng:NextNumber() - 0.5),
 0
 )
 task.wait(0.05)
 cam.CFrame = cf
 end
 end)

 task.wait(0.05)

 -- [4] FireServer ke remote ringan (bukan remote penting)
 -- Ini yang paling efektif reset idle server-side
 -- Pakai RE.AutoHeroQuirk atau remote lain yang aman
 pcall(function()
 local now = tick()
 if (now - _lastRemoteUse) >= 60 then
 _lastRemoteUse = now
 -- Pakai ShowReward atau remote read-only yang tidak mengubah state
 local safe = Remotes:FindFirstChild("GetRaidTeamInfos") or Remotes:FindFirstChild("GetCityRaidInfos")
 if safe then
 pcall(function() safe:InvokeServer() end)
 end
 end
 end)

 -- [5] VIM keyboard (Xeno PC saja, skip kalau tidak ada)
 pcall(function()
 if VIM then
 VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
 task.wait(0.04 + _rng:NextNumber() * 0.06)
 VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
 end
 end)
 end)
 end
 end)
 else
 _antiAfkStart = nil
 end
 RefreshStatus()
 end)

 SectionHeader(p,"OTHER",10)
 local rejoinCard=Frame(p,C.SURFACE,UDim2.new(1,0,0,50))
 rejoinCard.LayoutOrder=11; Corner(rejoinCard, 10); Stroke(rejoinCard,C.BORD, 1.5,0.88); Padding(rejoinCard,8,8,12,8)
 local rejoinLbl=Label(rejoinCard,"REJOIN SERVER",12,C.TXT,Enum.Font.GothamBold)
 rejoinLbl.Size=UDim2.new(0.65,0,0,18); rejoinLbl.Position=UDim2.new(0,0,0,6)
 local rejoinSub=Label(rejoinCard,"Reconnect Same Server",10,C.TXT3,Enum.Font.GothamBold)
 rejoinSub.Size=UDim2.new(0.85,0,0,14); rejoinSub.Position=UDim2.new(0,0,0,26)
 local rejoinBtn=Btn(rejoinCard,C.ACC,UDim2.new(0,70,0,30))
 rejoinBtn.Position=UDim2.new(1,-76,0.5,-15); Corner(rejoinBtn, 10); Stroke(rejoinBtn,C.ACC2, 1.5,0.2)
 local rejoinBtnLbl=Label(rejoinBtn,"REJOIN",12,C.BLACK,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 rejoinBtnLbl.Size=UDim2.new(1,0,1,0)
 rejoinBtn.MouseButton1Click:Connect(function()
 rejoinBtnLbl.Text="..."; task.wait(0.5); DoRejoin()
 end)
end

-- ============================================================
-- PANEL : HERO FASTROLL
-- ============================================================
do
 local p = NewPanel("autoroll")
 local hrOpen = false

 -- State
 _HR_RPT = {
 guid = "",
 nameLbl = nil,
 slotLbls = {nil,nil,nil},
 slotTarget = {{},{},{}},
 running = false,
 SetSlot = function(i,txt,col)
 if _HR_RPT.slotLbls[i] then
 _HR_RPT.slotLbls[i].Text = txt
 _HR_RPT.slotLbls[i].TextColor3 = col or Color3.fromRGB(160,148,135)
 end
 end,
 Refresh = function()
 if not _HR_RPT.nameLbl then return end
 if _HR_RPT.guid and _HR_RPT.guid ~= "" then
 local found = nil
 pcall(function()
 for _, obj in ipairs(game.Players.LocalPlayer.PlayerGui:GetDescendants()) do
 if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Name == "NameText" and obj.Parent and obj.Parent.Name == "HeroFrame" and obj.Parent.Parent and obj.Parent.Parent.Name == "SelectHeroBtn" then
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
 _HR_RPT.nameLbl.Text = "captured"
 _HR_RPT.nameLbl.TextColor3 = Color3.fromRGB(255,200,60)
 end
 else
 _HR_RPT.nameLbl.Text = "PLEASE REROLL 1x First"
 _HR_RPT.nameLbl.TextColor3 = Color3.fromRGB(180,220,255)
 end
 end,
 SetToggleOff = function() end, -- diisi setelah toggle dibuat
 }

 -- Header dropdown
 local hrHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,38))
 hrHeader.LayoutOrder = 1; Corner(hrHeader, 10); Stroke(hrHeader,C.BORD, 1.5,0.88)
 local hrIcon = Label(hrHeader,">",12,C.ACC2,Enum.Font.GothamBold)
 hrIcon.Size = UDim2.new(0,20,1,0); hrIcon.Position = UDim2.new(0,10,0,0)
 local hrLabel = Label(hrHeader,"Hero Fastroll",13,C.TXT,Enum.Font.GothamBold)
 hrLabel.Size = UDim2.new(1,-40,1,0); hrLabel.Position = UDim2.new(0,30,0,0)

 local hrBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
 hrBody.LayoutOrder = 2; hrBody.ClipsDescendants = true
 Corner(hrBody, 10); Stroke(hrBody,C.BORD, 1.5,0.88); hrBody.Visible = false

 local hrInner = Frame(hrBody, C.BLACK, UDim2.new(1,-16,0,0))
 hrInner.BackgroundTransparency = 1; hrInner.Position = UDim2.new(0,8,0,8)
 local hrLayout = New("UIListLayout",{Parent=hrInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0, 10)})

 local function ResizeHRBody()
 hrLayout:ApplyLayout()
 local h = hrLayout.AbsoluteContentSize.Y + 20
 hrInner.Size = UDim2.new(1,0,0,h); hrBody.Size = UDim2.new(1,0,0,h+16)
 end

 -- Card laporan (1 kotak besar)
 local rptCard = Frame(hrInner, C.SURFACE, UDim2.new(1,0,0,0))
 rptCard.LayoutOrder = 1; Corner(rptCard, 10); Stroke(rptCard,C.BORD, 1.5,0.88)
 rptCard.AutomaticSize = Enum.AutomaticSize.Y
 local rptPad = Instance.new("UIPadding", rptCard)
 rptPad.PaddingLeft=UDim.new(0,10); rptPad.PaddingRight=UDim.new(0,10)
 rptPad.PaddingTop=UDim.new(0, 10); rptPad.PaddingBottom=UDim.new(0, 10)
 New("UIListLayout",{Parent=rptCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})

 -- Nama hero
 local nameRow = Frame(rptCard, C.BG2, UDim2.new(1,0,0,26))
 nameRow.LayoutOrder = 0; Corner(nameRow,6)
 local namePre = Label(nameRow,"Hero :",11,C.TXT3,Enum.Font.GothamBold)
 namePre.Size=UDim2.new(0,46,1,0); namePre.Position=UDim2.new(0,8,0,0)
 namePre.TextXAlignment=Enum.TextXAlignment.Left
 local nameLbl = Label(nameRow,"PLEASE REROLL 1x First",11,Color3.fromRGB(180,220,255),Enum.Font.GothamBold)
 nameLbl.Size=UDim2.new(1,-58,1,0); nameLbl.Position=UDim2.new(0,54,0,0)
 nameLbl.TextXAlignment=Enum.TextXAlignment.Left
 nameLbl.TextTruncate=Enum.TextTruncate.AtEnd
 _HR_RPT.nameLbl = nameLbl

 -- Status slot 1-3
 local slotNames = {"Slot 1","Slot 2","Slot 3"}
 for i = 1, 3 do
 local sRow = Frame(rptCard, C.BG3, UDim2.new(1,0,0,24))
 sRow.LayoutOrder = i; Corner(sRow,5)
 local sPre = Label(sRow,slotNames[i].." :",11,C.TXT3,Enum.Font.GothamBold)
 sPre.Size=UDim2.new(0,46,1,0); sPre.Position=UDim2.new(0,8,0,0)
 sPre.TextXAlignment=Enum.TextXAlignment.Left
 local sLbl = Label(sRow,"Idle",11,Color3.fromRGB(160,148,135),Enum.Font.GothamBold)
 sLbl.Size=UDim2.new(1,-58,1,0); sLbl.Position=UDim2.new(0,54,0,0)
 sLbl.TextXAlignment=Enum.TextXAlignment.Left
 sLbl.TextTruncate=Enum.TextTruncate.AtEnd
 _HR_RPT.slotLbls[i] = sLbl
 end

 -- Divider
 local div1 = Frame(hrInner, C.BG3, UDim2.new(1,0,0,1))
 div1.LayoutOrder = 2; div1.BackgroundTransparency = 0.4

 -- Dropdown target per slot
 for si = 1, 3 do
 local si_l = si
 local tRow = Frame(hrInner, C.BG2, UDim2.new(1,0,0,32))
 tRow.LayoutOrder = 2 + si; Corner(tRow,6)

 local tLbl = Label(tRow,"Target "..slotNames[si].." :",11,C.TXT,Enum.Font.GothamBold)
 tLbl.Size=UDim2.new(0,92,1,0); tLbl.Position=UDim2.new(0,8,0,0)
 tLbl.TextXAlignment=Enum.TextXAlignment.Left

 local tDdBtn = Btn(tRow, C.DD_BG, UDim2.new(1,-108,0,24))
 tDdBtn.Position=UDim2.new(0,100,0.5,-12); Corner(tDdBtn,5); Stroke(tDdBtn,C.BORD2, 1.5,0.85)
 local tDdLbl = Label(tDdBtn,"-- SELECT TARGET --",10,C.TXT2,Enum.Font.GothamBold,Enum.TextXAlignment.Left)
 tDdLbl.Size=UDim2.new(1,-20,1,0); tDdLbl.Position=UDim2.new(0,7,0,0)
 tDdLbl.TextTruncate=Enum.TextTruncate.AtEnd
 local tArrow = Label(tDdBtn,"v",9,C.ACC,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 tArrow.Size=UDim2.new(0,14,1,0); tArrow.Position=UDim2.new(1,-16,0,0)

 MakeGenericDropdown({
 ddBtn = tDdBtn,
 list = QUIRK_LIST_PER_SLOT[si_l],
 maxSel = MAX_PER_SLOT,
 selTable = _HR_RPT.slotTarget[si_l],
 onRefresh = function()
 local names = {}
 for _, q in ipairs(QUIRK_LIST_PER_SLOT[si_l]) do
 if _HR_RPT.slotTarget[si_l][q.id] then
 table.insert(names, q.name)
 end
 end
 tDdLbl.Text = #names > 0 and table.concat(names," / ") or "-- SELECT TARGET --"
 tDdLbl.TextColor3 = #names > 0 and C.ACC2 or C.TXT2
 end,
 })
 end

 -- Toggle Auto Roll Hero
 local toggleRow = Frame(hrInner, C.BG2, UDim2.new(1,0,0,34))
 toggleRow.LayoutOrder = 7; Corner(toggleRow, 10); Stroke(toggleRow,C.ACC, 1.5,0.7)
 local tgLbl = Label(toggleRow,"Auto Roll Hero",12,C.TXT,Enum.Font.GothamBold)
 tgLbl.Size=UDim2.new(0.55,0,1,0); tgLbl.Position=UDim2.new(0,10,0,0)
 local tgSub = Label(toggleRow,"ON = START REROLL",9,C.TXT3,Enum.Font.GothamBold)
 tgSub.Size=UDim2.new(0.55,0,0,12); tgSub.Position=UDim2.new(0,10,1,-14)
 local hrPill = Btn(toggleRow,C.BG3,UDim2.new(0,40,0,22))
 hrPill.Position=UDim2.new(1,-50,0.5,-11); Corner(hrPill,11)
 local hrKnob = Frame(hrPill,C.TXT,UDim2.new(0,18,0,18))
 hrKnob.Position=UDim2.new(0,2,0.5,-9); Corner(hrKnob,9)

 local function SetHeroToggleUI(on)
 TweenService:Create(hrPill,TweenInfo.new(0.15),{BackgroundColor3=on and C.PILL_ON or C.BG3}):Play()
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
 hrIcon.Text = hrOpen and "v" or ">"
 if hrOpen then task.defer(ResizeHRBody) end
 end)
end

-- PANEL : AUTO ROLL - HALO
do
 local p = Panels["autoroll"]
 local haloOpen = false

 local haloHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,38))
 haloHeader.LayoutOrder = 30; Corner(haloHeader, 10); Stroke(haloHeader,C.BORD, 1.5,0.88)
 local haloIcon = Label(haloHeader,">",12,C.ACC2,Enum.Font.GothamBold)
 haloIcon.Size = UDim2.new(0,20,1,0); haloIcon.Position = UDim2.new(0,10,0,0)
 local haloLabel = Label(haloHeader,"Auto Gacha Halo",13,C.TXT,Enum.Font.GothamBold)
 haloLabel.Size = UDim2.new(1,-40,1,0); haloLabel.Position = UDim2.new(0,30,0,0)

 local haloBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
 haloBody.LayoutOrder = 31; haloBody.ClipsDescendants = true
 Corner(haloBody, 10); Stroke(haloBody,C.BORD, 1.5,0.88); haloBody.Visible = false

 local haloInner = Frame(haloBody, C.BLACK, UDim2.new(1,-16,0,0))
 haloInner.BackgroundTransparency = 1; haloInner.Position = UDim2.new(0,8,0,8)
 local haloLayout = New("UIListLayout",{Parent=haloInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0, 10)})

 function ResizeHaloBody()
 haloLayout:ApplyLayout()
 local h = haloLayout.AbsoluteContentSize.Y + 20
 haloInner.Size = UDim2.new(1,0,0,h); haloBody.Size = UDim2.new(1,0,0,h+16)
 end

 local HALO_COLORS = {C.ACC, C.ACC2, C.ACC3}
 local HALO_ICONS = {"","",""}

 for hi = 1, 3 do
 local hi_l = hi

 local hCard = Frame(haloInner, C.SURFACE, UDim2.new(1,0,0,0))
 hCard.LayoutOrder = hi; Corner(hCard, 10); Stroke(hCard,C.BORD, 1.5,0.88)
 hCard.AutomaticSize = Enum.AutomaticSize.Y
 local hPad = Instance.new("UIPadding", hCard)
 hPad.PaddingLeft=UDim.new(0,12); hPad.PaddingRight=UDim.new(0,12)
 hPad.PaddingTop=UDim.new(0,10); hPad.PaddingBottom=UDim.new(0,10)
 New("UIListLayout",{Parent=hCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

 local hTitle = Label(hCard, HALO_NAMES[hi], 14, C.ACC, Enum.Font.GothamBold)
 hTitle.Size = UDim2.new(1,0,0,18); hTitle.LayoutOrder = 0

 local statRow = Frame(hCard, C.BG2, UDim2.new(1,0,0,26))
 statRow.LayoutOrder = 1; Corner(statRow,6); Stroke(statRow,C.BORD2, 1.5,0.5)
 local hDot = Frame(statRow, Color3.fromRGB(100,100,100), UDim2.new(0,8,0,8))
 hDot.Position = UDim2.new(0,7,0.5,-4); Corner(hDot,4)
 HALO.dotRefs[hi] = hDot
 local hStLbl = Label(statRow,"Idle - Enable to Start Gacha",10,C.TXT2,Enum.Font.GothamBold)
 hStLbl.Size = UDim2.new(1,-22,1,0); hStLbl.Position = UDim2.new(0,21,0,0)
 hStLbl.TextTruncate = Enum.TextTruncate.AtEnd
 HALO.statLbls[hi] = hStLbl

 local infoRow = Frame(hCard, C.BG3, UDim2.new(1,0,0,22))
 infoRow.LayoutOrder = 2; Corner(infoRow,5)
 local attLbl = Label(infoRow,"Attempt: -",9.5,C.TXT3,Enum.Font.GothamBold)
 attLbl.Size = UDim2.new(1,-8,1,0); attLbl.Position = UDim2.new(0,8,0,0)
 HALO.attemptLbls[hi] = attLbl

 local enRow = Frame(hCard, C.BG2, UDim2.new(1,0,0,34))
 enRow.LayoutOrder = 4; Corner(enRow, 10); Stroke(enRow, C.ACC, 1.5, 0.6)

 local enLbl = Label(enRow,"Auto Gacha",12,C.TXT,Enum.Font.GothamBold)
 enLbl.Size = UDim2.new(0.6,0,1,0); enLbl.Position = UDim2.new(0,10,0,0)
 local enSub = Label(enRow,"ON = START GACHA",9,C.TXT3,Enum.Font.GothamBold)
 enSub.Size = UDim2.new(0.6,0,0,12); enSub.Position = UDim2.new(0,10,1,-14)

 local enToggle = Btn(enRow, C.BG3, UDim2.new(0,40,0,22))
 enToggle.Position = UDim2.new(1,-50,0.5,-11); Corner(enToggle,11)
 local enKnob = Frame(enToggle, C.TXT, UDim2.new(0,18,0,18))
 enKnob.Position = UDim2.new(0,2,0.5,-9); Corner(enKnob,9)

 HALO.toggleBtns[hi] = enToggle
 HALO.toggleKnobs[hi] = enKnob

 enToggle.MouseButton1Click:Connect(function()
 HALO.enOnFlags[hi_l] = not HALO.enOnFlags[hi_l]
 local enOn = HALO.enOnFlags[hi_l]
 enToggle.BackgroundColor3 = enOn and C.ACC or C.BG3
 enKnob.Position = enOn and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
 enRow.BackgroundColor3 = enOn and C.BG2 or C.BG2
 Stroke(enRow, C.ACC, 1.5, enOn and 0.2 or 0.6)
 DoAutoRollHalo(hi_l, enOn)
 end)
 end

 haloHeader.MouseButton1Click:Connect(function()
 haloOpen = not haloOpen
 haloBody.Visible = haloOpen
 haloIcon.Text = haloOpen and "v" or ">"
 if haloOpen then task.defer(ResizeHaloBody) end
 end)
end

-- ============================================================
-- PANEL : AUTO ROLL - ORNAMENT
-- ============================================================
do
 local p = Panels["autoroll"]
 local ornOpen = false

 local ornHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,38))
 ornHeader.LayoutOrder = 35; Corner(ornHeader, 10); Stroke(ornHeader,C.BORD, 1.5,0.88)
 local ornIcon = Label(ornHeader,">",12,C.ACC2,Enum.Font.GothamBold)
 ornIcon.Size = UDim2.new(0,20,1,0); ornIcon.Position = UDim2.new(0,10,0,0)
 local ornLabel = Label(ornHeader,"Auto Roll Ornament",13,C.TXT,Enum.Font.GothamBold)
 ornLabel.Size = UDim2.new(1,-40,1,0); ornLabel.Position = UDim2.new(0,30,0,0)

 local ornBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
 ornBody.LayoutOrder = 36; ornBody.ClipsDescendants = true
 Corner(ornBody, 10); Stroke(ornBody,C.BORD, 1.5,0.88); ornBody.Visible = false

 local ornInner = Frame(ornBody, C.BLACK, UDim2.new(1,-16,0,0))
 ornInner.BackgroundTransparency = 1; ornInner.Position = UDim2.new(0,8,0,8)
 ornInner.AutomaticSize = Enum.AutomaticSize.Y
 local ornLayout = New("UIListLayout",{Parent=ornInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0, 10)})
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
 local ORN_ICONS = {"","","","","",""}

 -- Info cara pakai
 local infoCard = Frame(ornInner, C.BG2, UDim2.new(1,0,0,0))
 infoCard.LayoutOrder = 0; infoCard.AutomaticSize = Enum.AutomaticSize.Y
 Corner(infoCard,7); Stroke(infoCard,C.ACC, 1.5,0.5)
 local infoPad = Instance.new("UIPadding",infoCard)
 infoPad.PaddingLeft=UDim.new(0,10); infoPad.PaddingRight=UDim.new(0,10)
 infoPad.PaddingTop=UDim.new(0,7); infoPad.PaddingBottom=UDim.new(0,7)
 local infoLbl = Label(infoCard,
 "[i] Enable the Fastroll toggle to start rolling automatically without stopping.",
 9.5, Color3.fromRGB(230,210,170), Enum.Font.GothamBold)
 infoLbl.Size = UDim2.new(1,0,0,0); infoLbl.AutomaticSize = Enum.AutomaticSize.Y
 infoLbl.TextWrapped = true; infoLbl.LayoutOrder = 0

 for mi = 1, #_ASH_ORN.MACHINES do
 local mi_l = mi
 local mInfo = _ASH_ORN.MACHINES[mi]

 local mCard = Frame(ornInner, C.SURFACE, UDim2.new(1,0,0,0))
 mCard.LayoutOrder = mi; Corner(mCard, 10); Stroke(mCard,C.BORD, 1.5,0.88)
 mCard.AutomaticSize = Enum.AutomaticSize.Y
 local mPad = Instance.new("UIPadding", mCard)
 mPad.PaddingLeft=UDim.new(0,12); mPad.PaddingRight=UDim.new(0,12)
 mPad.PaddingTop=UDim.new(0,10); mPad.PaddingBottom=UDim.new(0,10)
 New("UIListLayout",{Parent=mCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

 -- Title
 local mTitle = Label(mCard, mInfo.name, 14, C.TXT, Enum.Font.GothamBold)
 mTitle.Size = UDim2.new(1,0,0,18); mTitle.LayoutOrder = 0

 -- Status row
 local statRow = Frame(mCard, C.BG2, UDim2.new(1,0,0,26))
 statRow.LayoutOrder = 1; Corner(statRow,6); Stroke(statRow,C.BORD2, 1.5,0.5)
 local mDot = Frame(statRow, Color3.fromRGB(100,100,100), UDim2.new(0,8,0,8))
 mDot.Position = UDim2.new(0,7,0.5,-4); Corner(mDot,4)
 ORN.dotRefs[mi] = mDot
 local mStLbl = Label(statRow,"Idle - SELECT TARGET & ENABLE",10,C.TXT2,Enum.Font.GothamBold)
 mStLbl.Size = UDim2.new(1,-22,1,0); mStLbl.Position = UDim2.new(0,21,0,0)
 mStLbl.TextTruncate = Enum.TextTruncate.AtEnd
 ORN.statLbls[mi] = mStLbl

 -- Info attempt & last
 local infoRow = Frame(mCard, C.BG3, UDim2.new(1,0,0,22))
 infoRow.LayoutOrder = 2; Corner(infoRow,5)
 local attLbl = Label(infoRow,"Attempt: -",9.5,C.TXT3,Enum.Font.GothamBold)
 attLbl.Size = UDim2.new(0.5,0,1,0); attLbl.Position = UDim2.new(0,8,0,0)
 ORN.attemptLbls[mi] = attLbl
 local lastLbl = Label(infoRow,"Last: -",9.5,Color3.fromRGB(180,180,180),Enum.Font.GothamBold,Enum.TextXAlignment.Right)
 lastLbl.Size = UDim2.new(0.5,-10,1,0); lastLbl.Position = UDim2.new(0.5,0,0,0)
 ORN.lastLbls[mi] = lastLbl

 local divLine = Frame(mCard, C.BG3, UDim2.new(1,0,0,1))
 divLine.LayoutOrder = 3; divLine.BackgroundTransparency = 0.4

 -- Enable toggle
 local enRow = Frame(mCard, C.BG2, UDim2.new(1,0,0,34))
 enRow.LayoutOrder = 6; Corner(enRow, 10); Stroke(enRow,ORN_COLORS[mi], 1.5,0.7)

 local enLbl = Label(enRow,"Fastroll",12,C.TXT,Enum.Font.GothamBold)
 enLbl.Size = UDim2.new(0.55,0,1,0); enLbl.Position = UDim2.new(0,10,0,0)
 local enSub = Label(enRow,"ON = START REROLL",9,C.TXT3,Enum.Font.GothamBold)
 enSub.Size = UDim2.new(0.55,0,0,12); enSub.Position = UDim2.new(0,10,1,-14)

 local enToggle = Btn(enRow, C.BG3, UDim2.new(0,40,0,22))
 enToggle.Position = UDim2.new(1,-50,0.5,-11); Corner(enToggle,11)
 local enKnob = Frame(enToggle, C.TXT, UDim2.new(0,18,0,18))
 enKnob.Position = UDim2.new(0,2,0.5,-9); Corner(enKnob,9)

 ORN.toggleBtns[mi] = enToggle
 ORN.toggleKnobs[mi] = enKnob

 enToggle.MouseButton1Click:Connect(function()
 ORN.enOnFlags[mi_l] = not ORN.enOnFlags[mi_l]
 local enOn = ORN.enOnFlags[mi_l]
 enToggle.BackgroundColor3 = enOn and C.ACC or C.BG3
 enKnob.Position = enOn and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
 enRow.BackgroundColor3 = enOn and C.SURFACE or C.BG2
 Stroke(enRow, C.ACC, 1.5, enOn and 0.3 or 0.7)
 _ASH_ORN.DoRoll(mi_l, enOn)
 end)

 task.defer(ResizeOrnBody)
 end

 ornHeader.MouseButton1Click:Connect(function()
 ornOpen = not ornOpen
 ornBody.Visible = ornOpen
 ornIcon.Text = ornOpen and "v" or ">"
 if ornOpen then task.defer(ResizeOrnBody) end
 end)
end


-- ============================================================
do -- [FIX] AutoRaid+Webhook: isolated scope
-- AUTO RAID : LOGIC (Data dari RaidSniffer v2)
-- Format confirmed:
-- UpdateRaidInfo -> arg[1] = {
-- action = "RemoveRaidEnters" | "AddRaidEnters"
-- raidInfos = {
-- [raidId(number)] = {
-- spawnName = "RE1001"/"RE1002"
-- endTime = number
-- mapId = number (50011, 50007, dst)
-- raidId = number
-- }
-- }
-- }
-- ============================================================

-- RAID_LIVE: [raidId] = {raidId, mapId, spawnName, rank, label}
RAID_LIVE = {}
RAID_ID_LIST = {} -- sorted list untuk UI
_raidIdRefreshCb = nil
_defaultRRIdx = 0 -- [v265] Round-robin index untuk Pick Mode Default

-- [FIX v256] SPAWN_RANK: HANYA identifikasi SLOT SPAWN (lokasi portal di map)
-- CONFIRMED via sniffing: RE1001/RE1002 BUKAN indikator grade!
-- RE1001 bisa grade B, G, M++. RE1002 bisa grade D, S. Tidak ada korelasi.
-- Tetap disimpan karena dipakai ConnectRaidListeners untuk data slot.
SPAWN_RANK = {
 RE1001 = 1, RE1002 = 2, RE1003 = 3, RE1004 = 4, RE1005 = 5, RE1006 = 6,
}
-- RANK_LABEL: mapping grade number -> nama grade (dipakai chat parser + UI display)
-- TIDAK ADA hubungan dengan SPAWN_RANK. Grade HANYA dari chat announce.
RANK_LABEL = {
 [1]="E", [2]="D", [3]="C", [4]="B", [5]="A",
 [6]="S", [7]="SS", [8]="G", [9]="N", [10]="M",
 [11]="M+", [12]="M++", [15]="XM", [17]="ULT",
}
-- Nama map in-game (mapNum = mapId - 50000)
MAP_NAMES = {
 [1] = "Shadow Gate City",
 [2] = "Level Grinding Cavern",
 [3] = "Shadow Castle",
 [4] = "Seolhan Forest",
 [5] = "Demon Castle - Tier 1",
 [6] = "Orc Palace",
 [7] = "Demon Castle - Tier 2",
 [8] = "Ant Island",
 [9] = "Land of Giant",
 [10] = "Plagueheart",
 [11] = "Umbralfrost Domain",
 [12] = "Kamish's Demise",
 [13] = "Lava Hell",
 [14] = "Illusory World",
 [15] = "Inferno Altar",
 [16] = "Shadow Throne",
 [17] = "Angel Holy Realm",
 [18] = "Golden Throne",
 -- [v117] Ascension Tower maps
 [19] = "Ascension Tower 1",
 [20] = "Ascension Tower 2",
 [21] = "Ascension Tower 3",
 [22] = "Ascension Tower 4",
 [23] = "Ascension Tower 5",
 [24] = "Ascension Tower 6",
 [25] = "Ascension Tower 7",
 [26] = "Ascension Tower 8",
 [27] = "Ascension Tower 9",
 [28] = "Ascension Tower 10",
}

-- Koordinat spawn boss per map Raid (tpMapId = raidMapId + 100)
-- Karakter + hero langsung TP ke sini setelah masuk map
RAID_SPAWN_POS = {
 [50101] = Vector3.new(2424.9, 8.5, 482.9), -- Map 1 Shadow Gate City
 [50102] = Vector3.new(1683.1, 8.6, -24.1), -- Map 2 Level Grinding Cavern
 [50103] = Vector3.new(1913.1, 12, -194.4), -- Map 3 Shadow Castle
 [50104] = Vector3.new( 515.8, 7.6, -98.0), -- Map 4 Seolhan Forest
 [50105] = Vector3.new(-229.3, 9.6, -2.3), -- Map 5 Demon Castle Tier 1
 [50106] = Vector3.new(1998.2, 8.0, 237.7), -- Map 6 Orc Palace
 [50107] = Vector3.new( -42.0, 8.4, 334.0), -- Map 7 Demon Castle Tier 2
 [50108] = Vector3.new(-925.8,-396.2, -901.6), -- Map 8 Ant Island
 [50109] = Vector3.new( 8.7, 13.0, 244.2), -- Map 9 Land of Giant
 [50110] = Vector3.new(2003.0, 8.1, 344.0), -- Map 10 Plagueheart
 [50111] = Vector3.new(2068.0, 49.4, -155.8), -- Map 11 Umbralfrost Domain
 [50112] = Vector3.new( 16.5, 9.0, 269.5), -- Map 12 Kamish's Demise
 [50113] = Vector3.new(2100.7, 63.1, 423.1), -- Map 13 Lava Hell
 [50114] = Vector3.new( 27.8, 49.8, 303.9), -- Map 14 Illusory World
 [50115] = Vector3.new( -0.9, 24.0, 185.3), -- Map 15 Inferno Altar
 [50116] = Vector3.new(1999.6, 17.0, 236.5), -- Map 16 Shadow Throne
 [50117] = Vector3.new( -0.4, 18.5, 93.5), -- Map 17 Angel Holy Realm
 [50118] = Vector3.new(2000.0, 45.4, 234.7), -- Map 18 Golden Throne
}

-- Pilih raidEntry dari RAID_ID_LIST sesuai difficulty


do -- chat listener + grade cache

-- ============================================================
-- GRADE CACHE & PARSER
-- Sumber grade: TipsFloatingPanel (primer) + chat history (backup)
-- Structure: TipsFloatingPanel > PopupFrame > PopupBg > ContentBg > TextLabel
-- ============================================================

GRADE_LIST = {"E","D","C","B","A","S","SS","G","N","M","M+","M++","XM","ULT"}
_runeGradeCache = {} -- {[mapNum]=grade} - diisi dari popup/chat
_towerBossCache = {} -- {[mapNum]=bossName} - untuk webhook
_pendingTowerNum = nil
_pendingTowerTime = 0

-- [FIX v267] GRADE_RANK: nilai numerik grade untuk perbandingan di ParseChatLine
-- shouldUpdate hanya update kalau grade baru LEBIH TINGGI dari yang di cache
GRADE_RANK = {
 ["E"]=1,["D"]=2,["C"]=3,["B"]=4,["A"]=5,["S"]=6,["SS"]=7,
 ["G"]=8,["N"]=9,["M"]=10,["M+"]=11,["M++"]=12,["XM"]=15,["ULT"]=17,
}

-- [v272 FIX] RAID_CONFIG_GRADE: formula terpisah Normal Raid vs Ascension Tower
-- Normal Raid: slot = (raidId - 930001) % 10 -> ["D","B","S","SS","G","N","M+","M++","XM","ULT"]
-- AT: slot = (raidId - 935101) % 10 -> ["E","D","C","B","A","S","SS","G","N","M"]
-- AT mapNum: ((raidId - 935001) // 100 - 1) % 18 + 1
-- Verified dari game data: formula % 10 langsung tanpa % 180 wrapper
RAID_CONFIG_GRADE = setmetatable({}, {
 __index = function(_, raidId)
 if type(raidId) ~= "number" then return nil end
 -- Ascension Tower: raidId 935xxx atau 936xxx range AT
 if raidId >= 935001 then
 local _at = {"E","D","C","B","A","S","SS","G","N","M"}
 local slot = (raidId - 935101) % 10
 if slot >= 0 and slot <= 9 then return _at[slot + 1] end
 return nil
 end
 -- Normal Raid: raidId 930001+
 if raidId >= 930001 then
 local _nr = {"D","B","S","SS","G","N","M+","M++","XM","ULT"}
 local slot = (raidId - 930001) % 10
 return _nr[slot + 1]
 end
 return nil
 end
})


--  ParseChatLine: parse teks raid/siege, update cache 
function ParseChatLine(text)
 if type(text) ~= "string" or #text < 3 then return end
 text = text:gsub("<[^>]+>",""):gsub("[\r\n]+"," "):match("^%s*(.-)%s*$") or text

 -- RAID: "The MaFissure appeared in 6,Orc Palace [B]"
 if text:find("MaFissure",1,true) and text:find("appeared",1,true) then
 local mapStr, rest = text:match("appeared in (%d+),(.+)")
 if not mapStr then mapStr, rest = text:match("appeared in (%d+) (.+)") end
 if mapStr then
 local mapNum = tonumber(mapStr)
 local grade = rest:match("%[M%+%+%]") and "M++" or rest:match("%[M%+%]") and "M+" or rest:match("%[SS%]") and "SS" or rest:match("%[XM%]") and "XM" or rest:match("%[ULT%]") and "ULT" or rest:match("%[GOD%]") and "GOD" or rest:match("%[([EDCBAGSNMedcbagsn])%]") or (rest:find("%[M%]") and "M")
 if not grade then
 grade = text:match("%[M%+%+%]") and "M++" or text:match("%[M%+%]") and "M+" or text:match("%[SS%]") and "SS" or text:match("%[XM%]") and "XM" or text:match("%[ULT%]") and "ULT" or text:match("%[([EDCBAGSNMedcbagsn])%]") or (text:find("%[M%]") and "M")
 end
 if not grade and text:find("Monarch",1,true) then grade = "?" end
 if mapNum and grade then
 local prev = _runeGradeCache[mapNum]
 local cleanPrev = prev and prev:match("^([^%s%(]+)") or prev
 local shouldUpdate = not prev or cleanPrev == "?" or (GRADE_RANK[grade] and GRADE_RANK[cleanPrev] and GRADE_RANK[grade] > GRADE_RANK[cleanPrev])
 if shouldUpdate then _runeGradeCache[mapNum] = grade end
 if not _whSilent then TriggerWebhookDebounce() end
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 end
 else
 -- Ascension Tower baris 1: "appeared in Ascension Tower 7 -"
 local towerNum = text:match("Ascension Tower (%d+)")
 if towerNum then
 _pendingTowerNum = tonumber(towerNum)
 _pendingTowerTime = tick()
 end
 end
 return
 end

 -- ASCENSION TOWER baris 2: "[Monarch] Frostborne [E]"
 if text:find("Monarch",1,true) and _pendingTowerNum and (tick() - _pendingTowerTime) < 10 then
 local towerNum = _pendingTowerNum
 _pendingTowerNum = nil; _pendingTowerTime = 0
 local bossName = text:match("%[Monarch%]%s*([%a%s]+)%s*%[") or "?"
 bossName = bossName:match("^%s*(.-)%s*$") or bossName
 if bossName ~= "?" then _towerBossCache[18 + towerNum] = bossName end
 local grade2 = text:match("%[M%+%+%]") and "M++" or text:match("%[M%+%]") and "M+" or text:match("%[SS%]") and "SS" or text:match("%[XM%]") and "XM" or text:match("%[ULT%]") and "ULT"
 if not grade2 then
 for bracket in text:gmatch("%[([^%]]+)%]") do
 if bracket ~= "Monarch" and #bracket <= 3 and bracket:match("^[EDCBAGSNMedcbagsn%+]+$") then
 grade2 = bracket:upper(); break
 end
 end
 end
 if grade2 then
 local mn = 18 + towerNum
 local prev = _runeGradeCache[mn]
 local cleanPrev = prev and prev:match("^([^%s%(]+)") or prev
 local shouldUpdate = not prev or cleanPrev == "?" or (GRADE_RANK[grade2] and GRADE_RANK[cleanPrev] and GRADE_RANK[grade2] > GRADE_RANK[cleanPrev])
 if shouldUpdate then _runeGradeCache[mn] = grade2 end
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 if not _whSilent then TriggerWebhookDebounce() end
 end
 return
 end

 -- SIEGE: "has begun" + map number
 if text:find("has begun",1,true) then
 local mn = text:match("Map (%d+)") or text:match("(%d+)[%s%-]")
 if mn then
 local num = tonumber(mn)
 local siegeMaps = {3,7,10,13}
 for _, sm in ipairs(siegeMaps) do
 if num == sm then
 _siegeChatOpen = _siegeChatOpen or {}
 _siegeChatOpen[num] = true
 if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
 break
 end
 end
 end
 end
end

--  Deduplicate seen messages (v273 FIX: Short-term memory 3 minutes)
local _chatSeen = {}
local function _processMsg(raw)
    if type(raw) ~= "string" or #raw < 5 then return end
    local txt = raw:gsub("<[^>]+>",""):gsub("[\r\n]+"," "):match("^%s*(.-)%s*$") or raw
    
    local function hasKW(s)
        return s:find("MaFissure",1,true) or s:find("appeared in",1,true) or s:find("Ascension Tower",1,true) or s:find("has begun",1,true)
    end
    
    if not hasKW(txt) then
        local stripped = txt:match("^[^:]+:%s*(.+)$")
        if stripped and hasKW(stripped) then txt = stripped end
    end
    if not hasKW(txt) then return end

    -- [v273 FIX] Unique key: gunakan seluruh teks (max 200) agar membedakan map/grade
    local key = txt:sub(1,200)
    local now = tick()

    -- [v273 FIX] Short-term memory: 3 menit (180 detik)
    if _chatSeen[key] and (now - _chatSeen[key]) < 180 then 
        return 
    end
    
    _chatSeen[key] = now
    ParseChatLine(txt)
    
    -- Cleanup cache lama setiap 10 pesan baru (agar memori tidak bocor)
    local count = 0
    for _ in pairs(_chatSeen) do count = count + 1 end
    if count > 50 then
        for k, t in pairs(_chatSeen) do
            if (now - t) > 180 then _chatSeen[k] = nil end
        end
    end
end

--  PRIMER: TipsFloatingPanel detector 
-- Structure: TipsFloatingPanel (ScreenGui) > PopupFrame > PopupBg > ContentBg > TextLabel
-- Ini sumber paling awal - muncul saat popup raid muncul di tengah-atas layar
task.spawn(function()
 pcall(function()
 local pg = LP.PlayerGui

 local function watchTextLabel(lbl)
 if not lbl:IsA("TextLabel") then return end
 -- JANGAN baca langsung - teks masih "Label" kosong saat label baru dibuat
 -- Andalkan GetPropertyChangedSignal + delayed read
 pcall(function()
 lbl:GetPropertyChangedSignal("Text"):Connect(function()
 pcall(function()
 local txt = (lbl.Text or ""):gsub("<[^>]+>",""):gsub("[\r\n]+"," ")
 if #txt > 5 then _processMsg(txt) end
 end)
 end)
 end)
 -- Baca setelah 2s (teks sudah terisi animasi) dan 5s (sudah di history)
 task.spawn(function()
 task.wait(2)
 pcall(function()
 local txt = (lbl.Text or ""):gsub("<[^>]+>",""):gsub("[\r\n]+"," ")
 if #txt > 5 then _processMsg(txt) end
 end)
 task.wait(3) -- total 5s
 pcall(function()
 local txt = (lbl.Text or ""):gsub("<[^>]+>",""):gsub("[\r\n]+"," ")
 if #txt > 5 then _processMsg(txt) end
 end)
 end)
 end

 local function watchContentBg(contentBg)
 for _, child in ipairs(contentBg:GetChildren()) do
 if child:IsA("TextLabel") then watchTextLabel(child) end
 end
 contentBg.ChildAdded:Connect(function(child)
 if child:IsA("TextLabel") then watchTextLabel(child) end
 end)
 end

 local function watchPopupFrame(popupFrame)
 local function findContentBg(parent)
 for _, child in ipairs(parent:GetChildren()) do
 if child.Name == "ContentBg" then
 watchContentBg(child)
 elseif child:IsA("Frame") or child:IsA("ImageLabel") then
 findContentBg(child)
 end
 end
 end
 findContentBg(popupFrame)
 popupFrame.DescendantAdded:Connect(function(desc)
 if desc.Name == "ContentBg" then
 watchContentBg(desc)
 elseif desc:IsA("TextLabel") and desc.Parent and desc.Parent.Name == "ContentBg" then
 watchTextLabel(desc)
 end
 end)
 end

 local function watchTipsFloatingPanel(panel)
 for _, child in ipairs(panel:GetChildren()) do
 if child.Name == "PopupFrame" or child:IsA("Frame") then
 watchPopupFrame(child)
 end
 end
 panel.ChildAdded:Connect(function(child)
 if child.Name == "PopupFrame" or child:IsA("Frame") then
 watchPopupFrame(child)
 end
 end)
 end

 -- Cari TipsFloatingPanel yang sudah ada
 for _, obj in ipairs(pg:GetChildren()) do
 if obj.Name == "TipsFloatingPanel" then
 watchTipsFloatingPanel(obj)
 end
 end
 -- Watch TipsFloatingPanel baru
 pg.ChildAdded:Connect(function(obj)
 if obj.Name == "TipsFloatingPanel" then
 watchTipsFloatingPanel(obj)
 end
 end)
 end)
end)
end

-- 

--  BACKUP: Chat history setelah 5 detik 
-- TextChatService: reliable di semua executor
task.spawn(function()
 pcall(function()
 local TCS = game:GetService("TextChatService")
 -- Tunggu TextChannels ready max 10 detik
 local _w = 0
 repeat task.wait(0.5); _w = _w + 0.5
 until TCS:FindFirstChild("TextChannels") or _w >= 10

 local channels = TCS:FindFirstChild("TextChannels")
 if not channels then return end

 local function watchChannel(ch)
 if not ch:IsA("TextChannel") then return end
 ch.DescendantAdded:Connect(function(obj)
 if obj:IsA("TextChatMessage") then
 -- Delay 5 detik: backup setelah popup selesai
 task.delay(5, function()
 pcall(function()
 -- TextChatMessage.Text bisa kosong, coba semua field
 local txt = obj.Text or ""
 if #txt < 5 then txt = (obj.PrefixText or "").." "..(obj.Text or "") end
 if #txt < 5 then
 -- Coba dari TextSource
 local ts = obj:FindFirstChildOfClass("TextSource")
 if ts then txt = ts.Text or "" end
 end
 _processMsg(txt)
 end)
 end)
 end
 end)
 end

 for _, ch in ipairs(channels:GetChildren()) do watchChannel(ch) end
 channels.ChildAdded:Connect(function(ch) task.wait(0.1); watchChannel(ch) end)

 -- Scan history awal saat startup (silent, jangan trigger webhook)
 task.wait(5)
 _whSilent = true
 pcall(function()
 for _, ch in ipairs(channels:GetChildren()) do
 if ch:IsA("TextChannel") then
 for _, obj in ipairs(ch:GetChildren()) do
 if obj:IsA("TextChatMessage") then
 local txt = obj.Text or ""
 if #txt < 5 then txt = (obj.PrefixText or "").." "..(obj.Text or "") end
 _processMsg(txt)
 end
 end
 end
 end
 end)
 _whSilent = false
 end)
end)
end

-- 

--  FALLBACK 3: ExperienceChat BodyText watcher 
-- Ini yang paling reliable karena BodyText selalu berisi teks penuh
-- Terbukti dari diagnostic: chat "The MaFissure appeared in X" ada di ExperienceChat
task.spawn(function()
 pcall(function()
 local CG = game:GetService("CoreGui")
 local ec = CG:WaitForChild("ExperienceChat", 15)
 if not ec then return end

 local function checkBodyText(lbl)
 pcall(function()
 if not lbl:IsA("TextLabel") or lbl.Name ~= "BodyText" then return end
 local function read()
 pcall(function()
 local txt = (lbl.Text or ""):gsub("<[^>]+>",""):gsub("[\r\n]+"," ")
 _processMsg(txt)
 end)
 end
 read()
 lbl:GetPropertyChangedSignal("Text"):Connect(read)
 end)
 end

 -- Scan yang sudah ada
 for _, obj in ipairs(ec:GetDescendants()) do
 checkBodyText(obj)
 end
 -- Watch yang baru muncul
 ec.DescendantAdded:Connect(function(obj)
 task.wait(4) -- tunggu teks penuh (sudah pindah ke history)
 checkBodyText(obj)
 end)
 end)
end)


-- do chat listener + grade cache


-- Forward declare raid+webhook functions
SendWebhookNotif=nil; RebuildRaidList=nil; ParseRaidEntry=nil
DisconnectRaidConns=nil; ConnectRaidListeners=nil; RaidFireDamage=nil

do -- [FIX] webhook + raid logic wrapped to free top-level locals

-- ============================================================
-- WEBHOOK SYSTEM - Bersih, akurat, executor-agnostic
-- Kirim notif ke Discord/Telegram saat Raid atau Siege OPEN
-- ============================================================
_WH = {}

-- Helper: dapatkan request function (support semua executor)
local function _getReqFunc()
 -- [FIX] Tambah executor lain yang umum dipakai
 return request or http_request or httprequest or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request) or (krnl and krnl.request) or (electron and electron.request) or nil
end

-- Helper: kirim HTTP POST ke Discord atau Telegram
local function _doSend(url, text)
 local reqFunc = _getReqFunc()
 if not reqFunc then
 return false
 end
 local HS = game:GetService("HttpService")
 local isDiscord = url:find("discord%.com/api/webhooks")
 local isTelegram = url:find("api%.telegram%.org")
 local ok, res = false, nil
 pcall(function()
 if isDiscord then
 res = reqFunc({
 Url = url,
 Method = "POST",
 Headers = { ["Content-Type"] = "application/json" },
 Body = HS:JSONEncode({ content = text }),
 })
 elseif isTelegram then
 local enc = tostring(text):gsub("([^%w%-_%.%~])", function(c)
 return string.format("%%%02X", string.byte(c))
 end)
 res = reqFunc({ Url = url .. "&text=" .. enc, Method = "GET" })
 end
 end)
 if res and type(res) == "table" then
 local sc = res.StatusCode or res.status or 0
 ok = (sc >= 200 and sc < 300)
 if not ok then
 ok = false -- Status non-2xx
 end
 elseif res ~= nil then
 ok = true
 else
 ok = false
 end
 return ok
end

-- Kirim notif Raid ke webhook
_WH.SendRaid = function(url)
 -- [v272] Grade colors Discord embed
 local GRADE_COLOR = {
 ["E"]=9868950,["D"]=6604900,["C"]=5294200,["B"]=6589695,
 ["A"]=11822335,["S"]=16757810,["SS"]=16768000,["G"]=16742440,
 ["N"]=16732240,["M"]=16727160,["M+"]=14428340,["M++"]=13115135,
 ["XM"]=16732360,["ULT"]=16766720,
 }
 local GRADE_RANK_W = {["E"]=1,["D"]=2,["C"]=3,["B"]=4,["A"]=5,["S"]=6,["SS"]=7,["G"]=8,["N"]=9,["M"]=10,["M+"]=11,["M++"]=12,["XM"]=15,["ULT"]=17}

 local raidList = {}
 for _, entry in pairs(RAID_LIVE or {}) do table.insert(raidList, entry) end
 table.sort(raidList, function(a,b) return (a.mapId or 0) < (b.mapId or 0) end)
 if #raidList == 0 then return end

 local function getGrade(entry)
 local mn = (entry.mapId or 50000) - 50000
 local g = "?"
 if entry.raidId and entry.raidId > 0 and RAID_CONFIG_GRADE then g = RAID_CONFIG_GRADE[entry.raidId] or "?" end
 if g == "?" then g = (GetBestGrade and GetBestGrade(mn)) or "?" end
 if g == "?" then g = entry.grade or "?" end
 return g
 end

 local normalRaids, atRaids = {}, {}
 for _, entry in ipairs(raidList) do
 local mn = (entry.mapId or 50000) - 50000
 local isAT = entry.isAT or (entry.raidId and entry.raidId >= 935001) or (mn >= 19)
 if isAT then table.insert(atRaids, entry)
 else table.insert(normalRaids, entry) end
 end

 local isDiscord = url:find("discord%.com/api/webhooks")
 local isTelegram = url:find("api%.telegram%.org")
 local HS = game:GetService("HttpService")
 local reqFunc = _getReqFunc()
 if not reqFunc then return end

 if isDiscord then
 local topGrade = "E"
 local lines_normal, lines_at = {}, {}
 for _, entry in ipairs(normalRaids) do
 local mn = (entry.mapId or 50000) - 50000
 local name = MAP_NAMES[mn] or ("Map "..mn)
 local g = getGrade(entry)
 table.insert(lines_normal, "Map "..mn.." - "..name.." ["..g.."]")
 if (GRADE_RANK_W[g] or 0) > (GRADE_RANK_W[topGrade] or 0) then topGrade = g end
 end
 for _, entry in ipairs(atRaids) do
 local mn = (entry.mapId or 50000) - 50000
 local towerNum = mn - 18
 local g = getGrade(entry)
 table.insert(lines_at, "Tower "..towerNum.." - Ascension Tower "..towerNum.." ["..g.."]")
 if (GRADE_RANK_W[g] or 0) > (GRADE_RANK_W[topGrade] or 0) then topGrade = g end
 end
 local color = GRADE_COLOR[topGrade] or GRADE_COLOR["E"]
 local fields = {}
 if #lines_normal > 0 then
 table.insert(fields, {name="[Normal Raid] ("..#lines_normal..")", value=table.concat(lines_normal,"\n"), inline=false})
 end
 if #lines_at > 0 then
 table.insert(fields, {name="[Ascension Tower] ("..#lines_at..")", value=table.concat(lines_at,"\n"), inline=false})
 end
 local payload = {embeds={{title="[RAID OPEN] Rank "..topGrade, description="Total: **"..#raidList.."** raid aktif", color=color, fields=fields, footer={text="ASH GUI FLa Project"}}}}
 pcall(function()
 reqFunc({Url=url, Method="POST", Headers={["Content-Type"]="application/json"}, Body=HS:JSONEncode(payload)})
 end)
 elseif isTelegram then
 local lines = {"[RAID OPEN]"}
 for _, entry in ipairs(normalRaids) do
 local mn = (entry.mapId or 50000) - 50000
 local g = getGrade(entry)
 table.insert(lines, "- Map "..mn.." - "..(MAP_NAMES[mn] or "Map "..mn).." ["..g.."]")
 end
 for _, entry in ipairs(atRaids) do
 local mn = (entry.mapId or 50000) - 50000
 local g = getGrade(entry)
 table.insert(lines, "Tower "..(mn-18).." ["..g.."]")
 end
 _doSend(url, table.concat(lines, "\n"))
 end
end
SendWebhookRaid = function(url) _WH.SendRaid(url) end -- alias internal

-- Kirim notif Siege ke webhook
_WH.SendSiege = function(url)
 local SIEGE_NAMES = {
 [3]="Shadow Castle", [7]="Demon Castle Tier 2",
 [10]="Plagueheart", [13]="Lava Hell"
 }
 local lines = { "**SIEGE OPEN**" }
 local found = false
 if SIEGE and SIEGE.live then
 for cid, mn in pairs(SIEGE.live) do
 local name = SIEGE_NAMES[mn] or ("Map " .. mn)
 table.insert(lines, string.format("- Map %d - %s", mn, name))
 found = true
 end
 end
 if not found then return end
 local msg = table.concat(lines, "\n")
 _doSend(url, msg)
end
SendWebhookSiege = function(url) _WH.SendSiege(url) end -- alias internal

-- Debounce timer: tunggu 3 detik setelah notif terakhir baru kirim
local _whDebounce = nil
local _whLastSent = 0

TriggerWebhookDebounce = function()
 if not _webhookEnabled or not _webhookUrl or _webhookUrl == "" then return end
 if _whDebounce then pcall(function() task.cancel(_whDebounce) end) end
 -- [v271] Debounce 1 detik (turun dari 3s) agar lebih responsif
 _whDebounce = task.delay(1, function()
 _whDebounce = nil
 -- [v271] Cooldown 10 detik (turun dari 30s) agar tidak terlalu lambat
 if (tick() - _whLastSent) < 10 then return end
 _whLastSent = tick()
 task.spawn(function()
 local mode = _webhookMode or "both"
 local url = _webhookUrl
 local hasRaid = next(RAID_LIVE or {}) ~= nil
 local hasSiege = SIEGE and SIEGE.live and next(SIEGE.live) ~= nil
 if (mode == "raid" or mode == "both") and hasRaid then SendWebhookRaid(url) end
 if (mode == "siege" or mode == "both") and hasSiege then
 task.wait(0.3)
 SendWebhookSiege(url)
 end
 end)
 end)
end

SendWebhookNotif = TriggerWebhookDebounce -- alias untuk kompatibilitas

FlushWebhookPending = function()
 _whLastSent = 0 -- reset cooldown
 TriggerWebhookDebounce()
end

_WH.SendCustomMessage = function(url, msg, onDone, onFail)
 if not url or url == "" then
 if onFail then onFail("URL kosong") end; return
 end
 if not url:find("discord%.com/api/webhooks") and not url:find("api%.telegram%.org") then
 if onFail then onFail("URL tidak dikenali (bukan Discord/Telegram)") end; return
 end
 if not _getReqFunc() then
 if onFail then onFail("Executor tidak support HTTP") end; return
 end
 task.spawn(function()
 local ok = _doSend(url, msg)
 task.wait(0.3)
 if ok then
 if onDone then onDone() end
 else
 if onFail then onFail("Gagal kirim") end
 end
 end)
end

_WH.VerifyWebhookUrl = function(url, onValid, onInvalid)
 if not url or url == "" then
 if onInvalid then onInvalid("URL kosong") end; return
 end
 local isDiscord = url:find("discord%.com/api/webhooks/")
 local isTelegram = url:find("api%.telegram%.org/bot[^/]+/sendMessage")
 if isDiscord then
 local id, token = url:match("webhooks/(%d+)/([%w_%-]+)")
 if id and token and #token > 10 then
 if onValid then onValid() end
 else
 if onInvalid then onInvalid("Format Discord webhook salah") end
 end
 elseif isTelegram then
 if url:find("chat_id=") then
 if onValid then onValid() end
 else
 if onInvalid then onInvalid("Telegram URL butuh chat_id=...") end
 end
 else
 if onInvalid then onInvalid("Bukan URL Discord/Telegram valid") end
 end
end

-- Koneksi raid listeners
_WH.raidConns = {}

RebuildRaidList = function()
 local sorted = {}
 for _, e in pairs(RAID_LIVE) do table.insert(sorted, e) end
 -- Sort by mapId ascending (map 1 -> map 18)
 table.sort(sorted, function(a, b) return (a.mapId or 0) < (b.mapId or 0) end)
 RAID_ID_LIST = {}
 for _, e in ipairs(sorted) do
 table.insert(RAID_ID_LIST, {
 label = "Map "..(e.mapId-50000).." - "..(MAP_NAMES[e.mapId-50000] or ("Map "..(e.mapId-50000))).." - "..(RANK_LABEL[e.rank] or ("["..e.spawnName.."]")).." (ID:"..e.raidId..")",
 id = e.raidId,
 rank = e.rank,
 mapId = e.mapId,
 spawnName = e.spawnName,
 })
 end
 if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end
 -- Kirim webhook setiap RAID_LIVE berubah
 if _webhookEnabled and _webhookUrl ~= "" then
 TriggerWebhookDebounce()
 end
end

-- Parse satu entry raidInfos
-- [v202] Simpan grade dari _runeGradeCache (diisi chat parser)
-- raidType: "normal" (50101-50118) atau "at" (50301-50318), di-set saat EnterRaidsUpdateInfo
ParseRaidEntry = function(k, info)
 if type(info) ~= "table" then return end
 local raidId = info.raidId or (type(k)=="number" and k) or tonumber(k)
 local mapId = info.mapId
 local spawnName = info.spawnName or "RE1001"
 if not raidId or not mapId then return end
 -- [v272 FIX] Normalize mapId ke internal range
 -- Normal Raid: 50101-50118 -> 50001-50018
 -- AT: 50301-50318 -> 50019-50036 (offset +18 agar tidak overlap normal)
 local isAT = false
 if mapId >= 50101 and mapId <= 50118 then
 mapId = mapId - 100
 elseif mapId >= 50301 and mapId <= 50318 then
 mapId = 50000 + 18 + (mapId - 50300)
 isAT = true
 elseif mapId >= 50019 and mapId <= 50036 then
 isAT = true
 end
 local rank = SPAWN_RANK[spawnName] or 0
 local mapNum = mapId - 50000
 local mapName = MAP_NAMES[mapNum] or ("Map "..mapNum)
 -- [v272] Grade dari RAID_CONFIG_GRADE via raidId (cover AT dan Normal)
 if raidId >= 935001 then isAT = true end
 local grade = (RAID_CONFIG_GRADE and RAID_CONFIG_GRADE[raidId]) or (_runeGradeCache and _runeGradeCache[mapNum]) or "?"
 local rankLbl = grade ~= "?" and ("["..grade.."]") or "[?]"
 RAID_LIVE[raidId] = {
 raidId = raidId,
 mapId = mapId,
 spawnName = spawnName,
 rank = rank,
 grade = grade,
 isAT = isAT,
 endTime = info.endTime,
 label = "Map "..mapNum.." - "..mapName.." "..rankLbl,
 }
end
end

-- [v270] GetBestGrade: grade dari RAID_CONFIG_GRADE via raidId (akurat 100%)
-- Fallback: _runeGradeCache (chat/popup), lalu RAID_LIVE entry grade field
-- mapNum = angka map (1-18), return string grade atau nil
function GetBestGrade(mapNum)
 -- 1. RAID_CONFIG_GRADE via raidId (data config game, paling akurat)
 local mapId = 50000 + mapNum
 for _, ent in pairs(RAID_LIVE) do
 if ent.mapId == mapId and ent.raidId and ent.raidId > 0 then
 local g = RAID_CONFIG_GRADE and RAID_CONFIG_GRADE[ent.raidId]
 if g and g ~= "?" then return g end
 end
 end
 -- 2. Chat cache (fallback)
 if _runeGradeCache and _runeGradeCache[mapNum] then
 return _runeGradeCache[mapNum]
 end
 -- 3. RAID_LIVE entry grade field
 for _, ent in pairs(RAID_LIVE) do
 if ent.mapId == mapId and ent.grade and ent.grade ~= "?" then
 return ent.grade
 end
 end
 return nil
end


--
-- Sumber 1 (UTAMA) - workspace.Maps.Map.RaidEnter:
-- ChildAdded di RE1001/RE1002 -> RaidEnterX muncul = raid Map X buka
-- ChildRemoved di RE1001/RE1002 -> RaidEnterX hilang = raid Map X tutup
-- INSTANT, tidak bisa miss/stale.
--
-- Sumber 2 (raidId saja) - UpdateRaidInfo remote:
-- Hanya untuk dapat raidId yang dibutuhkan CreateRaidTeam.
-- ============================================================

_WH.raidConns = {}

DisconnectRaidConns = function()
 for _, conn in ipairs(_WH.raidConns) do
 pcall(function() conn:Disconnect() end)
 end
 _WH.raidConns = {}
end

-- Ekstrak mapNum dari nama child (mis. "RaidEnter7" -> 7)
local function _parseRaidEnterName(name)
 local n = name:match("^RaidEnter(%d+)$")
 return n and tonumber(n) or nil
end

-- Child RaidEnterX muncul di RE1001/RE1002 = raid Map X buka
local function _onRaidChildAdded(child, slotName)
 local mapNum = _parseRaidEnterName(child.Name)
 if not mapNum or mapNum < 1 or mapNum > 28 then return end
 local mapId = 50000 + mapNum
 -- Cek sudah ada entry raidId asli untuk map ini
 for _, ent in pairs(RAID_LIVE) do
 if ent.mapId == mapId and not ent._tempEntry then return end
 end
 -- Buat entry sementara (tempKey negatif agar tidak bentrok raidId server)
 local tempKey = -(mapId)
 RAID_LIVE[tempKey] = {
 raidId = tempKey,
 mapId = mapId,
 spawnName = slotName or "RE1001",
 rank = 0,
 grade = "?",
 isAT = false,
 endTime = nil,
 _tempEntry = true,
 label = "Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." [?]",
 }
 RebuildRaidList()
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 -- [v271] Trigger webhook LANGSUNG saat raid muncul di workspace
 -- Tidak tunggu chat/TipsPanel - workspace adalah sumber tercepat
 if not _whSilent then
 task.spawn(function()
 task.wait(0.5) -- beri waktu RebuildRaidList selesai
 TriggerWebhookDebounce()
 end)
 end
end

-- Child RaidEnterX hilang = raid Map X tutup
local function _onRaidChildRemoved(child)
 local mapNum = _parseRaidEnterName(child.Name)
 if not mapNum then return end
 local mapId = 50000 + mapNum
 local changed = false
 for rid, ent in pairs(RAID_LIVE) do
 if ent.mapId == mapId then
 RAID_LIVE[rid] = nil; changed = true
 end
 end
 if changed then RebuildRaidList() end
end

-- Pasang watcher ke satu slot (RE1001 atau RE1002)
local function _watchRaidSlot(reFolder)
 if not reFolder then return end
 for _, child in ipairs(reFolder:GetChildren()) do
 _onRaidChildAdded(child, reFolder.Name)
 end
 reFolder.ChildAdded:Connect(function(child)
 _onRaidChildAdded(child, reFolder.Name)
 -- [v268] Scan RaidCoolingGui untuk dapat grade dari ValueText/TextLabel
 task.spawn(function()
 task.wait(1) -- tunggu descendants terisi
 pcall(function()
 -- Scan semua TextLabel di dalam child (RaidEnterX atau RaidCoolingGui)
 local function scanForGrade(obj)
 for _, desc in ipairs(obj:GetDescendants()) do
 if desc:IsA("TextLabel") or desc:IsA("TextBox") then
 local txt = (desc.Text or ""):gsub("<[^>]+>","")
 -- Cari teks yang mengandung grade bracket [X]
 local grade = txt:match("%[M%+%+%]") and "M++" or txt:match("%[M%+%]") and "M+" or txt:match("%[SS%]") and "SS" or txt:match("%[XM%]") and "XM" or txt:match("%[ULT%]") and "ULT" or txt:match("%[GOD%]") and "GOD" or txt:match("%[([EDCBAGSNMedcbagsn])%]") or (txt:find("%[M%]") and "M")
 if grade then
 -- Cari mapNum dari nama child (RaidEnterX)
 local mn = _parseRaidEnterName(child.Name)
 if mn and _runeGradeCache then
 local prev = _runeGradeCache[mn]
 if not prev or prev == "?" then
 _runeGradeCache[mn] = grade:upper()
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 end
 end
 end
 -- Watch Text changes juga
 pcall(function()
 desc:GetPropertyChangedSignal("Text"):Connect(function()
 local t2 = (desc.Text or ""):gsub("<[^>]+>","")
 local g2 = t2:match("%[M%+%+%]") and "M++" or t2:match("%[M%+%]") and "M+" or t2:match("%[SS%]") and "SS" or t2:match("%[XM%]") and "XM" or t2:match("%[ULT%]") and "ULT" or t2:match("%[GOD%]") and "GOD" or t2:match("%[([EDCBAGSNMedcbagsn])%]") or (t2:find("%[M%]") and "M")
 if g2 then
 local mn2 = _parseRaidEnterName(child.Name)
 if mn2 and _runeGradeCache then
 local prev2 = _runeGradeCache[mn2]
 if not prev2 or prev2 == "?" then
 _runeGradeCache[mn2] = g2:upper()
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 end
 end
 end
 end)
 end)
 end
 end
 end
 scanForGrade(child)
 -- Cari RaidCoolingGui khusus
 for _, desc in ipairs(child:GetDescendants()) do
 if desc.Name == "RaidCoolingGui" then
 scanForGrade(desc)
 end
 end
 end)
 end)
 end)
 reFolder.ChildRemoved:Connect(function(child)
 _onRaidChildRemoved(child)
 end)
end

-- Tunggu workspace.Maps.Map.RaidEnter lalu pasang watcher
task.spawn(function()
 local ok, mapsF = pcall(function() return workspace:WaitForChild("Maps", 15) end)
 if not ok or not mapsF then return end
 local ok2, mapF = pcall(function() return mapsF:WaitForChild("Map", 10) end)
 if not ok2 or not mapF then return end
 local ok3, reF = pcall(function() return mapF:WaitForChild("RaidEnter", 10) end)
 if not ok3 or not reF then return end
 local re1 = reF:WaitForChild("RE1001", 5)
 local re2 = reF:WaitForChild("RE1002", 5)
 _watchRaidSlot(re1)
 _watchRaidSlot(re2)
end)

-- UpdateRaidInfo: HANYA untuk dapat raidId + grade dari server
-- Bukan lagi sumber utama exist/tidak-nya raid
ConnectRaidListeners = function()
 DisconnectRaidConns()

 local _RE_Update = Remotes:FindFirstChild("UpdateRaidInfo")
 local _RE_Enter = Remotes:FindFirstChild("EnterRaidsUpdateInfo")

 if _RE_Update then
 local conn = _RE_Update.OnClientEvent:Connect(function(data)
 if type(data) ~= "table" then return end
 local action = data.action
 local raidInfos = data.raidInfos
 if type(raidInfos) ~= "table" then return end

 if action == "RemoveRaidEnters" then
 for k in pairs(raidInfos) do
 local raidId = type(k)=="number" and k or tonumber(k)
 if raidId then RAID_LIVE[raidId] = nil end
 end
 RebuildRaidList()
 else
 for k, info in pairs(raidInfos) do
 if type(info) ~= "table" then continue end
 local raidId = info.raidId or (type(k)=="number" and k) or tonumber(k)
 local mapId = info.mapId
 if not raidId or not mapId then continue end
 -- Normalize mapId ke lobby range
 if mapId >= 50101 and mapId <= 50118 then mapId = mapId - 100
 elseif mapId >= 50301 and mapId <= 50318 then mapId = 50000 + 18 + (mapId - 50300) end
 if mapId < 50001 or mapId > 50036 then continue end

 local mapNum = mapId - 50000
 local spawnName = info.spawnName or "RE1001"
 local rank = SPAWN_RANK[spawnName] or 0
 -- [v271] Grade dari RAID_CONFIG_GRADE (formula matematika, cover semua seri)
 local grade = (RAID_CONFIG_GRADE and RAID_CONFIG_GRADE[raidId]) or (_runeGradeCache and _runeGradeCache[mapNum]) or "?"
 local tempKey = -(mapId)
 local entryData = {
 raidId = raidId,
 mapId = mapId,
 spawnName = spawnName,
 rank = rank,
 grade = grade,
 isAT = false,
 endTime = info.endTime,
 label = "Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." ["..grade.."](ID:"..raidId..")",
 }
 -- Kalau ada entry temp dari workspace, replace dengan raidId asli
 if RAID_LIVE[tempKey] then
 RAID_LIVE[raidId] = entryData
 RAID_LIVE[tempKey] = nil
 elseif not RAID_LIVE[raidId] then
 -- Entry baru (workspace belum detect, atau AT)
 ParseRaidEntry(k, info)
 else
 -- Sudah ada, update grade saja
 RAID_LIVE[raidId].grade = grade
 RAID_LIVE[raidId].rank = rank
 RAID_LIVE[raidId].label = entryData.label
 end
 end
 RebuildRaidList()
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 TriggerWebhookDebounce()
 end
 end)
 table.insert(_WH.raidConns, conn)
 end

 -- EnterRaidsUpdateInfo: slotIndex + serverMapId saat masuk map
 if _RE_Enter then
 local conn = _RE_Enter.OnClientEvent:Connect(function(data)
 if type(data) ~= "table" then return end
 if data.slotIndex then RAID.slotIndex = data.slotIndex end
 if data.fromMapId then RAID.fromMapId = data.fromMapId end
 if data.mapId then
 local mid = data.mapId
 if (mid >= 50101 and mid <= 50118) or (mid >= 50301 and mid <= 50318) then
 RAID.serverMapId = mid
 if mid >= 50301 and RAID.raidId and RAID_LIVE[RAID.raidId] then
 RAID_LIVE[RAID.raidId].isAT = true
 end
 end
 end
 end)
 table.insert(_WH.raidConns, conn)
 end
end

-- Pasang listener saat start
task.spawn(function() ConnectRaidListeners() end)

-- Auto-reconnect kalau Remotes refresh (mis. setelah rejoin)
task.spawn(function()
 local lastRef = Remotes:FindFirstChild("UpdateRaidInfo")
 while ScreenGui.Parent do
 task.wait(3)
 local cur = Remotes:FindFirstChild("UpdateRaidInfo")
 if cur ~= lastRef then
 lastRef = cur
 if cur then ConnectRaidListeners() end
 end
 end
end)
--  Helpers 
function StopRaid()
 _raidInterrupt = false
 MODE:Release("raid") -- [v252]
 RAID.running = false
 RAID.inMap = false
 if RAID.thread then
 pcall(function() task.cancel(RAID.thread) end)
 RAID.thread = nil
 end
 -- [FIX] Destroy wakeup event agar tidak leak
 if _raidWakeup then
 pcall(function() _raidWakeup:Destroy() end)
 _raidWakeup = nil
 end
 -- Reset state sesi
 RAID.raidId = nil
 RAID.raidMapId = nil
 RAID.serverMapId = nil
 RAID.fromMapId = nil
 RAID.slotIndex = 2
 RAID._raidDone = false
 RAID_LIVE = {}
 _defaultRRIdx = 0 -- reset RR saat RAID habis
 RAID_ID_LIST = {}
 if _runeGradeCache then
 for k in pairs(_runeGradeCache) do _runeGradeCache[k] = nil end
 end
 if RebuildRaidList then pcall(RebuildRaidList) end
 -- [FIX] JANGAN reset setting user (difficulty/rune/grades/preferMaps) di sini!
 -- StopRaid dipanggil oleh StartRaidLoop setiap kali Start ditekan
 -- kalau di-reset di sini, semua pilihan user (Hard, Rune Map, Pick Rank) hilang
 -- Setting user hanya boleh direset dari UI (tombol difficulty/rune/grade)
end

_raidSessionStart = nil -- waktu mulai raid session

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
 if RAID.suksesLbl then RAID.suksesLbl.Text = tostring(RAID.sukses) end
end

-- [v73 FIX] RaidCollectAll - scan lebih agresif:
-- 1. Scan semua folder reward yang mungkin
-- 2. Scan workspace root langsung (ada item yang tidak di-folder)
-- 3. Retry 1x setelah 1.5 detik untuk item yang spawn delayed
function RaidCollectAll()
 local collected_guids = {}
 local function collectFolder(folder)
 if not folder then return end
 for _, obj in ipairs(folder:GetChildren()) do
 local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid") or obj:GetAttribute("ItemGuid")
 if guid and not collected_guids[guid] then
 collected_guids[guid] = true
 RAID.collected = RAID.collected + 1
 pcall(function() RE.CollectItem:InvokeServer(guid) end)
 pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
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
 local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid") or obj:GetAttribute("ItemGuid")
 if guid and not collected_guids[guid] then
 collected_guids[guid] = true
 RAID.collected = RAID.collected + 1
 pcall(function() RE.CollectItem:InvokeServer(guid) end)
 pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
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
 local g = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid") or e:GetAttribute("Guid") or e:GetAttribute("GUID")
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
 -- [FIX v240] Jeda 0.3s antar type agar animasi tidak overflow limit 64
 for _, aType in ipairs({1, 2, 3}) do
 pcall(function() RE.HeroUseSkill:FireServer({
 heroGuid = hGuid,
 attackType = aType,
 userId = MY_USER_ID,
 enemyGuid = g,
 }) end)
 task.wait(0.3)
 end
 elseif RE.HeroSkill then
 pcall(function() RE.HeroSkill:FireServer({
 heroGuid=hGuid, enemyGuid=g, skillType=1, masterId=MY_USER_ID
 }) end)
 end
 end
end

-- [v257] ForceRescanRaidEnter: manual scan workspace RaidEnter
-- Backup kalau ChildAdded tidak fire (Roblox replication issue)
-- [FIX v257] Throttle: max 1x per 3 detik agar tidak trigger race condition
-- dengan game internal RaidsManager.AddRaidEnters -> crash TipsManager
local _lastRescanTime = 0
local function ForceRescanRaidEnter()
 local now = tick()
 if now - _lastRescanTime < 3 then return end -- throttle 3s
 _lastRescanTime = now
 pcall(function()
 local mapsF = workspace:FindFirstChild("Maps")
 if not mapsF then return end
 local mapF = mapsF:FindFirstChild("Map")
 if not mapF then return end
 local reF = mapF:FindFirstChild("RaidEnter")
 if not reF then return end
 for _, slot in ipairs(reF:GetChildren()) do
 for _, child in ipairs(slot:GetChildren()) do
 local mapNum = child.Name:match("^RaidEnter(%d+)$")
 if mapNum then
 mapNum = tonumber(mapNum)
 if mapNum and mapNum >= 1 and mapNum <= 28 then
 local mapId = 50000 + mapNum
 -- Cek belum ada di RAID_LIVE
 local exists = false
 for _, ent in pairs(RAID_LIVE) do
 if ent.mapId == mapId then exists = true; break end
 end
 if not exists then
 local tempKey = -(mapId)
 RAID_LIVE[tempKey] = {
 raidId = tempKey,
 mapId = mapId,
 spawnName = slot.Name or "RE1001",
 rank = 0,
 grade = _runeGradeCache and _runeGradeCache[mapNum] or "?",
 isAT = false,
 endTime = nil,
 _tempEntry = true,
 label = "Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." [?]",
 }
 RebuildRaidList()
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 end
 end
 end
 end
 end
 -- Cek kebalikannya: hapus entry yang child-nya sudah hilang
 for rid, ent in pairs(RAID_LIVE) do
 if ent._tempEntry then
 local mn = ent.mapId - 50000
 local childName = "RaidEnter" .. mn
 local found = false
 for _, slot in ipairs(reF:GetChildren()) do
 if slot:FindFirstChild(childName) then found = true; break end
 end
 if not found then
 RAID_LIVE[rid] = nil
 RebuildRaidList()
 end
 end
 end
 end)
end

-- Main loop
-- [v200] REWRITE: Flow final MA+AutoRaid
-- 
-- Range mapId:
-- Lobby : 50001-50018 (normal) | 50001-50028 (incl AT)
-- Normal : 50101-50118 (area raid)
-- AT : 50301-50318 (area raid Ascension Tower)
-- Siege : 50201-50204 (BUKAN raid, skip total)
--
-- NORMAL mode (Default/Easy/Hard/ByMap/ByRank/Manual):
-- STEP1 : Workspace watcher RaidEnter -> RAID_LIVE (instant)
-- STEP2 : CreateRaidTeam(raidId) ->
-- StartChallengeRaidMap:FireServer({mapId})
-- mapId = lobby+100 (50101-50118) atau lobby+300 (50301-50318)
-- pilihan berdasar Default/Easy=terkecil, Hard=terbesar, ByMap/Manual=preferMaps
-- STEP3 : Tunggu masuk map (workspace mapId / enemy, max 10s)
-- STEP4 : Diam 5s -> cari boss -> TP player+hero -> serang (ClickEnemy+HeroUseSkill 1-3)
-- STEP5 : Boss mati -> collect -> hide reward -> TP ke MR.lastMapId
-- STEP6 : _raidInterrupt=false -> MA resume -> cooldown 10s
--
-- RUNE MAP mode:
-- STEP2 : CreateRaidTeam(raidId) -> UseRaidItem(10265-10282) ->
-- tunggu LocalPlayerTeleportSuccess (server handle TP)
-- STEP4-6: sama seperti Normal
-- 
local function IsRaidLiveInGame()
 -- Cukup cek RAID_ID_LIST ada entry (workspace ChildRemoved handle expire)
 -- Entry _tempEntry (belum ada raidId asli) tetap dianggap valid
 -- karena workspace sudah konfirmasi raid ada
 return #RAID_ID_LIST > 0
end

function StartRaidLoop()
 StopRaid()
 RAID.running = true
 RAID.sukses = 0
 RAID.collected = 0
 RAID.fromMapId = nil
 RaidCounterUpdate()
 _raidSessionStart = os.time()
 -- [FIX] Buat _raidWakeup BindableEvent agar chat/UpdateRaidInfo bisa bangunkan waiting loop
 if _raidWakeup then pcall(function() _raidWakeup:Destroy() end) end
 _raidWakeup = Instance.new("BindableEvent")

 -- [FIX] Bersihkan sisa runeMapTarget kalau runeEnabled OFF
 if not RAID.runeEnabled and RAID.runeMapTarget ~= 0 then
 RAID.runeMapTarget = 0
 end

 -- Workspace watcher sudah menjaga RAID_LIVE real-time
 -- Tidak perlu fetch manual - langsung mulai loop
 RaidStatusUpdate("Siap. Menunggu raid...", Color3.fromRGB(180,180,60))

 RAID.thread = task.spawn(function()
  while RAID.running do

   -- [v238 FIX] Cek apakah ada raid yang benar-benar aktif di game sekarang
   if not IsRaidLiveInGame() then
    RAID.raidId = nil
    RAID.raidMapId = nil
    RAID_LIVE = {}
    RAID_ID_LIST = {}
    _defaultRRIdx = 0
    if RebuildRaidList then pcall(RebuildRaidList) end
   end

   local raidEntry = ResolveEntry()

   while RAID.running and not raidEntry do
    ForceRescanRaidEnter()
    raidEntry = ResolveEntry()
    if not raidEntry then
     local _now2 = os.time()
     for rid, ent in pairs(RAID_LIVE) do
      if ent.endTime and ent.endTime < (_now2 - 10) then
       RAID_LIVE[rid] = nil
      end
     end
     if RebuildRaidList then pcall(RebuildRaidList) end

     local _pm = RAID.pickMode
     if not IsRaidLiveInGame() then
      RaidStatusUpdate("Empty RAID - Waiting new RAID", Color3.fromRGB(160,100,60))
     else
      RaidStatusUpdate("Waiting raid [" .. (_pm ~= "default" and _pm or RAID.difficulty) .. "]...", Color3.fromRGB(255,200,60))
     end

     local _woken = false
     local _wConn
     if _raidWakeup then
      _wConn = _raidWakeup.Event:Connect(function() _woken = true end)
     end
     local _we = 0
     while not _woken and _we < 1 and RAID.running do
      task.wait(0.1); _we = _we + 0.1
     end
     if _wConn then pcall(function() _wConn:Disconnect() end) end
    end
   end
   if not RAID.running then break end

   local _preCheck_ok = true
   if not raidEntry then
    _preCheck_ok = false
   elseif not RAID_LIVE[raidEntry.id] then
    _preCheck_ok = false
   elseif not IsRaidLiveInGame() then
    local _ent = RAID_LIVE[raidEntry.id]
    if _ent and not _ent.endTime then
     _preCheck_ok = true
    else
     _preCheck_ok = false
    end
   end

   if not _preCheck_ok then
    _raidInterrupt = false; RAID.inMap = false; MODE:Release("raid")
    RaidStatusUpdate("Raid expired sebelum masuk - tunggu raid baru...", Color3.fromRGB(255,100,60))
    task.wait(2)
    continue
   end

   _raidInterrupt = true 
   RAID.raidId = raidEntry.id
   RAID.raidMapId = raidEntry.mapId
   RAID.inMap = true
   if RAID.updateActiveLabel then pcall(RAID.updateActiveLabel) end
   
   if MA.running then
    local _wma = 0
    while MA.running and _raidInterrupt and _wma < 1 do
     task.wait(0.05); _wma = _wma + 0.05
    end
   end
   RAID.slotIndex = 2
   if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end

   local mn = raidEntry.mapId - 50000
   local mapLabel = MAP_NAMES[mn] or ("Map " .. mn)

   local _liveEntry = RAID_LIVE[RAID.raidId]
   if not _liveEntry then
    _raidInterrupt = false; RAID.inMap = false; MODE:Release("raid")
    task.wait(1); continue
   end

   RAID.serverMapId = nil
   if not RAID.running then break end

   -- STEP 2: NORMAL ENTER
   RaidStatusUpdate("Enter Map " .. mn .. " Now...", C.ACC2)
   if not RAID.fromMapId then RAID.fromMapId = RAID.raidMapId end

   if RE.CreateRaidTeam then
    pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end)
   end
   task.wait(0.2)
   if not RAID.running then break end

   local _targetMapId = RAID.raidMapId + 100
   if _targetMapId < 50101 then _targetMapId = 50101 end
   if _targetMapId > 50118 then _targetMapId = 50118 end

   local _cfailA = false
   local _cfConnA
   local _cfReA = Remotes:FindFirstChild("ChallengeRaidsFail")
   if _cfReA then
    _cfConnA = _cfReA.OnClientEvent:Connect(function()
     _cfailA = true
    end)
   end
   if RE.StartChallengeRaidMap then
    pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = _targetMapId}) end)
   end
   local _wA = 0
   while RAID.serverMapId == nil and _wA < 5 and RAID.running and not _cfailA do
    task.wait(0.05); _wA = _wA + 0.05
   end
   if _cfConnA then pcall(function() _cfConnA:Disconnect() end) end
   if _cfailA then
    RAID_LIVE[RAID.raidId] = nil; RebuildRaidList()
    _raidInterrupt = false; RAID.inMap = false; MODE:Release("raid"); RAID.fromMapId = nil
    task.wait(1); continue
   end

   if not RAID.running then break end

   -- 
   -- STEP 3: Tunggu masuk map (max 10s)
   -- 
   RaidStatusUpdate("[~] Waiting...", Color3.fromRGB(180,100,255))
   local _tpOk = false
   local _tpWait = 0
   while not _tpOk and _tpWait < 10 and RAID.running do
    task.wait(0.3); _tpWait = _tpWait + 0.3
    pcall(function()
     local wMapId = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
     if wMapId then
      if RAID.serverMapId and wMapId == RAID.serverMapId then
       _tpOk = true
      elseif (wMapId >= 50101 and wMapId <= 50118) or (wMapId >= 50301 and wMapId <= 50318) then
       _tpOk = true
      end
     end
    end)
    if not _tpOk and #GetEnemies() > 0 then _tpOk = true end
   end

   if not _tpOk and RAID.running then
    RAID_LIVE[RAID.raidId] = nil; RebuildRaidList()
    _raidInterrupt = false; RAID.inMap = false; MODE:Release("raid"); RAID.fromMapId = nil
    task.wait(1); continue
   end

   -- Recovery HERO_GUIDS kalau kosong
   if #HERO_GUIDS == 0 then
    pcall(function()
     local hf = RS:FindFirstChild("HeroData") or RS:FindFirstChild("Heroes")
     if hf then
      for _, h in ipairs(hf:GetChildren()) do
       local g = h:GetAttribute("heroGuid") or h:GetAttribute("guid")
       if type(g) == "string" and IsValidUUID(g) then
        local dup = false
        for _, ex in ipairs(HERO_GUIDS) do if ex == g then dup = true; break end end
        if not dup then table.insert(HERO_GUIDS, g) end
       end
      end
     end
    end)
   end

 -- [FIX] Equip hero ke map ini agar hero spawn di sebelah player
 -- Tanpa ini hero tidak muncul di map raid meski GUID sudah ada
 if #HERO_GUIDS > 0 then
 task.spawn(function()
 task.wait(0.5)
 -- EquipHeroWithData: daftarkan hero ke map saat ini
 if RE.EquipHeroWithData then
 for _, hGuid in ipairs(HERO_GUIDS) do
 pcall(function()
 RE.EquipHeroWithData:FireServer({
 heroGuid = hGuid,
 userId = MY_USER_ID,
 })
 end)
 task.wait(0.1)
 end
 end
 -- HeroStandTo ke posisi player sekarang
 if RE.HeroStand then
 local char = LP.Character
 local hrp = char and char:FindFirstChild("HumanoidRootPart")
 local spawnPos = (hrp and hrp.Position) or Vector3.new(0, 0, 0)
 pcall(function()
 RE.HeroStand:FireServer({
 userId = MY_USER_ID,
 standPos = spawnPos,
 })
 end)
 for _, hGuid in ipairs(HERO_GUIDS) do
 pcall(function()
 RE.HeroStand:FireServer({
 heroGuid = hGuid,
 userId = MY_USER_ID,
 standPos = spawnPos,
 })
 end)
 end
 end
 end)
 end

 -- 
 -- STEP 4: Di dalam raid - cari boss, TP, serang
 -- 
 RAID._raidDone = false
 local _raidSuccess = false

 local connS, connF
 local _reS = Remotes:FindFirstChild("ChallengeRaidsSuccess")
 local _reF = Remotes:FindFirstChild("ChallengeRaidsFail")
 if _reS then connS = _reS.OnClientEvent:Connect(function()
 RAID._raidDone = true; _raidSuccess = true
 end) end
 if _reF then connF = _reF.OnClientEvent:Connect(function()
 RAID._raidDone = true
 end) end

 -- [FIX v256] Reduced wait: 3s untuk map load, SAMBIL cari boss
 -- Sekarang: cari boss sejak detik ke-2 -> TP player+hero bareng -> Equip -> langsung serang
 RaidStatusUpdate("[..] Enter Map - loading...", Color3.fromRGB(160,148,135))
 local _loadWait = 0
 local _earlyBoss = nil
 while _loadWait < 3 and RAID.running and not RAID._raidDone do
  task.wait(0.5); _loadWait = _loadWait + 0.5
  if _loadWait >= 2 and not _earlyBoss then
   for _, e in ipairs(GetRaidEnemies()) do
    local n = e.model.Name:lower()
    if n:find("king",1,true) or n:find("arachnid",1,true) or n:find("buryura",1,true) or n:find("igris",1,true) or n:find("arch lich",1,true) or n:find("baran",1,true) or n:find("monarch",1,true) or n:find("boss",1,true) or n:find("beru",1,true) or n:find("legia",1,true) or n:find("ashborn",1,true) or n:find("antares",1,true) then
     _earlyBoss = e; break
    end
   end
  end
 end

 if RAID.running and not RAID._raidDone and RAID.autoKillBoss then
 local BOSS_KEYS = {
 "goblin king","giant arachnid","buryura","igris",
 "leader of the polar","arch lich","kargalgan","baran",
 "beru","grendal","monarch plague","frostborne","legia",
 "monarch beastly","beastly fangs","silas","unbreakable monarch",
 "yogumunt","monarch of transfiguration","transfiguration",
 "antares","ashborn","dominion","absolute","monarch","fragment","boss",
 }
 local function IsBoss(name)
 local n = name:lower()
 for _, k in ipairs(BOSS_KEYS) do if n:find(k,1,true) then return true end end
 return false
 end

 -- Pakai boss dari early detection kalau sudah ada
 local boss = _earlyBoss
 if boss and not IsBoss(boss.model.Name) then boss = nil end

 -- Cari boss max 15s (kalau belum ketemu dari early)
 local waitBoss = 0
 while RAID.running and not boss and waitBoss < 15 and not RAID._raidDone do
 for _, e in ipairs(GetRaidEnemies()) do
 if IsBoss(e.model.Name) then boss = e; break end
 end
 if not boss then
 RaidStatusUpdate("Find Boss... (" .. math.floor(waitBoss) .. "s/15s)", Color3.fromRGB(160,148,135))
 task.wait(0.5); waitBoss = waitBoss + 0.5
 end
 end

 if boss and RAID.running and not RAID._raidDone then
 local bossGuid = boss.guid
 local bossPos = (boss.hrp and boss.hrp.Position) or Vector3.new(0,0,0)
 -- [v259] Teleport delay user-controlled (RAID.bossDelay 1-10s)
 local _bd = math.max(1, math.min(10, RAID.bossDelay or 3))
 for _ci = _bd, 1, -1 do
 if not RAID.running or RAID._raidDone then break end
 RaidStatusUpdate("[K] Boss: "..boss.model.Name.." - TP ".._ci.."s...", Color3.fromRGB(255,160,60))
 task.wait(1)
 end
 if RAID.running and not RAID._raidDone then
 RaidStatusUpdate("[K] Boss: " .. boss.model.Name .. " - Attack!", Color3.fromRGB(255,80,80))

 -- 
 -- [v256] TP PLAYER + SEMUA HERO KE BOSS BARENG
 -- Tidak ada jeda - langsung TP semua sekaligus
 -- 

 -- 1) TP Player ke boss SEKARANG
 pcall(function()
 local char = LP.Character
 local hrp = char and char:FindFirstChild("HumanoidRootPart")
 if hrp then hrp.CFrame = CFrame.new(bossPos + Vector3.new(3,0,0)) end
 end)

 -- 2) TP SEMUA hero client-side ke boss SEKARANG
 pcall(function()
 local heroFolder = workspace:FindFirstChild("Heros")
 if heroFolder then
 for _, hModel in ipairs(heroFolder:GetChildren()) do
 local hHrp = hModel:FindFirstChild("HumanoidRootPart")
 if hHrp then
 hHrp.CFrame = CFrame.new(bossPos + Vector3.new(math.random(-2,2), 0, math.random(-2,2)))
 end
 end
 end
 end)

 -- 3) Fire SEMUA hero remote ke boss SEKARANG
 pcall(function() FireHeroRemotes(bossGuid, bossPos) end)
 if RE.HeroStand and #HERO_GUIDS > 0 then
 for _, hGuid in ipairs(HERO_GUIDS) do
 pcall(function()
 RE.HeroStand:FireServer({
 heroGuid = hGuid,
 userId = MY_USER_ID,
 standPos = bossPos + Vector3.new(1, 0, 1),
 })
 end)
 end
 end

 -- 4) UnEquip -> EquipBest (refresh hero di posisi boss)
 task.wait(0.3)
 if RE.UnEquipHero then
 pcall(function() RE.UnEquipHero:FireServer() end)
 end
 task.wait(0.3)
 if RE.EquipBestHero then
 pcall(function() RE.EquipBestHero:FireServer() end)
 end
 task.wait(0.3)

 -- 5) TP ulang semua hero setelah re-equip (hero spawn ulang di posisi baru)
 pcall(function()
 local heroFolder = workspace:FindFirstChild("Heros")
 if heroFolder then
 for _, hModel in ipairs(heroFolder:GetChildren()) do
 local hHrp = hModel:FindFirstChild("HumanoidRootPart")
 if hHrp then
 hHrp.CFrame = CFrame.new(bossPos + Vector3.new(math.random(-2,2), 0, math.random(-2,2)))
 end
 end
 end
 end)
 pcall(function() FireHeroRemotes(bossGuid, bossPos) end)

 -- 6) Background thread: TP player+hero terus ke boss tiap 0.5s
 local _tpTh = task.spawn(function()
 while RAID.running and not RAID._raidDone do
 pcall(function()
 local pos = (boss.hrp and boss.hrp.Position) or bossPos
 -- TP player
 local char = LP.Character
 local hrp = char and char:FindFirstChild("HumanoidRootPart")
 if hrp then hrp.CFrame = CFrame.new(pos + Vector3.new(3,0,0)) end
 -- TP semua hero
 local heroFolder = workspace:FindFirstChild("Heros")
 if heroFolder then
 for _, hModel in ipairs(heroFolder:GetChildren()) do
 local hHrp = hModel:FindFirstChild("HumanoidRootPart")
 if hHrp then
 hHrp.CFrame = CFrame.new(pos + Vector3.new(math.random(-2,2), 0, math.random(-2,2)))
 end
 end
 end
 -- Fire hero remotes
 FireHeroRemotes(bossGuid, pos)
 if RE.HeroStand then
 for _, hGuid in ipairs(HERO_GUIDS) do
 pcall(function()
 RE.HeroStand:FireServer({
 heroGuid = hGuid,
 userId = MY_USER_ID,
 standPos = pos + Vector3.new(1, 0, 1),
 })
 end)
 end
 end
 end)
 task.wait(0.5)
 end
 end)

 -- 7) SERANG BOSS - langsung tanpa jeda
 RaidStatusUpdate("[FLa] Attack: " .. boss.model.Name, Color3.fromRGB(255,80,80))
 while RAID.running and not RAID._raidDone do
 if not boss.model or not boss.model.Parent then break end
 local hum = boss.model:FindFirstChildOfClass("Humanoid")
 if hum and hum.Health <= 0 then break end
 local p = (boss.hrp and boss.hrp.Position) or bossPos
 task.spawn(function() pcall(function() RaidFireDamage(bossGuid, p) end) end)
 task.wait(0.08)
 end

 pcall(function() task.cancel(_tpTh) end)
 _raidSuccess = true
 RAID._raidDone = true
 RaidStatusUpdate("[FLa] Boss Dead!", Color3.fromRGB(100,255,150))
 end -- if RAID.running after delay
 else
 -- Boss tidak ditemukan setelah 15s
 if RAID.running then
 RaidStatusUpdate("[FLa] Boss not found - Go Out...", Color3.fromRGB(255,150,50))
 task.wait(3)
 end
 end -- if boss
 elseif RAID.running and not RAID._raidDone then
 -- Auto Kill Boss OFF - tunggu event ChallengeRaidsSuccess max 5 menit
 local _wt = 0
 while RAID.running and not RAID._raidDone and _wt < 300 do
 task.wait(1); _wt = _wt + 1
 end
 end

 if connS then pcall(function() connS:Disconnect() end) end
 if connF then pcall(function() connF:Disconnect() end) end

 if _raidSuccess then
 RAID.sukses = RAID.sukses + 1
 RaidCounterUpdate()
 RaidStatusUpdate("[OK] Succes-" .. RAID.sukses .. " Map " .. mn, Color3.fromRGB(100,255,150))
 end
 if not RAID.running then break end

 -- 
 if _raidSuccess then
  RaidStatusUpdate("[..] Wait 1s (Get reward)...", Color3.fromRGB(100,255,150))
  task.wait(1)
 end
 if not RAID.running then break end

 -- STEP 5: Collect + Exit raid
 -- 
 task.spawn(function() pcall(RaidCollectAll) end)
 RaidStatusUpdate("[FLa] Go Out raid...", Color3.fromRGB(100,200,255))

 -- Hide reward panel
 task.spawn(function()
 task.wait(0.3)
 pcall(function()
 for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
 if obj.Name == "RewardsFrame" and obj:IsA("Frame") and obj.Visible then
 obj.Visible = false
 end
 end
 end)
 end)

 RAID_LIVE[RAID.raidId] = nil
 RebuildRaidList()

 -- [v247] STEP 6: Selalu TP ke MapId 50001 (Map 1) setelah raid selesai
 -- Reward sudah di-collect bersamaan saat boss mati (RaidCollectAll di atas)
 local _toMapId = 50001
 RaidStatusUpdate("[FLa] Go Out -> Map 1...", Color3.fromRGB(200,100,100))

 -- Helper TP sesuai range map
 local function _fireTpRaid(mapId)
 local m = mapId - 50000
 if m >= 1 and m <= 4 then
 pcall(function() RE.StartTp:FireServer({ mapId = mapId }) end)
 else
 pcall(function() RE.LocalTp:FireServer({ mapId = mapId }) end)
 end
 end

 -- Cek masih di area raid
 local function _inRaidArea()
 local ok = false
 pcall(function()
 local wm = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
 if wm then
 ok = (wm >= 50101 and wm <= 50118) or (wm >= 50301 and wm <= 50318)
 end
 end)
 return ok
 end

 if true then -- [INDEPENDEN] tidak cek siege
 -- Kirim QuitRaidsMap + TpRemote berlapis
 local _quitRe = Remotes:FindFirstChild("QuitRaidsMap")
 if _quitRe then
 pcall(function()
 _quitRe:FireServer({ currentSlotIndex = RAID.slotIndex, toMapId = _toMapId })
 end)
 end
 task.wait(0.3)
 _fireTpRaid(_toMapId)

 -- Retry max 5x kalau masih di raid area
 local _exitTry = 0
 while _inRaidArea() and _exitTry < 5 and RAID.running do
 _exitTry = _exitTry + 1
 task.wait(1)
 if _quitRe then
 pcall(function()
 _quitRe:FireServer({ currentSlotIndex = RAID.slotIndex, toMapId = _toMapId })
 end)
 end
 task.wait(0.2)
 _fireTpRaid(_toMapId)
 end
 end

 RAID.fromMapId = nil
 RAID.inMap = false

 -- 
 -- STEP 6: Resume MA -> cooldown
 -- 
 _raidInterrupt = false
 MODE:Release("raid") -- [FIX v257] MA HARUS resume saat player di luar raid
 -- [FIX v256] Cooldown 12s: server butuh ~12s sebelum bisa masuk Raid lagi
 -- TAPI: selama cooldown, tetap scan workspace agar RAID_LIVE siap
 -- Saat cooldown habis, langsung masuk tanpa delay tambahan
 for cd = 12, 1, -1 do
 if not RAID.running then break end
 -- [INDEPENDEN] tidak tunggu siege setelah exit raid
 -- Scan workspace selama cooldown agar data siap
 if cd % 3 == 0 then ForceRescanRaidEnter() end
 RaidStatusUpdate("[..] Cooldown " .. cd .. "s...", Color3.fromRGB(160,148,135))
 if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
 task.wait(1)
 end

 -- [v247] STEP 7: Setelah cooldown selesai:
 -- 1. Jika SIEGE aktif/running -> tunggu SIEGE selesai total dulu (PRIORITAS atas MA)
 -- 2. Setelah SIEGE selesai -> baru MA bisa resume (via _raidInterrupt=false)
 -- 3. Jika tidak ada SIEGE -> MA langsung resume
 if RAID.running then
 RaidStatusUpdate("[>>] Waiting & Cooldown...", Color3.fromRGB(100,255,150))
 if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
 local _fw = 0
 while RAID.running do
 -- [FIX v256] Agresif: manual scan workspace tiap cycle
 ForceRescanRaidEnter()
 -- Cek IsRaidLiveInGame DULU sebelum ResolveEntry
 if IsRaidLiveInGame() then
 if ResolveEntry and ResolveEntry() then break end
 RaidStatusUpdate("[FLa] Waiting grade filter... (" .. _fw .. "s)", Color3.fromRGB(200,255,150))
 else
 RaidStatusUpdate("[FLa] Empty RAID - Waiting... (" .. _fw .. "s)", Color3.fromRGB(160,120,60))
 end
 -- [FIX v256] Wakeup CEPAT: poll 0.05s, max 0.5s
 local _woken2 = false
 local _wConn2
 if _raidWakeup then
 _wConn2 = _raidWakeup.Event:Connect(function() _woken2 = true end)
 end
 local _we2 = 0
 while not _woken2 and _we2 < 1 and RAID.running do
 task.wait(0.1); _we2 = _we2 + 0.1
 end
 if _wConn2 then pcall(function() _wConn2:Disconnect() end) end
 _fw = _fw + 1
 end
 end

 end -- while RAID.running

 _raidInterrupt = false
 RAID.running = false
 RAID.inMap = false
 _raidOn = false
 MODE:Release("raid") -- [v257] pastikan MA bisa resume
 RaidStatusUpdate("[FLa] Auto Raid STOP", Color3.fromRGB(160,148,135))
 if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
 end)
end

-- 

-- ============================================================
-- do (webhook + raid logic)

-- ============================================================

-- ============================================================
-- PANEL : AUTOMATION - Auto Raid UI [v259 REWRITE]
-- ============================================================
do
 local p = NewPanel("autoraid")
 SectionHeader(p,"Automation",0)

 -- 
 -- DROPDOWN: AUTO RAID [v262 REWRITE]
 -- 
 local raidOpen = false

 local raidHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,42))
 raidHeader.LayoutOrder=1; Corner(raidHeader,10); Stroke(raidHeader,C.ACC, 1.5,0.4)
 local raidArrow = Label(raidHeader,">",13,C.ACC2,Enum.Font.GothamBold)
 raidArrow.Size=UDim2.new(0,22,1,0); raidArrow.Position=UDim2.new(0,10,0,0)
 local raidHeaderLbl = Label(raidHeader,"Auto Raid",14,C.TXT,Enum.Font.GothamBold)
 raidHeaderLbl.Size=UDim2.new(1,-50,1,0); raidHeaderLbl.Position=UDim2.new(0,34,0,0)

 local raidBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
 raidBody.LayoutOrder=2; raidBody.ClipsDescendants=true
 Corner(raidBody,10); Stroke(raidBody,C.ACC, 1.5,0.25); raidBody.Visible=false

 local raidInner = Frame(raidBody, C.BLACK, UDim2.new(1,-16,0,0))
 raidInner.BackgroundTransparency=1; raidInner.Position=UDim2.new(0,8,0,8)
 local raidLayout = New("UIListLayout",{Parent=raidInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

 function ResizeRaidBody()
 task.spawn(function()
 task.wait(0)
 raidLayout:ApplyLayout()
 local h = raidLayout.AbsoluteContentSize.Y + 16
 raidInner.Size = UDim2.new(1,0,0,h)
 raidBody.Size = UDim2.new(1,0,0,h+16)
 end)
 end

 raidHeader.MouseButton1Click:Connect(function()
 raidOpen = not raidOpen; raidBody.Visible = raidOpen
 raidArrow.Text = raidOpen and "v" or ">"
 if raidOpen then task.defer(ResizeRaidBody) end
 end)

 --  ICON GEMBOK HELPER 
 local LOCK_ICON = ""

 --  ROW 1: STATUS 
 local statusCard = Frame(raidInner, C.SURFACE, UDim2.new(1,0,0,38))
 statusCard.LayoutOrder=1; Corner(statusCard, 10); Stroke(statusCard,C.BORD, 1.5,0.3)
 Padding(statusCard,6,6,10,10)
 local _raidDot = Frame(statusCard, Color3.fromRGB(100,100,100), UDim2.new(0,9,0,9))
 _raidDot.AnchorPoint=Vector2.new(0,0.5); _raidDot.Position=UDim2.new(0,0,0.5,0); Corner(_raidDot,5)
 RAID.dot = _raidDot
 local _statusKeyL = Label(statusCard,"Status",11,C.TXT3,Enum.Font.GothamBold)
 _statusKeyL.Size=UDim2.new(0,54,1,0); _statusKeyL.Position=UDim2.new(0,16,0,0)
 local _raidStatusLbl = Label(statusCard,"Disabled",11,Color3.fromRGB(160,148,135),Enum.Font.GothamBold)
 _raidStatusLbl.Size=UDim2.new(1,-76,1,0); _raidStatusLbl.Position=UDim2.new(0,70,0,0)
 _raidStatusLbl.TextXAlignment=Enum.TextXAlignment.Right
 _raidStatusLbl.TextTruncate=Enum.TextTruncate.AtEnd
 RAID.statusLbl = _raidStatusLbl

 --  ROW 2: ACTIVE RAID 
 -- Hanya tampil saat RAID.inMap=true (sedang di dalam raid)
 local activeCard = Frame(raidInner, C.SURFACE, UDim2.new(1,0,0,38))
 activeCard.LayoutOrder=2; Corner(activeCard, 10); Stroke(activeCard,C.BORD, 1.5,0.3)
 Padding(activeCard,6,6,10,10)
 local _activeKeyL = Label(activeCard,"Active Raid",11,C.TXT3,Enum.Font.GothamBold)
 _activeKeyL.Size=UDim2.new(0,74,1,0)
 local _activeRaidLbl = Label(activeCard,"Waiting",11,C.TXT2,Enum.Font.GothamBold)
 _activeRaidLbl.Size=UDim2.new(1,-84,1,0); _activeRaidLbl.Position=UDim2.new(0,82,0,0)
 _activeRaidLbl.TextXAlignment=Enum.TextXAlignment.Right
 _activeRaidLbl.TextTruncate=Enum.TextTruncate.AtEnd
 RAID.activeRaidLbl = _activeRaidLbl

 -- [v262] Fungsi update Active Raid label - dipanggil langsung saat state berubah
 local function UpdateActiveRaidLabel()
 pcall(function()
 if not _activeRaidLbl or not _activeRaidLbl.Parent then return end
 if RAID.inMap and RAID.raidMapId then
 local rawMn = RAID.raidMapId - 50000
 -- Kalau Rune Map aktif, tampilkan map tujuan (bukan kendaraan)
 local mn = (RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 18) and RAID.runeMapTarget or rawMn
 local nm = MAP_NAMES and MAP_NAMES[mn] or ("Map "..tostring(mn))
 local grade = (_runeGradeCache and _runeGradeCache[mn]) or ""
 local gs = grade ~= "" and grade ~= "?" and (" ["..grade.."]") or ""
 _activeRaidLbl.Text = "Map "..mn.." - "..nm..gs
 _activeRaidLbl.TextColor3 = Color3.fromRGB(100,220,180)
 else
 _activeRaidLbl.Text = "Waiting"
 _activeRaidLbl.TextColor3 = C.TXT3
 end
 end)
 end
 -- Expose agar bisa dipanggil dari luar blok UI
 RAID.updateActiveLabel = UpdateActiveRaidLabel

 -- Polling ringan 0.3s sebagai safety net (update utama via RAID.updateActiveLabel)
 task.spawn(function()
 while true do
 task.wait(0.3)
 UpdateActiveRaidLabel()
 end
 end)

 --  ROW 3: RAID COMPLETED 
 local completedCard = Frame(raidInner, C.SURFACE, UDim2.new(1,0,0,38))
 completedCard.LayoutOrder=3; Corner(completedCard, 10); Stroke(completedCard,C.BORD, 1.5,0.3)
 Padding(completedCard,6,6,10,10)
 local _compKeyL = Label(completedCard,"Raid Completed",11,C.TXT3,Enum.Font.GothamBold)
 _compKeyL.Size=UDim2.new(0.65,0,1,0)
 local _raidSuksesLbl = Label(completedCard,"0",11,Color3.fromRGB(110,231,183),Enum.Font.GothamBold)
 _raidSuksesLbl.Size=UDim2.new(0.35,0,1,0); _raidSuksesLbl.Position=UDim2.new(0.65,0,0,0)
 _raidSuksesLbl.TextXAlignment=Enum.TextXAlignment.Right
 RAID.suksesLbl = _raidSuksesLbl
 RAID.loopLbl = nil; RAID.killLbl = nil

 --  ROW 4: ENABLE AUTO RAID TOGGLE 
 local ctrlRow = Frame(raidInner, C.SURFACE, UDim2.new(1,0,0,44))
 ctrlRow.LayoutOrder=4; Corner(ctrlRow,10); Stroke(ctrlRow,C.ACC,1.5,0.2)
 local mL = Label(ctrlRow,"Enable Auto Raid",13,C.TXT,Enum.Font.GothamBold)
 mL.Size=UDim2.new(1,-68,0,20); mL.Position=UDim2.new(0,14,0.5,-10)
 local pill = Btn(ctrlRow,C.PILL_OFF,UDim2.new(0,52,0,30))
 pill.AnchorPoint=Vector2.new(1,0.5); pill.Position=UDim2.new(1,-12,0.5,0); Corner(pill,13)
 local knob = Frame(pill,C.KNOB_OFF,UDim2.new(0,24,0,24))
 knob.AnchorPoint=Vector2.new(0,0.5); knob.Position=UDim2.new(0,3,0.5,0); Corner(knob,10)
 pill.MouseButton1Click:Connect(function()
 _raidOn = not _raidOn
 TweenService:Create(pill,TweenInfo.new(0.16),{BackgroundColor3=_raidOn and C.PILL_ON or C.PILL_OFF}):Play()
 TweenService:Create(knob,TweenInfo.new(0.16),{
 Position=_raidOn and UDim2.new(1,-27,0.5,0) or UDim2.new(0,3,0.5,0),
 BackgroundColor3=_raidOn and C.KNOB_ON or C.KNOB_OFF,
 }):Play()
 if _raidOn then
 StartRaidLoop()
 else
 StopRaid()
 RaidStatusUpdate("Disabled",Color3.fromRGB(160,148,135))
 end
 end)

 --  PICK MODE 
 -- Default/Hard/Easy
 local PM_OPTS = {"Default","Hard","Easy"}
 local PM_KEYS = {"default","hard","easy"}
 local PM_COLORS = {
  Color3.fromRGB(148,195,255), -- Default: biru es
  Color3.fromRGB(255,80,80),   -- Hard: merah
  Color3.fromRGB(80,220,80),   -- Easy: hijau muda
 }
 local PM_DESC = {
  "Join a random raid without filters",
  "Always choose the largest map",
  "Always choose the smallest map",
 }
 local PM_TO_DIFF = {
  default="easy", hard="hard", easy="easy"
 }
 local curPM = 1
 RAID.pickMode = PM_KEYS[curPM]

 local pmHdr = Label(raidInner,"PICK MODE",10,C.TXT3,Enum.Font.GothamBold)
 pmHdr.LayoutOrder=5; pmHdr.Size=UDim2.new(1,0,0,14)
 local pmCard = Frame(raidInner,C.SURFACE,UDim2.new(1,0,0,40))
 pmCard.LayoutOrder=6; Corner(pmCard, 10); Stroke(pmCard,C.BORD, 1.5,0.3); Padding(pmCard,6,6,10,10)
 local _pmKeyL = Label(pmCard,"Pick Mode",11,C.TXT2,Enum.Font.GothamBold)
 _pmKeyL.Size=UDim2.new(0,72,1,0)
 local pmDDBtn = Btn(pmCard,C.BG3,UDim2.new(1,-82,0,28))
 pmDDBtn.Position=UDim2.new(0,80,0.5,-14); Corner(pmDDBtn,6); Stroke(pmDDBtn,C.BORD, 1.5,0.25)
 local pmDDLbl = Label(pmDDBtn," "..PM_OPTS[curPM],11,PM_COLORS[curPM],Enum.Font.GothamBold)
 pmDDLbl.Size=UDim2.new(1,-20,1,0)
 local pmArr = Label(pmDDBtn,"v",10,C.TXT3,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 pmArr.Size=UDim2.new(0,18,1,0); pmArr.Position=UDim2.new(1,-20,0,0)
 local pmDescLbl = Label(raidInner,PM_DESC[curPM],10,C.TXT3,Enum.Font.GothamBold)
 pmDescLbl.LayoutOrder=7; pmDescLbl.Size=UDim2.new(1,0,0,14)

 pmDDBtn.MouseButton1Click:Connect(function()
  CloseActiveDD()
  local aP=pmDDBtn.AbsolutePosition; local aS=pmDDBtn.AbsoluteSize; local IH=28
  local popup=Instance.new("Frame")
  popup.Parent=DDLayer; popup.BackgroundColor3=C.DD_BG; popup.BorderSizePixel=0
  popup.Size=UDim2.new(0,aS.X+10,0,#PM_OPTS*(IH+2)+12)
  popup.Position=UDim2.new(0,aP.X,0,aP.Y+aS.Y+3)
  popup.ZIndex=9999; Corner(popup, 10); Stroke(popup,C.BORD2, 1.5,0.85)
  local ll=Instance.new("UIListLayout",popup)
  ll.Padding=UDim.new(0,2); ll.SortOrder=Enum.SortOrder.LayoutOrder
  Instance.new("UIPadding",popup).PaddingTop=UDim.new(0,4)
  for i,opt in ipairs(PM_OPTS) do
   local item=Instance.new("TextButton",popup)
   item.Size=UDim2.new(1,-8,0,IH); item.LayoutOrder=i
   item.BackgroundColor3=i==curPM and C.SURFACE or C.BG3
   item.BackgroundTransparency=i==curPM and 0.18 or 0.42
   item.BorderSizePixel=0; item.Text=""; item.AutoButtonColor=false; item.ZIndex=9999
   Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)
   local iL=Instance.new("TextLabel",item)
   iL.Size=UDim2.new(1,-8,1,0); iL.Position=UDim2.new(0,8,0,0)
   iL.BackgroundTransparency=1; iL.Text=opt; iL.TextSize=12
   iL.Font=Enum.Font.Gotham; iL.TextColor3=PM_COLORS[i]
   iL.TextXAlignment=Enum.TextXAlignment.Left; iL.ZIndex=9999
   local ii=i
   item.MouseButton1Click:Connect(function()
    CloseActiveDD()
    curPM=ii; RAID.pickMode=PM_KEYS[ii]
    RAID.difficulty=PM_TO_DIFF[PM_KEYS[ii]]; RAID.snapshotMapId=nil
    pmDDLbl.Text=" "..PM_OPTS[ii]; pmDDLbl.TextColor3=PM_COLORS[ii]
    pmDescLbl.Text=PM_DESC[ii]
    task.defer(ResizeRaidBody)
   end)
  end
  DDLayer.Visible=true
  _activeDDClose=function() popup:Destroy(); DDLayer.Visible=false end
 end)

 --  AUTO BOSS KILL TOGGLE 
 local bossRow=Frame(raidInner,C.SURFACE,UDim2.new(1,0,0,44))
 bossRow.LayoutOrder=16; Corner(bossRow,10); Stroke(bossRow,C.BORD, 1.5,0.3)
 local bL=Label(bossRow,"AUTO KILL BOSS",13,C.TXT,Enum.Font.GothamBold)
 bL.Size=UDim2.new(1,-68,0,20); bL.Position=UDim2.new(0,14,0.5,-10)
 local bPill=Btn(bossRow,C.PILL_OFF,UDim2.new(0,52,0,30))
 bPill.AnchorPoint=Vector2.new(1,0.5); bPill.Position=UDim2.new(1,-12,0.5,0); Corner(bPill,13)
 local bKnob=Frame(bPill,C.KNOB_OFF,UDim2.new(0,24,0,24))
 bKnob.AnchorPoint=Vector2.new(0,0.5); bKnob.Position=UDim2.new(0,3,0.5,0); Corner(bKnob,10)
 bPill.MouseButton1Click:Connect(function()
 RAID.autoKillBoss=not RAID.autoKillBoss; local on=RAID.autoKillBoss
 TweenService:Create(bPill,TweenInfo.new(0.18,Enum.EasingStyle.Quad),{BackgroundColor3=on and C.PILL_ON or C.PILL_OFF}):Play()
 TweenService:Create(bKnob,TweenInfo.new(0.16),{
 Position=on and UDim2.new(1,-27,0.5,0) or UDim2.new(0,3,0.5,0),
 BackgroundColor3=on and C.KNOB_ON or C.KNOB_OFF,
 }):Play()
 end)

 --  TELEPORT DELAY SLIDER (1-10s) 
 local tpCard=Frame(raidInner,C.SURFACE,UDim2.new(1,0,0,54))
 tpCard.LayoutOrder=17; Corner(tpCard, 10); Stroke(tpCard,C.BORD, 1.5,0.3); Padding(tpCard,6,6,10,10)
 New("UIListLayout",{Parent=tpCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})
 -- Baris label + nilai
 local tpTop=Frame(tpCard,C.BLACK,UDim2.new(1,0,0,18)); tpTop.BackgroundTransparency=1; tpTop.LayoutOrder=0
 local _tpKeyL=Label(tpTop,"Teleport Delay",11,C.TXT2,Enum.Font.GothamBold); _tpKeyL.Size=UDim2.new(0.7,0,1,0)
 local tpValLbl=Label(tpTop,tostring(RAID.bossDelay).."s",11,C.ACC2,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
 tpValLbl.Size=UDim2.new(0.3,0,1,0); tpValLbl.Position=UDim2.new(0.7,0,0,0)
 -- Baris slider: - [track] +
 local tpBot=Frame(tpCard,C.BLACK,UDim2.new(1,0,0,22)); tpBot.BackgroundTransparency=1; tpBot.LayoutOrder=1
 New("UIListLayout",{Parent=tpBot,SortOrder=Enum.SortOrder.LayoutOrder,
 FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,4),
 VerticalAlignment=Enum.VerticalAlignment.Center})
 -- Tombol minus
 local tpMinus=Btn(tpBot,C.BG3,UDim2.new(0,26,0,22))
 tpMinus.LayoutOrder=0; Corner(tpMinus,6); Stroke(tpMinus,C.BORD, 1.5,0.4)
 Label(tpMinus,"-",14,C.TXT,Enum.Font.GothamBold,Enum.TextXAlignment.Center).Size=UDim2.new(1,0,1,0)
 -- Track slider (TextButton untuk support input Delta)
 local tpTrackBtn=Btn(tpBot,C.BG3,UDim2.new(1,-60,0,22))
 tpTrackBtn.LayoutOrder=1; Corner(tpTrackBtn,11); Stroke(tpTrackBtn,C.BORD, 1.5,0.4)
 local tpFill=Frame(tpTrackBtn,C.ACC,UDim2.new((RAID.bossDelay-1)/9,1,1,-2))
 tpFill.Position=UDim2.new(0,0,0,1); Corner(tpFill,10)
 local tpKnob=Frame(tpTrackBtn,C.KNOB_ON,UDim2.new(0,18,0,18))
 tpKnob.AnchorPoint=Vector2.new(0.5,0.5); tpKnob.Position=UDim2.new((RAID.bossDelay-1)/9,0,0.5,0)
 Corner(tpKnob,9); Stroke(tpKnob,C.ACC, 1.5,0.6)
 -- Tombol plus
 local tpPlus=Btn(tpBot,C.BG3,UDim2.new(0,26,0,22))
 tpPlus.LayoutOrder=2; Corner(tpPlus,6); Stroke(tpPlus,C.BORD, 1.5,0.4)
 Label(tpPlus,"+",14,C.TXT,Enum.Font.GothamBold,Enum.TextXAlignment.Center).Size=UDim2.new(1,0,1,0)
 -- Update fungsi slider
 local function UpdateTpSlider(val)
 val=math.clamp(math.round(val),1,10)
 RAID.bossDelay=val; tpValLbl.Text=val.."s"
 tpFill.Size=UDim2.new((val-1)/9,1,1,-2)
 tpKnob.Position=UDim2.new((val-1)/9,0,0.5,0)
 end
 tpMinus.MouseButton1Click:Connect(function() UpdateTpSlider(RAID.bossDelay-1) end)
 tpPlus.MouseButton1Click:Connect(function() UpdateTpSlider(RAID.bossDelay+1) end)
 -- Drag slider
 local _tpDrag=false
 tpTrackBtn.InputBegan:Connect(function(inp)
 if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
 _tpDrag=true
 local tA=tpTrackBtn.AbsolutePosition; local tS=tpTrackBtn.AbsoluteSize
 UpdateTpSlider(math.round(math.clamp((inp.Position.X-tA.X)/tS.X,0,1)*9)+1)
 end
 end)
 tpTrackBtn.InputChanged:Connect(function(inp)
 if not _tpDrag then return end
 if inp.UserInputType~=Enum.UserInputType.MouseMovement and inp.UserInputType~=Enum.UserInputType.Touch then return end
 local tA=tpTrackBtn.AbsolutePosition; local tS=tpTrackBtn.AbsoluteSize
 UpdateTpSlider(math.round(math.clamp((inp.Position.X-tA.X)/tS.X,0,1)*9)+1)
 end)
 tpTrackBtn.InputEnded:Connect(function(inp)
 if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
 _tpDrag=false
 end
 end)

 --  APPLY PICK MODE LOCK 
 -- Lock/unlock field berdasarkan Pick Mode
 -- Tampilkan gembok pada field yang terkunci
 local function SetFieldLock(card, lockLbl, keyLbl, ddBtn, locked)
 -- Visual: dimming card
 card.BackgroundTransparency = locked and 0.65 or 0.42
 -- Gembok: tampil saat locked
 if lockLbl then lockLbl.Visible = locked end
 -- Label judul: warna redup saat locked
 if keyLbl then keyLbl.TextColor3 = locked and C.TXT3 or C.TXT2 end
 -- Tombol DD: transparansi
 if ddBtn then
 ddBtn.BackgroundTransparency = locked and 0.72 or 0.25
 for _,ch in ipairs(ddBtn:GetDescendants()) do
 if ch:IsA("TextLabel") then
 ch.TextTransparency = locked and 0.5 or 0
 end
 end
 end
 end

 ApplyPickModeLock=function()
 local pm=RAID.pickMode
 local unlock=PM_UNLOCK[pm] or {map=false,rank=false,rune=false}
 -- Update state variabel lock
 _prefLocked = not unlock.map
 _rankLocked = not unlock.rank
 _runeLocked = not unlock.rune
 -- Apply visual
 SetFieldLock(prefCard, _prefLockLbl, _prefKeyL, prefDDBtn, _prefLocked)
 SetFieldLock(rankCard, _rankLockLbl, _rankKeyL, rankDDWrap, _rankLocked)
 SetFieldLock(runeCard, _runeLockLbl, _runeKeyL, runeDDBtn, _runeLocked)
 -- Clear data dari field yang terkunci
 if _prefLocked then
 for k in pairs(RAID.preferMaps) do RAID.preferMaps[k]=nil end
 UpdatePrefLabel()
 end
 if _rankLocked then
 for _,g in ipairs(GRADE_LIST) do RAID.runeGrades[g]=nil end
 RefreshRankDDLabel()
 end
 if _runeLocked then
 RAID.runeMapTarget=0; RAID.runeEnabled=false
 runeDDVal.Text=" -- NOT SELECTED --"; runeDDVal.TextColor3=C.TXT3
 end
 -- Sync difficulty ke logic lama
 RAID.difficulty=PM_TO_DIFF[pm] or "easy"
 task.defer(ResizeRaidBody)
 end

 ApplyPickModeLock()
 task.defer(ResizeRaidBody)

end



-- ============================================================
-- AUTO SIEGE - v97 [v54 FIX: dead code removed, _exitConfirmCount reset on alive>0, threshold 3→5]
-- Flow: EnterCityRaidMap -> GetRaidTeamInfos -> StartLocalPlayerTeleport -> LocalTpSuccess -> GetRaidTeamInfos
-- -> MA V2 serang semua enemy sampai habis -> GainRaidsRewards(1)
-- -> TipsPanel hide/restore -> MA biasa resume setelah 3 detik
-- Trigger: Listener notif UpdateCityRaidInfo + polling fallback tiap 30 detik
-- ============================================================

local SIEGE_DATA = {
 -- baseMapId = MapId map asal (Script Viewer confirmed)
 -- tpMapId = RaidId siege map (50201-50204)
 -- [v245 FIX] Nama map disesuaikan dengan MAP_NAMES (referensi resmi)
 [3] = {name="Map 3 - Shadow Castle", cityRaidId=1000001, tpMapId=50201, baseMapId=50003},
 [7] = {name="Map 7 - Demon Castle Tier 2", cityRaidId=1000002, tpMapId=50202, baseMapId=50007},
 [10] = {name="Map 10 - Plagueheart", cityRaidId=1000003, tpMapId=50203, baseMapId=50010},
 [13] = {name="Map 13 - Lava Hell", cityRaidId=1000004, tpMapId=50204, baseMapId=50013},
}
local SIEGE_MAP_NUMS = {3, 7, 10, 13}

SIEGE = {
 running = false,
 thread = nil,
 inMap = false,
 excludeMaps = {[3]=false,[7]=false,[10]=false,[13]=false},
 statusLbl = nil,
 dot = nil,
 countLbls = {},
 count = {[3]=0,[7]=0,[10]=0,[13]=0},
 killed = 0, -- [v150] FIX: inisialisasi killed agar tidak nil saat EnemyDeath event
 live = {}, -- {[cityRaidId] = mapNum} - diisi notif server
}

--  UI helpers 
_siegeSessionStart = nil -- waktu mulai siege session

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
 SIEGE.countLbls[mn].Text = "SUCCES: "..(SIEGE.count[mn] or 0)
 end
 end
end

StopSiege = function()
 SIEGE.running = false
 SIEGE.inMap = false
 _siegeInterrupt = false
 MODE:Release("siege")
 -- [FIX] Hard reset MODE jika masih stuck di siege
 if MODE.current == "siege" then MODE.current = "idle" end
 if SIEGE.thread then
 pcall(function() task.cancel(SIEGE.thread) end)
 SIEGE.thread = nil
 end
 SiegeStatus("[FLa] Idle", Color3.fromRGB(100,100,100))
end

-- ============================================================
--  Wakeup event untuk siege loop 
-- [v113] Listener UpdateCityRaidInfo sudah dipasang di awal script (pre-wait).
-- ConnectSiegeNotif hanya dipakai untuk reconnect di StartSiegeLoop.
-- [v54] _siegeNotifConn & ConnectSiegeNotif dihapus - sudah tidak dipakai (listener permanen di pre-listen block)
local _siegeWakeup = nil

--  Masuk Siege 
-- ============================================================
-- AUTO SIEGE - REWRITE
-- Flow:
-- 1. Tunggu SIEGE.live ada entry (dari UpdateCityRaidInfo listener)
-- 2. Tunggu RAID.inMap = false (raid selesai dulu)
-- 3. Set _siegeInterrupt = true (pause MA/Raid)
-- 4. EnterCityRaidMap + konfirmasi masuk via workspace MapId (bukan LocalPlayerTeleportSuccess)
-- 5. Attack loop sampai enemy habis (max 60s)
-- 6. GainRaidsRewards + TP keluar pakai StartTp/LocalTp
-- 7. Reset _siegeInterrupt = false, resume MA/Raid
-- ============================================================

-- Helper: cek apakah player sedang di dalam siege map
-- Sumber: workspace MapId (50201-50204) ATAU workspace.Map.CityRaidEnter (Dex confirmed)
local function IsInSiegeMap()
    local ok, wm = pcall(function()
        return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
    end)
    -- Cek MapId siege langsung
    if ok and type(wm) == "number" then
        if wm >= 50201 and wm <= 50204 then return true, wm end
    end
    -- Cek CityRaidEnter di workspace (ada hanya saat player di dalam siege map)
    -- CEK INI DULU sebelum return false berdasarkan MapId
    -- Karena saat transisi TP, MapId bisa masih di value lobby padahal CityRaidEnter sudah ada
    local ok2, hasCRE = pcall(function()
        local mapFolder = workspace:FindFirstChild("Map")
        return mapFolder and mapFolder:FindFirstChild("CityRaidEnter") ~= nil
    end)
    if ok2 and hasCRE then return true, nil end
    -- Kalau MapId valid non-siege DAN CityRaidEnter tidak ada = memang bukan siege
    if ok and type(wm) == "number" and wm >= 50001 then return false, wm end
    return false, nil
end

-- [v54] SiegeTpOut dihapus - tidak dipakai, exit siege sudah via QuitCityRaidMap di StartSiegeLoop

-- ============================================================
-- ============================================================
-- [v236] SiegeAttackV2 - INDEPENDENT dari MA state
-- FIX #1: Reset _deadG global saat masuk (cegah ghost-dead dari MA/Raid sebelumnya)
-- FIX #2: GetSiegeEnemies brute-force scan workspace (tidak tergantung nama folder)
-- FIX #3: BlindFire fallback kalau GetSiegeEnemies tetap kosong setelah 5s
-- ============================================================

-- [v237] GetSiegeEnemies - Dex Explorer confirmed: enemy siege ada di workspace.Enemys
-- Jalur 1: workspace.Enemys (primary - confirmed Dex)
-- Jalur 2: fallback folder lain yang mungkin dipakai
-- Jalur 3: brute-force scan workspace top-level (last resort)
local function GetSiegeEnemies()
 local list = {
 }
 local seen = {}

    -- [v285 FIX] Scan semua folder (Garrison/Raid/Siege/Tower/Hero)
    local function scanFolder(f, label)
        local found = 0
        for _, e in ipairs(f:GetChildren()) do
            if e:IsA("Model") then
                local g = e:GetAttribute("EnemyGuid") or e:GetAttribute("Guid") or e:GetAttribute("GUID") or e:GetAttribute("guid") or e:GetAttribute("heroGuid")
                local h = e:FindFirstChild("HumanoidRootPart")
                local hum = e:FindFirstChildOfClass("Humanoid")
                
                local isAlive = false
                if h and e.Parent then
                    if hum then
                        isAlive = hum.Health > 0
                    else
                        isAlive = true
                    end
                end
                
                if isAlive then
                    local key = g or (e.Name .. tostring(e:GetDebugId()))
                    if not seen[key] then
                        seen[key] = true
                        table.insert(list, {model=e, guid=key, hrp=h, hasGuid=(g~=nil)})
                        found = found + 1
                    end
                end
            end
        end
    end

    -- Jalur 1: workspace.Enemys (Standar)
    local enemysFolder = workspace:FindFirstChild("Enemys")
    if enemysFolder then scanFolder(enemysFolder, "workspace.Enemys") end

    -- Jalur 2: Heros (Penting untuk Map 2 / Dungeon Boss)
    local herosFolder = workspace:FindFirstChild("Heros")
    if herosFolder then scanFolder(herosFolder, "workspace.Heros") end

    -- Jalur 3: Fallback folders
    local FALLBACK_FOLDERS = {
        "EnemyCityRaid", "CityRaidEnemys", "Enemies", "CityEnemy",
        "SiegeEnemys", "RaidEnemys", "Enemy",
    }
    for _, fname in ipairs(FALLBACK_FOLDERS) do
        local f = workspace:FindFirstChild(fname)
        if f then
            scanFolder(f, "fallback:" .. fname)
        end
    end

 -- Jalur 3: brute-force workspace.Map.CityRaidEnter (Dex: map siege ada di sini)
 -- Enemy bisa nested di dalam CityRaidEnter
 if #list == 0 then
 pcall(function()
 local mapF = workspace:FindFirstChild("Map")
 local cre = mapF and mapF:FindFirstChild("CityRaidEnter")
 if cre then
 for _, obj in ipairs(cre:GetDescendants()) do
 if obj:IsA("Model") then
 local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID") or obj:GetAttribute("guid")
 local h = obj:FindFirstChild("HumanoidRootPart")
 local hum = obj:FindFirstChildOfClass("Humanoid")
 if h and hum and hum.Health > 0 then
 local key = g or (obj.Name .. tostring(obj:GetDebugId()))
 if not seen[key] then
 seen[key] = true
 table.insert(list, {model=obj, guid=key, hrp=h, hasGuid=(g~=nil)})
 end
 end
 end
 end
 if #list > 0 then
 -- Enemy ditemukan di CityRaidEnter
 end
 end
 end)
 end

 return list
end

-- [FIX #3] BlindFire: tembak remotes ke semua Model Humanoid hidup di workspace
local function SiegeBlindFire()
 local targets = {}
 pcall(function()
 for _, obj in ipairs(workspace:GetDescendants()) do
 if obj:IsA("Model") then
 local hum = obj:FindFirstChildOfClass("Humanoid")
 local hrp = obj:FindFirstChild("HumanoidRootPart")
 if hum and hum.Health > 0 and hrp then
 local isPlayer = false
 for _, p in ipairs(Players:GetPlayers()) do
 if p.Character == obj then isPlayer = true; break end
 end
 if not isPlayer then
 table.insert(targets, {hrp=hrp, model=obj})
 end
 end
 end
 end
 end)

 if #targets == 0 then
 return false
 end

 for _, t in ipairs(targets) do
 local pos = t.hrp.Position
 -- [FIX #2] TIDAK TP fisik. Player tetap diam; hanya remote yang dikirim.
 local pseudoGuid = t.model:GetAttribute("EnemyGuid") or t.model:GetAttribute("GUID") or t.model:GetAttribute("Guid") or t.model:GetAttribute("guid")
 if pseudoGuid then
 pcall(function()
 if RE.Atk then RE.Atk:FireServer({attackEnemyGUID=pseudoGuid}) end
 end)
 pcall(function()
 if RE.Click then RE.Click:InvokeServer({enemyGuid=pseudoGuid, enemyPos=pos}) end
 end)
 for _, hGuid in ipairs(HERO_GUIDS) do
 pcall(function()
 if RE.HeroUseSkill then
 RE.HeroUseSkill:FireServer({
 heroGuid=hGuid, attackType=1,
 userId=MY_USER_ID, enemyGuid=pseudoGuid,
 })
 end
 end)
 end
 else
 pcall(function()
 if RE.Atk then RE.Atk:FireServer({attackEnemyPos=pos}) end
 end)
 end
 task.wait(0.05)
 end
 return true
end

local function SiegeAttackV2_Independent(onStatus)
    -- [v273 REWRITE] Logic baru:
    -- - Attack terus selama IsInSiegeMap() = true
    -- - Exit HANYA ketika server keluarkan player (MapId berubah keluar 50201-50204)
    -- - GRACE timer DIHAPUS - server yang tentukan kapan player keluar
    -- - BlindFire tetap ada sebagai fallback kalau GetSiegeEnemies kosong

    -- Fallback HERO_GUIDS scan
    if #HERO_GUIDS == 0 then
        if onStatus then onStatus("[~] Scan HERO_GUIDS...") end
        pcall(function()
            for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
                local g = obj:GetAttribute("heroGuid") or obj:GetAttribute("guid")
                if type(g) == "string" and IsValidUUID(g) then
                    local dup = false
                    for _, ex in ipairs(HERO_GUIDS) do if ex == g then dup = true; break end end
                    if not dup then table.insert(HERO_GUIDS, g) end
                end
            end
        end)
    end

    _deadG = {}
    local _deadLocal = {}
    local totalTime  = 0
    local _everSawEnemy = false
    local _blindFireMode = false
    local _blindFireTick = 0
    local MAX_TIME   = 300
    local _pollTick  = 0
    local _exitConfirmCount = 0
    -- [v276 FIX] Warmup: jangan cek IsInSiegeMap selama 3 detik pertama
    -- workspace.MapId butuh waktu update setelah TP masuk siege
    -- Tanpa ini: MapId masih di value lobby -> IsInSiegeMap=false -> exit prematur
    local WARMUP = 3.0

    while SIEGE.running and SIEGE.inMap do
        totalTime = totalTime + 0.1
        _pollTick = _pollTick + 0.1

        -- CEK EXIT: poll setiap 0.5s, hanya setelah warmup 3 detik
        -- Exit HANYA jika: server sudah keluarkan player (IsInSiegeMap=false)
        -- DAN enemy sudah habis (alive=0) ATAU sudah 2x konfirmasi false
        if totalTime >= WARMUP and _pollTick >= 0.5 then
            _pollTick = 0
            local inSiege, _ = IsInSiegeMap()
            if not inSiege then
                _exitConfirmCount = _exitConfirmCount + 1
                -- Exit segera kalau enemy 0, atau sudah 5x konfirmasi (enemy lobby terdeteksi)
                local rawE = GetSiegeEnemies()
                local liveCount = 0
                for _, e in ipairs(rawE) do
                    if e.model and e.model.Parent then
                        local hum = e.model:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then liveCount = liveCount + 1 end
                    end
                end
                -- [v273 FIX] Lebih sabar: butuh 15x konfirmasi (7.5 detik) 
                -- jika MapId tidak stabil atau musuh baru spawn
                if liveCount == 0 or _exitConfirmCount >= 15 then
                    SIEGE.inMap     = false
                    _siegeInterrupt = false
                    MODE:Release("siege")
                    if onStatus then onStatus("[OK] SIEGE DONE") end
                    return "exited_by_server"
                end
            else
                _exitConfirmCount = 0
            end
        end

        -- Timeout failsafe (server seharusnya keluarkan sebelum ini)
        if totalTime >= MAX_TIME then
            SIEGE.inMap     = false
            _siegeInterrupt = false
            MODE:Release("siege")
            if onStatus then onStatus("[!] Timeout " .. MAX_TIME .. "s - OUT") end
            return "timeout"
        end

        -- Scan enemies
        local rawEnemies = GetSiegeEnemies()
        local targets = {}
        for _, e in ipairs(rawEnemies) do
            if not _deadLocal[e.guid] and not (e.hasGuid and _deadG[e.guid]) then
                if e.model and e.model.Parent then
                    local hum = e.model:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        table.insert(targets, e)
                    end
                end
            end
        end

        local alive = #targets

        -- Guard: kalau sudah tidak di siege map, skip attack (cegah nyerang enemy lobby)
        local _shouldAttack = true
        if totalTime >= WARMUP and alive > 0 then
            local inSiege, _ = IsInSiegeMap()
            if not inSiege then _shouldAttack = false end
        end

        if alive > 0 and _shouldAttack then
            _everSawEnemy    = true
            _blindFireMode   = false
            _exitConfirmCount = 0  -- [v54 BUG FIX] Reset counter: jangan exit saat enemy masih ada
            -- Attack semua enemy hidup
            for _, e in ipairs(targets) do
                if e.model and e.model.Parent then
                    local hrp = e.model:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local g, pos = e.guid, hrp.Position
                        task.spawn(function()
                            pcall(function() FireAllDamage(g, pos) end)
                            if #HERO_GUIDS > 0 then
                                pcall(function() FireHeroRemotes(g, pos) end)
                            end
                        end)
                    end
                end
            end
            if onStatus then
                onStatus("[S] " .. alive .. " enemy (" .. math.floor(totalTime) .. "s)")
            end
        else
            -- Tidak ada enemy terdeteksi
            if not _everSawEnemy then
                -- Belum pernah lihat enemy sejak masuk
                if totalTime > 5 and not _blindFireMode then
                    _blindFireMode = true
                end
                if _blindFireMode then
                    _blindFireTick = _blindFireTick + 0.1
                    if _blindFireTick >= 0.5 then
                        _blindFireTick = 0
                        task.spawn(function() pcall(SiegeBlindFire) end)
                        if onStatus then
                            onStatus("[BF] BlindFire (" .. math.floor(totalTime) .. "s) - Waiting Enemy/Exit")
                        end
                    end
                    -- Kalau 12 detik masih tidak ketemu, tunggu server keluarkan
                    if totalTime > 12 then
                        if onStatus then onStatus("[~] Not Found Enemy - Wait exit...") end
                    end
                else
                    if onStatus then onStatus("[~] Waiting enemy (" .. math.floor(totalTime) .. "s)...") end
                end
            else
                -- Pernah lihat enemy, sekarang kosong
                -- TIDAK exit sendiri - tunggu server yang keluarkan player
                -- Server PASTI keluarkan player setelah semua enemy mati
                if onStatus then
                    onStatus("[OK] Enemy ALL GONE (" .. math.floor(totalTime) .. "s) - Wait exit...")
                end
                -- Tetap kirim serangan siapa tahu ada enemy tersisa yang tidak terdeteksi
                _blindFireTick = _blindFireTick + 0.1
                if _blindFireTick >= 1.0 then
                    _blindFireTick = 0
                    task.spawn(function() pcall(SiegeBlindFire) end)
                end
            end
        end

        task.wait(0.1)
    end
    return "loop_ended"
end


-- Re-scan state siege dari semua sumber
StartSiegeLoop = function()
 if SIEGE.running then StopSiege() end
 SIEGE.running = true
 SIEGE.inMap = false
 SIEGE.killed = 0
 _siegeSessionStart = os.time()
 for _, mn in ipairs(SIEGE_MAP_NUMS) do SIEGE.count[mn] = 0 end
 SiegeCounterUpdate()

 if _siegeWakeup then pcall(function() _siegeWakeup:Destroy() end) end
 _siegeWakeup = Instance.new("BindableEvent")

 if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
    -- Poll snapshot langsung saat toggle ON (handle relog / missed event)
    task.spawn(function()
        if _pollSiegeLive then _pollSiegeLive("toggle_on") end
    end)

    SIEGE.thread = task.spawn(function()

        while SIEGE.running do

            -- STEP 2: Scan SIEGE.live - cari siege yang open & tidak di-exclude
            local targetMap = nil
            for _, mn in ipairs(SIEGE_MAP_NUMS) do
                if SIEGE.excludeMaps and SIEGE.excludeMaps[mn] then continue end
                local cid = SIEGE_DATA[mn].cityRaidId
                if SIEGE.live[cid] then targetMap = mn; break end
            end

            if not targetMap then
                local featStr = ""
                if MA.running then featStr = " | MA aktif" end
                if RAID.running then featStr = featStr.." | Raid aktif" end
                local exNames = {}
                if SIEGE.excludeMaps then
                    for _, mn in ipairs(SIEGE_MAP_NUMS) do
                        if SIEGE.excludeMaps[mn] then table.insert(exNames,"M"..mn) end
                    end
                end
                local exStr = #exNames > 0 and (" skip:"..table.concat(exNames,",")) or ""
                SiegeStatus("[..] Waiting Siege"..exStr..featStr.."...", Color3.fromRGB(255,200,60))
                if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
                local conn = _siegeWakeup.Event:Connect(function() end)
                task.wait(1); conn:Disconnect()
                continue
            end

            -- Tunggu Raid selesai dulu kalau sedang di dalam
            local d = SIEGE_DATA[targetMap]
            if not RAID.running then RAID.inMap = false end
            if RAID.inMap then
                SiegeStatus("[FLa] Waiting Raid DONE...", Color3.fromRGB(255,140,0))
                local _wr = 0
                while RAID.inMap and SIEGE.running do
                    if not RAID.running then RAID.inMap = false; break end
                    task.wait(0.5); _wr = _wr + 0.5
                end
                if not SIEGE.running then break end
                task.wait(0.3)
            end

            -- Pause MA/Raid, ambil slot siege
            _siegeInterrupt = true
            if not MODE:WaitAndRequest("siege", 15) then
                _siegeInterrupt = false
                task.wait(2); continue
            end
            task.wait(0.3)
            if not SIEGE.running then _siegeInterrupt = false; MODE:Release("siege"); break end

            -- STEP 4: Masuk Siege
            SiegeStatus("[>>] Masuk "..d.name.."...", Color3.fromRGB(180,120,255))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(180,120,255) end

            -- 4A: EnterCityRaidMap (integer langsung, confirmed SimpleSpy)
            local enterRe = Remotes:FindFirstChild("EnterCityRaidMap")
            if not enterRe then
                _siegeInterrupt = false; MODE:Release("siege")
                SiegeStatus("[!] Not Found - retry 5s...", Color3.fromRGB(255,100,60))
                task.wait(5); continue
            end
            pcall(function() enterRe:FireServer(d.cityRaidId) end)
            task.wait(0.5)
            if not SIEGE.running then _siegeInterrupt = false; MODE:Release("siege"); break end

            -- 4A2: GetRaidTeamInfos
            local grtRe = Remotes:FindFirstChild("GetRaidTeamInfos")
            if grtRe then task.spawn(function() pcall(function() grtRe:InvokeServer() end) end) end
            task.wait(0.2)

            -- 4B: StartLocalPlayerTeleport
            local stpRe = Remotes:FindFirstChild("StartLocalPlayerTeleport")
            if stpRe then pcall(function() stpRe:FireServer({mapId=d.tpMapId}) end) end
            task.wait(0.3)

            -- 4C: EquipHeroWithData
            local eqRe = Remotes:FindFirstChild("EquipHeroWithData")
            if eqRe then pcall(function() eqRe:FireServer() end) end
            task.wait(0.2)

            -- 4D: LocalPlayerTeleportSuccess (RemoteFunction)
            local ltpRe = Remotes:FindFirstChild("LocalPlayerTeleportSuccess")
            if ltpRe then task.spawn(function() pcall(function() ltpRe:InvokeServer() end) end) end
            task.wait(0.2)

            -- 4E: GetRaidTeamInfos lagi
            local grtRe2 = Remotes:FindFirstChild("GetRaidTeamInfos")
            if grtRe2 then task.spawn(function() pcall(function() grtRe2:InvokeServer() end) end) end
            task.wait(0.2)
            if not SIEGE.running then _siegeInterrupt = false; MODE:Release("siege"); break end

            -- STEP 5: Konfirmasi masuk (max 8 detik, poll 0.5s)
            SiegeStatus("[FLa] Waiting Enter Siege...", Color3.fromRGB(180,120,255))
            local _entered = false
            local _entWait = 0
            while not _entered and _entWait < 8 and SIEGE.running do
                task.wait(0.5); _entWait = _entWait + 0.5
                local inSiege, _ = IsInSiegeMap()
                if inSiege then _entered = true; break end
                if #GetSiegeEnemies() > 0 then _entered = true; break end
                local hasCRE = false
                pcall(function()
                    local mf = workspace:FindFirstChild("Map")
                    hasCRE = mf and mf:FindFirstChild("CityRaidEnter") ~= nil
                end)
                if hasCRE then _entered = true; break end
            end

            if not _entered then
                _siegeInterrupt = false; MODE:Release("siege")
                SiegeStatus("[!] Failure Enter - retry 3s...", Color3.fromRGB(255,100,60))
                task.wait(3); continue
            end

            -- STEP 6: Attack sampai server keluarkan player (IsInSiegeMap false)
            SIEGE.inMap = true
            SiegeStatus("[S] "..d.name.." - Attack!", Color3.fromRGB(80,220,80))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(80,220,80) end

            local siegeResult = SiegeAttackV2_Independent(function(msg)
                SiegeStatus("[S] "..msg, Color3.fromRGB(80,220,80))
            end)
            if not SIEGE.running then break end

            -- STEP 7: Cleanup
            SIEGE.inMap = false
            _siegeInterrupt = false
            MODE:Release("siege")

            -- [FIX v273] Hapus QuitCityRaidMap paksa agar server yang mengeluarkan player 
            -- secara alami saat Siege benar-benar SUCCES/FAIL.
            -- qRe:FireServer({d.cityRaidId})
            task.wait(0.3)

            -- Auto-close popup reward
            task.spawn(function()
                local _w = 0
                local POPUP = {"CityFightPanel","RewardsFrame","ResultFrame","RewardPanel"}
                local KEYS  = {"close","tutup","ok","selesai","done","claim","lanjut"}
                while _w < 4 do
                    task.wait(0.3); _w = _w + 0.3
                    local found = false
                    pcall(function()
                        for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
                            if obj:IsA("TextButton") and obj.Visible and obj.Text ~= "" then
                                local low = obj.Text:lower():gsub("%s+","")
                                for _, k in ipairs(KEYS) do
                                    if low:find(k,1,true) then
                                        local r = obj
                                        while r.Parent and r.Parent ~= LP.PlayerGui do
                                            r=r.Parent
                                        end
                                        for _, pn in ipairs(POPUP) do
                                            if r.Name == pn then
                                                pcall(function() obj.Activated:Fire() end)
                                                pcall(function() obj.MouseButton1Click:Fire() end)
                                                found = true; break
                                            end
                                        end
                                    end
                                    if found then break end
                                end
                            end
                            if found then break end
                        end
                        if not found then
                            for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
                                if (obj:IsA("Frame") or obj:IsA("ScreenGui")) and obj.Visible then
                                    for _, pn in ipairs(POPUP) do
                                        if obj.Name == pn then obj.Visible=false; found=true; break end
                                    end
                                end
                                if found then break end
                            end
                        end
                    end)
                    if found then break end
                end
            end)

            -- Tandai selesai
            SIEGE.live[d.cityRaidId] = nil
            if _siegeChatOpen then _siegeChatOpen[targetMap] = false end
            SIEGE.count[targetMap] = (SIEGE.count[targetMap] or 0) + 1
            SiegeCounterUpdate()
            _siegeInterrupt = false
            MODE:Release("siege")
            SiegeStatus("[OK] "..d.name.." SUCCES! Waiting Next Siege...", Color3.fromRGB(100,255,150))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
            task.wait(2)

        end -- while SIEGE.running

 _siegeInterrupt = false
 MODE:Release("siege")
 SIEGE.running = false
 SIEGE.inMap = false
 SiegeStatus("[.] Idle", Color3.fromRGB(100,100,100))
 if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
 end)
end


-- PANEL : AUTO SIEGE (UI) - di dalam panel Automation yang sama
-- ============================================================
do
 local p = Panels["autoraid"]
 if not p then return end

 -- 
 -- AUTO SIEGE - Collapsible (seperti Auto Raid)
 -- 
 local siegeOpen = false

 local siegeHeader = Btn(p, C.SURFACE, UDim2.new(1,0,0,42))
 siegeHeader.LayoutOrder = 20; Corner(siegeHeader,10); Stroke(siegeHeader,C.BORD, 1.5,0.88)
 local siegeArrow = Label(siegeHeader,">",13,C.ACC,Enum.Font.GothamBold)
 siegeArrow.Size = UDim2.new(0,22,1,0); siegeArrow.Position = UDim2.new(0,10,0,0)
 local siegeHeaderLbl = Label(siegeHeader,"Auto Siege",14,C.TXT,Enum.Font.GothamBold)
 siegeHeaderLbl.Size = UDim2.new(1,-50,1,0); siegeHeaderLbl.Position = UDim2.new(0,34,0,0)

 local siegeBody = Frame(p, C.BG2, UDim2.new(1,0,0,0))
 siegeBody.LayoutOrder = 21; siegeBody.ClipsDescendants = true
 Corner(siegeBody,10); Stroke(siegeBody,C.BORD, 1.5,0.25); siegeBody.Visible = false

 local siegeInner = Frame(siegeBody, C.BLACK, UDim2.new(1,-16,0,0))
 siegeInner.BackgroundTransparency = 1; siegeInner.Position = UDim2.new(0,8,0,8)
 local siegeLayout = New("UIListLayout",{Parent=siegeInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

 local function ResizeSiegeBody()
 siegeLayout:ApplyLayout()
 local h = siegeLayout.AbsoluteContentSize.Y + 16
 siegeInner.Size = UDim2.new(1,0,0,h)
 siegeBody.Size = UDim2.new(1,0,0,h+16)
 end

 siegeHeader.MouseButton1Click:Connect(function()
 siegeOpen = not siegeOpen; siegeBody.Visible = siegeOpen
 siegeArrow.Text = siegeOpen and "v" or ">"
 if siegeOpen then task.defer(ResizeSiegeBody) end
 end)

 -- Gunakan siegeInner sebagai parent untuk semua konten siege
 local p = siegeInner -- shadow p agar kode di bawah tetap pakai p

 -- Status bar
 local statusCard = Frame(p, C.BG3, UDim2.new(1,0,0,32))
 statusCard.LayoutOrder = 0; Corner(statusCard, 10); Stroke(statusCard,C.ACC, 1.5,0.3)
 SIEGE.dot = Frame(statusCard, Color3.fromRGB(100,100,100), UDim2.new(0,8,0,8))
 SIEGE.dot.Position = UDim2.new(0,8,0.5,-4); Corner(SIEGE.dot,4)
 SIEGE.statusLbl = Label(statusCard,"Idle - SELECT MAP",10,C.TXT2,Enum.Font.GothamBold)
 SIEGE.statusLbl.Size = UDim2.new(1,-24,1,0)
 SIEGE.statusLbl.Position = UDim2.new(0,22,0,0)
 SIEGE.statusLbl.TextTruncate = Enum.TextTruncate.AtEnd

 -- Toggle utama
 ToggleRow(p,"Auto Siege","ON = Waiting Enter SIEGE",1,function(on)
 if on then StartSiegeLoop() else StopSiege() end
 end)

 -- [v273] EXCLUDE MAP: Semua map masuk by default, user pilih map yg di-skip
 -- SIEGE.excludeMaps = {[3]=false,[7]=false,[10]=false,[13]=false}
 -- mapActive selalu true kecuali map di-exclude
 if not SIEGE.excludeMaps then
 SIEGE.excludeMaps = {[3]=false,[7]=false,[10]=false,[13]=false}
 end
 -- Sync mapActive: semua ON kecuali yang di-exclude
 -- Counter card (sukses per map)
 local cntCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,0))
 cntCard.LayoutOrder = 2; cntCard.AutomaticSize = Enum.AutomaticSize.Y
 Corner(cntCard, 10); Stroke(cntCard,C.BORD, 1.5,0.5)
 New("UIPadding",{Parent=cntCard,PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,6),PaddingLeft=UDim.new(0, 10),PaddingRight=UDim.new(0, 10)})
 local cntInner = Frame(cntCard, C.BLACK, UDim2.new(1,0,0,0))
 cntInner.BackgroundTransparency=1; cntInner.AutomaticSize=Enum.AutomaticSize.Y
 New("UIListLayout",{Parent=cntInner,FillDirection=Enum.FillDirection.Horizontal,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4)})
 for _, mn in ipairs(SIEGE_MAP_NUMS) do
 local cntF = Frame(cntInner, C.BG3, UDim2.new(0.25,-4,0,28))
 cntF.LayoutOrder=mn; Corner(cntF,6)
 local cntLbl = Label(cntF,"M"..mn..": 0",9,C.ACC2,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 cntLbl.Size=UDim2.new(1,0,1,0)
 SIEGE.countLbls[mn] = cntLbl
 end

    -- ============================================================
    -- EXCLUDE MAP: Dropdown list pilih map yang di-skip
    -- ============================================================
    if not SIEGE.excludeMaps then
        SIEGE.excludeMaps = {[3]=false,[7]=false,[10]=false,[13]=false}
    end

    -- Dropdown button + list
    local ddCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,0))
    ddCard.LayoutOrder = 3; ddCard.AutomaticSize = Enum.AutomaticSize.Y
    Corner(ddCard, 10); Stroke(ddCard,C.BORD, 1.5,0.5)
    New("UIPadding",{Parent=ddCard,PaddingTop=UDim.new(0, 10),PaddingBottom=UDim.new(0, 10),PaddingLeft=UDim.new(0, 10),PaddingRight=UDim.new(0, 10)})

    local ddInner = Frame(ddCard, C.BLACK, UDim2.new(1,0,0,0))
    ddInner.BackgroundTransparency = 1; ddInner.AutomaticSize = Enum.AutomaticSize.Y
    New("UIListLayout",{Parent=ddInner,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

    -- Label judul
    local ddTitleRow = Frame(ddInner, C.BLACK, UDim2.new(1,0,0,16))
    ddTitleRow.BackgroundTransparency = 1; ddTitleRow.LayoutOrder = 0
    local ddTitleLbl = Label(ddTitleRow,"Exclude Map (Skip Siege):",10,C.TXT3,Enum.Font.GothamBold)
    ddTitleLbl.Size = UDim2.new(1,0,1,0)

    -- Dropdown button
    local ddBtn = Btn(ddInner, C.BG3, UDim2.new(1,0,0,32))
    ddBtn.LayoutOrder = 1; Corner(ddBtn, 10); Stroke(ddBtn,C.BORD, 1.5,0.5)
    local ddBtnLbl = Label(ddBtn,"  SELECT MAP to SKIP...",11,C.TXT2,Enum.Font.Gotham,Enum.TextXAlignment.Left)
    ddBtnLbl.Size = UDim2.new(1,-30,1,0)
    ddBtnLbl.Position = UDim2.new(0,0,0,0)
    local ddArrow = Label(ddBtn,"v",11,C.TXT3,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
    ddArrow.Size = UDim2.new(0,24,1,0)
    ddArrow.Position = UDim2.new(1,-26,0,0)

    -- List container (dropdown menu, collapse/expand)
    local ddList = Frame(ddInner, C.BG2, UDim2.new(1,0,0,0))
    ddList.LayoutOrder = 2; ddList.AutomaticSize = Enum.AutomaticSize.Y
    ddList.Visible = false; Corner(ddList, 10); Stroke(ddList,C.BORD, 1.5,0.3)
    New("UIPadding",{Parent=ddList,PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,4),PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6)})
    New("UIListLayout",{Parent=ddList,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)})

    local MAP_NAMES_SIEGE = {
        [3]  = "Map 3  - Shadow Castle",
        [7]  = "Map 7  - Demon Castle Tier 2",
        [10] = "Map 10 - Plagueheart",
        [13] = "Map 13 - Lava Hell",
    }

    -- Helper: update label ringkasan di button
    local function updateDdLabel()
        local exNames = {}
        for _, mn in ipairs(SIEGE_MAP_NUMS) do
            if SIEGE.excludeMaps[mn] then table.insert(exNames,"Map "..mn) end
        end
        if #exNames == 0 then
            ddBtnLbl.Text = "  ALL MAP ACTIVE"
            ddBtnLbl.TextColor3 = C.GRN
        else
            ddBtnLbl.Text = "  Skip: "..table.concat(exNames,", ")
            ddBtnLbl.TextColor3 = Color3.fromRGB(255,160,60)
        end
    end

    -- Buat row untuk tiap map
    local itemRefs = {}
    for _, mn in ipairs(SIEGE_MAP_NUMS) do
        local mn_l = mn
        local row = Btn(ddList, C.SURFACE, UDim2.new(1,0,0,30))
        row.LayoutOrder = mn; Corner(row,6); row.AutoButtonColor = false

        -- Checkbox indicator
        local chk = Frame(row, C.BG3, UDim2.new(0,16,0,16))
        chk.Position = UDim2.new(0,6,0.5,-8); Corner(chk,4)
        Stroke(chk, C.BORD, 1.5, 0.3)
        local chkMark = Label(chk,"",10,Color3.fromRGB(255,255,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
        chkMark.Size = UDim2.new(1,0,1,0)
        chkMark.Text = SIEGE.excludeMaps[mn] and "x" or ""

        -- Map name label
        local rowLbl = Label(row, MAP_NAMES_SIEGE[mn], 11, C.TXT, Enum.Font.Gotham, Enum.TextXAlignment.Left)
        rowLbl.Size = UDim2.new(1,-30,1,0)
        rowLbl.Position = UDim2.new(0,28,0,0)

        -- Badge "SKIP" / "MASUK"
        local badge = Frame(row, C.BG3, UDim2.new(0,44,0,18))
        badge.Position = UDim2.new(1,-50,0.5,-9); Corner(badge,5)
        local badgeLbl = Label(badge, SIEGE.excludeMaps[mn] and "SKIP" or "ENTER", 9,
            SIEGE.excludeMaps[mn] and Color3.fromRGB(255,120,60) or C.GRN,
            Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        badgeLbl.Size = UDim2.new(1,0,1,0)

        itemRefs[mn] = {row=row, chkMark=chkMark, rowLbl=rowLbl, badge=badge, badgeLbl=badgeLbl}

        row.MouseButton1Click:Connect(function()
            SIEGE.excludeMaps[mn_l] = not SIEGE.excludeMaps[mn_l]
            local excl = SIEGE.excludeMaps[mn_l]
            -- Update visual
            chkMark.Text = excl and "x" or ""
            chk.BackgroundColor3 = excl and Color3.fromRGB(180,50,50) or C.BG3
            badge.BackgroundColor3 = excl and Color3.fromRGB(60,20,20) or Color3.fromRGB(20,60,30)
            badgeLbl.Text = excl and "SKIP" or "ENTER"
            badgeLbl.TextColor3 = excl and Color3.fromRGB(255,120,60) or C.GRN
            rowLbl.TextColor3 = excl and C.DIM or C.TXT
            TweenService:Create(row, TweenInfo.new(0.12), {
                BackgroundColor3 = excl and Color3.fromRGB(50,20,20) or C.SURFACE
            }):Play()
            updateDdLabel()
        end)
    end
    updateDdLabel()

    -- Toggle dropdown open/close
    local ddOpen = false
    ddBtn.MouseButton1Click:Connect(function()
        ddOpen = not ddOpen
        ddList.Visible = ddOpen
        ddArrow.Text = ddOpen and "^" or "v"
        task.defer(ResizeSiegeBody)
    end)

    task.defer(ResizeSiegeBody)


end


-- ============================================================
-- AUTO DUNGEON - Tower Defense (Map 5 -> MapId 50303)
-- Source: TowerManager client script (decompiled)
-- Event server: ChangeTowerState {towerState, endTimestamp}
-- towerState: 1=WaitPhase(tutup), 2=PreparatoryPhase(OPEN 30dtk), 3=BattlePhase(sedang battle)
-- Masuk : StartLocalPlayerTeleport {mapId=50303} + LocalPlayerTeleportSuccess
-- Keluar : StartLocalPlayerTeleport {mapId=50005}
-- Prioritas tertinggi di Automation (di atas MA, Raid, Siege)
-- ============================================================

--  PANEL : CLAIM REWARD
-- ============================================================
do
 local p = NewPanel("claim")
 SectionHeader(p,"AUTO CLAIM REWARD",0)

 -- Status label
 local statusCard = Frame(p, C.BG3, UDim2.new(1,0,0,32))
 statusCard.LayoutOrder = 1; Corner(statusCard, 10); Stroke(statusCard,C.ACC, 1.5,0.3)
 local statusLbl = Label(statusCard,"Idle - PRESS CLAIM ALL",10,C.TXT2,Enum.Font.GothamBold)
 statusLbl.Size = UDim2.new(1,-16,1,0); statusLbl.Position = UDim2.new(0,8,0,0)

 -- Log panel (snipping output)
 local logCard = Frame(p, C.BG3, UDim2.new(1,0,0,120))
 logCard.LayoutOrder = 2; Corner(logCard, 10); Stroke(logCard,C.BORD, 1.5,0.88)
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
 local lbl = Label(logScroll, msg, 10, col or C.TXT2, Enum.Font.RobotoMono)
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
 row.LayoutOrder = order; Corner(row,9); Stroke(row,C.BORD, 1.5,0.88)
 Padding(row,6,6,10,8)

 local ico = Label(row, icon, 18, C.TXT, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
 ico.Size = UDim2.new(0,24,0,24); ico.Position = UDim2.new(0,0,0.5,-12)

 local ttl = Label(row, title, 13, C.TXT, Enum.Font.GothamBold)
 ttl.Size = UDim2.new(1,-90,0,16); ttl.Position = UDim2.new(0,28,0,4)

 local sub = Label(row, desc, 11, C.TXT, Enum.Font.GothamBold)
 sub.Size = UDim2.new(1,-90,0,13); sub.Position = UDim2.new(0,28,0,22)

 local btn = Btn(row, C.ACC, UDim2.new(0,52,0,26))
 btn.AnchorPoint = Vector2.new(1,0.5); btn.Position = UDim2.new(1,-6,0.5,0)
 Corner(btn, 10)
 local btnLbl = Label(btn,"CLAIM",9,C.BLACK,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 btnLbl.Size = UDim2.new(1,0,1,0)

 btn.MouseButton1Click:Connect(function()
 btn.BackgroundColor3 = C.DIM
 btnLbl.Text = "..."
 task.spawn(function()
 fn(sub, SetStatus)
 btn.BackgroundColor3 = C.GRN
 btnLbl.Text = "v"
 task.wait(2)
 btn.BackgroundColor3 = C.ACC
 btnLbl.Text = "CLAIM"
 end)
 end)

 return row, sub
 end

 --  Online Reward 
 ClaimRow(2, "", "Online Reward", "Auto scan & Claim ALL online reward", function(sub, status)
 local RE = Remotes:FindFirstChild("ClaimOnlineReward")
 if not RE then status("[X] NOT FOUND", C.RED); return end
 local claimed = 0
 local tried = 0
 local consecutive_fail = 0

 -- Strategy: scan id 1-500
 -- consecutive_fail hanya mulai dihitung SETELAH claim pertama berhasil
 -- Sebelum claim pertama: tetap scan terus tanpa stop
 -- Setelah claim pertama: stop kalau 15 id berturut-turut gagal (reward habis)
 local ever_claimed = false
 status("[] SCAN...", C.YEL)

 for id = 1, 500 do
 local ok, res = pcall(function()
 return RE:InvokeServer({id = tostring(id)})
 end)
 tried = tried + 1

 if ok and res == true then
 claimed = claimed + 1
 consecutive_fail = 0
 ever_claimed = true
 Log("[OK] id="..id.." CLAIMED!", C.GRN)
 status("[G] Claimed "..claimed.." reward (id "..id..")", C.GRN)
 else
 if ever_claimed then
 -- Sudah pernah claim -> mulai hitung fail
 consecutive_fail = consecutive_fail + 1
 if consecutive_fail >= 15 then
 Log("[S] Stop - 15 fail Before claim Latest (id "..id..")", C.DIM)
 break
 end
 end
 -- Sebelum claim pertama: scan terus tanpa stop
 end

 task.wait(0.05)
 end

 if claimed > 0 then
 status("[OK] Online Reward DONE - "..claimed.." CLAIM from "..tried.." scan", C.GRN)
 sub.Text = "LAST: "..claimed.." reward CLAIM"
 sub.TextColor3 = C.GRN
 else
 status("[i] There are no online rewards that can be claimed", C.YEL)
 sub.Text = "All have been claimed / not yet available"
 end
 end)

 --  Season Task Reward 
 ClaimRow(3, "", "Season Task Reward", "CLAIM ALL season task reward", function(sub, status)
 local RE = Remotes:FindFirstChild("ClaimSeasonTaskReward")
 if not RE then status("[X] NOT FOUND", C.RED); return end
 status("[..] Claiming season task reward...", C.YEL)
 local ok, res = pcall(function() return RE:FireServer() end)
 Log("[C] SeasonTask -> ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.RED)
 task.wait(0.5)
 status("[OK] Season Task Reward diklaim", C.GRN)
 sub.Text = "Last: CLAIM SUCCES"
 sub.TextColor3 = C.GRN
 end)

 --  Season Pass Reward 
 ClaimRow(4, "", "Season Pass Reward", "CLAIM ALL season pass reward", function(sub, status)
 local RE = Remotes:FindFirstChild("ClaimSeasonPassReward")
 if not RE then status("[X] NOT FOUND", C.RED); return end
 status("[..] Claiming season pass reward...", C.YEL)
 local ok, res = pcall(function() return RE:FireServer() end)
 Log("[T] SeasonPass -> ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.RED)
 task.wait(0.5)
 status("[OK] Season Pass Reward DONE", C.GRN)
 sub.Text = "LAST: DONE"
 sub.TextColor3 = C.GRN
 end)

 --  Season Reward [v117] 
 ClaimRow(5, "", "Season Reward", "Claim completed season rewards", function(sub, status)
 local RE = Remotes:FindFirstChild("ClaimSeasonReward")
 if not RE then
 RE = Remotes:FindFirstChild("ClaimSeason") or Remotes:FindFirstChild("SeasonReward")
 end
 if not RE then status("[X] NOT FOUND", C.RED); return end
 status("[..] Claiming season reward...", C.YEL)
 local ok, res = pcall(function() return RE:FireServer() end)
 Log("[W] SeasonReward -> ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.RED)
 task.wait(0.5)
 status("[OK] Season Reward DONE", C.GRN)
 sub.Text = "LAST: DONE"
 sub.TextColor3 = C.GRN
 end)

 --  7 Day Login Reward 
 ClaimRow(6, "", "7 Day Login Reward", "CLAIM ALL DAY (1-7)", function(sub, status)
 local RE = Remotes:FindFirstChild("ClaimSevenLoginReward")
 if not RE then status("[X] NOT FOUND", C.RED); return end
 local claimed = 0
 status("[..] Claiming 7 day login reward...", C.YEL)
 for day = 1, 7 do
 local ok, res = pcall(function() return RE:FireServer(day) end)
 Log("[D] Day "..day.." -> ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.DIM)
 if ok then claimed = claimed + 1 end
 task.wait(0.3)
 end
 status("[OK] 7 Day Login DONE - "..claimed.."/7 CLAIM", C.GRN)
 sub.Text = "LAST: "..claimed.."/7 DAY CLAIM"
 sub.TextColor3 = C.GRN
 end)

 --  Raid Reward 
 ClaimRow(7, "", "Daily Task Reward", "Claim rewards for completed daily tasks", function(sub, status)
 local RE = Remotes:FindFirstChild("ClaimDailyTaskReward")
 if not RE then status("[X] NOT FOUND", C.RED); return end
 status("[..] Claiming daily task reward...", C.YEL)
 local ok, res = pcall(function() return RE:FireServer() end)
 Log("[D] DailyTask -> ok="..tostring(ok).." res="..tostring(res), ok and C.GRN or C.RED)
 task.wait(0.5)
 if ok then
 status("[OK] Daily Task Reward DONE", C.GRN)
 sub.Text = "LAST: DONE"
 sub.TextColor3 = C.GRN
 else
 status("[!] Daily Task FAILURE", C.YEL)
 end
 end)

 --  Claim ALL button 
 local allBtn = Btn(p, C.ACC, UDim2.new(1,0,0,38))
 allBtn.LayoutOrder = 8; Corner(allBtn,10); Stroke(allBtn,C.ACC2, 1.5,0.2)
 local allLbl = Label(allBtn,"CLAIM ALL",13,C.BLACK,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 allLbl.Size = UDim2.new(1,0,1,0)

 allBtn.MouseButton1Click:Connect(function()
 allBtn.BackgroundColor3 = C.DIM
 allLbl.Text = "... Claiming..."
 task.spawn(function()
 SetStatus("[..] START CLAIM ALL...", C.YEL)

 -- Online Reward (smart scan)
 local RE1 = Remotes:FindFirstChild("ClaimOnlineReward")
 if RE1 then
 SetStatus("[G] Online Reward SCAN...", C.YEL)
 local fail, ever = 0, false
 for id = 1, 500 do
 local ok, res = pcall(function() return RE1:InvokeServer({id = tostring(id)}) end)
 if ok and res == true then
 fail = 0; ever = true
 Log("[OK] OnlineReward id="..id.." CLAIM", C.GRN)
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
 SetStatus("[C] Season Task...", C.YEL)
 pcall(function() RE2:FireServer() end)
 task.wait(0.3)
 end

 -- Season Pass
 local RE3 = Remotes:FindFirstChild("ClaimSeasonPassReward")
 if RE3 then
 SetStatus("[T] Season Pass...", C.YEL)
 pcall(function() RE3:FireServer() end)
 task.wait(0.3)
 end

 -- 7 Day Login
 local RE4 = Remotes:FindFirstChild("ClaimSevenLoginReward")
 if RE4 then
 SetStatus("[D] 7 Day Login...", C.YEL)
 for day = 1, 7 do
 pcall(function() RE4:FireServer(day) end)
 task.wait(0.2)
 end
 end

 -- Daily Task Reward
 local RE6 = Remotes:FindFirstChild("ClaimDailyTaskReward")
 if RE6 then
 SetStatus("[D] Daily Task Reward...", C.YEL)
 pcall(function() RE6:FireServer() end)
 task.wait(0.3)
 end

 SetStatus("[OK] Claim All DONE!", C.GRN)
 allBtn.BackgroundColor3 = C.GRN
 allLbl.Text = "CLAIM ALL DONE"
 task.wait(3)
 allBtn.BackgroundColor3 = C.ACC
 allLbl.Text = "CLAIM ALL"
 end)
 end)
end

-- ============================================================
-- WEBHOOK SENDER
-- ============================================================
-- ============================================================
-- PANEL : SETTINGS
-- ============================================================
do
 local p = NewPanel("settings")
 SectionHeader(p,"UI & Performance",1)
 
 ToggleRow(p, "Potato Mode (Anti-Lag)", "Disable all VFX for performance", 2, function(v)
    _G.PotatoMode = v
    if v then 
        CleanupVFX()
        -- Extra destruction for Potato Mode
        pcall(function()
            for _, obj in ipairs(ScreenGui:GetDescendants()) do
                if obj:IsA("ParticleEmitter") or obj:IsA("UIGradient") or obj:IsA("UIStroke") then
                    obj:Destroy()
                end
            end
            Window.BackgroundTransparency = 0
        end)
        SystemNotify("[SYSTEM]: Potato Mode Activated! 🔥", 3)
    else
        Window.BackgroundTransparency = _G.ThemeTransparency
        ApplyTheme(_G.CurrentTheme)
    end
 end)

 SectionHeader(p,"Raid Notif/Webhook",10)

 -- Info card
 -- info card dihapus (V142)

 --  [v115] Mode Dropdown: Raid / Siege / Keduanya 
 local modeCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,0))
 modeCard.LayoutOrder=25; modeCard.AutomaticSize=Enum.AutomaticSize.Y
 Corner(modeCard,9); Stroke(modeCard,C.BORD, 1.5,0.88)
 Padding(modeCard,8,8,10,10)
 New("UIListLayout",{Parent=modeCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})

 local modeHdr = Label(modeCard," Mode Notifikasi Webhook",11,C.TXT,Enum.Font.GothamBold)
 modeHdr.Size=UDim2.new(1,0,0,16); modeHdr.LayoutOrder=0

 local modeSub = Label(modeCard,"Select the type of notification sent to Discord",9.5,C.TXT3,Enum.Font.GothamBold)
 modeSub.Size=UDim2.new(1,0,0,13); modeSub.LayoutOrder=1

 -- Dropdown button
 local MODE_OPTS = {
 {key="raid", label="Raid", desc="Notif saat Raid muncul/update", col=Color3.fromRGB(255,180,60)},
 {key="siege", label="Siege", desc="Notif saat Siege buka/tutup", col=Color3.fromRGB(100,180,255)},
 {key="both", label="Raid + Siege", desc="Notif Raid dan Siege", col=C.TXT},
 }
 local curModeIdx = 3 -- default: both

 local modeDDBtn = Btn(modeCard, C.DD_BG, UDim2.new(1,0,0,28))
 modeDDBtn.LayoutOrder=2; Corner(modeDDBtn,7); Stroke(modeDDBtn,C.BORD, 1.5,0.88)
 local modeDDLbl = Label(modeDDBtn," "..MODE_OPTS[curModeIdx].label,10.5,MODE_OPTS[curModeIdx].col,Enum.Font.GothamBold)
 modeDDLbl.Size=UDim2.new(1,-22,1,0); modeDDLbl.Position=UDim2.new(0,4,0,0)
 local modeArr = Label(modeDDBtn,"v",10,Color3.fromRGB(180,120,255),Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 modeArr.Size=UDim2.new(0,18,1,0); modeArr.Position=UDim2.new(1,-20,0,0)

 local modeDescLbl = Label(modeCard,MODE_OPTS[curModeIdx].desc,9,C.TXT3,Enum.Font.GothamBold)
 modeDescLbl.Size=UDim2.new(1,0,0,13); modeDescLbl.LayoutOrder=3

 modeDDBtn.MouseButton1Click:Connect(function()
 CloseActiveDD()
 local absPos = modeDDBtn.AbsolutePosition
 local absSize = modeDDBtn.AbsoluteSize
 local ITEM_H = 36

 local popup = Instance.new("Frame")
 popup.Parent=DDLayer; popup.BackgroundColor3=C.DD_BG; popup.BorderSizePixel=0
 popup.Size=UDim2.new(0,absSize.X+10,0,#MODE_OPTS*(ITEM_H+2)+12)
 popup.Position=UDim2.new(0,absPos.X,0,absPos.Y+absSize.Y+3)
 popup.ZIndex=9999
 Corner(popup, 10); Stroke(popup,C.BORD, 1.5,0.2)

 local ll=Instance.new("UIListLayout",popup)
 ll.Padding=UDim.new(0,2); ll.SortOrder=Enum.SortOrder.LayoutOrder
 Instance.new("UIPadding",popup).PaddingTop=UDim.new(0,5)

 for i, opt in ipairs(MODE_OPTS) do
 local item=Instance.new("TextButton",popup)
 item.Size=UDim2.new(1,-8,0,ITEM_H); item.LayoutOrder=i
 item.BackgroundColor3=i==curModeIdx and C.SURFACE or C.BG3
 item.BackgroundTransparency=i==curModeIdx and 0.18 or 0.42
 item.BorderSizePixel=0; item.Text=""; item.AutoButtonColor=false; item.ZIndex=9999
 Instance.new("UICorner",item).CornerRadius=UDim.new(0,6)

 local iL=Instance.new("TextLabel",item)
 iL.Size=UDim2.new(1,-8,0,16); iL.Position=UDim2.new(0,10,0,4)
 iL.BackgroundTransparency=1; iL.Text=opt.label; iL.TextSize=13
 iL.Font=Enum.Font.Gotham; iL.TextColor3=opt.col
 iL.TextXAlignment=Enum.TextXAlignment.Left; iL.ZIndex=9999

 local iD=Instance.new("TextLabel",item)
 iD.Size=UDim2.new(1,-8,0,13); iD.Position=UDim2.new(0,10,0,20)
 iD.BackgroundTransparency=1; iD.Text=opt.desc; iD.TextSize=11
 iD.Font=Enum.Font.GothamBold; iD.TextColor3=C.DIM
 iD.TextXAlignment=Enum.TextXAlignment.Left; iD.ZIndex=9999

 local ii=i
 item.MouseButton1Click:Connect(function()
 CloseActiveDD()
 curModeIdx = ii
 _webhookMode = opt.key
 modeDDLbl.Text = " "..opt.label
 modeDDLbl.TextColor3 = opt.col
 modeDescLbl.Text = opt.desc
 end)
 end
 DDLayer.Visible=true
 _activeDDClose=function() popup:Destroy(); DDLayer.Visible=false end
 end)

 -- URL input
 local urlCard = Frame(p, C.SURFACE, UDim2.new(1,0,0,58))
 urlCard.LayoutOrder=3; Corner(urlCard,9); Stroke(urlCard,C.BORD, 1.5,0.88); Padding(urlCard,8,8,10,10)
 New("UIListLayout",{Parent=urlCard,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,5)})
 local urlHdr=Label(urlCard,"URL Webhook",10.5,C.TXT2,Enum.Font.GothamBold)
 urlHdr.Size=UDim2.new(1,0,0,14); urlHdr.LayoutOrder=0
 local urlBox = Instance.new("TextBox")
 urlBox.Parent=urlCard; urlBox.LayoutOrder=1
 urlBox.Size=UDim2.new(1,0,0,24); urlBox.BackgroundColor3=C.BG3
 urlBox.BorderSizePixel=0; urlBox.TextSize=11; urlBox.Font=Enum.Font.GothamBold
 urlBox.TextColor3=C.TXT2; urlBox.PlaceholderColor3=C.DIM
 urlBox.PlaceholderText="PASTE YOUR LINK DISCORD HERE..."
 urlBox.Text=_webhookUrl; urlBox.TextXAlignment=Enum.TextXAlignment.Left
 urlBox.ClearTextOnFocus=false
 Corner(urlBox,5); Stroke(urlBox,C.BORD, 1.5,0.88)
 local urlPad=Instance.new("UIPadding",urlBox)
 urlPad.PaddingLeft=UDim.new(0,6); urlPad.PaddingRight=UDim.new(0,6)
 urlBox.FocusLost:Connect(function()
 _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
 end)

 -- Platform detect label
 local platformLbl = Label(p,"",9.5,C.DIM,Enum.Font.GothamBold)
 platformLbl.LayoutOrder=4; platformLbl.Size=UDim2.new(1,0,0,13)
 function UpdatePlatformLbl()
 local url = _webhookUrl
 if url:find("discord%.com/api/webhooks") then
 platformLbl.Text="[OK] Discord webhook DETECTED"; platformLbl.TextColor3=Color3.fromRGB(100,220,100)
 elseif url:find("api%.telegram%.org") then
 platformLbl.Text="[OK] Telegram bot API DETECTED"; platformLbl.TextColor3=Color3.fromRGB(100,180,255)
 elseif url=="" then
 platformLbl.Text="Content URL"; platformLbl.TextColor3=C.DIM
 else
 platformLbl.Text="URL not recognized (Discord/Telegram)"; platformLbl.TextColor3=Color3.fromRGB(255,180,60)
 end
 end
 urlBox.FocusLost:Connect(function() UpdatePlatformLbl() end)
 UpdatePlatformLbl()

 -- Toggle aktifkan webhook
 local wRow = Frame(p,C.BG3,UDim2.new(1,0,0,50))
 wRow.LayoutOrder=5; Corner(wRow,9); Stroke(wRow,C.BORD, 1.5,0.88)
 local wL=Label(wRow," ACTIVE Webhook",13,C.TXT,Enum.Font.GothamBold)
 wL.Size=UDim2.new(0.65,0,0,20); wL.Position=UDim2.new(0,10,0,6)
 local wS=Label(wRow,"Send notifications for every update",9.5,C.TXT3,Enum.Font.GothamBold)
 wS.Size=UDim2.new(0.65,0,0,14); wS.Position=UDim2.new(0,10,0,26)
 local wPill=Btn(wRow,C.TBAR,UDim2.new(0,50,0,26))
 wPill.AnchorPoint=Vector2.new(1,0.5); wPill.Position=UDim2.new(1,-10,0.5,0); Corner(wPill,13)
 local wKnob=Frame(wPill,Color3.fromRGB(120,50,8),UDim2.new(0,20,0,20))
 wKnob.AnchorPoint=Vector2.new(0,0.5); wKnob.Position=UDim2.new(0,3,0.5,0); Corner(wKnob,10)
 wPill.MouseButton1Click:Connect(function()
 _webhookEnabled=not _webhookEnabled; local on=_webhookEnabled
 _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
 TweenService:Create(wPill,TweenInfo.new(0.16),{BackgroundColor3=on and Color3.fromRGB(200,80,10) or C.TBAR}):Play()
 TweenService:Create(wKnob,TweenInfo.new(0.16),{
 Position=on and UDim2.new(1,-23,0.5,0) or UDim2.new(0,3,0.5,0),
 BackgroundColor3=on and Color3.fromRGB(255,255,255) or Color3.fromRGB(120,50,8),
 }):Play()
 wRow.BackgroundColor3=on and C.BG2 or C.BG3
 UpdatePlatformLbl()
 if on then
 -- [v129] Flush pending: reset cooldown + kirim semua data cache yang ada
 if FlushWebhookPending then task.spawn(FlushWebhookPending) end
 end
 end)

 --  Row: Test Webhook + Verify Link 
 local btnRow = Frame(p, C.BLACK, UDim2.new(1,0,0,36))
 btnRow.LayoutOrder=6; btnRow.BackgroundTransparency=1
 New("UIListLayout",{Parent=btnRow,FillDirection=Enum.FillDirection.Horizontal,
 SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0, 10)})

 -- Test Webhook
 local testRow=Frame(btnRow,C.BG3,UDim2.new(0.5,-4,1,0))
 testRow.LayoutOrder=1; Corner(testRow,9); Stroke(testRow,C.BORD, 1.5,0.88)
 local testBtn=Btn(testRow,Color3.fromRGB(160,65,8),UDim2.new(1,-16,0,24))
 testBtn.AnchorPoint=Vector2.new(0.5,0.5); testBtn.Position=UDim2.new(0.5,0,0.5,0)
 Corner(testBtn,7); Stroke(testBtn,C.BORD, 1.5,0.88)
 local testLbl=Label(testBtn," Test Webhook",10,C.TXT,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 testLbl.Size=UDim2.new(1,0,1,0)
 testBtn.MouseButton1Click:Connect(function()
 _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
 UpdatePlatformLbl()
 local msg = "[FLa Webhook] Webhook Active! Mode: "..(_webhookMode or "both"):upper()
 testLbl.Text="[..] Sending..."; testLbl.TextColor3=Color3.fromRGB(255,220,60)
 -- [FIX] Timeout UI 12s: kalau tidak ada callback dalam 12s, reset label
 local _done = false
 task.delay(12, function()
 if not _done then
 _done = true
 testLbl.Text="[!] Timeout"; testLbl.TextColor3=Color3.fromRGB(255,80,60)
 task.delay(2.5, function() testLbl.Text=" Test Webhook"; testLbl.TextColor3=C.TXT end)
 end
 end)
 _WH.SendCustomMessage(_webhookUrl, msg,
 function()
 if _done then return end; _done = true
 task.spawn(function()
 testLbl.Text="[OK] Sent!"; testLbl.TextColor3=Color3.fromRGB(100,255,100)
 task.wait(2.5)
 testLbl.Text=" Test Webhook"; testLbl.TextColor3=C.TXT
 end)
 end,
 function(err)
 if _done then return end; _done = true
 task.spawn(function()
 testLbl.Text=""..err; testLbl.TextColor3=Color3.fromRGB(255,80,60)
 task.wait(2.5)
 testLbl.Text=" Test Webhook"; testLbl.TextColor3=C.TXT
 end)
 end
 )
 end)

 -- Verify Link
 local verRow=Frame(btnRow,C.BG3,UDim2.new(0.5,-4,1,0))
 verRow.LayoutOrder=2; Corner(verRow,9); Stroke(verRow,C.BORD, 1.5,0.88)
 local verBtn=Btn(verRow,C.BG2,UDim2.new(1,-16,0,24))
 verBtn.AnchorPoint=Vector2.new(0.5,0.5); verBtn.Position=UDim2.new(0.5,0,0.5,0)
 Corner(verBtn,7); Stroke(verBtn,C.BORD, 1.5,0.88)
 local verLbl=Label(verBtn,"[] Verify Link",10,C.TXT,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 verLbl.Size=UDim2.new(1,0,1,0)
 verBtn.MouseButton1Click:Connect(function()
 _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
 UpdatePlatformLbl()
 verLbl.Text="[..] Cek..."; verLbl.TextColor3=Color3.fromRGB(255,220,60)
 _WH.VerifyWebhookUrl(_webhookUrl,
 function()
 task.spawn(function()
 verLbl.Text="[OK] Link Valid!"; verLbl.TextColor3=Color3.fromRGB(100,255,100)
 task.wait(2.5)
 verLbl.Text="[] Verify Link"; verLbl.TextColor3=C.TXT
 end)
 end,
 function(err)
 task.spawn(function()
 verLbl.Text=""..err; verLbl.TextColor3=Color3.fromRGB(255,80,60)
 task.wait(2.5)
 verLbl.Text="[] Verify Link"; verLbl.TextColor3=C.TXT
 end)
 end
 )
 end)

 --  Kirim Sekarang (manual trigger sesuai mode) 
 local sendNowCard = Frame(p, C.BG3, UDim2.new(1,0,0,38))
 sendNowCard.LayoutOrder=7; Corner(sendNowCard,9); Stroke(sendNowCard,C.BORD, 1.5,0.88)
 local sendNowBtn = Btn(sendNowCard,C.BG2,UDim2.new(0.7,0,0,26))
 sendNowBtn.AnchorPoint=Vector2.new(0.5,0.5); sendNowBtn.Position=UDim2.new(0.5,0,0.5,0)
 Corner(sendNowBtn, 10); Stroke(sendNowBtn,C.BORD, 1.5,0.88)
 local sendNowLbl=Label(sendNowBtn," Send Notify Now",10.5,C.TXT,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
 sendNowLbl.Size=UDim2.new(1,0,1,0)
 sendNowBtn.MouseButton1Click:Connect(function()
 _webhookUrl = urlBox.Text:match("^%s*(.-)%s*$") or ""
 if _webhookUrl == "" then
 sendNowLbl.Text="URL kosong!"; sendNowLbl.TextColor3=Color3.fromRGB(255,180,60)
 task.delay(2, function() sendNowLbl.Text=" Send Notify Now"; sendNowLbl.TextColor3=C.TXT end)
 return
 end
 sendNowLbl.Text="[..] Mengirim..."; sendNowLbl.TextColor3=Color3.fromRGB(255,220,60)
 -- [FIX] Timeout UI 12s: reset label kalau pengiriman hang
 local _snDone = false
 task.delay(12, function()
 if not _snDone then
 _snDone = true
 sendNowLbl.Text="[!] Timeout"; sendNowLbl.TextColor3=Color3.fromRGB(255,80,60)
 task.delay(2.5, function() sendNowLbl.Text=" Send Notify Now"; sendNowLbl.TextColor3=C.TXT end)
 end
 end)
 task.spawn(function()
 local mode = _webhookMode or "both"
 local url = _webhookUrl
 local sent = false
 local hasRaid = next(RAID_LIVE or {}) ~= nil
 local hasSiege = SIEGE and SIEGE.live and next(SIEGE.live) ~= nil
 if (mode == "raid" or mode == "both") and hasRaid then
 if _WH.SendRaid then _WH.SendRaid(url) end; sent = true
 end
 if (mode == "siege" or mode == "both") and hasSiege then
 task.wait(0.3)
 if _WH.SendSiege then _WH.SendSiege(url) end; sent = true
 end
 if not sent then
 -- Tidak ada data raid/siege - kirim pesan info
 if _WH.SendCustomMessage then
 _WH.SendCustomMessage(url, "[ASH] There are currently no active raids or sieges",
 nil, nil)
 end
 end
 _whLastSent = tick()
 if _snDone then return end; _snDone = true
 task.wait(0.5)
 sendNowLbl.Text="[OK] Sent!"; sendNowLbl.TextColor3=Color3.fromRGB(100,255,100)
 task.wait(2.5)
 sendNowLbl.Text=" Send Notify Now"; sendNowLbl.TextColor3=C.TXT
 end)
 end)
end


-- ============================================================
-- INIT
-- ============================================================
-- Pre-populate semua Ornament Quirk dengan nama lengkap
-- Urutan: common (atas) -> rare (bawah)
-- Format: {machineIdx, quirkId, "nama"}
do
 local ORN_KNOWN = {
 -- 
 -- [1] HEADDRESS - machineId=400001
 -- 
 {1, 410001, "Glowing Blue Eyes"},
 {1, 410002, "Fox Ears"},
 {1, 410003, "Blossom Crown of the Abyss"},
 {1, 410004, "Demon Horns"},
 {1, 410005, "Wizard Hat"},
 {1, 410006, "Sharktooth Hood"},
 {1, 410007, "Bunny Boom Helmet"},
 {1, 410008, "Cursed Harvest Helmet"},
 {1, 410009, "Bloodforged Casque"},
 {1, 410010, "Jester's Madness Cap"}, -- [*] RAREST

 -- 
 -- [2] ORNAMENT MACHINE - machineId=400002
 -- 
 {2, 410011, "Fox Brush"},
 {2, 410012, "Whale's Tail"},
 {2, 410013, "Dragon's Tail"},
 {2, 410014, "Dinosaur Swimming Circle"},
 {2, 410015, "Ghastroot Parasite"},
 {2, 410016, "Wishy Star Bunny"},
 {2, 410017, "Mechanical Wing"},
 {2, 410018, "Demon Wing"},
 {2, 410019, "Prism Wings"},
 {2, 410020, "Omenwing of the Void"}, -- [*] RAREST

 -- 
 -- [3] WEALTH BLESSING - machineId=400003
 -- 
 {3, 410021, "Single Glow Bless"},
 {3, 410022, "Double Stack Bless"},
 {3, 410023, "Slant Bless"},
 {3, 410024, "Misstack Bless"},
 {3, 410025, "High Stack Bless"},
 {3, 410026, "Initial Bag Bless"},
 {3, 410027, "Full Bag Bless"},
 {3, 410028, "Bag Scatter Bless"},
 {3, 410029, "Supreme Crown Gold"},
 {3, 410030, "Imperial Crown Full Bag"}, -- [*] RAREST

 -- 
 -- [4] SHADOWHUNTER BLESSING - machineId=400004
 -- 
 {4, 410031, "Shadowfelin Gaze"},
 {4, 410032, "Techowl Capture"},
 {4, 410033, "Beastglow Frame"},
 {4, 410034, "Croucharmor Beam"},
 {4, 410035, "Silveraura Agile"},
 {4, 410036, "Demonwing Aura"},
 {4, 410037, "Spikedial Gothic"},
 {4, 410038, "Galaxyvortex Lightning"},
 {4, 410039, "Demonhand Lightning"}, -- [*] RAREST

 -- 
 -- [5] PRIMORDIAL BLESSING - machineId=400005
 -- 
 {5, 410040, "Dawn's Spark"},
 {5, 410041, "Blade's Guide"},
 {5, 410042, "Edge's Glow"},
 {5, 410043, "Power's Nudge"},
 {5, 410044, "Resurgent Edge"},
 {5, 410045, "Sixth Dawn's Gift"},
 {5, 410046, "Flame's Fuel"},
 {5, 410047, "Gold Star's Whisper"},
 {5, 410048, "Stardust's Fury"}, -- [*] RAREST

 -- 
 -- [6] MONARCH POWER - machineId=400006
 -- 
 {6, 410049, "Flames Power"},
 {6, 410050, "Giant Power"},
 {6, 410051, "Beast Power"},
 {6, 410052, "Plague Power"},
 {6, 410053, "Frosh Power"},
 {6, 410054, "Unbreakable Power"},
 {6, 410057, "Transfiguration Power"},
 {6, 410056, "Destruction Power"},
 {6, 410055, "Shadow Power"}, -- [*] RAREST
 }
 for _, e in ipairs(ORN_KNOWN) do
 _ASH_ORN.AddQuirk(e[1], e[2], e[3])
 end
end

-- ============================================================
-- AUTO ROLL LOGIC - HERO
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
 local list = QUIRK_LIST_PER_SLOT[si]
 local targets = _HR_RPT and _HR_RPT.slotTarget and _HR_RPT.slotTarget[si] or {}
 local drawId = {920001, 920002, 920003}

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
 setSlot("[..] Klik 1x di Mesin Reroll dulu", Color3.fromRGB(255,150,50))
 task.wait(1); continue
 end
 -- Cek target dipilih - wajib ada sebelum roll
 local hasTarget = false
 for _ in pairs(targets) do hasTarget = true; break end
 if not hasTarget then
 setSlot("[!] SELECT TARGET PLEASE!", Color3.fromRGB(255,100,60))
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

 -- [v231] FIX: guard heroGuid & drawId sebelum InvokeServer
 -- mencegah server crash "attempt to index nil with drawHeroid"
 if not _HR_RPT or not _HR_RPT.guid or _HR_RPT.guid == "" then
 setSlot("[!] HERO NOT FOUND - WAITING", Color3.fromRGB(255,150,50))
 task.wait(1); continue
 end
 if not drawId[si] or type(drawId[si]) ~= "number" then
 setSlot("[!] invalid"..si, Color3.fromRGB(255,100,60))
 task.wait(1); continue
 end
 if not RE.RandomHeroQuirk then
 setSlot("[!] Remote RandomHeroQuirk nil", Color3.fromRGB(255,80,80))
 task.wait(2); continue
 end
 local ok, res = pcall(function()
 _ourCall = true
 local r = RE.RandomHeroQuirk:InvokeServer({
 heroGuid = _HR_RPT.guid,
 drawId = drawId[si],
 })
 _ourCall = false
 return r
 end)
 if not ok then
 task.wait(1); continue
 end

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

 local gotName = QUIRK_MAP[gotId] or (gotId and "ID:"..gotId or "")
 -- [v103] Hanya stop kalau target dipilih DAN hasil cocok
 local hit = gotId and hasTarget and targets[gotId] == true

 if hit then
 setSlot("DONE: "..gotName.." (#"..attempt..")", Color3.fromRGB(80,220,80))
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
 -- GUID belum ada -> tampil pesan, tunggu GUID, lalu auto-start
 if not (_HR_RPT and _HR_RPT.guid and _HR_RPT.guid ~= "") then
 for i = 1, 3 do
 if _HR_RPT then _HR_RPT.SetSlot(i, "WAITING - Click 1x on Reroll Machine", Color3.fromRGB(180,220,255)) end
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
-- CAPTURE SYSTEM - __namecall hook + flag _ourCall
-- IDENTIK dengan v129 yang terbukti tidak crash UI game
-- ============================================================
do
 local function SetupUniversalSpy()
 if _layer0Active then return end
 _layer0Active = true

 local _rHero = RE.RandomHeroQuirk
 local _rAuto = RE.AutoHeroQuirk
 local _rHeroSkill = RE.HeroUseSkill

 -- Helper capture GUID dari arg
 local function _captureHeroGuid(arg1)
 if type(arg1) ~= "table" then return end
 local g = arg1.heroGuid or arg1.HeroGuid or arg1.guid
 if type(g) ~= "string" or not IsValidUUID(g) then return end
 -- Simpan ke HERO_GUIDS global (untuk MA/Siege/Raid)
 local already = false
 for _, ex in ipairs(HERO_GUIDS) do if ex == g then already = true; break end end
 if not already then
 table.insert(HERO_GUIDS, g)
 end
 -- Simpan ke _HR_RPT (untuk reroll)
 if _HR_RPT then _HR_RPT.guid = g; _HR_RPT.Refresh() end
 end

 -- Coba hook via __namecall (Xeno/Delta support)
 local hookOk = false
 pcall(function()
 if type(getrawmetatable) ~= "function" then return end
 if type(setreadonly) ~= "function" then return end
 if type(newcclosure) ~= "function" then return end

 local mt = getrawmetatable(game)
 if not mt then return end
 local _old = mt.__namecall
 if not _old then return end

 setreadonly(mt, false)
 mt.__namecall = newcclosure(function(self, ...)
 -- [v254 FIX] Bypass SEMUA method selain yang kita butuhkan
 -- "require" dan method system lain harus langsung pass-through
 -- tanpa disentuh, agar tidak trigger "Cannot require non-RobloxScript"
 -- error pada UIManager/TipsManager/RaidsManager game
 local _m = ""
 pcall(function() _m = getnamecallmethod() end)
 if _m ~= "FireServer" and _m ~= "InvokeServer" then
 return _old(self, ...)
 end

 local arg1 = select(1, ...)

 -- Capture HeroUseSkill -> HERO_GUIDS (untuk MA/Raid/Siege)
 if self == _rHeroSkill and not _ourCall then
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

 -- Bukan remote reroll target -> pass through
 if self ~= _rHero and self ~= _rAuto then
 return _old(self, ...)
 end

 -- Jalankan remote asli dulu
 local r1, r2, r3, r4, r5 = _old(self, ...)

 -- Capture GUID dari arg setelah remote berhasil
 -- (_m sudah berisi "FireServer" atau "InvokeServer" dari cek atas)
 if self == _rHero or self == _rAuto then
 _captureHeroGuid(arg1)
 end

 return r1, r2, r3, r4, r5
 end)
 setreadonly(mt, true)
 hookOk = true
 end)

 if hookOk then
 -- __namecall hook berhasil dipasang
 else
 -- Fallback: polling OnClientEvent setelah setiap remote fire
 -- Cara ini tidak 100% akurat tapi lebih reliable di executor terbatas
 task.spawn(function()
 -- Poll: cek RS HeroData/Heroes/Weapons untuk ambil GUID
 while ScreenGui and ScreenGui.Parent do
 task.wait(2)
 pcall(function()
 -- Hero GUID
 local hf = RS:FindFirstChild("HeroData") or RS:FindFirstChild("Heroes")
 if hf then
 for _, h in ipairs(hf:GetChildren()) do
 local g = h:GetAttribute("heroGuid") or h:GetAttribute("guid")
 if type(g) == "string" and IsValidUUID(g) then
 local dup = false
 for _, ex in ipairs(HERO_GUIDS) do if ex == g then dup = true; break end end
 if not dup then
 table.insert(HERO_GUIDS, g)
 end
 -- Simpan ke _HR_RPT kalau belum ada
 if _HR_RPT and (_HR_RPT.guid == nil or _HR_RPT.guid == "") then
 _HR_RPT.guid = g
 if _HR_RPT.Refresh then pcall(_HR_RPT.Refresh) end
 end
 end
 end
 end
 end)
 end
 end)
 end
 end

 InitAllCaptureLayers = function()
 SetupUniversalSpy()
 end
end

 -- ============================================================
-- PANEL : THEME
-- ============================================================
do
    local p = NewPanel("theme")
    SectionHeader(p, "Theme Selection", 1)
    
    SliderRow(p, "UI Transparency", 1, 100, 42, function(v)
        _G.ThemeTransparency = (v - 1) / 99
        if not _G.PotatoMode then
            TweenService:Create(Window, TweenInfo.new(0.3), {BackgroundTransparency = _G.ThemeTransparency}):Play()
        end
    end)
    
    SectionHeader(p, "Color Palettes (30 Themes)", 10)
    
    local themeGrid = Frame(p, C.BLACK, UDim2.new(1,0,0,0))
    themeGrid.BackgroundTransparency = 1; themeGrid.AutomaticSize = Enum.AutomaticSize.Y
    themeGrid.LayoutOrder = 11
    local gl = New("UIGridLayout", {
        Parent = themeGrid, CellPadding = UDim2.new(0,5,0,5),
        CellSize = UDim2.new(0, math.floor(WIN_W/3)-12, 0, 34),
        SortOrder = Enum.SortOrder.Name
    })
    
    for name, colors in pairs(ThemePalettes) do
        local b = Btn(themeGrid, C.SURFACE, UDim2.new(1,0,1,0))
        b.Name = name; Corner(b, 6); Stroke(b, C.BORD, 1, 0.8)
        local l = Label(b, name, 8, C.TXT, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        l.Size = UDim2.new(1,0,1,0); l.TextWrapped = true
        
        b.MouseButton1Click:Connect(function()
            ApplyTheme(name)
        end)
    end
end
 
 ApplyTheme("Solo Leveling")
 SwitchTab("main")
 RefreshStatus()

-- ============================================================
-- ============================================================
-- SIEGE SCANNER - Akurat seperti Auto Raid
-- Sumber 1: UpdateCityRaidInfo listener (push dari server, permanent)
-- Sumber 2: GetCityRaidInfos poll (snapshot - untuk relog/missed event)
-- Sumber 3: Periodic re-poll setiap 30 detik (keepalive)
-- Sumber 4: Chat parser -> langsung isi SIEGE.live
-- ============================================================
local CITY_TO_MAP_CONN = {[1000001]=3,[1000002]=7,[1000003]=10,[1000004]=13}

-- Helper: parse satu entry GetCityRaidInfos result -> isi SIEGE.live
local function _applySiegeEntry(entry)
    if type(entry) ~= "table" then return end
    local id = entry.id
    local action = entry.action
    if not id then return end
    local mn = CITY_TO_MAP_CONN[id]
    if not mn then return end
    if not SIEGE or not SIEGE.live then return end
    if action == "OpenCityRaid" then
        SIEGE.live[id] = mn
    elseif action == "CloseCityRaid" then
        SIEGE.live[id] = nil
    end
end

-- Helper: poll snapshot dari server -> refresh SIEGE.live penuh
local function _pollSiegeLive(label)
    pcall(function()
        local getCR = Remotes:FindFirstChild("GetCityRaidInfos")
        if not getCR then return end
        local result = getCR:InvokeServer()
        if type(result) ~= "table" then return end
        -- Bersihkan dulu semua entry lama sebelum isi ulang dari snapshot
        if SIEGE and SIEGE.live then
            for k in pairs(SIEGE.live) do SIEGE.live[k] = nil end
        end
        for _, entry in ipairs(result) do
            _applySiegeEntry(entry)
        end
        if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
    end)
end

task.spawn(function()
    task.wait(4) -- tunggu GUI + game modules ready

    -- SUMBER 1: Listener permanent UpdateCityRaidInfo
    -- Server push ini setiap siege buka/tutup
    -- Masalah: kalau relog saat siege sudah open, event ini sudah lewat
    local _reCity = Remotes:FindFirstChild("UpdateCityRaidInfo")
    if _reCity then
        _reCity.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local id = data.id
            local action = data.action
            if not id or not action then return end
            local mn = CITY_TO_MAP_CONN[id]
            if not mn then return end
            if not SIEGE or not SIEGE.live then return end
            if action == "OpenCityRaid" then
                SIEGE.live[id] = mn
            elseif action == "CloseCityRaid" then
                SIEGE.live[id] = nil
            end
            if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
            -- Trigger webhook kalau siege buka
            if action == "OpenCityRaid" and not _whSilent then
                TriggerWebhookDebounce()
            end
        end)
    end

    -- SUMBER 2: Poll snapshot saat startup
    -- Ini yang handle kasus relog / join saat siege sudah open
    -- Tunggu game modules ready dulu
    local _pg = LP.PlayerGui
    local _dl = tick() + 12
    repeat task.wait(0.5) until (_pg:FindFirstChildWhichIsA("ScreenGui") ~= nil) or tick() > _dl
    task.wait(1)
    _pollSiegeLive("startup")

    -- SUMBER 3: Periodic re-poll setiap 30 detik (keepalive)
    -- Sync ulang kalau ada event yang terlewat
    task.spawn(function()
        while true do
            task.wait(30)
            if SIEGE then
                _pollSiegeLive("periodic")
            end
        end
    end)

    -- SUMBER 5: Workspace watcher - deteksi CityRaidEnter di workspace.Maps.Map
    -- Sama persis dengan cara Auto Raid deteksi via workspace.Maps.Map.RaidEnter
    -- Ini yang handle kasus: siege open sebelum script load, relog, missed event
    -- workspace.Maps.Map.CityRaidEnter berisi folder CityRaidX saat siege open
    local CITY_RAID_FOLDER_MAP = {
        CityRaid1 = 1000001,  -- Map 3
        CityRaid2 = 1000002,  -- Map 7
        CityRaid3 = 1000003,  -- Map 10
        CityRaid4 = 1000004,  -- Map 13
        -- Nama alternatif yang mungkin dipakai game
        CityRaidEnter1 = 1000001,
        CityRaidEnter2 = 1000002,
        CityRaidEnter3 = 1000003,
        CityRaidEnter4 = 1000004,
    }
    task.spawn(function()
        local ok, mapsF = pcall(function() return workspace:WaitForChild("Maps", 20) end)
        if not ok or not mapsF then
            -- Fallback: scan langsung workspace top-level
            pcall(function()
                workspace.ChildAdded:Connect(function(child)
                    local cid = CITY_RAID_FOLDER_MAP[child.Name]
                    if cid and SIEGE and SIEGE.live then
                        local mn = CITY_TO_MAP_CONN[cid]
                        if mn then
                            SIEGE.live[cid] = mn
                            if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
                        end
                    end
                end)
                workspace.ChildRemoved:Connect(function(child)
                    local cid = CITY_RAID_FOLDER_MAP[child.Name]
                    if cid and SIEGE and SIEGE.live then
                        SIEGE.live[cid] = nil
                        if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
                    end
                end)
                -- Scan yang sudah ada
                for _, child in ipairs(workspace:GetChildren()) do
                    local cid = CITY_RAID_FOLDER_MAP[child.Name]
                    if cid and SIEGE and SIEGE.live then
                        SIEGE.live[cid] = CITY_TO_MAP_CONN[cid]
                        if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
                    end
                end
            end)
            return
        end
        local ok2, mapF = pcall(function() return mapsF:WaitForChild("Map", 10) end)
        if not ok2 or not mapF then return end

        -- Helper: cek child workspace.Maps.Map apakah folder siege
        local function _onMapChildAdded(child)
            -- Cek nama folder: CityRaid1-4 atau CityRaidEnter1-4
            local cid = CITY_RAID_FOLDER_MAP[child.Name]
            if cid then
                local mn = CITY_TO_MAP_CONN[cid]
                if mn and SIEGE and SIEGE.live then
                    SIEGE.live[cid] = mn
                    if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
                end
                return
            end
            -- Fallback: scan descendants untuk cari hint siege
            -- Beberapa game version mungkin pakai nama berbeda
            pcall(function()
                for _, desc in ipairs(child:GetChildren()) do
                    local cid2 = CITY_RAID_FOLDER_MAP[desc.Name]
                    if cid2 then
                        local mn2 = CITY_TO_MAP_CONN[cid2]
                        if mn2 and SIEGE and SIEGE.live then
                            SIEGE.live[cid2] = mn2
                            if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
                        end
                    end
                end
            end)
        end

        local function _onMapChildRemoved(child)
            local cid = CITY_RAID_FOLDER_MAP[child.Name]
            if cid and SIEGE and SIEGE.live then
                SIEGE.live[cid] = nil
                if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
            end
        end

        -- Scan yang sudah ada saat script load (kasus relog saat siege sudah open)
        for _, child in ipairs(mapF:GetChildren()) do
            _onMapChildAdded(child)
        end
        -- Watch perubahan real-time
        mapF.ChildAdded:Connect(_onMapChildAdded)
        mapF.ChildRemoved:Connect(_onMapChildRemoved)
    end)

end)

-- SUMBER 4: Chat parser -> langsung isi SIEGE.live
-- _siegeChatOpen diisi ParseChatLine; kita watch dan konversi ke SIEGE.live
local CHAT_CID = {[3]=1000001,[7]=1000002,[10]=1000003,[13]=1000004}
task.spawn(function()
    -- Watch _siegeChatOpen changes setiap 0.5s
    -- (chat parser sudah set _siegeChatOpen[mn]=true saat "has begun" terbaca)
    local _lastSeen = {}
    while true do
        task.wait(0.5)
        if _siegeChatOpen and SIEGE and SIEGE.live then
            for mn, open in pairs(_siegeChatOpen) do
                if open and not _lastSeen[mn] then
                    _lastSeen[mn] = true
                    local cid = CHAT_CID[mn]
                    if cid then
                        SIEGE.live[cid] = mn
                        if _siegeWakeup then pcall(function() _siegeWakeup:Fire() end) end
                    end
                elseif not open then
                    _lastSeen[mn] = nil
                end
            end
        end
    end
end)

-- Hook dipasang langsung saat GUI muncul (Remotes sudah ready karena task.wait(3) di atas)
-- Tidak perlu delay tambahan - makin cepat hook aktif makin baik
task.spawn(function()
 task.wait(0.5)
 InitAllCaptureLayers()
end)

--  AUTO HIDE REWARD / RESULT PANELS [v273 FIX: AGGRESSIVE]
-- Berlaku untuk Raid, Garrison Boss, dan Siege
task.spawn(function()
    local HIDE_PANELS = {
        "RewardsFrame", "RaidsFightPanel", "CityFightPanel", 
        "RaidsPanel", "ResultFrame", "RewardPanel", "ChallengeGarrisonBossSuccess"
    }

    local function forceHide(obj)
        if not obj or not obj.Parent then return end
        pcall(function()
            -- [v273] Cek tipe objek untuk menghindari error "Visible is not a valid property"
            if obj:IsA("GuiObject") then
                obj.Visible = false
                if obj:IsA("CanvasGroup") then obj.Alpha = 0 end
                -- Pindahkan jauh dari layar agar benar-benar tidak terlihat
                obj.Position = UDim2.new(2, 0, 2, 0)
            elseif obj:IsA("ScreenGui") then
                obj.Enabled = false
            end
        end)
    end

    local function checkAndHide(obj)
        -- Hanya proses objek yang memiliki properti tampilan (GuiObject atau ScreenGui)
        if not (obj:IsA("GuiObject") or obj:IsA("ScreenGui")) then return end
        
        for _, name in ipairs(HIDE_PANELS) do
            if obj.Name == name or obj.Name:find("GarrisonBoss") then
                task.wait(0.2)
                forceHide(obj)
                
                -- Pasang listener berdasarkan tipe properti yang sesuai
                pcall(function()
                    if obj:IsA("GuiObject") then
                        obj:GetPropertyChangedSignal("Visible"):Connect(function()
                            if obj.Visible then forceHide(obj) end
                        end)
                    elseif obj:IsA("ScreenGui") then
                        obj:GetPropertyChangedSignal("Enabled"):Connect(function()
                            if obj.Enabled then forceHide(obj) end
                        end)
                    end
                end)
                break
            end
        end
    end

    -- 1. Scan existing
    for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
        checkAndHide(obj)
    end

    -- 2. Watch new ones
    LP.PlayerGui.DescendantAdded:Connect(function(obj)
        task.spawn(checkAndHide, obj)
    end)

    -- 3. Event Listeners (Back-end triggers)
    local _evts = {
        "ShowReward", "ChallengeGarrisonBossSuccess", 
        "ChallengeRaidsSuccess", "ChallengeRaidsFail"
    }
    for _, ename in ipairs(_evts) do
        local re = Remotes:WaitForChild(ename, 10)
        if re then
            re.OnClientEvent:Connect(function()
                task.wait(0.3)
                for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
                    checkAndHide(obj)
                end
            end)
        end
    end
end)

