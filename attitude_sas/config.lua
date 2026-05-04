return {
    -- Fill this with the IO Hub computer ID, or pass it as the first CLI arg.
    hubID = 65,
    -- Local modem side on this SAS computer.
    modemSide = "right",
    protocol = "moab_fc_v1",
    timeout = 3,

    sensors = {
        -- A/B must be verified against the installed gimbal sensor.
        -- Current convention:
        --   pitch = A, pitch+ = nose up
        --   roll  = B, roll+  = clockwise viewed from tail to nose
        -- Installed sensor mapping:
        --   Z angle = pitch
        --   X angle = roll
        pitch = "GimbalZAngle",
        roll = "GimbalXAngle"
    },

    actuators = {
        tailLeft = "PropTailLeft",
        tailRight = "PropTailRight",
        noseLeft = "PropNoseLeft",
        noseRight = "PropNoseRight"
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
        period = 0.10,
        pitchEnabled = true,
        rollEnabled = true,
        targetPitch = 0,
        targetRoll = 0,
        pitchScale = 1,
        rollScale = 1,
        angleFilterAlpha = 0.65,
        outputMin = -128,
        outputMax = 128,
        maxStep = 16,

        -- Pitch feedforward interface for main-thrust pitch coupling.
        -- sourceActuators are averaged before applying gain:
        --   ff = bias + gain * avg(sourceActuators)
        pitchFeedforward = {
            enabled = true,
            sourceActuators = {
                "MainThrusterLeft",
                "MainThrusterRight"
            },
            gain = 0,
            bias = 0,
            outputMin = -64,
            outputMax = 64
        },

        mixer = {
            neutral = 0,
            pitchScale = 1,
            rollScale = 1
        },

        pitchPid = {
            kp = 2.0,
            ki = 0,
            kd = 0.20,
            bias = 0,
            integralMin = -20,
            integralMax = 20,
            integralZone = 10,
            integralLeak = 0.98,
            resetIntegralOnErrorSignChange = true
        },

        rollPid = {
            kp = 2.0,
            ki = 0,
            kd = 0.20,
            bias = 0,
            integralMin = -20,
            integralMax = 20,
            integralZone = 10,
            integralLeak = 0.98,
            resetIntegralOnErrorSignChange = true
        }
    }
}
