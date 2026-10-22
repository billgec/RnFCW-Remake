package com.rnf.tools;

import com.rnf.assets.DataSsaArchive;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.Locale;
import java.util.stream.Stream;

/**
 * Copies the original's music and the sounds the remake uses into {@code game/assets/original}.
 *
 * <p>The original keeps its audio in two places. Music ({@code Data\Music\Song1\*.mp3}) and
 * the voice lines ({@code Data\Sounds\High\A_VO_*.wav}) sit loose in the install - one set
 * of voices per civilization ({@code A_VO_G} Greek, {@code _E} Egypt, {@code _P} Persia,
 * {@code _R} Rome) plus {@code A_VO_ALL} for what everybody shares, the death screams. The
 * effects (weapons, work, buildings, the hero) are inside {@code data.ssa} under
 * {@code sounds\high\a_*.wav}. The mapping of objects to sounds is in {@code dbsounds} and
 * {@code dbsoundgroups}, but the file names spell out what every sound is, so the remake
 * keeps its own readable table instead ({@code game/data/sounds.json}).
 *
 * <p>Names are made safe on the way: lower case, no {@code a_} prefix, every run of spaces
 * and dashes turned into one underscore - {@code A_VO_G-Swordsman1.wav} becomes
 * {@code vo_g_swordsman1.wav}.
 *
 * <pre>ExportSounds &lt;data.ssa&gt; &lt;out root&gt; &lt;civ letter, e.g. G&gt;</pre>
 */
public final class ExportSounds {

    /** Effect sounds worth taking out of the archive: fighting, dying, working, the hero. */
    private static final List<String> EFFECTS = List.of(
            "sword", "spear", "shield", "whoosh", "arrow", "bow", "flame", "flamming",
            "death", "scream", "splat", "impale", "pain",
            "chop", "mine", "hammer", "wood split", "tree break", "building construction",
            "hero ", "create ", "march", "horse", "infantry run");

    public static void main(String[] args) throws IOException {
        if (args.length < 3) {
            System.err.println("usage: ExportSounds <data.ssa> <out root> <civ letter>");
            System.exit(2);
        }
        Path dataSsa = Path.of(args[0]);
        Path out = Path.of(args[1]);
        String civ = args[2].toUpperCase(Locale.ROOT);
        Path install = dataSsa.getParent();

        int music = copyAll(install.resolve("Music").resolve("Song1"), out.resolve("music"), ".mp3", "");
        Path voices = install.resolve("Sounds").resolve("High");
        int voice = copyAll(voices, out.resolve("sounds").resolve("voice"), ".wav", "A_VO_" + civ)
                + copyAll(voices, out.resolve("sounds").resolve("voice"), ".wav", "A_VO_ALL");

        int effects = 0;
        Path sfx = out.resolve("sounds").resolve("sfx");
        Files.createDirectories(sfx);
        try (DataSsaArchive archive = new DataSsaArchive(dataSsa.toString())) {
            for (String entry : archive.list()) {
                String lower = entry.toLowerCase(Locale.ROOT);
                if (!lower.startsWith("sounds\\high\\a_") || !lower.endsWith(".wav")) continue;
                String name = lower.substring("sounds\\high\\".length());
                if (EFFECTS.stream().noneMatch(name::contains)) continue;
                Files.write(sfx.resolve(safeName(name)), archive.readFile(entry));
                effects++;
            }
        }
        System.out.printf("music %d, voice lines %d, effects %d%n", music, voice, effects);
    }

    private static int copyAll(Path from, Path to, String extension, String prefix) throws IOException {
        if (!Files.isDirectory(from)) {
            System.err.println("missing " + from);
            return 0;
        }
        Files.createDirectories(to);
        int copied = 0;
        try (Stream<Path> files = Files.list(from)) {
            for (Path file : files.toList()) {
                String name = file.getFileName().toString();
                if (!name.toLowerCase(Locale.ROOT).endsWith(extension) || !name.startsWith(prefix)) continue;
                Files.copy(file, to.resolve(safeName(name)), StandardCopyOption.REPLACE_EXISTING);
                copied++;
            }
        }
        return copied;
    }

    static String safeName(String name) {
        String lower = name.toLowerCase(Locale.ROOT);
        if (lower.startsWith("a_")) lower = lower.substring(2);
        int dot = lower.lastIndexOf('.');
        String stem = lower.substring(0, dot).replaceAll("[^a-z0-9]+", "_").replaceAll("^_+|_+$", "");
        return stem + lower.substring(dot);
    }
}
