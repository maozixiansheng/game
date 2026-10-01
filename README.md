# 倒爷修仙传 — 完整项目交付包

> 这是一份**可直接运行**的完整游戏源码包。
> 把本目录原样复制进一个空的 UrhoX(星火编辑器 / TapTap Code)项目，配置好多人与入口，执行一次 build 即可启动。

- **游戏类型**：文字 MUD 修仙网游（多人持久世界）
- **架构**：客户端 / 服务端分离，Remote Event 通信
- **运行模式**：`multiplayer.persistent_world`，`max_players = 100`
- **代码量**：33,589 行 / 16 个 Lua 文件
- **资源**：2 个字体 + 7 个音频 + 14 张图片（已全部包含在本包内）
- **引擎依赖**：全部为引擎内置，无需额外安装

---

## 一、目录结构

```
scripts_export/
├── README.md                  ← 本文件
├── MIGRATION.md               ← 逐步迁移指南（照着做即可）
├── MANIFEST.txt               ← 文件清单 + 校验和
│
├── scripts/                   ← 复制到新项目 scripts/
│   ├── main.lua               (23 行)    入口：自动判断客户端/服务端
│   ├── config/
│   │   ├── Settings.lua       (3,289 行) 全局配置：事件名/NPC/物品/技能/境界/战场/帮会
│   │   └── Theme.lua          (212 行)   UI 主题：配色、字体、贴图路径
│   ├── game/                  ← 服务端玩法逻辑
│   │   ├── Combat.lua         (1,059 行) 回合制战斗：伤害计算、PvE/PvP
│   │   ├── Cultivation.lua    (418 行)   修炼：打坐、熟练度、突破
│   │   ├── Market.lua         (514 行)   交易阁：上架/下架/购买/搜索
│   │   └── Tutorial.lua       (395 行)   新手引导：步骤卡片
│   └── network/               ← 网络层（客户端 / 服务端 / 共用）
│       ├── Client.lua         (13,786 行) 客户端主体：全部 UI 与交互
│       ├── Server.lua         (9,648 行)  服务端主体：全部权威逻辑
│       ├── Shared.lua         (493 行)    双端共用：事件注册、属性计算
│       ├── EntryFlow.lua      (656 行)    开局流程：欢迎页 / 创角 / 标题页
│       ├── BattlefieldMap.lua (1,421 行)  域外战场大地图：NanoVG 渲染、镜头跟随
│       ├── StrongholdPanel.lua(371 行)    据点交互面板
│       ├── TitlePanel.lua     (162 行)    称号面板
│       ├── Quest.lua          (457 行)    任务系统：主线/日常/Boss
│       └── Activity.lua       (685 行)    活动/成就系统
│
├── assets/                    ← 复制到新项目 assets/
│   ├── Fonts/                 (2 个 ttf，必须复制，否则 UI 无文字)
│   ├── audio/                 (2 首 BGM + 5 个音效)
│   └── image/                 (战斗立绘 + 背景贴图)
│
└── .project/                  ← 复制到新项目 .project/（或参照其内容手工配置）
    ├── project.json           ← 入口配置
    └── settings.json          ← 多人模式 + 构建配置
```

---

## 二、快速上手（3 步）

### 步骤 1 — 复制文件

在 UrhoX / 星火编辑器中**新建一个空项目**，然后把本包内容复制进去：

| 本包路径 | → 新项目路径 |
|---|---|
| `scripts/` | `scripts/` |
| `assets/` | `assets/` |
| `.project/settings.json` 的内容 | 合并进 `.project/settings.json` |
| `.project/project.json` 的内容 | 合并进 `.project/project.json` |

> ⚠️ 注意：**不要**复制本包的 `.project/` 目录去覆盖整个目录，新项目的 `.project/` 里还有 `project_id` 等引擎自动生成的字段。只需按下面第三步合并配置即可。

### 步骤 2 — 合并项目配置

**`.project/settings.json`** 必须有这段（决定多人持久世界模式）：

```json
{
  "@runtime": {
    "multiplayer": {
      "enabled": true,
      "max_players": 100,
      "persistent_world": {
        "enabled": true
      }
    }
  }
}
```

**`.project/project.json`** 的入口必须同时是客户端和服务端入口：

```json
{
  "entry": "main.lua",
  "entry@client": "main.lua",
  "entry@server": "main.lua"
}
```

### 步骤 3 — 构建

在 AI 助手或编辑器里执行构建，**必须同时指定客户端与服务端入口**：

```
build entry_client=main.lua entry_server=main.lua
```

同时确保构建参数为：

```
multiplayer.enabled = true
multiplayer.max_players = 100
multiplayer.persistent_world.enabled = true
```

构建成功即可预览。**多人玩法需要至少 2 个客户端连入**才能完整体验交易、帮会、据点等系统。

---

## 三、运行架构

### 3.1 模块加载流程

```
main.lua
  ├─ IsServerMode() == true  → require("network.Server").Start()
  └─ IsServerMode() == false → require("network.Client").Start()
```

`main.lua` 只有 23 行，它是**唯一入口**，本身不含玩法逻辑。

### 3.2 依赖关系图

```
                        config.Settings  ← 被所有模块引用（事件名/常量/配置表）
                              ▲
                              │
                        config.Theme     ← 仅客户端 UI 使用（配色/字体/贴图）

服务端 (Server.lua)
  ├── network.Shared        （双端共用：事件注册、CalcStats）
  ├── game.Combat           （战斗，依赖 Shared + cjson）
  ├── game.Cultivation      （修炼，依赖 Shared）
  ├── game.Market           （交易阁，依赖 Shared）
  ├── network.Quest         （任务，依赖 Shared + Server）
  └── network.Activity      （活动/成就，依赖 Settings + cjson）

客户端 (Client.lua)
  ├── network.Shared
  ├── config.Theme
  ├── urhox-libs/UI         （引擎内置 UI 组件库）
  ├── game.Tutorial         （新手引导）
  ├── network.BattlefieldMap（战场大地图）
  ├── network.StrongholdPanel（据点面板）
  ├── network.EntryFlow     （开局流程）
  └── network.TitlePanel    （称号面板）
```

**没有循环依赖，没有缺失模块，整包自洽。**

### 3.3 通信机制

```lua
-- 客户端 → 服务端
SendToServer(Settings.EVENTS.REQ_XXX, { Key = value })

-- 服务端 → 客户端
conn:SendRemoteEvent(Settings.EVENTS.PUSH_XXX, true, variantMap)
```

> ⚠️ **新增事件时必须同时注册三处**：
> 1. `config/Settings.lua` 的 `Settings.EVENTS`
> 2. `network/Shared.lua` 的 `SERVER_EVENTS`
> 3. `network/Shared.lua` 的 `CLIENT_EVENTS`
>
> 漏掉任何一处，事件都不会生效（这是本项目最容易踩的坑）。

### 3.4 数据持久化（云存档）

全部使用引擎内置的 `serverCloud` API，**无需自建数据库**：

| API | 用途 |
|---|---|
| `serverCloud.score` | 单值存储（玩家存档、属性） |
| `serverCloud.money` | 货币系统（silver 银两 / spirit_stone 灵石） |
| `serverCloud.list` | 列表存储（注册表、帮会、交易阁挂单） |
| `serverCloud.rank` | 排行榜 |

> ⚠️ 云存档按 `app_id` 隔离。**换新项目 = 全新存档，所有玩家从零开始**，这是预期行为。

---

## 四、核心系统一览

| 系统 | 服务端 | 客户端 | 说明 |
|---|---|---|---|
| 连接 / 存档 | `Server.lua` `OnClientIdentity` | `Client.lua` `OnConnected` | 上线加载、下线存档 |
| 开局流程 | — | `EntryFlow.lua` | 欢迎页 → 创角 → 标题页 |
| 场景 / 地图 | `OnReqChangeSpot` | 场景描述区 | 多场景切换 |
| 战斗 | `game/Combat.lua` | 战斗 UI | 回合制 PvE / PvP |
| 修炼 / 突破 | `game/Cultivation.lua` | 修炼面板 | 境界提升 |
| 交易阁 | `game/Market.lua` | 交易面板 | 玩家间寄售交易 |
| NPC / 商店 | `OnReqNpcOption` | 商店面板 | 多 NPC 交互 |
| 帮会 | 帮会 handler | 帮会面板 | 创建 / 加入 / 退出 |
| 领地战 | 据点 handler | `StrongholdPanel.lua` | 据点攻防 / 占领 |
| 域外战场 | 位置同步 | `BattlefieldMap.lua` | NanoVG 大地图自由移动 |
| 任务 | `Quest.lua` | 任务面板 | 主线 / 日常 / Boss |
| 活动 / 成就 | `Activity.lua` | 日常 / 周常面板 | 日常 / 周常 / 据点成就 |
| 炼丹 | `OnReqAlchemyCraft` | 炼丹面板 | 丹药合成 |
| 炼器 | `OnReqForgeCraft` | 炼器面板 | 装备打造 |
| 灵石系统 | 灵石 handler | 灵石面板 | 功法升阶 / 称号购买 |
| 称号 | 称号 handler | `TitlePanel.lua` | 称号展示 / 切换 |
| 管理员 | Admin handler | 管理面板 | 查询 / 修改玩家数据 |
| 聊天 | `OnReqChatSend` | 聊天面板 | 世界 / 门派 / 系统频道 |
| 新手引导 | — | `Tutorial.lua` | 步骤式教学 |
| 广告奖励 | `OnReqAdReward` | 广告按钮 | 看广告获奖励 |

---

## 五、资源清单

资源引用共 25 处，全部已包含在本包 `assets/` 内。

### 字体（必须！缺失则 UI 无文字）

| 文件 | 用途 |
|---|---|
| `assets/Fonts/WenKai-Regular.ttf` | 主 UI 字体（霞鹜文楷） |
| `assets/Fonts/WenKai-Light.ttf` | 细体 UI 字体 |

> `Fonts/MiSans-Regular.ttf` 在代码中也有引用，但它是 **UrhoX 引擎内置的兜底字体**（见 `urhox-libs/UI/Core/UI.lua`），**不需要**随包提供。

### 音频

| 文件 | 用途 |
|---|---|
| `audio/music_1780329458038.ogg` | 城镇 BGM |
| `audio/music_1780330016001.ogg` | 战斗 BGM |
| `audio/sfx/sfx_attack.ogg` | 攻击音效 |
| `audio/sfx/sfx_hit.ogg` | 受击音效 |
| `audio/sfx/sfx_crit.ogg` | 暴击音效 |
| `audio/sfx/sfx_victory.ogg` | 胜利音效 |
| `audio/sfx/sfx_defeat.ogg` | 战败音效 |

### 图片

| 文件 | 用途 |
|---|---|
| `image/p_idle / p_run / p_attack / p_hurt_*.png` | 玩家战斗立绘（4 帧状态） |
| `image/m_idle / m_run / m_attack / m_hurt_*.png` | 怪物战斗立绘（4 帧状态） |
| `image/bg_ink_paper_*.png` | 主背景（深墨色） |
| `image/bg_scroll_panel_*.png` | 竹简卡片底纹 |
| `image/welcome_bg_*.png` | 欢迎页背景 |
| `image/title_seal_style_*.png` | 标题页印章样式 |
| `image/title_logo_*.png` | 标题 Logo |
| `image/logo_transparent_*.png` | 透明 Logo |
| `image/game_icon_*.png` | 游戏图标 |

> 资源路径遵循引擎规则：`assets/` 是资源根目录，代码中**从下一级开始写**（如 `"Fonts/WenKai-Regular.ttf"`），**不要**写成 `"assets/Fonts/..."`。

---

## 六、重要注意事项

1. **必须开启多人持久世界**
   `multiplayer.enabled = true` 且 `persistent_world.enabled = true`，否则 Server.lua 的逻辑不会运行。

2. **构建必须同时指定双入口**
   `build entry_client=main.lua entry_server=main.lua`。只指定单入口会导致 `IsServerMode()` 判断异常。

3. **字体必须复制**
   缺少 `assets/Fonts/` 会导致所有 UI 文字无法渲染（黑屏或空白面板）。

4. **新增事件必须三处注册**
   见 §3.3，漏注册是最高频的 bug 来源。

5. **大文件提示**
   `Client.lua`（13,786 行）与 `Server.lua`（9,648 行）体量较大。后续如需维护，建议按功能拆分（面板 / 事件处理 / 渲染）。

6. **Lua 5.4 整数陷阱**
   传递给 `string.format("%d", ...)` 的值必须先用 `math.floor()` 转成整数，否则运行时报错。

7. **零硬编码，完全可移植**
   代码中不含任何 `project_id` / `app_id` / `user_id`，复制到任何项目都能跑。

8. **代码质量现状**
   本包代码通过 UrhoX LSP 静态检查：**0 Error**（766 Warning / 362 Hint，多为类型标注类提示，不影响运行）。

---

## 七、验收清单

复制完成后，逐项确认：

- [ ] `scripts/` 下 16 个 `.lua` 文件齐全（对照 `MANIFEST.txt`）
- [ ] `assets/Fonts/` 下 2 个 ttf 存在且非空
- [ ] `assets/audio/` 下 7 个 ogg 存在
- [ ] `assets/image/` 下 14 张图片存在
- [ ] `.project/settings.json` 已配置 `multiplayer.enabled = true`
- [ ] `.project/project.json` 已配置双入口
- [ ] 执行 `build entry_client=main.lua entry_server=main.lua` 构建成功
- [ ] 预览可见欢迎页 → 可进入游戏

---

## 八、版本信息

| 项目 | 值 |
|---|---|
| 交付包版本 | v12.0 |
| 导出日期 | 2026-10-01 |
| 代码量 | 33,589 行 / 16 文件 |
| LSP 检查 | 0 Error |
| 上一版 | v10.0（2026-06-05，29,357 行 / 14 文件） |

**相对 v10.0 的变更**：
- 新增 `config/Theme.lua`（UI 主题系统，212 行）
- 新增 `network/EntryFlow.lua`（开局流程，656 行）
- `Client.lua` 12,264 → 13,786 行
- `Server.lua` 8,501 → 9,648 行
- `BattlefieldMap.lua` 1,408 → 1,421 行
- 补全字体资源（WenKai 两个 ttf 已随包提供）
