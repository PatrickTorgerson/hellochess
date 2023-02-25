// ********************************************************************************
//! https://github.com/PatrickTorgerson/hellochess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

//! Here is the logic and main loop for the inline front end
//! This is the default front end that renders in the same buffer
//! as the calling command line

const std = @import("std");
const chess = @import("hellochess.zig");
const zcon = @import("zcon");

/// characters high the rendering area is
const render_height = 20;
/// characters wide the rendering area is
const render_width = 64;

const file_line = "#dgry   a b c d e f g h \n";

/// stores user's input
var input_buffer: [render_width]u8 = undefined;
var input_size: usize = 0;
/// status line for user feedback
var status: []const u8 = "#wht Let's play some chess!";

var board = chess.Board.init();
var turn_affiliation = chess.Piece.Affiliation.white;
var prompt: []const u8 = "#cyn white to move #def";

pub fn entry_point() !void {
    prime_buffer();
    zcon.save_cursor();

    while (true) {
        zcon.restore_cursor();
        try render_board();

        // status line
        zcon.clear_line();
        zcon.print(" {s}: {s}\n\n", .{ input_buffer[0..input_size], status });
        zcon.set_color(.default);

        // prompt
        zcon.clear_line();
        zcon.print(" > {s}: ", .{prompt});

        const input = try read_input();

        if (is_command(input)) {
            const should_break = do_commands(input);
            if (should_break) break;
        } else {
            const result = board.submit_move(turn_affiliation, input);
            status = status_from_move_result(result, input);

            if (was_successful_move(result)) {
                // whose turn is it anyway?
                turn_affiliation = if (turn_affiliation == .white)
                    .black
                else
                    .white;

                prompt = if (turn_affiliation == .white)
                    "#cyn white to move #def"
                else
                    "#yel black to move #def";
            }
        }
    }
}

/// write spaces to the area we will be rendering to
/// this is important to keep the board rendering in place
/// (without scrolling) on smaller buffers
fn prime_buffer() void {
    var i: i32 = 0;
    while (i < render_height) : (i += 1)
        zcon.print("{s: <[w]}\n", .{ .s = " ", .w = render_width });
    zcon.set_cursor_x(1);
    zcon.cursor_up(render_height);
}

/// writes the chess board to the buffer
fn render_board() !void {
    zcon.write(file_line);
    var pos = chess.Coordinate.init(0, 7); // a8
    while (pos.rank >= 0) : (pos.rank -= 1) {
        zcon.print("#dgry {} ", .{pos.rank + 1});
        while (pos.file < 8) : (pos.file += 1) {
            if (board.at(pos)) |piece| {
                const piece_col = if (piece.affiliation() == .white)
                    "#cyn"
                else
                    "#yel";
                zcon.print("{s}{u} ", .{ piece_col, piece.character() });
            } else zcon.write("#dgry . ");
        }
        zcon.print("#dgry {}\n", .{pos.rank + 1});
        pos.file = 0;
    }
    zcon.write(file_line);
    zcon.write("\n");
    zcon.set_color(.default);
}

/// read input from user
fn read_input() ![]const u8 {
    const count = try std.io.getStdIn().read(&input_buffer) - 2;
    input_size = count;
    return input_buffer[0..count];
}

/// determines if input is a / command
fn is_command(input: []const u8) bool {
    return input.len > 1 and input[0] == '/';
}

/// handle / commands
fn do_commands(input: []const u8) bool {
    if (std.mem.eql(u8, input, "/exit")) {
        return true;
    } else if (std.mem.eql(u8, input, "/reset")) {
        board = chess.Board.init();
        turn_affiliation = .white;
        status = "yes sir";
    } else if (std.mem.eql(u8, input, "/help")) {
        status = "#wht '/exit'  '/help [CMD]'  '/reset'";
    } else if (input.len > 5 and std.mem.eql(u8, input[1..5], "help")) {
        var cmd = input[6..];

        // trim whitespace
        while (cmd.len > 0 and cmd[0] == ' ')
            cmd = cmd[1..];
        while (cmd.len > 0 and cmd[cmd.len - 1] == ' ')
            cmd = cmd[0 .. cmd.len - 2];

        status = status_for_cmd_help(cmd);
    } else status = "#red Unrecognized command #def";

    return false;
}

/// return help text for a specific / command
fn status_for_cmd_help(cmd: []const u8) []const u8 {
    if (std.mem.eql(u8, cmd, "exit")) {
        return "quits the game, no saving";
    } else if (std.mem.eql(u8, cmd, "reset")) {
        return "reset the board for a new game";
    } else if (std.mem.eql(u8, cmd, "help")) {
        return "print a list of available commands, or info on a specific command";
    }

    return "#red no such command";
}

fn status_from_move_result(move_result: chess.MoveResult, input: []const u8) []const u8 {
    return switch (move_result) {
        .ok => "#grn ok",
        .ok_check => "#grn check!",
        .ok_mate => win_status(),
        .ok_stalemate => "#wht draw",
        .ok_repitition => "#wht draw",
        .ok_insufficient_material => "#wht draw",
        .bad_notation => bad_notation_status(input),
        .bad_disambiguation => "#red no such piece on specified rank or file",
        .ambiguous_piece => "#red ambiguous move",
        .no_such_piece => "#red no such piece",
        .no_visibility => "#red that pice can't move there",
        .in_check => "#red you are in check",
        .enters_check => "#red you cannot put yourself in check",
        .blocked => "#red there is a piece in your way",
    };
}

fn bad_notation_status(input: []const u8) []const u8 {
    if (std.mem.eql(u8, input, "exit") or
        std.mem.eql(u8, input, "reset") or
        std.mem.eql(u8, input, "help"))
    {
        return "#red did you forget a slash?";
    }

    return "#red this does not look like a chess move";
}

fn win_status() []const u8 {
    return if (turn_affiliation == .white)
        "#grn checkmate! white wins!"
    else
        "#grn checkmate! black wins!";
}

fn was_successful_move(move_result: chess.MoveResult) bool {
    return switch (move_result) {
        .ok => true,
        .ok_check => true,
        .ok_mate => true,
        .ok_stalemate => true,
        .ok_repitition => true,
        .ok_insufficient_material => true,
        .bad_notation => false,
        .bad_disambiguation => false,
        .ambiguous_piece => false,
        .no_such_piece => false,
        .no_visibility => false,
        .in_check => false,
        .enters_check => false,
        .blocked => false,
    };
}
