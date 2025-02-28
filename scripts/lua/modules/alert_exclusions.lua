--
-- (C) 2017-22 - ntop.org
--
-- Module to keep things in common across alert_exclusions of various type

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

require "lua_utils"
local alert_consts = require "alert_consts"
local json = require "dkjson"

-- ##############################################

local alert_exclusions = {}

-- ##############################################

local function _get_alert_exclusions_prefix_key()
   local key = string.format("ntopng.prefs.alert_exclusions")

   return key
end

-- ##############################################

local function _get_alert_exclusions_lock_key()
   local key = string.format("ntopng.cache.alert_exclusions.alert_exclusions_lock")

   return key
end

-- ##############################################

local function _lock()
   local max_lock_duration = 5 -- seconds
   local max_lock_attempts = 5 -- give up after at most this number of attempts
   local lock_key = _get_alert_exclusions_lock_key()

   for i = 1, max_lock_attempts do
      local value_set = ntop.setnxCache(lock_key, "1", max_lock_duration)

      if value_set then
	 return true -- lock acquired
      end

      ntop.msleep(1000)
   end

   return false -- lock not acquired
end

-- ##############################################

local function _unlock()
   ntop.delCache(_get_alert_exclusions_lock_key())
end

-- ##############################################

local function _check_host_ip_vlan_id(host_ip, vlan_id)
  if not isIPv4(host_ip) and not isIPv6(host_ip) and not isIPv4Network(host_ip) then
    -- Invalid host submitted
    return false
  end

  if (vlan_id) and (not tonumber(vlan_id)) then
    -- Invalid vlan_id
    return false
  end

  return true
end

-- ##############################################

local function _check_alert_key(alert_key)
  if not alert_consts.getAlertType(tonumber(alert_key)) then
    -- Invalid alert key submitted
    return false
  end

  return true
end

-- ##############################################

local function _get_configured_alert_exclusions()
  local excl_key = _get_alert_exclusions_prefix_key()
  local configured_excl_str = ntop.getPref(excl_key)
  local configured_excl = json.decode(configured_excl_str) or {}

  return configured_excl
end

-- ##############################################

local function _set_configured_alert_exclusions(exclusions)
   local excl_key = _get_alert_exclusions_prefix_key()
   local str = json.encode(exclusions)

   ntop.setPref(excl_key, str)   -- Add the preference
   ntop.reloadAlertExclusions()  -- Tell ntopng to reload
end

-- ##############################################

--@brief Enables or disables an alert
local function _toggle_alert_exclusion(subject_key, subject_type, alert_key, add_exclusion, is_flow_exclusion)
  local ret = false
  
  if not _check_alert_key(alert_key) then
    -- Invalid params submitted
    return false
  end

  local locked = _lock()

  if locked then
    local id = tonumber(alert_key)
    local exclusions = _get_configured_alert_exclusions()

    if add_exclusion then
      -- Add an entry for the current alert entity, if currently exising exclusions don't already have it
      if(exclusions[subject_key] == nil) then
        exclusions[subject_key] = { 
          type = subject_type,
          flow_alerts = {}, 
          host_alerts = {} 
        }
      end
	 
      if(is_flow_exclusion) then
        table.insert(exclusions[subject_key].flow_alerts, id)
      else
        table.insert(exclusions[subject_key].host_alerts, id)
      end

    else
      -- ip@vlan
      if exclusions[subject_key] then
        local r = {}
        local t = {}
        
        if(is_flow_exclusion) then
          t = exclusions[subject_key].flow_alerts
        else
          t = exclusions[subject_key].host_alerts
        end

        for i=0,table.len(t) do
          if(t[i] ~= id) then
            table.insert(r, t[i])
          end
        end
	    
        if(is_flow_exclusion) then
          exclusions[subject_key].flow_alerts = r
        else
          exclusions[subject_key].host_alerts = r
        end
      end
    end
      
    _set_configured_alert_exclusions(exclusions)
    
    ret = true
    _unlock()
  end

  return ret
end

-- ##############################################

--@brief Enables or disables an alert for an `host`, supports VLANs
local function _toggle_alert_exclusion_by_host(is_flow_exclusion, host_ip, vlan_id, alert_key, add_exclusion)
  if not _check_host_ip_vlan_id(host_ip, vlan_id) then
    -- Invalid params submitted
    return false
  end

  local host = host_ip

  -- Adding vlan_id to the host
  if (vlan_id) and (tonumber(vlan_id) ~= 0) then
    host = format_ip_vlan(host_ip, vlan_id)
  end

  return _toggle_alert_exclusion(host, "host", alert_key, add_exclusion, is_flow_exclusion)
end

-- ##############################################

--@brief Enables or disables alerts for a domain
local function _toggle_alert_exclusion_by_domain(domain_name, alert_key, add_exclusion)
  return _toggle_alert_exclusion(domain_name, "domain", alert_key, add_exclusion, true)
end

-- ##############################################

--@brief Enables or disables alerts for a domain
local function _toggle_alert_exclusion_by_certificate(certificate, alert_key, add_exclusion)
  return _toggle_alert_exclusion(certificate, "certificate", alert_key, add_exclusion, true)
end

-- ##############################################

--@brief Removes all exclusions for a given entity
local function _enable_all_alerts_by_host(host_ip, vlan_id)
  local ret = false
  
  local locked = _lock()

  if locked then
    local exclusions
    
    if(host_ip == nil) then
      exclusions = {}	 
    else
      local host = format_ip_vlan(host_ip, vlan_id)
      exclusions = _get_configured_alert_exclusions()	 
      exclusions[host] = nil
    end

    _set_configured_alert_exclusions(exclusions)

    ret = true
    _unlock()
  end

  return ret
end

-- ##############################################

-- @brief Returns true if `host_ip` has the alert identified with `alert_key` disabled
local function _has_disabled_alert_by_host(is_flow_exclusion, host_ip, vlan_id, alert_key)
  local exclusions = _get_configured_alert_exclusions()
  local id = tonumber(alert_key)
  local host = format_ip_vlan(host_ip, vlan_id)

  if(is_flow_exclusion) then
    if((exclusions[host] == nil) or (exclusions[host].flow_alerts[id] == nil)) then
      return false
    else
      return true
    end
  else
    if((exclusions[host] == nil) or (exclusions[host].host_alerts[id] == nil)) then
      return false
    else
      return true
    end
  end
end

-- ##############################################

-- @brief Returns true if `is_flow_exclusion` has one or more disabled alerts
function alert_exclusions.has_disabled_alerts()
  local exclusions = _get_configured_alert_exclusions()

  if(table.len(exclusions) > 0) then 
    return true
  else
    return false
  end
end

-- ##############################################

-- @brief Returns all excluded subjects (e.g. hosts, domains, certificates) for the given `alert_key` or nil if no exclusion exists
local function _get_exclusions(is_flow_exclusion, alert_key, subject_type)
  local exclusions = _get_configured_alert_exclusions()
  local id = tonumber(alert_key)
  local ret = {}

  for subject_key, v in pairs(exclusions) do

    if not v.type then
       v.type = "host"
    end

    if v.type == subject_type then
      local t

      if is_flow_exclusion then
        t = v.flow_alerts
      else
        t = v.host_alerts
      end

      if not t then
        traceError(TRACE_INFO,TRACE_CONSOLE, "Failure checking exclusions")
      else
        for i=0,table.len(t) do
          if t[i] == id then
            ret[subject_key] = true
            break
          end
        end     
      end
    end
  end
  
  return ret
end

-- ##############################################

--@brief Marks a flow alert as disabled for a given `host_ip`, considered either as client or server
--@return True, if alert is disabled with success, false otherwise
function alert_exclusions.disable_flow_alert_by_host(host_ip, vlan_id, alert_key)
   return _toggle_alert_exclusion_by_host(true --[[ flow --]], host_ip, vlan_id, alert_key, true --[[ disable --]])
end

-- ##############################################

--@brief Marks a flow alert as disabled for a given domain name
--@return True, if alert is disabled with success, false otherwise
function alert_exclusions.disable_flow_alert_by_domain(domain_name, alert_key)
   return _toggle_alert_exclusion_by_domain(domain_name, alert_key, true --[[ disable --]])
end

-- ##############################################

--@brief Marks a flow alert as disabled for a given certificate
--@return True, if alert is disabled with success, false otherwise
function alert_exclusions.disable_flow_alert_by_certificate(certificate, alert_key)
   return _toggle_alert_exclusion_by_certificate(certificate, alert_key, true --[[ disable --]])
end

-- ##############################################

--@brief Marks a flow alert as enabled for a given `host_ip`, considered either as client or server
--@return True, if alert is enabled with success, false otherwise
function alert_exclusions.enable_flow_alert_by_host(host_ip, vlan_id, alert_key)
   return _toggle_alert_exclusion_by_host(true --[[ flow --]], host_ip, vlan_id, alert_key, false --[[ enable --]])
end

-- ##############################################

--@brief Marks a flow alert as enabled for a given domain name
--@return True, if alert is enabled with success, false otherwise
function alert_exclusions.enable_flow_alert_by_domain(domain_name, alert_key)
   return _toggle_alert_exclusion_by_domain(domain_name, alert_key, false --[[ enable --]])
end

-- ##############################################

--@brief Marks a flow alert as enabled for a given certificate
--@return True, if alert is enabled with success, false otherwise
function alert_exclusions.enable_flow_alert_by_certificate(certificate, alert_key)
   return _toggle_alert_exclusion_by_certificate(certificate, alert_key, false --[[ enable --]])
end

-- ##############################################

--@brief Enables all flow alerts possibly disabled
--@param host If a valid ip address is specified, then all alerts will be enabled only for `host`, otherwise all alerts will be enabled
--@return True, if enabled with success, false otherwise
function alert_exclusions.enable_all_flow_alerts_by_host(host_ip, vlan_id)
   return _enable_all_alerts_by_host(host_ip, vlan_id)
end

-- ##############################################

-- @brief Returns true if `host_ip` has the flow alert identified with `alert_key` disabled
function alert_exclusions.has_disabled_flow_alert_by_host(host_ip, alert_key)
   return _has_disabled_alert_by_host(true --[[ flow --]], host_ip, 0, alert_key)
end
 
-- ##############################################

--@brief Marks a host alert as disabled for a given `host_ip`
--@return True, if alert is disabled with success, false otherwise
function alert_exclusions.disable_host_alert_by_host(host_ip, vlan_id, alert_key)
   return _toggle_alert_exclusion_by_host(false --[[ host --]], host_ip, vlan_id, alert_key, true --[[ disable --]])
end

-- ##############################################

--@brief Marks a host alert as enabled for a given `host_ip`
--@return True, if alert is enabled with success, false otherwise
function alert_exclusions.enable_host_alert_by_host(host_ip, vlan_id, alert_key)
   return _toggle_alert_exclusion_by_host(false --[[ host --]], host_ip, vlan_id, alert_key, false --[[ enable --]])
end

-- ##############################################

--@brief Enables all host alerts possibly disabled
--@param host If a valid ip address is specified, then all alerts will be enabled only for `host`, otherwise all alerts will be enabled
--@return True, if enabled with success, false otherwise
function alert_exclusions.enable_all_host_alerts_by_host(host_ip, vlan_id)
   return _enable_all_alerts_by_host(host_ip, vlan_id)
end

-- ##############################################

-- @brief Returns all the excluded hosts for the host alert identified with `alert_key`
function alert_exclusions.host_alerts_get_exclusions(alert_key, subject_type)
   return _get_exclusions(false --[[ host --]], alert_key, subject_type or "host") or {}
end

-- ##############################################

-- @brief Returns all the excluded hosts for the flowt alert identified with `alert_key`
function alert_exclusions.flow_alerts_get_exclusions(alert_key, subject_type)
   return _get_exclusions(true --[[ flow --]], alert_key, subject_type or "host") or {}
end

-- ##############################################

-- @brief Returns true if `host_ip` has the host alert identified with `alert_key` disabled
function alert_exclusions.has_disabled_host_alert_by_host(host_ip, alert_key)
   return _has_disabled_alert_by_host(false --[[ host --]], host_ip, 0, alert_key)
end

-- ##############################################

-- @brief Import a previously `export`ed exclusions configuration
function alert_exclusions.import(exclusions)
   _set_configured_alert_exclusions(exclusions)
end

-- ##############################################

-- @brief Exports the current configuration
function alert_exclusions.export()
   local exclusions = _get_configured_alert_exclusions()
  
   return exclusions
end

-- ##############################################

-- @brief Delete all alert_exclusions
function alert_exclusions.cleanup()
   local locked = _lock()

   if locked then
      local excl_key = _get_alert_exclusions_prefix_key()

      ntop.delCache(excl_key)
      ntop.reloadAlertExclusions() -- Tell ntopng to reload

      _unlock()
   end
end

-- ##############################################

return alert_exclusions
