package org.teavm.classlib.java.time;

public final class TZoneOffset extends TZoneId {
    public static final TZoneOffset UTC = new TZoneOffset(0);

    private final int seconds;

    private TZoneOffset(final int seconds) {
        this.seconds = seconds;
    }

    public static TZoneOffset ofTotalSeconds(final int seconds) {
        return seconds == 0 ? UTC : new TZoneOffset(seconds);
    }

    public static TZoneOffset parseOffset(final String id) {
        final String s = id.trim();
        switch (s.toUpperCase()) {
            case "Z": case "UTC": case "GMT": case "UT":
                return UTC;
            case "EST": return ofTotalSeconds(-5 * 3600);
            case "EDT": return ofTotalSeconds(-4 * 3600);
            case "CST": return ofTotalSeconds(-6 * 3600);
            case "CDT": return ofTotalSeconds(-5 * 3600);
            case "MST": return ofTotalSeconds(-7 * 3600);
            case "MDT": return ofTotalSeconds(-6 * 3600);
            case "PST": return ofTotalSeconds(-8 * 3600);
            case "PDT": return ofTotalSeconds(-7 * 3600);
            case "CET": return ofTotalSeconds(3600);
            case "CEST": return ofTotalSeconds(7200);
            default: break;
        }
        String body = s;
        if (body.startsWith("UTC") || body.startsWith("GMT")) {
            body = body.substring(3);
        }
        if (body.length() < 2 || body.charAt(0) != '+' && body.charAt(0) != '-') {
            throw new TDateTimeException("Unknown zone: " + id);
        }
        final int sign = body.charAt(0) == '-' ? -1 : 1;
        final String digits = body.substring(1).replace(":", "");
        try {
            final int hours = Integer.parseInt(digits.substring(0, Math.min(2, digits.length())));
            final int minutes = digits.length() >= 4 ? Integer.parseInt(digits.substring(2, 4)) : 0;
            return ofTotalSeconds(sign * (hours * 3600 + minutes * 60));
        } catch (final NumberFormatException e) {
            throw new TDateTimeException("Unknown zone: " + id);
        }
    }

    @Override
    public int shimOffsetSeconds() {
        return seconds;
    }

    @Override
    public boolean equals(final Object o) {
        return o instanceof TZoneOffset && ((TZoneOffset) o).seconds == seconds;
    }

    @Override
    public int hashCode() {
        return seconds;
    }

    @Override
    public String toString() {
        if (seconds == 0) {
            return "Z";
        }
        final int abs = Math.abs(seconds);
        final int h = abs / 3600;
        final int m = abs / 60 % 60;
        return (seconds < 0 ? "-" : "+") + (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }
}
