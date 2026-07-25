/* Internal interface between conf.c and the legacy one-liner parser
 *
 * Copyright (c) 2012-2026  Joachim Wiberg <troglobit@gmail.com>
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

#ifndef FINIT_LEGACY_H_
#define FINIT_LEGACY_H_

#include <sys/resource.h>

extern struct rlimit initial_rlimit[RLIMIT_NLIMITS];
extern int runparts_progress;
extern int runparts_sysv;

/*
 * legacy.c -- the frozen legacy one-liner parser.  No new features
 * land here, only in the libconfuse format frontend in conf.c
 */
int  legacy_parse_conf  (char *file, int is_rcsd);
void legacy_parse_env   (char *line);
void kmod_load          (char *mod);
void conf_parse_rlimit  (char *line, struct rlimit arr[]);
char *lim2str           (struct rlimit *rlim);

/*
 * conf.c -- format-detecting frontend.  The legacy include directive
 * routes back through this so included files are format-detected too.
 */
int  conf_parse_file    (char *file, int is_rcsd);

#endif	/* FINIT_LEGACY_H_ */

/**
 * Local Variables:
 *  indent-tabs-mode: t
 *  c-file-style: "linux"
 * End:
 */
