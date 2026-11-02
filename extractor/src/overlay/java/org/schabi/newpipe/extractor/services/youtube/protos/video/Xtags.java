package org.schabi.newpipe.extractor.services.youtube.protos.video;

import com.google.protobuf.InvalidProtocolBufferException;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Hand-written decoder replacing the code protoc generates from youtube/video/xtags.proto. */
public final class Xtags {
    private Xtags() {
    }

    public static final class KeyValuePair {
        private String key = "";
        private String value = "";

        public String getKey() {
            return key;
        }

        public String getValue() {
            return value;
        }
    }

    public static final class XTags {
        private final List<KeyValuePair> xtags = new ArrayList<>();

        public List<KeyValuePair> getXtagsList() {
            return xtags;
        }

        public static XTags parseFrom(final byte[] data) throws InvalidProtocolBufferException {
            final XTags result = new XTags();
            final Reader reader = new Reader(data, 0, data.length);
            while (reader.hasMore()) {
                final int tag = reader.varint();
                if (tag >>> 3 == 1 && (tag & 7) == 2) {
                    result.xtags.add(parsePair(reader.delimited()));
                } else {
                    reader.skip(tag & 7);
                }
            }
            return result;
        }

        private static KeyValuePair parsePair(final Reader reader)
                throws InvalidProtocolBufferException {
            final KeyValuePair pair = new KeyValuePair();
            while (reader.hasMore()) {
                final int tag = reader.varint();
                if (tag >>> 3 == 1 && (tag & 7) == 2) {
                    pair.key = reader.string();
                } else if (tag >>> 3 == 2 && (tag & 7) == 2) {
                    pair.value = reader.string();
                } else {
                    reader.skip(tag & 7);
                }
            }
            return pair;
        }
    }

    private static final class Reader {
        private final byte[] data;
        private int pos;
        private final int end;

        Reader(final byte[] data, final int pos, final int end) {
            this.data = data;
            this.pos = pos;
            this.end = end;
        }

        boolean hasMore() {
            return pos < end;
        }

        int varint() throws InvalidProtocolBufferException {
            int result = 0;
            for (int shift = 0; shift < 64; shift += 7) {
                if (pos >= end) {
                    throw new InvalidProtocolBufferException("Truncated varint");
                }
                final byte b = data[pos++];
                if (shift < 32) {
                    result |= (b & 0x7f) << shift;
                }
                if (b >= 0) {
                    return result;
                }
            }
            throw new InvalidProtocolBufferException("Malformed varint");
        }

        Reader delimited() throws InvalidProtocolBufferException {
            final int length = varint();
            if (length < 0 || length > end - pos) {
                throw new InvalidProtocolBufferException("Truncated field");
            }
            final Reader inner = new Reader(data, pos, pos + length);
            pos += length;
            return inner;
        }

        String string() throws InvalidProtocolBufferException {
            final Reader inner = delimited();
            return new String(data, inner.pos, inner.end - inner.pos, StandardCharsets.UTF_8);
        }

        void skip(final int wireType) throws InvalidProtocolBufferException {
            final int size;
            switch (wireType) {
                case 0:
                    varint();
                    return;
                case 1:
                    size = 8;
                    break;
                case 2:
                    delimited();
                    return;
                case 5:
                    size = 4;
                    break;
                default:
                    throw new InvalidProtocolBufferException("Bad wire type " + wireType);
            }
            if (size > end - pos) {
                throw new InvalidProtocolBufferException("Truncated field");
            }
            pos += size;
        }
    }
}
