# Spell Inspect Mode

![logo](https://github.com/Loadren/spell-inspect-mode/blob/main/logo.jpg?raw=true)

## Download

CurseForge: ([https://www.curseforge.com/wow/addons/spell-inspect-mode](https://www.curseforge.com/wow/addons/spell-inspect-mode))

## Overview

**Spell Inspect Mode** is a World of Warcraft addon inspired by the inspection feature from Baldur's Gate 3. It enhances the default UI by allowing players to easily view detailed information about talents and spells referenced within tooltips. This is particularly useful when talents reference other talents or spells by name, and you want to see what those abilities do without digging through your spellbook.

## Features

- **Inspect Mode Activation**: Instantly view detailed spell information by hovering over a spell or its hyperlink and pressing a designated keybind (You must define it in `Options/Keybindings/Spell Inspect Mode`). This feature is similar to Baldur's Gate 3's Inspect Mode.
- **Color Differentiation**: Easily distinguish between Talents and basic spells with color-coded highlights:
  - Talents are displayed in a light blue color.
  - Basic spells are shown in heirloom color, matching the in-game item rarity color scheme
- **Layered Tooltips**: Open multiple tooltips in sequence, each providing deeper information about linked spells and talents. Simply press the keybind again to view additional tooltips on top of the current one.
- **Exit Mechanism**: Easily exit Inspect Mode by pressing Escape or by using the keybind while not hovering over a spell, stepping back through the stack of opened tooltips.

## Usage

### Activating Inspect Mode
- **Initial Activation**: Hover over a spell or its hyperlink and press your keybind (you have to define it in `Options/Keybinds/Spell Inspect Mode`). The addon will display detailed information about the spell in a custom tooltip, positioned at the cursor for convenience.
- **Layered Inspection**: Hover over highlighted spell names within the tooltip and press the keybind again to open additional tooltips, providing deeper information in layers, just like in Baldur's Gate 3.

### Exiting Inspect Mode
- **Escape Key**: Pressing Escape will exit Inspect Mode, closing all tooltips. This action will also hide the overlay that prevents accidental interactions with the game world.
- **Keybind Exit**: Alternatively, press your keybind without hovering over a spell to close the current tooltip, and continue doing so to close subsequent tooltips in reverse order.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes. If you encounter any bugs or have feature requests, feel free to open an issue on GitHub.
Here's the updated section of your README with the added details about differentiating Talents from basic spells using colors: