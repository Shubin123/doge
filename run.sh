# run from the inner app binary inside the app bundle to get debug output


'/Applications/love.app/Contents/MacOS/love' ./src 
#   2  &  '/Applications/love.app/Contents/MacOS/love' ./src 1 &'/Applications/love.app/Contents/MacOS/love' ./src 3
# & '/Applications/love.app/Contents/MacOS/love' ./src 3
# CAREFUL STARTING THE GAME AT THE SAME TIME MEANS RNG math.random() samples are identical,YOU MIGHT NOT HAVE REPLICATED GAME STATE CORRECTLY!!!!!

# '/Applications/love.app/Contents/MacOS/love' ./misc 2 &  '/Applications/love.app/Contents/MacOS/love' ./misc 1
