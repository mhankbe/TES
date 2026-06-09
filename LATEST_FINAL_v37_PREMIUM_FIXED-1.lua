-- Hook SEMUA remote event, print yang fire saat buff aktif
-- Jalankan dulu, lalu tunggu/aktifkan buff

local RS  = game:GetService("ReplicatedStorage")
local hooked = {}
local count = 0

local function hookRemote(r)
    local id = r:GetFullName()
    if hooked[id] then return end
    hooked[id] = true
    count = count + 1
    r.OnClientEvent:Connect(function(...)
        local args = {...}
        local parts = {}
        for _, v in ipairs(args) do
            local t = typeof(v)
            if t == "table" then
                local kp = {}
                for k, val in pairs(v) do
                    table.insert(kp, tostring(k).."="..tostring(val))
                    if #kp >= 6 then table.insert(kp,"..."); break end
                end
                table.insert(parts, "{"..table.concat(kp,",").."}")
            else
                table.insert(parts, t..":"..tostring(v))
            end
        end
        warn("[FIRE] "..r.Name.." | "..table.concat(parts," | "))
    end)
end

for _, obj in ipairs(RS:GetDescendants()) do
    if obj:IsA("RemoteEvent") then pcall(hookRemote, obj) end
end

RS.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") then pcall(hookRemote, obj) end
end)

print("Hooked "..count.." remote events")
print("Sekarang aktifkan buff / tunggu buff muncul")
print("Semua remote yang fire akan muncul sebagai [FIRE]")
