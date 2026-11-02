package com.google.protobuf;

import java.io.IOException;

/** Stand-in: protobuf-javalite relies on reflection and Unsafe, which TeaVM cannot compile. */
public class InvalidProtocolBufferException extends IOException {
    public InvalidProtocolBufferException(final String message) {
        super(message);
    }
}
