# Collection Expedition

A World of Warcraft Retail addon that turns missing mounts and battle pets into personalized collecting expeditions.

## Current version

**v0.2.0**

The current working vertical slice supports Timeless Isle and includes:

- actual mount and battle-pet collection scanning
- filtering of supported collectibles you already own
- 30 / 60 / 120 minute expedition budgets
- open-ended expeditions
- value-aware route planning
- native Blizzard waypoints and SuperTracking
- automatic rerouting after a collection
- temporary skip/reroute behavior
- a "Why?" panel explaining planner assumptions

The addon does **not** automate movement, combat, looting, pet battles, or protected gameplay.

## Install directly with Git

The repository root is the addon folder, so clone it directly into WoW's AddOns directory.

```powershell
cd "D:\Blizzard\World of Warcraft\_retail_\Interface\AddOns"
git clone https://github.com/davidpm1021/CollectionExpedition.git
```

The final path should be:

```text
D:\Blizzard\World of Warcraft\_retail_\Interface\AddOns\CollectionExpedition\CollectionExpedition.toc
```

After future updates:

```powershell
cd "D:\Blizzard\World of Warcraft\_retail_\Interface\AddOns\CollectionExpedition"
git pull
```

Then in game:

```text
/reload
```

## Commands

- `/ce plan` - open the time-budget planner
- `/ce start 30` - start a 30-minute route
- `/ce start 60` - start a 60-minute route
- `/ce start 120` - start a 120-minute route
- `/ce start all` - run open-ended until you stop
- `/ce status` - current target, remaining collectibles, remaining budget
- `/ce why` - open the explanation panel for the current stop
- `/ce next` - skip the current target for this run and reroute
- `/ce show` - reopen the tracker
- `/ce stop` - stop and clear the addon waypoint
- `/ce reset` - reset the current session

## Planner model

Collection Expedition separates two concepts:

- **Useful attempt time:** how long the planner suggests spending at a stop before moving on.
- **Acquisition time:** unknowable for random drops and rare spawns.

The current route score considers travel time, useful attempt time, a conservative relative success heuristic, and extra collection weight for mounts in mixed routes.

These values are planning heuristics, not guarantees.

## Current Timeless Isle dataset

- Thundering Onyx Cloud Serpent
- Ashleaf Spriteling
- Ruby Droplet
- Dandelion Frolicker
- Death Adder Hatchling
- Jademist Dancer
- Ominous Flame
- Skunky Alemental
- Spineclaw Crab
- Gulp Froglet
- Swarmling of Gu'chi
- Jadefire Spirit

## Roadmap

The next development block is focused on:

1. full expedition itinerary preview
2. real elapsed-time countdown
3. stop X-of-N progress
4. adaptive replanning
5. nearby "While You're Here" detours
6. route modes
7. richer source and requirement details
8. expedition history and results
9. reload/logout recovery
10. multi-zone data architecture and another supported region
