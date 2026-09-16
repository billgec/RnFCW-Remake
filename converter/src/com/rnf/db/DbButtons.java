package com.rnf.db;

import java.util.ArrayList;
import java.util.List;

/**
 * Reader for {@code db\dbButtons.dat} - 2921 records of 232 bytes, one per
 * clickable thing in the game's command panel.
 *
 * <ul>
 *   <li>{@code +0} developer name (NUL-terminated)</li>
 *   <li>{@code +100} icon texture path, e.g. {@code textures\but_yGSwordInfantry1T}
 *       (no extension - it is a {@code .dds} here)</li>
 *   <li>{@code +204} the record's own index (redundant with its position)</li>
 *   <li>{@code +216} the <b>fixed cell</b> this button occupies in a building's
 *       command panel. The panel is 14 cells, clamped 0..13 in the original
 *       game's code: top row 0-6 are upgrades, bottom row 7-13 are units, and
 *       cell N sits directly above cell N+7. A value of 0 means "no fixed
 *       cell" - the engine places those itself (see {@link CommandPanel}).</li>
 * </ul>
 */
public final class DbButtons {

    private static final int RECORD_SIZE = 232;
    private static final int OFF_NAME = 0;
    private static final int OFF_ICON = 100;
    private static final int OFF_SLOT = 216;

    /** {@code iconPath} has no file extension - append {@code .dds} to load it. */
    public record Button(int index, String devName, String iconPath, int slot) {}

    private final List<Button> buttons;

    private DbButtons(List<Button> buttons) {
        this.buttons = buttons;
    }

    public static DbButtons parse(byte[] data) {
        DbTable table = new DbTable(data, RECORD_SIZE);
        List<Button> out = new ArrayList<>(table.recordCount);
        for (int i = 0; i < table.recordCount; i++) {
            out.add(new Button(i,
                    table.cString(i, OFF_NAME, 100),
                    table.cString(i, OFF_ICON, 100),
                    table.intAt(i, OFF_SLOT)));
        }
        return new DbButtons(out);
    }

    /** Returns null for out-of-range indices (objects with no button use -1). */
    public Button get(int index) {
        return index >= 0 && index < buttons.size() ? buttons.get(index) : null;
    }

    public int size() {
        return buttons.size();
    }
}
