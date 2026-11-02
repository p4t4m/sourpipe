package org.teavm.classlib.java.time;

import org.teavm.classlib.java.time.format.TDateTimeFormatter;
import org.teavm.classlib.java.time.temporal.TTemporalAccessor;

public final class TOffsetDateTime implements Comparable<TOffsetDateTime>, TTemporalAccessor {
    private final TLocalDateTime local;
    private final TZoneOffset offset;

    private TOffsetDateTime(final TLocalDateTime local, final TZoneOffset offset) {
        this.local = local;
        this.offset = offset;
    }

    public static TOffsetDateTime of(final TLocalDateTime local, final TZoneOffset offset) {
        return new TOffsetDateTime(local, offset);
    }

    public static TOffsetDateTime ofInstant(final TInstant instant, final TZoneId zone) {
        final TZoneOffset offset = TZoneOffset.ofTotalSeconds(zone.shimOffsetSeconds());
        return new TOffsetDateTime(TLocalDateTime.ofInstant(instant, offset), offset);
    }

    public static TOffsetDateTime parse(final CharSequence text) {
        return parse(text, TDateTimeFormatter.ISO_OFFSET_DATE_TIME);
    }

    public static TOffsetDateTime parse(final CharSequence text,
                                        final TDateTimeFormatter formatter) {
        return formatter.parseFields(text).toOffsetDateTime();
    }

    public TInstant toInstant() {
        return TInstant.ofEpochSecond(local.shimLocalEpochSecond() - offset.shimOffsetSeconds(),
                local.shimNano());
    }

    public TLocalDateTime toLocalDateTime() {
        return local;
    }

    public TLocalDate toLocalDate() {
        return local.toLocalDate();
    }

    public TZoneOffset getOffset() {
        return offset;
    }

    public String format(final TDateTimeFormatter formatter) {
        return formatter.format(this);
    }

    @Override
    public long shimLocalEpochSecond() {
        return local.shimLocalEpochSecond();
    }

    @Override
    public int shimNano() {
        return local.shimNano();
    }

    @Override
    public int compareTo(final TOffsetDateTime o) {
        return toInstant().compareTo(o.toInstant());
    }

    @Override
    public String toString() {
        return local + offset.toString();
    }
}
