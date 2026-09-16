package com.rnf.assets;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

/**
 * The game's display names, read out of {@code Language2.dll}.
 *
 * <p>The {@code db\*.dat} tables never spell a name out for the player: they
 * carry a numeric string ID ({@code dbobjects +296}, tech tree {@code [18]})
 * and a developer-facing label ("A - b  Barracks (SP) (Greek)") that is only
 * there to make the table readable. The player-facing text lives in a plain
 * Win32 resource-only DLL next to the executable - which means no game code is
 * needed to read it, just a PE resource walk: DOS stub to PE header, data
 * directory entry 2 to the resource tree, then the three usual levels
 * (type / name / language) down to {@code RT_STRING} (type 6).
 *
 * <p>{@code RT_STRING} stores strings in blocks of 16: string {@code n} is
 * entry {@code n % 16} of the block with resource name {@code n / 16 + 1},
 * and each entry is a {@code u16} character count followed by that many UTF-16
 * code units. Reading every block up front is simpler than seeking per lookup,
 * and the whole table is only a few thousand short strings.
 */
public final class StringTable {

    private static final int RT_STRING = 6;

    private final Map<Integer, String> strings;

    private StringTable(Map<Integer, String> strings) {
        this.strings = strings;
    }

    public static StringTable load(Path dllPath) throws IOException {
        byte[] file = Files.readAllBytes(dllPath);
        ByteBuffer buf = ByteBuffer.wrap(file).order(ByteOrder.LITTLE_ENDIAN);

        int peHeader = buf.getInt(0x3C);
        if (buf.getInt(peHeader) != 0x00004550) { // "PE\0\0"
            throw new IOException(dllPath + ": not a PE file");
        }
        int sectionCount = buf.getShort(peHeader + 6) & 0xFFFF;
        int optionalHeaderSize = buf.getShort(peHeader + 20) & 0xFFFF;
        int optionalHeader = peHeader + 24;
        int magic = buf.getShort(optionalHeader) & 0xFFFF;
        // Data directories start after the optional header's fixed part: 96 bytes for
        // PE32, 112 for PE32+ (the extra 16 are widened 64-bit fields).
        int dataDirectories = optionalHeader + (magic == 0x20B ? 112 : 96);
        int resourceRva = buf.getInt(dataDirectories + 2 * 8);
        if (resourceRva == 0) throw new IOException(dllPath + ": no resource directory");

        int sectionHeaders = optionalHeader + optionalHeaderSize;
        int resourceBase = rvaToFile(buf, sectionHeaders, sectionCount, resourceRva);

        Map<Integer, String> out = new HashMap<>();
        // Level 1: resource type. Level 2: block number. Level 3: language - any one
        // will do, this build ships a single localisation per DLL.
        for (Entry type : entries(buf, resourceBase, resourceBase)) {
            if (type.id != RT_STRING || !type.isDirectory) continue;
            for (Entry block : entries(buf, resourceBase, resourceBase + type.offset)) {
                if (!block.isDirectory) continue;
                for (Entry lang : entries(buf, resourceBase, resourceBase + block.offset)) {
                    if (lang.isDirectory) continue;
                    int dataRva = buf.getInt(resourceBase + lang.offset);
                    int dataSize = buf.getInt(resourceBase + lang.offset + 4);
                    int data = rvaToFile(buf, sectionHeaders, sectionCount, dataRva);
                    readBlock(buf, data, dataSize, (block.id - 1) * 16, out);
                    break; // first language only
                }
            }
        }
        return new StringTable(out);
    }

    private record Entry(int id, boolean isDirectory, int offset) {}

    private static Entry[] entries(ByteBuffer buf, int resourceBase, int directory) {
        int named = buf.getShort(directory + 12) & 0xFFFF;
        int byId = buf.getShort(directory + 14) & 0xFFFF;
        Entry[] out = new Entry[named + byId];
        for (int i = 0; i < out.length; i++) {
            int at = directory + 16 + i * 8;
            int name = buf.getInt(at);
            int offset = buf.getInt(at + 4);
            out[i] = new Entry(name & 0x7FFFFFFF, (offset & 0x80000000) != 0, offset & 0x7FFFFFFF);
        }
        return out;
    }

    private static void readBlock(ByteBuffer buf, int at, int size, int firstId, Map<Integer, String> out) {
        int end = at + size;
        for (int i = 0; i < 16 && at + 2 <= end; i++) {
            int length = buf.getShort(at) & 0xFFFF;
            at += 2;
            if (length == 0) continue;
            int bytes = Math.min(length * 2, end - at);
            if (bytes <= 0) break;
            byte[] raw = new byte[bytes];
            buf.duplicate().position(at).get(raw);
            out.put(firstId + i, new String(raw, StandardCharsets.UTF_16LE));
            at += bytes;
        }
    }

    private static int rvaToFile(ByteBuffer buf, int sectionHeaders, int sectionCount, int rva) throws IOException {
        for (int i = 0; i < sectionCount; i++) {
            int header = sectionHeaders + i * 40;
            int virtualAddress = buf.getInt(header + 12);
            int rawSize = buf.getInt(header + 16);
            int rawPointer = buf.getInt(header + 20);
            if (rva >= virtualAddress && rva < virtualAddress + Math.max(rawSize, buf.getInt(header + 8))) {
                return rawPointer + (rva - virtualAddress);
            }
        }
        throw new IOException("RVA 0x" + Integer.toHexString(rva) + " is in no section");
    }

    /** The display name for a {@code dbobjects +296} string ID, or null. */
    public String get(int id) {
        return strings.get(id);
    }

    public int size() {
        return strings.size();
    }
}
