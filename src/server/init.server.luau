--!strict
--[[
	ServerBootstrap (PROVISORIO)
	Sera reescrito no TSK-003 com ordem de inicializacao completa.
]]

local GameLoopManager = require(script.gameplay.GameLoopManager)

GameLoopManager.onPhaseChanged(function(phase, _endsAt, duration, roundId)
	print(string.format("[Loop] Rodada %d -> %s (%.0fs)", roundId, phase, duration))
end)

GameLoopManager.init()
GameLoopManager.start()

game:BindToClose(function()
	GameLoopManager.stop()
	task.wait(0.5)
end)