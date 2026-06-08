-- ============================================================
-- BUFF UI SNIFFER - FLa Project
-- Cari TextLabel yang isinya berubah (timer countdown buff)
-- Jalankan saat buff aktif, pantau [TIMER?] di console
-- ============================================================

local Players   = game:GetService("Players")
local lp        = Players.LocalPlayer
local playerGui = lp:WaitForChild("PlayerGui", 10)

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

-- Cek apakah string mengandung angka (kemungkinan timer)
local function looksLikeTimer(str)
    if not str or str == "" then return false end
    -- Match: "1:30", "01:30", "90", "1m30s", "30s", "00:01:30"
    if str:match("%d+:%d+") then return true end
    if str:match("%d+[ms]") then return true end
    if str:match("^%d+$") and tonumber(str) and tonumber(str) > 0 and tonumber(str) < 99999 then return true end
    return false
end

local watched  = {}
local snapshots = {}

--  Snapshot semua TextLabel saat ini 
local function snapshotAll()
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local ok, txt = pcall(function() return obj.Text end)
            if ok and txt and txt ~= "" then
                local path = getPath(obj)
                snapshots[path] = {obj=obj, text=txt}
            end
        end
    end
end

--  Watch semua TextLabel untuk perubahan 
local function watchAll()
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
            local path = getPath(obj)
            if not watched[path] then
                watched[path] = true
                local lastTxt = ""
                pcall(function() lastTxt = obj.Text end)

                obj:GetPropertyChangedSignal("Text"):Connect(function()
                    local newTxt = ""
                    pcall(function() newTxt = obj.Text end)
                    if newTxt == lastTxt then return end

                    -- Cek apakah perubahan ini seperti timer
                    local isTimer = looksLikeTimer(newTxt) or looksLikeTimer(lastTxt)
                    if isTimer then
                        warn(string.format("[TIMER?] %s: '%s' -> '%s' | PATH: %s",
                            obj.Name, lastTxt, newTxt, path))
                    else
                        -- Print semua perubahan text (mungkin buff name/status)
                        if #newTxt < 60 then
                            print(string.format("[TEXT CHANGE] %s: '%s' -> '%s'",
                                obj.Name, lastTxt, newTxt))
                        end
                    end
                    lastTxt = newTxt
                end)
            end
        end
    end
end

--  Watch DescendantAdded (GUI baru yang muncul saat buff) 
playerGui.DescendantAdded:Connect(function(obj)
    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
        task.wait(0.1)
        local txt = ""
        pcall(function() txt = obj.Text end)
        local path = getPath(obj)

        if looksLikeTimer(txt) then
            warn(string.format("[NEW TIMER] '%s' = '%s' | PATH: %s", obj.Name, txt, path))
        elseif txt ~= "" then
            print(string.format("[NEW TEXT] '%s' = '%s' | PATH: %s", obj.Name, txt, path))
        end

        -- Langsung watch juga
        if not watched[path] then
            watched[path] = true
            local lastTxt = txt
            obj:GetPropertyChangedSignal("Text"):Connect(function()
                local newTxt = ""
                pcall(function() newTxt = obj.Text end)
                if newTxt == lastTxt then return end
                local isTimer = looksLikeTimer(newTxt) or looksLikeTimer(lastTxt)
                if isTimer then
                    warn(string.format("[TIMER?] %s: '%s' -> '%s' | PATH: %s",
                        obj.Name, lastTxt, newTxt, path))
                end
                lastTxt = newTxt
            end)
        end
    end

    -- Watch juga ScreenGui baru (buff panel yang muncul)
    if obj:IsA("ScreenGui") then
        warn(string.format("[NEW ScreenGui] '%s' Enabled=%s | PATH: %s",
            obj.Name, tostring(obj.Enabled), getPath(obj)))
    end
end)

--  Print semua TextLabel yang isinya seperti timer 
print("")
print("====== BUFF UI SNIFFER AKTIF ======")
print("Scanning semua TextLabel yang tampak seperti timer...")
print("")

snapshotAll()
local timerCandidates = 0
for path, data in pairs(snapshots) do
    if looksLikeTimer(data.text) then
        warn(string.format("[TIMER CANDIDATE] '%s' = '%s' | PATH: %s",
            data.obj.Name, data.text, path))
        timerCandidates = timerCandidates + 1
    end
end

if timerCandidates == 0 then
    print("Tidak ada TextLabel dengan format timer ditemukan saat ini.")
    print("Pantau [TIMER?] dan [NEW TIMER] saat buff aktif/muncul.")
else
    print(string.format("Total timer candidates: %d", timerCandidates))
end

print("")
watchAll()
print("Watch aktif pada " .. tostring(#playerGui:GetDescendants()) .. " descendants")
print("Pantau [TIMER?] di console - itu lokasi timer buff")
print("====================================")
