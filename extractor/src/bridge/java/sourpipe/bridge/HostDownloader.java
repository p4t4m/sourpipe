package sourpipe.bridge;

import com.grack.nanojson.JsonArray;
import com.grack.nanojson.JsonObject;
import com.grack.nanojson.JsonParser;
import com.grack.nanojson.JsonParserException;
import com.grack.nanojson.JsonWriter;

import org.schabi.newpipe.extractor.downloader.Downloader;
import org.schabi.newpipe.extractor.downloader.Request;
import org.schabi.newpipe.extractor.downloader.Response;
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException;
import org.teavm.interop.Async;
import org.teavm.interop.AsyncCallback;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Suspends the calling TeaVM green thread while the host performs the HTTP request. */
final class HostDownloader extends Downloader {
    private static final class Raw {
        final String response;
        final String error;

        Raw(final String response, final String error) {
            this.response = response;
            this.error = error;
        }
    }

    @Async
    private static native Raw http(String method, String url, String headers, String body);

    private static void http(final String method, final String url, final String headers,
                             final String body, final AsyncCallback<Raw> callback) {
        Host.http(method, url, headers, body,
                (response, error) -> callback.complete(new Raw(response, error)));
    }

    /**
     * The page the app opens for the user to solve the challenge. A GET is simply repeated, as
     * NewPipe does, and the service redirects to its challenge. An API POST cannot be repeated in a
     * browser, so use the challenge page it was redirected to, or else the site's home page.
     */
    private static String challengeUrl(final Request request, final String finalUrl) {
        if ("GET".equals(request.httpMethod())) {
            return request.url();
        }
        if (!finalUrl.equals(request.url())) {
            return finalUrl;
        }
        final String url = request.url();
        final int scheme = url.indexOf("://");
        if (scheme < 0) {
            return url;
        }
        final int path = url.indexOf('/', scheme + 3);
        String origin = path < 0 ? url : url.substring(0, path);
        if (origin.endsWith("youtubei.googleapis.com")) {
            origin = "https://www.youtube.com";
        }
        return origin + "/";
    }

    @Override
    public Response execute(final Request request) throws IOException, ReCaptchaException {
        final JsonObject headers = new JsonObject();
        for (final Map.Entry<String, List<String>> e : request.headers().entrySet()) {
            headers.put(e.getKey(), new JsonArray(e.getValue()));
        }
        final byte[] data = request.dataToSend();
        final Raw raw = http(request.httpMethod(), request.url(), JsonWriter.string(headers),
                data == null ? null : Base64.getEncoder().encodeToString(data));
        if (raw.error != null) {
            throw new IOException(raw.error);
        }
        final JsonObject json;
        try {
            json = JsonParser.object().from(raw.response);
        } catch (final JsonParserException e) {
            throw new IOException("Bad response from host", e);
        }
        final int status = json.getInt("status");
        if (status == 429) {
            throw new ReCaptchaException("reCaptcha Challenge requested",
                    challengeUrl(request, json.getString("url", request.url())));
        }
        final Map<String, List<String>> responseHeaders = new HashMap<>();
        final JsonObject headerObject = json.getObject("headers");
        for (final String name : headerObject.keySet()) {
            final List<String> values = new ArrayList<>();
            for (final Object value : headerObject.getArray(name)) {
                values.add(String.valueOf(value));
            }
            responseHeaders.put(name, values);
        }
        return new Response(status, "", responseHeaders, json.getString("body", ""),
                json.getString("url", request.url()));
    }
}
