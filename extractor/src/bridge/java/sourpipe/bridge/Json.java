package sourpipe.bridge;

import com.grack.nanojson.JsonArray;
import com.grack.nanojson.JsonObject;

import org.schabi.newpipe.extractor.Image;
import org.schabi.newpipe.extractor.InfoItem;
import org.schabi.newpipe.extractor.Page;
import org.schabi.newpipe.extractor.channel.ChannelInfoItem;
import org.schabi.newpipe.extractor.comments.CommentsInfoItem;
import org.schabi.newpipe.extractor.localization.DateWrapper;
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem;
import org.schabi.newpipe.extractor.stream.AudioStream;
import org.schabi.newpipe.extractor.stream.Description;
import org.schabi.newpipe.extractor.stream.Stream;
import org.schabi.newpipe.extractor.stream.StreamInfoItem;
import org.schabi.newpipe.extractor.stream.SubtitlesStream;
import org.schabi.newpipe.extractor.stream.VideoStream;
import org.schabi.newpipe.extractor.MediaFormat;
import org.schabi.newpipe.extractor.services.youtube.ItagItem;

import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Converts extractor objects to the JSON shapes decoded by the Swift Models. */
final class Json {
    private Json() {
    }

    static JsonArray images(final List<Image> images) {
        final JsonArray out = new JsonArray();
        if (images != null) {
            for (final Image image : images) {
                final JsonObject o = new JsonObject();
                o.put("url", image.getUrl());
                o.put("width", image.getWidth());
                o.put("height", image.getHeight());
                out.add(o);
            }
        }
        return out;
    }

    static Object date(final DateWrapper date) {
        return date == null ? null : (Object) date.getInstant().toEpochMilli();
    }

    static String description(final Description description) {
        return description == null ? null : description.content();
    }

    static String descriptionType(final Description description) {
        if (description == null) {
            return "plain";
        }
        return description.type().name().toLowerCase();
    }

    static JsonObject page(final Page page) {
        if (!Page.isValid(page)) {
            return null;
        }
        final JsonObject o = new JsonObject();
        o.put("url", page.getUrl());
        o.put("id", page.getId());
        if (page.getIds() != null) {
            o.put("ids", new JsonArray(page.getIds()));
        }
        if (page.getCookies() != null) {
            final JsonObject cookies = new JsonObject();
            cookies.putAll(page.getCookies());
            o.put("cookies", cookies);
        }
        if (page.getBody() != null) {
            o.put("body", Base64.getEncoder().encodeToString(page.getBody()));
        }
        return o;
    }

    static Page parsePage(final JsonObject o) {
        if (o == null) {
            return null;
        }
        List<String> ids = null;
        if (o.has("ids")) {
            ids = new ArrayList<>();
            for (final Object id : o.getArray("ids")) {
                ids.add(String.valueOf(id));
            }
        }
        Map<String, String> cookies = null;
        if (o.has("cookies")) {
            cookies = new HashMap<>();
            final JsonObject source = o.getObject("cookies");
            for (final String key : source.keySet()) {
                cookies.put(key, source.getString(key));
            }
        }
        final String body = o.getString("body");
        return new Page(o.getString("url"), o.getString("id"), ids, cookies,
                body == null ? null : Base64.getDecoder().decode(body));
    }

    static JsonArray items(final List<? extends InfoItem> items) {
        final JsonArray out = new JsonArray();
        if (items != null) {
            for (final InfoItem item : items) {
                out.add(item(item));
            }
        }
        return out;
    }

    static JsonObject item(final InfoItem item) {
        final JsonObject o = new JsonObject();
        o.put("type", item.getInfoType().name().toLowerCase());
        o.put("serviceId", item.getServiceId());
        o.put("url", item.getUrl());
        o.put("name", item.getName());
        o.put("thumbnails", images(item.getThumbnails()));
        if (item instanceof StreamInfoItem) {
            final StreamInfoItem s = (StreamInfoItem) item;
            o.put("streamType", s.getStreamType().name());
            o.put("uploaderName", s.getUploaderName());
            o.put("uploaderUrl", s.getUploaderUrl());
            o.put("uploaderAvatars", images(s.getUploaderAvatars()));
            o.put("uploaderVerified", s.isUploaderVerified());
            o.put("viewCount", s.getViewCount());
            o.put("duration", s.getDuration());
            o.put("textualUploadDate", s.getTextualUploadDate());
            o.put("uploadDate", date(s.getUploadDate()));
            o.put("shortDescription", s.getShortDescription());
            o.put("isShort", s.isShortFormContent());
        } else if (item instanceof ChannelInfoItem) {
            final ChannelInfoItem c = (ChannelInfoItem) item;
            o.put("description", c.getDescription());
            o.put("subscriberCount", c.getSubscriberCount());
            o.put("streamCount", c.getStreamCount());
            o.put("verified", c.isVerified());
        } else if (item instanceof PlaylistInfoItem) {
            final PlaylistInfoItem p = (PlaylistInfoItem) item;
            o.put("uploaderName", p.getUploaderName());
            o.put("uploaderUrl", p.getUploaderUrl());
            o.put("uploaderVerified", p.isUploaderVerified());
            o.put("streamCount", p.getStreamCount());
        } else if (item instanceof CommentsInfoItem) {
            final CommentsInfoItem c = (CommentsInfoItem) item;
            o.put("commentId", c.getCommentId());
            o.put("text", description(c.getCommentText()));
            o.put("textType", descriptionType(c.getCommentText()));
            o.put("uploaderName", c.getUploaderName());
            o.put("uploaderUrl", c.getUploaderUrl());
            o.put("uploaderAvatars", images(c.getUploaderAvatars()));
            o.put("uploaderVerified", c.isUploaderVerified());
            o.put("textualUploadDate", c.getTextualUploadDate());
            o.put("uploadDate", date(c.getUploadDate()));
            o.put("likeCount", c.getLikeCount());
            o.put("textualLikeCount", c.getTextualLikeCount());
            o.put("hearted", c.isHeartedByUploader());
            o.put("pinned", c.isPinned());
            o.put("replyCount", c.getReplyCount());
            o.put("replies", page(c.getReplies()));
        }
        return o;
    }

    private static void baseStream(final JsonObject o, final Stream s) {
        final boolean direct = s.isUrl();
        o.put("id", s.getId());
        o.put("url", direct ? s.getContent() : null);
        o.put("delivery", s.getDeliveryMethod().name());
        o.put("manifestUrl", s.getManifestUrl());
        final MediaFormat format = s.getFormat();
        if (format != null) {
            o.put("format", format.getName());
            o.put("mime", format.getMimeType());
            o.put("suffix", format.getSuffix());
        }
    }

    private static void itag(final JsonObject o, final ItagItem itag) {
        if (itag != null) {
            o.put("contentLength", itag.getContentLength());
            o.put("approxDurationMs", itag.getApproxDurationMs());
        }
    }

    static JsonArray videoStreams(final List<VideoStream> streams) {
        final JsonArray out = new JsonArray();
        if (streams != null) {
            for (final VideoStream s : streams) {
                final JsonObject o = new JsonObject();
                baseStream(o, s);
                o.put("resolution", s.getResolution());
                o.put("videoOnly", s.isVideoOnly());
                o.put("itag", s.getItag());
                o.put("bitrate", s.getBitrate());
                o.put("width", s.getWidth());
                o.put("height", s.getHeight());
                o.put("fps", s.getFps());
                o.put("codec", s.getCodec());
                o.put("initStart", s.getInitStart());
                o.put("initEnd", s.getInitEnd());
                o.put("indexStart", s.getIndexStart());
                o.put("indexEnd", s.getIndexEnd());
                itag(o, s.getItagItem());
                out.add(o);
            }
        }
        return out;
    }

    static JsonArray audioStreams(final List<AudioStream> streams) {
        final JsonArray out = new JsonArray();
        if (streams != null) {
            for (final AudioStream s : streams) {
                final JsonObject o = new JsonObject();
                baseStream(o, s);
                o.put("averageBitrate", s.getAverageBitrate());
                o.put("itag", s.getItag());
                o.put("bitrate", s.getBitrate());
                o.put("codec", s.getCodec());
                o.put("initStart", s.getInitStart());
                o.put("initEnd", s.getInitEnd());
                o.put("indexStart", s.getIndexStart());
                o.put("indexEnd", s.getIndexEnd());
                o.put("trackId", s.getAudioTrackId());
                o.put("trackName", s.getAudioTrackName());
                o.put("trackType", s.getAudioTrackType() == null ? null
                        : s.getAudioTrackType().name());
                itag(o, s.getItagItem());
                out.add(o);
            }
        }
        return out;
    }

    static JsonArray subtitles(final List<SubtitlesStream> streams) {
        final JsonArray out = new JsonArray();
        if (streams != null) {
            for (final SubtitlesStream s : streams) {
                final JsonObject o = new JsonObject();
                baseStream(o, s);
                o.put("languageTag", s.getLanguageTag());
                o.put("name", s.getDisplayLanguageName());
                o.put("autoGenerated", s.isAutoGenerated());
                out.add(o);
            }
        }
        return out;
    }
}
