# MOAB_FC

MOAB_FC 是一个面向 CraftOS / ComputerCraft 有线调制解调器网络的分布式飞艇飞控实验仓库。

当前阶段只做一件事：先打通传感器与执行器的硬件抽象层，也就是 `io_hub/`。

## 目标结构

```text
MOAB_FC/
├── io_hub/                 # 统一数据调度中心 / HAL
│   ├── fleet_config.lua    # 全局硬件配置，传感器和执行器只在这里定义
│   ├── sensors.lua         # 传感器驱动
│   ├── actuators.lua       # 执行器驱动，含 0..15 模拟输出和 PDM/PWM 平滑
│   ├── display.lua         # monitor 显示屏驱动
│   ├── hal.lua             # 对外统一 read/write/snapshot 接口
│   ├── rednet_util.lua     # 本节点 rednet modem 打开工具
│   ├── main.lua            # rednet RPC 服务
│   ├── test_io.lua         # 本机打通测试
│   ├── probe_display.lua   # 显示屏链路探测
│   ├── probe_steam_vent.lua# Steam Vent 红石链路探测
│   ├── probe_relay_sides.lua# redstone_relay 六面输出探测
│   ├── clear_relay_sides.lua# redstone_relay 六面清零
│   ├── hold_actuator.lua   # 长驻小数输出测试
│   ├── inspect_to_file.lua # IO Hub 本机外设列表导出
│   ├── probe_peripheral.lua# IO Hub 本机外设方法探测
│   └── startup.lua         # 常驻启动入口
├── altitude_controller/    # 高度控制器节点，不直接访问硬件
│   ├── config.lua          # 控制器本机通信配置
│   ├── client.lua          # IO Hub RPC 客户端
│   ├── rednet_util.lua     # 本节点 rednet modem 打开工具
│   ├── pid.lua             # PID 基础模块
│   ├── feedforward.lua     # 高度悬停前馈表
│   ├── runtime.lua         # 串级高度控制器运行时
│   ├── display.lua         # AC 本机 monitor 显示
│   ├── main.lua            # AC 主程序
│   ├── startup.lua         # AC 自启动入口
│   └── test_iohub.lua      # 读高度/速度并写 SteamVent 的链路测试
├── attitude_sas/           # Pitch/Roll SAS 节点，不直接访问硬件
│   ├── config.lua          # SAS 本机通信与控制配置
│   ├── client.lua          # IO Hub RPC 客户端
│   ├── rednet_util.lua     # 本节点 rednet modem 打开工具
│   ├── pid.lua             # PID 基础模块
│   ├── runtime.lua         # Pitch/Roll PID 与四路混控
│   ├── display.lua         # SAS 本机 monitor 显示与调参
│   ├── main.lua            # SAS 主程序
│   ├── startup.lua         # SAS 自启动入口
│   └── test_iohub.lua      # 读姿态并写四路桨的链路测试
├── fc/                     # 飞控节点，不直接访问硬件
│   ├── config.lua          # FC 本机通信、前进 PID 和左右主推逻辑名
│   ├── client.lua          # IO Hub RPC 客户端
│   ├── rednet_util.lua     # 本节点 rednet modem 打开工具
│   ├── pid.lua             # PID 基础模块
│   ├── display.lua         # FC 左侧 monitor 显示
│   ├── typewriter.lua      # Linked Typewriter 输入驱动
│   ├── runtime.lua         # 前进速度 PID 与左右主推差速混控
│   ├── main.lua            # FC 主程序
│   ├── startup.lua         # FC 自启动入口
│   └── test_typewriter.lua # Linked Typewriter 输入探测
├── tools/
│   ├── inspect_peripherals.lua
│   ├── probe_peripheral.lua
│   └── io_client.lua
└── common/                 # 共享源码参考；节点目录内保留可直接部署副本
    └── rednet_util.lua     # rednet modem 配置优先、自动兜底打开
```

## 架构边界

`io_hub` 是唯一直接访问外设的电脑。

其他电脑后续只通过逻辑名访问：

```lua
Altitude
VerticalSpeed
SteamVent
MainThrusterLeft
MainThrusterRight
GimbalXAngle
GimbalZAngle
PropTailLeft
PropTailRight
PropNoseLeft
PropNoseRight
```

不要让 `Roll_SAS`、`Altitude_Controller`、`FC` 各自维护外设 side、remoteName、输出极性等硬件细节。

`Altitude_Controller` 这类功能节点只维护：

```lua
hubID
modemSide
protocol
Altitude / VerticalSpeed / SteamVent 这些逻辑名
```

`modemSide` 是本机调制解调器所在面。运行时会优先尝试配置值；如果该面没有 modem，再扫描 `left/right/front/back/top/bottom` 兜底。不要把它和 IO Hub 的外设 `remoteName` 或 redstone relay 的 `outputSide` 混用。

它不维护 `redstone_relay`、`outputSide`、传感器外设名等硬件配置。

## 第一步：列出有线外设

把 `tools/inspect_peripherals.lua` 放到 IO Hub 电脑上，运行：

```text
inspect_peripherals.lua
```

记录输出中的外设名，例如：

```text
altitude_sensor_0
redstone_relay_0
monitor_0
velocity_sensor_8
```

如果只想看某个外设：

```text
inspect_peripherals.lua redstone_relay_0
```

如果终端一页显示不完，不要用 `>` 重定向；部分 CraftOS 环境会把 `>` 当作普通参数。改用脚本内置输出：

```text
inspect_peripherals.lua --out inspect.txt
edit inspect.txt
```

或分页查看：

```text
inspect_peripherals.lua --page
```

如果要确认某个传感器方法的实际返回值：

```text
probe_peripheral.lua <peripheralName>
```

例如：

```text
probe_peripheral.lua attitude_sensor_0
```

## 第二步：填写全局硬件配置

编辑 `io_hub/fleet_config.lua`。

至少先填已经被 `inspect_peripherals.lua` 找到的外设。

如果只看到两个速度传感器，例如：

```text
velocity_sensor_8 [velocity_sensor]
  - getVelocity

velocity_sensor_9 [velocity_sensor]
  - getVelocity
```

已知 `velocity_sensor_8` 是前进方向，`velocity_sensor_9` 是高度/竖直方向时，按飞控语义名配置：

```lua
sensors = {
    ForwardSpeed = {
        enabled = true,
        driver = "method",
        remoteName = "velocity_sensor_8",
        method = "getVelocity",
        scale = 1,
        bias = 0
    },

    VerticalSpeed = {
        enabled = true,
        driver = "method",
        remoteName = "velocity_sensor_9",
        method = "getVelocity",
        scale = 1,
        bias = 0
    }
}
```

后续只需要校准极性：`ForwardSpeed` 应为“向前为正”，`VerticalSpeed` 应为“向上为正”。如果方向反了，只改对应通道的 `scale = -1`。

姿态传感器当前按源码中的两轴处理。Create Simulated 的 `gimbal_sensor` ComputerCraft peripheral 暴露：

```lua
getAngles()    -- 返回 { XAngle_degrees, ZAngle_degrees }
getAnglesRad() -- 返回 { XAngle_radians, ZAngle_radians }
```

HAL 层先使用源码名，不直接臆造 roll/pitch 映射：

```lua
sensors = {
    GimbalXAngle = {
        enabled = true,
        driver = "method",
        peripheralType = "gimbal_sensor",
        remoteName = "",
        method = "getAngles",
        index = 1,
        scale = 1,
        bias = 0
    },

    GimbalZAngle = {
        enabled = true,
        driver = "method",
        peripheralType = "gimbal_sensor",
        remoteName = "",
        method = "getAngles",
        index = 2,
        scale = 1,
        bias = 0
    }
}
```

如果一个网络内有多个 `gimbal_sensor`，不要用 `peripheralType` 自动查找；先用 `inspect_to_file.lua` 找到精确外设名，再填 `remoteName = "gimbal_sensor_..."`。

`GimbalXAngle/GimbalZAngle` 与飞控里的 `Roll/Pitch` 的对应关系取决于方块安装方向和机体系定义，后续通过实际倾斜测试确定。

高度计按源码中的 `altitude_sensor` ComputerCraft peripheral 处理：

```lua
getHeight()      -- 返回世界高度，单位 block
getAirPressure() -- 返回气压比例；护目镜 tooltip 显示为该值 * 100%
```

配置：

```lua
sensors = {
    Altitude = {
        enabled = true,
        driver = "method",
        peripheralType = "altitude_sensor",
        remoteName = "",
        method = "getHeight",
        scale = 1,
        bias = 0
    },

    AirPressure = {
        enabled = true,
        driver = "method",
        peripheralType = "altitude_sensor",
        remoteName = "",
        method = "getAirPressure",
        scale = 1,
        bias = 0
    }
}
```

如果一个网络内有多个高度计，先用 `inspect_to_file.lua` 找到精确外设名，再填 `remoteName = "altitude_sensor_..."`。

如果已经看到了高度表和执行器，再填：

```lua
sensors = {
    Altitude = {
        remoteName = "这里填高度表外设名",
        method = "getHeight"
    }
}

actuators = {
    SteamVent = {
        remoteName = "这里填红石继电器外设名",
        outputSide = "back"
    }
}
```

`remoteName` 必须来自 `inspect_peripherals.lua` 的实际输出，不要猜。

显示屏也在同一个全局配置里定义：

```lua
display = {
    enabled = true,
    peripheralType = "monitor",
    remoteName = "",
    textScale = 0.5,
    title = "MOAB IO HUB"
}
```

如果同一有线网络里只有一个显示屏，`remoteName = ""` 会自动查找 `monitor`。如果有多个显示屏，先用 `inspect_to_file.lua` 找到精确外设名，再填 `remoteName = "monitor_..."`。

## 第三步：本机测试传感器

在 IO Hub 电脑上运行：

```text
test_io.lua sensors 0.2 20
```

含义：

- `0.2`：采样周期，秒
- `20`：采样次数

预期能看到：

```text
ForwardSpeed = ...
VerticalSpeed = ...
```

如果 `ForwardSpeedErr` / `VerticalSpeedErr` 出现，先修 `fleet_config.lua` 里的 `remoteName` 或 `method`。

## 第四步：本机测试执行器

单次输出：

```text
test_io.lua actuator SteamVent 15 2
test_io.lua actuator MainThrusterRight 16 2
test_io.lua actuator MainThrusterLeft 16 2
```

含义：

- `SteamVent` / `MainThrusterRight` / `MainThrusterLeft`：执行器逻辑名
- `15` 或 `16`：命令值；`SteamVent` 是红石 `0..15`，主推变速器当前按 `-256..256` 转速目标处理
- `2`：保持 2 秒

停止：

```text
test_io.lua stop
```

阶梯扫描：

```text
test_io.lua sweep SteamVent 0 15 1 0.5
test_io.lua sweep MainThrusterRight -32 32 16 0.5
test_io.lua sweep MainThrusterLeft -32 32 16 0.5
```

含义：从起始值到结束值，每次增加指定步长，每档保持 0.5 秒。主推逻辑命令已归一化：正值表示前推；其中左推 raw #6 在 IO Hub 内部使用 `scale = -1` 反向。

## 第五步：本机测试显示屏

把 `io_hub/display.lua` 和 `io_hub/probe_display.lua` 放到 IO Hub 电脑上，运行：

```text
probe_display.lua 10 0.5
```

含义：

- `10`：持续刷新 10 秒
- `0.5`：每 0.5 秒刷新一次

预期：

- 终端输出 `monitor=... size=...`
- 显示屏先显示 `DISPLAY OK`
- 随后显示当前 `SENSORS` 和 `ACTUATORS` 快照

如果报 `cannot find peripheral type [monitor]`，说明显示屏不在 IO Hub 的有线网络里，或没有开有线调制解调器。如果有多个显示屏，不要让 `peripheral.find("monitor")` 自动选，直接在 `fleet_config.lua` 填 `display.remoteName = "monitor_..."`。

## 第六步：启动 IO Hub 服务

```text
main.lua
```

如果不是整目录复制，IO Hub 电脑至少需要：

```text
io_hub/fleet_config.lua
io_hub/hal.lua
io_hub/sensors.lua
io_hub/actuators.lua
io_hub/rednet_util.lua
io_hub/main.lua
```

或放置 `startup.lua` 后让电脑开机自动常驻。

IO Hub 服务支持：

```lua
{ type = "ping" }
{ type = "get_config" }
{ type = "get_snapshot" }
{ type = "read_sensors" }
{ type = "read_actuators" }
{ type = "write_actuator", name = "SteamVent", value = 7.5 }
{ type = "write_actuators", values = { SteamVent = 7.5 } }
{ type = "stop_all" }
```

## 第七步：远程测试 IO Hub

在另一台同网络电脑上放 `tools/io_client.lua`，运行：

```text
io_client.lua <hubID> top ping
io_client.lua <hubID> top snapshot
io_client.lua <hubID> top write SteamVent 10
io_client.lua <hubID> top stop
```

`hubID` 是 IO Hub 电脑的 `os.getComputerID()`。

## 第八步：Altitude Controller 新电脑链路测试

在 IO Hub 电脑上先运行：

```text
main.lua
```

记下 IO Hub 电脑 ID：

```text
id
```

在另一台新电脑上放入：

```text
altitude_controller/config.lua
altitude_controller/client.lua
altitude_controller/rednet_util.lua
altitude_controller/pid.lua
altitude_controller/feedforward.lua
altitude_controller/runtime.lua
altitude_controller/display.lua
altitude_controller/main.lua
altitude_controller/startup.lua
altitude_controller/test_iohub.lua
```

如果保持文件夹结构，运行：

```text
altitude_controller/test_iohub.lua <hubID> 7.5 10 0.5
```

如果直接把三个文件放在新电脑根目录，运行：

```text
test_iohub.lua <hubID> 7.5 10 0.5
```

参数含义：

- `<hubID>`：IO Hub 电脑 ID
- `7.5`：写给 `SteamVent` 的测试命令
- `10`：保持 10 秒
- `0.5`：每 0.5 秒读取一次 IO Hub 快照

预期输出：

```text
ping=pong
before alt=... vs=... out=...
write-ok output=...
tick=001 alt=... vs=... out=... cmd=... exact=...
...
stop-ok
```

这只验证三件事：

1. Altitude Controller 电脑能通过 rednet 找到 IO Hub。
2. 能从 IO Hub 读到 `Altitude` 和 `VerticalSpeed`。
3. 能通过 IO Hub 写 `SteamVent`，并由 IO Hub 常驻 PWM 循环维持小数输出。

如果 `timeout waiting for IO Hub`，先检查两台电脑是否在同一网络、`modemSide` 是否正确、IO Hub 是否正在运行 `main.lua`、`protocol` 是否一致。

当前配置默认：

```lua
-- io_hub/fleet_config.lua
modemSide = "bottom"

-- altitude_controller/config.lua
hubID = 65
modemSide = "right"
```

这两个值都是各自电脑的本机 modem 面；若实际安装不同，优先改配置。自动扫描只是兜底。

## 第九步：启动 Altitude Controller

AC 主程序默认不启用输出，也默认不打开显示屏。先运行：

```text
altitude_controller/main.lua 100
```

如果三个文件都放在根目录，运行：

```text
main.lua 100
```

`startup.lua` 会把参数原样转发给 `main.lua`，所以手动运行 `startup.lua 100 --display` 也可以；开机自动运行 `startup.lua` 时没有参数，因此默认不开显示屏、不启用输出。

参数 `100` 是目标高度。若需要本机显示屏，加 `--display`：

```text
altitude_controller/main.lua 100 --display
```

不要用 CraftOS 的 `monitor <side> ...` 命令来包住控制器程序；显示屏由程序内部的 `--display` 驱动。若用 `monitor` 命令，普通终端日志会被重定向到显示屏，现象就是屏幕上滚动 `mode=cascade ...` 这类文本。

如果要启动时直接启用控制并打开显示屏：

```text
altitude_controller/main.lua 100 --enable --display
```

显示屏使用适配 3x2 monitor 的多页菜单，顶部页签可触摸切换：

```text
CTRL  当前高度/目标高度/速度/输出总览
PID   目标高度、手动速度、内外环 PID、滤波、maxStep 调参
FF    各高度悬停前馈值调参
PLOT  高度、竖直速度、输出历史曲线
IO    IO Hub 回传的传感器和执行器快照
```

确认读数和显示正常后，用以下方式启用：

```text
space
```

若不需要显示屏，只直接启用控制：

```text
altitude_controller/main.lua 100 --enable
```

键盘/显示屏按钮：

- `space` / `[ON] [OFF]`：启停控制器
- `+` / `-` / `[+1] [-1]`：目标高度微调 1
- `[+5] [-5]`：目标高度微调 5
- `PID` / `FF` 页内：点某一行选择参数，再用 `[-]` / `[+]` 调整
- `[x0.1] [x1] [x10]`：切换显示屏调参步长倍率
- `[N]`：选择下一项可调参数
- `[PON]` / `[POF]` 或键盘 `p`：切换 PID 输出。`POF` 时最终输出只等于前馈值，适合单独校准悬停前馈表
- `[RD]` 或键盘 `l`：从 `tuning.lua` 读取当前调参配置
- `[WR]` 或键盘 `s`：把当前调参配置写入 `tuning.lua`，下次启动自动加载
- `m` / `[M]`：切换 `cascade -> speed -> feedforward`
- `r`：重置 PID 积分
- `q`：退出并向 IO Hub 发送 `stop_all`

当前算法：

```text
外环高度 PID: 目标高度 - 当前高度 -> 目标竖直速度
内环速度 PID: 目标竖直速度 - 当前竖直速度 -> SteamVent 修正量
最终输出: 高度前馈值 + 内环修正量
```

总输出只在最后限制到 `0..15`。不要再给内环速度 PID 单独加很窄的 `outputMin/outputMax`，否则会变成“前馈值 ± 小修正量”，执行器无法打满，低前馈高度段会出现明显稳态误差。

调参读写采用覆盖文件：`[WR]` 会写出 `altitude_controller/tuning.lua`（根目录部署时为 `tuning.lua`），`[RD]` 会在不重启程序的情况下重新读入该文件。该文件只保存控制器调参项，不保存 IO Hub ID、modem 面、传感器/执行器逻辑名等硬件配置；下次启动 `main.lua` 会自动读取并覆盖 `config.lua` 中的控制器默认值。

默认 `enabled = false`，这是安全策略。实际飞行前应先确认显示屏读数、`VerticalSpeed` 极性、`SteamVent` 输出方向都正确。

## 当前约束

- 当前已接入 Altitude Controller 的基础串级高度控制，以及 Pitch/Roll SAS 的基础 PID 混控；FC 和横向控制仍未接入。
- `io_hub` 是单点硬件抽象层；后续 FC 负责混控和权限仲裁。
- 小数执行器命令通过 PDM/PWM 在相邻整数输出之间切换，长期平均值接近目标值。
- `SteamVent` 输出按 `0..15` 红石模拟强度处理；`Create_RotationSpeedController` 输出按其方法接口的转速目标处理，当前配置限幅为 `-256..256`。
- 主推已在 IO Hub 中以 `MainThrusterRight` / `MainThrusterLeft` 接入，分别对应 `Create_RotationSpeedController_5` / `_6`；左推 raw 极性相反，已在 IO Hub 中用 `scale = -1` 归一化。

## Pitch/Roll SAS 节点

四个控制螺旋桨的 raw 外设名只在 `io_hub/fleet_config.lua` 内维护。当前观测结果：

```text
PropTailRight -> Create_RotationSpeedController_1 -> A+ B+
PropTailLeft  -> Create_RotationSpeedController_2 -> A+ B-
PropNoseRight -> Create_RotationSpeedController_3 -> A- B+
PropNoseLeft  -> Create_RotationSpeedController_4 -> A- B-
```

其中 `A = pitch`，`A+ = 翘头`；`B = roll`，`B+ = 从后看顺时针`。`attitude_sas` 只使用逻辑执行器名，并从 IO Hub 配置读取 `pitchEffect / rollEffect` 生成四路混控输出。

先在 IO Hub 电脑上运行：

```text
main.lua
```

在 SAS 电脑上做链路测试：

```text
attitude_sas/test_iohub.lua <hubID> 16 4 0.5
```

如果 SAS 报 `missing pitch/roll sensor`，先回到 IO Hub 电脑运行 `test_io.lua sensors 0.5 5`。若没有 `GimbalXAngle/GimbalZAngle`，说明 IO Hub 电脑没有加载正确的 `fleet_config.lua/sensors.lua`，或 IO Hub `main.lua` 没有重启。

启动 SAS，默认开启 Pitch/Roll，但默认不开显示屏：

```text
attitude_sas/main.lua <hubID>
```

把 `attitude_sas/startup.lua` 作为 SAS 电脑的开机入口时，也保持同样默认：Pitch/Roll 开启、Display 关闭。运行后可在电脑终端按键控制：

```text
p: Pitch 开关
b: Roll 开关
d: Display 开关
l: 读取 tuning
s: 写入 tuning
r: 重置 PID
q: 退出并把四路姿态桨清零
```

按 `s` 写出的 `attitude_sas/tuning.lua` 会保存 Pitch/Roll 两个环的开启状态；下次启动会先读 tuning 覆盖默认值。Display 开关不保存，始终由启动参数 `--display` 或终端 `d` 键控制。

只开显示屏：

```text
attitude_sas/main.lua <hubID> --display
```

启动时直接开启两个控制器并打开显示屏：

```text
attitude_sas/main.lua <hubID> --enable --display
```

也可以只开启单轴：

```text
attitude_sas/main.lua <hubID> --pitch --display
attitude_sas/main.lua <hubID> --roll --display
```

如果不保留 `attitude_sas/` 目录、而是把文件平铺到电脑根目录，显示模块文件名使用：

```text
attitude_config.lua        <- attitude_sas/config.lua
attitude_client.lua        <- attitude_sas/client.lua
attitude_pid.lua           <- attitude_sas/pid.lua
attitude_runtime.lua       <- attitude_sas/runtime.lua
attitude_display.lua       <- attitude_sas/display.lua
attitude_rednet_util.lua   <- attitude_sas/rednet_util.lua
```

然后用根目录的启动文件运行：

```text
main.lua <hubID> --display
```

## FC 前进速度 PID

FC 只通过 IO Hub 逻辑名读写：

```text
ForwardSpeed
MainThrusterLeft
MainThrusterRight
```

当前控制律：

```text
速度 PID: 目标前进速度 - 当前前进速度 -> 主推共同量 base
转弯输入: turnCommand -> 左右主推差速
左主推: base + turnCommand * leftTurnSign
右主推: base + turnCommand * rightTurnSign
```

IO Hub 已把左右主推极性归一化，所以 FC 中正的主推命令都表示前推。

启动：

```text
fc/main.lua <hubID> <targetSpeed> --enable
```

例如：

```text
fc/main.lua 65 2 --enable
```

也可以先不开输出，只观察读数：

```text
fc/main.lua 65 --target 2
```

如果出现 `timeout waiting for IO Hub`，先在 FC 电脑运行：

```text
fc/probe_iohub.lua 65
```

若 `PING ERR: timeout waiting for IO Hub`，问题在通信链路，不在前进 PID 或显示屏：确认 IO Hub 电脑正在运行 `main.lua`，确认两台电脑在同一有线 modem 网络内，且 `fleet_config.lua` 与 `fc/config.lua` 的 `protocol` 都是 `moab_fc_v1`。

FC 显示分两种模式：

- `compact`：实机运行 HUD，给左侧 1x1 显示屏，默认启用。
- `debug`：调 PID 用的大屏 UI，给 3x2 显示屏。

默认配置是：

```lua
display = {
    enabled = true,
    mode = "compact",
    profiles = {
        compact = { side = "left" },
        debug = { side = "", remoteName = "" }
    }
}
```

调 PID 时接 3x2 显示屏。如果它接在 IO Hub 的同一个有线 modem 网络上，FC 通常也能直接 `peripheral.wrap` 到它。先在 FC 电脑运行：

```text
fc/probe_displays.lua
```

脚本会列出 FC 可见的所有 monitor 名称和尺寸，并在面积最大的显示屏上写一行测试字。若 3x2 不在列表里，说明 FC 不能直接访问它，需要检查有线 modem 网络连接。

`debug` 模式在 `side` 和 `remoteName` 都为空时，会自动选择 FC 可见 monitor 中面积最大的那个，通常就是 IO Hub 3x2。然后运行：

```text
fc/main.lua 65 --target 2 --enable --debug-display
```

如果自动选择不对，就在 `fc/config.lua` 的 `display.profiles.debug.remoteName` 填 `probe_displays.lua` 输出的 monitor 名称。

实机接打字机时使用左侧 1x1 显示屏，运行：

```text
fc/main.lua 65 --target 2 --enable --compact-display
```

默认会从 `fc/config.lua` 的 `typewriter.side = "top"` 读取 Linked Typewriter。它和终端键盘使用同一套 action：

```text
Space: 前进 PID 输出开关
W/S: 目标前进速度 +/- speedStep，支持按住重复
A/D: 左右主推差速 +/- turnStep，支持按住重复
X: 差速回中
0: 目标速度归零
L: 读取 fc/tuning.lua
V: 写入 fc/tuning.lua
R: 重置 PID
M: 显示屏开关
Q: 退出并将左右主推写 0
```

如果打字机不在 `top`，只改：

```lua
typewriter = {
    side = "实际所在面"
}
```

调 PID 时如果不想让打字机输入参与控制，可加：

```text
fc/main.lua 65 --target 2 --enable --debug-display --no-typewriter
```

不要用 `monitor left fc/main.lua ...` 这种方式启动；那会把终端日志重定向到显示屏。直接在 FC 电脑终端运行 `fc/main.lua ...`，程序会自己 `peripheral.wrap("left")` 驱动左侧显示屏。

如果只想在终端刷日志、不写显示屏：

```text
fc/main.lua 65 --target 2 --no-display
```

终端按键：

```text
space: 前进 PID 输出开关
w/s: 目标前进速度 +/- speedStep
a/d: 左右主推差速 +/- turnStep
x: 差速回中
0: 目标速度归零
l: 读取 fc/tuning.lua
v: 写入 fc/tuning.lua
r: 重置 PID
m: 显示屏开关
q: 退出并将左右主推写 0
```

显示屏触摸按钮：

```text
[ON]/[OFF]: 前进 PID 输出开关
[V-]/[V+]: 目标速度减小/增大
[L]/[R]: 左右主推差速
[C]: 差速回中
[0]: 目标速度归零
[RD]/[WR]: 读写 tuning
```

按 `v` 写出的 tuning 会保存 `enabled`、目标速度、差速量、PID 参数和混控参数。硬件逻辑名仍只维护在 `io_hub/fleet_config.lua` 与 `fc/config.lua` 的 `actuators` 字段中。

平铺模式下姿态 SAS 只读取上述 `attitude_*` 模块名，不再读取根目录的 `config.lua/client.lua/pid.lua/runtime.lua/display.lua`，避免误加载高度控制器文件。调参保存文件会写到 `attitude_tuning.lua`。

键盘/显示屏按钮：

- `p` / `[PON] [POFF]`：Pitch PID 开关
- `b` / `[RON] [ROFF]`：Roll PID 开关
- `[RD]` 或 `l`：读取 `attitude_sas/tuning.lua`
- `[WR]` 或 `s`：写出当前调参到 `attitude_sas/tuning.lua`
- `[R]` 或 `r`：重置 PID 积分和曲线
- `q`：退出并只将四个姿态桨写为 `0`；不会调用 IO Hub `stop_all`，因此不会停止高度控制器的 `SteamVent`

Pitch 前馈接口在 `attitude_sas/config.lua` 的 `controller.pitchFeedforward` 中配置：

```lua
pitchFeedforward = {
    enabled = true,
    sourceActuator = "",
    gain = 0,
    bias = 0
}
```

如果后续 IO Hub 中加入主引擎逻辑名，例如 `MainThrust`，把 `sourceActuator = "MainThrust"`，则 pitch 修正量会叠加：

```text
pitch_ff = bias + gain * MainThrustCommand
pitch_total = pitch_pid + pitch_ff
```

## Steam Vent 执行器链路

源码显示 Steam Vent 读取邻近红石强度：

```java
level.getBestNeighborSignal(blockPos)
```

气体输出按红石强度线性缩放：

```java
gasOutput = steamAmount * efficiency * (signalStrength / 15)
```

因此 IO Hub 不直接 wrap `steam_vent`，而是驱动接到 Steam Vent 的 `redstone_relay`：

```lua
actuators = {
    SteamVent = {
        enabled = true,
        driver = "redstone_relay",
        peripheralType = "redstone_relay",
        remoteName = "",
        outputSide = "back",
        clearOtherSides = true,
        outputMin = 0,
        outputMax = 15,
        pwmEnabled = true,
        pwmPeriod = 0.05
    }
}
```

如果同一有线网络里有多个 `redstone_relay`，先用 `inspect_to_file.lua` 找到精确外设名，再填 `remoteName = "redstone_relay_..."`。
`redstone_relay` 接在调制解调器哪一面只影响外设连接；`outputSide` 表示 relay 自己从哪一面输出红石给 Steam Vent。以实测响应为准，当前链路使用 `back`。

如果曾经用六面扫描或旧配置输出过 `15`，relay 的其它面可能残留红石输出。先清零：

```text
clear_relay_sides.lua SteamVent
```

正式配置里 `clearOtherSides = true`，表示 `SteamVent` 独占这个 relay；每次输出都会先把其它五个面清成 `0`，避免旧方向残留导致“无论命令多少都像 15”。

小数输出必须持续刷新 PDM/PWM。一次性写入命令只能设置目标值，随后必须有长驻循环维持占空序列。专门测试小数用：

```text
hold_actuator.lua SteamVent 7.5 10
```

这个脚本会持续 10 秒刷新 PWM，并打印配置输出面与六个 relay 面的回读。如果 `back` 显示 `7/8` 交替，但 Steam Vent 仍表现为满档，说明问题不是 CraftOS 输出值，而是 Steam Vent 对邻近红石的实际解释或还有其它红石源参与。

优先用专用脚本探测链路：

```text
probe_steam_vent.lua
```

也可以显式指定参数：

```text
probe_steam_vent.lua SteamVent 15 7.5 2 5
```

含义依次是：执行器逻辑名、满档命令、小数档命令、满档保持秒数、小数档保持秒数。脚本会依次输出 `0 -> 15 -> 7.5 -> 0`，并打印 `redstone_relay` 回读值和小数档前 40 tick 的 PDM 脉冲序列。

判断规则：

- 如果报 `cannot find peripheral type [redstone_relay]`，说明继电器不在 IO Hub 的有线网络里，或 `peripheralType` 配错。
- 如果报 `cannot wrap peripheral [...]`，说明 `remoteName` 不是实际外设名。
- 如果 relay 回读能从 `0` 到 `15`，但 Steam Vent 没反应，优先检查 `outputSide` 和 Steam Vent 邻接红石方向。
- 如果 `7.5` 档能看到 `7/8` 交替脉冲，说明小数 PDM 输出逻辑已通。

如果 relay 回读正常但 Steam Vent 没响应，用六面扫描：

```text
probe_relay_sides.lua SteamVent 15 4
```

它会让同一个 `redstone_relay` 的 `left/right/front/back/top/bottom` 依次输出 15，每个方向保持 4 秒。观察 Steam Vent 在哪一段有响应，然后把该方向写回：

```lua
outputSide = "这里填实测响应方向"
```

如果六个方向都无响应，再用原版拉杆/红石块直接贴 Steam Vent 测试。若直接红石也无响应，问题不在 ComputerCraft 驱动，而在 Steam Vent 的工作条件、装配状态、蒸汽来源或该方块本身的红石接收逻辑。

泛用测试仍可用：

```text
test_io.lua actuator SteamVent 15 2
test_io.lua actuator SteamVent 7.5 5
test_io.lua stop
```
