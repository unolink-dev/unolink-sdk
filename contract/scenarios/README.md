# Scenarios

Each file is one scripted conversation with the API. The backend's contract tests replay every file against a real API
and database. The SDK test suites use the same files to check the requests they build and how they react to each
response.

```jsonc
{
  "name": "…",
  "setup": {
    "plan": "pro",                          // the app owner's plan: free | indie | pro | studio
    "key": "valid",                         // valid | revoked | malformed | none
    "links": [{ "slug": "tiktok", "deepLink": "/promo", "params": { "offer": "3for2" } }],
    "usageThisMonth": 0                     // quota-counted events already used this month
  },
  "steps": [
    { "click": { "link": "tiktok", "query": "utm_source=tiktok", "save": "c1" } },   // an Android visitor taps the link
    { "request": { "method": "POST", "path": "/v1/install", "body": { … } },
      "expect":  { "status": 200, "schema": "install-response", "body": { … } } }
  ]
}
```

`link` is a campaign slug, or `null` for the app's main link.

Placeholders inside strings:

| Placeholder | Value |
|---|---|
| `${uuid:name}` | A random UUID, the same every time `name` is used in the scenario |
| `${referrer:c1}` | The Play referrer string saved from click `c1` (what Play hands the app) |
| `${clickId:c1}` | The click ID of click `c1` |
| `${now}` | The current time, ISO 8601 |
| `${daysAgo:30}` | The time 30 days ago, ISO 8601 |
| `${any}` | In `expect.body` only: any non-null value |

`expect.body` is matched as a subset: every listed field must match; fields not listed are ignored. Arrays must have
the listed length and each element matches as a subset. `null` means the field is null or absent.
