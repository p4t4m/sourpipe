package org.schabi.newpipe.extractor.services.youtube.protos.playlist;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Hand-written encoder replacing the code protoc generates from
 * youtube/playlist/playlist_continuation_schema.proto.
 */
public final class PlaylistProtobufContinuation {
    private PlaylistProtobufContinuation() {
    }

    private static void writeVarint(final ByteArrayOutputStream out, final int value) {
        int v = value;
        while ((v & ~0x7f) != 0) {
            out.write(v & 0x7f | 0x80);
            v >>>= 7;
        }
        out.write(v);
    }

    private static void writeBytes(final ByteArrayOutputStream out, final int field,
                                   final byte[] bytes) {
        writeVarint(out, field << 3 | 2);
        writeVarint(out, bytes.length);
        out.write(bytes, 0, bytes.length);
    }

    private static void writeString(final ByteArrayOutputStream out, final int field,
                                    final String value) {
        // proto3 omits empty strings
        if (!value.isEmpty()) {
            writeBytes(out, field, value.getBytes(StandardCharsets.UTF_8));
        }
    }

    public static final class ContinuationParams {
        private final byte[] encoded;

        private ContinuationParams(final byte[] encoded) {
            this.encoded = encoded;
        }

        public static Builder newBuilder() {
            return new Builder();
        }

        public static final class Builder {
            private String browseId = "";
            private String continuationProperties = "";
            private String playlistId = "";

            public Builder setBrowseId(final String value) {
                browseId = value;
                return this;
            }

            public Builder setContinuationProperties(final String value) {
                continuationProperties = value;
                return this;
            }

            public Builder setPlaylistId(final String value) {
                playlistId = value;
                return this;
            }

            public ContinuationParams build() {
                final ByteArrayOutputStream out = new ByteArrayOutputStream();
                writeString(out, 2, browseId);
                writeString(out, 3, continuationProperties);
                writeString(out, 35, playlistId);
                return new ContinuationParams(out.toByteArray());
            }
        }
    }

    public static final class PlaylistContinuation {
        private final byte[] encoded;

        private PlaylistContinuation(final byte[] encoded) {
            this.encoded = encoded;
        }

        public byte[] toByteArray() {
            return encoded;
        }

        public static Builder newBuilder() {
            return new Builder();
        }

        public static final class Builder {
            private ContinuationParams parameters;

            public Builder setParameters(final ContinuationParams value) {
                parameters = value;
                return this;
            }

            public PlaylistContinuation build() {
                final ByteArrayOutputStream out = new ByteArrayOutputStream();
                if (parameters != null) {
                    writeBytes(out, 80226972, parameters.encoded);
                }
                return new PlaylistContinuation(out.toByteArray());
            }
        }
    }
}
