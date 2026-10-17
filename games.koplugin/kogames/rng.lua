--[[--
可复现的随机数（LCG）。种子相同序列相同。
--]]
local Rng = {}
Rng.__index = Rng

local M = 2147483648 -- 2^31

function Rng.new(seed)
    return setmetatable({ s = (math.floor(seed or 1) % M) }, Rng)
end

--- [0, 1)
function Rng:float()
    self.s = (self.s * 1103515245 + 12345) % M
    return self.s / M
end

--- 1..n（整数）
function Rng:int(n)
    return math.floor(self:float() * n) + 1
end

function Rng:shuffle(t)
    for i = #t, 2, -1 do
        local j = self:int(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

return Rng
