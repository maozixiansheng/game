-- ============================================================================
-- network/Server.lua - 服务端核心逻辑
-- ============================================================================

local Server = {}
local Shared  = require("network.Shared")
local Combat  = require("game.Combat")
local Cultivation = require("game.Cultivation")
local Market  = require("game.Market")
local Quest   = require("network.Quest")
local Activity = require("network.Activity")
local Settings = Shared.Settings

-- 前置声明（定义在域外战场模块，但 LoadGuildData 中引用）
local layerState_
local PushPvpLadderData  -- 天梯数据推送（定义在8600+行，OnBattleFinished中引用）

-- ============================================================================
-- 门派配置表（数据驱动，新增门派只需在此加入口）
-- ============================================================================
local SECT_CONFIG = {
    sword_sect = {
        display      = "剑宗",
        basic_skill  = "basic_sword",
        scene        = "sword_sect",
        recruiter    = "sect_recruiter",
        master_npc   = "sect_master",
        master_title = "掌门",
        join_msg     = "门人拱手一礼：「恭迎师弟入门！剑宗以剑立派，望你勤加修炼，光大门楣。」\n\n<绿>你加入了剑宗！</绿>",
        grant_msg    = "<黄>剑宗掌门亲自传授《基础剑法》！</黄>",
        wrong_sect   = "掌门说：「你并非剑宗弟子。」",
        elders = {
            { npc_id = "wind_elder",     branch = "swift",    display = "风长老"  },
            { npc_id = "lone_elder",     branch = "heavy",    display = "独孤长老" },
        },
    },
    iron_sect = {
        display      = "铁壁宗",
        basic_skill  = "iron_basic",
        scene        = "iron_sect",
        recruiter    = "iron_recruiter",
        master_npc   = "iron_master",
        master_title = "掌门",
        join_msg     = "门人抱拳行礼：「铁壁宗欢迎勇士！吾宗以铁铸体，以守为攻，愿你早日练就金刚不坏之身。」\n\n<绿>你加入了铁壁宗！</绿>",
        grant_msg    = "<黄>铁壁宗掌门亲授《铁壁心法》！</黄>",
        wrong_sect   = "掌门说：「你并非铁壁宗弟子。」",
        elders = {
            { npc_id = "shield_elder",   branch = "shield",   display = "盾卫长老" },
            { npc_id = "ironbody_elder", branch = "ironbody", display = "铁身长老" },
        },
    },
    medicine_sect = {
        display      = "药王谷",
        basic_skill  = "herb_basic",
        scene        = "medicine_sect",
        recruiter    = "medicine_recruiter",
        master_npc   = "medicine_master",
        master_title = "谷主",
        join_msg     = "弟子温和地点头：「药王谷欢迎有缘人。医武两道，相辅相成，望你潜心钻研，医济苍生。」\n\n<绿>你加入了药王谷！</绿>",
        grant_msg    = "<黄>药王谷谷主亲授《基础医典》！</黄>",
        wrong_sect   = "谷主说：「你并非药王谷弟子。」",
        elders = {
            { npc_id = "heal_elder",   branch = "heal",   display = "治愈长老" },
            { npc_id = "poison_elder", branch = "poison", display = "毒功长老" },
        },
    },
    shadow_sect = {
        display      = "天影楼",
        basic_skill  = "shadow_basic",
        scene        = "shadow_sect",
        recruiter    = "shadow_recruiter",
        master_npc   = "shadow_master",
        master_title = "楼主",
        join_msg     = "影使压低声音：「天影楼只留有用之人。速度与隐匿是你的道，切记，行于无形，杀于无声。」\n\n<绿>你加入了天影楼！</绿>",
        grant_msg    = "<黄>天影楼楼主亲授《基础身法》！</黄>",
        wrong_sect   = "楼主说：「你并非天影楼弟子。」",
        elders = {
            { npc_id = "dart_elder",   branch = "dart",   display = "暗器长老" },
            { npc_id = "shadow_elder", branch = "shadow", display = "影步长老" },
        },
    },
    qidan_sect = {
        display      = "器丹宗",
        basic_skill  = "alchemy_basic",
        scene        = "qidan_sect",
        recruiter    = "qidan_recruiter",
        master_npc   = "qidan_master",
        master_title = "宗主",
        join_msg     = "丹童含笑引路：「器丹宗以丹入道，以器证法，炼丹炼器双修。天下突破丹药皆出我宗，你肩上的担子不轻啊。」\n\n<绿>你加入了器丹宗！</绿>",
        grant_msg    = "<黄>器丹宗宗主亲授《基础丹术》！</黄>",
        wrong_sect   = "宗主说：「你并非器丹宗弟子。」",
        elders = {
            { npc_id = "pill_elder",   branch = "pill",  display = "炼丹长老" },
            { npc_id = "forge_elder",  branch = "forge", display = "炼器长老" },
        },
    },
}

-- 反向查找表（由 SECT_CONFIG 自动构建，避免硬编码）
local RECRUITER_TO_SECT = {}  -- npcId → sectId
local MASTER_TO_SECT    = {}  -- npcId → sectId
local NPC_TO_ELDER      = {}  -- npcId → { sect_id, branch, display }
local SCENE_TO_SECT     = {}  -- sceneName → sectId
local TRIAL_NPC_TO_SECT = {}  -- npcId → sectId（试炼执事）

for sectId, cfg in pairs(SECT_CONFIG) do
    RECRUITER_TO_SECT[cfg.recruiter]  = sectId
    MASTER_TO_SECT[cfg.master_npc]    = sectId
    SCENE_TO_SECT[cfg.scene]          = sectId
    for _, elder in ipairs(cfg.elders) do
        NPC_TO_ELDER[elder.npc_id] = {
            sect_id = sectId,
            branch  = elder.branch,
            display = elder.display,
        }
    end
end

-- 构建试炼NPC映射
for sectId, quest in pairs(Settings.SECT_TRIAL.QUESTS) do
    TRIAL_NPC_TO_SECT[quest.npc_id] = sectId
end

-- ============================================================================
-- 服务端状态
-- ============================================================================

-- 在线玩家缓存 { [uid] = playerData }
-- playerData 是内存中的完整玩家数据，定期与云端同步
local players_ = {}

-- uid -> connection 映射
local connections_ = {}

-- 当前传闻文本（持久化到云端，服务端启动时加载）
local systemNews_ = "交流提意见进Q群：584352243"

-- 聊天消息缓冲区（各频道最近 50 条）
-- 结构：{ channel = "world"|"sect"|"system", sender = name, text = str, time = t }
local CHAT_MAX_HISTORY = 50
local chatHistory_ = { world = {}, sect = {}, system = {} }

-- 玩家名 -> uid 注册表（在线玩家自动注册，用于管理员离线查询）
local playerRegistry_ = {}
-- uid set：已写入云端注册表的 uid，避免重复写入
local registryUidSet_ = {}

-- 客户端已就绪标志（CLIENT_READY 到达时云端数据可能还没加载完）
local clientReady_ = {}

-- 邀请码 → uid 查找表（在线玩家登录时注册）
local inviteCodes_ = {}

-- 战利品待拾取表 { [token] = { uid, item, expiresAt } }
-- 玩家点击日志中的链接发送 token 来领取，每个 token 只能用一次
local pendingLoots_ = {}
local lootTokenCounter_ = 0

-- 云端同步计时器（每30秒同步一次）
local syncTimer_ = 0
local SYNC_INTERVAL = 10.0  -- 每10秒自动存档（减少重启丢数据风险）

-- 修炼/经验更新计时器（每秒计算一次）
local gameTimer_ = 0
local GAME_TICK = 1.0

-- 经验推送计时器（修炼中每5秒推送一次轻量经验更新）
local expPushTimer_ = 0
local EXP_PUSH_INTERVAL = 5.0

-- 在线时长计时器（每60秒更新一次日常在线任务）
local onlineTimer_ = 0
local ONLINE_TICK = 60.0

-- 过期商品清理（每10分钟一次）
local marketCleanTimer_ = 0
local MARKET_CLEAN_INTERVAL = 600.0

-- NPC自动补货计时器
local npcRestockTimer_ = 0
local npcRestockRunning_ = false

-- 帮会/据点数据（前向声明，供 Start/Stop 和后续帮会系统引用）
local guilds_ = {}  -- guilds_[guild_id] = { name, leader_uid, members = {uid1, uid2...}, layer }
local strongpointOwners_ = {}  -- strongpointOwners_[sp_id] = { guild_id, guild_name, captured_at }
local guildDataLoaded_ = false  -- 帮会数据是否已异步加载完成
local pendingSnapshotResend_ = {}  -- 等待帮会数据加载后补发快照的玩家

-- 帮会/据点持久化
local function SaveGuildData()
    -- 深拷贝当前数据快照，避免异步回调期间引用被覆盖
    local spSnapshot = {}
    for k, v in pairs(strongpointOwners_) do spSnapshot[k] = v end
    local guildSnapshot = {}
    for k, v in pairs(guilds_) do guildSnapshot[k] = v end
    local data = { guilds = guildSnapshot, strongpoints = spSnapshot }

    local spCount = 0
    for _ in pairs(spSnapshot) do spCount = spCount + 1 end
    print(string.format("[Server] SaveGuildData: 准备保存 %d 个据点", spCount))

    serverCloud.list:Get(0, "guild_data", {
        ok = function(list)
            if list and #list > 0 then
                -- 统一使用最后一条记录（与 LoadGuildData 读取一致）
                local targetId = list[#list].list_id
                print(string.format("[Server] SaveGuildData: 更新记录 list_id=%s (共%d条)", tostring(targetId), #list))
                serverCloud.list:Modify(targetId, data, {
                    ok = function() print("[Server] 帮会数据已保存") end,
                    error = function(c, r) print("[Server] 帮会数据保存失败:", c, r) end,
                })
            else
                serverCloud.list:Add(0, "guild_data", data, {
                    ok = function() print("[Server] 帮会数据首次写入完成") end,
                    error = function(c, r) print("[Server] 帮会数据写入失败:", c, r) end,
                })
            end
        end,
        error = function(c, r) print("[Server] 帮会数据查询失败:", c, r) end,
    })
end

local function LoadGuildData()
    serverCloud.list:Get(0, "guild_data", {
        ok = function(list)
            if list and #list > 0 and list[#list].value then
                local targetId = list[#list].list_id
                print(string.format("[Server] LoadGuildData: 读取记录 list_id=%s (共%d条)", tostring(targetId), #list))
                local d = list[#list].value
                if d.guilds then guilds_ = d.guilds end
                if d.strongpoints then strongpointOwners_ = d.strongpoints end
                -- 数据迁移：清除空键/无效键的据点条目（修复历史bug产生的脏数据）
                local invalidKeys = {}
                for k, v in pairs(strongpointOwners_) do
                    if not k or k == "" or (type(k) == "string" and k:match("^%s*$")) then
                        invalidKeys[#invalidKeys + 1] = k
                    end
                end
                for _, k in ipairs(invalidKeys) do
                    print(string.format("[Server] ⚠️ 清除无效据点键: '%s' (guild='%s')", tostring(k), tostring(strongpointOwners_[k].guild_name)))
                    strongpointOwners_[k] = nil
                end
                if #invalidKeys > 0 then
                    SaveGuildData()  -- 持久化清理结果
                end
                local gCount = 0
                for _ in pairs(guilds_) do gCount = gCount + 1 end
                local spCount = 0
                for _ in pairs(strongpointOwners_) do spCount = spCount + 1 end
                print(string.format("[Server] 帮会数据加载完成：%d个帮会，%d个据点", gCount, spCount))
                -- 打印据点详情用于调试
                for spId, info in pairs(strongpointOwners_) do
                    print(string.format("[Server]   据点 %s -> 帮会: %s", spId, tostring(info.guild_name)))
                end
                -- 补发据点快照给所有已在战场层的玩家（解决加载时序问题）
                guildDataLoaded_ = true  -- 先标记完成，确保补发的快照包含完整数据
                if spCount > 0 then
                    -- 方式1: 补发给 pendingSnapshotResend_ 中标记的玩家
                    for uid, info in pairs(pendingSnapshotResend_) do
                        if info.conn then
                            print(string.format("[Server] 补发据点快照给标记玩家: uid=%s layer=%d", tostring(uid), info.layer))
                            Server.SendLayerSnapshot(uid, info.layer, info.conn)
                        end
                    end
                    pendingSnapshotResend_ = {}
                    -- 方式2: 遍历所有在线战场玩家（确保不遗漏）
                    if layerState_ then
                        for layerNum, state in pairs(layerState_) do
                            if state.players then
                                for uid, _ in pairs(state.players) do
                                    local conn = connections_[uid]
                                    if conn then
                                        Server.SendLayerSnapshot(uid, layerNum, conn)
                                    end
                                end
                            end
                        end
                    end
                    print("[Server] 已向在线战场玩家补发据点快照")
                end
            else
                print("[Server] 无帮会历史数据，使用空表")
                guildDataLoaded_ = true
            end
        end,
        error = function(c, r) print("[Server] 帮会数据加载失败:", c, r); guildDataLoaded_ = true end,
    })
end

local function LoadActivityConfigOnStart()
    serverCloud.list:Get(0, "activity_config", {
        ok = function(list)
            if list and #list > 0 and list[#list].value then
                local d = list[#list].value
                if d.monster_respawn_delay then
                    Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY = d.monster_respawn_delay
                end
                if d.war_start_hour then
                    Settings.TERRITORY_WAR.START_HOUR = d.war_start_hour
                    Settings.TERRITORY_WAR.START_MIN  = d.war_start_min or 0
                    Settings.TERRITORY_WAR.END_HOUR   = d.war_end_hour or 21
                    Settings.TERRITORY_WAR.END_MIN    = d.war_end_min or 0
                end
                print(string.format("[Server] 活动配置加载完成: 刷怪=%.1fs 领地战=%02d:%02d~%02d:%02d",
                    Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY,
                    Settings.TERRITORY_WAR.START_HOUR, Settings.TERRITORY_WAR.START_MIN,
                    Settings.TERRITORY_WAR.END_HOUR, Settings.TERRITORY_WAR.END_MIN))
            else
                print("[Server] 无持久化活动配置，使用默认值")
            end
        end,
        error = function(c, r) print("[Server] 活动配置加载失败:", c, r) end,
    })
end

-- ============================================================================
-- 启动
-- ============================================================================
function Server.Start()
    print("[Server] 启动……")

    -- 注册服务端需要接收的事件
    Shared.RegisterServerEvents()

    -- 订阅网络事件
    SubscribeToEvent("ClientConnected",    "Server_OnClientConnected")
    SubscribeToEvent("ClientDisconnected", "Server_OnClientDisconnected")
    SubscribeToEvent("ClientIdentity",     "Server_OnClientIdentity")

    -- 订阅玩家操作事件
    SubscribeToEvent(Settings.EVENTS.CLIENT_READY,      "Server_OnClientReady")
    SubscribeToEvent(Settings.EVENTS.REQ_MOVE_SCENE,    "Server_OnReqMoveScene")
    SubscribeToEvent(Settings.EVENTS.REQ_INTERACT_NPC,  "Server_OnReqInteractNpc")
    SubscribeToEvent(Settings.EVENTS.REQ_START_BATTLE,  "Server_OnReqStartBattle")
    SubscribeToEvent(Settings.EVENTS.REQ_FLEE_BATTLE,   "Server_OnReqFleeBattle")
    SubscribeToEvent(Settings.EVENTS.REQ_USE_ITEM,      "Server_OnReqUseItem")
    SubscribeToEvent(Settings.EVENTS.REQ_CULTIVATE,     "Server_OnReqCultivate")
    SubscribeToEvent(Settings.EVENTS.REQ_STOP_CULTIVATE,"Server_OnReqStopCultivate")
    SubscribeToEvent(Settings.EVENTS.REQ_CULTIVATE_BOOST, "Server_OnReqCultivateBoost")
    SubscribeToEvent(Settings.EVENTS.REQ_RENAME,          "Server_OnReqRename")
    SubscribeToEvent(Settings.EVENTS.REQ_CREATE_CHARACTER, "Server_OnReqCreateCharacter")
    SubscribeToEvent(Settings.EVENTS.REQ_GUILD_RENAME,    "Server_OnReqGuildRename")
    SubscribeToEvent(Settings.EVENTS.REQ_TOGGLE_REVIVE,  "Server_OnReqToggleRevive")
    SubscribeToEvent(Settings.EVENTS.REQ_GUILD_BOOST,    "Server_OnReqGuildBoost")
    SubscribeToEvent(Settings.EVENTS.REQ_SKILL_TIER_UP,   "Server_OnReqSkillTierUp")
    SubscribeToEvent(Settings.EVENTS.REQ_BUY_TITLE,      "Server_OnReqBuyTitle")
    SubscribeToEvent(Settings.EVENTS.REQ_EQUIP_TITLE,    "Server_OnReqEquipTitle")
    SubscribeToEvent(Settings.EVENTS.REQ_UNBIND_SKILL,  "Server_OnReqUnbindSkill")
    SubscribeToEvent(Settings.EVENTS.REQ_EQUIP_ITEM,    "Server_OnReqEquipItem")
    SubscribeToEvent(Settings.EVENTS.REQ_UNEQUIP_ITEM,  "Server_OnReqUnequipItem")
    SubscribeToEvent(Settings.EVENTS.REQ_DISCARD_ITEM,  "Server_OnReqDiscardItem")
    SubscribeToEvent(Settings.EVENTS.REQ_MARKET_LIST,   "Server_OnReqMarketList")
    SubscribeToEvent(Settings.EVENTS.REQ_MARKET_BUY,    "Server_OnReqMarketBuy")
    SubscribeToEvent(Settings.EVENTS.REQ_MARKET_SELL,   "Server_OnReqMarketSell")
    SubscribeToEvent(Settings.EVENTS.REQ_MARKET_SELL_SILVER, "Server_OnReqMarketSellSilver")
    SubscribeToEvent(Settings.EVENTS.REQ_MARKET_CANCEL,  "Server_OnReqMarketCancel")
    SubscribeToEvent(Settings.EVENTS.REQ_MARKET_HISTORY, "Server_OnReqMarketHistory")
    SubscribeToEvent(Settings.EVENTS.REQ_MARKET_TRENDS, "Server_OnReqMarketTrends")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_LOGIN,         "Server_OnReqAdminLogin")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_SELL,          "Server_OnReqAdminSell")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_SET_NEWS,      "Server_OnAdminSetNews")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_QUERY_PLAYER,  "Server_OnAdminQueryPlayer")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_ADD_CURRENCY,  "Server_OnAdminAddCurrency")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_MODIFY_PLAYER, "Server_OnAdminModifyPlayer")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_LIST_PLAYERS,  "Server_OnAdminListPlayers")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_SET_ACTIVITY,  "Server_OnAdminSetActivity")
    SubscribeToEvent(Settings.EVENTS.REQ_SHOP_BUY,      "Server_OnReqShopBuy")
    SubscribeToEvent(Settings.EVENTS.REQ_CHANGE_SPOT,    "Server_OnReqChangeSpot")
    SubscribeToEvent(Settings.EVENTS.REQ_NPC_OPTION,     "Server_OnReqNpcOption")
    SubscribeToEvent(Settings.EVENTS.REQ_USE_SKILL,      "Server_OnReqUseSkill")
    SubscribeToEvent(Settings.EVENTS.REQ_TOGGLE_AUTO,    "Server_OnReqToggleAuto")
    SubscribeToEvent(Settings.EVENTS.REQ_SET_BATTLE_SLOTS,"Server_OnReqSetBattleSlots")
    SubscribeToEvent(Settings.EVENTS.REQ_RANK,           "Server_OnReqRank")
    SubscribeToEvent(Settings.EVENTS.REQ_CHAT_SEND,      "Server_OnReqChatSend")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_RESET_SELF,   "Server_OnAdminResetSelf")
    SubscribeToEvent(Settings.EVENTS.REQ_ADMIN_RESET_PLAYER, "Server_OnAdminResetPlayer")
    SubscribeToEvent(Settings.EVENTS.REQ_PICKUP_LOOT,        "Server_OnReqPickupLoot")
    SubscribeToEvent(Settings.EVENTS.REQ_RESET_TUTORIAL,     "Server_OnReqResetTutorial")
    SubscribeToEvent(Settings.EVENTS.REQ_SKIP_TUTORIAL,      "Server_OnReqSkipTutorial")
    SubscribeToEvent(Settings.EVENTS.REQ_AD_REWARD,          "Server_OnReqAdReward")
    SubscribeToEvent(Settings.EVENTS.REQ_BREAKTHROUGH,       "Server_OnReqBreakthrough")
    SubscribeToEvent(Settings.EVENTS.REQ_REALM_PILL_SHOP,   "Server_OnReqRealmPillShop")
    SubscribeToEvent(Settings.EVENTS.REQ_BUY_REALM_PILL,    "Server_OnReqBuyRealmPill")
    SubscribeToEvent(Settings.EVENTS.REQ_USE_REALM_PILL,    "Server_OnReqUseRealmPill")
    SubscribeToEvent(Settings.EVENTS.REQ_ALCHEMY_CRAFT,      "Server_OnReqAlchemyCraft")
    SubscribeToEvent(Settings.EVENTS.REQ_BUY_MATERIAL,       "Server_OnReqBuyMaterial")
    SubscribeToEvent(Settings.EVENTS.REQ_ENTER_LAYER,        "Server_OnReqEnterLayer")
    SubscribeToEvent(Settings.EVENTS.REQ_MAP_MOVE,           "Server_OnReqMapMove")
    SubscribeToEvent(Settings.EVENTS.REQ_FORGE_CRAFT,        "Server_OnReqForgeCraft")
    -- 新炼器系统
    SubscribeToEvent(Settings.EVENTS.REQ_BUY_BLUEPRINT,     "Server_OnReqBuyBlueprint")
    SubscribeToEvent(Settings.EVENTS.REQ_FORGE_NEW,         "Server_OnReqForgeNew")
    SubscribeToEvent(Settings.EVENTS.REQ_BLUEPRINT_LIST,    "Server_OnReqBlueprintList")
    SubscribeToEvent(Settings.EVENTS.REQ_CREATE_GUILD,       "Server_OnReqCreateGuild")
    SubscribeToEvent(Settings.EVENTS.REQ_GUILD_INFO,         "Server_OnReqGuildInfo")
    SubscribeToEvent(Settings.EVENTS.REQ_JOIN_GUILD,         "Server_OnReqJoinGuild")
    SubscribeToEvent(Settings.EVENTS.REQ_LEAVE_GUILD,        "Server_OnReqLeaveGuild")
    SubscribeToEvent(Settings.EVENTS.REQ_SET_GUILD_NOTICE,  "Server_OnReqSetGuildNotice")
    SubscribeToEvent(Settings.EVENTS.REQ_GUILD_LIST,          "Server_OnReqGuildList")
    SubscribeToEvent(Settings.EVENTS.REQ_KICK_MEMBER,        "Server_OnReqKickMember")
    SubscribeToEvent(Settings.EVENTS.REQ_TRANSFER_LEADER,   "Server_OnReqTransferLeader")
    SubscribeToEvent(Settings.EVENTS.REQ_GUILD_DONATE,      "Server_OnReqGuildDonate")
    SubscribeToEvent(Settings.EVENTS.REQ_GUILD_UPGRADE,     "Server_OnReqGuildUpgrade")
    SubscribeToEvent(Settings.EVENTS.REQ_SET_GUILD_ROLE,    "Server_OnReqSetGuildRole")
    SubscribeToEvent(Settings.EVENTS.REQ_GUILD_DAILY,       "Server_OnReqGuildDaily")
    SubscribeToEvent(Settings.EVENTS.REQ_CLAIM_GUILD_TASK,  "Server_OnReqClaimGuildTask")
    -- 领地战事件
    SubscribeToEvent(Settings.EVENTS.REQ_STRONGPOINT_LIST,   "Server_OnReqStrongpointList")
    SubscribeToEvent(Settings.EVENTS.REQ_ATTACK_STRONGPOINT, "Server_OnReqAttackStrongpoint")
    SubscribeToEvent(Settings.EVENTS.REQ_SWITCH_STRONGPOINT, "Server_OnReqSwitchStrongpoint")
    SubscribeToEvent(Settings.EVENTS.REQ_DEFEND_STRONGPOINT, "Server_OnReqDefendStrongpoint")
    SubscribeToEvent(Settings.EVENTS.REQ_PVP_CHALLENGE,      "Server_OnReqPvpChallenge")
    SubscribeToEvent(Settings.EVENTS.REQ_QUEST_INFO,         "Server_OnReqQuestInfo")
    SubscribeToEvent(Settings.EVENTS.REQ_CHALLENGE_BOSS,     "Server_OnReqChallengeBoss")
    SubscribeToEvent(Settings.EVENTS.REQ_CLAIM_DAILY,        "Server_OnReqClaimDaily")
    SubscribeToEvent(Settings.EVENTS.REQ_QUEST_INFO_REQ,     "Server_OnReqQuestInfoReq")
    -- 好友系统
    SubscribeToEvent(Settings.EVENTS.REQ_FRIEND_LIST,        "Server_OnReqFriendList")
    SubscribeToEvent(Settings.EVENTS.REQ_ADD_FRIEND,         "Server_OnReqAddFriend")
    SubscribeToEvent(Settings.EVENTS.REQ_REMOVE_FRIEND,      "Server_OnReqRemoveFriend")
    -- 活动系统
    SubscribeToEvent(Settings.EVENTS.REQ_DAILY_SIGN,         "Server_OnReqDailySign")
    SubscribeToEvent(Settings.EVENTS.REQ_CLAIM_ACHIEVEMENT,  "Server_OnReqClaimAchievement")
    SubscribeToEvent(Settings.EVENTS.REQ_WEEKLY_INFO,        "Server_OnReqWeeklyInfo")
    SubscribeToEvent(Settings.EVENTS.REQ_CLAIM_WEEKLY,       "Server_OnReqClaimWeekly")
    SubscribeToEvent(Settings.EVENTS.REQ_PVP_LADDER_INFO,    "Server_OnReqPvpLadderInfo")
    SubscribeToEvent(Settings.EVENTS.REQ_PVP_LADDER_MATCH,   "Server_OnReqPvpLadderMatch")
    -- 背包增强
    SubscribeToEvent(Settings.EVENTS.REQ_AUTO_EQUIP_BEST,   "Server_OnReqAutoEquipBest")
    SubscribeToEvent(Settings.EVENTS.REQ_SELL_ITEM,         "Server_OnReqSellItem")
    SubscribeToEvent(Settings.EVENTS.REQ_BATCH_SELL,        "Server_OnReqBatchSell")
    -- 恢复（非战斗时回满气血内力）
    SubscribeToEvent(Settings.EVENTS.REQ_RESTORE,           "Server_OnReqRestore")

    -- 订阅Update
    SubscribeToEvent("Update", "Server_OnUpdate")

    -- 从云端加载持久化传闻
    serverCloud.list:Get(0, "system_news", {
        ok = function(list)
            if list and #list > 0 then
                local last = list[#list].value
                if last and last.text and last.text ~= "" then
                    systemNews_ = last.text
                end
            end
            print("[Server] 传闻加载完成：" .. systemNews_)
        end,
        error = function() print("[Server] 传闻加载失败，使用默认传闻") end
    })

    -- 从云端加载全量玩家注册表（启动时预热，使离线查询立即可用）
    serverCloud.list:Get(0, "player_registry", {
        ok = function(list)
            if list then
                for _, entry in ipairs(list) do
                    local v = entry.value
                    if v and v.name and v.uid then
                        playerRegistry_[v.name] = v.uid
                        registryUidSet_[v.uid] = true
                    end
                end
            end
            print("[Server] 玩家注册表加载完成，共" .. (function()
                local n = 0
                for _ in pairs(playerRegistry_) do n = n + 1 end
                return n
            end)() .. "位")
            -- 补录离线玩家排行榜分数（确保所有注册玩家都出现在排行榜中）
            Server.BackfillOfflineRankScores()
        end,
        error = function() print("[Server] 玩家注册表加载失败，仅本次在线玩家可查") end
    })

    -- 加载帮会/据点持久化数据
    LoadGuildData()

    -- 加载管理员修改的活动配置（领地战时间、刷怪间隔等）
    LoadActivityConfigOnStart()

    -- NPC商人波动定价初始化
    Server.InitPriceFluctuation()

    -- 一次性迁移：清空旧银两标价商品
    Market.MigrateClearSilverListings()

    -- NPC自动补货：启动时立即执行一次
    if Settings.ECONOMY.NPC_AUTO_LISTINGS and Settings.ECONOMY.NPC_AUTO_LISTINGS.ENABLED then
        Server.NpcRestockMarket()
    end

    print("[Server] 启动完成，等待玩家连入")
end

-- ============================================================================
-- NPC商人波动定价系统
-- ============================================================================
local npcPriceMultipliers_ = {}  -- { itemId = multiplier }
local priceFluctuationSeed_ = 0

function Server.InitPriceFluctuation()
    -- 根据当天日期生成价格种子（每24小时刷新一次）
    local cycleHours = Settings.ECONOMY.NPC_PRICE_CYCLE_HOURS or 24
    local now = os.time()
    priceFluctuationSeed_ = math.floor(now / (cycleHours * 3600))
    npcPriceMultipliers_ = {}
    
    -- 为每个商品生成波动系数
    local fluctuation = Settings.ECONOMY.NPC_PRICE_FLUCTUATION or 0.30
    local allShops = {}
    for _, item in ipairs(Settings.EQUIPMENT_SHOP or {}) do table.insert(allShops, item) end
    for _, item in ipairs(Settings.MEDICINE_SHOP or {}) do table.insert(allShops, item) end
    
    for i, item in ipairs(allShops) do
        -- 使用确定性伪随机（同一天所有玩家看到相同价格）
        local hash = (priceFluctuationSeed_ * 31 + i * 7) % 1000
        local ratio = (hash / 1000) * 2 - 1  -- [-1, 1)
        npcPriceMultipliers_[item.id] = 1.0 + ratio * fluctuation
    end
    
    print(string.format("[Server] NPC波动定价已刷新，种子=%d，波动±%d%%", priceFluctuationSeed_, math.floor(fluctuation * 100)))
end

function Server.GetFluctuatedPrice(itemId, basePrice)
    local mult = npcPriceMultipliers_[itemId] or 1.0
    return math.max(1, math.floor(basePrice * mult))
end


-- ============================================================================
-- 倒爷等级系统
-- ============================================================================
function Server.CalcTraderLevel(totalProfit)
    local level = 0
    for i = #Settings.TRADER_LEVELS, 1, -1 do
        if totalProfit >= Settings.TRADER_LEVELS[i].profit then
            level = i
            break
        end
    end
    return level
end

function Server.GetTraderTaxDiscount(traderLevel)
    if traderLevel <= 0 then return 0 end
    local cfg = Settings.TRADER_LEVELS[traderLevel]
    return cfg and cfg.tax_discount or 0
end

--- 交易成交后累加卖家利润，检查升级
--- @param sellerUid number
--- @param sellPrice number 成交价（买家支付）
--- @param boughtPrice number 卖家当初的购入成本
--- @param sellerTraderLevel number 卖家上架时的倒爷等级（用于算税）
function Server.AddTradeProfit(sellerUid, sellPrice, boughtPrice, sellerTraderLevel, currency)
    -- 计算实收（扣税后）
    local taxDiscount = Server.GetTraderTaxDiscount(sellerTraderLevel)
    local baseTax = (currency == "spirit_stone")
        and Settings.ECONOMY.MARKET_TAX_STONE
        or  Settings.ECONOMY.MARKET_TAX
    local effectiveTax = math.max(0, baseTax - taxDiscount)
    local received = math.floor(sellPrice * (1 - effectiveTax))
    local profit = received - boughtPrice
    if profit <= 0 then return end  -- 亏本交易不计入

    local pd = players_[sellerUid]
    if not pd then return end  -- 卖家不在线则跳过（下次登录补算可扩展）

    pd.trade_profit = (pd.trade_profit or 0) + profit
    local oldLevel = pd.trader_level or 0
    local newLevel = Server.CalcTraderLevel(pd.trade_profit)

    if newLevel > oldLevel then
        pd.trader_level = newLevel
        local title = Settings.TRADER_LEVELS[newLevel].title
        local sellerConn = Server.GetConnByUid(sellerUid)
        if sellerConn then
            Server.PushLog(sellerConn, string.format(
                "<金>【倒爷晋升】恭喜！你的商道等级提升为【%s】！手续费减免%.1f%%</金>",
                title, Settings.TRADER_LEVELS[newLevel].tax_discount * 100))
            Server.PushPlayerData(sellerUid, sellerConn)
        end
        Server.SavePlayerData(sellerUid, pd)
    end
end

function Server.Stop()
    -- 全员下线前存档
    for uid, pd in pairs(players_) do
        Server.SavePlayerData(uid, pd)
    end
    -- 保存帮会/据点数据
    SaveGuildData()
    print("[Server] 服务端关闭，数据已保存")
end

-- ============================================================================
-- 连接管理
-- ============================================================================

function Server_OnClientConnected(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    print("[Server] 客户端连入:", conn:GetAddress())
    -- 设置场景（必须在ClientIdentity之后）
end

function Server_OnClientIdentity(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    -- 不赋 conn.scene，避免引擎发送 LoadScene 消息（纯文字游戏不需要场景同步）
    local uid = conn.identity["user_id"]:GetInt64()
    print("[Server] ClientIdentity uid:", tostring(uid))
    connections_[uid] = conn
    -- 开始异步加载玩家数据，但不立即推送。
    -- 推送时机由 CLIENT_READY 决定（客户端就绪后才发），
    -- LoadOrCreatePlayer 内部会检查 clientReady_ 标志。
    Server.LoadOrCreatePlayer(uid, conn)
end

function Server_OnClientDisconnected(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    if uid then
        print("[Server] 玩家下线，uid:", tostring(uid))
        -- 清理大地图状态
        Server.MapPlayerDisconnect(uid)
        local pd = players_[uid]
        local leaveScene = pd and pd.scene
        if pd then
            pd.logout_time = os.time()
            Server.SavePlayerData(uid, pd)
        end
        -- 帮会下线通知
        Server.NotifyGuildOnline(uid, false)
        players_[uid] = nil
        connections_[uid] = nil
        clientReady_[uid] = nil
        -- 通知同场景玩家刷新（该玩家已离线）
        if leaveScene then
            Server.BroadcastSpotPlayers(leaveScene)
        end
    end
end

-- ============================================================================
-- 玩家初始化
-- ============================================================================

function Server_OnClientReady(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = conn.identity["user_id"]:GetInt64()
    print("[Server] ClientReady uid:", tostring(uid))
    clientReady_[uid] = true
    -- 如果云端数据已经加载完毕，立即推送；否则 LoadOrCreatePlayer 回调会检查标志再推送
    if players_[uid] then
        print("[Server] 数据已就绪，直接推送 uid:", tostring(uid))
        Server.SendInitPlayer(uid, conn, players_[uid])
    else
        print("[Server] 数据加载中，等待云端回调后推送 uid:", tostring(uid))
    end
end

function Server.LoadOrCreatePlayer(uid, conn)
    serverCloud:BatchGet(uid)
        :Key("player_data")
        :Fetch({
            ok = function(scores, iscores)
                local pd = nil
                if scores.player_data then
                    pd = scores.player_data
                    pd.uid = uid
                    print("[Server] 玩家数据已加载 uid:", tostring(uid), "等级:", pd.level)
                    -- 兜底补全：老玩家存档缺失新字段时填充默认值
                    for k, v in pairs(Settings.INITIAL_PLAYER) do
                        if pd[k] == nil then
                            -- tutorial_step 缺失 → 老玩家，直接标记为已完成（=3），不强迫走引导
                            -- scene 缺失 → 用默认值（古村）
                            if k == "tutorial_step" then
                                pd[k] = 3
                            else
                                pd[k] = v
                            end
                            print("[Server] 补全缺失字段 " .. k .. " = " .. tostring(pd[k]))
                        end
                    end
                    -- hp 不在 INITIAL_PLAYER 中，单独补全：nil 表示从未存储过，初始化为满血
                    if pd.hp == nil then
                        pd.hp = Shared.CalcStats(pd).hp
                        print("[Server] 补全 hp = " .. tostring(pd.hp))
                    end
                else
                    -- 新玩家
                    pd = {}
                    for k, v in pairs(Settings.INITIAL_PLAYER) do
                        pd[k] = v
                    end
                    pd.uid = uid
                    pd.hp = Shared.CalcStats(pd).hp  -- 新玩家满血
                    pd.name = "无名修士"  -- 占位名（角色创建后替换）
                    pd._isNewPlayer = true
                    pd._needCreate = true  -- 标记需要走角色创建流程
                    -- 生成邀请码
                    pd.invite_code = Server.GenerateInviteCode()
                    print("[Server] 新玩家创建 uid:", tostring(uid), "invite_code:", pd.invite_code)
                end

                -- 离线收益结算
                Server.CalcOfflineRewards(pd)

                -- 缓存到内存
                players_[uid] = pd

                -- 注册到玩家名册（用于管理员离线查询）
                if pd.name and pd.name ~= "无名修士" then
                    playerRegistry_[pd.name] = uid
                    -- 首次登录写入云端注册表（去重：同一 uid 只写一次）
                    if not registryUidSet_[uid] then
                        registryUidSet_[uid] = true
                        serverCloud.list:Add(0, "player_registry", { uid = uid, name = pd.name })
                        print("[Server] 新玩家写入云端注册表 name=" .. pd.name .. " uid=" .. tostring(uid))
                    end
                end

                -- 注册邀请码到查找表
                if pd.invite_code and pd.invite_code ~= "" then
                    inviteCodes_[pd.invite_code] = uid
                end

                -- 第一步：读取/重置货币
                if pd._isNewPlayer then
                    -- 新玩家：先读取云端残留数据，再扣除多余部分重置为初始值
                    pd._isNewPlayer = nil
                    serverCloud.money:Get(uid, {
                        ok = function(moneys)
                            local curSilver = moneys.silver or 0
                            local curStone = moneys.spirit_stone or 0
                            local initSilver = Settings.INITIAL_PLAYER.silver
                            local initStone = Settings.INITIAL_PLAYER.spirit_stone
                            -- 扣除多余银两
                            if curSilver > initSilver then
                                serverCloud.money:Cost(uid, "silver", curSilver - initSilver)
                            elseif curSilver < initSilver then
                                serverCloud.money:Add(uid, "silver", initSilver - curSilver)
                            end
                            -- 扣除多余灵石
                            if curStone > initStone then
                                serverCloud.money:Cost(uid, "spirit_stone", curStone - initStone)
                            elseif curStone < initStone then
                                serverCloud.money:Add(uid, "spirit_stone", initStone - curStone)
                            end
                            pd.silver = initSilver
                            pd.spirit_stone = initStone
                            pd._moneySyncSilver = math.floor(initSilver)
                            pd._moneySyncStone = math.floor(initStone)
                            print("[Server] 新玩家货币重置 silver=" .. initSilver .. " spirit_stone=" .. initStone)
                            Server.LoadInventoryFromList(uid, pd, function()
                                if clientReady_[uid] then
                                    Server.SendInitPlayer(uid, conn, pd)
                                else
                                    print("[Server] 数据加载完成但客户端尚未就绪，等待 CLIENT_READY uid:", tostring(uid))
                                end
                            end)
                        end,
                        error = function()
                            pd.silver = Settings.INITIAL_PLAYER.silver
                            pd.spirit_stone = Settings.INITIAL_PLAYER.spirit_stone
                            pd._moneySyncSilver = math.floor(pd.silver)
                            pd._moneySyncStone = math.floor(pd.spirit_stone)
                            serverCloud.money:Add(uid, "silver", pd.silver)
                            serverCloud.money:Add(uid, "spirit_stone", pd.spirit_stone)
                            Server.LoadInventoryFromList(uid, pd, function()
                                if clientReady_[uid] then
                                    Server.SendInitPlayer(uid, conn, pd)
                                else
                                    print("[Server] 数据加载完成但客户端尚未就绪，等待 CLIENT_READY uid:", tostring(uid))
                                end
                            end)
                        end
                    })
                else
                    serverCloud.money:Get(uid, {
                        ok = function(moneys)
                            pd.silver = moneys.silver or Settings.INITIAL_PLAYER.silver
                            pd.spirit_stone = moneys.spirit_stone or Settings.INITIAL_PLAYER.spirit_stone
                            -- 初始化货币同步基准值（用于 SavePlayerData 差值同步）
                            pd._moneySyncSilver = math.floor(pd.silver)
                            pd._moneySyncStone = math.floor(pd.spirit_stone)
                            -- 防作弊/数据残留：新手引导未完成时银两不应超过合理范围
                            local maxNewbieSilver = 500
                            if (pd.tutorial_step or 0) < 3 and pd.silver > maxNewbieSilver then
                                local excess = pd.silver - Settings.INITIAL_PLAYER.silver
                                if excess > 0 then
                                    serverCloud.money:Cost(uid, "silver", excess)
                                end
                                pd.silver = Settings.INITIAL_PLAYER.silver
                                pd._moneySyncSilver = math.floor(pd.silver)
                                print("[Server] 新手银两异常重置 uid=" .. tostring(uid) .. " 原值=" .. (moneys.silver or 0))
                            end
                            Server.LoadInventoryFromList(uid, pd, function()
                                if clientReady_[uid] then
                                    Server.SendInitPlayer(uid, conn, pd)
                                else
                                    print("[Server] 数据加载完成但客户端尚未就绪，等待 CLIENT_READY uid:", tostring(uid))
                                end
                            end)
                        end,
                        error = function()
                            pd.silver = pd.silver or Settings.INITIAL_PLAYER.silver
                            pd.spirit_stone = pd.spirit_stone or Settings.INITIAL_PLAYER.spirit_stone
                            pd._moneySyncSilver = math.floor(pd.silver)
                            pd._moneySyncStone = math.floor(pd.spirit_stone)
                            Server.LoadInventoryFromList(uid, pd, function()
                                if clientReady_[uid] then
                                    Server.SendInitPlayer(uid, conn, pd)
                                else
                                    print("[Server] 数据加载完成但客户端尚未就绪，等待 CLIENT_READY uid:", tostring(uid))
                                end
                            end)
                        end
                    })
                end
            end,
            error = function(code, reason)
                print("[Server] 读取玩家数据失败:", code, reason)
                -- 降级处理：使用初始数据
                local pd = {}
                for k, v in pairs(Settings.INITIAL_PLAYER) do pd[k] = v end
                pd.uid = uid
                pd.hp = Shared.CalcStats(pd).hp  -- 降级满血
                pd.name = "无名侠客"
                players_[uid] = pd
                if clientReady_[uid] then
                    Server.SendInitPlayer(uid, conn, pd)
                end
            end
        })
end

-- 离线收益结算
function Server.CalcOfflineRewards(pd)
    if not pd.logout_time or pd.logout_time <= 0 then return end
    local now = os.time()
    local offline = math.min(now - pd.logout_time, Settings.OFFLINE.MAX_SECONDS)
    if offline <= 0 then return end

    local expMult = Activity.GetEventMultiplier("double_exp")
    -- 动态经验：根据当前境界层所需经验 / 该境界每层所需小时数
    local expNeeded = Settings.REALM.GetExpNeeded(pd.realm, pd.realm_layer)
    local hoursPerLayer = Settings.OFFLINE.GetHoursPerLayer(pd.realm or 1)
    local expPerSec = expNeeded / (hoursPerLayer * 3600)
    local expGain = math.floor(expPerSec * offline * expMult)
    local silverGain = math.floor(Settings.OFFLINE.SILVER_PER_SECOND * offline)

    -- 据点加成（拥有据点的帮会成员获得额外收益）
    local spBonus = Server.GetStrongholdBonus(pd)
    if spBonus then
        local bType = spBonus.type
        local bVal  = spBonus.value or 0
        if bType == "silver_income" then
            silverGain = math.floor(silverGain * (1 + bVal))
        elseif bType == "cultivate_exp" then
            expGain = math.floor(expGain * (1 + bVal))
        end
    end

    pd.realm_exp = (pd.realm_exp or 0) + expGain
    pd.offline_silver_pending = (pd.offline_silver_pending or 0) + silverGain
    pd.logout_time = 0

    -- 离线潜能获取（境界等效等级×系数×秒数）
    local potentialGain = math.floor((pd.level or 1) * Settings.POTENTIAL.OFFLINE_PER_LEVEL * offline)
    -- 据点加成：离线潜能
    if spBonus and spBonus.type == "offline_potential" then
        potentialGain = math.floor(potentialGain * (1 + (spBonus.value or 0)))
    end
    pd.potential = (pd.potential or 0) + potentialGain

    -- 离线修炼（消耗潜能提升熟练度）
    local profGain = 0
    if pd.cultivating and pd.cultivating ~= "" then
        profGain, _ = Cultivation.CalcOffline(pd, offline)
    end

    pd.offline_rewards = {
        exp = expGain,
        silver = silverGain,
        potential = potentialGain,
        proficiency = math.floor(profGain * 100) / 100,
        seconds = offline,
    }

    -- 升级检查
    Server.CheckLevelUp(pd)
    print(string.format("[Server] 离线结算 uid=%s 时长=%ds 经验+%d 银两+%d",
        tostring(pd.uid), offline, expGain, silverGain))
end

-- 发送初始化数据
function Server.SendInitPlayer(uid, conn, pd)
    -- 古村场景默认进入村中心，无需手动选地点
    if pd.scene == Settings.SCENES.ANCIENT_VILLAGE then
        pd.spot = "village_center"
    else
        pd.spot = ""
    end
    local data = VariantMap()
    local serialized = Server.SerializePlayerData(pd)
    -- 新玩家标记：告知客户端需要走角色创建流程
    if pd._needCreate then
        serialized._needCreate = true
    end
    data["data_json"] = Variant(cjson.encode(serialized))
    if pd.offline_rewards then
        data["offline_rewards_json"] = Variant(cjson.encode(pd.offline_rewards))
        pd.offline_rewards = nil
    end
    conn:SendRemoteEvent(Settings.EVENTS.INIT_PLAYER, true, data)
    -- 推送当前传闻
    local newsData = VariantMap()
    newsData["Text"] = Variant(systemNews_)
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_NEWS_UPDATE, true, newsData)
    -- 广播同场景玩家列表，让其他人看到新上线的玩家
    Server.BroadcastSpotPlayers(pd.scene)
    -- 推送聊天历史
    Server.PushChatHistoryTo(uid, conn)
    -- 推送背包数据（inventory 不在 SerializePlayerData 中，需单独推送）
    Server.PushInventory(uid, conn)
    -- 初始化并推送任务状态
    Quest.InitPlayer(pd)
    Quest._syncMainQuestProgress(pd)
    Quest.PushActiveQuest(pd, conn)
    print("[Server] 初始化数据已发送 uid:", tostring(uid))
    -- 帮会上线通知
    Server.NotifyGuildOnline(uid, true)
    -- 上线同步排行榜分数（确保离线期间的数据也写入云端排行）
    Server.SyncRankScores(uid, pd)
end

-- ============================================================================
-- 背包持久化（serverCloud List）
-- ============================================================================

-- 从 List 加载背包，填入 pd.inventory
function Server.LoadInventoryFromList(uid, pd, onDone)
    serverCloud.list:Get(uid, "inventory", {
        ok = function(entries)
            pd.inventory = {}
            -- entries 是 {list_id, value} 数组
            for _, entry in ipairs(entries) do
                local item = entry.value
                -- 清理历史脏数据：银两虚拟商品不应出现在背包中
                if item.type == "currency" and item.silver_amount then
                    -- 将银两退回余额，并从云端删除此条目
                    pd.silver = (pd.silver or 0) + item.silver_amount
                    serverCloud.list:Delete(entry.list_id)
                    print(string.format("[Server] 清理背包脏数据: 银两×%d 已退回余额 uid=%s", item.silver_amount, tostring(uid)))
                else
                    -- 保存 list_id 以便后续删除
                    item._list_id = entry.list_id
                    table.insert(pd.inventory, item)
                end
            end
            print(string.format("[Server] 背包加载完成 uid=%s 共%d件", tostring(uid), #pd.inventory))
            if onDone then onDone() end
        end,
        error = function(code, reason)
            print(string.format("[Server] 背包加载失败 uid=%s code=%s", tostring(uid), tostring(code)))
            pd.inventory = pd.inventory or {}
            if onDone then onDone() end
        end
    })
end

-- 添加物品到背包（内存 + List 持久化）
function Server.AddItemToInventory(uid, item, onDone)
    local pd = players_[uid]
    if not pd then
        if onDone then onDone(false) end
        return
    end
    -- 背包容量检查
    local invCount = pd.inventory and #pd.inventory or 0
    if invCount >= Settings.INVENTORY_MAX then
        local conn = connections_[uid]
        if conn then
            Server.PushLog(conn, "<红>背包已满（" .. invCount .. "/" .. Settings.INVENTORY_MAX .. "），请先清理空间</红>")
        end
        if onDone then onDone(false) end
        return
    end
    serverCloud.list:Add(uid, "inventory", item, {
        ok = function(listId)
            item._list_id = listId
            pd.inventory = pd.inventory or {}
            table.insert(pd.inventory, item)
            if onDone then onDone(true) end
        end,
        error = function(code, reason)
            print(string.format("[Server] 背包写入失败 uid=%s item=%s: %s", tostring(uid), item.id, tostring(reason)))
            -- 降级：至少保存在内存里
            pd.inventory = pd.inventory or {}
            table.insert(pd.inventory, item)
            if onDone then onDone(false) end
        end
    })
end

-- 异步删除背包物品（内存同步移除 + List 删除）
function Server.RemoveInventoryItemAsync(uid, itemId, onDone)
    local pd = players_[uid]
    if not pd or not pd.inventory then
        if onDone then onDone(false, nil) end
        return
    end
    local found = nil
    local foundIdx = nil
    for i, item in ipairs(pd.inventory) do
        if item.id == itemId then
            found = item
            foundIdx = i
            break
        end
    end
    if not found then
        if onDone then onDone(false, nil) end
        return
    end
    -- 先从内存移除
    table.remove(pd.inventory, foundIdx)

    -- 再从 List 删除（有 _list_id 时）
    if found._list_id then
        serverCloud.list:Delete(found._list_id, {
            ok = function()
                if onDone then onDone(true, found) end
            end,
            error = function(code, reason)
                print(string.format("[Server] 背包删除失败 listId=%s: %s", tostring(found._list_id), tostring(reason)))
                if onDone then onDone(true, found) end  -- 内存已移除，视为成功
            end
        })
    else
        -- 没有 list_id（旧数据/内存物品），直接视为成功
        if onDone then onDone(true, found) end
    end
end

-- ============================================================================
-- 存档
-- ============================================================================

function Server.SavePlayerData(uid, pd)
    if not pd then return end
    pd.logout_time = os.time()
    local saveData = Server.SerializePlayerData(pd)

    serverCloud:BatchSet(uid)
        :Set("player_data", saveData)
        :Save("自动存档", {
            ok = function()
                print("[Server] 存档完成 uid:", tostring(uid))
            end,
            error = function(code, reason)
                print("[Server] 存档失败:", code, reason)
            end
        })

    -- 同步货币（offline pending）
    if pd.offline_silver_pending and pd.offline_silver_pending > 0 then
        serverCloud.money:Add(uid, "silver", pd.offline_silver_pending)
        pd.offline_silver_pending = 0
    end

    -- ★ 同步灵石/银两到 serverCloud.money（确保重启后读取一致）
    -- 很多游戏逻辑只修改了 pd.spirit_stone/pd.silver 内存值，没有调用 money:Add/Cost
    -- 这里通过差值同步：与上次同步值比较，只 Add/Cost 差额
    do
        local curSilver = math.floor(pd.silver or 0)
        local lastSilver = pd._moneySyncSilver or curSilver
        local diffSilver = curSilver - lastSilver
        if diffSilver > 0 then
            serverCloud.money:Add(uid, "silver", diffSilver)
        elseif diffSilver < 0 then
            serverCloud.money:Cost(uid, "silver", -diffSilver)
        end
        pd._moneySyncSilver = curSilver

        local curStone = math.floor(pd.spirit_stone or 0)
        local lastStone = pd._moneySyncStone or curStone
        local diffStone = curStone - lastStone
        if diffStone > 0 then
            serverCloud.money:Add(uid, "spirit_stone", diffStone)
        elseif diffStone < 0 then
            serverCloud.money:Cost(uid, "spirit_stone", -diffStone)
        end
        pd._moneySyncStone = curStone
    end

    -- 同步排行榜分数（全服排行，含离线玩家）
    Server.SyncRankScores(uid, pd)
end

--- 将玩家关键指标写入 serverCloud iscores，供全服排行榜使用
function Server.SyncRankScores(uid, pd)
    if not pd or not uid then return end
    local stats = Shared.CalcStats(pd)
    local power = Settings.CalcPower(stats)
    -- 境界排序值：realm*100 + realm_layer，保证高境界排前面
    local realmScore = (pd.realm or 1) * 100 + (pd.realm_layer or 1)
    -- 装备战力（内联计算，避免依赖后面的 local 函数）
    local eqAtk, eqDef, eqAgi, eqHp = 0, 0, 0, 0
    if pd.equipment then
        for _, item in pairs(pd.equipment) do
            if item and item.stats then
                eqAtk = eqAtk + (item.stats.atk or 0)
                eqDef = eqDef + (item.stats.def or 0)
                eqAgi = eqAgi + (item.stats.agi or 0)
                eqHp  = eqHp  + (item.stats.hp  or 0)
            end
        end
    end
    local equipPower = Settings.CalcPower({ atk = eqAtk, def = eqDef, agi = eqAgi, hp = eqHp })
    -- 天梯积分
    local ladderRating = pd.pvp_ladder and pd.pvp_ladder.rating or 0

    serverCloud:SetInt(uid, "rank_power", power)
    serverCloud:SetInt(uid, "rank_realm", realmScore)
    serverCloud:SetInt(uid, "rank_equip", equipPower)
    if ladderRating > 0 then
        serverCloud:SetInt(uid, "rank_ladder", ladderRating)
    end
end

--- 服务器启动时补录离线玩家排行榜分数
-- 遍历 player_registry 中所有 uid，逐个加载 player_data 并写入 iscores
-- 使用队列式串行处理，避免瞬间大量请求
function Server.BackfillOfflineRankScores()
    -- 收集所有注册 uid
    local queue = {}
    for _, uid in pairs(playerRegistry_) do
        -- 跳过当前在线玩家（他们登录时已自动同步）
        if not players_[uid] then
            queue[#queue + 1] = uid
        end
    end

    if #queue == 0 then
        print("[Server] 排行榜补录：无离线玩家需要补录")
        return
    end

    print(string.format("[Server] 排行榜补录：开始处理 %d 位离线玩家", #queue))

    local idx = 0
    local successCount = 0

    local function processNext()
        idx = idx + 1
        if idx > #queue then
            print(string.format("[Server] 排行榜补录完成：成功 %d/%d", successCount, #queue))
            return
        end

        local uid = queue[idx]
        serverCloud:BatchGet(uid)
            :Key("player_data")
            :Fetch({
                ok = function(scores, iscores)
                    local pd = scores.player_data
                    if pd then
                        pd.uid = uid
                        -- 补全缺失字段以确保 CalcStats 不报错
                        for k, v in pairs(Settings.INITIAL_PLAYER) do
                            if pd[k] == nil then pd[k] = v end
                        end
                        -- 计算并写入排行榜分数
                        local stats = Shared.CalcStats(pd)
                        local power = Settings.CalcPower(stats)
                        local realmScore = (pd.realm or 1) * 100 + (pd.realm_layer or 1)
                        local eqAtk, eqDef, eqAgi, eqHp = 0, 0, 0, 0
                        if pd.equipment then
                            for _, item in pairs(pd.equipment) do
                                if item and item.stats then
                                    eqAtk = eqAtk + (item.stats.atk or 0)
                                    eqDef = eqDef + (item.stats.def or 0)
                                    eqAgi = eqAgi + (item.stats.agi or 0)
                                    eqHp  = eqHp  + (item.stats.hp  or 0)
                                end
                            end
                        end
                        local equipPower = Settings.CalcPower({ atk = eqAtk, def = eqDef, agi = eqAgi, hp = eqHp })
                        local ladderRating = pd.pvp_ladder and pd.pvp_ladder.rating or 0

                        serverCloud:SetInt(uid, "rank_power", power)
                        serverCloud:SetInt(uid, "rank_realm", realmScore)
                        serverCloud:SetInt(uid, "rank_equip", equipPower)
                        if ladderRating > 0 then
                            serverCloud:SetInt(uid, "rank_ladder", ladderRating)
                        end
                        successCount = successCount + 1
                    end
                    processNext()
                end,
                error = function(code, reason)
                    print(string.format("[Server] 排行榜补录失败 uid=%s: %s", tostring(uid), tostring(reason)))
                    processNext()
                end
            })
    end

    processNext()
end

-- 序列化玩家数据为可存储格式
function Server.SerializePlayerData(pd)
    local save = {}
    -- 注意：inventory 已改为 serverCloud List 存储，不在此序列化
    local fields = {
        "uid","level","exp","potential","hp","hp_base","mp_base","atk_base","def_base",
        "agi_base","wis_base","scene","sect","skills","equipment",
        "cultivating","logout_time","name","is_admin",
        "tutorial_step","spot","quests",
        "boss_defeated","max_battlefield_layer",
        "main_quest_index","main_quest_progress","total_kills","daily",
        -- 境界与经济
        "realm","realm_layer","realm_exp","silver","spirit_stone",
        -- 帮会与社交
        "guild_id","guild_name","friends",
        -- 炼丹/锻造
        "alchemy_exp","alchemy_level","forge_exp","forge_level",
        -- 新炼器系统
        "blueprints_learned","forge_pity",
        -- 出战技能槽
        "battle_slots",
        -- 突破与修炼加成
        "breakthrough_fails","cultivate_cost_mult","realm_pill_daily",
        -- 战斗状态
        "in_battle",
        -- 角色创建
        "gender","invite_code","invited_by",
        -- 门派试炼
        "hint_city_shown",
        "alchemy_fails",
        "equip_pity",
        "first_battle_reward",
        "sect_trials",
        -- 管理员测试开关
        "debug_flags",
    }
    for _, f in ipairs(fields) do
        save[f] = pd[f]
    end
    return save
end

-- ============================================================================
-- 游戏循环
-- ============================================================================

function Server_OnUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 战斗更新
    local finishedBattles = Combat.Update(dt)
    for _, item in ipairs(finishedBattles) do
        -- item = { uid, result }，OnBattleFinished 需要 result 字段
        print(string.format("[Server] 战斗结束 item.uid=%s item.result=%s", tostring(item.uid), tostring(item.result)))
        Server.OnBattleFinished(item.result)
    end

    -- 修炼更新（每秒一次）
    gameTimer_ = gameTimer_ + dt
    if gameTimer_ >= GAME_TICK then
        local tick = gameTimer_
        gameTimer_ = 0
        for uid, pd in pairs(players_) do
            -- 帮会BUFF：修炼速度倍率
            local gBuff = Server.GetGuildBuff(pd)
            pd.guild_cult_bonus = gBuff and gBuff.cult_bonus or 1.0
            pd.guild_silver_bonus = gBuff and gBuff.silver_bonus or 0
            if pd.cultivating and pd.cultivating ~= "" then
                local wasCultivating = pd.cultivating
                Cultivation.Update(pd, tick)
                Activity.OnCultivateTime(pd, tick)

                -- 修炼刚结束 → 立刻推送，让客户端及时更新
                if (not pd.cultivating or pd.cultivating == "") and wasCultivating ~= "" then
                    local conn = connections_[uid]
                    if conn then Server.PushPlayerData(uid, conn) end
                end
            end

            -- ★ 在线自动获得境界经验（所有在线玩家，不需要打坐）
            do
                local expNeeded = Settings.REALM.GetExpNeeded(pd.realm, pd.realm_layer)
                local hoursPerLayer = Settings.OFFLINE.GetHoursPerLayer(pd.realm or 1)
                local basePerSec = expNeeded / (hoursPerLayer * 3600)
                local onlineExpPerSec = basePerSec * (Settings.ONLINE_CULTIVATE.EXP_MULT or 2.0)
                local onlineExpGain = onlineExpPerSec * tick
                -- 据点加成
                local spBonus = Server.GetStrongholdBonus(pd)
                if spBonus and spBonus.type == "cultivate_exp" then
                    onlineExpGain = onlineExpGain * (1 + (spBonus.value or 0))
                end
                -- 活动加成
                local expMult = Activity.GetEventMultiplier("double_exp")
                onlineExpGain = onlineExpGain * expMult
                -- 累加经验（使用浮点累加器避免每秒截断损失）
                pd._cultExpAccum = (pd._cultExpAccum or 0) + onlineExpGain
                if pd._cultExpAccum >= 1.0 then
                    local whole = math.floor(pd._cultExpAccum)
                    pd.realm_exp = (pd.realm_exp or 0) + whole
                    pd._cultExpAccum = pd._cultExpAccum - whole
                end
                -- 累计用于日志显示的经验（浮点累加，避免低境界每秒不足1时永远为0）
                pd._cultExpLogGain = (pd._cultExpLogGain or 0) + onlineExpGain

                -- 每20秒推送一次在线修炼经验日志
                pd._cultExpLogTimer = (pd._cultExpLogTimer or 0) + tick
                if pd._cultExpLogTimer >= 20.0 then
                    pd._cultExpLogTimer = 0
                    local logGain = math.floor(pd._cultExpLogGain or 0)
                    if logGain > 0 then
                        local conn = connections_[uid]
                        if conn then
                            Server.PushLog(conn, string.format("<绿>【在线】挂机修炼获得经验 +%d</绿>", logGain))
                        end
                    end
                    pd._cultExpLogGain = 0
                end
            end
            -- 经验升级检查
            Server.CheckLevelUp(pd)
        end
    end

    -- 经验轻量推送（修炼中每5秒推送一次，让客户端进度条实时动）
    expPushTimer_ = expPushTimer_ + dt
    if expPushTimer_ >= EXP_PUSH_INTERVAL then
        expPushTimer_ = 0
        for uid, pd in pairs(players_) do
            if pd.cultivating and pd.cultivating ~= "" then
                local conn = connections_[uid]
                if conn and not Combat.IsInBattle(uid) then
                    local data = VariantMap()
                    data["realm_exp"] = Variant(pd.realm_exp or 0)
                    data["realm"] = Variant(pd.realm or 1)
                    data["realm_layer"] = Variant(pd.realm_layer or 1)
                    conn:SendRemoteEvent(Settings.EVENTS.PUSH_EXP_UPDATE, true, data)
                end
            end
        end
    end

    -- 在线时长更新（每60秒）
    onlineTimer_ = onlineTimer_ + dt
    if onlineTimer_ >= ONLINE_TICK then
        local elapsed = onlineTimer_
        onlineTimer_ = 0
        for uid, pd in pairs(players_) do
            local conn = connections_[uid]
            Quest.OnOnlineTime(pd, conn, elapsed)
        end
    end

    -- 定期存档
    syncTimer_ = syncTimer_ + dt
    if syncTimer_ >= SYNC_INTERVAL then
        syncTimer_ = 0
        for uid, pd in pairs(players_) do
            Server.SavePlayerData(uid, pd)
            -- 推送最新数据给客户端
            local conn = connections_[uid]
            if conn and not Combat.IsInBattle(uid) then
                Server.PushPlayerData(uid, conn)
            end
        end
    end

    -- 清理过期商品
    marketCleanTimer_ = marketCleanTimer_ + dt
    if marketCleanTimer_ >= MARKET_CLEAN_INTERVAL then
        marketCleanTimer_ = 0
        Market.CleanExpired()
    end

    -- NPC自动补货（器丹宗丹药阁）
    local npcCfg = Settings.ECONOMY.NPC_AUTO_LISTINGS
    if npcCfg and npcCfg.ENABLED then
        npcRestockTimer_ = npcRestockTimer_ + dt
        if npcRestockTimer_ >= npcCfg.RESTOCK_INTERVAL and not npcRestockRunning_ then
            npcRestockTimer_ = 0
            npcRestockRunning_ = true
            Server.NpcRestockMarket()
        end
    end

    -- 大地图位置同步
    Server.MapSyncTick(dt)

    -- 怪物 AI + 位置广播
    Server.MonsterTick(dt)
    Server.MonsterSyncTick(dt)

    -- 领地战更新
    Server.TerritoryWarTick(dt)
end

-- 战斗结束处理
function Server.OnBattleFinished(result)
    local uid = result.uid
    local pd = players_[uid]
    local conn = result.connection
    print(string.format("[Server] OnBattleFinished uid=%s win=%s pd=%s conn=%s",
        tostring(uid), tostring(result.win), tostring(pd ~= nil), tostring(conn ~= nil)))
    if not pd or not conn then
        print("[Server] OnBattleFinished 提前返回：pd或conn为nil")
        return
    end

    -- 同步战后HP回玩家数据
    if result.playerHp ~= nil then
        pd.hp = result.playerHp
        print(string.format("[Server] OnBattleFinished 同步战后HP: pd.hp=%d", pd.hp))
    end

    -- ========== Boss 战特殊处理 ==========
    if pd._battleBossId then
        local bossId = pd._battleBossId
        pd._battleBossId = nil
        local bossDef = Settings.BOSS_MAP[bossId]
        local data = VariantMap()

        if result.win and bossDef then
            -- Boss 击败：记录、解锁层、发放奖励
            if not pd.boss_defeated then pd.boss_defeated = {} end
            table.insert(pd.boss_defeated, bossId)

            -- 解锁新层
            local unlocks = bossDef.unlocks or {}
            local maxUnlock = pd.max_battlefield_layer or Settings.BATTLEFIELD_INITIAL_LAYERS
            for _, layer in ipairs(unlocks) do
                if layer > maxUnlock then maxUnlock = layer end
            end
            pd.max_battlefield_layer = maxUnlock
            -- 门派试炼：战场层数推进
            Server.OnTrialBattlefieldClear(uid, conn, pd)

            -- 奖励
            local rewards = bossDef.rewards or {}
            if rewards.spirit_stone and rewards.spirit_stone > 0 then
                pd.spirit_stone = (pd.spirit_stone or 0) + rewards.spirit_stone
            end
            if rewards.potential and rewards.potential > 0 then
                pd.potential = (pd.potential or 0) + rewards.potential
            end
            if rewards.items then
                if not pd.inventory then pd.inventory = {} end
                for _, item in ipairs(rewards.items) do
                    local found = false
                    for _, inv in ipairs(pd.inventory) do
                        if inv.id == item.id then
                            inv.count = (inv.count or 1) + (item.count or 1)
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(pd.inventory, { id = item.id, count = item.count or 1, type = "material" })
                    end
                end
            end

            -- 恢复满血
            local maxHp = Shared.CalcStats(pd).hp
            pd.hp = maxHp

            local unlockMsg = ""
            if #unlocks > 0 then
                unlockMsg = string.format("，域外第%d-%d层已解锁", unlocks[1], unlocks[#unlocks])
            end
            data["Win"] = Variant(true)
            data["Log"] = Variant(string.format(
                "<金>【首领击败】恭喜击败【%s】！获得灵石+%d，潜能+%d%s</金>",
                bossDef.name, rewards.spirit_stone or 0, rewards.potential or 0, unlockMsg
            ))
            data["ExpGain"]    = Variant(0)
            data["PotentialGain"] = Variant(rewards.potential or 0)
            data["SilverGain"] = Variant(0)
            data["LootToken"]    = Variant("")
            data["LootItemName"] = Variant("")

            -- 通知 Quest 系统
            Quest.OnBossDefeated(pd, conn, bossId)

            Server.PushLog(conn, string.format(
                "<金>【%s】已被击败！%s</金>", bossDef.name, unlockMsg
            ))
        else
            -- Boss 战败：无惩罚，恢复满血
            local maxHp = Shared.CalcStats(pd).hp
            pd.hp = maxHp
            data["Win"]  = Variant(false)
            data["Log"]  = Variant(string.format(
                "<黄>挑战【%s】失败……实力尚有差距，继续修炼再来！</黄>",
                bossDef and bossDef.name or "首领"
            ))
            data["LootToken"]    = Variant("")
            data["LootItemName"] = Variant("")
        end

        -- 同步最新解锁层给客户端
        data["MaxBattlefieldLayer"] = Variant(pd.max_battlefield_layer or Settings.BATTLEFIELD_INITIAL_LAYERS)

        conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_BATTLE_END), true, data)
        Server.PushPlayerData(uid, conn)
        Server.SavePlayerData(uid)
        return
    end
    -- ========== End Boss 战 ==========

    -- ========== PvP 天梯战处理 ==========
    if pd._battlePvpData then
        local pvpInfo = pd._battlePvpData
        pd._battlePvpData = nil

        local opponentRating = pvpInfo.opponentRating
        local opponentUid = pvpInfo.opponentUid
        local opponentName = pvpInfo.opponentName
        local win = result.win

        -- 保存旧积分用于掉段保护判断
        local oldRating = pd.pvp_ladder and pd.pvp_ladder.rating or Settings.PVP_LADDER.INITIAL_RATING

        -- 处理ELO积分变化
        local ladderResult = Activity.ProcessLadderResult(pd, opponentRating, win)

        -- 掉段保护（仅输了才检查）
        local shielded = false
        if not win then
            shielded = Activity.CheckDemotionShield(pd, oldRating)
        end

        -- 更新赛季峰值
        if win then
            Activity.UpdateSeasonPeak(pd)
        end

        -- 如果对手是真实在线玩家，也更新其积分
        if opponentUid and players_[opponentUid] then
            local myRating = oldRating
            Activity.ProcessLadderResult(players_[opponentUid], myRating, not win)
            if win then
                Activity.UpdateSeasonPeak(players_[opponentUid])  -- 对手输了不更新峰值
            else
                Activity.UpdateSeasonPeak(players_[opponentUid])
            end
            Server.SavePlayerData(opponentUid)
            local oppConn = connections_[opponentUid]
            if oppConn then
                if win then
                    Server.PushLog(oppConn, string.format(
                        "<红>【天梯】%s 在天梯中击败了你（积分变化）</红>", pd.name or "?"))
                end
                PushPvpLadderData(opponentUid, oppConn)
            end
        end

        -- 恢复满血
        local maxHp = Shared.CalcStats(pd).hp
        pd.hp = maxHp

        -- 推送结果给客户端
        local data = VariantMap()
        local colorTag = win and "绿" or "红"
        local shieldMsg = shielded and "（掉段保护生效）" or ""
        local logMsg = string.format("<%s>【天梯】vs %s：%s%s（积分%+d → %d %s）</%s>",
            colorTag, opponentName, win and "胜利" or "失败", shieldMsg,
            ladderResult.rating_change, ladderResult.new_rating, ladderResult.new_rank, colorTag)

        data["Win"] = Variant(win)
        data["Log"] = Variant(logMsg)
        data["ExpGain"]    = Variant(0)
        data["SilverGain"] = Variant(0)
        data["LootToken"]    = Variant("")
        data["LootItemName"] = Variant("")
        conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_BATTLE_END), true, data)

        Server.PushLog(conn, logMsg)

        -- 周常
        if win then
            Activity.IncrWeekly(pd, "weekly_win", 1)
        end

        Server.PushPlayerData(uid, conn)
        Server.SavePlayerData(uid)
        PushPvpLadderData(uid, conn)
        return
    end
    -- ========== End PvP 天梯战 ==========

    local data = VariantMap()

    if result.win then
        local monDef = result.monsterDef
        -- 银两奖励（加入待同步队列）
        local silverAmt = monDef.silver
        local gSilverBonus = pd.guild_silver_bonus or 0
        if gSilverBonus > 0 then silverAmt = math.floor(silverAmt * (1 + gSilverBonus)) end
        pd.offline_silver_pending = (pd.offline_silver_pending or 0) + silverAmt
        pd.silver = (pd.silver or 0) + silverAmt
        Activity.OnEarnSilver(pd, silverAmt)

        -- 潜能奖励（打怪获取）
        local potentialGain = Settings.POTENTIAL.MONSTER_BASE + (monDef.level or 1) * Settings.POTENTIAL.MONSTER_PER_LEVEL
        if monDef.is_boss then
            potentialGain = potentialGain * Settings.POTENTIAL.BOSS_MULTIPLIER
        end
        pd.potential = (pd.potential or 0) + potentialGain

        -- 新手引导：击败迷失幼妖 → step 1 → 2，提示回老村长复命
        if monDef.tutorial_beast and (pd.tutorial_step or 0) == 1 then
            pd.tutorial_step = 2
            Server.PushLog(conn, "<黄>迷失幼妖已被驱散！请点击下方掉落物品拾取装备。</黄>")
        end

        -- 装备掉落：自动拾取到背包
        local lootToken = ""
        local lootItemName = ""
        local invCount = pd.inventory and #pd.inventory or 0
        if invCount >= Settings.INVENTORY_MAX then
            -- 背包满，跳过掉落
        elseif math.random() < monDef.drop_rate then
            local dropItem = Server.GenEquipDrop(pd.realm or 1, pd)
            if dropItem then
                -- 直接放入背包
                if not pd.inventory then pd.inventory = {} end
                table.insert(pd.inventory, dropItem)
                local qualityName = Settings.EQUIPMENT_QUALITY[dropItem.quality]
                    and Settings.EQUIPMENT_QUALITY[dropItem.quality].name or "普通"
                lootItemName = dropItem.name .. "（" .. qualityName .. "）"
                lootToken = "auto"  -- 标记为自动拾取
            end
        end

        -- 材料掉落（域外战场怪物专属）
        -- drop_materials 是字符串数组，如 {"herb_green", "catalyst_powder"}
        -- drop_rate 是该怪物的统一掉落概率
        local matDropMsg = ""
        if monDef.drop_materials and #monDef.drop_materials > 0 then
            local bagCount = pd.inventory and #pd.inventory or 0
            local dropRate = monDef.drop_rate or 0.15
            for _, matId in ipairs(monDef.drop_materials) do
                if bagCount >= Settings.INVENTORY_MAX then break end
                if math.random() <= dropRate then
                    local matCount = 1
                    -- 堆叠到背包
                    local found = false
                    for _, item in ipairs(pd.inventory or {}) do
                        if item.id == matId then
                            item.count = (item.count or 1) + matCount
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(pd.inventory, { id = matId, count = matCount, type = "material" })
                        bagCount = bagCount + 1
                    end
                    local matDef = Settings.ALCHEMY_MATERIALS[matId]
                    local matName = matDef and matDef.name or matId
                    matDropMsg = matDropMsg .. string.format("，材料【%s】×%d", matName, matCount)
                end
            end
        end

        -- 矿石掉落（按楼层独立掉落表，BATTLEFIELD_ORE_DROPS）
        local oreLayer = pd._battleMonsterLayer
        if oreLayer and Settings.BATTLEFIELD_ORE_DROPS[oreLayer] then
            local oreDrops = Settings.BATTLEFIELD_ORE_DROPS[oreLayer]
            local bagCount2 = pd.inventory and #pd.inventory or 0
            for _, oreDef in ipairs(oreDrops) do
                if bagCount2 >= Settings.INVENTORY_MAX then break end
                if math.random() <= oreDef.rate then
                    -- 堆叠到背包
                    local found = false
                    for _, item in ipairs(pd.inventory or {}) do
                        if item.id == oreDef.id then
                            item.count = (item.count or 1) + 1
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(pd.inventory, { id = oreDef.id, count = 1, type = "material" })
                        bagCount2 = bagCount2 + 1
                    end
                    local oreMat = Settings.ALCHEMY_MATERIALS[oreDef.id]
                    local oreName = oreMat and oreMat.name or oreDef.id
                    matDropMsg = matDropMsg .. string.format("，矿石【%s】×1", oreName)
                end
            end
        end

        data["Win"]       = Variant(true)
        data["Log"]       = Variant(string.format(
            "<绿>战斗胜利！获得潜能+%d，银两+%d%s</绿>",
            potentialGain, monDef.silver, matDropMsg
        ))
        data["ExpGain"]   = Variant(0)
        data["PotentialGain"] = Variant(potentialGain)
        data["SilverGain"]= Variant(monDef.silver)
        -- 掉落 token（空字符串表示无掉落）
        data["LootToken"]    = Variant(lootToken)
        data["LootItemName"] = Variant(lootItemName)
    else
        -- 失败处理：检查灵石免死
        local reviveCost = Settings.SPIRIT_STONE.REVIVE_COST
        local maxHp = Shared.CalcStats(pd).hp
        if pd.revive_shield and (pd.spirit_stone or 0) >= reviveCost then
            -- 灵石免死：扣灵石，恢复满血，不扣银两
            pd.spirit_stone = pd.spirit_stone - reviveCost
            pd.hp = maxHp
            data["Win"]  = Variant(false)
            data["Log"]  = Variant(string.format(
                "<金>💎灵石免死生效！消耗%d灵石，气血完全恢复。</金>", reviveCost))
        else
            -- 正常失败：扣除部分银两
            local loseSilver = math.floor((pd.silver or 0) * 0.05)
            pd.silver = math.max(0, (pd.silver or 0) - loseSilver)
            pd.hp = math.floor(maxHp * 0.3)
            data["Win"]  = Variant(false)
            if pd.revive_shield then
                data["Log"] = Variant(string.format(
                    "<红>战败！灵石不足无法免死，损失%s银两……</红>", Shared.FormatSilver(loseSilver)))
            else
                data["Log"] = Variant(string.format(
                    "<红>战败！损失%s银两，就地疗伤恢复部分气血……</红>", Shared.FormatSilver(loseSilver)))
            end
        end
    end

    -- 域外战场怪物击杀：战斗胜利时通知 MonsterManager 移除地图上的怪物并排入重生队列
    if result.win and pd._battleMonsterUid and pd._battleMonsterLayer then
        Server.MapMonsterKilled(pd._battleMonsterLayer, pd._battleMonsterUid)
        -- 帮会日常：击杀怪物
        Server.AdvanceGuildDaily(uid, "kill_mon", 1)
        -- 门派试炼：击杀怪物
        if result.monsterDef then
            Server.OnTrialKillMonster(uid, conn, pd, result.monsterDef.id)
        end
        -- 首次战场胜利奖励：100银两
        if not pd.first_battle_reward then
            pd.first_battle_reward = true
            pd.silver = (pd.silver or 0) + 100
            Server.PushLog(conn, "<金>🎉【首次战场胜利】额外奖励100银两！继续战斗积累修为吧！</金>")
        end
    end
    -- 任务系统：所有怪物战斗胜利都计入击杀（主线/日常/活动）
    if result.win and result.monsterDef then
        Quest.OnKillMonster(pd, conn, pd._battleMonsterLayer)
        Activity.OnKillMonster(pd)
    end
    -- 任务系统：战斗结束（不论胜负，计入日常）
    Quest.OnBattleFinished(pd, conn)
    if result.win then
        Quest.OnWinBattle(pd, conn)
        Activity.OnWinBattle(pd)
    end
    pd._battleMonsterUid = nil
    pd._battleMonsterLayer = nil

    print("[Server] 即将发送 PUSH_BATTLE_END，事件名=" .. tostring(Settings.EVENTS.PUSH_BATTLE_END))
    conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_BATTLE_END), true, data)
    print("[Server] PUSH_BATTLE_END 已发送")

    -- 推送更新后的玩家数据
    Server.PushPlayerData(uid, conn)
end

-- 生成装备掉落（按玩家境界匹配tier）
function Server.GenEquipDrop(playerRealm, pd)
    if #Settings.EQUIPMENT_TEMPLATES == 0 then return nil end
    local realm = playerRealm or 1
    -- 筛选当前境界及前一阶的装备模板
    local candidates = {}
    for _, t in ipairs(Settings.EQUIPMENT_TEMPLATES) do
        local tier = t.tier or 1
        if tier == realm or tier == realm - 1 then
            candidates[#candidates + 1] = t
        end
    end
    if #candidates == 0 then
        -- fallback: 取最高tier可用的
        for _, t in ipairs(Settings.EQUIPMENT_TEMPLATES) do
            if (t.tier or 1) <= realm then
                candidates[#candidates + 1] = t
            end
        end
    end
    if #candidates == 0 then candidates = Settings.EQUIPMENT_TEMPLATES end

    local tmpl = candidates[math.random(1, #candidates)]
    -- 掉落品质：大部分普通，少数优秀/精良（含幸运值保底）
    local qualityRoll = math.random()
    local quality = 1
    -- ★ 幸运值保底：连续100次掉落无史诗则必出史诗
    if pd and pd.equip_pity and pd.equip_pity >= 100 then
        quality = 4  -- 保底触发：必出史诗
        pd.equip_pity = 0
    elseif qualityRoll < 0.03 then
        quality = 4       -- 3% 史诗
        if pd then pd.equip_pity = 0 end  -- 自然出史诗也重置
    elseif qualityRoll < 0.10 then quality = 3   -- 7% 精良
    elseif qualityRoll < 0.25 then quality = 2   -- 15% 优秀
    else
        -- 非史诗掉落，累计幸运值
        if pd then pd.equip_pity = (pd.equip_pity or 0) + 1 end
    end

    local mult = Settings.EQUIPMENT_QUALITY_MULTIPLIER[quality] or 1.0
    local stats = {}
    for k, v in pairs(tmpl.base) do
        stats[k] = math.floor(v * mult)
    end

    return {
        type        = "equipment",
        id          = Shared.GenId(),
        template_id = tmpl.id,
        name        = tmpl.name .. (quality > 1 and ("·" .. Settings.EQUIPMENT_QUALITY[quality].name) or ""),
        slot        = tmpl.slot,
        quality     = quality,
        stats       = stats,
        bound       = false,
    }
end

-- 升级检查
function Server.CheckLevelUp(pd)
    -- 旧的纯等级升级已弃用，改为境界经验封顶检测
    -- 经验满后需要手动突破（消耗丹药），不再自动升级
    Server.CheckRealmExp(pd)
end

--- 境界经验检测：层内自动升重，跨境界封顶等待手动突破
function Server.CheckRealmExp(pd)
    if Settings.REALM.IsMaxRealm(pd.realm or 1, pd.realm_layer or 1) then
        pd.realm_exp = 0
        pd.level = Settings.REALM.CalcPowerLevel(pd.realm or 1, pd.realm_layer or 1)
        return
    end
    local realm = pd.realm or 1
    local layer = pd.realm_layer or 1
    local stage = Settings.REALM.STAGES[realm]
    if not stage then return end

    local needed = Settings.REALM.GetExpNeeded(realm, layer)

    -- 层内自动升重（经验满且未到本境界最末层）
    local layerChanged = false
    while (pd.realm_exp or 0) >= needed and layer < stage.layers do
        pd.realm_exp = (pd.realm_exp or 0) - needed
        layer = layer + 1
        pd.realm_layer = layer
        needed = Settings.REALM.GetExpNeeded(realm, layer)
        layerChanged = true
    end

    -- 已到本境界最末层：经验封顶，等待跨境界手动突破
    if layer >= stage.layers then
        if (pd.realm_exp or 0) >= needed then
            pd.realm_exp = needed  -- 封顶
        end
    end

    -- 同步兼容字段
    pd.level = Settings.REALM.CalcPowerLevel(pd.realm or 1, pd.realm_layer or 1)

    -- 境界/层变化时立即存档（防止重启丢失关键进度）
    if layerChanged then
        Server.SavePlayerData(pd.uid, pd)
    end
end

-- ============================================================================
-- 场景切换
-- ============================================================================

function Server_OnReqMoveScene(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local targetScene = eventData["Scene"]:GetString()

    -- 战斗中不能切换场景
    if Combat.IsInBattle(uid) then
        Server.PushLog(conn, "<红>战斗中无法移动！</红>")
        return
    end

    -- 门派场景自由进入（玩家需要前往宗门才能拜师）

    -- 古村新手引导锁：未完成引导不可出村
    if pd.scene == Settings.SCENES.ANCIENT_VILLAGE and (pd.tutorial_step or 0) < 3 then
        Server.PushLog(conn, "<红>老村长的声音传来：「孩子，还没准备好，先来找我。」</红>")
        return
    end

    -- 验证目标场景是否存在
    if not Settings.SCENE_DESC[targetScene] then
        Server.PushLog(conn, "<红>无法前往该地点</红>")
        return
    end

    -- 切换场景时落到该场景默认地点
    local oldScene = pd.scene
    pd.spot  = Settings.SCENE_DEFAULT_SPOT[targetScene] or ""
    pd.scene = targetScene
    local desc = Settings.SCENE_DESC[targetScene] or targetScene
    Server.PushLog(conn, "\n" .. desc)
    -- 任务系统：进入场景
    Quest.OnEnterScene(pd, conn, targetScene)
    -- 新手首次进城提示
    if targetScene == "main_city" and not pd.hint_city_shown then
        pd.hint_city_shown = true
        Server.PushLog(conn, "<黄>【新手提示】欢迎来到扬州城！</黄>")
        Server.PushLog(conn, "<黄>  · 找「药铺老板」买丹药（突破必备）</黄>")
        Server.PushLog(conn, "<黄>  · 找「武器商人」「防具商人」购买装备</黄>")
        Server.PushLog(conn, "<黄>  · 底部【战斗】按钮可进入域外战场（已解锁1-2层）</黄>")
        Server.PushLog(conn, "<黄>  · 底部【打坐】按钮可修炼积累修为</黄>")
    end
    -- 通知旧场景所有玩家刷新（该玩家离开了）
    Server.BroadcastSpotPlayers(oldScene)
    Server.PushPlayerData(uid, conn)
end

-- ============================================================================
-- 小地点切换
-- ============================================================================

function Server_OnReqChangeSpot(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local spot = eventData["Spot"]:GetString()
    pd.spot = spot
    -- 门派试炼：到达目的地检查
    Server.OnTrialTravel(uid, conn, pd)
    -- 广播同场景所有玩家的小地点信息
    Server.BroadcastSpotPlayers(pd.scene)
end

-- 广播同场景内所有玩家的小地点数据
function Server.BroadcastSpotPlayers(scene)
    -- 收集该场景内所有在线玩家的 {name, spot}
    local list = {}
    for uid2, pd2 in pairs(players_) do
        if pd2.scene == scene then
            list[#list + 1] = { name = pd2.name or "侠客", spot = pd2.spot or "" }
        end
    end
    -- 向该场景所有在线玩家推送（数组需要 JSON 编码，值需用 Variant 包装）
    local json = cjson.encode(list)
    local data = VariantMap()
    data["Players"] = Variant(json)
    for uid2, pd2 in pairs(players_) do
        if pd2.scene == scene then
            local conn2 = connections_[uid2]
            if conn2 then
                conn2:SendRemoteEvent(Settings.EVENTS.PUSH_SPOT_PLAYERS, true, data)
            end
        end
    end
end

-- ============================================================================
-- NPC交互
-- ============================================================================

function Server_OnReqInteractNpc(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local npcId = eventData["NpcId"]:GetString()
    print("[Server] NPC交互 uid:", tostring(uid), "npcId:", npcId)

    if TRIAL_NPC_TO_SECT[npcId] then
        Server.HandleSectTrial(uid, conn, pd, TRIAL_NPC_TO_SECT[npcId])
    elseif RECRUITER_TO_SECT[npcId] then
        Server.HandleJoinSect(uid, conn, pd, RECRUITER_TO_SECT[npcId])
    elseif MASTER_TO_SECT[npcId] then
        Server.HandleSectMaster(uid, conn, pd, MASTER_TO_SECT[npcId])
    elseif NPC_TO_ELDER[npcId] then
        local elderInfo = NPC_TO_ELDER[npcId]
        Server.HandleSkillElder(uid, conn, pd, elderInfo.branch, npcId, elderInfo)
    elseif npcId == "market_keeper" then
        -- 交易阁在客户端直接展示，不需要服务端特殊处理
        Server.PushLog(conn, "掌柜笑道：「欢迎光临交易阁，天下功法，应有尽有！」")
    elseif npcId == "equipment_shop" then
        Server.HandleEquipmentShop(uid, conn, pd)
    elseif npcId == "medicine_shop" then
        Server.HandleMedicineShop(uid, conn, pd)
    elseif npcId == "wandering_swordsman" then
        Server.HandleWanderingSwordsman(uid, conn, pd)
    elseif npcId == "village_elder" then
        Server.HandleVillageElder(uid, conn, pd)
    elseif npcId == "inn_keeper" then
        -- 客栈掌柜：免费休息恢复满血
        local maxHp = Shared.CalcStats(pd).hp
        local curHp = pd.hp or maxHp
        if curHp >= maxHp then
            Server.PushLog(conn, "掌柜笑道：「客官气色不错，无需歇息，喝杯茶再走吧！」")
        else
            pd.hp = maxHp
            Server.PushLog(conn, string.format("<绿>掌柜安排你入住上房歇息，气血恢复至满（%d → %d）</绿>", math.floor(curHp), math.floor(maxHp)))
            Server.PushPlayerData(uid, conn)
        end
    else
        Server.PushLog(conn, "对方只是望了你一眼，没有说话。")
    end
end

-- 发送 NPC 对话（带选项）
function Server.PushNpcDialog(conn, npcName, dialog, options)
    local encoded = cjson.encode(options or {})
    local data = VariantMap()
    data["npc_name"]     = Variant(npcName)
    data["dialog"]       = Variant(dialog)
    data["options_json"] = Variant(encoded)
    conn:SendRemoteEvent(Settings.EVENTS.NPC_DIALOG, true, data)
end

-- 流浪剑客张鹤：可挑战战斗
function Server.HandleWanderingSwordsman(uid, conn, pd)
    -- 选一个与玩家等级匹配的野怪
    local level = pd.level or 1
    local monsterId
    if level >= 8 then
        monsterId = "demon_wolf"
    elseif level >= 5 then
        monsterId = "black_bear"
    elseif level >= 3 then
        monsterId = "bandit"
    else
        monsterId = "wolf"
    end

    local monsterDef = Shared.GetMonsterDef(monsterId)
    local monsterName = monsterDef and monsterDef.name or monsterId

    Server.PushNpcDialog(conn,
        "流浪剑客·张鹤",
        string.format(
            "剑客斜眼打量了你一番，懒洋洋地说：\n「又一个不知死活的毛头小子。我在此地已杀了三十七人，你要做第三十八个么？\n……哼，看你眼神还算有点意思。来，我让一头%s陪你热身。」",
            monsterName
        ),
        {
            { text = "接受挑战！",   action = "battle", data = monsterId },
            { text = "量力而行，转身离去", action = "leave"  },
        }
    )
end

-- ============================================================================
-- 老村长：新手引导对话（按 tutorial_step 分支）
-- tutorial_step 0 → 介绍世界，接取任务，推进至 step 1
-- tutorial_step 1 → 提醒去打迷失幼妖
-- tutorial_step 2 → 任务完成复命，给予小回血丹，推进至 step 3（出村解锁）
-- tutorial_step 3+ → 普通闲聊
-- ============================================================================
function Server.HandleVillageElder(uid, conn, pd)
    local step = pd.tutorial_step or 0

    if step == 0 then
        -- 第一次见面：世界介绍 + 接取任务
        Server.PushNpcDialog(conn,
            "老村长",
            "老人抬起满是皱纹的脸，慈祥地打量着你，缓缓开口：\n\n「孩子，你初入江湖，可知这天地之大？」\n\n「此处乃扬州古村，老夫在此守了数十载。村外是新手野外，凶兽出没，游侠往来。再往北，便是扬州城，百业繁华，功法典籍皆可寻觅。而城外的剑宗，乃天下剑道之宗，若有志于剑道，日后亦可拜入门墙。」\n\n「然而，近日村外出现了数只迷失幼妖，扰得村人不得安宁。老夫年迈，力不从心。你既至此，可否替老夫驱散那幼妖，让村人安心？」",
            {
                { text = "晚辈愿意效劳！",   action = "tutorial_accept" },
                { text = "稍候再说。",        action = "leave"           },
            }
        )
    elseif step == 1 then
        -- 已接任务，提醒去打幼妖
        Server.PushNpcDialog(conn,
            "老村长",
            "老人目光期待地望向村外：\n\n「孩子，村口便有迷失幼妖出没。以你的身手，制服那幼妖当不在话下。」\n\n「点击「对战」，选中「迷失幼妖」，将其驱散即可。切记，万事开头难，胜了第一场，日后方能走得更远。」",
            {
                { text = "明白了，这就去！", action = "leave" },
            }
        )
    elseif step == 2 then
        -- 玩家已击败幼妖，前来复命
        pd.tutorial_step = 3

        -- 给予奖励：一瓶小回血丹
        local rewardItem = {
            type  = "medicine",
            id    = Shared.GenId(),
            item_id  = "medicine_small_hp",
            name  = "小回血丹",
            count = 3,
            effect = { hp = 40 },
            desc  = "最基础的疗伤丹药，略微止血。",
        }
        Server.AddItemToInventory(uid, rewardItem, function()
            -- 异步写入完成后推送背包和玩家数据
            Server.PushInventory(uid, conn)
            Server.PushPlayerData(uid, conn)
        end)

        Server.PushNpcDialog(conn,
            "老村长",
            "老人抚掌大笑，眼中满是欣慰：\n\n「好！好！果然是有灵根之人，小小幼妖不在话下！」\n\n「江湖路远，老夫无以为赠，这三粒【小回血丹】聊表心意，望你保重身体，切勿逞强。」\n\n「村口的路已经通了，去吧，孩子。新手野外、扬州城，乃至更远的地方，都在等着你去闯荡。\n\n记住——江湖凶险，武道无涯，但只要心中有道，何处皆可立足。」",
            {
                { text = "多谢村长，晚辈告辞！", action = "leave" },
            }
        )

        -- 教程完成奖励：200银两
        pd.silver = (pd.silver or 0) + 200
        Server.PushLog(conn, "<金>【引导完成】获得小回血丹×3 + 200银两！古村出口已解锁。</金>")
        Server.PushLog(conn, "")
        Server.PushLog(conn, "<金>═══════ 新手目标指引 ═══════</金>")
        Server.PushLog(conn, "<红>⚠ 重要：【打坐】是练功法技能，不是升境界！</红>")
        Server.PushLog(conn, "<红>  升境界靠【战斗】获得修为经验，满了再突破。</红>")
        Server.PushLog(conn, "<黄>1. 点击底部【战斗】杀怪获取修为经验（升级唯一途径）</黄>")
        Server.PushLog(conn, "<黄>2. 修为满后，点击【突破】晋升境界</黄>")
        Server.PushLog(conn, "<黄>3. 突破到筑基需要「筑基丹」→ 去扬州城【药铺】购买</黄>")
        Server.PushLog(conn, "<黄>4. 【打坐】用于提升功法熟练度（消耗潜能）</黄>")
        Server.PushLog(conn, "<黄>5. 点击顶部【地图】前往扬州城探索</黄>")
        Server.PushLog(conn, "<金>═══════════════════════════</金>")
    else
        -- 已完成引导：普通闲聊
        Server.PushNpcDialog(conn,
            "老村长",
            "老人微微颔首，目送远方：\n\n「孩子，江湖路漫漫，步步皆是修行。老夫在此祝你一路顺遂，武道有成。」\n\n「若日后闯出了名堂，记得回来告诉老夫。」",
            {
                { text = "定不负村长期望！", action = "leave" },
            }
        )
    end
end

-- ============================================================================
-- 宗门试炼系统
-- ============================================================================

-- 试炼NPC交互入口
function Server.HandleSectTrial(uid, conn, pd, sectId)
    local quest = Settings.SECT_TRIAL.QUESTS[sectId]
    local cfg   = SECT_CONFIG[sectId]
    if not quest or not cfg then
        Server.PushLog(conn, "对方只是望了你一眼，没有说话。")
        return
    end

    local npcName = quest.npc_id  -- 用于对话显示
    -- 从NPC定义中获取显示名
    local sceneCfg = Settings.NPCS[cfg.scene]
    if sceneCfg then
        for _, npc in ipairs(sceneCfg) do
            if npc.id == quest.npc_id then npcName = npc.name; break end
        end
    end

    -- 已加入门派时：只有本宗执事会打招呼
    if pd.sect ~= "" then
        if pd.sect == sectId then
            Server.PushLog(conn, string.format("%s微微行礼：「%s弟子，好好修炼。」", npcName, cfg.display))
        else
            local curDisplay = SECT_CONFIG[pd.sect] and SECT_CONFIG[pd.sect].display or pd.sect
            Server.PushLog(conn, string.format("%s淡然道：「你已是%s弟子，恕不接待。」", npcName, curDisplay))
        end
        return
    end

    -- 境界检查
    local reqRealm = Settings.REALM.JOIN_SECT_REALM
    local reqLayer = Settings.REALM.JOIN_SECT_LAYER
    if (pd.realm or 1) < reqRealm or ((pd.realm or 1) == reqRealm and (pd.realm_layer or 1) < reqLayer) then
        local reqName = Settings.REALM.GetDisplayName(reqRealm, reqLayer)
        Server.PushLog(conn, string.format("%s摇头道：「修为尚浅，待你修至%s再来。」", npcName, reqName))
        return
    end

    -- 初始化试炼数据
    if not pd.sect_trials then pd.sect_trials = {} end
    local trial = pd.sect_trials[sectId]

    -- 已完成（领过奖但未加入）：提供加入选项
    if trial and trial.status == "completed" then
        Server.PushNpcDialog(conn, npcName,
            string.format("「你已通过本宗试炼。是否正式加入%s？」", cfg.display),
            {
                { action = "trial_join", data = sectId, text = "正式拜入" .. cfg.display },
                { action = "close", text = "暂不加入" },
            })
        return
    end

    -- 已接取（进行中）：先检查是否可自动完成
    if trial and trial.status == "accepted" then
        local progress = trial.progress or 0
        local total    = quest.count or 1

        -- collect 类型：回来时尝试自动提交材料
        if quest.type == "collect" then
            Server.TrySubmitCollectTrial(uid, conn, pd, sectId)
            progress = trial.progress or 0  -- 刷新进度
        end

        -- battlefield 类型：检查当前层是否已达标
        if quest.type == "battlefield" then
            local curMax = pd.max_battlefield_layer or 1
            if curMax >= quest.target_layer and progress < 1 then
                trial.progress = 1
                progress = 1
            end
        end

        -- 进度满足 → 自动完成试炼
        if progress >= total then
            Server.CheckTrialProgress(uid, conn, pd, sectId)
            return
        end

        -- 进度未满：显示进度对话
        local progressText
        if quest.type == "travel" then
            progressText = "尚未到达目的地"
        elseif quest.type == "battlefield" then
            local curMax = pd.max_battlefield_layer or 1
            progressText = string.format("当前已通过第%d层（需通过第%d层）", curMax, quest.target_layer)
        else
            progressText = string.format("进度：%d/%d", progress, total)
        end
        Server.PushNpcDialog(conn, npcName,
            string.format("「%s」\n当前%s", quest.name, progressText),
            {
                { action = "trial_abandon", data = sectId, text = "放弃试炼" },
                { action = "close", text = "继续努力" },
            })
        return
    end

    -- 未接取（nil状态）：提供接取选项
    Server.PushNpcDialog(conn, npcName,
        string.format("「%s」\n%s", quest.name, quest.desc),
        {
            { action = "trial_accept", data = sectId, text = "接受试炼" },
            { action = "close", text = "暂不接受" },
        })
end

-- 检查试炼是否完成（通用入口，各钩子调用）
function Server.CheckTrialProgress(uid, conn, pd, sectId)
    if not pd.sect_trials then return end
    local trial = pd.sect_trials[sectId]
    if not trial or trial.status ~= "accepted" then return end

    local quest = Settings.SECT_TRIAL.QUESTS[sectId]
    if not quest then return end

    local total = quest.count or 1
    local progress = trial.progress or 0

    if progress >= total then
        -- 完成试炼，发放奖励
        trial.status = "completed"
        local reward = Settings.SECT_TRIAL.REWARD_POTENTIAL
        pd.potential = (pd.potential or 0) + reward
        Server.PushLog(conn, string.format(
            "<金>【试炼完成】%s！获得潜能 +%d</金>", quest.name, reward))
        Server.PushLog(conn, quest.complete_msg)
        Server.PushPlayerData(uid, conn)
        Quest.PushQuestState(pd, conn)
        Server.SavePlayerData(uid, pd)
    end
end

-- 试炼进度钩子：击杀怪物
function Server.OnTrialKillMonster(uid, conn, pd, monsterId)
    if not pd.sect_trials then return end
    for sectId, trial in pairs(pd.sect_trials) do
        if trial.status == "accepted" then
            local quest = Settings.SECT_TRIAL.QUESTS[sectId]
            if quest and quest.type == "kill" and quest.target == monsterId then
                trial.progress = (trial.progress or 0) + 1
                Quest.PushQuestState(pd, conn)
                Server.CheckTrialProgress(uid, conn, pd, sectId)
                return
            end
        end
    end
end

-- 试炼进度钩子：战场层通关（Boss击败时调用）
function Server.OnTrialBattlefieldClear(uid, conn, pd)
    if not pd.sect_trials then return end
    for sectId, trial in pairs(pd.sect_trials) do
        if trial.status == "accepted" then
            local quest = Settings.SECT_TRIAL.QUESTS[sectId]
            if quest and quest.type == "battlefield" then
                local curMax = pd.max_battlefield_layer or 1
                if curMax >= quest.target_layer then
                    trial.progress = 1
                    Server.CheckTrialProgress(uid, conn, pd, sectId)
                end
                return
            end
        end
    end
end

-- 试炼进度钩子：到达地点（切换spot时调用）
function Server.OnTrialTravel(uid, conn, pd)
    if not pd.sect_trials then return end
    for sectId, trial in pairs(pd.sect_trials) do
        if trial.status == "accepted" then
            local quest = Settings.SECT_TRIAL.QUESTS[sectId]
            if quest and quest.type == "travel" then
                if pd.scene == quest.target_scene and pd.spot == quest.target_spot then
                    trial.progress = 1
                    Quest.PushQuestState(pd, conn)
                    Server.PushLog(conn, "<黄>【试炼】已到达目的地，回去找执事复命吧。</黄>")
                    -- 不自动完成，需要回去找NPC
                end
                return
            end
        end
    end
end

-- 试炼进度钩子：锻造成功（锻造回调中调用）
function Server.OnTrialForgeSuccess(uid, conn, pd, bpId)
    if not pd.sect_trials then return end
    for sectId, trial in pairs(pd.sect_trials) do
        if trial.status == "accepted" then
            local quest = Settings.SECT_TRIAL.QUESTS[sectId]
            if quest and quest.type == "forge" and quest.target == bpId then
                trial.progress = (trial.progress or 0) + 1
                Quest.PushQuestState(pd, conn)
                Server.CheckTrialProgress(uid, conn, pd, sectId)
                return
            end
        end
    end
end

-- 试炼进度钩子：收集上交（与NPC对话时检查背包）
function Server.TrySubmitCollectTrial(uid, conn, pd, sectId)
    local quest = Settings.SECT_TRIAL.QUESTS[sectId]
    if not quest or quest.type ~= "collect" then return false end

    local trial = pd.sect_trials and pd.sect_trials[sectId]
    if not trial or trial.status ~= "accepted" then return false end

    -- 检查背包中目标材料数量
    local have = 0
    for _, item in ipairs(pd.inventory or {}) do
        if item.id == quest.target then
            have = have + (item.count or 1)
        end
    end

    local need = quest.count - (trial.progress or 0)
    if have <= 0 then return false end

    -- 扣除材料
    local submit = math.min(have, need)
    local remaining = submit
    for i = #(pd.inventory or {}), 1, -1 do
        if remaining <= 0 then break end
        local item = pd.inventory[i]
        if item.id == quest.target then
            local c = item.count or 1
            if c <= remaining then
                remaining = remaining - c
                table.remove(pd.inventory, i)
            else
                item.count = c - remaining
                remaining = 0
            end
        end
    end

    trial.progress = (trial.progress or 0) + submit
    local matDef = Settings.ALCHEMY_MATERIALS[quest.target]
    local matName = matDef and matDef.name or quest.target
    Server.PushLog(conn, string.format("<绿>上交【%s】×%d，进度：%d/%d</绿>",
        matName, submit, trial.progress, quest.count))
    Quest.PushQuestState(pd, conn)
    Server.CheckTrialProgress(uid, conn, pd, sectId)
    Server.PushInventory(uid, conn)
    return true
end

-- 加入门派（sectId 由 RECRUITER_TO_SECT 查找传入）
function Server.HandleJoinSect(uid, conn, pd, sectId)
    local cfg = SECT_CONFIG[sectId]
    if not cfg then
        Server.PushLog(conn, "对方只是望了你一眼，没有说话。")
        return
    end

    if pd.sect ~= "" then
        local curDisplay = (SECT_CONFIG[pd.sect] and SECT_CONFIG[pd.sect].display) or pd.sect
        Server.PushLog(conn, string.format("门人说：「你已经是%s的弟子了。」", curDisplay))
        return
    end
    -- 境界检查：需要筑基一层方可入门
    local reqRealm = Settings.REALM.JOIN_SECT_REALM
    local reqLayer = Settings.REALM.JOIN_SECT_LAYER
    if (pd.realm or 1) < reqRealm or ((pd.realm or 1) == reqRealm and (pd.realm_layer or 1) < reqLayer) then
        local reqName = Settings.REALM.GetDisplayName(reqRealm, reqLayer)
        Server.PushLog(conn, string.format("门人说：「修为尚浅，待你修至%s，再来入门不迟。」", reqName))
        return
    end

    pd.sect = sectId
    Server.PushLog(conn, cfg.join_msg)
    -- 任务系统：加入门派
    Quest.OnJoinSect(pd, conn)

    -- 传授入门基础功法
    local ok, _ = Cultivation.LearnSkill(pd, cfg.basic_skill, true)
    if ok then
        Server.PushLog(conn, cfg.grant_msg)
        local skillDef = Shared.GetSkillDef(cfg.basic_skill)
        local data = VariantMap()
        data["SkillId"]   = Variant(cfg.basic_skill)
        data["SkillName"] = Variant(skillDef and skillDef.name or cfg.basic_skill)
        data["Bound"]     = Variant(true)
        conn:SendRemoteEvent(Settings.EVENTS.NPC_SKILL_GRANT, true, data)
    end
    Server.PushPlayerData(uid, conn)
end

-- 掌门：传授神级功法（需要绝世满级）
function Server.HandleSectMaster(uid, conn, pd, sectId)
    local cfg = SECT_CONFIG[sectId]
    if not cfg or pd.sect ~= sectId then
        local wrongMsg = cfg and cfg.wrong_sect or "掌门说：「你并非本宗弟子。」"
        Server.PushLog(conn, wrongMsg)
        return
    end

    -- 检查是否有满级绝世功法可进阶
    local advanceable = {}
    for _, sk in ipairs(pd.skills or {}) do
        local def = Shared.GetSkillDef(sk.id)
        if def and def.grade == 4 and sk.proficiency >= def.max_proficiency then
            local nextId = Cultivation.GetNextSkill(sk.id)
            if nextId and not Cultivation.GetOwnedSkill(pd, nextId) then
                advanceable[#advanceable + 1] = nextId
            end
        end
    end

    if #advanceable > 0 then
        -- 进阶神级功法
        for _, skillId in ipairs(advanceable) do
            local ok, _ = Cultivation.LearnSkill(pd, skillId, true)
            if ok then
                local def = Shared.GetSkillDef(skillId)
                Server.PushLog(conn, string.format("<黄>掌门传授神级功法%s！</黄>", def and def.name or skillId))
            end
        end
        Server.PushPlayerData(uid, conn)
        return
    end

    -- 师傅指点修炼（costMultiplier = MASTER，更高效）
    if pd.cultivating and pd.cultivating ~= "" then
        -- 已在修炼中，切换为师傅指点倍率
        pd.cultivate_cost_mult = Settings.CULTIVATE_COST_MULT.MASTER
        Server.PushLog(conn, "<绿>掌门亲自指点你的修炼，效率大增！</绿>")
        Server.PushPlayerData(uid, conn)
        return
    end

    -- 未在修炼 → 提示用修炼选项
    local cultivableSkills = {}
    for _, sk in ipairs(pd.skills or {}) do
        local def = Shared.GetSkillDef(sk.id)
        if def and sk.proficiency < def.max_proficiency then
            cultivableSkills[#cultivableSkills + 1] = { id = sk.id, name = def.name }
        end
    end

    if #cultivableSkills == 0 then
        Server.PushLog(conn, "掌门说：「你的功法皆已登峰造极，为师甚慰。」")
        return
    end

    -- 找到第一个可修炼的功法，以师傅指点开始修炼
    local firstSkill = cultivableSkills[1]
    local ok, msg = Cultivation.StartCultivate(pd, firstSkill.id, Settings.CULTIVATE_COST_MULT.MASTER)
    if ok then
        Server.PushLog(conn, string.format("<绿>掌门指点你修炼%s，效率大增！</绿>", firstSkill.name))
    else
        Server.PushLog(conn, "<红>" .. msg .. "</红>")
    end
    Server.PushPlayerData(uid, conn)
end

-- 长老传功（中级/高级/绝世）
-- 找该分支当前可传授的下一阶功法列表（已满级且未拥有下阶）
local function FindGrantable(pd, branch)
    local toGrant = {}
    for _, sk in ipairs(pd.skills or {}) do
        local def = Shared.GetSkillDef(sk.id)
        if def and (def.branch == branch or def.branch == "common") then
            if sk.proficiency >= def.max_proficiency then
                local nextId = nil
                if def.branch == "common" then
                    -- common branch 可分叉，按 branch 方向查找
                    for _, skillDef in ipairs(Settings.SKILLS) do
                        if skillDef.require_skill == sk.id and skillDef.branch == branch then
                            nextId = skillDef.id
                            break
                        end
                    end
                else
                    nextId = Cultivation.GetNextSkill(sk.id)
                end
                if nextId then
                    local nextDef = Shared.GetSkillDef(nextId)
                    if nextDef and nextDef.branch == branch and not Cultivation.GetOwnedSkill(pd, nextId) then
                        toGrant[#toGrant + 1] = nextId
                    end
                end
            end
        end
    end
    return toGrant
end

-- 执行传功并推送 NPC_SKILL_GRANT（skills_json 格式），返回实际传授列表
function Server.GrantSkills(uid, conn, pd, skillIds)
    local granted = {}
    for _, skillId in ipairs(skillIds) do
        local ok, _ = Cultivation.LearnSkill(pd, skillId, true)
        if ok then
            local def = Shared.GetSkillDef(skillId)
            granted[#granted + 1] = {
                skill_id   = skillId,
                skill_name = def and def.name or skillId,
                bound      = true,
            }
        end
    end
    if #granted > 0 then
        local data = VariantMap()
        data["skills_json"] = Variant(cjson.encode(granted))
        conn:SendRemoteEvent(Settings.EVENTS.NPC_SKILL_GRANT, true, data)
        Server.PushPlayerData(uid, conn)
    end
    return granted
end

-- elderInfo = { sect_id, branch, display }（由 NPC_TO_ELDER 查找传入）
function Server.HandleSkillElder(uid, conn, pd, branch, npcId, elderInfo)
    local sectId   = elderInfo and elderInfo.sect_id or ""
    local elderName = elderInfo and elderInfo.display or "长老"
    local cfg      = SECT_CONFIG[sectId]

    -- 未加入对应门派
    if pd.sect ~= sectId then
        local sectDisplay = cfg and cfg.display or sectId
        Server.PushNpcDialog(conn, elderName,
            "长老淡淡扫了你一眼：「此处乃" .. sectDisplay .. "重地，非本宗弟子不得习武。」",
            { { text = "告辞", action = "leave" } }
        )
        return
    end

    -- 找可传授功法
    local toGrant = FindGrantable(pd, branch)

    if #toGrant == 0 then
        -- 判断是否已至顶阶（无下一阶可学）
        local atTop = true
        for _, sk in ipairs(pd.skills or {}) do
            local def = Shared.GetSkillDef(sk.id)
            if def and def.branch == branch then
                if sk.proficiency < def.max_proficiency then
                    atTop = false
                    break
                end
            end
        end
        local msg
        if atTop then
            msg = elderName .. "面露赞许：「你已将本派功法修至极境，他日必成大器。江湖广阔，去闯荡吧。」"
        else
            msg = elderName .. "微微颔首：「将手中功法修至大成，方可传授下一阶。」"
        end
        Server.PushNpcDialog(conn, elderName, msg,
            { { text = "多谢长老指点", action = "leave" } }
        )
        return
    end

    -- 构建学习选项
    local opts = {}
    for _, skillId in ipairs(toGrant) do
        local def = Shared.GetSkillDef(skillId)
        local gradeStr = Settings.SKILL_GRADE_NAME[def and def.grade or 1] or ""
        opts[#opts + 1] = {
            text   = "学习 " .. (def and def.name or skillId) .. "（" .. gradeStr .. "）",
            action = "learn_skill",
            npcId  = npcId,
            data   = skillId,
        }
    end
    opts[#opts + 1] = { text = "改日再来", action = "leave" }

    -- 首次晋升中级（grade 2）时提示将同时获得另一分支
    local firstGradeDef = Shared.GetSkillDef(toGrant[1])
    local extraHint = ""
    if firstGradeDef and firstGradeDef.grade == 2 and cfg then
        -- 找到本门派另一个分支的显示名
        local otherBranchDisplay = nil
        for _, elder in ipairs(cfg.elders) do
            if elder.branch ~= branch then
                local sectInfo = Settings.SECT_INFO and Settings.SECT_INFO[sectId]
                otherBranchDisplay = sectInfo and sectInfo.branches[elder.branch] or elder.branch
                break
            end
        end
        if otherBranchDisplay then
            extraHint = "\n\n（初入中级，老夫将同时赐你" .. otherBranchDisplay .. "入门功法，可双修或出售。）"
        end
    end

    local dialog = elderName .. "目光深邃地注视着你：「你已修成前阶，可传下一式。择你所求，吾为你开悟。」" .. extraHint
    Server.PushNpcDialog(conn, elderName, dialog, opts)
end

-- 装备铺：推送商品列表到客户端
function Server.HandleEquipmentShop(uid, conn, pd)
    Server.PushLog(conn, "老板说：「本店出售各类兵器防具，价格每日浮动！」")
    -- 将波动价格注入商品列表发送给客户端
    local items = {}
    for _, t in ipairs(Settings.EQUIPMENT_SHOP) do
        local copy = {}
        for k, v in pairs(t) do copy[k] = v end
        copy.price = Server.GetFluctuatedPrice(t.id, t.price)
        copy.base_price = t.price
        table.insert(items, copy)
    end
    local data = VariantMap()
    data["ShopType"]  = Variant("equipment")
    data["ShopTitle"] = Variant("装备铺（今日行情）")
    data["Items"]     = Variant(cjson.encode(items))
    data["Currency"]  = Variant("silver")
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_SHOP_DATA, true, data)
end

-- 药铺：推送商品列表到客户端
function Server.HandleMedicineShop(uid, conn, pd)
    -- 先弹出对话让玩家选择买什么
    Server.PushNpcDialog(conn, "药铺老板", "老板笑道：「客官想看点什么？普通药品银两结算，修为丹嘛……那得用灵石。」", {
        { text = "查看药品（银两）", action = "medicine_shop_items", npcId = "medicine_shop" },
        { text = "修为丹（灵石）",   action = "realm_pill_shop",     npcId = "medicine_shop" },
        { text = "告辞",            action = "leave" },
    })
end

function Server.HandleMedicineShopItems(uid, conn, pd)
    Server.PushLog(conn, "药铺老板说：「本店丹药价格随行就市，今日报价如下！」")
    local items = {}
    for _, t in ipairs(Settings.MEDICINE_SHOP) do
        local copy = {}
        for k, v in pairs(t) do copy[k] = v end
        copy.price = Server.GetFluctuatedPrice(t.id, t.price)
        copy.base_price = t.price
        table.insert(items, copy)
    end
    local data = VariantMap()
    data["ShopType"]  = Variant("medicine")
    data["ShopTitle"] = Variant("药铺（今日行情）")
    data["Items"]     = Variant(cjson.encode(items))
    data["Currency"]  = Variant("silver")
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_SHOP_DATA, true, data)
end










-- NPC 商店购买（REQ_SHOP_BUY）
function Server_OnReqShopBuy(eventType, eventData)
    local conn    = eventData["Connection"]:GetPtr("Connection")
    local uid     = Server.GetUidByConn(conn)
    local pd      = players_[uid]
    if not pd then return end

    local shopType = eventData["ShopType"]:GetString()
    local itemId   = eventData["ItemId"]:GetString()

    -- 找到商品模板
    local shopTable = nil
    if shopType == "equipment" then
        shopTable = Settings.EQUIPMENT_SHOP
    elseif shopType == "medicine" then
        shopTable = Settings.MEDICINE_SHOP
    end

    if not shopTable then
        Server.PushLog(conn, "<红>未知商店类型</红>")
        return
    end

    local template = nil
    for _, t in ipairs(shopTable) do
        if t.id == itemId then
            template = t
            break
        end
    end

    if not template then
        Server.PushLog(conn, "<红>商品不存在</红>")
        return
    end

    local price = Server.GetFluctuatedPrice(template.id, template.price)
    -- 扣除银两（原子操作）
    serverCloud.money:Cost(uid, "silver", price, {
        ok = function()
            pd.silver = math.max(0, (pd.silver or 0) - price)
            pd._moneySyncSilver = math.floor(pd.silver)  -- 同步基准值（已调用money:Cost）

            -- 生成物品
            local item = nil
            if shopType == "equipment" then
                item = {
                    type        = "equipment",
                    id          = Shared.GenId(),
                    template_id = template.id,
                    name        = template.name,
                    slot        = template.slot,
                    quality     = template.quality or 1,
                    stats       = template.stats or {},
                    bound       = false,
                }
            elseif shopType == "medicine" then
                if template.type == "pill" then
                    -- 丹药类物品（筑基丹等）
                    item = {
                        type   = "pill",
                        id     = Shared.GenId(),
                        name   = template.name,
                        pill_id = template.id,
                        quality = template.quality or 2,
                        bound  = false,
                    }
                else
                    item = {
                        type   = "medicine",
                        id     = Shared.GenId(),
                        name   = template.name,
                        effect = template.effect or {},
                        bound  = false,
                    }
                end
            end

            if item then
                item.bought_price = price  -- 记录购入价（倒爷系统）
                Server.AddItemToInventory(uid, item, function()
                    Server.PushLog(conn, string.format(
                        "<绿>购买了%s，花费%s，已入背包</绿>",
                        template.name, Shared.FormatSilver(price)
                    ))
                    Server.PushPlayerData(uid, conn)
                end)
            end
        end,
        error = function(code, reason)
            if reason and reason:find("余额不足") then
                Server.PushLog(conn, string.format("<红>银两不足，需要%s</红>", Shared.FormatSilver(price)))
            else
                Server.PushLog(conn, "<红>购买失败：" .. (reason or "未知错误") .. "</红>")
            end
        end
    })
end

-- ============================================================================
-- 战斗
-- ============================================================================

function Server_OnReqStartBattle(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local monsterId = eventData["MonsterId"]:GetString()

    -- 允许战斗的场景：域外战场 + 古村（教程妖兽）
    local allowBattle = (pd.scene == Settings.SCENES.BATTLEFIELD)
        or (pd.scene == Settings.SCENES.ANCIENT_VILLAGE and monsterId == "tutorial_beast")
    if not allowBattle then
        Server.PushLog(conn, "<红>此处没有可以战斗的对手</红>")
        return
    end

    -- 帮会战斗加成
    local gBuff1 = Server.GetGuildBuff(pd)
    pd.guild_combat_bonus = gBuff1 and gBuff1.combat_bonus or 0
    local ok, err = Combat.StartBattle(uid, conn, pd, monsterId)
    if not ok then
        Server.PushLog(conn, "<红>" .. (err or "战斗启动失败") .. "</红>")
        -- 通知客户端退出战斗状态（客户端可能已切换到战斗面板）
        local data = VariantMap()
        data["Win"]           = Variant(false)
        data["Log"]           = Variant(err or "战斗启动失败")
        data["ExpGain"]       = Variant(0)
        data["SilverGain"]    = Variant(0)
        data["LootToken"]     = Variant("")
        data["LootItemName"]  = Variant("")
        conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_BATTLE_END), true, data)
    end
end

function Server_OnReqFleeBattle(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    if not players_[uid] then return end

    local ok, msg, fleeHp = Combat.Flee(uid)
    if ok then
        -- 同步逃跑后的HP
        if fleeHp then
            players_[uid].hp = fleeHp
        end
        -- 逃跑成功：发送 PUSH_BATTLE_END 让客户端退出战斗
        local data = VariantMap()
        data["Win"]           = Variant(true)
        data["Log"]           = Variant("<绿>逃跑成功！</绿>")
        data["ExpGain"]       = Variant(0)
        data["SilverGain"]    = Variant(0)
        data["LootToken"]     = Variant("")
        data["LootItemName"]  = Variant("")
        conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_BATTLE_END), true, data)
        Server.PushPlayerData(uid, conn)
    else
        -- 逃跑失败：推送战斗日志让客户端看到原因
        Server.PushLog(conn, msg)
    end
end

-- 手动选择技能
function Server_OnReqUseSkill(eventType, eventData)
    local conn    = eventData["Connection"]:GetPtr("Connection")
    local uid     = Server.GetUidByConn(conn)
    local pd      = players_[uid]
    if not pd then return end
    local skillId = eventData["SkillId"]:GetString()
    local ok, err = Combat.UseSkill(uid, skillId)
    if not ok and err then
        Server.PushLog(conn, "<红>" .. err .. "</红>")
    else
        -- 技能已排队，立即推送状态让客户端显示"等待中"
        local battle = Combat.GetBattleInfo(uid)
        if battle then Combat.PushBattleState(battle, "", "none") end
    end
end

-- 切换自动/手动战斗
function Server_OnReqToggleAuto(eventType, eventData)
    local conn    = eventData["Connection"]:GetPtr("Connection")
    local uid     = Server.GetUidByConn(conn)
    local pd      = players_[uid]
    if not pd then return end
    -- 等级校验：20级以下禁止开启自动战斗
    if (pd.level or 1) < 20 then
        Server.PushLog(conn, "<红>自动战斗需达到20级方可开启</红>")
        -- 强制回推关闭状态
        Combat.SetAutoFight(uid, false)
        local battle = Combat.GetBattleInfo(uid)
        if battle then Combat.PushBattleState(battle, "") end
        return
    end
    local enabled = eventData["Enabled"]:GetBool()
    Combat.SetAutoFight(uid, enabled)
    local label = enabled and "自动战斗已开启" or "切换为手动战斗"
    Server.PushLog(conn, "<金>" .. label .. "</金>")
    -- 立即推一次状态让客户端刷新
    local battle = Combat.GetBattleInfo(uid)
    if battle then Combat.PushBattleState(battle, "") end
end

-- 配置出战技能槽
function Server_OnReqSetBattleSlots(eventType, eventData)
    local conn    = eventData["Connection"]:GetPtr("Connection")
    local uid     = Server.GetUidByConn(conn)
    local pd      = players_[uid]
    if not pd then return end
    if Combat.IsInBattle(uid) then
        Server.PushLog(conn, "<红>战斗中无法调整技能槽</红>")
        return
    end
    local json    = eventData["Slots"]:GetString()
    local ok, slots = pcall(cjson.decode, json)
    if not ok or type(slots) ~= "table" then
        Server.PushLog(conn, "<红>技能槽数据异常</红>")
        return
    end
    -- 最多 BATTLE_SKILL_SLOTS 个，且必须是玩家已学的技能
    local valid = {}
    for _, skillId in ipairs(slots) do
        if #valid >= Settings.BATTLE_SKILL_SLOTS then break end
        local def = Shared.GetSkillDef(skillId)
        if def and def.battle_type ~= "normal" then
            -- 确认玩家已学该技能（兼容 sk.id 和 sk.skill_id）
            for _, sk in ipairs(pd.skills or {}) do
                if sk.id == skillId or sk.skill_id == skillId then
                    valid[#valid + 1] = skillId
                    break
                end
            end
        end
    end
    pd.battle_slots = valid
    Server.SavePlayerData(uid, pd)
    Server.PushLog(conn, string.format("<绿>出战技能槽已更新，共%d个技能</绿>", #valid))
    Server.PushPlayerData(uid, conn)
end

function Server_OnReqUseItem(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local itemId = eventData["ItemId"]:GetString()
    print("[UseItem] uid=" .. tostring(uid) .. " itemId=" .. tostring(itemId))
    local item = Server.FindInventoryItem(pd, itemId)
    if not item then
        print("[UseItem] ITEM NOT FOUND in inventory! id=" .. itemId)
        Server.PushLog(conn, "<红>背包中没有这件物品</红>")
        return
    end
    print("[UseItem] Found: " .. item.name .. " type=" .. tostring(item.type) .. " hp=" .. tostring(pd.hp))

    if item.type ~= "medicine" then
        Server.PushLog(conn, "<红>这不是药品</红>")
        return
    end

    -- 计算回复量（兼容 heal_hp 和 effect.hp 两种格式）
    local healHp = item.heal_hp or (item.effect and item.effect.hp) or 0

    -- 判断是否在战斗中
    if Combat.IsInBattle(uid) then
        -- 战斗中使用（走 Combat 逻辑，含冷却）
        local ok, msg = Combat.UseItem(uid, item)
        Server.PushLog(conn, ok and ("<绿>" .. msg .. "</绿>") or ("<红>" .. msg .. "</红>"))
        if ok then
            Server.RemoveInventoryItemAsync(uid, itemId, function()
                Server.PushInventory(uid, conn)
                Server.PushPlayerData(uid, conn)
            end)
        end
    else
        -- 非战斗使用药品
        local maxHp = Shared.CalcStats(pd).hp
        -- pd.hp 为 nil 表示从未受过伤，视为满血
        local curHp = pd.hp or maxHp
        print(string.format("[UseItem] 非战斗用药: maxHp=%d curHp=%d pd.hp=%s healHp=%d",
            maxHp, curHp, tostring(pd.hp), healHp))

        if curHp >= maxHp then
            Server.PushLog(conn, "<黄>血量已满，无需服药</黄>")
            Server.PushInventory(uid, conn)  -- 触发客户端解锁操作按钮
            return
        end

        -- 回复血量
        local oldHp = curHp
        pd.hp = math.min(maxHp, curHp + healHp)
        local healed = pd.hp - oldHp

        -- 消耗物品（count > 1 则减数量，否则移除）
        if item.count and item.count > 1 then
            item.count = item.count - 1
            Server.PushLog(conn, string.format("<绿>服用%s，恢复%d点气血（剩余%d个）</绿>", item.name, healed, item.count))
            Server.PushInventory(uid, conn)
            Server.PushPlayerData(uid, conn)
        else
            Server.RemoveInventoryItemAsync(uid, itemId, function()
                Server.PushLog(conn, string.format("<绿>服用%s，恢复%d点气血</绿>", item.name, healed))
                Server.PushInventory(uid, conn)
                Server.PushPlayerData(uid, conn)
            end)
        end
    end
end

-- ============================================================================
-- 修炼
-- ============================================================================

function Server_OnReqCultivate(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    if Combat.IsInBattle(uid) then
        Server.PushLog(conn, "<红>战斗中无法修炼</红>")
        return
    end

    local skillId = eventData["SkillId"]:GetString()
    local budget = eventData["Budget"]:GetInt()

    -- 即时修炼：一次性消耗 budget 潜能，立刻获得熟练度
    local ok, msg = Cultivation.InstantCultivate(pd, skillId, budget, Settings.CULTIVATE_COST_MULT.SELF)
    Server.PushLog(conn, ok and ("<绿>" .. msg .. "</绿>") or ("<红>" .. msg .. "</红>"))
    if ok then
        Quest.OnStartCultivate(pd, conn)
        Server.AdvanceGuildDaily(uid, "cultivate", 1)
        Activity.OnCultivateTime(pd, 1)  -- 计活跃度（按次数）
        Server.PushPlayerData(uid, conn)
    end
end


-- 灵石加速修炼（消耗灵石开启2倍速打坐）
function Server_OnReqCultivateBoost(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    if Combat.IsInBattle(uid) then
        Server.PushLog(conn, "<红>战斗中无法修炼</红>")
        return
    end

    local cost = Settings.SPIRIT_STONE.CULTIVATE_BOOST_COST
    if (pd.spirit_stone or 0) < cost then
        Server.PushLog(conn, string.format("<红>灵石不足，加速修炼需要%d灵石。</红>", cost))
        return
    end

    local skillId = eventData["SkillId"]:GetString()
    local ok, msg = Cultivation.StartCultivate(pd, skillId, Settings.CULTIVATE_COST_MULT.SELF)
    if ok then
        -- 扣除灵石，设置加速倍率
        pd.spirit_stone = (pd.spirit_stone or 0) - cost
        pd.spirit_stone_boost = Settings.SPIRIT_STONE.CULTIVATE_BOOST_MULT
        Server.PushLog(conn, string.format("<金>消耗%d灵石，开启%d倍加速修炼！</金>", cost, Settings.SPIRIT_STONE.CULTIVATE_BOOST_MULT))
        Quest.OnStartCultivate(pd, conn)
        Server.AdvanceGuildDaily(uid, "cultivate", 1)
        Server.PushPlayerData(uid, conn)
        Server.SavePlayerData(uid)
    else
        Server.PushLog(conn, "<红>" .. msg .. "</红>")
    end
end
function Server_OnReqStopCultivate(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local ok, msg = Cultivation.StopCultivate(pd)
    Server.PushLog(conn, ok and msg or ("<红>" .. msg .. "</红>"))
    if ok then Server.PushPlayerData(uid, conn) end
end

function Server_OnReqUnbindSkill(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local skillId = eventData["SkillId"]:GetString()
    local ok, item, msg = Cultivation.UnbindSkill(pd, skillId)
    Server.PushLog(conn, ok and ("<黄>" .. msg .. "</黄>") or ("<红>" .. msg .. "</红>"))
    if ok and item then
        Server.AddItemToInventory(uid, item, function()
            Server.PushPlayerData(uid, conn)
        end)
    end
end

-- ============================================================================
-- 装备
-- ============================================================================

function Server_OnReqEquipItem(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local itemId = eventData["ItemId"]:GetString()
    local item = Server.FindInventoryItem(pd, itemId)
    if not item or item.type ~= "equipment" then
        Server.PushLog(conn, "<红>背包中没有这件装备</红>")
        return
    end

    pd.equipment = pd.equipment or {}
    -- 卸下原有装备（回背包）
    local old = pd.equipment[item.slot]

    -- 先异步删除背包中的新装备
    Server.RemoveInventoryItemAsync(uid, itemId, function(removeOk, removedItem)
        if not removeOk or not removedItem then
            Server.PushLog(conn, "<红>装备失败：物品不在背包中</红>")
            return
        end
        pd.equipment[removedItem.slot] = removedItem
        -- 旧装备放回背包
        if old then
            Server.AddItemToInventory(uid, old, function()
                Server.PushLog(conn, string.format(
                    "<绿>装备了%s，卸下%s（已放入背包）</绿>",
                    removedItem.name, old.name
                ))
                Quest.OnEquipItem(pd, conn)
                Server.PushPlayerData(uid, conn)
                Server.PushInventory(uid, conn)
            end)
        else
            Server.PushLog(conn, string.format("<绿>装备了%s</绿>", removedItem.name))
            Quest.OnEquipItem(pd, conn)
            Server.PushPlayerData(uid, conn)
            Server.PushInventory(uid, conn)
        end
    end)
end

function Server_OnReqUnequipItem(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local slot = eventData["Slot"]:GetString()
    pd.equipment = pd.equipment or {}
    local item = pd.equipment[slot]
    if not item then
        Server.PushLog(conn, "<红>该部位没有装备</红>")
        return
    end

    pd.equipment[slot] = nil
    Server.AddItemToInventory(uid, item, function()
        Server.PushLog(conn, string.format("卸下了%s", item.name))
        Server.PushPlayerData(uid, conn)
        Server.PushInventory(uid, conn)
    end)
end

-- ============================================================================
-- 背包增强：一键最强装备
-- ============================================================================
local QUALITY_ORDER = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5, divine = 6 }

local function CalcEquipPower(item)
    if not item or not item.stats then return 0 end
    local s = item.stats
    return (s.atk or 0) * 2 + (s.def or 0) * 1.5 + (s.hp or 0) * 0.5 + (s.agi or 0) * 1
end

function Server_OnReqAutoEquipBest(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    pd.equipment = pd.equipment or {}
    pd.inventory = pd.inventory or {}

    -- 对每个槽位，找背包中战力最高的装备与当前已装备比较
    local changes = {}
    for _, slotId in ipairs(Settings.EQUIPMENT_SLOTS) do
        local bestItem = nil
        local bestPower = 0
        -- 扫描背包找该槽位最强
        for i, item in ipairs(pd.inventory) do
            if item.type == "equipment" and item.slot == slotId then
                local power = CalcEquipPower(item)
                if power > bestPower then
                    bestPower = power
                    bestItem = item
                end
            end
        end
        -- 与当前装备比较
        local curPower = CalcEquipPower(pd.equipment[slotId])
        if bestItem and bestPower > curPower then
            changes[#changes + 1] = { slot = slotId, newItem = bestItem }
        end
    end

    if #changes == 0 then
        Server.PushLog(conn, "当前装备已是最强配置，无需更换。")
        return
    end

    -- 执行换装
    local msgs = {}
    for _, ch in ipairs(changes) do
        local oldItem = pd.equipment[ch.slot]
        -- 从背包移除新装备
        for i, item in ipairs(pd.inventory) do
            if item == ch.newItem then
                table.remove(pd.inventory, i)
                break
            end
        end
        -- 穿上新装备
        pd.equipment[ch.slot] = ch.newItem
        -- 旧装备放回背包
        if oldItem then
            table.insert(pd.inventory, oldItem)
        end
        msgs[#msgs + 1] = (Settings.EQUIPMENT_SLOT_NAME[ch.slot] or ch.slot) .. "→" .. ch.newItem.name
    end

    Server.SavePlayerData(uid, pd)
    Server.PushPlayerData(uid, conn)
    Server.PushInventory(uid, conn)
    Server.PushLog(conn, string.format("<绿>一键装备完成（%d件）：%s</绿>", #changes, table.concat(msgs, "、")))
end

-- ============================================================================
-- 背包增强：出售物品换银两
-- ============================================================================
local SELL_BASE_PRICE = { [1] = 30, [2] = 80, [3] = 200, [4] = 500, [5] = 1200, [6] = 3000, [7] = 8000 }
local QUALITY_SELL_MULT = { common = 1.0, uncommon = 1.5, rare = 2.5, epic = 4.0, legendary = 7.0, divine = 12.0 }

local function CalcSellPrice(item)
    if not item then return 0 end
    local itemType = item.type or item.item_type
    if itemType == "equipment" then
        local tier = item.tier or 1
        local base = SELL_BASE_PRICE[tier] or 30
        local mult = QUALITY_SELL_MULT[item.quality] or 1.0
        return math.floor(base * mult)
    elseif itemType == "medicine" then
        for _, def in ipairs(Settings.MEDICINE_SHOP) do
            if def.id == item.id then
                return math.floor((def.price or 20) * 0.5)
            end
        end
        return 10
    elseif itemType == "material" then
        local def = Settings.ALCHEMY_MATERIALS[item.id]
        if def then return math.floor((def.price or 10) * 0.4 * (item.count or 1)) end
        return 5
    end
    return 10
end

function Server_OnReqSellItem(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local itemId = eventData["ItemId"]:GetString()
    local item = Server.FindInventoryItem(pd, itemId)
    if not item then
        Server.PushLog(conn, "<红>背包中没有这件物品</红>")
        return
    end

    local sellPrice = CalcSellPrice(item)
    local itemName = item.name or (Settings.ALCHEMY_MATERIALS[item.id] and Settings.ALCHEMY_MATERIALS[item.id].name) or "未知物品"

    Server.RemoveInventoryItemAsync(uid, itemId, function(ok)
        if ok then
            pd.silver = (pd.silver or 0) + sellPrice
            Server.SavePlayerData(uid, pd)
            Server.PushPlayerData(uid, conn)
            Server.PushInventory(uid, conn)
            Server.PushLog(conn, string.format("<绿>出售%s，获得%d银两</绿>", itemName, sellPrice))
        else
            Server.PushLog(conn, "<红>出售失败</红>")
        end
    end)
end

-- ============================================================================
-- 背包增强：批量出售
-- ============================================================================
function Server_OnReqBatchSell(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local idsJson = eventData["ItemIds"]:GetString()
    local ok2, ids = pcall(cjson.decode, idsJson)
    if not ok2 or type(ids) ~= "table" or #ids == 0 then
        Server.PushLog(conn, "<红>批量出售参数错误</红>")
        return
    end

    pd.inventory = pd.inventory or {}
    local totalSilver = 0
    local soldCount = 0

    -- 标记需要删除的索引
    local toRemove = {}
    for _, targetId in ipairs(ids) do
        for i, item in ipairs(pd.inventory) do
            if tostring(item.id) == tostring(targetId) or tostring(item._list_id) == tostring(targetId) then
                if not toRemove[i] then
                    toRemove[i] = true
                    totalSilver = totalSilver + CalcSellPrice(item)
                    soldCount = soldCount + 1
                end
                break
            end
        end
    end

    -- 按索引从大到小删除
    local indices = {}
    for i in pairs(toRemove) do indices[#indices + 1] = i end
    table.sort(indices, function(a, b) return a > b end)
    for _, i in ipairs(indices) do
        table.remove(pd.inventory, i)
    end

    if soldCount > 0 then
        pd.silver = (pd.silver or 0) + totalSilver
        Server.SavePlayerData(uid, pd)
        Server.PushPlayerData(uid, conn)
        Server.PushInventory(uid, conn)
        Server.PushLog(conn, string.format("<绿>批量出售%d件物品，共获得%d银两</绿>", soldCount, totalSilver))
    else
        Server.PushLog(conn, "没有可出售的物品。")
    end
end

function Server_OnReqDiscardItem(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local itemId = eventData["ItemId"]:GetString()
    local item = Server.FindInventoryItem(pd, itemId)
    if not item then
        Server.PushLog(conn, "<红>背包中没有这件物品</红>")
        return
    end

    local itemName = item.name or "未知物品"
    Server.RemoveInventoryItemAsync(uid, itemId, function(ok)
        if ok then
            Server.PushLog(conn, string.format("丢弃了%s", itemName))
            Server.PushInventory(uid, conn)
        else
            Server.PushLog(conn, "<红>丢弃失败</红>")
        end
    end)
end

-- ============================================================================
-- 交易阁
-- ============================================================================

function Server_OnReqMarketList(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local filterType    = eventData["FilterType"]:GetString()
    local filterQuality = eventData["FilterQuality"]:GetString()
    local sortBy        = eventData["SortBy"]:GetString()
    local page          = eventData["Page"]:GetInt()

    local function sendResponse(listings, total)
        local data = VariantMap()
        data["listings_json"] = Variant(cjson.encode(listings or {}))
        data["total_pages"]   = Variant(math.ceil((total or 0) / 20))
        data["page"]          = Variant(page)
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_MARKET_DATA, true, data)
    end

    -- "mine"：查询当前玩家自己上架的商品（用 GetMyListings 而非 GetListings）
    if filterType == "mine" then
        local uid = Server.GetUidByConn(conn)
        if not uid then sendResponse({}, 0) return end
        Market.GetMyListings(uid, function(ok, allListings)
            local filtered = {}
            for _, item in ipairs(allListings or {}) do
                local qualOk = true
                if filterQuality and filterQuality ~= "all" and filterQuality ~= "" then
                    local fq = tonumber(filterQuality)
                    qualOk = (fq ~= nil and item.item and item.item.quality == fq)
                end
                if qualOk then
                    filtered[#filtered + 1] = item
                end
            end
            -- 排序
            if sortBy == "price_asc" then
                table.sort(filtered, function(a, b) return a.price < b.price end)
            elseif sortBy == "price_desc" then
                table.sort(filtered, function(a, b) return a.price > b.price end)
            else
                table.sort(filtered, function(a, b) return (a.listed_at or 0) > (b.listed_at or 0) end)
            end
            -- 分页
            local total = #filtered
            local pageSize = 20
            local startIdx = (page - 1) * pageSize + 1
            local endIdx = math.min(startIdx + pageSize - 1, total)
            local pageData = {}
            for i = startIdx, endIdx do
                pageData[#pageData + 1] = filtered[i]
            end
            sendResponse(pageData, total)
        end)
    else
        Market.GetListings(filterType, filterQuality, sortBy, page, 20, function(ok, listings, total)
            sendResponse(listings or {}, total or 0)
        end)
    end
end

function Server_OnReqMarketBuy(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local listingIdStr = eventData["ListingId"]:GetString()
    local listingId = tonumber(listingIdStr)
    print("[Market][Buy] 收到购买请求 raw_str=" .. tostring(listingIdStr) .. " parsed_num=" .. tostring(listingId))
    if not listingId then Server.PushLog(conn, "<红>无效商品ID</红>") return end

    -- 先查询listing确认数据
    serverCloud.list:GetById(listingId, {
        ok = function(items)
            print("[Market][Buy] GetById 返回 " .. #items .. " 条结果, listingId=" .. tostring(listingId))
            if #items == 0 then
                Server.PushLog(conn, "<红>商品已下架或被他人购买</红>")
                return
            end
            local listing = items[1].value

            -- 倒爷系统：记录卖家原始成本 & 买家购入价
            local sellerCost = listing.item.bought_price or 0
            listing.item.bought_price = listing.price  -- 买家的购入成本
            local sellerTraderLevel = listing.seller_trader_level or 0
            local taxDiscount = Server.GetTraderTaxDiscount(sellerTraderLevel)
            Market.BuyItem(uid, pd.name, listingId,
                listing.seller_uid, listing.seller_name,
                listing.item, listing.price, "spirit_stone",
                function(buyOk, item, msg)
                    if buyOk and item then
                        -- 扣除买家灵石
                        pd.spirit_stone = math.max(0, (pd.spirit_stone or 0) - listing.price)
                        -- 银两商品：加银两到买家余额；普通物品：加入背包
                        if item.type == "currency" and item.silver_amount then
                            pd.silver = (pd.silver or 0) + item.silver_amount
                            Server.SavePlayerData(uid, pd)
                        else
                            -- 物品已在 BatchCommit 内原子写入云端库存
                            pd.inventory = pd.inventory or {}
                            table.insert(pd.inventory, item)
                            Server.PushInventory(uid, conn)
                            -- 持久化 player_data（确保 spirit_stone 等字段同步保存）
                            Server.SavePlayerData(uid, pd)
                        end
                        Server.PushLog(conn, "<绿>" .. msg .. "</绿>")
                        Server.PushPlayerData(uid, conn)
                        -- 活动系统：卖家成交（如果在线则更新）
                        local sellerPd = players_[listing.seller_uid]
                        if sellerPd then
                            Activity.OnMarketSell(sellerPd)
                        end
                        -- 倒爷系统：计算卖家利润并累加
                        Server.AddTradeProfit(listing.seller_uid, listing.price, sellerCost, sellerTraderLevel, "spirit_stone")
                    else
                        Server.PushLog(conn, "<红>" .. msg .. "</红>")
                    end
                end,
                taxDiscount
            )
        end,
        error = function()
            Server.PushLog(conn, "<红>查询失败，请重试</红>")
        end
    })
end

function Server_OnReqMarketSell(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local itemId   = eventData["ItemId"]:GetString()
    local price    = eventData["Price"]:GetInt()
    -- 统一使用灵石交易
    local currency = "spirit_stone"

    -- 找到背包中的物品
    local item = Server.FindInventoryItem(pd, itemId)
    if not item then
        Server.PushLog(conn, "<红>背包中没有这件物品</红>")
        return
    end
    if item.bound then
        Server.PushLog(conn, "<红>绑定物品无法上架，请先解绑</红>")
        return
    end

    -- 异步从背包移除后再上架，防止物品丢失
    Server.RemoveInventoryItemAsync(uid, itemId, function(removeOk, removedItem)
        if not removeOk or not removedItem then
            Server.PushLog(conn, "<红>背包中没有该物品</红>")
            return
        end

        local now = os.time()
        local listing = {
            seller_uid  = uid,
            seller_name = pd.name or "侠客",
            seller_trader_level = pd.trader_level or 0,
            item        = removedItem,
            price       = price,
            currency    = currency,
            listed_at   = now,
            expires_at  = now + Settings.ECONOMY.MARKET_DURATION,
        }
        serverCloud.list:Add(Market.ADMIN_UID, "market_listings", listing, {
            ok = function(listId)
                Server.PushLog(conn, string.format("<绿>%s已上架，售价%d💎（7天有效）</绿>",
                    removedItem.name, price))
                Server.PushPlayerData(uid, conn)
            end,
            error = function(code, reason)
                -- 上架失败，退回物品（异步）
                Server.AddItemToInventory(uid, removedItem)
                Server.PushLog(conn, "<红>上架失败：" .. (reason or "未知错误") .. "</红>")
            end
        })
    end)
end

-- ═══ 上架银两作为商品（灵石标价） ═══
-- [已移除] 银两寄售功能已下架
function Server_OnReqMarketSellSilver(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    Server.PushLog(conn, "<红>银两寄售功能已关闭</红>")
end

function Server_OnReqMarketCancel(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local listingId = tonumber(eventData["ListingId"]:GetString())
    if not listingId then Server.PushLog(conn, "<红>无效商品ID</红>") return end
    Market.CancelListing(uid, listingId, function(ok, item)
        if ok and item then
            -- 银两商品：退回银两余额；普通物品：退回背包
            if item.type == "currency" and item.silver_amount then
                pd.silver = (pd.silver or 0) + item.silver_amount
                Server.SavePlayerData(uid, pd)
                Server.PushLog(conn, string.format("<绿>%d银两已下架并退回</绿>", item.silver_amount))
                Server.PushPlayerData(uid, conn)
            else
                Server.AddItemToInventory(uid, item, function()
                    Server.PushLog(conn, string.format("<绿>%s已下架并退回背包</绿>", item.name))
                    Server.PushPlayerData(uid, conn)
                    Server.PushInventory(uid, conn)
                end)
            end
        else
            Server.PushLog(conn, "<红>下架失败</红>")
        end
    end)
end

-- 查询玩家自己的交易记录
function Server_OnReqMarketHistory(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    if not players_[uid] then return end

    Market.GetHistory(uid, function(ok, records)
        local data = VariantMap()
        data["history_json"] = Variant(ok and cjson.encode(records) or "[]")
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_MARKET_HISTORY, true, data)
    end)
end


function Server_OnReqMarketTrends(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    print("[Server] 收到行情请求, 直接返回")
    -- 先尝试直接返回空结果以测试通信链路
    local data = VariantMap()
    data["trends_json"] = Variant("[]")
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_MARKET_TRENDS, true, data)
    -- 再异步获取真实数据
    Market.GetMarketTrends(function(ok, trends)
        print("[Server] 行情回调: ok=" .. tostring(ok) .. " count=" .. #trends)
        local data2 = VariantMap()
        data2["trends_json"] = Variant(ok and cjson.encode(trends) or "[]")
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_MARKET_TRENDS, true, data2)
    end)
end

-- ============================================================================
-- NPC自动补货（器丹宗丹药阁自动上架交易阁）
-- ============================================================================
function Server.NpcRestockMarket()
    local cfg = Settings.ECONOMY.NPC_AUTO_LISTINGS
    if not cfg or not cfg.ENABLED then
        npcRestockRunning_ = false
        return
    end

    -- 获取当前市场中NPC的所有上架物品
    serverCloud.list:Get(Market.ADMIN_UID, "market_listings", {
        ok = function(list)
            local now = os.time()
            -- 统计NPC（器丹宗·丹药阁）当前在架的各丹药数量
            local npcStock = {}
            for _, entry in ipairs(list) do
                local listing = entry.value
                if listing.seller_name == cfg.SELLER_NAME
                    and listing.expires_at and listing.expires_at > now then
                    local itemId = listing.item and listing.item.id
                    if itemId then
                        npcStock[itemId] = (npcStock[itemId] or 0) + 1
                    end
                end
            end

            -- 逐个检查需要补货的丹药
            for _, itemCfg in ipairs(cfg.ITEMS) do
                local currentCount = npcStock[itemCfg.pill_id] or 0
                local needCount = itemCfg.max_stock - currentCount
                for _ = 1, needCount do
                    local pillDef = Settings.PILLS[itemCfg.pill_id]
                    local item = {
                        id      = itemCfg.pill_id,
                        name    = itemCfg.name or (pillDef and pillDef.name) or itemCfg.pill_id,
                        type    = "pill",
                        quality = itemCfg.quality or (pillDef and pillDef.quality) or 2,
                        desc    = pillDef and pillDef.desc or "",
                    }
                    Market.AdminListItem(cfg.SELLER_NAME, item, itemCfg.price, function() end)
                end
                if needCount > 0 then
                    print(string.format("[NPC补货] %s 补充 %d 个到交易阁", itemCfg.name, needCount))
                end
            end

            npcRestockRunning_ = false
        end,
        error = function()
            npcRestockRunning_ = false
        end
    })
end

-- ============================================================================
-- 管理员
-- ============================================================================

function Server_OnReqAdminLogin(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local code = eventData["Code"]:GetString()
    local data = VariantMap()
    if code == Settings.ECONOMY.ADMIN_CODE then
        pd.is_admin = true
        data["Success"] = Variant(true)
        Server.PushLog(conn, "<绿>管理员权限已激活！</绿>")
        Server.SavePlayerData(uid, pd)
        Server.PushPlayerData(uid, conn)
    else
        data["Success"] = Variant(false)
        Server.PushLog(conn, "<红>激活码错误</红>")
    end
    conn:SendRemoteEvent(Settings.EVENTS.ADMIN_LOGIN_RESULT, true, data)
end

function Server_OnReqAdminSell(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "<红>权限不足</红>")
        return
    end

    local itemJson = eventData["Item"]:GetString()
    local price    = eventData["Price"]:GetInt()
    local ok2, item = pcall(cjson.decode, itemJson)
    if not ok2 or not item then
        Server.PushLog(conn, "<红>物品数据解析失败</红>")
        return
    end

    item.id = Shared.GenId()
    item.bound = false

    Market.AdminListItem(pd.name or "神秘商人", item, price, function(ok, result)
        if ok then
            Server.PushLog(conn, string.format("<绿>管理员上架成功：%s，售价%s</绿>",
                item.name, Shared.FormatSilver(price)))
        else
            Server.PushLog(conn, "<红>" .. tostring(result) .. "</红>")
        end
    end)
end

-- ── 管理员：修改传闻 ─────────────────────────────────────────────────────────
function Server_OnAdminSetNews(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    local pd   = players_[uid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "<红>权限不足</红>")
        return
    end

    local text = eventData["Text"]:GetString()
    if not text or text == "" then return end

    systemNews_ = text

    -- 持久化到云端（Get+Modify 模式，避免无限追加）
    serverCloud.list:Get(0, "system_news", {
        ok = function(list)
            if list and #list > 0 then
                serverCloud.list:Modify(list[#list].list_id, { text = text }, {
                    ok = function() print("[Server] 传闻已持久化（Modify）") end,
                    error = function(c, r) print("[Server] 传闻保存失败:", c, r) end,
                })
            else
                serverCloud.list:Add(0, "system_news", { text = text }, {
                    ok = function() print("[Server] 传闻首次写入完成") end,
                    error = function(c, r) print("[Server] 传闻写入失败:", c, r) end,
                })
            end
        end,
        error = function(c, r) print("[Server] 传闻查询失败:", c, r) end,
    })

    -- 广播给所有在线玩家
    local newsData = VariantMap()
    newsData["Text"] = Variant(text)
    for _, c in pairs(connections_) do
        if c and c:IsConnected() then
            c:SendRemoteEvent(Settings.EVENTS.PUSH_NEWS_UPDATE, true, newsData)
        end
    end

    -- 回复操作结果
    local result = VariantMap()
    result["Ok"]  = Variant(true)
    result["Msg"] = Variant("传闻已更新并广播给所有在线玩家")
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_ADMIN_RESULT, true, result)
    print("[Server] 管理员更新传闻：" .. text)
end

-- ── 管理员：查询玩家数据 ──────────────────────────────────────────────────────
function Server_OnAdminQueryPlayer(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    local pd   = players_[uid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "<红>权限不足</红>")
        return
    end

    local targetName = eventData["Name"]:GetString()

    local function sendInfo(info)
        local data = VariantMap()
        data["info_json"] = Variant(cjson.encode(info))
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_ADMIN_PLAYER_INFO, true, data)
    end

    -- 先在在线玩家里找
    local targetUid, targetPd = nil, nil
    for u, p in pairs(players_) do
        if p.name == targetName then
            targetUid, targetPd = u, p
            break
        end
    end

    if targetPd then
        local stats = Shared.CalcStats(targetPd)
        sendInfo({
            uid          = targetUid,
            name         = targetPd.name,
            level        = targetPd.level or 1,
            silver       = targetPd.silver or 0,
            spirit_stone = targetPd.spirit_stone or 0,
            potential    = targetPd.potential or 0,
            hp_base      = stats and stats.hp_base or 0,
            scene        = targetPd.scene or "?",
            online       = true,
            realm        = targetPd.realm or 1,
            realm_layer  = targetPd.realm_layer or 1,
            realm_exp    = targetPd.realm_exp or 0,
            skills       = targetPd.skills or {},
            inventory    = targetPd.inventory or {},
            debug_flags  = targetPd.debug_flags or {},
        })
        return
    end

    -- 查离线玩家（通过名册找 uid，再从云端加载）
    local offlineUid = playerRegistry_[targetName]
    if not offlineUid then
        sendInfo({ error = "未找到玩家「" .. targetName .. "」，该玩家可能从未登录过" })
        return
    end

    serverCloud:BatchGet(offlineUid)
        :Key("player_data")
        :Fetch({
            ok = function(scores)
                local opd = scores.player_data
                if not opd then
                    sendInfo({ error = "云端无该玩家存档" })
                    return
                end
                serverCloud.money:Get(offlineUid, {
                    ok = function(moneys)
                        sendInfo({
                            uid          = offlineUid,
                            name         = opd.name or targetName,
                            level        = opd.level or 1,
                            silver       = moneys.silver or 0,
                            spirit_stone = moneys.spirit_stone or 0,
                            scene        = opd.scene or "?",
                            online       = false,
                            realm        = opd.realm or 1,
                            realm_layer  = opd.realm_layer or 1,
                            realm_exp    = opd.realm_exp or 0,
                            skills       = opd.skills or {},
                        })
                    end,
                    error = function()
                        sendInfo({
                            uid    = offlineUid,
                            name   = opd.name or targetName,
                            level  = opd.level or 1,
                            silver = 0, spirit_stone = 0,
                            scene  = opd.scene or "?",
                            online = false,
                            realm        = opd.realm or 1,
                            realm_layer  = opd.realm_layer or 1,
                            realm_exp    = opd.realm_exp or 0,
                            skills       = opd.skills or {},
                        })
                    end
                })
            end,
            error = function()
                sendInfo({ error = "云端查询失败，请稍后重试" })
            end
        })
end

-- ── 管理员：给玩家添加货币 ────────────────────────────────────────────────────
function Server_OnAdminAddCurrency(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    local pd   = players_[uid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "<红>权限不足</红>")
        return
    end

    local targetName   = eventData["Name"]:GetString()
    local currency     = eventData["Currency"]:GetString()  -- "silver" | "spirit_stone"
    local amount       = eventData["Amount"]:GetInt()
    local currencyLabel = currency == "spirit_stone" and "灵石" or "银两"

    if amount <= 0 then return end

    local function sendResult(ok, msg)
        local result = VariantMap()
        result["Ok"]  = Variant(ok)
        result["Msg"] = Variant(msg)
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_ADMIN_RESULT, true, result)
    end

    -- 查找目标玩家
    local targetUid, targetPd = nil, nil
    for u, p in pairs(players_) do
        if p.name == targetName then
            targetUid, targetPd = u, p
            break
        end
    end

    if targetPd then
        -- 在线：修改内存 + 云端
        if currency == "spirit_stone" then
            targetPd.spirit_stone = (targetPd.spirit_stone or 0) + amount
            targetPd._moneySyncStone = math.floor(targetPd.spirit_stone)
        else
            targetPd.silver = (targetPd.silver or 0) + amount
            targetPd._moneySyncSilver = math.floor(targetPd.silver)
        end
        serverCloud.money:Add(targetUid, currency, amount)

        -- 通知目标玩家刷新数据
        local targetConn = connections_[targetUid]
        if targetConn then
            Server.PushPlayerData(targetUid, targetConn)
            Server.PushLog(targetConn, string.format(
                "<金>管理员赠予你 %d %s</金>", amount, currencyLabel))
        end
        sendResult(true, string.format("已向【%s】（在线）添加 %d %s", targetName, amount, currencyLabel))
        return
    end

    -- 离线：仅修改云端
    local offlineUid = playerRegistry_[targetName]
    if not offlineUid then
        sendResult(false, "未找到玩家「" .. targetName .. "」")
        return
    end

    serverCloud.money:Add(offlineUid, currency, amount, {
        ok    = function()
            sendResult(true, string.format("已向【%s】（离线）添加 %d %s，下次登录生效", targetName, amount, currencyLabel))
        end,
        error = function()
            sendResult(false, "云端操作失败，请重试")
        end
    })
end

-- ── 管理员：修改玩家属性 ────────────────────────────────────────────────────────
function Server_OnAdminModifyPlayer(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    local pd   = players_[uid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "<红>权限不足</红>")
        return
    end

    local targetUid = eventData["TargetUid"]:GetString()
    local field     = eventData["Field"]:GetString()   -- "realm"|"realm_layer"|"silver"|"spirit_stone"|"skill_level"
    local value     = eventData["Value"]:GetInt()
    local extra     = eventData["Extra"]:GetString()   -- skill_level 时为 skillId

    local function sendResult(ok, msg)
        local result = VariantMap()
        result["Ok"]  = Variant(ok)
        result["Msg"] = Variant(msg)
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_ADMIN_RESULT, true, result)
    end

    -- 查找在线玩家
    local targetPd = nil
    local isOnline = false
    for u, p in pairs(players_) do
        if tostring(u) == targetUid then
            targetPd = p
            targetUid = u
            isOnline = true
            break
        end
    end

    -- 应用修改到 player_data 的核心逻辑（在线/离线共用）
    local function applyModification(tPd, tUid, tName, online)
        if field == "realm" then
            if value < 1 then value = 1 end
            tPd.realm = value
            tPd.level = Settings.REALM.CalcPowerLevel(tPd.realm, tPd.realm_layer or 1)
            sendResult(true, string.format("已将【%s】（%s）境界修改为 %d", tName, online and "在线" or "离线", value))
        elseif field == "realm_layer" then
            if value < 1 then value = 1 end
            tPd.realm_layer = value
            tPd.level = Settings.REALM.CalcPowerLevel(tPd.realm or 1, tPd.realm_layer)
            sendResult(true, string.format("已将【%s】（%s）境界层修改为 %d", tName, online and "在线" or "离线", value))
        elseif field == "silver" then
            local delta = value - (tPd.silver or 0)
            tPd.silver = value
            tPd._moneySyncSilver = math.floor(tPd.silver)
            if delta ~= 0 then serverCloud.money:Add(tUid, "silver", delta) end
            sendResult(true, string.format("已将【%s】（%s）银两设置为 %d", tName, online and "在线" or "离线", value))
        elseif field == "spirit_stone" then
            local delta = value - (tPd.spirit_stone or 0)
            tPd.spirit_stone = value
            tPd._moneySyncStone = math.floor(tPd.spirit_stone)
            if delta ~= 0 then serverCloud.money:Add(tUid, "spirit_stone", delta) end
            sendResult(true, string.format("已将【%s】（%s）灵石设置为 %d", tName, online and "在线" or "离线", value))
        elseif field == "potential" then
            if value < 0 then value = 0 end
            tPd.potential = value
            sendResult(true, string.format("已将【%s】（%s）潜能设置为 %d", tName, online and "在线" or "离线", value))
        elseif field == "skill_level" then
            local skillId = extra
            if skillId == "" then
                sendResult(false, "未指定功法ID")
                return
            end
            local found = false
            for _, sk in ipairs(tPd.skills or {}) do
                if sk.id == skillId then
                    sk.level = value
                    found = true
                    break
                end
            end
            if found then
                sendResult(true, string.format("已将【%s】（%s）功法 %s 等级修改为 %d", tName, online and "在线" or "离线", skillId, value))
            else
                sendResult(false, string.format("玩家【%s】未拥有功法 %s", tName, skillId))
                return
            end
        elseif field == "toggle_debug_flag" then
            local flagKey = extra
            if flagKey == "" then
                sendResult(false, "未指定 flag key")
                return
            end
            local enabled = (value ~= 0)
            tPd.debug_flags = tPd.debug_flags or {}
            tPd.debug_flags[flagKey] = enabled or nil
            local label = flagKey
            for _, def in ipairs(Settings.ADMIN_DEBUG_FLAGS) do
                if def.key == flagKey then label = def.label; break end
            end
            sendResult(true, string.format("【%s】（%s）%s：%s", tName, online and "在线" or "离线", label, enabled and "已开启" or "已关闭"))
        elseif field == "material" then
            local matId = extra
            if matId == "" then
                sendResult(false, "未指定材料ID")
                return
            end
            local matDef = Settings.ALCHEMY_MATERIALS[matId]
            if not matDef then
                sendResult(false, "材料不存在: " .. matId)
                return
            end
            tPd.inventory = tPd.inventory or {}
            local found = false
            for i, item in ipairs(tPd.inventory) do
                if item.id == matId then
                    found = true
                    if value <= 0 then
                        table.remove(tPd.inventory, i)
                    else
                        item.count = value
                    end
                    break
                end
            end
            if not found and value > 0 then
                table.insert(tPd.inventory, { id = matId, count = value, type = "material" })
            end
            Server.SavePlayerData(tUid, tPd)
            if online then
                local targetConn2 = connections_[tUid]
                if targetConn2 then
                    Server.PushInventory(tUid, targetConn2)
                end
            end
            sendResult(true, string.format("已将【%s】（%s）的%s设置为 %d", tName, online and "在线" or "离线", matDef.name, value))
        elseif field == "add_skill" then
            local skillId = extra
            if skillId == "" then
                sendResult(false, "未指定功法ID")
                return
            end
            local skillDef = nil
            for _, sk in ipairs(Settings.SKILLS) do
                if sk.id == skillId then skillDef = sk; break end
            end
            if not skillDef then
                sendResult(false, "功法不存在: " .. skillId)
                return
            end
            tPd.skills = tPd.skills or {}
            for _, sk in ipairs(tPd.skills) do
                if sk.id == skillId then
                    sendResult(false, string.format("玩家【%s】已拥有功法 %s", tName, skillDef.name))
                    return
                end
            end
            table.insert(tPd.skills, {
                id = skillId,
                skill_id = skillId,
                level = value > 0 and value or 1,
                proficiency = 0,
                bound = true,
            })
            sendResult(true, string.format("已为【%s】（%s）添加功法《%s》Lv.%d", tName, online and "在线" or "离线", skillDef.name, value > 0 and value or 1))
        else
            sendResult(false, "不支持的字段: " .. field)
            return
        end

        -- 推送更新给目标玩家（在线时）
        if online then
            local targetConn = connections_[tUid]
            if targetConn then
                Server.PushPlayerData(tUid, targetConn)
            end
        end

        -- 向管理员推送更新后的玩家详情（刷新管理面板）
        local stats = Shared.CalcStats(tPd)
        local infoData = VariantMap()
        infoData["info_json"] = Variant(cjson.encode({
            uid          = tUid,
            name         = tPd.name,
            level        = tPd.level or 1,
            silver       = tPd.silver or 0,
            spirit_stone = tPd.spirit_stone or 0,
            potential    = tPd.potential or 0,
            scene        = tPd.scene or "?",
            online       = online,
            realm        = tPd.realm or 1,
            realm_layer  = tPd.realm_layer or 1,
            realm_exp    = tPd.realm_exp or 0,
            skills       = tPd.skills or {},
            inventory    = tPd.inventory or {},
            debug_flags  = tPd.debug_flags or {},
        }))
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_ADMIN_PLAYER_INFO, true, infoData)
        Server.SavePlayerData(tUid, tPd)
    end

    if isOnline then
        -- 在线玩家：直接修改内存数据
        applyModification(targetPd, targetUid, targetPd.name or "?", true)
    else
        -- 离线玩家：从云端加载 → 修改 → 保存
        -- 先尝试从 playerRegistry_ 查找 UID（targetUid 可能是字符串形式）
        local numericUid = tonumber(targetUid)
        if not numericUid then
            sendResult(false, "无效的玩家UID: " .. tostring(targetUid))
            return
        end
        -- 验证该 UID 确实在注册列表中
        local uidExists = false
        for _, regUid in pairs(playerRegistry_) do
            if regUid == numericUid then
                uidExists = true
                break
            end
        end
        if not uidExists then
            sendResult(false, "未找到该玩家（UID: " .. tostring(targetUid) .. "）")
            return
        end
        -- 异步加载离线玩家数据
        serverCloud:BatchGet(numericUid)
            :Key("player_data")
            :Fetch({
                ok = function(scores, iscores)
                    local offPd = scores.player_data
                    if not offPd then
                        sendResult(false, "加载离线玩家数据失败（无存档）")
                        return
                    end
                    offPd.uid = numericUid
                    -- 补充默认值
                    for k, v in pairs(Settings.INITIAL_PLAYER) do
                        if offPd[k] == nil then offPd[k] = v end
                    end
                    applyModification(offPd, numericUid, offPd.name or "?", false)
                end,
                error = function(code, reason)
                    sendResult(false, "加载离线玩家数据失败: " .. tostring(reason))
                end
            })
    end
end

-- ── 管理员：玩家列表（分页）────────────────────────────────────────────────────
function Server_OnAdminListPlayers(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    local pd   = players_[uid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "<红>权限不足</红>")
        return
    end

    local mode     = eventData["Mode"]:GetString()    -- "online" | "all"
    local page     = eventData["Page"]:GetInt()       -- 1-based
    local pageSize = eventData["PageSize"]:GetInt()
    if page < 1 then page = 1 end
    if pageSize < 1 or pageSize > 50 then pageSize = 20 end

    local items = {}

    if mode == "online" then
        -- 在线玩家直接从内存读取
        for oUid, oPd in pairs(players_) do
            items[#items + 1] = {
                uid    = oUid,
                name   = oPd.name or "?",
                level  = oPd.level or 1,
                realm  = oPd.realm or 1,
                realm_layer = oPd.realm_layer or 1,
                scene  = oPd.scene or "-",
                silver = oPd.silver or 0,
                spirit_stone = oPd.spirit_stone or 0,
                online = true,
            }
        end
        -- 按名字排序
        table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
    else
        -- 全部玩家：合并注册表（在线状态叠加）
        local seen = {}
        for name, rUid in pairs(playerRegistry_) do
            if not seen[rUid] then
                seen[rUid] = true
                local oPd = players_[rUid]
                items[#items + 1] = {
                    uid    = rUid,
                    name   = name,
                    level  = oPd and (oPd.level or 1) or nil,
                    realm  = oPd and (oPd.realm or 1) or nil,
                    realm_layer = oPd and (oPd.realm_layer or 1) or nil,
                    scene  = oPd and (oPd.scene or "-") or nil,
                    silver = oPd and (oPd.silver or 0) or nil,
                    spirit_stone = oPd and (oPd.spirit_stone or 0) or nil,
                    online = (oPd ~= nil),
                }
            end
        end
        table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
    end

    local total   = #items
    local startI  = (page - 1) * pageSize + 1
    local endI    = math.min(startI + pageSize - 1, total)
    local pageItems = {}
    for i = startI, endI do
        pageItems[#pageItems + 1] = items[i]
    end

    local result = VariantMap()
    result["list_json"] = Variant(cjson.encode(pageItems))
    result["total"]     = Variant(total)
    result["page"]      = Variant(page)
    result["page_size"] = Variant(pageSize)
    result["mode"]      = Variant(mode)
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_ADMIN_PLAYER_LIST, true, result)
end

-- 管理员重置自身存档（清除云端 player_data，重登后变新号）
function Server_OnAdminResetSelf(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    local pd   = players_[uid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "<红>权限不足，需先激活管理员</红>")
        return
    end

    -- 立即清除内存，防止定时存档任务覆盖即将进行的云端重置
    players_[uid] = nil

    -- 删除云端 player_data 键
    serverCloud:Delete(uid, "player_data", {
        ok = function()
            Server.PushLog(conn, "存档已清除！请重新打开游戏以新号身份进入。", "good")
            print("[Admin] 存档重置完成 uid:", tostring(uid))
        end,
        error = function(code, reason)
            Server.PushLog(conn, "重置主存档失败：" .. tostring(reason), "danger")
        end,
    })

    -- 逐条删除背包 List（inventory）：先 Get 拿到所有 listId，再逐一 Delete
    serverCloud.list:Get(uid, "inventory", {
        ok = function(entries)
            if not entries or #entries == 0 then
                print("[Admin] inventory 为空，无需清除 uid:", tostring(uid))
                return
            end
            print(string.format("[Admin] 开始清除 inventory %d 条 uid=%s", #entries, tostring(uid)))
            for _, entry in ipairs(entries) do
                serverCloud.list:Delete(entry.list_id, {
                    error = function(code, reason)
                        print(string.format("[Admin] inventory 删除条目失败 listId=%s: %s",
                            tostring(entry.list_id), tostring(reason)))
                    end,
                })
            end
        end,
        error = function(code, reason)
            print("[Admin] inventory 读取失败，跳过清除:", tostring(reason))
        end,
    })
end

-- 管理员重置指定玩家存档（按 uid 清除云端数据，在线则踢下线）
function Server_OnAdminResetPlayer(eventType, eventData)
    local conn    = eventData["Connection"]:GetPtr("Connection")
    local callerUid = Server.GetUidByConn(conn)
    local pd      = players_[callerUid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "权限不足，需先激活管理员", "danger")
        return
    end

    local targetUid = eventData:GetInt64("TargetUid")
    if not targetUid or targetUid == 0 then
        Server.PushLog(conn, "目标 uid 无效", "danger")
        return
    end

    local targetConn = connections_[targetUid]
    local targetName = players_[targetUid] and players_[targetUid].name or tostring(targetUid)

    -- 从邀请码查找表中移除旧码
    local oldPd = players_[targetUid]
    if oldPd and oldPd.invite_code and oldPd.invite_code ~= "" then
        inviteCodes_[oldPd.invite_code] = nil
    end

    -- 立即用初始数据重置内存，阻止定时存档覆盖旧数据
    local newPd = {}
    for k, v in pairs(Settings.INITIAL_PLAYER) do
        newPd[k] = v
    end
    newPd.uid  = targetUid
    newPd.name = "无名修士"  -- 重置名字，让玩家重新取名
    newPd.hp = Shared.CalcStats(newPd).hp  -- 重置满血
    newPd._isNewPlayer = true
    newPd._needCreate = true  -- 标记需要走角色创建流程
    newPd.invite_code = Server.GenerateInviteCode()
    inviteCodes_[newPd.invite_code] = targetUid
    players_[targetUid] = newPd

    -- 如果在线，推送重置数据（客户端收到 _needCreate 将重新走注册流程）
    if targetConn then
        Server.SendInitPlayer(targetUid, targetConn, newPd)
        Server.PushLog(targetConn, "管理员已清除你的存档，请重新创建角色！", "danger")
    end

    -- 删除云端 player_data
    serverCloud:Delete(targetUid, "player_data", {
        ok = function()
            Server.PushLog(conn, "已重置玩家 " .. targetName .. " 的存档！", "good")
            print("[Admin] 存档重置完成 targetUid:", tostring(targetUid))
        end,
        error = function(code, reason)
            Server.PushLog(conn, "重置失败：" .. tostring(reason), "danger")
        end,
    })

    -- 逐条删除背包 List
    serverCloud.list:Get(targetUid, "inventory", {
        ok = function(entries)
            if not entries or #entries == 0 then return end
            for _, entry in ipairs(entries) do
                serverCloud.list:Delete(entry.list_id, {
                    error = function(code, reason)
                        print(string.format("[Admin] inventory 删除失败 listId=%s: %s",
                            tostring(entry.list_id), tostring(reason)))
                    end,
                })
            end
        end,
        error = function(code, reason)
            print("[Admin] inventory 读取失败，跳过清除:", tostring(reason))
        end,
    })
end

-- ============================================================================
-- 活动管理（管理员设置活动参数）
-- ============================================================================

local function SaveActivityConfig()
    local data = {
        monster_respawn_delay = Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY,
        war_start_hour = Settings.TERRITORY_WAR.START_HOUR,
        war_start_min  = Settings.TERRITORY_WAR.START_MIN,
        war_end_hour   = Settings.TERRITORY_WAR.END_HOUR,
        war_end_min    = Settings.TERRITORY_WAR.END_MIN,
    }
    serverCloud.list:Get(0, "activity_config", {
        ok = function(list)
            if list and #list > 0 then
                serverCloud.list:Modify(list[#list].list_id, data, {
                    ok = function() print("[Server] 活动配置已持久化") end,
                    error = function(c, r) print("[Server] 活动配置保存失败:", c, r) end,
                })
            else
                serverCloud.list:Add(0, "activity_config", data, {
                    ok = function() print("[Server] 活动配置首次写入完成") end,
                    error = function(c, r) print("[Server] 活动配置写入失败:", c, r) end,
                })
            end
        end,
        error = function(c, r) print("[Server] 活动配置查询失败:", c, r) end,
    })
end

local function LoadActivityConfig()
    serverCloud.list:Get(0, "activity_config", {
        ok = function(list)
            if list and #list > 0 and list[#list].value then
                local d = list[#list].value
                if d.monster_respawn_delay then
                    Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY = d.monster_respawn_delay
                end
                if d.war_start_hour then
                    Settings.TERRITORY_WAR.START_HOUR = d.war_start_hour
                    Settings.TERRITORY_WAR.START_MIN  = d.war_start_min or 0
                    Settings.TERRITORY_WAR.END_HOUR   = d.war_end_hour or 21
                    Settings.TERRITORY_WAR.END_MIN    = d.war_end_min or 0
                end
                print(string.format("[Server] 活动配置加载完成: 刷怪=%.1fs 领地战=%02d:%02d~%02d:%02d",
                    Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY,
                    Settings.TERRITORY_WAR.START_HOUR, Settings.TERRITORY_WAR.START_MIN,
                    Settings.TERRITORY_WAR.END_HOUR, Settings.TERRITORY_WAR.END_MIN))
            else
                print("[Server] 无持久化活动配置，使用默认值")
            end
        end,
        error = function(c, r) print("[Server] 活动配置加载失败:", c, r) end,
    })
end

function Server_OnAdminSetActivity(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    local pd   = players_[uid]
    if not pd or not pd.is_admin then
        Server.PushLog(conn, "<红>权限不足，需先激活管理员</红>")
        return
    end

    local action = eventData:GetString("Action")
    local value  = eventData:GetString("Value")
    print("[Admin] SetActivity action=" .. tostring(action) .. " value=" .. tostring(value))

    if action == "set_respawn_delay" then
        local delay = tonumber(value)
        if not delay or delay < 1 or delay > 3600 then
            Server.PushLog(conn, "刷怪间隔无效(1-3600秒)", "danger")
            return
        end
        Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY = delay
        SaveActivityConfig()
        Server.PushLog(conn, string.format("怪物刷新间隔已修改为 %d 秒（已永久保存）", delay), "good")

    elseif action == "set_war_time" then
        -- value 格式: "HH:MM-HH:MM"
        local sh, sm, eh, em = value:match("^(%d+):(%d+)-(%d+):(%d+)$")
        sh, sm, eh, em = tonumber(sh), tonumber(sm), tonumber(eh), tonumber(em)
        if not sh or sh > 23 or sm > 59 or not eh or eh > 23 or em > 59 then
            Server.PushLog(conn, "时间格式错误，应为 HH:MM-HH:MM", "danger")
            return
        end
        Settings.TERRITORY_WAR.START_HOUR = sh
        Settings.TERRITORY_WAR.START_MIN  = sm
        Settings.TERRITORY_WAR.END_HOUR   = eh
        Settings.TERRITORY_WAR.END_MIN    = em
        SaveActivityConfig()
        Server.PushLog(conn, string.format("领地战时间已修改为 %02d:%02d - %02d:%02d（已永久保存）", sh, sm, eh, em), "good")

    elseif action == "force_war_start" then
        if territoryWarActive_ then
            Server.PushLog(conn, "领地战已经在进行中", "warning")
            return
        end
        forceWarOverride_ = true  -- 持续覆盖，防止下个tick被IsTerritoryWarTime()改回false
        territoryWarActive_ = true
        -- 广播开战通知
        local notifyData = VariantMap()
        notifyData["Msg"] = Variant("⚔ 管理员强制开启领地战！前往帮会领地层争夺据点！")
        for _, c in pairs(connections_) do
            if c and c:IsConnected() then
                c:SendRemoteEvent(Settings.EVENTS.NOTIFY_WAR_START, true, notifyData)
            end
        end

        spDefenders_ = {}
        spAttackers_ = {}
        spCaptureTimers_ = {}
        Server.PushLog(conn, "领地战已强制开启（将持续到手动关闭或服务器重启）", "good")

    elseif action == "force_war_end" then
        if not territoryWarActive_ then
            Server.PushLog(conn, "领地战当前未进行", "warning")
            return
        end
        forceWarOverride_ = nil  -- 恢复为按时间自动判断
        territoryWarActive_ = false
        -- 广播结束通知
        local notifyData = VariantMap()
        notifyData["Msg"] = Variant("领地战已被管理员强制结束。据点归属已确定。")
        for _, c in pairs(connections_) do
            if c and c:IsConnected() then
                c:SendRemoteEvent(Settings.EVENTS.NOTIFY_WAR_END, true, notifyData)
            end
        end
        spCaptureTimers_ = {}  -- 清除进行中的占领计时器
        Server.PushLog(conn, "领地战已强制结束（恢复为按时间自动判断）", "good")

    else
        Server.PushLog(conn, "未知操作: " .. tostring(action), "danger")
    end
end

-- ============================================================================
-- 战利品拾取处理
-- ============================================================================

function Server_OnReqPickupLoot(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    if not uid then return end

    local token = eventData:GetString("Token")
    if not token or token == "" then return end

    local entry = pendingLoots_[token]
    if not entry then
        -- token 已用或不存在（可能已过期被清理）
        local data = VariantMap()
        data["Success"]  = Variant(false)
        data["ItemName"] = Variant("")
        conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_LOOT_RESULT), true, data)
        return
    end

    -- 安全检查：token 只能被对应玩家领取
    if entry.uid ~= uid then
        Server.PushLog(conn, "拾取失败：物品不属于你", "danger")
        return
    end

    -- 移除 token（一次性，防止重复拾取）
    pendingLoots_[token] = nil

    -- 写入背包（异步），在回调中推送结果和背包更新
    local itemName = entry.item.name or "未知物品"
    Server.AddItemToInventory(uid, entry.item, function(success)
        local data = VariantMap()
        data["Success"]  = Variant(true)
        data["ItemName"] = Variant(itemName)
        conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_LOOT_RESULT), true, data)

        -- 背包写入完成后再推送，确保客户端拿到最新数据
        Server.PushInventory(uid, conn)
    end)
end

-- ============================================================================
-- 重置新手教程（设置面板，开发/测试用）
-- ============================================================================
function Server_OnReqResetTutorial(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    if not uid then return end
    local pd = players_[uid]
    if not pd then return end

    pd.tutorial_step = 0
    pd.scene = Settings.SCENES.ANCIENT_VILLAGE
    pd.spot  = "village_center"

    Server.PushLog(conn, "<黄>【系统】新手引导已重置！即将重新开始教程…</黄>")
    Server.SendInitPlayer(uid, conn, pd)
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
end

-- ============================================================================
-- 跳过新手教程（客户端请求）
-- ============================================================================
function Server_OnReqSkipTutorial(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    if not uid then return end
    local pd = players_[uid]
    if not pd then return end

    -- 已完成教程则忽略
    if (pd.tutorial_step or 0) >= 3 then return end

    -- 直接标记教程完成
    pd.tutorial_step = 3

    -- 给予奖励（与正常完成一致）：小回血丹x3 + 200银两
    local rewardItem = {
        type  = "medicine",
        id    = Shared.GenId(),
        item_id  = "medicine_small_hp",
        name  = "小回血丹",
        count = 3,
        effect = { hp = 40 },
        desc  = "最基础的疗伤丹药，略微止血。",
    }
    pd.silver = (pd.silver or 0) + 200

    Server.AddItemToInventory(uid, rewardItem, function()
        Server.PushInventory(uid, conn)
    end)

    -- 立即推送玩家数据（tutorial_step=3），不依赖异步回调
    Server.PushPlayerData(uid, conn)

    Server.PushLog(conn, "<金>【跳过引导】获得小回血丹×3 + 200银两！古村出口已解锁。</金>")
    Server.PushLog(conn, "")
    Server.PushLog(conn, "<金>═══════ 新手目标指引 ═══════</金>")
    Server.PushLog(conn, "<红>⚠ 重要：【打坐】是练功法技能，不是升境界！</红>")
    Server.PushLog(conn, "<红>  升境界靠【战斗】获得修为经验，满了再突破。</红>")
    Server.PushLog(conn, "<黄>1. 点击底部【战斗】杀怪获取修为经验（升级唯一途径）</黄>")
    Server.PushLog(conn, "<黄>2. 修为满后，点击【突破】晋升境界</黄>")
    Server.PushLog(conn, "<黄>3. 突破到筑基需要「筑基丹」→ 去扬州城【药铺】购买</黄>")
    Server.PushLog(conn, "<黄>4. 【打坐】用于提升功法熟练度（消耗潜能）</黄>")
    Server.PushLog(conn, "<黄>5. 点击顶部【地图】前往扬州城探索</黄>")
    Server.PushLog(conn, "<金>═══════════════════════════</金>")

    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
end

-- ============================================================================
-- 推送工具函数
-- ============================================================================

function Server.PushLog(conn, text, color)
    local data = VariantMap()
    data["text"] = Variant(text)
    if color then data["color"] = Variant(color) end
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_GAME_LOG, true, data)
end

function Server.PushPlayerData(uid, conn)
    local pd = players_[uid]
    if not pd or not conn then return end
    local stats = Shared.CalcStats(pd)
    -- 境界数据
    local realm = pd.realm or 1
    local realmLayer = pd.realm_layer or 1
    local realmExpNeeded = Settings.REALM.IsMaxRealm(realm, realmLayer) and 0
        or Settings.REALM.GetExpNeeded(realm, realmLayer)

    local payload = {
        uid         = uid,
        level       = pd.level,
        exp         = pd.realm_exp or 0,
        exp_max     = realmExpNeeded,
        realm       = realm,
        realm_layer = realmLayer,
        realm_exp   = pd.realm_exp or 0,
        realm_exp_max = realmExpNeeded,
        realm_name  = Settings.REALM.GetDisplayName(realm, realmLayer),
        potential   = math.floor(pd.potential or 0),
        silver      = pd.silver or 0,
        spirit_stone= pd.spirit_stone or 0,
        sect        = pd.sect,
        scene       = pd.scene,
        spot        = pd.spot or "",
        name        = pd.name,
        cultivating = pd.cultivating,
        in_battle   = Combat.IsInBattle(uid),
        is_admin    = pd.is_admin or false,
        stats       = stats,
        skills      = pd.skills or {},
        equipment   = pd.equipment or {},
        inventory_count = pd.inventory and #pd.inventory or 0,
        tutorial_step   = pd.tutorial_step or 0,
        alchemy_level = pd.alchemy_level or 0,
        alchemy_exp   = pd.alchemy_exp or 0,
        -- 当前气血/内力
        hp          = pd.hp or stats.hp,
        mp          = pd.mp or stats.mp,
        max_hp      = stats.hp,
        max_mp      = stats.mp,
        -- 基础属性（供客户端属性面板显示）
        hp_base     = pd.hp_base or 0,
        mp_base     = pd.mp_base or 0,
        atk_base    = pd.atk_base or 0,
        def_base    = pd.def_base or 0,
        agi_base    = pd.agi_base or 0,
        wis_base    = pd.wis_base or 0,
        -- 帮会
        guild_id    = pd.guild_id or "",
        guild_name  = pd.guild_name or "",
        -- 新炼器系统
        blueprints_learned = pd.blueprints_learned or {},
        forge_pity         = pd.forge_pity or {},
        -- 出战技能槽
        battle_slots       = pd.battle_slots or {},
        -- 突破与修炼加成
        breakthrough_fails = pd.breakthrough_fails or 0,
        cultivate_cost_mult = pd.cultivate_cost_mult or 1,
        -- 门派试炼进度
        sect_trials = pd.sect_trials or {},
        -- 域外战场解锁层数
        max_battlefield_layer = pd.max_battlefield_layer or Settings.BATTLEFIELD_INITIAL_LAYERS,
        -- Boss 击败记录
        boss_defeated = pd.boss_defeated or {},
        revive_shield = pd.revive_shield or false,
        titles_owned = pd.titles_owned or {},
        active_title = pd.active_title or "",
    }
    local data = VariantMap()
    data["data_json"] = Variant(cjson.encode(payload))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_PLAYER_DATA, true, data)
end

-- ============================================================================
-- 背包推送
-- ============================================================================

function Server.PushInventory(uid, conn)
    local pd = players_[uid]
    if not pd or not conn then return end
    local items = pd.inventory or {}
    local data = VariantMap()
    data["items_json"] = Variant(cjson.encode(items))
    conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_INVENTORY), true, data)
end

-- ============================================================================
-- 背包工具函数
-- ============================================================================

function Server.FindInventoryItem(pd, itemId)
    if not pd.inventory then return nil end
    for _, item in ipairs(pd.inventory) do
        if item.id == itemId or tostring(item._list_id) == itemId then return item end
    end
    return nil
end

function Server.RemoveInventoryItem(pd, itemId)
    if not pd.inventory then return end
    for i, item in ipairs(pd.inventory) do
        if item.id == itemId then
            table.remove(pd.inventory, i)
            return
        end
    end
end

-- ============================================================================
-- NPC 对话选项回调（客户端选择非战斗选项后发送）
-- ============================================================================

function Server_OnReqNpcOption(eventType, eventData)
    local conn   = eventData["Connection"]:GetPtr("Connection")
    local uid    = Server.GetUidByConn(conn)
    local pd     = players_[uid]
    if not pd then return end

    local npcId  = eventData["NpcId"]:GetString()
    local action = eventData["Action"]:GetString()

    if npcId == "village_elder" and action == "tutorial_accept" then
        -- 玩家接受了老村长任务，推进 step 0 → 1
        if (pd.tutorial_step or 0) == 0 then
            pd.tutorial_step = 1
            -- 传授基本拳脚功法
            Server.GrantSkills(uid, conn, pd, {"basic_fist"})
            Server.PushLog(conn, "老村长拍了拍你的肩膀：「这套拳脚是老夫年轻时练的，虽不入流，但打坐修炼亦可强身。去吧，村口便有幼妖出没，将其驱散即可。」")
            Server.PushLog(conn, "<黄>【提示】前往「竹林」驱散迷失幼妖，完成老村长的委托。</黄>")
            Server.PushPlayerData(uid, conn)
        end

    elseif action == "learn_skill" then
        -- 玩家在对话中选择学习某一功法
        local skillId   = eventData["Data"]:GetString()

        -- 通过 npcId 查找长老信息（数据驱动）
        local elderInfo = NPC_TO_ELDER[npcId]
        if not elderInfo or skillId == "" then return end

        local branch    = elderInfo.branch
        local elderName = elderInfo.display
        local sectId    = elderInfo.sect_id

        if pd.sect ~= sectId then return end

        -- 再次校验：该功法确实是当前可传授的（防止重放）
        local grantable = FindGrantable(pd, branch)
        local valid = false
        for _, id in ipairs(grantable) do
            if id == skillId then valid = true; break end
        end
        if not valid then
            Server.PushLog(conn, "<红>该功法暂无法传授。</红>")
            return
        end

        local toGive = { skillId }

        -- 首次晋升中级（grade 2）时，同时赠送本门派另一分支的中级
        local skillDef = Shared.GetSkillDef(skillId)
        if skillDef and skillDef.grade == 2 then
            ---@diagnostic disable-next-line: assign-type-mismatch
            local sectCfg = SECT_CONFIG[sectId]
            if sectCfg then
                for _, elder in ipairs(sectCfg.elders) do
                    if elder.branch ~= branch then
                        -- 找对应另一分支的 grade=2 功法
                        for _, sd in ipairs(Settings.SKILLS) do
                            if sd.grade == 2 and sd.branch == elder.branch then
                                if not Cultivation.GetOwnedSkill(pd, sd.id) then
                                    toGive[#toGive + 1] = sd.id
                                end
                                break
                            end
                        end
                        break
                    end
                end
            end
        end

        local granted = Server.GrantSkills(uid, conn, pd, toGive)
        if #granted > 0 then
            local names = {}
            for _, g in ipairs(granted) do names[#names + 1] = g.skill_name end
            Server.PushLog(conn, string.format(
                "<黄>%s传功完毕，获得：%s（绑定，可解绑出售）</黄>",
                elderName, table.concat(names, "、")
            ))
        end

    elseif action == "trial_accept" then
        -- 接受宗门试炼
        local sectId = eventData["Data"]:GetString()
        local quest = Settings.SECT_TRIAL.QUESTS[sectId]
        if not quest then return end
        if pd.sect ~= "" then return end  -- 已有门派不能接
        if not pd.sect_trials then pd.sect_trials = {} end
        if pd.sect_trials[sectId] and pd.sect_trials[sectId].status then return end  -- 已有记录不重复接
        pd.sect_trials[sectId] = { status = "accepted", progress = 0 }
        Server.PushLog(conn, quest.accept_msg)
        Server.PushLog(conn, string.format("<黄>【试炼已接取】%s</黄>", quest.desc))
        -- 收集类：立即检查背包是否已有材料
        if quest.type == "collect" then
            Server.TrySubmitCollectTrial(uid, conn, pd, sectId)
        end
        -- 战场类：检查是否已满足通关条件
        if quest.type == "battlefield" then
            local curMax = pd.max_battlefield_layer or 1
            if curMax >= quest.target_layer then
                pd.sect_trials[sectId].progress = 1
                Server.CheckTrialProgress(uid, conn, pd, sectId)
            end
        end
        Server.PushPlayerData(uid, conn)
        Quest.PushQuestState(pd, conn)
        Server.SavePlayerData(uid, pd)

    elseif action == "trial_abandon" then
        -- 放弃试炼（可以重新接取）
        local sectId = eventData["Data"]:GetString()
        if not pd.sect_trials then return end
        if not pd.sect_trials[sectId] then return end
        if pd.sect_trials[sectId].status ~= "accepted" then return end
        pd.sect_trials[sectId] = nil  -- 清除记录，允许重新接取
        local quest = Settings.SECT_TRIAL.QUESTS[sectId]
        local qname = quest and quest.name or "试炼"
        Server.PushLog(conn, string.format("<黄>已放弃【%s】，可以随时再来重新接取。</黄>", qname))
        Server.PushPlayerData(uid, conn)
        Quest.PushQuestState(pd, conn)
        Server.SavePlayerData(uid, pd)

    elseif action == "trial_join" then
        -- 通过试炼后正式加入门派
        local sectId = eventData["Data"]:GetString()
        if pd.sect ~= "" then return end  -- 已有门派
        if not pd.sect_trials or not pd.sect_trials[sectId] then return end
        if pd.sect_trials[sectId].status ~= "completed" then return end
        -- 执行加入门派（复用现有逻辑）
        Server.HandleJoinSect(uid, conn, pd, sectId)

    elseif action == "leave_sect" then
        -- 退出门派
        local curSect = pd.sect or ""
        if curSect == "" then return end  -- 没有门派
        local sectDisplay = Settings.SECT_INFO and Settings.SECT_INFO[curSect]
            and Settings.SECT_INFO[curSect].display or curSect
        -- 清除门派归属
        pd.sect = ""
        pd.branch = nil
        pd.sect_trials = nil
        -- 清除门派技能（通过前缀匹配判断归属）
        local sectPrefixes = {
            sword_sect    = { "basic_sword", "swift_", "heavy_", "wind_", "lone_", "shadowless_sword", "dragon_", "sky_", "broken_" },
            iron_sect     = { "iron_", "shield_", "bastion_", "stone_", "diamond_", "undying_" },
            medicine_sect = { "herb_", "spring_", "marrow_", "golden_needle", "life_death", "venom_", "viper_", "ten_thousand", "soul_devouring" },
            shadow_sect   = { "shadow_", "ghost_", "phantom_", "night_flash", "heaven_shadow", "hidden_dart", "needle_rain", "ten_dir_darts", "shadowless_strike" },
            qidan_sect    = {},  -- 器丹宗暂无独有战斗技能
        }
        if pd.skills then
            local prefixes = sectPrefixes[curSect] or {}
            local kept = {}
            for _, sk in ipairs(pd.skills) do
                local isSectSkill = false
                for _, prefix in ipairs(prefixes) do
                    if sk.id:sub(1, #prefix) == prefix or sk.id == prefix then
                        isSectSkill = true
                        break
                    end
                end
                if not isSectSkill then
                    kept[#kept + 1] = sk
                end
            end
            pd.skills = kept
        end
        -- 清除出战技能槽中的门派技能
        if pd.battle_slots then
            for i, slotId in ipairs(pd.battle_slots) do
                local found = false
                for _, sk in ipairs(pd.skills) do
                    if sk.id == slotId then found = true; break end
                end
                if not found then
                    pd.battle_slots[i] = ""
                end
            end
        end
        Server.PushLog(conn, string.format(
            "<红>你已退出【%s】，门派技能已清除。如需重新加入，请再次完成入门试炼。</红>", sectDisplay))
        Server.PushPlayerData(uid, conn)
        Server.SavePlayerData(uid, pd)

    elseif action == "realm_pill_shop" then
        -- 药铺老板的修为丹子菜单
        Server_OnReqRealmPillShop(eventType, eventData)

    elseif action == "medicine_shop_items" then
        -- 药铺老板：查看普通药品
        Server.HandleMedicineShopItems(uid, conn, pd)
    end
end

-- ============================================================================
-- 排名（多类型排行榜 - serverCloud 全服排行，含离线玩家）
-- ============================================================================

local rankCache_ = {}       -- rankCache_[type] = { data = ..., time = 0 }
local RANK_CACHE_TTL = 30   -- 缓存有效期（秒）- 异步查询不能太频繁

-- 计算装备战力（仅装备贡献）
local function CalcEquipPower(pd)
    local eqAtk, eqDef, eqAgi, eqHp = 0, 0, 0, 0
    if pd.equipment then
        for _, item in pairs(pd.equipment) do
            if item and item.stats then
                eqAtk = eqAtk + (item.stats.atk or 0)
                eqDef = eqDef + (item.stats.def or 0)
                eqAgi = eqAgi + (item.stats.agi or 0)
                eqHp  = eqHp  + (item.stats.hp  or 0)
            end
        end
    end
    return Settings.CalcPower({ atk = eqAtk, def = eqDef, agi = eqAgi, hp = eqHp })
end

-- serverCloud 排行榜 key 映射
local RANK_KEYS = {
    power  = "rank_power",
    realm  = "rank_realm",
    equip  = "rank_equip",
    ladder = "rank_ladder",
}

-- 构建帮会总战力榜（帮会数据仍需聚合在线+离线，暂保留在线统计）
local function BuildRankGuild()
    local list = {}
    for guildId, g in pairs(guilds_) do
        local totalPower = 0
        local memberCount = 0
        if g.members then
            for _, memberUid in ipairs(g.members) do
                local pd = players_[memberUid]
                if pd then
                    local stats = Shared.CalcStats(pd)
                    totalPower = totalPower + Settings.CalcPower(stats)
                    memberCount = memberCount + 1
                end
            end
        end
        if memberCount > 0 then
            list[#list + 1] = {
                name        = g.name or "未知帮会",
                total_power = totalPower,
                avg_power   = math.floor(totalPower / memberCount),
                members     = memberCount,
                leader      = players_[g.leader_uid] and players_[g.leader_uid].name or "?",
            }
        end
    end
    table.sort(list, function(a, b) return a.total_power > b.total_power end)
    if #list > 20 then
        local trimmed = {}
        for i = 1, 20 do trimmed[i] = list[i] end
        return trimmed
    end
    return list
end

-- 构建门派英豪榜（仍基于在线玩家，因为需要门派归属信息）
local function BuildRankSect()
    local sects = { "sword_sect", "iron_sect", "medicine_sect", "shadow_sect", "qidan_sect" }
    local groups = {}
    for _, sid in ipairs(sects) do groups[sid] = {} end

    for _, pd in pairs(players_) do
        local sid = pd.sect or ""
        if groups[sid] then
            local stats = Shared.CalcStats(pd)
            local power = Settings.CalcPower(stats)
            groups[sid][#groups[sid] + 1] = {
                name        = pd.name or "未知",
                power       = power,
                realm       = pd.realm or 1,
                realm_layer = pd.realm_layer or 1,
            }
        end
    end

    local result = {}
    for _, sid in ipairs(sects) do
        local g = groups[sid]
        table.sort(g, function(a, b) return a.power > b.power end)
        local totalPower = 0
        for _, p in ipairs(g) do totalPower = totalPower + p.power end
        local avgPower = #g > 0 and math.floor(totalPower / #g) or 0
        if #g > 10 then
            local trimmed = {}
            for i = 1, 10 do trimmed[i] = g[i] end
            g = trimmed
        end
        result[sid] = {
            list = g,
            count = #groups[sid],
            avg_power = avgPower,
        }
    end
    return result
end

--- 异步查询 serverCloud 排行榜并发送给客户端
---@param conn any
---@param rankType string
---@param cloudKey string
local function FetchCloudRank(conn, rankType, cloudKey)
    -- 检查缓存
    local now = os.time()
    local cached = rankCache_[rankType]
    if cached and (now - cached.time) < RANK_CACHE_TTL then
        local data = VariantMap()
        data["RankJson"] = Variant(cjson.encode(cached.data))
        data["RankType"] = Variant(rankType)
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_RANK, true, data)
        return
    end

    serverCloud:GetRankList(cloudKey, 1, 50, {
        ok = function(rankList)
            -- 收集 userId 列表
            local userIds = {}
            for _, item in ipairs(rankList) do
                userIds[#userIds + 1] = item.userId
            end

            -- 根据 uid 查找游戏角色名（优先在线，回退注册表）
            local function getGameName(uid)
                local pd = players_[uid]
                if pd and pd.name and pd.name ~= "" then return pd.name end
                -- 遍历 playerRegistry_（name → uid）查找
                for name, rUid in pairs(playerRegistry_) do
                    if rUid == uid then return name end
                end
                return nil
            end

            -- 查询昵称后组装数据
            local function buildAndSend(nicknameMap)
                local list = {}
                for i, item in ipairs(rankList) do
                    local score = item.iscore and item.iscore[cloudKey] or 0
                    -- 名字优先使用游戏角色名，回退到平台昵称
                    local gameName = getGameName(item.userId)
                    local platformName = nicknameMap[item.userId]
                    local displayName = gameName or (platformName and platformName ~= "" and platformName) or "未知"
                    ---@type table<string, any>
                    local entry = {
                        name  = displayName,
                        score = score,
                    }
                    -- 根据排行类型填充特定字段（客户端兼容）
                    if rankType == "power" then
                        entry.power = score
                        local pd = players_[item.userId]
                        if pd then
                            entry.realm = pd.realm or 0
                            entry.realm_layer = pd.realm_layer or 0
                            entry.sect = pd.sect or ""
                            entry.guild_name = pd.guild_name or ""
                        else
                            -- 离线玩家：从 iscore 中的 rank_realm 解码境界
                            local realmScore = item.iscore and item.iscore["rank_realm"] or 0
                            if realmScore > 0 then
                                entry.realm = math.floor(realmScore / 100)
                                entry.realm_layer = realmScore % 100
                            else
                                entry.realm = 1
                                entry.realm_layer = 1
                            end
                            entry.sect = ""
                            entry.guild_name = ""
                        end
                    elseif rankType == "realm" then
                        -- realm score = realm*100 + realm_layer
                        entry.realm = math.floor(score / 100)
                        entry.realm_layer = score % 100
                        local pd = players_[item.userId]
                        entry.level = pd and pd.level or 0
                        entry.sect = pd and pd.sect or ""
                    elseif rankType == "equip" then
                        entry.equip_power = score
                        local pd = players_[item.userId]
                        entry.sect = pd and pd.sect or ""
                        entry.best_quality = ""
                    elseif rankType == "ladder" then
                        entry.rating = score
                        local pd = players_[item.userId]
                        entry.wins = pd and pd.pvp_ladder and pd.pvp_ladder.wins or 0
                        entry.losses = pd and pd.pvp_ladder and pd.pvp_ladder.losses or 0
                        entry.sect = pd and pd.sect or ""
                    end
                    list[i] = entry
                end

                -- 更新缓存
                rankCache_[rankType] = { data = list, time = os.time() }

                -- 发送给客户端
                local data = VariantMap()
                data["RankJson"] = Variant(cjson.encode(list))
                data["RankType"] = Variant(rankType)
                conn:SendRemoteEvent(Settings.EVENTS.PUSH_RANK, true, data)
            end

            -- 查询昵称（作为回退备用）
            if #userIds > 0 then
                local nicknameMap = {}
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        for _, info in ipairs(nicknames) do
                            nicknameMap[info.userId] = info.nickname or ""
                        end
                        buildAndSend(nicknameMap)
                    end,
                    onError = function()
                        -- 昵称查询失败，直接用游戏名
                        buildAndSend({})
                    end,
                })
            else
                buildAndSend({})
            end
        end,
        error = function(code, reason)
            print("[Server] 排行榜查询失败:", rankType, code, reason)
            -- 回退：发送空列表
            local data = VariantMap()
            data["RankJson"] = Variant(cjson.encode({}))
            data["RankType"] = Variant(rankType)
            conn:SendRemoteEvent(Settings.EVENTS.PUSH_RANK, true, data)
        end
    })
end

function Server_OnReqRank(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    if not uid then return end

    local rankType = "power" -- 默认总战力榜
    if eventData["RankType"] then
        rankType = eventData["RankType"]:GetString()
    end

    -- 门派榜和帮会榜仍使用在线数据聚合
    if rankType == "sect" then
        local rankData = BuildRankSect()
        local data = VariantMap()
        data["RankJson"] = Variant(cjson.encode(rankData))
        data["RankType"] = Variant(rankType)
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_RANK, true, data)
        return
    elseif rankType == "guild" then
        local rankData = BuildRankGuild()
        local data = VariantMap()
        data["RankJson"] = Variant(cjson.encode(rankData))
        data["RankType"] = Variant(rankType)
        conn:SendRemoteEvent(Settings.EVENTS.PUSH_RANK, true, data)
        return
    end

    -- power / realm / equip / ladder → 使用 serverCloud 全服排行
    local cloudKey = RANK_KEYS[rankType]
    if not cloudKey then
        cloudKey = "rank_power"  -- fallback
        rankType = "power"
    end

    FetchCloudRank(conn, rankType, cloudKey)
end

-- ============================================================================
-- 聊天
-- ============================================================================

-- 向某频道历史缓冲区追加消息（超出上限时滚动丢弃最旧的）
local function AppendChatHistory(channel, msg)
    local buf = chatHistory_[channel]
    if not buf then return end
    buf[#buf + 1] = msg
    if #buf > CHAT_MAX_HISTORY then
        table.remove(buf, 1)
    end
end

-- 向指定连接推送单条消息
local function PushChatMsg(conn, msg)
    local data = VariantMap()
    data["MsgJson"] = Variant(cjson.encode(msg))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_CHAT_MSG, true, data)
end

-- 向所有在线玩家广播（可选：仅同门派）
local function BroadcastChat(msg, sectFilter)
    for uid, conn in pairs(connections_) do
        if not sectFilter or (players_[uid] and players_[uid].sect == sectFilter) then
            PushChatMsg(conn, msg)
        end
    end
end

-- 上线时向该玩家推送各频道历史消息
function Server.PushChatHistoryTo(uid, conn)
    local pd = players_[uid]
    local channels = { "world", "system" }
    -- 只有加入门派的玩家才推送门派历史
    if pd and pd.sect and pd.sect ~= "" then
        channels[#channels + 1] = "sect_" .. pd.sect
    end

    local allHistory = {}
    -- world
    for _, m in ipairs(chatHistory_.world) do allHistory[#allHistory + 1] = m end
    -- sect（门派专属频道 key 用 sect_<name>）
    if pd and pd.sect and pd.sect ~= "" then
        local sectKey = "sect_" .. pd.sect
        local buf = chatHistory_[sectKey]
        if buf then
            for _, m in ipairs(buf) do allHistory[#allHistory + 1] = m end
        end
    end
    -- guild（帮会专属频道）
    if pd and pd.guild_id and pd.guild_id ~= "" then
        local guildKey = "guild_" .. pd.guild_id
        local buf = chatHistory_[guildKey]
        if buf then
            for _, m in ipairs(buf) do allHistory[#allHistory + 1] = m end
        end
    end
    -- system
    for _, m in ipairs(chatHistory_.system) do allHistory[#allHistory + 1] = m end

    if #allHistory == 0 then return end
    local data = VariantMap()
    data["HistoryJson"] = Variant(cjson.encode(allHistory))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_CHAT_HISTORY, true, data)
end

function Server_OnReqChatSend(eventType, eventData)
    local conn    = eventData["Connection"]:GetPtr("Connection")
    local uid     = Server.GetUidByConn(conn)
    if not uid then return end
    local pd = players_[uid]
    if not pd then return end

    local channel = eventData:GetString("Channel") or "world"
    local text    = eventData:GetString("Text") or ""
    text = text:match("^%s*(.-)%s*$")  -- trim
    if text == "" then return end
    -- 限制单条消息长度
    if #text > 200 then text = text:sub(1, 200) end

    -- ── 发言冷却（管理员豁免）──
    if not pd.is_admin then
        local cooldowns = { world = 5, sect = 3, guild = 3, private = 2 }
        local cd = cooldowns[channel] or 3
        pd.last_chat_times = pd.last_chat_times or {}
        local now = os.time()
        local lastTime = pd.last_chat_times[channel] or 0
        local elapsed = now - lastTime
        if elapsed < cd then
            local errData = VariantMap()
            errData["MsgJson"] = Variant(cjson.encode({
                channel = "system", sender = "系统", sect = "",
                text = string.format("发言太快，请等待 %d 秒", cd - elapsed),
                time = now,
            }))
            conn:SendRemoteEvent(Settings.EVENTS.PUSH_CHAT_MSG, true, errData)
            return
        end
        pd.last_chat_times[channel] = now
    end

    local msg = {
        channel = channel,
        sender  = pd.name or "未知",
        sect    = pd.sect or "",
        text    = text,
        time    = os.time(),
    }

    if channel == "world" then
        AppendChatHistory("world", msg)
        BroadcastChat(msg)
    elseif channel == "sect" then
        if not pd.sect or pd.sect == "" then
            -- 未加入门派，拒绝
            local errData = VariantMap()
            errData["MsgJson"] = Variant(cjson.encode({
                channel = "system", sender = "系统", sect = "",
                text = "你尚未加入门派，无法使用门派频道。", time = os.time(),
            }))
            conn:SendRemoteEvent(Settings.EVENTS.PUSH_CHAT_MSG, true, errData)
            return
        end
        msg.channel = "sect"
        local sectKey = "sect_" .. pd.sect
        if not chatHistory_[sectKey] then chatHistory_[sectKey] = {} end
        AppendChatHistory(sectKey, msg)
        BroadcastChat(msg, pd.sect)
    elseif channel == "private" then
        -- 私信：发送给指定玩家
        local target = eventData:GetString("Target") or ""
        target = target:match("^%s*(.-)%s*$")
        if target == "" then return end
        -- 查找目标玩家
        local targetConn = nil
        for tuid, tpd in pairs(players_) do
            if tpd.name == target then
                targetConn = Server.GetConnByUid(tuid)
                break
            end
        end
        if not targetConn then
            -- 目标不在线
            local errData = VariantMap()
            errData["MsgJson"] = Variant(cjson.encode({
                channel = "private", sender = "系统", sect = "",
                text = "玩家【" .. target .. "】不在线", time = os.time(),
            }))
            conn:SendRemoteEvent(Settings.EVENTS.PUSH_CHAT_MSG, true, errData)
            return
        end
        -- 发送给目标
        msg.channel = "private"
        msg.target  = target
        local pushData = VariantMap()
        pushData["MsgJson"] = Variant(cjson.encode(msg))
        targetConn:SendRemoteEvent(Settings.EVENTS.PUSH_CHAT_MSG, true, pushData)
    elseif channel == "guild" then
        -- 帮会频道
        if not pd.guild_id or pd.guild_id == "" then
            local errData = VariantMap()
            errData["MsgJson"] = Variant(cjson.encode({
                channel = "system", sender = "系统", sect = "",
                text = "你尚未加入帮会，无法使用帮会频道。", time = os.time(),
            }))
            conn:SendRemoteEvent(Settings.EVENTS.PUSH_CHAT_MSG, true, errData)
            return
        end
        msg.channel = "guild"
        local guildKey = "guild_" .. pd.guild_id
        if not chatHistory_[guildKey] then chatHistory_[guildKey] = {} end
        AppendChatHistory(guildKey, msg)
        Server.AdvanceGuildDaily(uid, "chat", 1)
        Server.BroadcastGuildChat(msg, pd.guild_id)
    elseif channel == "system" then
        -- 普通玩家不能发系统消息，忽略
        return
    end
end

-- 服务端主动推送系统通知（供其他模块调用）
function Server.BroadcastSystemMsg(text)
    local msg = {
        channel = "system", sender = "系统", sect = "",
        text = text, time = os.time(),
    }
    AppendChatHistory("system", msg)
    BroadcastChat(msg)
end

-- ============================================================================
-- 辅助
-- ============================================================================

function Server.GetUidByConn(conn)
    for uid, c in pairs(connections_) do
        if c == conn then return uid end
    end
    -- 兜底：从identity读取
    local ok2, uid = pcall(function()
        return conn.identity["user_id"]:GetInt64()
    end)
    return ok2 and uid or nil
end

-- ============================================================================
-- 福利广告奖励
-- ============================================================================
---@type table<integer, {count: integer, lastTime: number, date: string}>
local adRewardState_ = {}  -- uid → { count, lastTime, date }

function Server_OnReqAdReward(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    local pd   = players_[uid]
    if not pd then return end

    local cfg = Settings.AD_REWARD
    local now = os.time()
    local today = os.date("%Y%m%d", now)

    -- 初始化或重置每日计数
    local state = adRewardState_[uid]
    if not state or state.date ~= today then
        state = { count = 0, lastTime = 0, date = today }
        adRewardState_[uid] = state
    end

    -- 检查每日上限
    if state.count >= cfg.DAILY_LIMIT then
        local data = VariantMap()
        data["Success"] = Variant(false)
        data["Amount"]  = Variant(0)
        data["Msg"]     = Variant("今日广告次数已用完（" .. cfg.DAILY_LIMIT .. "/" .. cfg.DAILY_LIMIT .. "），明日再来~")
        conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_AD_REWARD), true, data)
        return
    end

    -- 检查冷却
    if (now - state.lastTime) < cfg.COOLDOWN then
        local remain = cfg.COOLDOWN - (now - state.lastTime)
        local data = VariantMap()
        data["Success"] = Variant(false)
        data["Amount"]  = Variant(0)
        data["Msg"]     = Variant("操作太快，请" .. remain .. "秒后再试")
        conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_AD_REWARD), true, data)
        return
    end

    -- 发放奖励
    state.count = state.count + 1
    state.lastTime = now
    pd.spirit_stone = (pd.spirit_stone or 0) + cfg.SPIRIT_STONE

    local data = VariantMap()
    data["Success"] = Variant(true)
    data["Amount"]  = Variant(cfg.SPIRIT_STONE)
    data["Msg"]     = Variant("")
    conn:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_AD_REWARD), true, data)

    print(string.format("[AdReward] uid=%s +%d灵石 (今日%d/%d)",
        tostring(uid), cfg.SPIRIT_STONE, state.count, cfg.DAILY_LIMIT))
end

-- ============================================================================
-- 境界突破
-- ============================================================================

function Server_OnReqBreakthrough(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local realm = pd.realm or 1
    local layer = pd.realm_layer or 1

    -- 已达最高境界
    if Settings.REALM.IsMaxRealm(realm, layer) then
        Server.PushLog(conn, "<红>你已达到最高境界，无需突破。</红>")
        return
    end

    -- 突破只在当前境界满层时可用（跨境界）
    local stage = Settings.REALM.STAGES[realm]
    if not stage or layer < stage.layers then
        Server.PushLog(conn, "<红>当前境界尚未满层，无需手动突破。修为积满后会自动升重。</红>")
        return
    end

    -- 经验是否满（最末层经验）
    local needed = Settings.REALM.GetExpNeeded(realm, layer)
    if (pd.realm_exp or 0) < needed then
        Server.PushLog(conn, string.format("<红>修为不足，需要 %d 经验才能尝试突破。</红>", needed))
        return
    end

    -- 检查丹药（按目标境界索引查找）
    local nextRealm = realm + 1
    local pillReq = Settings.REALM_PILLS[nextRealm]
    if not pillReq then
        Server.PushLog(conn, "<红>配置异常，无法突破。</红>")
        return
    end

    -- 查找背包中的丹药
    local pillIdx = nil
    for i, item in ipairs(pd.inventory or {}) do
        if item.id == pillReq.pill_id then
            pillIdx = i
            break
        end
    end
    if not pillIdx then
        Server.PushLog(conn, string.format("<红>突破需要【%s】×%d，你尚未持有。</红>", pillReq.name, pillReq.count))
        Server.PushLog(conn, "<黄>【提示】前往「交易阁」可购买突破丹药！</黄>")
        return
    end

    -- 消耗丹药
    table.remove(pd.inventory, pillIdx)

    -- 灵石突破保护（客户端传入 Protected=true）
    local isProtected = false
    local protectCost = Settings.SPIRIT_STONE.BREAKTHROUGH_PROTECT_COST
    if eventData["Protected"] and eventData["Protected"]:GetBool() then
        if (pd.spirit_stone or 0) >= protectCost then
            pd.spirit_stone = (pd.spirit_stone or 0) - protectCost
            isProtected = true
            Server.PushLog(conn, string.format("<金>消耗%d灵石，开启突破保护！</金>", protectCost))
        else
            Server.PushLog(conn, "<红>灵石不足，无法开启突破保护，将以无保护状态突破。</红>")
        end
    end

    -- 概率判定
    local successRate = Settings.REALM.SUCCESS_RATE[realm] or 0.5
    -- 悟性加成
    local wisBonus = (Shared.CalcStats(pd).wis or 0) * (Settings.REALM.WIS_CULTIVATE_FACTOR or 0)
    successRate = successRate + wisBonus
    -- 保底加成：每次失败 +10% 成功率
    local pityBonus = (pd.breakthrough_fails or 0) * 0.10
    successRate = math.min(1.0, successRate + pityBonus)
    -- 限时活动突破加成
    local realmBoost = Activity.GetEventMultiplier("realm_boost")
    if realmBoost > 1.0 then
        successRate = math.min(1.0, successRate * realmBoost)
    end

    local roll = math.random()
    local resultData = VariantMap()

    if roll <= successRate then
        -- 突破成功：重置保底计数
        pd.breakthrough_fails = 0

        -- 跨境界突破：进入下一境界第1重
        local newRealm = nextRealm
        local newLayer = 1
        pd.realm = newRealm
        pd.realm_layer = newLayer
        pd.realm_exp = 0
        pd.level = Settings.REALM.CalcPowerLevel(newRealm, newLayer)

        local newName = Settings.REALM.GetDisplayName(newRealm, newLayer)
        Server.PushLog(conn, string.format("<金>突破成功！你已进入【%s】！</金>", newName))
        -- 任务系统：境界突破
        Quest.OnBreakthrough(pd, conn)

        resultData["Success"] = Variant(true)
        resultData["Msg"]     = Variant(string.format("突破成功！进入%s", newName))
        resultData["Realm"]   = Variant(newRealm)
        resultData["Layer"]   = Variant(newLayer)
    else
        -- 突破失败：累加保底计数
        pd.breakthrough_fails = (pd.breakthrough_fails or 0) + 1
        Activity.OnBreakFail(pd)
        local failMsg = string.format("突破失败，丹药消散于天地间。（保底累积：+%d%%）", pd.breakthrough_fails * 10)
        -- 掉层判定（灵石保护可跳过）
        if not isProtected then
            local dropRoll = math.random()
            if dropRoll <= Settings.REALM.FAILURE.DROP_LAYER_CHANCE then
                if layer > 1 then
                    pd.realm_layer = layer - 1
                    failMsg = failMsg .. string.format(" 境界跌落至%s！", Settings.REALM.GetDisplayName(realm, pd.realm_layer))
                end
            end
            -- 经验损失
            pd.realm_exp = math.floor((pd.realm_exp or 0) * (1 - Settings.REALM.FAILURE.EXP_LOSS_RATIO))
        else
            failMsg = failMsg .. " 灵石保护生效，境界和经验未受损失！"
        end
        pd.level = Settings.REALM.CalcPowerLevel(pd.realm or 1, pd.realm_layer or 1)

        Server.PushLog(conn, "<红>" .. failMsg .. "</红>")

        resultData["Success"] = Variant(false)
        resultData["Msg"]     = Variant(failMsg)
        resultData["Realm"]   = Variant(pd.realm or 1)
        resultData["Layer"]   = Variant(pd.realm_layer or 1)
    end

    conn:SendRemoteEvent(Settings.EVENTS.PUSH_BREAKTHROUGH, true, resultData)
    Server.PushPlayerData(uid, conn)
    Server.PushInventory(uid, conn)
    Server.SavePlayerData(uid)
end

-- ============================================================================
-- 修为丹系统（药铺购买 + 服用加速修为）
-- ============================================================================

-- 请求修为丹商店列表
function Server_OnReqRealmPillShop(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    -- 检查是否在扬州
    if (pd.scene or "") ~= "main_city" then
        Server.PushLog(conn, "<红>需要在扬州城才能查看修为丹商铺。</红>")
        return
    end

    -- 获取今日已用次数
    local today = os.date("%Y%m%d")
    if not pd.realm_pill_daily then pd.realm_pill_daily = {} end
    if pd.realm_pill_daily.date ~= today then
        pd.realm_pill_daily = { date = today, used = 0 }
    end

    local pills = {}
    for i, pill in ipairs(Settings.REALM_EXP_PILLS.PILLS) do
        -- 查找该丹药对应的境界索引和名称
        local realmIdx = i  -- PILLS 索引就是境界索引
        local stage = Settings.REALM.STAGES[realmIdx]
        table.insert(pills, {
            index = i,
            id = pill.id,
            name = pill.name,
            realm_index = realmIdx,
            realm_name = stage and stage.name or "",
            exp = pill.exp,
            cost = pill.cost_spirit,
        })
    end

    local data = VariantMap()
    data["PillsJson"]   = Variant(cjson.encode(pills))
    data["DailyUsed"]   = Variant(pd.realm_pill_daily.used or 0)
    data["DailyLimit"]  = Variant(Settings.REALM_EXP_PILLS.DAILY_USE_LIMIT)
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_REALM_PILL_SHOP, true, data)
end

-- 购买修为丹（存入背包，花灵石）
function Server_OnReqBuyRealmPill(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local pillIndex = eventData["PillIndex"]:GetInt()
    local pillDef = Settings.REALM_EXP_PILLS.PILLS[pillIndex]
    if not pillDef then
        Server.PushLog(conn, "<红>无效的丹药选择。</红>")
        return
    end

    -- 检查是否在扬州
    if (pd.scene or "") ~= "main_city" then
        Server.PushLog(conn, "<红>需要在扬州城才能购买修为丹。</红>")
        return
    end

    -- 检查灵石
    local cost = pillDef.cost_spirit
    if (pd.spirit_stone or 0) < cost then
        Server.PushLog(conn, string.format("<红>灵石不足，需要 %d 灵石。（当前：%d）</红>", cost, pd.spirit_stone or 0))
        return
    end

    -- 扣灵石，加背包
    pd.spirit_stone = (pd.spirit_stone or 0) - cost
    if not pd.inventory then pd.inventory = {} end
    table.insert(pd.inventory, {
        id = pillDef.id,
        name = pillDef.name,
        type = "realm_pill",
        realm_index = pillIndex,
        exp = pillDef.exp,
    })

    Server.PushLog(conn, string.format("<绿>购买【%s】×1，花费 %d 灵石。</绿>", pillDef.name, cost))

    local resultData = VariantMap()
    resultData["Ok"]     = Variant(true)
    resultData["Msg"]    = Variant(string.format("购买%s×1", pillDef.name))
    resultData["Action"] = Variant("buy")
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_REALM_PILL_RESULT, true, resultData)

    Server.PushPlayerData(uid, conn)
    Server.PushInventory(uid, conn)
    Server.SavePlayerData(uid)
end

-- 服用修为丹（从背包消耗，加经验，每日限制5次）
function Server_OnReqUseRealmPill(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local pillIndex = eventData["PillIndex"]:GetInt()
    local pillDef = Settings.REALM_EXP_PILLS.PILLS[pillIndex]
    if not pillDef then
        Server.PushLog(conn, "<红>无效的丹药选择。</红>")
        return
    end

    -- 每日服用次数检查
    local today = os.date("%Y%m%d")
    if not pd.realm_pill_daily then pd.realm_pill_daily = {} end
    if pd.realm_pill_daily.date ~= today then
        pd.realm_pill_daily = { date = today, used = 0 }
    end
    local hasUnlimitedPill = pd.debug_flags and pd.debug_flags.dbg_unlimited_pill
    if not hasUnlimitedPill and (pd.realm_pill_daily.used or 0) >= Settings.REALM_EXP_PILLS.DAILY_USE_LIMIT then
        Server.PushLog(conn, string.format("<红>今日修为丹服用次数已达上限（%d/%d）。</红>",
            pd.realm_pill_daily.used, Settings.REALM_EXP_PILLS.DAILY_USE_LIMIT))
        return
    end

    -- 只能服用当前境界对应的修为丹
    local currentRealm = pd.realm or 1
    if pillIndex ~= currentRealm then
        local currentStageName = Settings.REALM.STAGES[currentRealm] and Settings.REALM.STAGES[currentRealm].name or "未知"
        Server.PushLog(conn, string.format("<红>【%s】不适合你当前的境界（%s期），无法服用。</红>", pillDef.name, currentStageName))
        return
    end

    -- 检查背包是否有该丹药
    local itemIdx = nil
    for i, item in ipairs(pd.inventory or {}) do
        if item.id == pillDef.id then
            itemIdx = i
            break
        end
    end
    if not itemIdx then
        Server.PushLog(conn, string.format("<红>你没有【%s】，请先购买。</红>", pillDef.name))
        return
    end

    -- 已满级不可服用
    if Settings.REALM.IsMaxRealm(pd.realm or 1, pd.realm_layer or 1) then
        Server.PushLog(conn, "<红>你已达到最高境界，无需服用修为丹。</红>")
        return
    end

    -- 当前境界最末层且经验已满，不能再服用（需要先突破）
    local stage = Settings.REALM.STAGES[currentRealm]
    local layer = pd.realm_layer or 1
    local needed = Settings.REALM.GetExpNeeded(currentRealm, layer)
    if layer >= stage.layers and (pd.realm_exp or 0) >= needed then
        Server.PushLog(conn, "<红>修为已满，请先突破至下一境界再服用。</红>")
        return
    end

    -- 消耗丹药 + 增加经验 + 增加每日计数
    table.remove(pd.inventory, itemIdx)
    pd.realm_pill_daily.used = (pd.realm_pill_daily.used or 0) + 1
    pd.realm_exp = (pd.realm_exp or 0) + pillDef.exp

    -- 检查升层（可能自动升重）
    Server.CheckRealmExp(pd)

    local newName = Settings.REALM.GetDisplayName(pd.realm or 1, pd.realm_layer or 1)
    Server.PushLog(conn, string.format("<绿>服用【%s】，获得 %d 修为经验！（今日 %d/%d）当前：%s</绿>",
        pillDef.name, pillDef.exp, pd.realm_pill_daily.used, Settings.REALM_EXP_PILLS.DAILY_USE_LIMIT, newName))

    -- 推送结果
    local resultData = VariantMap()
    resultData["Ok"]     = Variant(true)
    resultData["Msg"]    = Variant(string.format("服用%s，获得%d修为", pillDef.name, pillDef.exp))
    resultData["Action"] = Variant("use")
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_REALM_PILL_RESULT, true, resultData)

    Server.PushPlayerData(uid, conn)
    Server.PushInventory(uid, conn)
    Server.SavePlayerData(uid)
end

-- ============================================================================
-- 炼丹系统（仅丹宗弟子可用）
-- ============================================================================

function Server_OnReqAlchemyCraft(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    -- 只有器丹宗弟子可以炼丹
    if pd.sect ~= "qidan_sect" then
        Server.PushLog(conn, "<红>只有器丹宗弟子才能炼丹。</红>")
        return
    end

    local recipeId = eventData["RecipeId"]:GetString()
    local recipe = Settings.ALCHEMY_RECIPES[recipeId]
    if not recipe then
        Server.PushLog(conn, "<红>未知的丹方。</红>")
        return
    end

    -- 检查炼丹等级
    local alchemyLevel = pd.alchemy_level or 0
    if alchemyLevel < recipe.min_skill_level then
        Server.PushLog(conn, string.format("<红>炼丹等级不足，需要%d级。</红>", recipe.min_skill_level))
        return
    end

    -- 检查材料
    for _, mat in ipairs(recipe.materials) do
        local count = 0
        for _, item in ipairs(pd.inventory or {}) do
            if item.id == mat.id then
                count = count + (item.count or 1)
            end
        end
        if count < mat.count then
            local matDef = Settings.ALCHEMY_MATERIALS[mat.id]
            local matName = matDef and matDef.name or mat.id
            Server.PushLog(conn, string.format("<红>材料不足：【%s】需要%d，持有%d。</红>", matName, mat.count, count))
            return
        end
    end

    -- 扣除材料
    for _, mat in ipairs(recipe.materials) do
        local remaining = mat.count
        for i = #(pd.inventory or {}), 1, -1 do
            if remaining <= 0 then break end
            local item = pd.inventory[i]
            if item.id == mat.id then
                local have = item.count or 1
                if have <= remaining then
                    remaining = remaining - have
                    table.remove(pd.inventory, i)
                else
                    item.count = have - remaining
                    remaining = 0
                end
            end
        end
    end

    -- 炼丹成功率判定
    local successRate = recipe.success_rate
    -- 炼丹分支技能加成（每级 +5% 成功率）
    for _, sk in ipairs(pd.skills or {}) do
        local def = Shared.GetSkillDef(sk.id)
        if def and def.branch == "pill" then
            successRate = successRate + 0.05 * (sk.proficiency or 0) / (def.max_proficiency or 100)
        end
    end
    successRate = math.min(0.99, successRate)

        -- ★ 炼丹保底机制：每次失败+5%成功率，连续9次失败后第10次必成功
        if not pd.alchemy_fails then pd.alchemy_fails = {} end
        local alchFails = pd.alchemy_fails[recipeId] or 0
        local pityBonus = alchFails * 0.05
        successRate = math.min(1.0, successRate + pityBonus)

    local resultData = VariantMap()
    local roll = math.random()

    if roll <= successRate then
        -- 炼丹成功
        local yield = math.random(recipe.yield.min, recipe.yield.max)
        pd.alchemy_fails[recipeId] = 0  -- 成功重置保底
        -- 添加丹药到背包
        for _ = 1, yield do
            table.insert(pd.inventory, { id = recipeId, count = 1, type = "pill" })
        end
        -- 增加炼丹经验
        pd.alchemy_exp = (pd.alchemy_exp or 0) + recipe.exp_gain
        -- 检查炼丹升级（每100经验升1级，上限5级）
        pd.alchemy_level = math.min(5, math.floor((pd.alchemy_exp or 0) / 100) + 1)

        local pillDef = Settings.PILLS[recipeId]
        local pillName = pillDef and pillDef.name or recipe.name
        Server.PushLog(conn, string.format("<绿>炼丹成功！获得【%s】×%d</绿>", pillName, yield))

        resultData["Success"] = Variant(true)
        resultData["PillId"]  = Variant(recipeId)
        resultData["Count"]   = Variant(yield)
        resultData["Msg"]     = Variant(string.format("炼制成功！获得%s×%d", pillName, yield))
    else
        -- 炼丹失败（材料已消耗）
        pd.alchemy_fails[recipeId] = (pd.alchemy_fails[recipeId] or 0) + 1  -- 失败累计保底
        -- 失败也给少量经验
        pd.alchemy_exp = (pd.alchemy_exp or 0) + math.floor(recipe.exp_gain * 0.3)
        pd.alchemy_level = math.min(5, math.floor((pd.alchemy_exp or 0) / 100) + 1)

        Server.PushLog(conn, "<红>炼丹失败！丹炉中灵药化为灰烬……</红>")

        resultData["Success"] = Variant(false)
        resultData["PillId"]  = Variant(recipeId)
        resultData["Count"]   = Variant(0)
        resultData["Msg"]     = Variant("炼丹失败，材料已损耗")
    end

    conn:SendRemoteEvent(Settings.EVENTS.PUSH_ALCHEMY_RESULT, true, resultData)
    Server.PushPlayerData(uid, conn)
    Server.PushInventory(uid, conn)
    Server.SavePlayerData(uid)
end

-- ============================================================================
-- 购买炼丹材料（丹宗材料库NPC）
-- ============================================================================

function Server_OnReqBuyMaterial(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    -- 仅器丹宗弟子，且在器丹宗场景
    if pd.sect ~= "qidan_sect" then
        Server.PushLog(conn, "<红>只有器丹宗弟子才能在此购买材料。</红>")
        return
    end

    local matId = eventData["MaterialId"]:GetString()
    local count = eventData["Count"]:GetInt()
    if count <= 0 then count = 1 end

    -- 检查商店是否出售
    local shopItem = nil
    for _, si in ipairs(Settings.ALCHEMY_MATERIAL_SHOP) do
        if si.id == matId then
            shopItem = si
            break
        end
    end
    if not shopItem then
        Server.PushLog(conn, "<红>该材料不在商店出售范围内。</红>")
        return
    end

    -- 背包容量
    if #(pd.inventory or {}) >= Settings.INVENTORY_MAX then
        Server.PushLog(conn, "<红>背包已满！</红>")
        return
    end

    local totalCost = shopItem.price * count
    if (pd.silver or 0) < totalCost then
        Server.PushLog(conn, string.format("<红>银两不足，需要 %d 银两。</红>", totalCost))
        return
    end

    pd.silver = pd.silver - totalCost
    -- 合并到背包（堆叠）
    local found = false
    for _, item in ipairs(pd.inventory or {}) do
        if item.id == matId then
            item.count = (item.count or 1) + count
            found = true
            break
        end
    end
    if not found then
        table.insert(pd.inventory, { id = matId, count = count, type = "material" })
    end

    local matDef = Settings.ALCHEMY_MATERIALS[matId]
    local matName = matDef and matDef.name or matId
    Server.PushLog(conn, string.format("<绿>购买【%s】×%d，花费 %d 银两。</绿>", matName, count, totalCost))
    Server.PushPlayerData(uid, conn)
    Server.PushInventory(uid, conn)
    Server.SavePlayerData(uid)
end

-- ============================================================================
-- 域外战场：进入层数验证
-- ============================================================================

function Server_OnReqEnterLayer(eventType, eventData)
    print("[BF-DIAG-S] ═══ Server_OnReqEnterLayer 收到请求！ ═══")
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then print("[BF-DIAG-S] ✖ pd为空! uid=" .. tostring(uid)); return end

    local layerNum = eventData["Layer"]:GetInt()
    print("[BF-DIAG-S] uid=" .. tostring(uid) .. " layer=" .. tostring(layerNum))
    print("[BF-DIAG-S]   pd.scene=" .. tostring(pd.scene) .. " pd.spot=" .. tostring(pd.spot))
    print("[BF-DIAG-S]   pd.in_battle=" .. tostring(pd.in_battle) .. " pd._battlePvpData=" .. tostring(pd._battlePvpData ~= nil))
    local layerCfg = Settings.BATTLEFIELD_LAYERS[layerNum]
    if not layerCfg then
        Server.PushLog(conn, "<红>无效的层数。</红>")
        return
    end

    -- Boss 层锁检查：超过 max_battlefield_layer 的层不可进入
    local maxLayer = pd.max_battlefield_layer or Settings.BATTLEFIELD_INITIAL_LAYERS
    if layerNum > maxLayer then
        local bossDef = Settings.BOSS_BY_LAYER[maxLayer]
        local bossName = bossDef and bossDef.name or "守关首领"
        Server.PushLog(conn, string.format(
            "<红>前方被【%s】阻挡！击败它才能继续深入。</红>", bossName
        ))
        local resData = VariantMap()
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("首领未击败")
        conn:SendRemoteEvent(Settings.EVENTS.RES_ENTER_LAYER, true, resData)
        return
    end

    -- 境界限制已由 Boss 门替代（上方 maxLayer 检查）

    -- 帮会层检查（第3/8层是帮会区，仍然可以进入）
    -- 自动切换场景到域外战场（支持从任意地点直接进入）
    if pd.scene ~= "battlefield" then
        pd.scene = "battlefield"
    end
    -- 切换到对应层的 spot
    local spotId = "layer_" .. tostring(layerNum)
    pd.spot = spotId

    Server.PushLog(conn, string.format("<绿>进入【%s】</绿>", layerCfg.name))

    -- 任务系统：进入战场层
    Quest.OnEnterLayer(pd, conn, layerNum)

    local resData = VariantMap()
    resData["Success"] = Variant(true)
    resData["Layer"]   = Variant(layerNum)
    resData["Name"]    = Variant(layerCfg.name)
    resData["Desc"]    = Variant(layerCfg.desc)
    print("[BF-DIAG-S] ✓ 发送 RES_ENTER_LAYER Success=true layer=" .. tostring(layerNum))
    conn:SendRemoteEvent(Settings.EVENTS.RES_ENTER_LAYER, true, resData)
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)

    -- 大地图：加入层状态并发送快照
    Server.MapPlayerEnterLayer(uid, layerNum, conn)
end

-- ============================================================================
-- 域外战场·大地图位置同步
-- ============================================================================

-- 层状态: layerState_[layerNum] = { players = { [uid] = {x, y, name, guild} } }
layerState_ = {}
-- ═══════════════════════════════════════════════════════════════════
-- MonsterManager: 服务端驱动的怪物刷新、巡逻移动、碰撞检测、广播系统
-- ═══════════════════════════════════════════════════════════════════

-- layerMonsters_[layerNum] = { [uid] = monsterState }
-- monsterState = { uid, monId, x, y, alive, spawnX, spawnY, zoneIdx,
--                  patrolTargetX, patrolTargetY, patrolPause, moving }
local layerMonsters_ = {}
-- 刷新队列: layerRespawnQueue_[layerNum] = { {timer, zoneIdx} ... }
local layerRespawnQueue_ = {}
-- 怪物 UID 计数器
local monsterUidCounter_ = 0

-- 位置广播计时
local mapSyncTimer_ = 0
local MAP_SYNC_INTERVAL = 0.2  -- 200ms 广播玩家位置
local monsterSyncTimer_ = 0

-- 生成唯一怪物 UID
local function GenMonsterUid()
    monsterUidCounter_ = monsterUidCounter_ + 1
    return "mon_" .. monsterUidCounter_
end

-- 在刷怪区中随机一个位置（避开玩家）
local function RandPosInZone(zone, layerNum)
    local cfg = Settings.BATTLEFIELD_MAP
    local safeDist = cfg.MONSTER_SAFE_SPAWN_DIST or 150
    local players = layerState_[layerNum] and layerState_[layerNum].players or {}
    for attempt = 1, 10 do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * zone.radius
        local x = zone.cx + math.cos(angle) * dist
        local y = zone.cy + math.sin(angle) * dist
        -- 边界钳制
        x = math.max(30, math.min(cfg.MAP_WIDTH - 30, x))
        y = math.max(30, math.min(cfg.MAP_HEIGHT - 30, y))
        -- 检查是否离玩家太近
        local tooClose = false
        for _, p in pairs(players) do
            local dx, dy = x - p.x, y - p.y
            if dx * dx + dy * dy < safeDist * safeDist then
                tooClose = true
                break
            end
        end
        if not tooClose then return x, y end
    end
    -- 10 次都失败，退回到区域中心
    return zone.cx, zone.cy
end

-- 随机巡逻目标点（在 spawnX/Y 附近 PATROL_RADIUS 内）
local function RandPatrolTarget(mon)
    local cfg = Settings.BATTLEFIELD_MAP
    local radius = cfg.MONSTER_PATROL_RADIUS or 120
    local angle = math.random() * math.pi * 2
    local dist = math.random() * radius
    local tx = mon.spawnX + math.cos(angle) * dist
    local ty = mon.spawnY + math.sin(angle) * dist
    -- 边界钳制
    tx = math.max(30, math.min(cfg.MAP_WIDTH - 30, tx))
    ty = math.max(30, math.min(cfg.MAP_HEIGHT - 30, ty))
    return tx, ty
end

-- 创建一只怪物
local function SpawnMonster(layerNum, zone, zoneIdx)
    local uid = GenMonsterUid()
    local x, y = RandPosInZone(zone, layerNum)
    local tx, ty = RandPatrolTarget({ spawnX = x, spawnY = y })
    local mon = {
        uid       = uid,
        monId     = zone.monId,
        x         = x,
        y         = y,
        alive     = true,
        spawnX    = x,
        spawnY    = y,
        zoneIdx   = zoneIdx,
        patrolTargetX = tx,
        patrolTargetY = ty,
        patrolPause   = 0,  -- 暂停计时器
        moving        = true,
    }
    if not layerMonsters_[layerNum] then layerMonsters_[layerNum] = {} end
    layerMonsters_[layerNum][uid] = mon
    return mon
end

-- 初始化层的怪物（从 spawnZones 生成）
local function InitLayerMonsters(layerNum)
    if layerMonsters_[layerNum] then return end  -- 已初始化
    layerMonsters_[layerNum] = {}
    layerRespawnQueue_[layerNum] = {}
    local mapCfg = Settings.BATTLEFIELD_MAP[layerNum]
    if not mapCfg or not mapCfg.spawnZones then return end
    for zoneIdx, zone in ipairs(mapCfg.spawnZones) do
        for i = 1, (zone.count or 3) do
            SpawnMonster(layerNum, zone, zoneIdx)
        end
    end
    print(string.format("[MonsterMgr] Layer %d initialized, monsters spawned", layerNum))
end

-- 怪物 AI Tick：巡逻移动 + 碰撞检测
function Server.MonsterTick(dt)
    local cfg = Settings.BATTLEFIELD_MAP
    local moveSpeed = cfg.MONSTER_MOVE_SPEED or 50
    local pauseRange = cfg.MONSTER_PATROL_PAUSE or {1.5, 3.0}
    local triggerRadius = cfg.MONSTER_TRIGGER_RADIUS or 35

    for layerNum, monsters in pairs(layerMonsters_) do
        local state = layerState_[layerNum]
        if not state then goto nextLayer end
        local players = state.players

        -- 1) 移动每只活着的怪物
        for uid, mon in pairs(monsters) do
            if not mon.alive then goto nextMon end

            if mon.patrolPause > 0 then
                -- 暂停中
                mon.patrolPause = mon.patrolPause - dt
                if mon.patrolPause <= 0 then
                    -- 选新巡逻目标
                    mon.patrolTargetX, mon.patrolTargetY = RandPatrolTarget(mon)
                    mon.moving = true
                end
            else
                -- 向目标移动
                local dx = mon.patrolTargetX - mon.x
                local dy = mon.patrolTargetY - mon.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < 5 then
                    -- 到达目标，进入暂停
                    mon.moving = false
                    mon.patrolPause = pauseRange[1] + math.random() * (pauseRange[2] - pauseRange[1])
                else
                    local step = moveSpeed * dt
                    if step > dist then step = dist end
                    mon.x = mon.x + (dx / dist) * step
                    mon.y = mon.y + (dy / dist) * step
                end
            end

            -- 2) 碰撞检测已禁用：改为玩家手动点击怪物才触发（REQ_START_BATTLE）

            ::nextMon::
        end

        -- 3) 处理刷新队列
        local respawnQueue = layerRespawnQueue_[layerNum]
        if respawnQueue then
            local mapCfg = cfg[layerNum]
            local i = 1
            while i <= #respawnQueue do
                local entry = respawnQueue[i]
                entry.timer = entry.timer - dt
                if entry.timer <= 0 then
                    -- 刷出新怪
                    if mapCfg and mapCfg.spawnZones and mapCfg.spawnZones[entry.zoneIdx] then
                        local zone = mapCfg.spawnZones[entry.zoneIdx]
                        local newMon = SpawnMonster(layerNum, zone, entry.zoneIdx)
                        -- 通知同层玩家
                        local spawnData = VariantMap()
                        spawnData["Uid"]   = Variant(newMon.uid)
                        spawnData["X"]     = Variant(newMon.x)
                        spawnData["Y"]     = Variant(newMon.y)
                        spawnData["MonId"] = Variant(newMon.monId)
                        for pUid, _ in pairs(players) do
                            local c = connections_[pUid]
                            if c then
                                c:SendRemoteEvent(Settings.EVENTS.NOTIFY_MONSTER_SPAWN, true, spawnData)
                            end
                        end
                    end
                    table.remove(respawnQueue, i)
                else
                    i = i + 1
                end
            end
        end

        ::nextLayer::
    end
end

-- 怪物位置广播（周期性批量同步）
function Server.MonsterSyncTick(dt)
    local cfg = Settings.BATTLEFIELD_MAP
    monsterSyncTimer_ = monsterSyncTimer_ + dt
    if monsterSyncTimer_ < (cfg.MONSTER_SYNC_INTERVAL or 0.3) then return end
    monsterSyncTimer_ = 0

    for layerNum, monsters in pairs(layerMonsters_) do
        local state = layerState_[layerNum]
        if not state then goto nextLayer2 end
        -- 计算在线玩家数
        local playerCount = 0
        for _ in pairs(state.players) do playerCount = playerCount + 1 end
        if playerCount == 0 then goto nextLayer2 end

        -- 序列化怪物数据: uid|x|y|monId|alive\n...
        local lines = {}
        for uid, mon in pairs(monsters) do
            lines[#lines + 1] = string.format("%s|%.0f|%.0f|%s|%s",
                uid, mon.x, mon.y, mon.monId, mon.alive and "1" or "0")
        end
        if #lines == 0 then goto nextLayer2 end

        local syncData = VariantMap()
        syncData["Data"] = Variant(table.concat(lines, "\n"))
        for pUid, _ in pairs(state.players) do
            local conn = connections_[pUid]
            if conn then
                conn:SendRemoteEvent(Settings.EVENTS.NOTIFY_MONSTER_SYNC, true, syncData)
            end
        end

        ::nextLayer2::
    end
end

-- 标记怪物被击杀（由战斗结束回调调用）
function Server.MapMonsterKilled(layerNum, monsterUid)
    if not layerMonsters_[layerNum] then return end
    local mon = layerMonsters_[layerNum][monsterUid]
    if not mon then return end

    mon.alive = false

    -- 通知同层所有玩家
    if layerState_[layerNum] then
        local notifyData = VariantMap()
        notifyData["MonsterUid"] = Variant(monsterUid)
        for uid, _ in pairs(layerState_[layerNum].players) do
            local conn = connections_[uid]
            if conn then
                conn:SendRemoteEvent(Settings.EVENTS.NOTIFY_MONSTER_DEAD, true, notifyData)
            end
        end
    end

    -- 加入刷新队列
    if not layerRespawnQueue_[layerNum] then layerRespawnQueue_[layerNum] = {} end
    table.insert(layerRespawnQueue_[layerNum], {
        timer = Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY or 6.0,
        zoneIdx = mon.zoneIdx,
    })

    -- 移除死怪
    layerMonsters_[layerNum][monsterUid] = nil
end

-- 玩家进入某层
function Server.MapPlayerEnterLayer(uid, layerNum, conn)
    -- 离开旧层
    Server.MapPlayerLeaveLayer(uid)

    -- 确保层状态存在
    if not layerState_[layerNum] then
        layerState_[layerNum] = { players = {} }
    end
    InitLayerMonsters(layerNum)

    -- 获取出生点
    local mapCfg = Settings.BATTLEFIELD_MAP[layerNum]
    local spawnX = mapCfg and mapCfg.spawn and mapCfg.spawn.x or 800
    local spawnY = mapCfg and mapCfg.spawn and mapCfg.spawn.y or 600

    local pd = players_[uid]
    local playerName = pd and pd.name or "?"
    local guildName = ""
    if pd and pd.guild_id and pd.guild_id ~= "" and guilds_[pd.guild_id] then
        guildName = guilds_[pd.guild_id].name
    end

    -- 记录到层状态
    layerState_[layerNum].players[uid] = {
        x = spawnX, y = spawnY,
        name = playerName, guild = guildName,
        layer = layerNum,
    }

    -- 标记玩家当前层
    if pd then pd.map_layer = layerNum end

    -- 通知同层其他玩家
    local enterData = VariantMap()
    enterData["Uid"]   = Variant(uid)
    enterData["X"]     = Variant(spawnX)
    enterData["Y"]     = Variant(spawnY)
    enterData["Name"]  = Variant(playerName)
    enterData["Guild"] = Variant(guildName)
    for otherUid, _ in pairs(layerState_[layerNum].players) do
        if otherUid ~= uid then
            local otherConn = connections_[otherUid]
            if otherConn then
                otherConn:SendRemoteEvent(Settings.EVENTS.NOTIFY_PLAYER_ENTER, true, enterData)
            end
        end
    end

    -- 发送层快照给该玩家
    Server.SendLayerSnapshot(uid, layerNum, conn)

    -- 如果帮会数据尚未加载完成，标记需要补发（LoadGuildData 回调中会处理）
    if not guildDataLoaded_ then
        if not pendingSnapshotResend_ then pendingSnapshotResend_ = {} end
        pendingSnapshotResend_[uid] = { layer = layerNum, conn = conn }
        print(string.format("[Server] 帮会数据未就绪，标记补发: uid=%s layer=%d", tostring(uid), layerNum))
    end
end

-- 玩家离开层
function Server.MapPlayerLeaveLayer(uid)
    local pd = players_[uid]
    local oldLayer = pd and pd.map_layer or nil
    if not oldLayer or not layerState_[oldLayer] then return end

    layerState_[oldLayer].players[uid] = nil
    if pd then pd.map_layer = nil end

    -- 通知同层其他玩家
    local leaveData = VariantMap()
    leaveData["Uid"] = Variant(uid)
    for otherUid, _ in pairs(layerState_[oldLayer].players) do
        local otherConn = connections_[otherUid]
        if otherConn then
            otherConn:SendRemoteEvent(Settings.EVENTS.NOTIFY_PLAYER_LEAVE, true, leaveData)
        end
    end
end

-- 发送层快照（所有玩家位置 + 怪物状态 + 据点归属）
function Server.SendLayerSnapshot(uid, layerNum, conn)
    local state = layerState_[layerNum]
    if not state then return end

    -- 序列化同层玩家: uid|x|y|name|guild\n...
    local playerLines = {}
    for pUid, pData in pairs(state.players) do
        if pUid ~= uid then  -- 不含自己
            playerLines[#playerLines + 1] = string.format("%s|%.0f|%.0f|%s|%s",
                pUid, pData.x, pData.y, pData.name, pData.guild)
        end
    end

    -- 序列化怪物（新格式）: uid|x|y|monId|alive\n...
    local monsterLines = {}
    if layerMonsters_[layerNum] then
        for mUid, mon in pairs(layerMonsters_[layerNum]) do
            monsterLines[#monsterLines + 1] = string.format("%s|%.0f|%.0f|%s|%s",
                mUid, mon.x, mon.y, mon.monId, mon.alive and "1" or "0")
        end
    end

    -- 序列化据点归属: spId|guildName|guildId\n...
    local spLines = {}
    local mapCfg = Settings.BATTLEFIELD_MAP[layerNum]
    -- 构建据点所有权索引（tostring统一key类型）
    local spOwnerLookup = {}
    for k, v in pairs(strongpointOwners_) do
        spOwnerLookup[tostring(k)] = v
    end
    if mapCfg and mapCfg.strongpoints then
        for _, sp in ipairs(mapCfg.strongpoints) do
            local owner = spOwnerLookup[tostring(sp.id)]
            local ownerName = (owner and owner.guild_name and owner.guild_name ~= "") and owner.guild_name or ""
            local ownerId = (owner and owner.guild_id) and owner.guild_id or ""
            spLines[#spLines + 1] = string.format("%s|%s|%s", sp.id, ownerName, ownerId)
        end
    end

    local snapData = VariantMap()
    snapData["Layer"]       = Variant(layerNum)
    snapData["Players"]     = Variant(table.concat(playerLines, "\n"))
    snapData["Monsters"]    = Variant(table.concat(monsterLines, "\n"))
    snapData["Strongpoints"]= Variant(table.concat(spLines, "\n"))
    conn:SendRemoteEvent(Settings.EVENTS.RES_LAYER_SNAPSHOT, true, snapData)
end

-- 处理玩家移动请求
function Server_OnReqMapMove(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local layerNum = pd.map_layer
    if not layerNum or not layerState_[layerNum] then return end

    local pState = layerState_[layerNum].players[uid]
    if not pState then return end

    local targetX = eventData["X"]:GetFloat()
    local targetY = eventData["Y"]:GetFloat()

    -- 边界钳制
    local mapW = Settings.BATTLEFIELD_MAP.MAP_WIDTH
    local mapH = Settings.BATTLEFIELD_MAP.MAP_HEIGHT
    targetX = math.max(0, math.min(mapW, targetX))
    targetY = math.max(0, math.min(mapH, targetY))

    -- 速度校验（防作弊：距离不能超过合理范围）
    local dx = targetX - pState.x
    local dy = targetY - pState.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local maxDist = Settings.BATTLEFIELD_MAP.MOVE_SPEED * 2  -- 允许 2s 的移动量作为容差
    if dist > maxDist then
        -- 限制到最大合理距离
        local ratio = maxDist / dist
        targetX = pState.x + dx * ratio
        targetY = pState.y + dy * ratio
    end

    -- 更新位置
    pState.x = targetX
    pState.y = targetY
end

-- 大地图位置广播（在 Server_OnUpdate 中每帧调用）
function Server.MapSyncTick(dt)
    mapSyncTimer_ = mapSyncTimer_ + dt
    if mapSyncTimer_ < MAP_SYNC_INTERVAL then return end
    mapSyncTimer_ = 0

    -- 对每个有玩家的层进行广播
    for layerNum, state in pairs(layerState_) do
        local playerList = state.players
        -- 计算在线人数
        local count = 0
        for _ in pairs(playerList) do count = count + 1 end
        if count < 2 then goto continue end  -- 只有 1 人不需要广播

        -- 对每个玩家发送其他人的位置
        for uid, _ in pairs(playerList) do
            local conn = connections_[uid]
            if conn then
                -- 批量打包其他玩家位置: uid|x|y\n...
                local lines = {}
                for otherUid, otherData in pairs(playerList) do
                    if otherUid ~= uid then
                        lines[#lines + 1] = string.format("%s|%.0f|%.0f",
                            otherUid, otherData.x, otherData.y)
                    end
                end
                if #lines > 0 then
                    local posData = VariantMap()
                    posData["Data"] = Variant(table.concat(lines, "\n"))
                    conn:SendRemoteEvent(Settings.EVENTS.NOTIFY_PLAYER_POS, true, posData)
                end
            end
        end

        ::continue::
    end
end



-- 玩家断线时清理大地图状态
function Server.MapPlayerDisconnect(uid)
    Server.MapPlayerLeaveLayer(uid)
end

-- ============================================================================
-- 新炼器系统（所有门派可用）
-- ============================================================================

--- 返回玩家当前境界可购买的图纸列表
function Server_OnReqBlueprintList(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local realmIndex = pd.realm or 1
    local learned = pd.blueprints_learned or {}
    local list = {}
    for bpId, bp in pairs(Settings.BLUEPRINTS) do
        if realmIndex >= bp.realm_req then
            list[#list + 1] = {
                id       = bpId,
                name     = bp.name,
                tier     = bp.tier,
                slot     = bp.slot,
                price    = bp.price,
                learned  = learned[bpId] and true or false,
            }
        end
    end

    local resData = VariantMap()
    resData["DataJson"] = Variant(cjson.encode(list))
    conn:SendRemoteEvent(StringHash(Settings.EVENTS.RES_BLUEPRINT_LIST), true, resData)
end

--- 购买/学习一张图纸
function Server_OnReqBuyBlueprint(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local bpId = eventData["BlueprintId"]:GetString()
    local bp = Settings.BLUEPRINTS[bpId]
    local resData = VariantMap()

    if not bp then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("图纸不存在")
        resData["BlueprintId"] = Variant(bpId)
        conn:SendRemoteEvent(Settings.EVENTS.RES_BUY_BLUEPRINT, true, resData)
        return
    end

    -- 境界检查
    if (pd.realm or 1) < bp.realm_req then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("境界不足，无法购买此图纸")
        resData["BlueprintId"] = Variant(bpId)
        conn:SendRemoteEvent(Settings.EVENTS.RES_BUY_BLUEPRINT, true, resData)
        return
    end

    -- 已购买检查
    if not pd.blueprints_learned then pd.blueprints_learned = {} end
    if pd.blueprints_learned[bpId] then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("已购买此图纸")
        resData["BlueprintId"] = Variant(bpId)
        conn:SendRemoteEvent(Settings.EVENTS.RES_BUY_BLUEPRINT, true, resData)
        return
    end

    -- 银两检查
    if (pd.silver or 0) < bp.price then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant(string.format("银两不足（需要%s）", Shared.FormatSilver(bp.price)))
        resData["BlueprintId"] = Variant(bpId)
        conn:SendRemoteEvent(Settings.EVENTS.RES_BUY_BLUEPRINT, true, resData)
        return
    end

    -- 扣银两，购买图纸
    pd.silver = pd.silver - bp.price
    pd.blueprints_learned[bpId] = true

    resData["Success"] = Variant(true)
    resData["Msg"]     = Variant(string.format("成功购买【%s】", bp.name))
    resData["BlueprintId"] = Variant(bpId)
    conn:SendRemoteEvent(Settings.EVENTS.RES_BUY_BLUEPRINT, true, resData)

    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid, pd)
end

--- 新炼器：批量锻造装备
function Server_OnReqForgeNew(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local bpId  = eventData["BlueprintId"]:GetString()
    local count = eventData["Count"]:GetInt()
    count = math.max(1, math.min(10, count))  -- 限制 1~10

    local bp = Settings.BLUEPRINTS[bpId]
    local resData = VariantMap()

    if not bp then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("图纸不存在")
        resData["Items"]   = Variant("")
        conn:SendRemoteEvent(Settings.EVENTS.RES_FORGE_NEW, true, resData)
        return
    end

    -- 是否已购买
    if not pd.blueprints_learned or not pd.blueprints_learned[bpId] then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("尚未购买此图纸")
        resData["Items"]   = Variant("")
        conn:SendRemoteEvent(Settings.EVENTS.RES_FORGE_NEW, true, resData)
        return
    end

    -- 配方和材料检查
    local tier = bp.tier
    local recipe = Settings.FORGE.RECIPES[tier]
    if not recipe then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("该等阶无配方配置")
        resData["Items"]   = Variant("")
        conn:SendRemoteEvent(Settings.EVENTS.RES_FORGE_NEW, true, resData)
        return
    end

    -- 计算所需总材料
    local needMain = recipe.main.count * count
    local needSub  = recipe.sub.count  * count

    -- 统计背包中持有量
    local haveMain, haveSub = 0, 0
    for _, item in ipairs(pd.inventory or {}) do
        if item.id == recipe.main.id then haveMain = haveMain + (item.count or 1) end
        if item.id == recipe.sub.id  then haveSub  = haveSub  + (item.count or 1) end
    end

    if haveMain < needMain or haveSub < needSub then
        local mainDef = Settings.ALCHEMY_MATERIALS[recipe.main.id]
        local subDef  = Settings.ALCHEMY_MATERIALS[recipe.sub.id]
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant(string.format("材料不足：需%s×%d + %s×%d",
            mainDef and mainDef.name or recipe.main.id, needMain,
            subDef and subDef.name or recipe.sub.id, needSub))
        resData["Items"]   = Variant("")
        conn:SendRemoteEvent(Settings.EVENTS.RES_FORGE_NEW, true, resData)
        return
    end

    -- 背包空间检查（最多生成 count 件装备）
    local bagFree = Settings.INVENTORY_MAX - (pd.inventory and #pd.inventory or 0)
    if bagFree <= 0 then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("背包已满！")
        resData["Items"]   = Variant("")
        conn:SendRemoteEvent(Settings.EVENTS.RES_FORGE_NEW, true, resData)
        return
    end
    count = math.min(count, bagFree)

    -- 扣除材料
    local function ConsumeMaterial(matId, amount)
        local remaining = amount
        for i = #(pd.inventory or {}), 1, -1 do
            if remaining <= 0 then break end
            local item = pd.inventory[i]
            if item.id == matId then
                local have = item.count or 1
                if have <= remaining then
                    remaining = remaining - have
                    table.remove(pd.inventory, i)
                else
                    item.count = have - remaining
                    remaining = 0
                end
            end
        end
    end
    ConsumeMaterial(recipe.main.id, needMain)
    ConsumeMaterial(recipe.sub.id, needSub)

    -- 门派判定
    local isQidan = (pd.sect == "qidan_sect")
    local failRates = Settings.FORGE.FAIL_RATE[tier]
    local failRate = failRates and (isQidan and failRates.qidan or failRates.normal) or 0.20
    local qualityTable = isQidan and Settings.FORGE.QUALITY_RATES.qidan or Settings.FORGE.QUALITY_RATES.normal
    local pityMax = Settings.FORGE.PITY[tier] or 150

    -- 保底表初始化
    if not pd.forge_pity then pd.forge_pity = {} end
    if not pd.forge_pity[bpId] then pd.forge_pity[bpId] = 0 end

    -- 找到对应的装备模板
    local tmpl = nil
    for _, t in ipairs(Settings.EQUIPMENT_TEMPLATES) do
        if t.id == bp.template_id then tmpl = t; break end
    end
    if not tmpl then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("装备模板丢失")
        resData["Items"]   = Variant("")
        conn:SendRemoteEvent(Settings.EVENTS.RES_FORGE_NEW, true, resData)
        return
    end

    -- 开始锻造
    local resultItems = {}
    local successCount = 0
    local failCount = 0

    for i = 1, count do
        pd.forge_pity[bpId] = pd.forge_pity[bpId] + 1

        -- 失败判定
        if math.random() < failRate then
            failCount = failCount + 1
        else
            -- 成功：随机品质
            local quality = 1
            local isPity = (pd.forge_pity[bpId] >= pityMax)

            if isPity then
                -- 保底触发：强制史诗
                quality = 4
                pd.forge_pity[bpId] = 0
            else
                -- 加权随机
                local totalWeight = 0
                for _, q in ipairs(qualityTable) do totalWeight = totalWeight + q.weight end
                local roll = math.random() * totalWeight
                local cumulative = 0
                for _, q in ipairs(qualityTable) do
                    cumulative = cumulative + q.weight
                    if roll <= cumulative then
                        quality = q.quality
                        break
                    end
                end
                -- 如果抽到史诗及以上，重置保底
                if quality >= 4 then
                    pd.forge_pity[bpId] = 0
                end
            end

            -- 生成装备
            local mult = Settings.EQUIPMENT_QUALITY_MULTIPLIER[quality] or 1.0
            local stats = {}
            for k, v in pairs(tmpl.base) do
                stats[k] = math.floor(v * mult)
            end

            local qualityName = Settings.EQUIPMENT_QUALITY[quality]
                and Settings.EQUIPMENT_QUALITY[quality].name or "普通"
            local itemName = tmpl.name .. (quality > 1 and ("·" .. qualityName) or "")

            local newItem = {
                type        = "equipment",
                id          = Shared.GenId(),
                template_id = tmpl.id,
                name        = itemName,
                slot        = tmpl.slot,
                quality     = quality,
                stats       = stats,
                bound       = false,
                forged      = true,
            }
            table.insert(pd.inventory, newItem)
            successCount = successCount + 1

            resultItems[#resultItems + 1] = {
                name    = itemName,
                quality = quality,
                slot    = tmpl.slot,
            }
        end
    end

    -- 构建结果消息
    local msg
    if successCount > 0 and failCount > 0 then
        msg = string.format("锻造完成：成功%d件，失败%d件", successCount, failCount)
    elseif successCount > 0 then
        msg = string.format("锻造完成：成功%d件！", successCount)
    else
        msg = string.format("锻造全部失败（%d件），材料已消耗", failCount)
    end

    resData["Success"] = Variant(successCount > 0)
    resData["Msg"]     = Variant(msg)
    resData["Items"]   = Variant(cjson.encode(resultItems))
    conn:SendRemoteEvent(Settings.EVENTS.RES_FORGE_NEW, true, resData)

    Server.PushLog(conn, successCount > 0
        and string.format("<绿>【炼器】%s</绿>", msg)
        or  string.format("<红>【炼器】%s</红>", msg))

    -- 门派试炼：锻造成功
    if successCount > 0 then
        Server.OnTrialForgeSuccess(uid, conn, pd, bpId)
    end

    Server.PushPlayerData(uid, conn)
    Server.PushInventory(uid, conn)
    Server.SavePlayerData(uid, pd)
end

-- ============================================================================
-- 炼器系统（器丹宗·炼器分支）【旧系统保留】
-- ============================================================================

function Server_OnReqForgeCraft(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    -- 只有器丹宗弟子可以炼器
    if pd.sect ~= "qidan_sect" then
        Server.PushLog(conn, "<红>只有器丹宗弟子才能炼器。</红>")
        return
    end

    local recipeId = eventData["RecipeId"]:GetString()
    local recipe = Settings.FORGE_RECIPES[recipeId]
    if not recipe then
        Server.PushLog(conn, "<红>未知的锻造图纸。</红>")
        return
    end

    -- 检查炼器等级
    local forgeLevel = pd.forge_level or 0
    if forgeLevel < recipe.min_skill_level then
        Server.PushLog(conn, string.format("<红>炼器等级不足，需要%d级。</红>", recipe.min_skill_level))
        return
    end

    -- 检查材料
    for _, mat in ipairs(recipe.materials) do
        local count = 0
        for _, item in ipairs(pd.inventory or {}) do
            if item.id == mat.id then
                count = count + (item.count or 1)
            end
        end
        if count < mat.count then
            local matDef = Settings.ALCHEMY_MATERIALS[mat.id]
            local matName = matDef and matDef.name or mat.id
            Server.PushLog(conn, string.format("<红>材料不足：【%s】需要%d，持有%d。</红>", matName, mat.count, count))
            return
        end
    end

    -- 检查背包容量
    if #(pd.inventory or {}) >= Settings.INVENTORY_MAX then
        Server.PushLog(conn, "<红>背包已满，无法锻造！</红>")
        return
    end

    -- 扣除材料
    for _, mat in ipairs(recipe.materials) do
        local remaining = mat.count
        for i = #(pd.inventory or {}), 1, -1 do
            if remaining <= 0 then break end
            local item = pd.inventory[i]
            if item.id == mat.id then
                local have = item.count or 1
                if have <= remaining then
                    remaining = remaining - have
                    table.remove(pd.inventory, i)
                else
                    item.count = have - remaining
                    remaining = 0
                end
            end
        end
    end

    -- 炼器成功率判定
    local successRate = recipe.success_rate
    -- 炼器分支技能加成（每级 +5% 成功率）
    for _, sk in ipairs(pd.skills or {}) do
        local def = Shared.GetSkillDef(sk.id)
        if def and def.branch == "forge" then
            successRate = successRate + 0.05 * (sk.proficiency or 0) / (def.max_proficiency or 100)
        end
    end
    successRate = math.min(0.99, successRate)

    local resultData = VariantMap()
    local roll = math.random()

    if roll <= successRate then
        -- 锻造成功：生成装备
        local forgedItem = {
            id       = recipeId,
            name     = recipe.name,
            type     = "equipment",
            slot     = recipe.slot,
            quality  = recipe.quality,
            stats    = recipe.stats,
            forged   = true,  -- 标记为锻造装备
        }
        table.insert(pd.inventory, forgedItem)

        -- 增加炼器经验
        pd.forge_exp = (pd.forge_exp or 0) + recipe.exp_gain
        pd.forge_level = math.min(5, math.floor((pd.forge_exp or 0) / 100) + 1)

        Server.PushLog(conn, string.format("<绿>锻造成功！获得【%s】</绿>", recipe.name))

        resultData["Success"]  = Variant(true)
        resultData["ItemName"] = Variant(recipe.name)
        resultData["Msg"]      = Variant(string.format("锻造成功！获得%s", recipe.name))
    else
        -- 锻造失败（材料已消耗）
        pd.forge_exp = (pd.forge_exp or 0) + math.floor(recipe.exp_gain * 0.3)
        pd.forge_level = math.min(5, math.floor((pd.forge_exp or 0) / 100) + 1)

        Server.PushLog(conn, "<红>锻造失败！矿石碎裂化为飞灰……</红>")

        resultData["Success"]  = Variant(false)
        resultData["ItemName"] = Variant(recipe.name)
        resultData["Msg"]      = Variant("锻造失败，材料已损耗")
    end

    conn:SendRemoteEvent(Settings.EVENTS.RES_FORGE_CRAFT, true, resultData)
    Server.PushPlayerData(uid, conn)
    Server.PushInventory(uid, conn)
    Server.SavePlayerData(uid)
end

-- ============================================================================
-- 帮会系统
-- ============================================================================

-- 服务端帮会数据（已前移至大地图同步区域之前声明）

-- ============================================================================
-- 领地战状态
-- ============================================================================
-- 据点归属（已前移至大地图同步区域之前声明）
-- 领地战状态
local territoryWarActive_ = false
-- 管理员强制覆盖: nil=不干预(按时间判断), true=强制开启, false=强制关闭
local forceWarOverride_ = nil
-- 当前据点防守者列表: spDefenders_[sp_id] = { uid1, uid2, ... }
local spDefenders_ = {}
-- 当前据点攻击者: spAttackers_[sp_id] = { uid1, uid2, ... }
local spAttackers_ = {}
-- 无人防守占领计时器: spCaptureTimers_[sp_id] = { attacker_guild_id, elapsed_sec }
local spCaptureTimers_ = {}

function Server_OnReqCreateGuild(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    -- 已有帮会不能再创建
    if pd.guild_id and pd.guild_id ~= "" then
        Server.PushLog(conn, "<红>你已有帮会，需先退出当前帮会。</红>")
        return
    end

    -- 境界检查
    if (pd.realm or 1) < Settings.GUILD.CREATE_MIN_REALM then
        local realmName = Settings.REALM_NAMES[Settings.GUILD.CREATE_MIN_REALM] or "筑基"
        Server.PushLog(conn, string.format("<红>创建帮会需要%s期以上境界。</红>", realmName))
        return
    end

    -- 银两检查
    if (pd.silver or 0) < Settings.GUILD.CREATE_COST_SILVER then
        Server.PushLog(conn, string.format("<红>创建帮会需要%d银两。</红>", Settings.GUILD.CREATE_COST_SILVER))
        return
    end

    local guildName = eventData["GuildName"]:GetString()
    -- 名称长度检查
    if #guildName < Settings.GUILD.NAME_MIN_LEN or #guildName > Settings.GUILD.NAME_MAX_LEN * 3 then
        Server.PushLog(conn, string.format("<红>帮会名长度需要%d~%d个字。</红>", Settings.GUILD.NAME_MIN_LEN, Settings.GUILD.NAME_MAX_LEN))
        return
    end

    -- 检查名称重复
    for _, g in pairs(guilds_) do
        if g.name == guildName then
            Server.PushLog(conn, "<红>该帮会名已被占用。</红>")
            return
        end
    end

    -- 扣银两，创建帮会
    pd.silver = pd.silver - Settings.GUILD.CREATE_COST_SILVER
    local guildId = "guild_" .. tostring(uid) .. "_" .. tostring(os.time())
    local currentLayer = pd.realm_layer or 1
    guilds_[guildId] = {
        name       = guildName,
        leader_uid = uid,
        members    = { uid },
        layer      = currentLayer,
        created_at = os.time(),
        level      = 1,
        fund       = 0,
        exp        = 0,
        roles      = {},
    }
    pd.guild_id = guildId
    pd.guild_name = guildName

    Server.PushLog(conn, string.format("<绿>帮会【%s】创建成功！可前往第3/8层争夺据点。</绿>", guildName))

    local resData = VariantMap()
    resData["Success"]   = Variant(true)
    resData["GuildId"]   = Variant(guildId)
    resData["GuildName"] = Variant(guildName)
    resData["Layer"]     = Variant(currentLayer)
    conn:SendRemoteEvent(Settings.EVENTS.RES_CREATE_GUILD, true, resData)
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
    SaveGuildData()
end

function Server_OnReqGuildInfo(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local resData = VariantMap()

    -- 用 pcall 包裹整个逻辑，避免任何异常导致客户端无响应
    local ok, err = pcall(function()
        Server_OnReqGuildInfo_Inner(conn, uid, pd, resData)
    end)
    if not ok then
        print("[Server] GuildInfo handler error: " .. tostring(err))
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("服务器内部错误")
        conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_INFO, true, resData)
    end
end

function Server_OnReqGuildInfo_Inner(conn, uid, pd, resData)
    -- 直接用玩家自己的帮会（不再从 eventData 读可选字段，避免 Variant 类型问题）
    local queryGuildId = pd.guild_id or ""

    if queryGuildId == "" then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("未加入帮会")
        conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_INFO, true, resData)
        return
    end
    if not guilds_[queryGuildId] then
        if not guildDataLoaded_ then
            resData["Success"] = Variant(false)
            resData["Msg"]     = Variant("LOADING")
            conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_INFO, true, resData)
        else
            -- 数据已加载但该帮会不在列表中
            -- 如果 guilds_ 整体为空，可能是云存储尚未同步，继续重试
            local gCount = 0
            for _ in pairs(guilds_) do gCount = gCount + 1 end
            if gCount == 0 then
                -- 无任何帮会数据，视为存储未就绪，重新尝试加载
                guildDataLoaded_ = false
                LoadGuildData()
                resData["Success"] = Variant(false)
                resData["Msg"]     = Variant("LOADING")
                conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_INFO, true, resData)
            else
                -- 有其他帮会但该帮会不存在，确实已解散
                pd.guild_id = ""
                resData["Success"] = Variant(false)
                resData["Msg"]     = Variant("帮会已解散")
                conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_INFO, true, resData)
            end
        end
        return
    end

    local g = guilds_[queryGuildId]

    -- 构建成员详情列表
    local memberDetails = {}
    for _, memberUid in ipairs(g.members) do
        local mpd = players_[memberUid]
        local online = connections_[memberUid] ~= nil
        local mRole = Server.GetGuildRole(g, memberUid)
        if mpd then
            memberDetails[#memberDetails + 1] = {
                uid         = memberUid,
                name        = mpd.name or "未知",
                realm       = mpd.realm or 1,
                realm_layer = mpd.realm_layer or 1,
                online      = online,
                is_leader   = memberUid == g.leader_uid,
                role        = mRole,
                contribution = mpd.guild_contribution or 0,
            }
        else
            memberDetails[#memberDetails + 1] = {
                uid         = memberUid,
                name        = memberUid,
                realm       = 1,
                realm_layer = 1,
                online      = false,
                is_leader   = memberUid == g.leader_uid,
                role        = mRole,
                contribution = 0,
            }
        end
    end
    -- 帮主排最前，其余按境界降序
    table.sort(memberDetails, function(a, b)
        if a.is_leader ~= b.is_leader then return a.is_leader end
        if a.realm ~= b.realm then return a.realm > b.realm end
        return a.realm_layer > b.realm_layer
    end)

    -- 构建本帮会占领的据点（一个帮会只能拥有一个据点）
    local ownedStrongpoint = nil
    for spId, owner in pairs(strongpointOwners_) do
        if owner.guild_id == queryGuildId then
            -- 查找据点配置
            for layerNum, layerSps in pairs(Settings.STRONGPOINTS_BY_LAYER) do
                for _, sp in ipairs(layerSps) do
                    if sp.id == spId then
                        ownedStrongpoint = {
                            id         = spId,
                            name       = sp.name,
                            layer      = layerNum,
                            bonus_type = sp.bonus_type,
                            bonus_desc = sp.desc,
                        }
                        break
                    end
                end
                if ownedStrongpoint then break end
            end
            break  -- 只能有一个据点
        end
    end

    -- 帮主名字
    local leaderName = "未知"
    local leaderPd = players_[g.leader_uid]
    if leaderPd then leaderName = leaderPd.name or "未知" end

    local lvCfg = Server.GetGuildLevelCfg(g)
    local info = {
        guild_id     = queryGuildId,
        name         = g.name,
        leader_name  = leaderName,
        notice       = g.notice or "",
        member_count = #g.members,
        max_members  = lvCfg.max_members,
        members      = memberDetails,
        strongpoint  = ownedStrongpoint,  -- nil 或单个据点对象
        created_at   = g.created_at or 0,
        level        = g.level or 1,
        fund         = g.fund or 0,
        exp          = g.exp or 0,
        cult_bonus   = lvCfg.cult_bonus,
        combat_bonus = lvCfg.combat_bonus,
        silver_bonus = lvCfg.silver_bonus,
    }

    local encOk, jsonStr = pcall(cjson.encode, info)
    if not encOk then
        print("[Server] GuildInfo JSON encode error: " .. tostring(jsonStr))
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("服务器内部错误")
        conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_INFO, true, resData)
        return
    end

    resData["Success"]   = Variant(true)
    resData["InfoJson"]  = Variant(jsonStr)
    conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_INFO, true, resData)
end

function Server_OnReqJoinGuild(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    if pd.guild_id and pd.guild_id ~= "" then
        Server.PushLog(conn, "<红>你已有帮会，需先退出。</红>")
        return
    end

    local guildId = eventData["GuildId"]:GetString()
    local g = guilds_[guildId]
    if not g then
        Server.PushLog(conn, "<红>帮会不存在。</红>")
        return
    end

    local lvCfg = Settings.GUILD.LEVELS[g.level or 1] or Settings.GUILD.LEVELS[1]
    local maxMembers = lvCfg.max_members or Settings.GUILD.MAX_MEMBERS
    if #g.members >= maxMembers then
        Server.PushLog(conn, "<红>帮会已满员。</红>")
        return
    end

    table.insert(g.members, uid)
    pd.guild_id = guildId
    pd.guild_name = g.name

    Server.PushLog(conn, string.format("<绿>成功加入帮会【%s】！</绿>", g.name))

    -- 任务系统：加入帮会
    Quest.OnJoinGuild(pd, conn)

    local resData = VariantMap()
    resData["Success"]   = Variant(true)
    resData["GuildId"]   = Variant(guildId)
    resData["GuildName"] = Variant(g.name)
    conn:SendRemoteEvent(Settings.EVENTS.RES_JOIN_GUILD, true, resData)
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
    SaveGuildData()
end

function Server_OnReqLeaveGuild(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local guildId = pd.guild_id or ""
    if guildId == "" then
        Server.PushLog(conn, "<红>你没有加入任何帮会。</红>")
        return
    end

    local g = guilds_[guildId]
    if not g then
        pd.guild_id = ""
        pd.guild_name = ""
        Server.PushPlayerData(uid, conn)
        return
    end

    -- 从成员列表移除
    for i, memberId in ipairs(g.members) do
        if memberId == uid then
            table.remove(g.members, i)
            break
        end
    end

    -- 如果是帮主退出且帮会还有人，转让给下一个
    if g.leader_uid == uid then
        if #g.members > 0 then
            g.leader_uid = g.members[1]
            Server.PushLog(conn, string.format("<黄>帮主已转让给 %s。</黄>", g.leader_uid))
        else
            -- 帮会空了，解散
            guilds_[guildId] = nil
            Server.PushLog(conn, "<黄>帮会已解散。</黄>")
        end
    end

    pd.guild_id = ""
    pd.guild_name = ""
    Server.PushLog(conn, "<绿>你已退出帮会。</绿>")

    local resData = VariantMap()
    resData["Success"] = Variant(true)
    conn:SendRemoteEvent(Settings.EVENTS.RES_LEAVE_GUILD, true, resData)
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
    SaveGuildData()
end

function Server_OnReqSetGuildNotice(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local guildId = pd.guild_id or ""
    if guildId == "" or not guilds_[guildId] then
        Server.PushLog(conn, "<红>你没有加入帮会。</红>")
        return
    end

    local g = guilds_[guildId]
    if g.leader_uid ~= uid then
        Server.PushLog(conn, "<红>只有帮主才能设置公告。</红>")
        return
    end

    local notice = eventData["Notice"]:GetString()
    -- 限制公告长度（最多100字）
    if #notice > 300 then  -- UTF-8 中文约3字节/字
        notice = notice:sub(1, 300)
    end

    g.notice = notice
    SaveGuildData()

    Server.PushLog(conn, "<绿>帮会公告已更新。</绿>")
    local resData = VariantMap()
    resData["Success"] = Variant(true)
    conn:SendRemoteEvent(Settings.EVENTS.RES_SET_GUILD_NOTICE, true, resData)
end

-- ============================================================================
-- 帮会列表浏览
-- ============================================================================

function Server_OnReqGuildList(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    if not uid then return end

    local list = {}
    for guildId, g in pairs(guilds_) do
        list[#list + 1] = {
            id          = guildId,
            name        = g.name,
            leader_uid  = g.leader_uid,
            leader_name = (players_[g.leader_uid] and players_[g.leader_uid].name) or "离线",
            member_count = #g.members,
            max_members = (Settings.GUILD.LEVELS[g.level or 1] or Settings.GUILD.LEVELS[1]).max_members,
            layer       = g.layer or 1,
            notice      = g.notice or "",
        }
    end

    local resData = VariantMap()
    resData["Success"]  = Variant(true)
    resData["ListJson"] = Variant(cjson.encode(list))
    conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_LIST, true, resData)
end

-- ============================================================================
-- 帮主踢人
-- ============================================================================

function Server_OnReqKickMember(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local guildId = pd.guild_id or ""
    if guildId == "" or not guilds_[guildId] then
        Server.PushLog(conn, "<红>你没有加入帮会。</红>")
        return
    end

    local g = guilds_[guildId]
    if g.leader_uid ~= uid then
        Server.PushLog(conn, "<红>只有帮主才能踢人。</红>")
        return
    end

    local targetUid = eventData["TargetUid"]:GetInt64()
    if targetUid == uid then
        Server.PushLog(conn, "<红>不能踢自己，请使用退出帮会。</红>")
        return
    end

    -- 检查目标是否在帮会中
    local found = false
    for i, memberId in ipairs(g.members) do
        if memberId == targetUid then
            table.remove(g.members, i)
            found = true
            break
        end
    end

    if not found then
        Server.PushLog(conn, "<红>该玩家不在帮会中。</红>")
        return
    end

    -- 清除被踢玩家的帮会信息
    local targetPd = players_[targetUid]
    if targetPd then
        targetPd.guild_id = ""
        targetPd.guild_name = ""
        -- 通知被踢玩家
        local targetConn = connections_[targetUid]
        if targetConn then
            Server.PushLog(targetConn, "<红>你已被帮主移出帮会。</红>")
            Server.PushPlayerData(targetUid, targetConn)
        end
        Server.SavePlayerData(targetUid)
    end

    local targetName = (targetPd and targetPd.name) or tostring(targetUid)
    Server.PushLog(conn, string.format("<绿>已将【%s】移出帮会。</绿>", targetName))
    SaveGuildData()

    local resData = VariantMap()
    resData["Success"]   = Variant(true)
    resData["TargetUid"] = Variant(targetUid)
    conn:SendRemoteEvent(Settings.EVENTS.RES_KICK_MEMBER, true, resData)
end

-- ============================================================================
-- 转让帮主
-- ============================================================================

function Server_OnReqTransferLeader(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local guildId = pd.guild_id or ""
    if guildId == "" or not guilds_[guildId] then
        Server.PushLog(conn, "<红>你没有加入帮会。</红>")
        return
    end

    local g = guilds_[guildId]
    if g.leader_uid ~= uid then
        Server.PushLog(conn, "<红>只有帮主才能转让帮主。</红>")
        return
    end

    local targetUid = eventData["TargetUid"]:GetInt64()
    if targetUid == uid then
        Server.PushLog(conn, "<红>你已经是帮主了。</红>")
        return
    end

    -- 检查目标是否在帮会中
    local found = false
    for _, memberId in ipairs(g.members) do
        if memberId == targetUid then
            found = true
            break
        end
    end

    if not found then
        Server.PushLog(conn, "<红>该玩家不在帮会中。</红>")
        return
    end

    -- 执行转让
    g.leader_uid = targetUid
    SaveGuildData()

    local targetName = (players_[targetUid] and players_[targetUid].name) or tostring(targetUid)
    Server.PushLog(conn, string.format("<绿>帮主已转让给【%s】。</绿>", targetName))

    -- 通知新帮主
    local targetConn = connections_[targetUid]
    if targetConn then
        Server.PushLog(targetConn, "<绿>你已成为帮主！</绿>")
    end

    local resData = VariantMap()
    resData["Success"]   = Variant(true)
    resData["TargetUid"] = Variant(targetUid)
    conn:SendRemoteEvent(Settings.EVENTS.RES_TRANSFER_LEADER, true, resData)
end

-- ============================================================================
-- 帮会成员上下线通知
-- ============================================================================

function Server.NotifyGuildOnline(uid, isOnline)
    local pd = players_[uid]
    -- 离线时 pd 可能已被清除，尝试用 uid 反查帮会
    local guildId = pd and pd.guild_id or ""
    if guildId == "" then return end
    local g = guilds_[guildId]
    if not g then return end

    local playerName = (pd and pd.name) or tostring(uid)

    local data = VariantMap()
    data["PlayerName"] = Variant(playerName)
    data["IsOnline"]   = Variant(isOnline)
    data["Uid"]        = Variant(uid)

    -- 通知同帮会在线成员（不通知自己）
    for _, memberId in ipairs(g.members) do
        if memberId ~= uid then
            local memberConn = connections_[memberId]
            if memberConn then
                memberConn:SendRemoteEvent(Settings.EVENTS.NOTIFY_GUILD_ONLINE, true, data)
            end
        end
    end
end

-- ============================================================================
-- 帮会聊天频道
-- ============================================================================

function Server.BroadcastGuildChat(msg, guildId)
    local g = guilds_[guildId]
    if not g then return end
    local pushData = VariantMap()
    pushData["MsgJson"] = Variant(cjson.encode(msg))
    for _, memberId in ipairs(g.members) do
        local memberConn = connections_[memberId]
        if memberConn then
            memberConn:SendRemoteEvent(Settings.EVENTS.PUSH_CHAT_MSG, true, pushData)
        end
    end
end


-- ============================================================================
-- 帮会深度玩法：等级/资金/职位/日常任务/BUFF
-- ============================================================================

--- 获取帮会当前等级配置
function Server.GetGuildLevelCfg(g)
    local lv = g.level or 1
    return Settings.GUILD.LEVELS[lv] or Settings.GUILD.LEVELS[1]
end

--- 获取帮会等级BUFF（供修炼/战斗系统调用）
function Server.GetGuildBuff(pd)
    if not pd or not pd.guild_id or pd.guild_id == "" then return nil end
    local g = guilds_[pd.guild_id]
    if not g then return nil end
    local cfg = Server.GetGuildLevelCfg(g)
    return {
        cult_bonus    = cfg.cult_bonus,    -- 修炼速度倍率
        combat_bonus  = cfg.combat_bonus,  -- 战力加成（绝对值）
        silver_bonus  = cfg.silver_bonus,  -- 银两获取加成比例
    }
end

--- 获取成员在帮会中的职位
function Server.GetGuildRole(g, uid)
    if uid == g.leader_uid then return "leader" end
    if g.roles then return g.roles[uid] or "member" end
    return "member"
end

--- 检查职位权限
function Server.HasGuildPerm(g, uid, perm)
    local role = Server.GetGuildRole(g, uid)
    local perms = Settings.GUILD.ROLE_PERMS[role]
    return perms and perms[perm] == true
end

--- 帮会日常任务进度推进（供各系统调用）
function Server.AdvanceGuildDaily(uid, taskId, amount)
    local pd = players_[uid]
    if not pd or not pd.guild_id or pd.guild_id == "" then return end
    if not pd.guild_daily then pd.guild_daily = {} end
    local today = os.date("%Y%m%d")
    if pd.guild_daily.date ~= today then
        pd.guild_daily = { date = today }
    end
    if not pd.guild_daily[taskId] then pd.guild_daily[taskId] = { progress = 0, claimed = false } end
    local t = pd.guild_daily[taskId]
    if t.claimed then return end  -- 已领取不再累加
    t.progress = (t.progress or 0) + (amount or 1)
end

-- ── 捐献帮会 ──
function Server_OnReqGuildDonate(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    if not pd.guild_id or pd.guild_id == "" then
        Server.PushLog(conn, "<红>你尚未加入帮会。</红>")
        return
    end
    local g = guilds_[pd.guild_id]
    if not g then return end

    local optionId = eventData:GetString("OptionId")
    local option = nil
    for _, o in ipairs(Settings.GUILD.DONATE_OPTIONS) do
        if o.id == optionId then option = o; break end
    end
    if not option then
        Server.PushLog(conn, "<红>无效的捐献选项。</红>")
        return
    end

    -- 银两检查
    if (pd.silver or 0) < option.silver then
        Server.PushLog(conn, string.format("<红>银两不足，需要%d银两。</红>", option.silver))
        return
    end

    -- 扣银两
    pd.silver = pd.silver - option.silver
    -- 帮会资金和经验增加
    g.fund = (g.fund or 0) + option.silver
    g.exp  = (g.exp or 0) + option.exp
    -- 个人贡献增加
    pd.guild_contribution = (pd.guild_contribution or 0) + option.contribution

    -- 推进日常任务
    Server.AdvanceGuildDaily(uid, "donate", 1)

    Server.PushLog(conn, string.format("<绿>成功捐献%d银两！帮会资金+%d，个人贡献+%d。</绿>", option.silver, option.silver, option.contribution))

    local resData = VariantMap()
    resData["Success"]      = Variant(true)
    resData["Fund"]         = Variant(g.fund)
    resData["Exp"]          = Variant(g.exp)
    resData["Contribution"] = Variant(pd.guild_contribution)
    conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_DONATE, true, resData)

    Server.PushPlayerData(uid, conn)
    SaveGuildData()
end

-- ── 帮会升级 ──
function Server_OnReqGuildUpgrade(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    if not pd.guild_id or pd.guild_id == "" then return end
    local g = guilds_[pd.guild_id]
    if not g then return end

    -- 权限检查
    if not Server.HasGuildPerm(g, uid, "upgrade") then
        Server.PushLog(conn, "<红>你没有升级帮会的权限。</红>")
        return
    end

    local curLevel = g.level or 1
    if curLevel >= Settings.GUILD.MAX_LEVEL then
        Server.PushLog(conn, "<黄>帮会已达最高等级！</黄>")
        return
    end

    local nextCfg = Settings.GUILD.LEVELS[curLevel + 1]
    if not nextCfg then return end

    -- 检查资金和经验
    if (g.exp or 0) < nextCfg.exp then
        Server.PushLog(conn, string.format("<红>帮会经验不足，需要%d，当前%d。</红>", nextCfg.exp, g.exp or 0))
        return
    end
    if (g.fund or 0) < nextCfg.fund then
        Server.PushLog(conn, string.format("<红>帮会资金不足，需要%d，当前%d。</红>", nextCfg.fund, g.fund or 0))
        return
    end

    -- 升级
    g.level = curLevel + 1
    Server.PushLog(conn, string.format("<金>帮会升级至%d级！成员上限%d人，修炼加成×%.2f。</金>", g.level, nextCfg.max_members, nextCfg.cult_bonus))

    -- 广播通知全帮
    local notifyMsg = string.format("<帮会> 帮会升级至%d级！全员修炼加成提升。", g.level)
    for _, memberId in ipairs(g.members) do
        local mc = connections_[memberId]
        if mc then Server.PushLog(mc, "<金>" .. notifyMsg .. "</金>") end
    end

    local resData = VariantMap()
    resData["Success"] = Variant(true)
    resData["Level"]   = Variant(g.level)
    conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_UPGRADE, true, resData)
    SaveGuildData()
end

-- ── 设置成员职位 ──
function Server_OnReqSetGuildRole(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    if not pd.guild_id or pd.guild_id == "" then return end
    local g = guilds_[pd.guild_id]
    if not g then return end

    -- 权限检查（只有帮主可设置职位）
    if not Server.HasGuildPerm(g, uid, "set_role") then
        Server.PushLog(conn, "<红>只有帮主才能设置职位。</红>")
        return
    end

    local targetUid = eventData:GetString("TargetUid")
    local newRole   = eventData:GetString("Role")

    -- 验证职位合法性
    local validRoles = { vice_leader = true, elder = true, member = true }
    if not validRoles[newRole] then
        Server.PushLog(conn, "<红>无效的职位。</红>")
        return
    end

    -- 不能设置自己
    if targetUid == uid then
        Server.PushLog(conn, "<红>不能设置自己的职位。</红>")
        return
    end

    -- 检查目标是否是帮会成员
    local isMember = false
    for _, m in ipairs(g.members) do
        if m == targetUid then isMember = true; break end
    end
    if not isMember then
        Server.PushLog(conn, "<红>该玩家不是帮会成员。</红>")
        return
    end

    -- 检查职位数量限制
    if Settings.GUILD.ROLE_LIMITS[newRole] then
        local count = 0
        if not g.roles then g.roles = {} end
        for _, m in ipairs(g.members) do
            if g.roles[m] == newRole then count = count + 1 end
        end
        if count >= Settings.GUILD.ROLE_LIMITS[newRole] then
            local roleName = Settings.GUILD.ROLE_NAMES[newRole] or newRole
            Server.PushLog(conn, string.format("<红>%s人数已达上限（%d人）。</红>", roleName, Settings.GUILD.ROLE_LIMITS[newRole]))
            return
        end
    end

    -- 设置职位
    if not g.roles then g.roles = {} end
    g.roles[targetUid] = newRole
    local roleName = Settings.GUILD.ROLE_NAMES[newRole] or newRole
    local targetPd = players_[targetUid]
    local targetName = targetPd and targetPd.name or targetUid

    Server.PushLog(conn, string.format("<绿>已将 %s 的职位设为【%s】。</绿>", targetName, roleName))

    -- 通知目标玩家
    local targetConn = connections_[targetUid]
    if targetConn then
        Server.PushLog(targetConn, string.format("<金>你已被帮主任命为【%s】。</金>", roleName))
    end

    local resData = VariantMap()
    resData["Success"]   = Variant(true)
    resData["TargetUid"] = Variant(targetUid)
    resData["Role"]      = Variant(newRole)
    conn:SendRemoteEvent(Settings.EVENTS.RES_SET_GUILD_ROLE, true, resData)
    SaveGuildData()
end

-- ── 获取帮会日常任务信息 ──
function Server_OnReqGuildDaily(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    if not pd.guild_id or pd.guild_id == "" then
        Server.PushLog(conn, "<红>你尚未加入帮会。</红>")
        return
    end

    -- 初始化/重置日常数据
    if not pd.guild_daily then pd.guild_daily = {} end
    local today = os.date("%Y%m%d")
    if pd.guild_daily.date ~= today then
        pd.guild_daily = { date = today }
    end

    -- 构建任务状态列表
    local tasks = {}
    for _, cfg in ipairs(Settings.GUILD.DAILY_TASKS) do
        local t = pd.guild_daily[cfg.id] or { progress = 0, claimed = false }
        tasks[#tasks + 1] = {
            id       = cfg.id,
            name     = cfg.name,
            desc     = cfg.desc,
            goal     = cfg.goal,
            progress = t.progress or 0,
            claimed  = t.claimed or false,
            reward_contrib = cfg.reward_contrib,
            reward_silver  = cfg.reward_silver,
        }
    end

    local resData = VariantMap()
    resData["Success"]      = Variant(true)
    resData["DataJson"]     = Variant(cjson.encode(tasks))
    resData["Contribution"] = Variant(pd.guild_contribution or 0)
    conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_DAILY, true, resData)
end

-- ── 领取日常任务奖励 ──
function Server_OnReqClaimGuildTask(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    if not pd.guild_id or pd.guild_id == "" then return end
    local g = guilds_[pd.guild_id]
    if not g then return end

    local taskId = eventData:GetString("TaskId")

    -- 找到任务配置
    local cfg = nil
    for _, t in ipairs(Settings.GUILD.DAILY_TASKS) do
        if t.id == taskId then cfg = t; break end
    end
    if not cfg then
        Server.PushLog(conn, "<红>无效的任务。</红>")
        return
    end

    -- 检查进度和领取状态
    if not pd.guild_daily then pd.guild_daily = {} end
    local today = os.date("%Y%m%d")
    if pd.guild_daily.date ~= today then pd.guild_daily = { date = today } end

    local t = pd.guild_daily[taskId]
    if not t then
        Server.PushLog(conn, "<红>任务尚未开始。</红>")
        return
    end
    if t.claimed then
        Server.PushLog(conn, "<黄>奖励已领取。</黄>")
        return
    end
    if (t.progress or 0) < cfg.goal then
        Server.PushLog(conn, string.format("<红>任务未完成（%d/%d）。</红>", t.progress or 0, cfg.goal))
        return
    end

    -- 发放奖励
    t.claimed = true
    pd.silver = (pd.silver or 0) + cfg.reward_silver
    pd.guild_contribution = (pd.guild_contribution or 0) + cfg.reward_contrib
    -- 帮会资金也增加一部分
    g.fund = (g.fund or 0) + math.floor(cfg.reward_silver * 0.5)

    Server.PushLog(conn, string.format("<绿>领取成功！银两+%d，贡献+%d。</绿>", cfg.reward_silver, cfg.reward_contrib))

    local resData = VariantMap()
    resData["Success"]      = Variant(true)
    resData["TaskId"]       = Variant(taskId)
    resData["Silver"]       = Variant(pd.silver)
    resData["Contribution"] = Variant(pd.guild_contribution)
    conn:SendRemoteEvent(Settings.EVENTS.RES_CLAIM_GUILD_TASK, true, resData)
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
    SaveGuildData()
end


-- ============================================================================
-- 领地战系统
-- ============================================================================

-- 据点加成辅助：获取指定玩家帮会所拥有据点的加成
-- 返回 { offline_potential = 0.15, cultivate_exp = 0.10, silver_income = 0.12 } 或 nil
function Server.GetStrongholdBonus(pd)
    if not pd or not pd.guild_id or pd.guild_id == "" then return nil end
    for spId, owner in pairs(strongpointOwners_) do
        if owner.guild_id == pd.guild_id then
            -- 查找据点配置获取加成信息
            for _, layerSps in pairs(Settings.STRONGPOINTS_BY_LAYER) do
                for _, sp in ipairs(layerSps) do
                    if sp.id == spId then
                        return { type = sp.bonus_type, value = sp.bonus_value, name = sp.name }
                    end
                end
            end
        end
    end
    return nil
end

-- 据点每日收益结算（在每日重置时调用）
local lastDailyRewardDate_ = ""
function Server.StrongholdDailyReward()
    local today = os.date("%Y-%m-%d")
    if lastDailyRewardDate_ == today then return end
    lastDailyRewardDate_ = today

    for spId, owner in pairs(strongpointOwners_) do
        if owner.guild_id and owner.guild_id ~= "" then
            local guild = guilds_[owner.guild_id]
            if guild and guild.members then
                -- 查找据点加成
                local bonus = nil
                for _, layerSps in pairs(Settings.STRONGPOINTS_BY_LAYER) do
                    for _, sp in ipairs(layerSps) do
                        if sp.id == spId then bonus = sp; break end
                    end
                    if bonus then break end
                end
                if bonus then
                    -- 发放据点日常收益：每个成员获得银两
                    local silverReward = math.floor(500 * (1 + (bonus.bonus_value or 0)))
                    local spiritReward = (bonus.bonus_value or 0) >= 0.2 and 5 or 0
                    for _, memberUid in ipairs(guild.members) do
                        local memberPd = players_[memberUid]
                        if memberPd then
                            memberPd.silver = (memberPd.silver or 0) + silverReward
                            if spiritReward > 0 then
                                memberPd.spirit_stone = (memberPd.spirit_stone or 0) + spiritReward
                            end
                            -- 通知在线成员
                            local memberConn = connections_[memberUid]
                            if memberConn then
                                Server.PushLog(memberConn, string.format(
                                    "<绿>【据点收益】帮会据点「%s」日常产出：银两+%d%s</绿>",
                                    bonus.name or spId, silverReward,
                                    spiritReward > 0 and ("，灵石+" .. spiritReward) or ""
                                ))
                                Server.PushPlayerData(memberUid, memberConn)
                            end
                        end
                    end
                end
            end
        end
    end
    print("[Server] 据点每日收益结算完成: " .. today)
end

-- 防守者复活状态 spReviveTimers_[uid] = { spId, remaining_sec }
local spReviveTimers_ = {}

-- 处理复活计时（在 TerritoryWarTick 中调用）
local function TickDefenderRevive(dt)
    local reviveTime = Settings.TERRITORY_WAR.DEFENDER_REVIVE_SEC or 30
    local toRemove = {}
    for uid, info in pairs(spReviveTimers_) do
        info.remaining = info.remaining - dt
        if info.remaining <= 0 then
            -- 复活：重新加入防守者列表
            local spId = info.spId
            if spDefenders_[spId] then
                local alreadyIn = false
                for _, dUid in ipairs(spDefenders_[spId]) do
                    if dUid == uid then alreadyIn = true; break end
                end
                if not alreadyIn then
                    spDefenders_[spId][#spDefenders_[spId] + 1] = uid
                end
            end
            -- 取消占领计时器（因为有防守者复活了）
            if spCaptureTimers_[spId] then
                spCaptureTimers_[spId] = nil
            end
            -- 通知该玩家已复活
            local conn = connections_[uid]
            if conn then
                local notifyData = VariantMap()
                notifyData["Success"] = Variant(true)
                notifyData["Msg"] = Variant("你已复活，重新进入防守状态！")
                conn:SendRemoteEvent(Settings.EVENTS.RES_DEFEND_STRONGPOINT, true, notifyData)
            end
            toRemove[#toRemove + 1] = uid
        end
    end
    for _, uid in ipairs(toRemove) do
        spReviveTimers_[uid] = nil
    end
end

-- 辅助：检查当前是否在领地战时段
local function IsTerritoryWarTime()
    local tw = Settings.TERRITORY_WAR
    local t = os.date("*t")
    local nowMin = t.hour * 60 + t.min
    local startMin = tw.START_HOUR * 60 + tw.START_MIN
    local endMin   = tw.END_HOUR * 60 + tw.END_MIN
    return nowMin >= startMin and nowMin < endMin
end

-- 辅助：获取据点的在线防守者 uid 列表
local function GetOnlineDefenders(spId)
    local owner = strongpointOwners_[spId]
    if not owner or owner.guild_id == "" then return {} end
    -- 找到帮会
    local guild = guilds_[owner.guild_id]
    if not guild then return {} end
    -- 筛选在线成员
    local online = {}
    for _, memberUid in ipairs(guild.members or {}) do
        if connections_[memberUid] then
            online[#online + 1] = memberUid
        end
    end
    return online
end

-- 辅助：广播给帮会所有在线成员
local function BroadcastToGuild(guildId, eventName, data)
    local guild = guilds_[guildId]
    if not guild then return end
    for _, memberUid in ipairs(guild.members or {}) do
        local conn = connections_[memberUid]
        if conn then
            conn:SendRemoteEvent(eventName, true, data)
        end
    end
end

-- 请求据点列表（含归属信息）
function Server_OnReqStrongpointList(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    if not uid then return end

    local layerParam = eventData["Layer"]:GetInt()
    local spDefs = Settings.STRONGPOINTS_BY_LAYER[layerParam]
    if not spDefs then return end

    -- 序列化据点信息：id|name|bonus_type|bonus_value|owner_guild_name
    local lines = {}
    for _, sp in ipairs(spDefs) do
        local owner = strongpointOwners_[sp.id]
        local ownerName = (owner and owner.guild_name ~= "") and owner.guild_name or "无主"
        lines[#lines + 1] = string.format("%s|%s|%s|%.2f|%s|%s",
            sp.id, sp.name, sp.bonus_type, sp.bonus_value, ownerName, sp.desc)
    end

    local resData = VariantMap()
    resData["Success"] = Variant(true)
    resData["Layer"] = Variant(layerParam)
    resData["Data"] = Variant(table.concat(lines, "\n"))
    resData["WarActive"] = Variant(territoryWarActive_)
    conn:SendRemoteEvent(Settings.EVENTS.RES_STRONGPOINT_LIST, true, resData)
end

-- 请求攻击据点
function Server_OnReqAttackStrongpoint(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local spId = eventData["SpId"]:GetString()
    local resData = VariantMap()
    resData["Success"] = Variant(false)

    -- 前置校验：拒绝空据点ID
    if not spId or spId == "" then
        resData["Msg"] = Variant("无效据点。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_ATTACK_STRONGPOINT, true, resData)
        return
    end

    -- 检查是否在领地战时段
    if not territoryWarActive_ then
        resData["Msg"] = Variant("当前不在领地战时段，无法攻击。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_ATTACK_STRONGPOINT, true, resData)
        return
    end

    -- 检查玩家有帮会
    if not pd.guild_id or pd.guild_id == "" then
        resData["Msg"] = Variant("你没有帮会，无法参与领地战。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_ATTACK_STRONGPOINT, true, resData)
        return
    end

    -- 检查是否帮主（只有帮主可发起占领）
    local myGuild = guilds_[pd.guild_id]
    if not myGuild or myGuild.leader_uid ~= uid then
        resData["Msg"] = Variant("只有帮主才能发起据点占领。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_ATTACK_STRONGPOINT, true, resData)
        return
    end

    -- 检查帮会是否已有据点 → 如果有，提示客户端走"更换"流程
    for sid, ownerInfo in pairs(strongpointOwners_) do
        if ownerInfo.guild_id == pd.guild_id then
            -- 帮会已有据点，通知客户端弹确认框
            resData["Success"] = Variant(false)
            resData["HasExisting"] = Variant(true)
            resData["ExistingSpId"] = Variant(sid)
            resData["ExistingSpName"] = Variant(ownerInfo.sp_name or sid)
            resData["TargetSpId"] = Variant(spId)  -- 把请求目标据点ID传回客户端
            resData["Msg"] = Variant("帮会已拥有据点「" .. (ownerInfo.sp_name or sid) .. "」，如需更换请确认。")
            conn:SendRemoteEvent(Settings.EVENTS.RES_ATTACK_STRONGPOINT, true, resData)
            return
        end
    end

    -- 检查据点是否是自己帮会的（不能攻击自己）
    local owner = strongpointOwners_[spId]
    if owner and owner.guild_id == pd.guild_id then
        resData["Msg"] = Variant("不能攻击自己帮会的据点。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_ATTACK_STRONGPOINT, true, resData)
        return
    end

    -- 注册为攻击者
    if not spAttackers_[spId] then spAttackers_[spId] = {} end
    -- 避免重复添加
    local alreadyIn = false
    for _, aUid in ipairs(spAttackers_[spId]) do
        if aUid == uid then alreadyIn = true; break end
    end
    if not alreadyIn then
        spAttackers_[spId][#spAttackers_[spId] + 1] = uid
    end

    -- 获取在线防守者
    local defenders = GetOnlineDefenders(spId)

    if #defenders == 0 then
        -- 无人防守：启动倒计时占领
        if not spCaptureTimers_[spId] then
            spCaptureTimers_[spId] = { attacker_guild_id = pd.guild_id, elapsed = 0 }
        end
        -- 查找据点名
        local spNameForRes = spId
        for _, layerSps in pairs(Settings.STRONGPOINTS_BY_LAYER) do
            for _, sp in ipairs(layerSps) do
                if sp.id == spId then spNameForRes = sp.name; break end
            end
        end
        resData["Success"] = Variant(true)
        resData["Msg"] = Variant("据点无人防守！正在占领中...")
        resData["NoDefender"] = Variant(true)
        resData["SpName"] = Variant(spNameForRes)
        resData["CaptureSec"] = Variant(Settings.TERRITORY_WAR.FREE_CAPTURE_SEC or 10)
        conn:SendRemoteEvent(Settings.EVENTS.RES_ATTACK_STRONGPOINT, true, resData)
    else
        -- 有防守者：通知防守方
        resData["Success"] = Variant(true)
        resData["Msg"] = Variant(string.format("据点有%d名防守者在线，请选择对手发起1v1！", #defenders))
        resData["NoDefender"] = Variant(false)
        -- 构建防守者列表
        local defInfo = {}
        for _, dUid in ipairs(defenders) do
            local dPd = players_[dUid]
            if dPd then
                defInfo[#defInfo + 1] = string.format("%s|%s|%d|%d",
                    dUid, dPd.name or "?", dPd.realm or 1, dPd.realm_layer or 1)
            end
        end
        resData["Defenders"] = Variant(table.concat(defInfo, "\n"))
        conn:SendRemoteEvent(Settings.EVENTS.RES_ATTACK_STRONGPOINT, true, resData)

        -- 通知防守帮会
        if owner and owner.guild_id ~= "" then
            local notifyData = VariantMap()
            notifyData["SpId"] = Variant(spId)
            notifyData["SpName"] = Variant(owner.sp_name or spId)
            notifyData["AttackerName"] = Variant(pd.name or "?")
            notifyData["AttackerGuild"] = Variant(myGuild and myGuild.name or "?")
            BroadcastToGuild(owner.guild_id, Settings.EVENTS.NOTIFY_UNDER_ATTACK, notifyData)
        end
    end
end

-- 请求更换据点（帮主已确认更换）
function Server_OnReqSwitchStrongpoint(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local newSpId = eventData["SpId"]:GetString()
    local resData = VariantMap()
    resData["Success"] = Variant(false)

    -- 前置校验：拒绝空据点ID
    if not newSpId or newSpId == "" then
        resData["Msg"] = Variant("无效据点。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_SWITCH_STRONGPOINT, true, resData)
        return
    end

    -- 检查领地战是否进行中
    if not territoryWarActive_ then
        resData["Msg"] = Variant("当前不在领地战时段，无法更换据点。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_SWITCH_STRONGPOINT, true, resData)
        return
    end

    -- 检查帮会
    if not pd.guild_id or pd.guild_id == "" then
        resData["Msg"] = Variant("你没有帮会。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_SWITCH_STRONGPOINT, true, resData)
        return
    end

    -- 检查帮主
    local myGuild = guilds_[pd.guild_id]
    if not myGuild or myGuild.leader_uid ~= uid then
        resData["Msg"] = Variant("只有帮主才能更换据点。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_SWITCH_STRONGPOINT, true, resData)
        return
    end

    -- 检查帮会当前是否拥有据点
    local oldSpId = nil
    local oldSpName = nil
    for sid, ownerInfo in pairs(strongpointOwners_) do
        if ownerInfo.guild_id == pd.guild_id then
            oldSpId = sid
            oldSpName = ownerInfo.sp_name or sid
            break
        end
    end
    if not oldSpId then
        resData["Msg"] = Variant("帮会当前没有据点，请直接占领。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_SWITCH_STRONGPOINT, true, resData)
        return
    end

    -- 不能更换到自己已有的据点
    if newSpId == oldSpId then
        resData["Msg"] = Variant("这已经是你帮会的据点了。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_SWITCH_STRONGPOINT, true, resData)
        -- 保底：补发层快照修正客户端显示
        local layer = pd.map_layer
        if layer then
            Server.SendLayerSnapshot(uid, layer, conn)
        end
        return
    end

    -- 24小时冷却检查
    local lastSwitch = myGuild.last_sp_switch_time or 0
    local elapsed = os.time() - lastSwitch
    if elapsed < 86400 then
        local remainH = math.ceil((86400 - elapsed) / 3600)
        resData["Msg"] = Variant(string.format("24小时内只能更换一次据点，还需等待约%d小时。", remainH))
        conn:SendRemoteEvent(Settings.EVENTS.RES_SWITCH_STRONGPOINT, true, resData)
        return
    end

    -- 启动占领倒计时（标记为更换模式）
    -- 总是覆盖旧计时器，避免残留计时器阻止新请求
    local captureTime = Settings.TERRITORY_WAR.FREE_CAPTURE_SEC or 10
    spCaptureTimers_[newSpId] = {
        attacker_guild_id = pd.guild_id,
        elapsed = 0,
        is_switch = true,       -- 标记为更换模式
        old_sp_id = oldSpId,    -- 旧据点 id
        old_sp_name = oldSpName,
    }

    -- 查找新据点名
    local newSpName = newSpId
    for _, layerSps in pairs(Settings.STRONGPOINTS_BY_LAYER) do
        for _, sp in ipairs(layerSps) do
            if sp.id == newSpId then newSpName = sp.name; break end
        end
    end

    resData["Success"] = Variant(true)
    resData["Msg"] = Variant("正在更换据点为「" .. newSpName .. "」...")
    resData["SpName"] = Variant(newSpName)
    resData["CaptureSec"] = Variant(captureTime)
    conn:SendRemoteEvent(Settings.EVENTS.RES_SWITCH_STRONGPOINT, true, resData)
end

-- 请求防守据点（帮会成员进入防守状态）
function Server_OnReqDefendStrongpoint(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local resData = VariantMap()

    -- 检查玩家有帮会
    if not pd.guild_id or pd.guild_id == "" then
        resData["Success"] = Variant(false)
        resData["Msg"] = Variant("你没有帮会，无法防守。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_DEFEND_STRONGPOINT, true, resData)
        return
    end

    -- 自动查找帮会拥有的据点
    local spId = nil
    for sid, owner in pairs(strongpointOwners_) do
        if owner.guild_id == pd.guild_id then
            spId = sid
            break
        end
    end

    if not spId then
        resData["Success"] = Variant(false)
        resData["Msg"] = Variant("你的帮会还没有据点，无需防守。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_DEFEND_STRONGPOINT, true, resData)
        return
    end

    -- 注册为防守者
    if not spDefenders_[spId] then spDefenders_[spId] = {} end
    local alreadyIn = false
    for _, dUid in ipairs(spDefenders_[spId]) do
        if dUid == uid then alreadyIn = true; break end
    end
    if not alreadyIn then
        spDefenders_[spId][#spDefenders_[spId] + 1] = uid
    end

    -- 如果有占领计时器，因有人上线防守而取消
    if spCaptureTimers_[spId] then
        spCaptureTimers_[spId] = nil
    end

    resData["Success"] = Variant(true)
    resData["Msg"] = Variant("你已进入防守状态，等待敌方挑战。")
    conn:SendRemoteEvent(Settings.EVENTS.RES_DEFEND_STRONGPOINT, true, resData)
end

-- 请求 1v1 挑战
-- ============================================================================
-- 任务系统：客户端请求当前任务
-- ============================================================================
function Server_OnReqQuestInfo(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end
    Quest.InitPlayer(pd)
    Quest.PushActiveQuest(pd, conn)
end

-- ============================================================================
-- Boss 挑战系统
-- ============================================================================
function Server_OnReqChallengeBoss(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local bossId = eventData["BossId"]:GetString()
    local bossDef = Settings.BOSS_MAP[bossId]
    if not bossDef then
        Server.PushLog(conn, "<红>无效的首领目标。</红>")
        return
    end

    -- 检查是否已击败
    local defeated = pd.boss_defeated or {}
    for _, id in ipairs(defeated) do
        if id == bossId then
            Server.PushLog(conn, string.format("<黄>你已经击败了【%s】。</黄>", bossDef.name))
            return
        end
    end

    -- 检查是否在战斗中
    if Combat.IsInBattle(uid) then
        Server.PushLog(conn, "<红>战斗中无法挑战首领！</红>")
        return
    end

    -- 检查当前层是否是 boss 所在的 gate_layer（玩家必须在该层才能挑战）
    local maxLayer = pd.max_battlefield_layer or Settings.BATTLEFIELD_INITIAL_LAYERS
    if bossDef.gate_layer > maxLayer then
        Server.PushLog(conn, "<红>你尚未到达该首领所在的层。</红>")
        return
    end

    -- 标记 Boss 战斗（用于 OnBattleFinished 特殊处理）
    pd._battleBossId = bossId

    -- 任务系统：发起 Boss 挑战
    Quest.OnChallengeBoss(pd, conn, bossId)
    Activity.OnChallengeBoss(pd)

    Server.PushLog(conn, string.format("<黄>【首领战】你向【%s】发起挑战！</黄>", bossDef.name))
    -- 直接传 bossId，Shared.GetMonsterDef 会 fallback 到 BOSS_MAP
    -- 帮会战斗加成
    local gBuff2 = Server.GetGuildBuff(pd)
    pd.guild_combat_bonus = gBuff2 and gBuff2.combat_bonus or 0
    Combat.StartBattle(uid, conn, pd, bossId)
end

function Server_OnReqPvpChallenge(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local targetUid = eventData["TargetUid"]:GetString()
    local resData = VariantMap()

    -- 自动查找攻击者正在攻击的据点
    local spId = nil
    for sid, attackers in pairs(spAttackers_) do
        for _, aUid in ipairs(attackers) do
            if aUid == uid then spId = sid; break end
        end
        if spId then break end
    end
    if not spId then
        resData["Success"] = Variant(false)
        resData["Msg"] = Variant("你还未参与据点攻击。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_PVP_CHALLENGE, true, resData)
        return
    end

    -- 验证目标在线
    local targetConn = connections_[targetUid]
    local targetPd = players_[targetUid]
    if not targetConn or not targetPd then
        resData["Success"] = Variant(false)
        resData["Msg"] = Variant("对手已离线。")
        conn:SendRemoteEvent(Settings.EVENTS.RES_PVP_CHALLENGE, true, resData)
        return
    end

    -- 使用现有战斗系统进行 PvP（简化：比较战力，随机因子）
    local atkStats = Shared.CalcStats(pd)
    local defStats = Shared.CalcStats(targetPd)
    local atkPower = (atkStats.atk or 10) + ((pd.realm or 1) - 1) * 12
    local defPower = (defStats.atk or 10) + ((targetPd.realm or 1) - 1) * 12
    local atkRoll = atkPower * (0.8 + math.random() * 0.4)
    local defRoll = defPower * (0.8 + math.random() * 0.4)

    local attackerWin = atkRoll > defRoll

    resData["Success"] = Variant(true)
    resData["Win"] = Variant(attackerWin)
    resData["TargetName"] = Variant(targetPd.name or "?")

    if attackerWin then
        resData["Msg"] = Variant(string.format("你击败了 %s！", targetPd.name or "?"))
        -- 移除该防守者并启动复活计时器
        local defs = spDefenders_[spId]
        if defs then
            for i, dUid in ipairs(defs) do
                if dUid == targetUid then
                    table.remove(defs, i)
                    break
                end
            end
        end
        -- 启动复活倒计时（30s后可重新防守）
        spReviveTimers_[targetUid] = {
            spId = spId,
            remaining = Settings.TERRITORY_WAR.DEFENDER_REVIVE_SEC or 30,
        }
        -- 通知被击败的防守者
        if targetConn then
            local defeatData = VariantMap()
            defeatData["Msg"] = Variant(string.format(
                "你被 %s 击败！%d秒后自动复活。",
                pd.name or "?", Settings.TERRITORY_WAR.DEFENDER_REVIVE_SEC or 30))
            defeatData["ReviveSec"] = Variant(Settings.TERRITORY_WAR.DEFENDER_REVIVE_SEC or 30)
            targetConn:SendRemoteEvent(Settings.EVENTS.RES_PVP_CHALLENGE, true, defeatData)
        end
        -- 如果防守者全部被击败（含正在复活的不算），启动占领倒计时
        local remainingDefenders = GetOnlineDefenders(spId)
        -- 过滤掉正在复活中的
        local activeDefenders = {}
        for _, dUid in ipairs(remainingDefenders) do
            if not spReviveTimers_[dUid] then
                activeDefenders[#activeDefenders + 1] = dUid
            end
        end
        if #activeDefenders == 0 then
            spCaptureTimers_[spId] = { attacker_guild_id = pd.guild_id, elapsed = 0 }
            resData["AllDefeated"] = Variant(true)
        end
    else
        resData["Msg"] = Variant(string.format("你被 %s 击败了...", targetPd.name or "?"))
    end

    conn:SendRemoteEvent(Settings.EVENTS.RES_PVP_CHALLENGE, true, resData)

    -- 通知防守者结果
    local notifyDef = VariantMap()
    notifyDef["AttackerName"] = Variant(pd.name or "?")
    notifyDef["Win"] = Variant(not attackerWin)
    notifyDef["SpId"] = Variant(spId)
    targetConn:SendRemoteEvent(Settings.EVENTS.RES_PVP_CHALLENGE, true, notifyDef)
end

-- 领地战 Update 逻辑（在 Server_OnUpdate 中调用）
function Server.TerritoryWarTick(dt)
    local wasActive = territoryWarActive_
    -- 管理员强制覆盖优先于时间判断
    if forceWarOverride_ ~= nil then
        territoryWarActive_ = forceWarOverride_
    else
        territoryWarActive_ = IsTerritoryWarTime()
    end

    -- 开战通知
    if territoryWarActive_ and not wasActive then
        local notifyData = VariantMap()
        notifyData["Msg"] = Variant("⚔ 领地战开始！前往帮会领地层争夺据点！")
        for connUid, conn in pairs(connections_) do
            conn:SendRemoteEvent(Settings.EVENTS.NOTIFY_WAR_START, true, notifyData)
        end
        -- 清空攻防状态
        spDefenders_ = {}
        spAttackers_ = {}
        spCaptureTimers_ = {}
    end

    -- 结束通知
    if not territoryWarActive_ and wasActive then
        local notifyData = VariantMap()
        notifyData["Msg"] = Variant("领地战结束！据点归属已确定。")
        for connUid, conn in pairs(connections_) do
            conn:SendRemoteEvent(Settings.EVENTS.NOTIFY_WAR_END, true, notifyData)
        end
        spDefenders_ = {}
        spAttackers_ = {}
        spCaptureTimers_ = {}
    end

    -- 每日据点收益结算（每天凌晨第一次 tick 触发）
    Server.StrongholdDailyReward()

    -- 处理防守者复活计时器
    if territoryWarActive_ then
        TickDefenderRevive(dt)
    end

    -- 处理占领计时器（始终 tick，不受 territoryWarActive_ 限制）
    -- 原因：计时器在请求时已验证领地战活跃，启动后应保证完成
    do
        local captureTime = Settings.TERRITORY_WAR.FREE_CAPTURE_SEC or 60
        for spId, timer in pairs(spCaptureTimers_) do
            timer.elapsed = timer.elapsed + dt
            -- 每10秒打印一次进度日志（调试用）
            local prevSec = math.floor((timer.elapsed - dt))
            local currSec = math.floor(timer.elapsed)
            if math.floor(currSec / 10) > math.floor(prevSec / 10) then
                print(string.format("[TerritoryWar] 据点 %s 占领进度: %.0f/%ds", spId, timer.elapsed, captureTime))
            end
            if timer.elapsed >= captureTime then
                -- 占领成功
                local attackerGuild = guilds_[timer.attacker_guild_id]
                local guildName = attackerGuild and attackerGuild.name or "?"
                -- 查找据点名
                local spName = spId
                for _, layerSps in pairs(Settings.STRONGPOINTS_BY_LAYER) do
                    for _, sp in ipairs(layerSps) do
                        if sp.id == spId then spName = sp.name; break end
                    end
                end

                -- 如果是更换模式：释放旧据点 + 记录冷却时间
                if timer.is_switch and timer.old_sp_id then
                    strongpointOwners_[timer.old_sp_id] = nil
                    if attackerGuild then
                        attackerGuild.last_sp_switch_time = os.time()
                    end
                    print(string.format("[TerritoryWar] 帮会「%s」更换据点: %s → %s", guildName, timer.old_sp_name or timer.old_sp_id, spName))
                end

                strongpointOwners_[spId] = {
                    guild_id = timer.attacker_guild_id,
                    guild_name = guildName,
                    sp_name = spName,
                    captured_at = os.time(),
                }
                spCaptureTimers_[spId] = nil
                SaveGuildData()

                -- 触发参与攻击者的据点胜利成就/周常
                local attackers = spAttackers_[spId] or {}
                for _, aUid in ipairs(attackers) do
                    local aPd = players_[aUid]
                    if aPd then Activity.OnTerritoryWin(aPd) end
                end

                -- 广播占领通知
                local notifyData = VariantMap()
                notifyData["SpId"] = Variant(spId)
                notifyData["SpName"] = Variant(spName)
                notifyData["NewOwner"] = Variant(guildName)
                notifyData["NewOwnerId"] = Variant(timer.attacker_guild_id or "")
                -- 如果是更换，额外带上旧据点 id 让客户端更新地图
                if timer.is_switch and timer.old_sp_id then
                    notifyData["OldSpId"] = Variant(timer.old_sp_id)
                end
                for connUid, conn in pairs(connections_) do
                    conn:SendRemoteEvent(Settings.EVENTS.NOTIFY_SP_CAPTURED, true, notifyData)
                end
            end
        end
    end
end

-- ============================================================================
-- 任务系统事件处理
-- ============================================================================

--- 客户端请求领取日常任务奖励
function Server_OnReqClaimDaily(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local questId = eventData["QuestId"]:GetString()
    local ok, err = Quest.ClaimDailyReward(pd, conn, questId)
    if not ok then
        Server.PushLog(conn, string.format("<红>领取失败：%s</红>", err or "未知错误"))
    end
    -- 刷新玩家数据（货币变动）
    Server.PushPlayerData(uid, conn)
end

--- 客户端主动请求完整任务面板数据
function Server_OnReqQuestInfoReq(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    Quest.PushQuestState(pd, conn)
end

-- ============================================================================
-- 好友系统
-- ============================================================================

local function PushFriendList(uid, conn)
    local pd = players_[uid]
    if not pd or not conn then return end
    local friends = pd.friends or {}
    -- 附加在线状态
    local result = {}
    for i, f in ipairs(friends) do
        result[i] = {
            uid    = f.uid,
            name   = f.name,
            online = connections_[f.uid] ~= nil,
        }
    end
    local data = VariantMap()
    data["FriendsJson"] = Variant(cjson.encode(result))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_FRIEND_LIST, true, data)
end

function Server_OnReqFriendList(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    if not uid then return end
    PushFriendList(uid, conn)
end

function Server_OnReqAddFriend(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local targetName = eventData["TargetName"]:GetString()
    if not targetName or targetName == "" then
        Server.PushLog(conn, "<红>请输入好友名称</红>")
        return
    end
    if targetName == pd.name then
        Server.PushLog(conn, "<红>不能添加自己为好友</红>")
        return
    end

    -- 初始化好友列表
    if not pd.friends then pd.friends = {} end
    if #pd.friends >= 50 then
        Server.PushLog(conn, "<红>好友已满（上限50人）</红>")
        return
    end

    -- 查找目标玩家（在线优先，否则查注册表）
    local targetUid, targetPdName = nil, nil
    for tuid, tpd in pairs(players_) do
        if tpd.name == targetName then
            targetUid = tuid
            targetPdName = tpd.name
            break
        end
    end
    if not targetUid then
        Server.PushLog(conn, string.format("<红>找不到玩家【%s】</红>", targetName))
        return
    end

    -- 检查是否已是好友
    for _, f in ipairs(pd.friends) do
        if f.uid == targetUid then
            Server.PushLog(conn, string.format("<红>【%s】已是你的好友</红>", targetName))
            return
        end
    end

    -- 双向添加
    pd.friends[#pd.friends + 1] = { uid = targetUid, name = targetPdName }
    local targetPd = players_[targetUid]
    if targetPd then
        if not targetPd.friends then targetPd.friends = {} end
        targetPd.friends[#targetPd.friends + 1] = { uid = uid, name = pd.name }
        -- 通知对方
        local targetConn = connections_[targetUid]
        if targetConn then
            Server.PushLog(targetConn, string.format("<绿>【%s】添加你为好友</绿>", pd.name))
            PushFriendList(targetUid, targetConn)
        end
    end

    Server.PushLog(conn, string.format("<绿>已添加【%s】为好友</绿>", targetPdName))
    PushFriendList(uid, conn)
end

function Server_OnReqRemoveFriend(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd or not pd.friends then return end

    local targetUid = eventData["TargetUid"]:GetString()
    if not targetUid or targetUid == "" then return end

    -- 从自己的列表移除
    local removedName = nil
    for i, f in ipairs(pd.friends) do
        if f.uid == targetUid then
            removedName = f.name
            table.remove(pd.friends, i)
            break
        end
    end
    if not removedName then
        Server.PushLog(conn, "<红>该玩家不在好友列表中</红>")
        return
    end

    -- 从对方列表移除
    local targetPd = players_[targetUid]
    if targetPd and targetPd.friends then
        for i, f in ipairs(targetPd.friends) do
            if f.uid == uid then
                table.remove(targetPd.friends, i)
                break
            end
        end
        local targetConn = connections_[targetUid]
        if targetConn then PushFriendList(targetUid, targetConn) end
    end

    Server.PushLog(conn, string.format("<灰>已删除好友【%s】</灰>", removedName))
    PushFriendList(uid, conn)
end

-- ============================================================================
-- 活动系统（签到 / 成就 / 周常 / 天梯 / 限时活动）
-- ============================================================================

local function PushActivityData(uid, conn)
    local pd = players_[uid]
    if not pd or not conn then return end
    local signStatus = Activity.GetSignInStatus(pd)
    local activeEvents = Activity.GetActiveEvents()
    local data = VariantMap()
    data["DataJson"] = Variant(cjson.encode({
        sign_in = signStatus,
        active_events = activeEvents,
    }))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_ACTIVITY_DATA, true, data)
end

-- ===================== 称号系统 (Title System) =====================

--- 检查并自动授予成就关联称号
local function CheckAndGrantTitles(pd, conn, uid)
    if not Settings.TITLES then return end
    local owned = pd.titles_owned or {}
    pd.titles_owned = owned
    local granted = false
    for _, titleDef in ipairs(Settings.TITLES) do
        if titleDef.source == "achievement" and titleDef.req_ach then
            -- 检查是否已拥有
            local alreadyOwned = false
            for _, tid in ipairs(owned) do
                if tid == titleDef.id then alreadyOwned = true; break end
            end
            if not alreadyOwned then
                -- 检查成就是否已完成（claimed）
                local achs = pd.achievements or {}
                if achs[titleDef.req_ach] and achs[titleDef.req_ach].claimed then
                    table.insert(owned, titleDef.id)
                    granted = true
                    if conn then
                        Server.PushLog(conn, string.format("<金>获得称号：%s</金>", titleDef.name))
                    end
                end
            end
        end
    end
    if granted then
        Server.SavePlayerData(uid)
    end
end


local function PushAchievements(uid, conn)
    local pd = players_[uid]
    if not pd or not conn then return end
    local states = Activity.GetAchievementStates(pd)
    local data = VariantMap()
    data["DataJson"] = Variant(cjson.encode(states))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_ACHIEVEMENTS, true, data)
end

local function PushWeeklyData(uid, conn)
    local pd = players_[uid]
    if not pd or not conn then return end
    local states = Activity.GetWeeklyStates(pd)
    local data = VariantMap()
    data["DataJson"] = Variant(cjson.encode(states))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_WEEKLY_DATA, true, data)
end

PushPvpLadderData = function(uid, conn)
    local pd = players_[uid]
    if not pd or not conn then return end
    local ladderData = Activity.GetLadderData(pd)
    local data = VariantMap()
    data["DataJson"] = Variant(cjson.encode(ladderData))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_PVP_LADDER_DATA, true, data)
end

local function PushEventsStatus(uid, conn)
    local pd = players_[uid]
    if not pd or not conn then return end
    local activeEvents = Activity.GetActiveEvents()
    local data = VariantMap()
    data["DataJson"] = Variant(cjson.encode(activeEvents))
    conn:SendRemoteEvent(Settings.EVENTS.PUSH_EVENTS_STATUS, true, data)
end

-- 签到
function Server_OnReqDailySign(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local ok, msg, desc = Activity.DoSignIn(pd)
    if ok then
        Server.PushLog(conn, string.format("<绿>%s —— %s</绿>", msg, desc or ""))
        Server.PushPlayerData(uid, conn)
        Server.SavePlayerData(uid)
    else
        Server.PushLog(conn, string.format("<黄>%s</黄>", msg))
    end
    PushActivityData(uid, conn)
end

-- 领取成就
function Server_OnReqClaimAchievement(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local achId = eventData["AchId"]:GetString()
    local ok, msg = Activity.ClaimAchievement(pd, achId)
    if ok then
        Server.PushLog(conn, string.format("<金>%s</金>", msg))
        CheckAndGrantTitles(pd, conn, uid)
        Server.PushPlayerData(uid, conn)
        Server.SavePlayerData(uid)
    else
        Server.PushLog(conn, string.format("<黄>%s</黄>", msg))
    end
    PushAchievements(uid, conn)
end

-- 请求周常信息
function Server_OnReqWeeklyInfo(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    if not uid then return end
    PushWeeklyData(uid, conn)
end

-- 领取周常奖励
function Server_OnReqClaimWeekly(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local questId = eventData["QuestId"]:GetString()
    local ok, msg = Activity.ClaimWeekly(pd, questId)
    if ok then
        Server.PushLog(conn, string.format("<绿>%s</绿>", msg))
        Server.PushPlayerData(uid, conn)
        Server.SavePlayerData(uid)
    else
        Server.PushLog(conn, string.format("<黄>%s</黄>", msg))
    end
    PushWeeklyData(uid, conn)
end

-- 请求天梯信息
function Server_OnReqPvpLadderInfo(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    if not uid then return end
    local pd = players_[uid]
    if pd then
        -- 打开天梯面板时检查赛季是否需要重置
        local wasReset = Activity.EnsureCurrentSeason(pd)
        if wasReset then
            Server.SavePlayerData(uid)
            Server.PushLog(conn, "<黄>新赛季开始！积分已重置，上赛季奖励可领取。</黄>")
        end
    end
    PushPvpLadderData(uid, conn)
end

-- 天梯匹配（回合制战斗版）
function Server_OnReqPvpLadderMatch(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    -- 确保赛季是最新的
    Activity.EnsureCurrentSeason(pd)

    -- 验证是否可匹配
    local canMatch, errMsg = Activity.CanLadderMatch(pd)
    if not canMatch then
        local resData = VariantMap()
        resData["DataJson"] = Variant(cjson.encode({ error = errMsg }))
        conn:SendRemoteEvent(Settings.EVENTS.RES_PVP_LADDER_MATCH, true, resData)
        return
    end

    -- 查找对手：优先在线玩家中积分相近的
    local myRating = pd.pvp_ladder and pd.pvp_ladder.rating or Settings.PVP_LADDER.INITIAL_RATING
    local bestUid, bestDiff = nil, math.huge
    for otherUid, otherPd in pairs(players_) do
        if otherUid ~= uid and not otherPd.in_battle then
            local otherRating = otherPd.pvp_ladder and otherPd.pvp_ladder.rating or Settings.PVP_LADDER.INITIAL_RATING
            local diff = math.abs(otherRating - myRating)
            if diff < bestDiff then
                bestUid = otherUid
                bestDiff = diff
            end
        end
    end

    -- 构造对手数据
    local opponentData, opponentName, opponentRating, opponentUid
    if bestUid and players_[bestUid] then
        -- 真实玩家对手
        opponentData = players_[bestUid]
        opponentRating = opponentData.pvp_ladder and opponentData.pvp_ladder.rating or Settings.PVP_LADDER.INITIAL_RATING
        opponentName = opponentData.name or "无名侠客"
        opponentUid = bestUid
    else
        -- 无在线对手：生成AI虚拟对手（基于玩家自身数据缩放）
        opponentRating = myRating + math.random(-100, 100)
        opponentName = "天梯幻影"
        opponentUid = nil
        -- 构造虚拟对手数据（基于自身属性，略微随机化）
        local scaleFactor = 0.8 + math.random() * 0.4  -- 0.8~1.2
        opponentData = {
            realm = pd.realm or 1,
            hp = math.floor((pd.hp or 100) * scaleFactor),
            mp = pd.mp or 50,
            equipped_skills = pd.equipped_skills or {},
            equipment = pd.equipment or {},
            attributes = {},
        }
        -- 缩放属性
        if pd.attributes then
            for k, v in pairs(pd.attributes) do
                opponentData.attributes[k] = math.floor(v * scaleFactor)
            end
        end
    end

    -- 记录PvP战斗标志（用于 OnBattleFinished 判断）
    pd._battlePvpData = {
        opponentUid = opponentUid,
        opponentName = opponentName,
        opponentRating = opponentRating,
    }

    -- 启动回合制PvP战斗
    Combat.StartPvPBattle(uid, conn, pd, opponentData, opponentName, opponentRating)

    -- 通知客户端战斗已开始
    local resData = VariantMap()
    local oppRank = Activity.GetRankByRating(opponentRating)
    resData["DataJson"] = Variant(cjson.encode({
        started = true,
        opponent_name = opponentName,
        opponent_rating = opponentRating,
        opponent_rank = oppRank.name,
    }))
    conn:SendRemoteEvent(Settings.EVENTS.RES_PVP_LADDER_MATCH, true, resData)
end

-- ============================================================================
-- 灵石功能：改名 / 帮会改名
-- ============================================================================

function Server_OnReqRename(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local newName = eventData["NewName"]:GetString()
    local cost = Settings.SPIRIT_STONE.RENAME_COST
    local resData = VariantMap()

    -- 灵石检查
    if (pd.spirit_stone or 0) < cost then
        Server.PushLog(conn, string.format("<红>改名需要%d灵石，你的灵石不足。</红>", cost))
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("灵石不足")
        conn:SendRemoteEvent(Settings.EVENTS.RES_RENAME, true, resData)
        return
    end

    -- 名称长度检查
    local nameLen = utf8.len(newName) or 0
    if nameLen < Settings.SPIRIT_STONE.NAME_MIN_LEN or nameLen > Settings.SPIRIT_STONE.NAME_MAX_LEN then
        Server.PushLog(conn, string.format("<红>名称长度需要%d~%d个字。</红>", Settings.SPIRIT_STONE.NAME_MIN_LEN, Settings.SPIRIT_STONE.NAME_MAX_LEN))
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("名称长度不符合要求")
        conn:SendRemoteEvent(Settings.EVENTS.RES_RENAME, true, resData)
        return
    end

    -- 名称重复检查
    for _, p in pairs(players_) do
        if p.name == newName and p.uid ~= uid then
            Server.PushLog(conn, "<红>该名字已被其他人使用。</红>")
            resData["Success"] = Variant(false)
            resData["Msg"]     = Variant("名字已被占用")
            conn:SendRemoteEvent(Settings.EVENTS.RES_RENAME, true, resData)
            return
        end
    end

    -- 扣灵石，改名
    pd.spirit_stone = (pd.spirit_stone or 0) - cost
    local oldName = pd.name
    pd.name = newName
    Server.PushLog(conn, string.format("<金>改名成功！%s → %s（消耗%d灵石）</金>", oldName, newName, cost))

    resData["Success"] = Variant(true)
    resData["NewName"] = Variant(newName)
    resData["Msg"]     = Variant("改名成功")
    conn:SendRemoteEvent(Settings.EVENTS.RES_RENAME, true, resData)
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
end

-- ============================================================================
-- 邀请码生成
-- ============================================================================
local INVITE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

function Server.GenerateInviteCode()
    for _ = 1, 100 do  -- 最多尝试100次避免冲突
        local code = ""
        for i = 1, 6 do
            local idx = math.random(1, #INVITE_CHARS)
            code = code .. INVITE_CHARS:sub(idx, idx)
        end
        if not inviteCodes_[code] then
            return code
        end
    end
    -- 极端情况：用时间戳兜底
    return string.format("%06X", os.time() % 0xFFFFFF)
end

-- ============================================================================
-- 角色创建（进入游戏流程）
-- ============================================================================
function Server_OnReqCreateCharacter(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local resData = VariantMap()

    -- 只有新玩家才能创建角色
    if not pd._needCreate then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("角色已创建")
        conn:SendRemoteEvent(Settings.EVENTS.RES_CREATE_CHARACTER, true, resData)
        return
    end

    local name = eventData["Name"]:GetString()
    local gender = eventData["Gender"]:GetString()
    local inviteCode = eventData["InviteCode"]:GetString()

    -- 名称长度校验
    local nameLen = utf8.len(name) or 0
    if nameLen < Settings.SPIRIT_STONE.CREATE_NAME_MIN_LEN or nameLen > Settings.SPIRIT_STONE.CREATE_NAME_MAX_LEN then
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant(string.format("道号需要%d-%d个字", Settings.SPIRIT_STONE.CREATE_NAME_MIN_LEN, Settings.SPIRIT_STONE.CREATE_NAME_MAX_LEN))
        conn:SendRemoteEvent(Settings.EVENTS.RES_CREATE_CHARACTER, true, resData)
        return
    end

    -- 名称重复检查（在线玩家）
    for _, p in pairs(players_) do
        if p.name == name and p.uid ~= uid then
            resData["Success"] = Variant(false)
            resData["Msg"]     = Variant("此道号已被他人使用")
            conn:SendRemoteEvent(Settings.EVENTS.RES_CREATE_CHARACTER, true, resData)
            return
        end
    end

    -- 邀请码校验
    local inviterUid = nil
    if inviteCode ~= "" then
        if #inviteCode ~= 6 or not inviteCode:match("^[A-Z0-9]+$") then
            resData["Success"] = Variant(false)
            resData["Msg"]     = Variant("邀请码格式错误")
            conn:SendRemoteEvent(Settings.EVENTS.RES_CREATE_CHARACTER, true, resData)
            return
        end
        -- 不能填自己的邀请码
        if inviteCode == pd.invite_code then
            resData["Success"] = Variant(false)
            resData["Msg"]     = Variant("不能填写自己的邀请码")
            conn:SendRemoteEvent(Settings.EVENTS.RES_CREATE_CHARACTER, true, resData)
            return
        end
        inviterUid = inviteCodes_[inviteCode]
        if not inviterUid then
            resData["Success"] = Variant(false)
            resData["Msg"]     = Variant("邀请码不存在")
            conn:SendRemoteEvent(Settings.EVENTS.RES_CREATE_CHARACTER, true, resData)
            return
        end
    end

    -- 性别校验
    if gender ~= "male" and gender ~= "female" then
        gender = "male"
    end

    -- 设置角色信息
    pd.name = name
    pd.gender = gender
    pd._needCreate = nil  -- 标记创建完成

    -- 注册邀请码
    if pd.invite_code and pd.invite_code ~= "" then
        inviteCodes_[pd.invite_code] = uid
    end

    -- 注册到玩家名册
    playerRegistry_[pd.name] = uid
    if not registryUidSet_[uid] then
        registryUidSet_[uid] = true
        serverCloud.list:Add(0, "player_registry", { uid = uid, name = pd.name })
    end

    -- 处理邀请奖励
    local reward = Settings.SPIRIT_STONE.INVITE_REWARD
    if inviterUid then
        pd.invited_by = inviteCode
        -- 新玩家得灵石
        pd.spirit_stone = (pd.spirit_stone or 0) + reward
        pd._moneySyncStone = math.floor(pd.spirit_stone)  -- 同步基准值（已调用money:Add）
        serverCloud.money:Add(uid, "spirit_stone", reward)
        -- 邀请人得灵石
        local inviterPd = players_[inviterUid]
        if inviterPd then
            inviterPd.spirit_stone = (inviterPd.spirit_stone or 0) + reward
            inviterPd._moneySyncStone = math.floor(inviterPd.spirit_stone)  -- 同步基准值
            serverCloud.money:Add(inviterUid, "spirit_stone", reward)
            -- 通知邀请人
            local inviterConn = connections_[inviterUid]
            if inviterConn then
                Server.PushLog(inviterConn, string.format("<金>你的邀请码被【%s】使用，获得%d灵石奖励！</金>", name, reward))
                Server.PushPlayerData(inviterUid, inviterConn)
            end
            Server.SavePlayerData(inviterUid)
        end
        print(string.format("[Server] 邀请奖励：新玩家 %s 填写邀请码 %s（uid=%s），双方各得 %d 灵石",
            name, inviteCode, tostring(inviterUid), reward))
    end

    -- 成功
    resData["Success"] = Variant(true)
    resData["Msg"]     = Variant("创建成功")
    conn:SendRemoteEvent(Settings.EVENTS.RES_CREATE_CHARACTER, true, resData)

    -- 推送完整玩家数据（名字已更新）
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
    print(string.format("[Server] 角色创建完成 uid=%s name=%s gender=%s", tostring(uid), name, gender))
end

function Server_OnReqGuildRename(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local newName = eventData["NewName"]:GetString()
    local cost = Settings.SPIRIT_STONE.GUILD_RENAME_COST
    local resData = VariantMap()

    -- 检查是否有帮会
    local guildId = pd.guild_id or ""
    if guildId == "" or not guilds_[guildId] then
        Server.PushLog(conn, "<红>你还没有加入帮会。</红>")
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("未加入帮会")
        conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_RENAME, true, resData)
        return
    end

    -- 检查是否帮主
    local guild = guilds_[guildId]
    if guild.leader_uid ~= uid then
        Server.PushLog(conn, "<红>只有帮主才能修改帮会名称。</红>")
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("权限不足")
        conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_RENAME, true, resData)
        return
    end

    -- 灵石检查
    if (pd.spirit_stone or 0) < cost then
        Server.PushLog(conn, string.format("<红>帮会改名需要%d灵石。</红>", cost))
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("灵石不足")
        conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_RENAME, true, resData)
        return
    end

    -- 名称长度检查
    local nameLen = utf8.len(newName) or 0
    if nameLen < Settings.SPIRIT_STONE.NAME_MIN_LEN or nameLen > Settings.SPIRIT_STONE.NAME_MAX_LEN then
        Server.PushLog(conn, string.format("<红>帮会名长度需要%d~%d个字。</红>", Settings.SPIRIT_STONE.NAME_MIN_LEN, Settings.SPIRIT_STONE.NAME_MAX_LEN))
        resData["Success"] = Variant(false)
        resData["Msg"]     = Variant("名称长度不符合要求")
        conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_RENAME, true, resData)
        return
    end

    -- 名称重复检查
    for _, g in pairs(guilds_) do
        if g.name == newName then
            Server.PushLog(conn, "<红>该帮会名已被占用。</红>")
            resData["Success"] = Variant(false)
            resData["Msg"]     = Variant("帮会名已被占用")
            conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_RENAME, true, resData)
            return
        end
    end

    -- 扣灵石，修改帮会名
    pd.spirit_stone = (pd.spirit_stone or 0) - cost
    local oldName = guild.name
    guild.name = newName
    -- 更新所有成员的 guild_name 缓存
    for _, memberUid in ipairs(guild.members or {}) do
        local mp = players_[memberUid]
        if mp then mp.guild_name = newName end
    end
    Server.PushLog(conn, string.format("<金>帮会改名成功！%s → %s（消耗%d灵石）</金>", oldName, newName, cost))

    resData["Success"]  = Variant(true)
    resData["NewName"]  = Variant(newName)
    resData["Msg"]      = Variant("帮会改名成功")
    conn:SendRemoteEvent(Settings.EVENTS.RES_GUILD_RENAME, true, resData)
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
    SaveGuildData()
end


-- 灵石免死开关
function Server_OnReqToggleRevive(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local enabled = eventData["Enabled"]:GetBool()
    pd.revive_shield = enabled
    local cost = Settings.SPIRIT_STONE.REVIVE_COST
    if enabled then
        Server.PushLog(conn, string.format("<金>💎灵石免死已开启！战败时自动消耗%d灵石免除惩罚。</金>", cost))
    else
        Server.PushLog(conn, "<黄>灵石免死已关闭。</黄>")
    end
    Server.PushPlayerData(uid, conn)
end

-- 帮会加速升级
function Server_OnReqGuildBoost(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local cost = Settings.SPIRIT_STONE.GUILD_BOOST_COST
    local expGain = Settings.SPIRIT_STONE.GUILD_BOOST_EXP

    -- 检查帮会
    local guildId = pd.guild_id or ""
    if guildId == "" or not guilds_[guildId] then
        Server.PushLog(conn, "<红>你还没有加入帮会。</红>")
        return
    end

    -- 灵石检查
    if (pd.spirit_stone or 0) < cost then
        Server.PushLog(conn, string.format("<红>灵石不足！帮会加速需要%d灵石。</红>", cost))
        return
    end

    -- 扣灵石，增加帮会经验
    pd.spirit_stone = (pd.spirit_stone or 0) - cost
    local guild = guilds_[guildId]
    guild.exp = (guild.exp or 0) + expGain

    -- 检查是否触发升级
    local gCfg = Settings.GUILD
    local nextCfg = gCfg.LEVELS and gCfg.LEVELS[(guild.level or 1) + 1]
    if nextCfg and guild.exp >= nextCfg.exp and (guild.fund or 0) >= nextCfg.fund then
        guild.level = (guild.level or 1) + 1
        Server.PushLog(conn, string.format("<金>帮会升级！当前等级：%d</金>", guild.level))
    end

    Server.PushLog(conn, string.format("<金>💎消耗%d灵石，帮会获得%d经验！</金>", cost, expGain))
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
    SaveGuildData()
end


function Server_OnReqSkillTierUp(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local skillId = eventData["SkillId"]:GetString()
    if not skillId or skillId == "" then return end

    -- 查找玩家功法
    local sk = nil
    for _, s in ipairs(pd.skills or {}) do
        if (s.id or s.skill_id) == skillId then
            sk = s
            break
        end
    end
    if not sk then
        Server.PushLog(conn, "<红>未找到该功法。</红>")
        return
    end

    -- 获取功法定义
    local def = Shared.GetSkillDef(skillId)
    if not def then
        Server.PushLog(conn, "<红>功法定义不存在。</红>")
        return
    end

    -- 检查熟练度是否满级
    if (sk.proficiency or 0) < (def.max_proficiency or 100) then
        Server.PushLog(conn, "<红>功法熟练度未满，无法升阶。需要先修炼至「返璞归真」。</红>")
        return
    end

    -- 检查当前阶层
    local curTier = sk.tier or 0
    local maxTier = Settings.SKILL_TIER_UP.MAX_TIER
    if curTier >= maxTier then
        Server.PushLog(conn, "<黄>该功法已达最高阶「大成」，无法继续升阶。</黄>")
        return
    end

    -- 灵石消耗
    local cost = Settings.SKILL_TIER_UP.COSTS[curTier]
    if not cost then
        Server.PushLog(conn, "<红>升阶配置异常。</红>")
        return
    end
    if (pd.spirit_stone or 0) < cost then
        Server.PushLog(conn, string.format("<红>灵石不足！升阶需要%d灵石，当前%d。</红>", cost, pd.spirit_stone or 0))
        return
    end

    -- 执行升阶
    pd.spirit_stone = (pd.spirit_stone or 0) - cost
    sk.tier = curTier + 1
    local newTierInfo = Settings.SKILL_TIER_UP.TIERS[sk.tier + 1]
    local newTierName = newTierInfo and newTierInfo.name or "大成"
    local bonus = newTierInfo and newTierInfo.bonus or 2.0
    local oldTierName = Settings.SKILL_TIER_UP.TIERS[curTier + 1].name

    Server.PushLog(conn, string.format(
        "<金>💎功法《%s》升阶成功！%s → %s（属性×%.1f）消耗%d灵石。</金>",
        def.name, oldTierName, newTierName, bonus, cost
    ))

    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
end

function Server_OnReqBuyTitle(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local titleId = eventData["TitleId"]:GetString()

    -- 找到称号定义
    local titleDef = nil
    for _, t in ipairs(Settings.TITLES) do
        if t.id == titleId then titleDef = t; break end
    end
    if not titleDef then
        Server.PushLog(conn, "<系统>称号不存在")
        return
    end

    -- 只能购买商店称号
    if titleDef.source ~= "shop" then
        Server.PushLog(conn, "<系统>该称号不可购买")
        return
    end

    -- 检查是否已拥有
    pd.titles_owned = pd.titles_owned or {}
    for _, tid in ipairs(pd.titles_owned) do
        if tid == titleId then
            Server.PushLog(conn, "<黄>你已拥有该称号</黄>")
            return
        end
    end

    -- 检查灵石
    local cost = titleDef.cost or 0
    if (pd.spirit_stone or 0) < cost then
        Server.PushLog(conn, string.format("<系统>灵石不足，需要%d颗", cost))
        return
    end

    -- 扣除灵石，添加称号
    pd.spirit_stone = pd.spirit_stone - cost
    table.insert(pd.titles_owned, titleId)

    Server.PushLog(conn, string.format("<金>购买称号「%s」成功，消耗%d灵石</金>", titleDef.name, cost))
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
end

function Server_OnReqEquipTitle(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid = Server.GetUidByConn(conn)
    local pd = players_[uid]
    if not pd then return end

    local titleId = eventData["TitleId"]:GetString()

    -- 空字符串表示卸下称号
    if titleId == "" then
        pd.active_title = ""
        Server.PushLog(conn, "<系统>已卸下称号")
        Server.PushPlayerData(uid, conn)
        Server.SavePlayerData(uid)
        return
    end

    -- 检查是否拥有
    pd.titles_owned = pd.titles_owned or {}
    local found = false
    for _, tid in ipairs(pd.titles_owned) do
        if tid == titleId then found = true; break end
    end
    if not found then
        Server.PushLog(conn, "<系统>你未拥有该称号")
        return
    end

    -- 装备
    pd.active_title = titleId
    local titleDef = nil
    for _, t in ipairs(Settings.TITLES) do
        if t.id == titleId then titleDef = t; break end
    end
    local name = titleDef and titleDef.name or titleId
    Server.PushLog(conn, string.format("<金>已装备称号「%s」</金>", name))
    Server.PushPlayerData(uid, conn)
    Server.SavePlayerData(uid)
end


-- ============================================================================
-- 恢复气血/内力（非战斗时，瞬间回满）
-- ============================================================================
function Server_OnReqRestore(eventType, eventData)
    local conn = eventData["Connection"]:GetPtr("Connection")
    local uid  = Server.GetUidByConn(conn)
    if not uid then return end
    local pd = players_[uid]
    if not pd then return end
    print("[Server] REQ_RESTORE uid=" .. tostring(uid))

    -- 战斗中不能使用
    if Combat.IsInBattle(uid) then
        Server.PushLog(conn, "<红>战斗中无法恢复，请使用丹药！</红>")
        return
    end

    -- 计算满血满蓝
    local stats = Shared.CalcStats(pd)
    local oldHp, oldMp = pd.hp or 0, pd.mp or 0
    pd.hp = stats.hp
    pd.mp = stats.mp

    if oldHp >= stats.hp and oldMp >= stats.mp then
        Server.PushLog(conn, "<绿>气血和内力已满，无需恢复。</绿>")
    else
        Server.PushLog(conn, string.format("<绿>恢复完成！气血 %d→%d  内力 %d→%d</绿>", oldHp, stats.hp, oldMp, stats.mp))
    end
    Server.PushPlayerData(uid, conn)
end

return Server
