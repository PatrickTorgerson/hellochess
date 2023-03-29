// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

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

const WinState = enum {
    ongoing,
    white,
    black,
    draw,
};

const Command = struct {
    dev: bool = false,
    impl: *const fn (*Frontend, *ArgIterator) []const u8,
    help: []const u8,
};

const commands = std.ComptimeStringMap(Command, .{
    .{ "/exit", .{
        .impl = cmdExit,
        .help = "quits the game, no saving",
    } },
    .{ "/help", .{
        .impl = cmdHelp,
        .help = "args: [CMD] ; print a list of available commands, or info on a specific command [CMD]",
    } },
    .{ "/reset", .{
        .impl = cmdReset,
        .help = "reset the board for a new game",
    } },
    .{ "/resign", .{
        .impl = cmdResign,
        .help = "resign the game, resulting in a victory for your opponent",
    } },
    .{ "/draw", .{
        .impl = cmdDraw,
        .help = "offer a draw to your opponent",
    } },
    .{ "/flip", .{
        .impl = cmdFlip,
        .help = "flip the board perspective",
    } },

    .{ "/clear", .{
        .impl = cmdClear,
        .help = "clear all pieces from the board exept kings",
        .dev = true,
    } },
    .{ "/pass", .{
        .impl = cmdPass,
        .help = "passes current turn without making a move",
        .dev = true,
    } },
    .{ "/spawn", .{
        .impl = cmdSpawn,
        .help = "args: <EX> ; spawns piece for current affiliation at given coord, eg. Rh8 or e3",
        .dev = true,
    } },
});

/// stores user's input
input_buffer: [64]u8 = undefined,
/// characters in input_buffer
input_size: usize = 0,
/// helps stores text for status line
status_buffer: [256]u8 = undefined,
/// status line for user feedback, not necessarily sliced from status_buffer
status: []const u8,
/// big boi chess board
position: chess.Position,
/// piece color of client player
player_affiliation: chess.Affiliation,
/// I just like havin a doc comment on evry field ok
play_mode: PlayMode,
/// whether client has access to dev commands
dev_commands: bool,
/// whether the client has requested an exit
should_exit: bool,
/// who won the game
win_state: WinState = .ongoing,
/// a player offers a draw
draw_offered: ?chess.Affiliation = null,
col_white: zcon.Color = zcon.Color.col16(.white),
col_black: zcon.Color = zcon.Color.col16(.white),

// TODO: fields for network connection

/// a new frontend
pub fn init(dev_commands: bool, play_mode: PlayMode, player_affiliation: chess.Affiliation) Frontend {
    return .{
        .status = "#wht Let's play some chess!",
        .position = chess.Position.init(),
        .player_affiliation = player_affiliation,
        .play_mode = play_mode,
        .dev_commands = dev_commands,
        .should_exit = false,
    };
}

/// init a new pass and play frontend
pub fn passAndPlay(dev_commands: bool) Frontend {
    return Frontend.init(dev_commands, .pass_and_play, .white);
}

/// requests and makes next move
/// returns true when exit is requested
pub fn doTurn(this: *Frontend, writer: *zcon.Writer) !void {
    switch (this.play_mode) {
        .pass_and_play => try this.runPassAndPlay(writer),
        .ai_opponent => unreachable, // TODO: implement
        .network_multiplayer => unreachable, // TODO: implement
    }
}

/// turn logic for pass and play mode, returns true if exit is requested
pub fn runPassAndPlay(this: *Frontend, writer: *zcon.Writer) !void {
    const move = try this.clientMove(writer);
    if (isCommand(move))
        return;
    _ = this.tryMove(move);

    if (this.draw_offered != null and this.draw_offered.? != this.position.side_to_move) {
        this.status = switch (this.draw_offered.?) {
            .white => "white offerd a draw, /draw to accept",
            .black => "black offerd a draw, /draw to accept",
        };
    }
}

/// try to make move, swap turn and return true if successful
pub fn tryMove(this: *Frontend, move: []const u8) bool {
    const result = this.position.submitMove(move);
    this.status = this.statusFromMoveResult(result, move);
    const success = Frontend.wasSuccessfulMove(result);
    return success;
}

/// prompts client player for input, makes moves, and handles commands
pub fn clientMove(this: *Frontend, writer: *zcon.Writer) ![]const u8 {
    writer.clearLine();
    writer.setForeground(this.affiliatedColor());
    writer.fmt(" > {s}: ", .{this.promptText()});
    writer.usePreviousColor();
    writer.flush();

    const input = try this.readInput();

    if (this.win_state != .ongoing) {
        var iter = ArgIterator.init(input);
        if (std.mem.eql(u8, input, "y") or
            std.mem.eql(u8, input, "Y") or
            std.mem.eql(u8, input, "yes") or
            std.mem.eql(u8, input, "Yes"))
            this.status = cmdReset(this, &iter)
        else if (std.mem.eql(u8, input, "n") or
            std.mem.eql(u8, input, "N") or
            std.mem.eql(u8, input, "no") or
            std.mem.eql(u8, input, "No"))
            this.should_exit = true
        else
            this.status = "yes or no";

        return "/";
    }

    if (isCommand(input))
        this.status = this.doCommands(input);

    if (this.draw_offered != null and this.draw_offered.? != this.position.side_to_move) {
        this.draw_offered = null;
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
pub fn promptText(this: Frontend) []const u8 {
    if (this.win_state != .ongoing)
        return "play again? (y,n)"
    else
        return switch (this.position.side_to_move) {
            .white => "white to move",
            .black => "black to move",
        };
}

/// return text color for current side to move
pub fn affiliatedColor(this: Frontend) zcon.Color {
    return switch (this.position.side_to_move) {
        .white => this.col_white,
        .black => this.col_black,
    };
}

/// return an iterator that iterates over files
/// in order to be rendered from left to right
pub fn fileIterator(this: Frontend) chess.util.EnumIterator(chess.File) {
    return switch (this.player_affiliation) {
        .white => chess.File.file_a.iterator(),
        .black => chess.File.file_h.reverseIterator(),
    };
}

/// return an iterator that iterates over ranks
/// in order to be rendered from top to bottom
pub fn rankIterator(this: Frontend) chess.util.EnumIterator(chess.Rank) {
    return switch (this.player_affiliation) {
        .white => chess.Rank.rank_8.reverseIterator(),
        .black => chess.Rank.rank_1.iterator(),
    };
}

/// determines if input is a / command
pub fn isCommand(input: []const u8) bool {
    return input.len >= 1 and input[0] == '/';
}

/// handle / commands, returns status text
pub fn doCommands(this: *Frontend, input: []const u8) []const u8 {
    var arg_iter = ArgIterator.init(input);
    const arg1 = arg_iter.next() orelse "";

    if (commands.get(arg1)) |cmd| {
        if (cmd.dev and !this.dev_commands) return "#red you cannot use dev commands";
        return cmd.impl(this, &arg_iter);
    } else return "#red no such command";
}

fn cmdExit(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.should_exit = true;
    return "farwell friend";
}

fn cmdHelp(this: *Frontend, args: *ArgIterator) []const u8 {
    const arg = args.next() orelse
        return this.commandListStatus();
    this.status_buffer[0] = '/';
    std.mem.copy(u8, this.status_buffer[1 .. 1 + arg.len], arg);
    if (commands.get(this.status_buffer[0 .. 1 + arg.len])) |cmd| {
        return cmd.help;
    } else return "#red no such command";
}

fn cmdReset(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.position = chess.Position.init();
    this.win_state = .ongoing;
    this.draw_offered = null;
    return this.confirmationStatus();
}

fn cmdClear(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.position = chess.Position.initEmpty();
    this.win_state = .ongoing;
    this.draw_offered = null;
    return this.confirmationStatus();
}

fn cmdPass(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.position.side_to_move = this.position.side_to_move.opponent();
    return this.confirmationStatus();
}

fn cmdSpawn(this: *Frontend, args: *ArgIterator) []const u8 {
    const arg = args.next() orelse
        return "#red expected argument #dgry(ex. Qd4)";
    if (this.spawnPiece(arg)) |result|
        return this.statusFromMoveResult(result, "")
    else
        return "#red invalid placement expression, must match '[RNBQK]?[a-h][1-8]'";
}

fn cmdDraw(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    if (this.draw_offered == null) {
        this.draw_offered = this.position.side_to_move;
        return "make a move, your opponent can accept your offer on their turn";
    } else if (this.draw_offered != this.position.side_to_move) {
        this.win_state = .draw;
        return "#byel draw by agreement";
    }
    return "yeah yeah, just make a move";
}

fn cmdFlip(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.player_affiliation = this.player_affiliation.opponent();
    return this.confirmationStatus();
}

fn cmdResign(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.win_state = switch (this.position.side_to_move.opponent()) {
        .white => .white,
        .black => .black,
    };
    return if (this.position.side_to_move == .white)
        "#grn white resigns! black wins!"
    else
        "#grn black resigns! white wins!";
}

/// return list of commands, overwrite status_buffer
fn commandListStatus(this: *Frontend) []const u8 {
    var stream = std.io.fixedBufferStream(&this.status_buffer);
    var writer = stream.writer();
    for (commands.kvs[0..]) |kv| {
        if (kv.value.dev and !this.dev_commands) continue;
        writer.writeAll(kv.key) catch {};
        writer.writeAll("  ") catch {};
    }
    return this.status_buffer[0..stream.pos];
}

/// return random confirmation status message
fn confirmationStatus(this: *Frontend) []const u8 {
    _ = this;
    const seed = @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()));
    var rand = std.rand.DefaultPrng.init(seed);
    const responses = [_][]const u8{
        "gotcha",
        "okie-doki",
        "no doubt",
        "yes sir",
        "cool cool",
        "100%",
        "done",
        "for sure",
        "yes absolutely I will",
        "yeah, yeah",
        "fine",
        "whatever",
        "I knew you would say that",
        "oh really?",
        "interesting...",
        "if you say so",
        "your wish is my /command",
        "woah, totally excellent!",
        "#blu G#red O#yel O#blu D#grn !",
        "again?",
        "#dgry hmmm...",
        "#byel :P",
        "okay",
        "about time",
        "Obla-di, Obla-da",
        "life goes on",
        "what next?",
        "I guess so",
        "it's pretty late...",
        "living on the edge, huh?",
        "alrighty then",
        "BOOONE!?!",
        "I've heard it both ways",
        "you dirty cheat",
        "geese of a feather",
        "ok",
        "lemme see",
        "look at that",
        "there it is",
        "sure",
        "#bgrn CONFIRMATION!",
        "look at you go",
        "I just adore you",
        "I wish that I knew...",
        "what makes you think I'm so speacial?",
        " O.O ",
        "right",
        "y'all come back now, ya hear?",
        "are you still there?",
        "fantastic",
        "knights move like an L",
        "got em",
        "can you just win already?",
        "so needy...",
        "maybe just relax",
        "how many of theese are there anyway?",
        "$20 if you leave right now",
    };
    const at = rand.random().uintAtMost(usize, responses.len - 1);
    return responses[at];
}

fn statusFromMoveResult(this: *Frontend, move_result: chess.Move.Result, input: []const u8) []const u8 {
    return switch (move_result) {
        .ok => this.confirmationStatus(),
        .ok_en_passant => "#bgrn En Passant!",
        .ok_check => "#bgrn check!",
        .ok_mate => this.winStatus(),
        .ok_stalemate => "#wht draw",
        .ok_repitition => "#wht draw",
        .ok_insufficient_material => "#wht draw",
        .bad_notation => this.badNotationStatus(input),
        .bad_disambiguation => "#bred no such piece on specified rank or file",
        .ambiguous_piece => "#bred ambiguous move",
        .no_such_piece => "#bred no such piece",
        .no_visibility => "#bred that piece can't move there",
        .in_check => "#bred you are in check",
        .enters_check => "#bred you cannot put yourself in check",
        .blocked => "#bred there is a piece in your way",
        .bad_castle_in_check => "#bred cannot castle out of check",
        .bad_castle_through_check => "#bred cannot castle through check",
        .bad_castle_king_or_rook_moved => "#bred you have already moved your king or rook",
    };
}

fn badNotationStatus(this: *Frontend, input: []const u8) []const u8 {
    var arg_iter = ArgIterator.init(input);
    const arg = arg_iter.next() orelse "";

    this.status_buffer[0] = '/';
    std.mem.copy(u8, this.status_buffer[1 .. 1 + arg.len], arg);

    if (commands.get(this.status_buffer[0 .. 1 + arg.len])) |_| {
        return "#red did you forget a slash?";
    } else return "#red this does not look like a chess move";
}

fn winStatus(this: *Frontend) []const u8 {
    this.position.side_to_move = this.position.side_to_move.opponent();
    this.win_state = switch (this.position.side_to_move) {
        .white => .white,
        .black => .black,
    };
    return if (this.position.side_to_move == .white)
        "#grn checkmate! white wins!"
    else
        "#grn checkmate! black wins!";
}

fn wasSuccessfulMove(move_result: chess.Move.Result) bool {
    return switch (move_result) {
        .ok,
        .ok_en_passant,
        .ok_check,
        .ok_mate,
        .ok_stalemate,
        .ok_repitition,
        .ok_insufficient_material,
        => true,

        .bad_castle_in_check,
        .bad_castle_through_check,
        .bad_castle_king_or_rook_moved,
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

fn spawnPiece(this: *Frontend, expr: []const u8) ?chess.Move.Result {
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
    return this.position.spawn(class, coord);
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
