--
-- SettingsUtils
-- 
-- Module and settings information are handled here
--
-- @author:    	Xentro (Marcus@Xentro.se)
-- @website:	www.Xentro.se
-- 

GameExtension.modules 			= {};
GameExtension.moduleToIndex 	= {};
GameExtension.settingToIndex 	= {};
GameExtension.blackListState	= {};

GameExtension.BL_STATE_NORMAL 	 = 0;
GameExtension.BL_STATE_DONT_SHOW = 1; -- Don't show in gui, will save
GameExtension.BL_STATE_NOTHING 	 = 2; -- Won't show or save setting

-- Black List --

function GameExtension:getBlackListItem(name)
	if self.blackListState[name] ~= nil then
		return self.blackListState[name];
	end;
	
	return GameExtension.BL_STATE_NORMAL;
end;

function GameExtension:addBlackListItem(name, state)
	self.blackListState[name] = state;
end;


-- Modules --

function GameExtension:getModule(name)
	local idx = self.moduleToIndex[name];
	
	if idx ~= nil then
		return self.modules[idx];
	else
		return nil;
	end;
end;

function GameExtension:addModule(name, object, settings, callClassLocally)
	if self.moduleToIndex[name] == nil then
		local entry = {
			name 			= name,
			object 			= object,
			isActive		= true,
			callLocal		= callClassLocally == nil, -- If you do set this to false beware that function call in your class will not work like this class:function(), it will have to be predefined in the self table. Example self.function = class.function.
			settings 		= Utils.getNoNil(settings, {})
		};
		
		table.insert(self.modules, entry);
		self.moduleToIndex[name] = #self.modules;
	else
		log("ERROR", "Module - The module " .. name .. " already exist's.");
	end;
end;

function GameExtension:deactivateModule(name, modName)
	local m = self:getModule(name);
	
	if m ~= nil then
		m.isActive = false;
		self:addBlackListItem(name, GameExtension.BL_STATE_NOTHING);
		
		log("NOTICE", "Module " .. name .. " is being deactivated by the mod " .. Utils.getNoNil(modName, "MISSING_MOD_NAME"));
	end;
end;


-- Settings --

function GameExtension:getSetting(name, settingName, getTable)
	local m = name;
	
	if type(name) == "string" then
		m = self:getModule(name);
	end;
	
	if m ~= nil then
		local idx = self.settingToIndex[settingName];
		
		if idx ~= nil then
			if not getTable then
				return m.settings[idx].value;
			else
				return m.settings[idx];
			end;
		else
			log("ERROR", "Setting ( " .. tostring(settingName) .. " ) Don't exist.");
		end;
	else
		log("ERROR", "Module ( " .. tostring(name) .. " ) Don't exist.");
	end;
	
	return nil;
end;

function GameExtension:addSetting(settings, t)
	local blackListState = Utils.getNoNil(t.b, GameExtension.BL_STATE_NORMAL);
	local entry = {
		name 		= t.name,
		page 		= string.lower(Utils.getNoNil(t.page, "Client")),
		isMod 		= t.isMod, 			-- Gets translations from other mods.
		inputType 	= type(t.value),
		
		value 		  	= t.value,
		isLocked 		= false, 		-- Don't change this
		isLockedByForce = false, 		-- This can be changed by modders
		func 			= t.f,
		parent 			= t.p,			-- Class from where we will call the func 
		pageData 		= t.pageData	-- 
	};
	
	entry.event = Utils.getNoNil(t.e, entry.page == "server");
	
	if entry.inputType == "string" then
		entry.inputType = Types["STRING"];
	elseif entry.inputType == "number" then
		if string.find(entry.inputType, "%.") ~= nil then
			entry.inputType = Types["FLOAT"];
		else
			entry.inputType = Types["INT"]
		end;
	else
		entry.inputType = string.gsub(entry.inputType, "boolean", Types["BOOL"]);
	end;
	
	if blackListState ~= GameExtension.BL_STATE_NORMAL then
		self:addBlackListItem(entry.name , blackListState);
	end;
	
	if (entry.inputType == Types["FLOAT"] or entry.inputType == Types["INT"]) and blackListState == GameExtension.BL_STATE_NORMAL then
		if t.options ~= nil and t.optionsText then
			log("WARNING", "Setting " .. entry.name .. " have both options and optionsText, will use options.")
		end;
		
		if t.options ~= nil then
			if t.options.isText ~= nil then
				entry.options = t.options;
			else
				entry.options = self:getOptions(t.options);
			end;
		elseif t.optionsText ~= nil then
			entry.options = self:getOptionsText(t.optionsText);
		end;
		
		if entry.options == nil then
			log("ERROR", "Options are empty for setting " .. entry.name .. " which aren't allowed for Float and Int types. Settings won't be added.");
			return settings;
		end;
	end;
	
	if type(settings) == "table" then
		table.insert(settings, entry);
		
		self.settingToIndex[entry.name] = #settings;
		log("DEBUG", "Adding setting index: " .. self.settingToIndex[entry.name] .. ",		type: " .. entry.inputType .. ",	" .. entry.name .. ",		value: " .. tostring(entry.value));
		
		-- Return current table for more settings
		return settings;
	else
		-- Add one setting to module
		self:setSetting(settings, t.name, t, true, true); -- module name, setting name, table
	end;
end;

function GameExtension:setSetting(moduleName, name, newValue, noEventSend, firstLoad)
	local m = self:getModule(moduleName);
	
	if m ~= nil and name ~= nil then
		if not firstLoad then
			local s = self:getSetting(m, name, true);
			
			if s ~= nil then
				s.value = newValue;
				
				if s.func ~= nil then
					if s.parent ~= nil and s.parent[s.func] ~= nil then -- We are custom, we can't use object since it could be wrong.
						s.parent[s.func](s.parent, newValue); -- Call custom setting function
					elseif m.object[s.func] ~= nil then
						if m.callLocal then
							m.object[s.func](m.object, newValue); 			-- This limit us to the class only
						else
							m.object[s.func](self, newValue); 				-- Let us access everything within Game Extension
						end;
					else
						log("ERROR", "The function ( " .. s.func .. " ) for setting ( " .. name .. " ) don't exist.");
					end;
				end;
				
				if g_gameExtension.firstTimeRun then
					if s.event then
						SetSettingEvent.sendEvent(moduleName, name, s.inputType, newValue, noEventSend);
					else
						-- Save client settings when they are changed but only once everything is loaded and ready to go.
						if g_currentMission:getIsClient() and g_dedicatedServerInfo == nil then
							log("DEBUG", "Attempting to save client settings to xml file.")
							self:saveFile(self.filenames.client, false);
						end;
					end;
				end;
			else
				-- Setting don't exist
			end;
		else
			-- Setup setting
			table.insert(m.settings, newValue);
			self.settingToIndex[name] = #m.settings;
			
			log("DEBUG", "Adding setting type: " .. m.settings[self.settingToIndex[name]].inputType .. ",	" .. name .. ",		value: " .. tostring(m.settings[self.settingToIndex[name]].value));
		end;
	else
		-- Module don't exist
		-- log("ERROR", "Trying to change value for an setting in the module ( " .. tostring(moduleName) .. " ) but it doesn't exist.");
	end;
end;


function GameExtension:getLockState(moduleName, settingName, s)
	if s == nil then
		s = self:getSetting(moduleName, settingName, true);
	end;
	
	return s.isLocked or s.isLockedByForce;
end;

function GameExtension:lockSetting(moduleName, settingName, lock, force)
	local s = self:getSetting(moduleName, settingName, true);
	
	if s ~= nil then
		if not force then
			s.isLocked = lock;		  -- This is set by GameExtension
		else
			s.isLockedByForce = lock; -- Modders need to use this!
		end;
		
		-- TODO: Maybe we should be doing an event here?
	end;
end;


-- Setup, Load, Save Settings --

function GameExtension:saveFile(filename, isServer)
	local xmlFile = createXMLFile("savingGameExtension", filename, "GameExtension");
	local i = 0;
	
	-- logTable(GameExtension.blackListState);
	
	for _, m in ipairs(self.modules) do
		if self:getBlackListItem(m.name) ~= GameExtension.BL_STATE_NOTHING then
			-- log("DEBUG", "reading module " .. m.name .. " - isServer: " .. tostring(isServer));
			
			local key, valid = string.format("GameExtension.module(%d)", i), false;
			
			local subI = 0;
			for k, s in ipairs(m.settings) do
				local subKey = string.format(key .. ".setting(%d)", subI);
				
				if self:getBlackListItem(s.name) ~= GameExtension.BL_STATE_NOTHING then
					-- log("DEBUG", "	reading setting " .. s.name .. " 	- page: " .. tostring(s.page) .. " 	- event: " .. tostring(s.event));
					
					if isServer and s.event 					-- Server File
					or not isServer and not s.event then		-- Client File
						setXMLString(xmlFile, subKey .. "#name", s.name);
						
						loadstring("f=setXML" .. s.inputType)();
						f(xmlFile, subKey .. "#value", s.value);
						
						setXMLString(xmlFile, subKey .. "#inputType", s.inputType);
						
						valid = true;
						subI = subI + 1;
						
						-- log("DEBUG", "		" .. s.name .. " - " .. tostring(s.value));
					end;
				end;
			end;
			
			if valid then
				setXMLString(xmlFile, key .. "#name", m.name);
				i = i + 1;
			end;
		end;
	end;
	
	if i > 0 then -- save XML if we got something to save..
		if not saveXMLFile(xmlFile) then
			log("ERROR", "Something failed during saving, Can't save settings - xmlFile: " .. xmlFile .. ", File: " .. filename);
		else
			log("DEBUG", "Saved Settings - xmlFile ID: " .. xmlFile .. " - File Exists: " .. tostring(fileExists(filename)) .. " - File Path: " .. filename);
		end;
	end;
	
	delete(xmlFile);
end;

function GameExtension:loadSettingXML(xmlPath)
	if fileExists(xmlPath) then
		local xmlFile = loadXMLFile("GameExtension", xmlPath);
		local i = 0;
		
		while true do
			local key = string.format("GameExtension.module(%d)", i);
			if not hasXMLProperty(xmlFile, key) then break; end;
			
			local moduleName = getXMLString(xmlFile, key .. "#name");
			if moduleName ~= nil then
				local subI = 0;
				
				while true do
					local subKey = string.format(key .. ".setting(%d)", subI);
					if not hasXMLProperty(xmlFile, subKey) then break; end;
			
					local name = getXMLString(xmlFile, subKey .. "#name");
					local inputType = getXMLString(xmlFile, subKey .. "#inputType");
					local value, entry;
					
					loadstring("f=getXML" .. inputType)();
					value = f(xmlFile, subKey .. "#value");
					
					if value ~= nil then
						g_gameExtension:setSetting(moduleName, name, value, true); -- We check if names exist in function
					end;
					
					subI = subI + 1;
				end;
			end;
			
			i = i + 1;
		end;
		
		delete(xmlFile);
	else
		log("DEBUG", "Settings - Failed to load ( Saved ) settings, file don't exist " .. xmlPath);
	end;
end;

function GameExtension:saveSavegame(superFunc, ...)
	if superFunc ~= nil then
		superFunc(self, ...);
	end;
	
	if g_currentMission:getIsServer() and g_gameExtension ~= nil then
		g_gameExtension:saveFile(g_gameExtension.filenames.server, true);
	end;
	
	-- Don't save client settings here as they are auto saved 
end;
GameExtension:addClassOverride("OVERRIDE_SAVE_GAME", "onSaveComplete", SavegameController, GameExtension.saveSavegame);


-- Send settings to menu

function GameExtension:sendSettingsToMenu()
	for _, m in ipairs(self.modules) do
		if self:getBlackListItem(m.name) == GameExtension.BL_STATE_NORMAL then
			for i, s in ipairs(m.settings) do
				if self:getBlackListItem(s.name) == GameExtension.BL_STATE_NORMAL then
					if g_gameExtensionMenu:getPage(s.page) ~= nil then	-- Add to page
						g_gameExtensionMenu:addSettingsToPage(s.page, {module = m.name, name = s.name});
					else 							 	-- Create page
						if s.pageData ~= nil then
							local entry = {
								pageName = s.pageData.pageName,
								isAdminPage = Utils.getNoNil(s.pageData.isAdminPage, false),
								settings = {{module = m.name, name = s.name}}; -- We only add this one now, the rest will use "Add to page" above.
							};
							
							g_gameExtensionMenu:addSettingsToPage(s.page, entry);
						else
							log("ERROR", "Menu - Missing pageData for page ( ".. s.page .." ), page couldn't be created.");
						end;
					end;
				end;
			end;
		end;
	end;
	
	g_gameExtensionMenu:setIsLoaded(true);
end;