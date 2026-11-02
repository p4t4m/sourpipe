package sourpipe.bridge;

import org.teavm.jso.JSBody;
import org.teavm.jso.JSFunctor;
import org.teavm.jso.JSObject;

/** Everything the JavaScript bundle needs from whoever embeds it (iOS app or test harness). */
final class Host {
    private Host() {
    }

    @JSFunctor
    interface HttpCallback extends JSObject {
        /** @param response JSON {status, url, headers:{name:[values]}, body} or null on failure */
        void done(String response, String error);
    }

    @JSBody(params = {"method", "url", "headersJson", "bodyBase64", "callback"},
            script = "__sourpipeHost.http(method, url, headersJson, bodyBase64, callback);")
    static native void http(String method, String url, String headersJson, String bodyBase64,
                            HttpCallback callback);

    @JSBody(params = "message", script = "__sourpipeHost.log(message);")
    static native void log(String message);

    /** Throws a JS SyntaxError if the code does not compile. */
    @JSBody(params = "code", script = "new Function(code);")
    static native void compileJs(String code);

    @JSBody(params = {"code", "name", "parameters"},
            script = "var fn = new Function(code + '\\n;return ' + name + ';')();"
                    + "return String(fn.apply(null, parameters));")
    static native String runJs(String code, String name, String[] parameters);

    @JSFunctor
    interface Entry extends JSObject {
        void call(String method, String argsJson, ResultCallback callback);
    }

    @JSFunctor
    interface ResultCallback extends JSObject {
        void done(String resultJson, String errorJson);
    }

    @JSBody(params = "entry", script = "globalThis.__sourpipeCall = entry;")
    static native void install(Entry entry);
}
