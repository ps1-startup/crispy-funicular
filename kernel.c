#include <stdint.h>
#include <stdbool.h>

#define VGA_WIDTH 320
#define VGA_HEIGHT 200
#define VGA_MEMORY ((uint8_t*)0xA0000)

enum {
    COLOR_BLACK = 0,
    COLOR_WHITE = 15,
    COLOR_DARK_GRAY = 8,
    COLOR_LIGHT_GRAY = 7,
    COLOR_BLUE_BG = 1,
    COLOR_TASKBAR = 8,
    COLOR_WINDOW_BORDER = 7,
    COLOR_WINDOW_TITLE = 9,
    COLOR_WINDOW_BODY = 7,
    COLOR_WINDOW_SHADOW = 8,
    COLOR_CURSOR = 15,
    COLOR_BUTTON_RED = 12,
    COLOR_BUTTON_YELLOW = 14,
    COLOR_BUTTON_GREEN = 10
};

static inline void outb(uint16_t port, uint8_t value) {
    __asm__ volatile ("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static void io_wait(void) {
    outb(0x80, 0);
}

static void put_pixel(int x, int y, uint8_t color) {
    if (x < 0 || x >= VGA_WIDTH || y < 0 || y >= VGA_HEIGHT) return;
    VGA_MEMORY[y * VGA_WIDTH + x] = color;
}

static void fill_rect(int x, int y, int w, int h, uint8_t color) {
    for (int yy = 0; yy < h; yy++) {
        int py = y + yy;
        if (py < 0 || py >= VGA_HEIGHT) continue;
        for (int xx = 0; xx < w; xx++) {
            int px = x + xx;
            if (px < 0 || px >= VGA_WIDTH) continue;
            VGA_MEMORY[py * VGA_WIDTH + px] = color;
        }
    }
}

static void draw_rect_outline(int x, int y, int w, int h, uint8_t color) {
    for (int i = 0; i < w; i++) {
        put_pixel(x + i, y, color);
        put_pixel(x + i, y + h - 1, color);
    }
    for (int i = 0; i < h; i++) {
        put_pixel(x, y + i, color);
        put_pixel(x + w - 1, y + i, color);
    }
}

static void draw_window(int x, int y, int w, int h, uint8_t title_color) {
    fill_rect(x + 3, y + 3, w, h, COLOR_WINDOW_SHADOW);
    fill_rect(x, y, w, h, COLOR_WINDOW_BODY);
    draw_rect_outline(x, y, w, h, COLOR_WINDOW_BORDER);

    for (int yy = 0; yy < 16; yy++) {
        uint8_t grad = (uint8_t)(title_color + (yy > 7 ? 1 : 0));
        fill_rect(x + 1, y + 1 + yy, w - 2, 1, grad);
    }

    int btn_y = y + 4;
    fill_rect(x + w - 34, btn_y, 8, 8, COLOR_BUTTON_GREEN);
    fill_rect(x + w - 22, btn_y, 8, 8, COLOR_BUTTON_YELLOW);
    fill_rect(x + w - 10, btn_y, 8, 8, COLOR_BUTTON_RED);
}

static void draw_scene(void) {
    fill_rect(0, 0, VGA_WIDTH, VGA_HEIGHT, COLOR_BLUE_BG);
    fill_rect(0, VGA_HEIGHT - 24, VGA_WIDTH, 24, COLOR_TASKBAR);
    fill_rect(8, VGA_HEIGHT - 20, 40, 16, COLOR_LIGHT_GRAY);
    draw_rect_outline(8, VGA_HEIGHT - 20, 40, 16, COLOR_WHITE);

    draw_window(34, 28, 120, 90, COLOR_WINDOW_TITLE);
    draw_window(120, 54, 150, 100, COLOR_WINDOW_TITLE);
}

typedef struct {
    int x;
    int y;
    uint8_t under[16 * 16];
    bool visible;
} Cursor;

static Cursor cursor = {160, 100, {0}, false};

static const uint16_t cursor_shape[16] = {
    0b1000000000000000,
    0b1100000000000000,
    0b1110000000000000,
    0b1111000000000000,
    0b1111100000000000,
    0b1111110000000000,
    0b1111111000000000,
    0b1111111100000000,
    0b1111111110000000,
    0b1111111100000000,
    0b1110111000000000,
    0b1100011000000000,
    0b1000001100000000,
    0b0000000110000000,
    0b0000000011000000,
    0b0000000000000000,
};

static void cursor_save_under(void) {
    for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
            int px = cursor.x + x;
            int py = cursor.y + y;
            uint8_t c = COLOR_BLACK;
            if (px >= 0 && px < VGA_WIDTH && py >= 0 && py < VGA_HEIGHT) {
                c = VGA_MEMORY[py * VGA_WIDTH + px];
            }
            cursor.under[y * 16 + x] = c;
        }
    }
}

static void cursor_restore_under(void) {
    for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
            int px = cursor.x + x;
            int py = cursor.y + y;
            if (px >= 0 && px < VGA_WIDTH && py >= 0 && py < VGA_HEIGHT) {
                VGA_MEMORY[py * VGA_WIDTH + px] = cursor.under[y * 16 + x];
            }
        }
    }
}

static void cursor_draw(void) {
    cursor_save_under();
    for (int y = 0; y < 16; y++) {
        uint16_t row = cursor_shape[y];
        for (int x = 0; x < 16; x++) {
            if (row & (1u << (15 - x))) {
                put_pixel(cursor.x + x, cursor.y + y, COLOR_CURSOR);
            }
        }
    }
    cursor.visible = true;
}

static void cursor_move(int dx, int dy) {
    if (cursor.visible) cursor_restore_under();
    cursor.x += dx;
    cursor.y -= dy;
    if (cursor.x < 0) cursor.x = 0;
    if (cursor.y < 0) cursor.y = 0;
    if (cursor.x > VGA_WIDTH - 16) cursor.x = VGA_WIDTH - 16;
    if (cursor.y > VGA_HEIGHT - 16) cursor.y = VGA_HEIGHT - 16;
    cursor_draw();
}

static bool mouse_wait_in(void) {
    for (int i = 0; i < 100000; i++) {
        if (inb(0x64) & 1) return true;
    }
    return false;
}

static bool mouse_wait_out(void) {
    for (int i = 0; i < 100000; i++) {
        if (!(inb(0x64) & 2)) return true;
    }
    return false;
}

static void mouse_write(uint8_t value) {
    mouse_wait_out();
    outb(0x64, 0xD4);
    mouse_wait_out();
    outb(0x60, value);
}

static uint8_t mouse_read(void) {
    mouse_wait_in();
    return inb(0x60);
}

static void mouse_init(void) {
    mouse_wait_out();
    outb(0x64, 0xA8);

    mouse_wait_out();
    outb(0x64, 0x20);
    mouse_wait_in();
    uint8_t status = inb(0x60);
    status |= 0x02;

    mouse_wait_out();
    outb(0x64, 0x60);
    mouse_wait_out();
    outb(0x60, status);

    mouse_write(0xF6);
    (void)mouse_read();
    mouse_write(0xF4);
    (void)mouse_read();
}

void kmain(void) {
    draw_scene();
    mouse_init();
    cursor_draw();

    uint8_t packet[3];
    int index = 0;

    for (;;) {
        uint8_t status = inb(0x64);
        if (!(status & 1) || !(status & 0x20)) continue;

        uint8_t data = inb(0x60);
        if (index == 0 && !(data & 0x08)) continue;

        packet[index++] = data;
        if (index < 3) continue;
        index = 0;

        int dx = (int8_t)packet[1];
        int dy = (int8_t)packet[2];
        cursor_move(dx, dy);
    }
}
