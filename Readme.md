# Ella's Currency Tracker

> Lightweight World of Warcraft addon to track selected currencies with a compact, configurable overlay.

EllasCurrencyTracker displays one line per tracked currency showing the icon, name and current amount. It is small, configurable, and designed to be easy to use in any UI layout.

![Preview of EllasCurrencyTracker](preview.png)

## Features

- Track up to 18 currencies at once (saved per profile).
- Compact overlay with icon + name + amount for each tracked currency.
- Add currencies using a chat currency link, a numeric currency ID, or the settings UI.
- Settings panel integrated into the Blizzard addon options with categorized currency browser and search.
- Change the overlay's growth direction (UP / DOWN) and move the anchor anywhere on screen.
- Customize the currency and title colors, font size, line height, frame width, and scale.
- Reorder tracked currencies from the settings panel.
- Full profile system (per-character, per-class, per-realm, or shared) powered by AceDB.

## Installation

1. Copy the `EllasCurrencyTracker` folder into your WoW `Interface/AddOns/` directory.
2. Ensure the folder contains:
   - `EllasCurrencyTracker.toc`
   - `embeds.xml`
   - `Core.lua`
   - `Config.lua`
   - `Libs/` directory (with bundled Ace3 libraries)
3. Start or reload WoW and enable the addon from the AddOns menu.

## Usage

### Slash Commands

| Command | Description |
|---------|-------------|
| `/ect config` | Open the settings panel |
| `/ect add <id\|link>` | Add a currency by ID or link |
| `/ect remove <id>` | Remove a tracked currency |
| `/ect list` | List tracked currencies in chat |
| `/ect grow up\|down` | Change growth direction |
| `/ect anchor` | Toggle anchor move mode |
| `/ect reset` | Reset current profile to defaults |
| `/ect help` | Show help |

### Settings Panel

Open via `/ect config` or through the WoW **Options > AddOns > Ella's Currency Tracker** panel.

The settings panel has four tabs:

- **Display** - General settings (title toggle, growth direction), appearance (font/title colors), and sizing (font size, line height, frame width/scale).
- **Currencies** - Searchable, categorized list of all discovered currencies. Toggle checkboxes to add or remove currencies from tracking.
- **Tracked Order** - Reorder or remove tracked currencies using Move Up / Move Down / Remove buttons.
- **Profiles** - Create, copy, delete, and switch between profiles (powered by AceDB).

## Compatibility

- WoW Retail 11.x (The War Within)
- WoW Retail 12.0 (Midnight)

## Libraries

This addon uses the [Ace3](https://www.wowace.com/projects/ace3) framework:

- **AceAddon-3.0** - Addon lifecycle management
- **AceDB-3.0** - SavedVariables with profile support
- **AceDBOptions-3.0** - Profile management UI
- **AceConsole-3.0** - Slash command handling
- **AceEvent-3.0** - Event registration
- **AceConfig-3.0** - Declarative settings UI
- **AceGUI-3.0** - Widget toolkit (used by AceConfigDialog)

Libraries are bundled in the `Libs/` directory and managed via `.pkgmeta` for automated packaging.

## Migration from v1.x

If upgrading from the pre-Ace3 version, your tracked currencies and settings will be automatically migrated to the new profile format on first load. The old `EllasCurrencyCharacterProfile` per-character variable is no longer used.

## Contributing

Contributions, bug reports and feature requests are welcome. If you want to contribute:

1. Open an issue describing the change or bug.
2. Fork the repository and create a feature branch.
3. Submit a pull request with a clear description and any testing notes.

Please keep changes small and focused; follow the existing coding style.

## License & Credits

This addon was created by theswiftfox and is licensed under MIT. The WoW API used is subject to the terms of Blizzard Entertainment.
