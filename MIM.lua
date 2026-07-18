local MIMIndex = require("MIMIndex")

local args = { ... }

local function usage()
    print("Usage:")
    print("  MIM attach <name> [priority]")
    print("  MIM detach <name>")
    print("  MIM list")
    print("  MIM deposit")
end

local function requireInventory(name)
    if not peripheral.isPresent(name) then
        error("peripheral is not present: " .. name, 0)
    end
    if not peripheral.hasType(name, "inventory") then
        error("peripheral is not an inventory: " .. name, 0)
    end
end

local function attach()
    if not args[2] or args[4] then
        usage()
        error("attach requires a name and optional priority", 0)
    end
    requireInventory(args[2])
    local priority
    if args[3] then
        priority = tonumber(args[3])
        if not priority or priority < 1 or priority % 1 ~= 0 then
            error("priority must be a positive integer", 0)
        end
    end
    local index = MIMIndex.load()
    local entry = MIMIndex.attach(index, args[2], priority)
    MIMIndex.save(index)
    print("Attached " .. entry.name .. " at priority " .. entry.priority)
end

local function detach()
    if not args[2] or args[3] then
        usage()
        error("detach requires exactly one name", 0)
    end
    local index = MIMIndex.load()
    local entry = MIMIndex.detach(index, args[2])
    if not entry then
        error("inventory is not attached: " .. args[2], 0)
    end
    MIMIndex.save(index)
    print("Detached " .. entry.name)
    if entry.priority == 1 then
        print("Warning: deposit will fail until an inventory is attached at priority 1")
    end
end

local function filterSummary(entry)
    local parts = {}
    if entry.allow then
        table.insert(parts, "allow=" .. table.concat(entry.allow, ","))
    end
    if entry.deny then
        table.insert(parts, "deny=" .. table.concat(entry.deny, ","))
    end
    if #parts == 0 then
        return "all items"
    end
    return table.concat(parts, "; ")
end

local function inventoryUsage(name)
    if not peripheral.isPresent(name) or not peripheral.hasType(name, "inventory") then
        return nil
    end
    local inventory = peripheral.wrap(name)
    local listOk, contents = pcall(inventory.list)
    local sizeOk, size = pcall(inventory.size)
    if not listOk or not sizeOk then
        return nil
    end
    local count = 0
    for _, item in pairs(contents) do
        count = count + item.count
    end
    return count, size
end

local function list()
    if args[2] then
        usage()
        error("list does not take arguments", 0)
    end
    local index = MIMIndex.load()
    local entries = {}
    for _, entry in ipairs(index.entries) do
        table.insert(entries, entry)
    end
    table.sort(entries, function(a, b)
        return a.priority < b.priority
    end)
    if #entries == 0 then
        print("No inventories attached")
        return
    end
    for _, entry in ipairs(entries) do
        local count, capacity = inventoryUsage(entry.name)
        local status
        if count then
            status = count .. " items / " .. capacity .. " slots"
        else
            status = "OFFLINE"
        end
        print(entry.priority .. "  " .. entry.name .. "  " .. status .. "  " .. filterSummary(entry))
    end
end

local function loadOutput(entry)
    if not peripheral.isPresent(entry.name) or not peripheral.hasType(entry.name, "inventory") then
        print("Warning: skipping offline output " .. entry.name)
        return nil
    end
    local inventory = peripheral.wrap(entry.name)
    local listOk, contents = pcall(inventory.list)
    local sizeOk, size = pcall(inventory.size)
    if not listOk or not sizeOk then
        print("Warning: skipping offline output " .. entry.name)
        return nil
    end
    return {
        entry = entry,
        inventory = inventory,
        contents = contents,
        size = size,
        online = true,
    }
end

local function transfer(input, output, fromSlot, amount, toSlot)
    if not output.online or amount <= 0 then
        return 0
    end
    local ok, moved = pcall(input.pushItems, output.entry.name, fromSlot, amount, toSlot)
    if not ok then
        output.online = false
        print("Warning: output went offline: " .. output.entry.name)
        return 0
    end
    return moved or 0
end

local function getMaxCount(input, slot, itemName, cache)
    if cache[itemName] then
        return cache[itemName]
    end
    local ok, detail = pcall(input.getItemDetail, slot)
    if not ok or not detail then
        error("unable to inspect input slot " .. slot, 0)
    end
    cache[itemName] = detail.maxCount or 64
    return cache[itemName]
end

local function deposit()
    if args[2] then
        usage()
        error("deposit does not take arguments", 0)
    end
    local index = MIMIndex.load()
    local inputEntry = MIMIndex.input(index)
    if not inputEntry then
        error("no input is attached; use MIM attach <name> 1", 0)
    end
    requireInventory(inputEntry.name)
    local outputEntries = MIMIndex.outputs(index)
    if #outputEntries == 0 then
        error("no outputs are attached; use MIM attach <name> [priority]", 0)
    end

    local input = peripheral.wrap(inputEntry.name)
    local listOk, inputContents = pcall(input.list)
    if not listOk then
        error("unable to read input inventory " .. inputEntry.name, 0)
    end
    if next(inputContents) == nil then
        print("Nothing to deposit")
        return
    end

    local outputs = {}
    for _, entry in ipairs(outputEntries) do
        local output = loadOutput(entry)
        if output then
            table.insert(outputs, output)
        end
    end

    local remaining = {}
    local maxCounts = {}
    local total = 0
    for slot, item in pairs(inputContents) do
        remaining[slot] = item.count
        total = total + item.count
    end

    for slot, item in pairs(inputContents) do
        local maxCount = getMaxCount(input, slot, item.name, maxCounts)
        if maxCount > 1 then
            for _, output in ipairs(outputs) do
                if remaining[slot] == 0 then
                    break
                end
                if output.online and MIMIndex.accepts(output.entry, item.name) then
                    for targetSlot, target in pairs(output.contents) do
                        if remaining[slot] == 0 then
                            break
                        end
                        if target.name == item.name and target.count < maxCount then
                            local moved = transfer(input, output, slot, math.min(remaining[slot], maxCount - target.count), targetSlot)
                            remaining[slot] = remaining[slot] - moved
                            target.count = target.count + moved
                        end
                    end
                end
            end
        end
    end

    for slot, item in pairs(inputContents) do
        local maxCount = maxCounts[item.name] or getMaxCount(input, slot, item.name, maxCounts)
        for _, output in ipairs(outputs) do
            if remaining[slot] == 0 then
                break
            end
            if output.online and MIMIndex.accepts(output.entry, item.name) then
                for targetSlot = 1, output.size do
                    if remaining[slot] == 0 then
                        break
                    end
                    if output.contents[targetSlot] == nil then
                        local moved = transfer(input, output, slot, math.min(remaining[slot], maxCount), targetSlot)
                        remaining[slot] = remaining[slot] - moved
                        if moved > 0 then
                            output.contents[targetSlot] = {
                                name = item.name,
                                count = moved,
                            }
                        end
                    end
                end
            end
        end
    end

    local left = 0
    local rejected = {}
    local noRoom = {}
    for slot, item in pairs(inputContents) do
        local count = remaining[slot]
        if count > 0 then
            left = left + count
            local accepted = false
            for _, output in ipairs(outputs) do
                if MIMIndex.accepts(output.entry, item.name) then
                    accepted = true
                    break
                end
            end
            local reasons = accepted and noRoom or rejected
            reasons[item.name] = (reasons[item.name] or 0) + count
        end
    end

    print("Moved " .. (total - left) .. " items; " .. left .. " left behind")
    for name, count in pairs(rejected) do
        print("  " .. count .. " x " .. name .. ": rejected")
    end
    for name, count in pairs(noRoom) do
        print("  " .. count .. " x " .. name .. ": no room")
    end
end

local commands = {
    attach = attach,
    detach = detach,
    list = list,
    deposit = deposit,
}

local command = commands[args[1]]
if not command then
    usage()
    if args[1] then
        error("unknown command: " .. args[1], 0)
    end
    return
end
command()
