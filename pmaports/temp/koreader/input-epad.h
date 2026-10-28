/*
    KOReader: E-PAD (MT6797, mainline Linux) input abstraction for Lua

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
*/

#ifndef _KO_INPUT_EPAD_H
#define _KO_INPUT_EPAD_H

#include "libue.h"

#define EPAD_USB_ONLINE "/sys/class/power_supply/usb/online"

static void sendEvent(int fd, struct input_event* ev) {
    if (write(fd, ev, sizeof(struct input_event)) == -1) {
        fprintf(stderr, "[ko-input]: Failed to generate fake event.\n");
    }
}

static int readOnline(void) {
    char c = 0;
    int fd = open(EPAD_USB_ONLINE, O_RDONLY | O_CLOEXEC);
    if (fd != -1) {
        if (read(fd, &c, 1) != 1) {
            c = 0;
        }
        close(fd);
    }
    return c == 1;
}

// Charger plug/unplug: power_supply "change" uevents, compared against the last known state.
static void generateFakeEvent(int pipefd[2]) {
    struct uevent_listener listener;
    struct uevent uev;
    struct input_event ev = { 0 };
    int online = readOnline();

    close(pipefd[0]);
    ev.type = EV_KEY;
    ev.value = 1;

    int re = ue_init_listener(&listener);
    if (re < 0) {
        fprintf(stderr, "[ko-input]: Failed to initialize libue listener (%d)\n", re);
        return;
    }
    while ((re = ue_wait_for_event(&listener, &uev)) == 0) {
        if (uev.subsystem && UE_STR_EQ(uev.subsystem, "power_supply")) {
            int now = readOnline();
            if (now != online) {
                online = now;
                ev.code = now ? CODE_FAKE_CHARGING : CODE_FAKE_NOT_CHARGING;
                sendEvent(pipefd[1], &ev);
            }
        }
    }
}

#endif
