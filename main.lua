-- test comment from Frank
local states = {}
local currentState
local menuPulseTime = 0
local menuGameFont
local completedInterviews = {}
local draftTeam = "Las Vegas Raiders"
local draftRound = 1
local draftPick = 1

local function changeState(name, ...)
    local nextState = assert(states[name], "Unknown game state: ".. name)

    if currentState and currentState.leave then
        currentState:leave()
    end

    currentState = nextState
    if currentState.enter then
        currentState:enter(...)
    end
end

local function drawStadiumBackground()
    local width, height = love.graphics.getDimensions()
    local imageWidth, imageHeight = menuBackground:getDimensions()
    local scale = math.max(width / imageWidth, height / imageHeight)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        menuBackground,
        (width - imageWidth * scale) / 2,
        (height - imageHeight * scale) / 2,
        0,
        scale,
        scale
    )
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle("fill", 0, 0, width, height)
    return width, height
end

states.menu = {
    update = function(self, dt)
        menuPulseTime = menuPulseTime + dt
    end,

    keypressed = function(self, key)
        if key == "return" then
            changeState("game")
        end
    end,

    draw = function(self)
        local width, height = drawStadiumBackground()

        local logoWidth = width * 0.6
        local logoHeight = math.min(150, height * 0.24)
        local logoX = (width - logoWidth) / 2
        local logoY = height * 0.08
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", logoX, logoY, logoWidth, logoHeight, 12, 12)
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.rectangle("line", logoX, logoY, logoWidth, logoHeight, 12, 12)
        love.graphics.setFont(menuLogoFont)
        love.graphics.printf("GAME LOGO", logoX, logoY + (logoHeight - menuLogoFont:getHeight()) / 2, logoWidth, "center")

        local promptAlpha = 0.3 + 0.7 * ((math.sin(menuPulseTime * 2.5) + 1) / 2)
        love.graphics.setColor(1, 1, 1, promptAlpha)
        love.graphics.setFont(menuPromptFont)
        love.graphics.printf("Press Enter", 0, height * 0.74, width, "center")
        love.graphics.setFont(menuGameFont)
        love.graphics.setColor(1, 1, 1, 1)
    end
}

states.game = {
    update = function(self, dt)
        local dialogueOpen = narrator:isOpen()

        -- Freeze the player while a dialog is on screen so the conversation feels
        -- grounded. NPCs are paused via narrator:bindNPC's update wrapper.
        if not dialogueOpen then
            local isMoving = false

            if love.keyboard.isDown("right") then
                player.x = player.x + player.speed
                player.anim = player.animations.right
                isMoving = true
            end

            if love.keyboard.isDown("left") then
                player.x = player.x - player.speed
                player.anim = player.animations.left
                isMoving = true
            end

            if love.keyboard.isDown("down") then
                player.y = player.y + player.speed
                player.anim = player.animations.down
                isMoving = true
            end

            if love.keyboard.isDown("up") then
                player.y = player.y - player.speed
                player.anim = player.animations.up
                isMoving = true
            end

            -- Keep the player on the field (no obstacle layer to collide with)
            player.x, player.y = clampToMap(player.x, player.y)

            if isMoving == false then
                player.anim:gotoFrame(2)
            end
        else
            -- Hold the idle pose during conversation.
            player.anim:gotoFrame(2)
        end

        player.anim:update(dt)

        -- Update camera position
        cam:lookAt(player.x, player.y)

        -- This section prevents the camera from viewing outside the background
        -- First, get width/height of the game window
        local w, h = love.graphics.getDimensions()

        -- Get the size of the map in pixels
        local mapW = gameMap.width * gameMap.tilewidth
        local mapH = gameMap.height * gameMap.tileheight

        -- Keep the camera inside the map
        cam.x = math.max(w/2, math.min(cam.x, mapW - w/2))
        cam.y = math.max(h/2, math.min(cam.y, mapH - h/2))

        scoutNPC:update(dt)
        coachNPC:update(dt)

        -- Refresh proximity once per frame, only when no dialog is showing.
        if dialogueOpen then
            nearbyNPC = nil
        else
            nearbyNPC = findNearbyNPC()
        end

        narrator:update(dt)
    end,

    draw = function(self)
        cam:attach()
        gameMap:drawLayer(gameMap.layers["Tile Layer 1"])
        player.anim:draw(player.spriteSheet, player.x, player.y, nil, 3, nil, 6, 9)
        scoutNPC:draw()
        coachNPC:draw()

        if nearbyNPC then
            drawInteractPrompt(nearbyNPC)
        end
        cam:detach()

        love.graphics.print("x = " .. math.floor(player.x) .. " y = " .. math.floor(player.y), 10, 10)

        -- Dialogue UI is drawn last so it sits on top of everything.
        narrator:draw()
    end,

    keypressed = function(self, key)
        if narrator:isOpen() then
            -- Inside a dialog: advance / pick options.
            if key == "space" or key == "return" then
                narrator:onAction()
            elseif key == "up" then
                narrator:prevOption()
            elseif key == "down" then
                narrator:nextOption()
            end
        else
            -- Outside a dialog: E starts a conversation with the closest NPC.
            if key == "e" and nearbyNPC then
                narrator:startScript(nearbyNPC, function(npc)
                    completedInterviews[npc.script] = true
                    if completedInterviews.ScoutIntro and completedInterviews.CoachInterview then
                        changeState("gameover")
                    end
                end)
            end
        end
    end

}

local function resetGame()
    completedInterviews = {}
    menuPulseTime = 0

    player.x = 60
    player.y = 320
    player.anim = player.animations.left
    player.anim:gotoFrame(2)

    for _, npc in ipairs({ scoutNPC, coachNPC }) do
        npc.x = npc.originX
        npc.y = npc.originY
        npc.targetX = npc.originX
        npc.targetY = npc.originY
        npc.state = "paused"
        npc.pauseTimer = 0
        npc.pauseDuration = 1
        npc.anim = npc.animations.down
        npc.anim:gotoFrame(2)
        npc.isTalking = false
    end

    nearbyNPC = nil
    cam:lookAt(player.x, player.y)
end

states.gameover = {
    keypressed = function(self, key)
        if key == "space" then
            resetGame()
            changeState("menu")
        end
    end,

    draw = function(self)
        local width, height = drawStadiumBackground()
        local panelWidth = math.min(width * 0.8, 760)
        local panelHeight = math.min(height * 0.58, 360)
        local panelX = (width - panelWidth) / 2
        local panelY = (height - panelHeight) / 2

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", panelX, panelY, panelWidth, panelHeight, 14, 14)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(gameOverTitleFont)
        love.graphics.printf("GAME OVER", panelX, panelY + panelHeight * 0.16, panelWidth, "center")
        love.graphics.setFont(gameOverResultFont)
        love.graphics.printf(
            "The " .. draftTeam .. " selected you!",
            panelX + 20,
            panelY + panelHeight * 0.52,
            panelWidth - 40,
            "center"
        )
        love.graphics.setFont(gameOverDetailFont)
        love.graphics.printf(
            "Round " .. draftRound .. " - Pick " .. draftPick,
            panelX,
            panelY + panelHeight * 0.72,
            panelWidth,
            "center"
        )
        love.graphics.setFont(gameOverPromptFont)
        love.graphics.printf(
            "Press Escape to leave the game\nPress Space to restart",
            panelX,
            panelY + panelHeight * 0.8,
            panelWidth,
            "center"
        )
        love.graphics.setFont(menuGameFont)
        love.graphics.setColor(1, 1, 1, 1)
    end
}

function love.load()
    love.window.setTitle("Gridiron Glory")

    camera = require 'libraries/camera'
    NPC = require 'libraries/npc'
    anim8 = require 'libraries/anim8'
    sti = require 'libraries/sti'
    narrator = require 'libraries/narrator'

    cam = camera()

    love.graphics.setDefaultFilter("nearest", "nearest")
    menuGameFont = love.graphics.getFont()
    menuBackground = love.graphics.newImage('sprites/menu-background.png')
    menuLogoFont = love.graphics.newFont(36)
    menuPromptFont = love.graphics.newFont(26)
    gameOverTitleFont = love.graphics.newFont(52)
    gameOverResultFont = love.graphics.newFont(30)
    gameOverDetailFont = love.graphics.newFont(24)
    gameOverPromptFont = love.graphics.newFont(18)

    gameMap = sti('maps/football_map.lua')
    gameMap:resize(love.graphics.getWidth()*2, love.graphics.getHeight())

    player = {}
    player.x = 60
    player.y = 320
    player.speed = 5
    player.spriteSheet = love.graphics.newImage('sprites/qb-sheet.png')
    player.grid = anim8.newGrid( 12, 18, player.spriteSheet:getWidth(), player.spriteSheet:getHeight() )

    player.animations = {}
    player.animations.down = anim8.newAnimation( player.grid('1-4', 1), 0.2 )
    player.animations.left = anim8.newAnimation( player.grid('1-4', 2), 0.2 )
    player.animations.right = anim8.newAnimation( player.grid('1-4', 3), 0.2 )
    player.animations.up = anim8.newAnimation( player.grid('1-4', 4), 0.2 )

    player.anim = player.animations.left

    -- character sheet, starting position, wander x, wander y
    -- Scout Daniels paces the check-in table near the field entrance.
    scoutNPC = NPC.new('sprites/scout-sheet.png', 100, 500, 0, 60)
    -- Coach Reyes stands near midfield, watching prospects run routes.
    coachNPC = NPC.new('sprites/coach-sheet.png', 1390, 120, 60, 0)

    -- Narrator: ink + talkies wrapper. See narrator.lua.
    narrator:init()

    characterScout = narrator:newCharacter("Scout Daniels", "sprites/scout_avatar.png")
    characterCoach = narrator:newCharacter("Coach Reyes",   "sprites/coach_avatar.png")

    narrator:bindNPC(scoutNPC, characterScout, "ScoutIntro")
    narrator:bindNPC(coachNPC, characterCoach, "CoachInterview")

    -- Distance (in world pixels) at which the "E" prompt appears.
    interactRange = 80

    -- Set when the player is close enough to a bound NPC to interact.
    nearbyNPC = nil

    -- Font for the floating "E" key prompt.
    promptFont = love.graphics.newFont(14)

    changeState("menu")
end

-- The field is a single open layer with no obstacles, so the only
-- "collision" is keeping the player from walking off the map edges.
function clampToMap(x, y)
    local mapW = gameMap.width * gameMap.tilewidth
    local mapH = gameMap.height * gameMap.tileheight
    return math.max(0, math.min(x, mapW)), math.max(0, math.min(y, mapH))
end

-- Find the closest bound NPC within interactRange (or nil).
function findNearbyNPC()
    local closest, closestDist = nil, interactRange
    for _, npc in ipairs(narrator._boundNPCs) do
        local dx = npc.x - player.x
        local dy = npc.y - player.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= closestDist then
            closest, closestDist = npc, dist
        end
    end
    return closest
end

function love.update(dt)
    if currentState and currentState.update then
        currentState:update(dt)
    end
end

-- Small "E" key hint floating above an NPC's head.
function drawInteractPrompt(npc)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Press E", npc.x - 25, npc.y - 60)
end

function love.draw()
    if currentState and currentState.draw then
        currentState:draw()
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end

    if currentState and currentState.keypressed then
        currentState:keypressed(key)
    end
end
