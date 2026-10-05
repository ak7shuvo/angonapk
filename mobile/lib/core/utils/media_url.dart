/// Storage paths such as "/media/u/x.jpg" live on the API host; absolute URLs
/// (object storage / CDN) are used as-is.
String resolveMediaUrl(String baseUrl, String raw) =>
    raw.startsWith('/') ? '$baseUrl$raw' : raw;
