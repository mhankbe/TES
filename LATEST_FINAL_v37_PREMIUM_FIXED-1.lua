--[[
    KERANGKA MENU TAB -> WindUI (VERSI FINAL)
    Urutan sesuai permintaan terbaru - 11 tab, TIDAK di-flatten lagi.
    Automation & Reroll masing-masing CUMA 1 tab (sub-fitur di dalamnya diatur
    pakai Section/Group nanti waktu pengisian fungsi, bukan dipecah jadi tab sidebar).

    Tambahan: profil user (avatar + username Roblox asli) di pojok kiri-bawah sidebar,
    di bawah tab Theme - pakai config native `User` WindUI (pengganti CreateUserProfile()
    di baris 1132-1172 source asli).

    Pemetaan tab -> baris source asli (referensi buat pengisian fungsi nanti):
      1. Main        -> PANEL: MAIN (3812)
      2. Hide         -> PANEL: HIDE (5171)
      3. Farm         -> PANEL: FARM (5571)
      4. Mass Attack  -> PANEL: ATTACK (6785)
      5. Automation   -> Auto Raid (13577), Auto Ascension (14700), Auto Siege (16029),
                         Single Tower Map2 (17293), Join To Tower (17486), Join To Raid (17800)
      6. Reroll       -> Hero Fastroll (7241), Weapon Fastroll (7633), Pet Gear (8002),
                         Halo (8217), Ornament (8311)
      7. Player       -> PANEL: PLAYER (7022)
      8. Setting      -> PANEL: SETTINGS (19002)
      9. Webhook      -> PANEL: WEBHOOK (19113)
      10. Config      -> PANEL: CONFIG (20199)
      11. Theme       -> PANEL: THEME (21364)

      [belum dipetakan ke tab mana - tunggu instruksi]: Claim Reward (18167),
        Anniversary Celebration (18475) -- kemungkinan masuk ke dalam tab Main atau
        tab tersendiri, BELUM ditentukan di list barumu. Tanya saya nanti kalau sudah sampai sana.

    [v3] PENAMBAHAN ke tab Main:
      - COUNTER AUTO SELL HERO EQUIP  (Paragraph: R/Y/B/Supreme + Button RESET COUNTER)
      - AUTO SELL HERO EQUIP          (Toggle + seluruh logika sell)
        Logika: StartAutoSell, scanGuidNames, getType, getGrade, shouldSell, doSell,
                _sellToggleCb, global expose _setSellHeroToggle/_visSellHero/_autoSellOnState
      - Status info via Paragraph yang diupdate realtime

    [v4] PENAMBAHAN ke tab Main:
      - AUTO COLLECT GOLD & ITEM      (Toggle + seluruh logika collect)
        Dependency chain:
          _collectObj           (baris ~486)  - TP obj ke player + fire CollectItem/ExtraReward
          _instantCollectConns  (baris ~483)  - tabel koneksi instant collector
          _instantCollected     (baris ~484)  - dedup cache instant collector
          StartInstantGoldCollector (baris ~511) - listen ChildAdded per folder
          _goldMagnetRunning    (baris ~2420) - flag magnet loop
          StartGoldMagnet       (baris ~2421) - loop TP semua item ke player tiap 0.05s
          StopGoldMagnet        (baris ~2468) - stop magnet loop
          DoAutoCollect         (baris ~2720) - polling loop collect via StartLoop
          DoAutoCollectGoldItem (baris ~2472) - master toggle: panggil semua di atas
        Global expose: _setAutoCollectToggle, _visAutoCollect, _autoCollectState
        Dependency global: STATE, LOOPS, COLLECTED, RE, LP, PG_Wait, StartLoop, StopLoop
--]]

--  SERVICES 
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer
local PG                = LP:WaitForChild("PlayerGui")
local Remotes           = ReplicatedStorage:WaitForChild("Remotes")

--  BLOCK HERO HIT-ANIM (GLOBAL, independen RA/TA) 
-- Menstop AnimationTrack yang menumpuk di Animator milik Hero (workspace.Heros)
-- akibat spam attack (RA/TA) supaya tidak kena limit 64 track/Animator.
-- HANYA menstop AnimationTrack -- tidak menyentuh remote/fire attack logic,
-- jadi TIDAK mengganggu fungsi serang RA/TA. Aktif dari awal script jalan,
-- tidak bergantung pada state RA.running / TA.running manapun.
local _heroAnimConns = {}
local function _blockHeroTrack(animator)
    pcall(function()
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            track:Stop(0)
        end
    end)
    table.insert(_heroAnimConns, animator.AnimationPlayed:Connect(function(track)
        pcall(function() track:Stop(0) end)
    end))
end

local function _hookHeroFolder()
    local herosFolder = workspace:FindFirstChild("Heros")
    if not herosFolder then return end

    -- pasang di semua Animator yang sudah ada
    for _, desc in ipairs(herosFolder:GetDescendants()) do
        if desc:IsA("Animator") then
            _blockHeroTrack(desc)
        end
    end

    -- pasang di Animator baru (hero baru di-summon/respawn)
    table.insert(_heroAnimConns, herosFolder.DescendantAdded:Connect(function(desc)
        if desc:IsA("Animator") then
            _blockHeroTrack(desc)
        end
    end))
end

task.spawn(function()
    -- tunggu folder Heros muncul kalau belum ada saat script pertama jalan
    local herosFolder = workspace:FindFirstChild("Heros")
    if not herosFolder then
        herosFolder = workspace:WaitForChild("Heros", 30)
    end
    pcall(_hookHeroFolder)
end)

--  GLOBALS FARM (dibutuhkan StartRA / TA) 
HERO_GUIDS       = HERO_GUIDS or {}
HERO_DATA        = HERO_DATA  or {}
_walkSpeedState  = _walkSpeedState or 16
MY_USER_ID       = MY_USER_ID or LP.UserId

function IsValidUUID(str)
    if type(str) ~= "string" then return false end
    return str:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

--  GLOBALS BERSAMA (dibutuhkan AUTO COLLECT dan fitur lain) 
-- Source asli baris ~1504
STATE = {
    autoCollect         = false,
    autoCollectGoldItem = false,
    autoDestroyer       = false,
    autoArise           = false,
    noClip              = false,
    antiAfk             = false,
    autoConfirm         = false,
    autoClose           = false,
}
LOOPS     = {}  -- { [key] = thread } - dikelola StopLoop/StartLoop
COLLECTED = {}  -- dedup cache collect loop

--  StopLoop / StartLoop 
-- Source asli baris ~1507-1516
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

--  PG_Wait (Adaptive PingGuard wait) 
-- Source asli baris ~1588-1594
-- Fallback ke 1x kalau PG_Multiplier() belum ada (kerangka standalone).
-- Saat digabung ke script utama, PG_Multiplier() dari script utama yang dipakai.
if not PG_Wait then
    function PG_Wait(baseTime)
        local mult = (type(PG_Multiplier) == "function") and PG_Multiplier() or 1
        local t = (baseTime or 0.05) * mult
        if t > 5 then t = 5 end
        task.wait(t)
    end
end

--  RE: Remote Events / Functions 
-- Source asli baris ~443-477
-- Hanya remote yang dibutuhkan fitur di kerangka ini.
-- Remote lain (HeroUseSkill, Atk, dll) ditambahkan saat panel lain masuk.
RE = RE or {}
RE.CollectItem      = RE.CollectItem      or Remotes:WaitForChild("CollectItem", 10)
RE.ExtraReward      = RE.ExtraReward      or Remotes:WaitForChild("ExtraReward", 10)
RE.Click            = RE.Click            or Remotes:FindFirstChild("ClickEnemy")
RE.Atk              = RE.Atk              or Remotes:FindFirstChild("PlayerClickAttackSkill")
RE.Death            = RE.Death            or Remotes:FindFirstChild("EnemyDeath")
RE.HeroMove         = RE.HeroMove         or Remotes:FindFirstChild("HeroMoveToEnemyPos")
RE.HeroStand        = RE.HeroStand        or Remotes:FindFirstChild("HeroStandTo")
RE.HeroSkill        = RE.HeroSkill        or Remotes:FindFirstChild("HeroPlaySkillAnim")
RE.HeroUseSkill     = RE.HeroUseSkill     or Remotes:FindFirstChild("HeroUseSkill")
RE.StartTp          = RE.StartTp          or Remotes:FindFirstChild("StartLocalPlayerTeleport")
RE.LocalTp          = RE.LocalTp          or Remotes:FindFirstChild("LocalPlayerTeleport")
-- Hero Fastroll remotes
RE.RandomHeroQuirk  = RE.RandomHeroQuirk  or Remotes:WaitForChild("RandomHeroQuirk", 10)
RE.AutoHeroQuirk    = RE.AutoHeroQuirk    or Remotes:WaitForChild("AutoRandomHeroQuirk", 10)
-- Weapon Fastroll remotes
RE.RandomWeaponQuirk = RE.RandomWeaponQuirk or Remotes:WaitForChild("RandomWeaponQuirk", 10)
RE.AutoWeaponQuirk   = RE.AutoWeaponQuirk   or Remotes:WaitForChild("AutoRandomWeaponQuirk", 15)
-- Pet Gear Fastroll remotes (remote literal-nya bernama "RandomHeroEquipGrade" / "AutoRandomHeroEquipGrade"
-- meski dipakai untuk Pet Gear, bukan Hero - confirmed sniff 1.lua baris 460 & 3428)
RE.RandomPetGearGrade = RE.RandomPetGearGrade or Remotes:WaitForChild("RandomHeroEquipGrade", 10)
RE.AutoPetGearGrade    = RE.AutoPetGearGrade    or Remotes:WaitForChild("AutoRandomHeroEquipGrade", 15)
-- Halo Gacha remote (RemoteFunction)
RE.RerollHalo          = RE.RerollHalo          or Remotes:FindFirstChild("RerollHalo")
-- Ornament Roll remote (RemoteFunction)
RE.RerollOrnament      = RE.RerollOrnament      or Remotes:WaitForChild("RerollOrnament", 15)

-- ============================================================================
-- WINDUI EMBEDDED (v1.6.65) - Source lokal, TIDAK butuh HTTP/GitHub sama sekali
-- Di-embed langsung dari main.lua resmi WindUI (Footagesus/WindUI, Lisensi MIT)
-- supaya script ini 100% mandiri dan tidak pernah gagal load karena
-- GitHub down / rate limit / path/dist dihapus oleh maintainer.
-- ============================================================================
local function _LoadWindUI_Embedded()
--[[
     _      ___         ____  ______
    | | /| / (_)__  ___/ / / / /  _/
    | |/ |/ / / _ \/ _  / /_/ // /  
    |__/|__/_/_//_/\_,_/\____/___/
    
    v1.6.65  |  2026-07-01  |  Roblox UI Library for scripts
    
    To view the source code, see the `src/` folder on the official GitHub repository.
    
    Author: Footagesus (Footages, .ftgs, oftgs)
    Github: https://github.com/Footagesus/WindUI
    Discord: https://discord.gg/ftgs-development-hub-1300692552005189632
    License: MIT
]]

type ConfigType__DARKLUA_TYPE_a={
Object:Instance,
Camera:Instance?,
Interactive:boolean?,
Height:number?,
Focused:boolean,

Window:any,
WindUI:any,
Tab:any,
Parent:Instance,
}local a a={cache={}, load=function(b)if not a.cache[b]then a.cache[b]={c=a[b]()}end return a.cache[b].c end}do function a.a()

local b

local d={
New=nil,
Init=nil,
Shapes={
Circle={
Image="rbxassetid://111665032676235",
Rect=Rect.new(512,512,512,512),
Radius=512,
},
CircleOutline={
Image="rbxassetid://108556680453287",
Rect=Rect.new(512,512,512,512),
Radius=512,
},
CircleGlass={
Image="rbxassetid://95600044758841",
Rect=Rect.new(512,512,512,512),
Radius=512,
},



SquircleH={
Image="rbxassetid://125083578015333",
Rect=Rect.new(512,325,512,325),
Radius=325,
},
SquircleHOutline={
Image="rbxassetid://107043713170567",
Rect=Rect.new(512,325,512,325),
Radius=325,
},
SquircleHGlass={
Image="rbxassetid://84819521201001",
Rect=Rect.new(512,325,512,325),
Radius=325,
},
["SquircleH-TL-TR"]={
Image="rbxassetid://90680657206619",
Rect=Rect.new(807,512,807,512),
Radius=325,
AutoChange=false,
},
["SquircleH-BL-BR"]={
Image="rbxassetid://99216342056719",
Rect=Rect.new(0,512,0,512),
Radius=325,
AutoChange=false,
},

SquircleV={
Image="rbxassetid://124965260437653",
Rect=Rect.new(325,512,325,512),
Radius=325,
},
SquircleVOutline={
Image="rbxassetid://88808835404198",
Rect=Rect.new(325,512,325,512),
Radius=325,
},
SquircleVGlass={
Image="rbxassetid://124982801466667",
Rect=Rect.new(325,512,325,512),
Radius=325,
},

Squircle={
Image="rbxassetid://89641024074289",
Rect=Rect.new(460,460,460,460),
Radius=310,
},
SquircleOutline={
Image="rbxassetid://74029063732681",
Rect=Rect.new(512,512,512,512),
Radius=310,
},
SquircleGlass={
Image="rbxassetid://131126436897551",
Rect=Rect.new(512,512,512,512),
Radius=310,
},

["Squircle-TL-TR"]={
Image="rbxassetid://75712142040725",
Rect=Rect.new(512,512,512,512),
Radius=310,
AutoChange=false,
},
["Squircle-BL-BR"]={
Image="rbxassetid://83676684425544",
Rect=Rect.new(512,0,512,0),
Radius=310,
AutoChange=false,
},Square=
{
Image="rbxassetid://82909646051652",
Rect=Rect.new(512,512,512,512),
Radius=512,
AutoChange=false,
},
},
}

function d.Init(e,f)
b=f
return e.New
end

function d.New(e,f,g,h,i,j,l)
local m={
Radius=f or 0,
Type=g or"Circle",
GetRadius=nil,
GetType=nil,
SetRadius=nil,
SetType=nil,
}

local p={
["Glass-0.7"]="SquircleGlass",
["Glass-1"]="SquircleGlass",
["Glass-1.4"]="SquircleGlass",
["Squircle-Outline"]="SquircleOutline",
}

local function GetShape(r)
return d.Shapes[p[r]or r]or d.Shapes.Circle
end

local r=b.New(j and"ImageButton"or"ImageLabel",{
Image="",
ScaleType=l~=false and"Slice"or nil,
SliceCenter=m.Type~="Squircle"and Rect.new(512,512,512,512)or nil,
SliceScale=1,
ThemeTag=h and h.ThemeTag or nil,
BackgroundTransparency=1,
},i)

for u,v in next,h do
if not table.find({"ThemeTag"},u)then
r[u]=v
end
end

function m.SetRadius(u,v)
m.Radius=v
r.SliceScale=math.max(v/GetShape(m.Type).Radius,0.0001)
return m
end

function m.SetType(u,v)
m.Type=v
local x=GetShape(v)
r.Image=x.Image
r.SliceCenter=x.Rect
m:SetRadius(m.Radius)
return m
end

function m.GetRadius(u)
return m.Radius
end

function m.GetType(u)
return m.Type
end

m:SetRadius(f)
m:SetType(g)

b.AddSignal(r:GetPropertyChangedSignal"AbsoluteSize",function()
local u=GetShape(m.Type)
if u.AutoChange==false then
return
end

if string.find(m.Type,"Squircle")then
local v=string.find(m.Type,"Glass")and"Glass"or nil
local x=string.find(m.Type,"Outline")and"Outline"or nil

local z=math.round(r.AbsoluteSize.X/b.UIScale)
local A=math.round(r.AbsoluteSize.Y/b.UIScale)

local B=m.Radius~=0 and m.Radius or math.min(z,A)/2
local C=d.Shapes.Squircle.Radius/1024
local F=B/math.min(z,A)

local G

if z>A then
if F>=C then
G="SquircleH"..(x or v or"")
else
G="Squircle"..(x or v or"")
end
elseif z<A then
if F>=C then
G="SquircleV"..(x or v or"")
else
G="Squircle"..(x or v or"")
end
else
if F>=C then
G="Circle"..(x or v or"")
else
G="Squircle"..(x or v or"")
end
end

if G~=m:GetType()then
m:SetType(G)
end
end
end)

return r,m
end

return d end function a.b()

local b=(cloneref or clonereference or function(b)return b end)

local d=b(game:GetService"ReplicatedStorage":WaitForChild("GetIcons",99999):InvokeServer())

local function parseIconString(e)
if type(e)=="string"then
local f=e:find":"
if f then
local g=e:sub(1,f-1)
local h=e:sub(f+1)
return g,h
end
end
return nil,e
end

function d.AddIcons(e,f)
if type(e)~="string"or type(f)~="table"then
error"AddIcons: packName must be string, iconsData must be table"
return
end

if not d.Icons[e]then
d.Icons[e]={
Icons={},
Spritesheets={}
}
end

for g,h in pairs(f)do
if type(h)=="number"or(type(h)=="string"and h:match"^rbxassetid://")then
local i=h
if type(h)=="number"then
i="rbxassetid://"..tostring(h)
end

d.Icons[e].Icons[g]={
Image=i,
ImageRectSize=Vector2.new(0,0),
ImageRectPosition=Vector2.new(0,0),
Parts=nil
}
d.Icons[e].Spritesheets[i]=i

elseif type(h)=="table"then
if h.Image and h.ImageRectSize and h.ImageRectPosition then
local i=h.Image
if type(i)=="number"then
i="rbxassetid://"..tostring(i)
end

d.Icons[e].Icons[g]={
Image=i,
ImageRectSize=h.ImageRectSize,
ImageRectPosition=h.ImageRectPosition,
Parts=h.Parts
}

if not d.Icons[e].Spritesheets[i]then
d.Icons[e].Spritesheets[i]=i
end
else
warn("AddIcons: Invalid spritesheet data format for icon '"..g.."'")
end
else
warn("AddIcons: Unsupported data type for icon '"..g.."': "..type(h))
end
end
end

function d.SetIconsType(e)
d.IconsType=e
end

local e
function d.Init(f,g)
d.New=f
d.IconThemeTag=g

e=f
return d
end

function d.Icon(f,g,h)
h=h~=false
local i,j=parseIconString(f)

local l=i or g or d.IconsType
local m=j

local p=d.Icons[l]

if p and p.Icons and p.Icons[m]then
return{
p.Spritesheets[tostring(p.Icons[m].Image)],
p.Icons[m],
}
elseif p and p[m]and string.find(p[m],"rbxassetid://")then
return h and{
p[m],
{ImageRectSize=Vector2.new(0,0),ImageRectPosition=Vector2.new(0,0)}
}or p[m]
end
return nil
end

function d.GetIcon(f,g)
return d.Icon(f,g,false)
end


function d.Icon2(f,g,h)
return d.Icon(f,g,true)
end

function d.Image(f)
local g={
Icon=f.Icon or nil,
Type=f.Type,
Colors=f.Colors or{(d.IconThemeTag or Color3.new(1,1,1)),Color3.new(1,1,1)},
Transparency=f.Transparency or{0,0},
Size=f.Size or UDim2.new(0,24,0,24),

IconFrame=nil,
}

local h={}
local i={}

for j,l in next,g.Colors do
h[j]={
ThemeTag=typeof(l)=="string"and l,
Color=typeof(l)=="Color3"and l,
}
end

for j,l in next,g.Transparency do
i[j]={
ThemeTag=typeof(l)=="string"and l,
Value=typeof(l)=="number"and l,
}
end


local j=d.Icon2(g.Icon,g.Type)
local l=typeof(j)=="string"and string.find(j,'rbxassetid://')

if d.New then
local m=e or d.New



local p=m("ImageLabel",{
Size=g.Size,
BackgroundTransparency=1,
ImageColor3=h[1].Color or nil,
ImageTransparency=i[1].Value or nil,
ThemeTag=h[1].ThemeTag and{
ImageColor3=h[1].ThemeTag,
ImageTransparency=i[1].ThemeTag,
},
Image=l and j or j[1],
ImageRectSize=l and nil or j[2].ImageRectSize,
ImageRectOffset=l and nil or j[2].ImageRectPosition,
})


if not l and j[2].Parts then
for r,u in next,j[2].Parts do
local v=d.Icon(u,g.Type)

m("ImageLabel",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
ImageColor3=h[1+r].Color or nil,
ImageTransparency=i[1+r].Value or nil,
ThemeTag=h[1+r].ThemeTag and{
ImageColor3=h[1+r].ThemeTag,
ImageTransparency=i[1+r].ThemeTag,
},
Image=v[1],
ImageRectSize=v[2].ImageRectSize,
ImageRectOffset=v[2].ImageRectPosition,
Parent=p,
})
end
end

g.IconFrame=p
else
local m=Instance.new"ImageLabel"
m.Size=g.Size
m.BackgroundTransparency=1
m.ImageColor3=h[1].Color
m.ImageTransparency=i[1].Value or nil
m.Image=l and j or j[1]
m.ImageRectSize=l and nil or j[2].ImageRectSize
m.ImageRectOffset=l and nil or j[2].ImageRectPosition


if not l and j[2].Parts then
for p,r in next,j[2].Parts do
local u=d.Icon(r,g.Type)

local v=Instance.New"ImageLabel"
v.Size=UDim2.new(1,0,1,0)
v.BackgroundTransparency=1
v.ImageColor3=h[1+p].Color
v.ImageTransparency=i[1+p].Value or nil
v.Image=u[1]
v.ImageRectSize=u[2].ImageRectSize
v.ImageRectOffset=u[2].ImageRectPosition
v.Parent=m
end
end

g.IconFrame=m
end


return g
end

return d end function a.c()
return function(b)
return{


Primary="Icon",

White=Color3.new(1,1,1),
Black=Color3.new(0,0,0),

Dialog="Accent",

Background="Accent",
BackgroundTransparency=0,
Hover="Text",

PanelBackground="White",
PanelBackgroundTransparency=0.95,

WindowBackground="Background",

WindowShadow="Black",


WindowTopbarTitle="Text",
WindowTopbarAuthor="Text",
WindowTopbarIcon="Icon",
WindowTopbarButtonIcon="Icon",


WindowSearchBarBackground="Dialog",

TabBackground="Hover",
TabBackgroundHover="Hover",
TabBackgroundHoverTransparency=0.97,
TabBackgroundActive="Hover",
TabBackgroundActiveTransparency=0.93,
TabText="Text",
TabTextTransparency=0.3,
TabTextTransparencyActive=0,
TabTitle="Text",
TabIcon="Icon",
TabIconTransparency=0.4,
TabIconTransparencyActive=0.1,
TabBorderTransparency=1,
TabBorderTransparencyActive=0.75,
TabBorder="White",

ElementBackground="Text",
ElementBackgroundTransparency=0.93,
ElementBackgroundHover=b:AddColor("ElementBackground","#ffffff",0.1),
ElementTitle="Text",
ElementDesc="Text",
ElementIcon="Icon",

PopupBackground="Background",
PopupBackgroundTransparency="BackgroundTransparency",
PopupTitle="Text",
PopupContent="Text",
PopupIcon="Icon",

DialogBackground="Dialog",
DialogBackgroundTransparency="BackgroundTransparency",
DialogTitle="Text",
DialogContent="Text",
DialogIcon="Icon",

Toggle="Button",
ToggleBar="White",

Checkbox="Primary",
CheckboxIcon="White",
CheckboxBorder="White",
CheckboxBorderTransparency=0.75,

SliderIcon="Icon",

Slider="Primary",
SliderThumb="White",
SliderIconFrom="SliderIcon",
SliderIconTo="SliderIcon",

ProgressBar="Primary",
ProgressBarTrack="Text",
ProgressBarTrackTransparency=0.9,
ProgressBarText="Text",

Tooltip=Color3.fromHex"4C4C4C",
TooltipText="White",
TooltipSecondary="Primary",
TooltipSecondaryText="White",

TabSectionIcon="Icon",

SectionIcon="Icon",

SectionExpandIcon="Icon",
SectionExpandIconTransparency=0.4,
SectionBox="Text",
SectionBoxTransparency=0.95,
SectionBoxBorder="White",
SectionBoxBorderTransparency=0.75,
SectionBoxBackground="Text",
SectionBoxBackgroundTransparency=0.97,

SearchBarBorder="White",
SearchBarBorderTransparency=0.75,

Notification="Background",
Notification2="White",
Notification2Transparency=0.92,
NotificationTitle="Text",
NotificationTitleTransparency=0,
NotificationContent="Text",
NotificationContentTransparency=0.4,
NotificationDuration="White",
NotificationDurationTransparency=0.95,
NotificationBorder="White",
NotificationBorderTransparency=0.75,

DropdownTabBorder="White",
DropdownTabBackground="ElementBackground",
DropdownBackground="Background",

LabelBackground="White",
LabelBackgroundTransparency=0.95,

ViewportBackground="ElementBackground",
ViewportBackgroundTransparency="ElementBackgroundTransparency",
}
end end function a.d()

local b=(cloneref or clonereference or function(b)
return b
end)

local d=b(game:GetService"RunService")
local e=b(game:GetService"UserInputService")
local f=b(game:GetService"TweenService")
local g=b(game:GetService"LocalizationService")
local h=b(game:GetService"HttpService")

local i=a.load'a'local j=

d.Heartbeat

local l="https://raw.githubusercontent.com/Footagesus/Icons/main/Main-v2.lua"

local m
if d:IsStudio()or not writefile then
m=a.load'b'
else
m=loadstring(
game.HttpGet and game:HttpGet(l)or h:GetAsync(l)
)()
end

m.SetIconsType"lucide"

local p

local r
r={
Font="rbxassetid://12187365364",
Localization=nil,
CanDraggable=true,
Theme=nil,
Themes=nil,
Icons=m,
Signals={},
Objects={},
LocalizationObjects={},
UIScale=1,
FontObjects={},
Language=string.match(g.SystemLocaleId,"^[a-z]+"),
Request=http_request or(syn and syn.request)or request,
DefaultProperties={
ScreenGui={
ResetOnSpawn=false,
ZIndexBehavior="Sibling",
},
CanvasGroup={
BorderSizePixel=0,
BackgroundColor3=Color3.new(1,1,1),
},
Frame={
BorderSizePixel=0,
BackgroundColor3=Color3.new(1,1,1),
},
TextLabel={
BackgroundColor3=Color3.new(1,1,1),
BorderSizePixel=0,
Text="",
RichText=true,
TextColor3=Color3.new(1,1,1),
TextSize=14,
},
TextButton={
BackgroundColor3=Color3.new(1,1,1),
BorderSizePixel=0,
Text="",
AutoButtonColor=false,
TextColor3=Color3.new(1,1,1),
TextSize=14,
},
TextBox={
BackgroundColor3=Color3.new(1,1,1),
BorderColor3=Color3.new(0,0,0),
ClearTextOnFocus=false,
Text="",
TextColor3=Color3.new(0,0,0),
TextSize=14,
},
ImageLabel={
BackgroundTransparency=1,
BackgroundColor3=Color3.new(1,1,1),
BorderSizePixel=0,
},
ImageButton={
BackgroundColor3=Color3.new(1,1,1),
BorderSizePixel=0,
AutoButtonColor=false,
},
UIListLayout={
SortOrder="LayoutOrder",
},
ScrollingFrame={
ScrollBarImageTransparency=1,
BorderSizePixel=0,
},
VideoFrame={
BorderSizePixel=0,
},
},
Colors={
Red="#e53935",
Orange="#f57c00",
Green="#43a047",
Blue="#039be5",
White="#ffffff",
Grey="#484848",
},
ThemeFallbacks=nil,





















ThemeChangeCallbacks={},
}

function r.Init(u)
p=u

r.ThemeFallbacks=a.load'c'(r)

r.UIScale=u.UIScale

i:Init(r)
end

function r.AddSignal(u,v)
local x=u:Connect(v)
table.insert(r.Signals,x)
return x
end

function r.DisconnectAll()
for u,v in next,r.Signals do
local x=table.remove(r.Signals,u)
x:Disconnect()
end
end

function r.SafeCallback(u,...)
if not u then
return
end

local v,x=pcall(u,...)
if not v then
if p and p.Window and p.Window.Debug then local
z, A=x:find":%d+: "

warn("[ WindUI: DEBUG Mode ] "..x)

return p:Notify{
Title="DEBUG Mode: Error",
Content=not A and x or x:sub(A+1),
Duration=8,
}
end
end
end

function r.Gradient(u,v)
if p and p.Gradient then
return p:Gradient(u,v)
end

local x={}
local z={}

for A,B in next,u do
local C=tonumber(A)
if C then
C=math.clamp(C/100,0,1)
table.insert(x,ColorSequenceKeypoint.new(C,B.Color))
table.insert(z,NumberSequenceKeypoint.new(C,B.Transparency or 0))
end
end

table.sort(x,function(A,B)
return A.Time<B.Time
end)
table.sort(z,function(A,B)
return A.Time<B.Time
end)

if#x<2 then
error"ColorSequence requires at least 2 keypoints"
end

local A={
Color=ColorSequence.new(x),
Transparency=NumberSequence.new(z),
}

if v then
for B,C in pairs(v)do
A[B]=C
end
end

return A
end

function r.SetTheme(u)
local v=r.Theme
r.Theme=u
r.UpdateTheme(nil,false)

for x,z in next,r.ThemeChangeCallbacks do
r.SafeCallback(z,u,v)
end
end

function r.AddFontObject(u)
table.insert(r.FontObjects,u)
r.UpdateFont(r.Font)
end

function r.UpdateFont(u)
r.Font=u
for v,x in next,r.FontObjects do
x.FontFace=Font.new(u,x.FontFace.Weight,x.FontFace.Style)
end
end

function r.GetThemeProperty(u,v)
local function getValue(x,z)
local A=z[x]

if A==nil then
return nil
end

if typeof(A)=="string"and string.sub(A,1,1)=="#"then
return Color3.fromHex(A)
end

if typeof(A)=="Color3"then
return A
end

if typeof(A)=="number"then
return A
end

if typeof(A)=="table"and A.Color and A.Transparency then
return A
end

if typeof(A)=="function"then
return A(z)
end

return A
end

local x=getValue(u,v)
if x~=nil then
if typeof(x)=="string"and string.sub(x,1,1)~="#"then
local z=r.GetThemeProperty(x,v)
if z~=nil then
return z
end
else
return x
end
end

local z=r.ThemeFallbacks[u]
if z~=nil then
if typeof(z)=="string"and string.sub(z,1,1)~="#"then
return r.GetThemeProperty(z,v)
else
return getValue(u,{[u]=z})
end
end

x=getValue(u,r.Themes.Dark)
if x~=nil then
if typeof(x)=="string"and string.sub(x,1,1)~="#"then
local A=r.GetThemeProperty(x,r.Themes.Dark)
if A~=nil then
return A
end
else
return x
end
end

if z~=nil then
if typeof(z)=="string"and string.sub(z,1,1)~="#"then
return r.GetThemeProperty(z,r.Themes.Dark)
else
return getValue(u,{[u]=z})
end
end

return nil
end

function r.AddThemeObject(u,v,x)
if r.Objects[u]then
for z,A in pairs(v)do
r.Objects[u].Properties[z]=A
end
else
r.Objects[u]={Object=u,Properties=v}
end

if not x then
r.UpdateTheme(u,false)
end
return u
end

function r.AddLangObject(u)
local v=r.LocalizationObjects[u]
if not v then
return
end

local x=v.Object

r.SetLangForObject(u)

return x
end

function r.UpdateTheme(u,v,x,z,A,B)
local function ApplyTheme(C)
for F,G in pairs(C.Properties or{})do
local H=r.GetThemeProperty(G,r.Theme)
if H~=nil then
if typeof(H)=="Color3"then
local J=C.Object:FindFirstChild"LibraryGradient"
if J then
J:Destroy()
end

if x then
r.Tween(
C.Object,
z or 0.2,
{[F]=H},
A or Enum.EasingStyle.Quint,
B or Enum.EasingDirection.Out
):Play()
elseif v then
r.Tween(C.Object,0.08,{[F]=H}):Play()
else
C.Object[F]=H
end
elseif typeof(H)=="table"and H.Color and H.Transparency then
C.Object[F]=Color3.new(1,1,1)

local J=C.Object:FindFirstChild"LibraryGradient"
if not J then
J=Instance.new"UIGradient"
J.Name="LibraryGradient"
J.Parent=C.Object
end

J.Color=H.Color
J.Transparency=H.Transparency

for L,M in pairs(H)do
if L~="Color"and L~="Transparency"and J[L]~=nil then
J[L]=M
end
end
elseif typeof(H)=="number"then
if x then
r.Tween(
C.Object,
z or 0.2,
{[F]=H},
A or Enum.EasingStyle.Quint,
B or Enum.EasingDirection.Out
):Play()
elseif v then
r.Tween(C.Object,0.08,{[F]=H}):Play()
else
C.Object[F]=H
end
end
else
local J=C.Object:FindFirstChild"LibraryGradient"
if J then
J:Destroy()
end
end
end
end

if u then
local C=r.Objects[u]
if C then
ApplyTheme(C)
end
else
for C,F in pairs(r.Objects)do
ApplyTheme(F)
end
end
end

function r.SetThemeTag(u,v,x,z,A)
r.AddThemeObject(u,v)
r.UpdateTheme(u,false,true,x,z,A)
end

function r.SetLangForObject(u)
if r.Localization and r.Localization.Enabled then
local v=r.LocalizationObjects[u]
if not v then
return
end

local x=v.Object
local z=v.TranslationId

local A=r.Localization.Translations[r.Language]
if A and A[z]then
x.Text=A[z]
else
local B=r.Localization
and r.Localization.Translations
and r.Localization.Translations.en
or nil
if B and B[z]then
x.Text=B[z]
else
x.Text="["..z.."]"
end
end
end
end

function r.ChangeTranslationKey(u,v,x)
if r.Localization and r.Localization.Enabled then
local z=string.match(x,"^"..r.Localization.Prefix.."(.+)")
if z then
for A,B in ipairs(r.LocalizationObjects)do
if B.Object==v then
B.TranslationId=z
r.SetLangForObject(A)
return
end
end

table.insert(r.LocalizationObjects,{
TranslationId=z,
Object=v,
})
r.SetLangForObject(#r.LocalizationObjects)
end
end
end

function r.UpdateLang(u)
if u then
r.Language=u
end

for v=1,#r.LocalizationObjects do
local x=r.LocalizationObjects[v]
if x.Object and x.Object.Parent~=nil then
r.SetLangForObject(v)
else
r.LocalizationObjects[v]=nil
end
end
end

function r.SetLanguage(u)
r.Language=u
r.UpdateLang()
end

function r.Icon(u,v)
return m.Icon2(u,nil,v~=false)
end

function r.AddIcons(u,v)
return m.AddIcons(u,v)
end

function r.New(u,v,x)
local z=Instance.new(u)

for A,B in next,r.DefaultProperties[u]or{}do
z[A]=B
end

for A,B in next,v or{}do
if A~="ThemeTag"then
z[A]=B
end
if r.Localization and r.Localization.Enabled and A=="Text"then
local C=string.match(B,"^"..r.Localization.Prefix.."(.+)")
if C then
local F=#r.LocalizationObjects+1
r.LocalizationObjects[F]={TranslationId=C,Object=z}

r.SetLangForObject(F)
end
end
end

for A,B in next,x or{}do
B.Parent=z
end

if v and v.ThemeTag then
r.AddThemeObject(z,v.ThemeTag)
end
if v and v.FontFace then
r.AddFontObject(z)
end
return z
end

function r.Tween(u,v,x,...)
return f:Create(u,TweenInfo.new(v,...),x)
end








































































function r.NewRoundFrame(u,v,x,z,A,B)
return i:New(u,v,x,z,A,nil)
end

local u=r.New local v=
r.Tween

function r.SetDraggable(x)
r.CanDraggable=x
end

function r.Drag(x,z,A)
local B=p.GenerateGUID()

local C
local F=false
local G,H
local J

local L={
CanDraggable=true,
}

if not z or typeof(z)~="table"then
z={x}
end

local function update(M)
if not F or not L.CanDraggable then
return
end

local N=M.Position-G
r.Tween(x,0.02,{
Position=UDim2.new(
H.X.Scale,
H.X.Offset+N.X,
H.Y.Scale,
H.Y.Offset+N.Y
),
}):Play()
end

for M,N in pairs(z)do
N.InputBegan:Connect(function(O)
if not L.CanDraggable or F then
return
end

if
O.UserInputType==Enum.UserInputType.MouseButton1
or O.UserInputType==Enum.UserInputType.Touch
then
if p and p.CurrentInput and p.CurrentInput~=B then
return
end

p.CurrentInput=B

F=true
J=O
C=N
G=O.Position
H=x.Position

if A and typeof(A)=="function"then
A(true,C)
end
end
end)
end

e.InputChanged:Connect(function(M)
if not F then
return
end
if p.CurrentInput and p.CurrentInput~=B then
return
end

if J.UserInputType==Enum.UserInputType.MouseButton1 then
if M.UserInputType==Enum.UserInputType.MouseMovement then
update(M)
end
elseif J.UserInputType==Enum.UserInputType.Touch then
if M==J then
update(M)
end
end
end)

e.InputEnded:Connect(function(M)
if not F or p.CurrentInput~=B then
return
end

if
M==J
or(
J.UserInputType==Enum.UserInputType.MouseButton1
and M.UserInputType==Enum.UserInputType.MouseButton1
)
then
p.CurrentInput=nil
F=false
J=nil
C=nil

if A and typeof(A)=="function"then
A(false,nil)
end
end
end)

function L.Set(M,N)
L.CanDraggable=N
end

return L
end

m.Init(u,"Icon")

function r.SanitizeFilename(x)
local z=x:match"([^/]+)$"or x

z=z:gsub("%.[^%.]+$","")

z=z:gsub("[^%w%-_]","_")

if#z>50 then
z=z:sub(1,50)
end

return z
end

function r.Image(x,z,A,B,C,F,G,H)
B=B or"Temp"
z=r.SanitizeFilename(z)

local J=u("Frame",{
Size=UDim2.new(0,0,0,0),
BackgroundTransparency=1,
},{
u("ImageLabel",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
ScaleType="Crop",
ThemeTag=(r.Icon(x)or G)and{
ImageColor3=F and(H or"Icon")or nil,
}or nil,
},{
u("UICorner",{
CornerRadius=UDim.new(0,A),
}),
}),
})
if r.Icon(x)then
J.ImageLabel:Destroy()

local L=m.Image{
Icon=x,
Size=UDim2.new(1,0,1,0),
Colors={
(F and(H or"Icon")or false),
"Button",
},
}.IconFrame
L.Parent=J
elseif string.find(x,"http")and not string.find(x,"roblox.com")then
local L="WindUI/"..B.."/assets/."..C.."-"..z..".png"
local M,N=pcall(function()
task.spawn(function()
local M=r.Request
and r.Request{
Url=x,
Method="GET",
}.Body
or{}

if not d:IsStudio()and writefile then
writefile(L,M)
end


local N,O=pcall(getcustomasset,L)
if N then
J.ImageLabel.Image=O
else
warn(
string.format(
"[ WindUI.Creator ] Failed to load custom asset '%s': %s",
L,
tostring(O)
)
)
J:Destroy()

return
end
end)
end)
if not M then
warn(
"[ WindUI.Creator ]  '"..identifyexecutor()
or"Studio".."' doesnt support the URL Images. Error: "..N
)

J:Destroy()
end
elseif x==""then
J.Visible=false
else
J.ImageLabel.Image=x
end

return J
end

function r.Color3ToHSB(x)
local z,A,B=x.R,x.G,x.B
local C=math.max(z,A,B)
local F=math.min(z,A,B)
local G=C-F

local H=0
if G~=0 then
if C==z then
H=(A-B)/G%6
elseif C==A then
H=(B-z)/G+2
else
H=(z-A)/G+4
end
H=H*60
else
H=0
end

local J=(C==0)and 0 or(G/C)
local L=C

return{
h=math.floor(H+0.5),
s=J,
b=L,
}
end

function r.GetPerceivedBrightness(x)
local z=x.R
local A=x.G
local B=x.B
return 0.299*z+0.587*A+0.114*B
end

function r.GetTextColorForHSB(x,z)
local A=r.Color3ToHSB(x)local
B, C, F=A.h, A.s, A.b
if r.GetPerceivedBrightness(x)>(z or 0.5)then
return Color3.fromHSV(B/360,0,0.05)
else
return Color3.fromHSV(B/360,0,0.98)
end
end

function r.GetAverageColor(x)
local z,A,B=0,0,0
local C=x.Color.Keypoints
for F,G in ipairs(C)do

z=z+G.Value.R
A=A+G.Value.G
B=B+G.Value.B
end
local F=#C
return Color3.new(z/F,A/F,B/F)
end

function r.GenerateUniqueID(x)
return h:GenerateGUID(false)
end

function r.OnThemeChange(x,z)
if typeof(z)~="function"then
return
end

local A=h:GenerateGUID(false)
r.ThemeChangeCallbacks[A]=z

return{
Disconnect=function()
r.ThemeChangeCallbacks[A]=nil
end,
}
end

function r.AddColor(x,z,A,B)
B=math.clamp(B or 1,0,1)
if typeof(A)=="string"then
A=Color3.fromHex(A)
end

return function(C)
local F
if typeof(z)=="string"and string.sub(z,1,1)~="#"then
F=r.GetThemeProperty(z,C)
elseif typeof(z)=="string"then
F=Color3.fromHex(z)
else
F=z
end

if not F or typeof(F)~="Color3"then
return nil
end

return Color3.new(
math.clamp(F.R+A.R*B,0,1),
math.clamp(F.G+A.G*B,0,1),
math.clamp(F.B+A.B*B,0,1)
)
end
end

function r.GetElementPosition(x,z,A,B)
if type(A)~="number"or A~=math.floor(A)then
return nil,1
end






local C=#z


if C==0 or A<1 or A>C then
return nil,2
end

local function isDelimiter(F)
if F==nil then
return true
end
local G=F.__type
return G=="Divider"or G=="Space"or G=="Section"
end

if isDelimiter(z[A])then
return nil,3
end

local function calculate(F,G)
if G==1 then
return"Squircle"
end
if F==1 then
return B and"SquircleH-TL-TR"or"Squircle-TL-TR"
end
if F==G then
return B and"SquircleH-BL-BR"or"Squircle-BL-BR"
end
return"Square"
end

local F=1
local G=0

for H=1,C do
local J=z[H]
if isDelimiter(J)then
if A>=F and A<=H-1 then
local L=A-F+1
return calculate(L,G)
end
F=H+1
G=0
else
G=G+1
end
end

if A>=F and A<=C then
local H=A-F+1
return calculate(H,G)
end

return nil,4
end

return r end function a.e()

local b={}







function b.New(d,e,f)
local g={
Enabled=e.Enabled or false,
Translations=e.Translations or{},
Prefix=e.Prefix or"loc:",
DefaultLanguage=e.DefaultLanguage or"en"
}

f.Localization=g

return g
end



return b end function a.f()
local b=a.load'd'
local d=b.New
local e=b.Tween

local f={
Size=UDim2.new(0,300,1,-156),
SizeLower=UDim2.new(0,300,1,-56),
UICorner=18,
UIPadding=14,

Holder=nil,
NotificationIndex=0,
Notifications={},
}

function f.Init(g)
local h={
Lower=false,
}

function h.SetLower(i)
h.Lower=i
h.Frame.Size=i and f.SizeLower or f.Size
end

h.Frame=d("Frame",{
Position=UDim2.new(1,-29,0,56),
AnchorPoint=Vector2.new(1,0),
Size=f.Size,
Parent=g,
BackgroundTransparency=1,




},{
d("UIListLayout",{
HorizontalAlignment="Center",
SortOrder="LayoutOrder",
VerticalAlignment="Bottom",
Padding=UDim.new(0,8),
}),
d("UIPadding",{
PaddingBottom=UDim.new(0,29),
}),
})
return h
end

function f.New(g)
local h={
Title=g.Title or"Notification",
Content=g.Content or nil,
Icon=g.Icon or nil,
IconThemed=g.IconThemed,
Background=g.Background,
BackgroundImageTransparency=g.BackgroundImageTransparency,
Duration=g.Duration or 5,
Buttons=g.Buttons or{},
CanClose=g.CanClose~=false,
UIElements={},
Closed=false,
}



f.NotificationIndex=f.NotificationIndex+1
f.Notifications[f.NotificationIndex]=h









local i

if h.Icon then





















i=b.Image(
h.Icon,
h.Title..":"..h.Icon,
0,
g.Window,
"Notification",
h.IconThemed
)
i.Size=UDim2.new(0,26,0,26)
i.Position=UDim2.new(0,f.UIPadding,0,f.UIPadding)

end

local l
if h.CanClose then
l=d("ImageButton",{
Image=b.Icon"x"[1],
ImageRectSize=b.Icon"x"[2].ImageRectSize,
ImageRectOffset=b.Icon"x"[2].ImageRectPosition,
BackgroundTransparency=1,
Size=UDim2.new(0,16,0,16),
Position=UDim2.new(1,-f.UIPadding,0,f.UIPadding),
AnchorPoint=Vector2.new(1,0),
ThemeTag={
ImageColor3="Text",
},
ImageTransparency=0.4,
},{
d("TextButton",{
Size=UDim2.new(1,8,1,8),
BackgroundTransparency=1,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Text="",
}),
})
end

local m=b.NewRoundFrame(f.UICorner,"Squircle",{
Size=UDim2.new(0,0,1,0),
ThemeTag={
ImageTransparency="NotificationDurationTransparency",
ImageColor3="NotificationDuration",
},

})

local p=d("Frame",{
Size=UDim2.new(1,h.Icon and-28-f.UIPadding or 0,1,0),
Position=UDim2.new(1,0,0,0),
AnchorPoint=Vector2.new(1,0),
BackgroundTransparency=1,
AutomaticSize="Y",
},{
d("UIPadding",{
PaddingTop=UDim.new(0,f.UIPadding),
PaddingLeft=UDim.new(0,f.UIPadding),
PaddingRight=UDim.new(0,f.UIPadding),
PaddingBottom=UDim.new(0,f.UIPadding),
}),
d("TextLabel",{
AutomaticSize="Y",
Size=UDim2.new(1,-30-f.UIPadding,0,0),
TextWrapped=true,
TextXAlignment="Left",
RichText=true,
BackgroundTransparency=1,
TextSize=18,
ThemeTag={
TextColor3="NotificationTitle",
TextTransparency="NotificationTitleTransparency",
},
Text=h.Title,
FontFace=Font.new(b.Font,Enum.FontWeight.SemiBold),
}),
d("UIListLayout",{
Padding=UDim.new(0,f.UIPadding/3),
}),
})

if h.Content then
d("TextLabel",{
AutomaticSize="Y",
Size=UDim2.new(1,0,0,0),
TextWrapped=true,
TextXAlignment="Left",
RichText=true,
BackgroundTransparency=1,

TextSize=15,
ThemeTag={
TextColor3="NotificationContent",
TextTransparency="NotificationContentTransparency",
},
Text=h.Content,
FontFace=Font.new(b.Font,Enum.FontWeight.Medium),
Parent=p,
})
end

local r=b.NewRoundFrame(f.UICorner,"Squircle",{
Size=UDim2.new(1,0,0,0),
Position=UDim2.new(2,0,1,0),
AnchorPoint=Vector2.new(0,1),
AutomaticSize="Y",
ImageTransparency=0.05,
ThemeTag={
ImageColor3="Notification",
},

},{
b.NewRoundFrame(f.UICorner,"Squircle",{
Size=UDim2.new(1,0,1,0),
ThemeTag={
ImageColor3="Notification2",
ImageTransparency="Notification2Transparency",
},
}),
d("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
Name="DurationFrame",
},{






d("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
ClipsDescendants=true,
},{
m,
}),




}),
d("ImageLabel",{
Name="Background",
Image=h.Background,
BackgroundTransparency=1,
Size=UDim2.new(1,0,1,0),
ScaleType="Crop",
ImageTransparency=h.BackgroundImageTransparency,

},{
d("UICorner",{
CornerRadius=UDim.new(0,f.UICorner),
}),
}),

p,
i,
l,
})

local u=d("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,0,0),
Parent=g.Holder,
},{
r,
})

function h.Close(v)
if not h.Closed then
h.Closed=true
e(
u,
0.45,
{Size=UDim2.new(1,0,0,-8)},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
e(r,0.55,{Position=UDim2.new(2,0,1,0)},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
task.wait(0.45)
u:Destroy()
end
end

task.spawn(function()
task.wait()
e(
u,
0.45,
{Size=UDim2.new(1,0,0,r.AbsoluteSize.Y)},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
e(r,0.45,{Position=UDim2.new(0,0,1,0)},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
if h.Duration then
m.Size=UDim2.new(0,r.DurationFrame.AbsoluteSize.X,1,0)
e(
r.DurationFrame.Frame,
h.Duration,
{Size=UDim2.new(0,0,1,0)},
Enum.EasingStyle.Linear,
Enum.EasingDirection.InOut
):Play()
task.wait(h.Duration)
h:Close()
end
end)

if l then
b.AddSignal(l.TextButton.MouseButton1Click,function()
h:Close()
end)
end


return h
end

return f end function a.g()












local b=4294967296;local d=b-1;local function c(e,f)local g,h=0,1;while e~=0 or f~=0 do local i,l=e%2,f%2;local m=(i+l)%2;g=g+m*h;e=math.floor(e/2)f=math.floor(f/2)h=h*2 end;return g%b end;local function k(e,f,g,...)local h;if f then e=e%b;f=f%b;h=c(e,f)if g then h=k(h,g,...)end;return h elseif e then return e%b else return 0 end end;local function n(e,f,g,...)local h;if f then e=e%b;f=f%b;h=(e+f-c(e,f))/2;if g then h=n(h,g,...)end;return h elseif e then return e%b else return d end end;local function o(e)return d-e end;local function q(e,f)if f<0 then return lshift(e,-f)end;return math.floor(e%4294967296/2^f)end;local function s(e,f)if f>31 or f<-31 then return 0 end;return q(e%b,f)end;local function lshift(e,f)if f<0 then return s(e,-f)end;return e*2^f%4294967296 end;local function t(e,f)e=e%b;f=f%32;local g=n(e,2^f-1)return s(e,f)+lshift(g,32-f)end;local e={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}local function w(f)return string.gsub(f,".",function(g)return string.format("%02x",string.byte(g))end)end;local function y(f,g)local h=""for i=1,g do local l=f%256;h=string.char(l)..h;f=(f-l)/256 end;return h end;local function D(f,g)local h=0;for i=g,g+3 do h=h*256+string.byte(f,i)end;return h end;local function E(f,g)local h=64-(g+9)%64;g=y(8*g,8)f=f.."\128"..string.rep("\0",h)..g;assert(#f%64==0)return f end;local function I(f)f[1]=0x6a09e667;f[2]=0xbb67ae85;f[3]=0x3c6ef372;f[4]=0xa54ff53a;f[5]=0x510e527f;f[6]=0x9b05688c;f[7]=0x1f83d9ab;f[8]=0x5be0cd19;return f end;local function K(f,g,h)local i={}for l=1,16 do i[l]=D(f,g+(l-1)*4)end;for l=17,64 do local m=i[l-15]local p=k(t(m,7),t(m,18),s(m,3))m=i[l-2]i[l]=(i[l-16]+p+i[l-7]+k(t(m,17),t(m,19),s(m,10)))%b end;local l,m,p,r,u,v,x,z=h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]for A=1,64 do local B=k(t(l,2),t(l,13),t(l,22))local C=k(n(l,m),n(l,p),n(m,p))local F=(B+C)%b;local G=k(t(u,6),t(u,11),t(u,25))local H=k(n(u,v),n(o(u),x))local J=(z+G+H+e[A]+i[A])%b;z=x;x=v;v=u;u=(r+J)%b;r=p;p=m;m=l;l=(J+F)%b end;h[1]=(h[1]+l)%b;h[2]=(h[2]+m)%b;h[3]=(h[3]+p)%b;h[4]=(h[4]+r)%b;h[5]=(h[5]+u)%b;h[6]=(h[6]+v)%b;h[7]=(h[7]+x)%b;h[8]=(h[8]+z)%b end;local function Z(f)f=E(f,#f)local g=I{}for h=1,#f,64 do K(f,h,g)end;return w(y(g[1],4)..y(g[2],4)..y(g[3],4)..y(g[4],4)..y(g[5],4)..y(g[6],4)..y(g[7],4)..y(g[8],4))end;local f;local g={["\\"]="\\",["\""]="\"",["\b"]="b",["\f"]="f",["\n"]="n",["\r"]="r",["\t"]="t"}local h={["/"]="/"}for i,l in pairs(g)do h[l]=i end;local i=function(i)return"\\"..(g[i]or string.format("u%04x",i:byte()))end;local l=function(l)return"null"end;local m=function(m,p)local r={}p=p or{}if p[m]then error"circular reference"end;p[m]=true;if rawget(m,1)~=nil or next(m)==nil then local u=0;for v in pairs(m)do if type(v)~="number"then error"invalid table: mixed or invalid key types"end;u=u+1 end;if u~=#m then error"invalid table: sparse array"end;for v,x in ipairs(m)do table.insert(r,f(x,p))end;p[m]=nil;return"["..table.concat(r,",").."]"else for u,v in pairs(m)do if type(u)~="string"then error"invalid table: mixed or invalid key types"end;table.insert(r,f(u,p)..":"..f(v,p))end;p[m]=nil;return"{"..table.concat(r,",").."}"end end;local p=function(p)return'"'..p:gsub('[%z\1-\31\\"]',i)..'"'end;local r=function(r)if r~=r or r<=-math.huge or r>=math.huge then error("unexpected number value '"..tostring(r).."'")end;return string.format("%.14g",r)end;local u={["nil"]=l,table=m,string=p,number=r,boolean=tostring}f=function(v,x)local z=type(v)local A=u[z]if A then return A(v,x)end;error("unexpected type '"..z.."'")end;local v=function(v)return f(v)end;local x;local z=function(...)local z={}for A=1,select("#",...)do z[select(A,...)]=true end;return z end;local A=z(" ","\t","\r","\n")local B=z(" ","\t","\r","\n","]","}",",")local C=z("\\","/",'"',"b","f","n","r","t","u")local F=z("true","false","null")local G={["true"]=true,["false"]=false,null=nil}local H=function(H,J,L,M)for N=J,#H do if L[H:sub(N,N)]~=M then return N end end;return#H+1 end;local J=function(J,L,M)local N=1;local O=1;for P=1,L-1 do O=O+1;if J:sub(P,P)=="\n"then N=N+1;O=1 end end;error(string.format("%s at line %d col %d",M,N,O))end;local L=function(L)local M=math.floor;if L<=0x7f then return string.char(L)elseif L<=0x7ff then return string.char(M(L/64)+192,L%64+128)elseif L<=0xffff then return string.char(M(L/4096)+224,M(L%4096/64)+128,L%64+128)elseif L<=0x10ffff then return string.char(M(L/262144)+240,M(L%262144/4096)+128,M(L%4096/64)+128,L%64+128)end;error(string.format("invalid unicode codepoint '%x'",L))end;local M=function(M)local N=tonumber(M:sub(1,4),16)local O=tonumber(M:sub(7,10),16)if O then return L((N-0xd800)*0x400+O-0xdc00+0x10000)else return L(N)end end;local N=function(N,O)local P=""local Q=O+1;local R=Q;while Q<=#N do local S=N:byte(Q)if S<32 then J(N,Q,"control character in string")elseif S==92 then P=P..N:sub(R,Q-1)Q=Q+1;local T=N:sub(Q,Q)if T=="u"then local U=N:match("^[dD][89aAbB]%x%x\\u%x%x%x%x",Q+1)or N:match("^%x%x%x%x",Q+1)or J(N,Q-1,"invalid unicode escape in string")P=P..M(U)Q=Q+#U else if not C[T]then J(N,Q-1,"invalid escape char '"..T.."' in string")end;P=P..h[T]end;R=Q+1 elseif S==34 then P=P..N:sub(R,Q-1)return P,Q+1 end;Q=Q+1 end;J(N,O,"expected closing quote for string")end;local O=function(O,P)local Q=H(O,P,B)local R=O:sub(P,Q-1)local S=tonumber(R)if not S then J(O,P,"invalid number '"..R.."'")end;return S,Q end;local P=function(P,Q)local R=H(P,Q,B)local S=P:sub(Q,R-1)if not F[S]then J(P,Q,"invalid literal '"..S.."'")end;return G[S],R end;local Q=function(Q,R)local S={}local T=1;R=R+1;while 1 do local U;R=H(Q,R,A,true)if Q:sub(R,R)=="]"then R=R+1;break end;U,R=x(Q,R)S[T]=U;T=T+1;R=H(Q,R,A,true)local V=Q:sub(R,R)R=R+1;if V=="]"then break end;if V~=","then J(Q,R,"expected ']' or ','")end end;return S,R end;local R=function(R,S)local T={}S=S+1;while 1 do local U,V;S=H(R,S,A,true)if R:sub(S,S)=="}"then S=S+1;break end;if R:sub(S,S)~='"'then J(R,S,"expected string for key")end;U,S=x(R,S)S=H(R,S,A,true)if R:sub(S,S)~=":"then J(R,S,"expected ':' after key")end;S=H(R,S+1,A,true)V,S=x(R,S)T[U]=V;S=H(R,S,A,true)local W=R:sub(S,S)S=S+1;if W=="}"then break end;if W~=","then J(R,S,"expected '}' or ','")end end;return T,S end;local S={['"']=N,["0"]=O,["1"]=O,["2"]=O,["3"]=O,["4"]=O,["5"]=O,["6"]=O,["7"]=O,["8"]=O,["9"]=O,["-"]=O,t=P,f=P,n=P,["["]=Q,["{"]=R}x=function(T,U)local V=T:sub(U,U)local W=S[V]if W then return W(T,U)end;J(T,U,"unexpected character '"..V.."'")end;local T=function(T)if type(T)~="string"then error("expected argument of type string, got "..type(T))end;local U,V=x(T,H(T,1,A,true))V=H(T,V,A,true)if V<=#T then J(T,V,"trailing garbage")end;return U end;
local U,V,W=v,T,Z;





local X={}

local Y=(cloneref or clonereference or function(Y)return Y end)


function X.New(_,aa)

local ab=_;
local ac=aa;
local ad=true;


local ae=function(ae)end;


repeat task.wait(1)until game:IsLoaded();


local af=false;
local ag,ah,ai,aj,ak,al,am,an,ao=setclipboard or toclipboard,request or http_request or syn_request,string.char,tostring,string.sub,os.time,math.random,math.floor,gethwid or function()return Y(game:GetService"Players").LocalPlayer.UserId end
local ap,aq="",0;


local ar="https://api.platoboost.app";
local as=ah{
Url=ar.."/public/connectivity",
Method="GET"
};
if as.StatusCode~=200 and as.StatusCode~=429 then
ar="https://api.platoboost.net";
end


function cacheLink()
if aq+(600)<al()then
local at=ah{
Url=ar.."/public/start",
Method="POST",
Body=U{
service=ab,
identifier=W(ao())
},
Headers={
["Content-Type"]="application/json",
["User-Agent"]="Roblox/Exploit"
}
};

if at.StatusCode==200 then
local au=V(at.Body);

if au.success==true then
ap=au.data.url;
aq=al();
return true,ap
else
ae(au.message);
return false,au.message
end
elseif at.StatusCode==429 then
local au="you are being rate limited, please wait 20 seconds and try again.";
ae(au);
return false,au
end

local au="Failed to cache link.";
ae(au);
return false,au
else
return true,ap
end
end

cacheLink();


local at=function()
local at=""
for au=1,16 do
at=at..ai(an(am()*(26))+97)
end
return at
end


for au=1,5 do
local av=at();
task.wait(0.2)
if at()==av then
local aw="platoboost nonce error.";
ae(aw);
error(aw);
end
end


local au=function()
local au,av=cacheLink();

if au then
ag(av);
end
end


local av=function(av)
local aw=at();
local ax=ar.."/public/redeem/"..aj(ab);

local ay={
identifier=W(ao()),
key=av
}

if ad then
ay.nonce=aw;
end

local az=ah{
Url=ax,
Method="POST",
Body=U(ay),
Headers={
["Content-Type"]="application/json"
}
};

if az.StatusCode==200 then
local aA=V(az.Body);

if aA.success==true then
if aA.data.valid==true then
if ad then
if aA.data.hash==W("true".."-"..aw.."-"..ac)then
return true
else
ae"failed to verify integrity.";
return false
end
else
return true
end
else
ae"key is invalid.";
return false
end
else
if ak(aA.message,1,27)=="unique constraint violation"then
ae"you already have an active key, please wait for it to expire before redeeming it.";
return false
else
ae(aA.message);
return false
end
end
elseif az.StatusCode==429 then
ae"you are being rate limited, please wait 20 seconds and try again.";
return false
else
ae"server returned an invalid status code, please try again later.";
return false
end
end


local aw=function(aw)
if af==true then
return false,("A request is already being sent, please slow down.")
else
af=true;
end

local ax=at();
local ay=ar.."/public/whitelist/"..aj(ab).."?identifier="..W(ao()).."&key="..aw;

if ad then
ay=ay.."&nonce="..ax;
end

local az=ah{
Url=ay,
Method="GET",
};

af=false;

if az.StatusCode==200 then
local aA=V(az.Body);

if aA.success==true then
if aA.data.valid==true then
if ad then
if aA.data.hash==W("true".."-"..ax.."-"..ac)then
return true,""
else
return false,("failed to verify integrity.")
end
else
return true
end
else
if ak(aw,1,4)=="KEY_"then
return true,av(aw)
else
return false,("Key is invalid.")
end
end
else
return false,(aA.message)
end
elseif az.StatusCode==429 then
return false,("You are being rate limited, please wait 20 seconds and try again.")
else
return false,("Server returned an invalid status code, please try again later.")
end
end


local ax=function(ax)
local ay=at();
local az=ar.."/public/flag/"..aj(ab).."?name="..ax;

if ad then
az=az.."&nonce="..ay;
end

local aA=ah{
Url=az,
Method="GET",
};

if aA.StatusCode==200 then
local aB=V(aA.Body);

if aB.success==true then
if ad then
if aB.data.hash==W(aj(aB.data.value).."-"..ay.."-"..ac)then
return aB.data.value
else
ae"failed to verify integrity.";
return nil
end
else
return aB.data.value
end
else
ae(aB.message);
return nil
end
else
return nil
end
end


return{
Verify=aw,
GetFlag=ax,
Copy=au,
}
end


return X end function a.h()






local aa=(cloneref or clonereference or function(aa)
return aa
end)

local ab=aa(game:GetService"HttpService")
local ac={}

function ac.New(ad)
local ae=gethwid or function()
return aa(game:GetService"Players").LocalPlayer.UserId
end
local af,ag=request or http_request or syn_request,setclipboard or toclipboard

function ValidateKey(ah)
local ai="https://api.pandauth.com/api/v1/keys/validate"

local aj={
ServiceID=ad,
HWID=tostring(ae()),
Key=tostring(ah),
}

local ak=ab:JSONEncode(aj)
local al,am=pcall(function()
return af{
Url=ai,
Method="POST",
Headers={
["User-Agent"]="Roblox/Exploit",
["Content-Type"]="application/json",
},
Body=ak,
}
end)

if al and am then
if am.Success then
local an,ao=pcall(function()
return ab:JSONDecode(am.Body)
end)

if an and ao then
if ao.Authenticated_Status and ao.Authenticated_Status=="Success"then
return true,"Authenticated"
else
local ap=ao.Note or"Unknown reason"
return false,"Authentication failed: "..ap
end
else
return false,"JSON decode error"
end
else
warn(
" HTTP request was not successful. Code: "
..tostring(am.StatusCode)
.." Message: "
..am.StatusMessage
)
return false,"HTTP request failed: "..am.StatusMessage
end
else
return false,"Request pcall error"
end
end

function GetKeyLink()
return"https://new.pandadevelopment.net/getkey/"..tostring(ad).."?hwid="..tostring(ae())
end

function CopyLink()
return ag(GetKeyLink())
end

return{
Verify=ValidateKey,
Copy=CopyLink,
}
end

return ac end function a.i()







local aa={}

function aa.New(ab,ac)
local ad="https://sdkapi-public.luarmor.net/library.lua"

local ae=loadstring(game.HttpGet and game:HttpGet(ad)or HttpService:GetAsync(ad))()
local af=setclipboard or toclipboard

ae.script_id=ab

function ValidateKey(ag)
local ah=ae.check_key(ag)


if ah.code=="KEY_VALID"then
return true,"Whitelisted!"
elseif ah.code=="KEY_HWID_LOCKED"then
return false,"Key linked to a different HWID. Please reset it using our bot"
elseif ah.code=="KEY_INCORRECT"then
return false,"Key is wrong or deleted!"
else
return false,"Key check failed:"..ah.message.." Code: "..ah.code
end
end

function CopyLink()
af(tostring(ac))
end

return{
Verify=ValidateKey,
Copy=CopyLink,
}
end

return aa end function a.j()









local aa={}

function aa.New(ab,ac,ad)
JunkieProtected.API_KEY=ac
JunkieProtected.PROVIDER=ad
JunkieProtected.SERVICE_ID=ab

local function ValidateKey(ae)
if not ae or ae==""then
print"No key provided!"

return false,"No key provided. Please get a key."
end

local af=JunkieProtected.IsKeylessMode()
if af and af.keyless_mode then
print"Keyless mode enabled. Starting script..."
return true,"Keyless mode enabled. Starting script..."
end

local ag=JunkieProtected.ValidateKey{Key=ae}
if ag=="valid"then
print"Key is valid! Starting script..."
load()
if _G.JD_IsPremium then
print"Premium user detected!"
else
print"Standard user"
end

return true,"Key is valid!"
else
local ah=JunkieProtected.GetKeyLink()
print"Invalid key!"

return false,"Invalid key. Get one from:"..ah
end
end

local function copyLink()
local ae=JunkieProtected.GetKeyLink()

if setclipboard then
setclipboard(ae)
end
end
return{
Verify=ValidateKey,
Copy=copyLink
}
end

return aa end function a.k()



return{
platoboost={
Name="Platoboost",
Icon="rbxassetid://75920162824531",
Args={"ServiceId","Secret"},

New=a.load'g'.New
},
pandadevelopment={
Name="Panda Development",
Icon="panda",
Args={"ServiceId"},

New=a.load'h'.New
},
luarmor={
Name="Luarmor",
Icon="rbxassetid://130918283130165",
Args={"ScriptId","Discord"},

New=a.load'i'.New
},
junkiedevelopment={
Name="Junkie Development",
Icon="rbxassetid://106310347705078",
Args={"ServiceId","ApiKey","Provider"},

New=a.load'j'.New
},


}end function a.l()



return[[
{
    "name": "windui",
    "version": "1.6.65",
    "main": "./dist/main.lua",
    "repository": "https://github.com/Footagesus/WindUI",
    "discord": "https://discord.gg/ftgs-development-hub-1300692552005189632",
    "author": "Footagesus",
    "description": "Roblox UI Library for scripts",
    "license": "MIT",
    "scripts": {
        "dev": "bash build/build.sh dev $INPUT_FILE",
        "build": "bash build/build.sh build $INPUT_FILE",
        "live": "python3 -m http.server 8642",
        "watch": "chokidar . -i 'node_modules' -i 'dist' -i 'build' -c 'npm run dev --'",
        "live-build": "concurrently \"npm run live\" \"npm run watch --\"",
        "example-live-build": "INPUT_FILE=main_example.lua npm run live-build",
        "updater": "python3 updater/main.py"
    },
    "keywords": [
        "ui-library",
        "ui-design",
        "script",
        "script-hub",
        "exploiting"
    ],
    "devDependencies": {
        "chokidar-cli": "^3.0.0",
        "concurrently": "^9.2.0"
    }
}
]]end function a.m()

local aa={}

local ab=a.load'd'
local ac=ab.New
local ad=ab.Tween

function aa.New(ae,af,ag,ah,ai,aj,ak,al)
ah=ah or"Primary"
local am=al or(not ak and 10 or 999)
local an
if af and af~=""then
an=ac("ImageLabel",{
Image=ab.Icon(af)[1],
ImageRectSize=ab.Icon(af)[2].ImageRectSize,
ImageRectOffset=ab.Icon(af)[2].ImageRectPosition,
Size=UDim2.new(0,21,0,21),
BackgroundTransparency=1,
ImageColor3=ah=="White"and Color3.new(0,0,0)or nil,
ImageTransparency=ah=="White"and 0.4 or 0,
ThemeTag={
ImageColor3=ah~="White"and"Icon"or nil,
},
})
end

local ao=ac("TextButton",{
Size=UDim2.new(0,0,1,0),
AutomaticSize="X",
Parent=ai,
BackgroundTransparency=1,
},{
ab.NewRoundFrame(am,"Squircle",{
ThemeTag={
ImageColor3=ah~="White"and"Button"or nil,
},
ImageColor3=ah=="White"and Color3.new(1,1,1)or nil,
Size=UDim2.new(1,0,1,0),
Name="Squircle",
ImageTransparency=ah=="Primary"and 0 or ah=="White"and 0 or 0.9,
}),

ab.NewRoundFrame(am,"Squircle",{



ImageColor3=Color3.new(1,1,1),
Size=UDim2.new(1,0,1,0),
Name="Special",
ImageTransparency=ah=="Secondary"and 0.95 or 1,
}),

ab.NewRoundFrame(am,"Shadow-sm",{



ImageColor3=Color3.new(0,0,0),
Size=UDim2.new(1,3,1,3),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Name="Shadow",

ImageTransparency=1,
Visible=not ak,
}),

ab.NewRoundFrame(am,"SquircleGlass",{
ThemeTag={
ImageColor3="White",
},
Size=UDim2.new(1,1,1,1),

ImageTransparency=0.9,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Name="Outline",
},{













}),

ab.NewRoundFrame(am,"Squircle",{
Size=UDim2.new(1,0,1,0),
Name="Frame",
ThemeTag={
ImageColor3=ah~="White"and"Text"or nil,
},
ImageColor3=ah=="White"and Color3.new(0,0,0)or nil,
ImageTransparency=1,
},{
ac("UIPadding",{
PaddingLeft=UDim.new(0,16),
PaddingRight=UDim.new(0,16),
}),
ac("UIListLayout",{
FillDirection="Horizontal",
Padding=UDim.new(0,8),
VerticalAlignment="Center",
HorizontalAlignment="Center",
}),
an,
ac("TextLabel",{
BackgroundTransparency=1,
FontFace=Font.new(ab.Font,Enum.FontWeight.SemiBold),
Text=ae or"Button",
ThemeTag={
TextColor3=(ah~="Primary"and ah~="White")and"Text",
},
TextColor3=ah=="Primary"and Color3.new(1,1,1)
or ah=="White"and Color3.new(0,0,0)
or nil,
AutomaticSize="XY",
TextSize=18,
}),
}),
})

ab.AddSignal(ao.MouseEnter,function()
ad(ao.Frame,0.047,{ImageTransparency=0.95}):Play()
end)
ab.AddSignal(ao.MouseLeave,function()
ad(ao.Frame,0.047,{ImageTransparency=1}):Play()
end)
ab.AddSignal(ao.MouseButton1Click,function()
if aj then
aj:Close()()
end
if ag then
ab.SafeCallback(ag)
end
end)

return ao
end

return aa end function a.n()

local aa={}

local ab=a.load'd'
local ac=ab.New local ad=
ab.Tween

function aa.New(ae,af,ag,ah,ai,aj,ak,al,am)
ah=ah or"Input"
local an=ak or 10
local ao
if af and af~=""then
ao=ac("ImageLabel",{
Image=ab.Icon(af)[1],
ImageRectSize=ab.Icon(af)[2].ImageRectSize,
ImageRectOffset=ab.Icon(af)[2].ImageRectPosition,
Size=UDim2.new(0,21,0,21),
BackgroundTransparency=1,
ThemeTag={
ImageColor3="Icon",
},
})
end

local ap=ah=="Textarea"

local aq=ac("TextBox",{
BackgroundTransparency=1,
TextSize=17,
FontFace=Font.new(ab.Font,Enum.FontWeight.Regular),
Size=UDim2.new(1,ao and-29 or 0,1,0),
PlaceholderText=ae,
ClearTextOnFocus=al or false,
ClipsDescendants=true,
TextWrapped=ap,
MultiLine=ap,
TextXAlignment="Left",
TextYAlignment=ah~="Textarea"and"Center"or"Top",

ThemeTag={
PlaceholderColor3="PlaceholderText",
TextColor3="Text",
},
})

local ar=ac("Frame",{
Size=UDim2.new(1,0,0,42),
Parent=ag,
BackgroundTransparency=1,
},{
ac("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
},{
ab.NewRoundFrame(an,"Squircle",{
ThemeTag={
ImageColor3="Placeholder",
},
Size=UDim2.new(1,0,1,0),
ImageTransparency=0.85,
}),
not am and ab.NewRoundFrame(an-1,"SquircleGlass",{
ThemeTag={
ImageColor3="Outline",
},
Size=UDim2.new(1,1,1,1),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
ImageTransparency=0.8,
})or nil,
ab.NewRoundFrame(an,"Squircle",{
Size=UDim2.new(1,0,1,0),
Name="Frame",
ThemeTag={
ImageColor3="LabelBackground",
ImageTransparency="LabelBackgroundTransparency",
},


},{
ac("UIPadding",{
PaddingTop=UDim.new(0,ah~="Textarea"and 0 or 12),
PaddingLeft=UDim.new(0,12),
PaddingRight=UDim.new(0,12),
PaddingBottom=UDim.new(0,ah~="Textarea"and 0 or 12),
}),
ac("UIListLayout",{
FillDirection="Horizontal",
Padding=UDim.new(0,8),
VerticalAlignment=ah~="Textarea"and"Center"or"Top",
HorizontalAlignment="Left",
}),
ao,
aq,
}),
}),
})










if aj then
ab.AddSignal(aq:GetPropertyChangedSignal"Text",function()
if ai then
ab.SafeCallback(ai,aq.Text)
end
end)
else
ab.AddSignal(aq.FocusLost,function()
if ai then
ab.SafeCallback(ai,aq.Text)
end
end)
end

return ar
end

return aa end function a.o()

local aa=a.load'd'
local ab=aa.New
local ac=aa.Tween




local ad={
Holder=nil,

Parent=nil,
}

function ad.Create(ae,af,ag,ah,ai)
local aj={
UICorner=28,
UIPadding=12,

Window=ag,
WindUI=ah,

UIElements={},
}

if ae then
aj.UIPadding=0
end
if ae then
aj.UICorner=26
end

af=af or"Dialog"

if not ae then
aj.UIElements.FullScreen=ab("Frame",{
ZIndex=999,
BackgroundTransparency=1,
BackgroundColor3=Color3.fromHex"#000000",
Size=UDim2.new(1,0,1,0),
Active=false,
Visible=false,
Parent=ad.Parent
or(ag and ag.UIElements and ag.UIElements.Main and ag.UIElements.Main.Main),
},{
ab("UICorner",{
CornerRadius=UDim.new(0,ag.UICorner),
}),
})
end

ab("ImageLabel",{
Image="rbxassetid://8992230677",
ThemeTag={
ImageColor3="WindowShadow",

},
ImageTransparency=1,
Size=UDim2.new(1,100,1,100),
Position=UDim2.new(0,-50,0,-50),
ScaleType="Slice",
SliceCenter=Rect.new(99,99,99,99),
BackgroundTransparency=1,
ZIndex=-999999999999999,
Name="Blur",
})

aj.UIElements.Main=ab("Frame",{
Size=UDim2.new(0,280,0,0),
ThemeTag={
BackgroundColor3=af.."Background",
},
AutomaticSize="Y",
BackgroundTransparency=1,
Visible=false,
ZIndex=99999,
},{
ab("UIPadding",{
PaddingTop=UDim.new(0,aj.UIPadding),
PaddingLeft=UDim.new(0,aj.UIPadding),
PaddingRight=UDim.new(0,aj.UIPadding),
PaddingBottom=UDim.new(0,aj.UIPadding),
}),
})

aj.UIElements.MainContainer=aa.NewRoundFrame(aj.UICorner,"Squircle",{
Visible=false,

ImageTransparency=ae and 0.15 or 0,
Parent=ai or aj.UIElements.FullScreen,
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
AutomaticSize="XY",
ThemeTag={
ImageColor3=af.."Background",
ImageTransparency=af.."BackgroundTransparency",
},
ZIndex=9999,
},{






aj.UIElements.Main,




















})

function aj.Open(ak)
if not ae then
aj.UIElements.FullScreen.Visible=true
aj.UIElements.FullScreen.Active=true
end

task.spawn(function()
aj.UIElements.MainContainer.Visible=true

if not ae then
ac(aj.UIElements.FullScreen,0.1,{BackgroundTransparency=0.65}):Play()
end
ac(aj.UIElements.MainContainer,0.1,{ImageTransparency=0}):Play()


task.spawn(function()
task.wait(0.05)
aj.UIElements.Main.Visible=true
end)
end)
end
function aj.Close(ak)
if not ae then
ac(aj.UIElements.FullScreen,0.1,{BackgroundTransparency=1}):Play()
aj.UIElements.FullScreen.Active=false
task.spawn(function()
task.wait(0.1)
aj.UIElements.FullScreen.Visible=false
end)
end
aj.UIElements.Main.Visible=false

ac(aj.UIElements.MainContainer,0.1,{ImageTransparency=1}):Play()



task.spawn(function()
task.wait(0.1)
if not ae then
aj.UIElements.FullScreen:Destroy()
else
aj.UIElements.MainContainer:Destroy()
end
end)

return function()end
end


return aj
end

return ad end function a.p()

local aa={}

local ab=a.load'd'
local ac=ab.New
local ad=ab.Tween

local ae=a.load'm'.New
local af=a.load'n'.New

function aa.new(ag,ah,ai,aj)
local ak=a.load'o'
local al=ak.Create(true,"Popup",ag.Window,ag.WindUI,ag.WindUI.ScreenGui.KeySystem)

local am={}

local an

local ao=(ag.KeySystem.Thumbnail and ag.KeySystem.Thumbnail.Width)or 200

local ap=430
if ag.KeySystem.Thumbnail and ag.KeySystem.Thumbnail.Image then
ap=430+(ao/2)
end

al.UIElements.Main.AutomaticSize="Y"
al.UIElements.Main.Size=UDim2.new(0,ap,0,0)

local aq

if ag.Icon then
aq=
ab.Image(ag.Icon,ag.Title..":"..ag.Icon,0,"Temp","KeySystem",ag.IconThemed)
aq.Size=UDim2.new(0,24,0,24)
aq.LayoutOrder=-1
end

local ar=ac("TextLabel",{
AutomaticSize="XY",
BackgroundTransparency=1,
Text=ag.KeySystem.Title or ag.Title,
FontFace=Font.new(ab.Font,Enum.FontWeight.SemiBold),
ThemeTag={
TextColor3="Text",
},
TextSize=20,
})

local as=ac("TextLabel",{
AutomaticSize="XY",
BackgroundTransparency=1,
Text="Key System",
AnchorPoint=Vector2.new(1,0.5),
Position=UDim2.new(1,0,0.5,0),
TextTransparency=1,
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
ThemeTag={
TextColor3="Text",
},
TextSize=16,
})

local at=ac("Frame",{
BackgroundTransparency=1,
AutomaticSize="XY",
},{
ac("UIListLayout",{
Padding=UDim.new(0,14),
FillDirection="Horizontal",
VerticalAlignment="Center",
}),
aq,
ar,
})

local au=ac("Frame",{
AutomaticSize="Y",
Size=UDim2.new(1,0,0,0),
BackgroundTransparency=1,
},{





at,
as,
})

local av=af("Enter Key","key",nil,"Input",function(av)
an=av
end)

local aw
if ag.KeySystem.Note and ag.KeySystem.Note~=""then
aw=ac("TextLabel",{
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
TextXAlignment="Left",
Text=ag.KeySystem.Note,
TextSize=18,
TextTransparency=0.4,
ThemeTag={
TextColor3="Text",
},
BackgroundTransparency=1,
RichText=true,
TextWrapped=true,
})
end

local ax=ac("Frame",{
Size=UDim2.new(1,0,0,42),
BackgroundTransparency=1,
},{
ac("Frame",{
BackgroundTransparency=1,
AutomaticSize="X",
Size=UDim2.new(0,0,1,0),
},{
ac("UIListLayout",{
Padding=UDim.new(0,9),
FillDirection="Horizontal",
}),
}),
})

local ay
if ag.KeySystem.Thumbnail and ag.KeySystem.Thumbnail.Image then
local az
if ag.KeySystem.Thumbnail.Title then
az=ac("TextLabel",{
Text=ag.KeySystem.Thumbnail.Title,
ThemeTag={
TextColor3="Text",
},
TextSize=18,
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
BackgroundTransparency=1,
AutomaticSize="XY",
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
})
end
ay=ac("ImageLabel",{
Image=ag.KeySystem.Thumbnail.Image,
BackgroundTransparency=1,
Size=UDim2.new(0,ao,1,-12),
Position=UDim2.new(0,6,0,6),
Parent=al.UIElements.Main,
ScaleType="Crop",
},{
az,
ac("UICorner",{
CornerRadius=UDim.new(0,20),
}),
})
end

ac("Frame",{

Size=UDim2.new(1,ay and-ao or 0,1,0),
Position=UDim2.new(0,ay and ao or 0,0,0),
BackgroundTransparency=1,
Parent=al.UIElements.Main,
},{
ac("Frame",{

Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
},{
ac("UIListLayout",{
Padding=UDim.new(0,18),
FillDirection="Vertical",
}),
au,
aw,
av,
ax,
ac("UIPadding",{
PaddingTop=UDim.new(0,16),
PaddingLeft=UDim.new(0,16),
PaddingRight=UDim.new(0,16),
PaddingBottom=UDim.new(0,16),
}),
}),
})





local az=ae("Exit","log-out",function()
al:Close()()
end,"Tertiary",ax.Frame)

if ay then
az.Parent=ay
az.Size=UDim2.new(0,0,0,42)
az.Position=UDim2.new(0,10,1,-10)
az.AnchorPoint=Vector2.new(0,1)
end

if ag.KeySystem.URL then
ae("Get key","key",function()
setclipboard(ag.KeySystem.URL)
end,"Secondary",ax.Frame)
end

if ag.KeySystem.API then








local aA=240
local aB=false
local b=ae("Get key","key",nil,"Secondary",ax.Frame)

local d=ab.NewRoundFrame(99,"Squircle",{
Size=UDim2.new(0,1,1,0),
ThemeTag={
ImageColor3="Text",
},
ImageTransparency=0.9,
})

ac("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(0,0,1,0),
AutomaticSize="X",
Parent=b.Frame,
},{
d,
ac("UIPadding",{
PaddingLeft=UDim.new(0,5),
PaddingRight=UDim.new(0,5),
}),
})

local f=ab.Image("chevron-down","chevron-down",0,"Temp","KeySystem",true)

f.Size=UDim2.new(1,0,1,0)

ac("Frame",{
Size=UDim2.new(0,21,0,21),
Parent=b.Frame,
BackgroundTransparency=1,
},{
f,
})

local g=ab.NewRoundFrame(15,"Squircle",{
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
ThemeTag={
ImageColor3="Background",
},
},{
ac("UIPadding",{
PaddingTop=UDim.new(0,5),
PaddingLeft=UDim.new(0,5),
PaddingRight=UDim.new(0,5),
PaddingBottom=UDim.new(0,5),
}),
ac("UIListLayout",{
FillDirection="Vertical",
Padding=UDim.new(0,5),
}),
})

local h=ac("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(0,aA,0,0),
ClipsDescendants=true,
AnchorPoint=Vector2.new(1,0),
Parent=b,
Position=UDim2.new(1,0,1,15),
},{
g,
})

ac("TextLabel",{
Text="Select Service",
BackgroundTransparency=1,
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
ThemeTag={TextColor3="Text"},
TextTransparency=0.2,
TextSize=16,
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
TextWrapped=true,
TextXAlignment="Left",
Parent=g,
},{
ac("UIPadding",{
PaddingTop=UDim.new(0,10),
PaddingLeft=UDim.new(0,10),
PaddingRight=UDim.new(0,10),
PaddingBottom=UDim.new(0,10),
}),
})

for i,l in next,ag.KeySystem.API do
local m=ag.WindUI.Services[l.Type]
if m then
local p={}
for r,u in next,m.Args do
table.insert(p,l[u])
end

local r=m.New(table.unpack(p))
r.Type=l.Type
table.insert(am,r)

local u=ab.Image(
l.Icon or m.Icon or Icons[l.Type]or"user",
l.Icon or m.Icon or Icons[l.Type]or"user",
0,
"Temp",
"KeySystem",
true
)
u.Size=UDim2.new(0,24,0,24)

local v=ab.NewRoundFrame(10,"Squircle",{
Size=UDim2.new(1,0,0,0),
ThemeTag={ImageColor3="Text"},
ImageTransparency=1,
Parent=g,
AutomaticSize="Y",
},{
ac("UIListLayout",{
FillDirection="Horizontal",
Padding=UDim.new(0,10),
VerticalAlignment="Center",
}),
u,
ac("UIPadding",{
PaddingTop=UDim.new(0,10),
PaddingLeft=UDim.new(0,10),
PaddingRight=UDim.new(0,10),
PaddingBottom=UDim.new(0,10),
}),
ac("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(1,-34,0,0),
AutomaticSize="Y",
},{
ac("UIListLayout",{
FillDirection="Vertical",
Padding=UDim.new(0,5),
HorizontalAlignment="Center",
}),
ac("TextLabel",{
Text=l.Title or m.Name,
BackgroundTransparency=1,
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
ThemeTag={TextColor3="Text"},
TextTransparency=0.05,
TextSize=18,
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
TextWrapped=true,
TextXAlignment="Left",
}),
ac("TextLabel",{
Text=l.Desc or"",
BackgroundTransparency=1,
FontFace=Font.new(ab.Font,Enum.FontWeight.Regular),
ThemeTag={TextColor3="Text"},
TextTransparency=0.2,
TextSize=16,
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
TextWrapped=true,
Visible=l.Desc and true or false,
TextXAlignment="Left",
}),
}),
},true)

ab.AddSignal(v.MouseEnter,function()
ad(v,0.08,{ImageTransparency=0.95}):Play()
end)
ab.AddSignal(v.InputEnded,function()
ad(v,0.08,{ImageTransparency=1}):Play()
end)
ab.AddSignal(v.MouseButton1Click,function()
r.Copy()
ag.WindUI:Notify{
Title="Key System",
Content="Key link copied to clipboard.",
Image="key",
}
end)
end
end

ab.AddSignal(b.MouseButton1Click,function()
if not aB then
ad(
h,
0.3,
{Size=UDim2.new(0,aA,0,g.AbsoluteSize.Y+1)},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
ad(f,0.3,{Rotation=180},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
else
ad(
h,
0.25,
{Size=UDim2.new(0,aA,0,0)},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
ad(f,0.25,{Rotation=0},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end
aB=not aB
end)
end

local function handleSuccess(aA)
al:Close()()
writefile((ag.Folder or"Temp").."/"..ah..".key",tostring(aA))
task.wait(0.4)
ai(true)
end

local aA=ae("Submit","arrow-right",function()
local aA=tostring(an or"empty")local aB=
ag.Folder or ag.Title

if ag.KeySystem.KeyValidator then
local b=ag.KeySystem.KeyValidator(aA)

if b then
if ag.KeySystem.SaveKey then
handleSuccess(aA)
else
al:Close()()
task.wait(0.4)
ai(true)
end
else
ag.WindUI:Notify{
Title="Key System. Error",
Content="Invalid key.",
Icon="triangle-alert",
}
end
elseif not ag.KeySystem.API then
local b=type(ag.KeySystem.Key)=="table"and table.find(ag.KeySystem.Key,aA)
or ag.KeySystem.Key==aA

if b then
if ag.KeySystem.SaveKey then
handleSuccess(aA)
else
al:Close()()
task.wait(0.4)
ai(true)
end
end
else
local b,d
for f,g in next,am do
local h,i=g.Verify(aA)
if h then
b,d=true,i
break
end
d=i
end

if b then
handleSuccess(aA)
else
ag.WindUI:Notify{
Title="Key System. Error",
Content=d,
Icon="triangle-alert",
}
end
end
end,"Primary",ax)

aA.AnchorPoint=Vector2.new(1,0.5)
aA.Position=UDim2.new(1,0,0.5,0)










al:Open()
end

return aa end function a.q()




local aa=(cloneref or clonereference or function(aa)return aa end)


local function map(ab,ac,ad,ae,af)
return(ab-ac)*(af-ae)/(ad-ac)+ae
end

local function viewportPointToWorld(ab,ac)
local ad=aa(game:GetService"Workspace").CurrentCamera:ScreenPointToRay(ab.X,ab.Y)
return ad.Origin+ad.Direction*ac
end

local function getOffset()
local ab=aa(game:GetService"Workspace").CurrentCamera.ViewportSize.Y
return map(ab,0,2560,8,56)
end

return{viewportPointToWorld,getOffset}end function a.r()



local aa=(cloneref or clonereference or function(aa)return aa end)


local ab=a.load'd'
local ac=ab.New


local ad,ae=unpack(a.load'q')
local af=Instance.new("Folder",aa(game:GetService"Workspace").CurrentCamera)


local function createAcrylic()
local ag=ac("Part",{
Name="Body",
Color=Color3.new(0,0,0),
Material=Enum.Material.Glass,
Size=Vector3.new(1,1,0),
Anchored=true,
CanCollide=false,
Locked=true,
CastShadow=false,
Transparency=0.98,
},{
ac("SpecialMesh",{
MeshType=Enum.MeshType.Brick,
Offset=Vector3.new(0,0,-1E-6),
}),
})

return ag
end


local function createAcrylicBlur(ag)
local ah={}

ag=ag or 0.001
local ai={
topLeft=Vector2.new(),
topRight=Vector2.new(),
bottomRight=Vector2.new(),
}
local aj=createAcrylic()
aj.Parent=af

local function updatePositions(ak,al)
ai.topLeft=al
ai.topRight=al+Vector2.new(ak.X,0)
ai.bottomRight=al+ak
end

local function render()
local ak=aa(game:GetService"Workspace").CurrentCamera
if ak then
ak=ak.CFrame
end
local al=ak
if not al then
al=CFrame.new()
end

local am=al
local an=ai.topLeft
local ao=ai.topRight
local ap=ai.bottomRight

local aq=ad(an,ag)
local ar=ad(ao,ag)
local as=ad(ap,ag)

local at=(ar-aq).Magnitude
local au=(ar-as).Magnitude

aj.CFrame=
CFrame.fromMatrix((aq+as)/2,am.XVector,am.YVector,am.ZVector)
aj.Mesh.Scale=Vector3.new(at,au,0)
end

local function onChange(ak)
local al=ae()
local am=ak.AbsoluteSize-Vector2.new(al,al)
local an=ak.AbsolutePosition+Vector2.new(al/2,al/2)

updatePositions(am,an)
task.spawn(render)
end

local function renderOnChange()
local ak=aa(game:GetService"Workspace").CurrentCamera
if not ak then
return
end

table.insert(ah,ak:GetPropertyChangedSignal"CFrame":Connect(render))
table.insert(ah,ak:GetPropertyChangedSignal"ViewportSize":Connect(render))
table.insert(ah,ak:GetPropertyChangedSignal"FieldOfView":Connect(render))
task.spawn(render)
end

aj.Destroying:Connect(function()
for ak,al in ah do
pcall(function()
al:Disconnect()
end)
end
end)

renderOnChange()

return onChange,aj
end

return function(ag)
local ah={}
local ai,aj=createAcrylicBlur(ag)

local ak=ac("Frame",{
BackgroundTransparency=1,
Size=UDim2.fromScale(1,1),
})

ab.AddSignal(ak:GetPropertyChangedSignal"AbsolutePosition",function()
ai(ak)
end)

ab.AddSignal(ak:GetPropertyChangedSignal"AbsoluteSize",function()
ai(ak)
end)

ah.AddParent=function(al)
ab.AddSignal(al:GetPropertyChangedSignal"Visible",function()

end)
end

ah.SetVisibility=function(al)
aj.Transparency=al and 0.98 or 1
end

ah.Frame=ak
ah.Model=aj

return ah
end end function a.s()


local aa=a.load'd'
local ab=a.load'r'

local ac=aa.New

return function(ad)
local ae={}

ae.Frame=ac("Frame",{
Size=UDim2.fromScale(1,1),
BackgroundTransparency=1,
BackgroundColor3=Color3.fromRGB(255,255,255),
BorderSizePixel=0,
},{












ac("UICorner",{
CornerRadius=UDim.new(0,8),
}),

ac("Frame",{
BackgroundTransparency=1,
Size=UDim2.fromScale(1,1),
Name="Background",
ThemeTag={
BackgroundColor3="AcrylicMain",
},
},{
ac("UICorner",{
CornerRadius=UDim.new(0,8),
}),
}),

ac("Frame",{
BackgroundColor3=Color3.fromRGB(255,255,255),
BackgroundTransparency=1,
Size=UDim2.fromScale(1,1),
},{










}),

ac("ImageLabel",{
Image="rbxassetid://9968344105",
ImageTransparency=0.98,
ScaleType=Enum.ScaleType.Tile,
TileSize=UDim2.new(0,128,0,128),
Size=UDim2.fromScale(1,1),
BackgroundTransparency=1,
},{
ac("UICorner",{
CornerRadius=UDim.new(0,8),
}),
}),

ac("ImageLabel",{
Image="rbxassetid://9968344227",
ImageTransparency=0.9,
ScaleType=Enum.ScaleType.Tile,
TileSize=UDim2.new(0,128,0,128),
Size=UDim2.fromScale(1,1),
BackgroundTransparency=1,
ThemeTag={
ImageTransparency="AcrylicNoise",
},
},{
ac("UICorner",{
CornerRadius=UDim.new(0,8),
}),
}),

ac("Frame",{
BackgroundTransparency=1,
Size=UDim2.fromScale(1,1),
ZIndex=2,
},{










}),
})


local af

task.wait()
if ad.UseAcrylic then
af=ab()

af.Frame.Parent=ae.Frame
ae.Model=af.Model
ae.AddParent=af.AddParent
ae.SetVisibility=af.SetVisibility
end

return ae,af
end end function a.t()



local aa=(cloneref or clonereference or function(aa)return aa end)


local ab={
AcrylicBlur=a.load'r',

AcrylicPaint=a.load's',
}

function ab.init()
local ac=Instance.new"DepthOfFieldEffect"
ac.FarIntensity=0
ac.InFocusRadius=0.1
ac.NearIntensity=1

local ad={}

function ab.Enable()
for ae,af in pairs(ad)do
af.Enabled=false
end
ac.Parent=aa(game:GetService"Lighting")
end

function ab.Disable()
for ae,af in pairs(ad)do
af.Enabled=af.enabled
end
ac.Parent=nil
end

local function registerDefaults()
local function register(ae)
if ae:IsA"DepthOfFieldEffect"then
ad[ae]={enabled=ae.Enabled}
end
end

for ae,af in pairs(aa(game:GetService"Lighting"):GetChildren())do
register(af)
end

if aa(game:GetService"Workspace").CurrentCamera then
for ae,af in pairs(aa(game:GetService"Workspace").CurrentCamera:GetChildren())do
register(af)
end
end
end

registerDefaults()
ab.Enable()
end

return ab end function a.u()

local aa={}

local ab=a.load'd'
local ac=ab.New local ad=
ab.Tween


function aa.new(ae,af)
local ag={
Title=ae.Title or"Dialog",
Content=ae.Content,
Icon=ae.Icon,
IconThemed=ae.IconThemed,
Thumbnail=ae.Thumbnail,
Buttons=ae.Buttons,

IconSize=22,
}

local ah=a.load'o'
local ai=ah.Create(true,"Popup",ae.WindUI.Window,ae.WindUI,af)

local aj=200

local ak=430
if ag.Thumbnail and ag.Thumbnail.Image then
ak=430+(aj/2)
end

ai.UIElements.Main.AutomaticSize="Y"
ai.UIElements.Main.Size=UDim2.new(0,ak,0,0)



local al

if ag.Icon then
al=ab.Image(
ag.Icon,
ag.Title..":"..ag.Icon,
0,
ae.WindUI.Window,
"Popup",
true,
ae.IconThemed,
"PopupIcon"
)
al.Size=UDim2.new(0,ag.IconSize,0,ag.IconSize)
al.LayoutOrder=-1
end


local am=ac("TextLabel",{
AutomaticSize="Y",
BackgroundTransparency=1,
Text=ag.Title,
TextXAlignment="Left",
FontFace=Font.new(ab.Font,Enum.FontWeight.SemiBold),
ThemeTag={
TextColor3="PopupTitle",
},
TextSize=20,
TextWrapped=true,
Size=UDim2.new(1,al and-ag.IconSize-14 or 0,0,0)
})

local an=ac("Frame",{
BackgroundTransparency=1,
AutomaticSize="XY",
},{
ac("UIListLayout",{
Padding=UDim.new(0,14),
FillDirection="Horizontal",
VerticalAlignment="Center"
}),
al,am
})

local ao=ac("Frame",{
AutomaticSize="Y",
Size=UDim2.new(1,0,0,0),
BackgroundTransparency=1,
},{





an,
})

local ap
if ag.Content and ag.Content~=""then
ap=ac("TextLabel",{
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
TextXAlignment="Left",
Text=ag.Content,
TextSize=18,
TextTransparency=.2,
ThemeTag={
TextColor3="PopupContent",
},
BackgroundTransparency=1,
RichText=true,
TextWrapped=true,
})
end

local aq=ac("Frame",{
Size=UDim2.new(1,0,0,42),
BackgroundTransparency=1,
},{
ac("UIListLayout",{
Padding=UDim.new(0,9),
FillDirection="Horizontal",
HorizontalAlignment="Right"
})
})

local ar
if ag.Thumbnail and ag.Thumbnail.Image then
local as
if ag.Thumbnail.Title then
as=ac("TextLabel",{
Text=ag.Thumbnail.Title,
ThemeTag={
TextColor3="Text",
},
TextSize=18,
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
BackgroundTransparency=1,
AutomaticSize="XY",
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
})
end
ar=ac("ImageLabel",{
Image=ag.Thumbnail.Image,
BackgroundTransparency=1,
Size=UDim2.new(0,aj,1,0),
Parent=ai.UIElements.Main,
ScaleType="Crop"
},{
as,
ac("UICorner",{
CornerRadius=UDim.new(0,0),
})
})
end

ac("Frame",{

Size=UDim2.new(1,ar and-aj or 0,1,0),
Position=UDim2.new(0,ar and aj or 0,0,0),
BackgroundTransparency=1,
Parent=ai.UIElements.Main
},{
ac("Frame",{

Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
},{
ac("UIListLayout",{
Padding=UDim.new(0,18),
FillDirection="Vertical",
}),
ao,
ap,
aq,
ac("UIPadding",{
PaddingTop=UDim.new(0,16),
PaddingLeft=UDim.new(0,16),
PaddingRight=UDim.new(0,16),
PaddingBottom=UDim.new(0,16),
})
}),
})

local as=a.load'm'.New

for at,au in next,ag.Buttons do
as(au.Title,au.Icon,au.Callback,au.Variant,aq,ai)
end

ai:Open()


return ag
end

return aa end function a.v()
return function(aa,ab)
return{
Dark={
Name="Dark",

Accent=Color3.fromHex"#18181b",
Dialog=Color3.fromHex"#1a1a1a",
Outline=Color3.fromHex"#FFFFFF",
Text=Color3.fromHex"#FFFFFF",
Placeholder=Color3.fromHex"#a1a1a1",
Background=Color3.fromHex"#101010",
Button=Color3.fromHex"#52525b",
Icon=Color3.fromHex"#a1a1aa",
Toggle=Color3.fromHex"#33C759",
Slider=Color3.fromHex"#0091FF",
Checkbox=Color3.fromHex"#0091FF",

PanelBackground=Color3.fromHex"#FFFFFF",
PanelBackgroundTransparency=0.95,

SliderIcon=Color3.fromHex"#908F95",
Primary=Color3.fromHex"#0091FF",


LabelBackground=Color3.fromHex"#000000",
LabelBackgroundTransparency=0.83,

ElementBackground=Color3.fromHex"#2A2A2C",
ElementBackgroundTransparency=0,
},

Light={
Name="Light",

Accent=Color3.fromHex"#efefef",
Dialog=Color3.fromHex"#f4f4f5",
Outline=Color3.fromHex"#ffffff",
Text=Color3.fromHex"#000000",
Placeholder=Color3.fromHex"#555555",
Background=Color3.fromHex"#FFFFFF",
Button=Color3.fromHex"#18181b",
Icon=Color3.fromHex"#52525b",
Toggle=Color3.fromHex"#33C759",
Slider=Color3.fromHex"#0091FF",
Checkbox=Color3.fromHex"#0091FF",

DropdownTabBackground=Color3.fromHex"#bebebe",
DropdownBackground=Color3.fromHex"#ffffff",

TabBackground=Color3.fromHex"#ffffff",
TabBackgroundHover=Color3.fromHex"#f3f3f3",
TabBackgroundHoverTransparency=0,
TabBackgroundActive=Color3.fromHex"#efefef",
TabBackgroundActiveTransparency=0,

PanelBackground=Color3.fromHex"#efefef",
PanelBackgroundTransparency=0,

LabelBackground=Color3.fromHex"#efefef",
LabelBackgroundTransparency=0,

ElementBackground=Color3.fromHex"#ffffff",
ElementBackgroundTransparency=0,
},

Rose={
Name="Rose",

Accent=Color3.fromHex"#be185d",
Dialog=Color3.fromHex"#4c0519",

Text=Color3.fromHex"#fdf2f8",
Placeholder=Color3.fromHex"#d67aa6",
Background=Color3.fromHex"#1f0308",
Button=Color3.fromHex"#e95f74",
Icon=Color3.fromHex"#fb7185",

ElementBackground=Color3.fromHex"#381E23",
ElementBackgroundTransparency=0,
},

Plant={
Name="Plant",

Accent=Color3.fromHex"#166534",
Dialog=Color3.fromHex"#052e16",

Text=Color3.fromHex"#f0fdf4",
Placeholder=Color3.fromHex"#4fbf7a",
Background=Color3.fromHex"#0a1b0f",
Button=Color3.fromHex"#16a34a",
Icon=Color3.fromHex"#4ade80",

ElementBackground=Color3.fromHex"#28342A",
ElementBackgroundTransparency=0,
},

Red={
Name="Red",

Accent=Color3.fromHex"#991b1b",
Dialog=Color3.fromHex"#450a0a",

Text=Color3.fromHex"#fef2f2",
Placeholder=Color3.fromHex"#d95353",
Background=Color3.fromHex"#1c0606",
Button=Color3.fromHex"#dc2626",
Icon=Color3.fromHex"#ef4444",

ElementBackground=Color3.fromHex"#322221",
ElementBackgroundTransparency=0,
},

Indigo={
Name="Indigo",

Accent=Color3.fromHex"#3730a3",
Dialog=Color3.fromHex"#1e1b4b",

Text=Color3.fromHex"#f1f5f9",
Placeholder=Color3.fromHex"#7078d9",
Background=Color3.fromHex"#0f0a2e",
Button=Color3.fromHex"#4f46e5",
Icon=Color3.fromHex"#6366f1",

ElementBackground=Color3.fromHex"#282543",
ElementBackgroundTransparency=0,
},

Sky={
Name="Sky",

Accent=Color3.fromHex"#00d4ff",
Dialog=Color3.fromHex"#0a4d66",

Text=Color3.fromHex"#e6f7ff",
Placeholder=Color3.fromHex"#66b3cc",
Background=Color3.fromHex"#051a26",
Button=Color3.fromHex"#00a8cc",
Icon=Color3.fromHex"#2db8d9",

Toggle=Color3.fromHex"#00d9d9",
Slider=Color3.fromHex"#00d4ff",
Checkbox=Color3.fromHex"#00d4ff",

PanelBackground=Color3.fromHex"#0d3a47",
PanelBackgroundTransparency=0.8,

ElementBackground=Color3.fromHex"#172E3B",
ElementBackgroundTransparency=0,
},

Violet={
Name="Violet",

Accent=Color3.fromHex"#6d28d9",
Dialog=Color3.fromHex"#3c1361",

Text=Color3.fromHex"#faf5ff",
Placeholder=Color3.fromHex"#8f7ee0",
Background=Color3.fromHex"#1e0a3e",
Button=Color3.fromHex"#7c3aed",
Icon=Color3.fromHex"#8b5cf6",

ElementBackground=Color3.fromHex"#342650",
ElementBackgroundTransparency=0,
},

Amber={
Name="Amber",

Accent=aa:Gradient({
["0"]={Color=Color3.fromHex"#b45309",Transparency=0},
["100"]={Color=Color3.fromHex"#d97706",Transparency=0},
},{Rotation=45}),

Dialog=aa:Gradient({
["0"]={Color=Color3.fromHex"#451a03",Transparency=0},
["100"]={Color=Color3.fromHex"#6b2e05",Transparency=0},
},{Rotation=90}),






Text=aa:Gradient({
["0"]={Color=Color3.fromHex"#fffbeb",Transparency=0},
["100"]={Color=Color3.fromHex"#fff7ed",Transparency=0},
},{Rotation=45}),

Placeholder=aa:Gradient({
["0"]={Color=Color3.fromHex"#d1a326",Transparency=0},
["100"]={Color=Color3.fromHex"#fbbf24",Transparency=0},
},{Rotation=45}),

Background=aa:Gradient({
["0"]={Color=Color3.fromHex"#1c1003",Transparency=0},
["100"]={Color=Color3.fromHex"#3f210d",Transparency=0},
},{Rotation=90}),

Button=aa:Gradient({
["0"]={Color=Color3.fromHex"#d97706",Transparency=0},
["100"]={Color=Color3.fromHex"#f59e0b",Transparency=0},
},{Rotation=45}),

Icon=Color3.fromHex"#f59e0b",

Toggle=aa:Gradient({
["0"]={Color=Color3.fromHex"#d97706",Transparency=0},
["100"]={Color=Color3.fromHex"#f59e0b",Transparency=0},
},{Rotation=45}),

Slider=Color3.fromHex"#d97706",

Checkbox=aa:Gradient({
["0"]={Color=Color3.fromHex"#d97706",Transparency=0},
["100"]={Color=Color3.fromHex"#fbbf24",Transparency=0},
},{Rotation=45}),

PanelBackground=Color3.fromHex"#FFFFFF",
PanelBackgroundTransparency=0.95,

ElementBackground=Color3.fromHex"#3A2E22",
ElementBackgroundTransparency=0,
},

Emerald={
Name="Emerald",

Accent=Color3.fromHex"#047857",
Dialog=Color3.fromHex"#022c22",

Text=Color3.fromHex"#ecfdf5",
Placeholder=Color3.fromHex"#3fbf8f",
Background=Color3.fromHex"#011411",
Button=Color3.fromHex"#059669",
Icon=Color3.fromHex"#10b981",

ElementBackground=Color3.fromHex"#202E2A",
ElementBackgroundTransparency=0,
},

Midnight={
Name="Midnight",

Accent=Color3.fromHex"#1e3a8a",
Dialog=Color3.fromHex"#0c1e42",

Text=Color3.fromHex"#dbeafe",
Placeholder=Color3.fromHex"#2f74d1",
Background=Color3.fromHex"#0a0f1e",
Button=Color3.fromHex"#2563eb",
Primary=Color3.fromHex"#2563eb",
Icon=Color3.fromHex"#5591f4",

ElementBackground=Color3.fromHex"#242836",
ElementBackgroundTransparency=0,
},

Crimson={
Name="Crimson",

Accent=Color3.fromHex"#b91c1c",
Dialog=Color3.fromHex"#450a0a",

Text=Color3.fromHex"#fef2f2",
Placeholder=Color3.fromHex"#6f757b",
Background=Color3.fromHex"#0c0404",
Button=Color3.fromHex"#991b1b",
Icon=Color3.fromHex"#dc2626",

ElementBackground=Color3.fromHex"#251F1F",
ElementBackgroundTransparency=0,
},

MonokaiPro={
Name="Monokai Pro",

Accent=Color3.fromHex"#fc9867",
Dialog=Color3.fromHex"#1e1e1e",

Text=Color3.fromHex"#fcfcfa",
Placeholder=Color3.fromHex"#afafaf",
Background=Color3.fromHex"#191622",
Button=Color3.fromHex"#ab9df2",
Icon=Color3.fromHex"#a9dc76",

ElementBackground=Color3.fromHex"#323039",
ElementBackgroundTransparency=0,

Metadata={
PullRequest=23,
},
},

CottonCandy={
Name="Cotton Candy",

Accent=Color3.fromHex"#ec4899",
Dialog=Color3.fromHex"#2d1b3d",

Text=Color3.fromHex"#fdf2f8",
Placeholder=Color3.fromHex"#8a5fd3",
Background=Color3.fromHex"#1a0b2e",
Button=Color3.fromHex"#d946ef",
Slider=Color3.fromHex"#d946ef",
Icon=Color3.fromHex"#06b6d4",

ElementBackground=Color3.fromHex"#312643",
ElementBackgroundTransparency=0,
},

Mellowsi={
Name="Mellowsi",

Accent=Color3.fromHex"#342A1E",
Dialog=Color3.fromHex"#291C13",

Text=Color3.fromHex"#F5EBDD",
Placeholder=Color3.fromHex"#9C8A73",
Background=Color3.fromHex"#1C1002",
Button=Color3.fromHex"#342A1E",
Icon=Color3.fromHex"#C9B79C",

Toggle=Color3.fromHex"#a9873f",
Slider=Color3.fromHex"#C9A24D",
Checkbox=Color3.fromHex"#C9A24D",

ElementBackground=Color3.fromHex"#33291E",
ElementBackgroundTransparency=0,

Metadata={
PullRequest=52,
},
},

Rainbow={
Name="Rainbow",

Accent=aa:Gradient({
["0"]={Color=Color3.fromHex"#00ff41",Transparency=0},
["33"]={Color=Color3.fromHex"#00ffff",Transparency=0},
["66"]={Color=Color3.fromHex"#0080ff",Transparency=0},
["100"]={Color=Color3.fromHex"#8000ff",Transparency=0},
},{Rotation=45}),

Dialog=aa:Gradient({
["0"]={Color=Color3.fromHex"#ff0080",Transparency=0},
["25"]={Color=Color3.fromHex"#8000ff",Transparency=0},
["50"]={Color=Color3.fromHex"#0080ff",Transparency=0},
["75"]={Color=Color3.fromHex"#00ff80",Transparency=0},
["100"]={Color=Color3.fromHex"#ff8000",Transparency=0},
},{Rotation=135}),


Text=Color3.fromHex"#ffffff",
Placeholder=Color3.fromHex"#00ff80",

Background=aa:Gradient({
["0"]={Color=Color3.fromHex"#ff0040",Transparency=0},
["20"]={Color=Color3.fromHex"#ff4000",Transparency=0},
["40"]={Color=Color3.fromHex"#ffff00",Transparency=0},
["60"]={Color=Color3.fromHex"#00ff40",Transparency=0},
["80"]={Color=Color3.fromHex"#0040ff",Transparency=0},
["100"]={Color=Color3.fromHex"#4000ff",Transparency=0},
},{Rotation=90}),

Button=aa:Gradient({
["0"]={Color=Color3.fromHex"#ff0080",Transparency=0},
["25"]={Color=Color3.fromHex"#ff8000",Transparency=0},
["50"]={Color=Color3.fromHex"#ffff00",Transparency=0},
["75"]={Color=Color3.fromHex"#80ff00",Transparency=0},
["100"]={Color=Color3.fromHex"#00ffff",Transparency=0},
},{Rotation=60}),

Icon=Color3.fromHex"#ffffff",
},
}
end end function a.w()

local aa={}

local ab=a.load'd'
local ac=ab.New local ad=
ab.Tween

function aa.New(ae,af,ag,ah,ai,aj)
local ak=ai or 10
local al
if af and af~=""then
al=ac("ImageLabel",{
Image=ab.Icon(af)[1],
ImageRectSize=ab.Icon(af)[2].ImageRectSize,
ImageRectOffset=ab.Icon(af)[2].ImageRectPosition,
Size=UDim2.new(0,21,0,21),
BackgroundTransparency=1,
ThemeTag={
ImageColor3="Icon",
},
})
end

local am=ac("TextLabel",{
BackgroundTransparency=1,
TextSize=17,
FontFace=Font.new(ab.Font,Enum.FontWeight.Regular),
Size=UDim2.new(1,al and-29 or 0,1,0),
TextXAlignment="Left",
ThemeTag={
TextColor3=ah and"Placeholder"or"Text",
},
Text=ae,
})

local an=ac("TextButton",{
Size=UDim2.new(1,0,0,42),
Parent=ag,
BackgroundTransparency=1,
Text="",
},{
ac("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
},{
ab.NewRoundFrame(ak,"Squircle",{
ThemeTag={
ImageColor3="Placeholder",
},
Size=UDim2.new(1,0,1,0),
ImageTransparency=0.85,
}),
not aj and ab.NewRoundFrame(ak,"SquircleGlass",{
ThemeTag={
ImageColor3="Outline",
},
Size=UDim2.new(1,1,1,1),
ImageTransparency=0.9,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
})or nil,
ab.NewRoundFrame(ak,"Squircle",{
Size=UDim2.new(1,0,1,0),
Name="Frame",
ThemeTag={
ImageColor3="LabelBackground",
ImageTransparency="LabelBackgroundTransparency",
},


},{
ac("UIPadding",{
PaddingLeft=UDim.new(0,12),
PaddingRight=UDim.new(0,12),
}),
ac("UIListLayout",{
FillDirection="Horizontal",
Padding=UDim.new(0,8),
VerticalAlignment="Center",
HorizontalAlignment="Left",
}),
al,
am,
}),
}),
})

return an
end

return aa end function a.x()

local aa={}

local ab=cloneref or clonereference or function(ab)
return ab
end
local ac=ab(game:GetService"UserInputService")

local ad=a.load'd'
local ae=ad.New

function aa.New(af,ag,ah,ai,aj)
local ak=ae("Frame",{
Size=UDim2.new(0,ai,1,0),
BackgroundTransparency=1,
Position=UDim2.new(1,0,0,0),
AnchorPoint=Vector2.new(1,0),
Parent=ag,
ZIndex=999,
Active=true,
})

local al=ad.NewRoundFrame(ai/2,"Squircle",{
Size=UDim2.new(1,0,0,0),
ImageTransparency=0.85,
ThemeTag={ImageColor3="Text"},
Parent=ak,
})

local am=ae("Frame",{
Size=UDim2.new(1,12,1,12),
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
BackgroundTransparency=1,
Active=true,
ZIndex=999,
Parent=al,
})

local an=ad:GenerateUniqueID()
local ao=false
local ap,aq

local function UpdateVisuals()
local ar=af.AbsoluteCanvasSize.Y
local as=af.AbsoluteWindowSize.Y

if ar<=as then
al.Visible=false
return
end

al.Visible=true

local at=math.clamp(as/ar,0.05,1)
al.Size=UDim2.new(1,0,at,0)

local au=ar-as
local av=1-at

if au>0 then
local aw=af.CanvasPosition.Y/au
al.Position=UDim2.new(0,0,math.clamp(aw*av,0,av),0)
else
al.Position=UDim2.new(0,0,0,0)
end
end

local function StopDrag()
if aj.CurrentInput==an then
aj.CurrentInput=nil
end
ao=false
af.ScrollingEnabled=true
if ap then
ap:Disconnect()
end
if aq then
aq:Disconnect()
end
end

ad.AddSignal(am.InputBegan,function(ar)
if
ar.UserInputType~=Enum.UserInputType.MouseButton1
and ar.UserInputType~=Enum.UserInputType.Touch
then
return
end
if ao then
return
end
if aj.CurrentInput and aj.CurrentInput~=an then
return
end

aj.CurrentInput=an

ao=true
af.ScrollingEnabled=false

local as=ar.Position.Y
local at=af.CanvasPosition.Y

ap=ac.InputChanged:Connect(function(au)
if
au.UserInputType==Enum.UserInputType.MouseMovement
or au.UserInputType==Enum.UserInputType.Touch
then
local av=au.Position.Y-as

local aw=af.AbsoluteCanvasSize.Y
local ax=af.AbsoluteWindowSize.Y
local ay=math.max(aw-ax,0)

local az=ak.AbsoluteSize.Y
local aA=al.AbsoluteSize.Y
local aB=math.max(az-aA,1)

local b=av*(ay/aB)

af.CanvasPosition=
Vector2.new(af.CanvasPosition.X,math.clamp(at+b,0,ay))
end
end)

aq=ac.InputEnded:Connect(function(au)
if au.UserInputType==ar.UserInputType then
if aj.CurrentInput and aj.CurrentInput~=an then
return
end

aj.CurrentInput=nil

StopDrag()
end
end)
end)

ad.AddSignal(af:GetPropertyChangedSignal"AbsoluteWindowSize",UpdateVisuals)
ad.AddSignal(af:GetPropertyChangedSignal"AbsoluteCanvasSize",UpdateVisuals)
ad.AddSignal(af:GetPropertyChangedSignal"CanvasPosition",UpdateVisuals)

UpdateVisuals()

return ak
end

return aa end function a.y()

local aa={}

local ab=a.load'd'
local ac=ab.New
local ad=ab.Tween

function aa.New(ae,af,ag)
local ah={
Title=af.Title or"Tag",
Icon=af.Icon,
Color=af.Color or Color3.fromHex"#315dff",
Radius=af.Radius or 999,
Border=af.Border or false,

TagFrame=nil,
Height=26,
Padding=10,
TextSize=14,
IconSize=16,
}

local ai
if ah.Icon then
ai=ab.Image(ah.Icon,ah.Icon,0,af.Window,"Tag",false)

ai.Size=UDim2.new(0,ah.IconSize,0,ah.IconSize)
ai.ImageLabel.ImageColor3=typeof(ah.Color)=="Color3"
and ab.GetTextColorForHSB(ah.Color)
or typeof(ah.Color)=="string"
and(ab.GetTextColorForHSB(ab.GetThemeProperty(ah.Color,ab.Theme)))
end

local aj=ac("TextLabel",{
BackgroundTransparency=1,
AutomaticSize="XY",
TextSize=ah.TextSize,
FontFace=Font.new(ab.Font,Enum.FontWeight.SemiBold),
Text=ah.Title,
TextColor3=typeof(ah.Color)=="Color3"and ab.GetTextColorForHSB(ah.Color)or typeof(
ah.Color
)=="string"and(ab.GetTextColorForHSB(ab.GetThemeProperty(ah.Color,ab.Theme))),
})

local ak

if typeof(ah.Color)=="table"then
ak=ac"UIGradient"
for al,am in next,ah.Color do
ak[al]=am
end

aj.TextColor3=ab.GetTextColorForHSB(ab.GetAverageColor(ak))
if ai then
ai.ImageLabel.ImageColor3=ab.GetTextColorForHSB(ab.GetAverageColor(ak))
end
end

local al=ab.NewRoundFrame(ah.Radius,"Squircle",{
AutomaticSize="X",
Size=UDim2.new(0,0,0,ah.Height),
Parent=ag,
ImageColor3=typeof(ah.Color)=="Color3"and ah.Color
or typeof(ah.Color)=="table"and Color3.new(1,1,1)
or nil,
ThemeTag=typeof(ah.Color)=="string"and{
ImageColor3=ah.Color,
},
},{
ak,
ab.NewRoundFrame(ah.Radius+1,"SquircleGlass",{
Size=UDim2.new(1,1,1,1),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
ThemeTag={
ImageColor3="White",
},
ImageTransparency=0.75,
}),
ac("Frame",{
Size=UDim2.new(0,0,1,0),
AutomaticSize="X",
Name="Content",
BackgroundTransparency=1,
},{
ai,
aj,
ac("UIPadding",{
PaddingLeft=UDim.new(0,ah.Padding),
PaddingRight=UDim.new(0,ah.Padding),
}),
ac("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
Padding=UDim.new(0,ah.Padding/1.5),
}),
}),
})

function ah.SetTitle(am,an)
ah.Title=an
aj.Text=an

return ah
end

function ah.SetColor(am,an)
ah.Color=an
if typeof(an)=="table"then
local ao=ab.GetAverageColor(an)
ad(aj,0.06,{TextColor3=ab.GetTextColorForHSB(ao)}):Play()
local ap=al:FindFirstChildOfClass"UIGradient"or ac("UIGradient",{Parent=al})
for aq,ar in next,an do
ap[aq]=ar
end
ad(al,0.06,{ImageColor3=Color3.new(1,1,1)}):Play()
else
if ak then
ak:Destroy()
end
ad(aj,0.06,{TextColor3=ab.GetTextColorForHSB(an)}):Play()
if ai then
ad(ai.ImageLabel,0.06,{ImageColor3=ab.GetTextColorForHSB(an)}):Play()
end
ad(al,0.06,{ImageColor3=an}):Play()
end

return ah
end

function ah.SetIcon(am,an)
ah.Icon=an

if an then
ai=ab.Image(an,an,0,af.Window,"Tag",false)

ai.Size=UDim2.new(0,ah.IconSize,0,ah.IconSize)
ai.Parent=al

if typeof(ah.Color)=="Color3"then
ai.ImageLabel.ImageColor3=ab.GetTextColorForHSB(ah.Color)
elseif typeof(ah.Color)=="table"then
ai.ImageLabel.ImageColor3=ab.GetTextColorForHSB(ab.GetAverageColor(ak))
end
else
if ai then
ai:Destroy()
ai=nil
end
end
return ah
end

function ah.Destroy(am)
al:Destroy()
return ah
end

ab:OnThemeChange(function(am,an)
aj.TextColor3=ab.GetTextColorForHSB(ab.GetThemeProperty(ah.Color,ab.Theme))
ai.ImageLabel.ImageColor3=
ab.GetTextColorForHSB(ab.GetThemeProperty(ah.Color,ab.Theme))
end)

return ah
end

return aa end function a.z()

local aa=(cloneref or clonereference or function(aa)return aa end)


local ab=aa(game:GetService"RunService")
local ac=aa(game:GetService"HttpService")

local ad

local ae
ae={
Folder=nil,
Path=nil,
Configs={},
Parser={
Colorpicker={
Save=function(af)
return{
__type=af.__type,
value=af.Default:ToHex(),
transparency=af.Transparency or nil,
}
end,
Load=function(af,ag)
if af and af.Update then
af:Update(Color3.fromHex(ag.value),ag.transparency or nil)
end
end
},
Dropdown={
Save=function(af)
return{
__type=af.__type,
value=af.Value,
}
end,
Load=function(af,ag)
if af and af.Select then
af:Select(ag.value)
end
end
},
Input={
Save=function(af)
return{
__type=af.__type,
value=af.Value,
}
end,
Load=function(af,ag)
if af and af.Set then
af:Set(ag.value)
end
end
},
Keybind={
Save=function(af)
return{
__type=af.__type,
value=af.Value,
}
end,
Load=function(af,ag)
if af and af.Set then
af:Set(ag.value)
end
end
},
Slider={
Save=function(af)
return{
__type=af.__type,
value=af.Value.Default,
}
end,
Load=function(af,ag)
if af and af.Set then
af:Set(tonumber(ag.value))
end
end
},
Toggle={
Save=function(af)
return{
__type=af.__type,
value=af.Value,
}
end,
Load=function(af,ag)
if af and af.Set then
af:Set(ag.value)
end
end
},
}
}

function ae.Init(af,ag)
if not ag.Folder then
warn"[ WindUI.ConfigManager ] Window.Folder is not specified."
return false
end
if ab:IsStudio()or not writefile then
warn"[ WindUI.ConfigManager ] The config system doesn't work in the studio."
return false
end

ad=ag
ae.Folder=ad.Folder
ae.Path="WindUI/"..tostring(ae.Folder).."/config/"

if not isfolder(ae.Path)then
makefolder(ae.Path)
end

local ah=ae:AllConfigs()

for ai,aj in next,ah do
if isfile and readfile and isfile(aj..".json")then
ae.Configs[aj]=readfile(aj..".json")
end
end

return ae
end

function ae.SetPath(af,ag)
if not ag then
warn"[ WindUI.ConfigManager ] Custom path is not specified."
return false
end

ae.Path=ag
if not ag:match"/$"then
ae.Path=ag.."/"
end

if not isfolder(ae.Path)then
makefolder(ae.Path)
end

return true
end

function ae.CreateConfig(af,ag,ah)
local ai={
Path=ae.Path..ag..".json",
Elements={},
CustomData={},
AutoLoad=ah or false,
Version=1.2,
}

if not ag then
return false,"No config file is selected"
end

function ai.SetAsCurrent(aj)
ad:SetCurrentConfig(ai)
end

function ai.Register(aj,ak,al)
ai.Elements[ak]=al
end

function ai.Set(aj,ak,al)
ai.CustomData[ak]=al
end

function ai.Get(aj,ak)
return ai.CustomData[ak]
end

function ai.SetAutoLoad(aj,ak)
ai.AutoLoad=ak
end

function ai.Save(aj)
if ad.PendingFlags then
for ak,al in next,ad.PendingFlags do
ai:Register(ak,al)
end
end

local ak={
__version=ai.Version,
__elements={},
__autoload=ai.AutoLoad,
__custom=ai.CustomData
}

for al,am in next,ai.Elements do
if ae.Parser[am.__type]then
ak.__elements[tostring(al)]=ae.Parser[am.__type].Save(am)
end
end

local al=ac:JSONEncode(ak)
if writefile then
writefile(ai.Path,al)
end

return ak
end

function ai.Load(aj)
if isfile and not isfile(ai.Path)then
return false,"Config file does not exist"
end

local ak,al=pcall(function()
local ak=readfile or function()
warn"[ WindUI.ConfigManager ] The config system doesn't work in the studio."
return nil
end
return ac:JSONDecode(ak(ai.Path))
end)

if not ak then
return false,"Failed to parse config file"
end

if not al.__version then
local am={
__version=ai.Version,
__elements=al,
__custom={}
}
al=am
end

if ad.PendingFlags then
for am,an in next,ad.PendingFlags do
ai:Register(am,an)
end
end

for am,an in next,(al.__elements or{})do
if ai.Elements[am]and ae.Parser[an.__type]then
task.spawn(function()
ae.Parser[an.__type].Load(ai.Elements[am],an)
end)
end
end

ai.CustomData=al.__custom or{}

return ai.CustomData
end

function ai.Delete(aj)
if not delfile then
return false,"delfile function is not available"
end

if not isfile(ai.Path)then
return false,"Config file does not exist"
end

local ak,al=pcall(function()
delfile(ai.Path)
end)

if not ak then
return false,"Failed to delete config file: "..tostring(al)
end

ae.Configs[ag]=nil

if ad.CurrentConfig==ai then
ad.CurrentConfig=nil
end

return true,"Config deleted successfully"
end

function ai.GetData(aj)
return{
elements=ai.Elements,
custom=ai.CustomData,
autoload=ai.AutoLoad
}
end


if isfile(ai.Path)then
local aj,ak=pcall(function()
return ac:JSONDecode(readfile(ai.Path))
end)

if aj and ak and ak.__autoload then
ai.AutoLoad=true

task.spawn(function()
task.wait(0.5)
local al,am=pcall(function()
return ai:Load()
end)
if al then
if ad.Debug then print("[ WindUI.ConfigManager ] AutoLoaded config: "..ag)end
else
warn("[ WindUI.ConfigManager ] Failed to AutoLoad config: "..ag.." - "..tostring(am))
end
end)
end
end


ai:SetAsCurrent()
ae.Configs[ag]=ai
return ai
end

function ae.Config(af,ag,ah)
return ae:CreateConfig(ag,ah)
end

function ae.GetAutoLoadConfigs(af)
local ag={}

for ah,ai in pairs(ae.Configs)do
if ai.AutoLoad then
table.insert(ag,ah)
end
end

return ag
end

function ae.DeleteConfig(af,ag)
if not delfile then
return false,"delfile function is not available"
end

local ah=ae.Path..ag..".json"

if not isfile(ah)then
return false,"Config file does not exist"
end

local ai,aj=pcall(function()
delfile(ah)
end)

if not ai then
return false,"Failed to delete config file: "..tostring(aj)
end

ae.Configs[ag]=nil

if ad.CurrentConfig and ad.CurrentConfig.Path==ah then
ad.CurrentConfig=nil
end

return true,"Config deleted successfully"
end

function ae.AllConfigs(af)
if not listfiles then return{}end

local ag={}
if not isfolder(ae.Path)then
makefolder(ae.Path)
return ag
end

for ah,ai in next,listfiles(ae.Path)do
local aj=ai:match"([^\\/]+)%.json$"
if aj then
table.insert(ag,aj)
end
end

return ag
end

function ae.GetConfig(af,ag)
return ae.Configs[ag]
end

return ae end function a.A()
local aa={}

local ab=a.load'd'
local ac=ab.New
local ad=ab.Tween


local ae=(cloneref or clonereference or function(ae)return ae end)


ae(game:GetService"UserInputService")


function aa.New(af)
local ag={
Button=nil
}

local ah













local ai=ac("TextLabel",{
Text=af.Title,
TextSize=17,
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
BackgroundTransparency=1,
AutomaticSize="XY",
})

local aj=ac("Frame",{
Size=UDim2.new(0,36,0,36),
BackgroundTransparency=1,
Name="Drag",
},{
ac("ImageLabel",{
Image=ab.Icon"move"[1],
ImageRectOffset=ab.Icon"move"[2].ImageRectPosition,
ImageRectSize=ab.Icon"move"[2].ImageRectSize,
Size=UDim2.new(0,18,0,18),
BackgroundTransparency=1,
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
ThemeTag={
ImageColor3="Icon",
},
ImageTransparency=.3,
})
})
local ak=ac("Frame",{
Size=UDim2.new(0,1,1,0),
Position=UDim2.new(0,36,0.5,0),
AnchorPoint=Vector2.new(0,0.5),
BackgroundColor3=Color3.new(1,1,1),
BackgroundTransparency=.9,
})

local al=ac("Frame",{
Size=UDim2.new(0,0,0,0),
Position=UDim2.new(0.5,0,0,28),
AnchorPoint=Vector2.new(0.5,0.5),
Parent=af.Parent,
BackgroundTransparency=1,
Active=true,
Visible=false,
})


local am=ac("UIScale",{
Scale=1,
})

local an=ac("Frame",{
Size=UDim2.new(0,0,0,44),
AutomaticSize="X",
Parent=al,
Active=false,
BackgroundTransparency=.25,
ZIndex=99,
BackgroundColor3=Color3.new(0,0,0),
},{
am,
ac("UICorner",{
CornerRadius=UDim.new(1,0)
}),
ac("UIStroke",{
Thickness=1,
ApplyStrokeMode="Border",
Color=Color3.new(1,1,1),
Transparency=0,
},{
ac("UIGradient",{
Color=ColorSequence.new(Color3.fromHex"40c9ff",Color3.fromHex"e81cff")
})
}),
aj,
ak,

ac("UIListLayout",{
Padding=UDim.new(0,4),
FillDirection="Horizontal",
VerticalAlignment="Center",
}),

ac("TextButton",{
AutomaticSize="XY",
Active=true,
BackgroundTransparency=1,
Size=UDim2.new(0,0,0,36),

BackgroundColor3=Color3.new(1,1,1),
},{
ac("UICorner",{
CornerRadius=UDim.new(1,-4)
}),
ah,
ac("UIListLayout",{
Padding=UDim.new(0,af.UIPadding),
FillDirection="Horizontal",
VerticalAlignment="Center",
}),
ai,
ac("UIPadding",{
PaddingLeft=UDim.new(0,11),
PaddingRight=UDim.new(0,11),
}),
}),
ac("UIPadding",{
PaddingLeft=UDim.new(0,4),
PaddingRight=UDim.new(0,4),
})
})

ag.Button=an



function ag.SetIcon(ao,ap)
if ah then
ah:Destroy()
end
if ap then
ah=ab.Image(
ap,
af.Title,
0,
af.Folder,
"OpenButton",
true,
af.IconThemed
)
ah.Size=UDim2.new(0,22,0,22)
ah.LayoutOrder=-1
ah.Parent=ag.Button.TextButton
end
end

if af.Icon then
ag:SetIcon(af.Icon)
end



ab.AddSignal(an:GetPropertyChangedSignal"AbsoluteSize",function()
al.Size=UDim2.new(
0,an.AbsoluteSize.X,
0,an.AbsoluteSize.Y
)
end)

ab.AddSignal(an.TextButton.MouseEnter,function()
ad(an.TextButton,.1,{BackgroundTransparency=.93}):Play()
end)
ab.AddSignal(an.TextButton.MouseLeave,function()
ad(an.TextButton,.1,{BackgroundTransparency=1}):Play()
end)

local ao=ab.Drag(al)


function ag.Visible(ap,aq)
al.Visible=aq
end

function ag.SetScale(ap,aq)
am.Scale=aq
end

function ag.Edit(ap,aq)
local ar={
Title=aq.Title,
Icon=aq.Icon,
Enabled=aq.Enabled,
Position=aq.Position,
OnlyIcon=aq.OnlyIcon or false,
Draggable=aq.Draggable or nil,
OnlyMobile=aq.OnlyMobile,
CornerRadius=aq.CornerRadius or UDim.new(1,0),
StrokeThickness=aq.StrokeThickness or 2,
Scale=aq.Scale or 1,
Color=aq.Color
or ColorSequence.new(Color3.fromHex"40c9ff",Color3.fromHex"e81cff"),
}



if ar.Enabled==false then
af.IsOpenButtonEnabled=false
end

if ar.OnlyMobile~=false then
ar.OnlyMobile=true
else
af.IsPC=false
end


if ar.Draggable==false and aj and ak then
aj.Visible=ar.Draggable
ak.Visible=ar.Draggable

if ao then
ao:Set(ar.Draggable)
end
end

if ar.Position and al then
al.Position=ar.Position
end

if ar.OnlyIcon==true and ai then
ai.Visible=false
an.TextButton.UIPadding.PaddingLeft=UDim.new(0,7)
an.TextButton.UIPadding.PaddingRight=UDim.new(0,7)
elseif ar.OnlyIcon==false then
ai.Visible=true
an.TextButton.UIPadding.PaddingLeft=UDim.new(0,11)
an.TextButton.UIPadding.PaddingRight=UDim.new(0,11)
end





if ai then
if ar.Title then
ai.Text=ar.Title
ab:ChangeTranslationKey(ai,ar.Title)
elseif ar.Title==nil then

end
end

if ar.Icon then
ag:SetIcon(ar.Icon)
end

an.UIStroke.UIGradient.Color=ar.Color
if Glow then
Glow.UIGradient.Color=ar.Color
end

an.UICorner.CornerRadius=ar.CornerRadius
an.TextButton.UICorner.CornerRadius=UDim.new(ar.CornerRadius.Scale,ar.CornerRadius.Offset-4)
an.UIStroke.Thickness=ar.StrokeThickness

ag:SetScale(ar.Scale)
end

return ag
end



return aa end function a.B()
local aa={}

local ab=a.load'd'
local ac=ab.New
local ad=ab.Tween


function aa.New(ae,af,ag,ah,ai,aj)
local ak={
Container=nil,
TooltipSize=16,

TooltipArrowSizeX=ai=="Small"and 16 or 24,
TooltipArrowSizeY=ai=="Small"and 6 or 9,

PaddingX=ai=="Small"and 12 or 14,
PaddingY=ai=="Small"and 7 or 9,

Radius=999,

TitleFrame=nil,
}

ah=ah or""
aj=aj~=false

local al=ac("TextLabel",{
AutomaticSize="XY",
TextWrapped=aj,
BackgroundTransparency=1,
FontFace=Font.new(ab.Font,Enum.FontWeight.Medium),
Text=ae,
TextSize=ai=="Small"and 15 or 17,
TextTransparency=1,
ThemeTag={
TextColor3="Tooltip"..ah.."Text",
}
})

ak.TitleFrame=al

local am=ac("UIScale",{
Scale=.9
})

local an=ac("Frame",{
AnchorPoint=Vector2.new(0.5,0),
AutomaticSize="XY",
BackgroundTransparency=1,
Parent=af,

Visible=false
},{
ac("UISizeConstraint",{
MaxSize=Vector2.new(400,math.huge)
}),
ac("Frame",{
AutomaticSize="XY",
BackgroundTransparency=1,
LayoutOrder=99,
Visible=ag,
Name="Arrow",
},{
ac("ImageLabel",{
Size=UDim2.new(0,ak.TooltipArrowSizeX,0,ak.TooltipArrowSizeY),
BackgroundTransparency=1,

Image="rbxassetid://105854070513330",
ThemeTag={
ImageColor3="Tooltip"..ah,
},
},{










}),
}),
ab.NewRoundFrame(ak.Radius,"Squircle",{
AutomaticSize="XY",
ThemeTag={
ImageColor3="Tooltip"..ah,
},
ImageTransparency=1,
Name="Background",
},{



ac("Frame",{



AutomaticSize="XY",
BackgroundTransparency=1,
},{
ac("UICorner",{
CornerRadius=UDim.new(0,16),
}),
ac("UIListLayout",{
Padding=UDim.new(0,12),
FillDirection="Horizontal",
VerticalAlignment="Center"
}),

al,
ac("UIPadding",{
PaddingTop=UDim.new(0,ak.PaddingY),
PaddingLeft=UDim.new(0,ak.PaddingX),
PaddingRight=UDim.new(0,ak.PaddingX),
PaddingBottom=UDim.new(0,ak.PaddingY),
}),
})
}),
am,
ac("UIListLayout",{
Padding=UDim.new(0,0),
FillDirection="Vertical",
VerticalAlignment="Center",
HorizontalAlignment="Center",
}),
})
ak.Container=an

function ak.Open(ao)
an.Visible=true


ad(an.Background,.2,{ImageTransparency=0},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
ad(an.Arrow.ImageLabel,.2,{ImageTransparency=0},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
ad(al,.2,{TextTransparency=0},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
ad(am,.22,{Scale=1},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end

function ak.Close(ao,ap)

ad(an.Background,.3,{ImageTransparency=1},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
ad(an.Arrow.ImageLabel,.2,{ImageTransparency=1},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
ad(al,.3,{TextTransparency=1},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
ad(am,.35,{Scale=.9},Enum.EasingStyle.Quint,Enum.EasingDirection.In):Play()

ap=ap~=false
if ap then
task.wait(.35)

an.Visible=false
an:Destroy()
end
end

return ak
end



return aa end function a.C()
game:GetService"ReplicatedStorage"
local aa=a.load'd'
local ab=aa.New
local ac=aa.NewRoundFrame
local ad=aa.Tween

local ae=(cloneref or clonereference or function(ae)
return ae
end)

ae(game:GetService"UserInputService")

local af=a.load'y'

local function Color3ToHSB(ag)
local ah,ai,aj=ag.R,ag.G,ag.B
local ak=math.max(ah,ai,aj)
local al=math.min(ah,ai,aj)
local am=ak-al

local an=0
if am~=0 then
if ak==ah then
an=(ai-aj)/am%6
elseif ak==ai then
an=(aj-ah)/am+2
else
an=(ah-ai)/am+4
end
an=an*60
else
an=0
end

local ao=(ak==0)and 0 or(am/ak)
local ap=ak

return{
h=math.floor(an+0.5),
s=ao,
b=ap,
}
end

local function GetPerceivedBrightness(ag)
local ah=ag.R
local ai=ag.G
local aj=ag.B
return 0.299*ah+0.587*ai+0.114*aj
end

local function GetTextColorForHSB(ag)
local ah=Color3ToHSB(ag)local
ai, aj, ak=ah.h, ah.s, ah.b
if GetPerceivedBrightness(ag)>0.5 then
return Color3.fromHSV(ai/360,0,0.05)
else
return Color3.fromHSV(ai/360,0,0.98)
end
end

return function(ag)
local ah={
Title=ag.Title,
Desc=ag.Desc or nil,
Hover=ag.Hover,
Thumbnail=ag.Thumbnail,
ThumbnailSize=ag.ThumbnailSize or 80,
Image=ag.Image,
IconThemed=ag.IconThemed or false,
ImageSize=ag.ImageSize or 30,
Color=ag.Color,
Scalable=ag.Scalable,
Parent=ag.Parent,
Justify=ag.Justify or"Between",
UIPadding=ag.Window.ElementConfig.UIPadding,
UICorner=ag.Window.ElementConfig.UICorner,
Size=ag.Size or"Default",
Tags=ag.Tags or{},
UIElements={},

Index=ag.Index,
}

local ai=ah.Size=="Small"and-4 or ah.Size=="Large"and 4 or 0
local aj=ah.Size=="Small"and-4 or ah.Size=="Large"and 4 or 0

local ak=ah.ImageSize
local al=ah.ThumbnailSize
local am=true


local an=0

local ao
local ap
if ah.Thumbnail then
ao=aa.Image(
ah.Thumbnail,
ah.Title,
ag.Window.NewElements and ah.UICorner-11 or(ah.UICorner-4),
ag.Window.Folder,
"Thumbnail",
false,
ah.IconThemed
)
ao.Size=UDim2.new(1,0,0,al)
end
if ah.Image then
ap=aa.Image(
ah.Image,
ah.Title,
ag.Window.NewElements and ah.UICorner-11 or(ah.UICorner-4),
ag.Window.Folder,
"Image",
ah.IconThemed,
not ah.Color and true or false,
"ElementIcon"
)

if typeof(ah.Color)=="string"and not string.find(ah.Image,"rbxthumb")then
ap.ImageLabel.ImageColor3=GetTextColorForHSB(Color3.fromHex(aa.Colors[ah.Color]))
elseif typeof(ah.Color)=="Color3"and not string.find(ah.Image,"rbxthumb")then
ap.ImageLabel.ImageColor3=GetTextColorForHSB(ah.Color)
end

ap.Size=UDim2.new(0,ak,0,ak)

an=ak
end

local function CreateText(aq,ar)
local as=typeof(ah.Color)=="string"
and GetTextColorForHSB(Color3.fromHex(aa.Colors[ah.Color]))
or typeof(ah.Color)=="Color3"and GetTextColorForHSB(ah.Color)

return ab("TextLabel",{
BackgroundTransparency=1,
Text=aq or"",
TextSize=ar=="Desc"and 15 or 17,
TextXAlignment="Left",
ThemeTag={
TextColor3=not ah.Color and("Element"..ar)or nil,
},
TextColor3=ah.Color and as or nil,
TextTransparency=ar=="Desc"and 0.3 or 0,
TextWrapped=true,
Size=UDim2.new(ah.Justify=="Between"and 1 or 0,0,0,0),
AutomaticSize=ah.Justify=="Between"and"Y"or"XY",
FontFace=Font.new(aa.Font,ar=="Desc"and Enum.FontWeight.Medium or Enum.FontWeight.SemiBold),
})
end

local aq=CreateText(ah.Title,"Title")
local ar=CreateText(ah.Desc,"Desc")
if not ah.Title or ah.Title==""then
ar.Visible=false
end
if not ah.Desc or ah.Desc==""then
ar.Visible=false
end

ah.UIElements.Title=aq
ah.UIElements.Desc=ar

ah.UIElements.Container=ab("Frame",{
Size=UDim2.new(1,0,1,0),
AutomaticSize="Y",
BackgroundTransparency=1,
},{
ab("UIListLayout",{
Padding=UDim.new(0,ah.UIPadding),
FillDirection="Vertical",
VerticalAlignment="Center",
HorizontalAlignment=ah.Justify=="Between"and"Left"or"Center",
}),
ao,
ab("Frame",{
Size=UDim2.new(
ah.Justify=="Between"and 1 or 0,
ah.Justify=="Between"and-ag.TextOffset or 0,
0,
0
),
AutomaticSize=ah.Justify=="Between"and"Y"or"XY",
BackgroundTransparency=1,
Name="TitleFrame",
},{
ab("UIListLayout",{
Padding=UDim.new(0,ah.UIPadding),
FillDirection="Horizontal",
VerticalAlignment=ag.Window.NewElements and(ah.Justify=="Between"and"Top"or"Center")
or"Center",
HorizontalAlignment=ah.Justify~="Between"and ah.Justify or"Center",
}),
ap,
ab("Frame",{
BackgroundTransparency=1,
AutomaticSize=ah.Justify=="Between"and"Y"or"XY",
Size=UDim2.new(
ah.Justify=="Between"and 1 or 0,
ah.Justify=="Between"and(ap and-an-ah.UIPadding or-an)
or 0,
1,
0
),
Name="TitleFrame",
},{
ab("UIPadding",{
PaddingTop=UDim.new(0,(ag.Window.NewElements and ah.UIPadding/2 or 0)+aj),
PaddingLeft=UDim.new(0,(ag.Window.NewElements and ah.UIPadding/2 or 0)+ai),
PaddingRight=UDim.new(
0,
(ag.Window.NewElements and ah.UIPadding/2 or 0)+ai
),
PaddingBottom=UDim.new(
0,
(ag.Window.NewElements and ah.UIPadding/2 or 0)+aj
),
}),
ab("UIListLayout",{
Padding=UDim.new(0,6),
FillDirection="Vertical",
VerticalAlignment="Center",
HorizontalAlignment="Left",
}),
ab("ScrollingFrame",{
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
LayoutOrder=-99,
BackgroundTransparency=1,
ScrollingDirection="X",
CanvasSize=UDim2.new(0,0,0,0),
ScrollBarThickness=0,
Visible=false,
},{
ab("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment="Left",
Padding=UDim.new(0,ag.Window.UIPadding/2),
}),
}),
ab("Frame",{
Name="Space",
Size=UDim2.new(1,0,0,0),
BackgroundTransparency=1,
Visible=false,
}),
aq,
ar,
}),
}),
})

for as,at in next,ag.Tags or{}do
if not ah.UIElements.Container.TitleFrame.TitleFrame.ScrollingFrame.Visible then
ah.UIElements.Container.TitleFrame.TitleFrame.ScrollingFrame.Visible=true
ah.UIElements.Container.TitleFrame.TitleFrame.Space.Visible=true
end
af:New(at,ah.UIElements.Container.TitleFrame.TitleFrame.ScrollingFrame)
end

aa.AddSignal(
ah.UIElements.Container.TitleFrame.TitleFrame.ScrollingFrame.UIListLayout:GetPropertyChangedSignal
"AbsoluteContentSize"
,
function()
ah.UIElements.Container.TitleFrame.TitleFrame.ScrollingFrame.Size=UDim2.new(
1,
0,
0,
ah.UIElements.Container.TitleFrame.TitleFrame.ScrollingFrame.UIListLayout.AbsoluteContentSize.Y
/ag.ParentConfig.UIScale
)
end
)





local as=aa.Image("lock","lock",0,ag.Window.Folder,"Lock",false)
as.Size=UDim2.new(0,20,0,20)
as.ImageLabel.ImageColor3=Color3.new(1,1,1)
as.ImageLabel.ImageTransparency=0.4

local at=ab("TextLabel",{
Text="Locked",
TextSize=18,
FontFace=Font.new(aa.Font,Enum.FontWeight.Medium),
AutomaticSize="XY",
BackgroundTransparency=1,
TextColor3=Color3.new(1,1,1),
TextTransparency=0.05,
})

local au=ab("Frame",{
Size=UDim2.new(1,ah.UIPadding*2,1,ah.UIPadding*2),
BackgroundTransparency=1,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
ZIndex=9999999,
})

local av,aw=ac(ah.UICorner,"Squircle",{
Size=UDim2.new(1,0,1,0),
ImageTransparency=0.25,
ImageColor3=Color3.new(0,0,0),
Visible=false,
Active=false,
Parent=au,
},{
ab("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment="Center",
Padding=UDim.new(0,8),
}),
as,
at,
},nil,true)local

ax=ac(ah.UICorner,"Squircle-Outline",{
Size=UDim2.new(1,0,1,0),
ImageTransparency=1,
Active=false,
ThemeTag={
ImageColor3="Text",
},
Parent=au,
},{
ab("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment="Center",
Padding=UDim.new(0,8),
}),
},nil,true)

local ay,az=ac(ah.UICorner,"Squircle",{
Size=UDim2.new(1,0,1,0),
ImageTransparency=1,
Active=false,
ThemeTag={
ImageColor3="Text",
},
Parent=au,
},{
ab("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment="Center",
Padding=UDim.new(0,8),
}),
},nil,true)local

aA=ac(ah.UICorner,"Squircle-Outline",{
Size=UDim2.new(1,0,1,0),
ImageTransparency=1,
Visible=false,
Active=false,
ThemeTag={
ImageColor3="Text",
},
Parent=au,
},{
ab("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment="Center",
Padding=UDim.new(0,8),
}),
ab("UIGradient",{
Name="HoverGradient",
Color=ColorSequence.new{
ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),
ColorSequenceKeypoint.new(0.5,Color3.new(1,1,1)),
ColorSequenceKeypoint.new(1,Color3.new(1,1,1)),
},
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0,1),
NumberSequenceKeypoint.new(0.25,0.9),
NumberSequenceKeypoint.new(0.5,0.3),
NumberSequenceKeypoint.new(0.75,0.9),
NumberSequenceKeypoint.new(1,1),
},
}),
},nil,true)

local aB,b=ac(ah.UICorner,"Squircle",{
Size=UDim2.new(1,0,1,0),
ImageTransparency=1,
Active=false,
ThemeTag={
ImageColor3="Text",
},
Parent=au,
},{
ab("UIGradient",{
Name="HoverGradient",
Color=ColorSequence.new{
ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),
ColorSequenceKeypoint.new(0.5,Color3.new(1,1,1)),
ColorSequenceKeypoint.new(1,Color3.new(1,1,1)),
},
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0,1),
NumberSequenceKeypoint.new(0.25,0.9),
NumberSequenceKeypoint.new(0.5,0.3),
NumberSequenceKeypoint.new(0.75,0.9),
NumberSequenceKeypoint.new(1,1),
},
}),
ab("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment="Center",
Padding=UDim.new(0,8),
}),
},nil,true)

local d,f=ac(ah.UICorner,"Squircle",{
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
ImageTransparency=ah.Color and 0.05 or(not ag.Window.NewElements and 0.93 or nil),



Parent=ag.Parent,
ThemeTag={
ImageColor3=not ah.Color and(ag.Window.NewElements and"ElementBackground"or"Text")or nil,
ImageTransparency=not ah.Color
and(ag.Window.NewElements and"ElementBackgroundTransparency"or nil)
or nil,
},
ImageColor3=ah.Color and(typeof(ah.Color)=="string"and Color3.fromHex(
aa.Colors[ah.Color]
)or typeof(ah.Color)=="Color3"and ah.Color)or nil,
},{
ah.UIElements.Container,
au,
ab("UIPadding",{
PaddingTop=UDim.new(0,ah.UIPadding),
PaddingLeft=UDim.new(0,ah.UIPadding),
PaddingRight=UDim.new(0,ah.UIPadding),
PaddingBottom=UDim.new(0,ah.UIPadding),
}),
},true,true)

ah.UIElements.Main=d
ah.UIElements.Locked=av

if ah.Hover then
aa.AddSignal(d.MouseEnter,function()
if am then

ad(aB,0.12,{ImageTransparency=0.9}):Play()
ad(aA,0.12,{ImageTransparency=0.8}):Play()
aa.AddSignal(d.MouseMoved,function(g,h)
aB.HoverGradient.Offset=
Vector2.new(((g-d.AbsolutePosition.X)/d.AbsoluteSize.X)-0.5,0)
aA.HoverGradient.Offset=
Vector2.new(((g-d.AbsolutePosition.X)/d.AbsoluteSize.X)-0.5,0)
end)
end
end)
aa.AddSignal(d.InputEnded,function()
if am then

ad(aB,0.12,{ImageTransparency=1}):Play()
ad(aA,0.12,{ImageTransparency=1}):Play()
end
end)
end

function ah.SetTitle(g,h)
ah.Title=h
aq.Text=h
end

function ah.SetDesc(g,h)
ah.Desc=h
ar.Text=h or""
if not h then
ar.Visible=false
elseif not ar.Visible then
ar.Visible=true
end
end

function ah.Colorize(g,h,i)
if ah.Color then
h[i]=typeof(ah.Color)=="string"
and GetTextColorForHSB(Color3.fromHex(aa.Colors[ah.Color]))
or typeof(ah.Color)=="Color3"and GetTextColorForHSB(ah.Color)
or nil
end
end

if ag.ElementTable then
aa.AddSignal(aq:GetPropertyChangedSignal"Text",function()
if ah.Title~=aq.Text then
ah:SetTitle(aq.Text)
ag.ElementTable.Title=aq.Text
end
end)
aa.AddSignal(ar:GetPropertyChangedSignal"Text",function()
if ah.Desc~=ar.Text then
ah:SetDesc(ar.Text)
ag.ElementTable.Desc=ar.Text
end
end)
end





function ah.SetThumbnail(g,h,i)
ah.Thumbnail=h
if i then
ah.ThumbnailSize=i
al=i
end

if ao then
if h then
ao:Destroy()
ao=aa.Image(
h,
ah.Title,
ah.UICorner-3,
ag.Window.Folder,
"Thumbnail",
false,
ah.IconThemed
)
if ao then
ao.Size=UDim2.new(1,0,0,al)
ao.Parent=ah.UIElements.Container
local l=ah.UIElements.Container:FindFirstChild"UIListLayout"
if l then
ao.LayoutOrder=-1
end
end
else
ao.Visible=false
end
else
if h then
ao=aa.Image(
h,
ah.Title,
ah.UICorner-3,
ag.Window.Folder,
"Thumbnail",
false,
ah.IconThemed
)
if ao then
ao.Size=UDim2.new(1,0,0,al)
ao.Parent=ah.UIElements.Container
local l=ah.UIElements.Container:FindFirstChild"UIListLayout"
if l then
ao.LayoutOrder=-1
end
end
end
end
end

function ah.SetImage(g,h,i)
ah.Image=h
if i then
ah.ImageSize=i
ak=i
end

if h then
local l=ap and ap.Parent or ah.UIElements.Container.TitleFrame
if ap then
ap:Destroy()
end

ap=aa.Image(
h,
h,
ah.UICorner-3,
ag.Window.Folder,
"Image",
not ah.Color and true or false
)
if ap then
if typeof(ah.Color)=="string"and not string.find(ah.Image,"rbxthumb")then
ap.ImageLabel.ImageColor3=
GetTextColorForHSB(Color3.fromHex(aa.Colors[ah.Color]))
elseif typeof(ah.Color)=="Color3"and not string.find(ah.Image,"rbxthumb")then
ap.ImageLabel.ImageColor3=GetTextColorForHSB(ah.Color)
end

ap.Visible=true
ap.Parent=l
ap.LayoutOrder=-99

ap.Size=UDim2.new(0,ak,0,ak)
an=ah.ImageSize+ah.UIPadding
end
else
if ap then
ap.Visible=true
end
an=0
end

ah.UIElements.Container.TitleFrame.TitleFrame.Size=UDim2.new(1,-an,1,0)
end

function ah.Destroy(g)
d:Destroy()
end

function ah.Lock(g,h)
am=false
av.Active=true
av.Visible=true
at.Text=h or"Locked"
end

function ah.Unlock(g)
am=true
av.Active=false
av.Visible=false
end

function ah.Highlight(g)
local h=ab("UIGradient",{
Color=ColorSequence.new{
ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),
ColorSequenceKeypoint.new(0.5,Color3.new(1,1,1)),
ColorSequenceKeypoint.new(1,Color3.new(1,1,1)),
},
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0,1),
NumberSequenceKeypoint.new(0.1,0.9),
NumberSequenceKeypoint.new(0.5,0.3),
NumberSequenceKeypoint.new(0.9,0.9),
NumberSequenceKeypoint.new(1,1),
},
Rotation=0,
Offset=Vector2.new(-1,0),
Parent=ax,
})

local i=ab("UIGradient",{
Color=ColorSequence.new{
ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),
ColorSequenceKeypoint.new(0.5,Color3.new(1,1,1)),
ColorSequenceKeypoint.new(1,Color3.new(1,1,1)),
},
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0,1),
NumberSequenceKeypoint.new(0.15,0.8),
NumberSequenceKeypoint.new(0.5,0.1),
NumberSequenceKeypoint.new(0.85,0.8),
NumberSequenceKeypoint.new(1,1),
},
Rotation=0,
Offset=Vector2.new(-1,0),
Parent=ay,
})

ax.ImageTransparency=0.65
ay.ImageTransparency=0.88

ad(h,0.75,{
Offset=Vector2.new(1,0),
}):Play()

ad(i,0.75,{
Offset=Vector2.new(1,0),
}):Play()

task.spawn(function()
task.wait(0.75)
ax.ImageTransparency=1
ay.ImageTransparency=1
h:Destroy()
i:Destroy()
end)
end

function ah.UpdateShape(g)
if ag.Window.NewElements then
local h=aa:GetElementPosition(
g.Elements,
ah.Index,
ag.ParentConfig.ParentTable.__type=="HStack"or ag.ParentConfig.ParentTable.__type=="Group"
)

if h and d then
f:SetType(h)
aw:SetType(h)
az:SetType(h)

b:SetType(h)

end
end
end





return ah
end end function a.D()

local aa=a.load'd'
local ab=aa.New

local ac={}

local ad=a.load'm'.New

function ac.New(ae,af)
af.Hover=false
af.TextOffset=0
af.ParentConfig=af
af.IsButtons=af.Buttons and#af.Buttons>0 and true or false

local ag={
__type="Paragraph",
Title=af.Title or"Paragraph",
Desc=af.Desc or nil,

Locked=af.Locked or false,
}
local ah=a.load'C'(af)

ag.ParagraphFrame=ah
if af.Buttons and#af.Buttons>0 then
local ai=ab("Frame",{
Size=UDim2.new(1,0,0,38),
BackgroundTransparency=1,
AutomaticSize="Y",
Parent=ah.UIElements.Container,
},{
ab("UIListLayout",{
Padding=UDim.new(0,10),
FillDirection="Vertical",
}),
})

for aj,ak in next,af.Buttons do
local al=ad(
ak.Title,
ak.Icon,
ak.Callback,
ak.Variant or"White",
ai,
nil,
nil,
af.Window.NewElements and 999 or 10
)
al.Size=UDim2.new(1,0,0,38)

end
end

return ag.__type,ag
end

return ac end function a.E()

local aa=a.load'd'local ab=
aa.New

local ac={}

function ac.New(ad,ae)
local af={
__type="Button",
Title=ae.Title or"Button",
Desc=ae.Desc or nil,
Icon=ae.Icon or"mouse-pointer-click",
IconThemed=ae.IconThemed or false,
IconColor=ae.IconColor or nil,
Color=ae.Color,
Justify=ae.Justify or"Between",
IconAlign=ae.IconAlign or"Right",
Locked=ae.Locked or false,
LockedTitle=ae.LockedTitle,
Callback=ae.Callback or function()end,
UIElements={},
}

local ag=true

af.ButtonFrame=a.load'C'{
Title=af.Title,
Desc=af.Desc,
Parent=ae.Parent,




Window=ae.Window,
Color=af.Color,
Justify=af.Justify,
TextOffset=20,
Hover=true,
Scalable=true,
Tab=ae.Tab,
Index=ae.Index,
ElementTable=af,
ParentConfig=ae,
Size=ae.Size,
Tags=ae.Tags,
}














af.UIElements.ButtonIcon=aa.Image(
af.Icon,
af.Icon,
0,
ae.Window.Folder,
"Button",
not(af.Color or af.IconColor)and true or nil,
af.IconThemed
)

if af.IconColor then
af.UIElements.ButtonIcon.ImageLabel.ImageColor3=af.IconColor
end

af.UIElements.ButtonIcon.Size=UDim2.new(0,20,0,20)
af.UIElements.ButtonIcon.Parent=af.Justify=="Between"and af.ButtonFrame.UIElements.Main
or af.ButtonFrame.UIElements.Container.TitleFrame
af.UIElements.ButtonIcon.LayoutOrder=af.IconAlign=="Left"and-99999 or 99999
af.UIElements.ButtonIcon.AnchorPoint=Vector2.new(1,0.5)
af.UIElements.ButtonIcon.Position=UDim2.new(1,0,0.5,0)

af.ButtonFrame:Colorize(af.UIElements.ButtonIcon.ImageLabel,"ImageColor3")

function af.Lock(ah)
af.Locked=true
ag=false
return af.ButtonFrame:Lock(af.LockedTitle)
end
function af.Unlock(ah)
af.Locked=false
ag=true
return af.ButtonFrame:Unlock()
end

if af.Locked then
af:Lock()
end

aa.AddSignal(af.ButtonFrame.UIElements.Main.MouseButton1Click,function()
if ag then
task.spawn(function()
aa.SafeCallback(af.Callback)
end)
end
end)
return af.__type,af
end

return ac end function a.F()

local aa={}

local ab=a.load'd'
local ac=ab.New
local ad=ab.Tween

local ae=game:GetService"UserInputService"

function aa.New(af,ag,ah,ai,aj,ak,al)
local am={
GlassSpritesheet={
Id="rbxassetid://77297718671545",
MirroredId="rbxassetid://92258969882244",
Size=Vector2.new(102,128),
Total=80,
Cols=10,
},
}

function am.GetGlassFrame(an,ao:number):(string,Vector2,Vector2)
local ap=am.GlassSpritesheet
local aq:number

if ao<=0.4 then
aq=math.floor((ao/0.4)*(ap.Total-1))
elseif ao<0.6 then
aq=ap.Total-1
else
aq=math.floor(((ao-0.6)/0.4)*(ap.Total-1))
end

aq=math.clamp(aq,0,ap.Total-1)

local ar=ao>=0.6
if ar then
aq=(ap.Total-1)-aq
end

local as=ar and ap.MirroredId or ap.Id

return as,ap.Size,Vector2.new((aq%ap.Cols)*ap.Size.X,math.floor(aq/ap.Cols)*ap.Size.Y)
end

local an=12
local ao
if ag and ag~=""then
ao=ac("ImageLabel",{
Size=UDim2.new(0,13,0,13),
BackgroundTransparency=1,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Image=ab.Icon(ag)[1],
ImageRectOffset=ab.Icon(ag)[2].ImageRectPosition,
ImageRectSize=ab.Icon(ag)[2].ImageRectSize,
ImageTransparency=1,
ImageColor3=Color3.new(0,0,0),
})
end

local ap=ac("Frame",{
Size=UDim2.new(0,2,0,26),
BackgroundTransparency=1,
Parent=ai,
})

local aq=ab.NewRoundFrame(an,"Squircle",{
ImageTransparency=0.85,
ThemeTag={
ImageColor3="Text",
},
Parent=ap,
Size=UDim2.new(0,ak and(52)or(40.8),0,24),
AnchorPoint=Vector2.new(1,0.5),
Position=UDim2.new(0,0,0.5,0),
Name="ToggleFrame",
},{
ab.NewRoundFrame(an,"Squircle",{
Size=UDim2.new(1,0,1,0),
Name="Layer",
ThemeTag={
ImageColor3="Toggle",
},
ImageTransparency=1,
}),
ab.NewRoundFrame(an,"SquircleOutline",{
Size=UDim2.new(1,0,1,0),
Name="Stroke",
ImageColor3=Color3.new(1,1,1),
ImageTransparency=1,
},{
ac("UIGradient",{
Rotation=90,
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0,0),
NumberSequenceKeypoint.new(1,1),
},
}),
}),


ab.NewRoundFrame(an,"Squircle",{
Size=UDim2.new(0,ak and 30 or 20,0,20),
Position=UDim2.new(0,2,0.5,0),
AnchorPoint=Vector2.new(0,0.5),
ImageTransparency=1,
Name="Frame",
},{
ab.NewRoundFrame(an,"Squircle",{
Size=UDim2.new(1,0,1,0),
ImageTransparency=0,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Name="Bar",
},{
ab.New("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundColor3=Color3.new(1,1,1),
Name="Highlight",
BackgroundTransparency=1,
},{
ab.NewRoundFrame(9999,"SquircleGlass",{
Size=UDim2.new(1,1,1,1),
ImageColor3=Color3.new(1,1,1),
Name="SquircleGlass",
ImageTransparency=0.5,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
}),
ab.NewRoundFrame(an,"Squircle",{
Size=UDim2.new(1,0,1,0),
Name="GlassBackground",
ImageTransparency=0,
ThemeTag={
ImageColor3="ElementBackground",
},
ZIndex=-1,
}),
ac("ImageLabel",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
Name="Glass",
ImageTransparency=0,
},{
ac("UICorner",{
CornerRadius=UDim.new(1,0),
}),
}),






ab.NewRoundFrame(an,"Squircle",{
Size=UDim2.new(1,0,1,0),
Name="BarOverlay",
ThemeTag={
ImageColor3="ToggleBar",
},
ZIndex=999,
}),
}),
ao,
ac("UIScale",{
Scale=1,
}),
}),
}),
ac("TextButton",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
Name="Hitbox",
Text="",
}),
})

local ar
local as

local at=ak and 30 or 20
local au=aq.Size.X.Offset

function am.Set(av,aw,ax,ay)
if not ay then
if aw then
ad(aq.Frame,0.35,{
Position=UDim2.new(0,au-at-2,0.5,0),
},Enum.EasingStyle.Back,Enum.EasingDirection.Out):Play()
ab.SetThemeTag(aq.Frame.Bar.Highlight.Glass,{ImageColor3="Toggle"},0.15)

ad(
aq.Frame.Bar.Highlight.Glass,
0.15,
{ImageTransparency=0},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
else
ad(aq.Frame,0.35,{
Position=UDim2.new(0,2,0.5,0),
},Enum.EasingStyle.Back,Enum.EasingDirection.Out):Play()
ab.SetThemeTag(aq.Frame.Bar.Highlight.Glass,{ImageColor3="Text"},0.15)
ad(
aq.Frame.Bar.Highlight.Glass,
0.15,
{ImageTransparency=0.85},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
end
else
if aw then
aq.Frame.Position=UDim2.new(0,au-at-2,0.5,0)
else
aq.Frame.Position=UDim2.new(0,2,0.5,0)
end
end

if aw then
ad(aq.Layer,0.1,{
ImageTransparency=0,
}):Play()
ab.SetThemeTag(aq.Frame.Bar.Highlight.Glass,{ImageColor3="Toggle"},0.1)
ad(
aq.Frame.Bar.Highlight.Glass,
0.1,
{ImageTransparency=0},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()

if ao then
ad(ao,0.1,{
ImageTransparency=0,
}):Play()
end

local az,aA,aB=am:GetGlassFrame(1)

aq.Frame.Bar.Highlight.Glass.Image=az
aq.Frame.Bar.Highlight.Glass.ImageRectSize=aA
aq.Frame.Bar.Highlight.Glass.ImageRectOffset=aB
else
ad(aq.Layer,0.1,{
ImageTransparency=1,
}):Play()
ab.SetThemeTag(aq.Frame.Bar.Highlight.Glass,{ImageColor3="Text"},0.1)
ad(
aq.Frame.Bar.Highlight.Glass,
0.1,
{ImageTransparency=0.85},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()

if ao then
ad(ao,0.1,{
ImageTransparency=1,
}):Play()
end

local az,aA,aB=am:GetGlassFrame(0)

aq.Frame.Bar.Highlight.Glass.Image=az
aq.Frame.Bar.Highlight.Glass.ImageRectSize=aA
aq.Frame.Bar.Highlight.Glass.ImageRectOffset=aB
end

ax=ax~=false

task.spawn(function()
if aj and ax then
ab.SafeCallback(aj,aw)
end
end)
end

function am.Animate(av,aw,ax)
if not al.Window.IsToggleDragging then
al.Window.IsToggleDragging=true

local ay=aw.Position.X
local az=aw.Position.Y
local aA=aq.Frame.Position.X.Offset
local aB=false
local b=false

ad(
aq.Frame.Bar.UIScale,
0.28,
{Scale=1.5},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
ad(
aq.Frame.Bar.Highlight.BarOverlay,
0.28,
{ImageTransparency=0.86},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()

if ar then
ar:Disconnect()
end

ar=ae.InputChanged:Connect(function(d)
if not al.Window.IsToggleDragging then
return
end
if
d.UserInputType~=Enum.UserInputType.MouseMovement
and d.UserInputType~=Enum.UserInputType.Touch
then
return
end
if aB then
return
end

local f=math.abs(d.Position.X-ay)
math.abs(d.Position.Y-az)

if not b and f>8 then
b=true
end

local g=d.Position.X-ay
local h=math.max(2,math.min(aA+g,au-at-2))

local i=math.clamp((h-2)/(au-at-4),0,1)

local l,m,p=am:GetGlassFrame(i)
aq.Frame.Bar.Highlight.Glass.Image=l
aq.Frame.Bar.Highlight.Glass.ImageRectSize=m
aq.Frame.Bar.Highlight.Glass.ImageRectOffset=p

ad(aq.Frame,0.12,{
Position=UDim2.new(0,h,0.5,0),
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end)

if as then
as:Disconnect()
end

as=ae.InputEnded:Connect(function(d)
if not al.Window.IsToggleDragging then
return
end
if
d.UserInputType~=Enum.UserInputType.MouseButton1
and d.UserInputType~=Enum.UserInputType.Touch
then
return
end

al.Window.IsToggleDragging=false

if ar then
ar:Disconnect()
ar=nil
end
if as then
as:Disconnect()
as=nil
end

al.WindUI.CurrentInput=nil

if aB then
return
end

if not b then
ax:Set(not ax.Value,true,false)
else
local f=aq.Frame.Position.X.Offset
local g=f+at/2
local h=g>au/2
ax:Set(h,true,false)
end

ad(
aq.Frame.Bar.UIScale,
0.23,
{Scale=1},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
ad(
aq.Frame.Bar.Highlight.BarOverlay,
0.23,
{ImageTransparency=0},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
end)
end
end

return ap,am
end

return aa end function a.G()

local aa={}

local ab=a.load'd'local ac=
ab.New
local ad=ab.Tween


function aa.New(ae,af,ag,ah,ai,aj)
local ak={}

af=af or"sfsymbols:checkmark"

local al=9

local am=ab.Image(
af,
af,
0,
(aj and aj.Window.Folder or"Temp"),
"Checkbox",
true,
false,
"CheckboxIcon"
)
am.Size=UDim2.new(1,-26+ag,1,-26+ag)
am.AnchorPoint=Vector2.new(0.5,0.5)
am.Position=UDim2.new(0.5,0,0.5,0)


local an=ab.NewRoundFrame(al,"Squircle",{
ImageTransparency=.85,
ThemeTag={
ImageColor3="Text"
},
Parent=ah,
Size=UDim2.new(0,26,0,26),
},{
ab.NewRoundFrame(al,"Squircle",{
Size=UDim2.new(1,0,1,0),
Name="Layer",
ThemeTag={
ImageColor3="Checkbox",
},
ImageTransparency=1,
}),
ab.NewRoundFrame(al,"Glass-1.4",{
Size=UDim2.new(1,0,1,0),
Name="Stroke",
ThemeTag={
ImageColor3="CheckboxBorder",
ImageTransparency="CheckboxBorderTransparency",
},
},{







}),

am,
},true)

function ak.Set(ao,ap)
if ap then
ad(an.Layer,0.06,{
ImageTransparency=0,
}):Play()



ad(am.ImageLabel,0.06,{
ImageTransparency=0,
}):Play()
else
ad(an.Layer,0.05,{
ImageTransparency=1,
}):Play()



ad(am.ImageLabel,0.06,{
ImageTransparency=1,
}):Play()
end

task.spawn(function()
if ai then
ab.SafeCallback(ai,ap)
end
end)
end

return an,ak
end


return aa end function a.H()
local aa=a.load'd'local ab=
aa.New local ac=
aa.Tween

local ad=a.load'F'.New
local ae=a.load'G'.New

local af={}

function af.New(ag,ah)
local ai={
__type="Toggle",
Title=ah.Title or"Toggle",
Desc=ah.Desc or nil,
Locked=ah.Locked or false,
LockedTitle=ah.LockedTitle,
Value=ah.Value,
Icon=ah.Icon or nil,
IconSize=ah.IconSize or 23,
Type=ah.Type or"Toggle",
Callback=ah.Callback or function()end,
UIElements={},
}
ai.ToggleFrame=a.load'C'{
Title=ai.Title,
Desc=ai.Desc,




Window=ah.Window,
Parent=ah.Parent,
TextOffset=(52),
Hover=false,
Tab=ah.Tab,
Index=ah.Index,
ElementTable=ai,
ParentConfig=ah,
Tags=ah.Tags,
}

local aj=true

if ai.Value==nil then
ai.Value=false
end

function ai.Lock(ak)
ai.Locked=true
aj=false
return ai.ToggleFrame:Lock(ai.LockedTitle)
end
function ai.Unlock(ak)
ai.Locked=false
aj=true
return ai.ToggleFrame:Unlock()
end

if ai.Locked then
ai:Lock()
end

local ak=ai.Value

local al,am
if ai.Type=="Toggle"then
al,am=ad(
ak,
ai.Icon,
ai.IconSize,
ai.ToggleFrame.UIElements.Main,
ai.Callback,
ah.Window.NewElements,
ah
)
elseif ai.Type=="Checkbox"then
al,am=ae(
ak,
ai.Icon,
ai.IconSize,
ai.ToggleFrame.UIElements.Main,
ai.Callback,
ah
)
else
error("Unknown Toggle Type: "..tostring(ai.Type))
end

al.AnchorPoint=Vector2.new(1,ah.Window.NewElements and 0 or 0.5)
al.Position=UDim2.new(1,0,ah.Window.NewElements and 0 or 0.5,0)

function ai.Set(an,ao,ap,aq)
if aj then
am:Set(ao,ap,aq or false)
ak=ao
ai.Value=ao
end
end

ai:Set(ak,false,ah.Window.NewElements)

local an=ah.WindUI.GenerateGUID()

if ah.Window.NewElements and am.Animate then
if ai.Type=="Toggle"then
aa.AddSignal(al.ToggleFrame.Hitbox.InputBegan,function(ao)
if
not ah.Window.IsToggleDragging
and(
ao.UserInputType==Enum.UserInputType.MouseButton1
or ao.UserInputType==Enum.UserInputType.Touch
)
then
if ah.WindUI.CurrentInput and ah.WindUI.CurrentInput~=an then
return
end

ah.WindUI.CurrentInput=an
am:Animate(ao,ai)
end
end)
end





else
if ai.Type=="Toggle"then
aa.AddSignal(al.ToggleFrame.Hitbox.MouseButton1Click,function()
ai:Set(not ai.Value,nil,ah.Window.NewElements)
end)
elseif ai.Type=="Checkbox"then
aa.AddSignal(al.MouseButton1Click,function()
ai:Set(not ai.Value,nil,ah.Window.NewElements)
end)
end
end

return ai.__type,ai
end

return af end function a.I()

local aa=(cloneref or clonereference or function(aa)
return aa
end)

local ac=aa(game:GetService"UserInputService")
local ad=aa(game:GetService"RunService")

local ae=a.load'd'
local af=ae.New
local ag=ae.Tween

local ah={}

local ai=false

function ah.New(aj,ak)
local al={
__type="Slider",
Title=ak.Title or nil,
Desc=ak.Desc or nil,
Locked=ak.Locked or nil,
LockedTitle=ak.LockedTitle,
Value=ak.Value or{},
Icons=ak.Icons or nil,
IsTooltip=ak.IsTooltip or false,
IsTextbox=ak.IsTextbox,
Step=ak.Step or 1,
Callback=ak.Callback or function()end,
UIElements={},
IsFocusing=false,

Width=ak.Width or 130,
TextBoxWidth=ak.Window.NewElements and 40 or 30,
ThumbSize=13,
IconSize=26,
}
if al.Icons=={}then
al.Icons={
From="sfsymbols:sunMinFill",
To="sfsymbols:sunMaxFill",
}
end
if al.IsTextbox==nil and al.Title==nil then
al.IsTextbox=false
else
al.IsTextbox=al.IsTextbox~=false
end

local am
local an
local ao
local ap=al.Value.Default or al.Value.Min or 0

local aq=ap
local ar=(ap-(al.Value.Min or 0))/((al.Value.Max or 100)-(al.Value.Min or 0))

local as=true
local at=al.Step%1~=0

local function FormatValue(au)
if at then
return tonumber(string.format("%.2f",au))
end
return math.floor(au+0.5)
end

local function CalculateValue(au)
if at then
return math.floor(au/al.Step+0.5)*al.Step
else
return math.floor(au/al.Step+0.5)*al.Step
end
end

local au,av
local aw=32
if al.Icons then
if al.Icons.From then
au=ae.Image(
al.Icons.From,
al.Icons.From,
0,
ak.Window.Folder,
"SliderIconFrom",
true,
true,
"SliderIconFrom"
)
au.Size=UDim2.new(0,al.IconSize,0,al.IconSize)
aw=aw+al.IconSize-2
end
if al.Icons.To then
av=ae.Image(
al.Icons.To,
al.Icons.To,
0,
ak.Window.Folder,
"SliderIconTo",
true,
true,
"SliderIconTo"
)
av.Size=UDim2.new(0,al.IconSize,0,al.IconSize)
aw=aw+al.IconSize-2
end
end
al.SliderFrame=a.load'C'{
Title=al.Title,
Desc=al.Desc,
Parent=ak.Parent,
TextOffset=al.Width,
Hover=false,
Tab=ak.Tab,
Index=ak.Index,
Window=ak.Window,
ElementTable=al,
ParentConfig=ak,
Tags=ak.Tags,
}

al.UIElements.SliderIcon=ae.NewRoundFrame(99,"Squircle",{
ImageTransparency=0.95,
Size=UDim2.new(1,not al.IsTextbox and-aw or(-al.TextBoxWidth-8),0,4),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Name="Frame",
ThemeTag={
ImageColor3="Text",
},
},{
ae.NewRoundFrame(99,"Squircle",{
Name="Frame",
Size=UDim2.new(ar,0,1,0),
ImageTransparency=0.1,
ThemeTag={
ImageColor3="Slider",
},
},{
ae.NewRoundFrame(99,"Squircle",{
Size=UDim2.new(
0,
ak.Window.NewElements and(al.ThumbSize*2)or(al.ThumbSize+2),
0,
ak.Window.NewElements and(al.ThumbSize+4)or(al.ThumbSize+2)
),
Position=UDim2.new(1,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
ThemeTag={
ImageColor3="SliderThumb",
},
Name="Thumb",
},{
ae.NewRoundFrame(999,"SquircleGlass",{
Size=UDim2.new(1,0,1,0),
ImageColor3=Color3.new(1,1,1),
Name="Highlight",
ImageTransparency=0.5,
}),
}),
}),
})

al.UIElements.SliderContainer=af("Frame",{
Size=UDim2.new(al.Title==nil and 1 or 0,al.Title==nil and 0 or al.Width,0,0),
AutomaticSize="Y",
Position=UDim2.new(1,al.IsTextbox and(ak.Window.NewElements and-16 or 0)or 0,0.5,0),
AnchorPoint=Vector2.new(1,0.5),
BackgroundTransparency=1,
Parent=al.SliderFrame.UIElements.Main,
},{
af("UIListLayout",{
Padding=UDim.new(0,al.Title~=nil and 8 or 12),
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment=al.Icons
and(al.Icons.From and(al.Icons.To and"Center"or"Left")or al.Icons.To and"Right")
or"Center",
}),
au,
al.UIElements.SliderIcon,
av,
af("TextBox",{
Size=UDim2.new(0,al.TextBoxWidth,0,0),
TextXAlignment="Left",
Text=FormatValue(ap),
ThemeTag={
TextColor3="Text",
},
TextTransparency=0.4,
AutomaticSize="Y",
TextSize=15,
FontFace=Font.new(ae.Font,Enum.FontWeight.Medium),
BackgroundTransparency=1,
LayoutOrder=-1,
Visible=al.IsTextbox,
}),
})

local ax
if al.IsTooltip then
ax=a.load'B'.New(
ap,
al.UIElements.SliderIcon.Frame.Thumb,
true,
"Secondary",
"Small",
false
)
ax.Container.AnchorPoint=Vector2.new(0.5,1)
ax.Container.Position=UDim2.new(0.5,0,0,-8)
end

function al.Lock(ay)
al.Locked=true
as=false
return al.SliderFrame:Lock(al.LockedTitle)
end
function al.Unlock(ay)
al.Locked=false
as=true
return al.SliderFrame:Unlock()
end

if al.Locked then
al:Lock()
end


local ay=ak.Tab.UIElements.ContainerFrame

function al.Set(az,aA,aB)
if as then
if
not al.IsFocusing
and not ai
and(
not aB
or(
aB.UserInputType==Enum.UserInputType.MouseButton1
or aB.UserInputType==Enum.UserInputType.Touch
)
)
then
if aB then
am=(aB.UserInputType==Enum.UserInputType.Touch)
ay.ScrollingEnabled=false
ai=true

local b=am and aB.Position.X or ac:GetMouseLocation().X
local d=math.clamp(
(b-al.UIElements.SliderIcon.AbsolutePosition.X)
/al.UIElements.SliderIcon.AbsoluteSize.X,
0,
1
)
aA=CalculateValue(al.Value.Min+d*(al.Value.Max-al.Value.Min))
aA=math.clamp(aA,al.Value.Min or 0,al.Value.Max or 100)

if aA~=aq then
ag(al.UIElements.SliderIcon.Frame,0.05,{Size=UDim2.new(d,0,1,0)}):Play()
al.UIElements.SliderContainer.TextBox.Text=FormatValue(aA)
if ax then
ax.TitleFrame.Text=FormatValue(aA)
end
al.Value.Default=FormatValue(aA)
aq=aA
ae.SafeCallback(al.Callback,FormatValue(aA))
end

an=ad.RenderStepped:Connect(function()
local f=am and aB.Position.X or ac:GetMouseLocation().X
local g=math.clamp(
(f-al.UIElements.SliderIcon.AbsolutePosition.X)
/al.UIElements.SliderIcon.AbsoluteSize.X,
0,
1
)
aA=CalculateValue(al.Value.Min+g*(al.Value.Max-al.Value.Min))

if aA~=aq then
ag(al.UIElements.SliderIcon.Frame,0.05,{Size=UDim2.new(g,0,1,0)}):Play()
al.UIElements.SliderContainer.TextBox.Text=FormatValue(aA)
if ax then
ax.TitleFrame.Text=FormatValue(aA)
end
al.Value.Default=FormatValue(aA)
aq=aA
ae.SafeCallback(al.Callback,FormatValue(aA))
end
end)


ao=ac.InputEnded:Connect(function(f)
if
(
f.UserInputType==Enum.UserInputType.MouseButton1
or f.UserInputType==Enum.UserInputType.Touch
)and aB==f
then
an:Disconnect()
ao:Disconnect()
ai=false
ay.ScrollingEnabled=true

ak.WindUI.CurrentInput=nil

if ak.Window.NewElements then
ag(al.UIElements.SliderIcon.Frame.Thumb,0.2,{
ImageTransparency=0,
Size=UDim2.new(
0,
ak.Window.NewElements and(al.ThumbSize*2)or(al.ThumbSize+2),
0,
ak.Window.NewElements and(al.ThumbSize+4)or(al.ThumbSize+2)
),
},Enum.EasingStyle.Quint,Enum.EasingDirection.InOut):Play()
end
if ax then
ax:Close(false)
end
end
end)
else
aA=math.clamp(aA,al.Value.Min or 0,al.Value.Max or 100)

local b=math.clamp(
(aA-(al.Value.Min or 0))/((al.Value.Max or 100)-(al.Value.Min or 0)),
0,
1
)
aA=CalculateValue(al.Value.Min+b*(al.Value.Max-al.Value.Min))

if aA~=aq then
ag(al.UIElements.SliderIcon.Frame,0.05,{Size=UDim2.new(b,0,1,0)}):Play()
al.UIElements.SliderContainer.TextBox.Text=FormatValue(aA)
if ax then
ax.TitleFrame.Text=FormatValue(aA)
end
al.Value.Default=FormatValue(aA)
aq=aA
ae.SafeCallback(al.Callback,FormatValue(aA))
end
end
end
end
end

function al.SetMax(az,aA)
al.Value.Max=aA

local aB=tonumber(al.Value.Default)or aq
if aB>aA then
al:Set(aA)
else
local b=
math.clamp((aB-(al.Value.Min or 0))/(aA-(al.Value.Min or 0)),0,1)
ag(al.UIElements.SliderIcon.Frame,0.1,{Size=UDim2.new(b,0,1,0)}):Play()
end
end

function al.SetMin(az,aA)
al.Value.Min=aA

local aB=tonumber(al.Value.Default)or aq
if aB<aA then
al:Set(aA)
else
local b=math.clamp((aB-aA)/((al.Value.Max or 100)-aA),0,1)
ag(al.UIElements.SliderIcon.Frame,0.1,{Size=UDim2.new(b,0,1,0)}):Play()
end
end

ae.AddSignal(al.UIElements.SliderContainer.TextBox.FocusLost,function(az)
local aA=tonumber(al.UIElements.SliderContainer.TextBox.Text)
if aA then
al:Set(aA)
else
al.UIElements.SliderContainer.TextBox.Text=FormatValue(aq)
if ax then
ax.TitleFrame.Text=FormatValue(aq)
end
end
end)

local az=ak.WindUI.GenerateGUID()

ae.AddSignal(al.UIElements.SliderContainer.InputBegan,function(aA)
if al.Locked or ai then
return
end
if
aA.UserInputType==Enum.UserInputType.MouseButton1
or aA.UserInputType==Enum.UserInputType.Touch
then
if ak.WindUI.CurrentInput and ak.WindUI.CurrentInput~=az then
return
end
ak.WindUI.CurrentInput=az

al:Set(ap,aA)


if ak.Window.NewElements then
ag(al.UIElements.SliderIcon.Frame.Thumb,0.24,{
ImageTransparency=0.85,
Size=UDim2.new(
0,
(ak.Window.NewElements and(al.ThumbSize*2)or al.ThumbSize)+8,
0,
al.ThumbSize+8
),
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end
if ax then
ax:Open()
end

end
end)

return al.__type,al
end

return ah end function a.J()

local aa=a.load'd'
local ac=aa.New
local ad=aa.Tween

local ae={}

local function ToFiniteNumber(af)
local ag=tonumber(af)
if ag==nil or ag~=ag or math.abs(ag)==math.huge then
return nil
end

return ag
end

local function FormatNumber(af)
if af%1==0 then
return tostring(af)
end

return tostring(tonumber(string.format("%.2f",af)))
end

function ae.New(af,ag)
local ah=typeof(ag.Value)=="table"and ag.Value or{}
local ai=ToFiniteNumber(ah.Min)or ToFiniteNumber(ag.Min)or 0
local aj=ToFiniteNumber(ah.Max)or ToFiniteNumber(ag.Max)or 100

if ai>aj then
ai,aj=aj,ai
end

local ak=typeof(ag.Value)=="number"and ag.Value
or ToFiniteNumber(ah.Default)
or ToFiniteNumber(ag.Default)
or ai
ak=ToFiniteNumber(ak)or ai

local al=ag.Indeterminate==true

local am=ag.ShowValue
if am==nil then
am=not al
end

local an=math.max(ToFiniteNumber(ag.ValueWidth)or 44,0)

local ao={
__type="ProgressBar",
Title=ag.Title or"Progress",
Desc=ag.Desc or nil,
Value={
Min=ai,
Max=aj,
Default=math.clamp(ak,ai,aj),
},
ShowValue=am,
DisplayMode=ag.DisplayMode or"Percent",
Format=ag.Format,
Animate=ag.Animate~=false,
AnimationDuration=math.max(ToFiniteNumber(ag.AnimationDuration)or 0.15,0),
Indeterminate=al,
IndeterminateText=ag.IndeterminateText or"",
Speed=math.max(ToFiniteNumber(ag.Speed)or 1,0.01),
ControlGap=math.max(ToFiniteNumber(ag.ControlGap)or 16,0),
UIElements={},

Width=math.max(ToFiniteNumber(ag.Width)or 160,0),
ValueWidth=an,
}

local function GetRatio(ap)
if ao.Value.Max==ao.Value.Min then
return ap>=ao.Value.Max and 1 or 0
end

return math.clamp((ap-ao.Value.Min)/(ao.Value.Max-ao.Value.Min),0,1)
end

local function GetValueText(ap,aq)
if ao.Indeterminate then
return tostring(ao.IndeterminateText)
end

local ar=aq*100

if typeof(ao.Format)=="function"then
local as,at=
pcall(ao.Format,ap,ar,ao.Value.Min,ao.Value.Max)

if as and at~=nil then
return tostring(at)
end
end

if ao.DisplayMode=="Value"then
return FormatNumber(ap)
elseif ao.DisplayMode=="Fraction"then
return FormatNumber(ap).."/"..FormatNumber(ao.Value.Max)
end

return tostring(math.floor(ar+0.5)).."%"
end

ao.ProgressBarFrame=a.load'C'{
Title=ao.Title,
Desc=ao.Desc,
Parent=ag.Parent,
TextOffset=ao.Width+ao.ControlGap,
Hover=false,
Tab=ag.Tab,
Index=ag.Index,
Window=ag.Window,
ElementTable=ao,
ParentConfig=ag,
Tags=ag.Tags,
}

ao.UIElements.Fill=aa.NewRoundFrame(99,"Squircle",{
Name="Fill",
Size=ao.Indeterminate and UDim2.new(0.3,0,1,0)
or UDim2.new(GetRatio(ao.Value.Default),0,1,0),
Position=ao.Indeterminate and UDim2.new(-0.3,0,0,0)or UDim2.new(0,0,0,0),
ThemeTag={
ImageColor3="ProgressBar",
},
})

ao.UIElements.Bar=aa.NewRoundFrame(99,"Squircle",{
Name="Bar",
Size=UDim2.new(1,ao.ShowValue and-(ao.ValueWidth+8)or 0,0,6),
ClipsDescendants=true,
ImageTransparency=0.9,
ThemeTag={
ImageColor3="ProgressBarTrack",
ImageTransparency="ProgressBarTrackTransparency",
},
},{
ao.UIElements.Fill,
})

ao.UIElements.Value=ac("TextLabel",{
Name="Value",
Size=UDim2.new(0,ao.ValueWidth,0,20),
BackgroundTransparency=1,
FontFace=Font.new(aa.Font,Enum.FontWeight.Medium),
Text=GetValueText(ao.Value.Default,GetRatio(ao.Value.Default)),
TextSize=14,
TextTransparency=0.25,
TextTruncate="AtEnd",
TextXAlignment="Right",
Visible=ao.ShowValue,
ThemeTag={
TextColor3="ProgressBarText",
},
})

ao.UIElements.Container=ac("Frame",{
Name="ProgressBarContainer",
Size=UDim2.new(0,ao.Width,0,36),
Position=UDim2.new(1,0,ag.Window.NewElements and 0 or 0.5,0),
AnchorPoint=Vector2.new(1,ag.Window.NewElements and 0 or 0.5),
BackgroundTransparency=1,
Parent=ao.ProgressBarFrame.UIElements.Main,
},{
ac("UIListLayout",{
Padding=UDim.new(0,8),
FillDirection="Horizontal",
HorizontalAlignment="Right",
VerticalAlignment="Center",
}),
ao.UIElements.Bar,
ao.UIElements.Value,
})

if ao.Indeterminate then
local ap=ad(
ao.UIElements.Fill,
1/ao.Speed,
{Position=UDim2.new(1,0,0,0)},
Enum.EasingStyle.Linear,
Enum.EasingDirection.InOut,-1

)
aa.AddSignal(ao.UIElements.Bar.Destroying,function()
ap:Cancel()
end)
ap:Play()
end

local function Update(ap,aq)
local ar=ToFiniteNumber(ap)
if ar==nil then
return ao.Value.Default
end

ar=math.clamp(ar,ao.Value.Min,ao.Value.Max)
ao.Value.Default=ar

local as=GetRatio(ar)
local at=UDim2.new(as,0,1,0)

if ao.UIElements.Fill and not ao.Indeterminate then
if aq or not ao.Animate or ao.AnimationDuration<=0 then
ao.UIElements.Fill.Size=at
else
ad(
ao.UIElements.Fill,
ao.AnimationDuration,
{Size=at},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
end
end

ao.UIElements.Value.Text=GetValueText(ar,as)

return ar
end

function ao.Set(ap,aq)
return Update(aq,false)
end

function ao.Get(ap)
return ao.Value.Default
end

function ao.GetPercentage(ap)
return GetRatio(ao.Value.Default)*100
end

function ao.SetRange(ap,aq,ar)
aq=ToFiniteNumber(aq)
ar=ToFiniteNumber(ar)

if aq==nil or ar==nil then
return ao.Value.Min,ao.Value.Max
end

if aq>ar then
aq,ar=ar,aq
end

ao.Value.Min=aq
ao.Value.Max=ar
Update(ao.Value.Default,false)

return aq,ar
end

function ao.SetMin(ap,aq)
aq=ToFiniteNumber(aq)
if aq==nil then
return ao.Value.Min
end

ao:SetRange(aq,math.max(aq,ao.Value.Max))
return ao.Value.Min
end

function ao.SetMax(ap,aq)
aq=ToFiniteNumber(aq)
if aq==nil then
return ao.Value.Max
end

ao:SetRange(math.min(ao.Value.Min,aq),aq)
return ao.Value.Max
end

Update(ao.Value.Default,true)

return ao.__type,ao
end

return ae end function a.K()

local aa=(cloneref or clonereference or function(aa)
return aa
end)

local ac=aa(game:GetService"UserInputService")

local ad=a.load'd'
local ae=ad.New local af=
ad.Tween

local ag={
UICorner=6,
UIPadding=8,
}

local ah=a.load'w'.New

function ag.New(ai,aj)
local function NormalizeKeyCode(ak)
if typeof(ak)=="EnumItem"then
return ak.Name
elseif type(ak)=="string"then
return ak
else
return"F"
end
end

local ak={
__type="Keybind",
Title=aj.Title or"Keybind",
Desc=aj.Desc or nil,
Locked=aj.Locked or false,
LockedTitle=aj.LockedTitle,
Value=NormalizeKeyCode(aj.Value)or"F",
Callback=aj.Callback or function()end,
CanChange=aj.CanChange~=false,
Blacklist=aj.Blacklist or{},
Picking=false,
UIElements={},
}

local al={}

for am,an in next,ak.Blacklist do
table.insert(al,Enum.KeyCode[NormalizeKeyCode(an)])
end
table.insert(al,Enum.KeyCode[NormalizeKeyCode"Escape"])

local am=true

ak.KeybindFrame=a.load'C'{
Title=ak.Title,
Desc=ak.Desc,
Parent=aj.Parent,
TextOffset=85,
Hover=ak.CanChange,
Tab=aj.Tab,
Index=aj.Index,
Window=aj.Window,
ElementTable=ak,
ParentConfig=aj,
Tags=aj.Tags,
}

ak.UIElements.Keybind=ah(
ak.Value,
nil,
ak.KeybindFrame.UIElements.Main,
nil,
aj.Window.NewElements and 12 or 10
)

ak.UIElements.Keybind.Size=
UDim2.new(0,24+ak.UIElements.Keybind.Frame.Frame.TextLabel.TextBounds.X,0,42)
ak.UIElements.Keybind.AnchorPoint=Vector2.new(1,0.5)
ak.UIElements.Keybind.Position=UDim2.new(1,0,0.5,0)
ak.UIElements.Keybind.Interactable=false

ae("UIScale",{
Parent=ak.UIElements.Keybind,
Scale=0.85,
})

ad.AddSignal(
ak.UIElements.Keybind.Frame.Frame.TextLabel:GetPropertyChangedSignal"TextBounds",
function()
ak.UIElements.Keybind.Size=
UDim2.new(0,24+ak.UIElements.Keybind.Frame.Frame.TextLabel.TextBounds.X,0,42)
end
)

function ak.Lock(an)
ak.Locked=true
am=false
return ak.KeybindFrame:Lock(ak.LockedTitle)
end
function ak.Unlock(an)
ak.Locked=false
am=true
return ak.KeybindFrame:Unlock()
end

function ak.Set(an,ao)
local ap=NormalizeKeyCode(ao)
ak.Value=ap
ak.UIElements.Keybind.Frame.Frame.TextLabel.Text=ap
end

if ak.Locked then
ak:Lock()
end

local an

ad.AddSignal(ak.KeybindFrame.UIElements.Main.MouseButton1Click,function()
if am then
if ak.CanChange then
ak.Picking=true
ak.UIElements.Keybind.Frame.Frame.TextLabel.Text="..."



local ao
ao=ac.InputBegan:Connect(function(ap)
local aq

if ap.UserInputType==Enum.UserInputType.Keyboard then
if table.find(al,ap.KeyCode)then
aq=nil
return
else
aq=ap.KeyCode.Name
end
elseif
ap.UserInputType==Enum.UserInputType.MouseButton1
and not table.find(al,"MouseLeftButton")
then
aq="MouseLeftButton"
elseif
ap.UserInputType==Enum.UserInputType.MouseButton2
and not table.find(al,"MouseRightButton")
then
aq="MouseRightButton"
end

if an then
an:Disconnect()
end

an=ac.InputEnded:Connect(function(ar)
if
aq
and(
ar.KeyCode.Name==aq
or aq=="MouseLeft"and ar.UserInputType==Enum.UserInputType.MouseButton1
or aq=="MouseRight"and ar.UserInputType==Enum.UserInputType.MouseButton2
)
then
ak.Picking=false

ak.UIElements.Keybind.Frame.Frame.TextLabel.Text=aq
ak.Value=aq

ao:Disconnect()
an:Disconnect()
end
end)
end)
end
end
end)

ad.AddSignal(ac.InputBegan,function(ao,ap)
if ac:GetFocusedTextBox()then
return
end
if not am then
return
end
if ak.Picking then
return
end

if ao.UserInputType==Enum.UserInputType.Keyboard then
if ao.KeyCode.Name==ak.Value then
ad.SafeCallback(ak.Callback,ao.KeyCode.Name)
end
elseif ao.UserInputType==Enum.UserInputType.MouseButton1 and ak.Value=="MouseLeft"then
ad.SafeCallback(ak.Callback,"MouseLeft")
elseif ao.UserInputType==Enum.UserInputType.MouseButton2 and ak.Value=="MouseRight"then
ad.SafeCallback(ak.Callback,"MouseRight")
end
end)

return ak.__type,ak
end

return ag end function a.L()

local aa=a.load'd'local ac=
aa.New local ad=
aa.Tween

local ae={
UICorner=8,
UIPadding=8,
}local af=a.load'm'

.New
local ag=a.load'n'.New

function ae.New(ah,ai)
local aj={
__type="Input",
Title=ai.Title or"Input",
Desc=ai.Desc or nil,
Type=ai.Type or"Input",
Locked=ai.Locked or false,
LockedTitle=ai.LockedTitle,
InputIcon=ai.InputIcon or false,
Placeholder=ai.Placeholder or"Enter Text...",
Value=ai.Value or"",
Callback=ai.Callback or function()end,
ClearTextOnFocus=ai.ClearTextOnFocus or false,
UIElements={},

Width=150,
}

local ak=true

aj.InputFrame=a.load'C'{
Title=aj.Title,
Desc=aj.Desc,
Parent=ai.Parent,
TextOffset=aj.Width,
Hover=false,
Tab=ai.Tab,
Index=ai.Index,
Window=ai.Window,
ElementTable=aj,
ParentConfig=ai,
Tags=ai.Tags,
}

local al=ag(
aj.Placeholder,
aj.InputIcon,
aj.Type=="Textarea"and aj.InputFrame.UIElements.Container or aj.InputFrame.UIElements.Main,
aj.Type,
function(al)
aj:Set(al,true)
end,
nil,
ai.Window.NewElements and 12 or 10,
aj.ClearTextOnFocus
)

if aj.Type~="Textarea"then
al.Size=UDim2.new(0,aj.Width,0,36)
al.Position=UDim2.new(1,0,ai.Window.NewElements and 0 or 0.5,0)
al.AnchorPoint=Vector2.new(1,ai.Window.NewElements and 0 or 0.5)
else
al.Size=UDim2.new(1,0,0,148)
end






function aj.Lock(am)
aj.Locked=true
ak=false
return aj.InputFrame:Lock(aj.LockedTitle)
end
function aj.Unlock(am)
aj.Locked=false
ak=true
return aj.InputFrame:Unlock()
end

function aj.Set(am,an,ao)
if ak then
aj.Value=an
aa.SafeCallback(aj.Callback,an)

if not ao then
al.Frame.Frame.TextBox.Text=an
end
end
end

function aj.SetPlaceholder(am,an)
al.Frame.Frame.TextBox.PlaceholderText=an
aj.Placeholder=an
end

aj:Set(aj.Value)

if aj.Locked then
aj:Lock()
end

return aj.__type,aj
end

return ae end function a.M()

local aa=a.load'd'
local ae=aa.New

local af={}

function af.New(ag,ah)
local ai=ae("Frame",{
Size=ah.ParentType~="Group"and UDim2.new(1,0,0,1)or UDim2.new(0,1,1,0),
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
BackgroundTransparency=.9,
ThemeTag={
BackgroundColor3="Text"
}
})
local aj=ae("Frame",{
Parent=ah.Parent,
Size=ah.ParentType~="Group"and UDim2.new(1,-7,0,7)or UDim2.new(0,7,1,-7),
BackgroundTransparency=1,
},{
ai
})

return"Divider",{__type="Divider",ElementFrame=aj}
end

return af end function a.N()
local aa={}

local ae=(cloneref or clonereference or function(ae)
return ae
end)

local af=ae(game:GetService"UserInputService")
local ag=ae(game:GetService"Players").LocalPlayer:GetMouse()
local ah=ae(game:GetService"Workspace").CurrentCamera local ai=

workspace.CurrentCamera

local aj=a.load'n'.New

local ak=a.load'd'
local al=ak.New
local am=ak.Tween

local an=0.67

function aa.New(ao,ap,aq,ar)
local as={}

if not ap.Callback then
ar="Menu"
end

ap.UIElements.UIListLayout=al("UIListLayout",{
Padding=UDim.new(0,aq.MenuPadding/1.5),
FillDirection="Vertical",
HorizontalAlignment="Center",
})

ap.UIElements.Menu=ak.NewRoundFrame(aq.MenuCorner,"Squircle",{
ThemeTag={
ImageColor3="DropdownBackground",
},
ImageTransparency=1,
Size=UDim2.new(1,0,1,0),
AnchorPoint=Vector2.new(1,0),
Position=UDim2.new(1,0,0,0),
},{
al("UIPadding",{
PaddingTop=UDim.new(0,aq.MenuPadding),
PaddingLeft=UDim.new(0,aq.MenuPadding),
PaddingRight=UDim.new(0,aq.MenuPadding),
PaddingBottom=UDim.new(0,aq.MenuPadding),
}),
al("UIListLayout",{
FillDirection="Vertical",
Padding=UDim.new(0,aq.MenuPadding),
}),
al("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,1,ap.SearchBarEnabled and-aq.MenuPadding-aq.SearchBarHeight),

ClipsDescendants=true,
LayoutOrder=999,
Name="Frame",
},{
al("UICorner",{
CornerRadius=UDim.new(0,aq.MenuCorner-aq.MenuPadding),
}),
al("ScrollingFrame",{
Size=UDim2.new(1,0,1,0),
ScrollBarThickness=0,
ScrollingDirection="Y",
AutomaticCanvasSize="Y",
CanvasSize=UDim2.new(0,0,0,0),
BackgroundTransparency=1,
ScrollBarImageTransparency=1,
},{
ap.UIElements.UIListLayout,
}),
}),
})

ap.UIElements.MenuCanvas=al("Frame",{
Size=UDim2.new(0,ap.MenuWidth,0,300),
BackgroundTransparency=1,
Position=UDim2.new(-10,0,-10,0),
Visible=false,
Active=false,

Parent=ao.WindUI.DropdownGui,
AnchorPoint=Vector2.new(1,0),
},{
ap.UIElements.Menu,
al("UISizeConstraint",{
MinSize=Vector2.new(170,0),
MaxSize=Vector2.new(300,400),
}),
})

local function RecalculateCanvasSize()
ap.UIElements.Menu.Frame.ScrollingFrame.CanvasSize=
UDim2.fromOffset(0,ap.UIElements.UIListLayout.AbsoluteContentSize.Y)
end

local function RecalculateListSize()
local at=ao.WindUI.DropdownGui.AbsoluteSize.Y

local au=ap.UIElements.UIListLayout.AbsoluteContentSize.Y/ao.UIScale
local av=ap.SearchBarEnabled and(aq.SearchBarHeight+(aq.MenuPadding*3))
or(aq.MenuPadding*2)
local aw=au+av

if aw>at then
ap.UIElements.MenuCanvas.Size=
UDim2.fromOffset(ap.UIElements.MenuCanvas.AbsoluteSize.X,at)
else
ap.UIElements.MenuCanvas.Size=
UDim2.fromOffset(ap.UIElements.MenuCanvas.AbsoluteSize.X,aw)
end
end

function UpdatePosition()
local at=ap.UIElements.Dropdown or ap.DropdownFrame.UIElements.Main
local au=ap.UIElements.MenuCanvas

local av=ah.ViewportSize.Y
-(at.AbsolutePosition.Y+at.AbsoluteSize.Y)
-aq.MenuPadding
-54
local aw=au.AbsoluteSize.Y+aq.MenuPadding

local ax=-54
if av<aw then
ax=aw-av-54
end

au.Position=UDim2.new(
0,
at.AbsolutePosition.X+at.AbsoluteSize.X,
0,
at.AbsolutePosition.Y+at.AbsoluteSize.Y-ax+(aq.MenuPadding*2)
)
end

local at

function as.Display(au)
local av=ap.Values
local aw=""

if ap.Multi then
local ax={}
if typeof(ap.Value)=="table"then
for ay,az in ipairs(ap.Value)do
local aA=typeof(az)=="table"and az.Title or az
ax[aA]=true
end
end

for ay,az in ipairs(av)do
local aA=typeof(az)=="table"and az.Title or az
if ax[aA]then
aw=aw..aA..", "
end
end

if#aw>0 then
aw=aw:sub(1,#aw-2)
end
else
aw=typeof(ap.Value)=="table"and(ap.Value.Title or ap.Value[1])
or ap.Value
or""
end

if ap.UIElements.Dropdown then
ap.UIElements.Dropdown.Frame.Frame.TextLabel.Text=(aw==""and"--"or aw)
end
end

local function Callback(au)
as:Display()
if ap.Locked then
return
end

if ap.Callback then
task.spawn(function()
if ap.Locked then
return
end
ak.SafeCallback(ap.Callback,ap.Value)
end)
else
task.spawn(function()
if ap.Locked then
return
end
ak.SafeCallback(au)
end)
end
end

function as.LockValues(au,av)
if not av then
return
end

for aw,ax in next,ap.Tabs do
if ax and ax.UIElements and ax.UIElements.TabItem then
local ay=ax.Name
local az=false

for aA,aB in next,av do
if ay==aB then
az=true
break
end
end

if az then
am(ax.UIElements.TabItem,0.1,{ImageTransparency=1}):Play()

am(ax.UIElements.TabItem.Frame.Title.TextLabel,0.1,{TextTransparency=0.6}):Play()
if ax.UIElements.TabIcon then
am(ax.UIElements.TabIcon.ImageLabel,0.1,{ImageTransparency=0.6}):Play()
end

ax.UIElements.TabItem.Active=false
ax.Locked=true
else
if ax.Selected then
am(ax.UIElements.TabItem,0.1,{ImageTransparency=an}):Play()

am(ax.UIElements.TabItem.Frame.Title.TextLabel,0.1,{TextTransparency=0}):Play()
if ax.UIElements.TabIcon then
am(ax.UIElements.TabIcon.ImageLabel,0.1,{ImageTransparency=0}):Play()
end
else
am(ax.UIElements.TabItem,0.1,{ImageTransparency=1}):Play()

am(
ax.UIElements.TabItem.Frame.Title.TextLabel,
0.1,
{TextTransparency=ar=="Dropdown"and 0.4 or 0.05}
):Play()
if ax.UIElements.TabIcon then
am(
ax.UIElements.TabIcon.ImageLabel,
0.1,
{ImageTransparency=ar=="Dropdown"and 0.2 or 0}
):Play()
end
end

ax.UIElements.TabItem.Active=true
ax.Locked=false
end
end
end
end

function as.Refresh(au,av)
if ao.Window.Destroyed then
return
end

for aw,ax in next,ap.UIElements.Menu.Frame.ScrollingFrame:GetChildren()do
if not ax:IsA"UIListLayout"then
ax:Destroy()
end
end

ap.Tabs={}

if ap.SearchBarEnabled then
if not at then
at=aj("Search...","search",ap.UIElements.Menu,nil,function(aw)
for ax,ay in next,ap.Tabs do
if string.find(string.lower(ay.Name),string.lower(aw),1,true)then
ay.UIElements.TabItem.Visible=true
else
ay.UIElements.TabItem.Visible=false
end
RecalculateListSize()
RecalculateCanvasSize()
end
end,true)
at.Size=UDim2.new(1,0,0,aq.SearchBarHeight)
at.Position=UDim2.new(0,0,0,0)
at.Name="SearchBar"
end
end

for aw,ax in next,av do
if ax.Type~="Divider"then
local ay={
Name=typeof(ax)=="table"and ax.Title or ax,
Desc=typeof(ax)=="table"and ax.Desc or nil,
Icon=typeof(ax)=="table"and ax.Icon or nil,
IconSize=typeof(ax)=="table"and ax.IconSize or nil,
Original=ax,
Selected=false,
Locked=typeof(ax)=="table"and ax.Locked or false,
UIElements={},
}
local az
if ay.Icon then
az=ak.Image(ay.Icon,ay.Icon,0,ao.Window.Folder,"Dropdown",true)
az.Size=
UDim2.new(0,ay.IconSize or aq.TabIcon,0,ay.IconSize or aq.TabIcon)
az.ImageLabel.ImageTransparency=ar=="Dropdown"and 0.2 or 0
ay.UIElements.TabIcon=az
end
ay.UIElements.TabItem=ak.NewRoundFrame(
aq.MenuCorner-aq.MenuPadding,
"Squircle",
{
Size=UDim2.new(1,0,0,36),
AutomaticSize=ay.Desc and"Y",
ImageTransparency=1,
Parent=ap.UIElements.Menu.Frame.ScrollingFrame,

ThemeTag={
ImageColor3="DropdownTabBackground",
},
Active=not ay.Locked,
},
{
ak.NewRoundFrame(aq.MenuCorner-aq.MenuPadding,"Glass-1.4",{
Size=UDim2.new(1,0,1,0),
ThemeTag={
ImageColor3="DropdownTabBorder",
},
ImageTransparency=1,
Name="Highlight",
},{













}),
al("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
},{
al("UIListLayout",{
Padding=UDim.new(0,aq.TabPadding),
FillDirection="Horizontal",
VerticalAlignment="Center",
}),
al("UIPadding",{
PaddingTop=UDim.new(0,aq.TabPadding),
PaddingLeft=UDim.new(0,aq.TabPadding),
PaddingRight=UDim.new(0,aq.TabPadding),
PaddingBottom=UDim.new(0,aq.TabPadding),
}),
al("UICorner",{
CornerRadius=UDim.new(0,aq.MenuCorner-aq.MenuPadding),
}),
az,
al("Frame",{
Size=UDim2.new(1,az and-aq.TabPadding-aq.TabIcon or 0,0,0),
BackgroundTransparency=1,
AutomaticSize="Y",
Name="Title",
},{
al("TextLabel",{
Text=ay.Name,
TextXAlignment="Left",
FontFace=Font.new(ak.Font,Enum.FontWeight.Medium),
ThemeTag={
TextColor3="Text",
BackgroundColor3="Text",
},
TextSize=15,
BackgroundTransparency=1,
TextTransparency=ar=="Dropdown"and 0.4 or 0.05,
LayoutOrder=999,
AutomaticSize="Y",
Size=UDim2.new(1,0,0,0),
}),
al("TextLabel",{
Text=ay.Desc or"",
TextXAlignment="Left",
FontFace=Font.new(ak.Font,Enum.FontWeight.Regular),
ThemeTag={
TextColor3="Text",
BackgroundColor3="Text",
},
TextSize=15,
BackgroundTransparency=1,
TextTransparency=ar=="Dropdown"and 0.6 or 0.35,
LayoutOrder=999,
AutomaticSize="Y",
TextWrapped=true,
Size=UDim2.new(1,0,0,0),
Visible=ay.Desc and true or false,
Name="Desc",
}),
al("UIListLayout",{
Padding=UDim.new(0,aq.TabPadding/3),
FillDirection="Vertical",
}),
}),
}),
},
true
)

if ay.Locked then
ay.UIElements.TabItem.Frame.Title.TextLabel.TextTransparency=0.6
if ay.UIElements.TabIcon then
ay.UIElements.TabIcon.ImageLabel.ImageTransparency=0.6
end
end

if ap.Multi and typeof(ap.Value)=="string"then
for aA,aB in next,ap.Values do
if typeof(aB)=="table"then
if aB.Title==ap.Value then
ap.Value={aB}
end
else
if aB==ap.Value then
ap.Value={ap.Value}
end
end
end
end

if ap.Multi then
local aA=false
if typeof(ap.Value)=="table"then
for aB,b in ipairs(ap.Value)do
local d=typeof(b)=="table"and b.Title or b
if d==ay.Name then
aA=true
break
end
end
end
ay.Selected=aA
else
local aA=typeof(ap.Value)=="table"and ap.Value.Title or ap.Value
ay.Selected=aA==ay.Name
end

if ay.Selected and not ay.Locked then
ay.UIElements.TabItem.ImageTransparency=an

ay.UIElements.TabItem.Frame.Title.TextLabel.TextTransparency=0
if ay.UIElements.TabIcon then
ay.UIElements.TabIcon.ImageLabel.ImageTransparency=0
end
end

ap.Tabs[aw]=ay

as:Display()

if ar=="Dropdown"then
ak.AddSignal(ay.UIElements.TabItem.MouseButton1Click,function()
if ap.Locked or ay.Locked then
return
end

if ap.Multi then
if not ay.Selected then
ay.Selected=true
am(
ay.UIElements.TabItem,
0.1,
{ImageTransparency=an}
):Play()

am(ay.UIElements.TabItem.Frame.Title.TextLabel,0.1,{TextTransparency=0}):Play()
if ay.UIElements.TabIcon then
am(ay.UIElements.TabIcon.ImageLabel,0.1,{ImageTransparency=0}):Play()
end
table.insert(ap.Value,ay.Original)
else
if not ap.AllowNone and#ap.Value==1 then
return
end
ay.Selected=false
am(ay.UIElements.TabItem,0.1,{ImageTransparency=1}):Play()

am(ay.UIElements.TabItem.Frame.Title.TextLabel,0.1,{TextTransparency=0.4}):Play()
if ay.UIElements.TabIcon then
am(ay.UIElements.TabIcon.ImageLabel,0.1,{ImageTransparency=0.2}):Play()
end

for aA,aB in next,ap.Value do
if typeof(aB)=="table"and(aB.Title==ay.Name)or(aB==ay.Name)then
table.remove(ap.Value,aA)
break
end
end
end
else
for aA,aB in next,ap.Tabs do
am(aB.UIElements.TabItem,0.1,{ImageTransparency=1}):Play()

am(
aB.UIElements.TabItem.Frame.Title.TextLabel,
0.1,
{TextTransparency=0.4}
):Play()
if aB.UIElements.TabIcon then
am(aB.UIElements.TabIcon.ImageLabel,0.1,{ImageTransparency=0.2}):Play()
end
aB.Selected=false
end
ay.Selected=true
am(ay.UIElements.TabItem,0.1,{ImageTransparency=an}):Play()

am(ay.UIElements.TabItem.Frame.Title.TextLabel,0.1,{TextTransparency=0}):Play()
if ay.UIElements.TabIcon then
am(ay.UIElements.TabIcon.ImageLabel,0.1,{ImageTransparency=0}):Play()
end
ap.Value=ay.Original
end
Callback()
end)
elseif ar=="Menu"then
if not ay.Locked then
ak.AddSignal(ay.UIElements.TabItem.MouseEnter,function()
am(ay.UIElements.TabItem,0.08,{ImageTransparency=an}):Play()
end)
ak.AddSignal(ay.UIElements.TabItem.InputEnded,function()
am(ay.UIElements.TabItem,0.08,{ImageTransparency=1}):Play()
end)
end
ak.AddSignal(ay.UIElements.TabItem.MouseButton1Click,function()
if ap.Locked or ay.Locked then
return
end
Callback(ax.Callback or function()end)
end)
end

RecalculateCanvasSize()
RecalculateListSize()
else a.load'M'
:New{Parent=ap.UIElements.Menu.Frame.ScrollingFrame}
end
end










ap.UIElements.MenuCanvas.Size=UDim2.new(
0,
ap.MenuWidth+6+6+5+5+18+6+6,
ap.UIElements.MenuCanvas.Size.Y.Scale,
ap.UIElements.MenuCanvas.Size.Y.Offset
)
Callback()

ap.Values=av
end

as:Refresh(ap.Values)

function as.Select(au,av)
if av then
ap.Value=av
else
if ap.Multi then
ap.Value={}
else
ap.Value=nil
end
end
as:Refresh(ap.Values)
end

RecalculateListSize()
RecalculateCanvasSize()

function as.Open(au)
if not ap.Locked then
ap.UIElements.Menu.Visible=true
ap.UIElements.MenuCanvas.Visible=true
ap.UIElements.MenuCanvas.Active=true
ap.UIElements.Menu.Size=UDim2.new(1,0,0,0)
am(ap.UIElements.Menu,0.1,{
Size=UDim2.new(1,0,1,0),
ImageTransparency=0,
},Enum.EasingStyle.Quart,Enum.EasingDirection.Out):Play()

task.spawn(function()
task.wait(0.1)
if ap.Locked then
return
end
ap.Opened=true
end)

UpdatePosition()
end
end

function as.Close(au)
ap.Opened=false

am(ap.UIElements.Menu,0.25,{
Size=UDim2.new(1,0,0,0),
ImageTransparency=1,
},Enum.EasingStyle.Quart,Enum.EasingDirection.Out):Play()

task.spawn(function()
task.wait(0.1)
ap.UIElements.Menu.Visible=false
end)

task.spawn(function()
task.wait(0.25)
ap.UIElements.MenuCanvas.Visible=false
ap.UIElements.MenuCanvas.Active=false
end)
end

ak.AddSignal(
(
ap.UIElements.Dropdown and ap.UIElements.Dropdown.MouseButton1Click
or ap.DropdownFrame.UIElements.Main.MouseButton1Click
),
function()
as:Open()
end
)

ak.AddSignal(af.InputBegan,function(au)
if
au.UserInputType==Enum.UserInputType.MouseButton1
or au.UserInputType==Enum.UserInputType.Touch
then
local av=ap.UIElements.MenuCanvas
local aw,ax=av.AbsolutePosition,av.AbsoluteSize

local ay=ap.UIElements.Dropdown or ap.DropdownFrame.UIElements.Main
local az=ay.AbsolutePosition
local aA=ay.AbsoluteSize

local aB=ag.X>=az.X
and ag.X<=az.X+aA.X
and ag.Y>=az.Y
and ag.Y<=az.Y+aA.Y

local b=ag.X>=aw.X
and ag.X<=aw.X+ax.X
and ag.Y>=aw.Y
and ag.Y<=aw.Y+ax.Y

if ao.Window.CanDropdown and ap.Opened and not aB and not b then
as:Close()
end
end
end)

ak.AddSignal(
ap.UIElements.Dropdown and ap.UIElements.Dropdown:GetPropertyChangedSignal"AbsolutePosition"
or ap.DropdownFrame.UIElements.Main:GetPropertyChangedSignal"AbsolutePosition",
UpdatePosition
)

return as
end

return aa end function a.O()

local aa=(cloneref or clonereference or function(aa)
return aa
end)

aa(game:GetService"UserInputService")
aa(game:GetService"Players").LocalPlayer:GetMouse()local ae=
aa(game:GetService"Workspace").CurrentCamera

local af=a.load'd'
local ag=af.New local ah=
af.Tween

local ai=a.load'w'.New local aj=a.load'n'
.New
local ak=a.load'N'.New local al=

workspace.CurrentCamera

local am={
UICorner=10,
UIPadding=12,
MenuCorner=15,
MenuPadding=5,
TabPadding=10,
SearchBarHeight=39,
TabIcon=18,
}

function am.New(an,ao)
local ap={
__type="Dropdown",
Title=ao.Title or"Dropdown",
Desc=ao.Desc or nil,
Locked=ao.Locked or false,
LockedTitle=ao.LockedTitle,
Values=ao.Values or{},
MenuWidth=ao.MenuWidth or 180,
Value=ao.Value,
AllowNone=ao.AllowNone,
SearchBarEnabled=ao.SearchBarEnabled or false,
Multi=ao.Multi,
Callback=ao.Callback or nil,

UIElements={},

Opened=false,
Tabs={},

Width=150,
}

if ap.Multi and not ap.Value then
ap.Value={}
end
if ap.Values and typeof(ap.Value)=="number"then
ap.Value=ap.Values[ap.Value]
end

ap.DropdownFrame=a.load'C'{
Title=ap.Title,
Desc=ap.Desc,
Parent=ao.Parent,
TextOffset=ap.Callback and ap.Width or 20,
Hover=not ap.Callback and true or false,
Tab=ao.Tab,
Index=ao.Index,
Window=ao.Window,
ElementTable=ap,
ParentConfig=ao,
Tags=ao.Tags,
}

if ap.Callback then
ap.UIElements.Dropdown=
ai("",nil,ap.DropdownFrame.UIElements.Main,nil,ao.Window.NewElements and 12 or 10)

ap.UIElements.Dropdown.Frame.Frame.TextLabel.TextTruncate="AtEnd"
ap.UIElements.Dropdown.Frame.Frame.TextLabel.Size=
UDim2.new(1,ap.UIElements.Dropdown.Frame.Frame.TextLabel.Size.X.Offset-18-12-12,0,0)

ap.UIElements.Dropdown.Size=UDim2.new(0,ap.Width,0,36)
ap.UIElements.Dropdown.Position=UDim2.new(1,0,ao.Window.NewElements and 0 or 0.5,0)
ap.UIElements.Dropdown.AnchorPoint=Vector2.new(1,ao.Window.NewElements and 0 or 0.5)





end

ap.DropdownMenu=ak(ao,ap,am,"Dropdown")

ap.Display=ap.DropdownMenu.Display
ap.Refresh=ap.DropdownMenu.Refresh
ap.Select=ap.DropdownMenu.Select
ap.Open=ap.DropdownMenu.Open
ap.Close=ap.DropdownMenu.Close

ag("ImageLabel",{
Image=af.Icon"chevrons-up-down"[1],
ImageRectOffset=af.Icon"chevrons-up-down"[2].ImageRectPosition,
ImageRectSize=af.Icon"chevrons-up-down"[2].ImageRectSize,
Size=UDim2.new(0,18,0,18),
Position=UDim2.new(1,ap.UIElements.Dropdown and-12 or 0,0.5,0),
ThemeTag={
ImageColor3="Icon",
},
AnchorPoint=Vector2.new(1,0.5),
Parent=ap.UIElements.Dropdown and ap.UIElements.Dropdown.Frame
or ap.DropdownFrame.UIElements.Main,
})

function ap.Lock(aq)
ap.Locked=true
if ap.Opened or ap.UIElements.MenuCanvas.Visible then
ap:Close()
end
return ap.DropdownFrame:Lock(ap.LockedTitle)
end
function ap.Unlock(aq)
ap.Locked=false
return ap.DropdownFrame:Unlock()
end

if ap.Locked then
ap:Lock()
end

return ap.__type,ap
end

return am end function a.P()




local aa={}
local af={
lua={
"and",
"break",
"or",
"else",
"elseif",
"if",
"then",
"until",
"repeat",
"while",
"do",
"for",
"in",
"end",
"local",
"return",
"function",
"export",
},
rbx={
"game",
"workspace",
"script",
"math",
"string",
"table",
"task",
"wait",
"select",
"next",
"Enum",
"tick",
"assert",
"shared",
"loadstring",
"tonumber",
"tostring",
"type",
"typeof",
"unpack",
"Instance",
"CFrame",
"Vector3",
"Vector2",
"Color3",
"UDim",
"UDim2",
"Ray",
"BrickColor",
"OverlapParams",
"RaycastParams",
"Axes",
"Random",
"Region3",
"Rect",
"TweenInfo",
"collectgarbage",
"not",
"utf8",
"pcall",
"xpcall",
"_G",
"setmetatable",
"getmetatable",
"os",
"pairs",
"ipairs",
},
operators={
"#",
"+",
"-",
"*",
"%",
"/",
"^",
"=",
"~",
"=",
"<",
">",
},
}

local ag={
numbers=Color3.fromHex"#FAB387",
boolean=Color3.fromHex"#FAB387",
operator=Color3.fromHex"#94E2D5",
lua=Color3.fromHex"#CBA6F7",
rbx=Color3.fromHex"#F38BA8",
str=Color3.fromHex"#A6E3A1",
comment=Color3.fromHex"#9399B2",
null=Color3.fromHex"#F38BA8",
call=Color3.fromHex"#89B4FA",
self_call=Color3.fromHex"#89B4FA",
local_property=Color3.fromHex"#CBA6F7",
}

local function createKeywordSet(ai)
local ak={}
for al,am in ipairs(ai)do
ak[am]=true
end
return ak
end

local ai=createKeywordSet(af.lua)
local ak=createKeywordSet(af.rbx)
local al=createKeywordSet(af.operators)

local function getHighlight(am,an)
local ao=am[an]

if ag[ao.."_color"]then
return ag[ao.."_color"]
end

if tonumber(ao)then
return ag.numbers
elseif ao=="nil"then
return ag.null
elseif ao:sub(1,2)=="--"then
return ag.comment
elseif al[ao]then
return ag.operator
elseif ai[ao]then
return ag.lua
elseif ak[ao]then
return ag.rbx
elseif ao:sub(1,1)=='"'or ao:sub(1,1)=="'"then
return ag.str
elseif ao=="true"or ao=="false"then
return ag.boolean
end

if am[an+1]=="("then
if am[an-1]==":"then
return ag.self_call
end

return ag.call
end

if am[an-1]=="."then
if am[an-2]=="Enum"then
return ag.rbx
end

return ag.local_property
end
end

function aa.run(am,an)
if an~=nil then
for ao,ap in next,an do
ag[ao]=ap
end
end

local ao={}
local ap=""

local aq=false
local ar=false
local as=false

for at=1,#am do
local au=am:sub(at,at)

if ar then
if au=="\n"and not as then
table.insert(ao,ap)
table.insert(ao,au)
ap=""

ar=false
elseif am:sub(at-1,at)=="]]"and as then
ap=ap.."]"

table.insert(ao,ap)
ap=""

ar=false
as=false
else
ap=ap..au
end
elseif aq then
if au==aq and am:sub(at-1,at-1)~="\\"or au=="\n"then
ap=ap..au
aq=false
else
ap=ap..au
end
else
if am:sub(at,at+1)=="--"then
table.insert(ao,ap)
ap="-"
ar=true
as=am:sub(at+2,at+3)=="[["
elseif au=='"'or au=="'"then
table.insert(ao,ap)
ap=au
aq=au
elseif al[au]then
table.insert(ao,ap)
table.insert(ao,au)
ap=""
elseif au:match"[%w_]"then
ap=ap..au
else
table.insert(ao,ap)
table.insert(ao,au)
ap=""
end
end
end

table.insert(ao,ap)

local at={}

for au,av in ipairs(ao)do
local aw=getHighlight(ao,au)

if aw then
local ax=string.format(
'<font color = "#%s">%s</font>',
aw:ToHex(),
av:gsub("<","&lt;"):gsub(">","&gt;")
)

table.insert(at,ax)
else
table.insert(at,av)
end
end

return table.concat(at)
end

return aa end function a.Q()

local aa={}

local af=a.load'd'
local ag=af.New
local ai=af.Tween

local ak=a.load'P'

function aa.New(al,am,an,ao,ap)
local aq={
Radius=am.ElementConfig.UICorner,
Padding=am.NewElements and am.ElementConfig.UIPadding+4 or am.ElementConfig.UIPadding,

CodeFrame=nil,
}

local ar=ag("TextLabel",{
Text="",
TextColor3=Color3.fromHex"#CDD6F4",
TextTransparency=0,
TextSize=al.CodeSize,
TextWrapped=false,
LineHeight=1.15,
RichText=true,
TextXAlignment="Left",
Size=UDim2.new(0,0,0,0),
BackgroundTransparency=1,
AutomaticSize="XY",
},{
ag("UIPadding",{
PaddingTop=UDim.new(0,aq.Padding+3),
PaddingLeft=UDim.new(0,aq.Padding+3),
PaddingRight=UDim.new(0,aq.Padding+3),
PaddingBottom=UDim.new(0,aq.Padding+3),
}),
})
ar.Font="Code"

local as=ag("ScrollingFrame",{
Size=UDim2.new(1,0,0,0),
BackgroundTransparency=1,
AutomaticCanvasSize=al.Height~=nil and"XY"or"X",
ScrollingDirection=al.Height~=nil and"XY"or"X",
ElasticBehavior="Never",
CanvasSize=UDim2.new(0,0,0,0),
ScrollBarThickness=0,
},{
ar,
})

local at=al.CanCopied
and ag("TextButton",{
BackgroundTransparency=1,
Size=UDim2.new(0,35,0,35),
Position=UDim2.new(1,-aq.Padding/2,0,aq.Padding/2),
AnchorPoint=Vector2.new(1,0),
Visible=ao and true or false,
},{
af.NewRoundFrame(aq.Radius-4,"Squircle",{



ImageColor3=Color3.fromHex"#ffffff",
ImageTransparency=1,
Size=UDim2.new(1,0,1,0),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Name="Button",
},{
ag("UIScale",{
Scale=1,
}),
ag("ImageLabel",{
Image=af.Icon"copy"[1],
ImageRectSize=af.Icon"copy"[2].ImageRectSize,
ImageRectOffset=af.Icon"copy"[2].ImageRectPosition,
BackgroundTransparency=1,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Size=UDim2.new(0,12,0,12),



ImageColor3=Color3.fromHex"#ffffff",
ImageTransparency=0.1,
}),
}),
})
or nil

local au,av=af.NewRoundFrame(aq.Radius,"SquircleOutline",{
Size=UDim2.new(1,0,1,0),



ImageColor3=Color3.fromHex"#ffffff",
ImageTransparency=0.955,
Visible=false,
})

local aw,ax=af.NewRoundFrame(aq.Radius,"Squircle-TL-TR",{



ImageColor3=Color3.fromHex"#ffffff",
ImageTransparency=0.96,
Size=UDim2.new(1,0,0,20+(aq.Padding*2)),
Visible=al.Title and true or false,
},{










ag("TextLabel",{
Text=al.Title,



TextColor3=Color3.fromHex"#ffffff",
TextTransparency=0.2,
TextSize=18,
AutomaticSize="Y",
FontFace=Font.new(af.Font,Enum.FontWeight.Medium),
TextXAlignment="Left",
BackgroundTransparency=1,
TextTruncate="AtEnd",
Size=UDim2.new(1,at and-20-(aq.Padding*2),0,0),
}),
ag("UIPadding",{

PaddingLeft=UDim.new(0,aq.Padding+3),
PaddingRight=UDim.new(0,aq.Padding+3),

}),
ag("UIListLayout",{
Padding=UDim.new(0,aq.Padding),
FillDirection="Horizontal",
VerticalAlignment="Center",
}),
})

local ay,az=af.NewRoundFrame(aq.Radius,"Squircle",{



ImageColor3=Color3.fromHex"#212121",
ImageTransparency=0.035,
Size=al.Height~=nil
and UDim2.new(1,0,al.Height.Scale,al.Height.Offset==0 and-40 or al.Height.Offset)
or UDim2.new(1,0,0,20+(aq.Padding*2)),
AutomaticSize=al.Height~=nil and"None"or"Y",
Parent=an,
},{
au,
ag("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,al.Height~=nil and 1 or 0,0),
AutomaticSize=al.Height~=nil and"None"or"Y",
},{
aw,
as,
ag("UIListLayout",{
Padding=UDim.new(0,0),
FillDirection="Vertical",
}),
}),
at,
},nil,true)

aq.CodeFrame=ay
aq.CodeFrameModule=az
aq.OutlineFrame=au
aq.OutlineFrameModule=av
aq.TopbarFrame=aw
aq.TopbarFrameModule=ax

af.AddSignal(ar:GetPropertyChangedSignal"TextBounds",function()
if al.Height~=nil then
as.Size=UDim2.new(1,0,1,al.Title~=nil and-(20+(aq.Padding*2))or nil)
else
as.Size=
UDim2.new(1,0,0,(ar.TextBounds.Y/(ap or 1))+((aq.Padding+3)*2))
end
end)

function aq.Set(aA)
ar.Text=ak.run(aA,al.CodeTheme)
end

function aq.Destroy()
ay:Destroy()
aq=nil
end

aq.Set(al.Code)

if at then
af.AddSignal(at.InputBegan,function(aA:InputObject)
if
aA.UserInputType==Enum.UserInputType.MouseButton1
or aA.UserInputType==Enum.UserInputType.Touch
then
ai(at.Button,0.05,{ImageTransparency=0.95}):Play()
ai(at.Button.UIScale,0.05,{Scale=0.9}):Play()
end
end)
af.AddSignal(at.InputEnded,function()
ai(at.Button,0.08,{ImageTransparency=1}):Play()
ai(at.Button.UIScale,0.08,{Scale=1}):Play()
end)
af.AddSignal(at.MouseButton1Click,function()
if ao then
ao()
local aA=af.Icon"check"
at.Button.ImageLabel.Image=aA[1]
at.Button.ImageLabel.ImageRectSize=aA[2].ImageRectSize
at.Button.ImageLabel.ImageRectOffset=aA[2].ImageRectPosition

task.delay(1,function()
local aB=af.Icon"copy"
at.Button.ImageLabel.Image=aB[1]
at.Button.ImageLabel.ImageRectSize=aB[2].ImageRectSize
at.Button.ImageLabel.ImageRectOffset=aB[2].ImageRectPosition
end)
end
end)
end

return aq
end

return aa end function a.R()

local aa=a.load'd'local af=
aa.New


local ag=a.load'Q'

local ai={}

function ai.New(ak,al)
local am={
__type="Code",
Title=al.Title,
Code=al.Code,
CodeSize=al.CodeSize or 18,
Height=al.Height,
CodeTheme=al.CodeTheme,
Locked=false,
CanCopied=al.CanCopied~=false,
OnCopy=al.OnCopy,

Index=al.Index,
}

local an=not am.Locked











local ao=ag.New(am,al.Window,al.Parent,function()
if an then
local ao=am.Title or"code"
local ap,aq=pcall(function()
if toclipboard then
toclipboard(am.Code)
end
if setclipboard then
setclipboard(am.Code)
end

if am.OnCopy then
am.OnCopy()
end
end)
if not ap then
al.WindUI:Notify{
Title="Error",
Content="The "..ao.." is not copied. Error: "..aq,
Icon="x",
Duration=5,
}
end
end
end,al.WindUI.UIScale)

function am.SetCode(ap,aq)
ao.Set(aq)
am.Code=aq
end

function am.Set(ap,aq)
return am.SetCode(aq)
end

function am.Destroy(ap)
ao.Destroy()
am=nil
end

function am.UpdateShape(ap)
if al.Window.NewElements then
local aq=aa:GetElementPosition(
ap.Elements,
am.Index,
al.ParentType=="HStack"or al.ParentType=="Group"
)

if aq and ao.CodeFrameModule then
ao.CodeFrameModule:SetType(aq)

print(aq)
ao.TopbarFrameModule:SetType(
table.find({"Squircle-BL-BR","SquircleH-BL-BR"},aq)~=nil and"Square"or aq
)
end
end
end

am.UIElements={Main=ao.CodeFrame}
am.ElementFrame=ao.CodeFrame

return am.__type,am
end

return ai end function a.S()

local aa=a.load'd'
local af=aa.New local ag=
aa.Tween

local ai=(cloneref or clonereference or function(ai)
return ai
end)

local ak=ai(game:GetService"UserInputService")
ai(game:GetService"TouchInputService")
local al=ai(game:GetService"RunService")
local am=ai(game:GetService"Players")local an=

al.RenderStepped
local ao=am.LocalPlayer
local ap=ao:GetMouse()

local aq=a.load'm'.New
local ar=a.load'n'.New

local as={
UICorner=9,

}

local at

function as.Colorpicker(au,av,aw,ax,ay)
local az={
__type="Colorpicker",
Title=av.Title,
Desc=av.Desc,
Default=av.Value or av.Default,
Callback=av.Callback,
Transparency=av.Transparency,
UIElements=av.UIElements,

TextPadding=10,
}

local aA={}
local aB=az.Transparency~=nil

function az.SetHSVFromRGB(b,d)
local f,g,h=Color3.toHSV(d)
az.Hue=f
az.Sat=g
az.Vib=h
end

az:SetHSVFromRGB(az.Default)

local b=a.load'o'
local d=b.Create(nil,"Dialog",aw,ax,aw.UIElements.Main.Main)

az.ColorpickerFrame=d

d.UIElements.Main.Size=UDim2.new(1,0,0,0)



local f,g,h=az.Hue,az.Sat,az.Vib

az.UIElements.Title=af("TextLabel",{
Text=az.Title,
TextSize=20,
FontFace=Font.new(aa.Font,Enum.FontWeight.SemiBold),
TextXAlignment="Left",
Size=UDim2.new(0,0,0,0),
AutomaticSize="Y",
ThemeTag={
TextColor3="Text",
},
BackgroundTransparency=1,
Parent=d.UIElements.Main,
},{
af("UIPadding",{
PaddingTop=UDim.new(0,az.TextPadding/2),
PaddingLeft=UDim.new(0,az.TextPadding/2),
PaddingRight=UDim.new(0,az.TextPadding/2),
PaddingBottom=UDim.new(0,az.TextPadding/2),
}),
})





local i=af("Frame",{
Size=UDim2.new(1,0,1,0),
Position=UDim2.new(0,0,0,0),
BackgroundTransparency=1,
})

local l=af("Frame",{
Size=UDim2.new(0,14,0,14),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0,0),
Parent=i,
BackgroundColor3=az.Default,
},{
af("UIStroke",{
Thickness=2,
Transparency=0.1,
ThemeTag={
Color="Text",
},
}),
af("UICorner",{
CornerRadius=UDim.new(1,0),
}),
})

az.UIElements.SatVibMap=af("ImageLabel",{
Size=UDim2.fromOffset(160,158),
Position=UDim2.fromOffset(0,40+az.TextPadding),
Image="rbxassetid://4155801252",
BackgroundColor3=Color3.fromHSV(f,1,1),
BackgroundTransparency=0,
Parent=d.UIElements.Main,
},{
af("UICorner",{
CornerRadius=UDim.new(0,8),
}),
aa.NewRoundFrame(8,"SquircleOutline",{
ThemeTag={
ImageColor3="Outline",
},
Size=UDim2.new(1,0,1,0),
ImageTransparency=0.85,
ZIndex=99999,
},{
af("UIGradient",{
Rotation=45,
Color=ColorSequence.new{
ColorSequenceKeypoint.new(0.0,Color3.fromRGB(255,255,255)),
ColorSequenceKeypoint.new(0.5,Color3.fromRGB(255,255,255)),
ColorSequenceKeypoint.new(1.0,Color3.fromRGB(255,255,255)),
},
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0.0,0.1),
NumberSequenceKeypoint.new(0.5,1),
NumberSequenceKeypoint.new(1.0,0.1),
},
}),
}),

l,
})

az.UIElements.Inputs=af("Frame",{
AutomaticSize="XY",
Size=UDim2.new(0,0,0,0),
Position=UDim2.fromOffset(
aB and 240 or 210,
40+az.TextPadding
),
BackgroundTransparency=1,
Parent=d.UIElements.Main,
},{
af("UIListLayout",{
Padding=UDim.new(0,4),
FillDirection="Vertical",
}),
})





local m=af("Frame",{
BackgroundColor3=az.Default,
Size=UDim2.fromScale(1,1),
BackgroundTransparency=az.Transparency,
},{
af("UICorner",{
CornerRadius=UDim.new(0,8),
}),
})

af("ImageLabel",{
Image="http://www.roblox.com/asset/?id=14204231522",
ImageTransparency=0.45,
ScaleType=Enum.ScaleType.Tile,
TileSize=UDim2.fromOffset(40,40),
BackgroundTransparency=1,
Position=UDim2.fromOffset(85,208+az.TextPadding),
Size=UDim2.fromOffset(75,24),
Parent=d.UIElements.Main,
},{
af("UICorner",{
CornerRadius=UDim.new(0,8),
}),
aa.NewRoundFrame(8,"SquircleOutline",{
ThemeTag={
ImageColor3="Outline",
},
Size=UDim2.new(1,0,1,0),
ImageTransparency=0.85,
ZIndex=99999,
},{
af("UIGradient",{
Rotation=60,
Color=ColorSequence.new{
ColorSequenceKeypoint.new(0.0,Color3.fromRGB(255,255,255)),
ColorSequenceKeypoint.new(0.5,Color3.fromRGB(255,255,255)),
ColorSequenceKeypoint.new(1.0,Color3.fromRGB(255,255,255)),
},
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0.0,0.1),
NumberSequenceKeypoint.new(0.5,1),
NumberSequenceKeypoint.new(1.0,0.1),
},
}),
}),







m,
})

local p=af("Frame",{
BackgroundColor3=az.Default,
Size=UDim2.fromScale(1,1),
BackgroundTransparency=0,
ZIndex=9,
},{
af("UICorner",{
CornerRadius=UDim.new(0,8),
}),
})

af("ImageLabel",{
Image="http://www.roblox.com/asset/?id=14204231522",
ImageTransparency=0.45,
ScaleType=Enum.ScaleType.Tile,
TileSize=UDim2.fromOffset(40,40),
BackgroundTransparency=1,
Position=UDim2.fromOffset(0,208+az.TextPadding),
Size=UDim2.fromOffset(75,24),
Parent=d.UIElements.Main,
},{
af("UICorner",{
CornerRadius=UDim.new(0,8),
}),







aa.NewRoundFrame(8,"SquircleOutline",{
ThemeTag={
ImageColor3="Outline",
},
Size=UDim2.new(1,0,1,0),
ImageTransparency=0.85,
ZIndex=99999,
},{
af("UIGradient",{
Rotation=60,
Color=ColorSequence.new{
ColorSequenceKeypoint.new(0.0,Color3.fromRGB(255,255,255)),
ColorSequenceKeypoint.new(0.5,Color3.fromRGB(255,255,255)),
ColorSequenceKeypoint.new(1.0,Color3.fromRGB(255,255,255)),
},
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0.0,0.1),
NumberSequenceKeypoint.new(0.5,1),
NumberSequenceKeypoint.new(1.0,0.1),
},
}),
}),
p,
})

local r={}

for u=0,1,0.1 do
table.insert(r,ColorSequenceKeypoint.new(u,Color3.fromHSV(u,1,1)))
end

local u=af("UIGradient",{
Color=ColorSequence.new(r),
Rotation=90,
})

local v=af("Frame",{
Size=UDim2.new(0,14,0,14),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0,0),
Parent=i,


BackgroundColor3=az.Default,
},{
af("UIStroke",{
Thickness=2,
Transparency=0.1,
ThemeTag={
Color="Text",
},
}),
af("UICorner",{
CornerRadius=UDim.new(1,0),
}),
})

local x=af("Frame",{
Size=UDim2.fromOffset(6,192),
Position=UDim2.fromOffset(180,40+az.TextPadding),
Parent=d.UIElements.Main,
},{
af("UICorner",{
CornerRadius=UDim.new(1,0),
}),
u,
i,
})

local function CreateNewInput(z,A)
local B=ar(z,nil,az.UIElements.Inputs,nil,nil,nil,nil,nil,true)

af("TextLabel",{
BackgroundTransparency=1,
TextTransparency=0.4,
TextSize=17,
FontFace=Font.new(aa.Font,Enum.FontWeight.Regular),
AutomaticSize="XY",
ThemeTag={
TextColor3="Placeholder",
},
AnchorPoint=Vector2.new(1,0.5),
Position=UDim2.new(1,-12,0.5,0),
Parent=B.Frame,
Text=z,
})

af("UIScale",{
Parent=B,
Scale=0.85,
})

B.Frame.Frame.TextBox.Text=A
B.Size=UDim2.new(0,150,0,42)

return B
end

local function ToRGB(z)
return{
R=math.floor(z.R*255),
G=math.floor(z.G*255),
B=math.floor(z.B*255),
}
end

local z=CreateNewInput("Hex","#"..az.Default:ToHex())

local A=CreateNewInput("Red",ToRGB(az.Default).R)
local B=CreateNewInput("Green",ToRGB(az.Default).G)
local C=CreateNewInput("Blue",ToRGB(az.Default).B)
local F
if aB then
F=CreateNewInput("Alpha",((1-az.Transparency)*100).."%")
end

local G=af("Frame",{
Size=UDim2.new(0,0,0,40),
AutomaticSize="Y",
Position=UDim2.new(0,0,0,254+az.TextPadding),
BackgroundTransparency=1,
Parent=d.UIElements.Main,
LayoutOrder=4,
},{
af("UIListLayout",{
Padding=UDim.new(0,6),
FillDirection="Horizontal",
HorizontalAlignment="Right",
}),






})

aa.AddSignal(d.UIElements.Main:GetPropertyChangedSignal"AbsoluteSize",function()
az.UIElements.Title.Size=UDim2.new(
0,
d.UIElements.Main.AbsoluteSize.X/av.UIScale-(d.UIPadding*2),
0,
0
)
G.Size=UDim2.new(
0,
d.UIElements.Main.AbsoluteSize.X/av.UIScale-d.UIPadding*2,
0,
40
)
end)

local H={
{
Title="Cancel",
Variant="Secondary",
Callback=function()
av.IsShowed=false
for H,J in next,aA do
J:Disconnect()
end
aA={}
end,
},
{
Title="Apply",

Variant="Primary",
Callback=function()
av.IsShowed=false
for H,J in next,aA do
J:Disconnect()
end
aA={}

ay(Color3.fromHSV(az.Hue,az.Sat,az.Vib),az.Transparency)
end,
},
}

for J,L in next,H do
local M=aq(
L.Title,
L.Icon,
L.Callback,
L.Variant,
G,
d,
true
)
M.Size=UDim2.new(0.5,-3,0,40)
M.AutomaticSize="None"
end

local J,L,M
if aB then
local N=af("Frame",{
Size=UDim2.new(1,0,1,0),
Position=UDim2.fromOffset(0,0),
BackgroundTransparency=1,
})

L=af("ImageLabel",{
Size=UDim2.new(0,14,0,14),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0,0),
ThemeTag={
BackgroundColor3="Text",
},
Parent=N,
},{
af("UIStroke",{
Thickness=2,
Transparency=0.1,
ThemeTag={
Color="Text",
},
}),
af("UICorner",{
CornerRadius=UDim.new(1,0),
}),
})

M=af("Frame",{
Size=UDim2.fromScale(1,1),
},{
af("UIGradient",{
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0,0),
NumberSequenceKeypoint.new(1,1),
},
Rotation=270,
}),
af("UICorner",{
CornerRadius=UDim.new(0,6),
}),
})

J=af("Frame",{
Size=UDim2.fromOffset(6,192),
Position=UDim2.fromOffset(210,40+az.TextPadding),
Parent=d.UIElements.Main,
BackgroundTransparency=1,
},{
af("UICorner",{
CornerRadius=UDim.new(1,0),
}),
af("ImageLabel",{
Image="rbxassetid://14204231522",
ImageTransparency=0.45,
ScaleType=Enum.ScaleType.Tile,
TileSize=UDim2.fromOffset(40,40),
BackgroundTransparency=1,
Size=UDim2.fromScale(1,1),
},{
af("UICorner",{
CornerRadius=UDim.new(1,0),
}),
}),
M,
N,
})
end

function az.Round(N,O,P)
if P==0 then
return math.floor(O)
end
O=tostring(O)
return O:find"%."and tonumber(O:sub(1,O:find"%."+P))or O
end

function az.Update(N,O,P)
if O then
f,g,h=Color3.toHSV(O)
else
f,g,h=az.Hue,az.Sat,az.Vib
end

az.UIElements.SatVibMap.BackgroundColor3=Color3.fromHSV(f,1,1)
l.Position=UDim2.new(g,0,1-h,0)
l.BackgroundColor3=Color3.fromHSV(f,g,h)
p.BackgroundColor3=Color3.fromHSV(f,g,h)
v.BackgroundColor3=Color3.fromHSV(f,1,1)
v.Position=UDim2.new(0.5,0,f,0)

z.Frame.Frame.TextBox.Text="#"..Color3.fromHSV(f,g,h):ToHex()
A.Frame.Frame.TextBox.Text=ToRGB(Color3.fromHSV(f,g,h)).R
B.Frame.Frame.TextBox.Text=ToRGB(Color3.fromHSV(f,g,h)).G
C.Frame.Frame.TextBox.Text=ToRGB(Color3.fromHSV(f,g,h)).B

if P or aB then
p.BackgroundTransparency=az.Transparency or P
M.BackgroundColor3=Color3.fromHSV(f,g,h)
L.BackgroundColor3=Color3.fromHSV(f,g,h)
L.BackgroundTransparency=az.Transparency or P
L.Position=UDim2.new(0.5,0,1-az.Transparency or P,0)
F.Frame.Frame.TextBox.Text=az:Round(
(1-az.Transparency or P)*100,
0
).."%"
end
end

az:Update(az.Default,az.Transparency)

local function GetRGB()
local N=Color3.fromHSV(az.Hue,az.Sat,az.Vib)
return{R=math.floor(N.r*255),G=math.floor(N.g*255),B=math.floor(N.b*255)}
end



local function clamp(N,O,P)
return math.clamp(tonumber(N)or 0,O,P)
end

table.insert(
aA,
aa.AddSignal(z.Frame.Frame.TextBox.FocusLost,function(N)
if N then
local O=z.Frame.Frame.TextBox.Text:gsub("#","")
local P,Q=pcall(Color3.fromHex,O)
if P and typeof(Q)=="Color3"then
az.Hue,az.Sat,az.Vib=Color3.toHSV(Q)
az:Update()
az.Default=Q
end
end
end)
)

local function updateColorFromInput(N,O)
aa.AddSignal(N.Frame.Frame.TextBox.FocusLost,function(P)
if P then
local Q=N.Frame.Frame.TextBox
local R=GetRGB()
local S=clamp(Q.Text,0,255)
Q.Text=tostring(S)

R[O]=S
local T=Color3.fromRGB(R.R,R.G,R.B)
az.Hue,az.Sat,az.Vib=Color3.toHSV(T)
az:Update()
end
end)
end

updateColorFromInput(A,"R")
updateColorFromInput(B,"G")
updateColorFromInput(C,"B")

if aB then
aa.AddSignal(F.Frame.Frame.TextBox.FocusLost,function(N)
if N then
local O=F.Frame.Frame.TextBox
local P=clamp(O.Text,0,100)
O.Text=tostring(P)

az.Transparency=1-P*0.01
az:Update(nil,az.Transparency)
end
end)
end



local function UpdateSatVib(N,O)
local P=N.AbsolutePosition.X
local Q=P+N.AbsoluteSize.X
local R=N.AbsolutePosition.Y
local S=R+N.AbsoluteSize.Y

local T=math.clamp(ap.X,P,Q)
local U=math.clamp(ap.Y,R,S)

O.Sat=(T-P)/(Q-P)
O.Vib=1-((U-R)/(S-R))

O:Update()
end

local function UpdateHue(N,O)
local P=N.AbsolutePosition.Y
local Q=P+N.AbsoluteSize.Y

local R=math.clamp(ap.Y,P,Q)

O.Hue=(R-P)/(Q-P)

O:Update()
end

local function UpdateTransparency(N,O)
local P=N.AbsolutePosition.Y
local Q=P+N.AbsoluteSize.Y

local R=math.clamp(ap.Y,P,Q)

O.Transparency=1-((R-P)/(Q-P))

O:Update()
end

local N=ax.GenerateGUID()

table.insert(
aA,
ak.InputChanged:Connect(function(O)
if
O.UserInputType~=Enum.UserInputType.MouseMovement
and O.UserInputType~=Enum.UserInputType.Touch
then
return
end

if at=="SatVib"then
UpdateSatVib(az.UIElements.SatVibMap,az)
elseif at=="Hue"then
UpdateHue(x,az)
elseif at=="Transparency"then
UpdateTransparency(J,az)
end
end)
)

table.insert(
aA,
az.UIElements.SatVibMap.InputBegan:Connect(function(O)
if
O.UserInputType~=Enum.UserInputType.MouseButton1
and O.UserInputType~=Enum.UserInputType.Touch
then
return
end

if ax.CurrentInput and ax.CurrentInput~=N then
return
end
ax.CurrentInput=N

if at and at~="SatVib"then
return
end

at="SatVib"

UpdateSatVib(az.UIElements.SatVibMap,az)
end)
)

table.insert(
aA,
x.InputBegan:Connect(function(O)
if
O.UserInputType~=Enum.UserInputType.MouseButton1
and O.UserInputType~=Enum.UserInputType.Touch
then
return
end

if ax.CurrentInput and ax.CurrentInput~=N then
return
end
ax.CurrentInput=N

if at and at~="Hue"then
return
end

at="Hue"

UpdateHue(x,az)
end)
)

if J then
table.insert(
aA,
J.InputBegan:Connect(function(O)
if
O.UserInputType~=Enum.UserInputType.MouseButton1
and O.UserInputType~=Enum.UserInputType.Touch
then
return
end

if ax.CurrentInput and ax.CurrentInput~=N then
return
end
ax.CurrentInput=N

if at and at~="Transparency"then
return
end

at="Transparency"

UpdateTransparency(J,az)
end)
)
end

table.insert(
aA,
ak.InputEnded:Connect(function(O)
at=nil

if ax.CurrentInput and ax.CurrentInput~=N then
return
end
ax.CurrentInput=nil
end)
)

return az
end

function as.New(au,av)
local aw={
__type="Colorpicker",
Title=av.Title or"Colorpicker",
Desc=av.Desc or nil,
Locked=av.Locked or false,
LockedTitle=av.LockedTitle,
Default=av.Default or Color3.new(1,1,1),
Callback=av.Callback or function()end,

UIScale=av.UIScale,
Transparency=av.Transparency,
UIElements={},

IsShowed=false,
}

local ax=true



aw.ColorpickerFrame=a.load'C'{
Title=aw.Title,
Desc=aw.Desc,
Parent=av.Parent,
TextOffset=40,
Hover=false,
Tab=av.Tab,
Index=av.Index,
Window=av.Window,
ElementTable=aw,
ParentConfig=av,
Tags=av.Tags,
}

aw.UIElements.Colorpicker=aa.NewRoundFrame(as.UICorner,"Squircle",{
ImageTransparency=0,
Active=true,
ImageColor3=aw.Default,
Parent=aw.ColorpickerFrame.UIElements.Main,
Size=UDim2.new(0,26,0,26),
AnchorPoint=Vector2.new(1,0),
Position=UDim2.new(1,0,0,0),
ZIndex=2,
},{
aa.NewRoundFrame(as.UICorner,"SquircleGlass",{
Size=UDim2.new(1,0,1,0),
ThemeTag={
ImageColor3="Outline",
},
ImageTransparency=0.55,
}),
},true)

function aw.Lock(ay)
aw.Locked=true
ax=false
return aw.ColorpickerFrame:Lock(aw.LockedTitle)
end
function aw.Unlock(ay)
aw.Locked=false
ax=true
return aw.ColorpickerFrame:Unlock()
end

if aw.Locked then
aw:Lock()
end

function aw.Update(ay,az,aA)
aw.UIElements.Colorpicker.ImageTransparency=aA or 0
aw.UIElements.Colorpicker.ImageColor3=az
aw.Default=az
if aA then
aw.Transparency=aA
end
end

function aw.Set(ay,az,aA)
return aw:Update(az,aA)
end

aa.AddSignal(aw.UIElements.Colorpicker.MouseButton1Click,function()
if ax and not aw.IsShowed then
aw.IsShowed=true

as:Colorpicker(aw,av.Window,av.WindUI,function(ay,az)
aw:Update(ay,az)
aw.Default=ay
aw.Transparency=az
aa.SafeCallback(aw.Callback,ay,az)
end).ColorpickerFrame
:Open()
end
end)

return aw.__type,aw
end

return as end function a.T()

local aa=a.load'd'
local af=aa.New
local ai=aa.Tween

local ak={}

function ak.New(al,am)
local an={
__type="Section",
Title=am.Title or"Section",
Desc=am.Desc,
Icon=am.Icon,
IconThemed=am.IconThemed,
TextXAlignment=am.TextXAlignment or"Left",
TextSize=am.TextSize or 19,
DescTextSize=am.DescTextSize or 16,
Box=am.Box or false,
BoxBorder=am.BoxBorder or false,
FontWeight=am.FontWeight or Enum.FontWeight.SemiBold,
DescFontWeight=am.DescFontWeight or Enum.FontWeight.Medium,
TextTransparency=am.TextTransparency or 0.05,
DescTextTransparency=am.DescTextTransparency or 0.4,
Opened=am.Opened or false,
UIElements={},

HeaderSize=48,
IconSize=20,
Padding=10,

Elements={},

Expandable=false,
}

local ao

function an.SetIcon(ap,aq)
an.Icon=aq or nil
if ao then
ao:Destroy()
end
if aq then
ao=aa.Image(
aq,
aq..":"..an.Title,
0,
am.Window.Folder,
an.__type,
true,
an.IconThemed,
"SectionIcon"
)
ao.Size=UDim2.new(0,an.IconSize,0,an.IconSize)
end
end

local ap=af("Frame",{
Size=UDim2.new(0,an.IconSize,0,an.IconSize),
BackgroundTransparency=1,
Visible=false,
},{
af("ImageLabel",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
Image=aa.Icon"chevron-down"[1],
ImageRectSize=aa.Icon"chevron-down"[2].ImageRectSize,
ImageRectOffset=aa.Icon"chevron-down"[2].ImageRectPosition,
ThemeTag={
ImageTransparency="SectionExpandIconTransparency",
ImageColor3="SectionExpandIcon",
},
}),
})

if an.Icon then
an:SetIcon(an.Icon)
end

local aq=af("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
},{
af("UIListLayout",{
FillDirection="Vertical",
HorizontalAlignment=an.TextXAlignment,
VerticalAlignment="Center",
Padding=UDim.new(0,4),
}),
})

local ar,as

local function createTitle(at,au)
return af("TextLabel",{
BackgroundTransparency=1,
TextXAlignment=an.TextXAlignment,
AutomaticSize="Y",
TextSize=au=="Title"and an.TextSize or an.DescTextSize,
TextTransparency=au=="Title"and an.TextTransparency or an.DescTextTransparency,
ThemeTag={
TextColor3="Text",
},
FontFace=Font.new(aa.Font,au=="Title"and an.FontWeight or an.DescFontWeight),


Text=at,
Size=UDim2.new(1,0,0,0),
TextWrapped=true,
Parent=aq,
})
end

ar=createTitle(an.Title,"Title")
if an.Desc then
as=createTitle(an.Desc,"Desc")
end

local function UpdateTitleSize()
local at=0
if ao then
at=at-(an.IconSize+8)
end
if ap.Visible then
at=at-(an.IconSize+8)
end
aq.Size=UDim2.new(1,at,0,0)
end

local at=aa.NewRoundFrame(am.Window.ElementConfig.UICorner,"Squircle",{
Size=UDim2.new(1,0,0,0),
BackgroundTransparency=1,
Parent=am.Parent,

AutomaticSize="Y",
ThemeTag={
ImageTransparency=an.Box and"SectionBoxBackgroundTransparency"or nil,
ImageColor3="SectionBoxBackground",
},
ImageTransparency=not an.Box and 1 or nil,
},{
aa.NewRoundFrame(am.Window.ElementConfig.UICorner-1,"SquircleOutline",{
Size=UDim2.new(1,0,1,0),



ThemeTag={

ImageColor3="SectionBoxBorder",
},
ImageTransparency=an.Box and an.BoxBorder and 0.92 or 1,
Name="Outline",
ClipsDescendants=true,
},{
af("TextButton",{
Size=UDim2.new(1,0,0,an.Expandable and 0 or(not as and an.HeaderSize or 0)),
BackgroundTransparency=1,
AutomaticSize=(not an.Expandable or as)and"Y"or nil,
Text="",
Name="Top",
},{
an.Box and af("UIPadding",{
PaddingTop=UDim.new(
0,
am.Window.ElementConfig.UIPadding+(am.Window.NewElements and 4 or 0)
),
PaddingLeft=UDim.new(
0,
am.Window.ElementConfig.UIPadding+(am.Window.NewElements and 4 or 0)
),
PaddingRight=UDim.new(
0,
am.Window.ElementConfig.UIPadding+(am.Window.NewElements and 4 or 0)
),
PaddingBottom=UDim.new(
0,
am.Window.ElementConfig.UIPadding+(am.Window.NewElements and 4 or 0)
),
})or nil,
ao,
aq,
af("UIListLayout",{
Padding=UDim.new(0,8),
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment="Left",
}),
ap,
}),
af("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
Name="Content",
Visible=false,
Position=UDim2.new(0,0,0,an.HeaderSize+10),
},{
an.Box and af("UIPadding",{
PaddingLeft=UDim.new(0,am.Window.ElementConfig.UIPadding/1.5),
PaddingRight=UDim.new(0,am.Window.ElementConfig.UIPadding/1.5),
PaddingBottom=UDim.new(0,am.Window.ElementConfig.UIPadding/1.5),
})or nil,
af("UIListLayout",{
FillDirection="Vertical",
Padding=UDim.new(0,am.Tab.Gap),
VerticalAlignment="Top",
}),
}),
}),
})





an.ElementFrame=at

at.Outline.Top:GetPropertyChangedSignal"AbsoluteSize":Connect(function()
at.Outline.Content.Position=UDim2.new(0,0,0,(at.Outline.Top.AbsoluteSize.Y/am.UIScale)+10)

if an.Opened then
an:Open(true)
else
an.Close(true)
end
end)

local au=am.ElementsModule

au.Load(an,at.Outline.Content,au.Elements,am.Window,am.WindUI,function()
if not an.Expandable then
an.Expandable=true
ap.Visible=true
UpdateTitleSize()
end
end,au,am.UIScale,am.Tab)

UpdateTitleSize()

function an.SetTitle(av,aw)
an.Title=aw
ar.Text=aw
end

function an.SetDesc(av,aw)
an.Desc=aw
if not as then
as=createTitle(aw,"Desc")
end
as.Text=aw
end

function an.Destroy(av)
for aw,ax in next,an.Elements do
ax:Destroy()
end








at:Destroy()
end

function an.Open(av,aw)
if an.Expandable then
an.Opened=true
if aw then
at.Size=UDim2.new(
at.Size.X.Scale,
at.Size.X.Offset,
0,
at.Outline.Top.AbsoluteSize.Y/am.UIScale
+(at.Outline.Content.AbsoluteSize.Y/am.UIScale)
+10
)
ap.ImageLabel.Rotation=180
else
ai(at,0.33,{
Size=UDim2.new(
at.Size.X.Scale,
at.Size.X.Offset,
0,
at.Outline.Top.AbsoluteSize.Y/am.UIScale
+(at.Outline.Content.AbsoluteSize.Y/am.UIScale)
+10
),
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()

ai(
ap.ImageLabel,
0.2,
{Rotation=180},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
end
end
end
function an.Close(av,aw)
if an.Expandable then
an.Opened=false
if aw then
at.Size=UDim2.new(
at.Size.X.Scale,
at.Size.X.Offset,
0,
(at.Outline.Top.AbsoluteSize.Y/am.UIScale)
)
ap.ImageLabel.Rotation=0
else
ai(at,0.26,{
Size=UDim2.new(
at.Size.X.Scale,
at.Size.X.Offset,
0,
(at.Outline.Top.AbsoluteSize.Y/am.UIScale)
),
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
ai(
ap.ImageLabel,
0.2,
{Rotation=0},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
end
end
end

aa.AddSignal(at.Outline.Top.MouseButton1Click,function()
if an.Expandable then
if an.Opened then
an:Close()
else
an:Open()
end
end
end)

aa.AddSignal(at.Outline.Content.UIListLayout:GetPropertyChangedSignal"AbsoluteContentSize",function()
if an.Opened then
an:Open(true)
else
an:Close(true)
end
end)

task.defer(function()
if an.Expandable then








at.Size=
UDim2.new(at.Size.X.Scale,at.Size.X.Offset,0,at.Outline.Top.AbsoluteSize.Y/am.UIScale)
at.AutomaticSize="None"
at.Outline.Top.Size=UDim2.new(1,0,0,(not as and an.HeaderSize or 0))
at.Outline.Top.AutomaticSize=(not an.Expandable or as)and"Y"or"None"
at.Outline.Content.Visible=true
end
if an.Opened then
an:Open()
else
an:Close(true)
end
end)

return an.__type,an
end

return ak end function a.U()

local aa=a.load'd'
local af=aa.New

local ai={}

function ai.New(ak,al)
local am=af("Frame",{
Parent=al.Parent,
Size=not table.find({"Group","HStack"},al.ParentType)and UDim2.new(1,-7,0,7*(al.Columns or 1))or UDim2.new(0,7*(al.Columns or 1),0,0),
BackgroundTransparency=1,
})

return"Space",{__type="Space",ElementFrame=am}
end

return ai end function a.V()
local aa=a.load'd'
local af=aa.New

local ai={}

local function ParseAspectRatio(ak)
if type(ak)=="string"then
local al,am=ak:match"(%d+):(%d+)"
if al and am then
return tonumber(al)/tonumber(am)
end
elseif type(ak)=="number"then
return ak
end
return nil
end

function ai.New(ak,al)
local am={
__type="Image",
Image=al.Image or"",
AspectRatio=al.AspectRatio or"16:9",
Radius=al.Radius or al.Window.ElementConfig.UICorner,
}
local an=aa.Image(
am.Image,
am.Image,
am.Radius,
al.Window.Folder,
"Image",
false
)
if an and an.Parent then
an.Parent=al.Parent
an.Size=UDim2.new(1,0,0,0)
an.BackgroundTransparency=1












local ao=ParseAspectRatio(am.AspectRatio)
local ap

if ao then
ap=af("UIAspectRatioConstraint",{
Parent=an,
AspectRatio=ao,
AspectType="ScaleWithParentSize",
DominantAxis="Width"
})
end

function am.Destroy(aq)
an:Destroy()
end
end

return am.__type,am
end

return ai end function a.W()
local aa=a.load'd'
local af=aa.New

local ai={}

function ai.New(ak,al)
local am={
__type="Group",
Elements={},
ElementFrame=nil,
}

local an=af("Frame",{
Size=UDim2.new(1,0,0,0),
BackgroundTransparency=1,
AutomaticSize="Y",
Parent=al.Parent,
},{
af("UIListLayout",{
FillDirection="Horizontal",
HorizontalAlignment="Center",

Padding=UDim.new(0,al.Tab and al.Tab.Gap or(al.Window.NewElements and 1 or 6))
}),
})

am.ElementFrame=an

local ao=al.ElementsModule
ao.Load(
am,
an,
ao.Elements,
al.Window,
al.WindUI,
function(ap,aq)
local ar=al.Tab and al.Tab.Gap or(al.Window.NewElements and 1 or 6)

local as={}
local at=0

for au,av in next,aq do
if av.__type=="Space"then
at=at+(av.ElementFrame.Size.X.Offset or 6)
elseif av.__type=="Divider"then
at=at+(av.ElementFrame.Size.X.Offset or 1)
else
table.insert(as,av)
end
end

local au=#as
if au==0 then return end

local av=1/au

local aw=ar*(au-1)

local ax=-(aw+at)

local ay=math.floor(ax/au)
local az=ax-(ay*au)

for aA,aB in next,as do
local b=ay
if aA<=math.abs(az)then
b=b-1
end

if aB.ElementFrame then
aB.ElementFrame.Size=UDim2.new(av,b,1,0)
end
end
end,
ao,
al.UIScale,
al.Tab
)



return am.__type,am
end

return ai end function a.X()
local aa=a.load'd'
local af=aa.New

local ai={}

function ai.New(ak,al)
local am={
__type="HStack",
AutoSpace=al.AutoSpace or false,
Elements={},
ElementFrame=nil,
}

local an=af("Frame",{
Size=UDim2.new(1,0,0,0),
BackgroundTransparency=1,
AutomaticSize="Y",
Parent=al.Parent,
},{
af("UIListLayout",{
FillDirection="Horizontal",
HorizontalAlignment="Center",

Padding=UDim.new(0,al.Tab and al.Tab.Gap or(al.Window.NewElements and 1 or 6)),
}),
})

am.ElementFrame=an

local ao=al.ElementsModule
ao.Load(
am,
an,
ao.Elements,
al.Window,
al.WindUI,
function(ap,aq)
local ar=al.Tab and al.Tab.Gap or(al.Window.NewElements and 1 or 6)

local as={}
local at=0

for au,av in next,aq do
if av.__type=="Space"then
at=at+(av.ElementFrame.Size.X.Offset or 6)
elseif av.__type=="Divider"then
at=at+(av.ElementFrame.Size.X.Offset or 1)
else
table.insert(as,av)
end
end

local au=#as
if au==0 then
return
end

local av=1/au

local aw=ar*(au-1)

local ax=-(aw+at)

local ay=math.floor(ax/au)
local az=ax-(ay*au)

for aA,aB in next,as do
local b=ay
if aA<=math.abs(az)then
b=b-1
end

if aB.ElementFrame then
aB.ElementFrame.Size=UDim2.new(av,b,1,0)
end
end
end,
ao,
al.UIScale,
al.Tab
)

if am.AutoSpace then
for ap in next,ao.Elements do
if ap~="Space"and ap~="Divider"then
local aq=am[ap]
am[ap]=function(ar,as)
if#am.Elements>0 then
am:Space()
end
return aq(ar,as)
end
end
end
end

return am.__type,am
end

return ai end function a.Y()

local aa=a.load'd'
local af=aa.New

local ai={}

function ai.New(ak,al)
local am={
__type="VStack",
Elements={},
ElementFrame=nil,
}

local an=af("Frame",{
Size=UDim2.new(1,0,0,0),
BackgroundTransparency=1,
AutomaticSize="Y",
Parent=al.Parent,
},{
af("UIListLayout",{
FillDirection="Vertical",
HorizontalAlignment="Center",

Padding=UDim.new(0,al.Tab and al.Tab.Gap or(al.Window.NewElements and 1 or 6))
}),
})

am.ElementFrame=an

local ao=al.ElementsModule
ao.Load(
am,
an,
ao.Elements,
al.Window,
al.WindUI,







































nil,
ao,
al.UIScale,
al.Tab
)



return am.__type,am
end

return ai end function a.Z()
local aa=(cloneref or clonereference or function(aa)
return aa
end)

local af=aa(game:GetService"UserInputService")

local ai=a.load'd'
local ak=ai.New

local al={}














function al.New(am,an:ConfigType__DARKLUA_TYPE_a)
local ao={
__type="Viewport",
Object=an.Object,
Camera=an.Camera or Instance.new"Camera",
Interactive=an.Interactive or false,
Height=an.Height or 200,
Focused=an.Focused~=false,
}

local ap=false
local aq=false
local ar,as=0

local at=ai.NewRoundFrame(an.Window.ElementConfig.UICorner,"Squircle",{
Size=UDim2.new(1,0,0,ao.Height),
Parent=an.Parent,
ThemeTag={
ImageColor3="ViewportBackground",
ImageTransparency="ViewportBackgroundTransparency",
},
},{
ak("CanvasGroup",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
},{
ak("UICorner",{
CornerRadius=UDim.new(0,an.Window.ElementConfig.UICorner),
}),
ak("ViewportFrame",{
Name="Viewport",
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
CurrentCamera=ao.Camera,
Active=ao.Interactive,
},{
ao.Object,
}),
}),
})

local function IsTouchInsideViewport(au)
local av=at.CanvasGroup.Viewport.AbsolutePosition
local aw=at.CanvasGroup.Viewport.AbsoluteSize

return au.X>=av.X
and au.X<=av.X+aw.X
and au.Y>=av.Y
and au.Y<=av.Y+aw.Y
end

local au=an.WindUI.GenerateGUID()

ai.AddSignal(at.CanvasGroup.Viewport.MouseEnter,function()
if ao.Interactive then
an.Tab.UIElements.ContainerFrame.ScrollingEnabled=false
end
end)

ai.AddSignal(at.CanvasGroup.Viewport.InputEnded,function(av)
if
av.UserInputType==Enum.UserInputType.MouseMovement
or av.UserInputType==Enum.UserInputType.Touch
then
an.Tab.UIElements.ContainerFrame.ScrollingEnabled=true
end
end)

ai.AddSignal(at.CanvasGroup.Viewport.InputBegan,function(av)
if ao.Interactive then
if
(av.UserInputType==Enum.UserInputType.MouseButton1)
or(av.UserInputType==Enum.UserInputType.Touch and not aq)
then
if an.WindUI.CurrentInput and an.WindUI.CurrentInput~=au then
return
end

an.WindUI.CurrentInput=au

ap=true
as=av.Position
end
end
end)

ai.AddSignal(af.InputEnded,function(av)
if ao.Interactive then
if
av.UserInputType==Enum.UserInputType.MouseButton1
or av.UserInputType==Enum.UserInputType.Touch
then
if an.WindUI.CurrentInput and an.WindUI.CurrentInput~=au then
return
end

an.WindUI.CurrentInput=nil

ap=false
end
end
end)

ai.AddSignal(af.InputChanged,function(av)
if ao.Interactive and ap and not aq then
if
av.UserInputType==Enum.UserInputType.MouseMovement
or av.UserInputType==Enum.UserInputType.Touch
then
local aw=av.Position-as
as=av.Position

local ax=ao.Object:GetPivot().Position
local ay=ao.Camera

local az=CFrame.fromAxisAngle(Vector3.new(0,1,0),-aw.X*0.02)
ay.CFrame=CFrame.new(ax)*az*CFrame.new(-ax)*ay.CFrame

local aA=CFrame.fromAxisAngle(ay.CFrame.RightVector,-aw.Y*0.02)
local aB=CFrame.new(ax)*aA*CFrame.new(-ax)*ay.CFrame

if aB.UpVector.Y>0.1 then
ay.CFrame=aB
end
end
end
end)

ai.AddSignal(at.CanvasGroup.Viewport.InputChanged,function(av)
if ao.Interactive then
if av.UserInputType==Enum.UserInputType.MouseWheel then
local aw=av.Position.Z*2
ao.Camera.CFrame+=ao.Camera.CFrame.LookVector*aw
end
end
end)

ai.AddSignal(af.TouchPinch,function(av,aw,ax,ay)
if not IsTouchInsideViewport(av[1])or not IsTouchInsideViewport(av[2])then
return
end
if ao.Interactive then
if ay==Enum.UserInputState.Begin then
aq=true
ap=false
ar=(av[1]-av[2]).Magnitude
elseif ay==Enum.UserInputState.Change then
if aq then
local az=(av[1]-av[2]).Magnitude
local aA=(az-ar)*0.03
ar=az
ao.Camera.CFrame+=ao.Camera.CFrame.LookVector*aA
end
elseif ay==Enum.UserInputState.End or ay==Enum.UserInputState.Cancel then
aq=false
end
end
end)

local function FocusCamera()
local av=ao.Object:IsA"BasePart"and ao.Object.Size
or select(2,ao.Object:GetBoundingBox(0))
local aw=math.max(av.X,av.Y,av.Z)
local ax=aw*2
local ay=ao.Object:GetPivot().Position

ao.Camera.CFrame=
CFrame.new(ay+Vector3.new(0,aw/2,ax),ay)
end

if ao.Focused then
FocusCamera()
end

function ao.SetObject(av,aw,ax)
if ax then
aw=aw:Clone()
end
if ao.Object then
ao.Object:Destroy()
end

ao.Object=aw
ao.Object.Parent=at.CanvasGroup.Viewport
end

function ao.SetHeight(av,aw)
at.Size=UDim2.new(1,0,0,aw)
end

function ao.Focus(av)
if ao.Object then
FocusCamera()
end
end

function ao.SetCamera(av,aw)
ao.Camera=aw
at.CanvasGroup.Viewport.CurrentCamera=aw
end

function ao.SetInteractive(av,aw)
ao.Interactive=aw
at.CanvasGroup.Viewport.Active=aw
end

ao.Main=at

return ao.__type,ao
end

return al end function a._()

return{
Elements={
Paragraph=a.load'D',
Button=a.load'E',
Toggle=a.load'H',
Slider=a.load'I',
ProgressBar=a.load'J',
Keybind=a.load'K',
Input=a.load'L',
Dropdown=a.load'O',
Code=a.load'R',
Colorpicker=a.load'S',
Section=a.load'T',
Divider=a.load'M',
Space=a.load'U',
Image=a.load'V',
Group=a.load'W',
HStack=a.load'X',
VStack=a.load'Y',
Viewport=a.load'Z',

},
Load=function(aa,af,ai,ak,al,am,an,ao,ap)
for aq,ar in next,ai do
aa[aq]=function(as,at)
at=at or{}
at.Tab=ap or aa
at.ParentType=aa.__type
at.ParentTable=aa
at.Index=#aa.Elements+1
at.GlobalIndex=#ak.AllElements+1
at.Parent=af
at.Window=ak
at.WindUI=al
at.UIScale=ao
at.ElementsModule=an local

au, av=ar:New(at)

if at.Flag and typeof(at.Flag)=="string"then
if ak.CurrentConfig then
ak.CurrentConfig:Register(at.Flag,av)

if ak.PendingConfigData and ak.PendingConfigData[at.Flag]then
local aw=ak.PendingConfigData[at.Flag]

local ax=ak.ConfigManager
if ax.Parser[aw.__type]then
task.defer(function()
local ay,az=pcall(function()
ax.Parser[aw.__type].Load(av,aw)
end)

if ay then
ak.PendingConfigData[at.Flag]=nil
else
warn(
"[ WindUI ] Failed to apply pending config for '"
..at.Flag
.."': "
..tostring(az)
)
end
end)
end
end
else
ak.PendingFlags=ak.PendingFlags or{}
ak.PendingFlags[at.Flag]=av
end
end

local aw
for ax,ay in next,av do
if typeof(ay)=="table"and ax~="ElementFrame"and ax:match"Frame$"then
aw=ay
break
end
end

if aw then
av.ElementFrame=aw.UIElements.Main
function av.SetTitle(ax,ay)
return aw.SetTitle and aw:SetTitle(ay)
end
function av.SetDesc(ax,ay)
return aw.SetDesc and aw:SetDesc(ay)
end
function av.SetImage(ax,ay,az)
return aw.SetImage and aw:SetImage(ay,az)
end
function av.SetThumbnail(ax,ay,az)
return aw.SetThumbnail and aw:SetThumbnail(ay,az)
end
function av.Highlight(ax)
aw:Highlight()
end
function av.Destroy(ax)
aw:Destroy()

table.remove(ak.AllElements,at.GlobalIndex)
table.remove(aa.Elements,at.Index)
table.remove(ap.Elements,at.Index)
aa:UpdateAllElementShapes(aa)
end
end

ak.AllElements[at.Index]=av
aa.Elements[at.Index]=av
if ap then
ap.Elements[at.Index]=av
end

if ak.NewElements then
aa:UpdateAllElementShapes(aa)
end

if am then
am(av,aa.Elements)
end
return av
end
end
function aa.UpdateAllElementShapes(aq,ar)
for as,at in next,ar.Elements do
local au
for av,aw in pairs(at)do
if typeof(aw)=="table"and av:match"Frame$"then
au=aw
break
end
end

if not au and at.UpdateShape then
au=at
end

if au then

au.Index=as
if au.UpdateShape then

au.UpdateShape(ar)
end
end
end
end
end,
}end function a.aa()

local aa=(cloneref or clonereference or function(aa)
return aa
end)

local af=game:GetService"Players"

aa(game:GetService"UserInputService")
local ai=af.LocalPlayer:GetMouse()

local ak=a.load'd'
local al=ak.New

local am=a.load'B'.New
local an=a.load'x'.New



local ao={


Tabs={},
Containers={},
SelectedTab=nil,
TabCount=0,
ToolTipParent=nil,
TabHighlight=nil,

OnChangeFunc=function(ao)end,
}

function ao.Init(ap,aq,ar,as)
Window=ap
WindUI=aq
ao.ToolTipParent=ar
ao.TabHighlight=as
return ao
end

function ao.New(ap,aq)
local ar={
__type="Tab",
Title=ap.Title or"Tab",
Desc=ap.Desc,
Icon=ap.Icon,
IconColor=ap.IconColor,
IconShape=ap.IconShape,
IconThemed=ap.IconThemed,
Locked=ap.Locked,
ShowTabTitle=ap.ShowTabTitle,
TabTitleAlign=ap.TabTitleAlign or"Left",
CustomEmptyPage=(ap.CustomEmptyPage and next(ap.CustomEmptyPage)~=nil)and ap.CustomEmptyPage
or{Icon="lucide:frown",IconSize=48,Title="This tab is Empty",Desc=nil},
Border=ap.Border,
Selected=false,
Index=nil,
Parent=ap.Parent,
UIElements={},
Elements={},
ContainerFrame=nil,
UICorner=Window.UICorner-(Window.UIPadding/2),

Gap=Window.NewElements and 1 or 6,

TabPaddingX=4+(Window.UIPadding/2),
TabPaddingY=3+(Window.UIPadding/2),
TitlePaddingY=0,
}









if ar.IconShape then
ar.TabPaddingX=2+(Window.UIPadding/4)
ar.TabPaddingY=2+(Window.UIPadding/4)
ar.TitlePaddingY=2+(Window.UIPadding/4)
end

ao.TabCount=ao.TabCount+1

local as=ao.TabCount
ar.Index=as

ar.UIElements.Main=ak.NewRoundFrame(ar.UICorner,"Squircle",{
BackgroundTransparency=1,
Size=UDim2.new(1,-7,0,0),
AutomaticSize="Y",
Parent=ap.Parent,
ThemeTag={
ImageColor3="TabBackground",
},
ImageTransparency=1,
},{
ak.NewRoundFrame(ar.UICorner-1,"Glass-1.4",{
Size=UDim2.new(1,1,1,1),
ThemeTag={
ImageColor3="TabBorder",
},
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
ImageTransparency=1,
Name="Outline",
},{













}),
ak.NewRoundFrame(ar.UICorner,"Squircle",{
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
ThemeTag={
ImageColor3="Text",
},
ImageTransparency=1,
Name="Frame",
},{
al("UIListLayout",{
SortOrder="LayoutOrder",
Padding=UDim.new(0,2+(Window.UIPadding/2)),
FillDirection="Horizontal",
VerticalAlignment="Center",
}),
al("TextLabel",{
Text=ar.Title,
ThemeTag={
TextColor3="TabTitle",
},
TextTransparency=not ar.Locked and 0.4 or 0.7,
TextSize=15,
Size=UDim2.new(1,0,0,0),
FontFace=Font.new(ak.Font,Enum.FontWeight.Medium),
TextWrapped=true,
RichText=true,
AutomaticSize="Y",
LayoutOrder=2,
TextXAlignment="Left",
BackgroundTransparency=1,
},{
al("UIPadding",{
PaddingTop=UDim.new(0,ar.TitlePaddingY),


PaddingBottom=UDim.new(0,ar.TitlePaddingY),
}),
}),
al("UIPadding",{
PaddingTop=UDim.new(0,ar.TabPaddingY),
PaddingLeft=UDim.new(0,ar.TabPaddingX),
PaddingRight=UDim.new(0,ar.TabPaddingX),
PaddingBottom=UDim.new(0,ar.TabPaddingY),
}),
}),
},true)

local at=0
local au
local av

if ar.Icon then
au=ak.Image(
ar.Icon,
ar.Icon..":"..ar.Title,
0,
Window.Folder,
ar.__type,
ar.IconColor and false or true,
ar.IconThemed,
"TabIcon"
)
au.Size=UDim2.new(0,16,0,16)
if ar.IconColor then
au.ImageLabel.ImageColor3=ar.IconColor
end
if not ar.IconShape then
au.Parent=ar.UIElements.Main.Frame
ar.UIElements.Icon=au
au.ImageLabel.ImageTransparency=not ar.Locked and 0 or 0.7
at=-18-(Window.UIPadding/2)
ar.UIElements.Main.Frame.TextLabel.Size=UDim2.new(1,at,0,0)
elseif ar.IconColor then
ak.NewRoundFrame(
ar.IconShape~="Circle"and(ar.UICorner+5-(2+(Window.UIPadding/4)))or 9999,
"Squircle",
{
Size=UDim2.new(0,26,0,26),
ImageColor3=ar.IconColor,
Parent=ar.UIElements.Main.Frame,
},
{
au,
ak.NewRoundFrame(
ar.IconShape~="Circle"and(ar.UICorner+5-(2+(Window.UIPadding/4)))or 9999,
"Glass-1.4",
{
Size=UDim2.new(1,0,1,0),
ThemeTag={
ImageColor3="White",
},
ImageTransparency=0,
Name="Outline",
},
{













}
),
}
)
au.AnchorPoint=Vector2.new(0.5,0.5)
au.Position=UDim2.new(0.5,0,0.5,0)
au.ImageLabel.ImageTransparency=0
au.ImageLabel.ImageColor3=ak.GetTextColorForHSB(ar.IconColor,0.68)
at=-28-(Window.UIPadding/2)
ar.UIElements.Main.Frame.TextLabel.Size=UDim2.new(1,at,0,0)
end

av=
ak.Image(ar.Icon,ar.Icon..":"..ar.Title,0,Window.Folder,ar.__type,true,ar.IconThemed)
av.Size=UDim2.new(0,16,0,16)
av.ImageLabel.ImageTransparency=not ar.Locked and 0 or 0.7
at=-30




end

ar.UIElements.ContainerFrame=al("ScrollingFrame",{
Size=UDim2.new(1,0,1,ar.ShowTabTitle and-((Window.UIPadding*2.4)+12)or 0),
BackgroundTransparency=1,
ScrollBarThickness=0,
ElasticBehavior="Never",
CanvasSize=UDim2.new(0,0,0,0),
AnchorPoint=Vector2.new(0,1),
Position=UDim2.new(0,0,1,0),
AutomaticCanvasSize="Y",

ScrollingDirection="Y",
},{
al("UIPadding",{
PaddingTop=UDim.new(0,not Window.HidePanelBackground and 20 or 10),
PaddingLeft=UDim.new(0,not Window.HidePanelBackground and 20 or 10),
PaddingRight=UDim.new(0,not Window.HidePanelBackground and 20 or 10),
PaddingBottom=UDim.new(0,not Window.HidePanelBackground and 20 or 10),
}),
al("UIListLayout",{
SortOrder="LayoutOrder",
Padding=UDim.new(0,ar.Gap),
HorizontalAlignment="Center",
}),
})





ar.UIElements.ContainerFrameCanvas=al("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
Visible=false,
Parent=Window.UIElements.MainBar,
ZIndex=5,
},{
ar.UIElements.ContainerFrame,
al("Frame",{
Size=UDim2.new(1,-14,1,-14),
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
BackgroundTransparency=1,
Name="ScrollSliderHolder",
}),
al("Frame",{
Size=UDim2.new(1,0,0,((Window.UIPadding*2.4)+12)),
BackgroundTransparency=1,
Visible=ar.ShowTabTitle or false,
Name="TabTitle",
},{
av,
al("TextLabel",{
Text=ar.Title,
ThemeTag={
TextColor3="Text",
},
TextSize=20,
TextTransparency=0.1,
Size=UDim2.new(0,0,1,0),
FontFace=Font.new(ak.Font,Enum.FontWeight.SemiBold),

RichText=true,
LayoutOrder=2,
TextXAlignment="Left",
BackgroundTransparency=1,
AutomaticSize="X",
}),
al("UIPadding",{
PaddingTop=UDim.new(0,20),
PaddingLeft=UDim.new(0,20),
PaddingRight=UDim.new(0,20),
PaddingBottom=UDim.new(0,20),
}),
al("UIListLayout",{
SortOrder="LayoutOrder",
Padding=UDim.new(0,10),
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment=ar.TabTitleAlign,
}),
}),
al("Frame",{
Size=UDim2.new(1,0,0,1),
BackgroundTransparency=0.9,
ThemeTag={
BackgroundColor3="Text",
},
Position=UDim2.new(0,0,0,((Window.UIPadding*2.4)+12)),
Visible=ar.ShowTabTitle or false,
}),
})

ao.Containers[as]=ar.UIElements.ContainerFrameCanvas
ao.Tabs[as]=ar

ar.ContainerFrame=ar.UIElements.ContainerFrameCanvas

ak.AddSignal(ar.UIElements.Main.MouseButton1Click,function()
if not ar.Locked then
ao:SelectTab(as)
end
end)

if Window.ScrollBarEnabled then
an(
ar.UIElements.ContainerFrame,
ar.UIElements.ContainerFrameCanvas.ScrollSliderHolder,
Window,
4,
WindUI
)
end

local aw
local ax
local ay
local az=false


if ar.Desc then
ak.AddSignal(ar.UIElements.Main.InputBegan,function()
az=true
ax=task.spawn(function()
task.wait(0.35)
if az and not aw then
aw=am(ar.Desc,ao.ToolTipParent,true)
aw.Container.AnchorPoint=Vector2.new(0.5,0.5)

local function updatePosition()
if aw then
aw.Container.Position=UDim2.new(0,ai.X,0,ai.Y-4)
end
end

updatePosition()
ay=ai.Move:Connect(updatePosition)
aw:Open()
end
end)
end)
end

ak.AddSignal(ar.UIElements.Main.MouseEnter,function()
if not ar.Locked then
ak.SetThemeTag(ar.UIElements.Main.Frame,{
ImageTransparency="TabBackgroundHoverTransparency",
ImageColor3="TabBackgroundHover",
},0.1)
end
end)
ak.AddSignal(ar.UIElements.Main.InputEnded,function()
if ar.Desc then
az=false
if ax then
task.cancel(ax)
ax=nil
end
if ay then
ay:Disconnect()
ay=nil
end
if aw then
aw:Close()
aw=nil
end
end

if not ar.Locked then
ak.SetThemeTag(ar.UIElements.Main.Frame,{
ImageTransparency="TabBorderTransparency",
},0.1)
end
end)

function ar.ScrollToTheElement(aA,aB)
ar.UIElements.ContainerFrame.ScrollingEnabled=false

ak.Tween(ar.UIElements.ContainerFrame,0.45,{
CanvasPosition=Vector2.new(
0,
ar.Elements[aB].ElementFrame.AbsolutePosition.Y
-ar.UIElements.ContainerFrame.AbsolutePosition.Y
-ar.UIElements.ContainerFrame.UIPadding.PaddingTop.Offset
),
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()

task.spawn(function()
task.wait(0.48)

if ar.Elements[aB].Highlight then
ar.Elements[aB]:Highlight()
end
ar.UIElements.ContainerFrame.ScrollingEnabled=true
end)

return ar
end



local aA=a.load'_'

aA.Load(
ar,
ar.UIElements.ContainerFrame,
aA.Elements,
Window,
WindUI,
nil,
aA,
aq,
ar
)

function ar.LockAll(aB)

for b,d in next,Window.AllElements do
if d.Tab and d.Tab.Index and d.Tab.Index==ar.Index and d.Lock then
d:Lock()
end
end
end
function ar.UnlockAll(aB)
for b,d in next,Window.AllElements do
if d.Tab and d.Tab.Index and d.Tab.Index==ar.Index and d.Unlock then
d:Unlock()
end
end
end
function ar.GetLocked(aB)
local b={}

for d,f in next,Window.AllElements do
if f.Tab and f.Tab.Index and f.Tab.Index==ar.Index and f.Locked==true then
table.insert(b,f)
end
end

return b
end
function ar.GetUnlocked(aB)
local b={}

for d,f in next,Window.AllElements do
if f.Tab and f.Tab.Index and f.Tab.Index==ar.Index and f.Locked==false then
table.insert(b,f)
end
end

return b
end

function ar.Select(aB)
return ao:SelectTab(ar.Index)
end

task.spawn(function()
local aB
if ar.CustomEmptyPage.Icon then
aB=
ak.Image(ar.CustomEmptyPage.Icon,ar.CustomEmptyPage.Icon,0,"Temp","EmptyPage",true)
aB.Size=
UDim2.fromOffset(ar.CustomEmptyPage.IconSize or 48,ar.CustomEmptyPage.IconSize or 48)
end

local b=al("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,1,-Window.UIElements.Main.Main.Topbar.AbsoluteSize.Y),
Parent=ar.UIElements.ContainerFrame,
},{
al("UIListLayout",{
Padding=UDim.new(0,8),
SortOrder="LayoutOrder",
VerticalAlignment="Center",
HorizontalAlignment="Center",
FillDirection="Vertical",
}),











aB,
ar.CustomEmptyPage.Title and al("TextLabel",{
AutomaticSize="XY",
Text=ar.CustomEmptyPage.Title,
ThemeTag={
TextColor3="Text",
},
TextSize=18,
TextTransparency=0.5,
BackgroundTransparency=1,
FontFace=Font.new(ak.Font,Enum.FontWeight.Medium),
})or nil,
ar.CustomEmptyPage.Desc and al("TextLabel",{
AutomaticSize="XY",
Text=ar.CustomEmptyPage.Desc,
ThemeTag={
TextColor3="Text",
},
TextSize=15,
TextTransparency=0.65,
BackgroundTransparency=1,
FontFace=Font.new(ak.Font,Enum.FontWeight.Regular),
})or nil,
})





local d
d=ak.AddSignal(ar.UIElements.ContainerFrame.ChildAdded,function()
b.Visible=false
d:Disconnect()
end)
end)

return ar
end

function ao.OnChange(ap,aq)
ao.OnChangeFunc=aq
end

function ao.SelectTab(ap,aq)
if not ao.Tabs[aq].Locked then
ao.SelectedTab=aq

for ar,as in next,ao.Tabs do
if not as.Locked then
ak.SetThemeTag(as.UIElements.Main,{
ImageTransparency="TabBorderTransparency",
},0.15)
if as.Border then
ak.SetThemeTag(as.UIElements.Main.Outline,{
ImageTransparency="TabBorderTransparency",
},0.15)
end
ak.SetThemeTag(as.UIElements.Main.Frame.TextLabel,{
TextTransparency="TabTextTransparency",
},0.15)
if as.UIElements.Icon and not as.IconColor then
ak.SetThemeTag(as.UIElements.Icon.ImageLabel,{
ImageTransparency="TabIconTransparency",
},0.15)
end
as.Selected=false
end
end
ak.SetThemeTag(ao.Tabs[aq].UIElements.Main,{
ImageColor3="TabBackgroundActive",
ImageTransparency="TabBackgroundActiveTransparency",
},0.15)
if ao.Tabs[aq].Border then
ak.SetThemeTag(ao.Tabs[aq].UIElements.Main.Outline,{
ImageTransparency="TabBorderTransparencyActive",
},0.15)
end
ak.SetThemeTag(ao.Tabs[aq].UIElements.Main.Frame.TextLabel,{
TextTransparency="TabTextTransparencyActive",
},0.15)
if ao.Tabs[aq].UIElements.Icon and not ao.Tabs[aq].IconColor then
ak.SetThemeTag(ao.Tabs[aq].UIElements.Icon.ImageLabel,{
ImageTransparency="TabIconTransparencyActive",
},0.15)
end
ao.Tabs[aq].Selected=true

task.spawn(function()
for ar,as in next,ao.Containers do
as.AnchorPoint=Vector2.new(0,0.05)
as.Visible=false
end
ao.Containers[aq].Visible=true
local ar=game:GetService"TweenService"

local as=TweenInfo.new(0.15,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
local at=ar:Create(ao.Containers[aq],as,{
AnchorPoint=Vector2.new(0,0),
})
at:Play()
end)

ao.OnChangeFunc(aq)
end
end

return ao end function a.ab()

local aa={}


local af=a.load'd'
local ai=af.New
local ak=af.Tween

local al=a.load'aa'

function aa.New(am,an,ao,ap,aq)
local ar={
Title=am.Title or"Section",
Icon=am.Icon,
IconThemed=am.IconThemed,
Opened=am.Opened or false,

HeaderSize=42,
IconSize=18,

Expandable=false,
}

local as
if ar.Icon then
as=af.Image(
ar.Icon,
ar.Icon,
0,
ao,
"Section",
true,
ar.IconThemed,
"TabSectionIcon"
)

as.Size=UDim2.new(0,ar.IconSize,0,ar.IconSize)
as.ImageLabel.ImageTransparency=.25
end

local at=ai("Frame",{
Size=UDim2.new(0,ar.IconSize,0,ar.IconSize),
BackgroundTransparency=1,
Visible=false
},{
ai("ImageLabel",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
Image=af.Icon"chevron-down"[1],
ImageRectSize=af.Icon"chevron-down"[2].ImageRectSize,
ImageRectOffset=af.Icon"chevron-down"[2].ImageRectPosition,
ThemeTag={
ImageColor3="Icon",
},
ImageTransparency=.7,
})
})

local au=ai("Frame",{
Size=UDim2.new(1,0,0,ar.HeaderSize),
BackgroundTransparency=1,
Parent=an,
ClipsDescendants=true,
},{
ai("TextButton",{
Size=UDim2.new(1,0,0,ar.HeaderSize),
BackgroundTransparency=1,
Text="",
},{
as,
ai("TextLabel",{
Text=ar.Title,
TextXAlignment="Left",
Size=UDim2.new(
1,
as and(-ar.IconSize-10)*2
or(-ar.IconSize-10),

1,
0
),
ThemeTag={
TextColor3="Text",
},
FontFace=Font.new(af.Font,Enum.FontWeight.SemiBold),
TextSize=14,
BackgroundTransparency=1,
TextTransparency=.7,

TextWrapped=true
}),
ai("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
Padding=UDim.new(0,10)
}),
at,
ai("UIPadding",{
PaddingLeft=UDim.new(0,11),
PaddingRight=UDim.new(0,11),
})
}),
ai("Frame",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
Name="Content",
Visible=true,
Position=UDim2.new(0,0,0,ar.HeaderSize)
},{
ai("UIListLayout",{
FillDirection="Vertical",
Padding=UDim.new(0,aq.Gap),
VerticalAlignment="Bottom",
}),
})
})


function ar.Tab(av,aw)
if not ar.Expandable then
ar.Expandable=true
at.Visible=true
end
aw.Parent=au.Content
return al.New(aw,ap)
end

function ar.Open(av)
if ar.Expandable then
ar.Opened=true
ak(au,0.33,{
Size=UDim2.new(1,0,0,ar.HeaderSize+(au.Content.AbsoluteSize.Y/ap))
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()

ak(at.ImageLabel,0.1,{Rotation=180},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end
end
function ar.Close(av)
if ar.Expandable then
ar.Opened=false
ak(au,0.26,{
Size=UDim2.new(1,0,0,ar.HeaderSize)
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
ak(at.ImageLabel,0.1,{Rotation=0},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end
end

af.AddSignal(au.TextButton.MouseButton1Click,function()
if ar.Expandable then
if ar.Opened then
ar:Close()
else
ar:Open()
end
end
end)

af.AddSignal(au.Content.UIListLayout:GetPropertyChangedSignal"AbsoluteContentSize",function()
if ar.Opened then
ar:Open()
end
end)

if ar.Opened then
task.spawn(function()
task.wait()
ar:Open()
end)
end



return ar
end


return aa end function a.ac()
return{
Tab="table-of-contents",
Paragraph="type",
Button="square-mouse-pointer",
Toggle="toggle-right",
Slider="sliders-horizontal",
Keybind="command",
Input="text-cursor-input",
Dropdown="chevrons-up-down",
Code="terminal",
Colorpicker="palette",
}end function a.ad()
local aa=(cloneref or clonereference or function(aa)
return aa
end)

aa(game:GetService"UserInputService")

local af={
Margin=8,
Padding=9,
}

local ai=a.load'd'
local ak=ai.New
local al=ai.Tween

function af.new(am,an,ao)
local ap={
IconSize=18,
Padding=14,
Radius=22,
Width=400,
MaxHeight=380,

Icons=a.load'ac',
}

local aq=ak("TextBox",{
Text="",
PlaceholderText="Search...",
ThemeTag={
PlaceholderColor3="Placeholder",
TextColor3="Text",
},
Size=UDim2.new(1,-((ap.IconSize*2)+(ap.Padding*2)),0,0),
AutomaticSize="Y",
ClipsDescendants=true,
ClearTextOnFocus=false,
BackgroundTransparency=1,
TextXAlignment="Left",
FontFace=Font.new(ai.Font,Enum.FontWeight.Regular),
TextSize=18,
})

local ar=ak("ImageLabel",{
Image=ai.Icon"x"[1],
ImageRectSize=ai.Icon"x"[2].ImageRectSize,
ImageRectOffset=ai.Icon"x"[2].ImageRectPosition,
BackgroundTransparency=1,
ThemeTag={
ImageColor3="Icon",
},
ImageTransparency=0.1,
Size=UDim2.new(0,ap.IconSize,0,ap.IconSize),
},{
ak("TextButton",{
Size=UDim2.new(1,8,1,8),
BackgroundTransparency=1,
Active=true,
ZIndex=999999999,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Text="",
}),
})

local as=ak("ScrollingFrame",{
Size=UDim2.new(1,0,0,0),
AutomaticCanvasSize="Y",
ScrollingDirection="Y",
ElasticBehavior="Never",
ScrollBarThickness=0,
CanvasSize=UDim2.new(0,0,0,0),
BackgroundTransparency=1,
Visible=false,
},{
ak("UIListLayout",{
Padding=UDim.new(0,0),
FillDirection="Vertical",
}),
ak("UIPadding",{
PaddingTop=UDim.new(0,ap.Padding),
PaddingLeft=UDim.new(0,ap.Padding),
PaddingRight=UDim.new(0,ap.Padding),
PaddingBottom=UDim.new(0,ap.Padding),
}),
})

local at=ai.NewRoundFrame(ap.Radius,"Squircle",{
Size=UDim2.new(1,0,1,0),
ThemeTag={
ImageColor3="WindowSearchBarBackground",
},
ImageTransparency=0,
},{
ai.NewRoundFrame(ap.Radius,"Squircle",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,

Visible=false,
ThemeTag={
ImageColor3="White",
},
ImageTransparency=1,
Name="Frame",
},{
ak("Frame",{
Size=UDim2.new(1,0,0,46),
BackgroundTransparency=1,
},{








ak("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
},{
ak("ImageLabel",{
Image=ai.Icon"search"[1],
ImageRectSize=ai.Icon"search"[2].ImageRectSize,
ImageRectOffset=ai.Icon"search"[2].ImageRectPosition,
BackgroundTransparency=1,
ThemeTag={
ImageColor3="Icon",
},
ImageTransparency=0.1,
Size=UDim2.new(0,ap.IconSize,0,ap.IconSize),
}),
aq,
ar,
ak("UIListLayout",{
Padding=UDim.new(0,ap.Padding),
FillDirection="Horizontal",
VerticalAlignment="Center",
}),
ak("UIPadding",{
PaddingLeft=UDim.new(0,ap.Padding),
PaddingRight=UDim.new(0,ap.Padding),
}),
}),
}),
ak("Frame",{
BackgroundTransparency=1,
AutomaticSize="Y",
Size=UDim2.new(1,0,0,0),
Name="Results",
},{
ak("Frame",{
Size=UDim2.new(1,0,0,1),
ThemeTag={
BackgroundColor3="Outline",
},
BackgroundTransparency=0.9,
Visible=false,
}),
as,
ak("UISizeConstraint",{
MaxSize=Vector2.new(ap.Width,ap.MaxHeight),
}),
}),
ak("UIListLayout",{
Padding=UDim.new(0,0),
FillDirection="Vertical",
}),
}),
})

local au=ak("Frame",{
Size=UDim2.new(0,ap.Width,0,0),
AutomaticSize="Y",
Parent=an,
BackgroundTransparency=1,
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
Visible=false,

ZIndex=99999999,
},{
ak("UIScale",{
Scale=0.9,
}),
at,















})

local function CreateSearchTab(av,aw,ax,ay,az,aA)
local aB=ak("TextButton",{
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
BackgroundTransparency=1,
Parent=ay or nil,
},{
ai.NewRoundFrame(ap.Radius-11,"Squircle",{
Size=UDim2.new(1,0,0,0),
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),

ThemeTag={
ImageColor3="Text",
},
ImageTransparency=1,
Name="Main",
},{
ai.NewRoundFrame(ap.Radius-11,"Glass-1",{
Size=UDim2.new(1,0,1,0),
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
ThemeTag={
ImageColor3="White",
},
ImageTransparency=1,
Name="Outline",
},{








ak("UIPadding",{
PaddingTop=UDim.new(0,ap.Padding-2),
PaddingLeft=UDim.new(0,ap.Padding),
PaddingRight=UDim.new(0,ap.Padding),
PaddingBottom=UDim.new(0,ap.Padding-2),
}),
ak("ImageLabel",{
Image=ai.Icon(ax)[1],
ImageRectSize=ai.Icon(ax)[2].ImageRectSize,
ImageRectOffset=ai.Icon(ax)[2].ImageRectPosition,
BackgroundTransparency=1,
ThemeTag={
ImageColor3="Icon",
},
ImageTransparency=0.1,
Size=UDim2.new(0,ap.IconSize,0,ap.IconSize),
}),
ak("Frame",{
Size=UDim2.new(1,-ap.IconSize-ap.Padding,0,0),
BackgroundTransparency=1,
},{
ak("TextLabel",{
Text=av,
ThemeTag={
TextColor3="Text",
},
TextSize=17,
BackgroundTransparency=1,
TextXAlignment="Left",
FontFace=Font.new(ai.Font,Enum.FontWeight.Medium),
Size=UDim2.new(1,0,0,0),
TextTruncate="AtEnd",
AutomaticSize="Y",
Name="Title",
}),
ak("TextLabel",{
Text=aw or"",
Visible=aw and true or false,
ThemeTag={
TextColor3="Text",
},
TextSize=15,
TextTransparency=0.3,
BackgroundTransparency=1,
TextXAlignment="Left",
FontFace=Font.new(ai.Font,Enum.FontWeight.Medium),
Size=UDim2.new(1,0,0,0),
TextTruncate="AtEnd",
AutomaticSize="Y",
Name="Desc",
})or nil,
ak("UIListLayout",{
Padding=UDim.new(0,6),
FillDirection="Vertical",
}),
}),
ak("UIListLayout",{
Padding=UDim.new(0,ap.Padding),
FillDirection="Horizontal",
}),
}),
},true),
ak("Frame",{
Name="ParentContainer",
Size=UDim2.new(1,-ap.Padding,0,0),
AutomaticSize="Y",
BackgroundTransparency=1,
Visible=az,

},{
ai.NewRoundFrame(99,"Squircle",{
Size=UDim2.new(0,2,1,0),
BackgroundTransparency=1,
ThemeTag={
ImageColor3="Text",
},
ImageTransparency=0.9,
}),
ak("Frame",{
Size=UDim2.new(1,-ap.Padding-2,0,0),
Position=UDim2.new(0,ap.Padding+2,0,0),
BackgroundTransparency=1,
},{
ak("UIListLayout",{
Padding=UDim.new(0,0),
FillDirection="Vertical",
}),
}),
}),
ak("UIListLayout",{
Padding=UDim.new(0,0),
FillDirection="Vertical",
HorizontalAlignment="Right",
}),
})



aB.Main.Size=UDim2.new(
1,
0,
0,
aB.Main.Outline.Frame.Desc.Visible
and(((ap.Padding-2)*2)+aB.Main.Outline.Frame.Title.TextBounds.Y+6+aB.Main.Outline.Frame.Desc.TextBounds.Y)
or(((ap.Padding-2)*2)+aB.Main.Outline.Frame.Title.TextBounds.Y)
)

ai.AddSignal(aB.Main.MouseEnter,function()
al(aB.Main,0.04,{ImageTransparency=0.95}):Play()

end)
ai.AddSignal(aB.Main.InputEnded,function()
al(aB.Main,0.08,{ImageTransparency=1}):Play()

end)
ai.AddSignal(aB.Main.MouseButton1Click,function()
if aA then
aA()
end
end)

return aB
end

local function ContainsText(av,aw)
if not aw or aw==""then
return false
end

if not av or av==""then
return false
end

local ax=string.lower(av)
local ay=string.lower(aw)

return string.find(ax,ay,1,true)~=nil
end

local function Search(av)
if not av or av==""then
return{}
end

local aw={}
for ax,ay in next,am.Tabs do
local az=ContainsText(ay.Title or"",av)
local aA={}

for aB,b in next,ay.Elements do
if b.__type~="Section"then
local d=ContainsText(b.Title or"",av)
local f=ContainsText(b.Desc or"",av)

if d or f then
aA[aB]={
Title=b.Title,
Desc=b.Desc,
Original=b,
__type=b.__type,
Index=aB,
}
end
end
end

if az or next(aA)~=nil then
aw[ax]={
Tab=ay,
Title=ay.Title,
Icon=ay.Icon,
Elements=aA,
}
end
end
return aw
end

ai.AddSignal(as.UIListLayout:GetPropertyChangedSignal"AbsoluteContentSize",function()

al(as,0.06,{
Size=UDim2.new(
1,
0,
0,
math.clamp(
as.UIListLayout.AbsoluteContentSize.Y+(ap.Padding*2),
0,
ap.MaxHeight
)
),
},Enum.EasingStyle.Quint,Enum.EasingDirection.InOut):Play()






end)

function ap.Open(av)
task.spawn(function()
at.Frame.Visible=true
au.Visible=true
al(au.UIScale,0.12,{Scale=1},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end)
end

function ap.Close(av,aw)
task.spawn(function()
ao()
at.Frame.Visible=false
al(au.UIScale,0.12,{Scale=1},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()

task.wait(0.12)
au.Visible=false
if aw then
au:Destroy()
end
end)
end

ai.AddSignal(ar.TextButton.MouseButton1Click,function()
ap:Close(true)
end)

ap:Open()

function ap.Search(av,aw)
aw=aw or""

local ax=Search(aw)

as.Visible=true
at.Frame.Results.Frame.Visible=true
for ay,az in next,as:GetChildren()do
if az.ClassName~="UIListLayout"and az.ClassName~="UIPadding"then
az:Destroy()
end
end

if ax and next(ax)~=nil then
for ay,az in next,ax do
local aA=ap.Icons.Tab
local aB=CreateSearchTab(az.Title,nil,aA,as,true,function()
ap:Close()
am:SelectTab(ay)
end)
if az.Elements and next(az.Elements)~=nil then
for b,d in next,az.Elements do
local f=ap.Icons[d.__type]
CreateSearchTab(
d.Title,
d.Desc,
f,
aB:FindFirstChild"ParentContainer"and aB.ParentContainer.Frame
or nil,
false,
function()
ap:Close()
am:SelectTab(ay)
if az.Tab.ScrollToTheElement then

az.Tab:ScrollToTheElement(d.Index)
end

end
)

end
end
end
elseif aw~=""then
ak("TextLabel",{
Size=UDim2.new(1,0,0,70),
Text="No results found",
TextSize=16,
ThemeTag={
TextColor3="Text",
},
TextTransparency=0.2,
BackgroundTransparency=1,
FontFace=Font.new(ai.Font,Enum.FontWeight.Medium),
Parent=as,
Name="NotFound",
})
else
as.Visible=false
at.Frame.Results.Frame.Visible=false
end
end

ai.AddSignal(aq:GetPropertyChangedSignal"Text",function()
ap:Search(aq.Text)
end)

return ap
end

return af end function a.ae()



local aa=(cloneref or clonereference or function(aa)
return aa
end)

local af=aa(game:GetService"UserInputService")
local ai=aa(game:GetService"RunService")
local ak=aa(game:GetService"Players")

local al=workspace.CurrentCamera

local am=a.load't'

local an=a.load'd'
local ao=an.New
local ap=an.Tween


local aq=a.load'w'.New
local ar=a.load'm'.New
local as=a.load'x'.New
local at=a.load'y'

local au=a.load'z'



return function(av)
local aw={
Title=av.Title or"UI Library",
Author=av.Author,
Icon=av.Icon,
IconSize=av.IconSize or 22,
IconThemed=av.IconThemed,
IconRadius=av.IconRadius or 0,
Folder=av.Folder,
Resizable=av.Resizable~=false,
Background=av.Background,
BackgroundImageTransparency=av.BackgroundImageTransparency or 0,
ShadowTransparency=av.ShadowTransparency or 0.6,
User=av.User or{},
Footer=av.Footer or{},
Topbar=av.Topbar or{Height=52,ButtonsType="Default"},

Size=av.Size,

MinSize=av.MinSize or Vector2.new(560,350),
MaxSize=av.MaxSize or Vector2.new(850,560),

TopBarButtonIconSize=av.TopBarButtonIconSize,

ToggleKey=av.ToggleKey,
ElementsRadius=av.ElementsRadius,
Radius=av.Radius or 16,
Transparent=av.Transparent or false,
HideSearchBar=av.HideSearchBar~=false,
ScrollBarEnabled=av.ScrollBarEnabled or false,
SideBarWidth=av.SideBarWidth or 200,
Acrylic=av.Acrylic or false,
NewElements=av.NewElements or false,
IgnoreAlerts=av.IgnoreAlerts or false,
HidePanelBackground=av.HidePanelBackground or false,
AutoScale=av.AutoScale~=false,
OpenButton=av.OpenButton,
DragFrameSize=160,

Position=UDim2.new(0.5,0,0.5,0),
UICorner=16,
UIPadding=14,
UIElements={},
CanDropdown=true,
Closed=false,
Parent=av.Parent,
Destroyed=false,
IsFullscreen=false,
CanResize=av.Resizable~=false,
IsOpenButtonEnabled=true,

CurrentConfig=nil,
ConfigManager=nil,
AcrylicPaint=nil,
CurrentTab=nil,
TabModule=nil,

OnOpenCallback=nil,
OnCloseCallback=nil,
OnDestroyCallback=nil,

IsPC=false,

Gap=5,

TopBarButtons={},
AllElements={},

ElementConfig={},

PendingFlags={},

IsToggleDragging=false,
}

aw.UICorner=aw.Radius

aw.TopBarButtonIconSize=aw.TopBarButtonIconSize or(aw.Topbar.ButtonsType=="Mac"and 11 or 16)

aw.ElementConfig={
UIPadding=(aw.NewElements and 10 or 13),
UICorner=aw.ElementsRadius or(aw.NewElements and 23 or 16),
}

local ax=aw.Size or UDim2.new(0,580,0,460)
aw.Size=UDim2.new(
ax.X.Scale,
math.clamp(ax.X.Offset,aw.MinSize.X,aw.MaxSize.X),
ax.Y.Scale,
math.clamp(ax.Y.Offset,aw.MinSize.Y,aw.MaxSize.Y)
)

if aw.Topbar=={}then
aw.Topbar={Height=52,ButtonsType="Default"}
end

if not ai:IsStudio()and aw.Folder and writefile then
if not isfolder("WindUI/"..aw.Folder)then
makefolder("WindUI/"..aw.Folder)
end
if not isfolder("WindUI/"..aw.Folder.."/assets")then
makefolder("WindUI/"..aw.Folder.."/assets")
end
if not isfolder(aw.Folder)then
makefolder(aw.Folder)
end
if not isfolder(aw.Folder.."/assets")then
makefolder(aw.Folder.."/assets")
end
end

local ay=ao("UICorner",{
CornerRadius=UDim.new(0,aw.UICorner),
})

if aw.Folder then
aw.ConfigManager=au:Init(aw)
end

if aw.Acrylic then local
az=am.AcrylicPaint{UseAcrylic=aw.Acrylic}

aw.AcrylicPaint=az
end

local az=ao("Frame",{
Size=UDim2.new(0,32,0,32),
Position=UDim2.new(1,0,1,0),
AnchorPoint=Vector2.new(0.5,0.5),
BackgroundTransparency=1,
ZIndex=99,
Active=true,
},{
ao("ImageLabel",{
Size=UDim2.new(0,96,0,96),
BackgroundTransparency=1,
Image="rbxassetid://120997033468887",
Position=UDim2.new(0.5,-16,0.5,-16),
AnchorPoint=Vector2.new(0.5,0.5),
ImageTransparency=1,
}),
})
local aA=an.NewRoundFrame(aw.UICorner,"Squircle",{
Size=UDim2.new(1,0,1,0),
ImageTransparency=1,
ImageColor3=Color3.new(0,0,0),
ZIndex=98,
Active=false,
},{
ao("ImageLabel",{
Size=UDim2.new(0,70,0,70),
Image=an.Icon"expand"[1],
ImageRectOffset=an.Icon"expand"[2].ImageRectPosition,
ImageRectSize=an.Icon"expand"[2].ImageRectSize,
BackgroundTransparency=1,
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
ImageTransparency=1,
}),
})

local aB=an.NewRoundFrame(aw.UICorner,"Squircle",{
Size=UDim2.new(1,0,1,0),
ImageTransparency=1,
ImageColor3=Color3.new(0,0,0),
ZIndex=999,
Active=false,
})









aw.UIElements.SideBar=ao("ScrollingFrame",{
Size=UDim2.new(
1,
aw.ScrollBarEnabled and-3-(aw.UIPadding/2)or 0,
1,
not aw.HideSearchBar and-45 or 0
),
Position=UDim2.new(0,0,1,0),
AnchorPoint=Vector2.new(0,1),
BackgroundTransparency=1,
ScrollBarThickness=0,
ElasticBehavior="Never",
CanvasSize=UDim2.new(0,0,0,0),
AutomaticCanvasSize="Y",
ScrollingDirection="Y",
ClipsDescendants=true,
VerticalScrollBarPosition="Left",
},{
ao("Frame",{
BackgroundTransparency=1,
AutomaticSize="Y",
Size=UDim2.new(1,0,0,0),
Name="Frame",
},{
ao("UIPadding",{



PaddingBottom=UDim.new(0,aw.UIPadding/2),
}),
ao("UIListLayout",{
SortOrder="LayoutOrder",
Padding=UDim.new(0,aw.Gap),
}),
}),
ao("UIPadding",{

PaddingLeft=UDim.new(0,aw.UIPadding/2),
PaddingRight=UDim.new(0,aw.UIPadding/2),
PaddingBottom=UDim.new(0,aw.UIPadding/2),
}),

})

aw.UIElements.SideBarContainer=ao("Frame",{
Size=UDim2.new(
0,
aw.SideBarWidth,
1,
aw.User.Enabled and-aw.Topbar.Height-42-(aw.UIPadding*2)or-aw.Topbar.Height
),
Position=UDim2.new(0,0,0,aw.Topbar.Height),
BackgroundTransparency=1,
Visible=true,
},{
ao("Frame",{
Name="Content",
BackgroundTransparency=1,
Size=UDim2.new(1,0,1,not aw.HideSearchBar and-45-aw.UIPadding or-aw.UIPadding/2),
Position=UDim2.new(0,0,1,-aw.UIPadding/2),
AnchorPoint=Vector2.new(0,1),
}),
aw.UIElements.SideBar,
})

if aw.ScrollBarEnabled then
as(
aw.UIElements.SideBar,
aw.UIElements.SideBarContainer.Content,
aw,
3,
av.WindUI
)
end

aw.UIElements.MainBar=ao("Frame",{
Size=UDim2.new(1,-aw.UIElements.SideBarContainer.AbsoluteSize.X,1,-aw.Topbar.Height),
Position=UDim2.new(1,0,1,0),
AnchorPoint=Vector2.new(1,1),
BackgroundTransparency=1,
},{
an.NewRoundFrame(aw.UICorner-(aw.UIPadding/2),"Squircle",{
Size=UDim2.new(1,0,1,0),
ThemeTag={
ImageColor3="PanelBackground",
ImageTransparency="PanelBackgroundTransparency",
},


ZIndex=3,
Name="Background",
Visible=not aw.HidePanelBackground,
}),
ao("UIPadding",{

PaddingLeft=UDim.new(0,aw.UIPadding/2),
PaddingRight=UDim.new(0,aw.UIPadding/2),
PaddingBottom=UDim.new(0,aw.UIPadding/2),
}),
})

local b=ao("ImageLabel",{
Image="rbxassetid://8992230677",
ThemeTag={
ImageColor3="WindowShadow",

},
ImageTransparency=1,
Size=UDim2.new(1,100,1,100),
Position=UDim2.new(0,-50,0,-50),
ScaleType="Slice",
SliceCenter=Rect.new(99,99,99,99),
BackgroundTransparency=1,
ZIndex=-999999999999999,
Name="Blur",
})

if af.TouchEnabled and not af.KeyboardEnabled then
aw.IsPC=false
elseif af.KeyboardEnabled then
aw.IsPC=true
else
aw.IsPC=nil
end







local d
if aw.User then
local function GetUserThumb()local
f=ak:GetUserThumbnailAsync(
aw.User.Anonymous and 1 or ak.LocalPlayer.UserId,
Enum.ThumbnailType.HeadShot,
Enum.ThumbnailSize.Size420x420
)
return f
end

d=ao("TextButton",{
Size=UDim2.new(
0,
aw.UIElements.SideBarContainer.AbsoluteSize.X-(aw.UIPadding/2),
0,
42+aw.UIPadding
),
Position=UDim2.new(0,aw.UIPadding/2,1,-(aw.UIPadding/2)),
AnchorPoint=Vector2.new(0,1),
BackgroundTransparency=1,
Visible=aw.User.Enabled or false,
},{
an.NewRoundFrame(aw.UICorner-(aw.UIPadding/2),"SquircleOutline",{
Size=UDim2.new(1,0,1,0),
ThemeTag={
ImageColor3="Text",
},
ImageTransparency=1,
Name="Outline",
},{
ao("UIGradient",{
Rotation=78,
Color=ColorSequence.new{
ColorSequenceKeypoint.new(0.0,Color3.fromRGB(255,255,255)),
ColorSequenceKeypoint.new(0.5,Color3.fromRGB(255,255,255)),
ColorSequenceKeypoint.new(1.0,Color3.fromRGB(255,255,255)),
},
Transparency=NumberSequence.new{
NumberSequenceKeypoint.new(0.0,0.1),
NumberSequenceKeypoint.new(0.5,1),
NumberSequenceKeypoint.new(1.0,0.1),
},
}),
}),
an.NewRoundFrame(aw.UICorner-(aw.UIPadding/2),"Squircle",{
Size=UDim2.new(1,0,1,0),
ThemeTag={
ImageColor3="Text",
},
ImageTransparency=1,
Name="UserIcon",
},{
ao("ImageLabel",{
Image=GetUserThumb(),
BackgroundTransparency=1,
Size=UDim2.new(0,42,0,42),
ThemeTag={
BackgroundColor3="Text",
},
BackgroundTransparency=0.93,
},{
ao("UICorner",{
CornerRadius=UDim.new(1,0),
}),
}),
ao("Frame",{
AutomaticSize="XY",
BackgroundTransparency=1,
},{
ao("TextLabel",{
Text=aw.User.Anonymous and"Anonymous"or ak.LocalPlayer.DisplayName,
TextSize=17,
ThemeTag={
TextColor3="Text",
},
FontFace=Font.new(an.Font,Enum.FontWeight.SemiBold),
AutomaticSize="Y",
BackgroundTransparency=1,
Size=UDim2.new(1,-27,0,0),
TextTruncate="AtEnd",
TextXAlignment="Left",
Name="DisplayName",
}),
ao("TextLabel",{
Text=aw.User.Anonymous and"anonymous"or ak.LocalPlayer.Name,
TextSize=15,
TextTransparency=0.6,
ThemeTag={
TextColor3="Text",
},
FontFace=Font.new(an.Font,Enum.FontWeight.Medium),
AutomaticSize="Y",
BackgroundTransparency=1,
Size=UDim2.new(1,-27,0,0),
TextTruncate="AtEnd",
TextXAlignment="Left",
Name="UserName",
}),
ao("UIListLayout",{
Padding=UDim.new(0,4),
HorizontalAlignment="Left",
}),
}),
ao("UIListLayout",{
Padding=UDim.new(0,aw.UIPadding),
FillDirection="Horizontal",
VerticalAlignment="Center",
}),
ao("UIPadding",{
PaddingLeft=UDim.new(0,aw.UIPadding/2),
PaddingRight=UDim.new(0,aw.UIPadding/2),
}),
}),
})

function aw.User.Enable(f)
aw.User.Enabled=true
ap(
aw.UIElements.SideBarContainer,
0.25,
{Size=UDim2.new(0,aw.SideBarWidth,1,-aw.Topbar.Height-42-(aw.UIPadding*2))},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
d.Visible=true
end
function aw.User.Disable(f)
aw.User.Enabled=false
ap(
aw.UIElements.SideBarContainer,
0.25,
{Size=UDim2.new(0,aw.SideBarWidth,1,-aw.Topbar.Height)},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
d.Visible=false
end
function aw.User.SetAnonymous(f,g)
if g~=false then
g=true
end
aw.User.Anonymous=g
d.UserIcon.ImageLabel.Image=GetUserThumb()
d.UserIcon.Frame.DisplayName.Text=g and"Anonymous"or ak.LocalPlayer.DisplayName
d.UserIcon.Frame.UserName.Text=g and"anonymous"or ak.LocalPlayer.Name
end

if aw.User.Enabled then
aw.User:Enable()
else
aw.User:Disable()
end

if aw.User.Callback then
an.AddSignal(d.MouseButton1Click,function()
aw.User.Callback()
end)
an.AddSignal(d.MouseEnter,function()
ap(d.UserIcon,0.04,{ImageTransparency=0.95}):Play()
ap(d.Outline,0.04,{ImageTransparency=0.85}):Play()
end)
an.AddSignal(d.InputEnded,function()
ap(d.UserIcon,0.04,{ImageTransparency=1}):Play()
ap(d.Outline,0.04,{ImageTransparency=1}):Play()
end)
end
end

local f
local g

local h=false
local i

local l=typeof(aw.Background)=="string"and string.match(aw.Background,"^video:(.+)")or nil

local m=typeof(aw.Background)=="string"
and not l
and string.match(aw.Background,"^https?://.+")
or nil

local p=typeof(aw.Background)=="string"
and not l
and string.match(aw.Background,"^rbxassetid://%d+")
or nil

local function GetImageExtension(r)
if not r or typeof(r)~="string"then
return".png"
end
local u=r:match"^([^?#]+)"or r
local v=u:match"%.(%w+)$"
if v then
v=v:lower()
if v=="jpg"or v=="jpeg"or v=="png"or v=="webp"then
return"."..v
end
end
return".png"
end



if typeof(aw.Background)=="string"and l then
h=true

if string.find(l,"http")then
local r=(aw.Folder or"Temp").."/assets/."..an.SanitizeFilename(l)..".webm"
if not isfile(r)then
local u,v=pcall(function()





local u=game.HttpGet and game:HttpGet(l)
or an.Request{
Url=l,
Method="GET",
Headers={["User-Agent"]="Roblox/Exploit"},
}.Body

writefile(r,u)
end)
if not u then
warn("[ WindUI.Window.Background ] Failed to download video: "..tostring(v))
end
end

local u,v=pcall(function()
return getcustomasset(r)
end)
if not u then
warn("[ WindUI.Window.Background ] Failed to load custom asset: "..tostring(v))
end
warn"[ WindUI.Window.Background ] VideoFrame may not work with custom video"
l=v
end

i=ao("VideoFrame",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,1,0),
Video=l,
Looped=true,
Volume=0,
},{
ao("UICorner",{
CornerRadius=UDim.new(0,aw.UICorner),
}),
})
i:Play()
elseif m then
local r=(aw.Folder or"Temp")
.."/assets/."
..an.SanitizeFilename(m)
..GetImageExtension(m)

if isfile and not isfile(r)then
local u,v=pcall(function()
local u=game.HttpGet and game:HttpGet(m)
or an.Request{
Url=m,
Method="GET",
Headers={["User-Agent"]="Roblox/Exploit"},
}.Body

writefile(r,u)
end)

if not u then
warn("[ Window.Background ] Failed to download image: "..tostring(v))
end
end

local u,v=pcall(function()
return getcustomasset(r)
end)

if not u then
warn("[ Window.Background ] Failed to load custom asset: "..tostring(v))
end

i=ao("ImageLabel",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,1,0),
Image=v,
ImageTransparency=0,
ScaleType="Crop",
},{
ao("UICorner",{
CornerRadius=UDim.new(0,aw.UICorner),
}),
})
elseif p then
i=ao("ImageLabel",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,1,0),
Image=p,
ImageTransparency=0,
ScaleType="Crop",
},{
ao("UICorner",{
CornerRadius=UDim.new(0,aw.UICorner),
}),
})
elseif aw.Background then
i=ao("ImageLabel",{
BackgroundTransparency=1,
Size=UDim2.new(1,0,1,0),
Image=typeof(aw.Background)=="string"and aw.Background or"",
ImageTransparency=1,
ScaleType="Crop",
},{
ao("UICorner",{
CornerRadius=UDim.new(0,aw.UICorner),
}),
})
end

local r=an.NewRoundFrame(99,"Squircle",{
ImageTransparency=0.8,
ImageColor3=Color3.new(1,1,1),
Size=UDim2.new(0,0,0,4),
Position=UDim2.new(0.5,0,1,4),
AnchorPoint=Vector2.new(0.5,0),
},{
ao("TextButton",{
Size=UDim2.new(1,12,1,12),
BackgroundTransparency=1,
Position=UDim2.new(0.5,0,0.5,0),
AnchorPoint=Vector2.new(0.5,0.5),
Active=true,
ZIndex=99,
Name="Frame",
}),
})

function createAuthor(u)
return ao("TextLabel",{
Text=u,
FontFace=Font.new(an.Font,Enum.FontWeight.Medium),
BackgroundTransparency=1,
TextTransparency=0.35,
AutomaticSize="XY",
Parent=aw.UIElements.Main and aw.UIElements.Main.Main.Topbar.Left.Title,
TextXAlignment="Left",
TextSize=13,
LayoutOrder=2,
ThemeTag={
TextColor3="WindowTopbarAuthor",
},
Name="Author",
})
end

local u
local v

if aw.Author then
u=createAuthor(aw.Author)
end

local x=ao("TextLabel",{
Text=aw.Title,
FontFace=Font.new(an.Font,Enum.FontWeight.SemiBold),
BackgroundTransparency=1,
AutomaticSize="XY",
Name="Title",
TextXAlignment="Left",
TextSize=16,
ThemeTag={
TextColor3="WindowTopbarTitle",
},
})

aw.UIElements.Main=ao("Frame",{
Size=UDim2.new(aw.Size.X.Scale,aw.Size.X.Offset,0,0),
Position=aw.Position,
BackgroundTransparency=1,
Parent=av.Parent,
AnchorPoint=Vector2.new(0.5,0.5),
Active=true,

},{
av.WindUI.UIScaleObj,
aw.AcrylicPaint and aw.AcrylicPaint.Frame or nil,
b,
an.NewRoundFrame(aw.UICorner,"Squircle",{
ImageTransparency=1,
Size=UDim2.new(1,0,1,0),
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
Name="Background",
ThemeTag={
ImageColor3="WindowBackground",
},

},{
i,
r,
az,
}),




ay,
aA,
aB,
ao("Frame",{
Size=UDim2.new(1,0,1,0),
BackgroundTransparency=1,
Name="Main",

Visible=false,
ZIndex=97,
},{
ao("UICorner",{
CornerRadius=UDim.new(0,aw.UICorner),
}),
aw.UIElements.SideBarContainer,
aw.UIElements.MainBar,

d,

g,
ao("Frame",{
Size=UDim2.new(1,0,0,aw.Topbar.Height),
BackgroundTransparency=1,
BackgroundColor3=Color3.fromRGB(50,50,50),
Name="Topbar",
},{
f,






ao("Frame",{
AutomaticSize="X",
Size=UDim2.new(0,0,1,0),
BackgroundTransparency=1,
Name="Left",
},{
ao("UIListLayout",{
Padding=UDim.new(0,aw.UIPadding+4),
SortOrder="LayoutOrder",
FillDirection="Horizontal",
VerticalAlignment="Center",
}),
ao("Frame",{
AutomaticSize="XY",
BackgroundTransparency=1,
Name="Title",
Size=UDim2.new(0,0,1,0),
LayoutOrder=2,
},{
ao("UIListLayout",{
Padding=UDim.new(0,0),
SortOrder="LayoutOrder",
FillDirection="Vertical",
VerticalAlignment="Center",
}),
x,
u,
}),
ao("UIPadding",{
PaddingLeft=UDim.new(0,4),
}),
}),
ao("CanvasGroup",{
Size=UDim2.new(0,0,1,0),
BackgroundTransparency=1,
Name="Center",
AnchorPoint=Vector2.new(0,0.5),
Position=UDim2.new(0,0,0.5,0),
AutomaticSize="Y",
Visible=false,
},{



ao("ScrollingFrame",{
Name="Holder",
BackgroundTransparency=1,
AutomaticSize="Y",
ScrollBarThickness=0,
ScrollingDirection="X",
AutomaticCanvasSize="X",
CanvasSize=UDim2.new(0,0,0,0),
Size=UDim2.new(1,0,1,0),


},{

ao("UIListLayout",{
FillDirection="Horizontal",
VerticalAlignment="Center",
HorizontalAlignment="Left",
Padding=UDim.new(0,aw.UIPadding/2),
}),
}),
}),
ao("Frame",{
AutomaticSize="XY",
BackgroundTransparency=1,
Position=UDim2.new(aw.Topbar.ButtonsType=="Default"and 1 or 0,0,0.5,0),
AnchorPoint=Vector2.new(aw.Topbar.ButtonsType=="Default"and 1 or 0,0.5),
Name="Right",
},{
ao("UIListLayout",{
Padding=UDim.new(0,aw.Topbar.ButtonsType=="Default"and 9 or 0),
FillDirection="Horizontal",
SortOrder="LayoutOrder",
}),
}),
ao("UIPadding",{
PaddingTop=UDim.new(0,aw.UIPadding),
PaddingLeft=UDim.new(
0,
aw.Topbar.ButtonsType=="Default"and aw.UIPadding or aw.UIPadding-2
),
PaddingRight=UDim.new(0,8),
PaddingBottom=UDim.new(0,aw.UIPadding),
}),
}),
}),
})

an.AddSignal(aw.UIElements.Main.Main.Topbar.Left:GetPropertyChangedSignal"AbsoluteSize",function()
local z=0
local A=aw.UIElements.Main.Main.Topbar.Right.UIListLayout.AbsoluteContentSize.X
/av.WindUI.UIScale

z=aw.UIElements.Main.Main.Topbar.Left.AbsoluteSize.X/av.WindUI.UIScale
if aw.Topbar.ButtonsType~="Default"then
z=z+A+aw.UIPadding-4
end

aw.UIElements.Main.Main.Topbar.Center.Position=
UDim2.new(0,z+(aw.UIPadding/av.WindUI.UIScale),0.5,0)
aw.UIElements.Main.Main.Topbar.Center.Size=UDim2.new(
1,
-z
-(aw.UIPadding/av.WindUI.UIScale)
-(aw.Topbar.ButtonsType=="Default"and A+aw.UIPadding or 0),
1,
0
)
end)

if aw.Topbar.ButtonsType~="Default"then
an.AddSignal(aw.UIElements.Main.Main.Topbar.Right:GetPropertyChangedSignal"AbsoluteSize",function()
aw.UIElements.Main.Main.Topbar.Left.Position=UDim2.new(
0,
(aw.UIElements.Main.Main.Topbar.Right.AbsoluteSize.X/av.WindUI.UIScale)+aw.UIPadding-4,
0,
0
)
end)
end

function aw.CreateTopbarButton(z,A,B,C,F,G,H,J)
local L=an.Image(
B,
B,
0,
aw.Folder,
"WindowTopbarIcon",
aw.Topbar.ButtonsType=="Default"and true or false,
G,
"WindowTopbarButtonIcon"
)
L.Size=aw.Topbar.ButtonsType=="Default"
and UDim2.new(0,J or aw.TopBarButtonIconSize,0,J or aw.TopBarButtonIconSize)
or UDim2.new(0,0,0,0)
L.AnchorPoint=Vector2.new(0.5,0.5)
L.Position=UDim2.new(0.5,0,0.5,0)
L.ImageLabel.ImageTransparency=aw.Topbar.ButtonsType=="Default"and 0 or 1

if aw.Topbar.ButtonsType~="Default"then
L.ImageLabel.ImageColor3=an.GetTextColorForHSB(H)
end

local M=an.NewRoundFrame(
aw.Topbar.ButtonsType=="Default"and aw.UICorner-(aw.UIPadding/2)or 999,
"Squircle",
{
Size=aw.Topbar.ButtonsType=="Default"
and UDim2.new(0,aw.Topbar.Height-16,0,aw.Topbar.Height-16)
or UDim2.new(0,14,0,14),
LayoutOrder=F or 999,


ZIndex=9999,
AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.new(0.5,0,0.5,0),
ImageColor3=aw.Topbar.ButtonsType~="Default"and(H or Color3.fromHex"#ff3030")or nil,
ThemeTag=aw.Topbar.ButtonsType=="Default"and{
ImageColor3="Text",
}or nil,
ImageTransparency=aw.Topbar.ButtonsType=="Default"and 1 or 0,
},
{












L,
ao("UIScale",{
Scale=1,
}),
},
true
)

local N=ao("Frame",{
Size=aw.Topbar.ButtonsType~="Default"and UDim2.new(0,24,0,24)
or UDim2.new(0,aw.Topbar.Height-16,0,aw.Topbar.Height-16),
BackgroundTransparency=1,
Parent=aw.UIElements.Main.Main.Topbar.Right,
LayoutOrder=F or 999,
},{
M,
})



aw.TopBarButtons[100-F]={
Name=A,
Object=N,
}

an.AddSignal(M.MouseButton1Click,function()
if C then
C()
end
end)
an.AddSignal(M.MouseEnter,function()
if aw.Topbar.ButtonsType=="Default"then
ap(M,0.15,{ImageTransparency=0.93}):Play()


else

ap(
L.ImageLabel,
0.1,
{ImageTransparency=0},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
ap(L,0.1,{
Size=UDim2.new(
0,
J or aw.TopBarButtonIconSize,
0,
J or aw.TopBarButtonIconSize
),
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end
end)

an.AddSignal(M.MouseButton1Down,function()
ap(M.UIScale,0.2,{Scale=0.9},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end)

an.AddSignal(M.MouseLeave,function()
if aw.Topbar.ButtonsType=="Default"then
ap(M,0.1,{ImageTransparency=1}):Play()


else

ap(
L.ImageLabel,
0.1,
{ImageTransparency=1},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
ap(
L,
0.1,
{Size=UDim2.new(0,0,0,0)},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
end
end)

an.AddSignal(M.InputEnded,function()
ap(M.UIScale,0.2,{Scale=1},Enum.EasingStyle.Quint,Enum.EasingDirection.InOut):Play()
end)

return M
end

function aw.Topbar.Button(z,A:{
Name:string,
Icon:string,
Callback:any,
LayoutOrder:number,
IconThemed:boolean,
Color:Color3,
IconSize:number,
})
return aw:CreateTopbarButton(
A.Name,
A.Icon,
A.Callback,
A.LayoutOrder or 0,
A.IconThemed,
A.Color,
A.IconSize
)
end



local z=an.Drag(
aw.UIElements.Main,
{aw.UIElements.Main.Main.Topbar,r.Frame},
function(z,A)
if not aw.Closed then
if z and A==r.Frame then
ap(r,0.1,{ImageTransparency=0.35}):Play()
else
ap(r,0.2,{ImageTransparency=0.8}):Play()
end
aw.Position=aw.UIElements.Main.Position
aw.Dragging=z
end
end
)

if not h and aw.Background and typeof(aw.Background)=="table"then
local A=ao"UIGradient"
for B,C in next,aw.Background do
A[B]=C
end

aw.UIElements.BackgroundGradient=an.NewRoundFrame(aw.UICorner,"Squircle",{
Size=UDim2.new(1,0,1,0),
Parent=aw.UIElements.Main.Background,
ImageTransparency=aw.Transparent and av.WindUI.TransparencyValue or 0,
},{
A,
})
end














aw.OpenButtonMain=a.load'A'.New(aw)

task.spawn(function()
if aw.Icon then
local A=ao("Frame",{
Size=UDim2.new(0,22,0,22),
BackgroundTransparency=1,
Parent=aw.UIElements.Main.Main.Topbar.Left,
})

v=an.Image(
aw.Icon,
aw.Title,
aw.IconRadius,
aw.Folder,
"Window",
true,
aw.IconThemed,
"WindowTopbarIcon"
)
v.Parent=A
v.Size=UDim2.new(0,aw.IconSize,0,aw.IconSize)
v.Position=UDim2.new(0.5,0,0.5,0)
v.AnchorPoint=Vector2.new(0.5,0.5)

aw.OpenButtonMain:SetIcon(aw.Icon)











else
aw.OpenButtonMain:SetIcon(aw.Icon)

end
end)

function aw.SetToggleKey(A,B)
aw.ToggleKey=B
end

function aw.SetTitle(A,B)
aw.Title=B
x.Text=B
end

function aw.SetAuthor(A,B)
aw.Author=B
if not u then
u=createAuthor(aw.Author)
end

u.Text=B
end

function aw.SetSize(A,B)
if typeof(B)=="UDim2"then
aw.Size=B

ap(aw.UIElements.Main,0.08,{Size=B},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end
end

function aw.SetBackgroundImage(A,B)
aw.UIElements.Main.Background.ImageLabel.Image=B
end
function aw.SetBackgroundImageTransparency(A,B)
if i and i:IsA"ImageLabel"then
i.ImageTransparency=math.floor(B*10+0.5)/10
end
aw.BackgroundImageTransparency=math.floor(B*10+0.5)/10
end

function aw.SetBackgroundTransparency(A,B)
local C=math.floor(tonumber(B)*10+0.5)/10
av.WindUI.TransparencyValue=C
aw:ToggleTransparency(C>0)
end

local A
local B
an.Icon"minimize"
an.Icon"maximize"

aw:CreateTopbarButton(
"Fullscreen",
aw.Topbar.ButtonsType=="Mac"and"rbxassetid://127426072704909"or"maximize",
function()
aw:ToggleFullscreen()
end,
(aw.Topbar.ButtonsType=="Default"and 998 or 999),
true,
Color3.fromHex"#60C762",
aw.Topbar.ButtonsType=="Mac"and 9 or nil
)

local function SetSize(C)
ap(aw.UIElements.Main,0.45,{
Size=not aw.IsFullscreen and B or UDim2.new(
0,
(av.WindUI.ScreenGui.AbsoluteSize.X-20)/av.WindUI.UIScale,
0,
(av.WindUI.ScreenGui.AbsoluteSize.Y-20-52)/av.WindUI.UIScale
),
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()

ap(
aw.UIElements.Main,
0.45,
{Position=not aw.IsFullscreen and A or UDim2.new(0.5,0,0.5,26)},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
end

function aw.ToggleFullscreen(C)
local F=aw.IsFullscreen

z:Set(F)

if not F then
A=aw.UIElements.Main.Position
B=aw.UIElements.Main.Size

aw.CanResize=false
else
if aw.Resizable then
aw.CanResize=true
end
end

aw.IsFullscreen=not F

SetSize(true)
end

an.AddSignal(av.WindUI.ScreenGui:GetPropertyChangedSignal"AbsoluteSize",function()
if aw.IsFullscreen then
SetSize()
end
end)

aw:CreateTopbarButton("Minimize","minus",function()
if aw.Close then
aw:Close()
end






















end,(aw.Topbar.ButtonsType=="Default"and 997 or 998),nil,Color3.fromHex"#F4C948")

function aw.OnOpen(C,F)
aw.OnOpenCallback=F
end
function aw.OnClose(C,F)
aw.OnCloseCallback=F
end
function aw.OnDestroy(C,F)
aw.OnDestroyCallback=F
end

if av.WindUI.UseAcrylic then
aw.AcrylicPaint.AddParent(aw.UIElements.Main)
end

function aw.SetIconSize(C,F)
local G
if typeof(F)=="number"then
G=UDim2.new(0,F,0,F)
aw.IconSize=F
elseif typeof(F)=="UDim2"then
G=F
aw.IconSize=F.X.Offset
end

if v then
v.Size=G
end
end

function aw.Open(C)
if aw.Destroyed then
return
end
task.spawn(function()
if aw.OnOpenCallback then
task.spawn(function()
an.SafeCallback(aw.OnOpenCallback)
end)
end

task.wait(0.06)
aw.Closed=false

aw.UIElements.Main.Size=UDim2.new(aw.Size.X.Scale,aw.Size.X.Offset,0,100)

ap(aw.UIElements.Main,0.8,{

Size=aw.Size,
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()

if aw.UIElements.BackgroundGradient then
ap(aw.UIElements.BackgroundGradient,0.2,{
ImageTransparency=0,
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end

aw.UIElements.Main.Background.ImageTransparency=1
ap(aw.UIElements.Main.Background,0.4,{

ImageTransparency=aw.Transparent and av.WindUI.TransparencyValue or 0,
},Enum.EasingStyle.Exponential,Enum.EasingDirection.Out):Play()

if i then
if i:IsA"VideoFrame"then
i.Visible=true
else
ap(i,0.2,{
ImageTransparency=aw.BackgroundImageTransparency,
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end
end

if aw.OpenButtonMain and aw.IsOpenButtonEnabled then
aw.OpenButtonMain:Visible(false)
end









ap(
b,
0.25,
{ImageTransparency=aw.ShadowTransparency},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()




ap(
r,
0.45,
{Size=UDim2.new(0,aw.DragFrameSize,0,4),ImageTransparency=0.8},
Enum.EasingStyle.Exponential,
Enum.EasingDirection.Out
):Play()
z:Set(true)

if aw.Resizable then
ap(
az.ImageLabel,
0.45,
{ImageTransparency=0.8},
Enum.EasingStyle.Exponential,
Enum.EasingDirection.Out
):Play()
aw.CanResize=true
end

aw.CanDropdown=true
aw.UIElements.Main.Visible=true



aw.UIElements.Main:WaitForChild"Main".Visible=true

av.WindUI:ToggleAcrylic(true)

end)
end
function aw.Close(C)
if aw.Destroyed then
return
end

local F={}

if aw.OnCloseCallback then
task.spawn(function()
an.SafeCallback(aw.OnCloseCallback)
end)
end

av.WindUI:ToggleAcrylic(false)

if aw.UIElements.Main and aw.UIElements.Main:WaitForChild"Main"then
aw.UIElements.Main.Main.Visible=false
end

aw.CanDropdown=false
aw.Closed=true

ap(aw.UIElements.Main,0.9,{

Size=UDim2.new(aw.Size.X.Scale,aw.Size.X.Offset,0,0),
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
if aw.UIElements.BackgroundGradient then
ap(aw.UIElements.BackgroundGradient,0.2,{
ImageTransparency=1,
},Enum.EasingStyle.Quint,Enum.EasingDirection.InOut):Play()
end

ap(aw.UIElements.Main.Background,0.3,{

ImageTransparency=1,
},Enum.EasingStyle.Exponential,Enum.EasingDirection.InOut):Play()








if i then
if i:IsA"VideoFrame"then
i.Visible=false
else
ap(i,0.3,{
ImageTransparency=1,
},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
end
end
ap(b,0.25,{ImageTransparency=1},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()




ap(
r,
0.3,
{Size=UDim2.new(0,0,0,4),ImageTransparency=1},
Enum.EasingStyle.Exponential,
Enum.EasingDirection.InOut
):Play()
ap(
az.ImageLabel,
0.3,
{ImageTransparency=1},
Enum.EasingStyle.Exponential,
Enum.EasingDirection.Out
):Play()
z:Set(false)
aw.CanResize=false

task.spawn(function()
task.wait(0.4)

if not aw.Closed then
return
end

aw.UIElements.Main.Visible=false

if aw.OpenButtonMain and not aw.Destroyed and not aw.IsPC and aw.IsOpenButtonEnabled then
aw.OpenButtonMain:Visible(true)
end
end)

function F.Destroy(G)
task.spawn(function()
if aw.OnDestroyCallback then
task.spawn(function()
an.SafeCallback(aw.OnDestroyCallback)
end)
end

if aw.AcrylicPaint and aw.AcrylicPaint.Model then
aw.AcrylicPaint.Model:Destroy()
end

aw.Destroyed=true

task.wait(0.4)

av.WindUI.ScreenGui:Destroy()
av.WindUI.NotificationGui:Destroy()
av.WindUI.DropdownGui:Destroy()
av.WindUI.TooltipGui:Destroy()

an.DisconnectAll()

return
end)
end

return F
end
function aw.Destroy(C)
return aw:Close():Destroy()
end
function aw.Toggle(C)
if aw.Closed then
aw:Open()
else
aw:Close()
end
end

function aw.ToggleTransparency(C,F)

aw.Transparent=F
av.WindUI.Transparent=F

aw.UIElements.Main.Background.ImageTransparency=F and av.WindUI.TransparencyValue or 0


end

function aw.LockAll(C)
for F,G in next,aw.AllElements do
if G.Lock then
G:Lock()
end
end
end
function aw.UnlockAll(C)
for F,G in next,aw.AllElements do
if G.Unlock then
G:Unlock()
end
end
end
function aw.GetLocked(C)
local F={}

for G,H in next,aw.AllElements do
if H.Locked then
table.insert(F,H)
end
end

return F
end
function aw.GetUnlocked(C)
local F={}

for G,H in next,aw.AllElements do
if H.Locked==false then
table.insert(F,H)
end
end

return F
end

function aw.GetUIScale(C,F)
return av.WindUI.UIScale
end

function aw.SetUIScale(C,F)
av.WindUI.UIScale=F
ap(av.WindUI.UIScaleObj,0.2,{Scale=F},Enum.EasingStyle.Quint,Enum.EasingDirection.Out):Play()
return aw
end

function aw.SetToTheCenter(C)
ap(
aw.UIElements.Main,
0.45,
{Position=UDim2.new(0.5,0,0.5,0)},
Enum.EasingStyle.Quint,
Enum.EasingDirection.Out
):Play()
return aw
end

function aw.SetCurrentConfig(C,F)
aw.CurrentConfig=F
end

do
local C=40
local F=al.ViewportSize
local G=Vector2.new(aw.Size.X.Offset,aw.Size.Y.Offset)

if not aw.IsFullscreen and aw.AutoScale then
local H=F.X-(C*2)
local J=F.Y-(C*2)

local L=H/G.X
local M=J/G.Y

local N=math.min(L,M)

local O=0.3
local P=1.0

local Q=math.clamp(N,O,P)

local R=aw:GetUIScale()or 1
local S=0.05

if math.abs(Q-R)>S then
aw:SetUIScale(Q)
end
end
end

if aw.OpenButtonMain and aw.OpenButtonMain.Button then
an.AddSignal(aw.OpenButtonMain.Button.TextButton.MouseButton1Click,function()


aw:Open()
end)
end

an.AddSignal(af.InputBegan,function(C,F)
if F then
return
end

if aw.ToggleKey then
if C.KeyCode==aw.ToggleKey then
aw:Toggle()
end
end
end)

task.spawn(function()

aw:Open()
end)

function aw.EditOpenButton(C,F)
return aw.OpenButtonMain:Edit(F)
end

if aw.OpenButton and typeof(aw.OpenButton)=="table"then
aw:EditOpenButton(aw.OpenButton)
end

local C=a.load'aa'
local F=a.load'ab'
local G=C.Init(aw,av.WindUI,av.WindUI.TooltipGui)
G:OnChange(function(H)
aw.CurrentTab=H
end)

aw.TabModule=G

function aw.Tab(H,J)
J.Parent=aw.UIElements.SideBar.Frame
return G.New(J,av.WindUI.UIScale)
end

function aw.SelectTab(H,J)
G:SelectTab(J)
end

function aw.Section(H,J)
return F.New(
J,
aw.UIElements.SideBar.Frame,
aw.Folder,
av.WindUI.UIScale,
aw
)
end

function aw.IsResizable(H,J)
aw.Resizable=J
aw.CanResize=J
end

function aw.SetPanelBackground(H,J)
if typeof(J)=="boolean"then
aw.HidePanelBackground=J

aw.UIElements.MainBar.Background.Visible=J

if G then
for L,M in next,G.Containers do
M.ScrollingFrame.UIPadding.PaddingTop=UDim.new(0,aw.HidePanelBackground and 20 or 10)
M.ScrollingFrame.UIPadding.PaddingLeft=
UDim.new(0,aw.HidePanelBackground and 20 or 10)
M.ScrollingFrame.UIPadding.PaddingRight=
UDim.new(0,aw.HidePanelBackground and 20 or 10)
M.ScrollingFrame.UIPadding.PaddingBottom=
UDim.new(0,aw.HidePanelBackground and 20 or 10)
end
end
end
end

function aw.Divider(H)
local J=ao("Frame",{
Size=UDim2.new(1,0,0,1),
Position=UDim2.new(0.5,0,0,0),
AnchorPoint=Vector2.new(0.5,0),
BackgroundTransparency=0.9,
ThemeTag={
BackgroundColor3="Text",
},
})
local L=ao("Frame",{
Parent=aw.UIElements.SideBar.Frame,

Size=UDim2.new(1,-7,0,5),
BackgroundTransparency=1,
},{
J,
})

return L
end

local H=a.load'o'
function aw.Dialog(J,L)
local M={
Title=L.Title or"Dialog",
Width=L.Width or 320,
Content=L.Content,
Buttons=L.Buttons or{},

TextPadding=14,
}
local N=H.Create(false,"Dialog",aw,av.WindUI,aw.UIElements.Main.Main)

N.UIElements.Main.Size=UDim2.new(0,M.Width,0,0)

local O=ao("Frame",{
Size=UDim2.new(1,0,1,0),
AutomaticSize="Y",
BackgroundTransparency=1,
Parent=N.UIElements.Main,
},{
ao("UIListLayout",{
FillDirection="Vertical",

Padding=UDim.new(0,N.UIPadding),
}),
})

local P=ao("Frame",{
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
BackgroundTransparency=1,
Parent=O,
},{
ao("UIListLayout",{
FillDirection="Horizontal",
Padding=UDim.new(0,N.UIPadding),
VerticalAlignment="Center",
}),
ao("UIPadding",{
PaddingTop=UDim.new(0,M.TextPadding/2),
PaddingLeft=UDim.new(0,M.TextPadding/2),
PaddingRight=UDim.new(0,M.TextPadding/2),
}),
})

local Q
if L.Icon then
Q=an.Image(
L.Icon,
M.Title..":"..L.Icon,
0,
aw,
"Dialog",
true,
L.IconThemed
)
Q.Size=UDim2.new(0,22,0,22)
Q.Parent=P
end

N.UIElements.UIListLayout=ao("UIListLayout",{
Padding=UDim.new(0,12),
FillDirection="Vertical",
HorizontalAlignment="Left",
VerticalFlex="SpaceBetween",
Parent=N.UIElements.Main,
})

ao("UISizeConstraint",{
MinSize=Vector2.new(180,20),
MaxSize=Vector2.new(400,math.huge),
Parent=N.UIElements.Main,
})

N.UIElements.Title=ao("TextLabel",{
Text=M.Title,
TextSize=20,
FontFace=Font.new(an.Font,Enum.FontWeight.SemiBold),
TextXAlignment="Left",
TextWrapped=true,
RichText=true,
Size=UDim2.new(1,Q and-26-N.UIPadding or 0,0,0),
AutomaticSize="Y",
ThemeTag={
TextColor3="Text",
},
BackgroundTransparency=1,
Parent=P,
})
if M.Content then
ao("TextLabel",{
Text=M.Content,
TextSize=18,
TextTransparency=0.4,
TextWrapped=true,
RichText=true,
FontFace=Font.new(an.Font,Enum.FontWeight.Medium),
TextXAlignment="Left",
Size=UDim2.new(1,0,0,0),
AutomaticSize="Y",
LayoutOrder=2,
ThemeTag={
TextColor3="Text",
},
BackgroundTransparency=1,
Parent=O,
},{
ao("UIPadding",{
PaddingLeft=UDim.new(0,M.TextPadding/2),
PaddingRight=UDim.new(0,M.TextPadding/2),
PaddingBottom=UDim.new(0,M.TextPadding/2),
}),
})
end

local R=ao("UIListLayout",{
Padding=UDim.new(0,6),
FillDirection="Horizontal",
HorizontalAlignment="Center",
HorizontalFlex="Fill",
})

local S=ao("Frame",{
Size=UDim2.new(1,0,0,36),
AutomaticSize="None",
BackgroundTransparency=1,
Parent=N.UIElements.Main,
LayoutOrder=4,
},{
R,






})

local T={}

for U,V in next,M.Buttons do
local W=
ar(V.Title,V.Icon,V.Callback,V.Variant,S,N,true)
table.insert(T,W)
W.Size=UDim2.new(1,0,1,0)
end





















































N:Open()

return N
end

local J=false

aw:CreateTopbarButton("Close","x",function()
if not J then
if not aw.IgnoreAlerts then
J=true

aw:Dialog{

Title="Close Window",
Content="Do you want to close this window? You will not be able to open it again.",
Buttons={
{
Title="Cancel",

Callback=function()
J=false
end,
Variant="Secondary",
},
{
Title="Close Window",

Callback=function()
J=false
aw:Destroy()
end,
Variant="Primary",
},
},
}
else
aw:Destroy()
end
end
end,(aw.Topbar.ButtonsType=="Default"and 999 or 997),nil,Color3.fromHex"#F4695F")

function aw.Tag(L,M)
if aw.UIElements.Main.Main.Topbar.Center.Visible==false then
aw.UIElements.Main.Main.Topbar.Center.Visible=true
end
M.Window=aw
return at:New(M,aw.UIElements.Main.Main.Topbar.Center.Holder)
end

local L=av.WindUI.GenerateGUID()

local function startResizing(M)
if aw.CanResize then
isResizing=true
aA.Active=true
initialSize=aw.UIElements.Main.Size
initialInputPosition=M.Position


ap(az.ImageLabel,0.1,{ImageTransparency=0.35}):Play()

an.AddSignal(M.Changed,function()
if M.UserInputState==Enum.UserInputState.End then
if av.WindUI.CurrentInput and av.WindUI.CurrentInput~=L then
return
end

av.WindUI.CurrentInput=nil

isResizing=false
aA.Active=false


ap(az.ImageLabel,0.17,{ImageTransparency=0.8}):Play()
end
end)
end
end

an.AddSignal(az.InputBegan,function(M)
if
M.UserInputType==Enum.UserInputType.MouseButton1
or M.UserInputType==Enum.UserInputType.Touch
then
if av.WindUI.CurrentInput and av.WindUI.CurrentInput~=L then
return
end
av.WindUI.CurrentInput=L

if aw.CanResize then
startResizing(M)
end
end
end)

an.AddSignal(af.InputChanged,function(M)
if
M.UserInputType==Enum.UserInputType.MouseMovement
or M.UserInputType==Enum.UserInputType.Touch
then
if isResizing and aw.CanResize then
local N=M.Position-initialInputPosition
local O=UDim2.new(0,initialSize.X.Offset+N.X*2,0,initialSize.Y.Offset+N.Y*2)

O=UDim2.new(
O.X.Scale,
math.clamp(O.X.Offset,aw.MinSize.X,aw.MaxSize.X),
O.Y.Scale,
math.clamp(O.Y.Offset,aw.MinSize.Y,aw.MaxSize.Y)
)

ap(aw.UIElements.Main,0.08,{
Size=O,
},Enum.EasingStyle.Quad,Enum.EasingDirection.Out):Play()

aw.Size=O
end
end
end)

an.AddSignal(az.MouseEnter,function()
if av.WindUI.CurrentInput and av.WindUI.CurrentInput~=L then
return
end
if not isResizing then
ap(az.ImageLabel,0.1,{ImageTransparency=0.35}):Play()
end
end)
an.AddSignal(az.MouseLeave,function()
if av.WindUI.CurrentInput and av.WindUI.CurrentInput~=L then
return
end
if not isResizing then
ap(az.ImageLabel,0.17,{ImageTransparency=0.8}):Play()
end
end)



local M=0
local N=0.4
local O
local P=0

function onDoubleClick()
aw:SetToTheCenter()
end

an.AddSignal(r.Frame.MouseButton1Up,function()
local Q=tick()
local R=aw.Position

P=P+1

if P==1 then
M=Q
O=R

task.spawn(function()
task.wait(N)
if P==1 then
P=0
O=nil
end
end)
elseif P==2 then
if Q-M<=N and R==O then
onDoubleClick()
end

P=0
O=nil
M=0
else
P=1
M=Q
O=R
end
end)



if not aw.HideSearchBar then
local Q=a.load'ad'
local R=false





















local S=aq("Search","search",aw.UIElements.SideBarContainer,true)
S.Size=UDim2.new(1,-aw.UIPadding/2,0,39)
S.Position=UDim2.new(0,aw.UIPadding/2,0,0)

an.AddSignal(S.MouseButton1Click,function()
if R then
return
end

Q.new(aw.TabModule,aw.UIElements.Main,function()

R=false
if aw.Resizable then
aw.CanResize=true
end

ap(aB,0.1,{ImageTransparency=1}):Play()
aB.Active=false
end)
ap(aB,0.1,{ImageTransparency=0.65}):Play()
aB.Active=true

R=true
aw.CanResize=false
end)
end



function aw.DisableTopbarButtons(Q,R)
for S,T in next,R do
for U,V in next,aw.TopBarButtons do
if V.Name==T then
V.Object.Visible=false
end
end
end
end



























return aw
end end end

local aa={
Window=nil,
Theme=nil,
Creator=a.load'd',
LocalizationModule=a.load'e',
NotificationModule=a.load'f',
Themes=nil,
Transparent=false,

TransparencyValue=0.15,

UIScale=1,

ConfigManager=nil,
Version="0.0.0",

Services=a.load'k',

OnThemeChangeFunction=nil,

cloneref=nil,
UIScaleObj=nil,

CreateWindow=nil,

CurrentInput=nil,
}

local af=(cloneref or clonereference or function(af)
return af
end)

aa.cloneref=af

local ai=af(game:GetService"HttpService")
local ak=af(game:GetService"Players")
local al=af(game:GetService"CoreGui")
local am=af(game:GetService"RunService")
local an=af(game:GetService"UserInputService")

function aa.GenerateGUID()
return ai:GenerateGUID(false)
end

local ao=aa.GenerateGUID()

an.InputBegan:Connect(function(ap,aq)




task.defer(function()
if
ap.UserInputType==Enum.UserInputType.MouseButton1
or ap.UserInputType==Enum.UserInputType.Touch
then
if aa.CurrentInput and aa.CurrentInput~=ao then
return
end

aa.CurrentInput=ao


end
end)
end)
an.InputEnded:Connect(function(ap,aq)
if ap.UserInputType==Enum.UserInputType.MouseButton1 or ap.UserInputType==Enum.UserInputType.Touch then
if aa.CurrentInput and aa.CurrentInput~=ao then
return
end

aa.CurrentInput=nil
end
end)

local ap=ak.LocalPlayer or nil

local aq=ai:JSONDecode(a.load'l')
if aq then
aa.Version=aq.version
end

local ar=a.load'p'

local as=aa.Creator

local at=as.New




local au=a.load't'

local av=protectgui or(syn and syn.protect_gui)or function()end

local aw=gethui and gethui()or(al or ap:WaitForChild"PlayerGui")

local ax=at("UIScale",{
Scale=aa.UIScale,
})

aa.UIScaleObj=ax

aa.ScreenGui=at("ScreenGui",{
Name="WindUI",
Parent=aw,
IgnoreGuiInset=true,
ScreenInsets="None",
DisplayOrder=-99999,
},{

at("Folder",{
Name="Window",
}),






at("Folder",{
Name="KeySystem",
}),
at("Folder",{
Name="Popups",
}),
at("Folder",{
Name="ToolTips",
}),
})

aa.NotificationGui=at("ScreenGui",{
Name="WindUI/Notifications",
Parent=aw,
IgnoreGuiInset=true,
})
aa.DropdownGui=at("ScreenGui",{
Name="WindUI/Dropdowns",
Parent=aw,
IgnoreGuiInset=true,
})
aa.TooltipGui=at("ScreenGui",{
Name="WindUI/Tooltips",
Parent=aw,
IgnoreGuiInset=true,
})
av(aa.ScreenGui)
av(aa.NotificationGui)
av(aa.DropdownGui)
av(aa.TooltipGui)

as.Init(aa)

function aa.SetParent(ay,az)
if aa.ScreenGui then
aa.ScreenGui.Parent=az
end
if aa.NotificationGui then
aa.NotificationGui.Parent=az
end
if aa.DropdownGui then
aa.DropdownGui.Parent=az
end
if aa.TooltipGui then
aa.TooltipGui.Parent=az
end
end
math.clamp(aa.TransparencyValue,0,1)

local ay=aa.NotificationModule.Init(aa.NotificationGui)

function aa.Notify(az,aA)
aA.Holder=ay.Frame
aA.Window=aa.Window

return aa.NotificationModule.New(aA)
end

function aa.SetNotificationLower(az,aA)
ay.SetLower(aA)
end

function aa.SetFont(az,aA)
as.UpdateFont(aA)
end

function aa.OnThemeChange(az,aA)
aa.OnThemeChangeFunction=aA
end

function aa.AddTheme(az,aA)
aa.Themes[aA.Name]=aA
return aA
end

function aa.SetTheme(az,aA)
if aa.Themes[aA]then
aa.Theme=aa.Themes[aA]
as.SetTheme(aa.Themes[aA])

if aa.OnThemeChangeFunction then
aa.OnThemeChangeFunction(aA)
end

return aa.Themes[aA]
end
return nil
end

function aa.GetThemes(az)
return aa.Themes
end
function aa.GetCurrentTheme(az)
return aa.Theme.Name
end
function aa.GetTransparency(az)
return aa.Transparent or false
end
function aa.GetWindowSize(az)
return aa.Window.UIElements.Main.Size
end
function aa.Localization(az,aA)
return aa.LocalizationModule:New(aA,as)
end

function aa.SetLanguage(az,aA)
if as.Localization then
return as.SetLanguage(aA)
end
return false
end

function aa.ToggleAcrylic(az,aA)
if aa.Window and aa.Window.AcrylicPaint and aa.Window.AcrylicPaint.Model then
aa.Window.Acrylic=aA
aa.Window.AcrylicPaint.Model.Transparency=aA and 0.98 or 1
if aA then
au.Enable()
else
au.Disable()
end
end
end

function aa.Gradient(az,aA,aB)
local b={}
local d={}

for f,g in next,aA do
local h=tonumber(f)
if h then
h=math.clamp(h/100,0,1)

local i=g.Color
if typeof(i)=="string"and string.sub(i,1,1)=="#"then
i=Color3.fromHex(i)
end

local l=g.Transparency or 0

table.insert(b,ColorSequenceKeypoint.new(h,i))
table.insert(d,NumberSequenceKeypoint.new(h,l))
end
end

table.sort(b,function(f,g)
return f.Time<g.Time
end)
table.sort(d,function(f,g)
return f.Time<g.Time
end)

if#b<2 then
table.insert(b,ColorSequenceKeypoint.new(1,b[1].Value))
table.insert(d,NumberSequenceKeypoint.new(1,d[1].Value))
end

local f={
Color=ColorSequence.new(b),
Transparency=NumberSequence.new(d),
}

if aB then
for g,h in pairs(aB)do
f[g]=h
end
end

return f
end

function aa.Popup(az,aA)
aA.WindUI=aa
return a.load'u'.new(aA,aa.ScreenGui.Popups)
end

aa.Themes=a.load'v'(aa,as)

as.Themes=aa.Themes

aa:SetTheme"Dark"
aa:SetLanguage(as.Language)

function aa.CreateWindow(az,aA)
local aB=a.load'ae'

if not am:IsStudio()and writefile then
if not isfolder"WindUI"then
makefolder"WindUI"
end
if aA.Folder then
makefolder(aA.Folder)
else
makefolder(aA.Title)
end
end

aA.WindUI=aa
aA.Window=aa.Window
aA.Parent=aa.ScreenGui.Window

if aa.Window then
warn"You cannot create more than one window"
return
end

local b=true

local d=aa.Themes[aA.Theme or"Dark"]


as.SetTheme(d)

local f=gethwid or function()
return ak.LocalPlayer.UserId
end

local g=f()

if aA.KeySystem then
b=false

local function loadKeysystem()
ar.new(aA,g,function(h)
b=h
end)
end

local h=(aA.Folder or"Temp").."/"..g..".key"

if aA.KeySystem.KeyValidator then
if aA.KeySystem.SaveKey and isfile(h)then
local i=readfile(h)
local l=aA.KeySystem.KeyValidator(i)

if l then
b=true
else
loadKeysystem()
end
else
loadKeysystem()
end
elseif not aA.KeySystem.API then
if aA.KeySystem.SaveKey and isfile(h)then
local i=readfile(h)
local l=(type(aA.KeySystem.Key)=="table")and table.find(aA.KeySystem.Key,i)
or tostring(aA.KeySystem.Key)==tostring(i)

if l then
b=true
else
loadKeysystem()
end
else
loadKeysystem()
end
else
if isfile(h)then
local i=readfile(h)
local l=false

for m,p in next,aA.KeySystem.API do
local r=aa.Services[p.Type]
if r then
local u={}
for v,x in next,r.Args do
table.insert(u,p[x])
end

local v=r.New(table.unpack(u))
local x=v.Verify(i)
if x then
l=true
break
end
end
end

b=l
if not l then
loadKeysystem()
end
else
loadKeysystem()
end
end

repeat
task.wait()
until b
end

local h=aB(aA)

aa.Transparent=aA.Transparent
aa.Window=h

if aA.Acrylic then
au.init()
end













return h
end

return aa
end

--  LOAD WINDUI (LOKAL, TANPA HTTP) 
local WindUI = _LoadWindUI_Embedded()

--  WINDOW (+ floating minimize bubble, sudah teruji OK) 
local Window = WindUI:CreateWindow({
    Title       = "Auto Farming ASH",
    Icon        = "sword",
    Theme       = "Dark",
    Folder      = "premium_rejoin",
    Transparent = true,   -- aktifkan mode transparan (diperlukan SetBackgroundTransparency)

    OpenButton = {
        Title           = "FLa",
        CornerRadius    = UDim.new(0, 12),
        StrokeThickness = 2,
        Enabled         = true,
        Draggable       = true,
        OnlyMobile      = false,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(25, 45, 115)),
            ColorSequenceKeypoint.new(0.55, Color3.fromRGB(55, 105, 255)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(90, 145, 255)),
        }),
    },

    --  Pengganti CreateUserProfile() (baris 1132-1172 source asli) 
    User = {
        Enabled   = true,
        Anonymous = false,
        Callback  = function() end,
    },
})

Window:SetToggleKey(Enum.KeyCode.LeftAlt)

-- ============================================================================
-- 11 TAB SESUAI URUTAN TERBARU
-- ============================================================================

local MainTab = Window:Tab({
    Title = "Main",
    Icon  = "home",
})

local HideTab = Window:Tab({
    Title = "Hide",
    Icon  = "eye-off",
})

local FarmTab = Window:Tab({
    Title = "Farm",
    Icon  = "sword",
})

local MassAttackTab = Window:Tab({
    Title = "Mass Attack",
    Icon  = "swords",
})

local AutomationTab = Window:Tab({
    Title = "Automation",
    Icon  = "bot",
})

local RerollTab = Window:Tab({
    Title = "Reroll",
    Icon  = "dices",
})

local PlayerTab = Window:Tab({
    Title = "Player",
    Icon  = "user",
})

local SettingTab = Window:Tab({
    Title = "Setting",
    Icon  = "settings",
})

local WebhookTab = Window:Tab({
    Title = "Webhook",
    Icon  = "send",
})

local ConfigTab = Window:Tab({
    Title = "Config",
    Icon  = "save",
})

local ThemeTab = Window:Tab({
    Title = "Theme",
    Icon  = "palette",
})

-- ============================================================================
-- PANEL: MAIN
-- COUNTER AUTO SELL HERO EQUIP + AUTO SELL HERO EQUIP
-- Dipindah dari PANEL: MAIN baris 3812 source premium
-- Ditulis ulang pakai WindUI native API (tidak ada helper C/Frame/Label/Btn premium)
-- ============================================================================
do
    --  Global expose (dibaca oleh Config panel saat save/load) 
    -- Sama persis dengan deklarasi source asli baris ~1715-1718
    _setSellHeroToggle = nil   -- setter logic toggle (fn(bool))
    _visSellHero       = nil   -- setter visual-only toggle (fn(bool))
    _autoSellOnState   = false -- tracking state untuk CollectConfig

    --  State lokal (scope do-block, tidak bocor keluar) 
    local _autoSellOn   = false
    local _sellConn     = nil
    local _lockedGuids  = {}
    local _cnt          = {R=0, Y=0, B=0, other=0, skipped=0}
    local _sellToggleCb = nil

    --  Helper update label counter 
    local _cntParagraph = nil  -- diisi setelah Paragraph dibuat di bawah
    local function RefreshCounters()
        if not _cntParagraph then return end
        pcall(function()
            _cntParagraph:SetDesc(
                "R: " .. _cnt.R ..
                "  |  Y: " .. _cnt.Y ..
                "  |  B: " .. _cnt.B ..
                "  |  Supreme skip: " .. _cnt.skipped
            )
        end)
    end

    --  Helper update status line 
    local _statusParagraph = nil  -- diisi setelah Paragraph dibuat di bawah
    local function SetSellStatus(msg)
        if not _statusParagraph then return end
        pcall(function()
            _statusParagraph:SetDesc(msg)
        end)
    end

    -- 
    --  SECTION: COUNTER AUTO SELL HERO EQUIP
    --  Source asli baris ~3931-3969
    -- 
    MainTab:Section({ Title = "Counter Auto Sell Hero Equip", Icon = "bar-chart-2" })

    -- Paragraph yang menampilkan angka R/Y/B/Supreme (diupdate via RefreshCounters)
    _cntParagraph = MainTab:Paragraph({
        Title = "Sold Count",
        Desc  = "R: 0  |  Y: 0  |  B: 0  |  Supreme skip: 0",
    })

    -- Tombol RESET COUNTER
    MainTab:Button({
        Title    = "RESET COUNTER",
        Desc     = "Reset semua angka counter ke 0",
        Callback = function()
            _cnt = {R=0, Y=0, B=0, other=0, skipped=0}
            RefreshCounters()
            SetSellStatus("[OK] DONE RESET")
        end,
    })

    -- ============================================================================
    -- PANEL: MAIN (lanjutan)
    -- AUTO COLLECT GOLD & ITEM
    -- Dipindah dari baris ~5150 source premium
    -- Ditulis ulang pakai WindUI native API
    -- Dependency chain (semua dari source 1.lua):
    --   _collectObj, _instantCollectConns, _instantCollected  (~baris 483-509)
    --   StartInstantGoldCollector                              (~baris 511-573)
    --   _goldMagnetRunning, StartGoldMagnet, StopGoldMagnet   (~baris 2420-2469)
    --   DoAutoCollect                                          (~baris 2720-2748)
    --   DoAutoCollectGoldItem                                  (~baris 2473-2485)
    -- Global expose: _setAutoCollectToggle, _visAutoCollect, _autoCollectState
    -- ============================================================================
    do
        --  Global expose (dibaca Config panel saat save/load) 
        -- Sama persis dengan deklarasi source asli baris ~1713, ~1745, ~1794
        _setAutoCollectToggle = nil   -- setter logic toggle (fn(bool))
        _visAutoCollect       = nil   -- setter visual-only toggle (fn(bool))
        _autoCollectState     = false -- tracking state untuk CollectConfig

        -- 
        --  INSTANT COLLECTOR - STATE VARS
        --  Source asli baris ~483-484
        -- 
        local _instantCollectConns = {}
        local _instantCollected    = {}

        -- 
        --  _collectObj: TP obj ke player lalu fire CollectItem + ExtraReward
        --  Source asli baris ~486-509
        -- 
        local function _collectObj(obj)
            local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid")
            if not guid or _instantCollected[guid] then return end
            _instantCollected[guid] = true
            -- Teleport langsung ke player sebelum collect
            pcall(function()
                local char = LP.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local pos = hrp.Position
                    if obj:IsA("BasePart") then
                        obj.CFrame = CFrame.new(pos)
                    elseif obj:IsA("Model") then
                        local part = obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart
                        if part then part.CFrame = CFrame.new(pos) end
                    end
                end
            end)
            -- Fire collect remote (RemoteFunction -> InvokeServer)
            pcall(function() RE.CollectItem:InvokeServer(guid) end)
            if RE.ExtraReward then
                pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
            end
        end

        -- 
        --  StartInstantGoldCollector: listen ChildAdded per folder drop
        --  Source asli baris ~511-573
        -- 
        local function StartInstantGoldCollector(on)
            -- Putuskan semua koneksi lama
            for _, c in ipairs(_instantCollectConns) do pcall(function() c:Disconnect() end) end
            _instantCollectConns = {}
            _instantCollected    = {}

            if not on then return end

            local DROP_FOLDERS = {"Golds","Items","Drops","Rewards","Loot","DropItems","RewardItems"}

            for _, folderName in ipairs(DROP_FOLDERS) do
                -- Tunggu folder muncul atau sudah ada
                task.spawn(function()
                    local folder = workspace:FindFirstChild(folderName)
                                or workspace:WaitForChild(folderName, 5)
                    if not folder then return end

                    -- Collect semua yang sudah ada di folder (batch, tanpa delay)
                    for _, obj in ipairs(folder:GetChildren()) do
                        _collectObj(obj)
                    end

                    -- Listen ChildAdded di folder (BUKAN di workspace)
                    local conn = folder.ChildAdded:Connect(function(obj)
                        -- Tidak ada task.wait / task.delay - langsung collect
                        _collectObj(obj)
                    end)
                    table.insert(_instantCollectConns, conn)
                end)
            end

            -- Juga pantau folder baru yang mungkin muncul nanti di workspace
            local wsConn = workspace.ChildAdded:Connect(function(obj)
                for _, fn in ipairs(DROP_FOLDERS) do
                    if obj.Name == fn then
                        task.spawn(function()
                            task.wait(0.05)
                            -- Batch collect isi folder baru
                            for _, child in ipairs(obj:GetChildren()) do
                                _collectObj(child)
                            end
                            -- Connect ChildAdded ke folder baru
                            local c2 = obj.ChildAdded:Connect(function(item)
                                _collectObj(item)
                            end)
                            table.insert(_instantCollectConns, c2)
                        end)
                        break
                    end
                end
            end)
            table.insert(_instantCollectConns, wsConn)
        end

        -- 
        --  GOLD MAGNET - loop TP semua item di folder ke posisi player tiap 0.05s
        --  Source asli baris ~2420-2469
        -- 
        local _goldMagnetRunning = false

        local function StartGoldMagnet(checkFn)
            if _goldMagnetRunning then return end
            _goldMagnetRunning = true
            task.spawn(function()
                local GOLD_FOLDERS = {"Golds","Items","Drops","Rewards","Loot","DropItems","RewardItems"}
                while _goldMagnetRunning do
                    local shouldRun = (checkFn == nil) or checkFn()
                    if not shouldRun then
                        _goldMagnetRunning = false
                        break
                    end
                    pcall(function()
                        local char = LP.Character
                        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                        if not hrp then return end
                        local playerPos = hrp.Position
                        for _, folderName in ipairs(GOLD_FOLDERS) do
                            local folder = workspace:FindFirstChild(folderName)
                            if folder then
                                for _, obj in ipairs(folder:GetChildren()) do
                                    pcall(function()
                                        -- TP langsung ke player (no random offset agar pasti ke-collect)
                                        if obj:IsA("BasePart") then
                                            obj.CFrame = CFrame.new(playerPos)
                                        elseif obj:IsA("Model") then
                                            local part = obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart
                                            if part then part.CFrame = CFrame.new(playerPos) end
                                        end
                                        -- Fire collect
                                        local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid")
                                        if guid then
                                            pcall(function() RE.CollectItem:InvokeServer(guid) end)
                                            if RE.ExtraReward then
                                                pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                                            end
                                        end
                                    end)
                                end
                            end
                        end
                    end)
                    PG_Wait(0.05) -- [PingGuard] adaptive throttle (base 0.05s)
                end
                _goldMagnetRunning = false
            end)
        end

        local function StopGoldMagnet()
            _goldMagnetRunning = false
        end

        -- 
        --  DoAutoCollect: polling loop collect via StartLoop/StopLoop
        --  Source asli baris ~2720-2748
        -- 
        local function DoAutoCollect(on)
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
                                    -- [v112-FIX] Nil guard ExtraReward
                                    if RE.ExtraReward then
                                        pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                                    end
                                    PG_Wait(0.03) -- [PingGuard] collect item
                                end
                            end
                        end
                    end
                    PG_Wait(0.2) -- [PingGuard] collect poll outer
                end
            end)
        end

        -- 
        --  DoAutoCollectGoldItem: master toggle - panggil semua collector
        --  Source asli baris ~2473-2485
        -- 
        local function DoAutoCollectGoldItem(on)
            STATE.autoCollectGoldItem = on
            if on then
                StartInstantGoldCollector(true)
                StartGoldMagnet(function() return STATE.autoCollectGoldItem end)
                STATE.autoCollect = true
                DoAutoCollect(true)
            else
                StartInstantGoldCollector(false)
                StopGoldMagnet()
                STATE.autoCollect = false
                StopLoop("collect")
            end
        end

        -- 
        --  SECTION: AUTO COLLECT GOLD & ITEM (WindUI)
        --  Source asli baris ~5150-5163
        -- 
        MainTab:Section({ Title = "Auto Collect Gold & Item", Icon = "coins" })

        local _collectToggleElement = MainTab:Toggle({
            Flag     = "mainCollect",
            Title    = "AUTO COLLECT GOLD & ITEM",
            Desc     = "collect semua gold/item ke player",
            Value    = false,
            Callback = function(on)
                _autoCollectState = on
                DoAutoCollectGoldItem(on)
            end,
        })

        -- Expose ke global (dibaca Config panel saat restore)
        _setAutoCollectToggle = function(v)
            if _collectToggleElement then
                _collectToggleElement:Set(v)  -- trigger Callback + update visual
            end
        end
        _visAutoCollect = function(v)
            if _collectToggleElement then
                _collectToggleElement:Set(v, false)  -- update visual only (false = silent)
            end
        end

    end -- end do PANEL: MAIN (Auto Collect Gold & Item)


    -- 
    --  SECTION: AUTO SELL HERO EQUIP
    --  Source asli baris ~3971-4145
    -- 
    MainTab:Section({ Title = "Auto Sell Hero Equip", Icon = "package-minus" })

    -- Paragraph status (diupdate via SetSellStatus)
    _statusParagraph = MainTab:Paragraph({
        Title = "Status",
        Desc  = "Idle",
    })

    -- Toggle utama AUTO SELL HERO EQUIP
    -- Source asli baris ~3971-3978
    local _sellToggleElement = MainTab:Toggle({
        Flag     = "mainSellHero",
        Title    = "AUTO SELL HERO EQUIP",
        Desc     = "Auto sell all items (except Locked & Supreme)",
        Value    = false,
        Callback = function(on)
            _autoSellOn      = on
            _autoSellOnState = on
            if _sellToggleCb then _sellToggleCb(on) end
        end,
    })

    -- Expose ke global (dibaca Config panel saat restore)
    _setSellHeroToggle = function(v)
        if _sellToggleElement then
            _sellToggleElement:Set(v)   -- trigger Callback + update visual
        end
    end
    _visSellHero = function(v)
        if _sellToggleElement then
            _sellToggleElement:Set(v, false)  -- update visual only (false = silent)
        end
    end

    --  GUID name cache 
    -- Source asli baris ~3988-4012
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

    --  getType: R / Y / B / other dari karakter pertama nama item 
    -- Source asli baris ~4014-4022
    local function getType(name)
        if not name or #name == 0 then return "other" end
        local f = name:sub(1,1):upper()
        if f == "R" then return "R"
        elseif f == "Y" then return "Y"
        elseif f == "B" then return "B"
        else return "other" end
    end

    --  getGrade: parse grade dari data / nama item 
    -- Source asli baris ~4024-4038
    local function getGrade(item)
        local d = (item.data and type(item.data) == "table") and item.data or item
        local g = d.grade or d.Grade or d.gradeId or d.gradeType
        if g then return tostring(g):upper() end
        local name = item.name or item.Name or item.itemName or d.name or ""
        local found = name:match("%[M%+%+%]") and "M++"
                   or name:match("%[M%+%]")   and "M+"
                   or name:match("%[SS%]")     and "SS"
                   or name:match("%[([EDCBAGSNMedcbagsn])%]")
        if found then return found:upper() end
        return nil
    end

    --  shouldSell: filter lock / Supreme / tipe / grade 
    -- Source asli baris ~4040-4054 (dead code di source asli, tetap dibawa)
    local function shouldSell(item, name, isLock)
        if isLock then return false, "locked" end
        if name and name:lower():find("supreme", 1, true) then return false, "Supreme" end
        local typ = getType(name)
        if typ ~= "other" and not _sellTypes[typ] then return false, "tipe " .. typ .. " dimatikan" end
        local grade = getGrade(item)
        if grade then
            local itemRank = _SELL_GRADE_RANK[grade] or 0
            local minRank  = _SELL_GRADE_RANK[_minGrade] or 1
            if itemRank >= minRank then return false, "grade " .. grade .. " >= min " .. _minGrade end
        end
        return true, ""
    end

    --  doSell: fire remote + update counter 
    -- Source asli baris ~4058-4068 (dead code di source asli, tetap dibawa)
    local function doSell(guid, name)
        local remote = Remotes:FindFirstChild("DelectHeroEquips")
        if not remote then return end
        pcall(function()
            remote:FireServer({guid})
            local prefix = getType(name)
            _cnt[prefix] = (_cnt[prefix] or 0) + 1
            RefreshCounters()
            SetSellStatus(
                "Sold [" .. (_cnt.R + _cnt.Y + _cnt.B + _cnt.other) .. "] " .. name:sub(1,24)
            )
        end)
    end

    --  StartAutoSell: attach listener ke UpdateHeroEquip 
    -- Source asli baris ~4071-4136
    local function StartAutoSell()
        if _sellConn then pcall(function() _sellConn:Disconnect() end) end

        local updateRemote = Remotes:FindFirstChild("UpdateHeroEquip")
        if not updateRemote then
            SetSellStatus("[!] Remote UpdateHeroEquip NOT FOUND!")
            return
        end

        scanGuidNames()

        -- Pantau Lock / Unlock agar item locked tidak ikut terjual
        pcall(function()
            local lockR   = Remotes:FindFirstChild("LockHeroEquip")
            local unlockR = Remotes:FindFirstChild("UnlockHeroEquip")
            if lockR then
                lockR.OnClientEvent:Connect(function(d)
                    local g = type(d) == "string" and d
                          or (type(d) == "table" and (d.guid or d[1]))
                          or nil
                    if g then _lockedGuids[g] = true end
                end)
            end
            if unlockR then
                unlockR.OnClientEvent:Connect(function(d)
                    local g = type(d) == "string" and d
                          or (type(d) == "table" and (d.guid or d[1]))
                          or nil
                    if g then _lockedGuids[g] = nil end
                end)
            end
        end)

        _sellConn = updateRemote.OnClientEvent:Connect(function(data)
            if not _autoSellOn then return end
            if type(data) ~= "table" then return end
            task.spawn(function()
                task.wait(0.3)
                -- [v186] Struktur confirmed dari sniff:
                -- item = { guid="...", data = { id=970002, isLock=bool, grade=990001, guid="..." } }
                local items = {}
                if data.heroEquips and type(data.heroEquips) == "table" then
                    items = data.heroEquips
                elseif data[1] and type(data[1]) == "table" then
                    items = data
                elseif data.guid then
                    items = {data}
                end

                for _, item in ipairs(items) do
                    if not _autoSellOn then break end

                    local guid = item.guid
                    if guid and #tostring(guid) > 0 then
                        local d      = (item.data and type(item.data) == "table") and item.data or item
                        local isLock = d.isLock or d.locked or d.isLocked or false
                        if _lockedGuids[tostring(guid)] then isLock = true end

                        if not isLock then
                            scanGuidNames()
                            local name   = _guidNames[tostring(guid)] or ""
                            local prefix = getType(name)

                            task.wait(0.15)
                            local remote = Remotes:FindFirstChild("DelectHeroEquips")
                            if remote then
                                local ok = pcall(function() remote:FireServer({tostring(guid)}) end)
                                if ok then
                                    _cnt[prefix] = (_cnt[prefix] or 0) + 1
                                    RefreshCounters()
                                    local total = _cnt.R + _cnt.Y + _cnt.B + _cnt.other
                                    local label = #name > 0 and name:sub(1,20)
                                              or ("ID:" .. tostring(d.id or "?"))
                                    SetSellStatus(
                                        "Sold [" .. total .. "] " .. prefix .. ": " .. label
                                    )
                                end
                            end
                        end
                    end
                end
                task.delay(0.5, scanGuidNames)
            end)
        end)

        SetSellStatus("[OK] Monitoring Active - Sell All except Locked")
    end

    --  Callback toggle ON/OFF 
    -- Source asli baris ~4138-4145
    _sellToggleCb = function(on)
        if on then
            StartAutoSell()
        else
            if _sellConn then
                pcall(function() _sellConn:Disconnect() end)
                _sellConn = nil
            end
            local total = _cnt.R + _cnt.Y + _cnt.B + _cnt.other
            SetSellStatus("Idle - " .. total .. " item terjual")
        end
    end

end -- end do PANEL: MAIN (Counter + Auto Sell Hero Equip)

-- ============================================================================
-- PANEL: MAIN → AUTO SELL WEAPON
-- Ditempatkan di bawah "Auto Sell Hero Equip" sesuai permintaan.
--
-- Cara kerja (BUKAN event-driven seperti Auto Sell Hero Equip, tapi manual
-- scan-based sesuai spesifikasi):
--   1) User membuka EquipmentPanel (tab Weapon) secara manual di game.
--   2) User tekan tombol SCAN WEAPON -> baca semua clone weapon di
--      ScrollingFrame (nama child = GUID weapon), tentukan status
--      LOCK/UNLOCK dari visibility tombol aksi (LockBtn/UnLockBtn).
--      Hasil jumlah per-status ditampilkan di Status paragraph.
--      [SKIP FAV] Status Favourite SENGAJA tidak dipakai dalam logika ini
--      (elemen UnFavouriteBtn tidak konsisten terbaca saat sniff, dan atas
--      keputusan user cukup pakai Lock/Unlock saja untuk menentukan sell).
--   3) User tekan tombol SELL UNLOCK WEAPON -> fire SATU batch DeleteWeapons
--      berisi SEMUA guid yang berstatus UNLOCK (bukan Locked).
--   4) [FIX] Setiap GUID yang berhasil di-fire DeleteWeapons dicatat PERMANEN
--      ke blacklist (_soldGuidsEver), TIDAK PERNAH di-reset selama script masih
--      berjalan. SCAN berikutnya (kapan pun, walau sudah SELL berkali-kali)
--      akan MELEWATI TOTAL clone yang GUID-nya ada di blacklist ini -- sehingga
--      weapon yang sudah ter-SELL/DELETE TIDAK AKAN PERNAH terdeteksi lagi
--      sebagai UNLOCK, walau ScrollingFrame di GUI game sempat stale/delay
--      re-render dan masih menampilkan clone lamanya sesaat.
--
-- Struktur GUI dikonfirmasi via sniff manual (2025 session), path:
--   PlayerGui.EquipmentPanel.Frame.EquipmentPackage.Right.Mid.ScrollingFrame
--   -> direct children: UIGridLayout (skip) + 1x "EquipmentTemplate" (template
--      kosong, skip) + Nx clone weapon (nama = GUID format uuid).
-- Per clone weapon:
--   - Nama weapon      : clone.TitleText.Text
--   - Status LOCK      : clone...LockImage.UnLockBtn.Visible == true  -> LOCKED
--                         (LockBtn.Visible == true  -> UNLOCKED, kebalikannya)
--   [SKIP FAV] Status Favourite tidak dipakai (lihat catatan di atas).
--   (Confirmed: nama tombol = AKSI yang tersedia, bukan status saat ini -
--    itu sebabnya "LockBtn" visible justru berarti weapon BELUM di-lock.)
-- ============================================================================
do
    local GUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

    --  State lokal (scope do-block) 
    local _lastScan      = {}   -- array of {guid, name, isLock}  ([SKIP FAV] Favourite tidak lagi dipakai)
    local _scanDone      = false
    local _statusPara    = nil
    local _sellCooldown  = false  -- true sesaat setelah SELL, supaya SCAN tidak baca GUI yang masih stale
    local _soldGuidsEver = {}     -- [PERMANEN, TIDAK PERNAH DI-RESET] {[guid]=true} - semua GUID yang
                                   -- pernah berhasil di-fire DeleteWeapons sepanjang sesi script berjalan.
                                   -- Dipakai sebagai BLACKLIST permanen: begitu sebuah GUID pernah sukses
                                   -- di-sell, GUID itu TIDAK BOLEH pernah masuk hasil SCAN lagi -- walau
                                   -- clone-nya masih sempat kebaca stale di ScrollingFrame (delay render
                                   -- server->client). Ini mencegah weapon yang sudah terjual "muncul lagi"
                                   -- sebagai UNLOCK saat di-scan ulang.

    local function SetWStatus(msg)
        if not _statusPara then return end
        pcall(function() _statusPara:SetDesc(msg) end)
    end

    --  Cari EquipmentPanel yang sedang aktif (bisa ada >1 instance, pakai yang GUID children terbanyak) 
    local function _findActiveScrollFrame()
        local best, bestCount = nil, -1
        local candidates = {}
        for _, obj in ipairs(PG:GetDescendants()) do
            if obj.Name == "EquipmentPanel" then
                local sf = obj:FindFirstChild("ScrollingFrame", true)
                if sf then
                    local c = 0
                    for _, child in ipairs(sf:GetChildren()) do
                        if child.Name:match(GUID_PATTERN) then c = c + 1 end
                    end
                    table.insert(candidates, { path = sf:GetFullName(), count = c, ref = sf })
                    if c > bestCount then bestCount = c; best = sf end
                end
            end
        end

        -- [SILENT] Logika pemilihan scrollFrame tetap sama persis (pilih yang GUID
        -- children terbanyak kalau ada >1 instance panel co-exist), hanya print
        -- debug-nya yang dihilangkan supaya console tidak dibanjiri log.
        return best, bestCount
    end

    --  SCAN: baca semua weapon + status LOCK/UNLOCK/FAVOURITE 
    local function ScanWeapons()
        if _sellCooldown then
            SetWStatus("[!] Tunggu sebentar, GUI masih refresh setelah SELL terakhir...")
            return
        end

        local scrollFrame, count = _findActiveScrollFrame()
        if not scrollFrame or count <= 0 then
            _scanDone = false
            _lastScan = {}
            SetWStatus("[!] EquipmentPanel/weapon tidak ditemukan. Buka panel Weapon dulu di game.")
            return
        end

        local results = {}
        local unreadableCount = 0
        local blacklistedCount = 0  -- jumlah clone stale (GUID sudah pernah ke-sell) yang di-skip total
        for _, clone in ipairs(scrollFrame:GetChildren()) do
            if clone.Name:match(GUID_PATTERN) then
                repeat -- dibungkus repeat/until-true supaya bisa "continue" via break (goto/label
                       -- tidak dipakai demi kompatibilitas executor, konsisten dgn pola AUTO SIEGE)
                    local guid = clone.Name

                    -- [FIX UTAMA] Kalau GUID ini sudah PERNAH berhasil di-sell sebelumnya
                    -- (tercatat permanen di _soldGuidsEver), LEWATI TOTAL -- jangan masukkan
                    -- ke `results` sama sekali. Ini menangani kasus clone lama yang masih
                    -- sempat kebaca di ScrollingFrame karena GUI/server belum sepenuhnya
                    -- selesai refresh (stale), sehingga weapon yang sudah terjual TIDAK AKAN
                    -- PERNAH muncul lagi sebagai UNLOCK di hasil SCAN berikutnya.
                    if _soldGuidsEver[guid] then
                        blacklistedCount = blacklistedCount + 1
                        break
                    end

                    local name = "?"
                    local isLock = false
                    local lockReadOk = false  -- [DEBUG] true kalau LockImage.UnLockBtn benar2 ditemukan

                    pcall(function()
                        local titleText = clone:FindFirstChild("TitleText", true)
                        if titleText and titleText:IsA("TextLabel") then
                            name = titleText.Text
                        end

                        -- [SKIP FAV] Hanya status LOCK/UNLOCK yang dipakai untuk menentukan
                        -- boleh-tidaknya sell (sesuai keputusan: Favourite di-skip dari logika).
                        local lockImg = clone:FindFirstChild("LockImage", true)
                        if lockImg then
                            local unlockBtn = lockImg:FindFirstChild("UnLockBtn")
                            if unlockBtn then
                                isLock = (unlockBtn.Visible == true)
                                lockReadOk = true
                            end
                        end
                    end)

                    if not lockReadOk then
                        unreadableCount = unreadableCount + 1
                        -- [SILENT] Weapon yang gagal baca status Lock tetap otomatis
                        -- di-skip dari SELL (lihat SellUnlockedWeapons di bawah), hanya
                        -- print warning-nya yang dihilangkan.
                    end

                    table.insert(results, { guid = guid, name = name, isLock = isLock, lockReadOk = lockReadOk })
                until true
            end
        end

        -- [SILENT] Ringkasan unreadableCount & blacklistedCount tetap dihitung dan
        -- ditampilkan di Status paragraph GUI (lihat SetWStatus di bawah), hanya
        -- print ke console yang dihilangkan.

        -- `results` di titik ini SUDAH DIJAMIN tidak berisi satupun GUID yang ada di
        -- _soldGuidsEver (sudah difilter total di loop atas). Jadi setiap weapon yang
        -- muncul di sini sudah pasti weapon BARU/valid, bukan weapon lama yang sudah terjual.
        _lastScan = results
        _scanDone = true

        local lockedN, unlockedN = 0, 0
        local unlockedGuidsPreview = {}
        for _, w in ipairs(results) do
            if w.isLock then
                lockedN = lockedN + 1
            else
                unlockedN = unlockedN + 1
                if #unlockedGuidsPreview < 5 then
                    table.insert(unlockedGuidsPreview, (w.name or "?") .. "|" .. w.guid:sub(1,8))
                end
            end
        end

        local unlockedNote = ""
        if unlockedN > 0 then
            unlockedNote = "  (Sample: " .. table.concat(unlockedGuidsPreview, ", ") .. ")"
            -- [SILENT] Detail lengkap per-weapon UNLOCK sebelumnya di-print ke console;
            -- sekarang dihilangkan. Preview singkat (nama + 8 karakter GUID) tetap
            -- tampil di Status paragraph GUI lewat unlockedNote di atas.
        end

        local blacklistNote = ""
        if blacklistedCount > 0 then
            blacklistNote = "  |  Di-skip (sudah pernah terjual): " .. blacklistedCount
        end

        SetWStatus(
            "[OK] Total: " .. #results ..
            "  |  Unlock: " .. unlockedN ..
            "  |  Lock: " .. lockedN ..
            blacklistNote ..
            "  ->  Tekan SELL untuk hapus " .. unlockedN .. " weapon Unlock" ..
            unlockedNote
        )
    end

    --  SELL: fire batch DeleteWeapons untuk semua guid ber-status UNLOCK saja 
    local function SellUnlockedWeapons()
        if _sellCooldown then
            SetWStatus("[!] Tunggu sebentar, masih proses SELL sebelumnya...")
            return
        end
        if not _scanDone or #_lastScan == 0 then
            SetWStatus("[!] Belum ada hasil SCAN. Tekan SCAN WEAPON dulu.")
            return
        end

        local toSell = {}
        local skippedUnreadable = 0
        for _, w in ipairs(_lastScan) do
            -- [SAFETY] Kalau status Lock gagal terbaca (lockReadOk=false), JANGAN sell -
            -- lebih baik skip daripada salah jual weapon yang sebenarnya Lock.
            if not w.lockReadOk then
                skippedUnreadable = skippedUnreadable + 1
            elseif not w.isLock then
                table.insert(toSell, w.guid)
            end
        end

        -- [SILENT] Info skippedUnreadable tetap ditampilkan ke Status paragraph GUI
        -- lewat SetWStatus (lihat pesan "[skip krn gagal baca status]" di bawah),
        -- hanya print ke console yang dihilangkan.

        if #toSell == 0 then
            SetWStatus("[OK] Tidak ada weapon Unlock untuk dijual (semua Lock)." ..
                (skippedUnreadable > 0 and ("  [" .. skippedUnreadable .. " di-skip krn gagal baca status]") or ""))
            return
        end

        local remote = Remotes:FindFirstChild("DeleteWeapons")
        if not remote then
            SetWStatus("[!] Remote DeleteWeapons tidak ditemukan!")
            return
        end

        local ok = pcall(function()
            remote:FireServer(toSell)
        end)

        if ok then
            SetWStatus("[OK] SOLD " .. #toSell .. " weapon Unlock. Mohon tunggu, GUI sedang refresh...")

            -- [FIX UTAMA] Catat GUID yang barusan berhasil di-fire ke BLACKLIST PERMANEN
            -- (_soldGuidsEver) -- di-TAMBAHKAN, BUKAN DI-RESET/DITIMPA. Dengan begini,
            -- semua weapon yang PERNAH berhasil dijual sepanjang sesi script berjalan
            -- (bukan cuma dari SELL barusan) akan terus diblokir dan tidak pernah lagi
            -- muncul/ke-fire di SCAN atau SELL berikutnya, walau clone-nya masih sempat
            -- kebaca stale di GUI game.
            for _, g in ipairs(toSell) do _soldGuidsEver[g] = true end

            -- Reset hasil scan supaya tidak sell dobel kalau SELL ditekan lagi tanpa scan ulang
            _scanDone = false
            _lastScan = {}

            -- [FIX STALE GUI] Beri jeda 2 detik sebelum SCAN/SELL berikutnya boleh dipakai,
            -- supaya server sempat proses delete & client GUI (ScrollingFrame) sempat
            -- re-render tanpa clone yang baru dihapus. Tanpa jeda ini, SCAN yang ditekan
            -- terlalu cepat akan membaca clone lama yang belum sempat hilang dari GUI.
            _sellCooldown = true
            task.delay(2, function()
                _sellCooldown = false
                SetWStatus("[OK] SOLD " .. #toSell .. " weapon Unlock selesai. Tekan SCAN untuk cek sisa.")
            end)
        else
            SetWStatus("[!] Gagal fire DeleteWeapons.")
        end
    end

    --  UI 
    MainTab:Section({ Title = "Auto Sell Weapon", Icon = "package-minus" })

    _statusPara = MainTab:Paragraph({
        Title = "Status",
        Desc  = "Idle - buka EquipmentPanel di game, lalu tekan SCAN WEAPON",
    })

    MainTab:Button({
        Title    = "SCAN WEAPON",
        Desc     = "Scan status Lock/Unlock semua weapon (buka EquipmentPanel dulu)",
        Callback = function()
            ScanWeapons()
        end,
    })

    MainTab:Button({
        Title    = "SELL UNLOCK WEAPON",
        Desc     = "Jual/Delete semua weapon berstatus UNLOCK hasil SCAN (Lock aman)",
        Callback = function()
            SellUnlockedWeapons()
        end,
    })
end -- end do PANEL: MAIN (Auto Sell Weapon)

-- ============================================================================
-- TAB LAINNYA - placeholder (belum diisi fungsi)
-- FarmTab, MassAttackTab, AutomationTab, RerollTab,
-- PlayerTab, SettingTab, WebhookTab, ConfigTab, ThemeTab
-- -> diisi sesuai urutan pengisian selanjutnya
-- ============================================================================

-- ============================================================================
-- PANEL: HIDE
-- Dipindah dari baris ~5171 source premium
-- Ditulis ulang pakai WindUI native API
-- Perbedaan API vs source asli:
--   Source asli: NewPanel("hide") + ToggleRow custom
--   WindUI:      HideTab:Section() + HideTab:Toggle() + HideTab:Paragraph()
-- Global expose:
--   _hideRerollChatState, _setHideRerollChat, _visHideRerollChat
--   _hideAllUIState,      _setHideAllUI,      _visHideAllUI
--   _hideAllAnimState,    _setHideAllAnim,     _visHideAllAnim
--   _hideRewardState,     _setHideReward,      _visHideRewardPanel
-- ============================================================================
do
    -- Global expose state tracking (dibaca Config panel saat save/load)
    -- Sama persis dengan deklarasi source asli baris ~1787-1789
    _hideRerollChatState = false
    _hideAllUIState      = false
    _hideAllAnimState    = false
    _hideRewardState     = false

    -- Global expose setters/vis (diisi setelah Toggle dibuat)
    -- Sama persis dengan deklarasi source asli baris ~1767-1772, ~1743-1744
    _setHideRerollChat  = nil
    _visHideRerollChat  = nil
    _setHideAllUI       = nil
    _visHideAllUI       = nil
    _setHideAllAnim     = nil
    _visHideAllAnim     = nil
    _setHideReward      = nil
    _visHideRewardPanel = nil

    -- State internal
    local _hideRerollOn = false
    local _hideUIOn     = false
    local _hideAnimOn   = false
    local _hideRewardOn     = false
    local _hideRewardThread = nil  -- [FIXED zombie] track thread untuk cancel

    local _rerollConn  = nil
    local _animLoop    = nil
    local _animWsConn  = nil
    local _uiAddConn   = nil

    -- Cache untuk restore
    local _rerollHidden = {}  -- [Frame baris] = true
    local _uiCache      = {}  -- [obj] = state sebelum hide
    local _animBbCache  = {}
    local _animPcCache  = {}

    -- Nama GUI kita sendiri - dikecualikan dari HIDE ALL UI (source asli ~5189)
    local _OUR_GUI = "ASH_NightFrost"

    -- ============================================================
    -- 1. HIDE REROLL CHAT  (source asli baris ~5199-5292)
    -- Struktur ExperienceChat:
    --   ScrollingFrame[scrollView]
    --     Frame[0-{uuid}]    <-- satu baris chat (INI yang di-hide)
    --       Frame[TextMessage]
    --         TextLabel[BodyText]  <-- teks "... just reroll a ..."
    -- ============================================================

    local function isRerollText(t)
        t = (t or ""):gsub("<[^>]+>", ""):lower()
        return t:find("reroll a", 1, true) ~= nil
    end

    -- Naik 2 level: BodyText -> Frame[TextMessage] -> Frame[0-{uuid}] = baris chat
    local function getRowFrame(lbl)
        local p1 = lbl.Parent
        if not p1 then return lbl end
        local p2 = p1.Parent
        if not p2 then return p1 end
        if p2:IsA("ScrollingFrame") then return p1 end
        return p2
    end

    local function hideRow(row)
        if row and row.Parent and not _rerollHidden[row] then
            row.Visible = false
            _rerollHidden[row] = true
        end
    end

    local function scanAndHideReroll()
        pcall(function()
            local ec = game:GetService("CoreGui"):FindFirstChild("ExperienceChat")
            if not ec then return end
            for _, obj in ipairs(ec:GetDescendants()) do
                if obj.Name == "BodyText" and (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
                    if isRerollText(obj.Text) then hideRow(getRowFrame(obj)) end
                end
            end
        end)
    end

    local function ApplyHideReroll(on)
        _hideRerollChatState = on
        _hideRerollOn        = on
        if _rerollConn then _rerollConn:Disconnect(); _rerollConn = nil end

        if on then
            scanAndHideReroll()
            pcall(function()
                local CG2 = game:GetService("CoreGui")
                local ec   = CG2:FindFirstChild("ExperienceChat")
                if not ec then ec = CG2:WaitForChild("ExperienceChat", 10) end
                if not ec then return end
                _rerollConn = ec.DescendantAdded:Connect(function(obj)
                    task.delay(0.2, function()
                        pcall(function()
                            if not _hideRerollOn then return end
                            if obj.Name == "BodyText" and (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
                                if isRerollText(obj.Text) then hideRow(getRowFrame(obj)) end
                            end
                        end)
                    end)
                end)
            end)
        else
            for row in pairs(_rerollHidden) do
                pcall(function() if row and row.Parent then row.Visible = true end end)
            end
            _rerollHidden = {}
        end
    end

    -- ============================================================
    -- 2. HIDE ALL UI  (source asli baris ~5294-5373)
    -- ============================================================

    local function ApplyHideUI(on)
        _hideAllUIState = on
        _hideUIOn       = on
        if _uiAddConn then _uiAddConn:Disconnect(); _uiAddConn = nil end

        if on then
            _uiCache = {}
            pcall(function()
                for _, gui in ipairs(PG:GetChildren()) do
                    pcall(function()
                        if gui.Name == _OUR_GUI then return end
                        if gui:IsA("ScreenGui") or gui:IsA("GuiBase2d") then
                            _uiCache[gui] = gui.Enabled
                            gui.Enabled   = false
                        elseif gui:IsA("GuiObject") then
                            _uiCache[gui] = gui.Visible
                            gui.Visible   = false
                        end
                    end)
                end
            end)

            -- [FIX SIEGE] Panel Siege wajib dikecualikan dari hide
            local _SIEGE_PANEL_KW = {
                "cityraid","city_raid","garrisoncityraid","garrisonboss",
                "siege","cityraidpanel","cityraidenterpanel",
                "raidcityresult","garrisonraidresult","citycount","citytimer",
            }
            local function _isSiegePanelGui(gui)
                if not (SIEGE and SIEGE.inMap) then return false end
                local n = gui.Name:lower()
                for _, kw in ipairs(_SIEGE_PANEL_KW) do
                    if n:find(kw, 1, true) then return true end
                end
                return false
            end

            _uiAddConn = PG.ChildAdded:Connect(function(gui)
                task.defer(function()
                    pcall(function()
                        if not _hideUIOn then return end
                        if gui.Name == _OUR_GUI then return end
                        if _isSiegePanelGui(gui) then return end
                        if gui:IsA("ScreenGui") or gui:IsA("GuiBase2d") then
                            _uiCache[gui] = gui.Enabled
                            gui.Enabled   = false
                        elseif gui:IsA("GuiObject") then
                            _uiCache[gui] = gui.Visible
                            gui.Visible   = false
                        end
                    end)
                end)
            end)
        else
            if _uiAddConn then _uiAddConn:Disconnect(); _uiAddConn = nil end
            for obj, prev in pairs(_uiCache) do
                pcall(function()
                    if obj and obj.Parent then
                        if obj:IsA("ScreenGui") or obj:IsA("GuiBase2d") then
                            obj.Enabled = prev
                        elseif obj:IsA("GuiObject") then
                            obj.Visible = prev
                        end
                    end
                end)
            end
            _uiCache = {}
        end
    end

    -- ============================================================
    -- 3. HIDE ALL ANIMATION (versi penuh, restore sempurna)
    -- Source asli baris ~5375-5496
    -- ============================================================

    local function ApplyHideAnim(on)
        _hideAllAnimState = on
        _hideAnimOn       = on

        if on then
            _animBbCache = {}
            _animPcCache = {}
            if _animLoop then _animLoop:Disconnect(); _animLoop = nil end

            -- Stop animation tracks via RenderStepped (throttle 0.5s - FLa CPU)
            local _animLoop2LastT = 0
            _animLoop = game:GetService("RunService").RenderStepped:Connect(function()
                local _now2 = tick()
                if (_now2 - _animLoop2LastT) < 0.5 then return end
                _animLoop2LastT = _now2
                pcall(function()
                    for _, fname in ipairs({"Heros","Pets","Characters"}) do
                        local folder = workspace:FindFirstChild(fname)
                        if folder then
                            for _, char in ipairs(folder:GetChildren()) do
                                local hum = char:FindFirstChildOfClass("Humanoid")
                                         or char:FindFirstChildOfClass("AnimationController")
                                if hum then
                                    local anim = hum:FindFirstChildOfClass("Animator")
                                    if anim then
                                        for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                                            track:AdjustSpeed(0)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
            end)

            -- Matikan efek di workspace + cache state awal
            pcall(function()
                for _, obj in ipairs(workspace:GetDescendants()) do
                    pcall(function()
                        if obj:IsA("BillboardGui") then
                            local n = obj.Name:lower()
                            if not n:find("name") and not n:find("health") and not n:find("tag") then
                                _animBbCache[obj] = obj.Enabled
                                obj.Enabled = false
                            end
                        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
                            or obj:IsA("PointLight") or obj:IsA("Fire") or obj:IsA("Sparkles") then
                            _animPcCache[obj] = obj.Enabled
                            obj.Enabled = false
                        end
                    end)
                end
            end)

            -- Watch objek efek baru yang spawn
            if _animWsConn then _animWsConn:Disconnect(); _animWsConn = nil end
            _animWsConn = workspace.DescendantAdded:Connect(function(obj)
                task.defer(function()
                    pcall(function()
                        if not _hideAnimOn then return end
                        if obj:IsA("BillboardGui") then
                            local n = obj.Name:lower()
                            if not n:find("name") and not n:find("health") and not n:find("tag") then
                                _animBbCache[obj] = obj.Enabled; obj.Enabled = false
                            end
                        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
                            or obj:IsA("PointLight") or obj:IsA("Fire") or obj:IsA("Sparkles") then
                            _animPcCache[obj] = obj.Enabled; obj.Enabled = false
                        end
                    end)
                end)
            end)

        else
            -- RESTORE PENUH
            if _animLoop   then _animLoop:Disconnect();   _animLoop   = nil end
            if _animWsConn then _animWsConn:Disconnect(); _animWsConn = nil end

            -- Resume semua animation track
            pcall(function()
                for _, fname in ipairs({"Heros","Pets","Characters"}) do
                    local folder = workspace:FindFirstChild(fname)
                    if folder then
                        for _, char in ipairs(folder:GetChildren()) do
                            local hum = char:FindFirstChildOfClass("Humanoid")
                                     or char:FindFirstChildOfClass("AnimationController")
                            if hum then
                                local anim = hum:FindFirstChildOfClass("Animator")
                                if anim then
                                    for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                                        pcall(function() track:AdjustSpeed(1) end)
                                    end
                                end
                            end
                        end
                    end
                end
            end)

            for obj, prev in pairs(_animBbCache) do
                pcall(function() if obj and obj.Parent then obj.Enabled = prev end end)
            end
            _animBbCache = {}

            for obj, prev in pairs(_animPcCache) do
                pcall(function() if obj and obj.Parent then obj.Enabled = prev end end)
            end
            _animPcCache = {}
        end
    end

    -- ============================================================
    -- 4. AUTO HIDE REWARD  (source asli baris ~5498-5567)
    -- ============================================================

    local function ApplyHideReward(on)
        _hideRewardState = on
        _hideRewardOn    = on

        if on then
            local HIDE_PANELS = {"RewardsFrame","ResultFrame","RewardPanel","ChallengeGarrisonBossSuccess"}

            local function forceHide(obj)
                if not obj or not obj.Parent then return end
                pcall(function()
                    if obj:IsA("GuiObject") then
                        obj.Visible  = false
                        obj.Position = UDim2.new(2, 0, 2, 0)
                    elseif obj:IsA("ScreenGui") then
                        obj.Enabled = false
                    end
                end)
            end

            local function checkAndHide(obj)
                if not _hideRewardOn then return end
                if not (obj:IsA("GuiObject") or obj:IsA("ScreenGui")) then return end
                for _, name in ipairs(HIDE_PANELS) do
                    if obj.Name == name or obj.Name:find("GarrisonBoss") then
                        if _hideRewardOn then forceHide(obj) end
                        pcall(function()
                            if obj:IsA("GuiObject") then
                                obj:GetPropertyChangedSignal("Visible"):Connect(function()
                                    if _hideRewardOn and obj.Visible then forceHide(obj) end
                                end)
                            elseif obj:IsA("ScreenGui") then
                                obj:GetPropertyChangedSignal("Enabled"):Connect(function()
                                    if _hideRewardOn and obj.Enabled then forceHide(obj) end
                                end)
                            end
                        end)
                        break
                    end
                end
            end

            for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do checkAndHide(obj) end

            -- [FIXED zombie] cancel thread lama sebelum spawn baru
            if _hideRewardThread then
                pcall(function() task.cancel(_hideRewardThread) end)
                _hideRewardThread = nil
            end
            -- Ghost polling loop — state-bound: mati otomatis saat _hideRewardOn = false
            _hideRewardThread = task.spawn(function()
                while _hideRewardOn do
                    task.wait(0.5)
                    pcall(function()
                        for _, obj in ipairs(LP.PlayerGui:GetChildren()) do
                            for _, name in ipairs(HIDE_PANELS) do
                                if obj.Name == name or obj.Name:find("GarrisonBoss") then
                                    forceHide(obj)
                                end
                            end
                        end
                    end)
                end
                _hideRewardThread = nil  -- bersih saat loop selesai natural
            end)
        end
    end

    -- ============================================================
    -- WINDUI UI ELEMENTS
    -- ============================================================

    HideTab:Section({ Title = "Hide Manager", Icon = "eye-off" })

    HideTab:Paragraph({
        Title = "Hide Manager",
        Desc  = "Sembunyikan elemen game. Toggle OFF untuk restore penuh.",
    })

    -- 1. HIDE REROLL CHAT
    HideTab:Section({ Title = "Hide Reroll Chat", Icon = "message-square-off" })

    local _hrcrToggle = HideTab:Toggle({
        Flag     = "hideRerollChat",
        Title    = "HIDE REROLL CHAT",
        Desc     = "Sembunyikan baris chat 'just reroll a...' tanpa menghilangkan chat box",
        Value    = false,
        Callback = function(on) ApplyHideReroll(on) end,
    })
    _setHideRerollChat = function(v)
        ApplyHideReroll(v)
        if _hrcrToggle then pcall(function() _hrcrToggle:Set(v) end) end
    end
    _visHideRerollChat = function(v)
        if _hrcrToggle then pcall(function() _hrcrToggle:Set(v, false) end) end
    end

    -- 2. HIDE ALL UI
    HideTab:Section({ Title = "Hide All UI", Icon = "layout-dashboard" })

    local _hauiToggle = HideTab:Toggle({
        Flag     = "hideAllUI",
        Title    = "HIDE ALL UI",
        Desc     = "Sembunyikan semua panel game. Toggle OFF restore penuh.",
        Value    = false,
        Callback = function(on) ApplyHideUI(on) end,
    })
    _setHideAllUI = function(v)
        ApplyHideUI(v)
        if _hauiToggle then pcall(function() _hauiToggle:Set(v) end) end
    end
    _visHideAllUI = function(v)
        if _hauiToggle then pcall(function() _hauiToggle:Set(v, false) end) end
    end

    -- 3. HIDE ALL ANIMATION
    HideTab:Section({ Title = "Hide All Animation", Icon = "zap-off" })

    local _hanimToggle = HideTab:Toggle({
        Flag     = "hideAllAnim",
        Title    = "HIDE ALL ANIMATION",
        Desc     = "Matikan animasi, efek, partikel. Restore penuh saat OFF.",
        Value    = false,
        Callback = function(on) ApplyHideAnim(on) end,
    })
    _setHideAllAnim = function(v)
        ApplyHideAnim(v)
        if _hanimToggle then pcall(function() _hanimToggle:Set(v) end) end
    end
    _visHideAllAnim = function(v)
        if _hanimToggle then pcall(function() _hanimToggle:Set(v, false) end) end
    end

    -- 4. AUTO HIDE REWARD
    HideTab:Section({ Title = "Auto Hide Reward", Icon = "gift" })

    local _hrewToggle = HideTab:Toggle({
        Flag     = "hideReward",
        Title    = "AUTO HIDE REWARD",
        Desc     = "Sembunyikan popup reward otomatis.Aktifkan setelah Reward muncul",
        Value    = false,
        Callback = function(on) ApplyHideReward(on) end,
    })
    _setHideReward = function(v)
        ApplyHideReward(v)
        if _hrewToggle then pcall(function() _hrewToggle:Set(v) end) end
    end
    _visHideRewardPanel = function(v)
        if _hrewToggle then pcall(function() _hrewToggle:Set(v, false) end) end
    end

end -- end do PANEL: HIDE



-- ============================================================================
-- PANEL: MAIN (lanjutan)
-- AUTO DECOMPOSE GEMS
-- Dipindah dari baris ~4762 source premium
-- Ditulis ulang pakai WindUI native API
-- Perbedaan API vs source asli:
--   Source asli: Frame/Btn/Label/Pill + TextBox input custom
--   WindUI:      Toggle + Input (min) + Input (max) + Paragraph status
-- Global expose: _autoDecompGemSet, _visDecompGem, _autoDecompGemState,
--                _setGemLevelRange, _gemMinLevelState, _gemMaxLevelState
-- ============================================================================
do
    --  Global expose (dibaca Config panel saat save/load) 
    -- Sama persis dengan deklarasi source asli baris ~1720-1763
    _autoDecompGemSet  = nil   -- setter logic toggle (fn(bool))
    _visDecompGem      = nil   -- setter visual-only toggle (fn(bool))
    _autoDecompGemState = false -- tracking state untuk Config
    _setGemLevelRange  = nil   -- setter level range (fn(min,max))
    _gemMinLevelState  = 1     -- tracking min level untuk Config
    _gemMaxLevelState  = 1     -- tracking max level untuk Config

    --  State internal
    local _autoDecompGemOn     = false
    local _autoDecompGemThread = nil
    local GEM_ITEM_TYPE        = 7
    local _gemMinLevel         = 1
    local _gemMaxLevel         = 1

    --  GEM_ID_RANGES: tabel itemId gem berdasarkan nama dan level
    -- Source asli baris ~4772-4808
    -- Format: {startId, endId, minLevel, maxLevel, displayName}
    local GEM_ID_RANGES = {
        {88001, 88009,  1,  9, "Ruby"},
        {88011, 88019,  1,  9, "Emerald"},
        {88021, 88029,  1,  9, "Sapphire"},
        {88031, 88039,  1,  9, "Deadly Gem"},
        {88141, 88149,  1,  9, "Purple Gem"},
        -- Lv10
        {88010, 88010, 10, 10, "Ruby"},
        {88061, 88070, 11, 20, "Ruby"},
        {88020, 88020, 10, 10, "Emerald"},
        {88071, 88080, 11, 20, "Emerald"},
        {88030, 88030, 10, 10, "Sapphire"},
        {88081, 88090, 11, 20, "Sapphire"},
        {88040, 88040, 10, 10, "Deadly Gem"},
        {88091, 88100, 11, 20, "Deadly Gem"},
        {88150, 88150, 10, 10, "Purple Gem"},
        {88151, 88160, 11, 20, "Purple Gem"},
        -- Lv21-30
        {88171, 88180, 21, 30, "Ruby"},
        {88181, 88190, 21, 30, "Emerald"},
        {88191, 88200, 21, 30, "Sapphire"},
        -- Colorful Gem: game Level 101-109 = user level 1-9
        {88041, 88049,  1,  9, "Colorful Gem"},
        {88050, 88050, 10, 10, "Colorful Gem"},
        {88101, 88110, 11, 20, "Colorful Gem"},
        -- Rainbow Gem: game Level 101-109 = user level 1-9
        {88051, 88059,  1,  9, "Rainbow Gem"},
        {88060, 88060, 10, 10, "Rainbow Gem"},
        {88111, 88120, 11, 20, "Rainbow Gem"},
    }

    -- Build lookup: itemId -> userLevel
    -- Source asli baris ~4810-4816
    local GEM_ID_TO_LEVEL = {}
    for _, r in ipairs(GEM_ID_RANGES) do
        local startId, endId, minLv = r[1], r[2], r[3]
        for id = startId, endId do
            GEM_ID_TO_LEVEL[id] = minLv + (id - startId)
        end
    end

    -- IsGemIdToDecomp: cek apakah itemId masuk range min-max level
    -- Source asli baris ~4820-4823
    local function IsGemIdToDecomp(itemId, minLv, maxLv)
        local lv = GEM_ID_TO_LEVEL[itemId]
        if not lv then return false end
        return lv >= minLv and lv <= maxLv
    end

    --  SetDGStatus: update paragraph status
    local _dgStatusParagraph = nil
    local function SetDGStatus(msg)
        if not _dgStatusParagraph then return end
        pcall(function() _dgStatusParagraph:SetDesc(msg) end)
    end

    --  SetDGLevelRange: update state + visual Input WindUI
    -- Source asli baris ~4878-4892
    local _dgMinInputElement = nil
    local _dgMaxInputElement = nil
    local function SetDGLevelRange(minLv, maxLv)
        _gemMinLevel      = minLv or 1
        _gemMaxLevel      = maxLv or 1
        _gemMinLevelState = _gemMinLevel
        _gemMaxLevelState = _gemMaxLevel
        -- Update visual WindUI Input
        if _dgMinInputElement then
            pcall(function() _dgMinInputElement:Set(tostring(_gemMinLevel)) end)
        end
        if _dgMaxInputElement then
            pcall(function() _dgMaxInputElement:Set(tostring(_gemMaxLevel)) end)
        end
    end

    --  GetGemGuidsFromPanel: scan GemsPanel, filter berdasarkan itemId / Lv text
    -- Source asli baris ~4929-4994
    local function GetGemGuidsFromPanel(minLv, maxLv)
        local result = {}
        pcall(function()
            local pg = LP.PlayerGui
            local gp = pg:FindFirstChild("GemsPanel")
            if not gp then return end

            -- Cari ScrollingFrame container gem
            local sf = nil
            pcall(function()
                sf = gp:FindFirstChild("Frame")
                    :FindFirstChild("BgImage")
                    :FindFirstChild("List")
                    :FindFirstChild("ScrollingFrame")
            end)
            if not sf then
                for _, obj in ipairs(gp:GetDescendants()) do
                    if obj:IsA("ScrollingFrame") then sf = obj; break end
                end
            end
            if not sf then return end

            for _, child in ipairs(sf:GetChildren()) do
                repeat
                    local guidStr = child.Name
                    -- Hanya proses child dengan nama UUID
                    if #guidStr ~= 36 or not guidStr:find("^%x+%-%x+%-%x+%-%x+%-%x+$") then break end

                    -- Sumber 1: attribute langsung di child
                    local itemId = child:GetAttribute("itemId") or child:GetAttribute("ItemId")
                                or child:GetAttribute("id")     or child:GetAttribute("Id")
                                or child:GetAttribute("item_id")

                    -- Sumber 2: scan descendants
                    if not itemId then
                        for _, c in ipairs(child:GetDescendants()) do
                            local aid = c:GetAttribute("itemId") or c:GetAttribute("ItemId")
                                     or c:GetAttribute("id")     or c:GetAttribute("Id")
                                     or c:GetAttribute("item_id")
                            if aid and tonumber(aid) then itemId = tonumber(aid); break end
                        end
                    end

                    -- Jika dapat itemId, filter dengan GEM_ID_TO_LEVEL
                    if itemId and tonumber(itemId) then
                        local id = tonumber(itemId)
                        if IsGemIdToDecomp(id, minLv, maxLv) then
                            table.insert(result, guidStr)
                        end
                    else
                        -- Fallback: parse "Lv.X" dari NumText / TextLabel
                        local lvFound = nil
                        for _, c in ipairs(child:GetDescendants()) do
                            if c:IsA("TextLabel") and (
                                c.Name == "NumText" or
                                c.Name:lower():find("lv") or
                                c.Name:lower():find("level")
                            ) then
                                local n = c.Text:match("[Ll][Vv]%.?%s*(%d+)")
                                if n then lvFound = tonumber(n); break end
                            end
                        end
                        if lvFound and lvFound >= minLv and lvFound <= maxLv then
                            table.insert(result, guidStr)
                        end
                    end
                until true
            end
        end)
        return result
    end

    --  SetDGPillOff: matikan toggle secara paksa (WindUI)
    -- Source asli baris ~5001-5007
    local _dgToggleElement = nil
    local function SetDGPillOff()
        _autoDecompGemOn = false
        if _dgToggleElement then
            pcall(function() _dgToggleElement:Set(false, false) end)
        end
    end

    --  RunAutoDecompGem: validasi input, scan panel, fire DecomposeItems
    -- Source asli baris ~5008-5104
    local function RunAutoDecompGem()
        -- Validasi min level
        if _gemMinLevel < 1 then
            SetDGStatus("[ERROR] Min Level wajib diisi!")
            task.wait(2); SetDGPillOff()
            SetDGStatus("Idle - Input Error")
            return
        end

        -- Validasi max level
        if _gemMaxLevel < 1 then
            SetDGStatus("[ERROR] Max Level wajib diisi!")
            task.wait(2); SetDGPillOff()
            SetDGStatus("Idle - Input Error")
            return
        end

        -- Validasi: min tidak boleh > max
        if _gemMinLevel > _gemMaxLevel then
            SetDGStatus("[ERROR] Min Level > Max Level!")
            task.wait(2); SetDGPillOff()
            SetDGStatus("Idle - Input Error")
            return
        end

        -- Validasi: range 1-150
        if _gemMinLevel < 1 or _gemMinLevel > 150 or _gemMaxLevel < 1 or _gemMaxLevel > 150 then
            SetDGStatus("[ERROR] Level harus antara 1-150!")
            task.wait(2); SetDGPillOff()
            SetDGStatus("Idle - Input Error")
            return
        end

        -- Update state tracking
        _gemMinLevelState = _gemMinLevel
        _gemMaxLevelState = _gemMaxLevel

        SetDGStatus("SCAN Inventory...")
        task.wait(0.5)

        local guids = GetGemGuidsFromPanel(_gemMinLevel, _gemMaxLevel)

        if #guids == 0 then
            SetDGStatus("[!] OPEN GemsPanel First! (Lv" .. _gemMinLevel .. "-" .. _gemMaxLevel .. ")")
            task.wait(2); SetDGPillOff()
            SetDGStatus("Idle - OPEN GemsPanel First")
            return
        end

        SetDGStatus("GOT " .. #guids .. " gem (Lv" .. _gemMinLevel .. "-" .. _gemMaxLevel .. ")...")
        task.wait(0.3)

        local decomposed = 0
        local BATCH = 20
        local re = Remotes:FindFirstChild("DecomposeItems")
        if not re then
            SetDGStatus("[!] DecomposeItems remote NOT FOUND!")
            task.wait(2); SetDGPillOff()
            return
        end

        for i = 1, #guids, BATCH do
            if not _autoDecompGemOn then break end
            local batch = {}
            for j = i, math.min(i + BATCH - 1, #guids) do
                table.insert(batch, guids[j])
            end
            SetDGStatus("Decompose " .. decomposed .. "/" .. #guids .. "...")
            -- [v54 FIX] Format confirmed SimpleSpy: {itemType=7, data={guid1,...}}
            pcall(function() re:FireServer({itemType = GEM_ITEM_TYPE, data = batch}) end)
            decomposed = decomposed + #batch
            task.wait(0.5)
        end

        SetDGStatus("[OK] " .. decomposed .. " gem DECOMPOSED! (Lv" .. _gemMinLevel .. "-" .. _gemMaxLevel .. ")")
        task.wait(2); SetDGPillOff()
        SetDGStatus("Idle")
    end

    -- 
    --  SECTION: AUTO DECOMPOSE GEMS (WindUI)
    --  Source asli baris ~4826-5148
    -- 
    MainTab:Section({ Title = "Auto Decompose Gems", Icon = "gem" })

    -- Paragraph status
    _dgStatusParagraph = MainTab:Paragraph({
        Title = "Status",
        Desc  = "Idle",
    })

    -- Input Min Level
    -- Pengganti dgMinInput TextBox dari source asli baris ~4858-4868
    _dgMinInputElement = MainTab:Input({
        Flag        = "mainGemMin",
        Title       = "Min Level",
        Desc        = "Level minimum gem yang akan di-decompose (1-120)",
        Placeholder = "Contoh: 1",
        Value       = "1",
        Callback    = function(val)
            local n = tonumber(val)
            if n and n >= 1 and n <= 150 then
                _gemMinLevel      = n
                _gemMinLevelState = n
            end
        end,
    })

    -- Input Max Level
    -- Pengganti dgMaxInput TextBox dari source asli baris ~4870-4880
    _dgMaxInputElement = MainTab:Input({
        Flag        = "mainGemMax",
        Title       = "Max Level",
        Desc        = "Level maksimum gem yang akan di-decompose (1-120)",
        Placeholder = "Contoh: 5",
        Value       = "1",
        Callback    = function(val)
            local n = tonumber(val)
            if n and n >= 1 and n <= 150 then
                _gemMaxLevel      = n
                _gemMaxLevelState = n
            end
        end,
    })

    -- Set default via SetDGLevelRange (expose ke global setelah elemen dibuat)
    SetDGLevelRange(1, 1)
    _setGemLevelRange = SetDGLevelRange

    -- Toggle utama AUTO DECOMPOSE GEMS
    -- Source asli baris ~4826-4830 (dgPill.MouseButton1Click)
    _dgToggleElement = MainTab:Toggle({
        Flag     = "mainDecompGem",
        Title    = "AUTO DECOMPOSE GEMS",
        Desc     = "Scan GemsPanel & decompose gem sesuai range level",
        Value    = false,
        Callback = function(on)
            _autoDecompGemOn    = on
            _autoDecompGemState = on
            if on then
                _autoDecompGemThread = task.spawn(RunAutoDecompGem)
            else
                if _autoDecompGemThread then
                    pcall(function() task.cancel(_autoDecompGemThread) end)
                    _autoDecompGemThread = nil
                end
                SetDGStatus("Idle - STOPPED")
            end
        end,
    })

    --  Expose ke global (dibaca Config panel saat restore)
    -- Source asli baris ~5122-5148
    _autoDecompGemSet = function(v)
        if v == _autoDecompGemOn then return end
        _autoDecompGemOn    = v
        _autoDecompGemState = v
        if _dgToggleElement then _dgToggleElement:Set(v) end
    end

    _visDecompGem = function(v)
        _autoDecompGemState = v
        if _dgToggleElement then _dgToggleElement:Set(v, false) end
    end

end -- end do PANEL: MAIN (Auto Decompose Gems)

-- ============================================================================
-- PANEL: MAIN (lanjutan)
-- AUTO MERGE POTION
-- Dipindah dari baris ~8627 source premium (v243)
-- Ditulis ulang pakai WindUI native API
-- Perbedaan API vs source asli:
--   Source asli: Frame/Btn/Label custom + MakeDropdown + MakeSlider + ToggleRow
--   WindUI:      Section + Paragraph + Dropdown(Multi=false) + Input + Toggle
-- Remote: PotionMerge:InvokeServer({id=id, count=cnt})
-- Global expose: _mergeRunningState, _setMergeToggle, _visMerge
-- ============================================================================
do
    --  Global expose (dibaca Config panel saat save/load) 
    -- Sama persis dengan deklarasi source asli baris ~1721, ~1736, ~1752
    _mergeRunningState = false  -- tracking state untuk Config
    _setMergeToggle    = nil    -- setter logic toggle (fn(bool))
    _visMerge          = nil    -- setter visual-only toggle (fn(bool))

    --  POTION DATA (source asli baris ~8447-8455) 
    local MERGE_POTIONS = {
        {name = "Small Attack Potion", id = 10048},
        {name = "Small Gold Potion",   id = 10049},
        {name = "Small Luck Potion",   id = 10047},
        {name = "Big Potion DMG",      id = 10051},
        {name = "Big Potion Gold",     id = 10052},
        {name = "Big Potion Luck",     id = 10050},
    }

    --  Build tabel dropdown values (nama) dan lookup nama -> id
    -- WindUI Dropdown bekerja dengan string value
    local _mDropValues = {}   -- list nama untuk WindUI Dropdown Values
    local _mNameToId   = {}   -- {["Small Attack Potion"] = 10048, ...}
    for _, pt in ipairs(MERGE_POTIONS) do
        table.insert(_mDropValues, pt.name)
        _mNameToId[pt.name] = pt.id
    end

    --  State internal (source asli baris ~8654-8658) 
    local _mergeSelectedId = nil  -- nil = belum dipilih user
    local _mergeCount      = 1    -- default count = 1
    local _mergeRunning    = false
    local _mergeThread     = nil

    --  SetMergeStatus: update paragraph status 
    local _mergeStatusParagraph = nil
    local function SetMergeStatus(msg)
        if not _mergeStatusParagraph then return end
        pcall(function() _mergeStatusParagraph:SetDesc(msg) end)
    end

    -- 
    --  SECTION: AUTO MERGE POTION (WindUI)
    --  Source asli baris ~8627-8748
    -- 
    MainTab:Section({ Title = "Auto Merge Potion", Icon = "flask-conical" })

    -- Paragraph status (pengganti mStatusCard dari source asli baris ~8661-8665)
    _mergeStatusParagraph = MainTab:Paragraph({
        Title = "Status",
        Desc  = "Idle - SELECT ITEM & ENABLE",
    })

    -- Dropdown SELECT ITEM (pengganti MakeDropdown dari source asli baris ~8668-8690)
    -- Single-select (Multi=false):
    --   - Value = nil  -> placeholder "--" (WindUI default untuk kosong)
    --   - Callback menerima ap.Value langsung = string nama item (bukan table)
    local _mDropElement = MainTab:Dropdown({
        Flag     = "mainMergeItem",
        Title    = "Select Item",
        Desc     = "Pilih potion yang akan di-merge",
        Values   = _mDropValues,
        Value    = nil,   -- nil = kosong / belum pilih (bukan {} - itu untuk Multi=true)
        Multi    = false,
        Callback = function(val)
            -- Single-select: WindUI kirim ap.Value = string nama item
            local selectedName = type(val) == "string" and val or nil
            if selectedName and _mNameToId[selectedName] then
                _mergeSelectedId = _mNameToId[selectedName]
                SetMergeStatus("ITEM SELECTED: " .. selectedName)
            else
                _mergeSelectedId = nil
                SetMergeStatus("Idle - SELECT ITEM & ENABLE")
            end
        end,
    })

    -- Input COUNT 1-5 (pengganti MakeSlider(1,5) dari source asli baris ~8691-8707)
    -- WindUI tidak memiliki Slider -> pakai Input number
    local _mCountInput = MainTab:Input({
        Flag        = "mainMergeCount",
        Title       = "Count (1-5)",
        Desc        = "Jumlah merge per siklus (1-5)",
        Placeholder = "Contoh: 1",
        Value       = "1",
        Callback    = function(val)
            local n = tonumber(val)
            if n and n >= 1 and n <= 5 then
                _mergeCount = math.floor(n)
            end
        end,
    })

    -- Toggle ON/OFF (pengganti ToggleRow dari source asli baris ~8708-8741)
    local _mergeToggleElement = MainTab:Toggle({
        Flag     = "mainMergeToggle",
        Title    = "AUTO MERGE POTION",
        Desc     = "ON = START merge potion",
        Value    = false,
        Callback = function(on)
            if on then
                -- Validasi: item harus sudah dipilih
                if not _mergeSelectedId then
                    SetMergeStatus("[!] SELECT ITEM PLEASE!")
                    -- Matikan toggle kembali (silent)
                    task.defer(function()
                        if _mergeToggleElement then
                            pcall(function() _mergeToggleElement:Set(false, false) end)
                        end
                    end)
                    return
                end
                _mergeRunning      = true
                _mergeRunningState = true
                -- Cancel thread lama jika ada
                if _mergeThread then pcall(function() task.cancel(_mergeThread) end) end
                -- Spawn loop merge
                _mergeThread = task.spawn(function()
                    while _mergeRunning do
                        local id  = _mergeSelectedId
                        local cnt = _mergeCount
                        SetMergeStatus("[M] Merging id=" .. id .. " x" .. cnt)
                        pcall(function()
                            local re = Remotes:FindFirstChild("PotionMerge")
                            if re then re:InvokeServer({id = id, count = cnt}) end
                        end)
                        SetMergeStatus("[OK] Merge DONE x" .. cnt)
                        task.wait(0.5)
                    end
                    SetMergeStatus("Idle - toggle OFF")
                end)
            else
                _mergeRunning      = false
                _mergeRunningState = false
                if _mergeThread then
                    pcall(function() task.cancel(_mergeThread) end)
                    _mergeThread = nil
                end
                SetMergeStatus("Idle - SELECT ITEM & ENABLE")
            end
        end,
    })

    --  Expose ke global (dibaca Config panel saat restore)
    -- Source asli baris ~8740-8741
    _setMergeToggle = function(v)
        if _mergeToggleElement then
            _mergeToggleElement:Set(v)           -- trigger Callback + update visual
        end
    end
    _visMerge = function(v)
        if _mergeToggleElement then
            _mergeToggleElement:Set(v, false)    -- update visual only (silent)
        end
    end

end -- end do PANEL: MAIN (Auto Merge Potion)

-- ============================================================================
-- PANEL: MAIN (lanjutan)
-- AUTO USE POTION
-- Dipindah dari baris ~8750 source premium (v243)
-- Ditulis ulang pakai WindUI native API
-- Perbedaan API vs source asli:
--   Source asli: Frame/Btn/Label custom + MakeDropdown + MakeSlider + ToggleRow
--   WindUI:      Section + Paragraph + Dropdown(Multi=false) + Input + Toggle
-- Remote: UseItem:InvokeServer({useCount=cnt, itemId=id})
-- Global expose: _useRunningState, _setUseToggle, _visUse
-- ============================================================================
do
    --  Global expose (dibaca Config panel saat save/load) 
    -- Sama persis dengan deklarasi source asli baris ~1722, ~1737, ~1753
    _useRunningState = false  -- tracking state untuk Config
    _setUseToggle    = nil    -- setter logic toggle (fn(bool))
    _visUse          = nil    -- setter visual-only toggle (fn(bool))

    --  POTION DATA (source asli baris ~8456-8468) 
    -- USE_POTIONS memiliki 9 item (termasuk Super Potion) vs MERGE_POTIONS 6 item
    local USE_POTIONS = {
        {name = "Small Potion DMG",  id = 10048},
        {name = "Small Potion Gold", id = 10049},
        {name = "Small Potion Luck", id = 10047},
        {name = "Big Potion DMG",    id = 10051},
        {name = "Big Potion Gold",   id = 10052},
        {name = "Big Potion Luck",   id = 10050},
        {name = "Super Potion DMG",  id = 10060},
        {name = "Super Potion Gold", id = 10061},
        {name = "Super Potion Luck", id = 10059},
    }

    --  Build tabel dropdown values dan lookup nama -> id
    local _uDropValues = {}
    local _uNameToId   = {}
    for _, pt in ipairs(USE_POTIONS) do
        table.insert(_uDropValues, pt.name)
        _uNameToId[pt.name] = pt.id
    end

    --  State internal (source asli baris ~8783-8787) 
    local _useSelectedId = nil  -- nil = belum dipilih user
    local _useCount      = 1    -- default count = 1
    local _useRunning    = false
    local _useThread     = nil

    --  SetUseStatus: update paragraph status 
    local _useStatusParagraph = nil
    local function SetUseStatus(msg)
        if not _useStatusParagraph then return end
        pcall(function() _useStatusParagraph:SetDesc(msg) end)
    end

    -- 
    --  SECTION: AUTO USE POTION (WindUI)
    --  Source asli baris ~8750-8872
    -- 
    MainTab:Section({ Title = "Auto Use Potion", Icon = "zap" })

    -- Paragraph status (pengganti uStatusCard dari source asli baris ~8789-8793)
    _useStatusParagraph = MainTab:Paragraph({
        Title = "Status",
        Desc  = "Idle - SELECT ITEM & ENABLE",
    })

    -- Dropdown SELECT ITEM (pengganti MakeDropdown dari source asli baris ~8795-8816)
    -- Single-select (Multi=false):
    --   - Value = nil  -> placeholder "--" (WindUI default untuk kosong)
    --   - Callback menerima ap.Value langsung = string nama item (bukan table)
    local _uDropElement = MainTab:Dropdown({
        Flag     = "mainUseItem",
        Title    = "Select Item",
        Desc     = "Pilih potion yang akan digunakan",
        Values   = _uDropValues,
        Value    = nil,   -- nil = kosong / belum pilih (bukan {} - itu untuk Multi=true)
        Multi    = false,
        Callback = function(val)
            -- Single-select: WindUI kirim ap.Value = string nama item
            local selectedName = type(val) == "string" and val or nil
            if selectedName and _uNameToId[selectedName] then
                _useSelectedId = _uNameToId[selectedName]
                SetUseStatus("Item SELECTED: " .. selectedName)
            else
                _useSelectedId = nil
                SetUseStatus("Idle - SELECT ITEM & ENABLE")
            end
        end,
    })

    -- Input COUNT 1-100 (pengganti MakeSlider(1,100) dari source asli baris ~8817-8830)
    -- WindUI tidak memiliki Slider -> pakai Input number
    local _uCountInput = MainTab:Input({
        Flag        = "mainUseCount",
        Title       = "Use Count (1-100)",
        Desc        = "Jumlah potion yang digunakan per siklus (1-100)",
        Placeholder = "Contoh: 1",
        Value       = "1",
        Callback    = function(val)
            local n = tonumber(val)
            if n and n >= 1 and n <= 100 then
                _useCount = math.floor(n)
            end
        end,
    })

    -- Toggle ON/OFF (pengganti ToggleRow dari source asli baris ~8831-8863)
    local _useToggleElement = MainTab:Toggle({
        Flag     = "mainUseToggle",
        Title    = "AUTO USE POTION",
        Desc     = "ON = start use potion",
        Value    = false,
        Callback = function(on)
            if on then
                -- Validasi: item harus sudah dipilih
                if not _useSelectedId then
                    SetUseStatus("[!] SELECT ITEM PLEASE!")
                    -- Matikan toggle kembali (silent)
                    task.defer(function()
                        if _useToggleElement then
                            pcall(function() _useToggleElement:Set(false, false) end)
                        end
                    end)
                    return
                end
                _useRunning      = true
                _useRunningState = true
                -- Cancel thread lama jika ada
                if _useThread then pcall(function() task.cancel(_useThread) end) end
                -- Spawn loop use
                _useThread = task.spawn(function()
                    while _useRunning do
                        local id  = _useSelectedId
                        local cnt = _useCount
                        SetUseStatus("[U] Using id=" .. id .. " x" .. cnt)
                        pcall(function()
                            local re = Remotes:FindFirstChild("UseItem")
                            if re then re:InvokeServer({useCount = cnt, itemId = id}) end
                        end)
                        SetUseStatus("[OK] Use DONE x" .. cnt)
                        task.wait(0.5)
                    end
                    SetUseStatus("Idle - toggle OFF")
                end)
            else
                _useRunning      = false
                _useRunningState = false
                if _useThread then
                    pcall(function() task.cancel(_useThread) end)
                    _useThread = nil
                end
                SetUseStatus("Idle - SELECT ITEM & ENABLE")
            end
        end,
    })

    --  Expose ke global (dibaca Config panel saat restore)
    -- Source asli baris ~8862-8863
    _setUseToggle = function(v)
        if _useToggleElement then
            _useToggleElement:Set(v)           -- trigger Callback + update visual
        end
    end
    _visUse = function(v)
        if _useToggleElement then
            _useToggleElement:Set(v, false)    -- update visual only (silent)
        end
    end

end -- end do PANEL: MAIN (Auto Use Potion)


-- ============================================================================
-- PANEL: FARM
-- Dipindah dari baris ~5571 source premium (1.lua)
-- Ditulis ulang pakai WindUI native API
--
-- Perbedaan API vs source asli:
--   Source asli : ToggleRow(), custom Frame/Btn dropdown, custom ScrollingFrame rows
--   WindUI      : Tab:Toggle(), Tab:Dropdown(Multi=false), Tab:Paragraph(), Tab:Button()
--                 Enemy list rows dibuat manual (WindUI tidak punya dynamic list),
--                 disimulasikan via Paragraph + Button per enemy (lihat catatan TA di bawah)
--
-- Fitur:
--   1. ENEMY HP MONITOR   HP bar + stopwatch (Paragraph + Button START/STOP/RESET)
--   2. RANDOM ATTACK (RA)  Toggle, kill counter Paragraph, BlockSkillEffects
--   3. SELECT ENEMY / TARGET ATTACK (TA)  Mode dropdown + Refresh + enemy list rows
--
-- Remote:
--   RE.Atk   (RemoteEvent)  : FireServer({attackEnemyGUID=guid})
--   RE.Click (RemoteFunction): InvokeServer({enemyGuid=guid})
--   RE.Death (RemoteEvent)  : OnClientEvent  data.enemyGuid / data.guid
--   ShowEnemyTakeDamageInfo (RemoteEvent RS.Remotes): OnClientEvent  {enemyId, hp, maxHp}
--
-- Global expose:
--   _setRAToggle       set + trigger toggle RA
--   _visRandomAtk      set visual only RA
--   _raRunningState    bool state RA
-- ============================================================================
do
    --  Global expose (dibaca Config panel saat save/load) 
    _raRunningState = false
    _setRAToggle    = nil
    _visRandomAtk   = nil

    --  State RA & TA 
    local RA = { running=false, threads={}, killed=0, cur=nil, next=nil, _lockConn=nil }
    local TA = { running=false, threads={}, killed=0, cur=nil, targetName=nil }

    local _byNameLiveToken = nil
    local _raDiedConns     = {}
    local _deadG_F         = {}
    local HERO_GUIDS_F     = HERO_GUIDS  -- alias ke global, bukan copy

    --  Death listener global 
    -- Source asli baris 5587-5597
    if RE and RE.Death then
        RE.Death.OnClientEvent:Connect(function(d)
            if not d then return end
            local g = d.enemyGuid or d.guid
            if g then
                _deadG_F[g] = false
                if RA.running then RA.killed = RA.killed + 1 end
                if TA.running then TA.killed = TA.killed + 1 end
            end
        end)
    end

    --  Helper: validasi posisi HRP 
    -- Source asli baris 5600-5606
    local function IsPosValidF(hrp)
        if not hrp then return false end
        local pos = hrp.Position
        if pos.X~=pos.X or pos.Y~=pos.Y or pos.Z~=pos.Z then return false end
        if math.abs(pos.X)>1e10 or math.abs(pos.Y)>1e10 or math.abs(pos.Z)>1e10 then return false end
        return true
    end

    --  Helper: scan semua folder enemy standar 
    -- Source asli baris 5611-5635
    local function GetEnemiesF()
        local list = {}
        local seen = {}
        for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
            local f = workspace:FindFirstChild(fname)
            if f then
                for _,e in ipairs(f:GetChildren()) do
                    if e:IsA("Model") then
                        local g = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid")
                                or e:GetAttribute("Guid")     or e:GetAttribute("GUID")
                        local h = e:FindFirstChild("HumanoidRootPart")
                                or e.PrimaryPart
                                or e:FindFirstChild("Torso")
                                or e:FindFirstChild("UpperTorso")
                                or e:FindFirstChildWhichIsA("BasePart")
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        if g and h and hum and hum.Health>0 and not seen[g] and IsPosValidF(h) then
                            seen[g] = true
                            table.insert(list, {model=e, guid=g, hrp=h, name=e.Name})
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
        local hum = e.model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return true end
        return false
    end

    local function FindByGuidF(guid)
        for _,e in ipairs(GetEnemiesF()) do
            if e.guid == guid and not IsDeadF(e) then return e end
        end
        return nil
    end

    local function FindAllByNameF(nm)
        local result = {}
        for _,e in ipairs(GetEnemiesF()) do
            if e.name == nm and not IsDeadF(e) then
                table.insert(result, e)
            end
        end
        return result
    end

    --  Freeze / Unfreeze player 
    -- Source asli baris 5665-5710
    local _frozenWS     = nil
    local _frozenAnchor = false

    local function FreezePlayer()
        local char = LP and LP.Character; if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        _frozenWS = true
        if hrp then
            pcall(function() hrp.AssemblyLinearVelocity  = Vector3.new(0,0,0) end)
            pcall(function() hrp.AssemblyAngularVelocity = Vector3.new(0,0,0) end)
            hum.PlatformStand = false
            hrp.Anchored      = true
            _frozenAnchor     = true
        end
    end

    local function UnfreezePlayer()
        if _frozenWS == nil then return end
        local char = LP and LP.Character; if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and _frozenAnchor then
            hrp.Anchored  = false
            _frozenAnchor = false
        end
        _frozenWS = nil
    end

    local function ReassertFreeze()
        if _frozenWS == nil then return end
        local char = LP and LP.Character; if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and not hrp.Anchored then
            pcall(function() hrp.AssemblyLinearVelocity  = Vector3.new(0,0,0) end)
            pcall(function() hrp.AssemblyAngularVelocity = Vector3.new(0,0,0) end)
            hrp.Anchored = true
        end
    end

    --  TpToF  teleport 3 stud di depan musuh + FreezePlayer (anchor + velocity reset)
    local function TpToF(tgt)
        if not tgt or not tgt.hrp then return end
        local char = LP.Character; if not char then return end
        local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        pcall(function()
            hrp.CFrame = tgt.hrp.CFrame * CFrame.new(0, 0, -3)
        end)
        FreezePlayer()
    end

    --  IsEnemyGuidValid  validasi enemy masih ada & hidup 
    -- Source asli baris 2180-2214
    local function IsEnemyGuidValid(g)
        if not g then return false end
        local ENEMY_FOLDERS = {"Enemys","EnemyCityRaid","CityRaidEnemys","Enemies","Enemy"}
        for _, folderName in ipairs(ENEMY_FOLDERS) do
            local f = workspace:FindFirstChild(folderName)
            if f then
                for _, e in ipairs(f:GetChildren()) do
                    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
                        local hrp = e:FindFirstChild("HumanoidRootPart")
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        if hrp and hum and hum.Health > 0 then return true end
                        return false
                    end
                end
            end
        end
        -- Fallback: nested di workspace.Map.CityRaidEnter (Siege)
        pcall(function()
            local mapF = workspace:FindFirstChild("Map")
            local cre  = mapF and mapF:FindFirstChild("CityRaidEnter")
            if cre then
                for _, e in ipairs(cre:GetDescendants()) do
                    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
                        local hrp = e:FindFirstChild("HumanoidRootPart")
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        if hrp and hum and hum.Health > 0 then return true end
                    end
                end
            end
        end)
        return false
    end

    --  Hero-attack thread per-GUID (EnsureHeroAtkThreadFor / StopHeroAtkThreadFor) 
    -- Source asli baris 2217-2260
    local _heroAtkThreads = {}


    local function EnsureHeroAtkThreadFor(g)
        if not g then return end
        if _heroAtkThreads[g] and _heroAtkThreads[g].running then return end
        local handle = {running = true, tick = 0}
        _heroAtkThreads[g] = handle
        task.spawn(function()
            local _lastFire = {}
            while handle.running do
                if #HERO_GUIDS > 0 and (tick() - handle.tick) >= 0.5 and IsEnemyGuidValid(g) then
                    handle.tick = tick()
                    -- Ambil posisi player sekarang untuk dipasang ke semua hero
                    local _char = LP and LP.Character
                    local _pHRP = _char and _char:FindFirstChild("HumanoidRootPart")
                    local _pPos = _pHRP and _pHRP.Position or Vector3.new(0,0,0)
                    for _, hGuid in ipairs(HERO_GUIDS) do
                        local last = _lastFire[hGuid] or 0
                        if (tick() - last) >= 0.05 then
                            _lastFire[hGuid] = tick()
                            if RE.HeroUseSkill then
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                                task.wait(0.1)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=2,userId=MY_USER_ID,enemyGuid=g}) end)
                                task.wait(0.1)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=3,userId=MY_USER_ID,enemyGuid=g}) end)
                            end
                        end
                        task.wait(0.05)
                    end
                end
                task.wait(0.05)
                if not IsEnemyGuidValid(g) then
                    handle.running = false
                end
            end
            _heroAtkThreads[g] = nil
        end)
    end

    local function StopHeroAtkThreadFor(g)
        if g and _heroAtkThreads[g] then
            _heroAtkThreads[g].running = false
            _heroAtkThreads[g] = nil
        end
    end

    --  TA Spam threads  unlimited attack per-target 
    -- [UNIFIED] Disamakan dgn pola attack thread RA (tAtk, lihat StartRA):
    --   RE.Atk:FireServer 1x/frame + RE.Click:InvokeServer 1x/frame (spawned)
    --   + EnsureHeroAtkThreadFor(g) untuk serangan hero.
    -- FireAttack/FireAllDamage (dual RE.Atk + hero attackType=1 throttle 0.04s
    -- terpisah dari EnsureHeroAtkThreadFor) DIHAPUS karena cuma dipakai di sini
    -- dan menyebabkan RE.Atk + hero attackType=1 ke-fire dobel per frame.
    local _taSpamThreads = {}

    local function TaSpamF(g, enemyHRP)
        if not g then return end
        if _taSpamThreads[g] and _taSpamThreads[g].running then return end
        local handle = {running = true}
        _taSpamThreads[g] = handle
        task.spawn(function()
            while handle.running do
                if IsEnemyGuidValid(g) then
                    if RE.Atk then
                        pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
                    end
                    if RE.Click then
                        task.spawn(function()
                            pcall(function() RE.Click:InvokeServer({enemyGuid=g}) end)
                        end)
                    end
                    EnsureHeroAtkThreadFor(g)
                end
                task.wait()
            end
        end)
    end

    local function StopClickSpamF(g)
        if g and _taSpamThreads[g] then
            _taSpamThreads[g].running = false
            _taSpamThreads[g] = nil
        end
    end

    local function StopAllClickSpamF()
        for _, handle in pairs(_taSpamThreads) do
            handle.running = false
        end
        _taSpamThreads = {}
    end

    local function FCharF(g, enemyHRP)
        if not g then return end
        TaSpamF(g, enemyHRP)
    end

    --  Skill Effect Blocker 
    -- Source asli baris 5806-5907
    local _secBlocked  = false
    local _secOrigCast = {}
    local _enemyAnimBlocked = false
    local _enemyAnimConns   = {}

    local function BlockSkillEffects(on)
        if on == _secBlocked then return end
        _secBlocked = on
        pcall(function()
            local TARGET_FOLDERS = {"SkillEffectContainer", "Anims"}
            if on then
                for _, folderName in ipairs(TARGET_FOLDERS) do
                    local folder = workspace:FindFirstChild(folderName)
                    if not folder then continue end
                    for _, desc in ipairs(folder:GetDescendants()) do
                        if desc:IsA("Animator") then
                            pcall(function()
                                for _, track in ipairs(desc:GetPlayingAnimationTracks()) do
                                    track:Stop(0)
                                end
                            end)
                        elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                            pcall(function()
                                desc.Enabled = false
                                if desc:IsA("ParticleEmitter") then desc:Clear() end
                            end)
                        elseif desc:IsA("BasePart") then
                            _secOrigCast[desc] = desc.CastShadow
                            pcall(function()
                                desc.Transparency = 1
                                desc.CastShadow   = false
                                desc.CanCollide   = false
                                desc.CanQuery     = false
                                desc.CanTouch     = false
                            end)
                        end
                    end
                    folder.DescendantAdded:Connect(function(desc)
                        if not _secBlocked then return end
                        if desc:IsA("Animator") then
                            task.defer(function()
                                pcall(function()
                                    for _, track in ipairs(desc:GetPlayingAnimationTracks()) do
                                        track:Stop(0)
                                    end
                                end)
                            end)
                        elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                            pcall(function()
                                desc.Enabled = false
                                if desc:IsA("ParticleEmitter") then desc:Clear() end
                            end)
                        elseif desc:IsA("BasePart") then
                            pcall(function()
                                desc.Transparency = 1
                                desc.CanCollide   = false
                                desc.CanQuery     = false
                                desc.CanTouch     = false
                                desc.CastShadow   = false
                            end)
                        end
                    end)
                end
            else
                if RA.running or TA.running then return end
                for _, folderName in ipairs(TARGET_FOLDERS) do
                    local folder = workspace:FindFirstChild(folderName)
                    if not folder then continue end
                    for _, desc in ipairs(folder:GetDescendants()) do
                        if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                            pcall(function() desc.Enabled = true end)
                        elseif desc:IsA("BasePart") then
                            pcall(function()
                                desc.Transparency = 0
                                desc.CanCollide   = true
                                desc.CanQuery     = true
                                desc.CanTouch     = true
                                desc.CastShadow   = _secOrigCast[desc] ~= nil and _secOrigCast[desc] or true
                            end)
                        end
                    end
                end
                _secOrigCast = {}
            end
        end)
    end

    -- BlockEnemyHitAnim: memblokir animasi hit-react musuh (Animator di dalam
    -- model workspace.Enemys) secara real-time. Berbeda dari BlockSkillEffects
    -- (yang menangani SkillEffectContainer/Anims), ini menyasar Animator milik
    -- karakter musuh itu sendiri supaya track animasi tidak menumpuk (>64 limit)
    -- dan menghemat memory saat RA/TA/FASTATTACK menyerang enemy berkali-kali.
    local function BlockEnemyHitAnim(on)
        if on == _enemyAnimBlocked then return end
        _enemyAnimBlocked = on
        pcall(function()
            local enemysFolder = workspace:FindFirstChild("Enemys")
            if not enemysFolder then return end

            if on then
                -- Stop semua track yang sedang jalan sekarang
                for _, desc in ipairs(enemysFolder:GetDescendants()) do
                    if desc:IsA("Animator") then
                        pcall(function()
                            for _, track in ipairs(desc:GetPlayingAnimationTracks()) do
                                track:Stop(0)
                            end
                        end)
                    end
                end
                -- Listener: setiap Animator baru yang muncul (enemy baru di-spawn)
                table.insert(_enemyAnimConns, enemysFolder.DescendantAdded:Connect(function(desc)
                    if not _enemyAnimBlocked then return end
                    if desc:IsA("Animator") then
                        table.insert(_enemyAnimConns, desc.AnimationPlayed:Connect(function(track)
                            if not _enemyAnimBlocked then return end
                            pcall(function() track:Stop(0) end)
                        end))
                    end
                end))
                -- Listener: pasang juga di Animator yang sudah ada sekarang,
                -- untuk track baru yang mau diputar setelahnya (real-time block)
                for _, desc in ipairs(enemysFolder:GetDescendants()) do
                    if desc:IsA("Animator") then
                        table.insert(_enemyAnimConns, desc.AnimationPlayed:Connect(function(track)
                            if not _enemyAnimBlocked then return end
                            pcall(function() track:Stop(0) end)
                        end))
                    end
                end
            else
                for _, c in ipairs(_enemyAnimConns) do
                    pcall(function() c:Disconnect() end)
                end
                _enemyAnimConns = {}
            end
        end)
    end

    --  StopRA     -- Source asli baris 6122-6145 (forward-declared, dipakai StartRA  StopRA)
    local function StopRA()
        RA.running = false
        BlockSkillEffects(false)
        if not TA.running then BlockEnemyHitAnim(false) end
        if RA._lockConn then
            pcall(function() RA._lockConn:Disconnect() end)
            RA._lockConn = nil
        end
        for _,t in ipairs(RA.threads) do pcall(function() task.cancel(t) end) end
        -- Stop semua hero-atk thread
        for g in pairs(_heroAtkThreads) do StopHeroAtkThreadFor(g) end
        if RA.cur and RA.cur.guid then StopHeroAtkThreadFor(RA.cur.guid) end
        RA.threads={}; RA.cur=nil; RA.next=nil
        for _,c in ipairs(_raDiedConns or {}) do pcall(function() c:Disconnect() end) end
        _raDiedConns = {}
        if not TA.running then
            UnfreezePlayer()
        end
    end

    --  StopTA 
    -- Source asli baris 6274-6287
    local function StopTA()
        TA.running = false
        BlockSkillEffects(false)
        if not RA.running then BlockEnemyHitAnim(false) end
        for _,t in ipairs(TA.threads) do pcall(function() task.cancel(t) end) end
        TA.threads = {}
        StopAllClickSpamF()
        if TA.cur and TA.cur.guid then
            StopHeroAtkThreadFor(TA.cur.guid)
        end
        TA.cur=nil; TA.targetName=nil
        if not RA.running then
            UnfreezePlayer()
        end
        -- [FIX v17] Hapus task.defer(TpToRA)  race condition dengan auto-switch dropdown.
        -- Combat Lock Heartbeat RA akan otomatis relock player ke musuh RA di frame berikutnya.
    end

    --  StartRA 
    -- Source asli baris 5909-6120
    local function StartRA()
        if #HERO_GUIDS == 0 then
            pcall(function()
                for _, obj in ipairs(LP.PlayerGui:GetChildren()) do
                    local g = obj:GetAttribute("heroGuid") or obj:GetAttribute("guid")
                    if type(g)=="string" and IsValidUUID(g) then
                        local dup=false
                        for _,ex in ipairs(HERO_GUIDS) do if ex==g then dup=true; break end end
                        if not dup then table.insert(HERO_GUIDS, g) end
                    end
                end
            end)
        end
        RA.running=true; RA.killed=0; RA.cur=nil; RA.next=nil; RA.threads={}
        BlockSkillEffects(true)
        BlockEnemyHitAnim(true)

        local function IsTargetAliveRA(t)
            if not t or not t.model or not t.model.Parent then return false end
            local hum = t.model:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then return false end
            return true
        end

        -- RAFreezePlayer/RAUnfreezePlayer diganti dengan FreezePlayer/UnfreezePlayer global
        -- supaya StopRA -> UnfreezePlayer() selalu bisa melepas Anchored dengan benar

        local function TpToRA(tgt)
            if not tgt or not tgt.hrp then return end
            local char = LP.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            pcall(function()
                hrp.CFrame = tgt.hrp.CFrame * CFrame.new(0, 0, -3)
            end)
        end

        local function PickRandomEnemy(excludeGuids)
            local pool = {}
            local taGuid = TA.running and TA.cur and TA.cur.guid
            for _,e in ipairs(GetEnemiesF()) do
                if IsTargetAliveRA(e) then
                    local skip = false
                    if taGuid and e.guid == taGuid then skip = true end
                    if excludeGuids then
                        for _,ex in ipairs(excludeGuids) do
                            if e.guid == ex then skip = true; break end
                        end
                    end
                    if not skip then table.insert(pool, e) end
                end
            end
            if #pool == 0 then
                for _,e in ipairs(GetEnemiesF()) do
                    if IsTargetAliveRA(e) then table.insert(pool, e) end
                end
            end
            if #pool == 0 then return nil end
            return pool[math.random(1, #pool)]
        end

        local function LockNextTarget()
            local excludes = {}
            if RA.cur then table.insert(excludes, RA.cur.guid) end
            RA.next = PickRandomEnemy(excludes)
        end

        local _raDiedConnsLocal = {}
        local function WatchEnemyRA(e)
            if not e or not e.model then return end
            local hum = e.model:FindFirstChildOfClass("Humanoid"); if not hum then return end
            local conn; conn = hum.Died:Connect(function()
                _deadG_F[e.guid] = true
                if RA.running then RA.killed = RA.killed + 1 end
                if RA.cur and RA.cur.guid == e.guid then RA.cur = nil end
                pcall(function() conn:Disconnect() end)
            end)
            table.insert(_raDiedConnsLocal, conn)
        end

        -- Combat Lock via Heartbeat
        -- [FIX v17] Player nempel ke musuh RA (bukan musuh ke player).
        -- Skip saat TA running: player sedang di posisi musuh TA, biarkan saja.
        local _raLockFrame = 0
        local _raLockConn = RunService.Heartbeat:Connect(function()
            _raLockFrame = _raLockFrame + 1
            if _raLockFrame % 2 ~= 0 then return end
            if not RA.running then return end
            if TA.running then return end  -- TA ON: player harus di posisi musuh TA, bukan RA
            if not RA.cur or not IsTargetAliveRA(RA.cur) then return end
            local char = LP.Character
            local pHRP = char and char:FindFirstChild("HumanoidRootPart")
            local eHRP = RA.cur.hrp
            if pHRP and eHRP then
                pcall(function()
                    -- Player mengikuti musuh (3 stud di depan musuh)
                    pHRP.CFrame = eHRP.CFrame * CFrame.new(0, 0, -3)
                end)
            end
        end)
        RA._lockConn = _raLockConn

        -- Main thread
        local tMain = task.spawn(function()
            RA.cur = PickRandomEnemy({})
            if RA.cur then
                TpToRA(RA.cur); FreezePlayer()
                WatchEnemyRA(RA.cur)
                local hum = RA.cur.model:FindFirstChildOfClass("Humanoid")
                if hum then
                    local capturedGuid = RA.cur.guid
                    hum.Died:Connect(function()
                        RA.killed = RA.killed + 1
                        if RA.cur and RA.cur.guid == capturedGuid then RA.cur = nil end
                    end)
                end
                LockNextTarget()
            end
            while RA.running do
                if not RA.cur or not IsTargetAliveRA(RA.cur) then
                    local _oldGuid = RA.cur and RA.cur.guid
                    if _oldGuid then
                        StopHeroAtkThreadFor(_oldGuid)
                        _deadG_F[_oldGuid] = nil
                    end
                    RA.cur = IsTargetAliveRA(RA.next) and RA.next or PickRandomEnemy({})
                    RA.next = nil
                    if RA.cur then
                        if not TA.running then TpToRA(RA.cur); FreezePlayer() end  -- TA ON: jangan override posisi TA
                        WatchEnemyRA(RA.cur)
                        local hum = RA.cur.model:FindFirstChildOfClass("Humanoid")
                        if hum then
                            local capturedGuid = RA.cur.guid
                            hum.Died:Connect(function()
                                RA.killed = RA.killed + 1
                                if RA.cur and RA.cur.guid == capturedGuid then RA.cur = nil end
                            end)
                        end
                        LockNextTarget()
                    end
                end
                if not IsTargetAliveRA(RA.next) then LockNextTarget() end
                task.wait(0.15)
            end
        end)

        -- [v27] Attack thread RA: GASS terus, selalu serang guid musuh RA sendiri
        local tAtk = task.spawn(function()
            while RA.running do
                if RA.cur and IsTargetAliveRA(RA.cur) then
                    local g   = RA.cur.guid
                    if RE and RE.Atk then
                        pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
                    end
                    if RE and RE.Click then
                        task.spawn(function()
                            pcall(function() RE.Click:InvokeServer({enemyGuid=g}) end)
                        end)
                    end
                    EnsureHeroAtkThreadFor(g)
                end
                task.wait()
            end
        end)

        RA.threads = {tMain, tAtk}
    end

    --  StartTA By ID 
    -- Source asli baris 6147-6198
    local function StartTA_ByID(targetGuid, targetName, onStatus, onStop)
        TA.running=true; TA.killed=0; TA.targetName=targetName; TA.cur=nil; TA.threads={}
        BlockEnemyHitAnim(true)
        BlockSkillEffects(true)
        local tChar = task.spawn(function()
            local tgt = FindByGuidF(targetGuid)
            if tgt then
                TpToF(tgt); FreezePlayer()
                TA.cur = tgt
                local hum = tgt.model and tgt.model:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.Died:Connect(function()
                        _deadG_F[targetGuid] = true
                        if TA.running then TA.killed = TA.killed + 1 end
                        StopClickSpamF(targetGuid)
                        StopHeroAtkThreadFor(targetGuid)
                        TA.cur=nil; TA.running=false
                        if onStatus then onStatus(" ["..targetName.."] mati") end
                        if onStop   then task.defer(onStop) end
                    end)
                end
            end
            while TA.running do
                tgt = FindByGuidF(targetGuid)
                if not tgt then
                    StopClickSpamF(targetGuid)
                    StopHeroAtkThreadFor(targetGuid)
                    TA.cur = nil
                    if onStatus then onStatus(" ["..targetName.."] mati") end
                    TA.running = false
                    if onStop then onStop() end
                    break
                end
                if not IsDeadF(tgt) and tgt.model.Parent then
                    TA.cur = tgt
                    -- [v27] GASS terus tanpa jeda
                    ReassertFreeze()
                    FCharF(tgt.guid, tgt.hrp)
                    if onStatus then
                        onStatus(">> ["..targetName.."] "..(tgt.guid:sub(1,5)).." Kill: "..TA.killed)
                    end
                    task.wait()
                else
                    task.wait(0.1)
                end
            end
        end)
        TA.threads = {tChar}
    end

    --  StartTA By Name 
    -- Source asli baris 6200-6272
    local function StartTA_ByName(targetName, onStatus, onStop)
        TA.running=true; TA.killed=0; TA.targetName=targetName; TA.cur=nil; TA.threads={}
        BlockEnemyHitAnim(true)
        BlockSkillEffects(true)
        local tChar = task.spawn(function()
            local rrIdx    = 1
            local _curDied = false
            local _diedConn = nil
            local function WatchTarget(tgt)
                if _diedConn then pcall(function() _diedConn:Disconnect() end); _diedConn=nil end
                if not tgt or not tgt.model then return end
                local hum = tgt.model:FindFirstChildOfClass("Humanoid"); if not hum then return end
                _diedConn = hum.Died:Connect(function()
                    _deadG_F[tgt.guid] = true
                    if TA.running then TA.killed = TA.killed + 1 end
                    _curDied = true
                    if TA.cur and TA.cur.guid == tgt.guid then TA.cur = nil end
                end)
            end
            while TA.running do
                local pool = FindAllByNameF(targetName)
                if #pool == 0 then
                    if onStatus then onStatus("WAITING ["..targetName.."] respawn...") end
                    while TA.running do
                        task.wait(0.1)
                        pool = FindAllByNameF(targetName)
                        if #pool > 0 then break end
                    end
                    if not TA.running then break end
                    _deadG_F={}; rrIdx=1; _curDied=false
                end
                if rrIdx > #pool then rrIdx = 1 end
                local tgt = pool[rrIdx]
                if not tgt or IsDeadF(tgt) then
                    rrIdx = rrIdx + 1
                    task.wait(0.1)
                else
                    TA.cur   = tgt
                    _curDied = false
                    TpToF(tgt); FreezePlayer()
                    WatchTarget(tgt)
                    while TA.running and not _curDied and not IsDeadF(tgt) and tgt.model.Parent do
                        -- [v27] GASS terus tanpa jeda
                        ReassertFreeze()
                        FCharF(tgt.guid, tgt.hrp)
                        if onStatus then
                            onStatus(">> ["..targetName.."] ["..rrIdx.."/"..#pool.."] Kill: "..TA.killed)
                        end
                        task.wait()
                    end
                    StopClickSpamF(tgt.guid)
                    StopHeroAtkThreadFor(tgt.guid)
                    if TA.running then
                        rrIdx    = rrIdx + 1
                        _curDied = false
                    end
                end
            end
            if _diedConn then pcall(function() _diedConn:Disconnect() end) end
        end)
        TA.threads = {tChar}
    end

    -- =========================================================================
    --  ENEMY HP MONITOR (WindUI Paragraph + Buttons) 
    -- Source asli baris 6289-6507
    -- WindUI tidak punya custom widget HP bar, jadi kita pakai:
    --   Paragraph untuk display HP + % + rate
    --   Button START / STOP / RESET stopwatch
    -- =========================================================================
    do
        local _ehpLastEnemyId = nil
        local _ehpMaxHp       = 0
        local _ehpConn        = nil
        local _ehpStartPct    = nil
        local _ehpCurPct      = 0

        local _swRunning    = false
        local _swStartTick  = nil
        local _swAccum      = 0
        local _swTimerConn  = nil

        local function FmtHp(n)
            if not n or n <= 0 then return "0" end
            if n < 1e4 then return tostring(math.floor(n)) end
            local exp  = math.floor(math.log10(n))
            local mant = n / (10 ^ exp)
            return string.format("%.2fE+%02d", mant, exp)
        end
        local function FmtTime(secs)
            local s = math.floor(secs)
            return string.format("%02d:%02d", math.floor(s/60), s%60)
        end
        local function HpColor(pct)
            if pct > 50 then return ""
            elseif pct > 25 then return ""
            else return "" end
        end

        local _ehpPara   = nil
        local _timerPara = nil
        local _ratePara  = nil

        local function SwGetElapsed()
            if _swRunning and _swStartTick then
                return _swAccum + (tick() - _swStartTick)
            end
            return _swAccum
        end

        local function SwUpdateDisplay()
            local elapsed = SwGetElapsed()
            if _timerPara then
                pcall(function()
                    _timerPara:SetDesc(" " .. FmtTime(elapsed) .. (_swRunning and " [RUNNING]" or " [PAUSED]"))
                end)
            end
            if _ratePara and _ehpStartPct and elapsed > 2 then
                local pctDone = _ehpStartPct - _ehpCurPct
                if pctDone > 0.01 then
                    pcall(function() _ratePara:SetDesc("1% setiap ~" .. FmtTime(elapsed / pctDone)) end)
                end
            end
        end

        FarmTab:Section({ Title = " ENEMY HP MONITOR", Icon = "heart-pulse" })

        _ehpPara = FarmTab:Paragraph({ Title = "HP", Desc = " / " })
        _timerPara = FarmTab:Paragraph({ Title = "Stopwatch", Desc = " 00:00 [STOPPED]" })
        _ratePara  = FarmTab:Paragraph({ Title = "Rate", Desc = "1% setiap ~--:--" })

        FarmTab:Button({
            Title    = " START Stopwatch",
            Desc     = "Mulai / lanjut hitung waktu",
            Callback = function()
                if _swRunning then return end
                _swRunning   = true
                _swStartTick = tick()
                if _ehpStartPct == nil then _ehpStartPct = _ehpCurPct end
                if not _swTimerConn then
                    local _swLastUpdate = 0
                    _swTimerConn = RunService.Heartbeat:Connect(function()
                        local now = tick()
                        if (now - _swLastUpdate) < 0.1 then return end
                        _swLastUpdate = now
                        SwUpdateDisplay()
                    end)
                end
            end,
        })
        FarmTab:Button({
            Title    = " STOP Stopwatch",
            Desc     = "Pause timer (bisa dilanjut)",
            Callback = function()
                if not _swRunning then return end
                _swAccum     = SwGetElapsed()
                _swRunning   = false
                _swStartTick = nil
                if _swTimerConn then
                    pcall(function() _swTimerConn:Disconnect() end)
                    _swTimerConn = nil
                end
                SwUpdateDisplay()
            end,
        })
        FarmTab:Button({
            Title    = " RESET Stopwatch",
            Desc     = "Reset timer ke 00:00",
            Callback = function()
                _swAccum     = 0
                _swRunning   = false
                _swStartTick = nil
                _ehpStartPct = nil
                if _swTimerConn then
                    pcall(function() _swTimerConn:Disconnect() end)
                    _swTimerConn = nil
                end
                if _timerPara then pcall(function() _timerPara:SetDesc(" 00:00 [STOPPED]") end) end
                if _ratePara   then pcall(function() _ratePara:SetDesc("1% setiap ~--:--") end) end
            end,
        })

        -- Pasang listener HP dari ShowEnemyTakeDamageInfo
        pcall(function()
            local RS  = game:GetService("ReplicatedStorage")
            local rem = RS:FindFirstChild("Remotes")
                     and RS.Remotes:FindFirstChild("ShowEnemyTakeDamageInfo")
            if rem then
                _ehpConn = rem.OnClientEvent:Connect(function(data)
                    if type(data) ~= "table" then return end
                    pcall(function()
                        local eid = tostring(data.enemyId or "")
                        local hp  = tonumber(data.hp)    or 0
                        local mhp = tonumber(data.maxHp) or 0
                        if eid ~= "" and eid ~= _ehpLastEnemyId then
                            _ehpLastEnemyId = eid
                            _ehpMaxHp       = mhp
                        end
                        if mhp > 0 and mhp > _ehpMaxHp then _ehpMaxHp = mhp end
                        local curMaxHp = (_ehpMaxHp > 0) and _ehpMaxHp or mhp
                        if curMaxHp <= 0 then return end
                        local pct = math.clamp(hp / curMaxHp * 100, 0, 100)
                        _ehpCurPct = pct
                        if _ehpPara then
                            pcall(function()
                                _ehpPara:SetDesc(
                                    HpColor(pct) .. " " .. FmtHp(hp) .. " / " .. FmtHp(curMaxHp)
                                    .. "  (" .. string.format("%.3f%%", pct) .. ")"
                                )
                            end)
                        end
                    end)
                end)
            end
        end)
    end -- end Enemy HP Monitor block

    -- =========================================================================
    --  RANDOM ATTACK (RA) 
    -- Source asli baris 6509-6517
    -- =========================================================================
    FarmTab:Section({ Title = " RANDOM ATTACK", Icon = "sword" })

    local _raToggleElement = FarmTab:Toggle({
        Flag     = "farmRA",
        Title    = "RANDOM ATTACK",
        Desc     = "Auto attack musuh random sampai mati, lalu ganti target",
        Value    = false,
        Callback = function(on)
            _raRunningState = on
            if on then StartRA() else StopRA() end
        end,
    })

    _setRAToggle = function(v)
        _raRunningState = v
        if _raToggleElement then pcall(function() _raToggleElement:Set(v) end) end
    end
    _visRandomAtk = function(v)
        if _raToggleElement then pcall(function() _raToggleElement:Set(v, false) end) end
    end

    -- =========================================================================
    --  SELECT ENEMY / TARGET ATTACK (TA) 
    -- Source asli baris 6519-6783
    --
    -- WindUI tidak punya dynamic scrollable row list, jadi pendekatan:
    --   1. Dropdown Mode (By ID / By Name)   Tab:Dropdown(Multi=false)
    --   2. Button "Refresh Enemies"          Tab:Button()
    --   3. Status Paragraph                  Tab:Paragraph() diupdate realtime
    --   4. Enemy rows disimulasikan via      Tab:Dropdown(Multi=false, Values=list)
    --      Single dropdown terpilih = target TA yang aktif
    --   5. Button "START TARGET ATTACK"      Tab:Button()
    --   6. Button "STOP TARGET ATTACK"       Tab:Button()
    --
    -- Logika identik, hanya UI layer yang beda (row individual  dropdown pilih target)
    -- =========================================================================
    FarmTab:Section({ Title = " TARGET ATTACK", Icon = "crosshair" })

    local _taStatusPara      = FarmTab:Paragraph({ Title = "Status TA", Desc = "Idle" })

    -- Mode dropdown: By ID / By Name
    local _listMode = "id"
    FarmTab:Dropdown({
        Flag     = "farmTAMode",
        Title    = "Mode Select",
        Desc     = "By ID = target individu | By Name = musuh yang sama",
        Values   = {"By ID", "By Name"},
        Value    = "By ID",
        Multi    = false,
        Callback = function(val)
            local v = type(val)=="string" and val or nil
            if v == "By Name" then _listMode = "name"
            else _listMode = "id" end
        end,
    })

    -- Enemy dropdown  di-rebuild setiap klik Refresh Enemies
    local _enemyDropValues   = {}
    local _enemyDropSelected = nil
    local _enemyDropElement  = nil
    local _enemyDataById     = {}
    local _enemyDataByName   = {}

    _enemyDropElement = FarmTab:Dropdown({
        -- Flag tidak dipasang: list ini di-rebuild dinamis tiap REFRESH ENEMIES,
        -- nilai yang disimpan tidak bermakna lintas sesi (GUID enemy berubah).
        Title    = "Pilih Enemy",
        Desc     = "Klik REFRESH ENEMIES untuk load daftar musuh",
        Values   = {},
        Value    = nil,
        Multi    = false,
        Callback = function(val)
            _enemyDropSelected = type(val)=="string" and val or nil

            -- Auto-switch target jika TA sedang running  tidak perlu OFF/ON lagi
            if not _enemyDropSelected then return end
            if not TA.running then return end

            -- Stop TA lama
            StopTA()

            -- Start TA ke target baru sesuai mode
            if _listMode == "id" then
                local data = _enemyDataById[_enemyDropSelected]
                if not data then
                    if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Enemy tidak valid, Refresh dulu") end) end
                    -- Toggle kembali ke OFF karena target tidak valid
                    if _taToggleElement then pcall(function() _taToggleElement:Set(false, false) end) end
                    return
                end
                StartTA_ByID(data.guid, data.name,
                    function(msg)
                        if _taStatusPara then pcall(function() _taStatusPara:SetDesc(msg) end) end
                    end,
                    _taOnStop
                )
            else
                local data = _enemyDataByName[_enemyDropSelected]
                if not data then
                    if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Enemy tidak valid, Refresh dulu") end) end
                    if _taToggleElement then pcall(function() _taToggleElement:Set(false, false) end) end
                    return
                end
                StartTA_ByName(data.nm,
                    function(msg)
                        if _taStatusPara then pcall(function() _taStatusPara:SetDesc(msg) end) end
                    end,
                    _taOnStop
                )
            end
        end,
    })

    -- Refresh Enemies  scan workspace + rebuild dropdown sekaligus (soal 7 & 8)
    FarmTab:Button({
        Title    = " REFRESH ENEMIES",
        Desc     = "Scan & isi dropdown dengan musuh hidup beserta ID-nya",
        Callback = function()
            -- Stop TA dulu jika sedang running
            if TA.running then
                StopTA()
                if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Stopped (Refresh)") end) end
            end
            _enemyDataById   = {}
            _enemyDataByName = {}
            _enemyDropValues = {}
            _enemyDropSelected = nil

            local enemies = GetEnemiesF()
            if #enemies == 0 then
                if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Map kosong  tidak ada musuh") end) end
                if _enemyDropElement then pcall(function() _enemyDropElement:Set({}) end) end
                return
            end

            if _listMode == "id" then
                table.sort(enemies, function(a,b) return a.name < b.name end)
                for _, e in ipairs(enemies) do
                    local label = e.name .. " [" .. e.guid:sub(1,8) .. "]"
                    table.insert(_enemyDropValues, label)
                    _enemyDataById[label] = {guid=e.guid, name=e.name}
                end
                if _taStatusPara then
                    pcall(function() _taStatusPara:SetDesc(#enemies .. " musuh (By ID)  pilih dari dropdown") end)
                end
            else
                local nc = {}
                for _, e in ipairs(enemies) do nc[e.name]=(nc[e.name] or 0)+1 end
                local names = {}
                for nm in pairs(nc) do table.insert(names, nm) end
                table.sort(names)
                for _, nm in ipairs(names) do
                    local label = nm .. " x" .. nc[nm]
                    table.insert(_enemyDropValues, label)
                    _enemyDataByName[label] = {nm=nm}
                end
                if _taStatusPara then
                    pcall(function() _taStatusPara:SetDesc(#names .. " jenis, " .. #enemies .. " total (By Name)") end)
                end
            end

            -- Rebuild dropdown dengan data baru
            if _enemyDropElement then
                pcall(function() _enemyDropElement:Refresh(_enemyDropValues, nil) end)
                -- Fallback jika Refresh tidak tersedia di versi WindUI ini
                pcall(function()
                    _enemyDropElement.Values = _enemyDropValues
                end)
            end
        end,
    })

    -- TARGET ATTACK Toggle (ON = START, OFF = STOP)  soal 9
    local _taToggleElement = nil
    local function _taOnStop()
        if _taToggleElement then
            pcall(function() _taToggleElement:Set(false, false) end)
        end
        if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Target mati  pilih enemy baru & ON lagi") end) end
    end

    _taToggleElement = FarmTab:Toggle({
        Flag     = "farmTA",
        Title    = "TARGET ATTACK",
        Desc     = "ON = mulai serang target terpilih | OFF = stop",
        Value    = false,
        Callback = function(on)
            if on then
                if not _enemyDropSelected then
                    if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Pilih enemy dulu dari dropdown!") end) end
                    task.defer(function()
                        if _taToggleElement then
                            pcall(function() _taToggleElement:Set(false, false) end)
                        end
                    end)
                    return
                end
                if TA.running then StopTA() end

                if _listMode == "id" then
                    local data = _enemyDataById[_enemyDropSelected]
                    if not data then
                        if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Enemy tidak valid, Refresh dulu") end) end
                        task.defer(function()
                            if _taToggleElement then pcall(function() _taToggleElement:Set(false, false) end) end
                        end)
                        return
                    end
                    StartTA_ByID(data.guid, data.name,
                        function(msg)
                            if _taStatusPara then pcall(function() _taStatusPara:SetDesc(msg) end) end
                        end,
                        _taOnStop
                    )
                else
                    local data = _enemyDataByName[_enemyDropSelected]
                    if not data then
                        if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Enemy tidak valid, Refresh dulu") end) end
                        task.defer(function()
                            if _taToggleElement then pcall(function() _taToggleElement:Set(false, false) end) end
                        end)
                        return
                    end
                    StartTA_ByName(data.nm,
                        function(msg)
                            if _taStatusPara then pcall(function() _taStatusPara:SetDesc(msg) end) end
                        end,
                        _taOnStop
                    )
                end
            else
                StopTA()
                if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Stop") end) end
            end
        end,
    })

    -- ════════════════════════════════════════════════════════════════════════
    --  SECTION: FAST ATTACK 1 ENEMYS
    --  Duplikat salah satu musuh secara RANDOM dari workspace.Enemys.
    --  Clone disimpan di workspace.Enemys selama toggle ON.
    --  Ketika OFF → clone dihapus, koneksi dibersihkan.
    --
    --  Strategi:
    --    1. Ambil anak pertama workspace.Enemys yang valid (Model + HumanoidRootPart)
    --    2. Clone model tersebut
    --    3. Set EnemyGuid baru agar tidak bentrok dengan enemy asli
    --    4. Parent ke workspace.Enemys
    --    5. Heartbeat: jika enemy asli mati → pilih ulang (respawn) clone baru
    --    6. OFF → hapus clone + disconnect Heartbeat
    -- ════════════════════════════════════════════════════════════════════════
    FarmTab:Section({ Title = " FAST ATTACK 1 ENEMYS", Icon = "zap" })

    local _dupePara = FarmTab:Paragraph({
        Title = "Status",
        Desc  = "Idle",
    })

    -- State FAST ATTACK 1 ENEMYS
    local _dupeOn        = false
    local _dupeClone     = nil   -- referensi clone aktif
    local _dupeConn      = nil   -- Heartbeat connection (GET: monitor & respawn clone)

    -- State START (spawn di depan Player + face-lock ke Player)
    local _spawnOn          = false
    local _spawnConn        = nil  -- Heartbeat connection (START: hadapkan clone ke Player)
    local _spawnFixedCFrame = nil  -- posisi tetap hasil spawn, tidak ikut player setelah itu

    -- Config jarak spawn di depan Player
    local _SPAWN_DISTANCE = 8 -- studs di depan player

    -- Helper: set desc paragraph
    local function _dupeStatus(msg)
        if _dupePara then pcall(function() _dupePara:SetDesc(msg) end) end
    end

    -- GUID attrs yang mungkin dipakai game
    local _GUID_ATTRS = {"EnemyGuid","BossGuid","Guid","GUID"}

    -- Helper: baca GUID dari model (return attrName, value)
    local function _getGuid(model)
        for _, attr in ipairs(_GUID_ATTRS) do
            local v = model:GetAttribute(attr)
            if v then return attr, v end
        end
        return nil, nil
    end

    -- Helper: ambil random enemy valid dari workspace.Enemys (skip clone sendiri by GUID)
    local function _getRandomEnemy()
        local folder = workspace:FindFirstChild("Enemys")
        if not folder then return nil end

        -- GUID clone aktif untuk di-skip
        local cloneGuid = nil
        if _dupeClone then
            local _, g = _getGuid(_dupeClone)
            cloneGuid = g
        end

        local valid = {}
        for _, e in ipairs(folder:GetChildren()) do
            if e:IsA("Model") and e ~= _dupeClone then
                local _, g = _getGuid(e)
                if g and g ~= cloneGuid then
                    local hrp = e:FindFirstChild("HumanoidRootPart")
                             or e.PrimaryPart
                             or e:FindFirstChildWhichIsA("BasePart")
                    local hum = e:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        table.insert(valid, {model=e, guid=g, hrp=hrp})
                    end
                end
            end
        end
        if #valid == 0 then return nil end
        return valid[math.random(1, #valid)]
    end

    -- Helper: spawn clone dari model enemy sumber
    -- GUID dipakai ASLI persis dari enemy sumber (Clone() sudah copy semua Attributes)
    -- Posisi PERSIS sama (tidak di-offset) -- identik Ctrl+D / Duplicate manual di Studio
    local function _spawnClone(srcData)
        if _dupeClone then
            pcall(function() _dupeClone:Destroy() end)
            _dupeClone = nil
        end

        local src = srcData.model
        local ok, clone = pcall(function() return src:Clone() end)
        if not ok or not clone then return nil end

        -- Clone() sudah menyalin SEMUA Attributes (termasuk EnemyGuid, BossGuid, dll)
        -- dan posisi HumanoidRootPart persis sama dengan enemy asli
        -- Tidak perlu override apapun -- identik dengan Duplicate manual

        clone.Parent = workspace:FindFirstChild("Enemys")
        _dupeClone   = clone
        return clone
    end

    -- Helper: stop SPAWN (bersihkan face-lock conn + posisi tetap, TIDAK menghapus clone)
    local function _stopSpawnFacing()
        if _spawnConn then
            pcall(function() _spawnConn:Disconnect() end)
            _spawnConn = nil
        end
        _spawnOn = false
        _spawnFixedCFrame = nil
    end

    -- Helper: stop DUPE (bersihkan clone + conn + spawn state)
    local function _stopDupe()
        if _dupeConn then
            pcall(function() _dupeConn:Disconnect() end)
            _dupeConn = nil
        end
        _stopSpawnFacing()
        if _dupeClone then
            pcall(function() _dupeClone:Destroy() end)
            _dupeClone = nil
        end
        _dupeOn = false
        _dupeStatus("Idle")
    end

    -- Helper: mulai DUPE loop via Heartbeat
    local function _startDupe()
        -- pilih enemy awal
        local srcData = _getRandomEnemy()
        if not srcData then
            _dupeStatus("[!] Tidak ada enemy di workspace.Enemys")
            _dupeOn = false
            return
        end

        -- spawn clone pertama
        _spawnClone(srcData)
        _dupeStatus("SUCCESS - Random Attack First")

        -- Heartbeat: monitor clone; respawn jika mati/hilang
        local _dupeHbThrottle = 0
        _dupeConn = RunService.Heartbeat:Connect(function(dt)
            if not _dupeOn then return end

            -- throttle: cek setiap ~0.5s saja, tidak perlu tiap frame
            _dupeHbThrottle = _dupeHbThrottle + dt
            if _dupeHbThrottle < 0.5 then return end
            _dupeHbThrottle = 0

            local cloneAlive = false
            pcall(function()
                if _dupeClone and _dupeClone.Parent then
                    local hum = _dupeClone:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        cloneAlive = true
                    end
                end
            end)

            if not cloneAlive then
                -- clone mati/hilang → pilih enemy baru dan spawn clone baru
                local newData = _getRandomEnemy()
                if newData then
                    _spawnClone(newData)
                    _dupeStatus("SUCCESS - Select Enemy Target")
                else
                    _dupeStatus("SUCCESS - Attack Target Enemy")
                end
            end
        end)
    end

    -- Helper: mulai SPAWN (posisikan clone di depan Player, sekali, lalu clone terus
    -- menghadap ke Player kemanapun Player berjalan. Posisi TIDAK ikut Player.)
    local function _startSpawn()
        if not _dupeClone or not _dupeClone.Parent then
            _dupeStatus("[!] Belum ada clone. Tekan GET dahulu")
            return
        end

        local char = LP.Character
        local pHRP = char and char:FindFirstChild("HumanoidRootPart")
        if not pHRP then
            _dupeStatus("[!] Character/HumanoidRootPart Player tidak ditemukan")
            return
        end

        local cloneHRP = _dupeClone:FindFirstChild("HumanoidRootPart")
                       or _dupeClone.PrimaryPart
                       or _dupeClone:FindFirstChildWhichIsA("BasePart")
        if not cloneHRP then
            _dupeStatus("[!] Clone tidak punya bagian tubuh valid")
            return
        end

        -- hentikan facing-loop lama (jika START ditekan ulang) sebelum reposisi
        _stopSpawnFacing()

        -- hitung posisi tetap: beberapa studs di depan Player, hadap ke Player
        local pCFrame   = pHRP.CFrame
        local spawnPos  = pCFrame.Position + (pCFrame.LookVector * _SPAWN_DISTANCE)
        local faceToPlr = CFrame.lookAt(spawnPos, Vector3.new(pHRP.Position.X, spawnPos.Y, pHRP.Position.Z))
        _spawnFixedCFrame = faceToPlr

        pcall(function()
            if _dupeClone.PrimaryPart then
                _dupeClone:SetPrimaryPartCFrame(_spawnFixedCFrame)
            else
                _dupeClone:PivotTo(_spawnFixedCFrame)
            end
        end)

        _spawnOn = true
        _dupeStatus("SUCCESS - Enemy Spawned In Front Of Player")

        -- Heartbeat: posisi tetap diam di _spawnFixedCFrame, tapi rotasi selalu
        -- menghadap ke Player kemanapun Player berjalan (posisi X/Z/Y clone tidak berubah)
        _spawnConn = RunService.Heartbeat:Connect(function()
            if not _spawnOn then return end
            if not _dupeClone or not _dupeClone.Parent then
                _stopSpawnFacing()
                return
            end

            local pChar = LP.Character
            local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
            local cRoot = _dupeClone:FindFirstChild("HumanoidRootPart")
                        or _dupeClone.PrimaryPart
                        or _dupeClone:FindFirstChildWhichIsA("BasePart")
            if not pRoot or not cRoot or not _spawnFixedCFrame then return end

            local fixedPos = _spawnFixedCFrame.Position
            local lookCF   = CFrame.lookAt(fixedPos, Vector3.new(pRoot.Position.X, fixedPos.Y, pRoot.Position.Z))

            pcall(function()
                if _dupeClone.PrimaryPart then
                    _dupeClone:SetPrimaryPartCFrame(lookCF)
                else
                    _dupeClone:PivotTo(lookCF)
                end
            end)
        end)
    end

    -- Helper: STOP -> hapus clone (musuh duplikat) + hapus posisi spawn (reset semua state)
    local function _stopSpawn()
        _stopDupe()
        _dupeStatus("Idle")
    end

    -- Button GET (logika identik dengan toggle lama: pilih random enemy, clone,
    -- auto-respawn via Heartbeat jika clone mati)
    FarmTab:Button({
        Title    = "GET",
        Desc     = "START FIRST",
        Callback = function()
            -- restart bersih setiap kali GET ditekan
            if _dupeConn then
                pcall(function() _dupeConn:Disconnect() end)
                _dupeConn = nil
            end
            _stopSpawnFacing()
            if _dupeClone then
                pcall(function() _dupeClone:Destroy() end)
                _dupeClone = nil
            end
            _dupeOn = true
            BlockEnemyHitAnim(true)
            _startDupe()
        end,
    })

    -- Button START (spawn clone hasil GET di depan Player, posisi tetap, hadap ke Player)
    FarmTab:Button({
        Title    = "START",
        Desc     = "CLICK",
        Callback = function()
            _startSpawn()
        end,
    })

    -- Button STOP (hapus clone + hapus posisi spawn)
    FarmTab:Button({
        Title    = "STOP",
        Desc     = "Delete",
        Callback = function()
            _stopSpawn()
            if not RA.running and not TA.running then
                BlockEnemyHitAnim(false)
            end
        end,
    })

end -- end do PANEL: FARM


-- ============================================================================
-- PANEL: MASS ATTACK
-- Dipindah dari 1.lua baris ~6785 (PANEL: ATTACK)
-- Ditulis ulang pakai WindUI native API
-- Perbedaan API vs source asli:
--   Source asli: NewPanel("attack") + MakeSimpleDD custom + ToggleRow custom
--   WindUI:      MassAttackTab:Section() + MassAttackTab:Paragraph() +
--                MassAttackTab:Dropdown() + MassAttackTab:Toggle()
-- Gold-collector (StartDestroyWorker/StartGoldMagnet) TIDAK dimasukkan di sini
-- -> sudah ada di PANEL: MAIN
-- Global expose:
--   _setMaToggleGlobal, _setKillDDGlobal, _setDelayDDGlobal
--   _visMassAtk, _killDDIdxState, _delayDDIdxState
--   _maStatusPara (Paragraph widget untuk status)
--   _maMapSelState, _maMapItemRefs, _maUpdateMapDDLbl
-- Logika bisnis:
--   MA, MR, SKL, MAPS, FLa_PressKey (inline), MODE, _deadG, ORIGIN_POS
--   TpMap, GetEnemies, IsDead, SaveOrigin, ReturnHRPToOrigin
--   IsEnemyGuidValid, EnsureHeroAtkThreadFor (shared dengan FARM)
--   FireAllDamage, FireHeroRemotes, AttackLoop_Mass
--   WaitRaidDone, DoMassAttack
-- ============================================================================
do
    --  Global state (dibaca Config panel saat save/load) 
    -- Identik dengan deklarasi 1.lua baris ~1519, ~1792-1803
    MA = MA or {running=false, thread=nil, killed=0, killTarget=7, autoCollect=true}

    _killDDIdxState  = _killDDIdxState  or 1
    _delayDDIdxState = _delayDDIdxState or 2

    _setMaToggleGlobal = nil
    _setKillDDGlobal   = nil
    _setDelayDDGlobal  = nil
    _visMassAtk        = nil
    _maMapSelState     = nil
    _maMapItemRefs     = nil
    _maUpdateMapDDLbl  = nil
    _maStatusPara      = nil  -- WindUI Paragraph widget (ganti _maStatusLbl)

    --  MODE priority system (identik 1.lua baris ~1828) 
    if not MODE then
        MODE = {
            current  = "idle",
            priority = {siege=5, raid=4, asc=3, st2=2, ma=1, idle=0},
            _prev    = {},
        }
        function MODE:_p(name) return self.priority[name] or 0 end
        function MODE:IsHigherPriority(incoming) return self:_p(incoming) > self:_p(self.current) end
        function MODE:Request(name)
            if self.current == "idle" or self:IsHigherPriority(name) then
                self.current = name; return true
            end
            return false
        end
        function MODE:Release(name) if self.current == name then self.current = "idle" end end
        function MODE:ForceSet(name) self.current = name end
        function MODE:WaitAndRequest(name, timeout)
            local t = 0; local limit = timeout or 30
            while not self:Request(name) and t < limit do task.wait(0.5); t = t + 0.5 end
            return self.current == name
        end
    end

    --  Interrupt flags (identik 1.lua baris ~2000-2003) 
    if _raidInterrupt  == nil then _raidInterrupt  = false end
    if _ascInterrupt   == nil then _ascInterrupt   = false end
    if _siegeInterrupt == nil then _siegeInterrupt = false end

    --  Atomic map-enter lock (identik 1.lua baris ~1895) 
    if _MAP_ENTER_LOCK == nil then _MAP_ENTER_LOCK = nil end
    if _MAP_ENTER_LOCK_TIME == nil then _MAP_ENTER_LOCK_TIME = 0 end

    --  IsAnyMapActive (identik 1.lua baris ~1916) 
    if not IsAnyMapActive then
        function IsAnyMapActive()
            if RAID   and RAID.inMap            then return true, "raid"    end
            if ASC    and ASC.inMap             then return true, "asc"     end
            if SIEGE  and SIEGE.inMap           then return true, "siege"   end
            if ST2    and ST2.inMap             then return true, "st2"     end
            if _MAP_ENTER_LOCK ~= nil           then return true, _MAP_ENTER_LOCK end
            return false, nil
        end
    end

    --  MAPS + MR (identik 1.lua baris ~2021-2025) 
    local MAPS = {}
    for i = 1, 20 do
        MAPS[i] = {name="Map "..i, id=50000+i, remote=i<=4 and "Start" or "Local"}
    end
    MR = MR or {selected={}, nextMapDelay=3, teleportDelay=3}

    --  TpMap (identik 1.lua baris ~2027) 
    if not TpMap then
        function TpMap(m)
            MR.lastMapId = m.id
            if m.remote == "Start" then
                pcall(function() RE.StartTp:FireServer({mapId=m.id}) end)
            else
                pcall(function() RE.LocalTp:FireServer({mapId=m.id}) end)
            end
        end
    end

    --  FLa_PressKey inline (identik 1.lua baris ~244, tanpa compat-layer besar)
    -- Diperlukan oleh SKL / SkFireOnce
    if not FLa_PressKey then
        function FLa_PressKey(keyCode)
            -- Method 1: VirtualInputManager
            local ok1 = pcall(function()
                local VIM = game:GetService("VirtualInputManager")
                VIM:SendKeyEvent(true,  keyCode, false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, keyCode, false, game)
            end)
            if ok1 then return true end
            -- Method 2: UIS fire (mobile-friendly fallback)
            local ok3 = pcall(function()
                local UIS = game:GetService("UserInputService")
                local io  = Instance.new("InputObject")
                io.KeyCode       = keyCode
                io.UserInputType = Enum.UserInputType.Keyboard
                io.UserInputState = Enum.UserInputState.Begin
                UIS.InputBegan:Fire(io, false)
                task.wait(0.05)
                io.UserInputState = Enum.UserInputState.End
                UIS.InputEnded:Fire(io, false)
            end)
            if ok3 then return true end
            return false
        end
    end

    --  SKL (identik 1.lua baris ~2037) 
    if not SKL then
        SKL = {
            Z={on=false,t=nil,label="Z"},
            X={on=false,t=nil,label="X"},
            C={on=false,t=nil,label="C"},
            V={on=false,t=nil,label="V"},
            F={on=false,t=nil,label="F"},
            type_map = {Z=1,X=2,C=3,V=4,F=5},
            key_map  = {Z=Enum.KeyCode.Z,X=Enum.KeyCode.X,C=Enum.KeyCode.C,V=Enum.KeyCode.V,F=Enum.KeyCode.F},
            ui = {},
        }
    end

    local function PK(k) FLa_PressKey(k) end

    if not SkFireOnce then
        function SkFireOnce(n) PK(SKL.key_map[n]) end
    end

    if not SkSetUI then
        function SkSetUI(n, on)
            local u = SKL.ui[n]; if not u then return end
            u.btn.BackgroundColor3 = on and Color3.fromRGB(180,65,5) or Color3.fromRGB(30,30,30)
            u.lbl.Text = on and "ON" or "OFF"
            u.lbl.TextColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(180,180,180)
            local stk = u.btn:FindFirstChildWhichIsA("UIStroke")
            if stk then
                stk.Color       = on and Color3.fromRGB(255,200,50) or Color3.fromRGB(80,80,80)
                stk.Transparency = on and 0 or 0.3
            end
        end
    end

    if not SkOn then
        function SkOn(n)
            local s = SKL[n]; if s.t then return end
            s.on = true; SkSetUI(n, true)
            s.t = task.spawn(function()
                while s.on do SkFireOnce(n); task.wait(0.8) end
                s.t = nil
            end)
        end
    end

    if not SkOff then
        function SkOff(n)
            local s = SKL[n]; s.on = false; SkSetUI(n, false)
            if s.t then pcall(function() task.cancel(s.t) end); s.t = nil end
        end
    end

    -- Keyboard listener Z/X/C/V/F toggle (identik 1.lua baris ~2108)
    if not _sklKeyListenerBound then
        _sklKeyListenerBound = true
        game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local keyMap = {
                [Enum.KeyCode.Z]="Z", [Enum.KeyCode.X]="X",
                [Enum.KeyCode.C]="C", [Enum.KeyCode.V]="V", [Enum.KeyCode.F]="F",
            }
            local n = keyMap[input.KeyCode]; if not n then return end
            if SKL[n].on then SkOff(n) else SkOn(n) end
        end)
    end

    --  _deadG + SaveOrigin + ReturnHRPToOrigin (identik 1.lua baris ~2161)
    local _deadG = {}
    local ORIGIN_POS = Vector3.new(0, 0, 0)

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

    --  IsEnemyGuidValid (identik 1.lua baris ~2195) 
    local function IsEnemyGuidValid(g)
        if not g then return false end
        local ENEMY_FOLDERS = {"Enemys","EnemyCityRaid","CityRaidEnemys","Enemies","Enemy"}
        for _, folderName in ipairs(ENEMY_FOLDERS) do
            local f = workspace:FindFirstChild(folderName)
            if f then
                for _, e in ipairs(f:GetChildren()) do
                    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
                        local hrp = e:FindFirstChild("HumanoidRootPart")
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        if hrp and hum and hum.Health > 0 then return true end
                        return false
                    end
                end
            end
        end
        pcall(function()
            local mapF = workspace:FindFirstChild("Map")
            local cre  = mapF and mapF:FindFirstChild("CityRaidEnter")
            if cre then
                for _, e in ipairs(cre:GetDescendants()) do
                    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
                        local hrp = e:FindFirstChild("HumanoidRootPart")
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        if hrp and hum and hum.Health > 0 then return true end
                    end
                end
            end
        end)
        return false
    end

    --  EnsureHeroAtkThreadFor per-GUID (identik 1.lua baris ~2224)
    -- Shared dengan FARM (jika sudah ada tidak buat ulang)
    local _heroAtkThreads_MA = {}
    local function EnsureHeroAtkThreadFor_MA(g)
        if not g then return end
        if _heroAtkThreads_MA[g] and _heroAtkThreads_MA[g].running then return end
        local handle = {running=true, tick=0}
        _heroAtkThreads_MA[g] = handle
        task.spawn(function()
            local _lastFire = {}
            while handle.running and ScreenGui and ScreenGui.Parent do
                if #HERO_GUIDS > 0 and (tick()-handle.tick) >= 0.5 and IsEnemyGuidValid(g) then
                    handle.tick = tick()
                    for _, hGuid in ipairs(HERO_GUIDS) do
                        local last = _lastFire[hGuid] or 0
                        if (tick()-last) >= 1.0 then  -- [EDIT] interval per hero 1 detik
                            _lastFire[hGuid] = tick()
                            if RE.HeroUseSkill then
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                                PG_Wait(0.1)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=2,userId=MY_USER_ID,enemyGuid=g}) end)
                                PG_Wait(0.1)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=3,userId=MY_USER_ID,enemyGuid=g}) end)
                            end
                        end
                        PG_Wait(0.05)
                    end
                end
                PG_Wait(0.05)
                if not IsEnemyGuidValid(g) then
                    handle.running = false
                end
            end
            _heroAtkThreads_MA[g] = nil
        end)
    end

    --  GetEnemies (identik 1.lua baris ~2119) 
    local function GetEnemies()
        local list = {}
        local _curMap = pcall(function()
            return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
        end)
        do
            local ok, wm = pcall(function()
                return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
            end)
            if ok and type(wm) == "number" then
                local _inRaid    = wm >= 50101 and wm <= 50120
                local _inAsc     = wm >= 50301 and wm <= 50326
                local _inSiege   = wm >= 50201 and wm <= 50204
                local _inAnniv   = wm == 50401
                if _inRaid or _inAsc or _inSiege or _inAnniv then
                    return list
                end
            end
        end
        local ENEMY_FOLDERS = {"Enemys","EnemyCityRaid","CityRaidEnemys","Enemies","Enemy"}
        local seen = {}
        local MA_ATTACK_RADIUS = 2000
        local _lp = game:GetService("Players").LocalPlayer
        local _playerPos = nil
        if _lp and _lp.Character then
            local _hrp = _lp.Character:FindFirstChild("HumanoidRootPart")
            if _hrp then _playerPos = _hrp.Position end
        end
        local function _addEnemy(e)
            if not e:IsA("Model") then return end
            local g   = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid") or e:GetAttribute("Guid") or e:GetAttribute("GUID")
            local h   = e:FindFirstChild("HumanoidRootPart")
            local hum = e:FindFirstChildOfClass("Humanoid")
            if g and h and hum and hum.Health > 0 and not seen[g] then
                -- Filter radius 2000 studs dari posisi player
                if _playerPos and (h.Position - _playerPos).Magnitude > MA_ATTACK_RADIUS then return end
                seen[g] = true
                table.insert(list, {model=e, guid=g, hrp=h})
            end
        end
        for _, folderName in ipairs(ENEMY_FOLDERS) do
            local f = workspace:FindFirstChild(folderName)
            if f then for _, e in ipairs(f:GetChildren()) do _addEnemy(e) end end
        end
        if #list == 0 then
            for _, obj in ipairs(workspace:GetChildren()) do _addEnemy(obj) end
        end
        return list
    end

    --  IsDead (identik 1.lua baris ~2155) 
    local function IsDead(e)
        if _deadG[e.guid] then return true end
        if not e.model or not e.model.Parent then return true end
        local h = e.model:FindFirstChildOfClass("Humanoid")
        return not h or h.Health <= 0
    end

    --  FireAllDamage (identik 1.lua baris ~2284, enemyPos dihapus - serang murni via EnemyGUID) 
    local function FireAllDamage(g)
        if not IsEnemyGuidValid(g) then return end
        if RE.Click then
            task.spawn(function()
                pcall(function() RE.Click:InvokeServer({enemyGuid=g}) end)
            end)
        end
        if RE.Atk then
            pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
        end
        EnsureHeroAtkThreadFor_MA(g)
        if not RE.HeroUseSkill and RE.HeroSkill then
            for _, hGuid in ipairs(HERO_GUIDS) do
                pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=1,masterId=MY_USER_ID}) end)
                pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=2,masterId=MY_USER_ID}) end)
                pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=3,masterId=MY_USER_ID}) end)
            end
        end
    end

    --  FireHeroRemotes (identik 1.lua baris ~2313) 
    -- [Hero Static test] Tidak dipanggil lagi dari AttackLoop_Mass (hero diem di tempat).
    -- Fungsi dibiarkan utuh (bukan dihapus) biar gampang direvert kalau hasil test kurang menarik.
    -- [EDIT] HeroMoveToEnemyPos dihapus — tidak dipakai lagi.
    local function FireHeroRemotes(enemyGuid, enemyPos)
    end

    --  RE.Death listener untuk MA.killed (identik 1.lua baris ~2333)
    -- Guard: jangan bind dua kali
    if not _maDeathListenerBound then
        _maDeathListenerBound = true
        if RE.Death then
            RE.Death.OnClientEvent:Connect(function(d)
                if not d then return end
                local g = d.enemyGuid or d.guid
                if g then
                    _deadG[g] = true
                    if MA.running
                        and not (SIEGE  and SIEGE.inMap)
                        and not (RAID   and RAID.inMap)
                        and not (ST2    and ST2.running)
                    then
                        MA.killed = MA.killed + 1
                    end
                end
            end)
        end
    end

    -- =========================================================================
    --  ENEMY PULL WORKER
    --  Heartbeat loop: tarik musuh aktif ke spread di depan player.
    --  Musuh mati → Destroy model (bersihkan mayat).
    --  Spread: baris horizontal di depan player, jarak 3 studs antar musuh,
    --          offset maju 6 studs dari HRP player.
    -- =========================================================================
    local _pullWorkerConn  = nil   -- RBXScriptConnection Heartbeat
    local _pullTargets     = {}    -- array of {model, guid} yang sedang ditarik
    local _pullDestroyedG  = {}    -- set guid yang sudah di-Destroy (jangan proses ulang)

    local function _StopEnemyPullWorker()
        if _pullWorkerConn then
            pcall(function() _pullWorkerConn:Disconnect() end)
            _pullWorkerConn = nil
        end
        _pullTargets    = {}
        _pullDestroyedG = {}
    end

    -- offset: index 1,2,3,... → posisi spread kiri-kanan di depan player
    -- susunan: tengah dulu, lalu selang-seling kiri/kanan
    local function _spreadOffset(idx, total)
        -- Hitung posisi spread horizontal
        -- idx: 1-based, total: jumlah musuh
        local SPACING  = 3.5  -- studs antar musuh
        local FORWARD  = 6    -- studs di depan player
        -- posisi relatif: 0 = tengah, -1 kiri, +1 kanan dst
        local mid = (total + 1) / 2
        local slot = idx - mid  -- float, negatif = kiri, positif = kanan
        return slot * SPACING, FORWARD
    end

    local function _StartEnemyPullWorker(targets)
        _StopEnemyPullWorker()
        _pullTargets    = targets  -- array {model=..., guid=...}
        _pullDestroyedG = {}

        _pullWorkerConn = game:GetService("RunService").Heartbeat:Connect(function()
            local lp   = game:GetService("Players").LocalPlayer
            local char = lp and lp.Character
            local pHRP = char and char:FindFirstChild("HumanoidRootPart")
            if not pHRP then return end

            local cf     = pHRP.CFrame
            local right  = cf.RightVector
            local fwd    = cf.LookVector

            local total  = #_pullTargets
            for i, t in ipairs(_pullTargets) do
                if _pullDestroyedG[t.guid] then continue end

                local model = t.model
                -- Cek musuh mati → Destroy model, bersihkan mayat
                if not model or not model.Parent then
                    _pullDestroyedG[t.guid] = true
                    continue
                end
                local hum = model:FindFirstChildOfClass("Humanoid")
                if not hum or hum.Health <= 0 then
                    _pullDestroyedG[t.guid] = true
                    pcall(function() model:Destroy() end)
                    continue
                end

                -- Hitung posisi target di depan player
                local slotOff, fwdDist = _spreadOffset(i, total)
                local targetPos = pHRP.Position
                    + fwd    * fwdDist
                    + right  * slotOff

                -- Snap HRP musuh ke posisi target
                local eHRP = model:FindFirstChild("HumanoidRootPart")
                if eHRP then
                    pcall(function()
                        eHRP.CFrame = CFrame.new(targetPos, pHRP.Position)
                    end)
                end
            end
        end)
    end

    --  AttackLoop_Mass (identik 1.lua baris ~2491) 
    local function AttackLoop_Mass(onStatus)
        _deadG = {}
        -- FASE 1: Tunggu musuh muncul maks 10 detik
        local wt = 0
        while wt < 10 and MA.running do
            if #GetEnemies() > 0 then break end
            if onStatus then onStatus("Nunggu musuh... ("..math.floor(10-wt).."s)") end
            task.wait(0.4); wt = wt + 0.4
        end
        if not MA.running then _StopEnemyPullWorker(); return false end
        if #GetEnemies() == 0 then
            if onStatus then onStatus("Kosong, skip map...") end
            _StopEnemyPullWorker()
            return true
        end

        -- Tentukan musuh yang akan ditarik sesuai Kill Target
        -- killTarget=0 = Kill All (ambil semua), killTarget=N = ambil N musuh
        local allEnemies = GetEnemies()
        local isAll      = (MA.killTarget == 0)
        local pullCount  = isAll and #allEnemies or math.min(MA.killTarget, #allEnemies)
        local pullList   = {}
        for i = 1, pullCount do
            pullList[i] = { model = allEnemies[i].model, guid = allEnemies[i].guid }
        end

        -- Aktifkan pull worker — musuh di pullList akan di-lock di depan player tiap Heartbeat
        _StartEnemyPullWorker(pullList)

        -- FASE 2: Attack loop
        local start    = MA.killed
        local lastKill = MA.killed
        local stuckT   = 0
        local STUCK_LIMIT = 5.0

        while MA.running do
            -- Guard IsAnyMapActive
            do
                local _mBusy, _mWho = IsAnyMapActive()
                if _mBusy then _StopEnemyPullWorker(); return "interrupted" end
            end
            -- Guard interrupt flags lama (kompatibilitas)
            do local _ni=(MODE.current~="idle" and MODE.current~="ma") or _raidInterrupt or _siegeInterrupt or (ST2 and ST2.running) or (SIEGE and SIEGE.inMap); if _ni then _StopEnemyPullWorker(); return "interrupted" end end
            -- Guard: hanya serang di basemap 50001-50020
            do
                local ok, wm = pcall(function()
                    return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
                end)
                if ok and type(wm) == "number" then
                    if wm < 50001 or wm > 50020 then _StopEnemyPullWorker(); return "interrupted" end
                end
            end

            local here  = MA.killed - start

            -- Hitung musuh hidup dari pullList (bukan GetEnemies() — hanya yang ditarik)
            local alive = 0
            for _, t in ipairs(pullList) do
                if not _pullDestroyedG[t.guid] then
                    local model = t.model
                    if model and model.Parent then
                        local hum = model:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then alive = alive + 1 end
                    end
                end
            end

            -- Kondisi keluar A: semua musuh di pullList habis
            if alive == 0 then
                if onStatus then onStatus("[OK] Semua musuh habis!") end
                _StopEnemyPullWorker()
                return true
            end
            -- Kondisi keluar B: kill target terpenuhi
            if not isAll and here >= MA.killTarget then
                if onStatus then onStatus("[OK] Target "..MA.killTarget.." tercapai!") end
                _StopEnemyPullWorker()
                return true
            end

            -- Update status
            if isAll then
                if onStatus then onStatus("Kill All: "..alive.." sisa") end
            else
                if onStatus then onStatus(alive.." hidup | "..here.."/"..MA.killTarget) end
            end

            -- Stuck check
            if MA.killed > lastKill then
                lastKill = MA.killed; stuckT = 0
            else
                stuckT = stuckT + 0.08
                if stuckT >= STUCK_LIMIT then
                    if onStatus then onStatus("[!] Stuck "..STUCK_LIMIT.."s, skip map...") end
                    _StopEnemyPullWorker()
                    return true
                end
            end

            -- Serang semua musuh hidup di pullList
            for _, t in ipairs(pullList) do
                if not _pullDestroyedG[t.guid] then
                    local model = t.model
                    if model and model.Parent then
                        local hum = model:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            local g = t.guid
                            task.spawn(function()
                                FireAllDamage(g)
                            end)
                        end
                    end
                end
            end
            PG_Wait(0.08)
        end
        _StopEnemyPullWorker()
        return false
    end

    --  WaitRaidDone (identik 1.lua baris ~2827) 
    local function WaitRaidDone()
        local t = 0
        local function shouldPause()
            if MODE.current == "siege" or (SIEGE and SIEGE.inMap) or _siegeInterrupt then
                return true, "Auto Siege"
            end
            if RAID and RAID.running then
                if _raidInterrupt or (MODE.current == "raid" and RAID.inMap) or RAID.inMap then
                    return true, "Auto Raid"
                end
            end
            if ASC and (_ascInterrupt or ASC.inMap) then
                return true, "Auto Ascension"
            end
            return false, nil
        end

        local pause, reason = shouldPause()
        while pause and MA.running do
            t = t + 0.5
            if t >= 120 then
                if MODE.current ~= "idle" and MODE.current ~= "ma" then
                    MODE.current = "idle"
                end
                break
            end
            local label = reason or "Other Feature"
            -- Update status via Paragraph (WindUI API, ganti _maStatusLbl.Text)
            if _maStatusPara then
                pcall(function() _maStatusPara:SetDesc("[||] Pause ("..label..") - "..math.floor(t).."s") end)
            end
            task.wait(0.5)
            pause, reason = shouldPause()
        end
        if MA.running then task.wait(0.5) end
        if _maStatusPara and MA.running then
            pcall(function() _maStatusPara:SetDesc("> Continue After pause...") end)
        end
    end

    --  DoMassAttack (identik 1.lua baris ~2914) 
    function DoMassAttack(on)
        if on then
            _mOn = true
            MA.running = true
            MA.killed  = 0
            MA.collected = 0
            -- Gold collector dipakai dari MAIN (StartDestroyWorker/StartGoldMagnet)
            -- Cukup panggil jika fungsi tersedia
            if StartGoldMagnet then
                if StopGoldMagnet then StopGoldMagnet() end
                StartGoldMagnet(function() return MA.running end)
            end
            if StartInstantGoldCollector then StartInstantGoldCollector(true) end
            if StartDestroyWorker then StartDestroyWorker(function() return MA.running end) end

            MA.thread = task.spawn(function()
                local _maStart = os.time()
                local function maStatus(msg)
                    if _maStatusPara then
                        local dur = os.time() - _maStart
                        local ts  = string.format("%02d:%02d:%02d",
                            math.floor(dur/3600), math.floor(dur/60)%60, dur%60)
                        pcall(function() _maStatusPara:SetDesc("["..ts.."] "..msg) end)
                    end
                end

                while MA.running do
                    -- Pause kalau ada fitur prioritas lebih tinggi
                    do local _np=(MODE.current~="idle" and MODE.current~="ma") or _raidInterrupt or _siegeInterrupt or _ascInterrupt or (ST2 and ST2.running); if _np then WaitRaidDone() end end
                    if not MA.running then break end

                    local mapsToUse = {}
                    for i = 1, 20 do
                        if MR.selected[i] then table.insert(mapsToUse, MAPS[i]) end
                    end

                    if #mapsToUse == 0 then
                        -- Mode tanpa rotasi map: serang di map sekarang
                        local cont = AttackLoop_Mass(function(msg) maStatus(msg) end)
                        if cont == "interrupted" then
                            WaitRaidDone()
                        elseif not cont or not MA.running then
                            break
                        end
                        do local _np=(MODE.current~="idle" and MODE.current~="ma") or _raidInterrupt or _siegeInterrupt or _ascInterrupt or (ST2 and ST2.running); if _np then WaitRaidDone() end end
                        task.wait(MR.nextMapDelay)
                    else
                        -- Mode rotasi map: loop memutar semua map yang dipilih
                        local _mapIdx = 1
                        while MA.running do
                            repeat
                                -- Rebuild fresh list tiap iterasi (respon perubahan selection)
                                local _fresh = {}
                                for i = 1, 20 do
                                    if MR.selected[i] then table.insert(_fresh, MAPS[i]) end
                                end
                                if #_fresh == 0 then mapsToUse = {}; break end
                                if _mapIdx > #_fresh then _mapIdx = 1 end
                                local m = _fresh[_mapIdx]

                                do local _np=(MODE.current~="idle" and MODE.current~="ma") or _raidInterrupt or _siegeInterrupt or _ascInterrupt or (ST2 and ST2.running); if _np then WaitRaidDone() end end
                                if not MA.running then break end
                                if _raidInterrupt then _mapIdx = _mapIdx + 1; break end

                                maStatus("-> TP ke "..m.name.."...")
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

                                do local _np=(MODE.current~="idle" and MODE.current~="ma") or _raidInterrupt or _siegeInterrupt or _ascInterrupt or (ST2 and ST2.running); if _np then WaitRaidDone() end end
                                if not MA.running then break end

                                maStatus("[OK] SUCCES "..m.name.." - Go to...")
                                task.wait(MR.nextMapDelay)
                                _mapIdx = _mapIdx + 1
                                if _mapIdx > #_fresh then _mapIdx = 1 end
                            until true
                        end
                    end
                end

                _mOn = false
                MA.running = false

                if _maStatusPara then
                    pcall(function() _maStatusPara:SetDesc("[.] IDLE") end)
                end
                if StartInstantGoldCollector then StartInstantGoldCollector(false) end
                if StopGoldMagnet then StopGoldMagnet() end
            end)
        else
            _mOn = false; MA.running = false
            _StopEnemyPullWorker()  -- pastikan pull worker berhenti saat MA di-OFF
            if MA.thread then
                pcall(function() task.cancel(MA.thread) end)
                MA.thread = nil
            end
            if _maStatusPara then
                pcall(function() _maStatusPara:SetDesc("Idle") end)
            end
            if StartInstantGoldCollector then StartInstantGoldCollector(false) end
            if StopGoldMagnet then StopGoldMagnet() end
        end
    end

    -- =========================================================================
    -- WindUI ELEMENTS  (MassAttackTab)
    -- API: Tab:Section(), Tab:Paragraph(), Tab:Dropdown(), Tab:Toggle()
    -- =========================================================================

    --  Section header 
    MassAttackTab:Section({ Title = "Mass Attack" })

    --  Status paragraph (ganti _maStatusLbl dari 1.lua) 
    local statusPara = MassAttackTab:Paragraph({
        Title = "Status",
        Desc  = "Idle",
    })
    _maStatusPara = statusPara   -- expose global agar WaitRaidDone bisa update

    --  TARGET KILL dropdown (identik 1.lua baris ~6870) 
    -- WindUI Dropdown, Multi=false, Value=nil (bukan {})
    local _killOptVals  = {5, 10, 15, 20, 0}
    local _killOptNames = {"5", "10", "15", "20", "Kill All"}
    local killDD = MassAttackTab:Dropdown({
        Flag    = "maKillDD",
        Title   = "Target Kill",
        Desc    = "Jumlah kill sebelum pindah map",
        Multi   = false,
        Value   = nil,
        Values  = _killOptNames,
        Callback = function(val)
            -- Cari nilai dari nama
            for i, name in ipairs(_killOptNames) do
                if name == val then
                    MA.killTarget = _killOptVals[i]
                    _killDDIdxState = i
                    break
                end
            end
        end,
    })
    -- Expose setter (diperlukan Config restore)
    _setKillDDGlobal = function(idx)
        _killDDIdxState = idx
        if _killOptNames[idx] then
            pcall(function() killDD:Select(_killOptNames[idx]) end)
            MA.killTarget = _killOptVals[idx]
        end
    end
    -- Set default dari state tersimpan
    if _killOptNames[_killDDIdxState] then
        pcall(function() killDD:Select(_killOptNames[_killDDIdxState]) end)
        MA.killTarget = _killOptVals[_killDDIdxState]
    end

    --  Rotation Map dropdown (Multi, identik 1.lua baris ~6895) 
    local _mapOptNames = {"ALL MAP"}
    for i = 1, 20 do _mapOptNames[i+1] = "Map "..i end

    local mapSelSet   = {}
    local mapItemRefs = {}
    _maMapSelState  = mapSelSet
    _maMapItemRefs  = mapItemRefs

    -- Track apakah ALL MAP ada di selection iterasi sebelumnya
    local _prevHadAll = false

    local mapDD  -- forward ref untuk :Select() di dalam callback
    -- [FIX v5] Jangan pakai 'local _, mapDD = ...' — itu buat variable baru (mapDD_B = nil,
    -- karena WindUI Dropdown hanya return 1 value). _maUpdateMapDDLbl tangkap mapDD_B yg nil
    -- → if not mapDD then return end → visual tidak pernah update.
    -- Pakai assignment biasa (tanpa 'local') agar upvalue mapDD di atas ter-assign.
    mapDD = MassAttackTab:Dropdown({
        Flag     = "maMapDD",
        Title    = "Rotation Map",
        Desc     = "Pilih map untuk dirotasi (kosong = map sekarang)",
        Multi    = true,
        Value    = {},
        Values   = _mapOptNames,
        Callback = function(val)
            -- val = ap.Value saat ini (full array setelah klik)
            local hasAll = false
            if type(val) == "table" then
                for _, v in ipairs(val) do
                    if v == "ALL MAP" then hasAll = true; break end
                end
            end

            if hasAll and not _prevHadAll then
                -- ALL MAP baru di-CHECK: select semua Map 1-20 + update visual
                _prevHadAll = true
                for i = 1, 20 do mapSelSet[i] = true; MR.selected[i] = true end
                -- Force visual: inject semua Map 1-20 ke ap.Value via :Select()
                local allVal = {"ALL MAP"}
                for i = 1, 20 do table.insert(allVal, "Map "..i) end
                task.defer(function()
                    pcall(function() mapDD:Select(allVal) end)
                end)

            elseif not hasAll and _prevHadAll then
                -- ALL MAP baru di-UNCHECK: clear semua
                _prevHadAll = false
                for i = 1, 20 do mapSelSet[i] = nil; MR.selected[i] = nil end
                -- Force visual: kosongkan semua via :Select(nil)  ap.Value={}
                task.defer(function()
                    pcall(function() mapDD:Select({}) end)
                end)

            elseif hasAll and _prevHadAll then
                -- ALL MAP masih ada, user pilih Map individual tambahan  biarkan
                for i = 1, 20 do mapSelSet[i] = true; MR.selected[i] = true end

            else
                -- Mode pilihan manual biasa (tanpa ALL MAP)
                _prevHadAll = false
                for i = 1, 20 do mapSelSet[i] = nil; MR.selected[i] = nil end
                if type(val) == "table" then
                    for _, v in ipairs(val) do
                        local mi = tonumber(v:match("Map (%d+)"))
                        if mi then mapSelSet[mi] = true; MR.selected[mi] = true end
                    end
                end
            end
        end,
    })

    _maUpdateMapDDLbl = function()
        -- Sync visual dropdown map sesuai _maMapSelState saat ini
        -- Dipakai oleh ApplyConfig setelah restore data mapSel
        if not mapDD then return end
        pcall(function()
            local selVals = {}
            local allOn = true
            for i = 1, 20 do
                if mapSelSet[i] then
                    table.insert(selVals, "Map "..i)
                else
                    allOn = false
                end
            end
            if allOn and #selVals == 20 then
                table.insert(selVals, 1, "ALL MAP")
                _prevHadAll = true
            else
                _prevHadAll = false
            end
            mapDD:Select(selVals)
        end)
    end

    --  DELAY PINDAH MAP dropdown (identik 1.lua baris ~6944) 
    local _delayOptVals  = {1, 3, 5, 7, 10}
    local _delayOptNames = {"1", "3", "5", "7", "10"}
    local delayDD = MassAttackTab:Dropdown({
        Flag    = "maDelayDD",
        Title   = "Delay Pindah Map",
        Desc    = "Detik tunggu sebelum pindah ke map berikutnya",
        Multi   = false,
        Value   = nil,
        Values  = _delayOptNames,
        Callback = function(val)
            for i, name in ipairs(_delayOptNames) do
                if name == val then
                    MR.nextMapDelay = _delayOptVals[i]
                    _delayDDIdxState = i
                    break
                end
            end
        end,
    })
    _setDelayDDGlobal = function(idx)
        _delayDDIdxState = idx
        if _delayOptNames[idx] then
            pcall(function() delayDD:Select(_delayOptNames[idx]) end)
            MR.nextMapDelay = _delayOptVals[idx]
        end
    end
    if _delayOptNames[_delayDDIdxState] then
        pcall(function() delayDD:Select(_delayOptNames[_delayDDIdxState]) end)
        MR.nextMapDelay = _delayOptVals[_delayDDIdxState]
    end

    --  MASS ATTACK master toggle (identik 1.lua baris ~7018) 
    MassAttackTab:Section({ Title = "Control" })

    local maToggle = MassAttackTab:Toggle({
        Flag     = "maToggle",
        Title    = "Mass Attack",
        Desc     = "Serang semua musuh di map sekaligus",
        Default  = false,
        Callback = function(on)
            DoMassAttack(on)
        end,
    })
    -- Expose setter dan visual toggle (kompatibilitas Config panel)
    _setMaToggleGlobal = function(on)
        pcall(function() maToggle:Set(on, false) end)
        DoMassAttack(on)
    end
    _visMassAtk = function(on)
        pcall(function() maToggle:Set(on, false) end)
    end

    --  AUTO SKILL section (identik 1.lua baris ~6954 skillCard) 
    MassAttackTab:Section({ Title = "Auto Skill" })

    local _skillKeys = {
        {n="Z", desc="Skill slot Z"},
        {n="X", desc="Skill slot X"},
        {n="C", desc="Skill slot C"},
        {n="V", desc="Skill slot V"},
        {n="F", desc="Skill slot F"},
    }
    -- Simpan elemen toggle per skill key agar bisa di-set saat restore Config
    local _skillToggleEls = {}
    for _, sk in ipairs(_skillKeys) do
        local key = sk.n
        local el = MassAttackTab:Toggle({
            Flag     = "maSkill_"..key,
            Title    = "Auto Skill "..key,
            Desc     = sk.desc,
            Default  = false,
            Callback = function(on)
                if on then SkOn(key) else SkOff(key) end
            end,
        })
        _skillToggleEls[key] = el
    end

    -- Expose setter skill visual ke global (dibaca Config panel saat restore)
    -- ApplyConfig memanggil SkOn/SkOff langsung untuk logika,
    -- tapi visual toggle WindUI perlu di-sync secara terpisah
    _setSkillToggleVis = function(key, v)
        local el = _skillToggleEls[key]
        if el then pcall(function() el:Set(v, false) end) end
    end

end -- end do PANEL: MASS ATTACK



-- ============================================================================
-- [FIX] MISSING GLOBALS UNTUK AUTO RAID
-- Fungsi-fungsi ini ada di 1.lua tapi tidak di-port ke 2.lua.
-- Tanpa ini StartRaidLoop crash diam-diam karena C.ACC2/C.ACC3/GetRaidEnemies/dll nil.
-- ============================================================================

-- [FIX 1] C color table (C.ACC2, C.ACC3 dipakai di StartRaidLoop)
if not C or not C.ACC3 then
    C = C or {}
    C.BG    = Color3.fromRGB(9,11,22)
    C.ACC   = Color3.fromRGB(55,105,255)
    C.ACC2  = Color3.fromRGB(90,145,255)
    C.ACC3  = Color3.fromRGB(72,125,255)
    C.TXT   = Color3.fromRGB(195,210,255)
    C.TXT2  = Color3.fromRGB(235,242,255)
    C.TXT3  = Color3.fromRGB(90,110,170)
end

-- [FIX 2] _heroFireTick (dipakai FireAttack global)
_heroFireTick = _heroFireTick or {}

-- [FIX 3] FireAttack global (dipakai _attackBoss di STEP4 StartRaidLoop)
if not FireAttack then
    function FireAttack(g, pos)
        if not g then return end
        local _atkPos = pos or Vector3.new(0,0,0)
        local _char = LP and LP.Character
        local _pHRP = _char and _char:FindFirstChild("HumanoidRootPart")
        if _pHRP and pos then
            local _dir = (_pHRP.Position - pos)
            local _dir2 = Vector3.new(_dir.X, 0, _dir.Z)
            if _dir2.Magnitude > 0.1 then
                _atkPos = pos + _dir2.Unit * 5
            else
                _atkPos = pos + Vector3.new(1,0,0) * 5
            end
        end
        if RE.Atk then pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end) end
        if RE.HeroUseSkill and #HERO_GUIDS > 0 then
            local now = tick()
            local last = _heroFireTick[g] or 0
            if now - last >= 0.04 then
                _heroFireTick[g] = now
                for _, hGuid in ipairs(HERO_GUIDS) do
                    pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g,targetPos=_atkPos}) end)
                end
            end
        end
    end
end

-- [FIX 4] GetPlayerPos global (dipakai GetRaidEnemies)
if not GetPlayerPos then
    function GetPlayerPos()
        local char = LP and LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        return hrp and hrp.Position or nil
    end
end

-- [FIX 5] GetRaidEnemies global (dipakai STEP3+STEP4 StartRaidLoop)
if not GetRaidEnemies then
    function GetRaidEnemies()
        local list = {}
        local seen = {}
        local currentMapId = GetCurrentMapId and GetCurrentMapId() or nil
        local _inNormalRaid = currentMapId and (currentMapId >= 50101 and currentMapId <= 50120)
        local _inAscTower   = currentMapId and (currentMapId >= 50301 and currentMapId <= 50326)
        if currentMapId then
            local _inSiege   = currentMapId >= 50201 and currentMapId <= 50204
            local _inAnniv   = currentMapId == 50401
            if _inSiege or _inAnniv then return list end
        end
        local playerPos = GetPlayerPos()
        local activeMapId = _inNormalRaid and (RAID and RAID.serverMapId) or
            (not _inNormalRaid and not _inAscTower and RAID and RAID.inMap and RAID.serverMapId) or nil
        local spawnPos = activeMapId and RAID_SPAWN_POS and RAID_SPAWN_POS[activeMapId]
        local refPos = (playerPos and playerPos.Magnitude > 1) and playerPos
                    or (spawnPos and spawnPos.Magnitude > 1) and spawnPos
                    or nil
        local MAX_DIST = 4000
        local useDistFilter = refPos ~= nil
        local function addEnemy(e)
            if not e:IsA("Model") then return end
            if not e:IsDescendantOf(workspace) then return end
            local g = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid") or e:GetAttribute("Guid") or e:GetAttribute("GUID")
            if not g or seen[g] then return end
            local hrp = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
                     or e:FindFirstChild("Torso") or e:FindFirstChild("UpperTorso")
                     or e:FindFirstChildWhichIsA("BasePart")
            local hum = e:FindFirstChildOfClass("Humanoid")
            if not (hrp and hum) then return end
            if hum.Health <= 0 then return end
            if hum.MaxHealth <= 0 then return end
            local _ep = hrp.Position
            if _ep.Magnitude <= 10 then return end
            if _ep.Y < -200 or _ep.Y > 1500 then return end
            if not hrp:IsDescendantOf(workspace) then return end
            if useDistFilter then
                local dist = (_ep - refPos).Magnitude
                if dist > MAX_DIST then return end
            end
            seen[g] = true
            table.insert(list, {guid=g, hrp=hrp, model=e})
        end
        for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
            local folder = workspace:FindFirstChild(fname)
            if folder then
                for _, e in ipairs(folder:GetChildren()) do addEnemy(e) end
            end
        end
        return list
    end
end

-- [FIX 6] _lastRescanTime + ForceRescanRaidEnter global
_lastRescanTime = _lastRescanTime or 0
if not ForceRescanRaidEnter then
    function ForceRescanRaidEnter()
        local now = tick()
        if now - _lastRescanTime < 1.5 then return end
        _lastRescanTime = now
        pcall(function()
            local RM = require(game:GetService("ReplicatedStorage").Scripts.Client.Manager.RaidsManager)
            if type(RM) ~= "table" then return end
            local newFound = false
            local currentActiveIds = {}
            for _, val in pairs(RM) do
                if type(val) == "table" then
                    for k, info in pairs(val) do
                        repeat
                        if type(info) == "table" and info.raidId and info.mapId then
                            local raidId = info.raidId
                            local mapId  = info.mapId
                            local spawnName = info.spawnName or "RE1001"
                            if raidId == 937101 then break end
                            if mapId >= 50101 and mapId <= 50120 then mapId = mapId - 100 end
                            if mapId < 50001 or mapId > 50020 then break end
                            currentActiveIds[raidId] = true
                            local mapNum = mapId - 50000
                            local grade = (RAID_CONFIG_GRADE and RAID_CONFIG_GRADE[raidId])
                                       or (_runeGradeCache and _runeGradeCache[mapNum]) or "?"
                            local tempKey = -(mapId)
                            if RAID_LIVE[tempKey] then RAID_LIVE[tempKey] = nil end
                            if not RAID_LIVE[raidId] then
                                RAID_LIVE[raidId] = {
                                    raidId=raidId, mapId=mapId, spawnName=spawnName,
                                    rank=SPAWN_RANK[spawnName] or 0, grade=grade,
                                    endTime=info.endTime,
                                    label="Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." ["..grade.."](ID:"..raidId..")"
                                }
                                newFound = true
                            else
                                if RAID_LIVE[raidId].grade ~= grade then
                                    RAID_LIVE[raidId].grade = grade
                                    RAID_LIVE[raidId].label = "Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." ["..grade.."](ID:"..raidId..")"
                                    newFound = true
                                end
                            end
                        end
                        until true
                    end
                end
            end
            for rid, ent in pairs(RAID_LIVE) do
                if rid > 0 and not currentActiveIds[rid] then
                    RAID_LIVE[rid] = nil; newFound = true
                end
            end
            if newFound then
                if RebuildRaidList then pcall(RebuildRaidList) end
                if TriggerEntryWakeup then TriggerEntryWakeup() end
            end
        end)
    end
end

-- [FIX v1.lua PORT] Radar global: scan otomatis tiap 1.5 detik
-- Di file 1 (baris 12186-12190) ini BERDIRI SENDIRI di luar guard apapun.
-- Di file 2 sebelumnya ada di dalam "if not ForceRescanRaidEnter" -> tidak jalan jika fungsi sudah ada!
task.spawn(function()
    while task.wait(1.5) do
        if ForceRescanRaidEnter then ForceRescanRaidEnter() end
    end
end)

-- [FIX 7] IsRaidLiveInGame (dipakai banyak di StartRaidLoop)
if not IsRaidLiveInGame then
    function IsRaidLiveInGame()
        return RAID_ID_LIST and #RAID_ID_LIST > 0
    end
end

-- [FIX 8] FireAllDamage global (dipakai _attackBoss STEP4 — versi lokal di MA block tidak accessible)
if not FireAllDamage then
    function FireAllDamage(g, ep)
        if not g then return end
        if RE.Click then
            task.spawn(function()
                pcall(function() RE.Click:InvokeServer({enemyGuid=g, enemyPos=ep}) end)
            end)
        end
        if RE.Atk then
            pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
        end
        if RE.HeroUseSkill and #HERO_GUIDS > 0 then
            for _, hGuid in ipairs(HERO_GUIDS) do
                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=2,userId=MY_USER_ID,enemyGuid=g}) end)
                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=3,userId=MY_USER_ID,enemyGuid=g}) end)
            end
        elseif RE.HeroSkill and #HERO_GUIDS > 0 then
            for _, hGuid in ipairs(HERO_GUIDS) do
                pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=1,masterId=MY_USER_ID}) end)
                pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=2,masterId=MY_USER_ID}) end)
                pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=3,masterId=MY_USER_ID}) end)
            end
        end
    end
end

-- [FIX 9] FireHeroRemotes global (dipakai _attackBoss STEP4 — versi lokal di MA block tidak accessible)
-- [EDIT] HeroMoveToEnemyPos dihapus — tidak dipakai lagi.
if not FireHeroRemotes then
    function FireHeroRemotes(enemyGuid, enemyPos)
    end
end


-- [FIX 10] BOSS_NAME_BY_MAP - diperlukan AUTO BOSS KILL STEP4
BOSS_NAME_BY_MAP = BOSS_NAME_BY_MAP or {
    [1]  = "Goblin King",
    [2]  = "Giant Arachnid Buryura",
    [3]  = "Igris",
    [4]  = "Leader Of The Polar Bears",
    [5]  = "Arch Lich",
    [6]  = "Kargalgan",
    [7]  = "Baran",
    [8]  = "Beru",
    [9]  = "Giant Monarch",
    [10] = "Monarch Of Plague",
    [11] = "Frostborne",
    [12] = "Legia",
    [13] = "Silas",
    [14] = "Yogumunt",
    [15] = "Antares",
    [16] = "Ashborn",
    [17] = "Dominion",
    [18] = "Absolute",
    [19] = "Broly",
    [20] = "Goku[Super4]",
}

-- [FIX 11] ParseChatLine + TipsPanel/ExperienceChat watcher
-- INI YANG MEMBUAT RAID TERDETEKSI DARI SEMUA MAP TANPA HARUS DEKAT!
-- Port identik dari 1.lua baris 9103-9430

_runeGradeCache = _runeGradeCache or {}
_ASC_CHAT_CACHE = _ASC_CHAT_CACHE or {}
_whSilent       = _whSilent or false

if not ParseChatLine then
    function ParseChatLine(text)
        if type(text) ~= "string" or #text < 3 then return end
        text = text:gsub("<[^>]+>",""):gsub("[\r\n]+"," "):match("^%s*(.-)%s*$") or text

        if text:find("MaFissure",1,true) and text:find("appeared",1,true) then

            local function extractGradeLast(t)
                local grade = nil
                for _, pat in ipairs({"M%+%+","M%+","SS","XM","ULT","GOD","M"}) do
                    if t:find("%["..pat.."]", 1, false) then
                        local last = nil
                        for m in t:gmatch("%["..pat.."]") do last = m end
                        if last then grade = last:match("%[(.+)%]"); break end
                    end
                end
                if grade then return grade:upper() end
                local last = nil
                for bracket in t:gmatch("%[([^%]]+)%]") do
                    local up = bracket:upper()
                    if up:match("^[EDCBAGSN]$") then last = up end
                end
                return last
            end

            -- Ascension Tower
            if text:find("Ascension Tower", 1, true) then
                local towerNum = tonumber(text:match("Ascension Tower (%d+)"))
                local grade    = extractGradeLast(text)
                if towerNum and grade then
                    _runeGradeCache[-towerNum] = grade
                    _ASC_CHAT_CACHE[towerNum] = { grade = grade, time = os.time() }
                    for _rid, _ent in pairs(RAID_LIVE) do
                        if _ent.isAscension and _ent.mapId then
                            local _mn2 = (_ent.mapId >= 50301 and _ent.mapId <= 50326)
                                and (_ent.mapId - 50300) or nil
                            if _mn2 == towerNum and (_ent.grade == "?" or not _ent.grade) then
                                _ent.grade = grade
                                _ent.label = "Ascension Tower ".._mn2.." ["..grade.."]"
                            end
                        end
                    end
                    if RebuildRaidList then pcall(RebuildRaidList) end
                    if _WH and _WH.AddLine then
                        _WH.AddLine("The MaFissure appeared in Ascension Tower "..towerNum.." ["..grade.."]")
                    end
                    if TriggerEntryWakeup then TriggerEntryWakeup() end
                end
                return
            end

            -- Normal Raid: "appeared in 6,Orc Palace [B]"
            local mapStr, rest
            mapStr, rest = text:match("appeared in (%d+),(.+)")
            if not mapStr then mapStr, rest = text:match("appeared in (%d+) (.+)") end
            if mapStr then
                local mapNum = tonumber(mapStr)
                local grade  = extractGradeLast(rest or "") or extractGradeLast(text)
                if mapNum and grade then
                    local prev      = _runeGradeCache[mapNum]
                    local cleanPrev = prev and prev:match("^([^%s%(]+)") or prev
                    local upd = not prev or cleanPrev == "?"
                        or (GRADE_RANK[grade] and GRADE_RANK[cleanPrev] and GRADE_RANK[grade] > GRADE_RANK[cleanPrev])
                    if upd then _runeGradeCache[mapNum] = grade end
                    for _, entry in pairs(RAID_LIVE) do
                        if entry.mapId and (entry.mapId - 50000) == mapNum then
                            entry.isAscension = false
                        end
                    end
                    if _WH and _WH.AddLine then
                        local _mapName = MAP_NAMES and MAP_NAMES[mapNum] or ("Map "..mapNum)
                        _WH.AddLine("The MaFissure appeared in "..mapNum..",".. _mapName.." ["..grade.."]")
                    end
                    if TriggerEntryWakeup then TriggerEntryWakeup() end
                end
            end
        end
    end
end

-- Chat dedup + dispatch
local _chatSeen = {}
local function _processMsg(raw)
    if type(raw) ~= "string" or #raw < 5 then return end
    local txt = raw:gsub("<[^>]+>",""):gsub("[\r\n]+"," "):match("^%s*(.-)%s*$") or raw
    local function hasKW(s)
        return s:find("MaFissure",1,true) or s:find("appeared in",1,true) or s:find("has begun",1,true)
    end
    if not hasKW(txt) then
        local stripped = txt:match("^[^:]+:%s*(.+)$")
        if stripped and hasKW(stripped) then txt = stripped end
    end
    if not hasKW(txt) then return end
    local key = txt:sub(1,200)
    local now = tick()
    if _chatSeen[key] and (now - _chatSeen[key]) < 180 then return end
    _chatSeen[key] = now
    ParseChatLine(txt)
    local count = 0
    for _ in pairs(_chatSeen) do count = count + 1 end
    if count > 50 then
        for k, t in pairs(_chatSeen) do
            if (now - t) > 180 then _chatSeen[k] = nil end
        end
    end
end

-- PRIMER: TipsFloatingPanel detector (poll setiap 0.3s)
task.spawn(function()
    local _lastTexts = {}
    while task.wait(0.3) do
        pcall(function()
            local pg = LP.PlayerGui
            for _, panel in ipairs(pg:GetChildren()) do
                if panel.Name == "TipsFloatingPanel" then
                    for _, desc in ipairs(panel:GetDescendants()) do
                        if desc:IsA("TextLabel") then
                            local txt = (desc.Text or ""):gsub("<[^>]+>",""):gsub("[\r\n]+"," ")
                            if #txt > 5 and _lastTexts[desc] ~= txt then
                                _lastTexts[desc] = txt
                                _processMsg(txt)
                            end
                        end
                    end
                end
            end
        end)
    end
end)

-- BACKUP: TextChatService chat history
task.spawn(function()
    pcall(function()
        local TCS = game:GetService("TextChatService")
        local _w = 0
        repeat task.wait(0.5); _w = _w + 0.5
        until TCS:FindFirstChild("TextChannels") or _w >= 10
        local channels = TCS:FindFirstChild("TextChannels")
        if not channels then return end
        local function watchChannel(ch)
            if not ch:IsA("TextChannel") then return end
            ch.ChildAdded:Connect(function(obj)
                if obj:IsA("TextChatMessage") then
                    task.delay(5, function()
                        pcall(function()
                            local txt = obj.Text or ""
                            if #txt < 5 then txt = (obj.PrefixText or "").." "..(obj.Text or "") end
                            _processMsg(txt)
                        end)
                    end)
                end
            end)
        end
        for _, ch in ipairs(channels:GetChildren()) do watchChannel(ch) end
        channels.ChildAdded:Connect(function(ch) task.spawn(function() task.wait(0.1); watchChannel(ch) end) end)
        -- Scan history awal
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

-- FALLBACK: ExperienceChat BodyText watcher
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
        for _, obj in ipairs(ec:GetDescendants()) do checkBodyText(obj) end
        ec.ChildAdded:Connect(function(obj)
            task.spawn(function()
                task.wait(4)
                checkBodyText(obj)
            end)
        end)
    end)
end)


-- ============================================================================
-- PANEL: AUTOMATION - AUTO RAID (v30)
-- Port dari 1.lua baris 8875-14697 ke WindUI
-- Section slide up/down persis seperti 1.lua, menggunakan AutomationTab
-- ============================================================================

do -- AUTO RAID: DATA & STATE GLOBAL

-- Remote tambahan untuk RAID (di luar yang sudah ada di RE)
RE = RE or {}
RE.CreateRaidTeam       = RE.CreateRaidTeam       or Remotes:FindFirstChild("CreateRaidTeam")
RE.StartChallengeRaidMap= RE.StartChallengeRaidMap or Remotes:FindFirstChild("StartChallengeRaidMap")
RE.LocalTpSuccess       = RE.LocalTpSuccess        or Remotes:FindFirstChild("LocalPlayerTeleportSuccess")
RE.UseRaidItem          = RE.UseRaidItem           or Remotes:FindFirstChild("UseRaidItem")
RE.GetRaidTeamInfos     = RE.GetRaidTeamInfos      or Remotes:FindFirstChild("GetRaidTeamInfos")
-- [FIX] Hero remotes untuk AUTO BOSS KILL (UnEquip -> EquipBest setelah TP)
RE.UnEquipHero          = RE.UnEquipHero           or Remotes:FindFirstChild("UnequipAllHero")
RE.EquipBestHero        = RE.EquipBestHero         or Remotes:FindFirstChild("AutoEquipBestHero")
RE.EquipHeroWithData    = RE.EquipHeroWithData      or Remotes:FindFirstChild("EquipHeroWithData")
RE.HeroStand            = RE.HeroStand             or Remotes:FindFirstChild("HeroStandTo")

--  SPAWN_RANK 
SPAWN_RANK = SPAWN_RANK or {
    RE1001=1, RE1002=2, RE1003=3, RE1004=4, RE1005=5, RE1006=6,
}

--  RANK_LABEL 
RANK_LABEL = RANK_LABEL or {
    [1]="E",[2]="D",[3]="C",[4]="B",[5]="A",
    [6]="S",[7]="SS",[8]="G",[9]="N",[10]="M",
    [11]="M+",[12]="M++",[15]="XM",[17]="ULT",
}

--  MAP_NAMES 
MAP_NAMES = MAP_NAMES or {
    [1]="Shadow Gate City",[2]="Level Grinding Cavern",[3]="Shadow Castle",
    [4]="Seolhan Forest",[5]="Demon Castle - Tier 1",[6]="Orc Palace",
    [7]="Demon Castle - Tier 2",[8]="Ant Island",[9]="Land of Giant",
    [10]="Plagueheart",[11]="Umbralfrost Domain",[12]="Kamish's Demise",
    [13]="Lava Hell",[14]="Illusory World",[15]="Inferno Altar",
    [16]="Shadow Throne",[17]="Angel Holy Realm",[18]="Golden Throne",
    [19]="Dragon Ball City",[20]="Dragon Ball Wasteland",
}

--  GRADE_LIST / GRADE_RANK 
GRADE_LIST = GRADE_LIST or {"E","D","C","B","A","S","SS","G","N","M","M+","M++","XM","ULT"}
GRADE_RANK = GRADE_RANK or {
    ["E"]=1,["D"]=2,["C"]=3,["B"]=4,["A"]=5,["S"]=6,["SS"]=7,
    ["G"]=8,["N"]=9,["M"]=10,["M+"]=11,["M++"]=12,["XM"]=15,["ULT"]=17,["GOD"]=18,
}

--  RAID_CONFIG_GRADE (formula dari raidId) 
if not RAID_CONFIG_GRADE then
    local _GRADE_IDX  = {"E","D","C","B","A","S","SS","G","N","M","M+","M++","XM","ULT","GOD"}
    local _GRADE_RAID = {"D","B","S","SS","G","N","M+","M++","XM","ULT"}
    RAID_CONFIG_GRADE = setmetatable({},{
        __index = function(_, raidId)
            if type(raidId) ~= "number" then return nil end
            if raidId == 937101 then return nil end
            if raidId >= 935001 then return _GRADE_IDX[raidId%100] or "?" end
            if raidId >= 930001 then return _GRADE_RAID[(raidId-930001)%10+1] or "?" end
            return nil
        end
    })
end

--  RAID_SPAWN_POS 
RAID_SPAWN_POS = RAID_SPAWN_POS or {
    [50101]=Vector3.new(2424.9,8.5,482.9),[50102]=Vector3.new(1683.1,8.6,-24.1),
    [50103]=Vector3.new(1913.1,12,-194.4),[50104]=Vector3.new(515.8,7.6,-98.0),
    [50105]=Vector3.new(-229.3,9.6,-2.3),[50106]=Vector3.new(1998.2,8.0,237.7),
    [50107]=Vector3.new(-42.0,8.4,334.0),[50108]=Vector3.new(-925.8,-396.2,-901.6),
    [50109]=Vector3.new(8.7,13.0,244.2),[50110]=Vector3.new(2003.0,8.1,344.0),
    [50111]=Vector3.new(2068.0,49.4,-155.8),[50112]=Vector3.new(16.5,9.0,269.5),
    [50113]=Vector3.new(2100.7,63.1,423.1),[50114]=Vector3.new(27.8,49.8,303.9),
    [50115]=Vector3.new(-0.9,24.0,185.3),[50116]=Vector3.new(1999.6,17.0,236.5),
    [50117]=Vector3.new(-0.4,18.5,93.5),[50118]=Vector3.new(2000.0,45.4,234.7),
    [50119]=Vector3.new(0,10.0,0),[50120]=Vector3.new(0,10.0,0),
}

--  RAID_MAP_INFO 
RAID_MAP_INFO = RAID_MAP_INFO or {
    [1]={instance="Map1",rootPart="4025"},[2]={instance="Map2",rootPart="4050"},
    [3]={instance="Map3",rootPart="4025"},[4]={instance="Map4",rootPart="4050"},
    [5]={instance="Map5",rootPart="4050"},[6]={instance="Map6",rootPart="4044"},
    [7]={instance="Map7",rootPart="4050"},[8]={instance="Map8",rootPart="4050"},
    [9]={instance="Map9",rootPart="4050"},[10]={instance="Map10",rootPart="4050"},
    [11]={instance="Map11",rootPart="4050"},[12]={instance="Map12",rootPart="4050"},
    [13]={instance="Map13",rootPart="4050"},[14]={instance="Map14",rootPart="4050"},
    [15]={instance="Map15",rootPart="4050"},[16]={instance="Map16",rootPart="4050"},
    [17]={instance="Map17",rootPart="4050"},[18]={instance="Map18",rootPart="4050"},
    [19]={instance="Map19",rootPart="4050"},[20]={instance="Map20",rootPart="4050"},
}

--  RAID & ASC STATE TABLES 
if not RAID then
    RAID = {
        running=false,inMap=false,thread=nil,sukses=0,collected=0,
        raidId=0,raidMapId=50001,slotIndex=2,fromMapId=nil,serverMapId=nil,
        _raidDone=false,statusLbl=nil,suksesLbl=nil,dot=nil,
        difficulty="easy",preferMaps={},runeGrades={},runeEnabled=false,
        runeMapTarget=0,updownEnabled=false,updownDir=nil,
        updownTargetGrade=nil,diffLbl=nil,snapshotMapId=nil,
        listEntries={},listEnabled=false,_listVisitedMaps={},
        autoKillBoss=false,bossDelay=3,pickMode="default",
        manualMatchMode="none",updateActiveLabel=nil,activeRaidLbl=nil,
    }
end
if not ASC then
    ASC = {
        running=false,inMap=false,thread=nil,sukses=0,pickMode="easy",
        preferMaps={},runeGrades={},runeEnabled=false,runeMapTarget=0,
        preferMapTarget=0,manualMatchMode="none",_rrIdx=0,
        autoKillBoss=false,bossDelay=3,listEnabled=false,listEntries={},
        _listVisitedMaps={},statusLbl=nil,dot=nil,suksesLbl=nil,serverMapId=nil,
    }
end

_raidOn          = _raidOn          or false
_ascOn           = _ascOn           or false
_ascWakeup       = _ascWakeup       or nil
_ascBusy         = _ascBusy         or false
_ascMatchedThisCycle  = _ascMatchedThisCycle  or false
_raidFallbackActive   = _raidFallbackActive   or false
_eventOwner           = _eventOwner           or nil
_ascInterrupt    = _ascInterrupt    or false
_MAP_ENTER_LOCK  = _MAP_ENTER_LOCK  or nil
_MAP_ENTER_LOCK_TIME = _MAP_ENTER_LOCK_TIME or 0
_raidIdRefreshCb = _raidIdRefreshCb or nil
_runeGradeCache  = _runeGradeCache  or {}
_ASC_CHAT_CACHE  = _ASC_CHAT_CACHE  or {}
_pendingTowerNum  = _pendingTowerNum  or nil
_pendingTowerTime = _pendingTowerTime or 0
_raidSessionStart = _raidSessionStart or nil
_defaultRRIdx    = _defaultRRIdx    or 0
_entryWakeupTimer = _entryWakeupTimer or nil
_ENTRY_DEBOUNCE_SEC = _ENTRY_DEBOUNCE_SEC or 3

-- Forward declare fungsi yang diperlukan UI
_setRaidToggle   = nil
_visRaidToggle   = nil
_setAscToggle    = nil
_visAscToggle    = nil
_setRaidPMIdx    = nil
_setAscPMIdx     = nil
_raidBossToggleVis   = nil
_raidBossDelaySet    = nil
_raidUpdatePrefLabel = nil
_raidUpdateRankLabel = nil
_raidRebuildListRows = nil
_setRaidListEnabledVis = nil
_raidUpdownToggleVis = nil
_raidUpdownDirVis    = nil
_setRaidUpdownGrade  = nil
_setRaidRuneMapTarget= nil
_syncRaidRuneState   = nil
_prefLocked = false; _rankLocked = false; _runeLocked = false; _updownLocked = false; _listLocked = false
_prefLockLbl=nil; _rankLockLbl=nil; _runeLockLbl=nil
_prefKeyL=nil; _rankKeyL=nil; _runeKeyL=nil

--  RAID_LIVE & RAID_ID_LIST 
RAID_LIVE    = RAID_LIVE    or {}
RAID_ID_LIST = RAID_ID_LIST or {}

--  ATOMIC MAP LOCK 
function TryClaimMapLock(featureName)
    local now = os.clock()
    if _MAP_ENTER_LOCK == nil or _MAP_ENTER_LOCK == featureName then
        _MAP_ENTER_LOCK = featureName; _MAP_ENTER_LOCK_TIME = now; return true
    end
    if (now - _MAP_ENTER_LOCK_TIME) > 30 then
        _MAP_ENTER_LOCK = featureName; _MAP_ENTER_LOCK_TIME = now; return true
    end
    return false
end

function ReleaseMapLock(featureName)
    if _MAP_ENTER_LOCK == featureName then
        _MAP_ENTER_LOCK = nil; _MAP_ENTER_LOCK_TIME = 0
    end
end

function IsAnyMapActive()
    if RAID and RAID.inMap then return true,"raid" end
    if ASC  and ASC.inMap  then return true,"asc"  end
    if SIEGE and SIEGE.inMap then return true,"siege" end
    if ST2 and ST2.inMap then return true,"st2" end
    if _MAP_ENTER_LOCK ~= nil then return true,_MAP_ENTER_LOCK end
    return false,nil
end

--  HELPER FUNCTIONS 
function GetBossRootPartCFrame(mapNum)
    local info = RAID_MAP_INFO[mapNum]; if not info then return nil end
    local mf = workspace:FindFirstChild("Maps"); if not mf then return nil end
    local mapFolder = mf:FindFirstChild(info.instance); if not mapFolder then return nil end
    local mapChild = mapFolder:FindFirstChild("Map"); if not mapChild then return nil end
    local re = mapChild:FindFirstChild("RaidsEnemys"); if not re then return nil end
    local rp = re:FindFirstChild(info.rootPart); if not rp then return nil end
    return rp.CFrame
end

function GetRaidMapNum(mapId)
    local mf = workspace:FindFirstChild("Maps")
    if mf then
        local ord = {
            {1,"Map1"},{2,"Map2"},{3,"Map3"},{4,"Map4"},{5,"Map5"},
            {6,"Map6"},{7,"Map7"},{8,"Map8"},{9,"Map9"},{10,"Map10"},
            {11,"Map11"},{12,"Map12"},{13,"Map13"},{14,"Map14"},{15,"Map15"},
            {16,"Map16"},{17,"Map17"},{18,"Map18"},{19,"Map19"},{20,"Map20"},
        }
        for _,v in ipairs(ord) do if mf:FindFirstChild(v[2]) then return v[1] end end
    end
    if type(mapId) ~= "number" then return nil end
    if mapId >= 50101 and mapId <= 50120 then return mapId - 50100 end
    if mapId >= 50001 and mapId <= 50020 then return mapId - 50000 end
    return nil
end

function GetBestGrade(mapNum, isAscension)
    local mapId = isAscension and (50300+mapNum) or (50000+mapNum)
    local cacheKey = isAscension and (-mapNum) or mapNum
    if isAscension and _ASC_CHAT_CACHE then
        local e = _ASC_CHAT_CACHE[mapNum]
        if e and e.grade and e.grade ~= "?" then return e.grade end
    end
    if isAscension and _runeGradeCache then
        local cg = _runeGradeCache[-mapNum] or _runeGradeCache[cacheKey]
        if cg and cg ~= "?" then return cg end
    end
    for _, ent in pairs(RAID_LIVE) do
        local mm = (ent.mapId == mapId)
        local am = (isAscension and ent.isAscension) or (not isAscension and not ent.isAscension)
        if mm and am and ent.raidId and ent.raidId > 0 then
            local g = RAID_CONFIG_GRADE and RAID_CONFIG_GRADE[ent.raidId]
            if g and g ~= "?" then return g end
        end
    end
    if not isAscension and _runeGradeCache then
        if _runeGradeCache[cacheKey] and _runeGradeCache[cacheKey] ~= "?" then
            return _runeGradeCache[cacheKey]
        end
    end
    for _, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId and ent.grade and ent.grade ~= "?" then
            if isAscension and ent.isAscension then return ent.grade end
            if not isAscension and not ent.isAscension then return ent.grade end
        end
    end
    return nil
end

function GetCurrentMapId()
    -- [FIX v1.lua PORT] File 1 pakai pcall + cek 3 attribute + return nil jika gagal
    -- bukan hanya workspace:GetAttribute("MapId") or 0 yang return 0 saat tidak ada
    local ok, wm = pcall(function()
        return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
    end)
    return (ok and type(wm) == "number") and wm or nil
end

--  REBUILD RAID LIST 
RebuildRaidList = function()
    local sorted = {}
    for _, e in pairs(RAID_LIVE) do
        local ridAbs = e.raidId and (e.raidId < 0 and math.abs(e.raidId) or e.raidId) or 0
        if ridAbs == 937101 then continue end
        if ridAbs >= 935001 and not e.isAscension then e.isAscension = true end
        local mn = e.mapId and (e.mapId - 50000) or 0
        if e.isAscension or (e.mapId and mn >= 1 and mn <= 20) then
            table.insert(sorted, e)
        end
    end
    table.sort(sorted, function(a,b)
        local aA = a.isAscension and true or false
        local bA = b.isAscension and true or false
        if aA ~= bA then return not aA end
        return (a.mapId or 0) < (b.mapId or 0)
    end)
    RAID_ID_LIST = {}
    for _, e in ipairs(sorted) do
        local mn = e.mapId and (e.mapId - 50000) or 0
        local lbl
        if e.isAscension then
            local bn = e.bossName and (e.bossName:gsub("^%l",string.upper)) or nil
            lbl = "Ascension Tower "..mn..(bn and (" - "..bn) or "").." ["..(e.grade or "?").."]"
        else
            lbl = "Map "..mn.." - "..(MAP_NAMES[mn] or "Map "..mn).." - "..(RANK_LABEL[e.rank] or (e.spawnName or "?")).." (ID:"..e.raidId..")"
        end
        table.insert(RAID_ID_LIST,{
            label=lbl,id=e.raidId,rank=e.rank,mapId=e.mapId,
            spawnName=e.spawnName,isAscension=e.isAscension,bossName=e.bossName,
        })
    end
    if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end
end

--  TRIGGER ENTRY WAKEUP 
TriggerEntryWakeup = function()
    if _entryWakeupTimer then
        pcall(function() task.cancel(_entryWakeupTimer) end)
        _entryWakeupTimer = nil
    end
    _entryWakeupTimer = task.delay(_ENTRY_DEBOUNCE_SEC, function()
        _entryWakeupTimer = nil
        _ascMatchedThisCycle = false; _raidFallbackActive = false
        if RAID and RAID._listVisitedMaps then
            local _lc=0; for _ in pairs(RAID_LIVE) do _lc=_lc+1 end
            local _vc=0; for _ in pairs(RAID._listVisitedMaps) do _vc=_vc+1 end
            local _ae=true
            if _vc > 0 then
                for mapId in pairs(RAID._listVisitedMaps) do
                    for _,r in ipairs(RAID_ID_LIST) do
                        if r.mapId == mapId then _ae=false; break end
                    end
                    if not _ae then break end
                end
            end
            if _vc == 0 or _ae then
                for k in pairs(RAID._listVisitedMaps) do RAID._listVisitedMaps[k]=nil end
            end
        end
        local _hasAsc = false
        if ASC and ASC.running then
            for rid, ent in pairs(RAID_LIVE) do
                local rA = rid < 0 and math.abs(rid) or rid
                if rA == 937101 then continue end
                if ent.isAscension or rA >= 935001 or (ent.mapId and ent.mapId >= 50301 and ent.mapId <= 50326) then
                    _hasAsc = true; break
                end
            end
        end
        if _hasAsc then
            _eventOwner = "asc"; _raidFallbackActive = false
            if _ascWakeup then pcall(function() _ascWakeup:Fire() end) end
        else
            _eventOwner = "raid"; _raidFallbackActive = true
            if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
        end
    end)
end

--  WORKSPACE WATCHER (RE1001/RE1002 ChildAdded) 
local function _parseRaidEnterName(name)
    local n = name:match("^RaidEnter(%d+)$")
    return n and tonumber(n) or nil
end

local function _onRaidChildAdded(child, slotName)
    local mapNum = _parseRaidEnterName(child.Name)
    if not mapNum or mapNum < 1 or mapNum > 26 then return end
    local mapId = 50000 + mapNum
    if mapId == 50401 then return end
    for _, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId and not ent._tempEntry then return end
    end
    local tempKey = -(mapId)
    local _prevIsAsc=false; local _prevBn=nil; local _prevGr="?"
    if RAID_LIVE[tempKey] and RAID_LIVE[tempKey].isAscension then
        _prevIsAsc=true; _prevBn=RAID_LIVE[tempKey].bossName; _prevGr=RAID_LIVE[tempKey].grade or "?"
    end
    RAID_LIVE[tempKey] = {
        raidId=tempKey,mapId=mapId,spawnName=slotName or "RE1001",rank=0,grade=_prevGr,
        endTime=nil,_tempEntry=true,isAscension=_prevIsAsc,bossName=_prevBn,
        label=_prevIsAsc
            and ("Ascension Tower "..mapNum..(_prevBn and (" - "..(_prevBn:gsub("^%l",string.upper))) or "").." [".._prevGr.."]")
            or ("Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." [?]"),
    }
    RebuildRaidList()
    if TriggerEntryWakeup then TriggerEntryWakeup() end
end

local function _onRaidChildRemoved(child)
    local mapNum = _parseRaidEnterName(child.Name); if not mapNum then return end
    local mapId = 50000 + mapNum; local changed = false
    for rid, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId then RAID_LIVE[rid]=nil; changed=true end
    end
    if changed then RebuildRaidList() end
end

local function _watchRaidSlot(reFolder)
    if not reFolder then return end
    for _, child in ipairs(reFolder:GetChildren()) do _onRaidChildAdded(child, reFolder.Name) end
    reFolder.ChildAdded:Connect(function(child) _onRaidChildAdded(child, reFolder.Name) end)
    reFolder.ChildRemoved:Connect(function(child) _onRaidChildRemoved(child) end)
end

task.spawn(function()
    local ok,mapsF = pcall(function() return workspace:WaitForChild("Maps",15) end)
    if not ok or not mapsF then return end
    local ok2,mapF = pcall(function() return mapsF:WaitForChild("Map",10) end)
    if not ok2 or not mapF then return end
    local ok3,reF = pcall(function() return mapF:WaitForChild("RaidEnter",10) end)
    if not ok3 or not reF then return end
    local re1 = reF:WaitForChild("RE1001",5)
    local re2 = reF:WaitForChild("RE1002",5)
    _watchRaidSlot(re1); _watchRaidSlot(re2)
end)

--  CONNECT RAID LISTENERS (UpdateRaidInfo + EnterRaidsUpdateInfo) 
_WH = _WH or {}
_WH.raidConns = _WH.raidConns or {}

DisconnectRaidConns = function()
    for _, c in ipairs(_WH.raidConns) do pcall(function() c:Disconnect() end) end
    _WH.raidConns = {}
end

ConnectRaidListeners = function()
    DisconnectRaidConns()
    local _RE_Update = Remotes:FindFirstChild("UpdateRaidInfo")
    local _RE_Enter  = Remotes:FindFirstChild("EnterRaidsUpdateInfo")
    if _RE_Update then
        local conn = _RE_Update.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local action = data.action; local raidInfos = data.raidInfos
            if type(raidInfos) ~= "table" then return end
            if action == "RemoveRaidEnters" then
                for k, info in pairs(raidInfos) do
                    local raidId = type(k)=="number" and k or tonumber(k)
                    if raidId and raidId ~= 937101 then RAID_LIVE[raidId] = nil end
                end
                RebuildRaidList()
            else
                for k, info in pairs(raidInfos) do
                    repeat
                        if type(info) ~= "table" then break end
                        local raidId = info.raidId or (type(k)=="number" and k) or tonumber(k)
                        local mapId = info.mapId
                        if not raidId or not mapId then break end
                        if raidId == 937101 then break end
                        if mapId >= 50101 and mapId <= 50120 then mapId = mapId - 100 end
                        local _isAscMapId = (mapId >= 50301 and mapId <= 50326)
                        local _isAnniversary = (raidId == 937101)
                        local _isAscById = (raidId >= 935001) and not _isAnniversary
                        if not _isAscMapId and not _isAscById and (mapId < 50001 or mapId > 50020) then break end
                        if _isAscById and not _isAscMapId then
                            if mapId >= 50001 and mapId <= 50026 then mapId = mapId + 300 end
                            if mapId >= 50101 and mapId <= 50126 then mapId = mapId + 200 end
                            if mapId >= 50401 and mapId <= 50426 then mapId = mapId - 100 end
                            if mapId >= 50201 and mapId <= 50226 then mapId = mapId + 100 end
                            if not (mapId >= 50301 and mapId <= 50326) then
                                local _mn = math.max(1,math.min(26,math.abs(mapId-50300)))
                                mapId = 50300 + _mn
                            end
                            _isAscMapId = true
                        end
                        local mapNum = _isAscMapId and (mapId-50300) or (mapId-50000)
                        local spawnName = info.spawnName or "RE1001"
                        local rank = SPAWN_RANK[spawnName] or 0
                        local _grCacheKey = _isAscMapId and (-mapNum) or mapNum
                        local grade = (RAID_CONFIG_GRADE and RAID_CONFIG_GRADE[raidId])
                            or (_runeGradeCache and _runeGradeCache[_grCacheKey])
                            or (_ASC_CHAT_CACHE and _isAscMapId and _ASC_CHAT_CACHE[mapNum] and _ASC_CHAT_CACHE[mapNum].grade)
                            or "?"
                        local tempKey = -(mapId)
                        local _isAsc = false; local _bnAsc = nil
                        if raidId >= 935001 and not _isAnniversary then
                            _isAsc = true
                            if RAID_LIVE[tempKey] and RAID_LIVE[tempKey].bossName then _bnAsc = RAID_LIVE[tempKey].bossName
                            elseif RAID_LIVE[raidId] and RAID_LIVE[raidId].bossName then _bnAsc = RAID_LIVE[raidId].bossName end
                        elseif RAID_LIVE[tempKey] and RAID_LIVE[tempKey].isAscension then
                            _isAsc = true; _bnAsc = RAID_LIVE[tempKey].bossName
                        elseif RAID_LIVE[raidId] and RAID_LIVE[raidId].isAscension then
                            _isAsc = true; _bnAsc = RAID_LIVE[raidId].bossName
                        end
                        local _lbl = _isAsc
                            and ("Ascension Tower "..mapNum..(_bnAsc and (" - "..(_bnAsc:gsub("^%l",string.upper))) or "").." ["..grade.."]")
                            or ("Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." ["..grade.."](ID:"..raidId..")")
                        local entryData = {raidId=raidId,mapId=mapId,spawnName=spawnName,rank=rank,grade=grade,isAscension=_isAsc,bossName=_bnAsc,endTime=info.endTime,label=_lbl}
                        if RAID_LIVE[tempKey] then
                            if grade == "?" and RAID_LIVE[tempKey].grade and RAID_LIVE[tempKey].grade ~= "?" then
                                entryData.grade = RAID_LIVE[tempKey].grade
                            end
                            RAID_LIVE[raidId] = entryData; RAID_LIVE[tempKey] = nil
                        elseif not RAID_LIVE[raidId] then
                            RAID_LIVE[raidId] = entryData
                        else
                            RAID_LIVE[raidId].grade = grade; RAID_LIVE[raidId].rank = rank; RAID_LIVE[raidId].label = _lbl
                            if _isAsc then RAID_LIVE[raidId].isAscension = true; if _bnAsc then RAID_LIVE[raidId].bossName = _bnAsc end end
                        end
                    until true
                end
                RebuildRaidList()
                if TriggerEntryWakeup then TriggerEntryWakeup() end
            end
        end)
        table.insert(_WH.raidConns, conn)
    end
    if _RE_Enter then
        local conn = _RE_Enter.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            if data.slotIndex == nil and data.fromMapId == nil and data.mapId == nil then return end
            local evMapId = data.mapId or data.fromMapId or 0
            if evMapId >= 50300 then
                if evMapId >= 50301 and evMapId <= 50326 and ASC and (ASC.running or ASC.inMap) then
                    ASC.serverMapId = evMapId
                end
                return
            end
            if ASC.inMap then return end
            if data.slotIndex then RAID.slotIndex = data.slotIndex end
            if data.fromMapId then RAID.fromMapId = data.fromMapId end
            if data.mapId then
                local mid = data.mapId
                if mid >= 50101 and mid <= 50120 then RAID.serverMapId = mid end
            end
        end)
        table.insert(_WH.raidConns, conn)
    end
end

task.spawn(function() ConnectRaidListeners() end)

-- [FIX v1.lua PORT] Auto-reconnect kalau Remotes refresh (mis. setelah rejoin)
-- File 1 baris 10423-10434 punya ini, file 2 hilang -> listener mati setelah rejoin
-- [FIXED zombie] pakai flag _raidReconnectAlive agar loop mati kalau nil-kan flag
_raidReconnectAlive = true
task.spawn(function()
    local lastRef = Remotes:FindFirstChild("UpdateRaidInfo")
    while _raidReconnectAlive do
        task.wait(3)
        local cur = Remotes:FindFirstChild("UpdateRaidInfo")
        if cur ~= lastRef then
            lastRef = cur
            if cur then ConnectRaidListeners() end
        end
    end
end)
-- [FIX v1.lua PORT] RaidCollectAll - dipakai di STEP 5 StartRaidLoop tapi tidak pernah didefinisikan di file 2!
-- Port dari file 1 baris 11918-11969 (v73 FIX: scan agresif + retry)
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
                if RE.ExtraReward then
                    pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                end
                task.wait(0.05)
            end
        end
    end
    -- Round 1: scan semua folder reward standar
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
                if RE.ExtraReward then
                    pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                end
                task.wait(0.05)
            end
        end
    end
    -- Round 2: tunggu 1.5 detik lalu scan ulang (item spawn delayed)
    task.wait(1.5)
    for _, folderName in ipairs(folders) do
        collectFolder(workspace:FindFirstChild(folderName))
    end
end

-- [FIX v1.lua PORT] GetRaidEnemies - override/define ulang sebagai global tanpa guard
-- Port dari file 1 baris 11975-12048. Di file 2 sebelumnya hanya ada di "if not GetRaidEnemies" guard
-- yang bisa dilewati jika fungsi sudah ada dari script master (versi berbeda/salah)
-- Dengan mendefinisikan ulang di sini, kita pastikan versi yang BENAR selalu dipakai
function GetRaidEnemies()
    local list = {}
    local seen = {}
    local currentMapId = GetCurrentMapId()
    local _inNormalRaid = currentMapId and (currentMapId >= 50101 and currentMapId <= 50120)
    local _inAscTower   = currentMapId and (currentMapId >= 50301 and currentMapId <= 50326)
    -- [BUG FIX] Jangan scan saat di Siege, Dungeon, atau Anniversary
    if currentMapId then
        local _inSiege   = currentMapId >= 50201 and currentMapId <= 50204
        local _inAnniv   = currentMapId == 50401
        if _inSiege or _inAnniv then return list end
    end
    local playerPos
    pcall(function()
        local char = LP and LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        playerPos = hrp and hrp.Position or nil
    end)
    local activeMapId = _inNormalRaid and (RAID and RAID.serverMapId) or
        (not _inNormalRaid and not _inAscTower and RAID and RAID.inMap and RAID.serverMapId) or nil
    local spawnPos = activeMapId and RAID_SPAWN_POS and RAID_SPAWN_POS[activeMapId]
    local refPos = (playerPos and playerPos.Magnitude > 1) and playerPos
                or (spawnPos and spawnPos.Magnitude > 1) and spawnPos
                or nil
    local MAX_DIST = 4000
    local useDistFilter = refPos ~= nil
    local function addEnemy(e)
        if not e:IsA("Model") then return end
        if not e:IsDescendantOf(workspace) then return end
        local g = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid") or e:GetAttribute("Guid") or e:GetAttribute("GUID")
        if not g or seen[g] then return end
        local hrp = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
                 or e:FindFirstChild("Torso") or e:FindFirstChild("UpperTorso")
                 or e:FindFirstChildWhichIsA("BasePart")
        local hum = e:FindFirstChildOfClass("Humanoid")
        if not (hrp and hum) then return end
        if hum.Health <= 0 then return end
        if hum.MaxHealth <= 0 then return end
        local _ep = hrp.Position
        if _ep.Magnitude <= 10 then return end
        if _ep.Y < -200 or _ep.Y > 1500 then return end
        if not hrp:IsDescendantOf(workspace) then return end
        if useDistFilter then
            local dist = (_ep - refPos).Magnitude
            if dist > MAX_DIST then return end
        end
        seen[g] = true
        table.insert(list, {guid=g, hrp=hrp, model=e})
    end
    -- [FIX V51] Scan semua folder enemy standar
    for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
        local folder = workspace:FindFirstChild(fname)
        if folder then
            for _, e in ipairs(folder:GetChildren()) do addEnemy(e) end
        end
    end
    return list
end

_raidSessionStart = nil

function StopRaid()
    _raidInterrupt = false
    if MODE then MODE:Release("raid") end
    RAID.running = false; RAID.inMap = false
    ReleaseMapLock("raid")
    if RAID.thread then pcall(function() task.cancel(RAID.thread) end); RAID.thread = nil end
    if _raidWakeup then pcall(function() _raidWakeup:Destroy() end); _raidWakeup = nil end
    RAID.raidId=nil; RAID.raidMapId=nil; RAID.serverMapId=nil; RAID.fromMapId=nil
    RAID.slotIndex=2; RAID._raidDone=false; RAID._cooldownActive=false
    RAID_LIVE={}; _defaultRRIdx=0; RAID_ID_LIST={}
    if RAID._listVisitedMaps then for k in pairs(RAID._listVisitedMaps) do RAID._listVisitedMaps[k]=nil end end
    if _runeGradeCache then for k in pairs(_runeGradeCache) do _runeGradeCache[k]=nil end end
    if RebuildRaidList then pcall(RebuildRaidList) end
end

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
    if RAID.dot then RAID.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100) end
end

function RaidCounterUpdate()
    if RAID.suksesLbl then RAID.suksesLbl.Text = tostring(RAID.sukses) end
end

function AscStatusUpdate(msg, color)
    if ASC.statusLbl then
        ASC.statusLbl.Text = msg
        ASC.statusLbl.TextColor3 = color or Color3.fromRGB(255,200,100)
    end
    if ASC.dot then ASC.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100) end
end

end -- end do: AUTO RAID DATA & STATE


-- ============================================================================
-- AUTO RAID: StartRaidLoop (port dari 1.lua baris 12218-13571)
-- ============================================================================
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
 pcall(function()
 while RAID.running do
 repeat

 -- [v252] Cek semua interrupt via MODE dispatcher

 -- [FIX] Cek ST2 (Single/Ascension Tower) - pause Auto Raid selama Tower berjalan
 if ST2 and (ST2.running or ST2.inMap) then
 RAID.inMap = false
 RaidStatusUpdate("[||] Tower aktif - Auto Raid pause...", Color3.fromRGB(255,140,0))
 while ST2 and (ST2.running or ST2.inMap) and RAID.running do
 task.wait(0.5)
 end
 if not RAID.running then break end
 RaidStatusUpdate("> Tower selesai - lanjut raid...", C.ACC3)
 task.wait(0.1)
 end

 -- [v56 FIX] Guard RAID: tunggu fitur lain selesai
 -- ASC: RAID boleh lolos guard HANYA jika ResolveAscEntry() = nil (tidak ada Tower match)
 -- Jika ASC.inMap = true (di Tower) -> tetap tunggu ASC keluar dulu sebelum cek ResolveAscEntry
 do
  -- RAID pause selama _ascBusy=true (ASC sedang inMap atau cooldown)
  -- _ascBusy diset false oleh ASC hanya saat benar-benar tidak ada Tower lagi
  local _rGuard = 0
  while RAID.running and _rGuard < 90 do
   -- Cek ASC busy dulu (prioritas)
   if ASC and ASC.running and _ascBusy then
    RaidStatusUpdate("[||] ASC aktif - RAID standby...", Color3.fromRGB(180,100,255))
    task.wait(0.5); _rGuard = _rGuard + 0.5
    continue
   end
   -- Cek fitur lain (Siege, Dungeon)
   local _busy, _who = IsAnyMapActive()
   local _selfBusy = (_who == "raid")
   if not _busy or _selfBusy then break end
   RaidStatusUpdate("[||] Tunggu "..(_who or "?").." selesai dulu...", Color3.fromRGB(255,140,0))
   task.wait(0.5); _rGuard = _rGuard + 0.5
  end
  if not RAID.running then break end
 end

        -- Prioritas: Rune Map + Pick Rank > Rune Map saja > Pick Rank > Difficulty
 -- Selalu baca RAID.runeEnabled / runeGrades / runeMapTarget live
 -- sehingga kalau user ganti setting di tengah, iterasi berikutnya langsung ikut

-- [RAID LIST ENTRY] ResolveEntryFromList
-- Resolver independen: bypass manual mode, scan entry dari bawah ke atas.
-- Return: raidEntry yang match, atau nil jika tidak ada yg match (caller fallback ke Easy)
local function ResolveEntryFromList()
    if not RAID.listEnabled then return nil end
    if #RAID.listEntries == 0 then return nil end
    if #RAID_ID_LIST == 0 then return nil end

    -- Filter Ascension keluar (sama seperti ResolveEntry)
    local normalList = {}
    for _, r in ipairs(RAID_ID_LIST) do
        local isAsc = r.isAscension == true or (r.id and r.id >= 935001)
        if not isAsc then
            local live = r.id and RAID_LIVE[r.id]
            if not (live and live.isAscension == true) then
                table.insert(normalList, r)
            end
        end
    end
    if #normalList == 0 then return nil end

    -- Helper ambil grade terbaik
    local function _getGrade(r)
        return GetBestGrade(r.mapId - 50000, false)
    end

    -- Kumpulkan semua lobby yang match dari semua entry sekaligus
    local function collectAllMatched(skipVisited)
        local allMatched = {}
        local seen = {}
        for i = 1, #RAID.listEntries do
            local ent = RAID.listEntries[i]
            local hasMaps  = next(ent.maps)  ~= nil
            local hasRanks = next(ent.ranks) ~= nil
            for _, r in ipairs(normalList) do
                if seen[r.mapId] then continue end
                -- Skip map yang sudah dikunjungi di siklus ini (kecuali sedang reset)
                if skipVisited and RAID._listVisitedMaps[r.mapId] then continue end
                local mn = r.mapId - 50000
                local mapsOk = (not hasMaps) or ent.maps[mn]
                if not mapsOk then continue end
                if hasRanks then
                    local grade = _getGrade(r)
                    if grade and ent.ranks[grade] then
                        table.insert(allMatched, r)
                        seen[r.mapId] = true
                    end
                else
                    table.insert(allMatched, r)
                    seen[r.mapId] = true
                end
            end
        end
        return allMatched
    end

    -- Tahap 1: cari match yang belum dikunjungi
    local allMatched = collectAllMatched(true)

    -- Tahap 2: kalau semua sudah dikunjungi -> reset visited dan loop ulang dari awal
    if #allMatched == 0 then
        for k in pairs(RAID._listVisitedMaps) do RAID._listVisitedMaps[k] = nil end
        allMatched = collectAllMatched(true)
    end

    if #allMatched == 0 then return nil end

    -- Pilih mapId terkecil dari semua yang match
    table.sort(allMatched, function(a, b) return a.mapId < b.mapId end)
    return allMatched[1]
end

local function ResolveEntry()
                if #RAID_ID_LIST == 0 then return nil end

                -- [LIST FALLBACK v3] Exclude {1,3,8} berlaku di SEMUA tahap — didefinisikan di GLOBAL_EXCLUDE bawah
                -- [RAID LIST ENTRY] Cek List Entry dulu sebelum logika normal
                -- [LIST FALLBACK v3] Kalau List Entry gagal match:
                --   Stage 2 → jalankan Pick Mode aktif (bukan langsung Easy)
                --   Stage 3 → Easy fallback terakhir, exclude {1,3,8}
                --   Kalau Stage 3 juga nil → return nil (Waiting loop)
                local _listFailed = false
                if RAID.listEnabled and #RAID.listEntries > 0 then
                    local listResult = ResolveEntryFromList()
                    if listResult then
                        return listResult
                    end
                    -- List Entry tidak match -> tandai, lanjut ke Pick Mode aktif (fall-through)
                    _listFailed = true
                end

                -- [v46] Auto Raid selalu filter Normal saja (Ascension ditangani Auto Ascension)
                local function _ascFilter(entry)
                    if not entry then return false end
                    -- Cek flag isAscension dari entry RAID_ID_LIST itu sendiri
                    if entry.isAscension == true then return false end
                    -- Cek raidId range Ascension Tower (confirmed SimpleSPY: 936501+)
                    -- Server pakai raidId >= 935001 untuk semua Ascension Tower event
                    if entry.id and entry.id >= 935001 then return false end
                    -- Cek dari RAID_LIVE via id entry
                    local live = entry.id and RAID_LIVE[entry.id]
                    if live and live.isAscension == true then return false end
                    -- Safety net: cek RAID_LIVE[-(mapId)] - entry chat Ascension yang belum di-resolve
                    if entry.mapId then
                        local chatKey = -(entry.mapId)
                        local chatEnt = RAID_LIVE[chatKey]
                        if chatEnt and chatEnt.isAscension == true then return false end
                    end
                    -- Lolos semua cek = RAID Normal
                    return true
                end
                local _now0 = os.time()
                local _pruned0 = false
                for rid, ent in pairs(RAID_LIVE) do
                    if ent.endTime and ent.endTime < (_now0 - 10) then
                        RAID_LIVE[rid] = nil; _pruned0 = true
                    end
                end
                if _pruned0 then
                    if RebuildRaidList then pcall(RebuildRaidList) end
                end
                if #RAID_ID_LIST == 0 then return nil end

                local pm = RAID.pickMode or "default"
                local runeOn = RAID.runeEnabled
                local runeTarget = runeOn and RAID.runeMapTarget or 0
                local hasPick = (pm == "byrank" or pm == "manual") and next(RAID.runeGrades) ~= nil

                -- [FIX] Helper grade yang sadar Ascension (pakai key cache negatif untuk AT)
                local function _getGrade(r)
                    return GetBestGrade(r.mapId - 50000, r.isAscension == true)
                end

                -- [Ascension Mode] Filter RAID_ID_LIST sesuai mode sebelum dipakai pick mode apapun
                local _filteredList = {}
                for _, r in ipairs(RAID_ID_LIST) do
                    if _ascFilter(r) then
                        table.insert(_filteredList, r)
                    end
                end
                -- Gunakan filtered list sebagai sumber utama semua pick mode
                local RAID_ID_LIST = _filteredList

                local function pickLowest(list)
                    table.sort(list, function(a, b) return a.mapId < b.mapId end)
                    return list[1]
                end

                -- [LIST FALLBACK v3] GLOBAL_EXCLUDE: semua tahap dan semua mode exclude {1,3,8}
                -- Dideklarasikan di sini agar bisa dipakai Manual mode dan pickByDiff
                local GLOBAL_EXCLUDE = {[1]=true, [3]=true, [8]=true}

-- [LOGIKA MANUAL MODE DEWA]
                if pm == "manual" then
                    RAID.manualMatchMode = "none" -- Status: "primary", "updown", atau "fallback"
                    local valid_raids = {}
                    local hasPreferMaps = next(RAID.preferMaps) ~= nil

                    -- 1. Wadah/Gerbang: Ambil semua map yang diizinkan
                    for _, r in ipairs(RAID_ID_LIST) do
                        local mn = r.mapId - 50000
                        if not hasPreferMaps or RAID.preferMaps[mn] then
                            table.insert(valid_raids, r)
                        end
                    end
                    if #valid_raids == 0 then return nil end

                    -- Helper: Sort dari Rank tertinggi ke terendah
                    local function sortHighestRank(list)
                        table.sort(list, function(a, b)
                            local ga = _getGrade(a) or "?"
                            local gb = _getGrade(b) or "?"
                            local ra = GRADE_RANK[ga] or 0
                            local rb = GRADE_RANK[gb] or 0
                            if ra == rb then return a.mapId < b.mapId end 
                            return ra > rb 
                        end)
                    end

                    -- 2. TAHAP 1: Cari kecocokan Preferred Rank
                    local matched = {}
                    local hasPreferRank = next(RAID.runeGrades) ~= nil
                    if hasPreferRank then
                        for _, r in ipairs(valid_raids) do
                            local grade = _getGrade(r)
                            if grade and RAID.runeGrades[grade] then
                                table.insert(matched, r)
                            end
                        end
                    end

                    if #matched > 0 then
                        -- MATCH UTAMA KETEMU
                        sortHighestRank(matched)
                        RAID.manualMatchMode = "primary"
                        return matched[1]
                    end

                    -- 3. TAHAP 2: Jika Preferred Rank GAGAL, cari Target UP/DOWN di lobi!
                    if RAID.updownEnabled and RAID.updownTargetGrade then
                        local udMatched = {}
                        for _, r in ipairs(valid_raids) do
                            local grade = _getGrade(r)
                            if grade == RAID.updownTargetGrade then
                                table.insert(udMatched, r)
                            end
                        end
                        if #udMatched > 0 then
                            -- KETEMU MANGSA UP/DOWN!
                            sortHighestRank(udMatched)
                            RAID.manualMatchMode = "updown"
                            return udMatched[1]
                        end
                    end

                    -- 4. TAHAP 3: "Jangan Maksa Dong!" -> Fallback murni ke map terkecil
                    -- [LIST FALLBACK v3] Exclude {1,3,8} di fallback Manual Mode.
                    RAID.manualMatchMode = "fallback"
                    local manualFiltered = {}
                    for _, r in ipairs(valid_raids) do
                        local mn = r.mapId - 50000
                        if not GLOBAL_EXCLUDE[mn] then table.insert(manualFiltered, r) end
                    end
                    if #manualFiltered == 0 then return nil end
                    table.sort(manualFiltered, function(a, b) return a.mapId < b.mapId end)
                    return manualFiltered[1]
                end

                -- [LIST FALLBACK v3] Semua mode dan semua fallback pakai GLOBAL_EXCLUDE {1,3,8}
                -- (EASY_EXCLUDE_MAPS / DEFAULT_EXCLUDE_MAPS dihapus — digantikan GLOBAL_EXCLUDE di atas)

                local function pickByDiff(list)
                    if #list == 0 then return nil end
                    -- [LIST FALLBACK v3] Filter exclude {1,3,8} berlaku di SEMUA mode
                    local filtered = {}
                    for _, r in ipairs(list) do
                        local mn = r.mapId - 50000
                        if not GLOBAL_EXCLUDE[mn] then table.insert(filtered, r) end
                    end
                    if #filtered == 0 then return nil end
                    if pm == "easy" then
                        table.sort(filtered, function(a, b) return a.mapId < b.mapId end)
                        return filtered[1]
                    elseif pm == "hard" then
                        table.sort(filtered, function(a, b) return a.mapId > b.mapId end)
                        return filtered[1]
                    elseif pm == "default" then
                        local maps1to8 = {}
                        for _, r in ipairs(filtered) do
                            local mn = r.mapId - 50000
                            if mn >= 1 and mn <= 8 then
                                table.insert(maps1to8, r)
                            end
                        end
                        if #maps1to8 == 0 then return nil end
                        table.sort(maps1to8, function(a, b) return a.mapId < b.mapId end)
                        _defaultRRIdx = _defaultRRIdx + 1
                        if _defaultRRIdx > #maps1to8 then _defaultRRIdx = 1 end
                        return maps1to8[_defaultRRIdx]
                    elseif pm == "byrank" then
                        table.sort(filtered, function(a, b)
                            local ga = _getGrade(a) or "?"
                            local gb = _getGrade(b) or "?"
                            local ra = GRADE_RANK[ga] or 0
                            local rb = GRADE_RANK[gb] or 0
                            if ra == rb then return a.mapId < b.mapId end
                            return ra > rb
                        end)
                        return filtered[1]
                    elseif pm == "bymap" then
                        table.sort(filtered, function(a, b) return a.mapId < b.mapId end)
                        for _, r in ipairs(filtered) do
                            if RAID.preferMaps[r.mapId - 50000] then return r end
                        end
                        return filtered[1]
                    end
                    -- fallback: terkecil dari filtered
                    table.sort(filtered, function(a, b) return a.mapId < b.mapId end)
                    return filtered[1]
                end

                if not IsRaidLiveInGame() then
                    RAID_LIVE = {}; RAID_ID_LIST = {}; _defaultRRIdx = 0
                    if RebuildRaidList then pcall(RebuildRaidList) end
                    return nil
                end

                if hasPick then
                    local matched2 = {}
                    for _, r in ipairs(RAID_ID_LIST) do
                        local grade = _getGrade(r)
                        if grade and RAID.runeGrades[grade] == true then table.insert(matched2, r) end
                    end
                    if #matched2 > 0 then
                        local chosen = pickByDiff(matched2)
                        if chosen then return chosen end
                    end
                    if pm == "byrank" then
                        -- byrank tidak ketemu grade match -> kalau _listFailed lanjut ke Easy final
                        -- kalau normal -> return nil (Waiting)
                        if not _listFailed then return nil end
                    end
                end

                if pm == "bymap" and next(RAID.preferMaps) ~= nil then
                    local mapMatched = {}
                    for _, r in ipairs(RAID_ID_LIST) do
                        if RAID.preferMaps[r.mapId - 50000] then table.insert(mapMatched, r) end
                    end
                    if #mapMatched > 0 then return pickLowest(mapMatched) end
                    -- bymap tidak ketemu preferred map -> kalau _listFailed lanjut ke Easy final
                    -- kalau normal -> return nil (Waiting)
                    if not _listFailed then return nil end
                end

                -- [LIST FALLBACK v3] Stage 2: Pick Mode aktif
                -- Kalau _listFailed=true (List Entry gagal): jalankan Pick Mode aktif dulu.
                -- Kalau Pick Mode juga tidak ketemu -> Stage 3: Easy final exclude {1,3,8} -> Waiting.
                -- Kalau _listFailed=false (List Entry OFF): perilaku normal, pakai Pick Mode.
                local pickResult = pickByDiff(RAID_ID_LIST)
                if pickResult then return pickResult end

                -- [LIST FALLBACK v3] Stage 3: Easy final (hanya dicapai kalau pickByDiff nil)
                -- Exclude {1,3,8} — kalau semua raid yang tersedia hanya Map 1/3/8 -> return nil -> Waiting
                local easyFinal = {}
                for _, r in ipairs(RAID_ID_LIST) do
                    local mn = r.mapId - 50000
                    if not GLOBAL_EXCLUDE[mn] then table.insert(easyFinal, r) end
                end
                if #easyFinal == 0 then return nil end  -- hanya 1/3/8 tersedia -> Waiting
                table.sort(easyFinal, function(a, b) return a.mapId < b.mapId end)
                return easyFinal[1]
            end
 -- [v238 FIX] Cek apakah ada raid yang benar-benar aktif di game sekarang
 -- Jika tidak, langsung masuk waiting loop tanpa coba masuk
 -- Ini mencegah "tindakan palsu" (TP ke enemy random, loop tak berguna)
 -- ketika Rune Map/Pick Rank di-OFF lalu di-ON lagi saat raid sudah habis
 if not IsRaidLiveInGame() then
 RAID.raidId = nil
 RAID.raidMapId = nil
 raidEntry = nil
 -- Paksa reset RAID_LIVE agar ResolveEntry tidak pakai data stale
 RAID_LIVE = {}
 RAID_ID_LIST = {}
 _defaultRRIdx = 0 -- reset RR saat RAID habis
 if RebuildRaidList then pcall(RebuildRaidList) end
 end

 local raidEntry = ResolveEntry()
 -- [v62 RINO/RINI FIX] Keputusan siapa yang "dipanggil" sudah dibuat di TriggerEntryWakeup.
 -- Jika _eventOwner == "asc" berarti siklus ini giliran ASC (Rino), RAID (Rini) tetap duduk.
 -- Fallback: kalau _eventOwner belum diset (nil), pakai cek ResolveAscEntry lama.
 if raidEntry and ASC and ASC.running then
  if _eventOwner == "asc" then
   raidEntry = nil -- giliran ASC, RAID standby
  elseif _eventOwner == nil and ResolveAscEntry and ResolveAscEntry() then
   raidEntry = nil -- belum ada keputusan, cek manual
  end
 end

 while RAID.running and not raidEntry do
 ForceRescanRaidEnter()
 raidEntry = ResolveEntry()
 -- [v62 RINO/RINI FIX] Cek ulang _eventOwner di setiap iterasi waiting loop
 if raidEntry and ASC and ASC.running then
  if _eventOwner == "asc" then
   raidEntry = nil
  elseif _eventOwner == nil and ResolveAscEntry and ResolveAscEntry() then
   raidEntry = nil
  end
 end
 if not raidEntry then
 -- Prune expired entries
 local _now2 = os.time()
 local _pruned2 = 0
 for rid, ent in pairs(RAID_LIVE) do
 if ent.endTime and ent.endTime < (_now2 - 10) then
 RAID_LIVE[rid] = nil; _pruned2 = _pruned2 + 1
 end
 end
 if _pruned2 > 0 then
 if RebuildRaidList then pcall(RebuildRaidList) end
 end
 -- [v262 FIX] Status label sesuai mode aktif (pickMode aware)
 local _pm = RAID.pickMode
 if not IsRaidLiveInGame() then
 RaidStatusUpdate("Empty RAID - Waiting new RAID", Color3.fromRGB(160,100,60))
 elseif ASC and ASC.running and (_eventOwner == "asc" or (ResolveAscEntry and ResolveAscEntry())) then
 -- [v62 RINO/RINI FIX] ASC ON dan siklus ini giliran ASC -> RAID standby
 RaidStatusUpdate("[||] ASC Ascension aktif & ada Tower match - Normal Raid standby...", Color3.fromRGB(180,100,255))
 elseif _pm == "byrank" and next(RAID.runeGrades) ~= nil then
 local _gr = {}
 for _,g in ipairs(GRADE_LIST) do if RAID.runeGrades[g] then table.insert(_gr,g) end end
 RaidStatusUpdate("Waiting Rank: ["..table.concat(_gr,"] [").."]...", Color3.fromRGB(200,120,255))
 elseif _pm == "bymap" and next(RAID.preferMaps) ~= nil then
 local _ms = {}
 for mn in pairs(RAID.preferMaps) do table.insert(_ms,"Map "..mn) end
 table.sort(_ms)
 RaidStatusUpdate("Waiting Map: "..table.concat(_ms,", ").."...", Color3.fromRGB(100,200,100))
 elseif RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 20 and next(RAID.runeGrades) ~= nil then
 RaidStatusUpdate("Waiting grade cocok -> override Map " .. RAID.runeMapTarget .. "...", Color3.fromRGB(200,140,255))
 elseif RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 20 then
 RaidStatusUpdate("Waiting raid apapun -> override Map " .. RAID.runeMapTarget .. "...", Color3.fromRGB(147,197,253))
 elseif next(RAID.runeGrades) ~= nil then
 RaidStatusUpdate("Waiting grade cocok [" .. RAID.difficulty .. "]...", Color3.fromRGB(200,255,150))
 else
 RaidStatusUpdate("Waiting raid [" .. (_pm ~= "default" and _pm or RAID.difficulty) .. "]...", Color3.fromRGB(255,200,60))
 end
 -- [FIX v256] Wakeup CEPAT: poll 0.05s, max 0.5s (bukan 1s)
 if _raidInterrupt and not RAID.running then _raidInterrupt = false end
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


 -- [v238 FIX] Double-check sebelum masuk: apakah raid di raidEntry
 -- masih valid di server saat ini?
 -- [v245 FIX] Longgarkan: kalau raidEntry ada di RAID_LIVE dan tidak ada endTime
 -- (server tidak kirim endTime), anggap masih valid - jangan blokir masuk
 local _preCheck_ok = true
 if not raidEntry then
 _preCheck_ok = false
 elseif not RAID_LIVE[raidEntry.id] then
 _preCheck_ok = false
 elseif not IsRaidLiveInGame() then
 -- Satu kesempatan lagi: kalau entry ada tapi tidak ada endTime, izinkan
 local _ent = RAID_LIVE[raidEntry.id]
 if _ent and not _ent.endTime then
 _preCheck_ok = true -- server tidak kirim endTime = anggap valid
 else
 _preCheck_ok = false
 end
 end

 if not _preCheck_ok then
 _raidInterrupt = false; RAID.inMap = false; ReleaseMapLock("raid"); MODE:Release("raid")
 RaidStatusUpdate("Raid expired sebelum masuk - tunggu raid baru...", Color3.fromRGB(255,100,60))
 task.wait(2)
 break
 end

 -- [v252] Pause Mass Attack via MODE dispatcher
 
 -- [HUKUM PRIORITAS TERTINGGI - ANTI CULIK]
 -- Jika Siege / Dungeon sedang jalan, RAID WAJIB PAUSE!
 if (SIEGE and (SIEGE.inMap or SIEGE.teleporting)) then
     RaidStatusUpdate("[!] PAUSE: Menunggu Siege Selesai...", Color3.fromRGB(255, 100, 100))
     task.wait(2)
     break
 end
 
 -- [v54] HUKUM PRIORITAS ASC > RAID NORMAL (diperkuat dari v53)
 -- Kasus 1: ASC ON + ada Tower match sekarang -> RAID Normal standby
 -- Kasus 2: ASC ON + sudah pernah dominasi event ini (dominatedThisEvent) -> RAID Normal
 --          tetap diblokir meskipun Tower saat ini tidak match, sampai event benar-benar habis
 -- Kasus 3: ASC ON + tidak pernah dominasi event ini + tidak ada Tower match -> RAID boleh (fallback)
 -- Kasus 4: ASC OFF -> RAID jalan penuh tanpa batasan
 -- [v56 FIX] RAID standby selama ASC.running=true DAN masih ada Tower match di event saat ini
 -- Tidak diblokir oleh ASC.inMap atau _ascDominatedThisEvent
 -- RAID hanya boleh jalan kalau ResolveAscEntry() = nil (tidak ada Tower match sama sekali)
 if ASC and ASC.running then
     local _ascEntry = ResolveAscEntry and ResolveAscEntry()
     if _ascEntry then
         RaidStatusUpdate("[||] AUTO RAID ASCENSION aktif & ada Tower match - Normal Raid standby...", Color3.fromRGB(180,100,255))
         task.wait(1)
         break
     end
     -- ResolveAscEntry() = nil -> tidak ada Tower match -> RAID boleh jalan sebagai fallback
     -- [v61 CYCLEFIX] Tandai bahwa RAID jalan sebagai fallback di siklus ini
     -- ASC harus standby dan tidak boleh mencuri sampai siklus baru datang
     _raidFallbackActive = true
 end

 local currentWm = workspace:GetAttribute("MapId") or 0
 -- [FIX] Blokir Auto Raid saat di dalam Map Siege atau Dungeon
 if (currentWm >= 50201 and currentWm <= 50204) then
     task.wait(2)
     break
 end
 -- [v56 FIX] Jika player masih secara fisik di dalam Tower (seharusnya tidak terjadi karena ASC.inMap sudah cover)
 -- Tapi sebagai safety net: tunggu sampai keluar, jangan langsung break
 if currentWm >= 50301 and currentWm <= 50326 then
     RaidStatusUpdate("[||] Masih di dalam Ascension Tower - tunggu keluar...", Color3.fromRGB(180,100,255))
     while (workspace:GetAttribute("MapId") or 0) >= 50301 and RAID.running do
         task.wait(0.5)
     end
     if not RAID.running then break end
 end
 -- [FIX] Pause Auto Raid jika ST2 (Single Tower) sedang aktif di dalam map
 if ST2 and ST2.inMap then
     RaidStatusUpdate("[||] Tower aktif - Auto Raid pause...", Color3.fromRGB(255,140,0))
     while ST2 and ST2.inMap and RAID.running do
         task.wait(0.5)
     end
     if not RAID.running then break end
     RaidStatusUpdate("> Tower selesai - lanjut raid...", C.ACC3)
     task.wait(0.1)
 end

 -- Siege cek tetap pakai flag lama (siege sudah pakai MODE juga via alias)
 -- Tunggu SIEGE selesai dulu jika sedang inMap
 if SIEGE and (SIEGE.inMap or SIEGE.teleporting) then
     RaidStatusUpdate("[||] Tunggu SIEGE selesai...", Color3.fromRGB(255,180,50))
     local _ws = 0
     while (SIEGE.inMap or SIEGE.teleporting) and RAID.running and _ws < 120 do
         task.wait(0.5); _ws = _ws + 0.5
     end
     if not RAID.running then break end
 end

 -- Tunggu ASC selesai dulu jika sedang inMap
 if ASC and ASC.inMap then
     RaidStatusUpdate("[||] Tunggu ASC selesai...", Color3.fromRGB(255,180,50))
     local _wa = 0
     while ASC.inMap and RAID.running and _wa < 120 do
         task.wait(0.5); _wa = _wa + 0.5
     end
     if not RAID.running then break end
 end

 _raidInterrupt = true -- signal MA untuk pause (MA cek di guard tiap iterasi)

 -- [v52 FIX] Atomic lock: cegah ASC masuk bersamaan saat RAID baru lolos guard
 do
  local _rLockWait = 0
  while RAID.running and _rLockWait < 15 do
   if TryClaimMapLock("raid") then break end
   RaidStatusUpdate("[||] Tunggu slot masuk map bebas...", Color3.fromRGB(200,200,100))
   task.wait(0.2); _rLockWait = _rLockWait + 0.2
  end
  if not RAID.running then ReleaseMapLock("raid"); break end
 end
 
-- [v262 FIX] JANGAN set inMap=true dulu sebelum raidMapId di-assign
                    -- [FIX Ascension] raidEntry.id negatif = Ascension entry (chat-only id)
                    -- CreateRaidTeam butuh raidId positif dari server -> ambil dari RAID_LIVE jika tersedia
                    local _resolvedRaidId = raidEntry.id
                    if raidEntry.isAscension and _resolvedRaidId < 0 then
                        -- Cari raidId positif dari RAID_LIVE entry yang sama mapId & isAscension
                        for _rid, _ent in pairs(RAID_LIVE) do
                            if _ent.isAscension and _ent.mapId == raidEntry.mapId and _rid > 0 then
                                _resolvedRaidId = _rid; break
                            end
                        end
                        -- Jika masih negatif: pakai abs (fallback darurat, mungkin tidak work tapi tidak crash)
                        if _resolvedRaidId < 0 then _resolvedRaidId = math.abs(_resolvedRaidId) end
                    end
                    RAID.raidId = _resolvedRaidId
                    RAID.raidMapId = raidEntry.mapId
                    RAID.inMap = true
                    ReleaseMapLock("raid") -- [v52 FIX] inMap=true sudah di-set, IsAnyMapActive sudah cover
                    if RAID.updateActiveLabel then pcall(RAID.updateActiveLabel) end


                    
                    RAID.slotIndex = 2
                    if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end
                    
                    local mn = raidEntry.mapId - 50000
                    if RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 20 then mn = RAID.runeMapTarget end
                    local mapLabel = MAP_NAMES[mn] or ("Map " .. mn)

                    local _liveEntry = RAID_LIVE[RAID.raidId]
                    if not _liveEntry then
                        _raidInterrupt = false; RAID.inMap = false; MODE:Release("raid")
                        task.wait(1); break
                    end
                    RAID.serverMapId = nil
                    if not RAID.running then break end

                    -- [FUNGSI DEWA: Eksekusi UP/DOWN Rank]
                    local function DoUpDownOverride()
                        if not RAID.updownEnabled or not RE.UseRaidItem then return end
                        local dir = RAID.updownDir or "up"  -- [FIX v1.lua] default "up" jika nil (file 1 baris 12863)
                        local udId = (dir == "up") and 10270 or 10271
                        RaidStatusUpdate("[~] Override: "..dir:upper(), Color3.fromRGB(200,140,255))
                        pcall(function() RE.UseRaidItem:FireServer(udId) end)
                        task.wait(0.3)
                    end

                    -- [LOGIKA KEPUTUSAN 4 HUKUM]
                    local pm = RAID.pickMode or "default"
                    local useRune = false
                    local useUpDown = false
                    
                    if pm == "manual" then
                        if RAID.manualMatchMode == "primary" then
                            -- TAHAP 1: MATCH PREFERRED RANK -> HANYA RUNE YANG BOLEH JALAN!
                            if RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 20 then 
                                -- [SISTEM ANTI-MUBAZIR]
                                if (raidEntry.mapId - 50000) == RAID.runeMapTarget then
                                    useRune = false -- Map sudah sama, simpan Rune-nya!
                                else
                                    useRune = true 
                                end
                            else
                                useRune = false
                            end
                            useUpDown = false -- << MUTLAK MATI DI TAHAP 1 (Gak boleh ikut campur!)
                            
                        elseif RAID.manualMatchMode == "updown" then
                            -- TAHAP 2: MATCH UP/DOWN TARGET -> Rune Mati, UpDown Jalan!
                            useRune = false
                            useUpDown = true
                            
                        elseif RAID.manualMatchMode == "fallback" then
                            -- TAHAP 3: JANGAN MAKSA! Keduanya mati.
                            useRune = false
                            useUpDown = false
                        end
                    else
                        -- Mode selain Manual (ByRank, dll)
                        if RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 20 then 
                            if (raidEntry.mapId - 50000) == RAID.runeMapTarget then
                                useRune = false
                            else
                                useRune = true 
                            end
                        end
                        if RAID.updownEnabled then useUpDown = true end
                    end

                    -- [EKSEKUSI]
                    if useRune then
                        -- >>> MODE RUNE MAP OVERRIDE <<<
                        local targetMap = RAID.runeMapTarget
                        RaidStatusUpdate("Create Team...", C.ACC2)
                        if not RAID.fromMapId then RAID.fromMapId = RAID.raidMapId end
                        if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end) end
                        task.wait(0.2)
                        
                        -- Prioritas: Rune digunakan dulu, setelah itu langsung UpDown!
                        if useUpDown then DoUpDownOverride() end
                        
                        RaidStatusUpdate("Use Item (Map "..targetMap..")...", Color3.fromRGB(255,200,60))
                        local RUNE_IDS = {
                            [1]=10265,[2]=10266,[3]=10267,[4]=10268,[5]=10269, [6]=10314,[7]=10315,[8]=10316,
                            [9]=10357,[10]=10358,[11]=10359,[12]=10360,[13]=10361, [14]=10362,[15]=10363,[16]=10364,[17]=10365,[18]=10366,
                            [19]=10367,[20]=10368,
                        }
                        local itemId = RUNE_IDS[targetMap]
                        if itemId and RE.UseRaidItem then
                            pcall(function() RE.UseRaidItem:FireServer(itemId) end)
                        end
                        task.wait(0.3)
                        
                        if RE.StartChallengeRaidMap then
                            local _runeMapId = 50100 + targetMap
                            pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = _runeMapId}) end)
                        end
                        
                        local _wR = 0
                        while RAID.serverMapId == nil and _wR < 10 and RAID.running do
                            task.wait(0.1); _wR = _wR + 0.1
                        end
                        
                        -- Fallback jika tiket Rune Map ternyata habis di inventory
                        if RAID.serverMapId == nil and RAID.running then
                            RaidStatusUpdate("[!] Material Kosong - Fallback...", Color3.fromRGB(255,140,0))
                            local _fbTargetMapId = raidEntry.mapId + 100
                            if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end) end
                            task.wait(0.2)
                            if RE.StartChallengeRaidMap then pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = _fbTargetMapId}) end) end
                            local _wFb = 0; while RAID.serverMapId == nil and _wFb < 5 and RAID.running do task.wait(0.05); _wFb = _wFb + 0.05 end
                        end
                        
                    else
                        -- >>> MODE NORMAL / FALLBACK <<<
                        local targetMapId = raidEntry.mapId + 100
                        RaidStatusUpdate("Enter Map " .. (targetMapId-50100) .. "...", C.ACC3)

                        if not RAID.fromMapId then RAID.fromMapId = RAID.raidMapId end
                        if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end) end
                        task.wait(0.2)
                        if not RAID.running then break end

                        if useUpDown then DoUpDownOverride() end

                        local _cfail = false
                        local _cfConn
                        local _cfRe = Remotes:FindFirstChild("ChallengeRaidsFail")
                        if _cfRe then _cfConn = _cfRe.OnClientEvent:Connect(function() _cfail = true end) end

                        if RE.StartChallengeRaidMap then
                            pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = targetMapId}) end)
                        end

                        local _w2 = 0
                        while RAID.serverMapId == nil and _w2 < 5 and RAID.running and not _cfail do task.wait(0.05); _w2 = _w2 + 0.05 end

                        if _cfConn then pcall(function() _cfConn:Disconnect() end) end
                        if _cfail then
                            RAID_LIVE[RAID.raidId] = nil; RebuildRaidList()
                            _raidInterrupt = false; RAID.inMap = false; MODE:Release("raid")
                            task.wait(1); break
                        end
                    end
 -- STEP 3: Tunggu masuk map (max 10s) - flow sama persis v41
 RaidStatusUpdate("[~] Waiting...", Color3.fromRGB(180,100,255))
 local _tpOk = false
 local _tpWait = 0
 while not _tpOk and _tpWait < 2 and RAID.running do
  task.wait(0.3); _tpWait = _tpWait + 0.3
  pcall(function()
   local wMapId = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
   if wMapId then
    if RAID.serverMapId and wMapId == RAID.serverMapId then
     _tpOk = true
    elseif RAID.runeEnabled then
     local ok = (wMapId >= 50101 and wMapId <= 50120)
     if ok then RAID.serverMapId = wMapId; _tpOk = true end
    elseif (wMapId >= 50101 and wMapId <= 50120) then
     _tpOk = true
    end
   end
  end)
  -- Fallback: kalau enemy sudah ada, berarti sudah di dalam map
  if not _tpOk and #GetRaidEnemies() > 0 then _tpOk = true end
 end

 if not _tpOk and RAID.running then
  -- Gagal masuk map: hapus entry dan retry
  RAID_LIVE[RAID.raidId] = nil; RebuildRaidList()
  _raidInterrupt = false; RAID.inMap = false; ReleaseMapLock("raid"); MODE:Release("raid"); RAID.fromMapId = nil
  task.wait(1); break
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
 PG_Wait(0.1) -- [PingGuard] equip hero loop
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

 -- STEP 4: Di dalam raid - cari boss, TP, serang
 -- [FIX v260] Jika sebelumnya Siege baru saja selesai, tunggu workspace bersih dulu.
 -- Cek aktif sampai 5 detik: jika masih ada enemy Siege di workspace, tunggu terus.
 -- Tanpa ini scan boss bisa menemukan sisa enemy Siege dan salah TP ke sana.
 if SIEGE and SIEGE._lastExitTime and (os.time() - SIEGE._lastExitTime) < 5 then
  RaidStatusUpdate("[~] Clearing Siege remnants...", Color3.fromRGB(160,148,135))
  local _siegeWait = 0
  while _siegeWait < 5 and RAID.running do
   local _curMId = GetCurrentMapId()
   -- Selama mapId masih di range Siege, tunggu
   if _curMId and (_curMId >= 50201 and _curMId <= 50204) then
    task.wait(0.5); _siegeWait = _siegeWait + 0.5
   else
    break -- mapId sudah bersih, lanjut
   end
  end
 end

 RAID._raidDone = false
 local _raidSuccess = false

 local connS, connF
 -- _raidServerDone = flag bahwa server sudah bilang sukses
 -- (attack loop tetap jalan sampai boss model hilang dari workspace)
 local _raidServerDone = false
 local _reS = Remotes:FindFirstChild("ChallengeRaidsSuccess")
 local _reF = Remotes:FindFirstChild("ChallengeRaidsFail")
 if _reS then connS = _reS.OnClientEvent:Connect(function()
  _raidServerDone = true; _raidSuccess = true
 end) end
 if _reF then connF = _reF.OnClientEvent:Connect(function()
  RAID._raidDone = true
 end) end

 --  HELPER: Cleanup semua koneksi + unfreeze player 
 -- Dipanggil di SETIAP jalur keluar dari STEP 4 (boss mati, boss tidak ketemu,
 local _freezeConn  = nil  -- RunService.Heartbeat conn untuk lock posisi player
 local _frozenCFrame = nil -- CFrame terkunci saat attack
 local function _step4Cleanup()
  -- 1) Lepas freeze player - pastikan Anchored = false
  pcall(function()
   local char = LP.Character
   local hrp  = char and char:FindFirstChild("HumanoidRootPart")
   if hrp then hrp.Anchored = false end
  end)
  -- 2) Disconnect Heartbeat freeze (idempoten - aman dipanggil berkali-kali)
  if _freezeConn then
   pcall(function() _freezeConn:Disconnect() end)
   _freezeConn  = nil
   _frozenCFrame = nil
  end
  -- 3) Disconnect server event listeners
  if connS then pcall(function() connS:Disconnect() end); connS = nil end
  if connF then pcall(function() connF:Disconnect() end); connF = nil end
 end

 --  LOADING WAIT: tunggu enemies muncul via ChildAdded 
 -- ChildAdded murni untuk deteksi instan + polling ringan sebagai safety net.
 RaidStatusUpdate("[..] Enter Map - loading...", Color3.fromRGB(160,148,135))

 -- [FIX v261] Snapshot mapId diambil SETELAH jeda singkat agar workspace.MapId
 -- sempat update dari server sebelum dipakai untuk validasi.
 task.wait(0.3) -- beri server 1 tick untuk update workspace.MapId

 local function _isValidRaidMap(mId)
  if not mId then return false end
  return (mId >= 50101 and mId <= 50120) or (mId >= 50301 and mId <= 50326)
 end

 local function _isValidRaidMapByInstance()
  local mf = workspace:FindFirstChild("Maps")
  if not mf then return false end
  -- Map1 dan Map3 instance-nya Map101/Map103 (beda sendiri)
  if mf:FindFirstChild("Map101") or mf:FindFirstChild("Map103") then return true end
  for i = 2, 20 do
   if i ~= 3 and mf:FindFirstChild("Map"..i) then return true end
  end
  return false
 end

 -- Tunggu mapId valid (max 3s) - cek via workspace.Maps instance ATAU numerik
 local _raidMapIdSnapshot = GetCurrentMapId()
 local _snapWait = 0
 while not (_isValidRaidMapByInstance() or _isValidRaidMap(_raidMapIdSnapshot)) and _snapWait < 3 and RAID.running do
  task.wait(0.3); _snapWait = _snapWait + 0.3
  _raidMapIdSnapshot = GetCurrentMapId()
 end

 -- [CUSTOM v54.1] Render delay sederhana - TANPA scan nama boss sama sekali.
 -- Mode TP DIRECT tidak butuh tahu siapa boss-nya; target diambil murni dari
 -- scan radius di titik TP (lihat blok AUTO BOSS KILL di bawah). Loading wait
 -- ini hanya untuk memberi waktu render server sebelum TP+scan dilakukan.
 RaidStatusUpdate("[..] Render delay...", Color3.fromRGB(160,148,135))
 local _preMapNum = GetRaidMapNum(raidEntry and raidEntry.mapId)
 local _renderDelay = (_preMapNum == 1) and 4 or 2
 task.wait(_renderDelay) -- Map1: 4s, lainnya: 2s

 if RAID.running and not RAID._raidDone and RAID.autoKillBoss then
  -- [v56] AUTO BOSS KILL - TP KE ROOTPART BOSS (REALTIME)
  -- Teleport player+hero langsung ke CFrame RootPart boss di workspace.Maps.
  -- Path: workspace.Maps.[instanceName].Map.RaidsEnemys.[rootPartName]
  -- Mapping instance+rootPart per mapNum ada di RAID_MAP_INFO.
  -- Setelah TP, scan musuh radius 50 studs dari posisi RootPart tersebut.

  -- Resolve mapNum via workspace.Maps instance (primary) lalu fallback numerik.
  local _mapNumNow = GetRaidMapNum(raidEntry and raidEntry.mapId)

  -- Ambil CFrame realtime dari RootPart boss
  local _tpTargetCF  = _mapNumNow and GetBossRootPartCFrame(_mapNumNow) or nil
  local _tpTargetPos = _tpTargetCF and _tpTargetCF.Position or nil

  -- [v56] FALLBACK BOSS NAME khusus Map 1 dan Map 3:
  -- RootPart di kedua map ini tidak bisa dideteksi via workspace.Maps,
  -- scan workspace.Enemys berdasarkan nama boss (Goblin King / Igris).
  if not _tpTargetPos and (_mapNumNow == 1 or _mapNumNow == 3) then
   local _bossName = BOSS_NAME_BY_MAP[_mapNumNow]
   local _enemysFolder = workspace:FindFirstChild("Enemys")
   if _enemysFolder and _bossName then
    for _, e in ipairs(_enemysFolder:GetChildren()) do
     if e:IsA("Model") and e.Name:find(_bossName, 1, true) then
      local _bHrp = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
      local _bHum = e:FindFirstChildOfClass("Humanoid")
      if _bHrp and _bHum and _bHum.Health > 0 then
       _tpTargetPos = _bHrp.Position
       _tpTargetCF  = _bHrp.CFrame
       break
      end
     end
    end
   end
  end

  if not _tpTargetPos then
   local _info = _mapNumNow and RAID_MAP_INFO[_mapNumNow]
   local _detail = _info and ("Maps."..(_info.instance)..".Map.RaidsEnemys.".._info.rootPart) or ("mapNum="..tostring(_mapNumNow))
   RaidStatusUpdate("[!] RootPart boss tidak ditemukan - " .. _detail .. " - skip", Color3.fromRGB(255,80,80))
   _step4Cleanup()
   task.wait(2)
  else
   -- Countdown delay sebelum TP (1-10s, user-controlled, sama seperti sebelumnya)
   local _bd = math.max(1, math.min(10, RAID.bossDelay or 3))
   for _ci = _bd, 1, -1 do
    if not RAID.running or RAID._raidDone then break end
    RaidStatusUpdate("[K] TP ke Boss Map " .. tostring(_mapNumNow) .. " - " .. _ci .. "s...", Color3.fromRGB(255,160,60))
    task.wait(1)
   end

   if RAID.running and not RAID._raidDone then
    -- Refresh CFrame boss tepat sebelum TP (posisi bisa saja bergerak)
    _tpTargetCF  = GetBossRootPartCFrame(_mapNumNow) or _tpTargetCF
    _tpTargetPos = _tpTargetCF.Position

    -- 1) TP Player ke posisi RootPart boss
    pcall(function()
     local char = LP.Character
     local hrp  = char and char:FindFirstChild("HumanoidRootPart")
     if hrp then hrp.CFrame = _tpTargetCF end
    end)

    -- 2) UnEquip -> EquipBest (timing: UnEquip, wait 1s, EquipBest, wait 2s)
    if RE.UnEquipHero  then pcall(function() RE.UnEquipHero:FireServer()  end) end
    task.wait(1)
    if RE.EquipBestHero then pcall(function() RE.EquipBestHero:FireServer() end) end
    task.wait(2)

    -- [FIX BOSS-KILL] Pastikan HERO_GUIDS terisi independen (jangan bergantung RA/TA/fitur lain).
    -- RE.HeroUseSkill butuh heroGuid eksplisit; tanpa ini hero diam walau EquipBestHero sukses.
    if #HERO_GUIDS == 0 then
     pcall(function()
      for _, obj in ipairs(LP.PlayerGui:GetChildren()) do
       local g = obj:GetAttribute("heroGuid") or obj:GetAttribute("guid")
       if type(g) == "string" and IsValidUUID(g) then
        local dup = false
        for _, ex in ipairs(HERO_GUIDS) do if ex == g then dup = true; break end end
        if not dup then table.insert(HERO_GUIDS, g) end
       end
      end
     end)
     if #HERO_GUIDS > 0 then
      RaidStatusUpdate("[HERO] "..#HERO_GUIDS.." hero guid ter-scan dari PlayerGui", Color3.fromRGB(120,220,255))
     else
      RaidStatusUpdate("[!] HERO_GUIDS masih kosong - hero mungkin tidak menyerang", Color3.fromRGB(255,140,0))
     end
    end

    -- 5) Kunci posisi player selama scan+attack (Heartbeat freeze)
    -- [TA-STYLE] Reposisi mengikuti target real-time (bukan statis di titik TP awal),
    -- identik pola ReassertFreeze/TpToF milik TARGET ATTACK: tiap frame CFrame
    -- direfresh ke 3 stud di depan HRP musuh terkini (_bossFollowTarget, diisi
    -- setelah target hasil scan radius ditemukan di bawah).
    local _bossFollowTarget = nil -- diisi = {hrp=...} setelah target ditemukan (lihat blok scan di bawah)
    pcall(function()
     local char = LP.Character
     local hrp  = char and char:FindFirstChild("HumanoidRootPart")
     if hrp then
      _frozenCFrame = _tpTargetCF
      hrp.Anchored  = true
      hrp.CFrame    = _frozenCFrame
      _freezeConn = RunService.Heartbeat:Connect(function()
       -- [FLa CPU] skip frame ganjil  efektif ~30fps
       if not _freezeFrame then _freezeFrame = 0 end
       _freezeFrame = _freezeFrame + 1
       if _freezeFrame % 2 ~= 0 then return end
       if not RAID.running or RAID._raidDone then
        pcall(function() if hrp and hrp.Parent then hrp.Anchored = false end end)
        if _freezeConn then _freezeConn:Disconnect(); _freezeConn = nil end
        _frozenCFrame = nil
        return
       end
       if hrp and hrp.Parent then
        -- [TA-STYLE] Kalau target sudah ada & hidup, ikuti posisinya (3 stud di depan).
        -- Kalau belum ada target (masih fase scan awal), tetap pakai _frozenCFrame lama.
        local _bt = _bossFollowTarget
        if _bt and _bt.hrp and _bt.hrp.Parent then
         local ok = pcall(function()
          _frozenCFrame = _bt.hrp.CFrame * CFrame.new(0, 0, -3)
          hrp.CFrame     = _frozenCFrame
         end)
         if not ok and _frozenCFrame then hrp.CFrame = _frozenCFrame end
        elseif _frozenCFrame then
         hrp.CFrame = _frozenCFrame
        end
       end
      end)
     end
    end)

    --  SCAN RADIUS 10 STUDS - cari 1 musuh terdekat dari posisi RootPart boss 
    -- Timeout 3 detik (sesuai keputusan): scan tiap 0.5s, total 6x percobaan.
    local TP_SCAN_RADIUS = 50
    local function _scanNearbyEnemy()
     local best, bestDist = nil, nil
     for _, e in ipairs(GetRaidEnemies()) do
      local hum = e.model:FindFirstChildOfClass("Humanoid")
      if hum and hum.Health > 0 and e.hrp and e.hrp.Parent then
       local d = (e.hrp.Position - _tpTargetPos).Magnitude
       if d <= TP_SCAN_RADIUS and (not bestDist or d < bestDist) then
        best = e; bestDist = d
       end
      end
     end
     return best
    end

    local target = _scanNearbyEnemy()
    local _scanWait = 0
    while not target and _scanWait < 3 and RAID.running and not RAID._raidDone do
     task.wait(0.5); _scanWait = _scanWait + 0.5
     target = _scanNearbyEnemy()
    end

    if not target then
     -- Tidak ada musuh dalam radius setelah timeout - anggap gagal, skip map ini
     RaidStatusUpdate("[!] Tidak ada musuh dalam radius " .. TP_SCAN_RADIUS .. " studs - Go Out...", Color3.fromRGB(255,150,50))
     _step4Cleanup()
     task.wait(2)
    else
     -- Musuh ketemu - attack loop pakai cara RA+TA (FCharF style)
     local targetGuid = target.guid
     RaidStatusUpdate("[FLa] Attack: " .. target.model.Name, Color3.fromRGB(255,80,60))

     -- [TA-STYLE] Aktifkan follow-target untuk Heartbeat freeze di atas: mulai
     -- sekarang player akan direposisi 3 stud di depan HRP boss setiap frame,
     -- mengikuti gerak boss (bukan lagi diam di titik TP awal).
     _bossFollowTarget = target

     -- Helper: hitung posisi 10 stud dari musuh ke arah player (sama seperti GetAtkPosF di Farm)
     local function _getBossAtkPos(enemyHRP)
      local char = LP and LP.Character
      local pHRP = char and char:FindFirstChild("HumanoidRootPart")
      if not pHRP or not enemyHRP then return enemyHRP and enemyHRP.Position or _tpTargetPos end
      local ePos = enemyHRP.Position
      local dir = pHRP.Position - ePos
      local dir2 = Vector3.new(dir.X, 0, dir.Z)
      if dir2.Magnitude < 0.1 then return ePos + Vector3.new(10,0,0) end
      return ePos + dir2.Unit * 10
     end

     -- [RA+TA HYBRID] Attack loop STEP4 diganti pakai mekanisme asli RA & TA
     -- (RE.Atk + RE.Click + EnsureHeroAtkThreadFor), BUKAN FireAttack/FireAllDamage/FireHeroRemotes.
     -- Tahap 1 (RA-style): begitu masuk radius 50 studs, fire ke GUID musuh RANDOM dari hasil scan
     --   (memicu combat state, identik cara kerja RA saat memilih musuh acak).
     -- Tahap 2 (TA-style): fire ke GUID boss hasil scan 50 studs, DIKUNCI terus tiap loop
     --   sampai target itu mati (identik cara kerja TA saat lock 1 target by GUID).
     local function _fireOnce(guid)
      if not guid then return end
      if RE.Atk then
       pcall(function() RE.Atk:FireServer({attackEnemyGUID=guid}) end)
      end
      if RE.Click then
       task.spawn(function()
        pcall(function() RE.Click:InvokeServer({enemyGuid=guid}) end)
       end)
      end
      EnsureHeroAtkThreadFor(guid)
     end

     -- Ambil GUID musuh random lain (selain target boss) dari radius 50 studs untuk tahap RA.
     -- Kalau tidak ada musuh lain, fallback pakai GUID boss itu sendiri sebagai RA (tidak masalah).
     local function _pickRandomGuidNearby(excludeGuid)
      local pool = {}
      for _, e in ipairs(GetRaidEnemies()) do
       local hum = e.model:FindFirstChildOfClass("Humanoid")
       if hum and hum.Health > 0 and e.hrp and e.hrp.Parent then
        local d = (e.hrp.Position - _tpTargetPos).Magnitude
        if d <= TP_SCAN_RADIUS then table.insert(pool, e) end
       end
      end
      if #pool == 0 then return excludeGuid end
      local pick = pool[math.random(1, #pool)]
      return pick.guid
     end

     -- Helper: attack 1 cycle = RA (random guid) lalu TA (locked target guid)
     local function _attackBoss(guid, enemyHRP)
      -- Tahap 1: RA-style ke guid random dalam radius
      local _raGuid = _pickRandomGuidNearby(guid)
      _fireOnce(_raGuid)
      -- Tahap 2: TA-style ke guid target boss (locked)
      _fireOnce(guid)
     end

     local _outOfMapCount = 0
     local _bossTimeout   = false          -- [v5] flag timeout 4 menit
     local _atkStart      = tick()         -- [v5] waktu mulai attack
     local BOSS_TIMEOUT   = 240            -- [v5] 4 menit (detik)
     while RAID.running do
      -- [v5] TIMEOUT: 4 menit tanpa boss mati → anggap sukses, keluar seperti kill normal
      if tick() - _atkStart >= BOSS_TIMEOUT then
       _bossTimeout = true
       RaidStatusUpdate("[T] Boss timeout 4min - Dianggap Sukses, keluar...", Color3.fromRGB(255,200,60))
       break
      end
      if _raidServerDone then break end
      local _curMap = GetCurrentMapId()
      if _curMap and (_curMap < 50101 or _curMap > 50120) then
       _outOfMapCount = _outOfMapCount + 1
       if _outOfMapCount >= 3 then
        RaidStatusUpdate("[!] Player keluar raid map - stop attack", Color3.fromRGB(255,140,0))
        break
       end
      else
       _outOfMapCount = 0
      end
      if not target.model or not target.model.Parent then break end
      local hum = target.model:FindFirstChildOfClass("Humanoid")
      if not hum or hum.Health <= 0 then break end
      if not target.hrp or not target.hrp.Parent then
       task.wait() -- [TA-STYLE] no-delay, sama seperti TA
       if not target.model or not target.model.Parent then break end
       local hum2 = target.model:FindFirstChildOfClass("Humanoid")
       if not hum2 or hum2.Health <= 0 then break end
       continue
      end
      -- Scan ulang musuh terdekat dalam radius (jaga-jaga boss ganti/spawn baru)
      local _nearNow = _scanNearbyEnemy()
      if _nearNow and _nearNow.guid ~= targetGuid then
       target = _nearNow
       targetGuid = target.guid
       _bossFollowTarget = target -- [TA-STYLE] update follow-target juga saat target berganti
       RaidStatusUpdate("[FLa] Target baru: " .. target.model.Name, Color3.fromRGB(255,80,60))
      end
      pcall(function() _attackBoss(targetGuid, target.hrp) end)
      task.wait() -- [TA-STYLE] no-delay, sama seperti TA (bukan PG_Wait(0.1))
     end

     _step4Cleanup()
     _raidSuccess = true
     RAID._raidDone = true
     if _bossTimeout then
      RaidStatusUpdate("[T] Timeout 4min - Raid Sukses (forced)", Color3.fromRGB(255,200,60))
     else
      RaidStatusUpdate("[FLa] Target Dead!", Color3.fromRGB(100,255,150))
     end
    end -- if target
   end -- if RAID.running (setelah countdown)
  end -- if _tpTargetPos valid
 elseif RAID.running and not RAID._raidDone then
 -- Auto Kill Boss OFF - tunggu event ChallengeRaidsSuccess max 5 menit
 local _wt = 0
 while RAID.running and not RAID._raidDone and _wt < 300 do
  task.wait(1); _wt = _wt + 1
 end
 end

 -- [FIX v260] Cleanup terpusat (idempoten - aman meski sudah dipanggil dari dalam autoKillBoss path)
 _step4Cleanup()

 if _raidSuccess then
 RAID.sukses = RAID.sukses + 1
 RaidCounterUpdate()
 RaidStatusUpdate("[OK] Succes-" .. RAID.sukses .. " Map " .. mn, Color3.fromRGB(100,255,150))
 -- [RAID LIST ENTRY] Catat map ini sudah dikunjungi setelah sukses keluar
 if RAID.listEnabled and RAID.raidMapId then
  RAID._listVisitedMaps[RAID.raidMapId] = true
 end
 end
 if not RAID.running then break end

 if _raidSuccess then
  RaidStatusUpdate("[..] Wait 1s (Get reward)...", Color3.fromRGB(100,255,150))
  task.wait(1)
 end
 if not RAID.running then break end

 -- STEP 5: Collect + Exit raid
 task.spawn(function() pcall(RaidCollectAll) end)
 RaidStatusUpdate("[FLa] Go Out raid...", Color3.fromRGB(100,200,255))

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
 ok = (wm >= 50101 and wm <= 50120) -- [FIX v17] cover Map 19 & 20
 end
 end)
 return ok
 end

 if true then -- [INDEPENDEN] tidak cek siege
 -- Kirim QuitRaidsMap + TpRemote berlapis
 local _quitRe = Remotes:FindFirstChild("QuitRaidsMap")
 if _quitRe then
 pcall(function() _quitRe:FireServer({ currentSlotIndex = RAID.slotIndex or 2, toMapId = _toMapId }) end)
 end
 task.wait(0.3)
 _fireTpRaid(_toMapId)

 -- Retry max 5x kalau masih di raid area
 local _exitTry = 0
 while _inRaidArea() and _exitTry < 5 and RAID.running do
 _exitTry = _exitTry + 1
 task.wait(1)
 if _quitRe then
 pcall(function() _quitRe:FireServer({ currentSlotIndex = RAID.slotIndex or 2, toMapId = _toMapId }) end)
 end
 task.wait(0.2)
 _fireTpRaid(_toMapId)
 end
 end

 RAID.fromMapId = nil
 RAID.inMap = false

 -- STEP 6: Resume MA -> cooldown
 _raidInterrupt = false
 MODE:Release("raid") -- [FIX v257] MA HARUS resume saat player di luar raid
 -- [FIX v256] Cooldown 12s: server butuh ~12s sebelum bisa masuk Raid lagi
 -- TAPI: selama cooldown, tetap scan workspace agar RAID_LIVE siap
 -- Saat cooldown habis, langsung masuk tanpa delay tambahan
 -- [BUG FIX 3] Tandai cooldown aktif agar standby loop tidak terburu-buru masuk
 RAID._cooldownActive = true
 for cd = 14, 1, -1 do
 if not RAID.running then break end
 -- [INDEPENDEN] tidak tunggu siege setelah exit raid
 -- Scan workspace selama cooldown agar data siap
 if cd % 3 == 0 then ForceRescanRaidEnter() end
 RaidStatusUpdate("[..] Cooldown " .. cd .. "s...", Color3.fromRGB(160,148,135))
 if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
 task.wait(1)
 end
 RAID._cooldownActive = false -- [BUG FIX 3] Cooldown selesai, standby loop boleh masuk

 -- [FIX BUG 2 LIST ENTRY] Buffer 2s tambahan setelah cooldown 14s
 -- Mencegah "terlalu cepat masuk raid lagi" notif dari server
 if RAID.listEnabled and #RAID.listEntries > 0 then
  RaidStatusUpdate("[..] List Entry buffer 2s...", Color3.fromRGB(160,148,135))
  for _bf = 2, 1, -1 do
   if not RAID.running then break end
   task.wait(1)
  end
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

            -- [HUKUM PRIORITAS TERTINGGI DI FASE STANDBY]
            local isBusy = false
            if (SIEGE and (SIEGE.inMap or SIEGE.teleporting)) then
                isBusy = true
            end
            local mapId = workspace:GetAttribute("MapId") or 0
            if (mapId >= 50201 and mapId <= 50204) then
                isBusy = true
            end
            -- RAID standby selama _ascBusy=true (ASC inMap atau cooldown dengan Tower tersedia)
            local _ascBlocking = ASC and ASC.running and _ascBusy

            if isBusy or _ascBlocking then
                if _ascBlocking then
                    RaidStatusUpdate("[||] ASC aktif & ada Tower match - Normal Raid standby...", Color3.fromRGB(180, 100, 255))
                else
                    RaidStatusUpdate("[!] PAUSE: Menunggu Siege/Dungeon Selesai...", Color3.fromRGB(255, 100, 100))
                end
            else
                -- Jika aman, baru boleh cari Raid
                -- Cek IsRaidLiveInGame DULU sebelum ResolveEntry
                -- [BUG FIX 3] Jangan break jika cooldown masih aktif
                if not RAID._cooldownActive and IsRaidLiveInGame() then
                    local _newEntry = ResolveEntry and ResolveEntry()
                    if _newEntry then raidEntry = _newEntry; break end
                    RaidStatusUpdate("[FLa] Waiting grade filter... (" .. _fw .. "s)", Color3.fromRGB(200,255,150))
                else
                    RaidStatusUpdate("[FLa] Empty RAID - Waiting event baru... (" .. _fw .. "s)", Color3.fromRGB(160,120,60))
                end
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

 until true
 end -- while RAID.running
 end) -- pcall

 -- [v63 FIX] Cleanup dijamin jalan meskipun ada Lua error di dalam loop
 _raidInterrupt = false
 RAID.running = false
 RAID.inMap = false
 _raidOn = false
 _raidFallbackActive = false  -- [v61 CYCLEFIX] reset saat RAID stop
 MODE:Release("raid") -- [v257] pastikan MA bisa resume
 RaidStatusUpdate("[FLa] Auto Raid STOP", Color3.fromRGB(160,148,135))
 if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
 end)
end

-- ============================================================================
-- AUTO ASCENSION: LOGIC (port dari 1.lua baris 10499-11916)
-- ResolveAscEntry & ResolveAscEntryFromList dibuat GLOBAL (bukan nested), independen dari RAID Normal
-- AUTO BOSS KILL: pakai metode lama 1.lua (scan nama boss + ChildAdded), damage call diganti
-- RaidFireDamage -> FireAttack+FireAllDamage+FireHeroRemotes (RaidFireDamage tidak ada di 2.lua)
-- ============================================================================
-- AUTO ASCENSION : LOGIC
function StopAscension()
 ASC.running = false
 ASC.inMap   = false
 _ascBusy    = false
 _eventOwner = nil
 ReleaseMapLock("asc")
 -- [v62 FIX] Reset status label agar tidak nyantol di "Dalam Tower x"
 AscStatusUpdate("OFF", Color3.fromRGB(120,120,120))
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 if ASC.thread then
  pcall(function() task.cancel(ASC.thread) end)
  ASC.thread = nil
 end
 if _ascWakeup then
  pcall(function() _ascWakeup:Destroy() end)
  _ascWakeup = nil
 end
end

function AscCounterUpdate()
 if ASC.suksesLbl then ASC.suksesLbl.Text = tostring(ASC.sukses) end
end

-- Helper: ambil semua entry Ascension dari RAID_LIVE (sorted)
local function GetAscensionList()
 local list = {}
 for rid, ent in pairs(RAID_LIVE) do
  -- isAscension == true ATAU raidId >= 935001 (range Ascension Tower dari server)
  local ridAbs = rid < 0 and math.abs(rid) or rid
  -- [v34 FIX] Kecuali Anniversary Celebration (raidId 937101) - BUKAN ASC Tower
  -- Sebelumnya Anniversary masuk ke ASC list karena ridAbs >= 935001
  local _isAnniversaryEntry = (ridAbs == 937101)
  if _isAnniversaryEntry then continue end -- skip Anniversary, bukan ASC
  if ent.isAscension == true or ridAbs >= 935001 then
   if not ent.isAscension then ent.isAscension = true end -- auto-mark
   -- Resolve raidId positif jika entry chat (negatif)
   local resolvedId = rid
   if rid < 0 then
    -- Cari raidId positif dari RAID_LIVE yang sama mapId & isAscension
    for rid2, ent2 in pairs(RAID_LIVE) do
     if rid2 > 0 and ent2.isAscension and ent2.mapId == ent.mapId then
      resolvedId = rid2; break
     end
    end
    -- Jika masih negatif, berarti raidId dari server belum datang
    -- Gunakan nilai absolut sebagai ID sementara supaya CreateRaidTeam bisa dicoba
    -- (server akan reject jika ID tidak valid, dan loop akan retry)
    if resolvedId < 0 then resolvedId = math.abs(resolvedId) end
   end
   -- ASC mapId 50301-50326 -> mapNum 1-26; RAID mapId 50001-50020 -> mapNum 1-20
   local _mId = ent.mapId or 50000
   local mn = (_mId >= 50301 and _mId <= 50326) and (_mId - 50300) or (_mId - 50000)
   -- [FIX] Grade resolution: prioritas chat cache -> runeGradeCache -> ent.grade -> "?"
   -- ent.grade bisa nil jika workspace event datang sebelum chat notif
   local _resolvedGrade = ent.grade
   if (not _resolvedGrade or _resolvedGrade == "?") and _ASC_CHAT_CACHE and _ASC_CHAT_CACHE[mn] then
    _resolvedGrade = _ASC_CHAT_CACHE[mn].grade or _resolvedGrade
   end
   if (not _resolvedGrade or _resolvedGrade == "?") and _runeGradeCache then
    _resolvedGrade = _runeGradeCache[-mn] or _runeGradeCache[mn] or _resolvedGrade
   end
   _resolvedGrade = _resolvedGrade or "?"
   table.insert(list, {
    id      = resolvedId,
    rawId   = rid,
    mapId   = ent.mapId,
    mapNum  = mn,
    grade   = _resolvedGrade,
    bossName= ent.bossName,
    isAscension = true,
   })
  end
 end
 return list
end

-- [ADAPT 2.lua] GetCurrentMapId & GetPlayerPos sudah ada sebagai fungsi global di 2.lua, tidak perlu didefinisikan ulang

-- ResolveAscEntry / ResolveAscEntryFromList dibuat GLOBAL (bukan nested di StartAscensionLoop)
-- agar bisa diakses dari luar (independen, sesuai keputusan salflo)
 function ResolveAscEntryFromList()
  if not ASC.listEnabled then return nil end
  if #ASC.listEntries == 0 then return nil end
  local ascList = GetAscensionList()
  if #ascList == 0 then return nil end

  -- Grade helper
  local function _getGradeL(r)
   local g = GetBestGrade(r.mapNum, true)
   if not g or g == "?" then g = r.grade end
   return (g and g ~= "?") and g or nil
  end

  -- Kumpulkan semua tower yang match dari semua entry
  local function collectAllMatched(skipVisited)
   local allMatched = {}
   local seen = {}
   for i = 1, #ASC.listEntries do
    local ent = ASC.listEntries[i]
    local hasMaps  = next(ent.maps)  ~= nil
    local hasRanks = next(ent.ranks) ~= nil
    for _, r in ipairs(ascList) do
     if seen[r.mapNum] then continue end
     if skipVisited and ASC._listVisitedMaps[r.mapNum] then continue end
     local mapsOk = (not hasMaps) or ent.maps[r.mapNum]
     if not mapsOk then continue end
     if hasRanks then
      local grade = _getGradeL(r)
      if grade and ent.ranks[grade] then
       table.insert(allMatched, r); seen[r.mapNum] = true
      end
     else
      table.insert(allMatched, r); seen[r.mapNum] = true
     end
    end
   end
   return allMatched
  end

  -- Tahap 1: cari yang belum dikunjungi
  local allMatched = collectAllMatched(true)
  -- Tahap 2: kalau semua sudah dikunjungi -> reset visited dan loop ulang
  if #allMatched == 0 then
   for k in pairs(ASC._listVisitedMaps) do ASC._listVisitedMaps[k] = nil end
   allMatched = collectAllMatched(true)
  end
  if #allMatched == 0 then return nil end
  -- Pilih mapNum terkecil dari semua yang match
  table.sort(allMatched, function(a, b) return a.mapNum < b.mapNum end)
  return allMatched[1]
 end

function ResolveAscEntry()
  local ascList = GetAscensionList()
  if #ascList == 0 then return nil, "no_tower" end

  -- [LIST ENTRY ASC] Cek List Entry dulu sebelum logika Pick Mode
  if ASC.listEnabled and #ASC.listEntries > 0 then
   local listResult = ResolveAscEntryFromList()
   if listResult then return listResult end
   -- Tidak ada match -> fallback ke Pick Mode normal (lanjut ke bawah)
  end

  -- Prune expired entries (sama seperti RAID)
  local _now0 = os.time()
  local _pruned0 = false
  for rid, ent in pairs(RAID_LIVE) do
   if ent.isAscension and ent.endTime and ent.endTime < (_now0 - 10) then
    RAID_LIVE[rid] = nil; _pruned0 = true
   end
  end
  if _pruned0 then
   ascList = GetAscensionList()
   if #ascList == 0 then return nil, "no_tower" end
  end

  local pm = ASC.pickMode or "easy"
  local hasPick = (pm == "byrank" or pm == "manual") and next(ASC.runeGrades or {}) ~= nil

  -- Grade helper: GetBestGrade dulu, fallback ke r.grade (sudah di-resolve di GetAscensionList)
  local function _getGrade(r)
   local g = GetBestGrade(r.mapNum, true)
   if not g or g == "?" then g = r.grade end
   return (g and g ~= "?") and g or nil
  end

  -- pickLowest: ambil tower dengan mapNum terkecil
  local function pickLowest(list)
   table.sort(list, function(a, b) return a.mapNum < b.mapNum end)
   return list[1]
  end

  -- sortHighestRank: sort rank tertinggi, tie-break mapNum terkecil (identik RAID)
  local function sortHighestRank(list)
   table.sort(list, function(a, b)
    local ga = _getGrade(a) or "?"
    local gb = _getGrade(b) or "?"
    local ra = GRADE_RANK[ga] or 0
    local rb = GRADE_RANK[gb] or 0
    if ra == rb then return a.mapNum < b.mapNum end
    return ra > rb
   end)
  end

  -- pickByDiff: identik RAID pickByDiff, adaptasi mapNum
  local function pickByDiff(list)
   if #list == 0 then return nil end
   if pm == "easy" then
    table.sort(list, function(a, b) return a.mapNum < b.mapNum end)
    return list[1]
   elseif pm == "hard" then
    table.sort(list, function(a, b) return a.mapNum > b.mapNum end)
    return list[1]
   elseif pm == "default" then
    -- Round-robin Tower 1-8, fallback ke terkecil (identik RAID map 1-8)
    local low = {}
    for _, r in ipairs(list) do
     if r.mapNum >= 1 and r.mapNum <= 8 then table.insert(low, r) end
    end
    if #low == 0 then return pickLowest(list) end
    table.sort(low, function(a, b) return a.mapNum < b.mapNum end)
    ASC._rrIdx = (ASC._rrIdx or 0) + 1
    if ASC._rrIdx > #low then ASC._rrIdx = 1 end
    return low[ASC._rrIdx]
   elseif pm == "byrank" then
    sortHighestRank(list)
    return list[1]
   elseif pm == "bymap" then
    table.sort(list, function(a, b) return a.mapNum < b.mapNum end)
    for _, r in ipairs(list) do
     if ASC.preferMaps[r.mapNum] then return r end
    end
    return list[1]
   end
   return pickLowest(list)
  end

  -- MANUAL MODE — identik RAID: 3 tahap, fallback ke terkecil
  if pm == "manual" then
   ASC.manualMatchMode = "none"
   local valid_asc = {}
   local hasPreferMaps = next(ASC.preferMaps or {}) ~= nil

   -- Tahap 0: kumpulkan kandidat, filter PreferMap jika di-set
   for _, r in ipairs(ascList) do
    local mn = r.mapNum
    if not hasPreferMaps or ASC.preferMaps[mn] then
     table.insert(valid_asc, r)
    end
   end
   if #valid_asc == 0 then return nil, "no_match" end  -- ada tower tapi tidak ada yg cocok preferMaps

   -- Helper sort
   local function sortHighestRankLocal(list)
    table.sort(list, function(a, b)
     local ga = _getGrade(a) or "?"
     local gb = _getGrade(b) or "?"
     local ra = GRADE_RANK[ga] or 0
     local rb = GRADE_RANK[gb] or 0
     if ra == rb then return a.mapNum < b.mapNum end
     return ra > rb
    end)
   end

   -- TAHAP 1: Cari kecocokan Preferred Rank
   local matched = {}
   local hasPreferRank = next(ASC.runeGrades or {}) ~= nil
   if hasPreferRank then
    for _, r in ipairs(valid_asc) do
     local grade = _getGrade(r)
     if grade and ASC.runeGrades[grade] then
      table.insert(matched, r)
     end
    end
    if #matched > 0 then
     sortHighestRankLocal(matched)
     ASC.manualMatchMode = "primary"
     return matched[1]
    end
    -- Rank diset tapi tidak ada tower yang cocok -> return nil+"no_match" agar RAID bisa fallback
    ASC.manualMatchMode = "none"
    return nil, "no_match"
   end

   -- Tidak ada Preferred Rank diset -> fallback ke tower terkecil dari kandidat
   ASC.manualMatchMode = "fallback"
   table.sort(valid_asc, function(a, b) return a.mapNum < b.mapNum end)
   return valid_asc[1]
  end

  -- BYRANK + BYMAP + hasPick: identik RAID
  if hasPick then
   local matched2 = {}
   for _, r in ipairs(ascList) do
    local grade = _getGrade(r)
    if grade and ASC.runeGrades[grade] == true then table.insert(matched2, r) end
   end
   if #matched2 > 0 then
    local chosen = pickByDiff(matched2)
    if chosen then return chosen end
   end
   if pm == "byrank" then return nil, "no_match" end  -- byrank: ada tower tapi rank tidak cocok
  end

  if pm == "bymap" and next(ASC.preferMaps or {}) ~= nil then
   local mapMatched = {}
   for _, r in ipairs(ascList) do
    if ASC.preferMaps[r.mapNum] then table.insert(mapMatched, r) end
   end
   if #mapMatched > 0 then return pickLowest(mapMatched) end
   return nil, "no_match"  -- bymap: ada tower tapi map tidak cocok
  end

  return pickByDiff(ascList)
 end

-- [FIX BUG] ResolveAscTargetMapId tertinggal saat port (asalnya di 1.lua baris 1697,
-- di luar range StartAscensionLoop yang diekstrak) - tanpa ini, StartAscensionLoop
-- crash setiap kali mau ENTER Tower (ResolveAscTargetMapId = nil value), pcall
-- menelan error-nya diam-diam -> ASC keluar loop -> "Auto Ascension STOP".
-- Inilah sebab kedua bug: deteksi sebenarnya jalan, tapi begitu mau masuk Tower
-- langsung crash sebelum sempat TP, jadi user lihatnya "tidak masuk" / "STOP".
function ResolveAscTargetMapId(mapNum)
 -- mapNum = nomor Tower (1-26) dari chat "Ascension Tower X"
 -- Return: mapId untuk StartChallengeRaidMap (50301-50326)
 if not mapNum or mapNum < 1 or mapNum > 26 then return 50301 end
 return 50300 + mapNum
end

function StartAscensionLoop()
 StopAscension()
 ASC.running = true
 ASC.sukses  = 0
 AscCounterUpdate()
 -- [v56 FIX] Wakeup RAID segera saat ASC di-ON
 -- RAID yang lagi di waiting loop harus langsung sadar ASC aktif dan mundur
 -- (fire SETELAH ASC.running = true agar kondisi ASC.running and ResolveAscEntry() terbaca benar)
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 if _ascWakeup then pcall(function() _ascWakeup:Destroy() end) end
 _ascWakeup = Instance.new("BindableEvent")

 AscStatusUpdate("Siap. Menunggu Ascension Tower...", Color3.fromRGB(180,180,60))

 -- ResolveAscEntry: Pick Mode logic IDENTIK dengan AUTO RAID
 -- Semua mode locked kecuali Manual -> hanya masuk Tower terkecil
 -- Manual: PREFERRED MAP + PREFERRED RANK aktif, fallback ke terkecil jika tidak match
 -- ResolveAscEntry: 100% IDENTIK dengan ResolveEntry (Auto Raid Normal)
 -- Satu-satunya perbedaan: pakai ASC.* dan ascList (mapNum) bukan RAID_ID_LIST (mapId)
 -- MapId masuk ke tower tetap 503xx — tidak diubah di sini
 -- Return: entry (match), nil+"no_tower" (tidak ada tower), nil+"no_match" (ada tower tapi filter tidak cocok)
 -- LIST ENTRY ASC: cari tower yang match list, fallback ke Pick Mode

 ASC.thread = task.spawn(function()
  pcall(function()
  while ASC.running do
   repeat

    -- [v48] Cek semua interrupt (sama seperti RAID)

    if ST2 and (ST2.running or ST2.inMap) then
     ASC.inMap = false
     AscStatusUpdate("[||] Tower aktif - Ascension pause...", Color3.fromRGB(255,140,0))
     while ST2 and (ST2.running or ST2.inMap) and ASC.running do task.wait(0.5) end
     if not ASC.running then break end
     AscStatusUpdate("> Tower selesai - lanjut Ascension...", C.ACC3)
     task.wait(0.1)
    end

    if (SIEGE and (SIEGE.inMap or SIEGE.teleporting)) or _siegeInterrupt then
     ASC.inMap = false
     AscStatusUpdate("[||] Siege aktif - Ascension pause...", Color3.fromRGB(255,140,0))
     while ((SIEGE and (SIEGE.inMap or SIEGE.teleporting)) or _siegeInterrupt) and ASC.running do task.wait(0.5) end
     if not ASC.running then break end
     AscStatusUpdate("> Siege selesai - lanjut Ascension...", C.ACC3)
     task.wait(0.1)
    end

    -- Blokir jika di dalam map RAID Normal atau Siege (bukan Ascension Tower sendiri)
    local curWm = workspace:GetAttribute("MapId") or 0
    if (curWm >= 50101 and curWm <= 50120) or (curWm >= 50201 and curWm <= 50205) then
     AscStatusUpdate("[||] Sedang di dalam map lain - tunggu...", Color3.fromRGB(255,140,0))
     task.wait(3); break
    end

    -- [v48] Resolve entry berdasarkan Pick Mode
    local raidEntry, _ascReason = ResolveAscEntry()

    -- [FALLBACK FIX] Jika ada tower tapi filter tidak match + RAID.running -> fallback ke RAID siklus ini
    if not raidEntry and _ascReason == "no_match" and RAID and RAID.running then
     AscStatusUpdate("[Fallback] Filter tidak match - giliran Auto Raid siklus ini...", Color3.fromRGB(140,80,200))
     if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
     _eventOwner = "raid"
     -- Tunggu sampai RAID selesai satu siklus atau ada tower baru yang match
     local _fbConn
     local _fbDone = false
     if _ascWakeup then
      _fbConn = _ascWakeup.Event:Connect(function()
       _fbDone = true  -- ada event baru, coba resolve lagi
      end)
     end
     while ASC.running and not _fbDone do
      task.wait(0.5)
      -- Cek apakah sekarang ada match (event baru bisa datang)
      local _recheck, _recheckReason = ResolveAscEntry()
      if _recheck then _fbDone = true; raidEntry = _recheck end
     end
     if _fbConn then pcall(function() _fbConn:Disconnect() end) end
     if not raidEntry then
      break  -- kembali ke outer while loop, cek kondisi fresh
     end
    end

    -- Waiting loop jika tidak ada Ascension Tower tersedia (no_tower atau ASC-only)
    while ASC.running and not raidEntry do
     local ascList = GetAscensionList()
     local _pm = ASC.pickMode or "easy"
     local _, _curReason = ResolveAscEntry()
     -- Jika ada tower tapi filter tidak match dan RAID running -> fallback
     -- (ini handle kasus dimana tower muncul SAAT waiting loop berjalan)
     if _curReason == "no_match" and RAID and RAID.running then
      AscStatusUpdate("[Fallback] Filter tidak match - giliran Auto Raid...", Color3.fromRGB(140,80,200))
      if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
      _eventOwner = "raid"
      break
     elseif _raidFallbackActive and RAID.running then
      AscStatusUpdate("[Standby] RAID fallback aktif siklus ini - tunggu siklus event baru...", Color3.fromRGB(140,80,200))
     elseif #ascList == 0 then
      if RAID.running then
       AscStatusUpdate("[Standby] Fallback ke Auto Raid - tunggu Ascension Tower...", Color3.fromRGB(140,100,200))
      else
       AscStatusUpdate("Waiting Ascension Tower [".._pm.."]...", Color3.fromRGB(140,140,60))
      end
     elseif _pm == "manual" then
      -- Manual mode: tampilkan filter aktif
      local _parts = {}
      local _hasMap = next(ASC.preferMaps or {}) ~= nil
      local _hasRank = next(ASC.runeGrades or {}) ~= nil
      if _hasMap then
       local _ms = {}
       for mn=1,26 do if ASC.preferMaps and ASC.preferMaps[mn] then table.insert(_ms,"T"..mn) end end
       table.insert(_parts, "Map["..table.concat(_ms,"|").."]")
      end
      if _hasRank then
       local _gr = {}
       for _, g in ipairs(GRADE_LIST) do if ASC.runeGrades[g] then table.insert(_gr, g) end end
       table.insert(_parts, "Rank["..table.concat(_gr,"||").."]")
      end
      if _hasRank and ASC.runeEnabled and ASC.runeMapTarget >= 1 and ASC.runeMapTarget <= 26 then
       table.insert(_parts, "Rune->T"..ASC.runeMapTarget)
      end
      local _filterStr = #_parts > 0 and table.concat(_parts," | ") or "no filter"
      -- Jika ada tower tapi tidak cocok filter rank -> beri keterangan lebih jelas
      local _ascListNow = GetAscensionList()
      local _noMatchNote = (#_ascListNow > 0 and _hasRank) and " [no rank match]" or "..."
      AscStatusUpdate("Waiting [Manual] "..(_filterStr).._noMatchNote, Color3.fromRGB(255,180,50))
     elseif _pm == "bymap" then
      local _ms = {}
      for mn=1,26 do if ASC.preferMaps and ASC.preferMaps[mn] then table.insert(_ms,"T"..mn) end end
      local _mapStr = #_ms > 0 and table.concat(_ms,"|") or "NOT SET"
      AscStatusUpdate("Waiting [ByMap] "..(_mapStr).." (fallback: terkecil)...", Color3.fromRGB(100,200,100))
     elseif _pm == "byrank" then
      local _gr = {}
      for _, g in ipairs(GRADE_LIST) do if ASC.runeGrades[g] then table.insert(_gr, g) end end
      local _rankStr = #_gr > 0 and table.concat(_gr,"||") or "NOT SET"
      AscStatusUpdate("Waiting [ByRank] "..(_rankStr).." (fallback: terkecil)...", Color3.fromRGB(200,120,255))
     elseif _pm == "hard" then
      AscStatusUpdate("Waiting Ascension Tower [Hard - Tower Terbesar]...", Color3.fromRGB(255,80,80))
     elseif _pm == "easy" then
      AscStatusUpdate("Waiting Ascension Tower [Easy - Tower Terkecil]...", Color3.fromRGB(80,220,80))
     else
      AscStatusUpdate("Waiting Ascension Tower [".._pm.."]...", Color3.fromRGB(255,200,60))
     end
     -- Wakeup cepat
     local _woken = false
     local _wConn
     if _ascWakeup then
      _wConn = _ascWakeup.Event:Connect(function() _woken = true end)
     end
     local _we = 0
     while not _woken and _we < 1 and ASC.running do
      task.wait(0.1); _we = _we + 0.1
     end
     if _wConn then pcall(function() _wConn:Disconnect() end) end
     -- [v62 RINO/RINI FIX] Jika TriggerEntryWakeup memutuskan ini giliran RAID ("rini"),
     -- ASC ("rino") tetap duduk. Tidak mencoba resolve apapun sampai siklus berikutnya.
     if _eventOwner == "raid" and RAID.running then
      raidEntry = nil  -- ASC standby, RAID yang jalan siklus ini
     elseif _raidFallbackActive and RAID.running then
      raidEntry = nil  -- fallback lama (v61 compat)
     else
      local _re2, _reason2 = ResolveAscEntry()
      raidEntry = _re2
      -- Jika ada tower tapi filter tidak match dan RAID running -> fallback ke RAID
      if not _re2 and _reason2 == "no_match" and RAID and RAID.running then
       AscStatusUpdate("[Fallback] Filter tidak match - giliran Auto Raid...", Color3.fromRGB(140,80,200))
       if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
       _eventOwner = "raid"
       break  -- keluar waiting loop, biarkan RAID jalan
      end
     end
    end
    if not ASC.running then break end
    if not raidEntry then break end

    -- [v56 FIX] ASC guard: tunggu fitur lain selesai sebelum masuk Tower
    -- RAID: tunggu sampai RAID.inMap = false (keluar dari map), lalu ASC boleh masuk
    do
     local _aWait = 0
     while ASC.running and _aWait < 90 do
      local _busy, _who = IsAnyMapActive()
      local _selfBusy = (_who == "asc")
      if not _busy or _selfBusy then break end
      AscStatusUpdate("[||] Tunggu "..(_who or "?").." selesai dulu...", Color3.fromRGB(255,140,0))
      task.wait(0.5); _aWait = _aWait + 0.5
     end
     if not ASC.running then break end
    end

    -- [v52 FIX] Atomic lock: cegah RAID masuk bersamaan saat ASC baru lolos guard
    -- Tanpa lock ini: RAID dan ASC bisa lolos guard hampir bersamaan (keduanya lihat inMap=false)
    -- lalu keduanya coba TP player ke map berbeda dalam waktu bersamaan
    do
     local _lockWait = 0
     while ASC.running and _lockWait < 15 do
      if TryClaimMapLock("asc") then break end
      AscStatusUpdate("[||] Tunggu slot masuk map bebas...", Color3.fromRGB(200,160,255))
      task.wait(0.2); _lockWait = _lockWait + 0.2
     end
     if not ASC.running then ReleaseMapLock("asc"); break end
    end

    local mn = raidEntry.mapNum
    -- [LIST ENTRY ASC] Tandai tower ini sudah dikunjungi di siklus ini
    if ASC.listEnabled and #ASC.listEntries > 0 then
     ASC._listVisitedMaps[mn] = true
    end
    local bossHint = raidEntry.bossName and (" - "..raidEntry.bossName) or ""
    AscStatusUpdate("Masuk: Tower "..mn..bossHint.." ["..raidEntry.grade.."]", Color3.fromRGB(100,200,255))

    -- Tunggu SIEGE selesai dulu jika sedang inMap
    if SIEGE and (SIEGE.inMap or SIEGE.teleporting) then
        AscStatusUpdate("[||] Tunggu SIEGE selesai...", Color3.fromRGB(255,180,50))
        local _ws = 0
        while (SIEGE.inMap or SIEGE.teleporting) and ASC.running and _ws < 120 do
            task.wait(0.5); _ws = _ws + 0.5
        end
        if not ASC.running then return end
    end

    -- Tunggu RAID selesai dulu jika sedang inMap
    if RAID and RAID.inMap then
        AscStatusUpdate("[||] Tunggu RAID selesai...", Color3.fromRGB(255,180,50))
        local _wr = 0
        while RAID.inMap and ASC.running and _wr < 120 do
            task.wait(0.5); _wr = _wr + 0.5
        end
        if not ASC.running then return end
    end

    _ascInterrupt = true  -- signal MA untuk pause (MA cek di guard tiap iterasi)

    ASC.inMap = true
    _ascInterrupt = false  -- inMap=true sudah aktif, WaitRaidDone cek ASC.inMap langsung
    _ascBusy  = true  -- RAID harus pause total selama ASC aktif (inMap+cooldown)
    _ascMatchedThisCycle = true   -- [v61 CYCLEFIX] ASC sudah match di siklus ini
    _raidFallbackActive  = false  -- [v61 CYCLEFIX] RAID tidak boleh fallback di siklus ini
    _ascPending = false -- [v57 FIX] inMap=true sudah cover, tidak perlu pending lagi
    -- [v52 FIX] Setelah inMap=true di-set, lock tidak diperlukan lagi (IsAnyMapActive sudah cover)
    ReleaseMapLock("asc")

    -- Entry ASC = identik RAID normal, beda hanya mapId dan RUNE_IDS:
    -- RAID: StartChallengeRaidMap({mapId = raidEntry.mapId + 100}) → 50101-50120
    -- ASC : StartChallengeRaidMap({mapId = 50300+mn})              → Tower X = 50301-50326
    -- mapNum sudah di-resolve oleh ResolveAscEntry (termasuk Preferred Map / Rank filter + fallback)
    local targetMapId = ResolveAscTargetMapId(mn)
    local _pm_now = ASC.pickMode or "easy"
    local mn_label = mn
    if _pm_now == "manual" and ASC.manualMatchMode == "primary" then
     mn_label = mn.." [Match]"
    elseif _pm_now == "manual" and ASC.manualMatchMode == "fallback" then
     mn_label = mn.." [Fallback]"
    elseif _pm_now == "bymap" then
     mn_label = mn.." [ByMap]"
    elseif _pm_now == "byrank" then
     mn_label = mn.." [ByRank]"
    end

    AscStatusUpdate("[~] Enter Tower "..mn_label.."...", Color3.fromRGB(100,200,255))

    -- [v64] ASC RUNE IDS (Preferred Rune / Item) - 26 Tower Ascension
    local ASC_RUNE_IDS = {
     [1]=10265,  -- Baran
     [2]=10266,  -- Baran+1
     [3]=10267,  -- Grendal
     [4]=10268,  -- Grendal+1
     [5]=10269,  -- Plague
     [6]=10314,  -- Plague+1
     [7]=10315,  -- Frostborne
     [8]=10316,  -- Frostborne+1
     [9]=10357,  -- Legia
     [10]=10358, -- Legia+1
     [11]=10359, -- Silas
     [12]=10360, -- Silas+1
     [13]=10361, -- Yogumunt
     [14]=10362, -- Yogumunt+1
     [15]=10363, -- Antares
     [16]=10364, -- Antares+1
     [17]=10365, -- Ashborn
     [18]=10366, -- Ashborn+1
     [19]=10367, -- Dominion
     [20]=10368, -- Dominion+1
     [21]=10369, -- Absolute
     [22]=10370, -- Absolute+1
     [23]=10371, -- Broly
     [24]=10372, -- Broly+1
     [25]=10373, -- Goku Super 4
     [26]=10374, -- Goku Super 4+1
    }

    -- [v64] LOGIKA KEPUTUSAN (disesuaikan untuk Tower 1-26)
    -- Identik AUTO RAID: rune aktif di semua mode selama runeEnabled=true dan runeMapTarget valid
    -- APM_UNLOCK hanya mengunci UI field (tidak bisa set baru), bukan memblokir eksekusi rune
    local useRune = false

    if ASC.runeEnabled and ASC.runeMapTarget >= 1 and ASC.runeMapTarget <= 26 then
     -- Anti-mubazir: kalau tower yang akan dimasuki sudah sama dengan target, simpan rune
     if mn == ASC.runeMapTarget then
      useRune = false
     else
      useRune = true
     end
    end

    -- [v64] EKSEKUSI (identik RAID - hanya RUNE_IDS dan mapId berbeda)
    if useRune then
     -- >>> MODE RUNE TOWER OVERRIDE <<<
     local targetTower = ASC.runeMapTarget
     AscStatusUpdate("Create Team...", C.ACC2)
     if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(raidEntry.id) end) end
     task.wait(0.2)

     AscStatusUpdate("Use Item (Tower "..targetTower..")...", Color3.fromRGB(255,200,60))
     local itemId = ASC_RUNE_IDS[targetTower]
     if itemId and RE.UseRaidItem then
      pcall(function() RE.UseRaidItem:FireServer(itemId) end)
     end
     task.wait(0.3)

     local _runeTargetMapId = 50300 + targetTower
     if RE.StartChallengeRaidMap then
      pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = _runeTargetMapId}) end)
     end

     ASC.serverMapId = nil
     local _wR = 0
     while ASC.serverMapId == nil and _wR < 10 and ASC.running do
      task.wait(0.1); _wR = _wR + 0.1
     end

     -- Jika serverMapId nil setelah timeout: material habis atau server reject
     if ASC.serverMapId == nil and ASC.running then
      -- Di Manual mode: JANGAN fallback masuk tower lain. Lapor dan nganggur.
      local _pm_rune = ASC.pickMode or "easy"
      if _pm_rune == "manual" then
       AscStatusUpdate("[!] Material Habis - Nganggur (Manual mode)...", Color3.fromRGB(255,80,80))
       ASC.inMap = false
       _ascBusy = false
       _ascInterrupt = false
       ReleaseMapLock("asc")
       -- Tunggu sampai wakeup event berikutnya (material diisi ulang / event baru)
       local _woken = false
       local _wConn
       if _ascWakeup then
        _wConn = _ascWakeup.Event:Connect(function() _woken = true end)
       end
       local _wt = 0
       while not _woken and _wt < 30 and ASC.running do
        task.wait(1); _wt = _wt + 1
        AscStatusUpdate("[!] Material Habis - Menunggu... ("..tostring(30-_wt).."s)", Color3.fromRGB(255,80,80))
       end
       if _wConn then pcall(function() _wConn:Disconnect() end) end
       break
      else
       -- Mode lain: fallback masuk tower original
       AscStatusUpdate("[!] Item Kosong - Fallback ke Tower "..mn.."...", Color3.fromRGB(255,140,0))
       if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(raidEntry.id) end) end
       task.wait(0.2)
       if RE.StartChallengeRaidMap then pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = targetMapId}) end) end
       local _wFb = 0
       while ASC.serverMapId == nil and _wFb < 5 and ASC.running do
        task.wait(0.05); _wFb = _wFb + 0.05
       end
      end
     end

    else
     -- >>> MODE NORMAL / FALLBACK <<<
     AscStatusUpdate("[~] Enter Tower "..mn_label.."...", Color3.fromRGB(100,200,255))
     -- Sama persis RAID: CreateRaidTeam(raidId)
     if RE.CreateRaidTeam then
      pcall(function() RE.CreateRaidTeam:InvokeServer(raidEntry.id) end)
     end
     task.wait(0.2)
     if not ASC.running then ASC.inMap = false; break end

     -- Sama persis RAID: StartChallengeRaidMap({mapId=targetMapId})
     local _cfail = false
     local _cfConn
     local _cfRe = Remotes:FindFirstChild("ChallengeRaidsFail")
     if _cfRe then _cfConn = _cfRe.OnClientEvent:Connect(function() _cfail = true end) end

     if RE.StartChallengeRaidMap then
      pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = targetMapId}) end)
     end

     -- [v64 FIX] Tunggu ASC.serverMapId (bukan RAID.serverMapId!) max 5s
     ASC.serverMapId = nil
     local _w2 = 0
     while ASC.serverMapId == nil and _w2 < 5 and ASC.running and not _cfail do
      task.wait(0.05); _w2 = _w2 + 0.05
     end
     if _cfConn then pcall(function() _cfConn:Disconnect() end) end

     if _cfail then
      RAID_LIVE[raidEntry.rawId] = nil
      if raidEntry.rawId ~= raidEntry.id then RAID_LIVE[raidEntry.id] = nil end
      if RebuildRaidList then pcall(RebuildRaidList) end
      ASC.inMap = false; ReleaseMapLock("asc")
      -- [v64 FIX] Jangan biarkan _ascBusy=true saat gagal masuk -> RAID/MA akan stuck pause
      _ascBusy = false
      _ascInterrupt = false  -- [FIX] reset jika gagal masuk
      AscStatusUpdate("[!] Server reject (ChallengeRaidsFail) - retry...", Color3.fromRGB(255,80,80))
      task.wait(1); break
     end
    end

    -- Tunggu masuk Tower (max 10s) - sama persis RAID tapi cek range 50301-50326
    AscStatusUpdate("[~] Waiting Tower "..mn_label.."...", Color3.fromRGB(180,100,255))
    local _tpOk = false
    local _tpW  = 0
    while not _tpOk and _tpW < 10 and ASC.running do
     task.wait(0.3); _tpW = _tpW + 0.3
     pcall(function()
      local wm = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
      if wm then
       if wm >= 50301 and wm <= 50326 then _tpOk = true end
      end
     end)
     if not _tpOk and #GetRaidEnemies() > 0 then _tpOk = true end
    end

    if not _tpOk and ASC.running then
     RAID_LIVE[raidEntry.rawId] = nil
     if raidEntry.rawId ~= raidEntry.id then RAID_LIVE[raidEntry.id] = nil end
     if RebuildRaidList then pcall(RebuildRaidList) end
     ASC.inMap = false; ReleaseMapLock("asc")
     -- [v64 FIX] Reset _ascBusy agar RAID/MA tidak stuck pause selamanya saat gagal TP
     _ascBusy = false
     _ascInterrupt = false  -- [FIX] reset pada gagal TP
     AscStatusUpdate("[!] Gagal masuk Tower - retry...", Color3.fromRGB(255,80,80))
     task.wait(1); break
    end

    -- Setup event listener boss/done
    local _ascDone = false
    local _ascSuccess = false
    local connAS, connAF
    -- [BUG FIX 1&2] _ascServerDone = server bilang sukses, tapi TIDAK interrupt attack loop.
    -- _ascDone hanya di-set true dari Fail event (batal total) atau setelah attack loop selesai.
    local _ascServerDone = false
    local _reAS = Remotes:FindFirstChild("ChallengeRaidsSuccess")
    local _reAF = Remotes:FindFirstChild("ChallengeRaidsFail")
    if _reAS then connAS = _reAS.OnClientEvent:Connect(function() _ascServerDone = true; _ascSuccess = true end) end
    if _reAF then connAF = _reAF.OnClientEvent:Connect(function() _ascDone = true end) end

    -- STEP 4: Dalam map - equip hero
    if #HERO_GUIDS > 0 then
     task.spawn(function()
      task.wait(0.5)
      if RE.EquipHeroWithData then
       for _, hGuid in ipairs(HERO_GUIDS) do
        pcall(function() RE.EquipHeroWithData:FireServer({ heroGuid = hGuid, userId = MY_USER_ID }) end)
        task.wait(0.1)
       end
      end
      if RE.HeroStand then
       local char = LP.Character
       local hrp = char and char:FindFirstChild("HumanoidRootPart")
       local spawnPos = (hrp and hrp.Position) or Vector3.new(0,0,0)
       pcall(function() RE.HeroStand:FireServer({ userId=MY_USER_ID, standPos=spawnPos }) end)
      end
     end)
    end

    AscStatusUpdate("[~] Dalam Tower "..mn.." - loading...", Color3.fromRGB(100,200,255))

    -- [v64 FIX] Watchdog: reset ASC.inMap + _ascBusy jika player terdeteksi keluar Tower
    -- Ini handle kasus race condition: MA/RAID TP player keluar saat ASC masih "inMap=true"
    -- Tanpa ini: ASC stuck "Dalam Tower... Loading" selamanya karena state tidak pernah direset
    local _watchdogTh = task.spawn(function()
     while ASC.inMap and ASC.running do
      task.wait(1)
      local ok, wm = pcall(function()
       return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or 0
      end)
      if ok and type(wm) == "number" then
       -- Jika player tidak di Ascension Tower range, berarti sudah keluar secara paksa
       if wm > 0 and (wm < 50301 or wm > 50326) then
        -- Jangan langsung reset jika masih di fase loading awal (beri waktu 3s)
        task.wait(3)
        local ok2, wm2 = pcall(function()
         return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or 0
        end)
        if ok2 and type(wm2) == "number" and (wm2 < 50301 or wm2 > 50326) and wm2 > 0 then
         AscStatusUpdate("[!] Watchdog: Player keluar Tower paksa - reset state", Color3.fromRGB(255,80,80))
         ASC.inMap = false
         _ascBusy = false
         _ascInterrupt = false  -- [FIX] reset pada watchdog exit
         ReleaseMapLock("asc")
         break
        end
       end
      end
     end
    end)



    -- [v48] AUTO BOSS KILL - sama persis dengan AUTO RAID
    if ASC.autoKillBoss then
     -- BOSS_KEYS untuk Ascension Tower (semua boss AT + boss normal)
     local BOSS_KEYS_ASC = {
      "baran","grendal","plague","frostborne","legia",
      "silas","yogumunt","antares","ashborn",
      -- [CUSTOM] Boss Ascension Tower
     }
     local function IsBossAsc(name)
      local n = name:lower()
      for _, k in ipairs(BOSS_KEYS_ASC) do if n:find(k,1,true) then return true end end
      return false
     end
     -- Prioritaskan nama boss dari entry jika ada
     local _ascHintName = raidEntry.bossName and raidEntry.bossName:lower() or nil
     local function IsBossAscWithHint(name)
      local n = name:lower()
      if _ascHintName and n:find(_ascHintName,1,true) then return true end
      return IsBossAsc(name)
     end

     -- [FIX v50] Tunggu mapId ASC valid sebelum mulai scan boss
     -- Identik pola RAID: snapshot mapId + anchor posisi player diambil SETELAH mapId valid
     -- Tanpa ini: filter mapId di _tryAddBoss terlalu cepat return saat ChildAdded fire
     task.wait(0.3) -- beri server 1 tick untuk update workspace.MapId
     local _ascMapIdSnapshot = GetCurrentMapId()
     local _ascSnapWait = 0
     while (_ascMapIdSnapshot == nil or _ascMapIdSnapshot < 50301 or _ascMapIdSnapshot > 50326)
      and _ascSnapWait < 3 and ASC.running and not _ascDone do
      task.wait(0.3); _ascSnapWait = _ascSnapWait + 0.3
      _ascMapIdSnapshot = GetCurrentMapId()
     end
     -- _ascMapIdFilterActive: hanya aktifkan filter mapId jika snapshot benar-benar valid
     -- Jika server lambat update, filter dimatikan agar boss tidak ditolak salah
     local _ascMapIdFilterActive = _ascMapIdSnapshot ~= nil
      and (_ascMapIdSnapshot >= 50301 and _ascMapIdSnapshot <= 50326)
     -- Anchor posisi player diambil setelah mapId valid
     -- Jika diambil terlalu awal posisi masih di map lama -> semua enemy ditolak karena jarak
     local _ascAnchorPos = GetPlayerPos()
     local _ascAnchorValid = _ascAnchorPos and _ascAnchorPos.Magnitude > 10
     local MAX_DIST_ASC_BOSS = 2000

     -- [FIX v50] Early boss detection ASC - scan agresif semua sumber
     local _earlyBoss = nil
     local _loadWait = 0
     while _loadWait < 5 and ASC.running and not _ascDone do
      task.wait(0.5); _loadWait = _loadWait + 0.5
      if _loadWait >= 1 and not _earlyBoss then
       local _pp = GetPlayerPos()
       -- Sumber 1: GetRaidEnemies()
       local _eList = GetRaidEnemies()
       -- [ADAPT 2.lua] GetEnemiesLocal tidak ada di 2.lua, GetRaidEnemies() sudah cukup + fallback folder scan di bawah
       for _, e in ipairs(_eList) do
        if IsBossAscWithHint(e.model.Name) then
         -- [FIX] Validasi jarak 500 studs - cegah boss dari map lain
         local _hrp = e.model and e.model:FindFirstChild("HumanoidRootPart")
         if _hrp and _pp and _pp.Magnitude > 1 then
          if (_hrp.Position - _pp).Magnitude <= 500 then _earlyBoss = e; break end
         elseif _hrp then
          _earlyBoss = e; break
         end
        end
       end
       -- Sumber 3: scan folder langsung kalau masih belum ketemu
       if not _earlyBoss then
        pcall(function()
         for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
          local f = workspace:FindFirstChild(fname)
          if f then
           for _, obj in ipairs(f:GetChildren()) do
            if obj:IsA("Model") and IsBossAscWithHint(obj.Name) then
             local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("BossGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID")
             local hrp = obj:FindFirstChild("HumanoidRootPart")
             local hum = obj:FindFirstChildOfClass("Humanoid")
             if g and hrp and hum and hum.Health > 0 then
              -- [FIX] Validasi jarak 500 studs - cegah boss dari map lain
              if _pp and _pp.Magnitude > 1 then
               if (hrp.Position - _pp).Magnitude <= 500 then
                _earlyBoss = {guid=g, hrp=hrp, model=obj}; break
               end
              else
               _earlyBoss = {guid=g, hrp=hrp, model=obj}; break
              end
             end
            end
           end
          end
          if _earlyBoss then break end
         end
        end)
       end
      end
      if _earlyBoss then
       local _ep = _earlyBoss.hrp and _earlyBoss.hrp.Parent and _earlyBoss.hrp.Position
       if _ep and _ep.Y > -200 and _ep.Magnitude > 1 and _loadWait >= 1.5 then break end
       if _ep and (_ep.Y <= -200 or _ep.Magnitude <= 1) then _earlyBoss = nil end
      end
     end

     -- [FIX v50] Event-based boss detection - identik dengan RAID
     -- Tambah _bossFoundViaEvent flag + scan existing children tiap folder
     local boss = (_earlyBoss and IsBossAscWithHint(_earlyBoss.model.Name)) and _earlyBoss or nil
     local _bossEventConns = {}
     local _bossFoundViaEvent = false
     local function _tryAddBoss(obj)
      if boss or not obj:IsA("Model") then return end
      if IsBossAscWithHint(obj.Name) then
       -- [FIX v50] Filter mapId toleran: hanya blokir jika filter aktif DAN mapId jelas di luar range
       -- Sebelumnya: hard reject jika mapId nil/belum update -> boss dari ChildAdded diabaikan
       -- Sekarang: jika _ascMapIdFilterActive=false (server belum update), biarkan lolos dulu
       if _ascMapIdFilterActive then
        local _curMap = GetCurrentMapId()
        if _curMap and (_curMap < 50301 or _curMap > 50326) then return end
       end
       local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("BossGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID")
       local hrp = obj:FindFirstChild("HumanoidRootPart")
       local hum = obj:FindFirstChildOfClass("Humanoid")
       if not (g and hrp and hum) then return end
       -- [FIX ZOMBIE] Validasi zombie: health, maxhealth, posisi
       if hum.Health <= 0 then return end
       if hum.MaxHealth <= 0 then return end
       local _ap = hrp.Position
       if _ap.Magnitude <= 10 then return end
       if _ap.Y < -200 or _ap.Y > 1500 then return end
       if not hrp:IsDescendantOf(workspace) then return end
       -- [FIX v50] Gunakan anchor posisi yang sudah divalidasi post-TP (identik pola RAID)
       -- Sebelumnya: GetPlayerPos() on-the-fly, bisa masih transit -> filter jarak tidak akurat
       if _ascAnchorValid then
        if (_ap - _ascAnchorPos).Magnitude > MAX_DIST_ASC_BOSS then return end
       else
        -- Anchor belum valid: fallback ke GetPlayerPos() on-the-fly
        local _pp = GetPlayerPos()
        if _pp and _pp.Magnitude > 1 then
         if (_ap - _pp).Magnitude > MAX_DIST_ASC_BOSS then return end
        end
       end
       boss = {guid=g, hrp=hrp, model=obj}
       _bossFoundViaEvent = true
      end
     end
     -- Pasang ChildAdded di semua folder enemy + scan existing children sekarang
     for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
      local folder = workspace:FindFirstChild(fname)
      if folder then
       table.insert(_bossEventConns, folder.ChildAdded:Connect(_tryAddBoss))
       -- [FIX] Scan existing children - boss mungkin sudah ada sebelum listener dipasang
       for _, child in ipairs(folder:GetChildren()) do _tryAddBoss(child) end
      end
     end
     -- Listen workspace.ChildAdded untuk folder yang baru muncul
     table.insert(_bossEventConns, workspace.ChildAdded:Connect(function(obj)
      if obj:IsA("Folder") or obj:IsA("Model") then
       _tryAddBoss(obj)
       pcall(function()
        table.insert(_bossEventConns, obj.ChildAdded:Connect(_tryAddBoss))
        for _, child in ipairs(obj:GetChildren()) do _tryAddBoss(child) end
       end)
      end
     end))

     -- [FIX v50] Cari boss - max 5s
     -- [ADAPT 2.lua] Pakai GetRaidEnemies() (GetEnemiesLocal tidak ada di 2.lua)
     local waitBoss = 0
     while ASC.running and not boss and waitBoss < 5 and not _ascDone do
      local _pp = GetPlayerPos()
      -- Coba GetRaidEnemies() dulu
      local _bList = GetRaidEnemies()
      for _, e in ipairs(_bList) do
       if IsBossAscWithHint(e.model.Name) then
        -- [FIX] Validasi jarak 500 studs - cegah boss dari map lain
        local _hrp = e.model and e.model:FindFirstChild("HumanoidRootPart")
        if _hrp and _pp and _pp.Magnitude > 1 then
         if (_hrp.Position - _pp).Magnitude <= 500 then boss = e; break end
        elseif _hrp then
         boss = e; break
        end
       end
      end
      -- Fallback terakhir: scan workspace:GetDescendants() setelah 15s (dead code - waitBoss max 5s)
      if not boss and waitBoss >= 15 and waitBoss % 5 < 0.4 then
       pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
         if obj:IsA("Model") and IsBossAscWithHint(obj.Name) then
          local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("BossGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID")
          local hrp = obj:FindFirstChild("HumanoidRootPart")
          local hum = obj:FindFirstChildOfClass("Humanoid")
          if g and hrp and hum and hum.Health > 0 then
           -- [FIX] Validasi jarak 500 studs - cegah boss dari map lain
           if _pp and _pp.Magnitude > 1 then
            if (hrp.Position - _pp).Magnitude <= 500 then
             boss = {guid=g, hrp=hrp, model=obj}; break
            end
           else
            boss = {guid=g, hrp=hrp, model=obj}; break
           end
          end
         end
        end
       end)
      end
      if not boss then
       AscStatusUpdate("Find Boss... ("..math.floor(waitBoss).."s/5s)", Color3.fromRGB(160,148,135))
       task.wait(0.3); waitBoss = waitBoss + 0.3
      end
     end
     for _, c in ipairs(_bossEventConns) do pcall(function() c:Disconnect() end) end
     _bossEventConns = {}

     -- Helper bossPos yang aman - [v34 FIX] prioritas HumanoidRootPart bukan Head
     local function GetSafeAscBossPos()
      -- [v34 FIX] HumanoidRootPart adalah anchor fisik yang benar untuk TP
      -- Head bisa floating di atas terrain / trigger animasi salah
      local headPart = boss and (
       boss.model:FindFirstChild("HumanoidRootPart")
       or boss.model.PrimaryPart
       or boss.model:FindFirstChild("Head")
      )
      if headPart and headPart.Parent then
       local p = headPart.Position
       -- [FIX ZOMBIE] Tolak: void (Y<-200), langit (Y>1500), posisi default (Magnitude<=10)
       if p.Y > -200 and p.Y < 1500 and p.Magnitude > 10 then return p end
      end
      return nil
     end

     -- [v35] Helper: offset posisi TP agar player tidak menindih HRP boss
     -- Berdiri 3 unit ke samping dari boss -> cegah part boss hilang/terpush physics
     local function _offsetFromBoss(basePos)
      if not basePos then return nil end
      local char = LP.Character
      local pHrp = char and char:FindFirstChild("HumanoidRootPart")
      local dir
      if pHrp then
       local d = (pHrp.Position - basePos)
       local dFlat = Vector3.new(d.X, 0, d.Z)
       dir = dFlat.Magnitude > 0.5 and dFlat.Unit or Vector3.new(1, 0, 0)
      else
       dir = Vector3.new(1, 0, 0)
      end
      return basePos + dir * 3
     end

     if boss and ASC.running and not _ascDone then
      local bossGuid = boss.guid
      local bossPos = GetSafeAscBossPos()
      if not bossPos then
       local _waitPos = 0
       while not bossPos and _waitPos < 3 and ASC.running and not _ascDone do
        task.wait(0.3); _waitPos = _waitPos + 0.3
        bossPos = GetSafeAscBossPos()
       end
      end

      -- [v48] Countdown bossDelay user-controlled (sama dengan RAID)
      local _bd = math.max(1, math.min(10, ASC.bossDelay or 3))
      for _ci = _bd, 1, -1 do
       if not ASC.running or _ascDone then break end
       AscStatusUpdate("[K] Boss: "..boss.model.Name.." - TP ".._ci.."s...", Color3.fromRGB(255,160,60))
       task.wait(1)
      end

      -- Refresh bossPos setelah countdown
      bossPos = GetSafeAscBossPos()
      local _refreshWait = 0
      while not bossPos and _refreshWait < 3 and ASC.running and not _ascDone do
       task.wait(0.3); _refreshWait = _refreshWait + 0.3
       bossPos = GetSafeAscBossPos()
      end

      if ASC.running and not _ascDone and bossPos then
       AscStatusUpdate("[K] Boss: "..boss.model.Name.." - Attack!", Color3.fromRGB(255,80,80))

       -- 1) TP Player ke posisi offset dari boss (3u samping) - cegah part boss hilang
       pcall(function()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local safePos = _offsetFromBoss(GetSafeAscBossPos())
        if hrp and safePos then hrp.CFrame = CFrame.new(safePos) end
       end)

       -- 2) TP semua hero client-side ke posisi offset dari boss
       pcall(function()
        local safePos2 = _offsetFromBoss(GetSafeAscBossPos())
        if not safePos2 then return end
        local heroFolder = workspace:FindFirstChild("Heros")
        if heroFolder then
         for _, hModel in ipairs(heroFolder:GetChildren()) do
          local hHrp = hModel:FindFirstChild("HumanoidRootPart")
          if hHrp then hHrp.CFrame = CFrame.new(safePos2) end
         end
        end
       end)

       -- 3) Fire hero remotes (pakai posisi boss asli untuk server-side damage)
       pcall(function()
        local safePos3 = GetSafeAscBossPos()
        if safePos3 then FireHeroRemotes(bossGuid, safePos3) end
       end)
       if RE.HeroStand and #HERO_GUIDS > 0 then
        local safePos3b = GetSafeAscBossPos()
        if safePos3b then
         for _, hGuid in ipairs(HERO_GUIDS) do
          pcall(function() RE.HeroStand:FireServer({ heroGuid=hGuid, userId=MY_USER_ID, standPos=safePos3b+Vector3.new(1,0,1) }) end)
         end
        end
       end

       -- 4) UnEquip -> EquipBest
       task.wait(0.3)
       if RE.UnEquipHero then pcall(function() RE.UnEquipHero:FireServer() end) end
       task.wait(0.3)
       if RE.EquipBestHero then pcall(function() RE.EquipBestHero:FireServer() end) end
       task.wait(0.3)

       -- 5) TP ulang hero setelah re-equip - offset dari boss
       pcall(function()
        local safePos5 = _offsetFromBoss(GetSafeAscBossPos())
        if not safePos5 then return end
        local heroFolder = workspace:FindFirstChild("Heros")
        if heroFolder then
         for _, hModel in ipairs(heroFolder:GetChildren()) do
          local hHrp = hModel:FindFirstChild("HumanoidRootPart")
          if hHrp then hHrp.CFrame = CFrame.new(safePos5) end
         end
        end
       end)
       pcall(function()
        local safePos5b = GetSafeAscBossPos()
        if safePos5b then FireHeroRemotes(bossGuid, safePos5b) end
       end)

       -- 6) KUNCI posisi player di titik offset dari boss - cegah physics overlap
       local _ascFrozenCFrame = nil
       local _ascFreezeConn = nil
       pcall(function()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local safePos6 = _offsetFromBoss(GetSafeAscBossPos())
        if hrp and safePos6 then
         _ascFrozenCFrame = CFrame.new(safePos6)
         hrp.Anchored = true
         hrp.CFrame = _ascFrozenCFrame
         _ascFreezeConn = RunService.Heartbeat:Connect(function()
          -- [FLa CPU] skip frame ganjil → efektif ~30fps
          if not _ascFreezeFrame then _ascFreezeFrame = 0 end
          _ascFreezeFrame = _ascFreezeFrame + 1
          if _ascFreezeFrame % 2 ~= 0 then return end
          if not ASC.running or _ascDone then
           pcall(function() hrp.Anchored = false end)
           if _ascFreezeConn then _ascFreezeConn:Disconnect(); _ascFreezeConn = nil end
           return
          end
          if hrp and hrp.Parent and _ascFrozenCFrame then
           hrp.CFrame = _ascFrozenCFrame
          end
         end)
        end
       end)

       local function UnfreezeAscPlayer()
        pcall(function()
         local char = LP.Character
         local hrp = char and char:FindFirstChild("HumanoidRootPart")
         if hrp then hrp.Anchored = false end
        end)
        if _ascFreezeConn then _ascFreezeConn:Disconnect(); _ascFreezeConn = nil end
       end

       local _tpTh = nil -- tidak ada background TP thread

       -- 7) Serang boss (sama dengan RAID: 0.08s per attack)
       AscStatusUpdate("[FLa] Attack: "..boss.model.Name, Color3.fromRGB(255,80,80))
       while ASC.running do
        -- Stop jika server sudah konfirmasi sukses
        if _ascServerDone then break end
        local _curMap = GetCurrentMapId()
        if _curMap and (_curMap < 50301 or _curMap > 50326) then
         AscStatusUpdate("[!] Player keluar Tower - stop attack", Color3.fromRGB(255,140,0))
         break
        end
        if not boss.model or not boss.model.Parent then break end
        local hum = boss.model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then break end
        local p = GetSafeAscBossPos()
        if not p then
         PG_Wait(0.08) -- [PingGuard] ASC boss attack
         if not boss.model or not boss.model.Parent then break end
         local hum2 = boss.model:FindFirstChildOfClass("Humanoid")
         if not hum2 or hum2.Health <= 0 then break end
         continue
        end
        task.spawn(function() pcall(function()
         FireAttack(bossGuid, p); FireAllDamage(bossGuid, p); FireHeroRemotes(bossGuid, p)
         FireAttack(bossGuid, p); FireAllDamage(bossGuid, p); FireHeroRemotes(bossGuid, p)
        end) end)
        PG_Wait(0.08) -- [PingGuard] ASC boss attack cycle
       end

       pcall(function() task.cancel(_tpTh) end)
       UnfreezeAscPlayer() -- lepas freeze player setelah boss mati
       -- Boss mati. _ascSuccess selalu true setelah attack loop selesai dari dalam tower.
       _ascSuccess = true
       if _ascServerDone then _ascSuccess = true end
       _ascDone = true
       AscStatusUpdate("[FLa] Boss Dead!", Color3.fromRGB(100,255,150))
      end -- if bossPos
     else
      -- Boss tidak ditemukan setelah 30s - last chance scan
      if not boss then
       pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
         if obj:IsA("Model") and IsBossAscWithHint(obj.Name) then
          local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("BossGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID")
          local hrp = obj:FindFirstChild("HumanoidRootPart")
          local hum = obj:FindFirstChildOfClass("Humanoid")
          if g and hrp and hum and hum.Health > 0 then
           boss = {guid=g, hrp=hrp, model=obj}; break
          end
         end
        end
       end)
      end
      if not boss and ASC.running then
       AscStatusUpdate("[FLa] Boss not found (30s) - Go Out...", Color3.fromRGB(255,150,50))
       task.wait(3)
      end
     end
    else
     -- Auto Kill Boss OFF - tunggu event ChallengeRaidsSuccess max 5 menit
     local _wt = 0
     while ASC.running and not _ascDone and _wt < 300 do
      task.wait(1); _wt = _wt + 1
      -- [v64 FIX] Guard keluar Tower: cek lebih komprehensif
      -- Jika player sudah tidak di Ascension Tower (50301-50326), berarti sudah keluar
      -- (bisa karena MA/RAID TP player keluar, atau server kick, atau kolisi event)
      local wm = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or 0
      if wm == 0 or (wm >= 50001 and wm <= 50028) then
       AscStatusUpdate("[!] Player keluar Tower (ext) - abort wait", Color3.fromRGB(255,140,0))
       break
      end
      -- Jika player tiba-tiba di map RAID normal atau Siege, juga keluar
      if (wm >= 50101 and wm <= 50120) or (wm >= 50201 and wm <= 50204) then
       AscStatusUpdate("[!] Player di map lain - abort wait", Color3.fromRGB(255,140,0))
       break
      end
     end
    end

    if connAS then pcall(function() connAS:Disconnect() end) end
    if connAF then pcall(function() connAF:Disconnect() end) end
    -- [v64 FIX] Cancel watchdog setelah keluar Tower normal
    if _watchdogTh then pcall(function() task.cancel(_watchdogTh) end) end

    if _ascSuccess then
     ASC.sukses = ASC.sukses + 1
     AscCounterUpdate()
     AscStatusUpdate("[OK] Sukses-"..ASC.sukses.." Tower "..mn, Color3.fromRGB(100,255,150))
    end
    if not ASC.running then break end

    -- Wait reward
    if _ascSuccess then
     AscStatusUpdate("[..] Wait 1s (Get reward)...", Color3.fromRGB(100,255,150))
     task.wait(1)
    end
    if not ASC.running then break end

    -- STEP 5: Collect + Exit Tower
    task.spawn(function() pcall(RaidCollectAll) end)
    AscStatusUpdate("[FLa] Go Out Tower...", Color3.fromRGB(100,200,255))

    RAID_LIVE[raidEntry.rawId] = nil
    if raidEntry.rawId ~= raidEntry.id then RAID_LIVE[raidEntry.id] = nil end
    if RebuildRaidList then pcall(RebuildRaidList) end

    -- Keluar dari Ascension Tower (kembali ke basemap Map 1)
    local _exitRe = Remotes:FindFirstChild("QuitRaidsMap")
    if _exitRe then
     pcall(function() _exitRe:FireServer({ currentSlotIndex = 2, toMapId = 50001 }) end)
    end
    task.wait(0.3)
    pcall(function() RE.LocalTp:FireServer({ mapId = 50001 }) end)
    -- Retry exit jika masih di Ascension Tower
    local _exitTry = 0
    local function _inAscArea()
     local ok, wm = pcall(function()
      return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or 0
     end)
     return (ok and wm >= 50301 and wm <= 50326)
    end
    while _inAscArea() and _exitTry < 5 and ASC.running do
     _exitTry = _exitTry + 1
     task.wait(1)
     if _exitRe then pcall(function() _exitRe:FireServer({ currentSlotIndex=2, toMapId=50001 }) end) end
     task.wait(0.2)
     pcall(function() RE.LocalTp:FireServer({ mapId=50001 }) end)
    end

    ASC.inMap = false
    ASC.serverMapId = nil -- [v64 FIX] Reset agar run berikutnya tidak pakai data stale
    ReleaseMapLock("asc") -- [v52 FIX] Pastikan lock selalu dilepas saat keluar map
    -- [v62 FIX] Reset status agar tidak nyantol di "Dalam Tower x" saat sudah di Lobby
    AscStatusUpdate("[>>] Keluar Tower - cooldown...", Color3.fromRGB(160,148,135))
    for cd = 14, 1, -1 do
     if not ASC.running then break end
     AscStatusUpdate("[..] Cooldown "..cd.."s...", Color3.fromRGB(160,148,135))
     if ASC.dot then ASC.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
     task.wait(1)
    end

    -- [v48] STEP 7: Standby loop setelah cooldown (sama dengan RAID)
    if ASC.running then
     AscStatusUpdate("[>>] Waiting & Cooldown...", Color3.fromRGB(100,255,150))
     if ASC.dot then ASC.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
     local _fw = 0
     while ASC.running do
      -- Cek busy (Siege / Dungeon)
      local isBusy = false
      if (SIEGE and (SIEGE.inMap or SIEGE.teleporting)) then isBusy = true end
      local _wm2 = workspace:GetAttribute("MapId") or 0
      if (_wm2 >= 50201 and _wm2 <= 50204) then isBusy = true end

      -- ASC cooldown loop tidak perlu reset flag ini lagi
      -- RAID sekarang independen: jalan saat ASC.inMap = false, pause saat ASC.inMap = true

      if isBusy then
       AscStatusUpdate("[!] PAUSE: Menunggu Siege/Dungeon Selesai...", Color3.fromRGB(255,100,100))
      else
       local nextEntry = ResolveAscEntry()
       if nextEntry then
        -- [FIX] Jangan set _ascBusy di sini -> MA bebas jalan selama cooldown
        -- _ascBusy di-set nanti saat ASC benar-benar masuk tower (setelah _ascInterrupt)
        -- Tapi RAID tetap perlu pause -> set _ascBusy agar RAID tidak rebutan masuk
        _ascBusy = true  -- RAID pause (tapi MA boleh jalan, MA cek ASC.inMap/_ascInterrupt)
        break
       end
       -- Tidak ada Tower yang cocok
       if #RAID_ID_LIST == 0 then
        -- Event habis total -> RAID boleh jalan, reset cycle flag
        _ascBusy = false
        _ascMatchedThisCycle = false  -- [v61 CYCLEFIX] siklus habis, reset
        _raidFallbackActive  = false
        _eventOwner = nil             -- [v62] reset penentu siapa yang dipanggil
        AscStatusUpdate("[>>] Menunggu event RAID baru dari server...", Color3.fromRGB(120,120,120))
       elseif #GetAscensionList() > 0 then
        -- Ada Ascension tapi tidak cocok filter (grade/map)
        -- [v61 CYCLEFIX] Jika ASC pernah match di siklus ini, pertahankan _ascBusy
        -- sampai siklus event benar-benar habis (RAID_LIVE kosong)
        if _ascMatchedThisCycle then
         _ascBusy = true  -- siklus ASC belum selesai, RAID tetap pause
         AscStatusUpdate("[||] ASC cycle aktif - RAID standby sampai event habis (".._fw.."s)", Color3.fromRGB(180,100,255))
        else
         AscStatusUpdate("[FLa] Waiting grade filter... (".._fw.."s)", Color3.fromRGB(200,255,150))
        end
       else
        -- Tidak ada Ascension, tapi masih ada Raid Normal di event ini
        -- [v61 CYCLEFIX] Jika ASC sudah dominasi siklus ini (pernah match),
        -- pertahankan _ascBusy sampai RAID_LIVE kosong (siklus habis)
        if _ascMatchedThisCycle then
         _ascBusy = true  -- siklus ASC belum habis, RAID tetap pause
         AscStatusUpdate("[||] Menunggu siklus event habis - RAID standby (".._fw.."s)", Color3.fromRGB(180,100,255))
        else
         -- ASC tidak pernah match di siklus ini -> lepas _ascBusy, RAID boleh fallback
         _ascBusy = false
         _raidFallbackActive = true   -- [v61 CYCLEFIX] tandai RAID sedang fallback
         _eventOwner = "raid"         -- [v62] giliran RAID di siklus ini
         if RAID.running then
          AscStatusUpdate("[Standby] Fallback ke Auto Raid (".._fw.."s)", Color3.fromRGB(140,100,200))
         else
          -- RAID OFF -> diam saja sampai event baru
          AscStatusUpdate("[FLa] Waiting Ascension Tower... (".._fw.."s)", Color3.fromRGB(160,120,60))
         end
        end
       end
      end
      -- Wakeup cepat
      local _woken2 = false
      local _wConn2
      if _ascWakeup then
       _wConn2 = _ascWakeup.Event:Connect(function() _woken2 = true end)
      end
      local _we2 = 0
      while not _woken2 and _we2 < 1 and ASC.running do
       task.wait(0.1); _we2 = _we2 + 0.1
      end
      if _wConn2 then pcall(function() _wConn2:Disconnect() end) end
      _fw = _fw + 1
     end
    end

   until true
  end -- while ASC.running
  end) -- pcall

  -- [v63 FIX] Cleanup dijamin jalan meskipun pcall catch error di dalam loop
  ASC.running = false
  ASC.inMap   = false
  _ascBusy    = false
  _ascInterrupt = false  -- [FIX] reset cleanup
  _ascOn      = false
  _ascDominatedThisEvent = false -- [v56 DEPRECATED] tidak dipakai lagi
  _ascMatchedThisCycle  = false  -- [v61 CYCLEFIX] reset saat ASC stop
  _raidFallbackActive   = false  -- [v61 CYCLEFIX] reset saat ASC stop
  ASC._rrIdx  = 0
  AscStatusUpdate("Auto Ascension STOP", Color3.fromRGB(160,148,135))
  if ASC.dot then ASC.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
 end)
end


-- ============================================================================
-- PANEL: AUTOMATION - AUTO RAID UI (WindUI Section accordion, identik 1.lua)
-- ============================================================================
do

-- Variabel state untuk Section collapse (slide up/down)
-- WindUI Section built-in sudah support collapse, tapi untuk full control
-- kita buat Section manual dengan callback seperti 1.lua (raidOpen/raidBody)

--  Warna grade untuk dropdown 
local GRADE_COLORS_UI = {
    ["E"]=Color3.fromRGB(150,150,150),["D"]=Color3.fromRGB(100,200,100),
    ["C"]=Color3.fromRGB(80,200,120),["B"]=Color3.fromRGB(100,140,255),
    ["A"]=Color3.fromRGB(180,100,255),["S"]=Color3.fromRGB(255,180,50),
    ["SS"]=Color3.fromRGB(255,220,0),["G"]=Color3.fromRGB(255,60,60),
    ["N"]=Color3.fromRGB(255,100,200),["M"]=Color3.fromRGB(255,0,0),
    ["M+"]=Color3.fromRGB(255,50,50),["M++"]=Color3.fromRGB(255,100,100),
    ["XM"]=Color3.fromRGB(180,0,0),["ULT"]=Color3.fromRGB(255,255,255),
}

--  PM (Pick Mode) config 
local PM_OPTS  = {"Default","By Rank","By Map","Hard","Easy","Manual"}
local PM_KEYS  = {"default","byrank","bymap","hard","easy","manual"}
local PM_TO_DIFF = {default="easy",byrank="easy",bymap="easy",hard="hard",easy="easy",manual="easy"}
local PM_UNLOCK = {
    -- map=Preferred Maps, rank=Preferred Rank, rune=Auto Item,
    -- updown=UP/DOWN (toggle+dir+grade), list=Raid List Entry
    default={map=false,rank=false,rune=false,updown=false,list=false},
    byrank ={map=false,rank=true, rune=false,updown=false,list=false},
    bymap  ={map=true, rank=false,rune=false,updown=false,list=false},
    hard   ={map=false,rank=false,rune=false,updown=false,list=false},
    easy   ={map=false,rank=false,rune=false,updown=false,list=false},
    manual ={map=true, rank=true, rune=true, updown=true, list=true },
}

--  WindUI Section: AUTO RAID (slide up/down) 
-- WindUI Tab:Section() sudah punya built-in collapse behavior (klik header = toggle)
-- Kita daftarkan semua elemen di dalam section yang sama

local raidSection = AutomationTab:Section({ Title = "Auto Raid", Icon = "sword", Opened = false, Box = true })

-- Status paragraph
local raidStatusPara = raidSection:Paragraph({
    Title = "Status",
    Desc  = "Disabled",
})
-- Expose ke RAID.statusLbl via wrapper (WindUI Paragraph tidak punya .Text property langsung)
-- Kita buat proxy: simpan ref ke Paragraph dan gunakan :Set()
local _raidStatusParaRef = raidStatusPara
RAID.statusLbl = {
    Text = "Disabled",
    TextColor3 = Color3.fromRGB(160,148,135),
}
-- Override RaidStatusUpdate agar update Paragraph WindUI
local _origRaidStatusUpdate = RaidStatusUpdate
RaidStatusUpdate = function(msg, color)
    if _raidStatusParaRef then
        pcall(function() _raidStatusParaRef:SetDesc(msg) end)
    end
    RAID.statusLbl.Text = msg
    RAID.statusLbl.TextColor3 = color or Color3.fromRGB(255,210,160)
end

-- Active Raid paragraph
local raidActivePara = raidSection:Paragraph({
    Title = "Active Raid",
    Desc  = "Waiting",
})
RAID.activeRaidLbl = {
    Text = "Waiting",
    TextColor3 = Color3.fromRGB(160,160,160),
}
local function UpdateActiveRaidLabel()
    pcall(function()
        if RAID.inMap and RAID.raidMapId then
            local rawMn = RAID.raidMapId - 50000
            local mn = RAID.serverMapId and (RAID.serverMapId - 50100) or rawMn
            local nm = MAP_NAMES and MAP_NAMES[mn] or ("Map "..tostring(mn))
            local grade = (_runeGradeCache and _runeGradeCache[mn]) or ""
            local gs = grade ~= "" and grade ~= "?" and (" ["..grade.."]") or ""
            local txt = "Map "..mn.." - "..nm..gs
            if _raidStatusParaRef then pcall(function() raidActivePara:SetDesc(txt) end) end
            RAID.activeRaidLbl.Text = txt
        else
            pcall(function() raidActivePara:SetDesc("Waiting") end)
            RAID.activeRaidLbl.Text = "Waiting"
        end
    end)
end
RAID.updateActiveLabel = UpdateActiveRaidLabel
-- [FIXED zombie] _raidReconnectAlive dijadikan flag bersama untuk loop-loop
-- tingkat atas yang seharusnya hidup sepanjang lifecycle script
task.spawn(function() while _raidReconnectAlive do task.wait(0.3); UpdateActiveRaidLabel() end end)

-- Raid Completed paragraph
local raidCompletedPara = raidSection:Paragraph({
    Title = "Raid Completed",
    Desc  = "0",
})
RAID.suksesLbl = {
    Text = "0",
    Parent = true, -- dummy agar RaidCounterUpdate tidak crash
}
local _origRaidCounterUpdate = RaidCounterUpdate
RaidCounterUpdate = function()
    RAID.suksesLbl.Text = tostring(RAID.sukses)
    pcall(function() raidCompletedPara:SetDesc(tostring(RAID.sukses)) end)
end

--  Enable Auto Raid Toggle 
local raidEnableToggle = raidSection:Toggle({
    Flag     = "raidEnable",
    Title    = "Enable Auto Raid",
    Desc     = "Aktifkan/matikan loop Auto Raid",
    Default  = false,
    Callback = function(on)
        _raidOn = on
        if on then StartRaidLoop()
        else StopRaid(); RaidStatusUpdate("Disabled", Color3.fromRGB(160,148,135)) end
    end,
})
_setRaidToggle = function(on)
    if on == _raidOn then return end
    _raidOn = on
    pcall(function() raidEnableToggle:Set(on, false) end)
    if on then StartRaidLoop()
    else StopRaid(); RaidStatusUpdate("Disabled", Color3.fromRGB(160,148,135)) end
end
-- Visual-only setter tanpa guard (untuk Config restore)
_visRaidToggle = function(on)
    pcall(function() raidEnableToggle:Set(on, false) end)
end

--  PICK MODE 
local curPM = 1
RAID.pickMode = PM_KEYS[curPM]

local raidPickModeDD = raidSection:Dropdown({
    Flag     = "raidPickMode",
    Title    = "Pick Mode",
    Desc     = "Pilih strategi pemilihan raid",
    Multi    = false,
    Value    = PM_OPTS[curPM],
    Values   = PM_OPTS,
    Callback = function(val)
        for i, opt in ipairs(PM_OPTS) do
            if opt == val then
                curPM = i
                RAID.pickMode = PM_KEYS[i]
                RAID.difficulty = PM_TO_DIFF[PM_KEYS[i]]
                RAID.snapshotMapId = nil
                if _applyPickModeLock then _applyPickModeLock(PM_KEYS[i]) end
                break
            end
        end
    end,
})
_setRaidPMIdx = function(ii)
    if ii < 1 or ii > #PM_KEYS then return end
    curPM = ii; RAID.pickMode = PM_KEYS[ii]
    RAID.difficulty = PM_TO_DIFF[PM_KEYS[ii]]; RAID.snapshotMapId = nil
    pcall(function() raidPickModeDD:Select(PM_OPTS[ii]) end)
    if _applyPickModeLock then _applyPickModeLock(PM_KEYS[ii]) end
end

--  PREFERRED MAPS
-- Default: KOSONG (tidak ada map terpilih = masuk semua map)
-- JANGAN pre-fill semua map - user tidak bisa unselect di WindUI multi dropdown kalau semua dipilih

local _mapOptNames = {"-- NOT SELECTED --"}
for i = 1, 20 do table.insert(_mapOptNames, "Map "..i) end
local _mapInitVal = {}
for i = 1, 20 do if RAID.preferMaps[i] then table.insert(_mapInitVal, "Map "..i) end end
if #_mapInitVal == 0 then _mapInitVal = {"-- NOT SELECTED --"} end

local raidPrefMapDD = raidSection:Dropdown({
    Flag     = "raidPrefMaps",
    Title    = "Preferred Maps",
    Desc     = "Pilih map yang ingin dimasuki (kosong = semua)",
    Multi    = true,
    Value    = _mapInitVal,
    Values   = _mapOptNames,
    Callback = function(val)
        for mn = 1, 20 do RAID.preferMaps[mn] = nil end
        if type(val) == "table" then
            -- Jika user pilih NOT SELECTED, clear semua dan reset visual
            local hasNotSel = false
            for _, v in ipairs(val) do
                if v == "-- NOT SELECTED --" then hasNotSel = true; break end
            end
            if hasNotSel then
                pcall(function() raidPrefMapDD:Select({"-- NOT SELECTED --"}) end)
                return
            end
            for _, v in ipairs(val) do
                local mi = tonumber(v:match("Map (%d+)"))
                if mi then RAID.preferMaps[mi] = true end
            end
        end
    end,
})
local function UpdatePrefLabel()
    local n = 0; local ns = {}
    for mn in pairs(RAID.preferMaps) do n=n+1; table.insert(ns,"Map "..mn) end
    table.sort(ns)
    if n == 0 then
        pcall(function() raidPrefMapDD:Select({"-- NOT SELECTED --"}) end)
    else
        pcall(function() raidPrefMapDD:Select(ns) end)
    end
end
_raidUpdatePrefLabel = UpdatePrefLabel

--  PREFERRED RANK 
local _rankInitVal = {}
for _, g in ipairs(GRADE_LIST) do
    if RAID.runeGrades[g] then table.insert(_rankInitVal, g) end
end

local _rankOptNames = {"-- NOT SELECTED --"}
for _, g in ipairs(GRADE_LIST) do table.insert(_rankOptNames, g) end
if #_rankInitVal == 0 then _rankInitVal = {"-- NOT SELECTED --"} end

local raidRankDD = raidSection:Dropdown({
    Flag     = "raidRank",
    Title    = "Preferred Rank",
    Desc     = "Filter rank raid yang ingin dimasuki",
    Multi    = true,
    Value    = _rankInitVal,
    Values   = _rankOptNames,
    Callback = function(val)
        for _, g in ipairs(GRADE_LIST) do RAID.runeGrades[g] = nil end
        if type(val) == "table" then
            -- Jika user pilih NOT SELECTED, clear semua dan reset visual
            local hasNotSel = false
            for _, v in ipairs(val) do
                if v == "-- NOT SELECTED --" then hasNotSel = true; break end
            end
            if hasNotSel then
                pcall(function() raidRankDD:Select({"-- NOT SELECTED --"}) end)
                if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
                return
            end
            for _, v in ipairs(val) do
                if GRADE_RANK[v] then RAID.runeGrades[v] = true end
            end
        end
        if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
    end,
})
local function RefreshRankDDLabel()
    local ns = {}
    for _, g in ipairs(GRADE_LIST) do
        if RAID.runeGrades[g] then table.insert(ns, g) end
    end
    if #ns == 0 then
        pcall(function() raidRankDD:Select({"-- NOT SELECTED --"}) end)
    else
        pcall(function() raidRankDD:Select(ns) end)
    end
end
_raidUpdateRankLabel = RefreshRankDDLabel

--  PREFERRED RUNE (Auto Item) 
local _runeOptNames = {"-- NOT SELECTED --"}
for mn = 1, 20 do
    table.insert(_runeOptNames, "Map "..mn.." - "..(MAP_NAMES[mn] or "Map "..mn))
end

local _runeInitVal = nil
if RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 20 then
    _runeInitVal = "Map "..RAID.runeMapTarget.." - "..(MAP_NAMES[RAID.runeMapTarget] or "Map "..RAID.runeMapTarget)
end

local raidRuneDD = raidSection:Dropdown({
    Flag     = "raidRune",
    Title    = "Auto Item (Rune Map)",
    Desc     = "Pilih map target item rune (opsional)",
    Multi    = false,
    Value    = _runeInitVal,
    Values   = _runeOptNames,
    Callback = function(val)
        if not val or val == "-- NOT SELECTED --" then
            RAID.runeMapTarget = 0; RAID.runeEnabled = false
        else
            local mi = tonumber(val:match("Map (%d+)"))
            if mi and mi >= 1 and mi <= 20 then
                RAID.runeMapTarget = mi; RAID.runeEnabled = true
            end
        end
    end,
})
local function SyncRuneState()
    if RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 20 then RAID.runeEnabled = true
    else RAID.runeEnabled = false end
end
_syncRaidRuneState = SyncRuneState
_setRaidRuneMapTarget = function(ml)
    RAID.runeMapTarget = ml or 0; SyncRuneState()
    if ml and ml >= 1 and ml <= 20 then
        local txt = "Map "..ml.." - "..(MAP_NAMES[ml] or "Map "..ml)
        pcall(function() raidRuneDD:Select(txt) end)
    else
        pcall(function() raidRuneDD:Select("-- NOT SELECTED --") end)
    end
end

--  UP/DOWN RANK 
-- updownDir default nil = NOT SELECTED

local raidUDToggle = raidSection:Toggle({
    Flag     = "raidUD",
    Title    = "UP/DOWN Rank",
    Desc     = "Fire UseRaidItem setelah masuk raid untuk naik/turun rank",
    Default  = RAID.updownEnabled or false,
    Callback = function(on)
        RAID.updownEnabled = on
    end,
})
_raidUpdownToggleVis = function(on)
    RAID.updownEnabled = on
    pcall(function() raidUDToggle:Set(on, false) end)
end

local raidUDDirDD = raidSection:Dropdown({
    Flag     = "raidUDDir",
    Title    = "UP/DOWN Direction",
    Desc     = "Arah rank yang diinginkan",
    Multi    = false,
    Value    = RAID.updownDir == "up" and "UP" or RAID.updownDir == "down" and "DOWN" or "-- NOT SELECTED --",
    Values   = {"-- NOT SELECTED --","UP","DOWN"},
    Callback = function(val)
        if val == "-- NOT SELECTED --" then
            RAID.updownDir = nil
        elseif val == "UP" then
            RAID.updownDir = "up"
        else
            RAID.updownDir = "down"
        end
    end,
})
_raidUpdownDirVis = function(dir)
    RAID.updownDir = dir or nil
    local disp = dir == "up" and "UP" or dir == "down" and "DOWN" or "-- NOT SELECTED --"
    pcall(function() raidUDDirDD:Select(disp) end)
end

local _targetGrades = {}
for i = 6, #GRADE_LIST do table.insert(_targetGrades, GRADE_LIST[i]) end
table.insert(_targetGrades, 1, "-- NOT SELECTED --")

local raidUDGradeDD = raidSection:Dropdown({
    Flag     = "raidUDGrade",
    Title    = "UP/DOWN Target Grade",
    Desc     = "Grade target lobi untuk UP/DOWN Rank",
    Multi    = false,
    Value    = RAID.updownTargetGrade or "-- NOT SELECTED --",
    Values   = _targetGrades,
    Callback = function(val)
        if val == "-- NOT SELECTED --" then RAID.updownTargetGrade = nil
        else RAID.updownTargetGrade = val end
    end,
})
_setRaidUpdownGrade = function(grade)
    RAID.updownTargetGrade = grade or nil
    pcall(function() raidUDGradeDD:Select(grade or "-- NOT SELECTED --") end)
end

--  AUTO KILL BOSS 
local raidBossToggle = raidSection:Toggle({
    Flag     = "raidBoss",
    Title    = "AUTO KILL BOSS",
    Desc     = "Teleport ke boss dan auto attack sampai mati",
    Default  = RAID.autoKillBoss or false,
    Callback = function(on)
        RAID.autoKillBoss = on
    end,
})
_raidBossToggleVis = function(on)
    RAID.autoKillBoss = on
    pcall(function() raidBossToggle:Set(on, false) end)
end

--  TELEPORT DELAY SLIDER 
local raidBossDelaySlider = raidSection:Slider({
    Flag     = "raidBossDelay",
    Title    = "Teleport Delay (s)",
    Desc     = "Delay sebelum teleport ke boss (1-10 detik)",
    Value    = { Min = 1, Max = 10, Default = RAID.bossDelay or 3 },
    Step     = 1,
    Callback = function(val)
        RAID.bossDelay = math.clamp(math.floor(val + 0.5), 1, 10)
    end,
})
_raidBossDelaySet = function(val)
    RAID.bossDelay = math.clamp(math.round(val), 1, 10)
    pcall(function() raidBossDelaySlider:Set(RAID.bossDelay) end)
end

--  RAID LIST ENTRY 
local raidListSection = raidSection:Section({ Title = "Raid List Entry", Icon = "list", Opened = false, Box = true })

local raidListToggle = raidListSection:Toggle({
    Flag     = "raidListEnabled",
    Title    = "List Entry",
    Desc     = "Aktifkan sistem antrian entry map+rank",
    Default  = RAID.listEnabled or false,
    Callback = function(on)
        RAID.listEnabled = on
        if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
    end,
})
_setRaidListEnabledVis = function(on)
    RAID.listEnabled = on
    pcall(function() raidListToggle:Set(on, false) end)
end

-- Save Entry button: snapshot maps + rank sekarang ke list
local raidListSaveBtn = raidListSection:Button({
    Title    = "+ Save Entry",
    Desc     = "Simpan kombinasi map+rank sekarang ke list",
    Callback = function()
        local snapMaps = {}; for mn,v in pairs(RAID.preferMaps) do snapMaps[mn]=v end
        local snapRanks = {}; for g,v in pairs(RAID.runeGrades) do snapRanks[g]=v end
        table.insert(RAID.listEntries, {maps=snapMaps, ranks=snapRanks})
        -- Rebuild display
        if _raidRebuildListRows then _raidRebuildListRows() end
    end,
})

-- Entry list paragraph (tampilkan daftar entry)
local _raidListPara = raidListSection:Paragraph({
    Title = "Saved Entries",
    Desc  = "(kosong)",
})
local function RebuildListDisplay()
    if #RAID.listEntries == 0 then
        pcall(function() _raidListPara:SetDesc("(kosong)") end)
        return
    end
    local lines = {}
    for i, ent in ipairs(RAID.listEntries) do
        local mapsStr
        if not next(ent.maps) then mapsStr = "All Maps"
        else
            local ms = {}; for mn in pairs(ent.maps) do table.insert(ms,mn) end
            table.sort(ms); local parts = {}
            for _, mn in ipairs(ms) do table.insert(parts, "M"..mn) end
            mapsStr = table.concat(parts,",")
        end
        local ranksStr
        if not next(ent.ranks) then ranksStr = "All"
        else
            local rs = {}
            for _, g in ipairs(GRADE_LIST) do if ent.ranks[g] then table.insert(rs,g) end end
            ranksStr = table.concat(rs,"/")
        end
        table.insert(lines, "#"..i.." "..mapsStr.." | "..ranksStr)
    end
    pcall(function() _raidListPara:SetDesc(table.concat(lines,"\n")) end)
end
_raidRebuildListRows = RebuildListDisplay

-- Tombol hapus entry terakhir
local raidListDeleteBtn = raidListSection:Button({
    Title    = "- Hapus Entry Terakhir",
    Desc     = "Hapus entry paling bawah dari list",
    Callback = function()
        if #RAID.listEntries > 0 then
            table.remove(RAID.listEntries)
            RebuildListDisplay()
        end
    end,
})

--  APPLY PICK MODE LOCK 
-- Dipanggil saat Pick Mode berubah.
-- Lock = clear data + reset UI ke NOT SELECTED + update Desc sebagai indikator visual.
-- WindUI tidak punya :SetEnabled() native, jadi kita gunakan flag guard + Desc label.

local function _doApplyLock(pm)
    local u = PM_UNLOCK[pm] or {map=false,rank=false,rune=false,updown=false,list=false}
    local lockMsg = "Tidak tersedia di mode " .. pm

    -- Preferred Maps
    _prefLocked = not u.map
    if _prefLocked then
        for k in pairs(RAID.preferMaps) do RAID.preferMaps[k] = nil end
        pcall(function() raidPrefMapDD:Select({}) end)
        pcall(function() raidPrefMapDD:Lock(lockMsg) end)
    else
        pcall(function() raidPrefMapDD:Unlock() end)
    end

    -- Preferred Rank
    _rankLocked = not u.rank
    if _rankLocked then
        for _, g in ipairs(GRADE_LIST) do RAID.runeGrades[g] = nil end
        pcall(function() raidRankDD:Select({}) end)
        pcall(function() raidRankDD:Lock(lockMsg) end)
    else
        pcall(function() raidRankDD:Unlock() end)
    end

    -- Auto Item (Rune)
    _runeLocked = not u.rune
    if _runeLocked then
        RAID.runeMapTarget = 0; RAID.runeEnabled = false
        pcall(function() raidRuneDD:Select("-- NOT SELECTED --") end)
        pcall(function() raidRuneDD:Lock(lockMsg) end)
    else
        pcall(function() raidRuneDD:Unlock() end)
    end

    -- UP/DOWN Rank + Direction + Target Grade
    _updownLocked = not u.updown
    if _updownLocked then
        RAID.updownEnabled = false; RAID.updownDir = nil; RAID.updownTargetGrade = nil
        pcall(function() raidUDToggle:Set(false, false) end)
        pcall(function() raidUDDirDD:Select("-- NOT SELECTED --") end)
        pcall(function() raidUDGradeDD:Select("-- NOT SELECTED --") end)
        pcall(function() raidUDToggle:Lock(lockMsg) end)
        pcall(function() raidUDDirDD:Lock(lockMsg) end)
        pcall(function() raidUDGradeDD:Lock(lockMsg) end)
    else
        pcall(function() raidUDToggle:Unlock() end)
        pcall(function() raidUDDirDD:Unlock() end)
        pcall(function() raidUDGradeDD:Unlock() end)
    end

    -- Raid List Entry
    _listLocked = not u.list
    if _listLocked then
        RAID.listEnabled = false
        pcall(function() raidListToggle:Set(false, false) end)
        pcall(function() raidListToggle:Lock(lockMsg) end)
        pcall(function() raidListSaveBtn:Lock(lockMsg) end)
        pcall(function() raidListDeleteBtn:Lock(lockMsg) end)
    else
        pcall(function() raidListToggle:Unlock() end)
        pcall(function() raidListSaveBtn:Unlock() end)
        pcall(function() raidListDeleteBtn:Unlock() end)
    end
end

_applyPickModeLock = _doApplyLock

-- Inisialisasi flag lock sesuai pickMode awal
_prefLocked   = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).map
_rankLocked   = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).rank
_runeLocked   = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).rune
_updownLocked = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).updown
_listLocked   = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).list

-- Apply lock saat script load (defer agar semua elemen sudah terdaftar ke WindUI)
task.defer(function() _doApplyLock(RAID.pickMode or "default") end)

RebuildListDisplay()

end -- end do: AUTO RAID UI


-- ============================================================================
-- PANEL: AUTOMATION - AUTO RAID ASCENSION UI (WindUI Section accordion)
-- Port dari 1.lua baris 14700-15506 ke WindUI, mengikuti pattern raidSection
-- Ditaruh DI BAWAH Auto Raid (AutomationTab:Section sendiri, slide up/down
-- bawaan WindUI Section), independen dari RAID Normal (sesuai keputusan)
-- ============================================================================
do

local ascSection = AutomationTab:Section({ Title = "Auto Raid Ascension", Icon = "swords", Opened = false, Box = true })

--  STATUS 
local ascStatusPara = ascSection:Paragraph({
    Title = "Status",
    Desc  = "Disabled",
})
ASC.statusLbl = {
    Text = "Disabled",
    TextColor3 = Color3.fromRGB(160,148,135),
}
local _origAscStatusUpdate = AscStatusUpdate
AscStatusUpdate = function(msg, color)
    pcall(function() ascStatusPara:SetDesc(msg) end)
    ASC.statusLbl.Text = msg
    ASC.statusLbl.TextColor3 = color or Color3.fromRGB(255,200,100)
end

--  ASCENSION COMPLETED 
local ascCompletedPara = ascSection:Paragraph({
    Title = "Ascension Completed",
    Desc  = "0",
})
ASC.suksesLbl = {
    Text = "0",
}
local _origAscCounterUpdate = AscCounterUpdate
AscCounterUpdate = function()
    ASC.suksesLbl.Text = tostring(ASC.sukses)
    pcall(function() ascCompletedPara:SetDesc(tostring(ASC.sukses)) end)
end

--  ENABLE AUTO ASCENSION TOGGLE 
local ascEnableToggle = ascSection:Toggle({
    Flag     = "ascEnable",
    Title    = "Enable Auto Ascension",
    Desc     = "Aktifkan/matikan loop Auto Raid Ascension",
    Default  = false,
    Callback = function(on)
        _ascOn = on
        if on then StartAscensionLoop()
        else StopAscension(); AscStatusUpdate("Disabled", Color3.fromRGB(160,148,135)) end
    end,
})
_setAscToggle = function(on)
    if on == _ascOn then return end
    _ascOn = on
    pcall(function() ascEnableToggle:Set(on, false) end)
    if on then StartAscensionLoop()
    else StopAscension(); AscStatusUpdate("Disabled", Color3.fromRGB(160,148,135)) end
end
-- Visual-only setter tanpa guard (untuk Config restore)
_visAscToggle = function(on)
    pcall(function() ascEnableToggle:Set(on, false) end)
end

--  PICK MODE 
local APM_OPTS   = {"Default","By Rank","By Map","Hard","Easy","Manual"}
local APM_KEYS   = {"default","byrank","bymap","hard","easy","manual"}
local APM_TO_DESC = {
    default = "Join Tower apapun tanpa filter",
    byrank  = "Filter by Preferred Rank",
    bymap   = "Filter by Preferred Map",
    hard    = "Selalu pilih Tower terbesar",
    easy    = "Selalu pilih Tower terkecil",
    manual  = "Setting manual: Map, Rank, Rune",
}
-- Unlock rule per mode (identik 1.lua APM_UNLOCK):
local APM_UNLOCK = {
    default = {map=false, rank=false, rune=false},
    byrank  = {map=false, rank=true,  rune=false},
    bymap   = {map=true,  rank=false, rune=false},
    hard    = {map=false, rank=false, rune=false},
    easy    = {map=false, rank=false, rune=false},
    manual  = {map=true,  rank=true,  rune=true },
}
local curAPM = 5 -- default: "easy" (sama seperti 1.lua)
ASC.pickMode = APM_KEYS[curAPM]

local ascPickModeDD = ascSection:Dropdown({
    Flag     = "ascPickMode",
    Title    = "Pick Mode",
    Desc     = APM_TO_DESC[ASC.pickMode],
    Multi    = false,
    Value    = APM_OPTS[curAPM],
    Values   = APM_OPTS,
    Callback = function(val)
        for i, opt in ipairs(APM_OPTS) do
            if opt == val then
                curAPM = i
                ASC.pickMode = APM_KEYS[i]
                pcall(function() ascPickModeDD:SetDesc(APM_TO_DESC[ASC.pickMode]) end)
                if _applyAscPickModeLock then _applyAscPickModeLock(ASC.pickMode) end
                break
            end
        end
    end,
})
_setAscPMIdx = function(ii)
    if ii < 1 or ii > #APM_KEYS then return end
    curAPM = ii; ASC.pickMode = APM_KEYS[ii]
    pcall(function() ascPickModeDD:Select(APM_OPTS[ii]) end)
    if _applyAscPickModeLock then _applyAscPickModeLock(ASC.pickMode) end
end

--  PREFERRED MAP (Tower tujuan masuk, 1-26) 
-- Default: KOSONG (tidak ada Tower terpilih = masuk semua Tower)
local ASC_TOWER_NAMES = {
    [1]="Baran",       [2]="Baran+1",
    [3]="Grendal",     [4]="Grendal+1",
    [5]="Plague",      [6]="Plague+1",
    [7]="Frostborne",  [8]="Frostborne+1",
    [9]="Legia",       [10]="Legia+1",
    [11]="Silas",      [12]="Silas+1",
    [13]="Yogumunt",   [14]="Yogumunt+1",
    [15]="Antares",    [16]="Antares+1",
    [17]="Ashborn",    [18]="Ashborn+1",
    [19]="Dominion",   [20]="Dominion+1",
    [21]="Absolute",   [22]="Absolute+1",
    [23]="Broly",      [24]="Broly+1",
    [25]="Goku Super 4", [26]="Goku Super 4+1",
}

local _ascMapOptNames = {"-- NOT SELECTED --"}
for i = 1, 26 do table.insert(_ascMapOptNames, "Tower "..i.." - "..(ASC_TOWER_NAMES[i] or ("Tower "..i))) end
local _ascMapInitVal = {}
for i = 1, 26 do if ASC.preferMaps[i] then table.insert(_ascMapInitVal, "Tower "..i.." - "..(ASC_TOWER_NAMES[i] or ("Tower "..i))) end end
if #_ascMapInitVal == 0 then _ascMapInitVal = {"-- NOT SELECTED --"} end

local ascPrefMapDD = ascSection:Dropdown({
    Flag     = "ascPrefMap",
    Title    = "Preferred Map",
    Desc     = "Pilih Tower yang ingin dimasuki (kosong = semua)",
    Multi    = true,
    Value    = _ascMapInitVal,
    Values   = _ascMapOptNames,
    Callback = function(val)
        for mn = 1, 26 do ASC.preferMaps[mn] = nil end
        if type(val) == "table" then
            local hasNotSel = false
            for _, v in ipairs(val) do
                if v == "-- NOT SELECTED --" then hasNotSel = true; break end
            end
            if hasNotSel then
                pcall(function() ascPrefMapDD:Select({"-- NOT SELECTED --"}) end)
                return
            end
            for _, v in ipairs(val) do
                local mi = tonumber(v:match("Tower (%d+)"))
                if mi then ASC.preferMaps[mi] = true end
            end
        end
    end,
})
local function UpdateAscPrefMapLabel()
    local ns = {}
    for mn = 1, 26 do
        if ASC.preferMaps[mn] then table.insert(ns, "Tower "..mn.." - "..(ASC_TOWER_NAMES[mn] or ("Tower "..mn))) end
    end
    if #ns == 0 then
        pcall(function() ascPrefMapDD:Select({"-- NOT SELECTED --"}) end)
    else
        pcall(function() ascPrefMapDD:Select(ns) end)
    end
end

--  PREFERRED RANK 
local _ascRankInitVal = {}
for _, g in ipairs(GRADE_LIST) do
    if ASC.runeGrades[g] then table.insert(_ascRankInitVal, g) end
end
local _ascRankOptNames = {"-- NOT SELECTED --"}
for _, g in ipairs(GRADE_LIST) do table.insert(_ascRankOptNames, g) end
if #_ascRankInitVal == 0 then _ascRankInitVal = {"-- NOT SELECTED --"} end

local ascRankDD = ascSection:Dropdown({
    Flag     = "ascRank",
    Title    = "Preferred Rank",
    Desc     = "Filter rank Tower yang ingin dimasuki",
    Multi    = true,
    Value    = _ascRankInitVal,
    Values   = _ascRankOptNames,
    Callback = function(val)
        for _, g in ipairs(GRADE_LIST) do ASC.runeGrades[g] = nil end
        if type(val) == "table" then
            local hasNotSel = false
            for _, v in ipairs(val) do
                if v == "-- NOT SELECTED --" then hasNotSel = true; break end
            end
            if hasNotSel then
                pcall(function() ascRankDD:Select({"-- NOT SELECTED --"}) end)
                if _ascWakeup then pcall(function() _ascWakeup:Fire() end) end
                return
            end
            for _, v in ipairs(val) do
                if GRADE_RANK[v] then ASC.runeGrades[v] = true end
            end
        end
        if _ascWakeup then pcall(function() _ascWakeup:Fire() end) end
    end,
})
local function RefreshAscRankLabel()
    local ns = {}
    for _, g in ipairs(GRADE_LIST) do if ASC.runeGrades[g] then table.insert(ns, g) end end
    if #ns == 0 then
        pcall(function() ascRankDD:Select({"-- NOT SELECTED --"}) end)
    else
        pcall(function() ascRankDD:Select(ns) end)
    end
end

--  PREFERRED RUNE (Auto Item) 
local _ascRuneOptNames = {"-- NOT SELECTED --"}
for mn = 1, 26 do
    table.insert(_ascRuneOptNames, "Tower "..mn.." - "..(ASC_TOWER_NAMES[mn] or ("Tower "..mn)))
end
local _ascRuneInitVal = nil
if ASC.runeMapTarget >= 1 and ASC.runeMapTarget <= 26 then
    _ascRuneInitVal = "Tower "..ASC.runeMapTarget.." - "..(ASC_TOWER_NAMES[ASC.runeMapTarget] or ("Tower "..ASC.runeMapTarget))
end

local ascRuneDD = ascSection:Dropdown({
    Flag     = "ascRune",
    Title    = "Auto Item (Rune Tower)",
    Desc     = "Pilih Tower target item rune (opsional)",
    Multi    = false,
    Value    = _ascRuneInitVal,
    Values   = _ascRuneOptNames,
    Callback = function(val)
        if not val or val == "-- NOT SELECTED --" then
            ASC.runeMapTarget = 0; ASC.runeEnabled = false
        else
            local mi = tonumber(val:match("Tower (%d+)"))
            if mi and mi >= 1 and mi <= 26 then
                ASC.runeMapTarget = mi; ASC.runeEnabled = true
            end
        end
    end,
})
local function AscSyncRuneState()
    if ASC.runeMapTarget >= 1 and ASC.runeMapTarget <= 26 then ASC.runeEnabled = true
    else ASC.runeEnabled = false end
end
AscSyncRuneState()

--  AUTO KILL BOSS 
local ascBossToggle = ascSection:Toggle({
    Flag     = "ascBoss",
    Title    = "AUTO KILL BOSS",
    Desc     = "Teleport ke boss dan auto attack sampai mati",
    Default  = ASC.autoKillBoss or false,
    Callback = function(on)
        ASC.autoKillBoss = on
    end,
})
_ascBossToggleVis = function(on)
    ASC.autoKillBoss = on
    pcall(function() ascBossToggle:Set(on, false) end)
end

--  TELEPORT DELAY SLIDER 
local ascBossDelaySlider = ascSection:Slider({
    Flag     = "ascBossDelay",
    Title    = "Teleport Delay (s)",
    Desc     = "Delay sebelum teleport ke boss (1-10 detik)",
    Value    = { Min = 1, Max = 10, Default = ASC.bossDelay or 3 },
    Step     = 1,
    Callback = function(val)
        ASC.bossDelay = math.clamp(math.floor(val + 0.5), 1, 10)
    end,
})
_ascBossDelaySet = function(val)
    ASC.bossDelay = math.clamp(math.round(val), 1, 10)
    pcall(function() ascBossDelaySlider:Set(ASC.bossDelay) end)
end

--  LIST ENTRY ASC 
local ascListSection = ascSection:Section({ Title = "Ascension List Entry", Icon = "list", Opened = false, Box = true })

local ascListToggle = ascListSection:Toggle({
    Flag     = "ascListEnabled",
    Title    = "List Entry",
    Desc     = "Aktifkan sistem antrian entry Tower+rank",
    Default  = ASC.listEnabled or false,
    Callback = function(on)
        ASC.listEnabled = on
        if _ascWakeup then pcall(function() _ascWakeup:Fire() end) end
    end,
})
_setAscListEnabledVis = function(on)
    ASC.listEnabled = on
    pcall(function() ascListToggle:Set(on, false) end)
end

local ascListSaveBtn = ascListSection:Button({
    Title    = "+ Save Entry",
    Desc     = "Simpan kombinasi Tower+rank sekarang ke list",
    Callback = function()
        local snapMaps = {}
        for mn = 1, 26 do if ASC.preferMaps[mn] then snapMaps[mn] = true end end
        local snapRanks = {}
        for _, g in ipairs(GRADE_LIST) do if ASC.runeGrades[g] then snapRanks[g] = true end end
        -- Cegah duplikat (identik 1.lua)
        for _, ent in ipairs(ASC.listEntries) do
            local dupMap, dupRank = true, true
            for mn = 1, 26 do
                if (snapMaps[mn] ~= nil) ~= (ent.maps[mn] ~= nil) then dupMap = false; break end
            end
            for _, g in ipairs(GRADE_LIST) do
                if (snapRanks[g] ~= nil) ~= (ent.ranks[g] ~= nil) then dupRank = false; break end
            end
            if dupMap and dupRank then return end
        end
        table.insert(ASC.listEntries, {maps=snapMaps, ranks=snapRanks})
        if _ascRebuildListRows then _ascRebuildListRows() end
    end,
})

local _ascListPara = ascListSection:Paragraph({
    Title = "Saved Entries",
    Desc  = "(kosong)",
})
local function AscRebuildListDisplay()
    if #ASC.listEntries == 0 then
        pcall(function() _ascListPara:SetDesc("(kosong)") end)
        return
    end
    local lines = {}
    for i, ent in ipairs(ASC.listEntries) do
        local mapsStr
        if not next(ent.maps) then mapsStr = "All Tower"
        else
            local ms = {}; for mn in pairs(ent.maps) do table.insert(ms, mn) end
            table.sort(ms); local parts = {}
            for _, mn in ipairs(ms) do table.insert(parts, "T"..mn) end
            mapsStr = table.concat(parts, ",")
        end
        local ranksStr
        if not next(ent.ranks) then ranksStr = "All"
        else
            local rs = {}
            for _, g in ipairs(GRADE_LIST) do if ent.ranks[g] then table.insert(rs, g) end end
            ranksStr = table.concat(rs, "/")
        end
        table.insert(lines, "#"..i.." "..mapsStr.." | "..ranksStr)
    end
    pcall(function() _ascListPara:SetDesc(table.concat(lines, "\n")) end)
end
_ascRebuildListRows = AscRebuildListDisplay

local ascListDeleteBtn = ascListSection:Button({
    Title    = "- Hapus Entry Terakhir",
    Desc     = "Hapus entry paling bawah dari list",
    Callback = function()
        if #ASC.listEntries > 0 then
            table.remove(ASC.listEntries)
            AscRebuildListDisplay()
        end
    end,
})

--  APPLY ASC PICK MODE LOCK 
-- Dipanggil saat Pick Mode berubah. Identik pattern RAID: lock = clear data + Lock()/Unlock()
local _ascPrefLocked, _ascRankLocked, _ascRuneLocked = false, false, false

local function _doApplyAscLock(pm)
    local u = APM_UNLOCK[pm] or {map=false, rank=false, rune=false}
    local lockMsg = "Tidak tersedia di mode " .. pm

    -- Preferred Map
    _ascPrefLocked = not u.map
    if _ascPrefLocked then
        for mn = 1, 26 do ASC.preferMaps[mn] = nil end
        pcall(function() ascPrefMapDD:Select({}) end)
        pcall(function() ascPrefMapDD:Lock(lockMsg) end)
    else
        pcall(function() ascPrefMapDD:Unlock() end)
    end

    -- Preferred Rank
    _ascRankLocked = not u.rank
    if _ascRankLocked then
        for _, g in ipairs(GRADE_LIST) do ASC.runeGrades[g] = nil end
        pcall(function() ascRankDD:Select({}) end)
        pcall(function() ascRankDD:Lock(lockMsg) end)
    else
        pcall(function() ascRankDD:Unlock() end)
    end

    -- Auto Item (Rune)
    _ascRuneLocked = not u.rune
    if _ascRuneLocked then
        ASC.runeMapTarget = 0; ASC.runeEnabled = false
        pcall(function() ascRuneDD:Select("-- NOT SELECTED --") end)
        pcall(function() ascRuneDD:Lock(lockMsg) end)
    else
        pcall(function() ascRuneDD:Unlock() end)
    end
end

_applyAscPickModeLock = _doApplyAscLock

-- Inisialisasi flag lock sesuai pickMode awal
_ascPrefLocked = not (APM_UNLOCK[ASC.pickMode or "easy"] or {}).map
_ascRankLocked = not (APM_UNLOCK[ASC.pickMode or "easy"] or {}).rank
_ascRuneLocked = not (APM_UNLOCK[ASC.pickMode or "easy"] or {}).rune

-- Apply lock saat script load (defer agar semua elemen sudah terdaftar ke WindUI)
task.defer(function() _doApplyAscLock(ASC.pickMode or "easy") end)

AscRebuildListDisplay()

end -- end do: AUTO RAID ASCENSION UI



-- ============================================================================
-- AUTO SIEGE - v100 [PORT dari 1.lua ke WindUI]
-- Flow:
--   1. Toggle ON -> tunggu UpdateCityRaidInfo dari server (SIEGE.live diisi scanner)
--   2. Notif masuk -> TP player ke baseMapId (LocalTp)
--   3. Delay 2 detik
--   4. Fire entry remotes: EnterCityRaidMap -> StartLocalPlayerTeleport
--      -> LocalPlayerTeleportSuccess -> EquipHeroWithData
--   5. Delay 4 detik (render musuh)
--   6. Validasi: scan workspace cari Map201-Map205
--   7. Serang semua musuh, pantau Map201-Map205 masih ada. Jika hilang -> stop
--   8. QuitCityRaidMap -> cleanup -> count -> tunggu notif berikutnya
-- ============================================================================

-- DATA & CONSTANTS
local SIEGE_DATA = {
    [3]  = {name="Map 3  - Shadow Castle",       cityRaidId=1000001, tpMapId=50201, baseMapId=50003, mapFolder="Map201"},
    [7]  = {name="Map 7  - Demon Castle Tier 2",  cityRaidId=1000002, tpMapId=50202, baseMapId=50007, mapFolder="Map202"},
    [10] = {name="Map 10 - Plagueheart",          cityRaidId=1000003, tpMapId=50203, baseMapId=50010, mapFolder="Map203"},
    [13] = {name="Map 13 - Lava Hell",            cityRaidId=1000004, tpMapId=50204, baseMapId=50013, mapFolder="Map204"},
    [18] = {name="Map 18 - Golden Throne",        cityRaidId=1000005, tpMapId=50205, baseMapId=50018, mapFolder="Map205"},
}
local SIEGE_MAP_NUMS = {3, 7, 10, 13, 18}

-- Kill target semua map Siege (paten)
local SIEGE_KILL_TARGET  = 30
-- Radius serang dari posisi player (studs)
local SIEGE_ATTACK_RADIUS = 2000

-- STATE TABLE
if not SIEGE then
    SIEGE = {
        running      = false,
        thread       = nil,
        inMap        = false,
        teleporting  = false,
        excludeMaps  = {[3]=false,[7]=false,[10]=false,[13]=false,[18]=false},
        statusLbl    = nil,
        dot          = nil,
        countSummaryLbl = nil,
        count        = {[3]=0,[7]=0,[10]=0,[13]=0,[18]=0},
        killed       = 0,
        live         = {},
        _lastExitTime = 0,
    }
end

_siegeToggleState = _siegeToggleState or false
_siegeSessionStart = _siegeSessionStart or nil
local _siegeWakeup = nil

-- Forward declare UI helpers (diisi oleh panel)
_setSiegeToggle      = _setSiegeToggle      or nil
_updateSiegeDdLabel  = _updateSiegeDdLabel  or nil

-- Status helper
SiegeStatus = function(msg, color)
    if SIEGE.statusLbl then
        local ts = ""
        if _siegeSessionStart then
            local dur = os.time() - _siegeSessionStart
            ts = string.format("[%02d:%02d:%02d] ", math.floor(dur/3600), math.floor(dur/60)%60, dur%60)
        end
        SIEGE.statusLbl.Text = ts .. msg
        SIEGE.statusLbl.TextColor3 = color or Color3.fromRGB(160,148,135)
    end
    if SIEGE.dot then
        SIEGE.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100)
    end
end

SiegeCounterUpdate = function()
    if SIEGE.countSummaryLbl then
        local parts = {}
        for _, mn in ipairs(SIEGE_MAP_NUMS) do
            table.insert(parts, "M"..mn..":"..(SIEGE.count[mn] or 0))
        end
        SIEGE.countSummaryLbl.Text = table.concat(parts, "  ")
    end
end

-- Stop
StopSiege = function()
    SIEGE.running     = false
    SIEGE.inMap       = false
    SIEGE.teleporting = false
    SIEGE._lastExitTime = os.time()
    _siegeInterrupt   = false
    MODE:Release("siege")
    if MODE.current == "siege" then MODE.current = "idle" end
    if SIEGE.thread then
        pcall(function() task.cancel(SIEGE.thread) end)
        SIEGE.thread = nil
    end
    SiegeStatus("[FLa] Idle", Color3.fromRGB(100,100,100))
end

-- Helper: cek player masih di Siege map (workspace scan)
local function IsInSiegeMapNow()
    for _, obj in ipairs(workspace:GetChildren()) do
        local n = obj.Name
        if n == "Map201" or n == "Map202" or n == "Map203"
        or n == "Map204" or n == "Map205" then
            return true
        end
    end
    local mf = workspace:FindFirstChild("Maps")
    if mf then
        for i = 1, 5 do
            if mf:FindFirstChild("Map20"..i) then return true end
        end
    end
    local ok, wm = pcall(function()
        return workspace:GetAttribute("MapId")
            or workspace:GetAttribute("mapId")
            or workspace:GetAttribute("CurrentMapId")
    end)
    if ok and type(wm) == "number" and wm >= 50201 and wm <= 50205 then
        return true
    end
    return false
end

-- Helper: scan musuh Siege dalam radius SIEGE_ATTACK_RADIUS dari posisi player
local function GetSiegeEnemies(mapFolder)
    local list, seen = {}, {}
    local FOLDERS = {"Enemys","EnemyCityRaid","CityRaidEnemys","Enemies","Enemy"}

    -- Ambil posisi player untuk filter radius
    local _playerPos = nil
    local _lp = game:GetService("Players").LocalPlayer
    if _lp and _lp.Character then
        local _hrp = _lp.Character:FindFirstChild("HumanoidRootPart")
        if _hrp then _playerPos = _hrp.Position end
    end

    local function _add(e)
        if not e:IsA("Model") then return end
        if not e:IsDescendantOf(workspace) then return end
        local g   = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid")
                 or e:GetAttribute("Guid")       or e:GetAttribute("GUID")
        local h   = e:FindFirstChild("HumanoidRootPart")
        local hum = e:FindFirstChildOfClass("Humanoid")
        if not (g and h and hum) then return end
        if seen[g] then return end
        if hum.Health <= 0 then return end
        if hum.MaxHealth <= 0 then return end
        local p = h.Position
        if p.Magnitude <= 10 then return end
        if p.Y < -200 or p.Y > 1500 then return end
        if not h:IsDescendantOf(workspace) then return end
        -- Filter radius: skip enemy yang lebih jauh dari SIEGE_ATTACK_RADIUS
        if _playerPos and (p - _playerPos).Magnitude > SIEGE_ATTACK_RADIUS then return end
        seen[g] = true
        table.insert(list, {model=e, guid=g, hrp=h})
    end
    -- Prioritas 1: nested di map folder aktif (anti-kontaminasi enemy Raid/ASC)
    if mapFolder then
        local mf = workspace:FindFirstChild(mapFolder)
        if mf then
            for _, fname in ipairs(FOLDERS) do
                local f = mf:FindFirstChild(fname)
                if f then for _, e in ipairs(f:GetChildren()) do _add(e) end end
            end
        end
    end
    -- Prioritas 2: fallback top-level workspace
    if #list == 0 then
        for _, fname in ipairs(FOLDERS) do
            local f = workspace:FindFirstChild(fname)
            if f then for _, e in ipairs(f:GetChildren()) do _add(e) end end
        end
    end
    if #list == 0 then
        for _, obj in ipairs(workspace:GetChildren()) do _add(obj) end
    end
    return list
end

-- FireAllDamage & FireHeroRemotes lokal untuk Siege
local function _SiegeFireDamage(g, ep)
    if RE.Click then
        task.spawn(function()
            pcall(function() RE.Click:InvokeServer({enemyGuid=g}) end)
        end)
    end
    if RE.Atk then
        pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
    end
    if RE.HeroUseSkill then
        for _, hGuid in ipairs(HERO_GUIDS) do
            pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid, enemyGuid=g}) end)
        end
    elseif RE.HeroSkill then
        for _, hGuid in ipairs(HERO_GUIDS) do
            pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=1,masterId=MY_USER_ID}) end)
            pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=2,masterId=MY_USER_ID}) end)
            pcall(function() RE.HeroSkill:FireServer({heroGuid=hGuid,enemyGuid=g,skillType=3,masterId=MY_USER_ID}) end)
        end
    end
end

-- [EDIT] _SiegeFireHeroMoves — HeroMoveToEnemyPos dihapus, fungsi tidak melakukan apapun.
local function _SiegeFireHeroMoves(g, ep)
end

-- Core: SiegeAttackLoop
local function SiegeAttackLoop(onStatus, d)
    local MAX_TIME   = 120
    local totalTime  = 0
    local deadGuids  = {}
    local killCount  = 0

    local _deathConn = nil
    if RE.Death then
        _deathConn = RE.Death.OnClientEvent:Connect(function(dd)
            if not dd then return end
            local g = dd.enemyGuid or dd.guid
            if g and not deadGuids[g] then
                deadGuids[g] = true
                killCount = killCount + 1
                SIEGE.killed = SIEGE.killed + 1
            end
        end)
    end

    local function cleanup()
        if _deathConn then _deathConn:Disconnect(); _deathConn = nil end
    end

    while SIEGE.running and SIEGE.inMap do
        totalTime = totalTime + 0.08

        if totalTime >= MAX_TIME then
            if onStatus then onStatus("[!] Timeout - paksa keluar") end
            cleanup(); return "timeout"
        end

        if not IsInSiegeMapNow() then
            if onStatus then onStatus("[OK] Player keluar Siege map - stop serang") end
            cleanup(); return "exited"
        end

        -- Kill target tercapai (30 musuh) -> keluar map, anggap selesai
        if killCount >= SIEGE_KILL_TARGET then
            if onStatus then onStatus(string.format("[OK] %d kill tercapai - selesai!", killCount)) end
            cleanup(); return "success"
        end

        local enemies = GetSiegeEnemies(d and d.mapFolder)
        local targets = {}
        for _, e in ipairs(enemies) do
            if not deadGuids[e.guid] then
                table.insert(targets, e)
            end
        end

        if #targets == 0 then
            if onStatus then onStatus(string.format("[~] Tunggu musuh... kill: %d/%d", killCount, SIEGE_KILL_TARGET)) end
        else
            if onStatus then
                onStatus(string.format("[ATK] %d target | kill: %d/%d", #targets, killCount, SIEGE_KILL_TARGET))
            end
            for _, e in ipairs(targets) do
                if e.model and e.model.Parent then
                    local hrp = e.hrp
                    if hrp and hrp.Parent then
                        local g, pos = e.guid, hrp.Position
                        pcall(function() _SiegeFireDamage(g, pos) end)
                        if #HERO_GUIDS > 0 then
                            pcall(function() _SiegeFireHeroMoves(g, pos) end)
                        end
                    end
                end
            end
        end

        PG_Wait(0.08)
    end

    cleanup()
    return "loop_ended"
end

-- Main Loop
StartSiegeLoop = function()
    if SIEGE.running then StopSiege() end

    SIEGE.running      = true
    SIEGE.inMap        = false
    SIEGE.teleporting  = false
    SIEGE.killed       = 0
    _siegeSessionStart = os.time()
    for _, mn in ipairs(SIEGE_MAP_NUMS) do SIEGE.count[mn] = 0 end
    SiegeCounterUpdate()
    SiegeStatus("[.] Waiting notif SIEGE...", Color3.fromRGB(255,200,60))

    if _siegeWakeup then pcall(function() _siegeWakeup:Destroy() end) end
    _siegeWakeup = Instance.new("BindableEvent")
    pcall(function() _siegeWakeup:Fire() end)

    -- Helper: satu siklus penuh masuk-serang-keluar map untuk targetMap tertentu
    -- Mengembalikan true = berhasil selesai siklus, false = harus break loop utama
    local function _SiegeDoEntry(targetMap)
        -- [v60] Kesadaran diri: tunggu RAID/ASC keluar map dulu
        if (RAID and RAID.inMap) or (ASC and ASC.inMap) then
            local _waitWho = (RAID and RAID.inMap) and "RAID" or "ASC"
            SiegeStatus("[..] " .. _waitWho .. " masih di Map - SIEGE menunggu...", Color3.fromRGB(255,200,60))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
            local _wg = 0
            while ((RAID and RAID.inMap) or (ASC and ASC.inMap)) and SIEGE.running and _wg < 600 do
                task.wait(0.5); _wg = _wg + 0.5
            end
            if not SIEGE.running then return false end
        end

        -- SIEGE sudah tunggu RAID/ASC selesai di blok atas (baris 9101-9110)
        -- Tidak perlu tunggu lagi di sini, langsung set interrupt
        _siegeInterrupt = true  -- signal MA untuk pause (MA cek di guard tiap iterasi)
        if not MODE:WaitAndRequest("siege", 15) then
            _siegeInterrupt = false
            task.wait(1)
            return true -- retry loop utama
        end

        local d = SIEGE_DATA[targetMap]
        SIEGE.teleporting = true
        SIEGE.live[d.cityRaidId] = nil

        -- PRE-ENTRY: TP ke BaseMap
        -- [PATCH v2] Deteksi via workspace.Maps folder, bukan MapId attribute
        -- Jika player sudah berada di base map siege (Map3/Map7/Map10/Map13/Map18),
        -- skip TP ke basemap — double-TP ditolak server dan menyebabkan stuck nil.
        local _BASEMAP_FOLDERS = {[3]="Map3",[7]="Map7",[10]="Map10",[13]="Map13",[18]="Map18"}
        local _baseFolder = _BASEMAP_FOLDERS[targetMap]
        local _alreadyAtBase = false
        if _baseFolder then
            local _mapsRoot = workspace:FindFirstChild("Maps")
            if _mapsRoot and _mapsRoot:FindFirstChild(_baseFolder) then
                _alreadyAtBase = true
            end
        end

        if _alreadyAtBase then
            -- Player sudah di basemap: bypass TP, langsung delay 2s lalu lanjut entry
            SiegeStatus("[>>] Sudah di "..(_baseFolder or "basemap").." - bypass TP, delay 2s...", Color3.fromRGB(120,180,255))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(120,180,255) end
            task.wait(2)
        else
            -- Normal: TP ke basemap dulu
            SiegeStatus("[>>] LocalTp ke BaseMap "..d.baseMapId.."...", Color3.fromRGB(120,180,255))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(120,180,255) end
            pcall(function()
                if RE.LocalTp then RE.LocalTp:FireServer({ mapId = d.baseMapId }) end
            end)
            if #HERO_GUIDS > 0 and RE.EquipHeroWithData then
                for _, hGuid in ipairs(HERO_GUIDS) do
                    pcall(function()
                        RE.EquipHeroWithData:FireServer({ heroGuid = hGuid, userId = MY_USER_ID })
                    end)
                    PG_Wait(0.05)
                end
            end
            SiegeStatus("[2s] Delay post-TP BaseMap...", Color3.fromRGB(120,180,255))
            task.wait(2)
        end

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        local _RE = Remotes

        -- EnterCityRaidMap
        SiegeStatus("[>>] Fire EnterCityRaidMap("..d.cityRaidId..")...", Color3.fromRGB(180,120,255))
        if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(180,120,255) end
        pcall(function()
            local re = _RE:FindFirstChild("EnterCityRaidMap")
            if re then re:FireServer(d.cityRaidId) end
        end)
        PG_Wait(0.8)

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        -- StartLocalPlayerTeleport
        SiegeStatus("[>>] Fire StartLocalPlayerTeleport(mapId="..d.tpMapId..")...", Color3.fromRGB(180,120,255))
        pcall(function()
            local re = _RE:FindFirstChild("StartLocalPlayerTeleport")
            if re then re:FireServer({mapId = d.tpMapId}) end
        end)
        PG_Wait(0.8)

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        -- LocalPlayerTeleportSuccess
        SiegeStatus("[>>] InvokeServer LocalPlayerTeleportSuccess...", Color3.fromRGB(180,120,255))
        pcall(function()
            local re = _RE:FindFirstChild("LocalPlayerTeleportSuccess")
            if re then re:InvokeServer() end
        end)
        PG_Wait(0.5)

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        -- Poll workspace.Maps.[mapFolder] max 15s
        SiegeStatus("[..] Poll "..d.mapFolder.." (max 15s)...", Color3.fromRGB(255,200,60))
        local mapAppeared = false
        local mapWait = 0
        while mapWait < 15 and SIEGE.running do
            if workspace:FindFirstChild(d.mapFolder) then
                mapAppeared = true; break
            end
            local mapsFolder = workspace:FindFirstChild("Maps")
            if mapsFolder and mapsFolder:FindFirstChild(d.mapFolder) then
                mapAppeared = true; break
            end
            task.wait(0.5); mapWait = mapWait + 0.5
        end

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        if not mapAppeared then
            SiegeStatus("[!] "..d.mapFolder.." tidak muncul - retry...", Color3.fromRGB(255,100,60))
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege")
            task.wait(2)
            return true -- retry
        end

        SiegeStatus("[OK] "..d.mapFolder.." muncul! (+"..string.format("%.1f", mapWait).."s)", Color3.fromRGB(80,220,80))

        -- EquipHeroWithData setelah map muncul
        SiegeStatus("[>>] Fire EquipHeroWithData...", Color3.fromRGB(180,120,255))
        pcall(function()
            local re = _RE:FindFirstChild("EquipHeroWithData")
            if re then re:FireServer() end
        end)
        PG_Wait(0.5)

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        -- Delay render musuh
        SiegeStatus("[4s] Delay render musuh...", Color3.fromRGB(255,200,60))
        task.wait(4)

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        SIEGE.teleporting = false
        SIEGE.inMap = true
        SiegeStatus("[S] "..d.name.." - ATTACK!", Color3.fromRGB(80,220,80))
        if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(80,220,80) end

        local result = SiegeAttackLoop(function(msg)
            SiegeStatus("[S] "..msg, Color3.fromRGB(80,220,80))
        end, d)

        -- Exit phase
        if result == "timeout" then
            SiegeStatus("[!] Timeout 2m - Force TP basemap...", Color3.fromRGB(255,100,60))
            pcall(function()
                local reQuit = Remotes:FindFirstChild("QuitCityRaidMap")
                if reQuit then reQuit:FireServer(d.cityRaidId) end
            end)
            pcall(function()
                if RE.LocalTp then RE.LocalTp:FireServer({ mapId = d.baseMapId }) end
            end)
            task.wait(3)
        else
            SiegeStatus("[<<] QuitCityRaidMap("..d.cityRaidId..")...", Color3.fromRGB(100,200,255))
            pcall(function()
                local re = Remotes:FindFirstChild("QuitCityRaidMap")
                if re then re:FireServer(d.cityRaidId) end
            end)
            local _exitWait = 0
            while IsInSiegeMapNow() and _exitWait < 8 and SIEGE.running do
                task.wait(0.3); _exitWait = _exitWait + 0.3
            end
        end

        SIEGE.inMap       = false
        SIEGE.teleporting = false
        SIEGE._lastExitTime = os.time()
        _siegeInterrupt   = false
        pcall(function() if MODE.current == "siege" then MODE:Release("siege") end end)

        if not SIEGE.running then return false end

        SIEGE.live[d.cityRaidId] = nil
        if _siegeChatOpen then _siegeChatOpen[targetMap] = false end
        SIEGE.count[targetMap] = (SIEGE.count[targetMap] or 0) + 1
        SiegeCounterUpdate()

        if result == "success" or result == "exited" then
            SiegeStatus("[OK] "..d.name.." SUCCESS! Waiting notif berikutnya...", Color3.fromRGB(100,255,150))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
        else
            SiegeStatus("[~] "..d.name.." ("..result..") - Waiting notif berikutnya...", Color3.fromRGB(255,200,60))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
        end
        task.wait(1)
        return true
    end

    SIEGE.thread = task.spawn(function()
        while SIEGE.running do

            -- Cari map siege tersedia, urut mapNum terkecil dulu
            local targetMap = nil
            for _, mn in ipairs(SIEGE_MAP_NUMS) do
                if not (SIEGE.excludeMaps and SIEGE.excludeMaps[mn]) then
                    local cid = SIEGE_DATA[mn].cityRaidId
                    if SIEGE.live[cid] then targetMap = mn; break end
                end
            end

            -- Kalau tidak ada, tunggu wakeup dari scanner (max 90 detik per cycle)
            if not targetMap then
                local exNames = {}
                for _, mn in ipairs(SIEGE_MAP_NUMS) do
                    if SIEGE.excludeMaps and SIEGE.excludeMaps[mn] then
                        table.insert(exNames, "M"..mn)
                    end
                end
                local exStr = #exNames > 0 and (" | Skip: "..table.concat(exNames,",")) or ""
                SiegeStatus("[.] Waiting OpenCityRaid..."..exStr, Color3.fromRGB(255,200,60))
                if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end

                local _waitConn = _siegeWakeup.Event:Connect(function() end)
                local guard = 0
                while SIEGE.running and guard < 90 do
                    for _, mn in ipairs(SIEGE_MAP_NUMS) do
                        if not (SIEGE.excludeMaps and SIEGE.excludeMaps[mn]) then
                            if SIEGE.live[SIEGE_DATA[mn].cityRaidId] then
                                targetMap = mn; break
                            end
                        end
                    end
                    if targetMap then break end
                    task.wait(0.5); guard = guard + 0.5
                end
                pcall(function() _waitConn:Disconnect() end)
                if not SIEGE.running then break end
            end

            if targetMap then
                local ok = _SiegeDoEntry(targetMap)
                if not ok then break end
            end

        end -- while SIEGE.running

        -- Cleanup akhir saat toggle OFF
        _siegeInterrupt   = false
        SIEGE.inMap       = false
        SIEGE.teleporting = false
        MODE:Release("siege")
        if MODE.current == "siege" then MODE.current = "idle" end
        SIEGE.running = false
        SiegeStatus("[.] Idle", Color3.fromRGB(100,100,100))
        if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
    end)
end


-- ============================================================================
-- PANEL: AUTO SIEGE (WindUI Section - di bawah Auto Raid Ascension)
-- ============================================================================
do

local siegeSection = AutomationTab:Section({ Title = "Auto Siege", Icon = "shield", Opened = false, Box = true })

-- Status
local siegeStatusPara = siegeSection:Paragraph({
    Title = "Status",
    Desc  = "Idle - SELECT MAP",
})
SIEGE.statusLbl = {
    Text = "Idle - SELECT MAP",
    TextColor3 = Color3.fromRGB(160,148,135),
}
local _origSiegeStatus = SiegeStatus
SiegeStatus = function(msg, color)
    pcall(function() siegeStatusPara:SetDesc(msg) end)
    SIEGE.statusLbl.Text = msg
    SIEGE.statusLbl.TextColor3 = color or Color3.fromRGB(160,148,135)
end

-- Counter ringkas
local siegeCountPara = siegeSection:Paragraph({
    Title = "Count",
    Desc  = "M3:0  M7:0  M10:0  M13:0  M18:0",
})
SIEGE.countSummaryLbl = {
    Text = "M3:0  M7:0  M10:0  M13:0  M18:0",
}
local _origSiegeCounterUpdate = SiegeCounterUpdate
SiegeCounterUpdate = function()
    local parts = {}
    for _, mn in ipairs(SIEGE_MAP_NUMS) do
        table.insert(parts, "M"..mn..":"..(SIEGE.count[mn] or 0))
    end
    local txt = table.concat(parts, "  ")
    SIEGE.countSummaryLbl.Text = txt
    pcall(function() siegeCountPara:SetDesc(txt) end)
end

-- Toggle utama
local siegeEnableToggle = siegeSection:Toggle({
    Flag     = "siegeEnable",
    Title    = "Enable Auto Siege",
    Desc     = "ON = Menunggu notif EnterCityRaid dari server",
    Default  = false,
    Callback = function(on)
        _siegeToggleState = on
        if on then StartSiegeLoop() else StopSiege() end
    end,
})
_setSiegeToggle = function(on)
    if on == _siegeToggleState then return end
    _siegeToggleState = on
    pcall(function() siegeEnableToggle:Set(on, false) end)
    if on then StartSiegeLoop() else StopSiege() end
end
-- Visual-only setter (tidak trigger logika, hanya sync UI)
_visSiege = function(on)
    pcall(function() siegeEnableToggle:Set(on, false) end)
end

-- Exclude Map Dropdown (multi-select style via Dropdown)
local MAP_NAMES_SIEGE = {
    [3]  = "Map 3  - Shadow Castle",
    [7]  = "Map 7  - Demon Castle Tier 2",
    [10] = "Map 10 - Plagueheart",
    [13] = "Map 13 - Lava Hell",
    [18] = "Map 18 - Golden Throne",
}
local MAP_LABEL_TO_NUM = {}
local DD_OPTIONS = {}
for _, mn in ipairs(SIEGE_MAP_NUMS) do
    local lbl = MAP_NAMES_SIEGE[mn]
    table.insert(DD_OPTIONS, lbl)
    MAP_LABEL_TO_NUM[lbl] = mn
end

local siegeExcludeDD = siegeSection:Dropdown({
    Flag     = "siegeExclude",
    Title    = "Exclude Map (Skip Siege)",
    Desc     = "Pilih map yang ingin di-SKIP (tidak dimasuki)",
    Values   = DD_OPTIONS,
    Multi    = true,
    Default  = {},
    Callback = function(selected)
        -- Reset semua ke false dulu
        for _, mn in ipairs(SIEGE_MAP_NUMS) do
            SIEGE.excludeMaps[mn] = false
        end
        -- Set yang dipilih jadi true (skip)
        if type(selected) == "table" then
            for lbl, active in pairs(selected) do
                if active then
                    local mn = MAP_LABEL_TO_NUM[lbl]
                    if mn then SIEGE.excludeMaps[mn] = true end
                end
            end
        end
    end,
})

-- Expose setter visual-only untuk restore dropdown exclude map Siege saat Load Config
-- ApplyConfig restore SIEGE.excludeMaps datanya, lalu panggil ini untuk sync tampilan DD
_visSiegeExcludeDD = function()
    if not siegeExcludeDD then return end
    pcall(function()
        -- Bangun tabel selected: { [label] = true } untuk setiap map yang di-exclude
        local sel = {}
        for _, mn in ipairs(SIEGE_MAP_NUMS) do
            if SIEGE.excludeMaps and SIEGE.excludeMaps[mn] then
                local lbl = MAP_NAMES_SIEGE[mn]
                if lbl then sel[lbl] = true end
            end
        end
        siegeExcludeDD:Set(sel)
    end)
end

end -- end do: AUTO SIEGE UI


-- ============================================================================
-- SIEGE SCANNER v102 - Hook UpdateCityRaidInfo
-- action=StartChallenge/OpenCityRaid -> SIEGE.live -> wakeup loop
-- action=CloseCityRaid/LeaveCityRaid -> hapus dari SIEGE.live
-- ============================================================================
task.spawn(function()
    task.wait(3)
    if not SIEGE then return end
    if not SIEGE.live then SIEGE.live = {} end

    local _cidToMap = {
        [1000001] = 3,
        [1000002] = 7,
        [1000003] = 10,
        [1000004] = 13,
        [1000005] = 18,
    }

    local _reCity = Remotes:FindFirstChild("UpdateCityRaidInfo")
    if not _reCity then
        task.wait(5)
        _reCity = Remotes:FindFirstChild("UpdateCityRaidInfo")
    end

    if _reCity then
        _reCity.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local id     = data.id
            local action = data.action
            local mn     = _cidToMap[id]
            if not id or not action or not mn then return end

            if action == "StartChallenge" or action == "OpenCityRaid" then
                if not SIEGE.live[id] then
                    SIEGE.live[id] = mn
                    if _siegeWakeup then
                        pcall(function() _siegeWakeup:Fire() end)
                    end
                end
            elseif action == "CloseCityRaid" or action == "LeaveCityRaid" then
                SIEGE.live[id] = nil
                if _siegeChatOpen then _siegeChatOpen[mn] = false end
            end
        end)
    end
end)



-- ============================================================================
-- JOIN TO RAID PLAYER (JTR)
-- SCAN  = ambil semua player di server (Players:GetPlayers())
-- JOIN  = StartLocalPlayerTeleport {hostId, mapId}
--         + EquipHeroWithData + LocalPlayerTeleportSuccess
-- Port dari 1.lua baris 17800-18157 ke WindUI AutomationTab
-- ============================================================================
do

local jtrSection = AutomationTab:Section({ Title = "Join To Raid Player", Icon = "users", Opened = false, Box = true })

-- State
local JTR_players = {}     -- { {name, userId} }
local JTR_selIdx  = nil
local JTR_joining = false
local JTR_mapId   = 50101  -- default: Normal Map 1
local JTR_isAsc   = false
local JTR_mapNum  = 1

local MAP_NORMAL_BASE = 50101
local MAP_NORMAL_MAX  = 20
local MAP_ASC_BASE    = 50302
local MAP_ASC_MAX     = 18

-- Status Paragraph
local jtrStatusPara = jtrSection:Paragraph({
    Title = "Status",
    Desc  = "Tekan SCAN untuk muat daftar player.",
})

local function JTRStat(msg)
    pcall(function() jtrStatusPara:SetDesc(msg) end)
end

-- Info Paragraph
jtrSection:Paragraph({
    Title = "Cara Pakai",
    Desc  = "SCAN -> Pilih Player -> Pilih Map -> JOIN.\nSetelah keluar dari Raid, tekan SCAN ulang.",
})

-- Player List Paragraph (hasil SCAN)
local jtrListPara = jtrSection:Paragraph({
    Title = "Daftar Player",
    Desc  = "(belum di-scan)",
})

local function RenderPlayerList()
    if #JTR_players == 0 then
        pcall(function() jtrListPara:SetDesc("(tidak ada player lain di server ini)") end)
        return
    end
    local lines = {}
    for i, entry in ipairs(JTR_players) do
        local marker = (i == JTR_selIdx) and "[v] " or "[ ] "
        table.insert(lines, marker .. i .. ". " .. entry.name .. "  (UID:" .. tostring(entry.userId) .. ")")
    end
    pcall(function() jtrListPara:SetDesc(table.concat(lines, "\n")) end)
end

-- Tombol SCAN
local _jtrBusy = false

jtrSection:Button({
    Title    = "SCAN Player",
    Desc     = "Ambil daftar semua player di server ini",
    Callback = function()
        if _jtrBusy then JTRStat("[~] Sedang scanning..."); return end
        _jtrBusy = true
        JTRStat("[~] Mengambil daftar player di server...")
        JTR_selIdx = nil

        task.spawn(function()
            local found = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP then
                    table.insert(found, {name = plr.Name, userId = plr.UserId})
                end
            end
            JTR_players = found
            _jtrBusy = false

            if #found == 0 then
                JTRStat("[!] Tidak ada player lain di server ini.")
                pcall(function() jtrListPara:SetDesc("(tidak ada player lain)") end)
            else
                JTRStat("[OK] " .. #found .. " player ditemukan. Pilih nomor -> JOIN.")
                RenderPlayerList()
            end
        end)
    end,
})

-- Input: Pilih nomor player dari daftar
jtrSection:Input({
    Title       = "Pilih Player (Nomor)",
    Desc        = "Ketik nomor urut player dari daftar SCAN di atas",
    Placeholder = "Contoh: 1",
    Value       = "",
    Callback    = function(val)
        local n = tonumber(val)
        if n and n >= 1 and n <= #JTR_players then
            JTR_selIdx = math.floor(n)
            local entry = JTR_players[JTR_selIdx]
            JTRStat("[v] Dipilih: " .. entry.name .. "  (hostId=" .. entry.userId .. ")")
            RenderPlayerList()
        else
            JTR_selIdx = nil
            if #JTR_players > 0 then
                JTRStat("[!] Nomor tidak valid. Masukkan angka 1-" .. #JTR_players)
            else
                JTRStat("[!] Scan dulu sebelum memilih player.")
            end
        end
    end,
})

-- Map Target Paragraph (info mapId aktif)
local jtrMapTypePara = jtrSection:Paragraph({
    Title = "Map Target",
    Desc  = "Mode: Normal Raid | Map 1  (mapId=50101)",
})

local function UpdateJTRMapDisplay()
    if JTR_isAsc then
        JTR_mapId = MAP_ASC_BASE
        pcall(function() jtrMapTypePara:SetDesc(
            "Mode: Ascension | Tower " .. JTR_mapNum .. "  (mapId=" .. JTR_mapId .. ")"
        ) end)
    else
        JTR_mapId = MAP_NORMAL_BASE + (JTR_mapNum - 1)
        pcall(function() jtrMapTypePara:SetDesc(
            "Mode: Normal Raid | Map " .. JTR_mapNum .. "  (mapId=" .. JTR_mapId .. ")"
        ) end)
    end
end

-- Toggle: Normal / Ascension
jtrSection:Toggle({
    Title    = "Mode Ascension",
    Desc     = "OFF = Normal Raid |  ON = Ascension",
    Default  = false,
    Callback = function(on)
        JTR_isAsc = on
        local maxMap = on and MAP_ASC_MAX or MAP_NORMAL_MAX
        if JTR_mapNum > maxMap then JTR_mapNum = maxMap end
        UpdateJTRMapDisplay()
    end,
})

-- Input: Nomor Map atau Tower
jtrSection:Input({
    Title       = "Nomor Map / Tower",
    Desc        = "Normal: 1-20  |  Ascension: 1-18",
    Placeholder = "Contoh: 1",
    Value       = "1",
    Callback    = function(val)
        local n = tonumber(val)
        if not n then return end
        n = math.floor(n)
        local maxMap = JTR_isAsc and MAP_ASC_MAX or MAP_NORMAL_MAX
        if n < 1 then n = 1 end
        if n > maxMap then n = maxMap end
        JTR_mapNum = n
        UpdateJTRMapDisplay()
    end,
})

UpdateJTRMapDisplay()

-- Tombol JOIN
jtrSection:Button({
    Title    = "JOIN to Raid Player",
    Desc     = "Teleport masuk ke Raid player yang dipilih",
    Callback = function()
        if JTR_joining then JTRStat("[~] Sedang proses JOIN..."); return end
        if not JTR_selIdx then
            JTRStat("[!] Belum ada player yang dipilih! SCAN lalu ketik nomor.")
            return
        end
        local entry = JTR_players[JTR_selIdx]
        if not entry then
            JTRStat("[!] Data tidak valid, coba SCAN ulang.")
            return
        end

        JTR_joining = true
        local mapId   = JTR_mapId
        local mapType = JTR_isAsc and "ASC" or "NORMAL"
        JTRStat("[JOIN] -> " .. entry.name .. " | hostId=" .. entry.userId .. " | mapId=" .. mapId .. " (" .. mapType .. ")")

        task.spawn(function()
            local ok, err = pcall(function()
                local reStartTp = Remotes:FindFirstChild("StartLocalPlayerTeleport")
                local reEquip   = Remotes:FindFirstChild("EquipHeroWithData")
                local reTpSucc  = Remotes:FindFirstChild("LocalPlayerTeleportSuccess")

                if not reStartTp then error("Remote StartLocalPlayerTeleport tidak ditemukan!") end

                -- Step 1: StartLocalPlayerTeleport {hostId, mapId}
                JTRStat("[1/3] Teleport ke raid " .. entry.name .. "...")
                reStartTp:FireServer({hostId = entry.userId, mapId = mapId})
                task.wait(0.5)

                -- Step 2: EquipHeroWithData
                if reEquip then pcall(function() reEquip:FireServer() end) end
                task.wait(0.3)

                -- Step 3: LocalPlayerTeleportSuccess
                if reTpSucc then
                    pcall(function() reTpSucc:InvokeServer() end)
                end
            end)

            JTR_joining = false

            if ok then
                JTRStat("[OK] Berhasil join " .. entry.name .. "! (mapId=" .. mapId .. ")")
            else
                JTRStat("[ERR] " .. (tostring(err):sub(1, 80)))
            end
        end)
    end,
})

-- Tombol BACK TO MAP 2
-- Remote: StartLocalPlayerTeleport:FireServer({mapId=50002})
-- Identik dengan 1.lua baris 17691-17726 (JTP panel)
local _jtrBackBusy = false
jtrSection:Button({
    Title    = "BACK TO MAP 2  (Lobby)",
    Desc     = "Teleport keluar ke Map 2 Lobby",
    Callback = function()
        if _jtrBackBusy then JTRStat("[~] Sedang teleport ke Map 2..."); return end
        _jtrBackBusy = true
        JTRStat("[~] Kembali ke Map Lobby 2...")

        task.spawn(function()
            local ok, err = pcall(function()
                local reStartTp = Remotes:FindFirstChild("StartLocalPlayerTeleport")
                if not reStartTp then error("Remote StartLocalPlayerTeleport tidak ditemukan!") end
                reStartTp:FireServer({mapId = 50002})
            end)

            _jtrBackBusy = false

            if ok then
                JTRStat("[OK] Berhasil teleport ke Map Lobby 2.")
            else
                JTRStat("[ERR] Gagal: " .. (tostring(err):sub(1, 80)))
            end
        end)
    end,
})

end -- do JTR






-- ============================================================
-- ANNIVERSARY CELEBRATION
-- Port dari 1.lua baris 18457-19090
-- Ditaruh DI BAWAH Join To Raid Player (AutomationTab:Section sendiri)
-- ============================================================

-- State
local ANNIV = {
    running     = false,
    thread      = nil,
    spinEnabled = false,
    spinThread  = nil,
}

local annivStatusPara   -- Paragraph WindUI untuk status bar
local _setAnnivRunFn    -- setter toggle Run (disimpan untuk auto-off saat gagal)
local _setAnnivSpinFn   -- setter toggle Spin Gems

-- Helper update status (tulis ke Paragraph WindUI + cetak ke output)
local function AnnivStatus(msg, _color)
    pcall(function()
        if annivStatusPara then annivStatusPara:SetDesc(msg) end
    end)
end

do
    local annivSection = AutomationTab:Section({
        Title  = "Anniversary Celebration",
        Icon   = "star",
        Opened = false,
        Box    = true,
    })

    -- ── Status bar ───────────────────────────────────────────────────
    annivStatusPara = annivSection:Paragraph({
        Title = "Status",
        Desc  = "Idle - Enable Run untuk START",
    })

    -- ── Toggle: Run ───────────────────────────────────────────────────
    annivSection:Toggle({
        Flag    = "annivRun",
        Title   = "Run",
        Desc    = "Jalankan loop Anniversary Celebration otomatis",
        Default = false,
        Callback = function(on)
            _setAnnivRunFn = function(v)
                -- WindUI tidak ekspos setter langsung; fallback via flag saja
                ANNIV.running = v
            end

            ANNIV.running = on
            if on then
                AnnivStatus("[..] Starting Anniversary Celebration...", nil)
                ANNIV.thread = task.spawn(function()
                    local RS      = game:GetService("ReplicatedStorage")
                    local Remotes = RS:WaitForChild("Remotes", 10)
                    if not Remotes then
                        AnnivStatus("[X] Remotes tidak ditemukan!", nil)
                        ANNIV.running = false
                        return
                    end

                    local RAID_ID  = 937101
                    local MAP_ID   = 50401
                    local LOBBY_ID = 50001
                    local hostId   = LP.UserId

                    -- Helper: apakah Player sudah ada di Anniversary map
                    -- Deteksi via workspace.Maps:FindFirstChild("MapAnniversary")
                    local function IsInAnnivMap()
                        local mf = workspace:FindFirstChild("Maps")
                        return mf and mf:FindFirstChild("MapAnniversary") ~= nil
                    end

                    -- Helper: apakah Player masih di lobby
                    local function IsInLobby()
                        local mf = workspace:FindFirstChild("Maps")
                        if not mf then return true end
                        return mf:FindFirstChild("MapAnniversary") == nil
                    end

                    -- Helper: get musuh anniversary (scan workspace langsung, bypass MapId guard)
                    -- IsDead inline supaya tidak bergantung pada lokal MA block
                    local function GetAnnivEnemies()
                        local list  = {}
                        local seen  = {}
                        local ENEMY_FOLDERS = { "Enemys", "EnemyCityRaid", "CityRaidEnemys", "Enemies", "Enemy" }
                        local function _add(e)
                            if not e:IsA("Model") then return end
                            local g   = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid") or e:GetAttribute("Guid") or e:GetAttribute("GUID")
                            local h   = e:FindFirstChild("HumanoidRootPart")
                            local hum = e:FindFirstChildOfClass("Humanoid")
                            if g and h and hum and hum.Health > 0 and not seen[g] then
                                seen[g] = true
                                list[#list + 1] = { guid = g, hrp = h, model = e }
                            end
                        end
                        for _, folderName in ipairs(ENEMY_FOLDERS) do
                            local f = workspace:FindFirstChild(folderName)
                            if f then for _, e in ipairs(f:GetChildren()) do _add(e) end end
                        end
                        -- fallback: scan workspace root
                        if #list == 0 then
                            for _, obj in ipairs(workspace:GetChildren()) do _add(obj) end
                        end
                        -- Filter: hanya yang hidup
                        local alive = {}
                        for i = 1, #list do
                            local e   = list[i]
                            local hum = e.model:FindFirstChildOfClass("Humanoid")
                            if e.model.Parent and hum and hum.Health > 0 then
                                alive[#alive + 1] = e
                            end
                        end
                        return alive
                    end

                    -- Helper: TP Player ke RaidsEnemys["4035"]
                    local function TpToAnnivEnemy()
                        local char = LP.Character
                        if not char then return false end
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if not hrp then return false end
                        local mf = workspace:FindFirstChild("Maps")
                        if not mf then return false end
                        local mapAnniv = mf:FindFirstChild("MapAnniversary")
                        if not mapAnniv then return false end
                        local mapFolder = mapAnniv:FindFirstChild("Map")
                        if not mapFolder then return false end
                        local raidEnemyFolder = mapFolder:FindFirstChild("RaidsEnemys")
                        if not raidEnemyFolder then return false end
                        local rootPart = raidEnemyFolder:FindFirstChild("4035")
                        if not rootPart then return false end
                        hrp.CFrame = rootPart.CFrame + Vector3.new(0, 3, 0)
                        return true
                    end

                    -- Helper: exit ke lobby
                    local function ExitToLobby()
                        local quitRe = Remotes:FindFirstChild("QuitRaidsMap")
                        -- Tembak QuitRaidsMap sekali, tunggu server proses
                        if quitRe then
                            pcall(function() quitRe:FireServer({ currentSlotIndex = 2, toMapId = LOBBY_ID }) end)
                        end
                        task.wait(1.5) -- [PingGuard] beri waktu server proses quit
                        -- Cek apakah sudah di lobby; kalau belum, baru retry (maks 3x, jeda 2s)
                        local exitTry = 0
                        while not IsInLobby() and exitTry < 3 and ANNIV.running do
                            exitTry = exitTry + 1
                            AnnivStatus("[EXIT] Belum di lobby, retry " .. exitTry .. "/3...", nil)
                            if quitRe then
                                pcall(function() quitRe:FireServer({ currentSlotIndex = 2, toMapId = LOBBY_ID }) end)
                            end
                            task.wait(2) -- tunggu lebih lama antar retry
                        end
                    end

                    -- MAIN LOOP
                    local failCount = 0
                    local FAIL_LIMIT = 3

                    while ANNIV.running do

                        -- ── PHASE 1: ENTRY SEQUENCE (SimpleSpy) ─────────────────
                        -- Urutan sesuai capture SimpleSpy:
                        -- 1. CreateRaidTeam(937101)
                        -- 2. StartChallengeRaidMap:FireServer()
                        -- 3. LeaveRaidTeam:FireServer(hostId)
                        -- 4. StartLocalPlayerTeleport:FireServer({hostId,slotIndex=3,mapId=50401,raidId=937101})
                        -- 5. LocalPlayerTeleportSuccess:InvokeServer({slotIndex=3,mapId=50401})
                        -- 6. EquipHeroWithData:FireServer()

                        -- Step 1: CreateRaidTeam
                        AnnivStatus("[1/6] Creating raid team...", nil)
                        local ok1, err1 = pcall(function()
                            Remotes.CreateRaidTeam:InvokeServer(RAID_ID)
                        end)
                        if not ok1 or not ANNIV.running then
                            AnnivStatus("[X] Step 1 gagal: " .. (err1 or "?"), nil)
                            ANNIV.running = false
                            break
                        end
                        PG_Wait(0.5) -- [PingGuard] ANNIV step 1

                        -- Step 2: StartChallengeRaidMap
                        AnnivStatus("[2/6] Starting challenge raid map...", nil)
                        local ok2, err2 = pcall(function()
                            Remotes.StartChallengeRaidMap:FireServer()
                        end)
                        if not ok2 or not ANNIV.running then
                            AnnivStatus("[X] Step 2 gagal: " .. (err2 or "?"), nil)
                            ANNIV.running = false
                            break
                        end
                        PG_Wait(0.5) -- [PingGuard] ANNIV step 2

                        -- Step 3: LeaveRaidTeam (hostId player sendiri)
                        AnnivStatus("[3/6] Leaving raid team slot...", nil)
                        pcall(function()
                            Remotes.LeaveRaidTeam:FireServer(hostId)
                        end)
                        PG_Wait(0.5) -- [PingGuard] ANNIV step 3

                        -- Step 4: StartLocalPlayerTeleport (slotIndex=3)
                        AnnivStatus("[4/6] Teleporting to anniversary map...", nil)
                        local ok4, err4 = pcall(function()
                            Remotes.StartLocalPlayerTeleport:FireServer({
                                hostId    = hostId,
                                slotIndex = 3,
                                mapId     = MAP_ID,
                                raidId    = RAID_ID,
                            })
                        end)
                        if not ok4 or not ANNIV.running then
                            AnnivStatus("[X] Step 4 teleport gagal: " .. (err4 or "?"), nil)
                            ANNIV.running = false
                            break
                        end
                        PG_Wait(1) -- [PingGuard] ANNIV step 4 (TP butuh waktu lebih)

                        -- Step 5: LocalPlayerTeleportSuccess (kirim args slotIndex+mapId)
                        AnnivStatus("[5/6] Confirming teleport success...", nil)
                        local ok5, err5 = pcall(function()
                            Remotes.LocalPlayerTeleportSuccess:InvokeServer({
                                slotIndex = 3,
                                mapId     = MAP_ID,
                            })
                        end)
                        if not ok5 or not ANNIV.running then
                            AnnivStatus("[X] Step 5 TeleportSuccess gagal: " .. (err5 or "?"), nil)
                            ANNIV.running = false
                            break
                        end
                        PG_Wait(0.5) -- [PingGuard] ANNIV step 5

                        -- Step 6: EquipHeroWithData
                        AnnivStatus("[6/6] Equipping hero...", nil)
                        pcall(function() Remotes.EquipHeroWithData:FireServer() end)
                        PG_Wait(0.5) -- [PingGuard] ANNIV step 6

                        -- ── VALIDASI MASUK: cek workspace.Maps ───────────────────
                        -- Tunggu server proses TP (maks 4 detik)
                        AnnivStatus("[..] Validasi masuk map...", nil)
                        local checkT = 0
                        while checkT < 4 and not IsInAnnivMap() do
                            PG_Wait(0.5) -- [PingGuard] ANNIV masuk map validate
                            checkT = checkT + 0.5
                        end

                        if not IsInAnnivMap() then
                            -- Player masih di lobby setelah entry sequence
                            -- Kemungkinan tiket habis atau server tolak
                            failCount = failCount + 1
                            AnnivStatus(
                                "[!] Gagal masuk (" .. failCount .. "/" .. FAIL_LIMIT .. ") - mungkin tiket habis...",
                                nil
                            )
                            if failCount >= FAIL_LIMIT then
                                AnnivStatus("[X] Tiket habis / gagal masuk " .. FAIL_LIMIT .. "x! AUTO OFF.", nil)
                                ANNIV.running = false
                                break
                            end
                            -- Cooldown sebelum retry
                            task.wait(2)
                            -- Kembali ke atas while loop (coba entry lagi)
                        else
                            -- Berhasil masuk - reset fail counter
                            failCount = 0
                            AnnivStatus("[OK] Berhasil masuk Anniversary Map! Jeda 2s...", nil)
                            task.wait(2)

                            -- ── PHASE 2: TP KE MUSUH ─────────────────────────────
                            AnnivStatus("[TP] Teleport ke RaidsEnemys.4035...", nil)
                            local tpOk = false
                            for i = 1, 5 do
                                if TpToAnnivEnemy() then tpOk = true; break end
                                AnnivStatus("[TP] Tunggu RaidsEnemys.4035... (" .. i .. "/5)", nil)
                                task.wait(1)
                            end

                            if not tpOk or not ANNIV.running then
                                AnnivStatus("[X] RaidsEnemys.4035 tidak ditemukan, exit...", nil)
                                ExitToLobby()
                                task.wait(2)
                            else
                                -- ── PHASE 3: UNEQUIP + EQUIP BEST ────────────────
                                AnnivStatus("[EQUIP] UnequipAll & AutoEquipBest...", nil)
                                pcall(function() Remotes.UnequipAllHero:FireServer() end)
                                task.wait(0.4)
                                pcall(function() Remotes.AutoEquipBestHero:FireServer() end)
                                task.wait(0.6)

                                -- ── PHASE 4: ATTACK LOOP ──────────────────────────
                                -- Target: semua musuh dalam radius 50 studs dari posisi Player
                                -- setelah teleport ke RaidsEnemys.4035
                                -- Selesai jika semua musuh dalam radius sudah mati / hilang
                                AnnivStatus("[ATK] Menyerang musuh...", nil)

                                -- Tunggu musuh spawn (maks 8 detik)
                                local spawnWait = 0
                                while spawnWait < 8 and #GetAnnivEnemies() == 0 and ANNIV.running do
                                    AnnivStatus("[ATK] Tunggu musuh spawn... (" .. math.floor(8 - spawnWait) .. "s)", nil)
                                    task.wait(0.5); spawnWait = spawnWait + 0.5
                                end

                                -- Rekam posisi Player tepat setelah TP sebagai titik acuan radius
                                local ATTACK_RADIUS = 50
                                local originPos = Vector3.new(0, 0, 0)
                                local char0 = LP.Character
                                local hrp0  = char0 and char0:FindFirstChild("HumanoidRootPart")
                                if hrp0 then originPos = hrp0.Position end

                                -- Helper: filter musuh hidup dalam radius 50 studs dari originPos
                                local function GetEnemiesInRadius()
                                    local out = {}
                                    local all = GetAnnivEnemies()
                                    for i = 1, #all do
                                        local e = all[i]
                                        if e.hrp then
                                            local dist = (e.hrp.Position - originPos).Magnitude
                                            if dist <= ATTACK_RADIUS then
                                                out[#out + 1] = e
                                            end
                                        end
                                    end
                                    return out
                                end

                                local stuckTimer     = 0
                                local STUCK_LIMIT    = 15.0
                                local lastAliveCount = #GetEnemiesInRadius()

                                while ANNIV.running do
                                    local inRange = GetEnemiesInRadius()

                                    -- Kondisi selesai: tidak ada lagi musuh dalam radius
                                    if #inRange == 0 then
                                        AnnivStatus("[OK] Semua musuh dalam radius mati! Diam 1s...", nil)
                                        break
                                    end

                                    -- Serang semua musuh dalam radius
                                    -- [FLa CPU] Direct call bukan task.spawn per target
                                    for i = 1, #inRange do
                                        local e   = inRange[i]
                                        local pos = e.hrp and e.hrp.Position or Vector3.new(0, 0, 0)
                                        pcall(function() FireAllDamage(e.guid, pos) end)
                                        pcall(function() FireHeroRemotes(e.guid, pos) end)
                                    end

                                    -- Anti-stuck: progress diukur dari berkurangnya jumlah musuh dalam radius
                                    if #inRange < lastAliveCount then
                                        lastAliveCount = #inRange
                                        stuckTimer     = 0
                                    else
                                        stuckTimer = stuckTimer + 0.08
                                        if stuckTimer >= STUCK_LIMIT then
                                            AnnivStatus("[!] Stuck " .. STUCK_LIMIT .. "s, paksa keluar...", nil)
                                            break
                                        end
                                    end

                                    AnnivStatus("[ATK] Serang... (" .. #inRange .. " musuh <= " .. ATTACK_RADIUS .. "studs)", nil)
                                    PG_Wait(0.08) -- [PingGuard] Anniversary attack inner loop
                                end


                                if not ANNIV.running then break end

                                -- ── PHASE 5: DELAY 2s LALU LOOP ULANG ───────────
                                AnnivStatus("[..] Musuh mati, delay 10s lalu mulai ulang...", nil)
                                task.wait(10)
                                if ANNIV.running then
                                    AnnivStatus("[LOOP] Mulai ulang Anniversary...", nil)
                                end
                            end
                        end

                    end -- end while ANNIV.running

                    ANNIV.running = false
                    ANNIV.thread  = nil
                end) -- end task.spawn
            else
                -- Toggle OFF
                ANNIV.running = false
                if ANNIV.thread then
                    pcall(function() task.cancel(ANNIV.thread) end)
                    ANNIV.thread = nil
                end
                AnnivStatus("[.] Idle - Toggle OFF", nil)
            end
        end,
    })

    -- ── Toggle: Spin Gems ─────────────────────────────────────────────
    -- Loop InvokeServer StartAnniversarySpin arg=1
    annivSection:Toggle({
        Flag    = "annivSpinGems",
        Title   = "Spin Gems",
        Desc    = "Spin Anniversary Gem",
        Default = false,
        Callback = function(on)
            ANNIV.spinEnabled = on
            if on then
                AnnivStatus("[..] Spin Gems aktif...", nil)
                ANNIV.spinThread = task.spawn(function()
                    local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 5)
                    local spinRE  = Remotes and Remotes:WaitForChild("StartAnniversarySpin", 5)
                    if not spinRE then
                        AnnivStatus("[X] tidak ditemukan!", nil)
                        ANNIV.spinEnabled = false
                        return
                    end
                    while ANNIV.spinEnabled do
                        pcall(function()
                            spinRE:InvokeServer(1)
                        end)
                        AnnivStatus("[>>] Spinning Gems...", nil)
                        PG_Wait(1) -- [PingGuard] ANNIV spin loop
                    end
                    AnnivStatus("[||] Spin Gems OFF.", nil)
                end)
            else
                ANNIV.spinEnabled = false
                if ANNIV.spinThread then
                    pcall(function() task.cancel(ANNIV.spinThread) end)
                    ANNIV.spinThread = nil
                end
                AnnivStatus("[||] Spin Gems OFF.", nil)
            end
        end,
    })

    -- ── Button: Claim All Gem ─────────────────────────────────────────
    -- Fire ClaimAnniversarySpinTicket:InvokeServer(arg) untuk arg = 1,3,4,5,6,7,8
    annivSection:Button({
        Title = "Claim All Gem",
        Desc  = "Claim semua reward gem anniversary (7 slot: 1,3,4,5,6,7,8)",
        Callback = function()
            task.spawn(function()
                local RE_CLAIM   = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 5)
                if not RE_CLAIM then
                    AnnivStatus("[X] tidak ditemukan!", nil)
                    return
                end
                local spinTicket = RE_CLAIM:WaitForChild("ClaimAnniversarySpinTicket", 5)
                if not spinTicket then
                    AnnivStatus("[X] tidak ditemukan!", nil)
                    return
                end
                local CLAIM_ARGS = { 1, 3, 4, 5, 6, 7, 8 }
                for i, arg in ipairs(CLAIM_ARGS) do
                    AnnivStatus("[..] Claiming Gem (" .. i .. "/" .. #CLAIM_ARGS .. ") arg=" .. arg .. "...", nil)
                    pcall(function()
                        spinTicket:InvokeServer(arg)
                    end)
                    task.wait(0.5)
                end
                AnnivStatus("[OK] ALL CLAIM DONE!", nil)
            end)
        end,
    })

end -- do Anniversary Celebration


-- ============================================================================
-- STUB SETTERS — panel belum diconvert ke 2.lua
-- Dipanggil oleh ApplyConfig saat Load Config. Tanpa definisi ini script crash
-- karena memanggil nil. Stub ini mencegah crash dan menyimpan state di variabel
-- backing sehingga logika tetap konsisten ketika panel akhirnya diconvert nanti.
-- ============================================================================

-- ── Dungeon toggle stub ───────────────────────────────────────────────────────
-- Panel Dungeon (JTR punya tombol join, bukan toggle persistent ON/OFF)
-- Belum diconvert ke 2.lua — stub simpan state saja, tidak ada visual.
if not _dungeonToggleState then _dungeonToggleState = false end
_setDungeonToggle = _setDungeonToggle or function(v)
    _dungeonToggleState = v == true
end
_visDungeon = _visDungeon or function(_v)
    -- tidak ada toggle visual di JTR panel — no-op
end

-- ── ST2 / Anniversary toggle stub ────────────────────────────────────────────
-- ST2 di 1.lua adalah panel terpisah yang belum diconvert ke 2.lua.
-- Di 2.lua ada ANNIV tapi strukturnya berbeda (tidak ada persistent toggle).
-- Stub ini simpan state ke ANNIV.running agar logika tetap tidak crash.
if not ST2 then
    ST2 = {
        running       = false,
        inMap         = false,
        enabled       = false,
        attackEnabled = false,
        waveCount     = 0,
        setAttackToggle = function(_v) end,
    }
end
_setST2Toggle = _setST2Toggle or function(v)
    ST2.enabled = v == true
    ST2.running = v == true
    if ANNIV then ANNIV.running = v == true end
end
_visST2 = _visST2 or function(_v)
    -- tidak ada toggle visual ST2 di 2.lua — no-op
end

-- ── Transparency slider ───────────────────────────────────────────────────────
-- Implementasi nyata ada di PANEL THEME (bawah). Stub ini hanya placeholder
-- agar CollectConfig tidak crash jika ThemeTab belum diload.
if not _G then _G = {} end
_G.ThemeTransparency = _G.ThemeTransparency or 50  -- default 50
_G.CurrentTheme      = _G.CurrentTheme or "Dark"   -- default Dark
_setTransSlider    = _setTransSlider    or function(v) _G.ThemeTransparency = v end
_setTransparencyVis = _setTransparencyVis or function(v) _setTransSlider(v) end
_setThemeVis        = _setThemeVis       or function(n) _G.CurrentTheme = n end

-- ── Webhook mode dropdown stub ────────────────────────────────────────────────
-- WebhookTab di 2.lua belum punya dropdown mode (By ID / By Name).
-- Stub simpan index ke _webhookMode agar CollectConfig bisa baca kembali.
-- PENTING: urutan harus sama persis dengan MODE_KEYS di CollectConfig: {"raid","siege","both"}
local _WH_MODE_KEYS = {"raid","siege","both"}
_webhookModeSetIdx = _webhookModeSetIdx or function(idx)
    if _WH_MODE_KEYS[idx] then
        _webhookMode = _WH_MODE_KEYS[idx]
    end
end


-- ============================================================
-- PLAYER TAB: Speed Run, No Clip, Anti Idle
-- Port dari 1.lua baris 7055-7237
-- Ditaruh di PlayerTab (tab Player)
-- ============================================================

-- ── State global ─────────────────────────────────────────────
local _walkSpeedState  = 160        -- default 1000%
local _noClipState     = false
local _antiIdleState   = false
local _noClipConn      = nil        -- RBXScriptConnection RunService.Stepped
local _antiIdleThread  = nil        -- task.spawn handle
local _antiIdleStart   = nil        -- os.time() saat aktif

-- ── Pastikan FLa_PressKey tersedia (guard — mungkin sudah ada dari MA block) ──
if not FLa_PressKey then
    local _FLa_VIM = nil
    pcall(function() _FLa_VIM = game:GetService("VirtualInputManager") end)
    local _FLa_VIM_ok = false
    if _FLa_VIM then
        local testOk = pcall(function() local _ = _FLa_VIM.SendKeyEvent; return type(_) == "function" end)
        _FLa_VIM_ok = testOk
    end
    local _FLa_keypress = nil
    if type(keypress) == "function" then
        _FLa_keypress = keypress
    elseif type(keyboard) == "table" and type(keyboard.press) == "function" then
        _FLa_keypress = function(kc) keyboard.press(kc); task.wait(0.05); keyboard.release(kc) end
    end
    local _FLa_keyrelease = nil
    if type(keyrelease) == "function" then _FLa_keyrelease = keyrelease end
    local _KC_MAP = {
        [Enum.KeyCode.Space] = 0x20,
        [Enum.KeyCode.W]     = 0x57,
        [Enum.KeyCode.A]     = 0x41,
        [Enum.KeyCode.S]     = 0x53,
        [Enum.KeyCode.D]     = 0x44,
    }
    function FLa_PressKey(keyCode)
        -- Method 1: VirtualInputManager (Delta Android, Xeno, Solara)
        if _FLa_VIM_ok and _FLa_VIM then
            local ok = pcall(function()
                _FLa_VIM:SendKeyEvent(true,  keyCode, false, game)
                task.wait(0.05)
                _FLa_VIM:SendKeyEvent(false, keyCode, false, game)
            end)
            if ok then return true end
        end
        -- Method 2: keypress/keyrelease UNC (KRNL, Xeno, Solara, Synapse)
        if _FLa_keypress then
            local kc = _KC_MAP[keyCode]
            if kc then
                local ok = pcall(function()
                    _FLa_keypress(kc)
                    if _FLa_keyrelease then task.wait(0.05); _FLa_keyrelease(kc) end
                end)
                if ok then return true end
            end
        end
        -- Method 3: UserInputService fire (mobile-friendly)
        local ok3 = pcall(function()
            local UIS = game:GetService("UserInputService")
            local io  = Instance.new("InputObject")
            io.KeyCode        = keyCode
            io.UserInputType  = Enum.UserInputType.Keyboard
            io.UserInputState = Enum.UserInputState.Begin
            UIS.InputBegan:Fire(io, false)
            task.wait(0.05)
            io.UserInputState = Enum.UserInputState.End
            UIS.InputEnded:Fire(io, false)
        end)
        if ok3 then return true end
        -- Method 4: no-op fallback — tidak crash, silent
        return false
    end
end

do
    -- ── Section: Speed Run ───────────────────────────────────────
    local speedSection = PlayerTab:Section({
        Title  = "Speed Run",
        Icon   = "zap",
        Opened = true,
        Box    = true,
    })

    -- Preset buttons (0%, 100%, 300%, 500%, 1000%)
    local presets = {
        { label = "0%",    v = 0   },
        { label = "100%",  v = 16  },
        { label = "300%",  v = 48  },
        { label = "500%",  v = 80  },
        { label = "1000%", v = 160 },
    }

    -- Paragraph untuk menampilkan speed saat ini
    local speedPara = speedSection:Paragraph({
        Title = "WalkSpeed",
        Desc  = "160 (1000%)",
    })

    local function SetSpeedValue(spd)
        spd = math.clamp(math.floor(spd), 0, 160)
        _walkSpeedState = spd
        local pct = math.floor(spd / 16 * 100)
        pcall(function() speedPara:SetDesc(spd .. " (" .. pct .. "%)") end)
        local char = LP.Character
        if char then
            local hum = char:FindFirstChild("Humanoid")
            if hum then hum.WalkSpeed = spd end
        end
    end

    -- Tombol preset
    for _, pr in ipairs(presets) do
        speedSection:Button({
            Title    = pr.label,
            Desc     = "Set WalkSpeed ke " .. pr.v .. " (" .. pr.label .. ")",
            Callback = function()
                SetSpeedValue(pr.v)
            end,
        })
    end

    -- Terapkan default speed 1000% saat karakter ready
    task.spawn(function()
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:WaitForChild("Humanoid", 5)
        if hum then hum.WalkSpeed = _walkSpeedState end
    end)
    -- Pertahankan speed saat respawn
    LP.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then hum.WalkSpeed = _walkSpeedState end
    end)

    -- ── Section: No Clip ─────────────────────────────────────────
    local noClipSection = PlayerTab:Section({
        Title  = "No Clip",
        Icon   = "ghost",
        Opened = true,
        Box    = true,
    })

    local _noClipToggleEl = noClipSection:Toggle({
        Flag     = "playerNoClip",
        Title    = "No Clip",
        Desc     = "Tembus tembok & objek apapun selama aktif",
        Default  = false,
        Callback = function(on)
            _noClipState = on
            -- Putus koneksi lama jika ada
            if _noClipConn then _noClipConn:Disconnect(); _noClipConn = nil end
            if on then
                -- [FLa CPU] Cache BasePart karakter, rebuild hanya saat karakter ganti
                local _ncCachedChar  = nil
                local _ncCachedParts = {}
                local _ncFrame       = 0
                local function _ncRebuildCache(char)
                    _ncCachedChar  = char
                    _ncCachedParts = {}
                    if not char then return end
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            table.insert(_ncCachedParts, part)
                        end
                    end
                end
                -- [FLa CPU] Throttle: jalan tiap 3 frame (~20fps), cukup untuk NoClip
                _noClipConn = RunService.Stepped:Connect(function()
                    _ncFrame = _ncFrame + 1
                    if _ncFrame % 3 ~= 0 then return end
                    local char = LP.Character; if not char then return end
                    -- Rebuild cache hanya saat karakter berubah
                    if char ~= _ncCachedChar then _ncRebuildCache(char) end
                    for _, part in ipairs(_ncCachedParts) do
                        if part and part.Parent and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end)
            else
                -- Restore state karakter saat NoClip dimatikan
                local char = LP.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hrp and hum then
                        local pos = hrp.CFrame
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                        task.wait(0.1)
                        hrp.CFrame = pos
                    end
                end
            end
        end,
    })

    -- Expose setter NoClip ke global (dibaca Config panel saat restore)
    _setNoClipToggle = function(v)
        _noClipState = v
        if _noClipToggleEl then pcall(function() _noClipToggleEl:Set(v) end) end
    end
    _visNoClip = function(v)
        if _noClipToggleEl then pcall(function() _noClipToggleEl:Set(v, false) end) end
    end

    -- ── Section: Anti Idle ───────────────────────────────────────
    -- Logika: bukan sekedar Anti AFK (cegah kick), tapi ANTI IDLE —
    -- simulasi aktivitas nyata agar server tidak mendeteksi player diam:
    --   1. Humanoid:Move() micro-movement setiap interval acak (180-300s)
    --   2. HumanoidRootPart CFrame micro-nudge + restore (tidak visible)
    --   3. Camera CFrame micro-rotate + restore
    --   4. Remote benign (GetRaidTeamInfos / GetCityRaidInfos) setiap 60s
    --   5. FLa_PressKey(Space) simulasi input keyboard
    --   6. CharacterController: FireServer dummy movement setiap 30s via
    --      workspace.Physics / Humanoid:SetStateEnabled toggle (paksa engine
    --      kirim network update ke server — ini yang paling efektif mencegah
    --      server-side idle detection)
    local antiIdleSection = PlayerTab:Section({
        Title  = "Anti Idle",
        Icon   = "activity",
        Opened = true,
        Box    = true,
    })

    local antiIdleStatusPara = antiIdleSection:Paragraph({
        Title = "Status",
        Desc  = "Idle - Enable untuk START",
    })

    local function AntiIdleStat(msg)
        pcall(function() antiIdleStatusPara:SetDesc(msg) end)
    end

    local _antiIdleToggleEl = antiIdleSection:Toggle({
        Flag     = "playerAntiIdle",
        Title    = "Anti Idle",
        Desc     = "Simulasi aktivitas nyata agar server tidak deteksi player diam",
        Default  = false,
        Callback = function(on)
            _antiIdleState = on
            if _antiIdleThread then
                pcall(function() task.cancel(_antiIdleThread) end)
                _antiIdleThread = nil
            end
            if on then
                _antiIdleStart  = os.time()
                _antiIdleThread = task.spawn(function()
                    local _rng           = Random.new()
                    local _lastRemote    = 0   -- tick() tracker untuk remote benign
                    local _lastNetUpdate = 0   -- tick() tracker untuk force network update
                    local RS = game:GetService("ReplicatedStorage")

                    while _antiIdleState do
                        -- Interval acak 180-300 detik antar "aksi" utama
                        local interval = 180 + _rng:NextInteger(0, 120)
                        local waited   = 0
                        while waited < interval and _antiIdleState do
                            task.wait(1); waited = waited + 1
                            -- Update status timer setiap 10 detik
                            if waited % 10 == 0 then
                                local dur = os.time() - _antiIdleStart
                                AntiIdleStat(string.format(
                                    "[ON] Active %02d:%02d:%02d | next action: %ds",
                                    math.floor(dur/3600), math.floor(dur/60)%60, dur%60,
                                    interval - waited
                                ))
                            end

                            -- [ANTI IDLE 6] Force network update setiap 30 detik:
                            -- Toggle Humanoid StateEnabled sebentar — memaksa engine
                            -- mengirim network packet ke server, server tidak anggap idle
                            local now = tick()
                            if (now - _lastNetUpdate) >= 30 then
                                _lastNetUpdate = now
                                pcall(function()
                                    local char = LP.Character; if not char then return end
                                    local hum  = char:FindFirstChildOfClass("Humanoid")
                                    if not hum or hum.Health <= 0 then return end
                                    -- Toggle state briefly — tidak visible ke player, tapi server terima update
                                    hum:SetStateEnabled(Enum.HumanoidStateType.Running, false)
                                    task.wait(0.016) -- 1 frame
                                    hum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
                                end)
                            end
                        end
                        if not _antiIdleState then break end

                        -- ── Aksi utama: simulasi aktivitas nyata ──────────────

                        pcall(function()
                            local char = LP.Character; if not char then return end
                            local hum  = char:FindFirstChildOfClass("Humanoid")
                            local hrp  = char:FindFirstChild("HumanoidRootPart")
                            if not hum or hum.Health <= 0 then return end

                            -- [ANTI IDLE 1] Humanoid:Move() micro-movement
                            pcall(function()
                                hum:Move(Vector3.new(0.001, 0, 0))
                                task.wait(0.05)
                                hum:Move(Vector3.new(0, 0, 0))
                            end)

                            -- [ANTI IDLE 2] HRP micro-nudge + restore (tidak terlihat)
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

                            -- [ANTI IDLE 3] Camera micro-rotate + restore
                            pcall(function()
                                local cam = workspace.CurrentCamera
                                if cam and cam.CameraType == Enum.CameraType.Custom then
                                    local cf = cam.CFrame
                                    cam.CFrame = cf * CFrame.Angles(0, 0.0001 * (_rng:NextNumber() - 0.5), 0)
                                    task.wait(0.05)
                                    cam.CFrame = cf
                                end
                            end)

                            task.wait(0.05)

                            -- [ANTI IDLE 4] Remote benign setiap 60 detik
                            pcall(function()
                                local now = tick()
                                if (now - _lastRemote) >= 60 then
                                    _lastRemote = now
                                    local Remotes = RS:FindFirstChild("Remotes")
                                    if Remotes then
                                        local safe = Remotes:FindFirstChild("GetRaidTeamInfos")
                                                  or Remotes:FindFirstChild("GetCityRaidInfos")
                                        if safe then pcall(function() safe:InvokeServer() end) end
                                    end
                                end
                            end)

                            -- [ANTI IDLE 5] Simulasi tekan Space via FLa_PressKey
                            pcall(function()
                                FLa_PressKey(Enum.KeyCode.Space)
                            end)
                        end)

                        AntiIdleStat("[ON] Aksi anti-idle dieksekusi!")
                    end -- end while

                    _antiIdleThread = nil
                    AntiIdleStat("Idle - Toggle OFF")
                end)
            else
                _antiIdleStart = nil
                AntiIdleStat("Idle - Enable untuk START")
            end
        end,
    })

    -- Expose setter Anti Idle ke global (dibaca Config panel saat restore)
    _setAntiAfkToggle = function(v)
        _antiIdleState = v
        if _antiIdleToggleEl then pcall(function() _antiIdleToggleEl:Set(v) end) end
    end
    _visAntiAfk = function(v)
        if _antiIdleToggleEl then pcall(function() _antiIdleToggleEl:Set(v, false) end) end
    end

    -- Expose setter WalkSpeed ke global (dibaca Config panel saat restore)
    _setSpeedSlider = function(v)
        pcall(function() SetSpeedValue(v) end)
    end

end -- do Player Tab



-- ============================================================================
-- HERO FASTROLL - WindUI Native API
-- Slide Up/Down: Section({ Opened=false, Box=true }) persis AutomationTab
-- GUID BUG FIX: spy intercept RandomHeroQuirk + HeroUseSkill, capture
--               arg1.heroGuid SEBELUM check _ourCall (manual reroll bukan ourCall)
-- ============================================================================

-- ── DATA: QUIRK LIST PER SLOT (persis 1.lua baris 3086-3120) ─────────────────
QUIRK_LIST_PER_SLOT = QUIRK_LIST_PER_SLOT or {
    {   -- Slot 1 (drawId=920001)
        {id=99013, name="Midas Touch"},
        {id=99014, name="Hyper Sprint"},
        {id=99015, name="Time Skipper"},
        {id=99016, name="Cosmic Luck"},
        {id=99017, name="Destiny Rewrite"},
        {id=99018, name="Final Judgment"},
        {id=99109, name="Golden Era"},
        {id=99110, name="The Chosen Singularity"},
        {id=99111, name="Axiom of Value"},
    },
    {   -- Slot 2 (drawId=920002)
        {id=99031, name="Resource Conqueror"},
        {id=99032, name="Elemental Overload"},
        {id=99033, name="Crimson Executioner"},
        {id=99034, name="God's Gift"},
        {id=99035, name="Apocalypse Carnival"},
        {id=99036, name="Divine Judgment"},
        {id=99112, name="Celestial Benediction"},
        {id=99113, name="Eclipse Masquerade"},
        {id=99114, name="Sovereign Verdict"},
    },
    {   -- Slot 3 (drawId=920003)
        {id=99049, name="Slayer's Instinct"},
        {id=99050, name="Harbinger of Ruin"},
        {id=99052, name="Godslayer's Fury"},
        {id=99053, name="Deicide's Endgame"},
        {id=99054, name="Final Arbiter"},
        {id=99115, name="Cosmic Cataclysm"},
        {id=99116, name="Omega Oblivion"},
        {id=99117, name="Sovereign Axiom"},
    },
}
MAX_PER_SLOT = math.huge

QUIRK_MAP = QUIRK_MAP or {}
for _, _ql in ipairs(QUIRK_LIST_PER_SLOT) do
    for _, _qq in ipairs(_ql) do QUIRK_MAP[_qq.id] = _qq.name end
end

-- ── GLOBALS ──────────────────────────────────────────────────────────────────
_HR_RPT            = _HR_RPT            or nil
_ourCall           = _ourCall           or false
DoAutoRollHero     = DoAutoRollHero     or nil
_setHeroRollToggle = _setHeroRollToggle or nil
_setHeroX100Toggle = _setHeroX100Toggle or nil
_layer0Active      = _layer0Active      or false
-- Weapon Fastroll globals
_WR_RPT              = _WR_RPT              or nil
DoAutoRollWeapon     = DoAutoRollWeapon     or nil
_setWeaponRollToggle = _setWeaponRollToggle or nil
_setWeaponX100Toggle = _setWeaponX100Toggle or nil

-- Pet Gear Fastroll globals
_PGR_RPT             = _PGR_RPT             or nil
DoAutoRollPetGear    = DoAutoRollPetGear    or nil
_setPetGearRollToggle= _setPetGearRollToggle or nil
_setPetGearX100Toggle= _setPetGearX100Toggle or nil
StartPG100Loop       = StartPG100Loop       or nil
StopPG100            = StopPG100            or nil

-- PG_GRADES_PER_MACHINE (confirmed DEX - includes GM/MM/M++)
-- R-Pet (980001): 990001-990010 + 990031 + 990032(GM) + 990033(MM) + 990034(M++)
-- Y-Pet (980002): 990011-990020 + 990041 + 990042(GM) + 990043(MM) + 990044(M++)
-- B-Pet (980003): 990021-990030 + 990051 + 990052(GM) + 990053(MM) + 990054(M++)
PG_DRAW_IDS = PG_DRAW_IDS or {980001, 980002, 980003}
PG_MACHINE_NAMES = PG_MACHINE_NAMES or {"R-Pet Gear", "Y-Pet Gear", "B-Pet Gear"}
PG_GRADES_PER_MACHINE = {  -- selalu overwrite agar grade baru selalu masuk
    -- [1] R-Pet Gear (drawId 980001)
    {
        {id=990001, name="E"}, {id=990002, name="D"}, {id=990003, name="C"},
        {id=990004, name="B"}, {id=990005, name="A"}, {id=990006, name="S"},
        {id=990007, name="SS"}, {id=990008, name="G"}, {id=990009, name="N"},
        {id=990010, name="M"}, {id=990031, name="M+"},
        {id=990032, name="GM"}, {id=990033, name="MM"}, {id=990034, name="M++"},
    },
    -- [2] Y-Pet Gear (drawId 980002)
    {
        {id=990011, name="E"}, {id=990012, name="D"}, {id=990013, name="C"},
        {id=990014, name="B"}, {id=990015, name="A"}, {id=990016, name="S"},
        {id=990017, name="SS"}, {id=990018, name="G"}, {id=990019, name="N"},
        {id=990020, name="M"}, {id=990041, name="M+"},
        {id=990042, name="GM"}, {id=990043, name="MM"}, {id=990044, name="M++"},
    },
    -- [3] B-Pet Gear (drawId 980003)
    {
        {id=990021, name="E"}, {id=990022, name="D"}, {id=990023, name="C"},
        {id=990024, name="B"}, {id=990025, name="A"}, {id=990026, name="S"},
        {id=990027, name="SS"}, {id=990028, name="G"}, {id=990029, name="N"},
        {id=990030, name="M"}, {id=990051, name="M+"},
        {id=990052, name="GM"}, {id=990053, name="MM"}, {id=990054, name="M++"},
    },
}
PG_GRADE_MAP = {}  -- [FIX] selalu overwrite, rebuild dari PG_GRADES_PER_MACHINE
for _, _pgl in ipairs(PG_GRADES_PER_MACHINE) do
    for _, _pgg in ipairs(_pgl) do PG_GRADE_MAP[_pgg.id] = _pgg.name end
end

-- W_QUIRK_LIST_PER_SLOT (dari 1.lua baris 3131)
W_QUIRK_LIST_PER_SLOT = W_QUIRK_LIST_PER_SLOT or {
    -- Slot 1
    {
        {id=99067,name="Celestial Onslaught"},
        {id=99068,name="Lucky Scavenger"},
        {id=99069,name="Titan's Wrath"},
        {id=99070,name="Omnipotent Benefactor"},
        {id=99071,name="Archangel's Judgment"},
        {id=99072,name="Avatar of Destruction"},
        {id=99118,name="Eternal Sovereign"},
        {id=99119,name="Seraphic Verdict"},
        {id=99120,name="Doombringer Ascendant"},
    },
    -- Slot 2
    {
        {id=99085,name="Celestial Onslaught"},
        {id=99086,name="Lucky Scavenger"},
        {id=99087,name="Titan's Wrath"},
        {id=99088,name="Omnipotent Benefactor"},
        {id=99089,name="Archangel's Judgment"},
        {id=99090,name="Avatar of Destruction"},
        {id=99121,name="Eternal Sovereign"},
        {id=99122,name="Seraphic Verdict"},
        {id=99123,name="Doombringer Ascendant"},
    },
    -- Slot 3
    {
        {id=99103,name="Celestial Onslaught"},
        {id=99104,name="Lucky Scavenger"},
        {id=99105,name="Titan's Wrath"},
        {id=99106,name="Omnipotent Benefactor"},
        {id=99107,name="Archangel's Judgment"},
        {id=99108,name="Avatar of Destruction"},
        {id=99124,name="Eternal Sovereign"},
        {id=99125,name="Seraphic Verdict"},
        {id=99126,name="Doombringer Ascendant"},
    },
}
W_MAX_PER_SLOT = math.huge  -- tidak ada batasan jumlah target
W_QUIRK_MAP = W_QUIRK_MAP or {}
for _, _wl in ipairs(W_QUIRK_LIST_PER_SLOT) do
    for _, _wq in ipairs(_wl) do W_QUIRK_MAP[_wq.id] = _wq.name end
end

if not FLa_CanHook then
    FLa_CanHook = function()
        return type(getrawmetatable)    == "function"
            and type(setreadonly)       == "function"
            and type(newcclosure)       == "function"
            and type(getnamecallmethod) == "function"
    end
end

-- ============================================================================
-- PANEL: REROLL TAB → HERO FASTROLL
-- Pola persis AutomationTab: Section({ Opened=false, Box=true })
-- semua elemen pakai hrSection:Paragraph/Dropdown/Toggle
-- ============================================================================
do
    local DRAWID = {920001, 920002, 920003}

    -- Reverse map name->id per slot
    local SLOT_NAME2ID = {}
    for si = 1, 3 do
        SLOT_NAME2ID[si] = {}
        for _, q in ipairs(QUIRK_LIST_PER_SLOT[si]) do
            SLOT_NAME2ID[si][q.name] = q.id
        end
    end

    local function BuildSlotValues(si)
        local out = {}
        for _, q in ipairs(QUIRK_LIST_PER_SLOT[si]) do
            table.insert(out, q.name)
        end
        return out
    end

    -- _HR_RPT state
    _HR_RPT = {
        guid       = "",
        running    = false,
        x100       = false,
        x100Thread = nil,
        slotTarget = {{}, {}, {}},
        statusEl     = nil,
        slotEls      = {nil, nil, nil},
        ddEls        = {nil, nil, nil},
        needsRefresh = false,   -- flag untuk Heartbeat poller (avoid capability error)

        SetSlot = function(i, txt)
            if _HR_RPT.slotEls[i] then
                _HR_RPT.slotEls[i]:SetDesc(txt)
            end
        end,

        Refresh = function()
            -- CAPABILITY FIX: jangan panggil SetDesc dari __namecall/task.defer thread.
            -- Set flag saja di sini; Heartbeat poller yang panggil SetDesc dari main thread.
            if not _HR_RPT.statusEl then return end
            local desc
            if _HR_RPT.guid and _HR_RPT.guid ~= "" then
                desc = "[GUID OK] " .. tostring(_HR_RPT.guid):sub(1,13) .. "..."
            else
                desc = "[..] REROLL 1x dulu di Mesin"
            end
            -- Direct call (hanya boleh dari main-thread / Heartbeat context)
            _HR_RPT.statusEl:SetDesc(desc)
        end,

        SetToggleOff = function() end,
    }

    -- ── Section (Slide Up/Down, collapsed by default) ─────────────────────────
    local hrSection = RerollTab:Section({
        Title  = "Hero Fastroll",
        Icon   = "dices",
        Opened = false,
        Box    = true,
    })

    -- Status hero
    -- [FIX] Section:Paragraph() return 1 value langsung (object).
    -- Pola identik siegeStatusPara / annivStatusPara yang terbukti bekerja.
    _HR_RPT.statusEl = hrSection:Paragraph({ Title = "Hero", Desc = "[..] REROLL 1x dulu di Mesin" })

    -- Status slot 1-3
    for i = 1, 3 do
        _HR_RPT.slotEls[i] = hrSection:Paragraph({ Title = "Slot " .. i, Desc = "Idle" })
    end

    -- Dropdown target per slot (Multi=true)
    for si = 1, 3 do
        local si_l    = si
        local nameMap = SLOT_NAME2ID[si]
        local ddEl, _ = hrSection:Dropdown({
            Flag     = "hrSlot" .. si,
            Title    = "Target Slot " .. si,
            Desc     = "Pilih quirk target slot " .. si,
            Values   = BuildSlotValues(si),
            Value    = {},
            Multi    = true,
            Callback = function(selected)
                local tbl = {}
                if type(selected) == "table" then
                    for _, nm in ipairs(selected) do
                        local id = nameMap[nm]
                        if id then tbl[id] = true end
                    end
                end
                _HR_RPT.slotTarget[si_l] = tbl
            end,
        })
        _HR_RPT.ddEls[si] = ddEl
    end

    -- Toggle Auto Roll Hero
    local _hrToggleEl = hrSection:Toggle({
        Flag     = "hrEnable",
        Title    = "Auto Roll Hero",
        Desc     = "ON = mulai reroll otomatis per slot",
        Value    = false,
        Callback = function(on)
            _HR_RPT.running = on
            if on then
                -- [FIX BUG 3] Jika x100 lagi jalan, stop dulu tanpa panggil
                -- _setHeroX100Toggle (rekursif via Toggle:Set -> Callback)
                if _HR_RPT.x100 then
                    _HR_RPT.x100 = false
                    if _HR_RPT.x100Thread then
                        pcall(function() task.cancel(_HR_RPT.x100Thread) end)
                        _HR_RPT.x100Thread = nil
                    end
                    for i=1,3 do _HR_RPT.SetSlot(i,"Idle") end
                end
                if DoAutoRollHero then DoAutoRollHero(true) end
            else
                if DoAutoRollHero then DoAutoRollHero(false) end
            end
        end,
    })

    _setHeroRollToggle = function(on)
        if _hrToggleEl then pcall(function() _hrToggleEl:Set(on) end) end
    end

    _HR_RPT.SetToggleOff = function()
        _HR_RPT.running = false
        if _hrToggleEl then pcall(function() _hrToggleEl:Set(false) end) end
    end

    -- ── x100 Reroll ───────────────────────────────────────────────────────────
    local function ScanResForTarget(res, targets)
        if type(res) ~= "table" then return nil, nil end
        local gotId, rawId = nil, nil
        local PRIO = {"finalResultId","quirkId","resultId","id","Id","result","Result"}
        for _, key in ipairs(PRIO) do
            local v = res[key]
            if type(v)=="number" and v>0 then
                rawId = rawId or v
                if QUIRK_MAP[v] then gotId = gotId or v end
                if targets[v] then return v, v end
            end
        end
        for _, v in pairs(res) do
            if type(v)=="number" and v>0 then
                rawId = rawId or v
                if QUIRK_MAP[v] then gotId = gotId or v end
                if targets[v] then return v, v end
            elseif type(v)=="table" then
                for _, vv in pairs(v) do
                    if type(vv)=="number" and vv>0 then
                        rawId = rawId or vv
                        if QUIRK_MAP[vv] then gotId = gotId or vv end
                        if targets[vv] then return vv, vv end
                    elseif type(vv)=="table" then
                        for _, vvv in pairs(vv) do
                            if type(vvv)=="number" and vvv>0 then
                                rawId = rawId or vvv
                                if QUIRK_MAP[vvv] then gotId = gotId or vvv end
                                if targets[vvv] then return vvv, vvv end
                            end
                        end
                    end
                end
            end
        end
        return gotId, rawId
    end

    local function StopX100()
        -- [FIX BUG 3] Jangan panggil _setHeroX100Toggle di sini (rekursi):
        -- StopX100 dipanggil dari dalam Callback Toggle itu sendiri
        _HR_RPT.x100 = false
        if _HR_RPT.x100Thread then
            pcall(function() task.cancel(_HR_RPT.x100Thread) end)
            _HR_RPT.x100Thread = nil
        end
        for i=1,3 do _HR_RPT.SetSlot(i,"Idle") end
    end

    local function StartX100Loop()
        if _HR_RPT.x100Thread then
            pcall(function() task.cancel(_HR_RPT.x100Thread) end)
        end
        _HR_RPT.x100Thread = task.spawn(function()
            if not (_HR_RPT.guid and _HR_RPT.guid ~= "") then
                for i=1,3 do _HR_RPT.SetSlot(i,"[..] Klik 1x di Mesin Reroll dulu") end
                while _HR_RPT.x100 and not (_HR_RPT.guid and _HR_RPT.guid ~= "") do task.wait(0.5) end
                if not _HR_RPT.x100 then return end
                task.wait(1.5)
            end
            if not RE.AutoHeroQuirk then
                for i=1,3 do _HR_RPT.SetSlot(i,"[!] Remote AutoRandomHeroQuirk nil") end
                StopX100()
                return
            end
            local attempt  = 0
            local slotDone = {false,false,false}
            while _HR_RPT.x100 do
                local allDone = true
                for si=1,3 do
                    local stopIds={}
                    for _,q in ipairs(QUIRK_LIST_PER_SLOT[si]) do
                        if _HR_RPT.slotTarget[si][q.id] then table.insert(stopIds,q.id) end
                    end
                    if #stopIds>0 and not slotDone[si] then allDone=false; break end
                end
                if allDone then
                    -- [FIX BUG 3] Cukup StopX100() saja, tidak perlu _setHeroX100Toggle
                    -- (Toggle UI di-update lewat _HR_RPT.x100=false sudah cukup)
                    StopX100()
                    break
                end
                for si=1,3 do
                    if not slotDone[si] then
                        local targets = _HR_RPT.slotTarget[si]
                        local stopIds = {}
                        for _,q in ipairs(QUIRK_LIST_PER_SLOT[si]) do
                            if targets[q.id] then table.insert(stopIds,q.id) end
                        end
                        if #stopIds==0 then
                            _HR_RPT.SetSlot(si,"[!] SELECT TARGET!")
                        else
                            attempt = attempt+1
                            _HR_RPT.SetSlot(si,"[x100] Slot"..si.." #"..attempt.."...")
                            _ourCall = true
                            local ok,res = pcall(function()
                                return RE.AutoHeroQuirk:InvokeServer({
                                    heroGuid     = _HR_RPT.guid,
                                    drawId       = DRAWID[si],
                                    stopQuirkIds = stopIds,
                                })
                            end)
                            _ourCall = false
                            if not ok then
                                _HR_RPT.SetSlot(si,"[!] Error - retry")
                            else
                                local gotId,rawId = ScanResForTarget(res,targets)
                                if gotId and targets[gotId] then
                                    local gn = QUIRK_MAP[gotId] or "ID:"..tostring(gotId)
                                    _HR_RPT.SetSlot(si,"[DONE] "..gn.." (#"..attempt..")")
                                    slotDone[si] = true
                                else
                                    local gn=(gotId and QUIRK_MAP[gotId]) or (rawId and "ID:"..tostring(rawId)) or "?"
                                    _HR_RPT.SetSlot(si,"[x100] #"..attempt.." Last: "..gn)
                                end
                            end
                        end
                    end
                end
                task.wait(0.05)
            end
            _HR_RPT.x100Thread = nil
        end)
    end

    local _x100ToggleEl = hrSection:Toggle({
        Flag     = "hrX100",
        Title    = "x100 Reroll",
        Desc     = "ON = 1 roll = 100 hasil",
        Value    = false,
        Callback = function(on)
            _HR_RPT.x100 = on
            if on then
                -- [FIX BUG 3] Jika Auto Roll Hero lagi jalan, stop dulu
                -- Tapi JANGAN panggil _setHeroRollToggle (rekursif via Toggle:Set)
                -- Cukup stop loop-nya dan update state manual
                if _HR_RPT.running then
                    _HR_RPT.running = false
                    if DoAutoRollHero then DoAutoRollHero(false) end
                end
                StartX100Loop()
            else
                StopX100()
            end
        end,
    })

    _setHeroX100Toggle = function(on)
        if _x100ToggleEl then pcall(function() _x100ToggleEl:Set(on) end) end
    end

    -- ── AUTO ROLL LOGIC ───────────────────────────────────────────────────────
    do
        local LOOPS_HR = {}

        local function StopHeroLoop(si)
            if LOOPS_HR[si] then
                pcall(function() task.cancel(LOOPS_HR[si]) end)
                LOOPS_HR[si] = nil
            end
        end

        local function StartHeroSlot(si)
            StopHeroLoop(si)
            local list    = QUIRK_LIST_PER_SLOT[si]
            local targets = _HR_RPT.slotTarget[si]
            if si==1 then _HR_RPT.Refresh() end

            LOOPS_HR[si] = task.spawn(function()
                local attempt = 0
                while _HR_RPT.running do
                    repeat
                        if not (_HR_RPT.guid and _HR_RPT.guid ~= "") then
                            _HR_RPT.SetSlot(si,"[..] Klik 1x di Mesin Reroll dulu")
                            task.wait(1); break
                        end
                        local hasTarget = false
                        for _ in pairs(targets) do hasTarget=true; break end
                        if not hasTarget then
                            _HR_RPT.SetSlot(si,"[!] SELECT TARGET!")
                            task.wait(1); break
                        end
                        if not RE.RandomHeroQuirk then
                            _HR_RPT.SetSlot(si,"[!] Remote RandomHeroQuirk nil")
                            task.wait(2); break
                        end
                        attempt = attempt+1
                        _HR_RPT.SetSlot(si,"Rolling #"..attempt.."...")

                        -- x100 path
                        if _HR_RPT.x100 then
                            if not RE.AutoHeroQuirk then
                                _HR_RPT.SetSlot(si,"[!] AutoHeroQuirk nil"); task.wait(2); break
                            end
                            local stopIds={}
                            for _,q in ipairs(list) do if targets[q.id] then table.insert(stopIds,q.id) end end
                            if #stopIds==0 then _HR_RPT.SetSlot(si,"[!] SELECT TARGET!"); task.wait(1); break end
                            _ourCall=true
                            local ok,res=pcall(function()
                                return RE.AutoHeroQuirk:InvokeServer({
                                    heroGuid=_HR_RPT.guid, drawId=DRAWID[si], stopQuirkIds=stopIds
                                })
                            end)
                            _ourCall=false
                            if not ok then _HR_RPT.SetSlot(si,"[!] x100 Error"); task.wait(1); break end
                            local gotId,_ = ScanResForTarget(res, targets)
                            if gotId and targets[gotId] then
                                _HR_RPT.SetSlot(si,"DONE: "..(QUIRK_MAP[gotId] or "?").." (#"..attempt..")")
                                StopHeroLoop(si)
                                local allDone=true
                                for i=1,3 do if LOOPS_HR[i] then allDone=false; break end end
                                if allDone then _HR_RPT.SetToggleOff() end
                                return
                            end
                            task.wait(0.05); break
                        end

                        -- Normal 1x path
                        _ourCall=true
                        local ok,res=pcall(function()
                            return RE.RandomHeroQuirk:InvokeServer({
                                heroGuid=_HR_RPT.guid, drawId=DRAWID[si],
                            })
                        end)
                        _ourCall=false
                        if not ok then task.wait(1); break end

                        local gotId,_rawId=nil,nil
                        if type(res)=="table" then
                            local PRIO={"finalResultId","quirkId","resultId","id","Id","result","Result"}
                            for _,key in ipairs(PRIO) do
                                local v=res[key]
                                if type(v)=="number" and v>0 then
                                    _rawId=_rawId or v
                                    if QUIRK_MAP[v] then gotId=v; break end
                                end
                            end
                            if not gotId then
                                for _,v in pairs(res) do
                                    if type(v)=="number" and v>0 then
                                        _rawId=_rawId or v
                                        if QUIRK_MAP[v] then gotId=v; break end
                                    end
                                end
                            end
                            if not gotId then
                                for _,v in pairs(res) do
                                    if type(v)=="table" then
                                        for _,vv in pairs(v) do
                                            if type(vv)=="number" and vv>0 then
                                                _rawId=_rawId or vv
                                                if QUIRK_MAP[vv] then gotId=vv; break end
                                            end
                                        end
                                        if gotId then break end
                                    end
                                end
                            end
                        end

                        if not gotId and _rawId and not QUIRK_MAP[_rawId] then
                            _HR_RPT.SetSlot(si,"[DBG] UnknownID:"..tostring(_rawId).." #"..attempt)
                            task.wait(0.3); break
                        end

                        if gotId and targets[gotId] then
                            _HR_RPT.SetSlot(si,"DONE: "..(QUIRK_MAP[gotId] or "?").." (#"..attempt..")")
                            StopHeroLoop(si)
                            local allDone=true
                            for i=1,3 do if LOOPS_HR[i] then allDone=false; break end end
                            if allDone then _HR_RPT.SetToggleOff() end
                            return
                        end
                        task.wait(0.05)
                    until true
                end
            end)
        end

        DoAutoRollHero = function(on)
            for i=1,3 do StopHeroLoop(i) end
            if not on then
                for i=1,3 do _HR_RPT.SetSlot(i, "Idle") end
                -- GUID tidak di-reset saat OFF: spy akan overwrite saat user reroll hero lain.
                _HR_RPT.Refresh()
                return
            end
            -- [FIX] GUID belum ada -> tampil pesan, polling sampai GUID tersedia, lalu auto-start
            if not (_HR_RPT.guid and _HR_RPT.guid ~= "") then
                for i=1,3 do _HR_RPT.SetSlot(i,"WAITING - Click 1x on Reroll Machine") end
                task.spawn(function()
                    while not (_HR_RPT.guid and _HR_RPT.guid ~= "") do task.wait(0.5) end
                    -- Jeda 1.5s agar server selesai proses manual click user
                    task.wait(1.5)
                    -- Pastikan toggle masih ON sebelum mulai
                    if _HR_RPT and _HR_RPT.running then
                        _HR_RPT.needsRefresh = true
                        for i=1,3 do StartHeroSlot(i) end
                    end
                end)
                return
            end
            for i=1,3 do StartHeroSlot(i) end
        end
    end

end -- do Hero Fastroll

-- ============================================================================
-- PANEL: REROLL TAB → WEAPON FASTROLL
-- Diconvert dari 1.lua baris 7633-7992 (UI) + 19698-19855 (logic)
-- Pakai pattern needsRefresh + Heartbeat (sama dengan Hero Fastroll)
-- ============================================================================
do
    -- ── State ────────────────────────────────────────────────────────────────
    _WR_RPT = {
        guid         = "",
        needsRefresh = false,
        statusEl     = nil,
        slotEls      = {nil, nil, nil},
        slotTarget   = {{}, {}, {}},
        running      = false,
        x100         = false,
        x100Thread   = nil,
        slotRefreshFns = {nil, nil, nil},
        SetSlot = function(i, txt)
            if _WR_RPT.slotEls[i] then
                _WR_RPT.slotEls[i]:SetDesc(txt)
            end
        end,
        Refresh = function()
            if not _WR_RPT.statusEl then return end
            local desc
            if _WR_RPT.guid and _WR_RPT.guid ~= "" then
                desc = "[GUID OK] " .. tostring(_WR_RPT.guid):sub(1,13) .. "..."
            else
                desc = "[..] REROLL 1x dulu di Mesin"
            end
            _WR_RPT.statusEl:SetDesc(desc)
        end,
        SetToggleOff = function() end,
    }

    -- ── Section ──────────────────────────────────────────────────────────────
    local wrSection = RerollTab:Section({
        Title  = "Weapon Fastroll",
        Icon   = "sword",
        Opened = false,
        Box    = true,
    })

    -- ── Status Paragraph ────────────────────────────────────────────────────
    _WR_RPT.statusEl = wrSection:Paragraph({ Title = "Weapon", Desc = "[..] REROLL 1x dulu di Mesin" })

    -- Slot status paragraphs
    for i = 1, 3 do
        _WR_RPT.slotEls[i] = wrSection:Paragraph({ Title = "Slot " .. i, Desc = "Idle" })
    end

    -- ── Target Dropdown per slot ─────────────────────────────────────────────
    for si = 1, 3 do
        local si_l = si
        local ddEl, _ = wrSection:Dropdown({
            Flag     = "wrSlot" .. si,
            Title    = "Target Slot " .. si,
            Values   = (function()
                local names = {}
                for _, q in ipairs(W_QUIRK_LIST_PER_SLOT[si_l]) do
                    table.insert(names, q.name)
                end
                return names
            end)(),
            Multi    = true,
            Value    = {},
            Callback = function(selected)
                -- selected = table of chosen names
                -- rebuild slotTarget dari selected names
                local tbl = {}
                for _, q in ipairs(W_QUIRK_LIST_PER_SLOT[si_l]) do
                    for _, selName in ipairs(selected) do
                        if selName == q.name then
                            tbl[q.id] = true
                        end
                    end
                end
                _WR_RPT.slotTarget[si_l] = tbl
            end,
        })
        -- Capture refresh fn untuk Config restore
        _WR_RPT.slotRefreshFns[si_l] = function()
            if ddEl and ddEl.Set then
                local names = {}
                for _, q in ipairs(W_QUIRK_LIST_PER_SLOT[si_l]) do
                    if _WR_RPT.slotTarget[si_l][q.id] then
                        table.insert(names, q.name)
                    end
                end
                ddEl:Set(names)
            end
        end
    end

    -- ── Toggle Auto Roll Weapon ──────────────────────────────────────────────
    local _wrToggleEl = wrSection:Toggle({
        Flag     = "wrEnable",
        Title    = "Auto Roll Weapon",
        Desc     = "ON = START REROLL",
        Value    = false,
        Callback = function(on)
            local _guard = false
            if _guard then return end
            _WR_RPT.running = on
            if on then
                -- matikan x100 jika sedang jalan
                if _WR_RPT.x100 then
                    _WR_RPT.x100 = false
                    if _WR_RPT.x100Thread then
                        pcall(function() task.cancel(_WR_RPT.x100Thread) end)
                        _WR_RPT.x100Thread = nil
                    end
                    for i=1,3 do _WR_RPT.SetSlot(i,"Idle") end
                end
                DoAutoRollWeapon(true)
            else
                DoAutoRollWeapon(false)
            end
        end,
    })

    _WR_RPT.SetToggleOff = function()
        _WR_RPT.running = false
        if _wrToggleEl then _wrToggleEl:Set(false) end
    end

    -- Expose ke global Config
    _setWeaponRollToggle = function(on)
        if on == _WR_RPT.running then return end
        _WR_RPT.running = on
        if _wrToggleEl then _wrToggleEl:Set(on) end
        if on then DoAutoRollWeapon(true) else DoAutoRollWeapon(false) end
    end

    -- ── Toggle x100 Reroll Weapon ────────────────────────────────────────────
    local _wx100ToggleEl = wrSection:Toggle({
        Flag     = "wrX100",
        Title    = "x100 Reroll",
        Desc     = "ON = 1 roll = 100 result",
        Value    = false,
        Callback = function(on)
            _WR_RPT.x100 = on
            if on then
                -- matikan Auto Roll jika sedang jalan
                if _WR_RPT.running then
                    _WR_RPT.running = false
                    -- [FIX C STACK OVERFLOW] JANGAN panggil _wrToggleEl:Set(false) di sini
                    -- (rekursif via Toggle:Set -> Callback toggle lain - pola sama dgn
                    -- "[FIX BUG 3]" di Hero Fastroll). DoAutoRollWeapon(false) sudah cukup.
                    DoAutoRollWeapon(false)
                end
                StartWRX100Loop()
            else
                StopWRX100()
            end
        end,
    })

    -- Expose ke global Config
    _setWeaponX100Toggle = function(on)
        if on == _WR_RPT.x100 then return end
        _WR_RPT.x100 = on
        if _wx100ToggleEl then _wx100ToggleEl:Set(on) end
        if on then
            if _WR_RPT.running then
                _WR_RPT.running = false
                -- [FIX C STACK OVERFLOW] sama dgn alasan di Callback di atas.
                DoAutoRollWeapon(false)
            end
            StartWRX100Loop()
        else
            StopWRX100()
        end
    end

    -- ── AUTO ROLL LOGIC - WEAPON (dari 1.lua baris 19698-19855) ─────────────
    local LOOPS_WR = {}

    local function StopWeaponLoop(si)
        if LOOPS_WR[si] then
            pcall(function() task.cancel(LOOPS_WR[si]) end)
            LOOPS_WR[si] = nil
        end
    end

    local function StartWeaponSlot(si)
        StopWeaponLoop(si)
        local list    = W_QUIRK_LIST_PER_SLOT[si]
        local targets = _WR_RPT.slotTarget[si] or {}
        local drawIds = {960001, 960002, 960003}

        -- Update status weapon saat slot 1 mulai
        if si == 1 then _WR_RPT.needsRefresh = true end

        _WR_RPT.SetSlot(si, "Memulai...")

        LOOPS_WR[si] = task.spawn(function()
            local attempt = 0
            while _WR_RPT.running do
                repeat
                    if not (_WR_RPT.guid and _WR_RPT.guid ~= "") then
                        _WR_RPT.SetSlot(si, "[..] Click 1x on Reroll Machine")
                        task.wait(1); break
                    end
                    local hasTarget = false
                    for _ in pairs(targets) do hasTarget = true; break end
                    if not hasTarget then
                        _WR_RPT.SetSlot(si, "[!] SELECT TARGET PLEASE!")
                        task.wait(1); break
                    end

                    attempt = attempt + 1
                    local names = {}
                    for _, q in ipairs(list) do
                        if targets[q.id] then table.insert(names, q.name) end
                    end
                    local tStr = table.concat(names, " / ")
                    _WR_RPT.SetSlot(si, "Rolling #"..attempt..(tStr~="" and " | "..tStr or ""))

                    _ourCall = true
                    local ok, res = pcall(function()
                        return RE.RandomWeaponQuirk:InvokeServer({
                            guid   = _WR_RPT.guid,
                            drawId = drawIds[si],
                        })
                    end)
                    _ourCall = false
                    if not ok then task.wait(0.5); break end

                    -- Scan hasil quirk (pass 1-3, dari 1.lua baris 19761-19799)
                    local gotId, _rawId = nil, nil
                    if type(res) == "table" then
                        local PRIO = {"finalResultId","quirkId","resultId","id","Id","result","Result"}
                        for _, key in ipairs(PRIO) do
                            local v = res[key]
                            if type(v)=="number" and v>0 then
                                _rawId = _rawId or v
                                if W_QUIRK_MAP[v] then gotId = v; break end
                            end
                        end
                        if not gotId then
                            for _, v in pairs(res) do
                                if type(v)=="number" and v>0 then
                                    _rawId = _rawId or v
                                    if W_QUIRK_MAP[v] then gotId = v; break end
                                end
                            end
                        end
                        if not gotId then
                            for _, v in pairs(res) do
                                if type(v)=="table" then
                                    for _, vv in pairs(v) do
                                        if type(vv)=="number" and vv>0 then
                                            _rawId = _rawId or vv
                                            if W_QUIRK_MAP[vv] then gotId = vv; break end
                                        end
                                    end
                                    if gotId then break end
                                end
                            end
                        end
                    end

                    local gotName = W_QUIRK_MAP[gotId] or (gotId and "ID:"..tostring(gotId) or "?")
                    local hit = gotId and hasTarget and targets[gotId] == true

                    if not hit and _rawId and not W_QUIRK_MAP[_rawId] then
                        _WR_RPT.SetSlot(si, "[DBG] UnknownID:"..tostring(_rawId).." #"..attempt)
                        task.wait(0.3); break
                    end

                    if hit then
                        _WR_RPT.SetSlot(si, "DONE: "..gotName.." (#"..attempt..")")
                        StopWeaponLoop(si)
                        local allDone = true
                        for i = 1, 3 do if LOOPS_WR[i] then allDone=false; break end end
                        if allDone then _WR_RPT.SetToggleOff() end
                        return
                    end

                    task.wait(0.05)
                until true
            end
        end)
    end

    DoAutoRollWeapon = function(on)
        for i = 1, 3 do StopWeaponLoop(i) end
        if not on then
            for i = 1, 3 do _WR_RPT.SetSlot(i, "Idle") end
            -- Pertahankan GUID; spy akan update sendiri saat user reroll weapon lain
            return
        end
        if not (_WR_RPT.guid and _WR_RPT.guid ~= "") then
            for i = 1, 3 do _WR_RPT.SetSlot(i, "Click 1x on Reroll Machine") end
            task.spawn(function()
                while not (_WR_RPT.guid and _WR_RPT.guid ~= "") do task.wait(0.5) end
                task.wait(1.5)
                if _WR_RPT.running then
                    _WR_RPT.needsRefresh = true
                    for i = 1, 3 do StartWeaponSlot(i) end
                end
            end)
            return
        end
        for i = 1, 3 do StartWeaponSlot(i) end
    end

    -- ── x100 Logic (dari 1.lua baris 7870-7989) ─────────────────────────────
    -- Helper scan nested 4 level untuk cari quirkId cocok target
    local function ScanWResForTarget(res, targets)
        if type(res) ~= "table" then return nil, nil end
        local gotId, rawId = nil, nil
        local PRIO = {"finalResultId","quirkId","resultId","id","Id","result","Result"}
        for _, key in ipairs(PRIO) do
            local v = res[key]
            if type(v)=="number" and v>0 then
                rawId = rawId or v
                if W_QUIRK_MAP[v] then gotId = gotId or v end
                if targets[v] then return v, v end
            end
        end
        for k, v in pairs(res) do
            if type(v)=="number" and v>0 then
                rawId = rawId or v
                if W_QUIRK_MAP[v] then gotId = gotId or v end
                if targets[v] then return v, v end
            elseif type(v)=="table" then
                for _, vv in pairs(v) do
                    if type(vv)=="number" and vv>0 then
                        rawId = rawId or vv
                        if W_QUIRK_MAP[vv] then gotId = gotId or vv end
                        if targets[vv] then return vv, vv end
                    elseif type(vv)=="table" then
                        for _, vvv in pairs(vv) do
                            if type(vvv)=="number" and vvv>0 then
                                rawId = rawId or vvv
                                if W_QUIRK_MAP[vvv] then gotId = gotId or vvv end
                                if targets[vvv] then return vvv, vvv end
                            end
                        end
                    end
                end
            end
        end
        return gotId, rawId
    end

    function StopWRX100()
        -- [FIX C STACK OVERFLOW] StopWRX100 dipanggil dari dalam Callback Toggle
        -- "x100 Reroll" itu sendiri (else branch saat on=false). :Set(false) di sini
        -- men-trigger Callback yg sama lagi -> rekursi tanpa henti sampai C stack
        -- overflow. Pola identik dgn StopX100 ("[FIX BUG 3]") di Hero Fastroll -
        -- state (_WR_RPT.x100) sudah cukup di-set manual, tidak perlu :Set() di sini.
        _WR_RPT.x100 = false
        if _WR_RPT.x100Thread then
            pcall(function() task.cancel(_WR_RPT.x100Thread) end)
            _WR_RPT.x100Thread = nil
        end
        for i = 1, 3 do _WR_RPT.SetSlot(i, "Idle") end
    end

    function StartWRX100Loop()
        if _WR_RPT.x100Thread then
            pcall(function() task.cancel(_WR_RPT.x100Thread) end)
        end
        _WR_RPT.x100Thread = task.spawn(function()
            -- Tunggu GUID
            if not (_WR_RPT.guid and _WR_RPT.guid ~= "") then
                for i=1,3 do _WR_RPT.SetSlot(i, "[..] Klik 1x di Mesin Reroll dulu") end
                while _WR_RPT.x100 and not (_WR_RPT.guid and _WR_RPT.guid ~= "") do task.wait(0.5) end
                if not _WR_RPT.x100 then return end
                task.wait(1.5)
            end
            if not RE.AutoWeaponQuirk then
                for i=1,3 do _WR_RPT.SetSlot(i, "[!] Remote AutoRandomWeaponQuirk nil") end
                StopWRX100(); return
            end
            local attempt = 0
            local slotDone = {false, false, false}

            while _WR_RPT.x100 do
                -- Cek apakah semua slot sudah DONE
                local allDone = true
                for si = 1, 3 do
                    local targets = _WR_RPT.slotTarget[si]
                    local hasStop = false
                    for _, q in ipairs(W_QUIRK_LIST_PER_SLOT[si]) do
                        if targets[q.id] then hasStop = true; break end
                    end
                    if hasStop and not slotDone[si] then allDone = false; break end
                end
                if allDone then StopWRX100(); break end

                for si = 1, 3 do
                    if not slotDone[si] then
                        local targets = _WR_RPT.slotTarget[si]
                        local drawId = ({960001,960002,960003})[si]
                        local stopIds = {}
                        for _, q in ipairs(W_QUIRK_LIST_PER_SLOT[si]) do
                            if targets[q.id] then table.insert(stopIds, q.id) end
                        end
                        if #stopIds == 0 then
                            _WR_RPT.SetSlot(si, "[!] SELECT TARGET!")
                        else
                            attempt = attempt + 1
                            _WR_RPT.SetSlot(si, "[x100] Slot"..si.." #"..attempt.."...")
                            _ourCall = true
                            local ok, res = pcall(function()
                                return RE.AutoWeaponQuirk:InvokeServer({
                                    guid         = _WR_RPT.guid,
                                    drawId       = drawId,
                                    stopQuirkIds = stopIds,
                                })
                            end)
                            _ourCall = false
                            if not ok then
                                _WR_RPT.SetSlot(si, "[!] Error - retry")
                            else
                                local gotId, rawId = ScanWResForTarget(res, targets)
                                local hit = gotId ~= nil and targets[gotId] == true
                                if hit then
                                    local gn = W_QUIRK_MAP[gotId] or "ID:"..tostring(gotId)
                                    _WR_RPT.SetSlot(si, "[DONE] "..gn.." (#"..attempt..")")
                                    slotDone[si] = true
                                else
                                    local gn = (gotId and W_QUIRK_MAP[gotId]) or (rawId and "ID:"..tostring(rawId)) or "?"
                                    _WR_RPT.SetSlot(si, "[x100] #"..attempt.." Last: "..gn)
                                end
                            end
                        end
                    end
                end
                task.wait(0.05)
            end
        end)
    end

    -- ── Heartbeat poller Weapon Fastroll ─────────────────────────────────────
    RunService.Heartbeat:Connect(function()
        if not (_WR_RPT and _WR_RPT.needsRefresh) then return end
        _WR_RPT.needsRefresh = false
        pcall(_WR_RPT.Refresh)
    end)

end -- do Weapon Fastroll

-- ============================================================================
-- PANEL: REROLL TAB → PET GEAR FASTROLL
-- Diconvert dari 1.lua baris 8002-8215 (UI) + 19858-20018 (logic 1x) +
--                  3340-3501 (logic 100x) + 20054-20070 (capture GUID)
-- BEDA dari Weapon/Hero Fastroll: Pet Gear = 3 MESIN INDEPENDEN (R/Y/B-Pet Gear),
-- masing-masing punya GUID, target grade, toggle Fastroll, dan toggle 100x SENDIRI
-- (bukan 1 toggle global untuk 3 slot seperti Weapon). Toggle OFF normal me-reset
-- GUID (wajib reroll manual 1x lagi) - 100x OFF TIDAK reset GUID. Pola asimetri ini
-- persis sama dengan 1.lua, dipertahankan sesuai sumber.
-- Pakai pattern needsRefresh + Heartbeat (sama dengan Hero/Weapon Fastroll)
-- ============================================================================
-- ── PET GEAR FASTROLL: logic functions (top-level, di luar do block) ────────
-- [DEPTH FIX] Semua fungsi logic diangkat ke top-level agar tidak menambah
-- kedalaman nesting block di dalam do..end. Fungsi UI (WindUI callback) di
-- dalam do block hanya memanggil fungsi-fungsi ini, bukan mendefinisikannya.
-- Ref: StartPetGearSlot, DoAutoRollPetGear, StartPG100Loop, dll.
_PG_LOOPS = {}  -- replaces local LOOPS_PG; must be global for top-level access

function _PG_StopLoop(si)
    if _PG_LOOPS[si] then
        pcall(function() task.cancel(_PG_LOOPS[si]) end)
        _PG_LOOPS[si] = nil
    end
end

function _PG_FindGradeId(t, d)
    if type(t) ~= "table" or d > 4 then return nil end
    for k, v in pairs(t) do
        if type(v) == "number" and v >= 990000 and v <= 999999 then
            return v
        elseif type(v) == "table" then
            local found = _PG_FindGradeId(v, d+1)
            if found then return found end
        end
    end
    return nil
end

function _PG_FindGradeId100(t, d)
    if type(t) ~= "table" or d > 4 then return nil end
    for k, v in pairs(t) do
        if type(v) == "number" and v > 0 then
            if _PGR_RPT and _PGR_RPT.targets then return nil end
        elseif type(v) == "table" then
            local found = _PG_FindGradeId100(v, d+1)
            if found then return found end
        end
    end
    return nil
end

function _PG_StartSlot(si)
    _PG_StopLoop(si)
    local drawId = PG_DRAW_IDS[si]
    if not (_PGR_RPT.guids[si] and _PGR_RPT.guids[si] ~= "") then
        _PGR_RPT.SetRoll(si, "[..] Click 1x on Reroll Machine")
        task.spawn(function()
            while _PGR_RPT.running[si] do
                if _PGR_RPT.guids[si] and _PGR_RPT.guids[si] ~= "" then
                    _PG_StartSlot(si)
                    return
                end
                task.wait(0.5)
            end
        end)
        return
    end
    local attempt = 0
    _PG_LOOPS[si] = task.spawn(function()
        while _PGR_RPT.running[si] do
            repeat
                if not (_PGR_RPT.guids[si] and _PGR_RPT.guids[si] ~= "") then
                    _PGR_RPT.SetRoll(si, "[..] Click 1x on Reroll Machine")
                    task.wait(1); break
                end
                local targets = _PGR_RPT.targets[si]
                local hasTarget = false
                for _ in pairs(targets) do hasTarget = true; break end
                if not hasTarget then
                    _PGR_RPT.SetRoll(si, "[!] SELECT TARGET PLEASE!")
                    task.wait(1); break
                end
                attempt = attempt + 1
                _PGR_RPT.SetRoll(si, "[~] Roll #" .. attempt)
                _ourCall = true
                local ok, res = pcall(function()
                    return RE.RandomPetGearGrade:InvokeServer({
                        guid   = _PGR_RPT.guids[si],
                        drawId = drawId,
                    })
                end)
                _ourCall = false
                if not ok then
                    _PGR_RPT.SetRoll(si, "[!] Error - retry...")
                    task.wait(0.5); break
                end
                local gotId = nil
                if type(res) == "table" then
                    gotId = res.gradeId or res.grade or res.id or res.resultId
                    if type(gotId) ~= "number" and type(res.data) == "table" then
                        gotId = res.data.grade or res.data.gradeId or res.data.id
                    end
                    if type(gotId) ~= "number" then
                        gotId = _PG_FindGradeId(res, 1)
                    end
                end
                local hit = gotId and hasTarget and targets[gotId] == true
                if hit then
                    _PGR_RPT.SetRoll(si, "[!] Target SUCCES! (#"..attempt..")")
                    local gradeName = PG_GRADE_MAP[gotId] or "?"
                    _PGR_RPT.SetLast(si, "Last: "..gradeName.." - TARGET!")
                    _PGR_RPT.running[si] = false
                    if _PGR_RPT.toggleEls[si] then _PGR_RPT.toggleEls[si]:Set(false) end
                    break
                else
                    _PGR_RPT.SetRoll(si, "[OK] Roll #"..attempt.." DONE")
                    local gradeName = gotId and PG_GRADE_MAP[gotId] or "?"
                    _PGR_RPT.SetLast(si, "Last: "..gradeName)
                end
                task.wait(0.05)
            until true
        end
        _PGR_RPT.SetRoll(si, "[.] Idle")
    end)
end

function DoAutoRollPetGear(si, on)
    _PG_StopLoop(si)
    _PGR_RPT.running[si] = on
    if not on then
        _PGR_RPT.guids[si] = ""
        _PGR_RPT.captured[si] = false
        _PGR_RPT.needsRefresh[si] = true
        _PGR_RPT.SetRoll(si, "[.] Idle")
        return
    end
    local hasTarget = false
    for _ in pairs(_PGR_RPT.targets[si]) do hasTarget = true; break end
    if not hasTarget then
        _PGR_RPT.SetRoll(si, "[!] SELECT TARGET PLEASE!")
    end
    _PG_StartSlot(si)
end

function _PG_SetOff100(si)
    -- [FIX C STACK OVERFLOW] _PG_SetOff100 dipanggil dari dalam Callback Toggle
    -- "100x Reroll" itu sendiri (else branch saat on=false). Memanggil :Set(false)
    -- di sini men-trigger Callback yang sama lagi secara synchronous -> Callback
    -- panggil _PG_SetOff100 lagi -> :Set(false) lagi -> rekursi tanpa henti sampai
    -- C stack overflow. Pola identik dgn yg sudah ditemukan & difix di Hero Fastroll
    -- StopX100 ("[FIX BUG 3]"). State (_PGR_RPT.x100[si]) sudah cukup di-set manual;
    -- tidak perlu :Set() di sini.
    _PGR_RPT.x100[si] = false
    if _PGR_RPT.x100Thread[si] then
        pcall(function() task.cancel(_PGR_RPT.x100Thread[si]) end)
        _PGR_RPT.x100Thread[si] = nil
    end
    _PGR_RPT.SetRoll(si, "[.] Idle")
end

function StartPG100Loop(si)
    if _PGR_RPT.x100Thread[si] then
        pcall(function() task.cancel(_PGR_RPT.x100Thread[si]) end)
    end
    _PGR_RPT.x100Thread[si] = task.spawn(function()
        local function CollectStopIds()
            local ids = {}
            for gradeId, isSelected in pairs(_PGR_RPT.targets[si]) do
                if isSelected then table.insert(ids, gradeId) end
            end
            return ids
        end
        if not (_PGR_RPT.guids[si] and _PGR_RPT.guids[si] ~= "") then
            _PGR_RPT.SetRoll(si, "[..] Click 1x on Reroll Machine")
            while _PGR_RPT.x100[si] do
                if _PGR_RPT.guids[si] and _PGR_RPT.guids[si] ~= "" then break end
                task.wait(0.5)
            end
            if not _PGR_RPT.x100[si] then return end
        end
        local stopIds = CollectStopIds()
        if #stopIds == 0 then
            _PGR_RPT.SetRoll(si, "[!] SELECT TARGET PLEASE!")
            _PG_SetOff100(si)
            return
        end
        local attempt = 0
        while _PGR_RPT.x100[si] do
            repeat
                if not (_PGR_RPT.guids[si] and _PGR_RPT.guids[si] ~= "") then
                    _PGR_RPT.SetRoll(si, "[..] Click 1x on Reroll Machine")
                    task.wait(1); break
                end
                local curStopIds = CollectStopIds()
                if #curStopIds == 0 then
                    _PGR_RPT.SetRoll(si, "[!] SELECT TARGET PLEASE!")
                    task.wait(1); break
                end
                attempt = attempt + 1
                _PGR_RPT.SetRoll(si, "[~] 100x Roll #"..attempt.."...")
                if not RE.AutoPetGearGrade then
                    _PGR_RPT.SetRoll(si, "[!] Remote Auto100x tidak ditemukan!")
                    task.wait(2); break
                end
                _ourCall = true
                local ok, res = pcall(function()
                    return RE.AutoPetGearGrade:InvokeServer({
                        drawId       = PG_DRAW_IDS[si],
                        stopGradeIds = curStopIds,
                        guid         = _PGR_RPT.guids[si],
                    })
                end)
                _ourCall = false
                if not ok then
                    _PGR_RPT.SetRoll(si, "[!] Error - retry...")
                    task.wait(0.5); break
                end
                local gotId = nil
                if type(res) == "table" then
                    gotId = res.gradeId or res.grade or res.id or res.resultId
                    if type(gotId) ~= "number" and type(res.data) == "table" then
                        gotId = res.data.grade or res.data.gradeId or res.data.id
                    end
                    if type(gotId) ~= "number" then
                        local deepHit = nil
                        local function _scan100(t, d)
                            if type(t) ~= "table" or d > 4 then return end
                            for k, v in pairs(t) do
                                if type(v) == "number" and v > 0 then
                                    if _PGR_RPT.targets[si][v] then deepHit = v; return end
                                    if PG_GRADE_MAP[v] then gotId = gotId or v end
                                elseif type(v) == "table" then
                                    _scan100(v, d+1)
                                    if deepHit then return end
                                end
                            end
                        end
                        _scan100(res, 1)
                        if deepHit then gotId = deepHit end
                    end
                end
                local hit = gotId ~= nil and _PGR_RPT.targets[si][gotId] == true
                if hit then
                    _PGR_RPT.SetRoll(si, "[DONE] Target FOUND! (100x Batch #"..attempt..")")
                    local gradeName = PG_GRADE_MAP[gotId] or "?"
                    _PGR_RPT.SetLast(si, "Last: "..gradeName.." - TARGET!")
                    _PG_SetOff100(si)
                    return
                else
                    _PGR_RPT.SetRoll(si, "[OK] 100x Batch #"..attempt.." DONE")
                    local gradeName = gotId and PG_GRADE_MAP[gotId] or "?"
                    _PGR_RPT.SetLast(si, "Last: "..gradeName)
                end
                task.wait(0.05)
            until true
        end
        _PG_SetOff100(si)
    end)
end

StopPG100 = _PG_SetOff100

-- ── PET GEAR FASTROLL: state init + UI (inside do block, thin wrapper only) ─
do
    -- ── State ────────────────────────────────────────────────────────────────
    _PGR_RPT = {
        guids         = {"", "", ""},
        captured      = {false, false, false},
        targets       = {{}, {}, {}},
        running       = {false, false, false},
        x100          = {false, false, false},
        x100Thread    = {nil, nil, nil},
        needsRefresh  = {false, false, false},
        statusEls     = {nil, nil, nil},
        rollEls       = {nil, nil, nil},
        lastEls       = {nil, nil, nil},
        toggleEls     = {nil, nil, nil},
        x100ToggleEls = {nil, nil, nil},
        ddRefreshFns  = {nil, nil, nil},
        SetRoll = function(si, txt)
            if _PGR_RPT.rollEls[si] then _PGR_RPT.rollEls[si]:SetDesc(txt) end
        end,
        SetLast = function(si, txt)
            if _PGR_RPT.lastEls[si] then _PGR_RPT.lastEls[si]:SetDesc(txt) end
        end,
        Refresh = function(si)
            if not _PGR_RPT.statusEls[si] then return end
            local desc
            if _PGR_RPT.guids[si] and _PGR_RPT.guids[si] ~= "" then
                desc = "[GUID OK] " .. tostring(_PGR_RPT.guids[si]):sub(1,13) .. "..."
            else
                desc = "[..] REROLL 1x dulu di Mesin"
            end
            _PGR_RPT.statusEls[si]:SetDesc(desc)
        end,
    }

    -- ── Section ──────────────────────────────────────────────────────────────
    local pgrSection = RerollTab:Section({
        Title  = "Pet Gear Fastroll",
        Icon   = "package",
        Opened = false,
        Box    = true,
    })

    -- ── UI per mesin (R/Y/B-Pet Gear) ────────────────────────────────────────
    for msi = 1, 3 do
        local msi_l = msi
        _PGR_RPT.statusEls[msi_l] = pgrSection:Paragraph({
            Title = PG_MACHINE_NAMES[msi_l],
            Desc  = "[..] REROLL 1x dulu di Mesin",
        })
        _PGR_RPT.rollEls[msi_l] = pgrSection:Paragraph({ Title = "Status", Desc = "Idle" })
        _PGR_RPT.lastEls[msi_l] = pgrSection:Paragraph({ Title = "Last", Desc = "-" })
        local ddEl, _ = pgrSection:Dropdown({
            Flag     = "pgrDD" .. msi,
            Title    = "Target " .. PG_MACHINE_NAMES[msi_l],
            Values   = (function()
                local names = {}
                for _, g in ipairs(PG_GRADES_PER_MACHINE[msi_l]) do
                    table.insert(names, g.name)
                end
                return names
            end)(),
            Multi    = true,
            Value    = {},
            Callback = function(selected)
                local tbl = {}
                for _, g in ipairs(PG_GRADES_PER_MACHINE[msi_l]) do
                    for _, selName in ipairs(selected) do
                        if selName == g.name then tbl[g.id] = true end
                    end
                end
                _PGR_RPT.targets[msi_l] = tbl
            end,
        })
        _PGR_RPT.ddRefreshFns[msi_l] = function()
            if ddEl and ddEl.Set then
                local names = {}
                for _, g in ipairs(PG_GRADES_PER_MACHINE[msi_l]) do
                    if _PGR_RPT.targets[msi_l][g.id] then table.insert(names, g.name) end
                end
                ddEl:Set(names)
            end
        end
        local toggleEl = pgrSection:Toggle({
            Flag     = "pgrToggle" .. msi,
            Title    = "Fastroll " .. PG_MACHINE_NAMES[msi_l],
            Desc     = "ON = START REROLL",
            Value    = false,
            Callback = function(on) DoAutoRollPetGear(msi_l, on) end,
        })
        _PGR_RPT.toggleEls[msi_l] = toggleEl
        local x100El = pgrSection:Toggle({
            Flag     = "pgrX100_" .. msi,
            Title    = "100x Reroll " .. PG_MACHINE_NAMES[msi_l],
            Desc     = "ON = 100x per invoke",
            Value    = false,
            Callback = function(on)
                _PGR_RPT.x100[msi_l] = on
                if on then
                    if _PGR_RPT.running[msi_l] then
                        _PGR_RPT.running[msi_l] = false
                        -- [FIX C STACK OVERFLOW] JANGAN panggil toggleEls[msi_l]:Set(false)
                        -- di sini (rekursif via Toggle:Set -> Callback toggle lain, lalu
                        -- balik lagi - sama dgn pola "[FIX BUG 3]" di Hero Fastroll).
                        -- State (_PGR_RPT.running) + DoAutoRollPetGear sudah cukup utk stop loop.
                        DoAutoRollPetGear(msi_l, false)
                    end
                    StartPG100Loop(msi_l)
                else
                    StopPG100(msi_l)
                end
            end,
        })
        _PGR_RPT.x100ToggleEls[msi_l] = x100El
    end

    -- ── Expose globals ────────────────────────────────────────────────────────
    _setPetGearRollToggle = function(si, on)
        if _PGR_RPT.running[si] == on then return end
        _PGR_RPT.running[si] = on
        if _PGR_RPT.toggleEls[si] then _PGR_RPT.toggleEls[si]:Set(on) end
        DoAutoRollPetGear(si, on)
    end
    _setPetGearX100Toggle = function(si, on)
        if _PGR_RPT.x100[si] == on then return end
        _PGR_RPT.x100[si] = on
        if _PGR_RPT.x100ToggleEls[si] then _PGR_RPT.x100ToggleEls[si]:Set(on) end
        if on then
            if _PGR_RPT.running[si] then
                _PGR_RPT.running[si] = false
                -- [FIX C STACK OVERFLOW] sama dgn alasan di Callback x100El di atas -
                -- jangan :Set() toggle lain dari sini.
                DoAutoRollPetGear(si, false)
            end
            StartPG100Loop(si)
        else
            StopPG100(si)
        end
    end

    -- ── Heartbeat poller (3 mesin independen) ─────────────────────────────────
    RunService.Heartbeat:Connect(function()
        for si = 1, 3 do
            if _PGR_RPT.needsRefresh[si] then
                _PGR_RPT.needsRefresh[si] = false
                pcall(_PGR_RPT.Refresh, si)
            end
        end
    end)

end -- do Pet Gear Fastroll

-- FIX BUG GUID: capture dilakukan SEBELUM check _ourCall untuk remote reroll
--               manual player. HeroUseSkill juga di-intercept untuk HERO_GUIDS.
-- Confirmed SimpleSpy: RandomHeroQuirk:InvokeServer({heroGuid=..., drawId=...})
-- ============================================================================
do
    local function IsValidGUID(s)
        return type(s)=="string" and #s>20 and s:find("-")~=nil
    end

    -- Capture heroGuid dari arg table ke _HR_RPT.guid dan HERO_GUIDS
    local function _captureHeroGuid(arg1)
        if type(arg1)~="table" then return end
        local g = arg1.heroGuid or arg1.HeroGuid or arg1.guid
        if not IsValidGUID(g) then return end
        -- Update _HR_RPT
        if _HR_RPT then
            _HR_RPT.guid = g
            -- CAPABILITY FIX: tidak panggil Refresh/SetDesc dari __namecall thread
            -- (menyebabkan 'lacking capability Plugin' error).
            -- Set flag; Heartbeat poller yang update UI dari main thread.
            _HR_RPT.needsRefresh = true
        end
        -- Update HERO_GUIDS global
        if HERO_GUIDS then
            local dup=false
            for _,ex in ipairs(HERO_GUIDS) do if ex==g then dup=true; break end end
            if not dup then table.insert(HERO_GUIDS,g) end
        end
    end

    -- [FIX SCOPE] _capturePetGearGuid diangkat ke level do block agar bisa diakses
    -- oleh wrap InvokeServer langsung (yang ada di luar SetupUniversalSpy)
    local function _capturePetGearGuid(arg1)
        if type(arg1) ~= "table" then return end
        local g   = arg1.guid
        local dId = arg1.drawId
        if not IsValidGUID(g) then return end
        if type(dId) ~= "number" then return end
        local si = ({[980001]=1, [980002]=2, [980003]=3})[dId]
        if si and _PGR_RPT then
            _PGR_RPT.guids[si]        = g
            _PGR_RPT.captured[si]     = true
            _PGR_RPT.needsRefresh[si] = true
        end
    end

    local function SetupUniversalSpy()
        if _layer0Active then return end
        _layer0Active = true

        -- Cache remote objects saat setup
        local _rHero      = RE.RandomHeroQuirk
        local _rAuto      = RE.AutoHeroQuirk
        local _rWeapon    = RE.RandomWeaponQuirk
        local _rPetG      = RE.RandomPetGearGrade
        local _rHeroSkill = RE.HeroUseSkill  -- untuk capture GUID saat combat biasa

        -- [FIX GUID PET GEAR] Nama remote sebagai fallback jika object reference meleset
        -- SimpleSpy confirmed: RandomHeroEquipGrade:InvokeServer({guid=..., drawId=980001})
        local _PET_GEAR_REMOTE_NAMES = {
            ["RandomHeroEquipGrade"]     = true,
            ["AutoRandomHeroEquipGrade"] = true,
        }

        -- Capture weaponGuid dari arg table ke _WR_RPT.guid
        local function _captureWeaponGuid(arg1)
            if type(arg1) ~= "table" then return end
            local g = arg1.guid or arg1.weaponGuid or arg1.id
            if not IsValidGUID(g) then return end
            if _WR_RPT then
                _WR_RPT.guid = g
                _WR_RPT.needsRefresh = true
            end
        end

        -- _capturePetGearGuid sudah diangkat ke level do block di atas (scope fix)

        local hookOk = false
        pcall(function()
            if not FLa_CanHook() then return end
            local mt = getrawmetatable(game)
            if not mt then return end

            -- [FIX HOOK RELIABILITY] _old di-forward-declare, baru diisi SETELAH
            -- hook benar2 terpasang (lewat hookmetamethod ATAU raw mt.__namecall).
            -- Versi lama: "local _old = mt.__namecall; if not _old then return end"
            -- -> kalau __namecall kebaca nil di executor ini (belum pernah disentuh
            -- hook resmi apapun), SetupUniversalSpy() diam2 GAGAL total, hookOk
            -- tetap false, capture GUID jatuh ke fallback poll 2 detik yang kurang
            -- akurat/telat. Ini pola persis kenapa GUID cuma "muncul" kalau
            -- SimpleSpy dibuka bareng: SimpleSpy masang hook-nya sendiri (lazimnya
            -- lewat hookmetamethod), __namecall jadi "kesentuh" & valid duluan,
            -- baru sesudah itu punya kita kebagian ikut nempel. Fix: hookmetamethod
            -- jadi jalur utama (gak bakal nil walau belum ada yang hook duluan),
            -- raw metatable cuma fallback kalau executor beneran gak nyediain
            -- hookmetamethod sama sekali.
            local _old

            local _spyFn = newcclosure(function(self, ...)
                local _m = ""
                pcall(function() _m = getnamecallmethod() end)

                -- Pass-through semua method selain FireServer/InvokeServer
                if _m ~= "FireServer" and _m ~= "InvokeServer" then
                    return _old(self, ...)
                end

                local arg1 = select(1, ...)

                -- ── HeroUseSkill: capture heroGuid ke HERO_GUIDS saat combat ──
                if self == _rHeroSkill and not _ourCall then
                    if type(arg1)=="table" and IsValidGUID(arg1.heroGuid) then
                        if HERO_GUIDS then
                            local dup=false
                            for _,g in ipairs(HERO_GUIDS) do
                                if g==arg1.heroGuid then dup=true; break end
                            end
                            if not dup then table.insert(HERO_GUIDS, arg1.heroGuid) end
                        end
                    end
                    return _old(self, ...)
                end

                -- ── Bukan remote target kita → pass through ──────────────────
                -- [FIX] dual check: object reference ATAU nama remote
                -- (object ref bisa meleset jika WaitForChild return instance berbeda)
                local _selfName = ""
                pcall(function() _selfName = self.Name end)
                local _isPetGear = (self == _rPetG) or (_PET_GEAR_REMOTE_NAMES[_selfName] == true)
                if self~=_rHero and self~=_rAuto and self~=_rWeapon and not _isPetGear then
                    return _old(self, ...)
                end

                -- Jalankan remote DULU (tanpa pcall, jaga context namecall)
                local r1,r2,r3,r4,r5 = _old(self, ...)

                -- Capture hanya jika bukan panggilan kita sendiri
                if not _ourCall then
                    if self == _rHero or self == _rAuto then
                        pcall(_captureHeroGuid, arg1)
                    elseif self == _rWeapon then
                        pcall(_captureWeaponGuid, arg1)
                    elseif _isPetGear then
                        -- [FIX] pakai _isPetGear (name-based) bukan self==_rPetG
                        pcall(_capturePetGearGuid, arg1)
                    end
                end

                return r1,r2,r3,r4,r5
            end)

            -- [FIX] hookmetamethod diprioritaskan (cara yang sama kayak SimpleSpy
            -- & kebanyakan spy tool) -- raw mt.__namecall cuma fallback kalau
            -- executor beneran gak nyediain hookmetamethod.
            if type(hookmetamethod) == "function" then
                _old = hookmetamethod(game, "__namecall", _spyFn)
            else
                _old = mt.__namecall or function(s, ...)
                    return s[getnamecallmethod()](s, ...)
                end
                setreadonly(mt, false)
                mt.__namecall = _spyFn
                setreadonly(mt, true)
            end

            _G.__FLa_SpyFn = _spyFn  -- referensi dipakai watchdog re-assert (lihat InitAllCaptureLayers)
            hookOk = true
            print("[FLa Spy] __namecall hook OK via " .. (type(hookmetamethod)=="function" and "hookmetamethod" or "raw metatable"))
        end)

        if not hookOk then
            -- Fallback: polling PlayerManager tiap 2 detik
            task.spawn(function()
                while LP and LP.Parent do
                    task.wait(2)
                    pcall(function()
                        local _pm = require(game:GetService("ReplicatedStorage").Scripts.Client.Manager.PlayerManager)
                        if not _pm or not _pm.localPlayerData then return end
                        local heroes = _pm.localPlayerData.heros or _pm.localPlayerData.heroes
                        if heroes then
                            for guid, data in pairs(heroes) do
                                if IsValidGUID(guid) and data.isEquip then
                                    if HERO_GUIDS then
                                        local dup=false
                                        for _,ex in ipairs(HERO_GUIDS) do if ex==guid then dup=true; break end end
                                        if not dup then table.insert(HERO_GUIDS,guid) end
                                    end
                                    if _HR_RPT and (_HR_RPT.guid==nil or _HR_RPT.guid=="") then
                                        _HR_RPT.guid = guid
                                        _HR_RPT.needsRefresh = true
                                    end
                                end
                            end
                        end
                    -- Weapon GUID fallback
                        local weapons = _pm.localPlayerData.weapons
                        if weapons and _WR_RPT and (_WR_RPT.guid==nil or _WR_RPT.guid=="") then
                            for guid, data in pairs(weapons) do
                                if IsValidGUID(guid) and data.isEquip then
                                    _WR_RPT.guid = guid
                                    _WR_RPT.needsRefresh = true
                                    break
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

    -- [FIX] Jangan pakai task.delay -- hook dipasang di akhir script setelah
    -- semua panel WindUI selesai dibuat (lihat baris paling akhir file ini)

    -- HEARTBEAT POLLER: update UI dari main-thread
    -- SetDesc tidak boleh dipanggil dari __namecall/task.defer thread karena
    -- menyebabkan 'lacking capability Plugin' error.
    -- Solusi: spy hanya set _HR_RPT.needsRefresh=true, Heartbeat yang eksekusi.
    RunService.Heartbeat:Connect(function()
        if not (_HR_RPT and _HR_RPT.needsRefresh) then return end
        _HR_RPT.needsRefresh = false
        pcall(_HR_RPT.Refresh)  -- pcall di sini AMAN: main-thread / Heartbeat context
    end)
end

-- ============================================================================
-- PANEL: REROLL TAB → AUTO GACHA HALO
-- Diconvert dari 1.lua: DoAutoRollHalo (baris 3254) + PANEL HALO (baris 8217)
-- Remote: RE.RerollHalo:InvokeServer(drawId)  (RemoteFunction)
-- 3 slot: Bronze Halo (drawId=1), Gold Halo (drawId=2), Diamond Halo (drawId=3)
-- ============================================================================
do
    -- ── Konstanta ──────────────────────────────────────────────────────────
    local HALO_NAMES   = { "Bronze Halo", "Gold Halo", "Diamond Halo" }
    local HALO_DRAW_ID = { 1, 2, 3 }

    -- ── State per slot ─────────────────────────────────────────────────────
    -- Semua state disimpan per-index (1=Bronze, 2=Gold, 3=Diamond)
    local _H = {
        running      = { false, false, false },
        attempt      = { 0, 0, 0 },
        threads      = { nil, nil, nil },
        needsRefresh = { false, false, false },
        -- UI refs (diisi saat Section dibuat)
        statusEls    = { nil, nil, nil },
        attemptEls   = { nil, nil, nil },
        toggleEls    = { nil, nil, nil }, -- ref Toggle WindUI per slot
    }

    -- ── UI Helper: Refresh satu slot (dipanggil dari Heartbeat) ────────────
    local function RefreshSlot(hi)
        if not _H.statusEls[hi] then return end
        local running = _H.running[hi]
        local att     = _H.attempt[hi]

        local statusTxt, attTxt
        if not running then
            statusTxt = "[.] Idle"
            attTxt    = "Attempt: -"
        else
            statusTxt = "[R] Rolling #" .. att .. "..."
            attTxt    = "Attempt: " .. att
        end

        pcall(function() _H.statusEls[hi]:SetDesc(statusTxt) end)
        pcall(function() _H.attemptEls[hi]:SetDesc(attTxt)   end)
    end

    -- ── Loop logic per slot (diport dari DoAutoRollHalo di 1.lua) ──────────
    local function StartHaloLoop(hi)
        -- Cancel thread lama kalau ada
        if _H.threads[hi] then
            task.cancel(_H.threads[hi])
            _H.threads[hi] = nil
        end

        if not _H.running[hi] then
            -- OFF: reset attempt display
            _H.attempt[hi]      = 0
            _H.needsRefresh[hi] = true
            return
        end

        local drawId = HALO_DRAW_ID[hi]

        _H.threads[hi] = task.spawn(function()
            while _H.running[hi] do
                _H.attempt[hi] = _H.attempt[hi] + 1
                _H.needsRefresh[hi] = true

                local ok = pcall(function()
                    -- RE.RerollHalo adalah RemoteFunction → InvokeServer(drawId)
                    if RE.RerollHalo then
                        RE.RerollHalo:InvokeServer(drawId)
                    end
                end)

                if not ok then
                    task.wait(1)
                else
                    task.wait(0.05)
                end
            end
            -- Loop selesai (di-toggle OFF dari dalam callback)
            _H.needsRefresh[hi] = true
        end)
    end

    -- ── Section ────────────────────────────────────────────────────────────
    local haloSection = RerollTab:Section({
        Title  = "Auto Gacha Halo",
        Icon   = "sparkles",
        Opened = false,
        Box    = true,
    })

    -- ── UI per slot Halo ──────────────────────────────────────────────────
    for hi = 1, 3 do
        local hi_l = hi

        -- Status paragraph (return 1 value langsung — CLAUDE.md §2 Pola Paragraph)
        _H.statusEls[hi] = haloSection:Paragraph({
            Title = HALO_NAMES[hi],
            Desc  = "[.] Idle",
        })

        -- Attempt paragraph
        _H.attemptEls[hi] = haloSection:Paragraph({
            Title = "Attempt " .. HALO_NAMES[hi],
            Desc  = "Attempt: -",
        })

        -- Toggle Enable (CLAUDE.md §5 Pola Toggle)
        _H.toggleEls[hi] = haloSection:Toggle({
            Flag     = "haloToggle" .. hi,
            Title    = "Auto Gacha " .. HALO_NAMES[hi],
            Desc     = "ON = START GACHA",
            Value    = false,
            Callback = function(on)
                _H.running[hi_l] = on
                if not on then
                    -- Stop loop
                    if _H.threads[hi_l] then
                        task.cancel(_H.threads[hi_l])
                        _H.threads[hi_l] = nil
                    end
                    _H.attempt[hi_l]      = 0
                    _H.needsRefresh[hi_l] = true
                else
                    -- Start loop
                    StartHaloLoop(hi_l)
                end
            end,
        })
    end

    -- ── Heartbeat poller (CLAUDE.md §3 — SetDesc tidak boleh dari spy/defer) ──
    -- Meski fitur ini tidak pakai spy, loop task.spawn juga butuh
    -- Heartbeat agar status update aman di main-thread context.
    RunService.Heartbeat:Connect(function()
        for hi = 1, 3 do
            if _H.needsRefresh[hi] then
                _H.needsRefresh[hi] = false
                RefreshSlot(hi)
            end
        end
    end)
end

-- ============================================================================
-- PANEL: REROLL TAB → AUTO ROLL ORNAMENT
-- Diconvert dari 1.lua: _ASH_ORN / _ASH_ORN.DoRoll (baris 3306) + PANEL (baris 8315)
-- Remote: RE.RerollOrnament:InvokeServer({machineId=..., isAuto=false})  (RemoteFunction)
-- 7 mesin: Headdress, Ornament Machine, Wealth Blessing, Shadowhunter,
--          Primordial Blessing, Monarch Power, Saiyan Blessing
-- Fitur: roll terus tanpa stop, parse ornamentId dari hasil, tampil "Last: <nama>"
-- TIDAK ada dropdown target (tidak pakai spy/GUID) — roll berjalan tanpa filter target.
-- ============================================================================
do
    -- ── Konstanta mesin (dari 1.lua baris 3308-3316) ──────────────────────
    local ORN_MACHINES = {
        { name = "Headdress",             machineId = 400001 },
        { name = "Ornament Machine",      machineId = 400002 },
        { name = "Wealth Blessing",       machineId = 400003 },
        { name = "Shadowhunter Blessing", machineId = 400004 },
        { name = "Primordial Blessing",   machineId = 400005 },
        { name = "Monarch Power",         machineId = 400006 },
        { name = "Saiyan Blessing",       machineId = 400007 },
    }
    local NM = #ORN_MACHINES  -- 7

    -- ── QUIRK_MAP: id → nama, diisi saat roll (diport dari _ASH_ORN.QUIRK_MAP) ──
    local ORN_QUIRK_MAP = {}

    local function OrnAddQuirk(id, name)
        if not id or not name then return end
        if not ORN_QUIRK_MAP[id] then
            ORN_QUIRK_MAP[id] = name
        elseif not ORN_QUIRK_MAP[id]:find("^ID:") then
            -- sudah punya nama asli, biarkan
        else
            ORN_QUIRK_MAP[id] = name
        end
    end

    -- ── State per mesin ────────────────────────────────────────────────────
    local _O = {
        running      = {},
        attempt      = {},
        threads      = {},
        needsRefresh = {},
        -- UI refs
        statusEls    = {},
        attemptEls   = {},
        lastEls      = {},
        toggleEls    = {},
    }
    for i = 1, NM do
        _O.running[i]      = false
        _O.attempt[i]      = 0
        _O.threads[i]      = nil
        _O.needsRefresh[i] = false
        _O.statusEls[i]    = nil
        _O.attemptEls[i]   = nil
        _O.lastEls[i]      = nil
        _O.toggleEls[i]    = nil
    end

    -- ── Parser ornamentId dari hasil InvokeServer (diport dari 1.lua baris 3586-3655) ──
    -- Kembalikan: gotId (number|nil), gotName (string)
    local function ParseOrnResult(res, mi)
        local gotId   = nil
        local gotName = ""
        if type(res) ~= "table" then return gotId, gotName end

        -- PRIORITY 1: res.ornamentIds = { [1]=410003, ... }
        if type(res.ornamentIds) == "table" then
            local oid = res.ornamentIds[1]
            if type(oid) == "number" and oid > 0 then
                gotId   = oid
                gotName = ORN_QUIRK_MAP[oid] or ("ID:"..tostring(oid))
                OrnAddQuirk(oid, gotName)
                return gotId, gotName
            end
        end

        -- PRIORITY 2: scan nested ornamentIds
        if not gotId then
            local function ScanOrnamentIds(tbl, depth)
                if depth > 4 or type(tbl) ~= "table" or gotId then return end
                if type(tbl.ornamentIds) == "table" then
                    local oid = tbl.ornamentIds[1]
                    if type(oid) == "number" and oid > 0 then
                        gotId   = oid
                        gotName = ORN_QUIRK_MAP[oid] or ("ID:"..tostring(oid))
                        OrnAddQuirk(oid, gotName)
                        return
                    end
                end
                for _, v in pairs(tbl) do
                    if type(v) == "table" then ScanOrnamentIds(v, depth + 1) end
                end
            end
            ScanOrnamentIds(res, 0)
        end

        -- PRIORITY 3: fallback scan quirkId / resultId / ornamentId + name
        if not gotId then
            local function ScanAndLearn(tbl, depth)
                if depth > 5 or type(tbl) ~= "table" or gotId then return end
                local id   = tbl.quirkId or tbl.finalResultId or tbl.resultId or tbl.ornamentId
                local name = tbl.quirkName or tbl.name or tbl.Name or tbl.title or tbl.displayName
                if type(id) == "number" and id > 0 then
                    if type(name) == "string" and #name > 0 and not name:find("^ID:") then
                        OrnAddQuirk(id, name)
                        if not gotId then gotId = id; gotName = name end
                    else
                        if not gotId then
                            gotId   = id
                            gotName = ORN_QUIRK_MAP[id] or ("ID:"..tostring(id))
                        end
                    end
                end
                for _, v in pairs(tbl) do
                    if type(v) == "table" then ScanAndLearn(v, depth + 1) end
                end
            end
            ScanAndLearn(res, 0)
        end

        -- PRIORITY 4: last resort — angka pertama dalam range 4xxxxx
        if not gotId then
            local function ScanNum(tbl, depth)
                if depth > 4 or gotId then return end
                for _, v in pairs(tbl) do
                    if type(v) == "number" and v >= 400000 and v < 500000 then
                        gotId   = v
                        gotName = ORN_QUIRK_MAP[v] or ("ID:"..tostring(v))
                        OrnAddQuirk(v, gotName)
                        return
                    elseif type(v) == "table" then
                        ScanNum(v, depth + 1)
                    end
                end
            end
            ScanNum(res, 0)
        end

        return gotId, gotName
    end

    -- ── UI refresh satu mesin (dipanggil dari Heartbeat saja) ─────────────
    -- Payload disimpan di _O.refreshPayload[mi] oleh loop thread
    local _refreshPayload = {}  -- [mi] = { status, attempt, last }
    for i = 1, NM do _refreshPayload[i] = nil end

    local function RefreshMachine(mi)
        local p = _refreshPayload[mi]
        if not p then return end
        _refreshPayload[mi] = nil
        if _O.statusEls[mi]  then pcall(function() _O.statusEls[mi]:SetDesc(p.status)   end) end
        if _O.attemptEls[mi] then pcall(function() _O.attemptEls[mi]:SetDesc(p.attempt) end) end
        if p.last ~= nil and _O.lastEls[mi] then
            pcall(function() _O.lastEls[mi]:SetDesc(p.last) end)
        end
    end

    local function PostRefresh(mi, status, attempt, last)
        _refreshPayload[mi] = { status = status, attempt = "Attempt: "..tostring(attempt), last = last }
        _O.needsRefresh[mi] = true
    end

    -- ── Loop logic per mesin (diport dari _ASH_ORN.DoRoll di 1.lua) ───────
    local function StartOrnLoop(mi)
        -- Cancel thread lama
        local loopKey = "ornroll" .. mi
        StopLoop(loopKey)
        if _O.threads[mi] then
            pcall(function() task.cancel(_O.threads[mi]) end)
            _O.threads[mi] = nil
        end

        if not _O.running[mi] then
            PostRefresh(mi, "[.] Idle", "-", "-")
            return
        end

        local mInfo = ORN_MACHINES[mi]

        _O.threads[mi] = task.spawn(function()
            local attempt = 0
            PostRefresh(mi, "[~] START...", 0, nil)

            while _O.running[mi] do
                repeat
                    -- Pastikan remote tersedia (lazy resolve jika nil awal)
                    if not RE.RerollOrnament then
                        RE.RerollOrnament = Remotes:FindFirstChild("RerollOrnament")
                    end
                    if not RE.RerollOrnament then
                        PostRefresh(mi, "[!] RerollOrnament NOT FOUND!", attempt, nil)
                        task.wait(2)
                        break
                    end

                    attempt = attempt + 1
                    PostRefresh(mi, "[~] Roll #" .. attempt, attempt, nil)

                    local ok, res = pcall(function()
                        return RE.RerollOrnament:InvokeServer({
                            machineId = mInfo.machineId,
                            isAuto    = false,
                        })
                    end)

                    if not ok then
                        PostRefresh(mi, "[!] Error (#" .. attempt .. ")", attempt, nil)
                        task.wait(0.5)
                        break
                    end

                    if res == false or res == nil then
                        task.wait(0.5)
                        break
                    end

                    local gotId, gotName = ParseOrnResult(res, mi)
                    local lastTxt = gotName ~= "" and ("Last: " .. gotName) or "Last: ?"
                    PostRefresh(mi, "[OK] Roll #" .. attempt .. " DONE", attempt, lastTxt)

                    task.wait(0.1)
                until true
            end

            PostRefresh(mi, "[.] STOPPED (" .. tostring(_O.attempt[mi]) .. "x roll)", _O.attempt[mi], nil)
        end)

        -- Simpan attempt ke state (untuk display saat stopped)
        task.spawn(function()
            while _O.threads[mi] do
                _O.attempt[mi] = _O.attempt[mi]  -- akan di-update via PostRefresh
                task.wait(0.5)
            end
        end)
    end

    -- ── Section ────────────────────────────────────────────────────────────
    local ornSection = RerollTab:Section({
        Title  = "Auto Roll Ornament",
        Icon   = "gem",
        Opened = false,
        Box    = true,
    })

    -- Info paragraph
    ornSection:Paragraph({
        Title = "Info",
        Desc  = "[i] Enable toggle mesin untuk start roll otomatis tanpa berhenti.",
    })

    -- ── UI per mesin (7 mesin) ─────────────────────────────────────────────
    for mi = 1, NM do
        local mi_l = mi

        -- Status paragraph
        _O.statusEls[mi] = ornSection:Paragraph({
            Title = ORN_MACHINES[mi].name,
            Desc  = "[.] Idle",
        })

        -- Attempt + Last paragraph
        _O.attemptEls[mi] = ornSection:Paragraph({
            Title = "Info " .. ORN_MACHINES[mi].name,
            Desc  = "Attempt: -  |  Last: -",
        })

        -- Toggle Fastroll per mesin
        _O.toggleEls[mi] = ornSection:Toggle({
            Flag     = "ornToggle" .. mi,
            Title    = "Fastroll " .. ORN_MACHINES[mi].name,
            Desc     = "ON = START REROLL",
            Value    = false,
            Callback = function(on)
                _O.running[mi_l] = on
                if not on then
                    -- Stop
                    if _O.threads[mi_l] then
                        pcall(function() task.cancel(_O.threads[mi_l]) end)
                        _O.threads[mi_l] = nil
                    end
                    _O.attempt[mi_l] = 0
                    PostRefresh(mi_l, "[.] Idle", "-", "-")
                else
                    -- Start
                    _O.attempt[mi_l] = 0
                    StartOrnLoop(mi_l)
                end
            end,
        })
    end

    -- ── Heartbeat poller ───────────────────────────────────────────────────
    -- SetDesc tidak boleh dari task.spawn thread (lacking capability Plugin).
    -- Loop hanya isi _refreshPayload + needsRefresh; Heartbeat yang eksekusi SetDesc.
    RunService.Heartbeat:Connect(function()
        for mi = 1, NM do
            if _O.needsRefresh[mi] then
                _O.needsRefresh[mi] = false
                RefreshMachine(mi)
            end
        end
    end)
end

-- ============================================================================
-- PANEL: SETTING TAB → GIFT CODE CLAIMER + SERVER TOOLS
-- Diconvert dari 1.lua: NewPanel("settings") (baris 19004)
-- Dependency baru yang di-declare di blok ini (belum ada di 2.lua):
--   FLa_GetRequest(), FLa_HttpGet(), GetCachedServerId()
--   RejoinServer(), ServerHop(), SmallServer()
-- ============================================================================

-- ── Helper: HTTP request function (adaptive semua executor) ─────────────────
-- Diport dari 1.lua baris 293
if not FLa_GetRequest then
    function FLa_GetRequest()
        local r = request or http_request or httprequest
        if r then return r end
        if syn    and type(syn.request)      == "function" then return syn.request      end
        if http   and type(http.request)     == "function" then return http.request     end
        if fluxus and type(fluxus.request)   == "function" then return fluxus.request   end
        if krnl   and type(krnl.request)     == "function" then return krnl.request     end
        if electron and type(electron.request) == "function" then return electron.request end
        if awp    and type(awp.request)      == "function" then return awp.request      end
        if comet  and type(comet.request)    == "function" then return comet.request    end
        if type(getgenv) == "function" then
            local ok, env = pcall(getgenv)
            if ok and env then
                r = env.request or env.http_request or env.httprequest
                if r then return r end
            end
        end
        return nil
    end
end

-- ── Helper: adaptive HTTP GET ────────────────────────────────────────────────
-- Diport dari 1.lua baris 320
if not FLa_HttpGet then
    function FLa_HttpGet(url)
        do
            local ok, result = pcall(function() return game:HttpGet(url) end)
            if ok and type(result) == "string" and #result > 0 then return result end
        end
        local reqF = FLa_GetRequest()
        if reqF then
            local ok, res = pcall(function()
                return reqF({ Url = url, Method = "GET" })
            end)
            if ok and res and type(res.Body) == "string" and #res.Body > 0 then
                return res.Body
            end
        end
        if syn and type(syn.request) == "function" then
            local ok, res = pcall(function()
                return syn.request({ Url = url, Method = "GET" })
            end)
            if ok and res and type(res.Body) == "string" then return res.Body end
        end
        return nil
    end
end

-- ── Helper: cached server ID ─────────────────────────────────────────────────
-- Diport dari 1.lua baris 432
if not GetCachedServerId then
    _CACHED_SERVER_ID = _CACHED_SERVER_ID or (function()
        -- PrivateServerId tidak bisa diakses dari client → pakai JobId saja
        local jobId = game.JobId ~= "" and game.JobId or nil
        if jobId then return jobId end
        return "N/A"
    end)()
    function GetCachedServerId()
        return _CACHED_SERVER_ID
    end
end

-- ── Server Tools functions ────────────────────────────────────────────────────
-- Diport dari 1.lua baris 3009
local _TS  = game:GetService("TeleportService")
local _HS  = game:GetService("HttpService")
local _PLR = game:GetService("Players")

local function RejoinServer()
    local lp = _PLR.LocalPlayer
    task.spawn(function()
        -- Deteksi private server: PrivateServerId terisi = private/reserved server
        -- TeleportToPlaceInstance ke private server butuh accessCode tidak bisa dari client
        local isPrivate = false
        pcall(function()
            isPrivate = game.PrivateServerId ~= nil and game.PrivateServerId ~= ""
        end)
        if isPrivate then
            warn("[REJOIN] Tidak support di Private Server. Jalankan di Public Server.")
            return
        end
        local ok = pcall(function()
            _TS:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp)
        end)
        if not ok then
            pcall(function() _TS:Teleport(game.PlaceId, lp) end)
        end
    end)
end

-- Diport dari 1.lua baris 3028
local function ServerHop()
    local lp = _PLR.LocalPlayer
    task.spawn(function()
        local ok = pcall(function()
            local url = "https://games.roblox.com/v1/games/"..tostring(game.PlaceId).."/servers/Public?sortOrder=Desc&limit=100"
            local raw = FLa_HttpGet(url)
            if not raw then error("HTTP tidak supported") end
            local data = _HS:JSONDecode(raw)
            if data and data.data then
                local avail = {}
                for _, v in ipairs(data.data) do
                    if type(v) == "table" and v.id ~= game.JobId and v.playing < v.maxPlayers then
                        table.insert(avail, v.id)
                    end
                end
                if #avail > 0 then
                    _TS:TeleportToPlaceInstance(game.PlaceId, avail[math.random(1, #avail)], lp)
                    return
                end
            end
            _TS:Teleport(game.PlaceId, lp)
        end)
        if not ok then
            pcall(function() _TS:Teleport(game.PlaceId, lp) end)
        end
    end)
end

-- Diport dari 1.lua baris 3059
local function SmallServer()
    local lp = _PLR.LocalPlayer
    task.spawn(function()
        local ok = pcall(function()
            local url = "https://games.roblox.com/v1/games/"..tostring(game.PlaceId).."/servers/Public?sortOrder=Asc&limit=100"
            local raw = FLa_HttpGet(url)
            if not raw then error("HTTP tidak supported") end
            local data = _HS:JSONDecode(raw)
            if data and data.data then
                for _, v in ipairs(data.data) do
                    if type(v) == "table" and v.id ~= game.JobId and v.playing < v.maxPlayers and v.playing > 0 then
                        _TS:TeleportToPlaceInstance(game.PlaceId, v.id, lp)
                        return
                    end
                end
            end
            _TS:Teleport(game.PlaceId, lp)
        end)
        if not ok then
            pcall(function() _TS:Teleport(game.PlaceId, lp) end)
        end
    end)
end

-- ============================================================================
-- SETTING TAB UI
-- ============================================================================
do
    -- ── GIFT CODE CLAIMER ───────────────────────────────────────────────────
    -- Tidak pakai Section expand. 1 tombol, fire semua kode 1-150 sekaligus
    -- (semua pcall di-spawn paralel, tidak berurutan/sequential).
    SettingTab:Button({
        Title    = "CLAIM GIFT CODE",
        Desc     = "Claim semua kode sekaligus",
        Callback = function()
            local gcRemote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
                and game:GetService("ReplicatedStorage").Remotes:FindFirstChild("GiftCodeReceived")
            if not gcRemote then return end
            -- Fire semua kode 1-150 paralel sekaligus
            for i = 1, 150 do
                task.spawn(function()
                    pcall(function() gcRemote:InvokeServer(i) end)
                end)
            end
        end,
    })

    -- ── SERVER TOOLS ────────────────────────────────────────────────────────
    -- Tidak pakai Section expand. 3 tombol langsung di tab.
    SettingTab:Button({
        Title    = "REJOIN SERVER",
        Desc     = "Masuk ulang ke server ID yang sama",
        Callback = function() RejoinServer() end,
    })

    SettingTab:Button({
        Title    = "SERVER HOP",
        Desc     = "Join server lain secara random / acak",
        Callback = function() ServerHop() end,
    })

    SettingTab:Button({
        Title    = "SMALL SERVER",
        Desc     = "Join server dengan player paling sedikit (Ascending)",
        Callback = function() SmallServer() end,
    })
end

-- ============================================================================
-- WEBHOOK SYSTEM - Bersih, akurat, executor-agnostic
-- Diport dari 1.lua baris 9368-9840 (do-block webhook + raid logic)
-- Kirim notif ke Discord saat Raid Normal atau Ascension Tower OPEN
-- ============================================================================

-- ── Global state declarations ──────────────────────────────────────────────
_webhookEnabled  = _webhookEnabled  or false
_webhookUrl      = _webhookUrl      or ""
_webhookUrlBox   = _webhookUrlBox   or nil   -- TextBox reference untuk restore text
_visWebhookToggle = _visWebhookToggle or nil  -- setter visual-only toggle (fn(bool))
_setWebhookToggle = _setWebhookToggle or nil  -- setter logic toggle (fn(bool))
_setWebhookUrlVis = _setWebhookUrlVis or nil  -- setter visual URL textbox (fn(string))
UpdatePlatformLbl = UpdatePlatformLbl or nil  -- fn() update label platform
FlushWebhookPending = FlushWebhookPending or nil -- fn() flush buffer webhook

do -- WEBHOOK SYSTEM wrapped do-block (free top-level locals)

-- Helper: dapatkan request function (support semua executor)
local function _getReqFunc()
    return FLa_GetRequest() -- [FLa COMPAT] adaptive semua executor
end

-- Helper: dapatkan string jam realtime (WIB UTC+7)
local function _getTimestamp()
    -- os.time() = Unix timestamp UTC
    -- Tambah 7 jam (25200 detik) untuk WIB
    local t = os.time() + 25200
    return os.date("!%d/%m/%Y %H:%M:%S WIB", t)
end

-- Helper: dapatkan baris "DisplayName (Username)" untuk footer webhook
-- Sama seperti info profil (avatar + nickname + username) yang tampil
-- di sidebar Window (User = {Enabled = true}). Contoh: "KINGRusdi (dlwmtbi_n22248)"
local function _getPlayerInfoLine()
    local dname = "?"
    local uname = "?"
    pcall(function()
        if LP then
            dname = LP.DisplayName or LP.Name or "?"
            uname = LP.Name or "?"
        end
    end)
    if dname ~= "" and dname ~= uname then
        return dname.." (".. uname ..")"
    end
    return uname
end

-- Helper: kirim HTTP POST ke Discord
-- return: true (sukses), false (gagal), string (error message)
local function _doSend(url, text)
    local reqFunc = _getReqFunc()
    if not reqFunc then
        pcall(function() warn("[ASH Webhook] ERROR: Executor tidak support HTTP request!") end)
        return false, "Executor tidak support HTTP"
    end
    local HS = game:GetService("HttpService")
    local ok, res, errMsg = false, nil, nil
    local callOk, callErr = pcall(function()
        res = reqFunc({
            Url     = url,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HS:JSONEncode({ content = text }),
        })
    end)
    if not callOk then
        errMsg = "HTTP error: "..(tostring(callErr):sub(1,60))
        pcall(function() warn("[ASH Webhook] "..errMsg) end)
        return false, errMsg
    end
    if res and type(res) == "table" then
        local sc = res.StatusCode or res.status or 0
        ok = (sc >= 200 and sc < 300)
        if not ok then
            errMsg = "HTTP "..sc..(res.Body and (" - "..tostring(res.Body):sub(1,40)) or "")
            pcall(function() warn("[ASH Webhook] Gagal: "..errMsg) end)
        end
    elseif res ~= nil then
        ok = true
    else
        errMsg = "Tidak ada response dari server"
        ok = false
    end
    return ok, errMsg
end

-- Buffer teks mentah dari TipsPanel, diisi ParseChatLine
local _whBuffer      = {}   -- list of raw lines dari event ini
local _whBufferTimer = nil  -- debounce handle
local _whLastSent    = 0

-- [BUG FIX 4 v2] Cache teks webhook dengan TTL timestamp.
-- Anti-spam: cegah teks sama dikirim dalam 1 window event (5 menit).
local _WH_SENT_TTL  = 300 -- 5 menit
local _whSentCache  = {} -- [text] = timestamp
local function _whResetSentCache()
    _whSentCache = {}
end
local function _whPruneSentCache()
    local now = tick()
    for k, t in pairs(_whSentCache) do
        if (now - t) >= _WH_SENT_TTL then
            _whSentCache[k] = nil
        end
    end
end
-- Auto-reset setiap 5 menit
task.spawn(function()
    while task.wait(_WH_SENT_TTL) do
        _whResetSentCache()
    end
end)

local GRADE_COLOR = {
    ["E"]=9868950,  ["D"]=6604900,  ["C"]=5294200,  ["B"]=6589695,
    ["A"]=11822335, ["S"]=16757810, ["SS"]=16768000, ["G"]=16742440,
    ["N"]=16732240, ["M"]=16727160, ["M+"]=14428340, ["M++"]=13115135,
    ["XM"]=16732360,["ULT"]=16766720,["GOD"]=16777215,
}
local GRADE_RANK_W = {
    ["E"]=1,["D"]=2,["C"]=3,["B"]=4,["A"]=5,["S"]=6,["SS"]=7,
    ["G"]=8,["N"]=9,["M"]=10,["M+"]=11,["M++"]=12,["XM"]=15,["ULT"]=17,["GOD"]=18,
}

-- Ambil grade dari bracket TERAKHIR dalam teks
local function _extractGradeLast(t)
    for _, pat in ipairs({"M%+%+","M%+","SS","XM","ULT","GOD","M"}) do
        if t:find("%["..pat.."]", 1, false) then
            local last = nil
            for m in t:gmatch("%["..pat.."]") do last = m end
            if last then return last:match("%[(.+)%]"):upper() end
        end
    end
    local last = nil
    for bracket in t:gmatch("%[([^%]]+)%]") do
        local up = bracket:upper()
        if up:match("^[EDCBAGSN]$") then last = up end
    end
    return last
end

-- Kirim buffer ke Discord, lalu kosongkan buffer
local _whFlushBuffer
_whFlushBuffer = function(url)
    if #_whBuffer == 0 then return end
    local lines  = _whBuffer
    _whBuffer    = {}
    _whLastSent  = tick()

    local reqFunc = _getReqFunc()
    if not reqFunc then return end
    local HS = game:GetService("HttpService")

    -- Grade helper: AT pakai isAscension=true, RAID pakai false
    local function _gradeFor(mapNum, isAscension)
        local g = GetBestGrade(mapNum, isAscension)
        if g and g ~= "?" then return g end
        if isAscension then
            return (_runeGradeCache and (_runeGradeCache[-mapNum] or _runeGradeCache[mapNum])) or "?"
        else
            return (_runeGradeCache and _runeGradeCache[mapNum]) or "?"
        end
    end

    -- Parse baris jadi entries
    local entries_normal, entries_at = {}, {}
    local topGrade = "E"

    for _, line in ipairs(lines) do
        local isAT = line:find("Ascension Tower", 1, true)
        if isAT then
            local towerNum = tonumber(line:match("Ascension Tower (%d+)"))
            local grade    = towerNum and _gradeFor(towerNum, true) or _extractGradeLast(line) or "?"
            if (GRADE_RANK_W[grade] or 0) > (GRADE_RANK_W[topGrade] or 0) then topGrade = grade end
            table.insert(entries_at, { mapNum = towerNum, grade = grade, raw = line })
        else
            local mapNum = tonumber(line:match("appeared in (%d+)"))
            local grade  = mapNum and _gradeFor(mapNum, false) or _extractGradeLast(line) or "?"
            if (GRADE_RANK_W[grade] or 0) > (GRADE_RANK_W[topGrade] or 0) then topGrade = grade end
            local mapName = (MAP_NAMES and mapNum and MAP_NAMES[mapNum]) or (mapNum and ("Map "..mapNum)) or "?"
            table.insert(entries_normal, { mapNum = mapNum, mapName = mapName, grade = grade, raw = line })
        end
    end

    local total = #entries_normal + #entries_at

    local fields = {}
    if #entries_normal > 0 then
        local valLines = {}
        for _, e in ipairs(entries_normal) do
            local gradeStr = e.grade ~= "?" and ("**["..e.grade.."**]") or "[?]"
            local mapStr   = e.mapNum and ("Map "..e.mapNum.." - "..e.mapName) or e.raw
            table.insert(valLines, gradeStr.." "..mapStr)
        end
        table.insert(fields, {
            name   = "Normal Raid ("..#entries_normal..")",
            value  = table.concat(valLines, "\n"),
            inline = false,
        })
    end
    if #entries_at > 0 then
        local valLines = {}
        for _, e in ipairs(entries_at) do
            local gradeStr = e.grade ~= "?" and ("**["..e.grade.."]**") or "[?]"
            local tStr     = e.mapNum and ("Tower "..e.mapNum) or "Tower ?"
            table.insert(valLines, gradeStr.." "..tStr)
        end
        table.insert(fields, {
            name   = "Ascension Tower ("..#entries_at..")",
            value  = table.concat(valLines, "\n"),
            inline = false,
        })
    end
    local color   = GRADE_COLOR[topGrade] or GRADE_COLOR["E"]
    local payload = {embeds = {{
        title       = "[RAID OPEN] Rank "..topGrade,
        description = "Total: **"..total.."** raid aktif",
        color       = color,
        fields      = fields,
        footer      = {text = "Server Id : "..GetCachedServerId().."\nPlayer : ".._getPlayerInfoLine().."\nSent at : ".._getTimestamp()},
    }}}
    pcall(function()
        reqFunc({
            Url     = url,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = HS:JSONEncode(payload),
        })
    end)
end

-- Dipanggil dari ParseChatLine setiap kali TipsPanel tangkap 1 baris raid/AT
_WH.AddLine = function(text)
    if not _webhookEnabled or not _webhookUrl or _webhookUrl == "" then return end
    if _whSilent then return end
    local _now = tick()
    if _whSentCache[text] and (_now - _whSentCache[text]) < _WH_SENT_TTL then return end
    for _, existing in ipairs(_whBuffer) do
        if existing == text then return end
    end
    _whSentCache[text] = _now
    local _cacheSize = 0
    for _ in pairs(_whSentCache) do _cacheSize = _cacheSize + 1 end
    if _cacheSize > 100 then _whPruneSentCache() end
    table.insert(_whBuffer, text)
    -- Reset debounce: tunggu 3 detik setelah baris terakhir baru kirim
    if _whBufferTimer then pcall(function() task.cancel(_whBufferTimer) end) end
    _whBufferTimer = task.delay(3, function()
        _whBufferTimer = nil
        -- Cooldown 10 detik antar pengiriman
        if (tick() - _whLastSent) < 10 then
            local sisa = 10 - (tick() - _whLastSent)
            _whBufferTimer = task.delay(sisa, function()
                _whBufferTimer = nil
                _whFlushBuffer(_webhookUrl)
            end)
            return
        end
        _whFlushBuffer(_webhookUrl)
    end)
end

-- Alias agar kode lain tidak error
_WH.SendRaid     = function(url) _whFlushBuffer(url) end
SendWebhookRaid  = function(url) _whFlushBuffer(url) end
-- [v52+] SIEGE webhook dihapus: hanya Raid Normal + Ascension Tower
_WH.SendSiege    = function() end
SendWebhookSiege = function() end

TriggerWebhookDebounce = function() end -- no-op, compat
SendWebhookNotif       = TriggerWebhookDebounce -- alias compat

-- FlushWebhookPending: reset cooldown dan flush buffer
FlushWebhookPending = function()
    _whLastSent = 0
    if _WH and _whFlushBuffer and _webhookUrl and _webhookUrl ~= "" then
        _whFlushBuffer(_webhookUrl)
    end
end

-- SendCustomMessage: kirim pesan custom ke Discord webhook
_WH.SendCustomMessage = function(url, msg, onDone, onFail)
    if not url or url == "" then
        if onFail then onFail("URL kosong") end; return
    end
    if not url:find("discord%.com/api/webhooks") then
        if onFail then onFail("URL tidak dikenali (bukan Discord webhook)") end; return
    end
    if not _getReqFunc() then
        if onFail then onFail("Executor tidak support HTTP") end; return
    end
    task.spawn(function()
        local ok, errMsg = _doSend(url, msg)
        task.wait(0.3)
        if ok then
            if onDone then onDone() end
        else
            local reason = errMsg or "Gagal kirim"
            if onFail then onFail(reason) end
        end
    end)
end

-- SendTestEmbed: kirim embed test (format sama persis notif raid) ke Discord
_WH.SendTestEmbed = function(url, onDone, onFail)
    if not url or url == "" then
        if onFail then onFail("URL kosong") end; return
    end
    if not url:find("discord%.com/api/webhooks") then
        if onFail then onFail("URL tidak dikenali (bukan Discord webhook)") end; return
    end
    local reqFunc = _getReqFunc()
    if not reqFunc then
        if onFail then onFail("Executor tidak support HTTP") end; return
    end
    task.spawn(function()
        local HS = game:GetService("HttpService")
        local payload = {embeds = {{
            title       = "Test Succes",
            description = "Webhook aktif dan siap menerima notifikasi Raid !",
            color       = GRADE_COLOR["S"] or 16757810,
            fields      = {},
            footer      = {text = "Server Id : "..GetCachedServerId().."\nPlayer : ".._getPlayerInfoLine().."\nSent at : ".._getTimestamp()},
        }}}
        local callOk, callErr = pcall(function()
            reqFunc({
                Url     = url,
                Method  = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body    = HS:JSONEncode(payload),
            })
        end)
        task.wait(0.3)
        if callOk then
            if onDone then onDone() end
        else
            if onFail then onFail(tostring(callErr):sub(1,60)) end
        end
    end)
end

-- VerifyWebhookUrl: validasi format Discord webhook URL
_WH.VerifyWebhookUrl = function(url, onValid, onInvalid)
    if not url or url == "" then
        if onInvalid then onInvalid("URL kosong") end; return
    end
    if not url:find("discord%.com/api/webhooks/") then
        if onInvalid then onInvalid("Bukan URL Discord webhook valid") end; return
    end
    local id, token = url:match("webhooks/(%d+)/([%w_%-]+)")
    if id and token and #token > 10 then
        if onValid then onValid() end
    else
        if onInvalid then onInvalid("Format Discord webhook salah") end
    end
end

end -- end do WEBHOOK SYSTEM

-- ============================================================================
-- WEBHOOK TAB UI
-- Diconvert dari 1.lua: NewPanel("webhook") (baris 19113)
-- Ditulis ulang pakai WindUI native API
-- Notif: Raid Normal + Ascension Tower, Discord only
-- ============================================================================
do
    -- ── SECTION: Raid Notif/Webhook ─────────────────────────────────────────
    WebhookTab:Section({ Title = "Raid Notif / Webhook", Icon = "bell" })

    -- ── URL Input ──────────────────────────────────────────────────────────
    local _urlInputElement = WebhookTab:Input({
        Flag        = "webhookUrl",
        Title       = "URL Webhook",
        Desc        = "Paste Discord webhook URL kamu di sini",
        Placeholder = "PASTE YOUR DISCORD WEBHOOK URL HERE...",
        Value       = _webhookUrl,
        Callback    = function(val)
            _webhookUrl = (val or ""):match("^%s*(.-)%s*$") or ""
            if UpdatePlatformLbl then UpdatePlatformLbl() end
        end,
    })
    -- Expose setter untuk Config restore (update visual textbox)
    _setWebhookUrlVis = function(url)
        _webhookUrl = (url or ""):match("^%s*(.-)%s*$") or ""
        if _urlInputElement then
            pcall(function() _urlInputElement:Set(_webhookUrl) end)
        end
        if UpdatePlatformLbl then pcall(UpdatePlatformLbl) end
    end

    -- ── Platform detect Paragraph ──────────────────────────────────────────
    local _platformParagraph = WebhookTab:Paragraph({
        Title = "Platform",
        Desc  = "Content URL",
    })

    UpdatePlatformLbl = function()
        if not _platformParagraph then return end
        local url = _webhookUrl or ""
        local desc
        if url:find("discord%.com/api/webhooks") then
            desc = "[OK] Discord webhook DETECTED"
        elseif url == "" then
            desc = "Content URL"
        else
            desc = "URL not recognized (bukan Discord webhook)"
        end
        pcall(function() _platformParagraph:SetDesc(desc) end)
    end
    UpdatePlatformLbl()

    -- ── Toggle: ACTIVE Webhook ─────────────────────────────────────────────
    -- Saat di-ON: webhook langsung aktif & mulai kirim notif Raid Normal + ASC
    local _webhookToggleElement = WebhookTab:Toggle({
        Flag     = "webhookEnabled",
        Title    = "ACTIVE Webhook",
        Desc     = "Aktifkan notifikasi Raid Normal & Ascension Tower ke Discord",
        Value    = _webhookEnabled,
        Callback = function(on)
            if on then
                _webhookUrl = (_webhookUrl or ""):match("^%s*(.-)%s*$") or ""
                if _webhookUrl == "" or not _webhookUrl:find("discord%.com/api/webhooks") then
                    _webhookEnabled = false
                    if _webhookToggleElement then
                        pcall(function() _webhookToggleElement:Set(false, false) end)
                    end
                    pcall(function() warn("[ASH Webhook] Isi URL Discord webhook dulu sebelum mengaktifkan!") end)
                    if UpdatePlatformLbl then UpdatePlatformLbl() end
                    return
                end
            end
            _webhookEnabled = on
            if UpdatePlatformLbl then UpdatePlatformLbl() end
            if on then
                if FlushWebhookPending then task.spawn(FlushWebhookPending) end
            end
        end,
    })

    -- Expose setter visual-only dan setter logic ke global
    _visWebhookToggle = function(v)
        if _webhookToggleElement then
            pcall(function() _webhookToggleElement:Set(v, false) end)
        end
    end
    _setWebhookToggle = function(v)
        if v == _webhookEnabled then return end
        _webhookEnabled = v
        if _webhookToggleElement then
            pcall(function() _webhookToggleElement:Set(v) end)
        end
    end

    -- ── Button: Test Webhook ───────────────────────────────────────────────
    -- Kirim embed test (format sama persis notif raid) ke Discord webhook
    WebhookTab:Button({
        Title    = "Test Webhook",
        Desc     = "Kirim embed uji coba ke Discord webhook URL yang diisi",
        Callback = function()
            _webhookUrl = (_webhookUrl or ""):match("^%s*(.-)%s*$") or ""
            if UpdatePlatformLbl then UpdatePlatformLbl() end
            local _done = false
            task.delay(10, function()
                if not _done then
                    _done = true
                    pcall(function() warn("[ASH Webhook] Test: Timeout/No HTTP") end)
                end
            end)
            _WH.SendTestEmbed(_webhookUrl,
                function()
                    if _done then return end; _done = true
                    pcall(function() warn("[ASH Webhook] Test: [OK] Sent!") end)
                end,
                function(err)
                    if _done then return end; _done = true
                    pcall(function() warn("[ASH Webhook] Test: "..tostring(err)) end)
                end
            )
        end,
    })

end -- end do WEBHOOK TAB UI

-- ============================================================================
-- PANEL: CONFIG
-- Diconvert dari 1.lua: PANEL CONFIG (baris 20199-21362)
-- Ditulis ulang pakai WindUI native API (ConfigTab:Section/Paragraph/Button)
-- Karena WindUI tidak punya TextBox native yang bisa di-embed bebas,
-- UI sub-panel (save/load/delete) dibangun via Frame + Instance Roblox biasa
-- yang di-parent ke dalam sebuah WindUI "host frame" via ConfigTab:Custom()
-- atau diletakkan langsung di bawah ConfigTab's ScrollingFrame via Parent inject.
-- ============================================================================
do

    -- ─── CONFIG FILE PATH ────────────────────────────────────────────────────
    local CONFIG_FOLDER = "FLaConfigs"

    -- Helper: pastikan folder ada (aman di semua executor via polyfill)
    local function _ensureFolder()
        local ok, exists = pcall(isfolder, CONFIG_FOLDER)
        if not ok or not exists then
            pcall(makefolder, CONFIG_FOLDER)
        end
    end

    local function _cfgPath(name)
        return CONFIG_FOLDER .. "/" .. name .. ".json"
    end

    local function ListConfigs()
        _ensureFolder()
        local ok, files = pcall(listfiles, CONFIG_FOLDER)
        if not ok or type(files) ~= "table" then return {} end
        local names = {}
        for _, f in ipairs(files) do
            local n = tostring(f):match("([^/\\]+)%.json$")
            if n and n ~= "" then table.insert(names, n) end
        end
        table.sort(names)
        return names
    end

    -- ─── JSON ENCODE / DECODE MINIMAL (Luau tanpa loadstring) ────────────────
    local function jsonEncode(t, indent)
        indent = indent or 0
        local pad  = string.rep(" ", indent)
        local padI = string.rep(" ", indent + 2)
        if type(t) == "boolean" then return t and "true" or "false" end
        if type(t) == "number"  then return tostring(t) end
        if type(t) == "string"  then
            local s = t:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n"):gsub("\r","\\r")
            return '"' .. s .. '"'
        end
        if type(t) ~= "table" then return '"[unsupported]"' end
        local isArr = true; local n = 0
        for k in pairs(t) do n = n + 1; if type(k) ~= "number" then isArr = false; break end end
        if isArr and n == 0 then return "[]" end
        if isArr then
            local parts = {}
            for i = 1, #t do parts[i] = padI .. jsonEncode(t[i], indent + 2) end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        else
            local parts = {}
            for k, v in pairs(t) do
                if type(k) == "string" or type(k) == "number" then
                    table.insert(parts, padI .. '"' .. tostring(k) .. '": ' .. jsonEncode(v, indent + 2))
                end
            end
            table.sort(parts)
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        end
    end

    local function jsonDecodeVal(s, pos)
        while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
        local c = s:sub(pos, pos)
        if c == '"' then
            local i = pos + 1; local res = {}
            while i <= #s do
                local ch = s:sub(i, i)
                if ch == '"' then return table.concat(res), i + 1 end
                if ch == '\\' then
                    local nx = s:sub(i + 1, i + 1)
                    if     nx == '"'  then table.insert(res, '"')
                    elseif nx == '\\' then table.insert(res, '\\')
                    elseif nx == 'n'  then table.insert(res, '\n')
                    elseif nx == 'r'  then table.insert(res, '\r')
                    else                   table.insert(res, nx) end
                    i = i + 2
                else
                    table.insert(res, ch); i = i + 1
                end
            end
            return "", pos
        end
        if c == '{' then
            local obj = {}; pos = pos + 1
            while pos <= #s do
                while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
                if s:sub(pos, pos) == '}' then return obj, pos + 1 end
                if s:sub(pos, pos) == ',' then pos = pos + 1 end
                while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
                local key, p2 = jsonDecodeVal(s, pos); pos = p2
                while pos <= #s and s:sub(pos, pos):match("[%s:]") do pos = pos + 1 end
                local val, p3 = jsonDecodeVal(s, pos); pos = p3
                obj[key] = val
            end
            return obj, pos
        end
        if c == '[' then
            local arr = {}; pos = pos + 1
            while pos <= #s do
                while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
                if s:sub(pos, pos) == ']' then return arr, pos + 1 end
                if s:sub(pos, pos) == ',' then pos = pos + 1 end
                local val, p2 = jsonDecodeVal(s, pos); pos = p2
                table.insert(arr, val)
            end
            return arr, pos
        end
        if s:sub(pos, pos + 3) == "true"  then return true,  pos + 4 end
        if s:sub(pos, pos + 4) == "false" then return false, pos + 5 end
        if s:sub(pos, pos + 3) == "null"  then return nil,   pos + 4 end
        local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
        if num then return tonumber(num), pos + #num end
        return nil, pos + 1
    end

    local function jsonDecode(s)
        local ok, val = pcall(function()
            local v, _ = jsonDecodeVal(s, 1)
            return v
        end)
        if ok then return val else return nil end
    end

    -- ─── COLLECT CONFIG STATE (snapshot semua state aktif saat ini) ──────────
    local function CollectConfig()
        local cfg = {}

        -- ── MAIN TAB ──────────────────────────────────────────────────────
        cfg.sellHeroOn        = _autoSellOnState or false
        cfg.autoCollectOn     = _autoCollectState or false
        cfg.sellWeaponOn      = _autoSellWeaponState or false
        cfg.swSelectAll       = _swSelectAllRef and _swSelectAllRef() or true
        cfg.swSelectedIds     = {}
        cfg.swSelNames        = {}
        if _swSelectedIdsGlobal then
            for k, v in pairs(_swSelectedIdsGlobal) do if v then cfg.swSelectedIds[tostring(k)] = true end end
        end
        if _swSelNamesGlobal then
            for k, v in pairs(_swSelNamesGlobal) do cfg.swSelNames[tostring(k)] = v end
        end
        cfg.decompGemOn       = _autoDecompGemState or false
        cfg.gemMinLevel       = _gemMinLevelState or 1
        cfg.gemMaxLevel       = _gemMaxLevelState or 1

        -- ── HIDE TAB ──────────────────────────────────────────────────────
        cfg.hideRerollChat    = _hideRerollChatState or false
        cfg.hideAllUI         = _hideAllUIState or false
        cfg.hideAllAnim       = _hideAllAnimState or false

        -- ── FARM TAB ──────────────────────────────────────────────────────
        cfg.randomAttackOn    = _raRunningState or false

        -- ── ATTACK TAB ────────────────────────────────────────────────────
        cfg.hideReward        = _hideRewardState or false
        cfg.massAttackOn      = MA and MA.running or false
        cfg.killDDIdx         = _killDDIdxState or 1
        cfg.delayDDIdx        = _delayDDIdxState or 2
        cfg.maMapSel          = {}
        if _maMapSelState then
            for k, v in pairs(_maMapSelState) do if v then cfg.maMapSel[tostring(k)] = true end end
        end
        cfg.skillZ = SKL and SKL.Z and SKL.Z.on or false
        cfg.skillX = SKL and SKL.X and SKL.X.on or false
        cfg.skillC = SKL and SKL.C and SKL.C.on or false
        cfg.skillV = SKL and SKL.V and SKL.V.on or false
        cfg.skillF = SKL and SKL.F and SKL.F.on or false

        -- ── PLAYER TAB ────────────────────────────────────────────────────
        cfg.noClipOn      = _noClipState or false
        cfg.antiAfkOn     = _antiIdleState or false
        cfg.walkSpeed     = _walkSpeedState or 16

        -- ── AUTOMATION TAB ────────────────────────────────────────────────
        cfg.raidOn        = _raidOn or false
        cfg.raidPMIdx     = 1
        cfg.raidPreferMaps  = {}
        cfg.raidRuneGrades  = {}
        cfg.raidRuneEnabled   = RAID and RAID.runeEnabled or false
        cfg.raidUpdownEnabled = RAID and RAID.updownEnabled or false
        cfg.raidUpdownDir     = RAID and RAID.updownDir or "up"
        cfg.raidUpdownTargetGrade = RAID and RAID.updownTargetGrade or nil
        cfg.raidRuneMapTarget = RAID and RAID.runeMapTarget or 0
        cfg.raidListEnabled   = RAID and RAID.listEnabled or false
        cfg.raidAutoKillBoss  = RAID and RAID.autoKillBoss or false
        cfg.raidBossDelay     = RAID and RAID.bossDelay or 3
        cfg.raidListEntries   = {}
        if RAID and RAID.listEntries then
            for i, ent in ipairs(RAID.listEntries) do
                local saveMaps = {}; local saveRanks = {}
                if ent.maps  then for mn, v in pairs(ent.maps)  do if v then saveMaps[tostring(mn)] = true end end end
                if ent.ranks then for g,  v in pairs(ent.ranks) do if v then saveRanks[g] = true end end end
                cfg.raidListEntries[i] = { maps = saveMaps, ranks = saveRanks }
            end
        end
        if RAID and RAID.preferMaps then
            for k, v in pairs(RAID.preferMaps) do if v then cfg.raidPreferMaps[tostring(k)] = true end end
        end
        if RAID and RAID.runeGrades then
            for k, v in pairs(RAID.runeGrades) do if v then cfg.raidRuneGrades[tostring(k)] = true end end
        end
        pcall(function()
            local PM_KEYS = {"default","byrank","bymap","hard","easy","manual"}
            for i, k in ipairs(PM_KEYS) do if RAID and k == RAID.pickMode then cfg.raidPMIdx = i; break end end
        end)

        cfg.ascOn        = _ascOn or false
        cfg.ascPMIdx     = 1
        cfg.ascPreferMaps= {}
        cfg.ascRuneGrades= {}
        cfg.ascRuneEnabled    = ASC and ASC.runeEnabled or false
        cfg.ascRuneMapTarget  = ASC and ASC.runeMapTarget or 0
        cfg.ascPreferMapTarget= ASC and ASC.preferMapTarget or 0
        cfg.ascAutoKillBoss   = ASC and ASC.autoKillBoss or false
        cfg.ascBossDelay      = ASC and ASC.bossDelay or 3
        if ASC and ASC.preferMaps then
            for k, v in pairs(ASC.preferMaps) do if v then cfg.ascPreferMaps[tostring(k)] = true end end
        end
        if ASC and ASC.runeGrades then
            for k, v in pairs(ASC.runeGrades) do if v then cfg.ascRuneGrades[tostring(k)] = true end end
        end
        pcall(function()
            local APM_KEYS = {"default","byrank","bymap","hard","easy","manual"}
            for i, k in ipairs(APM_KEYS) do if ASC and k == ASC.pickMode then cfg.ascPMIdx = i; break end end
        end)
        cfg.ascListEnabled = ASC and ASC.listEnabled or false
        cfg.ascListEntries = {}
        if ASC and ASC.listEntries then
            for i, ent in ipairs(ASC.listEntries) do
                local saveMaps = {}; local saveRanks = {}
                for k, v in pairs(ent.maps)  do if v then saveMaps[tostring(k)] = true end end
                for k, v in pairs(ent.ranks) do if v then saveRanks[tostring(k)] = true end end
                cfg.ascListEntries[i] = { maps = saveMaps, ranks = saveRanks }
            end
        end

        cfg.siegeOn      = _siegeToggleState or false
        cfg.siegeExclude = {}
        if SIEGE and SIEGE.excludeMaps then
            for k, v in pairs(SIEGE.excludeMaps) do cfg.siegeExclude[tostring(k)] = v end
        end

        cfg.dungeonOn    = _dungeonToggleState or false

        cfg.st2On        = ST2 and ST2.enabled or false
        cfg.st2AttackOn  = ST2 and ST2.attackEnabled or false
        cfg.st2WaveCount = ST2 and ST2.waveCount or 0

        -- ── REROLL TAB ────────────────────────────────────────────────────
        -- Hero Fastroll
        cfg.heroRollOn   = _HR_RPT and _HR_RPT.running or false
        cfg.heroX100On   = _HR_RPT and _HR_RPT.x100 or false
        cfg.heroSlotTarget = {{},{},{}}
        if _HR_RPT and _HR_RPT.slotTarget then
            for si = 1, 3 do
                for qid, v in pairs(_HR_RPT.slotTarget[si]) do
                    if v then cfg.heroSlotTarget[si][tostring(qid)] = true end
                end
            end
        end
        -- Weapon Fastroll
        cfg.weaponRollOn = _WR_RPT and _WR_RPT.running or false
        cfg.weaponX100On = _WR_RPT and _WR_RPT.x100 or false
        cfg.weaponSlotTarget = {{},{},{}}
        if _WR_RPT and _WR_RPT.slotTarget then
            for si = 1, 3 do
                for qid, v in pairs(_WR_RPT.slotTarget[si]) do
                    if v then cfg.weaponSlotTarget[si][tostring(qid)] = true end
                end
            end
        end
        -- PetGear
        cfg.pgrOn      = {false, false, false}
        cfg.pgr100On   = {false, false, false}
        cfg.pgrTargets = {{},{},{}}
        if PGR then
            for i = 1, 3 do
                cfg.pgrOn[i]  = PGR.enOnFlags[i] or false
                cfg.pgr100On[i] = PGR100 and PGR100.enOnFlags[i] or false
                for gid, v in pairs(PGR.targets[i]) do
                    if v then cfg.pgrTargets[i][tostring(gid)] = true end
                end
            end
        end
        -- Halo
        cfg.haloOn = {false, false, false}
        if HALO then
            for i = 1, 3 do cfg.haloOn[i] = HALO.enOnFlags[i] or false end
        end
        -- Ornament
        cfg.ornOn      = {}
        cfg.ornTargets = {}
        if ORN then
            local nm = #_ASH_ORN.MACHINES
            for i = 1, nm do
                cfg.ornOn[i]      = ORN.enOnFlags[i] or false
                cfg.ornTargets[i] = {}
                for qid, v in pairs(ORN.targets[i]) do
                    if v then cfg.ornTargets[i][tostring(qid)] = true end
                end
            end
        end
        -- Merge & Use Potion
        cfg.mergeOn = _mergeRunningState or false
        cfg.useOn   = _useRunningState or false

        -- ── SETTINGS / WEBHOOK TAB ────────────────────────────────────────
        cfg.webhookEnabled  = _webhookEnabled or false
        cfg.webhookUrl      = _webhookUrl or ""
        cfg.webhookMode     = _webhookMode or "both"
        cfg.webhookModeIdx  = 3
        pcall(function()
            local MODE_KEYS = {"raid","siege","both"}
            for i, k in ipairs(MODE_KEYS) do
                if k == (_webhookMode or "both") then cfg.webhookModeIdx = i; break end
            end
        end)

        -- ── THEME ─────────────────────────────────────────────────────────
        cfg.themeTransparency = _G.ThemeTransparency or 50   -- default 50
        cfg.themeName         = _G.CurrentTheme or "Dark"

        return cfg
    end

    -- ─── SAVE CONFIG ─────────────────────────────────────────────────────────
    local function SaveConfigAs(name)
        _ensureFolder()
        local ok, err = pcall(function()
            local cfg = CollectConfig()
            writefile(_cfgPath(name), jsonEncode(cfg))
        end)
        return ok, err
    end

    -- ─── APPLY CONFIG (restore semua state + visual) ─────────────────────────
    local function ApplyConfig(cfg)
        if type(cfg) ~= "table" then return false end

        -- ── ATURAN PANGGILAN ──────────────────────────────────────────────
        -- Setiap setter (_setXxx) sudah memanggil:
        --   1. logika backend (start/stop loop, flag)
        --   2. el:Set(v)  →  trigger Callback WindUI + sync visual
        -- _visXxx TIDAK dipanggil lagi untuk toggle yang setter-nya sudah
        -- lengkap — agar tidak double-fire callback + logika.
        -- _visXxx hanya dipakai di tempat yang MEMANG butuh visual-only
        -- (label refresh, sub-toggle updown/boss, dll).
        -- -----------------------------------------------------------------

        -- ── MAIN TAB ──────────────────────────────────────────────────────
        pcall(function()
            -- setter panggil el:Set(v) -> callback -> logika+visual ✓
            if _setSellHeroToggle    then _setSellHeroToggle(cfg.sellHeroOn == true) end
            if _setAutoCollectToggle then _setAutoCollectToggle(cfg.autoCollectOn == true) end
            if _swRestoreFromConfig then
                local isAll = cfg.swSelectAll ~= false
                _swRestoreFromConfig(isAll, cfg.swSelectedIds, cfg.swSelNames)
            end
            if _autoSellWeaponSet then _autoSellWeaponSet(cfg.sellWeaponOn == true) end
            -- internal guard (v==state), el:Set(v) ✓
            if _autoDecompGemSet then _autoDecompGemSet(cfg.decompGemOn == true) end
            if _setGemLevelRange and cfg.gemMinLevel and cfg.gemMaxLevel then
                _setGemLevelRange(cfg.gemMinLevel, cfg.gemMaxLevel)
            end
        end)

        -- ── HIDE TAB ──────────────────────────────────────────────────────
        -- Delay 0.3s agar PlayerGui sudah stabil sebelum hook dipasang
        task.delay(0.3, function()
            pcall(function()
                -- ApplyHideReroll(v) + _hrcrToggle:Set(v) — tidak perlu _vis* ✓
                if _setHideRerollChat then _setHideRerollChat(cfg.hideRerollChat == true) end
            end)
            pcall(function()
                if _setHideAllUI   then _setHideAllUI(cfg.hideAllUI == true) end
            end)
            pcall(function()
                if _setHideAllAnim then _setHideAllAnim(cfg.hideAllAnim == true) end
            end)
        end)

        -- ── FARM TAB ──────────────────────────────────────────────────────
        pcall(function()
            -- flag + el:Set(v) ✓
            if _setRAToggle then _setRAToggle(cfg.randomAttackOn == true) end
        end)

        -- ── ATTACK TAB ────────────────────────────────────────────────────
        pcall(function()
            -- Restore data map selection ke mapSelSet dan MR.selected
            if _maMapSelState and cfg.maMapSel then
                for k in pairs(_maMapSelState) do _maMapSelState[k] = nil end
                if MR and MR.selected then for k in pairs(MR.selected) do MR.selected[k] = nil end end
                for k, v in pairs(cfg.maMapSel) do
                    local n = tonumber(k)
                    if n then
                        _maMapSelState[n] = true
                        if MR then MR.selected[n] = true end
                    end
                end
                -- [FIX] _maMapItemRefs kosong di 2.lua (legacy 1.lua) — skip blok itu.
                -- _maUpdateMapDDLbl pakai mapDD:Select() yang butuh frame baru → task.defer
                task.defer(function()
                    if _maUpdateMapDDLbl then pcall(_maUpdateMapDDLbl) end
                end)
            end
            -- Kill/Delay dropdown ✓
            task.delay(0.1, function()
                pcall(function() if _setKillDDGlobal  and cfg.killDDIdx  then _setKillDDGlobal(cfg.killDDIdx)   end end)
                pcall(function() if _setDelayDDGlobal and cfg.delayDDIdx then _setDelayDDGlobal(cfg.delayDDIdx) end end)
            end)
            -- Skill Z/X/C/V/F: logika via SkOn/Off, visual via _setSkillToggleVis
            for _, n in ipairs({"Z","X","C","V","F"}) do
                local key   = "skill" .. n
                local wantOn = cfg[key] == true
                if wantOn and not SKL[n].on then
                    SkOn(n)
                elseif not wantOn and SKL[n].on then
                    SkOff(n)
                end
                if _setSkillToggleVis then
                    pcall(function() _setSkillToggleVis(n, wantOn) end)
                end
            end
            -- Hide Reward + Mass Attack setelah map applied
            task.delay(0.5, function()
                -- ApplyHideReward + el:Set(v) — tidak perlu _vis* ✓
                if _setHideReward     then _setHideReward(cfg.hideReward == true) end
                if _setMaToggleGlobal then _setMaToggleGlobal(cfg.massAttackOn == true) end
            end)
        end)

        -- ── PLAYER TAB ────────────────────────────────────────────────────
        pcall(function()
            -- flag + el:Set(v) — tidak perlu _vis* ✓
            if _setNoClipToggle  then _setNoClipToggle(cfg.noClipOn == true) end
            if _setAntiAfkToggle then _setAntiAfkToggle(cfg.antiAfkOn == true) end
            if _setSpeedSlider and cfg.walkSpeed then _setSpeedSlider(cfg.walkSpeed) end
        end)

        -- ── AUTOMATION: RAID ──────────────────────────────────────────────
        pcall(function()
            -- Tulis state data dulu SEBELUM visual/logika
            if cfg.raidPMIdx then
                local PM_KEYS = {"default","byrank","bymap","hard","easy","manual"}
                local ii = math.clamp(cfg.raidPMIdx, 1, #PM_KEYS)
                RAID.pickMode = PM_KEYS[ii]
                local PM_TO_DIFF = {default="easy",byrank="easy",bymap="easy",hard="hard",easy="easy",manual="easy"}
                RAID.difficulty = PM_TO_DIFF[PM_KEYS[ii]] or "easy"
                RAID.snapshotMapId = nil
            end
            if RAID.preferMaps and cfg.raidPreferMaps then
                for k in pairs(RAID.preferMaps) do RAID.preferMaps[k] = nil end
                for k, v in pairs(cfg.raidPreferMaps) do
                    local n = tonumber(k); if n then RAID.preferMaps[n] = true end
                end
            end
            if RAID.runeGrades and cfg.raidRuneGrades then
                for k in pairs(RAID.runeGrades) do RAID.runeGrades[k] = nil end
                for k, v in pairs(cfg.raidRuneGrades) do RAID.runeGrades[k] = true end
            end
            RAID.runeEnabled   = cfg.raidRuneEnabled   == true
            RAID.updownEnabled = cfg.raidUpdownEnabled  == true
            RAID.updownDir     = cfg.raidUpdownDir or "up"
            RAID.runeMapTarget = cfg.raidRuneMapTarget or 0

            task.delay(0.05, function()
                pcall(function()
                    if _raidUpdatePrefLabel then _raidUpdatePrefLabel() end
                    if _raidUpdateRankLabel then _raidUpdateRankLabel() end
                    if _setRaidPMIdx and cfg.raidPMIdx then _setRaidPMIdx(cfg.raidPMIdx) end
                    -- Re-restore: ApplyPickModeLock bisa clear data di atas
                    if RAID.preferMaps and cfg.raidPreferMaps then
                        for k in pairs(RAID.preferMaps) do RAID.preferMaps[k] = nil end
                        for k, v in pairs(cfg.raidPreferMaps) do
                            local n = tonumber(k); if n then RAID.preferMaps[n] = true end
                        end
                    end
                    if RAID.runeGrades and cfg.raidRuneGrades then
                        for k in pairs(RAID.runeGrades) do RAID.runeGrades[k] = nil end
                        for k, v in pairs(cfg.raidRuneGrades) do RAID.runeGrades[k] = true end
                    end
                    if _raidUpdatePrefLabel then _raidUpdatePrefLabel() end
                    if _raidUpdateRankLabel then _raidUpdateRankLabel() end
                end)
                pcall(function()
                    if _setRaidUpdownGrade    then _setRaidUpdownGrade(cfg.raidUpdownTargetGrade or nil) end
                    if _raidUpdownToggleVis   then _raidUpdownToggleVis(cfg.raidUpdownEnabled == true) end
                    if _raidUpdownDirVis      then _raidUpdownDirVis(cfg.raidUpdownDir or "up") end
                    if _setRaidRuneMapTarget  then _setRaidRuneMapTarget(cfg.raidRuneMapTarget or 0) end
                    if _raidBossToggleVis     then _raidBossToggleVis(cfg.raidAutoKillBoss == true) end
                    if _raidBossDelaySet      then _raidBossDelaySet(cfg.raidBossDelay or 3) end
                    if _setRaidListEnabledVis then
                        _setRaidListEnabledVis(cfg.raidListEnabled == true)
                    else
                        RAID.listEnabled = cfg.raidListEnabled == true
                    end
                    if RAID.listEntries and cfg.raidListEntries then
                        for k in pairs(RAID.listEntries) do RAID.listEntries[k] = nil end
                        for i, ent in ipairs(cfg.raidListEntries) do
                            local maps = {}; local ranks = {}
                            if type(ent.maps)  == "table" then
                                for mk, mv in pairs(ent.maps)  do if mv then maps[tonumber(mk) or mk] = true end end
                            end
                            if type(ent.ranks) == "table" then
                                for rk, rv in pairs(ent.ranks) do if rv then ranks[rk] = true end end
                            end
                            RAID.listEntries[i] = { maps = maps, ranks = ranks }
                        end
                        if _raidRebuildListRows then pcall(_raidRebuildListRows) end
                    end
                end)
                -- Main toggle RAID: _setRaidToggle handle visual (el:Set silently) + logika
                -- _visRaidToggle tidak dipanggil agar tidak double-fire StartRaidLoop ✓
                task.delay(0.5, function()
                    if _setRaidToggle then _setRaidToggle(cfg.raidOn == true) end
                end)
            end)
        end)

        -- ── AUTOMATION: ASC ───────────────────────────────────────────────
        pcall(function()
            if _setAscPMIdx and cfg.ascPMIdx then _setAscPMIdx(cfg.ascPMIdx) end
            if ASC.preferMaps and cfg.ascPreferMaps then
                for k in pairs(ASC.preferMaps) do ASC.preferMaps[k] = nil end
                for k, v in pairs(cfg.ascPreferMaps) do
                    local n = tonumber(k); if n then ASC.preferMaps[n] = true end
                end
            end
            if ASC.runeGrades and cfg.ascRuneGrades then
                for k in pairs(ASC.runeGrades) do ASC.runeGrades[k] = nil end
                for k, v in pairs(cfg.ascRuneGrades) do ASC.runeGrades[k] = true end
            end
            ASC.runeEnabled     = cfg.ascRuneEnabled     == true
            ASC.runeMapTarget   = cfg.ascRuneMapTarget   or 0
            ASC.preferMapTarget = cfg.ascPreferMapTarget or 0
            if _ascBossToggleVis then
                _ascBossToggleVis(cfg.ascAutoKillBoss == true)
            else
                ASC.autoKillBoss = cfg.ascAutoKillBoss == true
            end
            if _ascBossDelaySet then
                _ascBossDelaySet(cfg.ascBossDelay or 3)
            else
                ASC.bossDelay = cfg.ascBossDelay or 3
            end
            if ASC.listEntries and cfg.ascListEntries then
                for k in pairs(ASC.listEntries) do ASC.listEntries[k] = nil end
                for i, ent in ipairs(cfg.ascListEntries) do
                    local maps = {}; local ranks = {}
                    if ent.maps  then for k, v in pairs(ent.maps)  do local n = tonumber(k); if n then maps[n] = true end end end
                    if ent.ranks then for k, v in pairs(ent.ranks) do ranks[k] = true end end
                    ASC.listEntries[i] = { maps = maps, ranks = ranks }
                end
            end
            if _setAscListEnabledVis then
                _setAscListEnabledVis(cfg.ascListEnabled == true)
            else
                ASC.listEnabled = cfg.ascListEnabled == true
            end
            if _ascRebuildListRows then _ascRebuildListRows() end
            -- _setAscToggle handle visual + logika — tidak perlu _vis* ✓
            task.delay(0.7, function()
                if _setAscToggle then _setAscToggle(cfg.ascOn == true) end
            end)
        end)

        -- ── AUTOMATION: SIEGE ─────────────────────────────────────────────
        pcall(function()
            if SIEGE.excludeMaps and cfg.siegeExclude then
                for k, v in pairs(cfg.siegeExclude) do
                    local n = tonumber(k); if n then SIEGE.excludeMaps[n] = v end
                end
            end
            if _visSiegeExcludeDD then pcall(_visSiegeExcludeDD) end
            -- _setSiegeToggle: el:Set silently + StartSiegeLoop/StopSiege ✓
            task.delay(0.9, function()
                if _setSiegeToggle then _setSiegeToggle(cfg.siegeOn == true) end
            end)
        end)

        -- ── AUTOMATION: DUNGEON ───────────────────────────────────────────
        pcall(function()
            -- Tidak ada visual toggle di JTR; setter hanya update flag
            task.delay(1.1, function()
                if _setDungeonToggle then _setDungeonToggle(cfg.dungeonOn == true) end
            end)
        end)

        -- ── AUTOMATION: ST2 / ANNIVERSARY ────────────────────────────────
        pcall(function()
            ST2.waveCount = cfg.st2WaveCount or 0
            task.delay(1.3, function()
                if _setST2Toggle then _setST2Toggle(cfg.st2On == true) end
                if ST2.setAttackToggle and cfg.st2AttackOn ~= nil then
                    ST2.setAttackToggle(cfg.st2AttackOn == true)
                end
            end)
        end)

        -- ── REROLL TAB ────────────────────────────────────────────────────
        task.delay(0.3, function()
            pcall(function()
                -- Restore slotTarget dulu SEBELUM nyalakan toggle
                if _HR_RPT and _HR_RPT.slotTarget and cfg.heroSlotTarget then
                    for si = 1, 3 do
                        for k in pairs(_HR_RPT.slotTarget[si]) do _HR_RPT.slotTarget[si][k] = nil end
                        if type(cfg.heroSlotTarget[si]) == "table" then
                            for qid, v in pairs(cfg.heroSlotTarget[si]) do
                                if v then _HR_RPT.slotTarget[si][tonumber(qid) or qid] = true end
                            end
                        end
                    end
                end
                -- x100 dulu, baru running (urutan penting)
                if _setHeroX100Toggle then _setHeroX100Toggle(cfg.heroX100On == true) end
                task.delay(0.2, function()
                    if not cfg.heroX100On then
                        if _setHeroRollToggle then _setHeroRollToggle(cfg.heroRollOn == true) end
                    end
                end)
            end)
            pcall(function()
                if _WR_RPT and _WR_RPT.slotTarget and cfg.weaponSlotTarget then
                    for si = 1, 3 do
                        for k in pairs(_WR_RPT.slotTarget[si]) do _WR_RPT.slotTarget[si][k] = nil end
                        if type(cfg.weaponSlotTarget[si]) == "table" then
                            for qid, v in pairs(cfg.weaponSlotTarget[si]) do
                                if v then _WR_RPT.slotTarget[si][tonumber(qid) or qid] = true end
                            end
                        end
                    end
                end
                if _setWeaponX100Toggle then _setWeaponX100Toggle(cfg.weaponX100On == true) end
                task.delay(0.2, function()
                    if not cfg.weaponX100On then
                        if _setWeaponRollToggle then _setWeaponRollToggle(cfg.weaponRollOn == true) end
                    end
                end)
            end)
        end)

        -- ── WEBHOOK TAB ───────────────────────────────────────────────────
        pcall(function()
            -- [FIX] URL harus di-restore ke textbox dulu via _setWebhookUrlVis,
            -- bukan cuma tulis ke variabel global — agar input WindUI ikut update
            if _setWebhookUrlVis then
                _setWebhookUrlVis(cfg.webhookUrl or "")
            else
                _webhookUrl = (cfg.webhookUrl or ""):match("^%s*(.-)%s*$") or ""
            end

            -- [FIX v5] Gunakan _visWebhookToggle (visual-only, tanpa callback URL check).
            -- _setWebhookToggle memanggil :Set(v) WITH callback → callback validasi URL
            -- → jika URL belum siap atau kosong, callback paksa :Set(false,false) → visual
            -- balik OFF meski config punya webhookEnabled=true.
            -- Set _webhookEnabled langsung + update visual saja, tanpa trigger callback.
            local wantEnabled = cfg.webhookEnabled == true
            _webhookEnabled = wantEnabled
            if _visWebhookToggle then _visWebhookToggle(wantEnabled) end

            if _webhookModeSetIdx and cfg.webhookModeIdx then
                _webhookModeSetIdx(cfg.webhookModeIdx)
            end
        end)

        -- ── THEME TAB ────────────────────────────────────────────────────
        pcall(function()
            if type(cfg.themeTransparency) == "number" and _setTransparencyVis then
                _setTransparencyVis(math.clamp(math.floor(cfg.themeTransparency + 0.5), 0, 100))
            end
        end)
        pcall(function()
            if type(cfg.themeName) == "string" and _setThemeVis then
                _setThemeVis(cfg.themeName)
            end
        end)

        return true
    end

    -- ─── LOAD / DELETE CONFIG ─────────────────────────────────────────────────
    local function LoadConfigByName(name)
        local ok, result = pcall(function()
            local path = _cfgPath(name)
            local fileExists = false
            pcall(function() fileExists = isfile(path) end)
            if not fileExists then return nil end
            local raw = nil
            pcall(function() raw = readfile(path) end)
            if not raw or raw == "" then return nil end
            return jsonDecode(raw)
        end)
        if not ok then return nil end
        if type(result) ~= "table" then return nil end
        return result
    end

    local function DeleteConfigByName(name)
        local ok = pcall(function()
            local path = _cfgPath(name)
            local exists = pcall(isfile, path)
            if exists then pcall(delfile, path) end
        end)
        return ok
    end

    -- ─── SINGLE CONFIG SLOT (tidak multi-save lagi) ──────────────────────────
    -- Semua save/load/delete sekarang mengarah ke SATU file config tetap.
    -- Tidak ada lagi input nama, dropdown pilih config, atau tombol refresh.
    local SINGLE_CONFIG_NAME = "config"

    -- ─── PARAGRAPH STATUS (WindUI native) ────────────────────────────────────
    ConfigTab:Section({ Title = "Config Manager", Icon = "save" })

    local _statusPara = ConfigTab:Paragraph({
        Title = "Status",
        Desc  = "Pilih aksi di bawah.",
    })

    local function SetStatus(msg)
        pcall(function() _statusPara:SetDesc(msg) end)
    end

    -- ─── INISIALISASI STATUS AWAL ─────────────────────────────────────────────
    do
        local exists = false
        pcall(function() exists = isfile(_cfgPath(SINGLE_CONFIG_NAME)) end)
        if exists then
            SetStatus("Config tersimpan ditemukan. Klik LOAD CONFIG untuk menerapkan.")
        else
            SetStatus("Belum ada config tersimpan. Atur fitur lalu klik SAVE CONFIG.")
        end
    end

    -- ─── TOMBOL: SAVE CONFIG ──────────────────────────────────────────────────
    -- Menyimpan semua state/visual fitur yang sedang di-set user saat ini.
    -- Selalu menimpa (overwrite) file config tunggal yang sama -> tidak ada multi-save.
    ConfigTab:Button({
        Title    = "SAVE CONFIG",
        Desc     = "Simpan semua setting & fitur script saat ini (menimpa config sebelumnya)",
        Callback = function()
            SetStatus("Menyimpan config...")
            task.delay(0.05, function()
                local ok, err = SaveConfigAs(SINGLE_CONFIG_NAME)
                if ok then
                    SetStatus("Config tersimpan. (" .. os.date("%H:%M:%S") .. ")")
                else
                    SetStatus("[!] Gagal simpan: " .. tostring(err):sub(1, 60))
                end
            end)
        end,
    })

    -- ─── TOMBOL: LOAD CONFIG ──────────────────────────────────────────────────
    -- Restore sempurna semua state & tampilan menu/fitur sesuai config yang tersimpan.
    ConfigTab:Button({
        Title    = "LOAD CONFIG",
        Desc     = "Restore semua setting & fitur script sesuai config yang tersimpan",
        Callback = function()
            SetStatus("Memuat config...")
            task.delay(0.05, function()
                local cfg = LoadConfigByName(SINGLE_CONFIG_NAME)
                if type(cfg) == "table" then
                    ApplyConfig(cfg)
                    SetStatus("Config dimuat. (" .. os.date("%H:%M:%S") .. ")")
                else
                    SetStatus("[!] Tidak ada config tersimpan / gagal load.")
                end
            end)
        end,
    })

    -- ─── TOMBOL: DELETE CONFIG (double-confirm) ───────────────────────────────
    -- Klik pertama = konfirmasi, klik kedua (dalam 5 detik) = hapus permanen dari folder.
    local _pendingDel   = false
    local _pendingTimer = nil

    ConfigTab:Button({
        Title    = "DELETE CONFIG",
        Desc     = "Klik sekali untuk konfirmasi, klik lagi untuk hapus permanen",
        Callback = function()
            if _pendingDel then
                if _pendingTimer then pcall(task.cancel, _pendingTimer) end
                _pendingDel   = false
                _pendingTimer = nil
                local ok = DeleteConfigByName(SINGLE_CONFIG_NAME)
                if ok then
                    SetStatus("Config dihapus permanen.")
                else
                    SetStatus("[!] Gagal hapus config (mungkin belum ada yang tersimpan).")
                end
            else
                _pendingDel = true
                SetStatus("[!] YAKIN hapus config? Klik DELETE CONFIG sekali lagi untuk konfirmasi. (auto-cancel 5 detik)")
                _pendingTimer = task.delay(5, function()
                    _pendingDel   = false
                    _pendingTimer = nil
                    SetStatus("Hapus dibatalkan (timeout).")
                end)
            end
        end,
    })

end -- end do PANEL CONFIG

-- ════════════════════════════════════════════════════════════════════════════
-- PANEL: THEME  (ThemeTab)
-- GUI Transparency Slider: 0 (tebal/solid) → 50 (default★) → 100 (transparan)
--
-- Menggunakan API resmi WindUI:
--   Window:SetBackgroundTransparency(value)  → value 0.0 (opaque) – 1.0 (transparent)
--   WindUI.TransparencyValue = value          → sync ke internal WindUI juga
--
-- Slider 0–100 → dibagi 100 = nilai BackgroundTransparency WindUI (0.0–1.0)
-- ════════════════════════════════════════════════════════════════════════════
do
    -- ── State ─────────────────────────────────────────────────────────────
    local _transVal      = 50    -- nilai slider saat ini (default 50 → 0.5)
    local _transSliderEl = nil   -- referensi element WindUI slider

    -- ── Core: terapkan transparansi via API resmi WindUI ─────────────────
    -- sliderVal: 0 = solid/tebal, 100 = transparan penuh
    local function _applyTrans(sliderVal)
        local v = math.clamp(sliderVal / 100, 0, 1)
        -- Sync ke internal WindUI (dibaca saat SetTheme/redraw)
        pcall(function() WindUI.TransparencyValue = v end)
        -- Set transparansi background window via API resmi
        pcall(function() Window:SetBackgroundTransparency(v) end)
        -- Simpan ke global state
        _G.ThemeTransparency = sliderVal
        _transVal = sliderVal
    end

    -- ── Override _setTransSlider (menggantikan stub di atas) ─────────────
    -- Dipanggil dari luar (tidak perlu update visual slider, hanya logic).
    _setTransSlider = function(v)
        v = math.clamp(math.floor(v + 0.5), 0, 100)
        _applyTrans(v)
    end

    -- ── _setTransparencyVis: sync slider UI + apply efek ─────────────────
    -- ApplyConfig memanggil fungsi ini untuk restore nilai sekaligus update
    -- posisi slider agar visual slider ikut bergerak ke nilai yang benar.
    _setTransparencyVis = function(v)
        v = math.clamp(math.floor(v + 0.5), 0, 100)
        _applyTrans(v)
        -- Geser slider visual ke posisi yang sesuai
        pcall(function()
            if _transSliderEl then _transSliderEl:Set(v) end
        end)
    end

    -- ── Apply default (50 → 0.5) sesaat setelah WindUI fully render ──────
    task.delay(0.5, function()
        _applyTrans(_transVal)
    end)

    -- ════════════════════════════════════════════════════════════════════════
    -- UI: ThemeTab
    -- ════════════════════════════════════════════════════════════════════════

    ThemeTab:Section({ Title = "Tampilan GUI", Icon = "eye" })

    ThemeTab:Paragraph({
        Title = "GUI Transparency",
        Desc  = "Atur transparansi background window GUI.\n"
             .. "⬅ 0 = Tebal (solid)   |   50 = Default ★   |   100 = Transparan ➡",
    })

    _transSliderEl = ThemeTab:Slider({
        Flag     = "guiTransparency",
        Title    = "Transparency",
        Desc     = "0 = Solid/tebal   •   50 = Default   •   100 = Transparan penuh",
        Value    = { Min = 0, Max = 100, Default = 50 },
        Step     = 1,
        Callback = function(val)
            _applyTrans(val)
        end,
    })

    -- ════════════════════════════════════════════════════════════════════════
    -- DROPDOWN: COLOR THEME
    -- Ambil semua tema dari WindUI:GetThemes() secara dinamis → selalu up-to-date
    -- lalu sortir A-Z agar mudah dicari.
    -- ════════════════════════════════════════════════════════════════════════

    ThemeTab:Section({ Title = "Color Theme", Icon = "palette" })

    ThemeTab:Paragraph({
        Title = "Pilih Tema Warna",
        Desc  = "Ganti tema warna seluruh GUI secara real-time.\n"
             .. "Tema tersedia: Dark, Light, Rose, Plant, Indigo, Sky, Violet, Amber, Mellowsi, dll.",
    })

    -- ── Kumpulkan nama tema yang tersedia ────────────────────────────────
    local _themeList = {}
    pcall(function()
        for name, _ in pairs(WindUI:GetThemes()) do
            table.insert(_themeList, name)
        end
        table.sort(_themeList)  -- A-Z
    end)
    if #_themeList == 0 then
        -- Fallback hardcode kalau GetThemes() gagal
        _themeList = { "Amber", "Dark", "Indigo", "Light", "Mellowsi",
                       "Plant", "Rose", "Sky", "Violet" }
    end

    -- ── Tema aktif saat ini (dari CreateWindow Theme="Dark") ────────────
    local _currentThemeName = "Dark"
    pcall(function()
        local ct = WindUI:GetCurrentTheme()
        if type(ct) == "string" and ct ~= "" then
            _currentThemeName = ct
        end
    end)
    _G.CurrentTheme = _currentThemeName

    -- ── Dropdown element ─────────────────────────────────────────────────
    local _themeDropEl = ThemeTab:Dropdown({
        Flag     = "colorTheme",
        Title    = "Color Theme",
        Desc     = "Pilih tema warna GUI",
        Values   = _themeList,
        Value    = _currentThemeName,
        Multi    = false,
        Callback = function(selected)
            if type(selected) ~= "string" or selected == "" then return end
            pcall(function() WindUI:SetTheme(selected) end)
            _G.CurrentTheme = selected
        end,
    })

    -- ── Expose _setThemeVis untuk ApplyConfig ────────────────────────────
    -- Update visual dropdown + terapkan tema tanpa trigger loop callback.
    _setThemeVis = function(name)
        if type(name) ~= "string" or name == "" then return end
        pcall(function() WindUI:SetTheme(name) end)
        _G.CurrentTheme = name
        pcall(function()
            if _themeDropEl then _themeDropEl:Select(name) end
        end)
    end

end -- end do PANEL THEME

-- ============================================================================
-- CAPTURE LAYER INIT (dipasang di sini, SETELAH seluruh WindUI panel selesai)
-- Alasan: WindUI memasang hook __namecall internalnya saat CreateWindow/Tab.
-- Dengan pasang hook kita DI SINI (akhir script, synchronous), kita dijamin
-- jadi yang TERATAS di chain -- tidak ada lagi yang bisa timpa setelah ini.
-- Realtime: GUID langsung tertangkap saat player reroll 1x manual, tanpa delay.
-- ============================================================================
do
    if InitAllCaptureLayers then
        InitAllCaptureLayers()
    end
end
