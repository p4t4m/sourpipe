package org.teavm.classlib.java.time;

import org.teavm.classlib.java.time.format.TDateTimeFormatter;
import org.teavm.classlib.java.time.temporal.TTemporalAccessor;

public final class TZonedDateTime implements TTemporalAccessor {
    private final TLocalDateTime local;
    private final TZoneId zone;

    private TZonedDateTime(final TLocalDateTime local, final TZoneId zone) {
        this.local = local;
        this.zone = zone;
    }

    public static TZonedDateTime of(final TLocalDateTime local, final TZoneId zone) {
        return new TZonedDateTime(local, zone);
    }

    public static TZonedDateTime ofInstant(final TInstant instant, final TZoneId zone) {
        return new TZonedDateTime(TLocalDateTime.ofInstant(instant, zone), zone);
    }

    public static TZonedDateTime parse(final CharSequence text,
                                       final TDateTimeFormatter formatter) {
        final TOffsetDateTime parsed = formatter.parseFields(text).toOffsetDateTime();
        return new TZonedDateTime(parsed.toLocalDateTime(), parsed.getOffset());
    }

    public TInstant toInstant() {
        return TInstant.ofEpochSecond(local.shimLocalEpochSecond() - zone.shimOffsetSeconds(),
                local.shimNano());
    }

    public TOffsetDateTime toOffsetDateTime() {
        return TOffsetDateTime.of(local, TZoneOffset.ofTotalSeconds(zone.shimOffsetSeconds()));
    }

    public TLocalDateTime toLocalDateTime() {
        return local;
    }

    @Override
    public long shimLocalEpochSecond() {
        return local.shimLocalEpochSecond();
    }

    @Override
    public int shimNano() {
        return local.shimNano();
    }
}
