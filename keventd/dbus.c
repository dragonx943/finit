/* keventd D-Bus interface: org.finit.Device1 on its own local bus
 *
 * keventd serves /run/keventd/bus the same way Finit serves
 * /run/finit/bus: brokerless, libink, one socket per daemon.  No
 * message forwarding exists between the two, by design -- clients
 * that want both connect to both.
 *
 * Copyright (c) 2026  Joachim Wiberg <troglobit@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "config.h"

#ifdef HAVE_DBUS

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>
#include <uev/uev.h>

#ifdef _LIBITE_LITE
# include <libite/lite.h>
#else
# include <lite/lite.h>
#endif

#include "link.h"

#include "keventd.h"
#include "udevdb.h"
#include "util.h"

#define DEVBUS_DIR         "/run/keventd"
#define DEVBUS_SOCKET      DEVBUS_DIR "/bus"
#define DEVBUS_PATH_OBJECT "/org/finit/device"
#define DEVBUS_INTERFACE   "org.finit.Device1"
#define DEVBUS_MAX_PEERS   16
#define DEVBUS_MAX_SETTLES 8

struct peer {
	uev_t              watcher;
	link_connection_t *conn;
	int                dead;
	TAILQ_ENTRY(peer)  link;
};

static TAILQ_HEAD(, peer) peers = TAILQ_HEAD_INITIALIZER(peers);
static TAILQ_HEAD(, peer) reapq = TAILQ_HEAD_INITIALIZER(reapq);
static link_server_t     *server;
static uev_t              accept_watcher;
static uev_t              reap_timer;
static uev_ctx_t         *devbus_ctx;
static size_t             peer_count;
static int                bus_passive;

/* Parked Settle() calls with their own deadlines */
struct settle {
	link_connection_t *conn;
	link_authz_t       tok;
	uint64_t           deadline;	/* CLOCK_MONOTONIC ms */
};

static struct settle settles[DEVBUS_MAX_SETTLES];
static uev_t         settle_timer;
static int           settle_armed;

/*
 * Same policy as /run/finit/bus: root and members of the --with-group
 * group.  The group set comes from the kernel (SO_PEERGROUPS), the
 * owning gid is resolved once at init so no call ever hits NSS.
 */
static gid_t privileged_gid = (gid_t)-1;	/* DEFGROUP, resolved at init */

static int caller_is_privileged(uid_t uid, const gid_t *groups, int ngroups,
				void *userdata)
{
	(void)userdata;

	if (uid == 0)
		return 1;

	if (privileged_gid == (gid_t)-1)
		return 0;	/* no owning group to match against */

	for (int i = 0; i < ngroups; i++) {
		if (groups[i] == privileged_gid)
			return 1;
	}

	return 0;
}

static void link_log_cb(void *userdata, const char *func, const char *msg)
{
	(void)userdata;
	logit(LOG_DEBUG, "%s():%s", func, msg);
}

/* ---------- peer lifecycle, same shape as src/dbus.c ---------- */

static void peer_reap(uev_t *w, void *arg, int events)
{
	struct peer *p;

	(void)w; (void)arg; (void)events;
	while ((p = TAILQ_FIRST(&reapq))) {
		TAILQ_REMOVE(&reapq, p, link);
		link_connection_close(p->conn);
		free(p);
	}
}

static void peer_drop(struct peer *p)
{
	int i;

	if (p->dead)
		return;
	p->dead = 1;

	uev_io_stop(&p->watcher);
	TAILQ_REMOVE(&peers, p, link);
	peer_count--;

	/* Settles parked on this connection die with it */
	for (i = 0; i < DEVBUS_MAX_SETTLES; i++) {
		if (settles[i].conn == p->conn)
			settles[i].conn = NULL;
	}

	TAILQ_INSERT_TAIL(&reapq, p, link);
	uev_timer_set(&reap_timer, 10, 0);
}

static void peer_cb(uev_t *w, void *arg, int events)
{
	struct peer *p = arg;

	(void)w;

	if (UEV_ERROR == events || link_connection_process(p->conn) < 0)
		peer_drop(p);
}

static void accept_cb(uev_t *w, void *arg, int events)
{
	(void)arg;

	if (UEV_ERROR == events) {
		logit(LOG_ERR, "D-Bus accept watcher error");
		return;
	}

	for (;;) {
		link_connection_t *conn = NULL;
		struct peer *p;

		if (link_server_accept(server, &conn) < 0) {
			if (errno != EAGAIN && errno != EWOULDBLOCK)
				logit(LOG_ERR, "Failed accepting D-Bus client: %s",
				      strerror(errno));
			break;
		}

		if (peer_count >= DEVBUS_MAX_PEERS) {
			logit(LOG_WARNING, "D-Bus peer cap reached (%zu), dropping",
			      peer_count);
			link_connection_close(conn);
			continue;
		}

		p = calloc(1, sizeof(*p));
		if (!p) {
			link_connection_close(conn);
			continue;
		}

		p->conn = conn;
		TAILQ_INSERT_TAIL(&peers, p, link);
		peer_count++;

		if (uev_io_init(w->ctx, &p->watcher, peer_cb, p,
				link_connection_get_fd(conn), UEV_READ))
			peer_drop(p);
	}
}

/* ---------- parked Settle() bookkeeping ---------- */

static void settle_sweep(uev_t *w, void *arg, int events);

/*
 * The queue can only drain when an event is processed, and
 * devbus_notify() sweeps on exactly that; the timer exists solely to
 * enforce deadlines, so arm it one-shot for the nearest one.
 */
static void settle_arm(uint64_t deadline)
{
	uint64_t now = kev_now_ms();
	int ms = deadline > now ? (int)(deadline - now) : 1;

	if (!settle_armed) {
		uev_timer_init(devbus_ctx, &settle_timer, settle_sweep,
			       NULL, ms, 0);
		settle_armed = 1;
	} else {
		uev_timer_set(&settle_timer, ms, 0);
	}
}

/*
 * Resume parked settles: all of them when the queue drained (the
 * handler re-runs, sees the empty queue, replies true), expired ones
 * otherwise (the handler re-runs, sees link_call_resumed(), replies
 * false).
 */
static void settle_sweep(uev_t *w, void *arg, int events)
{
	uint64_t next = 0;
	uint64_t now = kev_now_ms();
	int empty = kev_queue_empty();
	int i;

	(void)w; (void)arg; (void)events;

	for (i = 0; i < DEVBUS_MAX_SETTLES; i++) {
		struct settle *s = &settles[i];

		if (!s->conn)
			continue;

		if (empty || now >= s->deadline) {
			link_connection_t *conn = s->conn;
			link_authz_t       tok  = s->tok;

			s->conn = NULL;
			link_call_resume(conn, tok);
			continue;
		}
		if (!next || s->deadline < next)
			next = s->deadline;
	}

	if (next) {
		settle_arm(next);
	} else if (settle_armed) {
		uev_timer_stop(&settle_timer);
		settle_armed = 0;
	}
}

/* ---------- org.finit.Device1 ---------- */

static int device1_settle(link_call_t *call, void *u)
{
	link_writer_t *w;
	uint32_t timeout;
	int i;

	int empty;

	(void)u;
	if (link_call_read_u32(call, &timeout) < 0)
		return link_call_reply_error(call,
			"org.freedesktop.DBus.Error.InvalidArgs",
			"expected (u)");

	empty = kev_queue_empty();
	if (!empty && !link_call_resumed(call)) {
		for (i = 0; i < DEVBUS_MAX_SETTLES; i++) {
			if (settles[i].conn)
				continue;

			if (link_call_park(call, &settles[i].tok))
				break;

			settles[i].conn     = link_call_connection(call);
			settles[i].deadline = kev_now_ms() + (uint64_t)timeout * 1000;
			settle_arm(settles[i].deadline);
			return 0;
		}
		/* no room to wait: answer with the state as it stands */
	}

	w = link_call_reply(call);
	link_w_bool(w, empty);
	return 0;
}

static int device1_trigger(link_call_t *call, void *u)
{
	const char *action, *glob;

	(void)u;
	if (link_call_read_string(call, &action) < 0 ||
	    link_call_read_string(call, &glob) < 0)
		return link_call_reply_error(call,
			"org.freedesktop.DBus.Error.InvalidArgs",
			"expected (s, s)");

	if (bus_passive)
		return link_call_reply_error(call,
			"org.finit.Error.Failed",
			"keventd is passive, device events are not handled here");

	if (*action && !uevent_action_valid(action))
		return link_call_reply_error(call,
			"org.freedesktop.DBus.Error.InvalidArgs",
			"unknown uevent action");

	if (coldplug_trigger(action, glob))
		return link_call_reply_error(call,
			"org.finit.Error.Failed", "trigger failed");

	(void)link_call_reply(call);
	return 0;
}

static int device1_info(link_call_t *call, void *u)
{
	struct uevent ev;
	const char *devpath;
	link_writer_t *w;
	int i;

	(void)u;
	if (link_call_read_string(call, &devpath) < 0 || *devpath != '/')
		return link_call_reply_error(call,
			"org.freedesktop.DBus.Error.InvalidArgs",
			"expected (s), an absolute devpath");

	memset(&ev, 0, sizeof(ev));
	if (udevdb_read_devpath(devpath, &ev)) {
		uevent_env_free(&ev);
		return link_call_reply_error(call,
			"org.finit.Error.NoSuchDevice",
			"no database record for devpath");
	}

	w = link_call_reply(call);
	link_w_array_begin(w, '{');
	for (i = 0; i < ev.nenv; i++) {
		link_w_struct_begin(w);
		link_w_string(w, ev.env_key[i]);
		link_w_string(w, ev.env_val[i]);
		link_w_struct_end(w);
	}
	link_w_array_end(w);

	uevent_env_free(&ev);
	return 0;
}

static int device1_rules_reload(link_call_t *call, void *u)
{
	link_writer_t *w;

	(void)u;
	if (bus_passive)
		return link_call_reply_error(call,
			"org.finit.Error.Failed",
			"keventd is passive, rules are not applied here");

	w = link_call_reply(call);
	link_w_u32(w, (uint32_t)kev_rules_reload());
	return 0;
}

static int prop_queue_empty(link_writer_t *w, void *u)
{
	(void)u;
	link_w_bool(w, kev_queue_empty());
	return 0;
}

static int prop_seqnum(link_writer_t *w, void *u)
{
	(void)u;
	link_w_u64(w, kev_seq_processed());
	return 0;
}

static const link_method_t device_methods[] = {
	{ .name = "Settle",      .in_sig = "u",  .out_sig = "b",
	  .handler = device1_settle },
	{ .name = "Trigger",     .in_sig = "ss", .out_sig = "",
	  .flags = LINK_METHOD_PRIVILEGED, .handler = device1_trigger },
	{ .name = "Info",        .in_sig = "s",  .out_sig = "a{ss}",
	  .handler = device1_info },
	{ .name = "RulesReload", .in_sig = "",   .out_sig = "u",
	  .flags = LINK_METHOD_PRIVILEGED, .handler = device1_rules_reload },
	{ NULL, NULL, NULL, 0, NULL }
};

static const link_property_t device_properties[] = {
	{ .name = "QueueEmpty",      .sig = "b", .getter = prop_queue_empty },
	{ .name = "SeqnumProcessed", .sig = "t", .getter = prop_seqnum },
	{ NULL, NULL, NULL }
};

static const link_signal_t device_signals[] = {
	{ .name = "DeviceProcessed", .sig = "ss" },
	{ NULL, NULL }
};

static const link_vtable_t device_vtable = {
	.interface  = DEVBUS_INTERFACE,
	.methods    = device_methods,
	.properties = device_properties,
	.signals    = device_signals,
};

/* ---------- signal emission + settle nudge ---------- */

static void devbus_emit_signal(const char *member, const char *sig,
			       const uint8_t *body, size_t len)
{
	struct peer *p, *tmp;

	TAILQ_FOREACH_SAFE(p, &peers, link, tmp) {
		if (link_connection_emit_signal(p->conn, DEVBUS_PATH_OBJECT,
						DEVBUS_INTERFACE, member,
						sig, body, len) >= 0)
			continue;
		if (errno == EMSGSIZE || errno == EINVAL)
			break;	/* nothing on the wire, same for all */
		peer_drop(p);
	}
}

void devbus_notify(const char *devpath, const char *action)
{
	uint8_t body[512];
	link_writer_t w;
	ssize_t blen;

	if (!server)
		return;

	/* A processed event may have been the last one in flight */
	if (settle_armed)
		settle_sweep(NULL, NULL, 0);

	if (TAILQ_EMPTY(&peers) || !devpath)
		return;

	link_writer_init(&w, body, sizeof(body));
	link_w_string(&w, devpath);
	link_w_string(&w, action ?: "");
	blen = link_writer_finish(&w);
	if (blen < 0)
		return;

	devbus_emit_signal("DeviceProcessed", "ss", body, (size_t)blen);
}

/* ---------- init / exit / settle client ---------- */

int devbus_init(uev_ctx_t *ctx, int passive)
{
	devbus_ctx  = ctx;
	bus_passive = passive;

	link_set_logger(link_log_cb, NULL);

	if (mkpath(DEVBUS_DIR, 0755) && errno != EEXIST) {
		logit(LOG_ERR, "Failed creating %s: %s", DEVBUS_DIR,
		      strerror(errno));
		return -1;
	}

	if (link_server_new(&server, DEVBUS_SOCKET, 0660) < 0) {
		logit(LOG_ERR, "Failed creating D-Bus socket %s: %s",
		      DEVBUS_SOCKET, strerror(errno));
		return -1;
	}

	/* Resolve the owning group once, see caller_is_privileged() */
	privileged_gid = getgroup(DEFGROUP);
	if (chown(DEVBUS_SOCKET, geteuid(), privileged_gid))
		logit(LOG_WARNING, "Failed setting group %s on %s: %s",
		      DEFGROUP, DEVBUS_SOCKET, strerror(errno));

	link_server_set_authorizer(server, caller_is_privileged, NULL);

	if (link_server_add_object(server, DEVBUS_PATH_OBJECT,
				   &device_vtable, NULL) < 0) {
		logit(LOG_ERR, "Failed registering %s", DEVBUS_INTERFACE);
		link_server_free(server);
		server = NULL;
		return -1;
	}

	uev_timer_init(ctx, &reap_timer, peer_reap, NULL, 0, 0);

	if (uev_io_init(ctx, &accept_watcher, accept_cb, NULL,
			link_server_get_fd(server), UEV_READ)) {
		logit(LOG_ERR, "Failed watching D-Bus socket");
		link_server_free(server);
		server = NULL;
		return -1;
	}

	logit(LOG_NOTICE, "Serving %s on %s", DEVBUS_INTERFACE, DEVBUS_SOCKET);
	return 0;
}

void devbus_exit(void)
{
	struct peer *p;

	if (!server)
		return;

	while ((p = TAILQ_FIRST(&peers)))
		peer_drop(p);
	peer_reap(NULL, NULL, 0);

	uev_io_stop(&accept_watcher);
	link_server_free(server);
	server = NULL;
}

/*
 * Client side of Settle, for `keventd -S`: ask the running keventd.
 * Returns 0 settled, 1 timeout, -1 when no bus answers (fall back to
 * polling the kernel seqnum).
 */
int devbus_client_settle(int timeout_s)
{
	link_client_t *c;
	link_reader_t r;
	const link_reply_t *reply;
	int rc, settled = 0;

	c = link_client_open(DEVBUS_SOCKET);
	if (!c)
		return -1;

	rc = link_client_call_v(c, DEVBUS_PATH_OBJECT, DEVBUS_INTERFACE,
				"Settle", "u", (uint32_t)timeout_s);
	if (rc != LINK_CALL_OK) {
		link_client_close(c);
		return -1;
	}

	reply = link_client_reply(c);
	if (reply && reply->body) {
		link_reader_init(&r, reply->body, reply->body_len);
		link_r_bool(&r, &settled);
	}
	link_client_close(c);

	return settled ? 0 : 1;
}

#endif /* HAVE_DBUS */
