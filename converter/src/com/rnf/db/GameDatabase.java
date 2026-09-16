package com.rnf.db;

import com.rnf.assets.DataSsaArchive;

import java.io.IOException;

/**
 * The three {@code db\*.dat} tables this project reads, loaded together
 * straight out of the original game's encrypted archive. They only make sense
 * as a set: an entry in a building's build list is an ID that has to be looked
 * up in {@link DbObjects} <em>and</em> {@link DbTechTree}, both of them end up
 * pointing into {@link DbButtons} for the icon and panel cell, and
 * {@link DbGraphics} is the hop from there towards the actual mesh.
 */
public final class GameDatabase {

    public final DbObjects objects;
    public final DbButtons buttons;
    public final DbTechTree techTree;
    public final DbGraphics graphics;

    private GameDatabase(DbObjects objects, DbButtons buttons, DbTechTree techTree, DbGraphics graphics) {
        this.objects = objects;
        this.buttons = buttons;
        this.techTree = techTree;
        this.graphics = graphics;
    }

    public static GameDatabase load(DataSsaArchive archive) throws IOException {
        return new GameDatabase(
                DbObjects.parse(archive.readFile("db\\dbobjects.dat")),
                DbButtons.parse(archive.readFile("db\\dbButtons.dat")),
                DbTechTree.parse(archive.readFile("db\\dbtechtree.dat")),
                DbGraphics.parse(archive.readFile("db\\dbgraphics.dat")));
    }

    /** Convenience: the command panel of the first object whose name contains {@code needle}. */
    public CommandPanel.Cell[] panelFor(String needle, String civ) {
        DbObjects.Entry building = objects.findByName(needle);
        if (building == null) return new CommandPanel.Cell[CommandPanel.CELLS];
        return CommandPanel.build(building, civ, objects, buttons, techTree);
    }
}
