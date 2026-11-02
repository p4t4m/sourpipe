package org.teavm.classlib.java.time;

import org.teavm.classlib.java.time.format.TDateTimeFormatter;
import org.teavm.classlib.java.time.temporal.TChronoUnit;
import org.teavm.classlib.java.time.temporal.TTemporalAccessor;
import org.teavm.classlib.java.time.temporal.TTemporalUnit;

public final class TLocalDateTime implements Comparable<TLocalDateTime>, TTemporalAccessor {
    private final long epochSecond;
    private final int nanos;

    private TLocalDateTime(final long epochSecond, final int nanos) {
        this.epochSecond = epochSecond;
        this.nanos = nanos;
    }

    static TLocalDateTime of(final TLocalDate date, final int hour, final int minute,
                             final int second, final int nano) {
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
            throw new TDateTimeException("Invalid time " + hour + ":" + minute + ":" + second);
        }
        return new TLocalDateTime(date.toEpochDay() * 86400 + hour * 3600 + minute * 60 + second,
                nano);
    }

    static TLocalDateTime ofLocalEpochSecond(final long epochSecond, final int nano) {
        return new TLocalDateTime(epochSecond, nano);
    }

    public static TLocalDateTime now() {
        return ofInstant(TInstant.now(), TZoneId.systemDefault());
    }

    public static TLocalDateTime ofInstant(final TInstant instant, final TZoneId zone) {
        return new TLocalDateTime(instant.getEpochSecond() + zone.shimOffsetSeconds(),
                instant.getNano());
    }

    public static TLocalDateTime parse(final CharSequence text,
                                       final TDateTimeFormatter formatter) {
        return formatter.parseFields(text).toLocalDateTime();
    }

    public static TLocalDateTime parse(final CharSequence text) {
        return parse(text, TDateTimeFormatter.ISO_LOCAL_DATE_TIME);
    }

    public TZonedDateTime atZone(final TZoneId zone) {
        return TZonedDateTime.of(this, zone);
    }

    public TOffsetDateTime atOffset(final TZoneOffset offset) {
        return TOffsetDateTime.of(this, offset);
    }

    public TLocalDate toLocalDate() {
        return TLocalDate.ofEpochDay(Math.floorDiv(epochSecond, 86400L));
    }

    public TLocalDateTime minus(final long amount, final TTemporalUnit unit) {
        return plus(-amount, unit);
    }

    public TLocalDateTime plus(final long amount, final TTemporalUnit unit) {
        switch ((TChronoUnit) unit) {
            case NANOS:
                return plusNanos(amount);
            case MICROS:
                return plusNanos(amount * 1000);
            case MILLIS:
                return plusNanos(amount * 1_000_000);
            case SECONDS:
                return plusSeconds(amount);
            case MINUTES:
                return plusSeconds(amount * 60);
            case HOURS:
                return plusSeconds(amount * 3600);
            case HALF_DAYS:
                return plusSeconds(amount * 43200);
            case DAYS:
                return plusSeconds(amount * 86400);
            case WEEKS:
                return plusSeconds(amount * 604800);
            case MONTHS:
                return plusMonths(amount);
            case YEARS:
                return plusMonths(amount * 12);
            case DECADES:
                return plusMonths(amount * 120);
            case CENTURIES:
                return plusMonths(amount * 1200);
            case MILLENNIA:
                return plusMonths(amount * 12000);
            default:
                throw new TDateTimeException("Unsupported unit: " + unit);
        }
    }

    private TLocalDateTime plusNanos(final long amount) {
        final long total = nanos + amount;
        return new TLocalDateTime(epochSecond + Math.floorDiv(total, 1_000_000_000L),
                (int) Math.floorMod(total, 1_000_000_000L));
    }

    private TLocalDateTime plusSeconds(final long amount) {
        return new TLocalDateTime(epochSecond + amount, nanos);
    }

    private TLocalDateTime plusMonths(final long months) {
        final long secondOfDay = Math.floorMod(epochSecond, 86400L);
        return new TLocalDateTime(toLocalDate().plusMonths(months).toEpochDay() * 86400
                + secondOfDay, nanos);
    }

    public TLocalDateTime minusYears(final long years) {
        return plusMonths(-years * 12);
    }

    public TLocalDateTime minusDays(final long days) {
        return plusSeconds(-days * 86400);
    }

    public TLocalDateTime truncatedTo(final TTemporalUnit unit) {
        final long size;
        switch ((TChronoUnit) unit) {
            case SECONDS:
                size = 1;
                break;
            case MINUTES:
                size = 60;
                break;
            case HOURS:
                size = 3600;
                break;
            case DAYS:
                size = 86400;
                break;
            default:
                throw new TDateTimeException("Unsupported unit: " + unit);
        }
        return new TLocalDateTime(Math.floorDiv(epochSecond, size) * size, 0);
    }

    @Override
    public long shimLocalEpochSecond() {
        return epochSecond;
    }

    @Override
    public int shimNano() {
        return nanos;
    }

    @Override
    public int compareTo(final TLocalDateTime o) {
        final int c = Long.compare(epochSecond, o.epochSecond);
        return c != 0 ? c : Integer.compare(nanos, o.nanos);
    }

    @Override
    public boolean equals(final Object o) {
        return o instanceof TLocalDateTime && compareTo((TLocalDateTime) o) == 0;
    }

    @Override
    public int hashCode() {
        return Long.hashCode(epochSecond) * 31 + nanos;
    }

    @Override
    public String toString() {
        return TDateTimeFormatter.ISO_LOCAL_DATE_TIME.format(this);
    }
}
