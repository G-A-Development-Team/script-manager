
-- Simple GUI window to list Lua scripts in a folder and Load/Unload them.
-- Uses Aimware-style API: gui.*, file.*, LoadScript, UnloadScript
--
-- Default folders scanned: workspace/, thread_luas/
-- You can change the active folder via dropdown and refresh.

-- UI
local WINDOW = gui.Window("script_manager", "Script Manager", 200, 200, 460, 470)
local gbList = gui.Groupbox(WINDOW, "Available Scripts", 10, 10, 440, 300)
local cbFolder = gui.Combobox(gbList, "sm_folder", "Folder", "<scanning>")
local btnRefresh -- created after layout setup
local lstScripts = gui.Listbox(gbList, "sm_list", 0, 0, 0, 0)
local lblStatus = gui.Text(gbList, "Status: Idle")

-- Layout within list groupbox
cbFolder:SetPosX(10)
cbFolder:SetPosY(20)
cbFolder:SetWidth(220)

lstScripts:SetPosX(10)
lstScripts:SetPosY(60)
lstScripts:SetWidth(410)
lstScripts:SetHeight(200)

lblStatus:SetPosX(10)
lblStatus:SetPosY(265)

local gbActions = gui.Groupbox(WINDOW, "Actions", 10, 335, 440, 150)
local btnLoad -- created below with callback
local btnUnload -- created below with callback

-- State
local indexToPath = {}
local loadedSet = {}
local folders = {"<all>"}

local function setStatus(msg)
    lblStatus:SetText("Status: " .. tostring(msg))
end

-- Safe getter for listbox index (returns -1 if no valid selection)
local function get_list_index()
    local ok, v = pcall(function() return lstScripts:GetValue() end)
    if not ok or type(v) ~= "number" then return -1 end
    return v
end

local function normalize_path(p)
    p = tostring(p or "")
    p = p:gsub("\\", "/")
    -- collapse any double slashes
    p = p:gsub("/+", "/")
    return p
end

local function list_lua_files(folder)
    local show_all = folder == "<all>"
    folder = show_all and "" or normalize_path(folder)
    local items = {}
    local seen = {}

    -- Aimware-style enumeration: callback over all files
    pcall(function()
        file.Enumerate(function(path)
            path = normalize_path(path)
            if type(path) == "string" and path:lower():sub(-4) == ".lua" then
                if show_all or path:sub(1, #folder + 1) == folder .. "/" then
                    local base = path:match("([^/]+)$") or path
                    if not seen[path] then
                        seen[path] = true
                        table.insert(items, { name = base, full = path })
                    end
                end
            end
        end)
    end)

    table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
    return items
end

local function refresh()
    indexToPath = {}

    local idx = cbFolder:GetValue()
    local folder = folders[idx + 1] or "<all>"
    local files = list_lua_files(folder)

    local opts = {}
    for i = 1, #files do
        opts[i] = files[i].name
        indexToPath[i] = files[i].full
    end

    if #opts == 0 then
        lstScripts:SetOptions("<no scripts>")
    else
        local unpack_fn = _G.unpack or table.unpack
        lstScripts:SetOptions(unpack_fn(opts))
    end

    setStatus(string.format("Found %d scripts in %s", #files, folder))
end

-- Create buttons with callbacks exactly once
btnRefresh = gui.Button(gbList, "Refresh", function()
    refresh()
end)
btnRefresh:SetWidth(100)
btnRefresh:SetPosX(330)
btnRefresh:SetPosY(20)

btnLoad = gui.Button(gbActions, "Load Selected", function()
    local idx0 = get_list_index()
    local path = indexToPath[idx0 + 1]
    if not path then
        setStatus("Select a script to load")
        return
    end
    local ok, err = pcall(function() LoadScript(path) end)
    if ok then
        loadedSet[path] = true
        setStatus("Loaded: " .. path)
    else
        setStatus("Load failed: " .. tostring(err))
    end
end)

btnUnload = gui.Button(gbActions, "Unload Selected", function()
    local idx0 = get_list_index()
    local path = indexToPath[idx0 + 1]
    if not path then
        setStatus("Select a script to unload")
        return
    end
    local ok, err = pcall(function() UnloadScript(path) end)
    if ok then
        loadedSet[path] = nil
        setStatus("Unloaded: " .. path)
    else
        setStatus("Unload failed: " .. tostring(err))
    end
end)

-- Track selection changes by polling in Draw
local lastSel = -1

-- Show the window when menu is open
callbacks.Register("Draw", function()
    -- Always show when menu is open
    local menu = gui.Reference and gui.Reference("MENU")
    if menu and menu:IsActive() then
        WINDOW:SetActive(true)
    else
        WINDOW:SetActive(false)
    end

    -- Poll selection change for listbox (no SetCallback in API)
    local idx0 = get_list_index()
    if idx0 ~= lastSel then
        lastSel = idx0
        local path = indexToPath[idx0 + 1]
        if path then
            if loadedSet[path] then
                setStatus("Selected (loaded): " .. path)
            else
                setStatus("Selected: " .. path)
            end
        else
            setStatus("No selection")
        end
    end
end)

-- Build folder list from file.Enumerate results
local function rebuild_folders()
    local seen = { ["<all>"] = true }
    folders = {"<all>"}

    pcall(function()
        file.Enumerate(function(path)
            path = normalize_path(path)
            -- Collect top-level directory names (before first slash)
            local dir = path:match("^([^/]+)/")
            if dir and not seen[dir] then
                seen[dir] = true
                table.insert(folders, dir)
            end
        end)
    end)

    -- Update combobox options
    if #folders == 1 then
        cbFolder:SetOptions("<all>")
    else
        local unpack_fn = _G.unpack or table.unpack
        cbFolder:SetOptions(unpack_fn(folders))
    end
end

rebuild_folders()
refresh()
