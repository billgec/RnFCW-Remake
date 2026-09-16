package com.rnf.gr2;

import java.io.IOException;

/**
 * Java port of RAD Game Tools' "Oodle 1" compression algorithm (an adaptive
 * range coder over an LZ-style dictionary), as used to compress {@code .gr2}
 * (Granny 2) file sectors.
 *
 * <p>Ported from the independent, from-scratch C reimplementation in
 * <a href="https://github.com/arves100/opengr2">opengr2</a>
 * ({@code libopengrn/oodle1.c}, MPL-2.0), which is itself derived from
 * <a href="https://github.com/Arbos/nwn2mdk">nwn2mdk</a>'s
 * {@code gr2_decompress.cpp}. Not RAD's own code - this is a clean-room
 * community reverse-engineering of the wire format, not a wrapper around
 * RAD's proprietary SDK/DLL.
 *
 * <p>This is a faithful line-for-line port of the algorithm's control flow;
 * see the C source (or docs/FORMATS.md) for the
 * "why", this file mostly just has the "what".
 */
public final class Oodle1Decompressor {

    private Oodle1Decompressor() {}

    /** One decoded {@code TParameter} bitfield struct (12 bytes on disk, per-block). */
    private record Parameters(int decodedValueMax, int backrefValueMax, int decodedCount,
                               int highbitCount, int[] sizesCount) {
        static Parameters read(byte[] src, int pos) {
            // C: unsigned decoded_value_max:9, backref_value_max:23; (one uint32, LSB-first
            // bitfield packing - the overwhelmingly common convention for MSVC/GCC on x86)
            int word0 = readU32(src, pos);
            int decodedValueMax = word0 & 0x1FF;
            int backrefValueMax = (word0 >>> 9) & 0x7FFFFF;
            // unsigned decoded_count:9, padding:10, highbit_count:13; (another uint32)
            int word1 = readU32(src, pos + 4);
            int decodedCount = word1 & 0x1FF;
            int highbitCount = (word1 >>> 19) & 0x1FFF;
            int[] sizesCount = new int[4];
            for (int i = 0; i < 4; i++) sizesCount[i] = src[pos + 8 + i] & 0xFF;
            return new Parameters(decodedValueMax, backrefValueMax, decodedCount, highbitCount, sizesCount);
        }
    }

    /** Range decoder state ({@code TDecoder}). */
    private static final class Decoder {
        long numer;
        long denom;
        long nextDenom;
        byte[] stream;
        int pos; // cursor into stream

        void init(byte[] stream, int pos) {
            this.stream = stream;
            this.pos = pos;
            this.numer = (stream[pos] & 0xFF) >>> 1;
            this.denom = 0x80;
        }

        int decode(int max) {
            for (; denom <= 0x800000L; denom <<= 8) {
                numer <<= 8;
                numer |= ((long) (stream[pos] & 0xFF) << 7) & 0x80;
                numer |= ((long) (stream[pos + 1] & 0xFF) >>> 1) & 0x7f;
                pos++;
            }
            nextDenom = denom / max;
            long v = numer / nextDenom;
            return (int) Math.min(v, max - 1);
        }

        int commit(int max, int val, int err) {
            numer -= nextDenom * val;
            if (val + err < max) {
                denom = nextDenom * err;
            } else {
                denom -= nextDenom * val;
            }
            return val;
        }

        int decodeCommit(int max) {
            return commit(max, decode(max), 1);
        }
    }

    /** Adaptive frequency table ({@code TWeighWindow}). */
    private static final class WeighWindow {
        int countCap;
        int[] ranges;
        int[] values;
        int[] weights;
        int weightTotal;
        int threshIncrease;
        int threshIncreaseCap;
        int threshRangeRebuild;
        int threshWeightRebuild;

        void init(int maxValue, int countCap) {
            this.weightTotal = 4;
            this.countCap = countCap + 1;
            this.ranges = new int[]{0, 0x4000};
            this.weights = new int[]{4};
            this.values = new int[]{0};
            this.threshIncrease = 4;
            this.threshRangeRebuild = 8;
            this.threshWeightRebuild = Math.max(256, Math.min(32 * maxValue, 15160));
            this.threshIncreaseCap = maxValue > 64
                    ? Math.min(2 * maxValue, threshWeightRebuild / 2 - 32)
                    : 128;
        }

        void rebuildRanges() {
            if (ranges.length != weights.length + 1) {
                ranges = new int[weights.length + 1];
            }
            int rangeWeight = 8 * 0x4000 / weightTotal;
            int rangeStart = 0;
            for (int i = 0; i < weights.length; i++) {
                ranges[i] = rangeStart;
                rangeStart += (weights[i] * rangeWeight) / 8;
            }
            ranges[ranges.length - 1] = 0x4000;

            if (threshIncrease > threshIncreaseCap / 2) {
                threshRangeRebuild = weightTotal + threshIncreaseCap;
            } else {
                threshIncrease *= 2;
                threshRangeRebuild = weightTotal + threshIncrease;
            }
        }

        private static int maxElementIndex(int[] arr, int length, int offset) {
            int max = 0, index = offset;
            for (int i = offset; i < length; i++) {
                if (arr[i] > max) { max = arr[i]; index = i; }
            }
            return index;
        }

        void rebuildWeights() {
            int weightTotal = 0;
            for (int i = 0; i < weights.length; i++) {
                weights[i] /= 2;
                weightTotal += weights[i];
            }
            this.weightTotal = weightTotal;

            int weightsLength = weights.length;
            int valuesLength = values.length;
            for (int i = 1; i < weightsLength; i++) {
                while (i < weightsLength && weights[i] == 0) {
                    weights[i] = weights[weightsLength - 1];
                    values[i] = values[valuesLength - 1];
                    weightsLength--;
                    valuesLength--;
                }
            }
            if (weightsLength != weights.length) {
                weights = java.util.Arrays.copyOf(weights, weightsLength);
                values = java.util.Arrays.copyOf(values, valuesLength);
            }

            int it = maxElementIndex(weights, weights.length, 1);
            if (it < weights.length) {
                int tmp = weights[it];
                weights[it] = weights[weights.length - 1];
                weights[weights.length - 1] = tmp;
                tmp = values[it];
                values[it] = values[values.length - 1];
                values[values.length - 1] = tmp;
            }

            if (weights.length < countCap && weights[0] == 0) {
                weights[0] = 1;
                this.weightTotal++;
            }
        }

        /** {@code IndexValuePair}: index==0xFFFF means "value is final", otherwise it's a new-value slot index. */
        record IndexValuePair(int index, int value) {}

        IndexValuePair tryDecode(Decoder decoder) {
            if (weightTotal >= threshRangeRebuild) {
                if (threshRangeRebuild >= threshWeightRebuild) rebuildWeights();
                rebuildRanges();
            }

            int value = decoder.decode(0x4000);
            int rangeit = ranges.length - 1;
            for (int i = 0; i < ranges.length; i++) {
                if (ranges[i] > value) { rangeit = i; break; }
            }
            if (rangeit > 0) rangeit--;

            decoder.commit(0x4000, ranges[rangeit], ranges[rangeit + 1] - ranges[rangeit]);

            int index = rangeit;
            weights[index]++;
            weightTotal++;

            if (index > 0) {
                return new IndexValuePair(0xFFFF, values[index]);
            }

            if (weights.length >= ranges.length && decoder.decodeCommit(2) == 1) {
                int idx = ranges.length + decoder.decodeCommit(weights.length - ranges.length + 1) - 1;
                weights[idx] += 2;
                weightTotal += 2;
                return new IndexValuePair(0xFFFF, values[idx]);
            }

            values = java.util.Arrays.copyOf(values, values.length + 1);
            values[values.length - 1] = 0;
            weights = java.util.Arrays.copyOf(weights, weights.length + 1);
            weights[weights.length - 1] = 2;
            weightTotal += 2;

            if (weights.length == countCap) {
                weightTotal -= weights[0];
                weights[0] = 0;
            }

            return new IndexValuePair(values.length - 1, 0);
        }
    }

    /** Decompression dictionary state ({@code TDictionary}). */
    private static final class Dictionary {
        int decodedSize;
        int backrefSize;
        int decodedValueMax, backrefValueMax, lowbitValueMax, midbitValueMax, highbitValueMax;
        WeighWindow lowbitWindow = new WeighWindow();
        WeighWindow highbitWindow = new WeighWindow();
        WeighWindow[] midbitWindows;
        WeighWindow[] decodedWindows;
        WeighWindow[] sizeWindows;

        void init(Parameters p) {
            decodedSize = 0;
            backrefSize = 0;
            decodedValueMax = p.decodedValueMax();
            backrefValueMax = p.backrefValueMax();
            lowbitValueMax = Math.min(backrefValueMax + 1, 4);
            midbitValueMax = Math.min(backrefValueMax / 4 + 1, 256);
            highbitValueMax = backrefValueMax / 1024 + 1;

            lowbitWindow.init(lowbitValueMax - 1, lowbitValueMax);
            highbitWindow.init(highbitValueMax - 1, p.highbitCount() + 1);

            midbitWindows = new WeighWindow[highbitValueMax];
            for (int i = 0; i < highbitValueMax; i++) {
                midbitWindows[i] = new WeighWindow();
                midbitWindows[i].init(midbitValueMax - 1, midbitValueMax);
            }

            decodedWindows = new WeighWindow[4];
            for (int i = 0; i < 4; i++) {
                decodedWindows[i] = new WeighWindow();
                decodedWindows[i].init(decodedValueMax - 1, p.decodedCount());
            }

            sizeWindows = new WeighWindow[4 * 16 + 1];
            int index = 0;
            for (int i = 0; i < 4; i++) {
                for (int j = 0; j < 16; j++) {
                    sizeWindows[index] = new WeighWindow();
                    sizeWindows[index].init(64, p.sizesCount()[3 - i]);
                    index++;
                }
            }
            sizeWindows[index] = new WeighWindow();
            sizeWindows[index].init(64, p.sizesCount()[0]);
        }

        /** Decompresses one block into {@code out} at {@code pos}; returns bytes written. */
        int decompressBlock(Decoder decoder, byte[] out, int pos) {
            WeighWindow.IndexValuePair d1 = sizeWindows[backrefSize].tryDecode(decoder);
            int d1value = d1.value();
            if (d1.index() != 0xFFFF) {
                d1value = decoder.decodeCommit(65);
                sizeWindows[backrefSize].values[d1.index()] = d1value;
            }
            backrefSize = d1value;

            if (backrefSize > 0) {
                int[] sizes = {128, 192, 256, 512};
                int backrefLen = backrefSize < 61 ? backrefSize + 1 : sizes[backrefSize - 61];
                int backrefRange = Math.min(backrefValueMax, decodedSize);

                WeighWindow.IndexValuePair d3 = lowbitWindow.tryDecode(decoder);
                int d3value = d3.value();
                if (d3.index() != 0xFFFF) {
                    d3value = decoder.decodeCommit(lowbitValueMax);
                    lowbitWindow.values[d3.index()] = d3value;
                }

                WeighWindow.IndexValuePair d4 = highbitWindow.tryDecode(decoder);
                int d4value = d4.value();
                if (d4.index() != 0xFFFF) {
                    d4value = decoder.decodeCommit(backrefRange / 1024 + 1);
                    highbitWindow.values[d4.index()] = d4value;
                }

                WeighWindow.IndexValuePair d5 = midbitWindows[d4value].tryDecode(decoder);
                int d5value = d5.value();
                if (d5.index() != 0xFFFF) {
                    d5value = decoder.decodeCommit(Math.min(backrefRange / 4 + 1, 256));
                    midbitWindows[d4value].values[d5.index()] = d5value;
                }

                int backrefOffset = (d4value << 10) + (d5value << 2) + d3value + 1;
                decodedSize += backrefLen;

                int repeat = backrefLen / backrefOffset;
                int remain = backrefLen % backrefOffset;
                int srcStart = pos - backrefOffset;
                for (int i = 0; i < repeat; i++) {
                    System.arraycopy(out, srcStart, out, pos + i * backrefOffset, backrefOffset);
                }
                System.arraycopy(out, srcStart, out, pos + repeat * backrefOffset, remain);

                return backrefLen;
            } else {
                int i = pos % 4;
                WeighWindow.IndexValuePair d2 = decodedWindows[i].tryDecode(decoder);
                int d2value = d2.value();
                if (d2.index() != 0xFFFF) {
                    d2value = decoder.decodeCommit(decodedValueMax);
                    decodedWindows[i].values[d2.index()] = d2value;
                }
                out[pos] = (byte) (d2value & 0xff);
                decodedSize++;
                return 1;
            }
        }
    }

    private static int readU32(byte[] b, int pos) {
        return (b[pos] & 0xFF) | ((b[pos + 1] & 0xFF) << 8) | ((b[pos + 2] & 0xFF) << 16) | ((b[pos + 3] & 0xFF) << 24);
    }

    /**
     * Decompresses one Oodle-1 sector.
     *
     * @param compressed     compressed sector bytes (the raw on-disk bytes for this sector)
     * @param decompressedLength exact expected output length (from the sector table)
     * @param oodleStop0     sector's {@code oodleStop0} field ("first 16-bit stop")
     * @param oodleStop1     sector's {@code oodleStop1} field ("first 8-bit stop")
     */
    public static byte[] decompress(byte[] compressed, int decompressedLength, int oodleStop0, int oodleStop1)
            throws IOException {
        byte[] out = new byte[decompressedLength];
        if (compressed.length == 0) return out;

        Parameters[] parameters = new Parameters[3];
        for (int i = 0; i < 3; i++) parameters[i] = Parameters.read(compressed, i * 12);

        Decoder decoder = new Decoder();
        decoder.init(compressed, 36); // sizeof(parameters) = 3 * 12 bytes

        int[] steps = {oodleStop0, oodleStop1, decompressedLength};
        int pos = 0;
        for (int i = 0; i < 3; i++) {
            Dictionary dict = new Dictionary();
            dict.init(parameters[i]);
            while (pos < steps[i]) {
                pos += dict.decompressBlock(decoder, out, pos);
            }
        }
        return out;
    }
}
