# Mod Translation Toolkit v0.5.8

## New translation providers
Automatic translation is no longer Google-only.

### Google Cloud Translation
Uses the official v2 endpoint and sends the key through `X-goog-api-key`.

### DeepL API
Supports API Free and API Pro.

### LibreTranslate
Supports managed and custom/self-hosted servers. A self-hosted instance can work without any API key.

## Security
Credentials are encrypted locally with Windows DPAPI.

## Why LibreTranslate matters
A local LibreTranslate server offers an automatic-translation path without requiring a Google/DeepL billing account.
