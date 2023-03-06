// ********************************************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

//! General utility code for front end

const std = @import("std");
const chess = @import("../hellochess.zig");
const zcon = @import("zcon");

const Frontend = @This();

/// stores user's input
input_buffer: [64]u8 = undefined,
/// characters in input_buffer
input_size: usize = 0,
/// status line for user feedback
status: []const u8,
/// big boi chess board
board: chess.Board,
/// whose turn it is
turn_affiliation: chess.Piece.Affiliation,

/// a new frontend
pub fn init() Frontend {
    return .{
        .status = "#wht Let's play some chess!",
        .board = chess.Board.init(),
        .turn_affiliation = .white,
    };
}

/// prompts the user for input, makes moves, and handles commands
/// returns true when exit is requested
pub fn prompt(this: *Frontend, writer: *zcon.Writer) !bool {
    writer.clearLine();
    writer.fmt(" > {s}: ", .{Frontend.promptText(this.turn_affiliation)});
    writer.flush();

    const input = try this.readInput();

    if (isCommand(input)) {
        const should_break = this.doCommands(input);
        if (should_break) return true;
    } else {
        const result = this.board.submit_move(this.turn_affiliation, input);
        this.status = this.statusFromMoveResult(result, input);
        if (Frontend.wasSuccessfulMove(result)) {
            this.turn_affiliation = this.turn_affiliation.opponent();
        }
    }

    return false;
}

/// reads input from stdin
pub fn readInput(this: *Frontend) ![]const u8 {
    const count = try std.io.getStdIn().read(&this.input_buffer) - 2;
    this.input_size = count;
    return this.input_buffer[0..count];
}

/// returns the previous input
pub fn getLastInput(this: *Frontend) []const u8 {
    return this.input_buffer[0..this.input_size];
}

/// returns prompt text for given affiliation
pub fn promptText(turn_affiliation: chess.Piece.Affiliation) []const u8 {
    return switch (turn_affiliation) {
        .white => "#cyn white to move #def",
        .black => "#yel black to move #def",
    };
}

/// determines if input is a / command
pub fn isCommand(input: []const u8) bool {
    return input.len > 1 and input[0] == '/';
}

/// handle / commands
pub fn doCommands(this: *Frontend, input: []const u8) bool {
    if (std.mem.eql(u8, input, "/exit")) {
        return true;
    } else if (std.mem.eql(u8, input, "/reset")) {
        this.board = chess.Board.init();
        this.turn_affiliation = .white;
        this.status = "yes sir";
    } else if (std.mem.eql(u8, input, "/clear")) {
        this.board = chess.Board.init_empty();
        this.turn_affiliation = .white;
        this.status = "gotcha";
    } else if (std.mem.eql(u8, input, "/help")) {
        this.status = "#wht '/exit'  '/help [CMD]'  '/reset'  '/clear'";
    } else if (input.len > 5 and std.mem.eql(u8, input[1..5], "help")) {
        var cmd = input[6..];

        // trim whitespace
        while (cmd.len > 0 and cmd[0] == ' ')
            cmd = cmd[1..];
        while (cmd.len > 0 and cmd[cmd.len - 1] == ' ')
            cmd = cmd[0 .. cmd.len - 2];

        this.status = Frontend.statusForCmdHelp(cmd);
    } else this.status = "#red Unrecognized command #def";

    return false;
}

/// return help text for a specific / command
fn statusForCmdHelp(cmd: []const u8) []const u8 {
    if (std.mem.eql(u8, cmd, "exit")) {
        return "quits the game, no saving";
    } else if (std.mem.eql(u8, cmd, "reset")) {
        return "reset the board for a new game";
    } else if (std.mem.eql(u8, cmd, "help")) {
        return "print a list of available commands, or info on a specific command";
    } else if (std.mem.eql(u8, cmd, "clear")) {
        return "clear all pieces from the board";
    }

    return "#red no such command";
}

fn statusFromMoveResult(this: Frontend, move_result: chess.MoveResult, input: []const u8) []const u8 {
    return switch (move_result) {
        .ok => "#grn ok",
        .ok_check => "#grn check!",
        .ok_mate => this.winStatus(),
        .ok_stalemate => "#wht draw",
        .ok_repitition => "#wht draw",
        .ok_insufficient_material => "#wht draw",
        .bad_notation => Frontend.badNotationStatus(input),
        .bad_disambiguation => "#red no such piece on specified rank or file",
        .ambiguous_piece => "#red ambiguous move",
        .no_such_piece => "#red no such piece",
        .no_visibility => "#red that piece can't move there",
        .in_check => "#red you are in check",
        .enters_check => "#red you cannot put yourself in check",
        .blocked => "#red there is a piece in your way",
    };
}

fn badNotationStatus(input: []const u8) []const u8 {
    if (std.mem.eql(u8, input, "exit") or
        std.mem.eql(u8, input, "reset") or
        std.mem.eql(u8, input, "help"))
    {
        return "#red did you forget a slash?";
    }

    return "#red this does not look like a chess move";
}

fn winStatus(this: Frontend) []const u8 {
    return if (this.turn_affiliation == .white)
        "#grn checkmate! white wins!"
    else
        "#grn checkmate! black wins!";
}

fn wasSuccessfulMove(move_result: chess.MoveResult) bool {
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
