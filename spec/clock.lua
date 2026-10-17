return function(t)
    local H = t.H

    -- 虚拟时钟宿主：schedule 入队，advance(秒) 按时间顺序触发
    local function clockHost()
        local h = setmetatable({}, { __index = H.host })
        local now, q, seq = 0, {}, 0
        h.pending = function() return #q end
        h.now = function() return 1000 + now end
        h.schedule = function(_, sec, fn)
            seq = seq + 1
            local item = { at = now + sec, fn = fn, id = seq }
            q[#q + 1] = item
            return item
        end
        h.unschedule = function(_, item)
            for i, v in ipairs(q) do if v == item then table.remove(q, i) return end end
        end
        h.advance = function(sec)
            local limit = now + sec
            while true do
                local bi
                for i, v in ipairs(q) do if v.at <= limit and (not bi or v.at < q[bi].at) then bi = i end end
                if not bi then break end
                local item = table.remove(q, bi)
                now = item.at
                item.fn()
            end
            now = limit
        end
        return h
    end

    local function launch(def)
        H.saved, H.view = {}, nil
        local host = clockHost()
        host.showScreen = function(_, v) H.view = v H.shows = H.shows + 1 end
        local ctx = require("kogames.ctx").new(host, def, nil)
        local game = def.new(ctx)
        ctx.on_closed = function() if game.stop then game.stop() end end
        game.start()
        return game, host, ctx
    end

    local function gridText(v)
        local g = v.grid
        local n = 0
        for r = 1, g.rows do for c = 1, g.cols do if g.cell(r, c) then n = n + 1 end end end
        return n
    end
    return launch, gridText
end
