# Mod Translation Toolkit — instrukcja PL

## Uruchomienie
Uruchom plik `Mod Translation Toolkit.vbs`. Toolkit nie wymaga Pythona i nie powinien otwierać widocznego okna PowerShell/CMD.

## RimWorld — nowe tłumaczenie
1. Otwórz zakładkę **Zainstalowane mody** albo użyj **Wybierz folder moda**.
2. Możesz też wkleić ścieżkę do folderu moda i nacisnąć Enter albo przeciągnąć folder na pole ścieżki.
3. Toolkit skanuje `Languages/English`, Defs oraz wersjonowane foldery zawartości.
4. Wybierz język źródłowy i docelowy.
5. Tłumacz ręcznie, użyj **Tłumacz brakujące** albo eksportu/importu CSV.
6. Przed zapisem użyj **Sprawdź / napraw placeholdery**.
7. Kliknij **Zbuduj oddzielny mod**.

## Aktualizacja istniejącego tłumaczenia
1. Kliknij **Aktualizuj istniejące tłumaczenie**.
2. Wklej/przeciągnij folder zaktualizowanego moda źródłowego.
3. Wklej/przeciągnij folder istniejącego moda tłumaczeniowego.
4. Toolkit zachowa pasujące tłumaczenia i pokaże nowe/brakujące/nieaktualne wpisy.
5. Uzupełnij brakujące wpisy.
6. Kliknij **Zapisz aktualizację**. Istniejące `packageId`, `About.xml` i pliki Workshop pozostają zachowane.

## Wyszukiwanie i szybkie poprawki
Pole wyszukiwania nad tabelą może działać na:
- **Oba**
- **Oryginał**
- **Tłumaczenie**

Przykład: wyszukaj `Finish Off`, wybierz **Oryginał**, wpisz poprawne polskie tłumaczenie i kliknij **Zamień wszędzie**.

## Diagnostyka skrótów i UI
**Diagnostyka skrótów** skanuje `KeyBindingDef`.
- jeśli ma `label` / `description`, tekst może być tłumaczony normalnie,
- jeśli nie ma tych pól, Toolkit oznaczy przypadek jako możliwy tekst generowany przez UI/kod.

**Diagnostyka DLL/UI** skanuje Assemblies heurystycznie i szuka charakterystycznych odwołań/stringów, m.in.:
`Hotkey`, `KeyBindingDef`, `Tooltip`, `TooltipHandler`, `Gizmo`, `Command`, `Widgets`, `Translate`.

To diagnostyka pomocnicza. Samo znalezienie słowa/API w DLL nie oznacza, że tekst da się zmienić zwykłym modem tłumaczeniowym.

> Diagnostyka DLL/UI uruchamia się dopiero po kliknięciu przycisku. Zwykłe wczytanie moda nie skanuje DLL. Toolkit pomija typowe biblioteki zależności, np. Harmony, i analizuje aktywną/najnowszą wersję moda.


### Jak czytać raport DLL/UI
- `Tooltip`, `TooltipHandler`, `Widgets`, `Gizmo`, `Command` — kod tworzy lub modyfikuje interfejs.
- `Translate`, `TaggedString` — kod korzysta z API tłumaczeń RimWorlda.
- `HarmonyPatch`, `Prefix`, `Postfix`, `Transpiler` — mod patchuje istniejący kod.
- nazwy metod, np. `DoTimeControlsGUI`, pomagają ustalić, jaki element UI jest zmieniany.

Kilka takich sygnałów jednocześnie sugeruje tekst generowany/modyfikowany w kodzie, ale nie jest to automatycznie dowód na hardcoded string.

## Workshop Dashboard
W zakładce **Workshop** możesz:
- zapisać nazwę kreatora,
- dodać SteamID/link do profilu,
- dodać publikacje po URL lub PublishedFileID,
- odświeżać publiczne statystyki,
- sumować subskrypcje, ulubione i wyświetlenia.

Toolkit nie prosi o hasło Steam i nie przechowuje publisher API key.

## Kenshi Game
Profil Kenshi obsługuje obecnie podstawową grę:
- UI gettext z `locale\en\LC_MESSAGES\main.pot/main.po`,
- dane gry/dialogi po eksporcie FCS,
- CSV,
- automatyczne tłumaczenie,
- generowanie `main.po` i `main.mo`,
- przygotowanie `__translations\pl_PL`.

Finalny plik danych `.translation` nadal buduje Forgotten Construction Set.

## Ważne
Automatyczne tłumaczenie jest opcjonalne. Ręczna praca i poprawki terminologii są pełnoprawnym workflow Toolkita.


## Nawigacja v0.5.0
Górny poziom Toolkita został uproszczony:
- **Profile gier**
  - **RimWorld Game**
  - **RimWorld Mod**
    - **Tłumaczenie**
    - **Zainstalowane mody**
  - **Kenshi Game**
- **Workshop**

### RimWorld Game
Pierwsza wersja tego modułu wykrywa instalację RimWorlda, pokazuje Core i wykryte dodatki/moduły danych oraz pozwala zaznaczyć pojedynczy moduł, wszystkie, tylko Core albo tylko DLC. Skan obecnie zbiera angielskie i polskie wpisy Keyed z wybranych modułów. Obsługa DefInjected/Defs i porównywanie zmian wersji gry będzie rozwijane dalej.


### RimWorld Game — wykrywanie języków
Od v0.5.2 Toolkit nie zakłada już sztywno folderu `Languages\Polish`. Najpierw analizuje `LanguageInfo.xml`, a dopiero potem nazwę folderu. Skanowane są osobno `Keyed` i `DefInjected`. Po skanie status pokazuje, ile polskich wpisów znaleziono i dopasowano.


### Oficjalne archiwa językowe RimWorlda
RimWorld przechowuje wiele oficjalnych tłumaczeń jako pliki `.tar`, np. `Polish (Polski).tar`. Od v0.5.3 Toolkit wykrywa takie archiwa, rozpakowuje je wyłącznie do tymczasowego cache w `%TEMP%` i odczytuje z nich `Keyed` oraz `DefInjected`. Oryginalne pliki gry nie są modyfikowane.


### RimWorld Game — DefInjected
Od v0.5.6 angielskie wpisy DefInjected dla Core/DLC są budowane bezpośrednio z `Defs`. RimWorld nie musi przechowywać kompletnej angielskiej kopii `Languages/English/DefInjected`, dlatego wcześniejszy skaner widział głównie Keyed. Toolkit dopasowuje wygenerowane klucze `defName.field` do oficjalnego tłumaczenia docelowego.

## Własny klucz Google Cloud Translation API
Automatyczne tłumaczenie wymaga teraz własnego klucza API.

1. Otwórz Google Cloud Console.
2. Utwórz lub wybierz projekt.
3. Włącz **Cloud Translation API**.
4. Dodaj rozliczenia, jeśli Google wymaga ich dla projektu.
5. Przejdź do **APIs & Services → Credentials**.
6. Wybierz **Create credentials → API key**.
7. W Toolkicie kliknij **Ustawienia API** i wklej klucz.
8. Zalecane jest ograniczenie klucza wyłącznie do Cloud Translation API.

Klucz jest zapisywany w `%APPDATA%\ModTranslationToolkit` w postaci zaszyfrowanej przez Windows DPAPI dla bieżącego konta użytkownika.

**Koszty i limity API należą do właściciela klucza.** Toolkit nie dostarcza wspólnego klucza i nie wysyła klucza do autora Toolkita.

## Dostawcy automatycznego tłumaczenia
W **API / Tłumaczenie** można wybrać:

### Google Cloud Translation
Wymaga klucza Google Cloud Translation API i zwykle skonfigurowanego billingu.

### DeepL API
Wymaga klucza DeepL API. Dostępne są endpointy API Free i API Pro. DeepL API Free może wymagać danych płatniczych do zapobiegania nadużyciom.

### LibreTranslate
Można użyć publicznej usługi z kluczem albo własnego serwera. Dla self-hosted domyślny endpoint to `http://localhost:5000`, a klucz API może być pusty, jeśli serwer go nie wymaga.

Klucze są przechowywane lokalnie i szyfrowane przez Windows DPAPI.


## Język interfejsu
Od v0.5.9 teksty interfejsu PL/EN są zarządzane przez centralny słownik Toolkita. Dotyczy to również nowych sekcji RimWorld Game, Workshop, Kenshi Game i ustawień API. Rozwijane listy ComboBox mają własny styl o podwyższonym kontraście.


## Wybieranie folderów
Od v0.6.0 Toolkit korzysta ze wspólnego, unowocześnionego okna wyboru folderów Windows. Dotyczy ono RimWorld Game, modów RimWorld, Kenshi, folderu docelowego dla tłumaczenia oraz aktualizacji istniejących tłumaczeń. W oknach aktualizacji nadal można wkleić ścieżkę albo przeciągnąć folder, a dodatkowo dostępny jest przycisk **Przeglądaj...**.


## Warstwa języków
Od v0.6.1 Toolkit posiada centralny rejestr języków. Lista języka źródłowego i docelowego nie jest już wpisana na sztywno jako English/Polski. Każdy język ma własny kod Toolkita, nazwę folderu RimWorld oraz mapowanie na Google, DeepL i LibreTranslate. To pierwszy etap pełnej wielojęzyczności.


## RimWorld Mod i dowolny język
Od v0.6.2 profil **RimWorld Mod** korzysta z wybranego języka źródłowego i docelowego. Toolkit skanuje odpowiedni folder lokalizacji, wykrywa istniejące tłumaczenia, automatycznie wczytuje wybrany język docelowy i zapisuje wynik do poprawnego `Languages/<Language>`. Dla English nadal uzupełnia źródła z `Defs`; dla innych języków nie miesza automatycznie angielskich Defów.


## RimWorld Game: język źródłowy i docelowy
Od v0.6.3 zakładka **RimWorld Game** ma własny wybór języka źródłowego i docelowego. Skan Core/DLC korzysta z centralnego rejestru języków i obsługuje zarówno rozpakowane foldery `Languages`, jak i oficjalne archiwa `.tar`.

Dla źródła English Toolkit generuje brakujące DefInjected z `Defs`, tak jak wcześniej. Dla innych języków źródłem jest wyłącznie wybrana oficjalna lokalizacja, dzięki czemu angielskie teksty nie są mieszane z tłumaczeniem.


## Sprawdzanie obsługi języków przez API
Od v0.6.4 Toolkit sprawdza wybraną parę językową przed uruchomieniem automatycznego tłumaczenia.

- **Google Cloud** korzysta z centralnego mapowania kodów języków.
- **DeepL** pobiera aktualną listę języków źródłowych i docelowych z API. Toolkit rozróżnia m.in. warianty `EN-US`, `PT-BR`, `PT-PT` i chińskie warianty skryptu, jeśli są zwracane przez API.
- **LibreTranslate** pobiera `/languages` z wybranego serwera i sprawdza, czy konkretny serwer oferuje daną parę.

W **API / Tłumaczenie** dostępny jest przycisk **Sprawdź języki**, który weryfikuje bieżącą konfigurację dostawcy. Nieobsługiwana para jest blokowana przed rozpoczęciem tłumaczenia.


## Domknięcie wielojęzyczności
Od v0.7.0 nazwa moda, `packageId`, opis Workshop, raport buildu i flaga Preview uwzględniają język docelowy.

### Creator ID
Nowe pole **Creator ID** jest zapisywane lokalnie. `packageId` ma format:

`<oryginalny.packageId>.<creatorId>.<język>`

Eksport CSV zawiera `SourceLanguage` i `TargetLanguage`.
