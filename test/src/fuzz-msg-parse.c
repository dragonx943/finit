/* libink — fuzz target for __msg_parse().
 *
 * __msg_parse() is the one place where bytes off a socket become
 * pointers, before any authentication has vouched for the peer.  It
 * hands back borrowed pointers into the caller's buffer, so "did not
 * crash" is too weak a pass: a field that points outside the header it
 * was supposed to come from, or a string with no terminator inside it,
 * is a bug the caller hits later and somewhere else.  Every input is
 * checked against that contract here.
 *
 * Built two ways.  With libFuzzer (clang -fsanitize=fuzzer,address
 * -DLINK_FUZZ_LIBFUZZER) it is a normal fuzz target.  Otherwise it
 * gets the driver below: named files are replayed, which is how a
 * crash found by the fuzzer is reproduced, and with no arguments it
 * runs a fixed sweep so the suite exercises the same contract on
 * every build without needing clang or a corpus in the tree.
 *
 * Copyright (c) 2026  Joachim Wiberg <troglobit@gmail.com>
 * SPDX-License-Identifier: MIT
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

#define FRAME_MAX      512
#define HDR_FIXED_SIZE  16	/* must agree with proto.c */

static void fail(const char *what, size_t size)
{
	fprintf(stderr, "fuzz-msg-parse: %s, on a %zu byte input\n", what, size);
	abort();
}

/* A header field is read out of the header field array and nowhere
 * else.  Checking it against the whole buffer would be too generous:
 * a parser that walked off the end of the fields and into the body
 * would still be pointing at bytes it was handed, and pass.  The
 * bound is derived from the raw header here rather than taken from
 * the parser, so the two have to agree independently.
 *
 * The string must also terminate inside that region, or whoever
 * borrows it reads past what it was given. */
static void check_str(const char *s, const uint8_t *base, size_t len,
		      size_t hdr_end, const char *what)
{
	const char *first = (const char *)base + HDR_FIXED_SIZE;
	const char *last  = (const char *)base + hdr_end;
	size_t room;

	if (!s)
		return;
	if (s < first || s >= last)
		fail(what, len);

	room = (size_t)(last - s);
	if (strnlen(s, room) == room)
		fail(what, len);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct link_msg m;
	size_t hdr_end, body_off;
	uint32_t fields_len;
	ssize_t rc;

	rc = __msg_parse(data, size, &m);
	if (rc <= 0)
		return 0;	/* need more, or refused: both fine */

	/* Consuming more than it was handed would desynchronise the
	 * read loop and make it skip into the next message. */
	if ((size_t)rc > size)
		fail("claimed more bytes than it was given", size);

	/* Only 'l' messages parse, so reading the length this way is
	 * safe, and rc > 0 means the fixed header was all there. */
	memcpy(&fields_len, data + 12, sizeof(fields_len));
	hdr_end  = HDR_FIXED_SIZE + fields_len;
	body_off = (hdr_end + 7) & ~(size_t)7;
	if (hdr_end > size || body_off > size)
		fail("accepted a header longer than the message", size);

	check_str(m.path,        data, size, hdr_end, "path outside the header");
	check_str(m.interface,   data, size, hdr_end, "interface outside the header");
	check_str(m.member,      data, size, hdr_end, "member outside the header");
	check_str(m.error_name,  data, size, hdr_end, "error name outside the header");
	check_str(m.destination, data, size, hdr_end, "destination outside the header");
	check_str(m.sender,      data, size, hdr_end, "sender outside the header");
	check_str(m.signature,   data, size, hdr_end, "signature outside the header");

	if (m.body_avail) {
		if (m.body != data + body_off)
			fail("body does not start where the header ends", size);
		if (m.body_avail > size - body_off)
			fail("body runs past the buffer", size);
	}

	return 0;
}

#ifndef LINK_FUZZ_LIBFUZZER
/* Hand the parser a buffer sized to the input and nothing more.
 * Reading past the end of a roomy array stays inside the allocation
 * and the sanitizer never sees it; against an exact allocation the
 * same read is a fault.  This is what libFuzzer does, and the reason
 * it finds things a fixed buffer cannot. */
static void run(const uint8_t *data, size_t size)
{
	uint8_t *exact = malloc(size ? size : 1);

	if (!exact) {
		fprintf(stderr, "fuzz-msg-parse: out of memory\n");
		abort();
	}
	memcpy(exact, data, size);
	LLVMFuzzerTestOneInput(exact, size);
	free(exact);
}

/* Deterministic, so a failure reproduces from the same build. */
static uint32_t prng(uint32_t *state)
{
	uint32_t x = *state;

	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;

	return *state = x;
}

static int sweep(void)
{
	uint8_t frame[FRAME_MAX], copy[FRAME_MAX];
	static const uint8_t poke[] = { 0x00, 0x01, 0x7f, 0x80, 0xff };
	uint32_t state = 0x1234abcd;
	ssize_t len;
	size_t i, j, n;

	len = __msg_build_method_call(frame, sizeof(frame), 1,
				      "/org/finit/manager", "org.finit.Manager1",
				      "ListServices", NULL, NULL, 0);
	if (len <= 0) {
		fprintf(stderr, "fuzz-msg-parse: cannot build a reference frame\n");
		return 1;
	}

	/* Every prefix: the read loop hands over whatever arrived, and
	 * a short read must come back "need more", never a parse. */
	for (i = 0; i <= (size_t)len; i++)
		run(frame, i);

	/* One byte wrong, everywhere, with the values that flip a
	 * length or an offset furthest. */
	for (i = 0; i < (size_t)len; i++) {
		for (j = 0; j < sizeof(poke); j++) {
			memcpy(copy, frame, (size_t)len);
			copy[i] = poke[j];
			run(copy, (size_t)len);
		}
	}

	/* fields_len decides where the header walk stops, so it is the
	 * byte that decides whether a field is read from the header or
	 * from somewhere else.  Walk it across the whole frame, and
	 * past it, at every truncation the read loop could hand over. */
	for (i = 0; i <= (size_t)len + 8; i++) {
		uint32_t fl = (uint32_t)i;

		memcpy(copy, frame, (size_t)len);
		memcpy(copy + 12, &fl, sizeof(fl));
		for (j = 0; j <= (size_t)len; j++)
			run(copy, j);
	}

	/* And input that was never a message to begin with. */
	for (n = 0; n < 20000; n++) {
		size_t sz = prng(&state) % (FRAME_MAX + 1);

		for (i = 0; i < sz; i++)
			copy[i] = (uint8_t)prng(&state);

		/* Half of them keep a plausible header, so the parser
		 * gets past its first checks and into field walking. */
		if (sz >= 16 && (n & 1)) {
			copy[0] = 'l';
			copy[3] = LINK_PROTOCOL_VERSION;
		}
		run(copy, sz);
	}

	return 0;
}

static int replay(const char *path)
{
	uint8_t buf[64 * 1024];
	size_t  len;
	FILE   *fp;

	fp = fopen(path, "rb");
	if (!fp) {
		perror(path);
		return 1;
	}
	len = fread(buf, 1, sizeof(buf), fp);
	fclose(fp);

	run(buf, len);
	return 0;
}

int main(int argc, char *argv[])
{
	int i, rc = 0;

	if (argc < 2)
		return sweep();

	for (i = 1; i < argc; i++)
		rc |= replay(argv[i]);

	return rc;
}
#endif /* !LINK_FUZZ_LIBFUZZER */
