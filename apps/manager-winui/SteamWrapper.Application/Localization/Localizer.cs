using System.Globalization;
using System.Resources;
using SteamWrapper.Application.Profiles;

namespace SteamWrapper.Application.Localization;

/// <summary>Explicit UI language: independent of the OS locale and of protocol/user data.</summary>
public sealed class Localizer(string? language = null)
{
    internal static readonly ResourceManager Resources = new("SteamWrapper.Application.Localization.Strings", typeof(Localizer).Assembly);
    public const string English = "en-US";
    public const string Chinese = "zh-CN";
    public string Language { get; private set; } = NormalizeLanguage(language);
    public void SetLanguage(string? language) => Language = NormalizeLanguage(language);
    public static string NormalizeLanguage(string? language) => language?.Trim().ToLowerInvariant() is "zh-cn" or "zh-hans" ? Chinese : English;
    public string this[string key] => Resources.GetString(key, CultureInfo.GetCultureInfo(Language))
        ?? throw new MissingManifestResourceException($"Missing UI resource: {key}");
    public string Format(LocalMessage message) => string.Format(CultureInfo.GetCultureInfo(Language), this[message.Key],
        message.Arguments.Select(value => value switch
        {
            LocalMessage nested => Format(nested),
            Exception error => Describe(error),
            _ => value
        }).ToArray());
    // Only our structured messages are localized. OS/parser diagnostics and user input stay verbatim.
    public string Describe(Exception error) => error.Data[Messages.DataKey] is LocalMessage message ? Format(message) : error.Message;
}

public sealed record LocalMessage(string Key, params object?[] Arguments)
{
    public override string ToString() => new Localizer().Format(this);
}

/// <summary>Keep invariant English exception diagnostics and the original exception types; UI can render their message in its own language.</summary>
public static class Messages
{
    internal const string DataKey = "SteamWrapper.LocalMessage";
    public static LocalMessage Text(string key, params object?[] args) => new(key, args);
    private static T Attach<T>(T error, LocalMessage text) where T : Exception { error.Data[DataKey] = text; return error; }
    public static ProfileStoreException Profile(string key, Exception? inner = null, params object?[] args)
    { var text = Text(key, args); return Attach(new ProfileStoreException(text.ToString(), inner), text); }
    public static ProfileConflictException Conflict(string key, params object?[] args)
    { var text = Text(key, args); return Attach(new ProfileConflictException(text.ToString()), text); }
    public static IOException Io(string key, Exception? inner = null, params object?[] args)
    { var text = Text(key, args); return Attach(new IOException(text.ToString(), inner), text); }
    public static FormatException Format(string key, params object?[] args)
    { var text = Text(key, args); return Attach(new FormatException(text.ToString()), text); }
    public static InvalidOperationException Invalid(string key, params object?[] args)
    { var text = Text(key, args); return Attach(new InvalidOperationException(text.ToString()), text); }
    public static ArgumentException Argument(string key, string parameter)
    { var text = Text(key); return Attach(new ArgumentException(text.ToString(), parameter), text); }
}
