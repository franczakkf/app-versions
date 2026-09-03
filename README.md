# Numery wersji moich aplikacji

Publiczne repozytorium z **jedną rzeczą na aplikację: numerem najnowszej wersji.**

## Po co to istnieje

Piszę narzędzia, których **kod jest prywatny**, ale które mają umieć powiedzieć
„jest nowsza wersja". Odpytywanie prywatnego repozytorium wymagałoby tokenu
**wewnątrz dystrybuowanego pliku wykonywalnego** — a token w pliku EXE nie jest
sekretem, bo da się go stamtąd wyjąć. Kosztem byłby dostęp do prywatnego repo
w zamian za funkcję „powiedz mi, że wyszła nowa wersja".

Dlatego publiczny jest wyłącznie **numer**. Kod, instalatory i wydania zostają prywatne.

## Czego tu nigdy nie będzie

- kodu źródłowego ani plików do pobrania,
- adresów do prywatnych repozytoriów i wydań,
- tokenów, kluczy i czegokolwiek, co jest sekretem,
- danych o użytkownikach.

Aplikacje czytają te pliki **anonimowo**: zwykły `GET`, bez logowania i bez nagłówków
uwierzytelniających. Serwer dowiaduje się tylko tego, że ktoś pobrał plik.

## Format

Jeden plik JSON na aplikację, nazwany jej identyfikatorem:

```json
{
  "version": "0.1.0",
  "notes": "Krótki opis zmian. Pole opcjonalne."
}
```

| Pole | Wymagane | Znaczenie |
|---|---|---|
| `version` | tak | numer najnowszego wydania, człony oddzielone kropkami |
| `notes` | nie | jedno–dwa zdania o zmianach; brak pola jest w porządku |

**`version` musi być samymi cyframi i kropkami.** Aplikacja odrzuca zapisy w rodzaju
`1_0`, `+2` czy cyfry spoza ASCII — każdy z nich kłamałby **w górę**, a fałszywe
„jest nowsza wersja" wysyła użytkownika po wydanie, którego nie ma.

## Jak aplikacja to czyta

Adres surowego pliku:

```
https://raw.githubusercontent.com/franczakkf/app-versions/main/<identyfikator>.json
```

Zasady po stronie aplikacji, wspólne dla wszystkich moich narzędzi:

1. **Brak sieci to cisza, nie błąd.** To narzędzia lokalne; mają działać bez internetu.
2. **Odpowiedź spoza kontraktu niczego nie przewraca** — HTML zamiast JSON, pole innego
   typu albo skasowany plik dają po prostu „nie wiadomo".
3. **Tylko `https`**, przekierowania sprawdzane po kolei, limit rozmiaru i czasu.
4. **Wynik nie jest oknem na wierzchu** — trafia tam, gdzie użytkownik go szuka.

## Aplikacje

| Plik | Aplikacja |
|---|---|
| [`storytel-audio-manager.json`](storytel-audio-manager.json) | Storytel Audio Manager — lokalny menedżer audiobooków z własnego konta (Windows) |
| [`music-library-manager.json`](music-library-manager.json) | Music Library Manager — lokalny menedżer biblioteki muzycznej z bramką jakości (Windows) |

## Aktualizacja po wydaniu

Po opublikowaniu nowej wersji zmieniam `version` w odpowiednim pliku. To wszystko —
nic tu nie buduje się automatycznie i nic nie zależy od prywatnych repozytoriów.
