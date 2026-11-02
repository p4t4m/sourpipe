package com.google.re2j;

/** See {@link Pattern}. */
public final class Matcher {
    private final java.util.regex.Matcher delegate;

    Matcher(final java.util.regex.Matcher delegate) {
        this.delegate = delegate;
    }

    public boolean find() {
        return delegate.find();
    }
}
