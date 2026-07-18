local MIMIndex = {}

local INDEX_FILE = "mim_index.tbl"
local VERSION = 1

local function emptyIndex()
    return {
        version = VERSION,
        entries = {},
    }
end

local function validatePatterns(patterns, field, name)
    if patterns == nil then
        return
    end
    if type(patterns) ~= "table" then
        error(field .. " filters for " .. name .. " must be a list", 0)
    end
    for i, pattern in ipairs(patterns) do
        if type(pattern) ~= "string" then
            error(field .. " filter " .. i .. " for " .. name .. " must be a string", 0)
        end
        local valid = pcall(string.find, "", pattern)
        if not valid then
            error(field .. " filter " .. i .. " for " .. name .. " is not a valid Lua pattern", 0)
        end
    end
    for key in pairs(patterns) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #patterns then
            error(field .. " filters for " .. name .. " must be a list", 0)
        end
    end
end

local function validate(index)
    if type(index) ~= "table" then
        error("MIM index must be a table", 0)
    end
    if index.version ~= VERSION then
        error("unsupported MIM index version: " .. tostring(index.version), 0)
    end
    if type(index.entries) ~= "table" then
        error("MIM index entries must be a list", 0)
    end

    local names = {}
    local priorities = {}
    local count = 0
    for i, entry in ipairs(index.entries) do
        count = count + 1
        if type(entry) ~= "table" then
            error("MIM index entry " .. i .. " must be a table", 0)
        end
        if type(entry.name) ~= "string" or entry.name == "" then
            error("MIM index entry " .. i .. " has an invalid name", 0)
        end
        if type(entry.priority) ~= "number" or entry.priority < 1 or entry.priority % 1 ~= 0 then
            error("MIM index entry " .. entry.name .. " has an invalid priority", 0)
        end
        if names[entry.name] then
            error("MIM index contains duplicate inventory " .. entry.name, 0)
        end
        if priorities[entry.priority] then
            error("MIM index priority " .. entry.priority .. " is shared by " .. priorities[entry.priority] .. " and " .. entry.name, 0)
        end
        validatePatterns(entry.allow, "allow", entry.name)
        validatePatterns(entry.deny, "deny", entry.name)
        names[entry.name] = true
        priorities[entry.priority] = entry.name
    end
    for key in pairs(index.entries) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            error("MIM index entries must be a list", 0)
        end
    end
    return index
end

local function copyPatterns(patterns)
    if patterns == nil then
        return nil
    end
    local copy = {}
    for i, pattern in ipairs(patterns) do
        copy[i] = pattern
    end
    return copy
end

function MIMIndex.load()
    if not fs.exists(INDEX_FILE) then
        return emptyIndex()
    end
    if fs.isDir(INDEX_FILE) then
        error(INDEX_FILE .. " is a directory", 0)
    end
    local handle, openError = fs.open(INDEX_FILE, "r")
    if not handle then
        error("unable to open " .. INDEX_FILE .. ": " .. tostring(openError), 0)
    end
    local contents = handle.readAll()
    handle.close()
    local index = textutils.unserialize(contents)
    if index == nil then
        error("unable to parse " .. INDEX_FILE, 0)
    end
    return validate(index)
end

function MIMIndex.save(index)
    validate(index)
    local handle, openError = fs.open(INDEX_FILE, "w")
    if not handle then
        error("unable to open " .. INDEX_FILE .. ": " .. tostring(openError), 0)
    end
    handle.write(textutils.serialize(index))
    handle.close()
end

function MIMIndex.attach(index, name, priority, filters)
    validate(index)
    if type(name) ~= "string" or name == "" then
        error("inventory name must be a non-empty string", 0)
    end

    local existing
    local maxPriority = 0
    for _, entry in ipairs(index.entries) do
        if entry.name == name then
            existing = entry
        end
        maxPriority = math.max(maxPriority, entry.priority)
    end
    priority = priority or maxPriority + 1
    if type(priority) ~= "number" or priority < 1 or priority % 1 ~= 0 then
        error("priority must be a positive integer", 0)
    end
    for _, entry in ipairs(index.entries) do
        if entry.priority == priority and entry ~= existing then
            error("priority " .. priority .. " is already assigned to " .. entry.name, 0)
        end
    end

    if not existing then
        existing = { name = name }
        table.insert(index.entries, existing)
    end
    existing.priority = priority
    if filters ~= nil then
        if type(filters) ~= "table" then
            error("filters must be a table", 0)
        end
        existing.allow = copyPatterns(filters.allow)
        existing.deny = copyPatterns(filters.deny)
    end
    validate(index)
    return existing
end

function MIMIndex.detach(index, name)
    validate(index)
    for i, entry in ipairs(index.entries) do
        if entry.name == name then
            table.remove(index.entries, i)
            return entry
        end
    end
    return nil
end

function MIMIndex.input(index)
    validate(index)
    for _, entry in ipairs(index.entries) do
        if entry.priority == 1 then
            return entry
        end
    end
    return nil
end

function MIMIndex.outputs(index)
    validate(index)
    local outputs = {}
    for _, entry in ipairs(index.entries) do
        if entry.priority ~= 1 then
            table.insert(outputs, entry)
        end
    end
    table.sort(outputs, function(a, b)
        return a.priority < b.priority
    end)
    return outputs
end

function MIMIndex.accepts(entry, itemName)
    if entry.deny then
        for _, pattern in ipairs(entry.deny) do
            if string.find(itemName, pattern) then
                return false
            end
        end
    end
    if entry.allow then
        for _, pattern in ipairs(entry.allow) do
            if string.find(itemName, pattern) then
                return true
            end
        end
        return false
    end
    return true
end

return MIMIndex
