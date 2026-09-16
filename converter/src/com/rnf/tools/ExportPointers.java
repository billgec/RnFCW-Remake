package com.rnf.tools;

import com.rnf.assets.DataSsaArchive;
import com.rnf.gltf.Json;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Exports the original mouse pointers from {@code db\dbmousepointer.dat} (63 records of 224
 * bytes: name[100], texture path[100], six ints) to {@code cursors/<name>.png} plus
 * {@code cursors/cursors.json} (pointer name -&gt; png).
 *
 * <p>Pointer textures are either DDS or the third {@code .sst} variant: a 15-byte header
 * followed by an uncompressed TGA (type 2, 32 bpp) and its smaller mip levels.
 */
public final class ExportPointers {

    public static void main(String[] args) throws Exception {
        Path out = Path.of(args[1]).resolve("cursors");
        Files.createDirectories(out);
        Map<String, Object> index = new LinkedHashMap<>();
        try (DataSsaArchive archive = new DataSsaArchive(args[0])) {
            ByteBuffer table = ByteBuffer.wrap(archive.readFile("db\\dbmousepointer.dat")).order(ByteOrder.LITTLE_ENDIAN);
            int count = table.getInt(0);
            int size = (table.capacity() - 4) / count;
            for (int i = 0; i < count; i++) {
                int base = 4 + i * size;
                String name = cString(table, base, 100);
                String texture = cString(table, base + 100, 100);
                BufferedImage image = null;
                for (String candidate : List.of(texture + ".dds", texture + ".sst", texture + ".tga")) {
                    if (!archive.contains(candidate)) continue;
                    try {
                        image = decode(archive.readFile(candidate));
                        break;
                    } catch (Exception e) {
                        System.err.println("warn: " + candidate + ": " + e.getMessage());
                    }
                }
                if (image == null) {
                    System.err.println("pointer " + name + ": no usable texture " + texture);
                    continue;
                }
                String file = name.toLowerCase().replaceAll("[^a-z0-9]+", "_") + ".png";
                ImageIO.write(image, "png", out.resolve(file).toFile());
                index.put(name, file);
            }
        }
        Files.writeString(out.resolve("cursors.json"), Json.pretty(index));
        System.out.println(index.size() + " pointers exported");
    }

    static BufferedImage decode(byte[] data) {
        for (int i = 0; i + 4 <= Math.min(64, data.length); i++) {
            if (data[i] == 'D' && data[i + 1] == 'D' && data[i + 2] == 'S' && data[i + 3] == ' ') {
                return DdsToPng.decode(java.util.Arrays.copyOfRange(data, i, data.length));
            }
        }
        int tga = data.length > 33 && data[15 + 2] == 2 ? 15 : (data[2] == 2 ? 0 : -1);
        if (tga < 0) throw new IllegalArgumentException("neither DDS nor TGA");
        return decodeTga(data, tga);
    }

    /** Uncompressed true-colour TGA (24/32 bpp), honouring the top-left origin flag. */
    static BufferedImage decodeTga(byte[] d, int base) {
        ByteBuffer b = ByteBuffer.wrap(d).order(ByteOrder.LITTLE_ENDIAN);
        int idLength = d[base] & 0xFF;
        int width = b.getShort(base + 12) & 0xFFFF;
        int height = b.getShort(base + 14) & 0xFFFF;
        int bpp = d[base + 16] & 0xFF;
        boolean topDown = (d[base + 17] & 0x20) != 0;
        int bytes = bpp / 8;
        int p = base + 18 + idLength;
        BufferedImage img = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < height; y++) {
            int row = topDown ? y : height - 1 - y;
            for (int x = 0; x < width; x++) {
                int blue = d[p] & 0xFF, green = d[p + 1] & 0xFF, red = d[p + 2] & 0xFF;
                int alpha = bytes == 4 ? d[p + 3] & 0xFF : 255;
                img.setRGB(x, row, (alpha << 24) | (red << 16) | (green << 8) | blue);
                p += bytes;
            }
        }
        return img;
    }

    private static String cString(ByteBuffer b, int offset, int max) {
        int end = offset;
        while (end < offset + max && b.get(end) != 0) end++;
        byte[] bytes = new byte[end - offset];
        b.get(offset, bytes);
        return new String(bytes, StandardCharsets.ISO_8859_1);
    }
}
