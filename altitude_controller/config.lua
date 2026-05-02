return {
    -- Fill this with the IO Hub computer ID, or pass it as the first CLI arg.
    hubID = 65,
    -- Local modem side on this controller computer.
    -- The runtime tries this side first, then scans all sides as fallback.
    modemSide = "right",
    protocol = "moab_fc_v1",
    timeout = 3,

    sensors = {
        altitude = "Altitude",
        verticalSpeed = "VerticalSpeed"
    },

    actuator = {
        steamVent = "SteamVent"
    },

    linkTest = {
        command = 7.5,
        seconds = 10,
        period = 0.5,
        stopAfter = true
    },

    display = {
        -- main.lua does not open the monitor unless started with --display.
        enabled = false,
        peripheralType = "monitor",
        remoteName = "",
        textScale = 0.5,
        period = 0.5,
        historyMax = 160
    },

    controller = {
        enabled = false,
        mode = "cascade",
        period = 0.2,
        targetAltitude = 100,
        manualSpeedTarget = 0,
        -- IO Hub VerticalSpeed is currently negative while altitude is rising.
        -- Controller convention is positive upward, so use -1 here.
        verticalSpeedScale = -1,
        speedFilterAlpha = 0.65,
        outputMin = 0,
        outputMax = 15,
        maxStep = 0.6,

        feedforward = {
            enabled = true,
            source = "target",
            outputMin = 0,
            outputMax = 15,
            levels = {
                { altitude = 80, level = 7.55 },
                { altitude = 100, level = 8.40 },
                { altitude = 120, level = 8.77 },
                { altitude = 140, level = 9.54 },
                { altitude = 160, level = 10.30 },
                { altitude = 180, level = 11.10 },
                { altitude = 200, level = 12.00 },
                { altitude = 220, level = 13.00 }
            }
        },

        outerPid = {
            kp = 0.06,
            ki = 0.012,
            kd = 0.18,
            bias = 0,
            integralMin = -16,
            integralMax = 16,
            integralZone = 12,
            integralLeak = 0.98,
            resetIntegralOnErrorSignChange = true
        },

        innerPid = {
            kp = 2.6,
            ki = 0.012,
            kd = 0,
            bias = 0,
            integralMin = -8,
            integralMax = 8,
            integralZone = 1.5,
            integralLeak = 0.98,
            resetIntegralOnErrorSignChange = true
        }
    }
}
