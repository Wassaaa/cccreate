local logger = {}

function logger.info(message)
  print("[INFO] " .. tostring(message))
end

function logger.warn(message)
  print("[WARN] " .. tostring(message))
end

function logger.error(message)
  print("[ERROR] " .. tostring(message))
end

return logger
