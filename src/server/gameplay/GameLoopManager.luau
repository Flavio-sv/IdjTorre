--!strict
--[[
	GameLoopManager

	Maquina de estados autoritativa da rodada. Unico dono do relogio do jogo.
	O cliente nunca calcula tempo: ele le o instante de termino replicado e
	deriva o restante contra o relogio compartilhado do servidor.

	Ciclo: Lobby -> Starting -> Building -> Disaster -> Climax -> Reset -> Lobby
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--==============================================================
-- Dependencias
--==============================================================

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local GameEnums = require(ReplicatedStorage.Shared.GameEnums)

local Phase = GameEnums.RoundPhase

--==============================================================
-- Tipos
--==============================================================

export type PhaseChangedListener = (phase: string, endsAt: number, duration: number, roundId: number) -> ()

type AbortPredicate = () -> boolean

--==============================================================
-- Estado interno
--==============================================================

local GameLoopManager = {}

local isInitialized = false
local isRunning = false

local currentPhase: string? = nil
local currentRoundId = 0
local currentPhaseEndsAt = 0

local stateFolder: Folder? = nil
local startPad: BasePart? = nil

local phaseListeners: { [number]: PhaseChangedListener } = {}
local nextListenerId = 0

--==============================================================
-- Tabela de transicoes permitidas
--==============================================================

local ALLOWED_TRANSITIONS: { [string]: { string } } = {
	[Phase.Lobby] = { Phase.Starting },
	[Phase.Starting] = { Phase.Building, Phase.Lobby },
	[Phase.Building] = { Phase.Disaster, Phase.Reset },
	[Phase.Disaster] = { Phase.Climax, Phase.Reset },
	[Phase.Climax] = { Phase.Reset },
	[Phase.Reset] = { Phase.Lobby },
}

local function assertTransitionIsLegal(fromPhase: string?, toPhase: string): ()
	if fromPhase == nil then
		return
	end

	local allowedTargets = ALLOWED_TRANSITIONS[fromPhase]
	if not allowedTargets then
		error(string.format("[GameLoopManager] Fase de origem desconhecida: '%s'.", fromPhase), 2)
	end

	if not table.find(allowedTargets, toPhase) then
		error(
			string.format("[GameLoopManager] Transicao ilegal: '%s' -> '%s'.", fromPhase, toPhase),
			2
		)
	end
end

--==============================================================
-- Replicacao de estado
--==============================================================

local function publishPhase(newPhase: string, durationSeconds: number): ()
	local folder = stateFolder
	if not folder then
		error("[GameLoopManager] publishPhase chamado sem stateFolder. init() rodou?", 2)
	end

	local replication = GameConstants.Replication
	local endsAt = if durationSeconds > 0 then Workspace:GetServerTimeNow() + durationSeconds else 0

	currentPhase = newPhase
	currentPhaseEndsAt = endsAt

	folder:SetAttribute(replication.ATTRIBUTE_PHASE, newPhase)
	folder:SetAttribute(replication.ATTRIBUTE_PHASE_ENDS_AT, endsAt)
	folder:SetAttribute(replication.ATTRIBUTE_PHASE_DURATION, durationSeconds)
	folder:SetAttribute(replication.ATTRIBUTE_ROUND_ID, currentRoundId)

	for _, listener in phaseListeners do
		task.spawn(listener, newPhase, endsAt, durationSeconds, currentRoundId)
	end
end

local function transitionTo(newPhase: string, durationSeconds: number): ()
	assertTransitionIsLegal(currentPhase, newPhase)
	publishPhase(newPhase, durationSeconds)
end

--==============================================================
-- Deteccao de jogadores no pad
--==============================================================

local function isPositionOnPad(pad: BasePart, position: Vector3): boolean
	local localPosition = pad.CFrame:PointToObjectSpace(position)
	local halfSize = pad.Size * 0.5
	local verticalTolerance = GameConstants.Lobby.PAD_VERTICAL_TOLERANCE_STUDS

	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Z) <= halfSize.Z
		and math.abs(localPosition.Y) <= halfSize.Y + verticalTolerance
end

local function countPlayersOnPad(): number
	local pad = startPad
	if not pad then
		return 0
	end

	local playersOnPad = 0

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") and isPositionOnPad(pad, rootPart.Position) then
			playersOnPad += 1
		end
	end

	return playersOnPad
end

local function hasMinimumPlayers(): boolean
	return #Players:GetPlayers() >= GameConstants.Lobby.MINIMUM_PLAYERS_TO_START
end

local function serverIsEmpty(): boolean
	return #Players:GetPlayers() < GameConstants.Lobby.MINIMUM_PLAYERS_TO_START
end

--==============================================================
-- Primitivas de espera interrompivel
--==============================================================

--[[
	Espera 'durationSeconds' em fatias curtas, permitindo abortar.
	Retorna true se a fase completou; false se foi interrompida.
]]
local function waitPhase(durationSeconds: number, shouldAbort: AbortPredicate?): boolean
	local tickInterval = GameConstants.Loop.TICK_INTERVAL_SECONDS
	local deadline = os.clock() + durationSeconds

	while isRunning and os.clock() < deadline do
		if shouldAbort and shouldAbort() then
			return false
		end
		task.wait(tickInterval)
	end

	return isRunning
end

--[[
	Bloqueia no Lobby ate haver jogador suficiente E alguem no pad.
	Retorna false apenas se o loop foi encerrado.
]]
local function waitForPadActivation(): boolean
	local tickInterval = GameConstants.Loop.TICK_INTERVAL_SECONDS

	while isRunning do
		if hasMinimumPlayers() and countPlayersOnPad() > 0 then
			return true
		end
		task.wait(tickInterval)
	end

	return false
end

--==============================================================
-- Loop principal
--==============================================================

local function shouldCancelCountdown(): boolean
	if serverIsEmpty() then
		return true
	end

	if GameConstants.Lobby.CANCEL_COUNTDOWN_WHEN_PAD_EMPTY then
		return countPlayersOnPad() == 0
	end

	return false
end

local function runResetPhase(): ()
	transitionTo(Phase.Reset, GameConstants.Round.RESET_SECONDS)
	waitPhase(GameConstants.Round.RESET_SECONDS, nil)
end

local function runGameLoop(): ()
	local lobbyConstants = GameConstants.Lobby
	local roundConstants = GameConstants.Round

	while isRunning do
		transitionTo(Phase.Lobby, 0)

		if not waitForPadActivation() then
			break
		end

		transitionTo(Phase.Starting, lobbyConstants.COUNTDOWN_SECONDS)
		local countdownCompleted = waitPhase(lobbyConstants.COUNTDOWN_SECONDS, shouldCancelCountdown)

		if not countdownCompleted then
			continue
		end

		if not hasMinimumPlayers() then
			continue
		end

		currentRoundId += 1

		transitionTo(Phase.Building, roundConstants.BUILDING_SECONDS)
		if not waitPhase(roundConstants.BUILDING_SECONDS, serverIsEmpty) then
			if not isRunning then
				break
			end
			runResetPhase()
			continue
		end

		transitionTo(Phase.Disaster, roundConstants.DISASTER_SECONDS)
		if not waitPhase(roundConstants.DISASTER_SECONDS, serverIsEmpty) then
			if not isRunning then
				break
			end
			runResetPhase()
			continue
		end

		transitionTo(Phase.Climax, roundConstants.CLIMAX_SECONDS)
		if not waitPhase(roundConstants.CLIMAX_SECONDS, nil) then
			break
		end

		runResetPhase()
	end
end

--==============================================================
-- API publica
--==============================================================

function GameLoopManager.init(): ()
	if isInitialized then
		error("[GameLoopManager] init() chamado duas vezes.", 2)
	end

	local replication = GameConstants.Replication
	local lobbyConstants = GameConstants.Lobby

	if ReplicatedStorage:FindFirstChild(replication.STATE_FOLDER_NAME) then
		error(
			string.format(
				"[GameLoopManager] '%s' ja existe em ReplicatedStorage. Instancia residual no place?",
				replication.STATE_FOLDER_NAME
			),
			2
		)
	end

	local lobbyFolder = Workspace:FindFirstChild(lobbyConstants.LOBBY_FOLDER_NAME)
	if not lobbyFolder then
		error(
			string.format("[GameLoopManager] Workspace.%s ausente.", lobbyConstants.LOBBY_FOLDER_NAME),
			2
		)
	end

	local pad = lobbyFolder:FindFirstChild(lobbyConstants.START_PAD_NAME)
	if not pad or not pad:IsA("BasePart") then
		error(
			string.format(
				"[GameLoopManager] Workspace.%s.%s ausente ou nao e BasePart.",
				lobbyConstants.LOBBY_FOLDER_NAME,
				lobbyConstants.START_PAD_NAME
			),
			2
		)
	end
	startPad = pad

	local folder = Instance.new("Folder")
	folder.Name = replication.STATE_FOLDER_NAME
	folder:SetAttribute(replication.ATTRIBUTE_PHASE, Phase.Lobby)
	folder:SetAttribute(replication.ATTRIBUTE_PHASE_ENDS_AT, 0)
	folder:SetAttribute(replication.ATTRIBUTE_PHASE_DURATION, 0)
	folder:SetAttribute(replication.ATTRIBUTE_ROUND_ID, 0)
	folder.Parent = ReplicatedStorage
	stateFolder = folder

	isInitialized = true
end

function GameLoopManager.start(): ()
	if not isInitialized then
		error("[GameLoopManager] start() chamado antes de init().", 2)
	end
	if isRunning then
		error("[GameLoopManager] start() chamado com o loop ja em execucao.", 2)
	end

	isRunning = true
    task.spawn(runGameLoop)
end

function GameLoopManager.stop(): ()
	isRunning = false
	table.clear(phaseListeners)
end

--[[
	Registra um observador de mudanca de fase.
	Retorna a funcao de cancelamento — chama-la e responsabilidade do chamador.
]]
function GameLoopManager.onPhaseChanged(listener: PhaseChangedListener): () -> ()
	nextListenerId += 1
	local listenerId = nextListenerId
	phaseListeners[listenerId] = listener

	return function()
		phaseListeners[listenerId] = nil
	end
end

function GameLoopManager.getPhase(): string?
	return currentPhase
end

function GameLoopManager.getRoundId(): number
	return currentRoundId
end

function GameLoopManager.getSecondsRemaining(): number
	if currentPhaseEndsAt <= 0 then
		return 0
	end
	return math.max(0, currentPhaseEndsAt - Workspace:GetServerTimeNow())
end

return GameLoopManager