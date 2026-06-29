local reporter = {}

local function loadConfig()
  local ok, config = pcall(require, "config.webhook")

  if ok then
    return config
  end

  return nil
end

function reporter.saveLocal(report, path)
  local ok, serializedOrError = pcall(textutils.serialize, report)
  if not ok then
    print("Could not serialize report for " .. path .. ": " .. tostring(serializedOrError))
    return false
  end

  local handle = fs.open(path, "w")

  if not handle then
    print("Could not write " .. path)
    return false
  end

  local writeOk, writeError = pcall(handle.write, serializedOrError)
  handle.close()

  if not writeOk then
    if fs.exists(path) then
      pcall(fs.delete, path)
    end
    print("Could not save report to " .. path .. ": " .. tostring(writeError))
    return false
  end

  print("Saved local report to " .. path)
  return true
end

function reporter.send(report)
  local config = loadConfig()

  if not config or not config.url or config.url == "" then
    print("No webhook configured.")
    print("Copy config/webhook.example.lua to config/webhook.lua and edit it.")
    return false
  end

  if not http then
    print("HTTP API is not enabled in CC:Tweaked.")
    return false
  end

  local headers = {
    ["Content-Type"] = "application/json",
  }

  if config.token and config.token ~= "" then
    headers["X-CC-Token"] = config.token
  end

  print("Sending report to webhook...")

  local response, errorMessage = http.post(config.url, textutils.serializeJSON(report), headers)

  if not response then
    print("Webhook failed: " .. tostring(errorMessage))
    return false
  end

  local body = response.readAll()
  response.close()

  print("Webhook response: " .. tostring(body))
  return true
end

return reporter
