package com.rnf.db;

import java.util.ArrayList;
import java.util.List;

/**
 * Builds the command panel the original game shows when you click a building:
 * the 14-cell grid in the bottom right of the HUD, top row (cells 0-6) the
 * upgrades, bottom row (cells 7-13) the trainable units, cell N sitting
 * directly above cell N+7.
 *
 * <p>Everything here comes out of the original data files, not a hand-written
 * list. The chain, verified against the original
 * game:
 *
 * <ol>
 *   <li>the building's own {@code dbobjects} record carries a <b>build list</b>
 *       ({@code +908} count, {@code +1212} entries) of IDs it can produce -
 *       for the Greek barracks that is 74 entries;</li>
 *   <li>each ID resolves either to a unit ({@link DbObjects#byObjectId}) or to
 *       a research ({@link DbTechTree#byId}), which gives its button index;</li>
 *   <li>{@link DbButtons} turns that button index into an icon path and the
 *       cell the entry occupies.</li>
 * </ol>
 *
 * <p>Two filters turn those 74 raw entries into the seven a freshly built
 * Greek barracks actually shows:
 *
 * <ul>
 *   <li><b>Prerequisite.</b> The build list holds every level of every unit
 *       line and every step of every upgrade at once. Tech-tree field
 *       {@code [11]} names the research each one needs; only entries with
 *       {@code [11] == 0} are available on a fresh building. That alone cuts
 *       "Sword Infantry levels 1-5" down to level 1, and "Sword upgrade
 *       2/3/4/5" down to the first step.</li>
 *   <li><b>Civilization.</b> The build list also holds the other three
 *       civilizations' units (all four barracks share one list). There is
 *       <em>no civilization field anywhere</em> in {@code dbobjects} or the
 *       tech tree - that was established the hard way while modding, by
 *       byte-diffing units across civs - so the only discriminator available
 *       is the developer name, which does spell it out ("(Level 1 Greek)").
 *       Matching on that is a stand-in for whatever the engine really does,
 *       and it is why this takes a {@code civ} argument at all.</li>
 * </ul>
 *
 * <p>Cell 0 in {@code dbButtons +216} means "no fixed cell", not "the first
 * cell": the entries that carry it get placed into the first free cell of the
 * row their kind belongs to. For the Greek barracks that is exactly what puts
 * the sword upgrade top-left, above the swordsman - matching the real game.
 */
public final class CommandPanel {

    public static final int CELLS = 14;
    public static final int UNIT_ROW_START = 7;

    public enum Kind { UNIT, UPGRADE }

    /**
     * @param iconPath dbButtons' icon path, no extension (append {@code .dds})
     * @param id       the build-list ID this cell came from
     */
    public record Cell(int index, Kind kind, String name, String iconPath, int id) {}

    private CommandPanel() {}

    private static final String[] CIVILIZATIONS = {"Greek", "Persian", "Egypt", "Rome"};

    /**
     * @param civ one of {@link #CIVILIZATIONS}; entries naming a different
     *            civilization are dropped, entries naming none are kept
     * @return an array of {@link #CELLS} entries, null where the cell is empty
     */
    public static Cell[] build(DbObjects.Entry building, String civ,
                               DbObjects objects, DbButtons buttons, DbTechTree techTree) {
        return build(building, civ, objects, buttons, techTree, false).toArray(new Cell[CELLS]);
    }

    /**
     * @param includeLocked also return entries that still need a research - the remake needs
     *                      the whole ladder up front, the original panel only shows what is
     *                      available right now
     * @return {@link #CELLS} slots, null where empty; with {@code includeLocked} the list can
     *         be longer because several levels share one slot
     */
    public static java.util.List<Cell> build(DbObjects.Entry building, String civ, DbObjects objects,
                                             DbButtons buttons, DbTechTree techTree, boolean includeLocked) {
        List<Cell> fixed = new ArrayList<>();
        List<Cell> unplaced = new ArrayList<>();

        for (int id : building.buildList()) {
            DbTechTree.Entry tech = techTree.byId(id);
            if (tech == null) continue;
            if (tech.prerequisiteId() != 0 && !includeLocked) continue; // needs a research first

            DbObjects.Entry unit = objects.byObjectId(id);
            Kind kind = unit != null ? Kind.UNIT : Kind.UPGRADE;
            String name = unit != null ? unit.devName() : tech.name();
            int buttonIndex = unit != null ? unit.buttonIndex() : tech.buttonIndex();
            if (name.isEmpty() || !matchesCiv(name, civ)) continue;

            DbButtons.Button button = buttons.get(buttonIndex);
            if (button == null || button.iconPath().isEmpty()) continue;
            int slot = button.slot();
            if (slot < 0 || slot >= CELLS) continue;

            Cell cell = new Cell(slot, kind, name, button.iconPath(), id);
            if (slot > 0) fixed.add(cell);
            else unplaced.add(cell);
        }

        java.util.List<Cell> locked = new ArrayList<>();
        Cell[] grid = new Cell[CELLS];
        for (Cell c : fixed) {
            Cell existing = grid[c.index()];
            // A cell can be claimed twice - the ladder carrier is both a unit and a
            // research sharing one button. Whichever kind belongs in that row wins;
            // otherwise first come, first served.
            if (existing == null || (belongsInRow(c) && !belongsInRow(existing))) {
                if (existing != null) locked.add(existing);
                grid[c.index()] = c;
            } else {
                locked.add(c);
            }
        }
        // Only upgrades get auto-placed. Units without a fixed cell are the ones that
        // never appear in the panel at all - the barracks' "Building Defender Archer",
        // for instance, is the garrison archer that pops out when the building is
        // manned, not something you train - and dropping them into the first free cell
        // of the unit row puts an icon in the panel that the original game does not
        // show there. Upgrades with no fixed cell do belong in the row (that is what
        // puts the sword upgrade top-left, above the swordsman).
        for (Cell c : unplaced) {
            if (c.kind() != Kind.UPGRADE) continue;
            for (int i = 0; i < UNIT_ROW_START; i++) {
                if (grid[i] == null) {
                    grid[i] = new Cell(i, c.kind(), c.name(), c.iconPath(), c.id());
                    break;
                }
            }
        }
        java.util.List<Cell> all = new ArrayList<>(java.util.Arrays.asList(grid));
        if (includeLocked) all.addAll(locked);
        return all;
    }

    private static boolean belongsInRow(Cell c) {
        boolean unitRow = c.index() >= UNIT_ROW_START;
        return unitRow == (c.kind() == Kind.UNIT);
    }

    private static boolean matchesCiv(String name, String civ) {
        boolean named = false;
        for (String other : CIVILIZATIONS) {
            if (!containsIgnoreCase(name, other)) continue;
            if (other.equalsIgnoreCase(civ)) named = true;
            else return false; // explicitly another civilization's entry
        }
        return named || !mentionsAnyCiv(name);
    }

    private static boolean mentionsAnyCiv(String name) {
        for (String c : CIVILIZATIONS) {
            if (containsIgnoreCase(name, c)) return true;
        }
        return false;
    }

    private static boolean containsIgnoreCase(String haystack, String needle) {
        return haystack.toLowerCase().contains(needle.toLowerCase());
    }
}
