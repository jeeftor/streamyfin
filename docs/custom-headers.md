# Custom Headers

Streamyfin can attach custom HTTP headers to Jellyfin and Seerr requests. This is intended for deployments that sit behind proxy authentication such as Cloudflare Zero Trust, Pangolin tunnels, or similar access gateways.

## Jellyfin

Configure Jellyfin headers from the Network settings page or from the advanced section while adding a server.

When no custom headers are configured, Streamyfin sends requests normally. Disabled headers, blank header names, and blank header values are ignored and are not sent.

Header values are stored in the device secure store. Header metadata, such as the header name and enabled state, is stored with the saved server entry.

Jellyfin headers are only attached to URLs that match the configured Jellyfin server base URL. Streamyfin should not send Jellyfin custom headers to external artwork providers, remote media URLs, OpenSubtitles downloads, or other unrelated hosts.

## Seerr

Self-hosted integrations such as Seerr, Streamystats, and Marlin Search can use a separate header configuration from Jellyfin. In each integration's settings, choose one of these modes:

- Jellyfin: inherit the custom headers configured for the Jellyfin server.
- Custom: send a separate set of custom headers to that integration.
- None: do not send custom headers to that integration.

Use a separate integration configuration when the service is exposed through a different proxy, tunnel, hostname, or access policy than Jellyfin.

For safety, integrations do not inherit Jellyfin headers until that mode is selected. This prevents Jellyfin proxy credentials from being sent to a separate integration host by default.

## Behavior

Custom headers are only useful for headers required by your own proxy or access gateway. Do not duplicate Jellyfin's normal authorization header unless the proxy explicitly requires it.

If a header is removed, disabled, or left blank, Streamyfin should behave the same as it did before custom headers were configured.

Custom header names must be valid HTTP header tokens. Blank names, blank values, disabled entries, invalid names, control characters in values, and duplicate header names are ignored.
