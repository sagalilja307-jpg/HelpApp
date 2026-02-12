# HelpApp (workspace)

Det här repo:t är en “workspace”-rot som pekar på två delprojekt:
- `Helper/` – iOS-appen (Xcode-projekt i `Helper/Helper.xcodeproj`)
- `HelpersHelp/` – backend (FastAPI)

## Starta här
Öppna `00_START_HERE/` i Finder för genvägar till rätt del av projektet.

## Klona korrekt (submodules)
Om du klonar repo:t från GitHub, initiera även submodules:
```
git submodule update --init --recursive
```
