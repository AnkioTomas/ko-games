return function(t)
    t.test("every game has help; shown automatically only the first time", function()
        local H = t.H
        local Registry = require("kogames.registry")
        for _, def in ipairs(Registry.all()) do assert(def.help, def.id .. " has no help") end
        H.settings, H.saved = {}, {}
        Registry.launch(H.host, require("kogames.games.gomoku.main"), nil)
        assert(H.view.help and H.view.help_now)
        Registry.launch(H.host, require("kogames.games.gomoku.main"), nil)
        assert(H.view.help and not H.view.help_now)
    end)

    t.test("games with settings open the settings dialog on first entry and reset on start", function()
        local H = t.H
        H.settings, H.saved = {}, {}
        require("kogames.registry").launch(H.host, require("kogames.games.g2048.main"), nil)
        local v = H.view
        assert(v.settings and v.settings_now and not v.help_now and v.settings.reset)
        assert(#v.settings.groups[1].options >= 2)
        local before = v
        v.settings.reset()
        assert(H.view ~= before and not H.view.settings_now)
    end)
end
