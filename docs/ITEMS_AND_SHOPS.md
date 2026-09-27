# Items, shops and neutral objectives

The match's spending side: gold buys items at your base's shop. And its
map side: neutral camps to farm and the Nightmare to fight over. Every
number lives in a `.tres` (items, neutral data, `MatchRules` > Objectives
and Shop); nothing here references a specific hero.

Tests: `tools/match/items_test.tscn` and `tools/match/objectives_test.tscn`
(the shared hooks are also checked in `tools/heroes/infrastructure_test`).

## Items

An item is an `ItemData` (`resources/items/*.tres`), listed in the
`ShopCatalog` (`resources/items/shop_catalog.tres`, set in
`MatchRules.shop_catalog`).

| Field | What it does |
|---|---|
| `tier` | Cheap, Medium or Expensive: the shop's columns. |
| `family` | The shop's rows (`health`, `fire_rate`, `magic`, `active`); the catalog's `families` sets their order and titles. |
| `cost` | Full price. |
| `builds_from` | An upgrade path: owning that item takes its cost off the price, and buying uses it up (so an upgrade never needs a free slot). |
| `stat_modifiers` | `StatModifier`s on the hero's `StatsComponent` (+150 Health, +10% Health, +25 Magic ...). |
| `stat_multipliers` | Always-on multipliers keyed like a status's: `fire_rate`, `move_speed`, `damage`, `damage_taken`, `cooldown_rate` (1.12 = +12%). |
| `active_ability` | Makes it an **active item**: any `AbilityData` (the placeholders use `SelfStatusData`). |
| `color`, `glyph` | The shop button's look. |

The shop's tooltips come from `ItemData.describe()`, built from these
fields, so they never go stale.

### The placeholder set

Three families, three tiers each; each tier builds from the one below and
adds more buffs the more it costs.

| Family | Cheap | Medium | Expensive |
|---|---|---|---|
| **Vitality** (health) | Cozy Blanket, 300: +150 Health | Pillow Fort, 900: +350 Health, +15 Armor | Dreamheart, 2200: +600 Health, +10% Health, +30 Armor, +25 Magic Resist, +3% move speed |
| **Swiftness** (fire rate) | Sugar Rush, 350: +12% fire rate | Night Owl Espresso, 1000: +25% fire rate, +10 Weapon | Insomnia Engine, 2400: +40% fire rate, +25 Weapon, +5% move speed |
| **Reverie** (magic) | Stardust Pouch, 350: +25 Magic | Moonlit Tome, 1000: +55 Magic, cooldowns 10% faster | Crown of Reverie, 2500: +100 Magic, cooldowns 20% faster, +20 Magic Resist |
| **Active** | Dream Bubble, 400: a 3 s shield (120 +20/level), 40 s cooldown | Pocket Overdrive, 800: Overdrive for 4 s (+75% fire rate, +25% move speed), 50 s cooldown | |

Fire rate speeds up guns (`RangedAttackAbility`, `WeaponComponent`): melee
swings aren't timed by fire rate.

### Adding an item

1. Duplicate an item in `resources/items/`, give it a new `id`, and set its
   numbers.
2. Add it to `shop_catalog.tres` `items`. A new family also goes in
   `families` for its row title.
3. For an active item, point `active_ability` at an `AbilityData` (see the
   "You want / Use" table in `HOW_TO_ADD_A_HERO.md`; an instant
   `feel_override` like `resources/items/active/item_feel.tres` suits most).
4. Run `items_test`: it validates the whole catalog.

## Inventory and shopping (ItemInventory)

The `MatchManager` gives every hero in the match an `ItemInventory` (next
to its `UltimateCharge`). It buys through the match's gold
(`MatchManager.spend_gold`, reason `shop`) and applies each item:

* modifiers go on the `StatsComponent` tagged with the owned copy's id, so
  selling one of two copies removes only its own; gaining max HP from a
  purchase gains current HP too, and selling never grants any back;
* multipliers go in `StatusEffectComponent.set_persistent_multipliers()`:
  they count in `get_multiplier()` like a status, but survive deaths and
  `clear()`;
* an active item's ability is built into the `item` slot (a `GameRules`
  slot, `required = false`, key **G** = `hero_item`), exactly like a hero's
  own slots, so the ability bar, input and bots all see it. Selling calls
  `AbilityController.remove_ability()`.

Items stay through deaths. The rules (`MatchRules` > Shop):

* **Where:** in your base (within `shop_radius` of your team's `Shop`, or
  anywhere in your spawn area) or, with `shop_while_dead`, anywhere while
  you're dead. The shop window can be opened anywhere to browse.
* **How many:** `item_slots` passive items (6) and `max_active_items` active
  items (1). A second active is refused: sell the first.
* **Selling** refunds `sell_refund_pct` (60%) of the full cost.

Cues (match profiles, or the hero's own): `item_bought`, `item_sold`.

### The shop window (ShopPanel)

**B** (`shop_toggle`) opens and closes it, Escape closes it. Rows are
families, columns are tiers; each button shows your price right now (with
the full price in brackets when a component comes off it). Disabled buttons
say why in their tooltip ("Not enough gold", "Inventory full", "One active
item only", "Return to base to shop"). Your items are listed underneath:
click one to sell it. The match HUD shows a "B Shop" hint under your gold
whenever you can buy.

### Bots

Bots buy their role plan's `item_build` (see `BOT_AI.md` > Items).

### Debug

F1 > Match has **Items** (give free / buy any catalog item, clear your
items, open the shop, bots shop now, Shop anywhere) and **Neutral
objectives** (jungle camps now, the Nightmare now or its warning now, clear
all, objectives on/off).

### Shops on the map

A `Shop` node (`scripts/items/shop.gd`) with a `team`, placed in each base
(Dream Basin: in the spawn rooms). It only marks where the shop is and
draws a placeholder stall; the stock and prices are the catalog.

## Neutral objectives

A `NeutralCamp` node on the map points at a `NeutralData`
(`resources/match/neutrals/*.tres`). The `ObjectiveDirector` (a child of
the `MatchManager`) runs every camp on the match clock, only while the
match is PLAYING and `MatchRules.objectives_enabled` is on. Monsters are
`NeutralMonster`s (`scenes/match/neutral_monster.tscn`), on the `neutral`
team so both teams can hit them.

| NeutralData group | What it sets |
|---|---|
| Stats | A `StatBlock` on the 20-level range; level = the heroes' average (+ `level_bonus`); `count` monsters per camp (a pack). |
| Schedule | `first_spawn_time`, `respawn_time` after a clear (0 = once per match), `warning_time` + `announce` (banners, minimap ping, off-screen arrow). |
| Fight | A bolt `attack_projectile` + `attack_damage` (`ScalingValue`), `volley_count`/`volley_spread`, a ring every `ring_interval`, `leash_radius`, `reset_time`, `move_speed` (0 = stays put). |
| Rewards | `killer_gold`/`xp`, `team_gold`/`xp` (split over the team), `killer_ult_charge`, `team_ult_charge`, `mote_count` x `mote_value` Motes claimed by the killer's team for `mote_claim_time`, and a `team_status` for the killer's whole team. |
| Look | `look_scene` (the placeholder `NeutralLook` gel blob), `size`, `color`, `icon_color`. |

**Behaviour.** A monster is passive until hit, then fights whoever hit it
last. It gives up, walks home and heals to full when that hero dies, leaves
`leash_radius` of its home, or nobody has hit it for `reset_time`.

**Rewards** are paid per monster slain by a hero; the `team_status` goes
on when the camp's last monster falls. Heroes who are dead then get the
rest of it when they respawn. Motes from a kill are claimed (`Mote.claim`):
only the killing team can pick them up until the claim runs out.

Cues (match profiles): `<id>_warning`, `<id>_spawn`, `<id>_slain`,
`<id>_attack`, `<id>_ring`, `neutral_reset`. Signals on the
`ObjectiveDirector`: `objective_warning`, `objective_spawned`,
`objective_cleared(camp, team, killer)`, `monster_slain`.

### The placeholder set

| Camp | Where (Dream Basin) | Numbers |
|---|---|---|
| **Sleepwalker** | Each Glade and Stilt Ridge (4) | 900 HP (+110/level), 10 armor/MR. Up at 1:00, back 75 s after a clear. Killer 60 gold / 120 XP, team 60 / 150, 2 Motes. |
| **Dream Wisps** | Each Tangle and Driftfield (4) | A pack of 3, 350 HP each (+45/level), they chase a little. Up at 0:45, back 60 s after. Per wisp: killer 25 / 50, team 20 / 50, 1 Mote. |
| **The Nightmare** | The Cradle's centre (1) | 6000 HP (+450/level), 40 armor/MR, one level ahead of the heroes. Once, at 10:00, warned 30 s early. Volleys of 3 plus a 16-bolt ring every 6 s. Killer 300 / 400, team 1000 / 2000, ult charge, 12 Motes worth 5 (claimed 12 s), Nightmare's Bane for 120 s (+15% damage, -10% damage taken, +5% move speed). |

### Adding a camp

1. Make a `NeutralData` (duplicate one in `resources/match/neutrals/`).
2. On Dream Basin, add a `camp(x, y, "<file name>", "<Display Name>")` line
   in `tools/dream_basin/layout.py` (authored half; the rotation makes its
   twin), run `python3 tools/dream_basin/check.py`, and add the node to
   `scenes/maps/dream_basin.tscn` (any other map: place a `NeutralCamp`
   node and set its `data`).
3. Run `objectives_test`.
