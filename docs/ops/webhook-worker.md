# Scheduling the webhook worker (free infrastructure)

`bin/ots webhooks:work` is the only component that drains the Redis queue. It is
deliberately out of the web process. Use what the host already has — **cron** or a
**systemd timer** — and the wrapper at `script/webhook-worker.sh`. No new service,
broker, queue, or paid tier is needed.

The wrapper takes a non-blocking `flock`, refuses to run when
`WEBHOOK_ALLOW_PRIVATE=true`, and inherits the container environment (no secret in
argv). Delivery itself is pinned to the IP resolved and validated when the endpoint
was created; private ranges and IPv4-mapped IPv6 are rejected.

## Option A — cron (every minute)

```cron
* * * * * OTS_PROJECT_DIR=/srv/onetime-secret /srv/onetime-secret/script/webhook-worker.sh >> /var/log/ots-webhook-worker.log 2>&1
```

## Option B — systemd timer (preferred, no root cron needed)

`/etc/systemd/system/ots-webhook-worker.service`:

```ini
[Unit]
Description=OneShotLink webhook delivery drain
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
Environment=OTS_PROJECT_DIR=/srv/onetime-secret
ExecStart=/srv/onetime-secret/script/webhook-worker.sh
```

`/etc/systemd/system/ots-webhook-worker.timer`:

```ini
[Unit]
Description=Run OneShotLink webhook drain every minute

[Timer]
OnCalendar=*:0/1
Persistent=true

[Install]
WantedBy=timers.target
```

Enable with `systemctl daemon-reload && systemctl enable --now ots-webhook-worker.timer`.
`Persistent=true` catches up a run missed while the host was down; `MAX_ATTEMPTS`
and the short per-attempt lock in `Webhook.deliver` make redelivery safe.

## Secure egress (host firewall, no paid service)

The application already blocks private/metadata destinations at endpoint creation
and pins the TCP destination at delivery (`Webhook.validate_endpoint`,
`Webhook.pinned_address`, `Webhook.post`). For defence in depth, restrict the
worker container's outbound traffic to TCP 443 only. Example with ufw (adjust the
interface and deny rule to your host):

```sh
ufw allow out on eth0 to any port 443 proto tcp
ufw deny out on eth0 to 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16
```

On a managed/free container host where you cannot set host firewall rules, record
the provider's egress policy instead and verify a queued event reaches a public
test receiver with a valid `X-OneShotLink-Signature`.

## Verification (operator, on the target host)

1. Queue an event to a public test receiver you control.
2. Run `script/webhook-worker.sh` once (or wait for the timer).
3. Confirm the receiver got one POST and its HMAC verifies with the endpoint's
   signing secret; a forced re-run is a no-op (dedup key + lock).
4. Record the command output in `replica/deploy.md`.
