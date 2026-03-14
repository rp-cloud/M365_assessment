# M365 Assessment - Session Notes

## Kontekst projektu

- Repozytorium to framework PowerShell do audytu Microsoft 365.
- Architektura została przebudowana tak, aby obok EntraID można było rozwijać także osobne obszary dla Exchange i OneDrive.
- Obecnie kompletna logika audytowa dotyczy EntraID, a Exchange i OneDrive mają już przygotowane szkielety architektoniczne.

## Aktualna struktura

- `main.ps1` jest cienkim entrypointem uruchamiającym moduły i menu.
- `modules/reporting.ps1` obsługuje wspólny reporting.
- `modules/cache_EntraID.ps1` zawiera cache danych dla kontroli EntraID.
- `modules/framework.ps1` buduje kontekst aplikacji, ścieżki i mapy kategorii.
- `modules/navigation.ps1` obsługuje wspólne menu i routing dla wszystkich obszarów.
- `modules/bootstrap_EntraID.ps1` obsługuje logowanie do Graph i preload cache dla EntraID.
- `modules/bootstrap_Exchange.ps1` i `modules/bootstrap_OneDrive.ps1` są szkieletami pod przyszły bootstrap tych obszarów.
- `categories/EntraID/` zawiera wszystkie obecne skrypty kontroli EntraID.
- `categories/Exchange/` i `categories/OneDrive/` zawierają już pierwsze placeholderowe skrypty kategorii.
- `categories/EntraID/m365_entraID.json` zawiera katalog kontrolek dla EntraID.

## Co zostało zrobione wcześniej

### 1. Reporting

- Summary report został przebudowany do pól:
  - `Contrl_ID`
  - `Descryption`
  - `Result`
  - `Status`
  - `Expected_Value`
  - `Recommencdation`
  - `Comment`
- Wszystkie pola poza `Result` i `Status` są pobierane z katalogu kontroli JSON.
- Dodano funkcje:
  - `Initialize-ControlCatalog`
  - `Get-ControlDefinition`
  - `Export-ControlResult`

### 2. Obsługa katalogu kontroli JSON

- Plik źródłowy katalogu kontroli zawiera uszkodzone ciągi typu `te"N/A"t`, `gover"N/A"ce`.
- Nie poprawiano ręcznie całego pliku.
- W `modules/reporting.ps1` dodano sanitizację przed `ConvertFrom-Json`, aby katalog kontroli ładował się mimo tych błędów.

### 3. Cache EntraID

- Rozszerzono cache o wspólne funkcje dla:
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
- `Get-CachedSignIns` ma parametry:
  - `-Days`
  - `-Top`

### 4. Alerting & Reporting

- W kontroli alerting/reporting dodano limit:
  - `Get-CachedSignIns -Days 30 -Top 40000`
- To ogranicza liczbę pobieranych sign-in logs, żeby nie przeciążać Microsoft Graph.

### 5. Conditional Access

- Uporządkowano numerację kontroli:
  - dawne błędne mapowanie `AAD.PA.08` zostało przeniesione do `AAD.CA.09`
  - dotychczasowe `AAD.CA.09` zostało przesunięte do `AAD.CA.10`
- Zmieniono katalog kontroli JSON, aby identyfikatory zgadzały się z kodem.

#### AAD.CA.01

- Poprawiono wykrywanie Trusted Locations:
  - dodano `Get-MgIdentityConditionalAccessNamedLocation -All`
  - `IsTrusted` jest normalizowane z właściwości obiektu albo z `AdditionalProperties["isTrusted"]`

#### AAD.CA.09

- Kontrola sprawdza teraz:
  - `ExcludeApplications`
  - polityki z konkretnym `IncludeApplications` zamiast `All`
- Status:
  - `PASS` gdy nie ma takich polityk
  - `WARNING` gdy są wyjątki lub zawężenia

#### AAD.CA.10

- Kontrola sprawdza:
  - wykluczonych użytkowników w CA policies
  - dostępność trusted locations
  - potencjalne polityki kompensujące dla tych użytkowników
- Status:
  - `PASS` gdy nie ma wykluczeń użytkowników
  - `WARNING` gdy są wykluczenia, ale są też trusted locations i potencjalne polityki kompensujące
  - `FAIL` w pozostałych przypadkach

## Co zostało zrobione w nowej architekturze

### 1. Przebudowa struktury katalogów

- Utworzono podfoldery:
  - `categories/EntraID`
  - `categories/Exchange`
  - `categories/OneDrive`
- Wszystkie istniejące skrypty kategorii EntraID zostały przeniesione do `categories/EntraID`.
- Plik `m365_controls.json` został przeniesiony do `categories/EntraID` i zmieniono jego nazwę na `m365_entraID.json`.
- Plik `modules/cache.ps1` został zmieniony na `modules/cache_EntraID.ps1`.

### 2. Refactor entrypoint i menu

- `main.ps1` został uproszczony do roli entrypointu.
- Logika kontekstu aplikacji została przeniesiona do `modules/framework.ps1`.
- Logika nawigacji i menu została przeniesiona do `modules/navigation.ps1`.
- Logowanie do Microsoft Graph oraz preload cache dla EntraID zostały wydzielone do `modules/bootstrap_EntraID.ps1`.
- Menu główne i podmenu są teraz oparte o mapy kategorii, co upraszcza dokładanie kolejnych obszarów i opcji.

### 3. Szkielety Exchange i OneDrive

- Dodano `modules/bootstrap_Exchange.ps1` jako miejsce pod przyszły bootstrap Exchange.
- Dodano `modules/bootstrap_OneDrive.ps1` jako miejsce pod przyszły bootstrap OneDrive.
- Dodano mapowanie kategorii dla Exchange i OneDrive w `modules/framework.ps1`.
- Dodano placeholderowe skrypty kategorii:
  - `categories/Exchange/mail-flow.ps1`
  - `categories/OneDrive/sharing.ps1`
- Dzięki temu Exchange i OneDrive są już pełnoprawnymi gałęziami architektury, mimo że nie mają jeszcze realnych kontroli.

### 4. Dopasowanie ścieżek i importów

- Wszystkie skrypty kategorii EntraID importują `modules/cache_EntraID.ps1` i `modules/reporting.ps1` z nowej lokalizacji względnej.
- `modules/reporting.ps1` czyta teraz katalog kontroli z `categories/EntraID/m365_entraID.json`.

## Stan walidacji

- Parser PowerShell został sprawdzony po zmianach.
- Składnia `main.ps1`, nowych modułów architektonicznych i skryptów kategorii jest poprawna.
- Nie uruchamiano jeszcze pełnego testu live przeciwko realnemu tenantowi po przebudowie architektury.
- Exchange i OneDrive nie mają jeszcze testów funkcjonalnych, bo na razie zawierają tylko szkielety.

## Ważne ograniczenia

- Framework nadal ma realnie zaimplementowaną logikę audytową tylko dla EntraID.
- Exchange i OneDrive mają obecnie bootstrap i placeholderowe kategorie, ale bez właściwych kontroli i bez logiki połączeń do usług.
- Prywatny tenant bez licencji enterprise prawdopodobnie zwróci:
  - braki danych
  - puste wyniki
  - `MANUAL`
  - `WARNING`
  - błędy dostępu do części endpointów Graph

## Co warto zrobić dalej

Po lokalnym teście warto sprawdzić:

- czy każda kategoria EntraID kończy się bez przerwania całego skryptu
- czy summary ma poprawne kolumny
- czy detailed CSV zapisują się dla każdej kontroli
- które kontrole zwracają błędy lub nielogiczne wyniki
- kiedy dodać pierwsze realne kategorie i bootstrap połączeń dla Exchange
- kiedy dodać pierwsze realne kategorie i bootstrap połączeń dla OneDrive

## Jak wrócić do tematu jutro

Przy nowej sesji wystarczy napisać mniej więcej:

"Pracujemy dalej na repo M365 Assessment. Stan jest opisany w `session_notes.md`. Chcę przeanalizować wyniki testów / dodać pierwszy realny moduł Exchange / dodać pierwszy realny moduł OneDrive."
