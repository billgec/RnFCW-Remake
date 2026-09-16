package com.rnf.tools;

import com.rnf.gr2.Gr2Container;
import com.rnf.gr2.Gr2ElementParser;
import com.rnf.gr2.Gr2Node;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/** Dev tool: parses a .gr2 file and prints its full node tree, for exploring the format. */
public final class Gr2Dump {
    public static void main(String[] args) throws IOException {
        if (args.length < 1) {
            System.err.println("usage: <path-to.gr2> [maxDepth]");
            System.exit(1);
        }
        byte[] bytes = Files.readAllBytes(Path.of(args[0]));
        Gr2Container container = Gr2Container.parse(bytes);
        System.out.println("Parsed OK: " + bytes.length + " bytes -> " + container.data.length + " decompressed bytes");
        Gr2Node root = new Gr2ElementParser(container).parseRoot();
        StringBuilder sb = new StringBuilder();
        root.dump(sb, 0);
        System.out.println(sb);
    }
}
