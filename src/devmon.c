/* Device node monitor for the Finit condition engine
 *
 * Copyright (c) 2022-2025  Joachim Wiberg <troglobit@gmail.com>
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

#include <fnmatch.h>
#include <glob.h>
#include <limits.h>
#include <paths.h>

#include "finit.h"
#include "cond.h"
#include "helpers.h"
#include "pid.h"
#include "plugin.h"
#include "service.h"
#include "iwatch.h"

static struct iwatch iw_devmon;
static uev_t devw;
static int fd;

struct dev_node {
	TAILQ_ENTRY(dev_node) link;
	char   *name;
	size_t  refcnt;
};

static TAILQ_HEAD(, dev_node) dev_node_list = TAILQ_HEAD_INITIALIZER(dev_node_list);

static struct dev_node *find_node(const char *cond)
{
	struct dev_node *node, *tmp;

	TAILQ_FOREACH_SAFE(node, &dev_node_list, link, tmp) {
		if (string_compare(node->name, cond))
			return node;
	}

	return NULL;
}

static int devmon_cond(const char *cond)
{
	return !strncmp(cond, COND_DEV,   strlen(COND_DEV))   ||
	       !strncmp(cond, COND_CLASS, strlen(COND_CLASS)) ||
	       !strncmp(cond, COND_DRIVER, strlen(COND_DRIVER));
}

/*
 * keventd asserts class/ and driver/ conditions for devices that never
 * get a /dev node, e.g. LEDs and DSA switch ports.  For those the
 * condition file is the only record of the device.
 */
static int dev_exists(const char *cond)
{
	char path[PATH_MAX], tmp[PATH_MAX];

	snprintf(path, sizeof(path), "/%s", cond);
	if (fexist(path))
		return 1;

	snprintf(tmp, sizeof(tmp), _PATH_COND "%s", cond);
	return fexist(pid_runpath(tmp, path, sizeof(path)));
}

static void drop_node(struct dev_node *node)
{
	if (!node)
		return;

	node->refcnt--;
	if (node->refcnt)
		return;

	TAILQ_REMOVE(&dev_node_list, node, link);
	free(node->name);
	free(node);
}

void devmon_add_cond(const char *cond)
{
	struct dev_node *node;

	if (!cond || !devmon_cond(cond)) {
//		dbg("no match %s", cond ?: "<NIL>");
		return;
	}

//	dbg("%s", cond);
	node = find_node(cond);
	if (node) {
		node->refcnt++;
		return;
	}

	node = malloc(sizeof(*node));
	if (!node) {
	fail:
		warn("failed allocating node %s", cond);
		return;
	}

	node->name = strdup(cond);
	if (!node->name) {
		free(node);
		goto fail;
	}
	node->refcnt = 1;

	TAILQ_INSERT_TAIL(&dev_node_list, node, link);

	if (dev_exists(cond))
		cond_set(cond);
}

void devmon_del_cond(const char *cond)
{
	if (!cond || !devmon_cond(cond))
		return;

	drop_node(find_node(cond));
}

void devmon_reconf(void)
{
	struct dev_node *node, *tmp;

	TAILQ_FOREACH_SAFE(node, &dev_node_list, link, tmp) {
		if (dev_exists(node->name))
			cond_set(node->name);
		else
			cond_clear(node->name);
	}
}

static int devmon_add_path(struct iwatch *iw, char *path)
{
	char *ptr;

	ptr = strstr(path, "dev/");
	if (ptr) {
		char *slash;

		ptr += 4;
		slash = strchr(ptr, '/');
		if (slash) {
			ptr = slash++;
			slash = strchr(ptr, '/');
			if (slash) {
				dbg("Path too deep, skipping.");
				return -1;
			}
		}
	}

	return iwatch_add1(iw, path, IN_CREATE | IN_DELETE);
}

static void devmon_update_conds(char *dir, char *name, uint32_t mask)
{
	char fn[PATH_MAX];
	char *cond;

	paste(fn, sizeof(fn), dir, name);

	/*
	 * Events in the condition tree come from keventd, the file is
	 * the condition state so only kick affected services, like the
	 * sys/usr plugins do.
	 */
	cond = strstr(fn, COND_BASE);
	if (cond) {
		cond_update(cond + strlen(COND_BASE) + 1);
		return;
	}

	cond = &fn[1];

//	dbg("path: %s, mask: %08x, cond: %s", fn, mask, cond);
	if (!find_node(cond)) {
//		dbg("unregistered, skipping %s", cond);
		return;
	}

	if (mask & IN_CREATE)
		cond_set(cond);
	else if (mask & IN_DELETE)
		cond_clear(cond);
}

/* synthesize events in case of new run dirs */
static void devmon_scandir(struct iwatch *iw, char *dir, int len)
{
	char path[len + 6];
	glob_t gl;
	size_t i;
	int rc;

	(void)iw;

	snprintf(path, sizeof(path), "%s/*", dir);
	rc = glob(path, GLOB_NOSORT, NULL, &gl);
	if (rc && rc != GLOB_NOMATCH)
		return;

	for (i = 0; i < gl.gl_pathc; i++) {
//		dbg("scan found %s", gl.gl_pathv[i]);
		devmon_update_conds(dir, gl.gl_pathv[i], IN_CREATE);
	}
	globfree(&gl);
}

/*
 * create/remove sub-directory in monitored directory
 */
static void devmon_handle_dir(struct iwatch *iw, char *dir, char *name, int mask)
{
	char path[strlen(dir) + strlen(name) + 2];
	struct iwatch_path *iwp;

	paste(path, sizeof(path), dir, name);
	dbg("path: %s", path);

	iwp = iwatch_find_by_path(iw, path);

	if (mask & IN_CREATE) {
		if (!iwp) {
			if (!devmon_add_path(iw, path))
				devmon_scandir(iw, path, sizeof(path));
		}
	} else if (mask & IN_DELETE) {
		if (iwp)
			iwatch_del(&iw_devmon, iwp);
	}
}

static void devmon_cb(uev_t *w, void *arg, int events)
{
	static char ev_buf[8 *(sizeof(struct inotify_event) + NAME_MAX + 1) + 1];
	struct inotify_event *ev;
	ssize_t sz;
	size_t off;

	(void)arg;

	if (UEV_ERROR == events) {
		errx(1, "Unrecoverable error in devmon watcher");
		return;
	}

	sz = read(w->fd, ev_buf, sizeof(ev_buf) - 1);
	if (sz <= 0) {
		err(1, "invalid inotify event");
		return;
	}
	ev_buf[sz] = 0;

	for (off = 0; off < (size_t)sz; off += sizeof(*ev) + ev->len) {
		struct iwatch_path *iwp;

		if (off + sizeof(*ev) > (size_t)sz)
			break;

		ev = (struct inotify_event *)&ev_buf[off];
		if (off + sizeof(*ev) + ev->len > (size_t)sz)
			break;

		if (!ev->mask)
			continue;

		/* Find base path for this event */
		iwp = iwatch_find_by_wd(&iw_devmon, ev->wd);
		if (!iwp)
			continue;

		if (ev->mask & IN_ISDIR) {
			devmon_handle_dir(&iw_devmon, iwp->path, ev->name, ev->mask);
			continue;
		}

//		dbg("Got %s", ev->name);
		if (ev->mask & (IN_CREATE | IN_DELETE))
			devmon_update_conds(iwp->path, ev->name, ev->mask);
	}
}

void devmon_init(uev_ctx_t *ctx)
{
	const char *cond_dirs[] = { _PATH_CONDDEV, _PATH_CONDCLASS, _PATH_CONDDRIVER };
	char dir[MAX_ARG_LEN];
	size_t i;

	fd = iwatch_init(&iw_devmon);
	if (fd < 0)
		return;

	if (uev_io_init(ctx, &devw, devmon_cb, NULL, fd, UEV_READ)) {
		err(1, "Failed setting up I/O callback for /dev watcher");
		close(fd);
		return;
	}

	for (i = 0; i < NELEMS(cond_dirs); i++) {
		pid_runpath(cond_dirs[i], dir, sizeof(dir));
		if (mkpath(dir, 0755) && errno != EEXIST) {
			err(1, "Failed creating condition directory %s", dir);
			continue;
		}

		devmon_add_path(&iw_devmon, dir);
	}

	strlcpy(dir, _PATH_DEV, sizeof(dir));
	if (devmon_add_path(&iw_devmon, dir))
		iwatch_exit(&iw_devmon);
}

/**
 * Local Variables:
 *  indent-tabs-mode: t
 *  c-file-style: "linux"
 * End:
 */
