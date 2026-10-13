# Thottbot addon for WoW: Forever

Records what you see while you play and writes it to a file you can upload to
https://thottbot4ever.com so the database learns where NPCs stand, what they drop and how
often, what vendors sell, what trainers teach, and who gives and takes each quest.

## Install

1. Download `Thottbot-<version>.zip` from https://thottbot4ever.com/addon.
2. Unpack it so the folder is `World of Warcraft/_classic_beta_/Interface/AddOns/Thottbot/`
   (the folder must contain `Thottbot.toc`).
3. Start the game. If the addon list flags it as out of date, tick "Load out of date AddOns".

Forever loads addons and settings from a previous beta's `WTF` folder; if you played an
earlier beta, check the AddOns list on the character screen shows Thottbot enabled.

## What it records

- Quests you are offered, progress and turn in: text, level, rewards, and which NPC or
  object gave and took them, with your position at the time.
- NPCs you mouse over, target or talk to: id, name, title, level, classification, type,
  reaction, and your position.
- Objects you mouse over (chests, herbs, ore, quest objects): id, name, position.
- Loot windows: the source and every item in it; each corpse counts once.
- Vendors: every item with price, currency and limited stock. Trainers: every spell with
  cost and required level.
- Items you see: name, quality, item level, bind, class, sell price, tooltip lines.
- Screenshots you take with the addon's camera button: the screenshot's file name, what it
  shows (the NPC or object id, or the zone's map id), your map position and the time.

## What it never records

Your character name, realm, guild, level, chat, friends or account. The file holds only the
game entities above, your faction (Alliance or Horde), the addon version and the client
build.

## In game

- Minimap button: hover for status, left click to pause or resume, right click for the
  command list, drag to move.
- Camera button (beside the minimap, drag to move), `/thottbot shot`, or a key you bind under
  Key Bindings → Thottbot: takes a screenshot of your target NPC or object, else what is
  under the mouse, else the zone you are in. The interface is hidden for the shot, except in
  combat, when the game does not allow it. A TGA screenshot format is switched to JPG for the
  shot, since the site takes JPG and PNG only.
- `/thottbot` or `/tb`: `status`, `pause`, `resume`, `clear` (start a fresh file),
  `shot` (the camera button), `probe` (list which client APIs are available), `cursor` (what the client reports for the
  chest, node or herb under your mouse; use it if objects are missing from your uploads),
  `version`.

## Upload

The game writes the file when you log out or `/reload`.

**Automatic (Chrome or Edge):** open https://thottbot4ever.com/addon/watch, log in, and pick
your WoW folder once (the game folder or `_classic_beta_` is best: every account under
`WTF/Account` is found, and so are the cache files below). Tick "Allow on every visit" when
the browser asks, then keep the tab open while you play: every file the game writes is
uploaded for you. Nothing uploads while the tab is closed.

**By hand (any browser):** open https://thottbot4ever.com/addon/upload, log in, and choose
`World of Warcraft/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/Thottbot.lua`.

**Cache files (optional extras):** the game also keeps what your client has been shown in
`World of Warcraft/_classic_beta_/Cache/WDB/enUS/questcache.wdb`, `creaturecache.wdb` and
`gameobjectcache.wdb` (quests, creatures and objects) and in `Cache/ADB/enUS/DBCache.bin`
(item names and stats). Choose them together with `Thottbot.lua` on the upload page, or let
the auto-upload page watch them; only the enUS client's files are read.

**Screenshots:** the auto-upload page also uploads the camera button's screenshots, once the
game has written `Thottbot.lua` (`/reload` or logout), to the page of the NPC, object or zone
they show, where they appear at once with your name. Pick the game folder or `_classic_beta_`
so the page can reach `_classic_beta_/Screenshots`. It reads only the screenshots the button
recorded; other screenshots in the folder are never opened or sent. A screenshot of something
with no page on the site (inside an instance, say) is not uploaded, and the page says so.

Either way, uploading the same file later (after more play) replaces your earlier upload;
nothing is counted twice. `/thottbot clear` starts a new file when you want a clean slate.

## License

MIT — see `LICENSE` in this folder. The code is MIT; the Thottbot name and logo are reserved,
so fork it under your own name and point it at your own service.
