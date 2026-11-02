package org.teavm.classlib.java.time;

import org.teavm.classlib.java.time.format.TDateTimeFormatter;
import org.teavm.classlib.java.time.temporal.TTemporalAccessor;

public final class TLocalDate implements Comparable<TLocalDate>, TTemporalAccessor {
    private final int year;
    private final int month;
    private final int day;

    private TLocalDate(final int year, final int month, final int day) {
        this.year = year;
        this.month = month;
        this.day = day;
    }

    public static TLocalDate of(final int year, final int month, final int day) {
        if (month < 1 || month > 12 || day < 1 || day > lengthOfMonth(year, month)) {
            throw new TDateTimeException("Invalid date " + year + "-" + month + "-" + day);
        }
        return new TLocalDate(year, month, day);
    }

    public static TLocalDate parse(final CharSequence text, final TDateTimeFormatter formatter) {
        return formatter.parseFields(text).toLocalDate();
    }

    public static TLocalDate parse(final CharSequence text) {
        return parse(text, TDateTimeFormatter.ISO_LOCAL_DATE);
    }

    static int lengthOfMonth(final int year, final int month) {
        switch (month) {
            case 2:
                return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28;
            case 4: case 6: case 9: case 11:
                return 30;
            default:
                return 31;
        }
    }

    /** Days since 1970-01-01 (Hinnant's civil-date algorithm). */
    public long toEpochDay() {
        final long y = month <= 2 ? year - 1L : year;
        final long era = Math.floorDiv(y, 400L);
        final long yoe = y - era * 400;
        final long doy = (153L * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
        final long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146097 + doe - 719468;
    }

    public static TLocalDate ofEpochDay(final long epochDay) {
        final long z = epochDay + 719468;
        final long era = Math.floorDiv(z, 146097L);
        final long doe = z - era * 146097;
        final long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        final long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        final long mp = (5 * doy + 2) / 153;
        final int d = (int) (doy - (153 * mp + 2) / 5 + 1);
        final int m = (int) (mp < 10 ? mp + 3 : mp - 9);
        final long y = yoe + era * 400 + (m <= 2 ? 1 : 0);
        return new TLocalDate((int) y, m, d);
    }

    public int getYear() {
        return year;
    }

    public int getMonthValue() {
        return month;
    }

    public int getDayOfMonth() {
        return day;
    }

    public TLocalDateTime atStartOfDay() {
        return TLocalDateTime.of(this, 0, 0, 0, 0);
    }

    public TZonedDateTime atStartOfDay(final TZoneId zone) {
        return atStartOfDay().atZone(zone);
    }

    public TLocalDate plusMonths(final long months) {
        final long total = year * 12L + (month - 1) + months;
        final int y = (int) Math.floorDiv(total, 12L);
        final int m = (int) Math.floorMod(total, 12L) + 1;
        return new TLocalDate(y, m, Math.min(day, lengthOfMonth(y, m)));
    }

    public TLocalDate plusDays(final long days) {
        return ofEpochDay(toEpochDay() + days);
    }

    @Override
    public long shimLocalEpochSecond() {
        return toEpochDay() * 86400;
    }

    @Override
    public int shimNano() {
        return 0;
    }

    @Override
    public int compareTo(final TLocalDate o) {
        return Long.compare(toEpochDay(), o.toEpochDay());
    }

    @Override
    public boolean equals(final Object o) {
        return o instanceof TLocalDate && compareTo((TLocalDate) o) == 0;
    }

    @Override
    public int hashCode() {
        return year * 512 + month * 32 + day;
    }

    @Override
    public String toString() {
        return TDateTimeFormatter.ISO_LOCAL_DATE.format(this);
    }
}
