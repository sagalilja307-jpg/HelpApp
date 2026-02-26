# Features Structure

Den här mappen är organiserad per feature med samma interna mönster:

- `Views/` UI-vyer
- `ViewModels/` state + presentationlogik
- `Models/` feature-specifika modeller/states
- `Components/` återanvändbara UI-delar inom feature
- `Services/` feature-specifika integrationslager
- `Style/` visuell styling/theme helpers

## Nuvarande struktur

- `Chat/`
  - `Views/`
  - `ViewModels/`
  - `Visualization/`
- `Memory/`
  - `Views/`
  - `ViewModels/`
  - `Models/`
  - `Services/`
  - `Style/`
- `Settings/`
  - `Views/`
  - `Stores/`
  - `Models/`
  - `Components/`
- `Onboarding/`
  - `Views/`
  - `Models/`

## Riktlinjer

- Lägg ny UI i `Views/` först, inte i root för feature.
- Om en vy blir stor: bryt ut underkomponenter till `Components/`.
- Håll `ViewModels/` fria från framework-tunga UI-dependencies.
- Flytta integrationskod från views till `Services/` när den växer.
