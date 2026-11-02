package org.schabi.newpipe.extractor.utils.jsextractor;

/** Stand-in for org.mozilla.javascript.ScriptRuntime; avoids pulling in the Rhino runtime. */
final class ScriptRuntime {
    private ScriptRuntime() {
    }

    static boolean isJSLineTerminator(final int c) {
        return c == '\n' || c == '\r' || c == 0x2028 || c == 0x2029;
    }
}
