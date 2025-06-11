local myMath = {}

function myMath.sign(number)
    return number > 0 and 1 or (number == 0 and 0 or -1)
end


function myMath.round(n)
  return math.floor(n + 0.5)
end

function myMath.realRandom(low,high)
  return math.random() * (high - low) + low
end

function myMath.len(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function myMath.tokens(cmd)
  -- seperate tokens
  local token_array = {}
  local count = 0
        for token in string.gmatch(cmd, "[^%s]+") do
            -- print(token)
            
            token_array[count] = token
            count = count + 1
        end
        return token_array
end

    return myMath


