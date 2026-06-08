-- ============================================================
-- BUFF SNIFFER - FLa Project
-- Tujuan: Cari lokasi data buff + timer di game
-- Jalankan saat buff aktif (Blessing Gold atau buff apapun)
-- ============================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local lp           = Players.LocalPlayer
local playerGui    = lp:WaitForChild("PlayerGui", 10)
local char         = lp.Character or lp.CharacterAdded:Wait()

-- Kata kunci yang dicari
local BUFF_KEYS = {
    "buff","blessing","gold","boost","bonus","effect","aura",
    "timer","duration","expire","time","active","status",
    "multiplier","rate","drop","enhance","power","lucky",
    "fortune","reward","gain","increase","buff_list","buffs",
}

local function containsKey(str)
    local s = str:lower()
    for _, k in ipairs(BUFF_KEYS) do
        if s:find(k, 1, true) then return true, k end
    end
    return false, nil
end

local function getPath(obj)
    local parts = {}
    local cur, depth = obj, 0
    while cur and cur ~= game and depth < 10 do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
        depth = depth + 1
    end
    return table.concat(parts, ".")
end

local results = {}
local seen = {}

local function record(obj, reason)
    local path = getPath(obj)
    if seen[path] then return end
    seen[path] = true
    local val = ""
    pcall(function()
        if obj:IsA("NumberValue") or obj:IsA("IntValue")
        or obj:IsA("StringValue") or obj:IsA("BoolValue") then
            val = " = " .. tostring(obj.Value)
        end
    end)
    table.insert(results, {
        name   = obj.Name,
        class  = obj.ClassName,
        path   = path,
        reason = reason,
        val    = val,
    })
    print(string.format("[BUFF?] %s (%s)%s | %s | PATH: %s",
        obj.Name, obj.ClassName, val, reason, path))
end

--  Scan rekursif 
local function scanObj(obj, depth)
    if depth > 10 then return end
    local ok, children = pcall(function() return obj:GetChildren() end)
    if not ok then return end
    for _, child in ipairs(children) do
        local match, kw = containsKey(child.Name)

        -- Match nama
        if match then
            record(child, "nama mengandung '" .. kw .. "'")
        end

        -- NumberValue / IntValue dengan nilai > 0 (bisa timer detik)
        if (child:IsA("NumberValue") or child:IsA("IntValue")) then
            local v = 0
            pcall(function() v = child.Value end)
            if v > 0 and v < 99999 then
                record(child, "NumberValue aktif = " .. tostring(v))
            end
        end

        -- StringValue yang isinya mengandung kata buff
        if child:IsA("StringValue") then
            local v = ""
            pcall(function() v = child.Value end)
            local m, k2 = containsKey(v)
            if m then
                record(child, "StringValue berisi '" .. k2 .. "'")
            end
        end

        -- Scan lebih dalam
        pcall(scanObj, child, depth + 1)
    end
end

--  Target scan 
print("")
print("====== BUFF SNIFFER AKTIF ======")
print("Scanning saat Blessing Gold aktif...")
print("")

-- 1. PlayerGui
print("[SCAN] PlayerGui...")
pcall(scanObj, playerGui, 0)

-- 2. LocalPlayer instance
print("[SCAN] LocalPlayer...")
pcall(scanObj, lp, 0)

-- 3. Karakter player
print("[SCAN] Character...")
pcall(scanObj, char, 0)

-- 4. ReplicatedStorage
print("[SCAN] ReplicatedStorage...")
local rs = game:GetService("ReplicatedStorage")
pcall(scanObj, rs, 0)

-- 5. Workspace global
print("[SCAN] Workspace (shallow)...")
for _, obj in ipairs(workspace:GetChildren()) do
    local match, kw = containsKey(obj.Name)
    if match then record(obj, "workspace child '" .. kw .. "'") end
    -- 1 level dalam saja untuk workspace (terlalu besar)
    pcall(function()
        for _, child in ipairs(obj:GetChildren()) do
            local m, k = containsKey(child.Name)
            if m then record(child, "workspace.child '" .. k .. "'") end
        end
    end)
end

--  Sniff RemoteEvent terkait buff 
print("")
print("[SCAN] Remote Events terkait buff...")
local hookedRemotes = {}
local function hookRemote(remote)
    if hookedRemotes[remote:GetFullName()] then return end
    local match, kw = containsKey(remote.Name)
    if not match then return end
    hookedRemotes[remote:GetFullName()] = true
    print(string.format("[REMOTE BUFF] Hook: %s | keyword: %s", remote:GetFullName(), kw))
    remote.OnClientEvent:Connect(function(...)
        local args = {...}
        local parts = {}
        for i, v in ipairs(args) do
            local t2 = typeof(v)
            if t2 == "table" then
                local kparts = {}
                for k, val in pairs(v) do
                    table.insert(kparts, tostring(k).."="..tostring(val))
                    if #kparts >= 8 then break end
                end
                table.insert(parts, "{"..table.concat(kparts,",").."}")
            else
                table.insert(parts, tostring(v))
            end
        end
        warn(string.format("[BUFF EVENT] %s FIRED | %s", remote.Name, table.concat(parts, " | ")))
    end)
end

for _, obj in ipairs(rs:GetDescendants()) do
    if obj:IsA("RemoteEvent") then
        pcall(hookRemote, obj)
    end
end

--  Watch perubahan value secara real-time 
print("")
print("[WATCH] Memantau perubahan NumberValue/IntValue secara real-time...")
print("Pantau console - nilai yang berubah tiap detik = timer buff")
print("")

local watchList = {}
local function watchObj(obj, depth)
    if depth > 8 then return end
    local ok, children = pcall(function() return obj:GetChildren() end)
    if not ok then return end
    for _, child in ipairs(children) do
        if child:IsA("NumberValue") or child:IsA("IntValue") then
            local v = 0
            pcall(function() v = child.Value end)
            if v > 0 and v < 99999 then
                local path = getPath(child)
                if not watchList[path] then
                    watchList[path] = {obj=child, last=v}
                    child:GetPropertyChangedSignal("Value"):Connect(function()
                        local newV = 0
                        pcall(function() newV = child.Value end)
                        warn(string.format("[VALUE CHANGE] %s: %s -> %s | PATH: %s",
                            child.Name, tostring(watchList[path].last), tostring(newV), path))
                        watchList[path].last = newV
                    end)
                end
            end
        end
        pcall(watchObj, child, depth + 1)
    end
end

pcall(watchObj, playerGui, 0)
pcall(watchObj, lp, 0)
pcall(watchObj, char, 0)

--  Summary setelah 3 detik 
task.wait(3)
print("")
print("====== SUMMARY (" .. #results .. " kandidat ditemukan) ======")
if #results == 0 then
    print("Tidak ada kandidat buff ditemukan dari scan statis.")
    print("Pantau [BUFF EVENT] dan [VALUE CHANGE] di console saat buff muncul/habis.")
else
    for i, r in ipairs(results) do
        print(string.format("[%2d] %s (%s)%s | %s", i, r.name, r.class, r.val, r.path))
    end
end
print("")
print("Sniffer tetap aktif - pantau [VALUE CHANGE] untuk timer buff")
print("====== END SUMMARY ======")
