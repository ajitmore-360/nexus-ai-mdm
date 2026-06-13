{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Serve CanvasKit from the locally bundled copy instead of the Google CDN.
    // Flutter's build bundles canvaskit/ into build/web/canvaskit/ automatically;
    // this prevents a hard dependency on https://www.gstatic.com at runtime.
    canvasKitBaseUrl: "/canvaskit/",
  },
});
