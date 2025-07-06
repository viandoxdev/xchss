// Structs can be defined here for gdb
#include <stddef.h>
#include <stdint.h>

struct draw_board_features_flags {
    unsigned int draw_selected_square : 1;
    unsigned int draw_target_square : 1;
    unsigned int draw_moves_squares : 1;
    unsigned int draw_captures_squares : 1;
    unsigned int flip_board : 1;
};

struct draw_board_stack_arguments {
    uint8_t selected_file;
    uint8_t selected_rank;
    uint8_t target_file;
    uint8_t target_rank;
    uint8_t moves_count;
    uint8_t captures_count;
    uint8_t padding[2];
    uint64_t moves_array;
    uint64_t captures_array;
};

struct square_position {
    uint8_t file;
    uint8_t rank;
};

__attribute__((used)) static struct draw_board_features_flags __keep_1;
__attribute__((used)) static struct draw_board_stack_arguments __keep_2;
__attribute__((used)) static struct square_position __keep_3;
