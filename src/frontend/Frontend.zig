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
    return input.len >= 1 and input[0] == '/';
}

/// handle / commands, returns true if exit was requested
pub fn doCommands(this: *Frontend, input: []const u8) bool {
    var arg_iter = ArgIterator.init(input);
    const command = arg_iter.next() orelse "";

    if (std.mem.eql(u8, command, "/exit")) {
        return true;
    } else if (std.mem.eql(u8, command, "/reset")) {
        this.board = chess.Board.init();
        this.turn_affiliation = .white;
        this.status = "yes sir";
    } else if (std.mem.eql(u8, command, "/clear")) {
        this.board = chess.Board.init_empty();
        this.turn_affiliation = .white;
        this.status = "gotcha";
    } else if (std.mem.eql(u8, command, "/spawn-white")) {
        const arg = arg_iter.next() orelse {
            this.status = "#red expected argument #dgry(ex. Ba7)";
            return false;
        };
        if (!this.spawnPiece(.white, arg))
            this.status = arg //"#red invalid placement expression, must match '[RNBQK]?[a-h][1-8]'"
        else
            this.status = "for sure";
    } else if (std.mem.eql(u8, command, "/spawn-black")) {
        const arg = arg_iter.next() orelse {
            this.status = "#red expected argument #dgry(ex. Qd4)";
            return false;
        };
        if (!this.spawnPiece(.black, arg))
            this.status = "#red invalid placement expression, must match '[RNBQK]?[a-h][1-8]'"
        else
            this.status = "no doubt";
    } else if (std.mem.eql(u8, command, "/help")) {
        const arg = arg_iter.next() orelse {
            this.status = "#wht /exit  /help  /pass  /reset  /clear  /spawn-white  /spawn-black";
            return false;
        };
        this.status = Frontend.statusForCmdHelp(arg);
    } else if (std.mem.eql(u8, command, "/pass")) {
        this.turn_affiliation = this.turn_affiliation.opponent();
        this.status = "okie-doki";
    } else this.status = "#red Unrecognized command";

    return false;
}

/// return help text for a specific / command
fn statusForCmdHelp(cmd: []const u8) []const u8 {
    if (std.mem.eql(u8, cmd, "exit")) {
        return "quits the game, no saving";
    } else if (std.mem.eql(u8, cmd, "reset")) {
        return "reset the board for a new game";
    } else if (std.mem.eql(u8, cmd, "help")) {
        return "args: [CMD] ; print a list of available commands, or info on a specific command [CMD]";
    } else if (std.mem.eql(u8, cmd, "clear")) {
        return "clear all pieces from the board";
    } else if (std.mem.eql(u8, cmd, "spawn-white")) {
        return "args: <EX> ; spawns piece for white at given coord, eg. Rh8 or e3";
    } else if (std.mem.eql(u8, cmd, "spawn-black")) {
        return "args: <EX> ; spawns piece for black at given coord, eg. Nc2 or b6";
    } else if (std.mem.eql(u8, cmd, "pass")) {
        return "passes current turn without making a move";
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
    var arg_iter = ArgIterator.init(input);
    const command = arg_iter.next() orelse "";

    if (std.mem.eql(u8, command, "exit") or
        std.mem.eql(u8, command, "reset") or
        std.mem.eql(u8, command, "clear") or
        std.mem.eql(u8, command, "pass") or
        std.mem.eql(u8, command, "spawn-white") or
        std.mem.eql(u8, command, "spawn-black") or
        std.mem.eql(u8, command, "help"))
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

fn spawnPiece(this: *Frontend, affiliation: chess.Piece.Affiliation, expr: []const u8) bool {
    if (expr.len == 0) return false;
    var i: usize = 0;
    const class: chess.Piece.Class = switch (expr[i]) {
        'N' => .knight,
        'B' => .bishop,
        'R' => .rook,
        'Q' => .queen,
        'K' => .king,
        'a'...'h', '1'...'8' => .pawn,
        else => return false,
    };
    if (class != .pawn)
        i += 1;
    if (expr.len != i + 2)
        return false;
    const coord = chess.Coordinate.from_string(expr[i .. i + 2]);
    this.board.spawn(chess.Piece.init(class, affiliation), coord);
    return true;
}

const ArgIterator = struct {
    str: []const u8,
    i: usize,

    pub fn init(str: []const u8) ArgIterator {
        return .{
            .str = str,
            .i = 0,
        };
    }

    pub fn next(this: *ArgIterator) ?[]const u8 {
        if (this.str.len == 0) return null;
        while (this.i < this.str.len and this.str[this.i] == ' ')
            this.i += 1;
        if (this.i >= this.str.len) return null;

        const end_char = if (this.str[this.i] == '\'' or this.str[this.i] == '\"')
            this.str[this.i]
        else
            ' ';
        const at = if (end_char == ' ') this.i else this.i + 1;
        while (this.i < this.str.len and this.str[this.i] != end_char)
            this.i += 1;
        return this.str[at..this.i];
    }
};
