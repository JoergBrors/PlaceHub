using Xunit;
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using PlaceHub.Web;

namespace PlaceHub.Core.Tests;

public sealed class LocalizationTests
{
    private static readonly string[] RequiredLanguages = ["de", "en", "fr", "it", "es"];

    private static string WebRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "src", "PlaceHub.Web"))) dir = dir.Parent;
        return Path.Combine(dir?.FullName ?? throw new InvalidOperationException("repository root not found"), "src", "PlaceHub.Web");
    }

    private static Dictionary<string, Dictionary<string, string>> Files() =>
        Directory.GetFiles(Path.Combine(WebRoot(), "Localization"), "*.json")
            .ToDictionary(f => Path.GetFileNameWithoutExtension(f), f => JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(f))!);

    [Fact]
    public void EveryRequiredLanguageIsCompleteAndConsistentWithTheSourceLanguage()
    {
        var files = Files();
        var source = files["de"];
        foreach (var language in RequiredLanguages)
        {
            Assert.True(files.ContainsKey(language), language);
            var missing = source.Keys.Except(files[language].Keys).ToArray();
            Assert.True(missing.Length == 0, $"{language} is missing: {string.Join(", ", missing.Take(10))}");
            foreach (var (key, value) in files[language]) Assert.False(string.IsNullOrWhiteSpace(value), $"{language}:{key} is empty");
        }
    }

    [Fact]
    public void AdditionalLanguagesMayBePartialButNeverIntroduceUnknownKeysOrBrokenPlaceholders()
    {
        var files = Files();
        var placeholder = new Regex(@"\{\d+\}");
        foreach (var (language, table) in files)
        {
            Assert.True(table.ContainsKey("_name"), $"{language} needs a _name entry");
            foreach (var (key, value) in table.Where(x => x.Key != "_name"))
            {
                Assert.True(files["de"].ContainsKey(key), $"{language}:{key} is not a known key");
                var expected = placeholder.Matches(files["de"][key]).Select(x => x.Value).OrderBy(x => x).ToArray();
                var actual = placeholder.Matches(value).Select(x => x.Value).OrderBy(x => x).ToArray();
                Assert.True(expected.SequenceEqual(actual), $"{language}:{key} placeholders differ");
            }
        }
    }

    [Fact]
    public void EveryKeyReferencedFromMarkupAndCodeExists()
    {
        var de = Files()["de"];
        var direct = new Regex("""\bL(?:\.F)?[\[\(]\s*"([A-Za-z0-9_.]+)"|\bL\.Code\("([A-Z_]+)"\)""");
        var src = new Regex("""\bL\.Src\("([^"]+)"\)""");
        var failures = new List<string>();
        foreach (var file in Directory.GetFiles(WebRoot(), "*.*", SearchOption.AllDirectories).Where(f => (f.EndsWith(".razor") || f.EndsWith(".cs")) && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")))
        {
            var text = File.ReadAllText(file);
            foreach (Match m in direct.Matches(text)) if (m.Groups[1].Success && !de.ContainsKey(m.Groups[1].Value)) failures.Add($"{Path.GetFileName(file)}: {m.Groups[1].Value}");
            foreach (Match m in src.Matches(text)) if (!de.ContainsKey("src." + m.Groups[1].Value)) failures.Add($"{Path.GetFileName(file)}: src.{m.Groups[1].Value}");
        }
        Assert.True(failures.Count == 0, string.Join("; ", failures.Distinct()));
    }

    [Fact]
    public void EveryLanguageFileIsDiscoveredWithoutCodeChanges()
    {
        var loc = new Loc();
        Assert.Equal(Files().Keys.Order(), loc.Languages.Select(x => x.Code).Order());
        Assert.All(RequiredLanguages, l => Assert.Contains(loc.Languages, x => x.Code == l));
    }

    [Fact]
    public void LookupUsesTheCultureThenEnglishThenTheSourceLanguageThenTheKey()
    {
        var loc = new Loc(new Dictionary<string, IReadOnlyDictionary<string, string>>
        {
            ["de"] = new Dictionary<string, string> { ["_name"] = "Deutsch", ["a"] = "de-a", ["b"] = "de-b", ["c"] = "de-c" },
            ["en"] = new Dictionary<string, string> { ["_name"] = "English", ["a"] = "en-a", ["b"] = "en-b" },
            ["fr"] = new Dictionary<string, string> { ["_name"] = "Français", ["a"] = "fr-a", ["f"] = "fr-{0}" }
        });
        var previous = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = new CultureInfo("fr");
            Assert.Equal("fr-a", loc["a"]); Assert.Equal("en-b", loc["b"]); Assert.Equal("de-c", loc["c"]); Assert.Equal("missing", loc["missing"]);
            Assert.Equal("fr-7", loc.F("f", 7));
            CultureInfo.CurrentUICulture = new CultureInfo("ja");
            Assert.Equal("de", loc.Lang); Assert.Equal("de-a", loc["a"]);
        }
        finally { CultureInfo.CurrentUICulture = previous; }
    }

    [Fact]
    public void SourceLabelsAndCodesFallBackToTheOriginalText()
    {
        var loc = new Loc();
        var previous = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = new CultureInfo("en");
            Assert.Equal("Approval pending", loc.Src("Freigabe ausstehend"));
            Assert.Equal("Unlisted text", loc.Src("Unlisted text"));
            Assert.Equal("SOME_CODE", loc.Code("SOME_CODE"));
            Assert.Equal("", loc.Src(null));
        }
        finally { CultureInfo.CurrentUICulture = previous; }
    }
}
