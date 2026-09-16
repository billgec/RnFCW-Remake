package com.rnf.tools;

import com.rnf.assets.DataSsaArchive;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.File;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Dev tool: decodes a DXT1/3/5 texture out of data.ssa to a PNG on disk, so
 * you can actually look at what an atlas contains instead of inferring it
 * from UV numbers. {@link com.rnf.gfx.DDSTexture} hands the compressed
 * blocks straight to the GPU and never decodes them on the CPU, so this
 * carries its own (slow, clarity-first) block decoder.
 *
 * <pre>
 *   mvn exec:java -Dexec.mainClass=com.rnf.tools.DdsToPng
 *       -Dexec.args="textures/ui_ymrtst.dds out.png"
 * </pre>
 * (the real archive paths use backslashes)
 */
public final class DdsToPng {

    private static final String DATA_SSA_PATH = "D:/Code/Rise And Fall/Data/data.ssa";

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: DdsToPng <internal data.ssa path> <output.png>");
            System.exit(2);
        }
        byte[] dds;
        try (DataSsaArchive archive = new DataSsaArchive(DATA_SSA_PATH)) {
            dds = archive.readFile(args[0]);
        }
        BufferedImage image = decode(dds);
        ImageIO.write(image, "png", new File(args[1]));
        System.out.println("wrote " + args[1] + " (" + image.getWidth() + "x" + image.getHeight() + ")");
    }

    public static BufferedImage decode(byte[] all) {
        ByteBuffer buf = ByteBuffer.wrap(all).order(ByteOrder.LITTLE_ENDIAN);

        int base = -1;
        for (int i = 0; i <= 32 && i + 4 <= all.length; i++) {
            if (buf.getInt(i) == 0x20534444) { base = i; break; } // "DDS " - .sst files prepend a header
        }
        if (base < 0) throw new IllegalArgumentException("not a DDS file");

        int height = buf.getInt(base + 12);
        int width = buf.getInt(base + 16);
        int fourCC = buf.getInt(base + 84);
        int dataStart = base + 128;

        if (fourCC == 0) return decodeUncompressed(buf, base, width, height, dataStart);
        int blockBytes = switch (fourCC) {
            case 0x31545844 -> 8;  // DXT1
            case 0x33545844, 0x35545844 -> 16; // DXT3, DXT5
            default -> throw new IllegalArgumentException("unsupported fourCC 0x" + Integer.toHexString(fourCC));
        };

        BufferedImage out = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        int blocksX = (width + 3) / 4;
        int blocksY = (height + 3) / 4;

        for (int by = 0; by < blocksY; by++) {
            for (int bx = 0; bx < blocksX; bx++) {
                int off = dataStart + (by * blocksX + bx) * blockBytes;
                int[] alpha = new int[16];
                int colorOff = off;
                switch (fourCC) {
                    case 0x33545844 -> { // DXT3: 16 x 4-bit alpha, then the color block
                        for (int i = 0; i < 16; i++) {
                            int nibble = (all[off + i / 2] >> ((i % 2) * 4)) & 0xF;
                            alpha[i] = nibble * 17; // 0..15 -> 0..255
                        }
                        colorOff = off + 8;
                    }
                    case 0x35545844 -> { // DXT5: interpolated alpha
                        decodeDxt5Alpha(all, off, alpha);
                        colorOff = off + 8;
                    }
                    default -> java.util.Arrays.fill(alpha, 255);
                }

                int c0 = (all[colorOff] & 0xFF) | ((all[colorOff + 1] & 0xFF) << 8);
                int c1 = (all[colorOff + 2] & 0xFF) | ((all[colorOff + 3] & 0xFF) << 8);
                int[] palette = buildPalette(c0, c1, fourCC == 0x31545844);
                int bits = (all[colorOff + 4] & 0xFF) | ((all[colorOff + 5] & 0xFF) << 8)
                        | ((all[colorOff + 6] & 0xFF) << 16) | ((all[colorOff + 7] & 0xFF) << 24);

                for (int py = 0; py < 4; py++) {
                    for (int px = 0; px < 4; px++) {
                        int i = py * 4 + px;
                        int x = bx * 4 + px, y = by * 4 + py;
                        if (x >= width || y >= height) continue;
                        int rgb = palette[(bits >>> (i * 2)) & 3];
                        int a = fourCC == 0x31545844 ? ((rgb == 0 && c0 <= c1) ? 0 : 255) : alpha[i];
                        out.setRGB(x, y, (a << 24) | (rgb & 0xFFFFFF));
                    }
                }
            }
        }
        return out;
    }

    /** Uncompressed surface (no fourCC): bit count + channel masks from the pixel format block. */
    private static BufferedImage decodeUncompressed(ByteBuffer buf, int base, int width, int height, int dataStart) {
        int bits = buf.getInt(base + 88);
        int redMask = buf.getInt(base + 92);
        int greenMask = buf.getInt(base + 96);
        int blueMask = buf.getInt(base + 100);
        int alphaMask = buf.getInt(base + 104);
        int bytes = bits / 8;
        if (bytes < 1 || bytes > 4) throw new IllegalArgumentException("unsupported bit count " + bits);
        BufferedImage out = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int offset = dataStart + (y * width + x) * bytes;
                int value = 0;
                for (int i = 0; i < bytes; i++) value |= (buf.get(offset + i) & 0xFF) << (8 * i);
                int a = alphaMask == 0 ? 255 : channel(value, alphaMask);
                out.setRGB(x, y, (a << 24) | (channel(value, redMask) << 16)
                        | (channel(value, greenMask) << 8) | channel(value, blueMask));
            }
        }
        return out;
    }

    /** Extracts a channel and scales it to 0..255. */
    private static int channel(int value, int mask) {
        if (mask == 0) return 0;
        int shift = Integer.numberOfTrailingZeros(mask);
        int max = mask >>> shift;
        int raw = (value & mask) >>> shift;
        return max == 0 ? 0 : raw * 255 / max;
    }

    private static void decodeDxt5Alpha(byte[] all, int off, int[] alpha) {
        int a0 = all[off] & 0xFF, a1 = all[off + 1] & 0xFF;
        int[] table = new int[8];
        table[0] = a0;
        table[1] = a1;
        if (a0 > a1) {
            for (int i = 1; i <= 6; i++) table[i + 1] = ((7 - i) * a0 + i * a1) / 7;
        } else {
            for (int i = 1; i <= 4; i++) table[i + 1] = ((5 - i) * a0 + i * a1) / 5;
            table[6] = 0;
            table[7] = 255;
        }
        long bits = 0;
        for (int i = 0; i < 6; i++) bits |= ((long) (all[off + 2 + i] & 0xFF)) << (8 * i);
        for (int i = 0; i < 16; i++) alpha[i] = table[(int) ((bits >>> (i * 3)) & 7)];
    }

    private static int[] buildPalette(int c0, int c1, boolean dxt1) {
        int[] p = new int[4];
        p[0] = rgb565(c0);
        p[1] = rgb565(c1);
        if (!dxt1 || c0 > c1) {
            p[2] = lerp(p[0], p[1], 1, 3);
            p[3] = lerp(p[0], p[1], 2, 3);
        } else {
            p[2] = lerp(p[0], p[1], 1, 2);
            p[3] = 0;
        }
        return p;
    }

    private static int rgb565(int c) {
        int r = (c >> 11) & 0x1F, g = (c >> 5) & 0x3F, b = c & 0x1F;
        return ((r * 255 / 31) << 16) | ((g * 255 / 63) << 8) | (b * 255 / 31);
    }

    private static int lerp(int a, int b, int num, int den) {
        int r = (((a >> 16) & 0xFF) * (den - num) + ((b >> 16) & 0xFF) * num) / den;
        int g = (((a >> 8) & 0xFF) * (den - num) + ((b >> 8) & 0xFF) * num) / den;
        int bl = ((a & 0xFF) * (den - num) + (b & 0xFF) * num) / den;
        return (r << 16) | (g << 8) | bl;
    }
}
