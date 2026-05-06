-- ============================================================
--   Farm GUI - Dual Independent Attack Loop
--   Toggle 1 : Random Attack
--   Toggle 2 : Pilih Musuh (+ Refresh)
--   Aktif bersamaan = damage brutal double layer
-- ============================================================

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local TweenSvc   = game:GetService("TweenService")

local LP         = Players.LocalPlayer
local PG         = LP.PlayerGui

local Remotes    = RS:WaitForChild("Remotes", 30)
local RE = {
    Click        = Remotes:FindFirstChild("ClickEnemy"),
    Atk          = Remotes:FindFirstChild("PlayerClickAttackSkill"),
    HeroUseSkill = Remotes:FindFirstChild("HeroUseSkill"),
    HeroSkill    = Remotes:FindFirstChild("HeroPlaySkillAnim"),
    HeroMove     = Remotes:FindFirstChild("HeroMoveToEnemyPos"),
    Death        = Remotes:FindFirstChild("EnemyDeath"),
    CollectItem  = Remotes:FindFirstChild("CollectItem"),
}

local MY_USER_ID = LP.UserId
local HERO_GUIDS = {}
local _deadG     = {}

local RA = { running=false, threads={}, killed=0, cur=nil }
local TA = { running=false, threads={}, killed=0, cur=nil, targetName=nil }

-- ============================================================
-- HERO GUID CAPTURE
-- ============================================================
local _hookDone = false
local function SetupHook()
    if _hookDone or not RE.HeroUseSkill then return end
    pcall(function()
        local mt   = getrawmetatable(game)
        local _old = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            if self == RE.HeroUseSkill then
                local a = select(1,...)
                if type(a)=="table" and type(a.heroGuid)=="string" then
                    local found=false
                    for _,g in ipairs(HERO_GUIDS) do if g==a.heroGuid then found=true;break end end
                    if not found then table.insert(HERO_GUIDS, a.heroGuid) end
                end
            end
            return _old(self,...)
        end)
        setreadonly(mt, true)
        _hookDone = true
    end)
end
SetupHook()

-- ============================================================
-- DEATH LISTENER
-- ============================================================
if RE.Death then
    RE.Death.OnClientEvent:Connect(function(d)
        if not d then return end
        local g = d.enemyGuid or d.guid
        if g then
            _deadG[g]=true
            if RA.running then RA.killed=RA.killed+1 end
            if TA.running then TA.killed=TA.killed+1 end
        end
    end)
end

-- ============================================================
-- HELPERS
-- ============================================================
local function IsPosValid(hrp)
    if not hrp then return false end
    local p=hrp.Position
    if p.X~=p.X or p.Y~=p.Y or p.Z~=p.Z then return false end
    if math.abs(p.X)>1e10 or math.abs(p.Y)>1e10 or math.abs(p.Z)>1e10 then return false end
    return true
end

local function GetEnemies()
    local list={}
    local f=workspace:FindFirstChild("Enemys")
    if not f then return list end
    for _,e in ipairs(f:GetChildren()) do
        if e:IsA("Model") then
            local g=e:GetAttribute("EnemyGuid")
            local h=e:FindFirstChild("HumanoidRootPart")
            local hum=e:FindFirstChildOfClass("Humanoid")
            if g and h and hum and hum.Health>0 and IsPosValid(h) then
                table.insert(list,{model=e,guid=g,hrp=h})
            end
        end
    end
    return list
end

local function IsDead(e)
    if not e then return true end
    if _deadG[e.guid] then return true end
    if not e.model or not e.model.Parent then return true end
    local h=e.model:FindFirstChildOfClass("Humanoid")
    if not h or h.Health<=0 then return true end
    if not IsPosValid(e.hrp) then return true end
    return false
end

local function FindByName(nm)
    for _,e in ipairs(GetEnemies()) do
        if e.model.Name==nm and not IsDead(e) then return e end
    end
    return nil
end

-- ============================================================
-- TP HELPER
-- ============================================================
local function TpTo(tgt)
    if not tgt or not tgt.hrp then return end
    local char=LP.Character; if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local tgtPos=tgt.hrp.Position
    if tgtPos.Y < -100 then return end
    local OFFSET=4
    local dir=(hrp.Position-tgtPos)
    if dir.Magnitude<0.5 then dir=Vector3.new(1,0,0) end
    dir=Vector3.new(dir.X,0,dir.Z).Unit
    local nearPos=tgtPos+dir*OFFSET
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local ex={}
    if LP.Character then table.insert(ex,LP.Character) end
    local ef=workspace:FindFirstChild("Enemys"); if ef then table.insert(ex,ef) end
    params.FilterDescendantsInstances=ex
    local origins={
        nearPos+Vector3.new(0,20,0),nearPos+Vector3.new(0,10,0),nearPos+Vector3.new(0,5,0),
        tgtPos+Vector3.new(OFFSET,20,0),tgtPos+Vector3.new(-OFFSET,20,0),
        tgtPos+Vector3.new(0,20,OFFSET),tgtPos+Vector3.new(0,20,-OFFSET),
    }
    local safePos
    for _,orig in ipairs(origins) do
        local r=workspace:Raycast(orig,Vector3.new(0,-80,0),params)
        if r and r.Position.Y>=(tgtPos.Y-30) then safePos=r.Position+Vector3.new(0,3,0);break end
    end
    hrp.CFrame=CFrame.new(safePos or nearPos+Vector3.new(0,3,0))
end

-- ============================================================
-- FIRE HELPERS
-- ============================================================
local function FChar(g,pos)
    if RE.Atk then pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end) end
    if RE.Click then task.spawn(function() pcall(function() RE.Click:InvokeServer({enemyGuid=g,enemyPos=pos}) end) end) end
end

local function FHero(g)
    if RE.HeroUseSkill then
        for _,h in ipairs(HERO_GUIDS) do
            for t=1,3 do pcall(function() RE.HeroUseSkill:FireServer({heroGuid=h,attackType=t,userId=MY_USER_ID,enemyGuid=g}) end) end
        end
    end
    if RE.HeroSkill then
        for _,h in ipairs(HERO_GUIDS) do pcall(function() RE.HeroSkill:FireServer({heroGuid=h,enemyGuid=g,skillType=1,masterId=MY_USER_ID}) end) end
    end
    if RE.HeroMove then
        for _,h in ipairs(HERO_GUIDS) do pcall(function() RE.HeroMove:FireServer({attackTarget=g,userId=MY_USER_ID,heroTagetPosInfos={}}) end) end
    end
end

-- ============================================================
-- AUTO COLLECT
-- ============================================================
local function StartCollect(checkFn)
    task.spawn(function()
        local col={}
        while checkFn() do
            for _,fn in ipairs({"Golds","Items","Drops","Rewards"}) do
                local f=workspace:FindFirstChild(fn)
                if f then for _,o in ipairs(f:GetChildren()) do
                    if not checkFn() then break end
                    local g=o:GetAttribute("GUID") or o:GetAttribute("Guid")
                    if g and not col[g] then
                        col[g]=true
                        pcall(function() RE.CollectItem:InvokeServer(g) end)
                        task.wait(0.05)
                    end
                end end
            end
            task.wait(0.25)
        end
    end)
end

-- ============================================================
-- LOOP 1: RANDOM ATTACK
-- Karakter: serang musuh terdekat, TP sekali saat mulai/ganti target
-- Hero: serang musuh yang sama, independen
-- TP hanya kalau TA tidak aktif
-- ============================================================
local function StartRA()
    RA.running=true; RA.killed=0; RA.cur=nil
    RA.threads={}

    local tChar=task.spawn(function()
        local tpT=0
        while RA.running do
            if not RA.cur or IsDead(RA.cur) or not RA.cur.model.Parent then
                _deadG={}; RA.cur=nil
                for _,e in ipairs(GetEnemies()) do
                    if not IsDead(e) then RA.cur=e; break end
                end
                if RA.cur and not TA.running then
                    TpTo(RA.cur); tpT=0
                end
            end
            if RA.cur and not IsDead(RA.cur) and RA.cur.model.Parent then
                FChar(RA.cur.guid, RA.cur.hrp.Position)
                tpT=tpT+task.wait()
                if tpT>=2 and not TA.running then
                    tpT=0; TpTo(RA.cur)
                end
            else
                task.wait()
            end
        end
    end)

    local tHero=task.spawn(function()
        while RA.running do
            if RA.cur and not IsDead(RA.cur) and RA.cur.model.Parent then
                FHero(RA.cur.guid)
            end
            task.wait()
        end
    end)

    RA.threads={tChar,tHero}
    StartCollect(function() return RA.running end)
end

local function StopRA()
    RA.running=false
    for _,t in ipairs(RA.threads) do pcall(function() task.cancel(t) end) end
    RA.threads={}; RA.cur=nil
end

-- ============================================================
-- LOOP 2: TARGET ATTACK
-- Karakter: serang target pilihan, TP langsung saat diaktifkan
-- Hero: serang target pilihan, independen
-- TP selalu dipegang TA saat aktif
-- ============================================================
local function StartTA(targetName, onStatus)
    TA.running=true; TA.killed=0; TA.targetName=targetName; TA.cur=nil
    TA.threads={}

    local tChar=task.spawn(function()
        local lastGuid=nil; local tpT=0
        while TA.running do
            local tgt=FindByName(targetName)
            if not tgt then
                TA.cur=nil
                if onStatus then onStatus("Menunggu ["..targetName.."] respawn...") end
                while TA.running do
                    task.wait(0.3); tgt=FindByName(targetName)
                    if tgt then break end
                end
                if not TA.running then break end
                _deadG={}; lastGuid=nil
            end
            if tgt and not IsDead(tgt) and tgt.model.Parent then
                TA.cur=tgt
                if tgt.guid~=lastGuid then
                    lastGuid=tgt.guid
                    TpTo(tgt); tpT=0
                end
                FChar(tgt.guid, tgt.hrp.Position)
                tpT=tpT+task.wait()
                if tpT>=2 then tpT=0; TpTo(tgt) end
                if onStatus then onStatus(">> ["..targetName.."]  Kill: "..TA.killed) end
            else
                task.wait()
            end
        end
    end)

    local tHero=task.spawn(function()
        while TA.running do
            local tgt=TA.cur
            if tgt and not IsDead(tgt) and tgt.model.Parent then
                FHero(tgt.guid)
            end
            task.wait()
        end
    end)

    TA.threads={tChar,tHero}
    StartCollect(function() return TA.running end)
end

local function StopTA()
    TA.running=false
    for _,t in ipairs(TA.threads) do pcall(function() task.cancel(t) end) end
    TA.threads={}; TA.cur=nil; TA.targetName=nil
end

-- ============================================================
-- GUI
-- ============================================================
local C={
    BG      = Color3.fromRGB(14, 18, 14),
    PANEL   = Color3.fromRGB(22, 30, 22),
    CARD    = Color3.fromRGB(28, 38, 28),
    ACC     = Color3.fromRGB(80, 200, 80),
    ACC2    = Color3.fromRGB(50, 160, 55),
    RED     = Color3.fromRGB(210, 55, 60),
    TXT     = Color3.fromRGB(230, 255, 230),
    DIM     = Color3.fromRGB(110, 150, 110),
    BORD    = Color3.fromRGB(40, 65, 40),
    ON      = Color3.fromRGB(60, 200, 60),
    OFF     = Color3.fromRGB(35, 55, 35),
    KNOB    = Color3.fromRGB(255, 255, 255),
}

if PG:FindFirstChild("FarmGUI") then PG:FindFirstChild("FarmGUI"):Destroy() end

local SG=Instance.new("ScreenGui",PG)
SG.Name="FarmGUI"; SG.ResetOnSpawn=false; SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling

local WIN=Instance.new("Frame",SG)
WIN.Size=UDim2.new(0,280,0,420); WIN.Position=UDim2.new(0.5,-140,0.5,-210)
WIN.BackgroundColor3=C.BG; WIN.BorderSizePixel=0
WIN.Active=true; WIN.Draggable=true
Instance.new("UICorner",WIN).CornerRadius=UDim.new(0,12)
local ws=Instance.new("UIStroke",WIN); ws.Color=C.ACC2; ws.Thickness=1; ws.Transparency=0.5

local TITLE=Instance.new("Frame",WIN)
TITLE.Size=UDim2.new(1,0,0,38); TITLE.BackgroundColor3=Color3.fromRGB(18,26,18); TITLE.BorderSizePixel=0
Instance.new("UICorner",TITLE).CornerRadius=UDim.new(0,12)

local TL=Instance.new("TextLabel",TITLE)
TL.Size=UDim2.new(1,-40,1,0); TL.Position=UDim2.new(0,14,0,0); TL.BackgroundTransparency=1
TL.Text="FARM GUI"; TL.TextSize=13; TL.Font=Enum.Font.GothamBold; TL.TextColor3=C.ACC
TL.TextXAlignment=Enum.TextXAlignment.Left

local CLO=Instance.new("TextButton",TITLE)
CLO.Size=UDim2.new(0,24,0,24); CLO.Position=UDim2.new(1,-30,0.5,-12)
CLO.BackgroundColor3=Color3.fromRGB(200,50,55); CLO.BorderSizePixel=0
CLO.Text="x"; CLO.TextSize=12; CLO.Font=Enum.Font.GothamBold; CLO.TextColor3=Color3.fromRGB(255,255,255)
Instance.new("UICorner",CLO).CornerRadius=UDim.new(1,0)
CLO.MouseButton1Click:Connect(function() SG:Destroy(); StopRA(); StopTA() end)

local CONT=Instance.new("Frame",WIN)
CONT.Size=UDim2.new(1,-16,1,-46); CONT.Position=UDim2.new(0,8,0,42); CONT.BackgroundTransparency=1
local LIST=Instance.new("UIListLayout",CONT)
LIST.Padding=UDim.new(0,8); LIST.SortOrder=Enum.SortOrder.LayoutOrder

local function Card(parent,h,order)
    local f=Instance.new("Frame",parent)
    f.Size=UDim2.new(1,0,0,h); f.LayoutOrder=order
    f.BackgroundColor3=C.PANEL; f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,9)
    Instance.new("UIStroke",f).Color=C.BORD
    return f
end

local function Lbl(parent,txt,size,color,xa)
    local l=Instance.new("TextLabel",parent)
    l.BackgroundTransparency=1; l.Text=txt; l.TextSize=size or 11
    l.Font=Enum.Font.GothamBold; l.TextColor3=color or C.TXT
    l.TextXAlignment=xa or Enum.TextXAlignment.Left; l.TextWrapped=true
    return l
end

local function Pill(parent)
    local pill=Instance.new("Frame",parent)
    pill.Size=UDim2.new(0,44,0,24); pill.BackgroundColor3=C.OFF; pill.BorderSizePixel=0
    Instance.new("UICorner",pill).CornerRadius=UDim.new(1,0)
    local knob=Instance.new("Frame",pill)
    knob.Size=UDim2.new(0,18,0,18); knob.Position=UDim2.new(0,3,0.5,-9)
    knob.BackgroundColor3=C.KNOB; knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)
    local btn=Instance.new("TextButton",pill)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""
    return pill,knob,btn
end

local function SetPill(pill,knob,on)
    pill.BackgroundColor3=on and C.ON or C.OFF
    knob.Position=on and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)
end

-- ── CARD 1: RANDOM ATTACK ──
local c1=Card(CONT,76,1)
local c1T=Lbl(c1,"RANDOM ATTACK",11,C.ACC)
c1T.Size=UDim2.new(0.7,0,0,20); c1T.Position=UDim2.new(0,12,0,10)
local c1S=Lbl(c1,"Serang musuh terdekat otomatis",9,C.DIM)
c1S.Size=UDim2.new(0.8,0,0,16); c1S.Position=UDim2.new(0,12,0,28)
local c1K=Lbl(c1,"STANDBY",9,C.DIM)
c1K.Size=UDim2.new(0.8,0,0,16); c1K.Position=UDim2.new(0,12,0,48)

local raPill,raKnob,raBtn=Pill(c1)
raPill.Position=UDim2.new(1,-56,0.5,-12)

local raOn=false
raBtn.MouseButton1Click:Connect(function()
    raOn=not raOn
    SetPill(raPill,raKnob,raOn)
    if raOn then
        c1T.TextColor3=C.ACC; c1K.TextColor3=C.ON; c1K.Text="AKTIF"
        StartRA()
    else
        StopRA()
        c1T.TextColor3=C.DIM; c1K.TextColor3=C.DIM
        c1K.Text="STOP  Kill: "..RA.killed
    end
end)

task.spawn(function()
    while SG.Parent do
        if raOn then c1K.Text="AKTIF  Kill: "..RA.killed end
        task.wait(0.5)
    end
end)

-- ── CARD 2: PILIH MUSUH ──
local c2=Card(CONT,38,2)
local c2L=Lbl(c2,"PILIH MUSUH",11,C.ACC)
c2L.Size=UDim2.new(0.6,0,1,0); c2L.Position=UDim2.new(0,12,0,0)
c2L.TextYAlignment=Enum.TextYAlignment.Center

local refBtn=Instance.new("TextButton",c2)
refBtn.Size=UDim2.new(0,70,0,24); refBtn.Position=UDim2.new(1,-82,0.5,-12)
refBtn.BackgroundColor3=C.CARD; refBtn.BorderSizePixel=0
refBtn.Text="Refresh"; refBtn.TextSize=10
refBtn.Font=Enum.Font.GothamBold; refBtn.TextColor3=C.ACC
Instance.new("UICorner",refBtn).CornerRadius=UDim.new(0,6)
Instance.new("UIStroke",refBtn).Color=C.ACC2

local c2Stat=Lbl(CONT,"Tekan Refresh untuk muat musuh",9,C.DIM)
c2Stat.Size=UDim2.new(1,0,0,16); c2Stat.LayoutOrder=3

local eScroll=Instance.new("ScrollingFrame",CONT)
eScroll.Size=UDim2.new(1,0,0,160); eScroll.LayoutOrder=4
eScroll.BackgroundColor3=C.PANEL; eScroll.BorderSizePixel=0
eScroll.ScrollBarThickness=3; eScroll.ScrollBarImageColor3=C.ACC
eScroll.CanvasSize=UDim2.new(0,0,0,0); eScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
Instance.new("UICorner",eScroll).CornerRadius=UDim.new(0,9)
Instance.new("UIStroke",eScroll).Color=C.BORD
local ePad=Instance.new("UIPadding",eScroll)
ePad.PaddingTop=UDim.new(0,5); ePad.PaddingBottom=UDim.new(0,5)
ePad.PaddingLeft=UDim.new(0,6); ePad.PaddingRight=UDim.new(0,6)
local eLL=Instance.new("UIListLayout",eScroll)
eLL.Padding=UDim.new(0,4); eLL.SortOrder=Enum.SortOrder.LayoutOrder

local ePH=Instance.new("TextLabel",eScroll)
ePH.Size=UDim2.new(1,0,0,44); ePH.BackgroundTransparency=1
ePH.Text="Tekan Refresh untuk muat daftar musuh"
ePH.TextSize=10; ePH.Font=Enum.Font.GothamBold
ePH.TextColor3=C.DIM; ePH.TextXAlignment=Enum.TextXAlignment.Center; ePH.TextWrapped=true

local eRows={}
local activeRow=nil
local taOn=false

local function StopCurrentTA()
    taOn=false; StopTA()
    if activeRow then
        TweenSvc:Create(activeRow.f,TweenInfo.new(0.12),{BackgroundColor3=C.CARD}):Play()
        activeRow.s.Color=C.BORD; activeRow.n.TextColor3=C.DIM
        SetPill(activeRow.pill,activeRow.knob,false)
        activeRow=nil
    end
    c2Stat.TextColor3=C.DIM; c2Stat.Text="Stop  Kill: "..TA.killed
end

local function RefreshEnemies()
    if taOn then StopCurrentTA() end
    for _,r in pairs(eRows) do if r.f and r.f.Parent then r.f:Destroy() end end
    eRows={}; ePH.Visible=false

    local enemies=GetEnemies()
    if #enemies==0 then
        ePH.Text="Tidak ada musuh di map ini"; ePH.Visible=true
        c2Stat.Text="Map kosong"; return
    end

    local nc={}
    for _,e in ipairs(enemies) do nc[e.model.Name]=(nc[e.model.Name] or 0)+1 end
    local names={}
    for nm in pairs(nc) do table.insert(names,nm) end
    table.sort(names)

    for idx,nm in ipairs(names) do
        local row=Instance.new("Frame",eScroll)
        row.Size=UDim2.new(1,0,0,36); row.LayoutOrder=idx
        row.BackgroundColor3=C.CARD; row.BorderSizePixel=0
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
        local rs=Instance.new("UIStroke",row); rs.Color=C.BORD; rs.Thickness=1

        local nL=Instance.new("TextLabel",row)
        nL.Size=UDim2.new(1,-80,1,0); nL.Position=UDim2.new(0,10,0,0)
        nL.BackgroundTransparency=1; nL.Text=nm; nL.TextSize=12
        nL.Font=Enum.Font.GothamBold; nL.TextColor3=C.DIM
        nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd

        local cL=Instance.new("TextLabel",row)
        cL.Size=UDim2.new(0,28,1,0); cL.Position=UDim2.new(1,-72,0,0)
        cL.BackgroundTransparency=1; cL.Text="x"..nc[nm]; cL.TextSize=10
        cL.Font=Enum.Font.GothamBold; cL.TextColor3=C.DIM
        cL.TextXAlignment=Enum.TextXAlignment.Right

        local pill,knob,btn=Pill(row)
        pill.Position=UDim2.new(1,-46,0.5,-12)

        local rd={f=row,s=rs,n=nL,c=cL,pill=pill,knob=knob}
        eRows[nm]=rd

        btn.MouseButton1Click:Connect(function()
            if taOn and activeRow==rd then
                StopCurrentTA()
            else
                if taOn then StopCurrentTA() end
                taOn=true; activeRow=rd
                TweenSvc:Create(row,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(28,52,28)}):Play()
                rs.Color=C.ACC; nL.TextColor3=C.TXT
                SetPill(pill,knob,true)
                c2Stat.TextColor3=C.ACC; c2Stat.Text=">> ["..nm.."]"
                StartTA(nm,function(msg) c2Stat.Text=msg end)
            end
        end)
    end

    c2Stat.Text=#names.." jenis  "..#enemies.." total"
    c2Stat.TextColor3=C.DIM

    task.spawn(function()
        while SG.Parent and #names>0 do
            local live={}
            for _,e in ipairs(GetEnemies()) do
                if not IsDead(e) then live[e.model.Name]=(live[e.model.Name] or 0)+1 end
            end
            for _,nm2 in ipairs(names) do
                local r=eRows[nm2]; if not r then continue end
                local a=live[nm2] or 0
                r.c.Text="x"..a
                r.c.TextColor3=a==0 and C.RED or C.DIM
            end
            if taOn then c2Stat.Text=">> ["..(TA.targetName or "?").."]  Kill: "..TA.killed end
            task.wait(0.5)
        end
    end)
end

refBtn.MouseButton1Click:Connect(function()
    refBtn.Text="Loading..."
    task.spawn(function() RefreshEnemies(); task.wait(0.3); refBtn.Text="Refresh" end)
end)

-- ── FOOTER ──
local footer=Card(CONT,28,5)
local footL=Lbl(footer,"Mode: STANDBY",9,C.DIM)
footL.Size=UDim2.new(1,-12,1,0); footL.Position=UDim2.new(0,10,0,0)

task.spawn(function()
    while SG.Parent do
        if raOn and taOn then
            footL.Text="BRUTAL  RA:"..RA.killed.." TA:"..TA.killed
            footL.TextColor3=C.ON
        elseif raOn then
            footL.Text="Random Attack  Kill: "..RA.killed
            footL.TextColor3=C.ACC
        elseif taOn then
            footL.Text="Target Musuh  Kill: "..TA.killed
            footL.TextColor3=C.ACC
        else
            footL.Text="Mode: STANDBY"
            footL.TextColor3=C.DIM
        end
        task.wait(0.5)
    end
end)

warn("[FARM GUI] Loaded")
