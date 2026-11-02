package org.teavm.classlib.java.time.temporal;

/** Minimal: the shim's formatter only prints values that expose calendar fields. */
public interface TTemporalAccessor {
    /** Local epoch second of this value, as read on a wall clock. */
    long shimLocalEpochSecond();

    int shimNano();
}
