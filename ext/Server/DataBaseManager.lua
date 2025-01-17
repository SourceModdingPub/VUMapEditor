---@class DataBaseManager
DataBaseManager = class 'DataBaseManager'

local m_Logger = Logger("DataBaseManager", false)

local m_DB_Header_Table_Name = "project_header"
local m_ProjectName_Unique_Index = "idx_project_name"
local m_ProjectName_Text_Column_Name = "project_name"
local m_MapName_Text_Column_Name = "map_name"
local m_GameModeName_Text_Column_Name = "gamemode_name"
local m_RequiredBundles_Text_Column_Name = "required_bundles"
local m_SaveVersion_Text_Column_Name = "save_version"
local m_TimeStamp_Text_Column_Name = "timestamp"

local m_DB_Data_Table_Name = "project_data"
local m_ProjectHeader_Id_Column_Name = "project_header_id"
local m_SaveFile_Text_Column_Name = "save_file_json"

function DataBaseManager:__init()
	m_Logger:Write("Initializing DataBaseManager")

	---@type string
	self.m_ExportHeaderName = "header"
	---@type string
	self.m_ExportDataName = "data"

	self:CreateOrUpdateDatabase()
	--TODO: maybe update all project save files' structure if they are not up-to-date?
end

---@param p_ProjectName string
---@param p_MapName string
---@param p_GameModeName string
---@param p_RequiredBundles table|string
---@param p_GameObjectSaveDatas table|string
---@param p_SaveVersion string
---@param p_TimeStamp number|nil
---@return boolean success, string|nil errorMessage
function DataBaseManager:SaveProject(p_ProjectName, p_MapName, p_GameModeName, p_RequiredBundles, p_GameObjectSaveDatas, p_SaveVersion, p_TimeStamp)
	local s_TimeStamp = p_TimeStamp or SharedUtils:GetTimeMS()

	local s_GameObjectSaveDatasJson = p_GameObjectSaveDatas
	local s_RequiredBundlesJson = p_RequiredBundles

	if type(p_GameObjectSaveDatas) ~= 'string' then
		s_GameObjectSaveDatasJson = json.encode(p_GameObjectSaveDatas)
	end
	---@cast s_GameObjectSaveDatasJson -table

	-- Round transform numbers to 3 decimals
	s_GameObjectSaveDatasJson = string.gsub(s_GameObjectSaveDatasJson, '(%"[xyz]%":%s*)([-]?%d+%.%d+)', function(prefix, n)
		return prefix .. string.format("%.3f", tonumber(n))
	end)

	if type(p_RequiredBundles) ~= 'string' then
		s_RequiredBundlesJson = json.encode(p_RequiredBundles)
	end
	---@cast s_RequiredBundlesJson -table

	local s_Success, s_ErrorMsg, s_HeaderId = self:SaveProjectHeader(p_ProjectName, p_MapName, p_GameModeName, s_RequiredBundlesJson, p_SaveVersion, s_TimeStamp)

	if s_Success then
		---@cast s_HeaderId -nil
		return self:SaveProjectData(s_HeaderId, s_GameObjectSaveDatasJson)
	else
		return s_Success, s_ErrorMsg
	end
end

function DataBaseManager:CreateOrUpdateDatabase()
	m_Logger:Write("DataBaseManager:CreateOrUpdateDatabase()")

	if not SQL:Open() then
		return
	end

	-- Create our data table:
	local s_CreateProjectHeaderTableQuery = [[
		CREATE TABLE IF NOT EXISTS ]] .. m_DB_Header_Table_Name .. [[ (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			]] .. m_ProjectName_Text_Column_Name .. [[ TEXT,
			]] .. m_MapName_Text_Column_Name .. [[ TEXT,
			]] .. m_GameModeName_Text_Column_Name .. [[ TEXT,
			]] .. m_RequiredBundles_Text_Column_Name .. [[ TEXT,
			]] .. m_TimeStamp_Text_Column_Name .. [[ INTEGER,
			]] .. m_SaveVersion_Text_Column_Name .. [[ TEXT
		);

		CREATE UNIQUE INDEX IF NOT EXISTS ]] .. m_ProjectName_Unique_Index .. [[ ON ]] .. m_DB_Header_Table_Name .. [[(]] .. m_ProjectName_Text_Column_Name .. [[);
	]]

	-- m_Logger:Write(createProjectHeaderTableQuery)

	if not SQL:Query(s_CreateProjectHeaderTableQuery) then
		m_Logger:Error('Failed to execute query: ' .. SQL:Error())
		return
	end


	-- Add column if it doesn't exist (Added in savefile version 0.1.0)
	if not SQL:Query('SELECT ' .. m_SaveVersion_Text_Column_Name .. ' FROM ' .. m_DB_Header_Table_Name) then
		if not SQL:Query('ALTER TABLE ' .. m_DB_Header_Table_Name.. ' ADD COLUMN ' .. m_SaveVersion_Text_Column_Name .. ';') then
			m_Logger:Error('Failed to create save version column')
		end
		m_Logger:Write('Added save version column successfully')
	end

	-- Create our data table:
	local s_CreateProjectDataTableQuery = [[
		CREATE TABLE IF NOT EXISTS ]] .. m_DB_Data_Table_Name .. [[ (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			]] .. m_ProjectHeader_Id_Column_Name .. [[ INTEGER REFERENCES ]] .. m_DB_Header_Table_Name.. [[(id) ON DELETE CASCADE,
			]] .. m_SaveFile_Text_Column_Name .. [[ TEXT
		);
	]]

	if not SQL:Query(s_CreateProjectDataTableQuery) then
		m_Logger:Error('Failed to execute query: ' .. SQL:Error())
		return
	end

	m_Logger:Write("Successfully created database!")
end

---@param p_ProjectName string
---@param p_MapName string
---@param p_GameModeName string
---@param p_RequiredBundlesJson string
---@param p_SaveVersion string
---@param p_TimeStamp number
---@return boolean success, string|nil errorMessage, number|nil headerId
function DataBaseManager:SaveProjectHeader(p_ProjectName, p_MapName, p_GameModeName, p_RequiredBundlesJson, p_SaveVersion, p_TimeStamp)
	if p_ProjectName == nil or type(p_ProjectName) ~= "string" then
		return false, "Failed to save Project - header.projectName is invalid: " .. tostring(p_ProjectName)
	end

	if p_MapName == nil or type(p_MapName) ~= "string" then
		return false, "Failed to save Project - header.mapName is invalid: " .. tostring(p_MapName)
	end

	if p_GameModeName == nil or type(p_GameModeName) ~= "string" then
		return false, "Failed to save Project - header.gameModeName is invalid: " .. tostring(p_GameModeName)
	end

	if p_RequiredBundlesJson == nil or type(p_RequiredBundlesJson) ~= "string" then
		return false, "Failed to save Project - header.requiredBundles is invalid: " .. tostring(p_RequiredBundlesJson)
	end

	if p_SaveVersion == nil or type(p_SaveVersion) ~= "string" then
		return false, "Failed to save Project - header.saveVersion is invalid: " .. tostring(p_SaveVersion)
	end

	if p_TimeStamp == nil or type(p_TimeStamp) ~= "number" then
		return false, "Failed to save Project - header.timeStamp is invalid: " .. tostring(p_TimeStamp)
	end

	local s_Query = [[INSERT OR REPLACE INTO ]] .. m_DB_Header_Table_Name .. [[ (]] .. m_ProjectName_Text_Column_Name .. [[, ]] .. m_MapName_Text_Column_Name .. [[, ]] .. m_GameModeName_Text_Column_Name .. [[, ]] .. m_RequiredBundles_Text_Column_Name .. [[, ]] .. m_SaveVersion_Text_Column_Name .. [[, ]] .. m_TimeStamp_Text_Column_Name ..[[) VALUES (?, ?, ?, ?, ?, ?)]]

	m_Logger:Write("Inserting values:")
	m_Logger:Write(p_ProjectName .. " | " .. p_MapName .. " | " .. p_GameModeName .. " | " .. p_RequiredBundlesJson .. " | " .. p_SaveVersion .. " | " .. tostring(p_TimeStamp))

	if not SQL:Query(s_Query, p_ProjectName, p_MapName, p_GameModeName, p_RequiredBundlesJson, p_SaveVersion, p_TimeStamp) then
		m_Logger:Error('Failed to execute query: ' .. SQL:Error())
		return false, 'Internal database error, check server output for more info'
	end

	m_Logger:Write('Inserted header. Insert ID: ' .. tostring(SQL:LastInsertId()) .. '. Rows affected: ' .. tostring(SQL:AffectedRows()))
	return true, nil, SQL:LastInsertId()
end

---@param p_HeaderId number
---@param p_GameObjectSaveDatasJson string
---@return boolean success, string|nil errorMessage
function DataBaseManager:SaveProjectData(p_HeaderId, p_GameObjectSaveDatasJson)
	m_Logger:Write("SaveProjectData() " .. tostring(p_HeaderId))
	--m_Logger:Write(p_GameObjectSaveDatasJson)

	local s_Query = 'INSERT INTO ' .. m_DB_Data_Table_Name .. ' (' .. m_ProjectHeader_Id_Column_Name .. ', ' .. m_SaveFile_Text_Column_Name .. ') VALUES (?, ?)'

	m_Logger:Write(s_Query)

	if not SQL:Query(s_Query, p_HeaderId, p_GameObjectSaveDatasJson) then
		m_Logger:Error('Failed to execute query: ' .. SQL:Error())
		return false, 'Internal database error, check server output for more info'
	end

	m_Logger:Write('Inserted data. Insert ID: ' .. tostring(SQL:LastInsertId()) .. '. Rows affected: ' .. tostring(SQL:AffectedRows()))
	return true
end

---@return ProjectHeader[]|nil projectHeaders
function DataBaseManager:GetProjectHeaders()
	local s_ProjectHeaderRows = SQL:Query('SELECT * FROM ' .. m_DB_Header_Table_Name)

	if not s_ProjectHeaderRows then
		m_Logger:Error('Failed to execute query: ' .. SQL:Error())
		return
	end

	---@type ProjectHeader[]
	local s_ProjectHeaders = { }

	for _, l_Row in pairs(s_ProjectHeaderRows) do
		---@type ProjectHeader
		local s_Header = {
			projectName = l_Row[m_ProjectName_Text_Column_Name],
			mapName = l_Row[m_MapName_Text_Column_Name],
			gameModeName = l_Row[m_GameModeName_Text_Column_Name],
			requiredBundles = json.decode(l_Row[m_RequiredBundles_Text_Column_Name]),
			timeStamp = l_Row[m_TimeStamp_Text_Column_Name],
			saveVersion = l_Row[m_SaveVersion_Text_Column_Name],
			id = l_Row['id']
		}

		table.insert(s_ProjectHeaders, s_Header)
	end

	return s_ProjectHeaders
end

---@param p_ProjectId number
---@return ProjectHeader|nil projectHeader
function DataBaseManager:GetProjectHeader(p_ProjectId)
	local s_ProjectIdInt = math.floor(p_ProjectId)

	m_Logger:Write("GetProjectHeader()" .. s_ProjectIdInt)

	local s_ProjectHeaderRow = SQL:Query('SELECT * FROM ' .. m_DB_Header_Table_Name .. ' WHERE '.. 'id' .. ' = ' .. s_ProjectIdInt .. ' LIMIT 1')

	if not s_ProjectHeaderRow then
		m_Logger:Error('Failed to execute query: ' .. SQL:Error())
		return
	end

	---@type ProjectHeader
	local s_Header = {
		projectName = s_ProjectHeaderRow[1][m_ProjectName_Text_Column_Name],
		mapName = s_ProjectHeaderRow[1][m_MapName_Text_Column_Name],
		gameModeName = s_ProjectHeaderRow[1][m_GameModeName_Text_Column_Name],
		requiredBundles = json.decode(s_ProjectHeaderRow[1][m_RequiredBundles_Text_Column_Name]),
		timeStamp = s_ProjectHeaderRow[1][m_TimeStamp_Text_Column_Name],
		saveVersion = s_ProjectHeaderRow[1][m_SaveVersion_Text_Column_Name],
		id = s_ProjectHeaderRow[1]['id']
	}

	return s_Header
end

---@param p_ProjectId number
---@return string|nil
function DataBaseManager:GetProjectDataJSONByProjectId(p_ProjectId)
	local s_ProjectIdInt = math.floor(p_ProjectId)
	m_Logger:Write("GetProjectDataJSONByProjectId()" .. s_ProjectIdInt)

	local s_ProjectDataTable = SQL:Query('SELECT ' .. m_SaveFile_Text_Column_Name .. ' FROM ' .. m_DB_Data_Table_Name .. ' WHERE '.. m_ProjectHeader_Id_Column_Name .. ' = ' .. s_ProjectIdInt .. ' LIMIT 1')

	if not s_ProjectDataTable then
		m_Logger:Error('Failed to execute query: ' .. SQL:Error())
		return
	end

	local s_ProjectDataJSON = s_ProjectDataTable[1][m_SaveFile_Text_Column_Name]

	if not s_ProjectDataJSON then
		m_Logger:Error('Failed to get project data')
		return
	end

	return s_ProjectDataJSON
end

---@param p_ProjectId number
---@return ProjectDataEntry[]|nil projectData
function DataBaseManager:GetProjectDataByProjectId(p_ProjectId)
	local s_ProjectDataJSON = self:GetProjectDataJSONByProjectId(p_ProjectId)

	if not s_ProjectDataJSON then
		return
	end

	local s_ProjectData = DecodeParams(json.decode(s_ProjectDataJSON))
	---@cast s_ProjectData ProjectDataEntry[]

	if not s_ProjectData then
		m_Logger:Error('Failed to decode project data')
		return
	end

	return s_ProjectData
end

---@param p_ProjectId number
---@return ProjectSave|nil
function DataBaseManager:GetProjectByProjectId(p_ProjectId)
	m_Logger:Write("GetProjectByProjectId()" .. p_ProjectId)

	local s_ProjectData = self:GetProjectDataByProjectId(p_ProjectId)
	local s_Header = self:GetProjectHeader(p_ProjectId)

	if s_ProjectData == nil or s_Header == nil then
		m_Logger:Error('Failed to get project save')
		return
	end

	---@type ProjectSave
	return {
		[self.m_ExportHeaderName] = s_Header,
		[self.m_ExportDataName] = s_ProjectData
	}
end

---@param p_ProjectId number
---@return boolean success
function DataBaseManager:DeleteProject(p_ProjectId)
	m_Logger:Write("DeleteProject()" .. p_ProjectId)

	local s_ProjectHeader = self:GetProjectHeader(p_ProjectId)

	if not s_ProjectHeader then
		m_Logger:Error("Invalid project id")
		return false
	end

	SQL:Query('DELETE FROM ' .. m_DB_Header_Table_Name .. ' WHERE id = ' .. s_ProjectHeader.id) -- this should cascade delete the according data table
	SQL:Query('DELETE FROM ' .. m_DB_Data_Table_Name .. ' WHERE '.. m_ProjectHeader_Id_Column_Name .. ' = ' .. s_ProjectHeader.id)
	return true
end

DataBaseManager = DataBaseManager()

return DataBaseManager
