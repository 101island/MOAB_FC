return {
    -- Local modem side on the IO Hub computer.
    -- The runtime tries this side first, then scans all sides as fallback.
    modemSide = "bottom",

    -- Rednet protocol shared by IO Hub, FC, controllers, and display.
    protocol = "moab_fc_v1",

    -- IO Hub local sampling period. Keep controller periods independent.
    samplePeriod = 0.10,

    actuatorPwm = {
        enabled = true,
        -- 0.05 s equals one Minecraft tick at 20 TPS.
        period = 0.05
    },

    display = {
        enabled = true,
        peripheralType = "monitor",
        -- Optional: fill exact wired name if multiple monitors exist.
        -- Example: "monitor_0"
        remoteName = "",
        textScale = 0.5,
        title = "MOAB IO HUB"
    },

    sensorOrder = {
        -- Raw channels found by tools/inspect_peripherals.lua.
        -- Body-frame names: forward is positive forward, vertical is positive upward after scale is calibrated.
        "ForwardSpeed",
        "VerticalSpeed",
        "GimbalXAngle",
        "GimbalZAngle",
        "Altitude",
        "AirPressure",
    },

    sensors = {
        Altitude = {
            enabled = true,
            driver = "method",
            peripheralType = "altitude_sensor",
            -- Optional: fill exact wired name if multiple altitude sensors exist.
            -- Example: "altitude_sensor_0"
            remoteName = "",
            method = "getHeight",
            scale = 1,
            bias = 0,
            unit = "block"
        },

        AirPressure = {
            enabled = true,
            driver = "method",
            peripheralType = "altitude_sensor",
            remoteName = "",
            method = "getAirPressure",
            -- Source returns pressure ratio; tooltip displays this value * 100 as percent.
            scale = 1,
            bias = 0,
            unit = "ratio"
        },

        AltitudeRateFromAltitude = {
            enabled = false,
            driver = "derived_delta",
            source = "Altitude",
            scale = 1,
            bias = 0,
            unit = "block/s"
        },

        ForwardSpeed = {
            enabled = true,
            driver = "method",
            remoteName = "velocity_sensor_8",
            method = "getVelocity",
            scale = 1,
            bias = 0,
            unit = "block/s"
        },

        VerticalSpeed = {
            enabled = true,
            driver = "method",
            remoteName = "velocity_sensor_9",
            method = "getVelocity",
            scale = 1,
            bias = 0,
            unit = "block/s"
        },

        GimbalXAngle = {
            enabled = true,
            driver = "method",
            -- Source method returns [XAngle, ZAngle]. Do not rename this to roll/pitch
            -- until airframe mounting direction is verified.
            peripheralType = "gimbal_sensor",
            -- Optional: fill exact wired name if multiple gimbal sensors exist.
            -- Example: "gimbal_sensor_10"
            remoteName = "",
            method = "getAngles",
            index = 1,
            scale = 1,
            bias = 0,
            unit = "deg"
        },

        GimbalZAngle = {
            enabled = true,
            driver = "method",
            peripheralType = "gimbal_sensor",
            remoteName = "",
            method = "getAngles",
            index = 2,
            scale = 1,
            bias = 0,
            unit = "deg"
        }
    },

    actuatorOrder = {
        "SteamVent"
    },

    actuators = {
        SteamVent = {
            enabled = true,
            driver = "redstone_relay",
            -- Steam Vent itself is controlled by redstone strength, not wrapped as
            -- a ComputerCraft peripheral. Drive the redstone relay wired to it.
            peripheralType = "redstone_relay",
            -- Optional: fill exact wired name if multiple redstone relays exist.
            -- Example: "redstone_relay_0"
            remoteName = "",
            outputSide = "back",
            -- Keep this relay dedicated to SteamVent: every update clears the
            -- other five redstone faces so old probe outputs cannot remain at 15.
            clearOtherSides = true,
            scale = 1,
            bias = 0,
            outputMin = 0,
            outputMax = 15,
            failsafe = 0,
            pwmEnabled = true,
            pwmPeriod = 0.05
        }
    }
}
