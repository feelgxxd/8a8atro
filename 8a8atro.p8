pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
function _init()
    poke(0x5f2d, 1)
    deck = {}
    hand = {}
    hover_idx = 0
    max_selected = 5
    
    drag_idx = 0
    drag_type = "hand"
    drag_x = 0
    drag_y = 0
    
    game_state = "menu"
    
    ante = 1
    current_blind_step = 1
    blind_names = {"small", "big", "boss"}
    blind_mults = {1.0, 1.5, 2.0}
    blind_cleared = {false, false, false}
    
    target_score = 300
    current_score = 0
    display_score = 0
    hands_left = 4
    discards_left = 3
    money = 4
    
    jokers = {}
    max_jokers = 5
    hover_joker_idx = 0
    shop_jokers = {}
    reroll_cost = 5
    
    joker_db = {
        {id="joker",       name="joker",       cost=2, desc="+4 mult",       col=8,  spr=1},
        {id="banner",      name="banner",      cost=5, desc="+30c/discard",   col=10, spr=3},
        {id="popcorn",     name="popcorn",     cost=5, desc="+20m (-4/hand)",  col=10, spr=5},
        {id="gros_michel", name="gros michel", cost=5, desc="+15m (1/6 dest)",col=11, spr=7},
        {id="cavendish",   name="cavendish",   cost=8, desc="x3 mult",       col=10, spr=9},
        {id="bull",        name="bull",        cost=6, desc="+2c per $1",     col=12, spr=11}
    }
    
    anim_timer = 0
    anim_step = 0
    anim_queue = {}
    anim_cards = {}
    anim_sel_cards = {}
    anim_joker_idx = 1
    
    particles = {}
    float_texts = {}
    menu_cards = {}
    shake_time = 0
    shake_mag = 0
    pulse_timer = 0
    
    for i=1,12 do
        add(menu_cards, {
            x = rnd(120), y = rnd(128),
            spd = 0.2 + rnd(0.4),
            suit = flr(rnd(4))+1, val = flr(rnd(13))+1
        })
    end
    
    suit_colors = {12, 8, 9, 0}
    val_labels = {"a","2","3","4","5","6","7","8","9","10","j","q","k"}
    
    hand_base = {
        ["high card"]        = {chips=5, mult=1},
        ["pair"]             = {chips=10, mult=2},
        ["two pair"]         = {chips=20, mult=2},
        ["three of a kind"]  = {chips=30, mult=3},
        ["straight"]         = {chips=30, mult=4},
        ["flush"]            = {chips=35, mult=4},
        ["full house"]       = {chips=40, mult=4},
        ["four of a kind"]   = {chips=60, mult=7},
        ["straight flush"]   = {chips=100,mult=8}
    }
    current_hand_name = "none"
    current_hand_chips = 0
    current_hand_mult = 0
end

function start_new_game()
    ante = 1
    current_blind_step = 1
    blind_cleared = {false, false, false}
    money = 4
    jokers = {}
    sfx(0)
    game_state = "select_blind"
end

function get_blind_target(step)
    local base_score = 300 * (1.8 ^ (ante - 1))
    return flr(base_score * blind_mults[step])
end

function start_blind(step)
    if step != current_blind_step then return end
    target_score = get_blind_target(step)
    current_score = 0
    display_score = 0
    hands_left = 4
    discards_left = 3
    
    current_hand_name = "none"
    current_hand_chips = 0
    current_hand_mult = 0
    
    create_deck()
    shuffle_deck()
    hand = {}
    draw_hand(8)
    sfx(0)
    game_state = "play"
end

function on_blind_won()
    blind_cleared[current_blind_step] = true
    money += 3 + current_blind_step
    generate_shop()
    sfx(3)
    game_state = "shop"
end

function generate_shop()
    shop_jokers = {}
    local pool = {}
    
    for template in all(joker_db) do
        local owned = false
        for j in all(jokers) do
            if j.id == template.id then owned = true break end
        end
        if not owned then add(pool, template) end
    end
    
    for i=1,2 do
        if #pool > 0 then
            local idx = flr(rnd(#pool)) + 1
            local template = deli(pool, idx)
            add(shop_jokers, {
                id = template.id,
                name = template.name,
                cost = template.cost,
                desc = template.desc,
                col = template.col,
                spr = template.spr,
                val = (template.id == "popcorn") and 20 or nil
            })
        end
    end
end

function buy_joker(idx)
    local j = shop_jokers[idx]
    if j and money >= j.cost and #jokers < max_jokers then
        money -= j.cost
        add(jokers, {
            id = j.id, name = j.name, cost = j.cost,
            desc = j.desc, col = j.col, spr = j.spr, hover_off = 0, y_bounce = 0
        })
        deli(shop_jokers, idx)
        add_float_text("satin alindi!", 64, 60, 10)
        sfx(3)
    end
end

function sell_joker(idx)
    local j = jokers[idx]
    if j then
        local sell_price = flr(j.cost / 2)
        money += sell_price
        deli(jokers, idx)
        add_float_text("+$"..sell_price, 64, 60, 10)
        sfx(3)
    end
end

function reroll_shop()
    if money >= reroll_cost then
        money -= reroll_cost
        generate_shop()
        add_float_text("yenilendi!", 64, 60, 9)
        sfx(4)
    end
end

function create_deck()
    deck = {}
    for s=1,4 do
        for v=1,13 do
            add(deck, {suit=s, val=v, selected=false, y_off=0, hover_off=0})
        end
    end
end

function shuffle_deck()
    for i=#deck,2,-1 do
        local j = flr(rnd(i)) + 1
        deck[i], deck[j] = deck[j], deck[i]
    end
end

function draw_hand(count)
    while #hand < count and #deck > 0 do
        add(hand, deli(deck, 1))
    end
end

function trigger_shake(mag, time)
    shake_mag = mag
    shake_time = time
end

function add_particle(x, y, col)
    add(particles, {
        x = x, y = y,
        dx = (rnd(2) - 1), dy = (rnd(2) - 1.5),
        life = flr(rnd(12)) + 10, col = col
    })
end

function add_float_text(txt, x, y, col)
    add(float_texts, {
        txt = txt, x = x, y = y,
        dy = -0.6, life = 32, col = col
    })
end

function sort_hand_by_rank()
    for i=1,#hand do
        for j=i+1,#hand do
            if hand[i].val < hand[j].val then
                hand[i], hand[j] = hand[j], hand[i]
            end
        end
    end
    sfx(6)
end

function sort_hand_by_suit()
    for i=1,#hand do
        for j=i+1,#hand do
            if hand[i].suit > hand[j].suit or (hand[i].suit == hand[j].suit and hand[i].val < hand[j].val) then
                hand[i], hand[j] = hand[j], hand[i]
            end
        end
    end
    sfx(6)
end

function clear_selection()
    for c in all(hand) do c.selected = false end
    evaluate_selected_hand()
    sfx(0)
end

function get_card_chip_value(val)
    if val == 1 then return 11 end
    if val >= 10 then return 10 end
    return val
end

function _update()
    pulse_timer += 0.05
    display_score += (current_score - display_score) * 0.25
    
    if shake_time > 0 then shake_time -= 1 end
    
    for mc in all(menu_cards) do
        mc.y += mc.spd
        if (mc.y > 130) mc.y = -20 mc.x = rnd(120)
    end
    
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.x += p.dx p.y += p.dy p.life -= 1
        if (p.life <= 0) deli(particles, i)
    end
    
    for i = #float_texts, 1, -1 do
        local ft = float_texts[i]
        ft.y += ft.dy ft.life -= 1
        if (ft.life <= 0) deli(float_texts, i)
    end
    
    for i = #anim_cards, 1, -1 do
        local ac = anim_cards[i]
        ac.x += (ac.target_x - ac.x) * 0.3
        ac.y += (ac.target_y - ac.y) * 0.3
        ac.life -= 1
        if (flr(rnd(2)) == 0) add_particle(ac.x + 6, ac.y + 9, suit_colors[ac.suit])
        if (ac.life <= 0) deli(anim_cards, i)
    end
    
    local mx, my, mb = stat(32), stat(33), stat(34)
    
    if game_state == "menu" then
        if mb == 1 and not prev_mb then
            if mx >= 34 and mx <= 94 and my >= 78 and my <= 98 then start_new_game() end
        end
        prev_mb = (mb == 1)
        return
    end
    
    if game_state == "shop" then
        hover_joker_idx = 0
        for i=1,2 do
            local sx = (i==1) and 8 or 68
            if mx >= sx and mx <= sx+52 and my >= 34 and my <= 82 then hover_joker_idx = i end
        end
        
        if mb == 1 and not prev_mb then
            if mx >= 8 and mx <= 60 and my >= 34 and my <= 82 then buy_joker(1)
            elseif mx >= 68 and mx <= 120 and my >= 34 and my <= 82 then buy_joker(2)
            elseif mx >= 8 and mx <= 60 and my >= 88 and my <= 104 then reroll_shop()
            elseif mx >= 68 and mx <= 120 and my >= 88 and my <= 104 then
                if current_blind_step == 3 then
                    ante += 1 current_blind_step = 1 blind_cleared = {false, false, false}
                else current_blind_step += 1 end
                sfx(0)
                game_state = "select_blind"
            end
            
            for i=1,#jokers do
                local jx = 4 + (i-1)*13
                if mx >= jx and mx <= jx+11 and my >= 15 and my <= 32 then sell_joker(i) break end
            end
        end
        prev_mb = (mb == 1)
        return
    end
    
    if game_state == "select_blind" then
        if mb == 1 and not prev_mb then
            for b=1,3 do
                local bx1 = 4 + (b-1)*40
                if mx >= bx1 and mx <= bx1+36 and my >= 45 and my <= 110 then
                    if b == current_blind_step then start_blind(b) end
                end
            end
        end
        prev_mb = (mb == 1)
        return
    end
    
    if game_state == "gameover" then
        if mb == 1 and not prev_mb then game_state = "menu" end
        prev_mb = (mb == 1)
        return
    end
    
    if game_state == "anim_play" then update_play_animation() return
    elseif game_state == "anim_discard" then update_discard_animation() return end
    
    if game_state != "play" then return end
    
    if mb == 2 and not prev_mb_right then clear_selection() end
    prev_mb_right = (mb == 2)
    
    hover_idx = 0
    for i, c in ipairs(hand) do
        local x = 4 + (i - 1) * 15
        local y = 88 + c.y_off + c.hover_off
        if mx >= x and mx <= x+11 and my >= y and my <= y+17 then hover_idx = i break end
    end
    
    hover_joker_idx = 0
    for i, j in ipairs(jokers) do
        local jx = 4 + (i-1)*13
        local jy = 15 + (j.hover_off or 0) + (j.y_bounce or 0)
        if mx >= jx and mx <= jx+11 and my >= jy and my <= jy+17 then hover_joker_idx = i break end
    end
    
    for i, j in ipairs(jokers) do
        j.hover_off = j.hover_off or 0
        j.y_bounce = j.y_bounce or 0
        
        j.y_bounce += (0 - j.y_bounce) * 0.3
        if (abs(j.y_bounce) < 0.1) j.y_bounce = 0
        
        local target = (i == hover_joker_idx) and -2 or 0
        j.hover_off += (target - j.hover_off) * 0.4
        if (abs(target - j.hover_off) < 0.1) j.hover_off = target
    end
    
    if mb == 1 and not prev_mb then
        if hover_idx > 0 then
            drag_idx = hover_idx drag_type = "hand" drag_x = mx drag_y = my
        elseif hover_joker_idx > 0 then
            drag_idx = hover_joker_idx drag_type = "joker" drag_x = mx drag_y = my
        elseif mx >= 4 and mx <= 50 and my >= 115 and my <= 125 then handle_action("play")
        elseif mx >= 52 and mx <= 62 and my >= 115 and my <= 125 then sort_hand_by_suit()
        elseif mx >= 64 and mx <= 74 and my >= 115 and my <= 125 then sort_hand_by_rank()
        elseif mx >= 76 and mx <= 123 and my >= 115 and my <= 125 then handle_action("discard") end
    end
    
    if mb == 1 and drag_idx > 0 then
        if drag_type == "hand" and hover_idx > 0 and hover_idx != drag_idx then
            hand[drag_idx], hand[hover_idx] = hand[hover_idx], hand[drag_idx]
            drag_idx = hover_idx
            sfx(6)
        elseif drag_type == "joker" and hover_joker_idx > 0 and hover_joker_idx != drag_idx then
            jokers[drag_idx], jokers[hover_joker_idx] = jokers[hover_joker_idx], jokers[drag_idx]
            drag_idx = hover_joker_idx
            sfx(6)
        end
    end
    
    if mb == 0 and prev_mb and drag_idx > 0 then
        if drag_type == "hand" and flr(abs(mx - drag_x)) < 2 and flr(abs(my - drag_y)) < 2 then
            toggle_card_selection(drag_idx)
        end
        drag_idx = 0
    end
    
    prev_mb = (mb == 1)
    
    for i, card in ipairs(hand) do
        local target_hover = (i == hover_idx) and -5 or 0
        card.hover_off += (target_hover - card.hover_off) * 0.4
        if (abs(target_hover - card.hover_off) < 0.1) card.hover_off = target_hover
        
        local target_y = card.selected and -8 or 0
        card.y_off += (target_y - card.y_off) * 0.35
        if (abs(target_y - card.y_off) < 0.1) card.y_off = target_y
    end
end

function toggle_card_selection(idx)
    local c = hand[idx]
    if not c then return end
    c.selected = not c.selected
    local count = 0
    for card in all(hand) do if (card.selected) count += 1 end
    if count > max_selected then c.selected = false
    else 
        sfx(0)
        if (c.selected) add_particle(4 + (idx-1)*15 + 6, 88 + c.y_off, 10) 
    end
    evaluate_selected_hand()
end

function handle_action(action_type)
    local selected_count = 0
    for c in all(hand) do if (c.selected) selected_count += 1 end
    if action_type == "play" and selected_count > 0 and hands_left > 0 then 
        sfx(1)
        start_play_animation()
    elseif action_type == "discard" and selected_count > 0 and discards_left > 0 then 
        sfx(2)
        start_discard_animation() 
    end
end

function start_play_animation()
    game_state = "anim_play"
    anim_timer = 0
    anim_step = 0
    anim_queue = {}
    anim_cards = {}
    
    local count = 0
    local sel_cards = {}
    for i=1,#hand do
        if hand[i].selected then
            count += 1
            add(sel_cards, hand[i])
            add(anim_queue, {card=hand[i], idx=i, orig_x=4 + (i - 1) * 15, order=count})
        end
    end
    
    anim_sel_cards = sel_cards
    anim_joker_idx = 1
end

function update_play_animation()
    anim_timer += 1
    
    if anim_timer % 6 == 1 and #anim_queue > 0 then
        local item = deli(anim_queue, 1)
        local c = item.card
        local card_chip = get_card_chip_value(c.val)
        local target_center_x = 20 + (item.order * 14)
        
        add(anim_cards, {
            suit=c.suit, val=c.val,
            x=item.orig_x, y=88,
            target_x=target_center_x, target_y=64,
            life=40
        })
        
        trigger_shake(2, 4)
        sfx(5)
        if c.is_scoring then 
            add_float_text("+"..card_chip, target_center_x+2, 54, 12)
        end
        for i=1,6 do add_particle(target_center_x+6, 68, suit_colors[c.suit]) end
        for i=1,#hand do if hand[i] == c then deli(hand, i) break end end
    end
    
    if #anim_queue == 0 and anim_timer % 12 == 0 then
        if anim_joker_idx <= #jokers then
            local j = jokers[anim_joker_idx]
            local jx = 4 + (anim_joker_idx-1)*13
            j.y_bounce = -4
            
            local triggered = false
            local destroyed = false
            if j.id == "joker" then 
                current_hand_mult += 4 add_float_text("+4 mult", jx, 29, 8) triggered = true
            elseif j.id == "banner" then 
                local b_chips = (discards_left * 30)
                current_hand_chips += b_chips add_float_text("+"..b_chips, jx, 29, 12) triggered = true
            elseif j.id == "half_joker" and #anim_sel_cards <= 3 then 
                current_hand_mult += 20 add_float_text("+20 mult", jx, 29, 8) triggered = true
            elseif j.id == "gros_michel" then 
                current_hand_mult += 15 add_float_text("+15 mult", jx, 29, 8) triggered = true
                if flr(rnd(6)) == 0 then
                    deli(jokers, anim_joker_idx)
                    add_float_text("patladi!", jx, 29, 8)
                    destroyed = true
                end
            elseif j.id == "cavendish" then 
                current_hand_mult *= 3 add_float_text("x3 mult!", jx, 29, 10) triggered = true
            elseif j.id == "bull" then 
                local b_chips = money * 2
                current_hand_chips += b_chips add_float_text("+"..b_chips, jx, 29, 12) triggered = true
            end
            
            if triggered then
                sfx(5)
                trigger_shake(2, 3)
                for i=1,6 do add_particle(jx+4, 21, j.col) end
            end
            
            if not destroyed then
                anim_joker_idx += 1
            end
        end
    end
    
    if #anim_queue == 0 and anim_joker_idx > #jokers and anim_timer > 50 then
        local total_hand_score = current_hand_chips * current_hand_mult
        current_score += total_hand_score
        trigger_shake(4, 6)
        sfx(3)
        
        hands_left -= 1
        draw_hand(8)
        evaluate_selected_hand()
        if current_score >= target_score then on_blind_won()
        elseif hands_left <= 0 then game_state = "gameover"
        else game_state = "play" end
    end
end

function start_discard_animation()
    game_state = "anim_discard"
    anim_timer = 0
    anim_queue = {}
    anim_cards = {}
    for i=1,#hand do
        if hand[i].selected then
            add(anim_queue, {card=hand[i], idx=i, orig_x=4 + (i - 1) * 15})
        end
    end
end

function update_discard_animation()
    anim_timer += 1
    if anim_timer % 4 == 1 and #anim_queue > 0 then
        local item = deli(anim_queue, 1)
        local c = item.card
        add(anim_cards, {suit=c.suit, val=c.val, x=item.orig_x, y=88, target_x=item.orig_x, target_y=135, life=15})
        add_float_text("discarded", item.orig_x, 80, 8)
        trigger_shake(1, 2)
        for i=1,#hand do if hand[i] == c then deli(hand, i) break end end
    end
    if #anim_queue == 0 and anim_timer > 20 then
        discards_left -= 1
        draw_hand(8)
        evaluate_selected_hand()
        game_state = "play"
    end
end

function evaluate_selected_hand()
    local sel = {}
    for c in all(hand) do 
        if (c.selected) then c.is_scoring = false add(sel, c) end
    end
    
    if #sel == 0 then 
        current_hand_name = "none" current_hand_chips = 0 current_hand_mult = 0 return 
    end
    
    for i=1,#sel do
        for j=i+1,#sel do
            if sel[i].val > sel[j].val then sel[i], sel[j] = sel[j], sel[i] end
        end
    end
    
    local counts = {}
    local is_flush = (#sel == 5)
    local first_suit = sel[1].suit
    
    for c in all(sel) do
        counts[c.val] = (counts[c.val] or 0) + 1
        if c.suit != first_suit then is_flush = false end
    end
    
    local freq = {}
    for k, v in pairs(counts) do add(freq, v) end
    rsort(freq)
    
    local is_straight = false
    if #sel == 5 and #freq == 5 then
        if sel[5].val - sel[1].val == 4 then 
            is_straight = true
        elseif sel[1].val == 1 and sel[2].val == 2 and sel[3].val == 3 and sel[4].val == 4 and sel[5].val == 5 then 
            is_straight = true 
        elseif sel[1].val == 1 and sel[2].val == 10 and sel[3].val == 11 and sel[4].val == 12 and sel[5].val == 13 then
            is_straight = true
        end
    end
    
    if is_straight and is_flush then current_hand_name = "straight flush" for c in all(sel) do c.is_scoring = true end
    elseif freq[1] == 4 then current_hand_name = "four of a kind" local tv=0 for k,v in pairs(counts) do if v==4 then tv=k end end for c in all(sel) do if c.val==tv then c.is_scoring=true end end
    elseif freq[1] == 3 and freq[2] == 2 then current_hand_name = "full house" for c in all(sel) do c.is_scoring = true end
    elseif is_flush then current_hand_name = "flush" for c in all(sel) do c.is_scoring = true end
    elseif is_straight then current_hand_name = "straight" for c in all(sel) do c.is_scoring = true end
    elseif freq[1] == 3 then current_hand_name = "three of a kind" local tv=0 for k,v in pairs(counts) do if v==3 then tv=k end end for c in all(sel) do if c.val==tv then c.is_scoring=true end end
    elseif freq[1] == 2 and freq[2] == 2 then current_hand_name = "two pair" for c in all(sel) do if counts[c.val]==2 then c.is_scoring=true end end
    elseif freq[1] == 2 then current_hand_name = "pair" for c in all(sel) do if counts[c.val]==2 then c.is_scoring=true end end
    else current_hand_name = "high card" sel[#sel].is_scoring = true end
    
    local info = hand_base[current_hand_name]
    local bonus_chips = 0
    for c in all(sel) do if c.is_scoring then bonus_chips += get_card_chip_value(c.val) end end
    
    current_hand_chips = info.chips + bonus_chips
    current_hand_mult = info.mult
end

function rsort(t)
    for i=1,#t do
        for j=i+1,#t do if t[i] < t[j] then t[i], t[j] = t[j], t[i] end end
    end
end

function draw_table_background()
    cls(3)
    for y=0,128,8 do
        for x=0,128,8 do
            if ((x/8)+(y/8))%2 == 0 then rectfill(x, y, x+7, y+7, 11) end
        end
    end
    rect(0, 0, 127, 127, 0)
    rect(1, 1, 126, 126, 4)
end

function draw_suit_icon(suit, x, y, col)
    if suit == 1 then
        pset(x+2, y, col) rectfill(x+1, y+1, x+3, y+3, col) pset(x, y+3, col) pset(x+4, y+3, col) rectfill(x+2, y+4, x+2, y+5, col)
    elseif suit == 2 then
        pset(x+1, y, col) pset(x+3, y, col) rectfill(x, y+1, x+4, y+2, col) rectfill(x+1, y+3, x+3, y+3, col) pset(x+2, y+4, col)
    elseif suit == 3 then
        pset(x+2, y, col) rectfill(x+1, y+1, x+3, y+1, col) rectfill(x, y+2, x+4, y+2, col) rectfill(x+1, y+3, x+3, y+3, col) pset(x+2, y+4, col)
    elseif suit == 4 then
        pset(x+2, y, col) rectfill(x, y+2, x+4, y+2, col) rectfill(x+1, y+1, x+3, y+3, col) rectfill(x+2, y+4, x+2, y+5, col)
    end
end

function on_blind_won()
    blind_cleared[current_blind_step] = true
    money += 3 + current_blind_step
    generate_shop()
    sfx(3)
    
    for j in all(jokers) do
        j.y_bounce = 0
        j.hover_off = 0
    end
    
    game_state = "shop"
end

function draw_joker_card(j, x, y, w, h)
    w = w or 12
    h = h or 18

    rectfill(x, y, x + w - 1, y + h - 1, 7)
    rect(x, y, x + w - 1, y + h - 1, 0)

    print("j", x + 1, y + 2, 0)
    if w >= 16 then
        print("j", x + w - 5, y + h - 7, 0)
    end

    if j and j.spr then
        local sx = (j.spr % 16) * 8
        local sy = flr(j.spr / 16) * 8

        palt(0, true)
        local margin = 2
        sspr(sx, sy, 16, 24, x + margin, y + 4, w - (margin * 2), h - 6)
        palt()
    end
end

function draw_shop_card(item, box_x, box_y, box_w, box_h)
    rectfill(box_x, box_y, box_x + box_w - 1, box_y + box_h - 1, 0)
    rect(box_x, box_y, box_x + box_w - 1, box_y + box_h - 1, 5)

    local card_w = 16
    local card_h = 22
    local card_x = box_x + flr((box_w - card_w) / 2)
    local card_y = box_y + 3

    draw_joker_card(item, card_x, card_y, card_w, card_h)

    local text_y = card_y + card_h + 3
    local name_str = item.name or "joker"
    local text_x = box_x + flr((box_w - (#name_str * 4)) / 2)
    
    print(name_str, text_x, text_y, 10)

    local btn_w = 28
    local btn_h = 9
    local btn_x = box_x + flr((box_w - btn_w) / 2)
    local btn_y = box_y + box_h - btn_h - 2

    rectfill(btn_x, btn_y, btn_x + btn_w - 1, btn_y + btn_h - 1, 11)
    
    local price_str = "$" .. (item.cost or 0)
    local price_x = btn_x + flr((btn_w - (#price_str * 4)) / 2)
    print(price_str, price_x, btn_y + 2, 0)
end

function draw_card_sprite(x, y, suit, val, is_selected, is_hover)
    local shadow_off = is_selected and 4 or 2
    rectfill(x+shadow_off, y+shadow_off, x+11+shadow_off, y+17+shadow_off, 0)
    rectfill(x+1, y, x+10, y+17, 7) rectfill(x, y+1, x+11, y+16, 7)
    rectfill(x+1, y+16, x+10, y+16, 6)
    
    local border_col = 0
    if is_hover then border_col = 10 end
    if is_selected then border_col = (flr(pulse_timer * 12) % 2 == 0) and 10 or 9 end
    
    rect(x, y, x+11, y+17, border_col)
    local col = suit_colors[suit]
    print(val_labels[val], x+2, y+2, col)
    draw_suit_icon(suit, x+4, y+10, col)
end

function draw_joker_slots()
    for i = 1, max_jokers do
        local jx = 4 + (i - 1) * 13
        local jy = 15 + (jokers[i] and jokers[i].hover_off or 0) + (jokers[i] and jokers[i].y_bounce or 0)
        local slot_w, slot_h = 12, 18

        rectfill(jx, jy, jx + slot_w - 1, jy + slot_h - 1, 0)

        if jokers[i] then
            draw_joker_card(jokers[i], jx, jy, slot_w, slot_h)
        end

        rect(jx, jy, jx + slot_w - 1, jy + slot_h - 1, (i == hover_joker_idx) and 10 or 5)
    end
end

function draw_joker_tooltip(j)
    if not j then return end
    rectfill(12, 54, 116, 78, 0)
    rect(12, 54, 116, 78, 10)
    rect(13, 55, 115, 77, 9)
    print(j.name, 16, 58, 10)
    print(j.desc, 16, 67, 7)
end

function _draw()
    local cam_x, cam_y = 0, 0
    if shake_time > 0 then
        cam_x = flr(rnd(shake_mag * 2) - shake_mag)
        cam_y = flr(rnd(shake_mag * 2) - shake_mag)
    end
    camera(cam_x, cam_y)
    
    draw_table_background()
    local mx, my = stat(32), stat(33)
    
    if game_state == "menu" then
        for mc in all(menu_cards) do draw_card_sprite(mc.x, mc.y, mc.suit, mc.val, false, false) end
        local bob = flr(sin(time() * 0.8) * 3)
        rectfill(10, 16 + bob, 118, 60 + bob, 0)
        rectfill(12, 18 + bob, 116, 58 + bob, 4)
        rect(12, 18 + bob, 116, 58 + bob, 10)
        rect(13, 19 + bob, 115, 57 + bob, 9)
        
        local rainbow = flr(time() * 8) % 6 + 8
        print("8a8atro", 49, 29 + bob, 0) print("8a8atro", 48, 28 + bob, rainbow)
        print("demake edition", 35, 42 + bob, 7)
        
        local hover_btn = (mx >= 34 and mx <= 94 and my >= 78 and my <= 98)
        rectfill(34, 80, 94, 98, 0) rectfill(34, 78, 94, 96, hover_btn and 10 or 8)
        rect(34, 78, 94, 96, 7)
        print("play", 54, 85, hover_btn and 7 or 0)
        
        pset(mx, my, 7) camera(0, 0) return
    end
    
    if game_state == "shop" then
        rectfill(2, 2, 125, 12, 0) rect(2, 2, 125, 12, 10)
        print("shop - cash: $"..money, 22, 5, 10)
        
        draw_joker_slots()
        
        for i=1,2 do
            local sj = shop_jokers[i]
            local sx = (i==1) and 8 or 68
            local is_h = (hover_joker_idx == i)
            
            draw_shop_card(sj or {name="sold", cost=0}, sx, 34, 52, 48)
        end
        
        if hover_joker_idx > 0 and shop_jokers[hover_joker_idx] then
            draw_joker_tooltip(shop_jokers[hover_joker_idx])
        end
        
        local h_rr = (mx >= 8 and mx <= 60 and my >= 88 and my <= 104)
        rectfill(8, 88, 60, 104, h_rr and 9 or 8) rect(8, 88, 60, 104, 7)
        print("reroll", 18, 92, 7) print("$"..reroll_cost, 28, 98, 10)
        
        local h_next = (mx >= 68 and mx <= 120 and my >= 88 and my <= 104)
        rectfill(68, 88, 120, 104, h_next and 11 or 10) rect(68, 88, 120, 104, 7)
        print("next", 84, 92, 0) print("round", 82, 98, 0)
        
        pset(mx, my, 7) camera(0, 0) return
    end
    
    if game_state == "select_blind" then
        rectfill(2, 2, 125, 20, 0) rect(2, 2, 125, 20, 10)
        print("ante "..ante, 8, 8, 10) print("cash: $"..money, 75, 8, 11)
        
        for b=1,3 do
            local bx = 4 + (b-1)*40
            local bw, bh = 38, 94
            local is_active = (b == current_blind_step)
            local is_cleared = blind_cleared[b]
            local target = get_blind_target(b)
            
            rectfill(bx+1, 29, bx+bw+1, 123, 0) rectfill(bx, 28, bx+bw, 122, is_active and 4 or 0)
            rect(bx, 28, bx+bw, 122, is_active and 10 or 5)
            print(blind_names[b], bx+3, 32, is_active and 10 or 6)
            
            rectfill(bx+2, 50, bx+bw-2, 66, 1)
            print("goal", bx+4, 52, 6) print(target, bx+4, 58, is_active and 10 or 7)
            
            if is_cleared then print("[done]", bx+6, 100, 11)
            elseif is_active then
                local hover = (mx >= bx and mx <= bx+bw and my >= 28 and my <= 122)
                rectfill(bx+3, 100, bx+bw-3, 116, hover and 10 or 8) rect(bx+3, 100, bx+bw-3, 116, 7)
                print("select", bx+7, 105, hover and 7 or 0)
            else print("[locked]", bx+4, 100, 5) end
        end
        pset(mx, my, 7) camera(0, 0) return
    end
    
    rectfill(2, 2, 125, 12, 0) rect(2, 2, 125, 12, 5)
    print("a"..ante, 4, 5, 6)
    
    rectfill(24, 3, 64, 11, 1) print("g:", 26, 5, 6) print(target_score, 34, 5, 10)
    rectfill(68, 3, 123, 11, 1) print("score:", 70, 5, 6) print(flr(display_score), 94, 5, 11)
    
    draw_joker_slots()
    
    rectfill(4, 40, 123, 60, 0) rect(4, 40, 123, 60, 5)
    if current_hand_name != "none" then
        print(current_hand_name, 6, 42, 10)
        rectfill(6, 49, 54, 58, 12) print(current_hand_chips, 12, 51, 7)
        print("x", 58, 51, 7)
        rectfill(64, 49, 121, 58, 8) print(current_hand_mult, 70, 51, 7)
    else print("choose card...", 36, 46, 5) end
    
    if hover_joker_idx > 0 and jokers[hover_joker_idx] then
        draw_joker_tooltip(jokers[hover_joker_idx])
    end
    
    for ac in all(anim_cards) do draw_card_sprite(ac.x, ac.y, ac.suit, ac.val, false, false) end
    
    for i, c in ipairs(hand) do
        local x = 4 + (i - 1) * 15
        local y = 88 + c.y_off + c.hover_off
        if i == drag_idx and drag_type == "hand" and stat(34) == 1 then x = stat(32) - 5 y = stat(33) - 8 end
        draw_card_sprite(x, y, c.suit, c.val, c.selected, (i == hover_idx))
        if i == hover_idx then print("v", x+4, y-6, 10) end
    end
    
    for p in all(particles) do rectfill(p.x, p.y, p.x+1, p.y+1, p.col) end
    for ft in all(float_texts) do print(ft.txt, ft.x+1, ft.y+1, 0) print(ft.txt, ft.x, ft.y, ft.col) end
    
    if game_state == "gameover" then
        rectfill(16, 40, 112, 85, 0) rect(16, 40, 112, 85, 8)
        print("game over", 44, 48, 8) print("max ante: "..ante, 30, 60, 7)
    else
        local sel_cnt = 0
        for c in all(hand) do if (c.selected) sel_cnt += 1 end
        local can_p = (hands_left > 0 and sel_cnt > 0)
        local can_d = (discards_left > 0 and sel_cnt > 0)
        
        local h_p = (mx >= 4 and mx <= 50 and my >= 115 and my <= 125)
        local h_s = (mx >= 52 and mx <= 62 and my >= 115 and my <= 125)
        local h_r = (mx >= 64 and mx <= 74 and my >= 115 and my <= 125)
        local h_d = (mx >= 76 and mx <= 123 and my >= 115 and my <= 125)
        
        rectfill(4, 115, 50, 125, can_p and (h_p and 11 or 12) or 5) rect(4, 115, 50, 125, 6)
        print("play("..hands_left..")", 8, 118, can_p and 7 or 6)
        
        rectfill(52, 115, 62, 125, h_s and 10 or 0) rect(52, 115, 62, 125, 5)
        print("s", 55, 118, h_s and 0 or 7)
        
        rectfill(64, 115, 74, 125, h_r and 10 or 0) rect(64, 115, 74, 125, 5)
        print("r", 67, 118, h_r and 0 or 7)
        
        rectfill(76, 115, 123, 125, can_d and (h_d and 9 or 8) or 5) rect(76, 115, 123, 125, 6)
        print("discard("..discards_left..")", 78, 118, can_d and 7 or 6)
    end
    
    pset(mx, my, 7) camera(0, 0)
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000888000000000000000000000000000000000000000300bbb000000000000600000440000009aa00009aa000000000000000000000000000
0000000000000000288080000000099a9969a000000000022222220000339bbb0b0000000000066300aa4000009aa0000009aa00000000000000000000000000
000000000000000888000000000aa99aa969a90000000029999a9920000aa99b000000000000063aaaa9000009aa000000009aa0000000000000000000000000
000000000000000888800090009aa9990009a90000022299999949200000aaa90000b000000003a99aa600000aa0000000000aa0000000000000000000000000
0000000000009928888009995999aa000000090000299999499999920000aaaaa0bb000000000a99aa36000009a0000000009aa0000000000000000000000000
0000000000999288888499905599a0000006990002294999449499990000ba4aabbb00000006aa9aa336600009aa00000009aaa0000000000000000000000000
00000000099998888884999005990000099690002a99999999499999000b0a44a99000000363a99aa006666009aaa500059aaa00000000000000000000000000
0000000099994888888899900599009a99000000999999999999999a000000aaaaa00000063a99aa00000000009555555555a000000000000000000000000000
00000000990488888888490000900969a0000000999a949999994992000bbbaaaaa9bb0000399aaa000000005055555555555050000000000000000000000000
0000000090028a7777a889000056099600000000299949a98286a99200bbbbaa44a9b0b000a9aaa0000000005555445554455550000000000000000000000000
00000000000871777717800000550aaa0000000028869998828686200000bbaaa4a900000099aaa6600060005554555555545550000000000000000000000000
00000000000671777717500000056999690000002886886886868620000000aaaaaa0000039aaaa3666660005555655555655550000000000000000000000000
0000000000067777777750000005509699aa90002886886888868620000000aaaaa900000a9aaaa3666000000555565556555500000000000000000000000000
000000000067d776677d75000000550000a99900288688688686820000b000aaaaaa00000a9aaaaa300000600555555555555500000000000000000000000000
00000000006778877887750000005500000006002886886888868200000bbbaa4aab00000a9aaaaa006666600055555455555000000000000000000000000000
00000000000678e88e8760000000055000000a002886886886868200000bbaa44a90b0000a99aaaaa33666000055555455555000000000000000000000000000
0000000000cc678ee876ccc0000000560000990028868868888682000000baa4aa9000000aa9aaaaaaa9aa000005555555550000000000000000000000000000
000000000ccc67788776ccc1000000550000a90028868868828682000b000aaaaa90000003a99aaaaaaa9a000000eee5dee00000000000000000000000000000
000000008cccc666666cc0000000005500099a0028868868828629a00bbbaaaaa9b0000000aa999a9aaa0000000deeeeeeee0000000000000000000000000000
0000000000ccccccccccc000000000056006900029a68868aa8209aa00baa44aabbbb0000063aaaaaa000000000de5eee5ee0000000000000000000000000000
00000000000cccc00ccc000000000005500900002996886229200000000aaaa99000b00000600063330000000000deeeede00000000000000000000000000000
00000000000ccc0000cc00000000000055600000022229a0000900000033a990000b00000660000366600000000005dee5000000000000000000000000000000
000000000001000000080000000000000555000000a0099000000000000300000000000000000000000000000000005550000000000000000000000000000000
__label__
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888eeeeee888888888888888888888888888888888888888888888888888888888888888888888888ff8ff8888228822888222822888888822888888228888
8888ee888ee88888888888888888888888888888888888888888888888888888888888888888888888ff888ff888222222888222822888882282888888222888
888eee8e8ee88888e88888888888888888888888888888888888888888888888888888888888888888ff888ff888282282888222888888228882888888288888
888eee8e8ee8888eee8888888888888888888888888888888888888888888888888888888888888888ff888ff888222222888888222888228882888822288888
888eee8e8ee88888e88888888888888888888888888888888888888888888888888888888888888888ff888ff888822228888228222888882282888222288888
888eee888ee888888888888888888888888888888888888888888888888888888888888888888888888ff8ff8888828828888228222888888822888222888888
888eeeeeeee888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1111111111111ddd1ddd1ddd1ddd1ddd1ddd11dd1111111111111dd11ddd11dd1d1d11111dd11dd1111111dd1ddd1d111ddd11dd1ddd1ddd11dd1dd111111111
1111111111111d1d1d1d1d1d1d1d11d11d1d1d1d1111111111111d1d1d111d111d1d11111dd11dd111111d111d111d111d111d1111d111d11d1d1d1d11111111
1ddd1ddd11111dd11ddd1dd11ddd11d11dd11d1d11111ddd11111d1d1dd11d111dd1111111dd11dd11111ddd1dd11d111dd11d1111d111d11d1d1d1d11111111
1111111111111d1d1d1d1d1d1d1d11d11d1d1d1d1111111111111d1d1d111d111d1d11111d1d1d1d1111111d1d111d111d111d1111d111d11d1d1d1d11111111
1111111111111ddd1d1d1ddd1d1d11d11d1d1dd11111111111111ddd1ddd11dd1d1d11111ddd1ddd11111dd11ddd1ddd1ddd11dd11d11ddd1dd11d1d11111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
1eee1e1e1ee111ee1eee1eee11ee1ee1111111111666166116661666117111711111111111111111111111111111111111111111111111111111111111111111
1e111e1e1e1e1e1111e111e11e1e1e1e111111111161161611611161171111171111111111111111111111111111111111111111111111111111111111111111
1ee11e1e1e1e1e1111e111e11e1e1e1e111111111161161611611161171111171111111111111111111111111111111111111111111111111111111111111111
1e111e1e1e1e1e1111e111e11e1e1e1e111111111161161611611161171111171111111111111111111111111111111111111111111111111111111111111111
1e1111ee1e1e11ee11e11eee1ee11e1e111116661666161616661161117111711111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111661166611661616111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111616161116111616111117771111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111616166116111661111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111616161116111616111117771111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111666166611661616111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111117711111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111117771111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111117777111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111117711111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111171111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
82888222822882228888828288828282888888888888888888888888888888888888888888888888888888888888888882228882822282288222822288866688
82888828828282888888828288288282888888888888888888888888888888888888888888888888888888888888888882888828828288288282888288888888
82888828828282288888822288288222888888888888888888888888888888888888888888888888888888888888888882228828822288288222822288822288
82888828828282888888888288288882888888888888888888888888888888888888888888888888888888888888888888828828828288288882828888888888
82228222828282228888888282888882888888888888888888888888888888888888888888888888888888888888888882228288822282228882822288822288
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888

__sfx__
000200000000000000000002405000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000400002905030050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000500001f15018150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000400003015034150371500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00030000260502d050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00030000394503c450000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100001c55000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
