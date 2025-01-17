---@class ProjectManager
ProjectManager = class 'ProjectManager'

local m_Logger = Logger("ProjectManager", false)

local SAVE_VERSION = "0.1.1"

function ProjectManager:__init()
	m_Logger:Write("Initializing ProjectManager")

	self.m_CurrentProjectHeader = nil -- dont reset this, is required info for map restart
	self.m_ProjectLoadingState = ProjectLoadingState.Loaded

	self:RegisterVars()
	self:RegisterEvents()
end

function ProjectManager:RegisterVars()
	self.m_MapName = nil
	self.m_GameMode = nil
	self.m_LoadedBundles = {}
end

function ProjectManager:RegisterEvents()
	NetEvents:Subscribe('ProjectManager:RequestProjectHeaders', self, self.OnRequestProjectHeaders)
	NetEvents:Subscribe('ProjectManager:RequestProjectHeaderUpdate', self, self.UpdateClientProjectHeader)
	NetEvents:Subscribe('ProjectManager:RequestProjectData', self, self.OnRequestProjectData)
	NetEvents:Subscribe('ProjectManager:RequestProjectSave', self, self.OnRequestProjectSave)
	NetEvents:Subscribe('ProjectManager:RequestProjectLoad', self, self.OnRequestProjectLoad)
	NetEvents:Subscribe('ProjectManager:RequestProjectDelete', self, self.OnRequestProjectDelete)
	NetEvents:Subscribe('ProjectManager:RequestProjectImport', self, self.OnRequestProjectImport)
end

function ProjectManager:OnLoadBundles(p_Bundles, p_Compartment)
	for _, l_Bundle in pairs(p_Bundles) do
		self.m_LoadedBundles[l_Bundle] = true
	end
end

---@param p_Player Player
function ProjectManager:OnRequestProjectHeaders(p_Player)
	if p_Player == nil then -- update all players
		NetEvents:BroadcastLocal("MapEditorClient:ReceiveProjectHeaders", DataBaseManager:GetProjectHeaders())
		self:UpdateClientProjectHeader(nil)
	else
		NetEvents:SendToLocal("MapEditorClient:ReceiveProjectHeaders", p_Player, DataBaseManager:GetProjectHeaders())
		self:UpdateClientProjectHeader(p_Player)
	end
end

---@param p_Player Player|nil
function ProjectManager:UpdateClientProjectHeader(p_Player)
	if self.m_CurrentProjectHeader == nil then
		self.m_CurrentProjectHeader = {
			projectName = 'Untitled Project',
			mapName = self.m_MapName,
			gameModeName = self.m_GameMode,
			requiredBundles = self.m_LoadedBundles
		}
	end

	if p_Player == nil then -- update all players
		NetEvents:BroadcastLocal("MapEditorClient:ReceiveCurrentProjectHeader", self.m_CurrentProjectHeader)
	else
		NetEvents:SendToLocal("MapEditorClient:ReceiveCurrentProjectHeader", p_Player, self.m_CurrentProjectHeader)
	end
end

---@param p_Player Player
---@param p_ProjectId integer
function ProjectManager:OnRequestProjectData(p_Player, p_ProjectId)
	m_Logger:Write("Data requested: " .. p_ProjectId)

	local s_ProjectData = DataBaseManager:GetProjectByProjectId(p_ProjectId)

	NetEvents:SendToLocal("MapEditorClient:ReceiveProjectData", p_Player, s_ProjectData)
end

---@param p_Player Player
---@param p_ProjectId integer
function ProjectManager:OnRequestProjectDelete(p_Player, p_ProjectId)
	m_Logger:Write("Delete requested: " .. p_ProjectId)

	--TODO: if the project that gets deleted is the currently loaded project, we need to clear all data and reload an empty map.
	local s_Success = DataBaseManager:DeleteProject(p_ProjectId)

	if s_Success then
		NetEvents:BroadcastLocal("MapEditorClient:ReceiveProjectHeaders", DataBaseManager:GetProjectHeaders())
	end
end

---@param p_ProjectSave ProjectSave
---@return ProjectSave|nil projectSave, string|nil errorMessage
function ProjectManager:UpgradeSaveStructure(p_ProjectSave)
	local s_SaveVersion = p_ProjectSave[DataBaseManager.m_ExportDataName].saveVersion

	if s_SaveVersion == nil then -- Save from before versioning was implemented, try to upgrade to current version
		local s_Data = p_ProjectSave[DataBaseManager.m_ExportDataName]

		-- Some pre-versioning save files had an isVanilla flag
		for _, l_DataEntry in pairs(s_Data) do
			if l_DataEntry.isVanilla ~= nil then
				l_DataEntry.origin = GameObjectOriginType.Vanilla and l_DataEntry.isVanilla or GameObjectOriginType.Custom
				l_DataEntry.isVanilla = nil
			end
		end

		p_ProjectSave[DataBaseManager.m_ExportHeaderName].saveVersion = SAVE_VERSION

		return p_ProjectSave
	elseif s_SaveVersion > SAVE_VERSION then
		return nil, 'Importing save with a higher save format version than supported, please update MapEditor before importing'
	else
		-- New version updates are handled here

		-- Update save version
		p_ProjectSave[DataBaseManager.m_ExportHeaderName].saveVersion = SAVE_VERSION
		return p_ProjectSave
	end
end

---@param p_Player Player
---@param p_ProjectSaveJSON string
function ProjectManager:OnRequestProjectImport(p_Player, p_ProjectSaveJSON)
	m_Logger:Write("Import requested")

	local s_ProjectSave, s_Msg = self:ParseJSONProject(p_ProjectSaveJSON)
	local s_Success = s_ProjectSave ~= nil

	-- Update save structure to newest save version
	if s_ProjectSave then
		if not s_ProjectSave[DataBaseManager.m_ExportHeaderName].saveVersion or s_ProjectSave[DataBaseManager.m_ExportHeaderName].saveVersion ~= SAVE_VERSION then
			m_Logger:Write('Older save version found, updating to newest save structure..')

			s_ProjectSave, s_Msg = self:UpgradeSaveStructure(s_ProjectSave)
			s_Success = s_ProjectSave ~= nil
		end
	end

	-- Attempt saving the project
	if s_ProjectSave then
		local s_Header = s_ProjectSave[DataBaseManager.m_ExportHeaderName]
		local s_Data = s_ProjectSave[DataBaseManager.m_ExportDataName]

		s_Success, s_Msg = DataBaseManager:SaveProject(s_Header.projectName, s_Header.mapName, s_Header.gameModeName, s_Header.requiredBundles, s_Data, s_Header.saveVersion, s_Header.timeStamp)
	end

	if s_Success then
		m_Logger:Write('Correctly imported save file')
		-- Update clients with new save.
		NetEvents:BroadcastLocal("MapEditorClient:ReceiveProjectHeaders", DataBaseManager:GetProjectHeaders())
	else
		m_Logger:Write('Error importing save file: ' .. s_Msg)
	end

	s_Msg = s_Msg or 'Successfully imported save file.'

	NetEvents:SendToLocal("MapEditorClient:ProjectImportFinished", p_Player, s_Msg)
end

---@param p_ProjectSaveJSON string
---@return ProjectSave|nil projectSave, string|nil errorMessage
function ProjectManager:ParseJSONProject(p_ProjectSaveJSON)
	local s_ProjectSave = json.decode(p_ProjectSaveJSON)

	if s_ProjectSave == nil then
		return nil, 'Incorrect save format'
	end

	local s_Header = s_ProjectSave[DataBaseManager.m_ExportHeaderName]
	local s_Data = s_ProjectSave[DataBaseManager.m_ExportDataName]

	if s_Header == nil then
		return nil, 'Save file is missing header '
	end

	if s_Data == nil then
		return nil, 'Save file is missing data'
	end

	if s_Header.projectName == nil or
		s_Header.mapName == nil or
		s_Header.gameModeName == nil or
		-- s_Header.saveVersion == nil or -- not required, old saves didn't have it
		s_Header.requiredBundles == nil then
		return nil, 'Save header missing necessary field(s)'
	end

	return { [DataBaseManager.m_ExportHeaderName] = s_Header, [DataBaseManager.m_ExportDataName] = s_Data }
end

---@param p_Map string
---@param p_GameMode string
---@param p_Round integer
function ProjectManager:OnLevelLoaded(p_Map, p_GameMode, p_Round)
	if self.m_ProjectLoadingState == ProjectLoadingState.PendingLevelLoad then
		self.m_ProjectLoadingState = ProjectLoadingState.PendingProjectLoad
	end

	self.m_MapName = p_Map:gsub(".*/", "")
	self.m_GameMode = p_GameMode:gsub(".*/", "")
end

function ProjectManager:OnUpdatePass(p_Delta, p_Pass)
	if p_Pass ~= UpdatePass.UpdatePass_PreSim then
		return
	end

	if self.m_ProjectLoadingState == ProjectLoadingState.PendingProjectLoad then
		if self.m_CurrentProjectHeader == nil or self.m_CurrentProjectHeader.id == nil or self.m_CurrentProjectHeader.projectName == nil then
			self.m_CurrentProjectHeader = ProjectLoadingState.Loaded
			m_Logger:Warning('Pending load of project cancelled due to missing project data')
			return
		end

		self.m_ProjectLoadingState = ProjectLoadingState.Loaded

		if self.m_MapName:gsub(".*/", "") ~= self.m_CurrentProjectHeader.mapName:gsub(".*/", "") then
			m_Logger:Error("Can't load project that is not built for the same map as current one. Current: " .. tostring(self.m_MapName) .. ", target: " .. tostring(self.m_CurrentProjectHeader.mapName))
			return
		end

		local s_ProjectSave = DataBaseManager:GetProjectByProjectId(self.m_CurrentProjectHeader.id)

		if s_ProjectSave == nil then
			m_Logger:Error("Can't load project, not found in database.")
			return
		end

		m_Logger:Write('Loading project save')

		-- Upgrade if necessary
		local s_Msg
		s_ProjectSave, s_Msg = self:UpgradeSaveStructure(s_ProjectSave)

		if s_ProjectSave == nil then
			m_Logger:Error("Can't load project. Error: " .. tostring(s_Msg))
			return
		end

		self:CreateAndExecuteImitationCommands(s_ProjectSave[DataBaseManager.m_ExportDataName])
	end
end

---@param p_Player Player
---@param p_ProjectId integer
function ProjectManager:OnRequestProjectLoad(p_Player, p_ProjectId)
	m_Logger:Write("Load requested: " .. p_ProjectId)
	-- TODO: check player's permission once that is implemented

	local s_Project = DataBaseManager:GetProjectByProjectId(p_ProjectId)

	if s_Project == nil then
		m_Logger:Error('Failed to get project with id ' .. tostring(p_ProjectId))
		return
	end

	self.m_ProjectLoadingState = ProjectLoadingState.PendingLevelLoad
	self.m_CurrentProjectHeader = s_Project.header

	local s_MapName = s_Project.header.mapName
	local s_GameModeName = s_Project.header.gameModeName

	if s_MapName == nil or
		Maps[s_MapName] == nil or
		s_GameModeName == nil or
		GameModes[s_GameModeName] == nil then

		m_Logger:Error("Failed to load project, one or more fields of the project header are not set: " .. s_MapName .. " | " .. s_GameModeName)
		return
	end

	self:UpdateClientProjectHeader(nil)

	-- TODO: Check if we need to delay the restart to ensure all clients have properly updated headers. Would be nice to show a 'Loading Project' screen too (?)
	-- Invoke Restart
	if self.m_MapName == s_MapName then
		--Events:Dispatch('MapLoader:LoadLevel', { header = s_Project.header, data = s_Project.data, vanillaOnly = true })
		RCON:SendCommand('mapList.restartRound')
	else
		local s_Response = RCON:SendCommand('mapList.clear')
		if s_Response[1] ~= 'OK' then
			m_Logger:Error('Couldn\'t clear maplist. ' .. s_Response[1])
			return
		end

		s_Response = RCON:SendCommand('mapList.add', { s_MapName, s_GameModeName, '1' }) -- TODO: add proper map / gameplay support
		if s_Response[1] ~= 'OK' then
			m_Logger:Error('Couldn\'t add map to maplist. ' .. s_Response[1])
		end

		s_Response = RCON:SendCommand('mapList.runNextRound')
		if s_Response[1] ~= 'OK' then
			m_Logger:Error('Couldn\'t run next round. ' .. s_Response[1])
		end
	end
end

function ProjectManager:OnRequestProjectSave(p_Player, p_ProjectHeader)
	-- TODO: check player's permission once that is implemented
	self:SaveProjectCoroutine(p_ProjectHeader)
end

---@param p_ProjectHeader ProjectHeader
function ProjectManager:SaveProjectCoroutine(p_ProjectHeader)
	m_Logger:Write("Save requested: " .. p_ProjectHeader.projectName)

	local s_GameObjectSaveDatas = {}
	local s_Count = 0

	-- TODO: get the GameObjectSaveDatas not from the transferdatas array, but from the GO array of the GOManager. (remove the GOTD array)
	for _, l_GameObject in pairs(GameObjectManager.m_GameObjects) do
		if l_GameObject:IsUserModified() == true or l_GameObject:HasOverrides() then
			s_Count = s_Count + 1
			table.insert(s_GameObjectSaveDatas, GameObjectSaveData(l_GameObject):GetAsTable())
		end
	end

	-- m_Logger:Write("vvvvvvvvvvvvvvvvv")
	-- m_Logger:Write("GameObjectSaveDatas: " .. count)
	-- for _, gameObjectSaveData in pairs(s_GameObjectSaveDatas) do
	-- 	m_Logger:Write(tostring(gameObjectSaveData.guid) .. " | " .. gameObjectSaveData.name)
	-- end
	-- m_Logger:Write(json.encode(s_GameObjectSaveDatas))
	-- m_Logger:Write("^^^^^^^^^^^^^^^^^")
	self.m_CurrentProjectHeader = {
		projectName = p_ProjectHeader.projectName,
		mapName = self.m_MapName,
		gameModeName = self.m_GameMode,
		requiredBundles = self.m_LoadedBundles
	}
	local s_Success, s_Msg = DataBaseManager:SaveProject(p_ProjectHeader.projectName, self.m_CurrentProjectHeader.mapName, self.m_CurrentProjectHeader.gameModeName, self.m_LoadedBundles, s_GameObjectSaveDatas, SAVE_VERSION)

	if s_Success then
		NetEvents:BroadcastLocal("MapEditorClient:ReceiveProjectHeaders", DataBaseManager:GetProjectHeaders())
		NetEvents:BroadcastLocal("MapEditorClient:ReceiveCurrentProjectHeader", self.m_CurrentProjectHeader)
	else
		m_Logger:Error(s_Msg)
	end
end

---We're creating commands from the savefile, basically imitating every step that has been undertaken
---@param p_ProjectSaveData ProjectDataEntry[]
function ProjectManager:CreateAndExecuteImitationCommands(p_ProjectSaveData)
	local s_SaveFileCommands = {}

	for _, l_GameObjectSaveData in pairs(p_ProjectSaveData) do
		local s_Guid = l_GameObjectSaveData.guid:upper()

		--if (GameObjectManager.m_GameObjects[l_Guid] == nil) then
		--	m_Logger:Error("GameObject with Guid " .. tostring(l_Guid) .. " not found in GameObjectManager.")
		--end

		local s_Command

		-- Vanilla and nohavok objects are handled in levelloader
		if l_GameObjectSaveData.origin == GameObjectOriginType.Vanilla or
			l_GameObjectSaveData.origin == GameObjectOriginType.NoHavok then
			if l_GameObjectSaveData.isDeleted then
				s_Command = {
					guid = s_Guid,
					sender = "LoadingSaveFile",
					type = CommandActionType.DeleteGameObjectCommand,
					gameObjectTransferData = {
						guid = s_Guid
					}
				}
			else
				s_Command = {
					guid = s_Guid,
					sender = "LoadingSaveFile",
					type = CommandActionType.SetTransformCommand,
					gameObjectTransferData = {
						guid = s_Guid,
						transform = l_GameObjectSaveData.transform
					}
				}
			end

			table.insert(s_SaveFileCommands, s_Command)
		elseif l_GameObjectSaveData.origin == GameObjectOriginType.CustomChild then
			-- TODO Fool: Handle custom objects' children, they should be handled after the parent is spawned
		else
			s_Command = {
				guid = s_Guid,
				sender = "LoadingSaveFile",
				type = CommandActionType.SpawnGameObjectCommand,
				gameObjectTransferData = { -- We're not using the actual type, i think its because of json serialization fuckups
					guid = s_Guid,
					name = l_GameObjectSaveData.name,
					blueprintCtrRef = l_GameObjectSaveData.blueprintCtrRef,
					parentData = l_GameObjectSaveData.parentData or GameObjectParentData:GetRootParentData(),
					transform = l_GameObjectSaveData.transform,
					variation = l_GameObjectSaveData.variation or 0,
					gameEntities = {},
					isEnabled = l_GameObjectSaveData.isEnabled or true,
					isDeleted = l_GameObjectSaveData.isDeleted or false,
					overrides = l_GameObjectSaveData.overrides
				}
			}

			table.insert(s_SaveFileCommands, s_Command)
		end
	end

	ServerTransactionManager:QueueCommands(s_SaveFileCommands)
	ServerTransactionManager:SetLoadingProjectLastTransactionId(#s_SaveFileCommands)
end

ProjectManager = ProjectManager()

return ProjectManager
