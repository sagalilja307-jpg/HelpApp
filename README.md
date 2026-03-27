# Helper Monorepo

Helper är ett monorepo för iOS-appen och backend. Projektet är inte bara en traditionell assistant-app, utan en kontext- och strukturmotor där olika lager har tydliga ansvar.

## Struktur
- `ios/` – iOS-projektet (`ios/Helper.xcodeproj`)
- `backend/` – FastAPI-backend (`uvicorn api:app --reload`)

## Arkitektur just nu

### 1. Data layer
Systemets datakällor: kalender, påminnelser, mail, filer, bilder, kontakter, plats, hälsa, anteckningar och andra synkade källor.

### 2. Query layer
Tolkar informationsfrågor om datalagret.

Exempel:
- Vad händer idag?
- Har jag några olästa mail?
- Vad skrev jag om resan?
- Hur sov jag?

### 3. Suggestion layer
Upptäcker försiktigt möjliga handlingar i chatten och formar dem som förslag.

Exempel:
- Det här låter som något att lägga i kalendern
- Det här låter som en påminnelse
- Det här ser ut som info att spara
- Det här låter som något att följa upp

### 4. Action layer
Håller den explicita kedjan mellan förslag, användarens godkännande och faktisk handling.

Exempel:
- `ProposedAction`
- action confirmation state
- executors för kalender, reminders, notes
- koordinering av uppföljningar

Det här lagret ska inte blandas ihop med datakällor eller allmänt minne. Det tar redan tolkad förståelse och gör den handlingsbar.

### 5. State layer
Håller tillstånd som pågår över tid.

Exempel:
- `PendingFollowUp`
- uppföljningar som väntar
- handlingsutkast
- andra framtida pending states

### 6. Memory layer
Lång- och korttidsminne, embeddings, kluster, historik och annan sparad betydelse över tid.

### 7. Decision log
Loggar vad systemet föreslog, undertryckte eller genomförde. Detta är inte samma sak som full användarbesluts-historik.

## Min rekommenderade framtida struktur

### A. Data layer
Kalender, reminders, mail, files, health, notes, etc.

### B. Query layer
Tolkar informationsfrågor om datalagret.

På backend ligger detta främst i:
- `backend/src/helpershelp/api/routes/query.py`
- `backend/src/helpershelp/api/routes/process_memory.py`

### C. Suggestion layer
Upptäcker försiktigt möjliga handlingar och producerar `ProposedAction`.

### D. Action layer
Hanterar:
- förslag som väntar på godkännande
- bekräftelseflöde
- exekvering mot kalender, reminders, notes
- överlämning till pending follow-up state när en handling fortsätter över tid

### E. State layer
`PendingFollowUp`, andra pending states, handlingsutkast.

### F. Memory layer
Lång- och korttidsminne, embeddings, kluster, historik.

### G. Decision memory layer
Användarens val, orsaker, alternativ, lärdomar.

## Designprincip

Helper ska skilja på:
- information
- handling
- tillstånd
- minne
- beslutshistorik

Det betyder att:
- **Query** hämtar och strukturerar information
- **Suggestion** upptäcker möjliga handlingar
- **Action** håller ihop förslag, godkännande och exekvering
- **State** håller reda på sådant som fortfarande väntar efter att en handling startat
- **Memory** sparar betydelse över tid
- **Decision memory** är ett framtida lager för användarens egna val och lärdomar

## Snabbstart: iOS
1. Öppna `ios/Helper.xcodeproj` i Xcode.
2. Kör scheme `Helper`.

## Snabbstart: backend
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e .
uvicorn api:app --reload
```

## Start/Stop: backend

Starta backend (lyssna på alla interfaces):
```bash
cd backend
source .venv/bin/activate
uvicorn api:app --host 0.0.0.0 --port 8000
```

Stäng av backend:
```bash
pkill -f "uvicorn api:app"
```

## Test: backend
```bash
cd backend
source .venv/bin/activate
pytest -q
```
