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

## Kenshi
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
