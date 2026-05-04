return {
    -- Fill this with the IO Hub computer ID, or pass it as the first CLI arg.
    hubID = 65,
    -- Local modem side on the FC computer. "auto" scans all sides.
    modemSide = "auto",
    protocol = "moab_fc_v1",
    timeout = 3,

    sensors = {
        forwardSpeed = "ForwardSpeed"
    },

    actuators = {
        leftMain = "MainThrusterLeft",
        rightMain = "MainThrusterRight"
    },

    display = {
        enabled = true,
        -- compact: real flight HUD on the left 1x1 monitor.
        -- debug: PID tuning UI on a larger monitor. Fill side or remoteName as installed.
        mode = "compact",
        period = 0.2,
        profiles = {
            compact = {
                side = "left",
                peripheralType = "monitor",
                remoteName = "",
                textScale = 0.5
            },
            debug = {
                -- Leave side/remoteName empty to auto-pick the largest visible
                -- monitor on the wired modem network, usually the IO Hub 3x2.
                side = "",
                peripheralType = "monitor",
                remoteName = "",
                textScale = 0.5
            }
        }
    },

    controller = {
        period = 0.10,
        enabled = false,
        targetSpeed = 0,
        turnCommand = 0,
        speedScale = 1,
        speedFilterAlpha = 0.70,
        outputMin = -256,
        outputMax = 256,
        maxStep = 24,

        mixer = {
            neutral = 0,
            forwardScale = 1,
            turnScale = 1,
            leftTurnSign = -1,
            rightTurnSign = 1
        },

        forwardPid = {
            kp = 24,
            ki = 0,
            kd = 3,
            bias = 0,
            outputMin = -256,
            outputMax = 256,
            integralMin = -20,
            integralMax = 20,
            integralZone = 4,
            integralLeak = 0.98,
            resetIntegralOnErrorSignChange = true
        }
    },

    keyboard = {
        speedStep = 0.2,
        turnStep = 8
    },

    typewriter = {
        enabled = true,
        side = "top",
        remoteName = "",
        pollPeriod = 0.05,
        repeatDelay = 0.30,
        repeatPeriod = 0.12,

        -- Linked Typewriter returns key codes. These are GLFW-style ASCII
        -- codes for digits/letters in the current Create Simulated peripheral.
        keys = {
            [32] = "toggle",       -- Space
            [87] = "speedUp",      -- W
            [83] = "speedDown",    -- S
            [65] = "turnLeft",     -- A
            [68] = "turnRight",    -- D
            [88] = "turnZero",     -- X
            [48] = "speedZero",    -- 0
            [76] = "load",         -- L
            [86] = "save",         -- V
            [82] = "reset",        -- R
            [77] = "toggleDisplay",-- M
            [81] = "quit"          -- Q
        },

        repeatActions = {
            speedUp = true,
            speedDown = true,
            turnLeft = true,
            turnRight = true
        }
    }
}
