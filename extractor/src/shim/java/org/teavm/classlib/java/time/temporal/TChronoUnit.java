package org.teavm.classlib.java.time.temporal;

public enum TChronoUnit implements TTemporalUnit {
    NANOS, MICROS, MILLIS, SECONDS, MINUTES, HOURS, HALF_DAYS, DAYS, WEEKS, MONTHS, YEARS,
    DECADES, CENTURIES, MILLENNIA, ERAS, FOREVER;

    @Override
    public boolean isDateBased() {
        return compareTo(DAYS) >= 0 && this != FOREVER;
    }
}
