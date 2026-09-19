package com.rnf.tools;

import com.rnf.assets.DataSsaArchive;
import com.rnf.db.CommandPanel;
import com.rnf.db.DbButtons;
import com.rnf.db.DbGraphics;
import com.rnf.db.DbObjects;
import com.rnf.db.DbTechTree;
import com.rnf.gltf.Json;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Exports one civilization: the citizen's buildable structures and, per building, what it
 * trains - converting every involved model, skin and button icon on the way.
 *
 * <pre>ExportCiv &lt;data.ssa&gt; &lt;outRoot&gt; &lt;Civ&gt; "&lt;citizen&gt;" "&lt;hero&gt;" "&lt;building&gt;"...</pre>
 *
 * Writes {@code civs/<civ>.json}: {@code builds} (what citizens can found, in menu order,
 * with the building each one requires) and {@code buildings} (name, trains).
 * Costs come from the tech tree: {@code [10]} is read as gold x1000, {@code [5]} as wood and
 * {@code [7]} as build time in quarter seconds; {@code [11]} is the prerequisite. These are
 * hypotheses consistent across units and buildings, not confirmed in code.
 */
public final class ExportCiv {

    public static void main(String[] args) throws Exception {
        Path outRoot = Path.of(args[1]);
        String civ = args[2];
        Convert.setLanguageDll(Path.of(args[0]).toAbsolutePath().getParent().getParent().resolve("Language2.dll"));
        try (DataSsaArchive archive = new DataSsaArchive(args[0])) {
            var stats = Convert.stats(archive);
            DbObjects objects = stats.objects();
            DbGraphics graphics = stats.graphics();
            DbButtons buttons = DbButtons.parse(archive.readFile("db\\dbButtons.dat"));
            DbTechTree tech = DbTechTree.parse(archive.readFile("db\\dbtechtree.dat"));

            DbObjects.Entry citizen = exact(objects, args[3]);
            String heroName = args.length > 4 ? args[4] : null;
            List<DbObjects.Entry> chosen = new ArrayList<>();
            Map<Integer, String> udfByObjectId = new HashMap<>();
            for (int i = 5; i < args.length; i++) {
                DbObjects.Entry b = exact(objects, args[i]);
                if (b == null) {
                    System.err.println("building not found: " + args[i]);
                    continue;
                }
                chosen.add(b);
                udfByObjectId.put(b.objectId(), definition(graphics, b));
            }
            // A prerequisite may name another variant of a chosen building (SP vs MP):
            // resolve through the object's definition name as well.
            Map<String, String> udfByDevBase = new HashMap<>();
            for (DbObjects.Entry b : chosen) udfByDevBase.put(devBase(b.devName()), definition(graphics, b));

            Map<String, Object> buildings = new LinkedHashMap<>();
            List<Object> builds = new ArrayList<>();
            for (DbObjects.Entry building : chosen) {
                String buildingUdf = definition(graphics, building);
                List<Object> trains = new ArrayList<>();
                List<Object> upgrades = new ArrayList<>();
                List<Object> becomes = new ArrayList<>();
                for (CommandPanel.Cell cell : CommandPanel.build(building, civ, objects, buttons, tech, true)) {
                    if (cell == null) continue;
                    DbTechTree.Entry t = tech.byId(cell.id());
                    String icon = icon(archive, outRoot, cell.iconPath());
                    if (cell.kind() == CommandPanel.Kind.UPGRADE) {
                        Map<String, Object> upgrade = new LinkedHashMap<>();
                        upgrade.put("id", cell.id());
                        String label = t == null ? null : stats.stringById(t.nameStringId());
                        upgrade.put("name", label != null && !label.isBlank() ? label : readableUpgrade(cell.name()));
                        upgrade.put("dev_name", cell.name());
                        upgrade.put("slot", cell.index());
                        upgrade.put("level", t == null ? 0 : t.level());
                        upgrade.put("requires_research", t == null ? 0 : t.prerequisiteId());
                        upgrade.put("unlocks", t == null ? new int[0] : t.unlocks());
                        upgrade.put("icon", icon == null ? "" : icon);
                        upgrade.put("cost", cost(t, true));
                        upgrades.add(upgrade);
                        continue;
                    }
                    DbObjects.Entry unit = objects.byObjectId(cell.id());
                    String udf = definition(graphics, unit);
                    if (udf == null) continue;
                    // A building in another building's panel is not a trainable unit: it is
                    // what this one can be rebuilt into (Improved Tower, Bazaar).
                    if (udf.startsWith("bld_") || udf.startsWith("wall_")) {
                        if (udf.equals(buildingUdf)) continue;
                        Map<String, Object> into = new LinkedHashMap<>();
                        into.put("cost", cost(t, false));
                        into.put("icon", icon);
                        try {
                            Convert.unit(archive, outRoot, udf, unit, into);
                        } catch (Exception e) {
                            System.err.println("FAILED building upgrade " + udf + ": " + e);
                            continue;
                        }
                        Map<String, Object> step = new LinkedHashMap<>();
                        step.put("building", udf);
                        step.put("name", stats.displayName(unit));
                        step.put("slot", cell.index());
                        step.put("level", t == null ? 1 : Math.max(1, t.level()));
                        step.put("requires_research", t == null ? 0 : t.prerequisiteId());
                        step.put("icon", icon == null ? "" : icon);
                        step.put("cost", cost(t, false));
                        becomes.add(step);
                        continue;
                    }
                    if (udfByObjectId.containsValue(udf)) continue;
                    Map<String, Object> extra = new LinkedHashMap<>();
                    extra.put("icon", icon);
                    extra.put("cost", cost(t, false));
                    extra.put("level", t == null ? 1 : Math.max(1, t.level()));
                    extra.put("requires_research", t == null ? 0 : t.prerequisiteId());
                    try {
                        Convert.unit(archive, outRoot, udf, unit, extra);
                    } catch (Exception e) {
                        System.err.println("FAILED unit " + udf + ": " + e);
                        continue;
                    }
                    Map<String, Object> entry = new LinkedHashMap<>();
                    entry.put("unit", udf);
                    entry.put("name", stats.displayName(unit));
                    entry.put("slot", cell.index());
                    entry.put("level", t == null ? 1 : Math.max(1, t.level()));
                    entry.put("line", com.rnf.db.UnitStats.line(unit.devName()));
                    entry.put("requires_research", t == null ? 0 : t.prerequisiteId());
                    trains.add(entry);
                }
                DbTechTree.Entry bt = tech.byId(building.objectId());
                String requires = null;
                if (bt != null && bt.prerequisiteId() != 0) {
                    DbObjects.Entry pre = objects.byObjectId(bt.prerequisiteId());
                    requires = udfByObjectId.get(bt.prerequisiteId());
                    if (requires == null && pre != null) requires = udfByDevBase.get(devBase(pre.devName()));
                }
                Map<String, Object> extra = new LinkedHashMap<>();
                extra.put("cost", cost(bt, false));
                DbButtons.Button button = buttons.get(building.buttonIndex());
                if (button != null && !button.iconPath().isEmpty()) extra.put("icon", icon(archive, outRoot, button.iconPath()));
                extra.put("trains", trains);
                extra.put("upgrades", upgrades);
                extra.put("becomes", becomes);
                extra.put("requires", requires);
                try {
                    Convert.unit(archive, outRoot, buildingUdf, building, extra);
                } catch (Exception e) {
                    System.err.println("FAILED building " + buildingUdf + ": " + e);
                    continue;
                }
                buildings.put(buildingUdf, Map.of("name", stats.displayName(building),
                        "trains", trains, "upgrades", upgrades, "becomes", becomes));
                Map<String, Object> b = new LinkedHashMap<>();
                b.put("building", buildingUdf);
                b.put("name", stats.displayName(building));
                b.put("slot", button == null ? 99 : button.slot());
                b.put("requires", requires);
                builds.add(b);
            }
            // The hero carries the epoch techs ("ACTION - LEVEL 02" ...) in its own build
            // list: levelling the hero with glory is what unlocks the next tier of upgrades,
            // buildings and siege units.
            Map<String, Object> hero = new LinkedHashMap<>();
            DbObjects.Entry heroRecord = heroName == null ? null : exact(objects, heroName);
            if (heroRecord != null) {
                String heroUdf = definition(graphics, heroRecord);
                List<Object> levels = new ArrayList<>();
                for (int id : heroRecord.buildList()) {
                    DbTechTree.Entry t = tech.byId(id);
                    if (t == null || objects.byObjectId(id) != null) continue;
                    int level = heroLevel(t.name());
                    if (level <= 0) continue;
                    Map<String, Object> entry = new LinkedHashMap<>();
                    entry.put("id", id);
                    entry.put("hero_level", level);
                    DbButtons.Button heroButton = buttons.get(t.buttonIndex());
                    entry.put("icon", heroButton == null ? "" : icon(archive, outRoot, heroButton.iconPath()));
                    entry.put("name", "Level " + level);
                    entry.put("requires_research", t.prerequisiteId());
                    entry.put("cost", cost(t, true));
                    entry.put("unlocks", t.unlocks());
                    levels.add(entry);
                }
                levels.sort((x, y) -> Integer.compare((int) ((Map<?, ?>) x).get("hero_level"),
                        (int) ((Map<?, ?>) y).get("hero_level")));
                Map<String, Object> extra = new LinkedHashMap<>();
                extra.put("hero_levels", levels);
                Convert.unit(archive, outRoot, heroUdf, heroRecord, extra);
                hero.put("unit", heroUdf);
                hero.put("name", stats.displayName(heroRecord));
                hero.put("levels", levels);
            }

            Map<String, Object> out = new LinkedHashMap<>();
            out.put("civ", civ);
            out.put("hero", hero);
            out.put("citizen", citizen == null ? null : definition(graphics, citizen));
            out.put("builds", builds);
            out.put("buildings", buildings);
            Path json = outRoot.resolve("civs").resolve(civ.toLowerCase() + ".json");
            Files.createDirectories(json.getParent());
            Files.writeString(json, Json.pretty(out));
            System.out.println("wrote " + json);
        }
    }

    /** "ACTION - LEVEL 02 (Epoch tech)" -> 2, or 0 when the name is not a hero level. */
    private static int heroLevel(String name) {
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("LEVEL\\s+(\\d+)").matcher(name);
        return m.find() ? Integer.parseInt(m.group(1)) : 0;
    }

    /** Fallback label when Language2.dll has no string: "UP - Inf Sword 3 (Greek)" -> "Inf Sword 3". */
    private static String readableUpgrade(String devName) {
        return devName.replaceAll("^A - ", "").replaceAll("^UP - ", "")
                .replaceAll("\\((Greek|Persian|Egypt|Rome)\\)", "").replaceAll("\\s+", " ").trim();
    }

    /** "A - b  Barracks (MP) (Greek)" -> "barracks (greek)" - variant markers removed. */
    private static String devBase(String devName) {
        return devName.replaceAll("^A - b\\s+", "").replaceAll("\\((MP|SP|Tent)\\)", "")
                .replaceAll("\\s+", " ").trim().toLowerCase();
    }

    private static DbObjects.Entry exact(DbObjects objects, String devName) {
        for (DbObjects.Entry e : objects.all()) {
            if (e.devName().trim().equalsIgnoreCase(devName.trim())) return e;
        }
        return objects.findByName(devName);
    }

    private static String definition(DbGraphics graphics, DbObjects.Entry e) {
        DbGraphics.Entry g = e == null ? null : graphics.get(e.graphicsIndex());
        return g == null || g.definitionName().isEmpty() ? null : g.definitionName().toLowerCase();
    }

    /**
     * Units and buildings are paid for in gold and wood; researches (unit upgrades, hero
     * levels) are paid for in glory - the resource the original hands out for kills, own
     * losses, buildings and glory statues.
     */
    private static Map<String, Object> cost(DbTechTree.Entry t, boolean research) {
        Map<String, Object> m = new LinkedHashMap<>();
        if (t == null) {
            m.put(research ? "glory" : "gold", 0);
            if (!research) m.put("wood", 0);
            m.put("time_s", 10.0);
            return m;
        }
        if (research) {
            m.put("glory", t.cost() / 1000);
        } else {
            m.put("gold", t.cost() / 1000);
            m.put("wood", t.wood());
        }
        m.put("time_s", t.buildTimeTicks() / 4.0);
        return m;
    }

    private static String icon(DataSsaArchive archive, Path outRoot, String iconPath) {
        for (String candidate : List.of(iconPath + ".dds", iconPath + ".sst")) {
            if (!archive.contains(candidate)) continue;
            try {
                return "textures/" + Convert.texture(archive, outRoot, candidate);
            } catch (Exception e) {
                System.err.println("warn: icon " + candidate + ": " + e.getMessage());
            }
        }
        return null;
    }
}
