// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//! General utility code for front end

const std = @import("std");
const chess = @import("../hellochess.zig");
const zcon = @import("zcon");
const network = @import("network");

const Frontend = @This();

pub const PlayMode = enum {
    development,
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
    scopes: []const PlayMode = &[_]PlayMode{},
    impl: *const fn (*Frontend, *ArgIterator) []const u8,
    help: []const u8,
};

/// stores user's input
input_buffer: [128]u8 = undefined,
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
/// whether the client has requested an exit
should_exit: bool,
/// who won the game
win_state: WinState = .ongoing,
/// color associated with white pieces
col_white: zcon.Color = zcon.Color.col16(.white),
/// color associated with blac pieces
col_black: zcon.Color = zcon.Color.col16(.white),
/// history of moves played
move_history: [512]chess.Move.Result = undefined,
/// stored tesxt data for moves made
move_slice_buffer: [512 * 4]u8 = undefined,
/// slices into `move_slice_buffer` representinf textual
/// representations of move history
move_slices: [512][]const u8 = undefined,
/// last move played or undone
move_top: usize = 0,
/// number of moves in move_history
move_count: usize = 0,
/// do not wrap status line next print only
no_wrap: bool = false,
// network connection
sock: ?network.Socket = null,

/// a new frontend
pub fn init(play_mode: PlayMode, player_affiliation: chess.Affiliation) Frontend {
    return .{
        .status = "#wht Let's play some chess!",
        .position = chess.Position.init(),
        .player_affiliation = player_affiliation,
        .play_mode = play_mode,
        .should_exit = false,
    };
}

/// a new frontend for network p2p multiplayer
pub fn initNetwork(player_affiliation: chess.Affiliation, sock: network.Socket) Frontend {
    return .{
        .status = "#wht Let's play some chess!",
        .position = chess.Position.init(),
        .player_affiliation = player_affiliation,
        .play_mode = .network_multiplayer,
        .should_exit = false,
        .sock = sock,
    };
}

pub fn deinit(this: *Frontend) void {
    if (this.play_mode == .network_multiplayer)
        this.sock.?.close();
}

/// requests and makes next move
pub fn doTurn(this: *Frontend, writer: *zcon.Writer) !void {
    switch (this.play_mode) {
        .development => try this.runPassAndPlay(writer),
        .pass_and_play => try this.runPassAndPlay(writer),
        .ai_opponent => unreachable, // TODO: implement
        .network_multiplayer => try this.runNetworkMultiplayer(writer),
    }

    if (@import("../hellochess/zobrist.zig").hash(this.position) != this.position.hash)
        @panic("position hash out of sync");
}

/// turn logic for network multiplayer mode
pub fn runNetworkMultiplayer(this: *Frontend, writer: *zcon.Writer) !void {
    if (this.position.side_to_move == this.player_affiliation) {
        const move = try this.clientMove(writer);
        if (move.len == 0)
            return;
        if (isCommand(move))
            return;

        if (this.tryMove(move)) {
            const move_made = this.move_history[this.move_top - 1].move;
            _ = try this.sock.?.send(std.mem.toBytes(move_made)[0..]);
        }
    } else {
        writer.clearLine();
        writer.setForeground(this.affiliatedColor());
        writer.put(" > waiting for opponent ...");
        writer.usePreviousColor();
        writer.flush();

        var data: [@sizeOf(chess.Move)]u8 = undefined;
        const recieved = this.sock.?.receive(data[0..]);
        const move_made = std.mem.bytesToValue(chess.Move, &data);

        // opponent abandoned game
        if (move_made.bits.bits == chess.Move.invalid.bits.bits or std.meta.isError(recieved)) {
            this.should_exit = true;
            writer.clearLine();
            writer.put("\r#indent;opponent abandoned game, you win by resignation\n\npress enter to exit");
            writer.flush();
            this.waitForKey();
            return;
        }

        const prev_meta = this.position.meta;
        this.position.doMove(move_made);
        const result = this.position.checksAndMates();
        this.status = this.statusFromMoveResult(result, "");
        this.addMove(.{
            .move = move_made,
            .prev_meta = prev_meta,
            .tag = result,
        }) catch unreachable;
    }
}

/// turn logic for pass and play mode
pub fn runPassAndPlay(this: *Frontend, writer: *zcon.Writer) !void {
    const move = try this.clientMove(writer);
    if (move.len == 0)
        return;
    if (isCommand(move))
        return;

    _ = this.tryMove(move);
}

/// try to make move, swap turn and return true if successful
pub fn tryMove(this: *Frontend, move: []const u8) bool {
    var result = this.position.submitMove(move);

    if (this.play_mode == .development and result.tag == .ok_insufficient_material)
        result.tag = if (this.position.inCheck(this.position.side_to_move)) .ok_check else .ok;
    this.status = this.statusFromMoveResult(result.tag, move);
    const success = Frontend.wasSuccessfulMove(result.tag);
    if (success)
        this.addMove(result) catch unreachable;
    return success;
}

/// prompts client player for input, makes moves, and handles commands
pub fn clientMove(this: *Frontend, writer: *zcon.Writer) ![]const u8 {
    if (this.win_state != .ongoing) {
        this.should_exit = true;
        writer.clearLine();
        writer.put(" press enter to exit\n");
        writer.flush();
        this.waitForKey();
        return "/";
    }

    writer.clearLine();
    writer.setForeground(this.affiliatedColor());
    writer.fmt(" > {s}: ", .{this.promptText()});
    writer.usePreviousColor();
    writer.flush();

    const input = try this.readInput();

    if (input.len == 0)
        return input;

    if (isCommand(input))
        this.status = this.doCommands(input);

    return input;
}

pub fn waitForKey(this: *Frontend) void {
    _ = this.readInput() catch {};
}

pub fn printStatus(this: *Frontend, writer: *zcon.Writer) void {
    writer.clearLine();

    if (this.no_wrap) {
        this.no_wrap = false;
        writer.fmt("#dgry; {s}#prv;: {s}\n", .{ this.getLastInput(), this.status });
    } else {
        var start: usize = 0;
        var end = std.math.min(this.status.len, status_max_width);

        while (end < this.status.len and this.status[end] != ' ')
            end += 1;

        writer.fmt("#dgry; {s}#prv;: {s}\n", .{ this.getLastInput(), this.status[start..end] });

        start = end;
        while (start < this.status.len) {
            while (start < this.status.len and this.status[start] == ' ')
                start += 1;
            end = start + std.math.min(this.status.len - start, status_max_width);
            while (end < this.status.len and this.status[end] != ' ')
                end += 1;
            writer.clearLine();
            writer.writeByteNTimes(' ', this.getLastInput().len + 3) catch unreachable;
            writer.fmt("{s}\n", .{this.status[start..end]});
            start = end;
        }
    }

    writer.clearLine();
    writer.put("\n");
    writer.useDefaultColors();
}

pub fn printHistory(this: *Frontend, writer: *zcon.Writer, lines: i32) void {
    var start = std.math.min(
        this.move_top -| 1,
        this.move_count -| @intCast(usize, lines * 2) + 1,
    );
    if (start % 2 == 1)
        start -= 1;
    var i = start;

    while (i - start < lines * 2) : (i += 2) {
        writer.put("                          ");
        writer.cursorLeft(26);

        if (i >= this.move_count) {
            writer.cursorDown(1);
            continue;
        }

        const turn = (i / 2) + 1;
        writer.fmt("#dgry;{: >2}.#prv; ", .{turn});

        if (this.move_top > 0 and i == this.move_top - 1)
            writer.setForeground(zcon.Color.col16(.green));

        writer.fmt("{s}", .{this.move_slices[i]});
        writer.useDefaultColors();
        const white_len = @intCast(i16, this.move_slices[i].len + 4);
        if (i + 1 >= this.move_count) {
            writer.cursorDown(1);
            writer.cursorLeft(white_len);
            continue;
        }

        writer.put(" #dgry;..#prv; ");
        if (this.move_top > 0 and i + 1 == this.move_top - 1)
            writer.setForeground(zcon.Color.col16(.green));

        writer.fmt("{s}", .{this.move_slices[i + 1]});
        writer.useDefaultColors();

        writer.cursorDown(1);
        writer.cursorLeft(white_len + @intCast(i16, this.move_slices[i + 1].len + 4));
    }
}

/// reads input from stdin
pub fn readInput(this: *Frontend) ![]const u8 {
    this.input_size = 0;
    const stdin = std.io.getStdIn().reader();
    if (stdin.readUntilDelimiterOrEof(this.input_buffer[0..], '\n') catch |e| switch (e) {
        error.StreamTooLong => {
            while (try stdin.read(this.input_buffer[0..]) == this.input_buffer.len) {}
            this.status = "#bred input too long";
            return "";
        },
        else => return e,
    }) |input| {
        const line = std.mem.trimRight(u8, input[0..], "\r\n ");
        this.input_size = line.len;
        return this.input_buffer[0..this.input_size];
    }
    this.input_size = 0;
    return "";
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

        // determine if this command is in scope
        for (cmd.scopes) |scope| {
            if (scope == this.play_mode) break;
        } else return "#red command is unavailable in this mode";

        return cmd.impl(this, &arg_iter);
    } else return "#red no such command";
}

fn addMove(this: *Frontend, move: chess.Move.Result) !void {
    try this.writeMoveText(move);
    this.move_history[this.move_top] = move;
    this.move_top += 1;
    this.move_count = this.move_top;
}

fn writeMoveText(this: *Frontend, move: chess.Move.Result) !void {
    const castle_king_black = chess.Move.init(chess.Coordinate.e8, chess.Coordinate.g8, .castle).bits.bits;
    const castle_queen_black = chess.Move.init(chess.Coordinate.e8, chess.Coordinate.c8, .castle).bits.bits;
    const castle_king_white = chess.Move.init(chess.Coordinate.e1, chess.Coordinate.g1, .castle).bits.bits;
    const castle_queen_white = chess.Move.init(chess.Coordinate.e1, chess.Coordinate.c1, .castle).bits.bits;

    const start = if (this.move_top == 0)
        0
    else
        @ptrToInt(this.move_slices[this.move_top - 1].ptr) - @ptrToInt(&this.move_slice_buffer[0]) + this.move_slices[this.move_top - 1].len;
    var stream = std.io.fixedBufferStream(this.move_slice_buffer[start..]);
    var writer = stream.writer();

    if (move.move.bits.bits == chess.Move.invalid.bits.bits) {
        try writer.writeAll("pass");
    } else if (move.move.bits.bits == castle_king_black or move.move.bits.bits == castle_king_white) {
        try writer.writeAll("O-O");
    } else if (move.move.bits.bits == castle_queen_black or move.move.bits.bits == castle_queen_white) {
        try writer.writeAll("O-O-O");
    } else {
        const piece = if (move.move.promotion()) |_|
            chess.Piece.init(.pawn, this.position.side_to_move.opponent())
        else
            this.position.at(move.move.dest());
        const captured = this.position.meta.capturedPiece();

        if (piece.class().? != .pawn)
            try writer.writeByte(piece.character());

        // TODO: disamiguation, issue #4

        if (!captured.isEmpty())
            try writer.writeByte('x');
        try writer.print("{s}", .{move.move.dest().toString()});

        if (move.move.promotion()) |class| {
            try writer.writeByte('=');
            try writer.writeByte(class.character());
        }

        switch (move.tag) {
            .ok_check => try writer.writeByte('+'),
            .ok_mate => try writer.writeAll("\\#"),
            .ok_stalemate => try writer.writeAll(" (1/2)"),
            .ok_repitition => try writer.writeAll(" (1/2)"),
            .ok_fifty_move_rule => try writer.writeAll(" (1/2)"),
            .ok_insufficient_material => try writer.writeAll(" (1/2)"),
            else => {},
        }
    }

    this.move_slices[this.move_top] = this.move_slice_buffer[start .. start + stream.pos];
}

fn cmdExit(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.should_exit = true;
    if (this.play_mode == .network_multiplayer)
        _ = this.sock.?.send(std.mem.toBytes(chess.Move.invalid)[0..]) catch {};
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
    this.move_top = 0;
    this.move_count = 0;
    return this.confirmationStatus();
}

fn cmdClear(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.position = chess.Position.initEmpty();
    this.win_state = .ongoing;
    this.move_top = 0;
    this.move_count = 0;
    return this.confirmationStatus();
}

fn cmdPass(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.position.swapSideToMove();
    this.addMove(.{
        .move = chess.Move.invalid,
        .prev_meta = this.position.meta,
        .tag = .ok,
    }) catch unreachable;
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

fn cmdUndo(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    if (this.move_top == 0)
        return "#bred no moves left";
    this.move_top -= 1;
    const prev_move = this.move_history[this.move_top];
    if (prev_move.move.bits.bits == chess.Move.invalid.bits.bits)
        this.position.swapSideToMove()
    else if (prev_move.move.source().eql(prev_move.move.dest())) {
        this.position.undoSpawn(prev_move.move.dest(), prev_move.prev_meta, null);
    } else this.position.undoMove(prev_move.move, prev_move.prev_meta, null);
    return this.confirmationStatus();
}

fn cmdRedo(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    if (this.move_top == this.move_count)
        return "#bred no moves left";
    const move = this.move_history[this.move_top];
    if (move.move.bits.bits == chess.Move.invalid.bits.bits)
        this.position.swapSideToMove()
    else if (move.move.source().eql(move.move.dest())) {
        const class: chess.Class = switch (this.move_slices[this.move_top][0]) {
            'Q' => .queen,
            'K' => .king,
            'R' => .rook,
            'B' => .bishop,
            'N' => .knight,
            else => .pawn,
        };
        _ = this.position.spawn(class, move.move.source());
    } else this.position.doMove(move.move);
    this.move_top += 1;
    return this.confirmationStatus();
}

fn cmdRights(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    var i: usize = 0;

    if (this.position.meta.castleKing(.white)) {
        this.status_buffer[i] = 'K';
        i += 1;
    }
    if (this.position.meta.castleKing(.black)) {
        this.status_buffer[i] = 'k';
        i += 1;
    }
    if (this.position.meta.castleQueen(.white)) {
        this.status_buffer[i] = 'Q';
        i += 1;
    }
    if (this.position.meta.castleQueen(.black)) {
        this.status_buffer[i] = 'q';
        i += 1;
    }
    return this.status_buffer[0..i];
}

fn cmdLoad(this: *Frontend, args: *ArgIterator) []const u8 {
    const fen = args.rest() orelse return "#bred expected fen string";
    this.position = chess.fen.parse(fen) catch return "#bred failed to parse fen";
    return this.confirmationStatus();
}

fn cmdFen(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    var stream = std.io.fixedBufferStream(&this.status_buffer);
    var writer = stream.writer();
    chess.fen.writePosition(writer, this.position) catch return "#bred write error";
    this.no_wrap = true;
    return this.status_buffer[0..stream.pos];
}

fn cmdFlip(this: *Frontend, args: *ArgIterator) []const u8 {
    _ = args;
    this.player_affiliation = this.player_affiliation.opponent();
    return this.confirmationStatus();
}

/// return list of commands, overwrite status_buffer
fn commandListStatus(this: *Frontend) []const u8 {
    var stream = std.io.fixedBufferStream(&this.status_buffer);
    var writer = stream.writer();
    cmds: for (commands.kvs[0..]) |kv| {

        // determine if this command is in scope
        scopes: for (kv.value.scopes) |scope| {
            if (scope == this.play_mode) break :scopes;
        } else continue :cmds;

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

fn statusFromMoveResult(this: *Frontend, move_result: chess.Move.Result.Tag, input: []const u8) []const u8 {
    return switch (move_result) {
        .ok => this.confirmationStatus(),
        .ok_en_passant => "#bgrn En Passant!",
        .ok_check => "#bgrn check!",
        .ok_mate => this.winStatus(),
        .ok_stalemate => blk: {
            this.win_state = .draw;
            break :blk "#yel draw by stalemate";
        },
        .ok_repitition => blk: {
            this.win_state = .draw;
            break :blk "#yel draw by repitition";
        },
        .ok_insufficient_material => blk: {
            this.win_state = .draw;
            break :blk "#yel draw by insufficient material";
        },
        .ok_fifty_move_rule => blk: {
            this.win_state = .draw;
            break :blk "#yel draw by fifty move rule";
        },
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

fn wasSuccessfulMove(move_result: chess.Move.Result.Tag) bool {
    return switch (move_result) {
        .ok,
        .ok_en_passant,
        .ok_check,
        .ok_mate,
        .ok_stalemate,
        .ok_repitition,
        .ok_insufficient_material,
        .ok_fifty_move_rule,
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

fn spawnPiece(this: *Frontend, expr: []const u8) ?chess.Move.Result.Tag {
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

    if (coord.getRank() == this.position.side_to_move.opponent().backRank() and class == .pawn)
        return null;

    const meta = this.position.meta;
    var tag = this.position.spawn(class, coord);
    if (this.play_mode == .development and tag == .ok_insufficient_material)
        tag = if (this.position.inCheck(this.position.side_to_move)) .ok_check else .ok;

    this.addMove(.{
        .move = chess.Move.init(coord, coord, .none),
        .prev_meta = meta,
        .tag = .ok,
    }) catch unreachable;

    return tag;
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

    /// return the next arg in the string
    /// args are delimited by spaces
    /// redundant spaces are ignored
    /// args my be surrounded in quotes to include spaces
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
        this.i = at;
        while (this.i < this.str.len and this.str[this.i] != end_char)
            this.i += 1;
        return this.str[at..this.i];
    }

    /// return the remaining test in the string
    pub fn rest(this: *ArgIterator) ?[]const u8 {
        if (this.str.len == 0) return null;
        while (this.i < this.str.len and this.str[this.i] == ' ')
            this.i += 1;
        if (this.i >= this.str.len) return null;
        defer this.i = this.str.len;
        return this.str[this.i..];
    }
};

const status_max_width = 30;
const all_scopes = &[_]PlayMode{ .pass_and_play, .ai_opponent, .network_multiplayer, .development };

const commands = std.ComptimeStringMap(Command, .{
    .{ "/exit", .{
        .impl = cmdExit,
        .help = "quit the game, no saving",
        .scopes = all_scopes,
    } },
    .{ "/help", .{
        .impl = cmdHelp,
        .help = "args: [CMD] ; print a list of available commands, or info on a specific command [CMD]",
        .scopes = all_scopes,
    } },
    .{ "/reset", .{
        .impl = cmdReset,
        .help = "reset the board for a new game",
        .scopes = &[_]PlayMode{ .pass_and_play, .ai_opponent, .development },
    } },
    .{ "/flip", .{
        .impl = cmdFlip,
        .help = "flip the board perspective",
        .scopes = &[_]PlayMode{ .pass_and_play, .development },
    } },
    .{ "/load", .{
        .impl = cmdLoad,
        .help = "args: <FEN> ; load a position from the fen string <FEN>",
        .scopes = &[_]PlayMode{ .pass_and_play, .ai_opponent, .development },
    } },
    .{ "/fen", .{
        .impl = cmdFen,
        .help = "displays the cuurren position as a fen string",
        .scopes = all_scopes,
    } },

    .{ "/clear", .{
        .impl = cmdClear,
        .help = "clear all pieces from the board except kings",
        .scopes = &[_]PlayMode{.development},
    } },
    .{ "/pass", .{
        .impl = cmdPass,
        .help = "pass the current turn without making a move",
        .scopes = &[_]PlayMode{.development},
    } },
    .{ "/spawn", .{
        .impl = cmdSpawn,
        .help = "args: <EX> ; spawn a piece for the current affiliation at a given coord, eg. Rh8 or e3",
        .scopes = &[_]PlayMode{.development},
    } },
    .{ "/undo", .{
        .impl = cmdUndo,
        .help = "undo the last played move",
        .scopes = &[_]PlayMode{.development},
    } },
    .{ "/redo", .{
        .impl = cmdRedo,
        .help = "redo a previously undone move",
        .scopes = &[_]PlayMode{.development},
    } },
});
