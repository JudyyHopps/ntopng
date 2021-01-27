--
-- (C) 2019-21 - ntop.org
--

local alerts_api = require("alerts_api")
local alert_consts = require("alert_consts")
local user_scripts = require("user_scripts")
local alert_severities = require "alert_severities"

local script = {
  -- Script category
  category = user_scripts.script_categories.network,

  default_enabled = false,

  -- This script is only for alerts generation
  is_alert = true,

  default_value = {
    severity = alert_severities.error,
  },

  -- See below
  hooks = {},

  gui = {
    i18n_title = "alerts_thresholds_config.throughput",
    i18n_description = "alerts_thresholds_config.alert_throughput_description",
    i18n_field_unit = user_scripts.field_units.mbits,
    input_builder = "threshold_cross",
  }
}

-- #################################################################

function script.hooks.all(params)
  local interface_bytes = params.entity_info["stats"]["bytes"]

  -- Delta
  local value = alerts_api.interface_delta_val(script.key, params.granularity, interface_bytes)
  -- Granularity
  value = value / alert_consts.granularity2sec(params.granularity)
  -- Bytes to Mbit
  value = (value * 8) / 1000000

  -- Check if the configured threshold is crossed by the value and possibly trigger an alert
  alerts_api.checkThresholdAlert(params, alert_consts.alert_types.alert_threshold_cross, value)
end

-- #################################################################

return script
