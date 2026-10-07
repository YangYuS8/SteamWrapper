using System.Text;

namespace SteamWrapper.Deployment;

// An intentionally bounded syntax editor. Existing text is never serialized again.
internal sealed class SteamLaunchIntegrationVdf
{
    internal const int MaximumBytes = 32 * 1024 * 1024;
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private readonly string text, appId;
    private readonly Node apps;
    private readonly Node? game, option;

    internal SteamLaunchIntegrationVdf(byte[] bytes, string appId)
    {
        if (bytes.Length > MaximumBytes) throw Invalid();
        this.text = Utf8.GetString(bytes);
        this.appId = appId;
        var root = new Reader(text).Read();
        var hierarchy = new[] { "UserLocalConfigStore", "Software", "Valve", "Steam", "apps" };
        var members = root;
        Node? parent = null;
        foreach (var name in hierarchy)
        {
            parent = members.SingleOrDefault(node => node.Key.Value.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (parent?.Children is null) throw Invalid();
            members = parent.Children;
        }
        apps = parent!;
        game = members.SingleOrDefault(node => node.Key.Value == appId);
        if (game is not null && game.Children is null) throw Invalid();
        option = game?.Children?.SingleOrDefault(node => node.Key.Value.Equals("LaunchOptions", StringComparison.OrdinalIgnoreCase));
        if (option is not null && option.Children is not null) throw Invalid();
    }

    internal bool KeyExists => option is not null;
    internal bool GameExists => game is not null;
    internal string CurrentValue => option?.Value.Value ?? "";
    internal string? OriginalToken => option is null ? null : text.Substring(option.Value.Start, option.Value.Length);

    internal byte[] Set(string value)
    {
        if (value.Length > 32768 || value.Contains('\0')) throw Invalid();
        if (option is not null) return Encode(text.Remove(option.Value.Start, option.Value.Length).Insert(option.Value.Start, Quote(value)));
        var parent = game ?? apps;
        var newline = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        var indent = Indent(parent.Key.Start);
        var unit = parent.Children?.FirstOrDefault() is { } first && Indent(first.Key.Start).Length > indent.Length
            ? Indent(first.Key.Start)[indent.Length..] : "\t";
        var childIndent = indent + unit;
        var content = game is not null ? childIndent + "\"LaunchOptions\"\t" + Quote(value)
            : childIndent + Quote(appId) + newline + childIndent + "{" + newline + childIndent + unit + "\"LaunchOptions\"\t" + Quote(value) + newline + childIndent + "}";
        return Encode(text.Insert(parent.CloseStart, newline + content + newline + indent));
    }

    internal byte[] Restore(SteamLaunchIntegrationVdf original, string applied)
    {
        if (CurrentValue != applied || !KeyExists) throw new InvalidDataException("Steam launch options were edited after application.");
        if (original.KeyExists) return Encode(text.Remove(option!.Value.Start, option.Value.Length).Insert(option.Value.Start, original.OriginalToken!));
        // Remove our exact insertion when it remains intact. Later data in an inserted
        // game node prevents whole-node removal and is preserved by key-only removal.
        var generated = Utf8.GetString(original.Set(applied));
        var start = 0;
        while (start < original.text.Length && original.text[start] == generated[start]) start++;
        var suffix = 0;
        while (suffix < original.text.Length - start && original.text[^(suffix + 1)] == generated[^(suffix + 1)]) suffix++;
        var insertion = generated.Substring(start, generated.Length - original.text.Length);
        var match = text.IndexOf(insertion, StringComparison.Ordinal);
        if (match >= 0 && match <= option!.Key.Start && match + insertion.Length >= option.Value.Start + option.Value.Length &&
            text.IndexOf(insertion, match + 1, StringComparison.Ordinal) < 0)
            return Encode(text.Remove(match, insertion.Length));
        var removeStart = option!.Key.Start;
        var removeEnd = option.Value.Start + option.Value.Length;
        var lineStart = text.LastIndexOf('\n', Math.Max(0, removeStart - 1)) + 1;
        var lineEnd = text.IndexOf('\n', removeEnd);
        if (lineEnd >= 0 && text[lineStart..removeStart].All(c => c is ' ' or '\t') && text[removeEnd..lineEnd].All(c => c is ' ' or '\t' or '\r'))
        { removeStart = lineStart; removeEnd = lineEnd + 1; }
        return Encode(text.Remove(removeStart, removeEnd - removeStart));
    }

    private string Indent(int offset)
    {
        var start = text.LastIndexOf('\n', Math.Max(0, offset - 1)) + 1;
        return text[start..offset].All(c => c is ' ' or '\t') ? text[start..offset] : "";
    }
    private static byte[] Encode(string value)
    {
        var result = Utf8.GetBytes(value);
        if (result.Length > MaximumBytes) throw Invalid();
        return result;
    }
    internal static string Quote(string value) => "\"" + value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal)
        .Replace("\r", "\\r", StringComparison.Ordinal).Replace("\n", "\\n", StringComparison.Ordinal).Replace("\t", "\\t", StringComparison.Ordinal) + "\"";

    private sealed record Token(string Value, int Start, int Length, bool Brace = false);
    private sealed record Node(Token Key, Token Value, List<Node>? Children, int CloseStart);
    private sealed class Reader(string text)
    {
        private int offset, tokens;
        internal List<Node> Read() => Block(0, false).Nodes;
        private (List<Node> Nodes, int Close) Block(int depth, bool nested)
        {
            if (depth > 64) throw Invalid();
            var nodes = new List<Node>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            while (Next() is { } key)
            {
                if (key.Brace && key.Value == "}" && nested) return (nodes, key.Start);
                if (key.Brace || !seen.Add(key.Value)) throw Invalid();
                var value = Next() ?? throw Invalid();
                if (value.Brace)
                {
                    if (value.Value != "{") throw Invalid();
                    var child = Block(depth + 1, true);
                    nodes.Add(new(key, value, child.Nodes, child.Close));
                }
                else nodes.Add(new(key, value, null, -1));
            }
            if (nested) throw Invalid();
            return (nodes, -1);
        }
        private Token? Next()
        {
            while (offset < text.Length)
            {
                if (char.IsWhiteSpace(text[offset]) || offset == 0 && text[offset] == '\uFEFF') { offset++; continue; }
                if (text[offset] == '/' && offset + 1 < text.Length && text[offset + 1] == '/')
                { while (offset < text.Length && text[offset] != '\n') offset++; continue; }
                break;
            }
            if (offset == text.Length) return null;
            if (++tokens > 1_000_000) throw Invalid();
            var start = offset;
            var c = text[offset++];
            if (c is '{' or '}') return new(c.ToString(), start, 1, true);
            if (c != '"')
            {
                if (c is '[' or ']' || char.IsControl(c)) throw Invalid();
                while (offset < text.Length && !char.IsWhiteSpace(text[offset]) && text[offset] is not ('{' or '}'))
                { if (text[offset] is '"' or '[' or ']' || char.IsControl(text[offset])) throw Invalid(); offset++; }
                return new(text[start..offset], start, offset - start);
            }
            var value = new StringBuilder();
            while (offset < text.Length)
            {
                c = text[offset++];
                if (c == '"') return new(value.ToString(), start, offset - start);
                if (c == '\\')
                {
                    if (offset == text.Length) throw Invalid();
                    c = text[offset++];
                    if (c is not ('\\' or '"' or 'n' or 'r' or 't')) value.Append('\\');
                    c = c switch { 'n' => '\n', 'r' => '\r', 't' => '\t', _ => c };
                }
                if (c == '\0') throw Invalid();
                value.Append(c);
            }
            throw Invalid();
        }
    }
    private static InvalidDataException Invalid() => new("Unsupported or ambiguous Steam configuration; no launch options were changed.");
}
