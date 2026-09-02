--!strict
--[[
	GameConstants
	Valores compartilhados entre servidor e cliente.
	Congelado em runtime: nenhum sistema pode alterar um limiar em tempo de jogo.
    ..Test..
]]

local GameConstants = {}

GameConstants.Lobby = table.freeze({
	LOBBY_FOLDER_NAME = "Lobby",
	START_PAD_NAME = "StartPad",
	COUNTDOWN_SECONDS = 15,
	MINIMUM_PLAYERS_TO_START = 1,
	CANCEL_COUNTDOWN_WHEN_PAD_EMPTY = true,
	PAD_VERTICAL_TOLERANCE_STUDS = 6,
})

GameConstants.Round = table.freeze({
	BUILDING_SECONDS = 180,
	DISASTER_SECONDS = 20,
	CLIMAX_SECONDS = 8,
	RESET_SECONDS = 5,
})

GameConstants.Replication = table.freeze({
	STATE_FOLDER_NAME = "RoundState",
	ATTRIBUTE_PHASE = "Phase",
	ATTRIBUTE_PHASE_ENDS_AT = "PhaseEndsAt",
	ATTRIBUTE_PHASE_DURATION = "PhaseDuration",
	ATTRIBUTE_ROUND_ID = "RoundId",
})

GameConstants.Loop = table.freeze({
	TICK_INTERVAL_SECONDS = 0.25,
})

return table.freeze(GameConstants)