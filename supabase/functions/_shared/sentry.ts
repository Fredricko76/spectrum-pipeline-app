// Optional error reporting to Sentry for the edge functions.
// Env (Supabase function secret, never in the repo):
//   SENTRY_DSN          the spectrum-pipeline-app project DSN. If unset, reporting is a no-op.
//   SENTRY_ENVIRONMENT  optional override; otherwise "production" on the production project,
//                       "preview" everywhere else.
// Only called from error paths. It never throws and never changes a function's response.
// Payloads are scrubbed: no request bodies, headers, names, emails or tokens are sent.
import * as Sentry from "npm:@sentry/deno@11.10.0";

const PROD_REF = "qjkmkmmrgtoaocygymqo";
const EMAIL = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const SECRETISH = /\b(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]+|\bwhsec_[A-Za-z0-9]+|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g;
const PARAM = /([?&](?:key|token|access_token|apikey|email)=)[^&\s"']*/gi;

const scrub = (s: string) =>
  s.replace(EMAIL, "[email]").replace(SECRETISH, "[filtered]").replace(PARAM, "$1[filtered]");

function scrubDeep(v: unknown, depth = 0): unknown {
  if (depth > 6 || v == null) return v;
  if (typeof v === "string") return scrub(v);
  if (Array.isArray(v)) return v.map((x) => scrubDeep(x, depth + 1));
  if (typeof v === "object") {
    const o = v as Record<string, unknown>;
    for (const k of Object.keys(o)) o[k] = scrubDeep(o[k], depth + 1);
  }
  return v;
}

let state: "off" | "on" | undefined;

function ready(): boolean {
  if (state) return state === "on";
  state = "off";
  try {
    const dsn = Deno.env.get("SENTRY_DSN");
    if (!dsn) return false;
    const environment = Deno.env.get("SENTRY_ENVIRONMENT") ||
      ((Deno.env.get("SUPABASE_URL") ?? "").includes(PROD_REF) ? "production" : "preview");
    Sentry.init({
      dsn,
      environment,
      defaultIntegrations: false, // no global handlers, no Deno.serve wrapping, no tracing
      tracesSampleRate: 0,
      // no IP/user inference, cookies, headers, bodies or URL query params
      dataCollection: {
        userInfo: false,
        cookies: false,
        httpHeaders: false,
        httpBodies: [],
        urlQueryParams: false,
        graphQL: { document: false, variables: false },
      },
      beforeSend(event) {
        delete event.user;
        delete event.request;
        delete event.server_name;
        // the edge runtime's own IP would otherwise be recorded as a "user"
        event.sdk = { ...event.sdk, settings: { ...event.sdk?.settings, infer_ip: "never" } } as typeof event.sdk;
        if (event.message) event.message = scrub(event.message);
        scrubDeep(event.exception);
        scrubDeep(event.extra);
        scrubDeep(event.contexts);
        scrubDeep(event.breadcrumbs);
        return event;
      },
    });
    state = "on";
  } catch (_e) {
    state = "off";
  }
  return state === "on";
}

/**
 * Report an unexpected error. `fn` is the function name; `details` must not contain
 * personal information (ids and error codes only).
 */
export async function reportError(
  fn: string,
  err: unknown,
  details?: Record<string, string | number | boolean | null | undefined>,
): Promise<void> {
  try {
    if (!ready()) return;
    const e = err instanceof Error
      ? err
      : new Error(
        typeof err === "object" && err && "message" in err
          ? String((err as { message: unknown }).message)
          : String(err),
      );
    Sentry.withScope((scope) => {
      scope.setTag("function", fn);
      if (details) scope.setContext("details", details);
      Sentry.captureException(e);
    });
    await Sentry.flush(2000);
  } catch (_e) {
    // reporting must never break the function
  }
}
