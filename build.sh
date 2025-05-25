cd ./src && zip -9 -r ../game.love .
cd ..
cp -r /Applications/love.app/ ./game.app
cp  ./game.love ./game.app/Contents/Resources/

# for windows cross-compile (get the love.exe (32/64)bit):
cd love-11.5-win64
cat love.exe ../game.love > ./game.exe 
