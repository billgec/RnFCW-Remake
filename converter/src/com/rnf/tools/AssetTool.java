package com.rnf.tools;

import com.rnf.assets.DataSsaArchive;

import java.io.FileOutputStream;
import java.io.IOException;

/**
 * CLI equivalent of the original game repo's {@code tools/rnf_ssa3.pl}, for
 * poking at {@code data.ssa} without leaving the Java project / needing Perl.
 *
 * <pre>
 *   count  &lt;data.ssa&gt;
 *   cat    &lt;data.ssa&gt; &lt;internal-path&gt; &lt;out-file&gt;
 * </pre>
 */
public final class AssetTool {
    public static void main(String[] args) throws IOException {
        if (args.length < 2) {
            System.err.println("usage: count <data.ssa>  |  cat <data.ssa> <internal-path> <out-file>");
            System.exit(1);
        }
        String cmd = args[0];
        try (DataSsaArchive archive = new DataSsaArchive(args[1])) {
            switch (cmd) {
                case "count" -> System.out.println(archive.fileCount() + " entries");
                case "list" -> archive.list().forEach(System.out::println);
                case "cat" -> {
                    if (args.length < 4) {
                        System.err.println("usage: cat <data.ssa> <internal-path> <out-file>");
                        System.exit(1);
                        return;
                    }
                    byte[] data = archive.readFile(args[2]);
                    try (FileOutputStream out = new FileOutputStream(args[3])) {
                        out.write(data);
                    }
                    System.out.println("wrote " + args[3] + " (" + data.length + " bytes)");
                }
                default -> System.err.println("unknown command: " + cmd);
            }
        }
    }
}
