package org.teavm.classlib.java.time.format;

import org.teavm.classlib.java.time.TDateTimeException;
import org.teavm.classlib.java.time.TLocalDate;
import org.teavm.classlib.java.time.TLocalDateTime;
import org.teavm.classlib.java.time.TOffsetDateTime;
import org.teavm.classlib.java.time.TZoneOffset;
import org.teavm.classlib.java.time.temporal.TTemporalAccessor;

import java.util.Locale;

/** Small subset of DateTimeFormatter: numeric fields, English month names, offsets. */
public final class TDateTimeFormatter {
    private static final String[] MONTHS = {"January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"};

    public static final TDateTimeFormatter ISO_LOCAL_DATE = new TDateTimeFormatter("yyyy-MM-dd");
    public static final TDateTimeFormatter ISO_LOCAL_DATE_TIME =
            new TDateTimeFormatter("yyyy-MM-dd'T'HH:mm[:ss[.n]]");
    public static final TDateTimeFormatter ISO_OFFSET_DATE_TIME =
            new TDateTimeFormatter("yyyy-MM-dd'T'HH:mm[:ss[.n]]X");
    public static final TDateTimeFormatter ISO_INSTANT =
            new TDateTimeFormatter("yyyy-MM-dd'T'HH:mm:ss[.n]X");

    private final String pattern;

    private TDateTimeFormatter(final String pattern) {
        this.pattern = pattern;
    }

    public static TDateTimeFormatter ofPattern(final String pattern) {
        return new TDateTimeFormatter(pattern);
    }

    public static TDateTimeFormatter ofPattern(final String pattern, final Locale locale) {
        return new TDateTimeFormatter(pattern);
    }

    public String format(final TTemporalAccessor value) {
        final long second = value.shimLocalEpochSecond();
        final TLocalDate date = TLocalDate.ofEpochDay(Math.floorDiv(second, 86400L));
        final int secondOfDay = (int) Math.floorMod(second, 86400L);
        final StringBuilder out = new StringBuilder();
        int i = 0;
        while (i < pattern.length()) {
            final char c = pattern.charAt(i);
            if (c == '\'') {
                final int end = pattern.indexOf('\'', i + 1);
                out.append(pattern, i + 1, end);
                i = end + 1;
                continue;
            }
            if (c == '[' || c == ']') {
                i++;
                continue;
            }
            int count = 1;
            while (i + count < pattern.length() && pattern.charAt(i + count) == c) {
                count++;
            }
            i += count;
            switch (c) {
                case 'y': case 'u':
                    pad(out, date.getYear(), count);
                    break;
                case 'M':
                    if (count >= 3) {
                        final String name = MONTHS[date.getMonthValue() - 1];
                        out.append(count == 3 ? name.substring(0, 3) : name);
                    } else {
                        pad(out, date.getMonthValue(), count);
                    }
                    break;
                case 'd':
                    pad(out, date.getDayOfMonth(), count);
                    break;
                case 'H':
                    pad(out, secondOfDay / 3600, count);
                    break;
                case 'm':
                    pad(out, secondOfDay / 60 % 60, count);
                    break;
                case 's':
                    pad(out, secondOfDay % 60, count);
                    break;
                case 'S': case 'n':
                    final String nanos = String.valueOf(1_000_000_000L + value.shimNano())
                            .substring(1);
                    out.append(nanos, 0, c == 'n' ? 9 : Math.min(count, 9));
                    break;
                case 'X': case 'x': case 'z': case 'Z':
                    out.append(value instanceof TOffsetDateTime
                            ? ((TOffsetDateTime) value).getOffset().toString() : "Z");
                    break;
                default:
                    for (int k = 0; k < count; k++) {
                        out.append(c);
                    }
                    break;
            }
        }
        return out.toString();
    }

    private static void pad(final StringBuilder out, final int value, final int width) {
        final String s = String.valueOf(value);
        for (int k = s.length(); k < width; k++) {
            out.append('0');
        }
        out.append(s);
    }

    public Fields parseFields(final CharSequence text) {
        final String s = text.toString();
        final Fields fields = new Fields(s);
        final int end = parse(pattern, 0, pattern.length(), s, 0, fields);
        if (end != s.length()) {
            throw new TDateTimeParseException("Text '" + s + "' has trailing data", s, end);
        }
        return fields;
    }

    /** Returns the text position after the sub-pattern; fails with an exception. */
    private static int parse(final String pat, final int start, final int stop, final String s,
                             final int position, final Fields f) {
        int pos = position;
        int i = start;
        while (i < stop) {
            final char c = pat.charAt(i);
            if (c == '[') {
                final int close = matchingBracket(pat, i);
                final Fields trial = f.copy();
                try {
                    pos = parse(pat, i + 1, close, s, pos, trial);
                    f.assign(trial);
                } catch (final TDateTimeParseException ignored) {
                    // optional section did not match
                }
                i = close + 1;
                continue;
            }
            if (c == '\'') {
                final int end = pat.indexOf('\'', i + 1);
                final String literal = pat.substring(i + 1, end);
                if (!s.startsWith(literal, pos)) {
                    throw fail(s, pos);
                }
                pos += literal.length();
                i = end + 1;
                continue;
            }
            int count = 1;
            while (i + count < stop && pat.charAt(i + count) == c) {
                count++;
            }
            i += count;
            if (!Character.isLetter(c)) {
                for (int k = 0; k < count; k++) {
                    if (pos >= s.length() || s.charAt(pos) != c) {
                        throw fail(s, pos);
                    }
                    pos++;
                }
                continue;
            }
            switch (c) {
                case 'y': case 'u':
                    pos = number(s, pos, count == 2 ? 2 : 1, count == 2 ? 2 : 9, f, 'y');
                    if (count == 2) {
                        f.year += 2000;
                    }
                    break;
                case 'M':
                    if (count >= 3) {
                        pos = monthName(s, pos, f);
                    } else {
                        pos = number(s, pos, count, 2, f, 'M');
                    }
                    break;
                case 'd':
                    pos = number(s, pos, count, 2, f, 'd');
                    break;
                case 'H':
                    pos = number(s, pos, count, 2, f, 'H');
                    break;
                case 'm':
                    pos = number(s, pos, count, 2, f, 'm');
                    break;
                case 's':
                    pos = number(s, pos, count, 2, f, 's');
                    break;
                case 'S': case 'n':
                    final int from = pos;
                    while (pos < s.length() && Character.isDigit(s.charAt(pos))) {
                        pos++;
                    }
                    if (pos == from) {
                        throw fail(s, pos);
                    }
                    f.nano = Integer.parseInt((s.substring(from, pos) + "000000000")
                            .substring(0, 9));
                    break;
                case 'X': case 'x': case 'z': case 'Z': case 'O': case 'V':
                    int e = pos;
                    while (e < s.length() && !Character.isWhitespace(s.charAt(e))) {
                        e++;
                    }
                    if (e == pos) {
                        throw fail(s, pos);
                    }
                    try {
                        f.offset = TZoneOffset.parseOffset(s.substring(pos, e));
                    } catch (final TDateTimeException ex) {
                        throw fail(s, pos);
                    }
                    pos = e;
                    break;
                default:
                    throw new IllegalArgumentException("Unsupported pattern letter: " + c);
            }
        }
        return pos;
    }

    private static int matchingBracket(final String pat, final int open) {
        int depth = 0;
        for (int i = open; i < pat.length(); i++) {
            if (pat.charAt(i) == '[') {
                depth++;
            } else if (pat.charAt(i) == ']' && --depth == 0) {
                return i;
            }
        }
        throw new IllegalArgumentException("Unbalanced pattern: " + pat);
    }

    private static int number(final String s, final int position, final int min, final int max,
                              final Fields f, final char field) {
        int pos = position;
        int value = 0;
        while (pos < s.length() && pos - position < max && Character.isDigit(s.charAt(pos))) {
            value = value * 10 + (s.charAt(pos) - '0');
            pos++;
        }
        if (pos - position < min) {
            throw fail(s, position);
        }
        switch (field) {
            case 'y': f.year = value; break;
            case 'M': f.month = value; break;
            case 'd': f.day = value; break;
            case 'H': f.hour = value; break;
            case 'm': f.minute = value; break;
            default: f.second = value; break;
        }
        return pos;
    }

    private static int monthName(final String s, final int pos, final Fields f) {
        for (int m = 0; m < 12; m++) {
            final String name = MONTHS[m];
            if (s.regionMatches(true, pos, name, 0, name.length())) {
                f.month = m + 1;
                return pos + name.length();
            }
        }
        for (int m = 0; m < 12; m++) {
            if (s.regionMatches(true, pos, MONTHS[m], 0, 3)) {
                f.month = m + 1;
                return pos + 3;
            }
        }
        throw fail(s, pos);
    }

    private static TDateTimeParseException fail(final String s, final int pos) {
        return new TDateTimeParseException("Text '" + s + "' could not be parsed at index " + pos,
                s, pos);
    }

    /** Result of parsing; converts to the requested type or fails like the JDK would. */
    public static final class Fields {
        private final String text;
        int year = Integer.MIN_VALUE;
        int month = 1;
        int day = 1;
        int hour;
        int minute;
        int second;
        int nano;
        TZoneOffset offset;

        Fields(final String text) {
            this.text = text;
        }

        Fields copy() {
            final Fields c = new Fields(text);
            c.assign(this);
            return c;
        }

        void assign(final Fields o) {
            year = o.year;
            month = o.month;
            day = o.day;
            hour = o.hour;
            minute = o.minute;
            second = o.second;
            nano = o.nano;
            offset = o.offset;
        }

        public TLocalDate toLocalDate() {
            if (year == Integer.MIN_VALUE) {
                throw new TDateTimeParseException("No date in '" + text + "'", text, 0);
            }
            try {
                return TLocalDate.of(year, month, day);
            } catch (final TDateTimeParseException e) {
                throw e;
            } catch (final TDateTimeException e) {
                throw new TDateTimeParseException(e.getMessage(), text, 0);
            }
        }

        public TLocalDateTime toLocalDateTime() {
            return toLocalDate().atStartOfDay().plus(hour * 3600L + minute * 60L + second,
                    org.teavm.classlib.java.time.temporal.TChronoUnit.SECONDS)
                    .plus(nano, org.teavm.classlib.java.time.temporal.TChronoUnit.NANOS);
        }

        public TOffsetDateTime toOffsetDateTime() {
            if (offset == null) {
                throw new TDateTimeParseException("No offset in '" + text + "'", text, 0);
            }
            return TOffsetDateTime.of(toLocalDateTime(), offset);
        }
    }
}
