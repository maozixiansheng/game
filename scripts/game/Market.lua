-- ============================================================================
-- game/Market.lua - 交易阁逻辑（服务端专用）
-- ============================================================================

local Market = {}
local Shared = require("network.Shared")
local Settings = Shared.Settings

-- ============================================================================
-- 交易阁数据存储（云端）
-- ============================================================================
-- 交易阁数据存储在云端 serverCloud.list
-- key = "market_listings"
-- 每条记录：{ id, seller_uid, seller_name, item, price, listed_at, expires_at }
-- item 结构：{ type="skill"|"equipment", ... }

-- 全局虚拟UID（用于管理员/系统账号）
Market.ADMIN_UID = 0

-- ============================================================================
-- 上架物品
-- ============================================================================
function Market.ListItem(uid, sellerName, item, price, onDone)
    if price <= 0 then
        onDone(false, "价格必须大于0")
        return
    end

    local now = os.time()
    local listing = {
        seller_uid  = uid,
        seller_name = sellerName,
        item        = item,
        price       = price,
        listed_at   = now,
        expires_at  = now + Settings.ECONOMY.MARKET_DURATION,
    }

    serverCloud.list:Add(uid, "market_listings", listing, {
        ok = function(listId)
            print(string.format("[Market] 上架成功 listId=%s seller=%s price=%d", tostring(listId), sellerName, price))
            onDone(true, listId)
        end,
        error = function(code, reason)
            print("[Market] 上架失败:", code, reason)
            onDone(false, "上架失败：" .. (reason or "未知错误"))
        end
    })
end

-- ============================================================================
-- 购买（原子事务）
-- currency: "silver" 或 "spirit_stone"
-- ============================================================================
function Market.BuyItem(buyerUid, buyerName, listingId, sellerUid, sellerName, item, price, currency, onDone, taxDiscount)
    currency = currency or "silver"
    taxDiscount = taxDiscount or 0
    print(string.format("[Market] 购买请求 buyer=%s listing=%s price=%d currency=%s",
        tostring(buyerUid), tostring(listingId), price, currency))

    -- 根据货币选择税率（应用倒爷等级减免）
    local baseTaxRate = (currency == "spirit_stone")
        and Settings.ECONOMY.MARKET_TAX_STONE
        or  Settings.ECONOMY.MARKET_TAX
    local taxRate = math.max(0, baseTaxRate - taxDiscount)
    local tax = math.floor(price * taxRate)
    local sellerReceive = price - tax

    local function fmtPrice(amount)
        if currency == "spirit_stone" then
            return amount .. "灵石"
        end
        return Shared.FormatSilver(amount)
    end

    -- BatchCommit原子事务：扣买家钱 + 删上架条目 + 卖家收钱 + 买家入库
    -- GDD要求购买和入库必须在同一事务中，防止钱扣了但物品未入库
    local c = serverCloud:BatchCommit("交易阁购买")
    c:MoneyCost(buyerUid, currency, price)
    c:ListDelete(listingId)
    -- 卖家不论用哪种货币卖，收款均为同种货币
    c:MoneyAdd(sellerUid, currency, sellerReceive)
    -- 银两商品：原子加银两；普通物品：写入云端库存
    if item.type == "currency" and item.silver_amount then
        c:MoneyAdd(buyerUid, "silver", item.silver_amount)
    else
        c:ListAdd(buyerUid, "inventory", item)
    end
    c:Commit({
        ok = function()
            print(string.format("[Market] 交易成功 buyer=%s 花费%s，seller=%s 收到%s",
                tostring(buyerUid), fmtPrice(price), tostring(sellerUid), fmtPrice(sellerReceive)))

            -- 写入买家交易记录
            local now = os.time()
            local buyRecord = {
                record_type      = "buy",
                item_name        = item.name,
                item_type        = item.type,
                item_quality     = item.quality,
                price            = price,
                currency         = currency,
                counterpart_name = sellerName,
                time             = now,
            }
            serverCloud.list:Add(buyerUid, "trade_history", buyRecord)

            -- 写入卖家交易记录（管理员UID=0 不写，避免无限积累）
            if sellerUid ~= Market.ADMIN_UID then
                local sellRecord = {
                    record_type      = "sell",
                    item_name        = item.name,
                    item_type        = item.type,
                    item_quality     = item.quality,
                    price            = sellerReceive,   -- 卖家实收（扣税后）
                    currency         = currency,
                    counterpart_name = buyerName,
                    time             = now,
                }
                serverCloud.list:Add(sellerUid, "trade_history", sellRecord)
            end

            local successMsg
            if item.type == "currency" and item.silver_amount then
                successMsg = string.format(
                    "购买成功！花费%s（%s手续费），%s已到账",
                    fmtPrice(price), fmtPrice(tax), item.name)
            else
                successMsg = string.format(
                    "购买成功！花费%s（%s手续费），%s已入背包",
                    fmtPrice(price), fmtPrice(tax), item.name)
            end
            onDone(true, item, successMsg)
        end,
        error = function(code, reason)
            print("[Market] 交易失败:", code, reason)
            local errMsg = "购买失败"
            if reason and reason:find("余额不足") then
                if currency == "spirit_stone" then
                    errMsg = string.format("灵石不足，需要%d灵石", price)
                else
                    errMsg = string.format("银两不足，需要%s", Shared.FormatSilver(price))
                end
            elseif reason then
                errMsg = "购买失败：" .. reason
            end
            onDone(false, nil, errMsg)
        end
    })
end

-- ============================================================================
-- 下架（取消上架）
-- ============================================================================
function Market.CancelListing(uid, listingId, onDone)
    serverCloud.list:GetById(listingId, {
        ok = function(items)
            if #items == 0 then
                onDone(false, "商品不存在")
                return
            end
            local listing = items[1].value
            -- 验证是否是本人上架
            if listing.seller_uid ~= uid then
                onDone(false, "这不是你上架的商品")
                return
            end
            serverCloud.list:Delete(listingId, {
                ok = function()
                    onDone(true, listing.item)
                end,
                error = function(code, reason)
                    onDone(false, "下架失败：" .. (reason or "未知"))
                end
            })
        end,
        error = function(code, reason)
            onDone(false, "查询失败：" .. (reason or "未知"))
        end
    })
end

-- ============================================================================
-- 查询交易阁列表
-- ============================================================================
-- 由于serverCloud.list是按uid存储的，管理员的商品用特殊UID
-- 为了实现"全服市场"，我们用一个固定的"market_global"用户存储所有上架

-- 查询所有上架（全服，分页）
-- 注：实际实现中需要遍历所有卖家的list，这里简化为
-- 约定：所有上架都存在管理员uid=0的market_listings list下
-- 卖家信息存在listing的seller_uid字段
-- 这样查询时只需读一个list

-- filterType:    nil/"all" 或 item.type 字符串（"skill"/"equipment"）
-- filterQuality: nil/"all" 或品质索引字符串（"1"/"2"/"3"/"4"/"5"）
-- sortBy:        "time_desc"（默认）/"price_asc"/"price_desc"
function Market.GetListings(filterType, filterQuality, sortBy, page, pageSize, onDone)
    page     = page     or 1
    pageSize = pageSize or 20
    sortBy   = sortBy   or "time_desc"

    serverCloud.list:Get(Market.ADMIN_UID, "market_listings", {
        ok = function(list)
            print("[Market][GetListings] 云端返回 " .. #list .. " 条原始数据")
            if #list > 0 then
                -- 打印前3条的 list_id 类型和值
                for i = 1, math.min(3, #list) do
                    local e = list[i]
                    print(string.format("[Market][GetListings] entry[%d] list_id=%s type=%s", i, tostring(e.list_id), type(e.list_id)))
                end
            end
            local now = os.time()
            local filtered = {}
            for _, entry in ipairs(list) do
                local listing = entry.value
                -- 过滤过期
                if listing.expires_at and listing.expires_at > now then
                    -- 类型过滤
                    local typeOk = (not filterType or filterType == "all" or listing.item.type == filterType)
                    -- 品质过滤（filterQuality 为数字字符串如 "1"-"6" 或 "all"）
                    local qualOk = true
                    if filterQuality and filterQuality ~= "all" and filterQuality ~= "" then
                        local fq = tonumber(filterQuality)
                        qualOk = (fq ~= nil and listing.item.quality == fq)
                    end

                    if typeOk and qualOk then
                        filtered[#filtered + 1] = {
                            listing_id  = tostring(entry.list_id),  -- 字符串传输，防止cjson大整数精度丢失
                            seller_uid  = listing.seller_uid,
                            seller_name = listing.seller_name,
                            item        = listing.item,
                            item_name   = listing.item and listing.item.name or "未知",
                            price       = listing.price,
                            currency    = listing.currency or "silver",
                            listed_at   = listing.listed_at,
                        }
                    end
                end
            end

            -- 排序
            if sortBy == "price_asc" then
                table.sort(filtered, function(a, b) return a.price < b.price end)
            elseif sortBy == "price_desc" then
                table.sort(filtered, function(a, b) return a.price > b.price end)
            else
                -- time_desc：最新上架在前（listed_at 大的在前）
                table.sort(filtered, function(a, b)
                    return (a.listed_at or 0) > (b.listed_at or 0)
                end)
            end

            -- 分页
            local total = #filtered
            local startIdx = (page - 1) * pageSize + 1
            local endIdx = math.min(startIdx + pageSize - 1, total)
            local pageData = {}
            for i = startIdx, endIdx do
                pageData[#pageData + 1] = filtered[i]
            end

            onDone(true, pageData, total)
        end,
        error = function(code, reason)
            onDone(false, nil, 0)
        end
    })
end

-- 玩家自己的上架列表
function Market.GetMyListings(uid, onDone)
    serverCloud.list:Get(Market.ADMIN_UID, "market_listings", {
        ok = function(list)
            local myList = {}
            for _, entry in ipairs(list) do
                local listing = entry.value
                if listing.seller_uid == uid then
                    myList[#myList + 1] = {
                        listing_id  = tostring(entry.list_id),  -- 字符串传输，防止cjson大整数精度丢失
                        seller_uid  = listing.seller_uid,
                        seller_name = listing.seller_name,
                        item        = listing.item,
                        item_name   = listing.item and listing.item.name or "未知",
                        price       = listing.price,
                        currency    = listing.currency or "silver",
                        listed_at   = listing.listed_at,
                    }
                end
            end
            onDone(true, myList)
        end,
        error = function(code, reason)
            onDone(false, {})
        end
    })
end

-- ============================================================================
-- 管理员上架（绕过资产检查，直接注入市场）
-- ============================================================================
function Market.AdminListItem(adminName, item, price, onDone)
    local now = os.time()
    local listing = {
        seller_uid  = Market.ADMIN_UID,
        seller_name = adminName or "神秘商人",
        item        = item,
        price       = price,
        currency    = "spirit_stone",
        listed_at   = now,
        expires_at  = now + Settings.ECONOMY.MARKET_DURATION,
    }

    serverCloud.list:Add(Market.ADMIN_UID, "market_listings", listing, {
        ok = function(listId)
            print(string.format("[Market] 管理员上架 %s 价格%d", item.name, price))
            onDone(true, listId)
        end,
        error = function(code, reason)
            onDone(false, "管理员上架失败：" .. (reason or "未知"))
        end
    })
end

-- ============================================================================
-- 查询玩家自己的交易记录（最新50条，倒序）
-- ============================================================================
function Market.GetHistory(uid, onDone)
    serverCloud.list:Get(uid, "trade_history", {
        ok = function(list)
            -- 倒序取最新50条
            local result = {}
            for i = #list, math.max(1, #list - 49), -1 do
                result[#result + 1] = list[i].value
            end
            onDone(true, result)
        end,
        error = function(code, reason)
            onDone(false, {})
        end
    })
end

-- ============================================================================
-- 清理过期条目（可定时调用）
-- ============================================================================
function Market.CleanExpired()
    local now = os.time()
    serverCloud.list:Get(Market.ADMIN_UID, "market_listings", {
        ok = function(list)
            local count = 0
            for _, entry in ipairs(list) do
                local listing = entry.value
                if listing.expires_at and listing.expires_at <= now then
                    serverCloud.list:Delete(entry.list_id)
                    count = count + 1
                end
            end
            if count > 0 then
                print(string.format("[Market] 清理过期商品 %d 条", count))
            end
        end
    })
end

--- 一次性迁移：清空所有非灵石标价的旧商品（银两时代遗留）
function Market.MigrateClearSilverListings()
    serverCloud.list:Get(Market.ADMIN_UID, "market_listings", {
        ok = function(list)
            local count = 0
            for _, entry in ipairs(list) do
                local listing = entry.value
                if listing.currency ~= "spirit_stone" then
                    serverCloud.list:Delete(entry.list_id)
                    count = count + 1
                end
            end
            if count > 0 then
                print(string.format("[Market] 迁移清理：删除 %d 条银两标价旧商品", count))
            else
                print("[Market] 迁移检查：无旧银两商品需要清理")
            end
        end
    })
end



-- ============================================================================

-- 行情统计：按品类聚合当前在售均价，与基准价比较得出涨跌

-- ============================================================================

function Market.GetMarketTrends(onDone)
    print("[Market] GetMarketTrends called")

    serverCloud.list:Get(Market.ADMIN_UID, "market_listings", {

        ok = function(list)
            print("[Market] GetMarketTrends ok callback, list count=" .. #list)

            local now = os.time()

            -- 按品类聚合: { [category] = { total_price, count, items = {} } }

            local agg = {}

            for _, entry in ipairs(list) do

                local listing = entry.value

                if listing.expires_at and listing.expires_at > now then

                    local item = listing.item

                    local cat = item.type or "other"

                    if not agg[cat] then

                        agg[cat] = { total = 0, count = 0, items = {} }

                    end

                    agg[cat].total = agg[cat].total + listing.price

                    agg[cat].count = agg[cat].count + 1

                    -- 记录单品行情（取前5个最热门的具体物品）

                    local itemKey = item.name or item.id or "unknown"

                    if not agg[cat].items[itemKey] then

                        agg[cat].items[itemKey] = { total = 0, count = 0, base_price = item.bought_price or 0 }

                    end

                    agg[cat].items[itemKey].total = agg[cat].items[itemKey].total + listing.price

                    agg[cat].items[itemKey].count = agg[cat].items[itemKey].count + 1

                end

            end

            -- 输出为数组格式

            local trends = {}

            for cat, data in pairs(agg) do

                local avgPrice = math.floor(data.total / data.count)

                -- 提取热门单品（按数量排序取前5）

                local hotItems = {}

                for name, info in pairs(data.items) do

                    hotItems[#hotItems + 1] = {

                        name = name,

                        avg = math.floor(info.total / info.count),

                        count = info.count,

                        base = info.base_price,

                    }

                end

                table.sort(hotItems, function(a, b) return a.count > b.count end)

                -- 最多保留8个

                local top = {}

                for i = 1, math.min(8, #hotItems) do top[i] = hotItems[i] end

                trends[#trends + 1] = {

                    category = cat,

                    avg_price = avgPrice,

                    listing_count = data.count,

                    hot_items = top,

                }

            end

            table.sort(trends, function(a, b) return a.listing_count > b.listing_count end)

            onDone(true, trends)

        end,

        error = function()
            print("[Market] GetMarketTrends ERROR callback")

            onDone(false, {})

        end

    })

end
return Market
