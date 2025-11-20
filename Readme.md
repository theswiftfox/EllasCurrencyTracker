# EllasCurrencyTracker

Simple currency tracker addon converted from a WeakAuras setup.

Features:
- Show one line per tracked currency with icon, name and amount.
- Add currencies by pasting a currency link (from chat) or by ID.
- Choose growth direction (up or down).
- Drag the anchor to position it anywhere (position saved).

Commands:
- /cl add <currencyID|currencyLink>
- /cl remove <currencyID>
- /cl list
- /cl grow up|down
- /cl anchor   (toggle anchor unlock for dragging)
- /cl reset
- /cl help

Notes:
- The addon attempts to support both modern Retail APIs (C_CurrencyInfo) and older APIs when available.
- If a currency does not show an icon, the icon may not be exposed by the API or the ID is invalid.