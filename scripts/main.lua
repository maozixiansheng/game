-- ============================================================================
-- 倒爷修仙传
-- main.lua - 入口文件
-- ============================================================================

local Module = nil

function Start()
    if IsServerMode() then
        print("[Main] 启动服务端模式")
        Module = require("network.Server")
    else
        print("[Main] 启动客户端模式")
        Module = require("network.Client")
    end
    Module.Start()
end

function Stop()
    if Module and Module.Stop then
        Module.Stop()
    end
end
