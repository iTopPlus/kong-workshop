local cjson = require "cjson"
local kong = kong
local ngx = ngx
local timer_at = ngx.timer.at

local function log(premature, conf, message)
  if premature then
    return
  end

  local host = conf.log_host
  local port = conf.log_port
  local timeout = conf.log_timeout
  local keepalive = conf.log_keepalive

  local sock = ngx.socket.tcp()
  sock:settimeout(timeout)

  local ok, err = sock:connect(host, port)
  if not ok then
    kong.log.err("failed to connect to ", host, ":", tostring(port), ": ", err)
    sock:close()
    return
  end


  ok, err = sock:send(cjson.encode(message) .. "\n")
  if not ok then
    kong.log.err("failed to send data to ", host, ":", tostring(port), ": ", err)
  end

  ok, err = sock:setkeepalive(keepalive)
  if not ok then
    kong.log.err("failed to keepalive to ", host, ":", tostring(port), ": ", err)
    sock:close()
    return
  end
end


local tcp_logs = {}


function tcp_logs:log(conf)
  
  local message = kong.request.get_headers()
  message.response = {}
  message.response.status = conf.error_code

  local ok, err = timer_at(0, log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return tcp_logs
