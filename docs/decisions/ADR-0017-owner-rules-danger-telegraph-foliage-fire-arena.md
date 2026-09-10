# ADR-0017: Owner Rules — No Danger Telegraph, Foliage Fire, Training Arena Spawner

Status: Accepted (owner instructions of 2026-09-10 late evening, applied verbatim)

Date: 2026-09-10

Related: plan §5.2, §7.3 (foliage flammability "stage data, default off"), §8.7, §10.6 (danger telegraphs), §18.4; ADR-0016 (foliage cover); `docs/CURRENT_REVIEW.md` "Training Arena"

## Context

Three owner instructions from the device session:

1. "移除掉红圈这个设计，不需要警告" — remove the red-ring danger telegraph.
   Plan §10.6 asked that AP/Explosion/Fire/Mine enemies "be recognizable
   as threats before they fire"; the implementation was a tinted dashed
   ring with a warning triangle over those tanks. The owner does not
   want a warning.
2. "火焰弹打到草坪的时候，应该需要把相邻的草坪都点着" — fire that reaches grass must
   ignite the neighbouring grass. Plan §7.3 left foliage flammability
   off by default.
3. "训练场还是改成我点击一个按钮增加一个类型的坦克吧，不同类型的坦克按照抵抗力从低到高排序让我选择"
   — the Training Arena adds enemies per button, one archetype each,
   ordered by resistance from low to high.

## Decision

1. **No danger telegraph.** The scene's threat marker is removed; the
   `px_status_danger` frames stay in the atlas unused. Threat legibility
   rests on the tank silhouettes, turrets and colours (§12.3). Plan §10.6's
   telegraph requirement is superseded for V1 by this owner decision.
2. **Foliage fire (GameCore, ruleset data).** `WeaponRuleset.
   foliageSpreadDelayTicks` (20; 0 disables) and `foliageBurnsAway`
   (true). A flame patch placed on a foliage cell carries
   `FireHazardState.spreadsAtTicks` = lifetime − delay; when its
   remaining lifetime reaches that value it ignites the four orthogonal
   foliage neighbours that hold no flame yet — ownerless patches
   (sentinel −1: no active-count slot, so the wildfire never blocks the
   shooter's next volley) that keep the parent's team, filter, damage
   and full lifetime and spread on in turn (parents ascending by entity
   id, neighbours up/right/down/left). Foliage a flame goes out on
   becomes ground (`terrainChanged`); the scene leaves a burned-grass
   decal (`px_foliage_burned`). Replay format 7.
3. **Training Arena spawner.** The arena starts with no enemies; the
   training panel lists all 24 archetypes as buttons sorted by
   resistance = armour + shield (ties by family, then tier), labelled
   family + tier + resistance; each tap adds one tank at the next spawn
   cell (nearest free footprint) and enrols it in the respawn-on-death
   rule; "清空敌人" removes them all.

## Consequences

- Stage authoring: a foliage patch is now a fuse — fire enemies (VS-02)
  and the player's flamethrower burn grass cover away; VS-02's cover is
  temporary once fire is used. The AI does not plan around it.
- Tests: `FoliageFireTests` (spread after the delay to foliage only,
  once per patch, onward spreading, burn-away, data switches,
  serialization, the shooter not charged), `TrainingArenaTests` (empty
  start, roster order, spawner, clear).
- Open: whether burned grass should regrow; whether enemies should avoid
  burning cells (§10.4 cost profiles); a spread sound.
