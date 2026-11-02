package org.schabi.newpipe.extractor.utils.jsextractor;

/** Stand-in for the two org.mozilla.javascript.Kit helpers the tokenizer uses. */
final class Kit {
    private Kit() {
    }

    static int xDigitToInt(final int c, final int accumulator) {
        final int digit;
        if (c >= '0' && c <= '9') {
            digit = c - '0';
        } else if (c >= 'a' && c <= 'f') {
            digit = c - 'a' + 10;
        } else if (c >= 'A' && c <= 'F') {
            digit = c - 'A' + 10;
        } else {
            return -1;
        }
        return accumulator << 4 | digit;
    }

    static RuntimeException codeBug() {
        throw new IllegalStateException("Tokenizer bug");
    }
}
