# Mod Translation Toolkit v0.8.9 Experimental

## Provider detection + PZ scan performance

### Fixed provider detection
The API readiness check could report that no provider was configured even when one was selected. v0.8.9 reads the real selected ComboBox item, normalizes the provider name, and falls back to persisted settings.

LibreTranslate only requires an endpoint; an API key is optional for self-hosted instances.

### Faster Project Zomboid Game scan
Coverage now reuses the source/target maps built during the main scan instead of rereading the entire localization tree a second time.
