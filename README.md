# Reader Header

Reader Header adds a configurable header to KOReader's reader view. It draws
book metadata and reading status at the top of reflowable documents, such as
EPUB books, and adds its options to KOReader's built-in status bar settings.

## Features

Use Reader Header when you want a top status line that is separate from
KOReader's built-in bottom status bar.

- Shows a header only for reflowable documents.
- Skips off-screen renders, such as page browser and book map thumbnails.
- Provides left, center, and right slots.
- Lets you reorder slot items with KOReader's sort widget.
- Adds an option for KOReader-style Wi-Fi status icons to the header.
- Truncates long values before they can overlap items to their right.
- Lets you configure separators, font size, default bold text, per-item bold
  text, top padding, extra book text padding, and margins.
- Integrates into **Settings** > **Status bar** > **Header**, directly below
  **Alt status bar** when that KOReader menu item is available.

## Install

Install the plugin in KOReader's plugin directory, then enable it from
KOReader's plugin manager.

1. Copy `readerheader.koplugin` into KOReader's `plugins` directory.
2. Start or restart KOReader.
3. Open **Plugin management** and ensure **Reader Header** is enabled.
4. Restart KOReader or reopen the current book if the menu doesn't appear.

<!-- prettier-ignore -->
> [!IMPORTANT]
> Disable older header user patches, such as
> `2-reader-header-centered.lua` or `2-reader-header-cornered.lua`, while this
> plugin is enabled. If both are active, KOReader can draw duplicate headers.

## Settings

Open a book, then go to **Settings** > **Status bar** > **Header**. The
**Header** entry appears directly below **Alt status bar** when KOReader exposes
that menu item. KOReader builds the reader menu when a book opens, so restart
KOReader or reopen the book after installing or updating the plugin.

The **Header** menu includes these options:

- **Enable header** toggles the header on or off.
- **Center items** configures the center slot.
- **Left items** configures the left slot.
- **Right items** configures the right slot.
- **Separator** chooses the value used by the `separator` item.
- **Font size** sets the header font size from a preset list.
- **Bold by default** toggles the default bold style for header items.
- **Hide Wi-Fi when disconnected** hides the wifi item when Wi-Fi is off or
  unavailable. When disabled, Wi-Fi off is shown with KOReader's off icon.
- **Auto-update time** refreshes the header once per minute only when a slot
  shows the `time` item, so the time changes without requiring a page turn.
- **Top padding** changes the space above the header.
- **Book text padding** changes the extra space below the header. **None** keeps
  the book text as close as possible while still reserving enough room for the
  header; **Default** adds the header's top padding as extra space; **Large**
  adds more space.
- **Use book margins** aligns the header with the document margins.
- **Fixed margin** sets the fallback margin when book margins are disabled.
- **Reset defaults** restores the default Reader Header settings.

## Configure slots

Reader Header has three slots: left, center, and right. The plugin infers the
layout from the slots that contain enabled items, so you don't need to choose a separate centered or cornered layout.


Open **Center items**, **Left items**, or **Right items** to configure a slot. In
the item list, you can use these actions:

- Tap a checkmark to show or hide an item.
- Tap an item row to select it, then use the move buttons to change its order.
- Long-press an item row to toggle that item's bold or regular font style.
- Use the confirmation button to save the order and item choices.
- Use the cancel or close button to discard the previewed changes.


## Defaults

Reader Header starts with a compact three-slot configuration. The font and bold
settings inherit from KOReader's status bar unless you override them.

- Header enabled: `true`
- Left slot: `{title}`
- Center slot: `{time}`
- Right slot: `{battery}`
- Separator: `-`
- Font face: `ffont`
- Font size: inherited from KOReader's status bar, or `14`
- Bold by default: inherited from KOReader's status bar, or `false`
- Top padding: `small`
- Hide Wi-Fi when disconnected: `false`
- Auto-update time: `true`
- Book text padding: `none`
- Use book margins: `true`
- Fixed margin: `large`
- Center max width: `100`


## Acknowledgements

Reader Header was inspired and built based on Joshua Cant's
[KOReader.patches](https://github.com/joshuacant/KOReader.patches), especially
`2-reader-header-centered.lua` and `2-reader-header-cornered.lua`.

## Notes

Reader Header patches KOReader's `ReaderView.paintTo` method at runtime to draw
the header. This is the same general approach used by the older user patches,
but the configuration lives in KOReader settings instead of hardcoded Lua
variables.

For reflowable books, the plugin also adds the header height to KOReader's page
top margin so book text does not flow into the header. Changing **Book text
padding**, **Top padding**, font size, bold style, or enabled header items can
make KOReader re-render or re-paginate the book because the usable text area has
changed.

The plugin also appends its settings to KOReader's existing **Status bar** menu.
If you update the plugin while a book is open, KOReader might keep the old menu
until you reopen the book or restart KOReader.
