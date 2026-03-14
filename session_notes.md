# EntraAudit - Session Notes

## Kontekst projektu

- Repozytorium to framework PowerShell do audytu Microsoft Entra ID / M365.
- Nie zmieniano struktury `main.ps1` ani układu katalogów.
- Główne obszary przebudowy:
  - `modules/reporting.ps1`
  - `modules/cache.ps1`
  - wszystkie pliki w `categories/`

## Co zostało zrobione

### 1. Reporting

- Summary report został przebudowany do pól:
  - `Contrl_ID`
  - `Descryption`
  - `Result`
  - `Status`
  - `Expected_Value`
  - `Recommencdation`
  - `Comment`
- Wszystkie pola poza `Result` i `Status` są pobierane z `m365_controls.json`.
- Dodano funkcje:
  - `Initialize-ControlCatalog`
  - `Get-ControlDefinition`
  - `Export-ControlResult`

### 2. Obsługa m365_controls.json

- `m365_controls.json` zawiera uszkodzone ciągi typu `te"N/A"t`, `gover"N/A"ce`.
- Nie poprawiano ręcznie całego pliku.
- W `modules/reporting.ps1` dodano sanitizację przed `ConvertFrom-Json`, aby katalog kontroli ładował się mimo tych błędów.

### 3. Cache

- Rozszerzono `modules/cache.ps1` o wspólne funkcje cache dla:
  - users
  - users by id
  - CA policies
  - named locations
  - roles
  - role members
  - password protection
  - authorization policy
  - organization
  - domains
  - security defaults
  - group lifecycle policies
  - access review definitions
  - terms of use
  - user registration details
  - sign-in logs
- `Get-CachedSignIns` ma teraz parametry:
  - `-Days`
  - `-Top`

### 4. Alerting & Reporting

- W `categories/alerting-reporting.ps1` dodano limit:
  - `Get-CachedSignIns -Days 30 -Top 40000`
- To ogranicza liczbę pobieranych sign-in logs, żeby nie przeciążać Microsoft Graph.

### 5. Conditional Access

- Uporządkowano numerację kontroli:
  - dawne błędne mapowanie `AAD.PA.08` zostało przeniesione do `AAD.CA.09`
  - dotychczasowe `AAD.CA.09` zostało przesunięte do `AAD.CA.10`
- Zmieniono też `m365_controls.json`, aby identyfikatory zgadzały się z kodem.

#### AAD.CA.01

- Poprawiono wykrywanie Trusted Locations:
  - dodano `Get-MgIdentityConditionalAccessNamedLocation -All`
  - `IsTrusted` jest normalizowane z właściwości obiektu albo z `AdditionalProperties["isTrusted"]`
- To naprawia problem z niewykrywaniem Trusted Locations w środowisku.

#### AAD.CA.09

- Kontrola sprawdza teraz:
  - `ExcludeApplications`
  - oraz polityki z konkretnym `IncludeApplications` zamiast `All`
- Status:
  - `PASS` gdy nie ma takich polityk
  - `WARNING` gdy są wyjątki / zawężenia

#### AAD.CA.10

- Kontrola sprawdza:
  - wykluczonych użytkowników w CA policies
  - dostępność trusted locations
  - potencjalne polityki kompensujące dla tych użytkowników
- Status:
  - `PASS` gdy nie ma wykluczeń użytkowników
  - `WARNING` gdy są wykluczenia, ale są też trusted locations i potencjalne polityki kompensujące
  - `FAIL` w pozostałych przypadkach

## Stan walidacji

- Parser PowerShell sprawdzony po zmianach.
- Składnia zmienionych plików jest poprawna.
- Mapowanie `Control_ID` używanych w kategoriach do `m365_controls.json` zostało sprawdzone i było spójne po poprawkach.

## Ważne ograniczenia

- Framework nie był jeszcze kompleksowo przetestowany przeciwko realnemu tenantowi po wszystkich zmianach.
- Prywatny tenant bez licencji enterprise prawdopodobnie zwróci:
  - braki danych,
  - puste wyniki,
  - `MANUAL`,
  - `WARNING`,
  - błędy dostępu do części endpointów Graph.
- To jest oczekiwane i nadal przydatne do testu stabilności frameworka.

## Co zrobić dalej

Po lokalnym teście warto sprawdzić:

- czy każda kategoria kończy się bez przerwania całego skryptu,
- czy summary ma poprawne kolumny,
- czy detailed CSV zapisują się dla każdej kontroli,
- które kontrole zwracają błędy lub nielogiczne wyniki.

## Jak wrócić do tematu jutro

Przy nowej sesji wystarczy napisać mniej więcej:

"Pracujemy dalej na repo EntraAudit. Stan jest opisany w `session_notes.md`. Chcę przeanalizować wyniki testów / poprawić konkretną kategorię."
