package sourpipe.bridge;

import com.grack.nanojson.JsonArray;
import com.grack.nanojson.JsonObject;
import com.grack.nanojson.JsonParser;
import com.grack.nanojson.JsonWriter;

import org.schabi.newpipe.extractor.InfoItem;
import org.schabi.newpipe.extractor.ListExtractor.InfoItemsPage;
import org.schabi.newpipe.extractor.NewPipe;
import org.schabi.newpipe.extractor.Page;
import org.schabi.newpipe.extractor.StreamingService;
import org.schabi.newpipe.extractor.channel.ChannelInfo;
import org.schabi.newpipe.extractor.channel.tabs.ChannelTabInfo;
import org.schabi.newpipe.extractor.comments.CommentsInfo;
import org.schabi.newpipe.extractor.exceptions.AgeRestrictedContentException;
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException;
import org.schabi.newpipe.extractor.exceptions.ContentNotSupportedException;
import org.schabi.newpipe.extractor.exceptions.GeographicRestrictionException;
import org.schabi.newpipe.extractor.exceptions.PaidContentException;
import org.schabi.newpipe.extractor.exceptions.PrivateContentException;
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException;
import org.schabi.newpipe.extractor.exceptions.SignInConfirmNotBotException;
import org.schabi.newpipe.extractor.kiosk.KioskExtractor;
import org.schabi.newpipe.extractor.kiosk.KioskInfo;
import org.schabi.newpipe.extractor.kiosk.KioskList;
import org.schabi.newpipe.extractor.linkhandler.ListLinkHandler;
import org.schabi.newpipe.extractor.linkhandler.SearchQueryHandler;
import org.schabi.newpipe.extractor.localization.ContentCountry;
import org.schabi.newpipe.extractor.localization.Localization;
import org.schabi.newpipe.extractor.playlist.PlaylistInfo;
import org.schabi.newpipe.extractor.search.SearchInfo;
import org.schabi.newpipe.extractor.stream.StreamInfo;
import org.schabi.newpipe.extractor.stream.StreamSegment;
import org.schabi.newpipe.extractor.utils.JavaScript;
import org.schabi.newpipe.extractor.utils.JavaScriptInterpreter;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The entry point of the bundle: {@code __sourpipeCall(method, argsJson, (result, error) => ...)}.
 * Each call runs on its own TeaVM green thread, so calls may overlap.
 */
public final class Main {
    /** Some tab handlers carry prefetched data, so they stay here and Swift keeps a token. */
    private static final Map<String, ListLinkHandler> TABS = new LinkedHashMap<>();
    private static int nextTab;

    private Main() {
    }

    public static void main(final String[] args) {
        JavaScript.setExternalJavaScriptInterpreter(new JavaScriptInterpreter() {
            @Override
            public void compile(final String code) {
                Host.compileJs(code);
            }

            @Override
            public String run(final String code, final String name, final String... parameters) {
                return Host.runJs(code, name, parameters);
            }
        });
        NewPipe.init(new HostDownloader());
        Host.install((method, argsJson, callback) -> new Thread(() -> {
            String result = null;
            String error = null;
            try {
                result = JsonWriter.string(dispatch(method, JsonParser.object().from(argsJson)));
            } catch (final Throwable t) {
                error = describe(t);
            }
            callback.done(result, error);
        }).start());
    }

    private static String describe(final Throwable t) {
        final JsonObject o = new JsonObject();
        final String kind;
        if (t instanceof ReCaptchaException) {
            kind = "recaptcha";
        } else if (t instanceof SignInConfirmNotBotException) {
            kind = "botCheck";
        } else if (t instanceof AgeRestrictedContentException) {
            kind = "ageRestricted";
        } else if (t instanceof GeographicRestrictionException) {
            kind = "geoRestricted";
        } else if (t instanceof PaidContentException) {
            kind = "paid";
        } else if (t instanceof PrivateContentException) {
            kind = "private";
        } else if (t instanceof ContentNotSupportedException) {
            kind = "unsupported";
        } else if (t instanceof ContentNotAvailableException) {
            kind = "unavailable";
        } else if (t instanceof java.io.IOException) {
            kind = "network";
        } else {
            kind = "extraction";
        }
        o.put("kind", kind);
        if (t instanceof ReCaptchaException && ((ReCaptchaException) t).getUrl() != null) {
            o.put("url", ((ReCaptchaException) t).getUrl());
        }
        final StringBuilder message = new StringBuilder();
        Throwable current = t;
        for (int depth = 0; current != null && depth < 5; depth++) {
            if (depth > 0) {
                message.append(" <- ");
            }
            message.append(current.getClass().getName()).append(": ")
                    .append(current.getMessage());
            current = current.getCause();
        }
        o.put("message", message.toString());
        return JsonWriter.string(o);
    }

    private static StreamingService service(final JsonObject a) throws Exception {
        return NewPipe.getService(a.getInt("serviceId"));
    }

    private static JsonObject dispatch(final String method, final JsonObject a) throws Exception {
        switch (method) {
            case "configure":
                return configure(a);
            case "services":
                return services();
            case "resolve":
                return resolve(a);
            case "suggestions":
                return suggestions(a);
            case "search":
                return search(a);
            case "kiosk":
                return kiosk(a);
            case "channel":
                return channel(a);
            case "channelTab":
                return channelTab(a);
            case "playlist":
                return playlist(a);
            case "stream":
                return stream(a);
            case "comments":
                return comments(a);
            case "more":
                return more(a);
            default:
                throw new IllegalArgumentException("Unknown method: " + method);
        }
    }

    private static JsonObject configure(final JsonObject a) {
        final String language = a.getString("language", "en");
        final String country = a.getString("country", "US");
        NewPipe.setupLocalization(new Localization(language, country), new ContentCountry(country));
        return new JsonObject();
    }

    private static JsonObject services() throws Exception {
        final JsonArray list = new JsonArray();
        for (final StreamingService s : NewPipe.getServices()) {
            final JsonObject o = new JsonObject();
            o.put("id", s.getServiceId());
            o.put("name", s.getServiceInfo().getName());
            o.put("baseUrl", s.getBaseUrl());
            final JsonArray capabilities = new JsonArray();
            for (final StreamingService.ServiceInfo.MediaCapability c
                    : s.getServiceInfo().getMediaCapabilities()) {
                capabilities.add(c.name().toLowerCase());
            }
            o.put("capabilities", capabilities);
            final KioskList kiosks = s.getKioskList();
            o.put("kiosks", new JsonArray(new ArrayList<>(kiosks.getAvailableKiosks())));
            o.put("defaultKiosk", kiosks.getDefaultKioskId());
            o.put("searchFilters", new JsonArray(
                    java.util.Arrays.asList(s.getSearchQHFactory().getAvailableContentFilter())));
            list.add(o);
        }
        final JsonObject out = new JsonObject();
        out.put("services", list);
        return out;
    }

    private static JsonObject resolve(final JsonObject a) throws Exception {
        final String url = a.getString("url");
        final StreamingService s = NewPipe.getServiceByUrl(url);
        final JsonObject out = new JsonObject();
        out.put("serviceId", s.getServiceId());
        out.put("linkType", s.getLinkTypeByUrl(url).name().toLowerCase());
        return out;
    }

    private static JsonObject suggestions(final JsonObject a) throws Exception {
        final JsonObject out = new JsonObject();
        final List<String> list = service(a).getSuggestionExtractor() == null
                ? Collections.emptyList()
                : service(a).getSuggestionExtractor().suggestionList(a.getString("query"));
        out.put("suggestions", new JsonArray(list));
        return out;
    }

    private static JsonObject listInfo(final List<? extends InfoItem> items, final Page next) {
        final JsonObject o = new JsonObject();
        o.put("items", Json.items(items));
        o.put("nextPage", Json.page(next));
        return o;
    }

    private static JsonObject search(final JsonObject a) throws Exception {
        final StreamingService s = service(a);
        final SearchInfo info = SearchInfo.getInfo(s, searchHandler(s, a));
        final JsonObject o = listInfo(info.getRelatedItems(), info.getNextPage());
        o.put("url", info.getUrl());
        o.put("suggestion", info.getSearchSuggestion());
        o.put("corrected", info.isCorrectedSearch());
        errors(o, info.getErrors());
        return o;
    }

    private static SearchQueryHandler searchHandler(final StreamingService s, final JsonObject a)
            throws Exception {
        final List<String> filters = new ArrayList<>();
        if (a.getString("filter") != null) {
            filters.add(a.getString("filter"));
        }
        return s.getSearchQHFactory().fromQuery(a.getString("query"), filters, "");
    }

    private static void errors(final JsonObject o, final List<Throwable> errors) {
        final JsonArray list = new JsonArray();
        for (final Throwable t : errors) {
            list.add(t.getClass().getName() + ": " + t.getMessage());
        }
        o.put("errors", list);
    }

    private static JsonObject kiosk(final JsonObject a) throws Exception {
        final StreamingService s = service(a);
        final KioskExtractor<?> extractor = s.getKioskList()
                .getExtractorById(a.getString("id"), null);
        extractor.fetchPage();
        final KioskInfo info = KioskInfo.getInfo(extractor);
        final JsonObject o = listInfo(info.getRelatedItems(), info.getNextPage());
        o.put("name", info.getName());
        o.put("url", info.getUrl());
        errors(o, info.getErrors());
        return o;
    }

    private static JsonObject channel(final JsonObject a) throws Exception {
        final ChannelInfo info = ChannelInfo.getInfo(service(a), a.getString("url"));
        final JsonObject o = new JsonObject();
        o.put("serviceId", info.getServiceId());
        o.put("url", info.getUrl());
        o.put("name", info.getName());
        o.put("description", info.getDescription());
        o.put("avatars", Json.images(info.getAvatars()));
        o.put("banners", Json.images(info.getBanners()));
        o.put("subscriberCount", info.getSubscriberCount());
        o.put("verified", info.isVerified());
        final JsonArray tabs = new JsonArray();
        for (final ListLinkHandler tab : info.getTabs()) {
            final JsonObject t = new JsonObject();
            t.put("name", tab.getContentFilters().isEmpty() ? "" : tab.getContentFilters().get(0));
            final String token = "tab" + nextTab++;
            TABS.put(token, tab);
            if (TABS.size() > 200) {
                TABS.remove(TABS.keySet().iterator().next());
            }
            t.put("token", token);
            tabs.add(t);
        }
        o.put("tabs", tabs);
        errors(o, info.getErrors());
        return o;
    }

    private static JsonObject channelTab(final JsonObject a) throws Exception {
        final ListLinkHandler handler = TABS.get(a.getString("token"));
        if (handler == null) {
            throw new IllegalArgumentException("Channel tab expired; reopen the channel");
        }
        final ChannelTabInfo info = ChannelTabInfo.getInfo(service(a), handler);
        final JsonObject o = listInfo(info.getRelatedItems(), info.getNextPage());
        errors(o, info.getErrors());
        return o;
    }

    private static JsonObject playlist(final JsonObject a) throws Exception {
        final PlaylistInfo info = PlaylistInfo.getInfo(service(a), a.getString("url"));
        final JsonObject o = listInfo(info.getRelatedItems(), info.getNextPage());
        o.put("serviceId", info.getServiceId());
        o.put("url", info.getUrl());
        o.put("name", info.getName());
        o.put("thumbnails", Json.images(info.getThumbnails()));
        o.put("uploaderName", info.getUploaderName());
        o.put("uploaderUrl", info.getUploaderUrl());
        o.put("streamCount", info.getStreamCount());
        o.put("description", Json.description(info.getDescription()));
        errors(o, info.getErrors());
        return o;
    }

    private static JsonObject stream(final JsonObject a) throws Exception {
        final StreamInfo info = StreamInfo.getInfo(service(a), a.getString("url"));
        final JsonObject o = new JsonObject();
        o.put("serviceId", info.getServiceId());
        o.put("url", info.getUrl());
        o.put("id", info.getId());
        o.put("name", info.getName());
        o.put("streamType", info.getStreamType().name());
        o.put("thumbnails", Json.images(info.getThumbnails()));
        o.put("uploaderName", info.getUploaderName());
        o.put("uploaderUrl", info.getUploaderUrl());
        o.put("uploaderAvatars", Json.images(info.getUploaderAvatars()));
        o.put("uploaderSubscriberCount", info.getUploaderSubscriberCount());
        o.put("uploadDate", Json.date(info.getUploadDate()));
        o.put("textualUploadDate", info.getTextualUploadDate());
        o.put("duration", info.getDuration());
        o.put("viewCount", info.getViewCount());
        o.put("likeCount", info.getLikeCount());
        o.put("dislikeCount", info.getDislikeCount());
        o.put("ageLimit", info.getAgeLimit());
        o.put("description", Json.description(info.getDescription()));
        o.put("descriptionType", Json.descriptionType(info.getDescription()));
        o.put("category", info.getCategory());
        o.put("licence", info.getLicence());
        o.put("tags", new JsonArray(info.getTags() == null
                ? Collections.emptyList() : info.getTags()));
        o.put("hlsUrl", info.getHlsUrl());
        o.put("dashMpdUrl", info.getDashMpdUrl());
        o.put("startPosition", info.getStartPosition());
        o.put("videoStreams", Json.videoStreams(info.getVideoStreams()));
        o.put("videoOnlyStreams", Json.videoStreams(info.getVideoOnlyStreams()));
        o.put("audioStreams", Json.audioStreams(info.getAudioStreams()));
        o.put("subtitles", Json.subtitles(info.getSubtitles()));
        o.put("relatedItems", Json.items(info.getRelatedItems()));
        final JsonArray segments = new JsonArray();
        if (info.getStreamSegments() != null) {
            for (final StreamSegment segment : info.getStreamSegments()) {
                final JsonObject seg = new JsonObject();
                seg.put("title", segment.getTitle());
                seg.put("start", segment.getStartTimeSeconds());
                segments.add(seg);
            }
        }
        o.put("segments", segments);
        errors(o, info.getErrors());
        return o;
    }

    private static JsonObject comments(final JsonObject a) throws Exception {
        final CommentsInfo info = CommentsInfo.getInfo(service(a), a.getString("url"));
        final JsonObject o = listInfo(info.getRelatedItems(), info.getNextPage());
        o.put("disabled", info.isCommentsDisabled());
        o.put("count", info.getCommentsCount());
        errors(o, info.getErrors());
        return o;
    }

    private static JsonObject more(final JsonObject a) throws Exception {
        final StreamingService s = service(a);
        final Page page = Json.parsePage(a.getObject("page"));
        final String url = a.getString("url");
        final InfoItemsPage<? extends InfoItem> result;
        switch (a.getString("kind")) {
            case "search":
                result = SearchInfo.getMoreItems(s, searchHandler(s, a), page);
                break;
            case "kiosk":
                result = KioskInfo.getMoreItems(s, url, page);
                break;
            case "playlist":
                result = PlaylistInfo.getMoreItems(s, url, page);
                break;
            case "comments":
                result = CommentsInfo.getMoreItems(s, url, page);
                break;
            case "channelTab":
                final ListLinkHandler handler = TABS.get(a.getString("token"));
                if (handler == null) {
                    throw new IllegalArgumentException("Channel tab expired; reopen the channel");
                }
                result = ChannelTabInfo.getMoreItems(s, handler, page);
                break;
            default:
                throw new IllegalArgumentException("Unknown kind: " + a.getString("kind"));
        }
        return listInfo(result.getItems(), result.getNextPage());
    }
}
