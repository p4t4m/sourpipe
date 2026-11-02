package org.teavm.classlib.java.time;

import org.teavm.classlib.java.time.format.TDateTimeFormatter;
import org.teavm.classlib.java.time.temporal.TTemporalAccessor;

public final class TInstant implements Comparable<TInstant>, TTemporalAccessor {
    public static final TInstant EPOCH = new TInstant(0, 0);

    private final long seconds;
    private final int nanos;

    private TInstant(final long seconds, final int nanos) {
        this.seconds = seconds;
        this.nanos = nanos;
    }

    public static TInstant now() {
        return ofEpochMilli(System.currentTimeMillis());
    }

    public static TInstant ofEpochSecond(final long seconds) {
        return new TInstant(seconds, 0);
    }

    public static TInstant ofEpochSecond(final long seconds, final long nanoAdjustment) {
        return new TInstant(seconds + Math.floorDiv(nanoAdjustment, 1_000_000_000L),
                (int) Math.floorMod(nanoAdjustment, 1_000_000_000L));
    }

    public static TInstant ofEpochMilli(final long millis) {
        return new TInstant(Math.floorDiv(millis, 1000L),
                (int) Math.floorMod(millis, 1000L) * 1_000_000);
    }

    public static TInstant parse(final CharSequence text) {
        return TOffsetDateTime.parse(text).toInstant();
    }

    public long getEpochSecond() {
        return seconds;
    }

    public int getNano() {
        return nanos;
    }

    public long toEpochMilli() {
        return seconds * 1000 + nanos / 1_000_000;
    }

    public TOffsetDateTime atOffset(final TZoneOffset offset) {
        return TOffsetDateTime.ofInstant(this, offset);
    }

    public TZonedDateTime atZone(final TZoneId zone) {
        return TZonedDateTime.ofInstant(this, zone);
    }

    @Override
    public long shimLocalEpochSecond() {
        return seconds;
    }

    @Override
    public int shimNano() {
        return nanos;
    }

    @Override
    public int compareTo(final TInstant o) {
        final int c = Long.compare(seconds, o.seconds);
        return c != 0 ? c : Integer.compare(nanos, o.nanos);
    }

    @Override
    public boolean equals(final Object o) {
        return o instanceof TInstant && compareTo((TInstant) o) == 0;
    }

    @Override
    public int hashCode() {
        return Long.hashCode(seconds) * 31 + nanos;
    }

    @Override
    public String toString() {
        return TDateTimeFormatter.ISO_INSTANT.format(this);
    }
}
