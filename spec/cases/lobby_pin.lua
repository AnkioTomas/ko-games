return function(t)
    t.test("lobby: pin moves a game to the top and persists", function()
        local H = t.H
        H.settings = {}
        require("kogames.lobby").new(H.host):show()
        local items = H.view.cards.items
        local last = items[#items < 6 and #items or 6]
        local second = items[2]
        second.pin.callback()
        assert(H.view.cards.items[1].title == second.title)
        assert(H.view.cards.items[1].pin.on)
        second = H.view.cards.items[1]
        second.pin.callback()
        assert(not H.view.cards.items[1].pin.on and H.view.cards.items[1].title ~= second.title)
    end)
end
