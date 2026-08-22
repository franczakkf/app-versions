# CLAUDE.md — app-versions

Zacznij od [`README.md`](README.md) — jest kompletny i to on tłumaczy, **po co** to repo
istnieje. Tutaj tylko rzeczy, o które łatwo się potknąć.

## Granica danych

To repozytorium jest **publiczne**. Nie opisuj tu środowiska pracy, pracodawcy, klientów ani
zasad podziału pracy między narzędziami — te ustalenia żyją w prywatnych plikach warsztatu
i nie mają tu czego szukać. Do repozytorium trafiają wyłącznie numery wersji.

## To repozytorium jest publiczne

Wszystko, co tu zacommitujesz, jest natychmiast widoczne dla świata i pobierane anonimowo
przez `raw.githubusercontent.com`. Nie ma tu kodu, wydań, plików do pobrania ani niczego
o użytkownikach — i ma tak zostać.

Zanim dodasz **jakiekolwiek** nowe pole, plik albo zdanie, sprawdź, czy nie mówi czegoś,
czego nie chcesz mówić publicznie. Ten plik też jest publiczny — opisuj w nim reguły, nie
środowisko, w którym pracujesz.

## Format

Jeden plik JSON na aplikację, nazwany jej identyfikatorem. `README.md` dokumentuje dwa pola:
`version` (wymagane) i `notes` (opcjonalne).

**Uwaga — stan faktyczny odbiega od README.** Pliki niosą dziś także pole `url`, którego
tabela formatu nie wymienia, a sekcja „Czego tu nigdy nie będzie" wyklucza. To rozbieżność
do rozstrzygnięcia przez właściciela: albo pole zostaje i README trzeba poprawić, albo pole
znika. **Nie rozstrzygaj tego sam** i nie kopiuj `url` do kolejnych plików, dopóki nie ma
decyzji.

Jeden fakt do tej decyzji: **aplikacja z tego pola korzysta** — po wykryciu nowszej wersji
odsyła pod ten adres. Usunięcie nie jest więc zmianą kosmetyczną w tym repo, tylko zmianą
kontraktu z aplikacją, którą trzeba wtedy przygotować po drugiej stronie.

## Zasada, która chroni użytkownika

`version` musi być **samymi cyframi i kropkami**. Zapisy typu `1_0`, `+2` czy cyfry spoza
ASCII kłamałyby **w górę** — aplikacja uznałaby, że jest nowsze wydanie, i wysłała użytkownika
po coś, czego nie ma. Walidacja jest po stronie aplikacji, ale błąd zaczyna się tutaj.

## Praca

Podbicia wersji wykonuje pipeline wydawniczy — widać to w `git log` po commitach bota.
Ręczna edycja jest możliwa i bywa używana, ale wtedy **omija walidację po stronie pipeline'u**,
więc sprawdź numer sam. Nowa aplikacja = nowy plik JSON **plus** wiersz w tabeli „Aplikacje"
w `README.md`.

Commity: `<identyfikator-aplikacji>: <wersja>`, np. `storytel-audio-manager: 0.4.2` — tak jak
w istniejącym `git log`.
