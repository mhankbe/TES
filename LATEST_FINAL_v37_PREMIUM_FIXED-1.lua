-- ============================================================
-- BUFF TIMER SNIFFER - FLa Project
-- Khusus intercept UpdateBuffTimes remote event
-- Cari nilai awal timer saat buff baru aktif
-- ============================================================

local RS  = game:GetService("ReplicatedStorage")
local lp  = game:GetService("Players").LocalPlayer

local remote = nil
pcall(function()
    remote = RS:FindFirstChild("Remotes")
          and RS.Remotes:FindFirstChild("UpdateBuffTimes")
end)

if not remote then
    -- Cari recursive
    for _, obj in ipairs(RS:GetDescendants()) do
        if obj:IsA("RemoteEvent") and obj.Name == "UpdateBuffTimes" then
            remote = obj
            break
        end
    end
end

if not remote then
    warn("UpdateBuffTimes tidak ditemukan!")
else
    print("Remote ditemukan: " .. remote:GetFullName())
    print("Pantau semua buff ID dan timer-nya di bawah ini:")
    print("============================================================")

    local knownBuffs = {}

    remote.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then
            warn("DATA BUKAN TABLE: " .. tostring(data))
            return
        end

        -- Print semua entry dalam table
        for buffId, timeVal in pairs(data) do
            local id  = tostring(buffId)
            local val = tonumber(timeVal) or 0
            local prev = knownBuffs[id]

            if prev == nil then
                -- Buff baru pertama kali terdeteksi
                warn(string.format("[NEW BUFF] ID=%s | Timer=%s detik (~%.1f menit)",
                    id, tostring(val), val/60))
            elseif val ~= prev then
                -- Nilai berubah
                if val > prev then
                    warn(string.format("[BUFF RENEWED] ID=%s | %s -> %s (naik = buff di-refresh)",
                        id, tostring(prev), tostring(val)))
                elseif val == 0 and prev > 0 then
                    warn(string.format("[BUFF EXPIRED] ID=%s | Timer habis", id))
                else
                    print(string.format("[BUFF TICK] ID=%s | %s -> %s",
                        id, tostring(prev), tostring(val)))
                end
            end

            knownBuffs[id] = val
        end
    end)

    print("Sniffer aktif - tunggu buff baru muncul atau buff aktif di-refresh")
    print("[NEW BUFF]     = buff baru terdeteksi + nilai timer awalnya")
    print("[BUFF TICK]    = timer berkurang tiap update")
    print("[BUFF RENEWED] = buff di-refresh/diperpanjang")
    print("[BUFF EXPIRED] = timer habis")
    print("============================================================")
end
