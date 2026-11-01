# Localization (UI languages)

Languages: Deutsch (`de`, source language), English (`en`), Français (`fr`), Italiano (`it`), Español (`es`).

## How it works

- Every language is one JSON file `src/PlaceHub.Web/Localization/<code>.json`, embedded into the assembly and loaded **once at startup** into immutable lookup tables. There is no file access, no client script and no extra request per page, so load time is unchanged.
- Markup and code reference text by key: `@L["h.title"]`, `L.F("dp.submitted", id)` (placeholders `{0}`), `L.Src("Freigabe ausstehend")` for labels that code or the core produce in the source language (key `src.<text>`), `L.Code("SOME_CODE")` for safe diagnostic codes (key `code.<CODE>`, unknown codes are shown unchanged).
- Lookup order: active language → English → German → the key itself. A partially translated language therefore never breaks a page.
- The language comes from the cookie `placehub-lang` (set by the language menu, `POST /lang`, local return URLs only), otherwise from the browser's `Accept-Language`, otherwise German. The request-localization middleware sets the culture for the request and for the Blazor circuit; `<html lang>` follows it.
- The core and the worker stay language neutral: they return stable codes and source-language labels, never formatted sentences for a specific language.

## Adding a language

1. Copy `Localization/en.json` to `Localization/<code>.json` (for example `pt.json`).
2. Set `"_name"` to the language's own name (shown in the menu) and translate the values. Keep the `{0}` placeholders.
3. Build. The language appears in the menu and is accepted by the middleware automatically; no code change is needed. Keys you leave out fall back to English.

## Safeguards (`LocalizationTests`)

- The five shipped languages contain every key of the source language and no empty value.
- No language introduces unknown keys or changes the placeholders of a key.
- Every key referenced from `.razor` and `.cs` files exists.
- Languages are discovered from the files, so a new file is picked up without code.

Known limitation: two diagnostic warnings that embed numbers or timestamps (unresolved assigned locations, earlier-run comparison) are produced by the core as formatted German sentences and are shown unchanged in other languages.
