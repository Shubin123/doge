function love.conf(t)
    t.window.width, t.window.height = 64, 64
    t.window.title = "princess rig"
    t.modules.audio, t.modules.sound, t.modules.joystick, t.modules.physics = false, false, false, false
end
