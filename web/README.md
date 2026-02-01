# XcodeQuery WASM Demo

This folder hosts a browser-based demo that runs the XcodeQuery WASM module to execute GraphQL-style queries against a dropped `.xcodeproj` bundle.

## Build the WASM asset

```
make wasm-web
```

This writes `web/xcodequery-wasm.wasm`.

## Run the demo

Serve this folder with a local web server, then open the URL (for example `http://localhost:8082/`).
