using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace ModTranslationToolkit.Services;

public sealed class LibreTranslateService
{
    private readonly HttpClient _http = new();

    public async Task<string> TranslateAsync(string endpoint, string text,
        string source, string target, string? apiKey, CancellationToken ct)
    {
        endpoint = endpoint.TrimEnd('/') + "/translate";
        var body = new Dictionary<string, object?> {
            ["q"] = text, ["source"] = source, ["target"] = target, ["format"] = "text"
        };
        if (!string.IsNullOrWhiteSpace(apiKey))
            body["api_key"] = apiKey;

        using var response = await _http.PostAsJsonAsync(endpoint, body, ct);
        response.EnsureSuccessStatusCode();
        var dto = await response.Content.ReadFromJsonAsync<Response>(cancellationToken: ct);
        return dto?.TranslatedText ?? "";
    }

    private sealed class Response
    {
        [JsonPropertyName("translatedText")]
        public string TranslatedText { get; set; } = "";
    }
}
