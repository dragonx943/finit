noinst_PROGRAMS = serv

serv_SOURCES    = serv.c
serv_CPPFLAGS   = -D_XOPEN_SOURCE=600 -D_BSD_SOURCE -D_GNU_SOURCE -D_DEFAULT_SOURCE -I$(top_builddir)
# serv is what notify.sh drives to test notify:systemd, so it always
# needs sd_notify().  The source is in-tree and it links straight in,
# unrelated to whether --with-libsystemd installs the shared library.
serv_CPPFLAGS  += -DHAVE_LIBSYSTEMD=1 -I$(top_srcdir)/libsystemd $(lite_CFLAGS)
serv_SOURCES   += $(top_srcdir)/libsystemd/sd-daemon.c
serv_LDADD      = $(lite_LIBS)

if DBUS
noinst_PROGRAMS           += dbus-auth-client
dbus_auth_client_SOURCES   = dbus-auth-client.c
dbus_auth_client_CPPFLAGS  = -D_GNU_SOURCE -I$(top_srcdir)/libink
dbus_auth_client_LDADD     = $(top_builddir)/libink/libink.la
endif
