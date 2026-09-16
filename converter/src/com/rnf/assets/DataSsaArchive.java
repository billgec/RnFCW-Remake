package com.rnf.assets;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.Map;
import java.util.zip.DataFormatException;
import java.util.zip.Inflater;

/**
 * Reader for {@code Data/data.ssa}, the original game's main encrypted asset
 * archive ("rass" format, version 3). Java port of the reverse-engineered
 * format documented in <code>docs/FORMATS.md</code> (crypto verified against
 * LowLevelEngine.dll's {@code FSArchive::ReadHeader}/{@code ReadFAT}/
 * {@code ReadFATFile} via Ghidra + radare2 static analysis).
 *
 * <p>Layout in one sentence: a 12-byte header, a directory that is
 * XOR-then-zlib-decoded with a fixed key, and per-file payloads that are
 * XOR'd with their own individual key before being ZL01/PK01-decompressed.
 */
public final class DataSsaArchive implements AutoCloseable {

    /** Fixed 32-byte XOR key for the archive directory, from LowLevelEngine.dll RVA 0x1c35f4. */
    private static final byte[] FAT_KEY = {
            (byte) 0x64, (byte) 0x34, (byte) 0x68, (byte) 0x82, (byte) 0x55, (byte) 0x87, (byte) 0x49, (byte) 0x32,
            (byte) 0xd3, (byte) 0x02, (byte) 0x01, (byte) 0xb2, (byte) 0x12, (byte) 0x73, (byte) 0x13, (byte) 0xff,
            (byte) 0x59, (byte) 0x21, (byte) 0x39, (byte) 0x57, (byte) 0x54, (byte) 0x30, (byte) 0xef, (byte) 0xa3,
            (byte) 0x56, (byte) 0x23, (byte) 0x99, (byte) 0x48, (byte) 0x98, (byte) 0xb1, (byte) 0xa9, (byte) 0x48,
    };

    private record Entry(long start, long end, byte[] key) {
        long onDisk() { return end - start; }
    }

    private final RandomAccessFile file;
    private final Map<String, Entry> entries = new HashMap<>();

    public DataSsaArchive(String path) throws IOException {
        file = new RandomAccessFile(path, "r");
        readDirectory();
    }

    public int fileCount() {
        return entries.size();
    }

    /** All internal paths, lower-cased with backslashes, sorted. */
    public java.util.List<String> list() {
        java.util.List<String> names = new java.util.ArrayList<>(entries.keySet());
        java.util.Collections.sort(names);
        return names;
    }

    public boolean contains(String internalPath) {
        return entries.containsKey(normalize(internalPath));
    }

    /** e.g. {@code readFile("db\\dbobjects.dat")} or {@code readFile("textures/but_ymjavelint.dds")}. */
    public byte[] readFile(String internalPath) throws IOException {
        Entry e = entries.get(normalize(internalPath));
        if (e == null) throw new IOException("not found in data.ssa: " + internalPath);

        byte[] raw = new byte[(int) e.onDisk()];
        synchronized (file) {
            file.seek(e.start);
            file.readFully(raw);
        }

        int klen = (int) Math.min(raw.length, 32);
        for (int i = 0; i < klen; i++) {
            raw[i] ^= e.key[i];
        }
        if (raw.length <= 12) return raw;

        String tag = new String(raw, 0, 4, java.nio.charset.StandardCharsets.US_ASCII);
        if (tag.equals("ZL01")) {
            long rawLen = ByteBuffer.wrap(raw, 4, 8).order(ByteOrder.LITTLE_ENDIAN).getLong();
            return inflate(raw, 12, raw.length - 12, (int) rawLen);
        } else if (tag.equals("PK01")) {
            long rawLen = ByteBuffer.wrap(raw, 4, 8).order(ByteOrder.LITTLE_ENDIAN).getLong();
            byte[] out = new byte[(int) rawLen];
            System.arraycopy(raw, 12, out, 0, (int) rawLen);
            return out;
        }
        return raw;
    }

    private void readDirectory() throws IOException {
        byte[] hdr = new byte[12];
        file.seek(0);
        file.readFully(hdr);
        ByteBuffer hb = ByteBuffer.wrap(hdr).order(ByteOrder.LITTLE_ENDIAN);
        String magic = new String(hdr, 0, 4, java.nio.charset.StandardCharsets.US_ASCII);
        int version = hb.getInt(4);
        if (!magic.equals("rass")) throw new IOException("not a rass archive: " + magic);
        if (version != 3) throw new IOException("expected version 3, got " + version);

        byte[] fatSzBuf = new byte[4];
        file.readFully(fatSzBuf);
        int fatSize = ByteBuffer.wrap(fatSzBuf).order(ByteOrder.LITTLE_ENDIAN).getInt();

        byte[] fat = new byte[fatSize];
        file.readFully(fat);

        if (fatSize > 0x100) {
            for (int i = 0; i < 32; i++) {
                fat[i] ^= FAT_KEY[i];
            }
        }

        int compLen = ByteBuffer.wrap(fat, 0, 4).order(ByteOrder.LITTLE_ENDIAN).getInt();
        byte[] dir = inflateZlib(fat, 4, compLen);

        int p = 0;
        while (p + 4 <= dir.length) {
            int nameLen = ByteBuffer.wrap(dir, p, 4).order(ByteOrder.LITTLE_ENDIAN).getInt();
            if (nameLen <= 0 || nameLen > 1024 || p + 4 + nameLen + 12 > dir.length) break;

            int nameStart = p + 4;
            int nameEnd = nameStart;
            while (nameEnd < nameStart + nameLen && dir[nameEnd] != 0) nameEnd++;
            String name = new String(dir, nameStart, nameEnd - nameStart, java.nio.charset.StandardCharsets.US_ASCII);

            int rec = p + 4 + nameLen;
            ByteBuffer rb = ByteBuffer.wrap(dir, rec, 12).order(ByteOrder.LITTLE_ENDIAN);
            long start = rb.getInt() & 0xFFFFFFFFL;
            long end = rb.getInt() & 0xFFFFFFFFL;
            rb.getInt(); // "raw" field - not reliable as decompressed size, ignored (see FORMATS.md)

            byte[] key = new byte[32];
            System.arraycopy(dir, rec + 12, key, 0, 32);

            entries.put(normalize(name), new Entry(start, end, key));
            p = rec + 12 + 32;
        }
    }

    private static String normalize(String path) {
        return path.replace('/', '\\').toLowerCase();
    }

    private static byte[] inflateZlib(byte[] src, int offset, int len) throws IOException {
        Inflater inflater = new Inflater(false); // false = expect zlib header (matches LowLevelEngine.dll's inflateInit_)
        inflater.setInput(src, offset, len);
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream(len * 4);
        byte[] buf = new byte[65536];
        try {
            while (!inflater.finished()) {
                int n = inflater.inflate(buf);
                if (n == 0 && inflater.needsInput()) break;
                out.write(buf, 0, n);
            }
        } catch (DataFormatException e) {
            throw new IOException("zlib inflate failed", e);
        } finally {
            inflater.end();
        }
        return out.toByteArray();
    }

    private static byte[] inflate(byte[] src, int offset, int len, int expectedRawLen) throws IOException {
        byte[] out = inflateZlib(src, offset, len);
        if (out.length != expectedRawLen) {
            // not fatal - just means the declared size didn't match; keep what we decoded
            System.err.println("warning: inflate size mismatch, expected " + expectedRawLen + " got " + out.length);
        }
        return out;
    }

    @Override
    public void close() throws IOException {
        file.close();
    }
}
