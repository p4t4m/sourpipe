package com.google.re2j;

/** jsoup optionally references RE2/J; route it to java.util.regex to keep the bundle small. */
public final class Pattern {
    private final java.util.regex.Pattern delegate;

    private Pattern(final java.util.regex.Pattern delegate) {
        this.delegate = delegate;
    }

    public static Pattern compile(final String regex) {
        return new Pattern(java.util.regex.Pattern.compile(regex));
    }

    public Matcher matcher(final CharSequence input) {
        return new Matcher(delegate.matcher(input));
    }

    @Override
    public String toString() {
        return delegate.toString();
    }
}
