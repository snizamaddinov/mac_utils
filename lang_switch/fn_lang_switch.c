#include <Carbon/Carbon.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FN_KEY_CODE 179
const char TURKISH_LANGUAGE_LAYOUT_NAME[] = "com.apple.keylayout.Turkish-QWERTY-PC";
const char ENGLISH_LANGUAGE_LAYOUT_NAME[] = "com.apple.keylayout.US";

void switch_input_source() {
    FILE *fp;
    char output[256];
    
    fp = popen("/usr/local/bin/issw", "r");
    if (fp == NULL) {
        fprintf(stderr, "Failed to run issw\n");
        exit(1);
    }

    if (fgets(output, sizeof(output), fp) != NULL) {
        output[strcspn(output, "\n")] = 0;         
        if (strcmp(output, ENGLISH_LANGUAGE_LAYOUT_NAME) == 0) {
            char command[512];
            snprintf(command, sizeof(command), "/usr/local/bin/issw %s", TURKISH_LANGUAGE_LAYOUT_NAME);
            system(command);
        } else {
            char command[512];
            snprintf(command, sizeof(command), "/usr/local/bin/issw %s", ENGLISH_LANGUAGE_LAYOUT_NAME);
            system(command);
        }
    }
    pclose(fp);
}

CGEventRef event_handler(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if (type == kCGEventKeyDown) {
        int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

        if (keycode == FN_KEY_CODE) {
            switch_input_source();
            return NULL;         
        }
    }
    return event;
}

int main() {
    CGEventMask eventMask = CGEventMaskBit(kCGEventKeyDown);
    CFMachPortRef eventTap = CGEventTapCreate(kCGSessionEventTap,
                                              kCGTailAppendEventTap,
                                              kCGEventTapOptionDefault,
                                              eventMask,
                                              event_handler,
                                              NULL);

    if (!eventTap) {
        fprintf(stderr, "Failed to create event tap\n");
        exit(1);
    }

    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);

    CFRunLoopRun();

    return 0;
}
