/* Setup and start system message bus, D-Bus
 *
 * Copyright (c) 2012-2025  Joachim Wiberg <troglobit@gmail.com>
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

#include <sys/types.h>
#ifdef _LIBITE_LITE
# include <libite/lite.h>
#else
# include <lite/lite.h>
#endif

#include "finit.h"
#include "config.h"
#include "helpers.h"
#include "plugin.h"
#include "conf.h"
#include "util.h"
#include "log.h"

#define DBUS_DAEMON "dbus-daemon"

/*
 * Dumnpster diving for the D-Bus main configuration file
 * where <pidfile> is defined.
 */
static char *dbus_pidfn(void)
{
	char *alt[] = {
		"/usr/share/dbus-1/system.conf",
		"/etc/dbus-1/system.conf",
		NULL
	};
	int i;

	for (i = 0; alt[i]; i++) {
		char *fn = alt[i];
		char buf[256];
		FILE *fp;

		fp = fopen(fn, "r");
		if (!fp)
			continue;

		fn = NULL;
		while (fgets(buf, sizeof(buf), fp)) {
			char *pos;

			pos = strstr(buf, "<pidfile>");
			if (!pos)
				continue;
			fn = pos + strlen("<pidfile>");
			pos = strstr(fn, "</pidfile>");
			if (!pos) {
				fn = NULL;
				break;
			}
			*pos = 0;
			break;
		}

		fclose(fp);
		if (fn)
			return strdup(fn);
	}

	return NULL;
}

/*
 * The directories live in tmpfiles.d/dbus.conf and the service in
 * system/20-dbus.conf, both of which an administrator can override.
 * What is left needs to look at the running system, so it stays here.
 */
static void setup(void *arg)
{
	char *pidfn;

	if (rescue) {
		dbg("Skipping %s plugin in rescue mode.", "dbus");
		return;
	}

	if (!whichp(DBUS_DAEMON)) {
		dbg("Skipping plugin, %s is not installed.", DBUS_DAEMON);
		return;
	}

	/* Clean up from any previous pre-bootstrap run */
	pidfn = dbus_pidfn();
	if (pidfn) {
		remove(pidfn);
		free(pidfn);
	}

	/* Generate machine id for dbus */
	if (whichp("dbus-uuidgen"))
		run_interactive("dbus-uuidgen --ensure", "Verifying D-Bus machine UUID");
}

static plugin_t plugin = {
	.name = "dbus",
	.hook[HOOK_SVC_PLUGIN] = { .cb  = setup },
};

PLUGIN_INIT(__init)
{
	plugin_register(&plugin);
}

PLUGIN_EXIT(__exit)
{
	plugin_unregister(&plugin);
}

/**
 * Local Variables:
 *  indent-tabs-mode: t
 *  c-file-style: "linux"
 * End:
 */
