local cjson = require "cjson"
local sandbox = require "kong.tools.sandbox".sandbox
local kong_meta = require "kong.meta"

local kong = kong
local ngx = ngx
local timer_at = ngx.timer.at


local sandbox_opts = { env = { kong = kong, ngx = ngx } }


local function log(premature, conf, message)
  if premature then
    return
  end

  local host = conf.host
  local port = conf.port
  local timeout = conf.timeout
  local keepalive = conf.keepalive

  local sock = ngx.socket.tcp()
  sock:settimeout(timeout)

  local ok, err = sock:connect(host, port)
  if not ok then
    kong.log.err("failed to connect to ", host, ":", tostring(port), ": ", err)
    sock:close()
    return
  end

  if conf.tls then
    ok, err = sock:sslhandshake(true, conf.tls_sni, false)
    if not ok then
      kong.log.err("failed to perform TLS handshake to ", host, ":", port, ": ", err)
      sock:close()
      return
    end
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


local TcpLogHandler = {
  PRIORITY = 7,
  VERSION = kong_meta.version,
}
function TcpLogHandler:access(conf) -- luacheck: ignore 212
  local body, err, mimetype = kong.request.get_body()
  if err then
    kong.log.err("failed to get request body: ", err)
  elseif body then
    if mimetype == "application/json" then
      ngx.ctx.request_body = body
    end
  end
end


function TcpLogHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression, sandbox_opts)())
    end
  end

  local message = kong.log.serialize()
  if(message.response.status == 500) then
    message.request_body = ngx.ctx.request_body
  end
  local ok, err = timer_at(0, log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return TcpLogHandler
