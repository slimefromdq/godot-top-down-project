# Six New Heroes: Implementation Plan

Sep 26, 2026 · @Lucy

## Overview

Six heroes join the 6v6 roster: two Tanks, one Carry, two Tempo heroes and one Support. Most of their mechanics share a small set of new systems, so those get built once, before any single hero.

| Hero | Title | Role | One-line fantasy |
| --- | --- | --- | --- |
| Pike | The Beloved's Shadow | Tempo | Picks one person and makes sure it's just the two of them |
| Butler | The Composed | Tank | Protects the team with perfect manners, until the hunger wins |
| Nimbus | The Gentleman Spy | Carry (gun) | Unhurried, precise, never breaks a sweat |
| Hazmat | The Contaminant | Tank / Flex bruiser | You're afraid to be near him, and he wants to be near you |
| Sam | The Visitor | Tempo | An alien trying to make friends; his affection is the disable |
| Tilly | The Crash Test Acrobat | Support | Built to be broken, chose to be graceful |

The plan runs in the order you'd build it: roster fit, shared systems, one section per hero, then the objective, items, art and a phased Claude Code build order. Titles are placeholders in the style of the existing roster ("Smiling Assassin", "Living Doll").

## Roster fit

With these six, the roster reaches 12 playable heroes, three per role. The code's `HeroDefinition.Role` enum already has Tank, Carry, Tempo and Flex, so no new role is needed: Tilly ships as Flex, like Melody.

| Role | Current | New | Notes |
| --- | --- | --- | --- |
| Tank | Avery, Cpt. Yellow | Butler, Hazmat | Butler can fill the planned "bodyguard" slot. Hazmat is the slow zone tank Yellow isn't. |
| Carry | Jose, Cosmo, Rook | Nimbus | Nimbus is the planned less-mobile gun carry. Cosmo's magic partner is still open. |
| Tempo | none yet | Pike, Sam | The first two Tempo heroes, both about pulling one person out of position. |
| Flex | Melody | Tilly | Two doll supports; see overlaps below. |

**Overlaps to watch, and how each is resolved:**

- **Pike's Beloved vs Jose's Coin.** Both mark one enemy. The Coin is a skillshot that sets up an execute; Beloved is a relationship that unlocks a teleport. Keep them visually distinct: a gold coin spinning over the head vs a pink heart that only the Beloved and Pike see clearly.
- **Tilly vs Melody.** Both are doll supports who move the team. Melody moves the team *with her* (Grand March formation). Tilly sends the team *where she points* (trampolines). Lore contrast: Melody wants to be real; Tilly was built to be broken and made it art.
- **Hazmat vs Cpt. Yellow.** Both tanks, but Yellow is a fast swarm charge and Hazmat is a slow walking hazard. Keep Hazmat's movement speed below Yellow's at every level.
- **Nimbus vs Jose.** Both precise gunmen. Jose's charged shot is hold-and-release. Nimbus never charges: he scopes to see further and fires slow semi-auto shots.
- **Butler's cloak vs Nimbus's umbrella.** Only Butler blocks. Nimbus's umbrella parries a single projectile.
- **Sam's ult vs Pike's ult.** Both isolate one enemy. Pike's ring traps her *with* the target. Sam's UFO takes the target *away* and drops them somewhere else.

## Shared systems to build first

About two-thirds of what these six need already exists in the codebase. Nine small new systems cover the rest, and most of them will be reused by later heroes too.

**Already there (reuse as-is):**

| Need | Existing piece | Used by |
| --- | --- | --- |
| Stun, root, silence, untargetable | `StatusEffect` crowd-control group | Sam, Pike, Hazmat |
| Taunt | `StatusEffect` compel (`compel_enabled`) | Tilly's All Eyes on Me |
| Carrying someone along | `StatusEffect.carry_enabled` | Sam's Tractor Beam and UFO |
| Launch over walls and ledges | `Actor.launch()` and the `JumpPad` map object | Tilly's trampolines, Nimbus's Descend |
| Aura that follows the caster | `ZoneAbilityData` with `follow_owner` | Hazmat's gas |
| Cast on an ally, with tether | `AllyTargeting` + `tether_range` | Butler, Sam, Tilly |
| Shields | `StatusEffect.shield_amount` | Butler, Sam's Hug |
| Damage over time | `StatusEffect` tick damage | Hazmat |
| Stat and resist changes | `stat_modifiers`, incoming damage multipliers | Butler's frenzy, Tilly's taunt |
| Passive with pips on the HUD | `passive` slot + `PassiveAbility.get_hud_pips` | Butler's hunger |
| Intercepting a lethal hit | `CombatHooks.about_to_die` (Avery's Phoenix Rebirth uses it) | Tilly's Safety Net |
| React to a marked target dying | `status_target_died` hook | Pike's Beloved |

**New systems to build:**

1. **Line-of-sight query.** `CombatQueries.has_line_of_sight(from, to)`: a raycast against world and cover layers. Bushes should also block sight, which makes them stalking spots for Pike. Used by Pike's Obsession passive.
2. **Viewer-filtered visuals.** A `visible_to` rule on attached VFX: everyone, allies, enemies, or specific actors. Pike's heart shows fully only to Pike and her Beloved. Sam's airlock only renders for the victim.
3. **Containment ring.** A zone with a collision edge that blocks a listed set of actors from crossing, in either direction, and blocks projectiles from outside. Pike's ult. Later reusable for arena-style objectives.
4. **Slot swapping.** `AbilityController.swap_slot(slot_id, ability_data)` and `restore_slot(slot_id)`, keeping cooldowns sensible across swaps. Butler's two forms.
5. **Frontal blocker.** A hitbox on the hero's aim arc that eats enemy projectiles and has its own HP. Butler's cloak.
6. **Parry and reflect.** A short window where an incoming projectile flips team and direction. Nimbus's umbrella.
7. **Camera look-ahead.** The camera shifts toward the cursor by a set distance while an ability is active. Nimbus's scope. Also useful as a small global setting.
8. **Placeable jump pad.** Spawn a `JumpPad` at runtime with a team filter, lifetime, charge count and a landing point set by drag. Tilly's trampolines.
9. **Minigame instance.** A per-player overlay that takes over one hero's input for a few seconds, reports a result, and runs with a minimum and maximum duration. Sam's airlock. Design it so the rhythm system (`RhythmPerformer`) could run through it later.

**One global rule: Resolve.** Several of these heroes add hard crowd control at once, so after any stun, root or taunt ends, the victim gets 2 seconds of 50% shorter hard CC. It sits in `game_rules.tres` so it's tunable in one place, and it keeps Sam, Pike, Hazmat and Tilly from chaining someone forever. Built in Phase 0: carries (Tractor Beam, the UFO), self-applied CC (Butler's tie-straightening), pulls you can walk out of and formations are exempt, and `ignores_resolve` exempts anything else.

## Pike, The Beloved's Shadow (Tempo)

Pike wins by choosing one enemy and making every fight a 1v1 with them. Her whole kit keys off one condition, the Beloved: she can reach them from almost anywhere, and she hits hardest when they can't see her coming.

**Look.** A sailor-collar school uniform in glossy pink and white, a heart hair clip, and a too-calm smile. Five chrome kitchen knives with heart-shaped handles orbit her at all times; they are her ammo counter. When she's hunting, her eyes go flat and the orbit tightens.

**Stats** (L1 → L10): Health 560 → 1050 · Weapon 40 → 95 · Magic 10 → 18 · light armor.

| Slot | Ability | What it does | Starting numbers |
| --- | --- | --- | --- |
| Passive | Obsession | While her Beloved can't see her, she moves faster and fades. Her first knife after they see her again deals double damage and roots for 0.75 s. | +20% speed; root at most once per 6 s |
| LMB | Juggled Knives | Fast thrown knives. The orbit refills itself instead of reloading. | 4 shots/s, 5 knives, 1 knife back every 0.5 s; 0.4 × Weapon + 0.5% target max HP |
| RMB | Beloved | Throws a heart. The enemy hit becomes her Beloved and the old one is dropped. | 4 s cooldown |
| Shift | There You Are | Blinks behind her Beloved from anywhere in range. No line of sight or setup needed. With no Beloved it's a short dash. | 900 px range, 10 s cooldown |
| E | Don't Go | A thrown knife that pins the first enemy hit in place. Her Beloved stays pinned longer. | 1 s root (1.5 s on her Beloved), 12 s cooldown |
| Q | Only Us | A heart-shaped containment ring closes around Pike and her Beloved. Nobody gets in or out, including projectiles. | 4 s, 450 px radius, must be within 600 px, 90 s cooldown |

**Built from.** Knives: `RangedAttackData` with `reload_style = REGEN`. Beloved: a `StatusEffect` with `stack_per_applier` and `ends_if_applier_dies`. Obsession: a `PassiveAbility` that checks the new line-of-sight query each tick to toggle the speed and fade, and flags her next knife as empowered. There You Are: `ChargeData` with high speed and `stop_at_target`, aimed at the Beloved. Don't Go: a skillshot with a root `on_hit_status`, longer if the target carries her Beloved status. Only Us: the new containment ring.

**Readability and counterplay.** The Beloved sees a pink heart over their own head, and it beats faster as Pike gets closer, with a matching heartbeat sound; it glows brighter once she's within teleport range. Allies of the Beloved see a smaller heart, so they know to stick close. Because the teleport is easy to reach, the counterplay is in her passive: keep her in view and her burst and root never trigger. Staying near teammates keeps her ult from being a free pick.

**Why the max-HP damage.** 0.4% per knife is about 8 extra damage per hit on a 2000 HP tank, around 30 per second at full speed. Small on carries, meaningful on tanks: it's what lets her win duels she otherwise shouldn't.

## Butler, The Composed (Tank)

Butler is two heroes sharing one body: a protective tank while Composed, a lifestealing bruiser while Starving. The switch happens *to* him when his Hunger fills, and Hunger fills from damage taken, so the harder he tanks the sooner he snaps, usually right at the peak of a fight.

**Look.** Tall and pale in a crisp tailcoat and white gloves, wrapped in a high-collared vampiric cloak lined with wine-red silk, twirling a silver-topped cane. Every movement is a little theatrical. Red eyes, calm expression. Starving, the gloves come off, his hair falls loose, his coat tails split into bat wings and his shadow gets too long. The cloak whips around him like it's hungry too.

**Stats** (L1 → L10): Health 900 → 1750 · Weapon 38 → 78 · Magic 20 → 45 · high armor.

**Passive: Hunger** (0–100). +1 Hunger per 1% of max HP he loses, and +1 per second in fights. At 100 he becomes **Starving** for up to 8 s. Each Bite lowers Hunger by 35; at 0 he recovers. On recovering, he spends 0.6 s straightening his tie (rooted, slightly vulnerable), then gets 3 s of bonus armor.

| Slot | Composed | Starving |
| --- | --- | --- |
| LMB | **Cane**: three-hit melee combo | **Claws**: faster swipes with 25% lifesteal |
| RMB | **Vampiric Cloak**: hold to sweep his cloak up in front of him and block projectiles. The cloak has its own HP (400 → 1100) and regenerates when lowered. Lowering it with a flourish gives a short speed burst. | **Bite**: lunge-grab, 0.5 s stun, drains health and lowers Hunger by 35. 3 s cooldown. |
| Shift | **At Your Service**: dash to an ally and shield them (150 + 60% Magic). Short dash if no ally. 10 s cooldown. | **Pounce**: dash to the enemy nearest the cursor. 6 s cooldown. |
| E | **Polite Refusal**: cane sweep that knocks enemies back 250 px. 9 s cooldown. | **Hiss**: short cone that slows 40% and silences for 1 s. 9 s cooldown. |
| Q | **Dinner Is Served**: fills Hunger instantly and bursts him into a bat swarm. He flies 900 px, untargetable, draining every enemy he passes, then lands already Starving with a full 8 s. 80 s cooldown. | same |

**Built from.** Hunger is a `PassiveAbility` listening to `damage_taken`, with a bar instead of pips. The form change uses the new `swap_slot`. Cloak: the new frontal blocker, plus a speed status on release. At Your Service: `AllyTargeting` + `ChargeData` + shield status. Bite: `MeleeAttackData` with a stun `on_hit_status` and a heal on hit. Bat swarm: `ChargeData` with an untargetable `self_status` and a drain status on every enemy hit.

**Readability and counterplay.** His Hunger bar shows to everyone, in both teams' colours, so allies know the cloak is about to come down and enemies know when to back off. Anti-heal counters his Starving form directly. The tie-straightening moment is the punish window.

## Nimbus, The Gentleman Spy (Carry)

Nimbus is the roster's low-mobility gun carry: slow, heavy, precise shots from further away than anyone else can see. His one escape is a floaty umbrella glide, so positioning is his whole defence.

**Look.** Slim, in a grey pinstripe three-piece suit and bowler hat, powder-blue tie. His weapon is a long black umbrella with the barrel in the tip; opened, the canopy is glossy and translucent like a water droplet. A tiny personal raincloud drifts above him when idle and rains harder when he's scoped in.

**Stats** (L1 → L10): Health 500 → 950 · Weapon 50 → 110 · Magic 10 → 18 · light armor, the lowest movement speed of any Carry.

| Slot | Ability | What it does | Starting numbers |
| --- | --- | --- | --- |
| Passive | Steady Hand | Each second standing still adds damage to his next shot. | +10% per second, up to +40% |
| LMB | Umbrella Rifle | Semi-auto, heavy, fast-travelling shots that pierce one target. | 1.1 shots/s, 5 rounds, 1.2 × Weapon |
| RMB | Scope | Hold: the camera shifts toward the cursor and a thin laser shows his aim line to everyone. | +500 px view, −40% move speed |
| Shift | Descend | Opens the umbrella and glides over walls and ledges, steering freely while airborne. His only mobility, so it's a big one. | up to 1100 px, 1.6 s steerable air time, 22 s cooldown |
| E | Parry | A 0.35 s spin that reflects the first projectile, or stuns a melee attacker for 0.5 s. Success refunds half the cooldown and makes his next shot a crit. | 10 s cooldown |
| Q | Overcast | A raincloud anywhere within two screens. Enemies under it are revealed (even in bushes) and slowed; his shots into it always crit and pierce everyone. | 500 px radius, 6 s, 15% slow, 1.75× crit, 70 s cooldown |

**Built from.** Rifle: `RangedAttackData`, `fire_mode = SEMI`, pierce 1. Scope: the new camera look-ahead, plus a movement `stat_modifier` while held. Descend: `ChargeData` whose movement calls `Actor.launch()` so it clears ledges like a jump pad; steering in the air needs a small script feeding his move input into the flight. Parry: the new reflect window. Overcast: a `GroundZoneData` that applies a reveal status and a "marked for Nimbus" status his gun checks for.

**Built in Phase 2.** Choices the table left open:
- Descend flies over low cover and ledges like a jump pad, but full walls still stop it (the same rule as map jump pads).
- A far cursor is clamped to 1100 px, and steering moves the landing point at 450 px/s.
- A Parry crit uses the same 1.75× as Overcast.
- Steady Hand's bonus is spent by the next shot.
- "Two screens" for Overcast is 3600 px.
- Scope is held while he keeps shooting; its laser is stopped by walls.
- Move speed is 490, against Cosmo's 520, the next-slowest Carry.

**The top-down sniper problem.** In a top-down game a sniper's range is capped by the screen. Scope solves it by moving the camera rather than zooming out, so he still sees nothing behind him. The laser line keeps it fair: you always know which direction a Nimbus shot is coming from, even if he's off your screen.

## Hazmat, The Contaminant (Tank)

Hazmat is a slow walking hazard: his gas makes standing near him get worse every second, and his grab drags people in. He ships as a Tank in code but plays like a bruiser, taking space rather than protecting allies.

**Look.** A bulky, glossy yellow hazmat suit with twin canisters on his back and a black rubber hose. The visor shows nothing inside, only a reflection of blue sky and clouds, very Frutiger Aero, and deeply unsettling. The gas is bubbly, bright chartreuse, with a crisp edge ring so everyone can see where it ends.

**Stats** (L1 → L10): Health 950 → 1850 · Weapon 35 → 70 · Magic 30 → 80 (the gas scales on Magic) · high armor, low speed (always slower than Cpt. Yellow).

| Slot | Ability | What it does | Starting numbers |
| --- | --- | --- | --- |
| Passive | Contamination | A gas aura follows him. Damage ramps up the longer an enemy stays inside, then resets 1 s after they leave. | 220 px radius; 10 + 20% Magic per second, +50% per second inside, up to 3× |
| LMB | Sprayer | A short cone of chemical spray. Enemies hit start their gas ramp one step higher. | 350 px range, auto-fire |
| RMB | Canister | Lobs a canister that bursts into a lingering cloud. Good for denying a Mote spawn or a chokepoint. | 250 px cloud, 6 s, 12 s cooldown |
| Shift | Seal Suit | Seals up and shoves forward, taking less damage. | 400 px, 30% damage reduction for 2 s, 12 s cooldown |
| E | Quarantine | A hose hook that pulls the first enemy hit to him and stuns briefly. | 500 px, 0.4 s stun, 11 s cooldown |
| Q | Containment Breach | The aura swells to full ramp instantly. When it ends it leaves a residue zone behind. | 500 px for 6 s, then an 8 s residue, 90 s cooldown |

**Built from.** Aura: `ZoneAbilityData` with `follow_owner`, plus a small script tracking time-in-zone per target through the zone's `target_*` signals. Sprayer: `RangedAttackData` with many small projectiles and spread. Canister: an exploding `ProjectileData` that leaves a `GroundZoneData`. Quarantine: a skillshot with a pull `on_hit_status` (displacement toward caster) plus a stun. Breach: a script that resizes the aura and spawns the residue zone at the end.

**Built in Phase 1.** Choices the table left open: the gas ticks once a second, so the ramp counts ticks (x1, x1.5 ... x3 on the fifth). All of his gas (aura, Canister cloud, Breach and its residue) shares one ramp per enemy, so standing in two clouds ramps twice as fast. Canister's burst deals 20 + 30% Magic, lands on the cursor up to 800 px away and flies over walls. Seal Suit's shove deals 20 + 30% Weapon and pushes enemies 160 px aside. The residue is 300 px. Move speed is 460, against Cpt. Yellow's 500. Breach is instant, so he keeps fighting while it runs.

**Readability and counterplay.** The ramp is the counterplay: stepping in and out is always safe, standing in it is not. The edge ring must stay readable under every other effect, so draw it on a layer above other ground VFX. Cleanse items and Lucy's salt cleanse reset the ramp, and his low speed means kiting beats him.

## Sam, The Visitor (Tempo)

Sam doesn't understand teams, so most of his abilities work on anyone: allies get something nice, enemies get disabled. His ult, Close Encounter, abducts one enemy into an airlock minigame while Sam flies the UFO somewhere terrible to drop them.

**Look.** A small, round alien in pale lilac with huge glossy eyes and one antenna tipped with a glowing bulb. He wears a "HELLO my name is SAM" sticker; he picked the name himself. His UFO is chrome with a bubble-glass dome, straight out of a 2008 screensaver.

**Stats** (L1 → L10): Health 620 → 1150 · Weapon 25 → 45 · Magic 40 → 110 · medium armor.

| Slot | Ability | On enemies | On allies | Starting numbers |
| --- | --- | --- | --- | --- |
| LMB | Hello! | Little greeting orbs that bounce off walls once | none | 3 shots/s, magic damage |
| RMB | Hug | His arms stretch out across the screen and wrap up the first person they reach; enemies are rooted for 1 s | Shields them | 650 px skillshot that stops on the first ally or enemy; shield 120 + 50% Magic; 9 s cooldown |
| Shift | Tractor Beam | Lifts and carries them, stunned | Lifts and carries them, untargetable (a rescue) | 400 px carry, 14 s cooldown; with no target, a short hover-dash for Sam |
| E | Friendship Bracelet | Links two enemies; they can't get more than 300 px apart | Links two allies; 50% of healing on one is shared with the other | 4 s link, 12 s cooldown |
| Q | Close Encounter | Abducts one enemy into the airlock minigame | none | see below, 80 s cooldown |

**Close Encounter, step by step.**

1. Sam targets an enemy within 700 px. A 0.4 s beam telegraph lands on them; they can still dodge it.
2. The victim is lifted into the UFO: untargetable, can't be damaged, carried under the ship.
3. The victim's screen cuts to the airlock minigame, with a small inset showing where the UFO is on the map.
4. Sam steers the UFO toward his cursor at about 350 px/s. He can keep walking and shooting, but can't use other abilities.
5. The victim escapes (or the timer runs out) and drops wherever the UFO is, with a 0.3 s landing daze.

**The airlock minigame.** A small top-down room, played with normal WASD. The victim starts on the left; the airlock door is on the right. Sam's affection fills the room: slow heart projectiles in simple patterns, "HI!!" speech bubbles that sweep across, and a wobbly hug-arm that grabs at the player's position. Each hit pushes the victim back 60 px. Reaching the door with a short 0.3 s hold opens it. Room length is tuned so a perfect run takes about 1.5 s; the ship forcibly ejects them at 4 s. Outside audio is muffled; inside, Sam chatters happily over a ship intercom.

**Built from.** Hello!: `RangedAttackData` with bouncing `ProjectileData`. Hug: a skillshot projectile that stops on the first actor of either team and applies a root or a shield by team, with a stretchy arm drawn from Sam to the hand. Tractor Beam: `AllyTargeting` extended to accept either team, with different statuses per team; the beam uses `carry_enabled`. Bracelet: a projectile that chains to the nearest second target, then a small script enforcing the 300 px leash each tick. Close Encounter: `carry_enabled` + untargetable on the victim, the new minigame instance for their input, and `movement_component.set_cruise()` to fly the UFO. When multiplayer arrives, the minigame only needs to send the victim's movement input to the server; it can be simulated there like any other actor.

**Readability.** While the UFO is flying, everyone sees a shadow on the ground under it and a small portrait of who's inside. The victim's teammates can follow the shadow to be ready at the drop point.

## Tilly, The Crash Test Acrobat (Flex)

Tilly supports by moving her team, not healing it: trampolines send allies over walls, and her ult catches anyone who would die nearby. She was built to take hits, so her disruption is a taunt that makes enemies aim at her.

**Look.** A crash-test dummy with a performer's grace: smooth jointed limbs, yellow-and-black target circles on her hips and temples, a sequinned acrobat leotard, a trailing ribbon and a neat bun. Her seams glow a little when she lands a flip. She's always smiling; her face was painted that way.

**Stats** (L1 → L10): Health 580 → 1120 · Weapon 30 → 60 · Magic 40 → 100 · medium armor.

| Slot | Ability | What it does | Starting numbers |
| --- | --- | --- | --- |
| Passive | Crumple Zone | Knockbacks and displacements on her are shorter, and after any launch she lands with a flip and a burst of speed. | −40% displacement, +25% speed for 1.5 s |
| LMB | Bouncy Balls | Rubber balls that ricochet off walls. | 2.5 shots/s, 2 bounces |
| RMB | Trampoline | Click to place, drag to aim the landing spot. Allies who step on it are launched there. Enemies who step on it are bounced back the way they came. | 700 px max throw, 10 s or 4 launches, 2 charges, 16 s recharge |
| Shift | Cartwheel | A quick dash. If it ends on one of her trampolines, she launches with it and the cooldown resets. | 350 px, 8 s cooldown |
| E | All Eyes on Me | A dazzling spin. Nearby enemies are forced to walk toward her and target her, while she takes much less damage. | 300 px, 1.25 s taunt, 40% damage reduction, 12 s cooldown |
| Q | Safety Net | A big net zone around her. Any ally inside who would die is instead bounced to her side at 15% health and briefly untargetable, once per ally. | 600 px, 6 s, 1 s untargetable, 100 s cooldown |

**Built from.** Balls: `ProjectileData` with bounce. Trampoline: the new placeable jump pad (a runtime `JumpPad` with team filter, lifetime and charges); the enemy bounce is a displacement status. Cartwheel: `ChargeData`, plus a check for overlapping her own pad at the end. All Eyes on Me: compel status with `compel_overrides_input` and a damage-reduction self status. Safety Net: a zone that subscribes to each ally's `CombatHooks.about_to_die`, the same hook Avery's Phoenix Rebirth uses.

**Readability.** Trampolines always draw both ends, like the map's jump pads, so enemies can wait at the landing ring. That's the counterplay, and it's why pads expire after 4 launches.

## Motes and Wake the Dreamer

Each of the six has a clear job around Motes, and two small objective rules make the Tempo heroes matter there. No Mote code exists in the repo yet, so these rules can go straight into the first Mote implementation.

**Proposed rules:**

- **Jostle.** Any hard displacement (a carry, pull, knockback or launch by an enemy) makes the carrier drop one Mote where they land. Tempo heroes become Mote thieves without any special code per hero.
- **Heavy pockets.** Carriers can use trampolines and jump pads, but each Mote adds 0.1 s of air time, so a greedy carrier is easier to shoot out of the sky.
- **No banking in transit.** Nobody can bank or deliver while airborne, abducted or inside a containment ring.

| Hero | Offence with Motes | Defence against Motes |
| --- | --- | --- |
| Pike | Only Us on an enemy carrier cuts them off from their escort | Her Beloved's Mote count shows to Pike through walls, so she can hunt carriers |
| Butler | At Your Service is a carrier escort: dash to them and shield | Bite jostles a carrier, and Dinner Is Served can dive the whole delivery route |
| Nimbus | Overcast over the enemy Dreamer covers his team's delivery | Picks off carriers from off-screen; Overcast on a spawn reveals who's grabbing |
| Hazmat | Walks carriers in behind his gas | Canister and Containment Breach deny a Mote spawn or block the path to his Dreamer |
| Sam | Tractor Beam carries an allied carrier forward, even into the enemy Dreamer | Close Encounter lifts a carrier out and drops them among his team; the jostled Mote drops at the landing spot |
| Tilly | Trampolines are delivery highways straight to a Dreamer | Safety Net keeps a carrier from dying and dropping everything |

## Items

Each new hero needs at least one clean answer in the shared shop, and a few staples need rulings on how they interact with these kits. No item code exists yet, so this list can seed the first `ItemData` pass alongside your earlier ideas (Vitality Gauntlet, Burn Down, Leap).

| Item | Staple | Twist | Answers or pairs with |
| --- | --- | --- | --- |
| Burn Down | Anti-heal projectile | (your existing idea) | Answers Butler's Starving form and Sam's Bracelet |
| Filter Mask | Magic resist | Active: cleanses you and resets any damage ramp on you | Answers Hazmat, and any future damage-over-time hero |
| Iron Will | Unstoppable (BKB) | 3 s of CC immunity; you also can't be displaced, so you can't be jostled off Motes | Answers Sam's beam, Tilly's taunt, Hazmat's hook |
| Tailwind Boots | Move speed | Double bonus for 2 s after you drop below 30% health | Escape tool against Hazmat and Butler dives |

**Rulings these heroes force:**

- **Iron Will vs Close Encounter.** Unstoppable blocks the beam during its 0.4 s telegraph. Once someone is inside the UFO, buying or activating it does nothing until they're out.
- **Iron Will vs Only Us.** The ring is terrain, not crowd control, so Unstoppable doesn't let you walk out.
- **Leap vs Only Us.** Teleports can't cross the ring either. "Nobody in or out" has to be absolute or the ult stops meaning anything.
- **Anti-heal vs Butler.** Anti-heal reduces Bite's healing but not its Hunger reduction, so it slows him down without trapping him in Starving forever.

## Art direction

The six should look like they came out of the same 2009 web-game lobby: glossy "gel" highlights, chunky soft outlines, saturated bubbly effects and a little chrome. Because the codebase keeps visuals in `VisualProfile` and `VisualCue` resources, all of this is art and profile work; no gameplay code changes.

**House rules for all six:**

- **Gel shine.** Every sprite gets a soft white highlight across its top third, like a Tetris Friends piece or an Aero button. This could be a small addition to `actor_body.gdshader` so it's consistent and cheap.
- **Readable silhouettes first.** From top-down at play size, each hero needs one unmistakable shape: Pike's knife orbit, Butler's cloak, Nimbus's umbrella canopy, Hazmat's back canisters, Sam's antenna bulb, Tilly's ribbon.
- **Team colour lives on the outline and ground ring**, never on the costume, so each hero's palette stays intact.
- **Effects are bubbly, not gritty.** Hits sparkle, heals bloom like bokeh, gas bubbles. Screenshake is allowed; blood is not (Butler's drain is a stream of red sparkles).
- **Ability icons are gel orbs** with a bold single glyph, in the style of a Windows Vista sidebar gadget.

| Hero | Palette | Signature shape | Signature VFX | Mastery accessory for avatars |
| --- | --- | --- | --- | --- |
| Pike | Bubblegum pink, white, chrome | Orbit of five heart-handled knives | Pink heart over the Beloved; the ring closes in lace-edged hearts | Heart hair clip |
| Butler | Black, ivory, wine red | Tailcoat and high-collared cloak | Cloak sweeps open in a silk-lined flourish on block; bats burst out in a swirl of red sparkles | White gloves |
| Nimbus | Slate grey, powder blue | Open umbrella canopy | Rain streaks on his shots; Overcast is a fat glossy cartoon cloud | Bowler hat |
| Hazmat | Hazard yellow, chartreuse | Back canisters and hose | Bubbling gas with a crisp edge ring; visor reflects a blue sky | Sky-reflecting visor |
| Sam | Lilac, mint, chrome | Round body with antenna bulb | Chrome UFO with a bubble dome; tractor beam in rainbow scanlines | "HELLO my name is" sticker |
| Tilly | Crash-test yellow, black, sequin silver | Ribbon trail | Trampolines with star-burst springs; target circles pulse on landing | Target-circle earrings |

**Sam's airlock** is the best place to go full Flash maximalism: a spinning starfield outside the porthole, a lava-lamp console, Sam's face on a glossy CRT monitor, and a MySpace-style marquee scrolling "WELCOME FRIEND!!" across the top.

## Build order

Build the heroes from least to most new code: Hazmat first because he's almost entirely existing parts, Sam last because his ult needs the most new infrastructure. Each phase adds its new systems plus one hero, and ends with a test in the training grounds.

| Phase | New systems | Hero | Done when |
| --- | --- | --- | --- |
| 0 | Resolve rule, line-of-sight query, viewer-filtered VFX | none | A dummy stunned twice in a row gets a 50% shorter second stun; a debug overlay draws sight lines |
| 1 | Ramping zone damage (small script) | Hazmat | Standing in his aura for 4 s deals 3× the first second's damage; stepping out resets it |
| 2 | Camera look-ahead, parry/reflect window | Nimbus | A dummy's bolt reflected by Parry damages the dummy; Scope shows targets 500 px past the screen edge |
| 3 | Placeable jump pad, ally death-intercept zone | Tilly | An ally launched from a trampoline lands on the dragged spot; a lethal hit inside Safety Net bounces the ally to Tilly |
| 4 | `swap_slot` / `restore_slot`, frontal blocker | Butler | Taking 100% of his max HP flips him to Starving; Bites bring him back; the cloak absorbs exactly its HP |
| 5 | Containment ring | Pike | Obsession's speed and root only trigger while her Beloved can't see her; nothing crosses the ring, Leap included |
| 6 | Either-team targeting, two-target leash, minigame instance | Sam | A perfect airlock run takes about 1.5 s, a bad one ejects at 4 s, and the victim lands wherever Sam steered |
| 7 | Mote rules (Jostle, heavy pockets), first items | none | A Tractor-Beamed carrier drops one Mote; Iron Will blocks the Close Encounter telegraph |

**Prompt pattern for each phase.** Keep the phased approach you already use with Claude Code: one prompt for the shared systems, then one for the hero. A template:

```
Read docs/HOW_TO_ADD_A_HERO.md and ROADMAP.md.
Phase N, part 1: add [new system] as a reusable component.
- It must not reference any specific hero.
- Add a row for it to the "You want / Use" table in HOW_TO_ADD_A_HERO.md.
- Add a case for it to tools/heroes/ranged_test so it can be tested alone.
Stop after part 1 and list the files you changed.

Phase N, part 2: scaffold [Hero] with Tools > New Hero from Template.
Fill the definition from the kit below, using existing AbilityData types
wherever the table in HOW_TO_ADD_A_HERO.md has a row for it.
Write a script only where no row fits.
[paste the hero's kit table from this doc]
```

Two habits keep this codebase healthy: every new system gets a row in the How-To table, and every hero gets checked in the balance CSV export against a hero of the same role before moving on.

Full copy-ready prompts for every phase: Implementation prompts

## Open questions

- [ ] Max level is 10 (already set in game\_rules). Stats stay authored over the code's 20-level range, and the L10 numbers above are set to sit beside same-role heroes at level 10 (Avery 1368 HP, Cpt. Yellow 2270, Jose 1008, Melody 1178). For linear growth, growth = (L10 − L1) ÷ 9.
- [x] Should bushes block line of sight? **Yes (Phase 0).** Bushes hide their occupants one way (from inside you see out), vision is shared by team, hidden enemies can still be hit blind, and a `reveals` status (Overcast) shows them. Still open: should attacking from a bush reveal you, and should AI see into bushes?
- [ ] Should Butler's Hunger bar be visible to enemies, or only to his team?
- [ ] Can enemies use Tilly's trampolines? This draft bounces them back instead; letting them use it would be funnier and riskier.
- [ ] Is Jostle (displacement drops a Mote) too punishing for carriers, or should it need two displacements?
- [ ] Should the airlock get harder as Sam levels, or stay fixed so victims can master it?
- [ ] Final titles for all six.
