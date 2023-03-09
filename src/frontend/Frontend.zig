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

const PlayMode = enum {
    pass_and_play,
    ai_opponent,
    network_multiplayer,
};

/// stores user's input
input_buffer: [64]u8 = undefined,
/// characters in input_buffer
input_size: usize = 0,
/// status line for user feedback
status: []const u8,
/// big boi chess board
board: chess.Board,
/// piece color of client player
player_affiliation: chess.Piece.Affiliation,
/// whose turn is it anyway
turn_affiliation: chess.Piece.Affiliation,
/// I just like havin a doc comment on evry field ok
play_mode: PlayMode,
/// whether client has access to dev commands
dev_commands: bool,

// TODO: fields for network connection

/// a new frontend
pub fn init(dev_commands: bool, play_mode: PlayMode, player_affiliation: chess.Piece.Affiliation) Frontend {
    return .{
        .status = "#wht Let's play some chess!",
        .board = chess.Board.init(),
        .turn_affiliation = .white,
        .player_affiliation = player_affiliation,
        .play_mode = play_mode,
        .dev_commands = dev_commands,
    };
}

/// init a new pass and play frontend
pub fn passAndPlay(dev_commands: bool) Frontend {
    return Frontend.init(dev_commands, .pass_and_play, .white);
}

/// requests and makes next move
/// returns true when exit is requested
pub fn doTurn(this: *Frontend, writer: *zcon.Writer) !bool {
    return switch (this.play_mode) {
        .pass_and_play => try this.runPassAndPlay(writer),
        .ai_opponent => unreachable, // TODO: implement
        .network_multiplayer => unreachable, // TODO: implement
    };
}

/// turn logic for pass and play mode, returns true if exit is requested
pub fn runPassAndPlay(this: *Frontend, writer: *zcon.Writer) !bool {
    const move = try this.clientMove(writer);

    if (std.mem.eql(u8, move, "/exit"))
        return true;
    if (move.len > 0 and move[0] == '/')
        return false;

    _ = this.tryMove(move);
    return false;
}

/// try to make move, swap turn and return true if successful
pub fn tryMove(this: *Frontend, move: []const u8) bool {
    const result = this.board.submitMove(this.turn_affiliation, move);
    this.status = this.statusFromMoveResult(result, move);
    const success = Frontend.wasSuccessfulMove(result);
    if (success) {
        this.turn_affiliation = this.turn_affiliation.opponent();
    }
    return success;
}

/// prompts client player for input, makes moves, and handles commands
/// returns true when exit is requested
pub fn clientMove(this: *Frontend, writer: *zcon.Writer) ![]const u8 {
    writer.clearLine();
    writer.fmt(" > {s}: ", .{Frontend.promptText(this.turn_affiliation)});
    writer.flush();

    const input = try this.readInput();

    if (isCommand(input)) {
        const should_break = this.doCommands(input);
        if (should_break) return "/exit";
    }

    return input;
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

    const help_line = "#wht /exit  /help  /reset";
    const help_dev_commands = "#wht /exit  /help  /pass  /reset  /clear  /spawn";

    this.status = "#red Unrecognized command";
    if (std.mem.eql(u8, command, "/exit")) {
        return true;
    } else if (std.mem.eql(u8, command, "/reset")) {
        this.board = chess.Board.init();
        this.turn_affiliation = .white;
        this.status = "yes sir";
        return false;
    } else if (std.mem.eql(u8, command, "/help")) {
        const arg = arg_iter.next() orelse {
            this.status = if (this.dev_commands) help_dev_commands else help_line;
            return false;
        };
        this.status = Frontend.statusForCmdHelp(arg, this.dev_commands);
        return false;
    }

    // -- dev commands
    if (!this.dev_commands) {
        return false;
    }

    if (std.mem.eql(u8, command, "/clear")) {
        this.board = chess.Board.initEmpty();
        this.turn_affiliation = .white;
        this.status = "gotcha";
    } else if (std.mem.eql(u8, command, "/spawn")) {
        const arg = arg_iter.next() orelse {
            this.status = "#red expected argument #dgry(ex. Qd4)";
            return false;
        };
        if (this.spawnPiece(arg)) |result|
            this.status = this.statusFromMoveResult(result, "")
        else
            this.status = "#red invalid placement expression, must match '[RNBQK]?[a-h][1-8]'";
    } else if (std.mem.eql(u8, command, "/pass")) {
        this.turn_affiliation = this.turn_affiliation.opponent();
        this.status = "okie-doki";
    } else this.status = "#red Unrecognized command";

    return false;
}

/// return help text for a specific / command
fn statusForCmdHelp(cmd: []const u8, include_dev_commands: bool) []const u8 {
    if (std.mem.eql(u8, cmd, "exit")) {
        return "quits the game, no saving";
    } else if (std.mem.eql(u8, cmd, "reset")) {
        return "reset the board for a new game";
    } else if (std.mem.eql(u8, cmd, "help")) {
        return "args: [CMD] ; print a list of available commands, or info on a specific command [CMD]";
    }

    if (!include_dev_commands)
        return "#red no such command";

    if (std.mem.eql(u8, cmd, "clear")) {
        return "clear all pieces from the board exept kings";
    } else if (std.mem.eql(u8, cmd, "spawn")) {
        return "args: <EX> ; spawns piece for current affiliation at given coord, eg. Rh8 or e3";
    } else if (std.mem.eql(u8, cmd, "pass")) {
        return "passes current turn without making a move";
    }

    return "#red no such command";
}

fn statusFromMoveResult(this: Frontend, move_result: chess.MoveResult, input: []const u8) []const u8 {
    return switch (move_result) {
        .ok => "#grn ok",
        .ok_en_passant => "#grn En Passant!",
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
        .castle_in_check => "#red cannot castle out of check",
        .castle_through_check => "#red cannot castle through check",
        .castle_king_moved => "#red you have already moved your king",
        .castle_rook_moved => "#red that rook has already moved",
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
        .ok,
        .ok_en_passant,
        .ok_check,
        .ok_mate,
        .ok_stalemate,
        .ok_repitition,
        .ok_insufficient_material,
        => true,

        .castle_in_check,
        .castle_through_check,
        .castle_king_moved,
        .castle_rook_moved,
        .bad_notation,
        .bad_disambiguation,
        .ambiguous_piece,
        .no_such_piece,
        .no_visibility,
        .in_check,
        .enters_check,
        .blocked,
        => return false,
    };
}

fn spawnPiece(this: *Frontend, expr: []const u8) ?chess.MoveResult {
    if (expr.len == 0) return null;
    var i: usize = 0;
    const class: chess.Piece.Class = switch (expr[i]) {
        'N' => .knight,
        'B' => .bishop,
        'R' => .rook,
        'Q' => .queen,
        'K' => .king,
        'a'...'h', '1'...'8' => .pawn,
        else => return null,
    };
    if (class != .pawn)
        i += 1;
    if (expr.len != i + 2)
        return null;
    if (!chess.Coordinate.isFile(expr[i])) return null;
    if (!chess.Coordinate.isRank(expr[i + 1])) return null;
    const coord = chess.Coordinate.fromString(expr[i .. i + 2]);
    const result = this.board.spawn(chess.Piece.init(class, this.turn_affiliation), coord);
    if (wasSuccessfulMove(result))
        this.turn_affiliation = this.turn_affiliation.opponent();
    return result;
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
