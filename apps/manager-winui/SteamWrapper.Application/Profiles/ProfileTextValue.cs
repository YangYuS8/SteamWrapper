namespace SteamWrapper.Application.Profiles;

/// <summary>Keeps source text intact when a native editor normalizes its displayed value.</summary>
public sealed record ProfileTextValue(string SourceText, string InitialDisplayText)
{
    public string Read(string currentDisplayText) => currentDisplayText == InitialDisplayText ? SourceText : currentDisplayText;
}
