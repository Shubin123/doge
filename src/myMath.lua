local myMath = {}

function myMath.sign(number)
    return number > 0 and 1 or (number == 0 and 0 or -1)
end


function myMath.round(n)
  return math.floor(n + 0.5)
end

    return myMath