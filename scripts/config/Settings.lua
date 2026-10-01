-- ============================================================================
-- config/Settings.lua - 全局配置
-- ============================================================================

local Settings = {}

-- ============================================================================
-- 网络事件名（客户端↔服务端通信）
-- ============================================================================
Settings.EVENTS = {
    -- 连接握手
    CLIENT_READY        = "ClientReady",        -- 客户端就绪
    INIT_PLAYER         = "InitPlayer",         -- 服务端初始化玩家数据

    -- 玩家操作请求（客户端→服务端）
    REQ_MOVE_SCENE      = "ReqMoveScene",       -- 请求切换场景
    REQ_INTERACT_NPC    = "ReqInteractNpc",     -- 请求与NPC交互
    REQ_START_BATTLE    = "ReqStartBattle",     -- 请求开始战斗
    REQ_FLEE_BATTLE     = "ReqFleeBattle",      -- 请求逃跑
    REQ_USE_ITEM        = "ReqUseItem",         -- 请求使用物品（药品）
    REQ_CULTIVATE       = "ReqCultivate",       -- 请求开始打坐修炼
    REQ_STOP_CULTIVATE  = "ReqStopCultivate",   -- 请求停止修炼
    REQ_UNBIND_SKILL    = "ReqUnbindSkill",     -- 请求解绑功法
    REQ_EQUIP_ITEM      = "ReqEquipItem",       -- 请求装备物品
    REQ_UNEQUIP_ITEM    = "ReqUnequipItem",     -- 请求卸下物品
    REQ_DISCARD_ITEM    = "ReqDiscardItem",     -- 请求丢弃物品

    -- 交易阁（客户端→服务端）
    REQ_MARKET_LIST     = "ReqMarketList",      -- 请求交易阁列表
    REQ_MARKET_BUY      = "ReqMarketBuy",       -- 请求购买
    REQ_MARKET_SELL     = "ReqMarketSell",      -- 请求上架
    REQ_MARKET_SELL_SILVER = "ReqMarketSellSilver", -- 请求上架银两
    REQ_MARKET_CANCEL   = "ReqMarketCancel",    -- 请求下架
    REQ_MARKET_HISTORY  = "ReqMarketHistory",   -- 请求我的交易记录
    REQ_MARKET_TRENDS   = "ReqMarketTrends",    -- 请求行情数据

    -- NPC交互（服务端→客户端）
    NPC_DIALOG          = "NpcDialog",          -- NPC对话内容
    NPC_SKILL_GRANT     = "NpcSkillGrant",      -- NPC传授功法（给两本）

    -- 数据推送（服务端→客户端）
    PUSH_GAME_LOG       = "PushGameLog",        -- 推送游戏日志文字
    PUSH_PLAYER_DATA    = "PushPlayerData",     -- 推送玩家完整数据
    PUSH_INVENTORY      = "PushInventory",      -- 推送背包数据
    PUSH_MARKET_DATA    = "PushMarketData",     -- 推送交易阁数据
    PUSH_MARKET_HISTORY = "PushMarketHistory",  -- 推送我的交易记录
    PUSH_MARKET_TRENDS  = "PushMarketTrends",   -- 推送行情数据
    PUSH_BATTLE_STATE   = "PushBattleState",    -- 推送战斗状态
    PUSH_BATTLE_END     = "PushBattleEnd",      -- 推送战斗结束
    PUSH_EXP_UPDATE     = "PushExpUpdate",      -- 轻量推送经验变化（修炼中每5秒）

    -- 管理员
    REQ_ADMIN_LOGIN         = "ReqAdminLogin",          -- 管理员登录验证
    ADMIN_LOGIN_RESULT      = "AdminLoginResult",        -- 管理员登录结果
    REQ_ADMIN_SELL          = "ReqAdminSell",            -- 管理员上架物品
    REQ_ADMIN_SET_NEWS      = "ReqAdminSetNews",         -- 修改传闻（持久化+广播）
    REQ_ADMIN_QUERY_PLAYER  = "ReqAdminQueryPlayer",     -- 查询玩家数据
    REQ_ADMIN_ADD_CURRENCY  = "ReqAdminAddCurrency",     -- 给玩家添加货币
    REQ_ADMIN_MODIFY_PLAYER = "ReqAdminModifyPlayer",   -- 管理员修改玩家属性 { TargetUid, Field, Value }
    REQ_ADMIN_LIST_PLAYERS  = "ReqAdminListPlayers",     -- 管理员请求玩家列表（分页）
    PUSH_NEWS_UPDATE        = "PushNewsUpdate",          -- 广播传闻更新→全体客户端
    PUSH_ADMIN_PLAYER_INFO  = "PushAdminPlayerInfo",     -- 推送玩家查询结果
    PUSH_ADMIN_RESULT       = "PushAdminResult",         -- 推送管理员操作结果
    PUSH_ADMIN_PLAYER_LIST  = "PushAdminPlayerList",     -- 推送玩家列表（分页结果）

    -- NPC商店
    REQ_SHOP_BUY        = "ReqShopBuy",         -- 请求NPC商店购买
    PUSH_SHOP_DATA      = "PushShopData",       -- 推送商店商品列表

    -- 小地点同屏玩家
    REQ_CHANGE_SPOT     = "ReqChangeSpot",      -- 请求切换小地点（客户端→服务端）
    PUSH_SPOT_PLAYERS   = "PushSpotPlayers",    -- 推送同场景玩家小地点列表（服务端→客户端）

    -- NPC 对话选项回调（客户端点击非战斗选项时通知服务端）
    REQ_NPC_OPTION      = "ReqNpcOption",       -- { NpcId, Action, Data } 客户端→服务端

    -- 福利广告
    REQ_AD_REWARD       = "ReqAdReward",        -- 客户端观看广告成功后请求奖励
    PUSH_AD_REWARD      = "PushAdReward",       -- 服务端推送广告奖励结果

    -- 战斗技能操作
    REQ_USE_SKILL       = "ReqUseSkill",        -- 玩家手动选择技能（客户端→服务端）
    REQ_TOGGLE_AUTO     = "ReqToggleAuto",      -- 切换自动/手动战斗（客户端→服务端）
    REQ_SET_BATTLE_SLOTS= "ReqSetBattleSlots",  -- 配置出战技能槽（客户端→服务端）

    -- 排名
    REQ_RANK            = "ReqRank",            -- 请求排行榜数据（客户端→服务端）
    PUSH_RANK           = "PushRank",           -- 推送排行榜数据（服务端→客户端）

    -- 聊天
    REQ_CHAT_SEND       = "ReqChatSend",        -- 发送聊天消息（客户端→服务端）
    PUSH_CHAT_MSG       = "PushChatMsg",        -- 推送聊天消息（服务端→客户端）
    PUSH_CHAT_HISTORY   = "PushChatHistory",    -- 推送历史消息（服务端→客户端，上线时）

    -- 管理员：重置自身存档（开发调试用）
    REQ_ADMIN_RESET_SELF   = "ReqAdminResetSelf",
    -- 管理员：重置指定玩家存档（开发调试用）
    REQ_ADMIN_RESET_PLAYER = "ReqAdminResetPlayer",
    -- 管理员：活动管理（修改Boss刷新、据点战时间等）
    REQ_ADMIN_SET_ACTIVITY = "ReqAdminSetActivity",

    -- 新手引导：战利品拾取
    REQ_PICKUP_LOOT        = "ReqPickupLoot",   -- 客户端点击拾取→服务端 { Token }
    PUSH_LOOT_RESULT       = "PushLootResult",  -- 服务端返回拾取结果 { Success, ItemName }

    -- 新手引导：重置教程（设置面板，开发/测试用）
    REQ_RESET_TUTORIAL     = "ReqResetTutorial",
    REQ_SKIP_TUTORIAL      = "ReqSkipTutorial",
    REQ_RESTORE            = "ReqRestore",

    -- 境界突破（客户端→服务端）
    REQ_BREAKTHROUGH       = "ReqBreakthrough",     -- 请求突破境界 { PillId }
    PUSH_BREAKTHROUGH      = "PushBreakthrough",    -- 突破结果 { Success, Msg, Realm, Layer }

    -- 修为丹（药铺购买+服用）
    REQ_REALM_PILL_SHOP    = "ReqRealmPillShop",    -- 请求修为丹商店列表
    PUSH_REALM_PILL_SHOP   = "PushRealmPillShop",   -- 推送修为丹商店数据
    REQ_BUY_REALM_PILL     = "ReqBuyRealmPill",     -- 购买修为丹 { PillIndex }
    REQ_USE_REALM_PILL     = "ReqUseRealmPill",     -- 服用修为丹 { PillIndex }
    PUSH_REALM_PILL_RESULT = "PushRealmPillResult", -- 服用结果 { Success, Msg, Exp }

    -- 炼丹系统（客户端→服务端，仅丹宗可用）
    REQ_ALCHEMY_CRAFT      = "ReqAlchemyCraft",     -- 请求炼丹 { RecipeId }
    PUSH_ALCHEMY_RESULT    = "PushAlchemyResult",   -- 炼丹结果 { Success, PillId, Count, Msg }
    REQ_BUY_MATERIAL       = "ReqBuyMaterial",      -- 购买炼丹材料 { MaterialId, Count }

    -- 好友系统
    REQ_FRIEND_LIST        = "ReqFriendList",       -- 请求好友列表
    REQ_ADD_FRIEND         = "ReqAddFriend",        -- 请求添加好友 { TargetName }
    REQ_REMOVE_FRIEND      = "ReqRemoveFriend",     -- 请求删除好友 { TargetUid }
    PUSH_FRIEND_LIST       = "PushFriendList",      -- 推送好友列表 { FriendsJson }

    -- 活动系统
    REQ_DAILY_SIGN         = "ReqDailySign",        -- 请求每日签到
    PUSH_ACTIVITY_DATA     = "PushActivityData",    -- 推送活动数据 { DataJson }

    -- 背包操作增强
    REQ_AUTO_EQUIP_BEST    = "ReqAutoEquipBest",    -- 一键最强装备
    REQ_SELL_ITEM          = "ReqSellItem",         -- 出售物品换银两 { ItemId, Count }
    REQ_BATCH_SELL         = "ReqBatchSell",        -- 批量出售 { ItemIds(json) }
}

-- ============================================================================
-- 场景定义
-- ============================================================================
Settings.SCENES = {
    BATTLEFIELD     = "battlefield",    -- 域外战场（10层）
    MAIN_CITY       = "main_city",      -- 主城
    SWORD_SECT      = "sword_sect",     -- 剑宗
    IRON_SECT       = "iron_sect",      -- 铁壁宗
    MEDICINE_SECT   = "medicine_sect",  -- 药王谷
    SHADOW_SECT     = "shadow_sect",    -- 天影楼
    QIDAN_SECT      = "qidan_sect",     -- 器丹宗
    ANCIENT_VILLAGE = "ancient_village",-- 古村
}

-- 进入场景后的默认落脚小地点
Settings.SCENE_DEFAULT_SPOT = {
    battlefield     = "layer_select",    -- 进入域外战场 → 入口大厅
    main_city       = "city_gate",       -- 进入主城 → 城门口
    sword_sect      = "sword_gate",      -- 进入剑宗 → 剑宗山门
    iron_sect       = "iron_gate",       -- 进入铁壁宗 → 宗门大门
    medicine_sect   = "valley_entrance", -- 进入药王谷 → 谷口
    shadow_sect     = "shadow_hall",     -- 进入天影楼 → 影楼大厅
    qidan_sect      = "sect_gate",       -- 进入器丹宗 → 宗门牌坊
    ancient_village = "stone_path",      -- 进入古村 → 青石小路（村口入口）
}

-- 场景描述文字
Settings.SCENE_DESC = {
    battlefield     = "域外战场，混沌之地，共分十层。越深入层数越高，妖兽越强，但掉落的炼丹炼器材料也越珍贵。第三层与第八层灵气汇聚，可供修士建立帮会基地。",
    main_city       = "繁华的江湖重镇，熙来攘往，商贾云集。交易阁高耸于城中央，每日交易的功法秘籍不计其数。这里是倒卖功法、积累财富的最佳之地。",
    sword_sect      = "华山之巅，云雾缭绕。剑宗弟子在此参悟剑道，苦练技艺。剑冢中沉睡着无数绝世剑法，只有真正有缘之人方能习得。",
    iron_sect       = "巍峨山岳之间，铁壁宗依山而建，城墙厚重如铁，令人望而生畏。宗内弟子以铁铸体，以盾为道，以坚不摧的防御著称于世。",
    medicine_sect   = "幽深山谷之中，百草丰茂，药香弥漫。药王谷弟子在此研习医术与毒功，以奇诡的医道武功闻名江湖，令人闻风丧胆又敬而远之。",
    shadow_sect     = "高楼隐于云端，天影楼以速度与隐匿立派。弟子身法如鬼魅，出手无声无息，或以暗器制敌于无形，或以影步令对手捉摸不透。",
    qidan_sect      = "丹火与锻炉并存，器丹宗以炼丹炼器双绝闻名天下。炼丹一脉掌控突破丹药，炼器一脉锻造神兵利器，修仙界各门各派无不争相结交。",
    ancient_village = "古老的村落掩映于荒野深处，青石铺路，大树参天。村人淳朴，却隐约透着不为人知的秘密。传说村中某处埋藏着一段尘封已久的往事...",
}

-- 场景出口（大地点间移动）
Settings.SCENE_EXITS = {
    battlefield     = { { to = "main_city", name = "返回扬州城" } },
    main_city       = {
        { to = "battlefield",   name = "前往域外战场" },
        { to = "sword_sect",    name = "前往剑宗" },
        { to = "iron_sect",     name = "前往铁壁宗" },
        { to = "medicine_sect", name = "前往药王谷" },
        { to = "shadow_sect",   name = "前往天影楼" },
        { to = "qidan_sect",    name = "前往器丹宗" },
        { to = "ancient_village", name = "前往古村" },
    },
    sword_sect      = { { to = "main_city", name = "返回扬州城" } },
    iron_sect       = { { to = "main_city", name = "返回扬州城" } },
    medicine_sect   = { { to = "main_city", name = "返回扬州城" } },
    shadow_sect     = { { to = "main_city", name = "返回扬州城" } },
    qidan_sect      = { { to = "main_city", name = "返回扬州城" } },
    ancient_village = { { to = "main_city", name = "返回扬州城" } },
}

-- 场景内小地点（当前大地点内可探索的具体位置）
-- pos = {row, col}：方位网格坐标，用于地图方位布局展示
-- spots: { id, name, desc, pos }
Settings.SCENE_SPOTS = {
    --[[ 域外战场方位示意：
         [第一层] [第二层] [第三层(帮会)]
         [第四层] [第五层] [第六层]
         [第七层] [第八层(帮会)] [第九层]
                  [第十层]
         [入口大厅]
    ]]
    battlefield = {
        { id = "layer_select", name = "入口大厅", desc = "域外战场入口，选择要探索的层数", pos = {5, 2} },
        { id = "layer_1",  name = "第一层", desc = "低阶妖兽横行，适合练气修士",       pos = {1, 1} },
        { id = "layer_2",  name = "第二层", desc = "妖兽略强，筑基期方可应对",         pos = {1, 2} },
        { id = "layer_3",  name = "第三层", desc = "灵气汇聚之地，可建帮会基地（无怪）", pos = {1, 3} },
        { id = "layer_4",  name = "第四层", desc = "凶兽出没，金丹期修士的试炼场",     pos = {2, 1} },
        { id = "layer_5",  name = "第五层", desc = "危机四伏，元婴修士方能立足",       pos = {2, 2} },
        { id = "layer_6",  name = "第六层", desc = "强横妖兽领地，化神境界的考验",     pos = {2, 3} },
        { id = "layer_7",  name = "第七层", desc = "混沌之地，大乘修士的角逐场",       pos = {3, 1} },
        { id = "layer_8",  name = "第八层", desc = "天地灵脉交汇，可建高级帮会基地（无怪）", pos = {3, 2} },
        { id = "layer_9",  name = "第九层", desc = "远古凶兽栖息地，接近渡劫之境",     pos = {3, 3} },
        { id = "layer_10", name = "第十层", desc = "域外最深处，天劫级凶兽盘踞",       pos = {4, 2} },
    },
    --[[ 主城方位示意：
         [茶楼] [客栈] [东市]
         [武馆] [西市]
                [城门]
    ]]
    main_city = {
        { id = "teahouse",    name = "茶　楼", desc = "消息灵通的情报中心",   pos = {1, 1} },
        { id = "inn",         name = "客　栈", desc = "休息恢复的好去处",     pos = {1, 2} },
        { id = "east_market", name = "东　市", desc = "物资丰富的集市",       pos = {1, 3} },
        { id = "arena",       name = "武　馆", desc = "切磋武艺的道场",       pos = {2, 1} },
        { id = "west_market", name = "西　市", desc = "功法交易的圣地",       pos = {2, 2} },
        { id = "city_gate",   name = "城　门", desc = "来往旅人的必经之路",   pos = {3, 2} },
    },
    --[[ 剑宗方位示意：
         [长老殿] [藏功阁] [后山]
         [重剑台] [演武场]
                  [剑冢]
                  [剑宗山门]
    ]]
    sword_sect = {
        { id = "elder_hall",      name = "长老殿",   desc = "宗门决策的庄严之地",             pos = {1, 1} },
        { id = "library",         name = "藏功阁",   desc = "珍藏无数武学秘籍",               pos = {1, 2} },
        { id = "back_mnt",        name = "后　山",   desc = "幽静绝境，适合悟道",             pos = {1, 3} },
        { id = "heavy_platform",  name = "重剑台",   desc = "以千斤重剑为媒，磨砺刚猛剑意",   pos = {2, 1} },
        { id = "training",        name = "演武场",   desc = "弟子修炼的核心场所",             pos = {2, 2} },
        { id = "sword_tomb",      name = "剑　冢",   desc = "埋葬绝世剑法的禁地",             pos = {3, 2} },
        { id = "sword_gate",      name = "剑宗山门", desc = "剑气冲霄的宗门入口，石阶千级",   pos = {4, 2} },
    },
    --[[ 铁壁宗方位示意：
         [铸甲堂] [铁壁悬崖] [铁壁祠]
         [盾卫演武场] [铁身炼体场]
                      [宗门大门]
    ]]
    iron_sect = {
        { id = "iron_gate",      name = "宗门大门", desc = "铁壁宗的巍峨大门，重甲守卫屹立两侧",         pos = {3, 2} },
        { id = "forge_hall",     name = "铸甲堂",   desc = "锻造铁甲与武器的核心场所，炉火日夜不熄",     pos = {1, 1} },
        { id = "iron_cliff",     name = "铁壁悬崖", desc = "宗门背后的天然屏障，壁面坚如铁石",           pos = {1, 2} },
        { id = "iron_shrine",    name = "铁壁祠",   desc = "供奉宗门历代掌门牌位的神圣之地",             pos = {1, 3} },
        { id = "shield_ground",  name = "盾卫演武场", desc = "盾卫分支弟子日常操练之地，铿锵之声不断",   pos = {2, 1} },
        { id = "body_ground",    name = "铁身炼体场", desc = "铁身弟子淬炼肉身的专属场地，常年烈火熏烤", pos = {2, 2} },
    },
    --[[ 药王谷方位示意：
         [百草园] [万毒池] [谷主峰]
         [治愈阁] [炼药房]
                  [谷　口]
    ]]
    medicine_sect = {
        { id = "valley_entrance", name = "谷　口",   desc = "药王谷的入口，草药香气扑鼻而来",           pos = {3, 2} },
        { id = "herb_garden",     name = "百草园",   desc = "栽培各类珍稀药草的宝地，四季常青",         pos = {1, 1} },
        { id = "poison_pool",     name = "万毒池",   desc = "汇聚天下奇毒的禁地，非毒功弟子不可近前",   pos = {1, 2} },
        { id = "valley_peak",     name = "谷主峰",   desc = "谷主闭关修炼之所，常人难以攀登",           pos = {1, 3} },
        { id = "heal_pavilion",   name = "治愈阁",   desc = "医治伤患、研究疗愈之术的清净之地",         pos = {2, 1} },
        { id = "alchemy_room",    name = "炼药房",   desc = "提炼丹药秘方的核心场所，药香经久不散",     pos = {2, 2} },
    },
    --[[ 天影楼方位示意：
         [暗器靶场] [楼　顶] [楼主密室]
         [影步道场] [情报室]
                    [影楼大厅]
    ]]
    shadow_sect = {
        { id = "shadow_hall",  name = "影楼大厅", desc = "天影楼的核心区域，弟子往来频繁",               pos = {3, 2} },
        { id = "dart_range",   name = "暗器靶场", desc = "专门练习各类暗器投掷的场地，靶木密布",         pos = {1, 1} },
        { id = "roof_top",     name = "楼　顶",   desc = "天影楼制高点，可俯瞰四方，弟子常在此悟道",     pos = {1, 2} },
        { id = "shadow_room",  name = "楼主密室", desc = "楼主处理机密要务之地，外人不得擅入",           pos = {1, 3} },
        { id = "shadow_dojo",  name = "影步道场", desc = "修炼身法步法的专属场所，地板不留痕迹",         pos = {2, 1} },
        { id = "intel_room",   name = "情报室",   desc = "汇聚江湖各路消息的枢纽，消息灵通无比",         pos = {2, 2} },
    },
    --[[ 器丹宗方位示意：
         [药田] [丹炉阁] [宗主峰]
         [锻造堂] [丹殿] [材料库]
                  [宗门牌坊]
    ]]
    qidan_sect = {
        { id = "herb_field",    name = "药　田",   desc = "种植各类灵药的宝地，四季常青",       pos = {1, 1} },
        { id = "furnace_hall",  name = "丹炉阁",   desc = "数十座丹炉日夜不熄，丹香四溢",     pos = {1, 2} },
        { id = "qidan_peak",    name = "宗主峰",   desc = "器丹宗宗主闭关之所，常有异象",     pos = {1, 3} },
        { id = "forge_hall",    name = "锻造堂",   desc = "百炉齐鸣，炼器弟子锻造神兵之地",   pos = {2, 1} },
        { id = "dan_hall",      name = "丹　殿",   desc = "弟子修习丹术与器术的核心场所",     pos = {2, 2} },
        { id = "material_hall", name = "材料库",   desc = "存放各类炼丹炼器珍稀材料的宝库",   pos = {2, 3} },
        { id = "sect_gate",     name = "宗门牌坊", desc = "器丹宗入口，丹烟与锻火交织",     pos = {3, 2} },
    },
    --[[ 古村方位示意：
         [祠堂] [田埂小道]
         [竹林] [村中心]   [古井]
                [青石小路]
    ]]
    ancient_village = {
        { id = "ancestral_hall", name = "祠　堂",   desc = "供奉先祖的神圣之地", pos = {1, 1} },
        { id = "field_path",     name = "田埂小道", desc = "蜿蜒于田野间的小路", pos = {1, 2} },
        { id = "bamboo_grove",   name = "竹　林",   desc = "幽静的翠竹深处",     pos = {2, 1} },
        { id = "village_center", name = "村中心",   desc = "古树参天的广场",     pos = {2, 2} },
        { id = "old_well",       name = "古　井",   desc = "据说井底藏有秘密",   pos = {2, 3} },
        { id = "stone_path",     name = "青石小路", desc = "光滑的青石板路",     pos = {3, 2} },
    },
}

-- ============================================================================
-- NPC定义
-- ============================================================================
-- spot 字段：对应 SCENE_SPOTS 中的 id，表示该 NPC 在哪个小地点出现
Settings.NPCS = {
    battlefield = {
        { id = "battlefield_guard", name = "战场守卫", spot = "layer_select",
          desc = "全身铠甲的守卫，负责维持域外战场的秩序" },
    },
    main_city = {
        { id = "market_keeper",  name = "交易阁掌柜",  spot = "west_market", desc = "负责管理交易阁的老者，满脸精明" },
        { id = "equipment_shop", name = "装备铺老板",  spot = "east_market", desc = "卖刀卖剑卖铠甲，样样俱全" },
        { id = "medicine_shop",  name = "药铺老板",    spot = "east_market", desc = "各类疗伤药品，价格公道" },
        { id = "talisman_shop",  name = "符箓铺掌柜",  spot = "east_market", desc = "经营各类攻防符箓，据说货源来自器丹宗" },
        { id = "inn_keeper",     name = "客栈掌柜",    spot = "inn",         desc = "热情好客，兼做各路消息的中间人" },
        { id = "tea_master",     name = "茶楼老板",    spot = "teahouse",    desc = "泡得一手好茶，闲聊间透露各路江湖消息" },
        { id = "arena_master",   name = "武馆馆主",    spot = "arena",       desc = "退隐江湖的老武者，开设武馆供人切磋比试" },
        { id = "city_guard",     name = "守城校尉",    spot = "city_gate",   desc = "身披银甲，守护扬州城安宁，指引旅人方向" },
    },
    sword_sect = {
        { id = "sect_master",       name = "剑宗掌门",    spot = "elder_hall",      desc = "白发飘飘，气宇轩昂，传说已达化神境界" },
        { id = "sword_trial_npc",   name = "剑宗执事",    spot = "sword_gate",      desc = "身穿白色剑袍，目光锐利，负责考核入门弟子" },
        { id = "wind_elder",        name = "风长老",      spot = "sword_tomb",      desc = "疾风剑派的传承者，身法如风，常在剑冢参悟剑意" },
        { id = "lone_elder",        name = "独孤长老",    spot = "heavy_platform",  desc = "重剑门的宗师，据说能以一剑开山裂石" },
        { id = "librarian",         name = "藏功阁守卫",  spot = "library",         desc = "面无表情，守护着无数武学秘籍" },
    },
    iron_sect = {
        { id = "iron_master",       name = "铁壁宗掌门",  spot = "iron_shrine",   desc = "身形魁梧如铁塔，全身披挂玄铁重甲，威压令人难以抬头" },
        { id = "iron_trial_npc",    name = "铁壁宗执事",  spot = "iron_gate",     desc = "身着厚重铁甲，面容刚毅，负责考核入门弟子" },
        { id = "shield_elder",      name = "盾卫长老",    spot = "shield_ground", desc = "盾卫分支的宗师，据说曾以一面盾牌独挡千军" },
        { id = "ironbody_elder",    name = "铁身长老",    spot = "body_ground",   desc = "铁身分支的传承者，皮肤黝黑如铁，刀剑难伤" },
        { id = "iron_keeper",       name = "铸甲堂守卫",  spot = "forge_hall",    desc = "负责守护铸甲堂的老兵，见过大风大浪，不苟言笑" },
    },
    medicine_sect = {
        { id = "medicine_master",      name = "药王谷谷主",  spot = "valley_peak",     desc = "须发皆白，目光如炬，精通天下一切毒药与解药" },
        { id = "medicine_trial_npc",   name = "药王谷执事",  spot = "valley_entrance", desc = "手持药箱，目光温和，负责考核入门弟子" },
        { id = "heal_elder",           name = "治愈长老",    spot = "heal_pavilion",   desc = "治愈分支的传承者，据说其双手能令垂死之人起死回生" },
        { id = "poison_elder",         name = "毒功长老",    spot = "poison_pool",     desc = "毒功分支的宗师，长年与万毒为伍，肤色略显青紫" },
        { id = "herb_keeper",          name = "百草园守卫",  spot = "herb_garden",     desc = "精通草药鉴别，守护百草园的老药农，脾气温和" },
    },
    shadow_sect = {
        { id = "shadow_master",      name = "天影楼楼主",  spot = "shadow_room",  desc = "难辨年龄，面覆黑纱，声音低沉，一举一动透出无尽杀机" },
        { id = "shadow_trial_npc",   name = "天影楼执事",  spot = "shadow_hall",  desc = "黑衣蒙面，行动无声，负责考核入门弟子" },
        { id = "dart_elder",         name = "暗器长老",    spot = "dart_range",   desc = "暗器分支的宗师，据说可在百步之外以飞针封穴" },
        { id = "shadow_elder",       name = "影步长老",    spot = "shadow_dojo",  desc = "影步分支的传承者，行走无声，常常忽然出现又倏然消失" },
        { id = "intel_keeper",       name = "情报室守卫",  spot = "intel_room",   desc = "掌握着无数江湖机密，沉默寡言，眼神锐利如鹰" },
    },
    qidan_sect = {
        { id = "qidan_master",     name = "器丹宗宗主",  spot = "qidan_peak",    desc = "白眉银发，左手布满药渍，右手覆锻纹，丹器双绝" },
        { id = "qidan_trial_npc",  name = "器丹宗执事",  spot = "dan_hall",      desc = "身着丹袍，手持玉简记录弟子考核，负责入门试炼" },
        { id = "pill_elder",       name = "炼丹长老",    spot = "furnace_hall",  desc = "炼丹分支的宗师，掌控火候的能力举世无双" },
        { id = "forge_elder",      name = "炼器长老",    spot = "forge_hall",    desc = "炼器分支的传承者，锻造出无数神兵利器" },
        { id = "material_keeper",  name = "材料库管事",  spot = "material_hall", desc = "精通各类炼丹炼器材料的鉴别与保管，一丝不苟" },
    },
    ancient_village = {
        { id = "village_elder",  name = "老村长",      spot = "village_center", desc = "头发花白的老人，见多识广，似乎知晓村中秘密" },
        { id = "herb_granny",    name = "采药老婆婆",  spot = "field_path",     desc = "整日在村外采药，总是神神秘秘" },
    },
}

-- ============================================================================
-- 野怪定义
-- scene 字段标识该怪所属场景；古村引导怪 tutorial_beast=true 仅用于新手引导
-- ============================================================================
Settings.MONSTERS = {
    -- ── 域外战场 第一层（练气期）──────────────────────────────
    -- 玩家参考：ATK≈7-10, DEF≈3-5, HP≈70-100
    -- 经验设计：exp_base=100，每层约打40怪升满
    {
        id = "bf_wolf",       name = "混沌野狼",      scene = "battlefield", layer = 1,
        level = 1,            hp = 30,    atk = 10,   def = 2,    agi = 8,
        exp = 12,             silver = 5,
        drop_rate = 0.15,     drop_materials = { "herb_green", "catalyst_powder" },
    },
    {
        id = "bf_imp",        name = "低阶小妖",      scene = "battlefield", layer = 1,
        level = 2,            hp = 45,    atk = 13,   def = 3,    agi = 6,
        exp = 18,             silver = 8,
        drop_rate = 0.15,     drop_materials = { "herb_green", "catalyst_powder" },
    },
    -- ── 域外战场 第二层（筑基期）──────────────────────────────
    -- 玩家参考：ATK≈19-32, DEF≈9-16, HP≈140-252
    -- 经验设计：exp_base=1000，每层约打40怪升满
    {
        id = "bf_bandit",     name = "混沌山贼",      scene = "battlefield", layer = 2,
        level = 4,            hp = 100,   atk = 28,   def = 8,    agi = 10,
        exp = 120,            silver = 15,
        drop_rate = 0.18,     drop_materials = { "herb_green", "herb_green", "catalyst_powder", "herb_fire" },
    },
    {
        id = "bf_bear",       name = "混沌黑熊",      scene = "battlefield", layer = 2,
        level = 5,            hp = 140,   atk = 35,   def = 12,   agi = 6,
        exp = 180,            silver = 22,
        drop_rate = 0.18,     drop_materials = { "herb_green", "herb_green", "catalyst_powder", "herb_fire" },
    },
    -- ── 域外战场 第四层（金丹期）──────────────────────────────
    -- 玩家参考：ATK≈52-83, DEF≈26-42, HP≈360-576（第三层跳过，3/4层用金丹区间）
    -- 经验设计：exp_base=10000，每层约打40怪升满
    {
        id = "bf_demon",      name = "赤焰魔",        scene = "battlefield", layer = 4,
        level = 8,            hp = 300,   atk = 80,   def = 22,   agi = 14,
        exp = 1500,           silver = 50,
        drop_rate = 0.20,     drop_materials = { "herb_fire", "herb_ice" },
    },
    {
        id = "bf_specter",    name = "幽影鬼",        scene = "battlefield", layer = 4,
        level = 9,            hp = 350,   atk = 95,   def = 18,   agi = 22,
        exp = 2200,           silver = 55,
        drop_rate = 0.20,     drop_materials = { "herb_fire", "catalyst_crystal" },
    },
    -- ── 域外战场 第五层（元婴期）──────────────────────────────
    -- 玩家参考：ATK≈119-190, DEF≈60-95, HP≈770-1232
    -- 经验设计：exp_base=100000，每层约打40怪升满
    {
        id = "bf_serpent",    name = "玄蟒",          scene = "battlefield", layer = 5,
        level = 12,           hp = 700,   atk = 170,  def = 50,   agi = 20,
        exp = 12000,          silver = 100,
        drop_rate = 0.22,     drop_materials = { "herb_earth", "herb_golden" },
    },
    {
        id = "bf_golem",      name = "岩魔",          scene = "battlefield", layer = 5,
        level = 13,           hp = 900,   atk = 155,  def = 75,   agi = 10,
        exp = 18000,          silver = 110,
        drop_rate = 0.22,     drop_materials = { "herb_earth", "catalyst_crystal" },
    },
    -- ── 域外战场 第六层（化神期）──────────────────────────────
    -- 玩家参考：ATK≈252-420, DEF≈126-210, HP≈1560-2600
    -- 经验设计：exp_base=1000000，每层约打40怪升满
    {
        id = "bf_phoenix",    name = "堕火凤",        scene = "battlefield", layer = 6,
        level = 16,           hp = 1600,  atk = 380,  def = 100,  agi = 28,
        exp = 120000,         silver = 200,
        drop_rate = 0.25,     drop_materials = { "herb_dragon", "catalyst_divine" },
    },
    {
        id = "bf_frost",      name = "冰霜巨兽",      scene = "battlefield", layer = 6,
        level = 17,           hp = 1900,  atk = 350,  def = 140,  agi = 18,
        exp = 180000,         silver = 220,
        drop_rate = 0.25,     drop_materials = { "herb_dragon", "herb_celestial" },
    },
    -- ── 域外战场 第七层（大乘期）──────────────────────────────
    -- 玩家参考：ATK≈550-900, DEF≈275-450, HP≈3300-5400
    -- 经验设计：exp_base=10000000，每层约打40怪升满
    {
        id = "bf_dragon",     name = "蛟龙幼崽",      scene = "battlefield", layer = 7,
        level = 20,           hp = 3800,  atk = 800,  def = 200,  agi = 30,
        exp = 1200000,        silver = 400,
        drop_rate = 0.28,     drop_materials = { "herb_celestial", "catalyst_divine" },
    },
    {
        id = "bf_titan",      name = "远古巨人",      scene = "battlefield", layer = 7,
        level = 21,           hp = 4500,  atk = 720,  def = 280,  agi = 20,
        exp = 1800000,        silver = 450,
        drop_rate = 0.28,     drop_materials = { "herb_celestial", "herb_divine" },
    },
    -- ── 域外战场 第九层（渡劫前期）─────────────────────────────
    -- 玩家参考：ATK≈1100-1500, DEF≈550-750, HP≈7200-9000
    -- 经验设计：exp_base=100000000，每层约打40怪升满
    {
        id = "bf_archfiend",  name = "太古魔神",      scene = "battlefield", layer = 9,
        level = 24,           hp = 6500,  atk = 1400, def = 400,  agi = 35,
        exp = 12000000,       silver = 800,
        drop_rate = 0.30,     drop_materials = { "herb_divine", "catalyst_divine" },
    },
    {
        id = "bf_voidbeast",  name = "虚空凶兽",      scene = "battlefield", layer = 9,
        level = 25,           hp = 7500,  atk = 1600, def = 450,  agi = 40,
        exp = 18000000,       silver = 900,
        drop_rate = 0.30,     drop_materials = { "herb_divine", "herb_celestial" },
    },
    -- ── 域外战场 第十层（渡劫级boss）───────────────────────────
    -- 玩家参考：ATK≈1500-1740, DEF≈750-870, HP≈9000-10200
    {
        id = "bf_calamity",   name = "天劫兽",        scene = "battlefield", layer = 10,
        level = 28,           hp = 18000, atk = 2200, def = 600,  agi = 45,
        exp = 50000000,       silver = 2000,
        drop_rate = 0.35,     drop_materials = { "herb_divine", "catalyst_divine" },
    },
    -- ── 古村引导怪（新手任务专用，战斗胜利后推进引导进度）────────
    -- 玩家参考：练气1重裸装 ATK=7, HP=70
    {
        id = "tutorial_beast",  name = "迷失幼妖",  scene = "ancient_village",
        tutorial_beast = true,                      -- 标记：引导专用怪
        level = 1,              hp = 20,    atk = 3,    def = 1,    agi = 5,
        exp = 5,                silver = 2,
        drop_rate = 1.0,        -- 教程必定掉落一件装备，引导玩家体验拾取→背包→装备流程
    },
}

-- ============================================================================
-- 功法定义（剑宗）
-- ============================================================================
-- 战斗技能类型常量
Settings.BATTLE_TYPE = {
    NORMAL  = "normal",   -- 普攻（无消耗，无冷却）
    DAMAGE  = "damage",   -- 伤害型（消耗内力，强化攻击）
    BUFF    = "buff",     -- 增强型（消耗内力，提升属性）
    DODGE   = "dodge",    -- 闪避型（消耗内力，可规避伤害）
    DEFEND  = "defend",   -- 防御型（减免伤害，盾卫系）
    HEAL    = "heal",     -- 治愈型（恢复气血，药宗系）
}

-- 出战技能槽数量（不含固定普攻）
Settings.BATTLE_SKILL_SLOTS = 7

Settings.SKILLS = {
    -- 村长传授的基础功法（教程奖励）
    {
        id = "basic_fist",      name = "《基本拳脚》",
        grade = 1,              branch = "common",
        bound = true,
        stat_bonus = { atk = 0.3, def = 0.2 },
        max_proficiency = 100,
        desc = "村中代代相传的基本拳脚功夫，虽不入流，却能强身健体。",
        battle_type     = "normal",
        mp_cost         = 0,
        cooldown        = 0,
        damage_coeff    = 0.8,
        priority        = 0,
    },
    -- 初级（普攻，不可更换，无消耗）
    {
        id = "basic_sword",     name = "《基础剑法》",
        grade = 1,              branch = "common",
        bound = true,
        stat_bonus = { atk = 0.5, agi = 0.3 },
        max_proficiency = 100,
        desc = "剑宗入门剑法，简单易学，威力平平。",
        -- 战斗属性
        battle_type     = "normal",
        mp_cost         = 0,
        cooldown        = 0,
        damage_coeff    = 1.0,
        priority        = 0,    -- 自动战斗优先级（越高越优先使用）
    },
    -- ============================================================================
    -- 疾风剑派（高agi，连击多段，以速度取胜）
    -- ============================================================================
    {
        id = "swift_sword",     name = "《疾风斩》",
        grade = 2,              branch = "swift",
        bound = true,
        stat_bonus = { atk = 0.8, agi = 1.0 },
        max_proficiency = 200,
        require_skill = "basic_sword",
        desc = "以速度制胜，出剑如疾风，攻速大幅提升。",
        battle_type     = "damage",
        mp_cost         = 15,
        cooldown        = 1,
        damage_coeff    = 1.4,
        priority        = 1,
        multi_hit       = true,  -- 连击型：基于agi优势可多次攻击
    },
    {
        id = "gale_sword",      name = "《连环剑》",
        grade = 3,              branch = "swift",
        bound = true,
        stat_bonus = { atk = 1.5, agi = 2.0 },
        max_proficiency = 300,
        require_skill = "swift_sword",
        desc = "连续攻击，每次命中叠加伤害加成，势如狂风。",
        battle_type     = "damage",
        mp_cost         = 25,
        cooldown        = 2,
        damage_coeff    = 1.8,
        priority        = 2,
        multi_hit       = true,
    },
    {
        id = "shadowless_sword", name = "《无影连击》",
        grade = 4,              branch = "swift",
        bound = true,
        stat_bonus = { atk = 3.0, agi = 4.0 },
        max_proficiency = 400,
        require_skill = "gale_sword",
        desc = "剑招快至肉眼难辨，出剑即中，无从躲避。",
        battle_type     = "dodge",
        mp_cost         = 35,
        cooldown        = 3,
        damage_coeff    = 1.6,
        priority        = 3,
        multi_hit       = true,
    },
    {
        id = "ten_thousand_swords", name = "《万剑归宗》",
        grade = 5,              branch = "swift",
        bound = true,
        stat_bonus = { atk = 8.0, agi = 5.0 },
        max_proficiency = 500,
        require_skill = "shadowless_sword",
        desc = "疾风剑派之巅，万剑汇聚于一，天下无双。",
        battle_type     = "damage",
        mp_cost         = 60,
        cooldown        = 4,
        damage_coeff    = 2.8,
        priority        = 5,
        multi_hit       = true,
    },
    -- ============================================================================
    -- 重剑门（高atk，穿甲，眩晕，单次高爆发）
    -- ============================================================================
    {
        id = "heavy_sword",     name = "《重力斩》",
        grade = 2,              branch = "heavy",
        bound = true,
        stat_bonus = { atk = 1.5, def = 0.5 },
        max_proficiency = 200,
        require_skill = "basic_sword",
        desc = "以力破巧，一剑重如泰山，击碎对手防御。",
        battle_type     = "damage",
        mp_cost         = 20,
        cooldown        = 2,
        damage_coeff    = 1.7,
        priority        = 2,
        ignore_def      = 0.1,
    },
    {
        id = "iron_sword",      name = "《碎甲一击》",
        grade = 3,              branch = "heavy",
        bound = true,
        stat_bonus = { atk = 3.0, def = 1.0 },
        max_proficiency = 300,
        require_skill = "heavy_sword",
        desc = "以玄铁重剑修炼，每击无视三成防御。",
        battle_type     = "damage",
        mp_cost         = 30,
        cooldown        = 2,
        damage_coeff    = 2.0,
        priority        = 3,
        ignore_def      = 0.3,
    },
    {
        id = "earth_breaker",   name = "《山河破碎》",
        grade = 4,              branch = "heavy",
        bound = true,
        stat_bonus = { atk = 6.0, def = 2.0 },
        max_proficiency = 400,
        require_skill = "iron_sword",
        desc = "一剑落下，天地为之色变，重若千钧，有概率震慑敌人。",
        battle_type     = "damage",
        mp_cost         = 40,
        cooldown        = 3,
        damage_coeff    = 2.4,
        priority        = 4,
        ignore_def      = 0.4,
        stun_chance     = 0.35,
        stun_rounds     = 1,
    },
    {
        id = "sword_breaks_all", name = "《一剑破万法》",
        grade = 5,              branch = "heavy",
        bound = true,
        stat_bonus = { atk = 10.0, def = 4.0 },
        max_proficiency = 500,
        require_skill = "earth_breaker",
        desc = "重剑门之巅，一剑可破天下一切法门，必有震慑之效。",
        battle_type     = "damage",
        mp_cost         = 70,
        cooldown        = 5,
        damage_coeff    = 3.0,
        priority        = 6,
        ignore_def      = 0.5,
        stun_chance     = 0.40,
        stun_rounds     = 1,
    },

    -- ============================================================================
    -- 铁壁宗功法
    -- ============================================================================
    -- 入门心法（通用）
    {
        id = "iron_basic",      name = "《铁壁心法》",
        grade = 1,              branch = "common",
        bound = true,
        stat_bonus = { def = 0.5, hp = 0.3 },
        max_proficiency = 100,
        desc = "铁壁宗入门心法，修炼后皮肤渐硬如铁，防御大幅提升。",
        battle_type     = "normal",
        mp_cost         = 0,
        cooldown        = 0,
        damage_coeff    = 1.0,
        priority        = 0,
    },
    -- 盾卫分支（defend型：放弃攻击，获得减伤buff）
    {
        id = "shield_bash",     name = "《盾击》",
        grade = 2,              branch = "shield",
        bound = true,
        stat_bonus = { def = 1.2, hp = 0.8 },
        max_proficiency = 200,
        require_skill = "iron_basic",
        desc = "以铁盾猛击敌人，力道沉稳，使对手短暂失去重心。",
        battle_type     = "damage",
        mp_cost         = 15,
        cooldown        = 1,
        damage_coeff    = 1.3,
        priority        = 1,
    },
    {
        id = "shield_wall",     name = "《铁壁》",
        grade = 3,              branch = "shield",
        bound = true,
        stat_bonus = { def = 2.5, hp = 1.5 },
        max_proficiency = 300,
        require_skill = "shield_bash",
        desc = "以盾为墙，放弃攻击转而防守，减免大量伤害。",
        battle_type     = "defend",
        mp_cost         = 25,
        cooldown        = 2,
        damage_coeff    = 0,
        priority        = 2,
    },
    {
        id = "bastion_smash",   name = "《堡垒冲击》",
        grade = 4,              branch = "shield",
        bound = true,
        stat_bonus = { def = 5.0, hp = 3.0 },
        max_proficiency = 400,
        require_skill = "shield_wall",
        desc = "整个身体化作移动的堡垒，以坚不可摧之姿抵挡一切攻击。",
        battle_type     = "defend",
        mp_cost         = 35,
        cooldown        = 3,
        damage_coeff    = 0,
        priority        = 3,
    },
    {
        id = "iron_bulwark",    name = "《万夫莫开》",
        grade = 5,              branch = "shield",
        bound = true,
        stat_bonus = { def = 10.0, hp = 6.0 },
        max_proficiency = 500,
        require_skill = "bastion_smash",
        desc = "盾卫之巅，一人守关，万夫莫开，任何攻击都无法动摇分毫。",
        battle_type     = "defend",
        mp_cost         = 65,
        cooldown        = 5,
        damage_coeff    = 0,
        priority        = 5,
    },
    -- 铁身分支（纯肉输出：高def/hp + 穿甲反击）
    {
        id = "iron_skin",       name = "《铁皮功》",
        grade = 2,              branch = "ironbody",
        bound = true,
        stat_bonus = { def = 1.5, hp = 1.0 },
        max_proficiency = 200,
        require_skill = "iron_basic",
        desc = "淬炼皮肉，使肌肤如铁甲般坚硬，普通刀剑难以伤及。",
        battle_type     = "damage",
        mp_cost         = 18,
        cooldown        = 1,
        damage_coeff    = 1.2,
        priority        = 1,
    },
    {
        id = "stone_flesh",     name = "《石肉神功》",
        grade = 3,              branch = "ironbody",
        bound = true,
        stat_bonus = { def = 3.0, hp = 2.0 },
        max_proficiency = 300,
        require_skill = "iron_skin",
        desc = "肉身锻炼至石块般坚韧，以体为盾，以肉为甲。",
        battle_type     = "damage",
        mp_cost         = 28,
        cooldown        = 2,
        damage_coeff    = 1.6,
        priority        = 2,
    },
    {
        id = "diamond_body",    name = "《金刚体》",
        grade = 4,              branch = "ironbody",
        bound = true,
        stat_bonus = { def = 6.0, hp = 4.0 },
        max_proficiency = 400,
        require_skill = "stone_flesh",
        desc = "肉身修炼达金刚境，刀枪不入，以不动之姿摧毁对手。",
        battle_type     = "damage",
        mp_cost         = 40,
        cooldown        = 3,
        damage_coeff    = 2.2,
        priority        = 4,
        ignore_def      = 0.3,
    },
    {
        id = "undying_iron",    name = "《不死铁神》",
        grade = 5,              branch = "ironbody",
        bound = true,
        stat_bonus = { def = 14.0, hp = 8.0 },
        max_proficiency = 500,
        require_skill = "diamond_body",
        desc = "铁身之巅，肉身不死不灭，以钢铁之躯碾压天下一切对手。",
        battle_type     = "damage",
        mp_cost         = 70,
        cooldown        = 5,
        damage_coeff    = 3.0,
        priority        = 6,
        ignore_def      = 0.5,
        stun_chance     = 0.40,
        stun_rounds     = 1,
    },

    -- ============================================================================
    -- 药王谷功法
    -- ============================================================================
    -- 入门医典（通用）
    {
        id = "herb_basic",      name = "《基础医典》",
        grade = 1,              branch = "common",
        bound = true,
        stat_bonus = { wis = 0.5, hp = 0.3 },
        max_proficiency = 100,
        desc = "药王谷入门医典，修炼后心神安定，内力运转更加流畅。",
        battle_type     = "normal",
        mp_cost         = 0,
        cooldown        = 0,
        damage_coeff    = 1.0,
        priority        = 0,
    },
    -- 治愈分支（heal型：回血+微伤害，PvE自动转伤害0.5x）
    {
        id = "spring_wind_palm", name = "《春风掌》",
        grade = 2,              branch = "heal",
        bound = true,
        stat_bonus = { wis = 1.0, hp = 0.8 },
        max_proficiency = 200,
        require_skill = "herb_basic",
        desc = "掌力如春风拂面，疏通经脉恢复气血，亦能以柔劲伤人。",
        battle_type     = "heal",
        mp_cost         = 20,
        cooldown        = 1,
        damage_coeff    = 0.8,
        heal_power      = 0.08,  -- 回复自身最大HP的8%
        priority        = 1,
    },
    {
        id = "marrow_cleanse",  name = "《洗髓伐毛》",
        grade = 3,              branch = "heal",
        bound = true,
        stat_bonus = { wis = 2.0, hp = 1.5 },
        max_proficiency = 300,
        require_skill = "spring_wind_palm",
        desc = "以医术调理自身经脉，大幅恢复气血，同时以内劲震伤对手。",
        battle_type     = "heal",
        mp_cost         = 30,
        cooldown        = 2,
        damage_coeff    = 0.8,
        heal_power      = 0.12,  -- 回复自身最大HP的12%
        priority        = 2,
    },
    {
        id = "golden_needle_strike", name = "《金针点穴》",
        grade = 4,              branch = "heal",
        bound = true,
        stat_bonus = { wis = 4.0, hp = 3.0 },
        max_proficiency = 400,
        require_skill = "marrow_cleanse",
        desc = "以金针封锁自身伤穴止血，同时精准刺入对手穴道令其麻痹。",
        battle_type     = "heal",
        mp_cost         = 40,
        cooldown        = 3,
        damage_coeff    = 0.8,
        heal_power      = 0.15,  -- 回复自身最大HP的15%
        priority        = 3,
        stun_chance     = 0.30,
        stun_rounds     = 1,
    },
    {
        id = "life_death_reversal", name = "《生死逆转》",
        grade = 5,              branch = "heal",
        bound = true,
        stat_bonus = { wis = 8.0, hp = 6.0 },
        max_proficiency = 500,
        require_skill = "golden_needle_strike",
        desc = "治愈之巅，以生死之力逆转乾坤，大幅恢复自身同时令对手元气大伤。",
        battle_type     = "heal",
        mp_cost         = 65,
        cooldown        = 5,
        damage_coeff    = 0.8,
        heal_power      = 0.20,  -- 回复自身最大HP的20%
        priority        = 5,
        stun_chance     = 0.35,
        stun_rounds     = 1,
    },
    -- 毒功分支（poison DoT：3回合后重前轻，可叠3层，减疗50%）
    {
        id = "venom_needle",    name = "《毒针》",
        grade = 2,              branch = "poison",
        bound = true,
        stat_bonus = { wis = 0.8, agi = 1.0 },
        max_proficiency = 200,
        require_skill = "herb_basic",
        desc = "以淬毒银针攻敌，毒性渗透入体，令对手持续削弱。",
        battle_type     = "damage",
        mp_cost         = 15,
        cooldown        = 1,
        damage_coeff    = 1.2,
        priority        = 1,
        dot_type        = "poison",   -- 毒伤DoT
        dot_power       = 0.15,       -- 每层基础伤害=atk*15%（按30%→70%→100%分布）
    },
    {
        id = "viper_fang",      name = "《蛇牙功》",
        grade = 3,              branch = "poison",
        bound = true,
        stat_bonus = { wis = 1.5, agi = 2.0 },
        max_proficiency = 300,
        require_skill = "venom_needle",
        desc = "模仿毒蛇攻击之姿，出手迅猛，毒性较《毒针》更为剧烈。",
        battle_type     = "damage",
        mp_cost         = 25,
        cooldown        = 2,
        damage_coeff    = 1.6,
        priority        = 2,
        dot_type        = "poison",
        dot_power       = 0.20,
    },
    {
        id = "ten_thousand_toxins", name = "《万毒归宗》",
        grade = 4,              branch = "poison",
        bound = true,
        stat_bonus = { wis = 3.0, agi = 4.0 },
        max_proficiency = 400,
        require_skill = "viper_fang",
        desc = "集万种毒素于一击，穿透对手防御，令其奇毒攻心，无解可解。",
        battle_type     = "damage",
        mp_cost         = 38,
        cooldown        = 3,
        damage_coeff    = 2.0,
        priority        = 4,
        ignore_def      = 0.3,
        dot_type        = "poison",
        dot_power       = 0.25,
    },
    {
        id = "soul_devouring_gu", name = "《噬魂蛊》",
        grade = 5,              branch = "poison",
        bound = true,
        stat_bonus = { wis = 7.0, agi = 8.0 },
        max_proficiency = 500,
        require_skill = "ten_thousand_toxins",
        desc = "毒功之巅，蛊毒入魂，侵蚀神魂，令对手持续中毒且治疗失效。",
        battle_type     = "damage",
        mp_cost         = 70,
        cooldown        = 5,
        damage_coeff    = 2.6,
        priority        = 6,
        ignore_def      = 0.5,
        stun_chance     = 0.40,
        stun_rounds     = 1,
        dot_type        = "poison",
        dot_power       = 0.30,
    },

    -- ============================================================================
    -- 天影楼功法
    -- ============================================================================
    -- 入门身法（通用）
    {
        id = "shadow_basic",    name = "《基础身法》",
        grade = 1,              branch = "common",
        bound = true,
        stat_bonus = { agi = 0.5, atk = 0.3 },
        max_proficiency = 100,
        desc = "天影楼入门身法，修炼后步伐轻盈，行动更加灵活飘逸。",
        battle_type     = "normal",
        mp_cost         = 0,
        cooldown        = 0,
        damage_coeff    = 1.0,
        priority        = 0,
    },
    -- 暗器分支（纯爆发：高agi+atk，穿甲伤害）
    {
        id = "hidden_dart",     name = "《藏锋镖》",
        grade = 2,              branch = "dart",
        bound = true,
        stat_bonus = { agi = 1.0, atk = 0.8 },
        max_proficiency = 200,
        require_skill = "shadow_basic",
        desc = "以藏匿于指间的暗镖突袭对手，令其措手不及，难以防范。",
        battle_type     = "damage",
        mp_cost         = 15,
        cooldown        = 1,
        damage_coeff    = 1.4,
        priority        = 1,
    },
    {
        id = "needle_rain",     name = "《飞针如雨》",
        grade = 3,              branch = "dart",
        bound = true,
        stat_bonus = { agi = 2.0, atk = 1.5 },
        max_proficiency = 300,
        require_skill = "hidden_dart",
        desc = "以千支飞针如雨点般倾泻而出，密不透风，令对手无处可躲。",
        battle_type     = "damage",
        mp_cost         = 25,
        cooldown        = 2,
        damage_coeff    = 1.9,
        priority        = 2,
    },
    {
        id = "ten_dir_darts",   name = "《十方暗器》",
        grade = 4,              branch = "dart",
        bound = true,
        stat_bonus = { agi = 4.0, atk = 3.0 },
        max_proficiency = 400,
        require_skill = "needle_rain",
        desc = "暗器从十个方向同时袭来，洞穿对手防御，令其陷入混乱。",
        battle_type     = "damage",
        mp_cost         = 38,
        cooldown        = 3,
        damage_coeff    = 2.3,
        priority        = 3,
        ignore_def      = 0.4,
        stun_chance     = 0.30,
        stun_rounds     = 1,
    },
    {
        id = "shadowless_strike", name = "《无影杀手》",
        grade = 5,              branch = "dart",
        bound = true,
        stat_bonus = { agi = 8.0, atk = 6.0 },
        max_proficiency = 500,
        require_skill = "ten_dir_darts",
        desc = "暗器之巅，出手无影无形，穿透一切防御，令对手在毫无察觉中陨落。",
        battle_type     = "damage",
        mp_cost         = 65,
        cooldown        = 5,
        damage_coeff    = 3.0,
        priority        = 5,
        ignore_def      = 0.6,
    },
    -- 影步分支（dodge型：闪避+反击）
    {
        id = "ghost_walk",      name = "《鬼步》",
        grade = 2,              branch = "shadow",
        bound = true,
        stat_bonus = { agi = 1.2, atk = 0.6 },
        max_proficiency = 200,
        require_skill = "shadow_basic",
        desc = "步伐诡异如鬼魅，令对手难以捕捉身形，同时借势反击。",
        battle_type     = "dodge",
        mp_cost         = 18,
        cooldown        = 1,
        damage_coeff    = 1.3,
        priority        = 1,
    },
    {
        id = "phantom_step",    name = "《幻影步》",
        grade = 3,              branch = "shadow",
        bound = true,
        stat_bonus = { agi = 2.5, atk = 1.2 },
        max_proficiency = 300,
        require_skill = "ghost_walk",
        desc = "施展时留下残影迷惑对手，以假乱真，出奇不意地给予重击。",
        battle_type     = "dodge",
        mp_cost         = 28,
        cooldown        = 2,
        damage_coeff    = 1.7,
        priority        = 2,
    },
    {
        id = "night_flash",     name = "《子夜闪》",
        grade = 4,              branch = "shadow",
        bound = true,
        stat_bonus = { agi = 5.0, atk = 2.5 },
        max_proficiency = 400,
        require_skill = "phantom_step",
        desc = "瞬间消失于黑暗之中，从对手意想不到的角度发动致命一击。",
        battle_type     = "dodge",
        mp_cost         = 38,
        cooldown        = 3,
        damage_coeff    = 2.1,
        priority        = 4,
        ignore_def      = 0.3,
    },
    {
        id = "heaven_shadow_art", name = "《天影神功》",
        grade = 5,              branch = "shadow",
        bound = true,
        stat_bonus = { agi = 10.0, atk = 5.0 },
        max_proficiency = 500,
        require_skill = "night_flash",
        desc = "影步之巅，如天际阴影覆盖四方，无处不在，无处可逃，令对手魂飞魄散。",
        battle_type     = "dodge",
        mp_cost         = 68,
        cooldown        = 5,
        damage_coeff    = 3.0,
        priority        = 6,
        ignore_def      = 0.5,
        stun_chance     = 0.35,
        stun_rounds     = 1,
    },

    -- ============================================================================
    -- 丹宗功法
    -- ============================================================================
    -- 入门丹术（通用）
    {
        id = "alchemy_basic",   name = "《丹术入门》",
        grade = 1,              branch = "common",
        bound = true,
        stat_bonus = { wis = 0.5, atk = 0.2 },
        max_proficiency = 100,
        desc = "丹宗入门功法，修炼后对火候与药性的感悟大幅提升。",
        battle_type     = "normal",
        mp_cost         = 0,
        cooldown        = 0,
        damage_coeff    = 1.0,
        priority        = 0,
    },
    -- 炉火分支（burn DoT：2回合前重后轻，不可叠加，刷新持续时间）
    {
        id = "fire_palm",       name = "《丹火掌》",
        grade = 2,              branch = "flame",
        bound = true,
        stat_bonus = { atk = 1.0, wis = 0.8 },
        max_proficiency = 200,
        require_skill = "alchemy_basic",
        desc = "以炼丹炉火凝聚掌心，灼烧对手经脉，令其内息紊乱。",
        battle_type     = "damage",
        mp_cost         = 15,
        cooldown        = 1,
        damage_coeff    = 1.3,
        priority        = 1,
        dot_type        = "burn",    -- 灼烧DoT
        dot_power       = 0.20,      -- 基础灼伤=atk*20%（按100%→50%分布）
    },
    {
        id = "furnace_burst",   name = "《炉火焚天》",
        grade = 3,              branch = "flame",
        bound = true,
        stat_bonus = { atk = 2.0, wis = 1.5 },
        max_proficiency = 300,
        require_skill = "fire_palm",
        desc = "将丹炉之火化为攻伐之术，烈焰焚尽一切。",
        battle_type     = "damage",
        mp_cost         = 25,
        cooldown        = 2,
        damage_coeff    = 1.7,
        priority        = 2,
        dot_type        = "burn",
        dot_power       = 0.25,
    },
    {
        id = "nine_fires",      name = "《九转真火》",
        grade = 4,              branch = "flame",
        bound = true,
        stat_bonus = { atk = 4.0, wis = 3.0 },
        max_proficiency = 400,
        require_skill = "furnace_burst",
        desc = "九种丹火合一，温度可熔金石，令对手防御土崩瓦解。",
        battle_type     = "damage",
        mp_cost         = 38,
        cooldown        = 3,
        damage_coeff    = 2.1,
        priority        = 3,
        ignore_def      = 0.3,
        dot_type        = "burn",
        dot_power       = 0.30,
    },
    {
        id = "heavenly_flame",  name = "《天火焚仙》",
        grade = 5,              branch = "flame",
        bound = true,
        stat_bonus = { atk = 8.0, wis = 6.0 },
        max_proficiency = 500,
        require_skill = "nine_fires",
        desc = "炉火之巅，召唤天火焚尽万物，连仙人也难以抵挡的毁灭之力。",
        battle_type     = "damage",
        mp_cost         = 65,
        cooldown        = 5,
        damage_coeff    = 2.8,
        priority        = 5,
        ignore_def      = 0.5,
        stun_chance     = 0.35,
        stun_rounds     = 1,
        dot_type        = "burn",
        dot_power       = 0.40,
    },
    -- 药理分支（辅助向：丹毒弱敌，poison DoT）
    {
        id = "poison_mist",     name = "《毒烟术》",
        grade = 2,              branch = "herblore",
        bound = true,
        stat_bonus = { wis = 1.2, agi = 0.6 },
        max_proficiency = 200,
        require_skill = "alchemy_basic",
        desc = "以炼丹废气凝成毒烟，令对手中毒虚弱。",
        battle_type     = "damage",
        mp_cost         = 15,
        cooldown        = 1,
        damage_coeff    = 1.2,
        priority        = 1,
        dot_type        = "poison",
        dot_power       = 0.15,
    },
    {
        id = "corrosion_pill",  name = "《蚀骨散》",
        grade = 3,              branch = "herblore",
        bound = true,
        stat_bonus = { wis = 2.5, agi = 1.2 },
        max_proficiency = 300,
        require_skill = "poison_mist",
        desc = "以特制丹粉撒向敌人，侵蚀其筋骨，削弱其战力。",
        battle_type     = "damage",
        mp_cost         = 25,
        cooldown        = 2,
        damage_coeff    = 1.5,
        priority        = 2,
        ignore_def      = 0.2,
        dot_type        = "poison",
        dot_power       = 0.20,
    },
    {
        id = "soul_erode_pill", name = "《噬魂丹雾》",
        grade = 4,              branch = "herblore",
        bound = true,
        stat_bonus = { wis = 5.0, agi = 2.5 },
        max_proficiency = 400,
        require_skill = "corrosion_pill",
        desc = "将数种奇毒炼成丹雾，侵蚀神魂，令对手神志昏沉。",
        battle_type     = "damage",
        mp_cost         = 38,
        cooldown        = 3,
        damage_coeff    = 1.9,
        priority        = 4,
        ignore_def      = 0.3,
        stun_chance     = 0.30,
        stun_rounds     = 1,
        dot_type        = "poison",
        dot_power       = 0.25,
    },
    {
        id = "myriad_pill_art", name = "《万丹归元》",
        grade = 5,              branch = "herblore",
        bound = true,
        stat_bonus = { wis = 10.0, agi = 5.0 },
        max_proficiency = 500,
        require_skill = "soul_erode_pill",
        desc = "药理之巅，以万丹之力归元化一，可令对手百毒攻心，无力招架。",
        battle_type     = "damage",
        mp_cost         = 68,
        cooldown        = 5,
        damage_coeff    = 2.6,
        priority        = 6,
        ignore_def      = 0.5,
        stun_chance     = 0.40,
        stun_rounds     = 1,
        dot_type        = "poison",
        dot_power       = 0.30,
    },
}

-- 功法等级到名称映射
Settings.SKILL_GRADE_NAME = { "初级", "中级", "高级", "绝世", "神级" }

-- ============================================================================
-- 装备定义（基础模板）
-- ============================================================================
Settings.EQUIPMENT_QUALITY = {
    { id = 1, name = "普通", color = { 200, 200, 200 } },
    { id = 2, name = "优秀", color = { 80, 200, 80 } },
    { id = 3, name = "精良", color = { 80, 150, 220 } },
    { id = 4, name = "史诗", color = { 160, 80, 220 } },
    { id = 5, name = "传说", color = { 220, 140, 40 } },
    { id = 6, name = "神器", color = { 220, 60, 60 } },
}

Settings.EQUIPMENT_QUALITY_MULTIPLIER = { 1.0, 1.3, 1.6, 2.0, 2.5, 3.0 }

Settings.EQUIPMENT_SLOTS = {
    "weapon", "helmet", "armor", "boots", "ring", "necklace"
}

Settings.EQUIPMENT_SLOT_NAME = {
    weapon = "武器（剑）", helmet = "头盔",
    armor = "铠甲",        boots = "靴子",
    ring = "戒指",         necklace = "项链",
}

-- 基础装备模板（普通品质数值）
Settings.EQUIPMENT_TEMPLATES = {
    -- ===== 练气期（tier 1）=====
    { id = "iron_sword",       slot = "weapon",   name = "铁剑",     base = { atk = 8 },             tier = 1 },
    { id = "steel_sword",      slot = "weapon",   name = "钢剑",     base = { atk = 15 },            tier = 1 },
    { id = "iron_helmet",      slot = "helmet",   name = "铁盔",     base = { def = 3, hp = 10 },    tier = 1 },
    { id = "iron_armor",       slot = "armor",    name = "铁甲",     base = { def = 6, hp = 20 },    tier = 1 },
    { id = "iron_boots",       slot = "boots",    name = "铁靴",     base = { def = 2, agi = 2 },    tier = 1 },
    { id = "copper_ring",      slot = "ring",     name = "铜指环",   base = { atk = 2, def = 1 },    tier = 1 },
    { id = "jade_necklace",    slot = "necklace", name = "玉坠",     base = { hp = 15, def = 2 },    tier = 1 },

    -- ===== 筑基期（tier 2）=====
    { id = "spirit_sword",     slot = "weapon",   name = "灵纹剑",   base = { atk = 30 },            tier = 2 },
    { id = "spirit_helmet",    slot = "helmet",   name = "灵纹盔",   base = { def = 8, hp = 30 },    tier = 2 },
    { id = "spirit_armor",     slot = "armor",    name = "灵纹甲",   base = { def = 14, hp = 50 },   tier = 2 },
    { id = "spirit_boots",     slot = "boots",    name = "灵纹靴",   base = { def = 5, agi = 6 },    tier = 2 },
    { id = "spirit_ring",      slot = "ring",     name = "灵石戒",   base = { atk = 6, def = 3 },    tier = 2 },
    { id = "spirit_necklace",  slot = "necklace", name = "灵玉链",   base = { hp = 35, def = 5 },    tier = 2 },

    -- ===== 金丹期（tier 3）=====
    { id = "gold_sword",       slot = "weapon",   name = "金虹剑",   base = { atk = 55 },            tier = 3 },
    { id = "gold_helmet",      slot = "helmet",   name = "紫金冠",   base = { def = 16, hp = 60 },   tier = 3 },
    { id = "gold_armor",       slot = "armor",    name = "玄晶甲",   base = { def = 28, hp = 100 },  tier = 3 },
    { id = "gold_boots",       slot = "boots",    name = "踏云靴",   base = { def = 10, agi = 12 },  tier = 3 },
    { id = "gold_ring",        slot = "ring",     name = "丹火戒",   base = { atk = 12, def = 6 },   tier = 3 },
    { id = "gold_necklace",    slot = "necklace", name = "金丹链",   base = { hp = 70, def = 10 },   tier = 3 },

    -- ===== 元婴期（tier 4）=====
    { id = "yuan_sword",       slot = "weapon",   name = "元罡剑",   base = { atk = 90 },            tier = 4 },
    { id = "yuan_helmet",      slot = "helmet",   name = "元灵冠",   base = { def = 28, hp = 100 },  tier = 4 },
    { id = "yuan_armor",       slot = "armor",    name = "元婴铠",   base = { def = 48, hp = 180 },  tier = 4 },
    { id = "yuan_boots",       slot = "boots",    name = "虚空步",   base = { def = 18, agi = 22 },  tier = 4 },
    { id = "yuan_ring",        slot = "ring",     name = "元神戒",   base = { atk = 22, def = 12 },  tier = 4 },
    { id = "yuan_necklace",    slot = "necklace", name = "元婴珠",   base = { hp = 120, def = 18 },  tier = 4 },

    -- ===== 化神期（tier 5）=====
    { id = "hua_sword",        slot = "weapon",   name = "化虹神剑", base = { atk = 140 },           tier = 5 },
    { id = "hua_helmet",       slot = "helmet",   name = "天灵冠",   base = { def = 45, hp = 160 },  tier = 5 },
    { id = "hua_armor",        slot = "armor",    name = "化神铠",   base = { def = 75, hp = 300 },  tier = 5 },
    { id = "hua_boots",        slot = "boots",    name = "神行靴",   base = { def = 30, agi = 35 },  tier = 5 },
    { id = "hua_ring",         slot = "ring",     name = "化神指",   base = { atk = 35, def = 20 },  tier = 5 },
    { id = "hua_necklace",     slot = "necklace", name = "神魂链",   base = { hp = 200, def = 28 },  tier = 5 },

    -- ===== 大乘期（tier 6）=====
    { id = "dao_sword",        slot = "weapon",   name = "道灵仙剑", base = { atk = 200 },           tier = 6 },
    { id = "dao_helmet",       slot = "helmet",   name = "大道冠",   base = { def = 70, hp = 250 },  tier = 6 },
    { id = "dao_armor",        slot = "armor",    name = "大乘法袍", base = { def = 110, hp = 450 }, tier = 6 },
    { id = "dao_boots",        slot = "boots",    name = "踏天靴",   base = { def = 45, agi = 50 },  tier = 6 },
    { id = "dao_ring",         slot = "ring",     name = "天道戒",   base = { atk = 55, def = 30 },  tier = 6 },
    { id = "dao_necklace",     slot = "necklace", name = "大道珠",   base = { hp = 300, def = 42 },  tier = 6 },

    -- ===== 渡劫期（tier 7）=====
    { id = "xian_sword",       slot = "weapon",   name = "诛仙剑",   base = { atk = 300 },           tier = 7 },
    { id = "xian_helmet",      slot = "helmet",   name = "混元冠",   base = { def = 100, hp = 400 }, tier = 7 },
    { id = "xian_armor",       slot = "armor",    name = "仙帝战铠", base = { def = 160, hp = 700 }, tier = 7 },
    { id = "xian_boots",       slot = "boots",    name = "缩地靴",   base = { def = 65, agi = 75 },  tier = 7 },
    { id = "xian_ring",        slot = "ring",     name = "仙帝戒",   base = { atk = 80, def = 45 },  tier = 7 },
    { id = "xian_necklace",    slot = "necklace", name = "天道链",   base = { hp = 450, def = 60 },  tier = 7 },
}

-- ============================================================================
-- 境界系统（取代等级系统）
-- ============================================================================
-- 境界列表：练气→筑基→金丹→元婴→化神→大乘→渡劫
-- 每个境界有若干"重"，经验填满后自动升层；跨大境界需要消耗丹药突破
Settings.REALM = {
    -- 境界定义 { id, name, layers, stat_mult_min, stat_mult_max, exp_base }
    -- stat_mult_min/max: 该境界第1重和最末重的属性倍率（层间线性插值）
    -- exp_base: 基础经验系数，实际每层所需 = exp_base * layer（层内递增）
    STAGES = {
        { id = "lianqi",   name = "练气", layers = 9,  stat_mult_min = 0.7,  stat_mult_max = 1.0,  exp_base = 100      },
        { id = "zhuji",    name = "筑基", layers = 9,  stat_mult_min = 1.1,  stat_mult_max = 1.8,  exp_base = 1000     },
        { id = "jindan",   name = "金丹", layers = 12, stat_mult_min = 2.0,  stat_mult_max = 3.2,  exp_base = 10000    },
        { id = "yuanying", name = "元婴", layers = 15, stat_mult_min = 3.5,  stat_mult_max = 5.6,  exp_base = 100000   },
        { id = "huashen",  name = "化神", layers = 18, stat_mult_min = 6.0,  stat_mult_max = 10.0, exp_base = 1000000  },
        { id = "dacheng",  name = "大乘", layers = 21, stat_mult_min = 11.0, stat_mult_max = 18.0, exp_base = 10000000 },
        { id = "dujie",    name = "渡劫", layers = 9,  stat_mult_min = 19.0, stat_mult_max = 30.0, exp_base = 100000000},
    },

    -- 突破成功率（按境界索引，层间突破使用当前境界的成功率）
    -- 练气期100%成功（村长送丹药），后续递减
    SUCCESS_RATE = {
        [1] = 1.00,  -- 练气: 100%
        [2] = 0.80,  -- 筑基: 80%
        [3] = 0.65,  -- 金丹: 65%
        [4] = 0.50,  -- 元婴: 50%
        [5] = 0.40,  -- 化神: 40%
        [6] = 0.30,  -- 大乘: 30%
        [7] = 0.20,  -- 渡劫: 20%
    },

    -- 突破失败惩罚（中等惩罚）
    FAILURE = {
        DROP_LAYER_CHANCE = 0.15,   -- 15% 概率跌落1层（原30%，优化玩家体验）
        EXP_LOSS_RATIO    = 0.50,   -- 失败后经验保留50%（损失一半）
    },

    -- 加入门派所需境界: 筑基1层 (realm=2, layer=1)
    JOIN_SECT_REALM  = 2,  -- 筑基
    JOIN_SECT_LAYER  = 1,

    -- 悟性对修炼速度的加成系数
    WIS_CULTIVATE_FACTOR = 0.02,
}

-- 突破所需丹药（按当前境界索引，突破到下一层/下一境界时消耗）
Settings.REALM_PILLS = {
    [2] = { pill_id = "pill_zhuji",    count = 1, name = "筑基丹" },
    [3] = { pill_id = "pill_ningdan",  count = 1, name = "凝丹散" },
    [4] = { pill_id = "pill_yuanying", count = 1, name = "元婴丹" },
    [5] = { pill_id = "pill_huashen",  count = 1, name = "化神丹" },
    [6] = { pill_id = "pill_dacheng",  count = 1, name = "大乘丹" },
    [7] = { pill_id = "pill_dujie",    count = 1, name = "渡劫丹" },
}

-- 辅助：根据 realm + layer 计算总"等级数"（兼容旧逻辑如怪物难度对比）
-- 练气9重=9, 筑基1重=10, 筑基9重=18, 金丹1重=19...
Settings.REALM.CalcPowerLevel = function(realm, layer)
    local total = 0
    local stages = Settings.REALM.STAGES
    for i = 1, realm - 1 do
        total = total + stages[i].layers
    end
    return total + layer
end

-- 辅助：获取当前层所需经验（层内递增：exp_base * layer）
Settings.REALM.GetExpNeeded = function(realm, layer)
    local stage = Settings.REALM.STAGES[realm]
    if not stage then return 99999999 end
    return stage.exp_base * layer
end

-- 辅助：获取指定境界的总经验需求
Settings.REALM.GetTotalExp = function(realm)
    local stage = Settings.REALM.STAGES[realm]
    if not stage then return 0 end
    local total = 0
    for i = 1, stage.layers do
        total = total + stage.exp_base * i
    end
    return total
end

-- 辅助：获取 realm+layer 对应的 stat_mult（层内线性插值）
Settings.REALM.GetStatMult = function(realm, layer)
    local stage = Settings.REALM.STAGES[realm]
    if not stage then return 1.0 end
    if stage.layers <= 1 then
        return stage.stat_mult_max
    end
    local t = (layer - 1) / (stage.layers - 1)  -- 0.0 ~ 1.0
    return stage.stat_mult_min + t * (stage.stat_mult_max - stage.stat_mult_min)
end

-- 辅助：获取境界显示名（如"练气九重"、"筑基一重"）
Settings.REALM.GetDisplayName = function(realm, layer)
    local stage = Settings.REALM.STAGES[realm]
    if not stage then return "未知" end
    local cn = {"一","二","三","四","五","六","七","八","九","十",
                "十一","十二","十三","十四","十五","十六","十七","十八",
                "十九","二十","二十一"}
    return stage.name .. (cn[layer] or tostring(layer)) .. "重"
end

-- 辅助：判断是否已满级（渡劫九重）
Settings.REALM.IsMaxRealm = function(realm, layer)
    local stages = Settings.REALM.STAGES
    return realm >= #stages and layer >= stages[#stages].layers
end

-- ============================================================================
-- 修为丹系统：花灵石加速境界修为，每日服用上限10次
-- ============================================================================
Settings.REALM_EXP_PILLS = {
    DAILY_USE_LIMIT = 10,  -- 每日服用上限（非购买上限）
    -- 按境界索引：能买任何境界的丹，但只能服用当前境界对应的
    PILLS = {
        [1] = { id = "pill_juqi",    name = "聚气丸", realm_id = "lianqi",   exp = 100,      cost_spirit = 8   },
        [2] = { id = "pill_guji",    name = "固基丸", realm_id = "zhuji",    exp = 1000,     cost_spirit = 15  },
        [3] = { id = "pill_ningyuan",name = "凝元丸", realm_id = "jindan",   exp = 10000,    cost_spirit = 25  },
        [4] = { id = "pill_yuying",  name = "育婴丸", realm_id = "yuanying", exp = 100000,   cost_spirit = 40  },
        [5] = { id = "pill_hualing", name = "化灵丸", realm_id = "huashen",  exp = 1000000,  cost_spirit = 60  },
        [6] = { id = "pill_guiyuan", name = "归元丸", realm_id = "dacheng",  exp = 10000000, cost_spirit = 80  },
        [7] = { id = "pill_tianjie", name = "天劫丸", realm_id = "dujie",    exp = 100000000,cost_spirit = 100 },
    },
}

-- 兼容旧代码引用（逐步迁移中）
Settings.LEVEL = {
    MAX = 25,
    EXP_PER_LEVEL = function(lv) return lv * 100 end,
    JOIN_SECT_LEVEL = 10,
    WIS_CULTIVATE_FACTOR = 0.02,
}

-- ============================================================================
-- 修炼系统 - 熟练度分阶 & 潜能消耗
-- ============================================================================

-- 6阶熟练度：比例用于计算每阶占总 max_proficiency 的份额
-- 前3阶(27%)到达"融会贯通"即可解锁下一等级功法
Settings.PROFICIENCY_TIERS = {
    { name = "初窥门径", ratio = 1   },  -- 6.1%
    { name = "略有小成", ratio = 1.5 },  -- 9.1%
    { name = "融会贯通", ratio = 2   },  -- 12.1% (累计27.3%，解锁下阶功法)
    { name = "炉火纯青", ratio = 3   },  -- 18.2%
    { name = "登峰造极", ratio = 4   },  -- 24.2%
    { name = "返璞归真", ratio = 5   },  -- 30.3% (累计100%)
}
-- 从"融会贯通"开始获得渐进加成（乘以 stat_bonus）
-- 未达融会贯通 = 1.0（无额外加成，stat_bonus * proficiency 正常生效）
Settings.PROFICIENCY_BONUS = {
    [3] = 1.0,   -- 融会贯通：基础100%
    [4] = 1.3,   -- 炉火纯青：130%
    [5] = 1.6,   -- 登峰造极：160%
    [6] = 2.0,   -- 返璞归真：200%
}

-- 按功法 grade 决定修炼总消耗潜能（填满整条熟练度所需）
Settings.CULTIVATE_COST_BY_GRADE = {
    [1] = 30000,      -- 初级：~2.5天 (lv5玩家)
    [2] = 150000,     -- 中级：~1周 (lv10玩家)
    [3] = 500000,     -- 高级：~2周 (lv20玩家)
    [4] = 1500000,    -- 绝品：~1月 (lv35玩家)
    [5] = 5000000,    -- 神品：~2.5月 (lv50玩家)
}

-- 功法升阶（灵石消耗）：熟练度满后可消耗灵石升阶
-- 阶层：0=基础, 1=精通, 2=圆满, 3=大成
Settings.SKILL_TIER_UP = {
    TIERS = {
        { name = "基础", bonus = 1.0 },
        { name = "精通", bonus = 1.3 },
        { name = "圆满", bonus = 1.6 },
        { name = "大成", bonus = 2.0 },
    },
    -- 升阶灵石消耗（从当前阶到下一阶）
    COSTS = {
        [0] = 30,   -- 基础→精通
        [1] = 60,   -- 精通→圆满
        [2] = 120,  -- 圆满→大成
    },
    MAX_TIER = 3,
}
-- 潜能获取配置
Settings.POTENTIAL = {
    -- 击杀怪物：5 + 怪物等级 × 2（野狼7, 山贼11, 黑熊15, 妖狼21）
    MONSTER_BASE = 5,
    MONSTER_PER_LEVEL = 2,
    -- Boss额外倍率
    BOSS_MULTIPLIER = 3,
    -- 离线挂机每秒潜能（按玩家等级：level × 0.15）
    OFFLINE_PER_LEVEL = 0.15,
}

-- 修炼速率：每秒消耗多少潜能（快速消耗型，约10-15秒耗尽储备）
-- 实际消耗 = CULTIVATE_DRAIN_PER_SEC × costMultiplier
Settings.CULTIVATE_DRAIN_PER_SEC = 80

-- 自主修炼 vs 师傅修炼的消耗倍率
Settings.CULTIVATE_COST_MULT = {
    SELF   = 1.2,  -- 自主修炼：1.2倍消耗
    MASTER = 1.0,  -- 师傅指导：1.0倍消耗
}

-- ============================================================================
-- 福利广告奖励
-- ============================================================================
Settings.AD_REWARD = {
    SPIRIT_STONE = 10,         -- 每次观看广告奖励灵石数量
    DAILY_LIMIT  = 5,          -- 每日最多观看次数
    COOLDOWN     = 60,         -- 两次观看最短间隔（秒）
}

-- ============================================================================
-- 服务器/分区配置
-- ============================================================================
Settings.SERVERS = {
    { id = 1, name = "青云境", status = "open", recommend = true },
    -- 后续加服只需在此追加，如：
    -- { id = 2, name = "玄天域", status = "open" },
}

-- ============================================================================
-- 管理员测试开关（玩家级 debug flags，存入玩家存档）
-- ============================================================================
Settings.ADMIN_DEBUG_FLAGS = {
    { key = "dbg_unlimited_pill",  label = "无限吃药", desc = "修为丹无每日次数限制" },
    { key = "dbg_god_mode",        label = "无敌模式", desc = "战斗中不掉血" },
    { key = "dbg_one_hit_kill",    label = "秒杀模式", desc = "战斗一击必杀" },
    { key = "dbg_fast_cultivate",  label = "修炼加速", desc = "打坐经验×100" },
    { key = "dbg_free_cost",       label = "免费购物", desc = "银两/灵石不扣" },
}

-- ============================================================================
-- 灵石消耗功能
-- ============================================================================
Settings.SPIRIT_STONE = {
    -- 修炼加速：灵石开启2倍修炼速度（单次打坐期间有效）
    CULTIVATE_BOOST_COST = 5,       -- 每次加速消耗灵石
    CULTIVATE_BOOST_MULT = 2.0,     -- 加速倍率（2倍速）

    -- 突破保护：防止掉境界和损失经验
    BREAKTHROUGH_PROTECT_COST = 20, -- 突破保护消耗灵石

    -- 改名
    RENAME_COST       = 10,         -- 玩家改名消耗灵石
    GUILD_RENAME_COST = 50,         -- 帮会改名消耗灵石（仅帮主）
    NAME_MIN_LEN      = 2,          -- 最短名称长度（字符数）
    NAME_MAX_LEN      = 8,          -- 最长名称长度（汉字数）

    -- 免死/复活：战败时灵石保护
    REVIVE_COST = 10,               -- 免死每次消耗灵石

    -- 帮会加速升级
    GUILD_BOOST_COST = 20,          -- 帮会加速升级消耗灵石
    GUILD_BOOST_EXP  = 500,         -- 每次加速获得帮会经验

    -- 角色创建
    CREATE_NAME_MIN_LEN = 1,        -- 创建角色名最短（字符数）
    CREATE_NAME_MAX_LEN = 6,        -- 创建角色名最长（字符数）
    INVITE_REWARD       = 100,      -- 邀请码奖励灵石（双方各得）
}

-- ============================================================================
-- 挂机经验（在线/离线均随境界动态缩放）
-- 设计基准：假设玩家每天 8h离线 + 4h在线修炼(2倍速) = 16有效小时/天
-- ============================================================================
Settings.OFFLINE = {
    MAX_SECONDS = 8 * 3600,         -- 离线最多累积8小时
    SILVER_PER_SECOND = 0.2,        -- 每秒银两
    -- 每个境界"光挂机"升满需要的天数（按 STAGES 索引 1-7）
    REALM_DAYS = {
        1,      -- 练气: 1天
        3,      -- 筑基: 3天
        10,     -- 金丹: 10天
        20,     -- 元婴: 20天
        40,     -- 化神: 40天
        80,     -- 大乘: 80天
        160,    -- 渡劫: 160天（暂定）
    },
    EFFECTIVE_HOURS_PER_DAY = 16,   -- 每日有效小时（8h离线 + 4h在线×2倍）
}

-- 在线修炼额外给经验（比离线快，奖励在线）
Settings.ONLINE_CULTIVATE = {
    EXP_MULT = 2.0,                 -- 在线修炼经验速率 = 离线速率 × 此倍率
}

-- 辅助：获取指定境界每层所需的离线等效小时数
Settings.OFFLINE.GetHoursPerLayer = function(realm)
    local stage = Settings.REALM.STAGES[realm]
    if not stage then return 24 end
    local days = Settings.OFFLINE.REALM_DAYS[realm] or 80
    return days * Settings.OFFLINE.EFFECTIVE_HOURS_PER_DAY / stage.layers
end

-- ============================================================================
-- 战斗系统
-- ============================================================================
Settings.BATTLE = {
    ROUND_INTERVAL = 2.0,       -- 每回合间隔（秒）
    -- 内力每回合恢复比例（降低以使内力管理有意义：高境界mp大，10%会完全抵消消耗）
    INNER_REGEN = 0,             -- 战斗中不自动恢复内力，需吃丹药
    MEDICINE_COOLDOWN = 30,     -- 药品公共冷却（秒）
    -- GDD公式：逃跑率 = (敌方敏捷 - 我方敏捷) × 1%，无基础成功率
    FLEE_BASE_RATE = 0.0,       -- 基础逃跑成功率（GDD无基础值）
    FLEE_AGI_FACTOR = 0.01,     -- 敏捷差每点影响逃跑率
    DAMAGE_RANDOM = 0.05,       -- 伤害随机波动范围
    DAMAGE_COEFF_CAP = 3.0,     -- 伤害系数上限封顶

    -- 疾风剑派：连击叠加系统
    SWIFT_COMBO_MAX   = 5,      -- 最大连击层数
    SWIFT_COMBO_BONUS = 0.15,   -- 每层额外伤害加成（15%）

    -- 疾风连击（multi_hit）：基于agi优势触发额外一击
    MULTI_HIT_AGI_THRESHOLD = 20,  -- agi差值超过此值开始有多击概率
    MULTI_HIT_CHANCE_PER_AGI = 0.02, -- 每超出1点agi增加2%多击概率
    MULTI_HIT_CHANCE_CAP = 0.60,   -- 多击概率上限60%
    MULTI_HIT_DAMAGE_MULT = 0.5,   -- 多击伤害为首击的50%

    -- agi闪避机制
    -- 公式: dodge = defender_agi/(defender_agi+attacker_agi)*0.6 - 0.1
    DODGE_FACTOR = 0.6,         -- 闪避因子
    DODGE_OFFSET = 0.1,         -- 闪避基础偏移（确保低agi不闪避）
    DODGE_CAP    = 0.45,        -- 闪避率上限45%
    DODGE_SKILL_BONUS = 0.15,   -- dodge型技能额外+15%闪避

    -- wis机制
    -- 技能伤害加成: wis/(wis+500)
    WIS_DAMAGE_DIVISOR = 500,   -- wis伤害加成分母
    -- 控制抗性: defender_wis/(defender_wis+attacker_wis+200)
    WIS_RESIST_OFFSET = 200,    -- 控制抗性偏移

    -- defend型（盾卫）
    DEFEND_REDUCTION = 0.35,    -- 每层减伤35%
    DEFEND_DURATION  = 3,       -- 持续3回合
    DEFEND_MAX_STACK = 2,       -- 最多叠2层（70%上限）

    -- DoT系统
    -- 灼烧：2回合，前重后轻（100%→50%），不可叠加，刷新持续时间
    BURN_ROUNDS = 2,
    BURN_DISTRIBUTION = { 1.0, 0.5 },  -- 第1回合100%，第2回合50%
    -- 毒伤：3回合，后重前轻（30%→70%→100%），可叠3层，减疗50%
    POISON_ROUNDS = 3,
    POISON_DISTRIBUTION = { 0.3, 0.7, 1.0 },
    POISON_MAX_STACKS = 3,
    POISON_HEAL_REDUCTION = 0.50,  -- 中毒状态减疗50%

    -- 眩晕递减
    STUN_DIMINISH_MULT = 0.5,   -- 同场战斗第二次眩晕概率减半
}

-- ============================================================================
-- 货币类型
-- ============================================================================
Settings.CURRENCY = {
    SILVER      = "silver",      -- 银两：日常打怪/NPC购买/低价交易
    SPIRIT_STONE= "spirit_stone",-- 灵石：交易阁高价值物品（功法/精良+装备）
}

-- ============================================================================
-- NPC商店商品（装备铺 - 银两结算）
-- ============================================================================
Settings.EQUIPMENT_SHOP = {
    -- 仅保留新手铁器（练气期）
    { id = "shop_iron_sword",    name = "铁剑",       slot = "weapon",   quality = 1, price = 80,
      stats = { atk = 8 },       desc = "锻造粗糙的铁剑，入门习武者常用。" },
    { id = "shop_steel_sword",   name = "钢剑",       slot = "weapon",   quality = 1, price = 200,
      stats = { atk = 15 },      desc = "精钢铸造，剑身流光，初窥门道。" },
    { id = "shop_iron_helmet",   name = "铁盔",       slot = "helmet",   quality = 1, price = 60,
      stats = { def = 3, hp = 10 }, desc = "标准铁盔，头部防护基础保障。" },
    { id = "shop_iron_armor",    name = "铁甲",       slot = "armor",    quality = 1, price = 120,
      stats = { def = 6, hp = 20 }, desc = "铁片拼制的铠甲，结实耐用。" },
    { id = "shop_iron_boots",    name = "铁靴",       slot = "boots",    quality = 1, price = 50,
      stats = { def = 2, agi = 2 }, desc = "厚底铁靴，行走稳健。" },
    { id = "shop_copper_ring",   name = "铜指环",     slot = "ring",     quality = 1, price = 40,
      stats = { atk = 2, def = 1 }, desc = "铜铸指环，细微加持。" },
    { id = "shop_jade_necklace", name = "玉坠",       slot = "necklace", quality = 1, price = 55,
      stats = { hp = 15, def = 2 }, desc = "温润玉石，强健体魄。" },
}

-- ============================================================================
-- NPC商店商品（药铺 - 银两结算）
-- ============================================================================
Settings.MEDICINE_SHOP = {
    -- 药铺只卖消耗品（回血回内），突破丹统一走交易阁
    { id = "medicine_small_hp",  name = "小回血丹",   type = "medicine", price = 40,
      effect = { hp = 40 },      desc = "最基础的疗伤丹药，略微止血。" },
    { id = "medicine_medium_hp", name = "中回血丹",   type = "medicine", price = 120,
      effect = { hp = 100 },     desc = "炼制精良，可快速恢复大量气血。" },
    { id = "medicine_large_hp",  name = "大回血丹",   type = "medicine", price = 300,
      effect = { hp = 250 },     desc = "上品疗伤丹，危急时刻力挽狂澜。" },
    { id = "medicine_small_mp",  name = "小回内丹",   type = "medicine", price = 50,
      effect = { mp = 40 },      desc = "略微恢复内力，打坐时常备。" },
    { id = "medicine_medium_mp", name = "中回内丹",   type = "medicine", price = 150,
      effect = { mp = 100 },     desc = "恢复大量内力，持续战斗必备。" },
}

-- ============================================================================
-- 丹药物品定义（突破用丹药 —— 仅丹宗可炼制，可交易）
-- ============================================================================
Settings.PILLS = {
    pill_zhuji = {
        name = "筑基丹", type = "pill", quality = 2, tradeable = true,
        desc = "凝聚灵气筑实根基，筑基期突破必备。",
        use_realm = 2,
    },
    pill_ningdan = {
        name = "凝丹散", type = "pill", quality = 3, tradeable = true,
        desc = "凝聚天地灵气为散，助修士结成金丹。",
        use_realm = 3,
    },
    pill_yuanying = {
        name = "元婴丹", type = "pill", quality = 4, tradeable = true,
        desc = "孕育元婴的珍稀丹药，材料极为罕见。",
        use_realm = 4,
    },
    pill_huashen = {
        name = "化神丹", type = "pill", quality = 5, tradeable = true,
        desc = "化解肉身桎梏，神魂蜕变之丹。",
        use_realm = 5,
    },
    pill_dacheng = {
        name = "大乘丹", type = "pill", quality = 5, tradeable = true,
        desc = "凝练大道法则入丹，世间极品。",
        use_realm = 6,
    },
    pill_dujie = {
        name = "渡劫丹", type = "pill", quality = 5, tradeable = true,
        desc = "护体渡劫之圣药，传说级丹药，万年难遇。",
        use_realm = 7,
    },
}

-- ============================================================================
-- 炼丹材料定义
-- ============================================================================
Settings.ALCHEMY_MATERIALS = {
    herb_green       = { name = "青灵草",   quality = 1, price = 35,  desc = "略带灵气的草药，味苦。" },
    herb_fire        = { name = "火灵花",   quality = 2, price = 80,  desc = "生长于火山附近，花瓣滚烫。" },
    herb_ice         = { name = "冰魄莲",   quality = 2, price = 80,  desc = "寒潭深处的莲花，触之生寒。" },
    herb_earth       = { name = "地脉参",   quality = 3, price = 200, desc = "扎根地脉百年方成，灵气浓厚。" },
    herb_golden      = { name = "金叶兰",   quality = 3, price = 250, desc = "叶片金黄如锻金，稀有灵植。" },
    herb_dragon      = { name = "龙血草",   quality = 4, price = 600, desc = "传说沾染过龙血的灵草，气息磅礴。" },
    herb_celestial   = { name = "天元果",   quality = 4, price = 800, desc = "万年灵树所结之果，蕴含天道法则。" },
    herb_divine      = { name = "神木髓",   quality = 5, price = 2000,desc = "神木精华凝结，可遇不可求。" },
    catalyst_powder  = { name = "聚灵粉",   quality = 1, price = 15,  desc = "辅助炼丹的基础催化剂。" },
    catalyst_crystal = { name = "凝丹晶",   quality = 2, price = 100, desc = "提升成丹率的珍贵晶体。" },
    catalyst_divine  = { name = "天火石",   quality = 4, price = 500, desc = "引导天火炼丹的奇石。" },
    -- 炼器矿石材料（域外战场怪物掉落）
    ore_copper       = { name = "赤铜矿",   quality = 1, price = 25,  desc = "最常见的灵矿，可锻造低阶法器。" },
    ore_iron         = { name = "玄铁矿",   quality = 2, price = 60,  desc = "品质上乘的铁矿，硬度极高。" },
    ore_silver       = { name = "银灵矿",   quality = 2, price = 90,  desc = "银白色灵矿，导灵性极佳。" },
    ore_mithril      = { name = "秘银矿",   quality = 3, price = 220, desc = "轻若无物却坚逾精钢，中阶法器首选。" },
    ore_darksteel    = { name = "暗钢矿",   quality = 3, price = 280, desc = "深渊矿脉所产，附带阴寒之力。" },
    ore_starfall     = { name = "陨星铁",   quality = 4, price = 650, desc = "天外陨石所含灵铁，蕴含星辰之力。" },
    ore_celestial    = { name = "天晶石",   quality = 5, price = 1800,desc = "仙界遗落的神矿碎片，可锻神器。" },
}

-- ============================================================================
-- 炼丹配方（仅丹宗弟子可使用）
-- ============================================================================
Settings.ALCHEMY_RECIPES = {
    pill_zhuji = {
        name = "筑基丹",
        min_skill_level = 2,
        materials = { { id = "herb_green", count = 3 }, { id = "herb_fire", count = 1 }, { id = "catalyst_powder", count = 2 } },
        success_rate = 0.75,
        yield = { min = 1, max = 1 },
        exp_gain = 15,
        time = 10,
    },
    pill_ningdan = {
        name = "凝丹散",
        min_skill_level = 3,
        materials = { { id = "herb_fire", count = 2 }, { id = "herb_earth", count = 2 }, { id = "catalyst_crystal", count = 1 } },
        success_rate = 0.60,
        yield = { min = 1, max = 1 },
        exp_gain = 30,
        time = 20,
    },
    pill_yuanying = {
        name = "元婴丹",
        min_skill_level = 4,
        materials = { { id = "herb_earth", count = 2 }, { id = "herb_golden", count = 2 }, { id = "herb_dragon", count = 1 }, { id = "catalyst_crystal", count = 2 } },
        success_rate = 0.45,
        yield = { min = 1, max = 1 },
        exp_gain = 60,
        time = 30,
    },
    pill_huashen = {
        name = "化神丹",
        min_skill_level = 5,
        materials = { { id = "herb_dragon", count = 2 }, { id = "herb_celestial", count = 2 }, { id = "catalyst_divine", count = 1 } },
        success_rate = 0.35,
        yield = { min = 1, max = 1 },
        exp_gain = 100,
        time = 45,
    },
    pill_dacheng = {
        name = "大乘丹",
        min_skill_level = 5,
        materials = { { id = "herb_celestial", count = 3 }, { id = "herb_divine", count = 1 }, { id = "catalyst_divine", count = 2 } },
        success_rate = 0.25,
        yield = { min = 1, max = 1 },
        exp_gain = 150,
        time = 60,
    },
    pill_dujie = {
        name = "渡劫丹",
        min_skill_level = 5,
        materials = { { id = "herb_divine", count = 3 }, { id = "herb_celestial", count = 3 }, { id = "catalyst_divine", count = 3 } },
        success_rate = 0.15,
        yield = { min = 1, max = 1 },
        exp_gain = 300,
        time = 90,
    },
}

-- ============================================================================
-- 炼丹材料商店（丹宗材料库NPC贩卖 - 银两结算）
-- ============================================================================
Settings.ALCHEMY_MATERIAL_SHOP = {
    { id = "herb_green",       count = 1, price = 35  },
    { id = "herb_fire",        count = 1, price = 80  },
    { id = "herb_ice",         count = 1, price = 80  },
    { id = "catalyst_powder",  count = 1, price = 15  },
    { id = "catalyst_crystal", count = 1, price = 100 },
    -- 高级材料不在商店出售，需打怪/交易获得
}

-- ============================================================================
-- 炼器系统（装备锻造）
-- ============================================================================
Settings.FORGE = {
    CRAFT_TIME = 3,  -- 每件装备炼制时间（秒）

    -- 各等阶炼器配方（tier → 配方）
    RECIPES = {
        [2] = { main = { id = "ore_copper",    count = 5 }, sub = { id = "ore_iron",      count = 2 } },
        [3] = { main = { id = "ore_iron",      count = 5 }, sub = { id = "ore_silver",    count = 3 } },
        [4] = { main = { id = "ore_mithril",   count = 5 }, sub = { id = "ore_darksteel", count = 3 } },
        [5] = { main = { id = "ore_darksteel", count = 5 }, sub = { id = "ore_starfall",  count = 3 } },
        [6] = { main = { id = "ore_starfall",  count = 5 }, sub = { id = "ore_celestial", count = 2 } },
        [7] = { main = { id = "ore_celestial", count = 5 }, sub = { id = "ore_starfall",  count = 3 } },
    },

    -- 各等阶失败率
    FAIL_RATE = {
        [2] = { normal = 0.15, qidan = 0.05 },   -- 筑基
        [3] = { normal = 0.20, qidan = 0.08 },   -- 金丹
        [4] = { normal = 0.30, qidan = 0.12 },   -- 元婴
        [5] = { normal = 0.40, qidan = 0.18 },   -- 化神
        [6] = { normal = 0.50, qidan = 0.25 },   -- 大乘
        [7] = { normal = 0.60, qidan = 0.35 },   -- 渡劫
    },

    -- 品质产出概率
    QUALITY_RATES = {
        normal = {  -- 其他门派
            { quality = 1, weight = 60   },  -- 普通 60%
            { quality = 2, weight = 25   },  -- 优秀 25%
            { quality = 3, weight = 10   },  -- 精良 10%
            { quality = 4, weight = 4    },  -- 史诗 4%
            { quality = 5, weight = 0.9  },  -- 传说 0.9%
            { quality = 6, weight = 0.1  },  -- 神器 0.1%
        },
        qidan = {  -- 器丹门派
            { quality = 1, weight = 40   },  -- 普通 40%
            { quality = 2, weight = 30   },  -- 优秀 30%
            { quality = 3, weight = 18   },  -- 精良 18%
            { quality = 4, weight = 9    },  -- 史诗 9%
            { quality = 5, weight = 2.5  },  -- 传说 2.5%
            { quality = 6, weight = 0.5  },  -- 神器 0.5%
        },
    },

    -- 史诗保底次数（按等阶）
    PITY = {
        [2] = 100,   -- 二阶 100次保底史诗
        [3] = 120,   -- 三阶
        [4] = 150,   -- 四阶
        [5] = 180,   -- 五阶
        [6] = 200,   -- 六阶
        [7] = 250,   -- 七阶
    },
}

-- 图纸配置（藏书阁出售）
-- 每个图纸对应 EQUIPMENT_TEMPLATES 中的一个 template_id
Settings.BLUEPRINTS = {}
do
    -- 图纸价格表：tier → { weapon, armor/helmet/boots, ring/necklace }
    local BLUEPRINT_PRICES = {
        [2] = { weapon = 1000,   armor = 600,    accessory = 500   },
        [3] = { weapon = 4000,   armor = 2500,   accessory = 2000  },
        [4] = { weapon = 12000,  armor = 8000,   accessory = 6000  },
        [5] = { weapon = 40000,  armor = 25000,  accessory = 20000 },
        [6] = { weapon = 120000, armor = 80000,  accessory = 60000 },
        [7] = { weapon = 350000, armor = 220000, accessory = 180000},
    }
    -- 部位 → 价格类型映射
    local SLOT_PRICE_TYPE = {
        weapon = "weapon", helmet = "armor", armor = "armor",
        boots = "armor", ring = "accessory", necklace = "accessory",
    }
    -- 解锁境界门槛（tier → 所需最低境界index）
    local BLUEPRINT_REALM_REQ = { [2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 6, [7] = 7 }

    for _, tmpl in ipairs(Settings.EQUIPMENT_TEMPLATES) do
        local tier = tmpl.tier or 1
        if tier >= 2 then
            local priceType = SLOT_PRICE_TYPE[tmpl.slot] or "accessory"
            local price = BLUEPRINT_PRICES[tier] and BLUEPRINT_PRICES[tier][priceType] or 1000
            Settings.BLUEPRINTS[tmpl.id] = {
                template_id  = tmpl.id,
                name         = tmpl.name .. "图纸",
                equip_name   = tmpl.name,
                tier         = tier,
                slot         = tmpl.slot,
                price        = price,
                realm_req    = BLUEPRINT_REALM_REQ[tier] or 2,
            }
        end
    end
end

-- 战场楼层矿石掉落配置
Settings.BATTLEFIELD_ORE_DROPS = {
    [1]  = { { id = "ore_copper", rate = 0.40 } },
    [2]  = { { id = "ore_copper", rate = 0.45 } },
    [3]  = { { id = "ore_copper", rate = 0.35 }, { id = "ore_iron",      rate = 0.25 } },
    [4]  = { { id = "ore_iron",   rate = 0.40 }, { id = "ore_silver",    rate = 0.20 } },
    [5]  = { { id = "ore_silver", rate = 0.35 }, { id = "ore_mithril",   rate = 0.20 } },
    [6]  = { { id = "ore_mithril",rate = 0.35 }, { id = "ore_darksteel", rate = 0.20 } },
    [7]  = { { id = "ore_darksteel",rate= 0.35}, { id = "ore_starfall",  rate = 0.20 } },
    [8]  = { { id = "ore_starfall", rate= 0.40 } },
    [9]  = { { id = "ore_starfall", rate= 0.30 }, { id = "ore_celestial", rate = 0.15 } },
    [10] = { { id = "ore_celestial",rate= 0.35 } },
}

-- ============================================================================
-- 经济系统
-- ============================================================================
Settings.INVENTORY_MAX = 30  -- 背包格子上限

Settings.ECONOMY = {
    MARKET_TAX          = 0.03,         -- 交易手续费3%（银两交易，大幅降低促进交易）
    MARKET_TAX_STONE    = 0.02,         -- 灵石交易手续费2%（精品市场）
    MARKET_DURATION     = 7 * 24 * 3600,-- 上架有效期7天（秒）
    -- 灵石定价门槛：品质>=3（精良）的物品才可灵石定价
    SPIRIT_STONE_MIN_QUALITY = 3,
    -- 管理员超管标识（云端存档中的特殊字段）
    ADMIN_FLAG_KEY  = "is_admin",
    ADMIN_CODE      = "2004120", -- 管理员激活码
    -- NPC商人波动定价系统
    NPC_PRICE_FLUCTUATION = 0.30,   -- 价格波动幅度±30%
    NPC_PRICE_CYCLE_HOURS = 24,     -- 价格刷新周期（小时）
    -- NPC自动上架交易阁（器丹宗丹药供给，灵石标价）
    NPC_AUTO_LISTINGS = {
        ENABLED = true,
        RESTOCK_INTERVAL = 3600,    -- 每小时检查补货一次（秒）
        SELLER_NAME = "器丹宗·丹药阁",
        -- 每种丹药保持的最大在架数量和灵石价格（比NPC直售略贵，鼓励玩家炼丹）
        ITEMS = {
            { pill_id = "pill_zhuji",    max_stock = 5, price = 6,   name = "筑基丹",  quality = 2 },
            { pill_id = "pill_ningdan",  max_stock = 3, price = 25,  name = "凝丹散",  quality = 3 },
            { pill_id = "pill_yuanying", max_stock = 2, price = 80,  name = "元婴丹",  quality = 4 },
        },
    },
}

-- ============================================================================
-- 倒爷等级系统（累计利润升级，奖励手续费减免）
-- ============================================================================
Settings.TRADER_LEVELS = {
    -- level 0 = 无称号（默认）— 利润单位：灵石
    [1] = { title = "货郎",     profit = 10,     tax_discount = 0.005 },  -- 10💎
    [2] = { title = "行商",     profit = 100,    tax_discount = 0.010 },  -- 100💎
    [3] = { title = "坐贾",     profit = 500,    tax_discount = 0.015 },  -- 500💎
    [4] = { title = "豪商",     profit = 2000,   tax_discount = 0.020 },  -- 2000💎
    [5] = { title = "商道之祖", profit = 10000,  tax_discount = 0.025 },  -- 10000💎
}

-- ============================================================================
-- 初始玩家数据
-- ============================================================================
Settings.INITIAL_PLAYER = {
    -- 境界系统（替代 level）
    realm = 1,         -- 当前大境界索引（1=练气）
    realm_layer = 1,   -- 当前层数（练气一层）
    realm_exp = 0,     -- 当前层经验
    level = 1,         -- [兼容] 等效等级（由 CalcPowerLevel 计算，仅显示用）
    exp = 0,
    potential = 0,
    hp_base = 100,
    mp_base = 100,
    atk_base = 10,
    def_base = 5,
    agi_base = 10,
    wis_base = 10,
    silver = 50,       -- 初始银两
    spirit_stone = 50, -- 初始灵石（新手赠送）
    scene = "ancient_village",  -- 新玩家先进古村完成新手引导
    tutorial_step = 0,          -- 新手引导进度：0=未开始 1=已接任务 2=已击败幼妖 3=已完成
    sect = "",         -- 未加入门派
    skills = {},       -- 已学功法
    inventory = {},    -- 背包
    equipment = {},    -- 已装备
    cultivating = "",  -- 当前修炼的功法
    in_battle = false,
    gender = "male",   -- 性别（male/female）
    invite_code = "",  -- 本人邀请码（6位大写字母+数字，首次创建时生成）
    invited_by = "",   -- 填写的邀请人邀请码（空=没填）
    logout_time = 0,   -- 上次下线时间
    alchemy_exp = 0,   -- 炼丹经验（器丹宗·炼丹分支专属）
    alchemy_level = 0, -- 炼丹等级（由经验计算：0=未入门，1-5=学徒到大师）
    forge_exp = 0,     -- 炼器经验（器丹宗·炼器分支专属）
    forge_level = 0,   -- 炼器等级（由经验计算：0=未入门，1-5=学徒到大师）
    guild_id = "",     -- 所属帮会ID（空=无帮会）
    boss_defeated = {},            -- 已击败的 Boss ID 列表（如 {"boss_1","boss_2"}）
    max_battlefield_layer = 2,     -- 当前可进入的最高域外层（初始=BATTLEFIELD_INITIAL_LAYERS）
    trade_profit = 0,              -- 累计交易利润（倒爷等级依据）
    trader_level = 0,              -- 倒爷等级（0=无称号，1-5）
}

-- ============================================================================
-- 门派基础信息（供 Server.lua 和 Client.lua 共享使用）
-- ============================================================================
Settings.SECT_INFO = {
    sword_sect = {
        display       = "剑宗",
        short         = "剑宗",
        master_title  = "掌门",
        color         = { 100, 180, 255 },  -- 蓝白色
        intro         = "以剑立派，疾风与重剑双修，攻击之道的巅峰所在。千年剑冢埋葬无数绝世剑法，只有真正有缘之人方能悉数习得。",
        branches      = { swift = "疾风剑派", heavy = "重剑门" },
    },
    iron_sect = {
        display       = "铁壁宗",
        short         = "铁壁",
        master_title  = "掌门",
        color         = { 180, 180, 200 },  -- 银灰色
        intro         = "以铁铸体，盾卫与铁身双修，坚守不败的防御流派。弟子以一夫当关之姿傲立江湖，令敌人望而却步，无计可施。",
        branches      = { shield = "盾卫", ironbody = "铁身" },
    },
    medicine_sect = {
        display       = "药王谷",
        short         = "药谷",
        master_title  = "谷主",
        color         = { 100, 200, 120 },  -- 草绿色
        intro         = "医武并济，治愈与毒功双修，奇诡莫测的医道流派。万毒池中蕴藏天下至毒，百草园内遍植天下至药，两者相辅相成。",
        branches      = { heal = "治愈", poison = "毒功" },
    },
    shadow_sect = {
        display       = "天影楼",
        short         = "天影",
        master_title  = "楼主",
        color         = { 180, 120, 220 },  -- 紫色
        intro         = "以速度与隐匿立道，暗器与影步俱精，出奇制胜的刺客流派。行于无形，杀于无声，令对手防不胜防，束手就擒。",
        branches      = { dart = "暗器", shadow = "影步" },
    },
    qidan_sect = {
        display       = "器丹宗",
        short         = "器丹",
        master_title  = "宗主",
        color         = { 255, 160, 50 },   -- 丹火橙色
        intro         = "以丹入道，以器证法，炼丹与炼器双修的绝世流派。器丹宗弟子掌握突破丹药的唯一炼制之法，亦能锻造神兵利器，各门各派竞相结交。",
        branches      = { pill = "炼丹", forge = "炼器" },
    },
}

-- ============================================================================
-- 域外战场层数配置（进入限制 + 描述）
-- ============================================================================
-- 拜师试炼配置
-- ============================================================================
Settings.SECT_TRIAL = {
    -- 奖励潜能（约等于筑基一层离线挂机4小时）
    REWARD_POTENTIAL = 5000,

    -- 各门派试炼任务定义
    QUESTS = {
        sword_sect = {
            npc_id   = "sword_trial_npc",
            name     = "剑宗试炼·斩妖",
            desc     = "在域外战场第二层击败5只混沌山贼，证明你的剑道之心。",
            type     = "kill",            -- 击杀类
            target   = "bf_bandit",       -- 目标怪物id
            count    = 5,                 -- 需要击杀数
            accept_msg = "执事肃然道：「欲入剑宗，须以实力证道。前往域外战场第二层，斩杀五名混沌山贼，方可入门。」",
            complete_msg = "执事微微点头：「剑心已现，果然是可造之材。这是宗门给予的潜能奖励，望你好生修炼。」",
        },
        iron_sect = {
            npc_id   = "iron_trial_npc",
            name     = "铁壁试炼·坚守",
            desc     = "在域外战场通过第2层，证明你坚韧不屈的体魄。",
            type     = "battlefield",     -- 战场层数类
            target_layer = 2,             -- 需通过的层数
            accept_msg = "执事沉声道：「铁壁宗以坚不可摧立世。前往域外战场，通过第二层试炼，证明你的铁骨铮铮。」",
            complete_msg = "执事拍了拍你的肩膀：「好！身如铁壁，心如磐石，正是我宗所需之材。收好这份潜能。」",
        },
        medicine_sect = {
            npc_id   = "medicine_trial_npc",
            name     = "药谷试炼·采药",
            desc     = "收集5株青灵草交给执事，证明你对草药的了解。",
            type     = "collect",         -- 收集上交类
            target   = "herb_green",      -- 目标材料id
            count    = 5,                 -- 需要数量
            accept_msg = "执事温言道：「药王谷以草木为友，灵药为伴。为我收集五株青灵草，以证你与草木的缘分。」",
            complete_msg = "执事接过草药，满意点头：「对草药的感知如此敏锐，当属天赋异禀。收好奖励，望你精进。」",
        },
        shadow_sect = {
            npc_id   = "shadow_trial_npc",
            name     = "天影试炼·潜行",
            desc     = "前往扬州城客栈，再返回天影楼大厅复命，证明你的速度与隐匿。",
            type     = "travel",          -- 前往地点类
            target_scene = "main_city",   -- 目标场景
            target_spot  = "inn",         -- 目标spot
            accept_msg = "执事低语道：「天影楼以速度立世，以无声胜有声。去扬州城客栈，再回来复命。证明你的身手敏捷。」",
            complete_msg = "执事嘴角微扬：「来去无踪，不错。天影楼的影子中，或许有你一席之地。」",
        },
        qidan_sect = {
            npc_id   = "qidan_trial_npc",
            name     = "器丹试炼·锻造",
            desc     = "锻造一把玄铁剑交给执事，证明你的炼器天赋。",
            type     = "forge",           -- 锻造上交类
            target   = "forge_sword_1",   -- 目标锻造配方id（玄铁剑）
            count    = 1,
            accept_msg = "执事抚须道：「器丹宗以丹器双绝立世。为我锻造一把玄铁剑，以证你对器术的领悟。」",
            complete_msg = "执事接过剑，仔细端详：「火候得当，锻纹清晰。你有炼器之才，收好这份奖励。」",
        },
    },
}

-- ============================================================================
Settings.BATTLEFIELD_LAYERS = {
    [1]  = { min_realm = 1, min_layer = 1,  name = "第一层·灵兽荒原",   desc = "低阶灵兽出没，适合练气期修士历练。" },
    [2]  = { min_realm = 1, min_layer = 6,  name = "第二层·妖灵谷",     desc = "妖灵盘踞之地，需有一定修为方可进入。" },
    [3]  = { min_realm = 2, min_layer = 1,  name = "第三层·灵脉福地",   desc = "灵气汇聚之地，可建设帮会基地。", is_guild_zone = true, guild_bonus = 1.2 },
    [4]  = { min_realm = 2, min_layer = 6,  name = "第四层·暗影深林",   desc = "林中暗影重重，危机四伏。" },
    [5]  = { min_realm = 3, min_layer = 1,  name = "第五层·熔岩炼狱",   desc = "炽热熔岩遍地，火属灵兽横行。" },
    [6]  = { min_realm = 3, min_layer = 8,  name = "第六层·雷霆峡谷",   desc = "雷电交加之地，天材地宝时有出现。" },
    [7]  = { min_realm = 4, min_layer = 1,  name = "第七层·虚空裂缝",   desc = "空间不稳，异界妖魔入侵之地。" },
    [8]  = { min_realm = 4, min_layer = 10, name = "第八层·仙灵圣域",   desc = "浓郁灵气直冲霄汉，帮会圣地。", is_guild_zone = true, guild_bonus = 1.5 },
    [9]  = { min_realm = 5, min_layer = 1,  name = "第九层·混沌深渊",   desc = "混沌之力弥漫，化神期以上方可存活。" },
    [10] = { min_realm = 6, min_layer = 1,  name = "第十层·天劫禁区",   desc = "天道法则笼罩，仅最强者可踏足。" },
}

-- ============================================================================
-- 帮会系统配置
-- ============================================================================
Settings.GUILD = {
    MAX_MEMBERS         = 5,          -- 帮会基础成员数（1级）
    CREATE_COST_SILVER  = 5000,       -- 创建帮会花费银两
    CREATE_MIN_REALM    = 2,          -- 创建帮会最低境界（筑基）
    NAME_MIN_LEN        = 2,          -- 帮会名最短
    NAME_MAX_LEN        = 8,          -- 帮会名最长
    -- 帮会基地层对应的修炼速度加成
    LAYER_BONUS = {
        [3] = 1.2,   -- 第三层灵脉福地：修炼速度 ×1.2
        [8] = 1.5,   -- 第八层仙灵圣域：修炼速度 ×1.5
    },
    -- 帮会等级系统（等级1~10）
    LEVELS = {
        -- { exp=升级所需总经验, fund=升级所需总资金, max_members, cult_bonus=修炼倍率, combat_bonus=战力加成, silver_bonus=银两加成比例 }
        [1]  = { exp = 0,     fund = 0,     max_members = 5, cult_bonus = 1.0,  combat_bonus = 0,  silver_bonus = 0 },
        [2]  = { exp = 500,   fund = 2000,  max_members = 8, cult_bonus = 1.05, combat_bonus = 2,  silver_bonus = 0.05 },
        [3]  = { exp = 1500,  fund = 5000,  max_members = 12, cult_bonus = 1.10, combat_bonus = 5,  silver_bonus = 0.08 },
        [4]  = { exp = 3000,  fund = 10000, max_members = 16, cult_bonus = 1.15, combat_bonus = 8,  silver_bonus = 0.10 },
        [5]  = { exp = 6000,  fund = 20000, max_members = 20, cult_bonus = 1.20, combat_bonus = 12, silver_bonus = 0.12 },
        [6]  = { exp = 10000, fund = 35000, max_members = 25, cult_bonus = 1.25, combat_bonus = 16, silver_bonus = 0.15 },
        [7]  = { exp = 16000, fund = 55000, max_members = 32, cult_bonus = 1.30, combat_bonus = 20, silver_bonus = 0.18 },
        [8]  = { exp = 25000, fund = 80000, max_members = 40, cult_bonus = 1.35, combat_bonus = 25, silver_bonus = 0.20 },
        [9]  = { exp = 40000, fund = 120000,max_members = 60, cult_bonus = 1.40, combat_bonus = 30, silver_bonus = 0.22 },
        [10] = { exp = 60000, fund = 180000,max_members = 100,cult_bonus = 1.50, combat_bonus = 40, silver_bonus = 0.25 },
    },
    MAX_LEVEL = 10,
    -- 帮会职位系统
    ROLES = {
        LEADER      = "leader",       -- 帮主
        VICE_LEADER = "vice_leader",  -- 副帮主
        ELDER       = "elder",        -- 长老
        MEMBER      = "member",       -- 普通成员
    },
    ROLE_NAMES = {
        leader      = "帮主",
        vice_leader = "副帮主",
        elder       = "长老",
        member      = "成员",
    },
    ROLE_LIMITS = {
        vice_leader = 2,    -- 副帮主最多2人
        elder       = 4,    -- 长老最多4人
    },
    -- 职位权限（true=允许）
    ROLE_PERMS = {
        leader      = { kick = true, invite = true, notice = true, set_role = true, upgrade = true },
        vice_leader = { kick = true, invite = true, notice = true, set_role = false, upgrade = true },
        elder       = { kick = false, invite = true, notice = false, set_role = false, upgrade = false },
        member      = { kick = false, invite = false, notice = false, set_role = false, upgrade = false },
    },
    -- 捐献配置
    DONATE_OPTIONS = {
        { id = "small",  silver = 100,  exp = 10,  contribution = 10,  label = "小额捐献" },
        { id = "medium", silver = 500,  exp = 55,  contribution = 55,  label = "中额捐献" },
        { id = "large",  silver = 2000, exp = 240, contribution = 240, label = "大额捐献" },
    },
    -- 帮会日常任务
    DAILY_TASKS = {
        { id = "donate",    name = "捐献帮会",  desc = "向帮会捐献一次银两", goal = 1, reward_contrib = 20, reward_silver = 50 },
        { id = "cultivate", name = "潜心修炼",  desc = "完成1次打坐修炼", goal = 1, reward_contrib = 15, reward_silver = 30 },
        { id = "kill_mon",  name = "除妖卫道",  desc = "击杀2只妖兽",    goal = 2, reward_contrib = 25, reward_silver = 80 },
        { id = "chat",      name = "帮会交流",  desc = "在帮会频道发言1条消息", goal = 1, reward_contrib = 5, reward_silver = 10 },
    },
}

-- ============================================================================
-- 域外战场 2D 大地图配置（自由移动 + 镜头跟随 + NanoVG 渲染）
-- ============================================================================
-- 每层为一张大地图（比屏幕大），玩家自由点击移动，镜头跟随。
-- 所有同层玩家实时可见，接近怪物触发战斗，帮会层有据点可占领。
Settings.BATTLEFIELD_MAP = {
    MAP_WIDTH  = 1600,   -- 逻辑地图宽度（像素）
    MAP_HEIGHT = 1200,   -- 逻辑地图高度（像素）
    MOVE_SPEED = 120,    -- 玩家移动速度（像素/秒）
    MONSTER_TRIGGER_RADIUS = 35,   -- 接近怪物触发战斗的距离
    STRONGPOINT_INTERACT_RADIUS = 50, -- 据点交互距离
    SYNC_INTERVAL = 0.2, -- 位置同步频率（秒）
    PLAYER_RADIUS = 8,   -- 玩家圆点半径

    -- ─── 怪物系统参数（服务端驱动）───
    MONSTER_MAX_PER_LAYER   = 20,   -- 每层最大同时存活怪物数
    MONSTER_RESPAWN_DELAY   = 6.0,  -- 击杀后刷新延迟（秒）
    MONSTER_MOVE_SPEED      = 80,   -- 怪物移动速度（像素/秒）
    MONSTER_PATROL_RADIUS   = 120,  -- 巡逻范围半径（围绕出生点）
    MONSTER_PATROL_PAUSE    = {0.8, 1.8}, -- 巡逻停顿时间范围（秒）
    MONSTER_SYNC_INTERVAL   = 0.3,  -- 怪物位置广播间隔（秒）
    MONSTER_SAFE_SPAWN_DIST = 150,  -- 刷怪时离玩家的最小安全距离

    -- ─── 每层地图数据 ───
    [1] = {
        spawn = { x = 800, y = 1000 },
        theme = "wasteland",  -- 荒原主题
        decor = {
            { type = "tree", x = 150, y = 200 }, { type = "tree", x = 200, y = 280 },
            { type = "tree", x = 400, y = 150 }, { type = "tree", x = 650, y = 300 },
            { type = "rock", x = 1000, y = 180 }, { type = "rock", x = 1300, y = 400 },
            { type = "tree", x = 1100, y = 700 }, { type = "tree", x = 300, y = 800 },
            { type = "rock", x = 500, y = 600 }, { type = "tree", x = 900, y = 500 },
            { type = "bush", x = 700, y = 900 }, { type = "bush", x = 1200, y = 850 },
            { type = "tree", x = 1400, y = 200 }, { type = "rock", x = 200, y = 1050 },
        },
        monsters = {},  -- 旧静态列表已废弃，由刷怪区动态生成
        -- 刷怪区：每区会持续生成 count 只怪物
        spawnZones = {
            { cx = 400,  cy = 300,  radius = 140, monId = "bf_wolf", count = 4 },
            { cx = 1100, cy = 350,  radius = 130, monId = "bf_wolf", count = 4 },
            { cx = 300,  cy = 700,  radius = 120, monId = "bf_imp",  count = 4 },
            { cx = 1300, cy = 700,  radius = 130, monId = "bf_imp",  count = 4 },
            { cx = 750,  cy = 500,  radius = 150, monId = "bf_wolf", count = 4 },
        },
    },
    [2] = {
        spawn = { x = 800, y = 1000 },
        theme = "valley",  -- 妖灵谷
        decor = {
            { type = "tree", x = 100, y = 150 }, { type = "tree", x = 350, y = 200 },
            { type = "rock", x = 600, y = 100 }, { type = "tree", x = 900, y = 250 },
            { type = "rock", x = 1200, y = 350 }, { type = "tree", x = 1400, y = 500 },
            { type = "bush", x = 250, y = 600 }, { type = "tree", x = 700, y = 750 },
            { type = "rock", x = 1050, y = 900 }, { type = "tree", x = 400, y = 950 },
        },
        monsters = {},  -- 旧静态列表已废弃
        spawnZones = {
            { cx = 350,  cy = 300,  radius = 130, monId = "bf_bandit", count = 5 },
            { cx = 1200, cy = 450,  radius = 140, monId = "bf_bandit", count = 5 },
            { cx = 600,  cy = 700,  radius = 130, monId = "bf_bear",   count = 5 },
            { cx = 1000, cy = 250,  radius = 120, monId = "bf_bear",   count = 5 },
        },
    },
    [3] = {
        spawn = { x = 800, y = 1000 },
        theme = "spirit",  -- 灵脉福地（帮会层）
        decor = {
            { type = "tree", x = 200, y = 200 }, { type = "tree", x = 400, y = 350 },
            { type = "tree", x = 1000, y = 250 }, { type = "tree", x = 1300, y = 400 },
            { type = "rock", x = 600, y = 600 }, { type = "tree", x = 300, y = 900 },
            { type = "tree", x = 1100, y = 800 }, { type = "bush", x = 900, y = 1050 },
        },
        monsters = {},  -- 帮会福地无怪
        strongpoints = {
            { id = "sp3_01", x = 250,  y = 200 },
            { id = "sp3_02", x = 700,  y = 150 },
            { id = "sp3_03", x = 1150, y = 200 },
            { id = "sp3_04", x = 250,  y = 550 },
            { id = "sp3_05", x = 700,  y = 500 },
            { id = "sp3_06", x = 1150, y = 550 },
            { id = "sp3_07", x = 250,  y = 850 },
            { id = "sp3_08", x = 700,  y = 800 },
            { id = "sp3_09", x = 1150, y = 850 },
            { id = "sp3_10", x = 450,  y = 350 },
            { id = "sp3_11", x = 950,  y = 350 },
            { id = "sp3_12", x = 450,  y = 700 },
        },
    },
    [4] = {
        spawn = { x = 800, y = 1000 },
        theme = "shadow",  -- 暗影深林
        decor = {
            { type = "tree", x = 100, y = 100 }, { type = "tree", x = 250, y = 300 },
            { type = "tree", x = 500, y = 200 }, { type = "tree", x = 750, y = 400 },
            { type = "tree", x = 1000, y = 150 }, { type = "tree", x = 1250, y = 350 },
            { type = "tree", x = 350, y = 700 }, { type = "tree", x = 800, y = 800 },
            { type = "tree", x = 1100, y = 650 }, { type = "tree", x = 600, y = 500 },
            { type = "tree", x = 150, y = 900 }, { type = "tree", x = 1350, y = 900 },
        },
        monsters = {},  -- 旧静态列表已废弃
        spawnZones = {
            { cx = 300,  cy = 300,  radius = 130, monId = "bf_demon",   count = 4 },
            { cx = 900,  cy = 400,  radius = 140, monId = "bf_demon",   count = 4 },
            { cx = 1200, cy = 300,  radius = 120, monId = "bf_specter", count = 4 },
            { cx = 500,  cy = 700,  radius = 130, monId = "bf_specter", count = 4 },
            { cx = 800,  cy = 600,  radius = 140, monId = "bf_demon",   count = 4 },
        },
    },
    [5] = {
        spawn = { x = 800, y = 1000 },
        theme = "lava",  -- 熔岩炼狱
        decor = {
            { type = "rock", x = 200, y = 200 }, { type = "rock", x = 500, y = 150 },
            { type = "rock", x = 900, y = 300 }, { type = "rock", x = 1200, y = 200 },
            { type = "rock", x = 350, y = 600 }, { type = "rock", x = 700, y = 500 },
            { type = "rock", x = 1050, y = 700 }, { type = "rock", x = 1400, y = 550 },
        },
        monsters = {},  -- 旧静态列表已废弃
        spawnZones = {
            { cx = 400,  cy = 300,  radius = 130, monId = "bf_serpent", count = 5 },
            { cx = 1000, cy = 250,  radius = 120, monId = "bf_serpent", count = 5 },
            { cx = 600,  cy = 600,  radius = 140, monId = "bf_golem",   count = 5 },
            { cx = 1200, cy = 650,  radius = 130, monId = "bf_golem",   count = 5 },
        },
    },
    [6] = {
        spawn = { x = 800, y = 1000 },
        theme = "thunder",  -- 雷霆峡谷
        decor = {
            { type = "rock", x = 150, y = 250 }, { type = "rock", x = 450, y = 100 },
            { type = "rock", x = 800, y = 350 }, { type = "rock", x = 1100, y = 200 },
            { type = "rock", x = 300, y = 700 }, { type = "rock", x = 1300, y = 600 },
            { type = "bush", x = 600, y = 850 }, { type = "bush", x = 1000, y = 950 },
        },
        monsters = {},  -- 旧静态列表已废弃
        spawnZones = {
            { cx = 300,  cy = 250,  radius = 130, monId = "bf_phoenix", count = 4 },
            { cx = 800,  cy = 400,  radius = 140, monId = "bf_phoenix", count = 4 },
            { cx = 1200, cy = 300,  radius = 120, monId = "bf_frost",   count = 4 },
            { cx = 500,  cy = 700,  radius = 130, monId = "bf_frost",   count = 4 },
            { cx = 1100, cy = 750,  radius = 130, monId = "bf_phoenix", count = 4 },
        },
    },
    [7] = {
        spawn = { x = 800, y = 1000 },
        theme = "void",  -- 虚空裂缝
        decor = {
            { type = "rock", x = 200, y = 200 }, { type = "rock", x = 600, y = 300 },
            { type = "rock", x = 1000, y = 150 }, { type = "rock", x = 1400, y = 400 },
            { type = "rock", x = 350, y = 650 }, { type = "rock", x = 900, y = 800 },
        },
        monsters = {},  -- 旧静态列表已废弃
        spawnZones = {
            { cx = 400,  cy = 300,  radius = 130, monId = "bf_dragon", count = 4 },
            { cx = 1000, cy = 400,  radius = 140, monId = "bf_dragon", count = 4 },
            { cx = 700,  cy = 200,  radius = 120, monId = "bf_titan",  count = 4 },
            { cx = 1300, cy = 600,  radius = 130, monId = "bf_titan",  count = 4 },
            { cx = 600,  cy = 750,  radius = 130, monId = "bf_dragon", count = 4 },
        },
    },
    [8] = {
        spawn = { x = 800, y = 1000 },
        theme = "celestial",  -- 仙灵圣域（帮会层）
        decor = {
            { type = "tree", x = 200, y = 250 }, { type = "tree", x = 500, y = 150 },
            { type = "tree", x = 900, y = 300 }, { type = "tree", x = 1300, y = 200 },
            { type = "bush", x = 400, y = 700 }, { type = "bush", x = 1100, y = 600 },
        },
        monsters = {},  -- 帮会圣域无怪
        strongpoints = {
            { id = "sp8_01", x = 250,  y = 200 },
            { id = "sp8_02", x = 700,  y = 150 },
            { id = "sp8_03", x = 1150, y = 200 },
            { id = "sp8_04", x = 250,  y = 550 },
            { id = "sp8_05", x = 700,  y = 500 },
            { id = "sp8_06", x = 1150, y = 550 },
            { id = "sp8_07", x = 250,  y = 850 },
            { id = "sp8_08", x = 700,  y = 800 },
            { id = "sp8_09", x = 1150, y = 850 },
            { id = "sp8_10", x = 450,  y = 350 },
            { id = "sp8_11", x = 950,  y = 350 },
            { id = "sp8_12", x = 450,  y = 700 },
        },
    },
    [9] = {
        spawn = { x = 800, y = 1000 },
        theme = "chaos",  -- 混沌深渊
        decor = {
            { type = "rock", x = 300, y = 200 }, { type = "rock", x = 700, y = 350 },
            { type = "rock", x = 1100, y = 200 }, { type = "rock", x = 500, y = 800 },
            { type = "rock", x = 1300, y = 700 },
        },
        monsters = {},  -- 由刷怪区动态生成
        spawnZones = {
            { cx = 400,  cy = 300,  radius = 130, monId = "bf_archfiend", count = 4 },
            { cx = 1100, cy = 350,  radius = 130, monId = "bf_archfiend", count = 4 },
            { cx = 500,  cy = 700,  radius = 130, monId = "bf_voidbeast", count = 4 },
            { cx = 1200, cy = 600,  radius = 130, monId = "bf_voidbeast", count = 4 },
        },
    },
    [10] = {
        spawn = { x = 800, y = 1000 },
        theme = "tribulation",  -- 天劫禁区
        decor = {
            { type = "rock", x = 400, y = 200 }, { type = "rock", x = 800, y = 300 },
            { type = "rock", x = 1200, y = 250 }, { type = "rock", x = 600, y = 700 },
            { type = "rock", x = 1000, y = 800 },
        },
        monsters = {},  -- 由刷怪区动态生成
        spawnZones = {
            { cx = 450,  cy = 300,  radius = 140, monId = "bf_calamity", count = 5 },
            { cx = 1100, cy = 350,  radius = 130, monId = "bf_calamity", count = 5 },
            { cx = 700,  cy = 700,  radius = 140, monId = "bf_calamity", count = 5 },
        },
    },
}

-- ============================================================================
-- 领地战据点配置（帮会领地层专用）
-- ============================================================================
-- 加成类型常量
Settings.STRONGPOINT_BONUS_TYPE = {
    OFFLINE_POTENTIAL = "offline_potential",  -- 离线潜能加成
    CULTIVATE_EXP     = "cultivate_exp",     -- 修炼经验加成
    SILVER_INCOME     = "silver_income",     -- 银两收入加成
}

-- 领地战时间段配置
Settings.TERRITORY_WAR = {
    START_HOUR   = 20,    -- 开战时间：20:00
    START_MIN    = 0,
    END_HOUR     = 21,    -- 结束时间：21:00
    END_MIN      = 0,
    DURATION_SEC = 3600,  -- 持续1小时
    -- 1v1 PvP 规则
    PVP_TIMEOUT_SEC     = 120,   -- 单场 PvP 超时（秒）
    DEFENDER_REVIVE_SEC = 30,    -- 防守方被击败后复活时间
    -- 攻占规则
    FREE_CAPTURE_SEC    = 10,    -- 无人防守时占领倒计时（秒）
}

-- 第三层据点定义（灵脉福地，12个据点）
Settings.STRONGPOINTS_LAYER3 = {
    { id = "sp3_01", name = "灵泉秘境",   bonus_type = "offline_potential", bonus_value = 0.15, desc = "离线潜能+15%" },
    { id = "sp3_02", name = "聚灵台",     bonus_type = "cultivate_exp",     bonus_value = 0.10, desc = "修炼经验+10%" },
    { id = "sp3_03", name = "银矿脉",     bonus_type = "silver_income",     bonus_value = 0.12, desc = "银两收入+12%" },
    { id = "sp3_04", name = "灵药园",     bonus_type = "offline_potential", bonus_value = 0.10, desc = "离线潜能+10%" },
    { id = "sp3_05", name = "修炼洞府",   bonus_type = "cultivate_exp",     bonus_value = 0.15, desc = "修炼经验+15%" },
    { id = "sp3_06", name = "金银矿洞",   bonus_type = "silver_income",     bonus_value = 0.18, desc = "银两收入+18%" },
    { id = "sp3_07", name = "灵脉交汇",   bonus_type = "offline_potential", bonus_value = 0.20, desc = "离线潜能+20%" },
    { id = "sp3_08", name = "悟道石",     bonus_type = "cultivate_exp",     bonus_value = 0.12, desc = "修炼经验+12%" },
    { id = "sp3_09", name = "聚宝盆地",   bonus_type = "silver_income",     bonus_value = 0.10, desc = "银两收入+10%" },
    { id = "sp3_10", name = "灵风谷",     bonus_type = "offline_potential", bonus_value = 0.12, desc = "离线潜能+12%" },
    { id = "sp3_11", name = "天机阁",     bonus_type = "cultivate_exp",     bonus_value = 0.20, desc = "修炼经验+20%" },
    { id = "sp3_12", name = "财神殿",     bonus_type = "silver_income",     bonus_value = 0.15, desc = "银两收入+15%" },
}

-- 第八层据点定义（仙灵圣域，12个据点，加成更高）
Settings.STRONGPOINTS_LAYER8 = {
    { id = "sp8_01", name = "仙灵泉眼",   bonus_type = "offline_potential", bonus_value = 0.25, desc = "离线潜能+25%" },
    { id = "sp8_02", name = "天道祭坛",   bonus_type = "cultivate_exp",     bonus_value = 0.20, desc = "修炼经验+20%" },
    { id = "sp8_03", name = "龙脉银矿",   bonus_type = "silver_income",     bonus_value = 0.22, desc = "银两收入+22%" },
    { id = "sp8_04", name = "太虚幻境",   bonus_type = "offline_potential", bonus_value = 0.20, desc = "离线潜能+20%" },
    { id = "sp8_05", name = "圣灵道场",   bonus_type = "cultivate_exp",     bonus_value = 0.25, desc = "修炼经验+25%" },
    { id = "sp8_06", name = "万宝金殿",   bonus_type = "silver_income",     bonus_value = 0.30, desc = "银两收入+30%" },
    { id = "sp8_07", name = "混沌灵池",   bonus_type = "offline_potential", bonus_value = 0.30, desc = "离线潜能+30%" },
    { id = "sp8_08", name = "悟道天梯",   bonus_type = "cultivate_exp",     bonus_value = 0.18, desc = "修炼经验+18%" },
    { id = "sp8_09", name = "藏金阁",     bonus_type = "silver_income",     bonus_value = 0.20, desc = "银两收入+20%" },
    { id = "sp8_10", name = "永恒灵泉",   bonus_type = "offline_potential", bonus_value = 0.18, desc = "离线潜能+18%" },
    { id = "sp8_11", name = "天元道殿",   bonus_type = "cultivate_exp",     bonus_value = 0.30, desc = "修炼经验+30%" },
    { id = "sp8_12", name = "圣域金库",   bonus_type = "silver_income",     bonus_value = 0.25, desc = "银两收入+25%" },
}

-- 据点层索引（方便按层查找）
Settings.STRONGPOINTS_BY_LAYER = {
    [3] = Settings.STRONGPOINTS_LAYER3,
    [8] = Settings.STRONGPOINTS_LAYER8,
}

-- ============================================================================
-- 炼器配方（器丹宗·炼器分支）
-- ============================================================================
Settings.FORGE_RECIPES = {
    -- 武器
    forge_sword_1 = {
        name = "玄铁剑", slot = "weapon", quality = 2,
        min_skill_level = 1,
        materials = { { id = "ore_copper", count = 3 }, { id = "ore_iron", count = 2 } },
        stats = { atk = 12 },
        success_rate = 0.85, exp_gain = 10, time = 10,
    },
    forge_sword_2 = {
        name = "秘银长剑", slot = "weapon", quality = 3,
        min_skill_level = 2,
        materials = { { id = "ore_iron", count = 3 }, { id = "ore_mithril", count = 2 } },
        stats = { atk = 25 },
        success_rate = 0.70, exp_gain = 25, time = 20,
    },
    forge_sword_3 = {
        name = "陨星重剑", slot = "weapon", quality = 4,
        min_skill_level = 4,
        materials = { { id = "ore_mithril", count = 2 }, { id = "ore_starfall", count = 3 } },
        stats = { atk = 50 },
        success_rate = 0.50, exp_gain = 60, time = 35,
    },
    forge_sword_4 = {
        name = "天晶神剑", slot = "weapon", quality = 5,
        min_skill_level = 5,
        materials = { { id = "ore_starfall", count = 3 }, { id = "ore_celestial", count = 2 } },
        stats = { atk = 90 },
        success_rate = 0.30, exp_gain = 120, time = 60,
    },
    -- 防具（衣服）
    forge_armor_1 = {
        name = "玄铁甲", slot = "armor", quality = 2,
        min_skill_level = 1,
        materials = { { id = "ore_copper", count = 2 }, { id = "ore_iron", count = 3 } },
        stats = { def = 10 },
        success_rate = 0.85, exp_gain = 10, time = 10,
    },
    forge_armor_2 = {
        name = "暗钢战甲", slot = "armor", quality = 3,
        min_skill_level = 2,
        materials = { { id = "ore_iron", count = 2 }, { id = "ore_darksteel", count = 3 } },
        stats = { def = 22 },
        success_rate = 0.70, exp_gain = 25, time = 20,
    },
    forge_armor_3 = {
        name = "陨星灵甲", slot = "armor", quality = 4,
        min_skill_level = 4,
        materials = { { id = "ore_darksteel", count = 2 }, { id = "ore_starfall", count = 3 } },
        stats = { def = 45 },
        success_rate = 0.50, exp_gain = 60, time = 35,
    },
    -- 鞋子
    forge_boots_1 = {
        name = "银灵靴", slot = "boots", quality = 2,
        min_skill_level = 1,
        materials = { { id = "ore_copper", count = 2 }, { id = "ore_silver", count = 2 } },
        stats = { def = 5, agi = 5 },
        success_rate = 0.85, exp_gain = 10, time = 8,
    },
    forge_boots_2 = {
        name = "秘银疾风靴", slot = "boots", quality = 3,
        min_skill_level = 3,
        materials = { { id = "ore_silver", count = 3 }, { id = "ore_mithril", count = 2 } },
        stats = { def = 12, agi = 12 },
        success_rate = 0.65, exp_gain = 30, time = 20,
    },
    -- 饰品
    forge_ring_1 = {
        name = "灵铜戒", slot = "ring", quality = 2,
        min_skill_level = 1,
        materials = { { id = "ore_copper", count = 4 }, { id = "catalyst_crystal", count = 1 } },
        stats = { atk = 5, def = 5 },
        success_rate = 0.80, exp_gain = 12, time = 10,
    },
    forge_ring_2 = {
        name = "暗钢指环", slot = "ring", quality = 3,
        min_skill_level = 3,
        materials = { { id = "ore_darksteel", count = 3 }, { id = "ore_starfall", count = 1 } },
        stats = { atk = 12, def = 12 },
        success_rate = 0.60, exp_gain = 35, time = 25,
    },
}

-- ============================================================================
-- 网络事件名（新增）
-- ============================================================================
Settings.EVENTS = Settings.EVENTS or {}
Settings.EVENTS.REQ_ENTER_LAYER     = "ReqEnterLayer"      -- 请求进入域外战场某层
Settings.EVENTS.RES_ENTER_LAYER     = "ResEnterLayer"      -- 进入层结果
Settings.EVENTS.REQ_CREATE_GUILD    = "ReqCreateGuild"     -- 请求创建帮会
Settings.EVENTS.RES_CREATE_GUILD    = "ResCreateGuild"     -- 创建帮会结果
Settings.EVENTS.REQ_GUILD_INFO      = "ReqGuildInfo"       -- 请求帮会信息
Settings.EVENTS.RES_GUILD_INFO      = "ResGuildInfo"       -- 帮会信息返回
Settings.EVENTS.REQ_JOIN_GUILD      = "ReqJoinGuild"       -- 请求加入帮会
Settings.EVENTS.RES_JOIN_GUILD      = "ResJoinGuild"       -- 加入帮会结果
Settings.EVENTS.REQ_LEAVE_GUILD     = "ReqLeaveGuild"     -- 请求退出帮会
Settings.EVENTS.RES_LEAVE_GUILD     = "ResLeaveGuild"     -- 退出帮会结果
Settings.EVENTS.REQ_SET_GUILD_NOTICE = "ReqSetGuildNotice" -- 帮主设置公告
Settings.EVENTS.RES_SET_GUILD_NOTICE = "ResSetGuildNotice" -- 设置公告结果
Settings.EVENTS.REQ_GUILD_LIST       = "ReqGuildList"       -- 请求帮会列表
Settings.EVENTS.RES_GUILD_LIST       = "ResGuildList"       -- 帮会列表结果
Settings.EVENTS.REQ_KICK_MEMBER      = "ReqKickMember"     -- 帮主踢人
Settings.EVENTS.RES_KICK_MEMBER      = "ResKickMember"     -- 踢人结果
Settings.EVENTS.REQ_TRANSFER_LEADER  = "ReqTransferLeader" -- 转让帮主
Settings.EVENTS.RES_TRANSFER_LEADER  = "ResTransferLeader" -- 转让帮主结果
Settings.EVENTS.NOTIFY_GUILD_ONLINE  = "NotifyGuildOnline"  -- 帮会成员上下线通知
-- 帮会深度玩法事件
Settings.EVENTS.REQ_GUILD_DONATE     = "ReqGuildDonate"     -- 请求捐献 { OptionId }
Settings.EVENTS.RES_GUILD_DONATE     = "ResGuildDonate"     -- 捐献结果
Settings.EVENTS.REQ_GUILD_UPGRADE    = "ReqGuildUpgrade"    -- 请求帮会升级
Settings.EVENTS.RES_GUILD_UPGRADE    = "ResGuildUpgrade"    -- 升级结果
Settings.EVENTS.REQ_SET_GUILD_ROLE   = "ReqSetGuildRole"   -- 设置成员职位 { TargetUid, Role }
Settings.EVENTS.RES_SET_GUILD_ROLE   = "ResSetGuildRole"   -- 设置职位结果
Settings.EVENTS.REQ_GUILD_DAILY      = "ReqGuildDaily"     -- 请求帮会日常任务信息
Settings.EVENTS.RES_GUILD_DAILY      = "ResGuildDaily"     -- 日常任务信息返回
Settings.EVENTS.REQ_CLAIM_GUILD_TASK = "ReqClaimGuildTask" -- 领取日常任务奖励 { TaskId }
Settings.EVENTS.RES_CLAIM_GUILD_TASK = "ResClaimGuildTask" -- 领取结果
Settings.EVENTS.REQ_FORGE_CRAFT     = "ReqForgeCraft"     -- 请求炼器（旧·器丹宗专属）
Settings.EVENTS.RES_FORGE_CRAFT     = "ResForgeCraft"     -- 炼器结果（旧）
-- 新炼器系统（所有门派可用）
Settings.EVENTS.REQ_BUY_BLUEPRINT   = "ReqBuyBlueprint"   -- 购买图纸 { BlueprintId }
Settings.EVENTS.RES_BUY_BLUEPRINT   = "ResBuyBlueprint"   -- 购买图纸结果 { Success, Msg, BlueprintId }
Settings.EVENTS.REQ_FORGE_NEW       = "ReqForgeNew"       -- 新炼器 { BlueprintId, Count }
Settings.EVENTS.RES_FORGE_NEW       = "ResForgeNew"       -- 新炼器结果 { Success, Msg, Items(json) }
Settings.EVENTS.REQ_BLUEPRINT_LIST  = "ReqBlueprintList"  -- 请求可购买图纸列表
Settings.EVENTS.RES_BLUEPRINT_LIST  = "ResBlueprintList"  -- 返回图纸列表 { DataJson }
-- 领地战相关事件
Settings.EVENTS.REQ_STRONGPOINT_LIST = "ReqStrongpointList" -- 请求据点列表（含归属）
Settings.EVENTS.RES_STRONGPOINT_LIST = "ResStrongpointList" -- 据点列表返回
Settings.EVENTS.REQ_ATTACK_STRONGPOINT = "ReqAttackStrongpoint" -- 请求攻击据点（新占领）
Settings.EVENTS.RES_ATTACK_STRONGPOINT = "ResAttackStrongpoint" -- 攻击据点结果
Settings.EVENTS.REQ_SWITCH_STRONGPOINT = "ReqSwitchStrongpoint" -- 请求更换据点（已确认）
Settings.EVENTS.RES_SWITCH_STRONGPOINT = "ResSwitchStrongpoint" -- 更换据点结果
Settings.EVENTS.REQ_DEFEND_STRONGPOINT = "ReqDefendStrongpoint" -- 请求防守据点
Settings.EVENTS.RES_DEFEND_STRONGPOINT = "ResDefendStrongpoint" -- 防守据点结果
Settings.EVENTS.NOTIFY_WAR_START    = "NotifyWarStart"     -- 服务端通知：领地战开始
Settings.EVENTS.NOTIFY_WAR_END      = "NotifyWarEnd"       -- 服务端通知：领地战结束
Settings.EVENTS.NOTIFY_UNDER_ATTACK = "NotifyUnderAttack"  -- 服务端通知：据点被攻击
Settings.EVENTS.NOTIFY_SP_CAPTURED  = "NotifySpCaptured"   -- 服务端通知：据点被占领
Settings.EVENTS.REQ_PVP_CHALLENGE   = "ReqPvpChallenge"    -- 请求向指定防守者发起1v1
Settings.EVENTS.RES_PVP_CHALLENGE   = "ResPvpChallenge"    -- 1v1挑战结果

-- 域外战场大地图·位置同步事件
Settings.EVENTS.REQ_MAP_MOVE        = "ReqMapMove"         -- 客户端请求移动 { X, Y }
Settings.EVENTS.NOTIFY_PLAYER_POS   = "NotifyPlayerPos"    -- 广播玩家位置 { Uid, X, Y, Name, Guild }
Settings.EVENTS.NOTIFY_PLAYER_ENTER = "NotifyPlayerEnter"  -- 有人进入本层 { Uid, X, Y, Name, Guild }
Settings.EVENTS.NOTIFY_PLAYER_LEAVE = "NotifyPlayerLeave"  -- 有人离开本层 { Uid }
Settings.EVENTS.RES_LAYER_SNAPSHOT  = "ResLayerSnapshot"   -- 进入层后的快照 { Players, Monsters, Strongpoints }
Settings.EVENTS.NOTIFY_MONSTER_DEAD = "NotifyMonsterDead"  -- 怪物被击杀 { MonsterId }
Settings.EVENTS.NOTIFY_MONSTER_SYNC = "NotifyMonsterSync"  -- 怪物位置批量同步 { Data = "uid|x|y|monId|alive\n..." }
Settings.EVENTS.NOTIFY_MONSTER_SPAWN = "NotifyMonsterSpawn" -- 新怪物刷出 { Uid, X, Y, MonId }
Settings.EVENTS.NOTIFY_BATTLE_TRIGGER = "NotifyBattleTrigger" -- 服务端判定玩家触发战斗 { MonsterUid, MonsterId }

-- 任务/Boss 系统事件
Settings.EVENTS.PUSH_QUEST_UPDATE   = "PushQuestUpdate"     -- 推送当前目标变更
Settings.EVENTS.PUSH_QUEST_COMPLETE = "PushQuestComplete"   -- 推送 Boss 击杀/目标完成
Settings.EVENTS.REQ_QUEST_INFO      = "ReqQuestInfo"        -- 请求当前目标信息
Settings.EVENTS.RES_QUEST_INFO      = "ResQuestInfo"        -- 返回当前目标信息
Settings.EVENTS.REQ_CHALLENGE_BOSS  = "ReqChallengeBoss"    -- 请求挑战 Boss { BossId }
Settings.EVENTS.REQ_CLAIM_DAILY     = "ReqClaimDaily"       -- 请求领取日常奖励 { QuestId }
Settings.EVENTS.REQ_QUEST_INFO_REQ  = "ReqQuestInfoReq"     -- 客户端主动请求任务面板数据

-- 活动系统扩展事件
Settings.EVENTS.REQ_CLAIM_ACHIEVEMENT = "ReqClaimAchievement" -- 领取成就奖励 { AchId }
Settings.EVENTS.PUSH_ACHIEVEMENTS     = "PushAchievements"    -- 推送成就状态 { DataJson }
Settings.EVENTS.REQ_WEEKLY_INFO       = "ReqWeeklyInfo"       -- 请求周常任务信息
Settings.EVENTS.REQ_CLAIM_WEEKLY      = "ReqClaimWeekly"      -- 领取周常奖励 { QuestId }
Settings.EVENTS.PUSH_WEEKLY_DATA      = "PushWeeklyData"      -- 推送周常状态 { DataJson }
Settings.EVENTS.REQ_PVP_LADDER_INFO   = "ReqPvpLadderInfo"    -- 请求天梯信息
Settings.EVENTS.REQ_PVP_LADDER_MATCH  = "ReqPvpLadderMatch"   -- 请求天梯匹配 {}
Settings.EVENTS.RES_PVP_LADDER_MATCH  = "ResPvpLadderMatch"   -- 天梯匹配结果
Settings.EVENTS.PUSH_PVP_LADDER_DATA  = "PushPvpLadderData"   -- 推送天梯数据 { DataJson }
Settings.EVENTS.PUSH_EVENTS_STATUS    = "PushEventsStatus"    -- 推送当前限时活动状态 { DataJson }

-- 灵石功能事件
Settings.EVENTS.REQ_CULTIVATE_BOOST   = "ReqCultivateBoost"   -- 灵石加速修炼 { SkillId }
Settings.EVENTS.REQ_RENAME            = "ReqRename"           -- 玩家改名 { NewName }
Settings.EVENTS.RES_RENAME            = "ResRename"           -- 改名结果 { Success, NewName, Msg }
Settings.EVENTS.REQ_GUILD_RENAME      = "ReqGuildRename"      -- 帮会改名 { NewName }
Settings.EVENTS.RES_GUILD_RENAME      = "ResGuildRename"      -- 帮会改名结果 { Success, NewName, Msg }
Settings.EVENTS.REQ_TOGGLE_REVIVE     = "ReqToggleRevive"     -- 开关免死 { Enabled }
Settings.EVENTS.REQ_GUILD_BOOST       = "ReqGuildBoost"       -- 帮会加速 {}
Settings.EVENTS.REQ_SKILL_TIER_UP     = "ReqSkillTierUp"     -- 功法升阶 { SkillId }
Settings.EVENTS.RES_SKILL_TIER_UP     = "ResSkillTierUp"     -- 升阶结果 { Success, Msg, SkillId, NewTier }
Settings.EVENTS.REQ_BUY_TITLE        = "ReqBuyTitle"        -- 购买称号 { TitleId }
Settings.EVENTS.REQ_EQUIP_TITLE      = "ReqEquipTitle"      -- 装备称号 { TitleId }
Settings.EVENTS.RES_TITLE_UPDATE     = "ResTitleUpdate"     -- 称号变更结果

-- 角色创建（进入游戏流程）
Settings.EVENTS.REQ_CREATE_CHARACTER  = "ReqCreateCharacter"  -- 创建角色 { Name, Gender, InviteCode }
Settings.EVENTS.RES_CREATE_CHARACTER  = "ResCreateCharacter"  -- 创建结果 { Success, Msg }

-- ============================================================================
-- Boss 门系统配置
-- ============================================================================

-- Boss 定义（域外战场层间关卡）
-- gate_layer: Boss 驻守的层（玩家打通该层后才能挑战）
-- unlocks: 击败后解锁的层列表
-- stats: Boss 战斗属性（与 MONSTERS 格式一致，is_boss=true）
-- recommended_power: 推荐战力（显示用，让玩家感知差距）
-- rewards: 击败奖励
-- wall_desc: 提示文字（告诉玩家需要做什么来变强）
Settings.BOSSES = {
    {
        id          = "boss_1",
        name        = "噬魂蛟",
        title       = "域外第二层·守关",
        desc        = "盘踞在域外深处的上古蛟蛇，灵气狂暴，非寻常练气修士所能抗衡。",
        gate_layer  = 2,
        unlocks     = { 3, 4 },
        is_boss     = true,
        level       = 6,
        hp          = 450,
        atk         = 30,
        def         = 12,
        agi         = 10,
        exp         = 500,
        silver      = 100,
        recommended_power = 150,
        wall_desc   = "提升境界、修炼功法、装备武器后再来挑战",
        rewards     = { spirit_stone = 500, exp = 1000, potential = 3000,
                        items = { { id = "medicine_small_hp", count = 10 } } },
    },
    {
        id          = "boss_2",
        name        = "赤炎魔将",
        title       = "域外第四层·守关",
        desc        = "身披烈焰铠甲的魔界将领，筑基期修士的噩梦。需要扎实的根基与精良装备才能与之一战。",
        gate_layer  = 4,
        unlocks     = { 5, 6 },
        is_boss     = true,
        level       = 11,
        hp          = 1200,
        atk         = 55,
        def         = 25,
        agi         = 14,
        exp         = 5000,
        silver      = 300,
        recommended_power = 380,
        wall_desc   = "筑基三层以上、功法精通二阶、装备精良级以上",
        rewards     = { spirit_stone = 1500, exp = 10000, potential = 8000,
                        items = { { id = "ore_silver", count = 5 } } },
    },
    {
        id          = "boss_3",
        name        = "冰魄天蟒",
        title       = "域外第六层·守关",
        desc        = "寒气凝结成实体的远古巨蟒，所过之处万物冰封。金丹期中段方有一战之力。",
        gate_layer  = 6,
        unlocks     = { 7, 8 },
        is_boss     = true,
        level       = 18,
        hp          = 4000,
        atk         = 120,
        def         = 65,
        agi         = 20,
        exp         = 500000,
        silver      = 600,
        recommended_power = 850,
        wall_desc   = "金丹中期、功法三阶以上、稀有装备",
        rewards     = { spirit_stone = 4000, exp = 1000000, potential = 20000,
                        items = { { id = "ore_mithril", count = 5 }, { id = "catalyst_crystal", count = 3 } } },
    },
    {
        id          = "boss_4",
        name        = "九幽魔龙",
        title       = "域外第八层·守关",
        desc        = "沉睡万年的魔龙苏醒，龙威覆盖方圆百里。唯有元婴巅峰、装备精锐的修士方可一搏。",
        gate_layer  = 8,
        unlocks     = { 9, 10 },
        is_boss     = true,
        level       = 23,
        hp          = 10000,
        atk         = 200,
        def         = 120,
        agi         = 28,
        exp         = 5000000,
        silver      = 1500,
        recommended_power = 1800,
        wall_desc   = "元婴后期、功法四阶、史诗装备",
        rewards     = { spirit_stone = 10000, exp = 10000000, potential = 50000,
                        items = { { id = "ore_starfall", count = 5 }, { id = "catalyst_divine", count = 3 } } },
    },
    {
        id          = "boss_5",
        name        = "天劫真龙",
        title       = "域外第十层·终极",
        desc        = "域外最深处的至强存在，传说中渡劫失败堕落的真龙。击败它意味着你已站在修仙界的巅峰。",
        gate_layer  = 10,
        unlocks     = {},  -- 最终 Boss，无后续解锁
        is_boss     = true,
        level       = 30,
        hp          = 25000,
        atk         = 450,
        def         = 250,
        agi         = 40,
        exp         = 50000000,
        silver      = 5000,
        recommended_power = 4000,
        wall_desc   = "大乘巅峰、功法五阶、传说装备",
        rewards     = { spirit_stone = 30000, exp = 100000000, potential = 100000,
                        items = { { id = "ore_celestial", count = 10 } } },
    },
}

-- Boss 快速索引
Settings.BOSS_MAP = {}          -- [boss_id] = boss_def
Settings.BOSS_BY_LAYER = {}     -- [gate_layer] = boss_def
for i, b in ipairs(Settings.BOSSES) do
    b._index = i
    Settings.BOSS_MAP[b.id] = b
    Settings.BOSS_BY_LAYER[b.gate_layer] = b
end

-- 每层独立守关怪物（完整战斗数据，注册到 BOSS_MAP 供战斗系统使用）
-- 第 3-10 层各有不同的守关妖兽，越深越强
-- 通关建议：挑战层境界 ≥ 该层 min_realm，功法/装备到位
--
-- 层  | 守关怪       | 建议境界        | 推荐战力
-- 3   | 噬魂蛟       | 筑基一层        | 150
-- 4   | 血影狼王     | 筑基三层        | 280
-- 5   | 赤炎魔将     | 金丹一层        | 450
-- 6   | 雷翼凶鹫     | 金丹三层        | 700
-- 7   | 冰魄天蟒     | 元婴一层        | 1000
-- 8   | 幽冥骨龙     | 元婴三层        | 1500
-- 9   | 九幽魔龙     | 化神一层        | 2200
-- 10  | 天劫真龙     | 大乘一层        | 3500
Settings.LAYER_GUARD = {
    [3]  = {
        id = "guard_3", name = "噬魂蛟", is_boss = true,
        title = "第三层·守关", desc = "盘踞灵脉的上古蛟蛇，灵气狂暴。",
        gate_layer = 2, unlocks = { 3 },
        level = 6, hp = 400, atk = 28, def = 10, agi = 9,
        exp = 500, silver = 80, recommended_power = 150,
        wall_desc = "筑基一层、练气功法精通",
        rewards = { spirit_stone = 300, exp = 1000, potential = 2000 },
    },
    [4]  = {
        id = "guard_4", name = "血影狼王", is_boss = true,
        title = "第四层·守关", desc = "统领暗影深林的嗜血狼王，速度极快。",
        gate_layer = 3, unlocks = { 4 },
        level = 9, hp = 700, atk = 40, def = 18, agi = 18,
        exp = 1500, silver = 150, recommended_power = 280,
        wall_desc = "筑基三层、功法二阶",
        rewards = { spirit_stone = 600, exp = 3000, potential = 4000 },
    },
    [5]  = {
        id = "guard_5", name = "赤炎魔将", is_boss = true,
        title = "第五层·守关", desc = "身披烈焰铠甲的魔界将领，攻击力惊人。",
        gate_layer = 4, unlocks = { 5 },
        level = 12, hp = 1200, atk = 60, def = 28, agi = 14,
        exp = 5000, silver = 300, recommended_power = 450,
        wall_desc = "金丹一层、功法二阶、精良装备",
        rewards = { spirit_stone = 1000, exp = 10000, potential = 6000 },
    },
    [6]  = {
        id = "guard_6", name = "雷翼凶鹫", is_boss = true,
        title = "第六层·守关", desc = "翼展十丈的雷属妖禽，雷电缠身刀枪不入。",
        gate_layer = 5, unlocks = { 6 },
        level = 15, hp = 2000, atk = 85, def = 42, agi = 24,
        exp = 50000, silver = 450, recommended_power = 700,
        wall_desc = "金丹三层、功法三阶、精良装备",
        rewards = { spirit_stone = 2000, exp = 100000, potential = 10000 },
    },
    [7]  = {
        id = "guard_7", name = "冰魄天蟒", is_boss = true,
        title = "第七层·守关", desc = "寒气凝实的远古巨蟒，所过之处万物冰封。",
        gate_layer = 6, unlocks = { 7 },
        level = 18, hp = 3500, atk = 120, def = 60, agi = 20,
        exp = 500000, silver = 600, recommended_power = 1000,
        wall_desc = "元婴一层、功法三阶、稀有装备",
        rewards = { spirit_stone = 3500, exp = 1000000, potential = 15000 },
    },
    [8]  = {
        id = "guard_8", name = "幽冥骨龙", is_boss = true,
        title = "第八层·守关", desc = "亡灵之力驱动的远古骨龙，防御极高。",
        gate_layer = 7, unlocks = { 8 },
        level = 21, hp = 6000, atk = 160, def = 100, agi = 22,
        exp = 2000000, silver = 1000, recommended_power = 1500,
        wall_desc = "元婴三层、功法四阶、稀有装备",
        rewards = { spirit_stone = 6000, exp = 5000000, potential = 25000 },
    },
    [9]  = {
        id = "guard_9", name = "九幽魔龙", is_boss = true,
        title = "第九层·守关", desc = "沉睡万年的魔龙苏醒，龙威覆盖方圆百里。",
        gate_layer = 8, unlocks = { 9 },
        level = 25, hp = 12000, atk = 250, def = 150, agi = 30,
        exp = 10000000, silver = 2000, recommended_power = 2200,
        wall_desc = "化神一层、功法四阶、史诗装备",
        rewards = { spirit_stone = 10000, exp = 30000000, potential = 40000 },
    },
    [10] = {
        id = "guard_10", name = "天劫真龙", is_boss = true,
        title = "第十层·终极守关", desc = "域外最深处的至强存在，渡劫失败堕落的真龙。",
        gate_layer = 9, unlocks = { 10 },
        level = 30, hp = 25000, atk = 450, def = 250, agi = 40,
        exp = 50000000, silver = 5000, recommended_power = 3500,
        wall_desc = "大乘一层、功法五阶、传说装备",
        rewards = { spirit_stone = 25000, exp = 100000000, potential = 80000 },
    },
}
-- 注册守关怪到 BOSS_MAP（供战斗系统查找）
for _, guard in pairs(Settings.LAYER_GUARD) do
    Settings.BOSS_MAP[guard.id] = guard
end

-- 域外战场初始解锁层（新玩家默认能进 1-2 层）
Settings.BATTLEFIELD_INITIAL_LAYERS = 2

-- ============================================================================
-- 战力计算公式（用于显示对比，服务端/客户端共用）
-- ============================================================================
Settings.CalcPower = function(stats)
    if not stats then return 0 end
    local hp  = stats.hp  or 0
    local atk = stats.atk or 0
    local def = stats.def or 0
    local agi = stats.agi or 0
    return math.floor(atk * 3 + def * 2 + hp * 0.2 + agi * 1.5)
end

-- Boss 战力值（预计算）
Settings.CalcBossPower = function(boss)
    return Settings.CalcPower({ hp = boss.hp, atk = boss.atk, def = boss.def, agi = boss.agi })
end

-- ============================================================================
-- 任务状态
-- ============================================================================
Settings.QUEST_STATUS = {
    LOCKED      = 0,
    ACTIVE      = 1,
    COMPLETED   = 2,
}

-- ============================================================================
-- 主线任务链
-- ============================================================================
-- trigger 类型:
--   enter_layer(layer)     进入指定层
--   kill_total(n)          累计击杀n只怪物
--   challenge_boss(bossId) 挑战Boss（不需胜）
--   defeat_boss(bossId)    击败Boss
--   join_guild             加入帮会
--   breakthrough           完成一次境界突破
--   kill_in_layers(layers, n) 在指定层击杀n只怪

Settings.MAIN_QUESTS = {
    -- 第一章：初入修仙（→ Boss 1）
    -- 经验设计：确保做完前5个任务时已到练气九重（总需4500经验）
    { id = "mq_1",  chapter = 1, name = "初入域外",   desc = "进入域外战场第1层",
      trigger = "enter_layer", param = 1, goal = 1,
      rewards = { exp = 300, silver = 50 } },
    { id = "mq_2",  chapter = 1, name = "首战告捷",   desc = "击败1只怪物",
      trigger = "kill_total", goal = 1,
      rewards = { exp = 500, silver = 50 } },
    { id = "mq_3",  chapter = 1, name = "小试牛刀",   desc = "累计击败10只怪物",
      trigger = "kill_total", goal = 10,
      rewards = { exp = 1000, potential = 500 } },
    { id = "mq_4",  chapter = 1, name = "知己知彼",   desc = "挑战噬魂蛟1次（不需胜利）",
      trigger = "challenge_boss", param = {"guard_3", "boss_1"}, goal = 1,
      rewards = { exp = 1200, spirit_stone = 5 } },
    { id = "mq_5",  chapter = 1, name = "百战成钢",   desc = "累计击败30只怪物",
      trigger = "kill_total", goal = 30,
      rewards = { exp = 1500, silver = 200 } },
    { id = "mq_6",  chapter = 1, name = "破关之战",   desc = "击败噬魂蛟",
      trigger = "defeat_boss", param = {"guard_3", "boss_1"}, goal = 1,
      rewards = { exp = 1000, spirit_stone = 20 } },

    -- 第二章：崭露头角（→ Boss 2）
    { id = "mq_7",  chapter = 2, name = "新的征程",   desc = "进入域外战场第3层",
      trigger = "enter_layer", param = 3, goal = 1,
      rewards = { exp = 2000 } },
    { id = "mq_8",  chapter = 2, name = "广交好友",   desc = "加入一个帮会",
      trigger = "join_guild", goal = 1,
      rewards = { spirit_stone = 10 } },
    { id = "mq_9",  chapter = 2, name = "深入虎穴",   desc = "在第3/4层击败50只怪物",
      trigger = "kill_in_layers", param = {3, 4}, goal = 50,
      rewards = { silver = 500 } },
    { id = "mq_10", chapter = 2, name = "境界突破",   desc = "完成一次境界突破",
      trigger = "breakthrough", goal = 1,
      rewards = { potential = 2000 } },
    { id = "mq_11", chapter = 2, name = "再攀高峰",   desc = "击败赤炎魔将",
      trigger = "defeat_boss", param = "guard_5", goal = 1,
      rewards = { spirit_stone = 50 } },

    -- 第三章：锋芒初露（→ Boss 3）
    { id = "mq_12", chapter = 3, name = "熔岩试炼",   desc = "进入域外战场第5层",
      trigger = "enter_layer", param = 5, goal = 1,
      rewards = { exp = 50000 } },
    { id = "mq_13", chapter = 3, name = "精锐猎手",   desc = "累计击败200只怪物",
      trigger = "kill_total", goal = 200,
      rewards = { silver = 1000 } },
    { id = "mq_14", chapter = 3, name = "降服炎魔",   desc = "击败冰魄天蟒",
      trigger = "defeat_boss", param = "guard_7", goal = 1,
      rewards = { spirit_stone = 100 } },

    -- 第四章（→ Boss 4）
    { id = "mq_15", chapter = 4, name = "雷霆之境",   desc = "进入域外战场第7层",
      trigger = "enter_layer", param = 7, goal = 1,
      rewards = { exp = 500000 } },
    { id = "mq_16", chapter = 4, name = "千战不殆",   desc = "累计击败500只怪物",
      trigger = "kill_total", goal = 500,
      rewards = { silver = 3000 } },
    { id = "mq_17", chapter = 4, name = "斩灭魔龙",   desc = "击败九幽魔龙",
      trigger = "defeat_boss", param = "guard_9", goal = 1,
      rewards = { spirit_stone = 200 } },

    -- 第五章（→ Boss 5）
    { id = "mq_18", chapter = 5, name = "天劫降临",   desc = "进入域外战场第9层",
      trigger = "enter_layer", param = 9, goal = 1,
      rewards = { exp = 5000000 } },
    { id = "mq_19", chapter = 5, name = "万战归一",   desc = "累计击败1000只怪物",
      trigger = "kill_total", goal = 1000,
      rewards = { silver = 10000 } },
    { id = "mq_20", chapter = 5, name = "终极之战",   desc = "击败天劫真龙",
      trigger = "defeat_boss", param = "guard_10", goal = 1,
      rewards = { spirit_stone = 500 } },
}

-- 主线任务快速索引
Settings.MAIN_QUEST_MAP = {}
for i, q in ipairs(Settings.MAIN_QUESTS) do
    q._index = i
    Settings.MAIN_QUEST_MAP[q.id] = q
end

-- ============================================================================
-- 日常任务配置（每日重置）
-- ============================================================================
Settings.DAILY_QUESTS = {
    { id = "dq_online",   name = "累计在线30分钟", desc = "今日累计在线30分钟",
      trigger = "online_time", goal = 1800, -- 秒
      rewards = { spirit_stone = 5, exp = 100 } },
    { id = "dq_kill",     name = "域外历练",       desc = "今日击败15只怪物",
      trigger = "daily_kill", goal = 15,
      rewards = { silver = 100, exp = 150 } },
    { id = "dq_battle",   name = "精进武学",       desc = "今日进行5场战斗",
      trigger = "daily_battle", goal = 5,
      rewards = { potential = 500, exp = 120 } },
    { id = "dq_win",      name = "百战百胜",       desc = "今日赢得2场战斗",
      trigger = "daily_win", goal = 2,
      rewards = { spirit_stone = 3, exp = 100 } },
    { id = "dq_boss",     name = "向首领挑战",     desc = "今日挑战首领 1次",
      trigger = "daily_boss_challenge", goal = 1,
      rewards = { spirit_stone = 3, exp = 80 } },
}

-- 日常全勤奖励
Settings.DAILY_ALL_COMPLETE_REWARD = { spirit_stone = 10 }

-- ============================================================================
-- 七日签到（循环，断签不重置）
-- ============================================================================
Settings.SIGN_IN = {
    CYCLE_DAYS = 7,
    REWARDS = {
        [1] = { silver = 200,   desc = "银两×200" },
        [2] = { spirit_stone = 5,  desc = "灵石×5" },
        [3] = { potential = 1000, desc = "潜力×1000" },
        [4] = { silver = 500,   desc = "银两×500" },
        [5] = { spirit_stone = 10, desc = "灵石×10" },
        [6] = { potential = 2000, desc = "潜力×2000" },
        [7] = { spirit_stone = 30, items = { { id = "pill_zhuji", count = 1 } }, desc = "灵石×30 + 筑基丹×1" },
    },
}

-- ============================================================================
-- 成就系统
-- ============================================================================
-- ============================================================================
-- 称号系统
-- ============================================================================
Settings.TITLES = {
    -- 成就解锁称号
    { id = "t_killer",    name = "杀神",     color = { 255, 80, 80 },   source = "achievement", req_ach = "ach_kill_2000" },
    { id = "t_boss",      name = "域外至尊", color = { 255, 200, 0 },   source = "achievement", req_ach = "ach_boss_all" },
    { id = "t_rich",      name = "富甲天下", color = { 255, 215, 0 },   source = "achievement", req_ach = "ach_silver_100k" },
    { id = "t_pvp",       name = "武林盟主", color = { 200, 100, 255 }, source = "achievement", req_ach = "ach_pvp_win_20" },
    { id = "t_persist",   name = "铁骨铮铮", color = { 180, 180, 180 }, source = "achievement", req_ach = "ach_fail_50" },
    -- 灵石购买称号
    { id = "t_vip",       name = "贵宾",     color = { 255, 180, 50 },  source = "shop", cost = 50 },
    { id = "t_legend",    name = "传说",     color = { 255, 100, 200 }, source = "shop", cost = 100 },
    { id = "t_immortal",  name = "仙人",     color = { 100, 255, 200 }, source = "shop", cost = 200 },
    { id = "t_dragon",    name = "真龙",     color = { 255, 60, 60 },   source = "shop", cost = 500 },
}

Settings.ACHIEVEMENTS = {
    -- 战斗类
    { id = "ach_kill_100",     name = "初窥门径",   desc = "累计击败100只怪物",    category = "combat",  trigger = "kill_total",     goal = 100,   rewards = { spirit_stone = 10 } },
    { id = "ach_kill_500",     name = "百战老兵",   desc = "累计击败500只怪物",    category = "combat",  trigger = "kill_total",     goal = 500,   rewards = { spirit_stone = 30 } },
    { id = "ach_kill_2000",    name = "杀神降世",   desc = "累计击败2000只怪物",   category = "combat",  trigger = "kill_total",     goal = 2000,  rewards = { spirit_stone = 80 } },
    { id = "ach_kill_10000",   name = "万夫莫当",   desc = "累计击败10000只怪物",  category = "combat",  trigger = "kill_total",     goal = 10000, rewards = { spirit_stone = 200 } },
    { id = "ach_boss_1",       name = "初斩强敌",   desc = "击败第一个首领",       category = "combat",  trigger = "boss_count",     goal = 1,     rewards = { spirit_stone = 20 } },
    { id = "ach_boss_3",       name = "三关斩将",   desc = "击败3个首领",          category = "combat",  trigger = "boss_count",     goal = 3,     rewards = { spirit_stone = 50 } },
    { id = "ach_boss_all",     name = "域外至尊",   desc = "击败全部5个首领",      category = "combat",  trigger = "boss_count",     goal = 5,     rewards = { spirit_stone = 200 } },
    { id = "ach_win_50",       name = "连战皆捷",   desc = "累计赢得50场战斗",     category = "combat",  trigger = "win_total",      goal = 50,    rewards = { potential = 2000 } },
    { id = "ach_win_500",      name = "常胜将军",   desc = "累计赢得500场战斗",    category = "combat",  trigger = "win_total",      goal = 500,   rewards = { spirit_stone = 50 } },

    -- 境界类
    { id = "ach_realm_2",      name = "筑基有成",   desc = "突破到筑基期",         category = "realm",   trigger = "realm_reach",    goal = 2,     rewards = { potential = 1000 } },
    { id = "ach_realm_3",      name = "金丹大道",   desc = "突破到金丹期",         category = "realm",   trigger = "realm_reach",    goal = 3,     rewards = { spirit_stone = 30 } },
    { id = "ach_realm_5",      name = "化神通天",   desc = "突破到化神期",         category = "realm",   trigger = "realm_reach",    goal = 5,     rewards = { spirit_stone = 100 } },
    { id = "ach_realm_7",      name = "渡劫飞升",   desc = "突破到渡劫期",         category = "realm",   trigger = "realm_reach",    goal = 7,     rewards = { spirit_stone = 500 } },
    { id = "ach_fail_10",      name = "屡败屡战",   desc = "突破失败10次",         category = "realm",   trigger = "break_fail",     goal = 10,    rewards = { spirit_stone = 20 } },
    { id = "ach_fail_50",      name = "百折不挠",   desc = "突破失败50次",         category = "realm",   trigger = "break_fail",     goal = 50,    rewards = { spirit_stone = 100 } },

    -- 社交类
    { id = "ach_guild_join",   name = "志同道合",   desc = "加入一个帮会",         category = "social",  trigger = "has_guild",      goal = 1,     rewards = { silver = 500 } },
    { id = "ach_territory_1",  name = "攻城略地",   desc = "帮会占领1个据点",      category = "social",  trigger = "territory_own",  goal = 1,     rewards = { spirit_stone = 30 } },
    { id = "ach_pvp_win_1",    name = "初试锋芒",   desc = "PvP获胜1次",           category = "social",  trigger = "pvp_win",        goal = 1,     rewards = { spirit_stone = 10 } },
    { id = "ach_pvp_win_20",   name = "武林高手",   desc = "PvP获胜20次",          category = "social",  trigger = "pvp_win",        goal = 20,    rewards = { spirit_stone = 50 } },

    -- 经济类
    { id = "ach_silver_10k",   name = "小有积蓄",   desc = "累计获得10000银两",    category = "economy", trigger = "silver_total",   goal = 10000,  rewards = { spirit_stone = 10 } },
    { id = "ach_silver_100k",  name = "富甲一方",   desc = "累计获得100000银两",   category = "economy", trigger = "silver_total",   goal = 100000, rewards = { spirit_stone = 50 } },
    { id = "ach_market_sell",  name = "生意兴隆",   desc = "交易阁卖出10件物品",   category = "economy", trigger = "market_sells",   goal = 10,    rewards = { spirit_stone = 20 } },
    { id = "ach_alchemy_5",    name = "丹道入门",   desc = "炼丹等级达到5",        category = "economy", trigger = "alchemy_level",  goal = 5,     rewards = { spirit_stone = 50 } },
    { id = "ach_forge_5",      name = "锻造大师",   desc = "炼器等级达到5",        category = "economy", trigger = "forge_level",    goal = 5,     rewards = { spirit_stone = 50 } },

    -- 探索类
    { id = "ach_layer_5",      name = "深入域外",   desc = "解锁域外第5层",        category = "explore", trigger = "max_layer",      goal = 5,     rewards = { potential = 3000 } },
    { id = "ach_layer_9",      name = "九层通关",   desc = "解锁域外第9层",        category = "explore", trigger = "max_layer",      goal = 9,     rewards = { spirit_stone = 100 } },
    { id = "ach_skills_5",     name = "博学多才",   desc = "学会5种功法",          category = "explore", trigger = "skill_count",    goal = 5,     rewards = { potential = 2000 } },
    { id = "ach_skills_15",    name = "百家争鸣",   desc = "学会15种功法",         category = "explore", trigger = "skill_count",    goal = 15,    rewards = { spirit_stone = 50 } },
    { id = "ach_signin_7",     name = "风雨无阻",   desc = "累计签到7天",          category = "explore", trigger = "signin_total",   goal = 7,     rewards = { spirit_stone = 10 } },
    { id = "ach_signin_30",    name = "持之以恒",   desc = "累计签到30天",         category = "explore", trigger = "signin_total",   goal = 30,    rewards = { spirit_stone = 50 } },
}

-- 成就快速索引
Settings.ACHIEVEMENT_MAP = {}
for _, a in ipairs(Settings.ACHIEVEMENTS) do
    Settings.ACHIEVEMENT_MAP[a.id] = a
end

-- ============================================================================
-- 周常任务（每周一重置）
-- ============================================================================
Settings.WEEKLY_QUESTS = {
    { id = "wq_kill",     name = "周·域外扫荡",   desc = "本周击败100只怪物",
      trigger = "weekly_kill", goal = 100,
      rewards = { spirit_stone = 20, potential = 3000 } },
    { id = "wq_win",      name = "周·武道精进",   desc = "本周赢得20场战斗",
      trigger = "weekly_win", goal = 20,
      rewards = { spirit_stone = 15 } },
    { id = "wq_boss",     name = "周·斩关夺将",   desc = "本周挑战首领 3次",
      trigger = "weekly_boss", goal = 3,
      rewards = { spirit_stone = 25 } },
    { id = "wq_market",   name = "周·商贾之道",   desc = "本周在交易阁完成3笔交易",
      trigger = "weekly_market", goal = 3,
      rewards = { silver = 1000 } },
    { id = "wq_cultivate",name = "周·闭关苦修",   desc = "本周累计修炼30分钟",
      trigger = "weekly_cultivate", goal = 1800,
      rewards = { potential = 5000 } },
}

-- 周常全勤奖励
Settings.WEEKLY_ALL_COMPLETE_REWARD = { spirit_stone = 30 }

-- ============================================================================
-- PvP 天梯配置
-- ============================================================================
Settings.PVP_LADDER = {
    INITIAL_RATING  = 1000,       -- 初始积分
    K_FACTOR        = 32,         -- ELO K值
    WIN_BONUS       = 10,         -- 胜利固定奖励积分
    LOSE_PENALTY    = 5,          -- 失败固定扣分
    DAILY_ATTEMPTS  = 10,         -- 每日挑战次数上限
    COOLDOWN_SEC    = 60,         -- 两次挑战间隔
    -- 段位定义
    RANKS = {
        { id = "bronze",   name = "青铜", min_rating = 0,    color = {180,120,60} },
        { id = "silver",   name = "白银", min_rating = 1100, color = {192,192,192} },
        { id = "gold",     name = "黄金", min_rating = 1300, color = {255,215,0} },
        { id = "diamond",  name = "钻石", min_rating = 1500, color = {100,200,255} },
        { id = "master",   name = "宗师", min_rating = 1800, color = {200,100,255} },
        { id = "legend",   name = "传说", min_rating = 2200, color = {255,50,50} },
    },
    -- 赛季奖励（按最高到达段位发放）
    SEASON_REWARDS = {
        bronze  = { silver = 500 },
        silver  = { spirit_stone = 20 },
        gold    = { spirit_stone = 50 },
        diamond = { spirit_stone = 100 },
        master  = { spirit_stone = 200 },
        legend  = { spirit_stone = 500 },
    },
    -- 赛季机制
    SEASON = {
        DURATION_DAYS      = 30,             -- 赛季时长（天）
        RESET_FACTOR       = 0.7,            -- 重置时积分保留比例
        RESET_FLOOR        = 1000,           -- 重置后积分下限
        DEMOTION_SHIELD    = 3,              -- 黄金以下掉段保护场数
        DEMOTION_THRESHOLD = "gold",         -- 此段位以下才有掉段保护
    },
}

-- ============================================================================
-- 限时活动框架
-- ============================================================================
Settings.EVENTS_SYSTEM = {
    -- 活动类型定义
    TYPES = {
        DOUBLE_EXP     = "double_exp",       -- 双倍经验
        DOUBLE_DROP    = "double_drop",      -- 双倍掉落
        BOSS_RUSH      = "boss_rush",        -- Boss连战（限时Boss弱化）
        MARKET_FEVER   = "market_fever",     -- 交易狂欢（手续费减半）
        REALM_BOOST    = "realm_boost",      -- 突破率提升
    },
    -- 预设活动模板（服务端按时间激活）
    TEMPLATES = {
        { id = "evt_weekend_exp",   type = "double_exp",   name = "周末双倍经验",
          trigger_rule = "weekend",  -- 每周六日自动激活
          multiplier = 2.0, desc = "所有经验获取×2" },
        { id = "evt_friday_market", type = "market_fever", name = "周五交易狂欢",
          trigger_rule = "friday",   -- 每周五
          multiplier = 0.5, desc = "交易阁手续费减半" },
        { id = "evt_monthly_realm", type = "realm_boost",  name = "月初突破福利",
          trigger_rule = "month_start",  -- 每月1-3号
          multiplier = 1.2, desc = "突破成功率+20%" },
    },
}

return Settings
