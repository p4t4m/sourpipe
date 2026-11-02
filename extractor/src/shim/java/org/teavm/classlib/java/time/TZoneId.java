package org.teavm.classlib.java.time;

import org.teavm.jso.JSBody;

/** Only fixed offsets exist in this shim; the system zone is the host's current UTC offset. */
public abstract class TZoneId {
    public static TZoneId systemDefault() {
        return TZoneOffset.ofTotalSeconds(-hostOffsetMinutes() * 60);
    }

    public static TZoneId of(final String id) {
        return TZoneOffset.parseOffset(id);
    }

    public abstract int shimOffsetSeconds();

    @JSBody(script = "return new Date().getTimezoneOffset();")
    private static native int hostOffsetMinutes();
}
