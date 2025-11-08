local Path = require("plenary.path")

local M = {}

-- Get the relative directory of path param,
---@param file string
---@param netrw boolean
---@return string|nil
M.get_project_directory = function(file, netrw)
  local currentMonorepo = require("monorepo").currentMonorepo
  local idx = string.find(file, currentMonorepo, 1, true)
  if idx then
    local relative_path = string.sub(file, idx + #currentMonorepo + 0)
    -- If netrw then string is already a diretory
    if netrw then
      return relative_path
    end
    -- If not netrw then remove filename from string
    local project_directory = string.match(relative_path, "(.-)[^/]+$") -- remove filename
    project_directory = project_directory:sub(1, -2) -- remove trailing slash
    return project_directory
  else
    return nil
  end
end

-- Save monorepoVars to data_path/monorepo.json
M.save = function()
  local monorepoVars = require("monorepo").monorepoVars
  local data_path = require("monorepo").config.data_path
  local persistent_json = data_path .. "/monorepo.json"
  Path:new(persistent_json):write(vim.fn.json_encode(monorepoVars), "w")
end

-- Load json file from data_path/monorepo.json into init module.
---@return boolean, table|nil
M.load = function()
  local module = require("monorepo")
  local data_path = module.config.data_path
  local persistent_json = data_path .. "/monorepo.json"
  local status, load = pcall(function()
    return vim.json.decode(Path:new(persistent_json):read())
  end, persistent_json)

  local actual_monorepo_path = module.currentMonorepo
  local config_key = module.currentMonorepo

  if status and load then
    module.monorepoVars = load
    -- Try to find a matching key (exact or glob pattern)
    local matched_key, actual_path = M.find_matching_monorepo(module.currentMonorepo, module.monorepoVars)
    if matched_key then
      config_key = matched_key  -- The key to look up in the config
      actual_monorepo_path = actual_path  -- The actual current directory
    elseif not module.monorepoVars[module.currentMonorepo] then
      module.monorepoVars[module.currentMonorepo] = { "/" }
    end
  else
    module.monorepoVars = {}
    module.monorepoVars[module.currentMonorepo] = { "/" }
  end

  -- Expand glob patterns in the project list using the actual current directory
  local project_patterns = module.monorepoVars[config_key]
  if project_patterns then
    module.currentProjects = M.expand_project_patterns(actual_monorepo_path, project_patterns)
  else
    module.currentProjects = { "/" }
  end

  -- Keep currentMonorepo as the actual path for directory operations
  module.currentMonorepo = actual_monorepo_path
end

-- Extend vim.notify to include silent option
M.notify = function(message)
  if require("monorepo").config.silent then
    return
  end
  vim.notify(message)
end

M.index_of = function(array, value)
  for i, v in ipairs(array) do
    if v == value then
      return i
    end
  end
  return nil
end

M.format_path = function(path)
  -- Remove leading ./ and add leading /
  if path:sub(1, 2) == "./" then
    path = path:sub(2)
  end
  -- Add leading /
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end
  return path
end

-- Convert a glob pattern to a Lua pattern
-- Supports * (any characters) and ? (single character)
---@param glob string
---@return string
M.glob_to_pattern = function(glob)
  local pattern = glob
  -- Escape special Lua pattern characters except * and ?
  pattern = pattern:gsub("([%^%$%(%)%%%.%[%]%+%-])", "%%%1")
  -- Convert glob wildcards to Lua patterns
  pattern = pattern:gsub("%*", ".*")
  pattern = pattern:gsub("%?", ".")
  return "^" .. pattern .. "$"
end

-- Find the first matching key from monorepoVars for the given path
-- Supports both exact matches and glob patterns
---@param path string The current working directory
---@param monorepoVars table The loaded monorepo configuration
---@return string|nil, string|nil matched_key, actual_path
M.find_matching_monorepo = function(path, monorepoVars)
  -- First try exact match
  if monorepoVars[path] then
    return path, path
  end

  -- Then try glob pattern matching
  for key, _ in pairs(monorepoVars) do
    -- Check if the key contains glob characters
    if key:match("[%*%?]") then
      local pattern = M.glob_to_pattern(key)
      if path:match(pattern) then
        return key, path  -- Return both the pattern key and the actual path
      end
    end
  end

  return nil, nil
end

-- Expand glob patterns in project list to actual directories
-- For example, "/packages/*" becomes ["/packages/api", "/packages/web", ...]
---@param monorepo_path string The absolute path to the monorepo root
---@param project_patterns table Array of project paths or glob patterns
---@return table Array of expanded project paths
M.expand_project_patterns = function(monorepo_path, project_patterns)
  local expanded = {}
  local seen = {} -- To avoid duplicates

  for _, pattern in ipairs(project_patterns) do
    -- Check if this is a glob pattern
    if pattern:match("[%*%?]") then
      -- Build the full filesystem path for globbing
      local full_pattern = monorepo_path .. pattern

      -- Use vim.fn.glob to expand the pattern
      local matches = vim.fn.glob(full_pattern, false, true)

      for _, match in ipairs(matches) do
        -- Convert back to relative path
        local relative = match:sub(#monorepo_path + 1)

        -- Check if it's a directory
        if vim.fn.isdirectory(match) == 1 and not seen[relative] then
          table.insert(expanded, relative)
          seen[relative] = true
        end
      end
    else
      -- Not a glob pattern, add as-is
      if not seen[pattern] then
        table.insert(expanded, pattern)
        seen[pattern] = true
      end
    end
  end

  return expanded
end

return M
