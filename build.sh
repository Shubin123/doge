cd ./src && zip -9 -r ../misc/game.love .
cd ..
cp -r /Applications/love.app/ ./misc/game.app
cp  ./misc/game.love ./misc/game.app/Contents/Resources/

# for windows cross-compile (get the love.exe (32/64)bit):
cd ./misc/love-11.5-win64
cat love.exe ../game.love > ./game.exe 
