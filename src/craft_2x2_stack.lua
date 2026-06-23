local INPUT = "minecraft:nether_brick"
local OUTPUT = "minecraft:nether_bricks"

local function itemName()
  local item = turtle.getItemDetail()
  return item and item.name
end

while true do
  turtle.select(1)

  if turtle.getItemCount() < 64 then
    turtle.suck(64 - turtle.getItemCount())
  end

  if turtle.getItemCount() > 0 and itemName() ~= INPUT then
    turtle.drop()
  elseif turtle.getItemCount() == 64 then
    turtle.transferTo(2, 16)
    turtle.transferTo(5, 16)
    turtle.transferTo(6, 16)

    turtle.select(16)
    if not turtle.craft(16) or itemName() ~= OUTPUT then
      error("Expected to craft " .. OUTPUT, 0)
    end

    turtle.drop()
  else
    sleep(1)
  end
end
