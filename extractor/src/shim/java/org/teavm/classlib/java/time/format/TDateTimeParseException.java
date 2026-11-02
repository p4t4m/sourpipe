package org.teavm.classlib.java.time.format;

import org.teavm.classlib.java.time.TDateTimeException;

public class TDateTimeParseException extends TDateTimeException {
    private final String parsed;
    private final int errorIndex;

    public TDateTimeParseException(final String message, final CharSequence parsed,
                                   final int errorIndex) {
        super(message);
        this.parsed = parsed.toString();
        this.errorIndex = errorIndex;
    }

    public String getParsedString() {
        return parsed;
    }

    public int getErrorIndex() {
        return errorIndex;
    }
}
