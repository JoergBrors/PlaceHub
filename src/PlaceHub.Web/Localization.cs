using System.Collections.Frozen;
using System.Globalization;
using System.Text.Json;

namespace PlaceHub.Web;

public sealed record LanguageInfo(string Code, string Name);

/// <summary>
/// Reference-based UI localization. Every language is one JSON file <c>Localization/&lt;code&gt;.json</c> (embedded, loaded once at start,
/// then immutable lookup tables: no I/O and no client script at request time). A new language is added by adding one file with a
/// <c>_name</c> entry; missing keys fall back to English, then to the default language, then to the key itself.
/// Keys: <c>area.name</c> for page text, <c>src.&lt;text&gt;</c> for domain labels produced by the core in the source language,
/// <c>code.&lt;CODE&gt;</c> for safe diagnostic codes.
/// </summary>
public sealed class Loc
{
    public const string CookieName = "placehub-lang";
    public const string DefaultLanguage = "de";
    private const string FallbackLanguage = "en";
    private const string NameKey = "_name";
    private readonly FrozenDictionary<string, FrozenDictionary<string, string>> catalog;

    public IReadOnlyList<LanguageInfo> Languages { get; }

    public Loc() : this(LoadEmbedded()) { }

    public Loc(IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> languages)
    {
        catalog = languages.ToFrozenDictionary(x => x.Key, x => x.Value.ToFrozenDictionary(StringComparer.Ordinal), StringComparer.OrdinalIgnoreCase);
        Languages = catalog.Select(x => new LanguageInfo(x.Key, x.Value.GetValueOrDefault(NameKey, x.Key))).OrderBy(x => x.Name, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }

    /// <summary>Active language of the current request or circuit (the culture is set by the request-localization middleware).</summary>
    public string Lang { get { var code = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName; return catalog.ContainsKey(code) ? code : DefaultLanguage; } }

    public string this[string key] => Lookup(key) ?? key;
    public string F(string key, params object?[] args) => string.Format(CultureInfo.CurrentCulture, this[key], args);
    /// <summary>Translates a domain label that the core produces in the source language; unknown text is shown unchanged.</summary>
    public string Src(string? text) => string.IsNullOrEmpty(text) ? "" : Lookup("src." + text) ?? text;
    /// <summary>Translates a safe diagnostic code; an unknown code is shown unchanged.</summary>
    public string Code(string code) => Lookup("code." + code) ?? code;

    public bool Has(string language, string key) => catalog.TryGetValue(language, out var table) && table.ContainsKey(key);

    private string? Lookup(string key)
    {
        if (catalog[Lang].TryGetValue(key, out var value)) return value;
        if (catalog.TryGetValue(FallbackLanguage, out var fallback) && fallback.TryGetValue(key, out value)) return value;
        return catalog.TryGetValue(DefaultLanguage, out var source) && source.TryGetValue(key, out value) ? value : null;
    }

    private static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> LoadEmbedded()
    {
        var assembly = typeof(Loc).Assembly;
        var result = new Dictionary<string, IReadOnlyDictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var name in assembly.GetManifestResourceNames().Where(x => x.StartsWith("i18n.", StringComparison.Ordinal) && x.EndsWith(".json", StringComparison.Ordinal)))
        {
            using var stream = assembly.GetManifestResourceStream(name)!;
            result[name["i18n.".Length..^".json".Length]] = JsonSerializer.Deserialize<Dictionary<string, string>>(stream) ?? [];
        }
        return result;
    }
}
