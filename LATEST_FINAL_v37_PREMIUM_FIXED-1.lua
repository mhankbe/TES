--[[
    MIGRASI: WindUI -> Fluent (dawid-scripts/Fluent)
    Tahap 1: Window + 11 Tab
    Tahap 2: Isi Tab MAIN (4 section: Counter Auto Sell, Auto Collect Gold & Item,
             Auto Sell Hero Equip, Auto Sell Weapon)

    Referensi lengkap: WindUI_to_Fluent_Mapping.md
    Urutan tab dipertahankan PERSIS sama seperti source WindUI asli:
      1. Main
      2. Hide
      3. Farm
      4. Mass Attack
      5. Automation
      6. Reroll
      7. Player
      8. Setting
      9. Webhook
      10. Config
      11. Theme

    CATATAN MIGRASI (baca sebelum lanjut isi tab):
    - Fluent TIDAK punya OpenButton custom (gradient/CornerRadius/Draggable) seperti WindUI.
      Minimize/restore window pakai mekanisme bawaan Fluent sendiri (klik tombol minimize
      di window -> jadi ikon kecil). Floating bubble custom kamu TIDAK otomatis ter-port;
      kalau mau dipertahankan persis, perlu dibangun manual di atas Fluent nanti.
    - Fluent TIDAK punya field `User` (avatar+username) built-in seperti WindUI. Kalau fitur
      profil user penting, perlu dibuat manual (Players:GetUserThumbnailAsync + Frame custom)
      dan ditempel terpisah ke window instance -- BELUM dikerjakan di skeleton ini.
    - `Window:SetToggleKey(...)` versi WindUI -> dipindah jadi field `MinimizeKey` di
      constructor `CreateWindow` versi Fluent (lihat di bawah).
    - `Transparent = true` + `SetBackgroundTransparency(...)` (dipakai di tab Config/Theme,
      baris ~16227 & ~16337 source WindUI) BELUM ada padanan langsung dicari -- akan
      diselesaikan nanti saat migrasi tab Config/Theme, bukan di skeleton ini.
--]]

-- ============================================================================
-- LOAD FLUENT (loadstring dari release resmi dawid-scripts/Fluent)
-- ============================================================================
local Fluent

do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
    end)

    if ok and result then
        Fluent = result
    else
        error("[FLa] Gagal load Fluent (loadstring): " .. tostring(result))
    end
end

if type(Fluent) ~= "table" then
    error("[FLa] Fluent tidak mengembalikan modul yang valid (type = " .. type(Fluent) .. ").")
end

-- ============================================================================
-- SERVICES + DEPENDENSI GLOBAL
-- Dipindah persis dari source WindUI (baris ~53-198) -- dibutuhkan tab Main
-- (Auto Collect Gold & Item pakai RE.CollectItem/ExtraReward + StartLoop/StopLoop).
-- ============================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer

local PG = LP:WaitForChild("PlayerGui", 30)
if not PG then
    error("[FLa] PlayerGui tidak ketemu dalam 30 detik - coba execute ulang setelah masuk game sepenuhnya.")
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not Remotes then
    error("[FLa] Folder 'Remotes' tidak ketemu dalam 30 detik - coba tunggu lebih lama setelah masuk game sebelum execute.")
end

STATE = {
    autoCollect         = false,
    autoCollectGoldItem = false,
}
LOOPS     = {}  -- { [key] = thread } - dikelola StopLoop/StartLoop
COLLECTED = {}  -- dedup cache collect loop

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

-- PG_Wait (Adaptive PingGuard wait) - fallback 1x kalau PG_Multiplier() belum ada
if not PG_Wait then
    function PG_Wait(baseTime)
        local mult = (type(PG_Multiplier) == "function") and PG_Multiplier() or 1
        local t = (baseTime or 0.05) * mult
        if t > 5 then t = 5 end
        task.wait(t)
    end
end

RE = RE or {}
RE.CollectItem  = RE.CollectItem  or Remotes:WaitForChild("CollectItem", 10)
RE.ExtraReward  = RE.ExtraReward  or Remotes:WaitForChild("ExtraReward", 10)
-- Dibutuhkan TAB: FARM (RA/TA/FAST ATTACK) -- dipindah dari 5.lua baris 176-182
RE.Click        = RE.Click        or Remotes:FindFirstChild("ClickEnemy")
RE.Atk          = RE.Atk          or Remotes:FindFirstChild("PlayerClickAttackSkill")
RE.Death        = RE.Death        or Remotes:FindFirstChild("EnemyDeath")
RE.HeroUseSkill = RE.HeroUseSkill or Remotes:FindFirstChild("HeroUseSkill")
-- Dibutuhkan TAB: MASS ATTACK (TpMap)
RE.StartTp      = RE.StartTp      or Remotes:FindFirstChild("StartLocalPlayerTeleport")
RE.LocalTp      = RE.LocalTp      or Remotes:FindFirstChild("LocalPlayerTeleport")

--  GLOBALS FARM (dibutuhkan StartRA / TA) -- dipindah dari 5.lua baris 116-125
HERO_GUIDS = HERO_GUIDS or {}
MY_USER_ID = MY_USER_ID or LP.UserId

function IsValidUUID(str)
    if type(str) ~= "string" then return false end
    return str:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

-- ============================================================================
-- WINDOW
-- ============================================================================
local Window = Fluent:CreateWindow({
    Title       = "Auto Farming ASH",
    SubTitle    = "by FLa",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(580, 460),
    Acrylic     = false,           -- blur effect, dimatikan demi performa di executor
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.LeftAlt,  -- padanan Window:SetToggleKey(...) WindUI
})

-- ============================================================================
-- 11 TAB - urutan & Title/Icon dipertahankan persis dari source WindUI
-- Method: Window:Tab({...}) [WindUI]  ->  Window:AddTab({...}) [Fluent]
-- ============================================================================

local Tabs = {}

Tabs.Main = Window:AddTab({
    Title = "Main",
    Icon  = "home",
})

Tabs.Hide = Window:AddTab({
    Title = "Hide",
    Icon  = "eye-off",
})

Tabs.Farm = Window:AddTab({
    Title = "Farm",
    Icon  = "sword",
})

Tabs.MassAttack = Window:AddTab({
    Title = "Mass Attack",
    Icon  = "swords",
})

Tabs.Automation = Window:AddTab({
    Title = "Automation",
    Icon  = "bot",
})

Tabs.Reroll = Window:AddTab({
    Title = "Reroll",
    Icon  = "dices",
})

Tabs.Player = Window:AddTab({
    Title = "Player",
    Icon  = "user",
})

Tabs.Setting = Window:AddTab({
    Title = "Setting",
    Icon  = "settings",
})

Tabs.Webhook = Window:AddTab({
    Title = "Webhook",
    Icon  = "send",
})

Tabs.Config = Window:AddTab({
    Title = "Config",
    Icon  = "save",
})

Tabs.Theme = Window:AddTab({
    Title = "Theme",
    Icon  = "palette",
})

-- ============================================================================
-- TAB: MAIN
-- 4 section dari source WindUI (baris 344-1188):
--   1. Counter Auto Sell Hero Equip
--   2. Auto Collect Gold & Item
--   3. Auto Sell Hero Equip
--   4. Auto Sell Weapon
--
-- CATATAN STRUKTUR: Section WindUI di tab ini TIDAK bersarang (semua flat,
-- langsung dari MainTab), jadi konversi flat langsung dari Tabs.Main tanpa
-- container tambahan. Tiap "Section" WindUI -> Tabs.Main:AddSection(title) Fluent
-- (Fluent TIDAK punya Groupbox seperti library Linoria-based -- terkonfirmasi
-- via uji langsung getmetatable elemen di game, lihat commit fix ini).
--
-- CATATAN _visXxx (silent-set): dipertahankan pola guard manual
-- (_suppressXxx) sesuai strategi di WindUI_to_Fluent_Mapping.md, karena
-- Fluent:SetValue() SELALU trigger Callback (WindUI :Set(v, false) tidak ada
-- padanan langsung).
--
-- CATATAN BUG BAWAAN SOURCE ASLI (bukan muncul dari migrasi): fungsi
-- shouldSell() (dead code, tidak pernah dipanggil di alur aktif) memakai
-- _sellTypes / _minGrade / _SELL_GRADE_RANK yang TIDAK PERNAH didefinisikan
-- di source WindUI manapun yang di-upload. Dibawa apa adanya sebagai dead
-- code (tidak mempengaruhi fungsi aktif StartAutoSell), TIDAK diperbaiki di
-- sini karena bukan scope migrasi UI. Beri tahu saya kalau mau dibenerin.
-- ============================================================================
do
    -- ── Global expose (dibaca Config panel saat save/load) ──────────────────
    _setSellHeroToggle = nil
    _visSellHero       = nil
    _autoSellOnState   = false
    _setAutoCollectToggle = nil
    _visAutoCollect       = nil
    _autoCollectState     = false

    -- 
    -- SECTION 1: COUNTER AUTO SELL HERO EQUIP
    -- 
    local _autoSellOn   = false
    local _sellConn     = nil
    local _lockedGuids  = {}
    local _cnt          = {R=0, Y=0, B=0, other=0, skipped=0}
    local _sellToggleCb = nil

    Tabs.Main:AddSection("Counter Auto Sell Hero Equip")

    local _cntParagraph = Tabs.Main:AddParagraph({
        Title   = "Sold Count",
        Content = "R: 0  |  Y: 0  |  B: 0  |  Supreme skip: 0",
    })
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

    local _statusParagraph = nil  -- diisi di Section 3 (Auto Sell Hero Equip)
    local function SetSellStatus(msg)
        if not _statusParagraph then return end
        pcall(function() _statusParagraph:SetDesc(msg) end)
    end

    Tabs.Main:AddButton({
        Title       = "RESET COUNTER",
        Description = "Reset semua angka counter ke 0",
        Callback    = function()
            _cnt = {R=0, Y=0, B=0, other=0, skipped=0}
            RefreshCounters()
            SetSellStatus("[OK] DONE RESET")
        end,
    })

    -- 
    -- SECTION 2: AUTO COLLECT GOLD & ITEM
    -- 
    do
        local _instantCollectConns = {}
        local _instantCollected    = {}

        local function _collectObj(obj)
            local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid")
            if not guid or _instantCollected[guid] then return end
            _instantCollected[guid] = true
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
            pcall(function() RE.CollectItem:InvokeServer(guid) end)
            if RE.ExtraReward then
                pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
            end
        end

        local function StartInstantGoldCollector(on)
            for _, c in ipairs(_instantCollectConns) do pcall(function() c:Disconnect() end) end
            _instantCollectConns = {}
            _instantCollected    = {}
            if not on then return end

            local DROP_FOLDERS = {"Golds","Items","Drops","Rewards","Loot","DropItems","RewardItems"}
            for _, folderName in ipairs(DROP_FOLDERS) do
                task.spawn(function()
                    local folder = workspace:FindFirstChild(folderName)
                                or workspace:WaitForChild(folderName, 5)
                    if not folder then return end
                    for _, obj in ipairs(folder:GetChildren()) do
                        _collectObj(obj)
                    end
                    local conn = folder.ChildAdded:Connect(function(obj)
                        _collectObj(obj)
                    end)
                    table.insert(_instantCollectConns, conn)
                end)
            end

            local wsConn = workspace.ChildAdded:Connect(function(obj)
                for _, fn in ipairs(DROP_FOLDERS) do
                    if obj.Name == fn then
                        task.spawn(function()
                            task.wait(0.05)
                            for _, child in ipairs(obj:GetChildren()) do
                                _collectObj(child)
                            end
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
                                        if obj:IsA("BasePart") then
                                            obj.CFrame = CFrame.new(playerPos)
                                        elseif obj:IsA("Model") then
                                            local part = obj:FindFirstChildWhichIsA("BasePart") or obj.PrimaryPart
                                            if part then part.CFrame = CFrame.new(playerPos) end
                                        end
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
                    PG_Wait(0.05)
                end
                _goldMagnetRunning = false
            end)
        end
        local function StopGoldMagnet()
            _goldMagnetRunning = false
        end

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
                                    if RE.ExtraReward then
                                        pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                                    end
                                    PG_Wait(0.03)
                                end
                            end
                        end
                    end
                    PG_Wait(0.2)
                end
            end)
        end

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

        Tabs.Main:AddSection("Auto Collect Gold & Item")

        -- Guard silent-set (padanan WindUI :Set(v, false)) - lihat mapping doc
        local _suppressCollectCb = false
        local _collectToggleElement = Tabs.Main:AddToggle("mainCollect", {
            Title       = "AUTO COLLECT GOLD & ITEM",
            Description = "collect semua gold/item ke player",
            Default     = false,
            Callback    = function(on)
                if _suppressCollectCb then return end
                _autoCollectState = on
                DoAutoCollectGoldItem(on)
            end,
        })

        _setAutoCollectToggle = function(v)
            if _collectToggleElement then
                _collectToggleElement:SetValue(v)  -- trigger Callback + update visual
            end
        end
        _visAutoCollect = function(v)
            if _collectToggleElement then
                _suppressCollectCb = true
                _collectToggleElement:SetValue(v)  -- update visual only (silent, guard aktif)
                _suppressCollectCb = false
            end
        end
    end

    -- 
    -- SECTION 3: AUTO SELL HERO EQUIP
    -- 
    Tabs.Main:AddSection("Auto Sell Hero Equip")

    _statusParagraph = Tabs.Main:AddParagraph({
        Title   = "Status",
        Content = "Idle",
    })

    local _suppressSellCb = false
    local _sellToggleElement = Tabs.Main:AddToggle("mainSellHero", {
        Title       = "AUTO SELL HERO EQUIP",
        Description = "Auto sell all items (except Locked & Supreme)",
        Default     = false,
        Callback    = function(on)
            if _suppressSellCb then return end
            _autoSellOn      = on
            _autoSellOnState = on
            if _sellToggleCb then _sellToggleCb(on) end
        end,
    })

    _setSellHeroToggle = function(v)
        if _sellToggleElement then
            _sellToggleElement:SetValue(v)   -- trigger Callback + update visual
        end
    end
    _visSellHero = function(v)
        if _sellToggleElement then
            _suppressSellCb = true
            _sellToggleElement:SetValue(v)   -- update visual only (silent, guard aktif)
            _suppressSellCb = false
        end
    end

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

    local function getType(name)
        if not name or #name == 0 then return "other" end
        local f = name:sub(1,1):upper()
        if f == "R" then return "R"
        elseif f == "Y" then return "Y"
        elseif f == "B" then return "B"
        else return "other" end
    end

    -- [DEAD CODE - dibawa apa adanya dari source, tidak pernah dipanggil di
    -- alur aktif StartAutoSell. Lihat catatan bug di komentar atas tab Main.]
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

    local function StartAutoSell()
        if _sellConn then pcall(function() _sellConn:Disconnect() end) end

        local updateRemote = Remotes:FindFirstChild("UpdateHeroEquip")
        if not updateRemote then
            SetSellStatus("[!] Remote UpdateHeroEquip NOT FOUND!")
            return
        end

        scanGuidNames()

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

    -- 
    -- SECTION 4: AUTO SELL WEAPON
    -- 
    do
        local GUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

        local _lastScan      = {}
        local _scanDone      = false
        local _statusPara    = nil
        local _sellCooldown  = false
        local _soldGuidsEver = {}  -- blacklist permanen, tidak pernah direset selama sesi berjalan

        local function SetWStatus(msg)
            if not _statusPara then return end
            pcall(function() _statusPara:SetDesc(msg) end)
        end

        local function _findActiveScrollFrame()
            local best, bestCount = nil, -1
            for _, obj in ipairs(PG:GetDescendants()) do
                if obj.Name == "EquipmentPanel" then
                    local sf = obj:FindFirstChild("ScrollingFrame", true)
                    if sf then
                        local c = 0
                        for _, child in ipairs(sf:GetChildren()) do
                            if child.Name:match(GUID_PATTERN) then c = c + 1 end
                        end
                        if c > bestCount then bestCount = c; best = sf end
                    end
                end
            end
            return best, bestCount
        end

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
            local blacklistedCount = 0
            for _, clone in ipairs(scrollFrame:GetChildren()) do
                if clone.Name:match(GUID_PATTERN) then
                    repeat
                        local guid = clone.Name
                        if _soldGuidsEver[guid] then
                            blacklistedCount = blacklistedCount + 1
                            break
                        end

                        local name = "?"
                        local isLock = false
                        local lockReadOk = false

                        pcall(function()
                            local titleText = clone:FindFirstChild("TitleText", true)
                            if titleText and titleText:IsA("TextLabel") then
                                name = titleText.Text
                            end
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
                        end

                        table.insert(results, { guid = guid, name = name, isLock = isLock, lockReadOk = lockReadOk })
                    until true
                end
            end

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
                if not w.lockReadOk then
                    skippedUnreadable = skippedUnreadable + 1
                elseif not w.isLock then
                    table.insert(toSell, w.guid)
                end
            end

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

                for _, g in ipairs(toSell) do _soldGuidsEver[g] = true end

                _scanDone = false
                _lastScan = {}

                _sellCooldown = true
                task.delay(2, function()
                    _sellCooldown = false
                    SetWStatus("[OK] SOLD " .. #toSell .. " weapon Unlock selesai. Tekan SCAN untuk cek sisa.")
                end)
            else
                SetWStatus("[!] Gagal fire DeleteWeapons.")
            end
        end

        Tabs.Main:AddSection("Auto Sell Weapon")

        _statusPara = Tabs.Main:AddParagraph({
            Title   = "Status",
            Content = "Idle - buka EquipmentPanel di game, lalu tekan SCAN WEAPON",
        })

        Tabs.Main:AddButton({
            Title       = "SCAN WEAPON",
            Description = "Scan status Lock/Unlock semua weapon (buka EquipmentPanel dulu)",
            Callback    = function()
                ScanWeapons()
            end,
        })

        Tabs.Main:AddButton({
            Title       = "SELL UNLOCK WEAPON",
            Description = "Jual/Delete semua weapon berstatus UNLOCK hasil SCAN (Lock aman)",
            Callback    = function()
                SellUnlockedWeapons()
            end,
        })
    end

    -- 
    -- SECTION 5: AUTO DECOMPOSE GEMS
    -- 
    do
        _autoDecompGemSet   = nil
        _visDecompGem       = nil
        _autoDecompGemState = false
        _setGemLevelRange   = nil
        _gemMinLevelState   = 1
        _gemMaxLevelState   = 1

        local _autoDecompGemOn     = false
        local _autoDecompGemThread = nil
        local GEM_ITEM_TYPE        = 7
        local _gemMinLevel         = 1
        local _gemMaxLevel         = 1

        local GEM_ID_RANGES = {
            {88001, 88009,  1,  9, "Ruby"},
            {88011, 88019,  1,  9, "Emerald"},
            {88021, 88029,  1,  9, "Sapphire"},
            {88031, 88039,  1,  9, "Deadly Gem"},
            {88141, 88149,  1,  9, "Purple Gem"},
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
            {88171, 88180, 21, 30, "Ruby"},
            {88181, 88190, 21, 30, "Emerald"},
            {88191, 88200, 21, 30, "Sapphire"},
            {88041, 88049,  1,  9, "Colorful Gem"},
            {88050, 88050, 10, 10, "Colorful Gem"},
            {88101, 88110, 11, 20, "Colorful Gem"},
            {88051, 88059,  1,  9, "Rainbow Gem"},
            {88060, 88060, 10, 10, "Rainbow Gem"},
            {88111, 88120, 11, 20, "Rainbow Gem"},
        }

        local GEM_ID_TO_LEVEL = {}
        for _, r in ipairs(GEM_ID_RANGES) do
            local startId, endId, minLv = r[1], r[2], r[3]
            for id = startId, endId do
                GEM_ID_TO_LEVEL[id] = minLv + (id - startId)
            end
        end

        local function IsGemIdToDecomp(itemId, minLv, maxLv)
            local lv = GEM_ID_TO_LEVEL[itemId]
            if not lv then return false end
            return lv >= minLv and lv <= maxLv
        end

        local _dgStatusParagraph = nil
        local function SetDGStatus(msg)
            if not _dgStatusParagraph then return end
            pcall(function() _dgStatusParagraph:SetDesc(msg) end)
        end

        local _dgMinInputElement = nil
        local _dgMaxInputElement = nil
        local function SetDGLevelRange(minLv, maxLv)
            _gemMinLevel      = minLv or 1
            _gemMaxLevel      = maxLv or 1
            _gemMinLevelState = _gemMinLevel
            _gemMaxLevelState = _gemMaxLevel
            if _dgMinInputElement then
                pcall(function() _dgMinInputElement:SetValue(tostring(_gemMinLevel)) end)
            end
            if _dgMaxInputElement then
                pcall(function() _dgMaxInputElement:SetValue(tostring(_gemMaxLevel)) end)
            end
        end

        local function GetGemGuidsFromPanel(minLv, maxLv)
            local result = {}
            pcall(function()
                local pg = LP.PlayerGui
                local gp = pg:FindFirstChild("GemsPanel")
                if not gp then return end

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
                        if #guidStr ~= 36 or not guidStr:find("^%x+%-%x+%-%x+%-%x+%-%x+$") then break end

                        local itemId = child:GetAttribute("itemId") or child:GetAttribute("ItemId")
                                    or child:GetAttribute("id")     or child:GetAttribute("Id")
                                    or child:GetAttribute("item_id")

                        if not itemId then
                            for _, c in ipairs(child:GetDescendants()) do
                                local aid = c:GetAttribute("itemId") or c:GetAttribute("ItemId")
                                         or c:GetAttribute("id")     or c:GetAttribute("Id")
                                         or c:GetAttribute("item_id")
                                if aid and tonumber(aid) then itemId = tonumber(aid); break end
                            end
                        end

                        if itemId and tonumber(itemId) then
                            local id = tonumber(itemId)
                            if IsGemIdToDecomp(id, minLv, maxLv) then
                                table.insert(result, guidStr)
                            end
                        else
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

        local _dgToggleElement = nil
        local function SetDGPillOff()
            _autoDecompGemOn = false
            if _dgToggleElement then
                pcall(function() _dgToggleElement:SetValue(false) end)
            end
        end

        local function RunAutoDecompGem()
            if _gemMinLevel < 1 then
                SetDGStatus("[ERROR] Min Level wajib diisi!")
                task.wait(2); SetDGPillOff()
                SetDGStatus("Idle - Input Error")
                return
            end

            if _gemMaxLevel < 1 then
                SetDGStatus("[ERROR] Max Level wajib diisi!")
                task.wait(2); SetDGPillOff()
                SetDGStatus("Idle - Input Error")
                return
            end

            if _gemMinLevel > _gemMaxLevel then
                SetDGStatus("[ERROR] Min Level > Max Level!")
                task.wait(2); SetDGPillOff()
                SetDGStatus("Idle - Input Error")
                return
            end

            if _gemMinLevel < 1 or _gemMinLevel > 150 or _gemMaxLevel < 1 or _gemMaxLevel > 150 then
                SetDGStatus("[ERROR] Level harus antara 1-150!")
                task.wait(2); SetDGPillOff()
                SetDGStatus("Idle - Input Error")
                return
            end

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
                pcall(function() re:FireServer({itemType = GEM_ITEM_TYPE, data = batch}) end)
                decomposed = decomposed + #batch
                task.wait(0.5)
            end

            SetDGStatus("[OK] " .. decomposed .. " gem DECOMPOSED! (Lv" .. _gemMinLevel .. "-" .. _gemMaxLevel .. ")")
            task.wait(2); SetDGPillOff()
            SetDGStatus("Idle")
        end

        Tabs.Main:AddSection("Auto Decompose Gems")

        _dgStatusParagraph = Tabs.Main:AddParagraph({
            Title   = "Status",
            Content = "Idle",
        })

        local _suppressDGMinCb = false
        _dgMinInputElement = Tabs.Main:AddInput("mainGemMin", {
            Title       = "Min Level",
            Description = "Level minimum gem yang akan di-decompose (1-120)",
            Default     = "1",
            Placeholder = "Contoh: 1",
            Callback    = function(val)
                if _suppressDGMinCb then return end
                local n = tonumber(val)
                if n and n >= 1 and n <= 150 then
                    _gemMinLevel      = n
                    _gemMinLevelState = n
                end
            end,
        })

        local _suppressDGMaxCb = false
        _dgMaxInputElement = Tabs.Main:AddInput("mainGemMax", {
            Title       = "Max Level",
            Description = "Level maksimum gem yang akan di-decompose (1-120)",
            Default     = "1",
            Placeholder = "Contoh: 5",
            Callback    = function(val)
                if _suppressDGMaxCb then return end
                local n = tonumber(val)
                if n and n >= 1 and n <= 150 then
                    _gemMaxLevel      = n
                    _gemMaxLevelState = n
                end
            end,
        })

        SetDGLevelRange(1, 1)
        _setGemLevelRange = SetDGLevelRange

        _dgToggleElement = Tabs.Main:AddToggle("mainDecompGem", {
            Title       = "AUTO DECOMPOSE GEMS",
            Description = "Scan GemsPanel & decompose gem sesuai range level",
            Default     = false,
            Callback    = function(on)
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

        _autoDecompGemSet = function(v)
            if v == _autoDecompGemOn then return end
            _autoDecompGemOn    = v
            _autoDecompGemState = v
            if _dgToggleElement then _dgToggleElement:SetValue(v) end
        end

        _visDecompGem = function(v)
            _autoDecompGemState = v
            if _dgToggleElement then
                pcall(function() _dgToggleElement:SetValue(v) end)
            end
        end
    end

    -- 
    -- SECTION 6: AUTO MERGE POTION
    -- 
    do
        _mergeRunningState = false
        _setMergeToggle    = nil
        _visMerge          = nil

        local MERGE_POTIONS = {
            {name = "Small Attack Potion", id = 10048},
            {name = "Small Gold Potion",   id = 10049},
            {name = "Small Luck Potion",   id = 10047},
            {name = "Big Potion DMG",      id = 10051},
            {name = "Big Potion Gold",     id = 10052},
            {name = "Big Potion Luck",     id = 10050},
        }

        local _mDropValues = {}
        local _mNameToId   = {}
        for _, pt in ipairs(MERGE_POTIONS) do
            table.insert(_mDropValues, pt.name)
            _mNameToId[pt.name] = pt.id
        end

        local _mergeSelectedId = nil
        local _mergeCount      = 1
        local _mergeRunning    = false
        local _mergeThread     = nil

        local _mergeStatusParagraph = nil
        local function SetMergeStatus(msg)
            if not _mergeStatusParagraph then return end
            pcall(function() _mergeStatusParagraph:SetDesc(msg) end)
        end

        Tabs.Main:AddSection("Auto Merge Potion")

        _mergeStatusParagraph = Tabs.Main:AddParagraph({
            Title   = "Status",
            Content = "Idle - SELECT ITEM & ENABLE",
        })

        local _mDropElement = Tabs.Main:AddDropdown("mainMergeItem", {
            Title       = "Select Item",
            Description = "Pilih potion yang akan di-merge",
            Values      = _mDropValues,
            Multi       = false,
            Callback    = function(val)
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

        local _mCountInput = Tabs.Main:AddInput("mainMergeCount", {
            Title       = "Count (1-5)",
            Description = "Jumlah merge per siklus (1-5)",
            Default     = "1",
            Placeholder = "Contoh: 1",
            Callback    = function(val)
                local n = tonumber(val)
                if n and n >= 1 and n <= 5 then
                    _mergeCount = math.floor(n)
                end
            end,
        })

        local _suppressMergeCb = false
        local _mergeToggleElement = Tabs.Main:AddToggle("mainMergeToggle", {
            Title       = "AUTO MERGE POTION",
            Description = "ON = START merge potion",
            Default     = false,
            Callback    = function(on)
                if _suppressMergeCb then return end
                if on then
                    if not _mergeSelectedId then
                        SetMergeStatus("[!] SELECT ITEM PLEASE!")
                        task.defer(function()
                            if _mergeToggleElement then
                                _suppressMergeCb = true
                                pcall(function() _mergeToggleElement:SetValue(false) end)
                                _suppressMergeCb = false
                            end
                        end)
                        return
                    end
                    _mergeRunning      = true
                    _mergeRunningState = true
                    if _mergeThread then pcall(function() task.cancel(_mergeThread) end) end
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

        _setMergeToggle = function(v)
            if _mergeToggleElement then
                _mergeToggleElement:SetValue(v)
            end
        end
        _visMerge = function(v)
            if _mergeToggleElement then
                _suppressMergeCb = true
                pcall(function() _mergeToggleElement:SetValue(v) end)
                _suppressMergeCb = false
            end
        end
    end

    -- 
    -- SECTION 7: AUTO USE POTION
    -- 
    do
        _useRunningState = false
        _setUseToggle    = nil
        _visUse          = nil

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

        local _uDropValues = {}
        local _uNameToId   = {}
        for _, pt in ipairs(USE_POTIONS) do
            table.insert(_uDropValues, pt.name)
            _uNameToId[pt.name] = pt.id
        end

        local _useSelectedId = nil
        local _useCount      = 1
        local _useRunning    = false
        local _useThread     = nil

        local _useStatusParagraph = nil
        local function SetUseStatus(msg)
            if not _useStatusParagraph then return end
            pcall(function() _useStatusParagraph:SetDesc(msg) end)
        end

        Tabs.Main:AddSection("Auto Use Potion")

        _useStatusParagraph = Tabs.Main:AddParagraph({
            Title   = "Status",
            Content = "Idle - SELECT ITEM & ENABLE",
        })

        local _uDropElement = Tabs.Main:AddDropdown("mainUseItem", {
            Title       = "Select Item",
            Description = "Pilih potion yang akan digunakan",
            Values      = _uDropValues,
            Multi       = false,
            Callback    = function(val)
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

        local _uCountInput = Tabs.Main:AddInput("mainUseCount", {
            Title       = "Use Count (1-100)",
            Description = "Jumlah potion yang digunakan per siklus (1-100)",
            Default     = "1",
            Placeholder = "Contoh: 1",
            Callback    = function(val)
                local n = tonumber(val)
                if n and n >= 1 and n <= 100 then
                    _useCount = math.floor(n)
                end
            end,
        })

        local _suppressUseCb = false
        local _useToggleElement = Tabs.Main:AddToggle("mainUseToggle", {
            Title       = "AUTO USE POTION",
            Description = "ON = start use potion",
            Default     = false,
            Callback    = function(on)
                if _suppressUseCb then return end
                if on then
                    if not _useSelectedId then
                        SetUseStatus("[!] SELECT ITEM PLEASE!")
                        task.defer(function()
                            if _useToggleElement then
                                _suppressUseCb = true
                                pcall(function() _useToggleElement:SetValue(false) end)
                                _suppressUseCb = false
                            end
                        end)
                        return
                    end
                    _useRunning      = true
                    _useRunningState = true
                    if _useThread then pcall(function() task.cancel(_useThread) end) end
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

        _setUseToggle = function(v)
            if _useToggleElement then
                _useToggleElement:SetValue(v)
            end
        end
        _visUse = function(v)
            if _useToggleElement then
                _suppressUseCb = true
                pcall(function() _useToggleElement:SetValue(v) end)
                _suppressUseCb = false
            end
        end
    end
end -- end do TAB: MAIN

-- ============================================================================
-- TAB: HIDE
-- Dipindah dari PANEL: HIDE (5.lua baris ~16867-17339)
-- Konversi WindUI -> Fluent:
--   HideTab:Section({Title,Icon})  -> Tabs.Hide:AddSection(title)
--   HideTab:Paragraph({Title,Desc})-> Tabs.Hide:AddParagraph({Title,Content})
--                                     + SetDesc pakai :SetDesc() via Heartbeat/pcall
--   HideTab:Toggle({Flag,Title,Desc,Value,Callback})
--                                  -> Tabs.Hide:AddToggle(Flag, {Title,Description,Default,Callback})
--   toggle:Set(v)       (WindUI)   -> toggleEl:SetValue(v)  (Fluent, selalu trigger Callback)
--   toggle:Set(v,false) (WindUI)   -> _suppressXxxCb=true; toggleEl:SetValue(v); _suppress=false
--
-- Global expose (dibaca Config panel saat save/load):
--   _hideRerollChatState, _setHideRerollChat, _visHideRerollChat
--   _hideAllUIState,      _setHideAllUI,      _visHideAllUI
--   _hideAllAnimState,    _setHideAllAnim,     _visHideAllAnim
--   _hideRewardState,     _setHideReward,      _visHideRewardPanel
-- ============================================================================
do
    -- Global expose state tracking (dibaca Config panel saat save/load)
    _hideRerollChatState = false
    _hideAllUIState      = false
    _hideAllAnimState    = false
    _hideRewardState     = false

    -- Global expose setters/vis (diisi setelah Toggle dibuat)
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
    -- FLUENT UI ELEMENTS
    -- Konversi:
    --   HideTab:Section({Title,Icon}) -> Tabs.Hide:AddSection(title)
    --     [Fluent hanya terima string title, Icon diabaikan]
    --   HideTab:Paragraph({Title,Desc}) -> Tabs.Hide:AddParagraph({Title,Content})
    --   HideTab:Toggle({Flag,Title,Desc,Value,Callback})
    --     -> Tabs.Hide:AddToggle(Flag, {Title,Description,Default,Callback})
    --   toggle:Set(v)       -> toggleEl:SetValue(v)       [trigger Callback]
    --   toggle:Set(v,false) -> _suppress=true; toggleEl:SetValue(v); _suppress=false
    -- ============================================================

    Tabs.Hide:AddSection("Hide Manager")

    Tabs.Hide:AddParagraph({
        Title   = "Hide Manager",
        Content = "Sembunyikan elemen game. Toggle OFF untuk restore penuh.",
    })

    -- 1. HIDE REROLL CHAT
    Tabs.Hide:AddSection("Hide Reroll Chat")

    local _suppressHrcrCb = false
    local _hrcrToggle = Tabs.Hide:AddToggle("hideRerollChat", {
        Title       = "HIDE REROLL CHAT",
        Description = "Sembunyikan baris chat 'just reroll a...' tanpa menghilangkan chat box",
        Default     = false,
        Callback    = function(on)
            if _suppressHrcrCb then return end
            ApplyHideReroll(on)
        end,
    })
    _setHideRerollChat = function(v)
        ApplyHideReroll(v)
        if _hrcrToggle then
            _suppressHrcrCb = true
            pcall(function() _hrcrToggle:SetValue(v) end)
            _suppressHrcrCb = false
        end
    end
    _visHideRerollChat = function(v)
        if _hrcrToggle then
            _suppressHrcrCb = true
            pcall(function() _hrcrToggle:SetValue(v) end)
            _suppressHrcrCb = false
        end
    end

    -- 2. HIDE ALL UI
    Tabs.Hide:AddSection("Hide All UI")

    local _suppressHauiCb = false
    local _hauiToggle = Tabs.Hide:AddToggle("hideAllUI", {
        Title       = "HIDE ALL UI",
        Description = "Sembunyikan semua panel game. Toggle OFF restore penuh.",
        Default     = false,
        Callback    = function(on)
            if _suppressHauiCb then return end
            ApplyHideUI(on)
        end,
    })
    _setHideAllUI = function(v)
        ApplyHideUI(v)
        if _hauiToggle then
            _suppressHauiCb = true
            pcall(function() _hauiToggle:SetValue(v) end)
            _suppressHauiCb = false
        end
    end
    _visHideAllUI = function(v)
        if _hauiToggle then
            _suppressHauiCb = true
            pcall(function() _hauiToggle:SetValue(v) end)
            _suppressHauiCb = false
        end
    end

    -- 3. HIDE ALL ANIMATION
    Tabs.Hide:AddSection("Hide All Animation")

    local _suppressHanimCb = false
    local _hanimToggle = Tabs.Hide:AddToggle("hideAllAnim", {
        Title       = "HIDE ALL ANIMATION",
        Description = "Matikan animasi, efek, partikel. Restore penuh saat OFF.",
        Default     = false,
        Callback    = function(on)
            if _suppressHanimCb then return end
            ApplyHideAnim(on)
        end,
    })
    _setHideAllAnim = function(v)
        ApplyHideAnim(v)
        if _hanimToggle then
            _suppressHanimCb = true
            pcall(function() _hanimToggle:SetValue(v) end)
            _suppressHanimCb = false
        end
    end
    _visHideAllAnim = function(v)
        if _hanimToggle then
            _suppressHanimCb = true
            pcall(function() _hanimToggle:SetValue(v) end)
            _suppressHanimCb = false
        end
    end

    -- 4. AUTO HIDE REWARD
    Tabs.Hide:AddSection("Auto Hide Reward")

    local _suppressHrewCb = false
    local _hrewToggle = Tabs.Hide:AddToggle("hideReward", {
        Title       = "AUTO HIDE REWARD",
        Description = "Sembunyikan popup reward otomatis. Aktifkan setelah Reward muncul",
        Default     = false,
        Callback    = function(on)
            if _suppressHrewCb then return end
            ApplyHideReward(on)
        end,
    })
    _setHideReward = function(v)
        ApplyHideReward(v)
        if _hrewToggle then
            _suppressHrewCb = true
            pcall(function() _hrewToggle:SetValue(v) end)
            _suppressHrewCb = false
        end
    end
    _visHideRewardPanel = function(v)
        if _hrewToggle then
            _suppressHrewCb = true
            pcall(function() _hrewToggle:SetValue(v) end)
            _suppressHrewCb = false
        end
    end

end -- end do TAB: HIDE

-- ============================================================================
-- TAB: FARM
-- Dipindah dari PANEL: FARM (5.lua baris 18040-19509)
-- Konversi API: WindUI -> Fluent
--   FarmTab:Section({Title,Icon})      -> Tabs.Farm:AddSection(title)
--   FarmTab:Paragraph({Title,Desc})    -> Tabs.Farm:AddParagraph({Title,Content})
--                                          + SetDesc pakai :SetDesc()
--   FarmTab:Button({Title,Desc,Callback}) -> Tabs.Farm:AddButton({Title,Description,Callback})
--   FarmTab:Toggle({Flag,Title,Desc,Value,Callback})
--                                       -> Tabs.Farm:AddToggle(Flag,{Title,Description,Default,Callback})
--   FarmTab:Dropdown({Flag,Title,Desc,Values,Value,Multi,Callback})
--                                       -> Tabs.Farm:AddDropdown(Flag,{Title,Description,Values,Multi,Callback})
--   toggle:Set(v)          -> toggleEl:SetValue(v)
--   toggle:Set(v,false) (silent) -> _suppressXxxCb guard + SetValue(v)
--   dropdown:Set({})       -> dropdownEl:SetValues({}) (silent rebuild, no callback fire)
--   dropdown:Refresh(vals,nil) -> dropdownEl:SetValues(vals)
--
-- SEMUA LOGIKA (state, threads, remote fire, freeze/unfreeze, block skill effects,
-- HP monitor, RA, TA by ID/Name, Fast Attack clone) dipindah 100% UTUH tanpa
-- ada 1 baris pun yang berubah dari sisi logika. Hanya layer pembuatan UI
-- (section/paragraph/button/toggle/dropdown) yang dikonversi ke Fluent API.
--
-- Fitur:
--   1. ENEMY HP MONITOR   HP bar + stopwatch (Paragraph + Button START/STOP/RESET)
--   2. RANDOM ATTACK (RA)  Toggle, kill counter Paragraph, BlockSkillEffects
--   3. SELECT ENEMY / TARGET ATTACK (TA)  Mode dropdown + Refresh + enemy list rows
--   4. FAST ATTACK 1 ENEMYS  Clone duplikat musuh (GET/START/STOP)
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
    --  ENEMY HP MONITOR (Fluent Paragraph + Buttons) 
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

        Tabs.Farm:AddSection(" ENEMY HP MONITOR")

        _ehpPara = Tabs.Farm:AddParagraph({ Title = "HP", Content = " / " })
        _timerPara = Tabs.Farm:AddParagraph({ Title = "Stopwatch", Content = " 00:00 [STOPPED]" })
        _ratePara  = Tabs.Farm:AddParagraph({ Title = "Rate", Content = "1% setiap ~--:--" })

        Tabs.Farm:AddButton({
            Title       = " START Stopwatch",
            Description = "Mulai / lanjut hitung waktu",
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
        Tabs.Farm:AddButton({
            Title       = " STOP Stopwatch",
            Description = "Pause timer (bisa dilanjut)",
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
        Tabs.Farm:AddButton({
            Title       = " RESET Stopwatch",
            Description = "Reset timer ke 00:00",
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
    Tabs.Farm:AddSection(" RANDOM ATTACK")

    local _raToggleElement = Tabs.Farm:AddToggle("farmRA", {
        Title       = "RANDOM ATTACK",
        Description = "Auto attack musuh random sampai mati, lalu ganti target",
        Default     = false,
        Callback = function(on)
            _raRunningState = on
            if on then StartRA() else StopRA() end
        end,
    })

    _setRAToggle = function(v)
        _raRunningState = v
        if _raToggleElement then pcall(function() _raToggleElement:SetValue(v) end) end
    end
    _visRandomAtk = function(v)
        if _raToggleElement then pcall(function() _raToggleElement:SetValue(v) end) end
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
    Tabs.Farm:AddSection(" TARGET ATTACK")

    local _taStatusPara      = Tabs.Farm:AddParagraph({ Title = "Status TA", Content = "Idle" })

    -- Mode dropdown: By ID / By Name
    local _listMode = "id"
    Tabs.Farm:AddDropdown("farmTAMode", {
        Title       = "Mode Select",
        Description = "By ID = target individu | By Name = musuh yang sama",
        Values      = {"By ID", "By Name"},
        Default     = "By ID",
        Multi       = false,
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

    _enemyDropElement = Tabs.Farm:AddDropdown("farmTAEnemy", {
        -- Flag dipasang minimal (Fluent AddDropdown butuh flag), list ini di-rebuild
        -- dinamis tiap REFRESH ENEMIES, nilai yang disimpan tidak bermakna lintas sesi
        -- (GUID enemy berubah).
        Title       = "Pilih Enemy",
        Description = "Klik REFRESH ENEMIES untuk load daftar musuh",
        Values      = {},
        Multi       = false,
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
                    if _taToggleElement then pcall(function() _taToggleElement:SetValue(false) end) end
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
                    if _taToggleElement then pcall(function() _taToggleElement:SetValue(false) end) end
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
    Tabs.Farm:AddButton({
        Title       = " REFRESH ENEMIES",
        Description = "Scan & isi dropdown dengan musuh hidup beserta ID-nya",
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
                if _enemyDropElement then pcall(function() _enemyDropElement:SetValues({}) end) end
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
                pcall(function() _enemyDropElement:SetValues(_enemyDropValues) end)
                -- Fallback jika SetValues tidak tersedia di versi Fluent ini
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
            pcall(function() _taToggleElement:SetValue(false) end)
        end
        if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Target mati  pilih enemy baru & ON lagi") end) end
    end

    _taToggleElement = Tabs.Farm:AddToggle("farmTA", {
        Title       = "TARGET ATTACK",
        Description = "ON = mulai serang target terpilih | OFF = stop",
        Default     = false,
        Callback = function(on)
            if on then
                if not _enemyDropSelected then
                    if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Pilih enemy dulu dari dropdown!") end) end
                    task.defer(function()
                        if _taToggleElement then
                            pcall(function() _taToggleElement:SetValue(false) end)
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
                            if _taToggleElement then pcall(function() _taToggleElement:SetValue(false) end) end
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
                            if _taToggleElement then pcall(function() _taToggleElement:SetValue(false) end) end
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
    Tabs.Farm:AddSection(" FAST ATTACK 1 ENEMYS")

    local _dupePara = Tabs.Farm:AddParagraph({
        Title   = "Status",
        Content = "Idle",
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
    Tabs.Farm:AddButton({
        Title       = "GET",
        Description = "START FIRST",
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
    Tabs.Farm:AddButton({
        Title       = "START",
        Description = "CLICK",
        Callback = function()
            _startSpawn()
        end,
    })

    -- Button STOP (hapus clone + hapus posisi spawn)
    Tabs.Farm:AddButton({
        Title       = "STOP",
        Description = "Delete",
        Callback = function()
            _stopSpawn()
            if not RA.running and not TA.running then
                BlockEnemyHitAnim(false)
            end
        end,
    })

end -- end do TAB: FARM

-- ============================================================================
-- TAB: MASS ATTACK
-- Dipindah dari PANEL: MASS ATTACK (5.lua baris 19513-20787)
-- Konversi API: WindUI -> Fluent
--   MassAttackTab:Section({Title})     -> Tabs.MassAttack:AddSection(title)
--   MassAttackTab:Paragraph({Title,Desc}) -> Tabs.MassAttack:AddParagraph({Title,Content})
--                                          + SetDesc pakai :SetDesc()
--   MassAttackTab:Dropdown({Flag,Title,Desc,Values,Value,Multi,Callback})
--                                       -> Tabs.MassAttack:AddDropdown(Flag,{Title,Description,Values,Multi,Callback})
--   MassAttackTab:Toggle({Flag,Title,Desc,Default,Callback})
--                                       -> Tabs.MassAttack:AddToggle(Flag,{Title,Description,Default,Callback})
--   dropdown:Select(val)   -> dropdownEl:SetValue(val)  (single & multi, val = string atau array string)
--   toggle:Set(v)          -> toggleEl:SetValue(v)
--   toggle:Set(v,false) (silent) -> _suppressXxxCb guard + SetValue(v)
--
-- SEMUA LOGIKA (MODE priority system, SKL skill spam, pull worker, MA RA/TA-style
-- HP-ranked attack thread, AttackLoop_Mass, WaitRaidDone, DoMassAttack) dipindah
-- 100% UTUH tanpa ada 1 baris pun yang berubah dari sisi logika. Hanya layer
-- pembuatan UI (section/paragraph/dropdown/toggle) yang dikonversi ke Fluent API.
--
-- Global expose:
--   _setMaToggleGlobal, _setKillDDGlobal, _setDelayDDGlobal
--   _visMassAtk, _killDDIdxState, _delayDDIdxState
--   _maStatusPara (Paragraph widget untuk status)
--   _maMapSelState, _maMapItemRefs, _maUpdateMapDDLbl
--   _setSkillToggleVis
-- Logika bisnis:
--   MA, MR, SKL, MAPS, FLa_PressKey (inline), MODE, _deadG, ORIGIN_POS
--   TpMap, GetEnemies, IsDead, SaveOrigin, ReturnHRPToOrigin
--   IsEnemyGuidValid, EnsureHeroAtkThreadFor_MA (independen dari FARM)
--   FireAllDamage, FireHeroRemotes, AttackLoop_Mass
--   WaitRaidDone, DoMassAttack
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
    -- [FIX] Parameter kedua dihapus dari signature -- targetPos dihitung REALTIME
    -- tiap kali fire (bukan di-cache sekali di awal), karena posisi musuh terus
    -- bergerak selama pull worker aktif (snap ke depan player tiap Heartbeat).
    -- Kalau pakai posisi lama yang di-passing sekali saja, hero akan tetap
    -- menyerang ke titik lama meski musuh sudah pindah lebih jauh/berbeda.
    local _heroAtkThreads_MA = {}
    local function _findEnemyHRP_MA(g)
        local ENEMY_FOLDERS = {"Enemys","EnemyCityRaid","CityRaidEnemys","Enemies","Enemy"}
        for _, folderName in ipairs(ENEMY_FOLDERS) do
            local f = workspace:FindFirstChild(folderName)
            if f then
                for _, e in ipairs(f:GetChildren()) do
                    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
                        return e:FindFirstChild("HumanoidRootPart")
                    end
                end
            end
        end
        return nil
    end
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
                    -- Hitung targetPos REALTIME (posisi HRP musuh saat ini, sudah
                    -- di-snap pull worker ke depan player), sama seperti FireAttack.
                    local _atkPos = nil
                    do
                        local eHRP = _findEnemyHRP_MA(g)
                        local _char = LP and LP.Character
                        local _pHRP = _char and _char:FindFirstChild("HumanoidRootPart")
                        if eHRP and _pHRP then
                            local ePos  = eHRP.Position
                            local _dir  = (_pHRP.Position - ePos)
                            local _dir2 = Vector3.new(_dir.X, 0, _dir.Z)
                            if _dir2.Magnitude > 0.1 then
                                _atkPos = ePos + _dir2.Unit * 5
                            else
                                _atkPos = ePos + Vector3.new(1,0,0) * 5
                            end
                        end
                    end
                    for _, hGuid in ipairs(HERO_GUIDS) do
                        local last = _lastFire[hGuid] or 0
                        if (tick()-last) >= 1.0 then  -- [EDIT] interval per hero 1 detik
                            _lastFire[hGuid] = tick()
                            if RE.HeroUseSkill then
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g,targetPos=_atkPos}) end)
                                PG_Wait(0.1)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=2,userId=MY_USER_ID,enemyGuid=g,targetPos=_atkPos}) end)
                                PG_Wait(0.1)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=3,userId=MY_USER_ID,enemyGuid=g,targetPos=_atkPos}) end)
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
        local MA_ATTACK_RADIUS = 2000  -- radius SCAN cari musuh (bukan radius kumpul tarikan)
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
                -- Filter radius 50 studs dari posisi player -- musuh manapun (GUID apa saja)
                -- yang masuk radius ini akan ikut ke-scan, tidak peduli identitas GUID-nya.
                local _dist = _playerPos and (h.Position - _playerPos).Magnitude or nil
                if _playerPos and _dist > MA_ATTACK_RADIUS then return end
                seen[g] = true
                table.insert(list, {model=e, guid=g, hrp=h, dist=_dist or 0})
            end
        end
        for _, folderName in ipairs(ENEMY_FOLDERS) do
            local f = workspace:FindFirstChild(folderName)
            if f then for _, e in ipairs(f:GetChildren()) do _addEnemy(e) end end
        end
        if #list == 0 then
            for _, obj in ipairs(workspace:GetChildren()) do _addEnemy(obj) end
        end
        -- [EDIT] Urutkan dari musuh TERDEKAT ke player dulu, supaya Target Kill yang
        -- dipilih konsisten menyerang musuh yang paling dekat dalam radius 50 studs.
        table.sort(list, function(a, b) return a.dist < b.dist end)
        return list
    end

    --  IsDead (identik 1.lua baris ~2155) 
    local function IsDead(e)
        if _deadG[e.guid] then return true end
        if not e.model or not e.model.Parent then return true end
        local h = e.model:FindFirstChildOfClass("Humanoid")
        return not h or h.Health <= 0
    end

    --  FireAllDamage (menyerang by GUID + kirim targetPos realtime ke RE.HeroUseSkill)
    -- [FIX] Sebelumnya enemyPos/targetPos dihapus total dari sini, ternyata
    -- RE.HeroUseSkill di fungsi FireAttack (global, dipakai RAID) memang menerima
    -- field targetPos -- dipakai server untuk memposisikan/mengarahkan hero saat
    -- menyerang. Tanpa targetPos, kemungkinan server memakai posisi lama/default
    -- untuk mengarahkan hero, sehingga hero terlihat menyerang ke tempat lama
    -- walau enemyGuid target sudah benar. targetPos dihitung sama seperti
    -- FireAttack: titik 5 studs dari musuh ke arah player.
    local function FireAllDamage(g, enemyPos)
        if not IsEnemyGuidValid(g) then return end

        local _atkPos = enemyPos
        if enemyPos then
            local _char = LP and LP.Character
            local _pHRP = _char and _char:FindFirstChild("HumanoidRootPart")
            if _pHRP then
                local _dir  = (_pHRP.Position - enemyPos)
                local _dir2 = Vector3.new(_dir.X, 0, _dir.Z)
                if _dir2.Magnitude > 0.1 then
                    _atkPos = enemyPos + _dir2.Unit * 5
                else
                    _atkPos = enemyPos + Vector3.new(1,0,0) * 5
                end
            end
        end

        if RE.Click then
            task.spawn(function()
                if _atkPos then
                    pcall(function() RE.Click:InvokeServer({enemyGuid=g, enemyPos=_atkPos}) end)
                else
                    pcall(function() RE.Click:InvokeServer({enemyGuid=g}) end)
                end
            end)
        end
        if RE.Atk then
            pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end)
        end
        EnsureHeroAtkThreadFor_MA(g, _atkPos)
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
    --  Heartbeat loop: tarik musuh aktif ke 1 titik kumpul di depan player.
    --  Musuh mati → Destroy model (bersihkan mayat).
    --  Cluster: semua musuh (sesuai Kill Target) ditarik ke 1 titik yang sama,
    --           20 studs di depan player, dengan jitter acak kecil (radius 1-2
    --           studs) supaya modelnya tidak saling tindih persis di 1 koordinat.
    -- =========================================================================
    local _pullWorkerConn  = nil   -- RBXScriptConnection Heartbeat
    local _pullTargets     = {}    -- array of {model, guid} yang sedang ditarik
    local _pullDestroyedG  = {}    -- set guid yang sudah di-Destroy (jangan proses ulang)
    local _pullRand        = Random.new()  -- generator jitter (independen math.random global)

    local function _StopEnemyPullWorker()
        if _pullWorkerConn then
            pcall(function() _pullWorkerConn:Disconnect() end)
            _pullWorkerConn = nil
        end
        _pullTargets    = {}
        _pullDestroyedG = {}
    end

    -- _clusterOffset: SEMUA musuh ditarik ke 1 titik yang PERSIS SAMA (tanpa jitter),
    -- supaya boleh saling bertumpuk di 1 koordinat -- sesuai permintaan.
    -- FORWARD: jarak titik kumpul di depan player (5 studs).
    local function _clusterOffset()
        local FORWARD = 5   -- studs di depan player (titik kumpul)
        return 0, FORWARD
    end

    local _pullOwnerSet = {}  -- guid -> true, supaya SetNetworkOwner cuma dicoba sekali per musuh

    local function _StartEnemyPullWorker(targets)
        _StopEnemyPullWorker()
        _pullTargets    = targets  -- array {model=..., guid=...}
        _pullDestroyedG = {}
        _pullOwnerSet   = {}

        -- Assign jitter SEKALI per musuh (menetap) -- bukan dihitung ulang tiap frame,
        -- supaya gerombolan terlihat diam/stabil, bukan bergetar.
        for _, t in ipairs(_pullTargets) do
            t.jitterSide, t.jitterFwd = _clusterOffset()
        end

        _pullWorkerConn = game:GetService("RunService").Heartbeat:Connect(function()
            local lp   = game:GetService("Players").LocalPlayer
            local char = lp and lp.Character
            local pHRP = char and char:FindFirstChild("HumanoidRootPart")
            if not pHRP then return end

            local cf     = pHRP.CFrame
            local right  = cf.RightVector
            local fwd    = cf.LookVector

            for _, t in ipairs(_pullTargets) do
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

                -- Posisi target: 1 titik kumpul di depan player + jitter tetap musuh ini
                local targetPos = pHRP.Position
                    + fwd    * t.jitterFwd
                    + right  * t.jitterSide

                -- Snap HRP musuh ke posisi target
                local eHRP = model:FindFirstChild("HumanoidRootPart")
                if eHRP then
                    -- [FIX] Coba ambil Network Ownership part musuh ke client SEKALI saja.
                    -- Kalau server mengizinkan (tidak di-lock via SetNetworkOwnershipAuto(false)
                    -- atau ownership manual dari server), CFrame yang kita set di bawah akan
                    -- benar-benar replicate ke semua client + server melihat posisi baru ini,
                    -- bukan cuma berubah secara visual di layar kita sendiri.
                    -- Kalau gagal (server memang mengunci ownership NPC), pcall menangkapnya
                    -- dengan aman dan snap CFrame di bawah tetap jalan seperti sebelumnya
                    -- (fallback ke perilaku lama, tidak ada regresi).
                    if not _pullOwnerSet[t.guid] then
                        _pullOwnerSet[t.guid] = true
                        pcall(function()
                            eHRP:SetNetworkOwner(lp)
                        end)
                    end
                    local _ok = pcall(function()
                        eHRP.CFrame = CFrame.new(targetPos, pHRP.Position)
                    end)
                    -- [FIX RACE CONDITION] Tandai musuh ini "settled" (sudah benar-benar
                    -- di-snap ke titik kumpul) setelah snap CFrame pertama berhasil.
                    -- AttackLoop_Mass HANYA boleh menyerang musuh yang settled=true,
                    -- supaya remote serang tidak pernah fire duluan sebelum musuh
                    -- benar-benar sampai di depan player.
                    if _ok then t.settled = true end
                end
            end
        end)
    end

    -- =========================================================================
    --  MASS ATTACK — 2 THREAD INDEPENDEN HP-RANKED (RA-style + TA-style)
    --  Menggantikan pola lama (1 thread spam per-guid untuk SEMUA musuh
    --  sekaligus) dengan 2 thread GLOBAL yang independen satu sama lain,
    --  meniru pola independensi RA & TA di FARM:
    --
    --    - RA-STYLE thread : SELALU menyerang guid dengan HP TERTINGGI di
    --      pullList (alive & settled). Ranking HP dihitung ULANG tiap iterasi
    --      loop langsung dari model.Humanoid.Health (realtime, tanpa cache,
    --      tanpa task.wait() besar). Kalau HP tertinggi pindah ke guid lain
    --      (karena guid lama kena damage / mati), thread ini LANGSUNG switch
    --      guid saat itu juga -- tidak menunggu apapun.
    --
    --    - TA-STYLE thread : SELALU menyerang guid dengan HP TERENDAH,
    --      tapi STICKY -- tetap di guid yang sama selama guid itu masih hidup,
    --      baru naik ke HP terendah berikutnya setelah guid itu benar-benar
    --      mati/hilang dari pullList. Urutannya otomatis: terkecil -> makin
    --      besar, karena ranking dihitung ulang tiap iterasi.
    --      PENGECUALIAN: kalau ada musuh BARU masuk pullList dengan HP lebih
    --      rendah dari target TA yang sedang diserang sekarang, TA-thread
    --      LANGSUNG pindah ke situ (tidak menunggu target lama mati).
    --
    --  Kedua thread ini BOLEH menyerang guid yang sama secara bersamaan
    --  (tidak saling exclude/lock) -- kalau HP tertinggi & terendah kebetulan
    --  jatuh ke 1 guid yang sama (misal cuma tersisa 1 musuh), RA-thread dan
    --  TA-thread tetap jalan paralel ke guid itu.
    --
    --  EnsureHeroAtkThreadFor_MA tetap dipanggil sama seperti sebelumnya:
    --  1x per-guid, hanya saat sebuah thread MULAI menyerang guid baru
    --  (bukan tiap frame) -- fungsi itu sendiri sudah guard idempotent.
    --
    --  Semua state ini LOKAL ke Mass Attack -- tidak menyentuh tabel RA/TA
    --  atau remote RE.Atk/RE.Click yang dipakai FARM.
    -- =========================================================================
    local _MA_RA = {running = false, guid = nil, thread = nil}  -- RA-style: HP tertinggi
    local _MA_TA = {running = false, guid = nil, thread = nil}  -- TA-style: HP terendah, sticky naik

    -- Ambil daftar musuh alive & settled di pullList beserta HP realtime-nya
    -- (langsung dari Humanoid.Health, BUKAN dari remote ShowEnemyTakeDamageInfo
    -- yang cuma broadcast 1 musuh per event -- tidak reliable untuk ranking
    -- banyak musuh sekaligus).
    local function _MA_GetAliveRanked(pullList)
        local out = {}
        for _, t in ipairs(pullList) do
            if not _pullDestroyedG[t.guid] and t.settled then
                local model = t.model
                if model and model.Parent then
                    local hum = model:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        out[#out + 1] = {guid = t.guid, model = model, hp = hum.Health}
                    end
                end
            end
        end
        return out
    end

    -- Fire RE.Click + RE.Atk 1x ke 1 guid (sama persis pola lama, cuma
    -- diekstrak jadi fungsi bersama dipakai RA-thread & TA-thread).
    local function _MA_FireAtGuid(guid, model)
        local eHRP = model and model:FindFirstChild("HumanoidRootPart")
        local ePos = eHRP and eHRP.Position or nil
        local _atkPos = ePos
        if ePos then
            local _char = LP and LP.Character
            local _pHRP = _char and _char:FindFirstChild("HumanoidRootPart")
            if _pHRP then
                local _dir  = (_pHRP.Position - ePos)
                local _dir2 = Vector3.new(_dir.X, 0, _dir.Z)
                if _dir2.Magnitude > 0.1 then
                    _atkPos = ePos + _dir2.Unit * 5
                else
                    _atkPos = ePos + Vector3.new(1,0,0) * 5
                end
            end
        end

        if RE.Click then
            pcall(function()
                if _atkPos then
                    RE.Click:InvokeServer({enemyGuid = guid, enemyPos = _atkPos})
                else
                    RE.Click:InvokeServer({enemyGuid = guid})
                end
            end)
        end
        if RE.Atk then
            pcall(function() RE.Atk:FireServer({attackEnemyGUID = guid}) end)
        end
    end

    -- Hentikan kedua thread (RA + TA). Dipanggil di semua titik keluar
    -- AttackLoop_Mass dan saat DoMassAttack(false) -- nama fungsi sengaja
    -- dipertahankan sama (_MA_StopAllSpam) supaya semua call-site lama tetap
    -- kompatibel tanpa perlu diubah satu-satu.
    local function _MA_StopAllSpam()
        _MA_RA.running = false
        _MA_TA.running = false
        _MA_RA.guid = nil
        _MA_TA.guid = nil
    end

    -- RA-STYLE thread: mulai 1x per AttackLoop_Mass (bukan per-guid, bukan
    -- per-frame) -- thread ini sendiri yang loop terus & re-target ke HP
    -- tertinggi tanpa jeda besar.
    local function _MA_StartRAThread(getPullList)
        if _MA_RA.running then return end
        _MA_RA.running = true
        _MA_RA.thread = task.spawn(function()
            while _MA_RA.running and MA.running do
                local ranked = _MA_GetAliveRanked(getPullList())
                if #ranked == 0 then
                    task.wait()
                else
                    -- Cari HP TERTINGGI di antara semua musuh alive&settled
                    local best = ranked[1]
                    for i = 2, #ranked do
                        if ranked[i].hp > best.hp then best = ranked[i] end
                    end
                    if _MA_RA.guid ~= best.guid then
                        -- Ranking berubah (target lama kena damage/mati, atau
                        -- musuh lain sekarang HP-nya lebih tinggi) -> switch
                        -- guid SEKARANG JUGA, tanpa delay.
                        _MA_RA.guid = best.guid
                        EnsureHeroAtkThreadFor_MA(best.guid)
                    end
                    _MA_FireAtGuid(best.guid, best.model)
                    task.wait()  -- tanpa jeda besar, sama seperti pola tAtk RA di FARM
                end
            end
            _MA_RA.running = false
            _MA_RA.guid = nil
        end)
    end

    -- TA-STYLE thread: mulai 1x per AttackLoop_Mass -- BUKAN lagi sticky ke
    -- 1 guid HP terendah. Sekarang TA-thread menyerang SEMUA EnemyGuid yang
    -- sudah di-teleport/pull ke depan player (sesuai Target Kill yang dipilih)
    -- sekaligus dalam 1 iterasi loop, urutan bebas sesuai hasil
    -- _MA_GetAliveRanked (tidak di-sort ulang). _MA_TA.guid tidak dipakai lagi
    -- untuk sticky-target, hanya disimpan sebagai info guid yang terakhir
    -- diserang (opsional, untuk debug/status).
    local function _MA_StartTAThread(getPullList)
        if _MA_TA.running then return end
        _MA_TA.running = true
        _MA_TA.thread = task.spawn(function()
            while _MA_TA.running and MA.running do
                local ranked = _MA_GetAliveRanked(getPullList())
                if #ranked == 0 then
                    _MA_TA.guid = nil
                    task.wait()
                else
                    -- Serang SEMUA guid alive & settled di pullList, 1x
                    -- EnsureHeroAtkThreadFor_MA + 1x _MA_FireAtGuid per guid
                    -- per iterasi. Urutan bebas (tidak di-ranking).
                    for _, e in ipairs(ranked) do
                        EnsureHeroAtkThreadFor_MA(e.guid)
                        _MA_FireAtGuid(e.guid, e.model)
                    end
                    _MA_TA.guid = ranked[#ranked].guid  -- info terakhir saja, tidak dipakai untuk logic
                    task.wait()  -- tanpa jeda besar, sama seperti pola tAtk RA di FARM
                end
            end
            _MA_TA.running = false
            _MA_TA.guid = nil
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
        if not MA.running then _MA_StopAllSpam(); _StopEnemyPullWorker(); return false end
        if #GetEnemies() == 0 then
            if onStatus then onStatus("Kosong, skip map...") end
            _MA_StopAllSpam()
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

        -- [FIX RACE CONDITION] Tunggu SAMPAI semua musuh di pullList benar-benar
        -- settled (sudah di-snap CFrame minimal 1x oleh pull worker Heartbeat) --
        -- bukan cuma delay buta. Attack loop di bawah baru boleh mulai fire remote
        -- serang setelah musuh benar-benar sampai di titik kumpul depan player.
        -- Timeout 2 detik sebagai fallback safety (misal HRP musuh belum ready).
        do
            local _settleWait = 0
            while MA.running and _settleWait < 2.0 do
                local _allSettled = true
                for _, t in ipairs(pullList) do
                    if not t.settled then _allSettled = false; break end
                end
                if _allSettled then break end
                task.wait(0.03)
                _settleWait = _settleWait + 0.03
            end
        end

        -- Mulai 2 thread independen HP-ranked (RA-style HP tertinggi,
        -- TA-style HP terendah-naik). Sengaja hanya dipanggil SEKALI di sini
        -- (bukan tiap iterasi loop) -- masing-masing thread punya loop
        -- internal sendiri yang re-cek ranking HP & re-target tanpa jeda besar.
        _MA_StartRAThread(function() return pullList end)
        _MA_StartTAThread(function() return pullList end)

        -- FASE 2: Attack loop
        local start    = MA.killed
        local lastKill = MA.killed
        local stuckT   = 0
        local STUCK_LIMIT = 5.0

        while MA.running do
            -- Guard IsAnyMapActive
            do
                local _mBusy, _mWho = IsAnyMapActive()
                if _mBusy then _MA_StopAllSpam(); _StopEnemyPullWorker(); return "interrupted" end
            end
            -- Guard interrupt flags lama (kompatibilitas)
            do local _ni=(MODE.current~="idle" and MODE.current~="ma") or _raidInterrupt or _siegeInterrupt or (ST2 and ST2.running) or (SIEGE and SIEGE.inMap); if _ni then _MA_StopAllSpam(); _StopEnemyPullWorker(); return "interrupted" end end
            -- Guard: hanya serang di basemap 50001-50020
            do
                local ok, wm = pcall(function()
                    return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
                end)
                if ok and type(wm) == "number" then
                    if wm < 50001 or wm > 50020 then _MA_StopAllSpam(); _StopEnemyPullWorker(); return "interrupted" end
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
                _MA_StopAllSpam()
                _StopEnemyPullWorker()
                return true
            end
            -- Kondisi keluar B: kill target terpenuhi
            if not isAll and here >= MA.killTarget then
                if onStatus then onStatus("[OK] Target "..MA.killTarget.." tercapai!") end
                _MA_StopAllSpam()
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
                    _MA_StopAllSpam()
                    _StopEnemyPullWorker()
                    return true
                end
            end

            -- Serang musuh hidup di pullList YANG SUDAH settled (sudah benar-benar
            -- di-snap CFrame ke titik kumpul depan player oleh pull worker).
            -- [FIX RACE CONDITION] Guard radius 50 studs dihapus -- sudah tidak relevan
            -- karena titik kumpul sekarang cuma 5 studs di depan player. Guard yang
            -- benar-benar mencegah race condition adalah flag settled: musuh yang
            -- belum sempat di-snap (misal baru masuk pullList di frame ini) TIDAK
            -- akan diserang sampai posisinya benar-benar sudah di depan player.
            -- [EDIT] RA-style & TA-style thread (_MA_StartRAThread /
            -- _MA_StartTAThread) sudah dimulai sekali sebelum loop ini dan
            -- jalan independen sendiri (re-target HP tanpa jeda besar). Loop
            -- utama di sini cuma jadi exit-condition checker + status updater,
            -- tidak perlu sinkronisasi manual lagi tiap iterasi.
            PG_Wait(0.08)
        end
        _MA_StopAllSpam()
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
                                SafeReequipAfterTeleport("MassAttack")

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
            _MA_StopAllSpam()       -- pastikan semua thread spam RA+TA berhenti saat MA di-OFF
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
    -- FLUENT ELEMENTS  (Tabs.MassAttack)
    -- API: Tab:AddSection(), Tab:AddParagraph(), Tab:AddDropdown(), Tab:AddToggle()
    -- =========================================================================

    --  Section header 
    Tabs.MassAttack:AddSection("Mass Attack")

    --  Status paragraph (ganti _maStatusLbl dari 1.lua) 
    local statusPara = Tabs.MassAttack:AddParagraph({
        Title   = "Status",
        Content = "Idle",
    })
    _maStatusPara = statusPara   -- expose global agar WaitRaidDone bisa update

    --  TARGET KILL dropdown (identik 1.lua baris ~6870) 
    -- Fluent Dropdown, Multi=false
    local _killOptVals  = {5, 10, 15, 20, 0}
    local _killOptNames = {"5", "10", "15", "20", "Kill All"}
    local killDD = Tabs.MassAttack:AddDropdown("maKillDD", {
        Title       = "Target Kill",
        Description = "Jumlah kill sebelum pindah map",
        Multi       = false,
        Values      = _killOptNames,
        Default     = _killOptNames[_killDDIdxState] or _killOptNames[1],
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
            pcall(function() killDD:SetValue(_killOptNames[idx]) end)
            MA.killTarget = _killOptVals[idx]
        end
    end
    -- Set default dari state tersimpan
    if _killOptNames[_killDDIdxState] then
        pcall(function() killDD:SetValue(_killOptNames[_killDDIdxState]) end)
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

    local mapDD  -- forward ref untuk :SetValue() di dalam callback
    -- [FIX v5] Jangan pakai 'local _, mapDD = ...' — itu buat variable baru (mapDD_B = nil,
    -- karena Dropdown hanya return 1 value). _maUpdateMapDDLbl tangkap mapDD_B yg nil
    -- → if not mapDD then return end → visual tidak pernah update.
    -- Pakai assignment biasa (tanpa 'local') agar upvalue mapDD di atas ter-assign.
    mapDD = Tabs.MassAttack:AddDropdown("maMapDD", {
        Title       = "Rotation Map",
        Description = "Pilih map untuk dirotasi (kosong = map sekarang)",
        Multi       = true,
        Values      = _mapOptNames,
        Default     = {},
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
                -- Force visual: inject semua Map 1-20 ke ap.Value via :SetValue()
                local allVal = {"ALL MAP"}
                for i = 1, 20 do table.insert(allVal, "Map "..i) end
                task.defer(function()
                    pcall(function() mapDD:SetValue(allVal) end)
                end)

            elseif not hasAll and _prevHadAll then
                -- ALL MAP baru di-UNCHECK: clear semua
                _prevHadAll = false
                for i = 1, 20 do mapSelSet[i] = nil; MR.selected[i] = nil end
                -- Force visual: kosongkan semua via :SetValue({})  ap.Value={}
                task.defer(function()
                    pcall(function() mapDD:SetValue({}) end)
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
            mapDD:SetValue(selVals)
        end)
    end

    --  DELAY PINDAH MAP dropdown (identik 1.lua baris ~6944) 
    local _delayOptVals  = {1, 3, 5, 7, 10}
    local _delayOptNames = {"1", "3", "5", "7", "10"}
    local delayDD = Tabs.MassAttack:AddDropdown("maDelayDD", {
        Title       = "Delay Pindah Map",
        Description = "Detik tunggu sebelum pindah ke map berikutnya",
        Multi       = false,
        Values      = _delayOptNames,
        Default     = _delayOptNames[_delayDDIdxState] or _delayOptNames[1],
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
            pcall(function() delayDD:SetValue(_delayOptNames[idx]) end)
            MR.nextMapDelay = _delayOptVals[idx]
        end
    end
    if _delayOptNames[_delayDDIdxState] then
        pcall(function() delayDD:SetValue(_delayOptNames[_delayDDIdxState]) end)
        MR.nextMapDelay = _delayOptVals[_delayDDIdxState]
    end

    --  MASS ATTACK master toggle (identik 1.lua baris ~7018) 
    Tabs.MassAttack:AddSection("Control")

    local _suppressMaToggleCb = false
    local maToggle = Tabs.MassAttack:AddToggle("maToggle", {
        Title       = "Mass Attack",
        Description = "Serang semua musuh di map sekaligus",
        Default     = false,
        Callback = function(on)
            if _suppressMaToggleCb then return end
            DoMassAttack(on)
        end,
    })
    -- Expose setter dan visual toggle (kompatibilitas Config panel)
    _setMaToggleGlobal = function(on)
        _suppressMaToggleCb = true
        pcall(function() maToggle:SetValue(on) end)
        _suppressMaToggleCb = false
        DoMassAttack(on)
    end
    _visMassAtk = function(on)
        _suppressMaToggleCb = true
        pcall(function() maToggle:SetValue(on) end)
        _suppressMaToggleCb = false
    end

    --  AUTO SKILL section (identik 1.lua baris ~6954 skillCard) 
    Tabs.MassAttack:AddSection("Auto Skill")

    local _skillKeys = {
        {n="Z", desc="Skill slot Z"},
        {n="X", desc="Skill slot X"},
        {n="C", desc="Skill slot C"},
        {n="V", desc="Skill slot V"},
        {n="F", desc="Skill slot F"},
    }
    -- Simpan elemen toggle per skill key agar bisa di-set saat restore Config
    local _skillToggleEls = {}
    local _suppressSkillCb = {}
    for _, sk in ipairs(_skillKeys) do
        local key = sk.n
        _suppressSkillCb[key] = false
        local el = Tabs.MassAttack:AddToggle("maSkill_"..key, {
            Title       = "Auto Skill "..key,
            Description = sk.desc,
            Default     = false,
            Callback = function(on)
                if _suppressSkillCb[key] then return end
                if on then SkOn(key) else SkOff(key) end
            end,
        })
        _skillToggleEls[key] = el
    end

    -- Expose setter skill visual ke global (dibaca Config panel saat restore)
    -- ApplyConfig memanggil SkOn/SkOff langsung untuk logika,
    -- tapi visual toggle Fluent perlu di-sync secara terpisah
    _setSkillToggleVis = function(key, v)
        local el = _skillToggleEls[key]
        if el then
            _suppressSkillCb[key] = true
            pcall(function() el:SetValue(v) end)
            _suppressSkillCb[key] = false
        end
    end

end -- end do TAB: MASS ATTACK

-- ============================================================================
-- TODO tahap berikutnya: isi Automation, Reroll,
-- Player, Setting, Webhook, Config, Theme.
-- Lihat WindUI_to_Fluent_Mapping.md untuk pola konversi tiap elemen.
-- ============================================================================

Fluent:Notify({
    Title   = "Auto Farming ASH",
    Content = "Skeleton window + 11 tab berhasil dimuat.",
    Duration = 5,
})
