return function(t)
    t.test("every game has help; shown automatically only the first time", function()
        local H = t.H
        local Registry = require("kogames.registry")
        for _, def in ipairs(Registry.all()) do assert(def.help, def.id .. " has no help") end
        H.settings, H.saved = {}, {}
        Registry.launch(H.host, require("kogames.games.gomoku"), nil)
        assert(H.view.help and H.view.help_now)
        Registry.launch(H.host, require("kogames.games.gomoku"), nil)
        assert(H.view.help and not H.view.help_now)
    end)
end
