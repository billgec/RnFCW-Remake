package com.rnf.gr2;

import java.io.IOException;
import java.util.Arrays;

/**
 * Parses a {@code .gr2} (Granny 2) file's container layer: header, file
 * info, sector table, per-sector decompression, and pointer fixups - into
 * one flat, fully-resolved {@code byte[]} that {@link Gr2ElementParser} can
 * walk directly.
 *
 * <p>Format reference: see docs/FORMATS.md and the header comment on
 * {@link Oodle1Decompressor}. Deliberately simplified vs. the C reference
 * (opengr2) in two ways that are safe for the files this game ships:
 * <ul>
 *   <li>Only the exact 32-bit little-endian, non-"extra16" magic/format this
 *   game's files actually use is accepted - not the full magic table.</li>
 *   <li>No endianness marshalling - unnecessary since we always read
 *   little-endian on a little-endian-authored file. Fixups (pointer
 *   resolution) are still applied, since those are needed regardless of
 *   endianness.</li>
 * </ul>
 * References are resolved to plain absolute {@code int} offsets into the
 * flat output buffer (0 = null) instead of the C library's "virtual
 * pointer" indirection table - Java doesn't need real pointers, so this
 * side-steps that whole mechanism.
 */
public final class Gr2Container {

    // The exact 16 magic bytes this game's .gr2 files use: 32-bit, little-endian, format 6.
    private static final int[] MAGIC = {0xcab067b8, 0x0fb16df8, 0x7e8c7284, 0x1e00195e};

    private static final int HEADER_SIZE = 32;
    private static final int FILE_INFO_SIZE = 56; // format 6, no "extra16"
    private static final int SECTOR_ENTRY_SIZE = 44; // 11 x u32

    public final byte[] data;      // flat, decompressed, fixed-up buffer
    public final int typeOffset;   // absolute offset into `data` of the root type-descriptor chain
    public final int rootOffset;   // absolute offset into `data` of the root instance data

    private Gr2Container(byte[] data, int typeOffset, int rootOffset) {
        this.data = data;
        this.typeOffset = typeOffset;
        this.rootOffset = rootOffset;
    }

    public static Gr2Container parse(byte[] file) throws IOException {
        if (file.length < HEADER_SIZE + FILE_INFO_SIZE) {
            throw new IOException("file too small to be a .gr2");
        }
        for (int i = 0; i < 4; i++) {
            if (readU32(file, i * 4) != MAGIC[i]) {
                throw new IOException("not a recognized .gr2 magic (only 32-bit LE / format 6 supported)");
            }
        }

        int fiOff = HEADER_SIZE;
        int format = readU32(file, fiOff);
        int totalSize = readU32(file, fiOff + 4);
        int fileInfoSize = readU32(file, fiOff + 12);
        int sectorCount = readU32(file, fiOff + 16);
        int typeSectorIdx = readU32(file, fiOff + 20);
        int typePosition = readU32(file, fiOff + 24);
        int rootSectorIdx = readU32(file, fiOff + 28);
        int rootPosition = readU32(file, fiOff + 32);

        if (format != 6) throw new IOException("unsupported .gr2 format " + format + " (only 6 supported)");
        if (fileInfoSize != FILE_INFO_SIZE) throw new IOException("unexpected file info size " + fileInfoSize);
        if (totalSize != file.length) throw new IOException("file size mismatch: header says " + totalSize + ", got " + file.length);

        int sectorTableOff = HEADER_SIZE + FILE_INFO_SIZE;
        int[] compressType = new int[sectorCount];
        int[] dataOffset = new int[sectorCount];
        int[] compressedLen = new int[sectorCount];
        int[] decompressLen = new int[sectorCount];
        int[] oodleStop0 = new int[sectorCount];
        int[] oodleStop1 = new int[sectorCount];
        int[] fixupOffset = new int[sectorCount];
        int[] fixupSize = new int[sectorCount];

        int totalDecompressed = 0;
        for (int i = 0; i < sectorCount; i++) {
            int o = sectorTableOff + i * SECTOR_ENTRY_SIZE;
            compressType[i] = readU32(file, o);
            dataOffset[i] = readU32(file, o + 4);
            compressedLen[i] = readU32(file, o + 8);
            decompressLen[i] = readU32(file, o + 12);
            // o+16: alignment - unused here
            oodleStop0[i] = readU32(file, o + 20);
            oodleStop1[i] = readU32(file, o + 24);
            fixupOffset[i] = readU32(file, o + 28);
            fixupSize[i] = readU32(file, o + 32);
            // o+36 marshallOffset, o+40 marshallSize - unused, see class javadoc
            totalDecompressed += decompressLen[i];
        }

        byte[] flat = new byte[totalDecompressed];
        int[] sectorOffsets = new int[sectorCount];
        int cursor = 0;
        for (int i = 0; i < sectorCount; i++) {
            sectorOffsets[i] = cursor;
            switch (compressType[i]) {
                case 0 -> System.arraycopy(file, dataOffset[i], flat, cursor, decompressLen[i]);
                case 1, 2 -> { // Oodle0 / Oodle1 - same algorithm (see Gr2_read.c reference)
                    byte[] compressed = Arrays.copyOfRange(file, dataOffset[i], dataOffset[i] + compressedLen[i]);
                    byte[] decompressed = Oodle1Decompressor.decompress(compressed, decompressLen[i], oodleStop0[i], oodleStop1[i]);
                    System.arraycopy(decompressed, 0, flat, cursor, decompressLen[i]);
                }
                default -> throw new IOException("unsupported sector compression type " + compressType[i]
                        + " (only none/Oodle0/Oodle1 supported)");
            }
            cursor += decompressLen[i];
        }

        // Fixups: for each sector, read (srcOffset,dstSector,dstOffset) triples from the
        // ORIGINAL file bytes at sector.fixupOffset, and overwrite the flat buffer at
        // (sectorOffsets[i]+srcOffset) with the absolute flat offset of (dstSector,dstOffset).
        for (int i = 0; i < sectorCount; i++) {
            for (int k = 0; k < fixupSize[i]; k++) {
                int p = fixupOffset[i] + k * 12;
                int srcOffset = readU32(file, p);
                int dstSector = readU32(file, p + 4);
                int dstOffset = readU32(file, p + 8);
                int resolved = sectorOffsets[dstSector] + dstOffset;
                writeU32(flat, sectorOffsets[i] + srcOffset, resolved);
            }
        }

        int typeAbs = sectorOffsets[typeSectorIdx] + typePosition;
        int rootAbs = sectorOffsets[rootSectorIdx] + rootPosition;
        return new Gr2Container(flat, typeAbs, rootAbs);
    }

    // --- little-endian primitive readers over `data`, absolute offsets ---

    public int readU32At(int pos) { return readU32(data, pos); }
    public float readFloatAt(int pos) { return Float.intBitsToFloat(readU32(data, pos)); }
    public short readU16At(int pos) { return (short) ((data[pos] & 0xFF) | ((data[pos + 1] & 0xFF) << 8)); }
    public byte readU8At(int pos) { return data[pos]; }

    public String readStringAt(int pos) {
        if (pos == 0) return null;
        int end = pos;
        while (end < data.length && data[end] != 0) end++;
        return new String(data, pos, end - pos, java.nio.charset.StandardCharsets.US_ASCII);
    }

    private static int readU32(byte[] b, int pos) {
        return (b[pos] & 0xFF) | ((b[pos + 1] & 0xFF) << 8) | ((b[pos + 2] & 0xFF) << 16) | ((b[pos + 3] & 0xFF) << 24);
    }

    private static void writeU32(byte[] b, int pos, int value) {
        b[pos] = (byte) value;
        b[pos + 1] = (byte) (value >>> 8);
        b[pos + 2] = (byte) (value >>> 16);
        b[pos + 3] = (byte) (value >>> 24);
    }
}
