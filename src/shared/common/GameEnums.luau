--!strict
--[[
	GameEnums
	Identificadores de estado como tipos literais.
	Um erro de digitacao vira erro de tipo em tempo de analise, nao comparacao
	de string silenciosamente falsa em runtime.
]]

export type RoundPhase = "Lobby" | "Starting" | "Building" | "Disaster" | "Climax" | "Reset"

type RoundPhaseRegistry = {
	Lobby: RoundPhase,
	Starting: RoundPhase,
	Building: RoundPhase,
	Disaster: RoundPhase,
	Climax: RoundPhase,
	Reset: RoundPhase,
}

local roundPhaseRegistry: RoundPhaseRegistry = {
	Lobby = "Lobby",
	Starting = "Starting",
	Building = "Building",
	Disaster = "Disaster",
	Climax = "Climax",
	Reset = "Reset",
}

local GameEnums = {
	RoundPhase = table.freeze(roundPhaseRegistry),
}

return table.freeze(GameEnums)