--
-- (C) 2019-21 - ntop.org
--

local user_scripts = require("user_scripts")
local alerts_api = require "alerts_api"
local alert_severities = require "alert_severities"
local alert_consts = require("alert_consts")

local script = {
  -- Script category
  category = user_scripts.script_categories.security, 

  -- Priodity
  prio = 20, -- Higher priority (executed sooner) than default 0 priority

  -- This module is disabled by default
  default_enabled = false,

  -- This script is only for alerts generation
  is_alert = true,

  -- The default configuration of this script
  default_value = {
    severity = alert_severities.error,
    items = {},
  },

  -- See below
  hooks = {},

  -- Allow user script configuration from the GUI
  gui = {
    -- Localization strings, from the "locales" directory of the plugin
    i18n_title = "alerts_dashboard.blacklisted_country",
    i18n_description = "alerts_dashboard.blacklisted_country_descr",
    input_builder = "items_list",
    item_list_type = "country",
  }
}

-- #################################################################

-- A fast lookup table
local blacklisted_countries = nil

-- Defines an hook which is executed every time a procotol of a flow is detected
function script.hooks.protocolDetected(now, conf)
  if(blacklisted_countries == nil) then
    blacklisted_countries = {}

    for _, country in pairs(conf.items or {}) do
      blacklisted_countries[string.upper(country)] = true
    end
  end

  local flow_info = flow.getInfo()
  local cli_country = flow.getClientCountry()
  local srv_country = flow.getServerCountry()
  local is_blacklisted = false
  local flow_score = 60
  local cli_score, srv_score, attacker, victim
  local info = {cli_blacklisted = false, srv_blacklisted = false}

  if(cli_country and blacklisted_countries[cli_country]) then
    info.cli_blacklisted = true
    is_blacklisted = true
    cli_score = 60
    srv_score = 10
    attacker = flow_info["cli.ip"]
    victim = flow_info["srv.ip"]
  end

  if(srv_country and blacklisted_countries[srv_country]) then
    info.srv_blacklisted = true
    is_blacklisted = true
    cli_score = 10
    srv_score = 60
    attacker = flow_info["srv.ip"]
    victim = flow_info["cli.ip"]
  end

  if(is_blacklisted) then
    -- Note: possibly nil
    info.cli_country = cli_country
    info.srv_country = srv_country

    local alert = alert_consts.alert_types.alert_blacklisted_country.new(
      cli_country,
      srv_country,
      info.cli_blacklisted,
      info.srv_blacklisted
    )
    
    alert:set_severity(conf.severity)
    alert:set_attacker(attacker)
    alert:set_victim(victim)

    alert:trigger_status(cli_score, srv_score, flow_score)
  end
end

-- #################################################################

return script
