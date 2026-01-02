-- Classroom Pulse - LÖVE2D Version
-- Class templates + Session tracking with save/load

-- ============================================
-- STATE
-- ============================================
local AppState = {
    MENU = "menu",
    CLASS_LIST = "class_list",
    CLASS_EDIT = "class_edit",
    SESSION_START = "session_start",
    TRACKING = "tracking",
    SESSION_LIST = "session_list",
    REVIEW = "review",
    MERGE_SELECT = "merge_select"
}

local state = AppState.MENU
local currentSession = nil
local currentClass = nil
local savedSessions = {}
local savedClasses = {}

-- Tracking state
local students = {}
local eventLog = {}
local flashingStudent = nil
local flashTimer = 0
local sessionStart = nil
local sessionName = ""

-- UI state
local inputText = ""
local inputActive = false
local inputPurpose = nil
local scrollOffset = 0
local maxScroll = 0
local confirmDialog = nil -- {message, onConfirm, onCancel}
local exportMessage = nil
local exportMessageTimer = 0
local undoMessage = nil
local undoMessageTimer = 0

-- Layout (defaults, will be calculated dynamically)
local buttonPadding = 8

-- Colors
local colors = {
    background = {0.1, 0.12, 0.15},
    panel = {0.15, 0.17, 0.2},
    button = {0.3, 0.35, 0.4},
    buttonHover = {0.35, 0.4, 0.45},
    flash = {0.8, 0.2, 0.2},
    text = {1, 1, 1},
    textDim = {0.5, 0.55, 0.6},
    accent = {0.2, 0.8, 0.8},
    badge = {0.8, 0.2, 0.2},
    success = {0.2, 0.6, 0.3},
    warning = {0.8, 0.6, 0.2},
    danger = {0.7, 0.2, 0.2},
    input = {0.2, 0.22, 0.25},
    inputActive = {0.25, 0.28, 0.32}
}

-- ============================================
-- LÖVE CALLBACKS
-- ============================================
function love.load()
    love.window.setTitle("Classroom Pulse")
    love.window.setMode(800, 600, {resizable = true, minwidth = 400, minheight = 500})
    love.keyboard.setKeyRepeat(true)
    
    loadAllClasses()
    loadAllSessions()
end

function love.update(dt)
    if flashingStudent then
        flashTimer = flashTimer - dt
        if flashTimer <= 0 then
            flashingStudent = nil
        end
    end
    
    if exportMessageTimer > 0 then
        exportMessageTimer = exportMessageTimer - dt
        if exportMessageTimer <= 0 then
            exportMessage = nil
        end
    end
    
    if undoMessageTimer > 0 then
        undoMessageTimer = undoMessageTimer - dt
        if undoMessageTimer <= 0 then
            undoMessage = nil
        end
    end
end

function love.draw()
    local width, height = love.graphics.getDimensions()
    
    love.graphics.setColor(colors.background)
    love.graphics.rectangle("fill", 0, 0, width, height)
    
    if state == AppState.MENU then
        drawMenu(width, height)
    elseif state == AppState.CLASS_LIST then
        drawClassList(width, height)
    elseif state == AppState.CLASS_EDIT then
        drawClassEdit(width, height)
    elseif state == AppState.SESSION_START then
        drawSessionStart(width, height)
    elseif state == AppState.TRACKING then
        drawTracking(width, height)
    elseif state == AppState.SESSION_LIST then
        drawSessionList(width, height)
    elseif state == AppState.REVIEW then
        drawReview(width, height)
    elseif state == AppState.MERGE_SELECT then
        drawMergeSelect(width, height)
    end
    
    if inputActive then
        drawInputOverlay(width, height)
    end
    
    if confirmDialog then
        drawConfirmDialog(width, height)
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    
    if confirmDialog then
        handleConfirmClick(x, y)
        return
    end
    
    if inputActive then
        handleInputClick(x, y)
        return
    end
    
    if state == AppState.MENU then
        handleMenuClick(x, y)
    elseif state == AppState.CLASS_LIST then
        handleClassListClick(x, y)
    elseif state == AppState.CLASS_EDIT then
        handleClassEditClick(x, y)
    elseif state == AppState.SESSION_START then
        handleSessionStartClick(x, y)
    elseif state == AppState.TRACKING then
        handleTrackingClick(x, y)
    elseif state == AppState.SESSION_LIST then
        handleSessionListClick(x, y)
    elseif state == AppState.REVIEW then
        handleReviewClick(x, y)
    elseif state == AppState.MERGE_SELECT then
        handleMergeSelectClick(x, y)
    end
end

function love.wheelmoved(x, y)
    if state == AppState.CLASS_LIST or state == AppState.SESSION_LIST or state == AppState.REVIEW or state == AppState.CLASS_EDIT or state == AppState.MERGE_SELECT then
        scrollOffset = math.max(0, math.min(maxScroll, scrollOffset - y * 30))
    end
end

function love.keypressed(key)
    if confirmDialog then
        if key == "escape" then
            confirmDialog = nil
        end
        return
    end
    
    if inputActive then
        if key == "return" then
            confirmInput()
        elseif key == "escape" then
            cancelInput()
        elseif key == "backspace" then
            inputText = string.sub(inputText, 1, -2)
        elseif key == "v" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")) then
            -- Paste into text input
            local clipboard = love.system.getClipboardText()
            if clipboard then
                inputText = inputText .. clipboard
            end
        end
        return
    end
    
    -- Ctrl+V / Cmd+V to paste student list in class edit mode
    if state == AppState.CLASS_EDIT then
        if key == "v" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")) then
            pasteStudentList()
            return
        end
    end
    
    if key == "escape" then
        if state == AppState.TRACKING then
            if #eventLog > 0 then
                saveCurrentSession()
            end
            state = AppState.MENU
        elseif state ~= AppState.MENU then
            state = AppState.MENU
            scrollOffset = 0
        else
            love.event.quit()
        end
    end
    
    if state == AppState.TRACKING and key == "e" then
        exportCurrentSessionCSV()
    end
    
    -- Ctrl+Z / Cmd+Z to undo during tracking
    if state == AppState.TRACKING then
        if key == "z" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")) then
            if #eventLog > 0 then
                local removed = table.remove(eventLog)
                undoMessage = "Undid: " .. removed.student_name
                undoMessageTimer = 2
                exportMessage = nil
                exportMessageTimer = 0
            end
        end
    end
end

function love.textinput(t)
    if inputActive then
        inputText = inputText .. t
    end
end

function love.touchpressed(id, x, y)
    love.mousepressed(x, y, 1)
end

-- ============================================
-- DYNAMIC GRID LAYOUT
-- ============================================
function calculateGrid(studentCount, availableWidth, availableHeight, padding)
    -- Find optimal columns/rows to fit all students without scrolling
    -- while maximizing button size
    
    if studentCount == 0 then
        return {cols = 3, rows = 1, btnWidth = 120, btnHeight = 70}
    end
    
    local bestLayout = nil
    local bestArea = 0
    
    -- Try different column counts
    for cols = 1, math.min(studentCount, 8) do
        local rows = math.ceil(studentCount / cols)
        
        local btnWidth = math.floor((availableWidth - (cols + 1) * padding) / cols)
        local btnHeight = math.floor((availableHeight - (rows + 1) * padding) / rows)
        
        -- Constrain proportions (not too wide, not too tall)
        local maxWidth = btnHeight * 2.5
        local maxHeight = btnWidth * 1.5
        btnWidth = math.min(btnWidth, maxWidth)
        btnHeight = math.min(btnHeight, maxHeight)
        
        -- Minimum sizes for usability
        btnWidth = math.max(btnWidth, 60)
        btnHeight = math.max(btnHeight, 40)
        
        -- Maximum sizes so it doesn't look ridiculous with few students
        btnWidth = math.min(btnWidth, 180)
        btnHeight = math.min(btnHeight, 100)
        
        local area = btnWidth * btnHeight
        
        -- Check if this layout fits
        local totalWidth = cols * btnWidth + (cols + 1) * padding
        local totalHeight = rows * btnHeight + (rows + 1) * padding
        
        if totalWidth <= availableWidth and totalHeight <= availableHeight then
            if area > bestArea then
                bestArea = area
                bestLayout = {
                    cols = cols,
                    rows = rows,
                    btnWidth = btnWidth,
                    btnHeight = btnHeight
                }
            end
        end
    end
    
    -- Fallback if nothing fits perfectly
    if not bestLayout then
        local cols = math.ceil(math.sqrt(studentCount * 1.5))
        local rows = math.ceil(studentCount / cols)
        bestLayout = {
            cols = cols,
            rows = rows,
            btnWidth = math.max(60, math.floor((availableWidth - (cols + 1) * padding) / cols)),
            btnHeight = math.max(40, math.floor((availableHeight - (rows + 1) * padding) / rows))
        }
    end
    
    return bestLayout
end

-- ============================================
-- MENU SCREEN
-- ============================================
function drawMenu(width, height)
    love.graphics.setColor(colors.accent)
    love.graphics.printf("Classroom Pulse", 0, height * 0.15, width, "center")
    
    love.graphics.setColor(colors.textDim)
    love.graphics.printf("Focus Break Tracker", 0, height * 0.15 + 35, width, "center")
    
    local btnWidth, btnHeight = 250, 60
    local btnX = (width - btnWidth) / 2
    local startY = height * 0.32
    local spacing = 75
    
    -- Start Session (pick a class)
    local startLabel = #savedClasses > 0 and "Start Session" or "Start Session"
    drawButton(btnX, startY, btnWidth, btnHeight, startLabel, colors.success)
    
    -- Manage Classes
    local classLabel = #savedClasses > 0 and "My Classes (" .. #savedClasses .. ")" or "My Classes"
    drawButton(btnX, startY + spacing, btnWidth, btnHeight, classLabel, colors.accent)
    
    -- Past Sessions
    local sessionLabel = #savedSessions > 0 and "Past Sessions (" .. #savedSessions .. ")" or "Past Sessions"
    drawButton(btnX, startY + spacing * 2, btnWidth, btnHeight, sessionLabel, colors.button)
    
    -- Quick start hint
    if #savedClasses == 0 then
        love.graphics.setColor(colors.textDim)
        love.graphics.printf("Create a class first in 'My Classes'", 0, startY + spacing * 3 + 20, width, "center")
    end
    
    love.graphics.setColor(colors.textDim)
    love.graphics.printf("v1.1 - Tap to log focus breaks", 0, height - 30, width, "center")
end

function handleMenuClick(x, y)
    local width, height = love.graphics.getDimensions()
    local btnWidth, btnHeight = 250, 60
    local btnX = (width - btnWidth) / 2
    local startY = height * 0.32
    local spacing = 75
    
    if isInside(x, y, btnX, startY, btnWidth, btnHeight) then
        -- Start Session
        if #savedClasses == 0 then
            -- No classes yet, go to class creation
            currentClass = nil
            state = AppState.CLASS_EDIT
            students = {}
            for i = 1, 6 do
                table.insert(students, {name = "Student " .. i, id = i})
            end
        else
            state = AppState.SESSION_START
            scrollOffset = 0
        end
    elseif isInside(x, y, btnX, startY + spacing, btnWidth, btnHeight) then
        -- My Classes
        state = AppState.CLASS_LIST
        scrollOffset = 0
    elseif isInside(x, y, btnX, startY + spacing * 2, btnWidth, btnHeight) then
        -- Past Sessions
        state = AppState.SESSION_LIST
        scrollOffset = 0
    end
end

-- ============================================
-- CLASS LIST SCREEN
-- ============================================
function drawClassList(width, height)
    love.graphics.setColor(colors.accent)
    love.graphics.printf("My Classes", 0, 20, width, "center")
    
    love.graphics.setColor(colors.textDim)
    love.graphics.printf("Saved rosters and seating charts", 0, 45, width, "center")
    
    local listY = 80
    local itemHeight = 70
    local listHeight = height - 160
    
    if #savedClasses == 0 then
        love.graphics.setColor(colors.textDim)
        love.graphics.printf("No classes yet.\nTap '+ New Class' to create one.", 0, height/2 - 30, width, "center")
    elseif listHeight > 10 then
        love.graphics.setScissor(20, listY, width - 40, listHeight)
        
        for i, class in ipairs(savedClasses) do
            local itemY = listY + (i-1) * (itemHeight + 10) - scrollOffset
            
            if itemY > listY - itemHeight and itemY < listY + listHeight then
                love.graphics.setColor(colors.panel)
                love.graphics.rectangle("fill", 30, itemY, width - 60, itemHeight, 8, 8)
                
                love.graphics.setColor(colors.text)
                love.graphics.print(class.name, 45, itemY + 12)
                
                love.graphics.setColor(colors.textDim)
                love.graphics.print(#class.students .. " students", 45, itemY + 38)
                
                -- Edit button
                love.graphics.setColor(colors.button)
                love.graphics.rectangle("fill", width - 130, itemY + 15, 80, 40, 6, 6)
                love.graphics.setColor(colors.text)
                love.graphics.printf("Edit", width - 130, itemY + 28, 80, "center")
            end
        end
        
        love.graphics.setScissor()
        maxScroll = math.max(0, #savedClasses * (itemHeight + 10) - listHeight)
    end
    
    -- Bottom buttons
    local btnY = height - 70
    local btnWidth2 = 150
    local spacing = 20
    
    drawButton(width/2 - btnWidth2 - spacing/2, btnY, btnWidth2, 50, "Back", colors.button)
    drawButton(width/2 + spacing/2, btnY, btnWidth2, 50, "+ New Class", colors.success)
end

function handleClassListClick(x, y)
    local width, height = love.graphics.getDimensions()
    
    local listY = 80
    local itemHeight = 70
    
    for i, class in ipairs(savedClasses) do
        local itemY = listY + (i-1) * (itemHeight + 10) - scrollOffset
        
        -- Edit button
        if isInside(x, y, width - 130, itemY + 15, 80, 40) then
            currentClass = class
            students = {}
            for _, s in ipairs(class.students) do
                table.insert(students, {name = s.name, id = s.id})
            end
            state = AppState.CLASS_EDIT
            scrollOffset = 0
            return
        end
    end
    
    -- Bottom buttons
    local btnY = height - 70
    local btnWidth2 = 150
    local spacing = 20
    
    if isInside(x, y, width/2 - btnWidth2 - spacing/2, btnY, btnWidth2, 50) then
        state = AppState.MENU
    elseif isInside(x, y, width/2 + spacing/2, btnY, btnWidth2, 50) then
        -- New Class
        currentClass = nil
        students = {}
        for i = 1, 6 do
            table.insert(students, {name = "Student " .. i, id = i})
        end
        state = AppState.CLASS_EDIT
        scrollOffset = 0
    end
end

-- ============================================
-- CLASS EDIT SCREEN
-- ============================================
function drawClassEdit(width, height)
    local isNew = currentClass == nil
    
    love.graphics.setColor(colors.accent)
    love.graphics.printf(isNew and "New Class" or "Edit Class", 0, 20, width, "center")
    
    -- Class name
    love.graphics.setColor(colors.text)
    love.graphics.print("Class Name:", 40, 55)
    
    local inputWidth = width - 80
    love.graphics.setColor(colors.input)
    love.graphics.rectangle("fill", 40, 78, inputWidth, 36, 6, 6)
    
    local className = currentClass and currentClass.name or ""
    if className == "" then
        love.graphics.setColor(colors.textDim)
        love.graphics.print("e.g. 1st Period - Math", 50, 88)
    else
        love.graphics.setColor(colors.text)
        love.graphics.print(className, 50, 88)
    end
    
    -- Students header
    love.graphics.setColor(colors.text)
    love.graphics.print("Students (" .. #students .. "):", 40, 125)
    
    -- Paste hint
    love.graphics.setColor(colors.textDim)
    local pasteHint = love.system.getOS() == "OS X" and "Cmd+V to paste list" or "Ctrl+V to paste list"
    love.graphics.printf(pasteHint, 0, 127, width - 40, "right")
    
    -- Calculate dynamic grid for students + add button
    local headerHeight = 145
    local bottomHeight = 75
    local availableWidth = width - 60
    local availableHeight = height - headerHeight - bottomHeight
    
    local totalItems = #students + 1  -- +1 for add button
    local grid = calculateGrid(totalItems, availableWidth, availableHeight, buttonPadding)
    local btnWidth = grid.btnWidth
    local btnHeight = grid.btnHeight
    local cols = grid.cols
    
    local gridWidth = cols * btnWidth + (cols - 1) * buttonPadding
    local startX = (width - gridWidth) / 2
    local startY = headerHeight
    
    -- Student buttons
    for i, student in ipairs(students) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = startX + col * (btnWidth + buttonPadding)
        local by = startY + row * (btnHeight + buttonPadding)
        
        love.graphics.setColor(colors.button)
        love.graphics.rectangle("fill", bx, by, btnWidth, btnHeight, 6, 6)
        
        -- Student name
        love.graphics.setColor(colors.text)
        local displayName = student.name
        if #displayName > math.floor(btnWidth / 7) then
            displayName = string.sub(displayName, 1, math.floor(btnWidth / 7) - 2) .. ".."
        end
        love.graphics.printf(displayName, bx + 2, by + btnHeight/2 - 12, btnWidth - 4, "center")
        
        -- Tap to edit hint
        if btnHeight > 50 then
            love.graphics.setColor(colors.textDim)
            love.graphics.printf("tap to edit", bx + 2, by + btnHeight/2 + 6, btnWidth - 4, "center")
        end
        
        -- Delete X
        love.graphics.setColor(colors.danger)
        local xSize = math.max(14, math.min(20, btnHeight / 4))
        love.graphics.printf("×", bx + btnWidth - xSize - 2, by + 2, xSize, "center")
    end
    
    -- Add student button
    local addIndex = #students
    local addCol = addIndex % cols
    local addRow = math.floor(addIndex / cols)
    local addX = startX + addCol * (btnWidth + buttonPadding)
    local addY = startY + addRow * (btnHeight + buttonPadding)
    
    love.graphics.setColor(colors.panel)
    love.graphics.rectangle("fill", addX, addY, btnWidth, btnHeight, 6, 6)
    love.graphics.setColor(colors.accent)
    love.graphics.printf("+ Add", addX, addY + btnHeight/2 - 8, btnWidth, "center")
    
    -- Bottom buttons
    local btnY = height - 65
    local bottomBtnWidth = 100
    local btnSpacing = 12
    
    if isNew then
        local totalWidth = bottomBtnWidth * 2 + btnSpacing
        local btnStartX = (width - totalWidth) / 2
        drawButton(btnStartX, btnY, bottomBtnWidth, 45, "Cancel", colors.button)
        drawButton(btnStartX + bottomBtnWidth + btnSpacing, btnY, bottomBtnWidth, 45, "Save Class", colors.success)
    else
        local totalWidth = bottomBtnWidth * 3 + btnSpacing * 2
        local btnStartX = (width - totalWidth) / 2
        drawButton(btnStartX, btnY, bottomBtnWidth, 45, "Cancel", colors.button)
        drawButton(btnStartX + bottomBtnWidth + btnSpacing, btnY, bottomBtnWidth, 45, "Delete", colors.danger)
        drawButton(btnStartX + (bottomBtnWidth + btnSpacing) * 2, btnY, bottomBtnWidth, 45, "Save", colors.success)
    end
end

function handleClassEditClick(x, y)
    local width, height = love.graphics.getDimensions()
    local isNew = currentClass == nil
    
    -- Class name input
    if isInside(x, y, 40, 78, width - 80, 36) then
        startInput("class_name", currentClass and currentClass.name or "")
        return
    end
    
    -- Calculate same grid as drawing
    local headerHeight = 145
    local bottomHeight = 75
    local availableWidth = width - 60
    local availableHeight = height - headerHeight - bottomHeight
    
    local totalItems = #students + 1
    local grid = calculateGrid(totalItems, availableWidth, availableHeight, buttonPadding)
    local btnWidth = grid.btnWidth
    local btnHeight = grid.btnHeight
    local cols = grid.cols
    
    local gridWidth = cols * btnWidth + (cols - 1) * buttonPadding
    local startX = (width - gridWidth) / 2
    local startY = headerHeight
    
    -- Student buttons
    for i, student in ipairs(students) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = startX + col * (btnWidth + buttonPadding)
        local by = startY + row * (btnHeight + buttonPadding)
        
        -- Delete X hit area
        local xSize = math.max(14, math.min(20, btnHeight / 4))
        if isInside(x, y, bx + btnWidth - xSize - 4, by, xSize + 4, xSize + 4) then
            table.remove(students, i)
            return
        end
        
        -- Edit name (rest of button)
        if isInside(x, y, bx, by, btnWidth, btnHeight) then
            startInput("student_name", student.name)
            inputPurpose = {type = "edit_student", index = i}
            return
        end
    end
    
    -- Add student button
    local addIndex = #students
    local addCol = addIndex % cols
    local addRow = math.floor(addIndex / cols)
    local addX = startX + addCol * (btnWidth + buttonPadding)
    local addY = startY + addRow * (btnHeight + buttonPadding)
    
    if isInside(x, y, addX, addY, btnWidth, btnHeight) then
        table.insert(students, {name = "Student " .. (#students + 1), id = #students + 1})
        return
    end
    
    -- Bottom buttons
    local btnY = height - 65
    local bottomBtnWidth = 100
    local btnSpacing = 12
    
    if isNew then
        local totalWidth = bottomBtnWidth * 2 + btnSpacing
        local btnStartX = (width - totalWidth) / 2
        
        if isInside(x, y, btnStartX, btnY, bottomBtnWidth, 45) then
            state = AppState.CLASS_LIST
            scrollOffset = 0
        elseif isInside(x, y, btnStartX + bottomBtnWidth + btnSpacing, btnY, bottomBtnWidth, 45) then
            saveCurrentClass()
            state = AppState.CLASS_LIST
            scrollOffset = 0
        end
    else
        local totalWidth = bottomBtnWidth * 3 + btnSpacing * 2
        local btnStartX = (width - totalWidth) / 2
        
        if isInside(x, y, btnStartX, btnY, bottomBtnWidth, 45) then
            state = AppState.CLASS_LIST
            scrollOffset = 0
        elseif isInside(x, y, btnStartX + bottomBtnWidth + btnSpacing, btnY, bottomBtnWidth, 45) then
            confirmDialog = {
                message = "Delete '" .. currentClass.name .. "'?",
                onConfirm = function()
                    deleteClass(currentClass)
                    state = AppState.CLASS_LIST
                    scrollOffset = 0
                end
            }
        elseif isInside(x, y, btnStartX + (bottomBtnWidth + btnSpacing) * 2, btnY, bottomBtnWidth, 45) then
            saveCurrentClass()
            state = AppState.CLASS_LIST
            scrollOffset = 0
        end
    end
end

-- ============================================
-- SESSION START SCREEN (Pick a class)
-- ============================================
function drawSessionStart(width, height)
    love.graphics.setColor(colors.accent)
    love.graphics.printf("Start Session", 0, 20, width, "center")
    
    love.graphics.setColor(colors.textDim)
    love.graphics.printf("Choose a class", 0, 45, width, "center")
    
    local listY = 80
    local itemHeight = 70
    local listHeight = height - 140
    
    if #savedClasses == 0 then
        love.graphics.setColor(colors.textDim)
        love.graphics.printf("No classes yet.\nCreate one in 'My Classes' first.", 0, height/2 - 30, width, "center")
    elseif listHeight > 10 then
        love.graphics.setScissor(20, listY, width - 40, listHeight)
        
        for i, class in ipairs(savedClasses) do
            local itemY = listY + (i-1) * (itemHeight + 10) - scrollOffset
            
            if itemY > listY - itemHeight and itemY < listY + listHeight then
                love.graphics.setColor(colors.panel)
                love.graphics.rectangle("fill", 30, itemY, width - 60, itemHeight, 8, 8)
                
                love.graphics.setColor(colors.text)
                love.graphics.print(class.name, 45, itemY + 12)
                
                love.graphics.setColor(colors.textDim)
                love.graphics.print(#class.students .. " students", 45, itemY + 38)
                
                -- Start button
                love.graphics.setColor(colors.success)
                love.graphics.rectangle("fill", width - 130, itemY + 15, 80, 40, 6, 6)
                love.graphics.setColor(colors.text)
                love.graphics.printf("Start", width - 130, itemY + 28, 80, "center")
            end
        end
        
        love.graphics.setScissor()
        maxScroll = math.max(0, #savedClasses * (itemHeight + 10) - listHeight)
    end
    
    -- Back button
    drawButton(width/2 - 75, height - 60, 150, 45, "Back", colors.button)
end

function handleSessionStartClick(x, y)
    local width, height = love.graphics.getDimensions()
    
    local listY = 80
    local itemHeight = 70
    
    for i, class in ipairs(savedClasses) do
        local itemY = listY + (i-1) * (itemHeight + 10) - scrollOffset
        
        -- Start button
        if isInside(x, y, width - 130, itemY + 15, 80, 40) then
            currentClass = class
            students = {}
            for _, s in ipairs(class.students) do
                table.insert(students, {name = s.name, id = s.id})
            end
            sessionName = class.name .. " - " .. os.date("%m/%d %I:%M%p")
            sessionStart = os.time()
            eventLog = {}
            state = AppState.TRACKING
            return
        end
    end
    
    -- Back button
    if isInside(x, y, width/2 - 75, height - 60, 150, 45) then
        state = AppState.MENU
    end
end

-- ============================================
-- TRACKING SCREEN
-- ============================================
function drawTracking(width, height)
    love.graphics.setColor(colors.accent)
    love.graphics.printf("Tracking", 0, 10, width, "center")
    
    love.graphics.setColor(colors.text)
    love.graphics.printf(sessionName, 0, 32, width, "center")
    
    -- Event counter
    love.graphics.setColor(colors.accent)
    love.graphics.printf(tostring(#eventLog), width - 80, 10, 60, "right")
    love.graphics.setColor(colors.textDim)
    love.graphics.printf("events", width - 80, 28, 60, "right")
    
    -- Elapsed time
    local elapsed = os.time() - sessionStart
    local minutes = math.floor(elapsed / 60)
    local seconds = elapsed % 60
    love.graphics.setColor(colors.textDim)
    love.graphics.print(string.format("%02d:%02d", minutes, seconds), 20, 15)
    
    -- Calculate dynamic grid
    local headerHeight = 55
    local bottomHeight = 60
    local availableWidth = width - 40
    local availableHeight = height - headerHeight - bottomHeight - 20
    
    local grid = calculateGrid(#students, availableWidth, availableHeight, buttonPadding)
    local btnWidth = grid.btnWidth
    local btnHeight = grid.btnHeight
    local cols = grid.cols
    
    -- Center the grid
    local gridWidth = cols * btnWidth + (cols - 1) * buttonPadding
    local startX = (width - gridWidth) / 2
    local startY = headerHeight
    
    -- Dynamic font size based on button size
    local nameFontSize = math.max(10, math.min(16, btnHeight / 5))
    
    for i, student in ipairs(students) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = startX + col * (btnWidth + buttonPadding)
        local by = startY + row * (btnHeight + buttonPadding)
        
        local isFlashing = flashingStudent == student.id
        if isFlashing then
            love.graphics.setColor(colors.flash)
        else
            love.graphics.setColor(colors.button)
        end
        love.graphics.rectangle("fill", bx, by, btnWidth, btnHeight, 6, 6)
        
        -- Student name (truncate if needed)
        love.graphics.setColor(colors.text)
        local displayName = student.name
        if #displayName > math.floor(btnWidth / 8) then
            displayName = string.sub(displayName, 1, math.floor(btnWidth / 8) - 2) .. ".."
        end
        love.graphics.printf(displayName, bx + 2, by + btnHeight/2 - 8, btnWidth - 4, "center")
        
        -- Badge
        local count = getStudentCount(student.name)
        if count > 0 then
            local badgeSize = math.max(12, math.min(18, btnHeight / 4))
            love.graphics.setColor(colors.badge)
            love.graphics.circle("fill", bx + btnWidth - badgeSize/2 - 3, by + badgeSize/2 + 3, badgeSize/2 + 2)
            love.graphics.setColor(colors.text)
            love.graphics.printf(tostring(count), bx + btnWidth - badgeSize - 6, by + 4, badgeSize + 4, "center")
        end
    end
    
    -- Bottom buttons
    local btnY = height - 55
    local bottomBtnWidth = 90
    local btnSpacing = 10
    local totalWidth = bottomBtnWidth * 3 + btnSpacing * 2
    local btnStartX = (width - totalWidth) / 2
    
    -- Undo button (only active if there are events)
    local undoColor = #eventLog > 0 and colors.button or colors.panel
    drawButton(btnStartX, btnY, bottomBtnWidth, 42, "Undo", undoColor)
    
    drawButton(btnStartX + bottomBtnWidth + btnSpacing, btnY, bottomBtnWidth, 42, "Export", colors.button)
    drawButton(btnStartX + (bottomBtnWidth + btnSpacing) * 2, btnY, bottomBtnWidth, 42, "End", colors.warning)
    
    -- Show feedback message (only one at a time, export takes priority)
    if exportMessage and exportMessageTimer > 0 then
        love.graphics.setColor(colors.success)
        love.graphics.printf(exportMessage, 20, btnY - 25, width - 40, "center")
    elseif undoMessage and undoMessageTimer > 0 then
        love.graphics.setColor(colors.accent)
        love.graphics.printf(undoMessage, 20, btnY - 25, width - 40, "center")
    end
end

function handleTrackingClick(x, y)
    local width, height = love.graphics.getDimensions()
    
    -- Calculate same grid as drawing
    local headerHeight = 55
    local bottomHeight = 60
    local availableWidth = width - 40
    local availableHeight = height - headerHeight - bottomHeight - 20
    
    local grid = calculateGrid(#students, availableWidth, availableHeight, buttonPadding)
    local btnWidth = grid.btnWidth
    local btnHeight = grid.btnHeight
    local cols = grid.cols
    
    local gridWidth = cols * btnWidth + (cols - 1) * buttonPadding
    local startX = (width - gridWidth) / 2
    local startY = headerHeight
    
    for i, student in ipairs(students) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local bx = startX + col * (btnWidth + buttonPadding)
        local by = startY + row * (btnHeight + buttonPadding)
        
        if isInside(x, y, bx, by, btnWidth, btnHeight) then
            logEvent(student)
            return
        end
    end
    
    -- Bottom buttons
    local btnY = height - 55
    local bottomBtnWidth = 90
    local btnSpacing = 10
    local totalWidth = bottomBtnWidth * 3 + btnSpacing * 2
    local btnStartX = (width - totalWidth) / 2
    
    if isInside(x, y, btnStartX, btnY, bottomBtnWidth, 42) then
        -- Undo
        if #eventLog > 0 then
            local removed = table.remove(eventLog)
            undoMessage = "Undid: " .. removed.student_name
            undoMessageTimer = 2
            exportMessage = nil  -- Clear any export message
            exportMessageTimer = 0
        end
    elseif isInside(x, y, btnStartX + bottomBtnWidth + btnSpacing, btnY, bottomBtnWidth, 42) then
        exportCurrentSessionCSV()
    elseif isInside(x, y, btnStartX + (bottomBtnWidth + btnSpacing) * 2, btnY, bottomBtnWidth, 42) then
        saveCurrentSession()
        state = AppState.MENU
    end
end

-- ============================================
-- SESSION LIST SCREEN
-- ============================================
function drawSessionList(width, height)
    love.graphics.setColor(colors.accent)
    love.graphics.printf("Past Sessions", 0, 20, width, "center")
    
    if #savedSessions == 0 then
        love.graphics.setColor(colors.textDim)
        love.graphics.printf("No sessions yet.\nComplete a tracking session to see it here.", 0, height/2 - 30, width, "center")
    else
        local listY = 60
        local itemHeight = 80
        local listHeight = height - 130
        
        if listHeight > 10 then
            love.graphics.setScissor(20, listY, width - 40, listHeight)
            
            for i, session in ipairs(savedSessions) do
                local itemY = listY + (i-1) * (itemHeight + 10) - scrollOffset
                
                if itemY > listY - itemHeight and itemY < listY + listHeight then
                    love.graphics.setColor(colors.panel)
                    love.graphics.rectangle("fill", 30, itemY, width - 60, itemHeight, 8, 8)
                    
                    love.graphics.setColor(colors.text)
                    love.graphics.print(session.name, 45, itemY + 10)
                    
                    love.graphics.setColor(colors.textDim)
                    love.graphics.print(session.date, 45, itemY + 32)
                    love.graphics.print(#session.events .. " events", 45, itemY + 52)
                    
                    love.graphics.setColor(colors.accent)
                    love.graphics.rectangle("fill", width - 130, itemY + 20, 80, 40, 6, 6)
                    love.graphics.setColor(colors.text)
                    love.graphics.printf("View", width - 130, itemY + 33, 80, "center")
                end
            end
            
            love.graphics.setScissor()
            maxScroll = math.max(0, #savedSessions * (itemHeight + 10) - listHeight)
        end
    end
    
    drawButton(width/2 - 75, height - 60, 150, 45, "Back", colors.button)
end

function handleSessionListClick(x, y)
    local width, height = love.graphics.getDimensions()
    
    local listY = 60
    local itemHeight = 80
    
    for i, session in ipairs(savedSessions) do
        local itemY = listY + (i-1) * (itemHeight + 10) - scrollOffset
        
        if isInside(x, y, width - 130, itemY + 20, 80, 40) then
            currentSession = session
            state = AppState.REVIEW
            scrollOffset = 0
            return
        end
    end
    
    if isInside(x, y, width/2 - 75, height - 60, 150, 45) then
        state = AppState.MENU
    end
end

-- ============================================
-- REVIEW SCREEN
-- ============================================
function drawReview(width, height)
    if not currentSession then 
        state = AppState.SESSION_LIST
        return 
    end
    
    -- Ensure session has required fields
    currentSession.events = currentSession.events or {}
    currentSession.students = currentSession.students or {}
    
    love.graphics.setColor(colors.accent)
    love.graphics.printf("Session Review", 0, 10, width, "center")
    
    love.graphics.setColor(colors.text)
    love.graphics.printf(currentSession.name, 0, 32, width, "center")
    
    love.graphics.setColor(colors.textDim)
    love.graphics.printf(currentSession.date .. " | " .. #currentSession.events .. " events", 0, 52, width, "center")
    
    -- Summary
    local summaryY = 80
    love.graphics.setColor(colors.text)
    love.graphics.print("Summary:", 30, summaryY)
    
    local counts = {}
    for _, event in ipairs(currentSession.events) do
        counts[event.student_name] = (counts[event.student_name] or 0) + 1
    end
    
    local summaryStartY = summaryY + 25
    local col = 0
    local row = 0
    local itemWidth = 130
    local itemHeight = 45
    local itemsPerRow = math.floor((width - 60) / itemWidth)
    
    for _, student in ipairs(currentSession.students) do
        local count = counts[student.name] or 0
        local ix = 30 + col * itemWidth
        local iy = summaryStartY + row * itemHeight
        
        love.graphics.setColor(colors.panel)
        love.graphics.rectangle("fill", ix, iy, itemWidth - 8, itemHeight - 5, 6, 6)
        
        love.graphics.setColor(colors.text)
        love.graphics.printf(student.name, ix + 5, iy + 6, itemWidth - 16, "left")
        
        local countColor = count == 0 and colors.textDim or (count >= 5 and colors.badge or colors.accent)
        love.graphics.setColor(countColor)
        love.graphics.printf(tostring(count), ix + 5, iy + 24, itemWidth - 16, "left")
        
        col = col + 1
        if col >= itemsPerRow then
            col = 0
            row = row + 1
        end
    end
    
    -- Event log (only if there's space)
    local logStartY = summaryStartY + (row + 1) * itemHeight + 10
    local logY = logStartY + 22
    local logHeight = height - logY - 115
    
    if logHeight > 30 then
        love.graphics.setColor(colors.text)
        love.graphics.print("Event Log:", 30, logStartY)
        
        love.graphics.setColor(colors.panel)
        love.graphics.rectangle("fill", 30, logY, width - 60, logHeight, 8, 8)
        
        love.graphics.setScissor(30, logY, width - 60, logHeight)
        
        for i, event in ipairs(currentSession.events) do
            local ey = logY + 8 + (i-1) * 22 - scrollOffset
            if ey > logY - 22 and ey < logY + logHeight then
                love.graphics.setColor(colors.textDim)
                love.graphics.print(i .. ".", 38, ey)
                love.graphics.setColor(colors.text)
                love.graphics.print(event.student_name, 65, ey)
                love.graphics.setColor(colors.textDim)
                love.graphics.printf(event.timestamp, 0, ey, width - 45, "right")
            end
        end
        
        love.graphics.setScissor()
        maxScroll = math.max(0, #currentSession.events * 22 - logHeight + 16)
    else
        maxScroll = 0
    end
    
    -- Bottom buttons - two rows
    local btnWidth2 = 100
    local spacing = 10
    
    -- Row 1: Export, Merge, Delete
    local row1Y = height - 100
    local row1Total = btnWidth2 * 3 + spacing * 2
    local row1Start = (width - row1Total) / 2
    
    drawButton(row1Start, row1Y, btnWidth2, 38, "Export CSV", colors.success)
    drawButton(row1Start + btnWidth2 + spacing, row1Y, btnWidth2, 38, "Merge...", colors.accent)
    drawButton(row1Start + (btnWidth2 + spacing) * 2, row1Y, btnWidth2, 38, "Delete", colors.danger)
    
    -- Row 2: Back
    local row2Y = height - 55
    drawButton(width/2 - 60, row2Y, 120, 38, "Back", colors.button)
    
    -- Show export path if recently exported
    if exportMessage and exportMessageTimer > 0 then
        love.graphics.setColor(colors.success)
        love.graphics.printf(exportMessage, 20, row1Y - 25, width - 40, "center")
    end
end

function handleReviewClick(x, y)
    local width, height = love.graphics.getDimensions()
    
    local btnWidth2 = 100
    local spacing = 10
    
    -- Row 1
    local row1Y = height - 100
    local row1Total = btnWidth2 * 3 + spacing * 2
    local row1Start = (width - row1Total) / 2
    
    if isInside(x, y, row1Start, row1Y, btnWidth2, 38) then
        exportSessionCSV(currentSession)
    elseif isInside(x, y, row1Start + btnWidth2 + spacing, row1Y, btnWidth2, 38) then
        -- Merge - go to merge selection screen
        state = AppState.MERGE_SELECT
        scrollOffset = 0
    elseif isInside(x, y, row1Start + (btnWidth2 + spacing) * 2, row1Y, btnWidth2, 38) then
        -- Delete
        confirmDialog = {
            message = "Delete this session?",
            onConfirm = function()
                deleteSession(currentSession)
                currentSession = nil
                state = AppState.SESSION_LIST
                scrollOffset = 0
            end
        }
    end
    
    -- Row 2: Back
    local row2Y = height - 55
    if isInside(x, y, width/2 - 60, row2Y, 120, 38) then
        state = AppState.SESSION_LIST
        scrollOffset = 0
    end
end

-- ============================================
-- MERGE SELECT SCREEN
-- ============================================
function drawMergeSelect(width, height)
    if not currentSession then
        state = AppState.SESSION_LIST
        return
    end
    
    love.graphics.setColor(colors.accent)
    love.graphics.printf("Merge Sessions", 0, 20, width, "center")
    
    love.graphics.setColor(colors.textDim)
    love.graphics.printf("Select a session to merge into: " .. (currentSession.name or ""), 20, 45, width - 40, "center")
    
    local listY = 80
    local itemHeight = 70
    local listHeight = height - 150
    
    -- Filter out current session
    local otherSessions = {}
    for _, session in ipairs(savedSessions) do
        if session.timestamp ~= currentSession.timestamp then
            table.insert(otherSessions, session)
        end
    end
    
    if #otherSessions == 0 then
        love.graphics.setColor(colors.textDim)
        love.graphics.printf("No other sessions to merge with.", 0, height/2 - 20, width, "center")
    elseif listHeight > 10 then
        love.graphics.setScissor(20, listY, width - 40, listHeight)
        
        for i, session in ipairs(otherSessions) do
            local itemY = listY + (i-1) * (itemHeight + 10) - scrollOffset
            
            if itemY > listY - itemHeight and itemY < listY + listHeight then
                love.graphics.setColor(colors.panel)
                love.graphics.rectangle("fill", 30, itemY, width - 60, itemHeight, 8, 8)
                
                love.graphics.setColor(colors.text)
                love.graphics.print(session.name, 45, itemY + 10)
                
                love.graphics.setColor(colors.textDim)
                love.graphics.print(session.date .. " | " .. #session.events .. " events", 45, itemY + 32)
                
                -- Merge button
                love.graphics.setColor(colors.accent)
                love.graphics.rectangle("fill", width - 130, itemY + 15, 80, 40, 6, 6)
                love.graphics.setColor(colors.text)
                love.graphics.printf("Merge", width - 130, itemY + 28, 80, "center")
            end
        end
        
        love.graphics.setScissor()
        maxScroll = math.max(0, #otherSessions * (itemHeight + 10) - listHeight)
    end
    
    drawButton(width/2 - 60, height - 60, 120, 45, "Cancel", colors.button)
end

function handleMergeSelectClick(x, y)
    local width, height = love.graphics.getDimensions()
    
    local listY = 80
    local itemHeight = 70
    
    -- Filter out current session
    local otherSessions = {}
    for _, session in ipairs(savedSessions) do
        if session.timestamp ~= currentSession.timestamp then
            table.insert(otherSessions, session)
        end
    end
    
    for i, session in ipairs(otherSessions) do
        local itemY = listY + (i-1) * (itemHeight + 10) - scrollOffset
        
        if isInside(x, y, width - 130, itemY + 15, 80, 40) then
            mergeSessions(currentSession, session)
            state = AppState.REVIEW
            scrollOffset = 0
            return
        end
    end
    
    -- Cancel button
    if isInside(x, y, width/2 - 60, height - 60, 120, 45) then
        state = AppState.REVIEW
        scrollOffset = 0
    end
end

-- ============================================
-- INPUT & CONFIRM DIALOGS
-- ============================================
function startInput(purpose, defaultText)
    inputActive = true
    inputText = defaultText or ""
    inputPurpose = purpose
    
    -- Show Android soft keyboard
    love.keyboard.setTextInput(true)
end

function confirmInput()
    if inputPurpose == "class_name" then
        if currentClass then
            currentClass.name = inputText
        else
            currentClass = {name = inputText, students = {}}
        end
    elseif inputPurpose == "session_name" then
        sessionName = inputText
    elseif type(inputPurpose) == "table" and inputPurpose.type == "edit_student" then
        if inputText ~= "" then
            students[inputPurpose.index].name = inputText
        end
    end
    inputActive = false
    inputText = ""
    inputPurpose = nil
    
    -- Hide Android soft keyboard
    love.keyboard.setTextInput(false)
end

function cancelInput()
    inputActive = false
    inputText = ""
    inputPurpose = nil
    
    -- Hide Android soft keyboard
    love.keyboard.setTextInput(false)
end

function drawInputOverlay(width, height)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, width, height)
    
    local boxWidth = math.min(400, width - 40)
    local boxHeight = 150
    local boxX = (width - boxWidth) / 2
    local boxY = (height - boxHeight) / 2
    
    love.graphics.setColor(colors.panel)
    love.graphics.rectangle("fill", boxX, boxY, boxWidth, boxHeight, 10, 10)
    
    love.graphics.setColor(colors.text)
    local title = "Enter Name"
    if inputPurpose == "class_name" then title = "Class Name"
    elseif inputPurpose == "session_name" then title = "Session Name"
    elseif type(inputPurpose) == "table" then title = "Student Name"
    end
    love.graphics.printf(title, boxX, boxY + 15, boxWidth, "center")
    
    love.graphics.setColor(colors.inputActive)
    love.graphics.rectangle("fill", boxX + 20, boxY + 45, boxWidth - 40, 40, 6, 6)
    love.graphics.setColor(colors.text)
    love.graphics.print(inputText .. "_", boxX + 30, boxY + 57)
    
    local btnWidth = (boxWidth - 60) / 2
    drawButton(boxX + 20, boxY + 100, btnWidth, 35, "Cancel", colors.button)
    drawButton(boxX + 40 + btnWidth, boxY + 100, btnWidth, 35, "OK", colors.success)
end

function handleInputClick(x, y)
    local width, height = love.graphics.getDimensions()
    local boxWidth = math.min(400, width - 40)
    local boxHeight = 150
    local boxX = (width - boxWidth) / 2
    local boxY = (height - boxHeight) / 2
    
    local btnWidth = (boxWidth - 60) / 2
    
    if isInside(x, y, boxX + 20, boxY + 100, btnWidth, 35) then
        cancelInput()
    elseif isInside(x, y, boxX + 40 + btnWidth, boxY + 100, btnWidth, 35) then
        confirmInput()
    end
end

function drawConfirmDialog(width, height)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, width, height)
    
    local boxWidth = math.min(350, width - 40)
    local boxHeight = 130
    local boxX = (width - boxWidth) / 2
    local boxY = (height - boxHeight) / 2
    
    love.graphics.setColor(colors.panel)
    love.graphics.rectangle("fill", boxX, boxY, boxWidth, boxHeight, 10, 10)
    
    love.graphics.setColor(colors.text)
    love.graphics.printf(confirmDialog.message, boxX + 20, boxY + 25, boxWidth - 40, "center")
    
    local btnWidth = (boxWidth - 60) / 2
    drawButton(boxX + 20, boxY + 75, btnWidth, 40, "Cancel", colors.button)
    drawButton(boxX + 40 + btnWidth, boxY + 75, btnWidth, 40, "Delete", colors.danger)
end

function handleConfirmClick(x, y)
    local width, height = love.graphics.getDimensions()
    local boxWidth = math.min(350, width - 40)
    local boxHeight = 130
    local boxX = (width - boxWidth) / 2
    local boxY = (height - boxHeight) / 2
    
    local btnWidth = (boxWidth - 60) / 2
    
    if isInside(x, y, boxX + 20, boxY + 75, btnWidth, 40) then
        confirmDialog = nil
    elseif isInside(x, y, boxX + 40 + btnWidth, boxY + 75, btnWidth, 40) then
        if confirmDialog.onConfirm then
            confirmDialog.onConfirm()
        end
        confirmDialog = nil
    end
end

-- ============================================
-- DATA FUNCTIONS
-- ============================================
function pasteStudentList()
    local clipboard = love.system.getClipboardText()
    if not clipboard or clipboard == "" then return end
    
    -- Split by newlines (handle both \n and \r\n)
    local names = {}
    for name in string.gmatch(clipboard, "[^\r\n]+") do
        -- Trim whitespace
        name = name:match("^%s*(.-)%s*$")
        if name and name ~= "" then
            table.insert(names, name)
        end
    end
    
    if #names == 0 then return end
    
    -- Clear default placeholder students if they're untouched
    local hasOnlyDefaults = true
    for i, s in ipairs(students) do
        if not string.match(s.name, "^Student %d+$") then
            hasOnlyDefaults = false
            break
        end
    end
    
    if hasOnlyDefaults then
        students = {}
    end
    
    -- Build a set of existing names (including what we're about to add)
    local nameCounts = {}
    for _, s in ipairs(students) do
        local baseName = s.name:match("^(.-)%s*%(%d+%)$") or s.name
        nameCounts[baseName] = (nameCounts[baseName] or 0) + 1
    end
    
    -- Add pasted names, handling duplicates
    local addedCount = 0
    for _, name in ipairs(names) do
        local finalName = name
        
        -- Check if this name already exists
        if nameCounts[name] then
            -- Find the next available number
            nameCounts[name] = nameCounts[name] + 1
            finalName = name .. " (" .. nameCounts[name] .. ")"
        else
            nameCounts[name] = 1
        end
        
        -- Also check against the exact finalName in case of weird edge cases
        local exists = false
        for _, s in ipairs(students) do
            if s.name == finalName then
                exists = true
                break
            end
        end
        
        if exists then
            -- Keep incrementing until we find a unique name
            local counter = nameCounts[name] + 1
            while exists do
                finalName = name .. " (" .. counter .. ")"
                exists = false
                for _, s in ipairs(students) do
                    if s.name == finalName then
                        exists = true
                        break
                    end
                end
                counter = counter + 1
            end
            nameCounts[name] = counter - 1
        end
        
        local newId = #students + 1
        table.insert(students, {name = finalName, id = newId})
        addedCount = addedCount + 1
    end
    
    print("Pasted " .. addedCount .. " students from clipboard")
end

function logEvent(student)
    local timestamp = os.date("%I:%M:%S %p")
    local isoTimestamp = os.date("%Y-%m-%dT%H:%M:%S")
    
    table.insert(eventLog, {
        student_name = student.name,
        timestamp = timestamp,
        timestamp_raw = isoTimestamp,
        event = "Focus_Break"
    })
    
    flashingStudent = student.id
    flashTimer = 0.3
end

function getStudentCount(studentName)
    local count = 0
    for _, event in ipairs(eventLog) do
        if event.student_name == studentName then
            count = count + 1
        end
    end
    return count
end

-- CLASS PERSISTENCE
function saveCurrentClass()
    if not currentClass then
        currentClass = {name = "New Class", timestamp = os.time()}
    end
    
    currentClass.students = {}
    for i, s in ipairs(students) do
        table.insert(currentClass.students, {name = s.name, id = i})
    end
    currentClass.timestamp = currentClass.timestamp or os.time()
    
    -- Check if updating existing
    local found = false
    for i, c in ipairs(savedClasses) do
        if c.timestamp == currentClass.timestamp then
            savedClasses[i] = currentClass
            found = true
            break
        end
    end
    
    if not found then
        table.insert(savedClasses, 1, currentClass)
    end
    
    -- Save to disk
    local filename = "class_" .. currentClass.timestamp .. ".json"
    love.filesystem.write(filename, encodeJSON(currentClass))
    print("Class saved: " .. currentClass.name)
end

function loadAllClasses()
    savedClasses = {}
    local files = love.filesystem.getDirectoryItems("")
    
    for _, filename in ipairs(files) do
        if string.match(filename, "^class_.*%.json$") then
            local content = love.filesystem.read(filename)
            if content then
                local class = decodeJSON(content)
                if class and class.name then
                    table.insert(savedClasses, class)
                end
            end
        end
    end
    
    table.sort(savedClasses, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    
    print("Loaded " .. #savedClasses .. " classes")
end

function deleteClass(class)
    if not class then return end
    
    -- Remove from list
    for i, c in ipairs(savedClasses) do
        if c.timestamp == class.timestamp then
            table.remove(savedClasses, i)
            break
        end
    end
    
    -- Delete file
    local filename = "class_" .. class.timestamp .. ".json"
    love.filesystem.remove(filename)
    print("Class deleted: " .. class.name)
end

-- SESSION PERSISTENCE
function saveCurrentSession()
    if #eventLog == 0 then return end
    
    local session = {
        name = sessionName,
        date = os.date("%Y-%m-%d %H:%M"),
        timestamp = os.time(),
        class_id = currentClass and currentClass.timestamp or nil,
        students = {},
        events = {}
    }
    
    for _, s in ipairs(students) do
        table.insert(session.students, {name = s.name, id = s.id})
    end
    
    for _, e in ipairs(eventLog) do
        table.insert(session.events, {
            student_name = e.student_name,
            timestamp = e.timestamp,
            timestamp_raw = e.timestamp_raw,
            event = e.event
        })
    end
    
    local filename = "session_" .. os.time() .. ".json"
    love.filesystem.write(filename, encodeJSON(session))
    
    table.insert(savedSessions, 1, session)
    print("Session saved: " .. session.name)
end

function loadAllSessions()
    savedSessions = {}
    local files = love.filesystem.getDirectoryItems("")
    
    for _, filename in ipairs(files) do
        if string.match(filename, "^session_.*%.json$") then
            local content = love.filesystem.read(filename)
            if content then
                local session = decodeJSON(content)
                if session then
                    table.insert(savedSessions, session)
                end
            end
        end
    end
    
    table.sort(savedSessions, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    
    print("Loaded " .. #savedSessions .. " sessions")
end

function deleteSession(session)
    if not session then return end
    
    -- Remove from list
    for i, s in ipairs(savedSessions) do
        if s.timestamp == session.timestamp then
            table.remove(savedSessions, i)
            break
        end
    end
    
    -- Delete file
    local filename = "session_" .. session.timestamp .. ".json"
    love.filesystem.remove(filename)
    print("Session deleted: " .. session.name)
end

function mergeSessions(targetSession, sourceSession)
    if not targetSession or not sourceSession then return end
    
    -- Ensure both sessions have required fields
    targetSession.students = targetSession.students or {}
    targetSession.events = targetSession.events or {}
    sourceSession.students = sourceSession.students or {}
    sourceSession.events = sourceSession.events or {}
    
    -- Merge students (avoid duplicates by name)
    local studentNames = {}
    for _, s in ipairs(targetSession.students) do
        studentNames[s.name] = true
    end
    
    for _, s in ipairs(sourceSession.students) do
        if not studentNames[s.name] then
            table.insert(targetSession.students, {name = s.name, id = #targetSession.students + 1})
            studentNames[s.name] = true
        end
    end
    
    -- Merge events (append source events to target)
    for _, event in ipairs(sourceSession.events) do
        table.insert(targetSession.events, event)
    end
    
    -- Sort events by timestamp
    table.sort(targetSession.events, function(a, b)
        return (a.timestamp_raw or "") < (b.timestamp_raw or "")
    end)
    
    -- Update target session name to indicate merge
    if not string.match(targetSession.name, "%(merged%)$") then
        targetSession.name = targetSession.name .. " (merged)"
    end
    
    -- Save updated target session
    local filename = "session_" .. targetSession.timestamp .. ".json"
    love.filesystem.write(filename, encodeJSON(targetSession))
    
    -- Delete source session
    deleteSession(sourceSession)
    
    -- Update currentSession reference
    currentSession = targetSession
    
    print("Merged sessions: " .. #targetSession.events .. " total events")
end

function exportCurrentSessionCSV()
    if #eventLog == 0 then 
        exportMessage = "No events to export"
        exportMessageTimer = 3
        return 
    end
    
    local csv = "Student_Name,Timestamp,Event,ISO_Timestamp\n"
    for _, event in ipairs(eventLog) do
        csv = csv .. string.format("%s,%s,%s,%s\n",
            event.student_name, event.timestamp, event.event, event.timestamp_raw)
    end
    
    local filename = "export_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
    local success = love.filesystem.write(filename, csv)
    
    if success then
        -- Also copy to clipboard for easy pasting
        love.system.setClipboardText(csv)
        exportMessage = "Exported & copied to clipboard!"
        exportMessageTimer = 4
        undoMessage = nil  -- Clear any undo message
        undoMessageTimer = 0
        print("Exported to: " .. love.filesystem.getSaveDirectory() .. "/" .. filename)
    else
        exportMessage = "Export failed"
        exportMessageTimer = 3
    end
end

function exportSessionCSV(session)
    if not session or #session.events == 0 then 
        exportMessage = "No events to export"
        exportMessageTimer = 3
        return 
    end
    
    local csv = "Student_Name,Timestamp,Event,ISO_Timestamp\n"
    for _, event in ipairs(session.events) do
        csv = csv .. string.format("%s,%s,%s,%s\n",
            event.student_name, event.timestamp, event.event, event.timestamp_raw or "")
    end
    
    local safeName = string.gsub(session.name, "[^%w]", "_")
    local filename = "export_" .. safeName .. ".csv"
    local success = love.filesystem.write(filename, csv)
    
    if success then
        -- Also copy to clipboard for easy pasting
        love.system.setClipboardText(csv)
        exportMessage = "Exported & copied to clipboard!"
        exportMessageTimer = 4
        
        local savePath = love.filesystem.getSaveDirectory()
        print("Exported to: " .. savePath .. "/" .. filename)
        print("CSV also copied to clipboard - paste into Excel/Sheets")
    else
        exportMessage = "Export failed"
        exportMessageTimer = 3
    end
end

-- ============================================
-- UTILITY
-- ============================================
function drawButton(x, y, w, h, text, color)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    love.graphics.setColor(colors.text)
    love.graphics.printf(text, x, y + h/2 - 8, w, "center")
end

function isInside(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function encodeJSON(obj)
    if type(obj) == "table" then
        local isArray = #obj > 0
        local items = {}
        
        if isArray then
            for _, v in ipairs(obj) do
                table.insert(items, encodeJSON(v))
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            for k, v in pairs(obj) do
                table.insert(items, '"' .. tostring(k) .. '":' .. encodeJSON(v))
            end
            return "{" .. table.concat(items, ",") .. "}"
        end
    elseif type(obj) == "string" then
        return '"' .. obj:gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
    elseif type(obj) == "number" or type(obj) == "boolean" then
        return tostring(obj)
    else
        return "null"
    end
end

function decodeJSON(str)
    if not str or str == "" then return nil end
    
    local luaStr = str
        :gsub('%[', '{')
        :gsub('%]', '}')
        :gsub('"([^"]+)"%s*:', '["%1"]=')
        :gsub(':null', '=nil')
        :gsub(':true', '=true')
        :gsub(':false', '=false')
    
    local f = load("return " .. luaStr)
    if f then
        local ok, result = pcall(f)
        if ok then return result end
    end
    return nil
end