// Public liveness endpoint. Deliberately reveals no project configuration or secrets.
Deno.serve((req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: { "Allow": "GET, HEAD", "Cache-Control": "no-store" },
    });
  }

  const body = JSON.stringify({
    status: "ok",
    service: "wasel-api",
    timestamp: new Date().toISOString(),
  });

  return new Response(req.method === "HEAD" ? null : body, {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
});
